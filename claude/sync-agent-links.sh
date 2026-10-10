#!/usr/bin/env bash

# Sync the per-user agent config tracked in this repo AND in every extension repo
# (overlay) listed in zsh-config into the dirs Claude Code and Cursor read from,
# one item at a time. Three collections are handled, from each repo root:
#
#   Agent Skills (directories):
#     ~/.claude/skills/<name>          ->  <root>/claude/skills/<name>
#     ~/.cursor/skills/<name>          ->  <root>/claude/skills/<name>
#
#   Output styles (files):
#     ~/.claude/output-styles/<file>   ->  <root>/claude/output-styles/<file>
#
#   Claude rules (files; replace the old single ~/.claude/CLAUDE.md):
#     ~/.claude/rules/<file>           ->  <root>/claude/rules/<file>
#
# Plus one single-target file: ~/.claude/settings.json -> the winning
# claude/settings[.<machine>].json across repos (utils/common.sh resolve_single).
# Cursor has no global rules directory; claude/render-cursor-rules.sh prints the
# rules for pasting into Cursor's User Rules instead.
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
# Safety model:
#   - Idempotent: re-running converges; links already correct are left alone.
#   - Non-destructive: a real file/dir or a foreign symlink sitting where a
#     link should go is skipped with a warning and left intact.
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
	CYAN='\033[36m'
	BOLD='\033[1m'
	RESET='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	CYAN=''
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
	echo -e "${CYAN}$*${RESET}"
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

From the base repo and every extension repo listed in zsh-config
(DOTFILES_OVERLAYS), symlinks each item of these collections, then prunes our own
now-stale links:
  claude/skills/<name>       -> ~/.claude/skills, ~/.cursor/skills
  claude/output-styles/*.md  -> ~/.claude/output-styles
  claude/rules/*.md          -> ~/.claude/rules
and links ~/.claude/settings.json to the winning claude/settings[.<machine>].json
(a real file there is left alone). The same item name in two repos is an error;
nothing is linked until it is resolved. Safe to re-run; non-destructive to
anything not tracked by these dotfiles.

Exit status: 0 when every item is linked; 2 when some were skipped because an
item already existed (see the warnings); 1 on error.

Options:
  -n, --dry-run          Show what would happen without changing anything.
  -h, --help             Show this help.
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
# symlink_item and prune_stale_links come from utils/common.sh and bump the
# LINKED_*/RELINKED/CONFLICTS/PRUNED counters reported below. sync_collection
# owns the globbing and presentation, mirroring unsync_collection.

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
	prune_stale_links "$src_dir" "$target_dir" "/claude/${src_dir##*/claude/}/"
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
export DOTFILES_DIR

# === Roots: the base repo plus every overlay on disk (utils/overlays.sh)
# shellcheck source=../utils/overlays.sh
. "$DOTFILES_DIR/utils/overlays.sh"
ZSH_CONFIG_FILE="$DOTFILES_DIR/zsh/zsh-config"
ROOTS=()
while IFS= read -r r; do ROOTS+=("$r"); done < <(dotfiles_roots)
MACHINE="$(dotfiles_machine_id)"

echo ""
echo_success "Syncing dqna64 dotfiles agent links"
echo_info "Machine: ${MACHINE:-<unset>}"
for r in "${ROOTS[@]}"; do
	if [ "$r" = "$DOTFILES_DIR" ]; then echo_info "Root (base):    $r"; else echo_info "Root (overlay): $r"; fi
done
[ "$DRY_RUN" = "true" ] && echo_warn "DRY RUN: no changes will be made."

