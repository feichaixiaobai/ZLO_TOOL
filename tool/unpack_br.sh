#!/usr/bin/env bash
set -e
BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
export PATH="$BIN_DIR:$PATH"

usage() { echo "用法: $0 <file.br> [out_file]"; exit 2; }
[ $# -lt 1 ] && usage
IN="$1"; OUT="${2:-${IN%.br}}"

command -v brotli >/dev/null 2>&1 || { echo "❌ 缺少 brotli，请放入 $BIN_DIR"; exit 1; }

brotli -d -o "$OUT" "$IN"
echo "✅ 已解压：$OUT"
