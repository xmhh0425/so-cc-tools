#!/usr/bin/env bash
# 修复 ~/.claude/settings.json：把 statusLine 与 hooks 合并回去。
#
# 场景：CC Switch 等代理切换工具会重写 ~/.claude/settings.json，
#       丢弃它不认识的 statusLine / hooks 字段，导致状态栏和通知失效。
#       本脚本读取当前配置 → 合并回所需字段 → 原子写回。
#
# 特性：
#   - 幂等：可重复执行，不产生重复 hook（按脚本文件名去重）
#   - 非破坏：保留其他工具/事件的 hook；合并前后都校验 JSON
#   - 安全：写入前生成 .bak 备份，临时文件 + 原子 mv 替换
#   - 自定位：从脚本自身位置推导仓库路径，移动仓库后仍可用
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"

# 脚本所在目录即 so-cc-tools 仓库根目录（本脚本放在仓库根目录）
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

NOTIFY="bash $REPO_DIR/notify/notify-cc-tools.sh"
STATUSLINE="bash $REPO_DIR/statusline/statusline.sh"
PRESKILL="bash $REPO_DIR/statusline/hook-pre-skill.sh"
TRACKER="bash $REPO_DIR/statusline/hook-skill-tracker.sh"

command -v jq >/dev/null 2>&1 || { echo "❌ 需要 jq：brew install jq" >&2; exit 1; }

# 文件不存在则以空对象起步
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# 当前内容必须是合法 JSON，否则中止（不覆盖可能损坏的文件）
if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  echo "❌ $SETTINGS 不是合法 JSON，已中止。请先手动检查。" >&2
  exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

jq \
  --arg sl "$STATUSLINE" \
  --arg notify "$NOTIFY" \
  --arg preskill "$PRESKILL" \
  --arg tracker "$TRACKER" '
  # 确保某事件下存在我们的 hook：
  #   先按脚本文件名($id)删掉我们旧的同名条目（兼容 ~/ 与绝对路径两种写法），
  #   保留其他工具的 hook，再追加一条规范条目。
  def ensure($event; $matcher; $command; $id):
    .hooks = (.hooks // {})
    | .hooks[$event] = (
        (.hooks[$event] // [])
        | map(select(((.hooks // []) | map(.command) | join(" ")) | test($id) | not))
        + [{matcher: $matcher, hooks: [{type: "command", command: $command}]}]
      );
  .statusLine = {type: "command", command: $sl, refreshInterval: 5}
  | ensure("Stop";                ""     ; $notify  ; "notify-cc-tools.sh")
  | ensure("Notification";        ""     ; $notify  ; "notify-cc-tools.sh")
  | ensure("StopFailure";         ""     ; $notify  ; "notify-cc-tools.sh")
  | ensure("PreToolUse";          "Skill"; $preskill; "hook-pre-skill.sh")
  | ensure("UserPromptExpansion"; ".*"   ; $tracker ; "hook-skill-tracker.sh")
' "$SETTINGS" > "$TMP"

# 校验合并结果，再备份并原子替换
if ! jq empty "$TMP" >/dev/null 2>&1; then
  echo "❌ 合并结果非法 JSON，已中止，原文件未改动。" >&2
  exit 1
fi

cp "$SETTINGS" "$SETTINGS.bak"
mv "$TMP" "$SETTINGS"
trap - EXIT

echo "✅ 已修复：$SETTINGS"
echo "   备份：    $SETTINGS.bak"
echo "   已写入：  statusLine + hooks(Stop/Notification/StopFailure/PreToolUse/UserPromptExpansion)"
echo "   提示：    若当前会话未立即生效，重开一个 Claude Code 会话即可。"
