@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **1:1 테트리스 관전**(0.3.65 / 1.0.13)의 못. 재는 것 여섯 — 전부 **결과**다(모양이 아니다).
//
//  ① **배선 한 줄** — `tetris.spectatorFeaturesEnabled`. 켠 것이 아니라 **켠 결과로 요청이 나가는 것**을 재고,
//     스위치만 되돌린 하네스에 같은 손짓을 걸어 **0건**을 나란히 본다([[comparison-baseline-must-differ]]).
//  ② **게이트는 관전 전용 깃발 하나** — `spectatorCountUnavailable`(관전자 수만 없다)로 잠그면 멀쩡한 관전이
//     통째로 막힌다(체스가 `rankingUnavailable` 겸업으로 데인 자리 · [[client-gates-come-in-pairs]]).
//  ③ **승자를 지어내지 않는다** — 관전 봉투에 `winner` 가 없고 a/b 는 uuid 순이라 `result` 로는 자리를 모른다.
//     시간이 다 돼 보여도 진행 중이면 결과가 없다.
//  ④ **입력 0건** — 판정의 처리기가 전부 nil 이고, 소스에 제스처·조작·기권이 한 글자도 없다.
//  ⑤ **망가진 판이 와도 서지 않는다** — 길이·글자 집합이 어긋난 `board` 는 **그 자리만** 접고 숫자는 산다.
//  ⑥ **두 판이 화면에 들어간다** — 칸 변 예산이 폭과 세로를 둘 다 본다.
//
// ── 왜 이 파일이 따로 있는가 ──
// 테트리스 관전 화면은 전부 `#if os(iOS)` 안이라 **맥 스위트가 한 줄도 못 본다**(저장소 메모 '폰 뷰는 맥
// 스위트가 못 본다' — `ios/scripts/build-sim.sh` 가 유일한 그물이다). 그래서 판정을 뷰에서 떼어
// (`GamesTetrisWatchPlan` · `GamesTetrisWatchStatus` · `GamesTetrisWatchBudget` · `GamesTetrisWatchEntry.hasContent`)
// 여기서 값으로 재고, 뷰가 그 판정을 **안 지나는 길**만 글자로 막는다(주석은 걷어낸다).

@MainActor
@Suite(.serialized) struct GamesTetrisWatchTests {

    private nonisolated static let rival = "p-tetris-rival"
    private nonisolated static let other = "p-tetris-other"
    private nonisolated static let watchedID = "m-watch-1"

    // MARK: - ① 배선 한 줄 (기준선 대비)

