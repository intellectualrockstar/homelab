#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

readonly TECHNITIUM_ROOT="${DOCKER_ROOT}/technitium"
readonly COMPOSE_SOURCE="${REPO_ROOT}/compose/technitium/compose.yaml"
readonly COMPOSE_TARGET="${TECHNITIUM_ROOT}/compose.yaml"

require_docker() {
    command_exists docker || die "Docker is required. Run the docker module before technitium."
    docker compose version >/dev/null 2>&1 ||
        die "Docker Compose is required. Run the docker module before technitium."
}

configure_host_dns_stub() {
    log_info "Disabling the systemd-resolved local DNS stub listener"

    install -d -m 0755 /etc/systemd/resolved.conf.d
    cat >/etc/systemd/resolved.conf.d/technitium.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF

    ln -sfn /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl restart systemd-resolved
}

install_technitium_stack() {
    [[ -f "${COMPOSE_SOURCE}" ]] ||
        die "Technitium Compose file is missing: ${COMPOSE_SOURCE}"

    log_info "Installing Technitium Compose stack in ${TECHNITIUM_ROOT}"

    install -d -m 0750 "${TECHNITIUM_ROOT}"
    install -d -m 0750 "${TECHNITIUM_ROOT}/config"
    install -d -m 0750 "${TECHNITIUM_ROOT}/logs"
    install -m 0640 "${COMPOSE_SOURCE}" "${COMPOSE_TARGET}"

    docker compose -f "${COMPOSE_TARGET}" pull
    docker compose -f "${COMPOSE_TARGET}" up -d
}

verify_technitium() {
    log_info "Verifying Technitium container"

    docker compose -f "${COMPOSE_TARGET}" ps
    docker compose -f "${COMPOSE_TARGET}" ps --status running --services |
        grep -qx 'dns-server' ||
        die "Technitium container is not running."
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    log_info "Starting Technitium bootstrap"

    require_docker
    configure_host_dns_stub
    install_technitium_stack
    verify_technitium

    log_info "Technitium bootstrap complete; configure DNS and DHCP at http://<vm-ip>:5380/"
}

main "$@"
