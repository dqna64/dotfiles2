# Status emojis in Gordon's notes (`notes.md` in project vaults)

Gordon's todo items are checkboxes. A colour square gives the item's status. Other emojis mark what a line is. Follow these rules when appending to or updating his notes, and stay surgical: match the surrounding lines.

## Status (colour squares, on open `- [ ]` items)
- 🟧 in progress; Gordon and possibly some agents are working on this presently. They may be multi-tasking between this and other in-progress tasks.
- 🟦 available for Gordon to pick up, but not demanding action: e.g. a self-review, an agent's spike or output to look at when he gets to it.
- 🟨 requires action from Gordon to move: implement, address review comments, merge, ask someone. Prefer 🟨 over 🟦 when something is waiting on him.
- 🟪 waiting on someone or something else: a reviewer, CI checks, an upstream PR.
- 🟫 stale: was being worked on, not actively now.

## When an item is done
- Tick it and drop its status emoji: `- [ ] 🟪 Awaiting review from a teammate` -> `- [x] Awaiting review from a teammate`.
- A merged PR gets a plain child line, not a checkbox: `- ✅ merged [[YYYY-MM-DD]]` (the date is a wikilink).

## Markers (what a line is, never ticked away)
- 🌀 the title of a discrete task: something that can eventually be completed. Its nested blocks may feature more specific info, status items and action items, as well as other sub-tasks, that constitute this task.
- 🐙 a GitHub PR: `- [ ] 🐙 [<number>](<url>) <short title>`, or `- 🐙 <url>`.
- 🌱 a branch: `` - 🌱 `<branch>` ``, then the worktree if it has one. If it branches off something other than main/master, say so: `` - 🌱 `<branch-b>` from `<branch-a>` ``.
- Whenever you note a PR (🐙), also note the branch it is for, as a 🌱 child line under it.
- 🐙 and 🌱 are only for PRs and branches Gordon is working on. Someone else's PR he is reviewing gets a plain
  link and a plain branch line, no marker emojis (Gordon, 2026-10-28).

## What not to write
- No CI or check statuses ("checks green on `<sha>`", "visual regression red"): CI state goes stale within
  hours and the PR page shows it. Note only what Gordon has to do or is waiting on (Gordon, 2026-11-16).
