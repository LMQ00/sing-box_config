自用 sing-box 配置

本配置适用于带 provider 功能 的 sing-box 内核，例如：
👉 [reF1nd](https://github.com/reF1nd/sing-box)

---

🚀 使用方法

1. 准备内核

将 bin/ 文件夹中对应系统的 sing-box 内核 移动到项目根目录。

2. 配置订阅链接

打开 config.json 文件，搜索 "订阅链接"，将其替换为你的订阅链接(需全部替换，如没有三个订阅可以重复添加)。

---

3. 启动服务

Macos/Linux

```bash
chmod +x ./sing-box
sudo ./sing-box run -D ./ -c ./config.json
```

Windows

1. 右键 sing-box.exe → 属性 → 兼容性 → ✅ 以管理员身份运行
2. 在项目根目录打开 CMD 或 PowerShell：

```bash
./sing-box.exe run -D ./ -c ./config.json
```

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

也可使用start.sh辅助运行，start.sh脚本启动后可自动连接到国外代理

---

🤖 Android 使用说明（Magisk 模块）

推荐模块

✅ [CHIZI-0618/box4magisk](https://github.com/CHIZI-0618/box4magisk)

配置要点：

· 代理模式选择 "core"（某些模块称为“核心模式”）
· tun_device 项填写 "tun0"（否则可能无法分享热点）

---
