#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

readonly COMPOSE_SOURCE="${REPO_ROOT}/compose/plex/compose.yaml"
readonly STARTUP_SERVICE_SOURCE="${REPO_ROOT}/compose/plex/plex-startup.service"
readonly STARTUP_SERVICE_TARGET="/etc/systemd/system/plex-startup.service"

PLEX_ROOT=""
COMPOSE_TARGET=""

require_docker() {
    command_exists docker || die "Docker is required. Run the docker module before Plex."
    docker compose version >/dev/null 2>&1 ||
        die "Docker Compose is required. Run the docker module before Plex."
}

install_plex_stack() {
    [[ -f "${COMPOSE_SOURCE}" ]] ||
        die "Plex Compose file is missing: ${COMPOSE_SOURCE}"

    log_info "Installing Plex Compose stack in ${PLEX_ROOT}"

    install -d -m 0750 "${PLEX_ROOT}"
    install -d -m 0750 "${PLEX_ROOT}/config"
    install -m 0640 "${COMPOSE_SOURCE}" "${COMPOSE_TARGET}"

    docker compose -f "${COMPOSE_TARGET}" pull
    docker compose -f "${COMPOSE_TARGET}" up -d
}

install_plex_startup_service() {
    [[ -f "${STARTUP_SERVICE_SOURCE}" ]] ||
        die "Plex startup service is missing: ${STARTUP_SERVICE_SOURCE}"

    log_info "Installing Plex NFS startup recovery service"

    install -m 0644 "${STARTUP_SERVICE_SOURCE}" "${STARTUP_SERVICE_TARGET}"
    systemctl daemon-reload
    systemctl enable plex-startup.service
}

verify_plex() {
    log_info "Verifying Plex container and startup service"

    docker compose -f "${COMPOSE_TARGET}" ps
    docker compose -f "${COMPOSE_TARGET}" ps --status running --services |
        grep -qx 'plex' ||
        die "Plex container is not running."

    systemctl is-enabled --quiet plex-startup.service ||
        die "Plex startup service is not enabled."
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    PLEX_ROOT="${DOCKER_ROOT}/plex"
    COMPOSE_TARGET="${PLEX_ROOT}/compose.yaml"

    log_info "Starting Plex bootstrap"

    require_docker
    install_plex_stack
    install_plex_startup_service
    verify_plex

    log_info "Plex bootstrap complete"
}

main "$@"
