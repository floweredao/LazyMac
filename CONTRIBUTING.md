# Contributing

## What you need

macOS 14 or newer, [bun](https://bun.sh), and `jq`. Full Xcode is needed to build the app, and
`rclone`, `gitleaks` and `age` to run the whole test suite. The [README](README.md#requirements)
lists what each one is for.

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path app
app/build.sh        # LazyMac.app and the release zip, in app/build/
```

`swift build` fails with `external macro implementation type 'SwiftUIMacros.StateMacro' could not be
found` when the Command Line Tools are selected instead of full Xcode. That is a missing toolchain,
not broken source.

## Test

```sh
for t in tests/*.sh; do zsh "$t" || break; done
zsh tests/due.sh     # or one script
```

Every script runs against a temporary home folder, a temporary Keychain and fake `defaults`,
`launchctl` and inventory programs, so it never reads or changes this Mac's own data, settings or
jobs. A script that needs a tool says which one is missing and exits non-zero.

GitHub Actions runs every `tests/*.sh` on macOS for each push to `main` and each pull request, so a
new test script is picked up with no change to the workflow. To be picked up it has to:

- be `tests/<name>.sh`, runnable as `zsh tests/<name>.sh` from the repository root;
- print one `ok <what it checked>` or `FAIL <what it checked>` line per check;
- exit `0` only when every check passed;
- install nothing and touch nothing outside its own temporary folder.

`tests/fixtures.zsh` has the shared fixtures (`seed_data`, `seed_inventory`, `fake_defaults`); use
them rather than writing new sample data.

## Sending a change

- One change per pull request, with the issue it closes in the body (`Fixes #12`).
- Commit subjects are a plain imperative sentence saying what changed, with the issue number at the
  end: `Say which tool is missing instead of ending the test silently (#4)`. The history has no
  `type:` prefixes.
- Say in the pull request what you ran and what it printed. "Tests pass" is not evidence; the output
  is.
- Run `gitleaks git --staged` before pushing. The repository keeps no secrets, only
  `secrets/*.age` ciphertext, and `.gitleaks.toml` allows nothing else.
- Never force-push a branch someone else may have pulled, and never rewrite published history.

## Documentation

English and Korean are kept side by side: `README.md` with `README-ko.md`, and `docs/<name>.md`
with `docs/<name>-ko.md`. A change to one belongs in the other in the same pull request.
