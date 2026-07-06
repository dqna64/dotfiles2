#!/usr/bin/env bash

# Shared, safety-critical shell helpers for the dotfiles scripts that run from a
# cloned checkout on disk (uninstall.sh, git/git-setup.sh, claude/sync-skills.sh,
# claude/unsync-skills.sh). Source it via a BASH_SOURCE-relative path, e.g.:
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
#     remove_dir_if_empty). They're resolved at call time, so define order
#     relative to this `source` doesn't matter.
#   - `shopt -s nullglob` must be set so the backup glob in
#     restore_latest_backup yields an empty list (not a literal '*') when no
#     backups exist.
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
