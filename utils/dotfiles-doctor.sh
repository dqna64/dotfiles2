#!/usr/bin/env bash
#
# dotfiles-doctor: show how this machine's dotfiles resolve - machine id, every
# repo (base + overlays) with its git state, which repo wins each single-target
# file, every agent link and the repo it points into, collisions, reserved
# paths in overlays. Read-only. Aliased to `dotdoctor`.

set -uo pipefail
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
export DOTFILES_DIR
. "$DOTFILES_DIR/utils/common.sh"
. "$DOTFILES_DIR/utils/overlays.sh"
ZSH_CONFIG_FILE="${ZSH_CONFIG_FILE:-$DOTFILES_DIR/zsh/zsh-config}"
echo_info() { :; }; echo_warn() { :; }; echo_note() { :; }; echo_error() { :; }
shopt -s nullglob

MACHINE="$(dotfiles_machine_id)"
ROOTS=(); while IFS= read -r r; do ROOTS+=("$r"); done < <(dotfiles_roots 2>/dev/null)
problems=0

echo "machine:  ${MACHINE:-<unset>}"
echo "repos (load order):"
while IFS= read -r e; do
	[ -n "$e" ] || continue
	p="$(dotfiles_overlay_path "$e")"
	[ -d "$p" ] || { echo "  MISSING  $(dotfiles_overlay_name "$e")  $p  (run install.sh to clone)"; problems=$((problems+1)); }
done < <(dotfiles_overlay_entries)
for r in "${ROOTS[@]}"; do
	kind="overlay"; [ "$r" = "$DOTFILES_DIR" ] && kind="base"
	state="not a git repo"
	if git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
		branch="$(git -C "$r" branch --show-current 2>/dev/null)"
		dirty=""; [ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ] && dirty=", dirty"
		ab="$(git -C "$r" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo "")"
		if [ -n "$ab" ]; then
			behind="${ab%%[[:space:]]*}"; ahead="${ab##*[[:space:]]}"
			state="$branch, $behind behind / $ahead ahead of upstream (as of last fetch)$dirty"
		else
			state="$branch, no upstream$dirty"
		fi
	fi
	printf '  %-8s %-28s %s  [%s]\n' "$kind" "$(basename "$r")" "$r" "$state"
	for f in $(dotfiles_reserved_paths_in "$r"); do
		[ "$r" != "$DOTFILES_DIR" ] && { echo "           RESERVED (ignored): $f"; problems=$((problems+1)); }
	done
	if [ "$r" != "$DOTFILES_DIR" ]; then
		unread="$(dotfiles_unread_paths_in "$r" | tr '\n' ' ')"
		[ -n "$unread" ] && echo "           not read by the base (info): $unread"
	fi
done

echo "single files:"
for spec in "claude/settings.json:$HOME/.claude/settings.json" "tmux/.tmux.conf:$HOME/.tmux.conf" \
            "karabiner/karabiner.json:$HOME/.config/karabiner/karabiner.json" "yabai/yabairc:$HOME/.config/yabai/yabairc"; do
	rel="${spec%%:*}"; dst="${spec#*:}"
	winner="$(resolve_single "$rel" "$MACHINE" "${ROOTS[@]}" 2>/dev/null)"; rc=$?
	case "$rc" in
		0) w="$winner" ;;
		2) w="COLLISION (run sync/install to see both)"; problems=$((problems+1)) ;;
		*) w="<no repo provides it>" ;;
	esac
	actual="<absent>"
	if [ -L "$dst" ]; then actual="$(readlink "$dst")"; elif [ -e "$dst" ]; then actual="<real file>"; fi
	mark=" "; [ "$actual" != "$w" ] && [ "$rc" -eq 0 ] && mark="*"
	printf '  %s %-26s resolver: %s\n    %-26s actual:   %s\n' "$mark" "$rel" "$w" "" "$actual"
done
echo "  (* = the linked file differs from the resolver's pick; re-run sync-agent-links.sh / install.sh)"

echo "collections:"
for spec in "claude/skills:*/" "claude/output-styles:*.md" "claude/rules:*.md"; do
	out="$(collect_collisions "${spec%%:*}" "${spec#*:}" "${ROOTS[@]}")" || { echo "  COLLISION in ${spec%%:*}: $out"; problems=$((problems+1)); }
done
out="$(collect_collisions bin "*" "${ROOTS[@]}")" || echo "  bin/: same script name in several repos (the later repo's wins on PATH): $out"
for tdir in "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.claude/output-styles" "$HOME/.claude/rules"; do
	[ -d "$tdir" ] || continue
	ours=0 foreign=0 dangling=0
	for entry in "$tdir"/*; do
		if [ -L "$entry" ]; then
			raw="$(readlink "$entry")"
			if [ ! -e "$entry" ]; then dangling=$((dangling+1))
			elif dotfiles_root_of "$raw" "${ROOTS[@]}" >/dev/null; then ours=$((ours+1))
			else foreign=$((foreign+1)); fi
		else foreign=$((foreign+1)); fi
	done
	printf '  %-28s %d from dotfiles, %d other, %d dangling\n' "${tdir#"$HOME/"}" "$ours" "$foreign" "$dangling"
	[ "$dangling" -gt 0 ] && problems=$((problems+1))
done
[ -e "$HOME/.claude/CLAUDE.md" ] && echo "  note: ~/.claude/CLAUDE.md exists; rules in ~/.claude/rules are the dotfiles' mechanism"

echo
if [ "$problems" -eq 0 ]; then echo "ok: no problems found"; else echo "$problems problem(s) flagged above"; fi
