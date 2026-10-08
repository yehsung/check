# AI 사용량 리밋 — 데이터 출처 계약 (2026-10-07 실측)

이 문서는 **Claude Code · OpenAI Codex · Google Antigravity 의 "리밋이 몇 % 찼는가"를 어디서 어떻게 읽어
어디까지 흘려보내는지의 정본**이다. 값·필드 이름·단위가 여기 적힌 것과 다르면 확인하고 이 문서를 고쳐라.
아래의 요청·응답 모양은 전부 **이 맥에서 실제로 호출해 받은 것**이다(2026-10-07). 추측으로 적힌 줄은 없고,
미확인인 것은 "미확인"이라고 적어 뒀다.

**한 줄 요약**: 맥만 세 도구의 로그인 자격증명을 읽어 **그 도구 자신의 서버**에 사용률을 묻고,
얻은 **퍼센트와 리셋 시각만** 아잉체크 서버에 올린다. 폰과 위젯은 그 숫자를 읽기만 한다.

## 0. 기존 토큰 축과의 관계

이것은 **별개의 새 축**이다. 기존 토큰 스캐너(`CheckTokenUsage.swift`,
`CheckAntigravityUsage.swift`, `CheckCodexAccountUsage.swift`)는 **로컬 로그에서 토큰 수를 센다** —
리밋은 **제공자 서버가 말해 주는 퍼센트**다. 두 축은 표도 화면도 공유하지 않는다.

- ★ 토큰 축 코드를 리밋 작업으로 **고치지 마라.** 같은 "AI 사용량"이라는 말을 쓰지만 장부가 다르다.
- 단위는 리밋 축 안에서 **"쓴 비율 0…100(Double)"** 하나로 통일한다. 제공자마다 다른 표현으로 들어오는 것을
  경계에서 한 번만 뒤집는다(§3 부호).

## 1. Claude Code

**자격증명**: macOS 로그인 키체인, 서비스 `Claude Code-credentials`.

```
/usr/bin/security find-generic-password -s "Claude Code-credentials" -w
```

→ JSON: `claudeAiOauth.{accessToken, refreshToken, expiresAt, scopes, subscriptionType, rateLimitTier}`.
`expiresAt` 은 **epoch 밀리초**, 수명 약 12시간.

- ★★ **Swift `SecItemCopyMatching` 를 쓰면 안 된다.** 이 키체인 항목은 우리 앱이 만든 것이 아니라
  ACL 허용 대화상자(SecurityAgent)가 떠서 **반환하지 않는다**(실측: 15초 타임아웃까지 대기, rc=124).
  메인 스레드에서 부르면 앱이 통째로 멈춘다. **자식 프로세스 + 타임아웃**이 유일하게 깨끗한 경로다.
- ★★ **`~/.claude/.credentials.json` 로 폴백하지 마라**(맥 한정). 그 파일의 토큰은 키체인의 것과 **다르고
  이미 죽어 있다**(실측: 만료된 토큰). 폴백하면 영구 401 을 '만료'로 오보한다.
- ★★ **토큰 갱신 책임을 지지 마라.** `refreshToken` 으로 우리가 갱신하면 refresh token 회전 + 키체인 되쓰기
  경합이 생겨 **사용자가 Claude Code 에서 로그아웃된다.** `expiresAt` 이 과거면 **호출조차 하지 말고**
  "클로드 코드를 한 번 실행해 주세요"로 접는다(만료는 네트워크 없이 공짜로 안다).

**요청**

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Accept: application/json
```

**응답 모양** (값은 자리표시자)

```
five_hour:  { utilization: <0…100>, resets_at: "<ISO8601>", limit_dollars: null, … }
seven_day:  { utilization: <0…100>, resets_at: "<ISO8601>", … }
seven_day_opus / seven_day_sonnet / <코드네임 창 20여 개> : 전부 null 일 수 있다
<달러 창>:  { utilization: <0…100>, resets_at: "<ISO8601>", limit_dollars: <정수> }
limits: [ { kind: "session",       percent: <0…100>, resets_at: …, is_active: <Bool> },
          { kind: "weekly_all",    percent: <0…100>, … },
          { kind: "weekly_scoped", percent: <0…100>, scope: { model: { id: null, display_name: "<모델명>" } } } ]
