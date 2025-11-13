#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zlo_tool.ops
镜像操作调度模块 - 跨平台封装各类分解/打包流程
"""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple

from .env import ToolEnvironment

LogFunc = Callable[[str], None]
ProgressFunc = Callable[[float, str], None]

SPARSE_MAGIC = 0xED26FF3A


class OperationError(RuntimeError):
    pass


class OperationRunner:
    """
    核心逻辑封装：提供分解/打包等操作接口。
    """

    def __init__(
        self,
        env: ToolEnvironment,
        logger: Optional[LogFunc] = None,
        progress: Optional[ProgressFunc] = None,
    ) -> None:
        self.env = env
        self.logger: LogFunc = logger or (lambda msg: None)
        self.progress_cb: ProgressFunc = progress or (lambda fraction, message: None)

    # ------------------------------------------------------------------ #
    # 公共工具方法
    # ------------------------------------------------------------------ #
    def _log(self, message: str) -> None:
        self.logger(message.rstrip())

    def _update_progress(self, fraction: float, message: str = "") -> None:
        clamped = max(0.0, min(1.0, fraction))
        self.progress_cb(clamped, message)

    def _run(self, cmd: List[str], *, cwd: Optional[Path] = None, capture_output: bool = False) -> str:
        env = self.env.prepare_subprocess_env()
        self._log(f"$ {' '.join(cmd)}")
        if capture_output:
            result = subprocess.run(
                cmd,
                cwd=str(cwd) if cwd else None,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            if result.returncode != 0:
                raise OperationError(f"命令执行失败，退出码：{result.returncode}\n{result.stdout}")
            return result.stdout
        else:
            process = subprocess.Popen(
                cmd,
                cwd=str(cwd) if cwd else None,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            assert process.stdout is not None
            for line in process.stdout:
                self._log(line.rstrip())
            ret = process.wait()
            if ret != 0:
                raise OperationError(f"命令执行失败，退出码：{ret}")
            return ""

    def _ensure_project(self, project_dir: Path) -> Path:
        if not project_dir.exists():
            raise FileNotFoundError(f"项目目录不存在：{project_dir}")
        return project_dir

    # ================================================================== #
    # IMG 操作
    # ================================================================== #
    def unpack_img(self, project_dir: Path, targets: Optional[Iterable[Path]] = None) -> None:
        """分解普通 IMG 镜像到 zlo_out/<分区名>/ 目录"""
        project_dir = self._ensure_project(project_dir)
        images = list(targets) if targets else sorted(project_dir.glob("*.img"))
        if not images:
            raise OperationError("项目中未找到 *.img 文件")

        normal_images: List[Path] = []
        for img_path in images:
            if not img_path.is_file():
                continue
            if self._is_super_image(img_path.name):
                self._log(f"跳过 super 镜像：{img_path.name} （请使用分解 super 功能）")
                continue
            normal_images.append(img_path)

        if not normal_images:
            raise OperationError("未找到可分解的普通 IMG 镜像")

        simg2img = self.env.find_binary("simg2img")
        if simg2img is None:
            raise OperationError("未找到 simg2img，请确认 bin 目录或 PATH 中存在该命令")

        out_root = project_dir / "zlo_out"
        out_root.mkdir(parents=True, exist_ok=True)

        total = len(normal_images)
        self._update_progress(0.0, f"准备分解 {total} 个镜像")

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_dir_path = Path(tmp_dir)
            for index, img_path in enumerate(normal_images, start=1):
                self._log(f"[{index}/{total}] 开始分解：{img_path.name}")
                
                # 检查文件大小
                img_size = img_path.stat().st_size
                if img_size == 0:
                    self._log(f"  ⚠️ 跳过空镜像（0 字节）")
                    self._update_progress(index / total, f"{img_path.name} 已跳过（空文件）")
                    continue
                
                self._log(f"  镜像大小：{img_size // (1024*1024)} MB")
                
                raw_path = tmp_dir_path / f"{img_path.stem}.raw.img"
                if self._is_sparse_image(img_path):
                    self._log("  检测到稀疏镜像，转换为 RAW ...")
                    self._run([str(simg2img), str(img_path), str(raw_path)])
                else:
                    self._log("  已是 RAW 镜像，直接复制")
                    shutil.copyfile(img_path, raw_path)

                extract_dir = out_root / img_path.stem
                extract_dir.mkdir(parents=True, exist_ok=True)

                if not self._extract_fs(raw_path, extract_dir):
                    self._log(f"  ❌ 无法解包 {img_path.name}，请检查：")
                    self._log(f"     1. 是否已安装 7-Zip 并添加到 PATH")
                    self._log(f"     2. 文件系统类型是否支持")
                    self._log(f"     3. 镜像文件是否完整")
                    # 不中断整个流程，继续处理下一个
                    continue

                self._log(f"  ✅ 完成：输出目录 {extract_dir.relative_to(project_dir)}")
                self._update_progress(index / total, f"{img_path.name} 分解完成")

        self._update_progress(1.0, "所有 IMG 分解完成")

    def pack_img(self, project_dir: Path, partitions: Optional[List[str]] = None, sparse: bool = False) -> None:
        """打包 zlo_out/<分区名>/ 为 IMG，输出到 zlo_pack/"""
        project_dir = self._ensure_project(project_dir)
        zlo_out = project_dir / "zlo_out"
        if not zlo_out.exists():
            raise OperationError("未找到 zlo_out 目录，请先分解镜像")

        candidates = [d for d in zlo_out.iterdir() if d.is_dir() and any(d.iterdir())]
        if not candidates:
            raise OperationError("zlo_out 下未发现可打包的分区目录")

        if partitions:
            targets = [zlo_out / p for p in partitions if (zlo_out / p).is_dir()]
        else:
            targets = candidates

        if not targets:
            raise OperationError("未找到有效分区目录")

        pack_dir = project_dir / "zlo_pack"
        pack_dir.mkdir(parents=True, exist_ok=True)

        # 检测打包工具
        backend = self._detect_img_pack_backend()
        if not backend:
            raise OperationError("未找到可用的 EXT4 打包工具：mkfs.ext4 / make_ext4fs / mke2fs+e2fsdroid")

        total = len(targets)
        self._update_progress(0.0, f"准备打包 {total} 个分区")

        for index, part_dir in enumerate(targets, start=1):
            part_name = part_dir.name
            self._log(f"[{index}/{total}] 打包：{part_name}")

            size_mb = self._estimate_partition_size(part_dir)
            self._log(f"  预分配大小：{size_mb} MB")

            raw_img = pack_dir / f"{part_name}.img"
            self._pack_ext4_image(part_dir, raw_img, part_name, size_mb, backend)

            if sparse:
                img2simg = self.env.find_binary("img2simg")
                if img2simg:
                    sparse_img = pack_dir / f"{part_name}.sparse.img"
                    self._log(f"  转换为稀疏镜像：{sparse_img.name}")
                    self._run([str(img2simg), str(raw_img), str(sparse_img)])
                    raw_img.unlink()
                    self._log(f"  完成：{sparse_img.relative_to(project_dir)}")
                else:
                    self._log("  警告：未找到 img2simg，输出 RAW 镜像")
                    self._log(f"  完成：{raw_img.relative_to(project_dir)}")
            else:
                self._log(f"  完成：{raw_img.relative_to(project_dir)}")

            self._update_progress(index / total, f"{part_name} 打包完成")

        self._update_progress(1.0, "所有 IMG 打包完成")

    # ================================================================== #
    # SUPER 操作
    # ================================================================== #
    def unpack_super(self, project_dir: Path) -> None:
        """分解 super 镜像到项目根目录"""
        project_dir = self._ensure_project(project_dir)

        super_img = self._locate_super_image(project_dir)
        if super_img is None:
            raise OperationError("未在项目中找到 super 镜像")

        simg2img = self.env.find_binary("simg2img")
        lpunpack = self.env.find_binary("lpunpack")

        if lpunpack is None:
            raise OperationError("缺少 lpunpack，请确认已放入 bin 目录或安装在 PATH 中")

        self._update_progress(0.0, "准备分解 super 镜像")

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_dir_path = Path(tmp_dir)
            raw_path = super_img

            if self._is_sparse_image(super_img):
                if simg2img is None:
                    raise OperationError("缺少 simg2img，无法处理稀疏 super 镜像")
                raw_path = tmp_dir_path / f"{super_img.stem}.raw.img"
                self._log("检测到稀疏 super 镜像，正在转换为 RAW ...")
                self._run([str(simg2img), str(super_img), str(raw_path)])
                self._update_progress(0.4, "稀疏镜像转换完成")

            self._log(f"使用 lpunpack 解包到：{project_dir}")
            self._run([str(lpunpack), str(raw_path), str(project_dir)])
            self._log("完成 super 镜像分解")
            self._update_progress(1.0, "super 镜像分解完成")

    def pack_super(self, project_dir: Path, partitions: Optional[List[str]] = None) -> None:
        """打包多个分区镜像为 super.img，输出到 zlo_super/"""
        project_dir = self._ensure_project(project_dir)
        pack_dir = project_dir / "zlo_pack"
        if not pack_dir.exists():
            raise OperationError("未找到 zlo_pack 目录，请先打包分区镜像")

        lpmake = self.env.find_binary("lpmake")
        if not lpmake:
            raise OperationError("缺少 lpmake 工具")

        # 收集候选分区（优先 RAW .img）
        candidates = self._collect_super_partitions(pack_dir)
        if not candidates:
            raise OperationError("zlo_pack 下未找到可用的分区镜像 (*.img / *.sparse.img)")

        if partitions:
            selected = {name: path for name, path in candidates.items() if name in partitions}
        else:
            selected = candidates

        if not selected:
            raise OperationError("未选择有效分区")

        self._update_progress(0.0, f"准备打包 {len(selected)} 个分区到 super")

        # 处理稀疏镜像
        simg2img = self.env.find_binary("simg2img")
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_dir_path = Path(tmp_dir)
            raw_images: Dict[str, Path] = {}
            total_size = 0

            for idx, (name, src_path) in enumerate(selected.items(), start=1):
                self._log(f"[{idx}/{len(selected)}] 处理分区：{name}")
                if self._is_sparse_image(src_path):
                    if not simg2img:
                        raise OperationError(f"分区 {name} 是稀疏镜像，但缺少 simg2img")
                    raw_path = tmp_dir_path / f"{name}.raw.img"
                    self._log(f"  解稀疏：{src_path.name} -> {raw_path.name}")
                    self._run([str(simg2img), str(src_path), str(raw_path)])
                    raw_images[name] = raw_path
                else:
                    raw_images[name] = src_path

                size = raw_images[name].stat().st_size
                total_size += size
                self._log(f"  大小：{size // (1024*1024)} MB")

            # 计算 device-size（+15% 余量，4MB 对齐，最小 1GB）
            margin = int(total_size * 0.15)
            device_size = total_size + margin
            align = 4 * 1024 * 1024
            device_size = ((device_size + align - 1) // align) * align
            device_size = max(device_size, 1024 * 1024 * 1024)

            self._log(f"原始大小：{total_size // (1024*1024)} MB")
            self._log(f"设备大小（含余量）：{device_size // (1024*1024)} MB")

            # 组装 lpmake 参数
            out_dir = project_dir / "zlo_super"
            out_dir.mkdir(parents=True, exist_ok=True)
            out_super = out_dir / "super.img"

            args = [
                str(lpmake),
                "--metadata-size", "65536",
                "--super-name", "super",
                "--device-size", str(device_size),
            ]

            for name, raw_path in raw_images.items():
                size = raw_path.stat().st_size
                args.extend([
                    "--partition", f"{name}:readonly",
                    "--image", f"{name}={raw_path}",
                    "--partition-size", f"{name}:{size}",
                ])

            args.extend(["--output", str(out_super)])

            self._log("执行 lpmake ...")
            self._run(args)
            self._log(f"完成：{out_super.relative_to(project_dir)}")
            self._update_progress(1.0, "super 镜像打包完成")

    # ================================================================== #
    # DAT 操作 (system.new.dat)
    # ================================================================== #
    def unpack_dat(self, project_dir: Path, dat_files: Optional[List[Path]] = None) -> None:
        """分解 .new.dat + .transfer.list 到 IMG"""
        project_dir = self._ensure_project(project_dir)

        sdat2img_py = self._find_sdat2img_script()
        if not sdat2img_py:
            raise OperationError("缺少 sdat2img.py 脚本，请放入 bin/Linux 或 bin/windows_x86 目录")

        python = shutil.which("python3") or shutil.which("python")
        if not python:
            raise OperationError("未找到 Python 解释器")

        if dat_files:
            targets = dat_files
        else:
            targets = list(project_dir.rglob("*.new.dat"))

        if not targets:
            raise OperationError("未找到 .new.dat 文件")

        out_dir = project_dir / "zlo_pack"
        out_dir.mkdir(parents=True, exist_ok=True)

        total = len(targets)
        self._update_progress(0.0, f"准备分解 {total} 个 DAT 文件")

        for idx, dat_path in enumerate(targets, start=1):
            self._log(f"[{idx}/{total}] 分解：{dat_path.name}")
            transfer_list = dat_path.parent / f"{dat_path.stem.replace('.new', '')}.transfer.list"
            if not transfer_list.exists():
                self._log(f"  警告：缺少 {transfer_list.name}，跳过")
                continue

            base_name = dat_path.stem.replace(".new", "")
            out_img = out_dir / f"{base_name}.img"

            cmd = [python, str(sdat2img_py), str(transfer_list), str(dat_path), str(out_img)]
            self._run(cmd)
            self._log(f"  完成：{out_img.relative_to(project_dir)}")
            self._update_progress(idx / total, f"{dat_path.name} 分解完成")

        self._update_progress(1.0, "DAT 文件分解完成")

    def pack_dat(self, project_dir: Path, img_files: Optional[List[Path]] = None) -> None:
        """打包 IMG 为 .new.dat 格式"""
        project_dir = self._ensure_project(project_dir)

        img2sdat_py = self._find_img2sdat_script()
        if not img2sdat_py:
            raise OperationError("缺少 img2sdat.py 脚本，请放入 bin/Linux 或 bin/windows_x86 目录")

        python = shutil.which("python3") or shutil.which("python")
        if not python:
            raise OperationError("未找到 Python 解释器")

        if img_files:
            targets = img_files
        else:
            targets = list(project_dir.rglob("*.img"))

        if not targets:
            raise OperationError("未找到 .img 文件")

        out_dir = project_dir / "zlo_pack"
        out_dir.mkdir(parents=True, exist_ok=True)

        total = len(targets)
        self._update_progress(0.0, f"准备打包 {total} 个 IMG 为 DAT")

        for idx, img_path in enumerate(targets, start=1):
            self._log(f"[{idx}/{total}] 打包：{img_path.name}")
            part_name = img_path.stem
            part_out = out_dir / part_name
            part_out.mkdir(parents=True, exist_ok=True)

            cmd = [python, str(img2sdat_py), str(img_path), "-o", str(part_out), "-v", "4", "-p", part_name]
            self._run(cmd)
            self._log(f"  完成：{part_out.relative_to(project_dir)}")
            self._update_progress(idx / total, f"{img_path.name} 打包完成")

        self._update_progress(1.0, "DAT 文件打包完成")

    # ================================================================== #
    # BR 操作 (Brotli)
    # ================================================================== #
    def unpack_br(self, project_dir: Path, files: Optional[Iterable[Path]] = None) -> None:
        """解压 .br 文件"""
        project_dir = self._ensure_project(project_dir)
        brotli = self.env.find_binary("brotli")
        if brotli is None:
            raise OperationError("缺少 brotli 工具")

        targets = list(files) if files else sorted(project_dir.rglob("*.br"))
        if not targets:
            raise OperationError("未找到 .br 文件")

        total = len(targets)
        self._update_progress(0.0, f"准备解压 {total} 个文件")

        for index, br_path in enumerate(targets, start=1):
            if not br_path.is_file():
                continue
            out_path = br_path.with_suffix("")
            self._log(f"[{index}/{total}] 解压：{br_path.name} -> {out_path.name}")
            self._run([str(brotli), "-d", "-f", "-o", str(out_path), str(br_path)])
            self._update_progress(index / total, f"{br_path.name} 解压完成")

        self._update_progress(1.0, "Brotli 文件解压完成")

    def pack_br(self, project_dir: Path, files: Optional[Iterable[Path]] = None, quality: int = 5) -> None:
        """压缩文件为 .br 格式"""
        project_dir = self._ensure_project(project_dir)
        brotli = self.env.find_binary("brotli")
        if brotli is None:
            raise OperationError("缺少 brotli 工具")

        if files:
            targets = list(files)
        else:
            # 默认打包 .dat 文件
            targets = sorted(project_dir.rglob("*.dat"))

        if not targets:
            raise OperationError("未找到可打包的文件")

        total = len(targets)
        self._update_progress(0.0, f"准备压缩 {total} 个文件")

        for index, input_path in enumerate(targets, start=1):
            out_path = Path(str(input_path) + ".br")
            self._log(f"[{index}/{total}] 压缩：{input_path.name} -> {out_path.name} (quality={quality})")
            self._run([str(brotli), "-q", str(quality), "-f", "-o", str(out_path), str(input_path)])
            self._update_progress(index / total, f"{out_path.name} 打包完成")

        self._update_progress(1.0, "Brotli 文件打包完成")

    # ================================================================== #
    # BIN 操作 (payload.bin)
    # ================================================================== #
    def unpack_bin(self, project_dir: Path, payload_bin: Optional[Path] = None) -> None:
        """分解 payload.bin"""
        project_dir = self._ensure_project(project_dir)

        if payload_bin is None:
            candidates = list(project_dir.rglob("payload.bin"))
            if not candidates:
                raise OperationError("未找到 payload.bin")
            payload_bin = candidates[0]

        if not payload_bin.exists():
            raise OperationError(f"payload.bin 不存在：{payload_bin}")

        pdg = self.env.find_binary("payload-dumper-go")
        if not pdg:
            raise OperationError("缺少 payload-dumper-go 工具，请下载并放入 bin 目录")

        out_dir = project_dir / "zlo_pack"
        out_dir.mkdir(parents=True, exist_ok=True)

        self._update_progress(0.0, "准备分解 payload.bin")
        self._log(f"分解：{payload_bin.name}")
        self._log(f"输出：{out_dir.relative_to(project_dir)}")

        # 列出分区
        partitions_raw = self._run([str(pdg), "-l", str(payload_bin)], capture_output=True)
        partitions = [p.strip() for p in partitions_raw.split(",") if p.strip()]

        if not partitions:
            raise OperationError("未能列出 payload.bin 中的分区")

        self._log(f"检测到 {len(partitions)} 个分区")

        # 逐个解包
        total = len(partitions)
        for idx, part in enumerate(partitions, start=1):
            self._log(f"[{idx}/{total}] 解包分区：{part}")
            self._run([str(pdg), "-p", part, "-o", str(out_dir), str(payload_bin)], cwd=out_dir)
            self._update_progress(idx / total, f"{part} 解包完成")

        self._update_progress(1.0, "payload.bin 分解完成")

    def pack_bin(self, project_dir: Path) -> None:
        """打包 payload.bin（暂不支持）"""
        raise OperationError("打包 payload.bin 功能暂未实现，请使用第三方工具")

    # ================================================================== #
    # BAT 操作（合并批处理文件）
    # ================================================================== #
    def pack_bat(self, project_dir: Path, bat_files: List[Path], output: Path) -> None:
        """合并多个 .bat 文件"""
        project_dir = self._ensure_project(project_dir)

        if not bat_files:
            raise OperationError("未指定要合并的 .bat 文件")

        self._update_progress(0.0, "准备合并 BAT 文件")

        with output.open("w", encoding="utf-8") as out_fh:
            total = len(bat_files)
            for idx, bat_path in enumerate(bat_files, start=1):
                if not bat_path.exists():
                    self._log(f"警告：文件不存在，跳过：{bat_path}")
                    continue
                self._log(f"[{idx}/{total}] 合并：{bat_path.name}")
                out_fh.write(f"REM ===== {bat_path.name} =====\n")
                out_fh.write(bat_path.read_text(encoding="utf-8", errors="ignore"))
                out_fh.write("\n\n")
                self._update_progress(idx / total, f"{bat_path.name} 合并完成")

        self._log(f"完成：{output.relative_to(project_dir)}")
        self._update_progress(1.0, "BAT 文件合并完成")

    # ================================================================== #
    # 辅助工具
    # ================================================================== #
    def _is_sparse_image(self, path: Path) -> bool:
        try:
            with path.open("rb") as fh:
                magic = fh.read(4)
            if len(magic) < 4:
                return False
            value = int.from_bytes(magic, "little")
            return value == SPARSE_MAGIC
        except OSError:
            return False

    def _is_super_image(self, filename: str) -> bool:
        name = filename.lower()
        return name.startswith("super") and name.endswith(".img")

    def _locate_super_image(self, project_dir: Path) -> Optional[Path]:
        preferred = [project_dir / "super.img"]
        variants = list(project_dir.glob("super_*.img")) + list(project_dir.glob("super*.img"))
        candidates = preferred + sorted(variants)
        for path in candidates:
            if path.exists():
                return path
        return None

    def _extract_fs(self, raw_path: Path, out_dir: Path) -> bool:
        """尝试多种方式提取文件系统"""
        # 检查文件大小
        file_size = raw_path.stat().st_size
        if file_size == 0:
            self._log("  ⚠️ 镜像文件为空，跳过解包")
            return False
        
        # 先检测文件系统类型
        fs_type = self._detect_filesystem_type(raw_path)
        self._log(f"  检测到文件系统类型：{fs_type or '未知'}")

        # 自定义脚本（Python）
        custom_py = self.env.tool_dir / "unpack_img_fs.py"
        if custom_py.exists():
            python = shutil.which("python") or shutil.which("python3")
            if python:
                try:
                    self._run([python, str(custom_py), str(raw_path), str(out_dir)])
                    if any(out_dir.iterdir()):
                        return True
                except OperationError:
                    self._log("  自定义 Python 脚本解包失败，尝试其他方式")

        # 自定义 Shell（Linux/Mac）
        custom_sh = self.env.tool_dir / "unpack_img_fs.sh"
        if custom_sh.exists() and not self.env.is_windows:
            try:
                self._run(["sh", str(custom_sh), str(raw_path), str(out_dir)])
                if any(out_dir.iterdir()):
                    return True
            except OperationError:
                self._log("  自定义 Shell 脚本解包失败，尝试其他方式")

        # 根据文件系统类型选择合适的工具
        if fs_type == "erofs":
            if self._extract_erofs(raw_path, out_dir):
                return True
        elif fs_type == "ext4":
            if self._extract_ext4(raw_path, out_dir):
                return True
        elif fs_type == "f2fs":
            if self._extract_f2fs(raw_path, out_dir):
                return True

        # 通用方法：尝试 7z
        seven_zip = self.env.find_binary("7z") or self.env.find_binary("7za")
        if seven_zip:
            try:
                self._log("  尝试使用 7-Zip 解包...")
                self._run([str(seven_zip), "x", "-y", f"-o{out_dir}", str(raw_path)])
                # 验证是否真的提取了文件
                if any(out_dir.iterdir()):
                    return True
                else:
                    self._log("  ⚠️ 7-Zip 未提取任何文件（可能不是支持的文件系统）")
            except OperationError:
                self._log("  ⚠️ 7-Zip 无法识别此镜像格式")
        else:
            self._log("  ⚠️ 未找到 7-Zip 工具")
            self._log("     Windows 安装方法：")
            self._log("       1. scoop install 7zip")
            self._log("       2. 或从 https://www.7-zip.org/ 下载安装")
            self._log("       3. 或将 7za.exe 放入 bin/windows_x86/ 目录")

        return False

    def _detect_filesystem_type(self, raw_path: Path) -> Optional[str]:
        """检测文件系统类型"""
        try:
            with raw_path.open("rb") as f:
                # 读取前 4KB
                header = f.read(4096)
                
                # EROFS magic: 0xE0F5E1E2 at offset 1024
                if len(header) >= 1028:
                    erofs_magic = int.from_bytes(header[1024:1028], "little")
                    if erofs_magic == 0xE0F5E1E2:
                        return "erofs"
                
                # EXT4 magic: 0xEF53 at offset 0x438 (1080)
                if len(header) >= 1082:
                    ext_magic = int.from_bytes(header[1080:1082], "little")
                    if ext_magic == 0xEF53:
                        return "ext4"
                
                # F2FS magic: 0xF2F52010 at offset 0x400 (1024)
                if len(header) >= 1028:
                    f2fs_magic = int.from_bytes(header[1024:1028], "little")
                    if f2fs_magic == 0xF2F52010:
                        return "f2fs"
                
                # SquashFS magic: "hsqs" at offset 0
                if header[:4] == b"hsqs" or header[:4] == b"sqsh":
                    return "squashfs"
                
        except Exception:
            pass
        return None

    def _extract_erofs(self, raw_path: Path, out_dir: Path) -> bool:
        """使用 extract.erofs 提取 EROFS 文件系统"""
        extract_erofs = self.env.find_binary("extract.erofs")
        if not extract_erofs:
            self._log("  未找到 extract.erofs 工具")
            return False
        
        try:
            self._log("  使用 extract.erofs 解包...")
            # extract.erofs 的参数格式
            self._run([str(extract_erofs), "-i", str(raw_path), "-o", str(out_dir), "-x"])
            # 验证是否成功
            if any(out_dir.iterdir()):
                return True
        except OperationError:
            self._log("  extract.erofs 解包失败")
        return False

    def _extract_ext4(self, raw_path: Path, out_dir: Path) -> bool:
        """提取 EXT4 文件系统"""
        # 尝试 debugfs (Linux)
        if not self.env.is_windows:
            debugfs = shutil.which("debugfs")
            if debugfs:
                try:
                    self._log("  使用 debugfs 解包 EXT4...")
                    # 使用 debugfs 提取
                    cmd_file = out_dir.parent / f".debugfs_{raw_path.stem}.txt"
                    cmd_file.write_text(f"rdump / {out_dir}\nquit\n")
                    self._run([debugfs, "-f", str(cmd_file), str(raw_path)])
                    cmd_file.unlink(missing_ok=True)
                    if any(out_dir.iterdir()):
                        return True
                except OperationError:
                    self._log("  debugfs 解包失败")
        
        # 尝试 7z（通常对 ext4 有效）
        return False

    def _extract_f2fs(self, raw_path: Path, out_dir: Path) -> bool:
        """提取 F2FS 文件系统"""
        # 尝试 fsck.f2fs + sload.f2fs 组合
        extract_f2fs = self.env.find_binary("extract.f2fs")
        if extract_f2fs:
            try:
                self._log("  使用 extract.f2fs 解包...")
                self._run([str(extract_f2fs), str(raw_path), str(out_dir)])
                if any(out_dir.iterdir()):
                    return True
            except OperationError:
                self._log("  extract.f2fs 解包失败")
        return False

    def _detect_img_pack_backend(self) -> Optional[str]:
        """检测可用的 EXT4 打包后端"""
        # 优先 mkfs.ext4 -d
        mkfs_ext4 = self.env.find_binary("mkfs.ext4")
        if mkfs_ext4:
            return "mkfs.ext4"

        # make_ext4fs
        make_ext4fs = self.env.find_binary("make_ext4fs")
        if make_ext4fs:
            return "make_ext4fs"

        # mke2fs + e2fsdroid
        mke2fs = self.env.find_binary("mke2fs")
        e2fsdroid = self.env.find_binary("e2fsdroid")
        if mke2fs and e2fsdroid:
            return "mke2fs+e2fsdroid"

        return None

    def _estimate_partition_size(self, part_dir: Path) -> int:
        """估算分区大小（MB），+30% 余量，最小 256MB，16MB 对齐"""
        total_bytes = sum(f.stat().st_size for f in part_dir.rglob("*") if f.is_file())
        size_mb = total_bytes // (1024 * 1024)
        extra = int(size_mb * 0.3)
        prealloc = size_mb + extra
        prealloc = max(prealloc, 256)
        # 16MB 对齐
        prealloc = ((prealloc + 15) // 16) * 16
        return prealloc

    def _pack_ext4_image(self, src_dir: Path, out_img: Path, label: str, size_mb: int, backend: str) -> None:
        """使用检测到的后端打包 EXT4 镜像"""
        if backend == "mkfs.ext4":
            mkfs_ext4 = self.env.find_binary("mkfs.ext4")
            assert mkfs_ext4
            self._run([
                str(mkfs_ext4),
                "-L", label,
                "-d", str(src_dir),
                str(out_img),
                f"{size_mb}M"
            ])
        elif backend == "make_ext4fs":
            make_ext4fs = self.env.find_binary("make_ext4fs")
            assert make_ext4fs
            self._run([
                str(make_ext4fs),
                "-l", f"{size_mb}M",
                "-a", label,
                str(out_img),
                str(src_dir)
            ])
        elif backend == "mke2fs+e2fsdroid":
            mke2fs = self.env.find_binary("mke2fs")
            e2fsdroid = self.env.find_binary("e2fsdroid")
            assert mke2fs and e2fsdroid
            self._run([str(mke2fs), "-t", "ext4", "-L", label, str(out_img), f"{size_mb}M"])
            self._run([str(e2fsdroid), "-a", f"/{label}", "-f", str(src_dir), str(out_img)])
        else:
            raise OperationError("未知的打包后端")

    def _collect_super_partitions(self, pack_dir: Path) -> Dict[str, Path]:
        """收集 zlo_pack 下的分区镜像（优先 RAW .img）"""
        partitions: Dict[str, Path] = {}

        # 收集 RAW .img
        for img in pack_dir.glob("*.img"):
            if img.suffix == ".img" and ".sparse" not in img.stem:
                partitions[img.stem] = img

        # 收集仅有 .sparse.img 的
        for sparse_img in pack_dir.glob("*.sparse.img"):
            name = sparse_img.stem.replace(".sparse", "")
            if name not in partitions:
                partitions[name] = sparse_img

        return partitions

    def _find_sdat2img_script(self) -> Optional[Path]:
        """查找 sdat2img.py"""
        candidates = [
            self.env.bin_dir / "sdat2img.py",
            self.env.tool_dir / "sdat2img.py",
            self.env.root_dir / "bin" / "Linux" / "sdat2img.py",
        ]
        for path in candidates:
            if path.exists():
                return path
        return None

    def _find_img2sdat_script(self) -> Optional[Path]:
        """查找 img2sdat.py"""
        candidates = [
            self.env.bin_dir / "img2sdat.py",
            self.env.tool_dir / "img2sdat.py",
            self.env.root_dir / "bin" / "Linux" / "img2sdat.py",
        ]
        for path in candidates:
            if path.exists():
                return path
        return None
