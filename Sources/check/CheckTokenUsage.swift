import CryptoKit
import Foundation
import Observation
import SwiftUI

// MARK: - 집계 모델 (월 단위)

/// KST 달력 '한 달' 치 AI CLI 토큰 사용량. 롤링 30일 창이 아니라 **현재 KST 월**(1일 0시부터)의 누적이며,
/// 달이 바뀌면(예: 8월 1일) 0부터 다시 쌓인다. 두 트랙이 공유하는 계약 타입이라 필드 이름·시그니처는 고정이다.
///
/// 프라이버시: 여기 담기는 값은 usage 숫자와 귀속 월(month)뿐이다. 대화 본문·프롬프트·파일 경로 등 내용 필드는
/// 스캔 단계에서 읽지도 보관하지도 않는다(아래 TokenUsageIncrementalScanner 주석 참고).
struct TokenUsageMonthly: Codable, Equatable, Sendable {
    /// 이 집계가 귀속된 KST 달력 월 'YYYY-MM'. 복원 시 이 값이 현재 월과 다르면 표시하지 않고 재스캔한다(월 리셋).
    var month: String
    var claudeInput: Int = 0
    var claudeOutput: Int = 0
    var claudeCacheRead: Int = 0
    var claudeCacheCreation: Int = 0
    /// Codex 입력 델타 합(**캐시 포함** — rollout 의 `input_tokens` 가 캐시 히트를 포함한 값이다).
    var codexInput: Int = 0
    /// Codex 출력 델타 합. v0.2.40 까지는 입력+출력을 합쳐 codexInput 에 몰아넣고 이 필드는 항상 0 이었다(v0.2.41 에 분리, issue #2).
    var codexOutput: Int = 0
    /// Codex 캐시 히트 델타 합(`cached_input_tokens`). **codexInput 의 부분집합**이라 `total` 에는 더하지 않는다 —
    /// 더하면 캐시분이 두 번 계상된다(Claude 의 cache_read 는 input_tokens 와 배타라 더하지만, Codex 는 포함 관계다).
    /// 툴팁·서버 컬럼(codex_cache_read)에 "얼마나 캐시로 처리됐나"를 보여 주기 위한 값(issue #2).
    var codexCacheRead: Int = 0

    /// 오늘(KST 자정 이후) 늘어난 토큰량 = "오늘 +N" 표시의 원천. 각 앱이 자기 로컬 로그에서 계산해 서버 행에 함께 올린다.
    /// v0.2.41 부터 두 일별 맵(claudeDaily/codexDaily)의 **오늘 키 값의 합으로 파생**된다 — 값은 예전과 같다:
    /// Claude 는 엔트리 ts14 의 KST 날짜 == 오늘인 것의 (입력+출력+캐시읽기+캐시생성) 합, Codex 는 token_count 이벤트마다
    /// 그 이벤트 timestamp(→KST)가 오늘인 delta(=Σ max(0, 현재누적 − 직전누적), 입력+출력)의 합. total 의 부분집합.
    var todayTotal: Int = 0
    /// todayTotal 이 귀속된 KST 날짜 'YYYY-MM-DD'. 표시 측이 현재 KST 날짜와 다르면(어제 이후 안 연 스냅샷) 오늘분을 0 으로 본다.
    var todayDate: String = ""
    /// KST 'YYYY-MM-DD' → 그 날 Claude 4필드 합(현재 월 안의 날짜만). 일별 추이(과제 E)의 원천이며 todayTotal 의 Claude 몫이다.
    var claudeDaily: [String: Int] = [:]
    /// KST 'YYYY-MM-DD' → 그 날 Codex 입력+출력 델타 합(현재 월 안의 날짜만). todayTotal 의 Codex 몫.
    var codexDaily: [String: Int] = [:]

    /// 화면 우측에 굵게 뜨는 총합 = 여섯 필드의 단순 합. **codexCacheRead 는 넣지 않는다**(codexInput 의 부분집합).
    /// 이 값이 서버 `total` 컬럼으로 올라가 기기 합산에 쓰이므로 의미(로컬 6필드 합)를 바꾸지 마라 — 계정 집계를 섞은
    /// 표시 총합은 TokenUsageDisplay.effectiveTotal 이 따로 만든다.
    var total: Int {
        claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation + codexInput + codexOutput
    }

    /// Claude 소계(입력+출력+캐시읽기+캐시생성) — 툴팁 표기용.
    var claudeTotal: Int { claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation }
    /// Codex 소계(입력+출력) — 툴팁 표기용. 의미 불변: 캐시는 입력에 이미 들어 있다.
    var codexTotal: Int { codexInput + codexOutput }

    /// 라벨 "N월 …"에 쓰는 월 숫자. 'YYYY-MM' 의 뒤 두 자리를 정수로(선행 0 제거). 파싱 실패 시 0.
    var monthNumber: Int { Int(month.split(separator: "-").last ?? "") ?? 0 }

    /// .help 툴팁 상세 문구(계정 집계 없이). 축약 없이 콤마 전체 숫자로, 값이 있는 소스만 이어 붙인다
    /// ("Claude 4,280,667,571 (입력 8,458,939 · 출력 9,796,198 · 캐시읽기 4,063,320,273 · 캐시생성 199,092,161) · Codex 145,691,467 (입력 145,068,307 · 출력 623,160 · 캐시 0)").
    var detailTooltip: String { detailTooltip(account: nil) }

    /// 계정 집계까지 붙인 툴팁. 계정 월합이 있으면 `Codex 계정 집계 N (D일까지 반영)` 을 잇고, 그 값이 로컬보다 크면
    /// 표시 총합에 계정값이 쓰였음을 한 줄로 명시한다(행의 굵은 숫자와 로컬 소계가 왜 다른지 설명하는 자리).
    func detailTooltip(account: CodexAccountUsage?) -> String {
        var parts: [String] = []
        if claudeTotal > 0 {
            parts.append(
                "Claude \(TokenNumberFormatter.grouped(claudeTotal)) "
                + "(입력 \(TokenNumberFormatter.grouped(claudeInput)) · 출력 \(TokenNumberFormatter.grouped(claudeOutput)) "
                + "· 캐시읽기 \(TokenNumberFormatter.grouped(claudeCacheRead)) · 캐시생성 \(TokenNumberFormatter.grouped(claudeCacheCreation)))"
            )
        }
        if codexTotal > 0 {
            parts.append(
                "Codex \(TokenNumberFormatter.grouped(codexTotal)) "
                + "(입력 \(TokenNumberFormatter.grouped(codexInput)) · 출력 \(TokenNumberFormatter.grouped(codexOutput)) "
                + "· 캐시 \(TokenNumberFormatter.grouped(codexCacheRead)))"
            )
        }
        if let account {
            let accountMonth = account.monthTotal(month)
            if accountMonth > 0 {
                var line = "Codex 계정 집계 \(TokenNumberFormatter.grouped(accountMonth))"
                if let day = account.latestBucketDate(in: month), let dayNumber = Int(day.suffix(2)) {
                    line += " (\(dayNumber)일까지 반영)"
                }
                parts.append(line)
                if accountMonth > codexTotal {
                    parts.append("총합은 계정 집계 기준")
                }
            }
        }
        // 내 박스 툴팁 끝에 "오늘 +N" 한 줄을 덧붙인다(값이 있을 때만 — 없으면 기존 문구 그대로라 하위 호환).
        // 내 박스 usage 는 매번 갓 스캔한 값이라 todayDate 는 항상 오늘이므로 여기선 날짜 가드 없이 노출한다.
        if todayTotal > 0 {
            parts.append("오늘 +\(TokenNumberFormatter.grouped(todayTotal))")
        }
        return parts.joined(separator: " · ")
    }
}

// TokenUsageMonthly Codable 하위호환: 옛 영속 스냅샷엔 today 필드가 없다 — decodeIfPresent 로 0/"" 폴백해
// 디코드 실패(nil 처리 → 재스캔) 없이 우아하게 복원한다. 키는 옛 스냅샷과 동일한 프로퍼티명(camelCase, 스네이크 변환 없음).
extension TokenUsageMonthly {
    enum CodingKeys: String, CodingKey {
        case month
        case claudeInput, claudeOutput, claudeCacheRead, claudeCacheCreation
        case codexInput, codexOutput, codexCacheRead
        case todayTotal, todayDate
        case claudeDaily, codexDaily
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        claudeInput = try c.decodeIfPresent(Int.self, forKey: .claudeInput) ?? 0
        claudeOutput = try c.decodeIfPresent(Int.self, forKey: .claudeOutput) ?? 0
        claudeCacheRead = try c.decodeIfPresent(Int.self, forKey: .claudeCacheRead) ?? 0
        claudeCacheCreation = try c.decodeIfPresent(Int.self, forKey: .claudeCacheCreation) ?? 0
        codexInput = try c.decodeIfPresent(Int.self, forKey: .codexInput) ?? 0
        codexOutput = try c.decodeIfPresent(Int.self, forKey: .codexOutput) ?? 0
        // 하위호환 핵심: 옛 스냅샷엔 없는 필드 — 없으면 0/""/빈 맵으로 본다(오늘분 미상 → 표시 0, 일별 미상 → 빈 추이).
        codexCacheRead = try c.decodeIfPresent(Int.self, forKey: .codexCacheRead) ?? 0
        todayTotal = try c.decodeIfPresent(Int.self, forKey: .todayTotal) ?? 0
        todayDate = try c.decodeIfPresent(String.self, forKey: .todayDate) ?? ""
        claudeDaily = try c.decodeIfPresent([String: Int].self, forKey: .claudeDaily) ?? [:]
        codexDaily = try c.decodeIfPresent([String: Int].self, forKey: .codexDaily) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(month, forKey: .month)
        try c.encode(claudeInput, forKey: .claudeInput)
        try c.encode(claudeOutput, forKey: .claudeOutput)
        try c.encode(claudeCacheRead, forKey: .claudeCacheRead)
        try c.encode(claudeCacheCreation, forKey: .claudeCacheCreation)
        try c.encode(codexInput, forKey: .codexInput)
        try c.encode(codexOutput, forKey: .codexOutput)
        try c.encode(codexCacheRead, forKey: .codexCacheRead)
        try c.encode(todayTotal, forKey: .todayTotal)
        try c.encode(todayDate, forKey: .todayDate)
        try c.encode(claudeDaily, forKey: .claudeDaily)
        try c.encode(codexDaily, forKey: .codexDaily)
    }
}

// MARK: - 숫자 포맷 (순수 함수)

/// 토큰 수를 콤마 천 단위 구분의 **전체 숫자**로 만든다(축약 B/M/K 없음, 1의 자리까지). 예: 4_564_338_243 → "4,564,338,243".
/// 로케일 의존을 피하려 수동으로 3자리마다 콤마를 넣는다(NumberFormatter 의 지역별 구분자 차이 회피 — 결정적).
/// 음수는 방어적으로 0 으로 클램프한다(토큰 수는 음이 될 수 없다).
enum TokenNumberFormatter {
    static func grouped(_ value: Int) -> String {
        let digits = String(max(0, value))
        var out = ""
        var count = 0
        // 뒤에서부터 3자리마다 콤마를 끼운다.
        for ch in digits.reversed() {
            if count > 0, count % 3 == 0 { out.append(",") }
            out.append(ch)
            count += 1
        }
        return String(out.reversed())
    }
}

// MARK: - 증분 캐시 (영속 · 파일 저장)

/// 증분 스캔의 상태를 담는 영속 캐시. Application Support 에 컴팩트 JSON 으로 저장한다(UserDefaults 에 수 MB 금지).
///
/// 세 축:
/// - claudeFileStates: 경로 → (size, mtime, consumedOffset). 파일이 안 변했는지(스킵)·어디까지 읽었는지(이어읽기) 판단.
/// - claudeEntries: dedupe 키(ClaudeEntryKey = "id\0requestId" 의 128비트 해시) → 엔트리. 라인 단위 usage 를 dedupe 해
///   월 필터로 합계를 낸다. append-only 로그라 파일이 커져도 새 바이트만 이어읽어 엔트리를 추가한다.
/// - codexFileStates: 경로 → (offset, size, mtime, 필드별 기준선 prev*, 월 기여 month*, 일별 맵 dayContrib). rollout 은
///   token_count 이벤트마다 그 이벤트 timestamp(→KST)로 delta 를 월/일에 정확히 귀속한다(파일 mtime 월에 세션 누적치를
///   통째 귀속하던 옛 근사 폐기). 경로는 `~/.codex/sessions` 와 `~/.codex/archived_sessions` 두 루트에서 온다(v0.2.41).
///
/// 압축: 엔트리/상태는 이름키 대신 배열 튜플로 인코딩한다(3만 엔트리 ≈ 수 MB → 이름키면 배로 커진다).
///
/// 상주 크기(v0.2.38 계측 후 개편): v0.2.37 은 문자열 키 딕셔너리가 ≈16MB 상주했다 — `[String: ClaudeEntry]` 7.67MB
/// (70,766 엔트리) + 키 문자열 저장소 74,431 개 8.0MB. 그중 73% 가 지난달 엔트리였다(보관 경계가 직전 월 1일).
/// 그래서 (1) 키를 16바이트 인라인 해시로(문자열 힙 객체 0), (2) 보관 경계를 월 시작 − 48h 로 당겨(월 경계 straddle 만 남김)
/// 엔트리 맵을 ≈1/5 로 줄인다. 두 변경 모두 합계 산식(현재 월 필터)은 건드리지 않는다.
///
/// 핫/콜드 분리(디스크): 파일 진행 상태(핫 — 파일이 자랄 때마다 바뀌는 수백 KB)와 엔트리(콜드 — 수 MB)를 별도 파일로
/// 쓴다. 저장은 스토어의 스로틀(≥5분 / 팝오버 닫힘 / 종료)을 타고, 그때도 더러워진 쪽만 다시 쓴다. 레이아웃은
/// TokenUsageCacheStore 참고.
///
/// 하위호환: codexSchemaVersion 으로 codex 상태의 스키마 세대를 표기한다. 이벤트-귀속 재설계로 옛 codexFileStates 는
/// 델타 이력이 없어 재활용 불가 — 로드 시 버전이 현재와 다르면 codexFileStates 만 버리고(Claude 상태는 유지) 전체 재파싱을
/// 1회 유발한다(과거 귀속이 소급 교정된다). 아래 커스텀 Codable 이 이 게이트를 수행한다.
struct TokenUsageCache: Equatable, Sendable {
    var claudeFileStates: [String: FileProgress] = [:]
    var claudeEntries: [ClaudeEntryKey: ClaudeEntry] = [:]
    var codexFileStates: [String: CodexFileProgress] = [:]
    /// codex 상태 스키마 버전. 로드 시 currentCodexSchemaVersion 과 다르면 codexFileStates 를 폐기해 재파싱을 유발한다.
    var codexSchemaVersion: Int = TokenUsageCache.currentCodexSchemaVersion

