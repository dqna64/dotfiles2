---
name: branch-plans
description: Locates, creates, and maintains the plan document associated with a git branch. Trigger this when starting or resuming work on a branch, when asked about a branch's plan, goal, or progress, or when finishing a chunk of work that the plan should record.
version: 1.0.0
---

# Branch Plans

- When working on a branch, look for a plan associated with the branch at the path "$AGENT_PLANS" (resolve the env var to its actual path before reading). If "$AGENT_PLANS" is unset or the path does not exist, fall back to "~/.agent/plans". If that path also does not exist, then just let the user know you can't find a plan, and proceed.
- If no plan is found for the current branch, inform the user and ask if they would like one to be created.
- Plan contents vary by the type of work. Use discretion - include only what's useful, skip sections that don't apply.
- Common elements across most plans:
  - **Goal**: what this branch is trying to achieve, and why.
  - **Steps**: ordered breakdown of the work.
  - **Verification**: how we'll know it's done and correct.
  - **Links**: Jira ticket, related PRs, design docs, Slack threads, etc.
  - **Sessions**: a running log of every Claude and Cursor session that referenced this plan (read it or worked against it). For each session record its session id, the agent (Claude or Cursor), the working directory it ran in, and the machine name (hostname). Append a new entry whenever a session first references the plan.
- Type-specific additions (use only the relevant ones):
  - **Bug fix / investigation**: reproduction steps, hypotheses, root cause once found, regression risk.
  - **New feature**: requirements, design decisions and trade-offs, component/module breakdown, rollout considerations.
  - **Small adjustment**: usually just goal, steps, and verification — keep it short.
  - **Refactor**: scope and boundaries, before/after shape, behavior-preservation strategy, regression risk.
  - **Writing tests**: what's being covered, current coverage gaps, test cases to add, fixtures/mocks needed.
- Keep the plan a living document — update it as work progresses (e.g. add the root cause once a bug is diagnosed, record changes as we implement the solution).
