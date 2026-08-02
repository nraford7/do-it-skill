---
name: do-it
description: Use when the user says /do-it, "just build it", "do it end-to-end", or "run the full pipeline" on a non-trivial build task. Not for trivial single-file edits, exploratory research, or work the user expects to steer mid-flight — the pipeline is single-shot and autonomous.
---

# /do-it — Autonomous Build Pipeline

End-to-end execution. User gives an instruction; this skill drives spec, plan, build, review, commit, push without further permission asks. The only place clarifying questions are allowed is **at the very start, before the spec is written**.

The loop has one job: deliver working code that passes review without burning tokens on diminishing returns.

## When to Use

- User says `/do-it <instruction>`
- User says "just do it", "build it end-to-end", "run the full pipeline" on a non-trivial change
- User wants the full Plan-with-superpowers / Execute-with-Agency / Review-with-superpowers workflow but does not want to be asked at every gate

**Do NOT use** for trivial single-file edits, exploratory research, or anything where the user expects to steer mid-flight. This skill assumes a single shot.

## The Pipeline

```
[0] Clarify (only if blocking)
      ↓
[1] Spec draft  ─→  REVIEW-TIER EVALUATOR (LIGHT/STANDARD/HEAVY + MODE: FAST|FULL)
      ↓                          ↓ (tier selects reviewer stacks; mode selects the pipeline shape)
    spec        ─→  review-loop  ─→  (split? recurse) ─→  ✓     [FAST: one review pass, no loop]
      ↓
[2] Plan        ─→  review-loop  ─→  (split? recurse) ─→  ✓     [FAST: one review pass, no loop]
      ↓
[3] Agency execution  (no permission asks — both modes, unchanged)
      ↓
[4] Post-build review (FULL: Stage 1 ∥ Stage 2 loop · FAST: one Stage-1 pass)
      ↓
[5] Verification gate → Commit + push   (both modes, unchanged)
```

Every FULL-mode fresheyes loop has a **Claude diminishing-returns judge** sitting on top deciding CONTINUE / STOP / SPLIT after each pass. FAST mode has no loops and no judge — see Pipeline Modes.

---

## Mandatory Artifacts (NO EXCEPTIONS)

By the time the pipeline reaches Step 5 (commit), ALL of the following files MUST exist on disk:

1. **Spec file** at `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md`
2. **Plan file** at `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`
3. **Run manifest** at `docs/superpowers/runs/YYYY-MM-DD-<slug>.md` (see Run Manifest below)
4. The actual code/doc deliverables for the work

**These are non-negotiable. The skill explicitly forbids the following rationalizations:**

- ❌ "The spec is detailed enough that the plan is implicit." → write the plan anyway, even if it's 30 lines.
- ❌ "This task is small / well-spec'd already." → small tasks get short plans, not no plans.
- ❌ "The parent spec already covers chunk X, so chunk X doesn't need its own plan." → write a chunk-specific plan that names files, line numbers, and acceptance criteria for that chunk.
- ❌ "The subagent prompt IS effectively the plan." → no, the plan is a versioned, fresheyes-reviewed artifact in git. The dispatch prompt is ephemeral.
- ❌ "Context budget is tight, so let's skip the plan step." → if the budget can't hold the cycle, save state and start fresh; don't skip.
- ❌ "Letting the cycle run feels heavy." → it's heavy by design. The discipline IS the value.

**If you (the executor) are tempted to skip a step in the cycle for ANY reason: write the missing artifact anyway.** That is always the correct resolution — every rationalization above ends the same way, so there is nothing to ask the user. Do NOT stop mid-run to ask; the pipeline is single-shot by design and a mid-run question stalls an unattended run indefinitely. Instead, record the temptation and its reason in the run manifest, and report it in the end-of-pipeline summary ("was tempted to skip X because Y; wrote it anyway"). The interactive ask survives in exactly ONE place — the Pre-Commit Artifact Verification backstop — because an artifact missing at that point means this rule already failed upstream and the user must decide.

