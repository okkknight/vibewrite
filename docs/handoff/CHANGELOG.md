# Changelog

## 2026-04-04
- Remote AI metadata now has an explicit Chinese-language constraint for Chinese writing tasks, so `summary`, `nextFocus`, and `suggestionChips` are expected to stay in Chinese instead of drifting into English.
- Continue-writing streaming now reveals from the end of the current正文 instead of starting from character 0, so the streamed preview stays anchored to the latest paragraph.

## 2026-04-04
- The selection popover no longer fires an opaque one-click `润色此处` edit. It now exposes explicit preset intents (`更画面`, `更克制`, `更抓人`) plus `自定义`, while still routing preset clicks through the existing `.edit` action with concrete prompt text.
- Composer-driven selection edits no longer fall back to an empty generic edit request. With an active selection, submitting without a typed instruction now activates the custom-input path and focuses the bottom composer instead of sending a black-box rewrite.
- Added a targeted macOS UI test for the new selection-preset flow and updated the edit patch timing unit test so it matches the current completion-only local edit behavior.

## 2026-04-04
- Added targeted crash logs around `performWritingAction`, `WritingEditPatch.build`, and `WritingEditPatch.init` to pinpoint the first-draft segfault without changing behavior.

## 2026-04-04
- Local edit now carries a stable `selectionRange` from the editor bridge through the AI request, patch builder, mock engine, response builder, and live preview. That removes the old string-only re-match path that could drift after repeated local edits.
- Edit mode no longer streams live正文 replacement into the visible document. The preview renderer is bypassed for `.edit`, so the final patch applies once at completion instead of making the page jump while chunks arrive.

## 2026-04-04
- The page header subtitle was restored to the original `project.summary` behavior after clarification that the issue is not the display component itself. The strange English copy under the title remains an upstream summary/model-output problem to investigate.

## 2026-04-04
- Edit streaming now reveals from the selected passage instead of from the top of the document. The edit flow computes a reveal offset from the selected range so the streaming preview is anchored to the user's selection.

## 2026-04-04
- The latest selection-popover regression was traced to the AppKit bridge missing direct non-empty selection changes and only recomputing the overlay once the scroll view bounds moved. `SelectableTextEditor` now observes `NSTextView.didChangeSelectionNotification` directly and flushes any selection sync that arrived during layout as soon as layout completes, so the popover does not have to wait for a manual scroll.

## 2026-04-04
- The selection popover issue was narrowed to the AppKit bridge: `SelectableTextEditor` no longer writes a nil desired selection back into the text view during update sync, so a live user selection can stabilize instead of being cleared during layout churn.
- The change keeps the rest of the selection/edit flow intact; only the selection-clearing branch in the bridge was removed.

## 2026-04-04
- The repo now ignores local Xcode artifacts, workspace user state, and `Config/VibeWrite.local.xcconfig` so those files stay out of future commits.
- The local-only `Config/VibeWrite.local.xcconfig` still carries the real `MINIMAX_API_KEY`, which is intentionally not committed and should be treated as a machine-specific secret.

## 2026-04-04
- The selection edit popover now anchors to the selected正文 region instead of staying fixed in the upper-right corner of the page. The change only touches the selection-positioning path; the edit and continue actions keep their previous behavior.
- Follow-up correction: selection changes now update the popover even when the editor is not currently editable, and the y-position math now uses the scroll-view's top-left coordinate system directly so the popover stays in view.
- Root-cause follow-up: the popover was still not appearing because the AppKit bridge was clearing the user's live selection during layout/update sync when the binding was nil. The selection sync now only clears the editor selection after a real mirrored selection existed, which lets the non-empty selection stabilize.

## 2026-04-04
- VibeWrite now uses file-backed Markdown documents as the source of truth for user writing state. The app saves and opens `.md`-style files with a compact metadata block, the File menu owns `Open`, `Save`, `Save As`, and `Open Recent`, and the project title is editable directly in the header.
- The document parser degrades safely: if metadata is missing or malformed, the app falls back to正文-only editing instead of blocking open/save or context recovery.
- The app no longer keeps user文本/协作 state in its primary local store. It now only retains lightweight recent-document entries for convenience, while the actual writing content lives in the user's file.

## 2026-04-04
- The streaming正文 preview now uses a dedicated playback renderer instead of a simple flush throttle: the first chunk still appears immediately, subsequent deltas are revealed on a frame-paced cadence, and the cadence is now configurable through `WritingStreamingConfiguration` plus `VIBEWRITE_STREAMING_*` build settings.
- While AI is in flight, the正文 editor now follows the document end automatically so the visible caret keeps pace with streamed output instead of requiring manual scrolling.

## 2026-04-04
- The正文 editor no longer relies only on SwiftUI update cycles during resize: `StyledTextView` now clamps live-resize frame sizes to non-zero values, refreshes layout immediately, the coordinator resyncs the text container from the current visible clip bounds instead of bailing out on transient zero content sizes, and the documentView frame is pinned back to the scroll origin so text does not drift out of view during repeated window resizing. This was verified in a real window with正文 content present.

## 2026-04-04
- The first-draft prompt-loss bug is fixed: `startDraft` no longer drops a prompt just because it matches `project.prompt`, and the flow skips duplicating that same user message in history when quick-start has already seeded it.

## 2026-04-04
- Resized compact/wide shell switches no longer leave the正文 visually blank: the editor bridge now keeps a stable identity and refreshes its AppKit layout geometry when the window crosses the layout breakpoint.

