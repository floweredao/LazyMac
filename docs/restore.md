# Restore guide

English · [한국어](restore-ko.md) · [Back to README](../README.md)

The README has the short version. This page covers every step, what it needs, and what remains by hand.

## Contents

- [1. Before leaving the old Mac](#1-before-leaving-the-old-mac)
- [2. On the new Mac](#2-on-the-new-mac)
- [3. What each setup step does](#3-what-each-setup-step-does)
- [4. By hand, after setup](#4-by-hand-after-setup)
- [5. Check the result](#5-check-the-result)

## 1. Before leaving the old Mac

1. **Re-pack the encrypted bundle and push it.** It carries your sign-in files, Keychain items, private job plists, and personal scripts (see [secrets.md](secrets.md#encrypted-bundle)). `age` asks for the passphrase twice; keep it in your password manager.
   ```sh
   bin/secrets-pack.sh && git add secrets/secrets.tar.age && git commit -m "secrets: update encrypted bundle" && git push
   ```
2. **Back up folders and local app data that are not on GitHub.**
   Copy any local-only application databases to an external disk or over AirDrop. For folders tracked in `~/Library/Application Support/lazymac/backup.conf`, click *Back Up Now* in LazyMac or run `bin/nogit-backup.sh rclone`. On the new Mac, *Restore > Folders* in LazyMac brings them back.
3. **Refresh the list and make sure nothing is unclassified:**
   ```sh
   bin/scan.sh && bun bin/catalog.ts check
   ```
4. **Push every project repo** (check that `git status -sb` in each repo shows nothing ahead or uncommitted).

## 2. On the new Mac

Finish the macOS setup, sign in with your Apple ID, open the App Store once, and sign in. Then run:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
gh repo clone alex/lazymac ~/Documents/lazymac
~/Documents/lazymac/bin/setup.sh
```

The Homebrew installer also installs the Xcode Command Line Tools. For `gh auth login`, pick GitHub.com, HTTPS, and log in with a web browser.

`setup.sh dotfiles` automatically rewrites `/Users/<old-user>` paths in your dotfiles to the new Mac's `$HOME`. If your custom LaunchAgent plists contain hardcoded `/Users/<name>` paths, either keep the same macOS account short name or update `WorkingDirectory` and `ProgramArguments` in those plists before loading them.

## 3. What each setup step does

`bin/setup.sh --list` shows the steps; `bin/setup.sh --dry-run` shows what every step would install or change without doing it; `bin/setup.sh <step>` runs a single step again. Every step skips what is already done.

| Step | What it does | Needs | If it stops |
|---|---|---|---|
| `brew` | `brew bundle --file=setup/Brewfile`: formulae, casks (apps and fonts), App Store apps, uv tools | App Store sign-in for App Store apps | Fix the named item and run `bin/setup.sh brew` again. If Xcode was installed, run `sudo xcodebuild -license accept` |
| `node` | nvm installs the Node version in `setup/versions.env`, links `node`, `npm`, and `npx` into `~/.local/bin` for background jobs, and installs `setup/npm.txt` | `brew` | |
| `bun` | Installs bun, then global packages in `setup/bun.txt` | | |
| `python` | `uv python install` for the version in `setup/versions.env` | `brew` | |
| `scripts` | Runs the official install script of each tool in `setup/scripts.tsv` | | |
| `releases` | Downloads and installs the latest GitHub release (`.dmg` or `.zip`) for each app in `setup/releases.tsv` | `gh` login only for private repos (public ones work before you sign in) | Check the repo or asset pattern in *Manage App Sources…* and run `bin/setup.sh releases` again |
| `dotfiles` | Copies `dotfiles/` to `~` (`ssh/config` to `~/.ssh/config`) and applies `dotfiles/macos-defaults.tsv`. Existing files that differ are backed up to `~/.local/share/lazymac/restore-backup-<time>/` first | | |
| `secrets` | `bin/secrets-restore.sh`: sign-in files, Keychain API keys, private job files, and scripts | `brew` (`age`), the passphrase | A wrong passphrase changes nothing; run `bin/setup.sh secrets` again |
| `repos` | Clones each repo in `setup/repos.tsv` (catalog rows with `how` `repo`) into its folder and runs its command | `gh` login only for private repos | Run `gh auth login`, then `bin/setup.sh repos` again |
| `jobs` | For each label in `setup/jobs.txt`: if its plist and program exist, loads it with `launchctl bootstrap`; otherwise prints what it is waiting for | `secrets`, and the target program | Install what the job waits for, then run `bin/setup.sh jobs` again |
| `downloads` | Opens the download page of every app and font in `setup/downloads.tsv` that is not installed yet | | |
| `check` | Scans the Mac again and lists `keep` items still missing | `bun` | |

Only items marked ✅ (`keep`) in `catalog.tsv` are written to `setup/`. Items marked ⛔ (`drop`) and ❓ (`ask`) are never installed unless selected in a profile or in the app.

## 4. By hand, after setup

- **Apps from download pages or manual installers**: install the apps that `downloads` opened in your browser and any apps listed in `setup/byhand.tsv` (for example Visual Studio Code or LazyMac itself).
- **Apps built from source**: clone and build any `how=build` repositories you use, then re-run `bin/setup.sh jobs` if background jobs depend on them.
- **Permissions** in System Settings > Privacy & Security, as each app asks: grant Accessibility, Screen Recording, Input Monitoring, and Full Disk Access (for LazyMac if it runs scheduled folder backups) to the apps that need them.
- **Sign in again**: Apple ID, Tailscale, chat and email apps, browsers, password managers, and desktop tools that bind credentials to the device hardware. For expired tokens or keys that need reissuing, see [secrets.md](secrets.md).
- **Tools with their own restore guides**: complete the restore steps for any services marked `how=restore` in your catalog, and clone the project repositories you actively work on (`gh repo list`).

## 5. Check the result

```sh
bin/setup.sh check
```

`keep items not found on this Mac` lists anything still missing. Each item listed there is either one of the manual installs above or a step you can re-run.
