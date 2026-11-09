import Foundation
import Testing
@testable import CheckCore

// 1:1 알까기 v2 코어(C1 뼈대) — 와이어 · 스토어 표면 · 문구 표(SPEC v1.1 §3.7 · §4.1~4.4). **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁 `AlkkagiServing`(호출을 기록하고 정해 둔 응답을 돌려준다 — host 가 없어 네트워크 0). 응답 JSON 은 SPEC §3.7 모양을 손으로 적은
// 픽스처다 — S 하네스 원문(`T/Fixtures/alkkagi-rpc`)이 오면 계약 시험(V03xxAlkkagiFixtureContractTests)이 원문으로 다시 잰다.
// 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"이고, 단언마다 결함 변이에서 갈리는 기준선 짝을 둔다.

// MARK: - 시험대

@MainActor
private final class AKStubService: AlkkagiServing {
    var calls: [AlkkagiCall] = []
    var handler: (AlkkagiCall) throws -> AlkkagiResponse

    init(_ handler: @escaping (AlkkagiCall) throws -> AlkkagiResponse) { self.handler = handler }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        calls.append(call)
        return try handler(call)
    }
}

private let akNow: Double = 1_800_000_000_000
private let akMe = "00000000-0000-4000-8000-000000000001"
private let akMinsu = "00000000-0000-4000-8000-000000000002"
private let akJiwoo = "00000000-0000-4000-8000-000000000003"
private let akMatch = "00000000-0000-4000-8000-0000000000aa"

private func akDecode(_ object: [String: Any], snake: Bool = false) throws -> AlkkagiResponse {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let decoder = JSONDecoder()
    if snake { decoder.keyDecodingStrategy = .convertFromSnakeCase }
    return try decoder.decode(AlkkagiResponse.self, from: data)
}

private func akPeer(_ id: String, _ name: String) -> [String: Any] {
    ["id": id, "display_name": name, "avatar_url": NSNull(), "character_id": "aing", "busy": false]
}

private func akUser(_ id: String, _ name: String, working: Bool = false, inMatch: Bool = false,
                    capable: Bool = true, focus: Bool = false) -> [String: Any] {
    ["id": id, "display_name": name, "avatar_url": NSNull(), "character_id": "aing",
     "is_working": working, "in_match": inMatch, "capable": capable, "focus_mode": focus]
}

/// SPEC §3.7 LOBBY(전체 로비). `light` 면 가벼운 로비(users [] · record null · matches []).
private func akLobby(light: Bool = false, doorOpen: Bool = true, ruby: Int = 100,
                     protocolVersion: Int = 2, users: [[String: Any]]? = nil) -> [String: Any] {
    [
        "status": "ok", "protocol": protocolVersion, "server_now_ms": akNow,
        "me": akPeer(akMe, "나"), "state": NSNull(),
        "incoming": [["id": akMatch, "opponent": akPeer(akMinsu, "민수"), "stake": 5, "expires_at_ms": akNow + 60_000]],
        "outgoing": NSNull(), "ruby_balance": ruby, "stakes": [3, 5, 10], "door_open": doorOpen,
        "record": light ? NSNull() : ["wins": 3, "losses": 1, "draws": 2] as [String: Any],
        "users": light ? [] : (users ?? [akUser(akMinsu, "민수", working: true), akUser(akJiwoo, "지우", inMatch: true)]),
        "matches": light ? [] : [["id": "00000000-0000-4000-8000-0000000000bb", "black": akPeer(akJiwoo, "지우"),
                                  "white": akPeer(akMinsu, "민수"), "stake": 10, "shot_count": 4, "watchers": 2,
                                  "accepted_at_ms": akNow - 90_000]],
    ]
}

private func akStone(_ id: Int, _ owner: String, _ x: Double, _ y: Double) -> [String: Any] {
    ["id": id, "owner": owner, "position": ["x": x, "y": y], "velocity": ["x": 0, "y": 0], "is_out": false, "is_placed": true]
}

