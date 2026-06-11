#!/bin/bash
# Claude Code 通知脚本
# 支持 macOS 系统通知和 ntfy.sh 推送

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/notify.log"
ENV_FILE="$SCRIPT_DIR/.env"

echo "$(date '+%Y-%m-%d %H:%M:%S') Hook triggered, args: $*" >> "$LOG_FILE"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# 通知方式配置（macos/ntfy/both）
NOTIFY_METHOD="${NOTIFY_METHOD:-macos}"

NTFY_TOPIC="${NTFY_TOPIC:-claude-notify-3d2f}"
NTFY_URL="${NTFY_URL:-https://ntfy.sh}"

TYPE="${1:-done}"
MESSAGE="${2:-}"

# macOS 原生通知（60 秒后自动消失）
NOTIFY_GROUP="claude-code-notify"
NOTIFY_ICON="$SCRIPT_DIR/claude-logo.png"
send_macos_notification() {
    local TITLE="$1"
    local SUBTITLE="$2"
    local MSG="$3"

    # 发送通知（使用 Claude app icon）
    terminal-notifier \
        -title "$TITLE" \
        -subtitle "$SUBTITLE" \
        -message "$MSG" \
        -sound "Glass" \
        -group "$NOTIFY_GROUP" \
        -sender "com.claude.notifier" \
        2>/dev/null

    # 60 秒后自动移除
    (sleep 60 && terminal-notifier -remove "$NOTIFY_GROUP" 2>/dev/null) &

    echo "$(date '+%Y-%m-%d %H:%M:%S') macOS notification sent: $TITLE - $MSG" >> "$LOG_FILE"
}

# ntfy.sh 推送通知
send_ntfy_notification() {
    local TITLE="$1"
    local PRIORITY="$2"
    local TAGS="$3"
    local MSG="$4"

    echo "$(date '+%Y-%m-%d %H:%M:%S') Sending ntfy: title=$TITLE priority=$PRIORITY msg=$MSG" >> "$LOG_FILE"

    curl -s \
        -H "Title: $TITLE" \
        -H "Priority: $PRIORITY" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "$NTFY_URL/$NTFY_TOPIC"
}

# 统一通知接口
send_notification() {
    local TITLE="$1"
    local SUBTITLE="$2"
    local MSG="$3"
    local PRIORITY="${4:-4}"
    local TAGS="${5:-}"

    case "$NOTIFY_METHOD" in
        macos)
            send_macos_notification "$TITLE" "$SUBTITLE" "$MSG"
            ;;
        ntfy)
            send_ntfy_notification "$TITLE" "$PRIORITY" "$TAGS" "$MSG"
            ;;
        both)
            send_macos_notification "$TITLE" "$SUBTITLE" "$MSG"
            send_ntfy_notification "$TITLE" "$PRIORITY" "$TAGS" "$MSG"
            ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') Unknown NOTIFY_METHOD: $NOTIFY_METHOD" >> "$LOG_FILE"
            send_macos_notification "$TITLE" "$SUBTITLE" "$MSG"
            ;;
    esac
}

# 直接指定类型
if [ "$TYPE" = "done" ]; then
    send_notification "Claude Code" "✅ 任务完成" "${MESSAGE:-任务处理完毕}" "4" "white_check_mark"
    exit 0
fi

if [ "$TYPE" = "confirm" ]; then
    send_notification "Claude Code" "⚠️ 需要确认" "${MESSAGE:-请查看}" "5" "warning"
    exit 0
fi

# Stop 事件：读取 stdin
INPUT=$(cat 2>/dev/null)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)

echo "$(date '+%Y-%m-%d %H:%M:%S') stop_hook_active=$STOP_HOOK_ACTIVE last_msg=${LAST_MSG:0:100}" >> "$LOG_FILE"

# stop_hook_active=true 表示 Claude 被阻塞（需要权限/确认）
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    send_notification "Claude Code" "⚠️ 需要确认" "Claude 需要你处理" "5" "warning"
    exit 0
fi

# 检查最后消息是否包含问号（Claude 在提问）
if echo "$LAST_MSG" | grep -qE '\？|\?'; then
    send_notification "Claude Code" "💬 需要回复" "$LAST_MSG" "4" "speech_balloon"
    exit 0
fi

# 默认：任务完成
send_notification "Claude Code" "✅ 任务完成" "任务处理完毕" "4" "white_check_mark"
