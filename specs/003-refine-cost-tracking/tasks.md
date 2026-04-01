# Tasks: Refine Cost Tracking Precision

**Input**: Design documents from `/specs/003-refine-cost-tracking/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included — the existing test suite (`tests/test-cost-tracker.sh`) must be maintained and extended.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All runtime files live under `.claude/` following Claude Code conventions. Tests in `tests/`. Installer in `src/`.

---

## Phase 1: Setup

**Purpose**: Create test fixtures and prepare for implementation

- [ ] T001 Create test fixture `tests/fixtures/unknown-model-transcript.jsonl` with assistant messages using a model not in pricing.json (e.g., `claude-future-model-5-20260401`) — 3 assistant messages with known token counts for fallback pricing verification
- [ ] T002 [P] Create test fixture `tests/fixtures/mixed-model-transcript.jsonl` with assistant messages using both a known model (`claude-opus-4-6-20260301`) and an unknown model (`claude-unknown-5`) — for verifying per-model pricing_estimated flags in multi-model sessions

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update pricing.json to v2 — ALL user stories depend on this file's new structure

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T003 Update `.claude/cost-data/pricing.json`: replace `fallback_formula` section with new `fallback` object containing complete Sonnet-tier rates (`input_per_mtok: 3.00, output_per_mtok: 15.00, cache_read_per_mtok: 0.30, cache_write_per_mtok: 3.75, tier: "sonnet"`), per data-model.md v2 schema
- [ ] T004 Update `.claude/cost-data/pricing.json`: add `claude-opus-4-1` entry ($15/$75/$1.50/$18.75) and `claude-opus-4-` catch-all entry ($15/$75/$1.50/$18.75) for older Opus models
- [ ] T005 Update `.claude/cost-data/pricing.json`: bump `version` from 1 to 2 and `updated` to `2026-04-01`

**Checkpoint**: pricing.json v2 ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Accurate Cost Estimation for Known Models (Priority: P1) 🎯 MVP

**Goal**: Verify the pricing table uses correct, up-to-date rates for all supported model families and that existing cost calculations remain accurate.

**Independent Test**: Run the hook with `tests/fixtures/sample-transcript.jsonl` and compare calculated costs against hand-computed expected values using official Anthropic API pricing.

### Implementation for User Story 1

- [ ] T006 [US1] Verify existing pricing rates in `.claude/cost-data/pricing.json` match official Anthropic API pricing (Opus 4.6/4.5: $5/$25, Sonnet 4.6/4.5/4: $3/$15, Haiku 4.5: $1/$5) — no changes expected, document verification in a comment at top of pricing.json
- [ ] T007 [US1] Update `tests/fixtures/expected-output.json` to add expected cost values for the newly added `claude-opus-4-1` and `claude-opus-4-` pricing entries, confirming older models calculate at $15/$75 rates
- [ ] T008 [US1] Add test case in `tests/test-cost-tracker.sh`: verify cost calculation for a transcript using `claude-opus-4-6-20260301` produces the correct cost at $5/$25 input/output rates (verifies known-model pricing accuracy)

**Checkpoint**: Known-model pricing verified and tested

---

## Phase 4: User Story 2 — Fallback Pricing for Unknown Models (Priority: P2)

**Goal**: Unknown models receive a non-zero estimated cost using Sonnet-tier fallback rates, with clear `pricing_estimated` tagging on both per-model and session-level records.

**Independent Test**: Run the hook with `tests/fixtures/unknown-model-transcript.jsonl` and verify: (a) cost is non-zero, (b) `pricing_estimated: true` on model entry, (c) `pricing_estimated: true` on session record, (d) stderr warning emitted.

### Implementation for User Story 2

- [ ] T009 [US2] Modify the jq cost-calculation pipeline in `.claude/hooks/cost-tracker.sh` (lines 176–192): when no prefix match found for a model, use `$pricing.fallback` rates instead of setting `cost_usd: 0`. Add `pricing_estimated: true` to the model entry when fallback is used, `pricing_estimated: false` when exact match found
- [ ] T010 [US2] Add session-level `pricing_estimated` field to the cost record assembly in `.claude/hooks/cost-tracker.sh` (around line 222–244): set to `true` if any model entry has `pricing_estimated: true`, `false` otherwise
- [ ] T011 [US2] Update the stderr warning in `.claude/hooks/cost-tracker.sh` (lines 195–199): change message from "no pricing for model(s): X — add to pricing.json" to "no pricing match for model 'X', using fallback (sonnet-tier) — add to pricing.json" to indicate fallback was applied (not zero cost)
- [ ] T012 [US2] Update the fallback behavior when `pricing.json` is missing entirely in `.claude/hooks/cost-tracker.sh` (lines 167–173): instead of `{"models":[],...}`, use hardcoded Sonnet-tier defaults as the fallback object so all models get estimated costs, and set `pricing_estimated: true` on all model entries
- [ ] T013 [US2] Add test case in `tests/test-cost-tracker.sh`: run hook with `tests/fixtures/unknown-model-transcript.jsonl` — assert cost > 0, assert `pricing_estimated` is `true` on both model entry and session, assert stderr contains "using fallback"
- [ ] T014 [P] [US2] Add test case in `tests/test-cost-tracker.sh`: run hook with `tests/fixtures/mixed-model-transcript.jsonl` — assert known model has `pricing_estimated: false`, unknown model has `pricing_estimated: true`, session-level `pricing_estimated: true`
- [ ] T015 [P] [US2] Add test case in `tests/test-cost-tracker.sh`: run hook with pricing file deleted — assert all models get non-zero cost and all `pricing_estimated: true`

**Checkpoint**: Unknown models produce estimated costs with clear tagging

---

## Phase 5: User Story 3 — Turn Count and Total Tokens Tracking (Priority: P3)

**Goal**: Each cost record includes `turns` (number of API calls) and `total_tokens` (sum of all four token types) at both per-model and session levels.

**Independent Test**: Run the hook with `tests/fixtures/sample-transcript.jsonl` (known number of deduplicated assistant messages) and verify `turns` and `total_tokens` match expected values.

### Implementation for User Story 3

- [ ] T016 [US3] Add `turns` computation to `.claude/hooks/cost-tracker.sh`: after the `ALL_USAGE` variable is set (around line 130), compute `TURNS` as the count of entries in the deduplicated usage array (e.g., `echo "$ALL_USAGE" | jq 'length'`)
- [ ] T017 [US3] Add per-model `total_tokens` computation to the MODEL_USAGE aggregation in `.claude/hooks/cost-tracker.sh` (lines 151–163): add field `total_tokens: (.input_tokens + .output_tokens + .cache_read_tokens + .cache_write_tokens)` to each model object
- [ ] T018 [US3] Add session-level `total_tokens` computation in `.claude/hooks/cost-tracker.sh`: compute `TOTAL_TOKENS` as sum of all per-model `total_tokens` values (e.g., `echo "$MODEL_USAGE_WITH_COST" | jq '[.[].total_tokens] | add // 0'`)
- [ ] T019 [US3] Add `turns` and `total_tokens` fields to the cost record JSON assembly in `.claude/hooks/cost-tracker.sh` (lines 222–244): add `--argjson turns "$TURNS"` and `--argjson total_tokens "$TOTAL_TOKENS"` to the `jq -cn` call
- [ ] T020 [US3] Add test case in `tests/test-cost-tracker.sh`: verify `turns` equals the expected count of deduplicated assistant messages from `tests/fixtures/sample-transcript.jsonl`
- [ ] T021 [P] [US3] Add test case in `tests/test-cost-tracker.sh`: verify per-model `total_tokens` equals `input_tokens + output_tokens + cache_read_tokens + cache_write_tokens` for each model in a sample session
- [ ] T022 [P] [US3] Add test case in `tests/test-cost-tracker.sh`: verify session-level `total_tokens` equals the sum of all per-model `total_tokens` values

**Checkpoint**: Turn count and total tokens tracked accurately

---

## Phase 6: User Story 4 — Pricing Audit Trail (Priority: P4)

**Goal**: Each cost record includes `pricing_version` sourced from the `version` field in `pricing.json`, enabling audit trails across pricing changes.

**Independent Test**: Run the hook with pricing.json v2 and verify the cost record contains `"pricing_version": 2`.

### Implementation for User Story 4

- [ ] T023 [US4] Add pricing version extraction to `.claude/hooks/cost-tracker.sh`: after loading `PRICING` (around line 168), extract `PRICING_VERSION=$(echo "$PRICING" | jq '.version // 0')` — defaults to 0 when the field is missing
- [ ] T024 [US4] Add `pricing_version` to the cost record JSON assembly in `.claude/hooks/cost-tracker.sh` (lines 222–244): add `--argjson pricing_version "$PRICING_VERSION"` and include `pricing_version: $pricing_version` in the output object
- [ ] T025 [US4] Add test case in `tests/test-cost-tracker.sh`: verify `pricing_version` in the output record matches the `version` field in the test pricing.json
- [ ] T026 [P] [US4] Add test case in `tests/test-cost-tracker.sh`: verify `pricing_version` defaults to `0` when the pricing.json has no `version` field

**Checkpoint**: Pricing version tracked in all cost records

---

## Phase 7: User Story 5 — Standardized Cost Precision (Priority: P5)

**Goal**: All USD cost values formatted to exactly 4 decimal places, aligning with the Rust source's `format_usd()` behavior.

**Independent Test**: Run the hook and verify cost values in the output record have exactly 4 decimal places.

### Implementation for User Story 5

- [ ] T027 [US5] Change cost rounding in `.claude/hooks/cost-tracker.sh` cost calculation pipeline (around line 182–187): replace `* 1000000 | round | . / 1000000` with `* 10000 | round | . / 10000` for per-model `cost_usd`
- [ ] T028 [US5] Change total cost rounding in `.claude/hooks/cost-tracker.sh` (around line 202): replace `* 1000000 | round | . / 1000000` with `* 10000 | round | . / 10000` for session `total_cost_usd`
- [ ] T029 [US5] Update `tests/fixtures/expected-output.json`: change all expected cost values from 6-decimal to 4-decimal precision
- [ ] T030 [US5] Update all existing test assertions in `tests/test-cost-tracker.sh` that compare cost values: adjust expected values to 4 decimal places
- [ ] T031 [US5] Add test case in `tests/test-cost-tracker.sh`: verify a cost that would have more than 4 decimal places is correctly rounded (e.g., verify `0.1235` not `0.123456`)

**Checkpoint**: All cost values use consistent 4-decimal precision

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Update consumer-facing components (slash commands, installer) and validate end-to-end

- [ ] T032 [P] Update `.claude/commands/cost-report.md`: add instructions for Claude to display `turns`, `total_tokens`, `pricing_version`, and `pricing_estimated` indicator (`*` for estimated models) in the report summary and per-model table; handle missing fields for old records gracefully
- [ ] T033 [P] Update `.claude/commands/cost-session.md`: add instructions for Claude to display `turns`, `total_tokens`, pricing version/estimated status in session detail view; handle missing fields for old records gracefully
- [ ] T034 Update `src/install.sh`: replace embedded `pricing.json` heredoc with v2 content (fallback section, new Opus entries, version 2)
- [ ] T035 Update `src/install.sh`: replace embedded `cost-tracker.sh` heredoc with the updated hook containing all changes (fallback pricing, turns, total_tokens, pricing_version, pricing_estimated, 4-decimal precision)
- [ ] T036 Update `src/install.sh`: replace embedded `cost-report.md` and `cost-session.md` heredocs with updated slash command content
- [ ] T037 Run full test suite `bash tests/test-cost-tracker.sh` — verify all existing and new tests pass
- [ ] T038 Run quickstart.md validation: manually verify upgrade path works (re-run installer, check new fields appear in output)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No dependencies on Phase 1 — can start in parallel with Setup
- **User Stories (Phases 3–7)**: All depend on Foundational phase (Phase 2) completion
  - US1–US4 can proceed in parallel (modify different sections of the hook)
  - US5 (precision change) affects test assertions across all stories — **recommend implementing US5 first or last** (see Implementation Strategy)
- **Polish (Phase 8)**: Depends on all user story phases being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US2 (P2)**: Can start after Phase 2 — no dependencies on other stories (modifies cost calculation pipeline — avoid parallel edits with US5)
- **US3 (P3)**: Can start after Phase 2 — no dependencies on other stories (modifies record assembly — avoid parallel edits with US4)
- **US4 (P4)**: Can start after Phase 2 — no dependencies on other stories
- **US5 (P5)**: Can start after Phase 2 — **note**: changes rounding that affects test assertions in US1–US4 tests

### Within Each User Story

- Implementation tasks before test tasks (when tests verify the implementation)
- Hook changes before test updates
- All test tasks marked [P] within a story can run in parallel

### Parallel Opportunities

- T001 and T002 (fixture creation) can run in parallel
- T003, T004, T005 (pricing.json updates) are sequential (same file)
- T032 and T033 (slash command updates) can run in parallel
- Test tasks within each story marked [P] can run in parallel

---

## Parallel Example: User Story 2

```bash
# After T009–T012 (hook implementation) complete:

