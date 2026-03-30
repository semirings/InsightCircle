# test_storage.jl — Unit tests for getServer and dbSetup (storage.jl)

using Test
using Logging
using D4M          # storage.jl uses Assoc from D4M
include("../src/storage.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
Return a path to a structurally-valid service-account JSON file written into
`dir`. A real throwaway RSA key is generated via `openssl` so that
GoogleCloud.JSONCredentials / MbedTLS.parse_key! can parse it. The key is
never used for actual GCP authentication.
"""
function fake_key_file(dir::String)::String
    pem_path = joinpath(dir, "test_rsa.pem")
    run(pipeline(`openssl genrsa 2048`, stdout=pem_path, stderr=devnull))
    private_key = replace(read(pem_path, String), "\n" => "\\n")

    path = joinpath(dir, "fake_key.json")
    write(path, """{
        "type": "service_account",
        "project_id": "fake-project",
        "private_key_id": "key1",
        "private_key": "$private_key",
        "client_email": "test@fake-project.iam.gserviceaccount.com",
        "client_id": "123456789",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test%40fake-project.iam.gserviceaccount.com"
    }""")
    return path
end

# Top-level logger struct for log-capture tests (structs must be at top level)
struct WarnCapture <: AbstractLogger
    seen::Ref{Bool}
end
Logging.min_enabled_level(::WarnCapture) = Logging.Debug
Logging.shouldlog(::WarnCapture, args...) = true
function Logging.handle_message(l::WarnCapture, level, msg, _mod, _group, _id, _file, _line; kwargs...)
    if level == Logging.Warn && occursin(".env", string(msg))
        l.seen[] = true
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 1. dbSetup — error when GOOGLE_APPLICATION_CREDENTIALS is unset / empty
# ─────────────────────────────────────────────────────────────────────────────

@testset "dbSetup — missing credentials" begin
    withenv("GOOGLE_APPLICATION_CREDENTIALS" => "") do
        err = @test_throws ErrorException dbSetup("my-project", "my-dataset")
        @test occursin("GOOGLE_APPLICATION_CREDENTIALS", err.value.msg)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. dbSetup — populates BQServer fields from arguments
# ─────────────────────────────────────────────────────────────────────────────

@testset "dbSetup — BQServer fields" begin
    mktempdir() do dir
        keypath = fake_key_file(dir)
        withenv("GOOGLE_APPLICATION_CREDENTIALS" => keypath) do
            srv = dbSetup("proj-abc", "ds-xyz")
            @test srv isa BQServer
            @test srv.project == "proj-abc"
            @test srv.dataset == "ds-xyz"
            @test srv.session isa GoogleCloud.GoogleSession
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. getServer — returns cached server without re-initialising
# ─────────────────────────────────────────────────────────────────────────────

@testset "getServer — cache hit" begin
    saved = _SERVER[]
    try
        mktempdir() do dir
            keypath = fake_key_file(dir)
            withenv("GOOGLE_APPLICATION_CREDENTIALS" => keypath) do
                cached = dbSetup("cache-proj", "cache-ds")
                _SERVER[] = cached
                result = getServer()
                @test result === cached          # exact same object, no re-init
                @test result.project == "cache-proj"
                @test result.dataset == "cache-ds"
            end
        end
    finally
        _SERVER[] = saved
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. getServer — emits @warn when .env file is absent
# ─────────────────────────────────────────────────────────────────────────────

@testset "getServer — warns on missing .env" begin
    saved = _SERVER[]
    logger = WarnCapture(Ref(false))
    # Base.active_project() is fixed at process startup and cannot be redirected
    # via withenv. Compute the path getServer() will actually check.
    env_path = joinpath(dirname(dirname(Base.active_project())), ".env")
    try
        _SERVER[] = nothing
        if isfile(env_path)
            # .env exists in this environment — warning path is not exercised.
            @test_skip "skipped: $env_path exists; warning only fires when .env is absent"
        else
            with_logger(logger) do
                withenv("GOOGLE_APPLICATION_CREDENTIALS" => "") do
                    @test_throws Exception getServer()
                end
            end
            @test logger.seen[]
        end
    finally
        _SERVER[] = saved
    end
end


println("All storage tests passed.")
