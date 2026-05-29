# dotfiles

Gordons cross-machine dotfiles. Includes shared and machine-specific
configurations for tools like zsh, git, ssh, vscode, claude, tmux, etc.

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
   `<file>.backup.<timestamp>`.

   ```bash
   curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | bash
   ```

   Or, if you'd rather inspect first, clone the repo manually and run
   `install.sh` from it:

   ```bash
   git clone https://github.com/dqna64/dotfiles2.git ~/dotfiles_dqna64
   ~/dotfiles_dqna64/install.sh
   ```

   To clone elsewhere, set `DOTFILES_DIR=<path>` — prefix it to the
   receiving `bash` in the curl form, or `export` it before running the
   manual form. `install.sh` will clone into that path and symlink
   `~/.zshenv` to it; `zsh/.zshenv` auto-derives `DOTFILES_DIR` from
   that symlink on every shell startup, so no shell-rc edit is needed
   to remember the non-default location. `.zshrc` warns at startup if
   `DOTFILES_DIR` doesn't resolve to a real clone.

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
   - `~/.ssh/dqna64-dotfiles.conf` — SSH host-alias snippet

   `~/.gitconfig` and `~/.ssh/config` are user-owned and never modified
   by the script. To pull in the rendered files, `git-setup.sh` prints
   the exact one-time blocks to add:

   ```ini
   # in ~/.gitconfig (path printed by git-setup.sh based on $DOTFILES_DIR)
   [include]
       path = ~/dotfiles_dqna64/git/dqna64-dotfiles.gitconfig
   ```

   ```
   # in ~/.ssh/config
   Include ~/.ssh/dqna64-dotfiles.conf
   ```

4. **(Optional) Symlink Claude / VS Code / Cursor config** following the
   per-tool instructions in `claude/README.md` and `vscode/README.md`.

## Aliases

Aliases and shell functions live in `aliases/` (cross-machine) and per-machine
`aliases.<machine>/` directories (e.g. `aliases.mb_m1/`, `aliases.mb_cnv/`,
`aliases.dvbx1/`). They're loaded by `zsh/.zshrc` on every interactive shell.

- File extension: `.zsh` (these files are sourced into zsh, not executed).
- All `*.zsh` files in `aliases/` are sourced on every machine.
- Per-machine `*.zsh` files are sourced from `aliases.<machine>/` only when
  `$DQNA64_MACHINE` matches. The mapping lives in the `case` block in
  `zsh/.zshrc`; add a branch when wiring up a new machine.

To add a new alias file: drop a `.zsh` file in the appropriate dir. No need
to register it anywhere — `.zshrc` globs the dirs automatically.

## Adding a new machine

1. Pick an identifier (e.g. `MB_M3`).
2. Add a branch to the **aliases** `case` block in `zsh/.zshrc` if
   you'll create an aliases dir (`MACHINE_ALIASES_DIR=…`). Add a branch
   in `zsh/.zshenv` if the machine needs PATH/env additions
   (e.g. `DVBX*` block).
3. Optionally create `aliases.<machine_lower>/` with machine-specific
   aliases (`mb_m1`, `mb_cnv`, `dvbx1`, ...). `_` not `-`, matching the
   aliases case block.
4. Optionally drop `zsh/.zshrc.<machine-with-hyphens>` (`mb-m1`,
   `mb-cnv`, `dvbx1`, …) for a machine-specific zshrc. **No
   registration needed** — `zsh/.zshrc` auto-sources by the derived
   filename. `-` not `_`, matching `.zshrc.mb-m1`.
5. Add a Claude settings file (`claude/settings.<machine_lower>.json`)
   and register it in `claude/README.md` if Claude Code will run there.

## Gitignored, per-machine files (do not commit)

- `zsh/zsh-config` — machine identifier + flags.
- `git/git-identity` — real name/email/SSH key paths/GitHub usernames.
- `*.backup.*` — created by `install.sh` and `git-setup.sh` when an
  existing file is moved aside.

## Brittleness

- **`zsh/.zshenv` depth is baked into `DOTFILES_DIR` derivation.**
  `.zshenv` uses `${_zshenv_self:A:h:h}` to walk two levels up to the
  repo root. If `.zshenv` moves to a different depth, update the `:h`
  count (`<repo>/.zshenv` → `:A:h`; `<repo>/zsh/sub/.zshenv` →
  `:A:h:h:h`). Dir name doesn't matter, only depth.

## Migrating from the bare git repo dotfiles

- [ ] clean up redundant bits in `~/.gitconfig`
- [ ] clean up previous symlink ~/.gitignore_global → /Users/gordonh/.config/git/gitignore_global 
