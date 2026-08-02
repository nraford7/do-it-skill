# do-it — Autonomous Build Pipeline Skill

A [Claude Code](https://claude.com/claude-code) skill for single-shot, end-to-end builds. You give one instruction; the pipeline drives spec → plan → build → review → commit → push without asking permission at every gate.

## What it does

```
[0] Clarify (only if blocking)
[1] Spec draft   → review loop (tiered: LIGHT / STANDARD / HEAVY)
[2] Plan         → review loop
[3] Execution    (no permission asks)
[4] Post-build review
[5] Verification gate → commit + push
```

Key ideas:

- **Review-tier evaluator** — a rubric scores each task and picks how heavy the review stack should be (`FAST` mode skips the loops entirely for low-risk work).
- **Diminishing-returns judge** — an independent judge decides CONTINUE / STOP / SPLIT after each review pass, so review effort stops when it stops paying.
- **Mandatory artifacts** — every run leaves a spec, a plan, and a run manifest in git. No rationalized skips.
- **Watchdog** — `scripts/watchdog.sh` supervises long external review runs (stall detection, hard ceiling), tunable via `FE_*` env vars.

## Contents

| Path | Purpose |
|---|---|
| `do-it/SKILL.md` | The skill itself — pipeline, modes, artifact rules |
| `do-it/references/evaluator-rubric.md` | Review-tier scoring rubric |
| `do-it/references/judge-prompt.md` | Diminishing-returns judge prompt |
| `do-it/scripts/watchdog.sh` | Supervisor for long-running review subprocesses |

## Install

Copy the `do-it/` directory into your Claude Code skills folder:

```sh
cp -R do-it ~/.claude/skills/do-it
```

Then trigger it with `/do-it <instruction>` (or "just build it", "do it end-to-end").

> The skill references companion tooling from my setup ([superpowers](https://github.com/obra/superpowers) skills, a `fresheyes` second-model reviewer, and an [Agency](https://github.com/agentbureau/agency) execution layer). It degrades gracefully without them, but the review loops assume an independent reviewer is available.

## License

MIT
