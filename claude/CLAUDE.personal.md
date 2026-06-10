# Claude Global Instructions

## Response Style
- Raise conventions and explain why the convention is suitable or why we deviate.
- If a change is obscure or non-obvious, give a thorough but concise explanation including the relevant context.
- Be concise — prefer short answers unless a longer answer is needed for clarity.
- After completing a task, always list a few likely next steps for the user to choose for the agent to continue working on.

## Code
- Minimal comments — only include when necessary to explain obscure code or provide important context for future devs and agents to fully grasp the code.
- Placeholder/TODO code allowed.
- Prefer editing existing files over creating new ones.

## Git
- Never force push.
- Prefer new commits over amending.
- Stage specific files — avoid `git add -A` or `git add .`.

## Branch Plans
- When working on a branch, look for a plan associated with the branch in `$AGENT_PLANS` (resolve the env var to its actual path before reading). If unset, fallback to "~/.agent/plans". If that also does not exist, then the user probably doesn't have an agent plans directory. Just inform them and proceed.
- If no plan is found for the current branch, inform the user and ask if they would like one to be created.
- Plan contents vary by the type of work. Use discretion — include only what's useful, skip sections that don't apply.
- Common elements across all plans:
  - **Goal**: what this branch is trying to achieve, and why.
  - **Steps**: ordered breakdown of the work.
  - **Verification**: how we'll know it's done and correct.
  - **Links**: Jira ticket, related PRs, design docs, Slack threads, etc.
  - **Sessions**: a running log of every Claude session that worked on this branch. For each session record its session id, the working directory, and the machine name (hostname). Append a new entry whenever you start work in a new session.
- Type-specific additions (use only the relevant ones):
  - **Bug fix / investigation**: reproduction steps, hypotheses, root cause once found, regression risk.
  - **New feature**: requirements, design decisions and trade-offs, component/module breakdown, rollout considerations.
  - **Small adjustment**: usually just goal, steps, and verification — keep it short.
  - **Refactor**: scope and boundaries, before/after shape, behavior-preservation strategy, regression risk.
  - **Writing tests**: what's being covered, current coverage gaps, test cases to add, fixtures/mocks needed.
- Keep the plan a living document — update it as work progresses (e.g. add the root cause once a bug is diagnosed, record changes as we implement the solution).

## PR Creation
- Bias towards using these headings: Overview/Purpose, Problem, Solution, Verify, Links.
  - **Overview/Purpose**: high-level summary of what the PR aims to achieve.
  - **Problem**: the issue and its technical cause that this PR addresses.
  - **Solution**: the technical solution implemented in this PR.
  - **Verify**: steps to test that the solution works.
  - **Links**: relevant links, including the Jira ticket.
- Not all of these headings are necessary for every PR. Use discretion to select the necessary ones only.

## Testing
<!-- Add project-specific test commands and conventions here -->

## Tooling & Environment
<!-- Add preferred package managers, build tools, runtimes here -->

## Project Conventions
<!-- Add naming conventions, folder structure preferences here -->

## External Services
<!-- Add API conventions, auth patterns, service notes here -->

## Misc

- Don't use emdash (—), use hypen (-) instead
- Don't use arrows (→), use -> instead

