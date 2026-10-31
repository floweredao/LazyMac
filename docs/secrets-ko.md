# 비밀값 목록

[English](secrets.md) · 한국어 · [README로](../README-ko.md)

**이 저장소에는 비밀값을 평문으로 두지 않아요.** 여기서는 LazyMac이 로그인 정보를 어떻게 나누는지, `secrets/manifest.txt`에 무엇을 적는지, `bin/secrets-pack.sh`와 `bin/secrets-restore.sh`가 암호화한 파일 하나에 담아 새 맥으로 어떻게 옮기는지 설명해요.

## 세 가지 종류

맥에 있는 로그인 정보와 상태 파일은 세 가지로 나눠요.

- **옮김**: 다시 발급할 수 없거나, 다시 발급하면 이미 암호화한 데이터를 못 여는 키나 묶음이에요. 묶음에 넣고, 비밀번호 관리자에도 사본을 둬요.
- **재발급**: API 키, CLI 토큰, OAuth 설정, SSH 키처럼 편하려고 암호화 묶음에 넣어 두지만, 암호를 잊으면 서비스 콘솔에서 새로 만들 수 있는 것이에요.
- **자동**: 세션 캐시, 기기에 묶인 Safe Storage 키, 다시 로그인하면 앱이 알아서 만드는 로컬 토큰이에요. 묶음에 넣지 않아요.

## 홈 폴더에 있는 파일 예

| 무엇 | 위치 | 복원하지 못했을 때 다시 얻는 법 | 종류 |
|---|---|---|---|
| SSH 키 | `~/.ssh/id_ed25519` (+ `.pub`) | `ssh-keygen -t ed25519`로 만들고 공개 키를 GitHub와 서버에 등록 | 재발급 |
| GitHub CLI | `~/.config/gh/hosts.yml` + 키체인 `gh:github.com` | `gh auth login` | 재발급 |
| Google Cloud CLI | `~/.config/gcloud/` (`logs/`, `cache/`, `virtenv/` 제외) | `gcloud auth login`, `gcloud auth application-default login` | 재발급 |
| rclone 설정 (예: `gdrive`) | `~/.config/rclone/rclone.conf` | LazyMac에서 연결(*백업 → 폴더*)하거나 `rclone config create gdrive drive scope=drive.file` | 재발급 |
| Docker 레지스트리 로그인 | `~/.docker/config.json` | `docker login` | 재발급 |
| 코딩 에이전트 인증 | `~/.omo/agent/auth.json`, `~/.codex/auth.json` | CLI로 다시 로그인 | 재발급 |

## 키체인 항목 예 (일반 암호)

| 무엇 | 키체인 서비스 | 다시 얻는 법 | 종류 |
|---|---|---|---|
| Cloudflare Pages 배포 토큰 | `lazymac-cloudflare` (또는 `$LAZYMAC_CF_KEYCHAIN`, 계정 `api-token`과 `account-id`) | Cloudflare 대시보드 → My Profile → API Tokens에서 만든 뒤 `security add-generic-password`로 저장 | 재발급 |
| omo용 Anthropic Console API 키 | `omo-anthropic-api` (계정마다 하나: `main`, `work`, ...) | Anthropic Console → API Keys에서 만든 뒤 `pbpaste \| bun bin/omo-anthropic.ts add <이름>` | 재발급 |
| Gemini API 키 | `gemini-api` | Google AI Studio → API keys | 재발급 |
| GitHub CLI 토큰 | `gh:github.com` | `gh auth login` | 재발급 |
| 앱 Safe Storage 키 | `Code Safe Storage`, `Slack Safe Storage`, `Notion Safe Storage` 등 | 앱이 알아서 만들어요. 앱에 다시 로그인하면 돼요 | 자동 |

## 선택 기능: omo용 Anthropic API 키

