import Testing
import Foundation
@testable import AlkkagiCore
@testable import AlkkagiPlayground

@Suite("Alkkagi online", .serialized)
@MainActor
struct AlkkagiOnlineTests {
    @Test func callsEncodeTheRPCContractAndKeepTheirActionNonce() throws {
        let matchID = OnlineFixture.matchID
        let opponentID = OnlineFixture.whiteID
        let nonce = UUID(uuidString: "ABCDEF01-2345-4678-9ABC-DEF012345678")!
        let match = matchID.uuidString
        let action = nonce.uuidString
        let cases: [(AlkkagiCall, String, [String: Any])] = [
            (.lobby(users: false), "alkkagi_lobby", ["p_users": false]),
            (.challenge(opponentID: opponentID, actionID: nonce), "alkkagi_challenge",
             ["p_opponent": opponentID.uuidString, "p_action_id": action]),
            (.cancel(matchID: matchID, actionID: nonce), "alkkagi_cancel",
             ["p_match_id": match, "p_action_id": action]),
            (.respond(matchID: matchID, accept: false, actionID: nonce), "alkkagi_respond",
             ["p_match_id": match, "p_accept": false, "p_action_id": action]),
            (.state(matchID: matchID, sinceChatSeq: 41), "alkkagi_state",
             ["p_match_id": match, "p_since_chat_seq": 41]),
            (.place(matchID: matchID, expectedPlacementRevision: 7, stoneID: 2,
                    position: OnlineFixture.vector(120, 420), actionID: nonce), "alkkagi_place",
             ["p_match_id": match, "p_expected_placement_revision": 7, "p_stone_id": 2,
              "p_x": 120, "p_y": 420, "p_action_id": action]),
            (.ready(matchID: matchID, expectedPlacementRevision: 7, actionID: nonce), "alkkagi_ready",
             ["p_match_id": match, "p_expected_placement_revision": 7, "p_action_id": action]),
            (.shoot(matchID: matchID, expectedRevision: 8, stoneID: 5,
                    pull: OnlineFixture.vector(-12, 75), actionID: nonce), "alkkagi_shoot",
             ["p_match_id": match, "p_expected_revision": 8, "p_stone_id": 5,
              "p_pull_x": -12, "p_pull_y": 75, "p_action_id": action]),
            (.resign(matchID: matchID, expectedRevision: 9, actionID: nonce), "alkkagi_resign",
             ["p_match_id": match, "p_expected_revision": 9, "p_action_id": action]),
            (.chatSend(matchID: matchID, body: "안녕 👋", actionID: nonce), "alkkagi_chat_send",
             ["p_match_id": match, "p_body": "안녕 👋", "p_action_id": action]),
            (.chatMute(matchID: matchID, muted: true, actionID: nonce), "alkkagi_chat_mute",
             ["p_match_id": match, "p_muted": true, "p_action_id": action]),
            (.leave(matchID: matchID, expectedRevision: 10, actionID: nonce), "alkkagi_leave",
             ["p_match_id": match, "p_expected_revision": 10, "p_action_id": action])
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (call, rpc, fields) in cases {
            var expected = fields
            expected["p_protocol"] = 1
            let encoded = try encoder.encode(call.parameters)
            let actual = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(call.rpcName == rpc)
            #expect(NSDictionary(dictionary: actual).isEqual(to: expected), "\(rpc): exact RPC keys and values")
            #expect(try encoder.encode(call.parameters) == encoded, "Re-encoding a retry keeps its nonce")
        }
    }

    @Test func nestedWirePayloadDecodesWithBothProductionDecoderStrategies() throws {
        for convertSnakeCase in [false, true] {
            let decoder = JSONDecoder()
            if convertSnakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
            let response = try decoder.decode(AlkkagiResponse.self, from: Data(OnlineFixture.wireJSON.utf8))
            #expect(response.status == .ok && response.protocolVersion == 1)
            #expect(response.serverNowMs == OnlineFixture.nowMs)
            #expect(response.me?.displayName == "Black")
            #expect(response.me?.avatarURL == "https://example.invalid/avatar.png")
            #expect(response.users?.first?.characterID == "turtle")
            #expect(response.incoming?.first?.expiresAtMs == OnlineFixture.nowMs + 60_000)
            let state = try #require(response.state)
            #expect(state.currentPlayer == .black && state.myColor == .black)
            #expect(state.phase == .rolling && state.revision == 7 && state.shotCount == 1)
            #expect(state.deadlineMs == OnlineFixture.nowMs + 30_000)
            #expect(state.chatSeq == 2 && state.chat.first?.senderID == OnlineFixture.white.id)
            #expect(state.chat.first?.sentAtMs == OnlineFixture.nowMs - 10)
            #expect(state.shot?.stoneID == 0 && state.shot?.steps == 720)
            #expect(state.shot?.initialStones.count == 3 && state.shot?.duration == 3)
            #expect(state.canonicalGame != nil && state.shotReplayGame != nil)
        }
    }

    @Test func bothPeersPlaceUsingTheirOwnRevisionAndReadyLocksTheirLayout() async throws {
        for color in AlkkagiGame.Player.allCases {
            var snapshot = OnlineFixture.match(myColor: color, phase: .placing)
            snapshot.placementRevision = 3
            let service = OnlineScript([.response(OnlineFixture.response(snapshot))],
                                       fallback: OnlineFixture.response())
            let store = makeStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            #expect(store.isMyTurn && store.canPlace && !store.canShoot)
            #expect(store.state?.stones.count == 5 && store.state?.stones.allSatisfy { $0.owner == color } == true)
            await store.confirmPlacement()
            await store.place(stoneID: color == .black ? 5 : 0, at: OnlineFixture.vector(300, 400))
            await store.place(stoneID: color == .black ? 0 : 5, at: OnlineFixture.vector(.nan, 400))
            #expect(service.calls.count == 1)
            let ownID = color == .black ? 0 : 5
            let position = OnlineFixture.vector(100, color == .black ? 440 : 160)
            // The other player changes the public revision, without invalidating my pending placement.
            snapshot.revision += 4
            snapshot.opponentReady = true
            service.enqueue(.response(OnlineFixture.response(snapshot)))
            await store.refreshLobby()
            await store.place(stoneID: ownID, at: position)
            guard case let .place(id, revision, stoneID, sentPosition, _) = service.calls.last else {
                Issue.record("Both colors must be allowed to place during the same phase")
                continue
            }
            #expect(id == OnlineFixture.matchID && revision == 3 && revision != snapshot.revision)
            #expect(stoneID == ownID && sentPosition == position)
            #expect(store.state == snapshot, "Only a server snapshot commits a placement")
            for index in snapshot.stones.indices { snapshot.stones[index].isPlaced = true }
            snapshot.revision += 1
            snapshot.placementRevision += 1
            service.enqueue(.response(OnlineFixture.response(snapshot)))
            await store.refreshLobby()
            await store.confirmPlacement()
            guard case let .ready(id, revision, _) = service.calls.last else {
                Issue.record("Five own stones allow ready")
                continue
            }
            #expect(id == OnlineFixture.matchID && revision == snapshot.placementRevision)
            snapshot.myReady = true
            snapshot.revision += 1
            snapshot.placementRevision += 1
            service.enqueue(.response(OnlineFixture.response(snapshot)))
            await store.refreshLobby()
            let before = service.calls.count
            await store.place(stoneID: ownID, at: position)
            await store.confirmPlacement()
            #expect(!store.canPlace && !store.canShoot && !store.isMyTurn)
            #expect(service.calls.count == before, "Ready locks this player's layout")
        }
    }

    @Test func opponentPlacementDoesNotInterruptMyPlacementDrag() async throws {
        var snapshot = OnlineFixture.match(phase: .placing)
        let service = OnlineScript([.response(OnlineFixture.response(snapshot))])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let model = AlkkagiLocalModel()
        model.attachOnline(store)
        let point = OnlineFixture.vector(100, 440)
        model.aim(start: point, translation: OnlineFixture.vector(20, 10))
        let dragged = model.dragPlacementID
        let target = model.placementPoint
        #expect(dragged != nil && target != nil)
        snapshot.revision += 1
        snapshot.opponentReady = true
        service.enqueue(.response(OnlineFixture.response(snapshot)))
        await store.refreshLobby()
        model.tick(now: 0)
        model.tick(now: 0.01)
        #expect(model.dragPlacementID == dragged && model.placementPoint == target)
        var revealed = OnlineFixture.match(revision: snapshot.revision + 1)
        revealed.myReady = true
        revealed.opponentReady = true
        service.enqueue(.response(OnlineFixture.response(revealed)))
        await store.refreshLobby()
        model.tick(now: 0.02)
        #expect(model.dragPlacementID == nil && model.placementPoint == nil)
    }

    @Test func onlyTheFirstAuthoritativeFinishRefreshesMissions() async throws {
        let active = OnlineFixture.match()
        var finished = active
        finished.phase = .finished
        finished.result = .black
        finished.deadlineMs = nil
        finished.revision += 1
        let service = OnlineScript([.response(OnlineFixture.response(active)),
                                    .response(OnlineFixture.response(finished)),
                                    .response(OnlineFixture.response(finished)),
                                    .response(OnlineFixture.response(active))])
        let store = makeStore(service)
        var finishes = 0
        store.onMatchFinished = { finishes += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(finishes == 0)
        await store.refreshMatch()
        #expect(finishes == 1)
        await store.refreshMatch()
        await store.refreshMatch()
        #expect(finishes == 1 && store.state?.phase == .finished)
        store.reset()
        service.enqueue(.response(OnlineFixture.response(active)))
        await store.refreshLobby()
        #expect(finishes == 1, "Resetting the account is not a game result")
        service.enqueue(.response(OnlineFixture.response(finished)))
        await store.refreshMatch()
        #expect(finishes == 2, "The next account/session keeps its own finish observations")
    }

    @Test func blockedPeersNeverBecomeVisibleOrTriggerAnInvitationNotification() async throws {
        var lobby = OnlineFixture.response()
        lobby.me = OnlineFixture.black
        lobby.users = [OnlineFixture.white]
        lobby.incoming = [OnlineFixture.invite()]
        lobby.outgoing = OnlineFixture.invite()
        let service = OnlineScript([.response(lobby)])
        let store = makeStore(service)
        store.hiddenPeerIDs = [OnlineFixture.white.id.uppercased()]
        var notifications = 0
        store.onInviteArrived = { _ in notifications += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.users.isEmpty && store.incoming.isEmpty && store.outgoing == nil)
        await store.challenge(opponentID: OnlineFixture.white.id)
        #expect(service.calls.count == 1 && notifications == 0)
    }

    @Test func aimingGatesBothPeersAndSendsOneShotWithTheSuppliedNonce() async throws {
        for shooter in AlkkagiGame.Player.allCases {
            var peers: [(AlkkagiOnlineStore, OnlineScript)] = []
            defer { for (store, service) in peers { store.reset(); service.finish() } }
            for color in AlkkagiGame.Player.allCases {
                var snapshot = OnlineFixture.match(myColor: color)
                snapshot.currentPlayer = shooter
                let service = OnlineScript([.response(OnlineFixture.response(snapshot)), .suspended],
                                           fallback: OnlineFixture.response())
                let store = makeStore(service)
                peers.append((store, service))
                await store.refreshLobby()
                #expect(store.canShoot == (color == shooter) && !store.canPlace)
                let ownID = color == .black ? 0 : 5
                await store.shoot(stoneID: color == .black ? 5 : 0, pull: OnlineFixture.vector(0, 80))
                await store.shoot(stoneID: ownID, pull: OnlineFixture.vector(0, 5))
                await store.shoot(stoneID: ownID, pull: OnlineFixture.vector(.infinity, 80))
                #expect(service.calls.count == 1)
                let nonce = UUID()
                let pull = OnlineFixture.vector(12, 80)
                let shot = Task { await store.shoot(stoneID: ownID, pull: pull, actionID: nonce) }
                defer { shot.cancel() }
                if color != shooter {
                    await shot.value
                    #expect(service.calls.count == 1)
                    continue
                }
                try await eventually { service.isSuspended(1) }
                #expect(store.isBusy && !store.canShoot)
                #expect(store.state == snapshot, "A shot must not optimistically roll or advance the turn")
                #expect(service.calls[1] == .shoot(matchID: OnlineFixture.matchID,
                                                 expectedRevision: snapshot.revision,
                                                 stoneID: ownID, pull: pull, actionID: nonce))
                await store.shoot(stoneID: ownID, pull: pull)
                #expect(service.calls.count == 2, "A second action cannot race the first")
                service.resume(1, returning: OnlineFixture.response())
                await shot.value
                #expect(!store.isBusy && store.canShoot)
                #expect(store.state == snapshot)
            }
        }
    }

