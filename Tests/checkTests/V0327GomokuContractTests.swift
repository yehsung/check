import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.27 → **0.3.28 로 다시 떴다** — 1:1 오목 서버↔앱 **응답 계약**(실제 SQL 출력).
//
// 픽스처 `Fixtures/gomoku-rpc/*.json` 은 스텁 추측이 아니다. 로컬 하네스(마이그레이션 체인 + 20260916120000_gomoku_duel.sql
// + 20260916200000_gomoku_chat.sql + 20260916210000_gomoku_timeout_autoplace.sql)에 harness.login 으로 authenticated
// 흉내를 내 RPC 를 **실제로 부른 jsonb 출력 그대로**다. 생성기는 `_gen_fixtures.py.txt`,
// 호출자·준비 SQL·M1 흐름 순서는 `_manifest.json` 에 있다(흑백은 서버 random() 이라 흐름은 manifest 가 말한다).
//
// ⚠️ 0.3.28 에서 **사라진 응답**은 픽스처도 지웠다: `gomoku_move__timeout` · `gomoku_resign__timeout`.
//    판은 더 이상 시간으로 죽지 않는다 — 마감이 지나면 서버가 무작위로 대신 놓고(`auto_placed`),
//    연속 3회면 `end_reason='abandoned'` 로 끝난다. 그 자리를 아래 자동 착수 테스트가 대신 지킨다.
//    (`GomokuRPCStatus.timeout` 과 `GomokuEndReason.timeout` 은 **모델에 남겨 둔다** — 배포 중간 창의 옛 서버가 아직 보낸다.)
//
// 여기서 보는 것: ① 모든 응답이 앱의 실제 응답 모델로 throw 없이 디코드되고 status 가 .unknown 으로 접히지 않는다
// ② 그 응답을 GomokuStore 에 먹이면(호스트별 URLProtocol 스텁이 픽스처를 순서대로 돌려준다) 화면 상태 — phase·board·turn·
// myColor·deadline(server_now_ms 보정)·outcome·endReason·rubyDelta·rubyBalance·notice·incoming/outgoing·blackPassed — 가
// 서버가 말한 사실과 같다. 스토어가 내는 요청 인자(p_expected_seq·p_since_seq)도 서버가 그 응답을 만든 인자와 같다.

// MARK: - 픽스처 도구

private struct ContractError: Error, CustomStringConvertible {
    let description: String
}

private let contractDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/gomoku-rpc", isDirectory: true)

private func fixtureData(_ name: String) throws -> Data {
    try Data(contentsOf: contractDirectory.appendingPathComponent("\(name).json"))
}

private func fixtureText(_ name: String) throws -> String {
    String(decoding: try fixtureData(name), as: UTF8.self)
}

