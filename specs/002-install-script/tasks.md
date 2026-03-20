# Tasks: Cost Tracker Install Script

**Input**: Design documents from `/specs/002-install-script/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not requested in spec. No test tasks generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project structure and install script skeleton

- [x] T001 Create src/ directory and initial src/install.sh with shebang (#!/usr/bin/env bash), set -euo pipefail, argument parsing for --help and --force flags, exit code constants (0=success, 1=prereq fail, 2=cancelled, 3=file error), and output helper functions (print_header, print_success, print_error, print_warning) per contracts/installer-contract.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Embed all 5 source file contents as heredoc-writing functions. These are needed by ALL user stories.

**Important**: Use single-quoted heredoc delimiters (`cat << 'HEREDOC_EOF'`) to prevent variable expansion, preserving `$CLAUDE_PROJECT_DIR` and other shell variables in embedded content.

- [x] T002 Embed the cost-tracker.sh hook script (268 lines from .claude/hooks/cost-tracker.sh) as a write_hook_script() function using heredoc in src/install.sh
- [x] T003 Embed the three slash command files as write_command_files() function using heredocs in src/install.sh: cost-report.md (75 lines from .claude/commands/cost-report.md), cost-session.md (54 lines from .claude/commands/cost-session.md), cost-reset.md (49 lines from .claude/commands/cost-reset.md)
- [x] T004 Embed the pricing.json (53 lines from .claude/cost-data/pricing.json) as a write_pricing_config() function using heredoc in src/install.sh

**Checkpoint**: All 5 source file contents embedded. File-writing functions callable.

---

## Phase 3: User Story 1 - One-Command Installation (Priority: P1) MVP

**Goal**: A developer runs one command and gets a fully working cost tracker installation with all files created and hook configured.

**Independent Test**: Run `bash src/install.sh` in a fresh temp directory (with a `.claude/` dir) and verify all 5 files exist in correct locations, hook script is executable, settings.local.json contains the hook entry, and pricing.json is valid JSON.

### Implementation for User Story 1

- [x] T005 [US1] Implement detect_project_root() function in src/install.sh: try git rev-parse --show-toplevel first, then walk up directories looking for .claude/, then fall back to pwd
- [x] T006 [US1] Implement create_directories() function in src/install.sh: mkdir -p for .claude/hooks/, .claude/commands/, .claude/cost-data/ with error handling — detect and report permission errors with a clear user-facing message (e.g., "Permission denied: cannot create .claude/hooks/") and exit code 3 on failure
- [x] T007 [US1] Implement create_fresh_settings() function in src/install.sh: create new .claude/settings.local.json with the hook entry JSON from research.md section 6 (matcher: "", command: "$CLAUDE_PROJECT_DIR"/.claude/hooks/cost-tracker.sh, timeout: 30000)
- [x] T008 [US1] Implement print_summary() function in src/install.sh: display installation summary matching the Success Output format in contracts/installer-contract.md, including target path, status, files written, and next steps. Use "zero-overhead data capture" messaging per FR-009.
- [x] T009 [US1] Wire up main() function in src/install.sh for fresh install flow: detect_project_root → create_directories → write_hook_script → write_command_files → write_pricing_config → chmod +x cost-tracker.sh → create_fresh_settings → print_summary

**Checkpoint**: Fresh install on a clean project fully works end-to-end.

---

## Phase 4: User Story 2 - Safe Installation with Existing Configuration (Priority: P2)

**Goal**: The installer safely handles projects with existing Claude Code settings, existing cost tracker installations, and preserves all existing configuration.

**Independent Test**: Create a temp project with an existing .claude/settings.local.json containing custom permissions and other hooks, run the installer, and verify: (1) existing hooks preserved, (2) cost tracker hook added without duplication, (3) existing command files untouched, (4) .bak backups created for cost tracker files.

### Implementation for User Story 2

- [x] T010 [US2] Implement detect_install_state() function in src/install.sh: count existing files among the 5 expected targets, return FRESH (0), PARTIAL (1-4), or ALREADY_INSTALLED (5) per data-model.md state machine
- [x] T011 [US2] Implement backup_existing_files() function in src/install.sh: for each of the 5 target files that exists, create a .bak copy (cp file file.bak) before overwriting
- [x] T012 [US2] Implement merge_settings() function in src/install.sh: use the jq idempotent merge pattern from research.md section 1 to add the cost tracker Stop hook entry to existing .claude/settings.local.json, preserving all other keys and deduplicating the cost-tracker.sh hook command
- [x] T013 [US2] Implement handle_malformed_json() in src/install.sh: detect invalid JSON in settings.local.json via jq validation, create .bak backup, warn user, and create fresh settings file per contracts/installer-contract.md Malformed JSON Handling section
- [x] T014 [US2] Update main() in src/install.sh to use detect_install_state() and branch: FRESH → create_fresh_settings, PARTIAL → print repair message + backup_existing_files + write all files + merge_settings, ALREADY_INSTALLED → print update message + backup_existing_files + write all files + merge_settings

**Checkpoint**: Installer safely handles existing configs, reinstalls, and partial installs.

---

## Phase 5: User Story 3 - Prerequisite Validation (Priority: P3)

**Goal**: The installer checks all prerequisites before installing and provides clear, actionable feedback if something is missing.

**Independent Test**: (1) Temporarily rename jq and run installer — verify it reports jq missing with OS-specific install instructions and exits code 1 without creating files. (2) Run from a directory with no .claude/ — verify it warns and prompts for confirmation.

### Implementation for User Story 3

- [x] T015 [US3] Implement check_prerequisites() function in src/install.sh: check jq via `command -v jq`, detect OS via `uname -s` for install instructions (brew for Darwin, apt for Linux), check bash version via BASH_VERSINFO. Exit code 1 on failure per contract.
- [x] T016 [US3] Implement handle_no_claude_dir() in src/install.sh: when .claude/ directory not found at project root, warn user and prompt for confirmation to create it. Read from /dev/tty when stdin is piped (curl | bash). With --force flag, skip prompt and proceed.
- [x] T017 [US3] Wire check_prerequisites() into main() as the first step in src/install.sh, before detect_project_root(). Wire handle_no_claude_dir() after root detection but before create_directories().

**Checkpoint**: All prerequisite failures are caught and reported before any files are touched.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: README update and end-to-end validation

- [x] T018 Update README.md Installation section to replace manual steps with the one-liner: `curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/main/src/install.sh | bash`
- [x] T019 Run full end-to-end validation per specs/002-install-script/quickstart.md: test fresh install, reinstall (verify .bak files), and prerequisite failure scenarios in isolated temp directories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001) - T002/T003/T004 all modify src/install.sh sequentially
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion - needs all embedded heredoc functions
- **User Story 2 (Phase 4)**: Depends on Phase 3 (US1 provides the base main() flow to extend)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (US1 provides the base main() flow to extend); can run in parallel with Phase 4
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on US1 (extends the main() fresh install flow with state detection and merge logic) — development order, not runtime order
- **User Story 3 (P3)**: Depends on US1 (inserts prerequisite checks at the start of main()); independent of US2 — development order, not runtime order (at runtime, prereqs run first)

### Within Each Phase

All tasks within each phase are sequential (all modify the same file: src/install.sh). No [P] markers within phases because parallelism is not possible on a single file.

### Parallel Opportunities

- T002, T003, T004 could theoretically run in parallel if writing to separate temp files that are later concatenated, but this adds unnecessary complexity for ~5 functions. Keep sequential.
- Phase 4 (US2) and Phase 5 (US3) extend different parts of main() and could be developed in parallel by different people on separate branches, then merged.
- T018 (README update) is independent of all implementation tasks and could be done at any time.

---

## Parallel Example: User Story 2 + User Story 3

```
# After US1 (Phase 3) is complete, these can proceed in parallel on separate branches:
Branch A: US2 tasks (T010-T014) — state detection, backup, merge
Branch B: US3 tasks (T015-T017) — prerequisite checks, prompts
# Merge both into 002-install-script branch
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001) — script skeleton
2. Complete Phase 2: Foundational (T002-T004) — embed all source files
3. Complete Phase 3: User Story 1 (T005-T009) — fresh install works
4. **STOP and VALIDATE**: Run install.sh in a temp directory, verify all files created
5. At this point a developer can install the cost tracker with one command

### Incremental Delivery

1. Setup + Foundational + US1 → Fresh install works (MVP!)
2. Add US2 (T010-T014) → Reinstall, backup, merge with existing settings
3. Add US3 (T015-T017) → Prerequisite validation, graceful failures
4. Polish (T018-T019) → README update, full validation

---

## Notes

- All tasks modify src/install.sh (single-file installer) — parallelism is limited
- Use `cat << 'EOF'` (single-quoted delimiter) for ALL heredocs to prevent variable expansion
- The script must work when piped via `curl | bash` — interactive prompts read from /dev/tty
- Never touch .claude/cost-data/sessions.jsonl or .claude/cost-data/report.md
- Total task count: 19 tasks across 6 phases
