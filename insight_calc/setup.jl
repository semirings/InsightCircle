#!/usr/bin/env julia

using Pkg

# Ensure we are in the insight_calc directory
project_dir = @__DIR__
cd(project_dir)

println("🚀 Activating InsightCircle Calculation Environment in $project_dir")
Pkg.activate(".")

# Core dependencies for the API and Data layers
core_deps = ["Pkg", "Oxygen", "JSON3", "HTTP", "StructTypes", "GoogleCloud", "Pluto"]

println("📦 Ensuring core dependencies are present...")
# This syntax is more resilient to registry UUID shifts
Pkg.add(core_deps)

# Path to your D4M fork (Relative to insight_calc)
d4m_path = "../D4M.jl" 

if isdir(joinpath(project_dir, d4m_path))
    println("🔗 Linking local D4M.jl fork...")
    # develop() ensures your local changes are used instead of a registered version
    Pkg.develop(path=d4m_path)
else
    # Fallback check if the path is actually one level up from the root
    alt_path = "../../D4M.jl"
    if isdir(joinpath(project_dir, alt_path))
        Pkg.develop(path=alt_path)
    else
        @error "❌ D4M.jl directory not found. Please check your rsync structure."
        exit(1)
    end
end

println("⚙️ Resolving and Precompiling (this may take a minute)...")
Pkg.resolve()
Pkg.instantiate()
Pkg.precompile()

println("✅ Environment is healthy. Project.toml and Manifest.toml updated.")