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
   manual form. `.zshrc` warns at shell startup if `DOTFILES_DIR`
   doesn't resolve to a real clone.

2. **Edit `zsh/zsh-config`** (bootstrapped from `zsh-config.example` by
   `install.sh`). Set `DQNA64_MACHINE` to one of `MB_M1`, `MB_CNV`,
   `DVBX1`, … and toggle the per-machine flags (`ENABLE_YABAI_DQNA64`,
   `ZSH_THEME_MY`, etc.). This file is gitignored.

3. **(Optional) Configure git identities + SSH host aliases.** Edit
   `git/git-identity` with your real values (it's bootstrapped from
   `git-identity.example`, also gitignored), then run
   `./git/git-setup.sh`. The script renders `~/.gitconfig`,
   `~/.gitconfig-personal`, the gitignore_global symlink, and the SSH
   host-alias snippet — and prints any one-off manual action you still
   need to take (e.g. adding the `Include` line to `~/.ssh/config`,
   which the script never touches).

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

1. Pick an identifier (e.g. `MB_M3`) and add a branch wherever
   `$DQNA64_MACHINE` is matched: the `case` blocks in `zsh/.zshrc`
   (aliases dir + optional machine-specific zshrc) and `zsh/.zshenv`
   (PATH / env additions).
2. Optionally create `aliases.<machine_lower>/` with machine-specific aliases.
3. If the machine needs a machine-specific zshrc, drop `zsh/.zshrc.<machine_lower>`
   and add the case branch to source it.
4. Add a Claude settings file (`claude/settings.<machine_lower>.json`) and
   register it in `claude/README.md` if Claude Code will run there.

## Gitignored, per-machine files (do not commit)

- `zsh/zsh-config` — machine identifier + flags.
- `git/git-identity` — real name/email/SSH key paths/GitHub usernames.
- `*.backup.*` — created by `install.sh` and `git-setup.sh` when an
  existing file is moved aside.
