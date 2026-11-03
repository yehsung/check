import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기(reversi) — **마이그레이션 ↔ 앱 글자 대조**(SPEC §6.3 T `V03xxReversiMigrationContractTests`, v1.1 CCT I13).
// 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다(SPEC §1).
//
// 스텁 서버 시험은 서버가 **무엇을 부르고 무엇을 내는지**를 앱이 적은 대로 가정한다 — 이름 한 글자가 갈려도 전부 초록이다
// (메모리 stub-tests-hide-roundtrip-bugs). 그래서 마이그레이션 **원문**과 앱 상수를 맞댄다:
//   ① 클라 RPC 집합 = `ReversiWire.RPC.all`(정의 · 실행권 둘 다), 내부 `reversi__` 는 클라가 못 부른다
//   ② RPC 인자 이름 · 형 · DEFAULT · 정의 1개(오버로드 0 — PGRST203)
//   ③ `reversi_protocol()` = `ReversiWire.protocolVersion` · 서버가 내는 status 어휘 = 설계서 §3.4 = 앱 `ReversiRPCStatus`
//   ④ `gomoku_` 머리 함수 정의 0(V0341) · `reversi_stakes` 머리 함수 하나(V0351) · 남의 busy 함수 직접 재정의 0(DEC:22)
//   ⑤ `daily_reversi` 정의 줄 = `DailyMissionStatus.key(game: "reversi")` · 제목 = 앱 게임 이름
//   ⑥ 조각 치환형 셋(game__busy_users · daily_mission_defs · match_watch_ping)을 **체인 최신 정의에 실제로 적용**해 결과를 잰다 —
//      관전 화이트리스트에 'reversi' · 대국 중 판정에 리버시 판 · 일일 정의표에 한 줄(모양이 아니라 결과, 메모리 tests-measure-shape-not-result)
//   ⑦ 매분 일은 `cron_minutely_steps` 한 줄로만(단독 매분 job 0 — CronMinutelyMigrationTests 는 옛 일곱만 본다)
// 실시간 이벤트 글자(`realtime.send(…, 'reversi', …)` = `RealtimeLinkConstants.reversiBroadcastEvent`)는 배선 갈래(T1) 몫이라 여기 없다.
//
// 마이그레이션 위치(SPEC §6.2 v1.1): `REVERSI_MIGRATION_SQL=<파일>` → 없으면 조상의 `supabase/migrations/20261108200000_reversi.sql`.
// `REVERSI_REQUIRE_MIGRATION=1` 이면 없을 때 건너뛰지 않고 빨갛다. ⑥ 이 읽는 **체인**(리버시 앞 파일들)은 다른 마이그레이션 시험과 같은
// 길(`CHECK_MIGRATIONS_DIR` → 조상의 `supabase/migrations`)이다 — 리버시 초안이 그 안에 있든 없든 결과가 같다(이름이 리버시 앞인 파일만 본다).
// 하우스 규칙: `--` 줄 주석을 걷고 본다(⑥ 의 조각·앵커는 함수 본문 글자 그대로라 원문으로 본다).

private let rmcMigrationName = "20261108200000_reversi.sql"

private struct RMCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - 마이그레이션 · 체인 찾기

private func rmcMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(rmcMigrationName)")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private let rmcMigrationRequired = ProcessInfo.processInfo.environment["REVERSI_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let rmcMigrationGate = rmcMigrationURL() != nil || rmcMigrationRequired

