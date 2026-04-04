# V2 严格对齐偏差清单与实施方案

## 结论

当前实现**不满足 V2 的严格产品设计要求**。

原因不是“能不能用”，而是核心页面骨架、辅助层组织方式、输入区位置、状态语义和响应式策略都被压缩成了一个更安静的单列 notebook 变体，和 V2 文档里明确写出的产品结构不一致。

本文件只接受一种标准：**严格对齐文档，不接受“刻意收敛”式替代方案。**

## 适用设计依据

- `docs/V2/PRD2.0.md`
- `docs/V2/IA2.0.md`
- `docs/V2/UI2.0.md`
- `docs/V2/Wireframes2.0.md`

## 当前实现范围

- `Sources/VibeWriteApp/Features/Home/HomeView.swift`
- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- `Sources/VibeWriteApp/Shared/Models/VibeWriteModels.swift`

---

## 一、偏差清单

### D1. 会话页 shell 被压成单列，未实现文档要求的侧栏骨架

**文档要求**

- 主页面应是“中央正文编辑区 + 可收缩 AI 侧栏 + 可收缩历史侧栏 + 选区浮层 + 轻量状态提示”。
- 周边辅助能力应以“侧栏 / 抽屉 / 浮层”方式出现，而不是常驻工作台分区。
- 宽屏下可以左右展开，窄屏下应转为抽屉覆盖。

参考：

- `docs/V2/UI2.0.md:79-93`
- `docs/V2/UI2.0.md:178-230`
- `docs/V2/UI2.0.md:283-320`
- `docs/V2/Wireframes2.0.md:211-249`
- `docs/V2/Wireframes2.0.md:504-517`
- `docs/V2/IA2.0.md:131-145`
- `docs/V2/IA2.0.md:316-345`

**当前实现**

- `WritingProjectView` 采用 `VStack -> ScrollView -> editorPanel / assistantLayer / historyLayer` 的单列堆叠。
- 这不是侧栏布局，也不是抽屉布局，而是正文下方继续堆叠辅助区块。

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:27-40`

**为什么这是偏差**

- V2 不是“只有正文内容正确就行”，而是明确要求页面骨架就是正文中心 + 周边增强层。
- 当前结构会把产品气质从“正文中心”进一步压成“长页面控制面板”，和文档里的 shell 设定不一致。

**对齐要求**

- 重建会话页根布局。
- 宽屏时使用左右侧栏 + 中央正文的结构。
- 窄屏时侧栏切换为可展开抽屉或 overlay。
- 正文始终是视觉中心，辅助层不得变成正文下方的普通分区。

---

### D2. AI 侧栏被做成 fold section，不是文档要求的独立协作侧栏

**文档要求**

- AI 侧栏应承载对话流、简短协作反馈、下一步建议。
- 默认可收起，需要时展开。
- 更像“写作旁注”或“协作便签”，不是独立聊天产品。

参考：

- `docs/V2/UI2.0.md:182-230`
- `docs/V2/IA2.0.md:316-345`
- `docs/V2/Wireframes2.0.md:316-318`

**当前实现**

- `assistantLayer` 只是正文下方的一块 `NotebookFoldSection`。
- 里面混合了：
  - 上下文信息
  - 下一步建议
  - 最近对话
  - 协作输入框

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:233-307`

**为什么这是偏差**

- 这不是“AI 侧栏”，而是“正文下方的折叠辅助面板”。
- 文档里的 AI 侧栏是周边协作空间，当前实现把它压回了正文流内部。

**对齐要求**

- AI 回复流必须进入独立 AI 侧栏。
- 建议、上下文、协作反馈应属于侧栏内容，而不是正文下方的折叠块。
- 侧栏默认收起，但展开后应有明确的侧栏存在感，而不是普通卡片区。

---

### D3. 历史 / 版本区被压成普通折叠区，缺少抽屉语义和历史组织

**文档要求**

- 历史侧栏 / 历史与版本抽屉应展示：
  - 最近会话
  - 版本回退
  - patch 历史
  - 前后对比
  - 重试最后一次修改
- 默认不占主视觉，但需要回顾时应可打开。

参考：

