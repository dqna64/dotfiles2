#!/usr/bin/env bash
#
# Agent activity log - the "was this turn worth recording?" gate.
#
# Reads a turn's event records (one JSON object per line, as written by
# agent-log.sh) on stdin. Exits 0 if the turn changed something, 1 if it didn't.
#
# Why gate at all: most turns are questions, searches and test runs that leave
# the project exactly as they found it. Logging those costs a model call each
# and buries the turns that matter under noise, which is the opposite of what
# the log is for. Only turns that mutated something earn an entry.
#
# Direction of error: an unrecognised tool counts as mutating. A stray entry is
# cheap to skim past; a silently missing one makes the log untrustworthy, and a
# log you can't trust is worse than no log. That means new MCP tools are logged
# by default until their name says otherwise - see the read-only name test.
#
# Known gap: a turn whose only outcome is "the tests fail, and here's why"
# changes nothing and so isn't recorded on its own. In practice that finding
# resurfaces in the next turn that acts on it, which is recorded.

set -u

# Tools that read and never write. Matched case-insensitively against the whole
# name, plus the substring test below for the MCP tools we can't enumerate.
#
# `task` is deliberately NOT here. Delegating to a subagent looks like a single
# read-only call from the parent, but the subagent's own tool calls don't reach
# this session's hook - so a turn that hands all its work to a subagent would be
# dropped, and the work would vanish from the log entirely. Counting delegation
# as mutating means the summariser gets the turn and can judge it from the
# parent's closing message, which does describe what the subagent did.
readonly_tools='^(read|read_file|grep|grep_search|glob|glob_file_search|ls|list_dir|codebase_search|semsearch|webfetch|web_search|websearch|fetch_rules|todowrite|todo_write|notebookread|readlints|read_lints|askquestion|getdynamictools)$'

# Read-only shell commands. A turn that only inspects the machine hasn't changed
# it, however many commands it took.
# `tee` and `xargs` are deliberately absent: tee writes, and xargs runs whatever
# it is handed. Both are handled below rather than trusted by name.
readonly_cmds='^(ls|cat|bat|head|tail|less|more|grep|rg|ag|ack|find|fd|wc|pwd|echo|printf|which|type|whereis|file|stat|du|df|tree|jq|yq|sort|uniq|cut|tr|awk|diff|date|printenv|ps|top|whoami|hostname|uname|sleep|true|test|basename|dirname|realpath|readlink|column)$'

# git is the command that most needs splitting by subcommand: `git status` is a
# read, `git commit` is the single most consequential thing a turn can do.
readonly_git='^(status|log|diff|show|blame|branch|remote|rev-parse|rev-list|describe|ls-files|ls-remote|shortlog|reflog|cat-file|show-ref|symbolic-ref|whatchanged|grep|count-objects|var|help)$'

# is_readonly_cmd <shell command string>
# True when every segment of the command line is a read. Pipelines and
# &&/||/; chains are split so that `cat x | tee y` is correctly seen as a write.
is_readonly_cmd() {
	local cmd="$1" segment first sub

	# Normalise the separators into newlines so each stage is tested alone.
	while IFS= read -r segment; do
		segment="${segment#"${segment%%[![:space:]]*}"}"
		[ -n "$segment" ] || continue
		# Word-split deliberately: these are command lines, not paths.
		# shellcheck disable=SC2086
		set -- $segment

		# Peel wrappers until the real program is at $1. Each of these takes
		# another command as its argument, so the verdict belongs to what they
		# run, not to them - `ls | xargs rm` is a delete, not a listing.
		while [ $# -gt 0 ]; do
			case "$(basename "$1")" in
				sudo|command|nohup|time|setsid|stdbuf|env|xargs)
					shift
					while [ $# -gt 0 ]; do
						case "$1" in
							-*|*=*) shift ;;
							*) break ;;
						esac
					done
					;;
				*) break ;;
			esac
		done
		# A bare wrapper with nothing after it (`env`, `xargs`) only prints.
		[ $# -gt 0 ] || continue

		first="$(basename "$1")"

		case "$first" in
			git)
				shift
				# Reach the subcommand past git's global options. -C, -c and the
				# --git-dir family each consume a following argument, so they
				# must be skipped in pairs or `git -C dir log` reads as `dir`.
				while [ $# -gt 0 ]; do
					case "$1" in
						-C|-c|--git-dir|--work-tree|--namespace|--exec-path)
							if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
						-*) shift ;;
						*) break ;;
					esac
				done
				sub="${1:-}"
				printf '%s' "$sub" | grep -Eqi "$readonly_git" || return 1
				;;
			sed|perl|awk)
				# In-place editing turns a filter into a writer.
				printf '%s' "$segment" | grep -Eq -- '(^|[[:space:]])-[a-zA-Z]*i' && return 1
				;;
			*)
				printf '%s' "$first" | grep -Eqi "$readonly_cmds" || return 1
				;;
		esac
	done <<< "$(printf '%s' "$cmd" | tr '\n' ' ' | sed -E 's/(\|\||&&|[|;&])/\n/g')"

	return 0
}

mutating=1

while IFS= read -r line; do
	[ -n "$line" ] || continue

	tool="$(printf '%s' "$line" | jq -r '.tool // empty' 2>/dev/null)"
	cmd="$(printf '%s' "$line" | jq -r '.cmd // empty' 2>/dev/null)"
	[ -n "$tool" ] || continue

	# A shell tool is judged by what it ran, not by its name.
	if [ -n "$cmd" ]; then
		is_readonly_cmd "$cmd" && continue
		mutating=0
		break
	fi

	printf '%s' "$tool" | grep -Eqi "$readonly_tools" && continue

	# MCP and plugin tools can't be enumerated ahead of time, so fall back to
	# what the name claims to do. Anything that reads is skipped; the rest is
	# assumed to act on the world.
	printf '%s' "$tool" | grep -Eqi '(^|_)(read|get|list|search|find|fetch|view|query|describe|show|check|lint)' && continue

	mutating=0
	break
done

exit "$mutating"
