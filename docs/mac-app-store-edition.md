# 맥 앱스토어 판 — 앱 코드 쪽 계약 (v0.3.51)

같은 소스에서 맥 앱이 두 벌 나간다. 가르는 것은 컴파일 플래그 하나다.

| | Developer ID 판 (brew·DMG) | 맥 앱스토어 판 |
|---|---|---|
| 빌드 | `swift build -c release …` (기본) | `swift build -c release … -Xswiftc -DCHECK_MAS` |
| 번들 ID | `kingcheck` | `com.yehsung.aingcheck` (아이폰 앱과 유니버설 구매) |
| 판정표 | `MacEdition.developerID` | `MacEdition.appStore` |

판정표는 `Sources/CheckCore/MacEdition.swift` 한 곳이다. 기본 빌드·`swift test`·아이폰 Xcode 빌드는 언제나 Developer ID 판이고, 그 판의 동작은 바뀌지 않았다. 앱스토어 판의 런타임 갈래는 기본 빌드의 테스트가 `.appStore` 를 주입해 돌린다(`Tests/checkTests/V0351MacAppStoreEditionTests.swift`).

## 앱스토어 판에서 달라지는 것

**업데이트(심사 지침 2.4.5(vii))** — 새 버전 안내가 없다. `UpdateCheckStore.isUpdateAvailable` 이 늘 거짓이라 배너·캐릭터 말풍선·메뉴바 점이 함께 꺼진다. 서버 `app_latest_release` 배선과 GitHub 폴링, brew upgrade·DMG 교체(`UpdateRunner` 와 그 스크립트), `UpdateBanner` 는 **컴파일되지 않는다.** 서버 공지 카드는 남지만 링크는 `https://apps.apple.com` 만 보여 주고, 그 밖의 링크는 QR·버튼 문구째 뗀다.

**외부 프로세스(2.5.2)** — 로그인 셸 조회(`/bin/zsh -lc/-ic`), `codex app-server` 계정 프로브, Claude 리밋(`/usr/bin/security` 로 남의 키체인 항목), 안티그래비티 리밋(`agy`)이 컴파일되지 않는다. 계정 프로브는 무해 인스턴스이고 업로드 경로가 부르지도 않는다(계정 상태는 서버에 '모름'으로 간다). Codex 리밋(`~/.codex/auth.json` 읽기)은 **남긴다**(2026-10-14 결정 — `MacEdition.readsCodexLimits` 한 줄로 끌 수 있다).

**진짜 홈** — 샌드박스에서는 `homeDirectoryForCurrentUser` 가 컨테이너다. 토큰 스캐너·Codex 진단·Codex 리밋은 `AIToolHome.current()`(앱스토어 판은 `getpwuid_r`)로 사용자의 진짜 홈을 읽는다. 읽는 자리는 다음 넷이고, 패키징의 읽기 전용 임시 예외(`com.apple.security.temporary-exception.files.home-relative-path.read-only`)와 짝이다.

- `/.claude/` — `projects`·`transcripts` 의 사용 기록
- `/.codex/` — `sessions`·`archived_sessions` 와 리밋용 `auth.json`(로그인 셸의 `CODEX_HOME` 은 못 묻는다 — 늘 `~/.codex`)
- `/.gemini/` — `antigravity-cli/conversations/*.db`(읽기 전용이라 `-shm` 을 못 만들면 `?immutable=1` 로 읽는다)
- `/Library/Application Support/orca/` — Orca 의 Codex 홈들

**동의(2.4.5(iii) · 5.1.1(ii) · 2.5.14)** — 첫 실행에 창 하나로 두 가지를 묻는다(한 번만): 로그인 시 자동 실행(기본 꺼짐)과 AI 도구 기록 읽기([허용하고 시작] / [나중에]). 설정 '일반'의 자동 실행 스위치와 '내 정보'의 **AI 사용 기록 읽기** 스위치로 바꾼다. 동의가 없으면 스캔·업로드·일별 업로드·스캔 하트비트·Codex 진단·리밋 읽기가 전부 멈춘다(읽지도 올리지도 않는다). 동의를 거두면 리밋 축도 잠재워 이미 올라간 리밋 행을 비운다.

