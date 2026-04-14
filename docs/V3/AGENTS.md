# VibeWrite V3 AGENTS

## 1. 这份文档是干什么的

这份文档是 VibeWrite V3 阶段的 agent 操作指南。

V3 的主题不是继续扩写本地单体，而是把项目拆成：

- 前端壳子
- 后端 AI 网关
- 简单后台管理页

V3 文档用于约束后续的拆分实现、接口设计和后台能力边界。

---

## 2. V3 的正式参考文档

V3 规划与实现优先阅读：

- `docs/V3/PRD3.0.md`
- `docs/V3/IA3.0.md`
- `docs/V3/ROADMAP3.0.md`
- `task/TASK_20260411_025.md`
- `task/TASK_20260411_026.md`
- `docs/V3/FRONTEND3.0.md`
- `docs/V3/BACKEND3.0.md`
- `docs/V3/DATA3.0.md`
- `docs/V3/API3.0.md`
- `docs/V3/ADMIN3.0.md`
- `docs/V3/DEPLOY3.0.md`
- `docs/V3/MIGRATION3.0.md`
- `task/TASK_20260411_027.md`
- `task/TASK_20260411_028.md`
- `task/TASK_20260412_029.md`
- `task/TASK_20260412_030.md`
- `task/TASK_20260412_031.md`
- `task/TASK_20260412_032.md`
- `task/TASK_20260412_033.md`
- `task/TASK_20260412_034.md`
- `task/TASK_20260412_035.md`
- `task/TASK_20260412_036.md`
- `task/TASK_20260412_037.md`
- `task/TASK_20260412_038.md`
- `task/TASK_20260412_039.md`
- `task/TASK_20260413_040.md`
- `task/TASK_20260414_041.md`
- `task/TASK_20260414_042.md`

如果和 V1 / V2 文档冲突，V3 规划优先于旧版本的产品设计，但当前已上线实现仍以现有代码状态为准。

---

## 3. V3 产品定位

VibeWrite V3 是一个：

- 保留本地编辑器能力的极简写作壳子
- 通过后端提供 AI 能力、AI system prompt 配置、密钥和限额控制
- 支持离线作为普通文本编辑器使用
- 支持一个轻量后台做密钥更新、请求监控和额度查看

V3 不是：

- 云文档系统
- 账号协作平台
- 多模型平台
- 重型内容管理后台
- 面向用户开放的 AI system prompt 配置市场

---

## 4. V3 的核心原则

### 4.1 前端只保留壳子

- 前端负责正文编辑、保存、打开、流式渲染和基础交互
- 前端不保存 AI 密钥
- 前端不保存 AI system prompt 配置设计
- 前端不承担请求路由和限额判定

### 4.2 后端只管机密与策略

- 后端负责 AI system prompt 编排
- 后端负责 provider 调用
- 后端负责限额和请求拒绝
- 后端负责日志与监控
- 后端不存正文与摘要

除非明确写成 `project.prompt`，这里的 `prompt` 都指 AI system prompt 配置，不指用户写作简述。

### 4.3 简单优先

- 不做账号体系
- 不做多版本 AI system prompt 管理
- 不做多模型接入
- 不做复杂权限系统
- 不做文档云同步
- 限额单位固定为 AI 请求次数
- 客户端必须携带 `installationId` 和 `deviceToken`
- 设备身份只认 `installationId` + `deviceToken`

### 4.4 离线可用

- 没网时，客户端仍可继续编辑和保存本地正文
- AI 入口在离线时只提示网络不可用
- 普通文本编辑器体验不能被后端依赖打断

---

## 5. V3 研发规则

### 5.1 先定边界，再定接口

V3 的第一优先级是明确：

- 哪些内容必须留在本地
- 哪些内容必须上后端
- 哪些能力要放到后台管理页

### 5.2 不把 V2 的单体逻辑原样搬过去

V2 里的以下内容，在 V3 中都必须从客户端移出：

- AI system prompt builder
- provider 选择
- API key 读取
- metadata 生成策略
- 限额判断
- 请求日志写入

### 5.3 客户端只保留必要协议

客户端保留的重点是：

- `WritingAIClient` 类似的协议层
- 文本流式渲染
- 本地文档读写
- 离线降级提示

### 5.4 管理页要极简

后台管理页只做：

- 简单登录
- 密钥更新
- AI system prompt 更新
- 请求监控
- 额度查看

不做：

- 多人协作
- RBAC
- 审批流
- 复杂仪表盘

---

## 6. 执行顺序

1. 先读 `PRD3.0.md` 和 `IA3.0.md`，把产品边界和信息架构钉住
2. 再读 `ROADMAP3.0.md`，把推进顺序、依赖和阶段门槛钉住
3. 再读 `task/TASK_20260411_025.md`、`task/TASK_20260411_026.md`、`task/TASK_20260411_027.md`、`task/TASK_20260411_028.md`、`task/TASK_20260412_029.md`、`task/TASK_20260412_030.md`、`task/TASK_20260412_031.md`、`task/TASK_20260412_032.md`、`task/TASK_20260412_033.md`、`task/TASK_20260412_034.md`、`task/TASK_20260412_035.md`、`task/TASK_20260412_036.md`、`task/TASK_20260412_037.md`、`task/TASK_20260412_038.md`、`task/TASK_20260412_039.md`、`task/TASK_20260413_040.md`、`task/TASK_20260414_041.md` 和 `task/TASK_20260414_042.md`，把现有执行卡钉住
4. 再读 `FRONTEND3.0.md`、`BACKEND3.0.md`、`DATA3.0.md`、`API3.0.md`、`ADMIN3.0.md` 和 `DEPLOY3.0.md`，把实现边界钉住
5. 最后按 `MIGRATION3.0.md` 的顺序落地

---

## 7. 给后续 agent 的提示

如果你是接手 V3 的 agent，请始终记住：

- 前端要像编辑器，不像工作台
- 后端要像网关，不像内容库
- 管理页要像运维面板，不像后台系统
- 离线编辑必须始终可用
- AI 不可用时，不能影响文本编辑和保存
