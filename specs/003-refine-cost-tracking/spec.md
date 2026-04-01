# Feature Specification: Refine Cost Tracking Precision

**Feature Branch**: `003-refine-cost-tracking`  
**Created**: 2026-04-01  
**Status**: Planned  
**Input**: User description: "Read the Claude source code (Rust) and COST-TRACKING.md to make the cost tracker skill more precise. Do not commit any files in rust folder."

## Background

The Claude Code cost tracker skill (feature 001) was built based on observed behavior and documented API patterns. The Rust source code of Claude Code's internal cost tracking system (`rust/crates/runtime/src/usage.rs`, `rust/crates/api/src/types.rs`, etc.) has now been analyzed, revealing several precision gaps between the skill's implementation and how Claude Code actually tracks costs internally. This feature refines the skill to align with the reference implementation.

### Key Gaps Identified

1. **Pricing table verification**: The skill's `pricing.json` uses rates ($5/$25 Opus, $3/$15 Sonnet) that differ from the Rust source's hardcoded rates ($15/$75 for both Opus and Sonnet, $1/$5 Haiku). Research confirmed the skill's rates are correct for current-generation models (Opus 4.5+, Sonnet 4+, Haiku 4.5); the Rust source uses stale Opus 4.0/4.1 pricing. The pricing table needs older model entries added but no rate corrections.
2. **No "estimated-default" tagging**: When the Rust source encounters an unknown model, it falls back to Sonnet-tier pricing AND tags the output with `pricing=estimated-default`. The skill silently returns zero cost for unpriced models — no fallback estimation, no user warning in cost records.
3. **Missing turn count tracking**: The Rust source tracks `turns` (number of API calls per session) via `UsageTracker`. The skill does not track turn count, losing useful granularity for understanding cost-per-turn.
4. **Cost precision inconsistency**: The Rust source formats costs to exactly 4 decimal places (`$X.XXXX`). The skill rounds to 6 decimal places. Inconsistent precision makes cross-referencing difficult.
5. **Total tokens calculation divergence**: The Rust runtime's `TokenUsage::total_tokens()` sums all four token types (input + output + cache_creation + cache_read). The skill does not compute or store a total_tokens field.
6. **No pricing source audit trail**: The skill stores costs but not which pricing version or source was used to calculate them. If pricing is updated, historical records cannot be distinguished from records calculated with newer rates.
7. **Fallback pricing for unknown models**: The Rust source falls back to Sonnet-tier pricing for unknown models. The skill's `fallback_formula` only computes cache rates as ratios of the input price but requires the input/output prices to exist — for a truly unknown model, it produces zero cost.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate Cost Estimation for Known Models (Priority: P1)

As a Claude Code user, I want the cost tracker to calculate costs using the correct, up-to-date per-model pricing rates so that my cost reports reflect what I actually pay.

**Why this priority**: If the pricing table is wrong, every cost number the skill produces is wrong. This is the most impactful single fix — it affects all users, all sessions, and all reports.

**Independent Test**: Can be fully tested by running the hook with a known transcript fixture and comparing the calculated cost against a hand-computed expected value using the official Anthropic API pricing rates.

**Acceptance Scenarios**:

1. **Given** a session using `claude-opus-4-6-20260301`, **When** the hook calculates cost, **Then** it uses the correct Opus-tier input, output, cache-read, and cache-write rates from the official Anthropic pricing.
2. **Given** a session using `claude-sonnet-4-6-20260301`, **When** the hook calculates cost, **Then** it uses the correct Sonnet-tier rates (which may differ from Opus-tier rates).
3. **Given** a session using `claude-haiku-4-5-20251001`, **When** the hook calculates cost, **Then** it uses the correct Haiku-tier rates.
4. **Given** a pricing.json that has been updated with new rates, **When** the hook runs on a new session, **Then** it uses the updated rates for new sessions while historical records retain their original calculated costs.

---

### User Story 2 - Fallback Pricing for Unknown Models (Priority: P2)

As a Claude Code user, I want unknown or newly released models to receive a reasonable estimated cost (rather than $0.00) so that my cost tracking does not silently undercount when Anthropic releases a new model variant.

