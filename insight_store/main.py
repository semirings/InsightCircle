"""InsightStore – FastAPI microservice.

Single endpoint: GET /ingest
Returns a list of file names found under gs://insightcircle_bucket/ingest/.
"""

from fastapi import FastAPI, HTTPException
from google.cloud import storage

app = FastAPI(title="InsightStore", version="0.1.0")

_BUCKET_NAME = "insightcircle_bucket"
_PREFIX      = "ingest/"


@app.get("/ingest", response_model=list[str], summary="List files in ingest/")
def list_ingest_files() -> list[str]:
    """Return the names of all objects under gs://insightcircle_bucket/ingest/."""
    try:
        client = storage.Client()
        bucket = client.bucket(_BUCKET_NAME)
        blobs  = bucket.list_blobs(prefix=_PREFIX)
        files  = [
            blob.name[len(_PREFIX):]   # strip the prefix so callers get bare names
            for blob in blobs
            if blob.name != _PREFIX    # skip the folder placeholder object if present
        ]
        return files
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
