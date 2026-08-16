import Foundation

// MARK: - Codex 집계 진단 (숫자만 · 전량 재순회 · 상태 없음)

/// Codex 집계 진단 스냅샷. **숫자만** 담는다 — 대화 본문·프롬프트·파일 경로·파일명은 일절 포함하지 않는다.
///
/// 왜 필요한가: 순위판에서 Codex 코호트의 하루당 토큰 중앙값이 Claude 코호트의 20배로 나오고, 같은 사람이 달마다
/// 50배씩 양방향으로 튄다. Claude 집계는 지상 실측과 0.05% 오차라 대조군이고, 결함은 Codex 경로에 있다.
/// 이 스냅샷은 "앱이 왜 그 숫자를 냈는가"를 현장에서 가르기 위한 계측이다 — 앱 산식(증분 델타 합)과 서로 독립적인
/// 대조 산식(세션 최종 누적치 합)을 나란히 담고, 둘이 갈리게 만드는 후보 원인(파일 간 중복 계상 · resume 카운터
/// 이월 · 누적 리셋 · 단일 파일 편중)을 각각 세어 둔다.
///
/// 프라이버시 규약(구조적 보증): 이 타입에는 **문자열 필드가 하나도 없다.** 필드를 추가하지 마라 — 문자열이 하나라도
/// 생기는 순간 경로·파일명·본문이 새어 나갈 통로가 열린다. 스캐너가 읽는 필드도 payload.type /
/// payload.info.total_token_usage.{input_tokens,output_tokens} / timestamp 뿐이다.
///
/// **렌즈 규약: 모든 계측값은 `compute(month:)` 로 넘긴 "대상 월" 하나를 기준으로 센다.** 파일 전체를 걸어가며
/// 누적 카운터를 잇는 것과, 무엇을 세는지는 별개다 — 세는 건 언제나 대상 월에 귀속된 이벤트뿐이다. 렌즈가 섞인
/// 진단은 읽는 사람을 틀리게 만든다(초판이 실제로 그랬다: 6월에 시작해 7월까지 이어진 세션이 7월 조회에서
/// 6월 누적치를 "이 달 이월"로 보고해 30배 괴리를 냈다). 예외는 두 개뿐이고 각각 아래에 명시했다
/// — `filesTotal`(전 기간 분모)과 `appBuild`(값의 출처 표시).
struct CodexUsageDiagnostics: Codable, Equatable, Sendable {
    /// **전 기간** rollout 파일 총 개수(mtime 프리필터 없이 전량). 월 렌즈의 예외 — `filesMonth` 의 분모다.
    var filesTotal: Int = 0
    /// 대상 월 이벤트가 하나라도 있는 파일 수.
    var filesMonth: Int = 0
    /// 대상 월 token_count 이벤트 수.
    var eventsMonth: Int = 0
    /// 대상 월 이벤트 중 단일 이벤트 최대 델타. 비정상적으로 크면 누적 카운터가 점프했다는 뜻이다.
    var maxDelta: Int = 0
    /// 파일의 **첫** token_count 이벤트가 **대상 월에 속하면서** 그 누적치가 20만을 넘는 파일 수(resume 카운터 이월 의심).
    /// 첫 이벤트가 지난달이면 이 달 합계에 이월 효과가 없으므로 세지 않는다.
    var carryFiles: Int = 0
    /// 그 파일들의 첫 이벤트 누적치 합 = **"파일마다 0 에서 시작하는 산식 탓에 대상 월에 잘못 더해진 양"의 상한 추정치**.
    /// 상한인 이유: 첫 이벤트는 prevCumulative==0 이라 델타가 누적치 전액이 되는데, 그 전액은 직전 세션에서 이미
    /// 계상됐을 수 있는 몫까지 포함하기 때문이다(실제 신규분은 그보다 작거나 같다).
    var carryTotal: Int = 0
    /// 대상 월 이벤트에서 (timestamp, cum) 쌍이 2개 이상 파일에 나타난 개수(0 이 아니면 파일 간 중복 계상).
    var dupEvents: Int = 0
    /// 그 중복분이 대상 월 앱 산식에 더해 넣은 토큰 추정합(중복 쌍의 첫 출현을 제외한 나머지 델타의 합).
    var dupTokens: Int = 0
    /// 대조 산식: 파일별 '**대상 월** 마지막 누적치' 합. 세션당 한 번만 세므로 델타 재계상이 있으면 앱값이 이보다 크다.
    var finalSum: Int = 0
    /// 대상 월 앱 산식 총합에 파일 간 중복 제거를 적용한 값(= 앱 산식 총합 − dupTokens).
    /// 앱 산식 총합은 dedupTotal + dupTokens 로 복원된다.
    var dedupTotal: Int = 0
    /// **대상 월 이벤트에서** 일어난 누적 감소(리셋) 횟수. 앱 산식은 max(0,…) 로 클램프하므로 여기서 토큰이 유실된다.
    var drops: Int = 0
    /// 대상 월 기준 단일 파일 최대 기여. 총합 대비 비중이 크면 한 세션이 그 달을 좌우한다는 뜻이다.
    var topFile: Int = 0
    /// 이 값을 만든 앱 CFBundleVersion. 빌드가 바뀌면 산식도 바뀔 수 있으므로 값과 함께 다닌다(월 렌즈의 예외).
    var appBuild: Int = 0

