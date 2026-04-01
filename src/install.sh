#!/usr/bin/env bash
# Claude Code Cost Tracker - Installer
# Self-contained installer: all source files embedded as heredocs.
# Usage: curl -sL <url> | bash
#    or: bash src/install.sh [--force] [--help]

set -euo pipefail

# --- Exit codes (per contract) ---
readonly EXIT_SUCCESS=0
readonly EXIT_PREREQ_FAIL=1
readonly EXIT_CANCELLED=2
readonly EXIT_FILE_ERROR=3

# --- Globals ---
FORCE=false
PROJECT_ROOT=""
INSTALL_STATE=""  # FRESH, PARTIAL, ALREADY_INSTALLED

# --- Output helpers ---
print_header() {
  echo ""
  echo "Claude Code Cost Tracker - Installer"
  echo "====================================="
  echo ""
}

print_success() {
  echo "  $1"
}

print_error() {
  echo "ERROR: $1" >&2
}

print_warning() {
  echo "WARNING: $1"
}

print_step() {
  echo "$1"
}

# --- Argument parsing ---
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)
        FORCE=true
        ;;
      --help|-h)
        print_header
        echo "Usage: bash install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Display this help message"
        echo ""
        echo "Or install remotely:"
        echo "  curl -sL <url> | bash"
        exit "$EXIT_SUCCESS"
        ;;
      *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information."
        exit "$EXIT_PREREQ_FAIL"
        ;;
    esac
    shift
  done
}

# ============================================================================
# Phase 2: Embedded source files (heredoc-writing functions)
# All heredocs use single-quoted delimiters to prevent variable expansion.
# ============================================================================

