import Foundation
import Observation
import SwiftUI

// MARK: - 집계 모델 (스냅샷)

/// 최근 30일 AI CLI 토큰 사용량 집계 결과. UserDefaults 에 JSON 으로 영속해 재시작 즉시 표시한다.
///
/// 프라이버시: 여기 담기는 값은 usage 숫자와 스캔 시각뿐이다. 대화 본문·프롬프트·파일 경로 등 내용 필드는
/// 스캔 단계에서 읽지도 보관하지도 않는다(아래 TokenUsageIncrementalScanner 주석 참고).
struct TokenUsageSnapshot: Codable, Equatable, Sendable {
    var claude: ClaudeTokenUsage
    var codex: CodexTokenUsage
    /// 이 집계를 만든 스캔 시각. 영속 스냅샷의 신선도 기준이자 화면 표시용 마지막 갱신 시각.
    var scannedAt: Date

    /// 화면 우측에 굵게 뜨는 총합. Claude(입력+출력+캐시읽기+캐시생성) + Codex(입력+출력).
    var total: Int { claude.total + codex.total }

    /// .help 툴팁 상세 문구. 값이 있는 소스만 이어 붙인다(둘 다 있으면
    /// "Claude 4.28B (입력 8.5M · 출력 9.8M · 캐시읽기 4.06B · 캐시생성 199.1M) · Codex 145.7M").
    var detailTooltip: String {
        var parts: [String] = []
        if claude.total > 0 {
            parts.append(
                "Claude \(TokenAbbreviation.short(claude.total)) "
                + "(입력 \(TokenAbbreviation.short(claude.input)) · 출력 \(TokenAbbreviation.short(claude.output)) "
                + "· 캐시읽기 \(TokenAbbreviation.short(claude.cacheRead)) · 캐시생성 \(TokenAbbreviation.short(claude.cacheCreation)))"
            )
        }
        if codex.total > 0 {
            parts.append("Codex \(TokenAbbreviation.short(codex.total))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Claude Code 사용량. 총합 = 네 필드의 단순 합(캐시 읽기/생성도 실제 소비 토큰이므로 포함).
struct ClaudeTokenUsage: Codable, Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheCreation: Int = 0

    var total: Int { input + output + cacheRead + cacheCreation }
}

/// Codex 사용량. input_tokens 는 캐시(cached_input_tokens)를 이미 포함한 누적치라, 총합은 input+output 이다
/// (캐시를 따로 더하면 이중 계상된다). cached 는 참고용으로만 보관한다.
struct CodexTokenUsage: Codable, Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var cached: Int = 0

    var total: Int { input + output }
}

// MARK: - 축약 포맷 (순수 함수)

/// 큰 토큰 수를 K/M/B 로 축약한다. 오라클(python)의 fmt 와 자릿수를 맞춘다:
/// 10억↑ 은 소수 2자리+B, 100만↑ 은 소수 1자리+M, 1000↑ 은 소수 1자리+K, 그 미만은 정수.
/// 예: 1_234 → "1.2K", 3_400_000 → "3.4M", 4_280_667_571 → "4.28B".
enum TokenAbbreviation {
    static func short(_ value: Int) -> String {
        let v = max(0, value)
        if v >= 1_000_000_000 { return String(format: "%.2fB", Double(v) / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", Double(v) / 1_000) }
        return "\(v)"
    }
}

// MARK: - 증분 캐시 (영속 · 파일 저장)

/// 증분 스캔의 상태를 담는 영속 캐시. Application Support 에 컴팩트 JSON 으로 저장한다(UserDefaults 에 수 MB 금지).
///
/// 세 축:
/// - claudeFileStates: 경로 → (size, mtime, consumedOffset). 파일이 안 변했는지(스킵)·어디까지 읽었는지(이어읽기) 판단.
/// - claudeEntries: dedupe 키(=id\0requestId) → 엔트리. 라인 단위 usage 를 dedupe 해 창 필터로 합계를 낸다.
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

/// Claude 한 라인의 집계값 + 창 판정용 타임스탬프(YYYYMMDDHHMMSS 정수 = 고정폭 UTC 라 사전식==시간순).
struct ClaudeEntry: Equatable, Sendable {
    /// 창/퇴거 판정용 ts14 = 이 dedupe 키에서 '관측한 최대 ts14'. max-output 이 이긴 레코드의 ts 가 아니라
    /// 관측 최대치를 유지해, 창밖의 옛 큰-output 스냅샷이 창 안(더 최신)의 같은 키를 통째로 탈락시키지 않게 한다.
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
/// 갱신된 캐시 + 스냅샷 + 계측을 돌려준다. 상태 없는 순수 로직이라 Task.detached 에서 돈다.
///
/// 증분 절차(파일마다):
/// - 디렉터리 워크 + stat → mtime 프리필터(컷오프 이전 파일 통째 스킵).
/// - size·mtime 동일 → 무변경, 재읽기 0.
/// - 커졌으면(append) consumedOffset 부터 tail 만 스트리밍 — 오프셋은 항상 마지막 "완결 라인"(개행) 끝으로 저장.
/// - 줄어들었거나 mtime 역행이면 그 파일 전체 재파싱(오프셋 0). 엔트리는 dedupe 키라 재삽입 무해.
///   (주의: 재파싱 후에도 사라진 라인의 엔트리는 맵에 잔류할 수 있다 — append-only 로그에선 드물고 실사용상 무시 가능.)
/// - 합계는 엔트리 맵을 창(30일)으로 필터해 재계산(3만 건 순회 sub-ms).
///
/// 프라이버시(핵심 규약): 대화 본문·프롬프트·툴 결과 등 "내용" 필드는 절대 읽거나 보관하지 않는다.
/// 라인당 보는 것은 usage 숫자·message.id·requestId·timestamp·payload.type 뿐이고, 캐시/스냅샷에도 숫자만 남는다.
enum TokenUsageIncrementalScanner {
    /// 집계 창(일). now - windowDays 이전은 창 밖(합계 제외).
    static let windowDays = 30
    /// 캐시 보존 여유(일). 창(30일)보다 하루 넉넉히 잡아, 경계 근처 엔트리가 조기 퇴거로 사라지지 않게 한다.
    static let evictDays = 31

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
        var snapshot: TokenUsageSnapshot
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

        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)     // 30일 창(합계)
        let evictCutoff = now.addingTimeInterval(-Double(evictDays) * 86_400) // 31일 퇴거(보존)
        let cutoffTs14 = ts14(from: cutoff)
        let evictTs14 = ts14(from: evictCutoff)
        let cutoffMicros = micros(from: cutoff)
        let evictMicros = micros(from: evictCutoff)

        // 1) 퇴거(로드 시점): 31일 밖 엔트리/파일상태 제거. 무언가 지워지면 캐시 변경으로 표시(저장 유도).
        evict(&cache, evictTs14: evictTs14, evictMicros: evictMicros, changed: &stats.cacheChanged)

        // 2) 소스별 증분 스캔.
        scanClaude(&cache, homeDirectory: homeDirectory, cutoff: cutoff, evictTs14: evictTs14, stats: &stats)
        scanCodex(&cache, homeDirectory: homeDirectory, cutoff: cutoff, stats: &stats)

        // 3) 합계 재계산(엔트리 맵 창 필터 + codex 파일상태 창 필터).
        let snapshot = totals(cache, cutoffTs14: cutoffTs14, cutoffMicros: cutoffMicros, now: now)
        return Result(cache: cache, snapshot: snapshot, stats: stats)
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
        // 31일 밖(퇴거 대상)은 아예 저장하지 않는다 — 엔트리 맵을 ≤31일 규모로 유지. 합계 창 필터는 별도(30일).
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
        // 창/퇴거 판정 ts 는 이 키에서 '관측한 최대 ts14'를 유지한다(max-output 이 이긴 레코드의 ts 가 아니라).
        // 트레이드오프: max-output 값이 창밖 라인에서 왔더라도, 같은 키의 더 최신 라인이 창 안이면 그 값을 창 안으로
        // 계상한다(드문 reverse-straddle 에서 소폭 과다). 창밖 옛 스냅샷이 창 안 키를 통째로 탈락시키는
        // 과소집계보다 안전한 쪽을 택한다. 어느 순서로 들어와도 max(output)·max(ts) 라 결과는 결정적이다.
        if var existing = cache.claudeEntries[key] {
            let windowTs14 = max(existing.ts14, ts)
            if existing.output >= output {
                // output 은 안 바뀌어도 더 최신 라인을 봤으면 창 판정 ts 만 끌어올린다(대입만, 값은 유지).
                if windowTs14 != existing.ts14 {
                    existing.ts14 = windowTs14
                    cache.claudeEntries[key] = existing
                }
                return
            }
            // max-output 교체: 값(input/cache 포함)은 이 레코드로, 창 판정 ts 는 관측 최대치로.
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

    /// 엔트리 맵을 창(30일)으로 필터해 Claude 합계를, codex 파일상태를 창(파일 mtime)으로 필터해 Codex 합계를 낸다.
    private static func totals(_ cache: TokenUsageCache, cutoffTs14: Int, cutoffMicros: Int, now: Date) -> TokenUsageSnapshot {
        var claude = ClaudeTokenUsage()
        for (_, e) in cache.claudeEntries where e.ts14 >= cutoffTs14 {
            claude.input += e.input
            claude.output += e.output
            claude.cacheRead += e.cacheRead
            claude.cacheCreation += e.cacheCreation
        }
        var codex = CodexTokenUsage()
        for (_, s) in cache.codexFileStates where s.mtimeMicros >= cutoffMicros {
            codex.input += s.input
            codex.output += s.output
            codex.cached += s.cached
        }
        return TokenUsageSnapshot(claude: claude, codex: codex, scannedAt: now)
    }

    /// 31일 밖 엔트리/파일상태를 제거(로드·저장 시점). 무언가 지워지면 changed 를 세워 저장을 유도한다.
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
    /// mtime 프리필터: 컷오프보다 오래 손대지 않은 파일은 창 내 항목이 없으므로 열지 않는다(대량 스킵).
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
    /// 고정폭 UTC 라 이 정수 비교 == 사전식 비교 == 시간 순서(초 정밀도) — Date 파싱 없이 창을 가른다.
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

    /// Date 를 UTC 기준 YYYYMMDDHHMMSS 정수로(컷오프 접두어와 같은 스케일).
    private static func ts14(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
        let h = c.hour ?? 0, mi = c.minute ?? 0, s = c.second ?? 0
        return ((((y * 100 + mo) * 100 + d) * 100 + h) * 100 + mi) * 100 + s
    }

    /// Date 를 마이크로초 정수로(파일 mtime 의 == 비교/창 필터용 — 부동소수 왕복 오차 회피).
    private static func micros(from date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1_000_000).rounded())
    }
}

// MARK: - 전체 스캔 진입점 (증분 스캐너에 위임 — 정확성 테스트 호환)

/// 기존 API 호환용 얇은 진입점. 빈 캐시로 증분 갱신 = 전체 스캔이라, "첫 스캔 == 전체 스캔"을 코드로 보장한다.
enum TokenUsageScanner {
    static func scan(homeDirectory: URL, now: Date = Date()) -> TokenUsageSnapshot {
        TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: homeDirectory, now: now).snapshot
    }
}

// MARK: - 스토어 (@MainActor · 표시/영속/증분 갱신 게이팅)

/// 토큰 사용량의 표시·영속·증분 갱신을 담당한다. 스캔은 백그라운드(Task.detached)에서 캐시를 이어받아 돌고,
/// 메인 액터엔 결과만 반영한다. 상시 타이머/앱 전역 루프 없음 — 갱신은 팝오버 표시 중 뷰의 .task 루프에서만 일어난다.
///
/// 정책(30분 스로틀 대체): 팝오버 표시 즉시 1회 갱신 + 열려 있는 동안 30초 주기. 빠른 여닫이 churn 방지로
/// 마지막 갱신 후 minRefreshInterval(3초) 미만이면 스킵한다.
@Observable
@MainActor
final class TokenUsageStore {
    nonisolated static let snapshotKey = "check.tokenUsage.snapshot"
    /// 갱신 루프 주기(초). 팝오버가 열려 있는 동안만 이 주기로 돈다.
    nonisolated static let refreshPeriod: TimeInterval = 30
    /// 최소 갱신 간격(초). 마지막 갱신 후 이 시간 미만이면 갱신을 스킵한다(여닫이 churn 방지).
    nonisolated static let minRefreshInterval: TimeInterval = 3

    /// 표시용 스냅샷. nil(영속 없음/최초)이거나 total==0 이면 행을 그리지 않는다.
    private(set) var snapshot: TokenUsageSnapshot?
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
        // 재시작 후 즉시 표시: 영속 스냅샷을 먼저 읽어 첫 프레임부터 값을 보여 준다.
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(TokenUsageSnapshot.self, from: data) {
            snapshot = restored
        }
        // 최초 실행(영속 스냅샷 없음)엔 표시할 행이 없어(EmptyView) 뷰의 .task 를 신뢰할 수 없으므로, 첫 페인트를 위해
        // 여기서 1회 부트스트랩 스캔을 킥한다. 값이 잡히면 행이 뜨고, 이후 갱신은 그 행의 .task 루프가 맡는다.
        if snapshot == nil {
            startScan()
        }
    }

    /// 뷰(.task)에서 부르는 갱신 루프. 표시 즉시 1회 + 이후 refreshPeriod 주기. 뷰가 사라지면 Task 취소로 끝난다.
    func runRefreshLoop() async {
        while !Task.isCancelled {
            await refreshNow()
            // tolerance 를 넉넉히 줘 정확한 타이밍을 요구하지 않는다(절전 — 시스템이 웨이크업을 뭉칠 수 있게).
            try? await Task.sleep(for: .seconds(Self.refreshPeriod), tolerance: .seconds(5))
        }
    }

    /// 즉시 1회 갱신. 진행 중이면 그 완료를 기다리고, 마지막 갱신 후 minRefreshInterval 미만이면 스킵한다.
    func refreshNow() async {
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
            let (newCache, snapshot) = await Task.detached(priority: .utility) { () -> (TokenUsageCache, TokenUsageSnapshot) in
                let base = inMemory ?? TokenUsageCacheStore.load(from: url)
                let result = TokenUsageIncrementalScanner.update(base, homeDirectory: home, now: now)
                // 새 데이터가 있을 때만 저장(무변경 갱신에선 쓰기 0).
                if result.stats.cacheChanged {
                    TokenUsageCacheStore.save(result.cache, to: url)
                }
                return (result.cache, result.snapshot)
            }.value
            guard let self else { return }
            self.cache = newCache
            self.apply(snapshot)
            self.isScanning = false
            self.scanTask = nil
        }
    }

