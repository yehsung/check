@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **1:1 테트리스 배선**(1.0.11 레인 A)의 못. 재는 것 여섯 — 모두 **결과 숫자**다(함수를 불렀는지가 아니라
// 요청이 몇 건 나갔는지 · 값이 어떻게 바뀌었는지).
//
//  ① **실시간 초인종** — 'tetris' 한 번에 판 상태 조회가 **정확히 한 번**. 러너 칸(`realtime.tetris`)을 떼면 0건이다.
//  ② **조인 따라잡기**(`.catchUp`) — 로비가 한 번. 같은 기준선으로 나란히 본다.
//  ③ **화면 수명** — 주 스위치는 `windowDidShow()` 이고, 그 결과로 재는 것은 깃발이 아니라 **준비 보고가 나가는지**다
//     (코어 머리말 ⑨: 준비 = 첫 보고, 창이 떠 있을 때만 낸다). 떠나는 길은 **요청 0건**이고 기권이 아니다.
//  ④ **P8 깨어남** — 화면이 보이면 가림 해제/`windowDidShow` + `catchUp`, 안 보이면 `systemDidWake`.
//     로비 조회는 어느 가지에서도 **한 번**이고, 가지를 뒤집으면 **보이지 않는 판의 준비 보고**가 나간다.
//  ⑤ **한 사람 한 판은 삼각**(P3) — 세 방향 × (흐르는 판은 막고 · 끝난 판은 안 막는다). 딥링크도 같은 값을 본다.
//  ⑥ **로그아웃** — 다음 계정에 앞 사람의 판·신청·순위·루비가 남지 않는다.
//
// ── 왜 이 파일이 따로 있는가 ──
// 테트리스 화면은 전부 `#if os(iOS)` 안이라 **맥 스위트가 한 줄도 못 본다**(저장소 메모 '폰 뷰는 맥 스위트가 못
// 본다'). 그런데 그 화면을 통째로 죽이는 원인은 뷰가 아니라 배선 몇 줄이다 — 그래서 판정은 플랫폼 분기가 없는
// 자리(`GamesStore` · `MobileRealtimeRunner` · `MobileAppModel`)에 두고 여기서 값으로 잰다.
// `GamesTetrisWiringTests`(이름이 비슷하다)는 **솔로** 테트리스 것이다 — 섞지 마라.
//
// 하네스는 `GamesHarness` 를 베꼈지만 **소켓이 있다**(`BaseFakeTransport`) — 초인종·조인 따라잡기를 실제 effect 로
// 흘려야 ①②가 "핸들러를 불렀나"가 아니라 "요청이 나갔나"가 된다. `GamesTestSupport` 는 남의 파일이라 고치지 않았다.

// MARK: - 하네스 (소켓이 붙은 로그인된 앱 모델 하나)

@MainActor
final class TetrisWireHarness {
    nonisolated static let userID = "u-games"
    nonisolated static let rival = "p-tetris-rival"
    nonisolated static let matchID = "m-tetris-1"

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
            BaseStub.authResponse(access: fresh, refresh: "r-tetris", userID: TetrisWireHarness.userID)
        }
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: server.host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-66666666bbbb",
            realtimeTransport: transport,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        // 메시지 활동 합치기 창은 테스트가 직접 닫는다 — `.catchUp` 이 메시지 조회까지 끌고 가면 셈이 흐려진다.
        model.realtime.coalesceSeconds = 3_600
    }

    var games: GamesStore { model.games }
    var tetris: TetrisDuelStore { model.tetris }
    var serverNowMs: Int { Int(clock.now.timeIntervalSince1970 * 1000) }
    var violations: [String] { MobileForbiddenCalls.violations(in: server.requests) }

    func count(_ rpc: String) -> Int { server.requests(rpc).count }

    func barrier() async { await baseBarrier(model.context.service) }

    /// 실행 → 로그아웃 상태 → active → 로그인. (로그인 직후 `activateStores()` 가 돌므로 테트리스 로비가
    /// **여기서 이미 한 번** 나간다 — P8 의 '안 보이는 가지'. 그래서 셈은 전부 '지금부터' 기준으로 잰다.)
    func signIn() async {
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedOut }
        model.sceneDidBecomeActive()
        await model.session.signIn(email: "tetris@aing.invalid", password: "pw")
    }

    func tearDown() async {
        if model.session.isSignedIn { await model.session.signOut() }
        model.gomoku.reset()
        model.tetris.reset()
        BaseStub.tearDown(host: server.host, storage: storage)
    }
}

// MARK: - 픽스처 (서버 모양 그대로 — SPEC-tetris §2.4·§2.5 의 키)

enum TetrisWireJSON {
    static func user(_ id: String, _ name: String, working: Bool = true, capable: Bool? = true,
                     inMatch: Bool = false, focused: Bool = false) -> String {
        let capableValue = capable.map { $0 ? "true" : "false" } ?? "null"
        return #"{"id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"is_working":\#(working),"in_match":\#(inMatch),"capable":\#(capableValue),"focus_mode":\#(focused)}"#
    }

    static func invite(_ id: String, peerKey: String, nowMs: Int, stake: Int = 3) -> String {
        #"{"match_id":"\#(id)","\#(peerKey)":{"id":"\#(TetrisWireHarness.rival)","display_name":"테트라이벌"},"stake":\#(stake),"expires_at_ms":\#(nowMs + 60_000)}"#
    }