extra_usage: { is_enabled: <Bool>, monthly_limit: <정수>, utilization: <0…100>, … }
```

- `utilization` 은 **쓴 비율 0~100(Double)**. 뒤집지 않는다.
- ★ **`limits[].is_active` 를 표시 게이트로 쓰지 마라** — 퍼센트가 0 이 아니라 분명히 쓰는 중인 5시간 창이 `false` 로 왔다. 뜻이 미확정이다.
- ★ **모델별 주간 창은 레거시 키가 아니라 `limits[]` 의 `kind:"weekly_scoped"` 에 있다.** 레거시
  `seven_day_opus`/`seven_day_sonnet` 가 둘 다 null 인데 `limits[]` 엔 모델 하나가 살아 있었다.
  `scope.model.id` 는 null 이라 **`display_name` 으로만** 식별된다. 1차 UI 에 안 띄워도 **버리지는 마라.**
- ★ **`resets_at` 형식이 두 가지 섞여 온다** — 소수점 6자리가 있는 것과 없는 것. `ISO8601DateFormatter`
  한 벌로는 **반드시 한쪽을 nil 로 떨군다.** `[.withInternetDateTime, .withFractionalSeconds]` 와
  `[.withInternetDateTime]` 을 **순서대로 시도하는 헬퍼**로 파싱한다. 소수점은 요청 시각의 잔여 분수일 뿐이니
  표시에 초 이하를 쓰지 않는다.
- ★ **창 키 다수가 코드네임이고 언제든 바뀐다.** 고정 프로퍼티로 접으면 새 창이 조용히 사라진다 —
  `rawKey` 를 남기고 **배열**로 들고, 모르는 창은 `.other` 로 받되 UI 에는 띄우지 않는다.

**레이트리밋 ★★**: 같은 토큰 10회 연속 호출 → 1~5번 200, **6번째부터 429** + `retry-after: 300`.

- 폴링 **최소 5분, 기본 10분.** 사용자가 누르는 강제 갱신에도 **하한 5분**을 둔다.
- 429 면 `retry-after` 동안 **완전히 침묵**한다(30초마다 다시 노크하는 구현은 300초 금지창에서 틀린 동작이다).
- ★ **유닛테스트는 반드시 스텁으로.** 실호출 테스트가 5회를 넘기면 사용자 계정이 5분간 잠긴다.

**실패 모양**: 만료·위조 토큰 → 401 `authentication_error`. 헤더 누락 → 같은 401("x-api-key header is
required"). 둘 다 '로그인 필요'로 접는다.

## 2. OpenAI Codex

**자격증명**: `~/.codex/auth.json` → `tokens.{access_token, account_id, refresh_token}`, `last_refresh`.

- `access_token` 은 JWT, **수명 약 10일**(실측 iat→exp 10일). Claude 보다 여유롭다.
- JWT 클레임에 플랜 종류와 계정 식별자가 있다 → **네트워크 없이 플랜 라벨을 얻을 수 있고**, 파일에서
  `account_id` 를 못 읽어도 JWT 에서 꺼낼 수 있다.
- ★★ **이 파일에 절대 쓰지 마라.** 401 이 와도 우리가 refresh 해서 덮으면 실제 codex CLI 와 회전 경합이 나서
  **사용자가 로그아웃된다.** 갱신은 Codex CLI 몫이다.

**요청**

```
GET https://chatgpt.com/backend-api/wham/usage
Accept: application/json
Authorization: Bearer <tokens.access_token>
ChatGPT-Account-Id: <tokens.account_id>
```

- `ChatGPT-Account-Id` 는 개인 계정에선 **없어도 200** 이지만(실측), 여러 워크스페이스에 걸친 사용자를 위해
  **항상 싣는다.** 단 `account_id` 를 못 읽었다고 **호출을 포기하지는 마라.**

**응답 모양**

```
plan_type: "<플랜 라벨>"
rate_limit.primary_window:   { used_percent: <0…100>, limit_window_seconds: 18000,  reset_after_seconds: <초>, reset_at: <epoch 초> }
rate_limit.secondary_window: { used_percent: <0…100>, limit_window_seconds: 604800, reset_after_seconds: <초>, reset_at: <epoch 초> }
credits: { has_credits: <Bool>, unlimited: <Bool>, balance: "<문자열>" }
```

- `primary_window` = 5시간, `secondary_window` = 주간. `used_percent` 는 **쓴 비율**(뒤집지 않는다).
  `reset_at` 은 **epoch 초**. `balance` 는 숫자가 아니라 **문자열**이다.
- 두 창 모두 null 일 수 있다(플랜 없음·크레딧 사용자) — 그 창은 **없는 것으로** 다룬다.
- ★★ **`used_percent == 0` 이면 `reset_at` 은 가짜다.** 두 번 호출 사이에 684초 움직였고 그 값은 경과 시간과
  정확히 같았다 — 서버가 `now + limit_window_seconds` 를 넣어 준다. 판별식:
  `used_percent == 0 || reset_after_seconds == limit_window_seconds` → **`resetsAt` 을 nil 로 접고 리셋 시각을
  띄우지 않는다.** 안 그러면 0% 인데 리셋 시각이 분마다 바뀌는 UI 가 나온다.
- 소비 중인 주간 창의 `reset_at` 은 두 호출에서 **똑같았다** — 진짜 고정 경계다.

**레이트리밋**: 6회 연속 호출 전부 200. Claude 보다 훨씬 관대하다. 그래도 5분 주기로 보수적으로 둔다.

## 3. Google Antigravity

리밋 구조가 **모델별이 아니다.** **모델 그룹 2개 × 창 2개 = 4칸**이다.

| 그룹 | 포함 | 창 |
|---|---|---|
| `Gemini Models` | Gemini Flash, Gemini Pro | weekly 1 + 5h 1 |
| `Claude and GPT models` | Claude Opus, Claude Sonnet, GPT-OSS | weekly 1 + 5h 1 |

5시간 창은 전역 수요 평탄화용이고, 주간 창이 내 요금제 몫이다.

### 경로 A (1순위) — `agy` CLI print 모드

```
agy -p /usage --output-format json --log-file <임시경로> </dev/null
```

- ★ `</dev/null` **필수** — 없으면 stdin 대기로 영원히 멈춘다.
- ★ `--log-file <임시경로>` **필수** — 안 주면 실행마다 ~19KB 로그가 `~/.gemini/antigravity-cli/log/` 에 쌓인다.
- 비용 약 5.1초. **대화를 만들지 않고 토큰 0을 쓴다**(실측: 응답 `usage.total_tokens=0`, `conversations/` 에
  새 DB 없음). `CheckAntigravityUsage.swift` 의 "agy 를 더 돌리지 마라" 경고는 **새 대화 생성**(구글 쿼터 소모)을
  막는 것이라 `/usage` 에는 해당 없다 — 다만 주기를 짧게 잡지는 않는다.
- 실패 시 100% 를 **지어내지 않는다**(네트워크를 끊고 검증: `{"status":"ERROR",…}`). 다만 내부 캐시가 있어
  부분 실패 때 낡은 값이 나올 여지는 있다.

`command.data` 모양:

```json
{"groups":[{"name":"<그룹명>","buckets":[
  {"id":"<버킷>","window":"weekly","remaining_fraction":<0…1>,"reset_time":"<ISO8601>"},
  {"id":"<버킷>","window":"5h",    "remaining_fraction":<0…1>,"reset_time":"<ISO8601>"}]}]}
