# Claude Code config

Claude config files live here. Nothing is symlinked automatically — pick
the one you want and symlink it into `~/.claude/`.

## 1. Pick a settings file

| File | For |
|---|---|
| `settings.mb_m1.json` | Personal: `sonnet[1m]`, no telemetry. |
| `settings.mb_cnv.json` | Canva laptop: otter telemetry + full hooks. |
| `settings.dvbx_cnv.json` | Canva devbox: otter telemetry + lighter hooks. |

## 2. Symlink it

```bash
ln -sf "$DOTFILES_DIR/claude/settings.mb_m1.json" "$HOME/.claude/settings.json"
```

Swap in whichever file from the table you picked.

## 3. (Optional) Global instructions

`CLAUDE.mb_cnv.md` holds global instructions (response style, git/PR
conventions). Symlink it if you want them:

```bash
ln -sf "$DOTFILES_DIR/claude/CLAUDE.mb_cnv.md" "$HOME/.claude/CLAUDE.md"
```

---

- `$DOTFILES_DIR` is set by `zsh/.zshenv` (defaults to `$HOME/dotfiles_dqna64`).
- `ln -sf` overwrites the target — back up first if you have local changes.
- Editing the symlinked file edits the repo copy, so changes are tracked.
- New config? Drop a `settings.<suffix>.json` here and add a table row.
