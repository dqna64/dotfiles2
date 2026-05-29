#!/usr/bin/env bash

set -e

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
		echo "Error: expected $src to exist." >&2
		exit 1
	fi

	mkdir -p "$(dirname "$dst")"

	if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
		echo "$dst already symlinked to $src, skipping."
		return 0
	fi

	if [ -e "$dst" ] || [ -L "$dst" ]; then
		local backup
		backup="$dst.backup_dqna64.$(date +%Y%m%d%H%M%S)"
		echo "Backing up existing $dst to $backup..."
		mv "$dst" "$backup"
	fi

	echo "Symlinking $src -> $dst..."
	ln -s "$src" "$dst"
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

# === Pre-clone checks

if ! command -v git >/dev/null 2>&1; then
	echo "Error: git is required but not installed." >&2
	exit 1
fi

# === Clone this dotfiles repo if it does not already exist

DOTFILES_REPO="https://github.com/dqna64/dotfiles2.git"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles_dqna64}"

if [ -d "$DOTFILES_DIR/.git" ]; then
	# A git repo already exists at $DOTFILES_DIR. We don't want to silently
	# symlink files out of it unless it's actually the dqna64-dotfiles
	# repo — otherwise a leftover test clone or unrelated repo at this
	# path would get installed into $HOME. Compare normalized origin URLs
	# so HTTPS / plain SSH / host-alias SSH all pass.
	existing_remote=$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo "")
	if [ "$(normalize_github_remote "$existing_remote")" != "$(normalize_github_remote "$DOTFILES_REPO")" ]; then
		echo "Error: $DOTFILES_DIR is a git repo, but its origin remote does not match the dqna64-dotfiles repo." >&2
		echo "  found:    ${existing_remote:-<no origin remote>}" >&2
		echo "  expected: $DOTFILES_REPO (or any URL pointing at the same owner/repo)" >&2
		echo "" >&2
		echo "Fix one of the following and re-run:" >&2
		echo "  - point origin at the right repo:  git -C \"$DOTFILES_DIR\" remote set-url origin \"$DOTFILES_REPO\"" >&2
		echo "  - install to a different path:     DOTFILES_DIR=<other-path> $0" >&2
		echo "  - remove the conflicting directory and let install.sh re-clone." >&2
		exit 1
	fi
	echo "Dotfiles repo already exists at $DOTFILES_DIR, skipping clone."
	echo "  To force a fresh clone, remove or move it aside first, e.g.:"
	echo "    mv \"$DOTFILES_DIR\" \"$DOTFILES_DIR.backup_dqna64.\$(date +%Y%m%d%H%M%S)\""
	echo "  Or install into a different path:"
	echo "    DOTFILES_DIR=<other-path> $0"
	echo "  To just pull the latest changes into the existing clone:"
	echo "    git -C \"$DOTFILES_DIR\" pull --ff-only"
else
	if [ -e "$DOTFILES_DIR" ]; then
		echo "Error: $DOTFILES_DIR exists but is not a git repo." >&2
		exit 1
	fi
	echo "Cloning dotfiles repo into $DOTFILES_DIR..."
	git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi


# === Install oh-my-zsh

# https://ohmyz.sh/

ZSH="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH" ]; then
	echo "oh-my-zsh already installed at $ZSH, skipping."
else
	echo "Installing oh-my-zsh..."
	# Prevent ohmyzsh installation running zsh at the end prevent it from
	# replacing .zshrc, preventing changing default shell
	RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "Downloading oh-my-zsh themes/plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

if [ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
	echo "powerlevel10k already installed, skipping."
else
	echo "powerlevel10k..."
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
fi

if [ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
	echo "zsh-autosuggestions already installed, skipping."
else
	echo "zsh-autosuggestions..."
	git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

# === zsh

symlink_dotfile "$DOTFILES_DIR/zsh/.zshenv" "$HOME/.zshenv"
symlink_dotfile "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"

# Bootstrap per-machine zsh config from the example, if missing. Sourced by
# ~/.zshenv to pick up DQNA64_MACHINE and friends. zsh-config itself is
# gitignored so each machine can edit it independently.
ZSH_CONFIG_FILE="$DOTFILES_DIR/zsh/zsh-config"
if [ ! -f "$ZSH_CONFIG_FILE" ]; then
	echo "No zsh-config found at $ZSH_CONFIG_FILE."
	echo "Creating one from ${ZSH_CONFIG_FILE}.example..."
	cp -v "${ZSH_CONFIG_FILE}.example" "$ZSH_CONFIG_FILE"
	echo "Edit $ZSH_CONFIG_FILE to customise per-machine values (DQNA64_MACHINE, theme, etc.)."
fi

## TODO set zsh as default shell

# === git
#
# All git-related host setup (gitconfig, gitignore_global symlink, SSH host
# aliases) is handled by git/git-setup.sh, not here, because most of it
# depends on values from git/git-identity.

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

# === karabiner

symlink_dotfile "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

# === tmux

symlink_dotfile "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# === yabai

symlink_dotfile "$DOTFILES_DIR/yabai/yabairc" "$HOME/.config/yabai/yabairc"

# === claude
#
# Claude config is per-machine (settings + CLAUDE.md vary by host), so it
# isn't symlinked here. The README has the exact `ln -sf` commands keyed by
# $DQNA64_MACHINE.

cat <<EOF

  Optional: install per-machine Claude Code config.

    See  $DOTFILES_DIR/claude/README.md  for the symlink commands
    matching your machine (\$DQNA64_MACHINE). E.g. on MB_M1:

      ln -sf "$DOTFILES_DIR/claude/settings.mb_m1.json" "\$HOME/.claude/settings.json"

    Skip if you'll manage ~/.claude/ by hand.

EOF

# === DOTFILES_DIR reminder

cat <<EOF

  Note: zsh/.zshenv auto-derives \$DOTFILES_DIR from its own location
  (now $DOTFILES_DIR) by resolving the ~/.zshenv symlink created above.
  No per-machine edit needed even if the repo lives outside the default
  \$HOME/dotfiles_dqna64. If you ever replace ~/.zshenv with a regular
  file (not a symlink), .zshenv falls back to \$HOME/dotfiles_dqna64.

EOF

# === Start zsh

echo "Starting zsh..."
exec zsh
