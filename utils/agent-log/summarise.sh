#!/usr/bin/env bash
#
# Agent activity log - the detached worker that writes one entry.
#
# Usage (only ever from agent-log.sh, already detached from the agent):
#   summarise.sh <snapshot_dir> <project_dir> <agent> <session_id> <turn>
#
# Turns one turn's evidence into a single JSON line appended to the project's
# log under $AGENT_LOGS. Nothing here is on the agent's hot path, so it can
# afford the model call and the git commands that agent-log.sh avoids.
#
# Concurrency: many of these run at once - several turns of one session, several
# sessions in one project, both agents at the same time - all appending to the
# same file. Safety comes from writing each entry as a single line in a single
# write() call under the filesystem block size, which O_APPEND makes atomic. No
# lock is taken, and none should be: macOS has no flock(1), so any lock-based
# design would need a second implementation per OS. See MAX_LINE below.
#
# Entries can therefore land out of order. That's fine and intended: each entry
# carries its own timestamp and turn index, so the renderer sorts on read.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

snap="${1:-}"
project_dir="${2:-}"
agent="${3:-unknown}"
session_id="${4:-}"
turn="${5:-0}"

[ -n "$snap" ] && [ -d "$snap" ] || exit 0

cleanup() { rm -rf "$snap"; }
trap cleanup EXIT

# A session rooted at $HOME or / isn't working on a project, and logging it
# would produce an entry nobody can act on.
case "$project_dir" in
	"$HOME"|/|"") exit 0 ;;
esac

. "$SCRIPT_DIR/log-path.sh"
log_file="$(agent_log_path "$project_dir")"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || exit 0

# A single entry must stay under the filesystem block size for the atomic append
# above to hold. 4000 bytes is far more than a summary needs and leaves room
# under the 4 KiB floor on both APFS and ext4.
MAX_LINE=4000

# Model calls are the only slow thing here and a hung one would linger forever,
# so cap it. macOS ships no timeout(1) (it's GNU coreutils), hence the poll.
MODEL_TIMEOUT="${AGENT_LOG_TIMEOUT:-90}"

# run_with_timeout <seconds> <command...>
run_with_timeout() {
	local secs="$1"; shift
	"$@" &
	local pid=$! waited=0
	while kill -0 "$pid" 2>/dev/null; do
		[ "$waited" -ge "$secs" ] && { kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
}

# redact <stdin>
# Strip the credential shapes that routinely appear in shell commands. This is
# the last line of defence, not the first: agent-log.sh already records only the
# shape of a tool call. But commands are recorded verbatim up to 400 chars, and
# this file is durable and sits inside the user's project, so anything that
# looks like a secret is masked before it reaches the log or the model.
redact() {
	sed -E \
		-e 's/(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]+/<redacted-token>/g' \
		-e 's/sk-[A-Za-z0-9_-]{16,}/<redacted-token>/g' \
		-e 's/(AKIA|ASIA)[A-Z0-9]{12,}/<redacted-key>/g' \
		-e 's/(xox[abposr]-[A-Za-z0-9-]+)/<redacted-token>/g' \
		-e 's/([Bb]earer[[:space:]]+)[A-Za-z0-9._~+\/-]{12,}=*/\1<redacted>/g' \
		-e 's/(--?(token|password|passwd|pw|secret|api[-_]?key|auth)[ =])[^ ]+/\1<redacted>/gI' \
		-e 's/([A-Z0-9_]*(TOKEN|SECRET|PASSWORD|API_?KEY)[A-Z0-9_]*=)[^ ]+/\1<redacted>/g' \
		-e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----/<redacted-private-key>/g'
}

# === Gather the evidence =====================================================

# Only files inside the project. Stripping the project prefix leaves in-project
# paths relative and everything else still absolute, so dropping the lines that
# still start with `/` filters out the transcripts, skill files and other
# machine paths a turn happened to read - which are not changes to this project
# and only mislead whoever reads the entry later.
files_touched="$(jq -r '.path // empty' "$snap/events.jsonl" 2>/dev/null \
	| sed "s|^$project_dir/||" | grep -v '^/' | sort -u | head -20)"

commands_run="$(jq -r '.cmd // empty' "$snap/events.jsonl" 2>/dev/null \
	| redact | sort -u | head -40)"

tools_used="$(jq -r '.tool // empty' "$snap/events.jsonl" 2>/dev/null \
	| sort | uniq -c | sort -rn | head -15)"

response=""
[ -s "$snap/response.txt" ] && response="$(head -c 4000 "$snap/response.txt" | redact)"

# Claude's Stop hook hands over a transcript path rather than the text itself,
# so the turn's closing message - the agent's own account of what it decided -
# is pulled from the last assistant block.
if [ -z "$response" ] && [ -s "$snap/transcript_path" ]; then
	tpath="$(cat "$snap/transcript_path")"
	if [ -f "$tpath" ]; then
		response="$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$tpath" 2>/dev/null \
			| tail -c 4000 | redact)"
	fi