The plan's value is independent of the spec's value:
- The spec describes WHAT and WHY.
- The plan describes HOW and IN WHAT ORDER.
- The plan's fresheyes pass surfaces issues the spec's fresheyes pass cannot — different artifact, different review angle, different findings.
- The plan creates the audit trail of implementation decisions.
- The fact that subagent execution succeeds without a plan does NOT validate the skip; it validates that the spec was sufficient *that one time*. The discipline is insurance; its value does not depend on catching something every run.

**Plan length scales with task size; plan EXISTENCE does not.** A 1-hour task gets a 30-line plan. A 1-week project gets a 500-line plan. Both go through ≥2 review passes.

---

## Run Manifest (state + resume + audit trail)

Create `docs/superpowers/runs/YYYY-MM-DD-<slug>.md` **before writing the spec** (first artifact of the run) and update it at every stage transition and every review pass. It is the single place a dead session can be resumed from and the audit trail the scorecards feed into.

Contents (keep it terse — this is a ledger, not prose):

```markdown
# Run: <slug>
Instruction: <the user's original /do-it instruction, verbatim>
Stage: <clarify | spec | spec-review | plan | plan-review | executing | code-review:<chunk> | verifying | committing | done>
Tier: <LIGHT | STANDARD | HEAVY> (<rubric scores or hard trigger>) <+ escalations with cause, if any>
Spec: docs/superpowers/specs/...   Plan: docs/superpowers/plans/...
Agency project: <id or —>

## Scorecards
<append every scorecard line, verbatim, as it is printed>

## Chunks
- [x] <chunk> — evaluator clean, review clean, N passes
- [ ] <chunk> — executing (task 3/5)

## Notes
<skip-temptations auto-resolved, re-plan amendments, fresheyes stalls/fallbacks, deferred findings>
```

**Resume rule:** if a session dies mid-run, a new session reads the manifest, verifies the artifacts it names still exist, and re-enters the pipeline at `Stage` — it does not restart from Step 0. If the budget can't hold the cycle (per the anti-skip rules), update the manifest and start fresh from it.

---

## Step 0 — Clarify (only at the start)

Read the user's instruction. If anything is genuinely blocking — ambiguous deliverable, missing acceptance criteria, conflicting constraints — ask **at most three** focused questions in a single message before doing anything else.