    init(
        filesTotal: Int = 0, filesMonth: Int = 0, eventsMonth: Int = 0, maxDelta: Int = 0,
        carryFiles: Int = 0, carryTotal: Int = 0, dupEvents: Int = 0, dupTokens: Int = 0,
        finalSum: Int = 0, dedupTotal: Int = 0, drops: Int = 0, topFile: Int = 0, appBuild: Int = 0
    ) {
        self.filesTotal = filesTotal
        self.filesMonth = filesMonth
        self.eventsMonth = eventsMonth
        self.maxDelta = maxDelta
        self.carryFiles = carryFiles
        self.carryTotal = carryTotal
        self.dupEvents = dupEvents
        self.dupTokens = dupTokens
        self.finalSum = finalSum
        self.dedupTotal = dedupTotal
        self.drops = drops
        self.topFile = topFile
        self.appBuild = appBuild
    }

    /// 누락 키를 기본값 0 으로 흡수한다(인코딩은 합성 구현). 이 스냅샷은 앱 빌드를 건너 저장·전송되므로,
    /// 옛 빌드가 쓴 부분 페이로드를 새 빌드가 읽을 때 통째로 실패하지 않게 한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filesTotal = try c.decodeIfPresent(Int.self, forKey: .filesTotal) ?? 0
        filesMonth = try c.decodeIfPresent(Int.self, forKey: .filesMonth) ?? 0
        eventsMonth = try c.decodeIfPresent(Int.self, forKey: .eventsMonth) ?? 0
        maxDelta = try c.decodeIfPresent(Int.self, forKey: .maxDelta) ?? 0
        carryFiles = try c.decodeIfPresent(Int.self, forKey: .carryFiles) ?? 0
        carryTotal = try c.decodeIfPresent(Int.self, forKey: .carryTotal) ?? 0
        dupEvents = try c.decodeIfPresent(Int.self, forKey: .dupEvents) ?? 0
        dupTokens = try c.decodeIfPresent(Int.self, forKey: .dupTokens) ?? 0
        finalSum = try c.decodeIfPresent(Int.self, forKey: .finalSum) ?? 0
        dedupTotal = try c.decodeIfPresent(Int.self, forKey: .dedupTotal) ?? 0
        drops = try c.decodeIfPresent(Int.self, forKey: .drops) ?? 0
        topFile = try c.decodeIfPresent(Int.self, forKey: .topFile) ?? 0
        appBuild = try c.decodeIfPresent(Int.self, forKey: .appBuild) ?? 0
    }
}

