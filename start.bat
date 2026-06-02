@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

REM =============================================================================
REM sing-box 管理脚本 (Windows)
REM 功能：自动部署、启动 sing-box 核心，以及更新订阅链接
REM 兼容：Windows 10/11
REM =============================================================================

REM --- 切换到脚本所在目录 ---
cd /d "%~dp0"

REM --- 请求管理员权限 ---
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dpnx0' -Verb RunAs"
    exit /b
)

set CONFIG_FILE=config.json
set PLACEHOLDER=订阅链接
set TARGET_BINARY=sing-box.exe
set RUN_DIR=run
set LOG_FILE=run\sing-box.log
set DASHBOARD_DIR=dashboard
set MAX_LOGS=5
set API_BASE=http://127.0.0.1:9090

cls
echo ==================================
echo   sing-box 管理脚本 (Windows版)
echo ==================================

REM --- 前置检查：config.json ---
if not exist "%CONFIG_FILE%" (
    echo ❌ 错误：找不到配置文件 %CONFIG_FILE%！
    pause
    exit /b 1
)

REM --- 部署 sing-box 核心 ---
echo 📁 正在部署 sing-box 核心...
set "SOURCE_PATH=%~dp0bin\windows-amd64\sing-box.exe"
if exist "%SOURCE_PATH%" (
    echo 📦 检测到 bin 版本，正在复制...
    copy /y "%SOURCE_PATH%" "%TARGET_BINARY%"
    if %errorlevel% equ 0 (
        echo ✅ 已更新 sing-box 核心！
    ) else (
        echo ❌ 复制失败（错误码 %errorlevel%），但尝试使用现有文件...
    )
) else (
    echo ℹ️  未找到 bin\windows-amd64\sing-box.exe，跳过复制。
)

if not exist "%TARGET_BINARY%" (
    echo ❌ 错误：根目录下也没有 sing-box.exe！
    echo     请确保至少存在以下之一：
    echo       - %SOURCE_PATH%
    echo       - %~dp0%TARGET_BINARY%
    pause
    exit /b 1
) else (
    echo ✅ 检测到可用的 sing-box.exe，准备启动。
)

REM ===================== 主菜单 =====================
echo ==================================
echo 1. 启动 sing-box 核心
echo 2. 更新订阅链接
echo ==================================
set /p choice=请选择操作 (1 或 2):

if "!choice!"=="1" goto start
if "!choice!"=="2" goto update
echo ❌ 无效选择，请输入 1 或 2。
pause
exit /b 1

REM ===================== 启动 sing-box =====================
:start
echo 🚀 正在启动 Sing-box 核心...

findstr /c:"%PLACEHOLDER%" "%CONFIG_FILE%" >nul 2>nul
if %errorlevel% equ 0 (
    echo 🚨 警告：配置文件中检测到未替换的 '%PLACEHOLDER%'！
    echo    程序可能无法正常运行。
    set /p "confirm=确定要继续启动吗？(y/N): "
    if /i not "!confirm!"=="y" exit /b 0
)

REM --- 创建运行目录 ---
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"

REM --- 清理旧日志（只保留最近 MAX_LOGS 个） ---
powershell -NoProfile -Command ^
    "$d='%RUN_DIR%'; $m=%MAX_LOGS%; " ^
    "$f=Get-ChildItem $d -Filter *.log -ErrorAction SilentlyContinue; " ^
    "if($f.Count -gt $m){$f|^ Sort-Object LastWriteTime|^ Select-Object -First ($f.Count-$m)^| Remove-Item -Force}"

REM --- 启动 sing-box（前台运行，等待退出） ---
echo ⏳ Sing-box 已启动，正在等待 %DASHBOARD_DIR% 生成文件...
echo ℹ️  按 Ctrl+C 退出程序。

REM 设置退出清理标记
set "SINGBOX_STARTED=1"

.\sing-box.exe run -c "%CONFIG_FILE%" -D .\

REM sing-box 退出后清理
set "SINGBOX_STARTED=0"
echo ⚠️  Sing-box 进程已退出。
call :cleanup
pause
exit /b 0

REM ===================== 更新订阅链接 =====================
:update
echo 📝 更新订阅链接
echo 💡 提示：如果只输入一个链接，它将被复制到所有三个位置。

REM --- 备份（用 PowerShell 生成统一格式的日期时间） ---
for /f "usebackq delims=" %%d in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "BACKUP_TS=%%d"
copy "%CONFIG_FILE%" "%CONFIG_FILE%.backup_%BACKUP_TS%" >nul 2>nul
echo 📄 已备份原配置文件

REM --- 使用 PowerShell 安全更新（防注入） ---
echo ✅ 正在更新配置文件...
powershell -NoProfile -ExecutionPolicy Bypass -NoLogo -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$cfg = '%CONFIG_FILE%';" ^
    "$ph = '%PLACEHOLDER%';" ^
    "$u1 = Read-Host '请输入 订阅1 链接';" ^
    "$u2 = Read-Host '请输入 订阅2 链接 (可留空)';" ^
    "$u3 = Read-Host '请输入 订阅3 链接 (可留空)';" ^
    "if ([string]::IsNullOrWhiteSpace($u1)) { Write-Host '❌ 错误：你没有输入任何链接！'; exit 1 };" ^
    "if ([string]::IsNullOrWhiteSpace($u2)) { $u2 = $u1 };" ^
    "if ([string]::IsNullOrWhiteSpace($u3)) { $u3 = $u1 };" ^
    "$c = Get-Content $cfg -Raw -Encoding UTF8;" ^
    "$urls = @($u1,$u2,$u3);" ^
    "foreach($u in $urls){" ^
    "  $i = $c.IndexOf($ph);" ^
    "  if($i -lt 0){break};" ^
    "  $c = $c.Substring(0,$i) + $u + $c.Substring($i + $ph.Length)" ^
    "};" ^
    "Set-Content $cfg -Value $c -NoNewline -Encoding UTF8;" ^
    "Write-Host '';" ^
    "Write-Host '✅ 成功！配置文件已更新。';" ^
    "foreach($idx in 0..2){" ^
    "  $val = @($u1,$u2,$u3)[$idx];" ^
    "  if($val.Length -gt 20){$val=$val.Substring(0,20)+'...'};" ^
    "  Write-Host ('   订阅{0}: {1}' -f ($idx+1),$val)" ^
    "}"

if %errorlevel% neq 0 (
    echo ❌ 更新失败！请检查 PowerShell 是否可用。
    pause
    exit /b 1
)

pause
exit /b 0

REM ===================== 退出清理：终止 sing-box 进程 =====================
:cleanup
if "%SINGBOX_STARTED%"=="1" (
    echo 🛑 正在停止 sing-box...
    taskkill /im sing-box.exe /f >nul 2>&1
    echo ✅ sing-box 已停止。
)
exit /b 0
