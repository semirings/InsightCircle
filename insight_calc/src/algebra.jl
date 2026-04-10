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

"""
    queryVideo(d4mQuery::String) -> InsightPayload

Query yt_metadata for a single video using a D4M query string
(e.g. `"vid123:"`) and return an InsightPayload.

d4m_score  = (likes + comments) / views  (engagement rate; 0 if views == 0)
is_high_value = d4m_score ≥ 0.05
gcs_uri    = gs://{GCS_VIDEO_BUCKET}/{video_id}.mp4
anchors    = [] (populated downstream when timestamp data is available)
"""
function queryVideo(d4mQuery::String)::InsightPayload
    aa = queryYtMetadata(d4mQuery)

    rows, cols, vals = find(aa)
    isempty(rows) && error("queryVideo: no results for D4M query \"$d4mQuery\"")

    video_id = first(rows)
    fields   = Dict(zip(cols, vals))

    views    = parse(Float64, get(fields, "views",    "0"))
    likes    = parse(Float64, get(fields, "likes",    "0"))
    comments = parse(Float64, get(fields, "comments", "0"))

    d4m_score     = views > 0 ? (likes + comments) / views : 0.0
    is_high_value = d4m_score >= 0.05

    bucket  = get(ENV, "GCS_VIDEO_BUCKET", "")
    gcs_uri = isempty(bucket) ? "" : "gs://$bucket/$video_id.mp4"

    return InsightPayload(video_id, gcs_uri, d4m_score, Float64[], is_high_value)
end

function analyseSegments(segments)::Dict
    @debug "[analyseSegments] begin" nSegments=length(segments)
    # TODO: convert segments to Assoc and run D4M operations, e.g.:
    #   A      = Assoc(row_keys, col_keys, values)
    #   colsum = sum(A, 1)
    @warn "[analyseSegments] stub — no D4M computation performed"
    return Dict("segment_count" => length(segments), "status" => "stub")
end
