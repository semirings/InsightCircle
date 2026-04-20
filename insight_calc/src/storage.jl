# storage.jl — BigQuery connection, session management, and streaming query results.
# All BQ I/O lives here. No business logic.

using DotEnv
using GoogleCloud
using HTTP
using JSON3
using Logging

# ── Auth abstraction ─────────────────────────────────────────────────────────
#
# GoogleCloud.jl v0.11.0 MetadataCredentials uses HTTP.get(url, headers=h)
# where `headers` is a positional arg in HTTP.jl v1.x, so the keyword form
# silently drops into kwargs and the Metadata-Flavor header is never sent,
# causing a 403 / CredentialError. Bypass it entirely for Cloud Run: fetch
# the token directly from the well-known metadata endpoint.

struct CloudRunSession end   # marker — no fields, no GoogleCloud dependency

const BQSession = Union{CloudRunSession, GoogleCloud.GoogleSession}

const _TOKEN_CACHE = Ref{Tuple{String, Float64}}(("", 0.0))

function _fetchMetadataToken()::String
    tok, exp = _TOKEN_CACHE[]
    time() < exp && return tok
    resp = HTTP.get(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        ["Metadata-Flavor" => "Google"],
    )
    data = JSON3.read(resp.body)
    tok  = String(data.access_token)
    exp  = time() + Float64(get(data, :expires_in, 3600)) - 60.0
    _TOKEN_CACHE[] = (tok, exp)
    return tok
end

# ── Connection types ──────────────────────────────────────────────────────────

struct BQServer
    project :: String
    dataset :: String
    session :: BQSession
end

struct BQTable
    server      :: BQServer
    name        :: String
    dataset     :: String
    row_key_col :: String        # column treated as the Assoc row key
end
BQTable(srv::BQServer, name::String) = BQTable(srv, name, srv.dataset, "id")
BQTable(srv::BQServer, name::String, row_key_col::String) = BQTable(srv, name, srv.dataset, row_key_col)

# ── Module-level singletons ───────────────────────────────────────────────────
const PROJECT_ROOT = abspath(joinpath(@__DIR__, "../.."))

const _SERVER = Ref{Union{Nothing, BQServer}}(nothing)

function dbSetup(projectId::String, dataset::String)::BQServer
    keyPath = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    session = if isempty(keyPath)
        @info "No GOOGLE_APPLICATION_CREDENTIALS set; using Cloud Run metadata server"
        CloudRunSession()
    else
        creds = GoogleCloud.JSONCredentials(keyPath)
        GoogleCloud.GoogleSession(creds, ["https://www.googleapis.com/auth/bigquery"])
    end
    return BQServer(projectId, dataset, session)
end

function getServer()::BQServer
    if isnothing(_SERVER[])
        bq_project = get(ENV, "BQ_PROJECT", "")
        bq_dataset = get(ENV, "BQ_DATASET", "insight_metadata")

        if isempty(bq_project)
            error("BQ_PROJECT environment variable is not set")
        end

        _SERVER[] = dbSetup(bq_project, bq_dataset)
    end
    return _SERVER[]
end

# ── REST helpers ──────────────────────────────────────────────────────────────

const _BQ_BASE = "https://bigquery.googleapis.com/bigquery/v2"

function _authHeaders(session::BQSession)
    token = if session isa CloudRunSession
        _fetchMetadataToken()
    else
        isempty(session.authorization) && GoogleCloud.authorize(session)
        auth_dict = session.authorization
        tok = get(auth_dict, :token, get(auth_dict, :access_token, ""))
        tok == "" && (tok = get(auth_dict, "access_token", ""))
        tok == "" && error("No token in authorization dict. Keys: $(keys(auth_dict))")
        tok
    end
    return ["Authorization" => "Bearer $token", "Content-Type" => "application/json"]
end

