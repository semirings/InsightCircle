module 

using GoogleCloud
using JSON3
using D4M

export fetchBqChunk, rowsToAA, initStorage!

# Global session variable to be populated on init
const SESSION = Ref{Union{GoogleCloud.Session, Nothing}}(nothing)

"""
Initialize the BigQuery session with a service account JSON.
"""
function initStorage!(path::String)
    creds = GoogleCloud.JSONCredentials(path)
    SESSION[] = GoogleCloud.session(creds, ["https://www.googleapis.com/auth/bigquery"])
    println("✅ BigQuery Session Initialized.")
end

function fetchBqChunk(limit=500, offset=0)
    isnothing(SESSION[]) && error("Storage not initialized. Call initStorage!(path) first.")
    
    query = """
    SELECT id, title, views, likes, query_term, tags 
    FROM `insight_metadata.yt_metadata`
    LIMIT $limit OFFSET $offset
    """
    # Assuming execute_query is defined or imported via GoogleCloud.jl
    return GoogleCloud.BigQuery.query(SESSION[], query) 
end

function rowsToAA(rows)
    row_idx = String[]
    col_idx = String[]
    values  = Float64[]

    for row in rows
        vid_id = row.id
        
        # Numeric metrics
        push!(row_idx, vid_id); push!(col_idx, "views"); push!(values, Float64(row.views))
        push!(row_idx, vid_id); push!(col_idx, "likes"); push!(values, Float64(row.likes))
        
        # Categorical strata
        push!(row_idx, vid_id); push!(col_idx, "strata:$(row.query_term)"); push!(values, 1.0)
        
        # Sparse Tag expansion
        if !isnothing(row.tags)
            for tag in row.tags
                push!(row_idx, vid_id); push!(col_idx, "tag:$tag"); push!(values, 1.0)
            end
        end
    end

    return Assoc(row_idx, col_idx, values)
end

end # module