#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_URL="https://raw.githubusercontent.com/intellectualrockstar/homelab/main/scripts/update-stack.sh"
DESTINATION="/usr/local/sbin/update-stack.sh"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this installer as root (for example: curl ... | sudo bash)." >&2
    exit 1
fi

echo "Installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl cron

echo "Enabling cron..."
systemctl enable --now cron

echo "Downloading latest update-stack.sh..."
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
curl -fsSL "$SOURCE_URL" -o "$tmp_file"

# Basic sanity check before replacing the installed copy.
if ! head -n 1 "$tmp_file" | grep -q '^#!/usr/bin/env bash'; then
    echo "ERROR: Downloaded file does not look like update-stack.sh; existing installation was not changed." >&2
    exit 1
fi

install -o root -g root -m 0755 "$tmp_file" "$DESTINATION"

echo
echo "Installed: $DESTINATION"
echo "Cron:      enabled and running"
echo
echo "Examples:"
echo "  sudo update-stack.sh media"
echo "  sudo update-stack.sh media -includeOS"
echo
echo "Manual run with logging:"
echo "  sudo sh -c '/usr/local/sbin/update-stack.sh media >> /var/log/update-stack.log 2>&1'"
echo
echo "Watch the log:"
echo "  sudo tail -f /var/log/update-stack.log"
