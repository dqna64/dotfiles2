# Machine logs - how it works

Usage (setting one up) is in `README.md` -> "Machine logs". Rules for changing
this feature are in `CLAUDE.md` -> "Machine logs".

The log lives wherever the user puts it - any path, any repo. These dotfiles
only need its path; nothing here creates, clones or validates it.

| Where | Does what |
|---|---|
| `zsh/zsh-config` | `MACHINE_LOG_FILE` - the log's path. Exported, so agents read it from the environment |
| `install.sh` | reports that path (or says it's unset). Creates nothing |
| `claude/CLAUDE.base.md` | the trigger: before/after a system-wide install, agents know to use the `machine-logs` skill. Symlinked to `~/.claude/CLAUDE.md` |
| `claude/skills/machine-logs/SKILL.md` | the detail: what counts as loggable, the entry format, the header for a new log, where to commit. Synced to `~/.claude/skills` by `claude/sync-agent-links.sh` |
