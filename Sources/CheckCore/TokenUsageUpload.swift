import Foundation

// 토큰 사용량 업로드의 본문 모양과 일별 계산(순수). 맥 앱과 원격 기계용 스캐너(aing-scan)가 **같은 파일**을 쓴다 —
// 스캐너 패키지는 이 파일을 심볼릭 링크로 함께 컴파일한다(aing-scan/Sources/CheckTokenScan). 그래서 이 파일은
// Foundation 과 토큰 스캐너 파일(CheckTokenUsage·Diagnostics·CodexAccountUsage·AntigravityUsage)만 본다.
// 원래 자리: 본문 모양은 SupabaseWorkModels.swift, 일별 계산은 WorkTimerStoreSync.swift(2026-11-07 그대로 옮김).

/// token_usage_device_monthly upsert 본문(snake_case 인코딩). D1 의 TokenUsageMonthly 에서 서비스가 값을 옮겨 담는다.
package struct TokenUsageUpsertRequest: Encodable {
    package let userId: String
    package let month: String
    /// 이 기기의 안정 식별자. 원장 키가 (user_id, month, device_id) 라 맥 2대가 서로의 값을 덮어쓰지 않고
    /// 각자 행을 유지하며, 월 총량 합산은 서버 보드(token_usage_board)가 user_id 로 묶어 수행한다.
    package let deviceId: String
    package let claudeInput: Int
    package let claudeOutput: Int
    package let claudeCacheRead: Int
    package let claudeCacheCreation: Int
    package let codexInput: Int
    package let codexOutput: Int
    package let total: Int
    // 오늘(KST) 증가량과 귀속 날짜 — 서버 행에 함께 저장돼 순위판 "오늘 +N" 에 쓰인다.
    package let todayTotal: Int
    package let todayDate: String
    /// Codex 캐시 히트 합(입력의 부분집합, total 에 안 들어감). **항상 실린다**(Int) — 매 업로드가 최신 로컬 집계이므로 덮어써야
    /// 맞다. ★ 이 키 때문에 20260903160000 마이그레이션이 **클라 배포 전에** 적용돼야 한다(컬럼이 없으면 PostgREST 가 400).
    package let codexCacheRead: Int

    // ── Codex 계정 집계(codex_account_*, 옵셔널 — nil 이면 키 생략 → 서버 값 보존) ──
    //
    // 계정 프로브가 이번 실행에서 아직 안 돌았거나 스냅샷이 없으면 nil 로 두어 서버의 마지막 계정값을 지우지 않는다.
    // 값이 있을 때는 다섯을 **함께** 싣는다(월합·누적·시각·마지막 반영일·상태) — 한쪽만 갱신되면 시각과 값이 어긋난다.
    // 상태(status)만은 스냅샷 없이도 실을 수 있다(예: 미로그인 3) — 서버 진단이 "왜 계정값이 없나"를 가른다.
    package var codexAccountMonth: Int?
    package var codexAccountLifetime: Int?
    /// ISO8601(서비스 dateFormatter). 계정 스냅샷을 받은 시각.
    package var codexAccountAt: String?
    /// 계정 버킷의 마지막 UTC 날짜 'YYYY-MM-DD'(이 달 안에서). 반영 지연을 서버에서 볼 수 있게.
    package var codexAccountLastDay: String?
    /// CodexAccountProbeStatus.rawValue.
    package var codexAccountStatus: Int?

    // ── Codex 집계 진단(codex_diag_*, 전부 Int · "<빌드>:<KST 날짜>" 도장당 1회만 값이 실린다) ──
    //
    // **옵셔널인 것이 이 설계의 전부다.** 합성 Encodable 은 Optional 프로퍼티를 encodeIfPresent 로 내보내므로
    // nil 이면 JSON 본문에 **키 자체가 없고**, PostgREST 의 upsert(INSERT … ON CONFLICT DO UPDATE)는
    // 본문에 온 컬럼만 갱신한다 — 즉 서버에 이미 쌓인 진단값이 그대로 보존된다.
    // 옵셔널이 아니면(Int 로 두면) 30초마다 도는 이 업로드가 매번 0 을 실어 보내 직전 진단값을 덮어써,
    // 기능 전체가 무의미해진다. 실측으로 확인했다 — diagnostics 가 nil 인 본문에는 codex_diag_ 로 시작하는
    // 키가 하나도 나오지 않는다(아래 init 주석의 인코딩 결과 참조).
    //
    // 중첩 객체가 아니라 19개를 **펼쳐** 담는 이유: 서버가 스칼라 컬럼 19개라 jsonb 하나로는 upsert 되지 않는다.
    // 전 필드가 Int 인 것은 프라이버시의 구조적 보증이다(CodexUsageDiagnostics 주석) — 문자열을 더하지 마라.
    package var codexDiagFilesTotal: Int?
    package var codexDiagFilesMonth: Int?
    package var codexDiagEventsMonth: Int?
    package var codexDiagMaxDelta: Int?
    package var codexDiagCarryFiles: Int?
    package var codexDiagCarryTotal: Int?
    package var codexDiagDupEvents: Int?
    package var codexDiagDupTokens: Int?
    package var codexDiagFinalSum: Int?
    package var codexDiagDedupTotal: Int?
    package var codexDiagDrops: Int?
    package var codexDiagTopFile: Int?
    package var codexDiagBuild: Int?

    // ── 2차 진단(델타 분포): 단일 이벤트 델타 10.7억의 정체를 가르는 5개 ──
    //
    // 1차(위 13개)로 resume 카운터 이월은 확정됐지만 `codexDiagMaxDelta` 하나가 총합을 좌우하는 사례가 남았다.
    // 그 델타가 (a) 앱을 오래 꺼 둔 사이 쌓인 정상 누적인지 (b) 산식이 만든 유령인지는 **분포와 시간 간격**으로만
    // 갈린다 — 그래서 큰 델타의 개수·합(bigDelta*)과 그 앞뒤 공백(gap 초)을 함께 싣는다. legacyTotal 은
    // 이월 수정 **전** 옛 산식의 총합이라, 같은 행에서 신·구 산식을 나란히 놓고 차이를 빼 볼 수 있게 한다.
    //
    // 위 13개와 완전히 같은 규약이다 — **옵셔널이 핵심**(nil = 키 생략 = 서버 값 보존), 전부 Int(문자열 금지),
    // 새 필드는 마지막에. 이 5개도 "<빌드>:<KST 날짜>" 도장당 1회만 값이 실린다(도장이 월→일 단위가 되어 하루 1회).
    package var codexDiagLegacyTotal: Int?
    package var codexDiagBigDeltaCount: Int?
    package var codexDiagBigDeltaTotal: Int?
    package var codexDiagMaxDeltaGapS: Int?
    package var codexDiagBigGapMedianS: Int?

    // ── 3차: 진단을 **잰 그 순간의 Codex 총합** 스냅샷(codex_diag_input_at_scan) ──
    //
    // 위 18개와 `codex_input` 은 **서로 다른 시각의 값**이었다. `codex_input` 은 업로드마다(30초) 갱신되는데
    // 진단은 도장당 1회만 계산되므로, 진단을 올린 뒤 Codex 를 더 쓴 사람은 codex_input 만 자라고 진단은 얼어 있다.
    // 그래서 `legacy_total − codex_input` 같은 뺄셈이 진단 이후의 사용량까지 섞어 **음수**를 낸다
    // (실사고: -4,297,774,877 — 진단 이후 43억을 더 쓴 것이 차이에 섞였다).
    // 이 한 필드가 그 뺄셈에 쓸 **같은 시각의 분모**를 준다: 진단이 실린 그 업로드의 Codex 총합.
    //
    // 규약은 위 18개와 완전히 같다 — **옵셔널이 핵심**이다. nil 이면 키가 빠져 PostgREST 가 이 컬럼을 건드리지 않으므로,
    // 진단이 안 실리는 평상시 업로드(30초마다)가 이 스냅샷을 덮지 않는다. 옵셔널이 아니면 매 업로드마다 갱신돼
    // codex_input 과 똑같아지고 이 필드의 존재 이유가 통째로 사라진다.
    //
    // 값의 출처는 아래 생성자다 — 인자로 받지 않고 **같은 본문에 실리는 codexInput+codexOutput 에서 파생**시킨다.
    // 호출측이 따로 넘기게 두면 행에 실린 Codex 합과 스냅샷이 어긋날 여지가 생기는데, 그 어긋남이 정확히
    // 이 필드가 없애려던 결함이다. 파생이면 구조적으로 불가능하다.
    package var codexDiagInputAtScan: Int?

    // ── 4차(v0.2.43): 포크 복사 구간 계수 2개(codex_diag_fork_files · codex_diag_fork_tokens, 20260906120000 컬럼) ──
    //
    // Codex 포크 파일의 복사 구간(CodexForkRule)이 몇 파일에 걸렸고, 옛 산식이라면 그 달에 얼마를 더했을지를 같은 도장 규약으로
    // 싣는다. 이 둘이 있어야 "이 사람의 과다계상이 포크 복사본에서 온 것인가"를 서버에서 로그 없이 가른다.
    // 규약은 위 19개와 같다 — **옵셔널이 핵심**(nil = 키 생략 = 서버 값 보존), Int 뿐(문자열 금지), 새 필드는 마지막에.
    package var codexDiagForkFiles: Int?
    package var codexDiagForkTokens: Int?

    // ── 안티그래비티 네 컬럼(antigravity_*, v0.3.12 · 20260911120000) ──────────────────────
    //
    // **옵셔널이고, 넷이 함께 실리거나 함께 빠진다**(codex_account_* 다섯과 같은 규약). 두 가지를 동시에 산다:
    //  ① 안 쓰는 사람(현재 절대다수)의 본문에는 키가 **하나도** 없다 → 서버에 컬럼이 아직 없어도(배포 순서가 어긋나도)
    //     그 사람의 월간 업로드는 종전과 바이트 단위로 같아 400 이 날 일이 없다. 즉 이 기능이 남의 사용량을 멈추지 못한다.
    //  ② 쓰는 사람의 값이 0 으로 떨어지는 상황(대화 디렉터리를 지웠다·읽기 실패)에서도 서버의 마지막 값이 보존된다 —
    //     PostgREST 의 merge-duplicates 는 본문에 온 컬럼만 SET 하므로, 키를 빼면 그 달 누적이 0 으로 밀리지 않는다.
    // ★ `total` 에는 절대 더하지 마라(TokenUsageMonthly.total 주석 · 서버 컬럼 주석). 순위판 총합은 서버가 이 넷에서 직접 더한다.
    package var antigravityInput: Int?
    package var antigravityOutput: Int?
    package var antigravityThinking: Int?
    package var antigravityCacheRead: Int?
}

