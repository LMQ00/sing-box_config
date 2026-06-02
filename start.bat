@echo off
chcp 65001 > nul
setlocal

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
    copy /y "%SOURCE_PATH%" "%TARGET_BINARY%" > nul
    if %errorlevel% equ 0 (
        echo ✅ 已更新 sing-box 核心！
    ) else (
        echo ❌ 复制失败，但尝试使用现有文件...
    )
) else (
    echo ℹ️  未找到 bin\windows-amd64\sing-box.exe，跳过复制。
)

if not exist "%TARGET_BINARY%" (
    echo ❌ 错误：根目录下也没有 sing-box.exe！
    echo     请确保至少存在以下之一：
    echo       - bin\windows-amd64\sing-box.exe
    echo       - %TARGET_BINARY%
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

if "%choice%"=="1" goto start
if "%choice%"=="2" goto update
echo ❌ 无效选择，请输入 1 或 2。
pause
exit /b 1

REM ===================== 启动 sing-box =====================
:start
echo 🚀 正在启动 Sing-box 核心...

findstr /c:"%PLACEHOLDER%" "%CONFIG_FILE%" >nul 2>nul
if %errorlevel% neq 0 goto run_singbox

echo 🚨 警告：配置文件中检测到未替换的 '%PLACEHOLDER%'！
echo    程序可能无法正常运行。
set /p confirm=确定要继续启动吗？(y/N):
if /i not "%confirm%"=="y" exit /b 0

:run_singbox
if not exist "run" mkdir "run"

echo ⏳ Sing-box 已启动。
echo ℹ️  按 Ctrl+C 退出程序。

.\sing-box.exe run -c "%CONFIG_FILE%" -D .\
pause
exit /b 0

REM ===================== 更新订阅链接 =====================
:update
echo 📝 更新订阅链接
echo 💡 提示：如果只输入一个链接，它将被复制到所有三个位置。

REM --- 备份（统一格式时间戳） ---
for /f "delims=" %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "BACKUP_TS=%%d"
copy "%CONFIG_FILE%" "%CONFIG_FILE%.backup_%BACKUP_TS%" >nul 2>nul
echo 📄 已备份原配置文件

REM --- 使用 PowerShell 安全更新（Read-Host 防注入） ---
powershell -NoProfile -ExecutionPolicy Bypass -NoLogo -Command ^
    "$ph='%PLACEHOLDER%'; $cfg='%CONFIG_FILE%';" ^
    "$u1=Read-Host '请输入 订阅1 链接';" ^
    "if([string]::IsNullOrWhiteSpace($u1)){Write-Host '❌ 错误：你没有输入任何链接！'; exit 1};" ^
    "$u2=Read-Host '请输入 订阅2 链接 (可留空)';" ^
    "$u3=Read-Host '请输入 订阅3 链接 (可留空)';" ^
    "if([string]::IsNullOrWhiteSpace($u2)){$u2=$u1};" ^
    "if([string]::IsNullOrWhiteSpace($u3)){$u3=$u1};" ^
    "$c=Get-Content $cfg -Raw -Encoding UTF8;" ^
    "foreach($u in @($u1,$u2,$u3)){" ^
    "  $i=$c.IndexOf($ph); if($i-lt 0){break};" ^
    "  $c=$c.Substring(0,$i)+$u+$c.Substring($i+$ph.Length)" ^
    "};" ^
    "[IO.File]::WriteAllText($cfg, $c, (New-Object System.Text.UTF8Encoding $false));" ^
    "Write-Host '';" ^
    "Write-Host '✅ 成功！配置文件已更新。';" ^
    "foreach($i in 0..2){" ^
    "  $v=@($u1,$u2,$u3)[$i];" ^
    "  if($v.Length-gt 20){$v=$v.Substring(0,20)+'...'};" ^
    "  Write-Host ('   订阅{0}: {1}' -f ($i+1),$v)" ^
    "}"

if %errorlevel% neq 0 (
    echo ❌ 更新失败！请检查 PowerShell 是否可用。
    pause
    exit /b 1
)

pause
exit /b 0
