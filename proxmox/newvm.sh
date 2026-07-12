#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# Homelab Proxmox VM Launcher
#
# Clones the Ubuntu Cloud-Init template, configures hardware and networking,
# injects SSH credentials, clones the private homelab Git repository, and runs
# the selected bootstrap modules.
# ==============================================================================

readonly TEMPLATE_ID="9000"
readonly DEFAULT_STORAGE="local-lvm"
readonly SNIPPET_STORAGE="local"
readonly SNIPPET_DIRECTORY="/var/lib/vz/snippets"

readonly CONFIG_DIRECTORY="/etc/homelab-vm"
readonly DEPLOY_KEY_FILE="${CONFIG_DIRECTORY}/deploy_key"
readonly AUTHORIZED_KEYS_FILE="${CONFIG_DIRECTORY}/authorized_keys"

readonly GIT_REPOSITORY="git@github.com:intellectualrockstar/homelab.git"
readonly GIT_DIRECTORY="/opt/homelab"
readonly ADMIN_USER="charles"

readonly DEFAULT_CORES="2"
readonly DEFAULT_MEMORY="2048"
readonly DEFAULT_DISK_SIZE="20"
readonly DEFAULT_BRIDGE="vmbr0"

declare -a NETWORK_OPTIONS=()
declare -a IPCONFIG_OPTIONS=()
declare -a SELECTED_MODULES=("common")

fatal() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || fatal "Run this command as root."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fatal "Required command is missing: $1"
}

require_file() {
    [[ -f "$1" ]] || fatal "Required file is missing: $1"
}

prompt_input() {
    local title="$1"
    local message="$2"
    local default_value="${3:-}"
    local result

    result="$(
        whiptail \
            --title "${title}" \
            --inputbox "${message}" \
            10 70 \
            "${default_value}" \
            3>&1 1>&2 2>&3
    )" || exit 1

    printf '%s' "${result}"
}

prompt_yes_no() {
    local title="$1"
    local message="$2"

    whiptail \
        --title "${title}" \
        --yesno "${message}" \
        10 70
}

get_next_vmid() {
    pvesh get /cluster/nextid
}

validate_integer() {
    local label="$1"
    local value="$2"

    [[ "${value}" =~ ^[0-9]+$ ]] ||
        fatal "${label} must be a whole number."
}

validate_required() {
    local label="$1"
    local value="$2"

    [[ -n "${value}" ]] || fatal "${label} cannot be blank."
}

select_modules() {
    local selections

    selections="$(
        whiptail \
            --title "Bootstrap Add-ons" \
            --checklist \
            "Common always runs. Select optional add-ons:" \
            15 70 5 \
            "docker" "Install Docker Engine and Docker Compose" OFF \
            "media" "Install Docker plus media/NFS configuration" OFF \
            3>&1 1>&2 2>&3
    )" || exit 1

    if grep -qw "media" <<<"${selections}"; then
        # Media requires Docker. Keep execution order explicit.
        SELECTED_MODULES+=("docker" "media")
    elif grep -qw "docker" <<<"${selections}"; then
        SELECTED_MODULES+=("docker")
    fi
}

configure_networks() {
    local nic_count="$1"
    local gateway_used="false"

    local nic_index
    for ((nic_index = 0; nic_index < nic_count; nic_index++)); do
        local bridge
        local vlan
        local mode
        local mac_config
        local ip_config

        bridge="$(
            prompt_input \
                "NIC ${nic_index}" \
                "Proxmox bridge for NIC ${nic_index}:" \
                "${DEFAULT_BRIDGE}"
        )"

        vlan="$(
            prompt_input \
                "NIC ${nic_index}" \
                "Optional VLAN tag for NIC ${nic_index}.\nLeave blank for untagged:" \
                ""
        )"

        mac_config="virtio,bridge=${bridge}"

        if [[ -n "${vlan}" ]]; then
            validate_integer "VLAN tag" "${vlan}"
            mac_config+=",tag=${vlan}"
        fi

        mode="$(
            whiptail \
                --title "NIC ${nic_index} Addressing" \
                --menu \
                "Choose IPv4 configuration:" \
                15 70 4 \
                "dhcp" "Obtain address using DHCP" \
                "static" "Configure a static IPv4 address" \
                3>&1 1>&2 2>&3
        )" || exit 1

        if [[ "${mode}" == "dhcp" ]]; then
            ip_config="ip=dhcp"
            DHCP_PRESENT="true"
        else
            local address
            local gateway=""

            address="$(
                prompt_input \
                    "NIC ${nic_index}" \
                    "IPv4 address with CIDR, for example 192.168.1.10/24:" \
                    ""
            )"

            validate_required "Static address" "${address}"
            ip_config="ip=${address}"

            if [[ "${gateway_used}" == "false" ]]; then
                gateway="$(
                    prompt_input \
                        "NIC ${nic_index}" \
                        "Default gateway for this NIC.\nLeave blank if this NIC should not carry the default route:" \
                        ""
                )"

                if [[ -n "${gateway}" ]]; then
                    ip_config+=",gw=${gateway}"
                    gateway_used="true"
                fi
            fi
        fi

        NETWORK_OPTIONS+=("--net${nic_index}" "${mac_config}")
        IPCONFIG_OPTIONS+=("--ipconfig${nic_index}" "${ip_config}")
    done
}

yaml_indent_file() {
    local file="$1"
    local spaces="$2"

    sed "s/^/$(printf '%*s' "${spaces}" '')/" "${file}"
}

