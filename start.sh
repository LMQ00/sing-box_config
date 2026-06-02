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

# --- 信号处理：优雅退出 ---
cleanup() {
    echo ""
    echo "🛑 正在停止 sing-box..."
    if [[ -n "${SING_BOX_PID:-}" ]]; then
        sudo kill "$SING_BOX_PID" 2>/dev/null
        wait "$SING_BOX_PID" 2>/dev/null
    fi
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

# ===================== 自动部署 sing-box 核心 =====================
if [[ -d "$BIN_DIR" ]]; then
    echo "📁 检测到 ./bin 目录，正在自动部署 sing-box 核心..."

    OS=""
    ARCH=""
    case "$OSTYPE" in
        linux-gnu*) OS="linux" ;;
        darwin*)    OS="darwin" ;;
        *)
            echo "⚠️  警告：无法识别的操作系统 ($OSTYPE)，跳过自动部署。"
            OS="unknown" ;;
    esac

    MACHINE_TYPE=$(uname -m)
    case "$MACHINE_TYPE" in
        x86_64)               ARCH="amd64" ;;
        aarch64|arm64|armv8*) ARCH="arm64" ;;
        *)
            echo "⚠️  警告：无法识别的架构 ($MACHINE_TYPE)，跳过自动部署。"
            ARCH="unknown" ;;
    esac

    if [[ "$OS" != "unknown" ]] && [[ "$ARCH" != "unknown" ]]; then
        SOURCE_PATH="$BIN_DIR/$OS-$ARCH/sing-box"
        if [[ -f "$SOURCE_PATH" ]]; then
            echo "📦 正在从 $SOURCE_PATH 部署..."
            install -m 755 "$SOURCE_PATH" "$TARGET_BINARY" && \
                echo "✅ sing-box ($OS-$ARCH) 部署成功！" || \
                echo "❌ 错误：复制文件失败。"
        else
            echo "❌ 错误：在 $BIN_DIR 中未找到 $OS-$ARCH/sing-box 文件。"
            echo "    请检查文件夹内是否有拼写错误。"
        fi
    fi
else
    echo "ℹ️  ./bin 目录不存在，使用现有根目录下的 sing-box 文件。"
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
echo "=================================="
read -p "请选择操作 (1 或 2): " choice

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

    *)
        echo "❌ 无效选择，请输入 1 或 2。"
        exit 1
        ;;
esac
