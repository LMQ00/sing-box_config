自用 sing-box 配置

本配置适用于带 provider 功能 的 sing-box 内核，例如：
👉 [reF1nd](https://github.com/reF1nd/sing-box) [tg](https://t.me/sing_box_reF1nd)

---

🚀 使用方法

### 1. 准备内核

将 `bin/` 文件夹中对应系统的 sing-box 内核移动到项目根目录。

### 2. 配置订阅链接

使用管理脚本自动配置（推荐）：

```bash
# Linux / macOS
./start.sh

# Windows
start.bat
```

选择 **选项 2** 输入订阅链接即可自动完成配置。

也可手动编辑 `config.json`，搜索 `订阅链接`，替换为你的订阅链接（需全部替换，如没有三个订阅可重复添加）。

### 3. 启动服务

使用管理脚本启动（推荐）：

```bash
# Linux / macOS
./start.sh

# Windows
start.bat
```

选择 **选项 1** 即可启动。

手动启动：

```bash
# Linux / macOS
sudo ./sing-box run -D ./ -c ./config.json

# Windows（管理员权限）
.\sing-box.exe run -D ./ -c ./config.json
```

---

📋 管理脚本功能

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 启动 sing-box | 启动代理服务，Ctrl+C 退出 |
| 2 | 更新订阅链接 | 输入新的订阅链接，自动备份并更新配置 |
| 3 | 自动修复 | 清除 `cache.db` 和 `run/` 缓存文件 |
| 4 | 重置配置 | 从最近的备份文件恢复 `config.json` |

---

🌐 访问面板

启动完成后，在浏览器中打开：
🔗 http://127.0.0.1:9090/ui/

---

⌨️ 无 UI 设备（如 TTY 环境）

可在同一局域网内的其他设备浏览器中访问：

```
http://<无UI设备的IP>:9090/ui/
```

---

🤖 Android 使用说明（Magisk 模块）

推荐模块

✅ [CHIZI-0618/box4magisk](https://github.com/CHIZI-0618/box4magisk)

配置要点：

· 代理模式选择 "core"（某些模块称为"核心模式"）
· tun_device 项填写 "tun0"（否则可能无法分享热点）
