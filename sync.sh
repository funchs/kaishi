#!/usr/bin/env bash
# 同步脚本到所有远程位置（Git/Gist/CDN）
set -euo pipefail

GIST_ID="9848b313c7fd00253543d2db032b5dce"

echo "==> 1/3 推送到 GitHub repo"
git push origin main

echo "==> 2/3 同步到 Gist (备用镜像)"
gh gist edit "$GIST_ID" -f install.sh install.sh
gh gist edit "$GIST_ID" -f install.ps1 install.ps1

echo "==> 3/3 清理 jsDelivr CDN 缓存"
curl -fsSL "https://purge.jsdelivr.net/gh/funchs/kaishi@main/install.sh" >/dev/null
curl -fsSL "https://purge.jsdelivr.net/gh/funchs/kaishi@main/install.ps1" >/dev/null

echo "✓ 全部同步完成"
