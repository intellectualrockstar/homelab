#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

remove_conflicting_packages() {
    log_info "Removing packages that conflict with Docker CE"

    apt-get remove -y \
        containerd \
        docker-compose \
        docker-compose-v2 \
        docker-doc \
        docker.io \
        podman-docker \
        runc 2>/dev/null || true
}

configure_docker_repository() {
    log_info "Configuring Docker apt repository"

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    # shellcheck source=/etc/os-release
    source /etc/os-release

    cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME}}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

install_docker() {
    log_info "Installing Docker Engine and Docker Compose"

    apt-get update

    apt_install \
        containerd.io \
        docker-buildx-plugin \
        docker-ce \
        docker-ce-cli \
        docker-compose-plugin
}

configure_docker() {
    log_info "Enabling Docker services"

    systemctl enable --now containerd
    systemctl enable --now docker

    if id "${ADMIN_USER}" >/dev/null 2>&1; then
        usermod -aG docker "${ADMIN_USER}"
    else
        log_warn "Admin user ${ADMIN_USER} does not exist; Docker group was not assigned"
    fi

    install -d \
        -m 0775 \
        -o root \
        -g docker \
        "${DOCKER_ROOT}"

    cat >/etc/profile.d/docker-aliases.sh <<'EOF'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
EOF

    chmod 0644 /etc/profile.d/docker-aliases.sh
}

verify_docker() {
    docker --version
    docker compose version
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    log_info "Starting Docker bootstrap"

    remove_conflicting_packages
    configure_docker_repository
    install_docker
    configure_docker
    verify_docker

    log_info "Docker bootstrap complete"
}

main "$@"
