#!/bin/bash

# --- Function to check for root privileges ---
require_root() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges."

        # Check if sudo exists
        if command -v sudo >/dev/null 2>&1; then
            echo "Attempting to re-run the script with sudo..."
            exec sudo "$0" "$@"
            exit 0
        else
            echo "Error: sudo is not installed. Please run this script as root."
            exit 1
        fi
    fi
}

# --- Request root if needed ---
require_root "$@"

# --- Ask for username ---
read -rp "Enter your username: " USERNAME

# Validate input
if [ -z "$USERNAME" ]; then
    echo "Error: Username cannot be empty."
    exit 1
fi

# --- Ask about bonus setup ---
while true; do
    read -rp "Do you want to set up the bonus stuff? (yes/no): " BONUS_INPUT
    case "$BONUS_INPUT" in
        [Yy][Ee][Ss]|[Yy])
            BONUS_SETUP=true
            break
            ;;
        [Nn][Oo]|[Nn])
            BONUS_SETUP=false
            break
            ;;
        *)
            echo "Please answer yes or no."
            ;;
    esac
done

# --- Print results (for debugging/demo) ---
echo "Username: $USERNAME"
echo "Bonus setup: $BONUS_SETUP"

# --- Variables available for later use ---
# $USERNAME contains the entered username
# $BONUS_SETUP contains true/false
