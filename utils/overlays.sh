#!/usr/bin/env bash
#
# Extension dotfiles repos ("overlays") - shared resolver for bash scripts and zsh.
#
# An overlay is a second repo with the same layout as this one. The base never
# stores which overlays exist; each machine lists them in its gitignored
# zsh/zsh-config as DOTFILES_OVERLAYS=( entries ), one entry per repo:
#
#   "<clone url>"           cloned by install.sh to $HOME/<repo name>
#   "<clone url>=<path>"    cloned to <path> (absolute; "$HOME/x", not "~/x")
#   "<path>"                an existing local directory; nothing is cloned
#
# Name of an overlay = repo name from the URL (or the directory name for a bare
# path), the same on every machine whatever the folder is called.
#
# Sourceable from bash (install.sh, sync-agent-links.sh, ...) and from zsh
# (.zshrc): only POSIX parameter expansion is used below.

# dotfiles_overlay_entries
# Print the raw entries, one per line. In zsh the array is already in the
# environment (.zshenv sourced zsh-config); bash scripts read zsh-config in a
# throwaway subshell so nothing it exports leaks into the caller.
dotfiles_overlay_entries() {
	if [ -n "${ZSH_VERSION:-}" ]; then
		local e
		for e in "${DOTFILES_OVERLAYS[@]}"; do
			[ -n "$e" ] && printf '%s\n' "$e"
		done
		return 0
	fi
	local cfg="${ZSH_CONFIG_FILE:-${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/zsh/zsh-config}"
	[ -f "$cfg" ] || return 0
	bash -c '. "$1" >/dev/null 2>&1; for e in "${DOTFILES_OVERLAYS[@]}"; do [ -n "$e" ] && printf "%s\n" "$e"; done' _ "$cfg" 2>/dev/null
	return 0
}

# dotfiles_overlay_url <entry>   -> clone url, or empty for a bare local path
dotfiles_overlay_url() {
	local src="${1%%=*}"
	case "$src" in
		/*) printf '\n' ;;
		*) printf '%s\n' "$src" ;;
	esac
}

# dotfiles_overlay_name <entry>  -> repo name (URL/path basename without .git)
dotfiles_overlay_name() {
	local src="${1%%=*}"
	src="${src%/}"
	src="${src%.git}"
	printf '%s\n' "${src##*/}"
}

# dotfiles_overlay_path <entry>  -> local directory (default $HOME/<name>).
# Paths must be absolute; write "$HOME/x" in zsh-config, not "~/x" (a quoted ~
# does not expand).
dotfiles_overlay_path() {
	local e="$1"
	case "$e" in
		*=*) printf '%s\n' "${e#*=}" ;;
		/*) printf '%s\n' "$e" ;;
		*) printf '%s\n' "$HOME/$(dotfiles_overlay_name "$e")" ;;
	esac
}

# dotfiles_roots
# The base repo, then every overlay whose directory exists, one path per line.
# A listed overlay that is not on disk yet is reported on stderr (install.sh
# clones it) and skipped.
dotfiles_roots() {
	printf '%s\n' "${DOTFILES_DIR:-$HOME/dotfiles_dqna64}"
	local e p
	dotfiles_overlay_entries | while IFS= read -r e; do
		p="$(dotfiles_overlay_path "$e")"
		if [ -d "$p" ]; then
			printf '%s\n' "$p"
		else
			printf 'dotfiles: overlay %s not found at %s (run install.sh to clone it)\n' "$(dotfiles_overlay_name "$e")" "$p" >&2
		fi
	done
}

# dotfiles_reserved_paths_in <overlay dir>
# Print any file an overlay carries that the base never reads from overlays.
dotfiles_reserved_paths_in() {
	local root="$1" f
	for f in zsh/.zshrc zsh/.zshenv install.sh uninstall.sh utils; do
		[ -e "$root/$f" ] && printf '%s\n' "$root/$f"
	done
	return 0
}

# dotfiles_unread_paths_in <overlay dir>
# Files in an overlay that the base never reads (unsupported dirs, typos such as
# claude/rule/). Reserved paths are reported separately. Informational.
dotfiles_unread_paths_in() {
	local root="$1" rel
	[ -d "$root" ] || return 0
	( cd "$root" && find . -path ./.git -prune -o \( -type f -o -type l \) -print ) 2>/dev/null | sed 's#^\./##' | sort | while IFS= read -r rel; do
		case "$rel" in
			bin/*|zsh/zshrc.d/*.zsh|zsh/zshrc.d.*/*.zsh) ;;
			claude/skills/*/*|claude/output-styles/*.md|claude/rules/*.md) ;;
			claude/settings.json|claude/settings.*.json) ;;
			tmux/.tmux.conf|tmux/.tmux.*.conf|karabiner/karabiner.json|karabiner/karabiner.*.json|yabai/yabairc|yabai/yabairc.*) ;;
			install.d/*.sh|git/gitconfig.template|git/dqna64-dotfiles.gitconfig|ssh/config.template|ssh/dqna64-dotfiles.conf) ;;
			zsh/.zshrc|zsh/.zshenv|install.sh|uninstall.sh|utils/*) ;;
			.agent_dqna64/*|README*|LICENSE*|CLAUDE.md|AGENTS.md|.gitignore|.gitattributes|.keep|*/.keep) ;;
			*) printf '%s\n' "$rel" ;;
		esac
	done
	return 0
}

# dotfiles_machine_id
# DQNA64_MACHINE as set in zsh-config (already in the environment under zsh).
dotfiles_machine_id() {
	if [ -n "${ZSH_VERSION:-}" ] || [ -n "${DQNA64_MACHINE:-}" ]; then
		printf '%s\n' "${DQNA64_MACHINE:-}"
		return 0
	fi
	local cfg="${ZSH_CONFIG_FILE:-${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/zsh/zsh-config}"
	[ -f "$cfg" ] || return 0
	bash -c '. "$1" >/dev/null 2>&1; printf "%s\n" "${DQNA64_MACHINE:-}"' _ "$cfg" 2>/dev/null
	return 0
}

# dotfiles_root_of <path> <root>...  -> the root that contains <path>
dotfiles_root_of() {
	local p="$1" r; shift
	for r in "$@"; do
		case "$p" in "$r"/*) printf '%s\n' "$r"; return 0 ;; esac
	done
	return 1
}
