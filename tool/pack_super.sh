#!/bin/sh
# pack_super.sh — 零参数自动把若干分区镜像打成 super.img（无需 root/sudo）
# 行为：
#   * 默认从 ./zlo_pack/ 读取分区镜像（优先 *.img；若只有 *.sparse.img 自动解稀疏）
#   * 交互选择：全部打包 / 指定序号（支持 1,3-5）
#   * 自动计算 --device-size（总和 +15% 余量，Min 1GiB，4MiB 对齐）
#   * 输出：./zlo_super/super.img
# 依赖：lpmake（必须）；simg2img（当存在 .sparse.img 且无 .img 时需要）
# 兼容：/bin/sh（dash），无需 sudo

set -eu

PROJECT_ROOT="$(pwd)"
PACK_DIR="$PROJECT_ROOT/zlo_pack"
OUT_DIR="$PROJECT_ROOT/zlo_super"
OUT_SUPER="$OUT_DIR/super.img"

# 优先从 tool/../bin 找可执行文件
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "🔧 $*"; }

need_cmd lpmake || die "缺少 lpmake，请将其放到 $BIN_DIR 或加入 PATH"

[ -d "$PACK_DIR" ] || die "未找到目录：$PACK_DIR（请先用打包脚本生成分区镜像）"
mkdir -p "$OUT_DIR"

# ---------- 枚举候选分区 ----------
# 规则：同名同时存在 <name>.img 与 <name>.sparse.img 时优先 RAW（.img）
# 若只有 .sparse.img 则记录为稀疏来源，稍后自动用 simg2img 转换为临时 RAW
NAMES=""
i=0

# 收集 RAW
for f in "$PACK_DIR"/*.img; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    *.sparse.img) : ;;  # 稍后处理
    *)
      name="${base%.img}"
      i=$((i+1))
      NAMES="${NAMES}
$i:$name:raw"
      ;;
  esac
done

# 收集仅有 SPARSE 的（且没有同名 RAW）
for f in "$PACK_DIR"/*.sparse.img; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .sparse.img)"
  # 如果 RAW 已存在则跳过
  if [ -f "$PACK_DIR/$name.img" ]; then
    continue
  fi
  i=$((i+1))
  NAMES="${NAMES}
$i:$name:sparse"
done

[ "$i" -gt 0 ] || die "zlo_pack 下未找到可用的分区镜像（*.img / *.sparse.img）"
count="$i"

idx_to_tuple() {
  # 输出：name:type ；type in {raw|sparse}
  echo "$NAMES" | awk -F: -v k="$1" 'NF==3 && $1==k {print $2 ":" $3}'
}
idx_to_path() {
  name="$1"; type="$2"
  if [ "$type" = "raw" ]; then
    printf "%s\n" "$PACK_DIR/$name.img"
  else
    printf "%s\n" "$PACK_DIR/$name.sparse.img"
  fi
}

echo "可用分区列表："
echo "$NAMES" | sed '/^[[:space:]]*$/d' | sed 's/^/  /' | sed 's/:raw$/ (RAW)/; s/:sparse$/ (SPARSE)/'

# ---------- 交互 1：选择范围（全部 / 按序号） ----------
if [ -t 0 ] && [ -t 1 ]; then
  echo "请选择打包范围："
  echo "  1) 全部分区"
  echo "  2) 按序号选择分区（支持 1,3-5）"
  printf "输入编号 [1/2，默认1]: "
  read sel || true
else
  sel="1"
fi

SELECTED_INDEXES=""
add_idx() {
  case ",$SELECTED_INDEXES," in *",$1,"*) :;; *) SELECTED_INDEXES="${SELECTED_INDEXES}${SELECTED_INDEXES:+,}$1";; esac
}

if [ "$sel" = "2" ]; then
  printf "请输入要打包的序号（1~%s），支持逗号与范围： " "$count"
  read s || true
  [ -n "$s" ] || die "未输入有效序号"
  IFS=','; set -- $s; IFS=' '
  for tok in "$@"; do
    tok="$(echo "$tok" | tr -d '[:space:]')"
    [ -n "$tok" ] || continue
    case "$tok" in
      *-*)
        a="$(echo "$tok" | awk -F- '{print $1}')"
        b="$(echo "$tok" | awk -F- '{print $2}')"
        echo "$a" | grep -Eq '^[0-9]+$' || die "非法范围：$tok"
        echo "$b" | grep -Eq '^[0-9]+$' || die "非法范围：$tok"
        [ "$a" -ge 1 ] && [ "$b" -le "$count" ] || die "范围越界：$tok"
        if [ "$a" -le "$b" ]; then
          k="$a"; while [ "$k" -le "$b" ]; do add_idx "$k"; k=$((k+1)); done
        else
          k="$a"; while [ "$k" -ge "$b" ]; do add_idx "$k"; k=$((k-1)); done
        fi
        ;;
      *)
        echo "$tok" | grep -Eq '^[0-9]+$' || die "非法序号：$tok"
        [ "$tok" -ge 1 ] && [ "$tok" -le "$count" ] || die "序号越界：$tok"
        add_idx "$tok"
        ;;
    esac
  done
else
  # 全部
  k=1; while [ "$k" -le "$count" ]; do add_idx "$k"; k=$((k+1)); done
fi

# ---------- 处理选择集：准备 RAW 清单（必要时解稀疏） ----------
TMPDIR_CONV=""
RAW_LIST_NAMES=""
RAW_LIST_PATHS=""
TOTAL_BYTES=0

need_sparse2raw=0
echo "$SELECTED_INDEXES" | awk -F, '{for(i=1;i<=NF;i++) print $i}' | while read idx; do
  [ -n "$idx" ] || continue
  tup="$(idx_to_tuple "$idx")" || exit 1
  name="$(echo "$tup" | awk -F: '{print $1}')"
  type="$(echo "$tup" | awk -F: '{print $2}')"
  src="$(idx_to_path "$name" "$type")"
  [ -f "$src" ] || die "找不到源文件：$src"

  if [ "$type" = "raw" ]; then
    path="$src"
  else
    # 需要把 sparse 转 raw
    need_cmd simg2img || die "已选择稀疏镜像，但缺少 simg2img，请安装或放到 $BIN_DIR"
    if [ -z "$TMPDIR_CONV" ]; then
      TMPDIR_CONV="$(mktemp -d)"
      trap 'rm -rf "$TMPDIR_CONV" 2>/dev/null || true' EXIT
    fi
    path="$TMPDIR_CONV/$name.raw.img"
    echo "ℹ️  解稀疏：$src → $path"
    simg2img "$src" "$path" >/dev/null 2>&1 || die "simg2img 转换失败：$src"
    need_sparse2raw=1
  fi

  size="$(wc -c < "$path" | tr -d ' ')"
  TOTAL_BYTES=$((TOTAL_BYTES + size))

  RAW_LIST_NAMES="${RAW_LIST_NAMES}${RAW_LIST_NAMES:+ }$name"
  RAW_LIST_PATHS="${RAW_LIST_PATHS}${RAW_LIST_PATHS:+ }$path"
done

# ---------- 交互 2：确认输出路径（可直接回车使用默认） ----------
if [ -t 0 ] && [ -t 1 ]; then
  printf "输出路径（默认 %s）: " "$OUT_SUPER"
  read custom || true
  if [ -n "$custom" ]; then
    case "$custom" in
      */) OUT_SUPER="${custom%/}/super.img" ;;
      *.img) OUT_SUPER="$custom" ;;
      *) OUT_SUPER="$custom/super.img" ;;
    esac
    outdir="$(dirname "$OUT_SUPER")"
    mkdir -p "$outdir"
  fi
