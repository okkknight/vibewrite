# VibeWrite Project Context

## What this project is
VibeWrite is a macOS SwiftUI writing collaborator. The product goal is editor-first drafting with a calm native shell: users start from a prompt, grow正文 with AI, and use AI/history rails only as auxiliary surfaces.

## What this project is not
- not a general chat app
- not a large writing suite
- not a project-management tool
- not a multi-document content library

## Current state
- V2 docs under `docs/V2/` are the source of truth.
- The latest committed change is `9a35b2c`, which adds repo-level ignore rules for local Xcode artifacts and workspace state so those files do not get staged accidentally.
- `Config/VibeWrite.local.xcconfig` is intentionally local-only and currently carries a real `MINIMAX_API_KEY`; it is ignored by git and should stay out of commits.
- The selection popover bridge no longer writes a nil desired selection back into `NSTextView` during update sync, which was clearing live selections before SwiftUI could show the popover.
- Streaming正文 preview now uses a dedicated playback renderer: the first chunk appears immediately, later deltas are revealed on a frame-paced cadence, and the editor follows the document end during AI streaming so the output feels fast without turning into big bursty jumps.
- The playback cadence is now code-configurable through `WritingStreamingConfiguration` and the `VIBEWRITE_STREAMING_*` build settings in `Config/VibeWrite.xcconfig`.
- Edit streaming now reveals from the selected region instead of replaying from character 0, so local patch responses feel anchored to the passage the user selected.
- The page header subtitle no longer surfaces the raw AI summary text; it now prefers the project's next focus text and falls back to the stage description when empty.
- The app has switched to a file-first document model: Markdown files carry a compact YAML-style metadata block plus正文, the header title is directly editable, `Cmd+O` / `Cmd+S` / `Cmd+Shift+S` now live in the File menu, and context recovery never blocks writing even if metadata is missing or malformed.
- User文本 and协作 state are no longer kept in the app's primary local store. Only lightweight recent-document entries remain app-owned; the writable project state now lives in the user's Markdown file.
- `task/TASK_20260403_024.md` completed the visual restyle pass: the app keeps the same structure and interactions, but the shell/theme now uses a clearer Apple-style visual system.
- The post-submit hang in `UITests/VibeWriteUITests.swift` was not an XCTest idle problem. Direct sampling showed a SwiftUI/AppKit feedback loop in the AppKit-backed editor bridge:
  - `SelectableTextEditor.updateNSView(...)` kept mutating `NSTextView` properties and syncing selection/accessibility state
  - `SelectableTextEditor.Coordinator.textDidChange(...)` and `textViewDidChangeSelection(...)` fed binding updates back into SwiftUI
  - `VibeWriteAppFlow.activeProjectBinding` was persisting every binding writeback, which amplified the loop
- The hang has been fixed in shared/business code, not just in the test:
  - `SelectableTextEditor` now guards programmatic updates and only writes appearance/accessibility changes when values actually change
  - `VibeWriteAppFlow.activeProjectBinding` now updates in memory without persisting on every binding writeback
- The latest prompt-path regression has also been fixed: `startDraft` now keeps the user's typed input in the real LLM payload, and the正文 editor renders with a clearer, larger AppKit-native text style so remote drafts are readable against the dark shell.
- The first-draft prompt-loss bug has now been fixed: `requestUserMessage(...)` no longer drops a `startDraft` prompt just because it matches `project.prompt`, and the flow avoids duplicating that same message in the conversation history when the quick-start path already seeded it.
- The latest resize regression was narrowed to the AppKit editor bridge and layout switching: shrinking the window across the compact/wide threshold could leave the正文 visually blank even though the model text still existed. The editor now keeps a stable identity across layout changes and refreshes its AppKit layout/scroll geometry when its parent shell changes size.
- A follow-up resize fix now also lives inside `StyledTextView`: during live resizing it clamps frame sizes to non-zero values, the coordinator always resyncs the text container from the current visible clip bounds instead of bailing out on transient zero content sizes, and the documentView frame is pinned back to `{0,0}` so it does not drift out of the visible area. This was verified in a real macOS window after pasting正文 and resizing the app larger.
- The selection edit popover now tracks the selected正文 region instead of staying pinned to the page's top-right corner. The key fix was to keep selection updates live and use the scroll-view's top-left coordinate system directly; the earlier version was converting the y position the wrong way and could push the popover out of view.
- Follow-up debugging showed the popover was still not appearing because the AppKit bridge kept syncing a nil binding back into `NSTextView` and clearing the user's non-empty selection during layout/update churn. The current fix only clears the editor selection after a real mirrored selection existed, so the user selection can stabilize and the popover can render.
- A later trace narrowed another popover regression further: non-empty selection snapshots were only reaching SwiftUI on scroll-bounds changes, while direct user selection changes were often missed during layout churn. `SelectableTextEditor` now listens to `NSTextView.didChangeSelectionNotification` directly and flushes any selection sync that arrived mid-layout as soon as layout finishes, so the popover no longer has to wait for a manual scroll to appear.
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes after the update.
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes after the latest edit-streaming and subtitle fixes.
- `swift test` currently compiles successfully but fails to launch the macOS test bundle in this environment because of a local library-load/code-signing policy issue; the app target still builds cleanly with `xcodebuild build`.
- The targeted UI test now gets past the second submit and into the rail section, but it is still not fully green because `project.assistantRailShell` does not appear within the current timeout.
- The writing session remains正文-first with collapsible AI/history rails and a standalone bottom composer.
- AI requests stream deltas into the active project; final responses are patched locally and persisted once at the end.
- Local project content persistence has been replaced by file-backed Markdown documents. The app still keeps a lightweight recent-document list for convenience, but the actual writing state now lives in the user's file.

