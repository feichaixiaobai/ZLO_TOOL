#!/usr/bin/env bash
set -e
usage() { echo "用法: $0 <file.bat> <out_dir>"; exit 2; }
[ $# -lt 2 ] && usage
BAT="$1"; OUT="$2"

mkdir -p "$OUT"
cp -f "$BAT" "$OUT/"
echo "✅ 已复制 bat 文件到：$OUT"
