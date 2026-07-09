#!/usr/bin/env bash

set -e

if [ -t 1 ]; then
	RED='\033[31m'
	GREEN='\033[32m'
	YELLOW='\033[33m'
	BLUE='\033[34m'
	BOLD='\033[1m'
	RESET='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	BOLD=''
	RESET=''
fi

echo_info() {
	echo -e "${GREEN}$*${RESET}"
}

echo_success() {
	echo -e "${GREEN}${BOLD}$*${RESET}"
}

echo_warn() {
	echo -e "${YELLOW}$*${RESET}" >&2
}

echo_error() {
	echo -e "${RED}${BOLD}$*${RESET}" >&2
}

echo_note() {
	echo -e "${BLUE}$*${RESET}"
}

# === Helpers

# symlink_dotfile <src> <dst>
#
# Idempotently symlink a tracked file from this dotfiles repo into its
# expected location.
#
# Behaviour:
#   - Errors out (exits) if <src> does not exist as a regular file.
#   - Creates the parent directory of <dst> with `mkdir -p` if missing.
#   - If <dst> is already a symlink pointing at <src>, prints a message and
#     does nothing (safe to re-run).
#   - If <dst> exists as a regular file, directory, or symlink pointing
#     elsewhere, it is moved aside to "<dst>.backup_dqna64.<YYYYMMDDHHMMSS>"
#     before the new symlink is created. Existing files are never overwritten
#     or deleted. The marker keeps these backups distinct from any other
#     `.backup` files you might have and lets `.gitignore` match them precisely.
#   - Creates an absolute symlink: <dst> -> <src>.
#
# Args:
#   $1  src  Absolute path to the source file inside the dotfiles repo.
#   $2  dst  Absolute path where the symlink should be created.
symlink_dotfile() {
	local src="$1"
	local dst="$2"

	if [ ! -f "$src" ]; then
		echo_error "Error: expected $src to exist."
		exit 1
	fi

	mkdir -p "$(dirname "$dst")"

	if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
		echo "Already symlinked, skipping: $dst -> $src"
		return 0
	fi

	if [ -e "$dst" ] || [ -L "$dst" ]; then
		local backup
		# Canonical naming lives in utils/common.sh (dotfiles_backup_path), but
		# install.sh stays self-contained: in a `curl | bash` bootstrap this
		# runs before the repo is cloned, so the lib isn't on disk yet.
		# MAKE SURE TO keep this format identical to the one in common.sh.
		backup="$dst.backup_dqna64.$(date +%Y%m%d%H%M%S)"
		echo_warn "Backing up existing $dst to $backup..."
		mv "$dst" "$backup"
	fi

	echo_info "Symlinking $src -> $dst..."
	ln -s "$src" "$dst"
}

is_macos() {
	[ "$(uname -s)" = "Darwin" ]
}

# brew_executable returns the first usable Homebrew binary.
# Preconditions: a Homebrew installation may already exist in PATH or at a
# standard Apple Silicon / Intel install path.
brew_executable() {
	if command -v brew >/dev/null 2>&1; then
		command -v brew
		return 0
	fi

	local candidate
	for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
		if [ -x "$candidate" ]; then
			echo "$candidate"
			return 0
		fi
	done

	return 1
}

