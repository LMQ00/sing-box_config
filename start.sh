#!/bin/bash
# =============================================================================
# sing-box 管理脚本 (Linux/macOS)
# 功能：自动部署、启动 sing-box 核心，以及更新订阅链接
# 兼容：Linux / macOS
# =============================================================================

# --- cd 到脚本所在目录（兼容符号链接和各种 shell） ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$SCRIPT_DIR" || { echo "❌ 错误：无法切换到脚本目录 $SCRIPT_DIR"; exit 1; }

# --- 全局常量（readonly） ---
readonly CONFIG_FILE="config.json"
readonly PLACEHOLDER="订阅链接"
readonly BIN_DIR="./bin"
readonly TARGET_BINARY="./sing-box"
readonly RUN_DIR="./run"
readonly LOG_FILE="$RUN_DIR/sing-box.log"
readonly DASHBOARD_DIR="./dashboard"
readonly MAX_LOGS=5
readonly GITHUB_REPO="LMQ00/sing-box"
readonly GITHUB_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
TEMP_DIRS=()

# --- 信号处理：优雅退出 ---
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
trap cleanup SIGINT SIGTERM EXIT

# --- macOS 与 Linux 兼容的 sed -i 封装 ---
# 用法: sed_inplace 's|old|new|g' 文件
sed_inplace() {
    local expr="$1"
    local file="$2"
    if [[ "$OSTYPE" == darwin* ]]; then
        sed -i '' "$expr" "$file"
    else
        sed -i "$expr" "$file"
    fi
}

# --- 检查 sudo 是否可用 ---
ensure_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo "🔑 需要管理员权限来运行 sing-box，请输入密码..."
        if ! sudo -v; then
            echo "❌ 错误：无法获取 sudo 权限。"
            exit 1
        fi
    fi
}

# --- 检查 curl 是否可用 ---
check_curl() {
    if ! command -v curl &>/dev/null; then
        echo "❌ 错误：未找到 curl 命令，请先安装 curl。"
        exit 1
    fi
}

# --- 清理旧日志，只保留最近 MAX_LOGS 个 ---
cleanup_old_logs() {
    local dir="$1"
    local max="$2"
    mkdir -p "$dir"
    local count
    count=$(find "$dir" -maxdepth 1 -name '*.log' -type f 2>/dev/null | wc -l)
    count=$((count + 0))  # trim whitespace
    if (( count > max )); then
        local remove_count=$(( count - max ))
        # macOS 用 stat -f，Linux 用 stat -c
        if [[ "$OSTYPE" == darwin* ]]; then
            find "$dir" -maxdepth 1 -name '*.log' -type f -exec stat -f '%m %N' {} + 2>/dev/null \
                | sort -n \
                | head -n "$remove_count" \
                | awk '{print $2}' \
                | xargs rm -f
        else
            find "$dir" -maxdepth 1 -name '*.log' -type f -printf '%T@ %p\n' 2>/dev/null \
                | sort -n \
                | head -n "$remove_count" \
                | awk '{print $2}' \
                | xargs rm -f
        fi
    fi
}

# --- 脱敏显示 URL ---
mask_url() {
    local url="$1"
    if [[ ${#url} -gt 20 ]]; then
        echo "${url:0:20}..."
    else
        echo "$url"
    fi
}

# ===================== 检测系统架构 =====================
detect_platform() {
    local os="" arch=""

    case "$OSTYPE" in
        linux-android*) os="android" ;;
        linux-gnu*)    os="linux" ;;
        darwin*)       os="darwin" ;;
        msys*|cygwin*|mingw*) os="windows" ;;
        *)
            echo "⚠️  警告：无法识别的操作系统 ($OSTYPE)"
            return 1 ;;
    esac

    local machine_type=$(uname -m)
    case "$machine_type" in
        x86_64)               arch="amd64" ;;
        aarch64|arm64|armv8*) arch="arm64" ;;
        armv7*|armhf*)        arch="armv7" ;;
        i386|i686)            arch="386" ;;
        *)
            echo "⚠️  警告：无法识别的架构 ($machine_type)"
            return 1 ;;
    esac

    echo "$os-$arch"
}

# ===================== 从 GitHub 下载最新版本 =====================
# 加速链接列表（按优先级排序）
MIRROR_URLS=(
    "https://ghfast.top"
    "https://ghgo.xyz"
    "https://gh-proxy.com"
    "https://mirror.ghproxy.com"
)

download_and_validate() {
    local url="$1"
    local output="$2"
    local desc="$3"

    echo "📥 正在下载: $desc"
    if curl -L --connect-timeout 15 --max-time 120 -o "$output" "$url" 2>/dev/null; then
        local fsize
        fsize=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo 0)
        if [[ -f "$output" ]] && [[ "$fsize" -gt 1000 ]]; then
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

