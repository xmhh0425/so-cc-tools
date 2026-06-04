# 小米手环通知配置指南

> **前提**：此配置仅在使用 ntfy 通知方式时需要。默认的 macOS 通知无需任何额外配置。

## 工作原理

```
Claude Code → ntfy.sh (HTTP) → Android 手机 ntfy App → Mi Fitness → 小米手环
```

**硬件要求**：
- 小米手环（Mi Band 8/9/10）
- Android 手机（需在手环 BLE 范围内，约 10 米）

## 配置步骤

### 1. 自定义 ntfy topic

编辑 `notify/.env`，将 `NTFY_TOPIC` 改为你自己定义的名称（越随机越好）：

```bash
NOTIFY_METHOD=ntfy   # 或 both（同时使用 macOS 通知）
NTFY_TOPIC=你的自定义topic名称
NTFY_URL=https://ntfy.sh
```

> ⚠️ ntfy.sh 免费托管的 topic 名是唯一安全机制，不要用容易猜到的名字。

### 2. 手机安装 ntfy App

从以下任一渠道安装：
- [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- [F-Droid](https://f-droid.org/en/packages/io.heckel.ntfy/)
- [GitHub APK](https://github.com/binwiederhier/ntfy-android/releases)

打开 App → Add Topic → 输入你在 `.env` 中设置的 topic 名称 → 订阅。

### 3. 小米手机必做：设置 ntfy 后台保活

1. 设置 → 应用管理 → ntfy → 自启动 → 开启
2. 设置 → 应用管理 → ntfy → 省电策略 → 无限制
3. 最近任务里把 ntfy 锁定（点锁头图标）

### 4. 配置 Mi Fitness 通知转发

1. 打开手机 **设置 → 应用管理 → Mi Fitness（小米运动健康）**
2. 确认已开启**通知读取权限**（允许读取其他 App 通知）
3. 确认手环已连接（蓝牙已配对）
4. Mi Fitness App 内检查手环设置 → 通知同步已开启

### 5. 验证

在开发机终端运行：

```bash
bash ~/AI/claude-tools/notify/notify.sh done '测试通知'
```

手机 ntfy App 应收到通知，手环应同步显示。

## 注意事项

- 手机需保持蓝牙开启，且在手环 BLE 范围内（~10 米）
- Mi Fitness App 会同步**所有**通知到手环，如需按 App 过滤可换成 [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)（开源）
- 如需更高的安全性或隐私控制，可考虑[自托管 ntfy](https://docs.ntfy.sh/install/)
