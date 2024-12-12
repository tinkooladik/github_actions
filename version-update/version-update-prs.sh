#!/bin/bash

set -e

# Static fields
BRANCH="bulk/update-library-versions"
PR_TITLE="Bulk | update library versions"
VERSION="0.0.2"
LIB_PR_URL="https://github.com/tinkooladik/github_actions/pull/1"

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
LIB_NAME=""
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
    "[lib_name]")
      SECTION="lib_name"
      ;;
    \[*\]) # Detect other sections
      SECTION=""
      ;;
    *)
      if [[ -n "$SECTION" ]]; then
        case "$SECTION" in
          "repos") [[ -n "$line" ]] && REPOS+=("$line") ;;
          "lib_name") [[ -n "$line" ]] && LIB_NAME="$line" ;;
        esac
      fi
      ;;
  esac
done < "$CONFIG_FILE"

# Validate input
if [[ ${#REPOS[@]} -eq 0 || -z "$LIB_NAME" ]]; then
  echo "Error: Missing required configuration in config file. 😿"
  exit 1
fi

COMMIT_NAME="Update $LIB_NAME library version"

# Process each repository
for REPO in "${REPOS[@]}"; do
  echo "🐱🐱🐱 Processing repository: $REPO 🐱🐱🐱"

  # Clone the repository
  REPO_DIR="$(basename "$REPO")"
  git clone "https://github.com/$REPO.git" || {
    echo "Failed to clone $REPO 😿"
    FAILED_REPOS+=("$REPO")
    continue
  }
  cd "$REPO_DIR" || continue

  # Create or switch to branch
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
    git pull origin "$BRANCH" --rebase
  else
    git checkout -b "$BRANCH"
  fi

  # Touch the gradle/libs.versions.toml file
  TOML_FILE="gradle/libs.versions.toml"
  if [[ ! -f "$TOML_FILE" ]]; then
    echo "Error: File '$TOML_FILE' not found in $REPO 😿"
    FAILED_REPOS+=("$REPO (file not found)")
    cd .. && rm -rf "$REPO_DIR"
    continue
  fi

  # Update the version for the library
  if grep -q "^$LIB_NAME" "$TOML_FILE"; then
    sed -i.bak -E "s|^($LIB_NAME\s*=\s*\"[0-9]+\.[0-9]+\.[0-9]+).*\"|\1$VERSION\"|" "$TOML_FILE" || {
      echo "Failed to update $LIB_NAME in $TOML_FILE 😿"
      FAILED_REPOS+=("$REPO (failed to update version)")
      cd .. && rm -rf "$REPO_DIR"
      continue
    }
    echo "Updated $LIB_NAME to version $VERSION in $TOML_FILE"
  else
    echo "Error: $LIB_NAME not found in $TOML_FILE 😿"
    FAILED_REPOS+=("$REPO (library not found)")
    cd .. && rm -rf "$REPO_DIR"
    continue
  fi

  # Commit and push changes
  git add "$TOML_FILE"
  git commit -m "$COMMIT_NAME" || {
    echo "No changes to commit for $REPO"
    FAILED_REPOS+=("$REPO (no changes to commit)")
  }
  git push origin "$BRANCH"

  # Create or update a PR
  PR_INFO=$(gh pr view "$BRANCH" --json url,body,state --jq '{url: .url, body: .body, state: .state}' 2>/dev/null || true)
  PR_URL=$(echo "$PR_INFO" | jq -r '.url')
  PR_BODY=$(echo "$PR_INFO" | jq -r '.body')
  PR_STATE=$(echo "$PR_INFO" | jq -r '.state')

  if [[ -n "$PR_URL" && "$PR_STATE" != "CLOSED" ]]; then
    echo "PR already exists: $PR_URL"

    # Append LIB_PR_URL to the existing description if not already present
    if [[ "$PR_BODY" != *"$LIB_PR_URL"* ]]; then
      UPDATED_PR_BODY="${PR_BODY}"$'<br>'"$LIB_PR_URL"
      gh pr edit "$BRANCH" \
        --body "$UPDATED_PR_BODY" || {
          echo "Failed to update PR $PR_URL 😿"
          FAILED_REPOS+=("$REPO (failed to update PR)")
          cd .. && rm -rf "$REPO_DIR"
          continue
        }
      echo "Updated PR description for $PR_URL"
    else
      echo "LIB_PR_URL already present in PR description for $PR_URL"
    fi
  else
    echo "Opening a new PR"
    PR_URL=$(gh pr create \
      --title "$PR_TITLE" \
      --body "Updated $LIB_NAME to version $VERSION." \
      --base main \
      --head "$BRANCH" 2>/dev/null) || {
      echo "Failed to create PR for $REPO 😿"
      FAILED_REPOS+=("$REPO (failed to create PR)")
      cd .. && rm -rf "$REPO_DIR"
      continue
    }

    if [[ $? -eq 0 && -n "$PR_URL" ]]; then
      PR_LINKS+=("$PR_URL")
    fi
  fi

done

# Output results
echo "✅ Pull Requests:"
for PR_LINK in "${PR_LINKS[@]}"; do
  echo "$PR_LINK"
done

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
  echo "❌ Failed repositories:"
  for FAILED_REPO in "${FAILED_REPOS[@]}"; do
    echo "$FAILED_REPO"
  done
fi