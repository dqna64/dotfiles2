---
name: branch-plans
description: Locates, creates, and maintains the plan document associated with a git branch. Trigger this when starting or resuming work on a branch, when asked about a branch's plan, goal, or progress, or when finishing a chunk of work that the plan should record.
version: 1.0.0
---

# Branch Plans

- Find the plans directory - the first of these that exists:
  1. `<git root of the cwd>/.agent_dqna64/plans/` (`git rev-parse --show-toplevel`). A project vault keeps the plans for branches of other repos (e.g. canva7 worktrees reached by absolute path), so this is the repo Claude was launched from, not the repo the branch lives in.
  2. `$AGENT_PLANS` (resolve the env var to its actual path before reading).
  3. `~/.agent/plans`.
  If none exists, let the user know you can't find a plans directory, and proceed.
  `.agent_dqna64/plans/` is part of the project and is committed with it - never add it to a project or global
  gitignore. A user who wants plans kept out of a repo uses the `$AGENT_PLANS` fallback instead.
- Find the branch's plan inside it - the first match wins:
  1. A `README.md` index row for the branch (table with `| branch | plan file |` columns).
  2. A file named after the branch (`<branch>.md`, with or without the `<user>/` prefix, `/` written as `-`).
  3. Any `*.md` whose first 15 lines name the branch (vault plans are named by topic and date and carry a branch-facts header; prefer the file that lists it as its current branch over one that merely mentions it).
- If no plan is found for the current branch, inform the user and ask if they would like one to be created - in the plans directory found above, named `<topic>-<YYYY-MM-DD>.md` when the directory uses that convention, else `<branch>.md`.
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
  - **Small adjustment**: usually just goal, steps, and verification - keep it short.
  - **Refactor**: scope and boundaries, before/after shape, behavior-preservation strategy, regression risk.
  - **Writing tests**: what's being covered, current coverage gaps, test cases to add, fixtures/mocks needed.
- Keep the plan a living document - update it as work progresses (e.g. add the root cause once a bug is diagnosed, record changes as we implement the solution).
