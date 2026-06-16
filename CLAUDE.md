# CLAUDE.md

## 项目概述

Claude Code 实用工具集，三个组件：
- `notify/` — 桌面通知脚本（OSC 777 / HTTP 桥接）
- `statusline/` — 多行彩色状态栏脚本
- `ClaudeNotify/` — macOS 菜单栏通知 app（SwiftUI）

## 构建与运行

```bash
# ClaudeNotify macOS app — Xcode 构建，零外部依赖，目标 macOS 14.0+
open ClaudeNotify/ClaudeNotify.xcodeproj
# ⌘R 运行

# Shell 脚本依赖：bash、jq
```

无测试套件，无 linter 配置。

## 架构要点

ClaudeNotify 数据流：Claude Code → HTTP POST `localhost:18765` → `HTTPServer`（Network.framework，自实现 HTTP 解析）→ `AppCoordinator` 分发到浮窗通知 / 系统通知 / 历史记录。

Hook 事件类型：`Stop`（任务完成）、`Notification`（等待输入）、`StopFailure`（API 错误）。

菜单栏下拉面板是 `NSPanel`（不是 `NSPopover`），通过 `StatusBarController` 管理。

## 代码风格

- **所有 UI 字符串使用中文**（"任务完成"、"需要输入"、"设置"、"退出"等）
- Swift 使用 `@Observable` 宏（不用 Combine），日志用 `os.log.Logger`
- Bash 脚本统一 `set -euo pipefail`，从 stdin 读 JSON，用 `jq` 提取字段
- Git 提交信息使用中文

## 工作流

修改 `~/.claude/settings.json` 时，`hooks` 字段必须与现有配置合并，不能覆盖其他 hook。

状态栏 skill 日志共享 `/tmp/cc-skills.log`（`hook-pre-skill.sh` 和 `hook-skill-tracker.sh` 都写入此文件）。

## 常见坑

- `FloatingNotificationManager` 用全局鼠标追踪（60fps timer + event monitor）实现关闭按钮交互，修改浮窗行为时需注意此机制
- `HTTPServer` 是手写 HTTP 解析（`HTTPParser`），不是 URLSession — 改网络层时注意
- `HookPayload` 所有字段都是 optional，解码时用 lenient 方式处理
- 状态栏脚本通过 `ANTHROPIC_DEFAULT_*_MODEL_NAME` 环境变量支持 CC Switch 代理名称解析