private func fixtureJSON(_ name: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any] else {
        throw ContractError(description: "\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func contractDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

private func contractManifest() throws -> [String: Any] {
    try fixtureJSON("_manifest")
}

private func callerOf(_ name: String) throws -> String {
    let fixtures = try contractManifest()["fixtures"] as? [String: Any]
    guard let entry = fixtures?[name] as? [String: Any], let caller = entry["caller"] as? String else {
        throw ContractError(description: "manifest 에 \(name) 호출자가 없다")
    }
    return caller
}

private func contractUser(_ key: String) throws -> String {
    guard let value = (try contractManifest()["users"] as? [String: String])?[key] else {
        throw ContractError(description: "manifest users.\(key) 없음")
    }
    return value
}

private func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

/// 상태를 싣는 응답 하나에서 읽은 서버의 사실.
private struct ServerFacts {
    let status: String
    let matchID: String
    let matchStatus: String
    let board: String
    let moveCount: Int
    let turn: String?
    let myColor: String
    let myID: String
    let result: String?
    let endReason: String?
    let stake: Int
    let ruby: Int?
    let serverNowMs: Double?
    let deadlineMs: Double?

    init(_ object: [String: Any]) throws {
        guard let match = object["match"] as? [String: Any],
              let status = object["status"] as? String,
              let id = match["id"] as? String,
              let matchStatus = match["status"] as? String,
              let board = match["board"] as? String,
              let moveCount = match["move_count"] as? Int,
              let myColor = object["my_color"] as? String,
              let stake = match["stake"] as? Int,
              let myID = (myColor == "black" ? match["black"] : match["white"]) as? String
        else { throw ContractError(description: "상태 응답 모양이 아니다: \(object.keys.sorted())") }
        self.status = status
        matchID = id
        self.matchStatus = matchStatus
        self.board = board
        self.moveCount = moveCount
        turn = match["turn"] as? String
        self.myColor = myColor
        self.myID = myID
        result = match["result"] as? String
        endReason = match["end_reason"] as? String
        self.stake = stake
        ruby = object["ruby_balance"] as? Int
        serverNowMs = number(object["server_now_ms"])
        deadlineMs = number(match["deadline_ms"])
    }

    init(fixture name: String) throws {
        try self.init(fixtureJSON(name))
    }

    var expectedOutcome: GomokuOutcome? {
        switch result {
        case "draw": return .draw
        case "black_win": return myColor == "black" ? .won : .lost
        case "white_win": return myColor == "white" ? .won : .lost
        default: return nil
        }
    }
}

/// 스토어의 대국 상태가 서버 사실과 같은가. `clock` 은 스토어에 꽂은 고정 '지금'(마감 보정 기준).
@MainActor
private func expectMatchEqualsServer(
    _ gomoku: GomokuStore,
    _ facts: ServerFacts,
    clock: Date,
    lastMove: GomokuPoint?? = nil,
    blackPassed: Bool? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let match = gomoku.match
    #expect(match?.id == facts.matchID, sourceLocation: sourceLocation)
    #expect(match?.board.serverString == facts.board, "판이 서버 board 와 다르다", sourceLocation: sourceLocation)
    #expect(match?.moveCount == facts.moveCount, sourceLocation: sourceLocation)
    #expect(match?.turn?.rawValue == facts.turn, "차례", sourceLocation: sourceLocation)
    #expect(match?.myColor.rawValue == facts.myColor, sourceLocation: sourceLocation)
    #expect(match?.stake == facts.stake, sourceLocation: sourceLocation)
    let finished = facts.matchStatus == "finished"
    #expect(match?.isFinished == finished, sourceLocation: sourceLocation)
    #expect(gomoku.phase == (finished ? .result : .playing), sourceLocation: sourceLocation)
    if !finished, let deadlineMs = facts.deadlineMs, let serverNowMs = facts.serverNowMs {
        // 서버 시계와 기기 시계가 몇 시간·며칠 어긋나도(픽스처는 과거에 떴다) 기기 시각으로는 '지금 + (마감 − 서버 지금)'이다.
        let expected = clock.addingTimeInterval((deadlineMs - serverNowMs) / 1000)
        let actual = match?.deadline ?? .distantPast
        // 오프셋은 문턱(250ms) 넘게 어긋날 때만 다시 잰다(2차 검증 set #1 수리 — 같은 신청·같은 마감이 응답마다 바뀌지 않게).
        // 픽스처는 이 고정 시계와 무관한 시각에 떴고 한 흐름 안의 server_now 가 수십 ms 씩 다르므로, 보정 오차는 문턱 안이면 맞다.
        let tolerance = GomokuStore.serverClockToleranceSeconds + 0.002
        #expect(abs(actual.timeIntervalSince(expected)) < tolerance,
                "마감 보정: \(actual.timeIntervalSince(expected))초 어긋남", sourceLocation: sourceLocation)
        let remaining = gomoku.remainingSeconds(now: clock) ?? -1
        #expect(remaining > 29 && remaining <= 30 + tolerance, "남은 시간 \(remaining)초", sourceLocation: sourceLocation)
    } else {
        #expect(match?.deadline == nil, sourceLocation: sourceLocation)
        #expect(gomoku.remainingSeconds(now: clock) == nil, sourceLocation: sourceLocation)
    }
    #expect(match?.outcome == facts.expectedOutcome, "결과", sourceLocation: sourceLocation)
    if let reason = facts.endReason {
        #expect(match?.endReason != nil && match?.endReason?.rawValue == reason, "끝난 이유 \(reason)", sourceLocation: sourceLocation)
    } else {
        #expect(match?.endReason == nil, sourceLocation: sourceLocation)
    }
    let expectedDelta: Int? = facts.expectedOutcome.map {
        switch $0 {
        case .won: return facts.stake
        case .lost: return -facts.stake
        case .draw: return 0
        }
    }
    #expect(match?.rubyDelta == expectedDelta, sourceLocation: sourceLocation)
    if let ruby = facts.ruby {
        #expect(gomoku.rubyBalance == ruby, "루비", sourceLocation: sourceLocation)
    }
    if let lastMove {
        #expect(match?.lastMove == lastMove, "마지막 수", sourceLocation: sourceLocation)
    }
    if let blackPassed {
        #expect(match?.blackPassed == blackPassed, "흑 자동 패스", sourceLocation: sourceLocation)
    }
}

// MARK: - 스토어 조립(호스트별 스텁 · rpc 별 픽스처 큐)

@MainActor
private enum ContractRetention {
    static var stores: [WorkTimerStore] = []
}

private let contractClock = Date(timeIntervalSince1970: 1_900_000_000)

/// `queues[rpc]` 의 픽스처 본문을 그 rpc 의 호출 순서대로 돌려준다. 큐 밖의 호출은 500(스토어의 실패 경로 — 화면을 안 바꾼다).
@MainActor
private func makeContractStore(
    _ label: String, me: String, queues: [String: [String]]
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0327-contract-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    let frozen = queues
    GomokuStubProtocol.register(host: host) { rpc, _, index in
        guard let list = frozen[rpc], index < list.count else {
            return GomokuStubProtocol.Reply(status: 500, body: #"{"message":"not scripted"}"#)
        }
        return GomokuStubProtocol.Reply(body: list[index])
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let defaults = GomokuTestDefaults.make("v0327-contract")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    ContractRetention.stores.append(store)
    store.gomoku.clock = { contractClock }
    return (store, store.gomoku, host)
}

@MainActor
private func contractWait(_ timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async {
    // 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례). 전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥐어
    // 벽시계 상한이 스토어의 Task 가 차례를 받기도 전에 끝났다(0.3.27 전체 실행: 690초 지점에서 20초 대기 실패, 격리 3/3 초록).
    // V0325TooltipTests.waitUntil 과 같은 해법 — 재개마다 메인 액터 차례를 거치므로 스토어의 Task 도 같은 줄에서 순서를 받는다.
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 픽스처(최상위 상태 묶음)를 스토어에 심는다. `mutate` 로 한 기기의 옛 화면을 흉내 낼 수 있다(판·기록을 덜어 낸다).
@MainActor
private func seed(_ gomoku: GomokuStore, _ name: String, mutate: ((inout [String: Any]) -> Void)? = nil) throws {
    var object = try fixtureJSON(name)
    object.removeValue(forKey: "state")
    mutate?(&object)
    let data = try JSONSerialization.data(withJSONObject: object)
    let payload = try contractDecoder().decode(GomokuStatePayload.self, from: data)
    #expect(gomoku.applyState(payload) == .applied, "seed \(name)")
}

private func lastBody(_ host: String, _ rpc: String) -> [String: Any] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).last?.json ?? [:]
}

private func peer(_ id: String) -> GomokuUser {
    GomokuUser(id: id, displayName: "", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: false)
}

// MARK: - 1. 디코드: 모든 픽스처가 앱의 실제 응답 모델로 읽힌다

@Test(.gomokuDefaultsCleanup)
func 실서버_오목_응답_전부가_앱_응답_모델로_디코드되고_status_를_안다() throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: contractDirectory.path)
        .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
        .map { String($0.dropLast(5)) }
        .sorted()
    #expect(names.count >= 60, "픽스처 수 \(names.count)")
    let decoder = contractDecoder()
    for name in names {
        let object = try fixtureJSON(name)
        let data = try fixtureData(name)
        let raw = try #require(object["status"] as? String, "\(name) status")
        let family = name.hasPrefix("flow_m1_")
            ? (name.hasSuffix("_move") ? "move" : "state")
            : String(name.split(separator: "_", omittingEmptySubsequences: true)[1])
        let status: GomokuRPCStatus
        switch family {
        case "lobby":
            let response = try decoder.decode(GomokuLobbyResponse.self, from: data)
            status = response.status
            #expect(response.me != nil && response.users != nil && response.serverNowMs != nil, "\(name)")
        case "inbox":
            let response = try decoder.decode(GomokuInboxResponse.self, from: data)
            status = response.status
            #expect(response.incoming != nil && response.serverNowMs != nil, "\(name)")
        case "state":
            let response = try decoder.decode(GomokuStateResponse.self, from: data)
            status = response.status
            #expect((response.state.match != nil) == (raw == "ok"), "\(name) 최상위 상태")
            if response.state.match != nil {
                let action = try decoder.decode(GomokuActionResponse.self, from: data)
                #expect(action.state == response.state, "\(name) state 키 안과 최상위가 같은 묶음이다")
            }
        default:
            let response = try decoder.decode(GomokuActionResponse.self, from: data)
            status = response.status
            if object["match"] != nil {
                #expect(response.state?.match?.id == (object["match"] as? [String: Any])?["id"] as? String, "\(name) 상태")
                let top = try decoder.decode(GomokuStatePayload.self, from: data)
                #expect(response.state == top, "\(name) state 키 안과 최상위가 같다")
            }
        }
        #expect(status != .unknown, "\(name): '\(raw)' 가 unknown 으로 접혔다")
        #expect(status.rawValue == raw, "\(name): \(status.rawValue) vs \(raw)")
    }
}

@Test(.gomokuDefaultsCleanup)
func 서버_board_인덱스는_앱_GomokuBoard_와_같은_y15x_이고_판정도_같다() throws {
    // 실제 기록(9수)으로 쌓은 앱 판 == 서버 board 문자열
    let finished = try fixtureJSON("gomoku_state__finished_loser_since0")
    let moves = try #require(finished["moves"] as? [[String: Any]])
    var board = GomokuBoard()
    for move in moves {
        let point = try #require(GomokuPoint(x: move["x"] as? Int ?? -1, y: move["y"] as? Int ?? -1))
        board[point] = GomokuColor(rawValue: move["color"] as? String ?? "")
    }
    #expect(board.serverString == (finished["match"] as? [String: Any])?["board"] as? String)

    // 서버가 forbidden(double-three)으로 막은 실제 판에서 앱 판정도 3-3 금수다
    let forbidden = try ServerFacts(fixture: "gomoku_move__forbidden_double_three")
    let forbiddenBoard = try #require(GomokuBoard(serverString: forbidden.board))
    #expect(GomokuRules.judge(board: forbiddenBoard, point: GomokuPoint(x: 7, y: 7)!, color: .black) == .forbidden(.doubleThree))

    // 서버가 흑 자동 패스를 선언한 판: 앱에서도 흑이 둘 곳이 없다(남은 빈칸은 전부 금수)
    let passed = try ServerFacts(fixture: "gomoku_move__ok_black_passed")
    let passBoard = try #require(GomokuBoard(serverString: passed.board))
    #expect(passBoard.stoneCount == 224)
    var blackLegal = 0
    for y in 0..<15 {
        for x in 0..<15 {
            let point = GomokuPoint(x: x, y: y)!
            guard passBoard[point] == nil else { continue }
            switch GomokuRules.judge(board: passBoard, point: point, color: .black) {
            case .legal, .win: blackLegal += 1
            default: break
            }
        }
    }
    #expect(blackLegal == 0, "서버는 흑 패스, 앱은 흑이 둘 곳 \(blackLegal)칸")
    // 백이 두기 전 판에서는 흑이 (2,0) 에 둘 수 있었다(서버 gomoku_black_has_move true 였던 판)
    let before = try ServerFacts(fixture: "gomoku_state__ok_before_pass_white")
    let beforeBoard = try #require(GomokuBoard(serverString: before.board))
    #expect(GomokuRules.judge(board: beforeBoard, point: GomokuPoint(x: 2, y: 0)!, color: .black) == .legal)
}

// MARK: - 2. M1 전체 흐름: 수락 → 9수 → 흑 5목, 두 사람 시점

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: ["black", "white"])
func 실서버_M1_흐름을_두_사람_시점으로_재생하면_화면이_서버와_같다(perspective: String) async throws {
    let manifest = try contractManifest()
    let fullFlow = try #require(manifest["flow_m1"] as? [[String: Any]])
    let flow = fullFlow.filter { $0["perspective"] as? String == perspective }
    let m1 = try contractUser("m1")
    let accept = try ServerFacts(fixture: "gomoku_respond__accept_ok")
    let acceptMatch = try #require(try fixtureJSON("gomoku_respond__accept_ok")["match"] as? [String: Any])
    let blackID = try #require(acceptMatch["black"] as? String)
    let whiteID = try #require(acceptMatch["white"] as? String)
    let challengerID = try #require(acceptMatch["challenger"] as? String)
    let myID = perspective == "black" ? blackID : whiteID
    let peerID = perspective == "black" ? whiteID : blackID
    #expect(accept.stake == 5)

    var points: [Int: GomokuPoint] = [:]
    for entry in fullFlow where entry["kind"] as? String == "place" {
        points[(entry["expected"] as? Int ?? -1) + 1] = GomokuPoint(x: entry["x"] as? Int ?? -1, y: entry["y"] as? Int ?? -1)
    }
    var queues: [String: [String]] = [:]
    for entry in flow {
        let rpc: String
        switch entry["kind"] as? String {
        case "respond": rpc = "gomoku_respond"
        case "inbox": rpc = "gomoku_inbox"
        case "state": rpc = "gomoku_state"
        default: rpc = "gomoku_move"
        }
        queues[rpc, default: []].append(try fixtureText(try #require(entry["file"] as? String)))
    }
    queues["gomoku_lobby"] = [try fixtureText("gomoku_lobby__ok_after_win_\(perspective)")]
    let (store, gomoku, host) = makeContractStore("flow-\(perspective)", me: myID, queues: queues)
    if myID == challengerID {
        gomoku.outgoing = GomokuInvite(id: m1, peer: peer(peerID), stake: 5, expiresAt: contractClock.addingTimeInterval(50))
    } else {
        gomoku.incoming = [GomokuInvite(id: m1, peer: peer(peerID), stake: 5, expiresAt: contractClock.addingTimeInterval(50))]
    }

    var index = 0
    var states = 0
    var moves = 0
    while index < flow.count {
        let entry = flow[index]
        var file = try #require(entry["file"] as? String)
        switch entry["kind"] as? String {
        case "respond":
            await gomoku.respond(inviteID: m1, accept: true)
            #expect(gomoku.incoming.isEmpty, "수락한 신청 카드가 남았다")
            #expect(lastBody(host, "gomoku_respond")["p_accept"] as? Bool == true)
        case "inbox":
            // 인박스가 active_match_id 를 말하면 스토어가 곧바로 그 판을 since 0 으로 읽는다 — 흐름의 다음 항목이 그 응답이다.
            await gomoku.loadInbox()
            let next = flow[index + 1]
            #expect(next["kind"] as? String == "state")
            file = try #require(next["file"] as? String)
            index += 1
            states += 1
            #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == next["since"] as? Int)
            #expect(gomoku.outgoing == nil, "수락된 보낸 신청 카드가 남았다")
        case "state":
            await gomoku.refreshMatch()
            states += 1
            #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == entry["since"] as? Int,
                    "스토어가 낸 since 가 서버가 이 응답을 만든 since 와 다르다")
        default:
            let point = try #require(GomokuPoint(x: entry["x"] as? Int ?? -1, y: entry["y"] as? Int ?? -1))
            await gomoku.place(point)
            moves += 1
            #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == entry["expected"] as? Int)
            #expect(lastBody(host, "gomoku_move")["p_x"] as? Int == point.x)
        }
        #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == states, "\(file) state 호출 수")
        #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == moves, "\(file) move 호출 수")
        let facts = try ServerFacts(fixture: file)
        #expect(facts.myID == myID)
        expectMatchEqualsServer(gomoku, facts, clock: contractClock,
                                lastMove: .some(facts.moveCount > 0 ? points[facts.moveCount] : nil), blackPassed: false)
        #expect(gomoku.notice == nil, "\(file) 안내: \(gomoku.notice ?? "")")
        #expect(store.rubyBalance == facts.ruby, "\(file) 호스트 루비 칩")
        index += 1
    }

    let final = try #require(gomoku.match)
    #expect(final.isFinished)
    #expect(final.moveCount == 9)
    #expect(final.outcome == (perspective == "black" ? .won : .lost))
    #expect(final.endReason == .five)
    #expect(final.rubyDelta == (perspective == "black" ? 5 : -5))
    // 서버 정산 산수: 100 → 수락 −5 → 승자 +10
    #expect(gomoku.rubyBalance == (perspective == "black" ? 105 : 95))
    // 판이 끝난 순간 전적을 다시 읽는다(스토어 계약) — 서버 로비 me 가 이 판을 센다.
    await contractWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") == 1 && gomoku.record != nil }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") == 1)
    #expect(gomoku.record == (perspective == "black" ? GomokuRecord(wins: 1, losses: 0, draws: 0)
                                                     : GomokuRecord(wins: 0, losses: 1, draws: 0)))
    #expect(gomoku.phase == .result, "로비 재조회가 결과 화면을 걷었다")
}

