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
    var codexInput: Int = 0
    var codexOutput: Int = 0

    /// 화면 우측에 굵게 뜨는 총합 = 여섯 필드의 단순 합. (Codex input 은 cached 를 이미 포함한 누적치라 그대로 더한다.)
    var total: Int {
        claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation + codexInput + codexOutput
    }

    /// Claude 소계(입력+출력+캐시읽기+캐시생성) — 툴팁 표기용.
    var claudeTotal: Int { claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation }
    /// Codex 소계(입력+출력) — 툴팁 표기용.
    var codexTotal: Int { codexInput + codexOutput }

    /// 라벨 "N월 …"에 쓰는 월 숫자. 'YYYY-MM' 의 뒤 두 자리를 정수로(선행 0 제거). 파싱 실패 시 0.
    var monthNumber: Int { Int(month.split(separator: "-").last ?? "") ?? 0 }

    /// .help 툴팁 상세 문구. 축약 없이 콤마 전체 숫자로, 값이 있는 소스만 이어 붙인다
    /// ("Claude 4,280,667,571 (입력 8,458,939 · 출력 9,796,198 · 캐시읽기 4,063,320,273 · 캐시생성 199,092,161) · Codex 145,691,467").
    var detailTooltip: String {
        var parts: [String] = []
        if claudeTotal > 0 {
            parts.append(
                "Claude \(TokenNumberFormatter.grouped(claudeTotal)) "
                + "(입력 \(TokenNumberFormatter.grouped(claudeInput)) · 출력 \(TokenNumberFormatter.grouped(claudeOutput)) "
                + "· 캐시읽기 \(TokenNumberFormatter.grouped(claudeCacheRead)) · 캐시생성 \(TokenNumberFormatter.grouped(claudeCacheCreation)))"
            )
        }
        if codexTotal > 0 {
            parts.append("Codex \(TokenNumberFormatter.grouped(codexTotal))")
        }
        return parts.joined(separator: " · ")
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
/// - claudeEntries: dedupe 키(=id\0requestId) → 엔트리. 라인 단위 usage 를 dedupe 해 월 필터로 합계를 낸다.
///   append-only 로그라 파일이 커져도 새 바이트만 이어읽어 엔트리를 추가한다.
/// - codexFileStates: 경로 → (size, mtime, offset, totals). rollout 파일은 "마지막 token_count 누적치"가 세션값이라
///   파일 단위로 그 값을 캐시한다(꼬리에서 더 최신 token_count 를 만나면 덮어씀).
///
/// 압축: 엔트리/상태는 이름키 대신 배열 튜플로 인코딩한다(3만 엔트리 ≈ 수 MB → 이름키면 배로 커진다).
struct TokenUsageCache: Codable, Equatable, Sendable {
    var claudeFileStates: [String: FileProgress] = [:]
    var claudeEntries: [String: ClaudeEntry] = [:]
    var codexFileStates: [String: CodexFileProgress] = [:]
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

/// Codex 파일(세션)의 진행 상태 + 그 세션의 마지막 유효 token_count 누적치.
struct CodexFileProgress: Equatable, Sendable {
    var size: Int
    var mtimeMicros: Int
    var consumedOffset: Int
    var input: Int
    var output: Int
    var cached: Int
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

extension CodexFileProgress: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        size = try c.decode(Int.self)
        mtimeMicros = try c.decode(Int.self)
        consumedOffset = try c.decode(Int.self)
        input = try c.decode(Int.self)
        output = try c.decode(Int.self)
        cached = try c.decode(Int.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(size); try c.encode(mtimeMicros); try c.encode(consumedOffset)
        try c.encode(input); try c.encode(output); try c.encode(cached)
    }
}

/// 캐시 파일 로드/저장(Application Support/aing-check/token-usage-cache.json). 스캔과 분리해 스캐너는 로그 파일만 읽게 한다.
enum TokenUsageCacheStore {
    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("aing-check/token-usage-cache.json", isDirectory: false)
    }

    /// 없거나 손상됐으면 빈 캐시(첫 실행 = 전체 스캔). 예외를 던지지 않는다(캐시는 항상 재구성 가능한 파생물).
    static func load(from url: URL) -> TokenUsageCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(TokenUsageCache.self, from: data)
        else { return TokenUsageCache() }
        return cache
    }

    /// 상위 폴더를 만들고 원자적으로 쓴다. 호출측이 "새 데이터가 있을 때만" 부르므로 무변경 갱신에선 쓰기 0.
    static func save(_ cache: TokenUsageCache, to url: URL) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 증분 스캐너 (순수 · nonisolated, 백그라운드 실행)

/// 로컬 AI CLI 로그를 "증분"으로 집계한다. 캐시(파일상태+엔트리)를 받아, 바뀐 파일의 새 바이트만 이어읽고,
/// 갱신된 캐시 + 현재 KST 월 집계 + 계측을 돌려준다. 상태 없는 순수 로직이라 Task.detached 에서 돈다.
///
/// 월 귀속(핵심 개편):
/// - Claude: 엔트리 ts14(UTC 초) 를 KST(UTC+9)로 본 달력 월에 귀속. 현재 월 = [이번달 1일 0시 KST, 다음달 1일 0시 KST).
/// - Codex: 파일 mtime 의 KST 월로 '파일 단위' 귀속(장기 세션이 월을 걸치는 극단은 mtime 월 귀속으로 수용).
/// - 집계는 현재 KST 월만. 엔트리 보관은 현재+직전 월(월초 지연 기록·시계 오차 대비), 그 이전은 퇴거.
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

    /// 주어진 시각이 속한 KST 달력 월의 경계(절대 시각)와 'YYYY-MM' 문자열, 직전 월 시작.
    /// start = 이번달 1일 0시 KST, end = 다음달 1일 0시 KST, prevStart = 지난달 1일 0시 KST.
    static func monthBounds(now: Date) -> (start: Date, end: Date, prevStart: Date, month: String) {
        let cal = kstCalendar
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps)!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        let prevStart = cal.date(byAdding: .month, value: -1, to: start)!
        let month = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        return (start, end, prevStart, month)
    }

    /// 주어진 시각의 KST 달력 월 'YYYY-MM'. 스토어가 복원 스냅샷의 월 일치 판정에 쓴다.
    static func kstMonthString(_ date: Date) -> String { monthBounds(now: date).month }

    /// 증분 갱신 계측(테스트/실증용). 재읽기 바이트·읽은 파일 수와 캐시 변경 여부를 보고한다.
    struct Stats: Equatable, Sendable {
        var claudeFilesStatted = 0
        var claudeFilesRead = 0
        var claudeBytesRead = 0
        var codexFilesStatted = 0
        var codexFilesRead = 0
        var codexBytesRead = 0
        /// 캐시에 실제 변경(엔트리/상태 추가·갱신 또는 퇴거)이 있었는가. false 면 저장을 건너뛴다.
        var cacheChanged = false
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
    static func update(_ input: TokenUsageCache, homeDirectory: URL, now: Date = Date()) -> Result {
        var cache = input
        var stats = Stats()

        // 현재 KST 월 경계. 합계 창 = [monthStart, monthEnd), 스캔 프리필터 컷오프 = monthStart,
        // 퇴거(보관) 경계 = prevMonthStart(직전 월까지 보관).
        let (monthStart, monthEnd, prevMonthStart, monthString) = monthBounds(now: now)
        let monthStartTs14 = ts14(from: monthStart)
        let monthEndTs14 = ts14(from: monthEnd)
        let prevMonthStartTs14 = ts14(from: prevMonthStart)
        let monthStartMicros = micros(from: monthStart)
        let monthEndMicros = micros(from: monthEnd)
        let prevMonthStartMicros = micros(from: prevMonthStart)

        // 1) 퇴거(로드 시점): 직전 월 시작 밖 엔트리/파일상태 제거. 무언가 지워지면 캐시 변경으로 표시(저장 유도).
        evict(&cache, evictTs14: prevMonthStartTs14, evictMicros: prevMonthStartMicros, changed: &stats.cacheChanged)

        // 2) 소스별 증분 스캔(프리필터 컷오프 = 현재 월 시작).
        scanClaude(&cache, homeDirectory: homeDirectory, cutoff: monthStart, evictTs14: prevMonthStartTs14, stats: &stats)
        scanCodex(&cache, homeDirectory: homeDirectory, cutoff: monthStart, stats: &stats)

        // 3) 합계 재계산(엔트리 맵 현재-월 필터 + codex 파일상태 현재-월 필터).
        let usage = totals(
            cache, month: monthString,
            monthStartTs14: monthStartTs14, monthEndTs14: monthEndTs14,
            monthStartMicros: monthStartMicros, monthEndMicros: monthEndMicros
        )
        return Result(cache: cache, usage: usage, stats: stats)
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
            guard let read = readTail(at: f.url, from: startOffset, { line in
                ingestClaudeLine(line, into: &cache, evictTs14: evictTs14)
            }) else { continue }
            stats.claudeFilesRead += 1
            stats.claudeBytesRead += read.bytesRead
            cache.claudeFileStates[path] = FileProgress(
                size: f.size, mtimeMicros: f.mtimeMicros, consumedOffset: read.consumedOffset
            )
            stats.cacheChanged = true
        }
    }

    /// 한 Claude 라인을 파싱해 dedupe 키로 엔트리 맵에 넣는다(포크 복제는 같은 키라 한 번만 계상).
    private static func ingestClaudeLine(_ line: UnsafeRawBufferPointer, into cache: inout TokenUsageCache, evictTs14: Int) {
        // 프리체크: "usage"(assistant 라인에만) → "assistant". 둘 다 있어야 디코드(대다수 라인 조기 배제).
        guard contains(line, usagePattern), contains(line, assistantPattern) else { return }
        guard let base = line.baseAddress,
              let object = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count)) as? [String: Any],
              object["type"] as? String == "assistant",
              let timestamp = object["timestamp"] as? String,
              let message = object["message"] as? [String: Any],
              let usageObject = message["usage"] as? [String: Any],
              let ts = ts14(fromTimestampPrefix: timestamp)
        else { return }
        // 직전 월 시작 밖(퇴거 대상)은 아예 저장하지 않는다 — 엔트리 맵을 ≤2개월 규모로 유지. 합계 창 필터는 별도(현재 월).
        guard ts >= evictTs14 else { return }
        // (message.id, requestId) 쌍으로 dedupe. NUL 구분자(둘 다 NUL 을 못 담으므로 충돌 불가).
        let key = "\(message["id"] as? String ?? "")\u{0}\(object["requestId"] as? String ?? "")"
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
        if var existing = cache.claudeEntries[key] {
            let windowTs14 = max(existing.ts14, ts)
            if existing.output >= output {
                // output 은 안 바뀌어도 더 최신 라인을 봤으면 월 판정 ts 만 끌어올린다(대입만, 값은 유지).
                if windowTs14 != existing.ts14 {
                    existing.ts14 = windowTs14
                    cache.claudeEntries[key] = existing
                }
                return
            }
            // max-output 교체: 값(input/cache 포함)은 이 레코드로, 월 판정 ts 는 관측 최대치로.
            cache.claudeEntries[key] = ClaudeEntry(
                ts14: windowTs14,
                input: intField(usageObject["input_tokens"]),
                output: output,
                cacheRead: intField(usageObject["cache_read_input_tokens"]),
                cacheCreation: intField(usageObject["cache_creation_input_tokens"])
            )
            return
        }
        cache.claudeEntries[key] = ClaudeEntry(
            ts14: ts,
            input: intField(usageObject["input_tokens"]),
            output: output,
            cacheRead: intField(usageObject["cache_read_input_tokens"]),
            cacheCreation: intField(usageObject["cache_creation_input_tokens"])
        )
    }

    // MARK: Codex

    /// ~/.codex/sessions/**/rollout-*.jsonl. 각 파일(세션)의 마지막 유효 token_count 누적치를 파일 단위 캐시에 담아 합산.
    private static func scanCodex(
        _ cache: inout TokenUsageCache, homeDirectory: URL, cutoff: Date, stats: inout Stats
    ) {
        let root = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = recentFiles(
            under: root, cutoff: cutoff,
            matching: { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
        )
        for f in files {
            stats.codexFilesStatted += 1
            let path = f.url.path
            let prior = cache.codexFileStates[path]
            if let p = prior, p.size == f.size, p.mtimeMicros == f.mtimeMicros { continue }
            // 성장이면 이어읽기 + 직전 누적치를 시작값으로(꼬리에 새 token_count 없으면 유지). 그 외면 처음부터.
            let startOffset: Int
            var accInput = 0, accOutput = 0, accCached = 0
            if let p = prior, f.size >= p.size, f.mtimeMicros >= p.mtimeMicros {
                startOffset = p.consumedOffset
                accInput = p.input; accOutput = p.output; accCached = p.cached
            } else {
                startOffset = 0
            }
            guard let read = readTail(at: f.url, from: startOffset, { line in
                guard contains(line, tokenCountPattern) else { return }
                guard let base = line.baseAddress,
                      let object = try? JSONSerialization.jsonObject(with: Data(bytes: base, count: line.count)) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any]
                else { return }
                // 마지막 유효 token_count 로 덮어쓴다 — 누적치라 파일(꼬리) 최종값이 세션 전체 사용량.
                accInput = intField(total["input_tokens"])
                accOutput = intField(total["output_tokens"])
                accCached = intField(total["cached_input_tokens"])
            }) else { continue }
            stats.codexFilesRead += 1
            stats.codexBytesRead += read.bytesRead
            cache.codexFileStates[path] = CodexFileProgress(
                size: f.size, mtimeMicros: f.mtimeMicros, consumedOffset: read.consumedOffset,
                input: accInput, output: accOutput, cached: accCached
            )
            stats.cacheChanged = true
        }
    }

    // MARK: 합계 / 퇴거

    /// 엔트리 맵을 현재 월 [start,end) 로 필터해 Claude 합계를, codex 파일상태를 현재 월(파일 mtime)로 필터해 Codex 합계를 낸다.
    private static func totals(
        _ cache: TokenUsageCache, month: String,
        monthStartTs14: Int, monthEndTs14: Int, monthStartMicros: Int, monthEndMicros: Int
    ) -> TokenUsageMonthly {
        var usage = TokenUsageMonthly(month: month)
        for (_, e) in cache.claudeEntries where e.ts14 >= monthStartTs14 && e.ts14 < monthEndTs14 {
            usage.claudeInput += e.input
            usage.claudeOutput += e.output
            usage.claudeCacheRead += e.cacheRead
            usage.claudeCacheCreation += e.cacheCreation
        }
        for (_, s) in cache.codexFileStates where s.mtimeMicros >= monthStartMicros && s.mtimeMicros < monthEndMicros {
            usage.codexInput += s.input
            usage.codexOutput += s.output
        }
        return usage
    }

    /// 직전 월 시작 밖 엔트리/파일상태를 제거(로드·저장 시점). 무언가 지워지면 changed 를 세워 저장을 유도한다.
    private static func evict(_ cache: inout TokenUsageCache, evictTs14: Int, evictMicros: Int, changed: inout Bool) {
        let beforeEntries = cache.claudeEntries.count
        cache.claudeEntries = cache.claudeEntries.filter { $0.value.ts14 >= evictTs14 }
        let beforeClaudeFiles = cache.claudeFileStates.count
        cache.claudeFileStates = cache.claudeFileStates.filter { $0.value.mtimeMicros >= evictMicros }
        let beforeCodexFiles = cache.codexFileStates.count
        cache.codexFileStates = cache.codexFileStates.filter { $0.value.mtimeMicros >= evictMicros }
        if cache.claudeEntries.count != beforeEntries
            || cache.claudeFileStates.count != beforeClaudeFiles
            || cache.codexFileStates.count != beforeCodexFiles {
            changed = true
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
}

// MARK: - 전체 스캔 진입점 (증분 스캐너에 위임 — 정확성 테스트 호환)

/// 기존 API 호환용 얇은 진입점. 빈 캐시로 증분 갱신 = 전체 스캔이라, "첫 스캔 == 전체 스캔"을 코드로 보장한다.
enum TokenUsageScanner {
    static func scan(homeDirectory: URL, now: Date = Date()) -> TokenUsageMonthly {
        TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: homeDirectory, now: now).usage
    }
}

