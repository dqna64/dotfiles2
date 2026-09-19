#!/usr/bin/env bash
#
# Agent activity log - render the JSONL to readable markdown on stdout.
#
# Usage: render.sh [dir] [-n <count>] [-s <session id prefix>] [-a]
#   dir     project to read (default: the git root above $PWD, else $PWD)
#   -n      show only the most recent <count> entries
#   -s      only the session(s) whose id starts with the given prefix
#   -a      every project under the global logs root, merged
#
# Logs are one JSONL file per session, in one directory per project (see
# log-path.sh). That's a write-side layout, not a reading experience, so the
# human view - all sessions merged, oldest first - is generated here.
#
# Entries are sorted on read: detached summarisers finish out of order, so the
# file's line order is arrival order, not event order.

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log-path.sh"

dir=""
count=0
all=false
session=""
while [ $# -gt 0 ]; do
	case "$1" in
		-n) count="${2:-0}"; shift 2 ;;
		-s) session="${2:-}"; shift 2 ;;
		-a|--all) all=true; shift ;;
		-h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) dir="$1"; shift ;;
	esac
done

[ -n "$dir" ] || dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$(agent_project_dir "$dir")"
logs_dir="$(agent_logs_dir "$dir")"

shopt -s nullglob
if [ "$all" = true ]; then
	root="$(agent_logs_global_root)"
	logs=( "$root"/*/*.jsonl )
	[ ${#logs[@]} -gt 0 ] || { printf 'No agent logs under %s\n' "$root" >&2; exit 1; }
	title="All projects"
	subtitle="$root"
else
	logs=( "$logs_dir"/*_"$session"*.jsonl )
	[ ${#logs[@]} -gt 0 ] || { printf 'No agent log for %s\n  (expected files in %s)\n' "$dir" "$logs_dir" >&2; exit 1; }
	title="$(basename "$dir")"
	subtitle="$dir · ${#logs[@]} session(s)"
fi
shopt -u nullglob

entries="$(cat "${logs[@]}" 2>/dev/null | jq -s -c 'sort_by(.ts, .turn)[]' 2>/dev/null || true)"
[ -n "$entries" ] || { printf 'Agent log is empty or unreadable\n' >&2; exit 1; }

[ "$count" -gt 0 ] && entries="$(printf '%s\n' "$entries" | tail -n "$count")"

printf '# %s\n%s · %s entries · summaries are model-written, unverified\n' \
	"$title" "$subtitle" "$(printf '%s\n' "$entries" | wc -l | tr -d ' ')"

# Only worth naming the machine when it isn't this one - on a single-machine
# log it's the same string on every line, which is exactly the chrome that makes
# a log unskimmable.
here="$(hostname -s 2>/dev/null || hostname)"

last_day=""
while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	day="$(printf '%s' "$entry" | jq -r '.ts[0:10]')"
	if [ "$day" != "$last_day" ]; then
		printf '\n## %s\n' "$day"
		last_day="$day"
	fi
	printf '%s' "$entry" | jq -r --arg here "$here" --argjson all "$all" '
		"\n" + .ts[11:16]
		+ " · " + .agent
		# Two path segments, not one: the basename alone is ambiguous across
		# checkouts (canva5/web vs canva7/web) - which is the same collision the
		# log filename has to defend against.
		+ (if $all then " · " + (.project | split("/") | .[-2:] | join("/")) else "" end)
		+ (if (.branch // "") != "" then " · " + .branch else "" end)
		+ (if (.machine // "") != "" and .machine != $here then " · " + .machine else "" end)
		+ "\n" + .summary
		+ (if (.files | length) > 0
		   then "\n  " + (.files[0:6] | join(", "))
		        + (if (.files | length) > 6 then ", +\(.files | length - 6) more" else "" end)
		   else "" end)'
done <<< "$entries"