    /// `tetris_lobby` 한 벌. `me` 의 세 자리는 전부 빈 값이 기본이다(받은·보낸 신청·진행 판 없음).
    static func lobby(nowMs: Int, activeMatchID: String? = nil, incoming: [String] = [],
                      outgoing: String? = nil, users: [String]? = nil) -> String {
        let rows = users ?? [user(rivalID, "테트라이벌"), user("p-tetris-old", "구버전", capable: false)]
        let active = activeMatchID.map { "\"\($0)\"" } ?? "null"
        let out = outgoing ?? "null"
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"invite_ttl_seconds":60,"me":{"ruby_balance":100,"wins":2,"losses":1,"draws":0,"active_match_id":\#(active),"incoming":[\#(incoming.joined(separator: ","))],"outgoing":\#(out)},"users":[\#(rows.joined(separator: ","))],"matches":[]}"#
    }

    static func player(_ id: String, _ name: String, ready: Bool = false, seq: Int = 0,
                       sent: Int = 0, toppedOut: Bool = false) -> String {
        #"{"id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"ready":\#(ready),"seq":\#(seq),"board":null,"lines":0,"garbage_sent":\#(sent),"garbage_applied":0,"pending":0,"last_seen_ms":null,"topped_out":\#(toppedOut)}"#
    }

    /// §2.5 상태 한 벌을 **`state` 봉투에 담아** 돌려준다(펼치지 않는다 — 와이어 계약).
    /// `myDevice` 기본 'this' = 이 폰이 두는 판(서버 20261103124000 의 my_device — 코어 머리말 ⑩). nil 이면 키를 안 싣는다(옛 서버).
    static func stateEnvelope(nowMs: Int, id: String = TetrisWireHarness.matchID, status: String = "active",
                              startAtMs: Int? = nil, meReady: Bool = false, opponentSent: Int = 0,
                              result: String? = nil, winner: String? = nil, endReason: String? = nil,
                              myDevice: String? = "this") -> String {
        let start = startAtMs.map { "\($0)" } ?? "null"
        let maxEnd = startAtMs.map { "\($0 + 480_000)" } ?? "null"
        let finished = status == "finished" ? "\(nowMs)" : "null"
        let resultValue = result.map { "\"\($0)\"" } ?? "null"
        let winnerValue = winner.map { "\"\($0)\"" } ?? "null"
        let reasonValue = endReason.map { "\"\($0)\"" } ?? "null"
        let device = myDevice.map { #","my_device":"\#($0)""# } ?? ""
        let state = #"{"match_id":"\#(id)","status":"\#(status)","stake":5,"seed":4242,"server_now_ms":\#(nowMs),"accepted_at_ms":\#(nowMs - 2_000),"start_at_ms":\#(start),"ready_deadline_ms":\#(nowMs + 28_000),"max_end_ms":\#(maxEnd),"finished_at_ms":\#(finished),"me":\#(player(TetrisWireHarness.userID, "나", ready: meReady)),"opponent":\#(player(rivalID, "테트라이벌", ready: true, seq: 3, sent: opponentSent)),"result":\#(resultValue),"winner":\#(winnerValue),"end_reason":\#(reasonValue),"ruby_balance":97\#(device)}"#
        return #"{"status":"ok","state":\#(state)}"#
    }

    static func ranking(nowMs: Int) -> String {
        let rows = [
            #"{"rank":1,"id":"\#(rivalID)","display_name":"테트라이벌","avatar_url":null,"character":"jelly","wins":5,"losses":1,"draws":0,"points":4}"#,
            #"{"rank":2,"id":"\#(TetrisWireHarness.userID)","display_name":"나","avatar_url":null,"character":"aing","wins":2,"losses":1,"draws":0,"points":1}"#,
        ]
        return #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":{"rank":2,"wins":2,"losses":1,"draws":0,"points":1},"rows":[\#(rows.joined(separator: ","))]}"#
    }

    private static var rivalID: String { TetrisWireHarness.rival }
}

@MainActor
@Suite(.serialized) struct GamesTetrisDuelWiringTests {
    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    private nonisolated static let mine = TetrisWireHarness.userID
    private nonisolated static let rival = TetrisWireHarness.rival
    private nonisolated static let matchID = TetrisWireHarness.matchID

    /// 테트리스 화면이 부르는 조회 + 옆 게임 조회(허브·active 가 함께 부른다)를 스텁에 걸어 둔다.
    private func serve(_ harness: TetrisWireHarness, activeMatchID: String? = nil, incoming: [String] = [],
                       outgoing: String? = nil) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("tetris_lobby", json: TetrisWireJSON.lobby(
            nowMs: nowMs, activeMatchID: activeMatchID, incoming: incoming, outgoing: outgoing))
        harness.server.setDefault("tetris_state", json: TetrisWireJSON.stateEnvelope(nowMs: nowMs))
        harness.server.setDefault("tetris_ranking", json: TetrisWireJSON.ranking(nowMs: nowMs))
        harness.server.setDefault("tetris_report", json: TetrisWireJSON.stateEnvelope(nowMs: nowMs, meReady: true))
        harness.server.setDefault("chess_lobby", json: #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"invite_ttl_seconds":60,"ruby_balance":100,"me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0,"active_match_id":null,"outgoing_match_id":null,"incoming_match_id":null},"users":[],"matches":[]}"#)
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
    }

    /// 상태 응답 한 벌을 **스토어에 직접 꽂는다**(서버 왕복 없이 '판이 흐르는 중'을 세운다 — 판 구동기까지 선다).
    @discardableResult
    private func applyLiveState(_ harness: TetrisWireHarness, startAtMs: Int? = nil,
                                meReady: Bool = false) -> Bool {
        let text = TetrisWireJSON.stateEnvelope(nowMs: harness.serverNowMs, startAtMs: startAtMs, meReady: meReady)
        guard let payload = Self.decodeState(text) else {
            Issue.record("상태 픽스처가 와이어와 어긋난다 — 이 테스트의 전제를 못 세웠다")
            return false
        }
        return harness.tetris.applyState(payload) == .applied
    }

    private nonisolated static func decodeState(_ text: String) -> TetrisStatePayload? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(TetrisActionResponse.self, from: Data(text.utf8)))?.state
    }

    // MARK: - 판 조각 (다른 게임의 '흐르는 판')

