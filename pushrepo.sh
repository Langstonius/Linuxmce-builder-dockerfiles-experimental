#!/bin/bash
# Script to incrementally push a large Git repository to GitHub
# including all branches and tags

# Set the GitHub remote - change this to your remote name
REMOTE="origin"

# Function to push a branch incrementally
push_branch_incrementally() {
    local branch=$1
    echo "Processing branch: $branch"
    
    # Get all commit hashes for this branch in chronological order
    local commits=$(git log --format="%H" --reverse $branch)
    
    # Count total commits
    local total_commits=$(echo "$commits" | wc -l)
    echo "Total commits in $branch: $total_commits"
    
    # Push in batches of 1000 commits
    local batch_size=1000
    local count=0
    
    echo "$commits" | while read commit; do
        count=$((count + 1))
        
        # Push every 1000 commits or if it's the last commit
        if [ $((count % batch_size)) -eq 0 ] || [ $count -eq $total_commits ]; then
            echo "Pushing commit $count/$total_commits in $branch"
            git push $REMOTE $commit:refs/heads/$branch
            
            # Sleep to avoid overwhelming the server
            sleep 2
        fi
    done
    
    # Final push to ensure the branch pointer is updated correctly
    echo "Final push for branch $branch"
    git push $REMOTE $branch:$branch
}

# Get all local branches
branches=$(git branch | sed 's/^\*/ /' | tr -d ' ')

# Process each branch
for branch in $branches; do
    push_branch_incrementally $branch
done

# Push all tags at the end
echo "Pushing tags..."
git push $REMOTE --tags

echo "Incremental push completed for all branches and tags."
exit 0
