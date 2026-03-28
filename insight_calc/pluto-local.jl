#!/usr/bin/env julia
using Pkg
Pkg.activate(@__DIR__)

# 1. Load the .env from the parent directory
const ENV_PATH = abspath(joinpath(@__DIR__, "..", ".env"))

if isfile(ENV_PATH)
    for raw_line in eachline(ENV_PATH)
        line = strip(replace(raw_line, "\r" => ""))
        if isempty(line) || startswith(line, "#") || !occursin("=", line)
            continue
        end
        key, val = split(line, "=", limit=2)
        ENV[strip(key)] = strip(val)
    end
else
    @error "CRITICAL: .env not found at $ENV_PATH"
    exit(1)
end

# 2. Extract verified keys
const VM_IP = "136.112.45.248"
const PLUTO_PORT = get(ENV, "INSIGHT_PLUTO_PORT", "5202")
const PLUTO_SECRET = get(ENV, "INSIGHT_PLUTO_SECRET", "")

# 3. Construct and launch
# Note: Ensure the secret is handled as a plain string
target_url = "http://$VM_IP:$PLUTO_PORT/?secret=$PLUTO_SECRET"

println("🚀 Launching InsightCircle Portal...")
println("🌐 Target: http://$VM_IP:$PLUTO_PORT")

# This command triggers your Mac's default browser
run(`open $target_url`)