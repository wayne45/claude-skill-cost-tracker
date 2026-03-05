# Feature Specification: Claude Code Cost Tracker

**Feature Branch**: `001-cost-tracker`
**Created**: 2026-03-05
**Status**: Draft
**Input**: User description: "I want to create a plugin or skill or hook or something for claude project that can continue calculate cost on the same claude project and can generate a report for details cost. including using models, tokens input output etc all about cost details."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track Cost Per Conversation (Priority: P1)

As a Claude Code user, I want costs to be automatically tracked after each conversation session so that I can understand how much each interaction costs without any manual effort.

When a conversation ends, the system automatically captures the full session data — including models used, token counts (input, output, cache read, cache write), durations (API time and wall time), code changes (lines added/removed), and calculated cost — then stores this data persistently within the project. The cost data accumulates across all conversations in the same Claude Code project.

**Why this priority**: Without automatic cost capture, there is no data to report on. This is the foundational capability that everything else depends on.

**Independent Test**: Can be fully tested by running a Claude Code conversation in the project and verifying that a cost record is created with the correct model, token counts, and calculated cost.

**Acceptance Scenarios**:

1. **Given** a Claude Code project with the cost tracker installed, **When** a conversation session completes, **Then** the system records: total cost, API duration, wall duration, code changes (lines added/removed), timestamp, and per-model token breakdown (input, output, cache read, cache write, and per-model cost).
2. **Given** a Claude Code project with existing cost records, **When** a new conversation session completes, **Then** the new cost record is appended to the existing data without overwriting previous records.
3. **Given** a conversation that uses multiple models (e.g., Opus and Haiku via subagents), **When** the session completes, **Then** the system records each model's token usage separately (input, output, cache read, cache write) with per-model cost.

---

### User Story 2 - Generate Cost Summary Report (Priority: P2)

As a Claude Code user, I want to generate a cost report on demand so that I can review a summary of all costs accumulated in my project, broken down by model, token type, and time period.

The user triggers a report command and receives a formatted summary showing total costs, per-model breakdown, token usage statistics, and cost trends.

**Why this priority**: Reporting is the primary way users consume the tracked data. Without it, the tracked data has limited value.

**Independent Test**: Can be fully tested by populating sample cost data and running the report command, then verifying the output includes all expected breakdowns and totals.

**Acceptance Scenarios**:

1. **Given** a project with accumulated cost data from multiple conversations, **When** the user requests a cost report, **Then** the system displays a summary in the conversation (total cost, total API duration, total wall duration, total code changes, per-model token and cost breakdown, session count) and saves a detailed markdown report file to the project directory.
2. **Given** a project with cost data spanning multiple days, **When** the user requests a cost report, **Then** the detailed report file includes a time-based breakdown (daily and session-level).
3. **Given** a project with no cost data, **When** the user requests a cost report, **Then** the system displays a clear message indicating no cost data has been recorded yet (no file is generated).
4. **Given** a generated report file already exists, **When** the user requests a new cost report, **Then** the previous report file is overwritten with the latest data.

---

### User Story 3 - View Cost for Current Session (Priority: P3)

As a Claude Code user, I want to see the cost of my current or most recent conversation so that I can get immediate feedback on how much an individual interaction cost.

**Why this priority**: While the full report covers aggregate data, users often want quick feedback on the cost of what they just did. This complements the summary report with real-time awareness.

**Independent Test**: Can be fully tested by completing a conversation and immediately requesting the current session cost, verifying it shows the correct model, tokens, and cost for that session.

**Acceptance Scenarios**:

1. **Given** a completed conversation session with cost data, **When** the user requests the current session cost, **Then** the system displays: total cost, API duration, wall duration, code changes, and per-model token breakdown (input, output, cache read, cache write, per-model cost).
2. **Given** multiple models were used in a single session, **When** the user requests the current session cost, **Then** the breakdown shows each model's contribution separately (input, output, cache read, cache write, cost) along with a session total.

---

### User Story 4 - Reset or Clear Cost Data (Priority: P4)

As a Claude Code user, I want to reset or clear the accumulated cost data so that I can start fresh tracking from a specific point in time (e.g., beginning of a new billing period or project phase).

**Why this priority**: Over time, accumulated data may become less relevant. Users need the ability to manage their tracking history.

**Independent Test**: Can be fully tested by accumulating some cost data, running the reset command, and verifying the data is cleared and subsequent reports show zero.

**Acceptance Scenarios**:

1. **Given** a project with accumulated cost data, **When** the user requests to reset cost data, **Then** the system clears all stored cost records and confirms the action.
2. **Given** a project with accumulated cost data, **When** the user requests to reset, **Then** the system asks for confirmation before deleting data.

---

### Edge Cases

