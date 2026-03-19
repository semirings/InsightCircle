#!/usr/bin/env bash
set -euo pipefail

# Compile insight_store
echo "==> Building insight_store..."
(cd insight_store && ./gradlew clean bootJar)

# Build and start all containers
echo "==> Starting containers..."
docker compose up --build
