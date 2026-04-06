# Changelog

## 2026-04-06
- The正文 editor bridge now tracks a real pending user-text change before preserving live text, instead of depending on marked-text state, so ordinary typing still wins over stale binding sync while blank focused editors stay out of the first-open hydration path.
- Pristine blank startup sessions now bypass the discard prompt on window close, so the app does not ask to save when no real正文 or collaboration edits have happened yet.

## 2026-04-06
- Remote AI metadata now uses a structured Anthropic tool call: the metadata request forces `emit_metadata` and decodes the tool arguments directly, which removes the old text JSON parse failure mode for `summary`, `nextFocus`, and `suggestionChips`.

## 2026-04-06
- Prose streaming completion now pins the正文 caret to the end of the newly streamed text and keeps the viewport anchored there briefly, so the document no longer snaps back to the earlier selection position when the stream finishes.
- Verification note: the current worktree still has an unrelated `RemoteWritingAIClient.swift` access-control mismatch, so the full-project build remains blocked outside this localized prose-end follow change.

## 2026-04-06
- Added runtime diagnostics for the prose/metadata split: each action now gets a short trace id, and the logs record prose network duration, prose playback tail wait duration, metadata request duration, and metadata parse failures with raw payload size.

## 2026-04-06
- `startDraft` / `continueWriting` now keep `isProseRequestInFlight` alive until the streaming preview tail finishes, so正文 auto-follow, subtitle thinking dots, and the send-button spinner stay in their thinking state through the full prose playback instead of dropping as soon as the network stream ends.
- Metadata still starts as soon as prose streaming finishes and continues independently during that tail playback window.

## 2026-04-06
- `.edit` now preserves the currently visible assistant suggestion chips when they already exist, and only uses edit-returned chips when the suggestion area was empty before the edit completed.

## 2026-04-06
- `startDraft` and `continueWriting` now run as a two-phase AI flow: prose streams first, then a separate metadata request starts as soon as the prose stream completes and can overlap the preview renderer's tail finish. Metadata fills `summary`, `nextFocus`, and `suggestionChips` after the prose phase completes, metadata failures stay silent and leave the assistant suggestion area empty instead of fabricating fallback chips, and the composer now shows a lightweight `建议生成中` pill while metadata is pending.
- `.edit` keeps the legacy combined prose-plus-metadata request path unchanged.
- Verification for this change passed with `swift test`, plus targeted filters for the new prompt, remote metadata, prose streaming, metadata failure, and flow-request split coverage.

## 2026-04-06
- `continueWriting` now advances only a little, avoids a fully closed ending, and relies on the persisted continuation summary plus the document tail instead of the fuller project-state block, so the continuation path stays softer and leaves room for the next turn.

## 2026-04-06
- Closing the macOS window via the title-bar close button now routes through the same dirty-check confirmation flow as Open/New, so unsaved正文 changes prompt to save before the window closes.

## 2026-04-05
- The正文 editor bridge now keeps live user text intact when `NSTextView` is the active first responder and its visible buffer has drifted ahead of the SwiftUI binding, so selection/focus refreshes no longer wipe freshly typed text before save.

## 2026-04-05
- Fixed the duplicate top-level `File` menu on macOS by moving VibeWrite's document actions out of a standalone `CommandMenu("File")` and into standard `CommandGroup` insertion, so the app keeps one File menu instead of creating a second one.

## 2026-04-05
- Fixed the blank-start / first-open regression: the app now seeds its saved snapshot from the blank collaboration shell, and the project view ignores stale title/body writebacks from inactive project instances so opening an external file no longer gets overwritten by an empty buffer on the first pass.

## 2026-04-05
- The selection popover preview now drops blank lines from multi-paragraph selections before rendering, so the excerpt reads as one continuous snippet and falls back to ellipsis if it still does not fit.

## 2026-04-05
- The selection popover loading state now says `思考中` and keeps only the spinner, so the state still reads as busy without the longer `AI 正在思考` label.

## 2026-04-05
- Fixed capsules and clickable suggestion chips now use distinct foreground/background tones in both day and night themes, so the non-interactive pills stay more muted while tappable chips read as actionable.
- The project title and subtitle block now sits more evenly centered inside the shortened header area, instead of drifting toward the top edge after the spacing trim.

## 2026-04-05
- The title header spacing above正文 was tightened so the title background feels shorter and the正文 sits closer, without changing any other shell styling.

## 2026-04-05
- The app now launches in day mode by default.
- Fixed capsules stay more muted than clickable suggestion chips in both day and night themes, while the suggestion chips themselves keep a warmer but lighter gold-brown day-mode tone.

## 2026-04-05
- `startDraft` now carries a harder metadata prompt: the model is explicitly told to always return `summary`, `nextFocus`, and exactly 3 concise follow-up chips even when the opening itself is short.
- `startDraft` now also spells out the response as two ordered parts, opening prose first and the metadata block second, to reduce cases where the model stops after the opening.
- `startDraft` now uses a wider request budget than the default path so the opening and trailing metadata have more room than before.

