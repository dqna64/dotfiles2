alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gps="git push"
alias gpl="git pull"
alias gd="git diff"
alias gl="git log"
alias grb="git rebase"
alias gsw="git switch"

# Git identities live in numbered slots under the [dqna64-git-identities]
# section of the rendered gitconfig (see git/gitconfig.template). Slot 1 is the
# primary/default identity. Read a slot's fields with:
#   git config dqna64-git-identities.<slot>.name
#   git config dqna64-git-identities.<slot>.email
_DQNA64_IDENTITY_SECTION="dqna64-git-identities"

# Highly visible banner: this commit is NOT using the primary identity.
# Args: <name> <email>.
_dqna64_non_primary_commit_banner() {
    print -P "%S%F{red}%B"
    print -P "  ⚠  COMMITTING AS NON-PRIMARY IDENTITY  ⚠"
    print -P "     $1 <$2>%b%f%s"
}

# Email of identity slot 1 (the primary/default). Empty if not configured.
_dqna64_primary_email() {
    git config "${_DQNA64_IDENTITY_SECTION}.1.email"
}

# If the repo's *effective* commit identity is anything other than the primary
# (slot 1) one, print the banner. Fires no matter how the identity got set
# (e.g. `git secondary`, a per-repo user.email, a worktree override, etc.).
# No-op when the primary identity isn't configured or already matches.
_dqna64_warn_if_not_primary_identity() {
    local primary_email cur_email
    primary_email="$(_dqna64_primary_email)"
    if [[ -z "$primary_email" ]]; then
        # Can't tell whether the active identity is "primary" without it.
        print -P -u2 "%F{yellow}note: primary git identity not set (${_DQNA64_IDENTITY_SECTION}.1.email); run dotfiles_dqna64/git/git-setup.sh%f"
        return 0
    fi
    cur_email="$(git config user.email)"
    if [[ "$cur_email" != "$primary_email" ]]; then
        _dqna64_non_primary_commit_banner "$(git config user.name)" "$cur_email"
    fi
}

# gm: `git commit -m`, with an optional leading slot flag to author a single
# commit as a specific git identity (defined in [dqna64-git-identities]).
#
#   gm "message"      # commit as the repo's active identity (banner if non-primary)
#   gm -2 "message"   # commit as identity slot 2 (secondary), banner shown
#   gm -3 "message"   # commit as identity slot 3, and so on for any slot N
#   gm -1 "message"   # commit as identity slot 1 (primary), no banner
#
# A -N flag passes that slot's name/email via `git -c`, so only this commit's
# author/committer change (the repo's configured identity is untouched).
# When committing, if the git identity during commit is not the primary, a
# banner is shown to inform the user.
# Slots are rendered to dotfiles_dqna64/git/dqna64-dotfiles.gitconfig by
# dotfiles_dqna64/git/git-setup.sh; if a slot is missing, re-run git-setup.sh.
#
# Oh My Zsh's git plugin defines `gm` as an alias (`git merge`). It loads before
# these alias files, so without this unalias the `gm()` line below is a parse
# error ("near `()'") and an alias would shadow this function anyway.
unalias gm 2>/dev/null
gm() {
    local slot=""
    if [[ "$1" =~ '^-[0-9]+$' ]]; then
        slot="${1#-}"
        shift
    fi

    if [[ -n "$slot" ]]; then
        local name email
        name="$(git config "${_DQNA64_IDENTITY_SECTION}.${slot}.name")"
        email="$(git config "${_DQNA64_IDENTITY_SECTION}.${slot}.email")"
        if [[ -z "$name" || -z "$email" ]]; then
            echo "Error: git identity slot $slot not configured (${_DQNA64_IDENTITY_SECTION}.${slot}.name/email)." >&2
            echo "       Define it and re-run dotfiles_dqna64/git/git-setup.sh." >&2
            return 1
        fi
        [[ "$email" != "$(_dqna64_primary_email)" ]] && _dqna64_non_primary_commit_banner "$name" "$email"
        git -c user.name="$name" -c user.email="$email" commit -m "$@"
    else
        _dqna64_warn_if_not_primary_identity
        git commit -m "$@"
    fi
}

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
