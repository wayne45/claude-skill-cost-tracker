# Implementation Plan: Refine Cost Tracking Precision

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-refine-cost-tracking/spec.md`

## Summary

Refine the Claude Code cost tracker skill to align with the reference Rust implementation's behavior. After analyzing the Rust source code (`rust/crates/runtime/src/usage.rs`, etc.), seven precision gaps were identified. Research confirmed the skill's pricing rates are already correct (the Rust source has stale pricing). The remaining work focuses on: adding fallback pricing for unknown models with estimation tagging, tracking API turn count and total tokens per session, including pricing version for audit trails, and standardizing cost precision to 4 decimal places. All changes are backwards-compatible and additive.

## Technical Context

**Language/Version**: Bash 5.x (compatible with 3.2+ on macOS) + jq 1.6+
**Primary Dependencies**: jq (JSON processor), Claude Code hooks system, Claude Code slash commands
**Storage**: JSONL file (`.claude/cost-data/sessions.jsonl`) + JSON config (`.claude/cost-data/pricing.json`)
**Testing**: Bash test script (`tests/test-cost-tracker.sh`) with JSONL fixtures
**Target Platform**: macOS / Linux (any platform running Claude Code CLI)
**Project Type**: Claude Code extension (hooks + slash commands)
**Performance Goals**: Hook execution < 1 second (no change from feature 001)
**Constraints**: Zero-cost operation; no files in `rust/` directory modified; backwards-compatible with existing cost records
**Scale/Scope**: Incremental refinement to existing hook, pricing file, and 2 slash commands

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution is an unfilled template with no active principles or gates defined. No violations possible. Gate passes by default.

**Post-Phase 1 re-check**: Still passes. The changes are minimal, additive modifications to existing bash/jq scripts and a JSON config file. No new dependencies, no new architectural patterns.

## Project Structure

### Documentation (this feature)

```text
specs/003-refine-cost-tracking/
├── plan.md                          # This file
├── spec.md                          # Feature specification
├── research.md                      # Phase 0: pricing verification, design decisions
├── data-model.md                    # Phase 1: updated entity schemas
├── quickstart.md                    # Phase 1: upgrade guide
├── checklists/
│   └── requirements.md              # Spec quality checklist
├── contracts/
│   ├── hook-contract-changes.md     # Hook output contract changes
│   └── slash-commands-changes.md    # Slash command display changes
└── tasks.md                         # Phase 2 output (created by /speckit.tasks)
```

### Source Code (files to modify)

```text
.claude/
├── hooks/
│   └── cost-tracker.sh              # MODIFY: add fallback pricing, turns, total_tokens, pricing_version, 4-decimal precision
├── commands/
│   ├── cost-report.md               # MODIFY: display new fields (turns, total_tokens, pricing info)
│   └── cost-session.md              # MODIFY: display new fields (turns, total_tokens, pricing info)
├── cost-data/
│   └── pricing.json                 # MODIFY: bump to v2, add fallback section, add older Opus models
└── settings.local.json              # NO CHANGE

src/
└── install.sh                       # MODIFY: embed updated files (pricing.json v2, updated hook)

tests/
├── fixtures/
│   ├── sample-transcript.jsonl      # NO CHANGE (fixture data stays the same)
│   ├── duplicate-assistant.jsonl    # NO CHANGE
│   └── expected-output.json         # MODIFY: update expected values for 4-decimal precision, add new field expectations
└── test-cost-tracker.sh             # MODIFY: update existing test assertions, add new test cases
```

**Structure Decision**: No new files in the source tree. All changes are modifications to existing files established in feature 001. The hook, pricing config, slash commands, installer, and tests all receive targeted updates.

## Key Design Decisions

### 1. Pricing Rates Are Already Correct

Research (R1) confirmed the skill's `pricing.json` matches current official Anthropic API pricing. The Rust source code uses stale Opus 4.0/4.1 pricing ($15/$75) applied incorrectly to newer Opus 4.5+ and to all Sonnet models. No rate changes needed — only structural improvements to the pricing file (fallback section, version bump, additional model entries).

### 2. Full Sonnet-Tier Fallback for Unknown Models

Instead of the current `fallback_formula` (cache ratios only, resulting in $0.00 for unknown models), the new `fallback` section provides complete Sonnet-tier rates. This mirrors the Rust source's behavioral pattern of falling back to Sonnet pricing. The `pricing_estimated` flag on both per-model and session levels makes it clear when estimates are in play.

### 3. Turn Count = Deduplicated Assistant Message Count

The hook's existing deduplication logic (keeping only the last assistant message in consecutive chains) already produces exactly the right set to count. `turns` is simply the array length — no new parsing logic needed, just a new field extracted from existing data.

### 4. Total Tokens Follows Rust Runtime (Not API)

The Rust runtime includes all four token types in `total_tokens()` (input + output + cache_creation + cache_read), while the API-level `Usage::total_tokens()` excludes cache tokens. We follow the runtime behavior because it gives a more complete picture of total token volume processed.

### 5. 4-Decimal Precision Matches Rust `format_usd()`

Changing from 6 to 4 decimal places aligns with the Rust source's formatting (`format!("${amount:.4}")`). The jq rounding changes from `* 1000000 | round | . / 1000000` to `* 10000 | round | . / 10000`. This is the only change that affects existing test assertions.

## Implementation Approach

### Phase 1: Update pricing.json

1. Add `fallback` section with complete Sonnet-tier rates
2. Remove `fallback_formula`
3. Add `claude-opus-4-1` and `claude-opus-4-` entries
4. Bump `version` to 2, update `updated` date

### Phase 2: Update cost-tracker.sh (hook)

1. **Fallback pricing**: Modify the jq cost calculation pipeline to use `$pricing.fallback` when no prefix match found, and set `pricing_estimated: true` on the model entry
2. **Turn count**: Extract array length from deduplicated usage as `turns`
3. **Total tokens**: Compute per-model and session-level `total_tokens`
4. **Pricing version**: Read `$pricing.version // 0` and include as `pricing_version`
5. **Session pricing_estimated**: OR across all model `pricing_estimated` flags
6. **4-decimal precision**: Change rounding from 6 to 4 decimal places
7. **Fallback when pricing.json missing**: Use hardcoded Sonnet-tier defaults (not just zero costs), set all `pricing_estimated: true`

### Phase 3: Update slash commands

1. **cost-report.md**: Add turns, total_tokens, pricing version, and estimated marker to display instructions
2. **cost-session.md**: Add turns, total_tokens, pricing info to display instructions
3. Both commands: Handle missing fields gracefully for old records

### Phase 4: Update tests

1. Update existing test expected values for 4-decimal precision
2. Add test: fallback pricing for unknown model → non-zero cost, `pricing_estimated: true`
3. Add test: turn count matches expected deduplicated assistant message count
4. Add test: total_tokens equals sum of all four token types
5. Add test: pricing_version included in output, matches pricing.json version
6. Add test: mixed known/unknown models → correct per-model `pricing_estimated` flags
7. Add test: missing pricing.json → uses Sonnet-tier defaults, all estimated

### Phase 5: Update installer

1. Update embedded `pricing.json` heredoc with v2 content
2. Update embedded `cost-tracker.sh` heredoc with all hook changes
3. Update embedded slash command heredocs
