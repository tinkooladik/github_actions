#!/bin/bash

set -e

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Config file in the same directory as the script
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file '$CONFIG_FILE' not found 😿"
  exit 1
fi

# Read config file
REPOS=()
FILES=()
BRANCH=""
COMMIT_MESSAGE=""
PR_TITLE=""
PR_DESCRIPTION=""
SECTION=""
PR_LINKS=()
FAILED_REPOS=()

while IFS= read -r line || [ -n "$line" ]; do
  # Trim leading/trailing whitespace
  line=$(echo "$line" | xargs)

  case "$line" in
    "[repos]")
      SECTION="repos"
      ;;
    "[files]")
      SECTION="files"
      ;;
    "[branch]")
      SECTION="branch"
      ;;
    "[commit_message]")
      SECTION="commit_message"
      ;;
    "[pr_title]")
      SECTION="pr_title"
      ;;
    "[pr_description]")
      SECTION="pr_description"
      ;;
    \[*\]) # Detect other sections
      SECTION=""
      ;;
    *)
      if [[ -n "$SECTION" ]]; then
        case "$SECTION" in
          "repos") [[ -n "$line" ]] && REPOS+=("$line") ;;
          "files") [[ -n "$line" ]] && FILES+=("$line") ;;
          "branch") [[ -n "$line" ]] && BRANCH="$line" ;;
          "commit_message") [[ -n "$line" ]] && COMMIT_MESSAGE="$line" ;;
          "pr_title") [[ -n "$line" ]] && PR_TITLE="$line" ;;
          "pr_description") [[ -n "$line" ]] && PR_DESCRIPTION+="$line"$'\n' ;;
        esac
      fi
      ;;
  esac
done < "$CONFIG_FILE"

# Check if BRANCH is updated
if [[ "$BRANCH" == "alex/RBMN-XXXXX-update-repos" ]]; then
  echo "Using template branch 'alex/RBMN-XXXXX-update-repos'. Did you forget to update the config file? 🔫😾😾😾"
  exit 0
fi

