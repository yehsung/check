@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **아잉 뒤집기 배선**(1.0.17 · 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)")의 못. 재는 것은 **결과 숫자**다(함수를 불렀는지가 아니라
// 요청이 몇 건 나갔는지 · 값이 어떻게 바뀌었는지). 결과 단언마다 **값 하나만 바꾼 기준선**을 함께 둔다(같은 입력이면 영원히 초록이다).
//
// 뷰는 전부 `#if os(iOS)` 안이라 맥 스위트가 못 본다 — 그 화면을 죽이는 원인은 배선 몇 줄이다:
//  ① 앱 모델: 스토어 생성 · 호스트 · 시계 · '이 기기가 연 판' 장부 저장소 · 순위·관전 주 스위치 둘 · 실시간 칸 · 판 끝 미션 · 로그아웃 사슬
//  ② 러너: `.reversiSignal` → `handleSignal()` · `.catchUp` → `realtimeDidJoin()`(맥 계약 `V03xxReversiWiringTests` 가 글자를 잰다)
//  ③ 게임 탭 스토어: 화면 수명 · 앱 전환 · 허브 30초 스로틀 · 차단 거울 · 탭 배지 · 다섯 방향 입구 · 화면 꺼짐 방지 · 배너 미룸 · 판 시작 문

@MainActor
final class ReversiWireHarness {
    nonisolated static let userID = "a0000000-0000-4000-8000-0000000000a1"
    nonisolated static let rival = "a0000000-0000-4000-8000-0000000000b2"
    nonisolated static let thirdID = "a0000000-0000-4000-8000-0000000000c3"
    nonisolated static let matchID = "a0000000-0000-4000-8000-0000000000f1"
    nonisolated static let watchedID = "a0000000-0000-4000-8000-0000000000f2"
    nonisolated static let inviteID = "a0000000-0000-4000-8000-0000000000e1"

    let server: GamesStubServer
    let storage: AingSharedStorage
    let clock: BaseTestClock
    let transport: BaseFakeTransport
    let model: MobileAppModel

    init(label: String) {
        server = GamesStubServer(label: label)
        storage = BaseStub.makeStorage(label)
        clock = BaseTestClock()
        transport = BaseFakeTransport()
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: Self.userID)
        server.setDefault("/auth/v1/token") { _ in
            BaseStub.authResponse(access: fresh, refresh: "r-reversi", userID: ReversiWireHarness.userID)
        }
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: server.host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-66666666dddd",
            realtimeTransport: transport,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        model.realtime.coalesceSeconds = 3_600
        // 폴링 한 걸음은 시험이 직접 밟는다(시계가 멈춰 있다) · AI 는 생각하지 않는다(내 수만 남긴다).
        model.reversi.pollStepSeconds = 3_600
        model.reversi.aiMoveChooser = { _, _ in nil }
    }

    var games: GamesStore { model.games }
    var reversi: ReversiStore { model.reversi }
    var nowMs: Int { Int(clock.now.timeIntervalSince1970 * 1000) }

    func count(_ rpc: String) -> Int { server.requests(rpc).count }

    func barrier() async {
        await baseBarrier(model.context.service)
        await baseYield(turns: 8)
        await baseBarrier(model.context.service)
    }

    /// 화면이 부르는 조회를 스텁에 건다(로비 · 순위 · 관전 둘) + 허브가 함께 부르는 오목 받은함.
    func serve(incoming: Bool = false, activeMatchID: String? = nil, matches: Bool = false) {
        server.setDefault("reversi_lobby", json: ReversiWireJSON.lobby(
            nowMs: nowMs, incoming: incoming, activeMatchID: activeMatchID, matches: matches))
        server.setDefault("reversi_ranking", json: ReversiWireJSON.ranking(nowMs: nowMs))
        server.setDefault("reversi_watch_live", json: ReversiWireJSON.watch(nowMs: nowMs))
        server.setDefault("reversi_watch", json: ReversiWireJSON.watch(nowMs: nowMs))
        server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
    }

    /// 내 1:1 판 상태를 스텁에 걸고 그 판을 읽는다(서버 왕복 그대로 — `applyState` 를 지난다).
    func loadMatch(status: String = "active", owned: Bool) async {
        server.setDefault("reversi_state", json: ReversiWireJSON.state(nowMs: nowMs, status: status))
        if owned { reversi.noteOwnsMatch(Self.matchID) }
        await reversi.refreshMatch(id: Self.matchID)
    }

    func signIn() async {
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedOut }
        model.sceneDidBecomeActive()
        await model.session.signIn(email: "reversi@aing.invalid", password: "pw")
        await barrier()
    }

    func tearDown() async {
        if model.session.isSignedIn { await model.session.signOut() }
        model.reversi.reset()
        BaseStub.tearDown(host: server.host, storage: storage)
    }
}

/// 서버 모양 그대로(키 이름은 `Tests/checkTests/Fixtures/reversi-rpc/` 실측 캡처와 같다).
enum ReversiWireJSON {
    nonisolated static let startBoard = "...........................wb......bw..........................."

    static func user(_ id: String, _ name: String, capable: Bool? = true, inMatch: Bool = false, focus: Bool = false) -> String {
        let capableValue = capable.map { $0 ? "true" : "false" } ?? "null"
        return #"{"id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"center":null,"is_working":true,"in_match":\#(inMatch),"capable":\#(capableValue),"focus_mode":\#(focus)}"#
    }

    static func peer(_ id: String, _ name: String) -> String {
        #"{"id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null}"#
    }

