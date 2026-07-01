#!/bin/sh
# unpack_payload.sh — 分解 payload.bin，带进度条显示
# 依赖：payload-dumper-go（放在 tool/bin 或 PATH）
# 输出目录：./zlo_pack/
# 支持交互式选择、--parts、--all、--payload 参数等
# 兼容 /bin/sh；无需 sudo

set -eu

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "❌ $*" >&2; exit 1; }
info(){ echo "🔧 $*"; }

# 找 payload-dumper-go
if [ -x "$BIN_DIR/payload-dumper-go" ]; then
  PDG="$BIN_DIR/payload-dumper-go"
else
  PDG="$(command -v payload-dumper-go 2>/dev/null || true)"
fi
[ -n "$PDG" ] || die "缺少 payload-dumper-go，请放入 tool/bin 或加入 PATH"

OUT_DIR="$PROJECT_ROOT/zlo_pack"
PAYLOAD_IN=""
MODE=""         # all | parts
PARTS_CSV=""

mkdir -p "$OUT_DIR"

# ---------- 参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --payload) PAYLOAD_IN="$2"; shift 2;;
    --payload=*) PAYLOAD_IN="${1#*=}"; shift;;
    --all) MODE="all"; shift;;
    --parts) MODE="parts"; PARTS_CSV="$2"; shift 2;;
    --parts=*) MODE="parts"; PARTS_CSV="${1#*=}"; shift;;
    --out) OUT_DIR="$2"; shift 2;;
    --out=*) OUT_DIR="${1#*=}"; shift;;
    -h|--help)
      echo "用法: $0 [--payload <path>] [--all | --parts \"system,vendor\"] [--out dir]"
      exit 0;;
    *) echo "未知参数: $1"; exit 2;;
  esac
done

# ---------- 自动找 payload.bin ----------
find_payload() {
  {
    find "$PROJECT_ROOT" -maxdepth 1 -type f -name 'payload.bin' -printf '%P\n' 2>/dev/null
    find "$PROJECT_ROOT" -maxdepth 2 -mindepth 2 -type f -name 'payload.bin' -printf '%P\n' 2>/dev/null
  } | sort -V
}

if [ -z "$PAYLOAD_IN" ]; then
  LIST="$(find_payload)"
  [ -n "$LIST" ] || die "未找到 payload.bin"
  CNT=$(printf "%s\n" "$LIST" | wc -l | tr -d ' ')
  if [ "$CNT" -gt 1 ] && [ -t 0 ]; then
    echo "检测到多个 payload.bin，请选择："
    i=0
    printf "%s\n" "$LIST" | while read -r rel; do
      i=$((i+1)); printf "  %d) %s\n" "$i" "$rel"
    done
    printf "输入序号 [1-%d，默认1]: " "$CNT"
    read sel || sel=1
    case "$sel" in ''|*[!0-9]*) sel=1;; esac
    PAYLOAD_IN="$PROJECT_ROOT/$(printf "%s\n" "$LIST" | sed -n "${sel}p")"
  else
    PAYLOAD_IN="$PROJECT_ROOT/$(printf "%s\n" "$LIST" | head -n1)"
  fi
fi

[ -f "$PAYLOAD_IN" ] || die "payload.bin 不存在: $PAYLOAD_IN"

# ---------- 列出可用分区 ----------
PARTS_RAW="$("$PDG" -l "$PAYLOAD_IN" 2>/dev/null || true)"
[ -n "$PARTS_RAW" ] || die "无法列出分区，请确认工具可用。"

PARTS=$(printf "%s\n" "$PARTS_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep .)
count=$(printf "%s\n" "$PARTS" | wc -l | tr -d ' ')

# ---------- 交互 ----------
if [ -z "$MODE" ] && [ -t 0 ]; then
  echo "可解包分区："
  i=0
  printf "%s\n" "$PARTS" | while read -r p; do
    i=$((i+1)); printf "  %d) %s\n" "$i" "$p"
  done
  echo
  echo "1) 全部解包"
  echo "2) 按序号选择"
  printf "输入 [1/2，默认1]: "
  read sel || sel=1
  case "$sel" in 2) MODE="parts";; *) MODE="all";; esac
  if [ "$MODE" = "parts" ]; then
    printf "输入要解包的序号（支持1,3-5）："
    read idxs || idxs=""
    [ -n "$idxs" ] || die "未输入序号"
    PARTS_CSV=""
    for tok in $(echo "$idxs" | tr ',' ' '); do
      case "$tok" in
        *-*) a=$(echo "$tok"|cut -d- -f1); b=$(echo "$tok"|cut -d- -f2)
             [ "$a" -ge 1 ] && [ "$b" -le "$count" ] || die "范围越界"
             seq "$a" "$b" | while read -r n; do name=$(printf "%s\n" "$PARTS"|sed -n "${n}p"); PARTS_CSV="${PARTS_CSV}${PARTS_CSV:+,}$name"; done;;
        *) name=$(printf "%s\n" "$PARTS"|sed -n "${tok}p"); PARTS_CSV="${PARTS_CSV}${PARTS_CSV:+,}$name";;
      esac
    done
  fi
fi

[ -n "$MODE" ] || MODE="all"

# ---------- 进度条函数 ----------
show_progress() {
  cur=$1; total=$2
  percent=$((cur * 100 / total))
  bars=$((percent / 2))
  printf "\r进度: ["
  i=1; while [ $i -le 50 ]; do
    if [ $i -le $bars ]; then printf "#"; else printf " "; fi
    i=$((i+1))
  done
  printf "] %3d%%" "$percent"
}

# ---------- 执行解包 ----------
cd "$OUT_DIR"
echo "📦 解包: $PAYLOAD_IN"
if [ "$MODE" = "all" ]; then
  echo "🔧 解包全部分区 ($count 个)..."
  idx=0
  printf "%s\n" "$PARTS" | while read -r part; do
    idx=$((idx+1))
    show_progress "$idx" "$count"
    "$PDG" -p "$part" "$PAYLOAD_IN" >/dev/null 2>&1 || printf '\n⚠️ %s 解包失败\n' "$part"
  done
else
  chosen=$(echo "$PARTS_CSV" | tr ',' '\n')
  total=$(printf "%s\n" "$chosen" | wc -l | tr -d ' ')
  echo "🔧 解包指定分区 ($total 个): $PARTS_CSV"
  idx=0
  echo "$chosen" | while read -r part; do
    idx=$((idx+1))
    show_progress "$idx" "$total"
    "$PDG" -p "$part" "$PAYLOAD_IN" >/dev/null 2>&1 || printf '\n⚠️ %s 解包失败\n' "$part"
  done
fi
printf "\n✅ 完成！输出目录: %s\n" "$OUT_DIR"