    @Test func staleBoardRevisionStillMergesChatAndAdvancesOnlyTheChatCursor() async throws {
        var newest = OnlineFixture.match(revision: 12)
        newest.chatSeq = 2
        newest.chat = [OnlineFixture.message(2, "original")]
        var stale = newest
        stale.revision = 11
        stale.currentPlayer = .white
        stale.stones[0].position.x += 20
        stale.chatSeq = 5
        stale.chat = [OnlineFixture.message(5, "five"), OnlineFixture.message(2, "replacement"),
                      OnlineFixture.message(4, "four"), OnlineFixture.message(0, "invalid"),
                      OnlineFixture.message(6, "beyond cursor"),
                      OnlineFixture.message(3, String(repeating: "a", count: 101))]
        var invalidDate = OnlineFixture.message(1, "invalid date")
        invalidDate.sentAtMs = .nan
        stale.chat.append(invalidDate)
        let service = OnlineScript([.response(OnlineFixture.response(newest)),
                                    .response(OnlineFixture.response(stale)),
                                    .response(OnlineFixture.response())])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        await store.refreshMatch()
        #expect(store.state?.revision == 12 && store.state?.currentPlayer == .black)
        #expect(store.state?.stones == newest.stones)
        #expect(store.chat.map(\.seq) == [2, 4, 5])
        #expect(store.chat.map(\.body) == ["original", "four", "five"])
        #expect(store.state?.chat == store.chat && store.state?.chatSeq == 5)
        await store.refreshMatch()
        #expect(service.calls == [.lobby(users: true), .state(matchID: OnlineFixture.matchID, sinceChatSeq: 2),
                                  .state(matchID: OnlineFixture.matchID, sinceChatSeq: 5)])
    }

    @Test func resetIgnoresLateAccountRepliesAndTheirBusyCleanup() async throws {
        let old = OnlineFixture.match()
        let service = OnlineScript([.response(OnlineFixture.response(old)), .suspended,
                                    .response(OnlineFixture.response(OnlineFixture.match(myColor: .white))),
                                    .suspended])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let oldAction = Task { await store.resign() }
        defer { oldAction.cancel() }
        try await eventually { service.isSuspended(1) }
        let generation = store.resetGeneration
        store.reset()
        #expect(store.resetGeneration != generation)
        #expect(store.me == nil && store.state == nil && store.chat.isEmpty)
        #expect(!store.isBusy && !store.isLoading && !store.isSendingChat && !store.canShoot)
        await store.refreshLobby()
        #expect(store.me == OnlineFixture.white, "The injected service survives an account reset")
        let newAction = Task { await store.resign() }
        defer { newAction.cancel() }
        try await eventually { service.isSuspended(3) }
        var late = OnlineFixture.response(old)
        late.users = [OnlineFixture.black]
        late.incoming = [OnlineFixture.invite()]
        service.resume(1, returning: late)
        await oldAction.value
        #expect(store.me == OnlineFixture.white && store.state?.myColor == .white)
        #expect(store.users.isEmpty && store.incoming.isEmpty && store.chat.isEmpty)
        #expect(store.isBusy, "An old action's defer must not unlock a new account's action")
        service.resume(3, returning: OnlineFixture.response())
        await newAction.value
        #expect(!store.isBusy)
    }

    @Test func authenticationLossClearsAccountAndCancelsAnInFlightSync() async throws {
        for failure in [OnlineReply.response(AlkkagiResponse(status: .notSignedIn,
                                                            serverNowMs: OnlineFixture.nowMs)),
                        .failure(.notSignedIn)] {
            let service = OnlineScript([.response(OnlineFixture.response(OnlineFixture.match())),
                                        .suspended, failure])
            let store = makeStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            let refresh = Task { await store.refreshMatch() }
            defer { refresh.cancel() }
            try await eventually { service.isSuspended(1) }
            await store.sendChat(body: "hello")
            #expect(store.me == nil && store.state == nil && store.chat.isEmpty)
            #expect(!store.isSendingChat && !store.isLoading && !store.canShoot)
            try await eventually { service.cancelledRequests.contains(1) }
            service.resume(1, returning: OnlineFixture.response(OnlineFixture.match()))
            await refresh.value
            #expect(store.me == nil && store.state == nil && store.incoming.isEmpty)
        }
    }

    @Test func aPreviousMatchReplyCannotReplaceTheNewMatchOrItsChat() async throws {
        var previous = OnlineFixture.match()
        previous.phase = .finished
        previous.result = .black
        previous.chatSeq = 1
        previous.chat = [OnlineFixture.message(1, "old")]
        var next = OnlineFixture.match(id: OnlineFixture.nextMatchID)
        next.chatSeq = 1
        next.chat = [OnlineFixture.message(1, "new")]
        let service = OnlineScript([.response(OnlineFixture.response(previous)), .suspended,
                                    .response(OnlineFixture.response(next))])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let oldChat = Task { await store.sendChat(body: "delayed") }
        defer { oldChat.cancel() }
        try await eventually { service.isSuspended(1) }
        await store.refreshLobby()
        #expect(store.state?.id == next.id && store.chat.map(\.body) == ["new"])
        previous.revision = 999
        previous.chatSeq = 2
        previous.chat.append(OnlineFixture.message(2, "late old chat"))
        service.resume(1, returning: OnlineFixture.response(previous))
        await oldChat.value
        #expect(store.state == next && store.chat == next.chat)
        #expect(!store.isSendingChat)
    }

    @Test func aBurstOfRefreshSignalsProducesOneCoalescedFollowup() async throws {
        let snapshot = OnlineFixture.match()
        let response = OnlineFixture.response(snapshot)
        let service = OnlineScript([.suspended, .response(response), .response(response)])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        let refresh = Task { await store.refreshLobby() }
        defer { refresh.cancel() }
        try await eventually { service.isSuspended(0) }
        for _ in 0..<20 {
            store.handleSignal()
            store.realtimeDidJoin()
            store.systemDidWake()
        }
        #expect(service.calls == [.lobby(users: true)] && service.maxConcurrentCalls == 1)
        service.resume(0, returning: response)
        await refresh.value
        #expect(service.calls == [.lobby(users: true), .lobby(users: false),
                                  .state(matchID: OnlineFixture.matchID, sinceChatSeq: 0)])
        #expect(service.maxConcurrentCalls == 1 && !store.isLoading)
    }

    @Test func serverClockUsesRequestMidpointAndLateRepliesCannotRewindIt() async throws {
        let clock = OnlineClock(milliseconds: 10_000)
        let snapshot = OnlineFixture.match()
        let service = OnlineScript([.suspended, .suspended,
                                    .response(OnlineFixture.response(snapshot, serverNowMs: 1_003_100))])
        let store = makeStore(service, clock: clock)
        defer { store.reset(); service.finish() }
        let initial = Task { await store.refreshLobby() }
        defer { initial.cancel() }
        try await eventually { service.isSuspended(0) }
        clock.milliseconds = 10_200
        service.resume(0, returning: OnlineFixture.response(snapshot))
        await initial.value
        // Foundation Date rounds sub-millisecond values around its reference epoch.
        #expect(abs(store.estimatedServerNowMs - 1_000_100) < 0.001)
        #expect(abs(store.remainingSeconds - 29.9) < 0.000001)
        clock.milliseconds += 3_000
        #expect(abs(store.remainingSeconds - 26.9) < 0.000001)
        let oldChat = Task { await store.sendChat(body: "late clock") }
        defer { oldChat.cancel() }
        try await eventually { service.isSuspended(1) }
        await store.refreshMatch()
        let synchronizedNow = store.estimatedServerNowMs
        service.resume(1, returning: OnlineFixture.response(snapshot, serverNowMs: 900_000))
        await oldChat.value
        #expect(abs(store.estimatedServerNowMs - synchronizedNow) < 0.001)
        #expect(abs(store.remainingSeconds - 26.9) < 0.000001)
    }

    @Test func rollingPausesTheServerClockAndReadingItHasNoSideEffects() async throws {
        let clock = OnlineClock()
        let decoded = try JSONDecoder().decode(AlkkagiResponse.self, from: Data(OnlineFixture.wireJSON.utf8))
        let snapshot = try #require(decoded.state)
        let service = OnlineScript([.response(decoded)])
        let store = makeStore(service, clock: clock)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.remainingSeconds == 30 && !store.canShoot && !store.canPlace)
        clock.milliseconds += 120_000
        for _ in 0..<20 { #expect(store.remainingSeconds == 30) }
        #expect(snapshot.canonicalGame(serverNowMs: clock.milliseconds)?.turnRemaining == 30)
        #expect(store.state == snapshot && service.calls.count == 1)
        #expect(store.state?.phase == .rolling && store.state?.currentPlayer == .black)
    }

    @Test func deadlineExpirationRequestsStateWithoutAdvancingTheTurnLocally() async throws {
        let clock = OnlineClock()
        var snapshot = OnlineFixture.match()
        snapshot.deadlineMs = OnlineFixture.nowMs + 15
        let response = OnlineFixture.response(snapshot)
        let service = OnlineScript([.response(response), .response(response), .response(response), .suspended],
                                   fallback: OnlineFixture.response())
        let store = makeStore(service, clock: clock, pollSeconds: 0.05)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        store.windowDidShow()
        try await eventually { service.calls.count == 3 && !store.isLoading }
        clock.milliseconds += 60_000
        // This must run before the first 50 ms poll; the deadline is only 15 ms away.
        try await eventually(timeout: .milliseconds(40)) { service.isSuspended(3) }
        #expect(store.remainingSeconds == 0 && !store.canShoot)
        #expect(store.state == snapshot && store.state?.currentPlayer == .black)
        #expect(store.state?.revision == snapshot.revision && store.state?.shotCount == 0)
        store.windowDidHide()
        service.resume(3, returning: AlkkagiResponse(status: .ok, serverNowMs: clock.milliseconds))
        try await eventually { !store.isLoading }
        #expect(service.calls.last == .state(matchID: OnlineFixture.matchID, sinceChatSeq: 0))
        #expect(store.state == snapshot, "Only a later authoritative snapshot may change turns")
    }

    // check 통합(PR #9 를 받으며): 판 중 걸음은 판 상태만 — 로비(사람 목록)를 걸음마다 부르지 않는다.
    @Test func pollingDuringAMatchReadsOnlyTheMatch() async throws {
        let service = OnlineScript(fallback: OnlineFixture.response(OnlineFixture.match()))
        let store = makeStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await eventually { service.calls.count >= 8 && !store.isLoading }
        store.windowDidHide()
        try await eventually { !store.isLoading }
        let lobbies = service.calls.filter { if case .lobby = $0 { true } else { false } }.count
        let states = service.calls.filter { if case .state = $0 { true } else { false } }.count
        #expect(lobbies == 1, "창을 열 때 한 번만 — 판 중 걸음은 로비를 부르지 않는다(실제 \(lobbies))")
        #expect(states >= 6)
    }

    // 판이 없으면 걸음마다 로비를 읽되 사람 목록은 30초에 한 번(시계를 멈춘 채라 처음 한 번뿐).
    @Test func pollingWithoutAMatchRefreshesPeopleAtMostEveryThirtySeconds() async throws {
        let clock = OnlineClock()
        let service = OnlineScript(fallback: OnlineFixture.response())
        let store = makeStore(service, clock: clock, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await eventually { service.calls.count >= 6 && !store.isLoading }
        store.windowDidHide()
        try await eventually { !store.isLoading }
        let withPeople = service.calls.filter { $0 == .lobby(users: true) }.count
        let light = service.calls.filter { $0 == .lobby(users: false) }.count
        #expect(withPeople == 1, "사람 목록 로비는 창을 열 때 한 번(실제 \(withPeople))")
        #expect(light >= 2, "초대는 가벼운 로비가 걸음마다 싣는다")
    }

    @Test func hidingAndClosingStopPollsAndShowingTwiceDoesNotDuplicateThem() async throws {
        let service = OnlineScript(fallback: OnlineFixture.response())
        let store = makeStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        store.windowDidShow()
        try await eventually { service.calls.count >= 2 && !store.isLoading }
        store.windowDidHide()
        try await eventually { !store.isLoading }
        let hiddenCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == hiddenCount && !store.isWindowVisible)
        store.windowDidShow()
        try await eventually { service.calls.count >= hiddenCount + 2 && !store.isLoading }
        store.windowDidClose()
        try await eventually { !store.isLoading }
        let closedCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == closedCount && !store.isWindowVisible)
        #expect(service.maxConcurrentCalls == 1)
    }

    @Test func occlusionStopsPollingAndResetCancelsTheResumedPoll() async throws {
        let service = OnlineScript(fallback: OnlineFixture.response())
        let store = makeStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await eventually { service.calls.count >= 2 && !store.isLoading }
        store.windowOcclusionDidChange(visible: false)
        try await eventually { !store.isLoading }
        let occludedCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(store.isWindowVisible && store.isWindowOccluded)
        #expect(service.calls.count == occludedCount)
        service.enqueue(.suspended)
        store.windowOcclusionDidChange(visible: true)
        try await eventually { service.isSuspended(occludedCount) }
        #expect(!store.isWindowOccluded)
        store.reset()
        try await eventually { service.cancelledRequests.contains(occludedCount) }
        service.resume(occludedCount, returning: OnlineFixture.response(OnlineFixture.match()))
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == occludedCount + 1)
        #expect(store.state == nil && !store.isWindowVisible && !store.isLoading)
    }

    @Test func unknownProtocolPhaseResultAndStatusFailClosed() async throws {
        let decoder = JSONDecoder()
        let unknownPhase = try decoder.decode(AlkkagiMatchPhase.self, from: Data("\"future_phase\"".utf8))
        let unknownResult = try decoder.decode(AlkkagiMatchResult.self, from: Data("\"future_result\"".utf8))
        let unknownStatus = try decoder.decode(AlkkagiRPCStatus.self, from: Data("\"future_status\"".utf8))
        #expect(unknownPhase == .unknown && unknownResult == .unknown && unknownStatus == .unknown)
        let valid = OnlineFixture.match()
        var protocolMismatch = OnlineFixture.response(valid)
        protocolMismatch.protocolVersion = 2
        var badPhase = valid
        badPhase.phase = unknownPhase
        var badResult = valid
        badResult.phase = .finished
        badResult.result = unknownResult
        for rejected in [protocolMismatch, OnlineFixture.response(badPhase), OnlineFixture.response(badResult),
                         AlkkagiResponse(status: unknownStatus, serverNowMs: OnlineFixture.nowMs),
                         AlkkagiResponse(status: .unsupportedClient, serverNowMs: OnlineFixture.nowMs)] {
            let service = OnlineScript([.response(OnlineFixture.response(valid)), .response(rejected)])
            let store = makeStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            #expect(store.canShoot)
            await store.refreshMatch()
            #expect(store.state == valid && store.notice != nil)
            #expect(!store.canShoot && !store.canPlace)
            await store.shoot(stoneID: 0, pull: OnlineFixture.vector(0, 80))
            await store.sendChat(body: "must not send")
            #expect(service.calls.count == 2)
        }
    }

    @Test func malformedCheckpointsAreRejectedWithoutReplacingTheLastValidBoard() async throws {
        let valid = OnlineFixture.match()
        #expect(valid.canonicalGame != nil)
        let corruptions: [(String, (inout AlkkagiMatch) -> Void)] = [
            ("negative revision", { $0.revision = -1 }),
            ("negative chat cursor", { $0.chatSeq = -1 }),
            ("nonfinite deadline", { $0.deadlineMs = .infinity }),
            ("placement exposes opponent stones", { $0.phase = .placing }),
            ("unfinished result", { $0.result = .black }),
            ("missing finished result", { $0.phase = .finished }),
            ("duplicate stone IDs", { $0.stones[1] = $0.stones[0] }),
            ("owner disagrees with stone ID", {
                $0.stones[0] = AlkkagiGame.Stone(id: 0, owner: .white, position: OnlineFixture.vector(100, 100))
            }),
            ("invalid stone ID", {
                $0.stones[0] = AlkkagiGame.Stone(id: 10, owner: .black, position: OnlineFixture.vector(100, 400))
            }),
            ("nonfinite position", { $0.stones[0].position.x = .nan }),
            ("nonfinite velocity", { $0.stones[0].velocity.y = .infinity }),
            ("live stone outside board", { $0.stones[0].position.x = -1 }),
            ("moving unplaced stone", {
                $0.stones[0].isPlaced = false
                $0.stones[0].velocity.x = 1
            }),
            ("unplaced ring-out", { $0.stones[0].isPlaced = false; $0.stones[0].isOut = true }),
            ("negative shot count", { $0.shotCount = -1 }),
            ("overflowing shot count", { $0.shotCount = Int.max })
        ]
        for (reason, corrupt) in corruptions {
            var malformed = valid
            corrupt(&malformed)
            #expect(malformed.canonicalGame == nil, "Rejected checkpoint: \(reason)")
            let service = OnlineScript([.response(OnlineFixture.response(valid)),
                                        .response(OnlineFixture.response(malformed))])
            let store = makeStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            await store.refreshMatch()
            #expect(store.state == valid && !store.canShoot && store.notice != nil, "Rejected checkpoint: \(reason)")
        }
    }

    @Test func shotReplayIsDeterministicAndCannotReplaceTheAuthoritativeCheckpoint() async throws {
        let response = try JSONDecoder().decode(AlkkagiResponse.self, from: Data(OnlineFixture.wireJSON.utf8))
        let snapshot = try #require(response.state)
        let service = OnlineScript([.response(response)])
        let store = makeStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        var slower = try #require(store.state?.shotReplayGame)
        var faster = try #require(store.state?.shotReplayGame)
        #expect(slower.phase == .rolling && slower.currentPlayer == .black && slower.shotCount == 1)
        var slowImpacts: [AlkkagiGame.Impact] = []
        var fastImpacts: [AlkkagiGame.Impact] = []
        for _ in 0..<90 { slowImpacts += slower.advance(dt: 1.0 / 30) }
        for _ in 0..<432 { fastImpacts += faster.advance(dt: 1.0 / 144) }
        #expect(slower.phase == .aiming && slower.currentPlayer == .white)
        #expect(slower.result == nil && slower.shotCount == 1)
        #expect(slower.stones.first { $0.id == 5 }?.isOut == true)
        #expect(slower.stones.first { $0.id == 6 }?.isOut == false)
        #expect(slower.phase == faster.phase && slower.currentPlayer == faster.currentPlayer)
        #expect(slower.result == faster.result && slower.shotCount == faster.shotCount)
        #expect(slowImpacts.contains { $0.isRingOut } && slowImpacts.contains { !$0.isRingOut })
        #expect(slowImpacts.count == fastImpacts.count)
        for (slow, fast) in zip(slower.stones, faster.stones) {
            #expect(slow.id == fast.id && slow.isOut == fast.isOut)
            #expect((slow.position - fast.position).length < 1e-8)
            #expect((slow.velocity - fast.velocity).length < 1e-8)
        }
        #expect(store.state == snapshot && store.state?.phase == .rolling)
        #expect(store.remainingSeconds == 30 && service.calls.count == 1)
        var badShot = snapshot
        badShot.shot?.steps = -1
        #expect(badShot.shotReplayGame == nil)
        badShot = snapshot
        badShot.shot?.pull = OnlineFixture.vector(.nan, 10)
        #expect(badShot.shotReplayGame == nil)
        badShot = snapshot
        badShot.shot?.initialStones.append(snapshot.shot!.initialStones[0])
        #expect(badShot.shotReplayGame == nil)
    }

    @Test func incomingInviteExpiresWhileTheWindowIsClosedWithoutStartingPolls() async throws {
        let clock = OnlineClock()
        var response = OnlineFixture.response()
        response.me = OnlineFixture.black
        response.incoming = [OnlineFixture.invite(expiresAtMs: OnlineFixture.nowMs + 20)]
        let expired = AlkkagiResponse(status: .ok, serverNowMs: OnlineFixture.nowMs + 60_001, incoming: [])
        let service = OnlineScript([.response(response)], fallback: expired)
        let store = makeStore(service, clock: clock, pollSeconds: 0.01)
        var notifications = 0
        store.onInviteArrived = { _ in notifications += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.incoming.count == 1 && notifications == 1 && !store.isWindowVisible)
        // A short deadline keeps the test fast; the injected clock crosses the real 60 s lifetime.
        clock.milliseconds += 60_001
        try await eventually(timeout: .milliseconds(150)) { store.incoming.isEmpty }
        #expect(!store.isWindowVisible && notifications == 1)
        #expect(service.calls.count <= 2, "Local cleanup or one deadline RPC is enough; no hidden-window polling")
        let settledCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == settledCount)
    }

    private func makeStore(_ service: OnlineScript, clock: OnlineClock = OnlineClock(),
                           pollSeconds: Double = 0.02) -> AlkkagiOnlineStore {
        AlkkagiOnlineStore(service: service, clock: { clock.date }, pollSeconds: pollSeconds)
    }

    private func eventually(timeout: Duration = .milliseconds(300),
                            _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(predicate(), "The expected asynchronous state did not arrive within \(timeout)")
    }
}

