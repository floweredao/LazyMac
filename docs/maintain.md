# Keeping the list

[Back to README](../README.md)

How the catalog list is built, how to update it, and how to scan and prune items across your Macs.

## How the pieces fit

```
catalog.tsv        the one list: every app, tool, background job, setting, secret group, other repo, leftover
groups.tsv         the subcategory titles (English, Korean) in display order; the README, the history page, and
                   the app all read it, so a new subcategory needs no app release
   │  bun bin/catalog.ts render
   ├──> README.md, README-ko.md     the lists between <!-- ...:begin --> and <!-- ...:end --> markers
   └──> setup/                      what bin/setup.sh installs (keep items only)
          Brewfile  npm.txt  bun.txt  scripts.tsv  releases.tsv  downloads.tsv  byhand.tsv  jobs.txt  versions.env

bin/inventory.sh   read-only scan of this Mac -> inventory/<host>/ (what is here now; one folder per Mac)
bin/scan.sh        inventory.sh, then commit and push only inventory/<host>/ (the app's "Scan This Mac")
bin/catalog.ts check   every Mac's scan vs catalog.tsv: new things (tagged with the Mac), missing keep items, out-of-date files
bin/catalog.ts prune   removes rows for things the scans can see that are gone from every Mac (then render)
machines.tsv       host -> role (main runs the full daily job) and the profiles the app starts with
profiles/          named choices over catalog.tsv: Mac profiles (from keep|empty|<base>) and add-ons on top
   │  bun bin/catalog.ts profile <base[,add-on...]> <dir>     the setup/ lists for a profile (setup.sh --profile)
   └  bun bin/catalog.ts compare <base[,add-on...]> [--host h]   missing / extra / same against a Mac's scan
bin/snapshot.ts    snapshots/<date>.tsv (the list each day) -> history page https://lazymac-history.pages.dev/
bin/setup.sh       runs on the new Mac from setup/
bin/nogit-backup.sh   copies the folders in backup.conf to the cloud with rclone, lists and restores them
secrets/           manifest.txt (names only) + secrets.tar.age (encrypted)
dotfiles/          copies of shell, git, tmux, npm, and ssh settings, plus macos-defaults.tsv (Dock settings,
                   written with `defaults write` by `setup.sh dotfiles`)
```

Never edit `setup/` or the generated marker blocks of the READMEs by hand; edit `catalog.tsv` and run `bun bin/catalog.ts render`.

## catalog.tsv columns

| Column | Meaning |
|---|---|
| `section` | `app`, `cli`, `job`, `setting`, `secret`, `elsewhere`, `leftover` |
| `group` | The subcategory inside the section, e.g. `assistants`, `terminal`, `git`, `rust`, `tools`. Every value needs a row in `groups.tsv` (section, group, English and Korean title); `check` lists the ones that have none and `render` refuses. Keep a subcategory small (about 2 to 7 items); split it when it grows |
| `id` | What the scan sees: app folder name, bundle ID, or `<bundle_id>@<team_id>`, launchd label, `~/.local/bin` name, font file prefix. Several values can be comma-separated |
| `name`, `name_ko` | Shown in the README (`name_ko` empty = same as `name`) |
| `decision` | `keep` (bring), `drop` (leave behind), `ask` (undecided; not installed until changed to `keep`) |
| `how` | How it comes back, see below |
| `ref` | The value `how` needs: formula, cask, App Store id, package, URL, `owner/repo[#pattern]`, label |
| `what_en`, `what_ko` | What it does, in plain words |
| `why_en`, `why_ko` | One-line evidence for the decision |

`how` values:

| Value | Comes back by | Value | Comes back by |
|---|---|---|---|
| `brew`, `cask`, `tap`, `mas`, `uv` | `setup/Brewfile` | `bundle` | encrypted bundle |
| `npm` | `setup/npm.txt` | `copy` | `dotfiles/` |
| `bun` | `setup/bun.txt` | `register` | `setup/jobs.txt`, plist from `launchd/` or the bundle |
| `nvm`, `uv-python` | `setup/versions.env` | `with-app`, `with-tool` | installing `ref` |
| `bun-install`, `script` | official install script | `restore` | its own restore guide |
| `release` | `setup/releases.tsv` (`gh release download`) | `repo` | `setup.sh repos` |
| `download`, `build` | `setup/downloads.tsv` (page opened) | `byhand`, `signin` | the user (`setup/byhand.tsv`) |
| `none` | nothing (`drop`) | | |

## How decisions are made

Evidence comes from the Mac itself, read-only: app last-used date and open count (Spotlight `kMDItemLastUsedDate`, `kMDItemUseCount`), whether it is running now, file access dates of command-line tools, launchd state, and whether a job's program still exists.

- Used in the last 30 days, running now, or needed by something that is kept -> `keep`.
- Not used for 30 to 60 days, or overlapping with something else -> `ask`.
- Never opened, a one-time job that has finished, replaced, empty, or reinstallable in seconds when needed -> `drop`.

Blind spot: this evidence only sees this Mac. An app whose account syncs across devices (mail, messengers, notes) can look unused on one Mac while being used every day elsewhere. Check before marking such an app `ask` or `drop` on local Spotlight dates alone. Menu-bar-only apps (`LSUIElement`) never appear in Screen Time's foreground-app log, so judge them by Spotlight dates, whether they are running, and their data folders.

## Change a decision

1. Edit the `decision` (and `why_*`) in `catalog.tsv`.
2. Run `bun bin/catalog.ts render`.
3. Run `bun bin/catalog.ts check`; it must end with `unclassified: 0` and `out of date: 0`.
4. Commit `catalog.tsv`, `setup/`, and both READMEs together.

## Profiles