/// ~/.codex/sessions 를 전량 1회 순회해 진단값을 만든다. 순수 함수(상태 없음) — Task.detached 에서 돈다.
///
/// 산식은 프로덕션 스캐너(TokenUsageIncrementalScanner.scanCodex)의 Codex 경로를 **그대로 재현**한다:
/// 파일마다 prevCumulative 0 에서 시작해 token_count 이벤트마다 delta = max(0, cum − prevCumulative) 를
/// 그 이벤트 timestamp(→KST)의 월에 귀속한다. cum = total_token_usage.(input_tokens + output_tokens).
/// info/total/timestamp 결손 이벤트는 건너뛰되 prevCumulative 를 갱신하지 않는다(다음 유효 이벤트가 흡수).
///
/// 차이는 둘뿐이고, 둘 다 "진단은 전량을 본다"는 목적에서 나온다:
/// 1) 증분 캐시·mtime 프리필터가 없다(모든 rollout 파일을 offset 0 부터 읽는다).
/// 2) 개행 없이 끝나는 마지막 라인도 파싱한다(증분 스캐너는 다음 갱신을 위해 남겨 두지만, 여기선 다음이 없다).
///
/// 비용: 전량 순회라 비싸다. 호출측이 **앱 빌드당 1회만** 부르는 것을 전제로 캐시를 두지 않는다.
enum CodexUsageDiagnosticsScanner {
    /// month 는 KST 'YYYY-MM'. appBuild 는 결과에 그대로 실려 나간다(값의 출처 표시).
    static func compute(homeDirectory: URL, month: String, appBuild: Int) -> CodexUsageDiagnostics {
        var result = CodexUsageDiagnostics()
        result.appBuild = appBuild

        let root = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = rolloutFiles(under: root)
        result.filesTotal = files.count
        guard !files.isEmpty else { return result }

        // 스캔 중 변하는 상태는 전부 참조 타입 한 곳에 모은다 — 스트리밍 콜백이 지역 var 를 inout 으로 잡으면
        // 배타적 접근이 겹칠 수 있어서다(기존 스캐너가 캐시 맵을 클로저 밖으로 뺀 것과 같은 이유).
        let state = ScanState(month: month)

        for (index, url) in files.enumerated() {
            state.beginFile(index: index)
            streamLines(at: url) { line in
                state.ingest(line)
            }
            state.endFile()
        }

        result.filesMonth = state.filesMonth
        result.eventsMonth = state.eventsMonth
        result.maxDelta = state.maxDelta
        result.carryFiles = state.carryFiles
        result.carryTotal = state.carryTotal
        result.drops = state.drops
        result.finalSum = state.finalSum
        result.topFile = state.topFile
        // (timestamp, cum) 이 2개 이상 **파일**에 나타난 키만 중복으로 센다. 같은 파일 안의 반복은 누적치가 그대로라
        // 델타 0 이므로 애초에 총합을 부풀리지 않는다 — 부풀리는 건 파일을 건너뛴 재출현뿐이다.
        result.dupEvents = state.duplicateKeyCount()
        result.dupTokens = state.dupTokens
        result.dedupTotal = state.appTotal - state.dupTokens
        return result
    }

    // MARK: 스캔 상태

    /// 한 번의 compute 동안만 사는 가변 상태. 파일 경계(beginFile/endFile)와 이벤트 수집(ingest)을 함께 들고 있다.
    /// 문자열은 내부 계산(월키·중복키)에만 쓰이고 결과 타입으로 나가지 않는다.
    private final class ScanState {
        /// (timestamp, cum) 키의 출현 이력: 마지막으로 본 파일 인덱스 + 지금까지 본 서로 다른 파일 수.
        /// 파일을 순서대로 훑으므로 같은 키의 동일 파일 내 반복은 lastFileIndex 비교만으로 걸러진다.
        private struct KeySighting {
            var lastFileIndex: Int
            var fileCount: Int
        }

        /// 파일에서 맨 처음 처리된 token_count 이벤트. 그 이벤트만 prevCumulative==0 을 만나 델타가 누적치 전액이 된다.
        /// 그게 대상 월에 속할 때만 이 달 합계가 부풀므로, 누적치와 함께 '대상 월 소속'을 같이 들고 다닌다.
        private struct FirstEvent {
            var cumulative: Int
            var inMonth: Bool
        }

        private let month: String

