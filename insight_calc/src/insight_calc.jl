"""
    InsightCalc

HTTP microservice that receives segmentation results, runs D4M.jl analytics,
and integrates with GCP/BigQuery.  Acts as both an HTTP server (Oxygen.jl)
and an HTTP client (HTTP.jl) to communicate with sibling microservices.
"""
module InsightCalc

const PROJECT_ROOT = dirname(@__DIR__) 
const DATA_DIR = joinpath(PROJECT_ROOT, "data")

using Dates
using Logging
using JSON3
using HTTP
using Oxygen
using GoogleCloud

# ── Optional: uncomment once D4M.jl is registered via Pkg.develop ────────────
# using D4M
# -----------------------------------------------------------------------------

export start_server, stop_server, init_bq_client

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

const START_TIME = Ref{DateTime}(now())

# Holds the initialised GCP session; populated by init_bq_client().
const BQ_SESSION = Ref{Union{Nothing, GoogleCloud.GoogleSession}}(nothing)

# Holds the Oxygen server task when running in async mode.
const SERVER_TASK = Ref{Union{Nothing, Task}}(nothing)

# ---------------------------------------------------------------------------
# GCP / BigQuery
# ---------------------------------------------------------------------------

"""
    init_bq_client(key_path::String) -> GoogleCloud.GoogleSession

Initialise a GCP session from a service-account JSON key file and store it
in the module-level `BQ_SESSION` ref.  Call this before any BigQuery work.

# Example
```julia
InsightCalc.init_bq_client("/secrets/gcp-sa-key.json")
```
"""
function init_bq_client(key_path::String)::GoogleCloud.GoogleSession
    @info "Initialising GCP session" key_path
    creds   = GoogleCloud.JSONCredentials(key_path)
    session = GoogleCloud.GoogleSession(creds, ["https://www.googleapis.com/auth/bigquery"])
    BQ_SESSION[] = session
    @info "GCP session ready"
    return session
end

"""
    bq_session() -> GoogleCloud.GoogleSession

Return the active BQ session, raising an error if it has not been initialised.
"""
function bq_session()::GoogleCloud.GoogleSession
    isnothing(BQ_SESSION[]) && error("BQ session not initialised — call init_bq_client() first")
    return BQ_SESSION[]
end

# ---------------------------------------------------------------------------
# HTTP client helpers (calling sibling microservices)
# ---------------------------------------------------------------------------

"""
    post_json(url::String, body) -> JSON3.Object

POST `body` (serialised to JSON) to `url` and return the parsed response.
Throws on non-2xx status.
"""
function post_json(url::String, body)
    payload  = JSON3.write(body)
    headers  = ["Content-Type" => "application/json", "Accept" => "application/json"]
    response = HTTP.post(url, headers, payload)
    return JSON3.read(response.body)
end

"""
    get_json(url::String; headers = []) -> JSON3.Object

GET `url` and return the parsed JSON response.
"""
function get_json(url::String; headers = [])
    response = HTTP.get(url, ["Accept" => "application/json", headers...])
    return JSON3.read(response.body)
end

# ---------------------------------------------------------------------------
# Analytics stubs (D4M integration point)
# ---------------------------------------------------------------------------

"""
    analyse_segments(segments) -> Dict

Placeholder for D4M.jl analytics over SAM segmentation results.
Replace the body with real D4M triple-store operations once D4M is loaded.
"""
function analyse_segments(segments)
    # TODO: convert `segments` to a D4M.Assoc and run analytics
    # Example (once `using D4M` is active):
    #   A = D4M.Assoc(row_keys, col_keys, values)
    #   result = D4M.sum(A, 1)          # column sums
    @warn "analyse_segments: D4M stub — no computation performed"
    return Dict("segment_count" => length(segments), "status" => "stub")
end

# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

"""
GET /health

Liveness probe.  Returns service name and uptime as JSON.
"""
@get "/health" function(_req::HTTP.Request)
    uptime_s = round(Int, (now() - START_TIME[]).value / 1_000)
    return json(Dict(
        "status"  => "ok",
        "service" => "insight_calc",
        "uptime"  => "$(uptime_s)s",
    ))
end

"""
POST /analyse

Receive a JSON body of SAM segmentation results from the Python microservice
and run D4M analytics.  Expected body: `{"video_id": "...", "segments": [...]}`.
"""
@post "/analyse" function(req::HTTP.Request)
    body = JSON3.read(req.body)

    haskey(body, :video_id)  || return json(Dict("error" => "missing video_id"),  status=400)
    haskey(body, :segments)  || return json(Dict("error" => "missing segments"),   status=400)

    result = analyse_segments(body.segments)

    return json(Dict(
        "video_id" => body.video_id,
        "result"   => result,
    ))
end

# ---------------------------------------------------------------------------
# Server lifecycle
# ---------------------------------------------------------------------------

"""
    start_server(; host="0.0.0.0", port=8080, async=true)

Start the Oxygen HTTP server.  When `async=true` (default) the server runs in
a background task and the call returns immediately, which is required for
embedding inside a larger Julia process.  When `async=false` the call blocks.

Multi-threading: set `JULIA_NUM_THREADS` before launching Julia to allow
Oxygen to dispatch handlers on the thread pool.
"""
function start_server(; host::String = "0.0.0.0", port::Int = 8080, async::Bool = true)
    START_TIME[] = now()
    @info "Starting InsightCalc server" host port async

    if async
        SERVER_TASK[] = @async Oxygen.serveasync(; host, port, verbose=false)
        @info "InsightCalc server running (async)" host port
        return SERVER_TASK[]
    else
        Oxygen.serve(; host, port, verbose=false)
    end
end

"""
    stop_server()

Gracefully shut down the Oxygen server if running in async mode.
"""
function stop_server()
    Oxygen.terminate()
    SERVER_TASK[] = nothing
    @info "InsightCalc server stopped"
end

end # module InsightCalc
