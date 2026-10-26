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

- `backend local|gdrive`: 기본값 `local`은 폴더나 외장 디스크에 복사하고 rclone이 필요 없어요. `gdrive`는 rclone으로 Google 드라이브를 써요. `brew install rclone`으로 설치하고 `rclone config`로 연결을 만들어요(설정 → 백업 장소에 단계가 나와요). `backend` 줄 없이 `remote` 줄만 있으면 계속 `gdrive`로 봐요.
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