## Architecture / state flow
- `VibeWriteAppFlow` is the main state owner: it manages the project list, active project, AI request state, local persistence, and revision history.
- `SelectableTextEditor` is the AppKit bridge for正文 selection/editing; it is the most sensitive place for reentrancy and snapshot-driven UI hangs.
- `WritingEditPatch` and revision history keep edit flows local and reversible.
- UI tests launch against stub AI mode and reset the app's own container-local store.

## Key files
- `Sources/VibeWriteApp/App/VibeWriteApp.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift`
- `Sources/VibeWriteApp/App/LocalProjectStore.swift`
- `Sources/VibeWriteApp/App/RecentDocumentStore.swift`
- `Sources/VibeWriteApp/App/VibeWriteCommands.swift`
- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectAISidebarView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectHistoryDrawerView.swift`
- `Sources/VibeWriteApp/Features/Project/ProjectComposerBar.swift`
- `Sources/VibeWriteApp/Shared/Views/SelectableTextEditor.swift`
- `Sources/VibeWriteApp/Shared/Views/ProjectShellChrome.swift`
- `Sources/VibeWriteApp/Shared/Documents/VibeWriteMarkdownDocument.swift`
- `Sources/VibeWriteApp/Shared/Models/WritingPatchModels.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIConfiguration.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingStreamingConfiguration.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingStreamingPreviewRenderer.swift`
- `Sources/VibeWriteApp/Shared/AI/RemoteWritingAIClient.swift`
- `Sources/VibeWriteApp/Shared/AI/StubWritingAIClient.swift`
- `UITests/VibeWriteUITests.swift`
- `Tests/VibeWriteAppTests/VibeWriteAppFlowTests.swift`
- `Tests/VibeWriteAppTests/WritingAITests.swift`
- `Config/VibeWriteInfo.plist`
- `Config/VibeWrite.xcconfig`
- `Config/VibeWrite.local.xcconfig`

## Verified commands
- `swift build`
- `swift test`
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`
- `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` currently gets past the second-submit path, but the UI suite still fails later at the assistant rail shell assertion
- `swift test` passes with the file-based document flow and menu commands in place.

## Runtime notes
- `VIBEWRITE_UI_TEST_RESET_STORAGE=1` resets the app's own container-local store for UI runs.
- `--clean-launch` and `VIBEWRITE_FORCE_BLANK_STARTUP=1` still force a blank start for acceptance runs.
- Keep local Xcode-generated files, `Config/VibeWrite.local.xcconfig`, and user workspace state out of commits; `.gitignore` now covers them, but double-check before staging if the repo status looks noisy.
- Avoid adding UI-test waits that depend on app idle or repeated `exists` / snapshot polling around the editor bridge; that was the area that hid the real hang.
- If you touch `SelectableTextEditor` or the AI writeback path, rerun the targeted UI test before assuming the post-submit flow is safe.
- If you touch the edit streaming preview path, check both `startDraft` and `edit` so the stream still reveals from the intended region.
- If you touch the start-draft request assembly again, make sure the prompt is still passed to the AI request once and is not silently dropped by dedup logic.
- If you touch the file document parser or save flow, make sure malformed metadata still degrades to正文-only editing instead of blocking open/save.

## Working rules
- Keep the handoff concise and durable.
- Do not duplicate the same status across multiple files.
- Prefer fixing shared business/editor code over patching around symptoms in the test when the app itself is hanging.
- If you change the shell or editor bridge, verify both the second-submit path and the rail-toggle path.
