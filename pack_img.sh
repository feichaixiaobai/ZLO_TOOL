#!/usr/bin/env bash
set -e
BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
export PATH="$BIN_DIR:$PATH"

usage() {
  echo "用法: $0 <root_dir> <out_img> [size_mb]"
  echo "例子: $0 ./system_root ./system_raw.img 2048"
  exit 2
}

[ $# -lt 2 ] && usage
ROOT="$1"
OUT="$2"
SIZE_MB="${3:-1024}"

[ -d "$ROOT" ] || { echo "❌ 目录不存在: $ROOT"; exit 1; }

# 检查 mkfs.ext4
command -v mkfs.ext4 >/dev/null 2>&1 || { echo "❌ 缺少 mkfs.ext4，请放入 $BIN_DIR"; exit 1; }

dd if=/dev/zero of="$OUT" bs=1M count="$SIZE_MB" status=none
mkfs.ext4 -F "$OUT" >/dev/null

TMP=$(mktemp -d)
sudo mount -o loop "$OUT" "$TMP"
sudo cp -a "$ROOT"/. "$TMP"/
sudo umount "$TMP"
rmdir "$TMP"

echo "✅ 已打包镜像: $OUT (${SIZE_MB}MB)"