    static func lobby(nowMs: Int, incoming: Bool = false, activeMatchID: String? = nil, matches: Bool = false) -> String {
        let active = activeMatchID.map { "\"\($0)\"" } ?? "null"
        let invites = incoming
            ? #"{"match_id":"\#(ReversiWireHarness.inviteID)","from":\#(peer(ReversiWireHarness.rival, "뒤집기라이벌")),"stake":5,"expires_at_ms":\#(nowMs + 60_000)}"#
            : ""
        let live = matches
            ? #"{"id":"\#(ReversiWireHarness.watchedID)","a":\#(peer(ReversiWireHarness.rival, "뒤집기라이벌")),"b":\#(peer(ReversiWireHarness.thirdID, "구경거리")),"stake":5,"watchers":0,"started_at_ms":\#(nowMs - 30_000)}"#
            : ""
        let users = [user(ReversiWireHarness.rival, "뒤집기라이벌"), user(ReversiWireHarness.thirdID, "구버전", capable: nil)]
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"turn_seconds":30,"turn_grace_seconds":2,"invite_ttl_seconds":60,"auto_abandon_streak":3,"me":{"ruby_balance":100,"wins":2,"losses":1,"draws":0,"active_match_id":\#(active),"incoming":[\#(invites)],"outgoing":null},"users":[\#(users.joined(separator: ","))],"matches":[\#(live)]}"#
    }

    static func player(_ id: String, _ name: String) -> String {
        #"{"user_id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"center":null}"#
    }

    /// 내 판(나는 흑 · 첫 수 차례) 한 벌을 `{status, state}` 봉투에 담는다.
    static func state(nowMs: Int, id: String = ReversiWireHarness.matchID, status: String) -> String {
        let me = ReversiWireHarness.userID, rival = ReversiWireHarness.rival
        let finished = status == "finished"
        let turn = finished ? "null" : #""black""#
        let deadline = finished ? "null" : "\(nowMs + 29_000)"
        let result = finished ? #""black_win""# : "null"
        let reason = finished ? #""resign""# : "null"
        let winner = finished ? "\"\(me)\"" : "null"
        let legal = finished ? "[]" : "[19,26,37,44]"
        let match = #"{"id":"\#(id)","status":"\#(status)","stake":5,"challenger":"\#(rival)","opponent":"\#(me)","black":"\#(me)","white":"\#(rival)","move_count":0,"turn":\#(turn),"turn_started_ms":\#(nowMs - 1_000),"deadline_ms":\#(deadline),"invite_expires_ms":null,"started_ms":\#(nowMs - 1_000),"finished_ms":null,"result":\#(result),"end_reason":\#(reason),"winner":\#(winner),"board":"\#(startBoard)","discs":{"black":2,"white":2,"empty":60},"score":null}"#
        return #"{"status":"ok","state":{"match":\#(match),"moves":[],"black_user":\#(player(me, "나")),"white_user":\#(player(rival, "뒤집기라이벌")),"opponent":\#(player(rival, "뒤집기라이벌")),"my_color":"black","legal_moves":\#(legal),"black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":0,"auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":95,"watchers":0,"server_now_ms":\#(nowMs)}}"#
    }

    /// 남의 판 관전 한 벌(참가자 칸이 null — 관전 모양).
    static func watch(nowMs: Int) -> String {
        let a = ReversiWireHarness.rival, b = ReversiWireHarness.thirdID
        let match = #"{"id":"\#(ReversiWireHarness.watchedID)","status":"active","stake":5,"challenger":"\#(a)","opponent":"\#(b)","black":"\#(a)","white":"\#(b)","move_count":0,"turn":"black","turn_started_ms":\#(nowMs - 1_000),"deadline_ms":\#(nowMs + 29_000),"started_ms":\#(nowMs - 30_000),"finished_ms":null,"result":null,"end_reason":null,"winner":null,"board":"\#(startBoard)","discs":{"black":2,"white":2,"empty":60},"score":null}"#
        return #"{"status":"ok","state":{"match":\#(match),"moves":[],"black_user":\#(player(a, "뒤집기라이벌")),"white_user":\#(player(b, "구경거리")),"opponent":null,"my_color":null,"legal_moves":[],"black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":null,"opponent_auto_streak":null,"auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":1,"server_now_ms":\#(nowMs)}}"#
    }

    static func ranking(nowMs: Int) -> String {
        let row = #"{"rank":1,"user_id":"\#(ReversiWireHarness.userID)","display_name":"나","avatar_url":null,"character":null,"center":null,"wins":2,"losses":1,"draws":0,"points":1}"#
        return #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":{"rank":1,"wins":2,"losses":1,"draws":0,"points":1},"rows":[\#(row)]}"#
    }
}

@MainActor
@Suite(.serialized) struct GamesReversiWiringTests {
    private let waits = GamesWaitBudget()

