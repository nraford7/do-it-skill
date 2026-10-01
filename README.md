# do-it — Autonomous Build Pipeline Skill

A [Claude Code](https://claude.com/claude-code) skill for single-shot, end-to-end builds. You give one instruction; the pipeline drives spec → plan → build → review → commit → push without asking permission at every gate.

## What it does

```
[0] Clarify (only if blocking)
[R] Router (fresh subagent, fixed rubric) → DIRECT | MEDIUM
      DIRECT: implement → tests → verify → commit + push (async independent review after push)
              escalates to MEDIUM if the change spreads, tests fail twice, or a new risk appears
      MEDIUM: [1] spec → [2] plan → [3] Agency execution → [4] one independent review per artifact
              → [5] verification gate → commit + push
              escalates to HEAVY (full review loop) only if a review leaves a serious finding unfixed
```

Key ideas:

- **Size routing.** Small, contained, low-loss work goes straight to the model. Everything else gets spec, plan, execution and one independent-model review. The executor never picks its own route.
- **Heavy only on evidence.** The full review loop (with a diminishing-returns judge) runs only when the medium pass leaves a serious problem unfixed.
- **Mandatory artifacts on the pipeline route.** Spec, plan and run manifest in git. No rationalized skips.
- **Watchdog.** `scripts/watchdog.sh` supervises long external review runs (stall detection, hard ceiling), tunable via `FE_*` env vars.

**Why:** a 2026-09-30 eval of 45 blinded, judged builds found that current models meet a clear brief without any process; process buys robustness on unstated edge cases, and only where a miss is costly. A same-model review pass added almost nothing; one independent-model pass after a spec and plan carried the gain.

## Contents

| Path | Purpose |
|---|---|
| `do-it/SKILL.md` | The skill: router, routes, escalation, artifact rules |
| `do-it/references/router-rubric.md` | Router prompt (DIRECT vs MEDIUM) |
| `do-it/references/judge-prompt.md` | Diminishing-returns judge prompt (heavy rung) |
| `do-it/scripts/watchdog.sh` | Supervisor for long-running review subprocesses |
| `tests/router/` | Router and escalation test scenarios and results |
| `archive/do-it-v2026-08-25/` | Previous version (fixed light/medium/heavy dial) |

## Install

Copy the `do-it/` directory into your Claude Code skills folder:

```sh
cp -R do-it ~/.claude/skills/do-it
```

Then trigger it with `/do-it <instruction>` (or "just build it", "do it end-to-end").

> The skill references companion tooling from my setup ([superpowers](https://github.com/obra/superpowers) skills, a `fresheyes` second-model reviewer, and an [Agency](https://github.com/agentbureau/agency) execution layer). It degrades gracefully without them, but the review loops assume an independent reviewer is available.

## License

MIT