private enum OnlineReply {
    case response(AlkkagiResponse)
    case failure(AlkkagiServiceError)
    case suspended
}

/// This transport only scripts replies. It never implements game rules or manufactures state transitions.
@MainActor
private final class OnlineScript: AlkkagiServing {
    private var replies: [OnlineReply]
    private let fallback: AlkkagiResponse?
    private var continuations: [Int: CheckedContinuation<AlkkagiResponse, any Error>] = [:]
    private var activeCalls = 0
    private(set) var calls: [AlkkagiCall] = []
    private(set) var maxConcurrentCalls = 0
    private(set) var cancelledRequests: Set<Int> = []

    init(_ replies: [OnlineReply] = [], fallback: AlkkagiResponse? = nil) {
        self.replies = replies
        self.fallback = fallback
    }

    func enqueue(_ reply: OnlineReply) { replies.append(reply) }

    func isSuspended(_ index: Int) -> Bool { continuations[index] != nil }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        let index = calls.count
        calls.append(call)
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
        defer { activeCalls -= 1 }
        let reply: OnlineReply
        if !replies.isEmpty {
            reply = replies.removeFirst()
        } else if let fallback {
            reply = .response(fallback)
        } else {
            Issue.record("Unscripted request \(index): \(call)")
            throw AlkkagiServiceError.invalidResponse
        }
        switch reply {
        case let .response(response): return response
        case let .failure(error): throw error
        case .suspended:
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuations[index] = $0 }
            } onCancel: {
                // Deliberately allow a cancelled transport to reply late, as real networking can.
                Task { @MainActor in self.cancelledRequests.insert(index) }
            }
        }
    }

    func resume(_ index: Int, returning response: AlkkagiResponse) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            Issue.record("Request \(index) was not suspended")
            return
        }
        continuation.resume(returning: response)
    }

    func finish() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class OnlineClock {
    var milliseconds: Double
    var date: Date { Date(timeIntervalSince1970: milliseconds / 1000) }

    init(milliseconds: Double = OnlineFixture.nowMs) { self.milliseconds = milliseconds }
}