    /// 현재 codex 상태 스키마 버전(이벤트-타임스탬프 귀속).
    ///
    /// 2 → 3: "파일의 첫 관측 누적치는 델타가 아니라 기준선" 규칙 도입(근거는 CodexFileProgress 주석의 프로덕션 실측).
    /// 버전이 오르면 로드 시 옛 codexFileStates 가 폐기되고 codex 전체 재파싱이 1회 일어나는데,
    /// **이미 부풀어 박힌 이번 달 값이 그 재파싱으로 재계산되는 것이 이 변경의 정정 메커니즘이다.**
    /// (버전을 그대로 두면 캐시에 남은 옛 monthContribTotal 이 그대로 살아 있어 산식만 고쳐도 숫자가 안 고쳐진다.)
    /// 옛 mtime-월/dayBaseline 캐시는 이 키가 없어 버전 0 으로 취급된다.
    ///
    /// 3 → 4(v0.2.41): 기준선·월 기여를 입력/출력/캐시 세 필드로 쪼개고(issue #2), 일키+일합 한 쌍을 일별 맵으로 바꿨다
    /// (과제 E 선행). 튜플 인코딩 형태가 달라졌으므로 옛 8원소 튜플은 재활용하지 않고 폐기 → codex 1회 전체 재파싱.
    /// 이 재파싱이 곧 **보관/압축 유실의 소급 정정**이기도 하다 — archived_sessions 를 처음 읽고, 옛 캐시가 버린 기여를 다시 쌓는다.
    static let currentCodexSchemaVersion = 4
}

/// Claude 엔트리의 dedupe 키. 옛 문자열 키 "message.id\0requestId" 의 **SHA-256 앞 16바이트**를 빅엔디언 UInt64 두 개로
/// 든다 — 정의가 "그 문자열의 해시"라 (id, requestId) 로 만들든 옛 문자열로 만들든 같은 키다.
///
/// 왜 해시인가: 문자열 키는 엔트리마다 힙 객체 하나(≈96B)를 더 들고, 딕셔너리 슬롯도 16B 포인터+길이 대신 그 문자열을
/// 비교한다. 16바이트 인라인 키는 힙 객체 0, 해시/비교가 정수 연산이고, JSON 으로도 32자 16진(옛 키 ≈60자+`\0`)이라
/// 콜드 파일도 준다.
///
/// 충돌: 128비트라 생일 경계가 2^64 개 키다. 한 달 치 10^5 개 키에서 충돌 확률 ≈ n²/2^129 ≈ 10^-29 — 실질 0
/// (SHA-256 절단이라 입력 편향에도 균일하다). 두 요청이 한 엔트리로 합쳐지려면 이 확률을 뚫어야 한다.
struct ClaudeEntryKey: Hashable, Sendable {
    let hi: UInt64
    let lo: UInt64

    /// 옛 dedupe 문자열("id\0requestId")에서. 캐시의 옛 세대 키를 그대로 해시하면 새 키가 된다(정의 그 자체).
    init(dedupeString: String) {
        self.init(hashing: Array(dedupeString.utf8))
    }

    /// 프로덕션 ingest 경로. NUL 구분자(둘 다 NUL 을 못 담으므로 ("ab","") 와 ("a","b") 가 다른 키다).
    init(messageID: String, requestID: String) {
        var bytes = Array(messageID.utf8)
        bytes.append(0)
        bytes.append(contentsOf: requestID.utf8)
        self.init(hashing: bytes)
    }

    private init(hashing bytes: [UInt8]) {
        let digest = SHA256.hash(data: bytes)
        (hi, lo) = digest.withUnsafeBytes { raw in
            (raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self).bigEndian,
             raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self).bigEndian)
        }
    }

    /// 32자 소문자 16진(hi 16자 + lo 16자). 캐시 JSON 의 오브젝트 키가 이 문자열이다.
    var hex: String {
        var out = [UInt8](repeating: 0, count: 32)
        let digits = Array("0123456789abcdef".utf8)
        var h = hi, l = lo
        for i in stride(from: 15, through: 0, by: -1) {
            out[i] = digits[Int(h & 0xF)]; h >>= 4
            out[16 + i] = digits[Int(l & 0xF)]; l >>= 4
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// 32자 16진에서. 자릿수가 다르거나 16진이 아닌 문자가 있으면 nil(옛 문자열 키는 항상 NUL 을 담으므로 여기서 걸러진다).
    init?(hex: String) {
        let b = Array(hex.utf8)
        guard b.count == 32 else { return nil }
        var acc: [UInt64] = [0, 0]
        for (i, c) in b.enumerated() {
            let v: UInt64
            switch c {
            case 48...57: v = UInt64(c - 48)
            case 97...102: v = UInt64(c - 87)
            case 65...70: v = UInt64(c - 55)
            default: return nil
            }
            acc[i / 16] = (acc[i / 16] << 4) | v
        }
        hi = acc[0]; lo = acc[1]
    }
}

// 단일값 16진 문자열로 왕복한다. 딕셔너리는 (Swift 의 비-String 키 딕셔너리가 평면 배열로 인코드되는 함정을 피해)
// 아래 헬퍼로 `[String: ClaudeEntry]` 오브젝트로 명시 변환해 쓴다.
extension ClaudeEntryKey: Codable {
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let key = ClaudeEntryKey(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "ClaudeEntryKey 16진 32자가 아님"))
        }
        self = key
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

extension Dictionary where Key == ClaudeEntryKey, Value == ClaudeEntry {
    /// 옛 dedupe 문자열("id\0requestId")로 조회/대입. 키의 정의가 그 문자열의 해시라 프로덕션 ingest 가 넣은 엔트리에
    /// 그대로 닿는다 — 우회가 아니라 정의를 쓰는 것이다(테스트·진단용, 스캔 경로는 (id, requestId) 이니셜라이저를 쓴다).
    subscript(_ dedupeString: String) -> ClaudeEntry? {
        get { self[ClaudeEntryKey(dedupeString: dedupeString)] }
        set { self[ClaudeEntryKey(dedupeString: dedupeString)] = newValue }
    }

    /// JSON 오브젝트(16진 키)로. 콜드 파일과 모놀리식 인코딩이 공유한다.
    var hexKeyed: [String: ClaudeEntry] {
        var out: [String: ClaudeEntry] = [:]
        out.reserveCapacity(count)
        for (k, v) in self { out[k.hex] = v }
        return out
    }

    /// JSON 오브젝트에서. strict 면 16진이 아닌 키 하나라도 있으면 nil(콜드 파일 손상 → 폐기). lenient 면 옛 문자열 키를
    /// 해시해 받아들인다(옛 모놀리식 캐시를 디코드하는 경로 — 스토어는 그 세대를 로드하지 않지만 디코더는 전 세대를 읽는다).
    static func fromHexKeyed(_ raw: [String: ClaudeEntry], strict: Bool) -> [ClaudeEntryKey: ClaudeEntry]? {
        var out: [ClaudeEntryKey: ClaudeEntry] = [:]
        out.reserveCapacity(raw.count)
        for (s, v) in raw {
            if let k = ClaudeEntryKey(hex: s) {
                out[k] = v
            } else if strict {
                return nil
            } else {
                out[ClaudeEntryKey(dedupeString: s)] = v
            }
        }
        return out
    }
}

// TokenUsageCache 커스텀 Codable(스키마 게이트 + 압축 딕셔너리 왕복). 옛 캐시(codexSchemaVersion 부재/불일치)는
// codexFileStates 를 통째로 버려(Claude 상태는 보존) 다음 스캔에서 codex 를 전체 재파싱하게 만든다. 이렇게 하면 옛 6/8필드
// codex 튜플(숫자열)을 새 8필드(문자열 섞임) 형식으로 억지 디코드하다 던지는 실패(→ 전체 캐시 폐기, Claude 재스캔)를 피한다.
//
// 이 인코딩은 "캐시 전체 한 덩어리"(모놀리식)다. 스토어(TokenUsageCacheStore)는 이걸 핫 파일의 본문으로 쓰되 엔트리를
// 비워 넣고, 엔트리는 콜드 파일에 따로 쓴다. 디코더는 옛 문자열 키 엔트리도(해시해서) 받아들이므로 어느 세대의 모놀리식
// JSON 도 읽히지만, 스토어의 레이아웃 버전 게이트는 v0.2.37 이하 파일을 로드하지 않는다(그쪽 주석 참고).
extension TokenUsageCache: Codable {
    enum CodingKeys: String, CodingKey {
        case claudeFileStates, claudeEntries, codexFileStates, codexSchemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeFileStates = try c.decodeIfPresent([String: FileProgress].self, forKey: .claudeFileStates) ?? [:]
        let rawEntries = try c.decodeIfPresent([String: ClaudeEntry].self, forKey: .claudeEntries) ?? [:]
        claudeEntries = Dictionary.fromHexKeyed(rawEntries, strict: false) ?? [:]
        let version = try c.decodeIfPresent(Int.self, forKey: .codexSchemaVersion) ?? 0
        if version == Self.currentCodexSchemaVersion {
            codexFileStates = try c.decodeIfPresent([String: CodexFileProgress].self, forKey: .codexFileStates) ?? [:]
        } else {
            // 스키마 불일치(옛 세대): 델타 이력 없는 codex 상태는 재활용 불가 — 버리고(빈 맵) 전체 재파싱 유발. Claude 는 위에서 이미 유지.
            codexFileStates = [:]
        }
        // 인메모리 버전은 항상 현재로. 다음 저장 시 새 형식·현재 버전으로 기록된다(1회 재파싱 후 정착).
        codexSchemaVersion = Self.currentCodexSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claudeFileStates, forKey: .claudeFileStates)
        try c.encode(claudeEntries.hexKeyed, forKey: .claudeEntries)
        try c.encode(codexFileStates, forKey: .codexFileStates)
        try c.encode(codexSchemaVersion, forKey: .codexSchemaVersion)
    }
}

/// Claude/Codex 공통 파일 진행 상태. consumedOffset 은 "마지막 완결 라인의 끝"(개행 다음 바이트) — 이어읽기 시작점.
struct FileProgress: Equatable, Sendable {
    var size: Int
    var mtimeMicros: Int   // mtime 을 마이크로초 정수로(부동소수 왕복 오차 없이 == 비교하기 위해).
    var consumedOffset: Int
}

/// Claude 한 라인의 집계값 + 월 판정용 타임스탬프(YYYYMMDDHHMMSS 정수 = 고정폭 UTC 라 사전식==시간순).
struct ClaudeEntry: Equatable, Sendable {
    /// 월/퇴거 판정용 ts14 = 이 dedupe 키에서 '관측한 최대 ts14'. max-output 이 이긴 레코드의 ts 가 아니라
    /// 관측 최대치를 유지해, 지난달의 옛 큰-output 스냅샷이 이번달(더 최신)의 같은 키를 통째로 탈락시키지 않게 한다.
    var ts14: Int
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheCreation: Int
}