    private nonisolated static func tetrisMatch(id: String = matchID, finished: Bool = false)
        -> TetrisDuelMatchState {
        TetrisDuelMatchState(
            id: id, stake: 5, seed: 4_242,
            opponent: TetrisDuelUser(id: rival, displayName: "테트라이벌", avatarURL: nil, characterID: nil,
                                     isWorking: true, isCapable: true, inMatch: !finished),
            acceptedAt: nil, readyDeadline: nil, startAt: nil, maxEnd: nil, meReady: false,
            opponentBoard: .empty, isFinished: finished,
            outcome: finished ? .won : nil, endReason: finished ? .topout : nil,
            rubyDelta: finished ? 4 : nil, finishedAt: nil)
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

    private nonisolated static func gomokuMatch(finished: Bool = false) -> GomokuMatchState {
        GomokuMatchState(
            id: "g-1", stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p-1", displayName: "구름빵", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: true),
            board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: finished ? nil : .black, deadline: nil,
            isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    // MARK: - 1. 배선 (물린 자리가 **같은 인스턴스**인가)

    @Test("폰 배선이 테트리스 스토어를 네 자리에 같은 인스턴스로 물린다 — 순위 스위치 · 러너 칸 · 화면 문 · 공유 호스트")
    func phoneWiringAttachesTheOneTetrisStore() async {
        // 없으면: 깃발만 참이고 화면·러너는 딴 인스턴스를 보는 상태가 아래 모든 테스트를 **초록인 채로** 무의미하게 만든다.
        let harness = TetrisWireHarness(label: "tetris-attach")
        let model = harness.model
        #expect(model.tetris.rankingEnabled, "배선이 rankingEnabled 를 안 켰다 — 순위 탭이 영영 로딩 문구다")
        #expect(model.context.tetris === model.tetris, "탭 스토어가 보는 테트리스 스토어가 딴 인스턴스다")
        #expect(harness.games.tetris === model.tetris, "GamesStore.tetris 가 딴 인스턴스다")
        #expect(model.realtime.tetris === model.tetris, "러너의 테트리스 칸이 비었거나 딴 인스턴스다 — 초인종이 죽는다")
        #expect(model.tetris.host === model.gomokuHost, "테트리스 호스트가 오목·체스와 다르다 — 루비 미러가 갈린다")
        #expect(model.tetris.presentWindow != nil,
                "코어의 화면 여는 문이 안 물렸다 — 수락·시작이 화면을 못 열고 준비 보고가 30초를 흘린다")
        // 배선 값은 로그아웃 reset 이 건드리지 않는다(재로그인 뒤에도 순위·문이 살아야 한다).
        model.tetris.reset()
        #expect(model.tetris.rankingEnabled, "reset 이 배선 값을 껐다")
        #expect(model.tetris.presentWindow != nil, "reset 이 화면 문을 떼었다")
        await harness.tearDown()
    }

    // MARK: - 2. 초인종 (요구 1 — 한 번에 한 번)

    @Test("실시간 'tetris' 초인종 한 번 → 판 상태 조회가 **정확히 한 번**. 러너 칸을 떼면 같은 초인종에 0건이다")
    func oneDoorbellMakesExactlyOneStateQuery() async {
        // 없으면(가지가 `break` 인 채): 맥 대 폰 판에서 폰만 방해 줄을 자기 보고 왕복(1초)까지 늦게 받는다.
        // 상쇄는 '줄을 안 지운 다음 굳힘'에서 일어나므로 1초는 한 조각을 잘못 놓게 만든다.
        // 두 번 나가면 안 되는 까닭: 초인종은 판 중 상대 공격마다 울린다 — 한 울림이 두 조회면 판 하나에 수십 건이 된다.
        let harness = TetrisWireHarness(label: "tetris-ring")
        serve(harness)
        await harness.signIn()
        harness.transport.emit(.joined)
        #expect(applyLiveState(harness, startAtMs: harness.serverNowMs - 1_000),
                "진행 중 판을 못 세웠다 — 아래 셈이 로비 쪽으로 간다")
        #expect(harness.tetris.match?.id == Self.matchID)
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        let before = harness.count("tetris_state")

        harness.transport.emit(.broadcast(event: "tetris"))
        #expect(harness.model.realtime.effectLog.contains(.tetrisSignal), "링이 테트리스 가지를 안 냈다")
        #expect(await waits.wait { harness.count("tetris_state") == before + 1 },
                "초인종에 판 상태 조회가 안 나갔다(또는 한 번이 아니다): \(harness.count("tetris_state") - before)건")
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_state") == before + 1,
                "초인종 한 번에 조회가 \(harness.count("tetris_state") - before)건 나갔다")
        // 초인종은 **메시지 활동으로 새지 않는다**(`.drain` 가지와 따로 둔 값).
        #expect(!harness.model.realtime.effectLog.suffix(2).contains(.drain), "테트리스 초인종이 drain 으로 샜다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 기준선: **러너 칸만 떼면**(= 가지를 `break` 로 되돌린 것) 같은 초인종에 조회가 0건이다.
        let bare = TetrisWireHarness(label: "tetris-ring-off")
        serve(bare)
        await bare.signIn()
        bare.transport.emit(.joined)
        #expect(applyLiveState(bare, startAtMs: bare.serverNowMs - 1_000))
        await bare.barrier()
        await baseYield(turns: 8)
        await bare.barrier()
        bare.model.realtime.tetris = nil
        let bareBefore = bare.count("tetris_state")
        bare.transport.emit(.broadcast(event: "tetris"))
        await bare.barrier()
        await baseYield(turns: 10)
        await bare.barrier()
        #expect(bare.count("tetris_state") == bareBefore,
                "기준선이 안 갈린다 — 러너 칸과 무관하게 조회가 나가면 위 초록은 배선을 재지 않는다")
        await bare.tearDown()
    }

    @Test("조인 따라잡기(`.catchUp`)가 테트리스 로비를 한 번 긁는다 — 소켓이 내려가 있던 사이의 신청·수락은 재생되지 않는다")
    func joiningTheSocketCatchesUpTheLobby() async {
        // 없으면: 소켓이 끊겼다 붙는 동안 온 신청·수락·정산을 폰이 통째로 놓치고, 다음 폴링·허브 진입까지 모른다.
        let harness = TetrisWireHarness(label: "tetris-catchup")
        serve(harness)
        await harness.signIn()
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        let before = harness.count("tetris_lobby")

        harness.transport.emit(.joined)
        #expect(harness.model.realtime.effectLog.contains(.catchUp), "조인이 따라잡기 effect 를 안 냈다")
        #expect(await waits.wait { harness.count("tetris_lobby") == before + 1 },
                "조인 따라잡기가 테트리스 로비를 안 읽었다: \(harness.count("tetris_lobby") - before)건")
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_lobby") == before + 1,
                "조인 한 번에 로비가 \(harness.count("tetris_lobby") - before)건 나갔다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        let bare = TetrisWireHarness(label: "tetris-catchup-off")
        serve(bare)
        await bare.signIn()
        await bare.barrier()
        await baseYield(turns: 8)
        await bare.barrier()
        bare.model.realtime.tetris = nil
        let bareBefore = bare.count("tetris_lobby")
        bare.transport.emit(.joined)
        await bare.barrier()
        await baseYield(turns: 10)
        await bare.barrier()
        #expect(bare.count("tetris_lobby") == bareBefore,
                "기준선이 안 갈린다 — 러너 칸 없이도 로비를 읽으면 위 초록은 `.catchUp` 가지를 재지 않는다")
        await bare.tearDown()
    }

    // MARK: - 3. 화면 수명 — 나타나는 길 (주 스위치는 그 **결과**로 잰다)

    @Test("화면이 뜨면 로비·순위를 읽고 **준비 보고가 나간다** — 훅을 안 부른 기준선은 보고 0건이다(= 수락한 판이 흘러간다)")
    func theScreenHookOpensTheReadyReport() async {
        // ★ 깃발(`isWindowVisible`)을 재면 안 된다. 그 깃발이 쥔 **가장 무거운 것**은 폴링이 아니라 준비 보고다:
        //   코어 `considerReport` 가 `if duel.lastReportAt == nil, !current.meReady, !isWindowVisible { return }`
        //   로 막는다(직접 확인했다). 준비를 못 내면 서버는 30초 뒤 `no_show` 무승부로 접고(D4), 사용자 눈에는
        //   **수락했는데 아무 일도 안 일어난 화면**이 30초 서 있다. 거절이 '의도된 동작'이라 깃발 단언으로는 안 잡힌다.
        let harness = TetrisWireHarness(label: "tetris-screen-on")
        serve(harness)
        await harness.signIn()
        // 수락 직후의 판(둘 다 준비 전 — `start_at` 없음). 구동기가 서고 준비 보고를 낼 자리까지 왔다.
        #expect(applyLiveState(harness), "수락 직후 판을 못 세웠다")
        #expect(harness.tetris.phase == .ready, "판이 준비 단계가 아니다 — 이 테스트의 전제가 깨졌다")
        let lobbyBefore = harness.count("tetris_lobby")

        harness.games.tetrisScreenDidAppear()
        #expect(harness.games.isTetrisScreenVisible)
        #expect(harness.tetris.isWindowVisible, "화면 훅이 코어 창 깃발을 안 켰다 — windowDidShow() 가 빠졌다")
        #expect(await waits.wait { harness.count("tetris_lobby") >= lobbyBefore + 1 },
                "화면이 떴는데 로비 조회가 나가지 않았다 — openWindow 배선이 끊겼다")
        #expect(await waits.wait { harness.count("tetris_report") >= 1 },
                "창이 섰는데 준비 보고가 안 나갔다 — 수락한 판이 30초 뒤 no_show 로 접힌다")
        // ★ 순위는 여기서 **안 나가는 것이 맞다**: 코어 `windowDidShow` 가 `phase == .lobby` 일 때만 당긴다
        //   (판 중에 순위를 긁지 않는다). 그래서 순위 쪽은 로비 단계 하네스로 아래에서 따로 잰다.
        #expect(harness.tetris.phase == .ready)
        #expect(harness.count("tetris_ranking") == 0, "판을 들고 있는데 순위를 긁었다 — 판 중 조회가 하나 늘어난다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 기준선 ①: **같은 상태**에서 화면 훅만 안 부르면 준비 보고가 0건이다(판 루프가 돌아도 창 가드가 막는다).
        let bare = TetrisWireHarness(label: "tetris-screen-off")
        serve(bare)
        await bare.signIn()
        #expect(applyLiveState(bare))
        bare.tetris.tick()            // 판 루프 한 걸음을 직접 민다(벽시계 대기 없이 같은 깔때기)
        await bare.barrier()
        await baseYield(turns: 10)
        await bare.barrier()
        #expect(bare.count("tetris_report") == 0,
                "기준선이 안 갈린다 — 창 깃발과 무관하게 보고가 나가면 위 단언은 화면 훅을 재지 않는다")
        #expect(!bare.tetris.isWindowVisible)
        await bare.tearDown()

        // 순위(로비 단계): 스위치가 켜져 있으니 `tetris_ranking` 이 실제로 나가고 값이 화면으로 옮겨진다.
        let lobby = TetrisWireHarness(label: "tetris-rank-on")
        serve(lobby)
        await lobby.signIn()
        lobby.games.tetrisScreenDidAppear()
        #expect(lobby.tetris.phase == .lobby, "로비 단계가 아니면 순위를 안 긁는다 — 전제가 깨졌다")
        #expect(await waits.wait { lobby.count("tetris_ranking") >= 1 },
                "순위 조회가 나가지 않았다 — 주 스위치나 화면 훅이 끊겼다")
        #expect(await waits.wait { lobby.tetris.ranking?.entries.count == 2 }, "순위 응답이 화면 값으로 안 옮겨졌다")
        #expect(lobby.tetris.hasLoadedRanking && !lobby.tetris.rankingLoadFailed && !lobby.tetris.rankingUnavailable)
        #expect(lobby.tetris.ranking?.me?.points == 1)
        #expect(lobby.violations.isEmpty, "\(lobby.violations)")
        await lobby.tearDown()

        // 기준선 ②: 순위 **스위치만** 되돌리면 같은 손짓에 순위 조회가 0건이다.
        let off = TetrisWireHarness(label: "tetris-rank-off")
        serve(off)
        off.model.tetris.rankingEnabled = false       // = 배선 한 줄을 지운 것
        await off.signIn()
        off.games.tetrisScreenDidAppear()
        #expect(await waits.wait { off.tetris.hasLoadedLobby }, "로비 조회는 스위치와 무관하다 — 손짓 자체가 안 닿았다")
        await off.barrier()
        await baseYield(turns: 10)
        await off.barrier()
        #expect(off.count("tetris_ranking") == 0, "스위치가 꺼졌는데 순위 조회가 \(off.count("tetris_ranking"))건 나갔다")
        #expect(off.tetris.ranking == nil)
        await off.tearDown()
    }

    // MARK: - 4. 화면 수명 — 떠나는 길 (기권이 아니다 · 요청 0건)

    @Test("화면을 떠나는 것은 **기권이 아니다**: 흐르는 판은 그대로 남고 떠나는 길에서 요청이 한 건도 안 나간다")
    func leavingTheScreenIsNotAResignation() async {
        // 없으면: 떠나는 길에 `resign()`·`leaveMatch` 류를 끼우면 탭을 옮긴 것만으로 판돈을 잃는다. 반대로
        // 조회를 끼우면(체스 `leaveWatch` 가 그랬다) 화면을 떠날 때마다 로비·순위가 한 번씩 더 나간다.
        let harness = TetrisWireHarness(label: "tetris-leave-live")
        serve(harness)
        await harness.signIn()
        #expect(applyLiveState(harness, startAtMs: harness.serverNowMs - 1_000, meReady: true))
        harness.games.tetrisScreenDidAppear()
        #expect(await waits.wait { harness.tetris.isWindowVisible })
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        let lobbyBefore = harness.count("tetris_lobby")
        let stateBefore = harness.count("tetris_state")
        let rankBefore = harness.count("tetris_ranking")

        harness.games.tetrisScreenDidDisappear()
        #expect(!harness.games.isTetrisScreenVisible)
        #expect(!harness.tetris.isWindowVisible, "창을 안 내렸다 — 폴링이 계속 돈다")
        #expect(harness.tetris.pollTask == nil, "떠났는데 폴링이 살아 있다")
        #expect(harness.tetris.match?.id == Self.matchID, "떠나는 길이 **흐르는 판**을 내렸다 — 판은 서버에서 계속 흐른다")
        #expect(harness.tetris.match?.isFinished == false)
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_resign") == 0,
                "화면을 떠났더니 기권 요청이 나갔다 — 탭을 옮긴 것만으로 판돈을 잃는다")
        #expect(harness.count("tetris_lobby") == lobbyBefore, "떠나는 길에서 로비 조회가 나갔다")
        #expect(harness.count("tetris_state") == stateBefore, "떠나는 길에서 상태 조회가 나갔다")
        #expect(harness.count("tetris_ranking") == rankBefore, "떠나는 길에서 순위 조회가 나갔다")
        // 두 번 불려도 멱등이다(SwiftUI 가 onDisappear 를 겹쳐 부를 수 있다).
        harness.games.tetrisScreenDidDisappear()
        #expect(harness.count("tetris_resign") == 0)
        #expect(harness.tetris.match?.id == Self.matchID)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("**끝난** 판은 떠날 때 접힌다 — `windowDidHide()` 만 부른 기준선은 그 결과 카드를 그대로 들고 있다")
    func leavingFoldsAFinishedMatch() async {
        // 없으면(0.3.50 에서 오목·체스가 똑같이 데인 자리의 폰 몫): 게임 탭에서 테트리스를 다시 누를 때 로비가
        // 아니라 **방금 본 결과 카드가 또 선다**([로비로]를 눌러야만 빠져나온다). 폰에서 '떠남'은 맥의 '최소화'가
        // 아니라 '창을 정말 닫았다'다.
        let harness = TetrisWireHarness(label: "tetris-leave-done")
        serve(harness)
        await harness.signIn()
        let finished = TetrisWireJSON.stateEnvelope(
            nowMs: harness.serverNowMs, status: "finished", startAtMs: harness.serverNowMs - 60_000,
            meReady: true, result: "challenger_win", winner: Self.mine, endReason: "topout")
        if let payload = Self.decodeState(finished) {
            #expect(harness.tetris.applyState(payload) == .applied)
        } else {
            Issue.record("끝난 판 픽스처가 와이어와 어긋난다 — 전제를 못 세웠다")
        }
        harness.games.tetrisScreenDidAppear()
        #expect(harness.tetris.match?.isFinished == true, "끝난 판을 못 세웠다 — 이 테스트의 전제가 깨졌다")
        #expect(harness.tetris.phase == .finished)

        harness.games.tetrisScreenDidDisappear()
        #expect(harness.tetris.match == nil,
                "떠났는데 끝난 판이 남았다 — 다시 들어오면 로비가 아니라 그 결과 카드가 선다(windowDidClose() 가 빠졌다)")
        #expect(harness.tetris.phase == .lobby)
        #expect(harness.count("tetris_resign") == 0, "끝난 판을 떠나며 기권 요청이 나갔다")
        await harness.tearDown()

        // 기준선: **같은 상태**에서 코어 숨김 통지만 부르면 끝난 판이 그대로 남는다 — 그래서 닫기 통지가 필요하다.
        let bare = TetrisWireHarness(label: "tetris-leave-done-bare")
        serve(bare)
        await bare.signIn()
        if let payload = Self.decodeState(TetrisWireJSON.stateEnvelope(
            nowMs: bare.serverNowMs, status: "finished", startAtMs: bare.serverNowMs - 60_000,
            meReady: true, result: "challenger_win", winner: Self.mine, endReason: "topout")) {
            #expect(bare.tetris.applyState(payload) == .applied)
        }
        bare.games.tetrisScreenDidAppear()
        bare.tetris.windowDidHide()         // = 폰 훅에서 windowDidClose() 를 지운 것
        #expect(bare.tetris.match?.isFinished == true,
                "기준선이 안 갈린다 — 코어 숨김이 이미 끝난 판을 접는다면 폰 훅의 닫기 통지는 아무것도 증명하지 않는다")
        await bare.tearDown()
    }

    @Test("앱을 잠깐 나간 것은 '떠남'이 아니다 — **가림**이라 결과 카드와 판이 남고, 돌아오면 폴링이 되살아난다")
    func goingToBackgroundOnlyOccludes() async {
        // 없으면: background 에서 `windowDidHide()` 를 부르면 알림 하나 읽고 온 사람의 **결과 카드가 접혀**
        // 루비가 얼마 움직였는지 못 보고 로비로 떨어진다(`windowDidClose` 와 짝이 된 접기 길).
        let harness = TetrisWireHarness(label: "tetris-background")
        serve(harness)
        await harness.signIn()
        #expect(applyLiveState(harness, startAtMs: harness.serverNowMs - 1_000, meReady: true))
        harness.games.tetrisScreenDidAppear()
        #expect(await waits.wait { harness.tetris.pollTask != nil || harness.tetris.isWindowVisible })

        harness.games.appDidEnterBackground()
        #expect(harness.tetris.isWindowVisible, "background 가 창을 내렸다 — 가림만 해야 한다")
        #expect(harness.games.isTetrisScreenVisible, "화면은 여전히 떠 있다(탭을 옮긴 것이 아니다)")
        #expect(harness.tetris.isWindowOccluded, "가림 상태가 안 섰다")
        #expect(harness.tetris.pollTask == nil, "가림인데 폴링이 계속 돈다")
        #expect(harness.tetris.match?.id == Self.matchID, "background 가 판을 내렸다")

        harness.games.appDidBecomeActive()
        #expect(harness.tetris.isWindowVisible)
        #expect(!harness.tetris.isWindowOccluded, "돌아왔는데 가림이 안 풀렸다")
        #expect(await waits.wait { harness.tetris.pollTask != nil }, "active 로 돌아왔는데 폴링이 안 돌아왔다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 5. P8 — 깨어남은 한 번만 따라잡는다

    @Test("P8: active 복귀의 로비 조회는 **어느 가지에서도 한 번**이고, 화면이 없으면 창 깃발·폴링·준비 보고가 서지 않는다")
    func wakingUpCatchesUpOnceAndOnlyOpensTheWindowWhenTheScreenIsThere() async {
        // ★ 설계 P8 은 "둘 다 부르면 로비를 두 번 긁는다"고 적었는데 **실측은 다르다**: `catchUp()` 과
        //   `systemDidWake()` 는 본문이 같고(둘 다 `refreshLobby()`), 코어 `refreshLobby` 의 `lobbyInFlight`
        //   가드가 겹친 호출을 하나로 합친다. 그래서 **조회 셈만으로는 가지를 뒤집은 결함이 안 잡힌다.**
        //   값으로 갈리는 것은 창 깃발이다: 화면이 없는데 `windowDidShow()` 를 부르면 코어가 폴링을 띄우고
        //   **보이지 않는 판의 준비 보고까지 낸다**(머리말 ⑨) — 사용자는 못 보는 카운트다운에 끌려 들어가 판돈을
        //   잃는다. 아래는 그 둘을 함께 잰다(상한으로서의 '한 번' + 가지의 실제 결과).

        // ① 화면이 보이는 채 돌아왔다 — 가림 해제/창 세우기 + 따라잡기, 로비는 한 번.
        let shown = TetrisWireHarness(label: "tetris-p8-shown")
        serve(shown)
        await shown.signIn()
        shown.games.tetrisScreenDidAppear()
        #expect(await waits.wait { shown.tetris.hasLoadedLobby })
        shown.games.appDidEnterBackground()
        await shown.barrier()
        await baseYield(turns: 8)
        await shown.barrier()
        shown.clock.advance(5)        // windowDidShow 의 1초 중복 제거 창을 지나게 둔다(최악의 셈을 재려고)
        let shownBefore = shown.count("tetris_lobby")
        shown.games.appDidBecomeActive()
        #expect(await waits.wait { shown.count("tetris_lobby") >= shownBefore + 1 },
                "화면이 보이는 채 돌아왔는데 따라잡기가 안 돌았다 — background 동안의 신청·공격 누계를 모른다")
        await shown.barrier()
        await baseYield(turns: 12)
        await shown.barrier()
        #expect(shown.count("tetris_lobby") == shownBefore + 1,
                "active 복귀에 로비가 \(shown.count("tetris_lobby") - shownBefore)건 나갔다 — 두 계기가 겹쳤다")
        #expect(shown.tetris.isWindowVisible && !shown.tetris.isWindowOccluded)
        #expect(await waits.wait { shown.tetris.pollTask != nil }, "폴링이 안 되살아났다")
        #expect(shown.violations.isEmpty, "\(shown.violations)")
        await shown.tearDown()

        // ② 화면이 **없는** 채 돌아왔다 — `systemDidWake()` 한 번. 창은 서지 않는다.
        let hidden = TetrisWireHarness(label: "tetris-p8-hidden")
        serve(hidden)
        await hidden.signIn()
        // 수락 직후 판(준비 전)을 들려 둔다 — 창이 서면 **곧바로 준비 보고가 나가는** 상태다.
        #expect(applyLiveState(hidden), "수락 직후 판을 못 세웠다")
        #expect(hidden.tetris.phase == .ready)
        hidden.games.appDidEnterBackground()
        await hidden.barrier()
        await baseYield(turns: 8)
        await hidden.barrier()
        hidden.clock.advance(5)
        let hiddenBefore = hidden.count("tetris_lobby")
        hidden.games.appDidBecomeActive()
        #expect(await waits.wait { hidden.count("tetris_lobby") >= hiddenBefore + 1 },
                "화면이 없을 때도 깨어남 따라잡기는 돌아야 한다 — 받은 신청 칩과 `activeMatchID` 가 이 계기에 달렸다")
        await hidden.barrier()
        await baseYield(turns: 12)
        await hidden.barrier()
        #expect(hidden.count("tetris_lobby") == hiddenBefore + 1,
                "화면 없는 복귀에 로비가 \(hidden.count("tetris_lobby") - hiddenBefore)건 나갔다")
        // ★ 여기가 가지를 가르는 단언이다.
        #expect(!hidden.games.isTetrisScreenVisible)
        #expect(!hidden.tetris.isWindowVisible,
                "화면이 없는데 창 깃발이 섰다 — `windowDidShow()` 가 가지 밖으로 나왔다")
        #expect(hidden.tetris.pollTask == nil, "화면이 없는데 폴링이 돈다")
        #expect(hidden.count("tetris_report") == 0,
                "화면이 없는데 **준비 보고가 나갔다** — 사용자가 못 보는 카운트다운에 끌려 들어가 판돈을 잃는다")
        #expect(hidden.violations.isEmpty, "\(hidden.violations)")
        await hidden.tearDown()
    }

    @Test("체스 가지가 함수 꼬리를 `guard` 로 끊지 않는다 — 끊으면 테트리스 따라잡기가 **한 번도** 안 돈다")
    func theChessBranchDoesNotSwallowTheTetrisBranch() async throws {
        // 실제 사고 모양: 테트리스 가지를 체스 가지 **뒤**에 붙였는데 체스가 `guard isChessScreenVisible else
        // { return }` 로 끝나 있었다 — 체스 화면이 안 보이는 거의 모든 때(= 콜드 스타트 포함) 테트리스 따라잡기가
        // 조용히 죽는다. 위 ②가 값으로 잡지만, 꼬리에 가지가 또 붙는 날을 위해 글자로도 못을 박는다.
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesStore.swift")
        let body = try #require(Self.slice(code, from: "package func appDidBecomeActive", length: 2_200))
        let chessHead = try #require(body.range(of: "isChessScreenVisible"), "체스 가지가 사라졌다")
        let tetrisHead = try #require(body.range(of: "isTetrisScreenVisible"), "테트리스 가지가 없다")
        #expect(chessHead.lowerBound < tetrisHead.lowerBound, "이 단언은 테트리스가 뒤에 오는 배치를 전제한다")
        let between = String(body[chessHead.upperBound..<tetrisHead.lowerBound])
        #expect(!between.contains("return"),
                "체스 가지와 테트리스 가지 사이에 `return` 이 있다 — 테트리스 따라잡기가 한 번도 안 돈다")
        #expect(body.contains("tetris.systemDidWake()"), "P8 의 '안 보이는' 가지가 없다")
        #expect(body.contains("Task { await tetris.catchUp() }"), "P8 의 '보이는' 가지 따라잡기가 없다")
    }

    // MARK: - 6. 한 사람 한 판 — 삼각 (P3)

    @Test("한 사람 한 판은 **삼각**이다: 세 게임 가운데 하나가 흐르면 나머지 둘의 입구가 막히고, 끝난 판은 안 막는다")
    func oneMatchPerPersonBlocksAllThreeDirections() async {
        // 없으면(한 방향이라도 열어 두면): 그 길로 들어가 다른 판을 **판돈째** 잃는다. 서버도 못 막는다 —
        // `chess__busy` 는 셋을 함께 보지만 **오목 쪽 게이트는 남을 모른다**(알려진 비대칭). 그리고 테트리스는
        // 15초 침묵이면 그쪽 패(D5)라 오목·체스보다 빨리 진다.
        let harness = TetrisWireHarness(label: "tetris-triangle")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        #expect(games.gomokuEntryBlock == nil && games.chessEntryBlock == nil && games.tetrisEntryBlock == nil,
                "아무 판도 없는데 입구가 막혔다")

        // ① 테트리스 판이 흐른다 → **오목·체스** 입구가 막힌다.
        harness.tetris.match = Self.tetrisMatch()
        #expect(games.hasLiveTetrisMatch && games.hasActiveTetrisMatch)
        #expect(games.gomokuEntryBlock == .tetris, "테트리스 중인데 오목 입구가 열려 있다 — 수락하면 테트리스가 15초에 진다")
        #expect(games.chessEntryBlock == .tetris, "테트리스 중인데 체스 입구가 열려 있다")
        #expect(games.tetrisEntryBlock == nil, "자기 판이 자기 입구를 막았다")
        harness.tetris.match = Self.tetrisMatch(finished: true)
        #expect(games.gomokuEntryBlock == nil, "끝난 테트리스 판이 오목 입구를 막았다 — 결과 카드는 판이 아니다")
        #expect(games.chessEntryBlock == nil, "끝난 테트리스 판이 체스 입구를 막았다")
        #expect(!games.hasLiveTetrisMatch)
        harness.tetris.match = nil

        // ② 오목 판이 흐른다 → **테트리스**(와 체스) 입구가 막힌다.
        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(games.tetrisEntryBlock == .gomoku, "오목 중인데 테트리스 입구가 열려 있다")
        #expect(games.chessEntryBlock == .gomoku)
        harness.model.gomoku.match = Self.gomokuMatch(finished: true)
        #expect(games.tetrisEntryBlock == nil, "끝난 오목 판이 테트리스 입구를 막았다")
        harness.model.gomoku.match = nil

        // ③ 체스 판이 흐른다 → **테트리스**(와 오목) 입구가 막힌다.
        harness.model.chess.match = Self.chessMatch()
        #expect(games.tetrisEntryBlock == .chess, "체스 중인데 테트리스 입구가 열려 있다")
        #expect(games.gomokuEntryBlock == .chess)
        harness.model.chess.match = Self.chessMatch(finished: true)
        #expect(games.tetrisEntryBlock == nil, "끝난 체스 판이 테트리스 입구를 막았다")
        harness.model.chess.match = nil
        #expect(games.gomokuEntryBlock == nil && games.chessEntryBlock == nil && games.tetrisEntryBlock == nil)

        // 막힌 까닭이 **문구 표의 제 이름**으로 옮겨진다(삼항으로 접으면 테트리스가 '오목'으로 읽힌다).
        #expect(GamesBusyGame.tetris.text == .tetris)
        #expect(GamesBusyGame.allCases.count == 3, "busy 열거가 셋이 아니다 — 차단 방향을 하나 놓친다")
        await harness.tearDown()
    }

    @Test("서버가 말한 진행 판 id 만 알고 판을 못 읽어도 입구는 막힌다 — 그 틈은 1 왕복이 아니라 **열린 채로 남는다**")
    func theServerSaidActiveMatchAloneClosesTheOtherEntrances() async {
        // 실제 경로: 로비 응답이 `active_match_id` 를 주면 코어가 곧바로 `tetris_state` 를 쏘는데(applyLobby 꼬리)
        // 그 조회가 **실패하면** `match` 는 영영 nil 이고 id 만 남는다. 씨앗의 `hasLiveTetrisMatch` 는 `match` 만
        // 봤으므로 그 사이 오목·체스 입구가 열려 있었고, 그 길로 오목을 수락하면 흐르던 테트리스가 15초에 진다.
        let harness = TetrisWireHarness(label: "tetris-active-id")
        serve(harness, activeMatchID: Self.matchID)
        harness.server.setDefault("tetris_state") { _ in .networkFailure() }
        await harness.signIn()
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        // ★ **건수로 재야 한다.** 로그인이 이미 `appDidBecomeActive` → `systemDidWake()` 로 로비를 한 번 읽으므로
        //   "`activeMatchID` 가 섰다"만 보면 허브의 조회를 지워도 **초록이다**(실측 — 뮤테이션 M11 이 그렇게 빠져나갔다).
        //   허브 진입이 **자기 몫의 조회 한 건**을 내는지가 이 줄의 재는 값이다: 그 조회가 없으면 받은 신청 칩이
        //   영영 비어 있고(폰에는 배너도 배지도 없다 — P5), 앱을 막 켠 사람의 진행 판 id 도 늦게 온다.
        let lobbyBefore = harness.count("tetris_lobby")
        harness.games.hubDidAppear()
        #expect(await waits.wait { harness.count("tetris_lobby") >= lobbyBefore + 1 },
                "게임 탭 첫 화면이 테트리스 로비를 안 읽었다 — 받은 신청 칩도 진행 판 id 도 못 받는다")
        await harness.barrier()
        await baseYield(turns: 10)
        await harness.barrier()
        #expect(harness.count("tetris_lobby") == lobbyBefore + 1,
                "허브 진입 한 번에 로비가 \(harness.count("tetris_lobby") - lobbyBefore)건 나갔다 — 30초 스로틀이 안 걸렸다")
        // 같은 화면을 다시 봐도 30초 안에는 또 읽지 않는다(스로틀 — 체스와 같은 규칙).
        harness.games.hubDidAppear()
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        #expect(harness.count("tetris_lobby") == lobbyBefore + 1, "30초 안인데 허브가 로비를 다시 읽었다")
        #expect(await waits.wait { harness.tetris.activeMatchID == Self.matchID },
                "로비가 말한 진행 판 id 를 안 받았다")
        #expect(harness.tetris.match == nil, "이 테스트는 상태 조회가 실패한 틈을 전제한다")
        #expect(harness.games.hasLiveTetrisMatch,
                "서버가 '진행 중 판이 있다'고 말했는데 입구 판정이 거짓이다 — 오목·체스가 열린 채다")
        #expect(harness.games.gomokuEntryBlock == .tetris, "그 틈에 오목 입구가 열려 있다")
        #expect(harness.games.chessEntryBlock == .tetris, "그 틈에 체스 입구가 열려 있다")
        #expect(harness.games.hasActiveTetrisMatch, "카드 한 줄 재료도 같은 사실을 봐야 한다")
        await harness.tearDown()
    }

    @Test("테트리스 판이 흐르는 동안 들어온 오목 딥링크는 오목 화면을 열지 않는다 — 솔로 테트리스 링크는 그대로 열린다")
    func aGomokuDeepLinkIsRefusedWhileATetrisMatchRuns() async {
        // 없으면: 오목 로비의 [수락]에는 게이트가 없다 — 푸시·위젯으로 그 화면에 닿는 길이 남으면 테트리스 중에
        // 오목이 시작되고 테트리스는 15초 침묵으로 판돈째 진다.
        let harness = TetrisWireHarness(label: "tetris-route-block")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        // 기준선: 판이 없으면 그 링크는 **열린다**(막는 것이 깃발 덕인지 길이 끊긴 덕인지 가린다).
        #expect(games.routeStep(for: .gomokuLobby) == .push(.gomoku))
        #expect(games.routeStep(for: .gomokuInvite(matchID: "g-9")) == .push(.gomoku))
        #expect(games.pendingGomokuFocusID == "g-9")

        harness.tetris.match = Self.tetrisMatch()
        #expect(games.routeStep(for: .gomokuLobby) == .popToRoot, "테트리스 중인데 오목 로비 링크가 화면을 열었다")
        #expect(games.routeStep(for: .gomokuInvite(matchID: "g-9")) == .popToRoot,
                "테트리스 중인데 오목 신청 링크가 화면을 열었다")
        #expect(games.pendingGomokuFocusID == nil, "막은 링크의 대상이 남았다 — 나중의 무관한 진입에 쓰인다")

        // ★ `games/tetris` 는 **솔로** 테트리스 링크다(v0.3.38). 대결 판이 흘러도 그 뜻이 바뀌지 않는다 —
        //   `AingRoute` 에 대결 가지를 끼우면 이미 나간 이 링크가 엉뚱한 화면을 연다(`routeStep` 주석의 결정).
        #expect(AingRoute(path: "games/tetris") == .miniGame(.tetris), "솔로 테트리스 딥링크의 뜻이 바뀌었다")
        #expect(games.routeStep(for: .miniGame(.tetris)) == .push(.miniGame(.tetris)),
                "솔로 테트리스 링크가 막혔거나 대결로 오배달됐다")
        await harness.tearDown()
    }

    // MARK: - 7. 화면 꺼짐 방지

    @Test("테트리스 판이 도는 동안은 어느 화면에 있든 화면을 켜 둔다 — 자동잠금이 닿으면 15초 침묵으로 진다")
    func theScreenStaysAwakeWhileATetrisMatchRuns() async {
        // 없으면: 자동잠금(최소 30초)이 iOS 에 판 루프 Task 를 재우게 하고 서버는 **15초** 침묵에 내 패로 닫는다
        // (D5 — 판돈을 잃는다). 체스 시계는 10분이지만 테트리스는 15초라 이 구멍이 훨씬 빨리 열린다.
        let harness = TetrisWireHarness(label: "tetris-idle")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        #expect(!games.wantsIdleTimerDisabled, "판도 없는데 화면을 켜 두려 한다")
        harness.tetris.match = Self.tetrisMatch()
        #expect(games.wantsIdleTimerDisabled, "테트리스 판이 도는데 화면이 꺼질 수 있다 — 15초면 진다")
        // 테트리스 화면 밖(게임 첫 화면·다른 탭)에서도 켜 둔다 — 판은 서버 시계로 흐른다.
        #expect(!games.isTetrisScreenVisible)
        #expect(games.wantsIdleTimerDisabled)
        harness.tetris.match = Self.tetrisMatch(finished: true)
        #expect(!games.wantsIdleTimerDisabled, "끝난 판인데 화면을 계속 켜 둔다")
        harness.tetris.match = nil
        #expect(!games.wantsIdleTimerDisabled)
        // 싱크까지 실제로 값이 흘러간다(주인은 이 스토어 하나다).
        var applied: [Bool] = []
        let fresh = TetrisWireHarness(label: "tetris-idle-sink")
        serve(fresh)
        await fresh.signIn()
        fresh.games.installIdleTimerSink { applied.append($0) }
        fresh.tetris.match = Self.tetrisMatch()
        #expect(await waits.wait { applied.last == true }, "판이 섰는데 화면 꺼짐 방지가 안 걸렸다: \(applied)")
        fresh.tetris.match = nil
        #expect(await waits.wait { applied.last == false }, "판이 끝났는데 방지가 안 풀렸다: \(applied)")
        await fresh.tearDown()
        await harness.tearDown()
    }

    // MARK: - 8. 화면을 여는 문 (코어가 부르면 경로가 쌓인다)

    @Test("코어가 `presentWindow` 를 부르면 게임 탭에 테트리스 화면이 쌓인다 — 문을 떼면 같은 손짓에 경로가 0이다")
    func theCoreDoorPushesTheTetrisScreen() async {
        // 없으면: 수락·판 시작이 화면을 못 연다. 맥이 체스에서 이 문을 안 물려 판돈 걸린 판을 조용히 시간패했고,
        // 테트리스는 수락 뒤 30초 안에 준비를 못 내면 `no_show` 로 접힌다(D4) — 준비는 창이 떠야 나간다.
        let harness = TetrisWireHarness(label: "tetris-door")
        serve(harness)
        await harness.signIn()
        let router = harness.model.router
        router.selectedTab = .me
        router.popToRoot(.games)
        #expect(router.path(for: .games).isEmpty)

        harness.tetris.openWindow(focusMatchID: nil)     // 코어가 그 문을 부르는 실제 자리 중 하나
        #expect(router.selectedTab == .games, "문이 게임 탭을 고르지 않았다")
        #expect(router.path(for: .games).count == 1, "문이 테트리스 화면을 쌓지 않았다")
        // 이미 화면이 보이면 **또 쌓지 않는다**(깃발을 먼저 적는 순서가 이것을 쥔다).
        harness.games.tetrisScreenDidAppear()
        let after = router.path(for: .games).count
        harness.tetris.openWindow(focusMatchID: nil)
        #expect(router.path(for: .games).count == after, "화면이 보이는데 또 쌓았다 — 같은 화면이 두 장 겹친다")
        await harness.tearDown()

        // 기준선: **문만 떼면** 같은 손짓에 경로가 안 쌓인다.
        let bare = TetrisWireHarness(label: "tetris-door-off")
        serve(bare)
        await bare.signIn()
        bare.model.tetris.presentWindow = nil            // = init 의 한 줄을 지운 것
        bare.model.router.selectedTab = .me
        bare.model.router.popToRoot(.games)
        bare.tetris.openWindow(focusMatchID: nil)
        #expect(bare.model.router.path(for: .games).isEmpty,
                "기준선이 안 갈린다 — 문과 무관하게 경로가 쌓이면 위 초록은 배선을 재지 않는다")
        await bare.tearDown()
    }

    // MARK: - 9. 한 판 한 기기 (0.3.69 — 코어 머리말 ⑩)

    @Test("다른 기기가 두는 판의 시작은 폰 화면을 열지 않는다(판·보고 0 · 안내 한 줄) — 같은 상태에 my_device this 면 연다 · 기록은 앱 저장소")
    func aMatchPlayedOnAnotherDeviceDoesNotOpenThePhoneScreen() async throws {
        // 없으면: 맥에서 수락한 판의 초인종을 받은 폰이 게임 탭으로 건너뛰어 대결 화면을 쌓고(보이는 화면은 곧바로 준비를 낸다)
        // 입력 없는 폰의 판이 맥의 판을 덮는다 — 2026-10-30 맥 두 대 사고의 폰 판.
        let harness = TetrisWireHarness(label: "tetris-other-device")
        serve(harness)
        await harness.signIn()
        // 기록은 앱 저장소(App Group defaults — `storage.defaults` 는 부를 때마다 새 인스턴스라 같은 스위트에 떨어지는지로 잰다).
        harness.tetris.noteOwnsMatch("m-tetris-owned")
        let owned = harness.storage.defaults.dictionary(
            forKey: TetrisDuelStore.ownedMatchesKey(userID: TetrisWireHarness.userID))
        #expect(owned?.keys.contains("m-tetris-owned") == true,
                "'이 폰이 연 판' 기록이 앱 저장소에 안 떨어진다 — 판 중에 다시 켜면 자기 판을 못 알아본다")
        let router = harness.model.router
        router.selectedTab = .me
        router.popToRoot(.games)
        let other = try #require(Self.decodeState(TetrisWireJSON.stateEnvelope(nowMs: harness.serverNowMs,
                                                                               myDevice: "other")))
        harness.tetris.applyState(other)
        #expect(router.selectedTab == .me && router.path(for: .games).isEmpty, "다른 기기의 판이 폰 화면을 열었다")
        #expect(harness.tetris.duel == nil && harness.tetris.playingElsewhere)
        #expect(harness.tetris.notice == TetrisDuelNoticeText.otherDevice)
        await harness.barrier()
        #expect(harness.count("tetris_report") == 0, "다른 기기의 판에 폰이 보고를 냈다")
        await harness.tearDown()

        // ★ 기준선: 같은 판 · 같은 손짓에 서버가 'this' 라 하면 화면이 열린다(막은 것이 판정 덕인지 길이 끊긴 덕인지 가린다).
        let mine = TetrisWireHarness(label: "tetris-this-device")
        serve(mine)
        await mine.signIn()
        mine.model.router.selectedTab = .me
        mine.model.router.popToRoot(.games)
        let this = try #require(Self.decodeState(TetrisWireJSON.stateEnvelope(nowMs: mine.serverNowMs)))
        mine.tetris.applyState(this)
        #expect(mine.model.router.selectedTab == .games && mine.model.router.path(for: .games).count == 1,
                "기준선이 안 갈린다 — 이 폰의 판도 화면을 못 연다")
        #expect(mine.tetris.duel != nil && !mine.tetris.playingElsewhere)
        await mine.tearDown()
    }

    @Test("다른 기기가 두는 판을 폰에서 열면 기다림 대신 그 사실 · '나가면 져요' 없음 · 화면 꺼짐 방지 없음 — 같은 판에 this 면 셋 다 선다")
    func aMatchPlayedOnAnotherDeviceShowsTheFactNotTheWaitingCard() async throws {
        // 없으면: 판을 두지 않는 폰이 `.ready` 에 머물러 "상대를 기다리는 중 · 앱을 켜 둔 채 기다려 주세요" 카드와
        // "판 중에 앱을 나가면 져요" 를 띄우고(둘 다 이 폰에는 거짓이다), 남의 기기 판이 끝날 때까지 최대 8분 화면을 켜 둔다.
        // 화면 표는 뷰가 만드는 그대로 **실제 스토어 값**으로 세운다(뷰 몸통은 `#if os(iOS)` 라 맥 스위트가 못 본다 —
        // 그 자리는 `GamesTetrisDuelMatchTests` 의 소스 계약이 잇는다).
        func chrome(_ tetris: TetrisDuelStore) throws -> GamesTetrisDuelChrome {
            GamesTetrisDuelChrome(match: try #require(tetris.match), phase: tetris.phase, myStats: tetris.myStats,
                                  notice: tetris.notice, connectionTrouble: tetris.connectionTrouble,
                                  playingElsewhere: tetris.playingElsewhere)
        }
        let harness = TetrisWireHarness(label: "tetris-other-device-screen")
        serve(harness)
        await harness.signIn()
        let other = try #require(Self.decodeState(TetrisWireJSON.stateEnvelope(nowMs: harness.serverNowMs,
                                                                               myDevice: "other")))
        harness.tetris.applyState(other)
        #expect(harness.tetris.phase == .ready && harness.tetris.playingElsewhere)
        let elsewhere = try chrome(harness.tetris)
        #expect(elsewhere.stage == .waiting && elsewhere.playingElsewhere, "덮개가 기다림 갈래를 탄다")
        #expect(!elsewhere.showsLeaveWarning, "판을 두지 않는 폰에 '판 중에 앱을 나가면 져요' 가 선다")
        #expect(!elsewhere.acceptsInput)
        #expect(elsewhere.notice == nil, "덮개 제목과 같은 안내가 판 밑에 한 번 더 선다")
        #expect(!harness.games.wantsIdleTimerDisabled, "남의 기기 판인데 이 폰 화면을 켜 둔다")
        await harness.tearDown()

        // ★ 기준선: 같은 판에 서버가 'this' 라 하면 기다림 카드 · 경고 · 화면 꺼짐 방지가 그대로 선다.
        let mine = TetrisWireHarness(label: "tetris-this-device-screen")
        serve(mine)
        await mine.signIn()
        let this = try #require(Self.decodeState(TetrisWireJSON.stateEnvelope(nowMs: mine.serverNowMs)))
        mine.tetris.applyState(this)
        let playing = try chrome(mine.tetris)
        #expect(playing.stage == .waiting && !playing.playingElsewhere)
        #expect(playing.showsLeaveWarning, "기준선이 안 갈린다 — 이 폰의 판에서도 경고가 사라졌다")
        #expect(mine.games.wantsIdleTimerDisabled, "기준선이 안 갈린다 — 이 폰의 판에서도 화면이 꺼질 수 있다")
        await mine.tearDown()
    }

    @Test("목적지가 실제로 테트리스 대결이다 — 쌓는 자리가 `GamesDestination.tetrisDuel` 인지 글자로 못 박는다")
    func theDoorPushesTheTetrisDestination() throws {
        // `NavigationPath` 는 원소를 되읽을 수 없어(Codable 이 아니다) 위 테스트는 **건수**만 잰다.
        // 어느 화면을 쌓는지는 그래서 글자로 본다 — 체스를 쌓으면 위 초록이 그대로다.
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesStore.swift")
        let body = try #require(Self.slice(code, from: "private func presentTetrisScreen", length: 400))
        #expect(body.contains("GamesDestination.tetrisDuel"), "테트리스 문이 테트리스 목적지를 쌓지 않는다")
        #expect(body.contains("isTetrisScreenVisible"), "이미 떠 있는 화면을 또 쌓는 것을 막지 않는다")
        #expect(body.contains("router.selectedTab = .games"), "문이 게임 탭을 고르지 않는다")
        let appear = try #require(Self.slice(code, from: "package func tetrisScreenDidAppear", length: 400))
        #expect(appear.contains("tetris.openWindow(focusMatchID:"), "나타나는 길이 로비·판을 안 읽는다")
        #expect(appear.contains("if isAppActive { tetris.windowDidShow() }"),
                "나타나는 길이 windowDidShow() 를 안 부른다 — 준비 보고의 문이 닫힌 채다")
        let leave = try #require(Self.slice(code, from: "package func tetrisScreenDidDisappear", length: 400))
        let hide = try #require(leave.range(of: "windowDidHide()"), "떠나는 길에 windowDidHide() 가 없다")
        let close = try #require(leave.range(of: "windowDidClose()"), "떠나는 길에 windowDidClose() 가 없다")
        #expect(hide.lowerBound < close.lowerBound, "닫기가 숨김보다 먼저다 — 접힌 뒤의 숨김이 빈 판을 본다")
        #expect(!leave.contains("resign"), "떠나는 길에서 기권을 부른다")
        let background = try #require(Self.slice(code, from: "package func appDidEnterBackground", length: 1_400))
        #expect(background.contains("context.tetris.windowOcclusionDidChange(visible: false)"),
                "background 가 테트리스를 가림으로 멈추지 않는다")
        #expect(!background.contains("context.tetris.windowDidHide"),
                "background 가 테트리스 창을 숨겼다 — 잠깐 나간 것이 '화면을 떠났다'가 된다")
    }

    // MARK: - 9. 로그아웃

    @Test("로그아웃하면 테트리스 판·신청·순위·루비가 남지 않는다 — 다음 계정이 앞 사람의 로비를 본다")
    func signingOutLeavesNoTetrisState() async {
        // 없으면: 다음 사람의 로비에 앞 사람의 판·신청·전적·루비가 남는다. 테트리스는 하나 더 붙는다 —
        // 판 구동기와 1초 보고가 살아서 **로그아웃한 사람의 판에 새 계정 토큰으로 보고가 계속 나간다.**
        let harness = TetrisWireHarness(label: "tetris-signout")
        serve(harness, incoming: [TetrisWireJSON.invite("m-in", peerKey: "from", nowMs: harness.serverNowMs)])
        await harness.signIn()
        harness.games.tetrisScreenDidAppear()
        #expect(await waits.wait { harness.tetris.hasLoadedLobby && harness.tetris.ranking != nil })
        #expect(applyLiveState(harness, startAtMs: harness.serverNowMs - 1_000, meReady: true))
        // 기준선: 거둘 것이 실제로 있어야 아래 '비었다'가 뜻을 가진다.
        #expect(harness.tetris.match != nil, "거둘 판이 없다 — 이 테스트가 공허해진다")
        #expect(!harness.tetris.incoming.isEmpty, "거둘 받은 신청이 없다")
        #expect(!harness.tetris.users.isEmpty, "거둘 로비 목록이 없다")
        #expect(harness.tetris.rubyBalance != nil, "거둘 루비가 없다")
        #expect(harness.tetris.ranking != nil, "거둘 순위가 없다")
        #expect(harness.tetris.duel != nil, "거둘 판 구동기가 없다")
        #expect(harness.games.isTetrisScreenVisible)

        await harness.model.session.signOut()
        let tetris = harness.model.tetris
        #expect(tetris.match == nil, "로그아웃이 앞 사람의 판을 남겼다")
        #expect(tetris.incoming.isEmpty && tetris.outgoing == nil, "로그아웃이 앞 사람의 신청을 남겼다")
        #expect(tetris.users.isEmpty, "로그아웃이 앞 사람의 로비 목록을 남겼다")
        #expect(tetris.record == nil && tetris.ranking == nil, "로그아웃이 앞 사람의 전적·순위를 남겼다")
        #expect(tetris.rubyBalance == nil, "로그아웃이 앞 사람의 루비를 남겼다")
        #expect(tetris.activeMatchID == nil, "로그아웃이 진행 판 id 를 남겼다 — 다음 계정의 입구가 막힌다")
        #expect(tetris.duel == nil, "로그아웃이 판 구동기를 남겼다 — 남의 판에 보고가 계속 나간다")
        #expect(tetris.phase == .lobby && !tetris.isWindowVisible && tetris.pollTask == nil)
        #expect(!harness.games.isTetrisScreenVisible, "게임 탭이 테트리스 화면 깃발을 남겼다")
        // 배선 값은 살아 있다(재로그인 뒤 순위·화면 문이 그대로 돌아야 한다).
        #expect(tetris.rankingEnabled && tetris.presentWindow != nil, "로그아웃이 배선 값을 거뒀다")
        #expect(harness.model.realtime.tetris === tetris, "로그아웃이 러너의 테트리스 칸을 끊었다")
        await harness.tearDown()
    }

    // MARK: - 소스 읽기 도우미 (주석을 걷고 읽는다)

    /// 저장소 파일 한 벌을 **주석을 걷어내고** 돌려준다. 안 걷으면 설명을 지워야만 초록이 되는 테스트가 된다
    /// (저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다').
    static func strippedSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// `needle` 뒤 `length` 글자(없으면 nil).
    static func slice(_ source: String, from needle: String, length: Int) -> String? {
        guard let hit = source.range(of: needle) else { return nil }
        return String(source[hit.upperBound...].prefix(length))
    }
}
