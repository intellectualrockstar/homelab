#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"

# shellcheck source=../lib/functions.sh
source "${REPO_ROOT}/lib/functions.sh"

readonly DOWNLOAD_PAGE="https://ui.com/download/releases/unifi-os-server"

verify_supported_ubuntu() {
    # shellcheck source=/etc/os-release
    source /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] ||
        die "The UniFi OS Server role expects Ubuntu 24.04 or later."

    dpkg --compare-versions "${VERSION_ID:-0}" ge "24.04" ||
        die "UniFi OS Server requires Ubuntu 24.04 or later."
}

install_unifi_prerequisites() {
    log_info "Installing official UniFi OS Server host prerequisites"

    apt-get update
    apt_install \
        podman \
        slirp4netns \
        uidmap
}

verify_unifi_prerequisites() {
    local podman_version
    local slirp4netns_version

    podman_version="$(dpkg-query -W -f='${Version}' podman)"
    slirp4netns_version="$(dpkg-query -W -f='${Version}' slirp4netns)"

    dpkg --compare-versions "${podman_version}" ge "4.9.3" ||
        die "UniFi OS Server requires Podman 4.9.3 or later; found ${podman_version}."
    dpkg --compare-versions "${slirp4netns_version}" ge "1.2" ||
        die "UniFi OS Server requires slirp4netns 1.2 or later; found ${slirp4netns_version}."
}

print_manual_install_step() {
    log_info "UniFi OS Server prerequisites are ready."
    log_info "Manual next step: copy the latest Linux x64 installer link from ${DOWNLOAD_PAGE}"
    log_info "Then run: curl -fLO '<copied-installer-url>' && chmod +x ./<downloaded-installer> && sudo ./<downloaded-installer>"
    log_info "Complete setup in the UniFi UI, then restore the July 11 backup through the setup/migration UI."
}

main() {
    require_root
    verify_supported_ubuntu
    install_unifi_prerequisites
    verify_unifi_prerequisites
    print_manual_install_step
}

main "$@"
