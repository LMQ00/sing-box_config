@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

REM --- 切换到脚本所在目录 ---
cd /d "%~dp0"

REM --- 管理员提权（处理路径空格；用 IsInRole 检测，避免依赖 Server 服务） ---
powershell -NoProfile -Command "exit ([int](-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))" >nul 2>&1
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
set DASHBOARD_DIR=.\dashboard
set M1=启动 sing-box 核心
set M2=更新订阅链接
set M3=自动修复(清除缓存)
set M4=重置配置(从备份恢复)
set M5=更新内核
set M6=退出

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

REM --- 加速链接列表（按优先级排序） ---
set "MIRRORS=https://gh.xmly.dev https://ghfast.top https://ghgo.xyz https://gh-proxy.com https://mirror.ghproxy.com"

REM --- 自动部署 sing-box 核心 ---
if not exist "%TARGET_BINARY%" (
    call :download_singbox
    if errorlevel 1 (
        pause
        exit /b 1
    )
)

:check_config
if not exist "%TARGET_BINARY%" (
    echo ❌ 错误：找不到 sing-box.exe！
    pause
    exit /b 1
)

REM --- 下载 Dashboard（与二进制文件同时部署） ---
call :download_dashboard

echo ✅ 准备启动。
echo.

goto menu

REM ===================== 下载 sing-box 核心 =====================
:download_singbox
echo 📥 正在从 GitHub 下载最新版本...

REM --- 获取最新版本号 ---
for /f "tokens=2 delims=:" %%i in ('curl -s "%GITHUB_API%" ^| findstr "tag_name"') do (
    set "RAW_TAG=%%i"
)
set "TAG=%RAW_TAG: =%"
set "TAG=%TAG:"=%"
set "TAG=%TAG:~0,-1%"

if not defined TAG (
    echo ❌ 错误：无法获取版本号，可能是网络问题或 API 限流。
    echo    请稍后重试或手动下载: https://github.com/LMQ00/sing-box/releases
    exit /b 1
)

REM --- 验证版本号格式（经环境变量传给 PowerShell，避免引号/注入；findstr 双锚点+重复类有缺陷） ---
set "SBTAG=%TAG%"
powershell -NoProfile -Command "exit ([int](-not ($env:SBTAG -match '^v[0-9][0-9.a-zA-Z-]*$')))" >nul 2>nul
if errorlevel 1 (
    echo ❌ 错误：无法获取版本号，可能是网络问题或 API 限流。
    echo    请稍后重试或手动下载: https://github.com/LMQ00/sing-box/releases
    exit /b 1
)

echo 📦 最新版本: %TAG%

REM --- 构建下载文件名 ---
set "DOWNLOAD_FILE=sing-box-%TAG:~1%-%PLATFORM%.zip"
set "DOWNLOAD_URL=https://github.com/%GITHUB_REPO%/releases/download/%TAG%/%DOWNLOAD_FILE%"

REM --- 创建临时目录 ---
set "TEMP_DIR=%TEMP%\sing-box-%RANDOM%%RANDOM%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if errorlevel 1 (
    echo ❌ 错误：无法创建临时目录 %TEMP_DIR%
    exit /b 1
)

REM --- 尝试直接下载 ---
echo 📥 正在下载: %DOWNLOAD_FILE%
set "DL_OK=0"
curl -fL --connect-timeout 15 --max-time 120 -o "%TEMP_DIR%\%DOWNLOAD_FILE%" "%DOWNLOAD_URL%" 2>nul
if %errorlevel% equ 0 if exist "%TEMP_DIR%\%DOWNLOAD_FILE%" (
    for %%a in ("%TEMP_DIR%\%DOWNLOAD_FILE%") do (
        if %%~za GTR 1000 set "DL_OK=1"
    )
)

REM --- 直接下载失败时，依次尝试加速链接 ---
if "%DL_OK%"=="0" (
    echo ⚠️  直接下载失败，尝试加速链接...
    for %%m in (%MIRRORS%) do (
        if "!DL_OK!"=="0" (
            echo 🔄 尝试加速链接: %%m
            curl -fL --connect-timeout 15 --max-time 120 -o "%TEMP_DIR%\%DOWNLOAD_FILE%" "%%m/https://github.com/%GITHUB_REPO%/releases/download/%TAG%/%DOWNLOAD_FILE%" 2>nul
            if !errorlevel! equ 0 if exist "%TEMP_DIR%\%DOWNLOAD_FILE%" (
                for %%a in ("%TEMP_DIR%\%DOWNLOAD_FILE%") do (
                    if %%~za GTR 1000 set "DL_OK=1"
                )
            )
            if "!DL_OK!"=="1" echo ✅ 加速链接下载成功: %%m
        )
    )
)

