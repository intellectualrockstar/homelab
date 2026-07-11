#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

install_common_packages() {
    log_info "Updating package lists"
    apt-get update

    log_info "Installing common packages"
    apt_install \
        bash-completion \
        ca-certificates \
        curl \
        git \
        htop \
        jq \
        nano \
        openssh-server \
        qemu-guest-agent \
        wget
}

configure_timezone() {
    log_info "Setting timezone to ${TIMEZONE}"
    timedatectl set-timezone "${TIMEZONE}"
}

configure_services() {
    log_info "Enabling SSH and QEMU guest agent"
    systemctl enable --now ssh
    systemctl enable qemu-guest-agent

    # The agent may not start until Proxmox exposes the guest-agent socket.
    systemctl restart qemu-guest-agent 2>/dev/null || true
}

configure_aliases() {
    log_info "Installing common shell aliases"

    cat >/etc/profile.d/homelab-aliases.sh <<'EOF'
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -CF'
EOF

    chmod 0644 /etc/profile.d/homelab-aliases.sh
}

cleanup_packages() {
    log_info "Cleaning package cache"
    apt-get autoremove -y
    apt-get clean
}

main() {
    require_root
    load_config "${REPO_ROOT}"

    log_info "Starting common bootstrap"

    install_common_packages
    configure_timezone
    configure_services
    disable_ufw
    configure_aliases
    cleanup_packages

    log_info "Common bootstrap complete"
}

main "$@"
