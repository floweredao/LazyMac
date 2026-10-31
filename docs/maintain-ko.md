# 목록 관리

[English](maintain.md) · 한국어 · [README로](../README-ko.md)

목록을 어떻게 만들고 고치는지, 여러 맥을 어떻게 훑고 정리하는지 설명해요.

## 전체 구조

```
catalog.tsv        하나뿐인 목록: 앱, 도구, 백그라운드 작업, 설정, 비밀값 묶음, 다른 저장소, 찌꺼기 전부
groups.tsv         하위 분류 제목(영어, 한국어)과 보이는 순서. README, 기록 페이지, 앱이 모두 이 파일을
                   읽으니, 하위 분류를 새로 만들어도 앱을 새로 낼 필요가 없어요
   │  bun bin/catalog.ts render
   ├──> README.md, README-ko.md     <!-- ...:begin -->과 <!-- ...:end --> 표시 사이의 목록
   └──> setup/                      bin/setup.sh가 설치하는 것(가져가는 항목만)
          Brewfile  npm.txt  bun.txt  scripts.tsv  releases.tsv  downloads.tsv  byhand.tsv  jobs.txt  versions.env

bin/inventory.sh   이 맥을 읽기만 하는 스캔 -> inventory/<host>/ (지금 있는 것, 맥마다 폴더 하나)
bin/scan.sh        inventory.sh를 돌린 뒤 데이터 폴더를 백업 장소로 복사(앱의 "이 맥 훑기")
bin/catalog.ts check   모든 맥의 스캔과 catalog.tsv 비교: 새것(어느 맥인지 표시), 빠진 가져갈 항목, 낡은 파일
bin/catalog.ts prune   스캔으로 볼 수 있는데 모든 맥에서 사라진 항목의 행을 지움(그다음 render)
machines.tsv       host -> 역할(main이 전체 매일 작업을 돌려요)과 앱이 처음 고르는 프로필
profiles/          catalog.tsv 위의 이름 붙인 선택: 맥 프로필(from keep|empty|<base>)과 그 위에 얹는 추가 프로필
   │  bun bin/catalog.ts profile <base[,add-on...]> <dir>     프로필의 setup/ 목록(setup.sh --profile)
   └  bun bin/catalog.ts compare <base[,add-on...]> [--host h]   한 맥의 스캔과 비교: 없음 / 더 있음 / 같음
bin/snapshot.ts    snapshots/<date>.tsv(그날의 목록) -> 기록 페이지 https://<LAZYMAC_CF_PROJECT>.pages.dev/
bin/setup.sh       새 맥에서 setup/을 보고 실행
bin/nogit-backup.sh   backup.conf의 폴더를 rclone으로 클라우드에 복사하고, 목록을 보여 주고, 되살림
secrets/           manifest.txt(이름만) + secrets.tar.age(암호화)
dotfiles/          셸, git, tmux, npm, ssh 설정 사본과 macos-defaults.tsv(Dock 설정,
                   `setup.sh dotfiles`가 `defaults write`로 써요)
```

`setup/`과 README의 생성 블록은 손으로 고치지 않아요. `catalog.tsv`를 고치고 `bun bin/catalog.ts render`를 실행해요.

## catalog.tsv 열

| 열 | 뜻 |
|---|---|
| `section` | `app`, `cli`, `job`, `setting`, `secret`, `elsewhere`, `leftover` |
| `group` | 섹션 안의 하위 분류. 예: `assistants`, `terminal`, `git`, `rust`, `tools`. 값마다 `groups.tsv`에 행(섹션, 그룹, 영어·한국어 제목)이 있어야 해요. 없으면 `check`가 알려 주고 `render`는 거부해요. 하위 분류는 작게(2~7개쯤) 두고, 커지면 나눠요 |
| `id` | 스캔이 보는 이름: 앱 폴더 이름, 번들 ID 또는 `<bundle_id>@<team_id>`, launchd 라벨, `~/.local/bin` 이름, 글꼴 파일 앞부분. 쉼표로 여러 개 적을 수 있어요 |
| `name`, `name_ko` | README에 보이는 이름(`name_ko`가 비면 `name`과 같아요) |
| `decision` | `keep`(가져감), `drop`(두고 감), `ask`(아직 모름. `keep`으로 바꾸기 전까지 설치하지 않아요) |
| `how` | 어떻게 되돌아오는지, 아래 표 참고 |
| `ref` | `how`에 필요한 값: formula, cask, App Store id, 패키지, URL, `owner/repo[#pattern]`(`release`), `owner/repo[#folder[#command]]`(`repo`: 클론할 곳, 기본값 `~/Documents/<repo>`, 그 안에서 실행할 명령), 라벨 |
| `what_en`, `what_ko` | 하는 일, 쉬운 말로 |
| `why_en`, `why_ko` | 그렇게 정한 근거 한 줄 |