if "%DL_OK%"=="0" (
    echo ❌ 错误：所有下载链接均失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
    exit /b 1
)

echo 📦 正在解压...

REM --- 解压 zip 文件 ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_DIR%\%DOWNLOAD_FILE%' -DestinationPath '%TEMP_DIR%\extracted' -Force"
if %errorlevel% neq 0 (
    echo ❌ 错误：解压失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
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
    exit /b 1
)

REM --- 复制到目标位置 ---
copy /y "%FOUND_BINARY%" "%TARGET_BINARY%" > nul
if %errorlevel% neq 0 (
    echo ❌ 错误：安装失败
    rmdir /s /q "%TEMP_DIR%" 2>nul
    exit /b 1
)

REM --- 清理临时文件 ---
rmdir /s /q "%TEMP_DIR%" 2>nul

echo ✅ sing-box (%PLATFORM%) 下载并安装成功！
exit /b 0

REM ===================== 主菜单 =====================
:menu
echo ==================================
echo 1. %M1%
echo 2. %M2%
echo 3. %M3%
echo 4. %M4%
echo 5. %M5%
echo 6. %M6%
echo ==================================
set "choice="
set /p choice=请选择操作 (1-6):<con
if not defined choice goto menu
set "choice=%choice: =%"

if "%choice%"=="1" goto start
if "%choice%"=="2" goto update
if "%choice%"=="3" goto fix
if "%choice%"=="4" goto reset
if "%choice%"=="5" goto update_kernel
if "%choice%"=="6" exit /b
echo ❌ 无效选择，请输入 1-6。
pause
goto menu

REM ===================== 启动 sing-box =====================
:start
echo 🚀 正在启动 Sing-box 核心...

REM --- 检测是否已在运行（避免端口 9090 冲突） ---
tasklist /fi "imagename eq sing-box.exe" 2>nul | findstr /i "sing-box.exe" >nul 2>nul
if not errorlevel 1 (
    echo ℹ️  sing-box 已在运行，无需重复启动。
    pause
    goto menu
)

REM --- 占位符检查（用 PowerShell 匹配 UTF-8 内容，findstr 按代码页解释会失效） ---
powershell -NoProfile -Command "$c=Get-Content '%CONFIG_FILE%' -Raw -Encoding UTF8; if($c.Contains('%PLACEHOLDER%')){exit 0}else{exit 1}" >nul 2>nul
if errorlevel 1 goto run_singbox

echo 🚨 警告：配置文件中检测到未替换的 '%PLACEHOLDER%'！
echo    程序可能无法正常运行。
set "confirm="
set /p confirm=确定要继续启动吗？(y/N):<con
if /i not "%confirm%"=="y" goto menu

:run_singbox
if not exist "run" mkdir "run"

REM 轮转日志：将当前日志重命名为带时间戳的文件
if exist "run\sing-box.log" (
    for /f "delims=" %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "LOG_TS=%%d"
    move /y "run\sing-box.log" "run\sing-box-!LOG_TS!.log" >nul 2>nul
)

REM 清理旧日志，只保留最近 5 个
set COUNT=0
for /f %%f in ('dir /b /o-n "run\*.log" 2^>nul') do (
    set /a COUNT+=1
    if !COUNT! GTR 5 del /f /q "run\%%f"
)

echo.
echo ==================================
echo   [OK] sing-box started!
echo ==================================
echo   Dashboard: http://127.0.0.1:9090/ui/
echo   API:      http://127.0.0.1:9090
echo ==================================
echo.

REM 后台启动 sing-box
start "" /B .\sing-box.exe run -c "%CONFIG_FILE%" -D .\ > "run\sing-box.log" 2>&1

REM --- 等待并检测进程是否存活（秒退时给出明确错误） ---
timeout /t 2 /nobreak >nul 2>nul
tasklist /fi "imagename eq sing-box.exe" 2>nul | findstr /i "sing-box.exe" >nul 2>nul
if errorlevel 1 (
    echo ❌ 错误：Sing-box 启动失败，请查看 run\sing-box.log。
    pause
    goto menu
)

echo [OK] sing-box running in background.
echo Log: run\sing-box.log
echo Press any key to view log, Ctrl+C to exit.

:watch_log
REM 按任意键打开日志
pause >nul
if exist "run\sing-box.log" (
    type "run\sing-box.log"
)
goto watch_log

