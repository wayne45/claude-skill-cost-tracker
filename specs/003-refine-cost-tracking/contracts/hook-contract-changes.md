# Hook Contract Changes: Cost Tracker Stop Hook

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01

This documents **changes** to the hook contract from feature 001 (`specs/001-cost-tracker/contracts/hook-contract.md`). The base contract (event type, settings schema, input contract, error handling) remains unchanged.

## Output Contract Changes

### Cost Record (new fields)

The cost record written to `.claude/cost-data/sessions.jsonl` gains the following fields:

| Field | Type | Position | Description |
|-------|------|----------|-------------|
| `turns` | integer | After `lines_removed` | Count of deduplicated assistant messages (API calls) |
| `total_tokens` | integer | After `turns` | Sum of all token types across all models |
| `pricing_version` | integer | After `total_tokens` | Version number from `pricing.json` |
| `pricing_estimated` | boolean | After `pricing_version` | True if any model used fallback pricing |

### Per-Model Entry (new fields)

Each object in the `models` array gains:

| Field | Type | Description |
|-------|------|-------------|
| `total_tokens` | integer | `input_tokens + output_tokens + cache_read_tokens + cache_write_tokens` |
| `pricing_estimated` | boolean | True if this model used fallback pricing |

### Cost Precision Change

All `cost_usd` and `total_cost_usd` values change from 6 to 4 decimal places.

## Behavior Changes

### Step 5 (updated): Look up pricing

**Before**: If no prefix match found, set `cost_usd: 0`.

**After**: If no prefix match found:
1. Use the `fallback` rates from `pricing.json` (Sonnet-tier defaults)
2. Set `pricing_estimated: true` on the model entry
3. Emit warning to stderr: `cost-tracker: no pricing match for model '<model_name>', using fallback (sonnet-tier) — add to pricing.json`

### Step 6 (updated): Calculate costs

**Before**: Round to 6 decimal places.

**After**: Round to 4 decimal places. Formula unchanged: `tokens / 1,000,000 * rate_per_mtok`.

### New Step 5.5: Read pricing version

Extract `version` field from `pricing.json` (default: 0 if missing).

### New Step 6.5: Compute turns and total_tokens

- `turns` = count of entries in deduplicated usage array
- Per-model `total_tokens` = `input_tokens + output_tokens + cache_read_tokens + cache_write_tokens`
- Session `total_tokens` = sum of all per-model `total_tokens`

### New Step 6.6: Determine pricing_estimated flag

- Session-level `pricing_estimated` = `true` if any model entry has `pricing_estimated: true`

## Error Handling Changes

| Condition | Behavior (before) | Behavior (after) |
|-----------|-------------------|------------------|
| Model not in pricing table | Set `cost_usd: 0`, warn to stderr | Use fallback rates, set `pricing_estimated: true`, warn to stderr |
| Pricing file missing | Use zero costs | Use built-in Sonnet-tier defaults, set all `pricing_estimated: true` |
| Pricing file has no `version` | N/A | Default to `pricing_version: 0` |

## Example Output

```json
{
  "session_id": "6f79372b-73a0-4576-a002-5153ae8d8011",
  "timestamp": "2026-04-01T10:05:00Z",
  "session_start": "2026-04-01T09:30:00Z",
  "session_end": "2026-04-01T10:05:00Z",
  "api_duration_ms": 354000,
  "wall_duration_ms": 2100000,
  "lines_added": 149,
  "lines_removed": 83,
  "total_cost_usd": 1.5100,
  "turns": 12,
  "total_tokens": 1300000,
  "pricing_version": 2,
  "pricing_estimated": false,
  "models": [
    {
      "model": "claude-opus-4-6-20260301",
      "input_tokens": 3200,
      "output_tokens": 14800,
      "cache_read_tokens": 1200000,
      "cache_write_tokens": 82000,
      "total_tokens": 1300000,
      "cost_usd": 1.5100,
      "pricing_estimated": false
    }
  ]
}
```
