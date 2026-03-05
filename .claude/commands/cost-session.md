---
name: cost-session
description: Display cost details for the most recent or a specific session
argument-hint: "[session-id]"
---

You are displaying cost details for a single Claude Code session.

## Data Source

**IMPORTANT**: First, use the Read tool to load `.claude/cost-data/sessions.jsonl` (JSONL, one JSON object per line).

If the file does not exist or is empty, respond with: "No cost data recorded yet. Cost data is automatically captured after each conversation via the Stop hook." and stop.

## Arguments

$ARGUMENTS

## Instructions

1. **Read the session data file** using the Read tool. Parse each line as a separate JSON object.

2. **Deduplicate by session_id**: If multiple records share the same `session_id`, keep only the one with the latest `timestamp`.

3. **Select the session to display**:
   - If `$ARGUMENTS` is provided and not empty: find the session whose `session_id` contains the argument text (partial match). If no match found, say "Session not found. Available sessions:" and list the 5 most recent session IDs with their dates.
   - If `$ARGUMENTS` is empty: select the session with the latest `session_end` timestamp.

4. **Format token counts** for display:
   - Under 1,000: show as-is (e.g., `800`)
   - 1,000-999,999: show as `X.Xk` (e.g., `3.2k`)
   - 1,000,000+: show as `X.Xm` (e.g., `1.2m`)

5. **Format durations**: Convert milliseconds to human-readable `Xm Xs` or `Xh Xm Xs`.

6. **Display in conversation** using this format:

```
## Session Cost: [first 12 chars of session_id]...

Date:           YYYY-MM-DD HH:MM
Total cost:     $X.XX
API duration:   Xm Xs
Wall time:      Xm Xs
Code changes:   X lines added, X lines removed

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Cost |
|-------|-------|--------|------------|-------------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | $X.XX |
```

Do NOT write any files. Display only.
