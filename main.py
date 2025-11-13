#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ZLO Android 镜像工具 - 主入口
支持 GUI 与 CLI 模式
"""
import argparse
import sys
from pathlib import Path

from zlo_tool import __version__
from zlo_tool.env import default_environment
from zlo_tool.gui import run_gui
from zlo_tool.ops import OperationError, OperationRunner
from zlo_tool.projects import InvalidProjectName, ProjectExistsError, ProjectManager


def main() -> int:
    parser = argparse.ArgumentParser(
        description="ZLO Android 镜像工具 - 跨平台分解与打包助手",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")

    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # GUI 模式
    parser_gui = subparsers.add_parser("gui", help="启动图形界面")

    # 项目管理
    parser_list = subparsers.add_parser("list", help="列出所有项目")
    parser_create = subparsers.add_parser("create", help="创建新项目")
    parser_create.add_argument("name", help="项目名称")
    parser_delete = subparsers.add_parser("delete", help="删除项目")
    parser_delete.add_argument("name", help="项目名称")

    # IMG 操作
    parser_unpack_img = subparsers.add_parser("unpack-img", help="分解 IMG 镜像")
    parser_unpack_img.add_argument("project", help="项目名称")

    parser_pack_img = subparsers.add_parser("pack-img", help="打包 IMG 镜像")
    parser_pack_img.add_argument("project", help="项目名称")
    parser_pack_img.add_argument("--sparse", action="store_true", help="输出稀疏镜像")

    # SUPER 操作
    parser_unpack_super = subparsers.add_parser("unpack-super", help="分解 SUPER 镜像")
    parser_unpack_super.add_argument("project", help="项目名称")

    parser_pack_super = subparsers.add_parser("pack-super", help="打包 SUPER 镜像")
    parser_pack_super.add_argument("project", help="项目名称")

    # DAT 操作
    parser_unpack_dat = subparsers.add_parser("unpack-dat", help="分解 DAT 文件")
    parser_unpack_dat.add_argument("project", help="项目名称")

    parser_pack_dat = subparsers.add_parser("pack-dat", help="打包 DAT 文件")
    parser_pack_dat.add_argument("project", help="项目名称")

    # BR 操作
    parser_unpack_br = subparsers.add_parser("unpack-br", help="解压 Brotli 文件")
    parser_unpack_br.add_argument("project", help="项目名称")

    parser_pack_br = subparsers.add_parser("pack-br", help="压缩为 Brotli")
    parser_pack_br.add_argument("project", help="项目名称")
    parser_pack_br.add_argument("--quality", type=int, default=5, help="压缩等级 (0-11)")

    # BIN 操作
    parser_unpack_bin = subparsers.add_parser("unpack-bin", help="分解 payload.bin")
    parser_unpack_bin.add_argument("project", help="项目名称")

    args = parser.parse_args()

    env = default_environment()

    # GUI 模式
    if args.command == "gui" or args.command is None:
        run_gui(env)
        return 0

    # CLI 模式
    project_manager = ProjectManager(env)

    try:
        # 项目管理
        if args.command == "list":
            projects = project_manager.list_projects()
            if not projects:
                print("暂无项目")
            else:
                print(f"共有 {len(projects)} 个项目：")
                for proj in projects:
                    print(f"  - {proj.name}")
            return 0

        elif args.command == "create":
            project_manager.create_project(args.name)
            print(f"✅ 项目已创建：{args.name}")
            return 0

        elif args.command == "delete":
            project_manager.delete_project(args.name)
            print(f"✅ 项目已删除：{args.name}")
            return 0

        # 操作类命令
        project_dir = env.root_dir / args.project
        if not project_dir.exists():
            print(f"❌ 项目不存在：{args.project}", file=sys.stderr)
            return 1

        runner = OperationRunner(
            env=env,
            logger=lambda msg: print(msg),
            progress=lambda fraction, message: print(f"[{fraction * 100:.1f}%] {message}"),
        )

        if args.command == "unpack-img":
            runner.unpack_img(project_dir)
        elif args.command == "pack-img":
            runner.pack_img(project_dir, sparse=args.sparse)
        elif args.command == "unpack-super":
            runner.unpack_super(project_dir)
        elif args.command == "pack-super":
            runner.pack_super(project_dir)
        elif args.command == "unpack-dat":
            runner.unpack_dat(project_dir)
        elif args.command == "pack-dat":
            runner.pack_dat(project_dir)
        elif args.command == "unpack-br":
            runner.unpack_br(project_dir)
        elif args.command == "pack-br":
            runner.pack_br(project_dir, quality=args.quality)
        elif args.command == "unpack-bin":
            runner.unpack_bin(project_dir)
        else:
            parser.print_help()
            return 1

        print("✅ 操作完成")
        return 0

    except (ProjectExistsError, InvalidProjectName, FileNotFoundError, OperationError) as exc:
        print(f"❌ 错误：{exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"❌ 意外错误：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
