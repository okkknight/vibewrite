# VibeWrite Data 3.0

## 1. 数据原则

V3 的数据原则非常明确：

- 正文留在客户端本地文件
- 后端只保留必要的元数据、配置和审计
- 不保存正文原文
- 不保存摘要原文
- 不保存 AI system prompt 模板原文
- `project.prompt` 作为用户写作简述继续保存在本地 project metadata 里

---

## 2. 本地数据

前端本地继续保留：

- Markdown 正文文件
- 文件内 hidden identity marker
- xattr 里的 document identity
- 最近打开文件列表
- 本地 revision history
- 本地 project metadata

当前本地 project metadata 的真实字段与 [`WritingProject`](file:///Users/linpeiwen/knightspace/vibewrite/Sources/VibeWriteApp/Shared/Models/VibeWriteModels.swift) 保持一致，至少包括：

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
- `revisionHistory`
- `updatedAt`

这里的 `prompt` 是用户写作简述，不是后台 AI system prompt 模板。

`context` 的真实字段与当前 `ProjectContext` 保持一致，包含：

- `intentSummary`
- `styleConstraints`
- `currentGoal`
- `recentDecisions`
- `workingMemory`
- `nextFocus`

`conversation` 的真实元素与当前 `ConversationMessage` 保持一致，包含：

- `id`
- `role`
- `text`
- `timestamp`

`mode` 目前只允许 `discussion` 和 `collaboration`。

当前本地元数据持久化文件是 `document-collaboration-store.json`，记录版本是 3；xattr identity marker 的 schemaVersion 是 2。

这些数据不需要上云。

---

## 3. 后端数据实体

### 3.1 Devices

记录匿名设备信息。

必备字段：

- `id`
- `installation_id`
- `installation_hash`
- `device_token_hash`
- `first_seen_at`
- `last_seen_at`
- `token_issued_at`
- `blocked_at`
- `block_reason`
- `status`

### 3.2 Request Logs

记录请求元数据。

必备字段：

- `request_id`
- `installation_id`
- `device_id`
- `action`
- `status`
- `error_code`
- `provider`
- `model`
- `duration_ms`
- `token_in`
- `token_out`
- `created_at`

### 3.3 Quota Usage Daily

记录设备当天已经消耗的请求次数。

必备字段：

- `installation_id`
- `usage_date`
- `used_requests`
- `updated_at`

说明：

- `usage_date` 固定使用 `Asia/Shanghai` 的自然日
- 每次后端接受一条 AI 请求，`used_requests` 加 1

### 3.4 Quota Usage Weekly

记录设备当周已经消耗的请求次数。

必备字段：

- `installation_id`
- `week_start_date`
- `used_requests`
- `updated_at`

说明：

- `week_start_date` 固定使用 `Asia/Shanghai` 的周一日期
- 每次后端接受一条 AI 请求，`used_requests` 加 1

### 3.5 AI System Prompt Config

保存当前 AI system prompt 配置。

这里的 AI system prompt 配置指后端当前生效配置，不是 `project.prompt`。

当前 V3 实现阶段先用内存版 system prompt config store 承载这份数据，启动时从当前客户端 prompt builder seed，更新后只在当前进程内生效；下面的表字段是后续持久化阶段的目标形态，不是本轮必须落库的内容。

必备字段：

- `config_key`
- `template_body`
- `action_rules_json`
- `model_context_rules_json`
- `updated_at`
- `updated_by`

说明：

- 不做多版本管理
- 只保留当前生效值

### 3.6 Secret Config

保存当前可用的 provider 密钥和后台管理员登录凭证。

当前 V3 实现阶段先用内存版 secret config store 承载这份数据，启动时从环境变量 seed，更新后只在当前进程内生效；下面的表字段是后续持久化阶段的目标形态，不是本轮必须落库的内容。

后续落到 PostgreSQL 时，`secret_ciphertext` 必须保存为可逆加密后的密文，不允许以明文写入数据库。加密密钥来源固定为 `ADMIN_SECRET_ENCRYPTION_KEY`。

必备字段：

- `secret_key`
- `secret_ciphertext`
- `updated_at`
- `updated_by`
- `enabled`

说明：

- 不做密钥版本树
- 只保留当前可用值和审计记录

### 3.7 Quota Rules

保存当前设备限额规则。

`quota_rules` 是当前限额的单一事实源。

必备字段：

- `daily_request_limit`
- `weekly_request_limit`
- `time_zone`
- `updated_at`
- `updated_by`

说明：

- 额度单位固定为请求次数
- 每次后端接受一条 AI 请求，日用量和周用量都加 1
- 被后端拒绝的请求不计入用量

### 3.8 Blocked Devices

保存被后台手动封禁的设备。

必备字段：

- `installation_id`
- `blocked_at`
- `block_reason`
- `blocked_by`

### 3.9 Admin Sessions

保存后台登录会话。

必备字段：

- `session_id`
- `created_at`
- `expires_at`
- `last_seen_at`
- `revoked_at`

---

## 4. 数据保留策略

### 4.1 请求日志

请求日志用于历史查询，默认保留 30 天；如需调整，必须通过部署参数显式修改。

### 4.2 敏感数据

正文、摘要、`userMessage`、`selectionText`、`project.prompt`、AI system prompt 模板原文都不入库，也不进日志。

### 4.3 审计数据

后台修改配置时只保留变更摘要，不记录正文内容。

---

## 5. 索引要求

必须为以下字段建立索引：

- `installation_id`
- `request_id`
- `created_at`
- `status`
- `action`
- `blocked_at`

---

## 6. 与前后端的关系

### 6.1 前端需要的本地数据

前端只需要本地文件和最近记录，不需要服务端持久化正文。

### 6.2 后端需要的服务端数据

后端只需要设备、请求、配置、会话和审计。

---

## 7. 数据迁移时的注意点

- 本地文档身份仍然要保留 xattr 优先、正文 marker 兜底的逻辑
- 设备限额不要和正文数据耦合
- 请求日志不要因为要查询而扩大到正文内容
