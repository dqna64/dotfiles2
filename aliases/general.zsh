alias ls="ls -hal"

# list files in order of creation
alias lsd='find . -maxdepth 1 -exec stat -f "%B %N" {} + | sort -n | awk '\''{print substr($0, index($0,$2))}'\'' | while IFS= read -r file; do ls -ld "$file" | awk '\''{printf "%-12s %-3s %-3s %-6s %6s %3s %3s %-5s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'\''; done'

function mkcd() {
  mkdir -p "$@" && cd "$_";
}

# SSH into a devbox and attach to a tmux session by prefix.
# Usage: sd <1|2|3|4|5> [tmux-session-prefix]
#   1 -> coder.gordnh-devbox-1
#   2 -> main.gordons-devbox-forge.gordonh.coder
#   3 -> main.gordons-qagent-devbox.gordonh.coder
#   4 -> gordons-dvbx4.coder
#   5 -> (no host yet)
# If no session prefix is given, lists the sessions on the host and replaces
# the remote shell with an interactive shell.
# If a session prefix is given, attempts to attach to the session.
# Example:
# $ sd 1 main- # ssh into devbox 1, attempt attach to tmux session
#   # whose name starts with "main-"
function sd() {
  local host
  case "$1" in
    1) host="coder.gordnh-devbox-1" ;;
    2) host="main.gordons-devbox-forge.gordonh.coder" ;;
    3) host="main.gordons-qagent-devbox.gordonh.coder" ;;
    4) host="gordons-dvbx4.coder" ;;
    5) echo "sd: no host configured for devbox 5 yet" >&2; return 1 ;;
    *) echo "usage: sd <1|2|3|4|5> [tmux-session-prefix]" >&2; return 1 ;;
  esac
  # Look the login shell up from /etc/passwd instead.
  # Eg '/bin/zsh' or '/bin/bash'
  # We do this bc $SHELL isn't reliably set in non-interactive ssh sessions
  local shell_cmd='exec "$(getent passwd "$(id -un)" | cut -d: -f7)" -l'
  if [ -z "$2" ]; then
    ssh -t "$host" "tmux ls; $shell_cmd"
    return
  fi
  ssh -t "$host" "tmux attach -t $2; $shell_cmd"
}

# SP  ' '  0x20 = · U+00B7 Middle Dot
# TAB '\t' 0x09 = ￫ U+FFEB Halfwidth Rightwards Arrow
# CR  '\r' 0x0D = § U+00A7 Section Sign (⏎ U+23CE also works fine)
# LF  '\n' 0x0A = ¶ U+00B6 Pilcrow Sign (was "Paragraph Sign")
alias whitespace="sed 's/ /·/g;s/\t/￫/g;s/\r/§/g;s/$/¶/g'"