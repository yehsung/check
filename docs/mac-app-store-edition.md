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

**외부 프로세스(2.5.2)** — 로그인 셸 조회(`/bin/zsh -lc/-ic`), `codex app-server` 계정 프로브, 안티그래비티 리밋(`agy`)이 컴파일되지 않는다. **Claude 리밋(시스템 `/usr/bin/security` 로 키체인 항목 읽기)은 남긴다**(2026-10-14 사용자 결정 "AI 리밋은 예외 권한으로 기능 그대로" + 샌드박스 실측: 상속 샌드박스에서 프롬프트 없이 exit 0 — `MacEdition.readsClaudeLimits` 한 줄로 끈다). 계정 프로브는 무해 인스턴스이고 업로드 경로가 부르지도 않는다(계정 상태는 서버에 '모름'으로 간다). Codex 리밋(`~/.codex/auth.json` 읽기)은 **남긴다**(2026-10-14 결정 — `MacEdition.readsCodexLimits` 한 줄로 끌 수 있다).

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

**다른 판 동시 실행** — brew 판(`kingcheck`)이 함께 돌고 있으면(실행 중에 켜져도) 한 번 알린다. 막지는 않는다(0.3.52 이하 brew 판을 쓰는 사람용 — 0.3.53 부터는 brew 판 쪽이 물러난다, 아래 절).

**진단 명령 루프**(`--check-settings-probe`)는 앱스토어 판에 없다.

## 두 판을 함께 설치했을 때 (v0.3.53 — brew·DMG 판이 물러난다)

같은 맥에 **설치된 앱스토어 판**이 있으면 Developer ID 판(brew·DMG)이 물러난다. 두 판이 함께 돌면 같은 맥이 서버에 기기 두 대로 잡혀 토큰이 두 번 집계되고, 전역 단축키 하나에 두 앱이 함께 근무를 토글한다. 설치 자체는 못 막으니 **실행을 막는다.**

앱스토어 판의 **동작**은 바뀌지 않았다 — 이 기능 전체(`Sources/check/AppStoreEditionRetirement.swift` · `CheckApp.swift` 의 배선 · 스토어 게이트)가 `#if !CHECK_MAS` 안이고, 판정표에는 `MacEdition.retiresWhenAppStoreEditionInstalled`(Developer ID 판만 참) 한 줄이 있다. 다만 **소스는 한 군데 바뀌었다**: 두 판의 메뉴바 갈래가 갈리면서(`MenuBarExtra { }` ↔ `MenuBarExtra(isInserted:)`) 팝오버 본문·라벨을 두 판이 함께 쓰는 속성(`menuContent` · `menuLabel`)으로 뺐다(라벨을 만드는 자리는 한 곳이어야 한다는 기존 계약 때문). 그리는 것은 같지만 0.3.52 심사본과 바이너리 바이트는 다르다 — 앱스토어 판을 다시 낼 때는 이 차이를 검토 범위에 넣는다. 그 속성에 물러남 코드·판 갈래가 들어오지 않는지 V0353 이 되묻는다. 패키징 게이트가 앱스토어 판 바이너리에서 `uninstall --cask` 를 금지어로 잰다.

**판정**(`AppStoreEditionRetirement.isInstalledAppStoreEdition`) — 후보는 LaunchServices 가 아는 `com.yehsung.aingcheck` 사본들 ∪ 지금 돌고 있는 사본 ∪ `/Applications/AingCheck.app` ∪ (재실행 인자의 힌트). 다섯 다 참이어야 '설치된 앱스토어 판'이다:

1. 경로에 `/.Trash/`(`/.Trashes/`)가 없다 — LaunchServices 는 휴지통의 앱도 기억한다.
2. 실제 자리가 **시동 볼륨** 위다(`volumeIsRootFileSystem` — `/Applications` · 홈 · 임시 폴더는 참, `/Volumes/<디스크 이미지·외장·백업>` 은 거짓, 2026-10-15 실측). LaunchServices 는 마운트된 볼륨의 앱도 기억하고, 복제 백업에는 영수증까지 복사돼 있다.
3. `Contents/Info.plist` 의 `CFBundleIdentifier` 가 정확히 `com.yehsung.aingcheck`.
4. `Contents/_MASReceipt/receipt` 가 비어 있지 않은 파일로 있다 — **앱스토어가 설치한 사본에만 있다.** 개발 맥의 `scripts/package-mas.sh` 산출물·스크래치 빌드는 같은 번들 ID 여도 영수증이 없어 걸리지 않는다.
5. `Contents/MacOS` 가 있다(그리고 `Wrapper`·`WrappedBundle` 이 없다) — 같은 번들 ID 의 아이폰 앱 래퍼는 제외.

