# Quickstart: Claude Code Cost Tracker

## Prerequisites

- **Claude Code** CLI installed and configured
- **jq** installed (used by hook scripts for JSON processing)
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`
  - Other: https://jqlang.github.io/jq/download/

## Installation

1. Copy the following files into your Claude Code project:

```
.claude/
├── hooks/
│   └── cost-tracker.sh          # Hook script (make executable)
├── commands/
│   ├── cost-report.md           # /cost-report slash command
│   ├── cost-session.md          # /cost-session slash command
│   └── cost-reset.md            # /cost-reset slash command
└── cost-data/
    └── pricing.json             # Token pricing table
```

2. Make the hook script executable:
```bash
chmod +x .claude/hooks/cost-tracker.sh
```

3. Add hook configuration to `.claude/settings.local.json`:
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

If `.claude/settings.local.json` already has content, merge the `hooks` section into the existing JSON.

4. Restart Claude Code (or start a new session) for hooks to take effect.

## Usage

### Automatic Tracking
Cost data is captured automatically after each Claude response. No action needed.

### View Current Session Cost
```
/cost-session
```

### Generate Full Report
```
/cost-report
```
Displays a summary and saves a detailed report to `.claude/cost-data/report.md`.

### Clear Data
```
/cost-reset confirm
```

## Updating Pricing

Edit `.claude/cost-data/pricing.json` to add new models or update pricing. The file uses a simple format:

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

The `model_pattern` is matched as a prefix against model IDs (e.g., `claude-opus-4-6` matches `claude-opus-4-6-20260301`).

## Troubleshooting

- **No data captured**: Check that `.claude/hooks/cost-tracker.sh` is executable and `jq` is installed. Run `jq --version` to verify.
- **Hook not firing**: Ensure `.claude/settings.local.json` has the correct hook configuration. Start a new Claude Code session after making changes.
- **Incorrect pricing**: Edit `.claude/cost-data/pricing.json`. Unknown models use a fallback formula (cache_read = 10% of input, cache_write = 25% of input).
