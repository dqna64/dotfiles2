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

# Shared helpers — we only use dotfiles_backup_path here (the single source of
# truth for the backup_dqna64 naming scheme), but sourcing keeps that marker
# defined in one place across all the cloned-repo scripts.
COMMON_LIB="$DOTFILES_DIR/utils/common.sh"
if [[ ! -r "$COMMON_LIB" ]]; then
    echo "Error: required helper library not found at $COMMON_LIB" >&2
    exit 1
fi
# shellcheck source=../utils/common.sh
. "$COMMON_LIB"

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

# Marker comments that wrap the block we ask the user to paste into their
# user-owned ~/.gitconfig / ~/.ssh/config. `#` is a valid comment leader in
# both formats, so one style works for both.
DQNA64_BLOCK_START="# --- START DQNA64 DOTFILES (managed by dotfiles at $DOTFILES_DIR) --- #"
DQNA64_BLOCK_END="# --- END DQNA64 DOTFILES --- #"
# Stable substrings used only to DETECT (not generate) an existing wrap.
DQNA64_MARKER_START_ANCHOR="START DQNA64 DOTFILES"
DQNA64_MARKER_END_ANCHOR="END DQNA64 DOTFILES"

# Robust guardrail: is `needle` (a fixed string, e.g. the Include line or the
# rendered gitconfig path) present on a line that sits BETWEEN our START/END
# marker comments? This reinforces the plain "does the include exist?" check —
# an include is only considered ours when it also lives inside the managed
# block, which is exactly what uninstall.sh keys off to tear it down again.
include_wrapped_in_markers() {
    local file="$1" needle="$2"
    [[ -f "$file" ]] || return 1
    awk -v start="$DQNA64_MARKER_START_ANCHOR" \
        -v end="$DQNA64_MARKER_END_ANCHOR" \
        -v needle="$needle" '
        index($0, start) { inblk = 1; next }
        index($0, end)   { inblk = 0; next }
        inblk && index($0, needle) { found = 1 }
        END { exit(found ? 0 : 1) }' "$file"
}

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
    echo "  To change names/emails/SSH keys/SSH host alias labels, edit it and re-run this script."
fi

# shellcheck source=/dev/null
source "$GIT_IDENTITY_FILE"

# Preflight: git-identity is created once from git-identity.example and then
# never auto-updated (it holds your real values). So when the example gains or
# renames variables, an existing git-identity silently lacks them — which would
# otherwise surface much later as a cryptic `set -u` "unbound variable" abort
# during rendering. Catch it here with a clear, actionable message instead.
#
# We compare the set of variable NAMES each file defines (obtained robustly by
# shell-var-names.sh, which sources the file rather than regex-scraping it),
# never values, so your real names/emails/keys are never inspected or printed.
example_file="${GIT_IDENTITY_FILE}.example"
actual_file="$GIT_IDENTITY_FILE"
SHELL_VAR_NAMES="$DOTFILES_DIR/utils/shell-var-names.sh"
if [[ -f "$example_file" && -f "$SHELL_VAR_NAMES" ]]; then
    example_vars="$(bash "$SHELL_VAR_NAMES" "$example_file")"
    actual_vars="$(bash "$SHELL_VAR_NAMES" "$actual_file")"
    missing_vars="$(comm -23 <(printf '%s\n' "$example_vars") <(printf '%s\n' "$actual_vars"))"
    extra_vars="$(comm -13 <(printf '%s\n' "$example_vars") <(printf '%s\n' "$actual_vars"))"

    if [[ -n "$missing_vars" ]]; then
        echo "Error: $actual_file is missing variables defined in $example_file:" >&2
        echo "$missing_vars" | sed 's/^/         + /' >&2
        if [[ -n "$extra_vars" ]]; then
            echo "       It also defines variables NOT in the example (likely the old/renamed names):" >&2
            echo "$extra_vars" | sed 's/^/         - /' >&2
        fi
        echo "       These are new or renamed. Update $actual_file to define the missing" >&2
        echo "       variables (compare against $example_file), then re-run this script." >&2
        exit 1
    fi
fi

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
        backup="$(dotfiles_backup_path "$file")"
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
        -e "s|{{PRIMARY_ACC_SSH_PRIV_KEY}}|${PRIMARY_ACC_SSH_PRIV_KEY}|g" \
        -e "s|{{PRIMARY_ACC_SSH_ALIAS}}|${PRIMARY_ACC_SSH_ALIAS}|g" \
        -e "s|{{SECONDARY_NAME}}|${SECONDARY_NAME}|g" \
        -e "s|{{SECONDARY_EMAIL}}|${SECONDARY_EMAIL}|g" \
        -e "s|{{SECONDARY_ACC_SSH_PRIV_KEY}}|${SECONDARY_ACC_SSH_PRIV_KEY}|g" \
        -e "s|{{SECONDARY_ACC_SSH_ALIAS}}|${SECONDARY_ACC_SSH_ALIAS}|g" \
        "$template_file" > "$output_file"

    # Stamp the rendered file with the git object id of the template it was
    # generated from. The shell-startup drift check in aliases.git_stuff/git.zsh
    # recomputes the template's oid and compares against this, so an upstream
    # template change (e.g. after `git pull`) that hasn't been re-rendered gets
    # surfaced loudly instead of silently drifting. Both gitconfig and ssh
    # config use `#` for comments, so a trailing comment is safe for either.
    printf '\n# dqna64-template-oid: %s\n' "$(git hash-object "$template_file")" >> "$output_file"

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
# Two independent signals, both required for a "fully managed" include:
#   1. the include actually resolves (git config parses include.path), and
#   2. it's wrapped in our markers (the extra guardrail; also what uninstall
#      keys off). A functional-but-unwrapped include still works, so we only
#      nudge rather than treat it as missing.
gitconfig_include_needed=true
gitconfig_markers_present=false
if [[ -f "$USER_GITCONFIG" ]] \
        && git config --file "$USER_GITCONFIG" --get-all include.path 2>/dev/null \
        | grep -qxF -- "$GITCONFIG_RENDERED"; then
    gitconfig_include_needed=false
    if include_wrapped_in_markers "$USER_GITCONFIG" "$GITCONFIG_RENDERED"; then
        gitconfig_markers_present=true
    fi