// MARK: - 3. 신청 (gomoku_challenge 12종)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_신청_응답을_스토어가_사용자_문구와_보낸_신청으로_옮긴다() async throws {
    let rivalB = try contractUser("B")
    // (픽스처, 안내, 뒤따라 다시 읽는 rpc)
    let cases: [(String, String, String?)] = [
        ("gomoku_challenge__invalid", "신청할 수 없는 상대예요", nil),
        ("gomoku_challenge__unsupported_client", "앱을 업데이트해야 대결할 수 있어요", nil),
        ("gomoku_challenge__blackout", "지금은 조용한 기간이라 신청할 수 없어요", nil),
        ("gomoku_challenge__not_working", "근무 중일 때만 신청할 수 있어요", nil),
        ("gomoku_challenge__target_not_working", "상대가 근무 중이 아니에요", "gomoku_lobby"),
        ("gomoku_challenge__target_focused", "상대가 집중 모드라 신청할 수 없어요", nil),
        ("gomoku_challenge__target_outdated", "상대가 앱을 업데이트해야 해요", "gomoku_lobby"),
        ("gomoku_challenge__busy", "이미 진행 중인 대국이 있어요", "gomoku_inbox"),
        ("gomoku_challenge__target_busy", "상대가 다른 대국 중이에요", "gomoku_lobby"),
        ("gomoku_challenge__insufficient", "루비 6개 더 필요해요", nil),
        ("gomoku_challenge__already_pending", "이미 보낸 신청이 있어요", "gomoku_inbox"),
        ("gomoku_challenge__ok", "신청을 보냈어요", nil)
    ]
    for (name, notice, follow) in cases {
        let object = try fixtureJSON(name)
        let (_, gomoku, host) = makeContractStore("challenge", me: try callerOf(name), queues: [
            "gomoku_challenge": [try fixtureText(name)],
            "gomoku_lobby": [try fixtureText("gomoku_lobby__ok")]
        ])
        gomoku.selectedStake = name.hasSuffix("insufficient") ? .ten : .five
        await gomoku.challenge(userID: rivalB)
        #expect(gomoku.notice == notice, "\(name): \(gomoku.notice ?? "nil")")
        #expect(gomoku.isBusy == false)
        for rpc in ["gomoku_lobby", "gomoku_inbox"] {
            #expect(GomokuStubProtocol.count(host: host, rpc: rpc) == (rpc == follow ? 1 : 0), "\(name) → \(rpc)")
        }
        if let ruby = object["ruby_balance"] as? Int {
            #expect(gomoku.rubyBalance == ruby, "\(name) 루비")
        }
        if name.hasSuffix("__ok") {
            let sent = try #require(gomoku.outgoing)
            #expect(sent.id == object["match_id"] as? String)
            #expect(sent.stake == 5)
            #expect(sent.peer.id == rivalB)
            let expires = try #require(number(object["invite_expires_ms"]))
            let now = try #require(number(object["server_now_ms"]))
            #expect(abs(sent.expiresAt.timeIntervalSince(contractClock.addingTimeInterval((expires - now) / 1000))) < 0.002)
            #expect(abs(sent.expiresAt.timeIntervalSince(contractClock) - 60) < 0.5, "신청 유효 60초")
        } else {
            #expect(gomoku.outgoing == nil, "\(name) 보낸 신청이 생겼다")
        }
        if follow == "gomoku_lobby" {
            #expect(gomoku.users.count == 5, "\(name) 로비 재조회가 목록을 채운다")
        }
    }
}

