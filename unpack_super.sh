#!/usr/bin/env bash
set -e
BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
export PATH="$BIN_DIR:$PATH"

usage() { echo "用法: $0 <super.img> <out_dir>"; exit 2; }
[ $# -lt 2 ] && usage
SUPER="$1"; OUT="$2"

command -v lpunpack >/dev/null 2>&1 || { echo "❌ 缺少 lpunpack，请放入 $BIN_DIR"; exit 1; }

mkdir -p "$OUT"
lpunpack "$SUPER" "$OUT"
echo "✅ 分解完成：$OUT"