[omo](https://github.com/code-yeongyu/oh-my-openagent) 코딩 에이전트를 쓰는 사람만 해당돼요. omo가 없어도 LazyMac은 똑같이 동작하고, 키체인에 `omo-anthropic-api` 항목이 없는 맥에서는 아래 내용이 하나도 실행되지 않아요.

`bin/omo-anthropic.ts`는 키체인의 `omo-anthropic-api` 항목을 모두 모아 omo 공급자 `anthropic-api` 하나로 만들어요. 키마다 계정이 하나씩이고, `main`이 맨 앞에 고정돼요. omo는 고정된 키를 먼저 쓰고, 그 키가 실패할 때(인증 오류, 사용량 제한, 크레딧 소진)만 다음 키로 넘어가요. `bin/setup.sh secrets`는 묶음을 복원한 뒤 그런 항목이 있을 때만 `sync`를 실행해요. sync가 실패해도 경고만 하고 단계는 실패로 치지 않아요. 복원 뒤에 내 작업을 돌리려면 `after-secrets` 훅을 써요([고급 설정](advanced-ko.md#훅-lazymac_hooks)).

```sh
pbpaste | bun bin/omo-anthropic.ts add main   # 새 키 저장(표준 입력에서 읽음) 후 sync
bun bin/omo-anthropic.ts list                 # 계정 이름만 출력(값은 절대 출력하지 않음)
bun bin/omo-anthropic.ts sync                 # ~/.omo/agent/models.json과 auth.json의 공급자를 다시 씀
bun bin/omo-anthropic.ts check                # 키마다 GET /v1/models로 확인(비용 없음)
```

바꾼 뒤에는 omo를 다시 시작해요. 테스트: `tests/omo-anthropic.sh`(가짜 키로 임시 키체인과 임시 폴더를 써요).

## 다시 로그인할 계정 (옮길 로컬 파일이 없음)

로그인 정보를 맥의 하드웨어 UUID에 묶거나 키체인 항목을 직접 관리하는 데스크톱 앱은 새 맥에서 손으로 다시 로그인해요. 애플 ID / App Store(`brew bundle`이 App Store 앱을 깔기 전에 필요), Tailscale, Discord, Slack, Notion, 메일 앱, 브라우저, 데스크톱 AI 앱이 그래요.

<a id="encrypted-bundle"></a>

## 암호화 묶음

`secrets/secrets.tar.age`는 내가 정한 암호(`scrypt`)로 잠근 [age](https://age-encryption.org) 파일 하나예요. 묶음에 들어갈 것은 데이터 폴더(`~/LazyMac-data`)의 `secrets/manifest.txt`에 패턴으로 적어요.

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
keychain:omo-anthropic-api
keychain:gemini-api
keychain:gh:github.com

# Private LaunchAgent plists and helper scripts not tracked in a public repo
Library/LaunchAgents/local.example.*.plist
.local/bin/my-private-script
```

- 경로와 글롭 패턴은 `~` 기준으로 찾아요.
- `exclude:<경로>`는 묶는 폴더 안의 캐시나 로그를 빼요.
- `keychain:<서비스 패턴>`은 로그인 키체인에서 이름이 맞는 일반 암호 항목(`class: "genp"`)을 꺼내요.

일부러 빼는 것: **자동** 항목(앱이 다시 만들어요)과, 접근 권한이 앱 실행 파일에 묶인 앱 전용 키체인 항목이에요.

```sh
bin/secrets-pack.sh --dry-run   # 맞는 경로와 키체인 서비스 이름만 보여 줌, 비밀값은 읽지 않음
bin/secrets-pack.sh             # 묶고 암호화(키체인 항목마다 macOS가 한 번 물을 수 있어요: "허용")
bin/secrets-restore.sh --list   # 묶음에 든 것만 보여 줌, 아무것도 바꾸지 않음
bin/secrets-restore.sh          # 파일(그룹·다른 사용자 읽기 권한 없이)과 키체인 항목을 되살림
```

**묶고 되살릴 때 안전한 이유:**
- `bin/secrets-pack.sh`가 도는 몇 초 동안만 키체인 값을 16진수로 저장소 밖의 권한 `700` 임시 폴더에 두고, 끝나면 지워요. 암호는 `age`에 바로 입력해요.
- `bin/secrets-restore.sh`는 맥에 이미 있는 파일 내용이 묶음과 다르면, 먼저 `~/.local/share/lazymac/restore-backup-<시각>/`으로 옮긴 뒤 묶음의 파일을 `chmod go-rwx`로 써요.
- 되살린 키체인 항목은 `security add-generic-password -U`로 넣어요. 그래서 앱이 처음 읽을 때 macOS가 권한을 물을 수 있어요. **항상 허용**을 눌러요.

## 내 맥에서 비밀 파일 찾기

`secrets/manifest.txt`를 만들려고 내 맥을 살펴볼 때는 로그인 정보 파일 이름(`*.env`, `*credential*`, `*token*`, `auth.json`)으로 찾고, 키체인 서비스 이름은 `security dump-keychain`을 `-d` **없이** 실행해 봐요. 그러면 항목의 속성만 나오고 비밀값은 절대 나오지 않아요.
