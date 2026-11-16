#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kartoza (Pty) Ltd <victoria@kartoza.com>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Check whether VS Code has been run in this project before.
: "${VSCODE_PROFILE:?not set}"
: "${VSCODE_USER_DIR:?not set}"
: "${VSCODE_EXT_DIR:?not set}"
: "${VSCODE_SETTINGS_FILE:?not set}"
: "${VSCODE_EXTENSIONS_SOURCE:?not set}"
: "${VSCODE_SETTINGS_SOURCE:?not set}"
: "${WORKING_DIR:?not set}"

vscode() {
    code --user-data-dir="$VSCODE_USER_DIR" \
        --profile="$VSCODE_PROFILE" \
        --extensions-dir="$VSCODE_EXT_DIR" "$@"
}

if [[ ! -d "$VSCODE_USER_DIR" || -z "$(ls -A "$VSCODE_USER_DIR" 2>/dev/null)" ]]; then
    \cat <<'EOF'

  🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻🔻
  ⭐️ It appears you have not run VSCode in this project before.
  After it opens, please close VSCode and then rerun this script
  so that the extensions directory initialises properly.
  🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺🔺

EOF
    mkdir -vp  "$VSCODE_USER_DIR" "$VSCODE_EXT_DIR"
    vscode "$WORKING_DIR"
    exit 0
fi

# Get the already installed Visual Studio Code Extensions (no version check)
mapfile -t installed_extensions < <(vscode --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort)

# Get the recommended Visual Studio Extensions (no version specified)
mapfile -t recommended_extensions < <(sed -E 's#^[[:space:]]*//.*$##' "$VSCODE_EXTENSIONS_SOURCE" | jq -r '.recommendations[]'| tr '[:upper:]' '[:lower:]' | LC_ALL=C sort)

# Installed and recommended Visual Studio Extensions
mapfile -t installed_and_recommended_extensions < <(LC_ALL=C comm -12 \
  <(printf '%s\n' "${recommended_extensions[@]}") \
  <(printf '%s\n' "${installed_extensions[@]}"))

# Install Recommended but NOT installed (these are the ones to install)
mapfile -t missing_recommended_extensions < <(LC_ALL=C comm -23 \
  <(printf '%s\n' "${recommended_extensions[@]}") \
  <(printf '%s\n' "${installed_and_recommended_extensions[@]}"))

green=$'\033[32m'
reset=$'\033[0m'

if [[ ${#installed_and_recommended_extensions[@]} -gt 0 ]]; then
    for ext in "${installed_and_recommended_extensions[@]}"; do
        echo "$ext ${green}already installed${reset}"
    done
else
    echo "No recommended extensions installed in $VSCODE_EXT_DIR"
fi

if [[ ${#missing_recommended_extensions[@]} -gt 0 ]]; then
    for ext in "${missing_recommended_extensions[@]}"; do
        vscode --install-extension "$ext" 2>/dev/null
    done
fi

# Launch Visual Studio Code
echo "Starting Visual Studio Code with the following configs: "
echo "Visual Studio Code User data dir: $VSCODE_USER_DIR"
echo "Visual Studio Code Profile: $VSCODE_PROFILE"
echo "Visual Studio Code Extensions Directory: $VSCODE_EXT_DIR"
echo "Visual Studio Code Settings file: $VSCODE_SETTINGS_FILE"
echo "Working Directory: $WORKING_DIR"

vscode "$WORKING_DIR" "$@"