Do NOT ask about:
- Style / cosmetic preferences (use project conventions)
- Implementation choices that the spec/plan loop will surface anyway
- Whether to proceed (the answer is yes; that's why they invoked `/do-it`)

If nothing is blocking, skip this step and go straight to the spec.

---

## Step 1 — Spec

**First artifact of the run: create the run manifest** at `docs/superpowers/runs/YYYY-MM-DD-<slug>.md` (see Run Manifest section) with the verbatim instruction and `Stage: spec`.

Use **`superpowers:brainstorming`** first if scope is fuzzy. Then author the spec yourself at:

```
docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md
```

The spec must include: problem statement, success criteria (measurable), proposed approach, alternatives considered with why-not, blast radius / rollback plan, and any open questions.

**Once the spec draft exists, run the Review-Tier Evaluator (next section) — its verdict selects the reviewer stack AND the pipeline mode for this run.** Then enter the **spec review loop** (see Review Loop section below) — **or, in FAST mode, the single spec-review pass (see Pipeline Modes)**.

---

## Review-Tier Evaluator (runs ONCE, after the spec draft)

Not every task earns multiple codex passes. A one-file bugfix reviewed by three independent codex runs is ritual, not rigor — but the decision to go light must never belong to the executor, whose incentive is always to go light. So the tier is set by a **fresh subagent applying a fixed rubric**, recorded in the run manifest, and only ever escalated afterward, never lowered.

**Procedure:** dispatch one `general-purpose` subagent with the user's instruction, the spec draft, and the prompt in `references/evaluator-rubric.md` (read that file; use the prompt verbatim).

**Record the full verdict line in the run manifest** (`Tier: STANDARD · Mode: FAST (BR1 REV1 NOV0 INT1 FC1 = 4, no hard trigger)`). The tier selects the reviewer stack in Reviewer Selection below; the mode selects the pipeline shape (see Pipeline Modes).

**If the evaluator emits a `Lens:`** (constraint phrasing like "byte-identical" / "don't break X" from the instruction), record it in the manifest and include it verbatim as a mandatory review focus in EVERY review pass's prompt, both modes, all stages. The lens is how constraints get enforced without inflating the tier.

**Escalation (one-way ratchet, tier AND mode):** bump the tier one level — and promote FAST → FULL — for all remaining stages if any of these occur mid-run: a hard trigger surfaces that the spec didn't reveal, any judge verdict of `SPLIT`, a NEW-CATEGORY BLOCKER at pass 3+, an Agency task failing its evaluator twice, or (FAST mode) any BLOCKER finding in a single-pass review. Promotion enters the FULL machinery from the current stage forward — artifacts already exist, so it costs only the additional passes. Log the escalation + cause in the manifest. Neither tier nor mode EVER goes down mid-run, and the executor may not overrule the evaluator downward for any reason — that is the same skip-temptation the Mandatory Artifacts rules exist to block. The user can override in either direction in the original instruction ("go light on this" / "full review").

---

## Pipeline Modes (set by the evaluator, empirically calibrated)

**Basis:** the 2026-07-03 quadrant experiment (`~/Experiments/quadrant-test-2026-07-03/REPORT.md`) — on a STANDARD-tier task, a single-pass pipeline with Agency execution scored 93/120 (blinded judges) vs the full loop machinery's 98/120, at ~21% of the cost and ~20% of the wall clock, with identical held-out conformance (26/26 both). The loops' premium is real but narrow: they buy defect classes that only matter when silent wrongness is expensive. FULL mode is reserved for exactly those surfaces.

**FULL mode** — the pipeline as specified in the rest of this skill, unchanged: review loops with floors, diminishing-returns judge, fresheyes per Reviewer Selection, Stage 1 ∥ Stage 2 code review loops.

**FAST mode** — same skeleton, single-pass reviews, empirically ~1/5 the cost:

1. **All Mandatory Artifacts still apply** — spec, plan, manifest, all written, all committed. FAST trims passes, never discipline. The manifest's resume value alone justifies it (proven three times in one afternoon during the experiment).
2. **Spec review: ONE pass** by a fresh `general-purpose` subagent (correctness/completeness lens). Fix impact-YES findings; advance. No fresheyes, no floor, no judge.
3. **Plan review: ONE pass**, same shape (implementability lens).
4. **Agency execution: unchanged.** Same project mirroring, per-task evaluators, fail-twice → re-plan rule.
5. **Post-build review: ONE Stage-1 pass** (`superpowers:requesting-code-review`) on the chunk diff + the verification gate. No Stage-2 fresheyes, no loop.
6. **Scorecards still print** for every pass (judge column reads `n/a-fast`). The audit trail survives the mode.
7. **Escalation:** any BLOCKER in any FAST pass promotes the run to FULL from that stage forward (one-way; log cause in manifest).

The Review Loop, Pass Caps, and Diminishing-Returns Judge sections below apply to FULL mode only.

---

## Step 2 — Plan (MANDATORY — see Mandatory Artifacts above)

**This step is NOT skippable. No exceptions, no judgment calls, no "the spec covers it."**

After the spec passes review, invoke **`superpowers:writing-plans`** with the approved spec as input. Plans land at:

```
docs/superpowers/plans/YYYY-MM-DD-<slug>.md
```

Plan must have checkbox steps grouped into chunks. Each chunk is the meaningful deliverable unit. Verification commands and acceptance criteria are mandatory per chunk.

For SMALL tasks (single-file edit, brief investigation, parameter change): write a SHORT plan — 30-100 lines is fine — but write one. The plan describes:
- Files to touch with line numbers
- The change at each location
- Verification commands (tests, lint, smoke run)
- Acceptance criteria
- Rollback steps

For LARGE tasks (multi-system, schema migration, refactor): write a full plan — typically 200-1000 lines — with chunked structure, dependency ordering, per-chunk acceptance criteria.

Then enter the **plan review loop** (minimum 2 passes even on short plans; floor, early exit, and reviewer selection per Review Loop § Pass caps and § Reviewer Selection). **In FAST mode: one subagent pass instead (see Pipeline Modes) — the loop, floor, and judge do not apply.**

**Self-check before advancing to Step 3:**
- [ ] Plan file exists at `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`
- [ ] Plan has gone through the review passes its mode+tier requires (FAST: one subagent pass, findings fixed; FULL: see Reviewer Selection)
- [ ] FULL mode only: diminishing-returns judge emitted STOP at pass 3+ OR the tier's clean-pass exit fired (LIGHT: one clean pass; STANDARD: two clean passes; HEAVY: no early exit)
- [ ] Scorecard line was printed for every plan-review pass (both modes)
- [ ] Run manifest updated (stage = plan-approved)

If any checkbox is unchecked, DO NOT advance. Either complete it or surface to user.

---

## Step 3 — Agency Execution

This is non-negotiable: **execution uses Agency, not `superpowers:subagent-driven-development` or `superpowers:executing-plans`**. That is this skill's standing execution policy.

```
mcp__agency__agency_create_project   # mirror the plan's chunk/task structure
mcp__agency__agency_assign           # one assign per task, with the plan section as context
mcp__agency__agency_evaluator        # after each task
mcp__agency__agency_submit_evaluation
```

Do not ask the user for permission to start, to assign tasks, or to mark tasks complete. The plan was approved; execute it.

If a task fails the Agency evaluator twice with the same root cause, **stop and re-plan** rather than thrashing. Re-planning is a **lightweight amendment, not a full Step 2 re-entry**: amend the affected plan section in place, run ONE reviewer pass on the amended delta (a `general-purpose` subagent with the *implementability* lens — no 3-pass floor, no fresheyes required), record the failure + amendment in the run manifest, and resume execution. Full re-entry into Step 2 (with its review loop) is required only if the amendment changes chunk boundaries or cross-chunk contracts. Mention the re-plan in the end-of-pipeline summary.

---

## Step 4 — Post-Build Review (chunk boundary)

Review runs at **chunk boundaries, not per task** — that is this skill's review policy. After all tasks in a chunk are Agency-evaluator-clean, run the **two-stage review on the chunk's combined diff**.

**In FAST mode: one Stage-1 pass + verification gate, then commit (see Pipeline Modes; a BLOCKER promotes to FULL).** In FULL mode — on the LIGHT tier, run Stage 1 only, no fresheyes (see Reviewer Selection; a BLOCKER escalates the tier and brings Stage 2 in). On STANDARD and HEAVY:

**Stages 1 and 2 are independent by design (no shared context) — launch them IN PARALLEL, not sequentially.** Fresheyes takes 5–15 min; Stage 1 rides inside that window for free. Dispatch the Stage 1 subagent and the watchdogged fresheyes in the same round, then collect both.

1. **Stage 1** — `superpowers:requesting-code-review` against the combined diff.
2. **Stage 2** — `superpowers:fresheyes` for independent cross-validation (different model, no shared context). Model and effort come from `settings.json` env (`FRESHEYES_MODEL`, `FRESHEYES_REASONING`) — never pass or hardcode a model in the call. **Run it through `scripts/watchdog.sh` per the Fresheyes Watchdog Protocol below — never a bare call that could hang.** If fresheyes stalls twice, the protocol's fallback applies: a fresh `general-purpose` subagent with no shared context, or `code-review:code-review` on PRs.
3. Once both stages return, apply the combined findings via `superpowers:receiving-code-review` (technical rigor, no performative agreement). Re-run both stages (again in parallel) if substantive changes land.

Wrap this stage in the **review loop** as well — same diminishing-returns judge, same 10-pass cap and two-clean-pass early exit (see Review Loop § Pass caps).

Only when both stages return clean does the chunk move to commit.

---

## Fresheyes Watchdog Protocol (MANDATORY for EVERY fresheyes invocation)

**The wall this prevents:** codex/fresheyes can hang indefinitely — process alive, near-zero CPU, no output — and an unbounded foreground wait then stalls the whole pipeline (observed: ~48 min before manual intervention). A fresheyes call must never be able to stall the loop. Applies to spec fresheyes, plan fresheyes, AND Stage-2 code fresheyes — every time.

**Never invoke `fresheyes.sh` directly and never hand-roll a waiter. Always run it through the bundled watchdog:**

```bash
~/.claude/skills/do-it/scripts/watchdog.sh <fresheyes.sh path> <scope args...>
```

**If your fresheyes detaches into its own session** (current manual-mode default: it prints `FRESHPID=<pid>` and the launcher exits), pass `--foreground` in the scope args — a detached review escapes the watchdog's process group, so the watchdog sees the launcher exit and false-stalls every run, and its teardown cannot reach the real process.

Launch with `run_in_background: true`; the script self-terminates at its 20-minute ceiling, so it can never hang the loop. It prints exactly one status line:

- `FRESHEYES_DONE OUT=<file> LOG=<file>` — extract the review. Read `LOG` if `OUT` is empty: a late kill can leave `OUT` unwritten while the full review sits in the codex log (find the last "## Files Examined" through end).
- `FRESHEYES_STALLED …` — retry ONCE from scratch. On a second stall, immediately dispatch a fresh `general-purpose` subagent reviewer (no shared context) — a first-class substitute for fresheyes that satisfies the independent-cross-validation requirement. Do NOT retry a third time, do NOT wait, do NOT spiral.

The liveness rules and their rationale (log-vs-stdout buffering, verdict-before-flat-timer, mtime-marker log discovery, process-group-scoped teardown — never pattern-`pkill`) are encoded in the script and documented in its header comments. Tune timers only via the `FE_*` env vars; do not re-implement the loop inline.

Always emit a scorecard line for the pass regardless of which reviewer produced it (fresheyes vs fallback subagent) — the loop must keep converging. Surface a reboot/fallback in one line ("fresheyes stalled at N min — fell back to independent subagent"); do not go silent.

---

## Pre-Commit Artifact Verification (MANDATORY before Step 5)

Before staging anything for commit, run this self-check:

```bash
test -f docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md && echo "spec ✓" || echo "spec MISSING"
test -f docs/superpowers/plans/YYYY-MM-DD-<slug>.md && echo "plan ✓" || echo "plan MISSING"
test -f docs/superpowers/runs/YYYY-MM-DD-<slug>.md && echo "manifest ✓" || echo "manifest MISSING"
```

**Then run the verification gate:** execute the project's standard verification once on the combined result — test suite, lint, build, whatever the project defines (check the plan's verification commands, CLAUDE.md, or the obvious `package.json`/`Makefile`/CI config). Agency evaluators checked per-task; this is the only whole-result check before push. A failure blocks the commit: fix it, re-run the failing verification, and if the fix was substantive run one more Stage-1 review pass on the fix delta. If the project has no runnable verification, note that in the run manifest and proceed.