fi

# ---------- 估算 device-size ----------
# 余量：15%，对齐到 4MiB；最小 1GiB
margin=$(( (TOTAL_BYTES * 15 + 99) / 100 ))
dev_size=$(( TOTAL_BYTES + margin ))
# 4MiB 对齐
align=$((4 * 1024 * 1024))
dev_size=$(( ( (dev_size + align - 1) / align ) * align ))
# 最小 1GiB
one_gb=$((1024 * 1024 * 1024))
[ "$dev_size" -lt "$one_gb" ] && dev_size="$one_gb"

info "分区数量：$(echo "$RAW_LIST_NAMES" | wc -w | tr -d ' ')"
info "原始总大小：$((TOTAL_BYTES / (1024*1024))) MiB"
info "设备大小（含余量/对齐）：$((dev_size / (1024*1024))) MiB"
[ "$need_sparse2raw" -eq 1 ] && info "注意：部分分区由稀疏镜像解稀疏得到，已自动处理。"

# ---------- 组装 lpmake 参数并打包 ----------
ARGS="--metadata-size 65536 --super-name super --device-size $dev_size"

# 把 name/path/size 拼接进去
# RAW_LIST_NAMES / RAW_LIST_PATHS 是按相同顺序累积的
names="$RAW_LIST_NAMES"
paths="$RAW_LIST_PATHS"

n_count="$(echo "$names" | wc -w | tr -d ' ')"
p_count="$(echo "$paths" | wc -w | tr -d ' ')"
[ "$n_count" -eq "$p_count" ] || die "内部错误：名称与路径数量不一致"

idx=1
while [ "$idx" -le "$n_count" ]; do
  nm="$(echo "$names" | awk -v k="$idx" '{print $k}')"
  pt="$(echo "$paths" | awk -v k="$idx" '{print $k}')"
  sz="$(wc -c < "$pt" | tr -d ' ')"
  # 追加参数：--partition name:readonly --image name=path --partition-size name:size
  ARGS="$ARGS --partition $nm:readonly --image $nm=$pt --partition-size $nm:$sz"
  idx=$((idx+1))
done

# 执行 lpmake
echo "➡️  lpmake 开始..."
# shellcheck disable=SC2086
lpmake $ARGS --output "$OUT_SUPER" || die "lpmake 执行失败"
echo "✅ 已打包 super 镜像：$OUT_SUPER"
