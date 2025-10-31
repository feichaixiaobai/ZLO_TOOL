# ZLO_TOOL

## 🧰 ANDROID_TOOL_LINUX

一个基于 Shell 的 **Android 镜像分解与打包工具**，支持多种镜像格式与文件系统类型。  
适合 ROM 定制、镜像分析、文件系统研究、自动化构建等场景。

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
```sss

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
