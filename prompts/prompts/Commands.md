

yt-dlp --print-to-file "{\"id\": \"%(id)s\", \"title\": \"%(title)s\", \"views\": %(view_count)d, \"date\": \"%(upload_date)s\"}" my_video.json [https://youtu.be/vOfmh16ZLIM

bq load \
  --project_id=creator-d4m-2026-1774038056 \
  --source_format=NEWLINE_DELIMITED_JSON \
  --autodetect \
  insight_metadata.yt_metadata \
  gs://insightcircle_bucket/ingest/insightcircle.jsonl

DROP TABLE IF EXISTS creator-d4m-2026-1774038056.insight_metadata.yt_metadata`;
*Turns out a table can be deleted from the browser.*

bq rm -f -t creator-d4m-2026-1774038056:insight_metadata.yt_metadata

**gcloud pubsub topics publish whisper-input \**
  **--message='{"video_id": "vOfmh16ZLIM"}' \**
  **--project=creator-d4m-2026-1774038056