All three files must exist. If any is missing:
- **STOP.**
- **Do NOT commit.**
- **Surface the missing artifact to the user.** Acceptable surfacing: "I notice the [spec|plan] file is missing because I [skipped step X | reason]. Per the skill's Mandatory Artifacts rule I cannot commit without it. Want me to (a) write the missing file now, (b) abort the run, (c) explicit override (you take responsibility for the skip)?"

This check is the audit-trail backstop. The earlier anti-skip rules prevent the skip in real-time; this check catches it if it slipped through anyway.

---

## Step 5 — Commit + Push

**Runs in the git repo of the current working directory at invocation time.** This skill is global — it does not have an opinion about which project it belongs to. Whatever repo `pwd` resolves to is the target.

Before doing anything in this step:

1. Run `git rev-parse --show-toplevel` from cwd. If it errors (no enclosing repo), STOP and surface the wall. Offer to (a) `git init` here, or (b) point at a different directory. Do not invent a target.
2. Verify a remote exists (`git remote -v`). If none, STOP and surface — there is nothing to push to.
3. Confirm the current branch (`git branch --show-current`).

Then:

4. Stage only the files changed by this pipeline. Never `git add -A` / `git add .`.
5. Commit using a descriptive message ending with the standard Co-Authored-By trailer.
6. Push to the **current branch** of the cwd's repo. Never force-push. Never push to `master`/`main` if the current branch is master/main without explicit user confirmation in this session.
7. Report the final commit SHA + remote URL. Do not open a PR (user can run `commit-commands:commit-push-pr` separately if they want one).

