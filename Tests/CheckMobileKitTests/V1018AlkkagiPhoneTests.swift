@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 1:1 알까기(대표 판 나누기 답 "한 판에 전부" #d_xB6BJcn2nsCq · 루비 그대로 #d_t103CxfPGinB). 맥 0.3.82 와 같은 서버 · 같은 코어 스토어.
@Suite("폰 1.0.18 — 1:1 알까기")
struct V1018AlkkagiPhoneTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("문구: 로비 줄 서열(업데이트 > 대결 중 > 집중 > 근무 · 가능) · 루비 줄 · 결과 · 관전 3인칭 · 맥과 같은 규칙 다섯 줄")
    @MainActor
    func text() throws {
        #expect(AlkkagiPhoneText.userStatus(AlkkagiLobbyUser(id: "a", displayName: "가", isCapable: false, isFocused: true)) == (AlkkagiPhoneText.needsUpdate, false))
        #expect(AlkkagiPhoneText.userStatus(AlkkagiLobbyUser(id: "a", displayName: "가", inMatch: true)) == (AlkkagiPhoneText.inMatch, false))
        #expect(AlkkagiPhoneText.userStatus(AlkkagiLobbyUser(id: "a", displayName: "가", isFocused: true)) == (AlkkagiPhoneText.focused, false))
        #expect(AlkkagiPhoneText.userStatus(AlkkagiLobbyUser(id: "a", displayName: "가", isWorking: true)) == (AlkkagiPhoneText.working, true))
        #expect(AlkkagiPhoneText.userStatus(AlkkagiLobbyUser(id: "a", displayName: "가")) == (AlkkagiPhoneText.available, true))
        // 단추가 설 수 있는가는 코어 `canBeChallenged` 와 같은 판정이다(두 벌이 갈리면 단추는 켜지는데 코어가 조용히 버린다).
        for user in [AlkkagiLobbyUser(id: "a", displayName: "가", isCapable: false), AlkkagiLobbyUser(id: "a", displayName: "가", inMatch: true),
                     AlkkagiLobbyUser(id: "a", displayName: "가", isFocused: true), AlkkagiLobbyUser(id: "a", displayName: "가", isWorking: true)] {
            #expect(AlkkagiPhoneText.userStatus(user).canChallenge == user.canBeChallenged)
        }
        #expect(AlkkagiPhoneText.rubyLine(5) == "+5" && AlkkagiPhoneText.rubyLine(-3) == "−3" && AlkkagiPhoneText.rubyLine(0) == "0 · 판돈을 돌려받았어요")
        #expect(AlkkagiPhoneText.outcomeTitle(.win) == "이겼어요" && AlkkagiPhoneText.outcomeTitle(.draw) == "무승부예요")
        #expect(AlkkagiPhoneText.stakeLine(10) == "10 · 이기면 +\(DuelFee.winnerNet(stake: 10))")
        #expect(AlkkagiPhoneText.watchEndReason(.ringOut, result: .black) == "백 돌이 모두 판 밖으로 나갔어요")
        #expect(AlkkagiPhoneText.watchEndReason(.resign, result: .white) == "흑이 기권했어요")
        #expect(AlkkagiPhoneText.power(0.456) == "힘 45%" && AlkkagiPhoneText.power(1.4) == "힘 100%")
        #expect(AlkkagiPhoneText.resignWarning(stake: 5) == AlkkagiNoticeText.resignWarning
                && AlkkagiPhoneText.resignWarning(stake: nil) == AlkkagiNoticeText.resignHelp)
        // 낱말 규칙: '대결' · '신청'(대전 · 초대 금지) · 💎 글자 금지.
        let source = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesAlkkagiText.swift")
        #expect(!source.contains("대전") && !source.contains("초대") && !source.contains("💎"))
        // 규칙 다섯 줄은 맥 `AlkkagiText.rulesLines` 와 같은 글자다(같은 서버 규칙 — 두 기기에서 다르게 말하면 안 된다).
        let mac = try String(contentsOf: Self.root.appendingPathComponent("Sources/check/AlkkagiInviteBanner.swift"), encoding: .utf8)
        #expect(AlkkagiPhoneText.rulesLines.count == 5)
        for line in AlkkagiPhoneText.rulesLines { #expect(mac.contains("\"\(line)\""), "맥 규칙과 갈렸다: \(line)") }
        // 입구 그림은 맥 입구 · 일일 미션 줄과 같은 기호다.
        #expect(AlkkagiPhoneText.entrySymbol == MeText.dailyMissionIcon(game: "alkkagi"))
        #expect(mac.contains("static let symbol = \"\(AlkkagiPhoneText.entrySymbol)\""))
    }

    @Test("연습 판: 흑 다섯 놓기 → 백 다섯 놓기 → 흑이 당겼다 놓으면 날아간다(진동: 잡기 · 힘 · 쏘기) · 굴림이 멈추면 차례가 넘어간다")
    @MainActor
    func practiceFlow() {
        let model = GamesAlkkagiBoardModel()
        var haptics: [AlkkagiPhoneHaptic] = []
        model.haptic = { haptics.append($0) }
        #expect(!model.isOnline && model.canInteract && model.game.phase == .placing && model.game.currentPlayer == .black)
        func place(_ x: Double, _ y: Double) {
            model.aim(start: AlkkagiVector(x: x, y: y), translation: AlkkagiVector(x: 0, y: 0))
            model.release()
        }
        // 영역 밖(위 반)은 안 놓인다 — 안내가 선다.
        place(100, 100)
        #expect(model.game.placedCount(.black) == 0 && model.notice == AlkkagiPhoneText.placementInvalid)
        for x in [80.0, 190, 300, 410, 520] { place(x, 470) }
        #expect(model.game.placedCount(.black) == 5)
        model.confirmPlacement()
        #expect(model.game.phase == .placing && model.game.currentPlayer == .white)
        for x in [80.0, 190, 300, 410, 520] { place(x, 130) }
        model.confirmPlacement()
        #expect(model.game.phase == .aiming && model.game.currentPlayer == .black)
        // 판의 첫 수(흑)는 힘 60%까지(맥 0.3.84 · 서버 20261112150000) — 안내가 먼저 그 말을 한다.
        #expect(model.status == AlkkagiPhoneText.firstShotHint)

        // 손가락 잡기 반경: 돌 중심에서 30(반지름 20 의 1.5배) 떨어져도 잡는다(맥 마우스보다 넓다).
        haptics = []
        model.aim(start: AlkkagiVector(x: 300 + 30, y: 470), translation: AlkkagiVector(x: 0, y: 60))
        #expect(model.selectedID != nil && model.status == AlkkagiPhoneText.firstShotRelease)
        #expect(model.power > 0.4 && model.power < 0.5)
        model.aim(start: AlkkagiVector(x: 330, y: 470), translation: AlkkagiVector(x: 0, y: 200))
        #expect(abs(model.pull.length - AlkkagiGame.firstShotMaxPull) < 1e-9 && abs(model.power - 0.6) < 1e-9,
                "판의 첫 수는 당김 81(60%)에서 멈춘다 — 서버가 줄여 저장하는 값과 같다: \(model.pull.length)")
        model.release()
        #expect(model.game.phase == .rolling && model.game.shotCount == 1 && model.selectedID == nil)
        #expect(haptics.first == .select && haptics.contains(.power) && haptics.contains { if case .launch = $0 { return true }; return false })

        var now = 1_000.0
        model.tick(now: now)
        for _ in 0..<600 where model.game.phase == .rolling {
            now += 1.0 / 60
            model.tick(now: now)
        }
        #expect(model.game.phase == .aiming && model.game.currentPlayer == .white, "굴림이 멈추면 백 차례다: \(model.game.phase)")
        #expect(model.status == AlkkagiPhoneText.aimHint(.white), "둘째 수부터는 보통 안내")
        let firstWhite = model.game.stones.first { $0.owner == .white && !$0.isOut }!
        model.aim(start: firstWhite.position, translation: AlkkagiVector(x: 0, y: -200))
        #expect(model.power == 1, "둘째 수부터는 maxPull 에서 멈춘다")
        model.cancelAim()

        // 너무 짧게 당겼다 놓으면(6 미만) 쏘지 않는다 — 돌 위로 되돌리면 취소.
        let white = model.game.stones.first { $0.owner == .white && !$0.isOut }!
        model.aim(start: white.position, translation: AlkkagiVector(x: 0, y: -3))
        model.release()
        #expect(model.game.phase == .aiming && model.game.shotCount == 1)

        model.restartPractice()
        #expect(model.game.phase == .placing && model.game.placedCount(.black) == 0)
    }

    @Test("서버 판: 붙이면 서버 돌이 판이 된다(숨긴 배치 = 내 색 · 조준 = 서버 차례) · 연습 새 판은 서버 판에서 안 먹는다")
    @MainActor
    func onlineAttach() {
        let store = AlkkagiOnlineStore()
        let me = AlkkagiPeer(id: "00000000-0000-0000-0000-00000000000a", displayName: "나")
        let them = AlkkagiPeer(id: "00000000-0000-0000-0000-00000000000b", displayName: "상대")
        var stones = AlkkagiGame().stones.filter { $0.owner == .white }
        for index in stones.indices { stones[index].isPlaced = false }
        store.state = AlkkagiMatch(id: "00000000-0000-0000-0000-0000000000a1", revision: 1, phase: .placing, currentPlayer: .black,
                                   myColor: .white, black: them, white: me, stones: stones, stake: 5)
        let model = GamesAlkkagiBoardModel()
        model.attachOnline(store)
        #expect(model.isOnline && model.myColor == .white)
        #expect(model.game.phase == .placing && model.game.currentPlayer == .white, "숨긴 배치는 내 색으로 선다")
        #expect(model.status == AlkkagiPhoneText.placingMine(.white))
        #expect(!model.canInteract, "서비스가 없는 스토어(시험)에서는 손댈 수 없다 — 판 진행 문은 코어가 쥔다")

        // 서버 판이 조준으로 넘어오면(새 revision) 그 판으로 갈아 끼운다.
        let placedBlack = AlkkagiGame().stones.filter { $0.owner == .black }.map { stone -> AlkkagiGame.Stone in var s = stone; s.isPlaced = true; return s }
        let placedWhite = AlkkagiGame().stones.filter { $0.owner == .white }.map { stone -> AlkkagiGame.Stone in var s = stone; s.isPlaced = true; return s }
        store.state = AlkkagiMatch(id: "00000000-0000-0000-0000-0000000000a1", revision: 2, phase: .aiming, currentPlayer: .black,
                                   myColor: .white, black: them, white: me, stones: placedBlack + placedWhite,
                                   myReady: true, opponentReady: true, stake: 5)
        model.synchronizeOnline()
        #expect(model.game.phase == .aiming && model.game.currentPlayer == .black)
        #expect(model.status == AlkkagiPhoneText.opponentTurn(name: "상대"))
        model.restartPractice()
        #expect(model.game.phase == .aiming, "서버 판을 연습 새 판으로 지웠다")
    }

    @Test("배선: 앱 모델(시계 · 호스트 · 순위 · 관전 · 초인종 · 미션 · reset) · 러너(신호 · 조인) · 게임 탭(입구 막기 일곱 · 배지 · 카드 · 화면 · 화면 꺼짐) — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        func code(_ path: String) throws -> String { try IntegrationContractTests.code(path).filter { !$0.isWhitespace } }
        let app = try code("Sources/CheckMobileKit/App/MobileAppModel.swift")
        for needle in ["letalkkagi=AlkkagiOnlineStore(clock:{clock.now()})", "alkkagi.attach(host:host)", "alkkagi.rankingEnabled=true",
                       "alkkagi.spectatorFeaturesEnabled=true", "realtime.alkkagi=alkkagi",
                       "alkkagi.onMatchFinished={[weakme]inme?.refreshAchievementsAfterGameResult(game:\"alkkagi\")}", "alkkagi.reset()"] {
            #expect(app.contains(needle), "앱 모델 배선이 없다: \(needle)")
        }
        let runner = try code("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
        #expect(runner.contains("case.alkkagiSignal:alkkagi?.handleSignal()") && runner.contains("alkkagi?.realtimeDidJoin()"))
        let games = try code("Sources/CheckMobileKit/Games/GamesStore.swift")
        // 다른 일곱 입구(오목 · 체스 · 테트리스 · 큐브 · 뒤집기 · 길건너 · 마작)가 모두 알까기 판을 본다(마작 입구는 마지막 줄 꼴).
        let ifForm = games.components(separatedBy: "ifhasLiveAlkkagiMatch{return.alkkagi}").count - 1
        let returnForm = games.components(separatedBy: "returnhasLiveAlkkagiMatch?.alkkagi:nil").count - 1
        #expect(ifForm + returnForm == 7, "일곱 입구 중 알까기를 안 막는 곳이 있다(\(ifForm) + \(returnForm))")
        #expect(games.contains("+context.alkkagi.visibleIncomingInvites.count"), "탭 배지가 알까기 받은 신청을 안 센다")
        #expect(games.contains("ifisAlkkagiScreenVisible,hasLiveAlkkagiMatch{returntrue}"), "판 중 화면 꺼짐 방지가 알까기를 모른다")
        #expect(games.contains("context.alkkagi.presentWindow={[weakself]inself?.presentAlkkagiScreen()}"))
        #expect(games.contains("syncAlkkagiHiddenPeers()context.alkkagi.refreshLobbyIfStale()"), "허브가 알까기 받은 신청을 안 당긴다")
        #expect(GamesBusyGame.alkkagi.text == .alkkagi && ChessPhoneText.BusyGame.alkkagi.gameName == "1:1 알까기")
        #expect(ChessPhoneText.busyTitle(.alkkagi) == "1:1 알까기 대결 중이에요")
        let tab = try code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.contains("case.alkkagi:GamesAlkkagiScreen(store:store)") && tab.contains("alkkagiCard.padding(.top,12)"))
        #expect(MeText.dailyMissionCaption(game: "alkkagi", detail: "맥에서 할 수 있어요").isEmpty)
        let match = try code("Sources/CheckMobileKit/Games/GamesAlkkagiMatch.swift")
        #expect(match.contains(".hidesTabBar(for:.alkkagiMatch)"), "판 화면이 탭 막대를 안 숨긴다")
        // 판 화면에는 스크롤이 없다(판 위 끌기가 스크롤과 다투면 당김이 끊긴다).
        #expect(!match.contains("ScrollView"))
    }

    @Test("한 사람 한 판: 알까기 판이 흐르면 여섯 입구가 막히고, 다른 판이 흐르면 알까기 입구가 그 이름으로 막힌다")
    @MainActor
    func entryBlocks() async throws {
        let harness = GamesHarness(label: "v1018-alkkagi-entry")
        let games = harness.model.games
        let alkkagi = harness.model.alkkagi
        #expect(games.alkkagiEntryBlock == nil && !games.hasLiveAlkkagiMatch)
        alkkagi.state = AlkkagiMatch(id: "00000000-0000-0000-0000-0000000000b1", revision: 1, phase: .aiming, currentPlayer: .black,
                                     myColor: .black, black: AlkkagiPeer(id: "a", displayName: "나"), white: AlkkagiPeer(id: "b", displayName: "상대"),
                                     stones: AlkkagiGame().stones, stake: 3)
        #expect(games.hasLiveAlkkagiMatch)
        #expect(games.gomokuEntryBlock == .alkkagi && games.chessEntryBlock == .alkkagi && games.tetrisEntryBlock == .alkkagi)
        #expect(games.rummyEntryBlock == .alkkagi && games.reversiEntryBlock == .alkkagi && games.crossyDuelEntryBlock == .alkkagi)
        #expect(games.alkkagiEntryBlock == nil, "자기 판으로 자기 입구를 막는다")
        alkkagi.state?.phase = .finished
        alkkagi.state?.result = .black
        #expect(!games.hasLiveAlkkagiMatch && games.gomokuEntryBlock == nil, "끝난 판이 입구를 막는다")
        alkkagi.state = nil
        await harness.tearDown()
    }
}