fi

# Render the SSH host-aliases snippet. Each account gets its own Host alias
# named github.com-<alias> (the <alias> label sourced from
# PRIMARY_ACC_SSH_ALIAS/SECONDARY_ACC_SSH_ALIAS in git-identity), pointing at github.com
# with a specific IdentityFile, so multiple GitHub accounts can be used in
# parallel without juggling ssh-agent.
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

# Same two-signal check as gitconfig above: the canonical `Include <abs-path>`
# line must exist AND be wrapped in our markers to count as fully managed.
ssh_include_needed=true
ssh_markers_present=false
ssh_include_after_host=false
if [[ -f "$SSH_CONFIG" ]] && grep -qxF "$SSH_INCLUDE_LINE" "$SSH_CONFIG"; then
    ssh_include_needed=false
    if include_wrapped_in_markers "$SSH_CONFIG" "$SSH_INCLUDE_LINE"; then
        ssh_markers_present=true
    fi
    # ssh only processes an Include nested in a Host/Match block when that block
    # matches, so an Include placed below one silently drops our aliases.
    if awk -v want="$SSH_INCLUDE_LINE" '
        /^[[:space:]]*(Host|Match)[[:space:]]/ { host=1 }
        $0==want && host { bad=1 } END { exit(bad?0:1) }' "$SSH_CONFIG"; then
        ssh_include_after_host=true
    fi
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
   gm -2 "message"    # Commit as secondary identity (this commit only)
===
GitHub SSH host aliases (per-remote):
   github.com-${PRIMARY_ACC_SSH_ALIAS}    -> $PRIMARY_ACC_SSH_PRIV_KEY
   github.com-${SECONDARY_ACC_SSH_ALIAS}  -> $SECONDARY_ACC_SSH_PRIV_KEY

   Attach a repo to a specific account by setting its remote URL:
     git remote set-url origin git@github.com-${PRIMARY_ACC_SSH_ALIAS}:<org>/<repo>.git
     git remote set-url origin git@github.com-${SECONDARY_ACC_SSH_ALIAS}:<user>/<repo>.git

   Verify which account a host alias authenticates as:
     ssh -T git@github.com-${PRIMARY_ACC_SSH_ALIAS}
     ssh -T git@github.com-${SECONDARY_ACC_SSH_ALIAS}
===
EOF

# OK requires BOTH: the include resolves AND it's wrapped in our markers (the
# wrap is mandatory — uninstall.sh keys off the markers to remove the block).
if [[ "$gitconfig_include_needed" == "false" && "$gitconfig_markers_present" == "true" ]]; then
    echo "OK: $USER_GITCONFIG includes $GITCONFIG_RENDERED (wrapped in DQNA64 markers)."
elif [[ "$gitconfig_include_needed" == "false" ]]; then
    cat <<EOF
ACTION REQUIRED: ~/.gitconfig's include isn't wrapped in the DQNA64 markers
(required — uninstall.sh keys off them). Wrap it like so:

$DQNA64_BLOCK_START
[include]
    path = $GITCONFIG_RENDERED
$DQNA64_BLOCK_END
EOF
else
    cat <<EOF
ACTION REQUIRED: ~/.gitconfig doesn't include the snippet (this script won't
touch it). Add this near the TOP so your later settings can override it:

$DQNA64_BLOCK_START
[include]
    path = $GITCONFIG_RENDERED
$DQNA64_BLOCK_END

Verify (not \`--global\`, which skips includes):
    git config --get user.email   # -> $PRIMARY_EMAIL
EOF
fi
echo "==="

# Same rule for ssh: Include must exist AND be wrapped in markers to be OK.
if [[ "$ssh_include_needed" == "false" && "$ssh_markers_present" == "true" ]]; then
    echo "OK: $SSH_CONFIG Includes $SSH_SNIPPET_DEST (wrapped in DQNA64 markers)."
    [[ "$ssh_include_after_host" == "true" ]] && echo "   WARNING: Include sits below a Host/Match block, so aliases won't load — move it ABOVE any Host/Match block."
elif [[ "$ssh_include_needed" == "false" ]]; then
    cat <<EOF
ACTION REQUIRED: ~/.ssh/config's Include isn't wrapped in the DQNA64 markers
(required — uninstall.sh keys off them). Wrap it like so:

$DQNA64_BLOCK_START
$SSH_INCLUDE_LINE
$DQNA64_BLOCK_END
EOF
    [[ "$ssh_include_after_host" == "true" ]] && echo "   WARNING: it also sits below a Host/Match block — keep the wrapped block ABOVE any Host/Match block."
else
    cat <<EOF
ACTION REQUIRED: add this to the TOP of ~/.ssh/config, before any Host/Match
block (this script won't touch it):

$DQNA64_BLOCK_START
$SSH_INCLUDE_LINE
$DQNA64_BLOCK_END

Test:
    ssh -T git@github.com-${PRIMARY_ACC_SSH_ALIAS}
    ssh -T git@github.com-${SECONDARY_ACC_SSH_ALIAS}
EOF
fi
echo "==="
