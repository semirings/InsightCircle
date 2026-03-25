#!/usr/bin/env julia

using Pluto

# Pull from .env (assuming you've loaded your ENV already)
const PLUTO_SECRET = get(ENV, "INSIGHT_PLUTO_SECRET", nothing)
const PLUTO_PORT = parse(Int, get(ENV, "INSIGHT_PLUTO_PORT", "5202"))

Pluto.run(
    port=PLUTO_PORT, 
    host="0.0.0.0", 
    secret=PLUTO_SECRET, # This locks the token
    launch_browser=false
)