        // 파일별(파일 경계에서 리셋)
        private var fileIndex = 0
        private var prevCumulative = 0
        private var firstEvent: FirstEvent?
        private var monthContrib = 0
        private var lastCumulativeInMonth = 0
        private var touched = false

        // 전역 누적
        private(set) var appTotal = 0
        private(set) var finalSum = 0
        private(set) var filesMonth = 0
        private(set) var eventsMonth = 0
        private(set) var maxDelta = 0
        private(set) var drops = 0
        private(set) var carryFiles = 0
        private(set) var carryTotal = 0
        private(set) var topFile = 0
        private(set) var dupTokens = 0
        private var sightings: [String: KeySighting] = [:]

        init(month: String) { self.month = month }

        func beginFile(index: Int) {
            fileIndex = index
            prevCumulative = 0
            firstEvent = nil
            monthContrib = 0
            lastCumulativeInMonth = 0
            touched = false
        }

        func endFile() {
            guard touched else { return }
            filesMonth += 1
            appTotal += monthContrib
            finalSum += lastCumulativeInMonth
            topFile = max(topFile, monthContrib)
            // resume 카운터 이월: 이 파일의 **첫** token_count 는 prevCumulative==0 을 만나 델타가 누적치 전액이 된다.
            // 그 이벤트가 대상 월에 속할 때만 전액이 이 달로 들어가므로(첫 이벤트가 지난달이면 이 달엔 무해하다),
            // 'inMonth' 를 함께 본다. 20만 문턱 초과분만 이월로 의심한다(정상 세션의 첫 응답은 그보다 훨씬 작다).
            if let first = firstEvent, first.inMonth, first.cumulative > 200_000 {
                carryFiles += 1
                carryTotal += first.cumulative
            }
        }

        /// 한 라인을 파싱해 상태에 반영한다. 프로덕션 Codex 경로와 같은 순서·같은 스킵 규약.
        func ingest(_ line: UnsafeRawBufferPointer) {
            guard contains(line, tokenCountPattern) else { return }
            guard let base = line.baseAddress,
                  let object = try? JSONSerialization.jsonObject(
                      with: Data(bytes: base, count: line.count)
                  ) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { return }   // info null·total 결손: 건너뛰되 prevCumulative 갱신 안 함(다음 유효 이벤트가 흡수).
            guard let timestamp = object["timestamp"] as? String,
                  let monthKey = kstMonthKey(fromTimestamp: timestamp)
            else { return }

            let cum = intField(total["input_tokens"]) + intField(total["output_tokens"])
            let inMonth = (monthKey == month)
            // prevCumulative 는 대상 월 밖 이벤트로도 계속 전진해야 한다 — 그래야 이 달 첫 델타의 기준선이 맞는다.
            // 월 렌즈가 가르는 건 '무엇을 세느냐'지 '어떻게 걸어가느냐'가 아니다.
            if firstEvent == nil { firstEvent = FirstEvent(cumulative: cum, inMonth: inMonth) }
            if inMonth, cum < prevCumulative { drops += 1 }
            let delta = max(0, cum - prevCumulative)
            prevCumulative = cum
            guard inMonth else { return }

            monthContrib += delta
            eventsMonth += 1
            touched = true
            lastCumulativeInMonth = cum
            maxDelta = max(maxDelta, delta)

            // 중복 계상 추적. NUL 구분자(타임스탬프에 NUL 이 들어갈 수 없어 충돌 불가).
            let key = "\(timestamp)\u{0}\(cum)"
            if var seen = sightings[key] {
                if seen.lastFileIndex != fileIndex {
                    // 다른 파일에서 같은 이벤트가 또 나왔다 = 첫 출현 이후의 재계상. 그 델타가 총합을 부풀린 몫이다.
                    seen.lastFileIndex = fileIndex
                    seen.fileCount += 1
                    sightings[key] = seen
                    dupTokens += delta
                }
            } else {
                sightings[key] = KeySighting(lastFileIndex: fileIndex, fileCount: 1)
            }
        }

        func duplicateKeyCount() -> Int {
            var n = 0
            for (_, s) in sightings where s.fileCount > 1 { n += 1 }
            return n
        }
    }

