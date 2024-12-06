#!/bin/bash

set -e

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Config file in the same directory as the script
CONFIG_FILE="$SCRIPT_DIR/create-prs-config.txt"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file '$CONFIG_FILE' not found"
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
      echo "Entering commit_message section"
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
          "repos")
            [[ -n "$line" ]] && REPOS+=("$line")
            ;;
          "files")
            [[ -n "$line" ]] && FILES+=("$line")
            ;;
          "branch")
            if [[ -n "$line" ]]; then
              BRANCH="$line"
            fi
            ;;
          "commit_message")
            if [[ -n "$line" ]]; then
              COMMIT_MESSAGE="$line"
            fi
            ;;
          "pr_title")
            if [[ -n "$line" ]]; then
              PR_TITLE="$line"
            fi
            ;;
          "pr_description")
            if [[ -n "$line" ]]; then
              PR_DESCRIPTION+="$line"$'\n'
            fi
            ;;
        esac
      fi
      ;;
  esac
done < "$CONFIG_FILE"

echo "REPOS: $REPOS"
echo "FILES: $FILES"
echo "Branch: $BRANCH"
echo "Commit message: $COMMIT_MESSAGE"

# Validate input
if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Error: No repositories specified in [repos] section."
  exit 1
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: No files specified in [files] section."
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  echo "Error: Branch name is missing in [branch] section."
  exit 1
fi

if [[ -z "$COMMIT_MESSAGE" ]]; then
  echo "Error: Commit message is missing in [commit_message] section."
  exit 1
fi

if [[ -z "$PR_TITLE" ]]; then
  echo "Error: PR title is missing in [pr_title] section."
  exit 1
fi

if [[ -z "$PR_DESCRIPTION" ]]; then
  echo "Error: PR description is missing in [pr_description] section."
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
  echo "_____________________________"
  echo "Processing repository: $REPO"

  REPO_DIR="$(basename "$REPO")"
  cleanup

  # Clone the repository
  git clone "https://github.com/$REPO.git" || { echo "Failed to clone $REPO"; continue; }
  cd "$REPO_DIR" || { echo "Failed to enter directory $REPO_DIR"; continue; }

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

  # Copy specified files
  for FILE in "${FILES[@]}"; do
    cp -v "$BASE_DIR/$FILE" ./ || { echo "Failed to copy $FILE to $REPO"; continue; }
  done

  # Commit and push changes
  git add .
  git commit -m "$COMMIT_MESSAGE"

  # Push the branch to the remote repository
  if git ls-remote --heads "https://github.com/$REPO.git" "$BRANCH" | grep -q "$BRANCH"; then
    echo "Branch '$BRANCH' already exists on remote. Resetting it..."
    git push origin "$BRANCH" --force
  else
    echo "Pushing new branch '$BRANCH' to remote..."
    git push origin "$BRANCH"
  fi

  # Create pull request
  gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_DESCRIPTION" \
    --base main \
    --head "$BRANCH" || { echo "Failed to create PR for $REPO"; }

  # Go back to the root directory
  cd ..
  cleanup
done

echo "_____________________________"
echo "All repositories processed."
