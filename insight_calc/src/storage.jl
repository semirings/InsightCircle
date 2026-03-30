# storage.jl — BigQuery connection, session management, and streaming query results.
# All BQ I/O lives here. No business logic.

using DotEnv
using GoogleCloud
using HTTP
using JSON3
using Logging

# ── Connection types ──────────────────────────────────────────────────────────

struct BQServer
    project :: String
    dataset :: String
    session :: GoogleCloud.GoogleSession
end

struct BQTable
    server  :: BQServer
    name    :: String
    dataset :: String
end
BQTable(srv::BQServer, name::String) = BQTable(srv, name, srv.dataset)

# ── Module-level singletons ───────────────────────────────────────────────────
const PROJECT_ROOT = abspath(joinpath(@__DIR__, "../.."))
const ENV_PATH = joinpath(PROJECT_ROOT, ".env")            
@info "ENV_PATH==$ENV_PATH"
const BQ_PROJECT = get(ENV, "BQ_PROJECT", "")
const BQ_DATASET = get(ENV, "BQ_DATASET", "insight_metadata")

const _SERVER = Ref{Union{Nothing, BQServer}}(nothing)

function dbSetup(projectId::String, dataset::String)::BQServer
    keyPath = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    isempty(keyPath) && error("Set GOOGLE_APPLICATION_CREDENTIALS environment variable")
    creds   = GoogleCloud.JSONCredentials(keyPath)
    session = GoogleCloud.GoogleSession(creds, ["https://www.googleapis.com/auth/bigquery"])
    return BQServer(projectId, dataset, session)
end

function getServer()::BQServer
    if isnothing(_SERVER[])

        if isfile(ENV_PATH)
            DotEnv.load!(ENV_PATH)
        else
            @warn ".env not found at $ENV_PATH. Using system ENV."
        end
        
        if isempty(BQ_PROJECT)
            @error "Environment variables missing" path=pwd()
            error("Set BQ_PROJECT in .env")
        end
        
        # Initialize the actual connection object
        _SERVER[] = dbSetup(BQ_PROJECT, BQ_DATASET)
    end
    return _SERVER[]
end

# ── REST helpers ──────────────────────────────────────────────────────────────

const _BQ_BASE = "https://bigquery.googleapis.com/bigquery/v2"

function _authHeaders(session::GoogleCloud.GoogleSession)
    # 1. FORCE AUTHORIZATION: If the dict is empty, trigger a refresh
    if isempty(session.authorization)
        @info "Session is unauthorized. Fetching new token..."
        GoogleCloud.authorize(session)
    end

    auth_dict = session.authorization
    
    # 2. Extract the token (usually :token or :access_token)
    token = get(auth_dict, :token, get(auth_dict, :access_token, ""))
    
    if token == ""
        # Last-ditch: maybe it's a string key?
        token = get(auth_dict, "access_token", "")
    end

    if token == ""
        error("Authorization succeeded but no token was returned. Keys: $(keys(auth_dict))")
    end
    
    return ["Authorization" => "Bearer $token", "Content-Type" => "application/json"]
end

# ── Table operations ──────────────────────────────────────────────────────────

function listTables()::Vector{String}
    srv  = getServer()
    url  = "$_BQ_BASE/projects/$(srv.project)/datasets/$(srv.dataset)/tables"
    
    # The header function will now handle the 0-entry Dict problem
    resp = HTTP.get(url, _authHeaders(srv.session))
    
    payload = JSON3.read(resp.body)
    tables  = get(payload, :tables, [])
    return [String(t.tableReference.tableId) for t in tables]
end

function createMetadataTable(tableName::String)::Bool
    srv  = getServer()
    url  = "$_BQ_BASE/projects/$(srv.project)/datasets/$(srv.dataset)/tables"
    body = JSON3.write(Dict(
        "tableReference" => Dict(
            "projectId" => srv.project,
            "datasetId" => srv.dataset,
            "tableId"   => tableName,
        )
    ))
    try
        HTTP.post(url, _authHeaders(srv.session), body)
        @info "Table created" tableName
        return true
    catch e
        @error "createMetadataTable failed" tableName e
        return false
    end
end

function insertVideoMetadata(tableName::String, videoData::Dict)::Bool
    srv = getServer()
    url = "$_BQ_BASE/projects/$(srv.project)/datasets/$(srv.dataset)/tables/$tableName/insertAll"
    row = Dict{String,Any}("id" => videoData["id"])
    for (k, v) in get(videoData, "snippet", Dict())
        row["meta_$k"] = string(v)
    end
    body = JSON3.write(Dict("rows" => [Dict("json" => row)]))
    try
        HTTP.post(url, _authHeaders(srv.session), body)
        return true
    catch e
        @error "insertVideoMetadata failed" tableName e
        return false
    end
end

# ── Paginated streaming: bqToMap / BQChunk ────────────────────────────────────

"""
Wraps an Assoc with BigQuery pagination state.
Call `chunk[]` to fetch the next page; returns `nothing` when exhausted.
"""
struct BQChunk
    assoc     :: Assoc
    jobId     :: String
    pageToken :: Union{String, Nothing}
    chunkSize :: Int
    projectId :: String
    session   :: GoogleCloud.GoogleSession
end

Base.getindex(chunk::BQChunk, i, j) = chunk.assoc[i, j]
Base.getindex(chunk::BQChunk, i)    = chunk.assoc[i]

