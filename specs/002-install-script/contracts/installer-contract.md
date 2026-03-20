# Installer CLI Contract

**Feature**: 002-install-script | **Date**: 2026-03-20 (updated from 2026-03-05)

## Command Interface

### Invocation

```bash
# Remote (recommended)
curl -sL https://raw.githubusercontent.com/wayne45/claude-skill-cost-tracker/main/src/install.sh | bash

# Local (from cloned repo)
bash src/install.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--force` | Skip confirmation prompts; overwrite existing files without asking |
| `--help` | Display usage information and exit |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Installation completed successfully |
| 1 | Missing prerequisite (jq not found, bash too old) |
| 2 | User cancelled installation |
| 3 | File operation error (permission denied, disk full) |

## Behavior Contract

### Fresh Install (no existing cost tracker files)

1. Validate prerequisites (jq, bash version)
2. Detect project root (git root → `.claude/` walk-up → cwd)
3. If `.claude/` directory doesn't exist, warn and ask confirmation (via `/dev/tty` when piped)
4. Create directory structure (`.claude/hooks/`, `.claude/commands/`, `.claude/cost-data/`)
5. Write 5 files from embedded heredocs
6. Set `cost-tracker.sh` as executable
7. Create or merge `settings.local.json` with hook entry
8. Display summary of actions taken

### Update / Reinstall (all files already present)

1. Validate prerequisites
2. Detect existing installation
3. Display "Already installed — updating to latest version" message
4. Create `.bak` backups of existing files
5. Write 5 files from embedded heredocs (overwrite)
6. Set `cost-tracker.sh` as executable
7. Merge `settings.local.json` (idempotent — no duplicates)
8. Display summary noting files updated and backups created

### Partial Install (some files present)

1. Validate prerequisites
2. Detect partial installation, list missing files
3. Display "Partial installation detected — repairing" message
4. Create `.bak` backups of any existing files
5. Write all 5 files from embedded heredocs
6. Set `cost-tracker.sh` as executable
7. Merge `settings.local.json`
8. Display summary noting repair

### Prerequisite Failure

1. Display which prerequisite is missing
2. Provide OS-specific installation instructions
3. Exit with code 1
4. Do not create or modify any files

## Output Format

### Success Output

```
Claude Code Cost Tracker - Installer
=====================================

Target: /path/to/project
Status: Fresh install

Creating directories...
  .claude/hooks/
  .claude/commands/
  .claude/cost-data/

Writing files...
  .claude/hooks/cost-tracker.sh (executable)
  .claude/commands/cost-report.md
  .claude/commands/cost-session.md
  .claude/commands/cost-reset.md
  .claude/cost-data/pricing.json

Configuring hooks...
  Updated .claude/settings.local.json

Installation complete!

Next steps:
  1. Start a new Claude Code session in /path/to/project
  2. Use /cost-session to see costs after your first conversation
  3. Use /cost-report for a full summary across sessions
```

### Prerequisite Failure Output

```
Claude Code Cost Tracker - Installer
=====================================

ERROR: jq is required but not installed.

Install jq:
  macOS:  brew install jq
  Ubuntu: sudo apt install jq
  Fedora: sudo dnf install jq
```

## Settings Merge Contract

### Input: Existing settings.local.json

Any valid JSON object. May contain `permissions`, `hooks`, or any other keys.

### Output: Merged settings.local.json

The same JSON object with the cost tracker hook entry added to `hooks.Stop[]`. All other content is preserved exactly.

### Idempotency Guarantee

Running the installer N times produces the same result as running it once. The cost tracker hook entry appears exactly once in `hooks.Stop[]` regardless of how many times the installer runs.

### Malformed JSON Handling

If `settings.local.json` exists but contains invalid JSON:
1. Create a backup: `settings.local.json.bak`
2. Warn the user about the malformed file
3. Create a new `settings.local.json` with only the hook entry
4. Display the backup path so the user can manually merge