// MARK: - 4. 취소 · 응답

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_취소_응답은_보낸_신청을_걷고_끝난_신청은_다시_읽는다() async throws {
    for (name, notice, inbox) in [("gomoku_cancel__ok", "신청을 취소했어요", 0), ("gomoku_cancel__not_pending", "이미 끝난 신청이에요", 1)] {
        let (_, gomoku, host) = makeContractStore("cancel", me: try callerOf(name), queues: ["gomoku_cancel": [try fixtureText(name)]])
        gomoku.outgoing = GomokuInvite(id: "x", peer: peer(try contractUser("A")), stake: 3, expiresAt: contractClock.addingTimeInterval(40))
        await gomoku.cancelChallenge()
        #expect(gomoku.notice == notice, "\(name)")
        #expect(gomoku.outgoing == nil)
        #expect(gomoku.rubyBalance == 100)
        #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == inbox, "\(name) 인박스 재조회")
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_수락_거절_응답은_사유별_문구와_신청_카드를_맞춘다() async throws {
    // (픽스처, accept, 안내, 카드가 남는가, 루비)
    let cases: [(String, Bool, String, Bool, Int)] = [
        ("gomoku_respond__decline_ok", false, "신청을 거절했어요", false, 100),
        ("gomoku_respond__expired", true, "신청 시간이 지났어요", false, 100),
        ("gomoku_respond__insufficient_me", true, "루비 3개 더 필요해요", true, 2),
        ("gomoku_respond__insufficient_challenger", true, "상대의 루비가 모자라요", true, 100),
        ("gomoku_respond__target_not_working", true, "상대가 근무를 끝냈어요", true, 100)
    ]
    for (name, accept, notice, keeps, ruby) in cases {
        let (store, gomoku, _) = makeContractStore("respond", me: try callerOf(name), queues: ["gomoku_respond": [try fixtureText(name)]])
        store.rubyBalance = 55
        gomoku.incoming = [GomokuInvite(id: "inv", peer: peer(try contractUser("A")), stake: 5, expiresAt: contractClock.addingTimeInterval(40))]
        await gomoku.respond(inviteID: "inv", accept: accept)
        #expect(gomoku.notice == notice, "\(name): \(gomoku.notice ?? "nil")")
        #expect(gomoku.incoming.isEmpty == !keeps, "\(name) 카드")
        #expect(gomoku.match == nil && gomoku.phase == .lobby, "\(name) 판이 열렸다")
        #expect(gomoku.rubyBalance == ruby && store.rubyBalance == ruby, "\(name) 루비(낙관적 차감 없음 · 서버값)")
    }
}

// MARK: - 5. 착수 — 거절 · 판이 바뀐 경우

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_stale_은_since_0_응답으로_판을_맞추고_since_2_로_다시_읽는다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_move__stale")
    let (_, gomoku, host) = makeContractStore("stale", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__stale")],
        "gomoku_state": [try fixtureText("gomoku_state__ok_black_since2_count2")]
    ])
    // 이 기기는 같은 판의 count 0 화면에 머물러 있다. 서버가 수락 때 흑백을 **무작위로** 정하므로 픽스처를 새로 뜨면
    // 수락 응답의 호출자가 흑일 수도 백일 수도 있다 — 색을 못 박지 말고 stale 응답의 호출자와 같은 시점의 count 0 응답을 고른다.
    let flow = try #require(try contractManifest()["flow_m1"] as? [[String: Any]])
    let seedFile = try #require(flow.first { entry in
        guard entry["perspective"] as? String == facts.myColor,
              ["respond", "state"].contains(entry["kind"] as? String ?? ""),
              let file = entry["file"] as? String,
              let seedFacts = try? ServerFacts(fixture: file) else { return false }
        return seedFacts.matchID == facts.matchID && seedFacts.moveCount == 0
    }?["file"] as? String, "stale 호출자(\(facts.myColor))의 count 0 응답이 흐름에 없다")
    try seed(gomoku, seedFile)
    #expect(gomoku.match?.myColor.rawValue == facts.myColor && gomoku.match?.moveCount == 0)
    await gomoku.place(GomokuPoint(x: 5, y: 5)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 0)
    #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == 2)
    expectMatchEqualsServer(gomoku, try ServerFacts(fixture: "gomoku_state__ok_black_since2_count2"), clock: contractClock,
                            lastMove: .some(GomokuPoint(x: 0, y: 1)), blackPassed: false)
    #expect(gomoku.match?.board[GomokuPoint(x: 5, y: 5)!] == nil)
    #expect(gomoku.notice == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_not_your_turn_은_상대_차례라고_말하고_판을_맞춘다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_move__not_your_turn")
    let white = try contractManifest()["flow_m1"] as? [[String: Any]]
    let seedFile = try #require(white?.first { $0["perspective"] as? String == "white" && $0["since"] as? Int == 0
        && ($0["file"] as? String)?.hasPrefix("flow_m1_k0") == true }?["file"] as? String)
    let (_, gomoku, host) = makeContractStore("nyt", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__not_your_turn")],
        "gomoku_state": [try fixtureText("gomoku_state__ok_white_since2_count2")]
    ])
    try seed(gomoku, seedFile)                         // 백의 이 기기는 count 1(자기 차례)로 알고 있다
    #expect(gomoku.match?.turn == .white && gomoku.match?.moveCount == 1)
    await gomoku.place(GomokuPoint(x: 5, y: 5)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 1)
    #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == 2)
    expectMatchEqualsServer(gomoku, try ServerFacts(fixture: "gomoku_state__ok_white_since2_count2"), clock: contractClock,
                            lastMove: .some(GomokuPoint(x: 0, y: 1)))
    #expect(gomoku.notice == "상대 차례예요")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_invalid_occupied_는_둘_수_없다고_말하고_서버_판으로_덮는다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_move__invalid_occupied")
    let (_, gomoku, host) = makeContractStore("invalid", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__invalid_occupied")],
        "gomoku_state": [try fixtureText("gomoku_state__ok_black_since4_count4")]
    ])
    // 이 기기의 판에서 (0,0) 흑돌이 빠져 있다고 흉내 낸다(서버 board 도 덜어 낸다)
    try seed(gomoku, "gomoku_state__ok_since0") { object in
        var match = object["match"] as? [String: Any] ?? [:]
        match.removeValue(forKey: "board")
        object["match"] = match
        object["moves"] = (object["moves"] as? [[String: Any]] ?? []).filter { ($0["seq"] as? Int) != 1 }
    }
    #expect(gomoku.match?.board[GomokuPoint(x: 0, y: 0)!] == nil)
    await gomoku.place(GomokuPoint(x: 0, y: 0)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 4)
    #expect(gomoku.notice == "둘 수 없는 자리예요")
    expectMatchEqualsServer(gomoku, try ServerFacts(fixture: "gomoku_state__ok_black_since4_count4"), clock: contractClock)
    #expect(gomoku.match?.board[GomokuPoint(x: 0, y: 0)!] == .black)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_흑_금수_응답은_사유_문구를_말하고_판은_서버_board_다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_move__forbidden_double_three")
    let (_, gomoku, host) = makeContractStore("forbidden", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__forbidden_double_three")]
    ])
    // ① 같은 판이면 앱이 먼저 막는다(서버와 판정이 같다) — 요청 0
    try seed(gomoku, "gomoku_state__ok_before_forbidden_black")
    await gomoku.place(GomokuPoint(x: 7, y: 7)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 0)
    #expect(gomoku.notice == "3-3 금수라 둘 수 없어요")
    // ② 이 기기 판에서 (10,7) 흑돌이 빠져 앱은 둘 수 있다고 본다 → 서버 forbidden{reason:'double-three'}
    let (_, gomoku2, host2) = makeContractStore("forbidden2", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__forbidden_double_three")]
    ])
    try seed(gomoku2, "gomoku_state__ok_before_forbidden_black") { object in
        var match = object["match"] as? [String: Any] ?? [:]
        match.removeValue(forKey: "board")
        object["match"] = match
        object["moves"] = (object["moves"] as? [[String: Any]] ?? []).filter { ($0["seq"] as? Int) != 7 }
    }
    await gomoku2.place(GomokuPoint(x: 7, y: 7)!)
    #expect(GomokuStubProtocol.count(host: host2, rpc: "gomoku_move") == 1)
    #expect(lastBody(host2, "gomoku_move")["p_expected_seq"] as? Int == 8)
    #expect(gomoku2.notice == "3-3 금수라 둘 수 없어요")
    expectMatchEqualsServer(gomoku2, facts, clock: contractClock)
    #expect(gomoku2.match?.board[GomokuPoint(x: 10, y: 7)!] == .black)
    #expect(gomoku2.match?.board[GomokuPoint(x: 7, y: 7)!] == nil)
    #expect(GomokuStubProtocol.count(host: host2, rpc: "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_끝난_판에_둔_not_active_는_결과로_옮기고_since_9_로_다시_읽는다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_move__not_active")
    let (_, gomoku, host) = makeContractStore("not-active", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__not_active")],
        "gomoku_state": [try fixtureText("gomoku_state__finished_since9")]
    ])
    // 백의 한 기기가 count 8 에서 자기 차례로 알고 있다(흉내)
    try seed(gomoku, "flow_m1_k7_white_move") { object in
        var match = object["match"] as? [String: Any] ?? [:]
        match["turn"] = "white"
        object["match"] = match
    }
    #expect(gomoku.match?.moveCount == 8 && gomoku.match?.turn == .white)
    await gomoku.place(GomokuPoint(x: 5, y: 5)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 8)
    #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == 9)
    #expect(gomoku.notice == "이미 끝난 대국이에요")
    expectMatchEqualsServer(gomoku, try ServerFacts(fixture: "gomoku_state__finished_since9"), clock: contractClock,
                            lastMove: .some(GomokuPoint(x: 4, y: 0)))
    #expect(gomoku.match?.outcome == .lost && gomoku.match?.endReason == .five && gomoku.match?.rubyDelta == -5)
}

