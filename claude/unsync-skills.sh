#!/usr/bin/env bash

# Reverse claude/sync-skills.sh: remove the per-skill symlinks it created under
# ~/.claude/skills and ~/.cursor/skills, restore anything it moved aside, and
# drop the skill dirs if they end up empty.
#
# Run it standalone to opt out of the dotfiles skills on a machine, or let
# uninstall.sh call it as part of a full uninstall.
#
# Safety model (mirrors sync-skills.sh / uninstall.sh):
#   - Only removes symlinks that resolve back into this repo's skills/ dir —
#     i.e. links we created. Foreign skills (e.g. ~/.cursor/skills/ast-grep) and
#     real files/dirs are reported and left untouched.
#   - After removing our link, restores the most recent
#     <dst>.backup_dqna64.<timestamp> if the path is now free, undoing the
#     "moved aside" that sync-skills.sh did when something was in the way.
#   - Removes ~/.claude/skills and ~/.cursor/skills only if they're empty
#     afterwards (rmdir no-ops otherwise), so foreign skills / leftover backups
#     keep the dir.
#   - --dry-run previews everything without changing the filesystem.

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

# Shared safety helpers (do_cmd, canonicalize_path, path_inside,
# restore_latest_backup, remove_dir_if_empty). This script lives in claude/, so
# the lib is one dir up.
COMMON_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/utils/common.sh"
if [ ! -r "$COMMON_LIB" ]; then
	echo_error "Error: required helper library not found at $COMMON_LIB"
	exit 1
fi
# shellcheck source=../utils/common.sh
. "$COMMON_LIB"

# === Options

DRY_RUN=false

usage() {
	cat <<EOF
Usage: $0 [options]

Removes the per-skill symlinks claude/sync-skills.sh created under
~/.claude/skills and ~/.cursor/skills (only those resolving back into this
repo), restores any backups it moved aside, and drops the skill dirs if empty.
Safe to re-run; never touches foreign skills or real files.

Options:
  -n, --dry-run   Show what would happen without changing anything.
  -h, --help      Show this help.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY_RUN=true ;;
		-h|--help) usage; exit 0 ;;
		*) echo_error "Unknown option: $1"; echo ""; usage; exit 1 ;;
	esac
	shift
done

# === Helpers
#
# do_cmd, canonicalize_path, path_inside, restore_latest_backup, and
# remove_dir_if_empty all come from utils/common.sh (sourced above).

# === Resolve DOTFILES_DIR
#
# Same detection logic as install.sh / uninstall.sh / sync-skills.sh: prefer the
# checkout this script runs from (it lives at claude/ under the repo root), fall
# back to the default location, allow an explicit DOTFILES_DIR override.
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
DOTFILES_DIR="$(cd "$DOTFILES_DIR" >/dev/null 2>&1 && pwd -P)"

SKILLS_SRC_DIR="$DOTFILES_DIR/claude/skills"
TARGET_DIRS=("$HOME/.claude/skills" "$HOME/.cursor/skills")

echo ""
echo_success "Removing dqna64 dotfiles skills"
echo_info "Source:   $SKILLS_SRC_DIR"
echo_info "Targets:  ${TARGET_DIRS[*]}"
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

REMOVED=0
RESTORED=0
SKIPPED=0

for target_dir in "${TARGET_DIRS[@]}"; do
	[ -d "$target_dir" ] || continue
	for entry in "$target_dir"/*; do
		[ -L "$entry" ] || continue
		resolved="$(canonicalize_path "$entry")"
		if path_inside "$SKILLS_SRC_DIR" "$resolved"; then
			echo_info "removing $entry -> $resolved"
			do_cmd rm "$entry"
			# assume_free: we just removed the link above (skipped under
			# --dry-run), so the path is free for the restore that follows.
			restore_latest_backup "$entry" true
			REMOVED=$((REMOVED + 1))
		else
			echo_note "skipping $entry: points outside the repo skills dir ($resolved); not ours."
			SKIPPED=$((SKIPPED + 1))
		fi
	done
	remove_dir_if_empty "$target_dir"
done

echo ""
echo_success "Done."
echo_note "  removed:  $REMOVED link(s)"
if [ "$RESTORED" -gt 0 ]; then
	echo_note "  restored: $RESTORED backup(s) moved aside by sync-skills.sh"
fi
if [ "$SKIPPED" -gt 0 ]; then
	echo_note "  skipped:  $SKIPPED foreign link(s) left in place"
fi