function Base.getindex(chunk::BQChunk)
    if isnothing(chunk.pageToken)
        @debug "[BQChunk[]] exhausted" jobId=chunk.jobId
        return nothing
    end
    @debug "[BQChunk[]] next page" jobId=chunk.jobId pageToken=chunk.pageToken
    return _fetchPage(chunk.session, chunk.projectId, chunk.jobId,
                      chunk.pageToken, chunk.chunkSize)
end

"""
    bqToMap(sqlClause; chunkSize=10000) -> BQChunk

Execute `sqlClause` in us-central1 and return the first chunk as a BQChunk.
Mapping: rows=video_id, cols=timestamp, vals=metric_value.
"""
function bqToMap(sqlClause::String; queryParameters::Vector=[], chunkSize::Int = 10_000)::BQChunk
    srv   = getServer()
    jobId = _submitJob(srv.session, srv.project, sqlClause; queryParameters)
    @debug "[bqToMap] job submitted" jobId
    return _fetchPage(srv.session, srv.project, jobId, nothing, chunkSize)
end

function _submitJob(session::GoogleCloud.GoogleSession, projectId::String,
                    sqlClause::String; queryParameters::Vector=[])::String
    url  = "$_BQ_BASE/projects/$projectId/jobs"
    query_config = Dict{String,Any}(
        "query"        => sqlClause,
        "useLegacySql" => false,
        "location"     => "us-central1",
    )
    if !isempty(queryParameters)
        query_config["parameterMode"]   = "NAMED"
        query_config["queryParameters"] = queryParameters
    end
    body = JSON3.write(Dict(
        "configuration" => Dict(
            "query" => query_config,
        )
    ))
    resp  = HTTP.post(url, _authHeaders(session), body)
    jobId = String(JSON3.read(resp.body).jobReference.jobId)
    @debug "[_submitJob]" jobId
    _waitForJob(session, projectId, jobId)
    return jobId
end

function _waitForJob(session::GoogleCloud.GoogleSession, projectId::String,
                     jobId::String)
    url = "$_BQ_BASE/projects/$projectId/jobs/$jobId?location=us-central1"
    while true
        state = String(JSON3.read(HTTP.get(url, _authHeaders(session)).body).status.state)
        @debug "[_waitForJob]" jobId state
        state == "DONE" && break
        sleep(1)
    end
end

function _fetchPage(session::GoogleCloud.GoogleSession, projectId::String,
                    jobId::String, pageToken::Union{String,Nothing},
                    chunkSize::Int)::BQChunk
    url = "$_BQ_BASE/projects/$projectId/queries/$jobId?maxResults=$chunkSize&location=us-central1"
    isnothing(pageToken) || (url *= "&pageToken=$pageToken")

    payload   = JSON3.read(HTTP.get(url, _authHeaders(session)).body)
    rows      = get(payload, :rows, [])
    nextToken = let t = get(payload, :pageToken, nothing)
        isnothing(t) ? nothing : String(t)
    end

    @debug "[_fetchPage]" jobId nRows=length(rows) hasNext=!isnothing(nextToken)
    assoc = _rowsToAssoc(rows, payload.schema.fields)
    return BQChunk(assoc, jobId, nextToken, chunkSize, projectId, session)
end

function _rowsToAssoc(rows, fields)::Assoc
    fieldNames   = [String(f.name) for f in fields]
    videoIdIdx   = findfirst(==("video_id"),     fieldNames)
    timestampIdx = findfirst(==("timestamp"),    fieldNames)
    metricIdx    = findfirst(==("metric_value"), fieldNames)
    return _rowsToAssocEAV(rows, fieldNames, fieldNames[videoIdIdx],
                           _fixedColAssoc=true,
                           colIdx=timestampIdx, valIdx=metricIdx)
end

"""
    rowsToAssoc(payload, rowKeyCol) -> Assoc

Convert a raw BQ query payload to an EAV Assoc.
- rowKeyCol: name of the column to use as the Assoc row key
- All other columns become (rowKey, colName) → value triples.
"""
function rowsToAssoc(payload, rowKeyCol::String)::Assoc
    fieldNames = [String(f.name) for f in payload.schema.fields]
    return _rowsToAssocEAV(payload.rows, fieldNames, rowKeyCol)
end

function _rowsToAssocEAV(rows, fieldNames::Vector{String}, rowKeyCol::String;
                          _fixedColAssoc::Bool=false,
                          colIdx::Union{Int,Nothing}=nothing,
                          valIdx::Union{Int,Nothing}=nothing)::Assoc
    rowKeyIdx = findfirst(==(rowKeyCol), fieldNames)
    isnothing(rowKeyIdx) && error("Column '$rowKeyCol' not found in fields: $fieldNames")

    rowKeys = String[]
    colKeys = String[]
    vals    = String[]

    for row in rows
        cells  = row.f
        rowKey = isnothing(cells[rowKeyIdx].v) ? "" : String(cells[rowKeyIdx].v)
        if _fixedColAssoc
            # Legacy: single (rowKey, timestamp) → metric_value triple per row
            push!(rowKeys, rowKey)
            push!(colKeys, isnothing(cells[colIdx].v) ? "" : String(cells[colIdx].v))
            push!(vals,    isnothing(cells[valIdx].v) ? "" : String(cells[valIdx].v))
        else
            # EAV: one triple per cell
            for (col, cell) in zip(fieldNames, cells)
                push!(rowKeys, rowKey)
                push!(colKeys, col)
                push!(vals,    isnothing(cell.v) ? "" : String(cell.v))
            end
        end
        @debug "[_rowsToAssocEAV]" rowKey
    end

    isempty(rowKeys) && return Assoc(String[], String[], String[])
    return Assoc(rowKeys, colKeys, vals)
end
