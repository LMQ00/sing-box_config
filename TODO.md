# 待优化项

## 1. start.sh — 临时文件 Ctrl+C 中断清理

当前 `trap cleanup` 只处理 sing-box 进程，不清理下载临时目录。

**修改文件：** `start.sh`

**修改位置：** cleanup 函数和 download_latest_version 函数

**修改内容：**

```bash
# 在全局变量区域添加
TEMP_DIRS=()

# 修改 cleanup 函数
cleanup() {
    echo ""
    echo "🛑 正在停止 sing-box..."
    if [[ -n "${SING_BOX_PID:-}" ]]; then
        sudo kill "$SING_BOX_PID" 2>/dev/null
        wait "$SING_BOX_PID" 2>/dev/null
    fi
    # 清理临时目录
    for d in "${TEMP_DIRS[@]}"; do
        [[ -d "$d" ]] && rm -rf "$d"
    done
    echo "✅ sing-box 已停止。"
}

# 修改 download_with_retry 函数，在创建 temp_dir 后添加
TEMP_DIRS+=("$temp_dir")
```

---

## 2. start.sh — 下载后校验文件完整性

当前只检查文件大小 > 1000 字节，未验证是否为有效 tar.gz。

**修改文件：** `start.sh`

**修改位置：** download_with_retry 函数

**修改内容：**

```bash
download_with_retry() {
    local url="$1"
    local output="$2"
    local desc="$3"

    echo "📥 正在下载: $desc"
    if curl -L --connect-timeout 15 --max-time 120 -o "$output" "$url" 2>/dev/null; then
        if [[ -f "$output" ]] && [[ $(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null) -gt 1000 ]]; then
            # 验证是否为有效的 gzip 文件
            if file "$output" | grep -q "gzip"; then
                return 0
            fi
            echo "⚠️  下载的文件格式异常，重试..."
            rm -f "$output"
        fi
    fi
    return 1
}
```

---

## 3. start.bat — 后台运行模式

当前 sing-box 前台运行，退出后才 pause。建议改为后台运行。

**修改文件：** `start.bat`

**修改位置：** `:run_singbox` 段

**修改内容：**

```bat
:run_singbox
if not exist "run" mkdir "run"

echo.
echo ==================================
echo   ✅ sing-box 已成功启动！
echo ==================================
echo   📊 管理面板: http://127.0.0.1:9090/ui/
echo   📡 API 地址: http://127.0.0.1:9090
echo ==================================
echo.

REM 后台启动 sing-box
start "" /B .\sing-box.exe run -c "%CONFIG_FILE%" -D .\ > "run\sing-box.log" 2>&1
echo ⏳ Sing-box 已在后台启动。
echo 📋 日志文件: run\sing-box.log
echo ℹ️  按任意键查看日志，按 Ctrl+C 退出。

:watch_log
REM 按任意键打开日志
pause >nul
if exist "run\sing-box.log" (
    type "run\sing-box.log"
)
goto watch_log
```

---

## 4. start.bat — 日志轮转

当前无日志管理，run 目录会积累大量日志文件。

**修改文件：** `start.bat`

**修改位置：** `:run_singbox` 段，启动前清理

**修改内容：**

```bat
REM 清理旧日志，只保留最近 5 个
set COUNT=0
for /f %%f in ('dir /b /o-n "run\*.log" 2^>nul') do (
    set /a COUNT+=1
    if !COUNT! GTR 5 del /f /q "run\%%f"
)
```

> 注意：需要在脚本开头添加 `setlocal enabledelayedexpansion` 才能使用 `!COUNT!`

---

## 5. start.bat — GitHub API 限流处理

未认证请求限制 60 次/小时，超限后解析会静默失败。

**修改文件：** `start.bat`

**修改位置：** 获取版本号后

**修改内容：**

```bat
echo %TAG% | findstr /r "^v[0-9]" >nul
if %errorlevel% neq 0 (
    echo ❌ 错误：无法获取版本号，可能是网络问题或 API 限流。
    echo    请稍后重试或手动下载: https://github.com/LMQ00/sing-box/releases
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)
```

---

## 6. .gitignore — 添加 bin/ 目录

旧版本用户升级后可能残留 bin/ 目录。

**修改文件：** `.gitignore`

**修改内容：**

```gitignore
# 添加到文件开头
# 旧版本残留
bin/
```

---

## 7. README — rules/ 目录补充 .srs 文件

当前 README 缺少 .srs 规则集文件说明。

**修改文件：** `README.md`

**修改位置：** 目录结构部分

**修改内容：**

```markdown
├── rules/              # 规则文件
│   ├── pcdn.json
│   ├── pcdn.srs
│   ├── private_DNS.json
│   ├── private_DNS.srs
│   ├── tg_bad.json
│   └── tg_bad.srs
```

---

## 优先级

| 优先级 | 项目 | 原因 |
|:------:|------|------|
| P1 | #1 临时文件清理 | Ctrl+C 后残留临时目录 |
| P1 | #5 API 限流处理 | 国内用户高频使用易触发 |
| P2 | #2 文件校验 | 下载损坏文件导致启动失败 |
| P2 | #6 .gitignore bin/ | 旧版本用户升级体验 |
| P3 | #3 后台运行 | Windows 用户体验优化 |
| P3 | #4 日志轮转 | 长期运行磁盘占用 |
| P3 | #7 README 补充 | 文档完整性 |