    private nonisolated static func gomokuMatch(finished: Bool = false) -> GomokuMatchState {
        GomokuMatchState(
            id: "g-1", stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p-1", displayName: "구름빵", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: true),
            board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: finished ? nil : .black, deadline: nil,
            isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    private nonisolated static func chessMatch(finished: Bool = false) -> ChessMatchState {
        ChessMatchState(
            id: "c-1", stake: 5, myColor: .white,
            opponent: ChessUser(id: "p-chess", displayName: "체스라이벌", avatarURL: nil, characterID: nil,
                                isWorking: true, isCapable: true, inMatch: true),
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            position: nil, plyCount: 0, turn: finished ? nil : .white, lastMove: nil, moves: [],
            clock: .initial, isInCheck: false, legalMoves: [], isFinished: finished,
            outcome: finished ? .won : nil, endReason: finished ? .resign : nil, rubyDelta: finished ? 5 : nil,
            drawOfferBy: nil, drawOfferedByMe: false)
    }

    // MARK: - ① 앱 모델 배선 값

    @Test("배선 값: 같은 스토어 · 같은 호스트 · 주 스위치 둘이 켜져 있고 reset 이 안 건드린다 · 장부가 앱 저장소에 떨어진다")
    func modelWiring() async {
        // 없으면: 스위치가 꺼진 채라 순위·관전이 영영 로딩 문구이고, 장부가 프로세스 안에만 살아 판 중에 다시 켠 폰이 자기 판을 못 알아본다.
        let harness = ReversiWireHarness(label: "reversi-wire-values")
        await harness.signIn()
        let model = harness.model
        #expect(model.context.reversi === model.reversi && harness.games.reversi === model.reversi, "탭 스토어가 딴 인스턴스를 본다")
        #expect(model.realtime.reversi === model.reversi, "실시간 칸이 비었다 — 초인종이 nil 에 말을 건다")
        #expect(model.reversi.host === model.gomokuHost, "호스트가 오목과 다르다 — 루비 미러가 갈린다")
        #expect(model.reversi.rankingEnabled && model.reversi.spectatorFeaturesEnabled, "주 스위치 둘 중 하나가 꺼져 있다")
        #expect(model.reversi.presentWindow != nil, "판 시작 문이 안 걸렸다 — 수락이 화면을 못 연다")
        model.reversi.reset()
        #expect(model.reversi.rankingEnabled && model.reversi.spectatorFeaturesEnabled, "reset 이 배선 값을 껐다")
        #expect(model.reversi.presentWindow != nil, "reset 이 판 시작 문을 뗐다")

        // 장부: 인스턴스가 아니라 **남는 값**으로 잰다(`storage.defaults` 는 부를 때마다 같은 suite 의 새 인스턴스다).
        model.reversi.noteOwnsMatch("m-reversi-owned")
        let key = model.reversi.deviceLedger.key(userID: ReversiWireHarness.userID)
        #expect(key != model.chess.deviceLedger.key(userID: ReversiWireHarness.userID), "체스와 한 키를 나눠 쓴다")
        #expect(harness.storage.defaults.dictionary(forKey: key)?.keys.contains("m-reversi-owned") == true,
                "장부가 앱 저장소에 안 떨어진다 — 판 중에 다시 켠 폰이 자기 판의 화면을 안 연다")
        var reopened = GameDeviceLedger(game: "reversi", ttlSeconds: 6 * 3_600)
        reopened.defaults = harness.storage.defaults
        #expect(reopened.owns("m-reversi-owned", userID: ReversiWireHarness.userID, now: model.reversi.clock()))
        // 시계도 앱 시계다(기기 시계 `Date.init` 이면 시험 시계와 갈려 장부 기한·마감이 흔들린다).
        #expect(model.reversi.clock() == harness.clock.now)
        await harness.tearDown()
    }

    @Test("주 스위치(순위): 화면이 뜨면 로비와 순위가 실제로 나간다 · 스위치만 끈 기준선은 순위 0건")
    func screenLoadsLobbyAndRanking() async {
        let harness = ReversiWireHarness(label: "reversi-rank-on")
        harness.serve()
        await harness.signIn()
        let lobbyBefore = harness.count("reversi_lobby")
        harness.games.reversiScreenDidAppear()
        #expect(harness.reversi.isWindowVisible, "화면 훅이 코어 창 깃발을 안 켰다 — 폴링·순위·관전·뒤집기 그림이 함께 죽는다")
        #expect(await waits.wait { harness.count("reversi_lobby") > lobbyBefore }, "화면이 떴는데 로비를 안 읽었다")
        #expect(await waits.wait { harness.count("reversi_ranking") >= 1 }, "순위 절이 영영 로딩 문구다 — rankingEnabled 배선이 빠졌다")
        #expect(await waits.wait { harness.reversi.ranking?.entries.count == 1 }, "순위 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.reversi.pollTask != nil, "창이 섰는데 폴링이 안 돈다")
        await harness.tearDown()

        let off = ReversiWireHarness(label: "reversi-rank-off")
        off.serve()
        await off.signIn()
        off.reversi.rankingEnabled = false          // = 배선 한 줄을 지운 것
        off.games.reversiScreenDidAppear()
        #expect(await waits.wait { off.reversi.record != nil }, "로비는 스위치와 무관하다 — 손짓 자체가 안 닿았다")
        await off.barrier()
        #expect(off.count("reversi_ranking") == 0, "스위치가 꺼졌는데 순위가 나갔다")
        await off.tearDown()
    }

    @Test("주 스위치(관전): 켜면 [관전]이 관전 상태를 세우고 판을 읽는다 · 끈 기준선은 상태도 요청도 0")
    func watchSwitch() async {
        let harness = ReversiWireHarness(label: "reversi-watch-on")
        harness.serve(matches: true)
        await harness.signIn()
        harness.games.reversiScreenDidAppear()
        #expect(await waits.wait { !harness.reversi.liveMatches.isEmpty }, "로비 '지금 대결 중'이 안 왔다")
        harness.reversi.startWatching(matchID: ReversiWireHarness.watchedID)
        #expect(await waits.wait { harness.count("reversi_watch_live") >= 1 }, "관전 조회가 안 나갔다")
        #expect(await waits.wait { harness.reversi.spectating?.blackUser?.id == ReversiWireHarness.rival },
                "관전 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.reversi.spectating?.isFinished == false)
        await harness.tearDown()

        let off = ReversiWireHarness(label: "reversi-watch-off")
        off.serve(matches: true)
        await off.signIn()
        off.reversi.spectatorFeaturesEnabled = false
        off.games.reversiScreenDidAppear()
        #expect(await waits.wait { !off.reversi.liveMatches.isEmpty })
        off.reversi.startWatching(matchID: ReversiWireHarness.watchedID)
        await off.barrier()
        #expect(off.reversi.spectating == nil, "스위치가 꺼졌는데 관전 상태가 섰다")
        #expect(off.count("reversi_watch_live") + off.count("reversi_watch") == 0, "스위치가 꺼졌는데 관전 조회가 나갔다")
        await off.tearDown()
    }

    // MARK: - ② 러너

    @Test("초인종: 'reversi' 한 번에 로비 조회 **한 번** · 메시지 조회로 안 샌다 · 러너 칸을 떼면 0건(기준선)")
    func theSignalReachesTheStore() async {
        let harness = ReversiWireHarness(label: "reversi-signal")
        harness.serve()
        await harness.signIn()
        harness.transport.emit(.joined)
        await harness.barrier()
        let before = harness.count("reversi_lobby")
        let activityBefore = harness.model.realtime.activityFlushCount
        harness.transport.emit(.broadcast(event: "reversi"))
        #expect(harness.model.realtime.effectLog.last == .reversiSignal, "링이 아잉 뒤집기 가지를 안 냈다")
        #expect(await waits.wait { harness.count("reversi_lobby") == before + 1 }, "초인종이 로비 조회가 안 됐다 — 받은 신청이 안 선다")
        await harness.barrier()
        #expect(harness.count("reversi_lobby") == before + 1, "초인종 한 번에 조회가 여러 건이다")
        harness.model.realtime.flushCoalescedSignals()
        #expect(harness.model.realtime.activityFlushCount == activityBefore, "아잉 뒤집기 초인종이 메시지 조회로 샜다")
        harness.model.realtime.reversi = nil
        harness.transport.emit(.broadcast(event: "reversi"))
        await harness.barrier()
        #expect(harness.count("reversi_lobby") == before + 1, "칸을 뗐는데 조회가 나갔다 — 이 시험이 아무것도 안 잰다")
        await harness.tearDown()
    }

    @Test("조인 따라잡기: `.catchUp` 이 아잉 뒤집기 로비를 한 번 읽는다 · 칸을 떼면 0건")
    func joinCatchesUp() async {
        let harness = ReversiWireHarness(label: "reversi-join")
        harness.serve()
        await harness.signIn()
        let before = harness.count("reversi_lobby")
        harness.transport.emit(.joined)
        harness.model.realtime.flushCoalescedSignals()
        #expect(harness.model.realtime.effectLog.contains(.catchUp), "조인이 따라잡기 effect 를 안 냈다")
        #expect(await waits.wait { harness.count("reversi_lobby") == before + 1 }, "조인 직후 로비를 안 읽었다")
        await harness.tearDown()

        let bare = ReversiWireHarness(label: "reversi-join-bare")
        bare.serve()
        await bare.signIn()
        bare.model.realtime.reversi = nil
        let bareBefore = bare.count("reversi_lobby")
        bare.transport.emit(.joined)
        await bare.barrier()
        #expect(bare.count("reversi_lobby") == bareBefore, "기준선이 안 갈린다 — 다른 길이 같은 조회를 낸다")
        await bare.tearDown()
    }

    // MARK: - ③ 화면 수명 · 앱 전환

    @Test("화면을 떠나면 진행 중인 관전이 내려가고(요청 0건) 끝난 판은 접힌다 · 진행 중인 내 판은 남는다 · 코어 숨김만 부른 기준선은 관전이 남는다")
    func leavingTheScreen() async {
        let harness = ReversiWireHarness(label: "reversi-leave")
        harness.serve(matches: true)
        await harness.signIn()
        harness.games.reversiScreenDidAppear()
        #expect(await waits.wait { !harness.reversi.liveMatches.isEmpty })
        harness.reversi.startWatching(matchID: ReversiWireHarness.watchedID)
        #expect(await waits.wait { harness.reversi.spectating?.blackUser != nil })
        await harness.barrier()
        let lobbyBefore = harness.count("reversi_lobby"), rankingBefore = harness.count("reversi_ranking")
        harness.games.reversiScreenDidDisappear()
        #expect(harness.reversi.spectating == nil, "화면을 떠났는데 진행 중인 관전이 남았다 — 다시 누르면 남의 판이 열린다")
        #expect(!harness.reversi.isWindowVisible && !harness.games.isReversiScreenVisible)
        await harness.barrier()
        #expect(harness.count("reversi_lobby") == lobbyBefore && harness.count("reversi_ranking") == rankingBefore,
                "떠나는 길에서 조회가 나갔다 — leaveWatch() 를 불렀다")
        harness.games.reversiScreenDidDisappear()      // 겹쳐 불려도 멱등
        #expect(harness.count("reversi_lobby") == lobbyBefore)

        // 진행 중인 내 판은 남는다(1:1 은 서버 시계로 흐른다 — 떠나는 것은 기권이 아니다).
        harness.games.reversiScreenDidAppear()
        await harness.loadMatch(owned: true)
        #expect(harness.reversi.phase == .playing)
        harness.games.reversiScreenDidDisappear()
        #expect(harness.reversi.match?.id == ReversiWireHarness.matchID && harness.reversi.phase == .playing, "진행 판을 접었다")
        // 끝난 판은 접는다 — 다시 들어올 때 결과가 다시 서지 않게.
        harness.games.reversiScreenDidAppear()
        await harness.loadMatch(status: "finished", owned: true)
        #expect(harness.reversi.phase == .result)
        harness.games.reversiScreenDidDisappear()
        #expect(harness.reversi.match == nil && harness.reversi.phase == .lobby, "끝난 판이 남았다 — 다시 누르면 결과가 선다")
        await harness.tearDown()

        let bare = ReversiWireHarness(label: "reversi-leave-bare")
        bare.serve(matches: true)
        await bare.signIn()
        bare.games.reversiScreenDidAppear()
        #expect(await waits.wait { !bare.reversi.liveMatches.isEmpty })
        bare.reversi.startWatching(matchID: ReversiWireHarness.watchedID)
        #expect(await waits.wait { bare.reversi.spectating?.blackUser != nil })
        // = 폰 훅에서 관전을 내리는 두 문(`stopWatching()` · `windowDidClose()`)을 **함께** 지운 것. 리버시 코어는 닫기 문도 관전을 내리므로
        //   한쪽만 지우면 초록이다(뮤테이션 실측 — `GamesStore.reversiScreenDidDisappear` 주석).
        bare.reversi.windowDidHide()
        #expect(bare.reversi.spectating != nil, "기준선이 안 갈린다 — 코어 숨김이 이미 내린다면 폰 훅은 아무것도 증명하지 않는다")
        await bare.tearDown()
    }

