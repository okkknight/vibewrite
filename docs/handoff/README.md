# Handoff Readme

This directory is the compact handoff layer for VibeWrite.

## Read order
1. `PROJECT_CONTEXT.md`
2. `docs/handoff/CHANGELOG.md`
3. `task/TASK_20260401_006.md`

## Purpose
- keep the project easy to resume
- record durable implementation changes
- avoid duplicating the same status across many notes

## Current state
- M2 is implemented as a SwiftUI macOS interaction skeleton on top of the M1 layout.
- task003 added automation support code: stable accessibility identifiers, accessibility polish, a minimal test target, and deterministic flow tests.
- task003 review was fixed: the discussion-mode start-draft identifier now exists only on the actual button, and there is a dedicated macOS `XCUI` target.
- M3 is implemented: the app now has a local project library, a fixed project context model, last-opened-project restoration, and a lightweight context summary on the writing screen.
- M4 code is in place: the app now has a real AI abstraction layer, a MiniMax remote client, structured request/response handling, and a stub path for tests, and task006 has been accepted.
- The source tree has been reorganized into an Xcode-like `App / Features / Shared` structure.
- The app builds successfully with `swift build`.
- M1 has been independently reviewed against the task and accepted.
- M2 has been reviewed and accepted.
- task003 is built, unit-tested, and UI-tested successfully.
- task004 is implemented, unit-tested, and UI-tested successfully.
- task005 is built, unit-tested, and UI-tested successfully, and task006 is built, unit-tested, and UI-tested successfully.
- `swift test` passes with the current unit test target.
- `xcodebuild test -project VibeWrite.xcodeproj -scheme VibeWrite -destination 'platform=macOS'` passes with the dedicated UI test target.
- task004 was independently verified against the current workspace code and accepted.
- task005 was independently verified against the current workspace code and found to have open review issues.
- task006 fixes those task005 review findings and has been independently reviewed and accepted after re-running `swift test` and `xcodebuild test`.

## Rule of thumb
- add only durable facts here
- do not turn this into a process log
- keep the handoff small and easy to scan
