#!/usr/bin/env bash

# Set up all git-related host config:
#   - gitconfig.template          -> ~/.gitconfig            (rendered)
#   - gitconfig-personal.template -> ~/.gitconfig-personal   (rendered)
#   - git/.gitignore_global       -> ~/.gitignore_global     (symlinked)
#   - ssh/config.template         -> ~/.ssh/dqna64-dotfiles.conf (rendered)
#
# Run AFTER install.sh — install.sh handles the zsh/karabiner/tmux/yabai
# pieces but leaves git-related host setup to this script because most of
# it depends on values from git/git-identity.
#
# Re-running is safe: existing rendered files are moved aside to
# <file>.backup.<YYYYMMDDHHMMSS> before being overwritten; the gitignore
# symlink is skipped if already correctly pointing at the repo.
#
# This script NEVER touches ~/.ssh/config. The SSH snippet only takes effect
# once you manually add `Include ~/.ssh/dqna64-dotfiles.conf` to ~/.ssh/config
# (ideally at or near the top). The script will print this instruction if
# the line is missing.

set -euo pipefail

# Resolve the dotfiles repo from this script's own location so the script
# works whether invoked directly, via install.sh, or from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_DIR="$DOTFILES_DIR/git"
SSH_TEMPLATE_DIR="$DOTFILES_DIR/ssh"
GIT_IDENTITY_FILE="$GIT_DIR/git-identity"

# Where the rendered SSH snippet lands and what gets Included from
# ~/.ssh/config. Kept under ~/.ssh (not ~/.ssh/config.d) for portability —
# Include just needs an absolute path.
SSH_SNIPPET_DEST="$HOME/.ssh/dqna64-dotfiles.conf"
SSH_CONFIG="$HOME/.ssh/config"
SSH_INCLUDE_LINE="Include $SSH_SNIPPET_DEST"

if [[ ! -f "$GIT_IDENTITY_FILE" ]]; then
    if [[ -f "${GIT_IDENTITY_FILE}.example" ]]; then
        echo "Creating git identity file from example..."
        cp "${GIT_IDENTITY_FILE}.example" "$GIT_IDENTITY_FILE"
        echo "Please edit $GIT_IDENTITY_FILE with your details, then run this script again."
    else
        echo "Error: $GIT_IDENTITY_FILE missing and ${GIT_IDENTITY_FILE}.example not found." >&2
    fi
    exit 1
fi

# shellcheck source=/dev/null
source "$GIT_IDENTITY_FILE"

# Back up <file> to <file>.backup.<ts> if it exists and is not a symlink we
# would happily overwrite. Symlinks point at things we don't own, so back
# them up too rather than dereferencing+overwriting.
backup_if_present() {
    local file="$1"
    if [[ -e "$file" || -L "$file" ]]; then
        local backup
        backup="$file.backup.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing $file to $backup..."
        mv "$file" "$backup"
    fi
}

# Idempotently create an absolute symlink <dst> -> <src>.
#   - If <dst> is already a symlink pointing at <src>: no-op.
#   - If <dst> exists as anything else (file, dir, wrong symlink): back it
#     up to <dst>.backup.<ts> first, then create the new symlink.
symlink_repo_file() {
    local src="$1"
    local dst="$2"

    if [[ ! -e "$src" ]]; then
        echo "Error: symlink source $src not found." >&2
        exit 1
    fi

    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        echo "$dst already symlinked to $src, skipping."
        return 0
    fi

    backup_if_present "$dst"
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "Symlinked $src -> $dst"
}

