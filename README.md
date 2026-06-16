# Claude Tools

Claude Code 实用工具集。

## 工具

### [通知](notify/) (notify)

Claude 完成任务或需要确认时，通过 Warp OSC 777 发送桌面通知。

零依赖：不需要 terminal-notifier、不需要自定义 app，由 Warp 原生处理。

### [状态栏](statusline/)

多行彩色状态栏，显示模型信息、上下文用量、Skill 调用历史。

```
Model: Sonnet 4.6 [high] | Context: ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 21% Session: 52m
Latest: C:chrome-connect
Skills: C:deep-research > U:brainstorming > C:chrome-connect
```

## 安装

```bash
git clone https://github.com/xmhh0425/claude-tools.git ~/AI/claude-tools
```

在 `~/.claude/settings.json` 中配置：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/AI/claude-tools/statusline/statusline.sh",
    "refreshInterval": 5
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/claude-tools/statusline/hook-pre-skill.sh"
          }
        ]
      }
    ],
    "UserPromptExpansion": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/claude-tools/statusline/hook-skill-tracker.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/claude-tools/notify/notify-osc.sh"
          }
        ]
      }
    ]
  }
}
```

> `hooks` 字段需与现有配置合并，不能覆盖。

## 配置被覆盖时的一键修复

CC Switch 等代理切换工具会重写 `~/.claude/settings.json`，丢弃它不认识的 `statusLine` / `hooks` 字段，导致状态栏和通知失效。此时运行：

```bash
~/AI/claude-tools/fix-settings.sh
```

脚本读取当前配置、合并回 `statusLine` 与 `hooks`（通知走 `notify-claude-notify.sh` → ClaudeNotify app），再原子写回。特性：

- **幂等**：可重复执行，按脚本文件名去重，不产生重复 hook
- **非破坏**：保留其他工具/事件的 hook 与其余字段；写前生成 `.bak` 备份
- **自定位**：从脚本自身位置推导仓库路径

修复后若当前会话未立即生效，重开一个会话即可。

## 依赖

- bash、jq（必需）
- Warp 终端（通知功能需要 OSC 777 支持）

## License

MIT
