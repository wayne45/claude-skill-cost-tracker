# Quickstart: Cost Tracker Install Script

**Feature**: 002-install-script | **Date**: 2026-03-20 (updated from 2026-03-05)

## Prerequisites

- **Bash** 3.2+ (pre-installed on macOS and Linux)
- **jq** 1.6+ — Install: `brew install jq` (macOS) or `sudo apt install jq` (Linux)
- A Claude Code project directory (or any directory where you want to set one up)

## Installation

### One-command install (recommended)

From your project's root directory:

```bash
curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/main/src/install.sh | bash
```

That's it. The installer validates prerequisites, creates all necessary files, configures the hook, and displays a summary.

### Local install (from cloned repo)

If you've already cloned the repository:

```bash
bash src/install.sh
```

### 2. Start a new Claude Code session

The cost tracker activates automatically on the next Claude Code session in the target project.

## What Gets Installed

```
your-project/
└── .claude/
    ├── hooks/
    │   └── cost-tracker.sh          # Runs after each conversation turn
    ├── commands/
    │   ├── cost-report.md           # /cost-report slash command
    │   ├── cost-session.md          # /cost-session slash command
    │   └── cost-reset.md            # /cost-reset slash command
    ├── cost-data/
    │   └── pricing.json             # Model pricing configuration
    └── settings.local.json          # Updated with hook registration
```

## Usage

After installation, these slash commands are available in Claude Code:

| Command | Description |
|---------|-------------|
| `/cost-report` | Full cost summary across all tracked sessions |
| `/cost-session` | Cost details for the most recent session |
| `/cost-session <id>` | Cost details for a specific session |
| `/cost-reset` | Preview what would be cleared |
| `/cost-reset confirm` | Clear all accumulated cost data |

## Updating

Re-run the installer to update all cost tracker files to the latest version:

```bash
curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/main/src/install.sh | bash
```

Existing files are backed up to `.bak` before overwriting. Your cost data (sessions.jsonl) is preserved across updates.

## Uninstalling

Remove the cost tracker files manually:

```bash
rm -f .claude/hooks/cost-tracker.sh
rm -f .claude/commands/cost-report.md .claude/commands/cost-session.md .claude/commands/cost-reset.md
rm -rf .claude/cost-data/
```

Then remove the Stop hook entry from `.claude/settings.local.json` manually.