If the working tree has unrelated dirty files, list them and ask before staging — do not auto-stage other people's work.

---

## The Review Loop (used in Steps 1, 2, 4 — FULL mode only; FAST mode uses the single passes defined in Pipeline Modes)

Each loop iteration:

1. Run the reviewer (see Reviewer Selection below). **Every fresheyes call here is governed by the Fresheyes Watchdog Protocol — bounded, liveness-watched, auto-rebooted or fallen back; a fresheyes pass may never stall the loop.**
2. Run the **Claude diminishing-returns judge** (see below).
3. **Print the one-line scorecard** (see below) — mandatory, every pass, no exceptions.
4. Judge returns one of: `CONTINUE`, `STOP`, `SPLIT`.

### Reviewer Selection (set by the Review-Tier Evaluator)

The tier from the Review-Tier Evaluator selects the reviewer stack for every loop:

| | Spec/plan loops | Code loop | Floor / exit |
|---|---|---|---|
| **LIGHT** | One `general-purpose` subagent pass per artifact — no codex. Clean (zero impact-YES B/S) → advance immediately. Findings → fix → one more subagent pass. | **Stage 1 only** (`superpowers:requesting-code-review`). No fresheyes unless a BLOCKER appears (→ escalate to STANDARD). | Single clean pass advances; judge from pass 3 as usual if findings keep coming. |
| **STANDARD** | Pass 1 uses **fresheyes** (the one independent-model look per text artifact). Passes 2+ use fresh `general-purpose` subagents — no shared context, one lens per pass, rotating: *correctness/completeness*, *implementability*, *failure modes/rollback*. | Stage 1 + Stage 2 every pass, **in parallel** (see Step 4). | Two-clean-pass early exit; 3-pass floor otherwise. |
| **HEAVY** | Passes 1 AND 2 use fresheyes; passes 3+ use lens-rotated subagents. | Stage 1 + Stage 2 every pass, in parallel. | **No early exit** — full 3-pass floor applies to every artifact. |

