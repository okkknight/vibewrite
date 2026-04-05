# AI Sample Log

This file collects representative AI request/response samples for continuation debugging.

## 2026-04-05

### Success sample 1
- Time: `2026-04-05 21:25:25` request, `21:25:39` response
- Action: `continueWriting`
- User input: `描写陆鸣洲成为上司后的第一次工作交集`
- Prompt stats:
  - `promptLength=18`
  - `conversationCount=2`
  - `documentCount=319`
  - `continuationSummaryCount=61`
  - `summaryCount=61`
  - `nextFocusCount=32`
  - `recentDecisionCount=2`
  - `workingMemoryCount=2`
  - `styleConstraintCount=4`
- Response stats:
  - `bodyLength=485`
  - `metadataLength=214`
  - `metadata parsed=true`
  - `suggestionCount=3`

### Success sample 2
- Time: `2026-04-05 21:25:56` request, `21:26:13` response
- Action: `continueWriting`
- User input: `加入其他同事视角丰富互动层次`
- Prompt stats:
  - `promptLength=14`
  - `conversationCount=4`
  - `documentCount=804`
  - `continuationSummaryCount=74`
  - `summaryCount=74`
  - `nextFocusCount=32`
  - `recentDecisionCount=2`
  - `workingMemoryCount=2`
  - `styleConstraintCount=4`
- Response stats:
  - `bodyLength=533`
  - `metadataLength=217`
  - `metadata parsed=true`
  - `suggestionCount=3`

## Notes
- Both samples returned a complete prose body plus metadata.
- These samples are useful for comparing against failures where `metadataLength=0`.
