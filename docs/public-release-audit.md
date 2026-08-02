# Public-release safety audit

**Audit date:** 2026-08-01

**Remote `main` baseline audited:** `d80ae07730d117d2ad18241995bed9c083ac4ad6`

**Verdict:** **SAFE TO REMAIN PUBLIC.**

No usable passwords, API keys, access tokens, API secrets, Plex tokens or claims,
Homarr encryption keys, Proxmox tokens, Nginx Proxy Manager credentials, provider
or DDNS credentials, private SSH or TLS keys, password hashes, cloud-init secrets,
runtime `.env` files, databases, configuration exports, or backup archives were
found in the current tracked tree or reachable Git history.

No credential rotation or Git history rewrite is indicated by the evidence
reviewed. This audit record and the accompanying `.gitignore` hardening are also
within the reviewed release tree; the final published commit was rescanned after
creation.

## Accepted-risk scope

The following deliberately are not release blockers or remediation findings:

- RFC1918/private IP addresses, internal topology, internal domains, service
  ports, NFS paths, storage layout, usernames, timezone, and naming conventions;
- the unauthenticated Restic REST server in `compose/restic/compose.yaml`, because
  the service is not configured for use, its network is firewalled, and Charles
  explicitly accepts the current state;
- Charles's name, public GitHub identity, and commit attribution metadata.

These decisions accept disclosure and operational risk; they do not imply that
private addressing or a firewall replaces authentication for a production-ready
backup service.

## Findings

### Release blockers

None.

### Non-blocking observations

- `compose/proxy/compose.yaml` references Homarr's key as
  `${SECRET_ENCRYPTION_KEY}`. The tracked `compose/proxy/.env.example` contains
  only `SECRET_ENCRYPTION_KEY=CHANGE_ME`; no real Homarr key appears in the commit
  that added the service or elsewhere in reachable history.
- Runtime `.env` files are ignored while `.env.example` templates remain
  trackable. Ignore coverage also includes common secret files, deploy keys,
  private-key formats, password files, Terraform variable files, generated
  cloud-init snippets, runtime application data, databases, exports, backups,
  and archives.
- The historical `compose/restic/.env.example` contains only explicit
  `CHANGE_ME_*` placeholders. It does not contain working credentials.
- `proxmox/newvm.sh` reads a deploy key and a console recovery password at
  runtime. The key is not embedded in the repository, and the generated password
  hash is not committed.

## Review performed

The review covered every tracked file and every reachable commit and blob on all
cloned refs, including the compose and documentation changes made on 2026-08-01.
It included checks for:

- private-key and certificate-key headers;
- GitHub, AWS, Cloudflare, Slack, Stripe, Plex, DDNS, and generic credential
  formats;
- password, secret, token, credential, API-key, and encryption-key assignments;
- cloud-init password material and deleted sensitive filenames;
- `.env` files, databases, dumps, exported configuration, backups, and archives;
- accidentally pasted credentials or terminal output in README, audit, example,
  and documentation files.

Gitleaks 8.30.1 reported zero findings against both the working tree and full Git
history. Manual pattern and diff review also reported no usable credentials.
`git fsck --full --no-reflogs --unreachable` reported no unreachable objects in
the fresh clone.

## Release checklist

- [x] Review the latest remote `main` tree.
- [x] Review all reachable Git history and deleted files.
- [x] Confirm Homarr uses an environment-variable reference, not a committed key.
- [x] Confirm runtime `.env` files and common secret/state artifacts are ignored.
- [x] Review today's README, audit, example, and compose changes.
- [x] Record the accepted private-network and Restic risk decisions.
- [x] Run an automated history-aware secret scan.
- [x] Rescan the final release commit before push.

## Scope boundary

This audit covers repository contents and Git history. It does not inspect GitHub
Actions secrets, deploy keys stored in GitHub, branch settings, releases, issues,
pull requests, container images, the live Proxmox host, firewall enforcement, or
external secret stores.