`how` 값:

| 값 | 되돌아오는 길 | 값 | 되돌아오는 길 |
|---|---|---|---|
| `brew`, `cask`, `tap`, `mas`, `uv` | `setup/Brewfile` | `bundle` | 암호화 묶음 |
| `npm` | `setup/npm.txt` | `copy` | `dotfiles/` |
| `bun` | `setup/bun.txt` | `register` | `setup/jobs.txt`, `launchd/`나 묶음의 plist |
| `nvm`, `uv-python` | `setup/versions.env` | `with-app`, `with-tool` | `ref`를 설치할 때 같이 |
| `bun-install`, `script` | 공식 설치 스크립트 | `restore` | 자체 복원 안내 |
| `release` | `setup/releases.tsv` (`gh release download`) | `repo` | `setup/repos.tsv` (`setup.sh repos`) |
| `download`, `build` | `setup/downloads.tsv` (페이지를 열어 줘요) | `byhand`, `signin` | 사람이 직접(`setup/byhand.tsv`) |
| `none` | 없음(`drop`) | | |

## 어떻게 정하나요

근거는 맥에서 읽기만 해서 얻어요. 앱을 마지막으로 쓴 날짜와 연 횟수(Spotlight `kMDItemLastUsedDate`, `kMDItemUseCount`), 지금 실행 중인지, 명령줄 도구 파일에 마지막으로 접근한 날짜, launchd 상태, 작업이 부르는 프로그램이 아직 있는지를 봐요.

- 최근 30일 안에 썼거나, 지금 돌고 있거나, 가져가는 다른 것이 필요로 하면 -> `keep`.
- 30~60일 안 썼거나 다른 것과 겹치면 -> `ask`.
- 한 번도 안 열었거나, 끝난 일회성 작업이거나, 다른 것으로 바뀌었거나, 비었거나, 필요할 때 몇 초면 다시 깔 수 있으면 -> `drop`.

빈틈: 이 근거는 이 맥만 봐요. 계정이 여러 기기에서 동기화되는 앱(메일, 메신저, 메모)은 이 맥에서는 안 쓰는 것처럼 보여도 다른 기기에서 매일 쓸 수 있어요. 이 맥의 Spotlight 날짜만 보고 `ask`나 `drop`으로 정하기 전에 확인해요. 메뉴 막대에만 있는 앱(`LSUIElement`)은 스크린 타임의 앞쪽 앱 기록에 나오지 않으니, Spotlight 날짜, 실행 중인지, 데이터 폴더로 판단해요.

## 결정 바꾸기

1. `catalog.tsv`에서 `decision`(과 `why_*`)을 고쳐요.
2. `bun bin/catalog.ts render`를 실행해요.
3. `bun bin/catalog.ts check`를 실행해요. 마지막이 `unclassified: 0`과 `out of date: 0`이어야 해요.
4. `catalog.tsv`, `setup/`, 두 README를 함께 커밋해요.

## 프로필

`profiles/<이름>.txt`, 파일 하나에 선택 하나예요. 줄 형식(`#`부터는 주석이고, 첫 주석은 앱이 보여 주는 설명이에요):

| 줄 | 뜻 |
|---|---|
| `from keep` / `from empty` / `from <base>` | 맥 프로필의 시작점: ✅ 행 전부, 아무것도 없음, 다른 맥 프로필. 이 줄이 없으면 추가 프로필이에요 |
| `+ group <section>/<group>` | 그 그룹의 ✅와 ❓ 행을 더해요(⛔ 행은 따로 이름을 적을 때만 들어와요) |
| `- group <section>/<group>` | 그룹 전체를 빼요 |
| `+ <section>/<id>` / `- <section>/<id>` | 행 하나, `section`과 적힌 그대로의 `id` 열로 |
| `skip <step>...` | 프로필이 빼는 설치 단계(예: `skip dotfiles secrets`) |

