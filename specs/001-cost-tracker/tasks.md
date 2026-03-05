# Tasks: Claude Code Cost Tracker

**Input**: Design documents from `/specs/001-cost-tracker/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested. Test fixtures included where they aid validation.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3, US4)
- Exact file paths included in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory structure, pricing data, and hook configuration

- [x] T001 Create directory structure: `.claude/hooks/`, `.claude/commands/`, `.claude/cost-data/`, `tests/fixtures/`
- [x] T002 [P] Create pricing configuration with Opus/Sonnet/Haiku rates and fallback formula in `.claude/cost-data/pricing.json` per data-model.md pricing.json spec
- [x] T003 [P] Add Stop hook configuration to `.claude/settings.local.json` per hook-contract.md settings schema, merging with any existing content

---

## Phase 2: User Story 1 - Track Cost Per Conversation (Priority: P1) MVP

**Goal**: Automatically capture cost data (tokens, durations, code changes, cost) after each Claude response via a Stop hook that parses the session transcript.

**Independent Test**: Run a Claude Code conversation in the project. After the conversation, check `.claude/cost-data/sessions.jsonl` for a cost record with correct model, token counts, and calculated cost.

### Implementation for User Story 1

- [x] T004 [US1] Create hook script skeleton in `.claude/hooks/cost-tracker.sh`: read JSON from stdin, extract `session_id`/`transcript_path`/`stop_hook_active`, validate `jq` is available, exit early if `stop_hook_active` is true, make file executable
- [x] T005 [US1] Implement transcript JSONL parsing in `.claude/hooks/cost-tracker.sh`: read transcript file line by line, filter for `type: "assistant"` messages, extract `message.model` and `message.usage` fields (input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens), aggregate totals per model using jq
- [x] T006 [US1] Implement pricing lookup and cost calculation in `.claude/hooks/cost-tracker.sh`: read `.claude/cost-data/pricing.json`, match model names by prefix against `model_pattern`, calculate per-model cost as `(input * input_per_mtok + output * output_per_mtok + cache_read * cache_read_per_mtok + cache_write * cache_write_per_mtok) / 1000000`, sum for total cost, use fallback formula for unknown models with warning to stderr
- [x] T007 [US1] Implement duration calculation in `.claude/hooks/cost-tracker.sh`: extract first and last message timestamps from transcript for wall duration, calculate API duration by summing time deltas between consecutive user→assistant message pairs, output as milliseconds
- [x] T008 [US1] Implement code change tracking in `.claude/hooks/cost-tracker.sh`: scan transcript for tool_use entries with `Edit`/`Write` tools, count lines added/removed from tool results (count `+` and `-` prefixed lines in diffs, count total lines for new file writes), default to 0 if no code changes detected
- [x] T009 [US1] Implement cost record assembly and JSONL append in `.claude/hooks/cost-tracker.sh`: build JSON object matching Cost Record schema from data-model.md (session_id, timestamp, session_start, session_end, api_duration_ms, wall_duration_ms, lines_added, lines_removed, total_cost_usd, models array), append single line to `.claude/cost-data/sessions.jsonl`, create cost-data directory if missing
- [x] T010 [US1] Create sample transcript fixture in `tests/fixtures/sample-transcript.jsonl` with realistic multi-model session data (Opus + Haiku messages with usage fields) and expected output in `tests/fixtures/expected-output.json`, validate hook produces correct output by running: `echo '{"session_id":"test-123","transcript_path":"tests/fixtures/sample-transcript.jsonl","stop_hook_active":false}' | .claude/hooks/cost-tracker.sh`

**Checkpoint**: Hook fires on every Claude response and appends accurate cost records to sessions.jsonl. US1 is MVP-complete.

---

## Phase 3: User Story 2 - Generate Cost Summary Report (Priority: P2)

**Goal**: Provide a `/cost-report` slash command that displays an aggregate summary in the conversation and saves a detailed markdown report file.

**Independent Test**: Populate `.claude/cost-data/sessions.jsonl` with sample data, run `/cost-report`, verify conversation shows totals and `.claude/cost-data/report.md` is generated with daily + per-session breakdowns.

### Implementation for User Story 2

- [x] T011 [US2] Create `/cost-report` slash command in `.claude/commands/cost-report.md` with YAML frontmatter (name: cost-report, description), dynamic context injection using `!` backtick syntax to read `.claude/cost-data/sessions.jsonl` and `.claude/cost-data/pricing.json`, instructions for Claude to: deduplicate by session_id (latest wins), aggregate totals (cost, durations, code changes, tokens by type), format conversation summary per contracts/slash-commands.md report structure, write detailed report with daily and per-session tables to `.claude/cost-data/report.md`, handle empty data case with "No cost data recorded yet" message

**Checkpoint**: `/cost-report` command available and produces accurate summary + file output.

---

## Phase 4: User Story 3 - View Cost for Current Session (Priority: P3)

**Goal**: Provide a `/cost-session` slash command that displays cost details for the most recent or a specific session.

**Independent Test**: With cost data present, run `/cost-session` and verify it shows the latest session's cost breakdown. Run `/cost-session <session-id>` to verify specific session lookup.

### Implementation for User Story 3

- [x] T012 [US3] Create `/cost-session` slash command in `.claude/commands/cost-session.md` with YAML frontmatter (name: cost-session, description, argument-hint: [session-id]), dynamic context injection to read `.claude/cost-data/sessions.jsonl`, instructions for Claude to: if `$ARGUMENTS` provided find matching session_id, else use session with latest session_end, deduplicate by session_id, display formatted single-session breakdown per contracts/slash-commands.md display structure, handle empty data and session-not-found cases

**Checkpoint**: `/cost-session` command available, shows latest or specific session details.

---

## Phase 5: User Story 4 - Reset or Clear Cost Data (Priority: P4)

**Goal**: Provide a `/cost-reset` slash command that clears accumulated cost data with a confirmation step.

**Independent Test**: With cost data present, run `/cost-reset` to see confirmation prompt. Run `/cost-reset confirm` to verify data is deleted and subsequent `/cost-report` shows no data.

### Implementation for User Story 4

- [x] T013 [US4] Create `/cost-reset` slash command in `.claude/commands/cost-reset.md` with YAML frontmatter (name: cost-reset, description, argument-hint: [confirm]), dynamic context injection to read session count from `.claude/cost-data/sessions.jsonl`, instructions for Claude to: if `$ARGUMENTS` does not contain "confirm" show data summary and ask user to run `/cost-reset confirm`, if "confirm" present then delete `.claude/cost-data/sessions.jsonl` and `.claude/cost-data/report.md` using Bash tool and display confirmation with count of sessions removed

**Checkpoint**: `/cost-reset` command available with two-step confirmation flow.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Error handling, edge cases, and validation

- [x] T014 Add malformed JSONL line handling in `.claude/hooks/cost-tracker.sh`: wrap transcript line parsing in error handling, skip unparseable lines with warning to stderr, continue processing remaining lines
- [x] T015 Add concurrent write safety in `.claude/hooks/cost-tracker.sh`: ensure JSONL append is atomic (single echo/printf with newline), verify cost-data directory exists before write
- [x] T016 Create validation test script in `tests/test-cost-tracker.sh`: run hook against sample fixture, compare output to expected-output.json, check exit codes, validate JSON structure of output record, report pass/fail

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - start immediately
- **US1 (Phase 2)**: Depends on Setup (T001-T003 complete). This is the MVP.
- **US2 (Phase 3)**: Can start after Setup (only needs data format knowledge from data-model.md). Implementation is parallel with US1, but validation requires US1 data.
- **US3 (Phase 4)**: Same as US2 - parallel implementation, sequential validation.
- **US4 (Phase 5)**: Same - parallel implementation, sequential validation.
- **Polish (Phase 6)**: Depends on US1 being complete (modifies hook script).

### User Story Dependencies

- **US1 (P1)**: No dependencies on other stories. Core MVP.
- **US2 (P2)**: Reads data produced by US1. Implementation parallel, testing sequential.
- **US3 (P3)**: Reads data produced by US1. Implementation parallel, testing sequential.
- **US4 (P4)**: Deletes data produced by US1. Implementation parallel, testing sequential.

### Within User Story 1

- T004 (skeleton) → T005 (parsing) → T006 (cost calc) → T007 (durations) → T008 (code changes) → T009 (record writing) → T010 (validation)
- Tasks are sequential because they all modify the same file (`.claude/hooks/cost-tracker.sh`)

### Parallel Opportunities

```
After Setup (Phase 1) completes:

  ┌─ US1: T004→T005→T006→T007→T008→T009→T010 (sequential, same file)
  │
  ├─ US2: T011 (independent file: cost-report.md)
  │
  ├─ US3: T012 (independent file: cost-session.md)
  │
  └─ US4: T013 (independent file: cost-reset.md)

