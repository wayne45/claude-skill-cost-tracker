---
name: cost-report
description: Generate a full cost summary report across all tracked sessions
---

You are generating a cost report from Claude Code session cost data.

## Data Sources

**IMPORTANT**: First, use the Read tool to load these two files before proceeding:
1. `.claude/cost-data/sessions.jsonl` — JSONL session cost records (one JSON object per line)
2. `.claude/cost-data/pricing.json` — token pricing configuration

If sessions.jsonl does not exist or is empty, respond with: "No cost data recorded yet. Cost data is automatically captured after each conversation via the Stop hook." and stop.

## Arguments

$ARGUMENTS

## Instructions

1. **Read both files** listed above using the Read tool. Parse each line of sessions.jsonl as a separate JSON object.

2. **Deduplicate by session_id**: If multiple records share the same `session_id`, keep only the one with the latest `timestamp`.

3. **Aggregate totals** across all deduplicated sessions:
   - Total cost (sum of `total_cost_usd`)
   - Total sessions (count of unique session_ids)
   - Total API duration (sum of `api_duration_ms`, format as `Xh Xm Xs`)
   - Total wall time (sum of `wall_duration_ms`, format as `Xh Xm Xs`)
   - Total lines added (sum of `lines_added`)
   - Total lines removed (sum of `lines_removed`)
   - Per-model token totals (sum `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens` across all sessions, grouped by model)
   - Per-model cost totals (sum `cost_usd` per model)

4. **Format token counts** for display:
   - Under 1,000: show as-is (e.g., `800`)
   - 1,000-999,999: show as `X.Xk` (e.g., `3.2k`)
   - 1,000,000+: show as `X.Xm` (e.g., `1.2m`)

5. **Display in conversation** using this format:

```
## Cost Report Summary

Total cost:         $X.XX
Total sessions:     N
Total API duration: Xh Xm Xs
Total wall time:    Xh Xm Xs
Total code changes: X lines added, X lines removed

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Cost |
|-------|-------|--------|------------|-------------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | $X.XX |

Report saved to: .claude/cost-data/report.md
```

6. **Write a detailed report** to `.claude/cost-data/report.md` containing:
   - All of the summary above
   - A **Daily Breakdown** table grouped by date (YYYY-MM-DD):

     | Date | Sessions | Cost | API Duration | Wall Time |
     |------|----------|------|--------------|-----------|

   - A **Per-Session Detail** table:

     | Session ID | Date | Cost | API Duration | Wall Time | Models | Lines +/- |
     |------------|------|------|--------------|-----------|--------|-----------|

   Use the Bash tool to write the report file: `cat > .claude/cost-data/report.md << 'REPORT_EOF'` followed by the full report content.

7. If `$ARGUMENTS` contains filter terms (like a date or model name), apply reasonable filtering before aggregating. If the filter doesn't match anything, say so.
