#!/usr/bin/env julia

using Pkg

# Ensure we are in the insight_calc directory
project_dir = @__DIR__
cd(project_dir)

println("🚀 Activating InsightCircle Calculation Environment in $project_dir")
Pkg.activate(".")

# 1. Clean out any old registry-based D4M references to avoid UUID conflicts
try
    Pkg.rm("D4M")
catch
    # It's fine if it wasn't there
end

# Core dependencies (Standard Registered Packages Only)
core_deps = ["Pkg", "Oxygen", "JSON3", "HTTP", "StructTypes", "GoogleCloud", "Pluto", "Automa", "Test", "Logging"]

println("📦 Ensuring core dependencies are present...")
Pkg.add(core_deps)

# 2. Link the local fork using your path logic
d4m_path = "../D4M.jl" 

if isdir(joinpath(project_dir, d4m_path))
    println("🔗 Linking local D4M.jl fork from $d4m_path...")
    Pkg.develop(path=d4m_path)
else
    alt_path = "../../D4M.jl"
    if isdir(joinpath(project_dir, alt_path))
        println("🔗 Linking local D4M.jl fork from $alt_path...")
        Pkg.develop(path=alt_path)
    else
        @error "❌ D4M.jl directory not found. Please check your rsync structure."
        exit(1)
    end
end

println("⚙️ Finalizing Environment...")
Pkg.resolve()
Pkg.instantiate()
Pkg.precompile()

println("✅ Environment is healthy for Julia 1.11.")