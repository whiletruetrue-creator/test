#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME=local/rag-qdrant:v1.18.3-arm64-64k
QDRANT_CONTAINER=rag-qdrant
QDRANT_STORAGE=/data/cubex/bushu/ai/rag/qdrant_storage
QWEN_CONTAINER=vllm-qwen25-72b-bf16

echo "===== Mandatory pre-deployment checks ====="
test "$(uname -m)" = "aarch64"
test "$(getconf PAGESIZE)" = "65536"
test "$(docker image inspect "$IMAGE_NAME" --format '{{.Architecture}}')" = "arm64"
test "$(docker image inspect "$IMAGE_NAME" --format '{{index .Config.Labels "com.cubex.qdrant.jemalloc-lg-page"}}')" = "16"
test "$(docker image inspect "$IMAGE_NAME" --format '{{index .Config.Labels "com.cubex.qdrant.max-system-page-size"}}')" = "65536"

QWEN_ID_BEFORE=$(docker inspect -f '{{.Id}}' "$QWEN_CONTAINER")
curl -fsS --max-time 5 http://127.0.0.1:8000/health >/dev/null

mkdir -p "$QDRANT_STORAGE"

echo "===== Replace only the failed RAG Qdrant container ====="
docker update --restart=no "$QDRANT_CONTAINER" >/dev/null 2>&1 || true
docker rm -f "$QDRANT_CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$QDRANT_CONTAINER" \
  --restart unless-stopped \
  --cpus=4 \
  --memory=8g \
  -p 127.0.0.1:6333:6333 \
  -p 127.0.0.1:6334:6334 \
  -v "$QDRANT_STORAGE:/qdrant/storage" \
  "$IMAGE_NAME" >/dev/null

ready=0
for attempt in $(seq 1 90); do
  if curl -fsS --max-time 3 http://127.0.0.1:6333/collections >/dev/null; then
    ready=1
    break
  fi

  running=$(docker inspect -f '{{.State.Running}}' "$QDRANT_CONTAINER" 2>/dev/null || echo false)
  if test "$running" != "true"; then
    echo "Qdrant exited during production startup" >&2
    docker logs --tail 200 "$QDRANT_CONTAINER" >&2 || true
    exit 1
  fi
  sleep 2
done

if test "$ready" != "1"; then
  echo "Qdrant production startup timed out" >&2
  docker logs --tail 200 "$QDRANT_CONTAINER" >&2 || true
  exit 1
fi

if docker logs "$QDRANT_CONTAINER" 2>&1 | grep -q 'Unsupported system page size'; then
  echo "jemalloc page-size error detected unexpectedly" >&2
  exit 1
fi

QWEN_ID_AFTER=$(docker inspect -f '{{.Id}}' "$QWEN_CONTAINER")
test "$QWEN_ID_BEFORE" = "$QWEN_ID_AFTER"
curl -fsS --max-time 5 http://127.0.0.1:8000/health >/dev/null

echo "===== Deployment result ====="
docker ps \
  --filter "name=^/${QDRANT_CONTAINER}$" \
  --filter "name=^/rag-embedding$" \
  --filter "name=^/rag-reranker$" \
  --filter "name=^/${QWEN_CONTAINER}$" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "PASS: Qdrant 64K production service: http://127.0.0.1:6333"
echo "PASS: Qwen was not restarted: $QWEN_ID_AFTER"

