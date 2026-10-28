<!-- 원본: 없음 (계약 폴더 안내 — Swift 짝 없음) -->
# contract/ — Swift ↔ Kotlin 계약 (K1)

맥·iOS 의 Swift 가 **기준 구현**이고, Android·Windows 의 Kotlin 이 따라간다(판정 권위는 서버). 그 사이를 이 폴더가 잇는다.
기준이 바뀌는 흐름은 **Swift → contract/ → Kotlin** 한 방향이다. 이 폴더의 파일은 **손으로 고치지 않는다.**

| 자리 | 무엇 | 누가 쓰나 |
|---|---|---|
| `golden/<영역>/<이름>.json` | 골든 한 벌(아래 형식) | 맥에서 `scripts/golden-export.sh` 쓰기 모드(Swift `GoldenExport` 스위트) |
| `golden/_manifest.json` | 계약 골든 목록 + 실험 표 목록 + GoldenExport 시험 수 | 같은 스크립트가 영수증으로 조립한다(생성물 — 병합 충돌이 나면 다시 돌린다) |
| `golden/_digests.json` | Swift 원본 지문(Swift 없는 CI 용) | `multiplatform/tools/golden-digest.py --write`(스크립트가 부른다) |
| `push/payloads/*.json` | 푸시 트리거 실출력(K7) | W0-c |

## 1. 영역과 주인(`multiplatform/tools/lanes.yml` 이 정본)

| 영역 | 주인 | 영역 | 주인 |
|---|---|---|---|
| `rng` | W0-b | `wire` · `errors` · `jwt` · `realtime` | W1-d |
| `tetris` · `flappy` · `timing-bar` · `framerate` | W1-a | `session` | W2-a |
| `renju` · `chess` · `duel-fee` | W1-b | `duel`(테트리스 대결 재개 — `tetris` 와 따로) · `pause` | W2-e |
| `gacha` · `insights` · `weekly` · `todo` · `text` · `sort` · `dates` · `stickers` | W1-c | `desktop-work` | W2-g |
| | | `token-usage` | W2-h |

- 0.3.62 범위: 아잉이 이모티콘 토큰 `"[아잉:<이름>]"` 판정 표는 `stickers`(W1-c — `MessageBody.sanitized` 뒤 **통째 일치**일 때만 그림),
  미니게임 자동 일시정지 `PauseState` 전이 표는 `pause`(W2-e). 두 표 모두 이 문서의 형식(K1) 그대로다.

## 2. 파일 형식(K1)

```json
{
  "cases": [
    { "id": "zero", "next": ["0xe220a8397b1dcdaf", "…"], "seed": "0x0000000000000000", "unitBits": ["3fec4415072f63b9", "…"] }
  ],
  "equivalence": "bit",
  "generator": "Tests/checkTests/GoldenExport/_base/GoldenExportBase.swift",
  "golden": "rng/splitmix64",
  "platformSensitive": false,
  "schema": 1,
  "spec": { "algorithm": "…", "unit": "…" },
  "swiftSources": ["Sources/CheckCore/MiniGameEngine.swift", "Sources/CheckCore/GomokuAIEngine.swift"]
}
```

머리말은 **정확히 여덟 칸**이다(더도 덜도 없다 — Kotlin 로더가 확인한다).

| 칸 | 뜻 |
|---|---|
| `golden` | `영역/이름`. 파일 경로 `golden/<golden>.json` 과 같아야 한다. 소문자·숫자·`-`(이름 마디는 `.`·`_` 도) |
| `schema` | 형식 판. 지금 `1`. 올리면 Swift 작성기·Kotlin 로더·golden-digest 를 같은 커밋에서 올린다 |
| `equivalence` | `bit`(모든 출력 비트가 같다) · `discrete`(정수·열거만 같다, 실수 허용 오차는 `spec` 에) · `set`(정답 집합 안) — C§5.1 |
| `generator` | 이 파일을 쓴 Swift 시험 파일(저장소 상대 경로). 작성기가 `#filePath` 로 채운다 |
| `swiftSources` | 이 값을 낸 Swift 원본(저장소 상대, `Sources/` 또는 `Tests/checkTests/Fixtures/`). 지문(_digests)이 이것을 센다 |
| `platformSensitive` | 기기 ICU·tzdata 에 기대면 `true` → Android 계측(헤드리스 에뮬레이터)에서도 대조한다(C§5.5) |
| `spec` | 사람이 읽는 규칙 설명(식·접기 규칙·인코딩). Kotlin 은 이것을 보고 구현하지, 값을 읽지 않는다 |
| `cases` | 비지 않은 배열. 원소는 객체이고 **글자 `id` 가 있다(파일 안에서 겹치지 않는다)** — 실패 문구가 case 를 가리킨다 |

