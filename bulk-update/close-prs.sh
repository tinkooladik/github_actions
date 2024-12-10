#!/bin/bash

set -e

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Config file in the same directory as the script
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file '$CONFIG_FILE' not found"
  exit 1
fi

# Read config file
REPOS=()
BRANCH=""
SECTION=""
CLOSED_PRS=()
FAILED_REPOS=()

while IFS= read -r line || [ -n "$line" ]; do
  # Trim leading/trailing whitespace
  line=$(echo "$line" | xargs)

  case "$line" in
    "[repos]")
      SECTION="repos"
      ;;
    "[branch]")
      SECTION="branch"
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
          "branch")
            if [[ -n "$line" ]]; then
              BRANCH="$line"
            fi
            ;;
        esac
      fi
      ;;
  esac
done < "$CONFIG_FILE"

# Validate input
if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Error: No repositories specified in [repos] section."
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  echo "Error: Branch name is missing in [branch] section."
  exit 1
fi

# Process each repository
for REPO in "${REPOS[@]}"; do
  echo "🐱🐱🐱 Processing repository: $REPO 🐱🐱🐱"

  # Check if a PR exists for the branch
  PR_INFO=$(gh pr list --repo "$REPO" --head "$BRANCH" --json number,state --jq '.[] | "\(.number) \(.state)"' 2>/dev/null || echo "")

  if [[ -n "$PR_INFO" ]]; then
    PR_NUMBER=$(echo "$PR_INFO" | awk '{print $1}')
    PR_STATE=$(echo "$PR_INFO" | awk '{print $2}')
    PR_URL="https://github.com/$REPO/pull/$PR_NUMBER"

    if [[ "$PR_STATE" != "CLOSED" ]]; then
      echo "Closing PR $PR_URL"
      if gh pr close "$PR_NUMBER" --repo "$REPO"; then
        echo "Closed PR $PR_URL"
        CLOSED_PRS+=("$PR_URL")
      else
        echo "Failed to close PR $PR_URL 😿"
        FAILED_REPOS+=("$REPO (failed to close $PR_URL)")
      fi
    else
      echo "PR $PR_URL is already closed."
      FAILED_REPOS+=("$REPO (PR $PR_URL already closed)")
    fi
  else
    echo "No PR found for branch '$BRANCH' in repository $REPO."
    FAILED_REPOS+=("$REPO (no PR found for branch $BRANCH)")
  fi
done

printf '😺%.0s' {1..30}
echo
echo "All repositories processed. 🐈"

echo
echo "✅ Closed PRs:"
for PR_LINK in "${CLOSED_PRS[@]}"; do
  echo "$PR_LINK"
done

echo
echo "❌ Failed repos:"
for REPO in "${FAILED_REPOS[@]}"; do
  echo "https://github.com/$REPO"
done
echo