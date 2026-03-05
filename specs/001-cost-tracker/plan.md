# Implementation Plan: Claude Code Cost Tracker

**Branch**: `001-cost-tracker` | **Date**: 2026-03-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-cost-tracker/spec.md`

## Summary

Build a zero-cost Claude Code extension that automatically tracks token usage and costs per conversation session using hooks, stores data locally in JSONL format, and provides slash commands for reporting and management. The hook parses session transcript files to extract per-model token usage (input, output, cache read, cache write), calculates costs from a bundled pricing table, and tracks durations and code changes. Three slash commands provide full reporting, per-session viewing, and data reset capabilities.

## Technical Context

**Language/Version**: Bash 5.x + jq 1.6+
**Primary Dependencies**: jq (JSON processor), Claude Code hooks system, Claude Code slash commands
**Storage**: JSONL file (`.claude/cost-data/sessions.jsonl`) + JSON config (`.claude/cost-data/pricing.json`)
**Testing**: Manual testing via Claude Code sessions; bash script validation with sample JSONL fixtures
**Target Platform**: macOS / Linux (any platform running Claude Code CLI)
**Project Type**: Claude Code extension (hooks + slash commands)
**Performance Goals**: Hook execution < 1 second; report generation < 5 seconds for 1000+ sessions
**Constraints**: Zero-cost operation (no API calls, no external services); jq must be installed; append-only JSONL for concurrent safety
**Scale/Scope**: Single developer, single project; hundreds to low thousands of session records

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution is an unfilled template with no active principles or gates defined. No violations possible. Gate passes by default.

**Post-Phase 1 re-check**: Still passes. The design uses simple bash scripts, flat-file storage, and standard Claude Code extension mechanisms. No over-engineering detected.

## Project Structure

### Documentation (this feature)

```text
specs/001-cost-tracker/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: research findings
├── data-model.md        # Phase 1: entity definitions and file formats
├── quickstart.md        # Phase 1: installation and usage guide
├── contracts/
│   ├── hook-contract.md     # Hook input/output/behavior contract
│   └── slash-commands.md    # Slash command interface contracts
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
.claude/
├── hooks/
│   └── cost-tracker.sh              # Stop hook: parses transcript, calculates cost, writes record
├── commands/
│   ├── cost-report.md               # /cost-report: full summary + saved markdown report
│   ├── cost-session.md              # /cost-session: current/specific session cost
│   └── cost-reset.md                # /cost-reset: clear accumulated data
├── cost-data/
│   ├── pricing.json                 # Bundled per-model token pricing
│   ├── sessions.jsonl               # Accumulated cost records (created at runtime)
│   └── report.md                    # Generated report file (created by /cost-report)
└── settings.local.json              # Hook configuration (updated with Stop hook)

tests/
├── fixtures/
│   ├── sample-transcript.jsonl      # Sample session transcript for testing
│   ├── sample-pricing.json          # Test pricing data
│   └── expected-output.json         # Expected cost calculation results
└── test-cost-tracker.sh             # Bash test script for hook logic
```

**Structure Decision**: This is a Claude Code extension project. All runtime files live under `.claude/` following Claude Code conventions (hooks in `hooks/`, commands in `commands/`). Cost data is stored in `.claude/cost-data/` to keep it co-located with the extension but separate from configuration. Test fixtures live in a top-level `tests/` directory.

## Key Design Decisions

### 1. Hook Event: `Stop` (not `SessionEnd`)

The `Stop` event fires each time Claude finishes a response, allowing progressive cost updates during multi-turn sessions. The hook is idempotent — it re-reads the full transcript and updates the record for the current session ID. This means the latest `Stop` event captures the most complete data, and if `SessionEnd` doesn't fire (e.g., process killed), we still have data from the last `Stop`.

### 2. Transcript Parsing for Token Data

Hooks do not receive token/cost data directly. The hook reads the session's JSONL transcript file (path provided in hook input) and aggregates `usage` fields from all assistant messages. This is the same data source Claude Code's built-in `/cost` command uses.

### 3. JSONL for Cost Data Storage

Append-only JSONL provides concurrent-write safety (atomic line appends). Multiple `Stop` events for the same session append updated records; the latest record per `session_id` is authoritative when reading. No file locking required.

### 4. Slash Commands as Claude Instructions

Slash commands are markdown files that instruct Claude to read the cost data files and format output. They use `!`command`` syntax to inject file contents dynamically. Claude performs the formatting and display — the commands themselves are zero-cost (no API calls beyond the conversation already in progress).

### 5. Bundled Pricing with Prefix Matching

Model IDs include version suffixes (e.g., `claude-opus-4-6-20260301`). Pricing entries use prefix patterns (e.g., `claude-opus-4-6`) for forward compatibility with new versions. Unknown models fall back to a configurable formula.