    // MARK: 파일 순회 / 스트리밍

    /// root 아래를 재귀 순회해 이름이 "rollout-" 으로 시작하고 확장자가 jsonl 인 정규 파일을 경로 사전순으로 돌려준다.
    /// mtime 프리필터가 없다 — 진단은 전량을 봐야 "이 달 이벤트가 있는 파일" 자체가 옳게 골라졌는지 검증할 수 있다.
    /// 정렬은 결정성을 위해서다(중복 키의 '첫 출현' 귀속이 순회 순서에 의존한다).
    private static func rolloutFiles(under root: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: nil
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// 파일 전체를 1MB 청크로 읽어 개행 단위 라인을 body 로 흘려보낸다(메모리 상수). 열기 실패면 조용히 지나간다.
    /// 증분 스캐너와 달리 개행 없이 끝나는 마지막 조각도 넘긴다 — 이어읽기가 없는 1회성 전량 스캔이라
    /// 남겨 둘 "다음 갱신"이 없다. 쓰다 만 라인이면 JSON 파싱에서 걸러지므로 안전하다.
    private static func streamLines(at url: URL, _ body: (UnsafeRawBufferPointer) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var carry: [UInt8] = []
        let chunkSize = 1 << 20
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
                            carry.append(contentsOf: bytes[start..<i])
                            carry.withUnsafeBytes { body($0) }
                            carry.removeAll(keepingCapacity: true)
                        }
                        start = i + 1
                    }
                    i += 1
                }
                if start < count { carry.append(contentsOf: bytes[start..<count]) }
            }
        }
        if !carry.isEmpty { carry.withUnsafeBytes { body($0) } }
    }

    // MARK: 헬퍼 (이 파일 안에서 자족 — 프로덕션 스캐너의 private 헬퍼를 건드리지 않는다)

    /// 라인 프리체크용 바이트 패턴. 매칭되는 라인에서만 JSON 디코드 비용을 치른다.
    private static let tokenCountPattern = Array("token_count".utf8)

    /// 원시 바이트 버퍼에 짧은 needle 이 들어 있는지(단순 바이트 스캔). Data 브리징 비용을 피한다.
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

    /// UTC ISO8601 타임스탬프(예 "2026-07-24T07:17:35.634Z")를 KST(+9)로 본 월키 'YYYY-MM'.
    /// 앞 19자(YYYY-MM-DDTHH:MM:SS)만 고정폭으로 읽어 UTC 컴포넌트를 만든 뒤 +9시간을 일·월·연 올림까지
    /// 정직하게 처리한다(문자열 산술의 경계 버그 회피). KST 는 1988년 이후 서머타임이 없어 고정 오프셋이 정확하다.
    private static func kstMonthKey(fromTimestamp s: String) -> String? {
        let b = Array(s.utf8)
        guard b.count >= 19 else { return nil }
        // 연(0..3) 월(5,6) 일(8,9) 시(11,12) 분(14,15) 초(17,18) — 나머지는 구분자('-' 'T' ':').
        for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
            let c = b[i]
            guard c >= 48, c <= 57 else { return nil }
        }
        func num(_ start: Int, _ len: Int) -> Int {
            var v = 0
            for k in start..<(start + len) { v = v * 10 + Int(b[k] - 48) }
            return v
        }
        var year = num(0, 4)
        var month = num(5, 2)
        var day = num(8, 2)
        let hour = num(11, 2)
        guard month >= 1, month <= 12, day >= 1, day <= daysInMonth(year: year, month: month), hour <= 23 else {
            return nil
        }
        // +9h: 시가 24를 넘으면 하루, 하루가 그 달을 넘으면 달, 달이 12를 넘으면 해를 올린다.
        if hour + 9 >= 24 {
            day += 1
            if day > daysInMonth(year: year, month: month) {
                day = 1
                month += 1
                if month > 12 { month = 1; year += 1 }
            }
        }
        return String(format: "%04d-%02d", year, month)
    }

    /// 그레고리력 월별 일수(윤년 규칙 포함). +9시간 올림에서 월 경계를 정확히 넘기기 위한 것.
    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        default: return 0
        }
    }
}