/// SPEC §3.7 STATE(28키 — v1 19키 + v2 덧붙임). 조준 · 흑 차례 · 나는 흑.
private func akState(phase: String = "aiming", result: Any = NSNull(), reason: Any = NSNull(),
                     myColor: String = "black", stake: Any = 5, myMissed: Int = 0, watchers: Int = 2) -> [String: Any] {
    let stones = (0..<5).map { akStone($0, "black", -0.4 + Double($0) * 0.2, 0.6) }
        + (5..<10).map { akStone($0, "white", -0.4 + Double($0 - 5) * 0.2, -0.6) }
    return [
        "id": akMatch, "revision": 7, "phase": phase, "current_player": "black", "my_color": myColor,
        "black": akPeer(akMe, "나"), "white": akPeer(akMinsu, "민수"), "stones": stones,
        "deadline_ms": akNow + 30_000, "shot_count": 3, "result": result, "finish_reason": reason, "shot": NSNull(),
        "chat_seq": 0, "chat": [], "muted": false, "placement_revision": 1, "my_ready": true, "opponent_ready": true,
        "stake": stake, "accepted_at_ms": akNow - 60_000, "my_missed_turns": myMissed, "opponent_missed_turns": 0,
        "forfeit_after": 3, "settled": phase == "finished", "ruby_balance": 95, "watchers": watchers, "grace_ms": 2000,
    ]
}

// MARK: - 시험

@MainActor
@Suite
struct V03xxAlkkagiStoreTests {
    // MARK: 와이어

    /// 없으면: 앱이 계속 protocol 1 로 부르거나 판돈을 싣지 않아도 초록이다(서버 v2 는 둘 다 `unsupported_client` · `invalid`).
    @Test
    func requestBodiesCarryProtocolTwoAndTheStake() throws {
        let opponent = try #require(UUID(uuidString: akMinsu))
        func keys(_ call: AlkkagiCall) throws -> [String: Any] {
            let data = try JSONEncoder().encode(call.parameters)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let challenge = try keys(.challenge(opponentID: opponent, stake: 5, actionID: UUID()))
        #expect(challenge["p_protocol"] as? Int == 2)
        #expect(challenge["p_stake"] as? Int == 5)
        #expect(Set(challenge.keys) == ["p_protocol", "p_opponent", "p_action_id", "p_stake"])
        // 기준선: 로비 · 순위 본문에는 판돈이 없다(키가 새면 서버 이름 인자 호출이 PGRST202).
        #expect(Set(try keys(.lobby(users: false)).keys) == ["p_protocol", "p_users"])
        #expect(Set(try keys(.ranking).keys) == ["p_protocol"])
        #expect(Set(try keys(.watchLive(matchID: opponent)).keys) == ["p_protocol", "p_match_id"])

        // RPC 15 — 새 셋이 이름표에 있다.
        #expect(AlkkagiOnlineWire.RPC.all.count == 15 && Set(AlkkagiOnlineWire.RPC.all).count == 15)
        #expect(AlkkagiCall.ranking.rpcName == "alkkagi_ranking")
        #expect(AlkkagiCall.watch(matchID: nil).rpcName == "alkkagi_watch")
        #expect(AlkkagiCall.watchLive(matchID: nil).rpcName == "alkkagi_watch_live")
        // 서버 어휘 넷이 열거로 산다 · 모르는 값은 unknown(기준선).
        for raw in ["blackout", "target_focused", "target_outdated", "insufficient"] {
            #expect(AlkkagiRPCStatus(rawValue: raw) != nil, "\(raw) 가 열거에 없다")
        }
        #expect(AlkkagiRPCStatus(rawValue: "muted") == nil, "서버가 안 내는 muted 가 남았다")
    }

    /// 없으면: v2 로비 키(사람 상태 · 전적 · 대결 중 · 문 · 잔액)를 디코더가 버려도 초록이다 — 두 디코더(원문 · snake 접기) 모두.
    @Test(arguments: [false, true])
    func lobbyV2KeysSurviveDecoding(snake: Bool) throws {
        let full = try akDecode(akLobby(), snake: snake)
        #expect(full.protocolVersion == 2 && full.doorOpen == true && full.rubyBalance == 100 && full.stakes == [3, 5, 10])
        #expect(full.record == AlkkagiRecord(wins: 3, losses: 1, draws: 2))
        let users = try #require(full.users)
        #expect(users.map(\.displayName) == ["민수", "지우"])
        #expect(users[0].isWorking && users[0].canBeChallenged)
        #expect(users[1].inMatch && !users[1].canBeChallenged)
        #expect(full.incoming?.first?.stake == 5)
        let live = try #require(full.matches?.first)
        #expect(live.stake == 10 && live.watchers == 2 && live.shotCount == 4 && live.acceptedAt != nil)
        // 기준선: 가벼운 로비는 record 가 nil(0 이 아니다) · 사람 0.
        let light = try akDecode(akLobby(light: true), snake: snake)
        #expect(light.record == nil && light.users?.isEmpty == true && light.matches?.isEmpty == true)
    }

    /// 없으면: WATCH(내 색 없음)를 STATE 로 읽다 디코딩이 통째 실패하거나, RANKING 의 `me`(순위 줄)를 PEER 로 읽어 실패해도 초록이다.
    /// 돌(`AlkkagiGame.Stone`)은 판 진행 타입이라(§4.6 경계) 운영 디코더(snake 접기)로만 읽힌다 — 판이 실린 응답은 그 디코더로 잰다.
    @Test(arguments: [false, true])
    func oneEnvelopeRoutesStateWatchAndRanking(snake rankingSnake: Bool) throws {
        let snake = true
        let mine = try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow, "state": akState()], snake: snake)
        let state = try #require(mine.state)
        #expect(mine.watch == nil)
        #expect(state.stake == 5 && state.watchers == 2 && state.graceMs == 2000 && state.forfeitAfter == 3)
        #expect(state.rubyBalance == 95 && state.myMissedTurns == 0 && state.settled == false)