# === Collision check: the same item name in two repos is an error, not a
# silent last-wins. Nothing is linked until it is resolved.
collisions=""
for spec in "claude/skills:*/" "claude/output-styles:*.md" "claude/rules:*.md"; do
	out="$(collect_collisions "${spec%%:*}" "${spec#*:}" "${ROOTS[@]}" || true)"
	[ -n "$out" ] && collisions="$collisions${spec%%:*}: $out"$'\n'
done
if [ -n "$collisions" ]; then
	echo_error "Refusing to sync: the same item is provided by more than one repo."
	printf '%s' "$collisions" | sed 's/^/  /' >&2
	echo_note "Rename or remove one copy (an overlay adds items; it never overrides the base)."
	exit 1
fi

LINKED_NEW=0
LINKED_OK=0
RELINKED=0
CONFLICTS=0
PRUNED=0

# === Legacy single-file links from before claude/rules existed
# ~/.claude/CLAUDE.md and ~/.cursor/rules/claude.mdc used to point at
# claude/CLAUDE.*.md in this repo. Those files are gone (rules replace them).
# Nothing here is removed, even a dangling link: the user decides (Gordon,
# 2026-10-10). unsync-agent-links.sh removes links into the repos on uninstall.
for legacy in "$HOME/.claude/CLAUDE.md" "$HOME/.cursor/rules/claude.mdc"; do
	[ -e "$legacy" ] || [ -L "$legacy" ] || continue
	if [ -L "$legacy" ] && [ ! -e "$legacy" ]; then
		echo_warn "  $legacy is a dangling link -> $(readlink "$legacy"); claude/rules/ replaced it. Remove it by hand if unwanted."
	elif [ -L "$legacy" ]; then
		echo_note "  $legacy -> $(readlink "$legacy") exists; the dotfiles use ~/.claude/rules/ instead and leave it alone."
	else
		echo_note "  $legacy exists (your own file); the dotfiles use ~/.claude/rules/ and leave it alone."
	fi
done

# === Sync each collection from every root
#
# Skills are directories linked into both agents; output styles and rules are
# files linked into Claude Code only. One call per (root, target dir).
for r in "${ROOTS[@]}"; do
	label="$(basename "$r")"
	sync_collection "Agent Skills [$label]" "$r/claude/skills" "*/" "$HOME/.claude/skills"
	sync_collection "Agent Skills [$label]" "$r/claude/skills" "*/" "$HOME/.cursor/skills"
	sync_collection "Output styles [$label]" "$r/claude/output-styles" "*.md" "$HOME/.claude/output-styles"
	sync_collection "Claude rules [$label]" "$r/claude/rules" "*.md" "$HOME/.claude/rules"
done

# === ~/.claude/settings.json: one file, one winner
#
# Most specific wins: claude/settings.<machine>.json in any repo, else
# claude/settings.json in an overlay, else claude/settings.json in the base.
# A real (non-link) file is yours and is left alone.
echo ""
echo_success "Claude settings -> $HOME/.claude/settings.json"
settings_dst="$HOME/.claude/settings.json"
set +e
winner="$(resolve_single "claude/settings.json" "$MACHINE" "${ROOTS[@]}")"
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
	echo_error "  collision between repos for claude/settings.json (see above); not touching $settings_dst."
	exit 1
elif [ "$rc" -ne 0 ]; then
	echo_note "  no claude/settings[.<machine>].json in any repo; leaving $settings_dst alone."
else
	winner_root="$(dotfiles_root_of "$winner" "${ROOTS[@]}")"
	if [ -L "$settings_dst" ] && [ "$(canonicalize_path "$settings_dst")" = "$(canonicalize_path "$winner")" ]; then
		echo "  already linked: $settings_dst -> $winner"
		LINKED_OK=$((LINKED_OK + 1))
	elif [ -e "$settings_dst" ] && [ ! -L "$settings_dst" ]; then
		echo_note "  $settings_dst is a real file (yours); not replacing it. Resolver's pick: $winner"
	else
		symlink_item "$winner_root" "$winner" "$settings_dst"
	fi
fi

# === Summary

echo ""
echo_success "Done."
echo_note "  linked:        $LINKED_NEW new, $LINKED_OK already correct"
[ "$RELINKED" -gt 0 ] && echo_note "  re-pointed:    $RELINKED"
[ "$CONFLICTS" -gt 0 ] && echo_warn  "  skipped:       $CONFLICTS existing item(s) left in place (see warnings above)"
[ "$PRUNED" -gt 0 ] && echo_note "  pruned:        $PRUNED stale link(s)"
echo_note "  Cursor has no global rules dir: paste  claude/render-cursor-rules.sh  output into Cursor > Settings > Rules once."
echo_note "  Re-run this after adding items or 'git pull'. Edits/pulls need no re-run (symlinks point at the repos)."

# Distinct from 1 (error) so a caller can tell "partially synced" from "failed".
[ "$CONFLICTS" -eq 0 ] || exit 2
