#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-alpine-chromium:test}"
CONTAINER_NAME="${CONTAINER_NAME:-alpine-chromium-test}"
SEC_COMP_FILE="${SEC_COMP_FILE:-$ROOT_DIR/chrome.json}"
HOST_PORT="${HOST_PORT:-9222}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
TARGET_URL="${TARGET_URL:-https://example.com}"
SKIP_BUILD="${SKIP_BUILD:-0}"

demand() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' not found" >&2
    exit 1
  fi
}

demand docker
demand curl

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

cleanup() {
  docker logs "$CONTAINER_NAME" 2>/dev/null || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [ "$SKIP_BUILD" != "1" ]; then
  docker build -t "$IMAGE_NAME" "$ROOT_DIR"
fi

CONTAINER_ID=$(docker run -d \
  --name "$CONTAINER_NAME" \
  --security-opt "seccomp=$SEC_COMP_FILE" \
  -p "127.0.0.1:${HOST_PORT}:9222" \
  "$IMAGE_NAME")
echo "Started $CONTAINER_ID"

echo "Waiting for Chromium debug port to become reachable..."
start_ts=$(date +%s)
while true; do
  if curl -sf "http://127.0.0.1:${HOST_PORT}/json/version" >/dev/null; then
    break
  fi
  now=$(date +%s)
  if [ $((now - start_ts)) -ge "$WAIT_SECONDS" ]; then
    echo "❌ Chromium did not become ready within ${WAIT_SECONDS}s" >&2
    exit 1
  fi
  sleep 2
done

echo "✅ Chromium debug port is reachable"
response_file="$(mktemp)"
curl -sf -X PUT "http://127.0.0.1:${HOST_PORT}/json/new?$TARGET_URL" >"$response_file"

grep -qi "$TARGET_URL" "$response_file"
echo "Checking that target URL returns content..."
body_file="$(mktemp)"
curl -sfL "$TARGET_URL" | head -c 2048 >"$body_file"

if ! grep -q "[^[:space:]]" "$body_file"; then
  echo "❌ Target URL responded but had no content" >&2
  exit 1
fi

if ! grep -qi "<html" "$body_file"; then
  echo "❌ Target URL responded but did not contain expected content" >&2
  echo "Response:" >&2
  head -c 512 "$body_file" >&2
  exit 1
fi

echo "✅ Target URL responded with expected content"

echo "All tests passed successfully!"
