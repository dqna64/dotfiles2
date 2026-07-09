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

`CLAUDE.base.md` holds the global instructions (response style, git/PR
conventions) and is the single source of truth. `CLAUDE.cnv.md` (Canva
machines) and `CLAUDE.personal.md` (personal machines) are repo-tracked
symlinks to it — machines link to the name matching their type, so if one
machine type ever needs different instructions, replace just that repo
symlink with a real file (start from a copy of `CLAUDE.base.md`) and no
machine has to re-link.

```bash
ln -sf "$DOTFILES_DIR/claude/CLAUDE.cnv.md" "$HOME/.claude/CLAUDE.md"      # Canva machines
ln -sf "$DOTFILES_DIR/claude/CLAUDE.personal.md" "$HOME/.claude/CLAUDE.md" # personal machines
```

## 4. (Optional) Agent skills + output styles

Two opt-in collections are kept in sync by one script:

- `skills/` — Agent Skills (each a `<skill-name>/SKILL.md`) shared between
  Claude Code and Cursor, linked into `~/.claude/skills` and `~/.cursor/skills`.
- `output-styles/` — named output style definitions for Claude Code, linked
  into `~/.claude/output-styles`. Switch styles in a session with `/config` →
  "Output style".

This directory is the single source of truth — `sync-agent-links.sh` symlinks
each item individually (never the whole dir), so editing one repo copy updates
every machine:

```bash
"$DOTFILES_DIR/claude/sync-agent-links.sh"
```

Run this once after install, then again whenever you want to sync new/deleted
skills or output styles from remote to your machine.
Pass `-n`/`--dry-run` to preview.

What it does and why it's safe:

- **Per-item symlinks** (not the whole dir), so skills / output styles you
  installed locally in those dirs stay untouched.
- **Idempotent**: links already correct are left alone; only new items get
  linked on a re-run.
- **Non-destructive**: a real file/dir or foreign symlink in the way is moved to
  `*.backup_dqna64.<timestamp>`, never overwritten.
- **Prunes** stale links (items you renamed/removed in the repo).
- **Edits/pulls need no re-run** — the symlinks point straight at the repo.

To add a new output style, drop a markdown file in `output-styles/` with the
frontmatter (re-run the sync to link it):

```markdown
---
name: Brief
description: Terse responses, no fluff
keep-coding-instructions: true
---

Respond as concisely as possible. No preamble, no summaries, no filler phrases.
```

To remove these links from a machine, run the reverse script (also invoked by
`uninstall.sh`):

```bash
"$DOTFILES_DIR/claude/unsync-agent-links.sh"
```

It drops only the links resolving back into the repo and restores anything
`sync-agent-links.sh` moved aside, leaving foreign items and the tool-owned
target dirs untouched. `-n`/`--dry-run` to preview.

## 5. (Optional) Cursor global rules

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
