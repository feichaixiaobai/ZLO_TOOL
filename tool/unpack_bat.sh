#!/bin/sh
# unpack_dat.sh — 将 <part>.transfer.list + <part>.new.dat(.br/.1...) 解成 <part>.img
# 交互式选择：零参数时，先选“全部/按序号”，再解包
# 也支持参数：./unpack_dat.sh system vendor   或   --parts "system,vendor"
# 输出：./zlo_pack/<part>.img
# 依赖：python(或python3)、sdat2img.py（建议放 tool/bin/）
# 可选：brotli（当存在 *.br 时需要）
set -eu

PROJECT_ROOT="$(pwd)"
OUT_DIR="$PROJECT_ROOT/zlo_pack"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "🔧 $*"; }

# 选 python
PY="python3"; need_cmd "$PY" || PY="python"
need_cmd "$PY" || die "未找到 python/python3"

# 找 sdat2img.py
if [ -f "$BIN_DIR/sdat2img.py" ]; then
  SDAT2IMG="$BIN_DIR/sdat2img.py"
elif [ -f "$SCRIPT_DIR/sdat2img.py" ]; then
  SDAT2IMG="$SCRIPT_DIR/sdat2img.py"
else
  SDAT2IMG="$(command -v sdat2img.py 2>/dev/null || true)"
  [ -n "$SDAT2IMG" ] || die "缺少 sdat2img.py，请放到 $BIN_DIR 或加入 PATH"
fi

mkdir -p "$OUT_DIR"

# ---------- 搜索 *.transfer.list ----------
find_lists() {
  find "$PROJECT_ROOT" -maxdepth 3 -type f -name '*.transfer.list' -printf '%P\n' 2>/dev/null | sort -V
}
LISTS="$(find_lists)"
[ -n "$LISTS" ] || die "未找到 *.transfer.list（把 OTA 解压内容放进项目目录内）"

# ---------- 把列表做成“索引:分区名:绝对路径”的清单 ----------
PARTS=""
i=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  base="$(basename "$rel")"
  part="${base%.transfer.list}"
  # 去重（同名多个 transfer.list 仅取第一个）
  case "$PARTS" in *":$part:"*) continue;; esac
  i=$((i+1))
  PARTS="${PARTS}
$i:$part:$PROJECT_ROOT/$rel"
done <<UNPACK_DAT_LISTS_EOF
$LISTS
UNPACK_DAT_LISTS_EOF
[ "$i" -gt 0 ] || die "未提取到分区列表"
count="$i"

idx_to_tuple() {
  echo "$PARTS" | awk -F: -v k="$1" 'NF>=3 && $1==k {print $2 ":" $3}'
}

# ---------- 解析命令行参数（可选的指定分区） ----------
WANTED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --parts) [ $# -ge 2 ] || die "--parts 需要值"; WANTED="$2"; shift 2;;
    --parts=*) WANTED="${1#*=}"; shift;;
    -h|--help)
      cat <<'H'
用法:
  ./tool/unpack_dat.sh                  # 交互式选择后解包
  ./tool/unpack_dat.sh system vendor    # 仅解指定分区
  ./tool/unpack_dat.sh --parts "system,vendor"
说明:
  自动匹配 <part>.new.dat / <part>.new.dat.br / <part>.new.dat.* 并输出到 zlo_pack/<part>.img
H
      exit 0;;
    *)
      if [ -z "$WANTED" ]; then WANTED="$1"; else WANTED="$WANTED,$1"; fi
      shift;;
  esac
done

SELECTED_INDEXES=""
add_idx(){ case ",$SELECTED_INDEXES," in *",$1,"*) :;; *) SELECTED_INDEXES="${SELECTED_INDEXES}${SELECTED_INDEXES:+,}$1";; esac }

# ---------- 若有 WANTED，则按名字选择；否则进入交互（TTY） ----------
if [ -n "$WANTED" ]; then
  # 规范化 wanted
  want_csv="$(echo "$WANTED" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
  j=1
  while [ "$j" -le "$count" ]; do
    tup="$(idx_to_tuple "$j")"; nm="$(echo "$tup" | cut -d: -f1 | tr 'A-Z' 'a-z')"
    case ",$want_csv," in *,"$nm",*) add_idx "$j";; esac
    j=$((j+1))
  done
  [ -n "$SELECTED_INDEXES" ] || die "按选择过滤后没有匹配的分区：$WANTED"
