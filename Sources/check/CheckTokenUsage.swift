import Foundation
import Observation
import SwiftUI

// MARK: - 집계 모델 (스냅샷)

/// 최근 30일 AI CLI 토큰 사용량 집계 결과. UserDefaults 에 JSON 으로 영속해 재시작 즉시 표시한다.
///
/// 프라이버시: 여기 담기는 값은 usage 숫자와 스캔 시각뿐이다. 대화 본문·프롬프트·파일 경로 등 내용 필드는
/// 스캔 단계에서 읽지도 보관하지도 않는다(아래 TokenUsageScanner 주석 참고).
struct TokenUsageSnapshot: Codable, Equatable, Sendable {
    var claude: ClaudeTokenUsage
    var codex: CodexTokenUsage
    /// 이 집계를 만든 스캔 시각. 30분 스로틀(재스캔 여부) 판정 기준이자 영속 스냅샷의 신선도 기준.
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

// MARK: - 스캐너 (순수 · nonisolated, 백그라운드 실행)

/// 로컬 AI CLI 로그에서 최근 30일 토큰 사용량을 집계한다. 상태 없는 순수 로직이라 Task.detached 에서 실행하고
/// 결과 스냅샷만 메인 액터로 돌려보낸다. homeDirectory 주입으로 테스트가 실제 홈을 건드리지 않게 한다.
///
/// 프라이버시(핵심 규약): 대화 본문·프롬프트·툴 결과 등 "내용" 필드는 절대 읽거나 보관하지 않는다.
/// 라인당 보는 것은 usage 숫자·message.id·requestId·timestamp·payload.type 뿐이고, 집계 결과에도 숫자만 남는다.
///
/// 성능: 파일은 mtime 프리필터(컷오프 이전 파일 통째 스킵) → 청크 스트리밍(전체 로드 금지) → 라인 단위
/// 바이트 부분검색 프리체크 후에만 JSONSerialization 디코드. 파이썬 오라클 3.2초/869MB 대비 여유 목표 < 10초.
enum TokenUsageScanner {
    /// 집계 창(일). now - windowDays 이전은 창 밖.
    static let windowDays = 30

