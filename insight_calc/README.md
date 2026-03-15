# insight_calc

YouTube ingestion micro-service for InsightCircle.

Fetches public YouTube video metadata via **yt-dlp**, serialises it to
**AssociativeArray (AA) JSON** (`rows`/`cols`/`vals` per `schemas/rcvs.json`),
and forwards the payload to the **HAZoo** store at `http://host.docker.internal:5102`.

---

## Project layout

```
insight_calc/
├── Dockerfile
├── requirements.txt
├── README.md
└── app/
    ├── main.py                  # FastAPI app & /ingest endpoint
    ├── models/
    │   └── youtube_data.py      # YouTubeData Pydantic model + to_aa()
    ├── services/
    │   └── youtube_service.py   # YouTubeService.ingest() via yt-dlp
    └── utils/
        └── aa_serializer.py     # to_aa_json() / to_aa_json_str() helpers
```

---

## Local development (venv)

```bash
# From the insight_calc/ directory
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Run the dev server (hot-reload)
uvicorn app.main:app --reload --port 5101
```

The API will be available at `http://localhost:5101`.
Interactive docs: `http://localhost:5101/docs`

---

## Docker

### Build

```bash
# From the insight_calc/ directory
docker build -t insight_calc:latest .
```

### Run

```bash
docker run --rm -p 5101:5101 insight_calc:latest
```

Add `--add-host host.docker.internal:host-gateway` on Linux if the HAZoo
service runs on the host:

```bash
docker run --rm -p 5101:5101 \
  --add-host host.docker.internal:host-gateway \
  insight_calc:latest
```

Override the HAZoo endpoint via an env var if needed:

```bash
docker run --rm -p 5101:5101 \
  -e HAZOO_BASE_URL=http://my-hazoo-host:5102 \
  insight_calc:latest
```

---

## API

### `POST /ingest`

Ingest a YouTube video URL into HAZoo.

**Request**

```json
{ "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }
```

**Response (success)**

```json
{
  "success": true,
  "video_id": "dQw4w9WgXcQ",
  "hazoo_status": 200,
  "detail": null
}
```

**Response (failure)**

```json
{
  "success": false,
  "video_id": "dQw4w9WgXcQ",
  "hazoo_status": null,
  "detail": "HAZoo unreachable: ..."
}
```

**curl example**

```bash
curl -X POST http://localhost:5101/ingest \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}'
```

### `GET /health`

Returns `{"status": "ok"}` – useful for container health checks.

---

## AA JSON format

Serialised payloads conform to `schemas/rcvs.json`:

```json
{
  "rows": ["dQw4w9WgXcQ", "dQw4w9WgXcQ", "dQw4w9WgXcQ", ...],
  "cols": ["video_id", "url", "title", "description", "views", ...],
  "vals": ["dQw4w9WgXcQ", "https://...", "Never Gonna Give You Up", ..., 1400000000]
}
```

Each `(rows[i], cols[i]) → vals[i]` triple represents one field of the video
record.

---

## Adding ML / SAM3 later

The project is structured so future capabilities can be added without touching
the ingestion pipeline:

| Concern | Where to add |
|---|---|
| ML preprocessing / feature extraction | `app/services/ml_service.py` |
| SAM3 segmentation (vision) | `app/services/sam3_service.py` |
| PyTorch training jobs | `app/tasks/` (e.g. Celery or ARQ workers) |
| New ingest sources (Twitter, RSS…) | `app/services/<source>_service.py` |
| Additional AA types | `app/utils/aa_serializer.py` – extend `serialize_dict()` |

Add new Python packages to `requirements.txt`; they will be picked up by both
the venv install and the Docker build automatically.
