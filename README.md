# Claude Tools

Claude Code 实用工具集。

## 工具

### [通知](notify/) (notify)

Claude 完成任务或需要确认时，发送系统通知提醒。

- macOS 原生通知（默认，推荐）
- 小米手环通知（通过 ntfy relay）

### [状态栏](statusline/)

多行彩色状态栏，显示模型信息、上下文用量、Skill 调用历史。

```
Model: Sonnet 4.6 [high] | Context: ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 21% 1h15m
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
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/claude-tools/notify/notify.sh stop"
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
- osascript（macOS 通知）
- curl（ntfy 通知）

## 相关文档

- [小米手环通知配置](docs/SETUP-NTFY.md)
- [手环通知调研报告](docs/RESEARCH.md)

## License

MIT
