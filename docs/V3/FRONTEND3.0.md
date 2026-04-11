# VibeWrite Frontend 3.0

## 1. 前端定位

V3 前端是一个本地优先的写作壳子，不是完整业务客户端。

它要保留的能力只有三类：

- 正文编辑
- 本地文件管理
- 远程 AI 结果的接收和渲染

它不要承担的能力包括：

- AI system prompt 编排
- provider 访问
- 密钥管理
- 限额判定
- 请求审计

---

## 2. 当前客户端里要保留的模块

以下模块必须继续留在前端：

- `Sources/VibeWriteApp/App/VibeWriteApp.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift`
- `Sources/VibeWriteApp/App/LocalProjectStore.swift`
- `Sources/VibeWriteApp/App/RecentDocumentStore.swift`
- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectComposerBar.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectAISidebarView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectHistoryDrawerView.swift`
- `Sources/VibeWriteApp/Shared/Views/SelectableTextEditor.swift`
- `Sources/VibeWriteApp/Shared/Views/ProjectShellChrome.swift`
- `Sources/VibeWriteApp/Shared/Documents/VibeWriteMarkdownDocument.swift`
- `Sources/VibeWriteApp/Shared/Documents/VibeWriteDocumentMetadataStore.swift`

这些模块负责：

- 编辑正文
- 打开 / 保存 / 另存为
- 最近打开记录
- 历史回退
- 侧栏 UI
- composer UI
- 离线编辑

---

## 3. 前端需要改造的点

### 3.1 AI 配置相关

前端不再直接读取：

- `MINIMAX_API_KEY`
- `MINIMAX_BASE_URL`
- `MINIMAX_TEXT_BASE_URL`
- `MINIMAX_MODEL`
- `MINIMAX_METADATA_ROUTE`

这些配置只能存在于后端。

### 3.2 AI system prompt 相关

前端不再持有：

- `WritingAIPromptBuilder`
- 任何 provider 专用 AI system prompt 模板字符串
- metadata 的结构化 AI system prompt 字符串

前端最多只保留：

- 动作类型
- 当前正文快照
- 用户输入
- 选区

前端仍然必须保留 `project.prompt`，因为它是用户写作简述，不是后端 AI system prompt 配置。

### 3.3 provider 调用相关

前端不再直接调用：

- MiniMax
- Anthropic-compatible endpoint
- 任何模型 API

前端改为调用后端 AI 网关。

---

## 4. 前端保留的状态模型

前端仍然需要保留这些本地状态：

- 当前打开文件路径
- 当前正文文本
- 最近打开记录
- 线性 revision history
- 选区状态
- 视口状态
- composer 输入状态
- AI 请求中的 UI 状态
- 离线提示状态

这些状态都属于界面或本地编辑器语义，不属于后端持久化对象。

---

## 5. 前端仍然负责的本地文件流

前端仍然要支持：

1. 新建本地正文
2. 打开本地 Markdown 文件
3. 保存当前文件
4. 另存为
5. 打开最近文件
6. 关闭窗口时走当前 dirty-check

本地文档格式仍然保持 Markdown。

---

## 6. 安装级匿名身份

前端首次启动时生成 `installationId`，并本地持久化。

后端在 `bootstrap` 时返回 `deviceToken`，前端也必须本地持久化这个值。

这个 ID 只用于：

- 发给后端做设备维度限额
- 请求监控
- 请求追踪

`deviceToken` 只用于后端校验设备身份，不代表账号，不承载用户身份。

当前本地项目数据也会继续保存 `project.prompt`、`localSummary`、`globalSynopsis`、`context`、`conversation` 和 `revisionHistory`，它们属于用户内容或本地协作元数据，不是后端模板。

---

## 7. 在线 / 离线行为

### 7.1 在线

当网络可用时，前端：

- 发送 AI 请求到后端
- 接收流式正文增量
- 接收最终 metadata
- 刷新正文、摘要、suggestion chips 和历史区

### 7.2 离线

当网络不可用时，前端：

- 继续允许编辑正文
- 继续允许保存本地文件
- AI 入口直接提示“网络不可用”
- 不进入后端请求流程

---

## 8. 客户端请求契约

前端发送到后端的核心内容必须保持为一条统一的请求结构，字段名和当前 Swift DTO 保持一致：

- 传输层使用 camelCase
- 后端存储层表字段仍然使用 snake_case

- `installationId`
- `deviceToken`
- `requestId`
- `action`
- `kind`
- `project`
- `userMessage`
- `selectionText`
- `selectionRange`

其中 `project` 必须直接使用当前 `WritingProjectSnapshot` 的完整等价对象，不在前端再拆成新的请求模型。

前端只负责把当前编辑器状态整理成请求，不负责理解 AI system prompt 细节，也不负责新增隐藏字段。

---

## 9. 前端与后端的交界

前端只认三种结果：

1. `delta`
2. `final`
3. `error`

### `delta`

正文增量，直接用于流式渲染。

### `final`

最终结果，字段与当前 `WritingAIResponse` 保持一致，前端使用：

- `documentText`
- `localSummary`
- `globalSynopsis`
- `nextFocus`
- `suggestionChips`

### `error`

标准化错误，前端只做友好提示，不做 provider 语义判断。

---

## 10. 前端迁移时的具体替换点

以下现有逻辑会被重构：

- `VibeWriteAppFlow.performWritingAction(...)`
- `WritingAIConfiguration`
- `RemoteWritingAIClient`
- `WritingAIPromptBuilder`
- `WritingProjectResponseBuilder` 的 AI 组装逻辑

前端保留的职责是：

- 组织 UI 状态
- 管正文编辑器
- 管本地文件
- 管请求生命周期显示

`Sources/VibeWriteApp/Shared/AI/StubWritingAIClient.swift` 也必须继续留在前端侧，作为本地测试和离线开发替身。

---

## 11. 前端验收标准

- 未联网时仍能完整作为本地文本编辑器使用
- AI 请求不再直接访问供应商
- 客户端不再包含任何密钥
- AI system prompt 配置不再留在客户端二进制里
- 流式正文渲染仍然顺滑
- 现有正文 / 侧栏 / 历史 / composer 的交互逻辑仍然成立