| 키(UserDefaults — 앱스토어 판은 컨테이너) | 뜻 |
|---|---|
| `check.mas.firstRunCompleted` | 첫 실행 안내를 끝냈다 |
| `check.mas.aiToolDataConsent` | AI 도구 기록 읽기 동의(없으면 거절) |
| `check.mas.aiLimitsPausedByConsent` | 동의를 거둘 때 우리가 리밋 마스터를 껐다 |
| `check.launchAtLogin.userOptedIn` | 사용자가 자동 실행을 직접 켰다(이때만 매 실행 복구) |
| `check.mas.otherEditionWarned` | 다른 판 동시 실행 경고를 보여 줬다 |

**키체인** — 세션 토큰의 service 가 `kingcheck.mas` 다. 같은 맥의 brew 판 항목(`kingcheck`)을 건드리지 않는다(남의 ACL 에서 `SecItem` 이 멈추거나 brew 판이 로그아웃되는 사고를 막는다). 앱스토어 판으로 옮기는 사람은 한 번 다시 로그인한다.

**다른 판 동시 실행** — brew 판(`kingcheck`)이 함께 돌고 있으면(실행 중에 켜져도) 한 번 알린다. 막지는 않는다.

**진단 명령 루프**(`--check-settings-probe`)는 앱스토어 판에 없다.

## 두 판 모두 (심사 지침 5.1.1(i)(v) · 1.2)

- 설정 '일반' 머리 줄에 [개인정보 처리방침 · 이용약관] 링크, '내 정보' 머리 줄에 [계정 삭제](로그인했을 때만). 머리 줄과 같은 글자 크기라 설정 본문의 높이 계약(창 884pt · 여유 5pt)은 그대로다.
- 계정 삭제는 설정 본문과 자리를 바꾸는 화면이다: 지워지는 것 → 비밀번호 → [계정 삭제] → [취소]/[영구 삭제] 2단 확인. 순서는 폰과 같다 — 비밀번호로 재로그인 → 프로필 사진 → `delete_my_account` → 로그아웃과 같은 로컬 정리(로그인 이메일·별명도 잊는다). 재로그인이 다른 계정이면 지우지 않는다.
- 가입 폼의 가입 버튼 아래 "가입하면 이용약관과 개인정보 처리방침에 동의하게 돼요"(두 낱말이 링크).
- 주소는 `CheckAppLinks.privacyPolicy` · `CheckAppLinks.termsOfService`(폰과 같은 GitHub Pages).

## 개인정보 매니페스트

`Sources/check/Resources/PrivacyInfo.xcprivacy`. 패키징 스크립트가 앱 번들의 `Contents/Resources/PrivacyInfo.xcprivacy` 로 복사한다(SwiftPM 리소스 번들 안에도 한 벌이 실리지만 해가 없다). 필수 사유 API: UserDefaults `CA92.1` · 파일 타임스탬프 `3B52.1` · 부팅 시각 `35F9.1`. 새 범주의 API 를 쓰면 V0351 테스트가 빨개진다.

## 패키징 게이트(바이너리 금지어)

앱스토어 판 실행 파일에 다음이 **없어야** 한다(`strings -a` · `nm`). 2026-10-14 디버그·릴리스 빌드(arm64) 실측 0건.

- 문자열: `brew upgrade` · `brew update` · `releases/latest` · `aing-check-update` · `api.github.com` · `nohup` · `hdiutil` · `spctl` · `app-server` · `Claude Code-credentials` · `/usr/bin/security` · `find-generic-password` · `/bin/zsh` · `--output-format` · `command -v codex`
- 심볼: `UpdateRunner` · `dmgUpdateScript` · `upgradeScript` · `AILimitClaudeReader` · `AILimitAntigravityReader` · `ProcessSession` · `shellLookupScript`
- `nm -u` 에 `NSTask` 참조가 0 이다(자식 프로세스를 띄우는 코드가 아예 없다).
- 주의: `kingcheck.mas` 같은 15바이트 이하 문자열은 릴리스 빌드에서 명령어 안에 박혀 `strings` 로 안 보인다 — "있어야 한다" 쪽 검사는 문자열로 하지 마라(디버그 빌드에서는 보인다).

## 운영 수칙(이 판이 생기며 새로 생긴 것)

- 앱스토어 판은 심사를 기다리는 동안 구버전이다. `app_build` 로 기능을 여는 서버 게이트(예: `chess_min_build`)는 앱스토어 판이 판매 중이 된 뒤에 올린다.
- 같은 커밋이면 두 판이 같은 `CFBundleVersion` 을 쓴다(서버는 빌드 번호만 본다).