- `docs/V2/IA2.0.md:301-345`
- `docs/V2/UI2.0.md:200-230`
- `docs/V2/Wireframes2.0.md:456-467`

**当前实现**

- `historyLayer` 目前只提供：
  - 撤销
  - 前后对比
  - 本段重试
  - 比较面板
- 它没有完整承载“历史 / 版本抽屉”的信息结构。

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:315-354`

**为什么这是偏差**

- 当前历史区是“操作按钮 + 比较视图”，不是“历史 / 版本抽屉”。
- 文档里明确强调历史是辅助回看，不应压过正文，但也不能缩成只有几个按钮。

**对齐要求**

- 历史 / 版本区需要恢复成独立抽屉或侧栏。
- 必须增加最近会话、patch 历史、回退记录等组织方式。
- compare / retry / undo 应放在正确的历史语境下，而不是孤立按钮组。

---

### D4. 底部输入区被嵌进 AI 区域，未实现独立的轻量输入区

**文档要求**

- 输入框可以放在正文下方、底部工具区，或作为轻量可展开面板。
- 输入区的作用是自然承载三类动作：起稿、续写、编辑。
- 输入区不应该被语义上绑定成“AI 对话区”。

参考：

- `docs/V2/IA2.0.md:226-246`
- `docs/V2/Wireframes2.0.md:211-249`
- `docs/V2/Wireframes2.0.md:394-426`

**当前实现**

- `协作输入` 现在是 `assistantLayer` 里的一个 `TextField`。
- 它和对话流、建议区混在同一折叠面板内。

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:286-307`

**为什么这是偏差**

- 这会把“写作协作输入”看成“AI 聊天输入”。
- 文档要求的是更轻的底部输入区或工具区，不是折叠在 AI 面板里的输入行。

**对齐要求**

- 独立出底部输入区。
- 输入区应与正文协作动作绑定，而不是与 AI 面板绑定。
- 默认提示文案、按钮语义、布局位置都要回到文档定义。

---

### D5. 顶部栏缺少文档定义的侧栏开关语义

**文档要求**

- 顶部栏除了返回、标题、状态外，还应提供侧栏开关按钮。

参考：

- `docs/V2/UI2.0.md:97-105`
- `docs/V2/Wireframes2.0.md:216-249`

**当前实现**

- 顶部栏只有返回、标题、状态和更多菜单。
- 没有 AI 侧栏 / 历史侧栏的显式开关。

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:52-93`

**为什么这是偏差**

- 文档要求侧栏是可控制的增强层。
- 当前实现让侧栏开关“消失”了，辅助层只能靠默认展开状态去碰运气。

**对齐要求**

- 顶部栏必须补回侧栏开关。
- 开关语义应与宽 / 窄屏布局联动。
- 侧栏可见性不能只靠 fold section 的展开状态来表达。

---

### D6. 状态语义被压缩，起稿态和协作态没有严格分层

**文档要求**

- 起稿阶段应明确显示“起稿中”。
- 起稿后进入正文协作阶段。
- 状态表达应帮助用户理解当前处于哪一段主线。

参考：

- `docs/V2/Wireframes2.0.md:394-426`
- `docs/V2/IA2.0.md:375-397`
- `docs/V2/PRD2.0.md:19-33`

**当前实现**

- `WritingProjectMode` 只有 `.discussion` / `.collaboration` 两个模式。
- `startQuickDraft(prompt:mode:)` 在 direct start 路径里当前使用 `.collaboration`。
- 这会让部分启动链路直接落到“正文协作中”，而不是严格的“起稿中 -> 协作中”。

参考：

- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift:96-123`
- `Sources/VibeWriteApp/Shared/Models/VibeWriteModels.swift:349-372`
- `Sources/VibeWriteApp/Features/Home/HomeView.swift:1-84`

**为什么这是偏差**

- 这不是 UI 文案的小问题，而是阶段模型没有严格分层。
- 对严格产品设计来说，阶段语义必须能被用户感知，不能被启动方式吞掉。

**对齐要求**

- 起稿态必须独立可见。
- 直接起稿进入正文后，状态转移要严格可追踪。
- 如果现有 `mode` 不够表达阶段，就补阶段字段，不要继续用一个模式勉强兼容所有语义。

