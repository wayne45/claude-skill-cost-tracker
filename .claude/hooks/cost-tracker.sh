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

# Aggregate by model
MODEL_USAGE=$(echo "$ALL_USAGE" | jq '
  group_by(.model) |
  map({
    model: .[0].model,
    input_tokens: ([.[].usage.input_tokens // 0] | add),
    output_tokens: ([.[].usage.output_tokens // 0] | add),
    cache_read_tokens: ([.[].usage.cache_read_input_tokens // 0] | add),
    cache_write_tokens: ([.[].usage.cache_creation_input_tokens // 0] | add)
  })
') || {
  echo "cost-tracker: failed to aggregate usage" >&2
  exit 1
}

# --- Load pricing and calculate costs ---

# Load pricing data (fall back to empty if file missing)
if [ -f "$PRICING_FILE" ]; then
  PRICING=$(cat "$PRICING_FILE")
else
  echo "cost-tracker: pricing file not found, using zero costs" >&2
  PRICING='{"models":[],"fallback_formula":{"cache_read_ratio":0.10,"cache_write_ratio":0.25}}'
fi

# Calculate per-model costs using longest-prefix match on pricing patterns
MODEL_USAGE_WITH_COST=$(echo "$MODEL_USAGE" | jq --argjson pricing "$PRICING" '
  map(. as $usage |
    ($pricing.models
     | map(select(.model_pattern as $pat | $usage.model | startswith($pat)))
     | sort_by(.model_pattern | length) | reverse | .[0] // null) as $price |
    if $price then
      . + {cost_usd: ((
        ($usage.input_tokens * $price.input_per_mtok / 1000000) +
        ($usage.output_tokens * $price.output_per_mtok / 1000000) +
        ($usage.cache_read_tokens * $price.cache_read_per_mtok / 1000000) +
        ($usage.cache_write_tokens * $price.cache_write_per_mtok / 1000000)
      ) * 1000000 | round | . / 1000000)}
    else
      . + {cost_usd: 0}
    end
  )
')

# Warn about models missing from pricing configuration
UNMATCHED=$(echo "$MODEL_USAGE_WITH_COST" | jq -r '
  [.[] | select(.cost_usd == 0 and (.input_tokens + .output_tokens) > 0) | .model] | .[]
')
if [ -n "$UNMATCHED" ]; then
  echo "cost-tracker: no pricing for model(s): $UNMATCHED — add to pricing.json" >&2
fi

TOTAL_COST=$(echo "$MODEL_USAGE_WITH_COST" | jq '[.[].cost_usd] | add // 0 | . * 1000000 | round | . / 1000000')

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
