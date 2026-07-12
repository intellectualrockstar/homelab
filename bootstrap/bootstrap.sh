#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/functions.sh"

declare -a RESOLVED_MODULES=()

append_module() {
    local module="$1"
    local existing

    for existing in "${RESOLVED_MODULES[@]}"; do
        [[ "${existing}" == "${module}" ]] && return
    done

    RESOLVED_MODULES+=("${module}")
}

resolve_modules() {
    local requested_module

    # Every homelab VM receives the common baseline.
    append_module "common"

    for requested_module in "$@"; do
        case "${requested_module}" in
            common)
                ;;
            docker)
                append_module "docker"
                ;;
            media)
                append_module "docker"
                append_module "media"
                ;;
            technitium)
                append_module "docker"
                append_module "technitium"
                ;;
            *)
                die "Unknown module: ${requested_module}"
                ;;
        esac
    done
}

run_module() {
    local module="$1"
    local module_path="${SCRIPT_DIR}/${module}.sh"

    [[ -f "${module_path}" ]] || die "Unknown module: ${module}"
    [[ -r "${module_path}" ]] || die "Module is not readable: ${module_path}"

    log_info "Running module: ${module}"
    bash "${module_path}"
}

main() {
    local module

    require_root
    resolve_modules "$@"

    for module in "${RESOLVED_MODULES[@]}"; do
        run_module "${module}"
    done

    log_info "All requested bootstrap modules completed"
}

main "$@"
