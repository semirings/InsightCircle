#!/usr/bin/env julia --project=@.

using Pkg
import Pkg
Pkg.activate(@__DIR__) # Activates the environment where the script lives
Pkg.instantiate()      # Optional: ensures all deps are actually installed

using Pluto

# Pull from .env
const PLUTO_SECRET = get(ENV, "INSIGHT_PLUTO_SECRET", nothing)
const PLUTO_PORT = parse(Int, get(ENV, "INSIGHT_PLUTO_PORT", "5202"))

# Use boolean logic: if secret is provided, enable security flags
const USE_SECURITY = !isnothing(PLUTO_SECRET)

Pluto.run(
    port=PLUTO_PORT, 
    host="0.0.0.0", 
    launch_browser=false,
    # New security flags replace the old 'secret' keyword
    require_secret_for_open_links=USE_SECURITY,
    require_secret_for_access=USE_SECURITY
)