private func rmcRaw() throws -> String {
    guard let url = rmcMigrationURL() else {
        throw RMCError("""
            리버시 마이그레이션이 없다(REVERSI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"] ?? "(없음)")) — \
            REVERSI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

private func rmcStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func rmcSquash(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// 리버시 앞 체인(다른 마이그레이션 시험과 같은 길 — `CHECK_MIGRATIONS_DIR` → 조상의 `supabase/migrations`).
private func rmcChainDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RMCError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw RMCError("체인(supabase/migrations)을 못 찾았다 — 워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func rmcMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

private func rmcCount(_ needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return text.components(separatedBy: needle).count - 1
}

// MARK: - 정의 · 실행권 읽기

private struct RMCArgument: Equatable {
    let name: String
    let type: String
    let defaultValue: String?
}

/// 마이그레이션의 `create or replace function public.<이름>(<인자>)` 전부(파일 순서).
private func rmcDefinitions(_ sql: String) throws -> [(name: String, arguments: [RMCArgument])] {
    try rmcMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(([^)]*)\)"#,
                   in: sql, options: [.caseInsensitive]).map { match in
        let arguments = match[2].split(separator: ",").compactMap { part -> RMCArgument? in
            let tokens = part.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
            guard tokens.count >= 2 else { return nil }
            let type: String = {
                switch tokens[1] {
                case "int", "integer", "int4": return "int"
                case "bool", "boolean": return "boolean"
                default: return tokens[1]
                }
            }()
            let defaultValue = tokens.firstIndex(of: "default").flatMap { $0 + 1 < tokens.count ? tokens[$0 + 1] : "" }
            return RMCArgument(name: tokens[0], type: type, defaultValue: defaultValue)
        }
        return (match[1].lowercased(), arguments)
    }
}

/// `grant execute …` / `revoke all …` 줄: 함수 이름 → 받는 역할 집합들(줄마다 하나).
private func rmcPrivileges(_ sql: String, verb: String) throws -> [String: [Set<String>]] {
    let pattern = verb == "grant"
        ? #"grant\s+execute\s+on\s+function\s+public\.([a-z0-9_]+)\s*\([^)]*\)\s+to\s+([^;]+);"#
        : #"revoke\s+all\s+on\s+function\s+public\.([a-z0-9_]+)\s*\([^)]*\)\s+from\s+([^;]+);"#
    var out: [String: [Set<String>]] = [:]
    for match in try rmcMatches(pattern, in: sql, options: [.caseInsensitive]) {
        let roles = Set(match[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        out[match[1].lowercased(), default: []].append(roles)
    }
    return out
}

// MARK: - 조각 치환 읽기 · 적용

private struct RMCSplice: Equatable {
    let function: String     // 'public.match_watch_ping(text,uuid)'
    let anchor: String
    let fragment: String
    let after: Bool
    let marker: String
    /// `public.match_watch_ping(text,uuid)` → `match_watch_ping`
    var bareName: String {
        String(function.dropFirst("public.".count).prefix { $0 != "(" })
    }
}

/// `do $<tag>$ … $<tag>$` 블록 안 `v_spec` 의 조각 행(원문 — 앵커·조각은 함수 본문 글자 그대로다).
private func rmcSplices(_ raw: String, block tag: String) throws -> [RMCSplice] {
    guard let open = raw.range(of: "do $\(tag)$"),
          let close = raw.range(of: "$\(tag)$", range: open.upperBound..<raw.endIndex) else {
        throw RMCError("do $\(tag)$ 블록이 없다 — 조각 치환 절이 사라졌거나 이름이 바뀌었다")
    }
    let block = String(raw[open.upperBound..<close.lowerBound])
    let pattern = #"array\[\s*'([^']+)'\s*,\s*\$frag\$(.*?)\$frag\$\s*,\s*\$frag\$(.*?)\$frag\$\s*,\s*'(after|before)'\s*,\s*\$frag\$(.*?)\$frag\$\s*\]"#
    return try rmcMatches(pattern, in: block, options: [.dotMatchesLineSeparators]).map {
        RMCSplice(function: $0[1], anchor: $0[2], fragment: $0[3], after: $0[4] == "after", marker: $0[5])
    }
}

/// 체인에서 리버시 **앞** 파일 가운데 그 함수를 마지막으로 정의한 파일과 그 본문(`as $tag$` ~ 닫는 `$tag$`, 원문).
private func rmcChainBody(_ function: String) throws -> (file: String, body: String) {
    let directory = try rmcChainDirectory()
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".sql") && $0 < rmcMigrationName }
        .sorted()
    let header = "create or replace function public.\(function)("
    for name in names.reversed() {
        let raw = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        guard let hit = raw.range(of: header, options: [.caseInsensitive, .backwards]) else { continue }
        let rest = raw[hit.upperBound...]
        guard let tagMatch = rest.range(of: #"\$[A-Za-z_]*\$"#, options: .regularExpression) else {
            throw RMCError("\(name): \(function) 본문의 여는 달러 태그가 없다")
        }
        let tag = String(rest[tagMatch])
        guard let closing = rest.range(of: tag, range: tagMatch.upperBound..<rest.endIndex) else {
            throw RMCError("\(name): \(function) 본문의 닫는 \(tag) 가 없다")
        }
        return (name, String(rest[tagMatch.upperBound..<closing.lowerBound]))
    }
    throw RMCError("체인(\(directory.path))에 \(function) 정의가 없다 — 앵커를 잴 출발점이 없다")
}

/// 일일 미션 정의 줄 `('daily_x', 'game', '제목', '설명', 보상, 목표, 순서)`.
private func rmcDailyRows(_ text: String) throws -> [[String]] {
    try rmcMatches(#"\(\s*'(daily_[a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)"#,
                   in: text).map { Array($0.dropFirst()) }
}

// MARK: - 시험

@Suite("아잉 뒤집기 마이그레이션 계약 — 서버 글자 = 앱 글자")
struct V03xxReversiMigrationContractTests {

    /// 설계서 §3.4 의 인자(이름 · 형 · DEFAULT). `p_protocol int default 0` 이 늘 먼저다.
    private static let expectedArguments: [ReversiWire.RPC: [RMCArgument]] = {
        let proto = RMCArgument(name: "p_protocol", type: "int", defaultValue: "0")
        let match = RMCArgument(name: "p_match_id", type: "uuid", defaultValue: "null")
        let since = RMCArgument(name: "p_since_seq", type: "int", defaultValue: "0")
        return [
            .lobby: [proto],
            .challenge: [proto, RMCArgument(name: "p_opponent", type: "uuid", defaultValue: "null"),
                         RMCArgument(name: "p_stake", type: "int", defaultValue: "null")],
            .cancel: [proto, match],
            .respond: [proto, match, RMCArgument(name: "p_accept", type: "boolean", defaultValue: "null")],
            .state: [proto, match, since],
            .move: [proto, match, RMCArgument(name: "p_expected_seq", type: "int", defaultValue: "null"),
                    RMCArgument(name: "p_idx", type: "int", defaultValue: "null")],
            .resign: [proto, match],
            .ranking: [proto],
            .watch: [proto, match, since],
            .watchLive: [proto, match, since],
        ]
    }()

    /// 설계서 §3.4 status 어휘 전체(클라 `ReversiRPCStatus` 와 같은 집합 — `unknown` 은 앱이 모르는 값을 접는 칸이라 빠진다).
    private static let specStatuses: Set<String> = [
        "ok", "unauthorized", "unsupported_client", "invalid", "blackout", "target_focused", "target_outdated", "busy",
        "target_busy", "already_pending", "insufficient", "not_found", "not_pending", "expired", "not_active",
        "not_your_turn", "stale", "illegal", "auto_placed",
    ]

    // ① 없으면: 앱이 부르는 이름이 서버에 없거나(오타 — 모든 버튼이 404), 서버가 `reversi_` 클라 함수를 하나 더 열어 두거나,
    //    내부 `reversi__` 함수(정산·자동 착수)에 authenticated 실행권이 남아 클라가 남의 판을 정산해도 스텁 시험은 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    func 클라_RPC_집합이_와이어와_같고_내부_함수는_클라가_못_부른다() throws {
        let sql = rmcStrip(try rmcRaw())
        let definitions = try rmcDefinitions(sql)
        let grants = try rmcPrivileges(sql, verb: "grant")
        let revokes = try rmcPrivileges(sql, verb: "revoke")
        let wire = Set(ReversiWire.RPC.all)
        #expect(wire.count == 10, "와이어 RPC 가 \(wire.count)개다(설계서 §3.4 는 열)")

        // 정의 쪽: p_protocol 을 먼저 받는 `reversi_` 함수 = 클라 RPC.
        let protocolFirst = Set(definitions.filter {
            $0.name.hasPrefix("reversi_") && !$0.name.hasPrefix("reversi__") && $0.arguments.first?.name == "p_protocol"
        }.map(\.name))
        #expect(protocolFirst == wire, """
            p_protocol 을 먼저 받는 서버 함수 \(protocolFirst.sorted()) ≠ 앱 와이어 \(wire.sorted())
            (서버에만: \(protocolFirst.subtracting(wire).sorted()) · 앱에만: \(wire.subtracting(protocolFirst).sorted()))
            """)

        // 실행권 쪽: authenticated 에게 주고 PUBLIC 에는 안 준(= 상수·순수 판정이 아닌) `reversi` 함수 = 클라 RPC.
        let clientGranted = Set(grants.filter { name, lines in
            name.hasPrefix("reversi") && lines.contains { $0.contains("authenticated") && !$0.contains("public") }
        }.keys)
        #expect(clientGranted == wire, """
            authenticated 실행권을 받은 리버시 함수 \(clientGranted.sorted()) ≠ 앱 와이어 \(wire.sorted())
            (서버에만: \(clientGranted.subtracting(wire).sorted()) · 앱에만: \(wire.subtracting(clientGranted).sorted()))
            """)
        // 클라 RPC 는 PUBLIC 기본 실행권을 회수해야 anon 이 못 부른다(MS:252 — 매 적용마다 다시).
        for rpc in wire {
            #expect(revokes[rpc]?.contains { $0.isSuperset(of: ["public", "anon"]) } == true,
                    "\(rpc): `revoke … from public, anon` 이 없다 — anon 이 기본 실행권으로 부른다")
        }

        // 내부(두 밑줄): 클라 역할 실행권 0 + 셋 다 회수.
        let internals = Set(definitions.map(\.name).filter { $0.hasPrefix("reversi__") })
        #expect(internals.count >= 5, "내부 reversi__ 함수를 \(internals.count)개만 읽었다 — 파서가 헛돈다")
        let clientRoles: Set<String> = ["public", "anon", "authenticated"]
        for name in internals {
            let leaked = (grants[name] ?? []).flatMap { $0.intersection(clientRoles) }
            #expect(leaked.isEmpty, "\(name): 클라 역할 \(Set(leaked).sorted()) 에 실행권을 준다 — 내부 함수는 service_role 만")
            #expect(revokes[name]?.contains { $0.isSuperset(of: clientRoles) } == true,
                    "\(name): `revoke … from public, anon, authenticated` 가 없다 — PUBLIC 기본 실행권이 남는다")
        }
    }

    // ② 없으면: 인자 하나에 DEFAULT 가 빠져(옛 앱이 그 키를 안 보내면 PGRST202) 또는 형이 바뀌어(uuid → text) 또는 같은 이름을 서명만
    //    바꿔 두 번 정의해(PGRST203 — 모든 호출이 모호) 운영에서 그 버튼만 죽어도, 요청 본문을 적은 대로 믿는 스텁 시험은 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    func RPC_인자_이름_형_DEFAULT_가_설계서와_같고_정의는_하나씩이다() throws {
        let definitions = try rmcDefinitions(rmcStrip(try rmcRaw()))
        for rpc in ReversiWire.RPC.allCases {
            let defined = definitions.filter { $0.name == rpc.rawValue }
            #expect(defined.count == 1, "\(rpc.rawValue) 정의가 \(defined.count)개다 — 서명이 둘이면 PostgREST 가 고르지 못한다(PGRST203)")
            guard let arguments = defined.last?.arguments, let expected = Self.expectedArguments[rpc] else {
                Issue.record("\(rpc.rawValue): 마이그레이션 정의나 설계서 기대 인자가 없다")
                continue
            }
            #expect(arguments == expected, """
                \(rpc.rawValue) 인자: 서버 \(arguments.map { "\($0.name) \($0.type) default \($0.defaultValue ?? "없음")" })
                ≠ 설계서 §3.4 \(expected.map { "\($0.name) \($0.type) default \($0.defaultValue ?? "없음")" })
                """)
            #expect(arguments.allSatisfy { $0.defaultValue != nil }, "\(rpc.rawValue): DEFAULT 없는 인자가 있다")
        }
    }

    // ③ 없으면: 서버가 프로토콜을 올렸는데 앱 상수가 그대로라 모든 호출이 unsupported_client 로 접히거나, 서버가 새 status 글자를
    //    내는데 앱이 모르는 값(.unknown)으로 조용히 접어 문구 없이 버튼이 안 먹어도 스텁 시험은 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    func 프로토콜_상수와_status_어휘가_앱과_같다() throws {
        let sql = rmcStrip(try rmcRaw())
        let protocolValue = try rmcMatches(#"function\s+public\.reversi_protocol\s*\(\s*\).*?select\s+(\d+)"#, in: sql,
                                           options: [.caseInsensitive, .dotMatchesLineSeparators]).first?[1]
        #expect(protocolValue.flatMap { Int($0) } == ReversiWire.protocolVersion,
                "reversi_protocol() = \(protocolValue ?? "없음") · 앱 ReversiWire.protocolVersion = \(ReversiWire.protocolVersion)")

        let emitted = Set(try rmcMatches(#"jsonb_build_object\(\s*'status'\s*,\s*'([a-z_]+)'"#, in: sql).map { $0[1] })
        #expect(emitted == Self.specStatuses, """
            서버가 내는 status \(emitted.sorted()) ≠ 설계서 §3.4 어휘
            (서버에만: \(emitted.subtracting(Self.specStatuses).sorted()) · 설계서에만: \(Self.specStatuses.subtracting(emitted).sorted()))
            """)
        for status in emitted.union(Self.specStatuses) {
            let decoded = ReversiRPCStatus(rawValue: status)
            #expect(decoded != nil && decoded != .unknown, "서버 status '\(status)' 를 앱이 모른다 — .unknown 으로 접혀 문구 없이 막힌다")
        }
    }

    // ④ 없으면: 리버시 파일이 `gomoku_` 머리 함수를 정의해 V0341 의 오목 계약을 몰래 덮거나, `reversi_stakes…` 꼴 함수를 더해 판돈 상수
    //    파서(V0351)를 헷갈리게 하거나, 대국 중 판정을 `chess__busy` 등에 직접 OR 로 붙여(DEC:22 — 한 곳 `game__busy_users` 에만) 다음
    //    게임이 또 다른 자리를 고쳐야 하는 길을 열어도 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    func gomoku_머리_함수와_남의_busy_함수를_정의하지_않는다() throws {
        let sql = rmcStrip(try rmcRaw())
        let names = try rmcDefinitions(sql).map(\.name)
        #expect(names.count > 40, "정의를 \(names.count)개만 읽었다 — 파서가 헛돈다")
        #expect(names.filter { $0.hasPrefix("gomoku_") }.isEmpty, "gomoku_ 머리 함수를 정의한다: \(names.filter { $0.hasPrefix("gomoku_") })")
        #expect(Set(names.filter { $0.hasPrefix("reversi_stakes") }) == ["reversi_stakes"],
                "reversi_stakes 머리 함수가 하나가 아니다: \(names.filter { $0.hasPrefix("reversi_stakes") })")
        let busy = names.filter { $0.hasSuffix("__busy") || $0 == "lobby__others" }
        #expect(busy.isEmpty, "남의 busy · 로비 함수를 직접 다시 만든다: \(busy) — 대국 중 판정은 game__busy_users 한 곳에만 더한다(DEC:22)")
        // 조각 치환형 셋은 통째로 다시 만들지 않는다(§3.8 — 최신 정의에서 출발해야 마작이 먼저 더한 줄을 지우지 않는다).
        for spliced in ["game__busy_users", "daily_mission_defs", "match_watch_ping"] {
            #expect(!names.contains(spliced), "\(spliced) 를 create or replace 로 통째로 다시 만든다 — 조각 치환형이어야 한다(§3.8)")
        }
    }

    // ⑤ 없으면: 서버 정의표 키가 `daily_reversi` 가 아니거나(앱은 `DailyMissionStatus.key(game:)` 로 그 줄을 찾는다 — 판이 끝나도 일일
    //    줄이 안 채워진 것처럼 보인다) 제목이 앱 게임 이름과 갈려도(목록에 다른 이름) 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    @MainActor
    func 일일_미션_정의_줄이_앱_키와_같다() throws {
        let sql = rmcStrip(try rmcRaw())
        let rows = try rmcDailyRows(sql).filter { $0[0].hasPrefix("daily_reversi") || $0[1] == "reversi" }
        try #require(!rows.isEmpty, "마이그레이션에 daily_reversi 정의 줄이 없다")
        let distinct = Set(rows.map { $0.joined(separator: "|") })
        #expect(distinct.count == 1, "daily_reversi 줄이 자리마다 다르다(치환 조각 · 사후 단언 조각이 갈렸다): \(distinct.sorted())")
        let row = rows[0]
        #expect(row[1] == "reversi")
        #expect(row[0] == DailyMissionStatus.key(game: row[1]), "서버 키 \(row[0]) ≠ 앱 키 \(DailyMissionStatus.key(game: row[1]))")
        #expect(row[2] == "\(ReversiNoticeText.gameName) 한 판 하기", "서버 제목 '\(row[2])' 가 앱 게임 이름(\(ReversiNoticeText.gameName))과 갈렸다")
        #expect(row[3] == "맥에서 할 수 있어요", "detail 이 큐브 선례('맥에서 할 수 있어요')와 다르다 — 폰·안드·윈도우에도 이 줄이 보인다")
        #expect(row[4] == "5" && row[5] == "1" && row[6] == "80", "보상 · 목표 · 순서가 설계서 §1(5 · 1 · 80)과 다르다: \(row)")
    }

    // ⑥ 없으면: 조각의 앵커가 체인 최신 정의에서 0회·2회가 되어 배포가 멈추거나(그 판단이 운영 적용 순간에야 난다), 조각이 붙긴 하는데
    //    관전 화이트리스트에 'reversi' 가 안 들어가(관전자 수가 늘 0) 또는 대국 중 판정에 리버시 판이 안 들어가(한 사람 두 판) 또는
    //    일일 정의표에 줄이 두 번 들어가도 초록이다. 모양(조각 글자)이 아니라 **적용한 결과**를 잰다.
    @Test(.enabled(if: rmcMigrationGate))
    func 조각_치환을_체인_최신_정의에_적용하면_리버시가_선다() throws {
        let raw = try rmcRaw()
        let splices = try rmcSplices(raw, block: "rv_splice")
        #expect(splices.count == 4, "조각 행을 \(splices.count)개 읽었다(기대 4 — busy 1 · 일일 1 · 관전 2)")
        // 사후 단언 블록이 같은 조각을 잰다(갈리면 사후 단언이 다른 것을 확인하고 통과한다).
        #expect(try rmcSplices(raw, block: "rv_canon_post") == splices, "사후 단언(rv_canon_post)의 조각이 치환(rv_splice) 조각과 다르다")

        var results: [String: String] = [:]
        var sources: [String: String] = [:]
        for function in Set(splices.map(\.bareName)).sorted() {
            let (file, body) = try rmcChainBody(function)
            sources[function] = file
            var text = body
            for splice in splices where splice.bareName == function {
                #expect(rmcCount(splice.anchor, in: body) == 1,
                        "\(function)(\(file)): 앵커가 \(rmcCount(splice.anchor, in: body))회다 — 배포가 §9 에서 멈춘다. 앵커: \(splice.anchor)")
                #expect(rmcCount(splice.marker, in: body) == 0, "\(function)(\(file)): 표지가 이미 있다 — 리버시 줄이 체인에 먼저 들어왔다")
                guard let anchor = text.range(of: splice.anchor) else { continue }
                text.replaceSubrange(anchor, with: splice.after ? splice.anchor + splice.fragment : splice.fragment + splice.anchor)
            }
            for splice in splices where splice.bareName == function {
                #expect(rmcCount(splice.marker, in: text) == 1, "\(function): 적용 뒤 표지가 \(rmcCount(splice.marker, in: text))회다")
                #expect(rmcCount(splice.anchor, in: text) == 1, "\(function): 적용 뒤 앵커가 \(rmcCount(splice.anchor, in: text))회다")
            }
            results[function] = text
        }

        // 대국 중 판정: 리버시 진행 중 판의 두 사람이 game__busy_users 에 든다(한 사람 한 판 — DEC:22).
        let busy = rmcSquash(try #require(results["game__busy_users"], "game__busy_users 조각이 없다"))
        for side in ["black", "white"] {
            #expect(busy.contains("union select g.\(side) from public.reversi_matches g where g.status = 'active' and g.\(side) is not null"),
                    "game__busy_users 결과에 리버시 \(side) 가 없다 — 리버시 대국 중인 사람이 다른 게임을 수락한다")
        }

        // 일일 정의표: 적용 전 줄은 그대로 · daily_reversi 한 줄 · 순서는 큐브 뒤에 겹치지 않게.
        let defsBefore = try rmcDailyRows(try rmcChainBody("daily_mission_defs").body)
        let defsAfter = try rmcDailyRows(try #require(results["daily_mission_defs"]))
        #expect(defsAfter.count == defsBefore.count + 1, "정의표가 \(defsBefore.count) → \(defsAfter.count)줄이다(기대 +1)")
        #expect(defsAfter.filter { $0[0] != "daily_reversi" } == defsBefore, "daily_reversi 말고 다른 줄이 바뀌었다")
        let reversiRows = defsAfter.filter { $0[0] == "daily_reversi" }
        #expect(reversiRows.count == 1, "daily_reversi 가 \(reversiRows.count)줄이다")
        let rummySort = defsBefore.first { $0[0] == "daily_rummy" }.flatMap { Int($0[6]) }
        let reversiSort = reversiRows.first.flatMap { Int($0[6]) }
        let afterRummy = (reversiSort ?? Int.min) > (rummySort ?? Int.max)
        #expect(afterRummy, "daily_reversi 순서(\(reversiSort ?? -1))가 큐브(\(rummySort ?? -1)) 뒤가 아니다")
        #expect(defsAfter.filter { Int($0[6]) == reversiSort }.count == 1, "순서 값 \(reversiSort ?? -1) 이 다른 줄과 겹친다")

        // 관전: 화이트리스트 목록에 'reversi' · case 에 리버시 갈래(숨김 격리 두 조건 · 끝난 뒤 꼬리 상수).
        let ping = try #require(results["match_watch_ping"], "match_watch_ping 조각이 없다")
        let list = try #require(try rmcMatches(#"p_game\s+not\s+in\s*\(([^)]*)\)"#, in: ping).first?[1],
                                "match_watch_ping 결과에 p_game not in (…) 목록이 없다")
        let games = Set(try rmcMatches(#"'([a-z_]+)'"#, in: list).map { $0[1] })
        #expect(games.isSuperset(of: ["gomoku", "chess", "tetris", "reversi"]),
                "관전 화이트리스트가 \(games.sorted()) 다 — 'reversi' 가 없으면 리버시 관전자 수가 늘 0 이다")
        let flat = rmcSquash(ping)
        let branch = try #require(flat.range(of: "when 'reversi' then"), "match_watch_ping 결과에 when 'reversi' then 갈래가 없다")
        let elseBranch = try #require(flat.range(of: "else return 0; end case;"), "case 의 else 갈래를 못 찾았다")
        try #require(branch.upperBound < elseBranch.lowerBound, "리버시 갈래가 else 뒤에 있다 — 닿지 않는다")
        let reversiArm = String(flat[branch.upperBound..<elseBranch.lowerBound])
        for token in ["from public.reversi_matches g", "public.reversi_watch_tail_seconds()",
                      "public.same_visibility(uid, g.challenger)", "public.same_visibility(uid, g.opponent)"] {
            #expect(reversiArm.contains(token), "리버시 관전 갈래에 '\(token)' 가 없다")
        }
        // 그 화이트리스트를 리버시가 실제로 부른다.
        #expect(rmcSquash(rmcStrip(raw)).contains("public.match_watch_ping('reversi', p_match_id)"),
                "reversi_watch_live 가 match_watch_ping('reversi', …) 를 안 부른다")
        print("[리버시 조각] 출발점: \(sources.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
    }

    // ⑦ 없으면: 리버시 백스톱을 단독 매분 job(`cron.schedule(…, '* * * * *', …)`)으로 등록해 minutely 와 같은 일이 매분 두 번 돌거나
    //    (CronMinutelyMigrationTests 는 옛 일곱 이름만 본다), 등록표 줄의 명령·순서가 설계서(37)와 달라 다른 게임과 겹쳐도 초록이다.
    @Test(.enabled(if: rmcMigrationGate))
    func 매분_일은_단계_행으로만_돈다() throws {
        let flat = rmcSquash(rmcStrip(try rmcRaw()))
        #expect(flat.contains("insert into public.cron_minutely_steps (step, command, position) values ('reversi-settle', 'select public.reversi_settle_expired()', 37)"),
                "매분 등록표에 reversi-settle(37) 줄이 없다")
        #expect(!flat.contains("'* * * * *'"), "리버시 파일이 매분 단독 cron job 을 만든다 — 매분 일은 cron_minutely_steps 한 줄로만")
        #expect(flat.contains("cron.schedule('reversi-purge', '53 18 * * *', 'select public.reversi_purge()')"),
                "하루 청소 job(reversi-purge 18:53 UTC)이 설계서 §1 과 다르다")
    }
}
