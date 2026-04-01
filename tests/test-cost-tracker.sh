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
check "api_duration_ms is 55000" "$(echo "$RECORD" | jq '.api_duration_ms')" "55000"
check "session_start is correct" "$(echo "$RECORD" | jq -r '.session_start')" "2026-03-05T09:00:00.000Z"
check "session_end is correct" "$(echo "$RECORD" | jq -r '.session_end')" "2026-03-05T09:02:10.000Z"

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
HAIKU_OUTPUT=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .output_tokens] | add')
HAIKU_CACHE_READ=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .cache_read_tokens] | add')
HAIKU_CACHE_WRITE=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .cache_write_tokens] | add')
check "haiku input_tokens = 800" "$HAIKU_INPUT" "800"
check "haiku output_tokens = 200" "$HAIKU_OUTPUT" "200"
check "haiku cache_read = 10000" "$HAIKU_CACHE_READ" "10000"
check "haiku cache_write = 1000" "$HAIKU_CACHE_WRITE" "1000"

# Check cost calculations
OPUS_COST=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-opus")) | .cost_usd] | add')
HAIKU_COST=$(echo "$RECORD" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .cost_usd] | add')
TOTAL_COST=$(echo "$RECORD" | jq '.total_cost_usd')
check "opus cost = 0.155" "$OPUS_COST" "0.155"
check "haiku cost = 0.0041" "$HAIKU_COST" "0.0041"
check "total cost = 0.1591" "$TOTAL_COST" "0.1591"

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

# --- Test 5: empty transcript file ---
echo
echo "Test 5: empty transcript file produces zero-cost record"
EMPTY_FIXTURE=$(mktemp)
: > "$EMPTY_FIXTURE"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000003\",\"transcript_path\":\"$EMPTY_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "sessions file created with empty transcript" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "exists"
EMPTY_RECORD=$(cat "$SESSIONS_FILE")
check "total_cost is 0 for empty transcript" "$(echo "$EMPTY_RECORD" | jq '.total_cost_usd')" "0"
check "models array is empty for empty transcript" "$(echo "$EMPTY_RECORD" | jq '.models | length')" "0"
rm -f "$EMPTY_FIXTURE" "$SESSIONS_FILE"

