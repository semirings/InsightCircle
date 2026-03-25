#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using Pluto

# Manually load .env if not using a package like DotEnv
if isfile(".env")
    for line in eachline(".env")
        if occursin("=", line) && !startswith(line, "#")
            key, val = split(line, "=", limit=2)
            ENV[strip(key)] = strip(val)
        end
    end
end

const PLUTO_SECRET = get(ENV, "INSIGHT_PLUTO_SECRET", "default_secret_if_env_missing")
const PLUTO_PORT = parse(Int, get(ENV, "INSIGHT_PLUTO_PORT", "5202"))

# Note: In Pluto, the 'secret' isn't a keyword, it's a security setting.
# We set the options to require the secret you've defined.
Pluto.run(
    port=PLUTO_PORT, 
    host="127.0.0.1",
    launch_browser=true,
    require_secret_for_open_links=true,
    require_secret_for_access=true
)