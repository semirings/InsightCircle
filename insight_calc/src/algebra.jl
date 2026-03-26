# algebra.jl — D4M Assoc computations. Pure functions: Assoc in, result out.
# No BQ I/O, no HTTP.

using D4M
using Logging

# ── Assoc construction ────────────────────────────────────────────────────────

# rowsToAssoc — generic row vector → Assoc for non-streaming use
function rowsToAssoc(rows)::Assoc
    rowKeys = String[]
    colKeys = String[]
    vals    = Float64[]

    for row in rows
        vidId = string(row.id)
        push!(rowKeys, vidId); push!(colKeys, "views");              push!(vals, Float64(row.views))
        push!(rowKeys, vidId); push!(colKeys, "likes");              push!(vals, Float64(row.likes))
        push!(rowKeys, vidId); push!(colKeys, "strata:$(row.query_term)"); push!(vals, 1.0)
        if !isnothing(row.tags)
            for tag in row.tags
                push!(rowKeys, vidId); push!(colKeys, "tag:$tag"); push!(vals, 1.0)
            end
        end
    end

    return Assoc(rowKeys, colKeys, vals)
end

# ── Analytics ─────────────────────────────────────────────────────────────────

function analyseSegments(segments)::Dict
    @debug "[analyseSegments] begin" nSegments=length(segments)
    # TODO: convert segments to Assoc and run D4M operations, e.g.:
    #   A      = Assoc(row_keys, col_keys, values)
    #   colsum = sum(A, 1)
    @warn "[analyseSegments] stub — no D4M computation performed"
    return Dict("segment_count" => length(segments), "status" => "stub")
end
