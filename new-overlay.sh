#!/usr/bin/env bash
#
# Scaffold an extension dotfiles repo ("overlay"): a second repo with the same
# layout as this one, which the base loads after itself on the machines that
# list it. Nothing in the base changes when you add one.
#
# Usage: new-overlay.sh <path> [--remote <clone url>]
#   <path>     directory to create (its basename is the overlay's name)
#   --remote   origin to set; also the entry to put in zsh-config on each machine
#
# Afterwards: commit and push it, then on every machine that should use it add
# the printed line to zsh/zsh-config (DOTFILES_OVERLAYS) and run install.sh and
# claude/sync-agent-links.sh.

set -euo pipefail

path="" remote=""
while [ $# -gt 0 ]; do
	case "$1" in
		--remote) remote="${2:-}"; shift 2 ;;
		-h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) path="$1"; shift ;;
	esac
done
[ -n "$path" ] || { echo "usage: new-overlay.sh <path> [--remote <clone url>]" >&2; exit 1; }
[ -e "$path" ] && { echo "error: $path already exists" >&2; exit 1; }

name="$(basename "$path")"
mkdir -p "$path"/{bin,zsh/zshrc.d,claude/skills,claude/output-styles,claude/rules,install.d,.agent_dqna64/plans}
: > "$path/bin/.keep"; : > "$path/zsh/zshrc.d/.keep"; : > "$path/claude/skills/.keep"; : > "$path/claude/output-styles/.keep"
: > "$path/claude/rules/.keep"; : > "$path/install.d/.keep"; : > "$path/.agent_dqna64/plans/.keep"

cat > "$path/README.md" <<README
# $name

Extension of my dotfiles (\`dqna64/dotfiles2\`). The base repo loads this one on
the machines that list it in \`zsh/zsh-config\`:

\`\`\`
DOTFILES_OVERLAYS=(
  "${remote:-<clone url>}"
)
\`\`\`

Machines using this repo: <list them>.

Layout and rules: the base README, section "Extension repos (overlays)". In
short: \`bin/\`, \`zsh/zshrc.d*/\`, \`claude/{skills,output-styles,rules}/\` add
to the base (a duplicate name is an error); \`claude/settings.json\`,
\`tmux/.tmux.conf\`, \`karabiner/karabiner.json\`, \`yabai/yabairc\` replace the
base's (a machine variant such as \`settings.<machine>.json\` wins over both);
\`install.d/*.sh\` run on every install; \`git/gitconfig.template\` and
\`ssh/config.template\` are rendered by the base. No secrets: identities stay in
the base's gitignored \`zsh/zsh-config\` / \`git/git-identity\`.
\`dotdoctor\` lists anything here the base does not read.
README

cat > "$path/.gitignore" <<'GI'
*.backup_dqna64.*
.DS_Store
# rendered by the base git-setup.sh from git-identity; never commit
git/dqna64-dotfiles.gitconfig
ssh/dqna64-dotfiles.conf
GI

git -C "$path" init -q
[ -n "$remote" ] && git -C "$path" remote add origin "$remote"
git -C "$path" add -A && git -C "$path" commit -q -m "Scaffold $name dotfiles extension"

echo "Created overlay '$name' at $path"
echo
echo "Next:"
echo "  1. push it:            git -C \"$path\" push -u origin main"
echo "  2. on each machine that should use it, add to zsh/zsh-config:"
echo "       DOTFILES_OVERLAYS=("
echo "         \"${remote:-$path}\""
echo "       )"
echo "  3. run install.sh and claude/sync-agent-links.sh there."
