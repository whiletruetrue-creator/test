# Qdrant v1.18.3 ARM64 / 64KB 页离线镜像构建包

这个构建包用于以下已经现场确认的环境：

- 服务器架构：`aarch64/arm64`
- 操作系统页大小：`65536` 字节（64KB）
- Qdrant：`v1.18.3`
- 最终镜像：`local/rag-qdrant:v1.18.3-arm64-64k`
- 现有 Qwen 容器：`vllm-qwen25-72b-bf16`

旧的普通 ARM64 Qdrant 镜像把 jemalloc 按较小页尺寸编译，因而在服务器上报：

```text
<jemalloc>: Unsupported system page size
```

本工程在 GitHub 原生 ARM64 Runner 上编译官方 Qdrant v1.18.3 源码，并设置：

```text
JEMALLOC_SYS_WITH_LG_PAGE=16
```

`2^16 = 65536`，与服务器系统页大小一致。

## 一、为什么需要 GitHub Actions

Windows 开发机没有 Docker Desktop，而当前 ChatGPT 执行环境也没有 Docker、Podman、Buildah 或 ARM64 编译工具链，因此不能在本地可靠地产出并实际验证镜像。

GitHub Actions 提供原生 `ubuntu-24.04-arm` 主机。构建、容器启动、REST CRUD 验证和镜像导出都在 ARM64 主机完成，Windows 只负责下载最终文件。

## 二、开始构建

1. 在 GitHub 创建一个空仓库。公开仓库速度更快；私有仓库也可以，但会使用账户的 Actions 分钟。
2. 解压本包，把全部内容上传到仓库根目录。必须确保隐藏目录 `.github` 一并上传。
3. 打开仓库的 `Actions` 页面。
4. 选择 `Build Qdrant ARM64 64K offline image`。
5. 点击 `Run workflow`。
6. 等待任务显示绿色对勾。
7. 在任务页面底部下载：

```text
qdrant-v1.18.3-arm64-64k-offline.zip
```

解压后应包含：

```text
qdrant-v1.18.3-arm64-64k.tar
SHA256SUMS.txt
BUILD-INFO.txt
docker-image-inspect.json
```

构建过程可能需要较长时间，因为 Qdrant 是大型 Rust 项目。只要日志仍在输出编译进度就不是卡死。

## 三、上传服务器

把以下文件放到服务器同一个目录：

```text
/data/cubex/bushu/ai/rag-offline-arm64/qdrant-64k/
├── qdrant-v1.18.3-arm64-64k.tar
├── SHA256SUMS.txt
├── 01-smoke-test-qdrant-64k.sh
├── 02-deploy-qdrant-64k.sh
└── 03-health-check-all.sh
```

服务器脚本就在本包的 `server` 目录。

设置执行权限：

```bash
cd /data/cubex/bushu/ai/rag-offline-arm64/qdrant-64k
chmod +x ./*.sh
```

## 四、先做隔离测试

```bash
./01-smoke-test-qdrant-64k.sh
```

成功时必须显示：

```text
PASS: Qdrant ARM64 64K image passed API CRUD on the target server
PASS: Qwen was not restarted
```

测试使用：

- 临时容器：`rag-qdrant-64k-check`
- 临时端口：`16333`
- 临时存储：`/data/cubex/bushu/ai/rag/qdrant_64k_check`

不会重启、停止或删除 Qwen。

## 五、正式部署 Qdrant

只有隔离测试通过以后才执行：

```bash
./02-deploy-qdrant-64k.sh
```

该脚本只替换失败的 `rag-qdrant` 容器，不删除 Qdrant 数据目录，也不操作 Qwen 容器。

正式服务地址：

```text
Qdrant REST: http://127.0.0.1:6333
Qdrant gRPC: 127.0.0.1:6334
```

## 六、检查整套服务

```bash
./03-health-check-all.sh
```

预期输出：

```text
PASS  Qwen
PASS  Qdrant
PASS  Embedding
PASS  Reranker
All four AI/RAG services are healthy
```

## 七、明确的安全边界

脚本不会执行：

```text
docker system prune
docker image prune
docker rm vllm-qwen25-72b-bf16
rm -rf /data/cubex/bushu/ai/model
```

脚本只针对：

```text
rag-qdrant
rag-qdrant-64k-check
/data/cubex/bushu/ai/rag/qdrant_storage
/data/cubex/bushu/ai/rag/qdrant_64k_check
```

Qwen 的容器 ID 会在执行前后比较，健康接口也会再次检查。

