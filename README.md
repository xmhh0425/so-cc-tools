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

## 依赖

- bash、jq（必需）
- Warp 终端（通知功能需要 OSC 777 支持）

## License

MIT
