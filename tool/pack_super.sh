#!/usr/bin/env bash
set -e
BIN_DIR="$(cd "$(dirname "$0")/../bin" && pwd)"
export PATH="$BIN_DIR:$PATH"

usage() { echo "用法: $0 <parts_dir> <out_super.img> [size_mb]"; exit 2; }
[ $# -lt 2 ] && usage
PDIR="$1"; OUT="$2"; SIZE_MB="${3:-8192}"

command -v lpmake >/dev/null 2>&1 || { echo "❌ 缺少 lpmake，请放入 $BIN_DIR"; exit 1; }

ARGS=( --metadata-size 65536 --super-name super --device-size $((SIZE_MB*1024*1024)) )

for f in "$PDIR"/*.img; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .img)"
  size=$(stat -c%s "$f")
  ARGS+=( --partition "$name:readonly" --image "$name=$f" --partition-size "$name:$size" )
done

lpmake "${ARGS[@]}" --output "$OUT"
echo "✅ 已打包 super 镜像：$OUT"