Rationale: subagent passes run in minutes; a codex fresheyes pass costs 5–15 min. The independence argument is strongest for code and for high-stakes artifacts — the tier spends codex passes exactly there and nowhere else.

### The One-Line Scorecard (mandatory after every pass)

After every reviewer pass, before moving on, print exactly one line in this format:

```
Pass N [<artifact>]: <B>B/<S>S/<C>C/<R>R · fixed <F>/<P> prior · velocity <↑|↓|=> (<prior>→<current>, escalation <yes|no>) · judge: <DECISION>
```

Where:
- `N` = pass number (1-indexed).
- `<artifact>` = `spec` | `plan` | `code:<chunk-name>`.
- `B / S / C / R` = count of BLOCKER / SUBSTANTIVE / COSMETIC / (RESTATEMENT + EXTENSION + DEFERRED) findings this pass.
- `F / P` = of the prior pass's BLOCKER+SUBSTANTIVE findings, how many are now resolved (`F`) out of the total that needed fixing (`P`). Pass 1 prints `fixed -/-`.
- `velocity` arrow: `↓` if `current_count < prior_count`, `=` if equal, `↑` if growing. Show raw counts in parens.
- `escalation` = `yes` if any current finding is more severe than the worst finding in the prior pass.
- `judge` = the verdict returned by the diminishing-returns judge (`CONTINUE`, `STOP-IMPACT`, `STOP-CLASS`, `STOP-VELOCITY`, `SPLIT`). At passes 1–2 the judge does not run; print `judge: pre-floor` — or `judge: early-exit` on pass 2 when the two-clean-pass early exit fires (see Pass caps). In FAST mode print `judge: n/a-fast` (no judge runs; a BLOCKER in the pass promotes the run to FULL instead).

