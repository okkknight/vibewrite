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
28. `task/TASK_20260411_027.md`
29. `task/TASK_20260411_028.md`
30. `task/TASK_20260412_029.md`
31. `task/TASK_20260412_030.md`
32. `task/TASK_20260412_031.md`
33. `task/TASK_20260412_032.md`
34. `task/TASK_20260412_033.md`
35. `docs/V3/FRONTEND3.0.md`
36. `docs/V3/BACKEND3.0.md`
37. `docs/V3/DATA3.0.md`
38. `docs/V3/API3.0.md`
39. `docs/V3/ADMIN3.0.md`
40. `docs/V3/DEPLOY3.0.md`
41. `docs/V3/MIGRATION3.0.md`

## Purpose
- keep the project easy to resume
- record durable implementation changes
- avoid duplicating the same status across many notes

## Current state
- `task/TASK_20260411_027.md`, `task/TASK_20260411_028.md`, `task/TASK_20260412_029.md`, `task/TASK_20260412_030.md`, `task/TASK_20260412_031.md`, and `task/TASK_20260412_032.md` are now in place in the repo: `Backend/` exists as an independent SwiftPM package, it links the root `VibeWriteShared` package, it exposes the `/v3/health` and `/v3/client/bootstrap` bootstrap-only backend skeleton with in-memory device-token reuse, and it now also wires `POST /v3/writes/start`, `POST /v3/writes/continue`, and `POST /v3/writes/edit` through a route-neutral backend-only transport envelope with bootstrap token validation plus deterministic stub `WritingAIResponse` responses, plus an in-memory quota gate and an in-memory request log store across all three write routes. `task/TASK_20260412_033.md` is the next Phase 1 execution card and turns that request log store into a queryable in-memory read model for later admin query work.
- V2 docs under `docs/V2/` remain archival reference for the current runtime behavior; `docs/V1/` is archival only.
- V3 planning docs define the frontend/backend split target, backend AI gateway, data model, deployment shape, roadmap order, and migration order, but the runtime implementation is still the current V2 client.
- `task/TASK_20260411_025.md` is the first Phase 1 execution card; `task/TASK_20260411_026.md` is the shared-module card and now lands the pure shared model boundary in the native `VibeWriteShared` target.
- `task/TASK_20260411_027.md` is the first backend-engineering card and starts the Swift + Vapor backend skeleton with health/bootstrap only.
- `task/TASK_20260411_028.md` is the first backend AI request-route card and connects the shared request envelope to `POST /v3/writes/start` with a backend-only transport envelope and placeholder completion result.
- `task/TASK_20260412_029.md` is the backend AI request-route card and generalizes the write transport envelope so `POST /v3/writes/continue` can reuse the same bootstrap-token path.
- `task/TASK_20260412_030.md` is the backend AI request-route card and adds `POST /v3/writes/edit` on the same bootstrap-token path with selection-aware validation.
- `task/TASK_20260412_031.md` is the backend quota card and adds an in-memory quota gate across all three write routes, still without persistence or admin exposure.
- `task/TASK_20260412_032.md` is the backend request-log card and now adds an in-memory log store across all three write routes, still without persistence or admin query surfaces.
- `task/TASK_20260412_033.md` is the backend request-log-read-model card and now adds query and summary access on top of the in-memory log store, still without HTTP admin routes or persistence.
- `Sources/VibeWriteShared/Models/VibeWriteSharedModels.swift` and `Sources/VibeWriteShared/AI/WritingAIContracts.swift` now hold the pure shared model/AI contract types, while `WritingAIModels.swift` still keeps the decoder, helper, and default implementation logic.
- The正文 editor now binds directly to `activeDocumentText` as the live session text, while `WritingProject` keeps the persisted metadata/snapshot shell.
- Save now writes the live session snapshot (`activeEditingProject`) directly, so `Cmd+S` reads the same正文 the editor shows instead of relying on a last-second window flush.
- `startDraft` and `continueWriting` now use a two-phase AI flow: prose request first, then a separate metadata request that starts as soon as the backend prose result is available; metadata updates `summary`, `nextFocus`, and `suggestionChips` only after the prose phase succeeds.
- The shared-module split is now in place; the next V3 work is the backend gateway, and the current handoff notes should be read together with the V3 roadmap rather than in isolation.

## Notes
- The durable historical log lives in `docs/handoff/CHANGELOG.md`.
- If you are picking up implementation work, follow the V3 roadmap and the numbered task cards in order.