# ── BQTable getindex — D4M-style table access ────────────────────────────────
#
# Usage (mirrors D4M HAZoo syntax):
#   T = BQTable(getServer(), "yt_metadata", "id")
#   T["vid123,vid456:", ":"]          # two specific rows, all cols
#   T[":", "views,likes,"]            # all rows, two cols
#   T["a..z:", ":"]                   # row range
#   T["deep*", ":"]                   # prefix match on rows
#
# Row filter → pushed down to BQ SQL (efficient).
# Col filter → applied in-memory on the returned Assoc (EAV cols are field names).

function Base.getindex(t::BQTable, row_query::String, col_query::String)::Assoc
    srv = t.server
    bqr = generateBqParams(_parse(row_query * col_query))

    row_filter = replace(bqr.row_clause, "row_key" => t.row_key_col)

    sql = """
        SELECT *
        FROM `$(srv.project).$(t.dataset).$(t.name)`
        WHERE $row_filter
    """

    jobId   = _submitJob(srv.session, srv.project, sql;
                         queryParameters=toApiParams(bqr.params))
    url     = "$_BQ_BASE/projects/$(srv.project)/queries/$jobId?maxResults=10000&location=us-central1"
    payload = JSON3.read(HTTP.get(url, _authHeaders(srv.session)).body)
    aa      = rowsToAssoc(payload, t.row_key_col)

    # Apply col filter in-memory unless it is the wildcard
    col_query == ":" && return aa
    return applyD4mMath(_parse(":" * col_query), aa)
end

# Convenience: T["vid123:"] — row only, all cols
Base.getindex(t::BQTable, row_query::String) = t[row_query, ":"]

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
    session   :: BQSession
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

function _submitJob(session::BQSession, projectId::String,
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

function _waitForJob(session::BQSession, projectId::String,
                     jobId::String)
    url = "$_BQ_BASE/projects/$projectId/jobs/$jobId?location=us-central1"
    while true
        state = String(JSON3.read(HTTP.get(url, _authHeaders(session)).body).status.state)
        @debug "[_waitForJob]" jobId state
        state == "DONE" && break
        sleep(1)
    end
end

function _fetchPage(session::BQSession, projectId::String,
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
            # EAV: one triple per cell, skip the row key column and null/empty values
            for (col, cell) in zip(fieldNames, cells)
                col == rowKeyCol && continue
                isnothing(cell.v) && continue
                cell.v isa JSON3.Array && continue   # skip array-typed columns
                v = String(cell.v)
                isempty(v) && continue
                push!(rowKeys, rowKey)
                push!(colKeys, col)
                push!(vals,    v)
            end
        end
        @debug "[_rowsToAssocEAV]" rowKey
    end

    isempty(rowKeys) && return Assoc(String[], String[], String[])
    return Assoc(rowKeys, colKeys, vals)
end

# ── yt_metadata query ─────────────────────────────────────────────────────────

"""
    queryYtMetadata(d4mQuery; chunkSize=10_000) -> Assoc

Parse a D4M query string and return an incidence Assoc over yt_metadata.
Rows = video id, cols = field/query_term, vals = cell value or "1".

Examples:
    queryYtMetadata(":")                 # all videos
    queryYtMetadata("vid123,vid456:")    # two specific videos
    queryYtMetadata(":deep learning")   # one query term
"""
function queryYtMetadata(d4mQuery::String; chunkSize::Int=10_000)::Assoc
    r          = scan(d4mQuery, BigQueryTarget)
    row_filter = replace(r.row_clause, "row_key" => "id")
    srv        = getServer()

    sql = """
        SELECT *
        FROM `$(srv.project).$(srv.dataset).yt_metadata`
        WHERE $row_filter
    """
    jobId   = _submitJob(srv.session, srv.project, sql;
                         queryParameters=toApiParams(r.params))
    url     = "$_BQ_BASE/projects/$(srv.project)/queries/$jobId?maxResults=$chunkSize&location=us-central1"
    payload = JSON3.read(HTTP.get(url, _authHeaders(srv.session)).body)
    return rowsToAssoc(payload, "id")
end