private enum OnlineFixture {
    static let nowMs: Double = 1_000_000
    static let blackID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let whiteID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let matchID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
    static let nextMatchID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
    static let black = AlkkagiPeer(id: blackID.uuidString.lowercased(), displayName: "Black")
    static let white = AlkkagiPeer(id: whiteID.uuidString.lowercased(), displayName: "White")

    static func vector(_ x: Double, _ y: Double) -> AlkkagiVector { AlkkagiVector(x: x, y: y) }

    static func match(myColor: AlkkagiGame.Player = .black, phase: AlkkagiMatchPhase = .aiming,
                      revision: Int = 7, id: UUID = matchID) -> AlkkagiMatch {
        var stones = AlkkagiGame().stones
        if phase != .placing {
            for index in stones.indices { stones[index].isPlaced = true }
        }
        if phase == .placing { stones.removeAll { $0.owner != myColor } }
        return AlkkagiMatch(id: id.uuidString.lowercased(), revision: revision, phase: phase,
                            currentPlayer: .black, myColor: myColor,
                            black: black, white: white, stones: stones, deadlineMs: nowMs + 30_000)
    }

    static func response(_ state: AlkkagiMatch? = nil, serverNowMs: Double = nowMs) -> AlkkagiResponse {
        let me = state.map { $0.myColor == .black ? black : white }
        return AlkkagiResponse(status: .ok, serverNowMs: serverNowMs, me: me, state: state)
    }

