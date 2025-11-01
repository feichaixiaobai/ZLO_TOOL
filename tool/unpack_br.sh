#!/bin/sh
# unpack_br.sh — 扫描并解压 *.br，支持交互选择/批量/删除源文件
# 依赖：brotli（已放 tool/bin/ 或在 PATH 中）
# 兼容 /bin/sh；无需 sudo

set -eu

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" 2>/dev/null || echo "$SCRIPT_DIR")"
PATH="$BIN_DIR:$PATH"; export PATH

need_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "🔧 $*"; }

need_cmd brotli || die "缺少 brotli，请将其放入 $BIN_DIR 或加入 PATH"

DELETE_SRC=0
FORCE=0
MODE=""     # ""=交互; "all"=全部; "files"=显式参数文件

FILES=""

usage() {
  cat <<'U'
用法:
  ./tool/unpack_br.sh                    # 交互式扫描并解压
  ./tool/unpack_br.sh file1.br [...]     # 解压指定文件
  选项:
    --delete, -j   解压后删除源文件
    --force        覆盖已存在的输出文件
    --all          非交互：扫描到的 .br 全部解压
U
  exit 2
}

# -------- 解析参数 --------
while [ $# -gt 0 ]; do
  case "$1" in
    --delete|-j) DELETE_SRC=1; shift ;;
    --force)     FORCE=1; shift ;;
    --all)       MODE="all"; shift ;;
    -h|--help)   usage ;;
    -*)
      echo "未知参数: $1"; usage ;;
    *)
      MODE="files"
      FILES="${FILES}
$1"
      shift ;;
  esac
done

# -------- 收集 *.br 列表（相对路径） --------
scan_br() {
  # 当前目录 -> 下一层子目录；按名字排序
  {
    find "$PROJECT_ROOT" -maxdepth 1 -type f -name '*.br' -printf '%P\n' 2>/dev/null
    find "$PROJECT_ROOT" -maxdepth 2 -mindepth 2 -type f -name '*.br' -printf '%P\n' 2>/dev/null
  } | sort -V
}

LIST=""
if [ "$MODE" = "files" ]; then
  # 去重并保持顺序
  echo "$FILES" | sed '/^[[:space:]]*$/d' | while IFS= read -r f; do
    [ -n "$f" ] || continue
    # 标准化为相对路径
    case "$f" in
      /*) rel="$(echo "$f" | sed "s#^$PROJECT_ROOT/##")" ;;
      *)  rel="$f" ;;
    esac
    [ -f "$PROJECT_ROOT/$rel" ] || die "文件不存在：$f"
    echo "$rel"
  done | awk '!seen[$0]++' > /tmp/.br.list.$$
  LIST="$(cat /tmp/.br.list.$$)"; rm -f /tmp/.br.list.$$ || true
else
  LIST="$(scan_br)"
  [ -n "$LIST" ] || die "未在项目中找到 .br 文件"
fi

# -------- 交互：选择文件 / 删除源 --------
SELECTED=""
if [ -t 0 ] && [ -t 1 ] && [ "$MODE" != "files" ] && [ "$MODE" != "all" ]; then
  # 列出可选项
  echo "可解压的 .br 文件："
  i=0
  echo "$LIST" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    i=$((i+1)); printf "  %d) %s\n" "$i" "$rel"
  done
  count="$i"

  echo
  echo "请选择："
  echo "  1) 全部解压"
  echo "  2) 按序号选择（支持 1,3-5）"
  printf "输入编号 [1/2，默认1]: "
  read ans || true

  SELECT_INDEXES=""
  add_idx(){ case ",$SELECT_INDEXES," in *",$1,"*) :;; *) SELECT_INDEXES="${SELECT_INDEXES}${SELECT_INDEXES:+,}$1";; esac }

  if [ "$ans" = "2" ]; then
    printf "输入要解压的序号："
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
    # 按索引抽取
    j=0
    echo "$LIST" | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      j=$((j+1))
      case ",$SELECT_INDEXES," in *",$j,"*) echo "$rel";; esac
    done > /tmp/.br.sel.$$
    SELECTED="$(cat /tmp/.br.sel.$$)"
    rm -f /tmp/.br.sel.$$
  else
    # 全部
    SELECTED="$LIST"
  fi

  # 是否删除源
  echo
  printf "解压后删除源文件？(y/N): "
  read yn || true
  case "$yn" in y|Y|yes|YES) DELETE_SRC=1 ;; *) : ;; esac

else
  # 非交互：files/all 都直接使用 LIST
  SELECTED="$LIST"
fi

# -------- 执行解压 --------
total=0; ok=0; skip=0; rmcount=0
echo "$SELECTED" | sed '/^[[:space:]]*$/d' | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  total=$((total+1))
  in="$PROJECT_ROOT/$rel"
  case "$rel" in
    *.br) out="$PROJECT_ROOT/$(echo "$rel" | sed 's/\.br$//')" ;;
    *)    out="$PROJECT_ROOT/$rel.out" ;;
  esac

  # 若输出已存在
  if [ -f "$out" ] && [ "$FORCE" -ne 1 ]; then
    echo "⚠️ 跳过（已存在）：$out"
    skip=$((skip+1))
    continue
  fi

  outdir="$(dirname "$out")"; mkdir -p "$outdir"
  if brotli -d -o "$out" "$in" >/dev/null 2>&1; then
    echo "✅ 解压：$rel  →  ${out#$PROJECT_ROOT/}"
    ok=$((ok+1))
    if [ "$DELETE_SRC" -eq 1 ]; then
      rm -f "$in" && rmcount=$((rmcount+1)) || true
    fi
  else
    echo "❌ 失败：$rel" >&2
  fi
done

echo "—— 统计 ——"
echo "总计：$(echo "$SELECTED" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')  成功：$ok  跳过：$skip  删除源：$rmcount"
