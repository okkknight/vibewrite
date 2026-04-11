# VibeWrite API 3.0

## 1. API 目标

V3 API 的目标很简单：

- 让客户端不用直接接供应商
- 让 AI system prompt 配置和密钥留在后端
- 让限额在服务端强制生效
- 让管理后台能够查询请求和配置

---

## 2. 客户端 API

### 2.1 设备注册

`POST /v3/client/bootstrap`

用途：

- 接收客户端生成的 `installationId`
- 返回设备是否可用
- 返回后端签发的 `deviceToken`
- 返回当前限额摘要

响应字段固定为：

- `deviceToken`
- `deviceStatus`
- `quotaSummary`

其中 `deviceStatus` 在当前阶段固定返回 `active`。

其中 `quotaSummary` 只包含当前默认限额，不包含历史用量：

- `dailyLimit`
- `weeklyLimit`

`bootstrap` 对同一 `installationId` 在进程生命周期内必须保持幂等，重复请求返回同一个 `deviceToken`。

请求字段：

- `installationId`
- `appVersion`
- `platform`
- `deviceName`

### 2.2 起稿

`POST /v3/writes/start`

### 2.3 续写

`POST /v3/writes/continue`

### 2.4 局部编辑

`POST /v3/writes/edit`

### 2.5 心跳 / 健康检查

`GET /v3/health`

响应固定为：

```json
{ "status": "ok" }
```

---

## 3. 客户端请求体

三类写作请求必须统一使用同一套核心字段，字段名和当前 Swift DTO 保持一致：

- 传输层使用 camelCase
- 存储层表字段使用 snake_case

- `installationId`
- `deviceToken`
- `requestId`
- `action`
- `kind`
- `project`
- `userMessage`
- `selectionText`
- `selectionRange`

其中，`project` 必须是 `WritingProjectSnapshot` 的完整等价对象，字段固定为：

- `id`
- `automationKey`
- `title`
- `prompt`
- `mode`
- `localSummary`
- `globalSynopsis`
- `context`
- `conversation`
- `documentText`
- `suggestionChips`
- `updatedAt`

这里的 `prompt` 是用户写作简述，不是后台 AI system prompt 模板。

`project.context`、`project.conversation` 以及其他嵌套类型必须沿用当前共享模型的既有结构，不得新造字段。

其中：

- `installationId`、`deviceToken`、`requestId`、`action`、`kind`、`project` 都是必填字段
- `userMessage`、`selectionText`、`selectionRange` 按 action 需要时传入
- `userMessage` 只表示用户输入，不表示后台的 AI system prompt 模板
- `project.prompt` 只表示用户写作简述，不表示后台的 AI system prompt 模板
- `project.documentText` 只用于当前 AI 请求
- `selectionText` 和 `selectionRange` 只用于局部编辑

后端不保存这些正文内容，也不在协议里新增隐藏字段。

---

## 4. 流式返回

后端必须使用 `SSE` 或兼容的流式响应。

流式事件固定为：

- `delta`
- `final`
- `error`

### `delta`

只携带正文增量，不包含机密信息。

### `final`

携带最终结构化结果，字段与当前 `WritingAIResponse` 保持一致：

- `assistantMessage`
- `documentText`
- `localSummary`
- `globalSynopsis`
- `intentSummary`
- `styleConstraints`
- `currentGoal`
- `recentDecisions`
- `workingMemory`
- `nextFocus`
- `suggestionChips`
- `mode`

### `error`

携带标准化错误码，例如：

- `network_unavailable`
- `quota_exceeded`
- `provider_error`
- `invalid_request`
- `unauthorized`

---

## 5. 服务端设备令牌

V3 不做账号体系，但仍然必须保护接口。

固定方案如下：

1. 客户端首次启动生成 `installationId`
2. `bootstrap` 接口返回后端签发的 `deviceToken`
3. 客户端本地持久化 `installationId` 和 `deviceToken`
4. 后续所有客户端 AI 请求必须同时携带这两个字段
5. 后端只接受通过 `deviceToken` 校验的设备请求

这样能做到：

- 不暴露供应商密钥
- 便于设备限额
- 便于服务端拒绝异常请求
- 便于后台封禁设备

---

## 6. 限额规则

### 6.1 维度

按设备维度控制：

- 日限额
- 周限额

### 6.2 判定

两个条件只要有一个超限，就直接拒绝：

- 当日已用量超过日上限
- 当周已用量超过周上限

### 6.3 统计单位

额度单位固定为 AI 请求次数。

- 每次后端接受一条 AI 请求，日用量加 1，周用量加 1
- 被后端拒绝的请求不计入任何用量
- 起稿、续写、局部编辑都按同一套请求次数规则统计

### 6.4 结果

超限时返回明确错误，不做复杂降级。

---

## 7. 管理后台 API

### 7.1 登录

`POST /v3/admin/login`

### 7.2 登出

`POST /v3/admin/logout`

### 7.3 请求查询

`GET /v3/admin/requests`

支持按以下条件查询：

- 时间范围
- 设备 ID
- action
- 状态
- 错误码

### 7.4 密钥管理

`GET /v3/admin/secrets`

`PUT /v3/admin/secrets`

### 7.5 AI system prompt 管理

这里的 AI system prompt 配置指后端当前生效配置，不是 `project.prompt`。

`GET /v3/admin/system-prompt`

`PUT /v3/admin/system-prompt`

### 7.6 限额管理

`GET /v3/admin/quota`

`PUT /v3/admin/quota`

### 7.7 设备管理

`GET /v3/admin/devices`

`PUT /v3/admin/devices/:id/block`

`PUT /v3/admin/devices/:id/unblock`

---

## 8. 请求日志原则

后端日志只保留元数据，不保留正文和摘要。

必须记录：

- `request_id`
- `installation_id`
- `device_token_hash`
- `action`
- `status`
- `duration_ms`
- `token_in`
- `token_out`
- `error_code`
- `provider`
- `model`

不记录：

- 正文原文
- 摘要原文
- `project.prompt`
- `userMessage`
- `selectionText`
- AI system prompt 模板原文
- 选区原文

---

## 9. 数据库表

最少需要这些表：

- `devices`
- `quota_usage_daily`
- `quota_usage_weekly`
- `request_logs`
- `admin_sessions`
- `prompt_config`
- `secrets`
- `blocked_devices`

`quota_usage_daily` 和 `quota_usage_weekly` 只记录请求次数，不记录正文。

`admin_sessions` 只用于后台登录态，不承载客户端身份。

`devices` 必须保存设备当前状态、封禁状态和 `device_token` 的哈希值。

---

## 10. 兼容原则

后端先只支持一个模型，但 API 契约必须保留：

- `provider`
- `model`
- `route`

这样以后如果要换模型，不需要改客户端协议。