    private func apply(_ result: TokenUsageSnapshot) {
        // 인메모리엔 항상 반영해 scannedAt(표시용 신선도)을 확보한다.
        snapshot = result
        // 영속(UserDefaults)은 표시할 값이 있을 때만 — 로그가 없는(집계 0) 머신은 재실행 때 다시 부트스트랩한다.
        if result.total > 0, let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }
}

// MARK: - 뷰 (CheckTokenUsageRow)

/// 팝오버 하단 슬림 행. 스냅샷이 없거나 집계 0 이면 아무것도 그리지 않는다(EmptyView — 빈 자리/간격 없음).
/// 값이 있으면 FooterBar 톤(panelStyle · 가로 12/세로 8)의 한 줄: sparkles + "최근 30일 AI 토큰" + 우측 총합(굵게).
/// CheckMenuView 가 인자 없이 CheckTokenUsageRow() 로 마운트하므로 스토어는 뷰가 소유한다(@State).
struct CheckTokenUsageRow: View {
    @State private var store = TokenUsageStore()

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot, snapshot.total > 0 {
            slimRow(snapshot)
                // 표시 중에만 도는 구조적 루프(즉시 1회 + 30초 주기). 팝오버가 닫혀 행이 사라지면 자동 취소된다.
                // EmptyView(집계 0) 브랜치엔 걸지 않는다 — 라이프사이클을 못 믿는 대신 부트스트랩 스캔이 첫 행을 띄운다.
                .task { await store.runRefreshLoop() }
        } else {
            // 표시할 사용량 없음(로그 부재/집계 0) — 행을 아예 그리지 않는다.
            EmptyView()
        }
    }

    private func slimRow(_ snapshot: TokenUsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text("최근 30일 AI 토큰")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(TokenAbbreviation.short(snapshot.total))
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
        // 스캔 중엔 살짝 흐리게(절제된 진행 표시). 값은 이전 스냅샷을 유지하다 완료 시 교체된다.
        .opacity(store.isScanning ? 0.55 : 1)
        .help(snapshot.detailTooltip)
    }
}
