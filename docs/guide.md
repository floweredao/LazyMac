# LazyMac in detail

[Back to README](../README.md)

## Why it helps

- **Back up and restore, both ways.** Folders that are not on GitHub or iCloud are copied to Google Drive (or any of the 70+ clouds rclone supports) or a local folder, and come back on a new Mac with one button. Nothing is ever deleted, on the Mac or in the cloud.
- **Works on any Mac.** No account, folder, or path is built in. Pick your folders, your cloud, and your LazyMac repo in the app; folder backup works without a repo at all.
- **A clean start.** Nothing is copied over wholesale. Only what you use gets installed fresh, and the leftovers stay behind.
- **No item-by-item review.** Every item is sorted by how it is used (last opened date, running now) into ✅ bring, ⛔ leave, or ❓ your call. Only the few ❓ items need your decision.
- **One command installs it.** On the new Mac, `bin/setup.sh` installs the ✅ items in order, restores your secrets, and registers your background jobs.
- **Different for each Mac and each use.** Profiles save "only these on this Mac" so you can pick one and install it. Start from a Mac profile (`pro`, `air`), add use profiles on top (`dev`, `light`, `outside`), and compare with this Mac to see what is missing and what is extra.
- **A second Mac is safe.** Each Mac keeps its own scan, and a row leaves the list only when it is gone from every Mac. A Mac you use now and then, like an Air, scans itself only when you open the app, or on a schedule you set.
- **See how this Mac is built.** Apps, command-line tools, background jobs, settings, secrets, and things kept in other repos, with similar items grouped together.

## The app

LazyMac goes both ways: **Back Up** keeps this Mac safe, and **Restore** brings it back on the next one. The sidebar on the left has both.

- **Back Up > Overview**: where the copies go, how many folders are tracked, the last backup and check, the schedule and how its last run went, and, with a LazyMac repo, this Mac's list of apps and settings (*Scan This Mac*).
- **Back Up > Folders**: install rclone and connect a cloud (Google Drive right in the app, any other cloud through `rclone config`), add or remove folders, add extra skip patterns, then click *Back Up Now* or *Check* (compares without copying).
- **Back Up > Schedule**: run every hour, every few hours, every day, or every week. It runs in the background even when the app is closed.
- **Restore > Folders**: click *Find Backed-Up Folders*, tick the ones you want, and put them back where they were or into another folder. Files already on the Mac are left alone unless you turn on replacing files that are older than the backup.
- **Restore > Apps and Settings**: installs what you pick from your LazyMac list in four steps (below).

The app supports English and Korean and follows the system language (System Settings > General > Language & Region, configurable per app). *View > Bigger Text* (`⌘+`) scales every text element up to twice its default size, and `⌘0` resets it.

