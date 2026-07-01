#!/bin/sh
# pack_dat.sh — 自动打包 img 为 dat 格式
# 依赖: python3/python + img2sdat.py (放在 tool/bin 或 PATH)
# 输出: ./zlo_pack/<part>.new.dat / .transfer.list / .patch.dat
# 支持交互选择/批量/参数模式
# 无需 sudo，/bin/sh 兼容

set -eu

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "❌ $*" >&2; exit 1; }
info(){ echo "🔧 $*"; }

# 找 python
PY="python3"; need_cmd "$PY" || PY="python"
need_cmd "$PY" || die "未找到 python/python3"

# 找 img2sdat.py
if [ -f "$BIN_DIR/img2sdat.py" ]; then
  IMG2SDAT="$BIN_DIR/img2sdat.py"
elif [ -f "$SCRIPT_DIR/img2sdat.py" ]; then
  IMG2SDAT="$SCRIPT_DIR/img2sdat.py"
else
  IMG2SDAT="$(command -v img2sdat.py 2>/dev/null || true)"
  [ -n "$IMG2SDAT" ] || die "缺少 img2sdat.py，请放到 $BIN_DIR 或加入 PATH"
fi

OUT_DIR="$PROJECT_ROOT/zlo_pack"
mkdir -p "$OUT_DIR"

usage(){
  cat <<'U'
用法:
  ./tool/pack_dat.sh                     # 自动扫描并交互式打包
  ./tool/pack_dat.sh system.img vendor.img  # 打包指定 img
  ./tool/pack_dat.sh --out outdir           # 指定输出目录
  ./tool/pack_dat.sh --all                  # 全部打包（非交互）
U
  exit 2
}

MODE=""
FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2;;
    --out=*) OUT_DIR="${1#*=}"; shift;;
    --all) MODE="all"; shift;;
    -h|--help) usage;;
    *.img) FILES="${FILES}
$1"; shift;;
    *) echo "未知参数: $1"; usage;;
  esac
done

# 扫描所有 img 文件
scan_img(){
  {
    find "$PROJECT_ROOT" -maxdepth 1 -type f -name '*.img' -printf '%P\n' 2>/dev/null
    find "$PROJECT_ROOT" -maxdepth 2 -mindepth 2 -type f -name '*.img' -printf '%P\n' 2>/dev/null
  } | sort -V
}
LIST="$(scan_img)"
[ -n "$LIST" ] || die "未找到 .img 文件"

if [ -z "$FILES" ]; then
  if [ "$MODE" = "all" ]; then
    FILES="$LIST"
  elif [ -t 0 ] && [ -t 1 ]; then
    echo "检测到以下镜像："
    i=0
    printf "%s\n" "$LIST" | while read -r rel; do
      i=$((i+1)); printf "  %d) %s\n" "$i" "$rel"
    done
    echo
    echo "1) 全部打包"
    echo "2) 按序号选择（支持 1,3-5）"
    printf "输入 [1/2，默认1]: "
    read sel || sel=1
    case "$sel" in 2)
      printf "输入要打包的序号："
      read idxs || die "未输入序号"
      FILES=""
      for tok in $(echo "$idxs" | tr ',' ' '); do
        case "$tok" in
          *-*) a=$(echo "$tok"|cut -d- -f1); b=$(echo "$tok"|cut -d- -f2)
               n="$a"
               while [ "$n" -le "$b" ]; do
                 FILES="${FILES}
$(printf "%s\n" "$LIST" | sed -n "${n}p")"
                 n=$((n+1))
               done;;
          *) FILES="${FILES}
$(printf "%s\n" "$LIST" | sed -n "${tok}p")";;
        esac
      done;;
    ""|1|*) FILES="$LIST";;
    esac
  else
    FILES="$LIST"
  fi
fi

mkdir -p "$OUT_DIR"
echo "📦 输出目录: $OUT_DIR"
count=$(printf "%s\n" "$FILES" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
i=0

printf "%s\n" "$FILES" | sed '/^[[:space:]]*$/d' | while read -r img; do
  [ -n "$img" ] || continue
  i=$((i+1))
  base="$(basename "$img" .img)"
  info "[$i/$count] 打包 $base.img ..."
  outdir="$OUT_DIR/$base"
  mkdir -p "$outdir"
  (
    cd "$outdir"
    $PY "$IMG2SDAT" "$PROJECT_ROOT/$img" -v 4 -p "$base" >/dev/null 2>&1 \
      && echo "✅ $base 打包完成 → $outdir" \
      || echo "❌ $base 打包失败"
  )
done

echo "🎉 全部完成！输出路径: $OUT_DIR"
