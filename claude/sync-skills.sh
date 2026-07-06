#!/usr/bin/env bash

# Sync the Agent Skills tracked in this repo (claude/skills/<name>/) into the
# per-user skill dirs that Claude Code and Cursor read from:
#
#   ~/.claude/skills/<name>   ->  $DOTFILES_DIR/claude/skills/<name>
#   ~/.cursor/skills/<name>   ->  $DOTFILES_DIR/claude/skills/<name>
#
# Run this AFTER install.sh (skills aren't installed at install time — you opt
# in by running this), and re-run it any time you add a skill to the repo or
# pull changes on a machine. It's the one command to keep skills in sync across
# every machine these dotfiles live on.
#
# Why per-skill symlinks (not symlinking the whole skills/ dir):
#   ~/.claude/skills and ~/.cursor/skills may already hold skills you installed
#   by hand or that other tools dropped there (e.g. a foreign
#   ~/.cursor/skills/ast-grep). Linking each skill individually lets ours live
#   alongside those without clobbering the directory.
#
# Why symlinks (not copies): editing a skill in the repo — or `git pull`ing an
# update — is instantly reflected on the machine, with nothing to re-copy.
#
# Safety model (mirrors install.sh / uninstall.sh):
#   - Idempotent: re-running converges; links already correct are left alone.
#   - Non-destructive: a real file/dir or a foreign symlink sitting where a
#     skill link should go is moved aside to <dst>.backup_dqna64.<timestamp>,
#     never overwritten. The backup_dqna64 marker is the same one .gitignore and
#     uninstall.sh understand.
#   - Prune is conservative: only symlinks that resolve back into this repo's
#     skills/ dir AND no longer have a matching tracked skill are removed (i.e.
#     skills you renamed or deleted in the repo). Foreign skills are never
#     touched.
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

Symlinks every skill in \$DOTFILES_DIR/claude/skills/ into ~/.claude/skills/
and ~/.cursor/skills/, then prunes our own now-stale skill symlinks. Safe to
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
# do_cmd, canonicalize_path, path_inside, and dotfiles_backup_path come from
# utils/common.sh (sourced above). The skill-specific helpers are below.

# link_skill <src> <dst>
# Idempotently point <dst> at <src> (both absolute). Returns via globals counters.
link_skill() {
	local src="$1" dst="$2"

	do_cmd mkdir -p "$(dirname "$dst")"

	if [ -L "$dst" ] && [ "$(canonicalize_path "$dst")" = "$src" ]; then
		echo "  already linked: $dst"
		LINKED_OK=$((LINKED_OK + 1))
		return 0
	fi

	if [ -L "$dst" ] && path_inside "$SKILLS_SRC_DIR" "$(canonicalize_path "$dst")"; then
		# Our own link, but pointing at a different repo skill (shouldn't
		# normally happen for matching names). Re-point it — no backup needed
		# since it's a link we own.
		echo_info "  re-pointing our stale link: $dst"
		do_cmd rm "$dst"
		do_cmd ln -s "$src" "$dst"
		RELINKED=$((RELINKED + 1))
		return 0
	fi

	if [ -e "$dst" ] || [ -L "$dst" ]; then
		# A real file/dir, or a foreign symlink: move aside, never clobber.
		local backup
		backup="$(dotfiles_backup_path "$dst")"
		echo_warn "  backing up existing $dst -> $backup"
		do_cmd mv "$dst" "$backup"
		BACKED_UP=$((BACKED_UP + 1))
	fi

	echo_info "  linking $dst -> $src"
	do_cmd ln -s "$src" "$dst"
	LINKED_NEW=$((LINKED_NEW + 1))
}

# prune_stale <target_dir>
# Remove symlinks in <target_dir> that resolve into this repo's skills/ dir but
# whose target skill no longer exists (renamed/deleted in the repo). Foreign
# links and real files are left alone.
prune_stale() {
	local target_dir="$1" entry resolved
	[ -d "$target_dir" ] || return 0
	for entry in "$target_dir"/*; do
		[ -L "$entry" ] || continue
		resolved="$(canonicalize_path "$entry")"
		path_inside "$SKILLS_SRC_DIR" "$resolved" || continue
		if [ ! -d "$resolved" ]; then
			echo_warn "  pruning stale skill link: $entry -> $resolved (no longer in repo)"
			do_cmd rm "$entry"
			PRUNED=$((PRUNED + 1))
		fi
	done
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
TARGET_DIRS=("$HOME/.claude/skills" "$HOME/.cursor/skills")

if [ ! -d "$SKILLS_SRC_DIR" ]; then
	echo_error "Error: no skills dir at $SKILLS_SRC_DIR."
	exit 1
fi

echo ""
echo_success "Syncing dqna64 dotfiles skills"
echo_info "Source:   $SKILLS_SRC_DIR"
echo_info "Targets:  ${TARGET_DIRS[*]}"
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

LINKED_NEW=0
LINKED_OK=0
RELINKED=0
BACKED_UP=0
PRUNED=0

# === Link every tracked skill into each target dir

skills=("$SKILLS_SRC_DIR"/*/)
if [ ${#skills[@]} -eq 0 ]; then
	echo_warn "No skills found in $SKILLS_SRC_DIR; nothing to link."
else
	for skill in "${skills[@]}"; do
		skill="${skill%/}"
		name="$(basename "$skill")"
		echo ""
		echo_info "$name"
		for target_dir in "${TARGET_DIRS[@]}"; do
			link_skill "$skill" "$target_dir/$name"
		done
	done
fi

# === Prune our own now-stale links (skills removed/renamed in the repo)

echo ""
echo_info "Pruning stale skill links that resolve into the repo..."
for target_dir in "${TARGET_DIRS[@]}"; do
	prune_stale "$target_dir"
done

# === Summary

echo ""
echo_success "Done."
echo_note "  linked:        $LINKED_NEW new, $LINKED_OK already correct"
[ "$RELINKED" -gt 0 ] && echo_note "  re-pointed:    $RELINKED"
[ "$BACKED_UP" -gt 0 ] && echo_warn  "  backed up:     $BACKED_UP existing item(s) moved aside (*.backup_dqna64.*)"
[ "$PRUNED" -gt 0 ] && echo_note "  pruned:        $PRUNED stale link(s)"
echo_note "  Re-run this after adding skills or 'git pull'. Skill edits/pulls need no re-run (symlinks point at the repo)."
