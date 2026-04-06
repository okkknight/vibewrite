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
- The正文 editor now binds directly to `activeDocumentText` as the live session text, while `WritingProject` keeps the persisted metadata/snapshot shell. The old正文 project-body writeback bridge is gone, so title and metadata edits can stay on the project side without stealing正文 from the live editor.
- Save now writes the live session snapshot (`activeEditingProject`) directly, so `Cmd+S` reads the same正文 the editor shows instead of relying on a last-second window flush.
- Project-level updates that intentionally change正文, such as open, undo, and AI responses, now sync the live正文 back into the session snapshot through `replaceActiveProject`, which keeps the live buffer and persisted project aligned.
- Command logs now report live正文 counts, so Open / Save / Save As diagnostics match the new session layer instead of stale project-body counts.
- `startDraft` and `continueWriting` now use a two-phase AI flow: prose request first, then a separate metadata request that starts as soon as prose streaming finishes and can overlap the preview renderer's tail finish. The prose path streams normally and keeps the subtitle/send-button thinking state alive until the streaming preview tail has fully played; metadata updates `summary`, `nextFocus`, and `suggestionChips` only after the prose phase succeeds, and the composer shows a lightweight `建议生成中` pill during the metadata wait; metadata now has two routeable implementations, the current Anthropic-compatible `emit_metadata` tool path selected by default and a `MiniMax-Text-01` `json_schema` path that can still be chosen explicitly with `MINIMAX_METADATA_ROUTE=text01_json_schema`; the current tool path prompt now hard-requires a single `emit_metadata` tool call and forbids ordinary assistant text, and the latest prompt tightening makes suggestion chips the highest-priority output while keeping the global synopsis short and stable; `.edit` keeps the legacy combined-response path unchanged.
- Runtime AI logs now include a short action trace id plus prose-network, prose-playback, and metadata timing markers, which makes it easier to separate network failure, metadata parse failure, and playback-tail timing issues when QA reports a regression.
- The正文 editor and bottom composer now share one outer content column, and the editor bridge no longer centers a separate readable-width block. The editor uses a fixed text inset while the visible vertical scroll indicator is rendered in a reserved far-right lane at the edge of the app, and the editor bridge keeps its internal text width aligned with that inset so the正文 does not clip on the right; the indicator fades in on scroll activity and fades back out after a short period of idle time, while still staying hidden when the正文 is not scrollable.
- Clicking `自定义` in the selection popover now brings in a same-width context capsule above the bottom composer, keeps the input focused/highlighted, and hides the popover while the user continues the custom-edit flow.
- The selection context capsule and assistant suggestion chips now use a warmer gold-brown day-mode foreground with slightly stronger light-mode contrast so the day theme stays readable while the night theme remains unchanged.
- The app now launches in day mode by default, and the fixed capsules stay more muted than the clickable suggestion chips in both day and night themes.
- External document opens now pass through a short hydration window so the freshly loaded正文 is not immediately overwritten by an empty binding sync on the first render.
- The latest repo commit before this update is `370ec50`, which split metadata routing between the current structured-tool path and `MiniMax-Text-01` `json_schema`; this update then removes `continuationSummary` entirely and replaces it with `localSummary` plus `globalSynopsis`.
- The正文 editor bridge now preserves live user text when the NSTextView is the active first responder and its content diverges from the SwiftUI binding, so selection/focus refreshes no longer overwrite freshly typed text before save.
- The live-text preservation guard was narrowed so a focused but empty editor no longer overrides the first-open body of an external document. It now keys off a real pending user-text change instead of marked-text state, which keeps manual typing saveable while restoring the first-open hydration behavior for file-backed documents.
- Pristine blank startup sessions now bypass the discard prompt on window close, so the app does not ask to save when no real正文 or collaboration edits have happened yet.
- When prose streaming completes, the正文 editor now keeps the caret pinned to the end of the newly streamed text briefly, so the view no longer snaps back to the earlier selection position at completion.
- `swift test` and `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` both pass after the current metadata routing split, so reviewer verification can focus on the localized prose-end and metadata-routing behavior first.
- Closing the window via the macOS title-bar `×` now reuses the same dirty-check confirmation path as Open/New, so unsaved正文 changes prompt before the app closes.
- `.edit` now keeps any already-visible assistant suggestion chips instead of replacing them; the new edit metadata only appears when the suggestion area was empty before the edit completed.
- The duplicate top-level `File` menu was traced to a standalone `CommandMenu("File")` in `VibeWriteCommands`; the current fix routes those actions through standard `CommandGroup` placement so the app keeps one top-level File menu.
- `Config/VibeWrite.local.xcconfig` stays local-only and currently contains a real `MINIMAX_API_KEY`; it is ignored and should not be committed.
- `scripts/package_dmg.sh` is now the simple friend-trial packaging path: it builds a Release app with `ENABLE_DEBUG_DYLIB=NO` and stages it with an `/Applications` shortcut, so the current build can be turned into a DMG without adding a full installer flow.
- The document storage model now keeps正文 and collaboration state separate: the Markdown file stores正文 plus a hidden identity marker, `xattr` carries the primary `docID`, and the app-side metadata store keeps conversation history, `localSummary`, `globalSynopsis`, and the latest collaboration context. Save As creates a fresh `docID`, and malformed metadata falls back to正文-only editing instead of blocking open/save.
- The selection popover bridge was narrowed so update sync no longer clears a live NSTextView selection when the SwiftUI binding is nil, which lets the non-empty selection stabilize for popover display.
- Streaming正文 preview now uses a dedicated playback renderer: the first visible chunk is emitted immediately, later deltas are revealed on a frame-paced cadence, and when the upstream stream ends the renderer keeps finishing the remaining text character by character instead of flushing the tail in one jump.
- The流式 cadence is code-configurable through `WritingStreamingConfiguration` plus the `VIBEWRITE_STREAMING_*` build settings in `Config/VibeWrite.xcconfig`, so we can tune the feel without scattering constants through the app.
- Remote AI metadata is now explicitly constrained to the current document language for Chinese writing tasks, which keeps `localSummary`, `globalSynopsis`, `nextFocus`, and `suggestionChips` aligned with the prose language instead of drifting into English.
- `startDraft` prose is now metadata-free; the metadata prompt is a separate request that runs after the prose phase completes.
- `continueWriting` prose is now metadata-free; the metadata prompt is a separate request that runs after the prose phase completes, while the prose prompt still uses the persisted `globalSynopsis` and document tail.
- `continueWriting` now also tells the model to advance only a little and avoid a fully closed ending, so the prompt leaves some forward momentum for the next step.
- Continue-writing streaming playback now reveals from the end of the current正文 instead of starting from character 0, so the visible stream stays anchored to the latest paragraph.
- Local edit requests now preserve the selected正文 position as a stable `selectionRange`, and the edit/revision/mock/preview layers use that exact range instead of re-finding text by content. That prevents repeated local edits from drifting to earlier duplicate passages.
- Local edit completion now has its own transient presentation state: the正文 viewport stays anchored while the replacement lands, then the new text flashes briefly so users can see what changed without the page jumping away from the edited paragraph.
- The local-edit flash was refined again: it now uses a rounded overlay highlight with a lighter yellow tint, the flash pops in immediately and fades out gradually, and the viewport stays anchored after the flash instead of snapping the cursor to the document end.
- Trace logs confirmed the first flash frame was arriving fully transparent; the overlay timing now keeps the initial frame visible before the fade begins.
- The正文 editor now buffers user text changes that arrive during layout sync and flushes the pending binding update once layout settles, so save operations preserve newly typed正文 instead of falling back to an older model snapshot.
- The正文 editor bridge now also commits `insertText` directly into the live正文 binding, so manual typing no longer depends on `textDidChange` alone before save or selection refreshes.
- The selection-preset loading state is now represented as a real busy/disabled state in the selection chips, and the targeted UI test waits for the preset button to disable instead of probing a fragile accessibility spinner node.
- Blank startup no longer trips the discard prompt or wipes a newly opened file: the flow now starts from the blank shell's rendered snapshot, and the title/body bindings ignore stale writebacks from an inactive project so an external document is not overwritten by an empty buffer during the first load.
- Edit mode no longer uses the streaming preview renderer to rewrite the正文 live. The final patch is applied once at completion so local edits do not visually flicker through chunk-by-chunk replacement.
- The app now saves and opens user work as Markdown files with正文 plus a hidden marker. The File menu owns `Open`, `Save`, `Save As`, and `Open Recent`, the header title is editable in place, and bad or missing collaboration metadata never blocks正文 editing.
- The app-owned local store now only keeps lightweight recent-document entries; the actual writing state lives in the Markdown file, and the collaboration state lives in the app-side metadata store keyed by `docID`.
- Debug logs were added around正文 binding writeback and `saveCurrentDocument` so the current Ctrl+S save-loss repro can be traced with real `OSLog` instead of the no-op debug trace sink.
- The current save-loss debugging pass also logs the menu command entry points and `SelectableTextEditor.textDidChange`, which should let the next repro distinguish command dispatch from editor commit and from disk save.
- The current save-loss tracing pass now also logs the live正文 binding setter and the editor bridge's make/update/sync decisions in one shot, so the next repro can follow a single input from `NSTextView` into `activeDocumentText` and then into the saved snapshot without adding more probes.
- Edit streaming now starts from the selected passage instead of replaying from the top of the document, so local patch responses feel anchored to the user’s selection.
- The page header subtitle continues to use `project.localSummary`; if the text under the title is off-topic, the issue is in the local summary source, not the subtitle component.
- The current head keeps `continueWriting` soft, but the collaboration metadata now stores `localSummary` and `globalSynopsis` instead of the old `continuationSummary`.
- `task/TASK_20260403_024.md` completed the visual restyle pass, but the deeper post-submit diagnosis found an app-side hang rather than an XCTest idle issue.
- The hang was fixed in `SelectableTextEditor` and `VibeWriteAppFlow`, and the targeted UI test now gets past the second submit.
- The latest prompt-path fix restored `startDraft` user input into the actual LLM payload, and the正文 editor now applies a clearer, larger AppKit text style so remote drafts are readable on the dark shell.
- The first-draft prompt-loss bug is now fixed too: `startDraft` keeps the user's input in the AI request even when it matches `project.prompt`, and the flow avoids duplicating that same message in conversation history during quick-start.
- A follow-up editor fix now clamps `StyledTextView` resize sizes to non-zero values, refreshes layout during live resizing, and keeps the documentView pinned to the scroll view origin while reusing the visible clip bounds whenever resize geometry is still settling. That stopped正文 text from vanishing when the whole window is repeatedly stretched and shrunk, and the fix was verified in a real window with正文 content present.
- The selection edit popover now follows the selected正文 area instead of staying fixed in the page's upper-right corner. The working fix keeps selection updates live and uses the scroll-view's top-left coordinate system directly; the previous y conversion could push the popover out of view. The edit/continue actions were left intact.
- A follow-up root cause was found in the AppKit bridge: a nil selection binding could still be reflected back into `NSTextView` during update churn, which cleared the user's non-empty selection before SwiftUI could render the popover. The current sync logic only clears when there was an actual mirrored selection to clear.
- The latest popover follow-up found a second bridge gap: direct non-empty selection changes were not reliably surfacing through the existing delegate path, so the popover often appeared only after the正文 scroll view moved and forced another snapshot. The bridge now observes `NSTextView.didChangeSelectionNotification` directly and flushes selection sync again after layout if the change arrived mid-layout.
- The selection popover no longer hides edit semantics behind a single `润色此处` button. It now shows `更画面` / `更克制` / `更抓人` / `自定义`; the first three still route through the same `.edit` action with explicit prompts, while `自定义` now hands the selected text down into the composer context capsule for a user-written instruction.
- Selection edit no longer has an empty-instruction fallback from the composer. If a selection exists and the user submits with no text, the UI now treats that as `自定义` activation instead of silently sending a generic edit request.
- Remote AI now separates prose and metadata for `startDraft` / `continueWriting`:正文 streams first, then a second request fills `summary`, `nextFocus`, and `suggestionChips`; `.edit` keeps the legacy combined path.
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
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes after the prompt-loss fix; the document split now has targeted unit coverage for save/reopen, malformed metadata fallback, and xattr precedence.
- `xcodebuild build -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes after the local-edit flash and viewport refinements.
- `swift test --filter VibeWriteAppFlowTests/testEditPatchExposesReplacementHighlightRangeForLocalFlash`
- The new document split is covered by targeted tests for save/reopen, malformed metadata fallback, and xattr precedence, so the storage path has direct coverage instead of relying on the older embedded-metadata flow.
- `swift test` now passes with the file-based document flow and menu commands in place.
- `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS' -only-testing:VibeWriteUITests/VibeWriteUITests/testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit` passes and exercises the new preset-based local edit flow on the real app.
- The remaining open issues are the later UI-test rail assertion and the layout/semantics work that still needs review outside this prompt-loss fix.
- The latest resize regression is now handled at the editor bridge: the正文 editor keeps a stable identity across compact/wide shell switches and refreshes its AppKit layout geometry so shrinking and re-expanding the window does not leave the document visually blank.
- Local Xcode-generated files and user workspace state are now ignored in git; double-check that only source, docs, and intended assets are staged before committing.
- Keep `PROJECT_CONTEXT.md` as the primary source of truth and `CHANGELOG.md` as the append-only history.
- The app no longer synthesizes fallback next-step suggestions when the model omits metadata: `summary`, `nextFocus`, and `suggestionChips` now stay empty unless the remote response provides them, and the sidebar/composer render only real model output.
- Runtime AI logs now record whether completion metadata was actually parsed, along with the parsed summary/next-focus/suggestion counts, so the next real request can confirm whether the remote model is returning suggestions or the UI is simply receiving an empty block.
- Crash tracing logs were added around the first-draft patch path so the next reproduce cycle can tell whether the segfault happens before `WritingEditPatch.init` finishes or inside one of its field assignments.
- If you touch the file document parser or save flow, keep `xattr` as the first identity source, fall back to the hidden body marker only when needed, and make sure missing or malformed metadata still degrades to正文-only editing instead of blocking open/save.
- If you touch collaboration state persistence, keep the latest 20 conversation rounds plus the `localSummary` and `globalSynopsis` in sync with the metadata store.
