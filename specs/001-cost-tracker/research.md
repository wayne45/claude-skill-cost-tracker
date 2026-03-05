# Research: Claude Code Cost Tracker

**Branch**: `001-cost-tracker` | **Date**: 2026-03-05

## R1: Claude Code Hook System

**Decision**: Use `Stop` hook event for cost capture after each Claude response.

**Rationale**: The `Stop` event fires each time Claude finishes responding. By making the hook idempotent (re-reading the full transcript and updating the session record), we get progressive updates during multi-turn sessions. The final `Stop` before session exit captures the most complete data. `SessionEnd` was considered but risks not firing if the process is killed.

**Alternatives considered**:
- `SessionEnd`: Fires once at session termination. Risk: may not fire on crashes or force-quit. Chosen as a secondary/backup event.
- `PostToolUse`: Too granular (fires per tool call), would create excessive I/O.

**Key details**:
- Hooks receive JSON on stdin: `{ "session_id", "transcript_path", "cwd", "stop_hook_active", ... }`
- Hooks do NOT receive token counts or cost data directly
- The `transcript_path` field points to the session JSONL file containing all messages with usage data
- `stop_hook_active` must be checked to prevent infinite loops
- Hook configuration goes in `.claude/settings.local.json` under `hooks.Stop`

## R2: Session File Format and Token Data

**Decision**: Parse session JSONL files to extract token usage per assistant message, then aggregate by model.

**Rationale**: Each assistant message in the JSONL contains a `usage` object with all token type breakdowns and a `model` field. Summing these across all messages in a session gives accurate per-model totals. This matches how Claude Code's built-in `/cost` command calculates its data.

**Alternatives considered**:
- `stats-cache.json`: Contains aggregate stats across ALL sessions/projects, not per-session breakdowns. Not suitable for per-project tracking.
- `sessions-index.json`: Only has metadata (message counts, dates), no token usage data.

**Key data fields per assistant message**:
```json
{
  "message": {
    "model": "claude-opus-4-6-20260301",
    "usage": {
      "input_tokens": 3200,
      "output_tokens": 14800,
      "cache_read_input_tokens": 1200000,
      "cache_creation_input_tokens": 82000
    }
  },
  "type": "assistant",
  "timestamp": "2026-03-05T10:00:00.000Z"
}
```

**Note**: The JSONL field is `cache_creation_input_tokens` (not "cache write"). In the user-facing `/cost` output, this is displayed as "cache write". Our data model will use the term `cache_write_tokens` for consistency with user expectations but map from `cache_creation_input_tokens` when parsing.

## R3: Duration and Code Changes Tracking

**Decision**: Calculate durations from message timestamps. Track code changes by counting lines in Edit/Write tool results within the transcript.

**Rationale**:
- **API duration**: Sum of time between each user message and its corresponding assistant response.
- **Wall duration**: Time from first to last message in the session.
- **Code changes**: Parse `PostToolUse` entries for `Edit`, `Write`, and `Bash` tool calls that modify files. The transcript contains the diffs/content which can be used to count lines added/removed.

**Alternatives considered**:
- External timing mechanisms: Adds complexity, less accurate than parsing timestamps already in the data.
- Git diff for code changes: Would require git operations in the hook, slower and may not work in non-git projects.

**Limitation**: Code change tracking from transcript parsing may not be 100% accurate (e.g., if the same line is modified multiple times). This is acceptable for a cost-tracking tool — directional accuracy is sufficient.

## R4: Slash Command Architecture

**Decision**: Create three slash commands as markdown files in `.claude/commands/`:
1. `/cost-report` — Full summary report (conversation display + markdown file)
2. `/cost-session` — Current/latest session cost
3. `/cost-reset` — Clear accumulated data

**Rationale**: Markdown-based slash commands are the standard extension mechanism for Claude Code. They instruct Claude to read the cost data file and format the output. The commands themselves execute zero-cost (no API calls) because they only direct Claude to read local files and perform text formatting.

**Alternatives considered**:
- MCP server: Overkill for file-based data reading. Adds unnecessary complexity.
- Single command with subcommands: Claude Code slash commands don't natively support subcommands. Three separate commands are clearer.

**Key implementation details**:
- Commands use `!`command`` syntax for dynamic context (reading cost data file)
- Commands include instructions for Claude to format the output as tables/summaries
- `/cost-report` additionally instructs Claude to write a markdown report file

## R5: Cost Data Storage Format

**Decision**: Use a JSONL file (`.claude/cost-data/sessions.jsonl`) with one cost record per line, keyed by session ID. Use last-write-wins deduplication when reading.

**Rationale**: JSONL is append-only and safe for concurrent writes (atomic line appends). The `Stop` hook fires multiple times per session, so each firing appends an updated record for that session. When reading, the latest record per session ID is used. This approach is simple, requires no locking, and matches the pattern used by Claude Code's own session files.

**Alternatives considered**:
- Single JSON file: Requires read-modify-write cycle, not safe for concurrent access.
- SQLite: Adds dependency, overkill for the data volume expected (hundreds to low thousands of records).
- CSV: Less structured, harder to extend with new fields.

**File structure**:
```jsonl
{"session_id":"abc-123","timestamp":"2026-03-05T10:00:00Z","total_cost":1.51,...}
{"session_id":"abc-123","timestamp":"2026-03-05T10:05:00Z","total_cost":2.30,...}
```

## R6: Pricing Data Management

**Decision**: Bundle a `pricing.json` file with hardcoded per-model pricing. Users can edit this file to update pricing for new models.

**Rationale**: The zero-cost constraint prohibits fetching pricing from the internet. Bundling pricing locally is the only option. Using a JSON file (rather than hardcoding in scripts) makes it easy to update without modifying code.

**Pricing structure** (per million tokens, USD):

| Model | Input | Output | Cache Read | Cache Write |
|-------|-------|--------|------------|-------------|
| claude-opus-4-6 | $15.00 | $75.00 | $1.50 | $3.75 |
| claude-sonnet-4-6 | $3.00 | $15.00 | $0.30 | $0.75 |
| claude-haiku-4-5 | $0.80 | $4.00 | $0.08 | $0.20 |

**Note**: Cache read = 10% of input price. Cache write (creation) = 25% of input price. This formula can be used as a fallback for unknown models, with a warning logged.

## R7: Implementation Language

**Decision**: Use bash scripts with `jq` for hook processing and cost calculation.

**Rationale**: Claude Code hooks execute shell commands. Bash + jq is the most lightweight approach with no additional runtime dependencies beyond what's commonly available in development environments. The processing is straightforward (parse JSONL, sum numbers, format output) and well within jq's capabilities.

**Alternatives considered**:
- Python: More powerful but not guaranteed on all systems (macOS removed default Python). Adds a runtime dependency.
- Node.js: Heavier runtime, not universally available.
- Pure bash (no jq): Possible but fragile for JSON parsing.

**Dependency**: `jq` must be installed. The setup guide will include installation instructions. The hook script will check for `jq` availability and fail gracefully with a clear error message if not found.