// MARK: - 6. 자동 착수 · 자리 비움 · 기권

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_auto_placed_는_진_것이_아니라_서버가_대신_놓은_것이다() async throws {
    // 0.3.27 의 gomoku_move__timeout 을 대신하는 자리다. 마감이 지나도 **판은 계속된다** —
    // 서버가 빈칸 하나에 대신 놓고 차례를 넘긴다. 여기서 결과 화면으로 넘어가면 사용자는 진 줄 안다.
    let facts = try ServerFacts(fixture: "gomoku_move__auto_placed")
    let object = try fixtureJSON("gomoku_move__auto_placed")
    let (_, gomoku, host) = makeContractStore("auto-placed", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__auto_placed")]
    ])
    // 이 기기는 아직 자동 착수 전(내 차례, 기록 1수)으로 알고 있다.
    try seed(gomoku, "gomoku_move__auto_placed") { object in
        var match = object["match"] as? [String: Any] ?? [:]
        match["move_count"] = 1
        match["turn"] = facts.myColor
        match.removeValue(forKey: "board")
        object["match"] = match
        object["moves"] = []
        object["my_auto_streak"] = 0
    }
    #expect(gomoku.match?.moveCount == 1 && gomoku.match?.turn?.rawValue == facts.myColor)

    await gomoku.place(GomokuPoint(x: 8, y: 8)!)

    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 1)
    #expect(object["auto_placed_count"] as? Int == 1, "픽스처: 한 수가 자동으로 놓였다")
    // ① 판은 끝나지 않았고 ② 내 돌이 아니라 **서버가 놓은 돌**이 하나 늘었고 ③ 차례가 상대에게 갔다
    #expect(gomoku.match?.isFinished == false && gomoku.phase == .playing, "자동 착수를 결과 화면으로 옮겼다")
    #expect(gomoku.match?.moveCount == facts.moveCount)
    #expect(gomoku.match?.board.serverString == facts.board)
    #expect(gomoku.match?.turn?.rawValue == facts.turn)
    #expect(gomoku.match?.outcome == nil && gomoku.match?.endReason == nil)
    #expect(gomoku.match?.lastMoveWasAuto == true, "자동으로 놓인 수가 회색 점으로 구분되지 않는다")
    #expect(gomoku.myAutoStreak == 1 && gomoku.autoStreakWarning == nil, "첫 번째부터 겁을 주지 않는다")
    #expect(gomoku.notice == GomokuNoticeText.autoPlaced)
    #expect(gomoku.notice != GomokuNoticeText.timedOut, "옛 시간 초과 문구가 남아 있다")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0, "상태를 함께 실어 줬는데 또 물었다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_상대_돌만_자동으로_놓이면_stale_로_판만_맞춘다() async throws {
    // 내 색이 colors 에 없으면 auto_placed 가 아니다 — 내 차례는 그대로이고 기록 수만 밀렸다.
    let facts = try ServerFacts(fixture: "gomoku_move__stale_opponent_auto")
    let (_, gomoku, host) = makeContractStore("stale-auto", me: facts.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__stale_opponent_auto")]
    ])
    try seed(gomoku, "gomoku_move__stale_opponent_auto") { object in
        var match = object["match"] as? [String: Any] ?? [:]
        match["move_count"] = 1
        match.removeValue(forKey: "board")
        object["match"] = match
        object["moves"] = []
        object["opponent_auto_streak"] = 0
    }
    await gomoku.place(GomokuPoint(x: 8, y: 8)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 1)
    #expect(gomoku.match?.moveCount == facts.moveCount)
    #expect(gomoku.match?.turn?.rawValue == facts.myColor, "상대가 자동으로 둬서 다시 내 차례다")
    #expect(gomoku.myAutoStreak == 0, "내가 놓친 게 아닌데 내 연속 횟수가 올랐다")
    #expect(gomoku.opponentAutoStreak == 1)
    #expect(gomoku.notice == nil, "stale 은 말없이 판만 맞춘다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_기권_ok_는_진_결과와_판돈만큼의_루비다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_resign__ok")
    let (_, gomoku, host) = makeContractStore("resign", me: facts.myID, queues: [
        "gomoku_resign": [try fixtureText("gomoku_resign__ok")]
    ])
    try seed(gomoku, "gomoku_state__ok_before_forbidden_black")
    await gomoku.resign()
    expectMatchEqualsServer(gomoku, facts, clock: contractClock, lastMove: .some(GomokuPoint(x: 0, y: 6)))
    #expect(gomoku.match?.outcome == .lost && gomoku.match?.endReason == .resign && gomoku.match?.rubyDelta == -3)
    #expect(gomoku.rubyBalance == 97)
    #expect(gomoku.notice == nil)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_자리_비움으로_끝난_판은_abandoned_이고_연속_횟수가_임계값이다() throws {
    // 0.3.27 의 gomoku_resign__timeout 을 대신하는 자리다. 이제 판을 끝내는 것은 시계가 아니라
    // **연속 3회 자동 착수**이고, 사유 어휘도 timeout 이 아니라 abandoned 다.
    let facts = try ServerFacts(fixture: "gomoku_state__abandoned")
    let object = try fixtureJSON("gomoku_state__abandoned")
    #expect(facts.endReason == "abandoned")
    #expect(facts.turn == nil && facts.deadlineMs == nil, "끝난 판인데 차례·마감이 남아 있다")

    let (_, gomoku, _) = makeContractStore("abandoned", me: facts.myID, queues: [:])
    try seed(gomoku, "gomoku_state__abandoned")
    expectMatchEqualsServer(gomoku, facts, clock: contractClock)
    #expect(gomoku.match?.endReason == .abandoned, "abandoned 가 모르는 사유로 접혔다")
    #expect(gomoku.match?.outcome == .lost && gomoku.match?.rubyDelta == -facts.stake)
    // 자리를 비운 쪽의 연속 횟수는 임계값 그대로다. 경고는 **한 번 남았을 때만** 뜨므로 여기선 안 뜬다.
    #expect(object["my_auto_streak"] as? Int == GomokuStore.autoPlaceLossStreak)
    #expect(gomoku.myAutoStreak == GomokuStore.autoPlaceLossStreak)
    #expect(gomoku.autoStreakWarning == nil, "이미 끝난 판에서 '한 번 더 놓치면 집니다'가 뜬다")
    // 자동으로 놓인 수와 사람이 둔 수가 한 기록에 섞여 온다.
    let moves = try #require(object["moves"] as? [[String: Any]])
    #expect(moves.contains { $0["auto"] as? Bool == true } && moves.contains { $0["auto"] as? Bool == false },
            "auto true/false 가 섞인 기록이 아니다")
}