# install_homebrew_if_needed installs Homebrew on macOS when it is not
# already available. Preconditions: the machine is macOS and the installer can
# be downloaded from GitHub using curl.
install_homebrew_if_needed() {
	if ! is_macos; then
		echo_info "Not macOS; skipping Homebrew installation."
		return 0
	fi

	if brew_executable >/dev/null 2>&1; then
		echo_info "Homebrew already installed, skipping."
		return 0
	fi

	if command -v xcode-select >/dev/null 2>&1 && ! xcode-select -p >/dev/null 2>&1; then
		echo_warn "Warning: Xcode command line tools are not installed. Homebrew may still install, but some formulae may fail later."
		echo_warn "Run 'xcode-select --install' if you want to install the developer toolchain now."
	fi

	echo_info "macOS detected — installing Homebrew..."
	if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
		echo_error "Homebrew installation failed. Check network connectivity and permissions, then retry."
		return 1
	fi

	local brew_exec
	if ! brew_exec=$(brew_executable 2>/dev/null); then
		echo_error "Homebrew installation completed, but brew is not on PATH."
		echo_info "Try adding Homebrew to your PATH and re-run the script."
		echo_info "  Apple Silicon: eval \"\$(/opt/homebrew/bin/brew shellenv)\""
		echo_info "  Intel Mac:    eval \"\$(/usr/local/bin/brew shellenv)\""
		return 1
	fi

	eval "$("$brew_exec" shellenv)" >/dev/null 2>&1 || true
	echo_success "Homebrew installation finished."
}

# normalize_github_remote <url>
#
# Reduce a GitHub remote URL to the canonical "owner/repo" form so we can
# compare URLs that differ only in transport / auth. Accepts:
#   - https://github.com/owner/repo(.git)?
#   - git@github.com:owner/repo(.git)?
#   - git@github.com-<alias>:owner/repo(.git)?    (SSH host-alias form from
#                                                  this repo's ssh/config.template)
#   - ssh://git@github.com/owner/repo(.git)?
# Strips the protocol+host prefix, any `.git` (with optional trailing `/`),
# and any leftover trailing `/`. Returns the raw input unchanged if no
# pattern matches.
normalize_github_remote() {
	# Use `#` as the sed delimiter so the `|` alternation inside the regex
	# isn't interpreted as the delimiter itself. `#` doesn't appear in
	# normal git remote URLs.
	echo "$1" | sed -E 's#^(https://|git@|ssh://git@)[^:/]*[:/]##;s#\.git/?$##;s#/$##'
}

# Optionally install Homebrew on macOS.
# Failure to install Homebrew here won't abort the rest of the install.
install_homebrew_if_needed || echo_warn "Continuing without Homebrew; install it later if you need it."

# === Pre-clone checks

if ! command -v git >/dev/null 2>&1; then
	echo_error "Error: git is required but not installed."
	exit 1
fi

# zsh is required for:
# - oh-my-zsh installer
# - it is the preferred shell of this dotfiles
if ! command -v zsh >/dev/null 2>&1; then
	echo_error "Error: zsh is required but not installed."
	echo_info "Install zsh and re-run, e.g.:"
	echo_info "  macOS:         brew install zsh"
	echo_info "  Debian/Ubuntu: sudo apt-get install zsh"
	exit 1
fi

# === Clone this dotfiles repo if it does not already exist

# Canonical repo URL. Only used as a last-resort fallback when we can't learn
# the URL from a local checkout — i.e. a piped `curl | bash` bootstrap, where
# the script arrives on stdin and has no way to know which URL it came from.
# Override with DOTFILES_REPO=... in the environment (e.g. to bootstrap a fork).
DOTFILES_REPO_FALLBACK="https://github.com/dqna64/dotfiles2.git"

# Prefer learning where to install from — and which repo URL to use — from the
# checkout this script is actually running out of. The common case is "clone
# somewhere, then run ./install.sh": in that case we install from that clone
# (no surprise second copy in $HOME) and treat its origin as the repo URL (so
# forks/renames work without editing this script). A piped `curl | bash` run
# has no script file on disk, so both fall back to the defaults below.
default_dotfiles_dir="$HOME/dotfiles_dqna64"
detected_repo=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
	script_repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || echo "")"
	# Require install.sh to live at the repo root, so a copy of this script
	# vendored deep inside some unrelated monorepo can't hijack the install.
	if [ -n "$script_repo_root" ] && [ -f "$script_repo_root/install.sh" ]; then
		detected_remote="$(git -C "$script_repo_root" remote get-url origin 2>/dev/null || echo "")"
		if [ -n "$detected_remote" ]; then
			default_dotfiles_dir="$script_repo_root"
			detected_repo="$detected_remote"
		fi
	fi