`profiles/<name>.txt`, one choice per file. Lines (a `#` starts a comment; the first comment is the description the app shows):

| Line | Meaning |
|---|---|
| `from keep` / `from empty` / `from <base>` | A Mac profile starts here: every ✅ row, nothing, or another Mac profile. A file without it is an add-on |
| `+ group <section>/<group>` | Add the group's ✅ and ❓ rows (⛔ rows only come in when named on their own) |
| `- group <section>/<group>` | Take the whole group out |
| `+ <section>/<id>` / `- <section>/<id>` | One row, by `section` and the `id` column as written |
| `skip <step>...` | Setup steps the profile leaves out (for example `skip dotfiles secrets`) |

Names use `a-z`, `0-9`, and `-`. A wrong group, row, step, or a loop stops with exit 2. `machines.tsv` gives each Mac a role and its profiles (`pro,dev`: the Mac profile first, then add-ons); the app picks those when it opens and can save the current choice as a new Mac profile (committed and pushed). `tests/profiles.sh` checks the rules; `tests/app-setup-files.sh` checks that the app writes the same lists as `catalog.ts profile`.

## Every day at 04:00 (main Mac)

The LaunchAgent `local.lazymac-daily` runs `bin/daily.sh`. Before starting, it runs `~/.config/lazymac/hooks/before-daily` if that executable exists (override the hooks folder with `LAZYMAC_HOOKS`).

On the Mac whose role is `main` in `machines.tsv`:

1. `bin/scan.sh --no-push` scans into `inventory/<host>/` and commits it after a `gitleaks` check.
2. `bun bin/catalog.ts prune` and `render` remove rows for items gone from every Mac and update `catalog.tsv`, `setup/`, and the READMEs, then commit.
3. `bun bin/snapshot.ts take` saves the day's list as `snapshots/<date>.tsv` and commits it, then `bin/scan.sh --push-only` pushes all commits (checking with `gitleaks` and pulling with `--rebase` if another Mac pushed first).
4. `bun bin/snapshot.ts deploy` publishes the history page.
5. When `~/Library/Application Support/lazymac/storage.conf` sets `files on` (file backup is `off` by default), `bin/nogit-backup.sh rclone` copies the folders in `backup.conf` and verifies them with `--check`.

The script holds a lock so two runs never overlap, stays quiet on success, and on failure runs `~/.config/lazymac/hooks/on-failure "<message>"` (or shows a macOS notification if no hook is installed). Log: `~/Library/Logs/lazymac-daily/<date>.log` (kept for 30 days). Run it now:

```sh
launchctl kickstart gui/$(id -u)/local.lazymac-daily
```

On any other Mac, the same script scans that Mac and pushes `inventory/<host>/`, then backs up its folders when `files on` is set in `storage.conf` and that Mac has folders in `backup.conf`. Another Mac has no scheduled job unless you turn on *Back up automatically* in the app (Back Up > Schedule, or LazyMac > Settings): that writes `~/Library/LaunchAgents/local.lazymac-daily.plist` with the chosen schedule and loads it; turning it off unloads and removes it. The main Mac's 04:00 schedule can be changed there too; `setup.sh jobs` registers the daily job only on the main Mac.

Test hook: `lazymac --schedule <spec>|off|show` (`tests/app-schedule.sh` runs it against a temporary folder).
A Mac with no LazyMac repo (or no bun) gets a job that runs the app itself, `lazymac --run-backup`: it copies and compares the folders in `backup.conf`, logs to the same folder, and shows a notification when it fails (`tests/app-backup.sh`). That job reads the folders as LazyMac, so LazyMac needs Full Disk Access.

## History page

[lazymac-history.pages.dev](https://lazymac-history.pages.dev/) shows every day's list, its counts, and what was added, removed, or changed (✅ ⛔ ❓) since the day before. Because the site is public, `bin/snapshot.ts build` publishes only names, subcategories, decisions, and the one-line description, leaves out the `secret` section and the `data` group (what lives only on this Mac), and refuses to publish (exit 5) when a word from `~/.config/lazymac/private-words` (`LAZYMAC_PRIVATE_WORDS`), an email address, a `/Users/` home path, or an IPv4 address shows up. It reads the Cloudflare API token and account ID from the macOS Keychain under service `$LAZYMAC_CF_KEYCHAIN` (default `lazymac-cloudflare`, accounts `api-token` and `account-id`, falling back to `wrangler login`) and creates the Pages project `lazymac-history` the first time.

```sh
bun bin/snapshot.ts take          # snapshots/<today>.tsv from catalog.tsv
bun bin/snapshot.ts backfill      # past days from git history (only days with no file yet)
bun bin/snapshot.ts build <dir>   # the site, to look at locally
bun bin/snapshot.ts deploy        # build and publish, waits until the page shows the newest day
```

## Find new things

```sh
bin/inventory.sh               # rewrites inventory/<host>/ (about a minute, reads only)
bun bin/catalog.ts check       # "+" lines are new ("(host)" when only another Mac has it): add a row, then render
bun bin/catalog.ts prune       # rows for things deleted from every Mac go; then render
```

`prune` stops without changing anything when this Mac's scan has an empty file or more than 10 rows would be removed at once (`LAZYMAC_PRUNE_LIMIT`), since that points to a broken scan rather than real deletions. Rows the scan cannot see (settings, secrets, repos, install-script tools) are never pruned. Another Mac's scan only ever keeps rows: when its scan file for a kind is missing or empty (for example, it has no `mas`), rows of that kind stay. `tests/hosts.sh` checks these rules.

The scan never installs, deletes, loads, or unloads anything, never reads secret values, and writes the home folder as `~`. New background jobs that hold private paths or tokens go into `secrets/manifest.txt`, never into the repo as plain files.
