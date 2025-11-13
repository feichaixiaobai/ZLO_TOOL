
# 🧰 ANDROID_TOOL_LINUX

一个基于 Shell 的 **Android 镜像分解与打包工具**，支持多种镜像格式与文件系统类型。  
适合 ROM 定制、镜像分析、文件系统研究、自动化构建等场景。
=======
# 🧰 ZLO Android 镜像工具

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)
![Python](https://img.shields.io/badge/python-3.9%2B-green.svg)
![License](https://img.shields.io/badge/license-MIT-orange.svg)

**跨平台 Android 镜像分解与打包工具集**

支持 IMG / SUPER / DAT / BR / BIN 等多种格式 | 现代化图形界面 | 命令行工具 | 自动化脚本

[功能特性](#-功能特性) • [安装](#-安装) • [使用指南](#-使用指南) • [常见问题](#-常见问题) • [贡献](#-贡献)

</div>

---

## 📖 简介

ZLO Tool 是一个功能强大的跨平台 Android 镜像处理工具，专为 ROM 开发者、安全研究人员和高级用户设计。提供直观的图形界面和灵活的命令行接口，支持多种 Android 镜像格式的分解、修改和打包。

### ✨ 核心亮点

- 🎨 **现代化 GUI**：清爽的卡片式界面，实时进度条，深色日志面板
- 🖥️ **跨平台支持**：原生支持 Windows 和 Linux，无需虚拟机
- 🚀 **智能检测**：自动识别文件系统类型（EXT4/EROFS/F2FS/SquashFS）
- 📦 **项目管理**：独立工作空间，支持多项目并行处理
- ⚡ **批量操作**：可选择全部或部分镜像进行操作
- 🔧 **扩展机制**：支持自定义 Python/Shell 脚本
>>>>>>> 199941f (fix bug)

---

## 🚀 功能特性


✅ 分解与打包以下镜像类型：
- `img` / `super.img`
- `br` / `bat` / `bin`

✅ 自动检测与转换稀疏镜像（`simg2img`）  
✅ 支持多种文件系统：
- `ext4`
- `EROFS`
- `SquashFS`
- `F2FS`

✅ 智能输出路径：
- `super.img` → 分区镜像输出在项目目录下  
- 普通 `img` → 内容解包到 `zlo_out/<分区名>/`

✅ 外部扩展机制：
- 在 `tool/` 目录中添加自定义脚本（`pack_*.sh`、`unpack_*.sh`）

---

## ⚙️ 一键安装依赖

在 **Ubuntu / Debian** 系统中执行：

```bash
grep -v '^#' requirements.txt | grep -v '^$' | xargs sudo apt-get install -y
```

在 **Fedora** 系统中执行：

```bash
grep -v '^#' requirements.txt | grep -v '^$' | xargs sudo dnf install -y
```

在 **Arch Linux** 系统中执行：

```bash
grep -v '^#' requirements.txt | grep -v '^$' | xargs sudo pacman -S --noconfirm
```

## 🔧 启动与使用

1️⃣ 给脚本授权：

```bash
chmod +x run.sh
chmod +x tool/*.sh
chmod +x bin/*
```

2️⃣ 启动主程序：

```bash
./run.sh
```
=======
### 支持的镜像格式

| 格式 | 分解 | 打包 | 说明 |
|:---:|:---:|:---:|:---|
| **IMG** | ✅ | ✅ | 普通分区镜像，自动检测稀疏镜像 |
| **SUPER** | ✅ | ✅ | 动态分区镜像，支持多分区管理 |
| **DAT** | ✅ | ✅ | system.new.dat 格式（OTA 包） |
| **BR** | ✅ | ✅ | Brotli 压缩文件 |
| **BIN** | ✅ | ⚠️ | payload.bin（分解支持，打包开发中） |
| **BAT** | - | ✅ | 批处理文件合并工具 |

### 支持的文件系统

- **EXT4** - Android 最常用的文件系统
- **EROFS** - 增强型只读文件系统
- **F2FS** - Flash-Friendly 文件系统
- **SquashFS** - 只读压缩文件系统

### 操作模式

#### 🖥️ 图形界面模式
- 项目管理（创建/删除/切换）
- 可视化文件选择对话框
- 实时操作日志输出
- 进度条显示（0-100%）
- 友好的错误提示

#### 💻 命令行模式
- 适合自动化脚本
- 支持批量处理
- CI/CD 集成友好
- 详细的日志输出

#### 🔧 Shell 脚本模式（Linux）
- 传统交互式菜单
- 完整的 POSIX 兼容性
- 适合服务器环境

---

## 📦 安装

### 系统要求

- **操作系统**：Windows 10/11 或 Linux（Ubuntu 20.04+）
- **Python**：3.9 或更高版本
- **磁盘空间**：至少 5GB 可用空间（用于临时文件）
- **内存**：建议 4GB 以上

### Windows 安装

```powershell
# 1. 安装 Python（如未安装）
# 访问 https://www.python.org/downloads/ 下载安装

# 2. 克隆或下载项目
git clone https://github.com/yourusername/zlo_tool.git
cd zlo_tool

# 3. 验证二进制文件
# bin/windows_x86/ 已包含大部分工具

# 4. 启动图形界面
python main.py gui
```

### Linux 安装

```bash
# 1. 安装系统依赖
sudo apt-get update
sudo apt-get install -y python3 python3-pip

# 2. 安装 Android 工具（推荐）
sudo apt-get install -y android-sdk-libsparse-utils \
    android-sdk-ext4-utils e2fsprogs p7zip-full brotli

# 3. 克隆项目
git clone https://github.com/yourusername/zlo_tool.git
cd zlo_tool

# 4. 授权脚本
chmod +x run.sh tool/*.sh bin/Linux/*

# 5. 启动（GUI 或 Shell）
python3 main.py gui
# 或
./run.sh
```

### 可选依赖

**7-Zip**（Windows）:
```powershell
# 使用 Scoop 安装
scoop install 7zip

# 或从官网下载
# https://www.7-zip.org/
```

**WSL**（Windows 打包镜像）:
```powershell
# 启用 WSL 以使用完整的 Linux 工具
wsl --install
```

---

## 📘 使用指南

### 快速开始

#### 方式一：图形界面（推荐）

```bash
# 启动 GUI
python main.py gui

# 操作流程：
# 1. 点击「➕ 新建」创建项目
# 2. 将镜像文件（.img）复制到项目目录
# 3. 选择项目，点击「📤 分解 IMG」
# 4. 在弹出的对话框中选择要分解的镜像
# 5. 查看实时日志和进度条
# 6. 完成后在 zlo_out/ 目录查看结果
```

#### 方式二：命令行

```bash
# 创建项目
python main.py create my_rom

# 将镜像文件放入项目目录
cp system.img vendor.img my_rom/

# 分解镜像
python main.py unpack-img my_rom

# 修改文件
# 编辑 my_rom/zlo_out/system/ 下的文件

# 打包镜像
python main.py pack-img my_rom

# 打包为稀疏镜像
python main.py pack-img my_rom --sparse
```

#### 方式三：Shell 脚本（Linux）

```bash
./run.sh

# 按提示操作：
# 1. 创建项目
# 2. 选择项目
# 3. 选择操作（11=分解IMG, 22=打包IMG）
```

### 详细操作指南

#### 🔽 分解操作

**分解普通 IMG 镜像**
```bash
# CLI
python main.py unpack-img <项目名>

# GUI
选择项目 → 点击「📤 分解 IMG」→ 选择镜像 → 开始
```

**分解 super 动态分区**
```bash
# CLI
python main.py unpack-super <项目名>

# GUI
选择项目 → 点击「📤 分解 SUPER」→ 自动处理
```

**分解 DAT 文件**
```bash
# CLI
python main.py unpack-dat <项目名>

# GUI
选择项目 → 点击「📤 分解 DAT」→ 开始
```

**解压 Brotli 文件**
```bash
# CLI
python main.py unpack-br <项目名>

# GUI
选择项目 → 点击「📤 解压 BR」→ 开始
```

**分解 payload.bin**
```bash
# CLI
python main.py unpack-bin <项目名>

# GUI
选择项目 → 点击「📤 分解 BIN」→ 开始
```

#### 🔼 打包操作

**打包 IMG 镜像**
```bash
# 打包为 RAW 镜像
python main.py pack-img <项目名>

# 打包为稀疏镜像
python main.py pack-img <项目名> --sparse

# GUI 操作
选择项目 → 点击「📥 打包 IMG」→ 选择分区 → 选择格式
```

**打包 super 镜像**
```bash
# CLI
python main.py pack-super <项目名>

# GUI
选择项目 → 点击「📥 打包 SUPER」→ 选择要包含的分区
```

**打包 DAT 文件**
```bash
# CLI
python main.py pack-dat <项目名>

# GUI
选择项目 → 点击「📥 打包 DAT」→ 开始
```

**压缩为 Brotli**
```bash
# CLI（自定义压缩等级）
python main.py pack-br <项目名> --quality 9

# GUI
选择项目 → 点击「📥 压缩 BR」→ 输入压缩等级（0-11）
```

---

## 📂 目录结构

```
ZLO_TOOL/
├── main.py                 # 主入口（GUI + CLI）
├── run.sh                  # Shell 脚本入口（Linux）
├── requirements.txt        # 系统依赖清单
├── README.md              # 本文档
│
├── bin/                   # 二进制工具
│   ├── windows_x86/       # Windows 工具
│   │   ├── simg2img.exe
│   │   ├── lpunpack.exe
│   │   ├── brotli.exe
│   │   └── ...
│   └── Linux/             # Linux 工具
│       ├── simg2img
│       ├── lpunpack
│       └── ...
│
├── tool/                  # Shell 扩展脚本
│   ├── unpack_img_fs.sh   # 自定义文件系统解包
│   ├── pack_img.sh        # IMG 打包脚本
│   ├── pack_super.sh      # SUPER 打包脚本
│   └── ...
│
├── zlo_tool/              # Python 核心模块
│   ├── __init__.py        # 版本信息
│   ├── env.py             # 环境检测与配置
│   ├── projects.py        # 项目管理
│   ├── ops.py             # 操作调度（800+ 行）
│   └── gui.py             # 图形界面（600+ 行）
│
└── <项目名>/              # 用户创建的项目
    ├── *.img              # 原始镜像文件
    ├── zlo_out/           # 分解输出目录
    │   ├── system/        # 分区内容
    │   └── vendor/
    ├── zlo_pack/          # 打包输出目录
    │   ├── system.img
    │   └── vendor.img
    └── zlo_super/         # SUPER 镜像输出
        └── super.img
```

---

## 🎨 界面预览

### 图形界面

```
┌────────────────────────────────────────────────────────────────────┐
│  🧰 ZLO 镜像工具箱                                                   │
│  支持 IMG / SUPER / DAT / BR / BIN 等多种格式的分解与打包             │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  📁 项目管理              │  ⚙️ 镜像操作                            │
│  ┌──────────────────┐    │  ┌──────────┬──────────┬──────────┐   │
│  │  ☑ ROM_Xiaomi_13 │    │  │ 📤分解IMG │ 📥打包IMG │ 📤分解SUPER│  │
│  │  ☐ ROM_OnePlus_11│    │  │ 📥打包SUPER│ 📤分解DAT │ 📥打包DAT │  │
│  │  ☐ ROM_Samsung_S23│   │  │ 📤解压BR  │ 📥压缩BR  │ 📤分解BIN │  │
│  └──────────────────┘    │  └──────────┴──────────┴──────────┘   │
│  [➕新建] [🔄刷新]        │                                         │
│  [🗑️删除]                │  📊 执行进度                            │
│                           │  ██████████░░░░ 75%                    │
│                           │  正在分解：system.img                  │
│                           │                                         │
│                           │  📜 操作日志                            │
│                           │  ┌─────────────────────────────────┐  │
│                           │  │ [1/4] 开始分解：system.img      │  │
│                           │  │   检测到文件系统类型：ext4       │  │
│                           │  │   镜像大小：2048 MB             │  │
│                           │  │   使用 7-Zip 解包...            │  │
│                           │  │ ✅ 完成：zlo_out/system/         │  │
│                           │  └─────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

### 文件选择对话框

```
┌─────────────────────────────────────────┐
│  选择要分解的镜像                        │
├─────────────────────────────────────────┤
│  共 8 个项目，请选择要分解镜像的内容：   │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ ☑ system.img         (2048 MB)    │ │
│  │ ☑ vendor.img         (512 MB)     │ │
│  │ ☑ product.img        (1024 MB)    │ │
│  │ ☐ system_ext.img     (256 MB)     │ │
│  │ ☐ odm.img            (128 MB)     │ │
│  │ ☐ mi_ext_a.img       (64 MB)      │ │
│  │ ☐ mi_ext_b.img       (0 MB - 空)  │ │
│  │ ☐ vendor_dlkm.img    (32 MB)      │ │
│  └────────────────────────────────────┘ │
│                                          │
│  [ 全选 ] [ ✓ 全部 ] [ ✓ 已选 ] [ ✗ 取消 ]│
└─────────────────────────────────────────┘
```

---

## ❓ 常见问题

### Q1: Windows 下无法打包 IMG，提示缺少依赖？

**A:** Windows 版本的 `e2fsdroid.exe` 可能缺少 DLL。解决方案：

1. **使用 WSL**（推荐）:
   ```powershell
   wsl --install
   wsl
   sudo apt-get install android-sdk-libsparse-utils e2fsprogs
   ```

2. **下载完整工具包**:
   - 访问：https://github.com/osm0sis/android-image-tools
   - 下载 Windows 版本，包含所有 DLL
   - 将文件复制到 `bin/windows_x86/`

### Q2: 分解 EROFS 镜像失败？

**A:** 确保已安装 `extract.erofs` 工具：

```bash
# Linux
sudo apt-get install erofs-utils

# Windows
# 已包含在 bin/windows_x86/extract.erofs.exe
# 如失败，尝试更新到最新版本
```

### Q3: 如何修改分解后的文件？

**A:** 分解后的文件位于 `<项目名>/zlo_out/<分区名>/`，可以：

1. 直接编辑文本文件
2. 替换 APK/SO 文件
3. 添加/删除文件
4. 修改权限（需要 `root`）

修改完成后，使用打包功能重新生成镜像。

### Q4: 打包后的镜像能直接刷入手机吗？

**A:** 取决于镜像类型：

- **IMG 镜像**：通常可以通过 Fastboot 刷入
- **SUPER 镜像**：需要与设备分区布局匹配
- **建议**：在刷入前先备份原始镜像

### Q5: 支持哪些压缩格式？

**A:** 目前支持：

- **Brotli** (.br) - OTA 包常用
- **Gzip** (.gz) - 自动解压
- **稀疏镜像** - 自动检测与转换

### Q6: 如何添加自定义文件系统支持？

**A:** 在 `tool/` 目录创建脚本：

**Python 脚本**（`tool/unpack_img_fs.py`）:
```python
#!/usr/bin/env python3
import sys
from pathlib import Path

raw_img = Path(sys.argv[1])
out_dir = Path(sys.argv[2])

# 你的解包逻辑
# ...
```

**Shell 脚本**（`tool/unpack_img_fs.sh`）:
```bash
#!/bin/bash
RAW_IMG="$1"
OUT_DIR="$2"

# 你的解包逻辑
# ...
```

工具会自动检测并优先使用自定义脚本。

### Q7: 为什么某些镜像分解后是空的？

**A:** 可能原因：

1. **镜像大小为 0**：检查原始文件
2. **不支持的文件系统**：查看日志中的检测结果
3. **加密镜像**：需要先解密
4. **损坏的镜像**：尝试修复或重新提取

### Q8: 命令行模式如何查看帮助？

**A:** 
```bash
# 查看所有命令
python main.py -h

# 查看特定命令帮助
python main.py unpack-img -h
python main.py pack-super -h
```

---

## 🛠️ 高级功能

### 自动化脚本示例

**批量处理多个 ROM**:
```python
#!/usr/bin/env python3
from pathlib import Path
from zlo_tool.env import default_environment
from zlo_tool.ops import OperationRunner
from zlo_tool.projects import ProjectManager

env = default_environment()
pm = ProjectManager(env)
runner = OperationRunner(env, logger=print)

# 创建项目并分解
for rom in ['ROM_A', 'ROM_B', 'ROM_C']:
    pm.create_project(rom)
    project_dir = env.root / rom
    
    # 复制镜像文件（假设已准备好）
    # ...
    
    # 自动分解
    runner.unpack_img(project_dir)
    runner.unpack_super(project_dir)
    
    print(f"✅ {rom} 处理完成")
```

### 性能优化建议

1. **使用 SSD**：临时文件操作频繁
2. **充足内存**：大镜像需要更多 RAM
3. **并行处理**：手动管理多个项目
4. **定期清理**：删除不需要的 `zlo_out` 和 `zlo_pack`

### 扩展二进制工具

在 `bin/` 目录添加新工具：

```
bin/
├── windows_x86/
│   └── your_tool.exe
└── Linux/
    └── your_tool
```

工具会自动检测并添加到 PATH。

---

## 🤝 贡献

欢迎贡献代码、报告 Bug 或提出建议！

### 如何贡献

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 报告 Bug

请包含以下信息：

- 操作系统版本
- Python 版本
- 完整的错误信息
- 复现步骤

### 功能请求

欢迎提出新功能建议！请在 Issues 中详细描述：

- 使用场景
- 期望行为
- 可选的实现方案

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

```
MIT License

Copyright (c) 2025 ZLO Tool Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 致谢

感谢以下开源项目和工具：

- [Android SDK Tools](https://developer.android.com/studio/command-line) - simg2img, lpunpack 等工具
- [7-Zip](https://www.7-zip.org/) - 文件系统解压
- [Brotli](https://github.com/google/brotli) - 压缩算法
- [EROFS Utils](https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git/) - EROFS 文件系统工具
- [Python Tkinter](https://docs.python.org/3/library/tkinter.html) - GUI 框架

特别感谢所有贡献者和用户的支持！

---

## 📊 项目统计

- **代码行数**: ~3000+ 行
- **支持格式**: 6 种主要格式
- **二进制工具**: 40+ 个跨平台工具
- **测试覆盖**: 核心功能全覆盖

---

## 🗺️ 路线图

### v1.1.0（计划中）

- [ ] 支持打包 payload.bin
- [ ] 增加镜像对比功能
- [ ] 添加签名验证
- [ ] 支持增量 OTA 生成

### v1.2.0（计划中）

- [ ] Web 界面支持
- [ ] 插件系统
- [ ] 云端备份集成
- [ ] 自动化测试框架

### 长期计划

- [ ] 支持更多文件系统（XFS, Btrfs）
- [ ] AI 辅助分析
- [ ] 多语言界面
- [ ] Docker 容器化

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star！**

Made with ❤️ by ZLO Tool Team

[⬆ 回到顶部](#-zlo-android-镜像工具)

</div>

