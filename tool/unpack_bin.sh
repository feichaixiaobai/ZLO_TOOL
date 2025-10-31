#!/usr/bin/env bash
set -e
BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
export PATH="$BIN_DIR:$PATH"

usage() { echo "用法: $0 <file.bin> <out_dir>"; exit 2; }
[ $# -lt 2 ] && usage
BIN="$1"; OUT="$2"
mkdir -p "$OUT"

if command -v binwalk >/dev/null 2>&1; then
  binwalk -e --directory "$OUT" "$BIN"
  echo "✅ 使用 binwalk 提取到：$OUT"
else
  cp -f "$BIN" "$OUT/"
  echo "⚠️ 未检测到 binwalk，仅复制文件到：$OUT"
fi
