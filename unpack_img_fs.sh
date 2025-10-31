#!/bin/sh
# tool/unpack_img_fs.sh
# 用途：从 RAW 分区镜像中把文件系统内容解到输出目录（尽量无 root）。
# 用法：unpack_img_fs.sh <raw.img> <outdir>

set -eu

RAW="${1:?RAW image path required}"
OUT="${2:?Output dir required}"

#------------------------- 常用小工具 -------------------------
info(){ printf '[INFO] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
err (){ printf '[ERR ] %s\n' "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

ensure_out(){
  mkdir -p "$OUT"
}

tmpdir_make(){
  mktemp -d -p "${TMPDIR:-/tmp}" "unpackfs.XXXXXX"
}

cleanup_mount(){
  _mnt="$1"
  if [ -n "$_mnt" ] && mountpoint -q "$_mnt" 2>/dev/null; then
    umount "$_mnt" 2>/dev/null || true
  fi
  [ -n "$_mnt" ] && rmdir "$_mnt" 2>/dev/null || true
}

copy_tree(){
  src="$1"; dst="$2"
  mkdir -p "$dst"
  if have rsync; then
    rsync -aHAX --numeric-ids --inplace --no-inc-recursive "$src"/ "$dst"/ 2>/dev/null || rsync -a "$src"/ "$dst"/
  else
    (cd "$src" && tar cf - .) | (cd "$dst" && tar xpf -)
  fi
}

#------------------------- FS 识别 -------------------------
detect_fs(){
  # 优先 blkid
  if have blkid; then
    t=$(blkid -o value -s TYPE "$RAW" 2>/dev/null || true)
    if [ -n "$t" ]; then
      echo "$t" | tr '[:upper:]' '[:lower:]'
      return
    fi
  fi
  # 其次 file
  if have file; then
    desc=$(file -b "$RAW" 2>/dev/null || true)
    case "$desc" in
      *ext2*|*ext3*|*ext4*) echo "ext4"; return;;
      *erofs*) echo "erofs"; return;;
      *squashfs*) echo "squashfs"; return;;
      *f2fs*) echo "f2fs"; return;;
    esac
  fi
  echo "unknown"
}

#------------------------- 个别 FS 处理 -------------------------
extract_ext(){
  ensure_out
  # 1) debugfs（无root，强烈推荐）
  if have debugfs; then
    info "ext* using debugfs rdump → $OUT"
    # rdump 可能对非常大的 inode 报错，尽量容错
    if debugfs -R "rdump / \"$OUT\"" "$RAW"; then
      return 0
    fi
    warn "debugfs rdump 失败，尝试 7z"
  else
    warn "未找到 debugfs，尝试 7z"
  fi

  # 2) 7z 解（部分发行版能直接解 ext4）
  if have 7z; then
    info "ext* using 7z → $OUT"
    if 7z x -y -o"$OUT" "$RAW"; then
      return 0
    fi
    warn "7z 解失败，尝试挂载复制（需要 root）"
  fi

  # 3) 挂载只读复制（需要 root）
  if [ "$(id -u)" -eq 0 ]; then
    mnt=$(tmpdir_make)
    trap 'cleanup_mount "$mnt"' EXIT INT TERM
    info "ext* mounting ro,loop at $mnt"
    mount -o ro,loop "$RAW" "$mnt"
    copy_tree "$mnt" "$OUT"
    umount "$mnt"
    rmdir "$mnt"
    trap - EXIT INT TERM
    return 0
  else
    err "ext*：缺少 debugfs/7z 或未以 root 运行，无法继续。"
    return 1
  fi
}

