$ErrorActionPreference = "Stop"

Write-Host "Qdrant ARM64 64K 构建包检查" -ForegroundColor Cyan

$required = @(
    ".github\workflows\build-qdrant-arm64-64k.yml",
    "runtime.Dockerfile",
    "README.md",
    "server\01-smoke-test-qdrant-64k.sh",
    "server\02-deploy-qdrant-64k.sh",
    "server\03-health-check-all.sh"
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "缺少文件：$path。请在解压后的构建包根目录执行本脚本。"
    }
}

Write-Host "文件完整。下一步：" -ForegroundColor Green
Write-Host "1. 在 GitHub 新建空仓库。"
Write-Host "2. 把本目录全部内容上传到仓库根目录，必须包含隐藏目录 .github。"
Write-Host "3. 打开 Actions -> Build Qdrant ARM64 64K offline image -> Run workflow。"
Write-Host "4. 绿色通过后下载 qdrant-v1.18.3-arm64-64k-offline.zip。"

