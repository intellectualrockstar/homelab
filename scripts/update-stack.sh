#!/usr/bin/env bash

set -euo pipefail

# Docker stack update helper
#
# Recommended install location:
#   /usr/local/sbin/update-stack.sh
#
# Install/update the script:
#   sudo cp scripts/update-stack.sh /usr/local/sbin/update-stack.sh
#   sudo chmod +x /usr/local/sbin/update-stack.sh
#
# Normal runs update container images only. Running "docker compose up -d"
# after the pull is non-destructive when nothing changed; Compose only
# recreates services whose image or configuration changed.
#
# Add these entries with:
#   sudo crontab -e
#
# Run container updates at 4:00 AM Sunday-Friday:
#   0 4 * * 0-5 /usr/local/sbin/update-stack.sh <stack-name> >> /var/log/update-stack.log 2>&1
#
# Run the Saturday 4:00 AM update with OS package maintenance included:
#   0 4 * * 6 /usr/local/sbin/update-stack.sh <stack-name> -includeOS >> /var/log/update-stack.log 2>&1
#
# Replace <stack-name> with the stack on that VM, for example:
#   media
#   proxy
#   plex

usage() {
    echo "Usage: sudo $0 <stack-name> [-includeOS]" >&2
    echo "Example: sudo $0 media" >&2
    echo "Example: sudo $0 media -includeOS" >&2
}

# Root is required for optional OS package maintenance and for consistent
# operation when this script is invoked from root's cron.
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: this script must be run with sudo." >&2
    usage
    exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Error: provide a Docker stack name and optionally -includeOS." >&2
    usage
    exit 1
fi

STACK_NAME="$1"
INCLUDE_OS=false

if [[ $# -eq 2 ]]; then
    if [[ "$2" == "-includeOS" ]]; then
        INCLUDE_OS=true
    else
        echo "Error: unknown option '$2'." >&2
        usage
        exit 1
    fi
fi

# Keep the resolved path safely below /opt/docker.
if [[ ! "${STACK_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "Error: invalid stack name '${STACK_NAME}'." >&2
    exit 1
fi

STACK_DIR="/opt/docker/${STACK_NAME}"
COMPOSE_FILE="${STACK_DIR}/compose.yaml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "Error: Compose file not found: ${COMPOSE_FILE}" >&2
    exit 1
fi

cd "${STACK_DIR}"

if [[ "${INCLUDE_OS}" == true ]]; then
    echo "Updating operating system packages..."
    apt update
    apt upgrade -y

    echo "Removing unused operating system packages..."
    apt autoremove -y
else
    echo "Skipping operating system updates (use -includeOS to include them)."
fi

echo "Checking for updated container images..."
docker compose pull

echo "Applying container image/configuration changes..."
docker compose up -d --remove-orphans

echo "Removing unused Docker images..."
docker image prune -f

echo "Current stack status:"
docker compose ps

if [[ "${INCLUDE_OS}" == true && -f /var/run/reboot-required ]]; then
    echo "NOTICE: The operating system reports that a reboot is required."
    if [[ -f /var/run/reboot-required.pkgs ]]; then
        echo "Packages requesting the reboot:"
        cat /var/run/reboot-required.pkgs
    fi
fi

echo "Docker stack '${STACK_NAME}' updated successfully."
