#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

readonly COMPOSE_SOURCE="${REPO_ROOT}/compose/media/compose.yaml"

MEDIA_ROOT=""
COMPOSE_TARGET=""

require_docker() {
    command_exists docker || die "Docker is required. Run the docker module before media."
    docker compose version >/dev/null 2>&1 ||
        die "Docker Compose is required. Run the docker module before media."
}

install_media_stack() {
    local service

    [[ -f "${COMPOSE_SOURCE}" ]] ||
        die "Media Compose file is missing: ${COMPOSE_SOURCE}"

    log_info "Installing media Compose stack in ${MEDIA_ROOT}"

    install -d -m 0750 "${MEDIA_ROOT}"

    for service in sonarr radarr prowlarr sabnzbd seerr; do
        install -d -m 0750 -o 1000 -g 1000 "${MEDIA_ROOT}/${service}"
    done

    install -m 0640 "${COMPOSE_SOURCE}" "${COMPOSE_TARGET}"

    docker compose -f "${COMPOSE_TARGET}" pull
    docker compose -f "${COMPOSE_TARGET}" up -d
}

verify_media_stack() {
    local service

    log_info "Verifying media containers"

    docker compose -f "${COMPOSE_TARGET}" ps

    for service in sonarr radarr prowlarr sabnzbd seerr; do
        docker compose -f "${COMPOSE_TARGET}" ps --status running --services |
            grep -qx "${service}" ||
            die "Media container is not running: ${service}"
    done
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    MEDIA_ROOT="${DOCKER_ROOT}/media"
    COMPOSE_TARGET="${MEDIA_ROOT}/compose.yaml"

    log_info "Starting media bootstrap"

    require_docker
    install_media_stack
    verify_media_stack

    log_info "Media bootstrap complete"
}

main "$@"
