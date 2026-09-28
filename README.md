# VibeWrite

VibeWrite 是一款 macOS 原生 AI 写作应用。SwiftUI 客户端负责编辑正文、管理本地写作项目和修订历史；Swift/Vapor 后端提供写作 AI 网关与管理页面。

## 构建

需要 macOS 14 或更新版本，以及完整的 Xcode。仓库根目录是客户端 Swift Package，`Backend/` 是独立的服务端 Package。

```bash
swift build
swift build --package-path Backend
```

本地启动后端前，将 [`Backend/.env.local.example`](Backend/.env.local.example) 复制为 `Backend/.env.local`，自行设置管理员密码和加密密钥。`scripts/backend_up.sh` 会构建后端、停止已有的本地 VibeWrite 后端进程，然后启动新的服务。客户端也可使用 Xcode 打开 `VibeWrite.xcodeproj`。

当前架构与状态见 [项目上下文](PROJECT_CONTEXT.md)。

## 许可

应用代码和 `Resources/` 中的自制应用图标采用 [MIT 许可证](LICENSE)。第三方依赖遵循各自的许可证。
