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
set SOURCE_PATH=./bin/windows-amd64/sing-box.exe
set RUN_DIR=./run
set LOG_FILE=./run/sing-box.log
set DASHBOARD_DIR=./dashboard
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

goto :eof

REM ===================== 启动 sing-box =====================
:start
echo 🚀 正在启动 Sing-box 核心...

findstr /c:"%PLACEHOLDER%" "%CONFIG_FILE%" >nul
if %errorlevel% equ 0 (
    echo 🚨 警告：配置文件中检测到未替换的 '%PLACEHOLDER%'！
    echo    程序可能无法正常运行。
    set /p confirm=确定要继续启动吗？(y/N):
    if /i not "!confirm!"=="y" exit /b 0
)

REM --- 创建运行目录并清理旧日志（只保留最近 MAX_LOGS 个） ---
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"
call :cleanup_logs "%RUN_DIR%" %MAX_LOGS%

REM --- 启动 sing-box ---
start "" /b sing-box.exe run -c "%CONFIG_FILE%" -D .\ > "%LOG_FILE%" 2>&1

REM --- 等待 2 秒后检查进程是否存活 ---
timeout /t 2 /nobreak > nul
tasklist /fi "imagename eq sing-box.exe" | find /i "sing-box.exe" > nul
if %errorlevel% neq 0 (
    echo ❌ 错误：Sing-box 启动失败，请检查 %LOG_FILE% 查看详情。
    pause
    exit /b 1
)

REM --- 设置退出清理标记 ---
set "SINGBOX_STARTED=1"

echo ✅ Sing-box 已启动。
echo    日志: %LOG_FILE%

REM --- 等待 dashboard 就绪，最多 60 秒 ---
echo ⏳ 正在等待 %DASHBOARD_DIR% 生成文件...
set /a dashboard_wait=0
:wait_dashboard
if !dashboard_wait! geq 60 goto dashboard_timeout

REM 检查 sing-box 进程是否仍然存活
tasklist /fi "imagename eq sing-box.exe" | find /i "sing-box.exe" > nul
if %errorlevel% neq 0 (
    echo ❌ 错误：Sing-box 进程已退出，请检查 %LOG_FILE% 查看详情。
    pause
    exit /b 1
)

REM 检查 dashboard 目录是否有文件
if exist "%DASHBOARD_DIR%\*" (
    echo ✅ 检测到 %DASHBOARD_DIR% 中有文件，正在执行节点切换...
    powershell -NoProfile -Command ^
        "try { Invoke-RestMethod -Method Put -Uri '%API_BASE%/proxies/国外代理' -ContentType 'application/json' -Body '{\"name\":\"订阅1国外自动\"}' | Out-Null; Write-Host '✅ 节点切换成功。' } catch { Write-Host ('⚠️  节点切换失败: ' + $_.Exception.Message) }"
    goto after_dashboard
)

REM 每 5 秒打印一次进度
set /a mod=!dashboard_wait! %% 5
if !dashboard_wait! gtr 0 if !mod! equ 0 (
    echo ⏳ 已等待 !dashboard_wait! 秒，继续等待 %DASHBOARD_DIR% ...
)

timeout /t 1 /nobreak > nul
set /a dashboard_wait+=1
goto wait_dashboard

:dashboard_timeout
echo ⚠️  等待超时（60 秒），%DASHBOARD_DIR% 尚未生成文件，跳过自动节点切换。

:after_dashboard
echo ℹ️  按 Ctrl+C 退出程序。
echo ⏳ sing-box 运行中，脚本进入等待状态...

REM --- 等待 sing-box 进程退出 ---
:wait_exit
timeout /t 3 /nobreak > nul
tasklist /fi "imagename eq sing-box.exe" | find /i "sing-box.exe" > nul
if %errorlevel% equ 0 goto wait_exit

echo ⚠️  Sing-box 进程已退出。
call :cleanup
pause
exit /b 0

