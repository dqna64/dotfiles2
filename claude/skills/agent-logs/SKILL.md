---
name: agent-logs
description: Read this project's agent activity log - a shared record of what previous Claude and Cursor sessions changed in this directory, and why. Trigger this when starting or picking up work in a repo, when asking "what has been done here", "who changed this and why", "what was tried already", or before repeating work another session may have already attempted.
version: 1.0.0
---

# Agent logs

A per-project record of what agent sessions have actually changed here. Every
session working in a directory appends to the same file, so it accumulates
across sessions, across agents, and across machines.

**Logs live in `$AGENT_LOGS`** (resolve the env var before reading; fall back to
`~/.agent/logs` if it is unset), one file per project, named
`<project-basename>-<checksum>.jsonl`. Same convention as `branch-plans`: plans
are keyed by branch, logs by project. They are written automatically by hooks -
you never write to one by hand.

Don't construct the filename yourself; ask for it:

```sh
"${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/utils/agent-log/render.sh"      # this project
```

If there's no log, no session has changed anything in this project yet. Say so
and carry on; do not create one.

## Read it when

- You are starting or resuming work in a repo, before planning anything. It is
  the cheapest way to find out what state the project was left in.
- You are about to try an approach that might already have been tried. Entries
  record rejected approaches, which is often the most valuable part.
- The user asks what happened here, what changed recently, or why something is
  the way it is.
- Something looks half-finished. The log records unfinished threads and owed
  follow-ups that the code itself won't tell you about.

## How to read it

One JSON object per line, oldest first by `ts`. Render it rather than reading
raw when you want the whole thing:

```sh
render.sh            # this project's log
render.sh -n 20      # recent entries only
render.sh -a         # every project, merged - what agents did lately
```

The user has this aliased as `agentlog`.

For a targeted question, query the JSONL directly instead of reading all of it -
it grows without bound:

```sh
log="$(ls "${AGENT_LOGS:-$HOME/.agent/logs}"/"$(basename "$PWD")"-*.jsonl)"
jq -r 'select(.files[]? | test("api/")) | "\(.ts) \(.summary)"' "$log"
jq -r 'select(.branch == "my-branch") | .summary' "$log"
```

Fields: `ts`, `agent`, `session`, `turn`, `machine`, `project`, `branch`,
`commit`, `files`, `summary`.

## Trust it carefully

**Summaries are model-written and were never verified.** They are one agent's
account of its own turn, written without review. Treat an entry as a lead worth
checking, not as fact:

- Verify anything load-bearing against the code, the git history, or the tests
  before you act on it.
- Where the log and the code disagree, the code is right.
- Do not repeat a log claim to the user as established fact. Say where it came
  from ("a previous session recorded that...").

The mechanical fields - `files`, `commit`, `branch`, `ts` - are recorded
directly from the tool calls and are reliable. It's `summary` that is inferred.

## Do not write to it

Entries are appended by hooks, one per turn that changed something. Never add,
edit, or delete entries by hand, and never "tidy up" a log file: other sessions
may be appending to it at the same moment, and it is append-only by design so
that concurrent writers can't corrupt each other.

Logs live outside every repo, so they never dirty a project's `git status` and
can't be committed by accident - which matters, because entries are derived from
prompts and may quote work in progress.

## Related

`branch-plans` covers the *intended* work for a branch; this covers what
sessions *actually did* in a directory. When both exist, read the plan for
where the work is going and the log for where it has been.
