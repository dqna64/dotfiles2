# Repo location (`DOTFILES_DIR`) - how it works

Usage (installing to a custom path) is in `README.md` -> "First-time setup".

## How scripts find the repo

`install.sh`, `uninstall.sh` and the other scripts resolve `$DOTFILES_DIR` in
this order: an explicit `DOTFILES_DIR=...` env var, else the checkout the script
runs from, else `$HOME/dotfiles_dqna64`.

## How the shell finds it

`install.sh` symlinks `~/.zshenv` into the repo. At every shell startup
`zsh/.zshenv` resolves that symlink with zsh's `:A` modifier and walks up to the
repo root, so the repo can live anywhere without per-machine edits. If
`~/.zshenv` is a regular file instead (install.sh hasn't run), it falls back to
`$HOME/dotfiles_dqna64`. A `DOTFILES_DIR` already in the environment wins.

`zsh/.zshrc` checks the result at startup and warns if `DOTFILES_DIR` doesn't
contain a clone (`$DOTFILES_DIR/zsh/.zshenv` missing).

## Brittleness: `.zshenv` depth is baked in

`.zshenv` uses `${_zshenv_self:A:h:h}` to walk two levels up (`zsh/.zshenv` ->
`zsh/` -> repo root). If `.zshenv` moves to a different depth, update the `:h`
count (`<repo>/.zshenv` -> `:A:h`; `<repo>/zsh/sub/.zshenv` -> `:A:h:h:h`). Only
depth matters, not directory names.
