# services.jl — HTTP client helpers and orchestration.
# Calls storage for data and algebra for computation. No BQ types here.

using HTTP
using JSON3

# ── HTTP client helpers ───────────────────────────────────────────────────────

function postJson(url::String, body)
    payload  = JSON3.write(body)
    headers  = ["Content-Type" => "application/json", "Accept" => "application/json"]
    response = HTTP.post(url, headers, payload)
    return JSON3.read(response.body)
end

function getJson(url::String; headers = [])
    response = HTTP.get(url, ["Accept" => "application/json", headers...])
    return JSON3.read(response.body)
end
