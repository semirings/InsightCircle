# pubsub.jl — Publish InsightPayload messages to Google Pub/Sub.

using Base64
using JSON3
using StructTypes

const _PUBSUB_BASE = "https://pubsub.googleapis.com/v1"

struct InsightPayload
    video_id      :: String
    gcs_uri       :: String
    d4m_score     :: Float64
    anchors       :: Vector{Float64}  # Timestamps for IW to focus on
    is_high_value :: Bool
end

StructTypes.StructType(::Type{InsightPayload}) = StructTypes.Struct()

"""
    publish(msg::InsightPayload; topic::String = ENV["PUBSUB_TOPIC"]) -> String

Serialize `msg` as JSON, base64-encode it, and publish it as a single Pub/Sub
message to `projects/{BQ_PROJECT}/topics/{topic}`.
Returns the Pub/Sub message ID on success.
"""
function publish(msg::InsightPayload; topic::String = get(ENV, "PUBSUB_TOPIC", ""))
    isempty(topic) && error("Set PUBSUB_TOPIC in .env or pass topic= keyword")

    srv     = getServer()
    fqTopic = "projects/$(srv.project)/topics/$topic"
    url     = "$_PUBSUB_BASE/$fqTopic:publish"

    encoded = base64encode(JSON3.write(msg))
    body    = JSON3.write(Dict("messages" => [Dict("data" => encoded)]))
    resp    = HTTP.post(url, _authHeaders(srv.session), body)

    msgId = String(first(JSON3.read(resp.body).messageIds))
    @info "[publish] InsightPayload published" topic=topic video_id=msg.video_id messageId=msgId
    return msgId
end