    @Test("앱을 잠깐 나간 것은 가림이다 — 관전·창은 남고 폴링만 멈춘다 · 돌아오면 가림이 풀려 폴링이 돈다")
    func backgroundIsOcclusion() async {
        let harness = ReversiWireHarness(label: "reversi-background")
        harness.serve(matches: true)
        await harness.signIn()
        harness.games.reversiScreenDidAppear()
        #expect(await waits.wait { !harness.reversi.liveMatches.isEmpty })
        harness.reversi.startWatching(matchID: ReversiWireHarness.watchedID)
        #expect(await waits.wait { harness.reversi.spectating?.blackUser != nil })
        harness.games.appDidEnterBackground()
        #expect(harness.reversi.spectating != nil, "background 가 관전을 끊었다 — 가림이 아니라 숨김을 불렀다")
        #expect(harness.reversi.isWindowVisible && harness.reversi.isWindowOccluded, "가림이 아니다")
        #expect(harness.reversi.pollTask == nil, "가림인데 폴링이 계속 돈다")
        let lobbyBefore = harness.count("reversi_lobby")
        harness.games.appDidBecomeActive()
        #expect(!harness.reversi.isWindowOccluded)
        #expect(await waits.wait { harness.reversi.pollTask != nil }, "돌아왔는데 폴링이 안 돌아왔다")
        #expect(await waits.wait { harness.count("reversi_lobby") > lobbyBefore }, "돌아와서 놓친 것을 안 읽었다(catchUp)")
        await harness.tearDown()
    }

