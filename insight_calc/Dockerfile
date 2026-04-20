# Build context must be populi.Wk/ (parent of InsightCircle and D4M.jl)
FROM julia:1.11-bookworm

WORKDIR /app

# D4M.jl is a path dep: Manifest references ../../D4M.jl → /D4M.jl from /app
COPY D4M.jl /D4M.jl

# ── Layer: install + precompile all dependencies ──────────────────────────────
# Cached until Project.toml or Manifest.toml change (~70 s first run, 0 s after).
# Pkg.instantiate installs deps and precompiles them; InsightCalc itself is
# skipped here because src/ is not present yet.
COPY InsightCircle/insight_calc/Project.toml InsightCircle/insight_calc/Manifest.toml ./
RUN JULIA_PKG_PRECOMPILE_AUTO=0 julia --project=. -e "using Pkg; Pkg.instantiate()"

# ── Layer: precompile heavy deps only (no InsightCalc source yet) ─────────────
# Cached until Project.toml/Manifest.toml change. Source changes skip this layer.
RUN julia --project=. -e "using D4M, DataFrames, HTTP, Oxygen, GoogleCloud, JSON3, Automa, DotEnv, Dates, Logging"

# ── Layer: copy source and precompile InsightCalc ─────────────────────────────
# Cached until src/ changes. Precompiling here means cold-start is a cache
# load (~1-2 s) instead of a full JIT compilation (~5-10 min).
COPY InsightCircle/insight_calc/src/ ./src/
RUN julia --project=. -e "using Pkg; Pkg.precompile()"

ENV PORT=8080

CMD ["julia", "--project=.", "src/InsightCalc.jl"]
