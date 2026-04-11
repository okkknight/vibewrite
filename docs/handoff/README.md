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
22. `docs/V3/AGENTS.md`
23. `docs/V3/PRD3.0.md`
24. `docs/V3/IA3.0.md`
25. `docs/V3/ROADMAP3.0.md`
26. `task/TASK_20260411_025.md`
27. `task/TASK_20260411_026.md`
28. `docs/V3/FRONTEND3.0.md`
29. `docs/V3/BACKEND3.0.md`
30. `docs/V3/DATA3.0.md`
31. `docs/V3/API3.0.md`
32. `docs/V3/ADMIN3.0.md`
33. `docs/V3/DEPLOY3.0.md`
34. `docs/V3/MIGRATION3.0.md`

## Purpose
- keep the project easy to resume
- record durable implementation changes
- avoid duplicating the same status across many notes

## Current state
- V2 docs under `docs/V2/` remain archival reference for the current runtime behavior; `docs/V1/` is archival only.
- V3 planning docs define the frontend/backend split target, backend AI gateway, data model, deployment shape, roadmap order, and migration order, but the runtime implementation is still the current V2 client.
- `task/TASK_20260411_025.md` is the first Phase 1 execution card; `task/TASK_20260411_026.md` is the next shared-module card and promotes the pure shared model boundary into `VibeWriteShared`.
- `Sources/VibeWriteApp/Shared/AI/WritingAIContracts.swift` currently holds the contract/DTO types, while `WritingAIModels.swift` still keeps the decoder, helper, and default implementation logic.
- The正文 editor now binds directly to `activeDocumentText` as the live session text, while `WritingProject` keeps the persisted metadata/snapshot shell.
- Save now writes the live session snapshot (`activeEditingProject`) directly, so `Cmd+S` reads the same正文 the editor shows instead of relying on a last-second window flush.
- `startDraft` and `continueWriting` now use a two-phase AI flow: prose request first, then a separate metadata request that starts as soon as the backend prose result is available; metadata updates `summary`, `nextFocus`, and `suggestionChips` only after the prose phase succeeds.
- The app still needs the shared-module split work before any backend gateway lands, and the current handoff notes should be read together with the V3 roadmap rather than in isolation.

## Notes
- The durable historical log lives in `docs/handoff/CHANGELOG.md`.
- If you are picking up implementation work, follow the V3 roadmap and the numbered task cards in order.
