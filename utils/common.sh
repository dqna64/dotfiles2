#!/usr/bin/env bash

# Shared, safety-critical shell helpers for the dotfiles scripts that run from a
# cloned checkout on disk (uninstall.sh, git/git-setup.sh,
# claude/sync-agent-links.sh, claude/unsync-agent-links.sh). Source it via a
# BASH_SOURCE-relative path, e.g.:
#
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils/common.sh"        # repo root
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/utils/common.sh"     # claude/, git/, ...
#
# Deliberately NOT here (kept per-script): the color vars + echo_* helpers and
# install.sh's pre-clone copies. install.sh must stay fully self-contained
# because in a `curl | bash` bootstrap it emits messages BEFORE the repo (and
# hence this file) exists on disk.
#
# Caller contract:
#   - Define the echo_* helpers (echo_info/echo_warn/echo_note/...) before
#     calling any function here that narrates (do_cmd, restore_latest_backup,
#     remove_dir_if_empty, symlink_item, prune_stale_links, unlink_dir_from).
#     They're resolved at call time, so define order relative to this `source`
#     doesn't matter.
#   - `shopt -s nullglob` must be set so the backup glob in restore_latest_backup
#     and the directory globs in prune_stale_links / unlink_dir_from yield an
#     empty list (not a literal '*') when nothing matches.
#   - DRY_RUN gates do_cmd; it defaults to false below if the caller hasn't set
#     it, so a script with no --dry-run still works.

: "${DRY_RUN:=false}"

# dotfiles_backup_path <file>
# The single source of truth for the backup naming scheme. The backup_dqna64
# marker is load-bearing: it's matched by .gitignore and by uninstall.sh's
# restore logic, so every script that moves a user file aside MUST use this
# exact shape. Prints the path; does not touch the filesystem.
dotfiles_backup_path() {
	printf '%s\n' "$1.backup_dqna64.$(date +%Y%m%d%H%M%S)"
}

# do_cmd <command...>
# Run a command, or just print it under --dry-run. Routes all real filesystem
# mutations so dry-run is honored for free.
do_cmd() {
	if [ "$DRY_RUN" = "true" ]; then
		echo_note "  [dry-run] $*"
	else
		"$@"
	fi
}

# canonicalize_path <path>
# Fully resolve <path> to an absolute path, following symlink chains by hand
# (not just one hop) and canonicalising symlinked path components. macOS's stock
# readlink has no portable -f/realpath, so we walk the chain ourselves. Works on
# broken links too, as long as the final target's parent dir exists — enough to
# answer "does this link point into the repo?". The max counter guards against
# symlink loops (ELOOP) so we never hang.
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

# path_inside <parent> <path>
# True if <path> is <parent> or lives under it. Used so we only ever delete
# symlinks that resolve back into a known-safe directory.
path_inside() {
	local parent="$1" p="$2"
	[ "$p" = "$parent" ] || [ "${p#"$parent"/}" != "$p" ]
}

