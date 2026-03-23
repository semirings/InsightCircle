#!/usr/bin/env julia

using Pkg

# 1. Activate the local project (creates Project.toml if missing)
Pkg.activate(".")

# 2. Define your core stack
# If these aren't in Project.toml, Julia will add them with fresh, correct UUIDs
core_deps = ["Oxygen", "JSON3", "HTTP", "StructTypes", "GoogleCloud"]

println("📦 Ensuring core dependencies are present...")
Pkg.add(core_deps)

# 3. Path to your D4M fork
d4m_path = "../../D4M.jl"

if isdir(d4m_path)
    println("🔗 Linking local D4M.jl fork from $d4m_path...")
    # develop() overrides any registry version with your local source
    Pkg.develop(path=d4m_path)
else
    error("❌ D4M.jl directory not found at $d4m_path. Check your rsync script.")
end

# 4. Resolve and Precompile
println("⚙️ Finalizing environment...")
Pkg.resolve()
Pkg.precompile()

println("✅ Setup complete. Project.toml and Manifest.toml are now healthy.")