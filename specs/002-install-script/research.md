# Research: Cost Tracker Install Script

**Feature**: 002-install-script | **Date**: 2026-03-20 (updated from 2026-03-05)

## 1. Safe JSON Merging with jq

**Decision**: Use jq `//=` alternative assignment + filter-then-append pattern for idempotent hook injection.

**Rationale**: This single jq expression handles all cases — missing `hooks` key, missing `hooks.Stop` array, existing cost-tracker entry, other hooks present — without any conditional branching in bash. The `//=` operator creates keys only if absent, the filter removes stale cost-tracker entries, and the append adds the current config.

**Pattern**:
```bash
jq --argjson new_hook "$NEW_HOOK" --arg cmd "$HOOK_COMMAND" '
  .hooks //= {} |
  .hooks.Stop //= [] |
  .hooks.Stop = [
    (.hooks.Stop[] | select(
      ([.hooks[]? | .command] | any(. == $cmd)) | not
    ))
  ] + [$new_hook]
' "$SETTINGS_FILE"
```

**Alternatives considered**:
- Manual bash if/else branching for each case → error-prone, many code paths
- Python/Node helper script → adds dependency, violates self-contained constraint
- `jq -s '.[0] * .[1]'` deep merge → would overwrite existing Stop hooks array entirely

## 2. Idempotent Installer Patterns

**Decision**: Tri-state detection (fresh / partial / complete) with backup-then-overwrite on update.

**Rationale**: Checking all 5 expected files against the filesystem gives a reliable state classification. On update, existing files get `.bak` copies created before overwriting. Cost data files (sessions.jsonl, report.md) are never touched. The jq merge pattern for settings.local.json is inherently idempotent.

**Detection logic**: Count installed files among the 5 expected. 0 = fresh install, 1-4 = partial/repair, 5 = already installed (backup + update).

**Backup strategy**: Create `<filename>.bak` before overwriting. Only back up files that already exist. Re-running overwrites the previous `.bak` (acceptable since it was itself an older version).

**Alternatives considered**:
- Version stamp file → adds state that can get out of sync
- Checksum comparison → overly complex for this use case
- Always overwrite without detection → poor UX, no feedback about existing install

## 3. Project Root Detection

**Decision**: Combined strategy — git root first, then walk-up for `.claude/`, then cwd with confirmation.

**Rationale**: `git rev-parse --show-toplevel` is the most reliable for git projects and handles subdirectory invocation correctly. Walking up for `.claude/` catches non-git Claude Code projects. Falling back to cwd with a confirmation prompt handles new projects safely.

**Alternatives considered**:
- Only git root → fails for non-git projects
- Only cwd → fails when run from subdirectory
- Environment variable → requires user action, not zero-config

## 4. File Distribution Strategy

**Decision**: Embed all source file contents directly in the install script as heredocs. Distributed via `curl -sL <url> | bash`.

**Rationale**: A self-contained script eliminates runtime network dependencies after the initial fetch. Users don't need to clone the repository. Using single-quoted heredoc delimiters (`cat << 'EOF'`) prevents variable expansion, safely preserving `$CLAUDE_PROJECT_DIR` references and other shell variables in the embedded content.

**Key implementation notes**:
- Use `cat << 'EOF'` (single-quoted delimiter) for all heredocs to prevent expansion.
- The script must work when piped from stdin (`curl | bash`). Interactive prompts must read from `/dev/tty` instead of stdin, or be avoided entirely.
- Total embedded content: ~500 lines (268-line hook script, 3 command files ~60 lines each, 53-line pricing JSON).

**Alternatives considered**:
- Copy from cloned repo → requires user to clone first, not a true one-command install
- Multi-fetch (download each file from GitHub raw URLs) → fragile, depends on GitHub availability
- tar/zip archive → unnecessary complexity for 5 small files

## 5. Cross-Platform Compatibility

**Decision**: Avoid all BSD/GNU-divergent utilities; use jq exclusively for JSON operations.

**Key findings**:
| Utility | macOS (BSD) | Linux (GNU) | Installer approach |
|---------|-------------|-------------|-------------------|
| `readlink -f` | Missing | Works | Use `$(cd "$(dirname "$0")" && pwd)` |
| `sed -i` | Requires `''` arg | No `''` arg | Use jq + temp file + mv |
| `mktemp` | Requires template | Template optional | Always use explicit template |
| `install -D` | Missing | Works | Use `mkdir -p` + `cp` |

**Alternatives considered**:
- Platform detection + conditional code → complex, error-prone
- Require GNU coreutils on macOS → unnecessary dependency

## 6. Hook Configuration Format

**Decision**: Use the exact hook entry format validated in feature 001.

**The hook entry to inject**:
```json
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
```

**Key details**: Empty `matcher` = match all events. `$CLAUDE_PROJECT_DIR` is a runtime variable set by Claude Code. The timeout of 30000ms allows for transcript parsing of large sessions.
