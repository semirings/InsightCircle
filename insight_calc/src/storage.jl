# storage.jl — BigQuery connection, session management, and streaming query results.
# All BQ I/O lives here. No business logic.

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

const BQ_PROJECT = get(ENV, "BQ_PROJECT", "")
const BQ_DATASET = get(ENV, "BQ_DATASET", "insight_metadata")

const _SERVER = Ref{Union{Nothing, BQServer}}(nothing)

function dbsetup(projectId::String, dataset::String)::BQServer
    keyPath = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    isempty(keyPath) && error("Set GOOGLE_APPLICATION_CREDENTIALS environment variable")
    creds   = GoogleCloud.JSONCredentials(keyPath)
    session = GoogleCloud.GoogleSession(creds, ["https://www.googleapis.com/auth/bigquery"])
    return BQServer(projectId, dataset, session)
end

function getServer()::BQServer
    if isnothing(_SERVER[])
        isempty(BQ_PROJECT) && error("Set BQ_PROJECT environment variable")
        _SERVER[] = dbsetup(BQ_PROJECT, BQ_DATASET)
    end
    return _SERVER[]
end

# ── REST helpers ──────────────────────────────────────────────────────────────

const _BQ_BASE = "https://bigquery.googleapis.com/bigquery/v2"

function _authHeaders(session::GoogleCloud.GoogleSession)
    token = session.oauth.access_token
    return ["Authorization" => "Bearer $token", "Content-Type" => "application/json"]
end

# ── Table operations ──────────────────────────────────────────────────────────

function listTables()::Vector{String}
    srv  = getServer()
    url  = "$_BQ_BASE/projects/$(srv.project)/datasets/$(srv.dataset)/tables"
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
function bqToMap(sqlClause::String; chunkSize::Int = 10_000)::BQChunk
    srv   = getServer()
    jobId = _submitJob(srv.session, srv.project, sqlClause)
    @debug "[bqToMap] job submitted" jobId
    return _fetchPage(srv.session, srv.project, jobId, nothing, chunkSize)
end

function _submitJob(session::GoogleCloud.GoogleSession, projectId::String,
                    sqlClause::String)::String
    url  = "$_BQ_BASE/projects/$projectId/jobs"
    body = JSON3.write(Dict(
        "configuration" => Dict(
            "query" => Dict(
                "query"        => sqlClause,
                "useLegacySql" => false,
                "location"     => "us-central1",
            )
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
    rowKeys = String[]
    colKeys = String[]
    vals    = String[]

    fieldNames   = [String(f.name) for f in fields]
    videoIdIdx   = findfirst(==("video_id"),     fieldNames)
    timestampIdx = findfirst(==("timestamp"),    fieldNames)
    metricIdx    = findfirst(==("metric_value"), fieldNames)

    for row in rows
        cells     = row.f
        videoId   = String(cells[videoIdIdx].v)
        timestamp = String(cells[timestampIdx].v)
        metricVal = String(cells[metricIdx].v)
        push!(rowKeys, videoId)
        push!(colKeys, timestamp)
        push!(vals,    metricVal)
        @debug "[_rowsToAssoc]" videoId timestamp metricVal
    end

    isempty(rowKeys) && return Assoc(String[], String[], String[])
    return Assoc(rowKeys, colKeys, vals)
end