/// Codex 파일(세션)의 증분 진행 상태 + 이벤트-타임스탬프 귀속 누적. 파일 mtime 월에 세션 누적치를 통째 귀속하던 옛 근사
/// (지난달 시작 세션을 이번 달 resume 하면 과거 누적 전체가 이번 달로 편입 → +수십억 이상치)를 버리고, token_count
/// 이벤트마다 그 이벤트 timestamp(→KST)로 delta 를 월/일에 정확히 귀속한다.
///
/// **파일의 첫 관측 누적치는 델타가 아니라 기준선이다.** 여기엔 원래 "resume/fork 파일은 카운터가 0에서 새로
/// 시작하므로(이월 없음) 파일 간 중복합산 걱정이 없다"고 적혀 있었다. 그 단언에는 근거가 없었고, v0.2.30 에 넣은
/// 진단 계측이 프로덕션에서 회수한 값으로 **거짓임이 확인됐다**(실사용자 2인, 2026-08 기준):
///
/// | | 앱값(codex_input) | 큰 누적치로 '시작'하는 파일 수 | 그 시작치들의 합 | 파일당 평균 |
/// |---|---|---|---|---|
/// | A | 96,805,065,798 | 54  | 35,924,152,806 (앱값의 37%) | 665,262,089 |
/// | B | 74,487,275,586 | 105 | 44,134,955,126 (앱값의 59%) | 420,332,905 |
///
/// 둘 다 dup_events 0 / drops 0 이었다 — 파일 간 중복 계상도, 카운터 리셋도 아니다. 남는 설명은 하나뿐이다:
/// 파일이 평균 6.6억/4.2억 토큰**에서 시작한다.** 그 파일이 첫 로그 줄을 쓰기도 전에 소비했을 수 있는 양이 아니므로
/// 직전 세션에서 이어받은 카운터이고, 파일마다 기준선을 0 에서 시작하면 그 전액이 이번 달 델타로 통째로 들어간다.
///
/// 그래서 오프셋 0 부터 새로 파싱할 때(신규 파일 / 축소·mtime 역행에 의한 전체 재파싱) 그 파일에서 **처음 만나는
/// 유효 token_count 는 델타를 만들지 않고 기준선만 세운다**(delta 0). 두 번째 이벤트부터 max(0, cum − 기준선).
/// 이어읽기 경로는 캐시의 prevCumulative 가 이미 유효한 기준선이라 동작이 바뀌지 않는다.
///
/// 트레이드오프: **진짜 새 세션의 첫 턴을 놓친다.** 그 크기는 최대 컨텍스트(수십만) 수준이라 이월분 6.6억에 견주면
/// 무시할 수 있고, 남의 세션에서 이어받은 누적을 이번 달에 통째로 얹는 쪽보다 훨씬 작은 오차다. 되돌리려는 사람은
/// 위 실측을 먼저 반박해라 — 이 선택은 추정이 아니라 프로덕션 계측에서 나왔다.
struct CodexFileProgress: Equatable, Sendable {
    var size: Int
    var mtimeMicros: Int
    var consumedOffset: Int
    /// 파일별 마지막 유효 token_count 의 누적치 세 갈래(`total_token_usage` 의 input_tokens(캐시 포함)·output_tokens·
    /// cached_input_tokens). 다음 이벤트 delta 의 기준선이며 **필드별로** `max(0, cum − prev)` 를 낸다(issue #2 — 캐시 분리).
    /// info null·timestamp 결손 이벤트는 이 값을 갱신하지 않는다 — 건너뛴 토큰은 다음 유효 이벤트의 delta 에 자연 흡수(유실 없음).
    /// 이 파일에서 아직 유효 이벤트를 하나도 못 본 상태는 (consumedOffset == 0, prev* == 0) 으로 표현된다
    /// — 이벤트 라인을 소비했다면 그 줄의 개행까지 소비돼 consumedOffset > 0 이므로, 이 조합은 "기준선 없음"과 동치다.
    var prevInput: Int
    var prevOutput: Int
    var prevCached: Int
    /// 이 파일 상태가 마지막으로 갱신된 KST 'YYYY-MM'. month* = 그 월에 귀속된 이벤트 delta 의 필드별 합.
    /// 표시 총합은 monthKey == 현재 월 인 파일의 month* 만 더한다(월 롤오버 시 0 리셋 → 과거분 자연 탈락).
    var monthKey: String
    var monthInput: Int
    var monthOutput: Int
    var monthCached: Int
    /// KST 'YYYY-MM-DD' → 그 날 귀속 delta(입력+출력)의 합. **현재 월(monthKey) 의 키만** 담고 월 롤오버 때 비운다.
    /// v0.2.40 까지의 (dayKey, dayContribTotal) 한 쌍을 대체한다 — 일 롤오버마다 상태를 고쳐 쓰던(저장 유도) 비용이 없어지고,
    /// 지난 날들의 값이 남아 일별 추이(과제 E)를 만들 수 있다. 오늘 값은 이 맵의 오늘 키다.
    var dayContrib: [String: Int]

    /// 옛 산식과의 대조용 합(입력+출력) — 델타의 기준선을 한 숫자로 보고 싶은 테스트·주석이 쓴다.
    var prevCumulative: Int { prevInput + prevOutput }
    /// 이 파일의 현재 월 기여(입력+출력) — 캐시는 입력의 부분집합이라 더하지 않는다.
    var monthContribTotal: Int { monthInput + monthOutput }
}

// 압축 인코딩(배열 튜플). 이름키 JSON 대비 절반 크기 — 3만 엔트리 캐시를 수 MB 이내로 유지한다.
extension FileProgress: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        size = try c.decode(Int.self)
        mtimeMicros = try c.decode(Int.self)
        consumedOffset = try c.decode(Int.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(size); try c.encode(mtimeMicros); try c.encode(consumedOffset)
    }
}

extension ClaudeEntry: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        ts14 = try c.decode(Int.self)
        input = try c.decode(Int.self)
        output = try c.decode(Int.self)
        cacheRead = try c.decode(Int.self)
        cacheCreation = try c.decode(Int.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(ts14); try c.encode(input); try c.encode(output)
        try c.encode(cacheRead); try c.encode(cacheCreation)
    }
}

// 압축 배열-튜플 인코딩(11원소, 스키마 v4):
//   [size, mtime, offset, prevInput, prevOutput, prevCached, monthKey, monthInput, monthOutput, monthCached, {day: delta}].
// 옛 세대 튜플(v3 의 8원소·그 이전 숫자열)은 TokenUsageCache 의 스키마 게이트가 애초에 이 디코더로 오지 못하게 막으므로,
// 여기의 decodeIfPresent 는 새 형식의 잘린 튜플에 대한 방어일 뿐이다(at-end → 기본값). monthKey 위치에 숫자를 억지 디코드하는 일은 없다.
extension CodexFileProgress: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        size = try c.decode(Int.self)
        mtimeMicros = try c.decode(Int.self)
        consumedOffset = try c.decode(Int.self)
        prevInput = try c.decodeIfPresent(Int.self) ?? 0
        prevOutput = try c.decodeIfPresent(Int.self) ?? 0
        prevCached = try c.decodeIfPresent(Int.self) ?? 0
        monthKey = try c.decodeIfPresent(String.self) ?? ""
        monthInput = try c.decodeIfPresent(Int.self) ?? 0
        monthOutput = try c.decodeIfPresent(Int.self) ?? 0
        monthCached = try c.decodeIfPresent(Int.self) ?? 0
        dayContrib = try c.decodeIfPresent([String: Int].self) ?? [:]
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(size); try c.encode(mtimeMicros); try c.encode(consumedOffset)
        try c.encode(prevInput); try c.encode(prevOutput); try c.encode(prevCached)
        try c.encode(monthKey)
        try c.encode(monthInput); try c.encode(monthOutput); try c.encode(monthCached)
        try c.encode(dayContrib)
    }
}

/// 캐시 파일 로드/저장. 스캔과 분리해 스캐너는 로그 파일만 읽게 한다.
///
/// 레이아웃(v0.2.38, 핫/콜드 분리). 베이스 URL(옛 단일 파일 자리, Application Support/aing-check/token-usage-cache.json)에서
/// 두 파일을 파생한다:
/// - `<베이스>.state.json`(핫): `{"schemaVersion": N, "state": <TokenUsageCache 모놀리식, 엔트리 비움>}` — 파일 진행 상태.
///   파일이 자랄 때마다 바뀌지만 수백 KB 다.
/// - `<베이스>.entries.json`(콜드): `{"<16진 키>": [ts14, in, out, cr, cc], ...}` — 엔트리 맵. 수 MB 지만 새 usage 라인이
///   들어올 때만 바뀐다.
/// 저장은 더러워진 쪽만 다시 쓰되(둘 다 없으면 만들고), **콜드를 먼저** 쓴다 — 핫이 콜드보다 앞서 디스크에 남으면
/// "이미 소비한 오프셋"인데 엔트리가 없는 상태가 되어 과소집계다(반대는 재읽기+dedupe 로 무해).
///
/// 로드는 두 파일이 다 있고 핫의 schemaVersion 이 현재와 같을 때만 성립한다. 그 외(없음·손상·옛 세대)는 전부 빈 캐시
/// → 다음 스캔이 전체 스캔이다(캐시는 항상 재구성 가능한 파생물이라 예외를 던지지 않는다).
///
/// v0.2.37 이하의 단일 파일(베이스 자리, 문자열 키 7.6MB)은 읽지 않고 **지운다**: 새 세대는 다른 파일명을 쓰므로 어차피
/// 로드되지 않고, 남겨 두면 디스크만 차지한다. 다운그레이드도 안전하다 — 옛 버전은 베이스 파일이 없으면 전체 스캔하고,
/// 새 파일들은 건드리지 않는다(같은 파일을 두 세대가 다르게 해석해 과소집계하는 사고가 이 이름 분리로 막힌다).
enum TokenUsageCacheStore {
    /// 레이아웃 세대. 핫 파일의 값이 이와 다르면 두 파일 모두 폐기(→ 1회 전체 재스캔). 옛 단일 파일엔 이 키가 없다(= 0).
    /// 1: v0.2.38 — 해시 키 + 핫/콜드 분리 + 48h 보관 경계.
    static let currentSchemaVersion = 1

    /// 어느 파일이 더러워졌는가(저장 대상). 스캐너 Stats 가 채우고 스토어가 누적한다.
    struct Parts: OptionSet, Sendable, Equatable {
        let rawValue: UInt8
        /// 핫: claudeFileStates / codexFileStates.
        static let state = Parts(rawValue: 1)
        /// 콜드: claudeEntries.
        static let entries = Parts(rawValue: 2)
        static let all: Parts = [.state, .entries]
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("aing-check/token-usage-cache.json", isDirectory: false)
    }

    static func stateURL(for base: URL) -> URL {
        base.deletingPathExtension().appendingPathExtension("state.json")
    }

    static func entriesURL(for base: URL) -> URL {
        base.deletingPathExtension().appendingPathExtension("entries.json")
    }

    /// 핫 파일 봉투. state 는 모놀리식 TokenUsageCache 인코딩(엔트리는 비워 넣는다).
    private struct StateFile: Codable {
        var schemaVersion: Int
        var state: TokenUsageCache
    }

    /// 두 파일이 다 있고 세대가 맞을 때만 캐시. 그 외엔 빈 캐시(첫 실행 = 전체 스캔). 옛 단일 파일이 있으면 지운다.
    static func load(from base: URL) -> TokenUsageCache {
        removeLegacyFile(at: base)
        guard let stateData = try? Data(contentsOf: stateURL(for: base)),
              let envelope = try? JSONDecoder().decode(StateFile.self, from: stateData),
              envelope.schemaVersion == currentSchemaVersion,
              let entriesData = try? Data(contentsOf: entriesURL(for: base)),
              let rawEntries = try? JSONDecoder().decode([String: ClaudeEntry].self, from: entriesData),
              let entries = Dictionary.fromHexKeyed(rawEntries, strict: true)
        else { return TokenUsageCache() }
        var cache = envelope.state
        cache.claudeEntries = entries
        return cache
    }

    /// parts 에 든 파일(과 아직 디스크에 없는 파일)을 원자적으로 쓴다. 콜드 → 핫 순서이고, 콜드 쓰기가 실패하면 핫은
    /// 건드리지 않는다(위 과소집계 불변식). 반환은 요청한 부분이 전부 써졌는가.
    @discardableResult
    static func save(_ cache: TokenUsageCache, parts requested: Parts, to base: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        var parts = requested
        if !fm.fileExists(atPath: entriesURL(for: base).path) { parts.insert(.entries) }
        if !fm.fileExists(atPath: stateURL(for: base).path) { parts.insert(.state) }

        if parts.contains(.entries) {
            guard let data = try? JSONEncoder().encode(cache.claudeEntries.hexKeyed),
                  (try? data.write(to: entriesURL(for: base), options: .atomic)) != nil
            else { return false }
        }
        if parts.contains(.state) {
            var hot = cache
            hot.claudeEntries = [:]
            guard let data = try? JSONEncoder().encode(StateFile(schemaVersion: currentSchemaVersion, state: hot)),
                  (try? data.write(to: stateURL(for: base), options: .atomic)) != nil
            else { return false }
        }
        return true
    }

    /// v0.2.37 이하의 단일 파일 제거(있을 때만). 실패는 무시한다 — 다음 로드에서 다시 시도된다.
    private static func removeLegacyFile(at base: URL) {
        guard FileManager.default.fileExists(atPath: base.path) else { return }
        try? FileManager.default.removeItem(at: base)
    }
}

// MARK: - 증분 스캐너 (순수 · nonisolated, 백그라운드 실행)

