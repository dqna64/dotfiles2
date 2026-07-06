#!/usr/bin/env bash

# Warn at interactive shell startup when a local git clone has fallen behind its
# upstream, so you remember to `git pull`. Used by zsh/.zshrc for $CANVA_DOCU
# (the local clone of the Canva documentation repo), but deliberately generic:
# point it at any clone.
#
# Usage: check-repo-freshness.sh <repo_path> <label>
#   <repo_path>  path to the local clone (e.g. "$CANVA_DOCU")
#   <label>      friendly name shown in the warning (e.g. "Canva docs")
#
# Design (why it's safe on the shell-startup hot path):
#   - The "behind upstream" check is purely LOCAL: it compares HEAD to the
#     remote-tracking ref left by the last fetch. No network on the hot path,
#     so it never slows the prompt.
#   - The `git fetch` that refreshes those remote-tracking refs runs in the
#     BACKGROUND and is THROTTLED to at most once per interval (default 6h),
#     so we stay reasonably fresh without blocking startup or hammering the
#     network. The fetch refreshes refs for the *next* shell's comparison.
#   - Every "not applicable" case (path unset / missing / not a git repo / no
#     upstream / offline) exits 0 SILENTLY, so a machine that doesn't have the
#     repo, or is offline, never spams the prompt.

set -u

repo="${1:-}"
label="${2:-${repo:-repo}}"

[ -n "$repo" ] || exit 0
# The repo may simply not be cloned on this machine: stay silent.
[ -d "$repo" ] || exit 0
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# How often to refresh remote-tracking refs with a background fetch (seconds).
: "${REPO_FRESHNESS_FETCH_INTERVAL:=21600}" # 6h

# Throttle marker holding the epoch of our last background fetch for this repo.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dqna64/repo-freshness"
# Turn the repo path into a flat, filesystem-safe stamp filename.
stamp_key="$(printf '%s' "$repo" | tr -c 'A-Za-z0-9._-' '_')"
stamp="$cache_dir/$stamp_key.stamp"

now="$(date +%s)"
last=0
[ -f "$stamp" ] && last="$(cat "$stamp" 2>/dev/null || echo 0)"
case "$last" in '' | *[!0-9]*) last=0 ;; esac

if [ "$((now - last))" -ge "$REPO_FRESHNESS_FETCH_INTERVAL" ]; then
	mkdir -p "$cache_dir" 2>/dev/null || true
	# Stamp BEFORE fetching so an offline failure doesn't retry every shell;
	# we just try again after the interval.
	printf '%s\n' "$now" >"$stamp" 2>/dev/null || true
	# Detached, silent, non-interactive: BatchMode/ConnectTimeout + no terminal
	# prompt make it fail fast instead of hanging when offline or unauthorized.
	# `|| true` so a failed fetch is harmless. Orphaned on script exit (the
	# parent shell doesn't HUP it), so startup isn't blocked on the network.
	(
		GIT_TERMINAL_PROMPT=0 \
			GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5' \
			git -C "$repo" fetch --quiet >/dev/null 2>&1 || true
	) &
fi

# Skip silently if there's no upstream (detached HEAD / local-only branch).
upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || exit 0
[ -n "$upstream" ] || exit 0

# rev-list --left-right --count HEAD...@{u} prints "<ahead>\t<behind>".
counts="$(git -C "$repo" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null)" || exit 0
behind="$(printf '%s' "$counts" | awk '{print $2}')"
case "$behind" in '' | *[!0-9]*) behind=0 ;; esac

[ "$behind" -gt 0 ] || exit 0

# Yellow on a terminal; plain otherwise (e.g. captured into a log).
if [ -t 2 ]; then y=$'\033[33m'; r=$'\033[0m'; else y=''; r=''; fi
printf '%swarning: %s (%s) is %s commit(s) behind %s.\n' "$y" "$label" "$repo" "$behind" "$upstream" >&2
printf '         Run: git -C %s pull%s\n' "$repo" "$r" >&2

exit 0