        var watch = akState()
        for key in ["my_color", "chat_seq", "chat", "muted", "placement_revision", "my_ready", "opponent_ready",
                    "my_missed_turns", "opponent_missed_turns", "ruby_balance", "grace_ms", "settled", "accepted_at_ms"] {
            watch.removeValue(forKey: key)
        }
        watch["black_ready"] = true
        watch["white_ready"] = false
        watch["stones"] = []
        watch["black_missed_turns"] = 1
        watch["white_missed_turns"] = 0
        watch["finished_at_ms"] = NSNull()
        let watched = try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow, "state": watch], snake: snake)
        let spectated = try #require(watched.watch)
        #expect(watched.state == nil)
        #expect(spectated.stones.isEmpty && spectated.blackReady && !spectated.whiteReady && spectated.watchers == 2)
        #expect(spectated.blackMissedTurns == 1 && spectated.stake == 5)

        let ranking = try akDecode([
            "status": "ok", "server_now_ms": akNow, "record_since_ms": NSNull(),
            "me": ["rank": NSNull(), "wins": 0, "losses": 0, "draws": 0, "points": 0],
            "rows": [["rank": 1, "id": akMinsu.uppercased(), "display_name": "민수", "avatar_url": NSNull(),
                      "character_id": "aing", "wins": 4, "losses": 1, "draws": 0, "points": 3],
                     ["rank": 2, "display_name": "id 없는 줄"]],
        ], snake: rankingSnake)
        let board = try #require(ranking.ranking)
        #expect(ranking.me == nil, "순위 me 가 PEER 자리로 샜다")
        #expect(board.entries.map(\.id) == [akMinsu], "깨진 줄을 버리지 않았거나 id 를 소문자로 접지 않았다")
        #expect(board.entries.first?.points == 3 && board.me?.rank == nil && board.recordSince == nil)
        // 기준선: 로비는 순위가 아니다.
        #expect(try akDecode(akLobby(), snake: rankingSnake).ranking == nil)
    }

    // MARK: 스토어

    /// 없으면(VC-8): 서버 옛판 · 함수 없음 · 문 닫힘이 모두 "업데이트"로 보여도, 또는 그 반대여도 초록이다 — 여섯 갈래 접기.
    @Test
    func availabilityFoldsSixWays() async throws {
        func fold(_ make: @escaping () throws -> AlkkagiResponse) async -> AlkkagiAvailability {
            let store = AlkkagiOnlineStore(service: AKStubService { _ in try make() })
            await store.refreshLobby()
            return store.availability
        }
        #expect(await fold { try akDecode(akLobby(protocolVersion: 1)) } == .serverMissing)          // ① 서버 옛판
        #expect(await fold { throw AlkkagiServiceError.serverMissing } == .serverMissing)            // ② PGRST202
        #expect(await fold { try akDecode(akLobby(doorOpen: false)) } == .serverMissing)            // ③ 문 닫힘
        #expect(await fold { AlkkagiResponse(status: .unsupportedClient, serverNowMs: akNow, doorOpen: false) }
                == .serverMissing)                                                                   // ④
        #expect(await fold { AlkkagiResponse(status: .unsupportedClient, serverNowMs: akNow, doorOpen: true) }
                == .updateRequired)                                                                  // ⑤ 내 build 모자람
        #expect(await fold { try akDecode(akLobby()) } == .available)                               // ⑥
    }

    /// 없으면: 팝오버의 가벼운 로비(users [] · record null)가 창 로비의 사람 · 전적 · 대결 중을 지워도 초록이다.
    @Test
    func lightLobbyDoesNotOverwriteUsersRecordOrLiveMatches() async throws {
        var light = false
        var emptyFull = false
        let store = AlkkagiOnlineStore(service: AKStubService { call in
            if case .lobby(false) = call { return try akDecode(akLobby(light: true)) }
            #expect(!light, "가벼운 로비를 부르려 했는데 전체 로비가 나갔다")
            return try akDecode(akLobby(users: emptyFull ? [] : nil))
        })
        await store.refreshLobby()
        #expect(store.users.count == 2 && store.record != nil && store.liveMatches.count == 1 && store.hasLoadedLobby)
        #expect(store.rubyBalance == 100)

        light = true
        store.handleSignal()                       // 창이 안 보이면 신호는 가벼운 로비(p_users false)를 부른다
        await store.refreshMatch()
        #expect(store.users.count == 2, "가벼운 로비가 사람 목록을 지웠다")
        #expect(store.record == AlkkagiRecord(wins: 3, losses: 1, draws: 2), "가벼운 로비가 전적을 지웠다")
        #expect(store.liveMatches.count == 1)

        // 기준선: **전체** 로비가 빈 사람을 주면 지운다(덮지 않는 규칙이 가벼운 로비에만 걸린다).
        light = false
        emptyFull = true
        await store.refreshLobby()
        #expect(store.users.isEmpty)
    }

    /// 없으면(VC-5): 정산 뒤 늦게 닿은 옛 응답(서버 시각이 앞섬)이 잔액을 되감아도 초록이다.
    @Test
    func lateRubyResponsesDoNotRewindTheBalance() {
        let store = AlkkagiOnlineStore()
        store.applyRuby(105, serverNowMs: 2_000)
        store.applyRuby(95, serverNowMs: 1_000)
        #expect(store.rubyBalance == 105, "먼저 만든 응답의 95 가 105 를 되감았다")
        // 기준선: 서버 시각이 없는 응답은 그대로 옮긴다 · 더 늦은 응답도 옮긴다.
        store.applyRuby(90, serverNowMs: 3_000)
        #expect(store.rubyBalance == 90)
        store.applyRuby(80, serverNowMs: nil)
        #expect(store.rubyBalance == 80)
    }

    /// 없으면: 결과 카드의 승패 · 루비 줄이 내 색을 안 보고 서버 result 만 읽어도(흑이 이기면 늘 승) 초록이다.
    @Test
    func outcomeAndRubyDeltaAreFromMyPointOfView() throws {
        func scene(result: String, reason: String, myColor: String, stake: Any = 5) throws -> AlkkagiOnlineStore {
            let store = AlkkagiOnlineStore()
            store.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                     "state": akState(phase: "finished", result: result, reason: reason,
                                                                      myColor: myColor, stake: stake)], snake: true).state)
            return store
        }
        let win = try scene(result: "black", reason: "ring_out", myColor: "black")
        #expect(win.outcome == .win && win.rubyDelta == DuelFee.winnerNet(stake: 5) && win.endReason == .ringOut)
        let loss = try scene(result: "black", reason: "ring_out", myColor: "white")
        #expect(loss.outcome == .loss && loss.rubyDelta == -5)                     // 기준선: 같은 판, 색만 다름
        let voided = try scene(result: "draw", reason: "void", myColor: "white")
        #expect(voided.outcome == .draw && voided.rubyDelta == 0 && voided.endReason == .void)
        let legacy = try scene(result: "white", reason: "timeout", myColor: "white", stake: NSNull())
        #expect(legacy.outcome == .win && legacy.rubyDelta == nil, "옛 판(판돈 없음)에 루비 줄이 섰다")
        #expect(try scene(result: "black", reason: "rollback", myColor: "black").endReason == .unknown)
        // 진행 판은 결과가 없다 · 관전자 수 칩은 STATE watchers 를 따른다(판이 없으면 0, VC-6).
        let live = AlkkagiOnlineStore()
        #expect(live.spectatorCount == 0)
        live.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                "state": akState(myMissed: 1, watchers: 2)], snake: true).state)
        #expect(live.outcome == nil && live.rubyDelta == nil && live.spectatorCount == 2 && live.defersMegaphoneBanner)
        #expect(live.missedTurnWarning?.mine == 1 && live.missedTurnWarning?.forfeitAfter == 3)
        live.state = nil
        #expect(live.spectatorCount == 0 && !live.defersMegaphoneBanner && live.missedTurnWarning == nil)
    }

    /// 없으면: 로비 순서가 서버 순서 그대로이거나, 차단한 사람 · 지금 내 판과 같은 신청이 목록 · 배너에 남아도 초록이다.
    @Test
    func visibleListsSortAndFilter() throws {
        let store = AlkkagiOnlineStore()
        store.users = [
            AlkkagiLobbyUser(id: "e", displayName: "구버전", isCapable: false),
            AlkkagiLobbyUser(id: "d", displayName: "대결중", inMatch: true),
            AlkkagiLobbyUser(id: "c", displayName: "하늘", isWorking: false),
            AlkkagiLobbyUser(id: "b", displayName: "가람", isWorking: false),
            AlkkagiLobbyUser(id: "a", displayName: "근무", isWorking: true),
            AlkkagiLobbyUser(id: "f", displayName: "집중", isWorking: true, isFocused: true),
        ]
        #expect(store.visibleUsers.map(\.id) == ["a", "b", "c", "d", "e", "f"])
        store.hiddenPeerIDs = ["B"]                                        // 대소문자 무시
        #expect(store.visibleUsers.map(\.id) == ["a", "c", "d", "e", "f"])

        let peer = AlkkagiPeer(id: "x", displayName: "엑스")
        store.incoming = [AlkkagiInvite(id: akMatch.uppercased(), opponent: peer, expiresAtMs: akNow + 60_000, stake: 5),
                          AlkkagiInvite(id: "other", opponent: peer, expiresAtMs: akNow + 60_000, stake: 3)]
        #expect(store.visibleIncoming?.stake == 5)                          // 기준선: 판이 없으면 첫 신청
        store.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                 "state": akState()], snake: true).state)
        #expect(store.visibleIncomingInvites.map(\.id) == ["other"], "지금 내 판과 같은 신청이 남았다")
    }

    /// 없으면(VC-17): 문구가 길건너 출처에서 갈라져도 초록이다 — 공유 status 는 게임 이름만 다르고, 다른 곳은 SPEC §4.4 표가 정한 곳뿐.
    @Test
    func noticeTextIsCrossyTextWithTheGameNameSwapped() {
        func crossy(_ s: AlkkagiRPCStatus) -> CrossyDuelRPCStatus? { CrossyDuelRPCStatus(rawValue: s.rawValue) }
        func swap(_ text: String?) -> String? { text?.replacingOccurrences(of: "1:1 알까기", with: "1:1 길건너") }
        let all: [AlkkagiRPCStatus] = [.ok, .stale, .invalid, .busy, .expired, .forbidden, .blackout, .insufficient,
                                       .notSignedIn, .unsupportedClient, .notFound, .notPending, .notActive,
                                       .alreadyPending, .targetBusy, .targetFocused, .targetOutdated, .rateLimited, .unknown]
        // SPEC §4.4 표가 길건너와 다르게 정한 곳(알까기만 있는 forbidden · rate_limited 는 길건너에 없어 비교하지 않는다).
        let cancelOwn: Set<AlkkagiRPCStatus> = [.stale]
        let respondOwn: Set<AlkkagiRPCStatus> = [.targetOutdated]
        var compared = 0
        for status in all {
            guard let other = crossy(status) else { continue }
            compared += 1
            #expect(swap(AlkkagiNoticeText.challenge(status, need: 5, have: 2)) == CrossyDuelNoticeText.challenge(other, need: 5, have: 2),
                    "challenge \(status.rawValue)")
            if !cancelOwn.contains(status) {
                #expect(swap(AlkkagiNoticeText.cancel(status)) == CrossyDuelNoticeText.cancel(other), "cancel \(status.rawValue)")
            }
            for accept in [true, false] where !respondOwn.contains(status) {
                #expect(swap(AlkkagiNoticeText.respond(accept: accept, status, side: "challenger"))
                        == CrossyDuelNoticeText.respond(accept: accept, other, side: "challenger"), "respond \(status.rawValue)")
            }
            #expect(swap(AlkkagiNoticeText.resign(status)) == CrossyDuelNoticeText.resign(other), "resign \(status.rawValue)")
        }
        #expect(compared == 17)
        // 표가 정한 차이 — 기준선 짝(길건너 글자와 갈린다).
        #expect(AlkkagiNoticeText.cancel(.stale) == AlkkagiNoticeText.finishedInvite)
        #expect(CrossyDuelNoticeText.cancel(.stale) == CrossyDuelNoticeText.tryAgain)
        #expect(AlkkagiNoticeText.respond(accept: true, .targetOutdated) == "상대 앱이 1:1 알까기를 아직 몰라요")
        #expect(AlkkagiNoticeText.cancel(.forbidden) == AlkkagiNoticeText.finishedInvite)
        #expect(AlkkagiNoticeText.respond(accept: true, .forbidden) == "받을 수 없는 신청이에요")
        #expect(AlkkagiNoticeText.move(.forbidden) == "상대 차례예요" && AlkkagiNoticeText.move(.stale) == nil)
        // 문 닫힘이면 '곧 열려요', 열렸는데 내 build 가 모자라면 '업데이트'(VC-8).
        #expect(AlkkagiNoticeText.challenge(.unsupportedClient, doorOpen: false) == "1:1 알까기는 곧 열려요")
        #expect(AlkkagiNoticeText.challenge(.unsupportedClient, doorOpen: true) == AlkkagiNoticeText.updateMine)
        // 끝 사유 · 놓친 차례(§4.4).
        #expect(AlkkagiNoticeText.endReason(.ringOut, outcome: .draw) == "마지막 돌이 함께 나가 무승부예요")
        #expect(AlkkagiNoticeText.endReason(.timeout, outcome: .loss) == "차례를 세 번 넘겨 졌어요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 1, forfeitAfter: 3) == "시간이 지나 차례가 넘어갔어요 · 두 번 더 넘기면 져요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 2, forfeitAfter: 3) == "시간이 지나 차례가 넘어갔어요 · 한 번 더 넘기면 져요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 0, forfeitAfter: 3) == nil)
        // 화면 낱말: '대전'·'초대'·'참가비'·'💎' 0.
        let words = [AlkkagiNoticeText.gameName, AlkkagiNoticeText.updateMine, AlkkagiNoticeText.unavailable,
                     AlkkagiNoticeText.finishedMatch, AlkkagiNoticeText.resignWarning]
            + all.map { AlkkagiNoticeText.challenge($0) } + all.compactMap { AlkkagiNoticeText.respond(accept: false, $0) }
        for banned in ["대전", "초대", "참가비", "💎"] {
            #expect(!words.contains { $0.contains(banned) }, "'\(banned)' 이 문구에 있다")
        }
    }
}
