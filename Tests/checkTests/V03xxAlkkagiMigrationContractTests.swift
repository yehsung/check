import Foundation
import Testing
@testable import CheckCore

// 1:1 알까기 v2 — **서버 초안 ↔ 앱 글자 대조**(alkkagi/v2 SPEC v1.1 §7.2 T `V03xxAlkkagiMigrationContractTests`).
//
// 스텁 서버 시험은 서버가 **무엇을 부르고 무엇을 내는지**를 앱이 적은 대로 가정한다 — 이름 한 글자가 갈려도 전부 초록이다
// (메모리 stub-tests-hide-roundtrip-bugs). 그래서 초안 **원문**과 앱 상수를 맞댄다(C 의 FixtureContract 가 이미 재는 요청 본문 키 ·
// 봉투 키 · status ⊆ 열거는 되풀이하지 않고, 반대 방향과 서명 · 정본 조각을 잰다):
//   ① 클라 RPC 15 = 초안 §11 실행권 표(`v_rpc`) = `AlkkagiOnlineWire.RPC.all` · 정의 출처(초안 다섯 · v1 열) · 서명이 바뀌는 것은 신청
//      하나(옛 3인자 서명 drop 뒤 새로 — 남으면 PGRST203) · 그대로인 서명은 v1 과 글자까지 같다 · DEFAULT 수 · 정의는 하나씩
//   ② status 어휘: SPEC §3.5 의 18 글자 = `AlkkagiRPCStatus`(unknown 빼고) — 앱이 서버가 안 내는 값을 품거나(muted) 서버 값을 모르면 빨강
//   ③ `realtime.send(…, '<이벤트>', …)` 글자(v1 `alk_notify` — 초안은 다시 짓지 않는다) = `RealtimeLinkConstants.alkkagiBroadcastEvent`
//   ④ 원장 reason 셋(`spend:alkkagi:stake:` · `prize:alkkagi:` · `grant:alkkagi:refund:`) — 원장 접두 CHECK 안이고 그 밖 알까기 글자 0
//   ⑤ 일일 줄 = `DailyMissionStatus.key(game: "alkkagi")` · cron 단계 행은 v1 의 36 · 5000 그대로(새 cron 0) · 문 2147483647 '임시'
//   ⑥ 조각 치환을 **체인 최신 정의에 실제로 적용**해 결과로 잰다(뒤집기 꼴). 알까기 앵커 일부(`v_cdmatch record;` · `daily_crossy_duel`
//      줄 · `v_cd` 갈래)는 앞선 게임(마작 · 길건너)이 **조각 치환으로** 넣은 글자라 체인의 마지막 `create or replace` 본문에는 없다 —
//      그래서 체인 파일의 조각 행(5칸 · 마작 6칸 두 꼴)을 이름 순서대로 다시 적용한 뒤(표지가 이미 있으면 건너뜀 — 운영 가드 ①과 같은
//      멱등) 그 위에 알까기 조각을 얹는다.
//
// 초안 위치: `ALKKAGI_MIGRATION_SQL=<파일>` → 없으면 조상의 `supabase/migrations/20261111150000_alkkagi_v2.sql`.
// `ALKKAGI_REQUIRE_MIGRATION=1` 이면 없을 때 건너뛰지 않고 빨갛다(SPEC §1 계약 시험 변수). 체인은 다른 마이그레이션 시험과 같은 길
// (`CHECK_MIGRATIONS_DIR` → 조상의 `supabase/migrations`) — 이 초안 **앞** 이름의 파일만 본다.

private let amcDraftName = "20261111150000_alkkagi_v2.sql"
private let amcV1Name = "20261110130000_alkkagi.sql"

