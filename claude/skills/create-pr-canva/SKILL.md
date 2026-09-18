---
name: create-pr-canva
description: Conventions and templates for pull requests in the Canva/canva repo - title, description, draft/precheck mechanics, stacked PR trains. Trigger this whenever creating a Canva/canva pull request (e.g. gh pr create) or drafting or revising its title/description. Optional argument: a template name (default, inspection) or a path to a template file.
version: 2.0.0
---

# PR Creation (Canva/canva)

Scope: PRs in `Canva/canva`. Identify the repo by the checkout's remote, never by its directory name (clones are called
`canva7`, `~/work/canva`, worktrees, etc.): `git remote get-url origin` matches `github.com[:/]Canva/canva`, or
`gh repo view --json nameWithOwner` says `Canva/canva`. Anything else is out of scope for this skill.

## 1. Pick the template

1. The argument, if given (`/create-pr-canva inspection`), names the template. Otherwise choose the most suitable one
   yourself from those available (project overrides plus the ones shipped here) by what the PR is - e.g. a spike that must
   never merge -> `inspection`; an ordinary change -> `default` - and say which you chose and why in one line.
2. An argument that is a path to an existing file (relative to the cwd or absolute) is used as the template directly.
   Otherwise resolve the name, first match wins:
   - `<git root of the cwd>/.claude/pr-templates/<name>.md` (`git rev-parse --show-toplevel`) - project override, e.g. a
     project vault's own variants. The cwd is the repo Claude was launched from, which may not be the canva checkout.
   - `templates/<name>.md` next to this file (`~/.claude/skills/create-pr-canva/templates/<name>.md`, symlinked from dotfiles).
3. A named template that is not found: say so, list the names available in both places, and use `default`.

## 2. Fill it

- Keep the headings. Each `<!-- ... -->` comment is guidance for its section: replace it with content, or delete the
  section when there is nothing non-inferable to say. `## Overview` always stays.
- The body carries only what a reviewer cannot infer from the diff: motivation (why now, what it enables), decisions and
  trade-offs invisible in the code, what is deliberately deferred and where, how later PRs depend on THIS one (never what
  they do), links (Jira, design, predecessor or superseded PR, Slack thread).
- No sections that narrate hunks or list the CI commands that ran. Complex hunks get inline PR comments instead. Code
  comments that merely restate the code are removed before review.
- Prose as paragraphs of one or two sentences separated by blank lines; bullets only for enumerations.
- Title: `<Project>: <what this PR does>` on one line, with the project's prefix (e.g. `Canva Jam: `,
  `Font Panel Redesign: `).

## 3. Open it

- `gh pr create --repo Canva/canva --draft --title ... --body-file ...`, base = `master` unless stacked on a parent branch.
- Drafts get no precheck: comment `@canva-ci-bot trigger canva-ci-precheck` right after creating. Poll `gh pr checks <n>`
  in a loop; `--watch` exits early on the OWNERS row, which stays red until an owner approves.
- Precheck red and the bot offers a fix: comment `@canva-ci-bot autofix`, wait, re-check. Otherwise fix locally and push.
- Translations are submitted only by an explicit `@canva-ci-bot trigger i18n-submit-for-translation`, once per PR, and only
  for strings the user has marked final.
- Precheck green: `gh pr ready <n>`. Never request reviewers - name the suggested reviewer to the user instead.

## 4. PR trains (applies to any template)

- A PR is part of a train when its base is another PR's branch or another PR is based on it. Whatever template was used,
  such a PR ends with a `## PR Train` section (after `## Links`): one line per PR in train order,
  `- https://github.com/canva/canva/pull/<n>`, this PR's own line ending ` <-- this PR`. Bare links, no titles.
- In `## Overview`, say how the later PRs depend on this one - never what they do.
- Whenever a train PR opens, closes, is retitled or reordered, rewrite the section on every PR in one go:
  `python3 ~/.claude/skills/create-pr-canva/scripts/update_train_section.py <numbers in train order>` (talks to
  `Canva/canva` through `gh --repo`, so it runs from any directory; `--dry-run` to preview).

## Templates shipped here

- `default` - blockquote (optional), `## Overview`, `## Links`.
- `inspection` - a draft spike PR that must never merge: do-not-merge banner, what to look at, relation to the train.