```

### 경로 B (2순위 폴백) — HTTP 직접

```
POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary
Authorization: Bearer <agy 토큰>
Content-Type: application/json
User-Agent: check/<버전> (antigravity-usage)
body: {}
```

응답: `groups[].buckets[]` 에 `{bucketId, displayName, window:"5h"|"weekly", remainingFraction, resetTime}`.
경로 A 보다 약 5배 빠르다.

- ★★ **User-Agent 게이트가 403 '라이선스 없음'으로 위장된다.** UA 가 없거나 `antigravity` 문자열을 담지 않으면
  `403 PERMISSION_DENIED / SUBSCRIPTION_REQUIRED / "You do not have a valid license…"` 가 온다. 계정 문제로
  오인하기 딱 좋다. 12회 UA 매트릭스로 확인: **대소문자 무관 부분문자열**이면 통과하므로 **우리 이름을 담은 UA 로
  통과한다 — 사칭할 필요가 없다.**
- 토큰은 키체인 `service="gemini", account="antigravity"`(값은 `go-keyring-base64:` + base64 JSON).
  `~/.gemini/oauth_creds.json` 은 **제미나이 CLI 쪽이라 스코프가 달라 403 이다** — 쓰지 않는다.
- ★ `remaining` 은 proto `oneof` 라 `remainingAmount` 로 올 수도 있고 `disabled:true` 버킷도 있다.
  `remainingFraction` 이 항상 있다고 가정하지 않는다.
- ★★ **토큰 갱신을 우리가 하지 않는다.** 갱신하려면 agy 바이너리에서 뽑은 구글 설치앱 client_id/secret 을 우리
  바이너리에 심어야 하는데, 그것은 타사 OAuth 클라이언트 자격증명을 공개 앱에 박는 짓이다. 저장된
  access_token 이 만료됐으면 **경로 A 로 떨어진다**(agy 가 스스로 갱신한다).

### ★★ 부호 — 안티그래비티만 반대다

두 경로 모두 `remaining_fraction` / `remainingFraction` 은 **남은 비율**이다(1.0 = 하나도 안 씀).
우리 모델은 "쓴 비율"로 통일하므로 경계에서 뒤집는다.

```
used = (1 - remainingFraction) * 100
```

Claude(`utilization`)·Codex(`used_percent`) 와 **부호가 반대다.** 한 군데라도 안 뒤집히면 0% 와 100% 가 바뀐다.
그래서 세 어댑터의 변환 지점에 단위 테스트를 **각각** 둔다 — 한 벌로 묶으면 뒤집기 누락이 가려진다.

### 미확인

실측 당시 모든 버킷이 100% 남은 상태라 **소비 중인 모습을 보지 못했다.** `0 < fraction < 1` 일 때의 값,
`remainingAmount`/`disabled` 가 실제로 오는지, 소비 시작 후 `reset_time` 이 고정 경계로 굳는지는 미확인이다.
100% 일 때는 `now + 창길이`로 따라 움직였다 — **Codex 와 같은 함정**이니 §2 와 같은 가드를 건다.

## 4. 신선도·하한 규칙 (맥이 꺼져 있을 때)

근거는 **단조성**이다: 한 창 안에서 사용률은 **올라가기만 한다.** 그래서 마지막으로 읽은 값은
**안전한 하한**이고, 리셋 경계를 지나면 하한이 0 으로 떨어진다. 이 두 줄이 아래 규칙 전부의 근거다.

- 리셋 전: `floor = 마지막 값`. 값이 오래됐으면 숫자에 "이상" 접미사를 붙인다.
- 리셋 후 **+120초 유예**: `floor = 0`, 캡션 `초기화됨`.
- ★ `usedPercent == 0` 행은 **리셋을 주장하지 않는다**(§2 의 가짜 `reset_at` 함정이 0% 행에만 걸린다).
- ★ 리셋 뒤 '다음 경계'를 창 길이로 **추정하지 마라** — Claude 주간은 고정 경계인데 Codex 주간은 계정별
  롤링 앵커다. 서버가 준 경계만 쓴다.
- 등급: `claimAge` ≤60초 fresh / ≤30분 recent / ≤1일 stale / 그 위 ancient.
- 두 출처가 있으면 **같은 창일 때만** 비교하고 **높은 쪽**을 믿는다. 장부가 하나이고 단조라서 성립한다 —
  폐기된 `max(로컬, 계정)` 증폭기와는 다른 상황이다(그쪽은 장부가 둘이라 중복 계상이었다).
- 나이 문구는 `FeedbackText.ageText(_:now:)` 를 **재사용한다**(새로 만들면 네 벌째가 된다).
- 출처(폰 직접 / 서버 경유)를 **화면에 쓰지 않는다** — 사용자에게 의미 없는 내부 사정이다.

## 5. 서버에 올라가는 것과 안 올라가는 것

| 올라간다 | 올라가지 않는다 |
|---|---|
| 제공자 구분(claude / codex / antigravity) | 액세스·리프레시 토큰, JWT 본문 |
| 창 종류(5시간 / 주간) | 그 도구의 계정 이메일·`account_id`·`user_id` |
| 사용률 퍼센트(0…100) | 계정 지문(그 식별자의 SHA-256 앞 16자) |
| 리셋 시각 | 크레딧 잔액 |
| 관측(읽은) 시각 | 자격증명 파일 경로·키체인 항목 이름 |
| 플랜 라벨(`max`·`plus` 원문, 32자까지) | 대화 내용·프롬프트·파일 목록 |
| 기기 이름(시스템 설정의 컴퓨터 이름, 64자까지) | 기기 모델명·일련번호·MAC 주소·Mac 사용자 계정 이름 |

- 공개 범위는 **본인만(RLS)**. **순위판·보드 RPC 에 절대 섞지 마라** — 한 번 섞이면 거두는 쪽이
  구버전 클라이언트를 끊는다.
- ★ 토큰 문자열이 `Logger`·에러 메시지·제보 자동 첨부·테스트 픽스처에 섞이지 않게 한다. 에러는 **분류만**
  남기고 본문은 버린다. Codex 응답에는 이메일·식별자가 들어 있으니 디버그 덤프에 남기지 않는다.
- 세 자격증명 전부 **읽기 전용**이다. 쓰면 사용자가 그 도구에서 로그아웃된다(§1·§2·§3).
- ★ **플랜 라벨은 올린다.** 폰 '나' 탭 카드(`MeAILimitsCard`)가 그 이름을 그대로 그린다. 사람을 가리키지 않고
  32자 상한이 있다(`AILimitPlanLabelContract` — 넘치면 **버린다**). 초안의 이 표는 그 칸을 '안 올라간다' 쪽에
  적어 **코드와 정반대**를 말했다(v0.3.45 P1 에서 고쳤다).
- ★ **기기 이름은 올린다**(v0.3.47). 업로드 행에 함께 싣는다 — 맥이 여러 대인 사람의 폰 카드·위젯이 "어느 맥의
  숫자인가"를 그 이름으로 말한다(그래서 접지 않는다 — 접으면 맥 A 에서 끈 제공자가 맥 B 값으로 되살아난다).
  값은 시스템 설정의 컴퓨터 이름이고(`scutil --get ComputerName` 과 같은 값 — 이 맥 실측: `Mac mini`),
  **사용자가 직접 붙인 말이 들어 있다고 보고 다뤄라**(예: `예성의 MacBook Pro`). 64자로 자르고 빈 값은
  올리지 않는다. 이름은 **겹칠 수 있다**(맥 미니 두 대) — 가르는 일은 맥이 아니라 폰이 한다.
  로그·에러 메시지·제보 자동 첨부에 이 문자열을 끼우지 마라(사람 이름이 들어 있을 수 있다).
- **메인 맥 선택**은 `ai_limits_prefs.main_device_id` 에 계정당 한 값으로 저장된다(기기 식별자 하나, 아직
  안 골랐으면 null). 위 표는 `ai_limits` 업로드 행의 칸만 세므로 이 값은 표에 줄이 없지만, 서버에 남는
  항목이라 **처리방침에는 함께 적는다**(공개 약속은 표 단위가 아니다).
- ★ **계정 지문은 만들기는 해도 올리지 않는다**(v0.3.45 P1). 생성(`AILimitFingerprint.make`)은 남아 있고 쓰임은
  업로드 게이트(`AILimitUploadLedger.fingerprint` — "무엇이 바뀌었나"를 재는 로컬 비교) 하나다. 그 문자열은
  **이 맥을 벗어나지 않는다**. 지운 근거는 "해시라서 괜찮다"가 아니라 **쓰임이 없다**는 것이다: 서버에서
  소비·표시·비교하는 호출부가 **0건**이고(폰은 일부러 안 받는다 — `MeAILimitsService`), 선언된 목적
  ("맥 두 대가 같은 계정을 보는지 판정")을 구현한 코드가 없었다. 서버 컬럼 `account_fingerprint` 는
  nullable 로 **그대로 두고**(검증된 칸이다) 아무도 채우지 않는다 — 안 보내면 null 로 남는다.
- 공개 약속의 정본은 `docs/privacy.md` 의 "AI 사용량 리밋을 읽는 방법" 절이다. 읽는 대상이나 올리는 항목이
  바뀌면 **코드보다 그 문서를 먼저** 고친다 — 그 문서는 공개 URL 로 앱·가입 화면·App Store 에 걸려 있다.
  ★ 그 대조에는 **그물이 있다**: `uploadedColumnsMatchTheTwoPublicDocuments` 가 업로드 행의 `CodingKeys` 와
  위 표의 두 칸, 그리고 처리방침의 "어디로 가는가" 열거를 맞춰 본다. 칸을 더하거나 빼면 **문서를 같이 고치지
  않는 한 빨개진다**(표는 왼쪽·오른쪽 칸을 갈라서 읽는다 — 한 줄을 통째로 `contains` 하면 '안 올라간다' 쪽
  글자가 '올라간다'를 만족시켜 이 결함이 그대로 산다). 기기 이름 칸을 더하는 쪽은 그 대조표에
  `기기 이름` 짝을 같이 넣어야 한다 — 두 문서가 쓰는 글자는 양쪽 다 **`기기 이름`** 이다.

## 6. 위젯까지의 홉

```
세 도구의 자격증명 (이 맥, 읽기 전용)
  └─ 맥 앱: 제공자 서버에 사용률 질의 (5분 하한 / 기본 10분)
       └─ 숫자만 아잉체크 서버로 (제공자·창·퍼센트·리셋·관측 시각, RLS 본인만)
            ├─ 맥: 팝오버 한 줄 요약 + 별도 창의 제공자 카드 (5시간 크게 + 주간 얇은 줄, 둘 다)
            └─ 폰 앱: '나' 탭 카드 (리밋 + 기존 토큰 사용량 함께)
                 └─ App Group 스냅샷
                      └─ 전용 "AI 리밋" 위젯 (small / medium / large)
