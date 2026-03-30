# InsightCalc — HTTP microservice for D4M analytics over BigQuery.
# This file owns: route definitions, server lifecycle, module imports.

module InsightCalc

using Dates
using Logging
using JSON3
using HTTP
using Oxygen
using GoogleCloud
using D4M

# Load order matters: storage first (defines BQ types), then algebra, then services.
include("storage.jl")
include("automata.jl")
include("algebra.jl")
include("services.jl")

export startServer, stopServer, bqToMap, BQChunk, scan, BQResult, BQParam, toApiParams

# ── Global state ──────────────────────────────────────────────────────────────

const START_TIME  = Ref{DateTime}(now())
const SERVER_TASK = Ref{Union{Nothing, Task}}(nothing)

# ── Routes ────────────────────────────────────────────────────────────────────

# GET /health — liveness probe
@get "/health" function(_req::HTTP.Request)
    uptimeS = round(Int, (now() - START_TIME[]).value / 1_000)
    return json(Dict(
        "status"  => "ok",
        "service" => "insight_calc",
        "uptime"  => "$(uptimeS)s",
    ))
end

# POST /analyse — receive SAM segmentation results, run D4M analytics
@post "/analyse" function(req::HTTP.Request)
    body = JSON3.read(req.body)
    haskey(body, :video_id) || return json(Dict("error" => "missing video_id"), status=400)
    haskey(body, :segments) || return json(Dict("error" => "missing segments"),  status=400)
    result = analyseSegments(body.segments)
    return json(Dict("video_id" => body.video_id, "result" => result))
end

# GET /tables — list BigQuery tables in the dataset
@get "/tables" function(_req::HTTP.Request)
    tables = listTables()
    return json(Dict("tables" => tables, "count" => length(tables)))
end

# POST /tables/create — create a table by name
@post "/tables/create" function(req::HTTP.Request)
    data = JSON3.read(req.body)
    haskey(data, :tableName) || return json(Dict("error" => "missing tableName"), status=400)
    if createMetadataTable(string(data.tableName))
        return json(Dict("status" => "success", "table" => data.tableName))
    else
        return json(Dict("status" => "error", "message" => "BQ table creation failed"), status=500)
    end
end

# ── Server lifecycle ──────────────────────────────────────────────────────────

function startServer(; host::String = "0.0.0.0", port::Int = 5200, async::Bool = true)
    START_TIME[] = now()
    @info "Starting InsightCalc" host port
    if async
        SERVER_TASK[] = @async Oxygen.serveasync(; host, port, verbose=false)
        @info "InsightCalc running (async)" host port
        return SERVER_TASK[]
    else
        Oxygen.serve(; host, port, verbose=false)
    end
end

function stopServer()
    Oxygen.terminate()
    SERVER_TASK[] = nothing
    @info "InsightCalc stopped"
end

startServer(host="0.0.0.0", port=5200, async=false)

end # module InsightCalc
