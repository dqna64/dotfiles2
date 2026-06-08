# Claude Code config

Claude config files live here. Nothing is symlinked automatically — pick
the one you want and symlink it into `~/.claude/`.

## 1. Pick a settings file

See the `settings.*.json` files in this directory and pick the one for your
environment (e.g. `settings.mb_m1.json`).

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

## 4. (Optional) Output styles

`output-styles/` contains named output style definitions. Switch styles
inside a session with `/config` → "Output style". Symlink the whole
directory so Claude Code picks them up:

```bash
ln -sf "$DOTFILES_DIR/claude/output-styles" "$HOME/.claude/output-styles"
```

To add a new style, drop a markdown file in `output-styles/` with the
frontmatter:

```markdown
---
name: Brief
description: Terse responses, no fluff
keep-coding-instructions: true
---

Respond as concisely as possible. No preamble, no summaries, no filler phrases.
```

---

- `$DOTFILES_DIR` is set by `zsh/.zshenv` (defaults to `$HOME/dotfiles_dqna64`).
- `ln -sf` overwrites the target — back up first if you have local changes.
- Editing the symlinked file edits the repo copy, so changes are tracked.
- New config? Drop a `settings.<suffix>.json` here.
