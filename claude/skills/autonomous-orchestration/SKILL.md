---
name: autonomous-orchestration
description: Act as an orchestrator that accomplishes a broad, decomposable task by spawning and managing many subagents over an extended, largely unsupervised window (hours). Use when the user says things like "implement N PRs across the codebase", "audit and fix X across all modules", "run this large migration/sweep", or "you'll be unsupervised for a few hours, keep going" — a task too big for one context that splits into many independent units, each taken to a verifiable done-state. Provides a repeatable playbook: recon, plan-as-single-source-of-truth, decompose into isolated units, fan out via the Workflow tool with bounded concurrency (implement → review → fix), verify against ground truth, self-paced monitoring, drive to done. NOT for single-step tasks, quick edits, or work needing constant human input.
version: 1.0.0
---

# Autonomous Orchestration

You are the **orchestrator** for a large, decomposable task that will run mostly unsupervised for hours. You will not write most of the code yourself — you decompose the work, fan it out to subagents (via the **Workflow tool**), verify their output against ground truth, and drive every unit to a concrete done-state. Optimize for **throughput and correctness**, not speed. **Never hang and never silently stall** — if blocked, take a sensible non-destructive default and keep moving.

This skill is a methodology, not a script. Adapt every step to the task. The two bundled templates are starting points:
- `references/workflow-template.js` — a chunked **implement → review → fix** Workflow pipeline with bounded concurrency and structured outputs.
- `references/monitor.sh` — a background **poll-until-terminal** loop for long-running external state (CI, deploys, queues).

## Core principles (the hard-won ones)