## 2026-04-04
- The app no longer synthesizes fallback next-step suggestions when the model omits metadata: `summary`, `nextFocus`, and `suggestionChips` now stay empty unless the remote response provides them, and the sidebar/composer render only real model output.
- Runtime AI logs now record whether completion metadata was actually parsed, along with the parsed summary/next-focus/suggestion counts, so the next real request can confirm whether the remote model is returning suggestions or the UI is simply receiving an empty block.

## 2026-04-04
- The composer guidance row is now intentionally minimal in the blank/start-draft state: the composer shows only the primary `生成开场` pill, and the assistant guidance chips remain on a single line instead of wrapping into a second row.

## 2026-04-04
- Remote AI now emits a trailing `[[VIBEWRITE_METADATA]]` JSON block after the streamed正文. The app strips that metadata from the visible document, parses `summary`, `nextFocus`, and `suggestionChips` from it, and surfaces the real next-step suggestion in the composer area above the input field.

## 2026-04-04
- The title subtitle now derives from the live正文 state: when the正文 is fully cleared, it falls back to the project's initial stage description instead of keeping the last generated summary. When AI is in flight, the subtitle can append a subtle animated ellipsis.

## 2026-04-04
- The blank-body investigation was narrowed to layout: a temporary min-height on the正文 editor made the content visible again, confirming the editor container had become too easy to collapse in the simplified page shell. That diagnostic tweak was removed after validation.
- The current prompt-path remains wired end-to-end: the submitted prompt is stored in the project record and passed into the request construction flow, but the remote draft output can still read generic and not obviously reflect the user's wording.

## 2026-04-03
- 空正文态现在只保留简约的编辑器页面和光标，正文区域里的“还没有正文 / 开始起稿”占位卡已移除。
- 正文编辑区和底部 composer 现在共用同一个版心容器与左右边距，缩小窗口时它们会保持对齐，不再各自按不同宽度规则排版。
- 历史边栏现已完全隐藏不展示，AI 侧栏只保留状态和最近回复；协作摘要与下一步建议仍保留在代码中，但默认不渲染。
- 窗口和项目 shell 的最小宽高限制已全部移除，现在可以在真实 macOS 窗口里自由拖拽尺寸，便于继续验证 compact / wide 的切换边界和真实布局密度。
- compact 模式不再复用那层“正文大圆角壳”，现在会直接铺开成整窗编辑面，避免缩小时又回到大框套小框的假页面感。
- AI 侧栏和历史侧栏进一步收平：去掉了 section 里的多层圆角卡片，改成更像 Codex 的单层滑出面板和列表行。
- 顶部左侧的 assistant sidebar toggle 重新恢复可点击：标题居中层现在忽略 hit testing，避免它把按钮的点击吞掉。

## 2026-04-03
- task024 的视觉重绘已经完成，当前界面保持了原有结构和交互，但视觉体系已经切到更清晰的 Apple 风格。
- 这次 post-submit hang 的真实根因不是 XCTest idle，而是 `SelectableTextEditor` / `VibeWriteAppFlow` 里的 AppKit-SwiftUI 回路；早先对 `project.sendButton.isEnabled` 的怀疑已经被直接采样结果取代。
- 修复已经落在共享/业务代码里，而不是只改 UI test：
  - `SelectableTextEditor` 现在只在需要时同步 `NSTextView` 的外观和 accessibility 状态，并且会抑制程序化回写的反馈回路
  - `VibeWriteAppFlow.activeProjectBinding` 不再在每次 binding writeback 时都持久化
- 目标 UI 测试现在能跑过第二次提交并进入 rail 阶段，但仍未完全通过，因为 `project.assistantRailShell` 还没有在当前超时时间内出现
- `startDraft` 的 prompt 组装被修回来了：用户输入现在会进入真实 LLM payload，而不是只留在项目记录里；同时正文桥接字体和颜色也改成了更清晰的 AppKit 原生正文样式
- `swift test` 和 `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` 都已通过

## 2026-04-02
- 完成了正文中心 shell 的严格对齐重构：AI sidebar、history drawer、composer 和 selection actions 都回到各自的辅助层职责，不再像工作台式中间卡片。
- `task/TASK_20260402_021.md` 把 composer 挪成了独立底部协作入口。
- `task/TASK_20260402_022.md` 收紧了 home / state / responsive 逻辑，wide 窗口和 compact 窗口采用不同的 rail 表现。
- `task/TASK_20260403_023.md` 修回了可读性和 rail 分离，确保 wide / compact 都不是白茫茫一片。
- `task/TASK_20260403_024.md` 开始了视觉重绘，并把主要 surfaces 切到更强对比的 Apple 风格。

## 2026-04-01
- 完成了 V2 的 editor-first shell 迁移：home 只保留直接起稿和 recent session 入口，writing shell 以正文为中心，AI / history 作为辅助层。
- `task/TASK_20260401_016.md` 把 AI 路径改成了 streaming 正文更新，并把 UI test 的存储和签名问题收稳了。
- `task/TASK_20260401_017.md`、`task/TASK_20260401_018.md`、`task/TASK_20260401_019.md`、`task/TASK_20260401_020.md`、`task/TASK_20260401_021.md`、`task/TASK_20260401_022.md`、`task/TASK_20260403_023.md`、`task/TASK_20260403_024.md` 依次推进了视觉、sidebar、history、composer 和响应式整合。
- 这一阶段的产品方向已经稳定为：`startDraft -> continueWriting -> edit` 的三动作正文中心写作流。

## 2026-03-31
- 创建了 VibeWrite 的最初 SwiftUI macOS 骨架。
- 完成了 home / project 的基础页面和最早的 mock 交互。
- 建立了本地存储、修订历史、AI 抽象和 UI automation 的基础设施。
- 这一阶段的目标是把产品跑起来并把主要交互面铺开，后续所有 V2 重构都建立在这套骨架上。
