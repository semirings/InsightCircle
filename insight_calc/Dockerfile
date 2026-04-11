# Build context must be /Users/gcr/populi.Wk/ (parent of InsightCircle and D4M.jl)
FROM julia:1.11-bookworm

WORKDIR /app

# D4M.jl is a local path dep: Manifest references ../../D4M.jl → /D4M.jl from /app
COPY D4M.jl /D4M.jl

# Copy project files
COPY InsightCircle/insight_calc/Project.toml InsightCircle/insight_calc/Manifest.toml ./
COPY InsightCircle/insight_calc/src/ ./src/

# Instantiate and precompile all packages at build time to minimise cold start
RUN julia --project=. -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"

ENV PORT=8080

CMD ["julia", "--project=.", "src/InsightCalc.jl"]
