# Advanced settings

English · [한국어](advanced-ko.md) · [Back to README](../README.md)

Config files, hooks, and environment variables for people who use LazyMac from Terminal.

## Storage

LazyMac separates catalog setup from folder backup. Folder and project backup is **off by default** (`files off`) so a daily catalog run never requires cloud storage unless you turn it on.

### Storage configuration (`storage.conf`)

Storage behavior is configured in `~/Library/Application Support/lazymac/storage.conf` (override the path with `LAZYMAC_STORAGE_CONF`):

```text
backend local
local /Volumes/Backup/LazyMac
files off
```

- `backend local|gdrive`: `local` (the default) copies to a folder or external disk and never needs rclone. `gdrive` uses Google Drive through rclone: install it with `brew install rclone` and create a remote with `rclone config` (Settings > Backup Place shows these steps). A file with a `remote` line and no `backend` line still means `gdrive`.
- `remote <remote:path>`: the rclone remote and folder path (for example `gdrive:LazyMac` or `gdrive:LazyMac/Alexs-MacBook-Pro`).
- `local <path>`: the local destination folder when using a local backend.
- `files on|off`: turns scheduled folder and project backup on or off in `bin/daily.sh`. The default is `off`.

### Folder list (`backup.conf`)

The folders to copy and any extra exclude patterns live in `~/Library/Application Support/lazymac/backup.conf` (edited in **Back Up > Folders**, or overridden with `LAZYMAC_BACKUP_CONF`):

```text
remote gdrive:LazyMac/Alexs-MacBook-Pro
folder ~/Documents/Notes
folder ~/Pictures/Studio
exclude *.mov
```

`bin/nogit-backup.sh` always skips dependencies and build caches (`node_modules`, `.build`, `dist`, `DerivedData`, `target`, `.venv`, etc.), secret-looking files (`.env`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`, `*credentials*.json`), any file flagged by `gitleaks`, and sub-folders that are already Git repositories with an `origin` remote.

## Hooks and environment variables

### Hooks (`LAZYMAC_HOOKS`)

`bin/daily.sh` looks for executable hooks in `~/.config/lazymac/hooks` (or the directory set in `LAZYMAC_HOOKS`):

- `~/.config/lazymac/hooks/before-daily`: runs at the start of `bin/daily.sh` before scanning or pulling (for example, to wait for a nightly package upgrade to finish). If it exits non-zero, the failure is logged and the daily job continues.
- `~/.config/lazymac/hooks/on-failure`: runs when `bin/daily.sh` fails, receiving the one-line error message as its first argument (`$1`). Use this to forward failure alerts to Slack, Discord, email, or a webhook. When `on-failure` is not present, LazyMac shows a macOS notification instead.

### Cloudflare Pages Keychain (`LAZYMAC_CF_KEYCHAIN`)

`bun bin/snapshot.ts deploy` publishes the static history site to Cloudflare Pages. It reads the Cloudflare API token and account ID from the macOS login Keychain under the service name in `LAZYMAC_CF_KEYCHAIN` (default: `lazymac-cloudflare`), using account names `api-token` and `account-id`:

```sh
security add-generic-password -U -a api-token -s lazymac-cloudflare -w "<YOUR_CF_API_TOKEN>"
security add-generic-password -U -a account-id -s lazymac-cloudflare -w "<YOUR_CF_ACCOUNT_ID>"
```

If those Keychain entries are not set, `snapshot.ts deploy` falls back to your active `wrangler login` session. To block personal terms from ever appearing on the public history page, list them one per line in `~/.config/lazymac/private-words` (or set `LAZYMAC_PRIVATE_WORDS`).
