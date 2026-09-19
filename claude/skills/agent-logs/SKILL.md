---
name: agent-logs
description: Read this project's agent activity log - a shared record of what previous Claude and Cursor sessions changed in this directory, and why. Trigger this when starting or picking up work in a repo, when asking "what has been done here", "who changed this and why", "what was tried already", or before repeating work another session may have already attempted.
version: 1.0.0
---

# Agent logs

A per-project record of what agent sessions have actually changed here. Every
session working in a directory writes its own file into the project's logs
directory; read together they accumulate across sessions, agents and machines.

Find the logs directory using the same hierarchy as `branch-plans` - the first
of these that exists:

1. `<git root of the cwd>/.agent_dqna64/logs/` (`git rev-parse --show-toplevel`) - used whenever the
   project has a `.agent_dqna64/` directory; committed with the project, like plans.
2. `$AGENT_LOGS/<project slug>/` (resolve the env var first; slug = git-root path with `/` -> `-`).
3. `~/.agent/logs/<project slug>/`.

If the directory is missing or empty, no session has changed anything in this project yet. Say so and
carry on; do not create one. Inside it, one file per agent session:
`<start>_<machine>_<agent>_<session id>.jsonl` - the session id is the agent's own, so `claude --resume <id>`
reopens the session a file came from. Files are written automatically by hooks - never write one by hand.

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

One JSON object per line per file; the renderer merges every session file and
sorts by `ts`. Render it rather than reading raw when you want the whole thing:

```sh
render.sh            # this project, all sessions merged
render.sh -n 20      # recent entries only
render.sh -s 097beb  # one session, by id prefix
render.sh -a         # every project under the global logs root, merged
```

The user has this aliased as `agentlog`.

For a targeted question, query the JSONL directly instead of reading all of it -
it grows without bound:

```sh
. "${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/utils/agent-log/log-path.sh"
logs="$(agent_logs_dir "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
cat "$logs"/*.jsonl | jq -r 'select(.files[]? | test("api/")) | "\(.ts) \(.summary)"'
cat "$logs"/*.jsonl | jq -r 'select(.branch == "my-branch") | .summary'
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

Repo-local logs are committed with the project, exactly like `.agent_dqna64/plans/`:
never add them to a project or global gitignore. A project that wants its log
kept out of the repo uses the `$AGENT_LOGS` fallback. Commit the log file along
with the work it describes; it is append-only, so commits never rewrite earlier lines.

## Related

`branch-plans` covers the *intended* work for a branch; this covers what
sessions *actually did* in a directory. When both exist, read the plan for
where the work is going and the log for where it has been.