download_latest_version() {
    local platform="$1"

    echo "🔍 正在从 GitHub 获取最新版本信息..."

    # 获取最新版本的 tag
    local latest_tag
    latest_tag=$(curl -s --connect-timeout 15 --max-time 30 "$GITHUB_API" | grep -o '"tag_name": "[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$latest_tag" ]]; then
        echo "❌ 错误：无法获取最新版本信息"
        return 1
    fi

    echo "📦 最新版本: $latest_tag"

    # 构建下载文件名（Linux/macOS 用 tar.gz）
    local download_file="sing-box-${latest_tag#v}-${platform}.tar.gz"
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$latest_tag/$download_file"

    echo "📥 正在下载: $download_file"

    # 下载文件
    local temp_dir
    temp_dir=$(mktemp -d)
    TEMP_DIRS+=("$temp_dir")

    # 尝试直接下载
    if download_and_validate "$download_url" "$temp_dir/$download_file" "$download_file"; then
        echo "✅ 直接下载成功"
    else
        echo "⚠️  直接下载失败，尝试加速链接..."
        local success=false
        for mirror in "${MIRROR_URLS[@]}"; do
            local mirror_url="${mirror}/https://github.com/$GITHUB_REPO/releases/download/$latest_tag/$download_file"
            echo "🔄 尝试加速链接: $mirror"
            if download_and_validate "$mirror_url" "$temp_dir/$download_file" "$download_file (via $mirror)"; then
                success=true
                echo "✅ 加速链接下载成功: $mirror"
                break
            fi
        done
        if [[ "$success" != true ]]; then
            echo "❌ 错误：所有下载链接均失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    echo "📦 正在解压..."

    # 解压文件
    if ! tar -xzf "$temp_dir/$download_file" -C "$temp_dir"; then
        echo "❌ 错误：解压失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 查找解压后的 sing-box 文件
    local extracted_binary
    extracted_binary=$(find "$temp_dir" -name "sing-box" -type f 2>/dev/null | head -1)

    if [[ -z "$extracted_binary" ]]; then
        echo "❌ 错误：在压缩包中未找到 sing-box 文件"
        rm -rf "$temp_dir"
        return 1
    fi

    # 复制到目标位置
    if ! install -m 755 "$extracted_binary" "$TARGET_BINARY"; then
        echo "❌ 错误：安装失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 清理临时文件
    rm -rf "$temp_dir"

    echo "✅ sing-box ($platform) 下载并安装成功！"
    return 0
}

# ===================== 自动部署 sing-box 核心 =====================
if [[ -f "$TARGET_BINARY" ]]; then
    echo "✅ 检测到现有 sing-box 文件，跳过下载。"
    echo "   如需更新，请删除 $TARGET_BINARY 后重新运行脚本。"
else
    echo "🔍 正在检测系统架构..."

    PLATFORM=$(detect_platform) || {
        echo "❌ 无法检测系统架构，请手动下载 sing-box"
        echo "   下载地址: https://github.com/$GITHUB_REPO/releases"
        exit 1
    }

    echo "💻 检测到平台: $PLATFORM"

    # 尝试从 GitHub 下载
    if ! download_latest_version "$PLATFORM"; then
        echo "❌ 从 GitHub 下载失败"
        echo "   请手动下载 sing-box 并放置到当前目录"
        echo "   下载地址: https://github.com/$GITHUB_REPO/releases"
        exit 1
    fi
fi

# ===================== 前置检查 =====================
[[ -f "$CONFIG_FILE" ]] || { echo "❌ 错误：找不到配置文件 $CONFIG_FILE"; exit 1; }
[[ -f "$TARGET_BINARY" ]] || { echo "❌ 错误：找不到 sing-box 核心文件"; exit 1; }

# 确保 sing-box 可执行
chmod +x "$TARGET_BINARY"

# ===================== 主菜单 =====================
echo "=================================="
echo "   sing-box 管理脚本"
echo "=================================="
echo "1. 启动 sing-box 核心"
echo "2. 更新订阅链接"
echo "3. 自动修复（清除缓存）"
echo "4. 重置配置（从备份恢复）"
echo "=================================="
read -p "请选择操作 (1-4): " choice

case $choice in
    1)
        echo "🚀 正在启动 Sing-box 核心..."

        if grep -q "$PLACEHOLDER" "$CONFIG_FILE"; then
            echo "🚨 警告：配置文件中检测到未替换的 '$PLACEHOLDER'！"
            echo "   程序可能无法正常运行。"
            read -p "确定要继续启动吗？(y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
        fi

        # 清理旧日志，只保留最近 MAX_LOGS 个
        cleanup_old_logs "$RUN_DIR" "$MAX_LOGS"

        ensure_sudo

        sudo "$TARGET_BINARY" run -c "$CONFIG_FILE" -D ./ > "$LOG_FILE" 2>&1 &
        SING_BOX_PID=$!

        # 等待进程启动
        sleep 2
        if ! kill -0 "$SING_BOX_PID" 2>/dev/null; then
            echo "❌ 错误：Sing-box 启动失败，请检查 $LOG_FILE 查看详情。"
            wait "$SING_BOX_PID" 2>/dev/null
            exit 1
        fi

        echo "PID: $SING_BOX_PID  |  日志: $LOG_FILE"
        echo "⏳ Sing-box 已启动，正在等待 $DASHBOARD_DIR 生成文件..."

        # 等待 dashboard 就绪，最多 60 秒，每 5 秒打印进度
        i=0
        for ((i = 0; i < 60; i++)); do
            if ! kill -0 "$SING_BOX_PID" 2>/dev/null; then
                echo "❌ 错误：Sing-box 进程异常退出，请检查 $LOG_FILE 查看详情。"
                exit 1
            fi
            if [[ -d "$DASHBOARD_DIR" ]] && [[ -n "$(find "$DASHBOARD_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
                echo "✅ 检测到 $DASHBOARD_DIR 中有文件，正在执行节点切换..."
                check_curl
                curl_code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "http://127.0.0.1:9090/proxies/国外代理" \
                    -H "Content-Type: application/json" \
                    -d '{"name":"订阅1国外自动"}')
                if [[ "$curl_code" -ge 200 ]] && [[ "$curl_code" -lt 300 ]]; then
                    echo "✅ 节点切换成功。"
                else
                    echo "⚠️  节点切换请求返回 HTTP $curl_code，可能需要手动检查。"
                fi
                break
            fi
            # 每 5 秒打印一次进度
            if (( i > 0 )) && (( i % 5 == 0 )); then
                echo "⏳ 已等待 ${i} 秒，继续等待 $DASHBOARD_DIR ..."
            fi
            sleep 1
        done

        if (( i >= 60 )); then
            echo "⚠️  等待超时（60 秒），$DASHBOARD_DIR 尚未生成文件，跳过自动节点切换。"
        fi

        echo "ℹ️  脚本转入守护模式，按 Ctrl+C 退出。"
        # 清除 EXIT trap，避免正常退出时执行 cleanup
        trap - EXIT
        trap 'echo ""; echo "⚠️  Sing-box 进程已退出。"; exit 0' SIGINT SIGTERM
        wait "$SING_BOX_PID" 2>/dev/null
        SING_BOX_PID=""
        echo "⚠️  Sing-box 进程已退出。"
        exit 0
        ;;

    2)
        echo "📝 更新订阅链接"
        echo "💡 提示：如果只输入一个链接，它将被复制到所有三个位置。"

        read -p "请输入 订阅1 链接: " url1
        read -p "请输入 订阅2 链接 (可留空): " url2
        read -p "请输入 订阅3 链接 (可留空): " url3

        final_url1="${url1}"
        final_url2="${url2:-${url1}}"
        final_url3="${url3:-${url1}}"

        if [[ -z "$final_url1" ]]; then
            echo "❌ 错误：你没有输入任何链接！"
            exit 1
        fi

        # 备份（统一日期格式，跨平台兼容）
        backup_name="${CONFIG_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$backup_name"
        echo "📄 已备份原配置文件 → $backup_name"

        # 转义替换文本中的特殊字符（用于 sed 分隔符 |）
        # 需要转义的：\、&、|
        esc_url1=$(printf '%s' "$final_url1" | sed 's/[\\&|]/\\&/g')
        esc_url2=$(printf '%s' "$final_url2" | sed 's/[\\&|]/\\&/g')
        esc_url3=$(printf '%s' "$final_url3" | sed 's/[\\&|]/\\&/g')

        # 使用 | 作为 sed 分隔符，避免 URL 中的 / 冲突
        sed_inplace "s|${PLACEHOLDER}|${esc_url1}|1" "$CONFIG_FILE"
        sed_inplace "s|${PLACEHOLDER}|${esc_url2}|1" "$CONFIG_FILE"
        sed_inplace "s|${PLACEHOLDER}|${esc_url3}|1" "$CONFIG_FILE"

        echo "✅ 成功！配置文件已更新。"
        echo "   订阅1: $(mask_url "$final_url1")"
        echo "   订阅2: $(mask_url "$final_url2")"
        echo "   订阅3: $(mask_url "$final_url3")"
        ;;

    3)
        echo "🔧 自动修复：清除缓存文件..."

        if [[ -f "cache.db" ]]; then
            rm -f "cache.db"
            echo "   ✅ 已删除 cache.db"
        else
            echo "   ℹ️  cache.db 不存在，跳过"
        fi

        if [[ -d "run" ]]; then
            rm -rf "run"
            echo "   ✅ 已删除 run 目录"
        else
            echo "   ℹ️  run 目录不存在，跳过"
        fi

        echo "✅ 缓存清理完成！"
        ;;

    4)
        echo "🔄 重置配置：从备份恢复..."

        # 查找最新的备份文件
        latest_backup=$(ls -t ${CONFIG_FILE}.backup_* 2>/dev/null | head -n 1)

        if [[ -z "$latest_backup" ]]; then
            echo "❌ 错误：未找到任何备份文件！"
            echo "   备份文件格式：config.json.backup_YYYYMMDD_HHMMSS"
            exit 1
        fi

        echo "   找到最新备份: $latest_backup"
        read -p "确定要恢复此备份吗？(y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0

        cp "$latest_backup" "$CONFIG_FILE"
        echo "✅ 配置已恢复自 $latest_backup"
        ;;

    *)
        echo "❌ 无效选择，请输入 1-4。"
        exit 1
        ;;
esac
