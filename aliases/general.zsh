alias ls="ls -hal"

# list files in order of creation
alias lsd='find . -maxdepth 1 -exec stat -f "%B %N" {} + | sort -n | awk '\''{print substr($0, index($0,$2))}'\'' | while IFS= read -r file; do ls -ld "$file" | awk '\''{printf "%-12s %-3s %-3s %-6s %6s %3s %3s %-5s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'\''; done'

function mkcd() {
  mkdir -p "$@" && cd "$_";
}

# SSH into a devbox and attach to a tmux session by prefix.
# Usage: sd <1|2|3> [tmux-session-prefix]
#   1 -> coder.gordnh-devbox-1
#   2 -> main.gordons-devbox-forge.gordonh.coder
#   3 -> main.gordons-qagent-devbox.gordonh.coder
# If no session prefix is given, lists the sessions on the host.
function sd() {
  local host
  case "$1" in
    1) host="coder.gordnh-devbox-1" ;;
    2) host="main.gordons-devbox-forge.gordonh.coder" ;;
    3) host="main.gordons-qagent-devbox.gordonh.coder" ;;
    *) echo "usage: sd <1|2|3> [tmux-session-prefix]" >&2; return 1 ;;
  esac
  if [ -z "$2" ]; then
    ssh -t "$host" 'tmux ls'
    return
  fi
  ssh -t "$host" "tmux attach -t $2"
}

# SP  ' '  0x20 = · U+00B7 Middle Dot
# TAB '\t' 0x09 = ￫ U+FFEB Halfwidth Rightwards Arrow
# CR  '\r' 0x0D = § U+00A7 Section Sign (⏎ U+23CE also works fine)
# LF  '\n' 0x0A = ¶ U+00B6 Pilcrow Sign (was "Paragraph Sign")
alias whitespace="sed 's/ /·/g;s/\t/￫/g;s/\r/§/g;s/$/¶/g'"