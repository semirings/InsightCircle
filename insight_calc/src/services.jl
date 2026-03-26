using Dates
using GoogleCloud

# ── BigQuery connection types ─────────────────────────────────────────────────

struct BQServer
    project :: String
    dataset :: String
    session :: GoogleCloud.GoogleSession
end

struct BQTable
    server  :: BQServer
    name    :: String
    dataset :: String
end
BQTable(srv::BQServer, name::String) = BQTable(srv, name, srv.dataset)

# ── Module-level singletons ───────────────────────────────────────────────────
# Credentials are read from GOOGLE_APPLICATION_CREDENTIALS at runtime.

const BQ_PROJECT = get(ENV, "BQ_PROJECT", "")
const BQ_DATASET = get(ENV, "BQ_DATASET", "insight_metadata")

const _SERVER = Ref{Union{Nothing, BQServer}}(nothing)
const _TABLE  = Ref{Union{Nothing, BQTable}}(nothing)

function dbsetup(projectId::String, dataset::String)::BQServer
    keyPath = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    isempty(keyPath) && error("Set GOOGLE_APPLICATION_CREDENTIALS environment variable")
    creds   = GoogleCloud.JSONCredentials(keyPath)
    session = GoogleCloud.GoogleSession(creds, ["https://www.googleapis.com/auth/bigquery"])
    return BQServer(projectId, dataset, session)
end

# getServer() -> BQServer
# Return the cached BQServer, creating it if not yet initialised.
function getServer()::BQServer
    if isnothing(_SERVER[])
        isempty(BQ_PROJECT) && error("Set BQ_PROJECT environment variable")
        _SERVER[] = dbsetup(BQ_PROJECT, BQ_DATASET)
    end
    return _SERVER[]
end

# getDB(tableName) -> BQTable
# Return a cached BQTable for tableName, creating it via the server if needed.
function getDB(tableName::String)::BQTable
    if isnothing(_TABLE[])
        _TABLE[] = BQTable(getServer(), tableName)
    end
    return _TABLE[]
end

function createMetadataTable(tableName::String)
    try
        getDB(tableName)
        @info "Successfully initialized/verified table: $tableName"
        return true
    catch e
        @error "D4M Table Creation Failed" e
        return false
    end
end

# listTables() -> Vector{String}
# Return all table names in the BigQuery dataset.
function listTables()::Vector{String}
    try
        return ls(getServer())
    catch e
        @error "D4M List Tables Failed" e
        return String[]
    end
end

function insertVideoMetadata(tableName::String, videoData::Dict)
    try
        db  = getDB(tableName)
        row = videoData["id"]
        for (key, val) in videoData["snippet"]
            setindex!(db, string(val), row, "meta:$key")
        end
        return true
    catch e
        @error "Metadata Insertion Failed" e
        return false
    end
end
