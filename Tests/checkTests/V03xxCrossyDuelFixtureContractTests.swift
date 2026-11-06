import Foundation
import Testing
@testable import CheckCore

// 1:1 길건너 와이어 ↔ 서버 초안 계약(SPEC v1.3 §6.3~6.5 · §8.2 · §10.2 C 줄 FixtureContract). **모양을 서버 원문에서 읽는다.**
//
//   ① 매니페스트(T/Fixtures/crossy-duel-rpc/_manifest.json — S 가 하네스에서 뜬 실응답 원문)의 케이스 파일이 다 있고, rpc 는
//      `CrossyDuelWire.RPC.all` 안이며, 모든 status 가 열거 안이다(`.unknown` 0).
//   ② 봉투 키 = 초안의 `v_*_keys` 배열 상수(C 의 계약 시험이 읽는 줄 — 초안 §12). 통합(T)이 S2 가 다시 뜬 픽스처(frames ·
//      checkpoint_ms 포함)로 바꿔 끼웠으므로 1차 차이를 더는 허락하지 않는다 — state 키 집합은 초안과 **같아야** 한다.
//   ③ 디코더 칸 = 초안 키(디코더가 키 하나를 모르면 그 값이 조용히 nil — 머리말 ①).
//   ④ 요청 본문 키 = SQL 인자 이름(PostgREST 는 본문 키 집합으로 함수를 고른다 — 이름 하나 어긋나면 PGRST202).
//   ⑤ 초안이 내는 status 글자 ⊆ `CrossyDuelRPCStatus`.
//
// 초안 위치: `CROSSY_DUEL_MIGRATION_SQL=<파일>` → 없으면 조상의 `supabase/migrations/20261109150000_crossy_duel.sql`.
// `CROSSY_DUEL_REQUIRE_MIGRATION=1` 이면 없을 때 건너뛰지 않고 빨갛다(SPEC §1 계약 시험 변수). `CHECK_MIGRATIONS_DIR` 는 보지 않는다.

private let cfcMigrationName = "20261109150000_crossy_duel.sql"

