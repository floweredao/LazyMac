<div align="center">

# LazyMac

**Back up your Mac, and set up the next one cleanly.<br>Keep one list of everything on your Mac, already sorted into what to bring along and what to leave behind.**

[한국어](README-ko.md) · [Releases](https://github.com/floweredao/LazyMac/releases/latest) · [Daily history](https://lazymac-history.pages.dev/)

</div>

LazyMac keeps track of what is installed on your Mac and sets up your next Mac from scratch without copying years of leftovers. Instead of migrating a whole disk, it scans your apps, command-line tools, background jobs, settings, fonts, and secrets into a single catalog, then installs only what you still use. Backups go to a folder you pick (an external disk is safest) and need no extra tools; Google Drive is an option in Settings. Copying project folders that are not on GitHub or iCloud is an optional extra, and nothing is ever deleted.

## Main features

- **Clean setup from a single catalog.** Scans your Mac read-only and sorts apps, command-line tools, background jobs, settings, fonts, and secrets into ✅ bring, ⛔ leave behind, and ❓ your call.
- **Four-step restore in the app or one command in Terminal.** Pick what to install in *Restore > Apps and Settings*, or run `bin/setup.sh` to install every ✅ item in order.
- **Profiles and multi-Mac support.** Define base profiles (like `pro` or `air`) and add-on profiles (like `dev`, `light`, or `outside`), compare any profile with this Mac, and keep per-Mac scans in `inventory/<Mac name>/` so pruning only drops items removed from every Mac.
- **App sources manager.** Check and update where non-Homebrew apps come from (GitHub releases, download pages, or source builds) right in the app.
- **Encrypted secrets bundle.** Packs sign-in files, SSH keys, Keychain items, and private job files into one passphrase-locked [age](https://age-encryption.org) archive (`secrets/secrets.tar.age`), and checks commits with `gitleaks` before pushing.
- **Back Up This Mac in one click.** Lists your apps and tools, saves your settings files and macOS settings, and copies them to your backup place. A local folder works without rclone; Google Drive is optional.
- **Optional folder backup and restore.** Copies chosen folders to a local folder or, if you choose it, Google Drive (or any rclone remote), skips build artifacts and secrets, and restores missing files without overwriting what is already on your Mac.

## Install

Download `LazyMac-<version>.zip` from [Releases](https://github.com/floweredao/LazyMac/releases/latest), unzip it, and move `LazyMac.app` to `/Applications`.

Because the app is signed ad hoc rather than notarized by Apple, macOS blocks it the first time you open it. Open **System Settings > Privacy & Security** and click **Open Anyway** at the bottom. If you plan to run scheduled backups in the background, grant **Full Disk Access** to LazyMac (there is a shortcut button in *Back Up > Schedule*).

## First run

You can use LazyMac with a GitHub repository for your catalog, with folder backups, or both:

1. Open **LazyMac.app**.
2. To track and restore apps and settings, go to **Restore > Apps and Settings**. In the **Prepare** step, click the buttons to install Homebrew and the GitHub CLI (`gh`), sign in to GitHub, and clone or pick your catalog repository (for example `alex/lazymac` into `~/Documents/lazymac`).
3. In **Back Up > Overview**, click **Scan This Mac** (or run `bin/scan.sh` in Terminal). LazyMac reads your installed apps, Homebrew packages, App Store apps, global CLI tools, fonts, and LaunchAgents into `inventory/<Mac name>/`.
4. Run `bun bin/catalog.ts check` to see newly discovered items, record your decisions (`keep`, `drop`, or `ask`) in `catalog.tsv`, and run `bun bin/catalog.ts render` to update `setup/` and your README tables.

<!-- counts:begin -->
| Area | ✅ bring | ⛔ leave | ❓ your call |
|---|---:|---:|---:|
| Apps | 12 | 3 | 0 |
| Command-line tools | 18 | 2 | 0 |
| Running in the background | 4 | 1 | 0 |
| Settings and fonts | 6 | 0 | 0 |
| Secrets and sign-ins | 3 | 0 | 0 |
| Kept in other repos | 2 | 0 | 0 |
| Leftovers on this Mac | 0 | 2 | 0 |
| **Total** | **45** | **8** | **0** |
<!-- counts:end -->

<!-- ask:begin -->
Nothing right now.
<!-- ask:end -->

<details>
<summary><b>Example catalog preview</b></summary>

<!-- catalog:begin -->
| Section | Name | What it does | Decision | On the new Mac |
|---|---|---|---|---|
| Apps | Ghostty | Terminal emulator | ✅ bring: Used today | auto (Homebrew) |
| Apps | Visual Studio Code | Code editor | ✅ bring: Used today | by hand |
| Apps | Raycast | Launcher and quick actions | ✅ bring: Running now | auto (Homebrew) |
| Apps | Ice | Menu bar manager | ⛔ leave: Replaced | - |
| Command-line tools | git | Version control | ✅ bring: Used today | auto (Homebrew) |
| Command-line tools | gh | GitHub CLI | ✅ bring: Used today | auto (Homebrew) |
| Command-line tools | bun | JavaScript runtime and package manager | ✅ bring: Used today | auto (bun installer) |
| Command-line tools | age | File encryption for the secrets bundle | ✅ bring: Used today | auto (Homebrew) |
| Command-line tools | rclone | Cloud file sync for folder backups | ✅ bring: Used today | auto (Homebrew) |
<!-- catalog:end -->

</details>

## Daily backup

Open **Back Up > Schedule** (or **LazyMac > Settings**, `⌘,`), turn on **Back up automatically**, choose how often it should run (every hour, every few hours, every day, or every week), and click **Apply**. LazyMac writes `~/Library/LaunchAgents/local.lazymac-daily.plist` and loads `local.lazymac-daily` so backups run even when the app is closed.

When `bin/daily.sh` runs on the main Mac (`role` set to `main` in `machines.tsv`), it:

1. Scans this Mac into `inventory/<host>/` and commits the scan after checking with `gitleaks`.
2. Prunes rows from `catalog.tsv` that have disappeared from every Mac's scan, re-renders `setup/` and the READMEs, and commits.
3. Saves the day's catalog snapshot to `snapshots/<date>.tsv`, commits, and pushes to GitHub (pulling with `--rebase` if another Mac pushed first).
4. Publishes the public history site with `bun bin/snapshot.ts deploy`.
5. If file backup is enabled (`files on` in `storage.conf`), copies the folders listed in `backup.conf` with `bin/nogit-backup.sh rclone` and verifies them with `--check`.

On a secondary Mac (`role` set to `extra`), the scheduled run only updates and pushes `inventory/<host>/`, plus its own folder backup when enabled. Logs are kept for 30 days in `~/Library/Logs/lazymac-daily/<date>.log`.

## Restore to a new Mac

### With the app

1. Complete the initial macOS setup and sign in to the App Store.
2. Install **LazyMac.app** from [Releases](https://github.com/floweredao/LazyMac/releases/latest).
3. If you backed up folders, open **Restore > Folders**, click **Find Backed-Up Folders**, select the folders you want, and click **Restore**. Existing files on the Mac are never overwritten unless you turn on **Replace files here that are older than the backup**.
4. Open **Restore > Apps and Settings** and step through **Prepare**, **Choose** (pick a Mac profile like `pro` or `air`, toggle add-ons like `dev` or `light`, or adjust individual items), **Review**, and **Install**. When `sudo` or `age` asks for a password or passphrase, the input bar below the console turns orange.

### With the terminal

After signing in to the App Store, open Terminal and run:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
gh repo clone alex/lazymac ~/Documents/lazymac
~/Documents/lazymac/bin/setup.sh
```

To install a specific profile instead of every ✅ item, pass `--profile`:

```sh
~/Documents/lazymac/bin/setup.sh --profile air,light
```

See the [restore guide](docs/restore.md) for what to do on your old Mac before switching and what each step of `bin/setup.sh` does.

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

## Screenshots

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/app-dark.png"><img src="docs/app.png" width="760" alt="LazyMac Back Up overview"></picture>

## Documentation

| Guide | What it covers |
|---|---|
| [LazyMac in detail](docs/guide.md) | App screens, app sources, profiles, using multiple Macs, terminal workflow, and building releases |
| [Restore guide](docs/restore.md) | Checklist before leaving your old Mac, every `bin/setup.sh` step, and post-setup manual steps |
| [Keeping the list](docs/maintain.md) | How `catalog.tsv`, `groups.tsv`, scans, pruning, profiles, and snapshots fit together |
| [Secrets index](docs/secrets.md) | How `secrets/manifest.txt` and `secrets/secrets.tar.age` pack and restore credentials and Keychain items |
