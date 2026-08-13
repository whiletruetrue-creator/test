#!/usr/bin/env bash
set -Eeuo pipefail

# Put the downloaded tar beside this script or override IMAGE_TAR explicitly.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE_TAR=${IMAGE_TAR:-"$SCRIPT_DIR/qdrant-v1.18.3-arm64-64k.tar"}
IMAGE_NAME=local/rag-qdrant:v1.18.3-arm64-64k
CHECK_CONTAINER=rag-qdrant-64k-check
CHECK_PORT=16333
CHECK_STORAGE=/data/cubex/bushu/ai/rag/qdrant_64k_check
QWEN_CONTAINER=vllm-qwen25-72b-bf16

echo "===== Read-only Qwen baseline ====="
QWEN_ID_BEFORE=$(docker inspect -f '{{.Id}}' "$QWEN_CONTAINER")
curl -fsS --max-time 5 http://127.0.0.1:8000/health >/dev/null
echo "Qwen healthy: $QWEN_ID_BEFORE"

echo "===== Host and package validation ====="
test "$(uname -m)" = "aarch64"
test "$(getconf PAGESIZE)" = "65536"
test -s "$IMAGE_TAR"

if test -s "$(dirname "$IMAGE_TAR")/SHA256SUMS.txt"; then
  (
    cd "$(dirname "$IMAGE_TAR")"
    sed 's/\r$//' SHA256SUMS.txt | sha256sum -c -
  )
else
  echo "WARNING: SHA256SUMS.txt was not found; checksum verification skipped"
fi

echo "===== Load and inspect the new image ====="
docker load -i "$IMAGE_TAR"
test "$(docker image inspect "$IMAGE_NAME" --format '{{.Architecture}}')" = "arm64"
test "$(docker image inspect "$IMAGE_NAME" --format '{{index .Config.Labels "com.cubex.qdrant.jemalloc-lg-page"}}')" = "16"
test "$(docker image inspect "$IMAGE_NAME" --format '{{index .Config.Labels "com.cubex.qdrant.max-system-page-size"}}')" = "65536"

echo "===== Isolated 64K-page smoke test ====="
docker rm -f "$CHECK_CONTAINER" >/dev/null 2>&1 || true
mkdir -p "$CHECK_STORAGE"

docker run -d \
  --name "$CHECK_CONTAINER" \
  --restart=no \
  --cpus=2 \
  --memory=4g \
  -p "127.0.0.1:${CHECK_PORT}:6333" \
  -v "$CHECK_STORAGE:/qdrant/storage" \
  "$IMAGE_NAME" >/dev/null

cleanup() {
  docker rm -f "$CHECK_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready=0
for attempt in $(seq 1 60); do
  if curl -fsS --max-time 3 "http://127.0.0.1:${CHECK_PORT}/collections" >/dev/null; then
    ready=1
    break
  fi

  running=$(docker inspect -f '{{.State.Running}}' "$CHECK_CONTAINER" 2>/dev/null || echo false)
  if test "$running" != "true"; then
    echo "Qdrant 64K smoke-test container exited" >&2
    docker logs --tail 200 "$CHECK_CONTAINER" >&2 || true
    exit 1
  fi
  sleep 2
done

if test "$ready" != "1"; then
  echo "Qdrant 64K smoke test timed out" >&2
  docker logs --tail 200 "$CHECK_CONTAINER" >&2 || true
  exit 1
fi

if docker logs "$CHECK_CONTAINER" 2>&1 | grep -q 'Unsupported system page size'; then
  echo "Old jemalloc page-size error is still present" >&2
  exit 1
fi

curl -fsS -X PUT \
  "http://127.0.0.1:${CHECK_PORT}/collections/__server_smoke_64k" \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":4,"distance":"Cosine"}}' >/dev/null

curl -fsS -X PUT \
  "http://127.0.0.1:${CHECK_PORT}/collections/__server_smoke_64k/points?wait=true" \
  -H 'Content-Type: application/json' \
  -d '{"points":[{"id":1,"vector":[0.1,0.2,0.3,0.4],"payload":{"check":"kunpeng-64k"}}]}' >/dev/null

curl -fsS \
  "http://127.0.0.1:${CHECK_PORT}/collections/__server_smoke_64k/points/1" >/dev/null

curl -fsS -X DELETE \
  "http://127.0.0.1:${CHECK_PORT}/collections/__server_smoke_64k" >/dev/null

QWEN_ID_AFTER=$(docker inspect -f '{{.Id}}' "$QWEN_CONTAINER")
test "$QWEN_ID_BEFORE" = "$QWEN_ID_AFTER"
curl -fsS --max-time 5 http://127.0.0.1:8000/health >/dev/null

echo "PASS: Qdrant ARM64 64K image passed API CRUD on the target server"
echo "PASS: Qwen was not restarted: $QWEN_ID_AFTER"
echo "Next: run 02-deploy-qdrant-64k.sh"

