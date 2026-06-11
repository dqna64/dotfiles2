---
name: branch-changes
description: Show the changes on the current branch relative to its base (master, or main if master is absent), including uncommitted working-tree changes. Use when the user asks to "view changes on this branch", "what changed on this branch", or wants a summary of the branch's diff.
---

# View Changes on This Branch

Show everything this branch has changed relative to where it diverged from the base branch — committed, staged, and unstaged.

**Read-only: do not make any edits as part of this skill.** This skill only inspects and summarizes the diff. Do not modify files, stage, commit, or run any command that mutates the repo or working tree.

## Determine the base branch

Prefer the **remote-tracking** base (`origin/master`, then `origin/main`) since it's more likely to be up to date than a local copy; fall back to local `master`/`main`.

```bash
base=$(for ref in origin/master origin/main master main; do
  git rev-parse --verify --quiet "$ref" >/dev/null 2>&1 && { echo "$ref"; break; }
done)
```

If none of these exist, or the current branch *is* the base branch, say so and ask the user which range to diff.

## Show the changes

Diff from the merge-base to the working tree, so committed + staged + unstaged changes are all included:

```bash
mb=$(git merge-base "$base" HEAD)
git diff --stat -M "$mb"   # overview first
git diff -M "$mb"          # full diff (-M detects renames)
```

* Diffing against the **merge-base** (not the base tip) excludes unrelated commits that landed on the base since this branch diverged.
* Giving `git diff` a single revision compares it against the **working tree**, so uncommitted changes are part of the output.
* `-M` enables rename detection so moved files read as renames, not a large delete + add.
* **Read the whole diff** — do not stop at a truncated view. If the output is cut off, re-run scoped to the remaining files with `git diff -M "$mb" -- <path>...` until you have seen every change.

### Include untracked (new) files

`git diff` does **not** show untracked files, so brand-new files would be invisible. List them and read their contents directly, since there is no prior version to diff against:

```bash
git status --short          # untracked files appear with a "??" prefix
git ls-files --others --exclude-standard   # just the untracked paths
```

Read each untracked file in full and treat it as part of the branch's changes.

## Get more context

You may also want to read up on what files and directories changed to understand the shape of the branch:

```bash
git diff --name-status "$mb"   # which files changed and how (added/modified/deleted)
git diff --dirstat "$mb"       # which directories saw the most change
```

**Do not rely on commit messages** — the actual code changes are the source of truth. Commit messages can be stale, aspirational, or inaccurate; base your understanding on the diff itself.

## Check for an existing PR

See whether this branch already has a pull request, and if so read its state (description and comments) for additional context — but treat it the same as commit messages: helpful background, not the source of truth.

```bash
gh pr view --json title,body,state,url,comments   # current branch's PR, if any
```

If this fails for any reason (`gh` not installed, not authenticated, no PR, not a GitHub remote), **do not stall** — just briefly say you tried and move on with the diff.

## Summarize

Lead with the `--stat` overview, then walk the user through the notable changes grouped by intent (feature, fix, refactor), not just file-by-file. Keep it concise; surface anything surprising (large deletions, generated files, secrets).
