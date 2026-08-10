# Design: Three-rung weight dial + escalation-by-default for /do-it

Date: 2026-08-10
Status: approved (design), pending spec review

## Problem

`/do-it` currently controls review depth with **two overlapping dials**:

- **Mode** — FAST (one review pass) vs FULL (loops + diminishing-returns judge + 10-pass cap)
- **Tier** — LIGHT / STANDARD / HEAVY (which reviewers run, how many independent-model passes)

On paper that is six combinations. In practice it is about **four real behaviors**, because FAST strips the independent-model passes that the tiers differ on — so FAST-LIGHT, FAST-STANDARD, and FAST-HEAVY behave almost identically. Worse, the muddiest surviving combination (LIGHT-FULL: same-model passes wrapped in the full loop machinery) sits exactly where a clean "medium" should be, and its "single clean pass advances" rule collapses it back toward FAST anyway. Nobody can describe it, so it is under-documented.

Two consequences:

1. There is **no clean middle rung** between "check it myself once" and "run the full independent-model loop till clean."
2. Review depth is **predicted upfront** by the evaluator (it picks a fixed tier+mode after the spec draft) rather than **climbing on evidence** as the work reveals whether it needs more.

## Core insight

The two dials that actually matter are independent:

- **WHO reviews** — same-model subagents (fast, cheap, share my blind spots) vs an independent model / fresheyes (catches blind spots, but 5–15 min per pass and pricier).
- **HOW MANY times** — one pass vs loop-till-clean.

Blind-spot coverage has exactly one source: **an independent look.** Three same-model passes do not fix a same-model blind spot. So the real user tradeoff is **blind spots vs speed**: how soon are we willing to pay for one independent look.

That tradeoff picks a single diagonal path through the who × how-many grid, which becomes the new three-rung dial.

## Solution

Collapse the two dials into **one linear weight dial** with three rungs, and drive it with **evidence-based escalation** instead of upfront prediction.

### The three rungs

| Rung | What it buys | Who reviews | Loop? | Speed cost |
|---|---|---|---|---|
| **light** | fast first look | 1 same-model (subagent) pass | no | seconds–minutes |
| **medium** | one independent look, no iteration | 1 independent-model (fresheyes/codex) pass | no | + one codex pass (~5–15 min), paid once |
| **heavy** | independent look + iterate till clean | independent-model loop (floor + judge + 10-cap) | yes | multiple codex passes (~15–45 min) |

- **light** = today's FAST behavior, made a first-class named rung. Default start.
- **medium** = new rung. "One pass with codex." The blind-spot/speed sweet spot: one independent set of eyes, no looping. This is the rung that does not exist today.
- **heavy** = today's FULL loop machinery (diminishing-returns judge, 3-pass floor, 10-pass cap, fresheyes per pass). Unchanged in behavior.

### Escalation ladder (default, one-way, mechanical)

- Every run **starts at light** unless floored (see below).
- After the current rung's pass(es), any **surviving BLOCKER or SUBSTANTIVE finding** bumps the run up exactly one rung, for all remaining stages.
  - light finds a blocker → **medium** (bring in the independent model once)
  - medium's independent pass still finds a blocker → **heavy** (loop till clean)
- **Clean at any rung → advance, no escalation.**
- Escalation is **one-way** (never steps down) and **mechanical** (driven by the finding severities the scorecard already prints, not by executor judgment). This preserves the skill's core principle: the executor must never be the one who chooses to go light.
- The existing non-severity escalation paths remain: a `SPLIT` verdict, an Agency task failing its evaluator twice, and hard triggers surfacing mid-run all still bump the rung.

### Start floor (risky work skips the cheap start)

The upfront evaluator still runs after the spec draft, but its job changes: instead of fixing a tier+mode, it sets a **starting floor**.

- Ordinary tasks → floor = light (start cheap, climb on evidence).
- **Hard triggers** (security-sensitive surface, schema / data migration, an explicit "don't break X" / "byte-identical" lens) → floor = **medium** or **heavy**, so the run never starts light on dangerous work.
- The floor only ever raises the start; escalation from there is unchanged.