// MARK: - 스토어 (@MainActor · 표시/영속/증분 갱신 게이팅)

/// 토큰 사용량의 표시·영속·증분 갱신을 담당한다. 스캔은 백그라운드(Task.detached)에서 캐시를 이어받아 돌고,
/// 메인 액터엔 결과만 반영한다. 상시 타이머/앱 전역 루프 없음 — 스캔은 init 이 아니라 팝오버 표시 중 뷰(.task) 루프에서만 시작된다.
///
/// 공유 인스턴스(shared): init 은 스캔을 킥하지 않고 영속 스냅샷만 복원한다. 첫 스캔은 CheckMenuView 의 .task 가 부르는
/// runRefreshLoop 로 일원화된다. 다른 트랙(팀 토큰 업로드)도 같은 인스턴스의 currentMonthUsage 를 읽으므로 뷰가 개인 소유하지 않는다.
///
/// 정책(30분 스로틀 대체): 팝오버 표시 즉시 1회 갱신 + 열려 있는 동안 30초 주기. 빠른 여닫이 churn 방지로
/// 마지막 갱신 후 minRefreshInterval(3초) 미만이면 스킵한다.
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
    /// 갱신 루프 주기(초). 팝오버가 열려 있는 동안만 이 주기로 돈다.
    nonisolated static let refreshPeriod: TimeInterval = 30
    /// 최소 갱신 간격(초). 마지막 갱신 후 이 시간 미만이면 갱신을 스킵한다(여닫이 churn 방지).
    nonisolated static let minRefreshInterval: TimeInterval = 3

    /// 현재 KST 월 사용량. nil(영속 없음/월 리셋/최초)이거나 total==0 이면 행을 그리지 않는다.
    /// 스캔 완료마다 계약 타입으로 갱신되고, 다른 트랙의 업로드 로직이 이 값을 읽는다.
    private(set) var currentMonthUsage: TokenUsageMonthly?
    /// 스캔 진행 중 여부. 재진입 방지 + UI 절제(불투명도) 표시에 쓴다.
    private(set) var isScanning = false
    /// 지금까지 시작한 스캔 횟수(테스트 계측 — churn 가드가 실제로 스캔을 건너뛰는지 확인).
    @ObservationIgnored private(set) var scanCount = 0

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let cacheURL: URL
    private let clock: () -> Date
    // 증분 캐시(인메모리). 첫 스캔에서 디스크로부터 로드하고 이후엔 메모리에서 이어받는다(재디코드 회피).
    @ObservationIgnored private var cache: TokenUsageCache?
    // 마지막 갱신 시작 시각(churn 가드 기준).
    @ObservationIgnored private var lastRefreshAt: Date?
    // 진행 중 스캔 핸들(재진입 방지). 관찰 대상 아님.
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// init 은 스캔을 절대 킥하지 않는다(부트스트랩 개념 제거). 영속 스냅샷 복원만 하고, 첫 스캔은 뷰(.task) 루프가 맡는다.
    /// 이로써 ImageRenderer(.task 미실행) 렌더 테스트가 결정적이 되고, 실홈 백그라운드 스캔이 테스트 러너 defaults 를 오염시키지 않는다.
    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheURL: URL = TokenUsageCacheStore.defaultURL(),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.cacheURL = cacheURL
        self.clock = clock
        // 재시작 후 즉시 표시: 영속 스냅샷을 먼저 읽는다. 단, 귀속 월(month)이 현재 KST 월과 다르면(달이 바뀜)
        // 표시하지 않고(리셋) 재스캔에 맡긴다 — 지난달 숫자가 새 달 첫 프레임에 잘못 보이지 않게.
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(TokenUsageMonthly.self, from: data),
           restored.month == TokenUsageIncrementalScanner.kstMonthString(clock()) {
            currentMonthUsage = restored
        }
    }

    /// 뷰(.task)에서 부르는 갱신 루프. 표시 즉시 1회 + 이후 refreshPeriod 주기. 뷰가 사라지면 Task 취소로 끝난다.
    func runRefreshLoop() async {
        while !Task.isCancelled {
            await refreshIfStale()
            // tolerance 를 넉넉히 줘 정확한 타이밍을 요구하지 않는다(절전 — 시스템이 웨이크업을 뭉칠 수 있게).
            try? await Task.sleep(for: .seconds(Self.refreshPeriod), tolerance: .seconds(5))
        }
    }

    /// 즉시 1회 갱신(단, 신선하면 스킵). 진행 중이면 그 완료를 기다리고, 마지막 갱신 후 minRefreshInterval 미만이면 스킵한다.
    func refreshIfStale() async {
        if scanTask != nil { await scanTask?.value; return }
        if let last = lastRefreshAt, clock().timeIntervalSince(last) < Self.minRefreshInterval { return }
        startScan()
        await scanTask?.value
    }

    /// 진행 중 스캔이 있으면 끝날 때까지 기다린다. 테스트 결정성용 — .utility 백그라운드 태스크를 직접 await.
    func awaitScanCompletion() async {
        await scanTask?.value
    }

    private func startScan() {
        guard scanTask == nil else { return }
        isScanning = true
        scanCount += 1
        let now = clock()
        lastRefreshAt = now
        let home = homeDirectory
        let url = cacheURL
        // 인메모리 캐시가 있으면 그대로 이어받고, 없으면(첫 스캔) 백그라운드에서 디스크 로드 → 증분(=전체) 스캔.
        let inMemory = cache
        scanTask = Task { @MainActor [weak self] in
            let (newCache, usage) = await Task.detached(priority: .utility) { () -> (TokenUsageCache, TokenUsageMonthly) in
                let base = inMemory ?? TokenUsageCacheStore.load(from: url)
                let result = TokenUsageIncrementalScanner.update(base, homeDirectory: home, now: now)
                // 새 데이터가 있을 때만 저장(무변경 갱신에선 쓰기 0).
                if result.stats.cacheChanged {
                    TokenUsageCacheStore.save(result.cache, to: url)
                }
                return (result.cache, result.usage)
            }.value
            guard let self else { return }
            self.cache = newCache
            self.apply(usage)
            self.isScanning = false
            self.scanTask = nil
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
    var onOpenBoard: (() -> Void)? = nil

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let usage = store.currentMonthUsage, usage.total > 0 {
            // 행은 표시만 한다 — 갱신 루프는 CheckMenuView 의 .task 가 일원화해 돌린다(행이 EmptyView 라 자체 .task 가
            // 애초에 안 돌던 순환 문제를 없앤다). ImageRenderer 가 .task 를 실행하지 않아 렌더 테스트도 결정적이다.
            slimRow(usage)
        } else {
            // 표시할 사용량 없음(로그 부재/집계 0/월 리셋 대기) — 행을 아예 그리지 않는다.
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
            Text(TokenNumberFormatter.grouped(usage.total))
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
        .help(usage.detailTooltip)
    }
}
