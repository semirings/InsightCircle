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

export bqToMap, BQChunk, BQTable, BQServer, getServer, scan, BQResult, BQParam, toApiParams, queryYtMetadata, queryTable, queryTableChunk, ICTable, getTable, aa2df, queryVideo, publishCompletion

const START_TIME = Ref{DateTime}(now())

# ── Completion middleware ─────────────────────────────────────────────────────
#
# Fires publishCompletion for every POST request automatically.
# Row count is extracted from the response body when a "rows" key is present.
# Error status is published when the handler throws instead of returning.

function _completionMiddleware(handle)
    function(req::HTTP.Request)
        req.method == "POST" || return handle(req)

        script = first(split(lstrip(req.target, '/'), '?'))
        t0     = now()

        local resp
        try
            resp = handle(req)
        catch err
            elapsed = round(Int, (now() - t0).value)
            publishCompletion(script, "error";
                duration_ms = elapsed,
                detail      = string(err))
            rethrow()
        end

        elapsed   = round(Int, (now() - t0).value)
        row_count = 0
        try
            parsed = JSON3.read(resp.body)
            haskey(parsed, :rows) && (row_count = length(parsed.rows))
        catch
        end
        publishCompletion(script, "ok"; row_count, duration_ms=elapsed)
        return resp
    end
end

# ── Routes ────────────────────────────────────────────────────────────────────

@get "/health" function(::HTTP.Request)
    uptimeS = round(Int, (now() - START_TIME[]).value / 1_000)
    return json(Dict(
        "status"  => "ok",
        "service" => "insight_calc",
        "uptime"  => "$(uptimeS)s",
    ))
end

@get "/tables" function(::HTTP.Request)
    tables = listTables()
    return json(Dict("tables" => tables, "count" => length(tables)))
end

@post "/query/yt_metadata" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :query) || return json(Dict("error" => "missing query"), status=400)
    aa = queryYtMetadata(string(body.query))
    rows, cols, vals = find(aa)
    return json(Dict("rows" => rows, "cols" => cols, "vals" => vals))
end

@post "/query" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :table) || return json(Dict("error" => "missing table"), status=400)
    haskey(body, :query) || return json(Dict("error" => "missing query"), status=400)
    tableName = string(body.table)
    d4mQuery  = string(body.query)
    rowKeyCol = haskey(body, :row_key)    ? string(body.row_key)  : "id"
    chunkSize = haskey(body, :chunk_size) ? Int(body.chunk_size)  : 10_000
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

# ── Script registry routes ────────────────────────────────────────────────────

@get "/scripts" function(::HTTP.Request)
    scripts = getRegistry()
    return json(Dict(
        "scripts" => [Dict("name" => s.name, "description" => s.description)
                      for s in scripts],
        "count"   => length(scripts),
    ))
end

@post "/script/:name" function(req::HTTP.Request, name::String)
    scripts = getRegistry()
    idx = findfirst(s -> s.name == name, scripts)
    isnothing(idx) && return json(Dict("error" => "script '$name' not found"), status=404)
    s   = scripts[idx]
    srv = getServer()
    jobId   = _submitJob(srv.session, srv.project, s.query)
    url     = "$_BQ_BASE/projects/$(srv.project)/queries/$jobId?maxResults=10000&location=us-central1"
    payload = JSON3.read(HTTP.get(url, _authHeaders(srv.session)).body)
    aa      = rowsToAssoc(payload, s.row_key)
    rs, cs, vs = find(aa)
    return json(Dict("rows" => rs, "cols" => cs, "vals" => vs, "script" => name))
end

@post "/scripts/reload" function(::HTTP.Request)
    scripts = loadRegistry!()
    return json(Dict("status" => "ok", "count" => length(scripts)))
end

function main()
    loadRegistry!()
    Oxygen.serve(host="0.0.0.0", port=parse(Int, get(ENV, "PORT", "8080")),
                 middleware=[_completionMiddleware])
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module InsightCalc