**Example lines:**

```
Pass 1 [spec]: 3B/5S/2C/0R · fixed -/- · velocity = (—→10, escalation no) · judge: pre-floor
Pass 2 [spec]: 1B/4S/3C/2R · fixed 7/8 prior · velocity = (10→10, escalation no) · judge: pre-floor
Pass 3 [spec]: 0B/1S/4C/2R · fixed 4/5 prior · velocity ↓ (10→7, escalation no) · judge: STOP-VELOCITY
Pass 4 [code:ingest]: 0B/0S/6C/3R · fixed 1/1 prior · velocity ↑ (4→9, escalation no) · judge: STOP-CLASS
```

(Note pass 4: the count *grew* — arrow `↑` — but STOP-CLASS still fires because it is evaluated before velocity and every finding is COSMETIC/RESTATEMENT. The arrows must always match the raw counts in parens: `↓` strictly falling, `=` equal, `↑` growing.)

The scorecard is the user-visible signal that the loop is converging. If three consecutive passes show all-COSMETIC + RESTATEMENT findings and the judge has not yet called STOP, the scorecard makes that obvious — the user can call STOP manually. Never skip the scorecard, even when the judge says CONTINUE; it is the audit trail.

### Pass caps (hard ceilings)

When `/do-it` is invoked, the cap is **10 passes** per artifact. The diminishing-returns judge is the primary brake; the cap is the backstop.

- **Spec loop**: cap at **10 passes**.
- **Plan loop**: cap at **10 passes**.
- **Code-review loop per chunk**: cap at **10 passes**.

Floor is **3 passes** before the judge is allowed to call STOP — three independent looks at an artifact is the minimum to trust "clean" — with exactly one exception:

**Early exit (tier-dependent):** on **STANDARD**, if passes 1 AND 2 both return **zero impact-YES BLOCKER or SUBSTANTIVE findings**, advance immediately — the judge never runs; the pass-2 scorecard prints `judge: early-exit`. On **LIGHT**, a single clean pass advances (scorecard prints `judge: early-exit` at pass 1). On **HEAVY**, there is no early exit — the full 3-pass floor applies. This is the small-task relief valve — a 30-line plan for a 1-hour task should normally exit at its tier's clean-pass mark, not pay a floor designed for multi-system artifacts. COSMETIC findings do not block the exit (fix the trivial ones inline first).

If pass 10 still finds blockers, the judge MUST emit `SPLIT`. The artifact is too large or too underspecified; iterate-to-exhaustion is forbidden.

> The judge is expected to call STOP well before pass 10 on most runs. The 10-pass ceiling exists for genuinely hard artifacts (multi-system specs, large refactor plans, security-sensitive code) where the user has already accepted the token cost of deeper review by invoking `/do-it`. If the user explicitly says "stay strict, cap at 5 on this one," honor that override.

