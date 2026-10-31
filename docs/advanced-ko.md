# 고급 설정

[English](advanced.md) · 한국어 · [README로 돌아가기](../README-ko.md)

터미널에서 LazyMac을 쓰는 분을 위한 설정 파일, 훅, 환경 변수예요.

## 저장소 설정 (Storage)

LazyMac은 카탈로그 관리와 폴더·프로젝트 파일 백업을 분리해요. 파일 백업은 **기본값이 꺼짐**(`files off`)이라서, 따로 켜지 않으면 매일 도는 작업이 클라우드 저장소를 요구하지 않아요.

### 스토리지 설정 (`storage.conf`)

백업 저장소 동작은 `~/Library/Application Support/lazymac/storage.conf`에서 설정해요(`LAZYMAC_STORAGE_CONF` 환경 변수로 경로 변경 가능).

```text
backend local
local /Volumes/Backup/LazyMac
files off
```

- `backend gdrive|local`: 기본값 `gdrive`는 rclone으로 Google 드라이브를 써요. `brew install rclone`으로 설치하고 `rclone config`로 연결을 만들어요(시작 안내와 설정 → 백업 장소에 단계가 나와요). `local`은 폴더나 외장 디스크에 복사하고 rclone이 필요 없어요. `backend` 줄이 없으면 `gdrive`로 보고, `local` 줄이 있으면 `local`로 봐요.
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

## 자동 백업 작업 (`local.lazymac-daily`)

이 파일은 직접 쓰지 않아요. **자동으로 백업**을 켜면(백업 > 일정, 또는 LazyMac > 설정) 이 맥에 맞는 `~/Library/LaunchAgents/local.lazymac-daily.plist`를 만들고 `launchctl bootstrap`으로 등록해요. 끄면 등록을 해제하고 파일을 지워요. 일정만 바꿀 때는 기존 파일의 다른 키를 그대로 둬요. 터미널에서는 `/Applications/LazyMac.app/Contents/MacOS/lazymac --schedule daily:04:00`이 같은 일을 해요(`hourly[:MM]`, `every:<N>[:HH:MM]`, `daily:HH:MM`, `weekly:<0-6>:HH:MM`, `show`, `off`).

[`launchd/local.lazymac-daily.plist`](../launchd/local.lazymac-daily.plist)는 앱이 쓰는 내용의 예시예요. `/Users/you`는 내 홈 폴더, `/Users/you/lazymac`은 내 목록 저장소 자리예요.

| 키 | 앱이 넣는 값 |
|---|---|
| `ProgramArguments` | 목록 저장소와 bun이 있으면 `bun exec "/bin/zsh '<저장소>/bin/daily.sh' --if-due"`. launchd가 띄운 `/bin/zsh`는 `~/Documents`를 못 읽지만 bun은 읽을 수 있고, bun이 띄운 zsh가 그 권한을 물려받아요. 저장소나 bun이 없으면 앱 자신의 실행 파일에 `--run-backup --if-due`(LazyMac에 '파일 및 폴더 전체 접근' 권한 필요) |
| `WorkingDirectory` | 목록 저장소, 없으면 홈 폴더 |
| `EnvironmentVariables` | `HOME`, Homebrew·`~/.bun/bin`·`~/.local/bin`이 들어간 `PATH`, 그리고 앱을 그 값으로 띄웠다면 `LAZYMAC_DATA` / `LAZYMAC_STORAGE_CONF` |
| `StartCalendarInterval` | 고른 일정 |
| `RunAtLoad`, `StartInterval`(1800) | 놓친 백업 따라잡기: 로그인할 때와 30분마다도 깨어나고, `--if-due`가 붙어 있어서 실제로 밀린 백업이 있을 때만 백업해요 |
| `StandardOutPath`, `StandardErrorPath` | `~/Library/Logs/lazymac-daily/launchd.log` |

`LAZYMAC_LAUNCHAGENTS_DIR`로 다른 폴더에 쓸 수 있어요(테스트에서 `LAZYMAC_LAUNCHCTL`의 가짜 `launchctl`과 함께 써요).

## 훅과 환경 변수

### 훅 (`LAZYMAC_HOOKS`)

`bin/daily.sh`는 `~/.config/lazymac/hooks`(또는 `LAZYMAC_HOOKS`로 지정한 폴더)에 실행 권한이 있는 스크립트가 있으면 함께 실행해요.

- `~/.config/lazymac/hooks/before-daily`: 매일 작업이 시작될 때 맥을 훑거나 Git 풀을 받기 전에 먼저 실행돼요(예: 밤사이 도는 패키지 업데이트가 끝날 때까지 대기). 종료 코드가 0이 아니어도 로그에 남기고 일일 작업을 이어 가요.
- `~/.config/lazymac/hooks/on-failure`: `bin/daily.sh`가 실패했을 때 첫 번째 인자(`$1`)로 한 줄짜리 실패 메시지를 받아 실행돼요. 슬랙, 디스코드, 이메일, 웹훅 등으로 알림을 보낼 때 써요. 이 훅이 없으면 macOS 알림 센터로 알림을 띄워요.

### Cloudflare Pages 프로젝트 (`LAZYMAC_CF_PROJECT`)

`bun bin/snapshot.ts deploy`는 `LAZYMAC_CF_PROJECT`에 적은 Cloudflare Pages 프로젝트(기본값: `lazymac-history`)에 올리고, `https://<프로젝트>.pages.dev`에 가장 참여한 날짜가 나올 때까지 기다려요.

`*.pages.dev` 주소는 먼저 등록한 Cloudflare 계정의 것이라, 기본 이름은 그 이름을 이미 가진 계정에서만 원하는 대로 동작해요. 내 페이지를 올리려면 내 프로젝트 이름을 정해줘요.

```sh
LAZYMAC_CF_PROJECT=my-mac-history bun bin/snapshot.ts deploy
```

프로젝트가 아직 없으면 `deploy`가 토큰의 계정 아래에 만들어요. 이름이 다른 계정에 이미 있어서 만들기가 실패하면, 오류 내용에 그 사정과 이 변수 이름이 나와요.

### Cloudflare Pages 키체인 (`LAZYMAC_CF_KEYCHAIN`)

`bun bin/snapshot.ts deploy`는 날짜별 히스토리 정적 사이트를 Cloudflare Pages에 올려요. 이때 macOS 로그인 키체인에서 `LAZYMAC_CF_KEYCHAIN` 서비스 이름(기본값: `lazymac-cloudflare`)의 `api-token`과 `account-id` 항목을 읽어요.

```sh
security add-generic-password -U -a api-token -s lazymac-cloudflare -w "<YOUR_CF_API_TOKEN>"
security add-generic-password -U -a account-id -s lazymac-cloudflare -w "<YOUR_CF_ACCOUNT_ID>"
```

키체인에 두 항목이 없으면 `wrangler login`으로 로그인된 세션을 대신 사용해요. 공개 히스토리 페이지에 절대 올라가면 안 되는 개인 단어가 있다면 `~/.config/lazymac/private-words`(`LAZYMAC_PRIVATE_WORDS`)에 한 줄에 하나씩 적어 두면 빌드할 때 자동으로 검사해 차단해요.