# --- Test 6: transcript with malformed lines ---
echo
echo "Test 6: malformed JSON lines are skipped gracefully"
MALFORMED_FIXTURE=$(mktemp)
cat > "$MALFORMED_FIXTURE" << 'FIXTURE_EOF'
not valid json at all
{"parentUuid":null,"type":"user","message":{"role":"user","content":"test"},"uuid":"msg-001","sessionId":"test","timestamp":"2026-03-05T09:00:00.000Z"}
{broken json
{"parentUuid":"msg-001","type":"assistant","message":{"model":"claude-opus-4-6-20260301","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"uuid":"msg-002","sessionId":"test","timestamp":"2026-03-05T09:00:10.000Z"}
FIXTURE_EOF
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000004\",\"transcript_path\":\"$MALFORMED_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "sessions file created with malformed lines" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "exists"
MALFORMED_RECORD=$(cat "$SESSIONS_FILE")
check "valid JSON despite malformed input" "$(echo "$MALFORMED_RECORD" | jq -e . >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid"
check "parsed valid lines only (input_tokens=100)" "$(echo "$MALFORMED_RECORD" | jq '[.models[].input_tokens] | add')" "100"
rm -f "$MALFORMED_FIXTURE" "$SESSIONS_FILE"

# --- Test 7: non-existent transcript file ---
echo
echo "Test 7: non-existent transcript file returns error"
rm -f "$SESSIONS_FILE"
OUTPUT=$(echo '{"session_id":"00000000-0000-0000-0000-000000000005","transcript_path":"/nonexistent/file.jsonl","stop_hook_active":false}' | bash "$HOOK" 2>&1) || true
check "error mentions not found" "$(echo "$OUTPUT" | grep -c 'not found')" "1"
check "no sessions file for missing transcript" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "missing"

# --- Test 8: upsert behavior (same session_id replaces previous record) ---
echo
echo "Test 8: same session_id replaces previous record (upsert)"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000006\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "first write creates file" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "exists"
check "one record after first write" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "1"
# Run again with same session_id — should replace, not append
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000006\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "still one record after upsert" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "1"
# Add a different session, then upsert the first again
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000007\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "two records with different IDs" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "2"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000006\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
check "still two records after upsert of first" "$(wc -l < "$SESSIONS_FILE" | tr -d ' ')" "2"
rm -f "$SESSIONS_FILE"

# --- Test 9: consecutive assistant deduplication ---
echo
echo "Test 9: consecutive assistant messages are deduplicated"
DEDUP_FIXTURE="$PROJECT_DIR/tests/fixtures/duplicate-assistant.jsonl"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000008\",\"transcript_path\":\"$DEDUP_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
DEDUP_RECORD=$(cat "$SESSIONS_FILE")
# Should only count the LAST assistant in the consecutive chain (not both)
check "dedup: input_tokens = 1000 (not 2000)" "$(echo "$DEDUP_RECORD" | jq '[.models[].input_tokens] | add')" "1000"
check "dedup: output_tokens = 200 (not 400)" "$(echo "$DEDUP_RECORD" | jq '[.models[].output_tokens] | add')" "200"
check "dedup: cache_read = 5000 (not 10000)" "$(echo "$DEDUP_RECORD" | jq '[.models[].cache_read_tokens] | add')" "5000"
check "dedup: cache_write = 500 (not 1000)" "$(echo "$DEDUP_RECORD" | jq '[.models[].cache_write_tokens] | add')" "500"
rm -f "$SESSIONS_FILE"

# --- Test 10: missing pricing file uses fallback (sonnet-tier) pricing ---
echo
echo "Test 10: missing pricing file uses fallback pricing"
rm -f "$SESSIONS_FILE"
PRICING_FILE="$PROJECT_DIR/.claude/cost-data/pricing.json"
PRICING_BACKUP="$PRICING_FILE.test-bak"
mv "$PRICING_FILE" "$PRICING_BACKUP"
OUTPUT=$(echo "{\"session_id\":\"00000000-0000-0000-0000-000000000009\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>&1)
check "warns about missing pricing" "$(echo "$OUTPUT" | grep -q 'pricing' && echo "yes" || echo "no")" "yes"
check "sessions file created without pricing" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "exists"
NO_PRICE_RECORD=$(cat "$SESSIONS_FILE")
check "total_cost > 0 with fallback pricing" "$(echo "$NO_PRICE_RECORD" | jq '.total_cost_usd > 0')" "true"
check "pricing_estimated is true without pricing file" "$(echo "$NO_PRICE_RECORD" | jq '.pricing_estimated')" "true"
check "all models pricing_estimated" "$(echo "$NO_PRICE_RECORD" | jq '[.models[].pricing_estimated] | all')" "true"
check "tokens still tracked without pricing" "$(echo "$NO_PRICE_RECORD" | jq '[.models[].input_tokens] | add')" "4300"
mv "$PRICING_BACKUP" "$PRICING_FILE"
rm -f "$SESSIONS_FILE"

# --- Test 11: invalid session_id format ---
echo
echo "Test 11: invalid session_id format exits silently"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"not-a-uuid\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
EXIT_CODE=$?
check "exit code is 0 for invalid UUID" "$EXIT_CODE" "0"
check "no sessions file for invalid UUID" "$(test -f "$SESSIONS_FILE" && echo "exists" || echo "missing")" "missing"

# --- Test 12: known-model pricing accuracy (T008) ---
echo
echo "Test 12: opus pricing accuracy at \$5/\$25 rates"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000010\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD12=$(cat "$SESSIONS_FILE")
OPUS_COST12=$(echo "$RECORD12" | jq '[.models[] | select(.model | startswith("claude-opus")) | .cost_usd] | add')
# Opus: (3500*5 + 1300*25 + 110000*0.50 + 8000*6.25) / 1000000 = 0.155
check "opus cost at \$5/\$25 = 0.155" "$OPUS_COST12" "0.155"
check "opus pricing_estimated = false" "$(echo "$RECORD12" | jq '[.models[] | select(.model | startswith("claude-opus")) | .pricing_estimated] | all(. == false)')" "true"
rm -f "$SESSIONS_FILE"

# --- Test 13: fallback pricing for unknown model (T013) ---
echo
echo "Test 13: unknown model gets fallback pricing"
UNKNOWN_FIXTURE="$PROJECT_DIR/tests/fixtures/unknown-model-transcript.jsonl"
rm -f "$SESSIONS_FILE"
OUTPUT13=$(echo "{\"session_id\":\"00000000-0000-0000-0000-000000000011\",\"transcript_path\":\"$UNKNOWN_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>&1)
RECORD13=$(cat "$SESSIONS_FILE")
check "unknown model cost > 0" "$(echo "$RECORD13" | jq '.total_cost_usd > 0')" "true"
check "model pricing_estimated = true" "$(echo "$RECORD13" | jq '.models[0].pricing_estimated')" "true"
check "session pricing_estimated = true" "$(echo "$RECORD13" | jq '.pricing_estimated')" "true"
check "stderr mentions fallback" "$(echo "$OUTPUT13" | grep -c 'using fallback')" "1"
rm -f "$SESSIONS_FILE"

# --- Test 14: mixed known/unknown models (T014) ---
echo
echo "Test 14: mixed known/unknown models in one session"
MIXED_FIXTURE="$PROJECT_DIR/tests/fixtures/mixed-model-transcript.jsonl"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000012\",\"transcript_path\":\"$MIXED_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD14=$(cat "$SESSIONS_FILE")
check "known model pricing_estimated = false" "$(echo "$RECORD14" | jq '[.models[] | select(.model | startswith("claude-opus")) | .pricing_estimated] | .[0]')" "false"
check "unknown model pricing_estimated = true" "$(echo "$RECORD14" | jq '[.models[] | select(.model == "claude-unknown-5") | .pricing_estimated] | .[0]')" "true"
check "session pricing_estimated = true (any estimated)" "$(echo "$RECORD14" | jq '.pricing_estimated')" "true"
rm -f "$SESSIONS_FILE"

# --- Test 15: missing pricing file produces fallback costs (T015) ---
echo
echo "Test 15: missing pricing file — all models get fallback"
rm -f "$SESSIONS_FILE"
mv "$PRICING_FILE" "$PRICING_BACKUP"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000013\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD15=$(cat "$SESSIONS_FILE")
check "all models estimated when no pricing file" "$(echo "$RECORD15" | jq '[.models[].pricing_estimated] | all')" "true"
check "total cost > 0 with fallback" "$(echo "$RECORD15" | jq '.total_cost_usd > 0')" "true"
mv "$PRICING_BACKUP" "$PRICING_FILE"
rm -f "$SESSIONS_FILE"

# --- Test 16: turn count (T020) ---
echo
echo "Test 16: turn count matches deduplicated assistant messages"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000014\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD16=$(cat "$SESSIONS_FILE")
# sample-transcript.jsonl has 3 assistant messages (msg-002, msg-004, msg-006), none consecutive
check "turns = 3" "$(echo "$RECORD16" | jq '.turns')" "3"
rm -f "$SESSIONS_FILE"

# --- Test 17: per-model total_tokens (T021) ---
echo
echo "Test 17: per-model total_tokens = sum of all 4 token types"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000015\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD17=$(cat "$SESSIONS_FILE")
# Opus: 3500 + 1300 + 110000 + 8000 = 122800
OPUS_TOTAL=$(echo "$RECORD17" | jq '[.models[] | select(.model | startswith("claude-opus")) | .total_tokens] | add')
check "opus total_tokens = 122800" "$OPUS_TOTAL" "122800"
# Haiku: 800 + 200 + 10000 + 1000 = 12000
HAIKU_TOTAL=$(echo "$RECORD17" | jq '[.models[] | select(.model | startswith("claude-haiku")) | .total_tokens] | add')
check "haiku total_tokens = 12000" "$HAIKU_TOTAL" "12000"
rm -f "$SESSIONS_FILE"

# --- Test 18: session-level total_tokens (T022) ---
echo
echo "Test 18: session total_tokens = sum of all model total_tokens"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000016\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD18=$(cat "$SESSIONS_FILE")
# 122800 + 12000 = 134800
check "session total_tokens = 134800" "$(echo "$RECORD18" | jq '.total_tokens')" "134800"
rm -f "$SESSIONS_FILE"

# --- Test 19: pricing_version (T025) ---
echo
echo "Test 19: pricing_version matches pricing.json version"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000017\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD19=$(cat "$SESSIONS_FILE")
EXPECTED_VERSION=$(jq '.version' "$PRICING_FILE")
check "pricing_version = $EXPECTED_VERSION" "$(echo "$RECORD19" | jq '.pricing_version')" "$EXPECTED_VERSION"
rm -f "$SESSIONS_FILE"

# --- Test 20: pricing_version defaults to 0 when missing (T026) ---
echo
echo "Test 20: pricing_version defaults to 0 when version field missing"
rm -f "$SESSIONS_FILE"
# Create a minimal pricing.json without version field
PRICING_NO_VER=$(mktemp)
echo '{"models":[],"fallback":{"tier":"sonnet","input_per_mtok":3,"output_per_mtok":15,"cache_read_per_mtok":0.30,"cache_write_per_mtok":3.75}}' > "$PRICING_NO_VER"
mv "$PRICING_FILE" "$PRICING_BACKUP"
mv "$PRICING_NO_VER" "$PRICING_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000018\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD20=$(cat "$SESSIONS_FILE")
check "pricing_version defaults to 0" "$(echo "$RECORD20" | jq '.pricing_version')" "0"
mv "$PRICING_BACKUP" "$PRICING_FILE"
rm -f "$SESSIONS_FILE"

# --- Test 21: 4-decimal cost precision (T031) ---
echo
echo "Test 21: cost values have 4-decimal precision"
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000019\",\"transcript_path\":\"$FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD21=$(cat "$SESSIONS_FILE")
# Haiku cost 0.00405 rounds to 0.0041 (not 0.004050 or 0.00405)
HAIKU_COST21=$(echo "$RECORD21" | jq -r '[.models[] | select(.model | startswith("claude-haiku")) | .cost_usd] | .[0] | tostring')
check "haiku cost rounded to 4 decimals = 0.0041" "$HAIKU_COST21" "0.0041"
rm -f "$SESSIONS_FILE"

# --- Test 22: zero-token model appears in output (T039) ---
echo
echo "Test 22: model with zero tokens still appears in output"
ZERO_FIXTURE=$(mktemp)
cat > "$ZERO_FIXTURE" << 'FIXTURE_EOF'
{"parentUuid":null,"type":"user","message":{"role":"user","content":"test"},"uuid":"msg-001","sessionId":"test","timestamp":"2026-04-01T10:00:00.000Z"}
{"parentUuid":"msg-001","type":"assistant","message":{"model":"claude-opus-4-6-20260301","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"uuid":"msg-002","sessionId":"test","timestamp":"2026-04-01T10:00:05.000Z"}
FIXTURE_EOF
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000020\",\"transcript_path\":\"$ZERO_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD22=$(cat "$SESSIONS_FILE")
check "zero-token model present" "$(echo "$RECORD22" | jq '.models | length')" "1"
check "zero-token model cost = 0" "$(echo "$RECORD22" | jq '.models[0].cost_usd')" "0"
check "zero-token model total_tokens = 0" "$(echo "$RECORD22" | jq '.models[0].total_tokens')" "0"
rm -f "$ZERO_FIXTURE" "$SESSIONS_FILE"

# --- Test 23: empty session (no assistant messages) (T040) ---
echo
echo "Test 23: session with no assistant messages"
USER_ONLY_FIXTURE=$(mktemp)
cat > "$USER_ONLY_FIXTURE" << 'FIXTURE_EOF'
{"parentUuid":null,"type":"user","message":{"role":"user","content":"hello"},"uuid":"msg-001","sessionId":"test","timestamp":"2026-04-01T10:00:00.000Z"}
FIXTURE_EOF
rm -f "$SESSIONS_FILE"
echo "{\"session_id\":\"00000000-0000-0000-0000-000000000021\",\"transcript_path\":\"$USER_ONLY_FIXTURE\",\"stop_hook_active\":false}" | bash "$HOOK" 2>/dev/null
RECORD23=$(cat "$SESSIONS_FILE")
check "turns = 0 for no assistants" "$(echo "$RECORD23" | jq '.turns')" "0"
check "total_tokens = 0 for no assistants" "$(echo "$RECORD23" | jq '.total_tokens')" "0"
check "total_cost = 0 for no assistants" "$(echo "$RECORD23" | jq '.total_cost_usd')" "0"
check "models empty for no assistants" "$(echo "$RECORD23" | jq '.models | length')" "0"
rm -f "$USER_ONLY_FIXTURE" "$SESSIONS_FILE"

# --- Summary ---
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
