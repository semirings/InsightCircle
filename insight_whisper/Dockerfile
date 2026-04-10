FROM python:3.11-slim

# ffmpeg is required by yt-dlp for audio extraction
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# setuptools must be in the main env so openai-whisper's legacy setup.py
# can find pkg_resources when built with --no-build-isolation.
RUN pip install --no-cache-dir setuptools wheel
RUN pip install --no-cache-dir --no-build-isolation openai-whisper==20240930
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY cookies.txt .

# Pre-download the Whisper model at build time so cold starts are fast.
# Override with WHISPER_MODEL env var (tiny/base/small/medium/large).
ARG WHISPER_MODEL=base
ENV WHISPER_MODEL=${WHISPER_MODEL}
RUN python -c "import whisper; whisper.load_model('${WHISPER_MODEL}')"

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
