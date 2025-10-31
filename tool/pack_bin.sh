#!/usr/bin/env bash
set -e
usage() { echo "用法: $0 <out.bin> <part1> [part2 ...]"; exit 2; }
[ $# -lt 2 ] && usage
OUT="$1"; shift

: > "$OUT"
for f in "$@"; do
  [ -f "$f" ] || { echo "跳过不存在的文件: $f"; continue; }
  cat "$f" >> "$OUT"
done
echo "✅ 已合并生成：$OUT"