판정은 못 찾음 쪽으로 기운다(읽기 오류·모호하면 '없음'). 오탐은 근무를 멈추지만 미탐은 지금 상태(앱스토어 판의 경고 한 번)로 돌아갈 뿐이다.

**실행 시점** — 델리게이트가 만들어지는 순간 판정한다(`AppStoreRetirementState.live()`). 참이면 메뉴바 아이콘을 넣지 않고(`MenuBarExtra(isInserted:)` — 첫 렌더부터), `applicationDidFinishLaunching` 은 SIGTERM 마무리 설치 바로 뒤에서 물러남 창 하나만 띄우고 돌아간다: 세션 활성화 · 전역 단축키 · 로그인 항목 자동 등록 · 업데이트/공지 감시 · 오버레이 · 할 일 동기화 · 오목/체스 배선 · 첫 실행 안내를 하나도 하지 않는다. 스토어에도 2차 게이트(`WorkTimerStore.retiredForAppStoreEdition`)가 있어 저장 세션 활성화 · 근무 시작 · AI 기록 읽기/토큰 업로드 · 깨어남 처리가 아무것도 하지 않는다. 앱 활성화(미니게임 인편)·종료(퇴근 동기화)도 서버를 치지 않는다.

**메뉴바 아이콘 빼기** — `MenuBarExtra(isInserted:)` 의 상태 항목은 ⌘-끌기로 뺄 수 있는데 빼도 앱이 끝나지 않는다(2026-10-15 실측: behavior = `removalAllowed`. 0.3.52 의 `MenuBarExtra { }` 는 `removalAllowed | terminationOnRemoval` 이라 빼면 끝났다). 그대로 두면 아이콘 없는 앱이 남으므로, 사용자가 뺀 쓰기가 오면 예전처럼 앱을 끝낸다(`shouldQuitAfterMenuBarWrite` — 근무 중이면 평소 종료처럼 마무리). 물러남이 내린 경우에는 끝내지 않는다.

**실행 중** — 앱스토어 판이 켜지는 것을 본다. **주 경로는 `NSWorkspace.runningApplications` KVO 다** — 앱스토어 판은 LSUIElement 라 `NSWorkspace.didLaunchApplicationNotification` 이 오지 않는다(2026-10-15 실측: LSUIElement 더미 앱을 띄우자 통지 0건 · KVO 삽입 1건). 통지 관찰은 보조 길로 남아 있다. 켜진 번들이 위 조건을 만족하면: 먼저 근무 시작을 막고(`retiringForAppStoreEdition` — 마무리를 기다리는 동안 단축키·넛지가 새 근무를 열면 곧 버려진다), 근무 중이고 내가 연 세션이면(종료 훅과 같은 조건) 평소 종료와 같은 퇴근 동기화(`finishWorkBeforeQuit`)를 끝내고, 자기를 새 인스턴스로 다시 띄워(`--check-retire-finished-work` · `--check-retire-app-store-edition <경로>`) 물러남 모드로 들어가게 한 뒤 이 인스턴스는 끝난다. 재실행이 실패해도 끝난다. 근무를 넘기지 않고 끝내는 이유: 끄기만 하면 앱스토어 판이 그 세션을 흡수해도 이 맥의 기기 주장 행 때문에 되찾지 않고, 스캐빈저가 10분 뒤 마지막 신호 시각으로 닫는다.

**물러남 창** — "이 맥에 앱스토어 판 아잉체크가 있어요"(근무를 마무리하고 다시 떴으면 그 사실 한 줄 · 지난번 brew 가 못 지웠으면 그 사실 한 줄 더). 본문은 계정에 남는 것(기록·루비·팀·할 일)과 넘어가지 않는 것(단축키 같은 이 맥의 설정 — 앱스토어 판은 다른 저장 자리에서 빈 상태로 시작한다)을 함께 말한다. [나중에]·창 닫기는 그냥 종료한다(로그인 항목은 그대로 — 다음 로그인에 다시 묻는다). [이 판 지우고 앱스토어 판 열기](기본 버튼 — Return)는:

