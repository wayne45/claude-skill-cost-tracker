# Slash Command Contracts

## /cost-report

**File**: `.claude/commands/cost-report.md`
**Purpose**: Generate a full cost summary report across all tracked sessions.

### Input
- `$ARGUMENTS`: Optional. Filter options (e.g., date range, model filter). If empty, report on all data.

### Output
1. **Conversation display**: Formatted summary with totals and per-model breakdown (markdown tables).
2. **File output**: Detailed markdown report saved to `.claude/cost-data/report.md`.

### Report Structure (conversation summary)
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
| ... | ... | ... | ... | ... | ... |

Report saved to: .claude/cost-data/report.md
```

### Report Structure (saved file — additional detail)
- All of the above, plus:
- Daily breakdown table
- Per-session detail table (session ID, date, cost, duration, models used)

### Behavior
1. Read `.claude/cost-data/sessions.jsonl`
2. Deduplicate by session_id (latest record wins)
3. Aggregate totals across all sessions
4. Format and display summary in conversation
5. Write detailed report to `.claude/cost-data/report.md`
6. If no data exists, display "No cost data recorded yet."

---

## /cost-session

**File**: `.claude/commands/cost-session.md`
**Purpose**: Display cost details for the most recent or a specific session.

### Input
- `$ARGUMENTS`: Optional. Session ID to query. If empty, show the most recent session.

### Output
- **Conversation display only** (no file output).

### Display Structure
```
## Session Cost: [SESSION_ID (truncated)]

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

### Behavior
1. Read `.claude/cost-data/sessions.jsonl`
2. If `$ARGUMENTS` is provided, find matching session
3. If empty, use the session with the latest `session_end` timestamp
4. Display formatted cost breakdown
5. If no data exists, display "No cost data recorded yet."

---

## /cost-reset

**File**: `.claude/commands/cost-reset.md`
**Purpose**: Clear all accumulated cost data.

### Input
- `$ARGUMENTS`: Optional. Confirmation phrase (e.g., "confirm").

### Output
- **Conversation display**: Confirmation message.

### Behavior
1. If `$ARGUMENTS` does not contain "confirm":
   - Display current data summary (total sessions, total cost)
   - Ask user: "To confirm deletion, run `/cost-reset confirm`"
   - Do NOT delete data
2. If `$ARGUMENTS` contains "confirm":
   - Delete `.claude/cost-data/sessions.jsonl`
   - Delete `.claude/cost-data/report.md` (if exists)
   - Display "Cost data cleared. X sessions removed."
