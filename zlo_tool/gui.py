#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zlo_tool.gui
Tkinter 图形界面 - 美化版，支持完整操作与进度条
"""
import queue
import threading
from pathlib import Path
from typing import Any, Iterable, List, Optional, Tuple

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

from .env import ToolEnvironment, default_environment
from .ops import OperationError, OperationRunner
from .projects import InvalidProjectName, ProjectExistsError, ProjectManager


class ZLOApp(tk.Tk):
    """
    主窗口：项目管理 + 镜像操作
    """

    def __init__(self, env: Optional[ToolEnvironment] = None) -> None:
        super().__init__()
        self.title("ZLO Android 镜像工具 - 跨平台版")
        self.geometry("1280x760")
        self.minsize(1100, 650)

        self.env = env or default_environment()
        self.project_manager = ProjectManager(self.env)

        self.log_queue: "queue.Queue[str]" = queue.Queue()
        self.progress_queue: "queue.Queue[Tuple[float, str]]" = queue.Queue()
        self.worker: Optional[threading.Thread] = None

        self.style = ttk.Style(self)
        self._init_styles()
        self._build_widgets()
        self._refresh_projects()
        self.after(120, self._poll_queues)

    # ================================================================== #
    # UI 样式与布局
    # ================================================================== #
    def _init_styles(self) -> None:
        """初始化现代化主题样式"""
        self.configure(bg="#f0f2f5")
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            pass

        # 标题样式
        self.style.configure("Title.TLabel", font=("微软雅黑", 22, "bold"), foreground="#1a1d29")
        self.style.configure("Subtitle.TLabel", font=("微软雅黑", 10), foreground="#6c757d")

        # 卡片框样式
        self.style.configure("Card.TLabelframe", padding=18, relief=tk.FLAT, background="#ffffff")
        self.style.configure("Card.TLabelframe.Label", font=("微软雅黑", 13, "bold"), foreground="#2c3e50")

        # 按钮样式
        self.style.configure(
            "Primary.TButton",
            font=("微软雅黑", 10, "bold"),
            padding=(16, 8),
            relief=tk.FLAT,
            background="#4a90e2",
            foreground="#ffffff",
        )
        self.style.map(
            "Primary.TButton",
            background=[("active", "#357abd"), ("disabled", "#d0d3db")],
            foreground=[("disabled", "#868e96")],
        )

        self.style.configure(
            "Secondary.TButton",
            font=("微软雅黑", 9),
            padding=(12, 6),
            relief=tk.FLAT,
            background="#6c757d",
            foreground="#ffffff",
        )
        self.style.map(
            "Secondary.TButton",
            background=[("active", "#5a6268"), ("disabled", "#e9ecef")],
        )

        self.style.configure(
            "Danger.TButton",
            font=("微软雅黑", 9),
            padding=(12, 6),
            relief=tk.FLAT,
            background="#e74c3c",
            foreground="#ffffff",
        )
        self.style.map("Danger.TButton", background=[("active", "#c0392b")])

        # 进度条样式
        self.style.configure(
            "Green.Horizontal.TProgressbar",
            troughcolor="#e9ecef",
            background="#28a745",
            bordercolor="#ffffff",
            lightcolor="#28a745",
            darkcolor="#28a745",
        )

    def _build_widgets(self) -> None:
        """构建主窗口布局"""
        # 头部
        header = ttk.Frame(self, padding=(24, 20, 24, 12))
        header.pack(fill=tk.X)
        header.configure(style="TFrame")

        ttk.Label(header, text="🧰 ZLO 镜像工具箱", style="Title.TLabel").pack(anchor=tk.W)
        ttk.Label(
            header,
            text="支持 IMG / SUPER / DAT / BR / BIN 等多种格式的分解与打包",
            style="Subtitle.TLabel",
        ).pack(anchor=tk.W, pady=(6, 0))

        ttk.Separator(self).pack(fill=tk.X, padx=24, pady=(0, 16))

        # 主容器（左右分栏）
        main_container = ttk.PanedWindow(self, orient=tk.HORIZONTAL)
        main_container.pack(fill=tk.BOTH, expand=True, padx=24, pady=(0, 24))

        # 左侧：项目管理
        left_frame = self._build_project_panel()
        main_container.add(left_frame, weight=3)

        # 右侧：操作面板
        right_frame = self._build_operation_panel()
        main_container.add(right_frame, weight=4)

    def _build_project_panel(self) -> ttk.Frame:
        """左侧项目管理面板"""
        panel = ttk.Labelframe(text="📁 项目管理", style="Card.TLabelframe")
        panel.columnconfigure(0, weight=1)
        panel.rowconfigure(0, weight=1)

        # 项目列表
        list_frame = ttk.Frame(panel)
        list_frame.grid(row=0, column=0, sticky="nsew", pady=(0, 12))

        self.project_list = tk.Listbox(
            list_frame,
            height=20,
            exportselection=False,
            font=("微软雅黑", 11),
            activestyle="dotbox",
            relief=tk.FLAT,
            bg="#f8f9fa",
            selectbackground="#4a90e2",
            selectforeground="#ffffff",
        )
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.project_list.yview)
        self.project_list.configure(yscrollcommand=scrollbar.set)
        self.project_list.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # 按钮区
        btn_frame = ttk.Frame(panel)
        btn_frame.grid(row=1, column=0, sticky="ew")
        btn_frame.columnconfigure((0, 1, 2), weight=1)

        ttk.Button(btn_frame, text="➕ 新建", style="Primary.TButton", command=self._on_create_project).grid(
            row=0, column=0, padx=(0, 6), sticky="ew"
        )
        ttk.Button(btn_frame, text="🔄 刷新", style="Secondary.TButton", command=self._refresh_projects).grid(
            row=0, column=1, padx=6, sticky="ew"
        )
        ttk.Button(btn_frame, text="🗑️ 删除", style="Danger.TButton", command=self._on_delete_project).grid(
            row=0, column=2, padx=(6, 0), sticky="ew"
        )

        return panel

    def _build_operation_panel(self) -> ttk.Frame:
        """右侧操作面板"""
        panel = ttk.Frame(self)

        # 操作区
        ops_frame = ttk.Labelframe(panel, text="⚙️ 镜像操作", style="Card.TLabelframe")
        ops_frame.pack(fill=tk.BOTH, expand=False, pady=(0, 12))

        # 网格布局：3 列
        ops_frame.columnconfigure((0, 1, 2), weight=1)

        operations = [
            ("📤 分解 IMG", self._on_unpack_img, "分解普通分区镜像"),
            ("📥 打包 IMG", self._on_pack_img, "打包为分区镜像"),
            ("📤 分解 SUPER", self._on_unpack_super, "分解 super 动态分区"),
            ("📥 打包 SUPER", self._on_pack_super, "打包为 super 镜像"),
            ("📤 分解 DAT", self._on_unpack_dat, "分解 system.new.dat"),
            ("📥 打包 DAT", self._on_pack_dat, "打包为 .new.dat"),
            ("📤 解压 BR", self._on_unpack_br, "解压 Brotli 文件"),
            ("📥 压缩 BR", self._on_pack_br, "压缩为 .br 格式"),
            ("📤 分解 BIN", self._on_unpack_bin, "分解 payload.bin"),
            # ("📥 打包 BIN", self._on_pack_bin, "打包 payload（未实现）"),
        ]

        for idx, (text, command, tooltip) in enumerate(operations):
            row = idx // 3
            col = idx % 3
            btn = ttk.Button(ops_frame, text=text, style="Secondary.TButton", command=command)
            btn.grid(row=row, column=col, padx=6, pady=6, sticky="ew")
            # 简单的 tooltip（可选）
            # btn.bind("<Enter>", lambda e, t=tooltip: self._log(t))

        # 进度条区
        progress_frame = ttk.Labelframe(panel, text="📊 执行进度", style="Card.TLabelframe")
        progress_frame.pack(fill=tk.X, pady=(0, 12))

        self.progress_var = tk.DoubleVar(value=0.0)
        self.progress_bar = ttk.Progressbar(
            progress_frame,
            orient=tk.HORIZONTAL,
            mode="determinate",
            variable=self.progress_var,
            maximum=100.0,
            style="Green.Horizontal.TProgressbar",
        )
        self.progress_bar.pack(fill=tk.X, pady=(0, 8))

        self.progress_label = ttk.Label(progress_frame, text="等待操作...", font=("微软雅黑", 9), foreground="#6c757d")
        self.progress_label.pack(anchor=tk.W)

        # 日志区
        log_frame = ttk.Labelframe(panel, text="📜 操作日志", style="Card.TLabelframe")
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.log_text = tk.Text(
            log_frame,
            height=14,
            wrap=tk.WORD,
            font=("Consolas", 9),
            bg="#2c3e50",
            fg="#ecf0f1",
            insertbackground="#ecf0f1",
            relief=tk.FLAT,
            state=tk.DISABLED,
        )
        log_scroll = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=log_scroll.set)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)

        return panel

    # ================================================================== #
    # 项目管理
    # ================================================================== #
    def _refresh_projects(self) -> None:
        """刷新项目列表"""
        self.project_list.delete(0, tk.END)
        for proj_name in self.project_manager.list_projects():
            self.project_list.insert(tk.END, proj_name)

    def _get_selected_project(self) -> Optional[Path]:
        """获取当前选中的项目目录"""
        sel = self.project_list.curselection()
        if not sel:
            messagebox.showwarning("提示", "请先选择一个项目")
            return None
        project_name = self.project_list.get(sel[0])
        return self.project_manager.root_dir / project_name

    def _on_create_project(self) -> None:
        """新建项目"""
        name = simpledialog.askstring("新建项目", "请输入项目名称：")
        if not name:
            return
        try:
            self.project_manager.create_project(name)
            self._refresh_projects()
            self._log(f"✅ 项目已创建：{name}")
        except (ProjectExistsError, InvalidProjectName) as exc:
            messagebox.showerror("错误", str(exc))

    def _on_delete_project(self) -> None:
        """删除项目"""
        sel = self.project_list.curselection()
        if not sel:
            messagebox.showwarning("提示", "请先选择要删除的项目")
            return
        project_name = self.project_list.get(sel[0])
        if not messagebox.askyesno("确认删除", f"确定要删除项目 \"{project_name}\" 吗？\n此操作不可恢复！"):
            return
        try:
            self.project_manager.delete_project(project_name)
            self._refresh_projects()
            self._log(f"✅ 项目已删除：{project_name}")
        except FileNotFoundError as exc:
            messagebox.showerror("错误", str(exc))

    # ================================================================== #
    # 操作调度
    # ================================================================== #
    def _run_operation(self, operation_name: str, func, *args, **kwargs) -> None:
        """后台线程执行操作"""
        if self.worker and self.worker.is_alive():
            messagebox.showwarning("提示", "当前有任务正在执行，请稍候")
            return

        self._log(f"▶ 开始：{operation_name}")
        self._update_progress(0.0, "准备中...")

        def worker():
            try:
                func(*args, **kwargs)
                self.log_queue.put(f"✅ {operation_name} 完成")
                self.progress_queue.put((1.0, f"{operation_name} 完成"))
            except OperationError as exc:
                self.log_queue.put(f"❌ 操作失败：{exc}")
                self.progress_queue.put((0.0, "操作失败"))
            except Exception as exc:
                self.log_queue.put(f"❌ 意外错误：{exc}")
                self.progress_queue.put((0.0, "意外错误"))

        self.worker = threading.Thread(target=worker, daemon=True)
        self.worker.start()

    def _on_unpack_img(self) -> None:
        """分解 IMG"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        
        # 查找所有 IMG 文件
        img_files = sorted(project_dir.glob("*.img"))
        if not img_files:
            messagebox.showwarning("提示", "项目中未找到 .img 文件")
            return
        
        # 过滤掉 super 镜像
        normal_imgs = [f for f in img_files if not f.name.lower().startswith("super")]
        if not normal_imgs:
            messagebox.showinfo("提示", "仅找到 super 镜像，请使用「分解 SUPER」功能")
            return
        
        # 询问用户选择
        if len(normal_imgs) == 1:
            targets = normal_imgs
        else:
            choice = self._show_file_selection_dialog(
                "选择要分解的镜像",
                [f.name for f in normal_imgs],
                "分解镜像"
            )
            if choice is None:
                return
            elif choice == "all":
                targets = normal_imgs
            else:
                targets = [normal_imgs[i] for i in choice]
        
        runner = self._make_runner()
        self._run_operation("分解 IMG", runner.unpack_img, project_dir, targets)

    def _on_pack_img(self) -> None:
        """打包 IMG"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        
        zlo_out = project_dir / "zlo_out"
        if not zlo_out.exists():
            messagebox.showwarning("提示", "未找到 zlo_out 目录，请先分解镜像")
            return
        
        # 查找可打包的分区
        partitions = [d.name for d in zlo_out.iterdir() if d.is_dir() and any(d.iterdir())]
        if not partitions:
            messagebox.showwarning("提示", "zlo_out 下没有可打包的分区目录")
            return
        
        # 询问用户选择
        if len(partitions) == 1:
            selected_parts = None  # 打包全部
        else:
            choice = self._show_file_selection_dialog(
                "选择要打包的分区",
                partitions,
                "打包镜像"
            )
            if choice is None:
                return
            elif choice == "all":
                selected_parts = None
            else:
                selected_parts = [partitions[i] for i in choice]
        
        sparse = messagebox.askyesno("打包选项", "是否输出稀疏镜像（.sparse.img）？")
        runner = self._make_runner()
        self._run_operation("打包 IMG", runner.pack_img, project_dir, selected_parts, sparse)

    def _on_unpack_super(self) -> None:
        """分解 SUPER"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        runner = self._make_runner()
        self._run_operation("分解 SUPER", runner.unpack_super, project_dir)

    def _on_pack_super(self) -> None:
        """打包 SUPER"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        
        zlo_pack = project_dir / "zlo_pack"
        if not zlo_pack.exists():
            messagebox.showwarning("提示", "未找到 zlo_pack 目录，请先打包分区镜像")
            return
        
        # 查找可用的分区镜像
        partition_imgs = {}
        for img in zlo_pack.glob("*.img"):
            if ".sparse" not in img.stem:
                partition_imgs[img.stem] = img
        for sparse_img in zlo_pack.glob("*.sparse.img"):
            name = sparse_img.stem.replace(".sparse", "")
            if name not in partition_imgs:
                partition_imgs[name] = sparse_img
        
        if not partition_imgs:
            messagebox.showwarning("提示", "zlo_pack 下未找到分区镜像文件")
            return
        
        partition_names = sorted(partition_imgs.keys())
        
        # 询问用户选择
        if len(partition_names) <= 2:
            selected_parts = None  # 打包全部
        else:
            choice = self._show_file_selection_dialog(
                "选择要打包到 super 的分区",
                partition_names,
                "打包 SUPER"
            )
            if choice is None:
                return
            elif choice == "all":
                selected_parts = None
            else:
                selected_parts = [partition_names[i] for i in choice]
        
        runner = self._make_runner()
        self._run_operation("打包 SUPER", runner.pack_super, project_dir, selected_parts)

    def _on_unpack_dat(self) -> None:
        """分解 DAT"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        runner = self._make_runner()
        self._run_operation("分解 DAT", runner.unpack_dat, project_dir)

    def _on_pack_dat(self) -> None:
        """打包 DAT"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        runner = self._make_runner()
        self._run_operation("打包 DAT", runner.pack_dat, project_dir)

    def _on_unpack_br(self) -> None:
        """解压 BR"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        runner = self._make_runner()
        self._run_operation("解压 BR", runner.unpack_br, project_dir)

    def _on_pack_br(self) -> None:
        """压缩 BR"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        quality = simpledialog.askinteger("压缩等级", "请输入 Brotli 压缩等级 (0-11)：", initialvalue=5, minvalue=0, maxvalue=11)
        if quality is None:
            return
        runner = self._make_runner()
        self._run_operation("压缩 BR", runner.pack_br, project_dir, None, quality)

    def _on_unpack_bin(self) -> None:
        """分解 BIN"""
        project_dir = self._get_selected_project()
        if not project_dir:
            return
        runner = self._make_runner()
        self._run_operation("分解 payload.bin", runner.unpack_bin, project_dir)

    def _on_pack_bin(self) -> None:
        """打包 BIN（未实现）"""
        messagebox.showinfo("提示", "打包 payload.bin 功能暂未实现，请使用第三方工具")

    # ================================================================== #
    # 日志与进度
    # ================================================================== #
    def _make_runner(self) -> OperationRunner:
        """创建 OperationRunner 实例，绑定日志与进度回调"""
        return OperationRunner(
            env=self.env,
            logger=lambda msg: self.log_queue.put(msg),
            progress=lambda fraction, message: self.progress_queue.put((fraction, message)),
        )

    def _log(self, message: str) -> None:
        """追加日志到文本框"""
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _update_progress(self, fraction: float, message: str) -> None:
        """更新进度条与状态文本"""
        percent = fraction * 100
        self.progress_var.set(percent)
        self.progress_label.configure(text=message if message else f"进度：{percent:.1f}%")

    def _poll_queues(self) -> None:
        """定时轮询队列，更新 UI"""
        try:
            while True:
                msg = self.log_queue.get_nowait()
                self._log(msg)
        except queue.Empty:
            pass

        try:
            while True:
                fraction, message = self.progress_queue.get_nowait()
                self._update_progress(fraction, message)
        except queue.Empty:
            pass

        self.after(120, self._poll_queues)

    def _show_file_selection_dialog(
        self, title: str, items: List[str], action_name: str
    ) -> Optional[Any]:
        """
        显示文件/分区选择对话框
        返回：
        - None: 用户取消
        - "all": 选择全部
        - List[int]: 选中的索引列表
        """
        dialog = tk.Toplevel(self)
        dialog.title(title)
        dialog.geometry("500x450")
        dialog.transient(self)
        dialog.grab_set()
        
        result = {"value": None}
        
        # 标题
        ttk.Label(
            dialog,
            text=title,
            font=("微软雅黑", 12, "bold"),
            padding=16
        ).pack(fill=tk.X)
        
        # 说明
        ttk.Label(
            dialog,
            text=f"共 {len(items)} 个项目，请选择要{action_name}的内容：",
            font=("微软雅黑", 9),
            padding=(16, 0, 16, 8)
        ).pack(fill=tk.X)
        
        # 列表框
        list_frame = ttk.Frame(dialog, padding=16)
        list_frame.pack(fill=tk.BOTH, expand=True)
        
        listbox = tk.Listbox(
            list_frame,
            selectmode=tk.MULTIPLE,
            font=("微软雅黑", 10),
            activestyle="dotbox",
            relief=tk.FLAT,
            bg="#f8f9fa",
            selectbackground="#4a90e2",
            selectforeground="#ffffff",
        )
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=listbox.yview)
        listbox.configure(yscrollcommand=scrollbar.set)
        listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        for item in items:
            listbox.insert(tk.END, item)
        
        # 按钮区
        btn_frame = ttk.Frame(dialog, padding=(16, 0, 16, 16))
        btn_frame.pack(fill=tk.X)
        btn_frame.columnconfigure((0, 1, 2, 3), weight=1)
        
        def on_all():
            result["value"] = "all"
            dialog.destroy()
        
        def on_selected():
            selected = listbox.curselection()
            if not selected:
                messagebox.showwarning("提示", "请至少选择一个项目", parent=dialog)
                return
            result["value"] = list(selected)
            dialog.destroy()
        
        def on_cancel():
            result["value"] = None
            dialog.destroy()
        
        def on_select_all():
            listbox.select_set(0, tk.END)
        
        ttk.Button(btn_frame, text="全选", command=on_select_all).grid(row=0, column=0, padx=3, sticky="ew")
        ttk.Button(btn_frame, text="✓ 全部", style="Primary.TButton", command=on_all).grid(row=0, column=1, padx=3, sticky="ew")
        ttk.Button(btn_frame, text="✓ 已选", style="Primary.TButton", command=on_selected).grid(row=0, column=2, padx=3, sticky="ew")
        ttk.Button(btn_frame, text="✗ 取消", command=on_cancel).grid(row=0, column=3, padx=3, sticky="ew")
        
        # 居中显示
        dialog.update_idletasks()
        x = self.winfo_x() + (self.winfo_width() - dialog.winfo_width()) // 2
        y = self.winfo_y() + (self.winfo_height() - dialog.winfo_height()) // 2
        dialog.geometry(f"+{x}+{y}")
        
        dialog.wait_window()
        return result["value"]


def run_gui(env: Optional[ToolEnvironment] = None) -> None:
    """启动 GUI"""
    app = ZLOApp(env)
    app.mainloop()
