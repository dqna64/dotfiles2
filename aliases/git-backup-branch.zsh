# Create a backup of the current branch and push to origin.
# Sourced by zsh/.zshrc; defines the backup-branch shell function.
# Usage (after sourcing): backup-branch

backup-branch() {
    local current_branch=$(git branch --show-current)
    if [[ -z "$current_branch" ]]; then
        echo "Error: Not on any branch (detached HEAD?)"
        return 1
    fi

    local timestamp=$(date +%y%m%d-%H%M)
    local backup_branch="${current_branch}-backup-${timestamp}"

    echo "Creating backup branch: $backup_branch"
    git branch "$backup_branch"

    echo "Pushing to origin..."
    git push -u origin "$backup_branch"

    echo "Backup complete. You remain on $current_branch."
}
