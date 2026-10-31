@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 **데모 픽스처·라우트**의 계약. 글자가 아니라 코어가 그 글자로 세우는 것을 잰다 — 서비스와 같은 디코더 · 데모 스텁과 같은 고르기 규칙 · 실제 앱 모델로 띄워 `phase` 까지.
// **데모 라우트가 없는 장면은 캡처할 수 없다** — 설계서 §3 장면이 스텁만으로 서는지가 이 파일의 값이다.
@MainActor
@Suite(.serialized) struct GamesRummyFixtureContractTests {
    static let index = MobileDemoFixtures.load()
    static let serverNowMs: Double = 1_789_621_500_000   // MobileClock.demoInstant

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// 스텁이 실제로 고르는 길로 픽스처를 집는다.
    private func body(rpc: String, matchID: UUID? = nil, route: String = "games/rummy/lobby") throws -> Data {
        var fields = [#""p_protocol":1"#]
        if let matchID { fields.append(#""p_match_id":"\#(matchID.uuidString.lowercased())""#) }
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)", query: "",
                                        headers: [:], bodyText: "{" + fields.joined(separator: ",") + "}")
        let scenario = route.replacingOccurrences(of: "/", with: "-")
        let entry = try #require(Self.index.entry(for: request, scenario: scenario), "\(rpc) 픽스처 없음(\(route))")
        return entry.data
    }

    private func state(_ id: UUID) throws -> RummyMatchState {
        let response = try Self.decoder.decode(RummyActionResponse.self, from: try body(rpc: "rummy_state", matchID: id))
        #expect(response.status == .ok)
        return try #require(response.state)
    }

    // MARK: - 라우트 값

    @Test("라우트: 표 그대로 풀린다 · 모르는 꼬리는 로비 머리로 · 다른 게임 글자는 nil")
    func parsing() {
        typealias R = MobileDemoRummyRoute
        #expect(R.Scene.allCases.count == 19)
        for scene in R.Scene.allCases { #expect(R(demoRoute: scene.rawValue)?.scene == scene, "\(scene)") }
        #expect(R(demoRoute: "games/rummy")?.scene == .lobby)
        #expect(R(demoRoute: "games/rummy/없는꼬리")?.scene == .lobby, "틀린 꼬리가 안 보인다")
        #expect(R(demoRoute: "/GAMES/RUMMY/ROOM/")?.scene == .room)
        #expect(R(demoRoute: "games/tetris/lobby") == nil && R(demoRoute: "games") == nil && R(demoRoute: "games/rummyish") == nil)
        #expect(R(demoRoute: "games/rummy/ranking")?.lobbyTab == .ranking)
        #expect(R(demoRoute: "games/rummy/lobby")?.lobbyTab == .people)
        #expect(R(demoRoute: "games/rummy/match/elsewhere")?.scene.engages == false, "놀던 기기 장면이 손댄 판으로 선다")
        #expect(GamesRummyLobbyTab(demo: .ranking) == .ranking && GamesRummyLobbyTab(demo: .people) == .people)
        #expect(R(demoRoute: "games/rummy/match/my-turn")?.destination == .rummy)
        // 기준선: 장면 다섯이 서로 다른 판·다른 스텁 장면을 고른다.
        let ids = R.Scene.allCases.compactMap(\.focusMatchID)
        #expect(Set(ids).count == 7)
    }

    // MARK: - 픽스처 값

    @Test("로비: 와이어 타입으로 읽히고 초대 · 공개 방 · 사람 갈래가 다 있다(사람 행 키는 id)")
    func lobbyDecodes() throws {
        let lobby = try Self.decoder.decode(RummyLobby.self, from: try body(rpc: "rummy_lobby"))
        #expect(lobby.status == .ok)
        #expect(lobby.me?.rubyBalance == 42 && lobby.me?.games == 12)
        #expect(lobby.invites?.count == 1 && lobby.publicRooms?.count == 2)
        let users = try #require(lobby.users)
        #expect(users.count == 8)
        #expect(users.contains { $0.capable == false }, "업데이트 필요 접기를 못 본다")
        #expect(users.contains { $0.inMatch == true }, "바쁜 사람을 못 본다")
        #expect(users.contains { $0.focusMode == true })
        #expect(users.filter { $0.capable == true && $0.inMatch == false && $0.focusMode == false }.count >= 3)
        #expect(!users.contains { $0.id.uuidString.lowercased() == MobileDemo.userID }, "나 자신이 초대 목록에 있다")
    }

    @Test("판 넷: 데모 계정이 내 자리고 · 묶음이 전부 맞고 · 타일이 두 벌을 넘지 않고 · 자리 수가 판돈 분배와 맞는다")
    func statesAreSound() throws {
        typealias S = MobileDemoRummyRoute.Scene
        let me = MobileDemo.userID
        for id in [S.myTurnID, S.waitingID, S.resultID, S.fullID, S.manyID] {
            let state = try state(id)
            #expect(state.id == id)
            let mine = try #require(RummyStore.mySeat(in: state, me: me))
            #expect(mine.seatNo == state.mySeatNo, "\(id): 내 자리가 안 맞는다")
            var counts: [RummyFace: Int] = [:]
            for meld in state.table ?? [] {
                #expect(RummyRules.analyze(meld).valid, "\(id): 맞지 않는 묶음 \(meld.map(\.text))")
                for face in meld { counts[face, default: 0] += 1 }
            }
            for face in state.myRack ?? [] { counts[face, default: 0] += 1 }
            for (face, count) in counts where !face.isJoker { #expect(count <= 2, "\(id): \(face.text) 가 \(count)벌") }
            let table = RummyTableLayout(sets: state.table ?? [], layout: state.tableLayout)
            for (index, frame) in table.frames.enumerated() {
                #expect(frame.x >= 0 && frame.y >= 0 && frame.maxX <= 1000 && frame.maxY <= 640, "\(id) \(index): 캔버스 밖 \(frame)")
                for other in table.frames[(index + 1)...] { #expect(RummyTableLayout.isClear(frame, among: [other]), "\(id): 묶음이 겹친다") }
            }
        }
        let myTurn = try state(S.myTurnID)
        #expect(RummyStore.isMyTurn(myTurn, me: me) && myTurn.myInitialDone == false)
        #expect(myTurn.myRack?.count == 15)
        // 기본 보기에서 오른쪽 화면 밖 묶음이 있어야 배지를 본다.
        let view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        let frames = RummyTableLayout(sets: myTurn.table ?? [], layout: myTurn.tableLayout).frames
        #expect(view.offscreenCounts(frames).right == 2, "my-turn 장면의 화면 밖 배지가 안 선다")
        let waiting = try state(S.waitingID)
        #expect(!RummyStore.isMyTurn(waiting, me: me))
        #expect(waiting.draft?.table?.count == 13, "남의 작업 판이 없다")
        #expect(waiting.seats?.contains { $0.state == .forfeit } == true)
        let result = try state(S.resultID)
        #expect(result.status == .finished && result.endReason == .rackEmpty)
        // 제로섬: payout 합 = 판돈 × 자리 수.
        let payouts = (result.seats ?? []).map { $0.payout ?? 0 }
        #expect(payouts.reduce(0, +) == (result.stake ?? 0) * (result.seatCount ?? 0), "정산이 제로섬이 아니다")
        #expect(payouts.sorted(by: >) == [15, 5, 0, 0], "4인 분배 3·1·0·0 × 판돈 5")
        #expect(result.seats?.first { $0.finalRank == 1 }?.isWinner == true)
        #expect(result.rematchInvitees.count == 2, "기권한 사람을 다시 부른다")
        let room = try state(S.roomID)
        #expect(room.status == .forming && room.hostId?.uuidString.lowercased() == me)
        #expect(room.seats?.filter { $0.state == .joined }.count == 3 && room.seats?.filter { $0.state == .invited }.count == 1)
    }

    @Test("순위 · 쓰기 응답이 와이어 타입으로 읽힌다(눌러도 404 로 화면이 안 죽는다)")
    func actionsDecode() throws {
        let ranking = try Self.decoder.decode(RummyRanking.self, from: try body(rpc: "rummy_ranking"))
        #expect(ranking.rows?.count == 5 && ranking.me?.rank == 2)
        for rpc in ["rummy_create", "rummy_invite", "rummy_join", "rummy_start", "rummy_play", "rummy_draw", "rummy_leave", "rummy_decline", "rummy_draft"] {
            let response = try Self.decoder.decode(RummyActionResponse.self, from: try body(rpc: rpc))
            #expect(response.status == .ok, "\(rpc)")
        }
        for rpc in ["rummy_heartbeat", "rummy_react"] {
            #expect(try Self.decoder.decode(RummyActionResponse.self, from: try body(rpc: rpc)).status == .ok, "\(rpc)")
        }
        // 코어가 부르는 RPC 가 하나도 안 빠졌다.
        for rpc in RummyWire.RPC.all { _ = try body(rpc: rpc, matchID: MobileDemoRummyRoute.Scene.myTurnID) }
    }

    // MARK: - 스텁만으로 장면이 선다

    /// 데모 환경으로 앱 모델을 띄워 그 장면까지 간다.
    private func launch(_ route: String) async throws -> MobileAppModel {
        let environment = try #require(MobileDemo.environment(arguments: ["-AingCheckDemo", "YES", "-AingCheckDemoRoute", route]))
        let model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        model.rummy.heartbeatEnabled = false
        model.rummy.deadlineWakeEnabled = false
        model.rummy.pollStepSeconds = 3_600
        model.start()
        model.sceneDidBecomeActive()
        _ = await baseWaitUntil { model.session.isSignedIn }
        #expect(model.games.consumePendingDemoRummyScreen(), "\(route): 게임 탭이 큐브를 안 쌓는다")
        model.games.rummyScreenDidAppear()
        return model
    }

    @Test("장면: 라우트마다 코어가 다른 단계를 세운다(기준선이 같은 입력이면 영원히 초록이다)")
    func scenesStandOnStubsAlone() async throws {
        typealias S = MobileDemoRummyRoute.Scene
        var seen: [String: RummyStore.Phase] = [:]
        for (route, phase) in [("games/rummy/lobby", RummyStore.Phase.lobby), ("games/rummy/room", .room),
                               ("games/rummy/match/my-turn", .playing), ("games/rummy/match/waiting", .playing),
                               ("games/rummy/result", .finished)] {
            let model = try await launch(route)
            #expect(await baseWaitUntil { model.rummy.phase == phase }, "\(route): \(phase) 가 안 선다(지금 \(model.rummy.phase))")
            #expect(model.rummy.availability == .available, "\(route): 픽스처가 빠져 서버 없음으로 접혔다")
            seen[route] = model.rummy.phase
            switch route {
            case "games/rummy/match/my-turn":
                #expect(model.rummy.isMyTurn)
                #expect(model.rummy.editor?.rack.count == 15)
                #expect(model.rummy.editor?.rackLayout.halfColumns == 22)
                #expect(model.rummy.isEngagedInCurrentMatch)
                #expect(model.rummy.turnRemaining(at: model.rummy.clock()) == 42, "데모 시계로 남은 초가 고정이 아니다")
            case "games/rummy/match/waiting":
                #expect(!model.rummy.isMyTurn)
                #expect(model.rummy.otherDraft?.count == 13)
            case "games/rummy/room":
                #expect(model.rummy.myRoom?.seats?.count == 4)
                #expect(RummyExitPolicy.amHost(model.rummy))
            default:
                break
            }
            await model.session.signOut()
        }
        #expect(Set(seen.keys).count == 5)
    }

    @Test("빽빽한 판 · 받침대 3줄: 판 80장 이상 · 첫 등록 뒤 · 받침대 24장은 3줄이다 · 전체 타일이 두 벌을 넘지 않는다")
    func denseScenes() async throws {
        typealias S = MobileDemoRummyRoute.Scene
        let full = try state(S.fullID)
        let onTable = (full.table ?? []).joined().count
        #expect(onTable >= 80, "빽빽한 판이 아니다: \(onTable)")
        #expect(full.myInitialDone == true)
        let total = onTable + (full.seats ?? []).reduce(0) { $0 + ($1.rackCount ?? 0) } + (full.poolCount ?? 0)
        #expect(total == 106, "판 + 받침대 + 더미 합이 타일 수가 아니다: \(total)")
        var counts: [RummyFace: Int] = [:]
        for face in (full.table ?? []).joined() + (full.myRack ?? []) { counts[face, default: 0] += 1 }
        for (face, count) in counts { #expect(count <= 2, "\(face.text) 가 \(count)벌") }

        let fullModel = try await launch("games/rummy/match/full")
        #expect(await baseWaitUntil { fullModel.rummy.editor != nil })
        #expect(fullModel.rummy.editor?.melds.joined().count == onTable)
        await fullModel.session.signOut()

        let many = try await launch("games/rummy/match/many")
        #expect(await baseWaitUntil { many.rummy.editor != nil })
        #expect(many.rummy.editor?.rack.count == 24)
        #expect(many.rummy.editor?.rackLayout.rowCount == 3, "받침대 3줄 장면이 3줄이 아니다")
        await many.session.signOut()
    }

    @Test("끌기 장면: 궤적이 실제 사건 길로 끌기 도중 상태를 세운다(자석 · 점선 · 거절 · 들어 올림 · 손잡이) · 놓지 않는다")
    func dragScenes() async throws {
        func model(_ route: String) async throws -> (app: MobileAppModel, input: GamesRummyMatchModel, before: RummyTurnEditor) {
            let app = try await launch(route)
            #expect(await baseWaitUntil { app.rummy.editor != nil }, "\(route)")
            let editor = try #require(app.rummy.editor)
            let layout = GamesRummyMatchLayout(size: CGSize(width: 393, height: 759), rackRows: editor.rackLayout.rowCount)
            let scene = GamesRummyBoardScene.make(match: app.rummy.match, editor: editor, isMyTurn: true, otherDraft: nil)
            let context = GamesRummyTouchContext(layout: layout, scene: scene, editor: editor, isMyTurn: true, editable: true)
            let input = GamesRummyMatchModel(tableSize: layout.table.size)
            input.playDemo(try #require(app.games.demoRummyRoute?.demoTouch), context: context)
            return (app, input, editor)
        }
        let dragging = try await model("games/rummy/match/dragging")
        guard case .insert(0, _, _, true)? = dragging.input.boardPreview else {
            Issue.record("끼울 자리 캐럿이 안 선다: \(String(describing: dragging.input.boardPreview))")
            return
        }
        #expect(dragging.app.rummy.editor == dragging.before, "장면이 놓아 버렸다")
        await dragging.app.session.signOut()

        let attach = try await model("games/rummy/match/attach")
        guard case .attach(1, .right, _, _, true)? = attach.input.boardPreview else {
            Issue.record("붙는 자석이 안 선다: \(String(describing: attach.input.boardPreview))")
            return
        }
        await attach.app.session.signOut()

        let placing = try await model("games/rummy/match/placing")
        #expect(placing.input.drag?.tiles.map(\.face.text) == ["A10", "A11", "A12"])
        guard case .ghost? = placing.input.boardPreview else {
            Issue.record("새 묶음 점선이 안 선다")
            return
        }
        await placing.app.session.signOut()

        let refused = try await model("games/rummy/match/refused")
        #expect(refused.input.hoverRefused && refused.input.drag?.surface == .board)
        await refused.app.session.signOut()

        let lifted = try await model("games/rummy/match/lifted")
        #expect(lifted.input.lift?.ids.count == 3 && lifted.input.drag == nil && lifted.input.liftSerial == 1)
        await lifted.app.session.signOut()

        let handle = try await model("games/rummy/match/handle")
        #expect(handle.input.movingSet == 0)
        guard case .ghost? = handle.input.boardPreview else {
            Issue.record("손잡이 점선이 안 선다")
            return
        }
        await handle.app.session.signOut()
    }

    @Test("장면: edited 는 작업 판이 서고(첫 등록 33/30) · 놀던 기기 장면은 쓰기 0건 · 규칙은 시트를 연다 · 순위 탭은 표를 읽는다")
    func routeSpecificScenes() async throws {
        let edited = try await launch("games/rummy/match/edited")
        #expect(await baseWaitUntil { edited.rummy.editor != nil })
        #expect(edited.rummy.editor?.isChanged == false)
        let route = try #require(edited.games.demoRummyRoute)
        route.applyEdit(to: edited.rummy)
        #expect(edited.rummy.editor?.isChanged == true, "작업 판이 안 섰다")
        #expect(edited.rummy.editor?.rack.count == 12)
        #expect(edited.rummy.editor?.initialPoints == 33)
        #expect(edited.rummy.editor?.canSubmit == true, "[완료]가 켜지는 장면이어야 한다")
        let melds = edited.rummy.editor?.melds.count
        route.applyEdit(to: edited.rummy)
        #expect(edited.rummy.editor?.melds.count == melds, "다시 부르면 또 낸다")
        await edited.session.signOut()

        let elsewhere = try await launch("games/rummy/match/elsewhere")
        #expect(await baseWaitUntil { elsewhere.rummy.phase == .playing })
        #expect(!elsewhere.rummy.isEngagedInCurrentMatch, "놀던 기기 장면이 손댄 판이다")
        #expect(!elsewhere.games.holdsRummyMatch)
        #expect(GamesRummyExit.decision(elsewhere.rummy) == .close)
        await elsewhere.session.signOut()

        let rules = try await launch("games/rummy/rules")
        #expect(rules.rummy.rulesShown)
        await rules.session.signOut()

        let ranking = try await launch("games/rummy/ranking")
        #expect(await baseWaitUntil { ranking.rummy.ranking?.rows?.count == 5 }, "순위 탭이 영영 로딩 문구다")
        #expect(ranking.games.demoRummyRoute?.lobbyTab == .ranking)
        await ranking.session.signOut()
    }
}
