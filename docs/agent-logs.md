# Agent activity logs - how it works

Usage (commands, enabling) is in `README.md` -> "Agent activity logs". Rules for
changing this feature are in `CLAUDE.md` -> "Agent activity logs".

## Where logs live

Resolved by `utils/agent-log/log-path.sh` - the writer, `agentlog` and
`install.sh` all use it, so they agree:

1. `<git root>/.agent_dqna64/logs/`, only if that directory already exists.
2. else `$AGENT_LOGS/<project slug>/`.
3. else `~/.agent_dqna64/logs/<project slug>/`.

Tier 1 is a per-project opt-in: the user creates the directory by hand
(`mkdir -p .agent_dqna64/logs`) in a repo that is private, and the logs are
then committed with the project like plans. Nothing creates it automatically,
and a repo that has only `.agent_dqna64/plans/` stays on tier 2/3. Entries
carry the hostname, absolute paths and unreviewed summaries, so never opt in a
public repo. `agentlog -a` lists only tiers 2/3 (the global root).

`<project slug>` is the absolute git-root path with `/` -> `-` (the scheme Claude
Code uses under `~/.claude/projects/`), so `canva5/web` and `canva7/web` never
collide. The directory is created on first write.

One JSONL file per agent session, `<start>_<machine>_<agent>_<session id>.jsonl`.
The id is the agent's own (`claude --resume <id>`), so no two writers ever share
a file. `render.sh` merges files on read and
sorts by timestamp.

## Moving parts

| File | Role |
|---|---|
| `claude/settings.json` (base, and any overlay's `settings[.<machine>].json`) | declares the hooks (`SessionStart`, `PostToolUse`, `Stop`) that call `agent-log.sh` |
| `utils/agent-log/agent-log.sh` | hook entry point: records the shape of each tool call, one line per event |
| `utils/agent-log/mutation-gate.sh` | decides whether a turn changed anything; read-only turns are dropped |
| `utils/agent-log/summarise.sh` | detached, at turn end: one-line model summary, credential redaction |
| `utils/agent-log/log-path.sh` | resolves the logs directory (above) |
| `utils/agent-log/render.sh` | the `agentlog` reader |
| `claude/skills/agent-logs/SKILL.md` | tells agents how to read the logs |

Cursor is covered by the same hook entries: it reads `~/.claude/settings.json`
as a third-party config source, and `agent-log.sh` detects the agent from the
payload (`cursor_version`).

## Trusting an entry

`summary` is the agent's own unverified account of its turn. `files`, `commit`,
`branch` and `ts` are recorded mechanically. Only the shape of tool calls is
captured (tool name, file path, command truncated to 400 chars), and credentials
are redacted before anything is written.
