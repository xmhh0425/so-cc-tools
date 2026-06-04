# Claude Code → 小米手环通知：调研报告

> 调研日期：2026-06-02  
> 调研方式：Deep Research Workflow（104 个子任务，22 个信息源，30 条事实陈述三轮对抗验证）

---

## 核心结论

**小米手环没有官方 SDK，没有第三方 App 开发平台，Zepp OS 不支持小米手环。** 唯一可行路径是间接通知中转：

```
Claude Code → ntfy (HTTP) → Android 手机通知 → Gadgetbridge/Mi Fitness → 手环 BLE
```

---

## 一、为什么不能直接开发

| 路径 | 结论 | 置信度 |
|------|------|--------|
| **小米手环官方 SDK** | 不存在。小米没有公开任何手环开发接口 | 高 |
| **Zepp OS Mini Program** | 只支持 Amazfit 手表，不支持小米手环 | 高 |
| **PC 直连手环 BLE** | 需要小米云认证，没有可靠的本地直连路径 | 中 |

**依据：** Zepp OS 支持设备列表（docs.zepp.com）仅包含 Amazfit 品牌设备；小米手环在 Zepp OS 和非 Zepp OS 分类中均缺失。小米未提供任何公开 SDK 或开发者文档。Zepp OS Mini Program 在架构上仅限于 Amazfit 硬件。

---

## 二、推荐方案：两跳中转

### 第一跳：Claude Code → ntfy

- **ntfy** 是 HTTP 发布/订阅通知服务，POST 一条 curl 即可推送
- Claude Code 的 hook 可以在任务完成/等待输入时自动触发
- 示例：`curl -d "PR #42 审查完成" ntfy.sh/my-claude-topic`
- 支持优先级（1-5）、操作按钮、标签
- 可自托管，也可用免费托管服务（GitHub 30k+ star，Apache-2.0）

**置信度：** 高

### 第二跳：ntfy → 手机通知 → 手环

- Android 手机安装 **ntfy App**（接收通知为系统通知）
- 安装 **Gadgetbridge**（开源）或用原生 **Mi Fitness App**
- Gadgetbridge 通过 BLE 将手机通知同步到手环，支持 Mi Band 1-10，有按 App 过滤能力
- 手机需在 BLE 范围内（约 10 米）

**置信度：** 高

---

## 三、工具链

| 组件 | 作用 | 地址 |
|------|------|------|
| **ntfy** | HTTP → Android 系统通知 | https://ntfy.sh |
| **Gadgetbridge** | Android 通知 → 手环 BLE 同步 | https://codeberg.org/Freeyourgadget/Gadgetbridge |
| **Claude Code hooks** | 任务事件触发 shell 命令 | settings.json 配置 |

### ntfy 详情

- HTTP PUT/POST 发布，topic 即密码模型
- Android 客户端：Google Play + F-Droid
- 优先级 1-5，不同级别有不同振动/声音模式
- 支持操作按钮、标签/emoji、附件
- 自托管实例支持 ACL 认证

### Gadgetbridge 详情

- 开源 Android App（5.0+）
- 使用 BLE GATT 通信（UUID FF03 通知，FF05 控制）
- Mi Band 1-10 全支持（7-10 标记为"Highly supported"）
- 屏幕关闭时自动转发通知
- 支持按 App 过滤通知

### Mi Band BLE 协议补充

- Mi Band 2-6 共享 Huami 协议（相同 UUID 和字节序列）
- Mi Band 7+ 协议有变化，公开文档不完整
- 无可靠的 PC 到手环直连路径（需小米云认证）

---

## 四、注意事项

1. **需要 Android 手机**：Gadgetbridge 只支持 Android，这是硬性依赖
2. **ntfy topic 安全性**：免费托管的 ntfy.sh 上 topic 名是唯一安全机制，涉及敏感信息时建议自托管
3. **端到端延迟未知**：HTTP → 手机 → 手环的延迟未经实测，目标 < 5 秒
4. **Claude Code hook 细节待确认**：hook 的具体事件名和配置方式需实测
5. **Mi Fitness App 也可用**：如果没有按 App 过滤的需求，可以不装 Gadgetbridge，用原生 App 即可

---

## 五、待解决问题

1. ntfy → Android 通知 → Gadgetbridge → 手环的端到端延迟是多少？是否 < 5 秒？
2. Claude Code hooks 的 settings.json 中可以配置哪些事件（任务完成、等待输入等）？
3. Mi Fitness App 的通知同步是否有按 App 过滤能力，还是必须用 Gadgetbridge？
4. Mi Band 7+ 上 Gadgetbridge 的通知转发能力是否有降级？

---

## 六、用户环境

- 小米手环默认连接小米手机
- 手机和手环通常在开发机旁边
- Android 手机作为中转的物理条件已满足

---

## 参考来源

| 来源 | 质量 | 内容 |
|------|------|------|
| https://docs.zepp.com/docs/guides/start/quick-start/ | primary | Zepp OS 设备支持列表 |
| https://docs.zepp.com/docs/reference/related-resources/device-list/ | primary | Zepp OS 兼容设备 |
| https://codeberg.org/Freeyourgadget/Gadgetbridge | primary | Gadgetbridge 源码与文档 |
| https://gadgetbridge.org/gadgets/wearables/xiaomi/ | primary | 小米设备支持状态 |
| https://ntfy.sh | primary | ntfy 官方文档 |
| https://ntfy.sh/docs/publish/ | primary | ntfy 发布 API |
| https://github.com/satcar77/miband4 | secondary | Mi Band 4 BLE 协议逆向 |