extension TokenUsageUpsertRequest {
    /// 진단 스냅샷을 21개 스칼라로 펼쳐 담는 생성자(19 + v0.2.43 포크 계수 2). **diagnostics 가 nil 이면 21개 필드가 전부 nil 로 남아**
    /// 인코딩 결과에서 codex_diag_* 키가 통째로 사라진다(= 서버의 기존 진단값 보존).
    ///
    /// 19번째(codexDiagInputAtScan)만 diagnostics 안이 아니라 **이 생성자가 받은 codexInput+codexOutput 에서 파생**된다
    /// (= 같은 본문의 codex_input+codex_output, 즉 usage.codexTotal). 진단 스캐너는 앱의 월간 집계를 모르므로 그쪽에
    /// 넣을 수 없고, 넣더라도 "행에 실린 값"과 "스냅샷"이 다른 경로로 오는 순간 어긋날 수 있다. 여기서 파생시키면
    /// 두 값이 같은 한 줄에서 나와 구조적으로 일치한다. diagnostics 가 nil 이면 이 필드도 nil 이다(키 생략).
    ///
    /// nil 로 인코딩한 실물(keyEncodingStrategy = .convertToSnakeCase):
    /// {"user_id":"…","month":"2026-08","device_id":"…","claude_input":11,"claude_output":22,
    ///  "claude_cache_read":33,"claude_cache_creation":44,"codex_input":55,"codex_output":66,
    ///  "total":231,"today_total":77,"today_date":"2026-08-16"}
    /// — codex_diag_ 키 0개. (본문 이전과 완전히 동일하므로 구서버·기존 테스트도 그대로 통과한다.)
    package init(
        userId: String,
        month: String,
        deviceId: String,
        claudeInput: Int,
        claudeOutput: Int,
        claudeCacheRead: Int,
        claudeCacheCreation: Int,
        codexInput: Int,
        codexOutput: Int,
        total: Int,
        todayTotal: Int,
        todayDate: String,
        codexCacheRead: Int = 0,
        account: TokenUsageAccountFields? = nil,
        antigravity: TokenUsageAntigravityFields? = nil,
        diagnostics: CodexUsageDiagnostics?
    ) {
        self.init(
            userId: userId,
            month: month,
            deviceId: deviceId,
            claudeInput: claudeInput,
            claudeOutput: claudeOutput,
            claudeCacheRead: claudeCacheRead,
            claudeCacheCreation: claudeCacheCreation,
            codexInput: codexInput,
            codexOutput: codexOutput,
            total: total,
            todayTotal: todayTotal,
            todayDate: todayDate,
            codexCacheRead: codexCacheRead,
            codexAccountMonth: account?.month,
            codexAccountLifetime: account?.lifetime,
            codexAccountAt: account?.fetchedAt,
            codexAccountLastDay: account?.lastDay,
            codexAccountStatus: account?.status,
            codexDiagFilesTotal: diagnostics?.filesTotal,
            codexDiagFilesMonth: diagnostics?.filesMonth,
            codexDiagEventsMonth: diagnostics?.eventsMonth,
            codexDiagMaxDelta: diagnostics?.maxDelta,
            codexDiagCarryFiles: diagnostics?.carryFiles,
            codexDiagCarryTotal: diagnostics?.carryTotal,
            codexDiagDupEvents: diagnostics?.dupEvents,
            codexDiagDupTokens: diagnostics?.dupTokens,
            codexDiagFinalSum: diagnostics?.finalSum,
            codexDiagDedupTotal: diagnostics?.dedupTotal,
            codexDiagDrops: diagnostics?.drops,
            codexDiagTopFile: diagnostics?.topFile,
            codexDiagBuild: diagnostics?.appBuild,
            codexDiagLegacyTotal: diagnostics?.legacyTotal,
            codexDiagBigDeltaCount: diagnostics?.bigDeltaCount,
            codexDiagBigDeltaTotal: diagnostics?.bigDeltaTotal,
            codexDiagMaxDeltaGapS: diagnostics?.maxDeltaGapSeconds,
            codexDiagBigGapMedianS: diagnostics?.bigGapMedianSeconds,
            // 진단이 실릴 때만 값이 생긴다(nil 이면 키 생략 → 서버 스냅샷 보존). 값은 이 본문의 Codex 총합 그 자체.
            // codexTotal 을 쓰는 이유: 앱은 Codex 델타를 입출력 구분 없이 전액 codexInput 에 담고 codexOutput 은 항상 0 이라
            // 오늘은 codexInput 과 같은 값이지만, 훗날 출력을 쪼개 담더라도 "그 업로드의 Codex 총합"이라는 뜻이 유지된다.
            codexDiagInputAtScan: diagnostics.map { _ in codexInput + codexOutput },
            codexDiagForkFiles: diagnostics?.forkFiles,
            codexDiagForkTokens: diagnostics?.forkCopyTokens,
            // 넷이 함께 — antigravity 가 nil 이면 네 키가 통째로 빠진다(위 필드 주석의 ①②).
            antigravityInput: antigravity?.input,
            antigravityOutput: antigravity?.output,
            antigravityThinking: antigravity?.thinking,
            antigravityCacheRead: antigravity?.cacheRead
        )
    }
}

