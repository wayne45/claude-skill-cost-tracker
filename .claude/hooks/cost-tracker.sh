#!/usr/bin/env bash
# Claude Code Cost Tracker - Stop Hook
# Parses session transcript to track token usage, durations, code changes, and costs.
# Writes cost records to .claude/cost-data/sessions.jsonl

set -euo pipefail

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

# Extract fields from hook input
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Guard: prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Validate required fields
if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  echo "cost-tracker: missing session_id or transcript_path in hook input" >&2
  exit 1
fi

# Validate transcript file exists
if [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "cost-tracker: transcript file not found: $TRANSCRIPT_PATH" >&2
  exit 1
fi

# Ensure cost data directory exists
mkdir -p "$COST_DATA_DIR"

# --- Parse transcript and aggregate token usage by model ---

# Extract all assistant messages with usage data, aggregate by model
# Uses jq -R -c to handle malformed lines gracefully (skip unparseable lines with warning)
MODEL_USAGE=$(jq -R -c 'try fromjson catch empty' "$TRANSCRIPT_PATH" 2>/dev/null | jq -s '
  [.[] | select(.type == "assistant" and .message.usage != null)] |
  group_by(.message.model) |
  map({
    model: .[0].message.model,
    input_tokens: (map(.message.usage.input_tokens // 0) | add),
    output_tokens: (map(.message.usage.output_tokens // 0) | add),
    cache_read_tokens: (map(.message.usage.cache_read_input_tokens // 0) | add),
    cache_write_tokens: (map(.message.usage.cache_creation_input_tokens // 0) | add)
  })
') || {
  echo "cost-tracker: failed to parse transcript" >&2
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

# Calculate per-model costs using pricing lookup with prefix matching
MODEL_USAGE_WITH_COST=$(echo "$MODEL_USAGE" | jq --argjson pricing "$PRICING" '
  map(. as $usage |
    ($pricing.models | map(select(.model_pattern as $pat | $usage.model | startswith($pat))) | .[0] // null) as $price |
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

TOTAL_COST=$(echo "$MODEL_USAGE_WITH_COST" | jq '[.[].cost_usd] | add // 0 | . * 1000000 | round | . / 1000000')

# --- Calculate durations ---

# Get all message timestamps sorted (resilient to malformed lines)
TIMESTAMPS=$(jq -R -c 'try fromjson catch empty' "$TRANSCRIPT_PATH" 2>/dev/null | jq -s '
  [.[] | select(.timestamp != null) | .timestamp] | sort
')

SESSION_START=$(echo "$TIMESTAMPS" | jq -r '.[0] // empty')
SESSION_END=$(echo "$TIMESTAMPS" | jq -r '.[-1] // empty')

# Calculate wall duration in milliseconds
if [ -n "$SESSION_START" ] && [ -n "$SESSION_END" ]; then
  # Use jq for ISO 8601 date math (portable)
  WALL_DURATION_MS=$(jq -n --arg start "$SESSION_START" --arg end "$SESSION_END" '
    (($end | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) -
     ($start | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) * 1000
  ' 2>/dev/null) || WALL_DURATION_MS=0
else
  WALL_DURATION_MS=0
fi

# Calculate API duration: sum of time between user messages and their assistant responses
API_DURATION_MS=$(jq -R -c 'try fromjson catch empty' "$TRANSCRIPT_PATH" 2>/dev/null | jq -s '
  [., .[1:]] | transpose |
  map(select(.[0].type == "user" and .[1].type == "assistant" and .[0].timestamp != null and .[1].timestamp != null)) |
  map(
    ((.[1].timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) -
     (.[0].timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) * 1000
  ) | add // 0
') || API_DURATION_MS=0

# --- Track code changes ---

# Count lines added/removed from Edit and Write tool results in transcript
CODE_CHANGES=$(jq -R -c 'try fromjson catch empty' "$TRANSCRIPT_PATH" 2>/dev/null | jq -s '
  def count_changes:
    [.[] | select(.type == "assistant" and .message.content != null) |
     .message.content[] |
     select(.type == "tool_result" or .type == "tool_use") |
     .text // .content // "" |
     if type == "string" then . else "" end
    ] |
    join("\n") |
    {
      lines_added: (split("\n") | map(select(startswith("+"))) | length),
      lines_removed: (split("\n") | map(select(startswith("-"))) | length)
    };
  count_changes
') || CODE_CHANGES='{"lines_added":0,"lines_removed":0}'

LINES_ADDED=$(echo "$CODE_CHANGES" | jq '.lines_added // 0')
LINES_REMOVED=$(echo "$CODE_CHANGES" | jq '.lines_removed // 0')

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

# Atomic append (single line write)
printf '%s\n' "$COST_RECORD" >> "$SESSIONS_FILE"

exit 0