이름은 `a-z`, `0-9`, `-`만 써요. 그룹, 행, 단계가 틀리거나 서로 꼬리를 물면 exit 2로 멈춰요. `machines.tsv`는 맥마다 역할과 프로필(`pro,dev`: 맥 프로필 먼저, 그다음 추가 프로필)을 정해요. 앱은 열 때 그 프로필을 고르고, 지금 고른 것을 새 맥 프로필로 저장할 수 있어요(`profiles/<이름>.txt`로 쓰고 백업 장소로 복사해요). `tests/profiles.sh`가 규칙을, `tests/app-setup-files.sh`가 앱이 `catalog.ts profile`과 같은 목록을 쓰는지 확인해요.

## 매일 04:00 (주 맥)

LaunchAgent `local.lazymac-daily`가 `bin/daily.sh`를 실행해요. 시작하기 전에 `~/.config/lazymac/hooks/before-daily`가 실행 파일로 있으면 그것부터 돌려요(훅 폴더는 `LAZYMAC_HOOKS`로 바꿀 수 있어요).

`machines.tsv`에서 역할이 `main`인 맥에서는:

1. `refresh`: 다른 맥의 스캔을 백업 장소에서 받아 와요. 이 맥에서 고친 것은 덮어쓰지 않아요.
2. `scan`: `bin/scan.sh --no-push`가 이 맥을 `inventory/<host>/`로 훑고, `gitleaks`가 거기서 비밀값을 찾으면 실행을 멈춰요.
3. `list`: `bun bin/catalog.ts prune`과 `render`가 모든 맥에서 사라진 항목의 행을 지우고 `catalog.tsv`, `setup/`, README를 고쳐요. `bun bin/snapshot.ts take`가 그날의 목록을 `snapshots/<date>.tsv`로 저장해요.
4. `settings`: `bin/settings.sh save`가 설정 파일을 저장해요. `gitleaks`가 걸러 낸 파일은 빼요. `LAZYMAC_DAILY_SKIP`에 `settings`가 있으면 건너뛰어요.
5. `copy`: 데이터 폴더를 백업 장소로 복사해요.
6. `folders`: `~/Library/Application Support/lazymac/storage.conf`에 `files on`이 있으면(파일 백업은 처음에 `off`예요) `bin/nogit-backup.sh rclone`이 `backup.conf`의 폴더를 복사하고 `--check`로 확인해요.

매일 작업은 Git을 전혀 쓰지 않아요. 데이터 폴더를 백업 장소와 맞추는 것이 전부예요. 목록을 Git 저장소에 둔다면 커밋과 푸시는 직접 해요. 기록 페이지를 `bun bin/snapshot.ts deploy`로 올리는 것도 마찬가지예요. `bin/scan.sh`의 `--no-push`와 `--push-only`는 호환을 위해 남긴 옛 이름이고, 뜻은 "복사는 건너뛰기"와 "복사만"이에요.

스크립트는 잠금을 잡아 두 번이 겹쳐 돌지 않게 하고, 성공하면 조용해요. 실패하면 `~/.config/lazymac/hooks/on-failure "<메시지>"`를 실행해요(훅이 없으면 macOS 알림을 띄워요). 로그: `~/Library/Logs/lazymac-daily/<date>.log`(30일 보관). 지금 바로 돌리려면:

```sh
launchctl kickstart gui/$(id -u)/local.lazymac-daily
```

다른 맥에서는 같은 스크립트가 그 맥을 훑어 `inventory/<host>/`를 백업 장소로 복사하고, `storage.conf`에 `files on`이 있고 그 맥의 `backup.conf`에 폴더가 있으면 폴더도 백업해요. 다른 맥은 앱에서 *자동으로 백업하기*(백업 → 일정, 또는 LazyMac → 설정)를 켜기 전에는 정해진 작업이 없어요. 켜면 고른 일정으로 `~/Library/LaunchAgents/local.lazymac-daily.plist`를 쓰고 불러오고, 끄면 내리고 지워요. 주 맥의 04:00 일정도 거기서 바꿀 수 있어요. `setup.sh jobs`는 매일 작업을 주 맥에만 등록해요.

