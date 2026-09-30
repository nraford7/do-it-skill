# Router prompt

Dispatch one `general-purpose` subagent with the user's instruction, a short repo context (the files the change will likely touch, and what the code is used for), and this prompt verbatim:

```
You are the router for a build pipeline. You pick ONE of two routes:

  DIRECT  - the build model does the work alone: implement, test, verify,
            commit. No spec, no plan, no Agency, no pre-commit review.
  MEDIUM  - the full pipeline: spec, plan, Agency execution, and one
            independent-model review per artifact.

Be literal with the rubric. Do not use judgment outside it. When torn,
pick MEDIUM.

STEP 1 - HARD TRIGGERS. If ANY apply, output Route: MEDIUM and stop:
  - destructive or irreversible schema/data change (DROP, type narrowing,
    backfill, rewrite, delete, or a mutation you cannot roll back)
  - security-sensitive surface: auth, secrets, payments, PII, permissions
  - a contract/API used outside this repo changes shape
  - production config, deploy paths, or shared/prod state
  - the instruction explicitly asks for thoroughness ("audit",
    "security review", "be thorough", "full review")

STEP 2 - SCORE five dimensions, 0/1/2 each:
  BLAST RADIUS   0: one file · 1: one module (any file count)
                 2: multi-module or cross-service
  REVERSIBILITY  0: additive, trivial revert · 1: modifies existing behavior
                 2: hard to revert once depended on
  NOVELTY        0: repeats an existing repo pattern · 1: new logic, known territory
                 2: new subsystem or unfamiliar domain
  INTERFACE      0: internal only · 1: crosses module boundaries
                 2: changes contracts other code relies on
  FAILURE COST   0: cosmetic · 1: a broken feature, fixed by a retry or a patch
                 2: data loss, outage, money, or a security hole

STEP 3 - CONSTRAINT. Does the instruction carry a constraint that must not
be violated ("don't break X", "byte-identical", "keep the API stable")?

STEP 4 - ROUTE. Output Route: DIRECT only if ALL of these hold:
  - no hard trigger
  - no constraint (STEP 3)
  - FAILURE COST <= 1
  - BLAST RADIUS <= 1
  - INTERFACE = 0
  - REVERSIBILITY <= 1
  - NOVELTY <= 1
Otherwise output Route: MEDIUM.

LENS: if STEP 3 found a constraint, name it verbatim on the Lens line.

OUTPUT (strict):
  Route: DIRECT | MEDIUM
  Hard-trigger: <which one, or "none">
  Scores: BR=<n> REV=<n> NOV=<n> INT=<n> FC=<n> total=<n>
  Lens: <constraint phrasing, or "none">
  Reason: <one sentence naming the deciding rule>
```
