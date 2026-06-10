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

`CLAUDE.cnv.md` holds global instructions (response style, git/PR
conventions). Symlink it if you want them:

```bash
ln -sf "$DOTFILES_DIR/claude/CLAUDE.cnv.md" "$HOME/.claude/CLAUDE.md"
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
## 5. (Optional) Agent skills

`skills/` holds Agent Skills (each a `<skill-name>/SKILL.md`) shared between
Claude Code and Cursor. This is the single source of truth — symlink each
skill into both agents' skill dirs so editing one repo copy updates both:

```bash
mkdir -p "$HOME/.claude/skills" "$HOME/.cursor/skills"
for skill in "$DOTFILES_DIR"/claude/skills/*/; do
  name=$(basename "$skill")
  ln -sn "$skill" "$HOME/.claude/skills/$name"
  ln -sn "$skill" "$HOME/.cursor/skills/$name"
done
```

Per-skill symlinks (not the whole dir) so locally-installed skills in those
locations stay untouched. Existing entries are left alone (the loop
just prints "File exists" and moves on).

## 6. (Optional) Cursor global rules

Cursor reads global `.mdc` rule files from `~/.cursor/rules/`. Symlink your
chosen `CLAUDE.*.md`:

```bash
mkdir -p "$HOME/.cursor/rules"
ln -sf "$DOTFILES_DIR/claude/CLAUDE.cnv.md" "$HOME/.cursor/rules/claude.mdc"
```

Notes:

- No YAML frontmatter is needed (or wanted) for global `~/.cursor/rules/*.mdc`
  files
- If a future Cursor version stops honoring global `.mdc` loading from `~/.cursor/rules/`,
  fall back to pasting the file's contents into Settings → Rules → User Rules,
  or to a project-level `.cursor/rules/` rule.

---

- `$DOTFILES_DIR` is set by `zsh/.zshenv` (defaults to `$HOME/dotfiles_dqna64`).
- `ln -sf` overwrites the target — back up first if you have local changes.
- Editing the symlinked file edits the repo copy, so changes are tracked.
- New config? Drop a `settings.<suffix>.json` here.
