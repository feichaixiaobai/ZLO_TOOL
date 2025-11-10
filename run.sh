#!/bin/sh

###############################################################################
# 环境与路径
###############################################################################
ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BIN_DIR="$ROOT_DIR/bin"
TOOL_DIR="$ROOT_DIR/tool"
export PATH="$BIN_DIR:$PATH"

BASE_DIR=$(pwd)
#TEST PB
#TEST PB
###############################################################################
# 小工具函数
###############################################################################
print_blank() {
    n="$1"; i=0
    while [ "$i" -lt "$n" ]; do echo; i=$((i+1)); done
}

need_cmd() {
    cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "缺少命令: $cmd ；请将其放到 $BIN_DIR 或添加到 PATH"
        return 1
    fi
    return 0
}

is_project_dir() {
    name="$1"
    [ -n "$name" ] || return 1
    [ -d "$name" ] || return 1
    [ "$name" = "bin" ] && return 1
    [ "$name" = "tool" ] && return 1
    return 0
}


# ============ 终端页工具 ============
supports_alt_screen() {
  [ -t 1 ] || return 1         
  [ -n "${TERM:-}" ] || return 1
  command -v tput >/dev/null 2>&1 || return 1
  tput smcup >/dev/null 2>&1 && tput rmcup >/dev/null 2>&1
}

enter_alt_screen() {
  if supports_alt_screen; then
    tput smcup 2>/dev/null || printf '\033[?1049h'
    tput clear 2>/dev/null  || printf '\033[2J\033[H'
  else
    printf '\033[2J\033[H'
  fi
}

leave_alt_screen() {
  if supports_alt_screen; then
    tput rmcup 2>/dev/null || printf '\033[?1049l'
  fi
}

# 包装器：始终保证离开备用屏
with_alt_screen() {
  enter_alt_screen
  "$@"
  rc=$?
  leave_alt_screen
  return $rc
}


###############################################################################
# 欢迎页
###############################################################################
cat <<'EOF'
ZZZZZZZZ  LL         OOOOOO     TTTTTTTT   OOOOOO    OOOOOO   LL
     ZZ   LL        OO    OO       TT     OO    OO  OO    OO  LL
    ZZ    LL        OO    OO       TT     OO    OO  OO    OO  LL
   ZZ     LL        OO    OO       TT     OO    OO  OO    OO  LL
  ZZ      LL        OO    OO       TT     OO    OO  OO    OO  LL
 ZZ       LL        OO    OO       TT     OO    OO  OO    OO  LL
ZZZZZZZZ  LLLLLLLL   OOOOOO        TT      OOOOOO    OOOOOO   LLLLLLLL
EOF
print_blank 3

