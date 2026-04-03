

yt-dlp --print-to-file "{\"id\": \"%(id)s\", \"title\": \"%(title)s\", \"views\": %(view_count)d, \"date\": \"%(upload_date)s\"}" my_video.json [https://youtu.be/vOfmh16ZLIM

bq load \
  --source_format=NEWLINE_DELIMITED_JSON \
  --autodetect \
  # insight_metadata.yt_metadata \
  ./path/to/your/data.json

DROP TABLE IF EXISTS creator-d4m-2026-1774038056.insight_metadata.yt_metadata`;

bq rm -f -t creator-d4m-2026-1774038056:insight_metadata.yt_metadata