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

PR_DESCRIPTION=$(echo -e "$PR_DESCRIPTION" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')

# Validate input
if [[ ${#REPOS[@]} -eq 0 || ${#FILES[@]} -eq 0 || -z "$BRANCH" || -z "$COMMIT_MESSAGE" || -z "$PR_TITLE" || -z "$PR_DESCRIPTION" ]]; then
  echo "Error: Missing required configuration in config file. 😿"
  exit 1
fi

# Function to clean up the cloned repository
cleanup() {
  if [[ -n "$REPO_DIR" && -d "$REPO_DIR" ]]; then
    echo "Cleaning up $REPO_DIR"
    rm -rf "$REPO_DIR"
  fi
}

# Set up a trap to call cleanup when the script exits
trap cleanup EXIT

# Process each repository
for REPO in "${REPOS[@]}"; do
  printf '🐱%.0s' {1..30}
  echo
  echo "Processing repository: $REPO"

  REPO_DIR="$(basename "$REPO")"
  cleanup

  # Clone the repository
  git clone "https://github.com/$REPO.git" || { echo "Failed to clone $REPO 😿"; continue; }
  cd "$REPO_DIR" || { echo "Failed to enter directory $REPO_DIR 😿"; continue; }

  # Create or use the branch
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch '$BRANCH' already exists locally. Checking out..."
    git checkout "$BRANCH"
  else
    echo "Creating new branch '$BRANCH'..."
    git checkout -b "$BRANCH"
  fi

  # Get the directory of the current script
  SCRIPT_DIR=$(dirname "$(realpath "$0")")

  # Go two levels up
  BASE_DIR=$(dirname "$(dirname "$SCRIPT_DIR")")

  echo "Base directory: $BASE_DIR"

  # Copy specified files or remove them if missing in the base directory
  for FILE in "${FILES[@]}"; do
    if [[ -f "$BASE_DIR/$FILE" ]]; then
      cp -v "$BASE_DIR/$FILE" ./ || { echo "Failed to copy $FILE to $REPO 😿"; continue; }
    elif [[ -f "./$FILE" ]]; then
      echo "File $FILE does not exist in the base directory but exists in the repo. Removing..."
      rm -v "./$FILE"
    fi
  done

  # Commit and push changes
  git add .
  git commit -m "$COMMIT_MESSAGE" || echo "No changes to commit"

  # Push the branch to the remote repository
  if git ls-remote --heads "https://github.com/$REPO.git" "$BRANCH" | grep -q "$BRANCH"; then
    echo "Branch '$BRANCH' already exists on remote. Resetting it..."
    git push origin "$BRANCH" --force
  else
    echo "Pushing new branch '$BRANCH' to remote..."
    git push origin "$BRANCH"
  fi

  PR_URL=$(gh pr view "$BRANCH" --json url --jq '.url' 2>/dev/null || true)
  if [[ -n "$PR_URL" ]]; then
    echo "Updating existing PR: $PR_URL"
    gh pr edit "$BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_DESCRIPTION"
    PR_LINKS+=("$PR_URL (updated)")
  else
    gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_DESCRIPTION" \
    --base main \
    --head "$BRANCH" || { echo "Failed to create PR for $REPO 😿"; }
    PR_LINKS+=("$PR_URL")
  fi

  # Go back to the root directory
  cd ..
  cleanup
done

printf '😺%.0s' {1..30}
echo
echo "All repositories processed. 🐈"
echo "Pull Requests:"
for PR_LINK in "${PR_LINKS[@]}"; do
  echo "$PR_LINK"
done
