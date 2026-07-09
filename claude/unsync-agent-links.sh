#!/usr/bin/env bash

# Reverse claude/sync-agent-links.sh: remove the per-item symlinks it created
# under ~/.claude/skills, ~/.cursor/skills, and ~/.claude/output-styles and
# restore anything it moved aside. The target dirs themselves are tool-owned
# (Claude / Cursor manage them), so we leave them in place even if empty.
#
# Run it standalone to opt out of the dotfiles skills / output styles on a
# machine, or let uninstall.sh call it as part of a full uninstall.
#
# Safety model (mirrors sync-agent-links.sh / uninstall.sh):
#   - Only removes symlinks that resolve back into the matching repo source dir
#     (claude/skills or claude/output-styles) — i.e. links we created. Foreign
#     items (e.g. ~/.cursor/skills/ast-grep) and real files/dirs are reported
#     and left untouched.
#   - After removing our link, restores the most recent
#     <dst>.backup_dqna64.<timestamp> if the path is now free, undoing the
#     "moved aside" that sync-agent-links.sh did when something was in the way.
#   - Leaves the target dirs in place regardless: they're owned by Claude /
#     Cursor, not us, so we only remove the individual links we created.
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
# restore_latest_backup). This script lives in claude/, so the lib is one dir
# up.
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

Removes the per-item symlinks claude/sync-agent-links.sh created under
~/.claude/skills, ~/.cursor/skills, and ~/.claude/output-styles (only those
resolving back into this repo) and restores any backups it moved aside. Leaves
the (tool-owned) target dirs in place. Safe to re-run; never touches foreign
items or real files.

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
# The per-target-dir link-removal primitive (unlink_dir_from) lives in
# utils/common.sh (sourced above), alongside do_cmd, canonicalize_path,
# path_inside, and restore_latest_backup; it drops only links resolving into a
# given source dir, restores backups, and bumps the REMOVED/SKIPPED/RESTORED
# counters we report below (leaving tool-owned target dirs in place even if
# emptied). unsync_collection is the script-local orchestrator owning the
# presentation — kept symmetric with sync-agent-links.sh's sync_collection.

# unsync_collection <label> <src_dir> <target_dir>
# Drop our links (those resolving into <src_dir>) from <target_dir> and restore
# backups, via unlink_dir_from. One target dir per call — invoke once per target
# rather than passing a list.
unsync_collection() {
	local label="$1" src_dir="$2" target_dir="$3"

	echo ""
	echo_success "$label -> $target_dir"
	unlink_dir_from "$src_dir" "$target_dir"
}

# === Resolve DOTFILES_DIR
#
# Same detection logic as install.sh / uninstall.sh / sync-agent-links.sh:
# prefer the checkout this script runs from (it lives at claude/ under the repo
# root), fall back to the default location, allow an explicit DOTFILES_DIR
# override.
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
OUTPUT_STYLES_SRC_DIR="$DOTFILES_DIR/claude/output-styles"

echo ""
echo_success "Removing dqna64 dotfiles agent links"
echo_info "Skills source:        $SKILLS_SRC_DIR (~/.claude/skills, ~/.cursor/skills)"
echo_info "Output styles source: $OUTPUT_STYLES_SRC_DIR (~/.claude/output-styles)"
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

REMOVED=0
RESTORED=0
SKIPPED=0

unsync_collection "Agent Skills" "$SKILLS_SRC_DIR" "$HOME/.claude/skills"
unsync_collection "Agent Skills" "$SKILLS_SRC_DIR" "$HOME/.cursor/skills"
unsync_collection "Output styles" "$OUTPUT_STYLES_SRC_DIR" "$HOME/.claude/output-styles"

echo ""
echo_success "Done."
echo_note "  removed:  $REMOVED link(s)"
if [ "$RESTORED" -gt 0 ]; then
	echo_note "  restored: $RESTORED backup(s) moved aside by sync-agent-links.sh"
fi
if [ "$SKIPPED" -gt 0 ]; then
	echo_note "  skipped:  $SKIPPED foreign link(s) left in place"
fi
