# Changelog

## 2026-04-01
- Fixed the task005 review issues by keeping collaboration drafts intact until the AI request succeeds, so failed submissions no longer clear the user's input prematurely.
- Normalized start-draft request construction so the same prompt no longer appears multiple times in the AI request context or visible conversation.
- Added unit tests that cover failure-state state preservation and start-draft prompt de-duplication, then re-ran `swift test` successfully.
- Re-ran `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` successfully to verify the macOS UI test flow still passes.
- Independently reviewed task006 and accepted it after confirming the latest workspace code includes the failure-state preservation and start-draft de-duplication fixes.

## 2026-03-31
- Created the initial VibeWrite SwiftUI macOS app scaffold.
- Implemented M1 home and writing project screens with mock data.
- Added a clean SwiftUI theme layer, reusable surface components, and basic screen routing.
- Verified the project builds successfully with `swift build`.
- Reorganized the source tree into an Xcode-like `App / Features / Shared` directory shape.
- Reviewed M1 against the task acceptance criteria and confirmed the home flow, project flow, and dual-mode writing-project skeleton are present.
- Ran `swift test`; no test targets exist yet, so there is no automated test coverage for this milestone.
- Implemented M2 interaction skeletons: direct start and discuss-first flow, mock draft generation, mock revisions, selection-to-dialogue entry, undo/compare/retry controls, and clickable suggestion chips.
- Added a local mock writing engine to keep interaction behavior deterministic without real AI or persistence.
- Verified M2 with `swift build`.
- Implemented M3 automation coverage: stable accessibility identifiers for the main home and project controls, a lightweight app-flow object for testable navigation, and a minimal XCTest target covering the quick-start paths and mock revision helper.
- Added accessibility-identifier handling that is safe for optional labels and preserved the existing visual structure.
- Verified M3 with `swift build` and `swift test`.
- Reviewed task003 and found an ambiguous automation target: the discussion-mode start-draft identifier is attached to both the empty-state wrapper and the actual button, so UI automation cannot rely on it unambiguously yet.
- Reviewed task003 and noted the test coverage remains unit-level; there is still no dedicated `XCUI` target for real UI automation.
- Updated the project state to clarify that task003 is automation support work, while the milestone M3 in the roadmap (local project-context drive) has not started yet.
- Fixed task003 review feedback by removing the duplicated `project.startDraftButton` accessibility identifier from the empty-state wrapper so only the actual button owns it.
- Converted the project to a runnable Xcode app target with a dedicated macOS UI test target and enabled local code signing for the app and test runner so `VibeWriteUITests-Runner.app` launches cleanly.
- Verified the UI test flow with `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`, which now passes.
- Implemented M3 local persistence: `WritingProject` now carries a fixed `ProjectContext`, the app persists a local project library and the last opened project, and the home screen reads real recent projects from local storage.
- Added a compact project store backed by JSON in Application Support, plus a `VIBEWRITE_STORAGE_URL` override so UI tests can launch against an isolated temporary store.
- Updated the writing project screen to show a lightweight context summary from the persisted project model instead of static placeholder context.
- Added a persistence-focused unit test that verifies a project survives a restart and restores as the last opened project.
- Verified M3 with `swift test` and `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`.
- Independently reviewed task004 against the latest workspace code and accepted it after re-running `swift test` and `xcodebuild test`.
- Added M4 real AI integration with a provider abstraction, structured request/response models, a prompt builder, a remote MiniMax client, and a stub client for tests.
- Wired the app to default to real AI mode while keeping UI tests on stub mode and preserving offline determinism.
- Stored the local MiniMax API key in a gitignored xcconfig file and wired the Xcode project back to read the config layer.
- Verified task005 with both `swift test` and `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`.
- Independently reviewed task005 and found an issue where the collaboration flow clears the prompt before the async AI request finishes, which can lose the user's input on failure.
- Independently reviewed task005 and found an issue where start-draft flows can duplicate the same prompt in the conversation/context because the prompt is seeded before `performWritingAction` appends it again.
