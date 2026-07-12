#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# Homelab Proxmox VM Launcher
# ==============================================================================
#
# Creates a new Ubuntu VM from Proxmox template 9000, configures its virtual
# hardware and Cloud-Init networking, injects passwordless SSH access, clones
# the private homelab repository with a read-only deploy key, and runs the
# selected bootstrap modules on first boot.
#
# Host prerequisites:
#   - Proxmox VE with template 9000 and a Cloud-Init drive
#   - Directory storage "local" with snippets enabled
#   - VM storage "local-lvm"
#   - /etc/homelab-vm/deploy_key (read-only GitHub deploy private key)
#   - /etc/homelab-vm/authorized_keys (one or more SSH public keys)
#
# Bootstrap handoff:
#   - newvm passes selected roles to the Git-backed dispatcher
#   - bootstrap/bootstrap.sh always runs common and resolves dependencies
#
# Generated first-boot log:
#   /var/log/homelab-bootstrap.log
# ==============================================================================

# ------------------------------------------------------------------------------
# Proxmox and storage configuration
# ------------------------------------------------------------------------------

readonly TEMPLATE_ID="9000"
readonly DEFAULT_STORAGE="local-lvm"
readonly SNIPPET_STORAGE="local"
readonly SNIPPET_DIRECTORY="/var/lib/vz/snippets"
readonly OS_DISK="scsi0"

# ------------------------------------------------------------------------------
# Credentials and bootstrap configuration
# ------------------------------------------------------------------------------

readonly CONFIG_DIRECTORY="/etc/homelab-vm"
readonly DEPLOY_KEY_FILE="${CONFIG_DIRECTORY}/deploy_key"
readonly AUTHORIZED_KEYS_FILE="${CONFIG_DIRECTORY}/authorized_keys"

readonly GIT_REPOSITORY="git@github.com:intellectualrockstar/homelab.git"
readonly GIT_DIRECTORY="/opt/homelab"
readonly ADMIN_USER="charles"

# ------------------------------------------------------------------------------
# Interactive defaults
# ------------------------------------------------------------------------------

readonly DEFAULT_CORES="2"
readonly DEFAULT_MEMORY="2048"
readonly DEFAULT_DISK_SIZE="20"
readonly DEFAULT_BRIDGE="vmbr0"

# Arguments accumulated while prompting for network interfaces.
declare -a NETWORK_OPTIONS=()
declare -a IPCONFIG_OPTIONS=()
declare -a SELECTED_MODULES=()

DHCP_PRESENT="false"
STATIC_GATEWAY_PRESENT="false"

# ==============================================================================
# Error handling and prerequisites
# ==============================================================================

# Print a fatal error and terminate the launcher.
fatal() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Require execution as root because qm, snippets, and credential files need it.
require_root() {
    [[ ${EUID} -eq 0 ]] || fatal "Run this command as root."
}

# Require a command used by the launcher.
require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fatal "Required command is missing: $1"
}

# Require a nonempty regular file.
require_file() {
    [[ -s "$1" ]] || fatal "Required file is missing or empty: $1"
}

# Validate that template 9000 exists, is marked as a template, has scsi0, and
# includes a Cloud-Init drive. This prevents creating an unbootable clone.
validate_template() {
    local config

    config="$(qm config "${TEMPLATE_ID}" 2>/dev/null)" ||
        fatal "Template ${TEMPLATE_ID} does not exist."

    grep -q '^template: 1$' <<<"${config}" ||
        fatal "VM ${TEMPLATE_ID} is not marked as a Proxmox template."

    grep -q "^${OS_DISK}:" <<<"${config}" ||
        fatal "Template ${TEMPLATE_ID} is missing ${OS_DISK}."

    grep -Eq '^(ide|sata|scsi)[0-9]+: .*cloudinit' <<<"${config}" ||
        fatal "Template ${TEMPLATE_ID} is missing a Cloud-Init drive."
}

# Validate storage and create the directory used for generated snippets.
validate_snippet_storage() {
    pvesm status --storage "${SNIPPET_STORAGE}" >/dev/null 2>&1 ||
        fatal "Snippet storage ${SNIPPET_STORAGE} does not exist."

    pvesm list "${SNIPPET_STORAGE}" --content snippets >/dev/null 2>&1 ||
        fatal "Storage ${SNIPPET_STORAGE} does not allow snippets."

    install -d -m 0755 "${SNIPPET_DIRECTORY}"
}

# ==============================================================================
# Interactive prompt helpers
# ==============================================================================

