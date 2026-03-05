# Data Model: Claude Code Cost Tracker

**Branch**: `001-cost-tracker` | **Date**: 2026-03-05

## Entities

### Cost Record

A single session's cost data, written to `.claude/cost-data/sessions.jsonl`.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `session_id` | string (UUID) | Unique session identifier | Hook stdin `session_id` |
| `timestamp` | string (ISO 8601) | When this record was written | Generated at write time |
| `session_start` | string (ISO 8601) | First message timestamp in session | Parsed from transcript |
| `session_end` | string (ISO 8601) | Last message timestamp in session | Parsed from transcript |
| `api_duration_ms` | integer | Total API processing time in milliseconds | Calculated from message pairs |
| `wall_duration_ms` | integer | Wall clock time from first to last message | `session_end - session_start` |
| `lines_added` | integer | Total lines of code added | Parsed from tool use results |
| `lines_removed` | integer | Total lines of code removed | Parsed from tool use results |
| `total_cost_usd` | float | Total session cost in USD | Sum of all model costs |
| `models` | array[ModelUsage] | Per-model token breakdown | Aggregated from transcript |

### ModelUsage

Per-model token usage within a session. Nested inside Cost Record's `models` array.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `model` | string | Model identifier (e.g., `claude-opus-4-6-20260301`) | `message.model` from transcript |
| `input_tokens` | integer | Regular input tokens consumed | `usage.input_tokens` |
| `output_tokens` | integer | Output tokens generated | `usage.output_tokens` |
| `cache_read_tokens` | integer | Tokens served from prompt cache | `usage.cache_read_input_tokens` |
| `cache_write_tokens` | integer | Tokens written to prompt cache | `usage.cache_creation_input_tokens` |
| `cost_usd` | float | Cost for this model's usage | Calculated from pricing table |

### Pricing Entry

Per-model pricing data, stored in `.claude/cost-data/pricing.json`.

| Field | Type | Description |
|-------|------|-------------|
| `model_pattern` | string | Model name prefix for matching (e.g., `claude-opus-4-6`) |
| `input_per_mtok` | float | USD per million input tokens |
| `output_per_mtok` | float | USD per million output tokens |
| `cache_read_per_mtok` | float | USD per million cache read tokens |
| `cache_write_per_mtok` | float | USD per million cache write tokens |

## Relationships

```
Cost Record 1──* ModelUsage
    │
    └── cost calculated using ──> Pricing Entry (matched by model_pattern)
```

- Each Cost Record contains one or more ModelUsage entries (one per distinct model used in the session).
- ModelUsage cost is calculated by matching the `model` field against Pricing Entry `model_pattern` prefixes.
- If no pricing match is found, a fallback formula is applied (cache_read = 10% of input, cache_write = 25% of input) using a default input/output price, and a warning is logged.

## Validation Rules

- `session_id` must be non-empty and a valid UUID format.
- `total_cost_usd` must equal the sum of all `models[].cost_usd` values (within floating point tolerance).
- `lines_added` and `lines_removed` must be >= 0.
- `api_duration_ms` and `wall_duration_ms` must be >= 0.
- `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens` must all be >= 0.
- `timestamp` must be valid ISO 8601.
- `session_start` must be <= `session_end`.

## State Transitions

Cost Records have a simple lifecycle:

1. **Created**: Written on first `Stop` hook firing for a session.
2. **Updated**: Overwritten (new JSONL line appended) on subsequent `Stop` hook firings for the same session. The latest line per `session_id` is the authoritative record.
3. **Deleted**: All records removed when user runs `/cost-reset` command.

No intermediate states. Records are immutable once written (append-only file); "updates" are achieved by appending a newer record with the same `session_id`.

## File Formats

### sessions.jsonl

```jsonl
{"session_id":"6f79372b-73a0-4576-a002-5153ae8d8011","timestamp":"2026-03-05T10:05:00Z","session_start":"2026-03-05T09:30:00Z","session_end":"2026-03-05T10:05:00Z","api_duration_ms":354000,"wall_duration_ms":2100000,"lines_added":149,"lines_removed":83,"total_cost_usd":1.51,"models":[{"model":"claude-opus-4-6-20260301","input_tokens":3200,"output_tokens":14800,"cache_read_tokens":1200000,"cache_write_tokens":82000,"cost_usd":1.51}]}
```

### pricing.json

```json
{
  "version": 1,
  "updated": "2026-03-05",
  "models": [
    {
      "model_pattern": "claude-opus-4-6",
      "input_per_mtok": 15.00,
      "output_per_mtok": 75.00,
      "cache_read_per_mtok": 1.50,
      "cache_write_per_mtok": 3.75
    },
    {
      "model_pattern": "claude-sonnet-4-6",
      "input_per_mtok": 3.00,
      "output_per_mtok": 15.00,
      "cache_read_per_mtok": 0.30,
      "cache_write_per_mtok": 0.75
    },
    {
      "model_pattern": "claude-haiku-4-5",
      "input_per_mtok": 0.80,
      "output_per_mtok": 4.00,
      "cache_read_per_mtok": 0.08,
      "cache_write_per_mtok": 0.20
    }
  ],
  "fallback_formula": {
    "cache_read_ratio": 0.10,
    "cache_write_ratio": 0.25,
    "note": "For unknown models: cache_read = input_price * 0.10, cache_write = input_price * 0.25"
  }
}
```
