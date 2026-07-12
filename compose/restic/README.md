# Restic backup service

This stack keeps the VM disposable:

- Docker is the only application dependency.
- The TrueNAS repository is mounted by Docker, not the host OS.
- No NFS entry is added to `/etc/fstab`.
- The repository data lives on `192.168.10.8:/mnt/MediaStorage/Backups`.
- The server runs continuously; the Restic CLI container runs only when requested.

## Runtime layout

```text
/opt/restic/
├── compose.yaml
├── .env
├── config/
└── scripts/
```

Copy this directory to `/opt/restic`, then create the local environment file:

```bash
cd /opt/restic
cp .env.example .env
chmod 600 .env
nano .env
```

Use different strong values for `RESTIC_REST_PASSWORD` and `RESTIC_PASSWORD`.
Do not commit `.env`.

## First-time initialization

Load the environment into the current shell so the user-creation command can use it:

```bash
cd /opt/restic
set -a
. ./.env
set +a
```

Create the REST server account in the NFS-backed volume:

```bash
docker compose run --rm rest-server create_user \
  "${RESTIC_REST_USERNAME}" "${RESTIC_REST_PASSWORD}"
```

Start the repository server:

```bash
docker compose up -d rest-server
docker compose ps
```

Initialize the encrypted Restic repository:

```bash
docker compose --profile tools run --rm restic init
```

Confirm that it is reachable:

```bash
docker compose --profile tools run --rm restic snapshots
```

## Routine administration

Run Restic commands through the on-demand CLI container:

```bash
docker compose --profile tools run --rm restic check
docker compose --profile tools run --rm restic snapshots
docker compose --profile tools run --rm restic stats
```

The `--append-only` server option prevents clients from deleting existing backup data.
Retention and pruning should be performed later through a separately controlled maintenance
workflow that temporarily has deletion access.

## Client repositories

With `--private-repos`, each REST username is confined to a repository having the same
name. The provided defaults therefore use `backup` for both
`RESTIC_REST_USERNAME` and `RESTIC_REPOSITORY_NAME`.

Client VMs should connect to:

```text
rest:http://192.168.51.25:8000/backup
```

Each client should use the same repository encryption password and REST credentials,
provided through its own uncommitted environment file or secret mechanism.
