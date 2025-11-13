from __future__ import annotations

import re
import shutil
from pathlib import Path
from typing import List

from .env import ToolEnvironment

RESERVED_NAMES = {"bin", "tool", "__pycache__"}
PROJECT_NAME_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class ProjectExistsError(FileExistsError):
    pass


class InvalidProjectName(ValueError):
    pass


class ProjectManager:
    """
    负责项目目录的增删查。
    """

    def __init__(self, env: ToolEnvironment) -> None:
        self.env = env
        self.root_dir = env.root

    # ------------------------------------------------------------------ #
    def list_projects(self) -> List[str]:
        names: List[str] = []
        for child in sorted(self.root_dir.iterdir()):
            if not child.is_dir():
                continue
            if child.name in RESERVED_NAMES:
                continue
            if child.name.startswith("."):
                continue
            names.append(child.name)
        return names

    def create_project(self, name: str) -> Path:
        self._validate_name(name)
        project_dir = self.root_dir / name
        if project_dir.exists():
            raise ProjectExistsError(f"项目 {name} 已存在")
        project_dir.mkdir(parents=True, exist_ok=False)
        (project_dir / "zlo_out").mkdir(exist_ok=True)
        (project_dir / "config").mkdir(exist_ok=True)
        return project_dir

    def delete_project(self, name: str) -> None:
        self._validate_name(name)
        if name in RESERVED_NAMES:
            raise InvalidProjectName(f"禁止删除保留目录：{name}")
        target = self.root_dir / name
        if target.exists():
            shutil.rmtree(target)

    # ------------------------------------------------------------------ #
    def _validate_name(self, name: str) -> None:
        if not name or not PROJECT_NAME_PATTERN.match(name):
            raise InvalidProjectName("项目名仅支持字母、数字、下划线、点、短横，长度 1~64")