/// 업로드 본문에 실을 안티그래비티 네 값(v0.3.12). 서비스가 TokenUsageMonthly 에서 만든다
/// (`SupabaseWorkService.upsertTokenUsage` — 합이 0 이면 **nil**, 그러면 본문에서 네 키가 통째로 빠진다).
/// 넷을 한 타입으로 묶어 두는 것 자체가 안전장치다: 따로 넘기면 "셋만 실린 본문"이 만들어질 수 있고,
/// 그러면 서버의 네 컬럼 합이 이 기기의 실제 합과 달라진다.
package struct TokenUsageAntigravityFields: Equatable, Sendable {
    package var input: Int
    package var output: Int
    package var thinking: Int
    package var cacheRead: Int

    /// 월 집계에서. 합이 0 이면 nil — "안 쓰는 사람의 본문엔 키가 없다" 규약을 **한 자리에서** 정한다.
    package init?(usage: TokenUsageMonthly) {
        guard usage.antigravityTotal > 0 else { return nil }
        input = usage.antigravityInput
        output = usage.antigravityOutput
        thinking = usage.antigravityThinking
        cacheRead = usage.antigravityCacheRead
    }
}

/// 업로드 본문에 실을 Codex 계정 집계 다섯 값. 서비스가 CodexAccountUsage 스냅샷+상태에서 만든다(SupabaseWorkService.upsertTokenUsage).
/// 스냅샷 없이 상태만 있으면(미로그인·미설치) month/lifetime/fetchedAt/lastDay 는 nil 로 두고 status 만 싣는다.
package struct TokenUsageAccountFields: Equatable, Sendable {
    package var month: Int?
    package var lifetime: Int?
    package var fetchedAt: String?
    package var lastDay: String?
    package var status: Int?
}