// MARK: - 7. 흑 자동 패스 · 판 가득 무승부

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_백_착수_뒤_흑_패스와_마지막_칸_무승부를_백_시점으로_옮긴다() async throws {
    let passed = try ServerFacts(fixture: "gomoku_move__ok_black_passed")
    let draw = try ServerFacts(fixture: "gomoku_move__board_full_draw")
    let (store, gomoku, host) = makeContractStore("pass-white", me: passed.myID, queues: [
        "gomoku_move": [try fixtureText("gomoku_move__ok_black_passed"), try fixtureText("gomoku_move__board_full_draw")]
    ])
    try seed(gomoku, "gomoku_state__ok_before_pass_white")
    #expect(gomoku.match?.moveCount == 223 && gomoku.match?.turn == .white)

    await gomoku.place(GomokuPoint(x: 2, y: 0)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 223)
    expectMatchEqualsServer(gomoku, passed, clock: contractClock, lastMove: .some(GomokuPoint(x: 2, y: 0)), blackPassed: true)
    #expect(gomoku.match?.turn == .white && gomoku.match?.moveCount == 225)
    #expect(gomoku.notice == nil)

    await gomoku.place(GomokuPoint(x: 3, y: 2)!)
    #expect(lastBody(host, "gomoku_move")["p_expected_seq"] as? Int == 225)
    expectMatchEqualsServer(gomoku, draw, clock: contractClock, lastMove: .some(GomokuPoint(x: 3, y: 2)), blackPassed: false)
    #expect(gomoku.match?.outcome == .draw && gomoku.match?.endReason == .boardFull && gomoku.match?.rubyDelta == 0)
    #expect(gomoku.match?.board.stoneCount == 225)
    #expect(gomoku.rubyBalance == 100 && store.rubyBalance == 100)   // 무승부 환불
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_흑_시점의_패스는_since_223_과_since_0_둘_다_blackPassed_다() async throws {
    let facts = try ServerFacts(fixture: "gomoku_state__ok_pass_since223")
    let (_, gomoku, host) = makeContractStore("pass-black", me: facts.myID, queues: [
        "gomoku_state": [try fixtureText("gomoku_state__ok_pass_since223")]
    ])
    try seed(gomoku, "gomoku_state__ok_before_pass_black")
    await gomoku.refreshMatch()
    #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == 223)
    expectMatchEqualsServer(gomoku, facts, clock: contractClock, lastMove: .some(GomokuPoint(x: 2, y: 0)), blackPassed: true)
    await gomoku.place(GomokuPoint(x: 3, y: 2)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 0, "패스한 흑은 둘 수 없다")
    #expect(gomoku.notice == "상대 차례예요")

    let fresh = try ServerFacts(fixture: "gomoku_state__ok_pass_since0")
    let (_, gomoku2, host2) = makeContractStore("pass-black0", me: fresh.myID, queues: [
        "gomoku_state": [try fixtureText("gomoku_state__ok_pass_since0")]
    ])
    await gomoku2.refreshMatch(id: fresh.matchID)
    #expect(lastBody(host2, "gomoku_state")["p_since_seq"] as? Int == 0)
    expectMatchEqualsServer(gomoku2, fresh, clock: contractClock, lastMove: .some(GomokuPoint(x: 2, y: 0)), blackPassed: true)
}

// MARK: - 8. 상태 조회 since 중간값 · not_found

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_state_since_0_과_since_2_와_not_found() async throws {
    let full = try ServerFacts(fixture: "gomoku_state__ok_since0")
    let (_, gomoku, host) = makeContractStore("since0", me: full.myID, queues: [
        "gomoku_state": [try fixtureText("gomoku_state__ok_since0")]
    ])
    await gomoku.refreshMatch(id: full.matchID.uppercased())
    #expect(lastBody(host, "gomoku_state")["p_since_seq"] as? Int == 0)
    expectMatchEqualsServer(gomoku, full, clock: contractClock, lastMove: .some(GomokuPoint(x: 1, y: 1)), blackPassed: false)

    let mid = try ServerFacts(fixture: "gomoku_state__ok_since2")
    let (_, gomoku2, host2) = makeContractStore("since2", me: mid.myID, queues: [
        "gomoku_state": [try fixtureText("gomoku_state__ok_since2")]
    ])
    try seed(gomoku2, "gomoku_state__ok_white_since2_count2")
    await gomoku2.refreshMatch()
    #expect(lastBody(host2, "gomoku_state")["p_since_seq"] as? Int == 2)
    expectMatchEqualsServer(gomoku2, mid, clock: contractClock, lastMove: .some(GomokuPoint(x: 1, y: 1)))

    let (_, gomoku3, _) = makeContractStore("not-found", me: try contractUser("C"), queues: [
        "gomoku_state": [try fixtureText("gomoku_state__not_found")]
    ])
    try seed(gomoku3, "gomoku_state__ok_since0")
    await gomoku3.refreshMatch()
    #expect(gomoku3.match == nil)
    #expect(gomoku3.phase == .lobby)
}

// MARK: - 9. 로비 · 받은함

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_로비는_가능_불가_대국중_근무안함을_칩과_정렬로_옮긴다() async throws {
    let lobby = try fixtureJSON("gomoku_lobby__ok")
    let me = try #require(lobby["me"] as? [String: Any])
    let (store, gomoku, host) = makeContractStore("lobby", me: try callerOf("gomoku_lobby__ok"), queues: [
        "gomoku_lobby": [try fixtureText("gomoku_lobby__ok")]
    ])
    await gomoku.refreshLobby()
    let byID = Dictionary(uniqueKeysWithValues: gomoku.users.map { ($0.id, $0) })
    let b = try #require(byID[try contractUser("B")])
    let c = try #require(byID[try contractUser("C")])
    let d = try #require(byID[try contractUser("D")])
    let e = try #require(byID[try contractUser("E")])
    let f = try #require(byID[try contractUser("F")])
    #expect(gomoku.users.count == 5)
    #expect(b.isWorking && b.isCapable && !b.inMatch)
    #expect(b.characterID == "jellyfish" && b.avatarURL == "https://example.invalid/avatar-b.png" && b.displayName == "코덱스토큰도둑예은")
    #expect(c.inMatch && d.inMatch && c.isWorking && c.isCapable)
    #expect(f.isWorking && !f.isCapable, "build 76 은 업데이트 필요")
    #expect(!e.isWorking && e.isCapable, "근무 안 함")
    #expect(gomoku.users.map(\.id) == [b.id, d.id, c.id, f.id, e.id], "도전 가능 → 대국 중(이름순) → 불가 → 근무 안 함")
    #expect(gomoku.record == GomokuRecord(wins: me["wins"] as? Int ?? -1, losses: me["losses"] as? Int ?? -1, draws: me["draws"] as? Int ?? -1))
    #expect(gomoku.rubyBalance == me["ruby_balance"] as? Int && store.rubyBalance == me["ruby_balance"] as? Int)
    #expect(gomoku.turnSeconds == 30)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0, "진행 중 대국이 없으면 판을 읽지 않는다")

    // 대국 중인 사람의 로비는 active_match_id 로 그 판을 연다
    let (_, gomoku2, host2) = makeContractStore("lobby-active", me: try callerOf("gomoku_lobby__ok_in_match"), queues: [
        "gomoku_lobby": [try fixtureText("gomoku_lobby__ok_in_match")],
        "gomoku_state": [try fixtureText("flow_m1_challenger_state_since0")]
    ])
    await gomoku2.refreshLobby()
    await contractWait { gomoku2.match != nil }
    #expect(lastBody(host2, "gomoku_state")["p_since_seq"] as? Int == 0)
    expectMatchEqualsServer(gomoku2, try ServerFacts(fixture: "flow_m1_challenger_state_since0"), clock: contractClock)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_받은함은_받은_신청_둘과_보낸_신청과_만료를_서버시계로_옮긴다() async throws {
    let inbox = try fixtureJSON("gomoku_inbox__ok")
    let serverNow = try #require(number(inbox["server_now_ms"]))
    let incomingRows = try #require(inbox["incoming"] as? [[String: Any]])
    let outgoingRow = try #require(inbox["outgoing"] as? [String: Any])
    let (store, gomoku, host) = makeContractStore("inbox", me: try callerOf("gomoku_inbox__ok"), queues: [
        "gomoku_inbox": [try fixtureText("gomoku_inbox__ok")]
    ])
    final class Arrivals { var ids: [String] = [] }
    let arrivals = Arrivals()
    gomoku.onInviteArrived = { arrivals.ids.append($0.id) }
    await gomoku.loadInbox()

    #expect(gomoku.incoming.count == 2)
    for row in incomingRows {
        let id = try #require(row["match_id"] as? String)
        let invite = try #require(gomoku.incoming.first { $0.id == id })
        let challenger = try #require(row["challenger"] as? [String: Any])
        #expect(invite.peer.id == challenger["user_id"] as? String)
        #expect(invite.peer.displayName == challenger["display_name"] as? String)
        #expect(invite.stake == row["stake"] as? Int)
        let expires = try #require(number(row["invite_expires_ms"]))
        #expect(abs(invite.expiresAt.timeIntervalSince(contractClock.addingTimeInterval((expires - serverNow) / 1000))) < 0.002)
    }
    #expect(Set(gomoku.incoming.map(\.peer.id)) == [try contractUser("A"), try contractUser("F")])
    let sent = try #require(gomoku.outgoing)
    #expect(sent.id == outgoingRow["match_id"] as? String)
    #expect(sent.peer.id == (outgoingRow["opponent"] as? [String: Any])?["user_id"] as? String)
    #expect(sent.peer.displayName == "abto.app")
    #expect(sent.stake == 5)
    #expect(gomoku.bannerInvite?.id == incomingRows.first?["match_id"] as? String, "먼저 온(먼저 만료되는) 신청이 배너")
    #expect(arrivals.ids == incomingRows.compactMap { $0["match_id"] as? String })
    #expect(gomoku.rubyBalance == 100 && store.rubyBalance == 100)
    // 최근 끝난 판(last_finished)은 로컬 판이 없고 아직 보여 준 적 없는 id 라 결과 화면을 세우려고 **한 번** 읽는다
    // (2차 검증 set #4 결정). 이 테스트의 스텁은 gomoku_state 를 스크립트하지 않아 실패로 끝나고, 화면은 로비 그대로다.
    let lastFinished = try #require(inbox["last_finished"] as? [String: Any], "픽스처: 최근 끝난 판(무승부)이 실려 있다")
    let finishedID = try #require(lastFinished["match_id"] as? String)
    #expect(gomoku.match == nil && gomoku.phase == .lobby)
    let states = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state")
    #expect(states.count == 1, "최근 끝난 판의 결과를 읽지 않았다(또는 두 번 읽었다)")
    #expect((states.first?.json["p_match_id"] as? String)?.lowercased() == finishedID.lowercased())
    #expect(states.first?.json["p_since_seq"] as? Int == 0)
}

// MARK: - 10. 0.3.28 — 실제 출력이 앱 모델을 조용히 무너뜨릴 수 있는 자리들
//
// 아래 다섯은 "스텁으로는 절대 안 잡히는" 자리만 모았다. 전부 **실서버 출력에서 읽은 사실**이고,
// 하나라도 모델을 잘못 적으면 응답 **전체가 throw** 하거나(타입) 화면이 조용히 멈춘다(어휘·루프).

@Test(.gomokuDefaultsCleanup)
func 실서버_나가기의_chat_deleted_는_참거짓이_아니라_지운_개수다() throws {
    // JSON 에서 0 과 false 는 눈으로 구분되지 않는다. Bool 로 적었다면 4 에서, Int 로 적었다면 false 에서 throw 한다.
    for (name, expected) in [("gomoku_leave__ok_one", 0), ("gomoku_leave__ok_both", 4)] {
        let raw = try #require(try fixtureJSON(name)["chat_deleted"] as? NSNumber, "\(name): chat_deleted 가 없다")
        #expect(raw.objCType.pointee != CChar(UInt8(ascii: "c")), "\(name): chat_deleted 가 Bool 로 왔다")
        #expect(raw.intValue == expected, "\(name): chat_deleted \(raw.intValue)")
        // 앱 모델은 이 키를 **일부러 안 읽는다**(화면이 쓸 데가 없다). 그래도 응답 전체는 읽혀야 한다.
        let response = try contractDecoder().decode(GomokuLeaveResponse.self, from: try fixtureData(name))
        #expect(response.status == .ok, "\(name)")
        #expect(response.bothLeft == (expected > 0), "\(name): both_left")
    }
    // 아직 안 끝난 판의 거절 어휘. .unknown 으로 접히면 나가기 실패가 '모르는 status' 로 기록되고 원인이 안 보인다.
    let refused = try contractDecoder().decode(
        GomokuLeaveResponse.self, from: try fixtureData("gomoku_leave__not_finished"))
    #expect(refused.status == .notFinished, "not_finished 가 '\(refused.status.rawValue)' 로 접혔다")
    #expect(refused.matchStatus == "active")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실서버_음소거_응답의_번호_구멍은_정상이고_전체_재요청_루프를_만들지_않는다() async throws {
    // 내가 껐으면 **서버가** 상대 줄을 빼고 준다 → chat[] 의 번호가 뛴다. 그런데 chat_seq 는 안 뛴다.
    // 앱이 이 어긋남을 '구멍'으로 읽으면 since 0 으로 전체를 다시 받고, 그 응답도 똑같이 어긋나 무한 반복이 된다.
    let object = try fixtureJSON("gomoku_state__ok_chat_my_muted")
    let seqs = try #require(object["chat"] as? [[String: Any]]).compactMap { $0["seq"] as? Int }
    let chatSeq = try #require(object["chat_seq"] as? Int)
    #expect(object["my_muted"] as? Bool == true)
    #expect(seqs == [1, 3], "음소거로 상대 줄이 빠진 모양이 아니다: \(seqs)")
    #expect(chatSeq == 4 && chatSeq > (seqs.last ?? 0),
            "chat_seq(\(chatSeq))와 마지막 줄(\(seqs.last ?? 0))이 어긋나야 이 테스트가 뜻을 갖는다")

    let facts = try ServerFacts(fixture: "gomoku_state__ok_chat_my_muted")
    let (_, gomoku, host) = makeContractStore("muted-gap", me: facts.myID, queues: [
        "gomoku_state": [try fixtureText("gomoku_state__ok_chat_my_muted")]
    ])
    try seed(gomoku, "gomoku_state__ok_chat_my_muted")
    #expect(gomoku.isMuted)
    #expect(gomoku.chat.map(\.seq) == seqs, "가려진 번호를 구멍으로 보고 줄을 버렸다")
    #expect(gomoku.chatSeq == chatSeq, "다음 since 는 마지막 줄이 아니라 서버 발급 번호다")

    await gomoku.refreshMatch()

    #expect(lastBody(host, "gomoku_state")["p_since_chat_seq"] as? Int == chatSeq,
            "가려진 구간을 0 부터 다시 물으면 매번 전체를 받는다")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1,
            "음소거로 빠진 번호를 구멍으로 읽어 전체 재요청 루프에 빠졌다")
    #expect(gomoku.chat.map(\.seq) == seqs && gomoku.chatSeq == chatSeq, "두 번째 응답이 대화를 흔들었다")
}