    @Test("화면 밖 앱 복귀: 로비를 30초 스로틀로 한 번 읽는다(받은 신청·한 사람 한 판) · 스로틀 안이면 0건")
    func becomingActiveOffScreenUsesTheThrottle() async {
        let harness = ReversiWireHarness(label: "reversi-active-offscreen")
        harness.serve(incoming: true)
        await harness.signIn()
        harness.reversi.lastMenuLobbyAt = .distantPast
        let before = harness.count("reversi_lobby")
        harness.games.appDidBecomeActive()
        #expect(await waits.wait { harness.count("reversi_lobby") == before + 1 }, "화면 밖에서 돌아왔는데 받은 신청을 못 읽었다")
        #expect(!harness.reversi.isWindowVisible, "화면이 없는데 창을 세웠다 — 보이지 않는 판에 폴링이 돈다")
        harness.games.appDidBecomeActive()
        await harness.barrier()
        #expect(harness.count("reversi_lobby") == before + 1, "스로틀이 안 걸렸다 — 로비(사람마다 capable)가 복귀마다 나간다")
        harness.clock.advance(31)
        harness.games.appDidBecomeActive()
        #expect(await waits.wait { harness.count("reversi_lobby") == before + 2 }, "30초가 지났는데 다시 안 읽는다")
        await harness.tearDown()
    }

    // MARK: - 허브 · 탭 배지 · 차단 거울

    @Test("허브: 로비를 30초 스로틀로 읽어 받은 신청이 카드 칩·탭 배지에 선다 · 오목 카드 재료에 안 섞인다 · 차단한 사람의 신청은 안 센다")
    func hubAndBadge() async {
        let harness = ReversiWireHarness(label: "reversi-hub")
        harness.serve(incoming: true)
        await harness.signIn()
        harness.reversi.lastMenuLobbyAt = .distantPast
        let before = harness.count("reversi_lobby")
        harness.games.hubDidAppear()
        #expect(await waits.wait { harness.count("reversi_lobby") == before + 1 }, "허브가 아잉 뒤집기 로비를 안 읽었다")
        harness.games.hubDidAppear()
        await harness.barrier()
        #expect(harness.count("reversi_lobby") == before + 1, "허브 스로틀이 안 걸렸다")
        #expect(harness.games.badgeCount == 1, "받은 신청이 탭 배지에 없다")
        #expect(harness.model.badges.games == 1)
        #expect(harness.games.gomokuIncomingCount == 0, "오목 카드 재료에 리버시 신청이 섞였다")
        #expect(GamesReversiCard.line(harness.games) == .incoming)
        #expect(GamesReversiCard.chip(harness.games) == "받은 신청 1건")
        // 차단 거울: 메시지 탭의 차단 목록이 허브에서 코어로 넘어간다 — 배지·상대 목록이 그 사람을 거른다.
        harness.model.messages.hiddenBlockedPeerIDs = [ReversiWireHarness.rival.uppercased()]
        #expect(harness.games.reversiLobbyUsers.allSatisfy { $0.id != ReversiWireHarness.rival }, "막 차단한 사람이 상대 목록에 남았다")
        #expect(harness.games.badgeCount == 1, "기준선: 거울을 맞추기 전에는 코어가 아직 모른다")
        harness.games.hubDidAppear()
        #expect(harness.reversi.hiddenPeerIDs == [ReversiWireHarness.rival], "차단 거울이 소문자 id 로 안 넘어갔다")
        #expect(harness.games.badgeCount == 0, "차단한 사람의 신청이 탭 배지에 남았다")
        await harness.tearDown()
    }

    @Test("카드 서열: 차단 > 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 — AI 연습 판은 받은 신청을 가리지 않는다")
    func cardOrder() async {
        let harness = ReversiWireHarness(label: "reversi-card")
        harness.serve()
        await harness.signIn()
        let games = harness.games, reversi = harness.reversi
        reversi.record = nil
        #expect(GamesReversiCard.line(games) == .idle)
        #expect(GamesReversiCard.detail(games) == ReversiPhoneText.idleLine && GamesReversiCard.chip(games) == nil)
        reversi.record = ReversiRecord(wins: 2, losses: 1, draws: 0)
        #expect(GamesReversiCard.line(games) == .record)
        #expect(GamesReversiCard.detail(games) == "내 전적 2승 1패 0무")
        let rival = ReversiUser(id: ReversiWireHarness.rival, displayName: "뒤집기라이벌")
        reversi.outgoing = ReversiOutgoing(id: "m-out", peer: rival, stake: 5, expiresAt: harness.clock.now.addingTimeInterval(60))
        #expect(GamesReversiCard.line(games) == .outgoing && GamesReversiCard.detail(games) == ReversiPhoneText.outgoingLine)
        reversi.incoming = [ReversiInvite(id: "m-in", peer: rival, stake: 5, expiresAt: harness.clock.now.addingTimeInterval(60))]
        #expect(GamesReversiCard.line(games) == .incoming, "받은 신청이 보낸 신청 뒤에 섰다")
        reversi.outgoing = nil
        // AI 연습 판: 받은 신청이 있으면 그쪽을 먼저 말한다(루비가 걸린 진짜 대결) · 없으면 '대국 중'.
        reversi.startAIMatch(humanColor: .black)
        #expect(reversi.isAIMatch)
        #expect(GamesReversiCard.line(games) == .incoming, "AI 연습 판이 사람의 신청을 가렸다")
        reversi.incoming = []
        #expect(GamesReversiCard.line(games) == .activeMatch && GamesReversiCard.chip(games) == GamesText.activeMatchChip)
        #expect(games.reversiEntryBlock == nil && games.gomokuEntryBlock == nil, "AI 연습 판이 입구를 막았다")
        await reversi.resign()
        reversi.backToLobby()
        // 다른 게임 판 → 막힘(칩 = 왜 · 보조 줄 = 언제).
        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(GamesReversiCard.line(games) == .blocked)
        #expect(GamesReversiCard.chip(games) == "오목을 두는 중이에요")
        #expect(GamesReversiCard.detail(games) == "오목 판이 끝나면 아잉 뒤집기를 신청할 수 있어요")
        harness.model.gomoku.match = nil
        await harness.tearDown()
    }

