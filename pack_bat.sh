#!/usr/bin/env bash
set -e
usage() { echo "用法: $0 <out.bat> <src1.bat> [src2.bat ...]"; exit 2; }
[ $# -lt 2 ] && usage
OUT="$1"; shift

: > "$OUT"
for f in "$@"; do
  [ -f "$f" ] || continue
  echo "REM ===== $(basename "$f") =====" >> "$OUT"
  cat "$f" >> "$OUT"
  echo >> "$OUT"
done

echo "✅ 打包完成：$OUT"