# Render <template> to <output>, substituting {{VAR}} placeholders with the
# values sourced from git-identity. Uses `|` as the sed delimiter so values
# containing `/` (e.g. SSH key paths) don't break the expression.
render_template() {
    local template_file="$1"
    local output_file="$2"

    if [[ ! -f "$template_file" ]]; then
        echo "Error: template $template_file not found." >&2
        exit 1
    fi

    backup_if_present "$output_file"

    sed -e "s|{{PRIMARY_NAME}}|${PRIMARY_NAME}|g" \
        -e "s|{{PRIMARY_EMAIL}}|${PRIMARY_EMAIL}|g" \
        -e "s|{{SECONDARY_NAME}}|${SECONDARY_NAME}|g" \
        -e "s|{{SECONDARY_EMAIL}}|${SECONDARY_EMAIL}|g" \
        -e "s|{{PRIMARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY}}|${PRIMARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY}|g" \
        -e "s|{{SECONDARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY}}|${SECONDARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY}|g" \
        -e "s|{{PRIMARY_GITHUB_USERNAME}}|${PRIMARY_GITHUB_USERNAME}|g" \
        -e "s|{{SECONDARY_GITHUB_USERNAME}}|${SECONDARY_GITHUB_USERNAME}|g" \
        "$template_file" > "$output_file"

    echo "Rendered $template_file -> $output_file"
}

render_template "$GIT_DIR/gitconfig.template"          "$HOME/.gitconfig"
render_template "$GIT_DIR/gitconfig-personal.template" "$HOME/.gitconfig-personal"

# Symlink the global gitignore so edits to git/.gitignore_global in the repo
# take effect immediately.
symlink_repo_file "$GIT_DIR/.gitignore_global" "$HOME/.gitignore_global"

# Render the SSH host-aliases snippet. Each account gets its own Host alias
# named github.com-<github-username> (with the username sourced from
# git-identity), pointing at github.com with a specific IdentityFile, so
# multiple GitHub accounts can be used in parallel without juggling ssh-agent.
#
# This script NEVER modifies ~/.ssh/config — that file may contain hand-
# curated config we must not touch. We only write to files we own:
#   - $HOME/.ssh/ (mkdir + chmod, harmless if already present)
#   - $HOME/.ssh/dqna64-dotfiles.conf (the rendered snippet; we own it)
# If ~/.ssh/config does not already Include our snippet, we PRINT
# instructions for the user to add the line manually.
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
render_template "$SSH_TEMPLATE_DIR/config.template" "$SSH_SNIPPET_DEST"
chmod 600 "$SSH_SNIPPET_DEST"

ssh_include_needed=false
if [[ ! -f "$SSH_CONFIG" ]]; then
    ssh_include_needed=true
elif ! grep -qxF "$SSH_INCLUDE_LINE" "$SSH_CONFIG"; then
    ssh_include_needed=true
fi

cat <<EOF

Git + SSH configuration installed successfully!

===
Git identity (per-repo):
   Primary:   $PRIMARY_NAME <$PRIMARY_EMAIL>
   Secondary: $SECONDARY_NAME <$SECONDARY_EMAIL>

   git primary        # Switch repo to primary identity
   git secondary      # Switch repo to secondary identity
   git whoami         # Show current identity
===
GitHub SSH host aliases (per-remote):
   github.com-${PRIMARY_GITHUB_USERNAME}    -> $PRIMARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY
   github.com-${SECONDARY_GITHUB_USERNAME}  -> $SECONDARY_REMOTE_ACCOUNT_SSH_PUBLIC_KEY

   Attach a repo to a specific account by setting its remote URL:
     git remote set-url origin git@github.com-${PRIMARY_GITHUB_USERNAME}:<org>/<repo>.git
     git remote set-url origin git@github.com-${SECONDARY_GITHUB_USERNAME}:<user>/<repo>.git

   Verify which account a host alias authenticates as:
     ssh -T git@github.com-${PRIMARY_GITHUB_USERNAME}
     ssh -T git@github.com-${SECONDARY_GITHUB_USERNAME}
===
EOF

if [[ "$ssh_include_needed" == "true" ]]; then
    cat <<EOF
ACTION REQUIRED: ~/.ssh/config does not Include the rendered snippet yet.
This script does not modify ~/.ssh/config — add the following line yourself,
ideally at (or near) the TOP of the file so the host aliases match before
any later \`Host *\` block:

    $SSH_INCLUDE_LINE

After adding it, test with:
    ssh -T git@github.com-${PRIMARY_GITHUB_USERNAME}
    ssh -T git@github.com-${SECONDARY_GITHUB_USERNAME}
===
EOF
else
    echo "OK: $SSH_CONFIG already Includes $SSH_SNIPPET_DEST."
    echo "==="
fi