PR_DESCRIPTION=$(echo -e "$PR_DESCRIPTION" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')

# Validate input
if [[ ${#REPOS[@]} -eq 0 || ${#FILES[@]} -eq 0 || -z "$BRANCH" || -z "$COMMIT_MESSAGE" || -z "$PR_TITLE" || -z "$PR_DESCRIPTION" ]]; then
  echo "Error: Missing required configuration in config file. 😿"
  exit 1
fi

# Base directory containing the source files
FILES_DIR="$SCRIPT_DIR/files"

if [[ ! -d "$FILES_DIR" ]]; then
  echo "Error: Source directory '$FILES_DIR' does not exist 😿"
  exit 1
fi

echo "Files directory: $FILES_DIR"

# Function to clean up the cloned repository
cleanup() {
  if [[ -n "$REPO_DIR" && -d "$REPO_DIR" ]]; then
    echo "Cleaning up $REPO_DIR"
    rm -rf "$REPO_DIR"
  fi
}

# Set up a trap to call cleanup when the script exits
trap cleanup EXIT

checkout_or_create_branch() {
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch '$BRANCH' already exists locally. Checking out..."
    git checkout "$BRANCH"
    git pull origin "$BRANCH" --rebase || {
      echo "Failed to pull changes for branch '$BRANCH' 😿"
      FAILED_REPOS+=("$REPO (failed to pull changes)")
      return 1
    }
  elif git ls-remote --heads "https://github.com/$REPO.git" "$BRANCH" | grep -q "$BRANCH"; then
    echo "Branch '$BRANCH' exists on remote but not locally. Checking out and pulling..."
    git checkout -b "$BRANCH" --track "origin/$BRANCH"
    git pull origin "$BRANCH" --rebase || {
      echo "Failed to pull changes for branch '$BRANCH' 😿"
      FAILED_REPOS+=("$REPO (failed to pull changes)")
      return 1
    }
  else
    echo "Branch '$BRANCH' does not exist. Creating a new branch..."
    git checkout -b "$BRANCH"
  fi

  return 0
}

update_pr() {
    local success_msg="$1"
    local error_msg="$2"

    echo "Updating existing PR: $PR_URL"

    if gh pr edit "$BRANCH" \
                --title "$PR_TITLE" \
                --body "$PR_DESCRIPTION"; then
                PR_LINKS+=("$PR_URL ($success_msg)")
    else
        echo "Failed to update PR $PR_URL 😿"
        FAILED_REPOS+=("$REPO ($error_msg)")
    fi
}

create_or_update_pr() {
    local is_draft_flag=$1 # Accept the --draft flag as the first parameter (optional)
    if [[ -n "$PR_URL" && "$PR_STATE" != "CLOSED" ]]; then
      update_pr "updated" \
          "failed to update PR $PR_URL"
    else
      echo "Opening a new PR"
      PR_URL=$(gh pr create \
          --title "$PR_TITLE" \
          --body "$PR_DESCRIPTION" \
          --base main \
          --head "$BRANCH" \
          $is_draft_flag 2>/dev/null) || {
                echo "Failed to create PR for repo $REPO 😿";
                FAILED_REPOS+=("$REPO (failed to create PR)");
                return 1
             }
      if [[ $? -eq 0 && -n "$PR_URL" ]]; then
          PR_LINKS+=("$PR_URL");
      fi
    fi
}

# Process each repository
for REPO in "${REPOS[@]}"; do
  printf '🐱%.0s' {1..30}
  echo
  echo "Processing repository: $REPO"

  REPO_DIR="$(basename "$REPO")"
  cleanup

  # Clone the repository
  git clone "https://github.com/$REPO.git" || {
    echo "Failed to clone $REPO 😿";
    FAILED_REPOS+=("$REPO (failed)");
    continue;
  }
  cd "$REPO_DIR" || {
    echo "Failed to enter directory $REPO_DIR 😿";
    FAILED_REPOS+=("$REPO (failed)");
    continue;
  }

  # Check if the branch exists locally or remotely
  if ! checkout_or_create_branch; then
    cd ..
    cleanup
    continue
  fi

  # Copy specified files or remove them if missing in the base directory
  for FILE in "${FILES[@]}"; do
      SOURCE_PATH="$FILES_DIR/$FILE"
      DEST_PATH="./$FILE"

      if [[ -f "$SOURCE_PATH" ]]; then
          # Create the necessary directory structure in the destination
          mkdir -p "$(dirname "$DEST_PATH")"
          # Copy the file
          cp -v "$SOURCE_PATH" "$DEST_PATH" || { echo "Failed to copy $FILE to $REPO 😿"; continue; }
      elif [[ -f "$DEST_PATH" ]]; then
          echo "File $FILE does not exist in the source but exists in the repo. Removing..."
          rm -v "$DEST_PATH"
      fi
  done

  # Retrieve PR information
  PR_INFO=$(gh pr view "$BRANCH" --json url,state,title,body --jq '{url: .url, state: .state, title: .title, description: .body}' 2>/dev/null || true)

  # Parse the JSON response
  PR_URL=$(echo "$PR_INFO" | jq -r '.url' 2>/dev/null)
  PR_STATE=$(echo "$PR_INFO" | jq -r '.state' 2>/dev/null)

  # Check if pr title / description were updated in config file
  OLD_PR_TITLE=$(echo "$PR_INFO" | jq -r '.title' 2>/dev/null | xargs)
  OLD_PR_DESCRIPTION=$(echo "$PR_INFO" | jq -r '.description' 2>/dev/null)
  OLD_PR_DESCRIPTION=$(echo -e "$OLD_PR_DESCRIPTION" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')
  if [[ "$OLD_PR_TITLE" != "$PR_TITLE" || "$OLD_PR_DESCRIPTION" != "$PR_DESCRIPTION" ]]; then
    PR_DETAILS_UPDATED=true
  else
    PR_DETAILS_UPDATED=false
  fi

  # Commit and push changes
  git add .
  git commit -m "$COMMIT_MESSAGE" || {
    echo "No changes to commit";

    # Update PR description if needed and exit script
    if [[ -n "$PR_URL" && "$PR_STATE" != "CLOSED" && "$PR_DETAILS_UPDATED" == "true" ]]; then
        update_pr "no changes to commit, updated title / description" \
            "no changes to commit, failed to update PR $PR_URL"
        cd ..; cleanup; continue;
    fi
    FAILED_REPOS+=("$REPO (no changes to commit)");
    cd ..; cleanup; continue; }

  # Push the branch to the remote repository
  echo "Pushing updates to branch '$BRANCH'..."
  git push origin "$BRANCH" || {
    echo "Failed to push changes";
    FAILED_REPOS+=("$REPO (failed to push changes)");
    cd ..; cleanup; continue;
  }

  if ! create_or_update_pr ""; then
    cd ..
    cleanup
    continue
  fi

  # Go back to the root directory
  cd ..
  cleanup
done

## Process output

OUTPUT+="✅ Pull Requests:<br>"
for PR_LINK in "${PR_LINKS[@]}"; do
  OUTPUT+="$PR_LINK<br>"
done

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  OUTPUT+="<br>"
  OUTPUT+="❌ Failed repos:<br>"
  for REPO in "${FAILED_REPOS[@]}"; do
    OUTPUT+="https://github.com/$REPO<br>"
  done
fi

## Post comment with results in shared repo
REPO="tinkooladik/github_actions"

# Check if the branch exists locally or remotely
if ! checkout_or_create_branch; then
  echo "Couldn't checkout shared repo branch"
fi

# Commit and push changes in shared repo
git add .
git commit -m "$COMMIT_MESSAGE" || { echo "No changes to commit"; }
git push origin "$BRANCH" || { echo "Failed to push changes"; }

# Create or update PR
PR_INFO=$(gh pr view "$BRANCH" --json url,state --jq '{url: .url, state: .state}' 2>/dev/null || true)
PR_URL=$(echo "$PR_INFO" | jq -r '.url' 2>/dev/null)
PR_STATE=$(echo "$PR_INFO" | jq -r '.state' 2>/dev/null)

if ! create_or_update_pr "--draft"; then
  echo "Couldn't create or update a PR $PR_URL"
fi

# Add comment with results
gh pr comment "$PR_URL" ---body "$OUTPUT" #|| { echo "Failed to comment on PR $PR_URL 😿"; }

printf '😺%.0s' {1..30}
echo
echo "All repositories processed. 🐈"
echo

# Replace <br> with newline
PROCESSED_OUTPUT=${OUTPUT//<br>/$'\n'}
echo -e "$PROCESSED_OUTPUT"
echo "Shared repo PR: $PR_URL"
