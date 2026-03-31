# VibeWrite Project Context

## What this project is
VibeWrite is a minimal AI writing collaborator for macOS, built as a SwiftUI app.

The MVP goal is to validate a dialogue-driven writing workflow:
- users can start by writing a prompt or by discussing the direction first
- the app keeps the writing experience centered on the document, not on chat
- the UI should feel native to macOS: calm, polished, and lightweight

## What this project is not
- not a general-purpose AI chat app
- not a heavy writing suite
- not a project-management tool
- not a multi-document content library

## Current implementation status
- The repository now contains a macOS SwiftUI app scaffold organized in an Xcode-like directory shape, with both a Swift Package source tree and an Xcode project wrapper.
- M2 is implemented as a front-end interaction skeleton on top of the M1 layout.
- task/TASK_20260331_003 added automation support code: stable accessibility identifiers, light accessibility refinements, a minimal test target, and deterministic flow tests for the main quick-start paths.
- task003 was fixed after review: the discussion-mode start-draft identifier now lives only on the actual button, and the repository now includes a dedicated macOS XCUI target that passes a real UI automation flow.
- M3 is implemented as a local project-library and context-driven persistence layer:
  - `WritingProject` now carries a fixed `ProjectContext`
  - the app persists local projects and the last opened project
  - the home screen reads recent projects from local storage
  - the project screen shows a lightweight context summary from the project model
  - UI tests launch with an isolated temporary storage URL so the home flow stays deterministic
- M4 code is in place as a real AI integration layer, and task006 has been independently reviewed and accepted:
  - `Shared/AI/` now contains a provider abstraction, structured request/response models, a prompt builder, a remote MiniMax client, and a stub client for tests
  - the app defaults to real AI mode, with `MiniMax-M2.7` and `https://api.minimax.io/v1` configured in the Xcode config layer
  - AI responses now feed back into the active writing project, updating the document text, conversation, project context, and suggestion chips
  - start-draft requests are normalized so the same prompt only appears once in the request context and visible conversation
  - collaboration submissions preserve the user's draft until the request succeeds, instead of clearing input on failure
  - UI tests continue to run in stub mode so they stay deterministic and offline-safe
- Home screen includes:
  - direct draft start
  - discuss-first start
  - recent project cards
  - inspiration examples
- Writing project screen includes:
  - discussion mode
  - collaboration mode
  - left conversation/context column
  - right document column
  - selection-action and revision skeletons
- Mock data is in place.
- The document editor is editable locally, and mock interaction flows update the正文 plus the local project context in memory before persisting.
- Local persistence is wired up with a compact JSON project store in Application Support, plus a launch override for UI tests.
- M1 and M2 have been accepted.
- task003 is reviewed, fixed, and verified with `xcodebuild test`.
- M3 has been implemented and verified with `swift test` and `xcodebuild test`.
- task004 has now been independently reviewed against the latest workspace code and accepted.
- M4 code has been implemented and verified with `swift test` and `xcodebuild test`, and task006 is accepted.

## Key files
- `Package.swift`
- `VibeWrite.xcodeproj/project.pbxproj`
- `VibeWrite.xcodeproj/xcshareddata/xcschemes/VibeWrite.xcscheme`
- `Sources/VibeWriteApp/App/VibeWriteApp.swift`
- `Sources/VibeWriteApp/App/RootShellView.swift`
- `Sources/VibeWriteApp/Shared/Models/VibeWriteModels.swift`
- `Sources/VibeWriteApp/Shared/Models/MockWritingEngine.swift`
- `Sources/VibeWriteApp/Shared/Theme/VibeWriteTheme.swift`
- `Sources/VibeWriteApp/Features/Home/HomeView.swift`
- `Sources/VibeWriteApp/Features/Project/WritingProjectView.swift`
- `Sources/VibeWriteApp/Shared/Automation/VibeWriteAutomationID.swift`
- `Sources/VibeWriteApp/App/VibeWriteAppFlow.swift`
- `Sources/VibeWriteApp/App/LocalProjectStore.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIModels.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIPromptBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingAIConfiguration.swift`
- `Sources/VibeWriteApp/Shared/AI/WritingProjectResponseBuilder.swift`
- `Sources/VibeWriteApp/Shared/AI/StubWritingAIClient.swift`
- `Sources/VibeWriteApp/Shared/AI/RemoteWritingAIClient.swift`
- `Tests/VibeWriteAppTests/VibeWriteAppFlowTests.swift`
- `UITests/VibeWriteUITests.swift`
- `docs/AGENTS.md`
- `docs/VibeWrite MVP PRD.md`
- `docs/VibeWrite MVP IA.md`
- `docs/VibeWrite MVP Wireframes.md`
- `docs/VibeWrite MVP Milestones.md`
- `task/TASK_20260331_001.md`
- `task/TASK_20260331_003.md`
- `task/TASK_20260331_004.md`
- `task/TASK_20260331_005.md`
- `task/TASK_20260401_006.md`

## Verified commands
- `swift build`
- `swift test`
- `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'`

## Runtime notes
- The app uses a Swift Package source tree plus an Xcode project wrapper for app and UI test execution.
- Persistence is stored locally in `Application Support/VibeWrite/local-project-store.json`, or in a test-specific path when `VIBEWRITE_STORAGE_URL` is set.
- AI configuration is wired through the Xcode config layer and also falls back to the process environment at runtime.
- The app defaults to real AI mode, but tests continue to inject stub mode so they remain offline-safe and deterministic.
- The local MiniMax API key is stored in a gitignored local xcconfig file and is not committed.
- Current state combines local JSON persistence with a real AI client abstraction and stubbed test paths.

## Working rules for future agents
- Follow `docs/AGENTS.md` and the task file before expanding scope.
- Keep the product minimal and writing-focused.
- Preserve the two-mode project screen and the home screen entry points.
- Do not turn the app into a generic chat UI or a feature-heavy writing suite.
- Prefer small, reversible changes and verify with the smallest meaningful build check.
