# Homelab

A Proxmox-based homelab automation and Docker platform for building repeatable VMs instead of collecting snowflake servers.

This repository turns an Ubuntu cloud-init template into a standardized host, bootstraps the roles it needs, and deploys reusable Compose stacks under `/opt/docker/<stack>/compose.yaml`. Git holds the rebuildable configuration; application state, media, backups, and secrets live elsewhere.

The hardware may be in a basement, but the deployment process has standards.

## What it does

- Creates Proxmox VMs from a cloud-init template with interactive CPU, memory, disk, network, VLAN, and role selection.
- Builds cloud-init user data, injects SSH access, and performs a Git-backed first-boot bootstrap.
- Applies a common Ubuntu baseline and installs Docker when a selected role needs it.
- Deploys repeatable Docker Compose stacks with a consistent runtime layout.
- Mounts shared storage through Docker-managed NFS volumes where practical.
- Provides one maintenance command for updating a host and its stack.

## How it fits together

```text
Proxmox template
      │
      ▼
proxmox/newvm.sh ──► cloud-init ──► bootstrap/bootstrap.sh
                                           │
                           ┌───────────────┼───────────────┐
                           ▼               ▼               ▼
                        common           docker       selected role
                                                            │
                                                            ▼
                                            /opt/docker/<stack>/compose.yaml
```

On a configured Proxmox host, launch the interactive VM builder:

```bash
sudo ./proxmox/newvm.sh
```

On a deployed Docker VM, update a stack and its host:

```bash
sudo update-stack.sh plex
```

The updater validates the stack name, updates Ubuntu packages, pulls current images, recreates the Compose project, and prunes unused packages and images.

## Repository map

| Path | Purpose |
| --- | --- |
| `proxmox/` | Interactive VM creation and cloud-init generation |
| `bootstrap/` | First-boot dispatcher and role modules |
| `compose/` | Reusable application stacks |
| `scripts/` | Day-two maintenance tooling |
| `config/` | Shared homelab defaults |
| `lib/` | Shell logging and bootstrap helpers |
| `docs/` | Architecture and release-safety notes |

## Current stacks

- **Media automation:** Sonarr, Radarr, Prowlarr, SABnzbd, and Seerr
- **Plex:** host-networked media server with read-only NFS media
- **Nginx Proxy Manager:** reverse proxy and certificate management
- **Technitium:** DNS and DHCP using host networking
- **Backrest + Restic REST Server:** backup administration and NFS-backed repository storage (Work in Progress)

## Design principles

- **Repeatable by default.** Rebuilding should be less exciting than troubleshooting.
- **Git is the source of truth.** Scripts and deployment configuration are versioned; credentials are not.
- **Disposable hosts, persistent data.** VMs and containers can be recreated without treating their local disks as sacred artifacts.
- **One runtime convention.** Docker stacks live at `/opt/docker/<stack>/compose.yaml`.
- **Storage belongs with the stack.** Docker-managed NFS volumes avoid unnecessary host-level mounts.
- **Predictable infrastructure.** Proxmox VMIDs come from the cluster, while address and VLAN choices follow a consistent interactive workflow.

## Security and public use

Secrets, deploy keys, runtime `.env` files, generated cloud-init data, and application state are intentionally excluded from Git. Before publishing a fork, review the [public-release audit](docs/public-release-audit.md) and replace environment-specific addresses, paths, usernames, and repository references.

This is built for one opinionated environment, not presented as a turnkey distribution. Borrow the patterns, adapt the assumptions, and read every script before giving it root privileges.

## Contributors

Built and operated by **Charles Johnson**, with architecture, documentation, debugging, and implementation assistance from **ChatGPT** and **Codex**. See [CONTRIBUTORS.md](CONTRIBUTORS.md) for the full credit—and proof that even a one-person infrastructure team can hold design meetings.
