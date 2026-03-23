# Claude Code Cost Tracker

Automatic session cost tracking with zero-overhead data capture for Claude Code projects. Captures token usage, model breakdown, durations, and code changes after every conversation — then lets you query it with simple slash commands.

## How It Works

- A **Stop hook** (`cost-tracker.sh`) runs automatically after each Claude Code response, parsing the session transcript to extract token counts, models used, durations, and code changes
- Cost records are appended to a local JSONL file (`.claude/cost-data/sessions.jsonl`)
- **Slash commands** let you view session costs, generate reports, or reset data — all without leaving the conversation

No API calls. No external services. Everything runs locally with `bash` + `jq`.

> **Note:** All costs shown are estimates for reference only. Actual billing may differ due to pricing changes, rounding, or features not captured by local parsing.

## Prerequisites

- **Claude Code** CLI installed and configured
- **jq** 1.6+ installed
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`

## Installation

From your project's root directory, run:

```bash
curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/refs/heads/main/src/install.sh | bash
```

This single command installs the hook script, slash commands, pricing config, and configures `settings.local.json` — safely merging with any existing settings.

Restart Claude Code for hooks to take effect.

### What Gets Installed

```
.claude/
├── hooks/
│   └── cost-tracker.sh          # Stop hook script (executable)
├── commands/
│   ├── cost-report.md           # /cost-report slash command
│   ├── cost-session.md          # /cost-session slash command
│   └── cost-reset.md            # /cost-reset slash command
├── cost-data/
│   └── pricing.json             # Token pricing table
└── settings.local.json          # Updated with hook registration
```

### Updating

Re-run the install command to update. Existing files are backed up to `.bak` before overwriting. Your cost data is preserved.

## Usage

### Automatic Tracking

Cost data is captured automatically after each Claude Code response. No action needed.

### View Current Session Cost

```
/cost-session
```

Shows cost, duration, and per-model token breakdown for the most recent session. Pass a partial session ID to look up a specific session.

### Generate Full Report

```
/cost-report
```

Displays an aggregate summary (total cost, sessions, durations, per-model usage) and saves a detailed report with daily and per-session breakdowns to `.claude/cost-data/report.md`.

### Clear All Data

```
/cost-reset
```

Clears all accumulated cost records. Requires confirmation before deletion.

## Tracked Data

Each session record includes:

| Field | Description |
|-------|-------------|
| `total_cost_usd` | Calculated cost based on token pricing |
| `api_duration_ms` | Time spent waiting for API responses |
| `wall_duration_ms` | Total elapsed wall clock time |
| `lines_added` / `lines_removed` | Code changes made during the session |
| `models[].input_tokens` | Input tokens per model |
| `models[].output_tokens` | Output tokens per model |
| `models[].cache_read_tokens` | Cache read tokens per model |
| `models[].cache_write_tokens` | Cache write tokens per model |

## Updating Pricing

Edit `.claude/cost-data/pricing.json` to add new models or update rates:

```json
{
  "models": [
    {
      "model_pattern": "claude-opus-4-6",
      "input_per_mtok": 15.00,
      "output_per_mtok": 75.00,
      "cache_read_per_mtok": 1.50,
      "cache_write_per_mtok": 3.75
    }
  ]
}
```

The `model_pattern` is matched as a prefix against model IDs (e.g., `claude-opus-4-6` matches `claude-opus-4-6-20260301`). Unknown models use a fallback formula.

## Troubleshooting

- **No data captured** — Check that `.claude/hooks/cost-tracker.sh` is executable and `jq` is installed (`jq --version`)
- **Hook not firing** — Ensure `.claude/settings.local.json` has the correct hook config. Start a new Claude Code session after changes.
- **Incorrect pricing** — Edit `.claude/cost-data/pricing.json`. Unknown models default to: cache_read = 10% of input price, cache_write = 25% of input price.

## License

[MIT](LICENSE)