@Test(.gomokuDefaultsCleanup)
func 실서버_not_found_응답은_키가_status_하나뿐이다() throws {
    // 여기엔 server_now_ms 조차 없다 — 이 응답으로 시계 보정이나 잔액 갱신을 하려 들면 그 경로가 조용히 죽는다.
    for name in ["gomoku_chat_send__not_found", "gomoku_state__not_found"] {
        let object = try fixtureJSON(name)
        #expect(Array(object.keys) == ["status"], "\(name): 키가 \(object.keys.sorted())")
        #expect(object["status"] as? String == "not_found", "\(name)")
    }
    let chat = try contractDecoder().decode(
        GomokuChatResponse.self, from: try fixtureData("gomoku_chat_send__not_found"))
    #expect(chat.status == .notFound && chat.serverNowMs == nil && chat.chatSeq == nil)
    let state = try contractDecoder().decode(
        GomokuStateResponse.self, from: try fixtureData("gomoku_state__not_found"))
    #expect(state.status == .notFound && state.state.match == nil)
}

@Test(.gomokuDefaultsCleanup)
func 실서버_시각은_13자리_epoch_밀리초라_32비트로는_넘친다() throws {
    let object = try fixtureJSON("gomoku_state__ok_since0")
    let now = try #require(number(object["server_now_ms"]))
    #expect(now > 1_000_000_000_000, "epoch 밀리초가 아니다: \(now)")
    #expect(Int32(exactly: now) == nil, "32비트에 들어가는 값이라 이 픽스처로는 넘침을 못 잡는다")
    // 앱 모델이 Double 로 받는 이유가 여기다(정수로 오든 소수로 오든 한 번에, 그리고 32비트 넘침이 없다).
    let decoded = try contractDecoder().decode(
        GomokuStateResponse.self, from: try fixtureData("gomoku_state__ok_since0"))
    #expect(decoded.state.serverNowMs == now)
    let deadline = try #require(decoded.state.match?.deadlineMs)
    #expect(deadline > 1_000_000_000_000)
    #expect(Double(Int64(now)) == now, "밀리초가 Double 의 정확 정수 범위를 벗어났다")
}

