@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 관전을 **화면 수명에 묶는** 폰 배선 못(0.3.41 수리 ⓑ).
//
// ── 무엇이 틀렸었나 ──
// 코어 `GomokuStore.windowDidHide()` 는 **진행 중인** 관전을 일부러 남긴다(`GomokuStoreWatch` C14) — 맥에서 그 통지는
// '창 최소화'이고, 최소화만 해도 보던 판이 사라지면 안 되기 때문이다. 그런데 폰에서 같은 통지(`GamesStore.gomokuScreenDidDisappear`)는
// **"사용자가 화면을 떠났다"** 다. 관전 화면은 대국·결과 화면과 달리 탭 막대를 숨기지 않아 탭 이동·뒤로가 그대로 되고,
// 그래서 관전하다 탭을 옮긴 뒤 게임 탭에서 오목을 누르면 로비가 아니라 **남의 대국이 다시 열렸다**(예고도 없다 —
// 카드 문구의 `hasActiveGomokuMatch` 는 관전 중 false 다).
//
// ── 왜 이 파일이 `#if os(iOS)` 밖인가 ──
// 관전 화면 파일은 전부 `#if os(iOS)` 안이라 맥 `swift test` 가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
// 하지만 되돌아가는 자리는 뷰가 아니라 **배선 두 줄**(`stopWatching()` 호출)이고 그것은 맥에서도 컴파일·실행된다 —
// `GamesGomokuSpectateWiringTests` 가 주 스위치 한 줄을 그렇게 지키는 것과 같은 까닭이다.
//
// ── 기준선이 달라야 한다 ──
// "떠난 뒤 `spectating == nil`" 만 재면 **관전이 선 적 없어서** 초록일 수 있다(저장소 메모 '비교 기준선이 달라야 한다').
// 그래서 셋을 나란히 잰다: ① 떠나기 전에 관전이 **서버 응답까지 받아** 서 있었다 ② 떠나는 길에서 요청이 **한 건도** 안 나갔다
// (`leaveWatch()` 는 로비·받은함·순위 셋을 다시 읽는다 — 그것을 불렀으면 요청 수로 드러난다) ③ **가림**(background)은
// 나간 것이 아니라 관전이 살아 있고, **진행 중인 내 판**은 화면을 떠나도 안 끊긴다(그건 예전부터 의도다).
//
// 관례는 같은 폴더 `GamesStoreScenarioTests`·`GamesStoreHardeningTests`·`GamesGomokuSpectateWiringTests` 그대로다:
// `GamesHarness`(스텁 서버·조작 시계·임시 저장소) · 테스트 하나 몫의 대기 예산 · 끝에서 폰 금지 호출 0건.

@MainActor
@Suite(.serialized) struct GamesGomokuWatchExitTests {
    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    // MARK: - 픽스처

    /// 관전할 남의 판 id. 로비 픽스처의 `matches` 는 비어 있어 씨앗 얼굴이 없다 — 목록에서 이미 빠진 판을 누른 것과 같은 상태이고,
    /// 흑·백은 아래 응답의 `black_user`/`white_user` 로만 선다(C15).
    private nonisolated static let watchedID = "m-watch-1"

    /// `gomoku_watch` 응답 한 벌(서버 모양 그대로). 진행 중 · 백 차례 · 세 수.
    ///
    /// `black_user`/`white_user` 에 `is_working` 이 **없는 것은 빠뜨린 것이 아니라 서버 계약**이다
    /// (마이그레이션 `20260930120000_gomoku_ranking_watch.sql` — user_id·display_name·avatar_url·character·center 다섯 칸).
    /// `board` 는 null 로 둔다: 판 문자열이 있으면 그쪽이 권위라 `moves` 와 한 글자만 어긋나도 코어가 `needsFull` 로 제자리를 돈다.
    /// `move_count` 는 마지막 `seq` 와 같게 맞춰 뒀다 — 다르면 같은 이유로 처음부터 다시 받으려 한다(`spectateState`).
    private nonisolated static func watchJSON(nowMs: Int, matchID: String = watchedID) -> String {
        let moves = [
            #"{"seq":1,"color":"black","kind":"stone","x":7,"y":7,"auto":false}"#,
            #"{"seq":2,"color":"white","kind":"stone","x":6,"y":8,"auto":false}"#,
            #"{"seq":3,"color":"black","kind":"stone","x":8,"y":8,"auto":false}"#
        ].joined(separator: ",")
        let black = #"{"user_id":"p-black","display_name":"달토끼","avatar_url":null,"character":null,"center":"seoul"}"#
        let white = #"{"user_id":"p-white","display_name":"민트별","avatar_url":null,"character":null,"center":"seoul"}"#
        let match = #"{"id":"\#(matchID)","status":"active","stake":10,"black":"p-black","white":"p-white","move_count":3,"turn":"white","deadline_ms":\#(nowMs + 22_000),"turn_started_ms":\#(nowMs - 8_000),"started_ms":\#(nowMs - 95_000),"result":null,"end_reason":null,"winner":null,"finished_ms":null,"board":null}"#
        return #"{"status":"ok","server_now_ms":\#(nowMs),"match":\#(match),"moves":[\#(moves)],"black_user":\#(black),"white_user":\#(white),"black_auto_streak":0,"white_auto_streak":0,"auto_abandon_streak":3}"#
    }