- What happens when the cost data storage file is corrupted or manually edited incorrectly? The system should handle malformed data gracefully, report what it can, and warn about unreadable entries.
- What happens when a conversation is interrupted or cancelled before completion? Partial usage data should still be captured if available. If the hook does not fire, the filesystem fallback may recover data on the next session.
- What happens when hook event data is unavailable or incomplete? The system should fall back to parsing local session files and log a warning about the data source used.
- What happens when new Claude models are released with different pricing? The pricing information should be updatable without losing historical cost records.
- What happens when cost data grows very large (hundreds or thousands of sessions)? Reports should still generate within a reasonable time.
- What happens when multiple Claude Code sessions run concurrently in the same project? Data should not be lost or corrupted due to concurrent writes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically capture cost data at the end of each Claude Code conversation session via a Claude Code hook, using hook event data as the primary source and local session file parsing as a fallback. Captured data per session MUST include: total cost, API duration, wall duration, code changes (lines added, lines removed), timestamp, and per-model token breakdown (input tokens, output tokens, cache read tokens, cache write tokens, per-model cost).
- **FR-002**: System MUST persist cost data within the project directory so that it accumulates across conversations and is available for reporting.
- **FR-003**: System MUST support tracking costs for all Claude model variants (Opus, Sonnet, Haiku, and future models).
- **FR-004**: System MUST calculate costs using accurate per-model pricing for input tokens, output tokens, cache read tokens, and cache write tokens.
- **FR-005**: System MUST provide a slash command (skill) to generate a cost summary report, displaying a summary in the conversation and saving a detailed report as a markdown file in the project directory.
- **FR-006**: Cost reports MUST include: total cost, total API duration, total wall duration, total code changes (lines added/removed), total input tokens, total output tokens, total cache read tokens, total cache write tokens, per-model breakdown, and number of sessions tracked.
- **FR-007**: Cost reports MUST include a time-based breakdown showing costs per day or per session.
- **FR-013**: The conversation summary MUST include key totals and per-model breakdown. The saved report file MUST include full session-level detail.
- **FR-008**: System MUST provide a slash command (skill) to view the cost of the most recent or current session.
- **FR-009**: System MUST provide a slash command (skill) to reset/clear accumulated cost data, with confirmation required before deletion.
- **FR-010**: System MUST handle cases where multiple models are used in a single session (e.g., via subagents) by recording each model's token usage separately (input, output, cache read, cache write) with per-model cost.
- **FR-011**: System MUST gracefully handle corrupted or malformed cost data without crashing, displaying a warning and processing what it can.
- **FR-012**: System MUST allow pricing information to be updated to accommodate new models or pricing changes without affecting historical records.

### Key Entities

- **Cost Record**: A single unit of tracked session data, including: total cost, API duration, wall duration, code changes (lines added, lines removed), timestamp, and a per-model breakdown. Each model entry includes: model name, input token count, output token count, cache read token count, cache write token count, and per-model cost.
- **Cost Data Store**: The persistent collection of all cost records within a project. Organized to support querying by time period and model.
- **Pricing Table**: A reference containing per-model token pricing (cost per input token, cost per output token, cost per cache read token, cost per cache write token) for all supported Claude models.
- **Cost Report**: A formatted output summarizing cost records, with breakdowns by model, time period, and token type. Delivered in two forms: a concise summary displayed in the conversation, and a detailed markdown file saved to the project directory.

## Clarifications

### Session 2026-03-05

- Q: What Claude Code extension mechanism should the cost tracker use? → A: Hooks for automatic capture + Slash commands (skills) for reporting and management.
- Q: Where should the cost tracker read token usage data from? → A: Hook event data (stdin/env vars) as primary source, with filesystem parsing of Claude Code's local session files as fallback.
- Q: How should cost reports be presented to the user? → A: Both - display a summary directly in the Claude Code conversation, and save a detailed report as a markdown file in the project directory.
- Refinement: Cost data fields expanded based on Claude Code's actual `/cost` output. Per session: total cost, API duration, wall duration, code changes (lines added/removed). Per model: input tokens, output tokens, cache read tokens, cache write tokens, per-model cost.

## Constraints

- **Zero-cost operation**: The cost tracker itself MUST NOT generate any cost. It must not make API calls, use external paid services, or consume billable resources. All processing must be performed locally using only locally available data.

## Assumptions

- Claude Code hooks are used for automatic cost capture at session end; slash commands (skills defined in `.claude/commands/`) are used for reporting and management operations.
- Token counts (input and output) are available from Claude Code hook event data (primary) and from Claude Code's local session files as a fallback source.
- Cost data will be stored locally within the project directory (not in external services).
- USD is the default currency for cost calculations.
- The feature is designed for individual developer use within a single Claude Code project (not multi-user or team-level tracking).
- Standard Anthropic API pricing is used as the basis for cost calculations, with the ability to update pricing as it changes.
- Pricing data must be bundled locally (not fetched from the internet) to comply with the zero-cost constraint.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Cost data is automatically captured for 100% of completed conversation sessions without requiring any manual user action.
- **SC-002**: Users can generate a full cost report in under 5 seconds, regardless of the number of tracked sessions.
- **SC-003**: Cost calculations are accurate to within 1% of actual API billing for the same usage.
- **SC-004**: Users can view the cost of any individual session within 2 seconds.
- **SC-005**: The cost tracker adds no noticeable delay (less than 1 second) to the end of any conversation session.
- **SC-006**: Cost data persists reliably across sessions, with zero data loss under normal operating conditions.