    // 라인 프리체크용 바이트 패턴(String 생성 없이 원시 바이트 부분검색). 디코드 비용을 매칭 라인으로만 한정한다.
    private static let usagePattern = Array(#""usage""#.utf8)
    private static let assistantPattern = Array(#""assistant""#.utf8)
    private static let tokenCountPattern = Array("token_count".utf8)

    /// 두 소스를 모두 스캔해 스냅샷을 만든다. now 는 창/스캔시각 기준(주입 가능).
    static func scan(homeDirectory: URL, now: Date = Date()) -> TokenUsageSnapshot {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        // Claude 라인 창 판정은 timestamp 문자열의 앞 19자("YYYY-MM-DDTHH:MM:SS", 전부 UTC)를 사전식으로 비교한다.
        // 고정폭 UTC ISO8601 은 사전식 순서 == 시간 순서라, 라인마다 Date 파싱 없이 초 단위로 창을 가른다.
        let cutoffPrefix = utcSecondPrefix(cutoff)
        let claude = scanClaude(homeDirectory: homeDirectory, cutoff: cutoff, cutoffPrefix: cutoffPrefix)
        let codex = scanCodex(homeDirectory: homeDirectory, cutoff: cutoff)
        return TokenUsageSnapshot(claude: claude, codex: codex, scannedAt: now)
    }

    // MARK: Claude Code

    /// ~/.claude/projects/**/*.jsonl. type=="assistant" + usage 라인만 디코드하고, (message.id, requestId)
    /// 글로벌 dedupe 로 세션 포크/이어가기로 파일 간 복제된 히스토리의 과대집계를 막는다.
    private static func scanClaude(homeDirectory: URL, cutoff: Date, cutoffPrefix: String) -> ClaudeTokenUsage {
        var usage = ClaudeTokenUsage()
        // dedupe 키 집합. 30일 매칭 라인 규모(수만)라 메모리 부담은 작다.
        var seen = Set<String>()
        let root = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        forEachRecentFile(under: root, cutoff: cutoff, matching: { $0.pathExtension == "jsonl" }) { fileURL in
            forEachLine(at: fileURL) { line in
                // 프리체크: "usage"(가장 선택적 — assistant 라인에만 등장)를 먼저, 그 다음 "assistant".
                // 둘 다 있어야 디코드한다(대다수 라인은 여기서 조기 배제 — 디코드 비용을 매칭 라인으로 한정).
                guard contains(line, usagePattern), contains(line, assistantPattern) else { return }
                guard let object = try? JSONSerialization.jsonObject(with: Data(bytes: line.baseAddress!, count: line.count)) as? [String: Any],
                      object["type"] as? String == "assistant",
                      let timestamp = object["timestamp"] as? String,
                      String(timestamp.prefix(19)) >= cutoffPrefix,
                      let message = object["message"] as? [String: Any],
                      let usageObject = message["usage"] as? [String: Any]
                else { return }
                // (message.id, requestId) 쌍으로 dedupe. 널 구분용 NUL 구분자로 이어 붙인다(오라클과 동일 의미).
                let key = "\(message["id"] as? String ?? "")\u{0}\(object["requestId"] as? String ?? "")"
                guard seen.insert(key).inserted else { return }
                // 누락/널 필드는 0. 내용 필드는 건드리지 않는다.
                usage.input += intField(usageObject["input_tokens"])
                usage.output += intField(usageObject["output_tokens"])
                usage.cacheRead += intField(usageObject["cache_read_input_tokens"])
                usage.cacheCreation += intField(usageObject["cache_creation_input_tokens"])
            }
        }
        return usage
    }

    // MARK: Codex

    /// ~/.codex/sessions/**/rollout-*.jsonl. 각 파일(세션)의 "마지막" 유효 payload.type=="token_count" 의
    /// info.total_token_usage(누적치)를 그 세션 값으로 채택해 파일 단위로 합산한다(세션 내부 합산 아님).
    private static func scanCodex(homeDirectory: URL, cutoff: Date) -> CodexTokenUsage {
        var usage = CodexTokenUsage()
        let root = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        forEachRecentFile(
            under: root,
            cutoff: cutoff,
            matching: { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
        ) { fileURL in
            var lastInput = 0, lastOutput = 0, lastCached = 0
            var found = false
            forEachLine(at: fileURL) { line in
                guard contains(line, tokenCountPattern) else { return }
                guard let object = try? JSONSerialization.jsonObject(with: Data(bytes: line.baseAddress!, count: line.count)) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any]
                else { return }
                // 마지막 유효 token_count 로 덮어쓴다 — 누적치이므로 파일 최종값이 그 세션의 전체 사용량.
                lastInput = intField(total["input_tokens"])
                lastOutput = intField(total["output_tokens"])
                lastCached = intField(total["cached_input_tokens"])
                found = true
            }
            if found {
                usage.input += lastInput   // input_tokens 는 캐시 포함 누적
                usage.output += lastOutput
                usage.cached += lastCached
            }
        }
        return usage
    }

    // MARK: 파일 순회 / 스트리밍

    /// root 아래를 재귀 순회하며 matching 을 통과하고 mtime 이 cutoff 이후인 정규 파일만 body 로 넘긴다.
    /// mtime 프리필터: 컷오프보다 오래 손대지 않은 파일은 창 내 항목이 없으므로 열지 않는다(대량 스킵).
    private static func forEachRecentFile(
        under root: URL,
        cutoff: Date,
        matching: (URL) -> Bool,
        _ body: (URL) -> Void
    ) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: nil
        ) else { return }
        for case let url as URL in enumerator {
            guard matching(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            if let mtime = values.contentModificationDate, mtime < cutoff { continue }
            body(url)
        }
    }

    /// 파일을 1MB 청크로 읽어 개행 단위 라인을 원시 바이트 버퍼로 흘려보낸다. 전체를 메모리에 올리지 않으며,
    /// 라인을 String/Data 로 만들지 않고 바이트 포인터로 넘겨(청크 안 라인은 무복사) 프리체크 후에만 디코드하게 한다.
    /// body 로 넘어가는 버퍼는 그 호출 동안만 유효하다(즉시 소비 — 프리체크/필요 시 Data 복사).
    private static func forEachLine(at url: URL, _ body: (UnsafeRawBufferPointer) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        // 청크 경계를 걸친 미완결 라인만 이월한다(대개 비어 있어 무복사 경로를 탄다).
        var carry: [UInt8] = []
        let chunkSize = 1 << 20
        // try? 가 Data? 를 평탄화하므로 chunk 는 Data. EOF(nil)·오류(nil)·빈 청크에서 루프를 벗어난다.
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
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
                        start = i + 1
                    }
                    i += 1
                }
                // 개행 없이 남은 꼬리 조각을 다음 청크로 이월한다.
                if start < count {
                    carry.append(contentsOf: bytes[start..<count])
                }
            }
        }
        if !carry.isEmpty {
            carry.withUnsafeBytes { body($0) }
        }
    }

    // MARK: 헬퍼

    /// 원시 바이트 버퍼에 짧은 needle 패턴이 들어 있는지(단순 바이트 스캔). Data.range(of:) 의 브리징 비용을 피해
    /// 873MB 프리체크를 저렴하게 유지한다. needle 은 짧아(≤11B) 나이브 검색으로 충분히 빠르다.
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

    /// UTC 기준 "YYYY-MM-DDTHH:MM:SS"(19자)를 만든다. Claude timestamp 앞 19자와 사전식 비교하기 위한 컷오프 접두어.
    private static func utcSecondPrefix(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }
}