### The Diminishing-Returns Judge

After each review pass starting at pass 3, dispatch a Claude subagent with the prompt in `references/judge-prompt.md` (read that file; use the prompt verbatim — the finding taxonomy, Implementation Impact Test, and decision order live there).

The judge's verdict is binding for this skill. Any `STOP-*` decision advances to the next pipeline step. `CONTINUE` means fix the BLOCKER + SUBSTANTIVE items (those whose Impact Test is YES) and run another pass. `SPLIT` goes to the **Splitting** section.

---

## Splitting (when reviews don't converge)

When the judge emits `SPLIT`:

1. **For a spec** — break the spec into 2+ smaller specs along the boundaries the judge recommended. Each becomes its own pipeline run (Step 1 onward). Run them sequentially unless they are genuinely independent (no shared schema/contract changes), in which case dispatch in parallel.
2. **For a plan** — split the plan into smaller plans (typically by chunk). Re-enter Step 2 for each. Often the spec was fine but the plan tried to do too much per chunk — re-chunk and re-review.
3. **For a code review** — split the chunk. The combined diff is too large for reviewers to converge. Pull the most independent slice into its own chunk, deliver that first, then re-review the remainder.

Splitting is not failure. It is the system telling you the unit of work was wrong. The split branches inherit the same loop discipline.

---

## Defaults & Guardrails

- **Never enter plan mode.** A settings hook blocks `EnterPlanMode`; use `superpowers:writing-plans` instead.
- **Never `--no-verify` on commits.** Fix hook failures; never bypass.
- **Never force-push.** Especially not to master/main.
- **Never auto-merge to master/main.** This skill works on the current branch. If on master/main, ask before pushing.
- **Spec/plan paths are conventional.** Use `docs/superpowers/specs/` and `docs/superpowers/plans/`. If the project does not have these directories, create them.
- **Memory writes are allowed.** When the pipeline learns something durable (an architecture decision, a confirmed user preference, a project state change), write a memory per the user's auto-memory rules.
- **The Oracle posture is active.** Lead with the true sentence. Commit fully. Subtract until what remains refuses to be subtracted.
- **The cycle is the discipline. The discipline is the value.** Every step in the pipeline exists because skipping it has been observed to fail. Do not treat the skill's instructions as suggestions you can override with judgment; they are guardrails the user has explicitly asked to be enforced. If your judgment says "this step doesn't apply here," your judgment is wrong — surface to the user instead of acting on it.

---

## Output Discipline During the Run

- One sentence per pipeline-stage transition. ("Spec passing pass 4. Moving to plan.")
- **One scorecard line per review pass** (see Review Loop § The One-Line Scorecard). This is the only multi-pass status the user sees during a loop.
- No narration of internal deliberation.
- No multi-paragraph status updates unless something blocks.
- End-of-pipeline summary: one paragraph. What was delivered, where the commit landed, any deferred items, and any skip-temptations that were auto-resolved (see the anti-skip rule).

If something blocks mid-pipeline (an irrecoverable Agency failure, a merge conflict), stop and surface it immediately — do not spiral through workarounds. When you hit a wall, say so; never spiral through failed approaches silently. **A stalled fresheyes is NOT a wall to surface-and-stop on — it is handled automatically by the Fresheyes Watchdog Protocol (kill → retry once → fall back to a general-purpose subagent). The loop keeps moving; you only mention it in one line.**

---

## What This Skill Does Not Do

- It does not open PRs. Use `commit-commands:commit-push-pr` if you want a PR.
- It does not deploy. Deployment is a separate concern; this skill ends at `git push`.
- It does not run exhaustive per-task test gates beyond what Agency evaluators and Stage 1 reviewers already check — but it DOES run the project's standard verification once on the combined result before commit (see Pre-Commit Artifact Verification). Add deeper verification steps inside the plan if the work warrants it.
- It does not negotiate with the user mid-pipeline. Clarification is Step 0 only.
