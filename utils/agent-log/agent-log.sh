#!/usr/bin/env bash
#
# Agent activity log - hook entry point for Claude Code and Cursor.
#
# Records one line per *consequential* agent turn into this session's log file
# (one file per session, in the project's logs directory selected by
# log-path.sh); read together, the files are the history that both the user and
# future agents consult.
#
# Invoked from the agents' hook configs as:
#   agent-log.sh <event> <agent>
# with the hook's JSON payload on stdin. <event> is one of the normalised names
# below; the caller maps each agent's native hook name onto them, so nothing
# downstream has to know which agent it came from.
#
#   session-start  Claude SessionStart  / Cursor sessionStart
#   tool           Claude PostToolUse   / Cursor postToolUse
#   response       (Claude: n/a)        / Cursor afterAgentResponse
#   turn-end       Claude Stop          / Cursor stop
#
# Cursor splits what Claude gives in one hook: its `stop` carries no assistant
# text, so the text arrives separately on afterAgentResponse and is stashed for
# the turn-end that follows. Claude's Stop hands over a transcript path instead,
# which the summariser reads the closing message out of.
#
# HOT PATH. `tool` fires on every tool call of every turn and is blocking on
# both agents, so the work here is one jq and one append - process spawns are
# latency the user feels. Everything expensive (the model call, git) is detached
# into summarise.sh. This must also never break a session: it always exits 0 and
# always prints `{}`, since Cursor parses stdout as JSON and treats a crashed
# hook as fail-open.

set -u

# Resolved lazily: the cd/pwd subshells are among the most expensive things
# this script does, and only turn-end (once per turn) needs the path. The
# `tool` event runs orders of magnitude more often and never touches it.
script_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

# Nothing below may take the session down with it. Any unexpected failure
# degrades to "this turn wasn't logged", never to a broken agent.
bail() { printf '{}\n'; exit 0; }
trap bail EXIT

event="${1:-}"
agent="${2:-unknown}"
[ -n "$event" ] || bail

command -v jq >/dev/null 2>&1 || bail

payload="$(cat)"
[ -n "$payload" ] || bail

# The single hot-path jq. Emits the session id on line 1 and, for `tool`, the
# compact event record on line 2. `tojson` keeps the record on one line so the
# split below is a plain shell operation rather than another process.
#
# The record deliberately captures only the *shape* of a call - tool name, file
# path, truncated command. Hook payloads carry whole file contents and raw shell
# commands, and this log is durable and lives inside the user's project, so the
# full arguments are never written. summarise.sh redacts on top of that.
#
# `null`, not `empty`: an `empty` anywhere in an object construction discards
# the entire object, which silently records nothing. Absent keys are dropped
# afterwards instead.
#
# The agent is detected from the payload rather than trusted from $2, because
# the two are not the same thing: Cursor reads ~/.claude/settings.json as a
# third-party config source, so Claude's hook entries fire inside Cursor
# sessions and would otherwise label every one of them "claude".
# `cursor_version` is on every Cursor hook payload and on no Claude one.
extracted="$(printf '%s' "$payload" | jq -r --arg ev "$event" '
	(.session_id // .conversation_id // ""),
	(if (.cursor_version // "") != "" or (.conversation_id // "") != ""
	 then "cursor" else "" end),
	(if $ev == "tool" then
		({ tool: (.tool_name // ""),
		   path: (.tool_input.file_path // .tool_input.path
		          // .tool_input.target_file // null),
		   cmd:  ((.tool_input.command // .command // null)
		          | if type == "string" then .[0:400] else null end) }
		 | with_entries(select(.value != null)) | tojson)
	 else "" end)' 2>/dev/null)"

{
	IFS= read -r session_id
	IFS= read -r detected_agent
	IFS= read -r event_json
} <<< "$extracted"
[ -n "${session_id:-}" ] || bail
# $2 stays the fallback: it's right for a genuine Claude session, where there is
# nothing in the payload to detect.
[ -n "${detected_agent:-}" ] && agent="$detected_agent"

# The directory the *session* belongs to, not wherever a tool happened to run.
# Both agents export this, so the payload fallback costs a second jq only on
# older versions that don't.
project_dir="${CLAUDE_PROJECT_DIR:-${CURSOR_PROJECT_DIR:-}}"
if [ -z "$project_dir" ]; then
	project_dir="$(printf '%s' "$payload" | jq -r '.workspace_roots[0] // .cwd // empty' 2>/dev/null)"
fi
[ -d "$project_dir" ] || bail

# Refuse to treat a non-project as a project. $HOME and / are the accidents that
# matter: a session started in either would otherwise scatter a log across the
# machine, and in $HOME it would sit among the dotfiles it describes.
case "$project_dir" in
	"$HOME"|/) bail ;;
esac

# Per-session scratch, kept outside the project so an abandoned session leaves
# no litter in the user's repo. One directory per session, so concurrent
# sessions in the same project never contend here.
state_dir="${TMPDIR:-/tmp}/agent-log-dqna64/$session_id"

case "$event" in
	session-start)
		mkdir -p "$state_dir" || bail
		printf '0\n' > "$state_dir/turn"
		;;

	tool)
		[ -n "$event_json" ] && [ "$event_json" != "$session_id" ] || bail
		[ -d "$state_dir" ] || mkdir -p "$state_dir" || bail
		printf '%s\n' "$event_json" >> "$state_dir/events.jsonl"
		;;

	response)
		# Cursor only. Held for the turn-end that follows: the agent's closing
		# message states the decisions it made, which is the single most useful
		# input to the summary and costs nothing to collect.
		[ -d "$state_dir" ] || mkdir -p "$state_dir" || bail
		printf '%s' "$payload" | jq -r '.text // empty' > "$state_dir/response.txt" 2>/dev/null
		;;

	turn-end)
		[ -d "$state_dir" ] || bail
		[ -s "$state_dir/events.jsonl" ] || bail

		SCRIPT_DIR="$(script_dir)" || bail

		# The gate. Most turns are questions, searches and test runs that change
		# nothing and are worth neither a model call nor a line in the log.
		if ! "$SCRIPT_DIR/mutation-gate.sh" < "$state_dir/events.jsonl"; then
			rm -f "$state_dir/events.jsonl" "$state_dir/response.txt"
			bail
		fi

		turn=$(( $(cat "$state_dir/turn" 2>/dev/null || echo 0) + 1 ))
		printf '%s\n' "$turn" > "$state_dir/turn"

		# Move this turn's evidence into a private snapshot, so the detached
		# worker reads a stable set of files while the next turn is already
		# writing new ones into the live scratch directory.
		snap="$state_dir/turn-$turn"
		mkdir -p "$snap" || bail
		mv "$state_dir/events.jsonl" "$snap/events.jsonl" 2>/dev/null || bail
		mv "$state_dir/response.txt" "$snap/response.txt" 2>/dev/null || true
		printf '%s' "$payload" | jq -r '.transcript_path // empty' \
			> "$snap/transcript_path" 2>/dev/null || true

		# Detach. Both agents block on this hook and neither documents a
		# background mode, so the model call has to outlive the hook and escape
		# its timeout. stdout must be closed, not merely ignored: Cursor reads
		# until EOF, and an inherited pipe would hold the turn open until the
		# summary finished - exactly the latency this avoids. The subshell is a
		# double fork that reparents the worker to init; setsid would say it
		# more clearly but doesn't exist on macOS.
		(
			nohup "$SCRIPT_DIR/summarise.sh" \
				"$snap" "$project_dir" "$agent" "$session_id" "$turn" \
				>/dev/null 2>&1 < /dev/null &
		) &
		;;
esac

bail