# Display a text input dialog and print the entered value.
prompt_input() {
    local title="$1"
    local message="$2"
    local default_value="${3:-}"
    local result

    result="$(
        whiptail \
            --title "${title}" \
            --inputbox "${message}" \
            10 72 \
            "${default_value}" \
            3>&1 1>&2 2>&3
    )" || exit 1

    printf '%s' "${result}"
}

# Return the next unused VM ID reported by the Proxmox cluster.
get_next_vmid() {
    pvesh get /cluster/nextid --output-format json | tr -d '"'
}

# ==============================================================================
# Input validation
# ==============================================================================

# Require a nonempty value.
validate_required() {
    local label="$1"
    local value="$2"

    [[ -n "${value}" ]] || fatal "${label} cannot be blank."
}

# Require a positive whole number.
validate_positive_integer() {
    local label="$1"
    local value="$2"

    [[ "${value}" =~ ^[1-9][0-9]*$ ]] ||
        fatal "${label} must be a positive whole number."
}

# Require a legal Proxmox/Linux hostname.
validate_hostname() {
    local hostname="$1"

    [[ ${#hostname} -le 63 ]] || fatal "Hostname cannot exceed 63 characters."
    [[ "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] ||
        fatal "Hostname contains invalid characters."
}

# Validate an optional IEEE 802.1Q VLAN tag.
validate_vlan() {
    local vlan="$1"

    [[ "${vlan}" =~ ^[0-9]+$ ]] || fatal "VLAN tag must be a whole number."
    ((vlan >= 1 && vlan <= 4094)) || fatal "VLAN tag must be between 1 and 4094."
}

# Validate an IPv4 address, including the valid range of each octet.
validate_ipv4_address() {
    local address="$1"
    local octet
    local -a octets

    [[ "${address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r -a octets <<<"${address}"

    for octet in "${octets[@]}"; do
        ((10#${octet} >= 0 && 10#${octet} <= 255)) || return 1
    done
}

# Validate an IPv4 address followed by a CIDR prefix from 0 through 32.
validate_ipv4_cidr() {
    local value="$1"
    local address
    local prefix

    [[ "${value}" == */* ]] || return 1

    address="${value%/*}"
    prefix="${value##*/}"

    validate_ipv4_address "${address}" || return 1
    [[ "${prefix}" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]]
}

# Validate a gateway or DNS server IPv4 address.
validate_ipv4() {
    local address="$1"

    validate_ipv4_address "${address}"
}

# Display an input-validation error without terminating the launcher.
show_input_error() {
    local title="$1"
    local message="$2"

    whiptail \
        --title "${title}" \
        --msgbox "${message}" \
        10 72 \
        3>&1 1>&2 2>&3
}

# Prompt until a valid IPv4/CIDR value is entered.
prompt_ipv4_cidr() {
    local title="$1"
    local message="$2"
    local value

    while true; do
        value="$(prompt_input "${title}" "${message}" "")"

        if validate_ipv4_cidr "${value}"; then
            printf '%s' "${value}"
            return
        fi

        show_input_error \
            "${title}" \
            "Invalid IPv4/CIDR address: ${value:-<blank>}

Enter a valid value such as 192.168.51.20/24."
    done
}

# Prompt until a valid IPv4 address is entered. When allow_blank is true, an
# empty value is accepted for optional fields such as a secondary NIC gateway.
prompt_ipv4() {
    local title="$1"
    local message="$2"
    local default_value="${3:-}"
    local allow_blank="${4:-false}"
    local value

    while true; do
        value="$(prompt_input "${title}" "${message}" "${default_value}")"

        if [[ -z "${value}" && "${allow_blank}" == "true" ]]; then
            printf '%s' ""
            return
        fi

        if validate_ipv4 "${value}"; then
            printf '%s' "${value}"
            return
        fi

        show_input_error \
            "${title}" \
            "Invalid IPv4 address: ${value:-<blank>}

Enter a valid value such as 192.168.51.1."
    done
}

# ==============================================================================
# Module and network selection
# ==============================================================================

# Ask which optional roles the Git-backed bootstrap dispatcher should run.
# Dependency ordering and the mandatory common baseline are resolved in Git.
select_modules() {
    local selections

    selections="$(
        whiptail \
            --title "Bootstrap Add-ons" \
            --checklist \
            "Common always runs. Select optional add-ons:" \
            15 74 5 \
            "docker" "Install Docker Engine and Docker Compose" OFF \
            "media" "Install Docker plus media/NFS configuration" OFF \
            "technitium" "Install Technitium DNS and DHCP Server" OFF \
            3>&1 1>&2 2>&3
    )" || exit 1

    if grep -qw 'docker' <<<"${selections}"; then
        SELECTED_MODULES+=("docker")
    fi

    if grep -qw 'media' <<<"${selections}"; then
        SELECTED_MODULES+=("media")
    fi

    if grep -qw 'technitium' <<<"${selections}"; then
        SELECTED_MODULES+=("technitium")
    fi
}

# Prompt for each NIC and build matching qm --netN and --ipconfigN arguments.
# Only one static NIC may receive the default IPv4 gateway.
configure_networks() {
    local nic_count="$1"
    local gateway_used="false"
    local nic_index

    for ((nic_index = 0; nic_index < nic_count; nic_index++)); do
        local bridge
        local vlan
        local mode
        local net_config
        local ip_config

        bridge="$(prompt_input "NIC ${nic_index}" "Proxmox bridge:" "${DEFAULT_BRIDGE}")"
        validate_required "NIC ${nic_index} bridge" "${bridge}"

        vlan="$(
            prompt_input \
                "NIC ${nic_index}" \
                "Optional VLAN tag. Leave blank for untagged:" \
                ""
        )"

        net_config="virtio,bridge=${bridge},firewall=0"

        if [[ -n "${vlan}" ]]; then
            validate_vlan "${vlan}"
            net_config+=",tag=${vlan}"
        fi

        mode="$(
            whiptail \
                --title "NIC ${nic_index} Addressing" \
                --menu \
                "Choose IPv4 configuration:" \
                15 72 4 \
                "dhcp" "Obtain an address using DHCP" \
                "static" "Configure a static IPv4 address" \
                3>&1 1>&2 2>&3
        )" || exit 1

        if [[ "${mode}" == "dhcp" ]]; then
            ip_config="ip=dhcp"
            DHCP_PRESENT="true"
        else
            local address
            local gateway=""

            address="$(prompt_ipv4_cidr \
                    "NIC ${nic_index}" \
                    "IPv4 address with CIDR (example: 192.168.51.20/24):"
            )"
            ip_config="ip=${address}"

            if [[ "${gateway_used}" == "false" ]]; then
                gateway="$(prompt_ipv4 \
                        "NIC ${nic_index}" \
                        "Default gateway. Leave blank for no default route:" \
                        "" \
                        true
                )"

                if [[ -n "${gateway}" ]]; then
                    ip_config+=",gw=${gateway}"
                    gateway_used="true"
                    STATIC_GATEWAY_PRESENT="true"
                fi
            fi
        fi

        NETWORK_OPTIONS+=("--net${nic_index}" "${net_config}")
        IPCONFIG_OPTIONS+=("--ipconfig${nic_index}" "${ip_config}")
    done
}

# ==============================================================================
# Cloud-Init generation
# ==============================================================================

# Indent every line in a file for insertion into a YAML literal block.
yaml_indent_file() {
    local file="$1"
    local spaces="$2"
    local indentation

    printf -v indentation '%*s' "${spaces}" ''
    sed "s/^/${indentation}/" "${file}"
}

# Convert authorized_keys into a correctly indented YAML sequence. Blank lines
# and comments are ignored so the source file may remain human-readable.
yaml_authorized_keys() {
    local key

    while IFS= read -r key || [[ -n "${key}" ]]; do
        [[ -z "${key}" || "${key}" == \#* ]] && continue
        printf '      - %s\n' "${key}"
    done <"${AUTHORIZED_KEYS_FILE}"
}

# Generate per-VM Cloud-Init user-data. A dedicated first-boot script keeps the
# YAML simple, provides deterministic logging, and guarantees deploy-key cleanup
# whether bootstrap succeeds or fails.
create_user_data() {
    local hostname="$1"
    local modules="$2"
    local output_file="$3"
    local deploy_key
    local authorized_keys

    deploy_key="$(yaml_indent_file "${DEPLOY_KEY_FILE}" 6)"
    authorized_keys="$(yaml_authorized_keys)"
    [[ -n "${authorized_keys}" ]] || fatal "No SSH public keys found in ${AUTHORIZED_KEYS_FILE}."

    cat >"${output_file}" <<EOF
#cloud-config

hostname: ${hostname}
manage_etc_hosts: true
ssh_pwauth: false
disable_root: true
package_update: true

users:
  - name: ${ADMIN_USER}
    gecos: Charles
    groups:
      - sudo
    shell: /bin/bash
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    ssh_authorized_keys:
${authorized_keys}

packages:
  - ca-certificates
  - git
  - openssh-client

write_files:
  - path: /root/.ssh/homelab_deploy_key
    owner: root:root
    permissions: "0600"
    content: |
${deploy_key}

  - path: /root/.ssh/config
    owner: root:root
    permissions: "0600"
    content: |
      Host github.com
          HostName github.com
          User git
          IdentityFile /root/.ssh/homelab_deploy_key
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new

  - path: /etc/homelab-bootstrap.conf
    owner: root:root
    permissions: "0600"
    content: |
      HOMELAB_MODULES="${modules}"
      HOMELAB_REPOSITORY="${GIT_REPOSITORY}"

  - path: /usr/local/sbin/homelab-firstboot
    owner: root:root
    permissions: "0700"
    content: |
      #!/usr/bin/env bash
      set -Eeuo pipefail

      readonly LOG_FILE="/var/log/homelab-bootstrap.log"
      readonly DEPLOY_KEY="/root/.ssh/homelab_deploy_key"
      readonly SSH_CONFIG="/root/.ssh/config"
      readonly REPOSITORY="${GIT_REPOSITORY}"
      readonly REPOSITORY_DIR="${GIT_DIRECTORY}"
      readonly MODULES="${modules}"

      exec > >(tee -a "\${LOG_FILE}") 2>&1

      cleanup_credentials() {
          rm -f "\${DEPLOY_KEY}" "\${SSH_CONFIG}"
      }

      trap cleanup_credentials EXIT

      printf '[INFO] Starting homelab first-boot provisioning.\n'
      install -d -m 0700 /root/.ssh
      install -d -m 0755 /opt

      if [[ -e "\${REPOSITORY_DIR}" ]]; then
          printf '[ERROR] Clone destination already exists: %s\n' "\${REPOSITORY_DIR}" >&2
          exit 1
      fi

      GIT_SSH_COMMAND="ssh -F \${SSH_CONFIG}" \\
          git clone --branch main --single-branch "\${REPOSITORY}" "\${REPOSITORY_DIR}"

      [[ -d "\${REPOSITORY_DIR}/.git" ]] || {
          printf '[ERROR] Homelab repository clone verification failed.\n' >&2
          exit 1
      }

      [[ -f "\${REPOSITORY_DIR}/bootstrap/bootstrap.sh" ]] || {
          printf '[ERROR] bootstrap/bootstrap.sh is missing from the cloned repository.\n' >&2
          exit 1
      }

      chmod +x "\${REPOSITORY_DIR}/bootstrap/"*.sh

      # MODULES contains only launcher-selected role names. The Git-backed
      # dispatcher adds common and resolves role dependencies.
      # Word splitting is intentional so each role becomes one argument.
      # shellcheck disable=SC2086
      "\${REPOSITORY_DIR}/bootstrap/bootstrap.sh" \${MODULES}

      touch /var/lib/homelab-bootstrap-complete
      printf '[INFO] Homelab first-boot provisioning completed successfully.\n'

runcmd:
  - [bash, /usr/local/sbin/homelab-firstboot]

final_message: |
  Cloud-Init completed after \$UPTIME seconds.
  Homelab requested roles: ${modules:-common only}
EOF

    chmod 0600 "${output_file}"
}

# ==============================================================================
# Confirmation and VM creation
# ==============================================================================

# Show all important choices and require confirmation before changing Proxmox.
show_summary() {
    local vmid="$1"
    local hostname="$2"
    local description="$3"
    local cores="$4"
    local memory="$5"
    local disk_size="$6"
    local nic_count="$7"
    local modules="$8"

    whiptail \
        --title "Confirm VM Creation" \
        --yesno \
        "VM ID: ${vmid}
Hostname: ${hostname}
Description: ${description:-<none>}
CPU cores: ${cores}
Memory: ${memory} MB
Disk: ${disk_size} GB
NICs: ${nic_count}
Roles: ${modules:-common only}

Create and start this VM?" \
        20 76
}

# Clone the template and apply hardware, network, DNS, description, snippet,
# disk size, and Cloud-Init settings before starting the VM.
create_vm() {
    local vmid="$1"
    local hostname="$2"
    local description="$3"
    local cores="$4"
    local memory="$5"
    local disk_size="$6"
    local nameserver="$7"
    local search_domain="$8"
    local snippet_file="$9"

    printf 'Cloning template %s to VM %s...\n' "${TEMPLATE_ID}" "${vmid}"

    qm clone \
        "${TEMPLATE_ID}" \
        "${vmid}" \
        --name "${hostname}" \
        --full true \
        --storage "${DEFAULT_STORAGE}"

    qm set "${vmid}" \
        --cores "${cores}" \
        --memory "${memory}" \
        --agent enabled=1 \
        "${NETWORK_OPTIONS[@]}" \
        "${IPCONFIG_OPTIONS[@]}"

    if [[ -n "${description}" ]]; then
        qm set "${vmid}" --description "${description}"
    fi

    if [[ -n "${nameserver}" ]]; then
        qm set "${vmid}" --nameserver "${nameserver}"
    fi

    if [[ -n "${search_domain}" ]]; then
        qm set "${vmid}" --searchdomain "${search_domain}"
    fi

    qm set "${vmid}" \
        --cicustom "user=${SNIPPET_STORAGE}:snippets/$(basename "${snippet_file}")"

    qm disk resize "${vmid}" "${OS_DISK}" "${disk_size}G"
    qm cloudinit update "${vmid}"

    printf 'Starting VM %s...\n' "${vmid}"
    qm start "${vmid}"
}

# ==============================================================================
# Main program
# ==============================================================================

main() {
    require_root

    require_command grep
    require_command pvesh
    require_command pvesm
    require_command qm
    require_command sed
    require_command tee
    require_command whiptail

    require_file "${DEPLOY_KEY_FILE}"
    require_file "${AUTHORIZED_KEYS_FILE}"
    validate_template
    validate_snippet_storage

    local suggested_vmid
    local vmid
    local hostname
    local description
    local cores
    local memory
    local disk_size
    local nic_count
    local nameserver=""
    local search_domain=""
    local modules
    local snippet_file

    suggested_vmid="$(get_next_vmid)"

    vmid="$(prompt_input "New VM" "VM ID:" "${suggested_vmid}")"
    hostname="$(prompt_input "New VM" "Hostname:" "")"
    description="$(prompt_input "New VM" "Optional Proxmox description:" "")"
    cores="$(prompt_input "New VM" "CPU cores:" "${DEFAULT_CORES}")"
    memory="$(prompt_input "New VM" "Memory in MB:" "${DEFAULT_MEMORY}")"
    disk_size="$(prompt_input "New VM" "OS disk size in GB:" "${DEFAULT_DISK_SIZE}")"
    nic_count="$(prompt_input "New VM" "Number of network adapters:" "1")"

    validate_positive_integer "VM ID" "${vmid}"
    validate_required "Hostname" "${hostname}"
    validate_hostname "${hostname}"
    validate_positive_integer "CPU cores" "${cores}"
    validate_positive_integer "Memory" "${memory}"
    validate_positive_integer "Disk size" "${disk_size}"
    validate_positive_integer "NIC count" "${nic_count}"

    qm status "${vmid}" >/dev/null 2>&1 && fatal "VM ID ${vmid} already exists."

    configure_networks "${nic_count}"

    if [[ "${DHCP_PRESENT}" == "false" ]]; then
        [[ "${STATIC_GATEWAY_PRESENT}" == "true" ]] ||
            fatal "At least one static NIC needs a default gateway for first-boot provisioning."

        nameserver="$(prompt_ipv4 \
            "DNS Configuration" \
            "Bootstrap DNS server address:" \
            "1.1.1.1" \
            false
        )"

        search_domain="$(
            prompt_input \
                "DNS Configuration" \
                "Optional DNS search domain:" \
                ""
        )"
    fi

    select_modules
    modules="${SELECTED_MODULES[*]}"

    show_summary \
        "${vmid}" \
        "${hostname}" \
        "${description}" \
        "${cores}" \
        "${memory}" \
        "${disk_size}" \
        "${nic_count}" \
        "${modules}" || exit 0

    snippet_file="${SNIPPET_DIRECTORY}/homelab-vm-${vmid}.yaml"
    [[ ! -e "${snippet_file}" ]] || fatal "Snippet already exists: ${snippet_file}"

    create_user_data "${hostname}" "${modules}" "${snippet_file}"

    create_vm \
        "${vmid}" \
        "${hostname}" \
        "${description}" \
        "${cores}" \
        "${memory}" \
        "${disk_size}" \
        "${nameserver}" \
        "${search_domain}" \
        "${snippet_file}"

    printf '\nVM %s (%s) was created and started.\n' "${vmid}" "${hostname}"
    printf 'Cloud-Init snippet: %s\n' "${snippet_file}"
    printf 'Requested roles: %s\n' "${modules:-common only}"
    printf 'First-boot log: /var/log/homelab-bootstrap.log\n'
    printf '\nUse the Proxmox console or run: qm terminal %s\n' "${vmid}"
}

main "$@"
