# 복원 안내

[English](restore.md) · 한국어 · [README로](../README-ko.md)

README에는 짧은 순서만 있어요. 여기에는 단계마다 하는 일, 필요한 것, 손으로 남는 일이 다 있어요.

## 차례

- [1. 옛 맥을 떠나기 전에](#1-옛-맥을-떠나기-전에)
- [2. 새 맥에서](#2-새-맥에서)
- [3. setup 단계별로 하는 일](#3-setup-단계별로-하는-일)
- [4. setup 뒤에 손으로 할 것](#4-setup-뒤에-손으로-할-것)
- [5. 결과 확인](#5-결과-확인)

## 1. 옛 맥을 떠나기 전에

1. **암호화 묶음을 새로 싸서 올려요.** 로그인 파일, 키체인 항목, 개인 백그라운드 작업 파일과 스크립트가 함께 들어가요([secrets.md](secrets.md#encrypted-bundle)). `age`가 암호를 두 번 물으니 비밀번호 관리자에 보관해 두세요.
   ```sh
   bin/secrets-pack.sh && git add secrets/secrets.tar.age && git commit -m "secrets: update encrypted bundle" && git push
   ```
2. **GitHub에 없는 폴더와 로컬 앱 데이터를 백업해요.**
   이 맥에만 있는 앱 데이터베이스는 외장 디스크나 AirDrop으로 옮겨요. `~/Library/Application Support/lazymac/backup.conf`에 등록한 폴더는 LazyMac의 *지금 백업*을 누르거나 `bin/nogit-backup.sh rclone`으로 클라우드에 복사해요. 새 맥에서는 LazyMac의 *복원 → 폴더*가 되살려요.
3. **목록을 새로 떠서 분류 안 된 게 없는지 봐요.**
   ```sh
   bin/scan.sh && bun bin/catalog.ts check
   ```
4. **모든 프로젝트 저장소를 올려 둬요.** (각 폴더에서 `git status -sb`에 안 올린 변경이나 앞선 커밋이 없게 해요.)

## 2. 새 맥에서

맥 첫 설정을 끝내고 애플 ID로 로그인한 다음, App Store를 한 번 열어 로그인해요. 그리고 터미널에서 아래를 실행해요.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
gh repo clone alex/lazymac ~/Documents/lazymac
~/Documents/lazymac/bin/setup.sh
```

Homebrew 설치기가 Xcode Command Line Tools도 같이 깔아요. `gh auth login`은 GitHub.com, HTTPS, 브라우저 로그인으로 진행해요.

`setup.sh dotfiles`는 설정 파일 안의 `/Users/<예전계정>` 경로를 새 맥의 `$HOME`으로 자동 변환해 복사해요. 다만 직접 만든 LaunchAgent plist 파일 안에 절대 경로가 적혀 있다면 맥 사용자 이름을 같게 맞추거나 plist의 경로를 고친 뒤 등록하세요.

## 3. setup 단계별로 하는 일

`bin/setup.sh --list`로 전체 단계를 보고, `bin/setup.sh --dry-run`으로 각 단계가 무엇을 설치하고 바꿀지 실제로 하지 않고 미리 봐요. `bin/setup.sh <단계>`로 원하는 단계만 다시 돌려요. 이미 설치된 항목은 건너뛰어요.

| 단계 | 하는 일 | 필요한 것 | 멈추면 |
|---|---|---|---|
| `brew` | `setup/Brewfile`로 명령줄 도구, 앱·글꼴(cask), App Store 앱, uv 도구 설치 | App Store 앱은 App Store 로그인 | 실패한 항목을 고치고 `bin/setup.sh brew` 다시 실행. Xcode를 깔았다면 끝나고 `sudo xcodebuild -license accept` 실행 |
| `node` | `setup/versions.env`의 Node 버전 설치, 백그라운드 작업용 `node`·`npm`·`npx`를 `~/.local/bin`에 연결, `setup/npm.txt` 설치 | `brew` | |
| `bun` | bun 설치 후 `setup/bun.txt` 전역 도구 설치 | | |
| `python` | `setup/versions.env`의 파이썬 버전을 uv로 설치 | `brew` | |
| `scripts` | `setup/scripts.tsv`의 공식 설치 스크립트 실행 | | |
| `releases` | `setup/releases.tsv`에 적힌 저장소의 최신 GitHub 릴리즈에서 `.dmg`·`.zip`을 받아 앱 설치 | 비공개 저장소만 `gh` 로그인 (공개 저장소는 로그인 전에도 돼요) | *앱 출처 관리…*에서 저장소나 파일 패턴을 확인하고 `bin/setup.sh releases` 다시 실행 |
| `dotfiles` | `dotfiles/`를 `~`로 복사(`ssh/config`는 `~/.ssh/config`)하고 `dotfiles/macos-defaults.tsv` 설정 적용. 내용이 다른 기존 파일은 먼저 `~/.local/share/lazymac/restore-backup-<시각>/`로 백업 | | |
| `secrets` | `bin/secrets-restore.sh`: 로그인 파일, 키체인 API 키, 개인 작업 파일·스크립트 복원 | `brew`(`age`), 묶음 암호 | 암호가 틀리면 아무것도 안 바뀌니 다시 실행 |
| `repos` | `setup/repos.tsv`(카탈로그에서 `how`가 `repo`인 행)의 저장소를 정한 폴더에 받고 그 명령을 실행 | 비공개 저장소만 `gh` 로그인 | `gh auth login` 뒤 `bin/setup.sh repos` 다시 실행 |
| `jobs` | `setup/jobs.txt`의 작업마다: 이미 켜져 있거나, plist와 실행 프로그램이 있으면 `launchctl bootstrap`, 아니면 무엇을 기다리는지 출력 | `secrets`, 해당 프로그램 | 기다리는 프로그램을 먼저 설치한 뒤 `bin/setup.sh jobs` 다시 실행 |
| `downloads` | `setup/downloads.tsv`에서 아직 설치되지 않은 앱·글꼴의 내려받기 페이지 열기 | | |
| `check` | 맥을 다시 훑어 아직 빠진 ✅ 항목 보여 주기 | `bun` | |

`setup/`에는 `catalog.tsv`에서 ✅(`keep`)인 것만 들어가요. ⛔(`drop`)와 ❓(`ask`)는 프로필이나 앱에서 직접 고르지 않는 한 설치하지 않아요.

## 4. setup 뒤에 손으로 할 것

- **내려받기 페이지가 열린 앱과 직접 설치 앱**: `downloads` 단계가 브라우저에 열어 준 페이지의 앱·글꼴과 `setup/byhand.tsv`에 안내된 앱(예: Visual Studio Code, LazyMac 앱 자체 등)을 설치해요.
- **소스에서 빌드하는 앱**: `how=build`로 표시한 저장소를 클론해 빌드하고, 그 프로그램이 필요한 백그라운드 작업이 있다면 `bin/setup.sh jobs`를 다시 실행해요.
- **권한 허용**(시스템 설정 → 개인정보 보호 및 보안, 앱이 물을 때): 터미널, 런처, 클립보드·창 관리 도구 등에 손쉬운 사용·화면 기록·입력 모니터링 권한을 허용해요. 예약 폴더 백업을 쓴다면 LazyMac에 전체 디스크 접근을 허용해요.
- **다시 로그인**: 애플 ID 앱, Tailscale, 메신저, 메일, 브라우저, 데스크톱 앱처럼 기기 고유 키에 로그인을 묶어 두는 앱에 다시 로그인해요. 만료된 토큰이나 재발급 방법은 [secrets.md](secrets.md)를 참고해요.
- **자체 복원 안내가 있는 도구와 작업 프로젝트**: `how=restore`로 분류된 도구는 해당 안내에 따라 복원하고, 작업할 GitHub 저장소를 클론해요(`gh repo list`).

## 5. 결과 확인

```sh
bin/setup.sh check
```

`keep items not found on this Mac`에 남은 항목이 아직 설치되지 않은 것이에요. 위에서 손으로 설치할 항목이거나 해당 단계를 다시 실행하면 돼요.
