#!/usr/bin/env bash

# Sync the per-user agent config tracked in this repo into the dirs Claude Code
# and Cursor read from, one item at a time. Two collections are handled:
#
#   Agent Skills (directories):
#     ~/.claude/skills/<name>          ->  $DOTFILES_DIR/claude/skills/<name>
#     ~/.cursor/skills/<name>          ->  $DOTFILES_DIR/claude/skills/<name>
#
#   Output styles (files):
#     ~/.claude/output-styles/<file>   ->  $DOTFILES_DIR/claude/output-styles/<file>
#
# Run this AFTER install.sh (these aren't installed at install time — you opt in
# by running this), and re-run it any time you add/remove an item in the repo or
# pull changes on a machine. It's the one command to keep both agents' skills and
# output styles in sync across every machine these dotfiles live on.
#
# Why per-item symlinks (not symlinking the whole skills/ or output-styles/ dir):
#   ~/.claude/skills, ~/.cursor/skills, and ~/.claude/output-styles may already
#   hold items you installed by hand or that other tools dropped there (e.g. a
#   foreign ~/.cursor/skills/ast-grep, or an output style you authored locally).
#   Linking each item individually lets ours live alongside those without
#   clobbering the directory.
#
# Why symlinks (not copies): editing an item in the repo — or `git pull`ing an
# update — is instantly reflected on the machine, with nothing to re-copy.
#
# Safety model (mirrors install.sh / uninstall.sh):
#   - Idempotent: re-running converges; links already correct are left alone.
#   - Non-destructive: a real file/dir or a foreign symlink sitting where a
#     link should go is moved aside to <dst>.backup_dqna64.<timestamp>, never
#     overwritten. The backup_dqna64 marker is the same one .gitignore and
#     uninstall.sh understand.
#   - Prune is conservative: only symlinks that resolve back into the matching
#     repo source dir AND no longer have a tracked item are removed (i.e. items
#     you renamed or deleted in the repo). Foreign items are never touched.
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
# dotfiles_backup_path). This script lives in claude/, so the lib is one dir up.
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

Symlinks every skill in \$DOTFILES_DIR/claude/skills/ into ~/.claude/skills/ and
~/.cursor/skills/, and every output style in \$DOTFILES_DIR/claude/output-styles/
into ~/.claude/output-styles/, then prunes our own now-stale links. Safe to
re-run; non-destructive to anything not tracked by these dotfiles.

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
# The per-item link + prune primitives (symlink_item, prune_stale_links) live in
# utils/common.sh (sourced above), alongside do_cmd, canonicalize_path,
# path_inside, and dotfiles_backup_path; they bump the LINKED_*/RELINKED/
# BACKED_UP/PRUNED counters we init and report below. sync_collection is the
# script-local orchestrator: it owns the globbing and the presentation (per-
# collection header, spacing) so that stays out of the shared lib. Kept symmetric
# with unsync-agent-links.sh's unsync_collection.

# sync_collection <label> <src_dir> <glob> <target_dir>
# Link every item matching <src_dir>/<glob> into <target_dir> (via symlink_item),
# then prune our own now-stale links there. <glob> is expanded UNQUOTED (nullglob
# set), so "*/" yields directories and "*.md" yields files. One target dir per
# call — invoke once per target rather than passing a list.
sync_collection() {
	local label="$1" src_dir="$2" glob="$3" target_dir="$4"

	echo ""
	echo_success "$label -> $target_dir"
	if [ ! -d "$src_dir" ]; then
		echo_warn "  no source dir at $src_dir; skipping."
		return 0
	fi

	local entries=("$src_dir"/$glob)
	if [ ${#entries[@]} -eq 0 ]; then
		echo_warn "  none found in $src_dir; nothing to link."
	else
		local entry name
		for entry in "${entries[@]}"; do
			entry="${entry%/}"
			name="$(basename "$entry")"
			symlink_item "$src_dir" "$entry" "$target_dir/$name"
		done
	fi

	echo_info "  Pruning stale links that resolve into $src_dir..."
	prune_stale_links "$src_dir" "$target_dir"
}

# === Resolve DOTFILES_DIR
#
# Same detection logic as install.sh / uninstall.sh: prefer the checkout this
# script runs from (it lives at claude/ under the repo root), fall back to the
# default location, allow an explicit DOTFILES_DIR override.
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
echo_success "Syncing dqna64 dotfiles agent links"
echo_info "Skills source:        $SKILLS_SRC_DIR -> ~/.claude/skills, ~/.cursor/skills"
echo_info "Output styles source: $OUTPUT_STYLES_SRC_DIR -> ~/.claude/output-styles"
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

LINKED_NEW=0
LINKED_OK=0
RELINKED=0
BACKED_UP=0
PRUNED=0

# === Sync each collection
#
# Skills are directories linked into both agents; output styles are files linked
# into Claude Code only (Cursor has no equivalent output-styles dir). One call
# per target dir.
sync_collection "Agent Skills" "$SKILLS_SRC_DIR" "*/" "$HOME/.claude/skills"
sync_collection "Agent Skills" "$SKILLS_SRC_DIR" "*/" "$HOME/.cursor/skills"
sync_collection "Output styles" "$OUTPUT_STYLES_SRC_DIR" "*.md" "$HOME/.claude/output-styles"

# === Summary

echo ""
echo_success "Done."
echo_note "  linked:        $LINKED_NEW new, $LINKED_OK already correct"
[ "$RELINKED" -gt 0 ] && echo_note "  re-pointed:    $RELINKED"
[ "$BACKED_UP" -gt 0 ] && echo_warn  "  backed up:     $BACKED_UP existing item(s) moved aside (*.backup_dqna64.*)"
[ "$PRUNED" -gt 0 ] && echo_note "  pruned:        $PRUNED stale link(s)"
echo_note "  Re-run this after adding items or 'git pull'. Edits/pulls need no re-run (symlinks point at the repo)."