fi

branch=""; git_stat=""; head_commit=""
if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
	branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
	git_stat="$(git -C "$project_dir" diff --stat HEAD 2>/dev/null | tail -25)"
	head_commit="$(git -C "$project_dir" log -1 --format='%h %s' 2>/dev/null)"
fi

# === Summarise ===============================================================

prompt="You are writing ONE entry in a shared log of what agents have changed in a
software project. Two people read it: a developer skimming a week of work, and
the next agent picking up where this one left off. Both are impatient. Every
word that doesn't change what they do next is noise.

Write ONE line. Add a second or a third ONLY for a genuinely separate fact worth
carrying forward - an approach tried and rejected, a constraint discovered, a
follow-up still owed. Never more than three. Start each with '- '. Keep each
under 120 characters.

- Name the concrete thing: the function, file, behaviour, flag. Never 'updated
  the code' or 'improved handling'.
- Record what the diff cannot show: why this, why not the obvious alternative.
- Do NOT narrate process ('read the file, then edited it', 'ran the tests').
- Do NOT list the files changed. They are recorded separately already.
- Do NOT restate what is plainly visible in the diff.
- No preamble, no headings, no closing remarks. Only the lines.

If this turn changed nothing worth carrying forward - a formatting pass, an
experiment that was reverted, a change with no consequence to anyone reading
later - reply with exactly: NOTHING

--- files touched ---
${files_touched:-(none)}

--- commands run ---
${commands_run:-(none)}

--- tool usage ---
${tools_used:-(none)}

--- working tree vs HEAD ---
${git_stat:-(no changes)}

--- the agent's closing message this turn ---
${response:-(unavailable)}"

summary=""
if command -v claude >/dev/null 2>&1; then
	summary="$(run_with_timeout "$MODEL_TIMEOUT" \
		claude -p --model "${AGENT_LOG_MODEL:-haiku}" "$prompt" 2>/dev/null)"
fi

# The model is given an explicit way to say "this wasn't worth an entry", which
# catches what the mechanical gate can't judge: a formatting-only edit, an
# experiment that was reverted before the turn ended.
if [ "$(printf '%s' "$summary" | tr -d '[:space:]')" = "NOTHING" ]; then
	exit 0
fi

# A failed or absent model call must not lose the turn - fall back to the
# mechanical facts, which are always available. One line, same as a real entry:
# a bullet per file would be exactly the noise the prompt above forbids.
if [ -z "$summary" ]; then
	[ -n "$files_touched" ] || exit 0
	summary="- changed $(printf '%s' "$files_touched" | head -6 | paste -sd', ' -)"
	[ "$(printf '%s\n' "$files_touched" | wc -l)" -gt 6 ] && summary="$summary, …"
fi

# === Append ==================================================================

# `project` is carried on every entry, not just implied by the filename, so that
# entries stay meaningful when logs from several projects are grepped or merged
# together - which is the whole point of keeping them in one directory.
line="$(jq -c -n \
	--arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--arg agent "$agent" \
	--arg session "$session_id" \
	--argjson turn "$turn" \
	--arg machine "$(hostname -s 2>/dev/null || hostname)" \
	--arg project "$project_dir" \
	--arg branch "$branch" \
	--arg commit "$head_commit" \
	--arg summary "$summary" \
	--argjson files "$(printf '%s' "$files_touched" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
	'{ts: $ts, agent: $agent, session: $session, turn: $turn, machine: $machine,
	   project: $project, branch: $branch, commit: $commit,
	   files: $files, summary: $summary}' 2>/dev/null)"

[ -n "$line" ] || exit 0

# Over-long entries are truncated rather than dropped: losing the tail of a
# summary is recoverable, losing atomicity corrupts the whole file for everyone.
if [ "${#line}" -gt "$MAX_LINE" ]; then
	line="$(jq -c '.summary |= .[0:600] | .files |= .[0:12] | .truncated = true' \
		<<< "$line" 2>/dev/null)"
	[ "${#line}" -le "$MAX_LINE" ] || exit 0
fi

# The atomic append. One line, one write(), O_APPEND.
printf '%s\n' "$line" >> "$log_file"
