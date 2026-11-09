import Foundation
import Testing
@testable import CheckCore

// 1:1 알까기 v2 와이어 ↔ 서버 초안 계약(SPEC v1.1 §3.5~3.7 · §4.1 · §7.2 C 줄 FixtureContract). **모양을 서버 원문에서 읽는다.**
//
//   ① 매니페스트(T/Fixtures/alkkagi-rpc/_manifest.json)의 케이스 파일이 다 있고 남는 파일이 없으며, rpc 는 `AlkkagiOnlineWire.RPC.all`
//      안이고 모든 status 가 열거 안이다(`.unknown` 0). 픽스처는 **S 하네스 원문**(V2/server/fixtures — gen.sh 가 체인 182 + 초안 3회
//      적용 위에서 실제 RPC 응답을 그대로 적은 68장, 통합 T 가 C 의 손 픽스처를 바꿔 끼웠다). 매니페스트의 `draft_md5` 가 초안과 같다.
//   ② 봉투 키 = 초안의 `v_*_keys` 배열 상수(초안 §13 흐름 프로브가 실제 응답과 대조하는 그 줄).
//   ③ 디코더 칸 = 초안 키(STATE 28 · WATCH 20) · 픽스처 값이 디코딩 뒤 그대로 산다(디코더가 키 하나를 모르면 그 값이 조용히 nil).
//   ④ 요청 본문 키 = SQL 인자 이름 · DEFAULT 없는 인자는 다 싣는다(PostgREST 는 본문 키 집합으로 함수를 고른다 — 이름 하나가
//      어긋나면 PGRST202). 바뀐 서명(challenge)과 새 셋은 초안, 그대로인 아홉은 v1 정본(20261110130000)에서 읽는다.
//   ⑤ 초안이 내는 status 글자 ⊆ `AlkkagiRPCStatus` · 실행권 목록 = `RPC.all` · `alk_protocol()` = `protocolVersion` · 판돈 = `AlkkagiStake`.
//   ⑥ 운영 어댑터 왕복(`attach(host:)` → 공용 `duelRPC` → snake 접기 디코더)으로 픽스처가 스토어에 선다 · PGRST202 → '곧 열려요'.
//
// 초안 위치: `ALKKAGI_MIGRATION_SQL=<파일>` → 없으면 조상의 `supabase/migrations/20261110160000_alkkagi_v2.sql`.
// `ALKKAGI_REQUIRE_MIGRATION=1` 이면 없을 때 건너뛰지 않고 빨갛다(SPEC §1 계약 시험 변수). v1 정본은 조상의 `supabase/migrations`.

private let afcDraftName = "20261110160000_alkkagi_v2.sql"
private let afcV1Name = "20261110130000_alkkagi.sql"

