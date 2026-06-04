alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gm="git commit -m "
alias gps="git push"
alias gpl="git pull"
alias gd="git diff"
alias gl="git log"
alias grb="git rebase"
alias gsw="git switch"

# By BlakeC
checkoutorigin() {
  git remote set-branches --add origin "$1" && git fetch origin "$1" && git checkout "$1"
}

# By BlakeC
evergreen() {
  # Verify we're in a git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not a git repository." >&2
    return 1
  fi

  # Check for unstaged changes (or any changes) using git status
  echo "Checking for unstaged changes..."
  if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: Unstaged changes detected. Please commit or stash them before switching branches." >&2
    return 1
  fi

  # Switch to the master branch and pull the latest changes
  echo "Switching to master and pulling down the latest..."
  git checkout master && git pull origin master
}
