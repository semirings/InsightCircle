# InsightCalc — HTTP microservice for D4M analytics over BigQuery.
# Routes: ad-hoc query endpoints. Server started directly on module load.

module InsightCalc

using Dates
using Logging
using JSON3
using HTTP
using Oxygen
using GoogleCloud
using D4M

# Load order matters: storage first (defines BQ types), then algebra.
include("storage.jl")
include("automata.jl")
include("algebra.jl")
include("pubsub.jl")

export bqToMap, BQChunk, BQTable, BQServer, getServer, scan, BQResult, BQParam, toApiParams, queryYtMetadata, queryTable, queryTableChunk, ICTable, getTable, aa2df, InsightPayload, publish, queryVideo

const START_TIME = Ref{DateTime}(now())

# ── Routes ────────────────────────────────────────────────────────────────────

@get "/health" function(_req::HTTP.Request)
    uptimeS = round(Int, (now() - START_TIME[]).value / 1_000)
    return json(Dict(
        "status"  => "ok",
        "service" => "insight_calc",
        "uptime"  => "$(uptimeS)s",
    ))
end

@get "/tables" function(_req::HTTP.Request)
    tables = listTables()
    return json(Dict("tables" => tables, "count" => length(tables)))
end

@post "/query/yt_metadata" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :query) || return json(Dict("error" => "missing query"), status=400)
    aa     = queryYtMetadata(string(body.query))
    rows, cols, vals = find(aa)
    return json(Dict("rows" => rows, "cols" => cols, "vals" => vals))
end

@post "/query" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :table) || return json(Dict("error" => "missing table"), status=400)
    haskey(body, :query) || return json(Dict("error" => "missing query"), status=400)
    tableName = string(body.table)
    d4mQuery  = string(body.query)
    rowKeyCol = haskey(body, :row_key)    ? string(body.row_key)           : "id"
    chunkSize = haskey(body, :chunk_size) ? Int(body.chunk_size)           : 10_000
    aa, jobId, pageToken = queryTableChunk(tableName, d4mQuery; rowKeyCol, chunkSize)
    rows, cols, vals = find(aa)
    return json(Dict("rows" => rows, "cols" => cols, "vals" => vals,
                     "job_id" => jobId, "page_token" => pageToken))
end

@post "/query/next" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :job_id)     || return json(Dict("error" => "missing job_id"),     status=400)
    haskey(body, :page_token) || return json(Dict("error" => "missing page_token"), status=400)
    jobId     = string(body.job_id)
    pageToken = string(body.page_token)
    rowKeyCol = haskey(body, :row_key)    ? string(body.row_key)  : "id"
    chunkSize = haskey(body, :chunk_size) ? Int(body.chunk_size)  : 10_000
    srv = getServer()
    aa, nextToken = _fetchPageGeneric(srv.session, srv.project, jobId, pageToken, chunkSize, rowKeyCol)
    rows, cols, vals = find(aa)
    return json(Dict("rows" => rows, "cols" => cols, "vals" => vals,
                     "job_id" => jobId, "page_token" => nextToken))
end

function main()
    Oxygen.serve(host="0.0.0.0", port=parse(Int, get(ENV, "PORT", "8080")))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module InsightCalc