0. **누른 순간 앱스토어 판을 다시 판정한다**(`AppStoreRetireRemoval.live`). 창이 떠 있는 동안 앱스토어 판을 지웠으면 아무것도 지우지 않고 끝낸다(처음 찾은 자리가 사라졌어도 다른 설치 사본이 있으면 그것을 연다).
1. 로그인 항목 해제(`SMAppService.mainApp.unregister()`) — 먼저.
2. 설치 출처는 업데이트와 같은 판정(`UpdateRunner.installSource` · `brewPath` — brew 가 **이 번들을** 관리할 때만 brew).
   - brew: 떼어 낸 셸(`nohup zsh -c`)로 이 앱이 끝나기를 잠깐 기다린 뒤 `brew uninstall --cask aing-check`, 끝나면 `open <앱스토어 판>`. 값은 전부 argv 로 넘긴다(스크립트·래퍼는 상수). 로그는 `~/Library/Logs/aing-check-retire.log`, 결과는 상태 파일 `~/Library/Caches/kingcheck/retire.state`(`ok` · `brew-failed`). brew 가 못 지웠으면(다른 관리자 소유 접두사 · 잠금) 다음 물러남 창이 그 사실을 알리고, 다음 [지우기]는 남은 자리를 Finder 로 먼저 보여 준다. 셸을 못 띄우면 지우지 않고 Finder 로 보여 준다(brew 가 관리하는 사본을 우리가 지우면 brew 기록이 낡는다).
   - 그 밖(DMG·수동): 자기 번들을 휴지통으로 — 실패하면(읽기 전용 볼륨 · 권한) Finder 에서 보여 준다. **App Translocation** 으로 돌고 있으면(끌어다 놓지 않고 바로 연 사본) 휴지통은 임시 사본에서 실패하므로 시도하지 않고, `SecTranslocateCreateOriginalPathForURL`(이름으로 찾는다)로 얻은 **원래 자리**를 Finder 로 보여 주기만 한다. 자기 번들이 우리 `.app`(번들 ID `kingcheck`)이 아니면(`swift run` 같은 개발 실행) 아무것도 지우지 않는다.
   - **자기 번들 말고는 아무것도 지우지 않는다.**
3. 앱스토어 판 열기 → 종료. 열기는 **이 앱이 끝난 뒤에** 한다(떼어 낸 셸이 PID 가 사라지기를 기다렸다가 `open`) — 이 앱이 살아 있을 때 열면 앱스토어 판의 첫 실행이 이 앱을 보고 한 번뿐인 "다른 판 동시 실행" 경고를 써 버린다. 셸을 못 띄우면 직접 연다.

실패는 삼키지 않고 `os.Logger`(subsystem `kingcheck`, category `retire`)에 남긴다.

**알려진 한계 — 디스크에 남은 동기화 큐** — 물러난 실행은 세션을 살리지 않으므로 지난 실행이 남긴 근무 동기화 큐(`pendingItems` — 오프라인에서 연·닫은 근무)를 보내지 않는다. 앱스토어 판은 저장 자리가 달라 그 큐를 못 본다. 그래서 오프라인에서 근무를 하고 앱을 끈 뒤 앱스토어 판을 깔고 이 판을 켜면 그 근무 기록은 서버에 가지 않는다(물러남은 '서버에 아무것도 보내지 않는다'가 먼저다 — 큐를 보내려면 세션을 살려야 한다). 실행 중 물러남도 마무리 동기화가 3초 안에 끝나지 않으면 퇴근 기록이 큐에 남는다 — 그 세션은 서버의 스캐빈저가 마지막 신호 시각으로 닫는다.

**개발자 탈출구** — `defaults write kingcheck check.allowAlongsideAppStoreEdition -bool true` 면 물러나지 않는다(실행 시점·실행 중 둘 다). UI 는 없다. 앱스토어에서 받은 사본과 brew 판을 한 맥에서 함께 시험할 때 쓴다.

