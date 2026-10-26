<div align="center">

# LazyMac

**Install this Mac's apps and tools on your next Mac, clean.**

[한국어](README-ko.md) · [Download](https://github.com/floweredao/LazyMac/releases/latest) · [Daily history](https://lazymac-history.pages.dev/)

</div>

LazyMac has one goal: set up your next Mac with the same apps and tools as this one, installed fresh.\
Backing up project folders and other files on this Mac is optional, and stays off until you turn it on.

It keeps a list of the apps, tools, settings, and sign-ins on this Mac and backs it up to Google Drive.\
On the new Mac, it installs fresh copies of what is on that list.\
Years of old files and leftovers stay behind.

- **Clean install on a new Mac**: pick what to bring, review it, and install.
- **One-click backup** to Google Drive by default, or to a folder or external disk.
- **Automatic backups** every hour, day, or week, even when the app is closed.
- **Passwords locked with your passphrase** in one encrypted file.
- **Folder backup is optional**: copying folders such as projects is off until you turn it on.
- **Nothing is deleted**: backups never remove files, and restores never overwrite yours.

<img src="docs/app.png" width="720" alt="LazyMac Back Up screen">

## Install

1. Download `LazyMac-<version>.zip` from [Releases](https://github.com/floweredao/LazyMac/releases/latest), unzip it, and move `LazyMac.app` to `/Applications`.
2. Open it. macOS blocks it the first time because the app is not notarized by Apple. Go to **System Settings > Privacy & Security** and click **Open Anyway**.

## Back up

### What a backup holds

| Part | What is saved | Where it comes from |
|---|---|---|
| Apps and tools | The list of installed apps, Homebrew packages, App Store apps, global command-line tools, fonts, and background jobs | A read-only scan of this Mac |
| Settings | Shell, Git, tmux, npm, and SSH settings files, plus Dock and Finder settings | `bin/settings.sh`. A file that looks like it holds a secret is skipped |
| Passwords and sign-ins | SSH keys, sign-in files, and Keychain items you choose, in one file locked with your passphrase | `bin/secrets-pack.sh` ([details](docs/secrets.md)) |
| Files and folders (optional) | Folders you pick that are not already on iCloud or GitHub. Off until you turn it on | `bin/nogit-backup.sh` |

Every backup is checked with `gitleaks` before it is saved, so a stray password does not end up in the list.

### First backup

1. Open **LazyMac**. A short welcome explains what it does, then asks where backups go.
2. **Connect Google Drive (the default).** Click **Install rclone**, a free tool that copies files to Google Drive. Then click **Connect Google Drive…** and sign in to Google in your browser. rclone can see only the files LazyMac makes.
   - **To use a folder instead**, click **Use a Folder Instead…**. A folder on an external disk needs no extra tools or sign-in.
   - You can change the place later in **Settings > Backup Place** (`⌘,`).
3. Click **Back Up This Mac**. It takes about a minute. Each part under **What a backup holds** gets a green check when it is saved.
4. **Lock your passwords (recommended).** Next to **Passwords and sign-ins**, click **Set Up…** and choose a passphrase. Store it in a password manager: without it the bundle cannot be opened.
5. **Copy folders (optional, off at first).** Turn on **Files and folders**, then pick folders in **Back Up > Folders**. Build output (`node_modules`, `DerivedData`, ...), secret-looking files (`.env`, `*.pem`, SSH keys), and folders that are already Git repositories are skipped.

### Automatic backups

1. Open **Back Up > Schedule**.
2. Turn on **Back up automatically**, choose how often (every hour, every few hours, every day, or every week), and click **Apply**.
3. Click the shortcut to give LazyMac **Full Disk Access**, so background backups can read every folder.

LazyMac installs a LaunchAgent (`local.lazymac-daily`) that runs the same backup when the app is closed. The **Back Up** screen shows the last result. If a backup fails, it says why in plain words (for example "Your backup disk is not connected") with a button to fix it. Logs are kept for 30 days in `~/Library/Logs/lazymac-daily/`.

## Restore to a new Mac

### Before you leave the old Mac

1. Click **Back Up This Mac** once more, so the backup is current.
2. If you added or changed passwords, click **Update…** next to **Passwords and sign-ins**.
3. Copy anything LazyMac does not back up, such as large app libraries, to an external disk.

### On the new Mac

1. Finish the macOS setup, sign in with your Apple ID, and **open the App Store and sign in**. App Store apps install only after this.
2. Install LazyMac (see [Install](#install)).
3. Choose **the same place** as on the old Mac. LazyMac finds the existing backup and uses its list.
   - **Google Drive**: connect the same Google account. Under **Folder in Drive**, enter the folder the old Mac used. **Settings > Backup Place** on the old Mac shows it.
   - **A folder**: connect the backup disk and choose the same folder.
4. Open **Restore > Apps and Settings** and go through the four steps:
   1. **Prepare**: install Homebrew with one click. The backup list loads.
   2. **Choose**: pick a Mac profile (such as `pro` or `air`), turn add-ons on or off, or tick single items.
   3. **Review**: check what will be installed.
   4. **Install**: watch the progress. When `sudo` or the passphrase is needed, the input bar under the log turns orange. Type it there.
5. If you backed up folders, open **Restore > Folders**, click **Find Backed-Up Folders**, select folders, and click **Restore**. Files already on this Mac are never touched unless you turn on **Replace files here that are older than the backup**.

<img src="docs/apps.png" width="720" alt="Restore apps and settings, Prepare step">

<img src="docs/restoreFolders.png" width="720" alt="Restore folders">

### What you still do by hand

- **Apps without an installer LazyMac can run**: LazyMac opens their download pages. Install them, along with apps listed as "by hand" (for example Visual Studio Code).
- **Permissions**: grant Accessibility, Screen Recording, or Full Disk Access in **System Settings > Privacy & Security** when each app asks.
- **Sign in again** to apps that tie sign-ins to the Mac's hardware: browsers, chat and mail apps, password managers, and VPNs.
- When macOS asks whether an app may use a restored Keychain item, choose **Always Allow**.

To check what is still missing, run `bin/setup.sh check` in Terminal. It lists every item on your list that is not on this Mac.

### Restore from Terminal

If your list lives in a GitHub repository, you can restore without the app:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
gh repo clone alex/lazymac ~/Documents/lazymac
~/Documents/lazymac/bin/setup.sh                 # everything marked ✅
~/Documents/lazymac/bin/setup.sh --profile air,light   # or one profile
```

Each step skips what is already done, so you can run it again safely. The [restore guide](docs/restore.md) explains every step.

## More

| Guide | What it covers |
|---|---|
| [LazyMac in detail](docs/guide.md) | App screens, app sources, profiles, several Macs, building releases |
| [Restore guide](docs/restore.md) | Old-Mac checklist, every `bin/setup.sh` step, manual steps |
| [Passwords and sign-ins](docs/secrets.md) | What goes into the encrypted bundle and how it is restored |
| [Keeping the list](docs/maintain.md) | `catalog.tsv`, scans, pruning, profiles, snapshots |
| [Advanced settings](docs/advanced.md) | `storage.conf`, `backup.conf`, hooks, environment variables |
