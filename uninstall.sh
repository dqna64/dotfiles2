#!/usr/bin/env bash

# Reverse install.sh (and git-setup.sh): remove the symlinks they created and
# restore whatever was moved aside, so the machine returns to its pre-install
# dotfiles state.
#
# What it does, in order:
#   1. For each symlink install.sh / git-setup.sh creates (~/.zshrc, ~/.zshenv,
#      ~/.tmux.conf, ~/.config/karabiner/karabiner.json, ~/.config/yabai/yabairc,
#      ~/.gitignore_global, and the optional ~/.claude/* and
#      ~/.cursor/rules/claude.mdc links), remove it ONLY
#      if it is a symlink resolving into $DOTFILES_DIR — i.e. one we know we own.
#      Real files, directories, and symlinks pointing elsewhere are left alone.
#   2. Restore the most recent <file>.backup_dqna64.<timestamp> for that path, if
#      one exists and the path is now free. Older backups are left in place.
#   3. Report (but do NOT remove) the out-of-tree dependencies install.sh
#      fetched — oh-my-zsh (+ its custom themes/plugins) and TPM — with by-hand
#      removal instructions.
#   4. Print the manual follow-ups it can't safely do for you: the [include] /
#      Include lines git-setup.sh told you to add to ~/.gitconfig / ~/.ssh/config,
#      reverting your login shell, and powerlevel10k leftovers (~/.p10k.zsh +
#      the ~/.cache/p10k-instant-prompt-* cache).
#   5. Optionally (only via --remove-repo, or an interactive yes) remove the
#      cloned $DOTFILES_DIR itself.
#
# Safe to re-run. Nothing user-owned is deleted without an explicit symlink
# check or a confirmation prompt. Use --dry-run to preview.

set -euo pipefail
shopt -s nullglob

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

# === Options

DRY_RUN=false
ASSUME_YES=false
ASSUME_NO=false
REMOVE_REPO=""   # "" = ask, "true"/"false" = decided by flag

usage() {
	cat <<EOF
Usage: $0 [options]

Reverses install.sh: removes the dotfiles symlinks it created and restores the
most recent backup_dqna64 snapshot for each path.

Options:
  -n, --dry-run        Show what would happen without changing anything.
  -y, --yes            Assume "yes" to the core dotfiles prompt only (removing
                       the symlinks + restoring backups). Does NOT remove the
                       dotfiles repo.
      --no             Assume "no" to every prompt (default for non-interactive
                       runs).
      --remove-repo    Remove the cloned dotfiles repo (\$DOTFILES_DIR). This is
                       the only way to remove the repo; -y never does.
      --keep-repo      Keep the cloned dotfiles repo.
  -h, --help           Show this help.

Prompt model:
  - Core dotfiles removal (symlinks + backup restore): prompted interactively;
    --yes auto-confirms it.
  - Out-of-tree dependencies (oh-my-zsh, TPM) are NOT removed — they're shared
    tools you may use outside these dotfiles, so the script only reports what's
    present and prints by-hand removal instructions.
  - Dotfiles repo: only ever removed via --remove-repo (or an interactive yes).
All prompts default to "no" when run non-interactively; --no forces "no".
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY_RUN=true ;;
		-y|--yes) ASSUME_YES=true ;;
		--no) ASSUME_NO=true ;;
		--remove-repo) REMOVE_REPO=true ;;
		--keep-repo) REMOVE_REPO=false ;;
		-h|--help) usage; exit 0 ;;
		*) echo_error "Unknown option: $1"; echo ""; usage; exit 1 ;;
	esac
	shift
done

if [ "$ASSUME_YES" = "true" ] && [ "$ASSUME_NO" = "true" ]; then
	echo_error "Error: --yes and --no are mutually exclusive."
	exit 1
fi

# === Helpers

# do_cmd <command...>
# Run a command, or just print it under --dry-run.
do_cmd() {
	if [ "$DRY_RUN" = "true" ]; then
		echo_note "[dry-run] $*"
	else
		"$@"
	fi
}

