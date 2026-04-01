# Data Model: Refine Cost Tracking Precision

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01

This document describes **changes** to the existing data model from feature 001. Only new or modified fields are detailed. Unchanged fields retain their original definitions from `specs/001-cost-tracker/data-model.md`.

## Entity Changes

### Cost Record (updated)

New fields added to the session-level cost record in `.claude/cost-data/sessions.jsonl`:

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `turns` | integer | Number of API turns (deduplicated assistant messages) | Count of usage entries after dedup |
| `total_tokens` | integer | Sum of all token types across all models | Sum of per-model `total_tokens` |
| `pricing_version` | integer | Version of pricing.json used for calculation | `pricing.json` → `version` field |
| `pricing_estimated` | boolean | True if any model used fallback pricing | Set when any model lacks a prefix match |

**Modified fields**:

| Field | Change | Before | After |
|-------|--------|--------|-------|
| `total_cost_usd` | Precision | 6 decimal places | 4 decimal places |

### ModelUsage (updated)

New fields added to per-model entries within the `models` array:

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `total_tokens` | integer | Sum of input + output + cache_read + cache_write | Calculated per model |
| `pricing_estimated` | boolean | True if this specific model used fallback pricing | Set when model lacks a prefix match |

**Modified fields**:

| Field | Change | Before | After |
|-------|--------|--------|-------|
| `cost_usd` | Precision | 6 decimal places | 4 decimal places |

### Pricing Table (updated)

Changes to `.claude/cost-data/pricing.json`:

| Field | Type | Description | Change |
|-------|------|-------------|--------|
| `version` | integer | Pricing version number | Bumped from 1 to 2 |
| `updated` | string | Last update date | Updated to current date |
| `fallback` | object | Complete default rates for unknown models | **NEW**: Replaces `fallback_formula` |

**New `fallback` structure** (replaces `fallback_formula`):

| Field | Type | Description |
|-------|------|-------------|
| `fallback.tier` | string | Name of the fallback tier (e.g., "sonnet") |
| `fallback.input_per_mtok` | float | Default input rate per million tokens |
| `fallback.output_per_mtok` | float | Default output rate per million tokens |
| `fallback.cache_read_per_mtok` | float | Default cache read rate per million tokens |
| `fallback.cache_write_per_mtok` | float | Default cache write rate per million tokens |

**New model entries added**:

| model_pattern | input_per_mtok | output_per_mtok | cache_read_per_mtok | cache_write_per_mtok | Notes |
|---------------|---------------|-----------------|--------------------|--------------------|-------|
| `claude-opus-4-1` | 15.00 | 75.00 | 1.50 | 18.75 | Older generation |
| `claude-opus-4-` | 15.00 | 75.00 | 1.50 | 18.75 | Catch-all for Opus 4.0 variants |

## Relationships

```
Cost Record 1──* ModelUsage
    │                │
    │                └── pricing_estimated: per-model flag
    │
    ├── pricing_version ──> Pricing Table.version
    ├── pricing_estimated ──> OR of all ModelUsage.pricing_estimated
    ├── turns ──> count of deduplicated assistant messages
    ├── total_tokens ──> sum of all ModelUsage.total_tokens
    │
    └── cost calculated using ──> Pricing Entry (matched by model_pattern)
                                  OR Pricing Table.fallback (when no match)
```

## Validation Rules (additions)

- `turns` must be >= 0.
- `total_tokens` must be >= 0 and must equal the sum of `input_tokens + output_tokens + cache_read_tokens + cache_write_tokens` for each model (and the grand sum at session level).
- `pricing_version` must be >= 0.
- `pricing_estimated` must be boolean.
- `total_cost_usd` and `cost_usd` values must have at most 4 decimal places.

## File Format Changes

### sessions.jsonl (updated record example)

```jsonl
{"session_id":"6f79372b-73a0-4576-a002-5153ae8d8011","timestamp":"2026-04-01T10:05:00Z","session_start":"2026-04-01T09:30:00Z","session_end":"2026-04-01T10:05:00Z","api_duration_ms":354000,"wall_duration_ms":2100000,"lines_added":149,"lines_removed":83,"total_cost_usd":1.5100,"turns":12,"total_tokens":1300000,"pricing_version":2,"pricing_estimated":false,"models":[{"model":"claude-opus-4-6-20260301","input_tokens":3200,"output_tokens":14800,"cache_read_tokens":1200000,"cache_write_tokens":82000,"total_tokens":1300000,"cost_usd":1.5100,"pricing_estimated":false}]}
```

### pricing.json (v2)

```json
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
```

### Backwards Compatibility

Old records (without new fields) are handled by consumers using defaults:
- Missing `turns`: Display as "—" or omit from output
- Missing `total_tokens`: Display as "—" or omit from output
- Missing `pricing_version`: Treat as version 0 (pre-audit-trail era)
- Missing `pricing_estimated`: Treat as `false` (assume exact pricing)
- Old 6-decimal `cost_usd` values remain valid — no rewriting needed
