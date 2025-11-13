from __future__ import annotations

import os
import platform
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Optional


@dataclass(frozen=True)
class BinaryInfo:
    name: str
    path: Optional[Path]


class ToolEnvironment:
    """
    统一维护工具根目录、二进制目录与环境变量配置。

    - 自动根据当前系统选择 ``bin/Windows_x86`` 或 ``bin/Linux``。
    - 在执行外部命令时，可通过 ``prepare_subprocess_env`` 注入 PATH。
    """

    def __init__(self, root_path: Optional[Path] = None) -> None:
        self.root: Path = Path(root_path or Path(__file__).resolve().parents[1])
        self.system: str = platform.system()
        self.bin_root: Path = self.root / "bin"
        self.tool_dir: Path = self.root / "tool"

        self._bin_dir: Optional[Path] = None
        self._cache: Dict[str, Optional[Path]] = {}

    # --------------------------------------------------------------------- #
    # 属性快照
    # --------------------------------------------------------------------- #
    @property
    def bin_dir(self) -> Path:
        if self._bin_dir is None:
            self._bin_dir = self._detect_bin_dir()
        return self._bin_dir

    @property
    def is_windows(self) -> bool:
        return self.system.lower().startswith("win")

    @property
    def is_linux(self) -> bool:
        return self.system.lower() == "linux"

    # --------------------------------------------------------------------- #
    # 对外接口
    # --------------------------------------------------------------------- #
    def find_binary(self, name: str, *, allow_system_path: bool = True) -> Optional[Path]:
        """
        返回给定命令对应的可执行文件路径；找不到时返回 ``None``。
        """
        if name in self._cache:
            return self._cache[name]

        candidates: Iterable[Path] = self._bin_candidates(name)
        for candidate in candidates:
            if candidate.exists() and os.access(candidate, os.X_OK):
                self._cache[name] = candidate
                return candidate

        if allow_system_path:
            sys_path = shutil.which(name)
            if sys_path:
                path = Path(sys_path)
                self._cache[name] = path
                return path

        self._cache[name] = None
        return None

    def require_binary(self, name: str) -> Path:
        """
        若找不到指定命令，则抛出 ``FileNotFoundError``。
        """
        path = self.find_binary(name)
        if path is None:
            raise FileNotFoundError(f"未找到依赖命令：{name}")
        return path

    def prepare_subprocess_env(self) -> Dict[str, str]:
        """
        返回用于 ``subprocess`` 的环境变量字典，确保自带 ``bin`` 已注入 PATH。
        """
        env = os.environ.copy()
        existing_path = env.get("PATH", "")
        path_entries = [str(self.bin_dir)]
        if existing_path:
            path_entries.append(existing_path)
        env["PATH"] = os.pathsep.join(path_entries)
        return env

    # --------------------------------------------------------------------- #
    # 内部工具方法
    # --------------------------------------------------------------------- #
    def _detect_bin_dir(self) -> Path:
        if self.is_windows:
            candidate = self.bin_root / "windows_x86"
        elif self.is_linux:
            candidate = self.bin_root / "Linux"
        else:
            candidate = self.bin_root

        if candidate.exists():
            return candidate
        return self.bin_root

    def _bin_candidates(self, name: str) -> Iterable[Path]:
        if self.is_windows:
            exe_names = [f"{name}.exe", name]
        else:
            exe_names = [name]
        for exe_name in exe_names:
            yield self.bin_dir / exe_name


def default_environment() -> ToolEnvironment:
    return ToolEnvironment()