테스트 훅: `lazymac --schedule <spec>|off|show`(`tests/app-schedule.sh`가 임시 폴더에서 실행해요).
LazyMac 저장소(또는 bun)가 없는 맥은 앱 자체를 실행하는 작업 `lazymac --run-backup`을 받아요. `backup.conf`의 폴더를 복사하고 비교하고, 같은 폴더에 로그를 남기고, 실패하면 알림을 띄워요(`tests/app-backup.sh`). 이 작업은 LazyMac으로서 폴더를 읽으니 LazyMac에 '전체 디스크 접근'이 필요해요.

<a id="history-page"></a>

## 기록 페이지

기록 페이지는 `https://<project>.pages.dev`에 있는 정적 사이트예요. 프로젝트는 `LAZYMAC_CF_PROJECT`에 적은 것이에요(기본값 `lazymac-history`, [고급 설정](advanced-ko.md#cloudflare-pages-프로젝트-lazymac_cf_project) 참고). 날마다의 목록, 개수, 전날보다 늘어난 것·빠진 것·바뀐 것(✅ ⛔ ❓)을 보여 줘요. 누구나 볼 수 있는 사이트라서 `bin/snapshot.ts build`는 이름, 하위 분류, 결정, 한 줄 설명만 올리고, `secret` 섹션과 `data` 그룹(이 맥에만 있는 것)은 빼요. `~/.config/lazymac/private-words`(`LAZYMAC_PRIVATE_WORDS`)에 적은 단어, 메일 주소, `/Users/` 홈 경로, IPv4 주소가 보이면 올리기를 거부해요(exit 5). Cloudflare API 토큰과 계정 ID는 macOS 키체인의 서비스 `$LAZYMAC_CF_KEYCHAIN`(기본값 `lazymac-cloudflare`, 계정 `api-token`과 `account-id`)에서 읽고, 없으면 `wrangler login`을 써요. 그 Pages 프로젝트가 없으면 처음 올릴 때 만들어요.

```sh
bun bin/snapshot.ts take          # catalog.tsv로 snapshots/<오늘>.tsv
bun bin/snapshot.ts backfill      # git 기록에서 지난 날짜(파일이 아직 없는 날만)
bun bin/snapshot.ts build <dir>   # 사이트를 만들어 로컬에서 보기
bun bin/snapshot.ts deploy        # 만들고 올린 뒤, 페이지에 최신 날짜가 보일 때까지 기다림
```

## 새것 찾기

```sh
bin/inventory.sh               # inventory/<host>/를 다시 씀(1분쯤, 읽기만 해요)
bun bin/catalog.ts check       # "+" 줄이 새것("(host)"는 다른 맥에만 있을 때): 행을 더하고 render
bun bin/catalog.ts prune       # 모든 맥에서 지운 것의 행이 빠져요. 그다음 render
```

`prune`은 이 맥의 스캔에 빈 파일이 있거나 한 번에 10행보다 많이 지워질 때(`LAZYMAC_PRUNE_LIMIT`) 아무것도 바꾸지 않고 멈춰요. 진짜로 지운 게 아니라 스캔이 망가졌다는 뜻이기 때문이에요. 스캔이 볼 수 없는 행(설정, 비밀값, 저장소, 설치 스크립트 도구)은 절대 지우지 않아요. 다른 맥의 스캔은 행을 남기기만 해요. 그 맥에 어떤 종류의 스캔 파일이 없거나 비어 있으면(예: `mas`가 없음) 그 종류의 행은 그대로 둬요. `tests/hosts.sh`가 이 규칙을 확인해요.

스캔은 무엇도 설치하거나, 지우거나, 불러오거나, 내리지 않고, 비밀값을 읽지 않으며, 홈 폴더는 `~`로 적어요. 개인 경로나 토큰이 든 새 백그라운드 작업은 저장소에 평문 파일로 두지 말고 `secrets/manifest.txt`에 적어요.