REM ===================== 下载 Dashboard =====================
:download_dashboard
if exist "%DASHBOARD_DIR%" (
    dir /b "%DASHBOARD_DIR%\*" >nul 2>nul && (
        echo ✅ Dashboard 已存在，跳过下载。
        exit /b 0
    )
)

REM --- 第1步：从 config.json 提取 external_ui_download_url ---
REM 用 findstr 提取（键名纯 ASCII，不受代码页影响；for /f 自动去掉行尾 CR）
set "DASHBOARD_URL="
for /f "tokens=1* delims=:" %%k in ('findstr /c:"external_ui_download_url" "%CONFIG_FILE%" 2^>nul') do (
    set "DASHBOARD_URL=%%l"
)
REM 去掉空白、引号与可能的行尾逗号
set "DASHBOARD_URL=%DASHBOARD_URL: =%"
set "DASHBOARD_URL=%DASHBOARD_URL:"=%"
if "%DASHBOARD_URL:~-1%"=="," set "DASHBOARD_URL=%DASHBOARD_URL:~0,-1%"

if not defined DASHBOARD_URL (
    echo ℹ️  config.json 中未配置 external_ui_download_url，跳过 Dashboard 下载。
    exit /b 0
)

echo 📥 正在下载 Dashboard...

set "TEMP_DIR=%TEMP%\dashboard-%RANDOM%%RANDOM%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if errorlevel 1 (
    echo ⚠️  无法创建临时目录 %TEMP_DIR%，跳过 Dashboard 下载。
    exit /b 0
)
set "ZIP_FILE=%TEMP_DIR%\dashboard.zip"

REM --- 第2步：直连下载 + 加速链接负载均衡 ---
set "DL_OK=0"
echo 📥 尝试直连...
curl -fL --connect-timeout 15 --max-time 120 -o "%ZIP_FILE%" "%DASHBOARD_URL%" 2>nul
if %errorlevel% equ 0 if exist "%ZIP_FILE%" (
    for %%a in ("%ZIP_FILE%") do if %%~za GTR 1000 set "DL_OK=1"
)

REM 如果直连失败且是 GitHub 地址，依次尝试加速链接
if "!DL_OK!"=="0" (
    echo %DASHBOARD_URL% | findstr "github.com" >nul
    if not errorlevel 1 (
        echo ⚠️  直连失败，尝试加速链接...

        REM 剥离已知镜像前缀，获取原始 GitHub URL
        set "RAW_URL=%DASHBOARD_URL%"
        for %%m in (%MIRRORS%) do (
            set "TMP_URL=!RAW_URL:%%m/=!"
            if not "!TMP_URL!"=="!RAW_URL!" set "RAW_URL=!TMP_URL!"
        )

        for %%m in (%MIRRORS%) do (
            if "!DL_OK!"=="0" (
                echo 🔄 尝试加速链接: %%m
                curl -fL --connect-timeout 15 --max-time 120 -o "!ZIP_FILE!" "%%m/!RAW_URL!" 2>nul
                if !errorlevel! equ 0 if exist "!ZIP_FILE!" (
                    for %%a in ("!ZIP_FILE!") do if %%~za GTR 1000 set "DL_OK=1"
                )
                if "!DL_OK!"=="1" echo ✅ 加速链接下载成功: %%m
            )
        )
    )
)

if "%DL_OK%"=="0" (
    echo ⚠️  Dashboard 所有下载链接均失败，跳过。
    rmdir /s /q "%TEMP_DIR%" 2>nul
    exit /b 0
)

echo 📦 正在解压 Dashboard...

REM --- 第3步：解压到 dashboard 目录 ---
mkdir "%DASHBOARD_DIR%" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$e='%TEMP_DIR%\extracted';Expand-Archive -Path '%ZIP_FILE%' -DestinationPath $e -Force;$i=Get-ChildItem $e;if($i.Count-eq1-and$i[0].PSIsContainer){$s=$i[0].FullName;Get-ChildItem $s|Copy-Item -Destination '%DASHBOARD_DIR%' -Recurse -Force}else{Get-ChildItem $e|Copy-Item -Destination '%DASHBOARD_DIR%' -Recurse -Force};Write-Host '✅ Dashboard 部署完成！路径: %DASHBOARD_DIR%'}catch{exit 1}"

if %errorlevel% neq 0 (
    echo ⚠️  Dashboard 解压失败，跳过。
)

rmdir /s /q "%TEMP_DIR%" 2>nul
exit /b 0

