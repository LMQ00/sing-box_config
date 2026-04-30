#!/bin/bash

cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" || exit 1

CONFIG_FILE="config.json"
PLACEHOLDER="订阅链接"

BIN_DIR="./bin"
TARGET_BINARY="./sing-box"

# 自动部署 sing-box 核心
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

# 前置检查
[[ -f "$CONFIG_FILE" ]] || { echo "❌ 错误：找不到配置文件 $CONFIG_FILE"; exit 1; }
[[ -f "$TARGET_BINARY" ]] || { echo "❌ 错误：找不到 sing-box 核心文件"; exit 1; }

# 确保 sing-box 可执行
chmod +x "$TARGET_BINARY"

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

        mkdir -p ./run
        rm -f ./run/*.log

        sudo "$TARGET_BINARY" run -c "$CONFIG_FILE" -D ./ > ./run/sing-box.log 2>&1 &
        SING_BOX_PID=$!

        # 等待进程启动
        sleep 2
        if ! kill -0 "$SING_BOX_PID" 2>/dev/null; then
            echo "❌ 错误：Sing-box 启动失败，请检查 ./run/sing-box.log 查看详情。"
            wait "$SING_BOX_PID" 2>/dev/null
            exit 1
        fi

        echo "PID: $SING_BOX_PID  |  日志: ./run/sing-box.log"
        echo "⏳ Sing-box 已启动，正在等待 ./dashboard 生成文件..."

        # 等待 dashboard 就绪，最多 60 秒
        for ((i = 0; i < 60; i++)); do
            if ! kill -0 "$SING_BOX_PID" 2>/dev/null; then
                echo "❌ 错误：Sing-box 进程异常退出，请检查 ./run/sing-box.log 查看详情。"
                exit 1
            fi
            if [[ -d "./dashboard" ]] && [[ -n "$(find ./dashboard -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
                echo "✅ 检测到 ./dashboard 中有文件，正在执行节点切换..."
                curl -X PUT "http://127.0.0.1:9090/proxies/国外代理" \
                    -H "Content-Type: application/json" \
                    -d '{"name":"订阅1国外自动"}'
                echo ""
                break
            fi
            sleep 1
        done

        echo "ℹ️  脚本转入守护模式，按 Ctrl+C 退出。"
        wait "$SING_BOX_PID"
        echo "⚠️  Sing-box 进程已退出。"
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

        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
        echo "📄 已备份原配置文件"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s@$PLACEHOLDER@$final_url1@1" "$CONFIG_FILE"
            sed -i '' "s@$PLACEHOLDER@$final_url2@1" "$CONFIG_FILE"
            sed -i '' "s@$PLACEHOLDER@$final_url3@1" "$CONFIG_FILE"
        else
            sed -i "s@$PLACEHOLDER@$final_url1@1" "$CONFIG_FILE"
            sed -i "s@$PLACEHOLDER@$final_url2@1" "$CONFIG_FILE"
            sed -i "s@$PLACEHOLDER@$final_url3@1" "$CONFIG_FILE"
        fi

        echo "✅ 成功！配置文件已更新。"
        echo "   订阅1: $final_url1"
        echo "   订阅2: $final_url2"
        echo "   订阅3: $final_url3"
        ;;

    *)
        echo "❌ 无效选择，请输入 1 或 2。"
        exit 1
        ;;
esac
