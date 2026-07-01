#!/bin/sh
# pack_zlo_out.sh — 先选“全部/单个”，再选输出“raw/sparse”
# 无需 root/sudo；不挂载；/bin/sh 兼容
# 后端自动选择：mkfs.ext4 -d → make_ext4fs → mke2fs+e2fsdroid
set -eu

PROJECT_ROOT="$(pwd)"
ZLO_OUT="$PROJECT_ROOT/zlo_out"
OUT_DIR="$PROJECT_ROOT/zlo_pack"

need_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "🔧 $*"; }

need_cmd du || die "缺少 du"
need_cmd awk || die "缺少 awk"
[ -d "$ZLO_OUT" ] || die "未找到目录：$ZLO_OUT"
mkdir -p "$OUT_DIR"

# ---------- 列出可打包的分区（只收录非空目录） ----------
PARTS=""
i=0
for d in "$ZLO_OUT"/*; do
  [ -d "$d" ] || continue
  if find "$d" -mindepth 1 -print -quit | grep -q .; then
    i=$((i+1))
    name="$(basename "$d")"
    PARTS="${PARTS}
$i:$name"
  fi
done
[ "$i" -gt 0 ] || die "zlo_out 下未发现可打包的分区目录。"
count="$i"

idx_to_name() {
  echo "$PARTS" | awk -F: -v k="$1" 'NF==2 && $1==k {gsub(/^[ \t\r\n]+|[ \t\r\n]+$/,"",$2); print $2}'
}
idx_to_path() {
  n="$(idx_to_name "$1")"
  [ -n "$n" ] && printf "%s\n" "$ZLO_OUT/$n" || printf "\n"
}

# ---------- 交互 1：选择“全部/单个” ----------
if [ -t 0 ] && [ -t 1 ]; then
  echo "请选择打包范围："
  echo "  1) 全部打包"
  echo "  2) 仅打包单个分区"
  printf "输入编号 [1/2，默认1]: "
  read sel || true
else
  sel="1"  # 非交互环境默认“全部”
fi

TARGETS=""
case "$sel" in
  2)
    echo "可用分区（共 $count 个）："
    echo "$PARTS" | sed '/^[[:space:]]*$/d' | sed 's/^/  /'
    printf "请输入要打包的分区序号（1~%s）: " "$count"
    read one || true
    echo "$one" | grep -Eq '^[0-9]+$' || die "非法序号"
    [ "$one" -ge 1 ] && [ "$one" -le "$count" ] || die "序号越界"
    p="$(idx_to_path "$one")"
    [ -n "$p" ] || die "内部错误：索引无映射"
    TARGETS="$p"
    ;;
  ""|1|*)
    j=1
    while [ "$j" -le "$count" ]; do
      p="$(idx_to_path "$j")"
      TARGETS="${TARGETS}
$p"
      j=$((j+1))
    done
    ;;
esac

# ---------- 交互 2：选择输出类型 raw/sparse ----------
MODE="raw"
if [ -t 0 ] && [ -t 1 ]; then
  echo "请选择输出类型："
  echo "  1) RAW（<partition>.img）"
  echo "  2) SPARSE（<partition>.sparse.img）"
  printf "输入编号 [1/2，默认1]: "
  read m || true
  case "$m" in
    2) MODE="sparse" ;;
    ""|1|*) MODE="raw" ;;
  esac
fi
if [ "$MODE" = "sparse" ]; then
  need_cmd img2simg || die "需要 img2simg 才能生成稀疏镜像（请安装 Android fs 工具）"
fi

# ---------- 后端能力探测（实际试跑） ----------
HAS_MKFS_D=0
if need_cmd mkfs.ext4; then
  PROBE_DIR="$(mktemp -d)"
  mkdir -p "$PROBE_DIR/src" && : > "$PROBE_DIR/src/ok"
  if mkfs.ext4 -q -L test -d "$PROBE_DIR/src" "$PROBE_DIR/probe.img" 16M >/dev/null 2>&1; then
    HAS_MKFS_D=1
  fi
  rm -rf "$PROBE_DIR" 2>/dev/null || true
fi
HAS_MAKE_EXT4FS=0; need_cmd make_ext4fs && HAS_MAKE_EXT4FS=1
HAS_E2FSDROID=0; need_cmd e2fsdroid && need_cmd mke2fs && HAS_E2FSDROID=1

[ $HAS_MKFS_D -eq 1 ] || [ $HAS_MAKE_EXT4FS -eq 1 ] || [ $HAS_E2FSDROID -eq 1 ] || \
  die "未找到可用的无 root 打包后端：mkfs.ext4(-d) / make_ext4fs / e2fsdroid"

# ---------- 公共函数 ----------
align_16mb() { val="$1"; echo $(( ((val + 15) / 16) * 16 )); }

build_raw_with_mkfs_d() { SRC="$1"; OUT_RAW="$2"; PART="$3"; SIZE_MB="$4"; mkfs.ext4 -L "$PART" -d "$SRC" "$OUT_RAW" "${SIZE_MB}M" >/dev/null 2>&1; }
build_raw_with_make_ext4fs() { SRC="$1"; OUT_RAW="$2"; PART="$3"; SIZE_MB="$4"; make_ext4fs -l "${SIZE_MB}M" -a "$PART" "$OUT_RAW" "$SRC" >/dev/null 2>&1; }
build_raw_with_e2fsdroid() {
  SRC="$1"; OUT_RAW="$2"; PART="$3"; SIZE_MB="$4"
  mke2fs -t ext4 -L "$PART" "$OUT_RAW" "${SIZE_MB}M" >/dev/null 2>&1 || return 1
  e2fsdroid -a "/$PART" -f "$SRC" "$OUT_RAW" >/dev/null 2>&1
}
to_sparse() { RAW="$1"; SPARSE="$2"; img2simg "$RAW" "$SPARSE" >/dev/null 2>&1; }

pack_one_partition() {
  SRC="$1"
  PART="$(basename "$SRC")"
  OUT_RAW="$OUT_DIR/$PART.img"
  OUT_SPARSE="$OUT_DIR/$PART.sparse.img"

  # 计算大小：目录体积 +30%，最小 256MB，16MB 对齐
  # 优先使用 --apparent-size（GNU），退回到普通 du 以兼容 BusyBox/BSD
  if du -sm --apparent-size "$SRC" >/dev/null 2>&1; then
    sz_mb="$(du -sm --apparent-size "$SRC" | awk '{print $1}')"
  else
    sz_mb="$(du -sm "$SRC" | awk '{print $1}')"
  fi
  [ -n "$sz_mb" ] || die "无法获取目录体积：$SRC"
  extra=$(( (sz_mb * 30 + 99) / 100 ))
  prealloc=$(( sz_mb + extra ))
  [ "$prealloc" -lt 256 ] && prealloc=256
  prealloc="$(align_16mb "$prealloc")"
  info "【$PART】源≈${sz_mb}MB → 预分配 ${prealloc}MB"

  ok=0
  if [ $HAS_MKFS_D -eq 1 ]; then
    info "【$PART】后端：mkfs.ext4 -d"
    build_raw_with_mkfs_d "$SRC" "$OUT_RAW" "$PART" "$prealloc" && ok=1
  fi
  if [ $ok -eq 0 ] && [ $HAS_MAKE_EXT4FS -eq 1 ]; then
    info "【$PART】后端：make_ext4fs"
    build_raw_with_make_ext4fs "$SRC" "$OUT_RAW" "$PART" "$prealloc" && ok=1
  fi
  if [ $ok -eq 0 ] && [ $HAS_E2FSDROID -eq 1 ]; then
    info "【$PART】后端：mke2fs + e2fsdroid"
    build_raw_with_e2fsdroid "$SRC" "$OUT_RAW" "$PART" "$prealloc" && ok=1
  fi
  [ $ok -eq 1 ] || die "【$PART】构建 RAW 失败（无可用后端）"

  if [ "$MODE" = "raw" ]; then
    echo "✅ RAW：$OUT_RAW"
  else
    info "【$PART】转换为稀疏…"
    to_sparse "$OUT_RAW" "$OUT_SPARSE" || die "【$PART】img2simg 不可用或失败"
    rm -f "$OUT_RAW" 2>/dev/null || true
    echo "✅ SPARSE：$OUT_SPARSE"
  fi
}

# ---------- 执行 ----------
echo "$TARGETS" | sed '/^[[:space:]]*$/d' | while IFS= read -r dir; do
  pack_one_partition "$dir"
done

echo "🎉 打包完成 → $OUT_DIR"
