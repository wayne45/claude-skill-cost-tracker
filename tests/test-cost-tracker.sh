#!/usr/bin/env bash
# Validation test for the cost-tracker hook
# Usage: bash tests/test-cost-tracker.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PROJECT_DIR/.claude/hooks/cost-tracker.sh"
FIXTURE="$PROJECT_DIR/tests/fixtures/sample-transcript.jsonl"
SESSIONS_FILE="$PROJECT_DIR/.claude/cost-data/sessions.jsonl"

PASS=0
FAIL=0

check() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected: $expected, got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Cost Tracker Hook Tests ==="
echo

# Clean up before test
rm -f "$SESSIONS_FILE"

# --- Test 1: stop_hook_active guard ---
echo "Test 1: stop_hook_active=true exits silently"
echo '{"stop_hook_active":true}' | bash "$HOOK" 2>/dev/null
EXIT_CODE=$?
check "exit code is 0" "$EXIT_CODE" "0"
check "no sessions file created" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "missing"

# --- Test 2: missing fields ---
echo
echo "Test 2: missing session_id returns error"
OUTPUT=$(echo '{"session_id":"","transcript_path":"","stop_hook_active":false}' | bash "$HOOK" 2>&1) || true
check "error message mentions missing" "$(echo "$OUTPUT" | grep -c 'missing')" "1"

# --- Test 3: successful run with sample fixture ---
echo
echo "Test 3: successful run with sample transcript"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000001\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "sessions file created" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "exists"
check "output is single line" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "1"

# Parse the output record
RECORD=$(cat "$SESSIONS_FILE")
check "valid JSON" "$(echo "$RECORD" | jq -e . >/dev/null 2>&1&& echo "valid" || echo "invalid")" "valid"
check "session_id matches" "$(echo "$RECORD" | jq -r '.session_id')" "00000000-0000-0000-0000-000000000001"
check "wall_duration_ms is 130000" "$(echo "$RECORD" | jq '.wall_duration_ms')" "130000"

# Check model token aggregation
OPUS_INPUT=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .input_tokens] | add')
OPUS_OUTPUT=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .output_tokens] | add')
OPUS_CACHE_READ=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .cache_read_tokens] | add')
OPUS_CACHE_WRITE=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .cache_write_tokens] | add')
check "opus input_tokens = 3500" "$OPUS_INPUT" "3500"
check "opus output_tokens = 1300" "$OPUS_OUTPUT" "1300"
check "opus cache_read = 110000" "$OPUS_CACHE_READ" "110000"
check "opus cache_write = 8000" "$OPUS_CACHE_WRITE" "8000"

HAIKU_INPUT=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .input_tokens] | add')
check "haiku input_tokens = 800" "$HAIKU_INPUT" "800"

# Check cost calculations
OPUS_COST=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .cost_usd] | add')
HAIKU_COST=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .cost_usd] | add')
TOTAL_COST=$(echo "$RECORD" | jq '.total_cost_usd')
check "opus cost = 0.345" "$OPUS_COST" "0.345"
check "haiku cost = 0.00244" "$HAIKU_COST" "0.00244"
check "total cost = 0.34744" "$TOTAL_COST" "0.34744"

# Check required fields exist
check "has timestamp" "$(echo "$RECORD" | jq 'has("timestamp")')" "true"
check "has session_start" "$(echo "$RECORD" | jq 'has("session_start")')" "true"
check "has session_end" "$(echo "$RECORD" | jq 'has("session_end")')" "true"
check "has api_duration_ms" "$(echo "$RECORD" | jq 'has("api_duration_ms")')" "true"
check "has lines_added" "$(echo "$RECORD" | jq 'has("lines_added")')" "true"
check "has lines_removed" "$(echo "$RECORD" | jq 'has("lines_removed")')" "true"
check "has models array" "$(echo "$RECORD" | jq -r '.models | type')" "array"
check "2 models tracked" "$(echo "$RECORD" | jq '.models | length')" "2"

# --- Test 4: idempotent append ---
echo
echo "Test 4: second run appends (does not overwrite)"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000002\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "sessions file has 2 lines" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "2"

# Clean up
rm -f "$SESSIONS_FILE"

# --- Summary ---
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
