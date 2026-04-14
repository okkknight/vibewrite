# VibeWrite Migration 3.0

## 1. 迁移目标

把现在的 V2 单体客户端，迁移成：

- 保留本地编辑器能力的前端
- 承载 AI system prompt 配置 / 密钥 / 限额 / 日志的后端
- 一个给单人使用的简单后台

---

## 2. 迁移原则

- 不做云文档
- 不做账号体系
- 不丢离线编辑
- 不把正文搬到后端
- 不做多模型平台
- 不做 AI system prompt 多版本

---

## 3. 现有代码的迁移映射

### 3.1 留在前端的代码

- `Sources/VibeWriteApp/App/VibeWriteApp.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift` 中的 UI 状态与本地文件逻辑
- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectComposerBar.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectAISidebarView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectHistoryDrawerView.swift`
- `Sources/VibeWriteApp/Shared/Views/SelectableTextEditor.swift`
- `Sources/VibeWriteApp/Shared/Documents/VibeWriteMarkdownDocument.swift`
- `Sources/VibeWriteApp/Shared/Documents/VibeWriteDocumentMetadataStore.swift`
- `Sources/VibeWriteApp/App/LocalProjectStore.swift`
- `Sources/VibeWriteApp/App/RecentDocumentStore.swift`

### 3.2 迁移到后端的代码

- `Sources/VibeWriteApp/Shared/AI/WritingAIConfiguration.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIPromptBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/RemoteWritingAIClient.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingProjectResponseBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIModels.swift` 中与 provider 调用、响应解析、后端拼装相关的职责
- `Sources/VibeWriteApp/Shared/Models/WritingPatchModels.swift` 中的 AI 结果组装职责

### 3.3 保留为共享 DTO 的代码

以下模型拆成共享协议层，但不再包含 provider 实现：

- `WritingAIRequest`
- `WritingAIResponse`
- `WritingAICompletionMetadata`
- `WritingAIStreamEvent`
- `WritingAIAction`
- `WritingTextSelectionRange`

`Sources/VibeWriteApp/Shared/AI/WritingAIModels.swift` 拆成：

- 一份共享 DTO 文件
- 一份后端专用实现文件

这样客户端和后端都能复用类型，但不会把 provider 逻辑留回客户端。

---

## 4. 迁移步骤

### 第 1 步：冻结现有行为

- 保持 V2 客户端当前可用
- 明确哪些 UI 和本地文件能力不改
- 把 AI 路径重构边界固定下来

### 第 2 步：抽出共享协议

- 统一请求 / 返回 DTO
- 定义后端流式事件
- 定义错误码

### 第 3 步：做后端 AI 网关

- 用后端替代客户端直连模型
- 复用当前 startDraft / continueWriting / edit 语义
- 保持流式输出体验
- 客户端改为携带 `installationId` 和 `deviceToken`

### 第 4 步：接设备限额

- 引入 `installationId`
- 引入 `deviceToken`
- 加日限额和周限额
- 超限直接拒绝

### 第 5 步：做后台管理页

- 简单登录
- 请求查看
- 密钥更新
- AI system prompt 配置更新
- 限额查看和封禁

### 第 6 步：把后端数据层切到 PostgreSQL

- 把 device、quota、request log、secret config、system prompt config、admin session 持久化到 PostgreSQL
- secret config 必须按加密 ciphertext 落库
- 仍然保持现有 API、DTO 和后台页面不变
- 只切生产主实现，不做双写 / 双读过渡

### 第 7 步：清理客户端机密

- 删除本地密钥依赖
- 删除 AI system prompt builder
- 删除 provider 直连
- 保留 `project.prompt` 作为用户写作简述和本地项目元数据

### 第 8 步：清理客户端正常路径残留

- 删除 `WritingAIClientFactory` 的正常运行态默认选择入口
- 删除 `WritingAIConfiguration` 对 `MINIMAX_*` 的正常运行态默认读取
- 删除 `WritingAIPromptBuilder` 和 `RemoteWritingAIClient` 的正常构建依赖
- 将仍需要保留的 provider 语义测试迁到 backend / shared 测试，或者删除已经被 backend gateway 覆盖的重复断言

---

## 5. 迁移时必须保留的兼容点

- 本地 Markdown 文件格式不变
- 本地保存 / 另存为不变
- 离线编辑不变
- 没网时 AI 直接提示网络不可用
- `stub` 测试模式继续可用
- 当前流式正文体验不得明显退化

---

## 6. 迁移时不要误删的东西

- 最近打开列表
- 本地 revision history
- 本地 document identity
- 选区和视口状态
- 现有 UI 的正文优先布局

---

## 7. 验证顺序

1. 先验证本地编辑和保存没有回退
2. 再验证后端 AI 直通
3. 再验证设备限额
4. 再验证后台配置修改
5. 再验证离线提示

---

## 8. 迁移完成的判定

迁移成功的标志是：

- 客户端里看不到 provider key
- 客户端里看不到 AI system prompt 配置设计
- 客户端不直接调模型
- 本地编辑仍然可用
- 后端能控 AI、限额、日志和后台配置