###############################################################################
# 项目列表
###############################################################################
list_projects() {
    # 收集所有子目录
    set -- */
    shown=0
    if [ "$1" = "*/" ] 2>/dev/null || [ $# -eq 0 ]; then
        echo "  (暂无项目)"
        return
    fi
    i=1
    for d in "$@"; do
        [ -d "$d" ] || continue
        d=${d%/}
        is_project_dir "$d" || continue
        printf "  %d. %s\n" "$i" "$d"
        i=$((i+1))
        shown=1
    done
    [ "$shown" -eq 1 ] || echo "  (暂无项目)"
}

# 检测是否为 Android 稀疏镜像（看魔数 0xed26ff3a）
is_sparse_img() {
    f="$1"
    # 读前4字节并转为十六进制
    magic=$(dd if="$f" bs=4 count=1 2>/dev/null | hexdump -v -e '1/4 "0x%08x"')
    [ "$magic" = "0xed26ff3a" ]
}

# 生成不与输入冲突的 RAW 输出路径（去掉 .img，加 _raw.img）
make_raw_out_path() {
    in="$1"   # 绝对或相对都可
    d=$(dirname "$in")
    b=$(basename "$in")
    base_noext=${b%.*}          # 只去掉最后一个扩展名
    out="$d/${base_noext}_raw.img"
    # 双保险：若竟然等于输入，就再加 .raw 后缀
    [ "$out" = "$in" ] && out="${in}.raw"
    echo "$out"
}

# 检查每个项目是否包含 .img（过滤 bin/tool）
check_img(){
    set -- */
    any=0
    if [ "$1" = "*/" ] 2>/dev/null || [ $# -eq 0 ]; then
        echo "  (暂无项目)"
        return
    fi
    for d in "$@"; do
        [ -d "$d" ] || continue
        d=${d%/}
        is_project_dir "$d" || continue
        any=1
        set -- "$d"/*.img
        if [ "$1" = "$d/*.img" ] 2>/dev/null; then
            echo "项目 $d 不包含 img 文件"
        else
            echo "项目 $d 包含 img 文件"
        fi
    done
    [ "$any" -eq 1 ] || echo "  (暂无项目)"
}

# 选择项目目录下的 super 镜像（返回选中的完整路径；失败返回空）
pick_super_img() {
    _dir="$1"
    _tmpfile=$(mktemp)
    # 收集候选（支持多种命名）
    for p in \
        "$_dir"/super.img \
        "$_dir"/super_*.img \
        "$_dir"/super*.img \
        "$_dir"/SUPER.img \
        "$_dir"/SUPER_*.img \
        "$_dir"/SUPER*.img
    do
        [ -f "$p" ] && realpath "$p" >>"$_tmpfile"
    done
    # 去重
    sort -u -o "$_tmpfile" "$_tmpfile"

    set -- $(cat "$_tmpfile" 2>/dev/null)
    rm -f "$_tmpfile"

    if [ $# -eq 0 ]; then
        return 1
    elif [ $# -eq 1 ]; then
        echo "$1"
        return 0
    else
        echo "检测到多个 super 镜像："
        i=1
        for f in "$@"; do
            echo "  $i) $f"
            i=$((i+1))
        done
        printf "请输入编号: "
        read -r idx
        i=1
        for f in "$@"; do
            if [ "$idx" = "$i" ]; then
                echo "$f"
                return 0
            fi
            i=$((i+1))
        done
        return 1
    fi
}

# 生成不冲突的输出目录（base, base_1, base_2, ...）
unique_outdir() {
    _base="$1"
    _d="$_base"
    _n=1
    while [ -e "$_d" ]; do
        _d="${_base}_$_n"
        _n=$(( _n + 1 ))
    done
    echo "$_d"
}

###############################################################################
# 从 RAW 分区镜像提取文件（优先 7z；也支持自定义脚本）
###############################################################################
extract_fs_from_raw() {
    _raw="$1"
    _out="$2"
    mkdir -p "$_out"

    # 如果用户提供了专用脚本，优先用它（可在 tool/unpack_img_fs.sh 内处理 ext4/erofs/f2fs 等）
    if [ -x "$TOOL_DIR/unpack_img_fs.sh" ]; then
        "$TOOL_DIR/unpack_img_fs.sh" "$_raw" "$_out"
        return $?
    fi

    # 兜底：尝试 7z（多数情况下能直接解出 ext4/erofs 内容）
    if command -v 7z >/dev/null 2>&1; then
        7z x -y -o"$_out" "$_raw" >/dev/null
        return $?
    fi

    echo "未找到可用的文件系统解包方式（请安装 7z 或提供 tool/unpack_img_fs.sh）。"
    return 1
}

show_home_menu(){
    echo "=================================="
    echo
    echo "1.创建项目         2.删除项目"
    echo
    echo "3.选择项目         0.退出"
    echo
    echo "=================================="
}

###############################################################################
# 项目子菜单（分解/打包）
###############################################################################
project_menu_core(){
   
    dir=$(pwd)

    echo "==============================="
    echo
    echo "11.分解img         22.打包img"
    echo
    echo "33.分解super       44.打包super"
    echo
    echo "55.分解dat         66.打包dat"
    echo
    echo "77.分解br          88.打包br"
    echo
    echo "99.分解bin         1010.打包bin(正在开发)"
    echo
    echo "00.返回上级菜单"
    echo "==============================="

    while :; do
        printf "请输入选项编号: "
        read -r demo_option
        case "$demo_option" in
            11)
                echo "正在分解 img..."
                need_cmd file || continue
                need_cmd simg2img || continue

                set -- "$dir"/*.img
                if [ "$1" = "$dir/*.img" ] 2>/dev/null; then
                    echo "项目中不包含 img 文件，无法分解"
                    continue
                fi

                echo "检测到以下 img 文件："
                for p in "$@"; do printf "  - %s\n" "$(basename "$p")"; done

                printf "选择分解方式(1.全部分解/2.自定义分解): "
                read -r confirm

                sel_list=""
                if [ "$confirm" = "1" ]; then
                    for p in "$@"; do sel_list="$sel_list $(basename "$p")"; done
                elif [ "$confirm" = "2" ]; then
                    printf "请输入要分解的 img 文件名（多个用空格分隔）: "
                    read -r input_names
                    for f in $input_names; do
                        if [ -f "$dir/$f" ]; then sel_list="$sel_list $f"; else echo "跳过不存在的文件: $f"; fi
                    done
                    [ -n "$sel_list" ] || { echo "未选择有效文件"; continue; }
                else
                    echo "无效的选择"
                    continue
                fi

                for img_file in $sel_list; do
                    # 跳过 super 镜像，提示用 33 选项
                    case "$img_file" in
                        super.img|super_*.img|super*.img|SUPER.img|SUPER_*.img|SUPER*.img)
                            echo "[$img_file] 为 super 镜像，已跳过。请使用“33.分解super”。"
                            continue
                            ;;
                    esac

                    src="$dir/$img_file"
                    base=${img_file%*.img}
                    outdir="$dir/zlo_out/$base"
                    mkdir -p "$outdir"

                    # 建立临时 RAW 路径（不作为最终产物保存）
                    tmp_raw="$(mktemp -p "${TMPDIR:-/tmp}" "${base}.XXXXXX.raw")"

                    if file -b "$src" | grep -qi 'Android sparse image'; then
                        echo "[$img_file] sparse → 转换为临时 RAW：$(basename "$tmp_raw")（不落盘输出）"
                        if ! simg2img "$src" "$tmp_raw"; then
                            echo "[$img_file] simg2img 转换失败"
                            rm -f "$tmp_raw"
                            continue
                        fi
                    else
                        echo "[$img_file] raw → 复制到临时 RAW：$(basename "$tmp_raw")（不落盘输出）"
                        if ! cp -f "$src" "$tmp_raw"; then
                            echo "[$img_file] 复制 RAW 失败"
                            rm -f "$tmp_raw"
                            continue
                        fi
                    fi

                    echo "[$img_file] 正在从 RAW 提取文件到：zlo_out/$base/"
                    if ! extract_fs_from_raw "$tmp_raw" "$outdir"; then
                        echo "[$img_file] 提取失败：请安装 7z 或提供 tool/unpack_img_fs.sh"
                        rm -f "$tmp_raw"
                        continue
                    fi

                    # 清理临时 RAW
                    rm -f "$tmp_raw"
                    echo "[$img_file] 提取完成（未输出 _raw.img，仅保留解出的文件）。"
                done
                echo "img 分解完成（文件已解出到 zlo_out/<分区名>/，未输出 *_raw.img）。"
                ;;
            22)
                echo "正在打包 img..."
                if [ -x "$TOOL_DIR/pack_img.sh" ]; then
                    sh "$TOOL_DIR/pack_img.sh"
                else
                    echo "请将 pack_img.sh 放入 $TOOL_DIR/ 目录"
                fi
                ;;
            33)
                echo "正在分解 super..."
                if [ -x "$TOOL_DIR/unpack_super.sh" ]; then
                    # 若你自备脚本，也请确保其把产物放在项目根目录
                    sh "$TOOL_DIR/unpack_super.sh"
                else
                    need_cmd lpunpack || continue

                    SUPER_IMG="$(pick_super_img "$dir")"
                    if [ -z "$SUPER_IMG" ]; then
                        echo "未在项目目录下检测到 super 镜像（支持 super.img / super_*.img / super*.img）。"
                        continue
                    fi
                    echo "已选择: $SUPER_IMG"

                    # 若是稀疏镜像，先转 raw
                    RAW_SUPER="$SUPER_IMG"
                    if is_sparse_img "$SUPER_IMG"; then
                        if [ -x /usr/bin/simg2img ]; then
                            SIMG2IMG_BIN="/usr/bin/simg2img"
                        else
                            need_cmd simg2img || continue
                            SIMG2IMG_BIN="simg2img"
                        fi

                        RAW_SUPER="$(make_raw_out_path "$SUPER_IMG")"
                        echo "检测到稀疏镜像 → 正在转换为原始镜像: $RAW_SUPER"
                        if ! "$SIMG2IMG_BIN" "$SUPER_IMG" "$RAW_SUPER"; then
                            echo "simg2img 转换失败"
                            continue
                        fi
                    fi

                    # 直接把各分区 *.img 解到“项目目录”下
                    if ! lpunpack "$RAW_SUPER" "$dir"; then
                        echo "lpunpack 执行失败，请检查镜像是否有效、二进制是否为本机架构。"
                        [ "$RAW_SUPER" != "$SUPER_IMG" ] && echo "提示：已保留转换后的 RAW 镜像用于排查：$RAW_SUPER"
                        continue
                    fi

                    echo "完成：已将分区镜像解包到项目目录：$dir"
                fi
                ;;
            44)
                echo "正在打包 super..."
                if [ -x "$TOOL_DIR/pack_super.sh" ]; then
                    sh "$TOOL_DIR/pack_super.sh"
                else
                    need_cmd lpmake || continue
                    echo "请在 $TOOL_DIR 添加 pack_super.sh 实现具体打包逻辑"
                fi
                ;;
            55)
                echo "正在分解 dat..."
                if [ -x "$TOOL_DIR/unpack_dat.sh" ]; then
                    sh "$TOOL_DIR/unpack_dat.sh"
                else
                    echo "请放入 $TOOL_DIR/unpack_dat.sh"
                fi
                ;;
            66)
                echo "正在打包 dat..."
                if [ -x "$TOOL_DIR/pack_dat.sh" ]; then
                    sh "$TOOL_DIR/pack_dat.sh"
                else
                    echo "请放入 $TOOL_DIR/pack_dat.sh"
                fi
                ;;
            77)
                echo "正在分解 br..."
                if [ -x "$TOOL_DIR/unpack_br.sh" ]; then
                    sh "$TOOL_DIR/unpack_br.sh"
                else
                    need_cmd brotli || continue
                    printf "输入 file.br 路径: "
                    read -r BR
                    OUT=${BR%*.br}
                    brotli -d -o "$OUT" "$BR"
                    echo "完成：$OUT"
                fi
                ;;
            88)
                echo "正在打包 br..."
                if [ -x "$TOOL_DIR/pack_br.sh" ]; then
                    sh "$TOOL_DIR/pack_br.sh"
                else
                    need_cmd brotli || continue
                    printf "输入原始文件路径: "
                    read -r IN
                    OUT="${IN}.br"
                    brotli -f -o "$OUT" "$IN"
                    echo "完成：$OUT"
                fi
                ;;
            99)
                echo "正在分解 bin..."
                if [ -x "$TOOL_DIR/unpack_bin.sh" ]; then
                    sh "$TOOL_DIR/unpack_bin.sh"
                else
                    echo "请放入 $TOOL_DIR/unpack_bin.sh"
                fi
                ;;
            1010)
                echo "正在打包 bin..."
                if [ -x "$TOOL_DIR/pack_bin.sh" ]; then
                    sh "$TOOL_DIR/pack_bin.sh"
                else
                    echo "请放入 $TOOL_DIR/pack_bin.sh"
                fi
                ;;
            00)
                echo "返回上级菜单"
                return
                ;;
            *)
                echo "无效的选项，请重新输入。"
                ;;
        esac
    done
}
project_menu() {
  with_alt_screen project_menu_core
}

###############################################################################
# 主循环（过滤 bin/tool）
###############################################################################
while :; do
    echo "=================================="
    echo "> 项目列表"
    print_blank 1
    list_projects
    print_blank 1

    cd "$BASE_DIR" || exit 1
    show_home_menu
    printf "请输入选项编号: "
    read -r option

    case "$option" in
        1)
            while :; do
                printf "请输入你要创建的项目名称："
                read -r project_name

                if [ -z "$project_name" ]; then
                    echo "项目名称不能为空，请重新输入"
                    continue
                fi
                # 禁止使用 bin/tool 作为项目名
                if [ "$project_name" = "bin" ] || [ "$project_name" = "tool" ]; then
                    echo "项目名不能为 bin 或 tool，请重新输入"
                    continue
                fi
                if [ -d "$project_name" ]; then
                    echo "项目 $project_name 已存在，请重新输入"
                    continue
                fi

                mkdir -p "$project_name"
                # 按需求：创建 zlo_out 与 config 目录
                mkdir -p "$project_name/zlo_out" "$project_name/config"

                echo "项目 $project_name 创建成功（已创建 zlo_out/ 与 config/）"

                printf "是否进入项目？(y/n): "
                read -r enter_option
                case "$enter_option" in
                    y|Y)
                        cd "$project_name" || exit 1
                        echo "已进入项目 $project_name"
                        project_menu
                        ;;
                    *)
                        echo "已返回首页"
                        ;;
                esac
                break
            done
            ;;
        2)
            echo "你已经创建的项目有："
            list_projects
            printf "请输入你要删除的项目名称："
            read -r del_project_name
            if ! is_project_dir "$del_project_name"; then
                echo "目标不是有效项目目录（或是 bin/tool）"
            else
                rm -rf -- "$del_project_name"
                echo "项目 $del_project_name 删除成功"
            fi
            ;;
        3)
           echo "你已经创建的项目有："
# 收集所有项目目录（过滤 bin/tool）
proj_list=""
for d in */; do
    d=${d%/}
    is_project_dir "$d" || continue
    proj_list="$proj_list $d"
done

i=1
for p in $proj_list; do
    echo "  $i. $p"
    i=$((i+1))
done

printf "请输入项目编号或名称："
read -r sel_input

# 尝试编号映射
sel_project_name=""
i=1
for p in $proj_list; do
    if [ "$sel_input" = "$i" ] || [ "$sel_input" = "$p" ]; then
        sel_project_name="$p"
        break
    fi
    i=$((i+1))
done

if [ -n "$sel_project_name" ] && is_project_dir "$sel_project_name"; then
    cd "$sel_project_name" || exit 1
    echo "已进入项目 $sel_project_name"
    project_menu
else
    echo "项目 $sel_input 不存在或不是有效项目（bin/tool 不显示且不可选择）"
fi
            ;;
        0)
            echo "退出"
            exit 0
            ;;
        *)
            echo "无效的选项，请重新输入。"
            ;;
    esac
done
