#!/bin/sh
# unpack_super.sh — 零参数、/bin/sh 兼容、全自动分解 Android super.img
# 行为：
# 1) 从当前目录向下一层子目录搜索 super 镜像：super.img > super_*.img > super*.img
# 2) 正确检测稀疏镜像（magic 0xed26ff3a），需要时用 simg2img 转 RAW（临时文件）
# 3) 使用 lpunpack 解包到“镜像所在目录”
# 4) 全程无需参数和交互

set -eu

# ====== PATH 优先找 ../bin ======
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR_DEFAULT="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR_DEFAULT:$PATH"; export PATH

need_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "$*"; }

# 稀疏镜像检测（POSIX）：读前4字节，用 od/hexdump 取十六进制并比对 ed26ff3a
is_sparse_img() {
  img="$1"
  magic=""
  if need_cmd od; then
    # od -An -tx4 输出一个 32bit 值；去空白后通常形如 "ed26ff3a"
    magic="$(dd if="$img" bs=4 count=1 2>/dev/null | od -An -tx4 2>/dev/null | tr -d '[:space:]' || true)"
  elif need_cmd hexdump; then
    magic="$(hexdump -n 4 -e '1/4 "%08x"' "$img" 2>/dev/null || true)"
  else
    # 没有 od/hexdump，就无法检测；返回非稀疏（后续若失败再提示）
    return 1
  fi

  case "$magic" in
    *ed26ff3a) return 0 ;;  # 稀疏
    *)         return 1 ;;
  esac
}

mktemp_img() {
  # 兼容 BusyBox/macOS：优先 TMPDIR
  mktemp "${TMPDIR:-/tmp}/raw_super_XXXXXX.img"
}

# ====== 自动查找 super 镜像（当前目录及下一层子目录）======
ROOT="$(pwd)"
CANDIDATE=""

# 当前目录：super.img -> super_*.img -> super*.img
[ -f "$ROOT/super.img" ] && CANDIDATE="$ROOT/super.img"
[ -z "$CANDIDATE" ] && CANDIDATE="$(find "$ROOT" -maxdepth 1 -type f -name 'super_*.img' | head -n1 || true)"
[ -z "$CANDIDATE" ] && CANDIDATE="$(find "$ROOT" -maxdepth 1 -type f -name 'super*.img'  | head -n1 || true)"

# 下一层子目录同优先级
[ -z "$CANDIDATE" ] && CANDIDATE="$(find "$ROOT" -maxdepth 2 -type f -name 'super.img'    | head -n1 || true)"
[ -z "$CANDIDATE" ] && CANDIDATE="$(find "$ROOT" -maxdepth 2 -type f -name 'super_*.img'  | head -n1 || true)"
[ -z "$CANDIDATE" ] && CANDIDATE="$(find "$ROOT" -maxdepth 2 -type f -name 'super*.img'   | head -n1 || true)"

[ -n "$CANDIDATE" ] || die "未找到 super 镜像（支持 super.img / super_*.img / super*.img）"
[ -f "$CANDIDATE" ] || die "镜像不是普通文件: $CANDIDATE"

OUT_DIR="$(cd "$(dirname "$CANDIDATE")" && pwd)"
SUPER_IMG="$CANDIDATE"

echo "正在分解 super..."
info "已选择: $SUPER_IMG"
info "输出目录: $OUT_DIR"

# ====== 依赖 ======
need_cmd lpunpack || die "缺少 lpunpack，请放到 $BIN_DIR_DEFAULT 或加入 PATH"
# simg2img 仅在稀疏镜像时需要

# ====== 稀疏 -> RAW（如需）======
RAW_IMG=""
cleanup() {
  if [ -n "${RAW_IMG:-}" ] && [ -f "$RAW_IMG" ] && [ "$RAW_IMG" != "$SUPER_IMG" ]; then
    rm -f -- "$RAW_IMG" || true
  fi
}
trap cleanup EXIT

if is_sparse_img "$SUPER_IMG"; then
  info "检测到稀疏镜像 → 正在转换为 RAW..."
  if need_cmd /usr/bin/simg2img; then
    SIMG2IMG="/usr/bin/simg2img"
  elif need_cmd simg2img; then
    SIMG2IMG="simg2img"
  else
    die "缺少 simg2img，无法转换稀疏镜像。请放到 $BIN_DIR_DEFAULT 或加入 PATH"
  fi
  RAW_IMG="$(mktemp_img)"
  info "转换到: $RAW_IMG"
  "$SIMG2IMG" "$SUPER_IMG" "$RAW_IMG" || die "simg2img 转换失败"
else
  info "非稀疏镜像，无需转换。"
  RAW_IMG="$SUPER_IMG"
fi

# ====== 解包 ======
info "使用 lpunpack 分解中..."
if ! lpunpack "$RAW_IMG" "$OUT_DIR"; then
  if [ "$RAW_IMG" != "$SUPER_IMG" ]; then
    trap - EXIT
    info "提示：已保留转换后的 RAW 镜像用于排查：$RAW_IMG"
  fi
  die "lpunpack 执行失败，请检查镜像是否有效、或二进制与本机架构是否匹配。"
fi

info "完成：已将分区镜像解包到目录：$OUT_DIR"
