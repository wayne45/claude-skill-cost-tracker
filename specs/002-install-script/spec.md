# Feature Specification: Cost Tracker Install Script

**Feature Branch**: `002-install-script`
**Created**: 2026-03-05
**Status**: Draft
**Input**: User description: "Create a script that can one click or run one script to install the cost tracker"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One-Command Installation (Priority: P1)

As a developer, I want to install the Claude Code cost tracker into any project by running a single command so that I can start tracking costs immediately without manual file copying or configuration.

The user runs one install command from the root of their Claude Code project. The script sets up all necessary files (hook script, slash commands, pricing data, hook configuration) and the cost tracker is ready to use on the next Claude Code session.

**Why this priority**: The entire purpose of this feature is to eliminate manual setup. A single-command install is the core value proposition.

**Independent Test**: Can be fully tested by running the install command in a fresh Claude Code project and verifying that all cost tracker files are created in the correct locations and the hook is configured.

**Acceptance Scenarios**:

1. **Given** a Claude Code project without the cost tracker, **When** the user runs the install command, **Then** all required files are created (hook script, slash commands, pricing config) and the hook is registered in settings.
2. **Given** a Claude Code project without the cost tracker, **When** the user runs the install command, **Then** the hook script is made executable automatically.
3. **Given** a successful installation, **When** the user starts a new Claude Code session, **Then** the cost tracker hook fires on conversation completion and the slash commands (`/cost-report`, `/cost-session`, `/cost-reset`) are available.

---

### User Story 2 - Safe Installation with Existing Configuration (Priority: P2)

As a developer, I want the install script to safely handle projects that already have Claude Code settings or an existing cost tracker installation so that my existing configuration is not overwritten or corrupted.

**Why this priority**: Many projects already have `.claude/settings.local.json` with custom permissions, hooks, or other configuration. Overwriting these would be destructive. Safe merging is essential for real-world adoption.

**Independent Test**: Can be fully tested by creating a project with an existing `.claude/settings.local.json` containing other hook configurations, running the installer, and verifying both the existing hooks and the new cost tracker hooks are present.

**Acceptance Scenarios**:

1. **Given** a project with an existing `.claude/settings.local.json` containing other hooks, **When** the user runs the install command, **Then** the cost tracker hook is added without removing or modifying existing hook entries.
2. **Given** a project where the cost tracker is already installed, **When** the user runs the install command, **Then** the script detects the existing installation and offers to update/reinstall rather than duplicating files.
3. **Given** a project with existing slash command files in `.claude/commands/`, **When** the user runs the install command, **Then** existing command files are not overwritten unless they are cost tracker commands being updated.

---

### User Story 3 - Prerequisite Validation (Priority: P3)

As a developer, I want the install script to check that all prerequisites are met before installing so that I get clear feedback if something is missing rather than a broken installation.

**Why this priority**: A failed or partial installation due to missing prerequisites creates a poor experience and debugging burden. Upfront validation prevents this.

**Independent Test**: Can be fully tested by running the install command without `jq` installed and verifying the script reports the missing prerequisite and does not proceed with installation.

**Acceptance Scenarios**:

1. **Given** a system without `jq` installed, **When** the user runs the install command, **Then** the script reports that `jq` is required, provides installation instructions for the detected operating system, and does not proceed.
2. **Given** a directory that is not a Claude Code project (no `.claude/` directory), **When** the user runs the install command, **Then** the script warns the user and asks for confirmation before creating the `.claude/` structure.
3. **Given** all prerequisites are met, **When** the user runs the install command, **Then** the prerequisite check passes silently and installation proceeds.

---

### Edge Cases

- What happens if the user runs the install script from a subdirectory of the project? The script should detect the project root (via git root or `.claude/` directory presence) and install relative to it, or warn the user to run from the project root.
- What happens if the `.claude/settings.local.json` file contains malformed JSON? The script should detect this, warn the user, and create a backup before attempting to fix or skip the settings merge.
- What happens if file permissions prevent creating files in `.claude/`? The script should report the permission error clearly.
- What happens if the install script is interrupted midway? Partial installations should be detectable and recoverable by re-running the installer.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The installer MUST be runnable as a single remote command (`curl -sL <url> | bash`) from the project root directory, requiring no prior clone of the repository.
- **FR-002**: The installer MUST create the hook script file and make it executable.
- **FR-003**: The installer MUST create all slash command files (`/cost-report`, `/cost-session`, `/cost-reset`).
- **FR-004**: The installer MUST create the pricing configuration file with current model pricing.
- **FR-005**: The installer MUST add the cost tracker hook configuration to `.claude/settings.local.json`, merging with existing content if the file already exists.
- **FR-006**: The installer MUST validate that `jq` is installed before proceeding, and provide OS-specific installation instructions if missing.
- **FR-007**: The installer MUST detect if the cost tracker is already installed. On reinstall, it MUST create `.bak` copies of existing files before overwriting them with updated versions.
- **FR-008**: The installer MUST preserve all existing hooks, commands, and settings when merging into existing configuration files.
- **FR-009**: The installer MUST display a summary of actions taken upon successful completion, including the list of files created/updated and next steps. Messaging must describe cost tracking as "zero-overhead data capture" (not "zero-cost"), since slash commands consume tokens.
- **FR-010**: The installer MUST work on macOS and Linux systems.

## Clarifications

### Session 2026-03-20

- Q: README says "zero-cost session cost tracking" but slash commands consume tokens. How should this be described? → A: "Automatic session cost tracking with zero-overhead data capture" — emphasizes the hook is free, commands cost normally.
- Q: Should the installer support remote one-liner install or only local execution after cloning? → A: Remote one-liner (`curl -sL <url> | bash`) — no clone needed, true single-command install.
- Q: How should the installer obtain cost tracker source files (hook, commands, pricing)? → A: Self-contained — all file contents embedded directly in the install script as heredocs.
- Q: What should the update/reinstall behavior be for existing files? → A: Overwrite with backup — create `.bak` copies of existing files before replacing.
- Q: Should the installer modify the target project's README.md? → A: No — technical files only. Don't touch README.

## Assumptions

- The install script is fully self-contained: all cost tracker files (hook script, slash commands, pricing config) are embedded in the script as heredocs. No additional network fetches are needed at install time.
- The user runs the install command from the root of a directory that is or will become a Claude Code project.
- The installer is a self-contained script with no external dependencies beyond standard shell utilities and `jq` (which it validates).
- The install script is hosted in this repository and fetchable via a raw GitHub URL. Users install via `curl -sL <url> | bash` without needing to clone the repo.
- The cost tracker feature (001-cost-tracker) is implemented and its source files are available for the installer to copy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can go from zero to a fully working cost tracker installation in under 30 seconds by running a single command.
- **SC-002**: The installer correctly preserves 100% of existing Claude Code settings when merging hook configuration.
- **SC-003**: The installer detects and reports missing prerequisites in 100% of cases before attempting installation.
- **SC-004**: 100% of installed files pass validation checks (hook script executable, JSON files parseable, command files present).
- **SC-005**: The installer works without modification on both macOS and Linux.
