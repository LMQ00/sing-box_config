@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dpnx0' -Verb RunAs"
    exit /b
)

set CONFIG_FILE=config.json
set PLACEHOLDER=订阅链接
set TARGET_BINARY=sing-box.exe
set SOURCE_PATH=./bin/windows-amd64/sing-box.exe

cls
echo ==================================
echo   sing-box 管理脚本 (Windows版)
echo ==================================

echo 📁 正在部署 sing-box 核心...
if exist "%SOURCE_PATH%" (
    echo 📦 检测到 bin 版本，正在复制...
    copy /y "%SOURCE_PATH%" "%TARGET_BINARY%" > nul
    if %errorlevel% equ 0 (
        echo ✅ 已更新 sing-box 核心！
    ) else (
        echo ❌ 复制失败，但尝试使用现有文件...
    )
) else (
    echo ℹ️  未找到 ./bin/windows-amd64/sing-box.exe，跳过复制。
)

if not exist "%TARGET_BINARY%" (
    echo ❌ 错误：根目录下也没有 sing-box.exe！
    echo     请确保至少存在以下之一：
    echo       - ./bin/windows-amd64/sing-box.exe
    echo       - ./sing-box.exe
    pause
    exit /b 1
) else (
    echo ✅ 检测到可用的 sing-box.exe，准备启动。
)


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

:start
echo 🚀 正在启动 Sing-box 核心...

findstr /c:"%PLACEHOLDER%" "%CONFIG_FILE%" >nul
if %errorlevel% equ 0 (
    echo 🚨 警告：配置文件中检测到未替换的 '%PLACEHOLDER%'！
    echo    程序可能无法正常运行。
    set /p confirm=确定要继续启动吗？(y/N):
    if /i not "!confirm!"=="y" exit /b 0
)

if not exist "./run" mkdir "./run"
del /q ./run\*.log 2>nul

echo ⏳ Sing-box 已启动。
echo ℹ️  按 Ctrl+C 退出程序。

.\sing-box.exe run -c "%CONFIG_FILE%" -D .\
pause
exit /b 0

:update
echo 📝 更新订阅链接
echo 💡 提示：如果只输入一个链接，它将被复制到所有三个位置。

set /p url1=请输入 订阅1 链接:
set /p url2=请输入 订阅2 链接 (可留空):
set /p url3=请输入 订阅3 链接 (可留空):

if "%url1%"=="" (
    echo ❌ 错误：你没有输入任何链接！
    pause
    exit /b 1
)
if "%url2%"=="" set url2=%url1%
if "%url3%"=="" set url3=%url1%

copy "%CONFIG_FILE%" "%CONFIG_FILE%.backup_%date:/=-%_%time::=%"
echo 📄 已备份原配置文件

echo ✅ 正在更新配置文件...
powershell -Command ^
    "$c = Get-Content '%CONFIG_FILE%' -Raw; " ^
    "$c = [regex]::Replace($c, [regex]::Escape('%PLACEHOLDER%'), '%url1%', 1); " ^
    "$c = [regex]::Replace($c, [regex]::Escape('%PLACEHOLDER%'), '%url2%', 1); " ^
    "$c = [regex]::Replace($c, [regex]::Escape('%PLACEHOLDER%'), '%url3%', 1); " ^
    "Set-Content '%CONFIG_FILE%' -Value $c -NoNewline"

echo.
echo ✅ 成功！配置文件已更新。
echo    订阅1: %url1%
echo    订阅2: %url2%
echo    订阅3: %url3%
pause
exit /b 0