/// token_usage_device_monthly **스캐너 하트비트** 본문. 위 TokenUsageUpsertRequest 와 같은 표·같은 충돌키
/// ((user_id, month, device_id))를 쓰지만 **토큰 컬럼을 하나도 담지 않는다** — 그것이 이 타입의 존재 이유다.
///
/// TokenUsageUpsertRequest 를 재사용하지 않는 이유: 그 타입은 토큰 컬럼(claude_*/codex_*/total/today_*)을
/// 갖고 있어 본문에 그대로 실린다. 하트비트는 합계가 0 일 때도 나가야 하므로 그 값들은 0 으로 실리고,
/// PostgREST 의 upsert 는 본문에 온 컬럼을 그대로 SET 하므로 **그 기기의 이번 달 누적치가 통째로 0 으로 밀린다.**
/// 반대로 본문에 **없는** 컬럼은 갱신하지 않는다(이 저장소가 created_at 을 보존하는 데 이미 기대는 성질 —
/// 20260726010000_token_usage_device.sql:57). 그래서 필드를 이 다섯 개로 묶어 두는 것 자체가 안전장치다.
/// 토큰 컬럼을 여기에 더하지 마라.
///
/// 인코더는 keyEncodingStrategy = .convertToSnakeCase 라(SupabaseWorkService.init) 카멜로 적으면
/// user_id·month·device_id·last_scan_at·scan_files 로 나간다 — CodingKeys 를 따로 두지 않는 이유다.
package struct TokenScanHeartbeatRequest: Encodable {
    package let userId: String
    package let month: String
    package let deviceId: String
    /// 스캔을 마친 시각(ISO8601 문자열). 다른 timestamptz 요청과 같이 서비스의 dateFormatter 로 찍어 넣는다.
    /// 이 값이 서버에 남아야 "총합 0" 이 미사용인지 스캐너 고장인지 갈린다 — 행 자체가 없던 시절엔 둘이 같아 보였다.
    package let lastScanAt: String
    /// 그 스캔이 stat 한 파일 수(claude+codex). 0 이면 "스캔은 돌았는데 볼 파일이 없었다"까지 구분된다.
    package let scanFiles: Int

    // 원격 스캐너(다른 모듈)도 같은 본문을 만든다 — package struct 의 합성 init 은 모듈 밖에서 안 보여 명시한다.
    package init(userId: String, month: String, deviceId: String, lastScanAt: String, scanFiles: Int) {
        self.userId = userId
        self.month = month
        self.deviceId = deviceId
        self.lastScanAt = lastScanAt
        self.scanFiles = scanFiles
    }
}