# confirm <prompt> [honor_assume_yes]
# Ask a yes/no question. Honours --yes / --no; defaults to "no" both when
# explicitly requested and when there's no terminal to prompt at.
# honor_assume_yes defaults to "true"; pass "false" for high-blast-radius
# prompts (repo removal) that a blanket --yes must NOT auto-confirm.
confirm() {
	local prompt="$1"
	local honor_assume_yes="${2:-true}"
	if [ "$honor_assume_yes" = "true" ] && [ "$ASSUME_YES" = "true" ]; then return 0; fi
	if [ "$ASSUME_NO" = "true" ]; then return 1; fi
	if [ ! -t 0 ]; then return 1; fi
	local reply
	read -r -p "$(echo -e "${BLUE}${prompt} [y/N] ${RESET}")" reply
	case "$reply" in
		[Yy]|[Yy][Ee][Ss]) return 0 ;;
		*) return 1 ;;
	esac
}

# decide <flag-value> <prompt> [honor_assume_yes]
# If the flag pre-decided the answer (true/false), use it; otherwise prompt.
decide() {
	local preset="$1"
	local prompt="$2"
	local honor_assume_yes="${3:-true}"
	case "$preset" in
		true) return 0 ;;
		false) return 1 ;;
		*) confirm "$prompt" "$honor_assume_yes" ;;
	esac
}

