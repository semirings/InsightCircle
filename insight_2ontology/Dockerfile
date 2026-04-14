FROM python:3.12-slim

WORKDIR /app

# Build context is InsightCircle root
COPY insight_2ontology/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY insight_2ontology/main.py .
COPY resources/gpc1.json resources/gpc1.json

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