/// token_usage_device_daily upsert 본문 **한 줄**(배열로 실린다, snake_case 인코딩). 하루(KST)·기기당 한 행이고
/// 충돌키는 (user_id, day, device_id) 다. 서비스 upsertTokenUsageDaily 가 `[TokenUsageDailyUpsertRow]` 를 그대로 보낸다.
///
/// codex_account 는 **옵셔널이 핵심**이다(월 표의 codex_account_*·codex_diag_* 와 같은 규약): 합성 Encodable 은 nil 을
/// encodeIfPresent 로 내보내 **키 자체가 빠지고**, PostgREST 의 merge-duplicates upsert 는 본문에 온 컬럼만 SET 한다.
/// 계정 버킷(UTC 일자)이 그 날짜에 없는 기기가 0 을 실으면 다른 기기가 앞서 올린 계정값을 0 으로 밀어 버린다 — nil 이면
/// 서버 값이 보존된다. 같은 규약이 v0.2.43 부터 네 값 전부에 적용된다(TokenUsageDailyValue 주석 — 각 로컬 맵이 **덮는 날에만** 값이 있다):
/// - claude_total: 이 기기의 Claude 로그가 온전한 날(TokenUsageMonthly.claudeCompleteFrom 이후)만. 그 앞은 키 생략.
/// - codex_total(KST 하루): 현재 KST 월의 날만(KST 맵은 현재 월뿐). 창 안 지난달 날은 키 생략 — 0 을 실으면 그 달 행의 Codex 가 지워진다.
/// - codex_utc_total(UTC 하루 = KST 오전 9시 ~ 다음날 9시, 계정 버킷과 같은 축): UTC 보존 하한(전월 마지막 UTC 일) 이후만. 그 앞은 키 생략.
///   서버 산식(20260906120000)의 꼬리·마지막 날 차분은 이 값을 우선 쓴다(`coalesce(codex_utc_total, codex_total)`).
/// 키 집합이 다른 행은 서비스가 묶음을 갈라 보낸다(upsertTokenUsageDaily).
package struct TokenUsageDailyUpsertRow: Encodable, Equatable, Sendable {
    package let userId: String
    /// 'YYYY-MM-DD' — claude_total/codex_total 은 이 날짜를 KST 하루로, codex_utc_total/codex_account 는 UTC 하루로 읽는다(서버 컬럼 주석).
    package let day: String
    package let deviceId: String
    package var claudeTotal: Int?
    package var codexTotal: Int?
    package var codexUtcTotal: Int? = nil
    package var codexAccount: Int?
    /// 그 날(KST) 안티그래비티 합(v0.3.12). 다른 넷과 같은 옵셔널 규약 — 모르는 날은 키를 빼 서버 값을 보존한다.
    /// 서버는 이 컬럼을 **읽지 않는다**(순위판은 월 표의 네 컬럼만 본다) — 잔디를 위한 저장 전용이다.
    package var antigravityTotal: Int? = nil

    /// B3: 모듈 밖(맥 타깃)에서 쓰는 memberwise init — 합성 init 은 internal 이라 명시했다(모양 동일).
    package init(userId: String, day: String, deviceId: String, claudeTotal: Int? = nil, codexTotal: Int? = nil, codexUtcTotal: Int? = nil, codexAccount: Int? = nil, antigravityTotal: Int? = nil) {
        self.userId = userId
        self.day = day
        self.deviceId = deviceId
        self.claudeTotal = claudeTotal
        self.codexTotal = codexTotal
        self.codexUtcTotal = codexUtcTotal
        self.codexAccount = codexAccount
        self.antigravityTotal = antigravityTotal
    }
}

