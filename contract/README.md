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

크기 예산(C§5.3): 파일 하나 2 MB 이하(작성기가 막는다), 계약 골든 합계 10 MB 이하(스크립트가 막는다).

### 2-1. 정규 바이트

같은 값이면 어느 작성기든 **같은 바이트**다 — 파이썬 `json.dumps(값, indent=2, sort_keys=True, ensure_ascii=False) + "\n"`.

- 키는 **유니코드 코드포인트 순서**로 정렬한다(Kotlin `String.compareTo` 는 UTF-16 단위라 다르다 — `GoldenCanonical.codePointOrder`).
  키는 ASCII 만 쓴다(Swift 사전은 정준 동치인 키를 하나로 합친다).
- 들여쓰기 2칸, 항목 사이 `,` + 줄바꿈, 키와 값 사이 `": "`, 빈 배열 `[]`·빈 객체 `{}`, 끝에 줄바꿈 하나.
- 글자는 `"` `\` 와 제어 문자만 이스케이프한다(`\b \f \n \r \t`, 나머지 `\u00xx` 소문자 16진). 다른 글자는 그대로 — **NFC 로 바꾸지 않는다.**
- 시각·기계 이름·툴체인 판·커밋 SHA 를 싣지 않는다(같은 소스면 같은 바이트). Swift `Dictionary`·`Set` 을 순회한 순서로 내지 않는다.

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

## 3. 잠금 세 겹(C§5.4 · A§4-2)

1. **Swift 비교 모드** — `GoldenExport` 스위트는 기본으로 비교 모드다. 엔진을 바꿨는데 골든을 안 다시 쓰면 Swift 가 빨갛다.
   맥 **전체 스위트**(출시 게이트, G §8-1)에 든다. `scripts/golden-export.sh` 가 그 소속을 개수로 잰다: `swift test list` 의 GoldenExport 시험 수 =
   실제로 돈 수(건너뜀 0) = `_manifest.json` 의 `exportTests`. 영수증 없는 골든 파일(생성 시험이 없거나 건너뛴 것)은 고아로 빨강.
2. **Kotlin 대조** — 각 골든에 `Golden.load("<이름>")` 하는 Kotlin 시험이 있어야 한다(`GoldenCoverageTest` — 미소비 금지). 목록에 없는 이름을 읽어도 빨강.
3. **소스 지문** — `golden-digest.py --check` 가 `swiftSources`·생성 시험·작성기(Tests/CheckGoldenSupport)를 주석을 걷어 sha256 으로 세고
   골든 파일 바이트까지 `_digests.json` 과 대조한다. CI(`mp-ci` golden-digest 잡, main·xplat 매 푸시)와 빠른 게이트가 돈다.
   다르면 "맥에서 `scripts/golden-export.sh` 를 돌려라". 주석·빈 줄만 바꾼 커밋은 그대로 초록이다.

## 4. 갱신 절차(사람·에이전트 공통)

1. 맥에서 `CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh` — 골든·`_manifest.json`·`_digests.json` 을 다시 쓰고 **언제나 종료 1**(실수로 초록이 되지 않게).
2. `git diff contract/golden` 으로 바뀐 이유를 확인하고 커밋 메시지에 적는다.
3. 같은 커밋(또는 바로 다음 커밋)에서 Kotlin 을 고친다.
4. `scripts/golden-export.sh`(비교 모드)가 종료 0 이어야 한다.

## 5. 갈래가 골든을 더하는 법

- Swift: `Tests/checkTests/GoldenExport/<갈래>/` 또는 `Tests/CheckMobileKitTests/GoldenExport/<갈래>/` 에 `@Suite struct GoldenExport<갈래>`
  (이름이 `GoldenExport` 로 시작 — 스크립트의 `--filter GoldenExport`; 자유 함수 `@Test` 금지 — `--filter` 가 빠뜨린다).
  `goldenEmit(GoldenFile(golden:equivalence:swiftSources:platformSensitive:spec:cases:))` 한 줄. UserDefaults·키체인·네트워크·창 금지.
- Kotlin: `Golden.load("<영역/이름>")` 로 읽고, 실패 문구는 `golden.failure(caseId, "…")`(골든 이름 · case · 첫 불일치 · swiftSources · Swift 자세히 보기 명령).
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
