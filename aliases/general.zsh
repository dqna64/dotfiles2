freshsauce() {
  source ~/.zshrc && echo "New alias just dropped. 🔥"
}

alias ls="ls -hal"

# list files in order of creation
alias lsd='find . -maxdepth 1 -exec stat -f "%B %N" {} + | sort -n | awk '\''{print substr($0, index($0,$2))}'\'' | while IFS= read -r file; do ls -ld "$file" | awk '\''{printf "%-12s %-3s %-3s %-6s %6s %3s %3s %-5s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'\''; done'

function mkcd() {
  mkdir -p "$@" && cd "$_";
}

# SP  ' '  0x20 = · U+00B7 Middle Dot
# TAB '\t' 0x09 = ￫ U+FFEB Halfwidth Rightwards Arrow
# CR  '\r' 0x0D = § U+00A7 Section Sign (⏎ U+23CE also works fine)
# LF  '\n' 0x0A = ¶ U+00B6 Pilcrow Sign (was "Paragraph Sign")
alias whitespace="sed 's/ /·/g;s/\t/￫/g;s/\r/§/g;s/$/¶/g'"