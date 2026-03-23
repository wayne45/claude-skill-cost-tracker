# autoresearch: claude-skill-cost-tracker

Autonomous improvement loop for the Claude Code cost tracker. Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

## Setup

To set up a new experiment, work with the user to:

1. **Agree on a run tag**: propose a tag based on today's date (e.g. `mar23`). The branch `autoresearch/<tag>` must not already exist.
2. **Create the branch**: `git checkout -b autoresearch/<tag>` from current main.
3. **Read the in-scope files**: Read these files for full context:
   - `README.md` — project overview
   - `.claude/hooks/cost-tracker.sh` — the hook script (main logic)
   - `.claude/commands/cost-report.md` — /cost-report slash command
   - `.claude/commands/cost-session.md` — /cost-session slash command
   - `.claude/commands/cost-reset.md` — /cost-reset slash command
   - `.claude/cost-data/pricing.json` — pricing config
   - `tests/test-cost-tracker.sh` — test suite
   - `tests/fixtures/sample-transcript.jsonl` — test fixture
   - `specs/001-cost-tracker/spec.md` — feature requirements (read-only reference)
   - `specs/002-install-script/spec.md` — installer requirements (read-only reference)
4. **Run the baseline**: `bash tests/test-cost-tracker.sh` and record the initial pass/fail counts.
5. **Initialize results.tsv**: Create `results.tsv` with just the header row.
6. **Confirm and go**: Confirm setup looks good.

Once you get confirmation, kick off the experimentation.

## The metric

The metric is a composite score:

```
score = (pass_count / total_count) * 100 + total_count * 0.1
```

- `pass_count`: number of PASS assertions in the test output
- `total_count`: total number of assertions (PASS + FAIL)
- First term: pass rate as percentage (max 100) — this is the dominant factor
- Second term: small bonus for test coverage growth (0.1 per assertion)

**A higher score is better.** The score improves when you:
- Fix a failing test (pass rate goes up)
- Add a new test that passes (both terms go up)
- The score decreases when you break an existing test

**Gate rule**: If `pass_count < total_count` (any test fails), the experiment is an automatic **discard** regardless of score change. All existing tests must continue to pass.

## Experimentation

**What you CAN modify:**
- `.claude/hooks/cost-tracker.sh` — the main hook script. Bug fixes, edge cases, performance, accuracy, new capabilities.
- `tests/test-cost-tracker.sh` — the test suite. Add new test cases for improvements you make.
- `tests/fixtures/*` — test fixtures. Add new fixtures for new test scenarios.
- `.claude/commands/cost-report.md` — improve the report slash command.
- `.claude/commands/cost-session.md` — improve the session view slash command.
- `.claude/commands/cost-reset.md` — improve the reset slash command.
- `.claude/cost-data/pricing.json` — update pricing data.

**What you CANNOT modify:**
- `src/install.sh` — the installer will be synced from deployed files later by the human.
- `README.md`, `CLAUDE.md` — documentation is out of scope.
- `specs/*` — specifications are read-only references for understanding requirements.
- `program.md` — do not modify this file.
- `.claude/settings.local.json` — do not touch Claude Code settings.
- `.claude/cost-data/sessions.jsonl` — real user data, do not modify.

**What you CANNOT do:**
- Install new system dependencies. Only use bash, jq, git, and standard POSIX utilities.
- Modify real cost data in `.claude/cost-data/sessions.jsonl`.
- Break backward compatibility of the sessions.jsonl data format.

## Evaluation

Run the test suite and extract the metric:

```bash
bash tests/test-cost-tracker.sh 2>&1 | tee run.log
```

Extract results:

```bash
PASS_COUNT=$(grep -c "^PASS:" run.log)
FAIL_COUNT=$(grep -c "^FAIL:" run.log)
TOTAL=$((PASS_COUNT + FAIL_COUNT))
SCORE=$(echo "scale=1; ($PASS_COUNT / $TOTAL) * 100 + $TOTAL * 0.1" | bc)
echo "pass=$PASS_COUNT fail=$FAIL_COUNT total=$TOTAL score=$SCORE"
```

## Ideas for improvement

Read the specs for the full requirements. Here are concrete areas to explore:

**Bug fixes & edge cases:**
- What happens with empty or malformed transcript files?
- What happens when pricing.json is missing or corrupt?
- What if session transcript has no token usage data?
- What if git is not available (no code change tracking)?
- Race conditions in the lock file mechanism
- What if jq is not available or an old version?

**Accuracy improvements:**
- Verify cost calculation matches Anthropic billing precisely
- Handle new model IDs that don't match any pricing pattern
- Handle edge cases in token deduplication logic

**Performance:**
- Profile hook execution time (spec requires < 1 second)
- Optimize jq pipeline for large transcripts

**New capabilities:**
- Track conversation turn count
- Track tool usage counts
- Detect and handle session resumptions
- Support for custom pricing overrides

**Robustness:**
- Better error messages when things fail
- Graceful degradation when optional data is missing
- Validate JSONL integrity before appending

When adding a new capability, always add corresponding test cases.

## Output format

The test suite prints lines like:
```
PASS: description of what passed
FAIL: description of what failed (expected X, got Y)
```

And a summary at the end:
```
Results: X passed, Y failed out of Z tests
```

## Logging results

When an experiment is done, log it to `results.tsv` (tab-separated).

Header and columns:

```
commit	score	pass	total	status	description
```

1. git commit hash (short, 7 chars)
2. score (e.g. 102.1)
3. pass count / total count (e.g. 21/21)
4. status: `keep`, `discard`, or `crash`
5. short text description of what this experiment tried

Example:

```
commit	score	pass	total	status	description
a1b2c3d	102.1	21/21	keep	baseline
b2c3d4e	104.5	23/23	keep	add malformed transcript edge case test + fix
c3d4e5f	102.1	20/22	discard	refactor token dedup (broke cache token test)
d4e5f6g	0.0	0/0	crash	syntax error in jq filter
```

## The experiment loop

The experiment runs on a dedicated branch (e.g. `autoresearch/mar23`).

LOOP FOREVER:

1. Look at the current state: branch, latest score, recent results.
2. Pick an improvement to try. Prioritize:
   - Fixing any currently failing tests first
   - Bug fixes with new regression tests
   - Edge case handling with new tests
   - Then capability improvements with new tests
3. Make the code changes in the appropriate files.
4. If you added new behavior, add corresponding test cases in `tests/test-cost-tracker.sh`.
5. git commit with a descriptive message.
6. Run the evaluation: `bash tests/test-cost-tracker.sh 2>&1 | tee run.log`
7. Extract pass/fail/score from `run.log`.
8. If the run crashes (syntax error, etc.), check `run.log`, attempt a fix. If unfixable after a few tries, log as crash, revert, move on.
9. Record the results in results.tsv.
10. **Keep rule**: All previous tests still pass AND score >= previous score. Git advance.
11. **Discard rule**: Any previously passing test now fails, OR score decreased. Git reset to previous commit.

**Timeout**: Each test run should complete in under 30 seconds. If it hangs, kill it and treat as crash.

**NEVER STOP**: Once the experiment loop has begun, do NOT pause to ask the human if you should continue. The human might be away. You are autonomous. If you run out of obvious improvements, dig deeper — re-read the specs for unimplemented requirements, look for subtle bugs, try stress-testing edge cases, or improve test quality. The loop runs until the human interrupts you.
