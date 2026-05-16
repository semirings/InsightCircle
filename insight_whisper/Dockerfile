FROM python:3.11-slim

# ffmpeg: audio extraction
# deno: yt-dlp JS runtime for n-parameter deobfuscation (single static binary)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ffmpeg \
        unzip \
    && curl -fsSL \
        https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip \
        -o /tmp/deno.zip \
    && unzip /tmp/deno.zip -d /usr/local/bin/ \
    && rm /tmp/deno.zip \
    && deno --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# setuptools must be in the main env so openai-whisper's legacy setup.py
# can find pkg_resources when built with --no-build-isolation.
RUN pip install --no-cache-dir setuptools wheel
# CPU-only torch — Cloud Run has no GPU; avoids pulling 2+ GB of CUDA packages
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir --no-build-isolation openai-whisper==20240930
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Pre-download the Whisper model at build time so cold starts are fast.
# Override with WHISPER_MODEL env var (tiny/base/small/medium/large).
ARG WHISPER_MODEL=base
ENV WHISPER_MODEL=${WHISPER_MODEL}
RUN python -c "import whisper; whisper.load_model('${WHISPER_MODEL}')"

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
