#!/usr/bin/env bash

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        die "This script must be run as root."
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

load_config() {
    local repo_root="$1"
    local config_file="${repo_root}/config/defaults.conf"

    [[ -f "${config_file}" ]] || die "Missing config file: ${config_file}"

    # shellcheck source=/dev/null
    source "${config_file}"

    : "${TIMEZONE:?TIMEZONE is required}"
    : "${ADMIN_USER:?ADMIN_USER is required}"
    : "${DOCKER_ROOT:?DOCKER_ROOT is required}"
    : "${PLEX_UID:?PLEX_UID is required}"
    : "${PLEX_GID:?PLEX_GID is required}"
}

apt_install() {
    apt-get install -y --no-install-recommends "$@"
}

disable_ufw() {
    if command_exists ufw; then
        log_info "Disabling UFW"
        ufw --force disable || true
        systemctl disable --now ufw 2>/dev/null || true
    fi
}