private struct AFCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func afcAncestorMigration(_ name: String) -> URL? {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(name)")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private func afcDraftURL() -> URL? {
    if let path = ProcessInfo.processInfo.environment["ALKKAGI_MIGRATION_SQL"], !path.isEmpty {
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    return afcAncestorMigration(afcDraftName)
}

private let afcRequired = ProcessInfo.processInfo.environment["ALKKAGI_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 초안이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let afcGate = afcDraftURL() != nil || afcRequired

/// `--` 줄 주석을 걷는다(키 배열 줄의 꼬리 주석이 글자를 흐리지 않게 — 하우스 규칙).
private func afcStrip(_ raw: String) -> String {
    raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        guard let range = line.range(of: "--") else { return String(line) }
        return String(line[..<range.lowerBound])
    }.joined(separator: "\n")
}

private func afcDraft() throws -> String {
    guard let url = afcDraftURL() else {
        throw AFCError("""
            1:1 알까기 v2 초안이 없다(ALKKAGI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["ALKKAGI_MIGRATION_SQL"] ?? "(없음)")) \
            — ALKKAGI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    return afcStrip(try String(contentsOf: url, encoding: .utf8))
}

private func afcV1() throws -> String {
    guard let url = afcAncestorMigration(afcV1Name) else {
        throw AFCError("v1 정본 \(afcV1Name) 이 체인에 없다(워크트리면 supabase 심링크)")
    }
    return afcStrip(try String(contentsOf: url, encoding: .utf8))
}

/// 초안의 `v_<name>_keys constant text[] := array[...]` 한 벌.
private func afcKeys(_ name: String, in sql: String) throws -> Set<String> {
    let pattern = "v_\(name)_keys\\s+constant\\s+text\\[\\]\\s*:=\\s*array\\[([^\\]]*)\\]"
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    guard let match = regex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)),
          let body = Range(match.range(at: 1), in: sql) else { throw AFCError("v_\(name)_keys 를 못 찾았다") }
    let items = sql[body].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n'")) }
    return Set(items.filter { !$0.isEmpty })
}

/// `create or replace function public.<name>(` 의 인자 — (이름, DEFAULT 있음). 정의가 둘 이상이면 빨강(오버로드 0).
private func afcArguments(_ function: String, in sql: String) throws -> [String: Bool] {
    let pattern = "create\\s+or\\s+replace\\s+function\\s+public\\.\(function)\\s*\\(([^)]*)\\)"
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    let matches = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql))
    guard matches.count == 1, let body = Range(matches[0].range(at: 1), in: sql) else {
        throw AFCError("\(function) 정의가 \(matches.count)개다(하나여야 한다)")
    }
    var out: [String: Bool] = [:]
    for piece in sql[body].split(separator: ",") {
        let text = piece.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let name = text.split(separator: " ").first, name.hasPrefix("p_") else { continue }
        out[String(name)] = text.contains(" default ")
    }
    return out
}

private let afcFixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/alkkagi-rpc", isDirectory: true)

private func afcObject(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: afcFixtureDirectory.appendingPathComponent(name))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AFCError("\(name) 가 객체가 아니다") }
    return object
}

private func afcText(_ name: String) throws -> String {
    try String(contentsOf: afcFixtureDirectory.appendingPathComponent(name), encoding: .utf8)
}

private struct AFCCase: Decodable {
    let file: String
    let rpc: String
    let status: String
}

private struct AFCManifest: Decodable {
    let protocolVersion: Int
    let cases: [AFCCase]
    private enum CodingKeys: String, CodingKey { case protocolVersion = "protocol", cases }
}

private func afcManifest() throws -> AFCManifest {
    try JSONDecoder().decode(AFCManifest.self, from: Data(contentsOf: afcFixtureDirectory.appendingPathComponent("_manifest.json")))
}

private func afcKeySet(_ value: Any?) -> Set<String> { Set((value as? [String: Any])?.keys ?? [:].keys) }

/// 디코더 칸 이름(Mirror 라벨) → snake_case(`URL` · `ID` 꼬리는 한 낱말로).
private func afcFields(_ value: Any) -> Set<String> {
    Set(Mirror(reflecting: value).children.compactMap(\.label).map { label in
        let folded = label.replacingOccurrences(of: "URL", with: "Url").replacingOccurrences(of: "ID", with: "Id")
        return folded.reduce(into: "") { out, ch in
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
    })
}

/// 요청 본문 → 서비스와 같은 인코더(snake 접기)로 본 키 집합.
private func afcBodyKeys(_ call: AlkkagiCall) throws -> Set<String> {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let object = try JSONSerialization.jsonObject(with: encoder.encode(call.parameters)) as? [String: Any] ?? [:]
    return Set(object.keys)
}

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiFixtureContractTests {
    /// 없으면: 매니페스트에 적힌 케이스 파일이 빠지거나(통합 때 바꿔 끼우다 한 장 누락) 앱이 모르는 status · rpc 가 픽스처에 있어도 초록이다.
    @Test("① 매니페스트 — 파일 다 있음 · 남는 파일 0 · rpc ∈ RPC.all · status ∈ 열거 · protocol 2")
    func manifestIsCompleteAndKnown() throws {
        let manifest = try afcManifest()
        #expect(manifest.protocolVersion == AlkkagiOnlineWire.protocolVersion)
        #expect(manifest.cases.count >= 60, "S 원문 68장이 아니다(손 픽스처로 되돌아갔나): \(manifest.cases.count)")
        let listed = Set(manifest.cases.map(\.file))
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: afcFixtureDirectory.path)
            .filter { $0.hasPrefix("alkkagi_") && $0.hasSuffix(".json") })
        #expect(listed == onDisk, "매니페스트와 폴더가 다르다: \(listed.symmetricDifference(onDisk).sorted())")
        for entry in manifest.cases {
            #expect(AlkkagiOnlineWire.RPC.all.contains(entry.rpc), "\(entry.file): rpc \(entry.rpc)")
            let raw = try afcObject(entry.file)["status"] as? String
            #expect(raw == entry.status, "\(entry.file): 매니페스트 status 와 다르다")
            #expect(AlkkagiRPCStatus(rawValue: entry.status) != nil, "\(entry.file): 앱이 모르는 status \(entry.status)")
            #expect(entry.file.hasPrefix("\(entry.rpc)__"), "\(entry.file): 파일 이름이 rpc 와 어긋난다")
        }
        // 기준선: 모르는 글자는 열거가 받지 않는다(그래서 위 단언이 갈린다).
        #expect(AlkkagiRPCStatus(rawValue: "muted") == nil)
    }

    /// 없으면(②): 서버가 키를 더하거나 이름을 바꿔도(예: `door_open` → `doorOpen`) 손 픽스처 · 디코더가 옛 이름으로 초록이다.
    @Test("② 봉투 키 = 초안 v_*_keys(LOBBY · PEER · USER · INVITE · LIVE · STATE · WATCH · RANKING 셋)", .enabled(if: afcGate))
    func envelopeKeysMatchTheDraftConstants() throws {
        let sql = try afcDraft()
        let lobbyKeys = try afcKeys("lobby", in: sql), peerKeys = try afcKeys("peer", in: sql)
        let userKeys = try afcKeys("user", in: sql), inviteKeys = try afcKeys("invite", in: sql)
        let liveKeys = try afcKeys("live", in: sql), stateKeys = try afcKeys("state", in: sql)
        let watchKeys = try afcKeys("watch", in: sql), rankingKeys = try afcKeys("ranking", in: sql)
        let rankingMeKeys = try afcKeys("ranking_me", in: sql), rankingRowKeys = try afcKeys("ranking_row", in: sql)
        #expect(stateKeys.count == 28 && watchKeys.count == 20 && lobbyKeys.count == 13)

        for name in ["alkkagi_lobby__ok.json", "alkkagi_lobby__light.json", "alkkagi_lobby__door_closed.json"] {
            let lobby = try afcObject(name)
            #expect(Set(lobby.keys) == lobbyKeys, "\(name) 최상위")
            #expect(afcKeySet(lobby["me"]) == peerKeys, "\(name) me")
            for user in lobby["users"] as? [[String: Any]] ?? [] { #expect(Set(user.keys) == userKeys, "\(name) users") }
            for invite in lobby["incoming"] as? [[String: Any]] ?? [] {
                #expect(Set(invite.keys) == inviteKeys, "\(name) incoming")
                #expect(afcKeySet(invite["opponent"]) == peerKeys)
            }
            for live in lobby["matches"] as? [[String: Any]] ?? [] {
                #expect(Set(live.keys) == liveKeys, "\(name) matches")
                #expect(afcKeySet(live["black"]) == peerKeys && afcKeySet(live["white"]) == peerKeys)
            }
        }
        let base: Set<String> = ["status", "protocol", "server_now_ms", "me", "state"]
        let gateExtras: Set<String> = ["incoming", "outgoing", "need", "have", "ruby_balance", "side", "match_id", "stakes", "door_open"]
        for entry in try afcManifest().cases where !entry.rpc.hasSuffix("_lobby") && entry.rpc != "alkkagi_ranking" {
            let envelope = try afcObject(entry.file)
            let keys = Set(envelope.keys)
            #expect(base.isSubset(of: keys) && keys.subtracting(base).isSubset(of: gateExtras), "\(entry.file) 봉투 \(keys.sorted())")
            if let outgoing = envelope["outgoing"] as? [String: Any] { #expect(Set(outgoing.keys) == inviteKeys) }
            guard let state = envelope["state"] as? [String: Any] else { continue }
            // protocol 1 응답(옛 판 · 0.3.80)은 v1 STATE 19키 그대로다 — v2 28키의 앞 19키(SPEC §3.3 · 초안 v_state_keys 순서).
            let legacy = (envelope["protocol"] as? Int) == 1
            #expect(!legacy || envelope["door_open"] == nil, "\(entry.file): protocol 1 응답에 door_open 이 실렸다")
            let expected = entry.rpc.hasPrefix("alkkagi_watch") ? watchKeys : stateKeys
            if legacy {
                #expect(Set(state.keys).isSubset(of: stateKeys) && state.count == 19, "\(entry.file) 옛 state \(state.count)키")
            } else {
                #expect(Set(state.keys) == expected, "\(entry.file) state")
            }
            #expect(afcKeySet(state["black"]) == peerKeys && afcKeySet(state["white"]) == peerKeys)
        }
        let ranking = try afcObject("alkkagi_ranking__ok.json")
        #expect(Set(ranking.keys) == rankingKeys && afcKeySet(ranking["me"]) == rankingMeKeys)
        for row in ranking["rows"] as? [[String: Any]] ?? [] { #expect(Set(row.keys) == rankingRowKeys) }
    }

    /// 없으면(③): 디코더가 STATE · WATCH 키 하나를 모르거나(값이 조용히 nil) 픽스처의 v2 값을 다른 칸으로 옮겨도 초록이다.
    @Test("③ 디코더 칸 = 초안 STATE 28 · WATCH 20 · 픽스처 값이 디코딩 뒤 그대로", .enabled(if: afcGate))
    func decoderFieldsMatchTheDraftAndCarryValues() throws {
        let sql = try afcDraft()
        // 관전자가 붙은 조준 판(S `state__watched` — watchers 1 · 놓친 차례 상대 1)이라 0 이 아닌 v2 값이 디코딩 뒤 사는지 잰다.
        let aiming = try #require(try akFixture("alkkagi_state__watched").state)
        #expect(afcFields(aiming) == (try afcKeys("state", in: sql)), "STATE 디코더 칸 ≠ 초안 v_state_keys")
        let watching = try #require(try akFixture("alkkagi_watch_live__ok").watch)
        #expect(afcFields(watching) == (try afcKeys("watch", in: sql)), "WATCH 디코더 칸 ≠ 초안 v_watch_keys")

        let raw = try afcObject("alkkagi_state__watched.json")["state"] as? [String: Any] ?? [:]
        #expect(aiming.stake == raw["stake"] as? Int && aiming.acceptedAtMs == raw["accepted_at_ms"] as? Double)
        #expect(aiming.myMissedTurns == raw["my_missed_turns"] as? Int && aiming.forfeitAfter == raw["forfeit_after"] as? Int)
        #expect(aiming.settled == raw["settled"] as? Bool && aiming.rubyBalance == raw["ruby_balance"] as? Int)
        #expect(aiming.watchers == raw["watchers"] as? Int && aiming.graceMs == raw["grace_ms"] as? Double)
        #expect(aiming.watchers == 1 && aiming.graceMs == 2000 && aiming.opponentMissedTurns == 1, "기준선: 픽스처가 0 이 아닌 값을 싣는다")
        #expect(try #require(try akFixture("alkkagi_state__aiming").state).watchers == 0, "기준선: 관전자 없는 같은 판은 0")

        // 값은 S 원문 그대로다(uuid · 시각은 생성한 판 값 — 매니페스트 notes). 사람 줄 칸 넷이 줄마다 디코딩 뒤 산다.
        let rawLobby = try afcObject("alkkagi_lobby__ok.json")
        let lobby = try akFixture("alkkagi_lobby__ok")
        #expect(lobby.doorOpen == true && lobby.stakes == AlkkagiStake.allCases.map(\.rawValue) && lobby.rubyBalance == 100)
        #expect(lobby.record == AlkkagiRecord(wins: 0, losses: 0, draws: 0), "전체 로비 record 는 null 이 아니라 0 이다")
        let users = try #require(lobby.users)
        let rawUsers = rawLobby["users"] as? [[String: Any]] ?? []
        #expect(users.count == rawUsers.count && users.count >= 10)
        #expect(users.map(\.isWorking) == rawUsers.map { $0["is_working"] as? Bool ?? false })
        #expect(users.map(\.inMatch) == rawUsers.map { $0["in_match"] as? Bool ?? false })
        #expect(users.map(\.isCapable) == rawUsers.map { $0["capable"] as? Bool ?? false })
        #expect(users.map(\.isFocused) == rawUsers.map { $0["focus_mode"] as? Bool ?? false })
        // 기준선: 원문이 네 칸 모두 참 · 거짓을 섞어 싣는다(전부 같은 값이면 위 대조가 디코더 결함을 못 가른다).
        #expect(Set(users.map(\.isWorking)) == [true, false] && Set(users.map(\.inMatch)) == [true, false])
        #expect(Set(users.map(\.isCapable)) == [true, false])
        let live = try #require(lobby.matches?.first)
        #expect(live.stake == 3 && live.shotCount == 0 && live.watchers == 0 && live.acceptedAt != nil)
        #expect(lobby.incoming?.first?.stake == 3 && lobby.outgoing?.stake == 5)
        let light = try akFixture("alkkagi_lobby__light")
        #expect(light.record == nil && light.users == [] && light.matches == [])
        #expect(try akFixture("alkkagi_lobby__door_closed").doorOpen == false)

        let insufficient = try akFixture("alkkagi_challenge__insufficient")
        #expect(insufficient.need == 3 && insufficient.have == 2 && insufficient.rubyBalance == 2)
        let challenger = try akFixture("alkkagi_respond__insufficient_challenger")
        #expect(challenger.side == "challenger" && challenger.have == nil && challenger.need == 10 && challenger.rubyBalance == 100)
        let mine = try akFixture("alkkagi_respond__insufficient_me")
        #expect(mine.side == "me" && mine.have == 4 && mine.need == 10 && mine.rubyBalance == 4)
        let pending = try akFixture("alkkagi_challenge__already_pending")
        #expect(pending.matchID != nil && pending.matchID == pending.outgoing?.id)
        // 문 닫힘 ↔ 문 열림(내 build 모자람)이 같은 status 안에서 door_open 으로 갈린다(VC-8).
        #expect(try akFixture("alkkagi_challenge__unsupported_client_door_closed").doorOpen == false)
        #expect(try akFixture("alkkagi_challenge__unsupported_client").doorOpen == true)
        #expect(try akFixture("alkkagi_challenge__unsupported_client_v1").doorOpen == nil)
        let board = try #require(try akFixture("alkkagi_ranking__ok").ranking)
        #expect(board.me == AlkkagiMyRank(rank: 3, wins: 1, losses: 1, draws: 1, points: 0))
        #expect(board.entries.map(\.rank) == [1, 1, 3, 3, 5, 5] && board.entries.allSatisfy { $0.points == $0.wins - $0.losses })
        let placing = try #require(try akFixture("alkkagi_watch__placing").watch)
        #expect(placing.stones.isEmpty && placing.phase == .placing && placing.stake == 3 && !placing.blackReady)
        #expect(watching.stones.count == 10 && watching.watchers == 1 && watching.whiteMissedTurns == 1, "기준선: 진행 판은 돌이 실린다")
    }

    /// 없으면(④): 앱 요청 본문 키가 SQL 인자 이름과 갈려(예: `p_stake` 누락 · 오타) 운영에서만 PGRST202 가 나도 초록이다.
    @Test("④ 요청 본문 키 = SQL 인자 이름 · DEFAULT 없는 인자 전부 · challenge 에 p_stake", .enabled(if: afcGate))
    func requestBodiesMatchSQLArguments() throws {
        let draft = try afcDraft()
        let v1 = try afcV1()
        let id = UUID()
        let samples: [AlkkagiCall] = [
            .lobby(users: false), .challenge(opponentID: id, stake: 5, actionID: id), .cancel(matchID: id, actionID: id),
            .respond(matchID: id, accept: true, actionID: id), .state(matchID: id, sinceChatSeq: 3),
            .place(matchID: id, expectedPlacementRevision: 1, stoneID: 0, position: AlkkagiVector(x: 1, y: 2), actionID: id),
            .ready(matchID: id, expectedPlacementRevision: 1, actionID: id),
            .shoot(matchID: id, expectedRevision: 1, stoneID: 0, pull: AlkkagiVector(x: 1, y: 2), actionID: id),
            .resign(matchID: id, expectedRevision: 1, actionID: id), .leave(matchID: id, expectedRevision: 1, actionID: id),
            .chatSend(matchID: id, body: "hi", actionID: id), .chatMute(matchID: id, muted: true, actionID: id),
            .ranking, .watch(matchID: id), .watchLive(matchID: id),
        ]
        #expect(Set(samples.map(\.rpcName)) == Set(AlkkagiOnlineWire.RPC.all))
        let draftOwned: Set<String> = ["alkkagi_lobby", "alkkagi_challenge", "alkkagi_ranking", "alkkagi_watch", "alkkagi_watch_live"]
        for call in samples {
            let source = draftOwned.contains(call.rpcName) ? draft : v1
            let arguments = try afcArguments(call.rpcName, in: source)
            let body = try afcBodyKeys(call)
            #expect(body.isSubset(of: Set(arguments.keys)), "\(call.rpcName): SQL 에 없는 키 \(body.subtracting(arguments.keys).sorted())")
            let required = Set(arguments.filter { !$0.value }.keys)
            #expect(required.isSubset(of: body), "\(call.rpcName): 빠진 필수 인자 \(required.subtracting(body).sorted())")
            #expect(body.contains("p_protocol"))
        }
        // challenge 는 초안에서만 판돈을 받는다(v1 서명은 drop) — 기준선: v1 정의에는 p_stake 가 없다.
        #expect(try afcArguments("alkkagi_challenge", in: draft)["p_stake"] != nil)
        #expect(try afcArguments("alkkagi_challenge", in: v1)["p_stake"] == nil)
        #expect(try afcBodyKeys(.challenge(opponentID: id, stake: 10, actionID: id)).contains("p_stake"))
    }

    /// 없으면(⑤): 서버가 새 status 를 내는데 앱이 `unknown` 으로 접어 '업데이트' 안내를 띄우거나, 실행권 · protocol · 판돈 상수가 갈려도 초록이다.
    @Test("⑤ status 글자 ⊆ 열거 · 실행권 15 = RPC.all · alk_protocol() = 2 · alk_stakes() = 3 · 5 · 10", .enabled(if: afcGate))
    func vocabularyGrantsProtocolAndStakesMatch() throws {
        let sql = try afcDraft()
        let patterns = ["alk_reply\\(\\s*[a-z_0-9]+\\s*,\\s*'([a-z_]+)'",
                        "jsonb_build_object\\(\\s*'status'\\s*,\\s*'([a-z_]+)'"]
        var words: Set<String> = []
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            for match in regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)) {
                if let range = Range(match.range(at: 1), in: sql) { words.insert(String(sql[range])) }
            }
        }
        #expect(words.count >= 15)
        for word in words.sorted() {
            #expect(AlkkagiRPCStatus(rawValue: word) != nil, "초안이 내는 '\(word)' 를 앱이 모른다")
        }
        let grants = try NSRegularExpression(pattern: "v_rpc\\s+constant\\s+text\\[\\]\\s*:=\\s*array\\[([^\\]]*)\\]", options: [])
        let grantMatch = try #require(grants.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)))
        let grantBody = try #require(Range(grantMatch.range(at: 1), in: sql))
        let granted = Set(sql[grantBody].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n'")) })
        #expect(granted == Set(AlkkagiOnlineWire.RPC.all), "실행권 목록 ≠ RPC.all: \(granted.symmetricDifference(AlkkagiOnlineWire.RPC.all).sorted())")
        let squashed = sql.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(squashed.contains("function public.alk_protocol() returns integer language sql immutable security definer set search_path = pg_catalog as $fn$ select \(AlkkagiOnlineWire.protocolVersion) $fn$"))
        let stakes = AlkkagiStake.allCases.map { String($0.rawValue) }.joined(separator: ", ")
        #expect(squashed.contains("function public.alk_stakes() returns integer[] language sql immutable security definer set search_path = pg_catalog as $fn$ select array[\(stakes)] $fn$"))
    }

    /// 없으면(⑥): 스텁이 응답 값을 바로 넘겨서 운영 길(공용 `duelRPC` · snake 접기 디코더 · PGRST202 접기)의 결함이 숨어도 초록이다
    /// (메모리 stub-tests-hide-roundtrip-bugs).
    @Test("⑥ 운영 어댑터 왕복 — 픽스처가 스토어에 선다 · 본문에 p_protocol 2 · p_stake · PGRST202 → 곧 열려요")
    func liveAdapterRoundTrip() async throws {
        let hostName = "v03xx-alkkagi-fc-\(UUID().uuidString.prefix(8))".lowercased()
        let lobby = try afcText("alkkagi_lobby__ok.json")
        let insufficient = try afcText("alkkagi_challenge__insufficient.json")
        GomokuStubProtocol.register(host: hostName) { rpc, _, index in
            switch rpc {
            case "alkkagi_lobby":
                if index >= 1 {
                    return .init(status: 404, body: #"{"code":"PGRST202","details":"Searched for the function public.alkkagi_lobby with parameters","hint":null,"message":"Could not find the function public.alkkagi_lobby in the schema cache"}"#)
                }
                return .init(body: lobby)
            case "alkkagi_challenge": return .init(body: insufficient)
            default: return .init(status: 500, body: "{}")
            }
        }
        let host = AKHost(hostName: hostName)
        let store = AlkkagiOnlineStore()
        store.attach(host: host)
        defer { store.reset() }
        await store.refreshLobby()
        let rawUsers = (try afcObject("alkkagi_lobby__ok.json")["users"] as? [[String: Any]] ?? []).count
        #expect(store.availability == .available && store.users.count == rawUsers && store.liveMatches.count == 1)
        #expect(host.rubyBalance == 100 && store.record == AlkkagiRecord(wins: 0, losses: 0, draws: 0))
        let first = try #require(store.visibleUsers.first)
        #expect(first.canBeChallenged && first.isWorking, "정렬 첫 줄이 '가능 · 근무 · 대결 아님'이 아니다: \(first.displayName)")
        await store.challenge(opponentID: first.id, stake: .three)
        #expect(host.rubyBalance == 2 && store.notice == "루비 1개 더 필요해요")
        let calls = GomokuStubProtocol.calls(host: hostName)
        #expect(calls.map(\.rpc) == ["alkkagi_lobby", "alkkagi_challenge"])
        #expect(calls[0].json["p_protocol"] as? Int == 2 && calls[0].json["p_users"] as? Bool == true)
        #expect(calls[1].json["p_stake"] as? Int == 3 && calls[1].json["p_protocol"] as? Int == 2)
        await store.refreshLobby()
        #expect(store.availability == .serverMissing && store.notice == AlkkagiNoticeText.unavailable)
    }
}