**Getting it.** Download `LazyMac-<version>.zip` from [Releases](https://github.com/floweredao/LazyMac/releases/latest), unzip it, and move `LazyMac.app` to Applications. The first time you open it, macOS blocks it: open System Settings > Privacy & Security and click "Open Anyway" at the bottom (it is signed ad hoc, not notarized by Apple). For backups that run on a schedule, allow Full Disk Access for LazyMac (Back Up > Schedule has the button) so it can read your folders while you are away.

## Setting up a new Mac

### With the app (pick what to bring yourself)

1. Finish the macOS setup and sign in to the App Store.
2. Get the app as above and open *Restore > Folders* to bring your folders back.
3. Open *Restore > Apps and Settings*. It walks you through four stages:
   - **Prepare**: install Homebrew and the GitHub CLI, sign in to GitHub (with a copy button for the one-time code), and get your LazyMac repo (`owner/name`, filled in from your GitHub account), one button each. No repo yet? The folder backup works without one.
   - **Choose**: this Mac's profiles (`machines.tsv`) are ticked already. The *Profile* menu at the top left picks another Mac profile, adds use profiles on top, saves your choice as a profile, or compares it with this Mac. Untick what you do not want, or turn on "Show Left-Behind Items" to add ⛔ ones. The settings, secrets, repos, and check steps can be switched off too.
   - **Review**: shows each step and how many items it installs.
   - **Install**: shows each step's progress and output. When your Mac password or the bundle passphrase is asked, the input field at the bottom turns orange. Failed steps can be run again on their own.

The app writes the lists for the chosen items, in the same format as `setup/`, to `~/Library/Application Support/lazymac/selection/` and runs `bin/setup.sh` with `LAZYMAC_SETUP_DIR` pointing there, so it installs the same way as the terminal workflow.

**App sources.** To check or fix where an app comes from, click *Manage App Sources…* at the bottom left (or Window > App Sources). Every app that comes from a GitHub release, a download page, or a source build is listed with its repo or link, the latest release and asset it would install, the installed version, and an update badge. *Find on GitHub* suggests repos, including the one in the installed app's Sparkle update feed. *Install It Automatically* switches a download page to its GitHub release. The window fetches the latest state from GitHub when it opens, and *Save and Sync* writes `catalog.tsv`, re-renders `setup/` and the READMEs, then commits and pushes them so the next install uses the fix. To pin a specific asset in a release, write `owner/repo#pattern` (for example `#*-arm64.dmg`).

### Profiles and more than one Mac

- **Profiles** (`profiles/<name>.txt`): a Mac profile starts from `from keep` (every ✅ item) and removes or adds items with lines like `- group app/vm` and `+ cli/rustup`. A use profile has no `from` line, only such rules, and layers on top of a Mac profile. Common profiles include `pro`, `air` (without jobs only the main Mac runs), `dev`, `light` (without large coding tools), and `outside` (without background jobs and remote control).
- **Macs** (`machines.tsv`): each Mac's hostname, role (`main` is the main Mac), and default profiles. A Mac not listed is treated as an `extra` Mac starting with `pro`.
- **Compare**: `bun bin/catalog.ts compare air,light` (*Compare with This Mac* in the app) shows what is missing on this Mac (installing adds it), what is extra (shown only, never deleted), and what is the same.
- **A scan per Mac**: scans live in `inventory/<Mac name>/`, one folder per Mac. The daily prune drops a row only when it is gone from every Mac.
- **Another Mac (for example an Air)**: no background job by default. It pushes its list only when you press *Scan This Mac* in the app (or run `bin/scan.sh`). For a regular backup, open *Back Up > Schedule* (or LazyMac > Settings, `⌘,`), turn on *Back up automatically*, pick how often (every hour, every few hours, every day, or every week, with the time and day), and press *Apply*. Another Mac pushes only its own list and pulls first, so it never clashes with the main Mac. When file backup is turned on (`files on` in `storage.conf`) and that Mac has folders configured in *Back Up > Folders*, each scheduled run backs them up too.
- **The main Mac (for example a Pro)**: runs the daily 04:00 job (scan, prune, snapshot, history page, and optional folder backup to the cloud). You can change its schedule on the same screen.

### With the terminal (every ✅ item)

1. Finish the macOS setup and sign in to the App Store.
2. Open Terminal and run:

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
   gh repo clone alex/lazymac ~/Documents/lazymac
   ~/Documents/lazymac/bin/setup.sh
   ```

3. Finish the manual steps: grant the permissions apps ask for, sign in to your accounts, and run the restore guides of any tools that have their own.

What `setup.sh` does, in order:

- Installs Homebrew, App Store apps, and fonts
- Installs Node.js, bun, Python, and their global packages
- Installs tools that ship their own install script
- Installs apps from the latest GitHub release of their repo (`.dmg` or `.zip`, matching this Mac's architecture)
- Copies terminal, Git, tmux, npm, SSH, and Dock settings
- Restores secrets, sign-in files, and private job files (asks for the bundle passphrase once)
- Clones and sets up helper repositories configured in `setup.sh`
- Registers the ✅ background jobs (a job whose program is not installed yet waits until you run `bin/setup.sh jobs` again)
- Opens the download page of apps that have neither a Homebrew package nor a GitHub release
- Lists any by-hand apps and checks what is still missing

To install a profile instead, run `bin/setup.sh --profile air,light`. Without step names, it runs every step except the ones the profile skips (`skip`).

Running `bin/setup.sh` again is safe: finished parts are skipped and nothing is deleted. For what to do before leaving your old Mac and every step in detail, see the [restore guide](restore.md).

### Changing and releasing the app

The app lives in `app/` (SwiftUI, a Swift package). It reads `catalog.tsv` at runtime instead of embedding items inside the binary, so a catalog change needs no app release. Only when the app code itself changes:

```sh
tests/app-setup-files.sh            # the app's lists match setup/ and catalog.ts profile
tests/app-schedule.sh               # the auto backup schedule lands in the LaunchAgent (in a temporary folder)
# bump app/VERSION (new screens or behavior 1.x.0, fixes 1.0.x)
app/build.sh                        # app/build/LazyMac-<version>.zip
gh release create app-v$(cat app/VERSION) app/build/LazyMac-$(cat app/VERSION).zip -R floweredao/LazyMac --title "LazyMac App $(cat app/VERSION)"
```