1. **Recon before you orchestrate.** Spawning a fleet on wrong assumptions wastes hours. First establish ground truth yourself: machine capacity (`nproc`, free RAM, free disk), required tooling + auth present, the targets actually exist, and the conventions/patterns the work must match. Scout inline; fan out only once the shape is known.
2. **The plan file is the single source of truth.** Create it at the very start (the user's convention is `~/.agent/plans/<branch>.md` / `$AGENT_PLANS`; otherwise a `PLAN.md` in the work dir). Keep it continuously updated: scope + exit criteria, the work inventory, per-unit status, decisions and *why*, blockers, results (branch/PR/URLs), and CI state. It must be enough for a fresh session to resume from cold. Update it as you go, not at the end.
3. **Decompose into independent units with isolation.** Each unit must be parallelizable without conflicting with the others. For code, that means **one git worktree + branch per unit** (`git worktree add -b <branch> <path> <base>`). **Pre-create isolation sequentially** from the orchestrator to avoid git index races — then hand each subagent its ready-made worktree path.
4. **Fan out with the Workflow tool, not ad-hoc agents.** Structure: a one-time **shared-context "guide" agent** (reads the conventions/API once and returns a reusable brief handed to every implementer), then a **chunked pipeline** of `implement → review → fix` with **JSON-schema structured outputs** so returns are reliable data, not prose. See `references/workflow-template.js`.
5. **Bound concurrency to real capacity.** This is the #1 way these runs go wrong. Unbounded fan-out of heavy build/test gates oversubscribes the box (a real incident: load average hit **223 on 16 cores**, starving every gate). **Cap concurrent heavy units to ~3** (process in chunks), iterate on the *cheapest* check available, and run the **heavy final gate as few times as possible** (get green on the light check first, then run the heavy gate ~once).
6. **Verify; do not trust self-reports.** Subagents over-report success. After a unit claims done, re-check against ground truth (e.g. `gh pr view`, re-run the gate, inspect the diff). Distinguish **real failures** from **flaky / stale / environmental** ones (a sibling unit passing the same check, or a clean local re-run, is strong evidence of flakiness).
7. **Quality bar: multiple approaches, multiple review rounds.** For each unit, weigh more than one approach and pick the simplest, most idiomatic, convention-matching, complete one — record the choice. After implementation, run **≥2 review passes** (read-only) that check the diff against existing patterns; iterate until a pass finds nothing substantive.
8. **Self-paced monitoring without burning cycles.** For long external waits (CI 20–50 min, deploys), use a **background command that polls and exits on a terminal state** — the harness re-invokes you when it exits, so you don't poll in-context. Don't schedule short wakeups to watch harness-tracked work (you're notified automatically). See "Monitoring" below.
9. **Unblock yourself.** You're unsupervised — never ask, never hang. If a unit is truly stuck after genuine effort, capture what you have (push a branch, open a *draft* PR documenting the blocker), record it in the plan, and move to the next unit. Partial-but-recorded beats blocked-and-waiting.
10. **Know what is not yours to force.** Human/approval gates (code-owner approval, required reviews) and outward actions (pinging people, requesting reviews, publishing externally) are **not** things to bypass or trigger without explicit authorization. Surface them in the plan/report and leave them for the human. Re-running CI won't turn a human gate green.
11. **Report faithfully.** State what actually passed, what's flaky, what's blocked, and what needs a human. No rounding up.

## Guardrails (non-destructive defaults — apply to yourself and every subagent)

- Each subagent works **only inside its own worktree**; never touch the main checkout, another worktree, or a protected branch (`master`/`main`).
- **No** force-push, `git reset --hard`, rebase, branch deletion, `git add -A`/`git add .` (stage specific files), `git worktree remove` of others, `rm -rf`, or history rewriting. **New commits only — never amend.**
- Never modify generated/vendored files (codegen output, lockfiles you didn't intend, etc.).
- Stay within authorized destinations; never exfiltrate code to external services. Treat anything outward-facing (PR comments that notify people, review requests, publishing) as requiring explicit user authorization.
- Commit messages and PRs follow the repo's conventions; include any required trailers.

## The orchestration loop

**Step 0 — Scope & exit criteria.** Pin down what "done" means for one unit (a concrete, checkable gate — e.g. "the gate command passes and a ready-for-review PR exists") and for the whole task (how many units, which subset). If unsupervised, default sensibly and record the assumption in the plan rather than asking.

**Step 1 — Recon.** Capacity, tooling, auth, target existence, conventions. Write findings to the plan.

**Step 2 — Inventory & prioritize.** Enumerate the units of work; group by category; order by priority/complexity. This lives in the plan.

**Step 3 — Decompose & pre-create isolation.** One worktree+branch per unit, created sequentially.

**Step 4 — Fan out.** Run the Workflow: guide → chunked `implement → review → fix` (concurrency ≤ ~3). Each implementer: evaluate approaches → implement → iterate on the light check → pass the heavy gate once → commit specific files → push → open ready-for-review PR. Each reviewer (read-only) audits the diff against conventions; a fix stage resolves blocking findings.

**Step 5 — Verify.** Re-check every unit's claimed result against ground truth; re-run gates where the report is thin or implausible.

**Step 6 — Drive to done.** For external gates (CI), trigger if authorized, monitor with a background poll loop, and **iterate only on real failures** — classify flaky/stale/environmental and re-trigger appropriately (note: a comment-trigger and a push-trigger may run *different* pipelines; a no-op/empty commit is a valid non-destructive way to re-run push-gated checks). Update the plan with each result.

**Step 7 — Report.** Final summary + plan fully reflects reality, including anything left for the human (approvals, review requests).

## Workflow structure (see `references/workflow-template.js`)

```
phase('Guide');      const guide = await agent(GUIDE_PROMPT, {agentType:'Explore', schema?})
for (const group of chunk(UNITS, 3)) {            // bound concurrency
  await pipeline(group,
    u  => agent(implPrompt(u, guide), {schema: IMPL_SCHEMA, ...}).then(r => ({u, impl:r})),
    p  => agent(reviewPrompt(p),       {schema: REVIEW_SCHEMA, agentType:'Explore'}).then(r => ({...p, review:r})),
    p  => p.review.approved ? p : agent(fixPrompt(p), {schema: FIX_SCHEMA}).then(r => ({...p, fix:r}))
  )
}
```
- Use `schema:` (JSON Schema) on every `agent()` so results are validated data.
- `pipeline()` (no barrier) over `parallel()` unless a stage genuinely needs all prior results.
- Bake the **guardrails** and a relentless **"do not stop until the gate is green and the PR exists; draft-PR + recorded blocker only if truly stuck"** mandate into each implementer/fix prompt.
- Pre-create worktrees in the orchestrator (Bash), not inside the workflow.

## Monitoring long-running external state (see `references/monitor.sh`)

- Launch a background Bash loop that polls the external state and **exits on a terminal condition** (or a max-wall-clock cap). You'll be re-invoked when it exits — no in-context polling.
- Watch for **staleness**: a status pinned to an old build/run won't change until the right trigger fires. Track the build/run id and wait for a *new* one to reach terminal.
- Don't pick a 5-minute poll. Either stay under the prompt-cache window (≤ ~270s) for active polling, or commit to a long fallback (≥ ~1200s) for genuinely idle waits.

## Concurrency & resource discipline

- `MAX_CONCURRENT ≈ min(3, floor((cores-2)/4))` for heavy build/test units; lower if RAM/disk is tight. Process units in chunks of that size; `await` each chunk before the next.
- Fresh worktrees lack installed deps — install on first use. Many parallel worktrees can exhaust file-watch limits and poison shared daemons; prefer flags that avoid the shared daemon over changing system limits.
- For stale toolchain/cache errors that reproduce on untouched files, a clean restart of the build daemon usually clears them — that's environmental, not your change.

## Tuning knobs (set these per task, record in the plan)

`base branch` · `branch prefix` · `worktree base dir` · `MAX_CONCURRENT` · `scope (which/how many units)` · `light check command` · `heavy gate command` · `done-state definition` · `CI trigger allowed? request-review allowed?`

## Worked example

This skill was distilled from a run that: audited a feature area's telemetry coverage → built a prioritized gap inventory in a plan file → pre-created N worktrees off `master` → orchestrated `implement→review→fix` in chunks of 3 → got each unit's gate green and opened a ready-for-review PR → triggered/monitored CI and fixed only the real failures (a flaky check was cleared with an empty-commit re-trigger) → left code-owner approval to the human. ~18 PRs, fully unsupervised, with the plan as the durable record.
