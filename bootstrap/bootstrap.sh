#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/functions.sh"

run_module() {
    local module="$1"
    local module_path="${SCRIPT_DIR}/${module}.sh"

    [[ -f "${module_path}" ]] || die "Unknown module: ${module}"
    [[ -r "${module_path}" ]] || die "Module is not readable: ${module_path}"

    log_info "Running module: ${module}"
    bash "${module_path}"
}

main() {
    require_root

    if [[ $# -eq 0 ]]; then
        die "Usage: bootstrap.sh <module> [module ...]"
    fi

    for module in "$@"; do
        run_module "${module}"
    done

    log_info "All requested bootstrap modules completed"
}

main "$@"
