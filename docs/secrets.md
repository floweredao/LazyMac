# Secrets index

English · [한국어](secrets-ko.md) · [Back to README](../README.md)

**No plain-text secret values are stored in this repository.** This guide explains how LazyMac categorizes credentials, what goes into `secrets/manifest.txt`, and how `bin/secrets-pack.sh` and `bin/secrets-restore.sh` move them to a new Mac inside one encrypted archive.

## Priority categories

When cataloging credentials and state files on your Mac, group them into three kinds:

- **Move**: keys or archives that cannot be reissued, or where reissuing would lose access to existing encrypted data. Include them in the bundle and keep a backup copy in your password manager.
- **Reissue**: API keys, CLI tokens, OAuth configs, and SSH keys that can be packed in the encrypted bundle for convenience, or recreated at the provider console if the passphrase is lost.
- **Auto**: session caches, device-bound Safe Storage keys, and local tokens that each app regenerates automatically when you sign in again. Leave these out of the bundle.

## Example files in the home folder

| What | Where | How to get it again if not restored | Kind |
|---|---|---|---|
| SSH keys | `~/.ssh/id_ed25519` (+ `.pub`) | `ssh-keygen -t ed25519`, then register the public key on GitHub and your servers | Reissue |
| GitHub CLI | `~/.config/gh/hosts.yml` + Keychain `gh:github.com` | `gh auth login` | Reissue |
| Google Cloud CLI | `~/.config/gcloud/` (excluding `logs/`, `cache/`, `virtenv/`) | `gcloud auth login` and `gcloud auth application-default login` | Reissue |
| rclone config (for example `gdrive`) | `~/.config/rclone/rclone.conf` | Connect in LazyMac (*Back Up > Folders*) or run `rclone config create gdrive drive scope=drive.file` | Reissue |
| Docker registry logins | `~/.docker/config.json` | `docker login` | Reissue |
| Coding agent sign-in | the agent's auth file, for example `~/.codex/auth.json` | Sign in again with the CLI | Reissue |

## Example Keychain items (generic passwords)

| What | Keychain service | How to get it again | Kind |
|---|---|---|---|
| Cloudflare Pages deploy token | `lazymac-cloudflare` (or `$LAZYMAC_CF_KEYCHAIN`, accounts `api-token` and `account-id`) | Cloudflare dashboard > My Profile > API Tokens, then store with `security add-generic-password` | Reissue |
| An API key you saved yourself | for example `example-api` | The provider's console | Reissue |
| GitHub CLI token | `gh:github.com` | `gh auth login` | Reissue |
| App Safe Storage keys | `Code Safe Storage`, `Slack Safe Storage`, `Notion Safe Storage`, etc. | Created automatically by each app; sign in to the app again | Auto |

## Accounts to sign in again (no local file to move)

Desktop apps that tie credentials to the Mac's hardware UUID or own their Keychain items must be signed in by hand on the new Mac: Apple ID / App Store (needed before `brew bundle` installs App Store apps), Tailscale, Discord, Slack, Notion, mail clients, browsers, and desktop AI apps.

## Encrypted bundle

`secrets/secrets.tar.age` is a single [age](https://age-encryption.org) archive locked with a passphrase you choose (`scrypt`). What goes into the bundle is listed by pattern in `secrets/manifest.txt` in your data folder (`~/LazyMac-data`):

```text
# Files and folders relative to ~
.ssh/id_*
.config/gh/hosts.yml
.config/rclone/rclone.conf
.config/gcloud
exclude:.config/gcloud/logs
exclude:.config/gcloud/cache
exclude:.config/gcloud/virtenv

# Keychain generic-password service names (glob patterns allowed)
keychain:lazymac-cloudflare
keychain:example-api
keychain:gh:github.com

# Private LaunchAgent plists and helper scripts not tracked in a public repo
Library/LaunchAgents/local.example.*.plist
.local/bin/my-private-script
```

- Plain paths and globs are matched relative to `~`.
- `exclude:<path>` skips caches or logs inside a packed folder.
- `keychain:<service-pattern>` exports matching generic-password items (`class: "genp"`) from the login Keychain.

Left out on purpose: **Auto** items (apps rebuild them) and app-owned Keychain items whose access control lists are tied to the app binary.

```sh
bin/secrets-pack.sh --dry-run   # list matched paths and Keychain service names only, reads no secret values
bin/secrets-pack.sh             # pack and encrypt (macOS may prompt once per Keychain item: click "Allow")
bin/secrets-restore.sh --list   # list what is inside the bundle, changes nothing
bin/secrets-restore.sh          # restore files (never group/world readable) and Keychain items
```

**How packing and restoring stay safe:**
- During `bin/secrets-pack.sh`, Keychain values are staged as hex in a mode `700` temporary folder outside the repository for a few seconds and deleted on exit; the passphrase is typed directly into `age`.
- During `bin/secrets-restore.sh`, any existing file on the Mac whose content differs from the bundle is moved to `~/.local/share/lazymac/restore-backup-<time>/` before the bundle's copy is written with `chmod go-rwx`.
- Restored Keychain items are added with `security add-generic-password -U`, so when an app reads one for the first time macOS may ask for permission: choose **Always Allow**.

## Finding secret files on your Mac

To audit your own Mac when building `secrets/manifest.txt`, search for credential file names (`*.env`, `*credential*`, `*token*`, `auth.json`) and list Keychain service names with `security dump-keychain` **without** `-d`, which prints item attributes only and never outputs secret data.