private struct AMCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func amcDraftURL() -> URL? {
    if let path = ProcessInfo.processInfo.environment["ALKKAGI_MIGRATION_SQL"], !path.isEmpty {
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    guard let directory = try? amcChainDirectory() else { return nil }
    let candidate = directory.appendingPathComponent(amcDraftName)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
}

private let amcRequired = ProcessInfo.processInfo.environment["ALKKAGI_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 초안이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let amcGate = amcDraftURL() != nil || amcRequired

private func amcRaw() throws -> String {
    guard let url = amcDraftURL() else {
        throw AMCError("""
            1:1 알까기 v2 초안이 없다(ALKKAGI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["ALKKAGI_MIGRATION_SQL"] ?? "(없음)")) \
            — ALKKAGI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// `--` 줄 주석을 걷는다(하우스 규칙). 조각 · 앵커는 함수 본문 글자 그대로라 ⑥ 은 원문으로 본다.
private func amcStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func amcSquash(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func amcChainDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AMCError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory.deleteLastPathComponent()
    }
    throw AMCError("체인(supabase/migrations)을 못 찾았다 — 워크트리라면 supabase 심링크나 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

/// 체인에서 이 초안 **앞** 파일들(이름 순, 원문).
private func amcChainFiles() throws -> [(name: String, text: String)] {
    let directory = try amcChainDirectory()
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".sql") && $0 < amcDraftName }
        .sorted()
    guard !names.isEmpty else { throw AMCError("체인(\(directory.path))이 비었다") }
    return try names.map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
}

private func amcV1() throws -> String {
    guard let v1 = try amcChainFiles().first(where: { $0.name == amcV1Name }) else {
        throw AMCError("v1 정본 \(amcV1Name) 이 체인에 없다(워크트리면 supabase 심링크)")
    }
    return v1.text
}

private func amcMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

private func amcCount(_ needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return text.components(separatedBy: needle).count - 1
}

// MARK: - 서명

private struct AMCArgument: Equatable, CustomStringConvertible {
    let name: String
    let type: String
    let defaultValue: String?
    var description: String { "\(name) \(type)\(defaultValue.map { " default \($0)" } ?? "")" }
}

/// `create or replace function public.<name>(…)` 의 인자 목록(주석 걷은 글자). 정의마다 하나씩.
private func amcDefinitions(_ function: String, in sql: String) throws -> [[AMCArgument]] {
    let pattern = #"create\s+or\s+replace\s+function\s+public\.\#(function)\s*\(([^)]*)\)"#
    return try amcMatches(pattern, in: sql, options: [.caseInsensitive]).map { match in
        match[1].split(separator: ",").compactMap { piece -> AMCArgument? in
            let words = piece.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
            guard let name = words.first, name.hasPrefix("p_"), words.count >= 2 else { return nil }
            let type = words[1] == "int" ? "integer" : words[1]
            let defaultValue = words.firstIndex(of: "default").flatMap { $0 + 1 < words.count ? words[$0 + 1] : nil }
            return AMCArgument(name: name, type: type, defaultValue: defaultValue)
        }
    }
}

// MARK: - 조각 치환 읽기 · 재생

private struct AMCSplice: Equatable {
    let function: String      // 'public.match_watch_ping(text,uuid)'
    let primaryAnchor: String // 마작 6칸 꼴의 첫 앵커('' = 없음) — 1회면 이것, 아니면 `anchor`
    let anchor: String
    let fragment: String
    let after: Bool
    let marker: String
    var bareName: String { String(function.dropFirst("public.".count).prefix { $0 != "(" }) }
}

/// 원문에서 조각 행을 읽는다 — 5칸 `[함수, 앵커, 조각, 자리, 표지]`(뒤집기 · 길건너 · 알까기) · 6칸 `[함수, 첫 앵커, 앵커, 조각, 자리, 표지]`(마작).
/// `range` 를 주면 그 안만. 결과는 원문 안 위치(offset) 순.
private func amcSplices(in text: String, block tag: String? = nil) throws -> [(offset: Int, splice: AMCSplice)] {
    var scope = text[...]
    if let tag {
        guard let open = text.range(of: "do $\(tag)$"),
              let close = text.range(of: "$\(tag)$", range: open.upperBound..<text.endIndex) else {
            throw AMCError("do $\(tag)$ 블록이 없다 — 조각 치환 절이 사라졌거나 이름이 바뀌었다")
        }
        scope = text[open.upperBound..<close.lowerBound]
    }
    let body = String(scope)
    // 조각 글자 안에 `$frag$` 가 없다 — 게으른 `.*?` 로 두면 6칸 꼴이 이웃한 5칸 행 둘을 가로질러 맞는다.
    let frag = #"\$frag\$((?:(?!\$frag\$).)*)\$frag\$"#
    let five = #"array\[\s*'(public\.[a-z0-9_]+\([^']*\))'\s*,\s*"# + frag + #"\s*,\s*"# + frag + #"\s*,\s*'(after|before)'\s*,\s*"# + frag + #"\s*\]"#
    let six = #"array\[\s*'(public\.[a-z0-9_]+\([^']*\))'\s*,\s*"# + frag + #"\s*,\s*"# + frag + #"\s*,\s*"# + frag
        + #"\s*,\s*'(after|before)'\s*,\s*"# + frag + #"\s*\]"#
    func scan(_ pattern: String, _ make: ([String]) -> AMCSplice) throws -> [(Int, AMCSplice)] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { match in
            let groups = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: body).map { String(body[$0]) } ?? "" }
            return (match.range.location, make(groups))
        }
    }
    let fives = try scan(five) { AMCSplice(function: $0[1], primaryAnchor: "", anchor: $0[2], fragment: $0[3], after: $0[4] == "after", marker: $0[5]) }
    let sixes = try scan(six) { AMCSplice(function: $0[1], primaryAnchor: $0[2], anchor: $0[3], fragment: $0[4], after: $0[5] == "after", marker: $0[6]) }
    // 6칸 행은 5칸 꼴로도 잘못 읽힐 수 없다('after|before' 자리가 다르다) — 같은 자리에 둘이 서면 6칸이 맞다.
    let sixOffsets = Set(sixes.map(\.0))
    return (sixes + fives.filter { !sixOffsets.contains($0.0) }).sorted { $0.0 < $1.0 }.map { (offset: $0.0, splice: $0.1) }
}

/// 조각 하나를 본문에 적용한다(운영 가드 그대로 — 표지가 이미 있으면 건너뜀 · 앵커가 1회가 아니면 실패).
private func amcApply(_ splice: AMCSplice, to body: inout String) -> Bool {
    if amcCount(splice.marker, in: body) > 0 { return true }
    var anchor = splice.anchor
    if !splice.primaryAnchor.isEmpty, amcCount(splice.primaryAnchor, in: body) == 1 { anchor = splice.primaryAnchor }
    guard amcCount(anchor, in: body) == 1, let range = body.range(of: anchor) else { return false }
    body.replaceSubrange(range, with: splice.after ? anchor + splice.fragment : splice.fragment + anchor)
    return true
}

/// 체인을 이름 순서로 재생한 **지금 운영 정의**의 본문: 마지막 `create or replace` 본문(`as $tag$` ~ 닫는 `$tag$`) 위에 그 뒤 파일들의
/// 조각 행을 차례로 얹는다. 실패한 조각(앵커 0·2회)은 목록으로 돌려준다(시험이 0 을 요구한다).
private func amcReplayChain(_ function: String) throws -> (body: String, base: String, replayed: [String], failed: [String]) {
    let header = "create or replace function public.\(function)("
    var body: String?
    var base = ""
    var replayed: [String] = []
    var failed: [String] = []
    for (name, raw) in try amcChainFiles() {
        var events: [(offset: Int, kind: Int, payload: Any)] = []
        var search = raw.startIndex..<raw.endIndex
        while let hit = raw.range(of: header, options: [.caseInsensitive], range: search) {
            let rest = raw[hit.upperBound...]
            if let tagMatch = rest.range(of: #"\$[A-Za-z_]*\$"#, options: .regularExpression),
               let closing = rest.range(of: String(rest[tagMatch]), range: tagMatch.upperBound..<rest.endIndex) {
                events.append((NSRange(hit, in: raw).location, 0, String(rest[tagMatch.upperBound..<closing.lowerBound])))
            }
            search = hit.upperBound..<raw.endIndex
        }
        for (offset, splice) in try amcSplices(in: raw) where splice.bareName == function {
            events.append((offset, 1, splice))
        }
        for event in events.sorted(by: { $0.offset < $1.offset }) {
            if event.kind == 0, let text = event.payload as? String {
                body = text
                base = name
                replayed = []
            } else if let splice = event.payload as? AMCSplice, var current = body {
                if amcApply(splice, to: &current) {
                    if current != body { replayed.append("\(name):\(splice.marker.prefix(30))") }
                    body = current
                } else {
                    failed.append("\(name): \(splice.marker.prefix(40))")
                }
            }
        }
    }
    guard let body else { throw AMCError("체인에 \(function) 정의가 없다 — 앵커를 잴 출발점이 없다") }
    return (body, base, replayed, failed)
}

/// 일일 미션 정의 줄 `('daily_x', 'game', '제목', '설명', 보상, 목표, 순서)`.
private func amcDailyRows(_ text: String) throws -> [[String]] {
    try amcMatches(#"\(\s*'(daily_[a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)"#,
                   in: text).map { Array($0.dropFirst()) }
}

// MARK: - 시험

@Suite("1:1 알까기 v2 마이그레이션 계약 — 서버 초안 글자 = 앱 글자")
struct V03xxAlkkagiMigrationContractTests {
    /// SPEC §3.5 'status 어휘(서버가 내는 것)' 18 글자.
    private static let specStatuses: Set<String> = [
        "ok", "not_signed_in", "unsupported_client", "invalid", "blackout", "target_focused", "target_outdated", "busy",
        "target_busy", "already_pending", "insufficient", "not_found", "not_pending", "expired", "not_active", "stale",
        "forbidden", "rate_limited",
    ]

    /// 없으면: 초안을 못 찾을 때 아래 시험이 전부 조용히 건너뛰어 "초록"으로 보인다 — REQUIRE 가 켜져 있으면 여기서 빨갛다.
    @Test("초안 관문: ALKKAGI_REQUIRE_MIGRATION=1 이면 초안이 있어야 한다(건너뜀 0)", .enabled(if: amcRequired))
    func theDraftIsPresentWhenRequired() throws {
        #expect(amcDraftURL() != nil, "ALKKAGI_MIGRATION_SQL 이 가리키는 초안이 없다")
        #expect(try amcRaw().contains("alkkagi_ranking"))
    }

    /// ① 없으면: 앱이 부르는 이름이 서버에 없거나(오타 — 모든 버튼이 404), 바뀐 신청 서명의 옛 3인자 판이 남아 PostgREST 가 두 후보를
    /// 고르지 못하거나(PGRST203), 그대로여야 할 서명이 슬쩍 바뀌어 0.3.80 옛 판(state · leave)이 PGRST202 를 받아도 스텁 시험은 초록이다.
    @Test(.enabled(if: amcGate))
    func theFifteenRPCsAndTheirSignaturesMatchTheWire() throws {
        let draft = amcStrip(try amcRaw())
        let v1 = amcStrip(try amcV1())
        let grants = try #require(try amcMatches(#"do \$alk2_grants\$.*?v_rpc\s+constant\s+text\[\]\s*:=\s*array\[([^\]]*)\]"#, in: draft,
                                                 options: [.dotMatchesLineSeparators]).first?[1], "§11 실행권 표(v_rpc)를 못 찾았다")
        let rpc = try amcMatches(#"'([a-z_]+)'"#, in: grants).map { $0[1] }
        #expect(rpc.count == 15 && Set(rpc) == Set(AlkkagiOnlineWire.RPC.all),
                "실행권 표 \(rpc.count): \(Set(rpc).symmetricDifference(AlkkagiOnlineWire.RPC.all).sorted())")
        let draftOwned: Set<String> = ["alkkagi_lobby", "alkkagi_challenge", "alkkagi_ranking", "alkkagi_watch", "alkkagi_watch_live"]
        for name in AlkkagiOnlineWire.RPC.all {
            let inDraft = try amcDefinitions(name, in: draft)
            let inV1 = try amcDefinitions(name, in: v1)
            #expect(inDraft.count == (draftOwned.contains(name) ? 1 : 0), "\(name): 초안 정의 \(inDraft.count)개")
            #expect(inV1.count <= 1, "\(name): v1 정의 \(inV1.count)개")
            let effective = try #require(inDraft.first ?? inV1.first, "\(name): 정의가 체인 · 초안 어디에도 없다")
            #expect(effective.last?.name == "p_protocol" || name == "alkkagi_challenge", "\(name): p_protocol 이 맨 뒤가 아니다(D1)")
            #expect(effective.contains { $0.name == "p_protocol" && $0.type == "integer" && $0.defaultValue != nil })
            if let old = inV1.first, let new = inDraft.first, name != "alkkagi_challenge" {
                #expect(old == new, "\(name): 서명이 v1 과 달라졌다(그대로여야 한다) — v1 \(old) · 초안 \(new)")
            }
        }
        // 신청: 옛 3인자 drop → 새 4인자(p_stake default null 맨 뒤 — D1: p_protocol 다음).
        let challenge = try #require(try amcDefinitions("alkkagi_challenge", in: draft).first)
        #expect(challenge.map(\.name) == ["p_opponent", "p_action_id", "p_protocol", "p_stake"], "\(challenge)")
        #expect(challenge.last == AMCArgument(name: "p_stake", type: "integer", defaultValue: "null"))
        #expect(challenge.filter { $0.defaultValue != nil }.count == 2, "신청 DEFAULT 수")
        let squashed = amcSquash(draft).lowercased()
        let drop = try #require(squashed.range(of: "drop function if exists public.alkkagi_challenge(uuid, uuid, integer);"),
                                "옛 신청 서명 drop 이 없다 — 3인자 · 4인자 두 판이 남아 PGRST203")
        let create = try #require(squashed.range(of: "create or replace function public.alkkagi_challenge("))
        #expect(drop.upperBound <= create.lowerBound, "drop 이 새 정의 뒤에 있다")
        #expect(amcCount("drop function", in: squashed) == 1, "drop 은 신청 한 번뿐이어야 한다(§3 관례)")
        // ★ 기준선: v1 신청은 3인자다(위 단언이 갈린다).
        #expect(try amcDefinitions("alkkagi_challenge", in: v1).first?.map(\.name) == ["p_opponent", "p_action_id", "p_protocol"])
        // 내부 함수(정산 · 무효 · 떠남 · 잠금 도우미)는 실행권 표 밖이다 — 클라가 남의 판을 정산하지 못한다.
        for helper in ["alk_settle", "alk_void", "alk_abandon", "alk_try_lock_users", "alk_record", "alk_reply"] {
            #expect(!rpc.contains(helper) && squashed.contains("function public.\(helper)("), "\(helper)")
        }
    }

    /// ② 없으면: 앱 열거가 서버가 내지 않는 값(0.3.80 의 `muted`)을 품거나, 서버 어휘 하나를 몰라 `unknown` → '업데이트' 안내로 접어도
    /// 초록이다. FixtureContract ⑤ 는 '초안 글자 ⊆ 열거' 한 방향만 잰다 — 여기서 반대 방향과 SPEC 표를 잰다.
    @Test(.enabled(if: amcGate))
    func theStatusVocabularyIsTheSpecTable() throws {
        // 열거는 CaseIterable 이 아니다(코어 갈래 표면) — 원문의 case 줄에서 raw 값을 읽고, 값마다 실제 생성자로 되묻는다.
        let wire = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CheckCore/AlkkagiOnlineWire.swift")
        let source = try String(contentsOf: wire, encoding: .utf8)
        let head = try #require(source.range(of: "package enum AlkkagiRPCStatus"))
        let close = try #require(source.range(of: "package init(from decoder", range: head.upperBound..<source.endIndex))
        var app: Set<String> = []
        for line in source[head.upperBound..<close.lowerBound].split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("case ") else { continue }
            for item in text.dropFirst(5).split(separator: ",") {
                let parts = item.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                app.insert(parts.count == 2 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : parts[0])
            }
        }
        app.remove("unknown")
        #expect(app == Self.specStatuses, "앱 열거 ↔ SPEC 어휘: \(app.symmetricDifference(Self.specStatuses).sorted())")
        for word in Self.specStatuses {
            let status = AlkkagiRPCStatus(rawValue: word)
            #expect(status != nil && status != .unknown, "SPEC 어휘 '\(word)' 를 앱 열거가 모른다")
        }
        let draft = amcStrip(try amcRaw())
        var words: Set<String> = []
        for pattern in [#"alk_reply\(\s*[a-z_0-9]+\s*,\s*'([a-z_]+)'"#, #"jsonb_build_object\(\s*'status'\s*,\s*'([a-z_]+)'"#] {
            words.formUnion(try amcMatches(pattern, in: draft).map { $0[1] })
        }
        #expect(words.isSubset(of: Self.specStatuses), "초안이 SPEC 밖 글자를 낸다: \(words.subtracting(Self.specStatuses).sorted())")
        // ★ 기준선: v2 가 새로 내는 넷이 초안에 실제로 있다(위 반복이 무언가를 읽는다).
        #expect(words.isSuperset(of: ["blackout", "target_focused", "target_outdated", "insufficient"]), "\(words.sorted())")
        #expect(!app.contains("muted") && AlkkagiRPCStatus(rawValue: "muted") == nil)
    }

    /// ③ 없으면: 서버가 다른 글자로 초인종을 울려도(예: 'alkkagi_v2') 앱 링은 그것을 drain 으로 접고 스텁 시험은 초록이다.
    @Test(.enabled(if: amcGate))
    func theDoorbellEventIsTheAppConstant() throws {
        let v1 = amcStrip(try amcV1())
        let draft = amcStrip(try amcRaw())
        let pattern = #"realtime\.send\((?:[^;]*?)\)\s*,\s*'([a-z_:-]+)'"#
        let events = try amcMatches(pattern, in: v1, options: [.dotMatchesLineSeparators]).map { $0[1] }
        #expect(Set(events) == [RealtimeLinkConstants.alkkagiBroadcastEvent], "v1 초인종 글자: \(events)")
        // 초안은 초인종을 다시 짓지 않는다(v1 alk_notify 를 부른다) — 다시 지으면 같은 글자여야 한다.
        let redefined = try amcMatches(pattern, in: draft, options: [.dotMatchesLineSeparators]).map { $0[1] }
        #expect(redefined.allSatisfy { $0 == RealtimeLinkConstants.alkkagiBroadcastEvent }, "초안 초인종 글자: \(redefined)")
        #expect(amcSquash(draft).contains("perform public.alk_notify("), "초안이 초인종을 안 울린다")
        // ★ 기준선: 다른 게임 글자는 앱 상수가 아니다.
        #expect(RealtimeLinkConstants.alkkagiBroadcastEvent != RealtimeLinkConstants.crossyDuelBroadcastEvent)
    }

    /// ④ 없으면: 원장 reason 이 접두 CHECK(mission · prize · spend · shop · grant) 밖이라 수락 · 정산이 운영에서만 23514 로 멈추거나,
    /// 판 id 를 안 붙여 하루 1회 유일 인덱스에 걸려 둘째 판 정산이 실패해도 초록이다.
    @Test(.enabled(if: amcGate))
    func theLedgerReasonsAreTheThreeSpecPrefixes() throws {
        let draft = amcStrip(try amcRaw())
        let reasons = Set(try amcMatches(#"'((?:spend|prize|grant|mission|shop):alkkagi[a-z:_]*)'"#, in: draft).map { $0[1] })
        #expect(reasons == ["spend:alkkagi:stake:", "prize:alkkagi:", "grant:alkkagi:refund:"], "원장 reason: \(reasons.sorted())")
        let squashed = amcSquash(draft)
        for reason in reasons {
            #expect(squashed.contains("'\(reason)' || "), "\(reason) 뒤에 판 id 를 안 붙인다(하루 1회 유일 인덱스)")
        }
        // 접두 CHECK(20260913180000) 안이다.
        let check = try #require(try amcChainFiles().first { $0.name.hasPrefix("20260913180000") }?.text)
        for prefix in ["spend:%", "prize:%", "grant:%"] {
            #expect(check.contains("reason like '\(prefix)'"), "원장 접두 CHECK 에 \(prefix) 가 없다")
        }
        // ★ 기준선: 같은 읽기가 길건너 초안의 다른 게임 글자를 알까기로 세지 않는다.
        #expect(!reasons.contains { $0.contains("crossy") })
    }

    /// ⑤ 없으면: 서버 일일 줄 키가 앱이 묻는 키(`daily_alkkagi`)와 갈려 판 끝 꼬리가 "이미 채움"을 못 알아보거나, 초안이 단독 매분 job ·
    /// 다른 자리를 더해 매분 단계 예산이 깨지거나, 문을 연 채(값이 2147483647 이 아님) 나가 시험판이 진짜 루비 판을 열어도 초록이다.
    @Test(.enabled(if: amcGate))
    func theDailyRowCronAndDoorMatchTheSpec() throws {
        let raw = try amcRaw()
        let draft = amcStrip(raw)
        let rows = try amcDailyRows(raw).filter { $0[0] == "daily_alkkagi" }
        let row = try #require(rows.first, "초안에 daily_alkkagi 정의 줄이 없다")
        #expect(Set(rows.map { $0.dropFirst().joined(separator: "|") }).count == 1, "daily_alkkagi 줄이 서로 다르게 두 벌이다")
        #expect(row[0] == DailyMissionStatus.key(game: row[1]) && row[1] == "alkkagi", "키 \(row[0]) · game \(row[1])")
        #expect(row[2] == "1:1 알까기 한 판 하기" && row[2].contains(AlkkagiNoticeText.gameName))
        #expect(row[3] == "맥에서 할 수 있어요" && row[4] == "5" && row[5] == "1" && row[6] == "110", "\(row)")
        // cron: 새 등록 0 — v1 의 단계 행(36 · 5000)을 그대로 쓴다(몸통만 넓힘, D18 · D19).
        let squashed = amcSquash(draft)
        #expect(!squashed.contains("cron.schedule("), "초안이 cron job 을 새로 등록한다")
        #expect(!squashed.contains("insert into public.cron_minutely_steps"), "초안이 매분 단계 행을 새로 넣는다")
        let v1 = amcSquash(amcStrip(try amcV1()))
        #expect(v1.contains("insert into public.cron_minutely_steps (step, command, position, timeout_ms)")
                && v1.contains("'alkkagi-sweep', 'select public.alk_sweep()', 36, 5000"), "v1 매분 단계 행(36 · 5000)이 없다")
        #expect(squashed.contains("s.step = 'alkkagi-sweep' and s.command = 'select public.alk_sweep()' and s.position = 36"),
                "사후 단언이 자리 36 을 재지 않는다")
        // 문: 2147483647 · '임시(출시 때 정함)'.
        #expect(squashed.contains("create or replace function public.alk_min_build() returns integer language sql stable security invoker "
                                    + "set search_path = pg_catalog as $fn$ select 2147483647 $fn$;"), "문을 다시 닫지 않는다(D5)")
        #expect(raw.contains("임시(출시 때 정함)"))
        // ★ 기준선: v1 은 문 133(열기 파일)이다 — 같은 읽기가 값을 가른다.
        let open = try #require(try amcChainFiles().first { $0.name.hasPrefix("20261110130500") }?.text)
        #expect(amcSquash(open).contains("select 133"))
    }

    /// ⑥ 없으면: 조각의 앵커가 **지금 운영 정의**(앞 게임 조각까지 얹힌 것)에서 0회·2회가 되어 배포가 멈추거나(그 판단이 운영 적용 순간에야
    /// 난다), 조각이 붙긴 하는데 계정 삭제가 판돈을 정산하기 전에 auth.users 를 지우거나(cascade 로 판돈 소각), 관전 화이트리스트에
    /// 'alkkagi' 가 안 들어가거나(관전자 수 늘 0), 일일 정의표에 줄이 두 번 들어가도 초록이다. 모양이 아니라 **적용한 결과**를 잰다.
    @Test(.enabled(if: amcGate))
    func applyingTheSplicesToTheReplayedChainStandsAlkkagiUp() throws {
        let raw = try amcRaw()
        let splices = try amcSplices(in: raw, block: "alk2_splice").map(\.splice) + amcSplices(in: raw, block: "alk2_daily").map(\.splice)
        #expect(splices.count == 10, "조각 행을 \(splices.count)개 읽었다(기대 10 — 계정 삭제 4 · 관전 2 · 일일 4)")
        var results: [String: String] = [:]
        var bases: [String: String] = [:]
        for function in Set(splices.map(\.bareName)).sorted() {
            let chain = try amcReplayChain(function)
            #expect(chain.failed.isEmpty, "\(function): 체인 재생 중 앞 게임 조각이 안 붙었다 — \(chain.failed)")
            bases[function] = "\(chain.base)+\(chain.replayed.count)"
            var text = chain.body
            for splice in splices where splice.bareName == function {
                #expect(amcCount(splice.anchor, in: chain.body) == 1,
                        "\(function)(\(chain.base) + 조각 \(chain.replayed.count)): 앵커가 \(amcCount(splice.anchor, in: chain.body))회다 — 배포가 멈춘다. 앵커: \(splice.anchor.prefix(60))")
                #expect(amcCount(splice.marker, in: chain.body) == 0, "\(function): 표지가 이미 있다 — 알까기 줄이 체인에 먼저 들어왔다")
                #expect(amcApply(splice, to: &text), "\(function): 조각을 못 붙였다")
            }
            for splice in splices where splice.bareName == function {
                #expect(amcCount(splice.marker, in: text) == 1, "\(function): 적용 뒤 표지가 \(amcCount(splice.marker, in: text))회다")
                #expect(amcCount(splice.anchor, in: text) == 1, "\(function): 적용 뒤 앵커가 \(amcCount(splice.anchor, in: text))회다")
            }
            results[function] = text
        }
        print("[알까기 조각] 출발점(정의 파일 + 앞 게임 조각 수): \(bases.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")

        // 계정 삭제: 정렬 키 두 자리 · 정산(미정산 끝난 판) → 떠남(진행 판) → auth.users 삭제 순서.
        let delete = amcSquash(try #require(results["delete_my_account"]))
        let settle = try #require(delete.range(of: "perform public.alk_settle(v_alkmatch.id)"), "계정 삭제에 미정산 판 정산이 없다(VC-11)")
        let abandon = try #require(delete.range(of: "perform public.alk_abandon(v_alkmatch.id, v_uid)"), "계정 삭제에 진행 판 떠남이 없다")
        let auth = try #require(delete.range(of: "delete from auth.users"), "계정 삭제 본문에 auth.users 삭제가 없다")
        #expect(settle.upperBound < abandon.lowerBound && abandon.upperBound < auth.lowerBound,
                "정산 < 떠남 < auth.users 삭제 순서가 아니다 — cascade 가 판돈을 먼저 지운다")
        let sortKey = try #require(delete.range(of: "-- ★ alkkagi: 1:1 알까기 판 상대도 같은 정렬 잠금에"))
        let loop = try #require(delete.range(of: "foreach v_key in array v_keys loop"))
        #expect(sortKey.upperBound < loop.lowerBound, "정렬 키 조각이 잠금 고리 뒤에 있다")
        let late = try #require(delete.range(of: "and g.black_id <> g.white_id"))
        let lateTail = try #require(delete.range(of: "where not (k.uid = any (v_keys))"))
        #expect(late.upperBound < lateTail.lowerBound, "늦은 키 조각이 자리 밖이다")
        // ★ 기준선: 앞 게임(길건너)의 같은 자리도 그대로 남아 있다(조각이 남의 줄을 덮지 않는다).
        #expect(delete.contains("v_cdmatch record;") && delete.contains("v_mjmatch record;"))

        // 일일 정의표: 적용 전 줄은 그대로 · daily_alkkagi 한 줄 · 순서는 길건너(100) 뒤 110 에 겹치지 않게.
        let defsBefore = try amcDailyRows(try amcReplayChain("daily_mission_defs").body)
        let defsAfter = try amcDailyRows(try #require(results["daily_mission_defs"]))
        #expect(defsAfter.count == defsBefore.count + 1, "정의표가 \(defsBefore.count) → \(defsAfter.count)줄이다(기대 +1)")
        #expect(defsAfter.filter { $0[0] != "daily_alkkagi" } == defsBefore, "daily_alkkagi 말고 다른 줄이 바뀌었다")
        #expect(defsBefore.contains { $0[0] == "daily_crossy_duel" && $0[6] == "100" }, "기준선: 재생한 체인에 길건너 줄(100)이 있다")
        let alkRows = defsAfter.filter { $0[0] == "daily_alkkagi" }
        #expect(alkRows.count == 1 && alkRows.first?[6] == "110" && defsAfter.filter { $0[6] == "110" }.count == 1)
        #expect(defsAfter.count == 12, "서버 일일 줄이 \(defsAfter.count)개다(폰 serverRoster 12 와 같아야 한다)")

        // 일일 판정: 알까기 갈래 · void · rollback 제외.
        let eval = amcSquash(try #require(results["daily_missions__eval"]))
        #expect(eval.contains("when d.game = 'alkkagi' then v_alk"), "daily_missions__eval 에 알까기 갈래가 없다")
        #expect(eval.contains("v_alk := least(") && amcCount("g.finish_reason not in ('void', 'rollback')", in: eval) == 2)
        #expect(eval.contains("when d.game = 'crossy_duel' then v_cd"), "기준선: 길건너 갈래가 그대로다")

        // 관전: 화이트리스트에 'alkkagi' · case 에 알까기 갈래(숨김 격리 두 조건 · 끝난 뒤 꼬리 상수) · else 앞.
        let ping = try #require(results["match_watch_ping"])
        let list = try #require(try amcMatches(#"p_game\s+not\s+in\s*\(([^)]*)\)"#, in: ping).first?[1])
        let games = Set(try amcMatches(#"'([a-z_]+)'"#, in: list).map { $0[1] })
        #expect(games.isSuperset(of: ["gomoku", "chess", "tetris", "reversi", "alkkagi"]), "관전 화이트리스트: \(games.sorted())")
        let flat = amcSquash(ping)
        let branch = try #require(flat.range(of: "when 'alkkagi' then"))
        let elseBranch = try #require(flat.range(of: "else return 0; end case;"))
        try #require(branch.upperBound < elseBranch.lowerBound, "알까기 갈래가 else 뒤에 있다 — 닿지 않는다")
        let arm = String(flat[branch.upperBound..<elseBranch.lowerBound])
        for token in ["from public.alk_matches g", "public.alk_watch_tail_seconds()",
                      "public.same_visibility(uid, g.black_id)", "public.same_visibility(uid, g.white_id)"] {
            #expect(arm.contains(token), "알까기 관전 갈래에 '\(token)' 가 없다")
        }
        // 그 화이트리스트를 알까기가 실제로 부른다.
        #expect(amcSquash(amcStrip(raw)).contains("public.match_watch_ping('alkkagi', "), "alkkagi_watch_live 가 match_watch_ping('alkkagi', …) 를 안 부른다")
        // game__busy_users 는 손대지 않는다 — v1 이 (단일 앵커 꼴 조각으로) 넣은 줄을 쓰고, 초안은 사전 · 사후 단언으로 있는지만 본다(§3.8).
        let v1 = amcSquash(try amcV1())
        #expect(v1.contains("v_fn constant text := 'public.game__busy_users()';")
                && v1.contains("v_mark constant text := $frag$union select m.user_id from public.alk_match_members m where m.is_active$frag$;"),
                "v1 이 game__busy_users 에 알까기 줄을 넣지 않는다 — 알까기 판 중인 사람이 다른 게임을 수락한다")
        #expect(!splices.contains { $0.bareName == "game__busy_users" }, "초안이 game__busy_users 를 고친다(손대지 않기로 했다)")
        #expect(amcCount("position('alk_match_members' in pg_get_functiondef('public.game__busy_users()'::regprocedure)) = 0",
                         in: amcSquash(amcStrip(raw))) == 2, "초안 사전 · 사후 단언이 v1 대국 중 줄을 재지 않는다")
    }
}
