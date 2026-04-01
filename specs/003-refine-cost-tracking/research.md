# Research: Refine Cost Tracking Precision

**Branch**: `003-refine-cost-tracking` | **Date**: 2026-04-01

## R1: Pricing Table Accuracy

**Decision**: Keep the current `pricing.json` rates as-is — they already match official Anthropic API pricing. Add missing model entries (Opus 4, Opus 4.1) at their correct older-generation rates.

**Rationale**: Verification against the official Anthropic pricing page (platform.claude.com/docs) confirmed:

| Model | Input/MTok | Output/MTok | Cache Write/MTok | Cache Read/MTok |
|-------|-----------|-------------|-----------------|-----------------|
| Opus 4.6 / 4.5 | $5.00 | $25.00 | $6.25 | $0.50 |
| Opus 4.1 / 4.0 | $15.00 | $75.00 | $18.75 | $1.50 |
| Sonnet 4.6 / 4.5 / 4 | $3.00 | $15.00 | $3.75 | $0.30 |
| Haiku 4.5 | $1.00 | $5.00 | $1.25 | $0.10 |

The skill's current `pricing.json` has correct rates for Opus 4.6/4.5 ($5/$25), all Sonnet variants ($3/$15), and Haiku 4.5 ($1/$5). Cache rates also match the official formula: write = 1.25x input, read = 0.1x input.

The **Rust source code** (`usage.rs`) uses stale Opus 4.0/4.1 pricing ($15/$75) for ALL Opus and Sonnet models. It also incorrectly applies $15/$75 to Sonnet. The COST-TRACKING.md correctly identified this as a limitation ("Sonnet and Opus share the same pricing constants").

**Alternatives considered**:
- Adopt Rust source pricing: Rejected — it's demonstrably stale and incorrect for current models.
- Fetch pricing from API at runtime: Rejected — violates zero-cost constraint.

**Action**: No pricing rate changes needed. Add entries for `claude-opus-4-1` and `claude-opus-4` at $15/$75 for completeness. Bump version to 2.

## R2: Fallback Pricing Strategy for Unknown Models

**Decision**: Implement full Sonnet-tier fallback with `pricing_estimated` tagging, matching the Rust source's behavioral pattern.

**Rationale**: The Rust source falls back to Sonnet-tier pricing for unknown models and tags output with `pricing=estimated-default`. The skill currently has a `fallback_formula` with cache ratios but no base input/output rates for unknown models, resulting in $0.00 cost — a worse outcome than an estimate.

The fallback should provide complete Sonnet-tier rates (input=$3/M, output=$15/M, cache_read=$0.30/M, cache_write=$3.75/M) since:
1. Sonnet is the most commonly used model tier
2. It provides a reasonable middle-ground estimate
3. The `pricing_estimated` flag makes it clear the cost is approximate

**Implementation approach**:
- Replace `fallback_formula` in `pricing.json` with a `fallback` object containing complete rates
- In the hook jq pipeline: when no prefix match is found, use the fallback rates and set `pricing_estimated: true` on the model entry
- At the session level, set `pricing_estimated: true` if ANY model used fallback pricing
- Continue emitting stderr warning for unmatched models (already partially implemented)

**Alternatives considered**:
- Use Opus-tier fallback: Rejected — would overestimate for most models. Better to underestimate slightly.
- No fallback (keep $0.00): Rejected — silent undercounting is worse than a flagged estimate.

## R3: Turn Count Tracking

**Decision**: Count deduplicated assistant messages as turns, matching the Rust source's `UsageTracker.turns` counter.

**Rationale**: The Rust source increments `turns` each time `usage_tracker.record(usage)` is called — once per API response. The hook's deduplication logic (keeping only the last assistant message in consecutive chains) already produces exactly this count. The turn count is simply the length of the deduplicated usage array.

**Implementation approach**:
- After deduplication, count the number of usage entries: `[.usage | length]`
- Store as `turns` at the session level in the cost record
- For multi-model sessions, `turns` is the total across all models (not per-model)

**Alternatives considered**:
- Count per-model turns: Possible but adds complexity with limited value. Session-level turns is sufficient.
- Count all assistant messages (before dedup): Would overcount — multiple content blocks from one API call appear as consecutive assistant messages.

## R4: Total Tokens Computation

**Decision**: Compute `total_tokens` as the sum of all four token types (input + output + cache_read + cache_write), matching the Rust runtime's `TokenUsage::total_tokens()`.

**Rationale**: The Rust runtime includes all four token types in `total_tokens()`:
```rust
pub fn total_tokens(&self) -> u32 {
    self.input_tokens + self.output_tokens +
    self.cache_creation_input_tokens + self.cache_read_input_tokens
}
```

Note: The Rust API-level `Usage::total_tokens()` only sums input + output (excluding cache). We follow the runtime behavior since it gives a more complete picture of total token volume.

**Implementation approach**:
- Per-model: `total_tokens = input_tokens + output_tokens + cache_read_tokens + cache_write_tokens`
- Session-level: sum of all per-model `total_tokens`
- Added in the jq aggregation pipeline alongside existing fields

## R5: Cost Precision (4 Decimal Places)

**Decision**: Round all USD cost values to 4 decimal places, matching the Rust source's `format_usd()`.

**Rationale**: The Rust source uses `format!("${amount:.4}")` which gives exactly 4 decimal places. The skill currently rounds to 6 decimal places via `* 1000000 | round | . / 1000000`. Changing to 4 decimal places (`* 10000 | round | . / 10000`) aligns output with the Rust source and is more readable.

**Impact on existing tests**: Test expected values will need updating to 4 decimal places. This is a minor test fixture change, not a behavioral breaking change — the records still contain valid USD amounts.

**Implementation approach**:
- Change jq rounding from `* 1000000 | round | . / 1000000` to `* 10000 | round | . / 10000`
- Apply consistently to both per-model `cost_usd` and session `total_cost_usd`

## R6: Pricing Version Audit Trail

**Decision**: Read the `version` field from `pricing.json` and include it as `pricing_version` in each cost record.

**Rationale**: When pricing rates change, historical records become ambiguous — was a cost calculated with old or new rates? Including the pricing version number enables:
1. Distinguishing records calculated with different pricing eras
2. Potential future recalculation of historical records with updated pricing
3. Debugging pricing discrepancies

**Implementation approach**:
- Extract `$pricing.version // 0` from the pricing JSON (default to 0 if missing)
- Include as `pricing_version` in the assembled cost record JSON
- Bump the pricing.json version when rates are added/changed

**Alternatives considered**:
- Store full pricing snapshot per record: Excessive storage overhead.
- Store pricing hash: More complex, less human-readable than a simple version integer.

## R7: Backwards Compatibility

**Decision**: All new fields are strictly additive. No existing fields are removed, renamed, or have their semantics changed.

**Rationale**: Existing cost records in `sessions.jsonl` will not have the new fields (`turns`, `total_tokens`, `pricing_version`, `pricing_estimated`). Report and session commands must handle records both with and without these fields.

**Implementation approach**:
- Slash commands: Use jq's `// null` or `// "N/A"` for missing fields when formatting output
- Reports: Show new fields when available, omit or show "—" when not present
- No migration of historical records — they remain as-is