/// 로컬 AI CLI 로그를 "증분"으로 집계한다. 캐시(파일상태+엔트리)를 받아, 바뀐 파일의 새 바이트만 이어읽고,
/// 갱신된 캐시 + 현재 KST 월 집계 + 계측을 돌려준다. 상태 없는 순수 로직이라 Task.detached 에서 돈다.
///
/// 월 귀속(핵심 개편):
/// - Claude: 엔트리 ts14(UTC 초) 를 KST(UTC+9)로 본 달력 월에 귀속. 현재 월 = [이번달 1일 0시 KST, 다음달 1일 0시 KST).
/// - Codex: token_count 이벤트마다 그 이벤트 timestamp(→KST)로 delta 를 월/일에 귀속(파일 mtime 월 통째 귀속 폐기 —
///   resume 세션이 지난달 누적을 이번 달로 편입하던 +수십억 이상치를 근절). 파일별 기준선(prevCumulative)으로 delta 를 잇되,
///   **파일을 처음부터 파싱할 때의 첫 유효 이벤트는 델타가 아니라 기준선**이다(CodexFileProgress 주석의 실측 근거 참고).
/// - 집계는 현재 KST 월만. 엔트리 보관은 [월 시작 − 48h, ∞) — 월 경계를 걸치는 세션(월말 밤에 시작해 월초 새벽까지
///   이어지는 스트리밍 스냅샷·포크 복제)의 dedupe 만 남기고 그 이전은 퇴거한다. v0.2.37 까지는 직전 월 1일부터 보관해
///   엔트리의 73% 가 지난달 것이었다(≈11MB 상주). 같은 (id, requestId) 라인들은 초~분 간격으로 찍히므로 48h 면 넉넉하다.
///
/// 증분 절차(파일마다):
/// - 디렉터리 워크 + stat → mtime 프리필터(현재 월 시작 이전 파일 통째 스킵).
/// - size·mtime 동일 → 무변경, 재읽기 0.
/// - 커졌으면(append) consumedOffset 부터 tail 만 스트리밍 — 오프셋은 항상 마지막 "완결 라인"(개행) 끝으로 저장.
/// - 줄어들었거나 mtime 역행이면 그 파일 전체 재파싱(오프셋 0). 엔트리는 dedupe 키라 재삽입 무해.
///   (주의: 재파싱 후에도 사라진 라인의 엔트리는 맵에 잔류할 수 있다 — append-only 로그에선 드물고 실사용상 무시 가능.)
/// - 합계는 엔트리 맵을 현재 월로 필터해 재계산(3만 건 순회 sub-ms).
///
/// 프라이버시(핵심 규약): 대화 본문·프롬프트·툴 결과 등 "내용" 필드는 절대 읽거나 보관하지 않는다.
/// 라인당 보는 것은 usage 숫자·message.id·requestId·timestamp·payload.type 뿐이고, 캐시/스냅샷에도 숫자만 남는다.
enum TokenUsageIncrementalScanner {
    /// KST 고정 캘린더(+9, 한국은 DST 없음). "ts14(UTC) + 9시간 = KST" 규약과 일치한다.
    private static let kstCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return c
    }()

    /// UTC 고정 캘린더. Codex 이벤트 timestamp(UTC ISO)를 컴포넌트로 조립해 절대 Date 로 만들 때 쓴다(그 뒤 KST 로 재해석).
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 엔트리/파일상태 보관 하한이 월 시작에서 얼마나 앞서는가. 월 경계 straddle 을 덮되 지난달 본체는 들지 않는 폭(48h).
    /// KST 는 DST 가 없어 48h 는 정확히 이틀이다.
    static let retentionSlack: TimeInterval = 48 * 3_600

    /// 주어진 시각이 속한 KST 달력 월의 경계(절대 시각)와 'YYYY-MM' 문자열, 보관 하한.
    /// start = 이번달 1일 0시 KST, end = 다음달 1일 0시 KST, retentionStart = start − 48h(그 이전 ts14/mtime 은 퇴거).
    static func monthBounds(now: Date) -> (start: Date, end: Date, retentionStart: Date, month: String) {
        let cal = kstCalendar
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps)!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        let retentionStart = start.addingTimeInterval(-retentionSlack)
        let month = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        return (start, end, retentionStart, month)
    }

    /// 주어진 시각의 KST 달력 월 'YYYY-MM'. 스토어가 복원 스냅샷의 월 일치 판정에 쓴다.
    static func kstMonthString(_ date: Date) -> String { monthBounds(now: date).month }

    /// 주어진 시각이 속한 KST 달력 '하루'의 경계(절대 시각)와 'YYYY-MM-DD' 문자열.
    /// start = 오늘 0시 KST, end = 내일 0시 KST. (KST 자정 = UTC 전날 15:00 — "오늘 +N" 창의 하한/상한.)
    /// 오늘은 항상 현재 월의 부분집합이라, 오늘 합은 월 필터 루프 안에서 겹쳐 계산된다.
    static func dayBounds(now: Date) -> (start: Date, end: Date, date: String) {
        let cal = kstCalendar
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        let date = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        return (start, end, date)
    }

    /// 증분 갱신 계측(테스트/실증용). 재읽기 바이트·읽은 파일 수와 캐시 변경 여부를 보고한다.
    struct Stats: Equatable, Sendable {
        var claudeFilesStatted = 0
        var claudeFilesRead = 0
        var claudeBytesRead = 0
        var codexFilesStatted = 0
        var codexFilesRead = 0
        var codexBytesRead = 0
        /// 콜드(엔트리 맵)에 실제 변경(추가·교체·ts 승격·퇴거)이 있었는가.
        var entriesChanged = false
        /// 핫(claude/codex 파일 진행 상태)에 실제 변경(갱신·롤오버·정리·퇴거)이 있었는가.
        var statesChanged = false
        /// 캐시 어디든 변경이 있었는가. false 면 저장할 것이 없다.
        var cacheChanged: Bool { entriesChanged || statesChanged }
        /// 저장 대상 파일(스토어의 dirty 누적에 그대로 합쳐진다).
        var changedParts: TokenUsageCacheStore.Parts {
            var p = TokenUsageCacheStore.Parts()
            if entriesChanged { p.insert(.entries) }
            if statesChanged { p.insert(.state) }
            return p
        }
    }

    struct Result: Sendable {
        var cache: TokenUsageCache
        var usage: TokenUsageMonthly
        var stats: Stats
    }

    // 라인 프리체크용 바이트 패턴(String 생성 없이 원시 바이트 부분검색). 디코드 비용을 매칭 라인으로만 한정한다.
    private static let usagePattern = Array(#""usage""#.utf8)
    private static let assistantPattern = Array(#""assistant""#.utf8)
    private static let tokenCountPattern = Array("token_count".utf8)

    /// 캐시를 받아 증분 갱신한 결과를 돌려준다. 빈 캐시를 주면 전체 스캔과 동일(첫 실행 경로).
    /// codexHome: 로그인 셸의 `CODEX_HOME` 이 있으면 그 경로(스토어가 CodexAccountUsageProbe 의 캐시된 셸 환경에서 넘긴다).
    /// nil 이면 `~/.codex`. 그 아래 `sessions/` 와 `archived_sessions/` 두 루트를 읽는다.
    static func update(_ input: TokenUsageCache, homeDirectory: URL, codexHome: URL? = nil, now: Date = Date()) -> Result {
        var cache = input
        var stats = Stats()

        // 현재 KST 월 경계. 합계 창 = [monthStart, monthEnd), 스캔 프리필터 컷오프 = monthStart,
        // 퇴거(보관) 경계 = retentionStart(월 시작 − 48h; 월 경계 straddle 만 남기고 지난달 본체는 들지 않는다).
        let (monthStart, monthEnd, retentionStart, monthString) = monthBounds(now: now)
        let monthStartTs14 = ts14(from: monthStart)
        let monthEndTs14 = ts14(from: monthEnd)
        let retentionTs14 = ts14(from: retentionStart)
        let retentionMicros = micros(from: retentionStart)

        // 오늘(KST) 일키. 두 트랙 모두 일별 맵(KST 'YYYY-MM-DD')을 만들고 오늘분은 그 맵의 오늘 키로 파생한다 —
        // Claude 는 엔트리 ts14 를 아래 일 버킷 경계로 가르고, Codex 는 이벤트 timestamp 의 KST 일키를 파일별 dayContrib 에 쌓는다.
        let todayDate = dayBounds(now: now).date
        let dayBuckets = kstDayBuckets(monthStart: monthStart, monthEnd: monthEnd)

        // 1) 퇴거(로드 시점): 보관 하한 밖 엔트리/파일상태 제거. 무언가 지워지면 캐시 변경으로 표시(저장 유도).
        evict(&cache, evictTs14: retentionTs14, evictMicros: retentionMicros, stats: &stats)

        // 2) 소스별 증분 스캔(프리필터 컷오프 = 현재 월 시작). Codex 는 이벤트 월/일 귀속을 위해 현재 월키를 받는다.
        scanClaude(&cache, homeDirectory: homeDirectory, cutoff: monthStart, evictTs14: retentionTs14, stats: &stats)
        scanCodex(
            &cache, roots: codexRoots(homeDirectory: homeDirectory, codexHome: codexHome),
            cutoff: monthStart, monthString: monthString, stats: &stats
        )

        // 3) 합계 재계산(엔트리 맵 현재-월 필터 + codex 파일상태 monthKey==현재월 필터). 일별 맵은 같은 순회에서 만들고
        //    오늘분은 두 맵의 오늘 키 합으로 파생한다.
        let usage = totals(
            cache, month: monthString,
            monthStartTs14: monthStartTs14, monthEndTs14: monthEndTs14,
            dayBuckets: dayBuckets, todayDate: todayDate
        )
        return Result(cache: cache, usage: usage, stats: stats)
    }

    /// Codex rollout 루트 두 곳. `sessions/YYYY/MM/DD/rollout-*.jsonl`(진행 중) 과 `archived_sessions/rollout-*.jsonl`(보관 — 평면
    /// 디렉터리). Codex CLI 는 채팅을 보관하면 파일을 `std::fs::rename` 으로 후자로 **옮기고**(mtime 보존), v0.2.40 까지의 스캐너는
    /// 전자만 봐서 옮겨진 파일의 이번 달 기여를 "사라진 파일"로 지웠다(issue #6 의 46% 과소집계). 파일 수 0 인 루트는
    /// 열거자가 아무것도 내지 않아 비용 0 이다.
    static func codexRoots(homeDirectory: URL, codexHome: URL?) -> [URL] {
        let base = codexHome ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        return [
            base.appendingPathComponent("sessions", isDirectory: true),
            base.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
    }

    /// 현재 월의 KST 일 버킷: (그 날 0시의 UTC ts14, 'YYYY-MM-DD') 오름차순. Claude 엔트리의 ts14 를 일자로 가르는 데 쓴다 —
    /// 엔트리마다 Calendar 를 부르지 않고(3만 건), 최대 31개 경계를 이진 탐색한다. 마지막 원소의 상한은 monthEnd 다.
    static func kstDayBuckets(monthStart: Date, monthEnd: Date) -> [(startTs14: Int, key: String)] {
        var out: [(startTs14: Int, key: String)] = []
        var day = monthStart
        while day < monthEnd {
            out.append((ts14(from: day), dayBounds(now: day).date))
            guard let next = kstCalendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: Claude Code

    /// ~/.claude/projects/**/*.jsonl. type=="assistant" + usage 라인을 (message.id, requestId) 로 글로벌 dedupe.
    private static func scanClaude(
        _ cache: inout TokenUsageCache, homeDirectory: URL, cutoff: Date, evictTs14: Int, stats: inout Stats
    ) {
        let root = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        // 워크/stat 는 클로저 밖에서(엔트리 맵을 캡처하는 tail 클로저와 배타적 접근이 겹치지 않게).
        let files = recentFiles(under: root, cutoff: cutoff, matching: { $0.pathExtension == "jsonl" })
        for f in files {
            stats.claudeFilesStatted += 1
            let path = f.url.path
            let prior = cache.claudeFileStates[path]
            // 무변경(크기·mtime 동일) → 재읽기 0.
            if let p = prior, p.size == f.size, p.mtimeMicros == f.mtimeMicros { continue }
            // 성장(append)이면 이어읽기, 그 외(신규/축소/mtime 역행)면 전체 재파싱(오프셋 0).
            let startOffset: Int
            if let p = prior, f.size >= p.size, f.mtimeMicros >= p.mtimeMicros {
                startOffset = p.consumedOffset
            } else {
                startOffset = 0
            }
            var entriesTouched = false
            guard let read = readTail(at: f.url, from: startOffset, { line in
                ingestClaudeLine(line, into: &cache, evictTs14: evictTs14, changed: &entriesTouched)
            }) else { continue }
            stats.claudeFilesRead += 1
            stats.claudeBytesRead += read.bytesRead
            cache.claudeFileStates[path] = FileProgress(
                size: f.size, mtimeMicros: f.mtimeMicros, consumedOffset: read.consumedOffset
            )
            stats.statesChanged = true
            if entriesTouched { stats.entriesChanged = true }
        }
    }

    /// 한 Claude 라인을 파싱해 dedupe 키로 엔트리 맵에 넣는다(포크 복제는 같은 키라 한 번만 계상).
    /// changed 는 엔트리 맵이 실제로 바뀌었을 때만 true 로 세운다(같은 값 재관측은 무변경).
    private static func ingestClaudeLine(
        _ line: UnsafeRawBufferPointer, into cache: inout TokenUsageCache, evictTs14: Int, changed: inout Bool
    ) {
        // 프리체크: "usage"(assistant 라인에만) → "assistant". 둘 다 있어야 디코드(대다수 라인 조기 배제).
        guard contains(line, usagePattern), contains(line, assistantPattern) else { return }
        // 라인마다 autoreleasepool: JSONSerialization 이 만드는 브리지 임시 객체(수 KB content 문자열 포함)를 그 라인
        // 안에서 돌려준다. 첫 스캔은 유틸리티 태스크에서 수십~수백 MB 를 연달아 파싱하므로, 풀 없이는 풀이 언제 비워지느냐가
        // peak footprint 를 정한다(v0.2.37 실측 peak 405MB). 프리체크를 통과한 라인에만 씌워 비용을 매칭 라인으로 한정한다.
        autoreleasepool {
            guard let base = line.baseAddress,
                  // 복사 없이 라인 버퍼를 그대로 파서에 넘긴다(파서는 동기·읽기 전용이라 수명이 이 호출 안에서 끝난다).
                  let object = try? JSONSerialization.jsonObject(
                      with: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: line.count, deallocator: .none)
                  ) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let timestamp = object["timestamp"] as? String,
                  let message = object["message"] as? [String: Any],
                  let usageObject = message["usage"] as? [String: Any],
                  let ts = ts14(fromTimestampPrefix: timestamp)
            else { return }
            // 보관 하한(월 시작 − 48h) 밖은 아예 저장하지 않는다 — 엔트리 맵을 현재 월 + straddle 규모로 유지. 합계 창 필터는 별도(현재 월).
            guard ts >= evictTs14 else { return }
            let key = ClaudeEntryKey(
                messageID: message["id"] as? String ?? "", requestID: object["requestId"] as? String ?? ""
            )
            ingest(
                key: key, ts: ts, usageObject: usageObject, into: &cache.claudeEntries, changed: &changed
            )
        }
    }

    /// 엔트리 맵 갱신 규칙(max-output wins · max-ts 유지). 파싱과 분리해 autoreleasepool 안을 짧게 유지한다.
    private static func ingest(
        key: ClaudeEntryKey, ts: Int, usageObject: [String: Any],
        into entries: inout [ClaudeEntryKey: ClaudeEntry], changed: inout Bool
    ) {
        // "키별로 output_tokens 최대치 채택"(max-output wins, 같으면 기존 유지). 한 assistant 메시지는 스트리밍 중
        // 같은 (id,requestId)로 여러 번 기록되며 이 중복 라인들은 진행 스냅샷이라 output_tokens 가 점증한다
        // (실측: [2,2,688], [7,7,7,7,343] — 마지막이 그 요청의 최종값). 따라서 "첫 값 채택"은 출력을 ~3.67배
        // 과소집계한다(실측 오라클: output 35.86M vs 첫값 9.77M). 최종 스냅샷의 값이 최종 진실이므로 최대 output
        // 라인의 input/cacheRead/cacheCreation·ts14 도 함께 그 레코드로 교체한다.
        // last-wins 가 아니라 max-output wins 인 이유: 파일 간 순서(포크 복제)와 증분 갱신(이어읽기) 순서에
        // 무관하게 결정적이다 — 어느 순서로 들어와도 최대 output 이 이기므로 결과가 같다.
        // (증분 일관: 1차에 [output=2]를 캐시에 넣었어도 다음 tail 에서 같은 키 [output=688]을 만나면 교체된다.)
        let output = intField(usageObject["output_tokens"])
        // 월/퇴거 판정 ts 는 이 키에서 '관측한 최대 ts14'를 유지한다(max-output 이 이긴 레코드의 ts 가 아니라).
        // 트레이드오프: max-output 값이 지난달 라인에서 왔더라도, 같은 키의 더 최신 라인이 이번달이면 그 값을 이번달로
        // 계상한다(드문 reverse-straddle 에서 소폭 과다). 지난달 옛 스냅샷이 이번달 키를 통째로 탈락시키는
        // 과소집계보다 안전한 쪽을 택한다. 어느 순서로 들어와도 max(output)·max(ts) 라 결과는 결정적이다.
        if var existing = entries[key] {
            let windowTs14 = max(existing.ts14, ts)
            if existing.output >= output {
                // output 은 안 바뀌어도 더 최신 라인을 봤으면 월 판정 ts 만 끌어올린다(대입만, 값은 유지).
                if windowTs14 != existing.ts14 {
                    existing.ts14 = windowTs14
                    entries[key] = existing
                    changed = true
                }
                return
            }
            // max-output 교체: 값(input/cache 포함)은 이 레코드로, 월 판정 ts 는 관측 최대치로.
            entries[key] = ClaudeEntry(
                ts14: windowTs14,
                input: intField(usageObject["input_tokens"]),
                output: output,
                cacheRead: intField(usageObject["cache_read_input_tokens"]),
                cacheCreation: intField(usageObject["cache_creation_input_tokens"])
            )
            changed = true
            return
        }
        entries[key] = ClaudeEntry(
            ts14: ts,
            input: intField(usageObject["input_tokens"]),
            output: output,
            cacheRead: intField(usageObject["cache_read_input_tokens"]),
            cacheCreation: intField(usageObject["cache_creation_input_tokens"])
        )
        changed = true
    }

    // MARK: Codex

    /// `<codexHome>/sessions/**/rollout-*.jsonl` + `<codexHome>/archived_sessions/rollout-*.jsonl`. 각 파일을 줄 단위로
    /// 이어읽으며 token_count 이벤트마다 delta 를 그 이벤트의 timestamp(→KST) 월/일에 귀속한다.
    /// delta 는 **필드별**(input_tokens(캐시 포함)·output_tokens·cached_input_tokens 각각) `max(0, cum − 기준선)`.
    /// **오프셋 0 부터 새로 파싱할 때 그 파일의 첫 유효 이벤트는 델타를 만들지 않고 기준선만 세운다**(그 누적치는
    /// 직전 세션에서 이어받은 카운터지 이번에 쓴 양이 아니다 — 근거는 CodexFileProgress 주석의 프로덕션 실측).
    /// info null·total 결손·timestamp 파싱 실패 이벤트는 건너뛰되 기준선을 갱신하지 않는다 — 건너뛴 토큰은 다음
    /// 유효 이벤트의 delta 에 자연 흡수(유실 없음). 누적이 줄면 max(0,…) 로 클램프(리셋 방어). 월 롤오버 시 월 기여·일별 맵 리셋.
    private static func scanCodex(
        _ cache: inout TokenUsageCache, roots: [URL], cutoff: Date,
        monthString: String, stats: inout Stats
    ) {
        let files = roots.flatMap { root in
            recentFiles(
                under: root, cutoff: cutoff,
                matching: { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
            )
        }
        scanCodexFiles(&cache, files: files, roots: roots, monthString: monthString, stats: &stats)
    }

    /// 열거된 파일 목록으로 codex 상태를 갱신한다(열거와 분리한 이유: 테스트가 "열거 뒤 옮겨진 파일" — 목록엔 있는데 읽을 수
    /// 없는 경로 — 를 손으로 만든 목록으로 재현할 수 있게. 실제 순회에선 두 루트를 차례로 열거하는 사이에 보관(rename)이
    /// 일어나면 정확히 그 모양이 된다).
    static func scanCodexFiles(
        _ cache: inout TokenUsageCache, files: [(url: URL, size: Int, mtimeMicros: Int)], roots: [URL],
        monthString: String, stats: inout Stats
    ) {
        // 이번 순회에서 **실제로 확인한** 경로(무변경 스킵 또는 읽기 성공). 아래 "사라진 파일 정리"가 이 집합을 쓴다.
        // 열거 직후가 아니라 읽기 성공 뒤에 넣는 것이 요건이다(리뷰 P2): 열거와 읽기 사이에 보관(rename)된 파일은 옛 경로 읽기가
        // 실패해 옛 상태가 그대로 남는데, 그것을 '본 것'으로 치면 정리를 건너뛰어 새 경로 상태와 함께 **정확히 두 배**로 잡히고
        // 배경 경로에선 그 값이 곧바로 업로드된다. 읽기 실패 경로는 정리 규칙(존재 확인 → .zst 확인)에 그대로 맡긴다.
        //
        // 무변경 스킵 분기는 파일을 열지 않으므로 '읽기 실패'가 없다 — 그런데 보관은 mtime 을 보존하는 rename 이라 열거가 준
        // stat 은 옛 상태와 **같다**(= 그 분기를 탄다). 그래서 같은 이름이 두 루트 목록에 함께 있으면(rollout 이름에 UUID 가 있어
        // 정상 상태에선 있을 수 없다) 한쪽은 열거 뒤 옮겨진 낡은 항목이다 — 그 경우에만 존재를 확인하고 없으면 seen 으로 치지
        // 않는다(정리 규칙이 지운다). 평상시엔 이름 집계 한 번뿐이라 stat 이 늘지 않는다.
        var seenPaths = Set<String>()
        var nameCounts: [String: Int] = [:]
        for f in files { nameCounts[f.url.lastPathComponent, default: 0] += 1 }
        for f in files {
            stats.codexFilesStatted += 1
            let path = f.url.path
            let prior = cache.codexFileStates[path]

            // 파일별 상태 시작값. 이어읽기면 직전 상태를 잇고, 신규/축소/역행이면 처음부터(0). 월 롤오버는 키가 바뀐
            // 월 기여·일별 맵을 0/빈 맵으로 리셋하되 기준선은 유지(누적 카운터는 파일 안에서 계속 이어진다).
            var startOffset = 0
            // 델타 기준선 = 직전 유효 token_count 의 누적치 세 갈래. nil 은 "이 파일에서 아직 기준선을 본 적이 없다"로,
            // "기준선이 0이다"와 **반드시 구분해야 한다** — 그 구분이 첫 관측을 델타로 만들지 않는 규칙의 전부다.
            // (영속 필드를 새로 만들지 않는다: 캐시에는 관측된 기준선만 들어가고, 미관측 상태는 offset 0 이 표현한다.)
            var baseline: (input: Int, output: Int, cached: Int)?
            var monthInput = 0
            var monthOutput = 0
            var monthCached = 0
            var dayContrib: [String: Int] = [:]

            if let p = prior {
                let sameMonth = (p.monthKey == monthString)

                // 무변경(크기·mtime 동일): 파일 재읽기는 없다. 다만 월이 넘어갔으면 월 기여·일별 맵을 리셋하고 키만 갱신한다
                // (안 그러면 지난달 누적이 이번달 표시로 샌다). 월이 그대로면 완전 무변경이라 스킵(캐시 변경 없음) —
                // 일 롤오버는 더 이상 상태를 건드리지 않는다(일별 맵이 날짜를 키로 들고 있어 오늘 값이 저절로 0 이다).
                if p.size == f.size, p.mtimeMicros == f.mtimeMicros {
                    if nameCounts[f.url.lastPathComponent, default: 0] > 1, !FileManager.default.fileExists(atPath: path) {
                        continue   // 열거 뒤 다른 루트로 옮겨진 낡은 항목 — 옛 상태는 아래 정리 규칙이 지운다.
                    }
                    seenPaths.insert(path)
                    if !sameMonth {
                        cache.codexFileStates[path] = CodexFileProgress(
                            size: p.size, mtimeMicros: p.mtimeMicros, consumedOffset: p.consumedOffset,
                            prevInput: p.prevInput, prevOutput: p.prevOutput, prevCached: p.prevCached,
                            monthKey: monthString, monthInput: 0, monthOutput: 0, monthCached: 0,
                            dayContrib: [:]
                        )
                        stats.statesChanged = true
                    }
                    continue
                }
                // 성장(append)이면 이어읽기 + 직전 상태 이월, 그 외(축소/역행)면 전체 재파싱(offset 0 + 기여/기준선 리셋).
                //
                // 압축이 풀린 파일(materialize: `.zst` → `.jsonl` 복원, `.zst` 삭제)도 이 규칙을 그대로 탄다: 되살아난 내용은
                // 압축 전과 **바이트 동일**하므로 크기가 같고 mtime 이 같거나 새롭다 → 무변경 스킵이거나 오프셋 이어읽기(새 바이트 0)
                // 라 이중 계상이 없다. 내용이 줄었거나 mtime 이 역행했다면 전체 재파싱 규칙이 맞다 — 첫 이벤트가 기준선이 되어
                // 그 파일의 이번 달 델타 합이 압축 전 값으로 재구성된다.
                if f.size >= p.size, f.mtimeMicros >= p.mtimeMicros {
                    startOffset = p.consumedOffset
                    // 이어읽기 경로: 캐시의 prev* 가 이미 유효한 기준선이다(값이 0 이어도 '관측된 0'이다).
                    // 그래서 이 경로의 동작은 첫-관측 규칙 도입으로 바뀌지 않는다.
                    // 예외는 consumedOffset == 0 뿐이다 — 완결 라인을 하나도 소비하지 못했다는 뜻이고(이벤트 라인을
                    // 읽었다면 그 줄의 개행까지 소비돼 offset > 0), 곧 기준선을 세운 적이 없다는 뜻이라 nil 로 되돌린다.
                    baseline = p.consumedOffset > 0 ? (p.prevInput, p.prevOutput, p.prevCached) : nil
                    if sameMonth {
                        monthInput = p.monthInput
                        monthOutput = p.monthOutput
                        monthCached = p.monthCached
                        dayContrib = p.dayContrib
                    }
                }
            }

            guard let read = readTail(at: f.url, from: startOffset, { line in
                guard contains(line, tokenCountPattern) else { return }
                guard let base = line.baseAddress,
                      let object = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count)) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any]
                else { return }   // info null·total 결손: 건너뛰되 기준선 갱신 안 함(다음 유효 이벤트가 흡수).
                // 이벤트 timestamp(UTC ISO)를 KST 월키/일키로. 파싱 실패도 동일하게 건너뜀(기준선 불변 → 흡수).
                guard let ts = object["timestamp"] as? String,
                      let keys = kstMonthDayKeys(fromTimestamp: ts) else { return }
                let input = intField(total["input_tokens"])
                let output = intField(total["output_tokens"])
                let cached = intField(total["cached_input_tokens"])
                // 첫 관측(baseline == nil)은 델타를 만들지 않고 기준선만 세운다 — 그 누적치는 "카운터가 이미 거기 와
                // 있었다"는 정보이지 이번에 쓴 양이 아니다(실측 근거는 CodexFileProgress 주석).
                if let prev = baseline {
                    // 필드별 클램프: 누적 감소(리셋)면 그 필드만 0. 캐시는 입력의 부분집합이라 월 합계에서 따로 더하지 않는다.
                    let dIn = max(0, input - prev.input)
                    let dOut = max(0, output - prev.output)
                    let dCached = max(0, cached - prev.cached)
                    if keys.month == monthString {
                        monthInput += dIn
                        monthOutput += dOut
                        monthCached += dCached
                        // 일별 맵은 현재 월 키만 담는다(월 롤오버에 통째로 비우므로 다른 달 키가 섞이면 안 된다).
                        if dIn + dOut > 0 { dayContrib[keys.day, default: 0] += dIn + dOut }
                    }
                }
                baseline = (input, output, cached)
            }) else { continue }
            seenPaths.insert(path)
            stats.codexFilesRead += 1
            stats.codexBytesRead += read.bytesRead

            // 기준선을 못 세운 채 끝난 파일(= 이번 읽기에서 유효 token_count 가 하나도 없었다: 헤더/히스토리만 쓰인
            // 갓 만들어진 rollout)은 **오프셋을 전진시키지 않는다.** 전진시키면 다음 이어읽기가 "관측된 기준선 0"을
            // 물려받아, 그때 처음 만나는 이벤트의 누적치 전액이 델타가 된다 — 이 커밋이 없애려는 결함이 그대로 되살아난다.
            // (baseline == nil 이면 이번 읽기는 반드시 offset 0 전체 파싱이었으므로 startOffset 도 0 이다.)
            // 비용은 그 파일이 다음에 자랐을 때 한 번 더 처음부터 읽는 것뿐이고, 크기·mtime 이 그대로면 아예 스킵된다.
            let persistedOffset = (baseline == nil) ? startOffset : read.consumedOffset
            cache.codexFileStates[path] = CodexFileProgress(
                size: f.size, mtimeMicros: f.mtimeMicros, consumedOffset: persistedOffset,
                prevInput: baseline?.input ?? 0, prevOutput: baseline?.output ?? 0, prevCached: baseline?.cached ?? 0,
                monthKey: monthString, monthInput: monthInput, monthOutput: monthOutput, monthCached: monthCached,
                dayContrib: dayContrib
            )
            stats.statesChanged = true
        }

        // ── 사라진 파일 정리(과다계상의 실제 원인) + 압축 파일 동결(과소집계의 실제 원인) ─────────────────────
        //
        // totals() 는 캐시에 남아 있는 **모든** codex 파일 상태의 month* 를 더한다. 그런데 파일이 그 경로에서
        // 사라져도(삭제·이동) 상태는 캐시에 남는다 — evict 는 mtime 이 보관 하한보다 오래된 것만 지우므로 이번 달
        // 기여는 그 달 내내 살아남는다. 그래서 증분 값이 **전량 재파싱보다 계속 커진다.** 재현(차분 테스트):
        // 파일 하나를 다른 경로로 옮기면 옛 키와 새 키가 함께 더해져 그 파일 몫이 **정확히 두 배**가 된다.
        //
        // 판정이 정확한 이유: monthKey == 현재 월 인 상태는 마지막 갱신 때 mtime 프리필터(cutoff = 이번 달 시작)를
        // 통과한 파일이고 mtime 은 되돌지 않는다 — 그 파일이 아직 그 경로에 있다면 이번 순회에도 반드시 잡힌다.
        // 그러므로 "이번 달 키인데 이번 순회에 없다" = 그 경로에 더는 없다. 순회가 I/O 오류로 놓쳤을 가능성만
        // fileExists 로 한 번 더 확인한다(후보가 있을 때만 도는 stat 이라 평상시 비용 0).
        // 다른 달 키의 상태는 이번 달 합계에 안 들어가므로 건드리지 않는다(프리필터 밖이라 순회에도 안 잡힌다 —
        // 여기서 지우면 재개된 세션의 이어읽기 기준선을 헛되이 버린다). 그쪽은 evict 가 mtime 으로 맡는다.
        //
        // **`.zst` 가 있으면 지우지 않는다(동결).** Codex CLI 는 mtime 이 7일 넘게 안 바뀐 rollout 을 백그라운드에서
        // `rollout-….jsonl.zst` 로 zstd 압축하고 **원본 `.jsonl` 을 삭제**한다(sessions/·archived_sessions/ 둘 다;
        // codex-rs/rollout/src/compression.rs). macOS SDK 엔 zstd 디코더가 없어 `.zst` 는 읽을 수 없지만, 그 파일의
        // 이번 달 기여는 압축 전에 이미 캐시에 있다 — 지우면 그 몫이 통째로 사라지고, 압축은 7일만 지나면 일어나므로
        // 한 달 내내 누수가 생긴다(issue #6 의 46% 과소집계가 정확히 이것이었다). 그래서 `<path>.zst` 가 남아 있는 상태는
        // 그대로 두어 기여를 보존하고 더 자라지 않게 둔다(순회에 안 잡히니 갱신도 없다). 세션을 다시 이어 쓰면 Codex 가
        // `.zst` 를 풀어 `.jsonl` 로 되돌리는데(materialize; `.zst` 삭제), 그때부터는 위 이어읽기 규칙이 그대로 동작한다.
        // 월이 바뀌면 monthKey 가 어긋나 합계에서 자연 탈락하고, 보관 하한이 지나면 evict 가 mtime 으로 지운다.
        //
        // 보관(rename → archived_sessions/)으로 경로가 바뀐 파일: 옛 경로 상태는 `.jsonl` 도 `.zst` 도 없어 여기서 정리되고,
        // 새 경로는 이번 순회(두 번째 루트)에서 0 부터 파싱되며 첫 이벤트가 기준선이므로 그 파일의 이번 달 델타 합이
        // 전량 재파싱과 **같은 값**으로 재구성된다(비용은 한 번의 재읽기뿐, 이중 계상 없음 — 테스트가 증명한다).
        //
        // **이미 압축된 파일이 옮겨진 경우**(리뷰 P2, codex 소스로 확인): 보관은 `existing_rollout_path` 가 고른 물리 경로를
        // 그대로 rename 하므로 `.jsonl.zst` 는 `archived_sessions/<같은 이름>.zst` 로 가고, 보관 해제는 파일명의 날짜로
        // `sessions/YYYY/MM/DD/<같은 이름>.zst` 로 돌아온다(`rollout_file_name.rs` 가 `.zst` 를 벗겨 파싱한다). 그때 옛 경로엔
        // `.jsonl` 도 `.zst` 도 없어 옛 규칙은 상태를 지웠고 새 경로의 `.zst` 는 읽을 수 없어 그 파일 몫이 통째로 사라졌다.
        // 그래서 동결 사유에 **다른 루트의 동명 `.zst`** 도 넣는다(compressedTwinCandidates). 동명 `.jsonl` 이 다른 루트에
        // 있으면 그것은 이번 순회에 새 키로 파싱됐으니 옛 상태를 지워야 한다(안 지우면 이중 계상) — `.zst` 만 동결이다.
        let beforeStates = cache.codexFileStates.count
        cache.codexFileStates = cache.codexFileStates.filter { path, state in
            if state.monthKey != monthString { return true }
            if seenPaths.contains(path) { return true }
            if FileManager.default.fileExists(atPath: path) { return true }
            return compressedTwinCandidates(for: path, roots: roots).contains { FileManager.default.fileExists(atPath: $0) }
        }
        if cache.codexFileStates.count != beforeStates { stats.statesChanged = true }
    }

    /// 사라진 rollout 경로의 압축 쌍둥이 후보(순수). ① 같은 경로 + `.zst`, ② archived 루트의 `<이름>.zst`(보관),
    /// ③ sessions 루트의 `YYYY/MM/DD/<이름>.zst`(보관 해제 — 날짜는 파일명 `rollout-YYYY-MM-DD…` 에서, codex 의
    /// `rollout_date_parts` 와 같은 규칙). 후보가 있을 때만 stat 하므로 평상시 비용 0. roots 는 codexRoots 의 순서(sessions, archived).
    static func compressedTwinCandidates(for path: String, roots: [URL]) -> [String] {
        var out = [path + ".zst"]
        let name = (path as NSString).lastPathComponent
        guard roots.count >= 2, name.hasPrefix("rollout-") else { return out }
        let sessionsRoot = roots[0]
        let archivedRoot = roots[1]
        let archived = archivedRoot.appendingPathComponent(name + ".zst").path
        if archived != out[0] { out.append(archived) }
        // rollout-YYYY-MM-DD... → YYYY/MM/DD
        let date = name.dropFirst("rollout-".count)
        if date.count >= 10 {
            let y = date.prefix(4), m = date.dropFirst(5).prefix(2), d = date.dropFirst(8).prefix(2)
            if y.allSatisfy(\.isNumber), m.allSatisfy(\.isNumber), d.allSatisfy(\.isNumber) {
                let restored = sessionsRoot.appendingPathComponent("\(y)/\(m)/\(d)/\(name).zst").path
                if !out.contains(restored) { out.append(restored) }
            }
        }
        return out
    }

    // MARK: 합계 / 퇴거

    /// 엔트리 맵을 현재 월 [start,end) 로 필터해 Claude 합계를, codex 파일상태를 monthKey==현재월 로 필터해 Codex 합계를 낸다.
    /// 일별 맵은 같은 순회에서 만든다 — Claude 는 엔트리 ts14 를 KST 일 버킷(dayBuckets, 이진 탐색)으로 갈라 4필드 합을,
    /// Codex 는 파일별 dayContrib(입력+출력 델타)를 날짜 키로 합친다. todayTotal 은 두 맵의 오늘 키 값의 합으로 **파생**한다
    /// (값은 v0.2.40 의 오늘 창 산식과 같다 — 버킷 경계가 dayBounds 와 같은 KST 자정이다).
    /// Codex 월 합계는 필드별: codexInput(캐시 포함 입력)·codexOutput·codexCacheRead(입력의 부분집합, total 에 안 들어감).
    private static func totals(
        _ cache: TokenUsageCache, month: String,
        monthStartTs14: Int, monthEndTs14: Int,
        dayBuckets: [(startTs14: Int, key: String)], todayDate: String
    ) -> TokenUsageMonthly {
        var usage = TokenUsageMonthly(month: month)
        for (_, e) in cache.claudeEntries where e.ts14 >= monthStartTs14 && e.ts14 < monthEndTs14 {
            usage.claudeInput += e.input
            usage.claudeOutput += e.output
            usage.claudeCacheRead += e.cacheRead
            usage.claudeCacheCreation += e.cacheCreation
            // 일별: ts14 가 속한 KST 일 버킷(startTs14 <= ts14 인 마지막 버킷)에 4필드 합을 더한다(월 부분집합).
            if let key = dayKey(for: e.ts14, in: dayBuckets) {
                usage.claudeDaily[key, default: 0] += e.input + e.output + e.cacheRead + e.cacheCreation
            }
        }
        for (_, s) in cache.codexFileStates where s.monthKey == month {
            // 월 집계: 이 파일 상태의 monthKey 가 현재 월일 때만 그 월 delta 합을 더한다(월 롤오버로 키가 어긋난 파일은 자연 탈락).
            usage.codexInput += s.monthInput
            usage.codexOutput += s.monthOutput
            usage.codexCacheRead += s.monthCached
            // 일별: 파일별 맵을 날짜 키로 합친다(어제 시작·오늘 성장 세션도 날짜별로 제자리에 들어간다).
            for (day, delta) in s.dayContrib { usage.codexDaily[day, default: 0] += delta }
        }
        usage.todayTotal = (usage.claudeDaily[todayDate] ?? 0) + (usage.codexDaily[todayDate] ?? 0)
        usage.todayDate = todayDate
        return usage
    }

    /// ts14 가 속한 KST 일 버킷 키. 버킷은 startTs14 오름차순이고 호출측이 이미 월 창으로 걸렀으므로 첫 버킷 이전은 없다(있으면 nil).
    private static func dayKey(for ts14: Int, in buckets: [(startTs14: Int, key: String)]) -> String? {
        var lo = 0
        var hi = buckets.count
        // upper_bound: startTs14 > ts14 인 첫 위치 → 그 앞 원소가 ts14 를 담는 버킷.
        while lo < hi {
            let mid = (lo + hi) / 2
            if buckets[mid].startTs14 <= ts14 { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? buckets[lo - 1].key : nil
    }

    /// 보관 하한(월 시작 − 48h) 밖 엔트리/파일상태를 제거(로드 시점). 무언가 지워지면 해당 부분의 변경 플래그를 세워
    /// 저장을 유도한다(엔트리는 콜드, 파일상태는 핫).
    ///
    /// 파일상태도 같은 하한을 쓴다: mtime 이 월 시작보다 오래된 파일은 프리필터에 걸려 이번 달 순회에 들지 않으므로 그
    /// 상태는 쓸 데가 없다. 지난달 codex 세션이 이번 달 재개되면(mtime 갱신) 오프셋 0 부터 다시 읽지만, 첫 이벤트가
    /// 기준선이 되고 지난달 이벤트 델타는 지난달로 귀속되므로 이번 달 값은 이어읽기와 **같다**(비용은 그 파일 1회 재읽기뿐).
    private static func evict(_ cache: inout TokenUsageCache, evictTs14: Int, evictMicros: Int, stats: inout Stats) {
        let beforeEntries = cache.claudeEntries.count
        cache.claudeEntries = cache.claudeEntries.filter { $0.value.ts14 >= evictTs14 }
        if cache.claudeEntries.count != beforeEntries { stats.entriesChanged = true }
        let beforeClaudeFiles = cache.claudeFileStates.count
        cache.claudeFileStates = cache.claudeFileStates.filter { $0.value.mtimeMicros >= evictMicros }
        let beforeCodexFiles = cache.codexFileStates.count
        cache.codexFileStates = cache.codexFileStates.filter { $0.value.mtimeMicros >= evictMicros }
        if cache.claudeFileStates.count != beforeClaudeFiles || cache.codexFileStates.count != beforeCodexFiles {
            stats.statesChanged = true
        }
    }

    // MARK: 파일 순회 / 스트리밍

    /// root 아래를 재귀 순회하며 matching 통과 + mtime 이 cutoff 이후인 정규 파일 목록을 (url, size, mtimeμs) 로 모은다.
    /// mtime 프리필터: 컷오프(현재 월 시작)보다 오래 손대지 않은 파일은 이번달 항목이 없으므로 열지 않는다(대량 스킵).
    private static func recentFiles(
        under root: URL, cutoff: Date, matching: (URL) -> Bool
    ) -> [(url: URL, size: Int, mtimeMicros: Int)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: nil
        ) else { return [] }
        var out: [(url: URL, size: Int, mtimeMicros: Int)] = []
        for case let url as URL in enumerator {
            guard matching(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            guard let mtime = values.contentModificationDate, mtime >= cutoff else { continue }
            out.append((url, values.fileSize ?? 0, micros(from: mtime)))
        }
        return out
    }

    /// 파일의 [startOffset, EOF) 를 1MB 청크로 읽어 개행 단위 "완결" 라인만 body 로 흘려보낸다.
    /// 반환: (consumedOffset = 마지막 개행 다음 절대 오프셋, bytesRead = 이번에 디스크에서 읽은 바이트).
    /// 개행 없는 꼬리(부분 라인)는 body 로 넘기지도, consumedOffset 을 전진시키지도 않는다 — 다음 갱신에서 완성분만 반영.
    /// startOffset==0 이면 전체 파싱과 동일. 열기/seek 실패면 nil.
    private static func readTail(
        at url: URL, from startOffset: Int, _ body: (UnsafeRawBufferPointer) -> Void
    ) -> (consumedOffset: Int, bytesRead: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        if startOffset > 0 {
            do { try handle.seek(toOffset: UInt64(startOffset)) } catch { return nil }
        }
        // 청크 경계를 걸친 미완결 라인만 이월한다(대개 비어 있어 무복사 경로를 탄다).
        var carry: [UInt8] = []
        var consumed = startOffset   // 마지막 완결 라인(개행) 다음의 절대 오프셋
        var absBase = startOffset    // 현재 청크 시작의 절대 오프셋
        var bytesRead = 0
        let chunkSize = 1 << 20
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            bytesRead += chunk.count
            chunk.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                let count = bytes.count
                var start = 0
                var i = 0
                while i < count {
                    if bytes[i] == 0x0A {
                        if carry.isEmpty {
                            // 라인이 이 청크 안에 온전히 있다 — 복사 없이 부분 버퍼로 넘긴다.
                            body(UnsafeRawBufferPointer(rebasing: raw[start..<i]))
                        } else {
                            // 앞 청크에서 이월된 조각과 이어 붙여 완성한 뒤 넘긴다.
                            carry.append(contentsOf: bytes[start..<i])
                            carry.withUnsafeBytes { body($0) }
                            carry.removeAll(keepingCapacity: true)
                        }
                        consumed = absBase + i + 1
                        start = i + 1
                    }
                    i += 1
                }
                // 개행 없이 남은 꼬리 조각을 다음 청크로 이월한다(소비하지 않음).
                if start < count {
                    carry.append(contentsOf: bytes[start..<count])
                }
                absBase += count
            }
        }
        return (consumed, bytesRead)
    }

    // MARK: 헬퍼

    /// 원시 바이트 버퍼에 짧은 needle 패턴이 들어 있는지(단순 바이트 스캔). Data.range(of:) 브리징 비용을 피한다.
    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        let h = haystack.count
        guard n > 0, h >= n else { return false }
        let first = needle[0]
        let limit = h - n
        var i = 0
        while i <= limit {
            if haystack[i] == first {
                var j = 1
                while j < n, haystack[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    /// JSON 수치 필드를 Int 로. 누락/널/비수치는 0. 대형 합(수십억)을 위해 int64 경유로 안전히 변환한다.
    private static func intField(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        return Int(number.int64Value)
    }

    /// Claude timestamp 문자열의 앞 19자("YYYY-MM-DDTHH:MM:SS")를 YYYYMMDDHHMMSS 정수로. 자릿수가 아니면 nil.
    /// 고정폭 UTC 라 이 정수 비교 == 사전식 비교 == 시간 순서(초 정밀도) — Date 파싱 없이 월 경계를 가른다.
    private static func ts14(fromTimestampPrefix s: String) -> Int? {
        let b = Array(s.utf8)
        guard b.count >= 19 else { return nil }
        // 연(0..3) 월(5,6) 일(8,9) 시(11,12) 분(14,15) 초(17,18) — 나머지 위치는 구분자('-' 'T' ':').
        let idx = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        var val = 0
        for i in idx {
            let c = b[i]
            guard c >= 48, c <= 57 else { return nil }
            val = val * 10 + Int(c - 48)
        }
        return val
    }

    /// Date 를 UTC 기준 YYYYMMDDHHMMSS 정수로(월 경계 접두어와 같은 스케일). KST 월 경계 Date 를 넣으면
    /// 그 절대 시각의 UTC ts14 가 나온다(예: KST 7/1 0시 → UTC 6/30 15:00 → 20260630150000).
    private static func ts14(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
        let h = c.hour ?? 0, mi = c.minute ?? 0, s = c.second ?? 0
        return ((((y * 100 + mo) * 100 + d) * 100 + h) * 100 + mi) * 100 + s
    }

    /// Date 를 마이크로초 정수로(파일 mtime 의 == 비교/월 필터용 — 부동소수 왕복 오차 회피).
    private static func micros(from date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    /// Codex 이벤트 timestamp(UTC ISO8601, 예 "2026-07-24T07:17:35.634Z")를 KST(+9)로 본 (월키 'YYYY-MM', 일키 'YYYY-MM-DD').
    /// 앞 19자(YYYY-MM-DDTHH:MM:SS, UTC)만 정수 컴포넌트로 읽어 UTC Date 를 만들고 KST 캘린더로 월/일을 뽑는다 — 단순 +9h
    /// 문자열 산술의 자릿수 올림(일·월·연 경계) 버그를 피한다. 소수초·타임존 표기 변형에 견고(앞 19자 고정폭만 사용). 실패 시 nil.
    private static func kstMonthDayKeys(fromTimestamp s: String) -> (month: String, day: String)? {
        let b = Array(s.utf8)
        guard b.count >= 19 else { return nil }
        // 연(0..3) 월(5,6) 일(8,9) 시(11,12) 분(14,15) 초(17,18) — 나머지는 구분자('-' 'T' ':').
        let digitIdx = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        for i in digitIdx {
            let c = b[i]
            guard c >= 48, c <= 57 else { return nil }
        }
        func num(_ start: Int, _ len: Int) -> Int {
            var v = 0
            for k in start..<(start + len) { v = v * 10 + Int(b[k] - 48) }
            return v
        }
        var comps = DateComponents()
        comps.year = num(0, 4); comps.month = num(5, 2); comps.day = num(8, 2)
        comps.hour = num(11, 2); comps.minute = num(14, 2); comps.second = num(17, 2)
        guard let date = utcCalendar.date(from: comps) else { return nil }
        let k = kstCalendar.dateComponents([.year, .month, .day], from: date)
        let y = k.year ?? 0, mo = k.month ?? 0, d = k.day ?? 0
        return (String(format: "%04d-%02d", y, mo), String(format: "%04d-%02d-%02d", y, mo, d))
    }
}

// MARK: - 전체 스캔 진입점 (증분 스캐너에 위임 — 정확성 테스트 호환)

/// 기존 API 호환용 얇은 진입점. 빈 캐시로 증분 갱신 = 전체 스캔이라, "첫 스캔 == 전체 스캔"을 코드로 보장한다.
enum TokenUsageScanner {
    static func scan(homeDirectory: URL, codexHome: URL? = nil, now: Date = Date()) -> TokenUsageMonthly {
        TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: homeDirectory, codexHome: codexHome, now: now).usage
    }
}

// MARK: - 스토어 (@MainActor · 표시/영속/증분 갱신 게이팅)

/// 토큰 사용량의 표시·영속·증분 갱신을 담당한다. 스캔은 백그라운드(Task.detached)에서 캐시를 이어받아 돌고,
/// 메인 액터엔 결과만 반영한다. 상시 타이머/앱 전역 루프 없음 — 스캔은 init 이 아니라 팝오버 표시 중 뷰(.task) 루프에서만 시작된다.
///
/// 공유 인스턴스(shared): init 은 스캔을 킥하지 않고 영속 스냅샷만 복원한다. 첫 스캔은 CheckMenuView 의 .task 가 부르는
/// runRefreshLoop 로 일원화된다. 다른 트랙(팀 토큰 업로드)도 같은 인스턴스의 currentMonthUsage 를 읽으므로 뷰가 개인 소유하지 않는다.
///
/// 정책(30분 스로틀 대체): 팝오버 표시 즉시 1회 갱신 + 열려 있는 동안 refreshPeriod(120초) 주기. 빠른 여닫이 churn 방지로
/// 마지막 갱신 후 minRefreshInterval(3초) 미만이면 스킵한다.
///
/// 저장 정책(v0.2.38): 스캔이 캐시를 바꿔도 즉시 쓰지 않고 더러움(어느 파일이)만 누적한다. 디스크에 가는 순간은 셋뿐이다 —
/// (a) 스캔 완료 시점에 마지막 저장 후 saveInterval(300초) 이상 지났으면, (b) 갱신 루프가 끝날 때(팝오버 닫힘) 1회,
/// (c) 앱 종료 알림에서 1회(동기). v0.2.37 은 변경이 있는 30초 갱신마다 7.6MB 를 통째로 다시 써 21분에 64MB 를 썼다.
@Observable
@MainActor
final class TokenUsageStore {
    /// 공유 인스턴스. 다른 트랙(팀 토큰 업로드)도 같은 인스턴스의 currentMonthUsage 를 읽으므로 뷰가 개인 소유하지 않는다.
    ///
    /// 구조적 결정성(감지-기반 땜질 제거): init 은 절대 스캔을 킥하지 않는다(영속 스냅샷 복원만). 첫 스캔은 팝오버 표시 중
    /// 뷰(CheckMenuView)의 .task 루프가 일원화한다. ImageRenderer 는 .task 를 실행하지 않으므로, 렌더 테스트가 이 공유
    /// 인스턴스를 접근해도 스캔이 돌지 않아 currentMonthUsage 는(영속 스냅샷이 없으면) nil 로 남고 행은 EmptyView(높이 0)다.
    /// 예전엔 XCTest 감지로 무해 인스턴스를 만들었으나, 감지가 일부 테스트 프로세스에서 실패해 프로덕션 경로가 실홈을
    /// 백그라운드 스캔→테스트 러너 .standard 에 영속→다음 실행 렌더 높이 오염(730pt)을 일으켰다. 감지 대신 구조로 고쳤다.
    static let shared = TokenUsageStore()

    nonisolated static let snapshotKey = "check.tokenUsage.snapshot"
    /// 갱신 루프 주기(초). 팝오버가 열려 있는 동안만 이 주기로 돈다. 30 → 120(v0.2.38): 한 주기가 ~1,600 파일 stat 순회라
    /// 열어 둔 팝오버의 utility CPU 스파이크(3.7%)를 1/4 로. 토큰 행은 정보성 표시라 최대 2분 지연을 허용한다(사장님 결정).
    nonisolated static let refreshPeriod: TimeInterval = 120
    /// 갱신 주기의 허용 오차(초). 시스템이 웨이크업을 뭉칠 수 있게 넉넉히 준다(절전).
    nonisolated static let refreshTolerance: TimeInterval = 20
    /// 최소 갱신 간격(초). 마지막 갱신 후 이 시간 미만이면 갱신을 스킵한다(여닫이 churn 방지).
    nonisolated static let minRefreshInterval: TimeInterval = 3
    /// 캐시 저장 최소 간격(초). 스캔이 캐시를 바꿔도 마지막 저장(스토어 생성 시점이 첫 기준)에서 이만큼 지나야 디스크에 쓴다.
    /// 그 사이 변경은 dirty 로 모였다가 다음 저장·루프 종료·앱 종료에 한 번에 나간다.
    nonisolated static let saveInterval: TimeInterval = 300

    /// 캐시 쓰기 직렬화 큐. 저장을 순서대로 처리하므로 더 오래된 스냅샷이 더 새 것을 덮어쓰지 못하고, 종료 시의 동기 저장
    /// (`sync`)은 진행 중이던 비동기 저장이 끝난 뒤에 최신 스냅샷을 쓴다.
    nonisolated private static let saveQueue = DispatchQueue(label: "kingcheck.tokenUsage.cacheSave", qos: .utility)

    /// 현재 KST 월 사용량. nil(영속 없음/월 리셋/최초)이거나 total==0 이면 행을 그리지 않는다.
    /// 스캔 완료마다 계약 타입으로 갱신되고, 다른 트랙의 업로드 로직이 이 값을 읽는다.
    private(set) var currentMonthUsage: TokenUsageMonthly?
    /// 스캔 진행 중 여부. 재진입 방지 + UI 절제(불투명도) 표시에 쓴다.
    private(set) var isScanning = false
    /// 지금까지 시작한 스캔 횟수(테스트 계측 — churn 가드가 실제로 스캔을 건너뛰는지 확인).
    @ObservationIgnored private(set) var scanCount = 0
    /// 지금까지 예약/수행한 캐시 저장 횟수(테스트 계측 — 스로틀·루프 종료·종료 훅이 실제로 몇 번 쓰는지 확인).
    @ObservationIgnored private(set) var saveCount = 0
    /// 마지막 스캔이 stat 한 로그 파일 수(claude + codex). **0 은 "스캔이 돌았는데 파일이 없다"(= AI CLI 를 안 쓴다)**이고,
    /// 갱신되지 않은 상태(lastScanAt == nil)는 "스캔이 아예 안 돌았다"(= 스캐너가 죽어 있다)다. 이 둘은 서버에서 보면
    /// 똑같이 "사용량 0"으로 보이는데 원인도 처방도 정반대라, 두 값을 같이 올려 갈라 본다.
    /// 2026-09-02 에 활동 중인데 9월 행이 없는 8명의 원인을 못 가른 것이 정확히 이 구분이 없어서였다.
    @ObservationIgnored private(set) var lastScanFileCount: Int = 0
    /// 마지막 스캔이 **끝난** 시각(주입 clock 기준). nil 은 이 프로세스에서 스캔이 한 번도 완주하지 않았다는 뜻이며,
    /// lastScanFileCount == 0 ("스캔은 돌았고 파일이 없었다")과 구분되는 유일한 신호다 — 위 구분의 나머지 반쪽이다.
    @ObservationIgnored private(set) var lastScanAt: Date?

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let cacheURL: URL
    private let clock: () -> Date
    private let notificationCenter: NotificationCenter
    /// Codex 홈 재정의(로그인 셸의 `CODEX_HOME`). 스캔마다 부른다 — 기본 구현은 CodexAccountUsageProbe 가 **이미 캐시한**
    /// 셸 환경만 읽으므로 셸을 새로 띄우지 않는다(첫 계정 프로브 전엔 nil → `~/.codex`). 테스트는 nil/고정값을 주입한다.
    private let codexHomeResolver: @Sendable () -> URL?
    // 증분 캐시(인메모리). 첫 스캔에서 디스크로부터 로드하고 이후엔 메모리에서 이어받는다(재디코드 회피).
    @ObservationIgnored private var cache: TokenUsageCache?
    // 마지막 갱신 시작 시각(churn 가드 기준).
    @ObservationIgnored private var lastRefreshAt: Date?
    // 진행 중 스캔 핸들(재진입 방지). 관찰 대상 아님.
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    // 아직 디스크에 안 나간 변경(어느 파일이). 저장이 예약되는 순간 비운다.
    @ObservationIgnored private var dirty = TokenUsageCacheStore.Parts()
    // 마지막 저장(예약) 시각. 스토어 생성 시점에서 출발한다 — "첫 저장도 생성 후 300초 또는 루프 종료/앱 종료".
    @ObservationIgnored private var lastSaveAt: Date
    // 앱 종료 알림 구독(스토어와 수명을 같이한다 — 박스의 deinit 이 해지).
    @ObservationIgnored private var terminationObserver: NotificationSubscription?

    /// 블록 옵저버 토큰을 수명에 묶는 박스. 스토어의 nonisolated deinit 에서 비-Sendable 토큰을 만질 수 없어 해지를 여기로 옮겼다.
    private final class NotificationSubscription: @unchecked Sendable {
        private let center: NotificationCenter
        private let token: any NSObjectProtocol
        init(center: NotificationCenter, token: any NSObjectProtocol) {
            self.center = center
            self.token = token
        }
        deinit { center.removeObserver(token) }
    }

    /// init 은 스캔을 절대 킥하지 않는다(부트스트랩 개념 제거). 영속 스냅샷 복원만 하고, 첫 스캔은 뷰(.task) 루프가 맡는다.
    /// 이로써 ImageRenderer(.task 미실행) 렌더 테스트가 결정적이 되고, 실홈 백그라운드 스캔이 테스트 러너 defaults 를 오염시키지 않는다.
    ///
    /// notificationCenter: 앱 종료(NSApplication.willTerminateNotification)를 듣는 곳. 테스트는 사설 센터를 주입해 종료를
    /// 모사한다(실 센터에 가짜 종료 알림을 흘리면 다른 구독자가 반응한다).
    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheURL: URL = TokenUsageCacheStore.defaultURL(),
        clock: @escaping () -> Date = { Date() },
        notificationCenter: NotificationCenter = .default,
        codexHomeResolver: @escaping @Sendable () -> URL? = { CodexAccountUsageProbe.cachedCodexHome() }
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.cacheURL = cacheURL
        self.clock = clock
        self.notificationCenter = notificationCenter
        self.codexHomeResolver = codexHomeResolver
        self.lastSaveAt = clock()
        // 재시작 후 즉시 표시: 영속 스냅샷을 먼저 읽는다. 단, 귀속 월(month)이 현재 KST 월과 다르면(달이 바뀜)
        // 표시하지 않고(리셋) 재스캔에 맡긴다 — 지난달 숫자가 새 달 첫 프레임에 잘못 보이지 않게.
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(TokenUsageMonthly.self, from: data),
           restored.month == TokenUsageIncrementalScanner.kstMonthString(clock()) {
            currentMonthUsage = restored
        }
        // (c) 앱 종료 훅: AppKit 은 이 알림을 메인 스레드에서 동기로 돌리고, 돌아오면 프로세스가 끝난다 — 그래서 큐 없이
        // (queue: nil = 게시 스레드에서 동기) 받아 **동기로** 쓴다. 비동기 홉은 종료 전에 돌지 않을 수 있다.
        let token = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistForTermination() }
        }
        terminationObserver = NotificationSubscription(center: notificationCenter, token: token)
    }

    /// 뷰(.task)에서 부르는 갱신 루프. 표시 즉시 1회 + 이후 refreshPeriod 주기. 뷰가 사라지면 Task 취소로 끝난다.
    ///
    /// (b) 루프가 끝나는 지점에서 더러운 캐시를 1회 저장한다. 취소 핸들러(withTaskCancellationHandler)가 아니라 루프 뒤에
    /// 두는 이유: 핸들러는 취소 즉시 — 스캔이 진행 중인 도중에도 — 불려 낡은 스냅샷을 쓰고, 곧이어 도착한 스캔 결과는 다음
    /// 열림까지 디스크에 못 간다. 위 await 는 진행 중이던 스캔을 끝까지 기다리므로 여기서 쓰는 스냅샷은 그 결과를 포함한다.
    /// (취소된 태스크도 본문은 끝까지 실행된다 — 협력적 취소.)
    func runRefreshLoop() async {
        while !Task.isCancelled {
            await refreshIfStale()
            try? await Task.sleep(for: .seconds(Self.refreshPeriod), tolerance: .seconds(Self.refreshTolerance))
        }
        persistIfDirty(force: true)
    }

    /// 즉시 1회 갱신(단, 신선하면 스킵). 진행 중이면 그 완료를 기다리고, 마지막 갱신 후 minRefreshInterval 미만이면 스킵한다.
    func refreshIfStale() async {
        if scanTask != nil { await scanTask?.value; return }
        if let last = lastRefreshAt, clock().timeIntervalSince(last) < Self.minRefreshInterval { return }
        startScan()
        await scanTask?.value
    }

    /// 신선도 스로틀을 무시하고 1회 스캔한다(진행 중이면 그 완료를 기다린다 — 동시 스캔은 여전히 금지다).
    /// 월 롤오버로 currentMonthUsage 가 nil 이 된 직후처럼 **지금 값이 없다는 것 자체가 이유**일 때만 쓴다.
    /// minRefreshInterval(3초)은 팝오버 여닫이 churn 을 막으라고 있는 것이지, "이번 달 값이 아직 하나도 없다"를
    /// 막으라고 있는 게 아니다 — 그 3초에 걸려 첫 스캔을 미루면 그 달 내내 0 으로 남는다(2026-09-02 결함).
    /// 평상시 경로는 refreshIfStale() 이다(연타는 그쪽 스로틀이 막는다).
    func refreshNow() async {
        if scanTask != nil { await scanTask?.value; return }
        startScan()
        await scanTask?.value
    }

    /// 진행 중 스캔이 있으면 끝날 때까지 기다린다. 테스트 결정성용 — .utility 백그라운드 태스크를 직접 await.
    func awaitScanCompletion() async {
        await scanTask?.value
    }

    /// 예약된 비동기 캐시 저장이 모두 디스크에 닿을 때까지 기다린다(테스트 결정성용 — 저장 큐에 장벽을 하나 넣는다).
    nonisolated func awaitPendingSaves() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.saveQueue.async { continuation.resume() }
        }
    }

    private func startScan() {
        guard scanTask == nil else { return }
        isScanning = true
        scanCount += 1
        let now = clock()
        lastRefreshAt = now
        let home = homeDirectory
        let codexHome = codexHomeResolver()
        let url = cacheURL
        // 인메모리 캐시가 있으면 그대로 이어받고, 없으면(첫 스캔) 백그라운드에서 디스크 로드 → 증분(=전체) 스캔.
        let inMemory = cache
        scanTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) { () -> TokenUsageIncrementalScanner.Result in
                let base = inMemory ?? TokenUsageCacheStore.load(from: url)
                return TokenUsageIncrementalScanner.update(base, homeDirectory: home, codexHome: codexHome, now: now)
            }.value
            guard let self else { return }
            self.cache = result.cache
            // 변경은 즉시 쓰지 않고 더러움만 누적한다 — (a) 저장 간격이 찼을 때만 디스크로.
            self.dirty.formUnion(result.stats.changedParts)
            self.apply(result.usage)
            // 관측값은 스캔이 **완주한 뒤에만** 채운다 — 시작 시점에 찍으면 중간에 죽은 스캔도 "돌았다"로 보여
            // "안 씀(파일 0)"과 "스캐너 죽음(미갱신)"의 구분이 무너진다.
            self.lastScanFileCount = result.stats.claudeFilesStatted + result.stats.codexFilesStatted
            self.lastScanAt = self.clock()
            self.persistIfDirty(force: false)
            self.isScanning = false
            self.scanTask = nil
        }
    }

    /// 더러운 부분을 저장 큐에 예약한다(비동기·직렬). force 가 아니면 마지막 저장 후 saveInterval 미만이면 미룬다.
    /// 예약과 동시에 dirty 를 비우고 시계를 갱신하므로, 그 뒤 스캔이 다시 더럽히면 다음 창에 나간다.
    private func persistIfDirty(force: Bool) {
        guard !dirty.isEmpty, let cache else { return }
        let now = clock()
        if !force, now.timeIntervalSince(lastSaveAt) < Self.saveInterval { return }
        let parts = dirty
        dirty = []
        lastSaveAt = now
        saveCount += 1
        let url = cacheURL
        Self.saveQueue.async {
            TokenUsageCacheStore.save(cache, parts: parts, to: url)
        }
    }

    /// (c) 앱 종료: 더러운 부분을 **동기로** 쓴다. 저장 큐에 sync 로 들어가므로 진행 중이던 비동기 저장이 끝난 뒤 최신
    /// 스냅샷이 마지막에 남는다. 2~3MB JSON 인코딩+원자적 쓰기라 종료를 수십 ms 늦출 뿐이다.
    private func persistForTermination() {
        guard !dirty.isEmpty, let cache else { return }
        let parts = dirty
        dirty = []
        lastSaveAt = clock()
        saveCount += 1
        let url = cacheURL
        Self.saveQueue.sync {
            _ = TokenUsageCacheStore.save(cache, parts: parts, to: url)
        }
    }

    private func apply(_ usage: TokenUsageMonthly) {
        // 인메모리엔 항상 반영해 표시/업로드가 최신 월 집계를 읽게 한다.
        currentMonthUsage = usage
        // 영속(UserDefaults)은 표시할 값이 있을 때만 — 로그가 없는(집계 0) 머신은 재실행 때 다시 부트스트랩한다.
        if usage.total > 0, let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }
}