## 2026-04-05
- `continueWriting` now includes a compact project-state block in addition to the persisted `continuationSummary` and trimmed document tail, and the remote request gives continuation a slightly wider token budget so the trailing metadata has more room to survive long generations.
- `continueWriting`'s prompt was tightened again to treat the trailing metadata block as a completion condition, remove the "writing text only" conflict, and spell out the exact `[[VIBEWRITE_METADATA]]` + JSON skeleton so `suggestionChips` are more likely to return intact.
- `continueWriting`'s prompt got a small follow-up polish to remove duplicated completion wording and replace the abstract `valid JSON` phrase with a more structural `exactly one JSON object` description, while keeping the same output protocol.
- `continueWriting` now omits the project-state block entirely and relies only on the continuation summary and document tail as context, as a prompt-only experiment to see whether less state pressure improves metadata stability.

## 2026-04-05
- Day-mode selection context capsules and assistant suggestion chips now use a warmer gold-brown foreground with slightly stronger contrast so the light theme stays legible without changing the night theme styling.

## 2026-04-05
- The far-right scrollbar overlay now stays hidden when the正文 is too short to scroll and automatically fades away again after a short period of scroll inactivity.
- The正文 content area now reserves a slim lane at the far right edge for that scrollbar instead of letting the control overlay sit on top of the text, so the text no longer gets clipped on the right.
- The AppKit text bridge now computes its internal text width from the same inset-aware layout formula as the main sync pass, which removes the last few clipped pixels on the right edge.
- The scrollbar visibility now fades in on scroll activity and fades out after a short idle delay, which makes the far-right chrome feel less abrupt and closer to the system scroller behavior.

## 2026-04-05
- Trace debugging found the local-edit flash was drawing at zero opacity on its first frame, so the overlay timing was adjusted to keep the rounded highlight visible briefly before fading out.
- Verification for this follow-up passed with `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS' -only-testing:VibeWriteUITests/VibeWriteUITests/testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit`.

## 2026-04-05
- The正文 editor now buffers real user text changes that arrive during layout sync and flushes the pending binding update once layout settles, so save operations persist the latest visible正文 instead of an older model snapshot.
- Verification for this follow-up passed with `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` and `swift test`.

## 2026-04-05
- The正文 scroll indicator is now rendered as a separate overlay at the far right edge of the app instead of inside the正文 editing column, so the正文 width itself stays unchanged while the chrome moves outward.
- Verified with `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`.

## 2026-04-05
- Local edit flash now uses a rounded overlay highlight instead of a flat text background. The yellow is lighter, the flash appears immediately and fades out gradually, and the viewport stays anchored after the flash finishes instead of snapping to the document end.
- The selection-preset loading state is now treated as a real busy/disabled state in the chips, and the targeted UI test waits for the preset button to disable rather than probing a fragile accessibility spinner node.
- Verification for this refinement passed with `swift test --filter VibeWriteAppFlowTests/testEditPatchExposesReplacementHighlightRangeForLocalFlash`, `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`, and `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS' -only-testing:VibeWriteUITests/VibeWriteUITests/testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit`.

## 2026-04-06
- `startDraft` and `continueWriting` now run as a two-phase AI flow: prose streams first, then a separate metadata request fills `summary`, `nextFocus`, and `suggestionChips` after the prose phase completes. Metadata failures stay silent and leave the assistant suggestion area empty instead of fabricating fallback chips.
- `.edit` keeps the legacy combined prose-plus-metadata request path unchanged.
- Verification for this change passed with `swift test`, plus targeted filters for the new prompt, remote metadata, prose streaming, metadata failure, and flow-request split coverage.

## 2026-04-05
- Opening an external document now enters a short hydration window before the project body/title bindings are allowed to write back, which keeps the first open from being blanked out by an empty editor sync while still leaving real user edits untouched.

## 2026-04-05
- `自定义` now brings the selected text into a same-width context capsule above the composer, keeps the input focused/highlighted, and hides the selection popover while the custom-edit flow stays active.
- Dismissing the custom-edit context now clears the capsule when the user leaves the editing area, while selection changes keep the capsule text in sync.

## 2026-04-05
- Non-`edit` streaming preview now finishes character by character after the upstream stream ends instead of calling a one-shot flush that instantly appends the remaining tail.
- The renderer now has an explicit completed state, so the flow waits for the preview to catch up before applying the final document result.

## 2026-04-05
- `continueWriting` now consumes a persisted `continuationSummary` plus a trimmed document tail instead of the full正文, which keeps the continuation prompt compact and makes the model-facing summary separate from the UI-facing summary.
- Independent review on 2026-04-05 passed the continuation-summary acceptance checks: `WritingAITests/testContinueWritingPromptRequestsConcreteSuggestionChips`, `VibeWriteAppFlowTests/testSavingAndReopeningDocumentRestoresMetadataStoreState`, `VibeWriteAppFlowTests/testOpenDocumentFallsBackToBodyOnlyWhenMetadataStoreIsMalformed`, `VibeWriteAppFlowTests/testDocumentIdentityPrefersXattrOverHiddenMarker`, and `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` all succeeded.
- `continueWriting` now also tells the model to advance only a little and avoid a full ending, so the passage keeps some forward momentum instead of closing itself too hard.

