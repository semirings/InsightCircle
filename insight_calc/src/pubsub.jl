# pubsub.jl — Publish CalcCompletion events to Google Pub/Sub.
#
# Every IC route calls publishCompletion() when it finishes (success or error).
# The event is picked up by InsightStore and written to pipeline_events in BQ.
#
# Required env var:
#   CALC_COMPLETION_TOPIC  — short topic name, e.g. "calc-completion"

using Base64
using Dates
using JSON3
using StructTypes

const _PUBSUB_BASE = "https://pubsub.googleapis.com/v1"

struct CalcCompletion
    script      :: String   # route identifier, e.g. "query/yt_metadata"
    status      :: String   # "ok" | "error"
    row_count   :: Int
    duration_ms :: Int
    timestamp   :: String   # ISO-8601 UTC
    detail      :: String   # error message or empty
end

StructTypes.StructType(::Type{CalcCompletion}) = StructTypes.Struct()

"""
    publishCompletion(script, status; row_count, duration_ms, detail)

Publish a CalcCompletion event to CALC_COMPLETION_TOPIC.
Failures are logged and swallowed so a Pub/Sub outage never breaks a route.
"""
function publishCompletion(
    script      :: String,
    status      :: String;
    row_count   :: Int    = 0,
    duration_ms :: Int    = 0,
    detail      :: String = "",
)
    topic = get(ENV, "CALC_COMPLETION_TOPIC", "")
    if isempty(topic)
        @warn "[publishCompletion] CALC_COMPLETION_TOPIC not set — skipping" script=script
        return
    end

    try
        srv     = getServer()
        fqTopic = "projects/$(srv.project)/topics/$topic"
        url     = "$_PUBSUB_BASE/$fqTopic:publish"

        msg = CalcCompletion(
            script,
            status,
            row_count,
            duration_ms,
            Dates.format(now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
            detail,
        )

        encoded = base64encode(JSON3.write(msg))
        body    = JSON3.write(Dict("messages" => [Dict("data" => encoded)]))
        resp    = HTTP.post(url, _authHeaders(srv.session), body)

        msgId = String(first(JSON3.read(resp.body).messageIds))
        @info "[publishCompletion] published" script=script status=status messageId=msgId
    catch err
        @error "[publishCompletion] failed — continuing" script=script error=string(err)
    end
end