    @Test("폰 배선이 테트리스 관전 주 스위치를 켠다 — 빠지면 [관전]도 안 뜨고 요청이 한 번도 안 나간다")
    func phoneWiringEnablesTetrisSpectatorFeatures() async {
        // 없으면: 칩이 뜨지도 않고 눌러도 관전 상태조차 서지 않는다. 화면 파일은 `#if os(iOS)` 안이라
        // 되돌려도 **빨개지는 테스트가 이것 말고는 없다**.
        let harness = GamesHarness(label: "tetris-watch-switch")
        #expect(harness.model.tetris.spectatorFeaturesEnabled,
                "MobileAppModel.init 이 tetris.spectatorFeaturesEnabled 를 안 켰다 — 관전이 통째로 죽는다")
        // 화면이 읽는 자리도 같은 스토어여야 한다(다른 인스턴스를 켜면 깃발은 참인데 화면은 그대로 꺼져 있다).
        #expect(harness.model.context.tetris === harness.model.tetris, "탭 스토어가 보는 테트리스 스토어가 딴 인스턴스다")
        #expect(harness.games.tetris === harness.model.tetris, "GamesStore.tetris 가 딴 인스턴스다")
        // 배선 값이라 로그아웃 reset 이 건드리지 않는다 — 재로그인 뒤에도 관전이 살아야 한다.
        harness.model.tetris.reset()
        #expect(harness.model.tetris.spectatorFeaturesEnabled, "reset 이 배선 값을 껐다 — 재로그인하면 관전이 안 열린다")
        await harness.tearDown()
    }

    @Test("[관전]을 누르면 `tetris_watch_live` 가 실제로 나가고 판·관전자 수가 화면 값이 된다 — 스위치만 되돌리면 0건")
    func watchingSendsTheRequestOnlyWhenTheSwitchIsOn() async {
        // 없으면: 깃발만 참이고 조회가 안 나가는 상태(창 게이트·세션 게이트가 어긋난 배선)가 위 테스트만으로는 초록이다.
        let harness = GamesHarness(label: "tetris-watch-on")
        serve(harness)
        await harness.signIn()
        harness.games.tetrisScreenDidAppear()
        #expect(await baseWaitUntil { harness.model.tetris.liveMatches.count == 1 }, "로비 카드가 안 섰다")
        #expect(harness.model.tetris.liveMatches.first?.watchers == 2, "로비 카드가 관전자 수를 안 실었다")

        harness.model.tetris.startWatching(matchID: Self.watchedID)
        #expect(await baseWaitUntil { harness.server.requests("tetris_watch_live").count >= 1 },
                "관전 조회가 나가지 않았다")
        #expect(await baseWaitUntil { harness.model.tetris.spectating?.hasServerState == true },
                "관전 응답이 화면 값으로 안 옮겨졌다")
        #expect(harness.model.tetris.spectatorCount == 5, "관전자 수가 화면 값이 안 됐다")
        #expect(harness.model.tetris.spectating?.a.lines == 7)
        #expect(harness.model.tetris.spectating?.b.toppedOut == true)
        #expect(harness.model.tetris.spectating?.isFinished == false)
        // **대국 상태 조회를 대신 부르지 않는다**(참가자 게이트에 걸려 관전자는 not_found 만 받는다).
        #expect(harness.server.requests("tetris_state").isEmpty, "관전이 참가자 전용 조회를 불렀다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 기준선이 달라야 이 테스트가 산다: 같은 손짓에서 **스위치만** 되돌리면 관전 조회가 0건이다.
        let off = GamesHarness(label: "tetris-watch-off")
        serve(off)
        off.model.tetris.spectatorFeaturesEnabled = false       // = 배선 한 줄을 지운 것
        await off.signIn()
        off.games.tetrisScreenDidAppear()
        #expect(await baseWaitUntil { off.model.tetris.liveMatches.count == 1 }, "로비는 스위치와 무관하다 — 손짓이 안 닿았다")
        off.model.tetris.startWatching(matchID: Self.watchedID)
        await off.barrier()
        await baseYield(turns: 8)
        await off.barrier()
        #expect(off.server.requests("tetris_watch_live").isEmpty,
                "스위치가 꺼졌는데 관전 조회가 나갔다: \(off.server.requests("tetris_watch_live").count)건")
        #expect(off.model.tetris.spectating == nil, "스위치가 꺼졌는데 관전 상태가 섰다")
        #expect(off.model.tetris.spectatorCount == 0)
        await off.tearDown()
    }

    // MARK: - ② 입구 게이트

    @Test("★ [관전] 칩 잠금은 **관전 전용 깃발** 하나다 — 관전자 수 깃발로 잠그면 멀쩡한 관전이 통째로 막힌다")
    func theWatchEntryLocksOnTheWatchFlagOnly() {
        let store = TetrisDuelStore()
        let live = Self.live(watchers: 0)

        // 주 스위치가 꺼진 배선: 칩 자체를 두지 않는다(눌러도 아무 일이 없는 버튼이 된다).
        #expect(GamesTetrisWatchPlan.entry(store, isMine: false) == .absent)
        #expect(!GamesTetrisWatchPlan.hasTrailingContent(store, live: live), "스위치가 꺼졌는데 슬롯이 선다")

        store.spectatorFeaturesEnabled = true
        #expect(GamesTetrisWatchPlan.entry(store, isMine: false) == .chip)
        #expect(GamesTetrisWatchPlan.entry(store, isMine: true) == .myMatch, "내 판에 칩이 선다 — 눌러도 접힌다")

        // ★ 관전자 수만 없는 창: 수 한 칸만 접고 **입구는 열려 있어야 한다**.
        store.spectatorCountUnavailable = true
        #expect(GamesTetrisWatchPlan.entry(store, isMine: false) == .chip,
                "관전자 수가 없다는 이유로 관전 입구가 잠겼다 — 두 깃발을 겸업시켰다")
        store.spectatorCountUnavailable = false

        // 순위표가 없는 창도 관전과 무관하다.
        store.rankingUnavailable = true
        #expect(GamesTetrisWatchPlan.entry(store, isMine: false) == .chip, "순위 깃발로 관전을 잠갔다")
        store.rankingUnavailable = false

        // 관전 자체가 없는 서버에서만 잠긴다.
        store.watchUnavailable = true
        #expect(GamesTetrisWatchPlan.entry(store, isMine: false) == .soon)
    }

    @Test("오른쪽 끝 슬롯은 **입구 또는 관전자 수**가 있으면 선다 — 스위치가 꺼진 배선에서도 수는 보인다")
    func theTrailingSlotShowsTheCountEvenWithoutAnEntry() {
        // 없으면: 수만 있는 행에서 폭을 안 재 "눈 3" 이 이름 줄을 밀어 판돈이 줄임표로 잘린다(오목 320pt 실측의 결).
        let store = TetrisDuelStore()                      // 스위치 꺼짐 = 입구 없음
        #expect(!GamesTetrisWatchPlan.hasTrailingContent(store, live: Self.live(watchers: 0)))
        #expect(GamesTetrisWatchPlan.hasTrailingContent(store, live: Self.live(watchers: 1)),
                "입구가 없는 행에서 관전자 수가 통째로 사라진다")
        store.spectatorFeaturesEnabled = true
        #expect(GamesTetrisWatchPlan.hasTrailingContent(store, live: Self.live(watchers: 0)))
    }

    // MARK: - ③ 승자를 지어내지 않는다

    @Test("★ 끝난 판의 승자는 **`match.winner` 로만** 가른다 — 3인칭으로 이름을 부르고, 모르면 말하지 않는다")
    func theStatusNamesTheWinnerOnlyFromTheServerUUID() {
        // 없으면 둘 중 하나다: ① `result`('challenger_win')로 a/b 중 하나를 승자로 칠한다 — a/b 는 **uuid
        // 오름차순**이라 그 글자로는 자리를 모르고, 둘일 때 맞는 식이 셋째 경우에 거짓말한다
        // ([[binary-flip-derivations-break-on-third-case]]). ② 아예 아무 말도 안 해서, 끝난 판을 본 관전자가
        // 누가 이겼는지 모른 채 화면을 떠난다.
        var loading = TetrisSpectateState(id: Self.watchedID)
        #expect(GamesTetrisWatchStatus.kind(for: loading) == .loading)
        #expect(GamesTetrisWatchStatus.headline(for: loading) == TetrisPhoneText.watchLoading)
        #expect(GamesTetrisWatchStatus.detail(for: loading) == nil, "첫 응답 전에 둘째 줄을 지어냈다")

        loading.hasServerState = true
        #expect(GamesTetrisWatchStatus.kind(for: loading) == .live)
        #expect(GamesTetrisWatchStatus.headline(for: loading) == TetrisPhoneText.playingNow)
        #expect(GamesTetrisWatchStatus.detail(for: loading) == nil, "진행 중인데 사유가 섰다")

        // 두 자리에 사람을 앉힌다(a = 테트라이벌 · b = 상대둘 — uuid 오름차순 **자리**다).
        var won = loading
        won.a.user = Self.live(watchers: 0).a
        won.b.user = Self.live(watchers: 0).b
        won.isFinished = true
        won.endReason = .topout
        // ★ `result` 는 'challenger_win' 인데 **승자 uuid 는 b 자리의 사람**이다. 역산하는 식이면 a 를 부른다.
        won.result = "challenger_win"
        won.winnerUserID = Self.other
        let headline = GamesTetrisWatchStatus.headline(for: won)
        #expect(headline == "상대둘 승리", "끝난 판 머리가 승자를 3인칭으로 안 부른다: \(headline)")
        #expect(!headline.contains("테트라이벌"), "★ `result` 로 자리를 역산해 **진 사람**을 승자로 불렀다")
        // 1인칭 금지 — 관전자에게는 둘 다 남이라 "이겼어요"·"상대" 는 누구 이야기인지 알 수 없다.
        let detail = GamesTetrisWatchStatus.detail(for: won) ?? ""
        #expect(detail == "꼭대기까지 쌓여서 끝났어요")
        for word in ["이겼어요", "졌어요", "내 판", "상대 판", "상대가"] {
            #expect(!headline.contains(word) && !detail.contains(word), "관전 문구가 1인칭으로 말한다: \(word)")
        }

        // 승자 uuid 를 **반대 자리**로 옮기면 부르는 이름도 따라 바뀐다(기준선이 달라야 위 줄이 산다).
        var otherWon = won
        otherWon.winnerUserID = Self.rival
        #expect(GamesTetrisWatchStatus.headline(for: otherWon) == "테트라이벌 승리")
        #expect(GamesTetrisWatchStatus.headline(for: otherWon) != headline, "승자를 바꿨는데 같은 글자다")

        // ★ 둘 다 거짓인 **정상 상태 셋**에서는 승자를 말하지 않는다.
        // ① 무승부 — 자리를 묻지 않는다.
        var draw = won
        draw.result = "draw"
        draw.winnerUserID = nil
        draw.endReason = .timeCap
        #expect(GamesTetrisWatchStatus.headline(for: draw) == TetrisPhoneText.watchEndedDraw)
        #expect(GamesTetrisWatchStatus.headline(for: draw) != headline, "무승부와 그 밖이 같은 글자다")
        #expect(GamesTetrisWatchStatus.detail(for: draw) == "시간이 다 돼서 끝났어요")

        // ② 승자 칸을 안 싣는 옛 서버 — `result` 는 있는데 uuid 가 없다. **이름을 지어내지 않는다.**
        var oldServer = won
        oldServer.winnerUserID = nil
        #expect(GamesTetrisWatchStatus.headline(for: oldServer) == TetrisPhoneText.watchEnded,
                "승자 uuid 가 없는데 `result` 로 이름을 지어냈다")
        #expect(GamesTetrisWatchStatus.winnerName(for: oldServer) == nil)

        // ③ 승자는 아는데 그 자리의 **이름이 비어 있다**(코어 경계가 모르면 빈 문자열을 넣는다).
        //    "— 승리" 는 아무도 가리키지 못하면서 다 끝난 것처럼 들린다.
        var namelessWinner = won
        namelessWinner.b.user = TetrisDuelUser(id: Self.other, displayName: "", avatarURL: nil, characterID: nil,
                                               isWorking: true, isCapable: true, inMatch: true)
        #expect(GamesTetrisWatchStatus.headline(for: namelessWinner) == TetrisPhoneText.watchEnded,
                "이름을 모르는 승자를 \"\(TetrisPhoneText.watchUnknownName) 승리\" 로 불렀다")

        // 사유를 모르면 둘째 줄이 서지 않는다(빈 줄을 그리지 않는다).
        var noReason = won
        noReason.endReason = nil
        #expect(GamesTetrisWatchStatus.detail(for: noReason) == nil)

        // 진행 중인 판에는 승자가 없다 — 승자 uuid 가 실려 있어도 머리는 "대결 중" 이다(코어가 그걸 비우지만,
        // 화면도 끝난 판에서만 승자를 말한다).
        var stillLive = won
        stillLive.isFinished = false
        #expect(GamesTetrisWatchStatus.headline(for: stillLive) == TetrisPhoneText.playingNow)

        // ★ 코어도 같은 약속이다: `status == "active"` 이면 시간이 다 돼 보여도 결과 칸이 빈 채다.
        let overdue = TetrisDuelStore.spectateState(
            applying: Self.watchResponse(status: "active", result: "challenger_win", reason: "topout"),
            to: TetrisSpectateState(id: Self.watchedID), a: nil, b: nil,
            aLastSeenAt: nil, bLastSeenAt: nil, startedAt: nil, finishedAt: nil)
        #expect(overdue?.isFinished == false)
        #expect(overdue?.result == nil, "진행 중인 판에 결과를 지어 넣었다")
        #expect(overdue?.endReason == nil)
    }

    @Test("★ 관전 판 보이스오버는 **이름으로** 읽는다 — 관전자에게는 둘 다 '상대'가 아니다")
    func theBoardVoiceOverNamesTheSeat() throws {
        // 없으면: 대국용 "상대 판" 이 두 자리에 똑같이 붙어, 눈이 안 보이는 사람에게는 **같은 판이 둘**이고
        // 누구의 판인지 영영 알 수 없다(대국에서는 하나뿐이라 맞는 말이 관전에서 거짓말이 된다).
        let spoken = TetrisPhoneText.watchBoardAccessibility(name: "앨리스", lines: 7, pending: 0)
        #expect(spoken == "앨리스 판, 지운 줄 7, 들어올 줄 0", "관전 판 라벨: \(spoken)")
        #expect(!spoken.contains(TetrisPhoneText.opponentBoardLabel),
                "대국용 '\(TetrisPhoneText.opponentBoardLabel)' 을 관전에 끌어다 썼다 — 누구의 상대인가")
        // 두 자리가 **다르게** 읽힌다(기준선: 라벨이 이름을 안 쓰면 이 줄이 빨개진다).
        #expect(spoken != TetrisPhoneText.watchBoardAccessibility(name: "밥", lines: 7, pending: 0))
        // 이름을 모르는 자리도 숫자는 읽힌다(라벨이 통째로 사라지지 않는다).
        #expect(TetrisPhoneText.watchBoardAccessibility(name: TetrisPhoneText.watchUnknownName, lines: 0, pending: 0)
                == "\(TetrisPhoneText.watchUnknownName) 판, 지운 줄 0, 들어올 줄 0")

        // 그리고 관전 판이 **그 식을 실제로 쓴다**(뷰는 맥 스위트가 못 본다 — 글자로 막는다).
        let code = try GamesWatcherCountTests.code(Self.watchPath)
        #expect(code.contains("TetrisPhoneText.watchBoardAccessibility("), "관전 판에 보이스오버 라벨이 없다")
        #expect(!code.contains("opponentBoardLabel"), "관전 판이 대국용 '상대 판' 라벨을 쓴다")
    }

    // MARK: - ③-b 탭을 떠나면 관전도 끊긴다

    @Test("★ 탭을 떠나면 관전이 **끊긴다** — \"안 보이는데 ping 한다\" 가 0 건이다")
    func leavingTheTabEndsTheWatch() async throws {
        // 없으면: [순위] 로 바꾸는 순간 관전 판만 화면에서 사라지고 `spectating` 은 살아 2초마다 조회가 나간다
        // (코어 `shouldPollWatch` 는 **탭을 모른다**) — 아무것도 안 보는 사람이 남의 카드에 관전자 1명으로
        // 잡히고, 나갈 문([나가기])은 그 사라진 절 안에 있어 **끌 수가 없다.**
        let harness = GamesHarness(label: "tetris-watch-tab")
        serve(harness)
        await harness.signIn()
        harness.games.tetrisScreenDidAppear()
        #expect(await baseWaitUntil { harness.model.tetris.liveMatches.count == 1 }, "로비 카드가 안 섰다")
        let tetris = harness.model.tetris
        tetris.startWatching(matchID: Self.watchedID)
        #expect(await baseWaitUntil { tetris.spectating?.hasServerState == true }, "관전이 안 섰다")

        // 기준선 ①: 관전 판이 **보이는** 탭에서는 탭 손짓이 관전을 건드리지 않는다.
        GamesTetrisWatchPlan.tabDidChange(tetris, to: .opponents)
        await harness.barrier()
        #expect(tetris.isSpectating, "관전 판이 보이는 탭인데 관전을 거뒀다")
        #expect(tetris.shouldPollWatch, "전제: 보이는 동안에는 폴링 문이 열려 있다")

        // 기준선 ②: 그 상태로 폴링 한 걸음을 밟으면 조회가 **실제로 한 건 더** 나간다
        // (이게 없으면 아래 '0건' 은 "원래 안 나간다" 와 구별되지 않는다 — [[comparison-baseline-must-differ]]).
        let before = harness.server.requests("tetris_watch_live").count
        await tetris.pollWatch(at: Date().addingTimeInterval(60))
        await harness.barrier()
        #expect(harness.server.requests("tetris_watch_live").count > before,
                "보이는 탭에서도 폴링이 안 돈다 — 아래 '0건' 이 아무 뜻이 없다")

        // ★ 탭을 떠나면: 관전이 내려가고 폴링 문이 닫힌다.
        GamesTetrisWatchPlan.tabDidChange(tetris, to: .ranking)
        await harness.barrier()
        #expect(tetris.spectating == nil, "★ 탭을 바꿨는데 관전이 살아 있다 — 안 보이는 사람이 관전자 수에 잡힌다")
        #expect(!tetris.shouldPollWatch, "화면에 없는 관전이 폴링 문을 열어 두고 있다")
        #expect(tetris.spectatorCount == 0, "안 보는 화면이 관전자 수를 들고 있다")

        // 그리고 그 뒤 폴링 걸음은 **0건**이다.
        let quiet = harness.server.requests("tetris_watch_live").count
        await tetris.pollWatch(at: Date().addingTimeInterval(120))
        await baseYield(turns: 8)
        await harness.barrier()
        #expect(harness.server.requests("tetris_watch_live").count == quiet,
                "탭을 떠났는데 관전 조회가 또 나갔다: \(harness.server.requests("tetris_watch_live").count - quiet)건")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 화면이 **그 판정을 지나는가**(뷰 한 줄이 빠지면 위 전부가 초록인 채로 기능이 죽는다).
        let screen = try GamesWatcherCountTests.code("Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift")
        #expect(screen.contains("GamesTetrisWatchPlan.tabDidChange(tetris, to: value)"),
                "탭이 바뀔 때 화면이 관전을 안 거둔다")
        // 관전 판은 [상대] 탭에만 그려진다 — 그 사실이 판정 한 곳에 적혀 있어야 위 손짓이 뜻을 가진다.
        #expect(GamesTetrisWatchPlan.showsWatch(on: .opponents))
        #expect(!GamesTetrisWatchPlan.showsWatch(on: .ranking))
        for tab in GamesTetrisLobbyTab.allCases where !GamesTetrisWatchPlan.showsWatch(on: tab) {
            let store = TetrisDuelStore()
            store.spectatorFeaturesEnabled = true
            GamesTetrisWatchPlan.tabDidChange(store, to: tab)
            #expect(!store.shouldPollWatch, "\(tab) 탭에서 폴링 문이 열려 있다")
        }
    }

    // MARK: - ④ 입력 0건

    @Test("관전 판은 **입력 처리기가 전부 nil** 이고 소스에 제스처·조작·기권이 한 글자도 없다")
    func theWatchPanelTakesNoInput() throws {
        // 없으면: 관전자가 남의 판에 조각을 먹이거나(코어가 막아도 요청은 나간다) [기권]이 서서 남의 판돈을 던진다.
        #expect(GamesTetrisWatchPlan.boardTapHandler == nil)
        #expect(GamesTetrisWatchPlan.boardDragHandler == nil)
        #expect(GamesTetrisWatchPlan.controls.isEmpty)
        #expect(!GamesTetrisWatchPlan.showsResign)

        let code = try GamesWatcherCountTests.code(Self.watchPath)
        for banned in Self.bannedInWatchSource where code.contains(banned) {
            Issue.record("관전 절에 입력·판 구동이 들어왔다: \(banned)")
        }
        // 제자리 절이다 — 새 화면을 밀면 `onDisappear` 로 폴링이 죽어 판이 영영 갱신되지 않는다.
        for pushed in ["NavigationLink", "navigationDestination", ".sheet(", "fullScreenCover"] {
            #expect(!code.contains(pushed), "관전 절이 새 화면을 민다(\(pushed))")
        }
        // 판 그림은 **코어 painter 한 벌**이다(새로 칠하지 않는다 — 맥과 폰의 같은 판이 달라진다).
        #expect(code.contains("TetrisBoardPainter.drawMiniBoard("), "관전 판을 코어 painter 로 안 그린다")
        // 그리고 로비가 **그 자리에서** 이 절로 갈아 끼운다(화면이 튀지 않는다).
        let screen = try GamesWatcherCountTests.code("Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift")
        #expect(screen.contains("GamesTetrisWatchPanel(store: tetris, watch: watch)"),
                "로비가 관전 판을 그 자리에 안 세운다")
        #expect(screen.contains("tetris.spectating"), "로비가 관전 중인지 안 본다")
    }

    // MARK: - ⑤ 망가진 판

    @Test("망가진 `board` 가 와도 그 자리만 접힌다 — 반대쪽 판과 양쪽 숫자는 산다")
    func abrokenBoardFoldsOnlyThatSeat() {
        // 없으면: 길이가 틀린 판 한 장에 화면이 통째로 빈 채로 선다(또는 디코더가 터진다).
        let broken = TetrisDuelStore.spectateSide(
            from: TetrisWatchSideRow(user: nil, board: "XXX", lines: 9, pending: 3,
                                     garbageSent: 4, toppedOut: false, lastSeenMs: nil),
            user: nil, lastSeenAt: nil, previous: .empty)
        #expect(broken.cells == nil, "망가진 판을 그대로 들었다")
        #expect(broken.board == nil, "판 글자와 칸이 따로 논다(둘은 언제나 같이 선다)")
        #expect(broken.lines == 9 && broken.pending == 3 && broken.attackSent == 4, "그 자리 숫자까지 버렸다")

        // 기준선: 멀쩡한 판은 실제로 읽힌다(안 그러면 위 단언은 '늘 nil' 일 뿐이다).
        let good = TetrisDuelStore.spectateSide(
            from: TetrisWatchSideRow(user: nil, board: Self.emptyBoard, lines: 1, pending: 0,
                                     garbageSent: 0, toppedOut: true, lastSeenMs: nil),
            user: nil, lastSeenAt: nil, previous: .empty)
        #expect(good.cells?.count == TetrisGame.visibleRows, "멀쩡한 판도 못 읽는다 — 대비가 성립하지 않는다")
        #expect(good.toppedOut)
        // 탑아웃은 **서버가 말한 사실**이고 흐리게 그릴지를 그 한 칸이 가른다(시간·결과로 역산하지 않는다).
        #expect(GamesTetrisWatchPlan.dims(good))
        #expect(!GamesTetrisWatchPlan.dims(broken))
    }

    // MARK: - ⑥ 두 판이 화면에 들어간다

    @Test("칸 변 예산이 폭과 세로를 **둘 다** 본다 — 두 판이 나란히 들어가고 상태 상자가 밀려나지 않는다")
    func theBudgetFitsTwoBoardsSideBySide() {
        // 없으면: 폭으로만 칸을 정해 판 높이가 300pt 를 넘고, iPhone SE 에서 상태 상자·캡션이 화면 밖이다
        // (체스 관전이 같은 자리에서 높이 예산으로 고쳤다).
        let inset = TetrisMiniBoardLayout.inset

        // iPhone SE(375) · 보통 뷰포트: 폭도 세로도 넉넉해 **상한**이 이긴다.
        let se = GamesTetrisWatchBudget.cell(availableWidth: 343, viewportHeight: 554)
        #expect(se == GamesTetrisWatchBudget.maximumCell, "넉넉한 화면에서 상한이 아니다: \(se)")
        // 두 판 + 틈이 실제로 가로에 들어간다.
        let twoBoards = TetrisMiniBoardLayout.boardSize(cell: se).width * 2 + GamesTetrisWatchBudget.columnGap
        #expect(twoBoards <= 343, "두 판이 가로를 넘는다: \(twoBoards)")

        // 세로가 모자라면 **높이가 이긴다**(상한보다 작아진다).
        let squeezed = GamesTetrisWatchBudget.cell(availableWidth: 343, viewportHeight: 420)
        #expect(squeezed < GamesTetrisWatchBudget.maximumCell, "세로가 모자란데 칸이 안 줄었다: \(squeezed)")
        let boards = TetrisMiniBoardLayout.boardSize(cell: squeezed).height
        #expect(boards + GamesTetrisWatchBudget.blocksAroundBoards() <= 420 + 1,
                "판 + 블록 합이 뷰포트를 넘는다: \(boards + GamesTetrisWatchBudget.blocksAroundBoards())")
        #expect(squeezed > GamesTetrisWatchBudget.minimumCell, "기준선: 이 뷰포트가 이미 하한이다 — 대비가 없다")

        // 아주 좁은 폭에서도 하한 아래로 내려가지 않는다(판이 사라지면 관전이 아니다).
        #expect(GamesTetrisWatchBudget.cell(availableWidth: 0, viewportHeight: 0) == GamesTetrisWatchBudget.minimumCell)
        #expect(GamesTetrisWatchBudget.cell(availableWidth: 120, viewportHeight: 100) == GamesTetrisWatchBudget.minimumCell)
        // 폭만 아는 첫 한 틱(뷰포트 0)에서도 두 판이 가로를 안 넘는다.
        let widthOnly = GamesTetrisWatchBudget.cell(availableWidth: 288, viewportHeight: 0)
        #expect(TetrisMiniBoardLayout.boardSize(cell: widthOnly).width * 2
                + GamesTetrisWatchBudget.columnGap <= 288)
        #expect(inset > 0, "전제: 판 테두리 여백이 0 이면 위 셈이 판 폭을 과소평가한다")
    }

    // MARK: - 픽스처 · 도우미

    private nonisolated static let watchPath = "Sources/CheckMobileKit/Games/GamesTetrisWatch.swift"

    /// 관전 절에 **있으면 안 되는** 글자. 코어 문 셋·손가락 상자·제스처·기권·판 구동이 전부 여기 있다.
    private nonisolated static let bannedInWatchSource = [
        "GamesTetrisDuelTouch", "DragGesture", "onTapGesture", "TapGesture", "simultaneousGesture",
        "moveLeftOneCell", "moveRightOneCell", "softDropOneCell", "hardDrop", "setLeftHeld",
        "tetris.resign", "store.resign", "releaseAllKeys", "TimelineView", "AingConfirmSheet"
    ]

    /// 빈 우물 200글자(10×20) — 코어 디코더가 받는 글자 집합.
    private nonisolated static var emptyBoard: String {
        String(repeating: ".", count: TetrisGame.columns * TetrisGame.visibleRows)
    }

    private nonisolated static func live(watchers: Int) -> TetrisDuelLiveMatch {
        TetrisDuelLiveMatch(
            id: watchedID,
            a: TetrisDuelUser(id: rival, displayName: "테트라이벌", avatarURL: nil, characterID: nil,
                              isWorking: true, isCapable: true, inMatch: true),
            b: TetrisDuelUser(id: other, displayName: "상대둘", avatarURL: nil, characterID: nil,
                              isWorking: true, isCapable: true, inMatch: true),
            stake: .five, startedAt: Date(timeIntervalSince1970: 1_800_000_000), watchers: watchers)
    }

    private nonisolated static func watchResponse(status: String, result: String?, reason: String?)
        -> TetrisWatchResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // swiftlint:disable:next force_try — 픽스처가 깨지면 이 파일이 재는 것이 아무 뜻이 없다.
        return try! decoder.decode(TetrisWatchResponse.self,
                                   from: Data(watchJSON(status: status, result: result, reason: reason).utf8))
    }

    /// `tetris_watch_live` 응답 한 벌(명세 §1.6). `watchers` 한 칸이 `tetris_watch` 와 다른 전부다.
    private nonisolated static func watchJSON(status: String, result: String?, reason: String?,
                                              watchers: Int? = 5) -> String {
        let resultValue = result.map { "\"\($0)\"" } ?? "null"
        let reasonValue = reason.map { "\"\($0)\"" } ?? "null"
        let finished = status == "finished" ? "1800000400000" : "null"
        let watchersValue = watchers.map { ",\"watchers\":\($0)" } ?? ""
        let a = #"{"user":{"id":"\#(rival)","display_name":"테트라이벌","avatar_url":null,"character":null,"center":null},"board":"\#(emptyBoard)","lines":7,"pending":0,"garbage_sent":2,"topped_out":false,"last_seen_ms":1800000300000}"#
        let b = #"{"user":{"id":"\#(other)","display_name":"상대둘","avatar_url":null,"character":null,"center":null},"board":"\#(emptyBoard)","lines":3,"pending":4,"garbage_sent":0,"topped_out":true,"last_seen_ms":1800000300000}"#
        return #"{"status":"ok","server_now_ms":1800000300000,"match":{"id":"\#(watchedID)","stake":5,"started_ms":1800000000000,"status":"\#(status)","result":\#(resultValue),"reason":\#(reasonValue),"finished_ms":\#(finished)},"a":\#(a),"b":\#(b)\#(watchersValue)}"#
    }

    /// 테트리스 화면이 부르는 조회 + 옆 게임 조회(허브·active 가 함께 부른다)를 스텁에 걸어 둔다.
    private func serve(_ harness: GamesHarness) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("tetris_lobby", json: Self.lobbyJSON(nowMs: nowMs))
        harness.server.setDefault("tetris_ranking",
                                  json: #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":null,"rows":[]}"#)
        harness.server.setDefault("tetris_watch_live",
                                  json: Self.watchJSON(status: "active", result: nil, reason: nil))
        harness.server.setDefault("chess_lobby", json: #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"invite_ttl_seconds":60,"ruby_balance":100,"me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0,"active_match_id":null,"outgoing_match_id":null,"incoming_match_id":null},"users":[],"matches":[]}"#)
        harness.server.setDefault("gomoku_lobby", json: #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"turn_seconds":30,"invite_ttl_seconds":60,"me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0},"users":[],"matches":[]}"#)
        harness.server.setDefault("gomoku_inbox", json: #"{"status":"ok","server_now_ms":\#(nowMs),"incoming":[],"outgoing":null}"#)
    }

    private nonisolated static func lobbyJSON(nowMs: Int) -> String {
        let card = #"{"id":"\#(watchedID)","a":{"id":"\#(rival)","display_name":"테트라이벌","avatar_url":null,"character":null},"b":{"id":"\#(other)","display_name":"상대둘","avatar_url":null,"character":null},"stake":5,"started_at_ms":\#(nowMs - 30_000),"watchers":2}"#
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"invite_ttl_seconds":60,"me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0,"active_match_id":null,"incoming":[],"outgoing":null},"users":[],"matches":[\#(card)]}"#
    }
}
