# Slash Command Contract Changes

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01

This documents **changes** to the slash command contracts from feature 001 (`specs/001-cost-tracker/contracts/slash-commands.md`). Base behavior and invocation patterns remain unchanged.

## /cost-report Changes

### Report Structure (conversation summary — updated)

Add new fields to the summary output:

```
## Cost Report Summary

Total cost:         $X.XXXX
Total sessions:     N
Total turns:        N
Total tokens:       X.Xm
Total API duration: Xh Xm Xs
Total wall time:    Xh Xm Xs
Total code changes: X lines added, X lines removed

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Total Tokens | Cost | Est? |
|-------|-------|--------|------------|-------------|-------------|------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | X.Xm | $X.XXXX | — |
| claude-future-5 | X.Xk | X.Xk | X.Xk | X.Xk | X.Xk | $X.XXXX | * |

* Estimated pricing (model not in pricing table)

Pricing version: 2
Report saved to: .claude/cost-data/report.md
```

**Changes**:
- Total cost displayed with 4 decimal places
- New "Total turns" line
- New "Total tokens" line
- New "Total Tokens" and "Est?" columns in model table
- "Est?" column shows `*` for models that used fallback pricing
- New "Pricing version" line at bottom
- Per-model cost displayed with 4 decimal places

### Backwards Compatibility

When reading records without new fields:
- Missing `turns`: Omit "Total turns" line or show "—"
- Missing `total_tokens`: Omit "Total tokens" line or show "—"
- Missing `pricing_estimated`: Assume exact pricing (no `*` marker)
- Missing `pricing_version`: Show "Pricing version: N/A"

## /cost-session Changes

### Display Structure (updated)

```
## Session Cost: [SESSION_ID (truncated)]

Date:            YYYY-MM-DD HH:MM
Total cost:      $X.XXXX
Turns:           N
Total tokens:    X.Xm
API duration:    Xm Xs
Wall time:       Xm Xs
Code changes:    X lines added, X lines removed
Pricing:         v2 (exact)   OR   v2 (estimated*)

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Total Tokens | Cost | Est? |
|-------|-------|--------|------------|-------------|-------------|------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | X.Xm | $X.XXXX | — |
```

**Changes**:
- New "Turns" line
- New "Total tokens" line
- New "Pricing" line showing version and exact/estimated status
- New "Total Tokens" and "Est?" columns in model table
- Cost values displayed with 4 decimal places

## /cost-reset

No changes. Reset behavior is unaffected by the new fields — all records are deleted regardless of schema version.