// MARK: - 월 본문 한 자리(맥 앱 서비스 · 스캐너 공용)

extension TokenUsageUpsertRequest {
    /// token_usage_device_monthly 본문을 만드는 **유일한** 자리. 맥 앱(SupabaseWorkService.upsertTokenUsage)과
    /// 원격 기계 스캐너(aing-scan)가 같은 함수를 불러, 같은 스캔 결과면 키 집합·값이 한 글자도 다르지 않다.
    /// formatDate 는 서비스의 ISO8601 포맷터(계정 스냅샷 시각) — 호출측 것을 그대로 받는다.
    package static func monthly(
        userID: String,
        usage: TokenUsageMonthly,
        deviceID: String,
        account: CodexAccountUsage?,
        accountStatus: CodexAccountProbeStatus?,
        diagnostics: CodexUsageDiagnostics?,
        formatDate: (Date) -> String
    ) -> TokenUsageUpsertRequest {
        // v0.2.43(코드 리뷰 P1): 미로그인(3)이면 스냅샷 네 값을 **싣지 않는다**. 스토어는 로그아웃·API 키 전환 뒤에도 마지막 스냅샷을
        // 계속 들고 있는데(CheckCodexAccountUsage 는 status 만 바꾼다), 그것을 status 3 과 함께 실으면 서버가 "스냅샷 있는 미로그인 기기"
        // 라는 어긋난 상태를 본다(구 산식은 그 기기의 반영일 로컬을 계정 위에 얹어 최대 2배 이중 계상). 키를 빼면 서버의 마지막 계정값은
        // 보존되고, 산식 쪽은 서버 가드(스냅샷 없는 status 3 만 계정 밖)가 막는다 — 클라 생략은 그 가드의 짝이지 대체가 아니다.
        let snapshot: CodexAccountUsage? = (accountStatus == .notLoggedIn) ? nil : account
        let accountFields: TokenUsageAccountFields? = (account == nil && accountStatus == nil) ? nil : TokenUsageAccountFields(
            month: snapshot.map { $0.monthTotal(usage.month) },
            lifetime: snapshot?.lifetimeTokens,
            fetchedAt: snapshot.map { formatDate($0.fetchedAt) },
            lastDay: snapshot?.latestBucketDate(in: usage.month),
            status: accountStatus?.rawValue
        )
        return TokenUsageUpsertRequest(
            userId: userID,
            month: usage.month,
            deviceId: deviceID,
            claudeInput: usage.claudeInput,
            claudeOutput: usage.claudeOutput,
            claudeCacheRead: usage.claudeCacheRead,
            claudeCacheCreation: usage.claudeCacheCreation,
            codexInput: usage.codexInput,
            codexOutput: usage.codexOutput,
            total: usage.total,
            todayTotal: usage.todayTotal,
            todayDate: usage.todayDate,
            codexCacheRead: usage.codexCacheRead,
            account: accountFields,
            // v0.3.12: 합이 0 이면 nil → 본문에서 antigravity_* 네 키가 통째로 빠진다(안 쓰는 사람의 본문은 종전과 동일).
            // 요청은 **늘리지 않는다** — 같은 upsert 한 번에 얹는다(컬럼이 없는 서버면 400 이고, 호출측이 조용히 삼켜 다음 기회에 재시도한다).
            antigravity: TokenUsageAntigravityFields(usage: usage),
            diagnostics: diagnostics
        )
    }
}

// MARK: - 일별 토큰 업로드의 순수 계산 (v0.2.41 토큰 잔디)