**Why this priority**: New model variants appear regularly (e.g., snapshot dates, experimental models). Showing $0.00 for these models is worse than showing an estimate, because it creates a false sense of low spending.

**Independent Test**: Can be fully tested by providing a transcript with a model name not in `pricing.json` (e.g., `claude-future-model-5`) and verifying the cost is estimated using a default tier, with the cost record clearly tagged as estimated.

**Acceptance Scenarios**:

1. **Given** a session using a model not in the pricing table (e.g., `claude-unknown-5`), **When** the hook calculates cost, **Then** it uses a default pricing tier (Sonnet-tier) to estimate the cost.
2. **Given** an unknown model that triggers fallback pricing, **When** the cost record is written, **Then** the record includes a field or flag (e.g., `"pricing_estimated": true`) indicating the cost is an estimate.
3. **Given** a transcript with both known and unknown models (multi-model session), **When** the hook calculates cost, **Then** known models use exact pricing and unknown models use estimated pricing, and the record clearly distinguishes which is which.

---

### User Story 3 - Turn Count and Total Tokens Tracking (Priority: P3)

As a Claude Code user, I want each cost record to include the number of API turns and a total token count so that I can understand the density and efficiency of my sessions (tokens per turn, cost per turn).

**Why this priority**: Turn count and total tokens are low-cost additions that significantly improve the analytical value of cost data. They mirror what the Rust source already tracks internally.

**Independent Test**: Can be fully tested by running the hook on a transcript fixture with a known number of assistant messages (after deduplication) and verifying the cost record contains the correct turn count and total token sum.

**Acceptance Scenarios**:

1. **Given** a session transcript with 5 deduplicated assistant messages (API turns), **When** the hook processes it, **Then** the cost record includes `"turns": 5`.
2. **Given** a session with input_tokens=1000, output_tokens=500, cache_read_tokens=200, cache_write_tokens=100, **When** the hook writes the record, **Then** the record includes `"total_tokens": 1800` (sum of all four types, matching the Rust runtime's `total_tokens()` behavior).
3. **Given** a multi-model session, **When** the hook aggregates usage, **Then** the session-level turn count reflects the total across all models, and total_tokens reflects the grand total.

---

### User Story 4 - Pricing Audit Trail (Priority: P4)

As a Claude Code user, I want each cost record to reference the pricing version used to calculate it so that when pricing is updated, I can tell which records used old vs. new rates.

**Why this priority**: Without audit trails, updating pricing creates ambiguity — did a cost drop because the session was cheaper, or because pricing was updated? This is important for accurate cost analysis over time.

**Independent Test**: Can be fully tested by calculating costs with two different pricing.json versions and verifying the records contain different pricing version identifiers.

**Acceptance Scenarios**:

1. **Given** a pricing.json with `"version": 2`, **When** the hook calculates cost, **Then** the cost record includes `"pricing_version": 2`.
2. **Given** historical records with `"pricing_version": 1` and new records with `"pricing_version": 2`, **When** the user generates a cost report, **Then** the report can distinguish between the two pricing eras.

---

### User Story 5 - Standardized Cost Precision (Priority: P5)

As a Claude Code user, I want cost values formatted to a consistent number of decimal places so that values are easy to read and compare across sessions.

**Why this priority**: Cosmetic but affects readability and consistency. Aligning with a standard precision (4 decimal places, matching the Rust source's `format_usd()`) prevents confusion.

**Independent Test**: Can be fully tested by running the hook and inspecting cost values in the output to verify they use exactly 4 decimal places.

**Acceptance Scenarios**:

1. **Given** a session with a computed cost of $1.5, **When** the record is written, **Then** the cost appears as `1.5000` (4 decimal places).
2. **Given** a session with a computed cost of $0.123456789, **When** the record is written, **Then** the cost appears as `0.1235` (rounded to 4 decimal places).

---

### Edge Cases

- What happens when `pricing.json` is missing entirely? The system should use built-in default pricing (Sonnet-tier) for all models with all records tagged as estimated.
- What happens when a model appears in the transcript with zero tokens (e.g., failed API call)? The record should include the model with zero cost and zero turns, not omit it.
- What happens when pricing.json contains a model pattern that matches multiple entries (e.g., both `claude-sonnet-4` and `claude-sonnet-4-6` exist)? Longest-prefix-match should continue to be used, selecting the most specific pattern.
- What happens when the pricing.json `version` field is missing? Default to version 0 and tag records accordingly.
- What happens when a session has zero assistant messages (empty conversation)? Turn count should be 0, total tokens should be 0, total cost should be 0.0000.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST verify and maintain the pricing table to reflect current official Anthropic API pricing for all supported model families (Opus, Sonnet, Haiku) across all four token types (input, output, cache read, cache write). Research confirmed existing rates are correct; this requirement covers adding missing model entries and keeping rates current.
- **FR-002**: System MUST apply fallback pricing (default: Sonnet-tier rates) when a model in the transcript is not found in the pricing table, instead of producing zero cost.
- **FR-003**: System MUST tag cost records with a `pricing_estimated` flag (boolean) when any model in the session used fallback/estimated pricing.
- **FR-004**: System MUST tag each per-model entry with `pricing_estimated: true` when that specific model used fallback pricing, so multi-model sessions clearly distinguish exact vs. estimated costs.
- **FR-005**: System MUST emit a warning to stderr when fallback pricing is used, identifying the unmatched model(s) and the fallback tier applied.
- **FR-006**: System MUST track the number of API turns per session (count of deduplicated assistant messages) and include it as a `turns` field in the cost record.
- **FR-007**: System MUST compute and store a `total_tokens` field per model (sum of input + output + cache_read + cache_write tokens), matching the Rust runtime's `total_tokens()` calculation.
- **FR-008**: System MUST compute and store a session-level `total_tokens` field (sum across all models).
- **FR-009**: System MUST include the pricing table version (`pricing_version` field from `pricing.json`) in each cost record for audit purposes.
- **FR-010**: System MUST format all USD cost values to exactly 4 decimal places in cost records.
- **FR-011**: System MUST preserve backwards compatibility: existing cost records (without the new fields) must still be readable by report and session commands; new fields are additive.
- **FR-012**: System MUST NOT modify any files in the `rust/` directory.

### Key Entities

- **Pricing Table**: Versioned reference containing per-model token rates (input, output, cache_read, cache_write) for all supported Claude models. Includes a `version` integer and `updated` date. Includes a `fallback` section defining default rates for unknown models.
- **Cost Record** (updated): Extends the existing cost record with new fields: `turns` (integer), `total_tokens` (integer), `pricing_version` (integer), and `pricing_estimated` (boolean). Per-model entries gain `total_tokens` (integer) and `pricing_estimated` (boolean).
- **Fallback Pricing**: A complete set of default rates (not just cache ratios) used when a model has no pricing table match. Based on a designated default tier (Sonnet).

## Assumptions

- The official Anthropic API pricing is the authoritative source for token rates. The Rust source code's hardcoded pricing may lag behind actual API pricing changes.
- The `pricing.json` file will be updated to include a `fallback` section with complete default rates (input, output, cache_read, cache_write) rather than only cache ratio formulas.
- Existing test fixtures and test cases will be updated to reflect the new pricing values and additional fields.
- The installer (`src/install.sh`) will need to embed the updated `pricing.json` with correct rates and the new fallback structure.
- Report and session slash commands will be updated to display the new fields (turns, total_tokens) when present, and gracefully handle records that lack them.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Cost calculations for known models match hand-computed values using official Anthropic API pricing to within $0.0001 (rounding tolerance).
- **SC-002**: 100% of sessions with unknown models produce a non-zero estimated cost (instead of $0.00) with the `pricing_estimated` flag set to true.
- **SC-003**: All cost records include `turns`, `total_tokens`, and `pricing_version` fields after the update.
- **SC-004**: Historical cost records (without the new fields) continue to be processed correctly by report and session commands — no breaking changes.
- **SC-005**: All existing tests continue to pass after being updated for the new pricing values and fields, plus new tests cover: fallback pricing, turn counting, total_tokens calculation, pricing_version inclusion, and 4-decimal formatting.