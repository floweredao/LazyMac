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

- `backend gdrive|local`: `gdrive` (the default) uses Google Drive through rclone: install it with `brew install rclone` and create a remote with `rclone config` (the welcome window and Settings > Backup Place show these steps). `local` copies to a folder or external disk and never needs rclone. A file with no `backend` line means `gdrive`, unless it has a `local` line.
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

## The automatic backup job (`local.lazymac-daily`)

You do not write this file by hand. Turning on **Back up automatically** (Back Up > Schedule, or LazyMac > Settings) writes `~/Library/LaunchAgents/local.lazymac-daily.plist` for this Mac and loads it with `launchctl bootstrap`; turning it off unloads and removes it. Changing the schedule keeps every other key of the existing file. From Terminal, `/Applications/LazyMac.app/Contents/MacOS/lazymac --schedule daily:04:00` does the same (`hourly[:MM]`, `every:<N>[:HH:MM]`, `daily:HH:MM`, `weekly:<0-6>:HH:MM`, `show`, or `off`).

[`launchd/local.lazymac-daily.plist`](../launchd/local.lazymac-daily.plist) is a sample of what the app writes, with `/Users/you` for your home folder and `/Users/you/lazymac` for your list repo:

| Key | What the app puts there |
|---|---|
| `ProgramArguments` | With a list repo and bun: `bun exec "/bin/zsh '<repo>/bin/daily.sh' --if-due"`. A `/bin/zsh` that launchd starts cannot read `~/Documents`, but bun can, and its child shell inherits that. Without a repo or bun: the app's own binary with `--run-backup --if-due` (give LazyMac Full Disk Access) |
| `WorkingDirectory` | The list repo, or your home folder |
| `EnvironmentVariables` | `HOME`, a `PATH` with Homebrew, `~/.bun/bin` and `~/.local/bin`, and `LAZYMAC_DATA` / `LAZYMAC_STORAGE_CONF` when the app was started with them |
| `StartCalendarInterval` | The schedule you chose |
| `RunAtLoad`, `StartInterval` (1800) | Catch-up: the job also starts at login and every 30 minutes, and `--if-due` makes it back up only when a backup is due |
| `StandardOutPath`, `StandardErrorPath` | `~/Library/Logs/lazymac-daily/launchd.log` |

Set `LAZYMAC_LAUNCHAGENTS_DIR` to write the job to another folder (the tests use this with a fake `launchctl` in `LAZYMAC_LAUNCHCTL`).

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