REM ===================== 更新订阅链接 =====================
:update
echo 📝 更新订阅链接
echo 💡 提示：如果只输入一个链接，它将被复制到所有三个位置。

REM --- 使用 PowerShell 安全更新（Read-Host 防注入；无占位符时不改动并提示） ---
powershell -NoProfile -ExecutionPolicy Bypass -NoLogo -Command ^
    "$ph='%PLACEHOLDER%'; $cfg='%CONFIG_FILE%';" ^
    "$c=Get-Content $cfg -Raw -Encoding UTF8;" ^
    "if(-not $c.Contains($ph)){Write-Host '⚠️ 配置文件中未找到占位符（可能已配置过订阅），未做修改。'; exit 0};" ^
    "$u1=Read-Host '请输入 订阅1 链接';" ^
    "if([string]::IsNullOrWhiteSpace($u1)){Write-Host '❌ 错误：你没有输入任何链接！'; exit 1};" ^
    "$u2=Read-Host '请输入 订阅2 链接 (可留空)';" ^
    "$u3=Read-Host '请输入 订阅3 链接 (可留空)';" ^
    "if([string]::IsNullOrWhiteSpace($u2)){$u2=$u1};" ^
    "if([string]::IsNullOrWhiteSpace($u3)){$u3=$u1};" ^
    "$bak=$cfg+'.backup_'+ (Get-Date -Format 'yyyyMMdd_HHmmss');" ^
    "Copy-Item $cfg $bak -Force -ErrorAction Stop;" ^
    "Write-Host ('📄 已备份原配置文件 → '+$bak);" ^
    "foreach($u in @($u1,$u2,$u3)){" ^
    "  $i=$c.IndexOf($ph); if($i-lt 0){break};" ^
    "  $c=$c.Substring(0,$i)+$u+$c.Substring($i+$ph.Length)" ^
    "};" ^
    "[IO.File]::WriteAllText($cfg, $c, (New-Object System.Text.UTF8Encoding $false));" ^
    "$left=([regex]::Matches($c,[regex]::Escape($ph))).Count;" ^
    "if($left-gt 0){Write-Host ('⚠️ 仍有 {0} 个占位符未替换（订阅数量少于 3 时正常）。' -f $left)};" ^
    "Write-Host '';" ^
    "Write-Host '✅ 成功！配置文件已更新。';" ^
    "foreach($i in 0..2){" ^
    "  $v=@($u1,$u2,$u3)[$i];" ^
    "  if($v.Length-gt 20){$v=$v.Substring(0,20)+'...'};" ^
    "  Write-Host ('   订阅{0}: {1}' -f ($i+1),$v)" ^
    "}"

if %errorlevel% neq 0 (
    echo ❌ 更新失败（未输入链接或 PowerShell 异常）！
    pause
    goto menu
)

pause
goto menu

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
goto menu

REM ===================== 更新内核 =====================
:update_kernel
echo 🔄 正在更新 sing-box 核心...

REM --- 检测是否在运行（文件被占用时备份/替换会失败） ---
tasklist /fi "imagename eq sing-box.exe" 2>nul | findstr /i "sing-box.exe" >nul 2>nul
if not errorlevel 1 (
    echo ⚠️  sing-box 正在运行，请先停止（结束 sing-box.exe 进程）再更新内核。
    pause
    goto menu
)

REM --- 备份现有二进制文件（括号块内 %var% 是解析期展开，须用 !var!） ---
if exist "%TARGET_BINARY%" (
    for /f "delims=" %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "BACKUP_TS=%%d"
    copy /y "%TARGET_BINARY%" "%TARGET_BINARY%.backup_!BACKUP_TS!" >nul 2>nul
    if errorlevel 1 (
        echo ❌ 备份失败（文件可能被占用），已中止更新。
        pause
        goto menu
    )
    echo 📄 已备份原核心 → %TARGET_BINARY%.backup_!BACKUP_TS!
)

REM --- 调用下载子程序 ---
call :download_singbox
if errorlevel 1 (
    echo ❌ 核心更新失败
    pause
    goto menu
)

echo ✅ 核心更新完成！
pause
goto menu

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
    goto menu
)

echo    找到最新备份: %LATEST_BACKUP%
set "confirm="
set /p confirm=确定要恢复此备份吗？(y/N):<con
if /i not "%confirm%"=="y" goto menu

copy /y "%LATEST_BACKUP%" "%CONFIG_FILE%" >nul 2>nul
if %errorlevel% equ 0 (
    echo ✅ 配置已恢复自 %LATEST_BACKUP%
) else (
    echo ❌ 恢复失败！
)

pause
goto menu