else
  if [ -t 0 ] && [ -t 1 ]; then
    echo "可用分区（共 $count 个）："
    echo "$PARTS" | sed '/^[[:space:]]*$/d' | sed 's/^/  /' | cut -d: -f1,2
    echo "请选择："
    echo "  1) 全部解包"
    echo "  2) 按序号选择（支持 1,3-5）"
    printf "输入编号 [1/2，默认1]: "
    read sel || true
    case "$sel" in
      2)
        printf "输入要解包的序号："
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
              if [ "$a" -le "$b" ]; then k="$a"; while [ "$k" -le "$b" ]; do add_idx "$k"; k=$((k+1)); done
              else k="$a"; while [ "$k" -ge "$b" ]; do add_idx "$k"; k=$((k-1)); done
              fi
              ;;
            *)
              echo "$tok" | grep -Eq '^[0-9]+$' || die "非法序号：$tok"
              [ "$tok" -ge 1 ] && [ "$tok" -le "$count" ] || die "序号越界：$tok"
              add_idx "$tok"
              ;;
          esac
        done
        ;;
      ""|1|*)
        k=1; while [ "$k" -le "$count" ]; do add_idx "$k"; k=$((k+1)); done
        ;;
    esac
  else
    # 非交互：默认全部
    k=1; while [ "$k" -le "$count" ]; do add_idx "$k"; k=$((k+1)); done
  fi
fi

# ---------- 工具：分段排序 ----------
sort_pieces() {
  awk '{n=$0;piece=0;if (match(n,/[.][0-9]+$/)){piece=substr(n,RSTART+1,RLENGTH-1)} printf "%010d\t%s\n",piece,n}' \
    | sort -n | cut -f2-
}

# ---------- 开始解包 ----------
echo "$SELECTED_INDEXES" | awk -F, '{for(i=1;i<=NF;i++) print $i}' | while read idx; do
  [ -n "$idx" ] || continue
  tup="$(idx_to_tuple "$idx")"
  part="$(echo "$tup" | cut -d: -f1)"
  tlist="$(echo "$tup" | cut -d: -f2-)"

  dir="$(dirname "$tlist")"
  dat_raw="$dir/$part.new.dat"
  dat_br="$dir/$part.new.dat.br"
  pieces="$(find "$dir" -maxdepth 1 -type f -name "$part.new.dat.*" -printf '%P\n' 2>/dev/null | sort_pieces || true)"

  TMPDIR_OP="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_OP" 2>/dev/null || true' EXIT

  in_dat=""
  if [ -f "$dat_raw" ]; then
    in_dat="$dat_raw"
  elif [ -f "$dat_br" ]; then
    need_cmd brotli || die "检测到 $part.new.dat.br 但缺少 brotli（请安装或放入 tool/bin/）"
    info "[$part] brotli 解压：$part.new.dat.br → $part.new.dat"
    brotli -d -o "$TMPDIR_OP/$part.new.dat" "$dat_br"
    in_dat="$TMPDIR_OP/$part.new.dat"
  elif [ -n "$pieces" ]; then
    info "[$part] 检测到分段 new.dat.*，按序合并..."
    cat_path="$TMPDIR_OP/$part.new.dat"
    echo "$pieces" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      cat "$dir/$p" >> "$cat_path"
    done
    in_dat="$cat_path"
  else
    echo "⚠️ 跳过：未找到 $part 的 new.dat/new.dat.br/new.dat.*" >&2
    rm -rf "$TMPDIR_OP"; trap - EXIT
    continue
  fi

  out_img="$OUT_DIR/$part.img"
  info "[$part] 生成：$out_img"
  if ! "$PY" "$SDAT2IMG" "$tlist" "$in_dat" "$out_img" >/dev/null 2>&1; then
    echo "❌ [$part] sdat2img 失败：$tlist + $in_dat" >&2
    rm -rf "$TMPDIR_OP"; trap - EXIT
    exit 1
  fi
  echo "✅ [$part] OK → $out_img"

  rm -rf "$TMPDIR_OP"; trap - EXIT
done

echo "🎉 全部完成，输出目录：$OUT_DIR"