### Why this resolves blind-spots vs speed

- Easy tasks stay at light and **never wait for an independent pass** — done in minutes.
- Only tasks that **show trouble** pay the one codex wait (→ medium).
- Only tasks where even the independent look keeps finding blockers pay for the loop (→ heavy).
- You buy blind-spot coverage **exactly on the tasks that earn it**, and speed everywhere else.

### Cost is additive, not restart

Escalation reuses the artifacts already on disk (spec, plan, run manifest). Stepping a rung up costs **only the extra passes**, not a re-run from Step 0 — the same property the current skill already relies on for its FAST→FULL promotion.

### Latency honesty

- **medium always costs at least one independent-model wait** (~5–15 min) — that wait *is* the blind-spot look; there is no free version.
- The existing **Fresheyes Watchdog Protocol** caps the downside: a hung codex is killed at the 20-min ceiling and falls back to an independent same-model subagent, so a stall can never hang the run.
- The independent pass runs **in parallel** with the same-model pass (as FULL mode already does for Stage 1 ∥ Stage 2), so it sets the latency floor but does not stack in series.

## What changes in the skill

This design doc defines behavior; the exact SKILL.md edits are the implementation plan (next step). At the design level:

1. **Replace** the Mode (FAST/FULL) × Tier (LIGHT/STANDARD/HEAVY) two-axis model with a single **light / medium / heavy** dial throughout SKILL.md.
2. **Rewrite the Review-Tier Evaluator** to emit a *starting floor* (default light) instead of a fixed tier+mode. `references/evaluator-rubric.md` is rewritten accordingly.
3. **Redefine escalation** around surviving finding severity (mechanical, one-way), folding in the existing hard-trigger / SPLIT / fail-twice paths.
4. **Redefine the three rungs** in Reviewer Selection:
   - light = one same-model subagent pass, no codex, no loop
   - medium = one independent-model (fresheyes) pass, no loop, no judge
   - heavy = independent-model loop (unchanged: floor + judge + 10-cap)
5. **Update the scorecard** to print a single rung label plus any escalation (`rung: medium (escalated from light: SUBSTANTIVE survived)`), replacing the separate mode/tier fields.

### Explicitly unchanged

Mandatory Artifacts, the Run Manifest format (aside from the Tier/Mode line becoming a rung line), Agency execution, the Fresheyes Watchdog Protocol, Pre-Commit Artifact Verification, and Commit + Push all stay as-is.

## Blast radius / rollback

- **Files touched:** `do-it/SKILL.md` and `do-it/references/evaluator-rubric.md` in the canonical repo, then a deploy-copy sync to `~/.claude/skills/do-it/` (per the deployment-copy rule).
- **In-flight runs:** old run manifests reference `Tier`/`Mode`; new runs use `rung`. Resume is not supported *across* this change — a run started under the old model finishes under the old model. Documented, not migrated.
- **Rollback:** revert the two files and re-sync the deploy copy. No data migration, no external state.

## Decisions locked (during brainstorming)

- **Ladder path = codex-early** (light → one-codex-pass → codex-loop), chosen by the user's blind-spots-vs-speed priority. Rejected alternative: loop-early (add same-model passes before codex), which spends passes on the model's own blind spots.
- **medium does not loop** — a single independent pass. Rejected alternative: a short capped same-model loop.
- **Risky work floors the start** at medium/heavy. Rejected alternative: always start light regardless.
- **Collapse to one dial** rather than adding "medium" as a third orthogonal Mode. Rejected alternative: keep the two axes (nine combinations to reason about).

## Open questions

None blocking. Two to confirm during planning:

1. Exact wording of the hard-trigger list the evaluator uses to set a medium-vs-heavy start floor (reuse the current rubric's hard-trigger list, split by severity).
2. Whether the diminishing-returns judge and 3-pass floor stay **only** in heavy, or a lightweight 2-pass cap also guards medium if it were ever to loop (design says medium never loops, so this should be a no-op — confirm).