REM ===================== 更新订阅链接 =====================
:update
echo 📝 更新订阅链接
echo 💡 提示：如果只输入一个链接，它将被复制到所有三个位置。

REM --- 备份（用 PowerShell 生成统一格式的日期时间） ---
for /f "usebackq delims=" %%d in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set BACKUP_TS=%%d
copy "%CONFIG_FILE%" "%CONFIG_FILE%.backup_%BACKUP_TS%" > nul
echo 📄 已备份原配置文件

echo ✅ 正在更新配置文件...

REM 使用临时 .ps1 脚本完成输入 + 替换，防止命令注入
set "PS_SCRIPT=%TEMP%\singbox_update_%RANDOM%.ps1"
(
    echo $ErrorActionPreference = 'Stop'
    echo $configPath = '%CONFIG_FILE%'
    echo $placeholder = '%PLACEHOLDER%'
    echo.
    echo $u1 = Read-Host '请输入 订阅1 链接'
    echo $u2 = Read-Host '请输入 订阅2 链接 (可留空^)'
    echo $u3 = Read-Host '请输入 订阅3 链接 (可留空^)'
    echo.
    echo if ([string]::IsNullOrWhiteSpace($u1^) ^) { Write-Host '❌ 错误：你没有输入任何链接！'; exit 1 }
    echo if ([string]::IsNullOrWhiteSpace($u2^) ^) { $u2 = $u1 }
    echo if ([string]::IsNullOrWhiteSpace($u3^) ^) { $u3 = $u1 }
    echo.
    echo $content = Get-Content $configPath -Raw -Encoding UTF8
    echo.
    echo # 逐个替换占位符（每次只替换第一个匹配）
    echo for ($n = 1; $n -le 3; $n++^) {
    echo     $idx = $content.IndexOf($placeholder^)
    echo     if ($idx -lt 0^) { break }
    echo     $val = Get-Variable -Name ('u'+$n^) -ValueOnly
    echo     $content = $content.Substring(0, $idx^) + $val + $content.Substring($idx + $placeholder.Length^)
    echo }
    echo Set-Content $configPath -Value $content -NoNewline -Encoding UTF8
    echo.
    echo Write-Host ''
    echo Write-Host '✅ 成功！配置文件已更新。'
    echo foreach ($i in 1..3^) {
    echo     $u = Get-Variable -Name ('u'+$i^) -ValueOnly
    echo     if ($u.Length -gt 20^) { Write-Host ('   订阅{0}: {1}...' -f $i, $u.Substring(0,20^) ^) }
    echo     else { Write-Host ('   订阅{0}: {1}' -f $i, $u ^) }
    echo }
) > "%PS_SCRIPT%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "PS_RESULT=%errorlevel%"

REM --- 清理临时脚本 ---
del "%PS_SCRIPT%" 2>nul

if %PS_RESULT% neq 0 (
    echo ❌ 更新失败！
    pause
    exit /b 1
)

pause
exit /b 0

REM ===================== 退出清理：终止 sing-box 进程 =====================
:cleanup
if "%SINGBOX_STARTED%"=="1" (
    echo 🛑 正在停止 sing-box...
    taskkill /im sing-box.exe /f > nul 2>&1
    echo ✅ sing-box 已停止。
)
exit /b 0

REM ===================== 子例程：清理旧日志 =====================
REM 用法: call :cleanup_logs "目录" 最大数量
:cleanup_logs
set "_logdir=%~1"
set "_maxlogs=%~2"
set /a "_logcount=0"

REM 统计日志文件数量
for %%f in ("%_logdir%\*.log") do set /a "_logcount+=1"

if %_logcount% leq %_maxlogs% goto :eof

REM 计算需要删除的数量
set /a "_todelete=%_logcount% - %_maxlogs%"

REM 按修改时间排序，删除最旧的文件（使用 PowerShell）
powershell -NoProfile -Command ^
    "Get-ChildItem '%_logdir%\*.log' | Sort-Object LastWriteTime | Select-Object -First %_todelete% | Remove-Item -Force"

goto :eof
