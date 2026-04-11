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

export bqToMap, BQChunk, BQTable, BQServer, getServer, scan, BQResult, BQParam, toApiParams, queryYtMetadata, aa2df, InsightPayload, publish, queryVideo

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

Oxygen.serve(host="0.0.0.0", port=parse(Int, get(ENV, "PORT", "8080")))

end # module InsightCalc