# Launch parallel test tasks:
Task T014: "Test mixed known/unknown models in tests/test-cost-tracker.sh"
Task T015: "Test missing pricing file fallback in tests/test-cost-tracker.sh"
# (T013 runs before these as it validates the core functionality)
```

## Parallel Example: User Story 3

```bash
# After T016–T019 (hook implementation) complete:

# Launch parallel test tasks:
Task T021: "Test per-model total_tokens in tests/test-cost-tracker.sh"
Task T022: "Test session-level total_tokens in tests/test-cost-tracker.sh"
```

---

## Implementation Strategy

### Recommended Execution Order

Because US5 (precision change) affects test expected values across all stories, the recommended order is:

1. **Phase 1 + Phase 2** (Setup + Foundational) — in parallel
2. **US5 first** (Phase 7: T027–T031) — change precision before writing new test assertions, so all new tests use 4-decimal values from the start
3. **US1** (Phase 3: T006–T008) — verify pricing
4. **US2** (Phase 4: T009–T015) — biggest implementation change
5. **US3** (Phase 5: T016–T022) — add turns and total_tokens
6. **US4** (Phase 6: T023–T026) — add pricing_version
7. **Phase 8** (Polish) — update slash commands and installer last

### MVP First (User Story 1 + 2 Only)

1. Complete Phase 1 + Phase 2
2. Complete US5 (precision — enables clean test baselines)
3. Complete US1 (verify pricing) → validates core accuracy
4. Complete US2 (fallback pricing) → eliminates $0 for unknown models
5. **STOP and VALIDATE**: Run full test suite
6. This delivers the most impactful improvements with minimal scope

### Incremental Delivery

1. Setup + Foundational → pricing.json v2 ready
2. US5 → precision standardized → test baseline clean
3. US1 → pricing verified → confidence in accuracy
4. US2 → fallback pricing → no more $0 for unknown models (MVP!)
5. US3 → turns + total_tokens → richer analytics
6. US4 → pricing_version → full audit trail
7. Polish → slash commands + installer updated → release ready

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in same phase
- [Story] label maps task to specific user story for traceability
- All changes modify existing files — no new source files (only new test fixtures)
- The hook file (`.claude/hooks/cost-tracker.sh`) is modified by US2, US3, US4, and US5 — avoid parallel edits to this file across stories
- Commit after each story phase completes to maintain clean git history
- `rust/` directory must NOT be modified (FR-012)
