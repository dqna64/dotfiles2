#!/usr/bin/env bash

# Set up all git-related host config:
#   - gitconfig.template          -> git/dqna64-dotfiles.gitconfig  (rendered, gitignored, included from ~/.gitconfig)
#   - git/.gitignore_global       -> ~/.gitignore_global             (symlinked)
#   - ssh/config.template         -> ssh/dqna64-dotfiles.conf        (rendered, gitignored, Included from ~/.ssh/config)
#
# Run AFTER install.sh — install.sh handles the zsh/karabiner/tmux/yabai
# pieces but leaves git-related host setup to this script because most of
# it depends on values from git/git-identity.
#
# Re-running is safe: existing rendered files are moved aside to
# <file>.backup_dqna64.<YYYYMMDDHHMMSS> before being overwritten; the gitignore
# symlink is skipped if already correctly pointing at the repo.
#
# This script NEVER touches ~/.gitconfig OR ~/.ssh/config — both are
# user-owned and may contain machine-local config we must not clobber
# (e.g. [maintenance], [trace2] in ~/.gitconfig). Instead, the script
# renders standalone files and prints the exact one-time line(s) to add
# to ~/.gitconfig / ~/.ssh/config to pull them in via [include] / Include.

set -euo pipefail

# Resolve the dotfiles repo from this script's own location so the script
# works whether invoked directly, via install.sh, or from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_DIR="$DOTFILES_DIR/git"
SSH_TEMPLATE_DIR="$DOTFILES_DIR/ssh"
GIT_IDENTITY_FILE="$GIT_DIR/git-identity"

# Rendered files live inside this repo, next to their templates, but
# gitignored — they contain per-machine values (real email, GitHub
# usernames, SSH key paths) substituted from git-identity. Each machine
# renders its own copies; nothing here is shared across hosts.
GITCONFIG_RENDERED="$GIT_DIR/dqna64-dotfiles.gitconfig"
SSH_SNIPPET_DEST="$SSH_TEMPLATE_DIR/dqna64-dotfiles.conf"

USER_GITCONFIG="$HOME/.gitconfig"
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
else
    echo "Using existing git identity at $GIT_IDENTITY_FILE to render the gitconfig + SSH snippet."
    echo "  To change names/emails/SSH keys/GitHub usernames, edit it and re-run this script."
fi

# shellcheck source=/dev/null
source "$GIT_IDENTITY_FILE"

# Reassure the user: git-identity and the files rendered from it are
# gitignored, so real names/emails/keys/usernames are never committed.
echo "Note: git-identity and the rendered gitconfig/SSH snippet are gitignored — your real details won't be committed."

# Back up <file> to <file>.backup_dqna64.<ts> if it exists and is not a
# symlink we would happily overwrite. Symlinks point at things we don't own,
# so back them up too rather than dereferencing+overwriting. The
# backup_dqna64 marker keeps these distinct from any other `.backup` files
# you might have and lets `.gitignore` match them precisely.
backup_if_present() {
    local file="$1"
    if [[ -e "$file" || -L "$file" ]]; then
        local backup
        backup="$file.backup_dqna64.$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing $file to $backup..."
        mv "$file" "$backup"
    fi
}

# Idempotently create an absolute symlink <dst> -> <src>.
#   - If <dst> is already a symlink pointing at <src>: no-op.
#   - If <dst> exists as anything else (file, dir, wrong symlink): back it
#     up to <dst>.backup_dqna64.<ts> first, then create the new symlink.
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
    mkdir -p "$(dirname "$output_file")"

    sed -e "s|{{PRIMARY_NAME}}|${PRIMARY_NAME}|g" \
        -e "s|{{PRIMARY_EMAIL}}|${PRIMARY_EMAIL}|g" \
        -e "s|{{SECONDARY_NAME}}|${SECONDARY_NAME}|g" \
        -e "s|{{SECONDARY_EMAIL}}|${SECONDARY_EMAIL}|g" \
        -e "s|{{PRIMARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY}}|${PRIMARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY}|g" \
        -e "s|{{SECONDARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY}}|${SECONDARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY}|g" \
        -e "s|{{PRIMARY_GITHUB_USERNAME}}|${PRIMARY_GITHUB_USERNAME}|g" \
        -e "s|{{SECONDARY_GITHUB_USERNAME}}|${SECONDARY_GITHUB_USERNAME}|g" \
        "$template_file" > "$output_file"

    echo "Rendered $template_file -> $output_file"
}

