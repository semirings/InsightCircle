using D4M
using Dates

# Module-level connection — instantiated once, reused across all functions.
const DB_INSTANCE = "accumulo"
const DB_HOST     = "zk-node-1:2181"
const DB_USER     = "hazoo_admin"
const DB_PASS     = "accumulo_pass"

const _SERVER = Ref{Union{Nothing, DBserver}}(nothing)
const _TABLE  = Ref{Union{Nothing, DBtable}}(nothing)

# getServer() -> DBserver
# Return the cached DBserver, creating it if not yet initialised.
function getServer()::DBserver
    if isnothing(_SERVER[])
        _SERVER[] = dbsetup(DB_INSTANCE, DB_HOST, DB_USER, DB_PASS)
    end
    return _SERVER[]
end

# getDB(tableName) -> DBtable
# Return a cached DBtable for tableName, creating it via the server if needed.
function getDB(tableName::String)::DBtable
    if isnothing(_TABLE[])
        _TABLE[] = getServer()[tableName]
    end
    return _TABLE[]
end

# Use camelCase per project style
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
# Return all table names currently registered in the Accumulo instance.
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
            # D4M Associative Array logic: A[row, col] = val
            # Mapping nested YT API structure to flat Accumulo columns
            setindex!(db, string(val), row, "meta:$key")
        end
        return true
    catch e
        @error "Metadata Insertion Failed" e
        return false
    end
end
