# Migrating a machine to the overlay system

Per-machine checklist for moving an existing install of these dotfiles onto
the extension-repo ("overlay") layout. For agents as much as for Gordon: run
it on each machine once, tick items in the machine's `MACHINE_LOG_FILE` if one
exists, and leave nothing from the old layout behind.

Background: `docs/overlays.md`. Design history: plan `dotfiles-private-overlay.md`
in the agent plans repo.

## Checklist

1. **Pull the base** (`dotpull` or `git -C ~/dotfiles_dqna64 pull`).
2. **Edit `zsh/zsh-config`** (gitignored; diff it against `zsh-config.example`):
   - `DQNA64_MACHINE` is set.
   - `DOTFILES_OVERLAYS=( ... )` lists this machine's extension repos, one
     entry per line, absolute paths only (`$HOME/x`, never `~/x`).
   - Remove `WORK_BIN_PATH` and `CNV_WORK_BIN_PATH`. Nothing reads them; every
     repo's `bin/` is put on `PATH` by `.zshenv` instead.
   - Any other variable `zsh-config.example` no longer has can go.
3. **Run `install.sh`**: clones listed overlays, links the single files,
   runs each overlay's `install.d/*.sh`.
4. **Run `claude/sync-agent-links.sh`**: skills, output styles, rules, settings
   from every repo. Rules replace the old global `CLAUDE.md`: if
   `~/.claude/CLAUDE.md` or `~/.cursor/rules/claude.mdc` is reported as a
   dangling link, delete it by hand. Paste `claude/render-cursor-rules.sh`
   output into Cursor > Settings > Rules once.
5. **Run `git/git-setup.sh`** so overlay git/ssh templates are rendered and
   included.
6. **Clean up the old work scripts directory.** Before the overlays, work
   scripts lived in a separate clone (`$HOME/.local/bin/cnv`, the "Gordon's
   scripts" repo, on `PATH` via `WORK_BIN_PATH`). They now live in the work
   overlay's `bin/`. On each machine:
   - `git -C "$HOME/.local/bin/cnv" status` - if it has uncommitted or
     unpushed changes, move them into the overlay's `bin/` first (and push).
   - Confirm every script you use resolves into an overlay: `command -v finci`
     should print a path under the overlay, not under `.local/bin/cnv`.
   - Then delete the directory. Leaving it does no harm to `PATH` (nothing
     adds it any more) but it will drift and confuse the next agent.
7. **Verify with `dotdoctor`**: machine id, every repo present and clean, each
   single file linked to the resolver's pick, no collisions, no dangling
   links, no "not read by the base" paths you did not expect.
8. **Open a new shell** and spot-check: an alias from the overlay's
   `zsh/zshrc.d/`, a script from its `bin/`, `git config --get user.email`.

## Notes

- Machine ids are renamed to neutral names in a later step (plan, decision 9);
  until then keep the id this machine already has.
- Nothing in the overlay system edits `~/.gitconfig` or `~/.ssh/config`
  beyond the single include line `git-setup.sh` already manages.
