# Hook Contract: Cost Tracker Stop Hook

## Hook Configuration

**Event**: `Stop`
**Type**: `command`
**Script**: `.claude/hooks/cost-tracker.sh`

### Settings Schema (`.claude/settings.local.json`)

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/cost-tracker.sh",
            "timeout": 30000
          }
        ]
      }
    ]
  }
}
```

## Input Contract (stdin JSON)

The hook receives JSON on stdin from Claude Code:

```json
{
  "session_id": "string (UUID)",
  "transcript_path": "string (absolute path to .jsonl file)",
  "cwd": "string (current working directory)",
  "stop_hook_active": "boolean",
  "hook_event_name": "Stop",
  "last_assistant_message": "string"
}
```

### Required Fields

| Field | Type | Used For |
|-------|------|----------|
| `session_id` | string | Keying cost records |
| `transcript_path` | string | Reading session data for token aggregation |
| `stop_hook_active` | boolean | Preventing infinite loops (skip if true) |

## Output Contract

**Exit code 0**: Success. No stdout required.
**Exit code 1**: Non-blocking error (logged, does not affect Claude).
**No stdout**: The hook writes to `.claude/cost-data/sessions.jsonl` directly, not to stdout.

## Behavior

1. Read JSON from stdin
2. If `stop_hook_active` is true, exit 0 immediately (prevent loops)
3. Validate `transcript_path` exists and is readable
4. Parse transcript JSONL to aggregate token usage by model
5. Look up pricing from `.claude/cost-data/pricing.json`
6. Calculate per-model and total cost
7. Append cost record to `.claude/cost-data/sessions.jsonl`
8. Exit 0

## Error Handling

| Condition | Behavior | Exit Code |
|-----------|----------|-----------|
| `jq` not installed | Log warning to stderr | 1 |
| Transcript file missing | Log warning to stderr | 1 |
| Pricing file missing | Use hardcoded defaults | 0 |
| Malformed transcript line | Skip line, continue | 0 |
| Cost data directory missing | Create it | 0 |
