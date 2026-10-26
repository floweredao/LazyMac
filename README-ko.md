<div align="center">

# LazyMac

**맥을 백업하고, 새 맥을 깨끗하게 다시 세팅해요.<br>맥에 있는 모든 것을 한 목록에 담아 가져갈 것과 두고 갈 것을 미리 정리해요.**

[English](README.md) · [내려받기](https://github.com/floweredao/LazyMac/releases/latest) · [날짜별 히스토리](https://lazymac-history.pages.dev/)

</div>

LazyMac은 지금 맥에 설치된 것들을 기록해 두었다가, 다음 맥을 세팅할 때 묵은 찌꺼기 없이 쓰는 것만 새로 깔아 주는 맥용 앱이자 도구 모음이에요. 디스크 전체를 통째로 옮기는 대신 앱, 명령줄 도구, 백그라운드 작업, 설정, 글꼴, 비밀값을 한 목록으로 모으고 실제로 쓰는 항목만 골라 설치해요. GitHub나 iCloud에 없는 폴더를 백업하고 싶을 때는 Google 드라이브나 로컬 폴더로 안전하게 복사해 두고, 어느 쪽에서도 파일을 지우지 않아요.

## 주요 기능

- **한 목록으로 끝내는 깨끗한 세팅.** 맥을 읽기 전용으로 훑어서 앱, 명령줄 도구, 백그라운드 작업, 설정, 글꼴, 비밀값을 ✅ 가져감, ⛔ 두고 감, ❓ 확인 필요로 미리 나눠요.
- **앱에서 네 단계 복원, 터미널에서 명령 한 줄.** *복원 → 앱과 설정*에서 가져갈 항목을 직접 고르거나, 터미널에서 `bin/setup.sh`를 실행해 ✅ 항목을 순서대로 설치해요.
- **프로필과 여러 맥 지원.** 맥 기본 프로필(`pro`, `air`)과 쓰임 프로필(`dev`, `light`, `outside`)을 조합해 맥마다 다르게 설치하고, 지금 맥과 비교해요. 맥별 스캔 결과는 `inventory/<맥 이름>/`에 따로 저장되어 모든 맥에서 지워진 항목만 목록에서 빠져요.
- **앱 출처 관리.** Homebrew나 App Store에 없는 앱을 어디서 받는지(GitHub 릴리즈, 다운로드 페이지, 직접 빌드) 앱 안에서 바로 확인하고 최신 릴리즈로 맞춰요.
- **암호화된 비밀값 묶음.** 로그인 설정 파일, SSH 키, 키체인 항목, 백그라운드 작업 파일을 암호 하나로 잠근 [age](https://age-encryption.org) 파일(`secrets/secrets.tar.age`)에 담아 옮기고, 푸시하기 전에 `gitleaks`로 비밀값 노출을 막아요.
- **필요할 때 켜는 폴더 백업과 복원.** 고른 폴더를 Google 드라이브(또는 rclone이 지원하는 클라우드)나 로컬 폴더에 복사해요. 빌드 캐시와 비밀값 파일은 자동으로 건너뛰고, 복원할 때 맥에 이미 있는 파일은 덮어쓰지 않아요.

## 설치하기

[Releases](https://github.com/floweredao/LazyMac/releases/latest)에서 `LazyMac-<버전>.zip`을 내려받아 압축을 풀고, `LazyMac.app`을 `/Applications`(응용 프로그램) 폴더로 옮겨요.

애플 공증 없이 개인 서명(ad hoc)으로 빌드되어 있어서 처음 열 때는 macOS가 실행을 막아요. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래쪽의 **그래도 열기**를 눌러 주세요. 정해진 일정에 따라 뒤에서 백업을 돌리려면 LazyMac에 **전체 디스크 접근** 권한을 허용해 주세요(*백업 → 일정* 화면에 설정 열기 버튼이 있어요).

## 첫 실행

카탈로그 저장소로 앱·설정 목록을 관리하거나, 폴더 백업만 쓰거나, 둘 다 함께 쓸 수 있어요.

1. **LazyMac.app**을 열어요.
2. 앱과 설정 목록을 쓰려면 **복원 → 앱과 설정**으로 가요. **준비** 단계에서 버튼을 차례로 눌러 Homebrew와 GitHub CLI(`gh`)를 설치하고, GitHub에 로그인한 뒤 내 카탈로그 저장소(예: `alex/lazymac`을 `~/Documents/lazymac`에)를 받거나 기존 폴더를 골라요.
3. **백업 → 한눈에**에서 **이 맥 훑기**를 누르거나 터미널에서 `bin/scan.sh`를 실행해요. 이 맥에 깔린 앱, Homebrew 패키지, App Store 앱, 전역 CLI 도구, 글꼴, LaunchAgent 목록이 `inventory/<맥 이름>/`에 기록돼요.
4. `bun bin/catalog.ts check`로 새로 발견된 항목을 확인하고, `catalog.tsv`에 결정(`keep`, `drop`, `ask`)을 적은 뒤 `bun bin/catalog.ts render`를 실행하면 `setup/`과 README 표가 갱신돼요.

<!-- counts:begin -->
| 묶음 | ✅ 가져감 | ⛔ 두고 감 | ❓ 확인 필요 |
|---|---:|---:|---:|
| 앱 | 12 | 3 | 0 |
| 명령줄 도구 | 18 | 2 | 0 |
| 뒤에서 도는 것 | 4 | 1 | 0 |
| 설정·글꼴 | 6 | 0 | 0 |
| 비밀값·로그인 | 3 | 0 | 0 |
| 다른 저장소에 있는 것 | 2 | 0 | 0 |
| 이 맥의 찌꺼기 | 0 | 2 | 0 |
| **합계** | **45** | **8** | **0** |
<!-- counts:end -->

<!-- ask:begin -->
지금은 없어요.
<!-- ask:end -->

<details>
<summary><b>예시 카탈로그 미리 보기</b></summary>

<!-- catalog:begin -->
| 구분 | 이름 | 하는 일 | 가져갈까 | 새 맥에서 |
|---|---|---|---|---|
| 앱 | Ghostty | 터미널 에뮬레이터 | ✅ 가져감: 오늘 사용 | 자동 (Homebrew) |
| 앱 | Visual Studio Code | 코드 편집기 | ✅ 가져감: 오늘 사용 | 직접 |
| 앱 | Raycast | 런처 및 빠른 실행 도구 | ✅ 가져감: 지금 켜져 있음 | 자동 (Homebrew) |
| 앱 | Ice | 메뉴 막대 정리 도구 | ⛔ 두고 감: 다른 앱으로 대체 | - |
| 명령줄 도구 | git | 버전 관리 도구 | ✅ 가져감: 오늘 사용 | 자동 (Homebrew) |
| 명령줄 도구 | gh | GitHub 명령줄 도구 | ✅ 가져감: 오늘 사용 | 자동 (Homebrew) |
| 명령줄 도구 | bun | 자바스크립트 런타임 및 패키지 관리자 | ✅ 가져감: 오늘 사용 | 자동 (bun 설치기) |
| 명령줄 도구 | age | 비밀값 묶음 암호화 도구 | ✅ 가져감: 오늘 사용 | 자동 (Homebrew) |
| 명령줄 도구 | rclone | 폴더 백업용 클라우드 동기화 도구 | ✅ 가져감: 오늘 사용 | 자동 (Homebrew) |
<!-- catalog:end -->

</details>

## 매일 자동 백업

**백업 → 일정**(또는 **LazyMac → 설정**, `⌘,`)을 열고 **자동으로 백업하기**를 켠 뒤, 실행 주기(매시간, 몇 시간마다, 매일, 매주)와 시각을 고르고 **적용**을 눌러요. `~/Library/LaunchAgents/local.lazymac-daily.plist`가 등록되어 앱을 닫아 두어도 `local.lazymac-daily` 작업이 뒤에서 돌아요.

주 맥(`machines.tsv`에서 `role`이 `main`인 맥)에서 `bin/daily.sh`가 돌 때 하는 일은 다음과 같아요.

1. 이 맥을 훑어 `inventory/<호스트>/`에 저장하고 `gitleaks`로 비밀값이 없는지 확인한 뒤 커밋해요.
2. 모든 맥의 스캔에서 사라진 항목을 `catalog.tsv`에서 정리(`prune`)하고, `setup/`과 README를 다시 그려 커밋해요.
3. 오늘자 목록을 `snapshots/<날짜>.tsv`로 저장해 커밋하고 GitHub에 푸시해요(다른 맥이 먼저 올렸다면 `--rebase`로 받아서 다시 올려요).
4. `bun bin/snapshot.ts deploy`로 히스토리 페이지를 배포해요.
5. 파일 백업이 켜져 있으면(`storage.conf`의 `files on`), `backup.conf`에 적힌 폴더를 `bin/nogit-backup.sh rclone`으로 복사하고 `--check`로 원본과 대조해요.

보조 맥(`role`이 `extra`인 맥)에서는 이 맥의 `inventory/<호스트>/`만 갱신해 올리고, 파일 백업이 켜져 있고 백업할 폴더가 설정된 경우에만 폴더를 백업해요. 실행 로그는 `~/Library/Logs/lazymac-daily/<날짜>.log`에 30일 동안 보관돼요.

## 새 맥으로 복원하기

### 앱으로 복원하기

1. macOS 첫 설정을 마치고 App Store 앱에 로그인해요.
2. [Releases](https://github.com/floweredao/LazyMac/releases/latest)에서 **LazyMac.app**을 받아 설치해요.
3. 백업해 둔 폴더가 있다면 **복원 → 폴더**를 열고 **백업된 폴더 찾기**를 누른 뒤, 되살릴 폴더를 골라 **복원**을 눌러요. **백업보다 오래된 파일은 바꾸기**를 켜지 않는 한 이 맥에 이미 있는 파일은 건드리지 않아요.
4. **복원 → 앱과 설정**을 열고 **준비**, **고르기**(맥 프로필 `pro`·`air` 선택, `dev`·`light` 덧붙이기, 개별 항목 체크), **확인**, **설치** 네 단계를 차례로 진행해요. 중간에 맥 로그인 암호나 비밀값 묶음 암호를 물어보면 출력 창 아래 입력칸이 주황색으로 바뀌어요.

### 터미널로 복원하기

App Store에 로그인한 뒤 터미널을 열고 아래 명령을 실행해요.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh && gh auth login
gh repo clone alex/lazymac ~/Documents/lazymac
~/Documents/lazymac/bin/setup.sh
```

✅ 전체 항목 대신 특정 프로필만 골라 설치하려면 `--profile` 옵션을 붙여요.

```sh
~/Documents/lazymac/bin/setup.sh --profile air,light
```

옛 맥을 떠나기 전에 챙길 것과 `bin/setup.sh` 단계별 동작은 [복원 안내](docs/restore-ko.md)에서 볼 수 있어요.

## 저장소 설정 (Storage)

LazyMac은 카탈로그 관리와 폴더·프로젝트 파일 백업을 분리해요. 파일 백업은 **기본값이 꺼짐**(`files off`)이라서, 따로 켜지 않으면 매일 도는 작업이 클라우드 저장소를 요구하지 않아요.

### 스토리지 설정 (`storage.conf`)

백업 저장소 동작은 `~/Library/Application Support/lazymac/storage.conf`에서 설정해요(`LAZYMAC_STORAGE_CONF` 환경 변수로 경로 변경 가능).

```text
backend gdrive
remote gdrive:LazyMac
local ~/Backups/LazyMac
files off
```

- `backend gdrive|local`: Google 드라이브(또는 다른 rclone 원격지)를 쓸 때는 `gdrive`, 로컬 폴더나 외장 드라이브를 쓸 때는 `local`로 적어요.
- `remote <원격지:경로>`: rclone 원격지 이름과 클라우드 안 폴더 경로예요(예: `gdrive:LazyMac` 또는 `gdrive:LazyMac/Alexs-MacBook-Pro`).
- `local <경로>`: 로컬 백엔드를 쓸 때 복사본을 둘 폴더 경로예요.
- `files on|off`: `bin/daily.sh`에서 폴더·프로젝트 백업 단계를 실행할지 정해요. 기본값은 `off`예요.

### 백업 폴더 목록 (`backup.conf`)

복사할 폴더와 추가로 건너뛸 패턴은 `~/Library/Application Support/lazymac/backup.conf`에 저장돼요(앱의 **백업 → 폴더**에서 편집하거나 `LAZYMAC_BACKUP_CONF`로 지정).

```text
remote gdrive:LazyMac/Alexs-MacBook-Pro
folder ~/Documents/Notes
folder ~/Pictures/Studio
exclude *.mov
```

`bin/nogit-backup.sh`는 의존성과 빌드 결과물(`node_modules`, `.build`, `dist`, `DerivedData`, `target`, `.venv` 등), 비밀값 파일(`.env`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`, `*credentials*.json`), `gitleaks`가 비밀값으로 탐지한 파일, 그리고 이미 `origin` 원격지가 연결된 하위 Git 저장소를 자동으로 건너뛰어요.

## 훅과 환경 변수

### 훅 (`LAZYMAC_HOOKS`)

`bin/daily.sh`는 `~/.config/lazymac/hooks`(또는 `LAZYMAC_HOOKS`로 지정한 폴더)에 실행 권한이 있는 스크립트가 있으면 함께 실행해요.

- `~/.config/lazymac/hooks/before-daily`: 매일 작업이 시작될 때 맥을 훑거나 Git 풀을 받기 전에 먼저 실행돼요(예: 밤사이 도는 패키지 업데이트가 끝날 때까지 대기). 종료 코드가 0이 아니어도 로그에 남기고 일일 작업을 이어 가요.
- `~/.config/lazymac/hooks/on-failure`: `bin/daily.sh`가 실패했을 때 첫 번째 인자(`$1`)로 한 줄짜리 실패 메시지를 받아 실행돼요. 슬랙, 디스코드, 이메일, 웹훅 등으로 알림을 보낼 때 써요. 이 훅이 없으면 macOS 알림 센터로 알림을 띄워요.

### Cloudflare Pages 키체인 (`LAZYMAC_CF_KEYCHAIN`)

`bun bin/snapshot.ts deploy`는 날짜별 히스토리 정적 사이트를 Cloudflare Pages에 올려요. 이때 macOS 로그인 키체인에서 `LAZYMAC_CF_KEYCHAIN` 서비스 이름(기본값: `lazymac-cloudflare`)의 `api-token`과 `account-id` 항목을 읽어요.

```sh
security add-generic-password -U -a api-token -s lazymac-cloudflare -w "<YOUR_CF_API_TOKEN>"
security add-generic-password -U -a account-id -s lazymac-cloudflare -w "<YOUR_CF_ACCOUNT_ID>"
```

키체인에 두 항목이 없으면 `wrangler login`으로 로그인된 세션을 대신 사용해요. 공개 히스토리 페이지에 절대 올라가면 안 되는 개인 단어가 있다면 `~/.config/lazymac/private-words`(`LAZYMAC_PRIVATE_WORDS`)에 한 줄에 하나씩 적어 두면 빌드할 때 자동으로 검사해 차단해요.

## 스크린샷

> 안내: 아래 스크린샷은 추후 업데이트에서 새 캡처 화면으로 교체될 예정이에요.

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/app-ko-dark.png"><img src="docs/app-ko.png" width="760" alt="LazyMac 백업 한눈에 화면"></picture>

## 더 보기

| 문서 | 내용 |
|---|---|
| [자세한 안내](docs/guide-ko.md) | 앱 화면별 설명, 앱 출처 관리, 프로필과 여러 맥 쓰기, 터미널 설치, 앱 빌드와 릴리즈 |
| [복원 안내](docs/restore-ko.md) | 옛 맥을 떠나기 전 할 일, `bin/setup.sh` 단계별 설명, 설치 뒤 직접 할 일 |
| [목록 관리](docs/maintain.md) | `catalog.tsv`, `groups.tsv`, 맥 스캔, 자동 정리, 프로필, 스냅샷 구조 |
| [비밀값 안내](docs/secrets.md) | `secrets/manifest.txt`와 `secrets/secrets.tar.age`로 비밀값·키체인 항목을 묶고 되살리는 방법 |
