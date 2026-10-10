# Sourced by zsh on EVERY invocation: login shells, interactive shells, AND
# non-interactive scripts (e.g. `ssh host cmd`, GUI-launched processes, cron).
#
# Rules of thumb for this file:
#   - Keep it FAST and SILENT (no echo / printf — output breaks scripts and
#     scp/rsync over ssh).
#   - Only put environment variables and PATH additions here. Aliases, prompt
#     setup, completion, and other interactive concerns belong in .zshrc.
#   - Guard sourced files with `[ -f ... ]` so missing files don't error out.

# === Path to this dotfiles repo
# Auto-derived from this file's own location when ~/.zshenv is a symlink
# into the repo (the layout install.sh creates): zsh's `:A` modifier
# resolves the symlink to its absolute target and `:h:h` walks
# .../zsh/.zshenv -> .../zsh -> the repo root. This lets the repo live
# anywhere on disk without per-machine edits to .zshenv.
#
# Fallback (regular-file .zshenv, i.e. install.sh hasn't run yet) uses
# install.sh's default clone location at $HOME/dotfiles_dqna64. An
# explicit DOTFILES_DIR set in the parent environment always wins.
#
# .zshrc sanity-checks the final value at startup and warns if it doesn't
# resolve to a valid clone, with instructions on how to fix it.
if [ -z "$DOTFILES_DIR" ]; then
	# ${(%):-%x} is the zsh prompt-expansion idiom for "the path to the
	# script currently being sourced" -- works in .zshenv (where $0 is
	# the parent zsh invocation, not this file).
	_zshenv_self="${(%):-%x}"
	if [ -L "$_zshenv_self" ]; then
		DOTFILES_DIR="${_zshenv_self:A:h:h}"
	else
		DOTFILES_DIR="$HOME/dotfiles_dqna64"
	fi
	unset _zshenv_self
fi
export DOTFILES_DIR

# === Machine-specific variables
# zsh-config is created from zsh-config.example by install.sh and holds
# per-machine values like DQNA64_MACHINE and DOTFILES_OVERLAYS that the
# blocks below depend on.
ZSH_CONFIG_FILE="$DOTFILES_DIR/zsh/zsh-config"
if [ -f "$ZSH_CONFIG_FILE" ]; then
	source "$ZSH_CONFIG_FILE"
fi
unset ZSH_CONFIG_FILE

# === anaconda3
# Only on machines where anaconda is actually installed.
[ -d /opt/anaconda3/bin ] && export PATH="/opt/anaconda3/bin:$PATH"

# === ripgrep config
# Point ripgrep at the ripgreprc tracked in this dotfiles repo. rg depends
# on this env var to find its config file.
export RIPGREP_CONFIG_PATH="$DOTFILES_DIR/ripgrep/ripgreprc"

# === User-installed scripts/binaries
# Prepended last so they win over earlier entries.
[ -d "$HOME/.local/bin" ]    && export PATH="$HOME/.local/bin:$PATH"

# === Work-tooling exports

# Appended by work machine provisioning; kept here unconditionally so it is
# not appended again.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# === bin/ from this repo and every extension repo
# Any dotfiles repo may carry bin/ with scripts. Each existing one is prepended
# to PATH, base first, so a later overlay's script shadows an earlier one's
# (dotdoctor reports same-named scripts). Work scripts live in the work
# overlay's bin/; nothing is configured per machine.
if [ -f "$DOTFILES_DIR/utils/overlays.sh" ]; then
	source "$DOTFILES_DIR/utils/overlays.sh"
	for _root in ${(f)"$(dotfiles_roots 2>/dev/null)"}; do
		[ -d "$_root/bin" ] && export PATH="$_root/bin:$PATH"
	done
	unset _root
fi
