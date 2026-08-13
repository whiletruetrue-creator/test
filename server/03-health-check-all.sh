#!/usr/bin/env bash
set -Eeuo pipefail

check() {
  name=$1
  url=$2
  if curl -fsS --max-time 10 "$url" >/dev/null; then
    echo "PASS  $name  $url"
  else
    echo "FAIL  $name  $url" >&2
    return 1
  fi
}

docker ps \
  --filter 'name=rag-' \
  --filter 'name=vllm-qwen25-72b-bf16' \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

check Qwen      http://127.0.0.1:8000/health
check Qdrant    http://127.0.0.1:6333/collections
check Embedding http://127.0.0.1:8011/health
check Reranker  http://127.0.0.1:8012/health

echo "All four AI/RAG services are healthy"

