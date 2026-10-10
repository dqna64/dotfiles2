alias ls="ls -hal"

# list files in order of creation
alias lsd='find . -maxdepth 1 -exec stat -f "%B %N" {} + | sort -n | awk '\''{print substr($0, index($0,$2))}'\'' | while IFS= read -r file; do ls -ld "$file" | awk '\''{printf "%-12s %-3s %-3s %-6s %6s %3s %3s %-5s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'\''; done'

function mkcd() {
  mkdir -p "$@" && cd "$_";
}

# Attach to tmux and immediately open the session/window tree picker.
alias tmls='tmux attach \; choose-tree -s'

# Read this project's agent activity log - what Claude/Cursor sessions have
# changed here, newest last. `agentlog -n 20` for just the recent entries.
# Stored as JSONL (many sessions append to it at once); this renders it.
alias agentlog='"${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/utils/agent-log/render.sh"'

# SP  ' '  0x20 = · U+00B7 Middle Dot
# TAB '\t' 0x09 = ￫ U+FFEB Halfwidth Rightwards Arrow
# CR  '\r' 0x0D = § U+00A7 Section Sign (⏎ U+23CE also works fine)
# LF  '\n' 0x0A = ¶ U+00B6 Pilcrow Sign (was "Paragraph Sign")
alias whitespace="sed 's/ /·/g;s/\t/￫/g;s/\r/§/g;s/$/¶/g'"

# Dotfiles across the base repo and every extension repo (overlay).
# dotpull:   pull each repo (fast-forward only), base first.
# dotdoctor: show machine id, repos, which repo wins each single file, links.
dotpull() {
  local root
  for root in ${(f)"$(dotfiles_roots)"}; do
    echo "== $root"
    git -C "$root" pull --ff-only || echo "   (pull failed; resolve by hand)"
  done
}
alias dotdoctor='"${DOTFILES_DIR:-$HOME/dotfiles_dqna64}/utils/dotfiles-doctor.sh"'
