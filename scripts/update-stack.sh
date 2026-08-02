#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: sudo $0 <stack-name>" >&2
    echo "Example: sudo $0 plex" >&2
}

# Package maintenance requires root privileges.
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: this script must be run with sudo." >&2
    usage
    exit 1
fi

if [[ $# -ne 1 ]]; then
    echo "Error: provide exactly one Docker stack name." >&2
    usage
    exit 1
fi

STACK_NAME="$1"

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

echo "Stopping Docker stack '${STACK_NAME}'..."
docker compose down

echo "Updating operating system packages..."
apt update
apt upgrade -y

echo "Pulling the latest container images..."
docker compose pull

echo "Starting Docker stack '${STACK_NAME}'..."
docker compose up -d

echo "Removing unused operating system packages..."
apt autoremove -y

echo "Removing unused Docker images..."
docker image prune -f

echo "Current stack status:"
docker compose ps

echo "Docker stack '${STACK_NAME}' updated successfully."