    // MARK: - 다섯 방향

    @Test("한 사람 한 판: 리버시 1:1 판이 흐르면 네 입구가 막히고 그 이름을 말한다 · 끝난 판·AI 판은 안 막는다 · 서버 id 만 알아도 막는다")
    func reversiBlocksTheOtherFour() async {
        let harness = ReversiWireHarness(label: "reversi-blocks")
        harness.serve()
        await harness.signIn()
        let games = harness.games
        func otherFour() -> [GamesBusyGame?] { [games.gomokuEntryBlock, games.chessEntryBlock, games.tetrisEntryBlock, games.rummyEntryBlock] }
        #expect(otherFour().allSatisfy { $0 == nil })
        await harness.loadMatch(owned: false)
        #expect(otherFour().allSatisfy { $0 == .reversi }, "리버시 판(같은 계정 다른 기기 판 포함)이 흐르는데 열린 입구가 있다: \(otherFour())")
        #expect(games.reversiEntryBlock == nil, "자기 입구를 자기가 막는다")
        await harness.loadMatch(status: "finished", owned: false)
        #expect(otherFour().allSatisfy { $0 == nil }, "끝난 판이 입구를 막는다")
        harness.reversi.backToLobby()
        await harness.barrier()
        #expect(harness.reversi.match == nil && otherFour().allSatisfy { $0 == nil })
        // 서버가 말한 id 만 안다(판을 못 읽었다) — 닫는 쪽으로 틀린다.
        harness.server.setDefault("reversi_state") { _ in .networkFailure() }
        harness.server.setDefault("reversi_lobby", json: ReversiWireJSON.lobby(nowMs: harness.nowMs, activeMatchID: ReversiWireHarness.matchID))
        await harness.reversi.refreshLobby()
        #expect(await waits.wait { harness.reversi.activeMatchID == ReversiWireHarness.matchID })
        await harness.barrier()
        #expect(harness.reversi.match == nil, "전제: 판은 못 읽었다")
        #expect(games.gomokuEntryBlock == .reversi, "그 틈에 오목 입구가 열려 있다 — 오목을 수락하면 리버시가 자동 착수 3번으로 진다")
        #expect(GamesBusyGame.reversi.text == .reversi)
        #expect(GamesBusyGame.allCases.count == 5)
        await harness.tearDown()
    }

    @Test("한 사람 한 판: 다른 넷 중 하나의 판이 흐르면 리버시 입구가 막힌다(넷 다 · 그 이름으로) · 끝난 판은 안 막는다")
    func theOtherFourBlockReversi() async {
        let harness = ReversiWireHarness(label: "reversi-blocked")
        harness.serve()
        await harness.signIn()
        let games = harness.games
        #expect(games.reversiEntryBlock == nil)
        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(games.reversiEntryBlock == .gomoku)
        harness.model.gomoku.match = Self.gomokuMatch(finished: true)
        #expect(games.reversiEntryBlock == nil, "끝난 오목 판이 리버시 입구를 막았다")
        harness.model.gomoku.match = nil
        harness.model.chess.match = Self.chessMatch()
        #expect(games.reversiEntryBlock == .chess)
        harness.model.chess.match = nil
        harness.server.setDefault("tetris_state") { _ in .networkFailure() }
        harness.server.setDefault("tetris_lobby", json: TetrisWireJSON.lobby(nowMs: harness.nowMs, activeMatchID: "m-t"))
        await games.tetris.refreshLobby()
        #expect(games.reversiEntryBlock == .tetris, "테트리스 중인데 리버시 입구가 열려 있다")
        harness.server.setDefault("tetris_lobby", json: TetrisWireJSON.lobby(nowMs: harness.nowMs))
        await games.tetris.refreshLobby()
        #expect(games.reversiEntryBlock == nil)
        harness.server.setDefault("rummy_state") { _ in .networkFailure() }
        harness.server.setDefault("rummy_lobby", json: RummyWireJSON.lobby(nowMs: harness.nowMs, activeMatchID: RummyWireHarness.matchID))
        await games.rummy.refreshLobby()
        #expect(games.reversiEntryBlock == .rummy, "아잉 큐브 판인데 리버시 입구가 열려 있다")
        await harness.tearDown()
    }

    // MARK: - 판 시작 문 · 화면 꺼짐 · 배너

