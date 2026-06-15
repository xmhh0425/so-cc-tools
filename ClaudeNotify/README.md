# ClaudeNotify

A macOS menu bar app that receives real-time notifications from [Claude Code](https://claude.ai/code) via HTTP hooks — no system notification dependency.

## Features

- **Floating notification banners** on all connected displays, auto-dismiss after 60s
- **Event types**: Task Complete (green), Needs Input (orange), API Error (red)
- **Stacked notifications** — new ones appear at the top, old ones push down
- **Notification history** in the menu bar dropdown
- **One-click hook setup** — installs HTTP hooks into `~/.claude/settings.json`

## Requirements

- macOS 14.0+ (Sonoma)
- [Claude Code](https://claude.ai/code) CLI

## Install

### From source (Xcode)

```bash
git clone https://github.com/anthropics/claude-notify.git
cd claude-notify
open ClaudeNotify.xcodeproj
# Build & Run (⌘R)
```

### Configure hooks

Open ClaudeNotify, click the bell icon in the menu bar → **Setup Hooks** → **Install All**.

Or manually add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:18765/hook/stop" }] }
    ],
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:18765/hook/notification" }] }
    ],
    "StopFailure": [
      { "matcher": "", "hooks": [{ "type": "http", "url": "http://127.0.0.1:18765/hook/stopfailure" }] }
    ]
  }
}
```

## Architecture

```
Claude Code events
  ↓ HTTP POST (native type: "http" hook)
App NWListener on :18765
  ├→ FloatingNotificationManager  (custom banners on all screens)
  ├→ NotificationManager          (system notification fallback)
  └→ HistoryStore                 (JSON persistence)
```

**Zero external dependencies** — pure Foundation + SwiftUI + Network.framework.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 18765 | HTTP server port |
| Floating Banner | ON | Custom floating notification |
| System Notification | OFF | macOS native notification |
| Sound | ON | Play sound on notification |
| Launch at Login | OFF | Auto-start on boot |

## License

MIT
