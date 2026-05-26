# Git squash and rebase function.
# Sourced by zsh/.zshrc; defines the squash+rebase shell function.
# Usage (after sourcing): squash+rebase

squash+rebase() {
    # Save current branch name
    local current_branch=$(git branch --show-current)
    
    # Safety check - don't run on master/main
    if [[ "$current_branch" == "master" || "$current_branch" == "main" ]]; then
        echo "Error: Cannot run this function on master/main branch"
        return 1
    fi
    
    echo "Current branch: $current_branch"
    
    echo "Fetching origin master..."
    git fetch origin master
    
    # Get merge-base commit between HEAD and origin/master
    local merge_base=$(git merge-base HEAD origin/master)
    if [[ $? -ne 0 ]]; then
        echo "Error: Could not find merge-base with origin/master"
        return 1
    fi
    
    echo "Merge base: $merge_base"
    
    # Check for uncommitted changes and handle them
    local include_uncommitted=false
    local did_stash=false
    if [[ -n $(git status --porcelain) ]]; then
        echo "You have uncommitted changes in your working tree:"
        git status --short
        echo
        echo -n "Include these changes in the squash commit? (y/N): "
        read REPLY
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            include_uncommitted=true
            echo "Uncommitted changes will be included in the squash."
        else
            echo "Stashing uncommitted changes for the rebase..."
            git stash push -m "Auto-stash before squash_and_rebase"
            did_stash=true
        fi
        echo
    fi
    
    # Show what will be reset and ask for confirmation
    echo "About to soft reset from $(git rev-parse --short HEAD) to $(git rev-parse --short "$merge_base")"
    echo "This will remove commits after the merge-base but keep all their changes staged for the squash commit."
    echo -n "Continue? (y/N): "
    read REPLY
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        return 1
    fi
    echo
    echo
    
    # Soft reset to merge-base commit
    echo "Soft resetting to merge-base..."
    git reset --soft "$merge_base"
    
    # Add uncommitted changes if requested, then commit
    echo "Committing squashed changes..."
    if [[ "$include_uncommitted" == "true" ]]; then
        git add -A  # Include uncommitted changes with the squash
    fi
    # Note: changes from removed commits are already staged after soft reset
    git commit -m "squash commits of $current_branch"
    
    # Rebase onto origin/master
    echo "Rebasing onto origin/master..."
    git rebase origin/master
    
    # Restore stashed changes if we stashed them
    if [[ "$did_stash" == "true" ]]; then
        echo "Remember to restore your uncommitted changes with: git stash apply"
    fi
    
    echo "Squashed and attempted rebase. Make sure to resolve rebase conflicts if any!"
}
