# Agent activity logs - how it works

Usage (commands, enabling) is in `README.md` -> "Agent activity logs". Rules for
changing this feature are in `CLAUDE.md` -> "Agent activity logs".

## Where logs live

Always outside the project, resolved by `utils/agent-log/log-path.sh` - the
writer, `agentlog` and `install.sh` all use it, so they agree:

1. `$AGENT_LOGS/<project slug>/`.
2. else `~/.agent_dqna64/logs/<project slug>/`.

Unlike branch plans there is no in-repo tier: entries carry the hostname,
absolute paths and unreviewed summaries, which must not be committed.

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
| `claude/settings.*.json` | declares the hooks (`SessionStart`, `PostToolUse`, `Stop`) that call `agent-log.sh` |
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