fi

# Resolution order (most specific wins): explicit env var > the local checkout
# we're running from > hardcoded canonical fallback.
DOTFILES_REPO="${DOTFILES_REPO:-${detected_repo:-$DOTFILES_REPO_FALLBACK}}"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"

# How to tell the user to re-invoke this installer in the messages below.
# When we're running from a real script file on disk we can point back at it
# ($0 is its path). A piped `curl | bash` bootstrap has no script on disk and
# leaves $0 as "bash", which would print a useless command — so fall back to
# the canonical curl one-liner instead.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
	reinstall_elsewhere="DOTFILES_DIR=<other-path> $0"
else
	reinstall_elsewhere="curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | DOTFILES_DIR=<other-path> bash"
fi

echo ""
if [ -d "$DOTFILES_DIR/.git" ]; then
	# A git repo already exists at $DOTFILES_DIR. We don't want to silently
	# symlink files out of it unless it's actually the dqna64-dotfiles
	# repo — otherwise a leftover test clone or unrelated repo at this
	# path would get installed into $HOME. Compare normalized origin URLs
	# so HTTPS / plain SSH / host-alias SSH all pass.
	existing_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo "")
	if [ "$(normalize_github_remote "$existing_remote")" != "$(normalize_github_remote "$DOTFILES_REPO")" ]; then
		echo_error "Error: another git repo already occupies $DOTFILES_DIR; its origin is not the dqna64-dotfiles repo."
		echo "  found:    ${existing_remote:-<no origin remote>}" >&2
		echo "  expected: $DOTFILES_REPO (or any URL pointing at the same owner/repo)" >&2
		echo "" >&2
		echo_warn "Pick the option that matches what's there and re-run:"
		echo_warn "  - it IS your dotfiles clone with a stale origin -> re-point it: git -C \"$DOTFILES_DIR\" remote set-url origin \"$DOTFILES_REPO\""
		echo_warn "  - it's an unrelated repo you want to keep        -> install elsewhere: $reinstall_elsewhere"
		echo_warn "  - it's disposable                               -> remove it and let install.sh re-clone."
		exit 1
	fi
	echo_info "Dotfiles repo already exists at $DOTFILES_DIR, skipping clone."
	echo_note "  To force a fresh clone, remove or move it aside first, e.g.:"
	echo_note "    mv \"$DOTFILES_DIR\" \"$DOTFILES_DIR.backup_dqna64.\$(date +%Y%m%d%H%M%S)\""
	echo_note "  Or install into a different path:"
	echo_note "    $reinstall_elsewhere"
	echo_note "  To just pull the latest changes into the existing clone:"
	echo_note "    git -C \"$DOTFILES_DIR\" pull --ff-only"
else
	if [ -e "$DOTFILES_DIR" ]; then
		echo_error "Error: $DOTFILES_DIR exists but is not a git repo."
		exit 1
	fi
	echo_info "Cloning dotfiles repo into $DOTFILES_DIR..."
	git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi


# === Install oh-my-zsh

# https://ohmyz.sh/

echo ""
ZSH="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH" ]; then
	echo "oh-my-zsh already installed at $ZSH, skipping."
else
	echo_info "Installing oh-my-zsh..."
	# Prevent ohmyzsh installation running zsh at the end, prevent it from
	# replacing .zshrc, preventing changing default shell
	RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo_info "Downloading oh-my-zsh themes/plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

