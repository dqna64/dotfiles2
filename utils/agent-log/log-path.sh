#!/usr/bin/env bash
#
# Agent activity log - where a project's log files live.
#
# Sourced by summarise.sh (to write) and render.sh (to read), so the naming
# scheme has one implementation. Deliberately not sourced by agent-log.sh: the
# path is only needed once per turn, and the hot path shouldn't pay to read it.
#
# Layout: one directory per project, one file per agent session inside it.
#
#   <logs dir>/<start>_<machine>_<agent>_<session id>.jsonl
#   e.g. 20260919T025400Z_dvbx5_claude_097bebc6-89df-4107-a807-15b9b47742c4.jsonl
#
# The session id is the agent's own id (the one `claude --resume <id>` takes),
# so a log file can be traced back to, and the session restarted from, the id
# in its name. One file per session means no two writers ever share a file:
# not two sessions on one machine, not two machines committing the same repo.
# The renderer merges files on read and sorts by timestamp.
#
# The project's logs directory follows the branch-plans hierarchy:
#   1. <git root>/.agent_dqna64/logs/   when the project has a .agent_dqna64/
#      directory (plans or logs) - committed with the project, like plans.
#   2. $AGENT_LOGS/<slug>/              the user's own logs root, one folder per
#   3. ~/.agent/logs/<slug>/            project; <slug> is the absolute git-root
#      path with '/' replaced by '-' (the same scheme Claude Code uses under
#      ~/.claude/projects/), so canva5/web and canva7/web never collide.

# agent_project_dir <dir>
# Resolve a session directory to its git root, or its physical path outside git.
agent_project_dir() {
	local dir="$1" root
	root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" && {
		printf '%s\n' "$root"
		return
	}
	(cd "$dir" 2>/dev/null && pwd -P)
}

# agent_project_slug <project_dir>
agent_project_slug() {
	printf '%s\n' "$1" | sed 's#/#-#g'
}

# agent_logs_global_root
# The user's logs root outside any project: $AGENT_LOGS, else ~/.agent/logs.
agent_logs_global_root() {
	if [ -n "${AGENT_LOGS:-}" ]; then
		printf '%s\n' "${AGENT_LOGS%/}"
	else
		printf '%s\n' "$HOME/.agent/logs"
	fi
}

# agent_logs_dir [project_dir]
# This project's logs directory (may not exist yet; the writer creates it).
agent_logs_dir() {
	local project_dir="${1:-$PWD}" root
	root="$(agent_project_dir "$project_dir")" || return 1

	if [ -d "$root/.agent_dqna64" ]; then
		printf '%s/.agent_dqna64/logs\n' "$root"
		return
	fi
	printf '%s/%s\n' "$(agent_logs_global_root)" "$(agent_project_slug "$root")"
}

# agent_session_log_path <project_dir> <agent> <session_id>
# The log file for one session of one project. Reuses the session's existing
# file (found by its id suffix) so every turn of a session lands in one file;
# otherwise names a new one with the current UTC time as its start.
agent_session_log_path() {
	local project_dir="$1" agent="${2:-unknown}" session_id="$3" dir existing machine start
	dir="$(agent_logs_dir "$project_dir")" || return 1
	session_id="${session_id//\//_}"
	agent="${agent//\//_}"
	if [ -d "$dir" ]; then
		for existing in "$dir"/*_"$session_id".jsonl; do
			if [ -e "$existing" ]; then
				printf '%s\n' "$existing"
				return
			fi
		done
	fi
	machine="$(hostname -s 2>/dev/null || hostname)"
	start="$(date -u +%Y%m%dT%H%M%SZ)"
	printf '%s/%s_%s_%s_%s.jsonl\n' "$dir" "$start" "${machine//_/-}" "$agent" "$session_id"
}
