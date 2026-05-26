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
# Must match install.sh's hardcoded clone location ($HOME/dotfiles_dqna64).
# If you cloned the repo somewhere else, change the default below (or
# export DOTFILES_DIR before zsh starts) so it points at the actual path.
# .zshrc sanity-checks this at startup and warns if it doesn't resolve to
# a valid clone, with instructions on how to fix it.
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles_dqna64}"

# === Machine-specific variables
# zsh-config is created from zsh-config.example by install.sh and holds
# per-machine values like DQNA64_MACHINE and CNV_WORK_BIN_PATH that the
# blocks below depend on.
ZSH_CONFIG_FILE="$DOTFILES_DIR/zsh/zsh-config"
if [ -f "$ZSH_CONFIG_FILE" ]; then
	source "$ZSH_CONFIG_FILE"
fi
unset ZSH_CONFIG_FILE

# === anaconda3
export PATH="/opt/anaconda3/bin:$PATH"

# === ripgrep config
# Point ripgrep at the ripgreprc tracked in this dotfiles repo. rg depends
# on this env var to find its config file.
export RIPGREP_CONFIG_PATH="$DOTFILES_DIR/ripgrep/ripgreprc"

# === Canva devbox-specific exports
# Active only when DQNA64_MACHINE identifies a Canva devbox.
case "$DQNA64_MACHINE" in
	DVBX1|DVBX2|DVBX3)
		# Prepend $CNV_WORK_BIN_PATH to PATH, if set in zsh-config.
		if [ -n "$CNV_WORK_BIN_PATH" ]; then
			export PATH="$CNV_WORK_BIN_PATH:$PATH"
		fi

		# Some binaries that are automatically installed on cnv devboxes.
		export PATH="$HOME/.local/bin:$PATH"
		export PATH="$HOME/.opencode/bin:$PATH"
		;;
esac