render_template "$GIT_DIR/gitconfig.template" "$GITCONFIG_RENDERED"

# Symlink the global gitignore so edits to git/.gitignore_global in the repo
# take effect immediately.
symlink_repo_file "$GIT_DIR/.gitignore_global" "$HOME/.gitignore_global"

# Check whether ~/.gitconfig pulls in the rendered snippet via [include].
# We never modify ~/.gitconfig — if the include is missing, print the
# exact block to add. Use `git config` for detection so whitespace /
# alternative formatting in ~/.gitconfig doesn't fool a raw grep.
gitconfig_include_needed=true
if [[ -f "$USER_GITCONFIG" ]] \
        && git config --file "$USER_GITCONFIG" --get-all include.path 2>/dev/null \
        | grep -qxF -- "$GITCONFIG_RENDERED"; then
    gitconfig_include_needed=false
fi

# Render the SSH host-aliases snippet. Each account gets its own Host alias
# named github.com-<github-username> (with the username sourced from
# git-identity), pointing at github.com with a specific IdentityFile, so
# multiple GitHub accounts can be used in parallel without juggling ssh-agent.
#
# This script NEVER modifies ~/.ssh/config — that file may contain hand-
# curated config we must not touch. We only write to files we own:
#   - $SSH_SNIPPET_DEST (the rendered snippet, inside this repo, gitignored)
# If ~/.ssh/config does not already Include our snippet, we PRINT
# instructions for the user to add the line manually. The snippet is
# chmod 600 so ssh is happy whether or not it enforces StrictModes on
# Included files.
render_template "$SSH_TEMPLATE_DIR/config.template" "$SSH_SNIPPET_DEST"
chmod 600 "$SSH_SNIPPET_DEST"

# Check whether ~/.ssh/config Includes our snippet. Match against the
# canonical `Include <absolute-path>` line as a fixed string. We don't
# bother handling unusual whitespace or quoting — anyone who edits the
# Include line by hand can recognize the script's nag and ignore it.
ssh_include_needed=true
if [[ -f "$SSH_CONFIG" ]] && grep -qxF "$SSH_INCLUDE_LINE" "$SSH_CONFIG"; then
    ssh_include_needed=false
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
   github.com-${PRIMARY_GITHUB_USERNAME}    -> $PRIMARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY
   github.com-${SECONDARY_GITHUB_USERNAME}  -> $SECONDARY_REMOTE_ACCOUNT_SSH_PRIVATE_KEY

   Attach a repo to a specific account by setting its remote URL:
     git remote set-url origin git@github.com-${PRIMARY_GITHUB_USERNAME}:<org>/<repo>.git
     git remote set-url origin git@github.com-${SECONDARY_GITHUB_USERNAME}:<user>/<repo>.git

   Verify which account a host alias authenticates as:
     ssh -T git@github.com-${PRIMARY_GITHUB_USERNAME}
     ssh -T git@github.com-${SECONDARY_GITHUB_USERNAME}
===
EOF

if [[ "$gitconfig_include_needed" == "true" ]]; then
    cat <<EOF
ACTION REQUIRED: ~/.gitconfig does not include the rendered snippet yet.
This script does not modify ~/.gitconfig — add the following two lines
yourself, ideally near the TOP so anything you set later in ~/.gitconfig
can override the defaults:

[include]
    path = $GITCONFIG_RENDERED

After adding it, verify with (NOT \`--global\`, which scopes to the
file itself and does not resolve includes):
    git config --get user.email   # should print $PRIMARY_EMAIL
===
EOF
else
    echo "OK: $USER_GITCONFIG already includes $GITCONFIG_RENDERED."
    echo "==="
fi

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
