@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 알까기 안내(맥 0.3.86 C안의 폰 짝 · 대표 #d_xygj8oZRFlfH 5번).
// 대표 11-10 "어디다 돌 둬야되는지 판 구분도 별로 안되어있고 어떻게 할지 유도해주는게 너무 약해. 뭘 하라는건지 모르겠어".
@Suite("폰 1.0.19 — 알까기 안내")
struct V1019AlkkagiGuideTests {
    @Test("경계: 파랗게 칠하는 칸 = 실제로 둘 수 있는 칸(코어 canPlace) — 흑 y ≥ 320 · 백 y ≤ 280")
    func zoneMatchesCanPlace() {
        var game = AlkkagiGame()
        let black = game.stones.first { $0.owner == .black }!
        #expect(game.canPlace(stoneID: black.id, at: AlkkagiVector(x: 300, y: AlkkagiPhoneGuideGeometry.blackZoneTop)))
        #expect(!game.canPlace(stoneID: black.id, at: AlkkagiVector(x: 300, y: AlkkagiPhoneGuideGeometry.blackZoneTop - 0.5)))
        for x in [80.0, 190, 300, 410, 520] {
            let id = game.stones.first { $0.owner == .black && !$0.isPlaced }!.id
            _ = game.placeStone(stoneID: id, at: AlkkagiVector(x: x, y: 470))
        }
        _ = game.confirmPlacement()
        let white = game.stones.first { $0.owner == .white }!
        #expect(game.currentPlayer == .white)
        #expect(game.canPlace(stoneID: white.id, at: AlkkagiVector(x: 300, y: AlkkagiPhoneGuideGeometry.whiteZoneBottom)))
        #expect(!game.canPlace(stoneID: white.id, at: AlkkagiVector(x: 300, y: AlkkagiPhoneGuideGeometry.whiteZoneBottom + 0.5)))
    }

    @Test("글: 맥 C안과 같은 글자 — 폰은 취소 꼬리만 '돌 위로 되돌리면 취소'")
    func copy() {
        #expect(AlkkagiPhoneGuideText.band(side: .black, placed: 2) == "내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 2/5")
        #expect(AlkkagiPhoneGuideText.band(side: .white, placed: 0) == "내 진영(위 파란 칸)에 돌 5개를 놓으세요 · 0/5")
        #expect(AlkkagiPhoneGuideText.placing(side: .black, placed: 3, player: nil) == "아래 파란 칸에 내 돌 5개를 놓으세요 (3/5)")
        #expect(AlkkagiPhoneGuideText.placing(side: .white, placed: 1, player: .white) == "백돌 차례 — 위 파란 칸에 돌 5개를 놓으세요 (1/5)")
        #expect(AlkkagiPhoneGuideText.placedWaiting == "준비 완료 — 상대가 놓기를 기다려요")
        #expect(AlkkagiPhoneGuideText.placeRejected == "파란 칸 안에, 다른 돌과 겹치지 않게 놓아 주세요")
        #expect(AlkkagiPhoneGuideText.opponentTurn("영희") == "영희님이 쏠 차례예요 — 기다려 주세요")
        #expect(AlkkagiPhoneGuideText.aiming(player: nil, holding: false, firstShotLimited: false) == "내 차례 — 내 돌을 뒤로 당겼다 놓으세요")
        #expect(AlkkagiPhoneGuideText.aiming(player: nil, holding: false, firstShotLimited: true)
                == "내 차례 — 내 돌을 뒤로 당겼다 놓으세요 (첫 수는 힘 60%까지)")
        #expect(AlkkagiPhoneGuideText.aiming(player: nil, holding: true, firstShotLimited: false) == "놓으면 반대쪽으로 날아가요 · 돌 위로 되돌리면 취소")
        #expect(!AlkkagiPhoneGuideText.aiming(player: nil, holding: true, firstShotLimited: true).contains("Esc"), "폰에 Esc 가 없다")
        #expect(AlkkagiPhoneGuideText.handHint == "뒤로 당겼다 놓기")
        #expect(AlkkagiPhoneFirstTimeCoach.steps.map(\.title) == [
            "파란 칸(내 진영)에 내 돌 5개를 숨겨 놓아요", "내 차례가 오면 내 돌을 뒤로 당겼다 놓아요", "상대 돌을 판 밖으로 모두 밀어내면 이겨요",
        ])
        #expect(AlkkagiPhoneFirstTimeCoach.shows(seen: false) && !AlkkagiPhoneFirstTimeCoach.shows(seen: true))
    }

    @Test("손 안내: 쏘기 차례 · 돌을 잡기 전에만 · 판 가운데에 가까운 내 돌 · 세 번 쏘면 사라지고 그 수를 기억한다(시험 스위트)")
    @MainActor
    func pullHintCountsThreeShots() {
        let model = GamesAlkkagiBoardModel()
        let defaults = MobileTestScratch.defaults("pull-hint")
        model.guideDefaults = defaults
        func place(_ x: Double, _ y: Double) {
            model.aim(start: AlkkagiVector(x: x, y: y), translation: AlkkagiVector(x: 0, y: 0))
            model.release()
        }
        #expect(model.pullHintStone == nil && model.guideBandText == "내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 0/5")
        for x in [80.0, 190, 300, 410, 520] { place(x, 470) }
        #expect(model.guideBandText == "내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 5/5")
        model.confirmPlacement()
        #expect(model.guideBandText == "내 진영(위 파란 칸)에 돌 5개를 놓으세요 · 0/5", "연습 판은 지금 놓는 쪽")
        for x in [80.0, 190, 300, 410, 520] { place(x, 130) }
        model.confirmPlacement()
        #expect(model.game.phase == .aiming && model.guideBandText == nil)
        #expect(model.guideIsMyAim && model.pullHintStone?.position.x == 300, "가운데 돌(x 300)에 손이 붙는다")
        // 돌을 잡으면 손 안내는 사라진다.
        model.aim(start: AlkkagiVector(x: 300, y: 470), translation: AlkkagiVector(x: 0, y: 40))
        #expect(model.pullHintStone == nil && !model.guideIsMyAim)
        var now = 1_000.0
        func shootAndSettle(from start: AlkkagiVector) {
            model.aim(start: start, translation: AlkkagiVector(x: 0, y: start.y > 300 ? 40 : -40))
            model.release()
            model.tick(now: now)
            for _ in 0..<900 where model.game.phase == .rolling {
                now += 1.0 / 60
                model.tick(now: now)
            }
        }
        model.release()
        model.tick(now: now)
        for _ in 0..<900 where model.game.phase == .rolling { now += 1.0 / 60; model.tick(now: now) }
        #expect(model.pullHintShots == 1 && defaults.integer(forKey: GamesAlkkagiBoardModel.pullHintShotsKey) == 1)
        for _ in 0..<4 where model.game.phase == .aiming {
            guard let stone = model.game.stones.first(where: { $0.owner == model.game.currentPlayer && $0.isPlaced && !$0.isOut }) else { break }
            shootAndSettle(from: stone.position)
        }
        #expect(model.pullHintShots == GamesAlkkagiBoardModel.pullHintShotLimit, "세 번에서 멈춘다: \(model.pullHintShots)")
        #expect(model.pullHintStone == nil, "세 번 쏜 뒤에도 손이 나온다")
        // 새 판(같은 기기)도 기억한 수를 읽는다.
        let fresh = GamesAlkkagiBoardModel()
        fresh.guideDefaults = defaults
        #expect(fresh.pullHintShots == GamesAlkkagiBoardModel.pullHintShotLimit)
    }

    @Test("손 안내 박자: 2초 한 바퀴 — 당김 0→1 · 버팀 · 놓음(맥과 같은 박자)")
    func pullHintPhase() {
        #expect(AlkkagiPhoneGuideGeometry.pullHintPhase(0).pull == 0)
        #expect(AlkkagiPhoneGuideGeometry.pullHintPhase(0.95) == (1, 0))
        #expect(AlkkagiPhoneGuideGeometry.pullHintPhase(1.2).pull == 0 && AlkkagiPhoneGuideGeometry.pullHintPhase(1.2).release == 1)
        #expect(AlkkagiPhoneGuideGeometry.pullHintPhase(2.45).pull > 0.3)
    }

    @Test("배선: 판이 내 칸 그림 · 초록 고리 · 손 안내 · 가운데 띠를 그리고 · 앱은 표준 스위트에 횟수를 기억 · 로비에 처음 한 번 카드 · 상태 상자 — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        let board = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesAlkkagiBoard.swift").filter { !$0.isWhitespace }
        #expect(board.contains("GamesAlkkagiGuideDrawing.zones(context:context,size:size,mine:player)"))
        #expect(board.contains("ifmodel.guideIsMyAim{GamesAlkkagiGuideDrawing.myStones("))
        #expect(board.contains("iflethint=model.pullHintStone{GamesAlkkagiPullHint(stone:hint,mine:model.guideSide,reduced:reduceMotion)"))
        #expect(board.contains("iflettext=model.guideBandText{Text(text)"))
        #expect(board.contains("ifmodel.guideDefaults==nil{model.guideDefaults=.standard}"))
        #expect(!board.contains("MobileTheme.accent.opacity(0.12)"), "옛 반쪽 칠하기가 남았다")
        let lobby = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesAlkkagiScreen.swift").filter { !$0.isWhitespace }
        #expect(lobby.contains("@AppStorage(AlkkagiPhoneFirstTimeCoach.seenKey)privatevarcoachSeen=false"))
        #expect(lobby.contains("ifAlkkagiPhoneFirstTimeCoach.shows(seen:coachSeen){GamesAlkkagiCoachCard{coachSeen=true}}"))
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesAlkkagiMatch.swift").filter { !$0.isWhitespace }
        #expect(match.contains("returnGamesAlkkagiStatusBox(text:headline.0,tint:headline.1,"))
        #expect(match.contains("GamesAlkkagiStatusBox(text:model.notice??model.status,tint:practiceTint(game),"))
    }
}
