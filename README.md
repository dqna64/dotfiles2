# dotfiles

Gordon's cross-machine dotfiles. Includes shared and machine-specific
configurations for tools like zsh, git, ssh, vscode, claude, tmux, etc

The install script will create symlinks on your machine for files that are
consumed by tools. Examples:
- `~/.zshrc`
- `~/.gitignore_global`
- `~/.config/karabiner/karabiner.json`
- `~/.tmux.conf`
So changes to the original files for those symlinks will take effect
without re-running the installer.

`.zshrc` will source lots of other dotfiles, so remember remember to
re-source `.zshrc` after making changes to those files.

## First-time setup on a new machine

1. **Bootstrap.** Clones this repo to `$HOME/dotfiles_dqna64`, installs
   oh-my-zsh + plugins, and symlinks the zsh / karabiner / tmux / yabai
   entry points. Existing files are backed up to
   `<file>.backup_dqna64.<timestamp>`.

   ```bash
   curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | bash
   ```

   Or, if you'd rather inspect first, clone the repo manually and run
   `install.sh` from it:

   ```bash
   git clone https://github.com/dqna64/dotfiles2.git ~/dotfiles_dqna64
   ~/dotfiles_dqna64/install.sh
   ```

   **Custom install path.** The default is `$HOME/dotfiles_dqna64`, but
   you can install anywhere by setting the `DOTFILES_DIR=<path>` env var:

   ```bash
   # curl form — put the var before the receiving `bash`:
   curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | DOTFILES_DIR=~/code/dotfiles bash


   `install.sh` clones into that path and symlinks `~/.zshenv` to it;
   `zsh/.zshenv` auto-derives `DOTFILES_DIR` from that symlink on every
   shell startup, so no shell-rc edit is needed to remember the
   non-default location. `.zshrc` warns at startup if `DOTFILES_DIR`
   doesn't resolve to a real clone.

2. **Edit `zsh/zsh-config`** (bootstrapped from `zsh-config.example` by
   `install.sh`). Set `DQNA64_MACHINE` to one of `MB_M1`, `MB_CNV`,
   `DVBX1`, … and toggle the per-machine flags (`ENABLE_YABAI_DQNA64`,
   `ZSH_THEME_MY`, etc.). This file is gitignored.

3. **(Optional) Configure git identities + SSH host aliases.** Edit
   `git/git-identity` with your real values (it's bootstrapped from
   `git-identity.example`, also gitignored), then run
   `./git/git-setup.sh`. The script renders:

   - `git/dqna64-dotfiles.gitconfig` — gitconfig snippet (gitignored,
     next to its template)
   - `~/.gitignore_global` — symlink to `git/.gitignore_global`
   - `ssh/dqna64-dotfiles.conf` — SSH host-alias snippet (gitignored,
     next to its template)

   `~/.gitconfig` and `~/.ssh/config` are user-owned and never modified
   by the script. To pull in the rendered files, `git-setup.sh` prints
   the exact one-time blocks to add:

   ```ini
   # in ~/.gitconfig (path printed by git-setup.sh based on $DOTFILES_DIR)
   [include]
       path = ~/dotfiles_dqna64/git/dqna64-dotfiles.gitconfig
   ```

   ```
   # in ~/.ssh/config (path printed by git-setup.sh based on $DOTFILES_DIR)
   Include ~/dotfiles_dqna64/ssh/dqna64-dotfiles.conf
   ```

4. **(Optional) Symlink Claude / VS Code / Cursor config** following the
   per-tool instructions in `claude/README.md` and `vscode/README.md`.

## Aliases

`zsh/.zshrc` sources every `*.zsh` in `aliases/` on all machines, plus any
per-machine `aliases.<suffix>/` dirs. A `case` block maps `$DQNA64_MACHINE`
to a list of suffixes, so a machine can load several dirs and machines can
share one (e.g. `DVBX1`/`DVBX2`/`DVBX3` → `(dvbx_cnv)`). Suffixes are
arbitrary; missing dirs are skipped. Just drop a `.zsh` file in a dir — no
registration needed.

## Adding a new machine

1. Pick an identifier (e.g. `MB_2026`).
2. For per-machine aliases, add a branch to the `case` block in `zsh/.zshrc`
   (e.g. `MB_2026) MACHINE_ALIAS_SUFFIXES=(mb_2026) ;;`) and create the matching
   `aliases.<suffix>/` dir(s). Suffixes use `_` not `-`. For PATH/env
   additions, add a branch in `zsh/.zshenv` (e.g. the `DVBX*` block).
3. Optionally drop `zsh/.zshrc.<machine-with-hyphens>` (`mb-m1`, `mb-cnv`,
   `dvbx1`, …) for a machine-specific zshrc. **No registration needed** —
   `zsh/.zshrc` auto-sources by the derived filename (`-` not `_`).

## Gitignored, per-machine files (do not commit)

- `zsh/zsh-config` — machine identifier + flags.
- `git/git-identity` — real name/email/SSH key paths/SSH host alias labels.
- `*.backup_dqna64.*` — created by `install.sh` and `git-setup.sh` when
  an existing file is moved aside before being replaced. The marker
  keeps these distinct from any other `.backup` files you might have.

## Brittleness

- **`zsh/.zshenv` depth is baked into `DOTFILES_DIR` derivation.**
  `.zshenv` uses `${_zshenv_self:A:h:h}` to walk two levels up to the
  repo root. If `.zshenv` moves to a different depth, update the `:h`
  count (`<repo>/.zshenv` → `:A:h`; `<repo>/zsh/sub/.zshenv` →
  `:A:h:h:h`). Dir name doesn't matter, only depth.

## Uninstall

`uninstall.sh` reverses `install.sh`: it removes the symlinks it created
(`~/.zshenv`, `~/.zshrc`, `~/.tmux.conf`, etc, plus the
`~/.gitignore_global` and any `~/.claude/*` links) and restores the most
recent `<file>.backup_dqna64.<timestamp>` for each path. It only ever
deletes symlinks that resolve back into `$DOTFILES_DIR`, so unrelated user
config is never touched. It's idempotent.

```bash
~/dotfiles_dqna64/uninstall.sh --dry-run            # preview, change nothing
~/dotfiles_dqna64/uninstall.sh                      # interactive (prompts)
~/dotfiles_dqna64/uninstall.sh -y                   # auto-confirm the core removal (symlinks + backups); repo still prompted/kept
~/dotfiles_dqna64/uninstall.sh -y --remove-repo     # also delete the cloned $DOTFILES_DIR
~/dotfiles_dqna64/uninstall.sh --help               # list every flag
```

Flags can be combined; `--dry-run` (`-n`) can be added to any of the above to
preview it. `--yes` (`-y`) and `--no` are mutually exclusive, and `--yes` never
removes the repo on its own — pair it with `--remove-repo` (or use `--keep-repo`
to suppress the repo prompt in an interactive run).

Prompt model (all default to "no" non-interactively):

- **Core dotfiles removal** (the symlinks + backup restore) is prompted, and
  `-y` / `--yes` auto-confirms *only* this part.
- **Out-of-tree dependencies** (`~/.oh-my-zsh`, TPM) are **not** removed —
  they're shared tools you may use outside these dotfiles. The script just
  reports what's present and prints by-hand removal commands.
- **The cloned `$DOTFILES_DIR`** is **never** removed by `-y` — it requires an
  explicit `--remove-repo`.

User-owned files aren't edited: the script prints the `[include]` / `Include`
lines to remove from `~/.gitconfig` / `~/.ssh/config` and a reminder to revert
your login shell. Run `uninstall.sh --help` for all options.

## TODO

- [ ] Test out installing in a different directory than default, via
   `./install.sh` and via curl -fsSL
- [x] tmux session saving (via TPM + tmux-resurrect; see `tmux/.tmux.conf`)

### `uninstall.sh` review (issues + improvements)

Found during a review of `uninstall.sh`. Roughly highest-impact first.
Completed items have been moved to the review plan in `$AGENT_PLANS`
(`dotfiles-repo-review.md`, "Jun 6 — uninstall.sh hardening"). Remaining:

- [ ] **No end-of-run summary.** Consider printing a tally (symlinks removed,
  backups restored, things kept/removed) so the user can see at a glance what
  changed.
- [ ] **Add a safe test harness.** Manual testing already caused real damage
  once (an inherited `ZSH` env var pointed `rm -rf` at the real `~/.oh-my-zsh`).
  Add a scripted test that runs with an isolated `HOME`, `env -i`, and `ZSH`
  unset, exercising: symlink-into-repo removal + restore, foreign-symlink
  skip, real-file skip, empty-parent-dir cleanup, and the `--remove-repo` path.
- [ ] **`-y` + repo removal ordering note.** Self-deleting `$DOTFILES_DIR`
  while running from inside it works because the block is last and `cd`s out
  first, but it's fragile — worth a comment/guard (already partially there)
  and a test.

## Migrating from the bare git repo dotfiles

- [ ] clean up redundant bits in `~/.gitconfig`
- [ ] Clean up previous symlink ~/.gitignore_global → /Users/gordonh/.config/git/gitignore_global 
