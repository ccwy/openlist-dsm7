#!/bin/bash
#
# sync-binaries.sh — 检测 OpenList 上游新版本，下载全部二进制，打包 SPK，全部发到 Releases
#
# 流程：
#   1. 检测上游最新版本（或用指定版本）
#   2. 下载该版本所有二进制文件到临时目录
#   3. 用其中的 linux-amd64 / linux-arm64 打包成 SPK
#   4. 输出所有文件路径，供 CI 上传到 GitHub Releases
#   5. 仓库中只保留 MD5 校验文件（几百字节）用于版本追踪
#
# Usage:
#   ./scripts/sync-binaries.sh                    # 自动检测最新版本
#   ./scripts/sync-binaries.sh 4.2.9              # 指定版本
#
# Environment:
#   GITHUB_TOKEN   — GitHub API token (避免 rate limit)
#
set -euo pipefail

# ── 配置 ─────────────────────────────────────────────────────────────
UPSTREAM_REPO="openlistteam/openlist"
UPSTREAM_API="https://api.github.com/repos/${UPSTREAM_REPO}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKSUMS_DIR="${REPO_ROOT}/checksums"   # MD5 文件存入仓库（很小）

# GitHub API 认证
AUTH_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

# ── 工具函数 ─────────────────────────────────────────────────────────
log() { echo "[$(date +'%H:%M:%S')] $*"; }
err() { echo "[$(date +'%H:%M:%S')] ERROR: $*" >&2; }
die() { err "$@"; exit 1; }

get_latest_version() {
  local tag
  tag=$(curl -sL "${AUTH_ARGS[@]}" "${UPSTREAM_API}/releases/latest" \
    | jq -r '.tag_name // empty')
  [ -z "$tag" ] && die "无法获取上游最新版本"
  echo "${tag#v}"
}

get_release_assets() {
  local version="$1"
  curl -sL "${AUTH_ARGS[@]}" "${UPSTREAM_API}/releases/tags/v${version}" \
    | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)\t\(.size)"'
}

# 检查本仓库是否已处理过该版本
has_version() {
  local version="$1"
  git -C "$REPO_ROOT" tag -l "v${version}" | grep -q . && return 0
  [ -d "${CHECKSUMS_DIR}/v${version}" ] && return 0
  return 1
}

download_file() {
  local url="$1" dest="$2"
  local filename
  filename="$(basename "$url")"
  log "  Download: $filename"
  curl -sL --retry 3 --retry-delay 5 "$url" -o "$dest"
  local size
  size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
  log "  OK: $filename (${size} bytes)"
}

extract_binary() {
  local tarball="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  tar xzf "$tarball" -C "$dest_dir" 2>/dev/null
  local binary
  binary=$(find "$dest_dir" -name "openlist" -type f | head -1)
  [ -z "$binary" ] && die "Binary not found in: $tarball"
  chmod +x "$binary"
  echo "$binary"
}

# ── 参数解析 ─────────────────────────────────────────────────────────
TARGET_VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    [0-9]*) TARGET_VERSION="$1"; shift ;;
    *) shift ;;
  esac
done

# 临时工作目录（脚本结束后自动清理）
WORK_DIR=$(mktemp -d)
DOWNLOAD_DIR="${WORK_DIR}/downloads"       # 上游下载的所有二进制
SPK_OUTPUT_DIR="${WORK_DIR}/spk"           # 打包出的 SPK
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "$DOWNLOAD_DIR" "$SPK_OUTPUT_DIR"

# ── Step 1: 确定版本号 ──────────────────────────────────────────────
if [ -z "$TARGET_VERSION" ]; then
  log "Detecting latest upstream version..."
  TARGET_VERSION=$(get_latest_version)
  log "Latest upstream: v${TARGET_VERSION}"
else
  log "Specified version: v${TARGET_VERSION}"
fi

# ── Step 2: 检查是否已处理过 ────────────────────────────────────────
if has_version "$TARGET_VERSION"; then
  log "Version v${TARGET_VERSION} already processed, skipping"
  echo "SKIP:${TARGET_VERSION}"
  exit 0
fi

log "New version v${TARGET_VERSION} detected, starting sync..."

