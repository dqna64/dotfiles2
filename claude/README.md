# Claude Code / Cursor config

Everything here is linked into `~/.claude` (and skills into `~/.cursor`) by one
re-runnable command, from this repo and from every extension repo (overlay)
listed in `zsh/zsh-config`:

```bash
"$DOTFILES_DIR/claude/sync-agent-links.sh"          # -n / --dry-run to preview
```

| In each repo | Linked to | Kind |
|---|---|---|
| `claude/skills/<name>/` | `~/.claude/skills/<name>`, `~/.cursor/skills/<name>` | collection |
| `claude/output-styles/*.md` | `~/.claude/output-styles/` | collection |
| `claude/rules/*.md` | `~/.claude/rules/` | collection |
| `claude/settings.json`, `claude/settings.<machine>.json` | `~/.claude/settings.json` | single file |

**Collections** are additive: every repo's items are linked. The same item name
in two repos is an error and nothing is linked until it is renamed.

**Rules replace a global `CLAUDE.md`.** Claude Code loads every
`~/.claude/rules/*.md` in every session, before project rules, with no approval
prompt. Each file covers one topic (`response-style.md`, `code-and-git.md`,
`skills.md`); an overlay adds files for its own domain and never restates a
base topic, because rule files concatenate and cannot override each other.
`~/.claude/CLAUDE.md` is not used; if one exists (your own file, or an old link
to the deleted `CLAUDE.*.md` files) `sync-agent-links.sh` only says so and
leaves it alone. `unsync-agent-links.sh` removes it on uninstall if it points
into a dotfiles repo.

**Settings** is one file, so one repo wins: `claude/settings.<machine>.json` in
any repo (`<machine>` = `DQNA64_MACHINE` lowercased), else `claude/settings.json`
in an overlay, else `claude/settings.json` here. The base `claude/settings.json`
holds the generic permissions and the agent-log hooks, so a machine with no
`settings.<machine>.json` anywhere works with zero configuration.

**Cursor.** Skills are shared through `~/.cursor/skills`. Cursor has no global
rules directory (User Rules live only in Cursor > Settings > Rules), so paste
the output of this once per machine, and again after rules change:

```bash
"$DOTFILES_DIR/claude/render-cursor-rules.sh"        # | pbcopy on macOS
```

The sync is idempotent, per-item (foreign items in those directories are left
alone), non-destructive (an existing item with the same name is skipped with a
warning, never replaced or backed up: delete or move it out, then re-run), and
prunes links whose repo item was removed or whose repo is no longer listed. Edits and `git pull` need no re-run: the links
point at the repos. To remove the links: `claude/unsync-agent-links.sh`
(also run by `uninstall.sh`).

To add an output style, drop a markdown file in `output-styles/` with frontmatter
(`name`, `description`, `keep-coding-instructions`) and re-run the sync. To add a
rule, drop a topic file in `rules/`. To add a skill, a `<name>/SKILL.md` directory.
Machine-independent, work-specific or private items belong in an overlay repo,
not here (see the root README, "Extension repos").
