@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 체스 **입구 배선**의 못. 재는 것 넷:
//
//  ① 순위·관전 **주 스위치**(`ChessStore.spectatorFeaturesEnabled`, 기본 false) — 켠 것이 아니라 **켠 결과로
//     요청이 나가는 것**을 잰다. 스위치만 되돌린 하네스에 같은 손짓을 걸어 0건을 나란히 본다.
//  ② 화면 **수명 훅** — 떠날 때 `stopWatching()` 이 **먼저**, `windowDidHide()` 가 **나중**이고,
//     `leaveWatch()`(네트워크)는 부르지 않는다. background 는 '가림'이라 판·관전이 남는다.
//  ③ **한 사람 한 판(B8) — 양방향.** 체스 중이면 오목 입구가 막히고, 오목 중이면 체스 입구가 막힌다.
//     서버의 오목 쪽 게이트는 체스를 모르므로(인수인계 §6-7) **이쪽 방향은 클라밖에 막는 데가 없다.**
//  ④ 화면 꺼짐 방지 · 딥링크 차단 · 문구 계약(루비가 **언제** 움직이는가).
//
// ── 왜 이 파일이 따로 있는가 ──
// 체스 화면은 전부 `#if os(iOS)` 안이라 **맥 스위트가 한 줄도 못 본다**(저장소 메모 '폰 뷰는 맥 스위트가 못 본다' —
// `ios/scripts/build-sim.sh` 가 유일한 그물이다). 그런데 그 화면 넷을 통째로 죽이는 원인은 뷰가 아니라 배선 몇 줄이다.
// 그래서 **판정은 뷰에 적지 않고** 플랫폼 분기가 없는 자리(`GamesStore.swift`)에 두고, 뷰가 그 자리를 실제로
// 부르는지만 **소스 글자로** 되묻는다(오목 `GamesGomokuSpectateWiringTests` 와 같은 관례).
//
// 관례는 같은 폴더 그대로: `GamesHarness`(스텁 서버·조작 시계·임시 저장소) · 테스트 하나 몫의 대기 예산 ·
// 끝에서 폰 금지 호출 0건.

@MainActor
@Suite(.serialized) struct GamesChessWiringTests {
    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    // MARK: - 픽스처 (서버 모양 그대로 — `Tests/checkTests/Fixtures/chess-rpc/` 의 실측 캡처와 같은 키)

    private nonisolated static let mine = GamesHarness.userID
    private nonisolated static let rival = "p-chess-rival"
    private nonisolated static let watched = "m-watched"

    private nonisolated static func user(
        _ id: String, _ name: String, working: Bool = true, capable: Bool? = true, inMatch: Bool = false
    ) -> String {
        let capableValue = capable.map { $0 ? "true" : "false" } ?? "null"
        return #"{"user_id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"center":"seoul","is_working":\#(working),"capable":\#(capableValue),"in_match":\#(inMatch)}"#
    }

