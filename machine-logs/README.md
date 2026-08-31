# machine-logs

Log of software installed **outside** this repo: brew formulae, manual installs,
toolchains, GUI app settings, OS permissions, PATH/env changes made elsewhere.
Answers "how did I install this" months later.

`machine.md.example` is a starting template. The log itself lives wherever you
put it; `MACHINE_LOG_FILE` in `zsh/zsh-config` names the path, and that one var
is what both `install.sh` and agents read.

## The parts

| Where | Does what |
|---|---|
| `zsh/zsh-config` | `MACHINE_LOG_FILE` - the log's path |
| `install.sh` | reports that path; creates nothing |
| `machine.md.example` | template for a new log |
| `claude/CLAUDE.base.md` | the global trigger: before/after a system-wide install, use the `machine-logs` skill. Symlinked to `~/.claude/CLAUDE.md`, so it applies in **every** repo |
| `claude/skills/machine-logs/` | the how: entry format, what counts, where to commit (synced to `~/.claude/skills`) |

## Setting it up

Copy `machine.md.example` to wherever you keep it, then in `zsh/zsh-config`:

```sh
export MACHINE_LOG_FILE="/path/to/log.md"
```
