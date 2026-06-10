---
name: finci
description: >-
  Formats, checks, commits, pushes, opens
  a PR, and triggers Canva CI for the current `web/` working tree: runs `taz f` +
  `pnpm lint:deps:fix`, runs `pnpm fin` (or `taz check`) in a fix-and-retry loop,
  creates a `gordonh-` branch if on master, pushes with upstream, opens a PR if
  missing, comments `@canva-ci-bot test` (or `merge`), and optionally requests a
  reviewer. Use when the user asks to finci, ship, format-and-check, or open/
  update a PR for the current Canva web changes.
disable-model-invocation: true
---

# finci

Drive the current `web/` working tree all the way to a CI-triggered PR. This is
the successor to `~/.local/bin/cnv/finci`; it follows that script's workflow but
adds branch creation, a fix-and-retry check loop, a real PR title/body, and the
corrected `req-review` invocation.

Use the Shell tool for every step.

## Options

These are off by default. Honor whichever the user requests:

| Request | Effect |
|---|---|
| `only <arg>` | Run `pnpm fin --only <arg>` instead of full `pnpm fin` (ignored with `use taz`) |
| `use taz` | Run `taz check` instead of `pnpm fin` |
| `skip checks` | Skip the test/check command entirely |
| `merge` | Comment `@canva-ci-bot merge` instead of `test` |
| `reviewer <user>` | After CI, request review from `<user>` via `req-review` |

## Workflow

```
- [ ] 1. Verify in web/; ensure a dedicated branch
- [ ] 2. Format: taz f + pnpm lint:deps:fix
- [ ] 3. Check loop: pnpm fin / taz check, fix + commit until clean
- [ ] 4. Commit remaining changes
- [ ] 5. Push (set upstream if needed)
- [ ] 6. Create PR if none exists
- [ ] 7. Comment @canva-ci-bot test (or merge)
- [ ] 8. Request reviewer (if specified)
```

### 1. Verify directory and branch

The script requires the working directory to be `web/` (because of `pnpm fin`).

```bash
basename "$PWD"        # must be "web"; cd into web/ if needed
git rev-parse --abbrev-ref HEAD
```

If on `master`/`main`, create a `gordonh-`-prefixed branch with a short
kebab-case slug from the change (ask if unclear):

```bash
git checkout -b gordonh-<slug>
```

If already on a non-`master` branch, keep it even without the prefix.

### 2. Format

```bash
taz f
pnpm lint:deps:fix
```

### 3. Check loop

Skip entirely if the user requested `skip checks`. Otherwise pick the command:

- default: `pnpm fin` (or `pnpm fin --only <arg>` if `only` was requested)
- `use taz`: `taz check`

Loop until it passes cleanly:

1. Run the check command.
2. If it passes and the tree has no new changes → exit the loop.
3. If it (or formatting) modified files, or it reports errors you can fix:
   fix the errors, then commit the staged result and re-run from step 1.

```bash
git add <changed paths>
git commit -m "taz f; pnpm lint:deps:fix"   # or a focused fix message
```

Guardrail: if the same error persists after a few fix attempts with no
progress, stop and report it to the user instead of looping forever.

### 4. Commit remaining changes

```bash
git status --porcelain
```

If non-empty, stage specific paths (never `git add -A` / `.`) and commit.

### 5. Push

Push when the local branch has commits not on the remote.

```bash
git fetch origin "$(git branch --show-current)" 2>/dev/null
git push -u origin HEAD          # add --force only if user requested force push
```

`-u` sets upstream when missing. Force push only on explicit request, never to
`master`.

### 6. Create PR if none exists

```bash
PR_BRANCH=$(git branch --show-current)
gh pr list --head "$PR_BRANCH" --repo "Canva/canva" --json number,url,baseRefName
```

If a PR exists, reuse it (capture its number). If none exists, create one with a
meaningful title/body (improvement over the script's generic "New PR"):

```bash
gh pr create --repo "Canva/canva" --title "<title>" --body "$(cat <<'EOF'
## Overview
<tl;dr>

## Problem
<the issue and its cause>

## Solution
<what this PR does>

## Verify
<how to test>

## Links
<Jira ticket / related PRs>
EOF
)"
```

Title: `[<JIRA-ID>] <description>` when a ticket is known, else
`<package>: <description>`. Base defaults to `master` unless the branch is
stacked on a parent.

### 7. Trigger CI

```bash
gh pr comment "$PR_BRANCH" --repo "Canva/canva" --body "@canva-ci-bot test"
```

Use `merge` instead of `test` if the user requested `merge`.

### 8. Request reviewer (if specified)

The on-PATH helper is `req-review --reviewer <user>` (it polls the PR up to ~1.5h
and adds the reviewer once CI passes).

```bash
req-review --reviewer <user>
```

This is long-running; consider running it in the background and reporting that
monitoring has started.

## Notes

- Default check is `pnpm fin` (web), matching the script; `use taz` swaps in
  `taz check`.
- Prefer new commits over amending; stage specific files; never force push
  unless explicitly asked.
- Repo is `Canva/canva`; commands assume you are inside `web/`.
- NEVER allow force push. If push rejects, tell the user and abort.
