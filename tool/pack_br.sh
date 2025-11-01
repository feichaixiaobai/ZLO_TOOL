#!/bin/sh
# pack_br.sh — 批量把 *.dat 打包为 *.dat.br（Brotli）
# 依赖：brotli（优先使用 tool/bin/ 里的二进制）
# 兼容：/bin/sh；无需 sudo
#
# 功能：
#   * 零参数交互：扫描项目内 *.dat → 选择“全部/按序号” → 选择压缩等级 → 是否删除源文件
#   * 非交互参数：
#       pack_br.sh file1.dat file2.dat ...
#       --all                # 扫描到的全部 .dat
#       --quality N          # 压缩等级（0-11，默认 5）
#       --delete | -j        # 打包后删除源 .dat
#       --force              # 覆盖已存在的 .br
#       --out DIR            # 输出到指定目录，保持相对目录结构

set -eu

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "❌ $*" >&2; exit 1; }
info(){ echo "🔧 $*"; }

need_cmd brotli || die "缺少 brotli，请放入 $BIN_DIR 或加入 PATH"

QUALITY=5          # brotli 0..11，越大压缩越高耗时越长
DELETE_SRC=0
FORCE=0
MODE=""            # ""=交互扫描；"all"=全扫；"files"=显式文件
OUT_DIR=""         # 为空则与源文件同目录

FILES=""

usage(){
  cat <<'U'
用法:
  ./tool/pack_br.sh                      # 交互式打包
  ./tool/pack_br.sh a.dat b.dat          # 指定文件打包
  选项:
    --all                扫描到的全部 .dat（非交互）
    --quality N          压缩等级 0..11（默认 5）
    --delete, -j         打包完成后删除源 .dat
    --force              覆盖已存在的 .br
    --out DIR            输出到指定目录（保留相对路径）
U
  exit 2
}

# ---------- 解析参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE="all"; shift;;
    --quality) QUALITY="${2:-}"; shift 2;;
    --quality=*) QUALITY="${1#*=}"; shift;;
    --delete|-j) DELETE_SRC=1; shift;;
    --force) FORCE=1; shift;;
    --out) OUT_DIR="${2:-}"; shift 2;;
    --out=*) OUT_DIR="${1#*=}"; shift;;
    -h|--help) usage;;
    -*)
      echo "未知参数: $1"; usage;;
    *)
      MODE="files"
      FILES="${FILES}
$1"
      shift;;
  esac
done

# 合法化 QUALITY
case "$QUALITY" in *[!0-9]*|'') QUALITY=5;; esac
[ "$QUALITY" -ge 0 ] 2>/dev/null || QUALITY=5
[ "$QUALITY" -le 11 ] 2>/dev/null || QUALITY=11

# ---------- 扫描 .dat ----------
scan_dat(){
  {
    find "$PROJECT_ROOT" -maxdepth 1 -type f -name '*.dat' -printf '%P\n' 2>/dev/null
    find "$PROJECT_ROOT" -maxdepth 2 -mindepth 2 -type f -name '*.dat' -printf '%P\n' 2>/dev/null
  } | sort -V
}

LIST="$(scan_dat)"
[ -n "$LIST" ] || die "未在项目中找到 .dat 文件"

# ---------- 交互选择 ----------
if [ "$MODE" = "files" ]; then
  # 标准化为相对路径
  SEL="$(echo "$FILES" | sed '/^[[:space:]]*$/d' | while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      /*) rel="$(echo "$f" | sed "s#^$PROJECT_ROOT/##")" ;;
      *)  rel="$f" ;;
    esac
    [ -f "$PROJECT_ROOT/$rel" ] || die "文件不存在：$f"
    printf "%s\n" "$rel"
  done | awk '!seen[$0]++')"
elif [ "$MODE" = "all" ]; then
  SEL="$LIST"
else
  if [ -t 0 ] && [ -t 1 ]; then
    echo "检测到以下 .dat 文件："
    i=0
    printf "%s\n" "$LIST" | while IFS= read -r rel; do
      i=$((i+1)); printf "  %d) %s\n" "$i" "$rel"
    done
    COUNT="$i"
    echo
    echo "1) 全部打包"
    echo "2) 按序号选择（支持 1,3-5）"
    printf "输入 [1/2，默认1]: "
    read sel || sel=1
    if [ "$sel" = "2" ]; then
      printf "输入要打包的序号："
      read idxs || die "未输入序号"
      SEL=""
      for tok in $(echo "$idxs" | tr ',' ' '); do
        case "$tok" in
          *-*) a=$(echo "$tok"|cut -d- -f1); b=$(echo "$tok"|cut -d- -f2)
               [ "$a" -ge 1 ] && [ "$b" -le "$COUNT" ] || die "范围越界: $tok"
               seq "$a" "$b" | while read -r n; do SEL="${SEL}
$(printf "%s\n" "$LIST" | sed -n "${n}p")"; done;;
          *) SEL="${SEL}
$(printf "%s\n" "$LIST" | sed -n "${tok}p")";;
        esac
      done
    else
      SEL="$LIST"
    fi
    # 询问压缩等级与是否删除源文件
    echo
    printf "压缩等级 [0-11，默认 %s]: " "$QUALITY"
    read q || true
    case "$q" in *[!0-9]*|'') : ;; *) QUALITY="$q";; esac
    [ "$QUALITY" -ge 0 ] 2>/dev/null || QUALITY=5
    [ "$QUALITY" -le 11 ] 2>/dev/null || QUALITY=11

    printf "打包后删除源文件？(y/N): "
    read yn || true
    case "$yn" in y|Y|yes|YES) DELETE_SRC=1 ;; *) : ;; esac
  else
    SEL="$LIST"
  fi
fi

# ---------- 执行打包 ----------
total=$(printf "%s\n" "$SEL" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
[ "$total" -gt 0 ] || die "无待打包文件"

packed=0; skipped=0; removed=0

echo "$SEL" | sed '/^[[:space:]]*$/d' | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  in="$PROJECT_ROOT/$rel"

  # 确定输出路径
  if [ -n "$OUT_DIR" ]; then
    out="$OUT_DIR/$rel.br"
    mkdir -p "$(dirname "$out")"
  else
    out="${in}.br"
  fi

  # 存在则覆盖与否
  if [ -f "$out" ] && [ "$FORCE" -ne 1 ]; then
    echo "⚠️ 跳过（已存在）：${out#$PROJECT_ROOT/}"
    skipped=$((skipped+1))
    continue
  fi

  if brotli -q "$QUALITY" "$in" -o "$out" >/dev/null 2>&1; then
    echo "✅ 打包：${rel}  →  ${out#$PROJECT_ROOT/}  (q=$QUALITY)"
    packed=$((packed+1))
    if [ "$DELETE_SRC" -eq 1 ]; then
      rm -f "$in" && removed=$((removed+1)) || true
    fi
  else
    echo "❌ 失败：$rel" >&2
  fi
done

echo "—— 统计 ——"
echo "总计：$total  成功：$packed  跳过：$skipped  删除源：$removed"
