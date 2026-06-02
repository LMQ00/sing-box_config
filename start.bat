@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

REM --- 切换到脚本所在目录 ---
cd /d "%~dp0"

REM --- 管理员提权（处理路径空格） ---
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process cmd -ArgumentList '/c """%~dpfx0"""' -Verb RunAs"
    exit /b
)

set CONFIG_FILE=config.json
set PLACEHOLDER=订阅链接
set TARGET_BINARY=sing-box.exe
set GITHUB_REPO=LMQ00/sing-box
set GITHUB_API=https://api.github.com/repos/%GITHUB_REPO%/releases/latest

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

REM --- 检查 curl 是否可用 ---
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ 错误：未找到 curl 命令，请先安装 curl 或升级到 Windows 10 1803+。
    pause
    exit /b 1
)

REM --- 检测系统架构 ---
echo 🔍 正在检测系统架构...
REM 处理 ARM64 WoW64 场景：cmd.exe 以 x86 兼容模式运行时
if defined PROCESSOR_ARCHITEW6432 (
    set "REAL_ARCH=%PROCESSOR_ARCHITEW6432%"
) else (
    set "REAL_ARCH=%PROCESSOR_ARCHITECTURE%"
)
if /i "%REAL_ARCH%"=="ARM64" (
    set PLATFORM=windows-arm64
) else if /i "%REAL_ARCH%"=="x86" (
    set PLATFORM=windows-386
) else (
    set PLATFORM=windows-amd64
)
echo 💻 检测到架构: %PLATFORM%

REM --- 检查是否已存在 sing-box.exe ---
if exist "%TARGET_BINARY%" (
    echo ✅ 检测到现有 sing-box.exe 文件，跳过下载。
    echo    如需更新，请删除 %TARGET_BINARY% 后重新运行脚本。
    goto check_config
)

echo 📥 正在从 GitHub 下载最新版本...

REM --- 获取最新版本号 ---
for /f "tokens=2 delims=:" %%i in ('curl -s "%GITHUB_API%" ^| findstr "tag_name"') do (
    set "RAW_TAG=%%i"
)
set TAG=%RAW_TAG: =%
set TAG=%TAG:"=%
set TAG=%TAG:~0,-1%

echo 📦 最新版本: %TAG%

REM --- 验证版本号格式 ---
echo %TAG% | findstr /r "^v[0-9]" >nul
if %errorlevel% neq 0 (
    echo ❌ 错误：无法获取版本号，可能是网络问题或 API 限流。
    echo    请稍后重试或手动下载: https://github.com/LMQ00/sing-box/releases
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

REM --- 构建下载文件名 ---
set "DOWNLOAD_FILE=sing-box-%TAG:~1%-%PLATFORM%.zip"
set "DOWNLOAD_URL=https://github.com/%GITHUB_REPO%/releases/download/%TAG%/%DOWNLOAD_FILE%"

echo 📥 正在下载: %DOWNLOAD_FILE%

REM --- 创建临时目录 ---
set "TEMP_DIR=%TEMP%\sing-box-%RANDOM%"
mkdir "%TEMP_DIR%" 2>nul

REM --- 下载文件 ---
curl -L -o "%TEMP_DIR%\%DOWNLOAD_FILE%" "%DOWNLOAD_URL%"
if %errorlevel% neq 0 (
    echo ❌ 错误：下载失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

REM --- 检查文件是否下载成功 ---
if not exist "%TEMP_DIR%\%DOWNLOAD_FILE%" (
    echo ❌ 错误：下载的文件不存在
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

echo 📦 正在解压...

REM --- 解压 zip 文件 ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_DIR%\%DOWNLOAD_FILE%' -DestinationPath '%TEMP_DIR%\extracted' -Force"
if %errorlevel% neq 0 (
    echo ❌ 错误：解压失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

REM --- 查找解压后的 sing-box.exe（取第一个匹配） ---
set "FOUND_BINARY="
for /f "delims=" %%f in ('dir /s /b "%TEMP_DIR%\extracted\sing-box.exe" 2^>nul') do (
    if not defined FOUND_BINARY set "FOUND_BINARY=%%f"
)

if not defined FOUND_BINARY (
    echo ❌ 错误：在压缩包中未找到 sing-box.exe
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

REM --- 复制到目标位置 ---
copy /y "%FOUND_BINARY%" "%TARGET_BINARY%" > nul
if %errorlevel% neq 0 (
    echo ❌ 错误：安装失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
    pause
    exit /b 1
)

REM --- 清理临时文件 ---
rmdir /s /q "%TEMP_DIR%" 2>nul

echo ✅ sing-box (%PLATFORM%) 下载并安装成功！

:check_config
if not exist "%TARGET_BINARY%" (
    echo ❌ 错误：找不到 sing-box.exe！
    pause
    exit /b 1
)

echo ✅ 准备启动。

REM ===================== 主菜单 =====================
echo ==================================
echo 1. 启动 sing-box 核心
echo 2. 更新订阅链接
echo 3. 自动修复（清除缓存）
echo 4. 重置配置（从备份恢复）
echo ==================================
set /p choice=请选择操作 (1-4):

if "%choice%"=="1" goto start
if "%choice%"=="2" goto update
if "%choice%"=="3" goto fix
if "%choice%"=="4" goto reset
echo ❌ 无效选择，请输入 1-4。
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

REM 清理旧日志，只保留最近 5 个
set COUNT=0
for /f %%f in ('dir /b /o-n "run\*.log" 2^>nul') do (
    set /a COUNT+=1
    if !COUNT! GTR 5 del /f /q "run\%%f"
)

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

REM ===================== 自动修复：清除缓存 =====================
:fix
echo 🔧 自动修复：清除缓存文件...

if exist "cache.db" (
    del /f /q "cache.db" 2>nul
    echo    ✅ 已删除 cache.db
) else (
    echo    ℹ️  cache.db 不存在，跳过
)

if exist "run" (
    rmdir /s /q "run" 2>nul
    echo    ✅ 已删除 run 目录
) else (
    echo    ℹ️  run 目录不存在，跳过
)

echo ✅ 缓存清理完成！
pause
exit /b 0

REM ===================== 重置配置：从备份恢复 =====================
:reset
echo 🔄 重置配置：从备份恢复...

REM 查找最新的备份文件
set "LATEST_BACKUP="
for /f "delims=" %%f in ('dir /b /o-n "%CONFIG_FILE%.backup_*" 2^>nul') do (
    if not defined LATEST_BACKUP set "LATEST_BACKUP=%%f"
)

if not defined LATEST_BACKUP (
    echo ❌ 错误：未找到任何备份文件！
    echo    备份文件格式：config.json.backup_YYYYMMDD_HHMMSS
    pause
    exit /b 1
)

call echo    找到最新备份: %%LATEST_BACKUP%%
set /p confirm=确定要恢复此备份吗？(y/N):
if /i not "%confirm%"=="y" exit /b 0

call copy /y "%%LATEST_BACKUP%%" "%CONFIG_FILE%" >nul 2>nul
if %errorlevel% equ 0 (
    call echo ✅ 配置已恢复自 %%LATEST_BACKUP%%
) else (
    echo ❌ 恢复失败！
)

pause
exit /b 0