// MARK: - 뷰 (CheckTokenUsageRow)

/// 팝오버 하단 슬림 행. 현재 월 사용량이 없거나 집계 0 이면 아무것도 그리지 않는다(EmptyView — 빈 자리/간격 없음).
/// 값이 있으면 FooterBar 톤(panelStyle · 가로 12/세로 8)의 한 줄: sparkles + "N월 AI 토큰" + 우측 총합(굵게, 전체 숫자).
/// onOpenBoard 가 주어지면 우측에 순위로 가는 아이콘 버튼을 붙인다(페이지 자체는 다른 트랙 소관).
/// 주입된 토큰 스토어(기본 .shared)를 읽는다 — 뷰 개인 소유(@State) 없이 다른 트랙/갱신 루프와 같은 인스턴스를 본다.
struct CheckTokenUsageRow: View {
    // 표시할 토큰 스토어. 기본은 전역 공유(.shared)라 다른 트랙과 같은 집계를 읽는다. 테스트는 격리 인스턴스를 주입한다
    // (렌더 결정성 — 실홈 스캔이 테스트 .standard 를 건드리지 않게). CheckMenuView 는 store.tokenUsage 를 넘긴다.
    var store: TokenUsageStore = .shared
    /// Codex 계정 사용량(선택). 있으면 굵은 총합이 `claudeTotal + max(codexTotal, 계정 월합)` 이 되고 툴팁에 계정 줄이 붙는다.
    /// CheckMenuView 는 store.codexAccount 를 넘긴다. nil 이면 로컬 집계만(옛 모양 그대로).
    var account: CodexAccountUsageStore? = nil
    var onOpenBoard: (() -> Void)? = nil

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        // 로컬 총합이 0 이어도 계정 집계가 있으면 행을 그린다(`.zst` 만 남은 채 앱을 처음 설치한 사람의 Codex 사용량은
        // 로컬에서 읽을 수 없고 계정 집계만이 그 몫을 안다 — 게이트는 짝으로 있어야 한다: 표시 총합 산식이 계정값을 쓰는데
        // 이 가드가 로컬 0 을 막으면 그 사람에겐 아무것도 안 보인다).
        if let usage = store.currentMonthUsage, usage.total > 0 || (accountMonth(for: usage) ?? 0) > 0 {
            // 행은 표시만 한다 — 갱신 루프는 CheckMenuView 의 .task 가 일원화해 돌린다(행이 EmptyView 라 자체 .task 가
            // 애초에 안 돌던 순환 문제를 없앤다). ImageRenderer 가 .task 를 실행하지 않아 렌더 테스트도 결정적이다.
            slimRow(usage)
        } else if let onOpenBoard {
            // 내 소모량이 없어도(AI CLI 를 안 쓰는 팀원·신규 설치) 순위판으로 가는 길은 남긴다.
            // 순위판은 앱 사용자 전체 공개 보드라 내 사용량이 0이어도 남의 순위를 볼 이유가 있고, 무엇보다
            // 월 이동(‹ ›)과 내 사용량 공개/비공개 토글은 **그 패널 안에만** 있다 — 이 행이 사라지면
            // person.2 버튼도 사라져 팝오버 어디에도 진입 경로가 없었다(회귀 지점).
            boardEntryRow(onOpenBoard)
        } else {
            // 표시할 사용량도 없고 순위판 콜백도 없다(행 단독 미리보기) — 아무것도 그리지 않는다.
            EmptyView()
        }
    }

    private func slimRow(_ usage: TokenUsageMonthly) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            // "토큰"만으로는 뭔지 바로 인지가 안 된다는 피드백으로 "소모량"까지 풀어 쓴다.
            Text("\(usage.monthNumber)월 AI 토큰 소모량")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            // 표시 총합만 계정 집계를 섞는다(TokenUsageDisplay.effectiveTotal). usage.total(업로드값)은 그대로다.
            Text(TokenNumberFormatter.grouped(TokenUsageDisplay.effectiveTotal(local: usage, accountMonth: accountMonth(for: usage))))
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
            // 콜백이 있을 때만 팀 순위 버튼을 붙인다(없으면 기존처럼 값까지만).
            if let onOpenBoard {
                IconButton(icon: "person.2", help: "팀 토큰 순위", action: onOpenBoard)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // 일반 panelStyle 대신 악센트 미광(테두리 + 부드러운 외곽광)으로 포인트를 준다 — 헤더/팀 카드 사이에서
        // 이 행이 묻히지 않게. 그림자는 레이아웃에 영향이 없어 창 높이 계산은 그대로다.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: CheckTheme.accent.opacity(0.35), radius: 7)
        )
        // 스캔 중엔 살짝 흐리게(절제된 진행 표시). 값은 이전 집계를 유지하다 완료 시 교체된다.
        .opacity(store.isScanning ? 0.55 : 1)
        .help(usage.detailTooltip(account: account?.snapshot))
    }

    /// 이 달의 계정 월합(스냅샷이 있을 때). 스냅샷의 월과 usage.month 는 각각 UTC/KST 월이지만 순위 용도에선 허용(문서화된 미결).
    private func accountMonth(for usage: TokenUsageMonthly) -> Int? {
        account?.snapshot?.monthTotal(usage.month)
    }

    /// 내 소모량이 없을 때의 대체 행 — 숫자 없이 순위판 진입만 준다.
    /// 톤은 일부러 조용하게(악센트 미광 없이 기본 panelStyle) 잡는다: 자랑할 내 숫자가 없는 사용자에게
    /// 빛나는 행을 들이밀 이유는 없고, 높이는 slimRow 와 같아(아이콘 버튼 27 + 상하 8 패딩) 창 높이 예산
    /// (CheckMenuView.tokenUsageRowHeight)이 두 경우 모두 그대로 맞는다.
    private func boardEntryRow(_ onOpenBoard: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text("AI 토큰 순위")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            IconButton(icon: "person.2", help: "AI 토큰 순위", action: onOpenBoard)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
        .help("앱 사용자 전체의 AI 토큰 순위를 봅니다")
    }
}