/// 일별 업로드의 변경 게이트 단위: 하루치 (claude, codex(KST), codexUTC, codexAccount). 값이 하나라도 다르면 '바뀐 날'이다.
/// **nil 은 "이 기기가 그 날의 그 값을 모른다" = 본문에서 키가 빠진다**(TokenUsageDailyUpsertRow 주석) — 0 을 실으면 서버의 완전값을
/// 부분값/0 으로 덮는다. 각 값이 nil 인 조건은 그 값의 로컬 맵이 **덮는 날짜 범위**다:
/// - claude: 이 기기의 Claude 로그가 온전한 날(TokenUsageMonthly.claudeCompleteFrom 이후)에만 값. 그 앞은 nil(v0.2.43).
/// - codex(KST): 현재 KST 월 안의 날에만 값 — KST 맵(codexDaily)은 현재 월뿐이다. 창(12주) 안이라도 지난달 날은 nil(v0.2.43 UTC 축 작업에서
///   잡은 구멍: 창이 12주로 넓어진 뒤 지난달 날에 0 을 실으면 그 달 행의 Codex 가 지워진다).
/// - codexUTC: **이 빌드의 스캔 산출물**(windowStart 가 채워진 스냅샷)이고, UTC 보존 하한(전월 마지막 UTC 일, `utcRetainFromKey`)
///   **다음 날 이후**의 날에만 값. 그 앞은 nil. 두 예외의 이유(코드 리뷰 P2 두 건):
///   · 첫 스캔 전 복원된 옛 스냅샷(v0.2.42, windowStart "")은 UTC 맵이 비어 있다 — 0 을 실으면 서버 `coalesce(codex_utc_total, codex_total)`
///     이 0 이 되어 그 사용자의 꼬리가 다음 업로드까지 0 이다. 모르는 값은 키를 뺀다.
///   · 전월 마지막 UTC 일(하한 당일, 예: 7월의 "2026-06-30")의 UTC 합은 이번 달 첫 9시간 몫만 담긴 **부분값**이다(전월 mtime 파일은
///     이번 달 프리필터 밖이라 파싱되지 않는다). 그 날은 서버 산식에서 반영일이라 계정 버킷이 쓰이므로 싣지 않아도 손실이 없다.
///     (스캐너가 그 키를 **보존**하는 것은 별개의 규칙이다 — 월초 마지막 날 차분 재료이지 업로드 재료가 아니다.)
/// - codexAccount: 그 날짜의 계정 버킷이 있을 때만.
package struct TokenUsageDailyValue: Equatable, Sendable {
    package var claude: Int?
    package var codex: Int?
    package var codexUTC: Int? = nil
    package var codexAccount: Int?
    /// 그 날(KST)의 안티그래비티 합(v0.3.12). **그 날 로컬 맵에 값이 있을 때만** 채운다 — 현재 월 밖이라 모르는 날도,
    /// 안티그래비티를 아예 안 쓰는 사람의 날도 nil 이다(values 주석의 ①②: 컬럼 없는 서버에서 전원 400 · 서버 값 0 으로 밀림).
    package var antigravity: Int? = nil

    // 모듈 밖(맥 앱 테스트)이 memberwise 모양 그대로 만들 수 있게 명시한다 — package struct 의 합성 init 은 모듈 안에서만 보인다.
    package init(claude: Int?, codex: Int?, codexUTC: Int? = nil, codexAccount: Int?, antigravity: Int? = nil) {
        self.claude = claude
        self.codex = codex
        self.codexUTC = codexUTC
        self.codexAccount = codexAccount
        self.antigravity = antigravity
    }
}

