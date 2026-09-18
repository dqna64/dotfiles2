#!/usr/bin/env bash
#
# Agent activity log - where a project's log file lives.
#
# Sourced by summarise.sh (to write) and render.sh (to read), so the naming
# scheme has one implementation. Deliberately not sourced by agent-log.sh: the
# path is only needed once per turn, and the hot path shouldn't pay to read it.
#
# Follows the same convention as branch-plans: an $AGENT_<THING> env var set in
# zsh/zsh-config, falling back to a ~/.agent/<thing> default so a machine that
# never set the var still works. Plans are keyed by branch; logs by project.

# agent_logs_dir
# The directory all project logs live in.
agent_logs_dir() {
	printf '%s\n' "${AGENT_LOGS:-$HOME/.agent/logs}"
}

# agent_log_path <project_dir>
# The log file for a given project, as <basename>-<checksum>.jsonl.
#
# The basename alone would collide - `canva5/web` and `canva7/web` are different
# projects with the same name - so the absolute path's checksum disambiguates
# while the leading basename keeps the directory readable at a glance. cksum is
# used because it's POSIX: md5, md5sum and shasum are not all present across
# macOS and the Linux devboxes.
agent_log_path() {
	local dir="$1" base sum
	base="$(basename "$dir")"
	sum="$(printf '%s' "$dir" | cksum | awk '{print $1}')"
	printf '%s/%s-%s.jsonl\n' "$(agent_logs_dir)" "$base" "$sum"
}