    @Test("판 시작 문: 이 기기가 연 판이 서면 게임 탭에 리버시 화면을 쌓는다(한 장만) · 다른 기기 판은 끌어 올리지 않는다(기준선)")
    func presentWindowOpensTheScreenOnlyForOwnedMatches() async {
        let harness = ReversiWireHarness(label: "reversi-present")
        harness.serve()
        await harness.signIn()
        let router = harness.model.router
        router.selectedTab = .me
        #expect(router.path(for: .games).isEmpty)
        await harness.loadMatch(owned: true)
        #expect(router.selectedTab == .games && router.path(for: .games).count == 1, "판이 섰는데 화면을 안 열었다 — 흑 30초를 흘린다")
        harness.games.reversiScreenDidAppear()      // 쌓인 화면이 섰다 — 그 안의 openWindow 가 문을 또 부른다
        #expect(router.path(for: .games).count == 1, "화면이 보이는데 또 쌓았다")
        await harness.tearDown()

        let other = ReversiWireHarness(label: "reversi-present-other")
        other.serve()
        await other.signIn()
        other.model.router.selectedTab = .me
        await other.loadMatch(owned: false)
        #expect(other.reversi.match?.id == ReversiWireHarness.matchID, "전제: 판은 읽었다")
        #expect(other.model.router.selectedTab == .me && other.model.router.path(for: .games).isEmpty,
                "같은 계정 다른 기기의 판이 폰 화면을 끌어 올렸다")
        await other.tearDown()
    }

    @Test("화면 꺼짐 방지: 이 기기가 연 1:1 판은 어느 화면에서든 켠다 · 다른 기기 판은 안 켠다 · AI 연습은 화면이 보일 때만")
    func idleTimerFollowsOwnedMatches() async {
        let harness = ReversiWireHarness(label: "reversi-idle")
        harness.serve()
        await harness.signIn()
        #expect(!harness.games.wantsIdleTimerDisabled)
        await harness.loadMatch(owned: true)
        #expect(harness.games.wantsIdleTimerDisabled, "이 기기 판인데 자동잠금이 닿는다 — 서버가 대신 둔 수가 쌓인다")
        await harness.tearDown()

        let other = ReversiWireHarness(label: "reversi-idle-other")
        other.serve()
        await other.signIn()
        await other.loadMatch(owned: false)
        #expect(other.reversi.match?.isFinished == false, "전제: 진행 판을 들고 있다")
        #expect(!other.games.wantsIdleTimerDisabled, "다른 기기 판인데 화면을 켜 둔다 — 배터리만 탄다")
        // AI 연습: 화면이 보일 때만.
        await other.loadMatch(status: "finished", owned: false)
        other.reversi.backToLobby()
        other.reversi.startAIMatch(humanColor: .black)
        #expect(other.reversi.isAIMatch)
        #expect(!other.games.wantsIdleTimerDisabled, "화면 밖 AI 판인데 화면을 켜 둔다(시계가 멈춰 있다)")
        other.games.reversiScreenDidAppear()
        #expect(other.games.wantsIdleTimerDisabled, "AI 판을 보는 중인데 자동잠금이 닿는다")
        await other.tearDown()
    }

    @Test("배너 미룸: 리버시 화면이 서면 미루고 떠나면 푼다 · 다른 기기 판을 들고 있어도 화면 밖이면 안 미룬다(코어 깃발과 갈린다)")
    func bannerDeferral() async {
        let harness = ReversiWireHarness(label: "reversi-banner")
        harness.serve()
        await harness.signIn()
        #expect(!harness.games.isAnyMatchScreenVisible)
        harness.games.reversiScreenDidAppear()
        #expect(harness.games.isAnyMatchScreenVisible && harness.model.isMegaphoneBannerDeferred, "판 화면 위에 배너가 덮인다")
        harness.games.reversiScreenDidDisappear()
        #expect(!harness.games.isAnyMatchScreenVisible)
        await harness.loadMatch(owned: false)
        #expect(harness.reversi.defersMegaphoneBanner, "기준선: 코어 깃발은 맥이 두는 판에도 참이다")
        #expect(!harness.games.isAnyMatchScreenVisible, "맥이 한 판 두는 동안 폰 배너가 통째로 멎는다")
        await harness.tearDown()
    }

    // MARK: - 로그아웃 · 판 끝