    /// 빈 순위표 한 벌. 로비를 보는 순간 `spectatorWindowDidShow` 가 순위를 한 번 읽으므로, 안 걸어 두면 그 조회가
    /// 실패로 접히며 아래 요청 수 측정 창에 늦게 끼어든다.
    private nonisolated static func rankingJSON(nowMs: Int) -> String {
        #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":null,"rows":[]}"#
    }

    /// 오목 화면이 실제로 부르는 조회들(로비·받은함·순위)과 관전 응답을 스텁에 걸어 둔다.
    private func serveLobbyAndWatch(_ harness: GamesHarness) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_ranking", json: Self.rankingJSON(nowMs: nowMs))
        harness.server.setDefault("gomoku_watch", json: Self.watchJSON(nowMs: nowMs))
    }

    /// 관전이 **서버 응답까지 받아** 선 상태를 만든다(씨앗만 선 것으로는 아래 단언들이 기준선 없이 초록이 된다).
    private func enterWatch(_ harness: GamesHarness) async {
        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby }, "로비 조회가 안 닿았다 — 손짓 자체가 안 걸렸다")
        #expect(await waits.wait { harness.gomoku.hasLoadedRanking }, "순위 한 번 읽기가 안 끝났다(측정 창에 늦게 끼어든다)")
        #expect(harness.gomoku.phase == .lobby, "관전은 로비 자리에만 선다")

        harness.gomoku.startWatching(matchID: Self.watchedID)
        #expect(await waits.wait { harness.gomoku.spectating?.hasServerState == true },
                "관전 씨앗이 서버 응답으로 채워지지 않았다 — 관전이 선 적 없으면 아래 단언은 기준선 없이 초록이다")
        #expect(harness.gomoku.spectating?.id == Self.watchedID)
        #expect(harness.gomoku.spectating?.moveCount == 3)
        #expect(harness.gomoku.spectating?.isFinished == false, "진행 중인 판이어야 한다 — 끝난 판은 코어가 이미 내린다")
    }

    // MARK: - 1. 화면을 떠나면 관전이 끝난다 · 그 길에서 요청은 0건

    @Test("관전 중 오목 화면을 떠나면 관전이 끝난다 — 요청은 한 건도 내지 않는다(leaveWatch 가 아니라 stopWatching)")
    func leavingTheScreenEndsSpectating() async {
        // 없으면: 관전하다 탭을 옮긴 뒤 오목을 다시 누르면 로비가 아니라 남의 대국이 다시 열린다.
        // 코어 `windowDidHide` 는 **끝난** 관전만 내리므로(맥의 창 최소화 규칙), 끊는 자리는 이 폰 배선뿐이다.
        let harness = GamesHarness(label: "gomoku-watch-exit")
        serveLobbyAndWatch(harness)
        await harness.signIn()
        await enterWatch(harness)

        // 떠나는 길은 조회를 내면 안 된다 — 측정 전에 이미 떠난 요청·늦은 응답을 먼저 흘려보낸다(사건 장벽).
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        let before = harness.server.requests

        harness.games.gomokuScreenDidDisappear()
        #expect(harness.gomoku.spectating == nil,
                "관전 중 화면을 떠났는데 남의 판이 그대로 남았다 — 다시 들어오면 로비 대신 그 판이 열린다")
        #expect(!harness.gomoku.isWindowVisible)
        #expect(harness.gomoku.pollTask == nil, "화면을 떠났는데 안전망 폴링이 돈다")

        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        let after = harness.server.requests
        let extra = after.dropFirst(before.count).map(GamesStubServer.key)
        #expect(extra.isEmpty, "화면을 떠나는 길에서 요청이 나갔다(leaveWatch 를 불렀거나 조회를 덧붙였다): \(extra)")

        // 다시 들어오면 로비다(사용자가 실제로 보는 결과).
        harness.games.gomokuScreenDidAppear()
        #expect(harness.gomoku.spectating == nil, "다시 들어오니 남의 판이 되살아났다")
        #expect(harness.gomoku.phase == .lobby)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 2. 대조 — 가림(background)은 나간 것이 아니다

    @Test("background 는 관전을 내리지 않는다 — 앱을 잠깐 나갔다 와도 보던 판이 그대로다(가림은 나간 것이 아니다)")
    func backgroundKeepsSpectating() async {
        // 없으면: 위 수리를 화면 수명이 아니라 '가림'에 걸어도 위 테스트가 초록이다. 그러면 알림을 하나 읽고 돌아올 때마다
        // 보던 판이 사라진다(코어가 background 에 `windowDidHide` 를 쓰지 않는 것과 같은 까닭 — `appDidEnterBackground` 주석).
        let harness = GamesHarness(label: "gomoku-watch-bg")
        serveLobbyAndWatch(harness)
        await harness.signIn()
        await enterWatch(harness)

        harness.model.sceneDidEnterBackground()
        #expect(harness.gomoku.isWindowOccluded, "background 는 가림이다(창을 닫은 것이 아니다)")
        #expect(harness.games.isGomokuScreenVisible, "화면은 그대로 떠 있다")
        #expect(harness.gomoku.spectating?.id == Self.watchedID,
                "background 가 관전을 내렸다 — 알림 하나 읽고 오면 보던 판이 사라진다")

        harness.model.sceneDidBecomeActive()
        #expect(await waits.wait { !harness.gomoku.isWindowOccluded })
        #expect(harness.gomoku.spectating?.id == Self.watchedID, "돌아왔더니 관전이 사라졌다")

        // 여기서 **떠나면** 끝난다 — 같은 하네스 안에서 두 통지가 갈라지는 것을 나란히 잰다.
        harness.games.gomokuScreenDidDisappear()
        #expect(harness.gomoku.spectating == nil, "가림과 떠남이 같은 길로 흘렀다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 3. 대조 — 진행 중인 내 판은 화면을 떠나도 안 끊긴다

    @Test("진행 중인 내 판은 오목 화면을 떠나도 안 끊긴다 — 관전을 끊는 수리가 대국까지 끊지 않았다")
    func leavingTheScreenKeepsMyRunningMatch() async throws {
        // 없으면: 관전을 끊는 한 줄이 내 판까지 끊어 놓아도(또는 `leaveWatch`·`leaveMatch` 를 잘못 부르게 바뀌어도)
        // 위 두 테스트는 초록이다. 폰에서 탭을 옮기는 것은 **대국**에서는 "그만 둘게"가 아니다 — 서버 시계는 계속 흐른다.
        let harness = GamesHarness(label: "gomoku-watch-mine")
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_leave", json: #"{"status":"ok","both_left":false}"#)
        harness.server.setDefault("gomoku_state") { _ in
            .json(GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-mine", moves: [("black", "H8"), ("white", "I9")]))
        }
        await harness.signIn()

        let active = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-mine", moves: [("black", "H8"), ("white", "I9")]).utf8))
        harness.gomoku.applyState(active.state)
        #expect(harness.gomoku.match?.id == "m-mine", "픽스처가 내 판을 세우지 못했다")
        #expect(harness.gomoku.match?.isFinished == false)

        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby })
        harness.games.gomokuScreenDidDisappear()

        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        #expect(harness.gomoku.match?.id == "m-mine", "진행 중인 내 판이 화면을 떠났다고 사라졌다")
        #expect(harness.gomoku.match?.isFinished == false)
        #expect(harness.server.requests("gomoku_leave").isEmpty,
                "진행 중인 내 판에서 나가 버렸다 — 떠나 있는 사이 대국이 죽는다(결과 화면일 때만 나가는 것이 코어 규칙이다)")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }
}
