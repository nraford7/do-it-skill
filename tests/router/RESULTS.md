# Router + escalation test results (2026-09-30)

## RED: old start-floor evaluator (do-it/references/evaluator-rubric.md)
s1 light · s2 medium · s3 medium · s4 light · s5 heavy · s6 medium · s7 light
Mismatches vs /do-it-auto design: s1, s4, s7 (no DIRECT path), s5 (heavy; NR wants hard triggers to start medium).

## GREEN v1 (router-rubric.md first draft)
s1 MEDIUM (wrong: read brief requirements such as "stdlib only" as constraints) · s2 MEDIUM (right route; wrongly fired the destructive trigger for the tool's own --delete) · s3 MEDIUM · s4 DIRECT · s5 MEDIUM · s6 MEDIUM · s7 DIRECT

## REFACTOR
Constraint = protect EXISTING behavior; brief requirements for new code are not constraints.
Destructive trigger = the change itself mutates real data; a tool whose features delete files is scored under FAILURE COST.

## GREEN v2
s1 DIRECT (2/2 reps) · s2 MEDIUM (FC=2) · s3 MEDIUM (FC=2, NOV=2) · s4 DIRECT · s5 MEDIUM (auth trigger) · s6 MEDIUM (lens + FC=2) · s7 DIRECT. 7/7.

## DIRECT escalation pressure test (tests/router/escalation.md)
Control (no skill): both E1 (2 failed fixes, late, "attempt 3 will work") and E2 (6-line change in a second shared module) stopped and ASKED THE USER: correct instinct, but stalls an unattended run.
Treatment (do-it-auto SKILL.md): both escalated DIRECT -> MEDIUM autonomously, citing the 2-attempt and module-count rules and the rationalization table; code kept as input.
