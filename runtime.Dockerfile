ARG QDRANT_VERSION=1.18.3
FROM qdrant/qdrant:v${QDRANT_VERSION}

COPY --chmod=0755 qdrant-arm64-64k /qdrant/qdrant

LABEL org.opencontainers.image.title="Qdrant ARM64 64K-page compatible"
LABEL org.opencontainers.image.description="Qdrant v1.18.3 rebuilt with JEMALLOC_SYS_WITH_LG_PAGE=16 for 64KB-page ARM64 Linux"
LABEL org.opencontainers.image.source="https://github.com/qdrant/qdrant"