# restore_latest_backup <dst> [assume_free]
# Move the newest <dst>.backup_dqna64.<timestamp> back to <dst>, but only if
# <dst> is now free. Backups sort chronologically (YYYYMMDDHHMMSS), so the
# lexically-last glob match is the most recent. Bumps RESTORED (if used) so
# callers can report a count.
#
# assume_free (default false): the caller already removed (or, under --dry-run,
# would remove) whatever was at <dst>, so the path is about to be free. Only
# honoured under --dry-run, where the rm was skipped and the live check below
# would otherwise see the still-present link and wrongly report "not restoring".
# In a real run the rm already happened, so the live filesystem check stays
# authoritative.
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
	RESTORED=$(( ${RESTORED:-0} + 1 ))

	if [ ${#backups[@]} -gt 1 ]; then
		echo_note "  ($((${#backups[@]} - 1)) older backup(s) for this path left in place.)"
	fi
}

# remove_dir_if_empty <dir>
# rmdir a directory once its expected contents are gone, but only if it's now
# empty. `rmdir` only succeeds on an empty dir, so a dir still holding a leftover
# backup, a foreign file, or a restored real config is left untouched. Symlinked
# dirs are skipped (we don't follow them).
remove_dir_if_empty() {
	local dir="$1"

	[ -d "$dir" ] && [ ! -L "$dir" ] || return 0

	if [ "$DRY_RUN" = "true" ]; then
		# Under --dry-run the contents weren't actually removed, so the dir
		# won't be empty yet; just announce the intent without touching it.
		echo_note "[dry-run] rmdir $dir (only if empty once its contents are gone)"
		return 0
	fi

	if rmdir "$dir" 2>/dev/null; then
		echo_info "Removed now-empty directory $dir"
	fi
}

# === Per-item symlink sync/teardown ===========================================
#
# Building blocks for "mirror a tracked source dir into one or more locations on
# the machine as per-item symlinks, non-destructively, idempotently, and
# reversibly". Used by claude/sync-agent-links.sh + claude/unsync-agent-links.sh.
#
# Scope: these are single-item / single-target-dir primitives, kept free of
# collection framing. The loop over a source dir's contents and the
# per-collection headers/spacing live in the callers (their `*_collection`
# helpers), so presentation stays out of this safety-critical lib. Forward, a
# caller pairs symlink_item (per item) with prune_stale_links (per target dir);
# reverse, it uses unlink_dir_from (per target dir).
#
# Why per-item (not symlinking the whole dir): the targets may already hold
# items installed by hand or by other tools; linking each item lets ours live
# alongside those without clobbering the directory.
#
# "Ours" vs foreign: a link is ours iff it resolves back into <src_root> (the
# tracked dir a collection lives under). Only our links are ever removed or
# re-pointed; real files, dirs, and foreign symlinks are backed up or left be.
#
# Counters (optional): these bump plain globals so callers can print a summary —
# LINKED_NEW / LINKED_OK / RELINKED / BACKED_UP / PRUNED (forward) and REMOVED /
# SKIPPED / RESTORED (reverse). They default to 0 when unset (${VAR:-0}), so a
# caller that doesn't care can ignore them; init them to 0 for a clean summary.
# Requires `shopt -s nullglob` (see contract above) for the directory globs.

# symlink_item <src_root> <src> <dst>
# Idempotently point <dst> at <src> (both absolute). <src_root> is the tracked
# dir the collection lives under, used to recognise links we own. Non-destructive:
# a real file/dir or foreign symlink at <dst> is moved to
# <dst>.backup_dqna64.<timestamp>, never overwritten. A stale link we own is
# re-pointed with no backup.
symlink_item() {
	local src_root="$1" src="$2" dst="$3"

	# Compare fully-resolved paths on both sides so an already-correct link is
	# recognised even when <src> itself is a symlink or has symlinked path
	# components. The link we create still points at the raw <src> (below).
	local src_canon
	src_canon="$(canonicalize_path "$src")"

	do_cmd mkdir -p "$(dirname "$dst")"

	if [ -L "$dst" ] && [ "$(canonicalize_path "$dst")" = "$src_canon" ]; then
		echo "  already linked: $dst"
		LINKED_OK=$(( ${LINKED_OK:-0} + 1 ))
		return 0
	fi

	if [ -L "$dst" ] && path_inside "$src_root" "$(canonicalize_path "$dst")"; then
		# Our own link, but pointing at a different tracked item (shouldn't
		# normally happen for matching names). Re-point it — no backup needed
		# since it's a link we own.
		echo_info "  re-pointing our stale link: $dst"
		do_cmd rm "$dst"
		do_cmd ln -s "$src" "$dst"
		RELINKED=$(( ${RELINKED:-0} + 1 ))
		return 0
	fi

	if [ -e "$dst" ] || [ -L "$dst" ]; then
		# A real file/dir, or a foreign symlink: move aside, never clobber.
		local backup
		backup="$(dotfiles_backup_path "$dst")"
		echo_warn "  backing up existing $dst -> $backup"
		do_cmd mv "$dst" "$backup"
		BACKED_UP=$(( ${BACKED_UP:-0} + 1 ))
	fi

	echo_info "  linking $dst -> $src"
	do_cmd ln -s "$src" "$dst"
	LINKED_NEW=$(( ${LINKED_NEW:-0} + 1 ))
}

# prune_stale_links <src_root> <target_dir>
# Remove symlinks in <target_dir> that resolve into <src_root> but whose target
# no longer exists (renamed/deleted at the source). Foreign links and real files
# are left alone. `-e` covers both directory and file items.
prune_stale_links() {
	local src_root="$1" target_dir="$2" entry resolved
	[ -d "$target_dir" ] || return 0
	for entry in "$target_dir"/*; do
		[ -L "$entry" ] || continue
		resolved="$(canonicalize_path "$entry")"
		path_inside "$src_root" "$resolved" || continue
		if [ ! -e "$resolved" ]; then
			echo_warn "  pruning stale link: $entry -> $resolved (no longer tracked)"
			do_cmd rm "$entry"
			PRUNED=$(( ${PRUNED:-0} + 1 ))
		fi
	done
}

# unlink_dir_from <src_root> <target_dir>
# Reverse of symlink_item across a target dir (the counterpart to
# prune_stale_links): in <target_dir>, drop ONLY the symlinks resolving into
# <src_root> (links we own) and restore any backup we moved aside. Foreign links
# and real files are reported and left in place. The <target_dir> itself is left
# even if it ends up empty — these are typically tool-owned dirs we shouldn't
# reap; call remove_dir_if_empty explicitly if you do want that.
unlink_dir_from() {
	local src_root="$1" target_dir="$2" entry resolved
	[ -d "$target_dir" ] || return 0
	for entry in "$target_dir"/*; do
		[ -L "$entry" ] || continue
		resolved="$(canonicalize_path "$entry")"
		if path_inside "$src_root" "$resolved"; then
			echo_info "  removing $entry -> $resolved"
			do_cmd rm "$entry"
			# assume_free: we just removed the link above (skipped under
			# --dry-run), so the path is free for the restore that follows.
			restore_latest_backup "$entry" true
			REMOVED=$(( ${REMOVED:-0} + 1 ))
		else
			echo_note "  skipping $entry: points outside $src_root ($resolved); not ours."
			SKIPPED=$(( ${SKIPPED:-0} + 1 ))
		fi
	done
}