if [ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
	echo "powerlevel10k already installed, skipping."
else
	echo_info "powerlevel10k..."
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
fi
echo_note "Using the powerlevel10k theme? Run 'p10k configure' in zsh to customise your prompt."

if [ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
	echo "zsh-autosuggestions already installed, skipping."
else
	echo_info "zsh-autosuggestions..."
	git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

# === zsh

echo ""
symlink_dotfile "$DOTFILES_DIR/zsh/.zshenv" "$HOME/.zshenv"
symlink_dotfile "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"

# Bootstrap per-machine zsh config from the example, if missing. Sourced by
# ~/.zshenv to pick up DQNA64_MACHINE and friends. zsh-config itself is
# gitignored so each machine can edit it independently.
ZSH_CONFIG_FILE="$DOTFILES_DIR/zsh/zsh-config"
if [ ! -f "$ZSH_CONFIG_FILE" ]; then
	echo_info "No zsh-config found at $ZSH_CONFIG_FILE."
	echo_info "Creating one from ${ZSH_CONFIG_FILE}.example..."
	cp -v "${ZSH_CONFIG_FILE}.example" "$ZSH_CONFIG_FILE"
	echo_note "Edit $ZSH_CONFIG_FILE to customise per-machine values (DQNA64_MACHINE, theme, etc.)."
	echo_note "It's sourced by ~/.zshenv at shell startup, so restart zsh (or run 'exec zsh') after editing for changes to take effect."
else
	echo_info "Existing zsh-config found at $ZSH_CONFIG_FILE, leaving it untouched."
	echo_note "Edit it to update per-machine values (DQNA64_MACHINE, theme, etc.); see ${ZSH_CONFIG_FILE}.example for any new options."
	echo_note "After updating, restart zsh (or run 'exec zsh') as it's sourced by ~/.zshenv at shell startup."
fi

# === git
#
# All git-related host setup (gitconfig, gitignore_global symlink, SSH host
# aliases) is handled by git/git-setup.sh, not here, because most of it
# depends on values from git/git-identity.

printf '%b' "$BLUE"
cat <<EOF

Configure git identities + per-account SSH host aliases [optional]

    Run:

      $DOTFILES_DIR/git/git-setup.sh

    Renders:
      - $DOTFILES_DIR/git/dqna64-dotfiles.gitconfig
                                (rendered from gitconfig.template;
                                 gitignored. Consumed via [include]
                                 in ~/.gitconfig.)
      - ~/.gitignore_global     (symlinked to git/.gitignore_global)
      - $DOTFILES_DIR/ssh/dqna64-dotfiles.conf
                                (rendered from ssh/config.template;
                                 gitignored. Consumed via Include in
                                 ~/.ssh/config. Defines github.com-<username>
                                 Host aliases (one per GitHub account) so
                                 multiple GitHub accounts can be used
                                 in parallel — no ssh-add juggling.)
    git-setup.sh does NOT touch ~/.gitconfig OR ~/.ssh/config — both
    are user-owned. If either does not already pull in the rendered
    snippet, the script prints the exact lines to add.
    Skip if you'll manage these files by hand.

EOF
printf '%b' "$RESET"

# === karabiner

echo ""
symlink_dotfile "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

# === tmux

echo ""
symlink_dotfile "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# Install TPM (tmux plugin manager), which manages the plugins declared in
# .tmux.conf (eg tmux-resurrect, etc).
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
	echo "TPM (tmux plugin manager) already installed at $TPM_DIR, skipping."
else
	echo_info "Installing TPM (tmux plugin manager)..."
	git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

printf '%b' "$BLUE"
cat <<EOF

  Finish tmux plugin setup [optional]

    The plugins are declared in $DOTFILES_DIR/tmux/.tmux.conf but aren't
    installed until you ask TPM to fetch them. Inside a tmux session:

      1. Reload the config (or start a fresh tmux):  tmux source ~/.tmux.conf
      2. Install the declared plugins:               prefix + I   (capital i)

    The default prefix is Ctrl-b, so that's Ctrl-b then Shift-i.

    tmux-resurrect (session persistence) usage, all with the prefix:

      prefix + Ctrl-s   save the current sessions/windows/panes
      prefix + Ctrl-r   restore the last saved environment

    Saved state lives in ~/.local/share/tmux/resurrect, so your layout
    survives a reboot or tmux server restart.

EOF
printf '%b' "$RESET"

# === yabai

echo ""
symlink_dotfile "$DOTFILES_DIR/yabai/yabairc" "$HOME/.config/yabai/yabairc"

# === claude
#
# Claude config isn't symlinked automatically — the README lists the
# available configs and the matching `ln -sf` commands.

printf '%b' "$BLUE"
cat <<EOF

  Optional: install Claude Code config.

    Configs live in $DOTFILES_DIR/claude/. Refer to
    $DOTFILES_DIR/claude/README.md — it walks you through picking a
    settings file and symlinking it (plus optional global instructions).

    Quick version: pick one and symlink it. E.g.:

      ln -sf "$DOTFILES_DIR/claude/settings.mb_m1.json" "\$HOME/.claude/settings.json"

    Global instructions for Claude:

      ln -sf "$DOTFILES_DIR/claude/CLAUDE.cnv.md" "\$HOME/.claude/CLAUDE.md"

    To share the global instructions with Cursor (one source of truth
    for both), symlink your chosen CLAUDE.*.md as a global Cursor rule:

      mkdir -p "\$HOME/.cursor/rules"
      ln -sf "$DOTFILES_DIR/claude/CLAUDE.cnv.md" "\$HOME/.cursor/rules/claude.mdc"

    Agent Skills (shared by Claude Code + Cursor) and Claude output styles
    are opt-in. To link the repo's skills into ~/.claude/skills and
    ~/.cursor/skills and its output styles into ~/.claude/output-styles, and
    to pick up new ones later, run (re-runnable; --dry-run to preview):

      $DOTFILES_DIR/claude/sync-agent-links.sh

EOF
printf '%b' "$RESET"

# === DOTFILES_DIR reminder

printf '%b' "$BLUE"
cat <<EOF

  Note: zsh/.zshenv auto-derives \$DOTFILES_DIR from its own location
  (now $DOTFILES_DIR) by resolving the ~/.zshenv symlink created above.
  No per-machine edit needed even if the repo lives outside the default
  \$HOME/dotfiles_dqna64. If you ever replace ~/.zshenv with a regular
  file (not a symlink), .zshenv falls back to \$HOME/dotfiles_dqna64.

EOF
printf '%b' "$RESET"

# === Set zsh as the default login shell
#
# oh-my-zsh was installed with CHSH=no, so the login shell is still unchanged
# at this point. Switch it to zsh here. Skipped if it's already zsh or if we
# can't prompt for a password (non-interactive bootstrap).
echo ""
# zsh's presence was already verified in the pre-clone checks above.
zsh_path="$(command -v zsh)"
if [ "$SHELL" = "$zsh_path" ]; then
	echo_info "Default login shell is already zsh ($zsh_path)."
elif [ ! -t 0 ]; then
	echo_warn "Non-interactive run; leaving your login shell unchanged."
	echo_note "To make zsh your default later, run:  chsh -s \"$zsh_path\""
else
	echo_info "Setting zsh ($zsh_path) as your default login shell..."
	# chsh only accepts shells listed in /etc/shells.
	if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
		echo_note "Adding $zsh_path to /etc/shells (may prompt for your password)..."
		echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null || true
	fi
	if chsh -s "$zsh_path"; then
		echo_success "Default shell changed to zsh; it takes effect on your next login."
	else
		echo_warn "Could not change the default shell automatically."
		echo_note "Run this yourself:  chsh -s \"$zsh_path\""
	fi
fi
unset zsh_path

# === Start zsh

# Only hand off to an interactive zsh when stdin is a real terminal. Under a
# piped bootstrap (`curl ... | bash`) stdin is the script stream, so `exec zsh`
# would inherit it, hit EOF, and exit immediately without an interactive
# shell — so we just tell the user to open a new terminal instead.
echo ""
if [ -t 0 ]; then
	echo_success "Done. Starting zsh..."
	exec zsh
else
	echo_success "Done. Open a new terminal (or run 'zsh') to start your configured shell."
fi