# --- T002: Embed cost-tracker.sh hook script ---
write_hook_script() {
  local target="$1"
  cat > "$target" << 'HOOK_SCRIPT_EOF'
#!/usr/bin/env bash
# Claude Code Cost Tracker - Stop Hook
# Parses session transcript to track token usage, durations, code changes, and costs.
# Writes cost records to .claude/cost-data/sessions.jsonl

set -uo pipefail

# Determine project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
COST_DATA_DIR="$PROJECT_DIR/.claude/cost-data"
PRICING_FILE="$COST_DATA_DIR/pricing.json"
SESSIONS_FILE="$COST_DATA_DIR/sessions.jsonl"

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "cost-tracker: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

# Read hook input from stdin
INPUT=$(cat)

# Extract fields from hook input (single jq parse)
_parsed=$(echo "$INPUT" | jq -r '
  [(.stop_hook_active // false | tostring), (.session_id // ""), (.transcript_path // "")] | @tsv
')
STOP_HOOK_ACTIVE=$(printf '%s' "$_parsed" | cut -f1)
SESSION_ID=$(printf '%s' "$_parsed" | cut -f2)
TRANSCRIPT_PATH=$(printf '%s' "$_parsed" | cut -f3)

# Guard: prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Validate required fields
if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  echo "cost-tracker: missing session_id or transcript_path in hook input" >&2
  exit 1
fi

# Validate session_id is a UUID (prevent path traversal)
if ! [[ "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "cost-tracker: invalid session_id format: $SESSION_ID" >&2
  exit 0
fi

# Validate transcript file exists
if [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "cost-tracker: transcript file not found: $TRANSCRIPT_PATH" >&2
  exit 1
fi

# Ensure cost data directory exists
mkdir -p "$COST_DATA_DIR"

# --- Parse transcript and aggregate token usage by model ---

# Helper: extract deduped usage from a transcript file.
# The transcript records each content block (text, thinking, tool_use) from the
# same API call as a separate assistant message with identical usage data.
# To avoid double-counting, we keep only the LAST assistant message in each
# consecutive chain (which carries the final cumulative usage for that API call).
extract_usage() {
  local file="$1"
  jq -R -c 'try fromjson catch empty' "$file" 2>/dev/null | jq -s '
    [range(length) as $i | {
      type: .[$i].type,
      model: .[$i].message.model,
      usage: .[$i].message.usage,
      next_type: (.[$i+1].type // "none")
    }] |
    [.[] | select(
      .type == "assistant" and
      (.usage | type) == "object" and
      (.next_type | . == "assistant" | not)
    ) | {model, usage}]
  ' 2>/dev/null || echo '[]'
}

# --- Single-pass parse of main transcript ---
# Extracts usage, timestamps, and durations in one jq pipeline (resilient to malformed lines)
MAIN_PARSE=$(jq -R -c 'try fromjson catch empty' "$TRANSCRIPT_PATH" 2>/dev/null | jq -s '
  def to_epoch_ms:
    (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) * 1000 +
    (if test("\\.[0-9]+Z$") then
      (capture("\\.(?<f>[0-9]+)Z$").f + "000" | .[0:3] | tonumber)
    else 0 end);

  [range(length) as $i | {
    type: .[$i].type,
    model: .[$i].message.model,
    usage: .[$i].message.usage,
    timestamp: .[$i].timestamp,
    next_type: (.[$i+1].type // "none")
  }] as $entries |

  {
    usage: [$entries[] | select(
      .type == "assistant" and
      (.usage | type) == "object" and
      (.next_type == "assistant" | not)
    ) | {model, usage}],

    session_start: ([$entries[] | select(.timestamp != null) | .timestamp] | sort | .[0] // ""),
    session_end: ([$entries[] | select(.timestamp != null) | .timestamp] | sort | .[-1] // ""),

    wall_duration_ms: (
      [$entries[] | select(.timestamp != null) | .timestamp] | sort |
      if length >= 2 then ((.[-1] | to_epoch_ms) - (.[0] | to_epoch_ms))
      else 0 end
    ),

    api_duration_ms: (
      [$entries, $entries[1:]] | transpose |
      map(select(
        .[0].type == "user" and .[1].type == "assistant" and
        .[0].timestamp != null and .[1].timestamp != null
      )) |
      map(((.[1].timestamp | to_epoch_ms) - (.[0].timestamp | to_epoch_ms))) |
      add // 0
    )
  }
') || {
  echo "cost-tracker: failed to parse transcript" >&2
  exit 1
}

ALL_USAGE=$(echo "$MAIN_PARSE" | jq '.usage')
SESSION_START=$(echo "$MAIN_PARSE" | jq -r '.session_start')
SESSION_END=$(echo "$MAIN_PARSE" | jq -r '.session_end')
WALL_DURATION_MS=$(echo "$MAIN_PARSE" | jq '.wall_duration_ms')
API_DURATION_MS=$(echo "$MAIN_PARSE" | jq '.api_duration_ms')

# Include subagent transcripts if present (single merge instead of O(n) merges)
TRANSCRIPT_DIR="$(dirname "$TRANSCRIPT_PATH")"
SESSION_DIR="$TRANSCRIPT_DIR/$SESSION_ID"
if [ -d "$SESSION_DIR/subagents" ]; then
  SUB_USAGES=()
  for sub_file in "$SESSION_DIR"/subagents/*.jsonl; do
    [ -f "$sub_file" ] || continue
    SUB_USAGES+=("$(extract_usage "$sub_file")")
  done
  if [ ${#SUB_USAGES[@]} -gt 0 ]; then
    ALL_USAGE=$(printf '%s\n' "$ALL_USAGE" "${SUB_USAGES[@]}" | jq -s 'add')
  fi
fi

# Count turns (deduplicated assistant messages = API calls)
TURNS=$(echo "$ALL_USAGE" | jq 'length')

# Aggregate by model (with total_tokens per model)
MODEL_USAGE=$(echo "$ALL_USAGE" | jq '
  group_by(.model) |
  map({
    model: .[0].model,
    input_tokens: ([.[].usage.input_tokens // 0] | add),
    output_tokens: ([.[].usage.output_tokens // 0] | add),
    cache_read_tokens: ([.[].usage.cache_read_input_tokens // 0] | add),
    cache_write_tokens: ([.[].usage.cache_creation_input_tokens // 0] | add)
  } | . + {total_tokens: (.input_tokens + .output_tokens + .cache_read_tokens + .cache_write_tokens)})
') || {
  echo "cost-tracker: failed to aggregate usage" >&2
  exit 1
}

# --- Load pricing and calculate costs ---

# Load pricing data (fall back to Sonnet-tier defaults if file missing)
if [ -f "$PRICING_FILE" ]; then
  PRICING=$(cat "$PRICING_FILE")
else
  echo "cost-tracker: pricing file not found, using fallback (sonnet-tier) defaults" >&2
  PRICING='{"version":0,"models":[],"fallback":{"tier":"sonnet","input_per_mtok":3.00,"output_per_mtok":15.00,"cache_read_per_mtok":0.30,"cache_write_per_mtok":3.75}}'
fi

# Extract pricing version for audit trail
PRICING_VERSION=$(echo "$PRICING" | jq '.version // 0')

# Calculate per-model costs using longest-prefix match, with fallback pricing
MODEL_USAGE_WITH_COST=$(echo "$MODEL_USAGE" | jq --argjson pricing "$PRICING" '
  map(. as $usage |
    ($pricing.models
     | map(select(.model_pattern as $pat | $usage.model | startswith($pat)))
     | sort_by(.model_pattern | length) | reverse | .[0] // null) as $price |
    if $price then
      . + {
        cost_usd: ((
          ($usage.input_tokens * $price.input_per_mtok / 1000000) +
          ($usage.output_tokens * $price.output_per_mtok / 1000000) +
          ($usage.cache_read_tokens * $price.cache_read_per_mtok / 1000000) +
          ($usage.cache_write_tokens * $price.cache_write_per_mtok / 1000000)
        ) * 10000 | round | . / 10000),
        pricing_estimated: false
      }
    elif ($pricing.fallback // null) then
      . + {
        cost_usd: ((
          ($usage.input_tokens * $pricing.fallback.input_per_mtok / 1000000) +
          ($usage.output_tokens * $pricing.fallback.output_per_mtok / 1000000) +
          ($usage.cache_read_tokens * $pricing.fallback.cache_read_per_mtok / 1000000) +
          ($usage.cache_write_tokens * $pricing.fallback.cache_write_per_mtok / 1000000)
        ) * 10000 | round | . / 10000),
        pricing_estimated: true
      }
    else
      . + {cost_usd: 0, pricing_estimated: true}
    end
  )
')

# Warn about models that used fallback pricing
UNMATCHED=$(echo "$MODEL_USAGE_WITH_COST" | jq -r '
  [.[] | select(.pricing_estimated == true and (.input_tokens + .output_tokens) > 0) | .model] | .[]
')
if [ -n "$UNMATCHED" ]; then
  while IFS= read -r model_name; do
    echo "cost-tracker: no pricing match for model '$model_name', using fallback (sonnet-tier) — add to pricing.json" >&2
  done <<< "$UNMATCHED"
fi

TOTAL_COST=$(echo "$MODEL_USAGE_WITH_COST" | jq '[.[].cost_usd] | add // 0 | . * 10000 | round | . / 10000')
TOTAL_TOKENS=$(echo "$MODEL_USAGE_WITH_COST" | jq '[.[].total_tokens] | add // 0')
PRICING_ESTIMATED=$(echo "$MODEL_USAGE_WITH_COST" | jq '[.[].pricing_estimated] | any')

# --- Track code changes ---

# Use git diff --stat for accurate line counts (tracks uncommitted changes)
if command -v git &>/dev/null && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
  DIFF_STAT=$(git -C "$PROJECT_DIR" diff --stat HEAD 2>/dev/null | tail -1)
  LINES_ADDED=$(echo "$DIFF_STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
  LINES_REMOVED=$(echo "$DIFF_STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
  [ -z "$LINES_ADDED" ] && LINES_ADDED=0
  [ -z "$LINES_REMOVED" ] && LINES_REMOVED=0
else
  LINES_ADDED=0
  LINES_REMOVED=0
fi

# --- Assemble and write cost record ---

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

COST_RECORD=$(jq -cn \
  --arg session_id "$SESSION_ID" \
  --arg timestamp "$TIMESTAMP" \
  --arg session_start "$SESSION_START" \
  --arg session_end "$SESSION_END" \
  --argjson api_duration_ms "$API_DURATION_MS" \
  --argjson wall_duration_ms "$WALL_DURATION_MS" \
  --argjson lines_added "$LINES_ADDED" \
  --argjson lines_removed "$LINES_REMOVED" \
  --argjson total_cost_usd "$TOTAL_COST" \
  --argjson turns "$TURNS" \
  --argjson total_tokens "$TOTAL_TOKENS" \
  --argjson pricing_version "$PRICING_VERSION" \
  --argjson pricing_estimated "$PRICING_ESTIMATED" \
  --argjson models "$MODEL_USAGE_WITH_COST" \
  '{
    session_id: $session_id,
    timestamp: $timestamp,
    session_start: $session_start,
    session_end: $session_end,
    api_duration_ms: $api_duration_ms,
    wall_duration_ms: $wall_duration_ms,
    lines_added: $lines_added,
    lines_removed: $lines_removed,
    total_cost_usd: $total_cost_usd,
    turns: $turns,
    total_tokens: $total_tokens,
    pricing_version: $pricing_version,
    pricing_estimated: $pricing_estimated,
    models: $models
  }')

# Atomic upsert: replace previous record for this session_id, write atomically
LOCKDIR="$SESSIONS_FILE.lock"
if mkdir "$LOCKDIR" 2>/dev/null; then
  trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT
  TEMP_FILE="$SESSIONS_FILE.tmp.$$"
  if [ -f "$SESSIONS_FILE" ]; then
    # Keep all records except previous entries for this session
    jq -R -c --arg sid "$SESSION_ID" \
      'try (fromjson | select(.session_id != $sid)) catch empty' \
      "$SESSIONS_FILE" > "$TEMP_FILE" 2>/dev/null || true
  else
    : > "$TEMP_FILE"
  fi
  printf '%s\n' "$COST_RECORD" >> "$TEMP_FILE"
  mv -f "$TEMP_FILE" "$SESSIONS_FILE"
  rmdir "$LOCKDIR" 2>/dev/null || true
  trap - EXIT
else
  # Lock contention: fall back to append (consumers still handle dedup)
  printf '%s\n' "$COST_RECORD" >> "$SESSIONS_FILE"
fi

exit 0
HOOK_SCRIPT_EOF
  chmod +x "$target"
}

# --- T003: Embed slash command files ---
write_command_files() {
  local commands_dir="$1"

  # cost-report.md
  cat > "$commands_dir/cost-report.md" << 'COST_REPORT_CMD_EOF'
---
name: cost-report
description: Generate a full cost summary report across all tracked sessions
---

You are generating a cost report from Claude Code session cost data.

## Data Sources

**IMPORTANT**: First, use the Read tool to load these two files before proceeding:
1. `.claude/cost-data/sessions.jsonl` — JSONL session cost records (one JSON object per line)
2. `.claude/cost-data/pricing.json` — token pricing configuration

If sessions.jsonl does not exist or is empty, respond with: "No cost data recorded yet. Cost data is automatically captured after each conversation via the Stop hook." and stop.

## Arguments

$ARGUMENTS

## Instructions

1. **Read both files** listed above using the Read tool. Parse each line of sessions.jsonl as a separate JSON object.

2. **Deduplicate by session_id**: If multiple records share the same `session_id`, keep only the one with the latest `timestamp`.

3. **Aggregate totals** across all deduplicated sessions:
   - Total cost (sum of `total_cost_usd`, format to 4 decimal places)
   - Total sessions (count of unique session_ids)
   - Total turns (sum of `turns`)
   - Total tokens (sum of `total_tokens`)
   - Total API duration (sum of `api_duration_ms`, format as `Xh Xm Xs`)
   - Total wall time (sum of `wall_duration_ms`, format as `Xh Xm Xs`)
   - Total lines added (sum of `lines_added`)
   - Total lines removed (sum of `lines_removed`)
   - Per-model token totals (sum `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `total_tokens` across all sessions, grouped by model)
   - Per-model cost totals (sum `cost_usd` per model)
   - Pricing version (from `pricing_version` field — show the latest version seen)
   - Pricing estimated flag: if any session has `pricing_estimated: true`, show a warning

4. **Format token counts** for display:
   - Under 1,000: show as-is (e.g., `800`)
   - 1,000-999,999: show as `X.Xk` (e.g., `3.2k`)
   - 1,000,000+: show as `X.Xm` (e.g., `1.2m`)

5. **Display in conversation** using this format:

```
## Cost Report Summary

Total cost:         $X.XXXX
Total sessions:     N
Total turns:        N
Total tokens:       X.Xm
Total API duration: Xh Xm Xs
Total wall time:    Xh Xm Xs
Total code changes: X lines added, X lines removed
Pricing version:    N
⚠ Some sessions used estimated (fallback) pricing   ← only if pricing_estimated is true

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Total | Cost | Est? |
|-------|-------|--------|------------|-------------|-------|------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | X.Xm | $X.XXXX | |
| claude-unknown | X.Xk | X.Xk | X.Xk | X.Xk | X.Xk | $X.XXXX | * |

* = estimated (fallback) pricing used for this model

Report saved to: .claude/cost-data/report.md
```

6. **Write a detailed report** to `.claude/cost-data/report.md` containing:
   - All of the summary above
   - A **Daily Breakdown** table grouped by date (YYYY-MM-DD):

     | Date | Sessions | Cost | API Duration | Wall Time |
     |------|----------|------|--------------|-----------|

   - A **Per-Session Detail** table:

     | Session ID | Date | Cost | API Duration | Wall Time | Models | Lines +/- |
     |------------|------|------|--------------|-----------|--------|-----------|

   Use the Bash tool to write the report file: `cat > .claude/cost-data/report.md << 'REPORT_EOF'` followed by the full report content.

7. If `$ARGUMENTS` contains filter terms (like a date or model name), apply reasonable filtering before aggregating. If the filter doesn't match anything, say so.
COST_REPORT_CMD_EOF

  # cost-session.md
  cat > "$commands_dir/cost-session.md" << 'COST_SESSION_CMD_EOF'
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
Total cost:     $X.XXXX
Turns:          N
Total tokens:   X.Xm
API duration:   Xm Xs
Wall time:      Xm Xs
Code changes:   X lines added, X lines removed
Pricing version: N
⚠ Some costs are estimated (fallback pricing)   ← only if pricing_estimated is true

### Usage by Model

| Model | Input | Output | Cache Read | Cache Write | Total | Cost | Est? |
|-------|-------|--------|------------|-------------|-------|------|------|
| claude-opus-4-6 | X.Xk | X.Xk | X.Xm | X.Xk | X.Xm | $X.XXXX | |
| claude-unknown | X.Xk | X.Xk | X.Xk | X.Xk | X.Xk | $X.XXXX | * |

* = estimated (fallback) pricing used for this model
```

Do NOT write any files. Display only.
COST_SESSION_CMD_EOF

  # cost-reset.md
  cat > "$commands_dir/cost-reset.md" << 'COST_RESET_CMD_EOF'
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
COST_RESET_CMD_EOF
}

# --- T004: Embed pricing.json ---
write_pricing_config() {
  local target="$1"
  cat > "$target" << 'PRICING_JSON_EOF'
{
  "version": 2,
  "updated": "2026-04-01",
  "models": [
    {
      "model_pattern": "claude-opus-4-6",
      "input_per_mtok": 5.00,
      "output_per_mtok": 25.00,
      "cache_read_per_mtok": 0.50,
      "cache_write_per_mtok": 6.25
    },
    {
      "model_pattern": "claude-sonnet-4-6",
      "input_per_mtok": 3.00,
      "output_per_mtok": 15.00,
      "cache_read_per_mtok": 0.30,
      "cache_write_per_mtok": 3.75
    },
    {
      "model_pattern": "claude-opus-4-5",
      "input_per_mtok": 5.00,
      "output_per_mtok": 25.00,
      "cache_read_per_mtok": 0.50,
      "cache_write_per_mtok": 6.25
    },
    {
      "model_pattern": "claude-haiku-4-5",
      "input_per_mtok": 1.00,
      "output_per_mtok": 5.00,
      "cache_read_per_mtok": 0.10,
      "cache_write_per_mtok": 1.25
    },
    {
      "model_pattern": "claude-sonnet-4-5",
      "input_per_mtok": 3.00,
      "output_per_mtok": 15.00,
      "cache_read_per_mtok": 0.30,
      "cache_write_per_mtok": 3.75
    },
    {
      "model_pattern": "claude-sonnet-4",
      "input_per_mtok": 3.00,
      "output_per_mtok": 15.00,
      "cache_read_per_mtok": 0.30,
      "cache_write_per_mtok": 3.75
    },
    {
      "model_pattern": "claude-opus-4-1",
      "input_per_mtok": 15.00,
      "output_per_mtok": 75.00,
      "cache_read_per_mtok": 1.50,
      "cache_write_per_mtok": 18.75
    },
    {
      "model_pattern": "claude-opus-4-",
      "input_per_mtok": 15.00,
      "output_per_mtok": 75.00,
      "cache_read_per_mtok": 1.50,
      "cache_write_per_mtok": 18.75
    }
  ],
  "fallback": {
    "tier": "sonnet",
    "input_per_mtok": 3.00,
    "output_per_mtok": 15.00,
    "cache_read_per_mtok": 0.30,
    "cache_write_per_mtok": 3.75
  }
}
PRICING_JSON_EOF
}

# ============================================================================
# Phase 5: Prerequisite validation (US3 — runs first at runtime)
# ============================================================================

# --- T015: Check prerequisites ---
check_prerequisites() {
  local os_name
  os_name="$(uname -s)"

  # Check bash version (3.2+)
  if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    print_error "Bash 3.2+ is required. Current: ${BASH_VERSION}"
    exit "$EXIT_PREREQ_FAIL"
  fi

  # Check jq
  if ! command -v jq &>/dev/null; then
    print_error "jq is required but not installed."
    echo ""
    echo "Install jq:"
    case "$os_name" in
      Darwin)
        echo "  macOS:  brew install jq"
        ;;
      Linux)
        echo "  Ubuntu: sudo apt install jq"
        echo "  Fedora: sudo dnf install jq"
        ;;
      *)
        echo "  Visit: https://jqlang.github.io/jq/download/"
        ;;
    esac
    exit "$EXIT_PREREQ_FAIL"
  fi
}

# ============================================================================
# Phase 3: Core installation functions (US1)
# ============================================================================

# --- T005: Detect project root ---
detect_project_root() {
  # Strategy 1: git root
  if command -v git &>/dev/null; then
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
    if [ -n "$git_root" ]; then
      PROJECT_ROOT="$git_root"
      return
    fi
  fi

  # Strategy 2: walk up looking for .claude/
  local dir
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.claude" ]; then
      PROJECT_ROOT="$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done

  # Strategy 3: fall back to cwd
  PROJECT_ROOT="$(pwd)"
}

# --- T016: Handle missing .claude/ directory ---
handle_no_claude_dir() {
  if [ -d "$PROJECT_ROOT/.claude" ]; then
    return
  fi

  if [ "$FORCE" = true ]; then
    return
  fi

  print_warning "No .claude/ directory found at: $PROJECT_ROOT"
  echo "  This doesn't appear to be a Claude Code project yet."
  echo ""

  # Read from /dev/tty to support curl | bash (stdin is the script itself)
  if [ -t 0 ]; then
    read -r -p "Create .claude/ directory and proceed? [y/N] " answer
  else
    read -r -p "Create .claude/ directory and proceed? [y/N] " answer < /dev/tty 2>/dev/null || {
      print_error "Cannot prompt for confirmation (no terminal). Use --force to skip."
      exit "$EXIT_CANCELLED"
    }
  fi

  case "$answer" in
    [yY]|[yY][eE][sS])
      return
      ;;
    *)
      echo "Installation cancelled."
      exit "$EXIT_CANCELLED"
      ;;
  esac
}

# --- T006: Create directories ---
create_directories() {
  print_step "Creating directories..."
  local dirs=(".claude/hooks" ".claude/commands" ".claude/cost-data")
  for dir in "${dirs[@]}"; do
    local full_path="$PROJECT_ROOT/$dir"
    if ! mkdir -p "$full_path" 2>/dev/null; then
      print_error "Permission denied: cannot create $dir"
      exit "$EXIT_FILE_ERROR"
    fi
    print_success "$dir/"
  done
  echo ""
}

# --- T007: Create fresh settings.local.json ---
create_fresh_settings() {
  local settings_file="$PROJECT_ROOT/.claude/settings.local.json"
  cat > "$settings_file" << 'SETTINGS_JSON_EOF'
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
SETTINGS_JSON_EOF
}

# ============================================================================
# Phase 4: Safe installation functions (US2)
# ============================================================================

# --- T010: Detect installation state ---
detect_install_state() {
  local count=0
  local files=(
    ".claude/hooks/cost-tracker.sh"
    ".claude/commands/cost-report.md"
    ".claude/commands/cost-session.md"
    ".claude/commands/cost-reset.md"
    ".claude/cost-data/pricing.json"
  )
  for f in "${files[@]}"; do
    [ -f "$PROJECT_ROOT/$f" ] && count=$((count + 1))
  done

  if [ "$count" -eq 0 ]; then
    INSTALL_STATE="FRESH"
  elif [ "$count" -lt 5 ]; then
    INSTALL_STATE="PARTIAL"
  else
    INSTALL_STATE="ALREADY_INSTALLED"
  fi
}

# --- T011: Backup existing files ---
backup_existing_files() {
  local files=(
    ".claude/hooks/cost-tracker.sh"
    ".claude/commands/cost-report.md"
    ".claude/commands/cost-session.md"
    ".claude/commands/cost-reset.md"
    ".claude/cost-data/pricing.json"
  )
  local backed_up=false
  for f in "${files[@]}"; do
    local full_path="$PROJECT_ROOT/$f"
    if [ -f "$full_path" ]; then
      cp "$full_path" "$full_path.bak"
      backed_up=true
    fi
  done
  if [ "$backed_up" = true ]; then
    print_success "Backed up existing files (.bak)"
  fi
}

# --- T012: Merge settings.local.json ---
merge_settings() {
  local settings_file="$PROJECT_ROOT/.claude/settings.local.json"
  local hook_command='"$CLAUDE_PROJECT_DIR"/.claude/hooks/cost-tracker.sh'

  local new_hook
  new_hook='{"matcher":"","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/cost-tracker.sh","timeout":30000}]}'

  if [ ! -f "$settings_file" ]; then
    create_fresh_settings
    return
  fi

  # Validate existing JSON
  if ! jq empty "$settings_file" 2>/dev/null; then
    handle_malformed_json "$settings_file"
    return
  fi

  # Idempotent merge: remove existing cost-tracker entry, then append
  local merged
  merged=$(jq --argjson new_hook "$new_hook" --arg cmd "$hook_command" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    .hooks.Stop = [
      (.hooks.Stop[] | select(
        ([.hooks[]? | .command] | any(. == $cmd)) | not
      ))
    ] + [$new_hook]
  ' "$settings_file") || {
    print_error "Failed to merge settings"
    exit "$EXIT_FILE_ERROR"
  }

  # Atomic write via temp file
  local temp_file
  temp_file=$(mktemp "$settings_file.XXXXXX")
  echo "$merged" > "$temp_file"
  mv -f "$temp_file" "$settings_file"
}

# --- T013: Handle malformed JSON ---
handle_malformed_json() {
  local settings_file="$1"
  print_warning "Malformed JSON detected in settings.local.json"
  cp "$settings_file" "$settings_file.bak"
  print_success "Backup created: settings.local.json.bak"
  echo "  Creating fresh settings file. Merge your old settings manually from the backup."
  create_fresh_settings
}

# --- T008: Print summary ---
print_summary() {
  local status_msg="$1"
  echo "Writing files..."
  print_success ".claude/hooks/cost-tracker.sh (executable)"
  print_success ".claude/commands/cost-report.md"
  print_success ".claude/commands/cost-session.md"
  print_success ".claude/commands/cost-reset.md"
  print_success ".claude/cost-data/pricing.json"
  echo ""
  echo "Configuring hooks..."
  print_success "Updated .claude/settings.local.json"
  echo ""
  echo "Installation complete! ($status_msg)"
  echo ""
  echo "Zero-overhead data capture: the Stop hook runs as a local bash"
  echo "script with no API calls. Slash commands use normal Claude tokens."
  echo ""
  echo "Next steps:"
  echo "  1. Start a new Claude Code session in $PROJECT_ROOT"
  echo "  2. Use /cost-session to see costs after your first conversation"
  echo "  3. Use /cost-report for a full summary across sessions"
}

# ============================================================================
# Main flow (T009, T014, T017 — wired together)
# ============================================================================

main() {
  parse_args "$@"

  print_header

  # T017: Prerequisites first (US3)
  check_prerequisites

  # T005: Detect project root
  detect_project_root
  echo "Target: $PROJECT_ROOT"

  # T016: Handle missing .claude/ dir (US3)
  handle_no_claude_dir

  # T010: Detect install state (US2)
  detect_install_state
  echo "Status: $INSTALL_STATE"
  echo ""

  # T014: Branch on state (US2)
  case "$INSTALL_STATE" in
    FRESH)
      create_directories
      write_hook_script "$PROJECT_ROOT/.claude/hooks/cost-tracker.sh"
      write_command_files "$PROJECT_ROOT/.claude/commands"
      write_pricing_config "$PROJECT_ROOT/.claude/cost-data/pricing.json"
      merge_settings
      print_summary "Fresh install"
      ;;
    PARTIAL)
      echo "Partial installation detected — repairing..."
      echo ""
      create_directories
      backup_existing_files
      write_hook_script "$PROJECT_ROOT/.claude/hooks/cost-tracker.sh"
      write_command_files "$PROJECT_ROOT/.claude/commands"
      write_pricing_config "$PROJECT_ROOT/.claude/cost-data/pricing.json"
      merge_settings
      print_summary "Repair complete"
      ;;
    ALREADY_INSTALLED)
      echo "Existing installation detected — updating to latest version..."
      echo ""
      create_directories
      backup_existing_files
      write_hook_script "$PROJECT_ROOT/.claude/hooks/cost-tracker.sh"
      write_command_files "$PROJECT_ROOT/.claude/commands"
      write_pricing_config "$PROJECT_ROOT/.claude/cost-data/pricing.json"
      merge_settings
      print_summary "Update complete"
      ;;
  esac

  exit "$EXIT_SUCCESS"
}

main "$@"
