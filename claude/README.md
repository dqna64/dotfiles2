# Claude Code config

Per-machine Claude config files live here. Pick the one matching your
machine and symlink it into `~/.claude/`. Not automated in `install.sh` —
just run the appropriate command below by hand.

## Files

| File | For machine (`$DQNA64_MACHINE`) |
|---|---|
| `settings.mb_m1.json` | `MB_M1` (personal MacBook) |
| `settings.mb_cnv.json` | `MB_CNV` (Canva MacBook) |
| `settings.dvbx_cnv.json` | `DVBX1` / `DVBX2` / `DVBX3` (Canva devboxes) |
| `CLAUDE.mb_cnv.md` | `MB_CNV` global instructions |

## Symlink commands

```bash
# MB_M1
ln -sf "$DOTFILES_DIR/claude/settings.mb_m1.json" "$HOME/.claude/settings.json"

# MB_CNV
ln -sf "$DOTFILES_DIR/claude/settings.mb_cnv.json" "$HOME/.claude/settings.json"
ln -sf "$DOTFILES_DIR/claude/CLAUDE.mb_cnv.md"    "$HOME/.claude/CLAUDE.md"

# DVBX1 / DVBX2 / DVBX3 (Canva devboxes share the same config)
ln -sf "$DOTFILES_DIR/claude/settings.dvbx_cnv.json" "$HOME/.claude/settings.json"
```

`$DOTFILES_DIR` is set by `zsh/.zshenv` (defaults to `$HOME/dotfiles_dqna64`).

## Notes

- `ln -sf` overwrites the destination. Back up first if you have unsaved
  local changes: `mv ~/.claude/settings.json ~/.claude/settings.json.bak`.
- Editing the symlinked file in Claude Code edits the file in this repo,
  so changes are tracked automatically.
- To add a new machine's config: add a `settings.<machine_lower>.json`
  here, document it in the table above, and add a symlink command.