    /// `chess_lobby` 한 벌. `me` 의 세 id 는 전부 null 이 기본이다(받은·보낸 신청·진행 판 없음).
    private nonisolated static func lobbyJSON(
        nowMs: Int, users: [String]? = nil, matches: [String] = [], activeMatchID: String? = nil
    ) -> String {
        let rows = users ?? [user(rival, "체스라이벌"), user("p-chess-old", "체스구버전", capable: false),
                             user("p-chess-unknown", "체스미지", capable: nil)]
        let active = activeMatchID.map { "\"\($0)\"" } ?? "null"
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"invite_ttl_seconds":60,"ruby_balance":100,"me":{"ruby_balance":100,"wins":2,"losses":1,"draws":0,"active_match_id":\#(active),"outgoing_match_id":null,"incoming_match_id":null},"users":[\#(rows.joined(separator: ","))],"matches":[\#(matches.joined(separator: ","))]}"#
    }

    /// 로비 "지금 대결 중" 한 줄(관전 입구).
    private nonisolated static func liveRow(nowMs: Int, id: String = watched) -> String {
        #"{"match_id":"\#(id)","a":{"user_id":"\#(rival)","display_name":"체스라이벌","avatar_url":null,"character":null,"center":null},"b":{"user_id":"p-chess-b","display_name":"체스지유","avatar_url":null,"character":null,"center":null},"stake":5,"started_ms":\#(nowMs - 30_000)}"#
    }

    private nonisolated static func rankingJSON(nowMs: Int) -> String {
        let rows = [
            #"{"rank":1,"user_id":"\#(rival)","display_name":"체스라이벌","avatar_url":null,"character":"fox","center":"seoul","wins":5,"losses":1,"draws":0,"points":4}"#,
            #"{"rank":2,"user_id":"\#(mine)","display_name":"나","avatar_url":null,"character":"aing","center":"seoul","wins":2,"losses":1,"draws":0,"points":1}"#
        ]
        return #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":{"rank":2,"wins":2,"losses":1,"draws":0,"points":1},"rows":[\#(rows.joined(separator: ","))]}"#
    }

    /// `chess_watch` ok(진행 중). 관전 폴링이 이 응답을 받아도 `isFinished` 가 서지 않아야 "진행 중인 관전"이다.
    private nonisolated static func watchJSON(nowMs: Int, id: String = watched) -> String {
        let match = #"{"id":"\#(id)","status":"active","stake":5,"white":"\#(rival)","black":"p-chess-b","ply_count":2,"fen":"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2","turn":"white","white_ms_left":590000,"black_ms_left":595000,"increment_ms":3000,"turn_started_ms":\#(nowMs - 2_000),"deadline_ms":\#(nowMs + 588_000),"started_ms":\#(nowMs - 30_000),"result":null,"end_reason":null,"winner":null,"draw_offer_by":null}"#
        let white = #"{"user_id":"\#(rival)","display_name":"체스라이벌","avatar_url":null,"character":null,"center":null}"#
        let black = #"{"user_id":"p-chess-b","display_name":"체스지유","avatar_url":null,"character":null,"center":null}"#
        return #"{"status":"ok","server_now_ms":\#(nowMs),"match":\#(match),"moves":[],"in_check":false,"white_user":\#(white),"black_user":\#(black)}"#
    }

    /// 체스 화면이 실제로 부르는 조회들을 스텁에 걸어 둔다(로비 · 순위 · 관전) + 오목 쪽 조회(허브가 함께 부른다).
    private func serve(_ harness: GamesHarness, matches: [String] = []) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("chess_lobby", json: Self.lobbyJSON(nowMs: nowMs, matches: matches))
        harness.server.setDefault("chess_ranking", json: Self.rankingJSON(nowMs: nowMs))
        harness.server.setDefault("chess_watch", json: Self.watchJSON(nowMs: nowMs))
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
    }

    // MARK: - 판 조각 (스토어에 직접 꽂는다 — 서버 왕복 없이 '판이 흐르는 중'을 세운다)

    private nonisolated static func chessMatch(id: String = "c-1", finished: Bool = false) -> ChessMatchState {
        ChessMatchState(
            id: id, stake: 5, myColor: .white,
            opponent: ChessUser(id: rival, displayName: "체스라이벌", avatarURL: nil, characterID: nil,
                                isWorking: true, isCapable: true, inMatch: true),
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            position: nil, plyCount: 0, turn: finished ? nil : .white, lastMove: nil, moves: [],
            clock: .initial, isInCheck: false, legalMoves: [], isFinished: finished,
            outcome: finished ? .won : nil, endReason: finished ? .resign : nil, rubyDelta: finished ? 5 : nil,
            drawOfferBy: nil, drawOfferedByMe: false)
    }

    private nonisolated static func gomokuMatch(id: String = "g-1", finished: Bool = false) -> GomokuMatchState {
        GomokuMatchState(
            id: id, stake: 5, myColor: .black,
            opponent: GomokuUser(id: "p-1", displayName: "구름빵", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: true),
            board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: finished ? nil : .black, deadline: nil,
            isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false)
    }

    // MARK: - 1. 배선 한 줄

