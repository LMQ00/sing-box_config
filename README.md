# sing-box 代理配置

自用 sing-box 配置，支持 provider 订阅、Clash API 面板、多平台一键管理。

> 适用于带 provider 功能的 sing-box 内核，例如 [reF1nd/sing-box](https://github.com/reF1nd/sing-box) · [Telegram](https://t.me/sing_box_reF1nd)

---

## 目录

- [快速开始](#快速开始)
- [管理脚本](#管理脚本)
- [目录结构](#目录结构)
- [手动使用](#手动使用)
- [面板访问](#面板访问)
- [Android](#android-使用说明)
- [故障排除](#故障排除)

---

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/LMQ00/sing-box_config.git
cd sing-box_config
```

### 2. 获取内核

运行管理脚本会自动检测您的系统架构，并从 GitHub 下载最新版本的 sing-box 内核。首次运行时会自动下载，无需手动操作。

> 如需更新内核：直接运行脚本并选择 **选项 5（Update Core）**；或删除根目录下的 `sing-box` (Linux/macOS) / `sing-box.exe` (Windows) 文件后重新运行脚本。

**内核信息：**

| 项目 | 地址 |
|------|------|
| 源码仓库 | https://github.com/reF1nd/sing-box |
| 下载地址 | https://github.com/LMQ00/sing-box/releases |
| 基于版本 | [reF1nd/sing-box](https://github.com/reF1nd/sing-box) · [Telegram](https://t.me/sing_box_reF1nd) |

### 3. 配置订阅

运行管理脚本，选择 **选项 2**，输入你的订阅链接：

```bash
# Linux / macOS
./start.sh

# Windows
start.bat
```

支持最多 3 条订阅链接，留空的会自动复用第一条。

### 4. 启动服务

再次运行管理脚本，选择 **选项 1** 即可启动。

---

## 管理脚本

提供 `start.sh`（Linux/macOS）和 `start.bat`（Windows）两个脚本，核心功能一致：

| 选项 | 功能 | 说明 |
|:---:|------|------|
| **1** | 启动服务 | 启动 sing-box 代理，Ctrl+C 退出 |
| **2** | 更新订阅 | 输入订阅链接，自动备份当前配置后更新 |
| **3** | 自动修复 | 清除 `cache.db` 缓存文件和 `run/` 运行目录 |
| **4** | 重置配置 | 从最近一次备份恢复 `config.json` |
| **5** | 更新内核 | 备份当前 sing-box 内核后从 GitHub 下载最新版 |

> `start.sh` 额外支持：后台守护运行、日志轮转、Dashboard 就绪检测及自动节点切换。

> 更新订阅时会自动备份当前配置为 `config.json.backup_YYYYMMDD_HHMMSS`，可通过选项 4 随时恢复。

---

## 目录结构

```
singbox/
├── start.sh            # 管理脚本 (Linux/macOS)
├── start.bat           # 管理脚本 (Windows)
├── config.json         # 主配置文件
├── cache.db            # 运行时缓存（自动生成）
├── sing-box            # 内核文件（自动下载）
├── rules/              # 规则文件
│   ├── pcdn.json
│   ├── pcdn.srs
│   ├── private_DNS.json
│   ├── private_DNS.srs
│   ├── tg_bad.json
│   └── tg_bad.srs
└── run/                # 运行时目录（日志等，自动生成）
```

---

## 手动使用

如果不想使用管理脚本，也可以手动启动：

```bash
# Linux / macOS
chmod +x ./sing-box
sudo ./sing-box run -D ./ -c ./config.json

# Windows (管理员 PowerShell)
.\sing-box.exe run -D ./ -c ./config.json
```

---

## 面板访问

启动后可通过 Clash API 面板管理节点：

- 本机：http://127.0.0.1:9090/ui/
- 局域网：http://<设备IP>:9090/ui/

---

## Android 使用说明

### 推荐模块

[CHIZI-0618/box4magisk](https://github.com/CHIZI-0618/box4magisk)

### 配置要点

- 代理模式选择 **core**（核心模式）
- `tun_device` 填写 **tun0**（否则可能无法分享热点）

---

## 故障排除

**启动报错 `invalid character 'ï'`**

配置文件被写入了 UTF-8 BOM。用记事本打开 `config.json`，另存为时选择 **UTF-8（无 BOM）** 格式。

**按选项 1 直接退出**

通常是配置文件中仍包含 `订阅链接` 占位符。选择选项 2 输入真实订阅链接后再启动。

**无法启动 / 连接失败**

选择选项 3 清除缓存后重试。若仍不行，选择选项 4 重置配置。
