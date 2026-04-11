# VibeWrite Backend 3.0

## 1. 后端定位

V3 后端是 AI 网关、策略层和最小管理面。

它负责：

- 接收客户端写作请求
- 判定设备是否可用
- 判定是否超限
- 拼装 AI system prompt 配置
- 调用单一模型
- 返回流式正文与最终 metadata
- 记录请求元数据
- 接管密钥和 AI system prompt 配置

它不负责：

- 存正文
- 存摘要
- 管文档库
- 做账号体系
- 做多模型路由

---

## 2. 后端模块拆分

拆成以下模块：

### 2.1 API Gateway

处理：

- 客户端请求
- 管理后台请求
- 健康检查
- 鉴权

### 2.2 Device Service

处理：

- `installationId` 注册
- 设备状态
- 设备封禁
- 设备限额

### 2.3 Quota Service

处理：

- 日限额
- 周限额
- 超限拒绝

### 2.4 AI System Prompt Service

处理：

- 当前 AI system prompt 配置内容
- AI system prompt 拼装
- AI system prompt 更新

### 2.5 Provider Adapter

处理：

- 单模型调用
- 流式正文返回
- 最终结果解析

### 2.6 Request Log Service

处理：

- 请求元数据记录
- 请求查询
- 失败原因记录

### 2.7 Admin Service

处理：

- 简单登录
- 密钥更新
- AI system prompt 更新
- 设备查看
- 请求查看

---

## 3. 必须从客户端迁移到后端的逻辑

下面这些逻辑现在都在客户端里，V3 需要迁走：

- `Sources/VibeWriteApp/Shared/AI/WritingAIConfiguration.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIPromptBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/RemoteWritingAIClient.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingProjectResponseBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIModels.swift` 中与 provider 调用、响应解析、后端拼装相关的职责
- `Sources/VibeWriteApp/Shared/Models/WritingPatchModels.swift` 中与 AI 结果组装相关的部分

这些逻辑迁走后，客户端只保留请求 DTO 和渲染 DTO。

---

## 4. 后端处理一条写作请求的流程

### 4.1 请求进入

请求进入后，后端必须先做：

- 基础格式校验
- `installationId` 校验
- `deviceToken` 校验
- 设备状态检查
- quota 检查

### 4.2 AI system prompt 生成

后端根据 action 读取当前 AI system prompt 配置，并将 `project.prompt` 作为用户写作简述一起送入模型。

当前 V3 只保留单版本 AI system prompt 配置，不做多版本发布。

### 4.3 模型调用

后端通过单一 provider adapter 调用模型。

此阶段必须支持：

- 起稿
- 续写
- 局部编辑

### 4.4 流式返回

后端必须向客户端流式返回正文增量。

### 4.5 最终结果

请求结束时返回最终结构化结果，字段与当前 `WritingAIResponse` 保持一致。

前端使用：

- `documentText`
- `localSummary`
- `globalSynopsis`
- `nextFocus`
- `suggestionChips`

---

## 5. 后端 AI system prompt 管理

V3 的 AI system prompt 配置完全后端化，但不做多版本管理。

后端只保留：

- 当前生效 AI system prompt 配置
- 当前生效 action 规则
- 当前模型上下文规则

AI system prompt 配置必须作为可编辑配置存在，不能写死在代码里。

`project.prompt` 不属于后端模板配置，它是来自客户端的用户写作简述。

---

## 6. 后端密钥管理

后端持有所有密钥，包括：

- 模型 API Key
- 后端管理后台的登录密码或管理员凭证

密钥不进入客户端，不通过客户端下发。

---

## 7. 限额规则

V3 的限额策略已确认：

- 按设备维度
- 日限额
- 周限额
- 超限直接拒绝

## 7.1 统计口径

统计口径固定为 AI 请求次数。

- 每次后端接受一条 AI 请求，日用量加 1，周用量加 1
- 被后端拒绝的请求不计入用量
- 起稿、续写、局部编辑都按同一套统计口径处理

---

## 8. 错误分类

后端必须返回标准化错误，不把 provider 原始错误直接暴露给前端。

错误类固定为：

- `network_unavailable`
- `unauthorized`
- `device_blocked`
- `quota_exceeded`
- `invalid_request`
- `provider_unavailable`
- `provider_error`
- `backend_error`

前端只需要按错误类做友好提示。

---

## 9. 日志与审计

后端只保留非敏感元数据：

- `request_id`
- `installation_id`
- `action`
- `status`
- `duration_ms`
- `provider`
- `model`
- `token_in`
- `token_out`
- `error_code`

不保留：

- 正文原文
- 摘要原文
- `project.prompt`
- `userMessage`
- `selectionText`
- AI system prompt 模板原文
- 选区原文

管理后台的配置变更要单独记审计，但也不要写正文内容。

---

## 10. 返回给前端的最小协议

后端必须支持三种返回：

1. 文本增量
2. 最终结果
3. 标准化错误

这三种返回必须稳定可用，前端才能继续维持当前的流式体验。

---

## 11. 与当前代码的对应关系

下面这些当前代码职责将重定位：

- `WritingAIClient` 协议保留为抽象接口，但实现换成后端网关客户端
- `StubWritingAIClient` 继续作为本地测试替身
- `WritingAIRequest` / `WritingAIResponse` 需要拆成客户端 DTO 与后端 DTO
- `VibeWriteAppFlow` 里与 AI 编排有关的逻辑会被显著缩减

---

## 12. 后端验收标准

- 不再需要客户端直连供应商
- AI system prompt 配置和密钥都不在客户端
- 限额在服务端强制生效
- 设备维度记录可查询
- 请求元数据可查询
- 正文和摘要不落库
- 单模型接入必须先跑通
