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

cleanup() {
  docker logs "$CONTAINER_NAME" 2>/dev/null || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [ "$SKIP_BUILD" != "1" ]; then
  docker build -t "$IMAGE_NAME" "$ROOT_DIR"
fi

start_container() {
  if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
  fi
  CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" \
    --security-opt "seccomp=$SEC_COMP_FILE" \
    -p "127.0.0.1:${HOST_PORT}:9222" \
    "$@" \
    "$IMAGE_NAME")
  echo "Started $CONTAINER_ID"
}

wait_ready() {
  echo "Waiting for Chromium debug port to become reachable..."
  local start_ts now
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
}

# Chromium can survive a broken GPU stack by silently falling back to
# software compositing: the debug port comes up and pages load, but the
# logs fill with GPU process errors, and stricter flags (--disable-gpu)
# or environments turn the same defect into a crash loop (issue #21).
# Fail on those errors instead of only checking reachability.
check_fatal_logs() {
  local bad
  bad=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -E \
    "FATAL|GPU process (isn't usable|exited unexpectedly|launch failed)|seccomp-bpf failure|eglInitialize .* failed|Extension not supported" \
    || true)
  if [ -n "$bad" ]; then
    echo "❌ Chromium logged fatal GPU/sandbox errors:" >&2
    { echo "$bad" | head -20 >&2; } || true
    exit 1
  fi
  echo "✅ No fatal GPU/sandbox errors in logs"
}

start_container
wait_ready
check_fatal_logs

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

echo "Checking that chromium renders a page to a screenshot..."
shot_log="$(mktemp)"
if ! docker exec --user chrome "$CONTAINER_NAME" chromium-browser \
  --headless \
  --user-data-dir=/tmp/test-profile \
  --screenshot=/tmp/test-shot.png \
  --window-size=800,600 \
  "data:text/html,<h1>render test</h1>" >"$shot_log" 2>&1; then
  echo "❌ Screenshot run failed:" >&2
  tail -20 "$shot_log" >&2
  exit 1
fi
shot_size=$(docker exec "$CONTAINER_NAME" stat -c %s /tmp/test-shot.png || echo 0)
if [ "$shot_size" -lt 1000 ]; then
  echo "❌ Screenshot missing or implausibly small (${shot_size} bytes)" >&2
  exit 1
fi
echo "✅ Chromium rendered a screenshot (${shot_size} bytes)"

check_fatal_logs

echo "Re-testing with --disable-gpu args (issue #21 regression)..."
start_container -e CHROMIUM_ARGS="--headless --disable-gpu --disable-dev-shm-usage --remote-debugging-port=9223 --disable-crash-reporter --no-crashpad"
wait_ready
check_fatal_logs

echo "All tests passed successfully!"
