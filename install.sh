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
#     elsewhere, it is moved aside to "<dst>.backup.<YYYYMMDDHHMMSS>" before
#     the new symlink is created. Existing files are never overwritten or
#     deleted.
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
		backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
		echo "Backing up existing $dst to $backup..."
		mv "$dst" "$backup"
	fi

	echo "Symlinking $src -> $dst..."
	ln -s "$src" "$dst"
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
	echo "Dotfiles repo already exists at $DOTFILES_DIR, skipping clone."
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

echo "Installing oh-my-zsh..."
# Prevent ohmyzsh installation running zsh at the end prevent it from
# replacing .zshrc, preventing changing default shell
RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "Downloading oh-my-zsh themes..."
echo "powerlevel10k..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
echo "zsh-autosuggestions..."
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"

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

  Optional: configure git identities + per-account SSH host aliases.

    1. Edit  $DOTFILES_DIR/git/git-identity  with your real values
       (copy from git-identity.example if it doesn't exist yet).
    2. Run   $DOTFILES_DIR/git/git-setup.sh
       Sets up:
         - ~/.gitconfig            (rendered from gitconfig.template)
         - ~/.gitconfig-personal   (rendered from gitconfig-personal.template)
         - ~/.gitignore_global     (symlinked to git/.gitignore_global)
         - ~/.ssh/dqna64-dotfiles.conf
                                   (rendered from ssh/config.template;
                                    defines github.com-<username> Host
                                    aliases (one per GitHub account) so
                                    multiple GitHub accounts can be used
                                    in parallel — no ssh-add juggling.)
       git-setup.sh does NOT touch ~/.ssh/config; if the file does not
       already Include the snippet, it prints the exact line to add.
       Skip step 2 if you'll manage these files by hand.

EOF

# === karabiner

symlink_dotfile "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

# === tmux

symlink_dotfile "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# === yabai

symlink_dotfile "$DOTFILES_DIR/yabai/yabairc" "$HOME/.config/yabai/yabairc"

# === claude
# Claude config is per-machine; see claude/README.md for the symlink commands
# matching your machine. Not automated here.

# === DOTFILES_DIR reminder

cat <<EOF

  Note: zsh/.zshenv reads \$DOTFILES_DIR to locate this repo at runtime.
  It defaults to \$HOME/dotfiles_dqna64 in .zshenv, which matches the
  default clone location used above ($DOTFILES_DIR).

  If you cloned to a different location, ensure DOTFILES_DIR is set to
  '$DOTFILES_DIR' in your shell environment BEFORE zsh sources .zshenv
  (e.g. via your login environment or a parent process). Otherwise the
  .zshenv default ('\$HOME/dotfiles_dqna64') will be used and any
  reference to \$DOTFILES_DIR (e.g. RIPGREP_CONFIG_PATH) will break.

EOF

# === Start zsh

echo "Starting zsh..."
exec zsh