# ── Step 3: 获取 release assets 列表 ────────────────────────────────
log "Fetching release assets..."
ASSETS_OUTPUT=$(get_release_assets "$TARGET_VERSION")
[ -z "$ASSETS_OUTPUT" ] && die "No assets found for v${TARGET_VERSION}"

# ── Step 4: 下载该版本所有文件到临时目录 ────────────────────────────
log "Downloading ALL assets for v${TARGET_VERSION} to temp dir..."

DOWNLOAD_COUNT=0
while IFS=$'\t' read -r name url size; do
  [ -z "$name" ] && continue
  download_file "$url" "${DOWNLOAD_DIR}/${name}"
  DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
done <<< "$ASSETS_OUTPUT"

log "Downloaded ${DOWNLOAD_COUNT} files total"

# ── Step 5: 保存 MD5 校验文件到仓库（仅几百字节）──────────────────
log "Saving MD5 checksum files to repo..."
VERSION_CHECKSUM_DIR="${CHECKSUMS_DIR}/v${TARGET_VERSION}"
mkdir -p "$VERSION_CHECKSUM_DIR"

while IFS=$'\t' read -r name url size; do
  [ -z "$name" ] && continue
  if [[ "$name" == md5*.txt ]]; then
    cp "${DOWNLOAD_DIR}/${name}" "${VERSION_CHECKSUM_DIR}/${name}"
  fi
done <<< "$ASSETS_OUTPUT"

log "Checksum files saved to ${VERSION_CHECKSUM_DIR}"

# ── Step 6: 打包 SPK ────────────────────────────────────────────────
log "Building SPK packages..."
chmod +x "${REPO_ROOT}/build-spk.sh"

# x64 SPK
AMD64_TARBALL="${DOWNLOAD_DIR}/openlist-linux-amd64.tar.gz"
if [ -f "$AMD64_TARBALL" ]; then
  log "  Building x64 SPK..."
  EXTRACT_DIR=$(mktemp -d)
  BINARY=$(extract_binary "$AMD64_TARBALL" "$EXTRACT_DIR")
  (cd "$REPO_ROOT" && ./build-spk.sh "$TARGET_VERSION" "x64" "$BINARY")
  SPK_FILE="openlist_x64_${TARGET_VERSION}.spk"
  [ -f "${REPO_ROOT}/${SPK_FILE}" ] && mv "${REPO_ROOT}/${SPK_FILE}" "${SPK_OUTPUT_DIR}/"
  rm -rf "$EXTRACT_DIR"
  log "  OK: ${SPK_FILE}"
fi

# arm64 SPK
ARM64_TARBALL="${DOWNLOAD_DIR}/openlist-linux-arm64.tar.gz"
if [ -f "$ARM64_TARBALL" ]; then
  log "  Building arm64 SPK..."
  EXTRACT_DIR=$(mktemp -d)
  BINARY=$(extract_binary "$ARM64_TARBALL" "$EXTRACT_DIR")
  (cd "$REPO_ROOT" && ./build-spk.sh "$TARGET_VERSION" "arm64" "$BINARY")
  SPK_FILE="openlist_arm64_${TARGET_VERSION}.spk"
  [ -f "${REPO_ROOT}/${SPK_FILE}" ] && mv "${REPO_ROOT}/${SPK_FILE}" "${SPK_OUTPUT_DIR}/"
  rm -rf "$EXTRACT_DIR"
  log "  OK: ${SPK_FILE}"
fi

# ── Step 7: 输出结果摘要 ────────────────────────────────────────────
log "========================================"
log "Sync complete for v${TARGET_VERSION}"
log "  Binaries (temp, for Release upload): ${DOWNLOAD_DIR}"
log "    ${DOWNLOAD_COUNT} files from upstream"
log "  SPK (temp, for Release upload): ${SPK_OUTPUT_DIR}"
for f in "$SPK_OUTPUT_DIR"/*.spk; do
  [ -f "$f" ] || continue
  log "    $(basename "$f") ($(du -h "$f" | cut -f1))"
done
log "  Checksums (in repo): ${VERSION_CHECKSUM_DIR}"
log "  Temp dir (auto-cleaned on exit): ${WORK_DIR}"
log "========================================"

# 输出给 CI 用的结果
echo "DONE:${TARGET_VERSION}"
echo "DOWNLOAD_DIR:${DOWNLOAD_DIR}"
echo "SPK_DIR:${SPK_OUTPUT_DIR}"
