#!/bin/bash

set -e

# Static fields
BRANCH="bulk/update-library-versions"
PR_TITLE="Bulk | update library versions"
VERSION="0.0.1"

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

done