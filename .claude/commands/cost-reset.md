---
name: cost-reset
description: Clear all accumulated cost data
argument-hint: "[confirm]"
---

You are managing cost data reset for the Claude Code cost tracker.

## Data Source

**IMPORTANT**: First, use the Read tool to load `.claude/cost-data/sessions.jsonl` (JSONL, one JSON object per line).

If the file does not exist or is empty, respond with: "No cost data to clear." and stop.

## Arguments

$ARGUMENTS

## Instructions

### If `$ARGUMENTS` does NOT contain "confirm":

1. Count the number of unique sessions in the data (deduplicate by `session_id`, latest `timestamp` wins).
2. Calculate the total cost across all sessions.
3. Display this summary:

```
## Cost Data Summary

Sessions recorded: N
Total cost tracked: $X.XX

To confirm deletion of all cost data, run: /cost-reset confirm
```

Do NOT delete any files.

### If `$ARGUMENTS` contains "confirm":

1. Count the sessions that will be removed (for the confirmation message).
2. Delete the cost data files using the Bash tool:
   ```
   rm -f .claude/cost-data/sessions.jsonl .claude/cost-data/report.md
   ```
3. Display confirmation:

```
Cost data cleared. X sessions removed.
```