After US1 completes:
  └─ Polish: T014→T015→T016 (sequential, same file + test)
```

---

## Parallel Example: After Setup

```
# These can all be worked on simultaneously (different files):
Task T004-T010: Hook script implementation in .claude/hooks/cost-tracker.sh
Task T011: /cost-report command in .claude/commands/cost-report.md
Task T012: /cost-session command in .claude/commands/cost-session.md
Task T013: /cost-reset command in .claude/commands/cost-reset.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: US1 - Hook Script (T004-T010)
3. **STOP and VALIDATE**: Run a Claude Code conversation, verify cost record appears in sessions.jsonl
4. MVP is usable — costs are tracked even without reporting commands

### Incremental Delivery

1. Setup (T001-T003) → Foundation ready
2. US1 (T004-T010) → Cost tracking works → **MVP!**
3. US2 (T011) → `/cost-report` available → Full reporting
4. US3 (T012) → `/cost-session` available → Quick session view
5. US4 (T013) → `/cost-reset` available → Data management
6. Polish (T014-T016) → Robustness and validation

---

## Notes

- All slash commands (US2-US4) are markdown files that instruct Claude — they don't contain executable logic themselves
- The hook script (US1) is the only executable code — it's a bash script using jq
- [P] tasks within Setup can run in parallel; US1 tasks are sequential (same file)
- US2/US3/US4 are each a single task (one markdown file each) and can be done in parallel
- Commit after each completed phase for clean history
- The `stop_hook_active` guard in T004 is critical to prevent infinite loops
