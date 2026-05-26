#!/bin/zsh

echo "=== Firefox Windows ==="
echo ""

# Get all Firefox windows with useful info
firefox_windows=$(yabai -m query --windows | jq -r '.[] | select(.app | ascii_downcase =="firefox") | "\(.id)|\(.title)|\(.space)|\(.frame.w)x\(.frame.h)"')

if [ -z "$firefox_windows" ]; then
    echo "No Firefox windows found!"
    exit 1
fi

# Display windows
echo "ID | Title | Space | Size"
echo "----------------------------------------"
echo "$firefox_windows" | while IFS='|' read -r id title space size; do
    printf "%-4s | %-50s | %-5s | %s\n" "$id" "${title:0:50}" "$space" "$size"
done
echo ""

# Prompt for space
echo -n "Enter space number (default: 5): "
read target_space
target_space=${target_space:-5}

# Get window IDs into array and clean them
typeset -a window_ids
while IFS='|' read -r id rest; do
    window_ids+=("$id")
done <<< "$firefox_windows"

# Interactive selection function
select_window() {
    local prompt="$1"
    local outfile="$2"
    local selected=1
    local total=${#window_ids[@]}
    local first_draw=true
    
    while true; do
        # Move cursor up if not first draw
        if [[ $first_draw == false ]]; then
            # Move cursor up (total + 4 lines: header + blank + instruction + blank + items)
            tput cuu $((total + 4))
            tput el
        fi
        first_draw=false
        
        echo "=== $prompt ==="
        echo ""
        echo "Use j/k to navigate, Enter to select"
        echo ""
        
        for i in {1..$total}; do
            local id="${window_ids[$i]}"
            local info=$(echo "$firefox_windows" | grep "^${id}|")
            IFS='|' read -r wid title space size <<< "$info"
            
            # Clear the line before printing
            tput el
            if [ $i -eq $selected ]; then
                echo "→ [$wid] ${title:0:60}"
            else
                echo "  [$wid] ${title:0:60}"
            fi
        done
        
        read -sk1 key
        if [[ $key == $'\n' ]]; then
            echo -n "${window_ids[$selected]}" > "$outfile"
            echo ""  # Add a newline after selection
            return
        fi
        
        case "$key" in
            j) ((selected=selected%total+1)) ;;
            k) ((selected=(selected-2+total)%total+1)) ;;
        esac
    done
}

# Create temp files
tmpfile1=$(mktemp)
tmpfile2=$(mktemp)

# Select windows
select_window "Select First Firefox Window" "$tmpfile1"
window1=$(cat "$tmpfile1")

select_window "Select Second Firefox Window" "$tmpfile2"
window2=$(cat "$tmpfile2")

# Clean up temp files
rm -f "$tmpfile1" "$tmpfile2"

clear
echo "Positioning windows $window1 and $window2 on space $target_space..."
## echo "DEBUG: window1='$window1' (length: ${#window1})"
## echo "DEBUG: window2='$window2' (length: ${#window2})"

# Move windows to target space
yabai -m window $window1 --space $target_space
yabai -m window $window2 --space $target_space

# Float settings for window
yabai -m config --space $target_space layout float
yabai -m config top_padding 12
yabai -m config bottom_padding 12
yabai -m config left_padding 12
yabai -m config right_padding 12
yabai -m config window_gap 06


# Position first window (left 2/5)
yabai -m window $window1 --toggle float 2>/dev/null
yabai -m window $window1 --grid 1:5:0:0:2:1

# Position second window (right 3/5)
yabai -m window $window2 --toggle float 2>/dev/null
yabai -m window $window2 --grid 1:5:2:0:3:1

echo "Done! Windows positioned on space $target_space"
