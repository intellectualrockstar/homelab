# Public-release safety audit

**Audit date:** 2026-08-01

**Audited revision:** `6e7ef24bab0d16137486b177d8c05b7cb849880a`

**Verdict:** **Not yet recommended for public release. Keep the repository private until the medium-severity Restic finding is remediated or explicitly accepted.**

No live passwords, API keys, access tokens, private keys, password hashes, TLS private keys, Plex claims/tokens, provider credentials, or public IP addresses were found in the current tracked tree or reachable Git history. No credential rotation or history purge is indicated by the evidence reviewed.

## Findings

| Severity | Location | Finding and impact | Recommended remediation |
| --- | --- | --- | --- |
| Medium | `compose/restic/compose.yaml:31` | The Restic REST server sets `DISABLE_AUTHENTICATION: "true"`. It is bound to an RFC1918 address, but any host able to reach that network can access the service; publishing the configuration also advertises this trust assumption. | Enable authentication before publication, store credentials outside Git, and confirm firewall/VLAN policy restricts port 8000. If unauthenticated access is intentional, document and formally accept the risk. |
| Low | `compose/media/compose.yaml`, `compose/plex/compose.yaml`, `compose/restic/compose.yaml` | Current files reveal RFC1918 addresses (`192.168.10.8`, `192.168.51.25`), NFS export names, service ports, and storage layout. These are not Internet-routable and are not credentials, but they provide a useful internal topology map. | Parameterize or replace these values before publication if topology privacy matters. Test any change against the deployment workflow; do not assume hiding RFC1918 addresses is a security control. |
| Low | Git history, including `fb8414c`, `2587382`, and `9f7e0dc` | Earlier revisions additionally reveal former service addresses (`192.168.51.15`, `192.168.10.25`) and the same NFS paths. Removing them only from the current tree would not remove them from public history. | Accept the historical topology disclosure or rewrite history before publication. No rewrite is required for credential safety based on this audit. |
| Informational | Git commit metadata, including `0b1717c`, `b1a8141`, and `5976b58` | Charles Johnson's name and `charles@intellectualrockstar.com` appear as author metadata. GitHub noreply addresses also appear. This is personally identifying information, not a secret. | Confirm the attribution and email exposure are intentional. If not, rewrite author metadata before publication and use a noreply address for future commits. |
| Informational | `config/defaults.conf`, `proxmox/newvm.sh`, `CONTRIBUTORS.md` | The admin username `charles`, GitHub account/repository, timezone, UID/GID conventions, Proxmox template/storage defaults, and deploy-key filesystem locations are disclosed. They do not grant access, but they fingerprint the environment. | Keep what is useful documentation; parameterize or generalize only the details Charles does not want associated with the public project. |
| Informational | `proxmox/newvm.sh` | Generated VMs grant the admin account passwordless sudo. Password SSH login is disabled and the recovery password is prompted for and hashed transiently, so no password was found in Git. This is an operational hardening choice rather than a release secret. | Confirm this trust model is intentional; consider narrower sudo policy for higher-security environments. |

## History review

The review covered all tracked files and all reachable commits and blobs on every cloned ref. It included searches for:

- private-key and certificate-key headers;
- common GitHub, AWS, Cloudflare, Slack, Stripe, Plex, DDNS, and generic token formats;
- password, secret, credential, token, API-key, and encryption-key assignments;
- email addresses, domain names, IPv4 addresses, cloud-init password material, and deleted sensitive filenames;
- unreachable objects reported by `git fsck` (none were reported).

The deleted historical `compose/restic/.env.example` contained only explicit `CHANGE_ME_*` placeholders, not working credentials. Dedicated tools such as Gitleaks, TruffleHog, and detect-secrets were not installed, so this was a manual and pattern-based review rather than a guarantee that no arbitrary high-entropy secret exists. A fresh automated scan is recommended immediately before changing repository visibility.

## Release checklist

- [ ] Require authentication for the Restic REST server, or explicitly accept and document the network trust boundary.
- [ ] Decide whether current and historical private topology details are acceptable in public.
- [ ] Confirm Charles's name, email address, GitHub identity, username, and timezone may be public.
- [ ] Run an automated history-aware secret scanner when available.
- [ ] Re-audit the final commit immediately before changing visibility.
- [ ] Keep the GitHub repository private until the blocker above is resolved.

## Scope note

This audit covers repository contents and Git history only. It does not validate GitHub Actions variables, deploy keys, branch settings, releases, issues, pull requests, container images, the live Proxmox host, firewall rules, or external secret stores.
