# 手机端配置指南（仅 ntfy 通知方式）

> **注意**：如果你使用 macOS 通知（默认配置），则无需此配置。

## 第一步：安装 ntfy App

1. 打开小米手机的应用商店，搜索 **ntfy**，或从 F-Droid/Google Play 下载
2. 安装后打开 App
3. 点击 **Add Topic**（添加主题）
4. 输入 topic 名称：`claude-notify-3d2f`（与 `.env` 中的 `NTFY_TOPIC` 一致）
5. 点击订阅

## 第二步：验证通知链路

在开发机终端运行：

```bash
bash ~/AI/claude-notify/notify.sh done '测试通知'
```

手机 ntfy App 应该收到通知，手环应同步显示。

## 第三步：确认 Mi Fitness App 通知转发

1. 打开手机 **设置 → 应用管理 → Mi Fitness（小米运动健康）**
2. 确认已开启**通知读取权限**（允许读取其他 App 通知）
3. 确认手环已连接（蓝牙已配对）
4. Mi Fitness App 内检查手环设置 → 通知同步已开启

## 自定义配置

编辑项目根目录的 `.env` 文件：

```bash
# 启用 ntfy 通知（或同时使用两种方式）
NOTIFY_METHOD=ntfy

# 修改 topic 名称（改完后手机端也要重新订阅）
NTFY_TOPIC=你的自定义名称
```

## 注意事项

- 手机需保持蓝牙开启，且在手环 BLE 范围内（~10 米）
- Mi Fitness App 会同步**所有**通知到手环，包括微信、短信等
- 如果通知太多想过滤，后续可换成 Gadgetbridge（开源，支持按 App 过滤）
- ntfy.sh 免费托管的 topic 名是唯一安全机制，不要用容易猜到的名字