크기 예산(C§5.3): 파일 하나 2 MB 이하(작성기가 막는다), 계약 골든 합계 12 MiB(12,582,912 B) 이하(G §8-18 6 — 10 MiB 에서 올림. 값은 `multiplatform/tools/golden-digest.py` 의 `TOTAL_BUDGET` 한 곳이고, `scripts/golden-export.sh` 의 assemble 이 막고 `golden-digest.py --self-test` 가 경계를 잰다).

### 2-1. 정규 바이트

같은 값이면 어느 작성기든 **같은 바이트**다 — 파이썬 `json.dumps(값, indent=2, sort_keys=True, ensure_ascii=False) + "\n"`.

- 키는 **유니코드 코드포인트 순서**로 정렬한다(Kotlin `String.compareTo` 는 UTF-16 단위라 다르다 — `GoldenCanonical.codePointOrder`).
  키는 ASCII 만 쓴다(Swift 사전은 정준 동치인 키를 하나로 합친다).
- 들여쓰기 2칸, 항목 사이 `,` + 줄바꿈, 키와 값 사이 `": "`, 빈 배열 `[]`·빈 객체 `{}`, 끝에 줄바꿈 하나.
- 글자는 `"` `\` 와 제어 문자만 이스케이프한다(`\b \f \n \r \t`, 나머지 `\u00xx` 소문자 16진). 다른 글자는 그대로 — **NFC 로 바꾸지 않는다.**
- 시각·기계 이름·툴체인 판·커밋 SHA 를 싣지 않는다(같은 소스면 같은 바이트). Swift `Dictionary`·`Set` 을 순회한 순서로 내지 않는다.
- 줄 끝은 LF 로 쓴다. 그러나 **바이트를 견주는 것은 맥 Swift 비교 모드뿐**이다. Kotlin 은 파일 날바이트가 아니라 **파싱한 값**으로 견준다(`Golden.load`).
  그래서 Windows 체크아웃(`core.autocrlf=true` 면 글자 파일이 CRLF 로 풀린다 — 저장소에 `.gitattributes` 가 없다)에서도 대조가 같다.
  `golden-digest.py` 의 골든 파일 지문은 CRLF 를 LF 로 접어 센다(지문이 체크아웃 줄 끝에 따라 갈리지 않게). Kotlin `GoldenCoverageTest` 가
  체크아웃의 줄 끝을 `AINGCHECK-GOLDEN-EOL` 줄로 시험 결과에 남긴다.

### 2-2. 값 표기

| 값 | 표기 | 예 |
|---|---|---|
| 64비트 정수(난수·해시·시드) | `"0x"` + 소문자 16진 **16자리** | `"0x00000000013529dc"` |
| Double | 키 이름 끝을 `Bits` 로, 값은 IEEE-754 비트 소문자 16진 16자리(`0x` 없음) | `"dtBits": "3f90000000000000"` |
| 정수 | JSON 숫자는 ±2^53 안에서만. 넘으면 위 64비트 표기 | `"advance": 196` |
| 글자(정규화·그래핌이 걸린 것) | 코드포인트 16진 목록(공백 구분) — 편집기가 NFC 로 바꿔도 값이 안 변한다 | `"cps": "1100 1161 11a8"` |
| 실수 숫자 | **쓰지 않는다**(십진 짧은 표기 규칙이 언어마다 달라 바이트가 갈린다) | — |

Kotlin 은 `Golden.hex64("0x…")` → `ULong`, `Golden.bits("…")` → `Double` 로 읽는다.

### 2-3. 디코드 덤프 규칙(G6 — C-X10 로 정했다)

Swift `GoldenMirror.dump`(Tests/CheckGoldenSupport) 와 Kotlin 리플렉션 덤프기가 **같은 바이트**를 낸다. 값이 객체로 오면 키는 저장 프로퍼티 이름(Swift 이름 그대로, C§2.3).

| Swift 값 | 덤프 |
|---|---|
| 구조체·클래스 | 객체. 저장 프로퍼티만(계산 프로퍼티 없음). 클래스는 상위 클래스 칸까지. lazy 저장 칸(`$__lazy_storage_$_…`)은 뺀다 |
| Optional | **모든 겹을 벗긴다.** `Int??` 의 `.some(nil)` 과 `nil` 은 같은 `null` 이다(Kotlin 에 겹친 널이 없다) |
| 연관값 없는 열거 | 갈래 이름 글자 — 원시값이 아니다(`"notSignedIn"`, `"not_signed_in"` 아님) |
| 연관값 있는 열거 | `{"$case": 이름, "$value": 값}`. 연관값 **하나**면 그 값(이름표는 버린다 — Swift 가 1-튜플을 안 만든다), **이름표 있는 둘 이상**은 객체, **이름표 없는 둘 이상**은 위치 순 배열 |
| 배열 | 배열 |
| Set | 원소 덤프의 정규 글자를 코드포인트 순서로 정렬한 배열 |
| 사전 | 키가 String 이면 객체(키는 snake 변환을 안 탄다 — C§4 #37, C-X3 실측), 아니면 `[키, 값]` 쌍 배열을 쌍의 정규 글자 순서로 |
| 정수(모든 폭) | ±2^53 안이면 숫자, 밖이면 `{"$int": "0x…"}`(64비트 2의 보수) |
| Double · Float · CGFloat | `{"$f64": "<비트>"}`(Float 은 Double 로 넓힌 비트) |
| Date | `{"$date": "<1970 기준 초 Double 비트>"}` |
| Data · UUID · URL | `{"$data": base64}` · `{"$uuid": 소문자}` · `{"$url": 절대 주소}` |
| Bool · String · Character | 불 · 글자 · 글자 |
| 그 밖 | 덤프기가 실패한다(조용히 description 으로 접지 않는다) |

Kotlin 쪽 약속(C-X10 실측 — `MirrorDumpProbeTest`):

- 연관값 없는 열거 → `enum class`, 상수 이름 = Swift case 이름 그대로. 연관값 있는 열거 → `sealed interface` + 갈래마다 `data object`/`data class`
  (클래스 이름은 Swift case 이름의 첫 글자만 대문자로 써도 덤프기가 첫 글자를 소문자로 접는다). 이름표 없는 연관값 둘 이상은 칸 이름 `v0`·`v1`….
- Swift `Date` 는 Kotlin 에서도 **1970 기준 초 Double** 로 든다(C§2.5). `Instant` 로 바꾸면 나노초 정수 산술이 끼어 비트가 갈릴 수 있다.
- **덤프기는 kotlin-reflect 의 선언 타입으로 칸을 읽는다.** JDK 리플렉션은 `ULong`(인라인 값 클래스) 칸을 밑 타입 `long` 으로 보여
  `UInt64.max` 가 `-1` 로 나온다(실측). 같은 이유로 인라인 값 클래스로 감싼 칸 전부가 해당된다.

### 2-4. 입력 대본 재생(G3 — C-X2 로 정했다)

테트리스 대본은 조종사 없이 **프레임별 입력 연산**으로 싣는다(`Tests/checkTests/GoldenExport/_base/GoldenTetrisOps.swift`).

- 연산: `L+ L-`(왼쪽 눌림/뗌) · `R+ R-` · `SD+ SD-`(소프트드롭) · `CW CCW`(회전) · `HOLD` · `ACT`(`action()`). 한 프레임 = 그 프레임의 연산을 부른 순서대로 → `step(dt)` 한 번.
  눌림/뗌은 상태가 바뀔 때만 적는다.
- RLE 글자: `"개수:연산들"` 을 쉼표로 잇는다. 연산이 여럿이면 공백으로 잇는다. 예 `"4:,1:R+,7:,1:R-,2:,1:CW ACT"`.
- 시작: `{"kind": "new", "preOps": "ACT"}`(새 판에서 첫 접기 전에 판 시작) 또는 `{"kind": "advance", "advance": 330}`(빈 판 · ARE 단계 픽스처).
- 해시: FNV-1a 64(`GoldenFNV1a64` = V0360 `GoldHasher`, 64비트 값을 작은 끝부터 8바이트로 접는다). 첫 접기 = 시작 판 전체, 프레임마다
  관측 칸(`goldFoldLight` 순서), advance 가 바뀐 프레임엔 판 전체. 64프레임마다 체크포인트, Kotlin 은 첫 불일치 구간 [f₀, f₁] 을 말한다.
- C-X2 실측: V0360 대본 A~D 를 기록해 재생한 해시가 박힌 네 값(`64cdf7c736fca8b9` · `b8cf191116c89774` · `d30fb21e622f28c6` · `6519e5cdf43bdb8c`)과
  전부 같다. RLE 크기 A 4,550 · B 4,170 · C 1,169 · D 414 바이트.

### 2-5. 스토어 시나리오(G7 — C-X9 로 정한 조건)

세션 시나리오(실행 → 조정자 갱신 → 401 → 갱신 → 재시도 → 로그아웃)를 20회씩 7묶음(부하 섞음) 돌린 실측:

- 요청 본문 바이트는 **실행마다 키 순서가 다르다**(JSONEncoder 에 `.sortedKeys` 가 없다) → G5·G7 은 본문을 **파싱해 정규 JSON 으로** 비교한다.
- 동시에 떠나는 요청(`register_device` 와 `memberships`)의 **순서가 부하에서 뒤집힌다**(7묶음 중 2묶음에서 20회 중 1회).
- 본문 정규화 + 요청 묶음을 **순서 없는 모음**으로 보면 140회 전부 같은 바이트였다. G7 골든은 이 두 정규화를 거친 모양으로만 만든다.

## 3. 잠금 세 겹(C§5.4 · A§4-2)과 어디서 무엇을 재나

1. **Swift 비교 모드** — `GoldenExport` 스위트는 기본으로 비교 모드다. 엔진을 바꿨는데 골든을 안 다시 쓰면 Swift 가 빨갛다.
   이 시험들은 맥 **전체 스위트**(`swift test`, 출시 게이트 — G §8-1)에 그대로 든다.
2. **Kotlin 대조** — 각 골든에 `Golden.load("<이름>")` 하는 Kotlin 시험이 있어야 한다(`GoldenCoverageTest` — 미소비 금지). 목록에 없는 이름을 읽어도 빨강.
   소비로 세는 것은 **게이트가 돌리는 소스셋**(commonTest · desktopTest · androidHostTest · 앱 모듈 test)의 주석 밖 코드에서 이름을 **글자 리터럴**로 부른 것뿐이다(§5).
3. **소스 지문** — `golden-digest.py --check` 가 `swiftSources`·생성 시험·작성기와 바탕(`Tests/CheckGoldenSupport/*.swift` · `Tests/*/GoldenExport/_base/*.swift`)을
   주석을 걷어 sha256 으로 세고 골든 파일 바이트(CRLF→LF)까지 `_digests.json` 과 대조한다. 생성 시험 파일의 코드(주석 밖)에 골든 이름이
   글자 리터럴로 있는지도 여기서 본다(주석 걷기는 `swift_source.py` 한 벌 — Swift 에 둘째 구현을 두지 않는다).
   CI(`mp-ci` golden-digest 잡, main·xplat 매 푸시)와 빠른 게이트가 돈다. 다르면 "맥에서 `scripts/golden-export.sh` 를 돌려라". 주석·빈 줄만 바꾼 커밋은 그대로 초록이다.

| 무엇을 재나 | 맥 전체 스위트(`swift test`) | `scripts/golden-export.sh`(비교 모드) | `golden-digest --check` | Kotlin 게이트 |
|---|---|---|---|---|
| 골든 값 = Swift 가 지금 내는 값 | ○(GoldenExport 시험) | ○ | — | — |
| 목록 = 디스크의 골든 파일(정적 고아·목록만) · 생성 시험 파일 있음 · 목록 정규 바이트 | ○(`GoldenExportBase.manifestMatchesFiles`) | ○ | 계약 고아 · 생성 시험 파일 | 계약 고아(`GoldenCoverageTest`) |
| 생성 시험 코드(주석 밖)에 이름 글자 리터럴 | — | ○(`--check` 를 부른다) | ○ | — |
| GoldenExport 시험 개수(목록 = 돈 수 = `exportTests`) · 건너뜀 0 · 스위트 밖 시험 0 | — | ○ | — | — |
| 영수증 고아(이번 실행에서 아무 시험도 쓰지 않은 골든·실험 표) · 목록 조립 | — | ○ | — | — |
| 소스 지문(`swiftSources` · 생성 시험 · 작성기·바탕 · 골든 바이트) | — | ○ | ○ | — |
| Kotlin 소비(미소비 · 목록 밖) | — | — | — | ○ |

**맥 전체 스위트만으로는 개수 · 건너뜀 · 스위트 밖 시험 · 영수증 고아를 재지 않는다.** 전체 스위트의 정적 잠금은 약하다 —
파일 집합만 보고, 어느 시험이 실제로 그 골든을 썼는지(영수증) · 몇 개가 돌았는지 · 건너뛰었는지는 모른다.
예: 실험 표(지문 밖)의 생성 시험에 `.disabled` 를 붙이면 전체 스위트는 그 시험을 건너뛰고 초록, `golden-digest --check` 도 초록이다 —
스크립트만 "건너뜀"·"영수증 고아"로 빨갛다. 그래서 `scripts/golden-export.sh`(비교 모드)를 **따로** 돌린다:

- 골든을 더하거나 고친 갈래의 완료 보고 전(브랜치에서 종료 0).
- 갈래를 병합할 때마다(G §2-5 — 생성물 `_manifest.json`·`_digests.json` 도 이때 다시 만든다).
- Android·Windows 출시 전(G §4-1 "Swift 쪽: 맥 빠른 게이트 + `golden-export.sh` 비교 모드 초록").
- 맥 앱 출시 스크립트는 이 스크립트를 부르지 않는다. 맥 출시를 막는 것은 전체 스위트 안의 비교 모드 시험뿐이다.

## 4. 갱신 절차(사람·에이전트 공통)

1. 맥에서 `CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh` — 골든·`_manifest.json`·`_digests.json` 을 다시 쓰고 **언제나 종료 1**(실수로 초록이 되지 않게).
2. `git diff contract/golden` 으로 바뀐 이유를 확인하고 커밋 메시지에 적는다.
3. 같은 커밋(또는 바로 다음 커밋)에서 Kotlin 을 고친다.
4. `scripts/golden-export.sh`(비교 모드)가 종료 0 이어야 한다.

## 5. 갈래가 골든을 더하는 법

- Swift: `Tests/checkTests/GoldenExport/<갈래>/` 또는 `Tests/CheckMobileKitTests/GoldenExport/<갈래>/` 에 `@Suite struct GoldenExport<갈래>`
  (이름이 `GoldenExport` 로 시작 — 스크립트의 `--filter GoldenExport` 와 `swift test list` 의 `.GoldenExport…/메서드` 개수).
  자유 함수 `@Test` 금지 — GoldenExport 파일 안의 자유 함수는 시험 ID 에 파일 이름이 들어 `--filter` 에 걸려 **돌기는 하지만**(W0-b 검증 실측)
  목록 정규식이 스위트 메서드만 세므로 "돈 수 ≠ 목록 수"로 빨갛다. 스크립트가 xunit 결과로 스위트 밖 시험 이름을 짚어 준다.
  `goldenEmit(GoldenFile(golden: "<영역/이름>", equivalence:swiftSources:platformSensitive:spec:cases:))` 한 줄 — 이름은 **글자 리터럴**로
  (`golden-digest --check` 가 생성 시험 코드에서 찾는다). UserDefaults·키체인·네트워크·창 금지.
- Kotlin: `Golden.load("<영역/이름>")` 로 읽는다. 이름은 **글자 리터럴**로 쓴다 — 상수로 빼면(`Golden.load(NAME)`) 실제로 대조해도
  `GoldenCoverageTest` 가 미소비로 센다. 소비 시험은 게이트가 돌리는 소스셋(commonTest · desktopTest · androidHostTest · 앱 모듈 test)에 둔다 —
  기기 계측(androidDeviceTest·androidTest)에만 있는 호출은 세지 않는다(골든은 JVM 에서 전부 대조하고 계측은 그 위에 더한다, C§5.5).
  실패 문구는 `golden.failure(caseId, "…")`(골든 이름 · case · 첫 불일치 · swiftSources · Swift 자세히 보기 명령).
  Swift 쪽 한 case 를 자세히 보려면 `CHECK_GOLDEN_VERBOSE=<id> scripts/golden-export.sh`.
- 서버 SQL 의 판정 결과(예: `minigame_min_seconds`, `gomoku_judge` 내부)는 싣지 않는다 — 공개 저장소다(C§5.6). 클라 상수만.

## 6. W0-b 실험 표(계약 아님) — `multiplatform/testkit/src/desktopTest/resources/golden/w0b-probe/`

같은 K1 형식이고 같은 비교/쓰기 모드로 지킨다(`_manifest.json` 의 `probes`). 계약이 아니라서 지문(_digests)에는 넣지 않는다.
Kotlin 은 `Golden.loadProbe("w0b-probe/<이름>")`. **W0-f ③(ART API 26·36)** 은 이 파일들을 그대로 계측 시험 assets 로 복사해 읽는다.

| 파일 | 실험 | 읽는 법(요약 — 자세히는 각 파일 `spec`) | JVM 실측(맥 JDK 21.0.10 aarch64 · CI 결과도 같으면 따로 안 적음) |
|---|---|---|---|
| `pow3.json` | C-X1 | x = SplitMix64(`spec.seed`).unit() 를 100만 개. Darwin `pow(x,3)` = `(x*x)*x` 의 비트 + δ(`deltas`: 36진 건너뛴 수 + `+`/`-`/`=δ;`). 되살린 값을 FNV 로 접어 `powDigest` 와 먼저 맞춘다 | aarch64(맥): `Math.pow`·`StrictMath.pow` 가 Darwin 과 다른 x **98,069개(9.81%)**, 둘끼리 0. amd64(CI ubuntu·windows, JDK 21.0.12): `Math.pow` **1,443개**, `StrictMath.pow` 98,069개, 둘끼리 97,708개 — **`Math.pow` 는 JVM 끼리도 아키텍처마다 비트가 다르다.** `(x*x)*x` 는 256,870개(25.7%, 전부 ±1ulp) |
| `gravity.json` | C-X1 | 단계 1~20: `baseBits`·`exponentBits`·Darwin `powBits` | 단계 18 이 1ulp 다르다(aarch64 `Math.pow`·`StrictMath.pow`, amd64 `StrictMath.pow`). amd64 `Math.pow` 는 20단계 다 같다 → 중력은 비트 표 상수(W1-a) |
| `text-scalars.json` | C-X4 | 평면마다 `ranges` = `시작-끝:분류`(분류 = 일반 범주 2자 + White_Space + 보이는 글자 + NFC 안정, 각 0/1). 구간 4,257개 | 일반 범주 **10,617** 스칼라 다름(JDK 21 = 유니코드 15.0, Swift 쪽이 더 새 판) · 보이는 글자 10,615 · White_Space 0 · NFC 안정 0 |
| `graphemes.json` | C-X4·C-X13 | `cps` → `clusters`(그래핌마다 스칼라 수) · `count` | `BreakIterator` 가 300줄 중 **2줄** 다름(인도계 결합 InCB, 유니코드 15.1 규칙) |
| `nfc.json` | C-X4 | `cps` → `nfc`(Swift `precomposedStringWithCanonicalMapping`) | `java.text.Normalizer` 와 **6줄** 다름 — **Swift(Foundation) 쪽이 표준과 어긋난다**(아래) |
| `kst.json` | C-X12 | epoch → KST 성분 · `weekday`(1=일) · `offset` · `dayKey` · `mondayEpoch`. 1950~2040 표본 + tzdb 서머타임 전환 ±1초(28회) + 앱 경계 | kotlinx-datetime 와 1,375건 **전부 같다** |
| `decoder.json` | C-X3 | 칸 타입 × 입력 28가지의 `ok:`/`error:` + 키 변환 표 | (Kotlin 대조는 W1-d) |
| `mirror-dump.json` | C-X10 | 실제 타입 열네 개 + 합성 표본의 G6 덤프 | 19표본 중 18 바이트 일치, 1개는 JDK 리플렉션의 ULong 한계(§2-3) |

`nfc.json` 의 Foundation 어긋남(맥·iOS 가 서버·JVM 과 다르게 정규화하는 입력 — W1-c 가 Kotlin 을 어느 쪽에 맞출지 정한다):
완성형 LV + 종성 자모(`ac00 11a8` → Foundation 그대로, 표준 `ac01`) · 옛 종성(`1100 1161 11c3` → Foundation `ac1c` = 엉뚱한 음절, 표준은 조합 안 함) ·
결합 등급 재배열 누락(`0f73`/`0345` 섞임 3줄) · 태그 글자 + 결합 점(`e0067 0307` → Foundation `0121`).

### 6-1. ART 실측(W0-f ③) — **2026-10-28 에 한 번 잰 스냅숏**(게이트가 다시 재지 않는다)

같은 표를 계측 APK assets 로 읽어 맥 arm64 에뮬레이터에서 쟀다. 봉인(sandbox-exec) · `-read-only` · debug 계측 APK.
측정기는 JVM 쪽과 **같은 소스**다(JVM 은 맥 JDK 21.0.10 aarch64 로 위 표 숫자를 그대로 재현). "Swift" 는 이 표(1b8260d), "JDK" 는 위 JVM 실측이다.
잰 판: API 26 = `system-images/android-26/google_apis/arm64-v8a` Pkg.Revision 1(OSR1.180418.028.A3) · API 36 = `system-images/android-36/google_apis_playstore/arm64-v8a`
Pkg.Revision 7(BE2A.250530.026.D1). **27~35 와 실기기는 재지 않았다** — 기기의 ICU·tzdata 는 시스템 업데이트로 바뀔 수 있다.

| 표 | API 26 — Android 8.0 · ICU 58.2 · Unicode 9.0 · tzdata 2017b | API 36 — Android 16 · ICU 76.1 · Unicode 16.0 · tzdata 2025a |
|---|---|---|
| `pow3.json` | `Math.pow` = `StrictMath.pow` = JDK aarch64 비트(지문 같음) → Darwin 과 **98,069**개 다름 | `Math.pow`(bionic libm) Darwin 과 **1,606**개, `StrictMath.pow` 는 JDK 와 같은 98,069 · 둘끼리 98,075 → **ART `Math.pow` 비트는 API 수준마다 다르다** |
| `gravity.json` | 단계 18 이 1ulp(`Math`·`Strict` 둘 다) | `Math.pow` 20단계 모두 Darwin 과 같음, `StrictMath` 는 단계 18 |
| `text-scalars.json` | 일반 범주 **31,683** · 보이는 글자 31,610 · White_Space 0 · NFC 안정 0(JDK 와는 21,066 · 20,995). 31,629 는 ART 쪽 Cn(배정 전), 54 는 둘 다 배정된 글자의 범주 차이 | 일반 범주 **4,804** · 보이는 글자 4,803 · White_Space 0 · NFC 안정 0(JDK 와는 5,813 — ART 가 더 새 판). 4,803 은 ART 쪽 Cn, 1 은 U+0295(Ll→Lo) |
| `graphemes.json` | `BreakIterator`(java.text = android.icu 같은 답) **26줄**: InCB 2(JDK 와 같은 줄) + 이모지 수식자 U+1F3FB~1F3FF 가 든 줄 23 + ZWJ 뒤 그림 문자 1(g-023). 정규식 `\X` 는 99줄 | **0줄**(JDK 의 InCB 2줄도 Swift 와 같다). `\X` 도 0 |
| `nfc.json` | `java.text.Normalizer` = `android.icu.text.Normalizer2` = JDK — 300줄 전부 같다 → Swift 와는 **위의 6줄만** 다르다 | 같음(6줄 · JDK 와 0) |
| `kst.json` | kotlinx-datetime(디슈거링 없이 java.time) **63건** 다름 — 전부 1948-05-31~1951-09-09 서머타임(tzdata 2017b 의 옛 이력). 1952 이후 1,240건 0 | 0건 |

덧붙여 잰 것: `Character.getType` 과 `android.icu.lang.UCharacter.getType` 은 두 API 모두 0 차이. 정규식 공백 속성 이름이 런타임마다 다르다 — JDK 21 은 `\p{IsWhite_Space}` 만(`\p{White_Space}` 는 PatternSyntaxException), ART API 26 은 `\p{White_Space}` 만, API 36 은 `\p{IsWhite_Space}` 도 된다. 공백 판정을 정규식 이름에 기대지 않는다.

다시 재는 법과 맞춰 볼 값: 측정기 원문은 [`measurements/w0f-art/`](measurements/w0f-art/README.md)(빌드에 들지 않는다 — 그 README 대로 저장소 사본에 넣어 돌린다).
측정기는 덤프를 쓴 **뒤** 표 sha256(W0-b 골든)·pow 표 지문·구간 연속·표 크기·예외 0 을 단언한다(깨진 표면 빨강 — 표 두 개를 바꾼 APK 로 API 26·36 모두 FAILURES 를 확인).
덤프의 정규 지문(시간 칸·단언 칸을 빼고 키를 정렬한 JSON 의 sha256, `measurements/w0f-art/canon.py`) — 같은 판에서 다시 재면 같은 값이 나와야 한다(2026-10-28 두 번 재서 같음):

| 덤프 | 정규 sha256 |
|---|---|
| JVM(JDK 21.0.10 aarch64) | `bbffba8122dea31866f77ae558d74a8c4065aaf030be6ea464b8fd2838ef715f` |
| ART API 26 | `38c2f326e8e54d860ce69318b54633764d98ff7e5ca1e5527bc85279c707053d` |
| ART API 36 | `936582a472b73c397e9e2e1478c1e5a99343d11fcb49021f1861d73d6fa9c656` |

### 6-2. FCM 토큰 실측(W0-f ⑤ — B§9-1 · B§9-4 · E-U6) — **2026-10-28 스냅숏**(바깥망 · 개발 Firebase `aingcheck-dev` · 게이트가 다시 재지 않는다)

계약 골든이 아니라 **서버 CHECK 판정 근거**다. Play 이미지 에뮬레이터(창 없음 · `-read-only` · 봉인 없음)에서 Google 계정 로그인 없이, 재설치·`pm clear` 로 매번 새로 받았다.
토큰 원문은 기기 밖으로 내지 않았다(기기 안에서 길이·글자·정규식 일치만 계산). 측정기 원문·판정 조건·결함 심기·다시 재는 법은 [`measurements/w0f-fcm/`](measurements/w0f-fcm/README.md).

| 판 | GMS | 토큰 | 길이 | 모양 · 글자 |
|---|---|---|---|---|
| API 35 Play(Pkg.Revision 9, `AE3A.240806.036`) | 24.23.35 | 20 | 142 | `<FID 22자>:APA91b<113자>`, `[A-Za-z0-9_:-]` 만(0x2D..0x7A), 대·소문자 섞임 |
| API 36 Play(Pkg.Revision 7, `BE2A.250530.026.D1`) | 25.08.34 → 26.41.31(부팅 안에서 저절로) | 35 | 142 | 같음 |

- 서버 세 꼴 — M1 CHECK `fcm_token ~ '^[!-~]+$' and char_length between 32 and 4096` · `register_device_fcm`(`btrim` 뒤 같은 꼴) · push-send `/^[!-~]{32,4096}$/` — 이 **55/55 를 받는다. 바꿀 것 없다.**
  `btrim` 이 걷는 글자 0. 소문자로 바꾸면 모든 토큰이 달라진다 → M4 의 FCM 비우기에 `lower(` 금지가 맞다. 재설치·데이터 지우기마다 새 토큰(10/10 서로 다름).
- 채널 없는 알림: 앱이 아직 안 만든 채널로 게시하면 **조용히 버려진다**(채널도 안 생긴다 · 만든 뒤엔 보인다) → data-only(K7) 앱은 게시 전에 채널 다섯을 만든다.
  SDK `notification` 메시지가 없는 채널을 가리키면 `fcm_fallback_notification_channel`("Miscellaneous")로 보인다(쓰지 않는 길).
- 재지 않은 것: 실제 발송 왕복(개발 프로젝트 서비스 계정 키 없음) · 실기기 · API 26~34.