    @Test("로그아웃 사슬: 다음 계정에 신청·판·전적이 남지 않는다 · 배선 값은 그대로다")
    func signOutChain() async {
        let harness = ReversiWireHarness(label: "reversi-signout")
        harness.serve(incoming: true)
        await harness.signIn()
        harness.games.hubDidAppear()
        #expect(await waits.wait { !harness.reversi.incoming.isEmpty && harness.reversi.record != nil })
        await harness.loadMatch(owned: true)
        #expect(harness.reversi.match != nil)
        await harness.model.session.signOut()
        #expect(harness.reversi.match == nil && harness.reversi.incoming.isEmpty && harness.reversi.record == nil,
                "로그아웃했는데 앞 사람의 판·신청·전적이 남았다")
        #expect(harness.reversi.activeMatchID == nil && harness.games.badgeCount == 0)
        #expect(harness.reversi.rankingEnabled && harness.reversi.spectatorFeaturesEnabled && harness.reversi.presentWindow != nil,
                "로그아웃이 배선 값을 건드렸다 — 재로그인하면 순위·관전·판 시작 문이 죽는다")
        await harness.tearDown()
    }

    @Test("판 끝: 1:1 판의 끝을 처음 본 순간 미션을 묻는다(한 번) · AI 판 끝은 안 묻는다 · 오늘 채운 줄이면 0건 — 이름이 서버 값과 다르면 값이 바뀐다")
    func finishAsksMissions() async {
        let harness = ReversiWireHarness(label: "reversi-mission")
        harness.serve()
        harness.server.setDefault("achievements_status", json: Self.missionStatus(reversiDone: false))
        await harness.signIn()
        await harness.model.me.loadAchievements()
        await harness.barrier()
        let before = harness.count("achievements_status")
        #expect(before >= 1)
        // AI 연습 판의 끝은 미션이 아니다(서버가 안 센다).
        harness.reversi.startAIMatch(humanColor: .black)
        await harness.reversi.resign()
        await harness.barrier()
        #expect(harness.reversi.match?.isFinished == true && harness.reversi.isAIMatch)
        #expect(harness.count("achievements_status") == before, "AI 연습 판이 끝났는데 미션을 물었다")
        harness.reversi.backToLobby()
        await harness.loadMatch(owned: true)
        await harness.barrier()
        #expect(harness.count("achievements_status") == before, "판 중에 미션을 물었다")
        await harness.loadMatch(status: "finished", owned: true)
        #expect(await waits.wait { harness.count("achievements_status") == before + 1 }, "판이 끝났는데 미션을 안 물었다 — [받기]가 안 뜬다")
        await harness.reversi.refreshMatch(id: ReversiWireHarness.matchID)
        await harness.barrier()
        #expect(harness.count("achievements_status") == before + 1, "같은 판의 끝을 또 세었다")
        await harness.tearDown()

        let done = ReversiWireHarness(label: "reversi-mission-done")
        done.serve()
        done.server.setDefault("achievements_status", json: Self.missionStatus(reversiDone: true))
        await done.signIn()
        await done.model.me.loadAchievements()
        await done.barrier()
        let doneBefore = done.count("achievements_status")
        await done.loadMatch(owned: true)
        await done.loadMatch(status: "finished", owned: true)
        await done.barrier()
        #expect(done.count("achievements_status") == doneBefore, "오늘 채운 줄인데 또 물었다 — 게임 이름이 서버 값(`reversi`)이 아니다")
        await done.tearDown()
    }

    private static func missionStatus(reversiDone: Bool) -> String {
        typealias Daily = MeDailyMissionStoreTests
        let row = Daily.dailyRow(.init(key: "daily_reversi", game: "reversi", title: "아잉 뒤집기 한 판 하기", sort: 80),
                                 done: reversiDone, claimed: false)
        let daily = #"{"kst_day":"2026-09-17","reset_at_ms":\#(Daily.resetMs),"missions":[\#(row)],"claimable_count":\#(reversiDone ? 1 : 0),"claimable_ruby":\#(reversiDone ? 5 : 0)}"#
        return Daily.status(dailyJSON: daily)
    }

    // MARK: - 화면이 부를 판정(뷰 밖)

    @Test("[도전] 게이트: 다른 게임 판 · 상대 대국 중 · 집중 · capable 모름 · 보낸 신청 · 내 판(AI 포함) · 서버가 말한 판을 모두 막는다")
    func challengeGate() async {
        let harness = ReversiWireHarness(label: "reversi-gate")
        harness.serve()
        await harness.signIn()
        let store = harness.reversi
        let ok = ReversiUser(id: ReversiWireHarness.rival, displayName: "뒤집기라이벌")
        #expect(GamesReversiChallengeGate.isEnabled(user: ok, store: store, blockedBy: nil), "기준선: 막을 까닭이 없는데 막혔다")
        #expect(!GamesReversiChallengeGate.isEnabled(user: ok, store: store, blockedBy: .gomoku))
        var busy = ok; busy.inMatch = true
        var focused = ok; focused.focusMode = true
        var old = ok; old.isCapable = false
        for user in [busy, focused, old] {
            #expect(!GamesReversiChallengeGate.isEnabled(user: user, store: store, blockedBy: nil), "막아야 할 상대가 열렸다: \(user)")
        }
        // capable 이 서버에서 null 이면 불가로 읽는다(코어 매퍼) — 로비 픽스처의 '구버전'.
        #expect(store.users.first { $0.id == ReversiWireHarness.thirdID }?.isCapable == false)
        store.outgoing = ReversiOutgoing(id: "m-out", peer: ok, stake: 3, expiresAt: harness.clock.now.addingTimeInterval(60))
        #expect(!GamesReversiChallengeGate.isEnabled(user: ok, store: store, blockedBy: nil), "보낸 신청이 있는데 또 신청한다")
        store.outgoing = nil
        store.startAIMatch(humanColor: .black)
        #expect(!GamesReversiChallengeGate.isEnabled(user: ok, store: store, blockedBy: nil),
                "AI 연습 중인데 신청이 나간다 — 수락되는 순간 두던 판이 말없이 사라진다")
        #expect(harness.games.hasLiveReversiAIGame)
        #expect(GamesReversiStakeSend.sendable(.three, store: store, balance: 100, blockedBy: nil) == nil, "AI 판 중인데 판돈 시트가 신청을 낸다")
        await store.resign()
        store.backToLobby()
        #expect(!harness.games.hasLiveReversiAIGame)
        store.activeMatchID = ReversiWireHarness.matchID
        #expect(!GamesReversiChallengeGate.isEnabled(user: ok, store: store, blockedBy: nil), "서버가 말한 내 판이 있는데 신청한다")
        store.activeMatchID = nil
        await harness.tearDown()
    }

    @Test("판돈 시트 마지막 문: 안 고름 · 모자람 · 다른 게임 판 · 보낸 신청 · 요청 중이면 nil · 잔액을 모르면 막지 않는다")
    func stakeSend() async {
        let harness = ReversiWireHarness(label: "reversi-stake")
        harness.serve()
        await harness.signIn()
        let store = harness.reversi
        #expect(GamesReversiStakeSend.sendable(.five, store: store, balance: 100, blockedBy: nil) == .five, "기준선")
        #expect(GamesReversiStakeSend.sendable(nil, store: store, balance: 100, blockedBy: nil) == nil, "안 골랐는데 신청이 나간다")
        #expect(GamesReversiStakeSend.sendable(.ten, store: store, balance: 9, blockedBy: nil) == nil, "모자란데 신청이 나간다")
        #expect(GamesReversiStakeSend.sendable(.ten, store: store, balance: nil, blockedBy: nil) == .ten, "잔액을 모르는데 막았다(맥 0.3.29 규칙)")
        #expect(GamesReversiStakeSend.sendable(.three, store: store, balance: 100, blockedBy: .tetris) == nil)
        store.isBusy = true
        #expect(GamesReversiStakeSend.sendable(.three, store: store, balance: 100, blockedBy: nil) == nil)
        store.isBusy = false
        #expect(ReversiStake.allCases.map(\.rawValue) == [3, 5, 10], "판돈 셋은 서버 CHECK 와 같다")
        await harness.tearDown()
    }
}
