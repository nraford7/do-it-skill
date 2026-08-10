# Three-Rung Weight Dial + Escalation-by-Default — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `/do-it`'s two-axis review model (Mode FAST/FULL × Tier LIGHT/STANDARD/HEAVY) with a single light/medium/heavy dial that starts light and climbs one rung on surviving BLOCKER/SUBSTANTIVE findings, with a start floor for risky work.

**Architecture:** Edit two markdown files in the canonical repo (`do-it/SKILL.md`, `do-it/references/evaluator-rubric.md`), leave `do-it/references/judge-prompt.md` and `do-it/scripts/watchdog.sh` untouched, then sync the deploy copy at `~/.claude/skills/do-it/`. The change is prose/spec editing, not code — "tests" are grep-based consistency gates plus a full read-through, because the artifact is an instruction document with no runnable suite.

**Tech Stack:** Markdown. Bash grep/diff/rsync for verification and sync. Git on branch `medium-tier-escalation`.

## Global Constraints

- Design source of truth: `docs/superpowers/specs/2026-08-10-medium-tier-escalation-design.md`. Every task implements a part of it.
- **The three rungs are exactly:** `light` = one same-model subagent pass, no loop; `medium` = one independent-model (fresheyes) pass, no loop; `heavy` = the existing full review loop (fresheyes passes 1–2, lens-rotated subagents 3+, 3-pass floor, diminishing-returns judge from pass 3, 10-pass cap, Stage 1 ∥ Stage 2 per code pass). Use these three lowercase words verbatim everywhere. Never reintroduce `FAST`, `FULL`, `STANDARD`, or the tier/mode split.
- **Escalation is one-way and mechanical:** a surviving impact-YES BLOCKER/SUBSTANTIVE finding after a rung's pass(es) climbs exactly one rung (light→medium→heavy). It never steps down. The executor may never choose to lower it.
- **Start floor:** ordinary work starts `light`; a hard trigger floors the start at `heavy`; FAILURE COST=2 or a "don't break X"/"byte-identical" constraint floors the start at `medium`.
- **light and medium never loop.** The Review Loop, Pass caps, Diminishing-Returns Judge, and early exit apply to `heavy` only.
- **Unchanged behavior (do not edit these sections' substance):** Mandatory Artifacts, Run Manifest format (except its Tier line), Step 3 Agency Execution, Fresheyes Watchdog Protocol, Pre-Commit Artifact Verification, Step 5 Commit + Push, Splitting, Defaults & Guardrails, Output Discipline, What This Skill Does Not Do.
- The canonical repo is `~/Projects/do-it-skill`; `~/.claude/skills/do-it/` is a deploy copy synced from it (never edit the deploy copy directly).

---

## File Structure

- `do-it/references/evaluator-rubric.md` — **rewritten** (Task 1). Emits a start-floor, not a tier+mode.
- `do-it/SKILL.md` — **converted** section-by-section to the three-rung model (Task 2).
- `do-it/references/judge-prompt.md` — **verified unchanged** (Task 3); it is a severity taxonomy that heavy reuses as-is.
- `do-it/scripts/watchdog.sh` — untouched.
- `~/.claude/skills/do-it/**` — **synced** from canonical (Task 4).

---

### Task 1: Rewrite the Start-Floor Evaluator rubric

**Files:**
- Modify (full rewrite): `do-it/references/evaluator-rubric.md`

**Interfaces:**
- Produces: an evaluator prompt whose strict output block has fields `Start-floor: light | medium | heavy`, `Hard-trigger:`, `Scores:`, `Lens:`, `Reason:`. SKILL.md Task 2 references these field names (`Start-floor`, `Lens`) verbatim.

- [ ] **Step 1: Replace the entire file contents** with:

````markdown
# Start-Floor Evaluator prompt

Dispatch one `general-purpose` subagent with the user's instruction, the spec draft, and this prompt verbatim:

```
You are a start-floor evaluator for a build pipeline. The pipeline starts
every run at the cheapest review rung (light) and climbs on evidence. Your
job is ONLY to decide whether THIS task is too risky to start light — i.e.
whether it must start already floored at medium or heavy. Be literal with the
rubric; do not exercise judgment outside it. When torn, pick the HIGHER floor.

STEP 1 — HARD TRIGGERS. If ANY apply, output Start-floor: heavy and stop:
  - DESTRUCTIVE or irreversible schema/data change: DROP, type narrowing,
    backfill, rewrite, delete, or any mutation you cannot roll back. Purely
    ADDITIVE changes (nullable column, enum value, new table) are NOT a hard
    trigger — they fall through to the score below.
  - security-sensitive surface: auth, secrets, payments, PII, permissions
  - a contract/API consumed outside this repo changes shape
  - touches production config, deploy paths, or shared/prod state
  - the user's instruction EXPLICITLY requests thoroughness ("audit",
    "security review", "be thorough", "full review").

STEP 2 — SCORE five dimensions, 0/1/2 each (for the audit trail and the
medium-floor test in STEP 3):
  BLAST RADIUS   0: one file · 1: one module (any file count)
                 2: multi-module or cross-service (file count alone never
                 scores 2 — a routine full-stack feature touching backend +
                 frontend + tests within one feature slice is a 1)
  REVERSIBILITY  0: additive, trivial revert · 1: modifies existing behavior
                 2: hard to revert once depended on
  NOVELTY        0: repeats an existing repo pattern · 1: new logic, known territory
                 2: new subsystem or unfamiliar domain
  INTERFACE      0: internal only · 1: crosses module boundaries
                 2: changes contracts other code relies on
  FAILURE COST   0: cosmetic · 1: a broken feature · 2: data loss, outage, or money

STEP 3 — MEDIUM FLOOR. If no hard trigger fired, output Start-floor: medium
if EITHER holds (buy one independent look up front on work that is expensive
to get wrong):
  - FAILURE COST = 2, OR
  - the instruction carries a constraint you must not violate ("don't break
    X", "byte-identical", "keep the API stable").

STEP 4 — Otherwise output Start-floor: light. Ordinary work starts light; the
pipeline escalates only if a review pass surfaces a surviving problem.

CONSTRAINT LENS: if the instruction carries constraint phrasing ("don't break
X" / "byte-identical"), name it verbatim on the Lens line REGARDLESS of floor
— every review pass at every rung must carry it as a mandatory focus.

OUTPUT (strict):
  Start-floor: light | medium | heavy
  Hard-trigger: <which one, or "none">
  Scores: BR=<n> REV=<n> NOV=<n> INT=<n> FC=<n> total=<n>
  Lens: <constraint phrasing to carry as a mandatory review lens, or "none">
  Reason: <one sentence>
```
````

- [ ] **Step 2: Verify no stale vocabulary remains**

Run: `grep -niE "Tier:|Mode:|FAST|FULL|STANDARD" do-it/references/evaluator-rubric.md`
Expected: no output (exit 1). If any line prints, the rewrite left old vocabulary — fix it.

- [ ] **Step 3: Verify the output contract fields exist**

Run: `grep -nE "Start-floor:|Hard-trigger:|Scores:|Lens:|Reason:" do-it/references/evaluator-rubric.md`
Expected: all five field names present (the STEP body + the OUTPUT block).

- [ ] **Step 4: Commit**

```bash
git add do-it/references/evaluator-rubric.md
git commit -m "do-it: rewrite evaluator to emit a start-floor, not a tier+mode"
```

---

### Task 2: Convert SKILL.md to the three-rung model

**Files:**
- Modify: `do-it/SKILL.md` (multiple sections — anchors below; line numbers are approximate and drift as edits land, so match on the quoted anchor text)

**Interfaces:**
- Consumes: the `Start-floor` / `Lens` output fields from Task 1's rubric.
- Produces: a SKILL.md that uses only `light`/`medium`/`heavy` and the escalation ladder; consumed by nothing downstream except the deploy sync in Task 4.

Each step below is one bounded edit. After a step, the file is intentionally mid-conversion; consistency is verified once at the end (Steps 12–14). Do the steps in order.

- [ ] **Step 1: Pipeline diagram + intro (the `## The Pipeline` fenced block and the paragraph under it, ~lines 22–38).** Replace the evaluator/mode annotations and the paragraph after the block.

Replace the annotation lines inside the code block:
```
[1] Spec draft  ─→  START-FLOOR EVALUATOR (light | medium | heavy start)
      ↓                          ↓ (floor = light unless risk floors it higher; climbs on evidence)
    spec        ─→  review       ─→  (escalate? / split?) ─→  ✓     [light/medium: one pass, no loop]
      ↓
[2] Plan        ─→  review       ─→  (escalate? / split?) ─→  ✓     [light/medium: one pass, no loop]
      ↓
[3] Agency execution  (no permission asks — all rungs, unchanged)
      ↓
[4] Post-build review (heavy: Stage 1 ∥ Stage 2 loop · light: one Stage-1 pass · medium: one Stage 1 ∥ Stage 2 round)
      ↓
[5] Verification gate → Commit + push   (all rungs, unchanged)
```

Replace the paragraph directly beneath the block (currently begins "Every FULL-mode fresheyes loop…") with:
```
Only the **heavy** rung loops; it has a Claude diminishing-returns judge on top deciding CONTINUE / STOP / SPLIT after each pass. **light** and **medium** do not loop — light is one same-model pass, medium is one independent-model pass. See The Three Rungs.
```

- [ ] **Step 2: `## Run Manifest` — the `Tier:` line (~line 83).** Replace:
```
Tier: <LIGHT | STANDARD | HEAVY> (<rubric scores or hard trigger>) <+ escalations with cause, if any>
```
with:
```
Rung: <light | medium | heavy> (start-floor <light | medium | heavy>: <hard-trigger | FC=2 | constraint-lens | default>) <+ escalations with cause, if any>
```

- [ ] **Step 3: Step 1 — Spec, the evaluator sentence (~line 127).** Replace the sentence beginning "Once the spec draft exists, run the Review-Tier Evaluator…" with:
```
**Once the spec draft exists, run the Start-Floor Evaluator (next section) — its verdict sets the run's starting rung (`light` unless risk floors it higher).** Then run the review for the current rung (see The Three Rungs) — one pass at light/medium, or the spec review loop at heavy.
```

- [ ] **Step 4: `## Review-Tier Evaluator` section header + body (~lines 131–141).** Rename the header to `## Start-Floor Evaluator (runs ONCE, after the spec draft)` and replace its body with:
```
Not every task earns an independent-model pass, let alone a full loop — but the decision to stay light must never belong to the executor, whose incentive is always to go light. So the STARTING rung is set by a **fresh subagent applying a fixed rubric**, recorded in the run manifest, and from there only ever climbs on evidence, never drops.

**Procedure:** dispatch one `general-purpose` subagent with the user's instruction, the spec draft, and the prompt in `references/evaluator-rubric.md` (read that file; use the prompt verbatim).

**Record the verdict line in the run manifest** (`Rung: light (start-floor light: default, BR1 REV1 NOV0 INT1 FC1 = 4)`). The floor sets where the run STARTS; The Three Rungs defines what each rung runs; escalation (below) defines how it climbs.

**If the evaluator emits a `Lens:`** (constraint phrasing like "byte-identical" / "don't break X"), record it in the manifest and include it verbatim as a mandatory review focus in EVERY review pass's prompt, every rung, all stages. The lens is how constraints get enforced at any rung.

**Escalation (one-way ratchet, mechanical):** the rung climbs exactly one step, for all remaining stages, whenever any of these occur mid-run:
- a review pass leaves an impact-YES BLOCKER or SUBSTANTIVE finding unfixed after that rung's pass(es) — light→medium, medium→heavy;
- a judge verdict of `SPLIT` (heavy only) → Splitting;
- a hard trigger surfaces that the spec didn't reveal → jump straight to heavy;
- an Agency task fails its evaluator twice → re-plan (Step 3) and bump the rung one step.

Escalation reuses the artifacts already on disk, so a step up costs only the additional passes, never a restart. The rung NEVER drops, and the executor may not overrule it downward for any reason — that is the same skip-temptation the Mandatory Artifacts rules exist to block. Escalation is driven by the finding severities the scorecard already prints, NOT by executor judgment. Log every escalation + cause in the manifest. The user can override in either direction in the original instruction ("go light on this" / "full review").
```

- [ ] **Step 5: Replace the whole `## Pipeline Modes` section (~lines 145–161)** with a new `## The Three Rungs` section:
```
## The Three Rungs (set by the Start-Floor Evaluator, climbed on evidence)

Review depth is a single dial with three rungs. Every run starts at its floor (light unless the evaluator floored it higher) and climbs one rung whenever a review pass leaves a real problem unfixed. It never climbs down. **All Mandatory Artifacts apply at every rung** — the rung trims passes, never discipline.

**Basis:** the 2026-07-03 quadrant experiment (`~/Experiments/quadrant-test-2026-07-03/REPORT.md`) — on a moderate task, a single-pass pipeline with Agency execution scored 93/120 (blinded judges) vs the full loop's 98/120, at ~21% of the cost and ~20% of the wall clock, with identical held-out conformance (26/26 both). The loop's premium is real but narrow: it buys defect classes that only matter when silent wrongness is expensive. Light spends nothing on it; heavy spends it in full; medium buys the one thing that closes most of the gap — a single independent look.

**light** — one same-model (`general-purpose` subagent) pass per artifact. No independent model, no loop, no judge. Fast (minutes). The default start.
- Spec/plan: one subagent pass (correctness/completeness lens). Clean → advance.
- Code: one Stage-1 pass (`superpowers:requesting-code-review`) + the verification gate. Clean → commit.
- A surviving impact-YES BLOCKER or SUBSTANTIVE finding escalates to medium. Light NEVER loops — it advances clean or escalates.

**medium** — one INDEPENDENT-model (`superpowers:fresheyes`) pass per artifact. No loop, no judge. Buys blind-spot coverage once (~5–15 min for the one codex pass, watchdog-capped).
- Spec/plan: one fresheyes pass (Fresheyes Watchdog Protocol applies). Clean → advance.
- Code: Stage 1 ∥ Stage 2 (fresheyes), ONE round in parallel (see Step 4). Clean → commit.
- Scorecard prints for the pass (judge column `n/a-medium`). A surviving impact-YES BLOCKER or SUBSTANTIVE finding escalates to heavy. Medium NEVER loops — one independent look, then advance or escalate.

**heavy** — the full review loop: fresheyes on passes 1–2, lens-rotated subagents 3+, 3-pass floor, diminishing-returns judge from pass 3, 10-pass cap, Stage 1 ∥ Stage 2 every code pass (see The Review Loop, Pass caps, and the Diminishing-Returns Judge below).
- Two-clean-pass early exit applies — UNLESS the run was floored at heavy by a hard trigger (security, destructive migration, explicit thoroughness), in which case there is NO early exit and the full 3-pass floor always runs.
- A judge `SPLIT` goes to Splitting.

The Review Loop, Pass caps, and Diminishing-Returns Judge sections below apply to the **heavy rung only**.
```

- [ ] **Step 6: Step 2 — Plan, the review sentence (~line 186).** Replace the sentence beginning "Then enter the **plan review loop**…" with:
```
Then run the plan review for the current rung (see The Three Rungs): one subagent pass at light, one fresheyes pass at medium, or the plan review loop at heavy (minimum 2 passes; floor, early exit, and reviewer selection per Review Loop § Pass caps and § Reviewer Selection).
```

- [ ] **Step 7: Step 2 — the self-check checkboxes (~lines 190–192).** Replace the three mode/tier checkboxes with:
```
- [ ] Plan has gone through the review its rung requires (light: one subagent pass, findings fixed; medium: one fresheyes pass; heavy: see Reviewer Selection)
- [ ] heavy only: diminishing-returns judge emitted STOP at pass 3+ OR the two-clean-pass early exit fired (never on hard-trigger-floored heavy)
- [ ] Scorecard line was printed for every plan-review pass (all rungs)
```

- [ ] **Step 8: Step 4 — Post-Build Review, the mode/tier paragraph (~line 220).** Replace the sentence beginning "In FAST mode: one Stage-1 pass…" with:
```
**At light: one Stage-1 pass + verification gate, then commit (a surviving BLOCKER/SUBSTANTIVE escalates to medium). At medium: one Stage 1 ∥ Stage 2 round in parallel, then commit if clean (a surviving BLOCKER/SUBSTANTIVE escalates to heavy).** At heavy:
```
(Leave the following "Stages 1 and 2 are independent by design… launch them IN PARALLEL" paragraph and the numbered Stage 1 / Stage 2 / apply-findings list intact — they describe the parallel mechanics that both medium and heavy use.)

- [ ] **Step 9: Step 4 — the "Wrap this stage in the review loop" sentence (~line 228).** Replace with:
```
At heavy, wrap this stage in the **review loop** — same diminishing-returns judge, 10-pass cap, and two-clean-pass early exit (see Review Loop § Pass caps). At light and medium there is no loop: one round, then advance or escalate.
```

- [ ] **Step 10: The Review Loop header (~line 297).** Replace:
```
## The Review Loop (used in Steps 1, 2, 4 — FULL mode only; FAST mode uses the single passes defined in Pipeline Modes)
```
with:
```
## The Review Loop (used in Steps 1, 2, 4 — HEAVY RUNG ONLY; light and medium run the single passes defined in The Three Rungs)
```

- [ ] **Step 11: Reviewer Selection table (~lines 306–316).** Replace the header line, intro sentence, and the three-row table with:
```
### Reviewer Selection (per rung)

The starting rung, and any rung it escalates to, selects the reviewer stack:

| Rung | Spec/plan | Code | Loop / exit |
|---|---|---|---|
| **light** | one `general-purpose` subagent pass. Clean → advance; surviving impact-YES B/S → escalate to medium. | Stage 1 only (`superpowers:requesting-code-review`) + verification gate. Surviving B/S → escalate to medium. | No loop — one pass, then advance or escalate. |
| **medium** | one `superpowers:fresheyes` pass (Watchdog Protocol). Clean → advance; surviving B/S → escalate to heavy. | Stage 1 ∥ Stage 2 (fresheyes), one parallel round (see Step 4). Surviving B/S → escalate to heavy. | No loop — one independent round, then advance or escalate. |
| **heavy** | passes 1 AND 2 use fresheyes; passes 3+ use lens-rotated `general-purpose` subagents — no shared context, one lens per pass, rotating: *correctness/completeness*, *implementability*, *failure modes/rollback*. | Stage 1 + Stage 2 every pass, in parallel (see Step 4). | 3-pass floor + judge from pass 3 + 10-pass cap. Two-clean-pass early exit, EXCEPT no early exit when floored at heavy by a hard trigger. |

Rationale: subagent passes run in minutes; a fresheyes pass costs 5–15 min. Light spends none; medium spends exactly one; heavy spends them across the loop. The independence argument is strongest for code and high-stakes artifacts — the ladder buys codex passes there, and climbs to them only on evidence.
```

- [ ] **Step 12: Scorecard judge field (~line 333) — the bullet defining `judge`.** Replace the sentence fragment "In FAST mode print `judge: n/a-fast`…" with:
```
At light print `judge: n/a-light` and at medium print `judge: n/a-medium` (no judge runs at those rungs; a surviving BLOCKER/SUBSTANTIVE escalates the rung instead). The judge runs only at heavy, from pass 3.
```

- [ ] **Step 13: Pass caps intro (~line 350) and Early exit (~line 358).**

Prepend to the "When `/do-it` is invoked, the cap is 10 passes per artifact" paragraph:
```
Pass caps, the floor, and early exit apply to the **heavy rung only** — light and medium do not loop.
```

Replace the `**Early exit (tier-dependent):**` paragraph with:
```
**Early exit (heavy only):** light and medium never loop, so early exit does not apply — they advance on a clean pass or escalate. On heavy, if passes 1 AND 2 both return zero impact-YES BLOCKER or SUBSTANTIVE findings, advance immediately — the judge never runs; the pass-2 scorecard prints `judge: early-exit`. EXCEPTION: when the run was floored at heavy by a hard trigger, there is no early exit — the full 3-pass floor always applies. COSMETIC findings do not block the exit (fix the trivial ones inline first).
```

- [ ] **Step 14: Sweep the remaining stray references.** Search and fix any leftover mode/tier vocabulary in prose not covered above (e.g. the `## When to Use` bullet at ~line 16 mentioning "run the full pipeline" is user-facing trigger text and stays; only fix internal mechanics references).

Run: `grep -niE "\bFAST\b|\bFULL mode\b|FULL-mode|\bSTANDARD\b|Tier:|tier |two-axis|Pipeline Modes" do-it/SKILL.md`
Expected: no matches referring to the old model. Any hit is either fixed to rung vocabulary or, if it is legitimately unrelated (e.g. "full plan" meaning a long plan, "full 3-pass floor"), left as-is. Judgement: the words `light`/`medium`/`heavy` should now be the only review-depth vocabulary.

- [ ] **Step 15: Full read-through consistency check.**

Read `do-it/SKILL.md` start to finish. Confirm: (a) the pipeline diagram, The Three Rungs, Reviewer Selection, scorecard, and pass-caps sections all agree that light=1 subagent pass / medium=1 fresheyes pass / heavy=loop; (b) nothing still promises a loop at light or medium; (c) the escalation ladder reads the same in every section that mentions it; (d) "heavy only" guards appear on Review Loop, Pass caps, judge, and early exit.

- [ ] **Step 16: Commit**

```bash
git add do-it/SKILL.md
git commit -m "do-it: replace FAST/FULL × tier with a light/medium/heavy rung dial + escalation-by-default"
```

---

### Task 3: Verify the judge prompt needs no change

**Files:**
- Inspect only: `do-it/references/judge-prompt.md`

**Interfaces:**
- Consumes: nothing. This task confirms the judge prompt is rung-agnostic (it categorizes finding severity and decides CONTINUE/STOP/SPLIT — concepts heavy reuses unchanged).

- [ ] **Step 1: Confirm the judge prompt contains no old-model vocabulary**

Run: `grep -niE "FAST|FULL|STANDARD|\btier\b|\bmode\b" do-it/references/judge-prompt.md`
Expected: no output. If the grep is clean, the file needs no edit — the judge is invoked only at heavy (per SKILL.md's "judge runs only at heavy"), and its severity taxonomy is unchanged.

- [ ] **Step 2: If (and only if) Step 1 printed matches**, edit those lines to remove the old vocabulary, then re-run the grep to confirm clean, and commit:
```bash
git add do-it/references/judge-prompt.md
git commit -m "do-it: drop stale mode/tier vocabulary from judge prompt"
```
If Step 1 was already clean, skip this step — no commit.

---

### Task 4: Sync the deploy copy and run the final end-to-end consistency gate

**Files:**
- Modify (sync target): `~/.claude/skills/do-it/**`

**Interfaces:**
- Consumes: the finished canonical `do-it/` tree from Tasks 1–3.

- [ ] **Step 1: Diff the deploy copy against canonical to see what will change**

Run: `diff -ru ~/.claude/skills/do-it ~/Projects/do-it-skill/do-it`
Expected: differences only in `SKILL.md` and `references/evaluator-rubric.md` (and `judge-prompt.md` only if Task 3 edited it). If unexpected files differ, stop and investigate — the deploy copy may have drifted independently.

- [ ] **Step 2: Sync canonical → deploy copy** (preserve the directory, do not delete unrelated files)

Run: `rsync -a --delete ~/Projects/do-it-skill/do-it/ ~/.claude/skills/do-it/`

Note: if `~/.claude/skills/do-it` is a symlink into Dropbox `claude-brain/skills/`, `rsync` follows it and writes the real target — that is correct. Do NOT attempt to write through the `~/.claude` path if an editor refuses; rsync to the resolved path is fine.

- [ ] **Step 3: Confirm the deploy copy matches canonical exactly**

Run: `diff -ru ~/.claude/skills/do-it ~/Projects/do-it-skill/do-it && echo "IN SYNC"`
Expected: `IN SYNC` (no diff output).

- [ ] **Step 4: Final vocabulary gate across the whole skill (canonical)**

Run: `grep -rniE "\bFAST\b|FULL-mode|FULL mode|\bSTANDARD\b|Tier:|two-axis|Pipeline Modes" ~/Projects/do-it-skill/do-it/`
Expected: no matches. This is the backstop that the old two-axis vocabulary is fully gone from every file.

- [ ] **Step 5: Confirm the three-rung vocabulary is present and consistent**

Run: `grep -rncE "\blight\b|\bmedium\b|\bheavy\b" ~/Projects/do-it-skill/do-it/SKILL.md`
Expected: a non-zero count. Spot-confirm by eye that "The Three Rungs", "Reviewer Selection (per rung)", and the manifest `Rung:` line all exist.

- [ ] **Step 6: Commit the run manifest for this build**

This plan's own run (if executed via `/do-it`) writes a manifest at `docs/superpowers/runs/2026-08-10-medium-tier-escalation.md`. Ensure it exists and is committed alongside. If this plan was executed manually (not via `/do-it`), skip the manifest requirement and note it in the final summary.

```bash
git add -A docs/superpowers/
git commit -m "do-it: run artifacts for the three-rung conversion" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Collapse two axes → one dial: Task 2 Steps 5, 11 (The Three Rungs, Reviewer Selection).
- Evaluator emits start-floor: Task 1; consumed in Task 2 Steps 3–4.
- Escalation around surviving finding severity, one-way, mechanical: Task 2 Step 4.
- Three rung definitions (light/medium/heavy): Task 2 Steps 5, 11; Global Constraints.
- Scorecard shows rung + escalation: Task 2 Steps 2, 12.
- Start floor for risky work (hard trigger → heavy; FC=2 / constraint → medium): Task 1 Steps 1; Task 2 Step 4.
- Unchanged sections (artifacts, manifest, Agency, watchdog, pre-commit, commit): protected by Global Constraints; not edited.
- Blast radius = 2 files + deploy sync: Tasks 1, 2, 4. `judge-prompt.md` unchanged: Task 3.
- Resume-not-supported-across-change: documented in the spec; no code change needed, so no task — the old manifests simply finish under old rules.

**2. Placeholder scan** — every edit step contains the exact replacement prose or an exact grep command with an expected result. No "TBD", no "handle appropriately", no "similar to above".

**3. Type consistency** — the field names `Start-floor`, `Hard-trigger`, `Scores`, `Lens`, `Reason` produced in Task 1 are the same names referenced in Task 2 Steps 3–4. The manifest key `Rung:` (Task 2 Step 2) matches the wording used in Task 2 Step 4's example line and Task 4 Step 5's check. The three rung words `light`/`medium`/`heavy` are lowercase everywhere. The "no early exit when hard-trigger-floored heavy" rule appears identically in Task 2 Steps 5, 11, and 13.

**Open item flagged for the human (not blocking):** the "medium floor for a constraint lens" rule (Task 1 Step 1, STEP 3) gives a `Lens:` a floor-raising role, whereas the old rubric said a lens never inflates depth. This is a deliberate change from the design's "don't break X → start floored at medium" example. If you'd rather a lens stay depth-neutral (enforced only as a review focus, never raising the floor), drop the second bullet of STEP 3 and the medium floor triggers on FAILURE COST=2 alone.