## 두 판 모두 (심사 지침 5.1.1(i)(v) · 1.2)

- 설정 '일반' 머리 줄에 [개인정보 처리방침 · 이용약관] 링크, '내 정보' 머리 줄에 [계정 삭제](로그인했을 때만). 머리 줄과 같은 글자 크기라 설정 본문의 높이 계약(창 높이 − 본문 = 여유 5pt)은 그대로다. 링크는 절 끝의 꼬리 클로저로 단다 — `section("내 정보") { 본문 } trailing: { 링크 }`. 여는 줄이 링크 없는 절과 같아서, 그 줄을 붙잡는 다른 계약(상태메시지 '별명 바로 아래')과 부딪히지 않는다.
- 이 문 넷(머리 줄 링크 둘 · 가입 한 줄 · 앱 시작의 첫 실행 안내 배선)은 지워도 높이가 그대로라 다른 테스트가 못 잡는다. V0351 이 그림(로그인 전·후 '내 정보' 머리 줄의 빨강)과 소스 계약으로 자리를 되묻는다 — 계약을 맞추려고 문을 떼지 마라.
- 계정 삭제는 설정 본문과 자리를 바꾸는 화면이다: 지워지는 것 → 비밀번호 → [계정 삭제] → [취소]/[영구 삭제] 2단 확인. 순서는 폰과 같다 — 비밀번호로 재로그인 → 프로필 사진 → `delete_my_account` → 로그아웃과 같은 로컬 정리(로그인 이메일·별명도 잊는다). 재로그인이 다른 계정이면 지우지 않는다.
- 가입 폼의 가입 버튼 아래 "가입하면 이용약관과 개인정보 처리방침에 동의하게 돼요"(두 낱말이 링크).
- 주소는 `CheckAppLinks.privacyPolicy` · `CheckAppLinks.termsOfService`(폰과 같은 GitHub Pages).

## 개인정보 매니페스트

`Sources/check/Resources/PrivacyInfo.xcprivacy`. 패키징 스크립트가 앱 번들의 `Contents/Resources/PrivacyInfo.xcprivacy` 로 복사한다(SwiftPM 리소스 번들 안에도 한 벌이 실리지만 해가 없다). 필수 사유 API: UserDefaults `CA92.1` · 파일 타임스탬프 `3B52.1` · 부팅 시각 `35F9.1`. 새 범주의 API 를 쓰면 V0351 테스트가 빨개진다.

## 패키징 게이트(바이너리 금지어)

앱스토어 판 실행 파일에 다음이 **없어야** 한다(`strings -a` · `nm`). 2026-10-14 디버그·릴리스 빌드(arm64) 실측 0건.

- 문자열: `brew upgrade` · `brew update` · `releases/latest` · `aing-check-update` · `api.github.com` · `nohup` · `hdiutil` · `spctl` · `app-server` · `/bin/zsh` · `--output-format` · `command -v codex` · `uninstall --cask`(0.3.53 물러남 — 2026-10-15 디버그 빌드 실측 0건)
- 심볼: `UpdateRunner` · `dmgUpdateScript` · `upgradeScript` · `AILimitAntigravityReader` · `ProcessSession` · `shellLookupScript`
- 자식 프로세스는 **Claude 리밋의 시스템 도구 `/usr/bin/security` 하나**만 띄운다(0.3.52 결정). 그래서 `nm -u` 의 `NSTask` 참조는 0 이 아니다 — 사용자 설치 실행 파일(`agy`·`codex`·로그인 셸)을 띄우는 문자열이 위 목록대로 0건인 것으로 가른다.
- 주의: `kingcheck.mas` 같은 15바이트 이하 문자열은 릴리스 빌드에서 명령어 안에 박혀 `strings` 로 안 보인다 — "있어야 한다" 쪽 검사는 문자열로 하지 마라(디버그 빌드에서는 보인다).

## 운영 수칙(이 판이 생기며 새로 생긴 것)

- 앱스토어 판은 심사를 기다리는 동안 구버전이다. `app_build` 로 기능을 여는 서버 게이트(예: `chess_min_build`)는 앱스토어 판이 판매 중이 된 뒤에 올린다.
- 같은 커밋이면 두 판이 같은 `CFBundleVersion` 을 쓴다(서버는 빌드 번호만 본다).
