# Quickstart: Refine Cost Tracking Precision

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01

## Prerequisites

- Existing cost tracker installation from feature 001
- Bash 3.2+ and jq 1.6+ (same as feature 001)

## What Changes

This feature updates the existing cost tracker without requiring reinstallation. The changes are:

1. **pricing.json** — Version bumped to 2, fallback section replaces fallback_formula, older Opus models added
2. **cost-tracker.sh** — Hook updated with fallback pricing, turn count, total_tokens, pricing_version, 4-decimal precision
3. **cost-report.md** — Slash command updated to display new fields
4. **cost-session.md** — Slash command updated to display new fields
5. **install.sh** — Installer updated with new embedded files

## Upgrade Path

### Option A: Re-run installer (recommended)

```bash
curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/refs/heads/main/src/install.sh | bash
```

The installer detects existing installation, backs up current files to `.bak`, and writes updated versions. Existing `sessions.jsonl` data is preserved — no migration needed.

### Option B: Manual update

Replace these files with the updated versions:
- `.claude/hooks/cost-tracker.sh`
- `.claude/cost-data/pricing.json`
- `.claude/commands/cost-report.md`
- `.claude/commands/cost-session.md`

## Verifying the Update

After updating, run a short Claude Code conversation and check the latest record:

```bash
tail -1 .claude/cost-data/sessions.jsonl | jq '.'
```

You should see the new fields:
- `turns` — number of API calls in the session
- `total_tokens` — total token count across all types
- `pricing_version` — should be `2`
- `pricing_estimated` — `false` for known models

## Backwards Compatibility

- Old cost records (without new fields) continue to work — report and session commands handle missing fields gracefully
- No data migration required
- Old and new records coexist in `sessions.jsonl`

## Testing

Run the test suite to verify the update:

```bash
bash tests/test-cost-tracker.sh
```

All existing tests should pass (with updated expected values for 4-decimal precision), plus new tests for:
- Fallback pricing for unknown models
- Turn count accuracy
- Total tokens computation
- Pricing version inclusion
- Estimated pricing flag