    static func message(_ seq: Int, _ body: String) -> AlkkagiChatMessage {
        AlkkagiChatMessage(seq: seq, senderID: white.id, body: body, sentAtMs: nowMs)
    }

    static func invite(expiresAtMs: Double = nowMs + 60_000) -> AlkkagiInvite {
        AlkkagiInvite(id: matchID.uuidString.lowercased(), opponent: white, expiresAtMs: expiresAtMs)
    }

    // A literal wire payload exercises snake_case keys independently of the production encoders.
    static let wireJSON = """
    {
      "status": "ok", "protocol": 1, "server_now_ms": 1000000,
      "me": {
        "id": "00000000-0000-4000-8000-000000000001", "display_name": "Black",
        "avatar_url": "https://example.invalid/avatar.png"
      },
      "users": [{"id": "00000000-0000-4000-8000-000000000002", "display_name": "White", "character_id": "turtle"}],
      "incoming": [{
        "id": "00000000-0000-4000-8000-000000000010", "expires_at_ms": 1060000,
        "opponent": {"id": "00000000-0000-4000-8000-000000000002", "display_name": "White"}
      }],
      "state": {
        "id": "00000000-0000-4000-8000-000000000010", "revision": 7, "phase": "rolling",
        "current_player": "black", "my_color": "black",
        "black": {"id": "00000000-0000-4000-8000-000000000001", "display_name": "Black"},
        "white": {"id": "00000000-0000-4000-8000-000000000002", "display_name": "White"},
        "stones": [
          {"id": 0, "owner": "black", "position": {"x": 300, "y": 460}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
          {"id": 5, "owner": "white", "position": {"x": 300, "y": 140}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
          {"id": 6, "owner": "white", "position": {"x": 120, "y": 100}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true}
        ],
        "deadline_ms": 1030000, "shot_count": 1, "result": null, "finish_reason": null,
        "chat_seq": 2, "chat": [{"seq": 2, "sender_id": "00000000-0000-4000-8000-000000000002", "body": "hello", "sent_at_ms": 999990}],
        "muted": false,
        "shot": {
          "id": "shot-1", "stone_id": 0, "pull": {"x": 0, "y": 135}, "started_at_ms": 1000000, "steps": 720,
          "initial_stones": [
            {"id": 0, "owner": "black", "position": {"x": 300, "y": 460}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
            {"id": 5, "owner": "white", "position": {"x": 300, "y": 140}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
            {"id": 6, "owner": "white", "position": {"x": 120, "y": 100}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true}
          ]
        }
      }
    }
    """
}