# canonicalize_path <path>
# Fully resolve <path> to an absolute path, following symlink chains (not just
# one hop) and canonicalising any symlinked path components. macOS's stock
# readlink has no portable -f/realpath, so we walk the chain by hand. The max
# counter guards against symlink loops (ELOOP) so we never hang.
canonicalize_path() {
	local path="$1" link max=40
	while [ -L "$path" ] && [ "$max" -gt 0 ]; do
		link="$(readlink "$path")"
		case "$link" in
			/*) path="$link" ;;
			*)  path="$(cd "$(dirname "$path")" >/dev/null 2>&1 && pwd -P)/$link" ;;
		esac
		max=$((max - 1))
	done
	local dir
	if dir="$(cd "$(dirname "$path")" >/dev/null 2>&1 && pwd -P)"; then
		path="$dir/$(basename "$path")"
	fi
	printf '%s\n' "$path"
}

# path_inside_dotfiles <path>
# True if <path> is $DOTFILES_DIR or lives under it. Used so we only ever
# delete symlinks that resolve back into the repo we're uninstalling.
path_inside_dotfiles() {
	local p="$1"
	[ "$p" = "$DOTFILES_DIR" ] || [ "${p#"$DOTFILES_DIR"/}" != "$p" ]
}

# restore_latest_backup <dst> [assume_free]
# Move the newest <dst>.backup_dqna64.<timestamp> back to <dst>, but only if
# <dst> is now free. Backups sort chronologically because the timestamp is
# YYYYMMDDHHMMSS, so the lexically-last glob match is the most recent.
#
# assume_free (default false): the caller already removed (or, under --dry-run,
# would remove) whatever was at <dst>, so the path is about to be free. We only
# honour it under --dry-run, where the rm was skipped and the live check below
# would otherwise see the still-present symlink and wrongly report "not
# restoring" — hiding the restore a real run would perform. In a real run the
# rm has already happened, so the live filesystem check stays authoritative.
restore_latest_backup() {
	local dst="$1"
	local assume_free="${2:-false}"
	local backups=( "$dst".backup_dqna64.* )

	if [ ${#backups[@]} -eq 0 ]; then
		return 0
	fi

	local latest="${backups[${#backups[@]}-1]}"

	if ! { [ "$DRY_RUN" = "true" ] && [ "$assume_free" = "true" ]; } \
		&& { [ -e "$dst" ] || [ -L "$dst" ]; }; then
		echo_warn "  Not restoring: $dst still exists. Newest backup left at $latest"
		return 0
	fi

	echo_info "  Restoring $latest -> $dst"
	do_cmd mv "$latest" "$dst"

	if [ ${#backups[@]} -gt 1 ]; then
		echo_note "  ($((${#backups[@]} - 1)) older backup(s) for this path left in place.)"
	fi
}

# remove_dotfile_symlink <dst>
# Remove <dst> only if it's a symlink resolving into $DOTFILES_DIR, then try to
# restore the most recent backup. Anything else is reported and left untouched.
remove_dotfile_symlink() {
	local dst="$1"

	if [ -L "$dst" ]; then
		# Fully resolve the link (following any chain and canonicalising
		# symlinked path components, e.g. macOS /tmp -> /private/tmp) so the
		# inside-repo check below compares like-for-like with $DOTFILES_DIR
		# and can't be dodged by a link whose target is itself a symlink.
		local target
		target="$(canonicalize_path "$dst")"

		if path_inside_dotfiles "$target"; then
			echo_info "Removing symlink $dst -> $target"
			do_cmd rm "$dst"
			restore_latest_backup "$dst" true
		else
			echo_warn "Skipping $dst: symlink points outside the dotfiles repo ($target). Not ours to remove."
		fi
		return 0
	fi

	if [ -e "$dst" ]; then
		echo_note "Skipping $dst: not a symlink (left as-is)."
		# A real file here means the user replaced our symlink; don't clobber
		# it by restoring a backup over the top.
		return 0
	fi

	# Nothing at $dst (already removed / never installed). A leftover backup can
	# still be restored to bring the path back to its pre-install state.
	restore_latest_backup "$dst"
}

# remove_dir_if_empty <dir>
# Remove a parent directory install.sh created with `mkdir -p` (e.g.
# ~/.config/karabiner, ~/.config/yabai) once its symlink is gone — but only if
# it's now empty. `rmdir` only succeeds on an empty directory, so a dir still
# holding a leftover backup, a user file, or a restored real config is left
# untouched. Symlinked dirs are skipped (we don't follow them).
remove_dir_if_empty() {
	local dir="$1"

	[ -d "$dir" ] && [ ! -L "$dir" ] || return 0

	if [ "$DRY_RUN" = "true" ]; then
		# The symlink wasn't actually removed under --dry-run, so the dir
		# won't be empty yet; just announce the intent without touching it.
		echo_note "[dry-run] rmdir $dir (only if empty once its symlink is gone)"
		return 0
	fi

	if rmdir "$dir" 2>/dev/null; then
		echo_info "Removed now-empty directory $dir"
	fi
}

# === Resolve DOTFILES_DIR
#
# Same detection logic as install.sh: prefer the checkout this script runs from
# (uninstall.sh must sit at the repo root), fall back to the default location,
# allow an explicit DOTFILES_DIR override.
default_dotfiles_dir="$HOME/dotfiles_dqna64"
detected_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
	script_repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || echo "")"
	if [ -n "$script_repo_root" ] && [ -f "$script_repo_root/install.sh" ]; then
		detected_dir="$script_repo_root"
	fi
fi
DOTFILES_DIR="${DOTFILES_DIR:-${detected_dir:-$default_dotfiles_dir}}"

if [ ! -d "$DOTFILES_DIR" ]; then
	echo_error "Error: dotfiles repo not found at $DOTFILES_DIR."
	echo_info "Set DOTFILES_DIR=<path> if your clone lives elsewhere."
	exit 1
fi
# Canonicalise so the inside-repo prefix check is exact.
DOTFILES_DIR="$(cd "$DOTFILES_DIR" >/dev/null 2>&1 && pwd -P)"

echo ""
echo_success "Uninstalling dqna64 dotfiles"
echo_info "Repo:     $DOTFILES_DIR"
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

# === Remove symlinks + restore backups
#
# This is the core, strictly-dotfiles part of the uninstall: it only ever
# touches symlinks that resolve into $DOTFILES_DIR. --yes auto-confirms it.
echo ""
if decide "" "Remove the dotfiles symlinks (resolving into $DOTFILES_DIR) and restore backups?"; then
	echo_info "Removing symlinks that resolve into the dotfiles repo, restoring backups..."

	# Symlinks created by install.sh.
	remove_dotfile_symlink "$HOME/.zshenv"
	remove_dotfile_symlink "$HOME/.zshrc"
	remove_dotfile_symlink "$HOME/.tmux.conf"
	remove_dotfile_symlink "$HOME/.config/karabiner/karabiner.json"
	remove_dotfile_symlink "$HOME/.config/yabai/yabairc"

	# Clean up the parent dirs install.sh created with `mkdir -p` for the two
	# links above, but only if they're now empty (rmdir is a no-op otherwise,
	# so a kept backup or a restored real config keeps the dir).
	remove_dir_if_empty "$HOME/.config/karabiner"
	remove_dir_if_empty "$HOME/.config/yabai"

	# Symlink created by git-setup.sh.
	remove_dotfile_symlink "$HOME/.gitignore_global"

	# Optional symlinks the user may have created by hand following claude/README.md.
	remove_dotfile_symlink "$HOME/.claude/settings.json"
	remove_dotfile_symlink "$HOME/.claude/CLAUDE.md"
	# Optional Cursor global-rule symlink (claude/README.md). Like the ~/.claude
	# links above this is hand-created, so we only drop the symlink and leave
	# the user-managed ~/.cursor/rules dir (it may hold other rules) in place.
	remove_dotfile_symlink "$HOME/.cursor/rules/claude.mdc"
else
	echo_note "Skipping symlink removal."
fi

# === Out-of-tree dependencies install.sh fetched (informational only)
#
# install.sh clones oh-my-zsh and TPM outside the repo. Removing third-party
# tools isn't this uninstaller's job — they're shared tools you may rely on
# outside these dotfiles — so we only report what's present and how to remove
# it by hand. Nothing here is deleted.

echo ""
echo_info "Out-of-tree dependencies which install.sh fetched (NOT removed by this script):"

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH_DIR" ]; then
	echo_note "  - oh-my-zsh at $ZSH_DIR (incl. powerlevel10k + zsh-autosuggestions)."
	echo_note "      Remove by hand if no longer wanted:  rm -rf \"$ZSH_DIR\""
else
	echo_note "  - oh-my-zsh: none found at $ZSH_DIR."
fi

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
	echo_note "  - TPM (tmux plugin manager) at $TPM_DIR, plus any plugins it"
	echo_note "    fetched alongside it under $HOME/.tmux/plugins/."
	echo_note "      Remove by hand if no longer wanted:  rm -rf \"$HOME/.tmux/plugins\""
	echo_note "    Persisted tmux-resurrect state lives in $HOME/.local/share/tmux/resurrect."
	echo_note "    To refresh TPM plugins after changing tmux config (prefix is Ctrl-b by default):"
	echo_note "      tmux source-file ~/.tmux.conf   # reload config first"
	echo_note "      prefix + I        # install plugins newly listed in tmux.conf"
	echo_note "      prefix + U        # update installed plugins"
	echo_note "      prefix + Alt-u    # uninstall plugins no longer listed in tmux.conf"
else
	echo_note "  - TPM: none found at $TPM_DIR."
fi

# === Manual follow-ups we won't do automatically

printf '%b' "$BLUE"
cat <<EOF

Manual follow-ups (uninstall.sh won't touch user-owned files):

  - ~/.gitconfig: remove the [include] block git-setup.sh told you to add:
        [include]
            path = $DOTFILES_DIR/git/dqna64-dotfiles.gitconfig
  - ~/.ssh/config: remove the Include line for the rendered SSH snippet:
        Include $DOTFILES_DIR/ssh/dqna64-dotfiles.conf
  - Login shell: install.sh may have run 'chsh -s \$(command -v zsh)'. If you
    want a different default shell back, run e.g.:  chsh -s /bin/bash
  - powerlevel10k leftovers (only if you used the p10k theme):
        ~/.p10k.zsh                              your generated prompt config
        ~/.cache/p10k-instant-prompt-*.zsh(.zwc) regenerable instant-prompt cache
    The cache is safe to delete (it regenerates); ~/.p10k.zsh is your own
    config, so it's left for you to remove if you no longer want it.

EOF
printf '%b' "$RESET"

# === Optional: remove the cloned repo (done last; we're running from inside it)

echo ""
if [ ! -f "$DOTFILES_DIR/install.sh" ] || [ ! -f "$DOTFILES_DIR/uninstall.sh" ]; then
	# Refuse to rm -rf a $DOTFILES_DIR that doesn't look like this repo (e.g.
	# a hand-set env var pointing somewhere unexpected).
	echo_warn "Not offering to remove $DOTFILES_DIR: it doesn't look like the dotfiles repo (missing install.sh/uninstall.sh)."
elif decide "$REMOVE_REPO" "Remove the cloned dotfiles repo at $DOTFILES_DIR? This deletes the repo (incl. uninstall.sh and any gitignored per-machine files: zsh-config, git-identity, rendered git/ssh snippets)." false; then
	echo_warn "Removing $DOTFILES_DIR..."
	# cd out first so we're not deleting the directory we're sitting in, and do
	# it as the very last action since the script file lives inside it. Route
	# the cd through do_cmd too, so a dry-run neither moves nor deletes anything.
	do_cmd cd "$HOME"
	do_cmd rm -rf "$DOTFILES_DIR"
	[ "$DRY_RUN" = "true" ] || echo_success "Done. Removed the dotfiles repo. Open a new terminal to start a clean shell."
else
	echo_note "Keeping the dotfiles repo at $DOTFILES_DIR."
	echo_success "Done. Open a new terminal (or run 'exec \$SHELL') to pick up the reverted config."
fi
