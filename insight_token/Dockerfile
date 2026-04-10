FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Download the spaCy model at build time so cold starts are fast.
# Override with SPACY_MODEL env var (en_core_web_sm/md/lg/trf).
ARG SPACY_MODEL=en_core_web_sm
ENV SPACY_MODEL=${SPACY_MODEL}
RUN python -m spacy download ${SPACY_MODEL}

COPY main.py .

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
