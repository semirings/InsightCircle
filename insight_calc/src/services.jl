# services.jl — HTTP client helpers and orchestration.
# Calls storage for data and algebra for computation. No BQ types here.

using HTTP
using JSON3

# ── HTTP client helpers ───────────────────────────────────────────────────────

function postJson(url::String, body)
    payload  = JSON3.write(body)
    headers  = ["Content-Type" => "application/json", "Accept" => "application/json"]
    response = HTTP.post(url, headers, payload)
    return JSON3.read(response.body)
end

function getJson(url::String; headers = [])
    response = HTTP.get(url, ["Accept" => "application/json", headers...])
    return JSON3.read(response.body)
end

# ── yt_metadata query ─────────────────────────────────────────────────────────

"""
    queryYtMetadata(d4mQuery; chunkSize=10_000) -> Assoc

Parse a D4M query string and return an incidence Assoc over yt_metadata.
Rows = video id, cols = query_term values, vals = "1".

Examples:
    queryYtMetadata(":")                      # all videos
    queryYtMetadata("vid123,vid456:")         # two specific videos
    queryYtMetadata(":deep learning")         # one query term
"""
function queryYtMetadata(d4mQuery::String; chunkSize::Int=10_000)::Assoc
    r          = scan(d4mQuery, BigQueryTarget)
    row_filter = replace(r.row_clause, "row_key" => "id")
    col_filter = replace(r.col_clause, "col_key" => "qt")
    srv        = getServer()

    rowKeys = String[]
    colKeys = String[]
    vals    = String[]

    # 1. Scalar fields (EAV: col=field name, val=cell value)
    sql_scalar = """
        SELECT id, title,
               CAST(views AS STRING)       AS views,
               CAST(likes AS STRING)       AS likes,
               CAST(comments AS STRING)    AS comments,
               CAST(duration AS STRING)    AS duration,
               upload_date, uploader,
               CAST(subscribers AS STRING) AS subscribers,
               category
        FROM `$(srv.project).$(srv.dataset).yt_metadata`
        WHERE $row_filter
    """
    jobId   = _submitJob(srv.session, srv.project, sql_scalar;
                         queryParameters=toApiParams(r.params))
    url     = "$_BQ_BASE/projects/$(srv.project)/queries/$jobId?maxResults=$chunkSize&location=us-central1"
    payload = JSON3.read(HTTP.get(url, _authHeaders(srv.session)).body)
    scalar_aa = rowsToAssoc(payload, "id")

    # 2. query_term: subscripted col names (query_term_1, query_term_2, ...)
    sql_terms = """
        SELECT id,
               CONCAT('query_term_',
                      CAST(ROW_NUMBER() OVER (PARTITION BY id ORDER BY qt) AS STRING)) AS term_col,
               qt AS term_val
        FROM `$(srv.project).$(srv.dataset).yt_metadata`,
        UNNEST(query_term) AS qt
        WHERE $row_filter AND $col_filter
    """
    jobId2   = _submitJob(srv.session, srv.project, sql_terms;
                          queryParameters=toApiParams(r.params))
    url2     = "$_BQ_BASE/projects/$(srv.project)/queries/$jobId2?maxResults=$chunkSize&location=us-central1"
    payload2 = JSON3.read(HTTP.get(url2, _authHeaders(srv.session)).body)

    # terms_aa: f[1]=id, f[2]=term_col value ("query_term_1",...), f[3]=term_val
    # Skip any rows where id, term_col, or term_val is null/empty
    term_rows = String[]
    term_cols = String[]
    term_vals = String[]
    for row in payload2.rows
        any(isnothing(row.f[k].v) for k in 1:3) && continue
        id_v   = String(row.f[1].v)
        col_v  = String(row.f[2].v)
        val_v  = String(row.f[3].v)
        (isempty(id_v) || isempty(col_v) || isempty(val_v)) && continue
        push!(term_rows, id_v)
        push!(term_cols, col_v)
        push!(term_vals, val_v)
    end

    # Merge: find() on scalar_aa gives per-entry triples; terms built directly
    r1, c1, v1 = find(scalar_aa)
    isempty(r1) && isempty(term_rows) && return Assoc(String[], String[], String[])
    return Assoc(vcat(r1, term_rows), vcat(c1, term_cols), vcat(v1, term_vals))
end