create_user_data() {
    local vmid="$1"
    local hostname="$2"
    local modules="$3"
    local output_file="$4"

    local deploy_key
    local authorized_keys

    deploy_key="$(yaml_indent_file "${DEPLOY_KEY_FILE}" 6)"
    authorized_keys="$(yaml_indent_file "${AUTHORIZED_KEYS_FILE}" 8)"

    cat >"${output_file}" <<EOF
#cloud-config

hostname: ${hostname}
manage_etc_hosts: true

users:
  - name: ${ADMIN_USER}
    gecos: Charles
    groups:
      - sudo
    shell: /bin/bash
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
${authorized_keys}

ssh_pwauth: false
disable_root: true

package_update: true

packages:
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

runcmd:
  - [mkdir, -p, /root/.ssh]
  - [chmod, "0700", /root/.ssh]
  - [mkdir, -p, /opt]
  - >
    GIT_SSH_COMMAND="ssh -F /root/.ssh/config"
    git clone "${GIT_REPOSITORY}" "${GIT_DIRECTORY}"
  - [chmod, +x, ${GIT_DIRECTORY}/bootstrap/bootstrap.sh]
  - ${GIT_DIRECTORY}/bootstrap/bootstrap.sh ${modules}
  - [rm, -f, /root/.ssh/homelab_deploy_key]
  - [rm, -f, /root/.ssh/config]
  - [touch, /var/lib/homelab-bootstrap-complete]

final_message: |
  Homelab bootstrap completed after \$UPTIME seconds.
  Modules: ${modules}
EOF

    chmod 600 "${output_file}"
}

show_summary() {
    local vmid="$1"
    local hostname="$2"
    local cores="$3"
    local memory="$4"
    local disk_size="$5"
    local modules="$6"
    local nic_count="$7"

    whiptail \
        --title "Confirm VM Creation" \
        --yesno \
        "VM ID: ${vmid}
Hostname: ${hostname}
CPU cores: ${cores}
Memory: ${memory} MB
Disk: ${disk_size} GB
NICs: ${nic_count}
Modules: ${modules}

Create and start this VM?" \
        18 72
}

main() {
    require_root

    require_command qm
    require_command pvesh
    require_command whiptail

    require_file "${DEPLOY_KEY_FILE}"
    require_file "${AUTHORIZED_KEYS_FILE}"

    mkdir -p "${SNIPPET_DIRECTORY}"

    local suggested_vmid
    local vmid
    local hostname
    local cores
    local memory
    local disk_size
    local nic_count
    local nameserver=""
    local search_domain=""
    local modules
    local snippet_file

    DHCP_PRESENT="false"

    suggested_vmid="$(get_next_vmid)"

    vmid="$(
        prompt_input \
            "New VM" \
            "VM ID:" \
            "${suggested_vmid}"
    )"

    hostname="$(
        prompt_input \
            "New VM" \
            "Hostname:" \
            ""
    )"

    cores="$(
        prompt_input \
            "New VM" \
            "CPU cores:" \
            "${DEFAULT_CORES}"
    )"

    memory="$(
        prompt_input \
            "New VM" \
            "Memory in MB:" \
            "${DEFAULT_MEMORY}"
    )"

    disk_size="$(
        prompt_input \
            "New VM" \
            "OS disk size in GB:" \
            "${DEFAULT_DISK_SIZE}"
    )"

    nic_count="$(
        prompt_input \
            "New VM" \
            "Number of network adapters:" \
            "1"
    )"

    validate_integer "VM ID" "${vmid}"
    validate_required "Hostname" "${hostname}"
    validate_integer "CPU cores" "${cores}"
    validate_integer "Memory" "${memory}"
    validate_integer "Disk size" "${disk_size}"
    validate_integer "NIC count" "${nic_count}"

    ((nic_count >= 1)) || fatal "At least one NIC is required."

    qm status "${vmid}" >/dev/null 2>&1 &&
        fatal "VM ID ${vmid} already exists."

    configure_networks "${nic_count}"

    if [[ "${DHCP_PRESENT}" == "false" ]]; then
        nameserver="$(
            prompt_input \
                "DNS Configuration" \
                "DNS server address:" \
                ""
        )"

        validate_required "DNS server" "${nameserver}"

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
        "${cores}" \
        "${memory}" \
        "${disk_size}" \
        "${modules}" \
        "${nic_count}" || exit 0

    snippet_file="${SNIPPET_DIRECTORY}/homelab-vm-${vmid}.yaml"

    create_user_data \
        "${vmid}" \
        "${hostname}" \
        "${modules}" \
        "${snippet_file}"

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

    if [[ -n "${nameserver}" ]]; then
        qm set "${vmid}" --nameserver "${nameserver}"
    fi

    if [[ -n "${search_domain}" ]]; then
        qm set "${vmid}" --searchdomain "${search_domain}"
    fi

    qm set "${vmid}" \
        --cicustom "user=${SNIPPET_STORAGE}:snippets/$(basename "${snippet_file}")"

    # The imported cloud image is smaller than the requested final disk size.
    # qm disk resize expects the desired absolute size.
    qm disk resize "${vmid}" scsi0 "${disk_size}G"

    qm cloudinit update "${vmid}"

    printf 'Starting VM %s...\n' "${vmid}"
    qm start "${vmid}"

    printf '\nVM %s (%s) created and started.\n' "${vmid}" "${hostname}"
    printf 'Cloud-Init snippet: %s\n' "${snippet_file}"
    printf 'Selected modules: %s\n' "${modules}"
    printf '\nWatch the console or run:\n'
    printf '  qm terminal %s\n' "${vmid}"
}

main "$@"