## 2026-04-05
- Local edit completion now has a dedicated transient presentation state: the正文 viewport is locked while the replacement lands, then the newly replaced range flashes briefly so users can see exactly what changed without the page jumping away from the edited passage.
- The flash is driven from the edit patch itself via the replacement range, so the effect stays scoped to the local edit path instead of becoming a general-purpose document animation.
- Verification for this update passed with `swift test --filter VibeWriteAppFlowTests/testEditPatchExposesReplacementHighlightRangeForLocalFlash`, `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`, and `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS' -only-testing:VibeWriteUITests/VibeWriteUITests/testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit`.
- Independent review on 2026-04-05 passed the local edit presentation checks: the patch exposes a replacement highlight range, the selection-popover UI test still passes on macOS, and the implementation keeps the flash limited to `.edit` without affecting start-draft or continue-writing paths.

## 2026-04-04
- The file/document model was redesigned around a split between正文 and collaboration metadata. Markdown files now keep正文 plus a hidden identity marker, `xattr` owns the primary `docID`, the app-side metadata store keeps the latest conversation history and short summary snapshot, and Save As generates a fresh `docID` instead of inheriting the old one.
- Open/save now treat collaboration metadata as optional附属信息: if `xattr` and the hidden marker both fail or the stored metadata is malformed, the app falls back to正文-only editing instead of blocking the document.
- Independent review on 2026-04-04 passed the metadata-storage acceptance checks: `swift test --filter VibeWriteAppFlowTests/testSavingAndReopeningDocumentRestoresMetadataStoreState`, `swift test --filter VibeWriteAppFlowTests/testOpenDocumentFallsBackToBodyOnlyWhenMetadataStoreIsMalformed`, `swift test --filter VibeWriteAppFlowTests/testDocumentIdentityPrefersXattrOverHiddenMarker`, and `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` all succeeded.

## 2026-04-04
- Conversation history is now capped to the latest 20 rounds, and the sidebars preview that cap by showing the latest 40 messages. A very short summary snapshot is stored alongside the conversation so the collaboration context can recover without carrying the entire history forever.

## 2026-04-04
- Clicking `自定义` in the selection popover now focuses the bottom composer input and briefly highlights only the input field, so the handoff from selection editing to custom instruction entry is visible without making the whole composer louder.
- `continueWriting` now asks for a complete metadata block plus 3 concise follow-up chips directly in the prompt, so the continuation path gives the model a stronger nudge to return suggestions in the same language as the正文 without adding any fallback behavior.

## 2026-04-04
- The正文 editor now shares the same outer content column as the bottom composer but no longer applies its own centered readable-width calculation. It uses a fixed internal text inset and a right-side scroll gutter instead, which keeps the editor and composer aligned on both left and right edges without clipping正文.
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

# 2026-04-06
- The first-open hydration regression came back through the live-text preservation guard in `SelectableTextEditor`. The guard is now narrowed so an empty focused editor no longer overwrites a freshly opened external document, while real uncommitted user text still preserves the live buffer and saves normally.

# 2026-04-06
- Independent review of `QA_REPORT_2026-04-06.md` did not fully pass: the referenced macOS UI regression test `VibeWriteUITests/testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit` failed in my environment while waiting for the main window to appear, so the report's completed verification set is not reproducible as written.
- The underlying dual-request implementation still looks consistent in code review, but the QA attachment should be treated as needing a rerun of the UI check before acceptance.

## 2026-04-04
- The selection edit popover now anchors to the selected正文 region instead of staying fixed in the upper-right corner of the page. The change only touches the selection-positioning path; the edit and continue actions keep their previous behavior.
- Follow-up correction: selection changes now update the popover even when the editor is not currently editable, and the y-position math now uses the scroll-view's top-left coordinate system directly so the popover stays in view.
- Root-cause follow-up: the popover was still not appearing because the AppKit bridge was clearing the user's live selection during layout/update sync when the binding was nil. The selection sync now only clears the editor selection after a real mirrored selection existed, which lets the non-empty selection stabilize.

## 2026-04-04
- VibeWrite now uses file-backed Markdown documents as the source of truth for user writing state. The app saves and opens `.md`-style files with正文 plus a hidden identity marker, `xattr` carries the primary `docID`, the File menu owns `Open`, `Save`, `Save As`, and `Open Recent`, and the project title is editable directly in the header.
- The document parser degrades safely: if the identity marker is missing or malformed, or if the stored collaboration metadata is broken, the app falls back to正文-only editing instead of blocking open/save or context recovery.
- The app no longer keeps user文本/协作 state in its primary local store. It now only retains lightweight recent-document entries for convenience, while the actual writing content lives in the user's file and collaboration state lives in the app-side metadata store.

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