extract_erofs(){
  ensure_out
  # 1) FUSE：erofsfuse（免 root）
  if have erofsfuse; then
    mnt=$(tmpdir_make)
    info "EROFS using erofsfuse at $mnt"
    erofsfuse "$RAW" "$mnt"
    copy_tree "$mnt" "$OUT"
    # 尝试卸载 FUSE
    if have fusermount; then fusermount -u "$mnt" 2>/dev/null || true; fi
    umount "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    return 0
  fi

  # 2) erofs-unpack（erofs-utils 新版提供）
  if have erofs-unpack; then
    info "EROFS using erofs-unpack → $OUT"
    erofs-unpack "$RAW" "$OUT"
    return 0
  fi

  # 3) 7z 兜底
  if have 7z; then
    info "EROFS using 7z → $OUT"
    if 7z x -y -o"$OUT" "$RAW"; then
      return 0
    fi
  fi

  # 4) root 挂载（只读）
  if [ "$(id -u)" -eq 0 ]; then
    mnt=$(tmpdir_make)
    trap 'cleanup_mount "$mnt"' EXIT INT TERM
    info "EROFS mounting ro,loop at $mnt"
    mount -t erofs -o ro,loop "$RAW" "$mnt"
    copy_tree "$mnt" "$OUT"
    umount "$mnt"; rmdir "$mnt"
    trap - EXIT INT TERM
    return 0
  fi

  err "EROFS：缺少 erofsfuse/erofs-unpack/7z，且非 root，无法继续。"
  return 1
}

extract_squashfs(){
  ensure_out
  if have unsquashfs; then
    info "Squashfs using unsquashfs → $OUT"
    unsquashfs -f -d "$OUT" "$RAW"
    return 0
  fi
  if have 7z; then
    info "Squashfs using 7z → $OUT"
    7z x -y -o"$OUT" "$RAW"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    mnt=$(tmpdir_make)
    trap 'cleanup_mount "$mnt"' EXIT INT TERM
    info "Squashfs mounting ro,loop at $mnt"
    mount -t squashfs -o ro,loop "$RAW" "$mnt"
    copy_tree "$mnt" "$OUT"
    umount "$mnt"; rmdir "$mnt"
    trap - EXIT INT TERM
    return 0
  fi
  err "Squashfs：缺少 unsquashfs/7z，且非 root，无法继续。"
  return 1
}

extract_f2fs(){
  ensure_out
  # 用户态工具对 f2fs 直接解包支持较弱，优先尝试只读挂载
  if [ "$(id -u)" -eq 0 ]; then
    mnt=$(tmpdir_make)
    trap 'cleanup_mount "$mnt"' EXIT INT TERM
    info "F2FS mounting ro,loop at $mnt"
    # 某些内核需 -t f2fs 指定
    if ! mount -t f2fs -o ro,loop "$RAW" "$mnt" 2>/dev/null; then
      # 再试自动类型侦测
      mount -o ro,loop "$RAW" "$mnt"
    fi
    copy_tree "$mnt" "$OUT"
    umount "$mnt"; rmdir "$mnt"
    trap - EXIT INT TERM
    return 0
  fi

  # 若无 root 尝试 7z（大概率无效，但作为兜底）
  if have 7z; then
    warn "F2FS 无 root，尝试 7z 兜底（成功率低）"
    if 7z x -y -o"$OUT" "$RAW"; then
      return 0
    fi
  fi

  err "F2FS：需要 root 只读挂载或提供可用的用户态解包工具。"
  return 1
}

extract_unknown(){
  ensure_out
  if have 7z; then
    info "Unknown FS: trying 7z → $OUT"
    if 7z x -y -o"$OUT" "$RAW"; then
      return 0
    fi
  fi
  err "未知文件系统，且 7z 无法解包。"
  return 1
}

#------------------------- 主流程 -------------------------
fs=$(detect_fs)
info "检测到文件系统类型：$fs"

case "$fs" in
  ext2|ext3|ext4) extract_ext ;;
  erofs)          extract_erofs ;;
  squashfs)       extract_squashfs ;;
  f2fs)           extract_f2fs ;;
  unknown)        extract_unknown ;;
  *)              # 某些发行版把 extN 标成 linux/Unix filesystem
                  case "$fs" in
                    linux|unix|filesystem|linux\ filesystem) extract_ext ;;
                    *) extract_unknown ;;
                  esac
                  ;;
esac

info "解包完成 → $OUT"
