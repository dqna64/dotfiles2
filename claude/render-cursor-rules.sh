#!/usr/bin/env bash
#
# Print every dotfiles repo's claude/rules/*.md as one document, for pasting into
# Cursor: Cursor Settings -> Rules -> User Rules. Cursor reads no global rules
# directory (only project .cursor/rules and the settings text box), so this is a
# once-per-machine paste; re-run and re-paste after rules change.
#
# Usage: render-cursor-rules.sh            # to stdout
#        render-cursor-rules.sh | pbcopy   # macOS clipboard

set -euo pipefail
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
. "$DOTFILES_DIR/utils/overlays.sh"

shopt -s nullglob
while IFS= read -r root; do
	for f in "$root"/claude/rules/*.md; do
		printf '<!-- %s -->\n' "${f#"$HOME/"}"
		cat "$f"
		printf '\n'
	done
done < <(dotfiles_roots 2>/dev/null)