private struct CFCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func cfcMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["CROSSY_DUEL_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(cfcMigrationName)")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private let cfcMigrationRequired = ProcessInfo.processInfo.environment["CROSSY_DUEL_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let cfcMigrationGate = cfcMigrationURL() != nil || cfcMigrationRequired

private func cfcSQL() throws -> String {
    guard let url = cfcMigrationURL() else {
        throw CFCError("""
            길건너 1:1 초안이 없다(CROSSY_DUEL_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["CROSSY_DUEL_MIGRATION_SQL"] ?? "(없음)")) \
            — CROSSY_DUEL_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    let raw = try String(contentsOf: url, encoding: .utf8)
    // `--` 줄 주석을 걷는다(키 배열 줄의 꼬리 주석이 글자를 흐리지 않게 — 하우스 규칙).
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        guard let range = line.range(of: "--") else { return String(line) }
        return String(line[..<range.lowerBound])
    }.joined(separator: "\n")
}

/// 초안의 `v_<name>_keys constant text[] := array[...]` 한 벌.
private func cfcKeys(_ name: String, in sql: String) throws -> Set<String> {
    let pattern = "v_\(name)_keys\\s+constant\\s+text\\[\\]\\s*:=\\s*array\\[([^\\]]*)\\]"
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    guard let match = regex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)),
          let body = Range(match.range(at: 1), in: sql) else { throw CFCError("v_\(name)_keys 를 못 찾았다") }
    let items = sql[body].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n'")) }
    return Set(items.filter { !$0.isEmpty })
}

/// 초안의 `create or replace function public.<name>(` 인자 이름(p_*) — 정의가 여럿이면 빨강(오버로드 0).
private func cfcArguments(_ function: String, in sql: String) throws -> Set<String> {
    let pattern = "create\\s+or\\s+replace\\s+function\\s+public\\.\(function)\\s*\\(([^)]*)\\)"
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    let matches = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql))
    guard matches.count == 1, let body = Range(matches[0].range(at: 1), in: sql) else {
        throw CFCError("\(function) 정의가 \(matches.count)개다(하나여야 한다)")
    }
    let names = try NSRegularExpression(pattern: "\\b(p_[a-z_]+)\\s", options: [])
    let text = String(sql[body]) + " "
    return Set(names.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
    })
}

private let cfcFixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/crossy-duel-rpc", isDirectory: true)

private func cfcObject(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: cfcFixtureDirectory.appendingPathComponent(name))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CFCError("\(name) 가 객체가 아니다") }
    return object
}

private func cfcFixtureFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: cfcFixtureDirectory.path)
        .filter { $0.hasPrefix("crossy_duel_") && $0.hasSuffix(".json") }.sorted()
}

/// 디코더 칸 이름(Mirror 라벨) → snake_case.
private func cfcFields(_ value: Any) -> Set<String> {
    Set(Mirror(reflecting: value).children.compactMap(\.label).map { label in
        label.reduce(into: "") { out, ch in
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
    })
}

/// 요청 값 → 서비스와 같은 인코더로 본 키 집합.
private func cfcBodyKeys(_ body: some Encodable) throws -> Set<String> {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any] ?? [:]
    return Set(object.keys)
}

private func cfcDecode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(contentsOf: cfcFixtureDirectory.appendingPathComponent(name)))
}

/// S2 가 1차 초안 위에 덧붙인 state 키(B5). 1차 픽스처에는 없을 수 있다 — 그 차이만 허락한다.
private let cfcFramesKeys: Set<String> = ["frames", "checkpoint_ms"]

@Suite("V03xx 길건너 1:1 — 와이어 ↔ 초안 · 픽스처 계약")
struct V03xxCrossyDuelFixtureContractTests {

    @Test("초안 관문: CROSSY_DUEL_REQUIRE_MIGRATION=1 이면 초안이 있어야 한다(건너뜀 0 — 없으면 빨강)")
    func migrationGateIsHonoured() throws {
        // 없으면: 통합 검증에서 초안 경로를 잘못 넣어도 아래 계약 시험이 조용히 건너뛰어 '초록'으로 보인다.
        if cfcMigrationRequired { #expect(cfcMigrationURL() != nil) }
        #expect(try cfcFixtureFiles().count >= 51)
    }

    @Test("매니페스트: 케이스 파일이 다 있다 · rpc 는 RPC.all 안 · status 는 열거 안(unknown 0) · 판 status 는 서버 어휘")
    func manifestCasesDecode() throws {
        // 없으면: 서버가 새 status 를 내는 날 클라가 `.unknown` 으로 접어 문구가 '잠시 후 다시'로 뭉개진다.
        let manifest = try cfcObject("_manifest.json")
        let cases = try #require(manifest["cases"] as? [[String: Any]])
        #expect(cases.count >= 51)
        let files = Set(try cfcFixtureFiles())
        let rpcs = Set(CrossyDuelWire.RPC.all)
        let matchStatuses: Set<String> = ["pending", "active", "finished", "declined", "cancelled", "expired"]
        for entry in cases {
            let file = try #require(entry["file"] as? String)
            #expect(files.contains(file), "\(file)")
            let rpc = try #require(entry["rpc"] as? String)
            #expect(rpcs.contains(rpc), "\(file)")
            let status: CrossyDuelRPCStatus
            switch rpc {
            case CrossyDuelWire.RPC.lobby: status = try cfcDecode(CrossyDuelLobbyResponse.self, file).status
            case CrossyDuelWire.RPC.ranking: status = try cfcDecode(CrossyDuelRankingResponse.self, file).status
            default:
                let response = try cfcDecode(CrossyDuelActionResponse.self, file)
                status = response.status
                if let state = response.state { #expect(matchStatuses.contains(state.status ?? ""), "\(file)") }
            }
            #expect(status != .unknown, "\(file)")
            #expect(status.rawValue == entry["status"] as? String, "\(file)")
        }
        // 기준선: 모르는 글자는 정말 `.unknown` 으로 접힌다(위 단언이 헛돌지 않게).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let odd = try decoder.decode(CrossyDuelActionResponse.self, from: Data(#"{"status":"brand_new"}"#.utf8))
        #expect(odd.status == .unknown)
    }

    @Test("봉투 키 = 초안 v_*_keys — state(frames·checkpoint_ms 까지 같음) · side · final · lobby · me · user · invite · ranking",
          .enabled(if: cfcMigrationGate))
    func envelopeKeysMatchDraft() throws {
        // 없으면: 서버가 키 이름을 바꾸거나(goal_at → goal_at_ms) 클라 픽스처가 다른 판의 것이어도 손 픽스처 시험은 초록이다.
        let sql = try cfcSQL()
        let stateKeys = try cfcKeys("state", in: sql)
        let sideKeys = try cfcKeys("side", in: sql)
        let finalKeys = try cfcKeys("final", in: sql)
        #expect(cfcFramesKeys.isSubset(of: stateKeys))                    // 초안은 S2 덧붙임을 담았다(B5)
        var states = 0
        var framesOn = 0
        for file in try cfcFixtureFiles() {
            let object = try cfcObject(file)
            guard let state = object["state"] as? [String: Any] else { continue }
            states += 1
            let keys = Set(state.keys)
            #expect(keys.isSubset(of: stateKeys), "\(file) 여분 \(keys.subtracting(stateKeys))")
            // S2 픽스처(초안 md5 4aa31144)는 frames · checkpoint_ms 를 늘 싣는다 — 1차 픽스처로 되돌리면 여기서 빨갛다.
            #expect(stateKeys.subtracting(keys).isEmpty, "\(file) 빠짐 \(stateKeys.subtracting(keys))")
            #expect(state["report_ms"] as? Int == 1000, "\(file) report_ms \(String(describing: state["report_ms"]))")
            #expect(state["checkpoint_ms"] as? Int == 3000, "\(file) checkpoint_ms \(String(describing: state["checkpoint_ms"]))")
            if (state["frames"] as? [String: Any])?["on"] as? Bool == true { framesOn += 1 }
            for side in ["me", "opponent"] {
                #expect(Set((state[side] as? [String: Any])?.keys ?? [:].keys) == sideKeys, "\(file) \(side)")
            }
            if let final = state["final"] as? [String: Any] { #expect(Set(final.keys) == finalKeys, "\(file)") }
            if let frames = state["frames"] as? [String: Any] { #expect(Set(frames.keys) == ["on", "topic"], "\(file)") }
        }
        #expect(states >= 25)
        // S2 보고: frames 가 켜진 장 9개(진행 중 판) — 0 이면 1차 픽스처이거나 방송 스위치가 꺼진 하네스에서 뜬 것이다.
        #expect(framesOn == 9, "frames.on 인 state 픽스처 \(framesOn)장")
        let lobby = try cfcObject("crossy_duel_lobby__ok.json")
        #expect(Set(lobby.keys) == (try cfcKeys("lobby", in: sql)))
        let me = try #require(lobby["me"] as? [String: Any])
        #expect(Set(me.keys) == (try cfcKeys("lobby_me", in: sql)))
        let users = try #require(lobby["users"] as? [[String: Any]])
        #expect(!users.isEmpty)
        for user in users { #expect(Set(user.keys) == (try cfcKeys("user", in: sql))) }
        let light = try cfcObject("crossy_duel_lobby__light.json")
        #expect(Set(light.keys) == (try cfcKeys("lobby", in: sql)))
        let lightMe = try #require(light["me"] as? [String: Any])
        #expect(Set(lightMe.keys) == (try cfcKeys("lobby_me", in: sql)))
        for invite in lightMe["incoming"] as? [[String: Any]] ?? [] {
            #expect(Set(invite.keys) == (try cfcKeys("invite", in: sql)))
            #expect(Set((invite["from"] as? [String: Any])?.keys ?? [:].keys) == (try cfcKeys("invite_peer", in: sql)))
        }
        if let out = lightMe["outgoing"] as? [String: Any] {
            #expect(Set(out.keys) == (try cfcKeys("invite_out", in: sql)))
        }
        let ranking = try cfcObject("crossy_duel_ranking__ok.json")
        #expect(Set(ranking.keys) == (try cfcKeys("ranking", in: sql)))
        #expect(Set((ranking["me"] as? [String: Any])?.keys ?? [:].keys) == (try cfcKeys("ranking_me", in: sql)))
        for row in ranking["rows"] as? [[String: Any]] ?? [] {
            #expect(Set(row.keys) == (try cfcKeys("ranking_row", in: sql)))
        }
        // 매니페스트의 키 표도 초안과 같은 판이다.
        let manifestKeys = try #require(try cfcObject("_manifest.json")["keys"] as? [String: [String]])
        #expect(Set(manifestKeys["side_keys"] ?? []) == sideKeys)
        #expect(Set(manifestKeys["state_keys"] ?? []).isSubset(of: stateKeys))
    }

    @Test("디코더 칸 = 초안 키(state · side · final · lobby · me · user · invite · ranking) — 칸 하나가 모자라면 그 값은 조용히 nil",
          .enabled(if: cfcMigrationGate))
    func decoderFieldsMatchDraft() throws {
        // 없으면: 서버가 키를 더했는데 디코더에 칸이 없으면(예: checkpoint_ms) 클라가 영영 기본값으로 돈다.
        let sql = try cfcSQL()
        #expect(cfcFields(CrossyDuelStatePayload()) == (try cfcKeys("state", in: sql)))
        #expect(cfcFields(CrossyDuelSideRow()) == (try cfcKeys("side", in: sql)))
        #expect(cfcFields(CrossyDuelFinalRow()) == (try cfcKeys("final", in: sql)))
        #expect(cfcFields(CrossyDuelLobbyResponse(status: .ok)) == (try cfcKeys("lobby", in: sql)))
        #expect(cfcFields(CrossyDuelLobbyMe()) == (try cfcKeys("lobby_me", in: sql)))
        #expect(cfcFields(CrossyDuelUserRow()) == (try cfcKeys("user", in: sql)))
        #expect(cfcFields(CrossyDuelInviteRow())
                == (try cfcKeys("invite", in: sql)).union(try cfcKeys("invite_out", in: sql)))
        #expect((try cfcKeys("invite_peer", in: sql)).isSubset(of: cfcFields(CrossyDuelPeerRow())))
        #expect(cfcFields(CrossyDuelRankingResponse(status: .ok)) == (try cfcKeys("ranking", in: sql)))
        #expect(cfcFields(CrossyDuelRankingMe()) == (try cfcKeys("ranking_me", in: sql)))
        #expect(cfcFields(CrossyDuelRankRow()) == (try cfcKeys("ranking_row", in: sql)))
        // 기준선: 칸을 하나 뺀 집합이면 갈린다(snake_case 변환이 헛돌지 않게).
        #expect(cfcFields(CrossyDuelSideRow()).subtracting(["goal_at_ms"]) != (try cfcKeys("side", in: sql)))
    }

    @Test("요청 본문 키 = 초안 함수 인자 이름 · 인자 전부 DEFAULT · 오버로드 0 · p_protocol 은 언제나", .enabled(if: cfcMigrationGate))
    func requestBodiesMatchArguments() throws {
        // 없으면: 본문 키 하나(`p_match` 대 `p_match_id`)가 어긋나면 PostgREST 가 함수를 못 골라 PGRST202 — '곧 열려요'로 영영 막힌다.
        let sql = try cfcSQL()
        let report = CrossyDuelReportRequest(matchID: "m", report: CrossyDuelReportBody(seq: 1, score: 0, deaths: 0))
        let pairs: [(String, Set<String>)] = [
            (CrossyDuelWire.RPC.lobby, try cfcBodyKeys(CrossyDuelLobbyRequest(pUsers: false))),
            (CrossyDuelWire.RPC.challenge, try cfcBodyKeys(CrossyDuelChallengeRequest(pOpponent: "o", pStake: 3))),
            (CrossyDuelWire.RPC.cancel, try cfcBodyKeys(CrossyDuelMatchRequest(pMatchId: "m"))),
            (CrossyDuelWire.RPC.respond, try cfcBodyKeys(CrossyDuelRespondRequest(pMatchId: "m", pAccept: true))),
            (CrossyDuelWire.RPC.report, try cfcBodyKeys(report)),
            (CrossyDuelWire.RPC.state, try cfcBodyKeys(CrossyDuelMatchRequest(pMatchId: "m"))),
            (CrossyDuelWire.RPC.resign, try cfcBodyKeys(CrossyDuelMatchRequest(pMatchId: "m"))),
            (CrossyDuelWire.RPC.ranking, try cfcBodyKeys(CrossyDuelProtocolRequest())),
        ]
        #expect(Set(pairs.map(\.0)) == Set(CrossyDuelWire.RPC.all))
        for (rpc, keys) in pairs {
            #expect(keys == (try cfcArguments(rpc, in: sql)), "\(rpc)")
            #expect(keys.contains("p_protocol"), "\(rpc)")
        }
        // 인자 전부 DEFAULT(인자 없는 호출도 함수를 고른다 — 프로토콜 판정이 먼저 돈다).
        for rpc in CrossyDuelWire.RPC.all {
            let pattern = "create\\s+or\\s+replace\\s+function\\s+public\\.\(rpc)\\s*\\(([^)]*)\\)"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let match = try #require(regex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)))
            let body = String(sql[try #require(Range(match.range(at: 1), in: sql))])
            for argument in body.split(separator: ",") {
                #expect(argument.lowercased().contains("default"), "\(rpc): \(argument)")
            }
        }
        #expect(CrossyDuelWire.protocolVersion == 1)
        #expect(sql.contains("crossy_duel_protocol()"))
    }

    @Test("초안이 내는 status 글자 ⊆ CrossyDuelRPCStatus(unknown 아님) · 픽스처가 본 status 는 전부 그 안", .enabled(if: cfcMigrationGate))
    func draftStatusVocabularyIsKnown() throws {
        // 없으면: 서버가 새 status(예: 'busy_other')를 내기 시작해도 클라는 `.unknown` 으로 접어 아무 안내 없이 버린다.
        let sql = try cfcSQL()
        let regex = try NSRegularExpression(pattern: "'status',\\s*'([a-z_]+)'", options: [])
        // 키 배열(`array['status', 'server_now_ms', …]`)의 이웃 글자는 status 값이 아니다 — 초안 키 이름을 걷는다.
        var keyNames: Set<String> = []
        for name in ["state", "side", "final", "lobby", "lobby_me", "user", "invite", "invite_out", "invite_peer",
                     "ranking", "ranking_me", "ranking_row"] {
            keyNames.formUnion(try cfcKeys(name, in: sql))
        }
        let words = Set(regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)).compactMap {
            Range($0.range(at: 1), in: sql).map { String(sql[$0]) }
        }).subtracting(keyNames)
        #expect(words.count >= 10)
        for word in words {
            #expect(CrossyDuelRPCStatus(rawValue: word) != nil, "\(word)")
        }
        let seen = try #require(try cfcObject("_manifest.json")["statuses_seen"] as? [String])
        for word in seen { #expect(CrossyDuelRPCStatus(rawValue: word) != nil, "\(word)") }
    }
}
