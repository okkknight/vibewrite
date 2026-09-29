# VibeWrite

VibeWrite 是一款以正文为中心的 macOS 写作协作器。你用一句写作 brief 启动第一段，接着在已有正文上续写，或者选中一个局部直接说想怎么改；AI 回来的是能接进当前文本的内容，而不是让你把整篇稿子反复搬进聊天窗口。

它的核心是“持续导演”一篇文本：先起稿，再用自然语言把下一段往前推，或者对选区做局部 patch。你始终可以自己直接编辑，AI 修订也有版本记录，觉得不对就退回去。

文稿保留为本地 Markdown 文件，离线时仍是一台普通而安静的文本编辑器。联网后，后端只负责 AI 请求、密钥、限额和监控，正文不进入后端数据库。

## 能做什么

- 从一句写作 brief 开始，起草第一版正文。
- 沿着已有内容续写，或把选中的一段改到更像你想说的话。
- 把 Markdown 文稿留在本地，同时保留 AI 修订历史。
- 用原生撤销/重做，也能单独回退或恢复一次 AI 修改。

客户端负责编辑和本地文件；后端负责 AI 请求、配额和服务配置。默认通过本机 Codex CLI 生成文本，也可以按配置接入 MiniMax。

## 本地启动

需要 macOS 14 或更新版本、完整 Xcode，以及已登录的 Codex CLI。客户端和后端是两个 Swift Package：

```bash
swift build
swift build --package-path Backend
```

后端首次启动前，复制配置模板并填写本机值：

```bash
cp Backend/.env.local.example Backend/.env.local
```

至少设置 `ADMIN_SECRET_ENCRYPTION_KEY`、`ADMIN_USERNAME` 和 `ADMIN_PASSWORD`。默认配置使用 SQLite 与 Codex CLI；密钥、密码和本地数据库都不应提交到仓库。然后启动后端：

```bash
./scripts/backend_up.sh
```

它会在 `http://127.0.0.1:8080` 启动服务。客户端可用 Xcode 打开 `VibeWrite.xcodeproj`，也可以从构建产物运行。`scripts/backend_up.sh` 会结束已有的本地 VibeWrite 后端进程后再启动新的实例。

## 文件和数据

正文是你的本地 Markdown 文件。VibeWrite 会放入一个隐藏标记来关联协作状态；项目摘要、AI 对话和修订历史保存在应用自己的元数据里，后端数据库只保存设备、请求、配额、管理会话和服务配置。

所以文稿可以独立备份和迁移，服务端也不是它唯一的家。当前架构、已完成工作和待解决问题见 [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md)。

## 开发

```bash
swift test
swift test --package-path Backend
```

客户端源码在 [`Sources/VibeWriteApp/`](Sources/VibeWriteApp/)，共享协议在 [`Sources/VibeWriteShared/`](Sources/VibeWriteShared/)，Vapor 后端在 [`Backend/`](Backend/)。

## 许可

应用代码和 `Resources/` 中的自制应用图标采用 [MIT 许可证](LICENSE)。第三方依赖遵循各自的许可证。
