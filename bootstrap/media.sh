#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

install_media_packages() {
    log_info "Installing NFS client support"

    apt-get update
    apt_install nfs-common
}

create_plex_group() {
    local existing_group

    if getent group "${PLEX_GID}" >/dev/null 2>&1; then
        existing_group="$(getent group "${PLEX_GID}" | cut -d: -f1)"

        [[ "${existing_group}" == "plex" ]] ||
            die "GID ${PLEX_GID} belongs to ${existing_group}, not plex"

        return
    fi

    groupadd --gid "${PLEX_GID}" plex
}

create_plex_user() {
    local existing_user

    if getent passwd "${PLEX_UID}" >/dev/null 2>&1; then
        existing_user="$(getent passwd "${PLEX_UID}" | cut -d: -f1)"

        [[ "${existing_user}" == "plex" ]] ||
            die "UID ${PLEX_UID} belongs to ${existing_user}, not plex"

        return
    fi

    useradd \
        --uid "${PLEX_UID}" \
        --gid "${PLEX_GID}" \
        --no-create-home \
        --shell /usr/sbin/nologin \
        plex
}

create_media_directories() {
    log_info "Creating media mount directory"

    install -d \
        -m 0775 \
        -o plex \
        -g plex \
        /mnt/media
}

verify_media_identity() {
    log_info "Verifying Plex identity"

    id plex
    getent passwd "${PLEX_UID}"
    getent group "${PLEX_GID}"
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    log_info "Starting media bootstrap"

    install_media_packages
    create_plex_group
    create_plex_user
    create_media_directories
    verify_media_identity

    log_info "Media bootstrap complete"
}

main "$@"
