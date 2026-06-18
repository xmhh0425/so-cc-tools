# SO CC Tools

Claude Code 实用工具集。

## 工具

### [通知](ClaudeNotify/) (notify + ClaudeNotify)

Claude Code 任务完成、等待输入、API 错误时发送桌面通知。

`notify/notify-claude-notify.sh` 作为 hook 适配层，将事件通过 HTTP 转发到 [ClaudeNotify](ClaudeNotify/) 菜单栏 app，由 app 显示浮窗通知并记录通知历史。另有 `notify/notify-osc.sh` 通过 OSC 777 终端转义序列通知，适用于 Warp/Ghostty 等终端。

### [状态栏](statusline/) (statusline)

多行彩色状态栏，显示模型信息、上下文用量、Skill 调用历史。

```
Model: Sonnet 4.6 [high] | Context: ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 21% Session: 52m
Latest: C:chrome-connect
Skills: C:deep-research > U:brainstorming > C:chrome-connect
```

## 安装

```bash
git clone https://github.com/xmhh0425/so-cc-tools.git ~/AI/so-cc-tools
```

在 `~/.claude/settings.json` 中配置：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/AI/so-cc-tools/statusline/statusline.sh",
    "refreshInterval": 5
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/so-cc-tools/notify/notify-claude-notify.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/so-cc-tools/notify/notify-claude-notify.sh"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/AI/so-cc-tools/notify/notify-claude-notify.sh"
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
~/AI/so-cc-tools/fix-settings.sh
```

脚本读取当前配置、合并回 `statusLine` 与 `hooks`（通知走 `notify-claude-notify.sh` → ClaudeNotify app），再原子写回。特性：

- **幂等**：可重复执行，按脚本文件名去重，不产生重复 hook
- **非破坏**：保留其他工具/事件的 hook 与其余字段；写前生成 `.bak` 备份
- **自定位**：从脚本自身位置推导仓库路径

修复后若当前会话未立即生效，重开一个会话即可。

## 依赖

- bash、jq（必需）
- [ClaudeNotify](ClaudeNotify/) macOS app（推荐，需要 macOS 14.0+）
- Warp/Ghostty 等终端（仅 `notify-osc.sh` 需要 OSC 777 支持）

## License

MIT