```

- ★ **위젯은 네트워크를 쓰지 않는다** — App Group 스냅샷만 읽는다. 폰 앱이 갱신할 때 스냅샷을 같이 쓴다.
- ★ `WidgetSnapshot.version` 을 **올리지 말고 옵셔널 필드로만 더한다.** 올리면 구버전 위젯이 스냅샷을
  못 읽어 빈 위젯이 된다.
- **폰은 자격증명을 읽지 않고 폰 직접 로그인도 넣지 않는다** — 근거는 §7.
- 맥이 꺼져 있는 동안의 열화는 §4 규칙이 덮는다(마지막 값 = 하한).

## 7. 폰 직접 로그인을 넣지 않는 이유

- **Claude: 불가.** Anthropic 이 2026-02-19 약관으로 "소비자 OAuth 토큰을 Claude Code/Claude.ai 외에서
  쓰는 것"을 금지했고, 2026-01 서버단 집행 → 2026-04-04 실제 차단을 집행했다. 처벌 대상은 우리 앱이 아니라
  **사용자 본인의 구독 계정**이다.
- **Antigravity: 불가.** 구글은 타사 client_id 재사용과 앱 유형 위반을 정책으로 막고, device code 플로는
  필요한 스코프를 지원하지 않는다.
- **Codex: 기술적으로만 가능**(redirect 가 루프백이라 iOS 에서 받을 수 있다). 명시적 금지는 없으나 보장도 없다.

→ 셋 중 하나만 되는데 그 하나도 회색이라 **서버 경유 단일 경로**로 간다. 이 결론이 뒤집히려면 약관이 바뀌어야
하니, 폰 직접 로그인을 다시 꺼내기 전에 위 날짜의 약관을 먼저 확인하라.

## 8. 실패 모드별 표시 (확정)

| 상황 | 표시 |
|---|---|
| 미설치(키체인 항목·파일 없음) | 그 제공자를 **목록에서 숨김** |
| 로그인 안 함(항목은 있는데 토큰이 비었다) | 숨김 |
| 토큰 만료(`expiresAt` 과거 / JWT `exp` 과거 / 401) | `클로드 코드를 한 번 실행해 주세요` · `코덱스를 한 번 실행해 주세요` |
| 네트워크 없음 | 직전 값 **그대로 두고** 나이 캡션만 낡게. 빨간 문구 금지 |
| 429 | 직전 값 유지 + `잠시 뒤 다시`, `retry-after` 까지 재호출 금지 |
| 플랜 없음(크레딧 사용자) | `구독 리밋 없음` 으로 접고 토큰 사용량만 보여 준다 |

설정 토글·알림은 **없다**(자동 감지, 미연동은 숨김).

## 9. 제공자 아이콘

세 마크는 `viewBox="0 0 100 100"` 의 **단일 path, 단색 실루엣**이라 SwiftUI `Path` 로 그린다.
출처는 CodexBar(by Peter Steinberger, **MIT License**, github.com/steipete/CodexBar) 의
`ProviderIcon-{claude,codex,antigravity}.svg` 다 — **MIT 는 재배포본에 저작권·라이선스 표기를 유지할 것을
요구한다.** 그래서 출처 한 줄을 코드에 **남긴다**(`Sources/CheckCore/AIProviderLogo.swift` 머리말). 지우면 위반이다.

이미지 파일로 가면 안 되는 **구조적 이유**: 이 저장소에는 맥·폰·위젯 세 타깃이 공유하는 리소스 경로가 **없다**
(CheckCore 리소스 선언 0건, 맥은 CheckMobileShared 를 링크하지 않는다). 이미지로 하면 캐릭터 아트처럼
복제 + 픽셀 동치 테스트를 한 벌 더 만들어야 하고, `ios/App/Assets.xcassets` 는 **위젯 타깃이 못 본다.**
벡터 path 는 한 소스로 세 타깃이 쓰고 어떤 크기에서도 선명하다.

색: claude `#D97757` / codex `#0D0D0D` / antigravity 구글 3색 `#4285F4`→`#34A853`→`#FBBC04`.
★ **제공자를 색으로만 구분하지 마라** — 위젯 틴트 모드가 색을 버린다. 이름 글자 + 실루엣으로 가른다.
