自用 sing-box 配置

适用于有 provider 的内核，如：
https://github.com/reF1nd/sing-box

使用方法

先将bin文件夹里的sing-box内核移动到文件夹根目录，然后去config.json中搜索 "机场链接"，填入订阅链接替换。

执行以下命令：

```bash
chmod +x ./sing-box
sudo ./sing-box run -D ./ -c ./config.json
```

说明

启动完后浏览器打开  http://127.0.0.1:9090/ui/ 启动面板