// MARK: - 스토어 (@MainActor · 결과 반영/영속/스로틀만)

/// 토큰 사용량 스냅샷의 표시·영속·재스캔 게이팅을 담당한다. 스캔 자체는 백그라운드(Task.detached)에서 돌고
/// 메인 액터엔 결과만 반영한다. 타이머/상시 루프 없음 — 갱신은 팝오버 표시(onAppear)에서 30분 스로틀로만 일어난다.
@Observable
@MainActor
final class TokenUsageStore {
    nonisolated static let snapshotKey = "check.tokenUsage.snapshot"
    /// 재스캔 스로틀(초). 마지막 성공 스캔 후 이 시간이 지나야 다시 스캔한다.
    nonisolated static let refreshInterval: TimeInterval = 30 * 60

    /// 표시용 스냅샷. nil(영속 없음/최초)이거나 total==0 이면 행을 그리지 않는다.
    private(set) var snapshot: TokenUsageSnapshot?
    /// 스캔 진행 중 여부. 재진입 방지 + UI 절제(불투명도) 표시에 쓴다.
    private(set) var isScanning = false

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let clock: () -> Date
    // 진행 중 스캔 핸들(재진입 방지). 관찰 대상 아님.
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.clock = clock
        // 재시작 후 즉시 표시: 영속 스냅샷을 먼저 읽어 첫 프레임부터 값을 보여 준다.
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(TokenUsageSnapshot.self, from: data) {
            snapshot = restored
        }
        // 최초 실행(영속 스냅샷 없음)엔 빈 상태가 EmptyView 라 뷰 onAppear 를 신뢰할 수 없으므로, 첫 페인트를 위해
        // 여기서 1회 부트스트랩 스캔을 킥한다. 이후 갱신은 뷰 onAppear + 스로틀로만 일어난다(타이머/루프 없음).
        if snapshot == nil {
            refreshIfStale()
        }
    }

    /// 팝오버 표시(onAppear)에서 호출. 진행 중이면(재진입) 무시하고, 마지막 스캔이 30분 지났을 때만 재스캔한다.
    func refreshIfStale() {
        guard scanTask == nil else { return }
        guard Self.shouldRescan(lastScannedAt: snapshot?.scannedAt, now: clock()) else { return }
        startScan()
    }

    /// 진행 중 스캔이 있으면 끝날 때까지 기다린다. 테스트 결정성용 — 전체 스위트 병렬 실행에서 .utility
    /// 백그라운드 태스크가 기아 상태가 되면 고정 시간 폴링은 플레이크가 되므로, 태스크 자체를 await 한다.
    func awaitScanCompletion() async {
        await scanTask?.value
    }

    /// 재스캔 여부(순수 · 주입 clock 으로 결정적). last 없으면 최초라 항상 스캔, 아니면 interval 경과 시에만.
    nonisolated static func shouldRescan(lastScannedAt: Date?, now: Date, interval: TimeInterval = refreshInterval) -> Bool {
        guard let last = lastScannedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    private func startScan() {
        isScanning = true
        let home = homeDirectory
        let now = clock()
        scanTask = Task { @MainActor [weak self] in
            // 스캔은 유틸리티 우선순위 백그라운드에서. 메인엔 완료 후 결과만 반영한다.
            let result = await Task.detached(priority: .utility) {
                TokenUsageScanner.scan(homeDirectory: home, now: now)
            }.value
            guard let self else { return }
            self.apply(result)
            self.isScanning = false
            self.scanTask = nil
        }
    }

    private func apply(_ result: TokenUsageSnapshot) {
        // 인메모리엔 항상 반영해 scannedAt(스로틀 기준)을 확보한다.
        snapshot = result
        // 영속은 표시할 값이 있을 때만 — 로그가 없는(집계 0) 머신은 재실행 때 다시 부트스트랩해 새 로그를 잡는다.
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
            // 행이 실제로 그려질 때(팝오버 표시) 신선도 체크 후 필요 시에만 재스캔한다.
            .onAppear { store.refreshIfStale() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot, snapshot.total > 0 {
            slimRow(snapshot)
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