/// 월간 사용량 + 계정 스냅샷에서 일별 표에 올릴 값을 고르는 순수 규칙(스토어·테스트 공용).
package enum TokenUsageDailyUpload {
    /// 창 안의 날짜별 값(v0.2.43 — 현재 월이 아니라 **12주 잔디 창** `usage.windowStartDay` 이후). 키 = (claudeDaily ∪ codexDaily ∪ 계정 버킷) 날짜.
    /// - Claude 일별 맵은 창 시작부터의 날만 담고(버킷이 창에서 시작한다), Codex 일별 맵은 현재 월뿐이다. 계정 버킷(~70일)은 창 앞
    ///   날짜도 들 수 있는데 그 날들은 **보내지 않는다**(창 필터) — 창 앞은 엔트리 보관 하한(창 시작 − 48시간) 탓에 부분값일 수 있고,
    ///   서버의 온전한 값을 부분값으로 덮으면 안 된다. 옛 스냅샷(windowStart 빈 문자열)은 월 1일이 창 시작이라 옛 월 접두어 규칙과 같다.
    /// - 첫 업로드는 최대 84일 × 1행(배열 upsert 한 번, 서버 max_rows 1000 이내)이고 그 뒤로는 changedDays 게이트가 바뀐 날만 고른다 —
    ///   그 행들이 서버에 남아 잔디가 v0.2.41 이전 기록(예: 2026-08 가입자의 8월)을 되찾는다.
    /// - 계정 버킷 날짜도 키에 넣는다(스펙의 claudeDaily ∪ codexDaily 보다 넓다): `.zst` 만 남은 채 설치한 사람의 Codex 사용은
    ///   로컬 맵에 없고 계정 버킷에만 있다 — 월간 경로가 "로컬 0 + 계정 > 0" 을 올리는 것과 같은 이유로 일별도 그 날을 남겨야
    ///   다른 맥과 서버 잔디에 그 날이 보인다. 셋 다 0/nil 인 날은 말할 것이 없어 뺀다.
    package static func values(usage: TokenUsageMonthly, account: CodexAccountUsage?) -> [String: TokenUsageDailyValue] {
        let windowStart = usage.windowStartDay
        let completeFrom = usage.claudeCompleteFrom
        let monthPrefix = usage.month + "-"
        // UTC 축 맵의 보존 하한(전월 마지막 UTC 일). 그 날과 그 앞 날짜의 codex_utc_total 은 모른다(nil) — 하한 당일은 재파싱 직후 부분값이고
        // (E-4), 그 앞은 맵에 없다. UTC 맵 자체는 이 빌드가 스캔한 스냅샷(windowStart 채워짐)에만 있다 — 옛 스냅샷은 통째로 모른다(E-3).
        let utcRetainFrom = TokenUsageIncrementalScanner.utcRetainFromKey(monthString: usage.month)
        let utcMapIsFromThisBuild = !usage.windowStart.isEmpty
        let buckets = account?.buckets ?? [:]
        var result: [String: TokenUsageDailyValue] = [:]
        // 고정폭 'YYYY-MM-DD' 라 사전식 비교 == 날짜 순서. 계정 버킷·UTC 맵은 UTC 일자 키, Claude·Codex KST 맵은 KST 일자 키인데
        // 한 행(day)에 다섯 값이 함께 실린다(v0.3.12 에 antigravity_total 합류) — 서버 컬럼이 축을 각각 명시한다
        // (codex_total=KST 하루, codex_utc_total=UTC 하루, codex_account=UTC 버킷, antigravity_total=KST 하루).
        let keys = Set(usage.claudeDaily.keys).union(usage.codexDaily.keys).union(usage.codexDailyUTC.keys)
            .union(usage.antigravityDaily.keys).union(buckets.keys)
        for day in keys where day >= windowStart {
            // 각 값은 그 맵이 덮는 날에만 싣는다(TokenUsageDailyValue 주석). 모르는 값은 nil → 키 생략 → 서버의 옛 완전값 보존.
            let claudeKnown = completeFrom.isEmpty || day >= completeFrom
            let codexKnown = day.hasPrefix(monthPrefix)
            let utcKnown = utcMapIsFromThisBuild && day > utcRetainFrom
            // 안티그래비티는 **그 날 맵에 값이 있을 때만** 싣는다. 현재 월이라는 것만으로 0 을 실으면
            //  ① 안티그래비티를 안 쓰는 절대다수의 행에까지 `antigravity_total` 키가 붙어, 서버에 컬럼이 아직 없는 창에서
            //     **모든 사용자의 일별 업로드**가 400 으로 죽는다(월간 경로가 네 키를 함께 빼는 것과 같은 이유).
            //  ② 그 사람의 그 날 값이 서버에 이미 있었다면 0 으로 밀린다(맵은 현재 월만 담고, 재파싱 중엔 비어 있을 수 있다).
            // 맵은 양수만 쌓으므로 "키가 있다 == 그 날 쓴 값이 있다"이다 — 키의 유무가 곧 앎의 유무다.
            let antigravityKnown = day.hasPrefix(monthPrefix) && usage.antigravityDaily[day] != nil
            let value = TokenUsageDailyValue(
                claude: claudeKnown ? max(0, usage.claudeDaily[day] ?? 0) : nil,
                codex: codexKnown ? max(0, usage.codexDaily[day] ?? 0) : nil,
                codexUTC: utcKnown ? max(0, usage.codexDailyUTC[day] ?? 0) : nil,
                codexAccount: buckets[day].map { max(0, $0) },
                antigravity: antigravityKnown ? max(0, usage.antigravityDaily[day] ?? 0) : nil
            )
            guard (value.claude ?? 0) > 0 || (value.codex ?? 0) > 0 || (value.codexUTC ?? 0) > 0
                    || value.codexAccount != nil || (value.antigravity ?? 0) > 0 else { continue }
            result[day] = value
        }
        return result
    }

    /// 마지막 성공 업로드와 값이 다른 날만(날짜 오름차순 — 요청 본문이 결정적이라 테스트·로그가 읽기 쉽다). 장부가 비어 있으면 전부.
    package static func changedDays(current: [String: TokenUsageDailyValue], lastUploaded: [String: TokenUsageDailyValue]) -> [String] {
        current.filter { day, value in lastUploaded[day] != value }.keys.sorted()
    }

    /// 요청 행(days 순서 그대로). values 에 없는 날은 건너뛴다(형이 어긋나도 크래시 없음).
    package static func rows(userID: String, deviceID: String, days: [String], values: [String: TokenUsageDailyValue]) -> [TokenUsageDailyUpsertRow] {
        days.compactMap { day in
            guard let value = values[day] else { return nil }
            return TokenUsageDailyUpsertRow(
                userId: userID, day: day, deviceId: deviceID,
                claudeTotal: value.claude, codexTotal: value.codex, codexUtcTotal: value.codexUTC,
                codexAccount: value.codexAccount, antigravityTotal: value.antigravity
            )
        }
    }
}

/// 떠 있는 `token_usage_board` 조회 한 건(stab-l6). `id` 는 끝난 Task 가 **자기 자리만** 비우게 하는 표식이다 —
/// force 조회가 자리를 넘겨받은 뒤 늦게 끝난 옛 조회가 새 자리를 지우면, 그 뒤 호출자가 다시 겹쳐 쏜다.