    @Test("폰 배선이 체스 순위·관전 주 스위치를 켠다 — 이 한 줄이 빠지면 순위·관전 요청이 한 번도 나가지 않는다")
    func phoneWiringEnablesChessSpectatorFeatures() async {
        // 없으면: 폰의 체스 순위 절은 영영 로딩 문구이고 [관전]은 눌러도 관전 상태조차 서지 않는다.
        // 화면 파일은 `#if os(iOS)` 안이라 맥 스위트가 못 보므로, 되돌려도 **빨개지는 테스트가 이것 말고는 없다**.
        let harness = GamesHarness(label: "chess-switch")
        #expect(harness.model.chess.spectatorFeaturesEnabled,
                "폰 배선(MobileAppModel.init)이 chess.spectatorFeaturesEnabled 를 안 켰다 — 순위·관전이 통째로 죽는다")
        // 화면이 읽는 자리도 같은 스토어여야 한다. 다른 인스턴스를 켜면 깃발은 참인데 화면 쪽은 그대로 꺼져 있다.
        #expect(harness.model.context.chess === harness.model.chess, "탭 스토어가 보는 체스 스토어가 딴 인스턴스다")
        #expect(harness.games.chess === harness.model.chess, "GamesStore.chess 가 딴 인스턴스다")
        #expect(harness.model.context.chess.spectatorFeaturesEnabled)
        // 호스트는 **오목과 같은 하나**다 — 두 벌이면 루비 미러가 갈려 탭마다 다른 잔액이 보인다.
        #expect(harness.model.chess.host === harness.model.gomokuHost, "체스 호스트가 오목과 다른 인스턴스다")
        // 스위치는 배선 값이라 로그아웃 reset 이 건드리지 않는다 — 재로그인 뒤에도 순위가 살아야 한다.
        harness.model.chess.reset()
        #expect(harness.model.chess.spectatorFeaturesEnabled, "reset 이 배선 값을 껐다 — 재로그인하면 순위가 안 열린다")
        await harness.tearDown()
    }

    // MARK: - 2. 켠 것이 실제로 닿는가 (기준선 대비)

    @Test("체스 화면이 뜨면 로비와 순위를 실제로 읽는다 — 스위치만 되돌린 하네스는 같은 손짓에 순위 0건이다")
    func openingTheChessScreenLoadsLobbyAndRanking() async {
        // 없으면: 깃발만 참이고 조회가 안 나가는 상태(창 게이트·세션 게이트가 어긋난 배선)가 위 테스트만으로는 초록이다.
        let harness = GamesHarness(label: "chess-rank-on")
        serve(harness)
        await harness.signIn()
        harness.games.chessScreenDidAppear()
        #expect(await waits.wait { harness.server.requests("chess_lobby").count >= 1 },
                "체스 화면이 떴는데 로비 조회가 나가지 않았다 — openWindow 배선이 끊겼다")
        #expect(await waits.wait { harness.server.requests("chess_ranking").count >= 1 },
                "체스 화면이 떴는데 순위 조회가 나가지 않았다")
        #expect(await waits.wait { harness.model.chess.ranking != nil }, "순위 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.model.chess.ranking?.entries.count == 2)
        #expect(harness.model.chess.hasLoadedRanking)
        #expect(!harness.model.chess.rankingUnavailable && !harness.model.chess.rankingLoadFailed)
        #expect(await waits.wait { harness.model.chess.hasLoadedLobby })
        // 서버가 말한 시계를 그대로 든다 — 캡션이 상수를 베끼지 않는다는 뜻이다(픽스처는 10분 + 3초).
        #expect(harness.model.chess.initialMs == 600_000, "로비가 말한 시작 시간을 안 받았다")
        #expect(harness.model.chess.incrementMs == 3_000)
        #expect(harness.model.chess.notice == nil, "로비 갈래가 상태줄을 가로챘다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 기준선이 달라야 이 테스트가 산다: 같은 손짓에서 **스위치만** 되돌리면 순위 조회가 0건이다.
        let off = GamesHarness(label: "chess-rank-off")
        serve(off)
        off.model.chess.spectatorFeaturesEnabled = false        // = 배선 한 줄을 지운 것
        await off.signIn()
        off.games.chessScreenDidAppear()
        #expect(await waits.wait { off.model.chess.hasLoadedLobby }, "로비 조회는 스위치와 무관하다 — 손짓 자체가 안 닿았다")
        await off.barrier()
        await baseYield(turns: 8)
        await off.barrier()
        #expect(off.server.requests("chess_ranking").isEmpty,
                "스위치가 꺼졌는데 순위 조회가 나갔다: \(off.server.requests("chess_ranking").count)건")
        #expect(off.model.chess.ranking == nil)
        await off.tearDown()
    }

    @Test("꺼진 스위치는 [관전]도 막는다 — 켜면 같은 손짓이 관전 상태를 세우고 판을 읽는다")
    func theSwitchAlsoGatesWatching() async {
        // 없으면: 관전 쪽은 순위와 **다른 깃발**을 지나므로(watchUnavailable 과도 다르다) 위 순위 단언만으로는
        // 관전이 열리는지 알 수 없다. 두 소비자를 한 깃발이 겸업하다 한쪽이 조용히 죽은 전례가 오목에 있다.
        let harness = GamesHarness(label: "chess-watch-on")
        serve(harness, matches: [Self.liveRow(nowMs: harness.serverNowMs)])
        await harness.signIn()
        harness.games.chessScreenDidAppear()
        #expect(await waits.wait { !harness.model.chess.liveMatches.isEmpty }, "로비 '지금 대결 중' 이 안 왔다")
        harness.model.chess.startWatching(matchID: Self.watched)
        #expect(await waits.wait { harness.server.requests("chess_watch").count >= 1 }, "관전 조회가 안 나갔다")
        #expect(await waits.wait { harness.model.chess.spectating?.hasServerState == true },
                "관전 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.model.chess.spectating?.isFinished == false, "픽스처가 진행 중인 판이어야 아래 수명 테스트가 산다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        let off = GamesHarness(label: "chess-watch-off")
        serve(off, matches: [Self.liveRow(nowMs: off.serverNowMs)])
        off.model.chess.spectatorFeaturesEnabled = false
        await off.signIn()
        off.games.chessScreenDidAppear()
        #expect(await waits.wait { !off.model.chess.liveMatches.isEmpty })
        off.model.chess.startWatching(matchID: Self.watched)
        await off.barrier()
        await baseYield(turns: 8)
        await off.barrier()
        #expect(off.model.chess.spectating == nil, "스위치가 꺼졌는데 관전 상태가 섰다")
        #expect(off.server.requests("chess_watch").isEmpty, "스위치가 꺼졌는데 관전 조회가 나갔다")
        await off.tearDown()
    }

    // MARK: - 3. 수명 훅 (떠날 때의 순서가 계약이다)

    @Test("체스 화면을 떠나면 **진행 중인** 관전도 내려간다 — `windowDidHide()` 만으로는 그 판이 남는다(기준선)")
    func leavingTheChessScreenDropsALiveSpectate() async {
        // 없으면: 코어 `windowDidHide` 는 **끝난** 관전만 내리고 진행 중인 관전은 일부러 남긴다(맥의 최소화 때문).
        // 폰에서 같은 통지는 "화면을 떠났다"이므로, `stopWatching()` 을 먼저 안 부르면 게임 탭에서 체스를 다시
        // 누를 때 로비가 아니라 **남의 대국이 다시 열린다**(예고도 없다 — 카드 문구는 내 판만 본다).
        let harness = GamesHarness(label: "chess-leave")
        serve(harness, matches: [Self.liveRow(nowMs: harness.serverNowMs)])
        await harness.signIn()
        harness.games.chessScreenDidAppear()
        #expect(await waits.wait { !harness.model.chess.liveMatches.isEmpty })
        harness.model.chess.startWatching(matchID: Self.watched)
        #expect(await waits.wait { harness.model.chess.spectating?.hasServerState == true })
        #expect(harness.model.chess.spectating?.isFinished == false)
        // `leaveWatch()` 는 이 둘을 다시 읽는다 — 그래서 이 둘의 건수가 곧 "그쪽을 불렀나" 다.
        let lobbyBefore = harness.server.requests("chess_lobby").count
        let rankingBefore = harness.server.requests("chess_ranking").count

        harness.games.chessScreenDidDisappear()
        #expect(harness.model.chess.spectating == nil,
                "화면을 떠났는데 진행 중인 관전이 남았다 — stopWatching() 이 windowDidHide() 뒤에 있거나 아예 없다")
        #expect(!harness.model.chess.isWindowVisible, "창을 안 내렸다 — 폴링이 계속 돈다")
        #expect(!harness.games.isChessScreenVisible)
        // ★ `leaveWatch()` 가 **아니다**: 그쪽은 로비·순위를 다시 읽는 네트워크 호출이다. 떠나는 길에서 조회가 나가면 안 된다.
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        #expect(harness.server.requests("chess_lobby").count == lobbyBefore,
                "화면을 떠나며 로비 조회가 나갔다 — leaveWatch() 를 불렀다")
        #expect(harness.server.requests("chess_ranking").count == rankingBefore,
                "화면을 떠나며 순위 조회가 나갔다 — leaveWatch() 를 불렀다")
        // 두 번 불려도 멱등이다(SwiftUI 가 onDisappear 를 겹쳐 부를 수 있다).
        harness.games.chessScreenDidDisappear()
        #expect(harness.server.requests("chess_lobby").count == lobbyBefore)
        await harness.tearDown()

        // 기준선: **같은 상태**에서 코어 통지만 부르면 진행 중인 관전이 남는다 — 그래서 폰 훅이 필요하다.
        let bare = GamesHarness(label: "chess-leave-bare")
        serve(bare, matches: [Self.liveRow(nowMs: bare.serverNowMs)])
        await bare.signIn()
        bare.games.chessScreenDidAppear()
        #expect(await waits.wait { !bare.model.chess.liveMatches.isEmpty })
        bare.model.chess.startWatching(matchID: Self.watched)
        #expect(await waits.wait { bare.model.chess.spectating?.hasServerState == true })
        bare.model.chess.windowDidHide()        // = 폰 훅에서 stopWatching() 을 지운 것
        #expect(bare.model.chess.spectating != nil,
                "기준선이 안 갈린다 — 코어가 진행 중인 관전을 이미 내린다면 폰 훅의 stopWatching() 은 아무것도 증명하지 않는다")
        await bare.tearDown()
    }

    @Test("앱을 잠깐 나간 것은 '그 판에서 나갔다'가 아니다 — 결과 화면의 판도, 보던 관전도 남는다")
    func goingToBackgroundKeepsTheMatchAndTheSpectate() async {
        // 없으면: background 에서 `windowDidHide()` 를 부르면 알림 하나 읽고 오는 것이 "그만 볼게"가 되어
        // 남의 판 관전이 끊기고, 결과 화면인 채 나간 사람의 판도 내려간다(오목 `GamesStore.swift:102` 의 당부).
        let harness = GamesHarness(label: "chess-background")
        serve(harness, matches: [Self.liveRow(nowMs: harness.serverNowMs)])
        await harness.signIn()
        harness.games.chessScreenDidAppear()
        #expect(await waits.wait { !harness.model.chess.liveMatches.isEmpty })
        harness.model.chess.startWatching(matchID: Self.watched)
        #expect(await waits.wait { harness.model.chess.spectating?.hasServerState == true })

        harness.games.appDidEnterBackground()
        #expect(harness.model.chess.spectating != nil, "background 가 관전을 끊었다 — 가림이 아니라 숨김을 불렀다")
        #expect(harness.model.chess.isWindowVisible, "background 가 창을 내렸다 — 가림만 해야 한다")
        #expect(harness.games.isChessScreenVisible, "화면은 여전히 떠 있다(탭을 옮긴 것이 아니다)")
        #expect(harness.model.chess.pollTask == nil, "가림인데 폴링이 계속 돈다")

        // 돌아오면 가림이 풀리고 폴링이 되살아난다.
        harness.games.appDidBecomeActive()
        #expect(harness.model.chess.isWindowVisible)
        #expect(await waits.wait { harness.model.chess.pollTask != nil }, "active 로 돌아왔는데 폴링이 안 돌아왔다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 4. 한 사람 한 판 — 양방향

    @Test("한 사람 한 판은 **양방향**이다: 체스 중이면 오목 입구가, 오목 중이면 체스 입구가 막힌다")
    func oneMatchPerPersonBlocksBothDirections() async {
        // 없으면(한 방향만 막으면): 막히지 않은 쪽으로 들어가 다른 판을 **판돈째 시간패**한다. 서버가 막아 주지도
        // 않는다 — 체스 쪽 게이트만 오목을 보고(`chess__busy`) **오목 쪽 게이트는 체스를 모른다**(알려진 비대칭).
        let harness = GamesHarness(label: "chess-both-ways")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        #expect(games.chessEntryBlock == nil && games.gomokuEntryBlock == nil, "아무 판도 없는데 입구가 막혔다")

        // ① 체스 판이 흐른다 → **오목** 입구가 막힌다.
        harness.model.chess.match = Self.chessMatch()
        #expect(games.hasLiveChessMatch)
        #expect(games.gomokuEntryBlock == .chess, "체스 중인데 오목 입구가 열려 있다 — 수락하면 체스를 시간패한다")
        #expect(games.chessEntryBlock == nil, "자기 판이 자기 입구를 막았다")
        // 끝난 판은 막지 않는다(결과 화면은 판이 아니다).
        harness.model.chess.match = Self.chessMatch(finished: true)
        #expect(games.gomokuEntryBlock == nil, "끝난 체스 판이 오목 입구를 막았다")
        harness.model.chess.match = nil

        // ② 오목 판이 흐른다 → **체스** 입구가 막힌다.
        harness.model.gomoku.match = Self.gomokuMatch()
        #expect(games.hasLiveGomokuMatch)
        #expect(games.chessEntryBlock == .gomoku, "오목 중인데 체스 입구가 열려 있다")
        #expect(games.gomokuEntryBlock == nil)
        harness.model.gomoku.match = Self.gomokuMatch(finished: true)
        #expect(games.chessEntryBlock == nil, "끝난 오목 판이 체스 입구를 막았다")
        harness.model.gomoku.match = nil
        #expect(games.chessEntryBlock == nil && games.gomokuEntryBlock == nil)
        await harness.tearDown()
    }

    @Test("로봇 판은 다른 게임 입구를 막지 않는다 — 루비·순위가 없고 화면을 떠나면 시계가 멈춘다")
    func aRobotGameDoesNotBlockTheOtherEntrance() async {
        // 없으면: 로봇과 한 판 두다 둔 채 둔 판 하나가(며칠이고 남는다) 사람과의 대결 입구를 통째로 잠근다.
        let harness = GamesHarness(label: "chess-ai-no-block")
        serve(harness)
        await harness.signIn()
        harness.model.chess.startAIMatch(humanColor: .white)
        #expect(harness.model.chess.isAIMatch, "로봇 판이 안 섰다 — 이 테스트는 그 상태를 전제한다")
        #expect(harness.model.chess.match?.isFinished == false)
        #expect(!harness.games.hasLiveChessMatch, "로봇 판을 '사람과의 판'으로 셌다")
        #expect(harness.games.gomokuEntryBlock == nil, "로봇 체스 판이 오목 입구를 막았다")
        await harness.tearDown()
    }

    @Test("체스 로비 [도전] 게이트: 다른 게임 판 · 상대 대국 중 · 보낸 신청 · 내 판 · **capable 모름**을 모두 막는다")
    func theChessChallengeGateRefusesEveryBlockedCase() async {
        // 없으면: 게이트가 뷰에만 있으면 되돌려도 빨개지는 테스트가 없다(화면은 `#if os(iOS)`).
        // ★ `capable` 이 nil 인 상대는 **불가**다(`ChessWire.swift:118`) — 모르는 상대에게 신청해
        //   `target_outdated` 를 받는 것보다 낫다. 그 판정은 `ChessStore.user(from:)` 에 있고 여기서 되묻는다.
        let harness = GamesHarness(label: "chess-gate")
        serve(harness)
        await harness.signIn()
        let chess = harness.model.chess
        let ok = ChessUser(id: "u-ok", displayName: "가능", avatarURL: nil, characterID: nil,
                           isWorking: false, isCapable: true, inMatch: false)
        #expect(GamesChessChallengeGate.isEnabled(user: ok, store: chess, blockedBy: nil),
                "근무 안 함이어도 신청할 수 있어야 한다(맥 게이트와 같다)")
        // 다른 게임 판 — 양방향 가운데 이쪽.
        #expect(!GamesChessChallengeGate.isEnabled(user: ok, store: chess, blockedBy: .gomoku),
                "오목 판이 흐르는데 체스 [도전]이 열려 있다")
        let inMatch = ChessUser(id: "u-busy", displayName: "대국중", avatarURL: nil, characterID: nil,
                                isWorking: true, isCapable: true, inMatch: true)
        #expect(!GamesChessChallengeGate.isEnabled(user: inMatch, store: chess, blockedBy: nil))
        let outdated = ChessUser(id: "u-old", displayName: "구버전", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: false, inMatch: false)
        #expect(!GamesChessChallengeGate.isEnabled(user: outdated, store: chess, blockedBy: nil))

        // `capable` 이 null 인 서버 행 → isCapable false → 게이트가 막는다.
        let unknownRow = ChessUserRow(userId: "u-unknown", displayName: "모름", avatarUrl: nil, character: nil,
                                      center: nil, isWorking: true, capable: nil, inMatch: false)
        let unknown = ChessStore.user(from: unknownRow)
        #expect(unknown?.isCapable == false, "capable 이 nil 인데 가능으로 읽었다 — target_outdated 를 받는다")
        if let unknown {
            #expect(!GamesChessChallengeGate.isEnabled(user: unknown, store: chess, blockedBy: nil))
        } else {
            Issue.record("로비 행 매퍼가 사람을 못 만들었다 — 이 갈래를 잴 수 없다")
        }

        // 보낸 신청 · 내 판.
        chess.outgoing = ChessInvite(id: "i-1", peer: ok, stake: 3, expiresAt: harness.clock.now.addingTimeInterval(60))
        #expect(!GamesChessChallengeGate.isEnabled(user: ok, store: chess, blockedBy: nil), "보낸 신청이 떠 있으면 막는다")
        chess.outgoing = nil
        chess.match = Self.chessMatch()
        #expect(!GamesChessChallengeGate.isEnabled(user: ok, store: chess, blockedBy: nil))
        chess.match = nil
        chess.isBusy = true
        #expect(!GamesChessChallengeGate.isEnabled(user: ok, store: chess, blockedBy: nil))
        chess.isBusy = false
        await harness.tearDown()
    }

    @Test("체스 판이 흐르는 동안 들어온 오목 딥링크는 오목 화면을 열지 않는다 — 카드만 막으면 이 길이 남는다")
    func aGomokuDeepLinkIsRefusedWhileAChessMatchRuns() async {
        // 없으면: 오목 로비의 [수락]에는 게이트가 없다(`GomokuPhoneChallengeGate` 는 보낸 신청용이다).
        // 푸시·위젯으로 그 화면에 닿는 길이 남으면 체스 중에 오목이 시작되고 체스가 시간패한다.
        let harness = GamesHarness(label: "chess-route-block")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        // 기준선: 판이 없으면 그 링크는 **열린다**(막는 것이 깃발 덕인지 길이 끊긴 덕인지 가린다).
        #expect(games.routeStep(for: .gomokuLobby) == .push(.gomoku))
        #expect(games.routeStep(for: .gomokuInvite(matchID: "g-9")) == .push(.gomoku))
        #expect(games.pendingGomokuFocusID == "g-9")

        harness.model.chess.match = Self.chessMatch()
        #expect(games.routeStep(for: .gomokuLobby) == .popToRoot, "체스 중인데 오목 로비 링크가 화면을 열었다")
        #expect(games.routeStep(for: .gomokuInvite(matchID: "g-9")) == .popToRoot,
                "체스 중인데 오목 신청 링크가 화면을 열었다")
        #expect(games.pendingGomokuFocusID == nil, "막은 링크의 대상이 남았다 — 나중의 무관한 진입에 쓰인다")
        // 미니게임은 막지 않는다(판돈도 시계도 없다).
        #expect(games.routeStep(for: .miniGame(.tetris)) == .push(.miniGame(.tetris)))
        await harness.tearDown()
    }

    // MARK: - 5. 화면 꺼짐 방지

    @Test("1:1 체스 판이 도는 동안은 어느 화면에 있든 화면을 켜 둔다 — 로봇 판은 체스 화면에서만")
    func theScreenStaysAwakeWhileAChessMatchRuns() async {
        // 없으면: 10분 시계에 자동잠금(최소 30초)이 닿아 한 수도 못 두고 시간패한다. 체스에는 오목의
        // 자동 착수 장치가 없다(DECISIONS B4) — 잠긴 화면 뒤에서 깃발이 그냥 떨어진다.
        let harness = GamesHarness(label: "chess-idle")
        serve(harness)
        await harness.signIn()
        let games = harness.games
        #expect(!games.wantsIdleTimerDisabled, "판도 없는데 화면을 켜 두려 한다")
        harness.model.chess.match = Self.chessMatch()
        #expect(games.wantsIdleTimerDisabled, "1:1 체스 판이 도는데 화면이 꺼질 수 있다")
        harness.model.chess.match = Self.chessMatch(finished: true)
        #expect(!games.wantsIdleTimerDisabled, "끝난 판인데 화면을 계속 켜 둔다")
        harness.model.chess.match = nil

        // 로봇 판: 체스 화면이 보일 때만. 화면을 떠나면 코어가 시계를 멈추므로 기다릴 것이 없다.
        harness.model.chess.startAIMatch(humanColor: .white)
        #expect(harness.model.chess.isAIMatch)
        #expect(!games.wantsIdleTimerDisabled, "로봇 판인데 체스 화면 밖에서도 화면을 켜 둔다")
        harness.games.chessScreenDidAppear()
        #expect(games.wantsIdleTimerDisabled, "로봇 판 + 체스 화면인데 화면이 꺼질 수 있다")
        harness.games.chessScreenDidDisappear()
        #expect(!games.wantsIdleTimerDisabled)
        await harness.tearDown()
    }

    // MARK: - 6. 소스 계약 (뷰가 그 자리를 실제로 부르는가 — 맥 스위트가 뷰를 못 보므로 글자로 잰다)

    @Test("게임 탭의 두 카드가 **양방향** 차단을 각각 본다 — 한 줄만 있으면 한 방향이 열린 채다")
    func bothCardsConsultTheCrossGameBlock() throws {
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(code.contains("store.gomokuEntryBlock"),
                "오목 카드가 '체스 중' 차단을 안 본다 — 체스 중에 오목을 수락하는 길이 열려 있다")
        #expect(code.contains("store.chessEntryBlock"),
                "체스 카드가 '오목 중' 차단을 안 본다")
        #expect(code.contains("GamesDestination.chess"), "체스 입구가 게임 탭에 없다 — 화면에 닿을 길이 없다")
        #expect(code.contains("GamesChessScreen(store: store)"), "체스 목적지가 화면으로 이어지지 않는다")
    }

    @Test("체스 화면 수명: 떠날 때 stopWatching() 이 windowDidHide() **앞**이고, leaveWatch() 는 부르지 않는다")
    func theChessLifecycleHookKeepsItsOrder() throws {
        // 값으로 재는 쪽은 위 `leavingTheChessScreenDropsALiveSpectate` 다. 이 테스트는 그 값이 **우연히**
        // 맞는 경우(코어가 언젠가 진행 중 관전까지 내리게 바뀌는 날)에도 순서 계약이 남아 있게 못을 박는다.
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesStore.swift")
        let body = try #require(Self.slice(code, from: "func chessScreenDidDisappear", length: 420))
        let stop = try #require(body.range(of: "stopWatching()"), "떠나는 길에 stopWatching() 이 없다")
        let hide = try #require(body.range(of: "windowDidHide()"), "떠나는 길에 windowDidHide() 가 없다")
        #expect(stop.lowerBound < hide.lowerBound,
                "stopWatching() 이 windowDidHide() 뒤에 있다 — 진행 중인 남의 판 관전이 남는다")
        #expect(!body.contains("leaveWatch"), "떠나는 길에서 leaveWatch() 를 부른다 — 조회 둘이 나간다")
        // background 는 가림이어야 한다(숨김이면 결과 화면·관전을 잃는다).
        let background = try #require(Self.slice(code, from: "func appDidEnterBackground", length: 900))
        #expect(background.contains("context.chess.windowOcclusionDidChange(visible: false)"),
                "background 가 체스를 가림으로 멈추지 않는다")
        #expect(!background.contains("context.chess.windowDidHide"),
                "background 가 체스 창을 숨겼다 — 잠깐 나간 것이 '그 판에서 나갔다'가 된다")
    }

    @Test("판돈 문구가 거짓말을 하지 않는다 — 루비는 **수락하는 순간** 움직이고 신청만으로는 0원도 안 빠진다")
    func theStakeCopyTellsWhenTheRubyActuallyMoves() throws {
        // 없으면: "신청하면 빠져요"로 적힌 한 줄이 사용자에게 **없는 손해**를 믿게 한다(신청은 60초 뒤
        // 만료되고 그때도 루비 이동이 없다). 서버 계약은 수락 트랜잭션에서 양쪽을 차감한다.
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesChessScreen.swift")
        #expect(code.contains("수락하는 순간 두 사람 모두 걸고"),
                "판돈 캡션이 '언제 빠지는지'를 말하지 않는다")
        #expect(code.contains("신청만 한 상태에서는 루비가 빠지지 않아요"),
                "보낸 신청 줄이 '아직 안 빠졌다'를 말하지 않는다")
        for lie in ["신청하면 빠", "신청하면 루비", "신청하는 순간"] {
            #expect(!code.contains(lie), "판돈 문구가 '\(lie)…' 로 거짓을 말한다")
        }
        // 순위·관전은 **로비 안 제자리 절**이다 — 새 라우트로 밀면 폴링이 죽는다.
        #expect(code.contains("GamesChessRankingSection(store: store)"), "순위 절이 로비에 없다")
        #expect(code.contains("GamesChessWatchSection(store: store)"), "관전 절이 로비에 없다")
        #expect(code.contains("GamesChessAISection(store: store)"), "로봇과 두기 입구가 로비에 없다")
        #expect(!code.contains("navigationDestination"), "체스 화면이 자식 라우트를 쌓는다 — 절이 밀려나면 폴링이 죽는다")
        // 로봇 판은 로그인을 보지 않는다 — 화면 자체를 로그인으로 가리면 비로그인 사용자의 그 길이 막힌다.
        #expect(!code.contains("session.isSignedIn"), "체스 화면이 로그인을 게이트로 쓴다 — 로봇 판 입구가 막힌다")
    }

    // MARK: - 소스 읽기 도우미

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