---

### D7. 宽 / 窄屏响应式策略没有真正落地

**文档要求**

- 宽屏时侧栏可以左右展开。
- 窄屏时侧栏应改为抽屉覆盖。
- 正文区域必须优先保留空间。

参考：

- `docs/V2/Wireframes2.0.md:504-517`
- `docs/V2/UI2.0.md:283-320`

**当前实现**

- 当前只有一个固定单列布局。
- 没有窗口宽度驱动的布局分支。

参考：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift:27-40`

**为什么这是偏差**

- 文档明确写了宽 / 窄屏策略。
- 单一布局会让 V2 在窗口变化时始终停留在“简化版”。

**对齐要求**

- 增加窗口宽度判断。
- 宽屏：侧栏并列。
- 窄屏：侧栏抽屉化。
- 不允许因为实现便利而把响应式策略永久省略。

---

## 二、对齐方案

### P0：先恢复页面骨架

目标：把会话页从“单列 notebook”改回“正文中心 + 周边增强层”。

实施要求：

1. 先重建根布局容器。
2. 在宽屏下恢复左 AI 侧栏、正文中心、右历史 / 版本侧栏。
3. 保留正文最大可读宽度，不让辅助层抢占视觉中心。
4. 选区浮层继续保留，但不要拿它充当侧栏替代品。

建议修改文件：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- 必要时新增 `ProjectSidebarView`、`ProjectComposerBar`、`ProjectHistoryDrawer` 等拆分组件

---

### P0：把输入区从 AI 区域里拆出去

目标：输入区回到文档定义的轻量底部输入区 / 工具区。

实施要求：

1. 输入框不再跟 AI 对话流混在同一块里。
2. 输入区支持三类动作：
   - 起稿
   - 续写
   - 编辑
3. 输入区文案和交互要与当前状态联动。

建议修改文件：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`

---

### P0：恢复 AI 侧栏和历史 / 版本抽屉的独立性

目标：辅助层必须作为独立增强层存在，而不是折叠区块。

实施要求：

1. AI 侧栏承载协作流、建议、简短反馈。
2. 历史 / 版本抽屉承载最近会话、patch 历史、回退与 compare。
3. 顶栏补侧栏开关按钮。
4. 默认态收起，但结构必须明确存在。

建议修改文件：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- 可能新增侧栏容器组件

---

### P1：把起稿态和协作态分开

目标：状态语义严格服务设计，不再用一个模式吞掉两个阶段。

实施要求：

1. 直接起稿进入起稿态，不要直接把语义压成“正文协作中”。
2. 首稿生成完成后，再进入正文协作态。
3. 如果 `WritingProjectMode` 无法表达阶段，就引入更明确的阶段字段。

建议修改文件：

- `Sources/VibeWriteApp/Shared/Models/VibeWriteModels.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift`
- `Sources/VibeWriteApp/Features/Home/HomeView.swift`

---

### P1：补齐宽 / 窄屏的布局分支

目标：响应式策略成为产品的一部分，不是未来再说。

实施要求：

1. 宽屏下左右侧栏可并存。
2. 窄屏下侧栏转为抽屉或覆盖层。
3. 正文必须优先，不得因辅助层导致正文可读性崩坏。

建议修改文件：

- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`

---

## 三、验收标准

以下条件全部满足之前，不视为严格对齐完成：

1. 会话页不再是单列折叠区堆叠。
2. AI 侧栏是独立结构，不在正文下方冒充。
3. 历史 / 版本是独立结构，不只剩按钮组。
4. 底部输入区独立，不挂在 AI 面板里。
5. 顶栏有侧栏开关。
6. 起稿态和协作态可明确区分。
7. 宽 / 窄屏有不同布局策略。

## 四、结论

如果目标是“能用”，当前实现已经接近可用。

但如果目标是“严格对齐 V2 的产品设计”，那当前实现仍然存在明显偏差，尤其是：

- 页面骨架
- 侧栏结构
- 输入区位置
- 状态语义

这四项不应被视为可接受收敛，必须按文档重建。
