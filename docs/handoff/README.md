# Handoff Readme

This directory is the compact handoff layer for VibeWrite.

## Read order
1. `PROJECT_CONTEXT.md`
2. `docs/V2/AGENTS.md`
3. `docs/V2/PRD2.0.md`
4. `docs/V2/IA2.0.md`
5. `docs/V2/UI2.0.md`
6. `docs/V2/Wireframes2.0.md`
7. `docs/handoff/CHANGELOG.md`
8. `task/TASK_20260402_012.md`
9. `task/TASK_20260402_013.md`
10. `task/TASK_20260402_014.md`
11. `task/TASK_20260402_015.md`
12. `task/TASK_20260402_016.md`
13. `task/TASK_20260402_017.md`
14. `docs/V2/STRICT_ALIGNMENT_AUDIT.md`
15. `task/TASK_20260402_018.md`
16. `task/TASK_20260402_019.md`
17. `task/TASK_20260402_020.md`
18. `task/TASK_20260402_021.md`
19. `task/TASK_20260402_022.md`
20. `task/TASK_20260403_023.md`
21. `task/TASK_20260403_024.md`

## Purpose
- keep the project easy to resume
- record durable implementation changes
- avoid duplicating the same status across many notes

## Current state
- V2 docs remain the source of truth; `docs/V1/` is archival only.
- The latest repo commit is `9a35b2c`, which adds ignore rules for local Xcode artifacts and workspace state so they do not get staged by accident.
- `Config/VibeWrite.local.xcconfig` stays local-only and currently contains a real `MINIMAX_API_KEY`; it is ignored and should not be committed.
- The selection popover bridge was narrowed so update sync no longer clears a live NSTextView selection when the SwiftUI binding is nil, which lets the non-empty selection stabilize for popover display.
- Streaming正文 preview now uses a dedicated playback renderer: the first visible chunk is emitted immediately, later deltas are revealed on a frame-paced cadence, and the editor auto-scrolls to the document end while AI is actively streaming.
- The流式 cadence is code-configurable through `WritingStreamingConfiguration` plus the `VIBEWRITE_STREAMING_*` build settings in `Config/VibeWrite.xcconfig`, so we can tune the feel without scattering constants through the app.
- The app now saves and opens user work as Markdown files with a compact metadata block. The File menu owns `Open`, `Save`, `Save As`, and `Open Recent`, the header title is editable in place, and bad metadata never blocks正文 editing.
- The app-owned local store now only keeps lightweight recent-document entries; the actual writing state is file-backed and lives in the user's Markdown document.
- Edit streaming now starts from the selected passage instead of replaying from the top of the document, so local patch responses feel anchored to the user’s selection.
- The page header subtitle now uses the project’s next-focus text instead of the raw AI summary, which prevents transient model copy from leaking into the title area.
- `task/TASK_20260403_024.md` completed the visual restyle pass, but the deeper post-submit diagnosis found an app-side hang rather than an XCTest idle issue.
- The hang was fixed in `SelectableTextEditor` and `VibeWriteAppFlow`, and the targeted UI test now gets past the second submit.
- The latest prompt-path fix restored `startDraft` user input into the actual LLM payload, and the正文 editor now applies a clearer, larger AppKit text style so remote drafts are readable on the dark shell.
- The first-draft prompt-loss bug is now fixed too: `startDraft` keeps the user's input in the AI request even when it matches `project.prompt`, and the flow avoids duplicating that same message in conversation history during quick-start.
- A follow-up editor fix now clamps `StyledTextView` resize sizes to non-zero values, refreshes layout during live resizing, and keeps the documentView pinned to the scroll view origin while reusing the visible clip bounds whenever resize geometry is still settling. That stopped正文 text from vanishing when the whole window is repeatedly stretched and shrunk, and the fix was verified in a real window with正文 content present.
- The selection edit popover now follows the selected正文 area instead of staying fixed in the page's upper-right corner. The working fix keeps selection updates live and uses the scroll-view's top-left coordinate system directly; the previous y conversion could push the popover out of view. The edit/continue actions were left intact.
- A follow-up root cause was found in the AppKit bridge: a nil selection binding could still be reflected back into `NSTextView` during update churn, which cleared the user's non-empty selection before SwiftUI could render the popover. The current sync logic only clears when there was an actual mirrored selection to clear.
- The latest popover follow-up found a second bridge gap: direct non-empty selection changes were not reliably surfacing through the existing delegate path, so the popover often appeared only after the正文 scroll view moved and forced another snapshot. The bridge now observes `NSTextView.didChangeSelectionNotification` directly and flushes selection sync again after layout if the change arrived mid-layout.
- Remote AI now uses a two-part completion protocol:正文 continues to stream as text, while a trailing `[[VIBEWRITE_METADATA]]` JSON block carries real `summary`, `nextFocus`, and `suggestionChips` values from the model; those suggestions now surface in the composer area above the input field.
- The composer guidance row is now intentionally sparse in the blank/start-draft state: initial empty正文 only shows the primary `生成开场` pill, while assistant guidance chips stay on a single line and no longer wrap into a second row.
- The window and project shell no longer impose hard minimum width/height constraints, so the app can now be resized freely for real-world layout testing.
- Compact project layout now uses a full-window editor surface instead of the old nested rounded shell, so shrinking the window no longer falls back to a fake-looking big-frame/little-frame composition.
- The AI and history sidebars have been flattened toward a Codex-style sliding panel treatment: softer shell, fewer nested section cards, and more list-like rows.
- The history sidebar is now intentionally hidden from the UI, while the AI sidebar keeps only status and recent replies; the collaboration summary and next-step suggestion blocks are still in code but not rendered.
- The正文 editor and composer now share the same centered content column and horizontal padding, so shrinking the window no longer makes the upper editor block and lower input bar drift out of alignment.
- During the latest validation, the正文 editor disappearance was reproduced as a layout-height issue: adding a temporary min-height made the正文 visible again, and that diagnostic change was then reverted. The remaining question is prompt semantics / model behavior, not transport.
- When the正文 is fully cleared, the title subtitle now falls back to the initial stage description instead of lingering on the last generated summary; while AI is thinking, the subtitle can append a light animated ellipsis.
- Empty body state is now stripped down to the plain editor surface and cursor-ready input area; the old "还没有正文" prompt card has been removed from the正文 panel.
- The top-left assistant sidebar toggle is clickable again; the centered project-title layer in the header now ignores hit testing so it no longer blocks the button.
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes after the prompt-loss fix; `swift test` compiles but currently fails to launch the macOS test bundle in this environment because of a local code-signing/library-load policy issue.
- `swift test` now passes with the file-based document flow and menu commands in place.
- The remaining open issues are the later UI-test rail assertion and the layout/semantics work that still needs review outside this prompt-loss fix.
- The latest resize regression is now handled at the editor bridge: the正文 editor keeps a stable identity across compact/wide shell switches and refreshes its AppKit layout geometry so shrinking and re-expanding the window does not leave the document visually blank.
- Local Xcode-generated files and user workspace state are now ignored in git; double-check that only source, docs, and intended assets are staged before committing.
- Keep `PROJECT_CONTEXT.md` as the primary source of truth and `CHANGELOG.md` as the append-only history.
- The app no longer synthesizes fallback next-step suggestions when the model omits metadata: `summary`, `nextFocus`, and `suggestionChips` now stay empty unless the remote response provides them, and the sidebar/composer render only real model output.
- Runtime AI logs now record whether completion metadata was actually parsed, along with the parsed summary/next-focus/suggestion counts, so the next real request can confirm whether the remote model is returning suggestions or the UI is simply receiving an empty block.