@Test(.gomokuDefaultsCleanup)
func 실서버_패스_수는_x_y_가_null_이고_자동_표시가_붙는다() throws {
    // 앱이 실제로 만나는 경로다: 흑이 둘 곳이 하나도 없으면 서버가 좌표 없는 pass 행을 적는다.
    // x·y 를 Int(non-optional)로 받으면 이 행 하나에서 **응답 전체가** throw 한다.
    for name in ["gomoku_state__ok_pass_since0", "gomoku_state__ok_pass_since223", "gomoku_move__ok_black_passed"] {
        let rows = try #require(try fixtureJSON(name)["moves"] as? [[String: Any]])
        let pass = try #require(rows.first { $0["kind"] as? String == "pass" }, "\(name): 패스 수가 없다")
        #expect(pass["x"] is NSNull && pass["y"] is NSNull, "\(name): 패스인데 좌표가 실려 있다")
        #expect(pass["auto"] as? Bool == true, "\(name): 0.3.28 서버는 규칙 패스도 auto 로 적는다")
        let decoded = try contractDecoder().decode(GomokuStatePayload.self, from: try fixtureData(name))
        let row = try #require(decoded.moves?.first { $0.kind == "pass" }, "\(name): 디코드된 패스 수가 없다")
        #expect(row.x == nil && row.y == nil, "\(name): 좌표가 Optional 이 아니면 여기서 throw 한다")
        #expect(row.auto == true, "\(name)")
        #expect(row.seq == 225, "\(name)")
    }
}
