import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 안내(대표 11-10 "알까기 어디다 돌 둬야되는지 판 구분도 별로 안되어있고 어떻게 할지 유도해주는게 너무 약해.
// 뭘 하라는건지 모르겠어" → 비교 자료 · #d_cjxnVZpLHWw5 "C안 — 남은 초 고침과 함께 다음 맥 판에").
//  · 숨겨 놓기: 둘 수 있는 **실제** 칸만 파랗게(경계 = canPlace 경계) · 판 가운데 큰 안내 · 오른쪽 상자 큰 글 · 색.
//  · 쏘기 차례: 내 돌 초록 고리 · 손 안내(이 기기에서 세 번 쏠 때까지 — 횟수는 주입한 UserDefaults 에만 쓴다).
//  · 상대 차례: 상대 카드는 '쏘는 중'. · 처음 한 번 따라 하기: 로비에서만.
// 렌더는 CHECK_SNAPSHOT_DIR/alkkagi-guide/ 에 PNG 로 남긴다(사람이 열어 본다). 단언마다 결과가 갈리는 짝을 둔다.

private let agWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let agNowMs = agWall0.timeIntervalSince1970 * 1000
private func agID(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
private let agMe = AlkkagiPeer(id: agID(13), displayName: "영식", characterID: "shiba")
private let agMinsu = AlkkagiPeer(id: agID(11), displayName: "민수", characterID: "fox")

private func agPlacedStones() -> [AlkkagiGame.Stone] {
    var stones = AlkkagiGame().stones
    for index in stones.indices { stones[index].isPlaced = true }
    return stones
}

/// 연습 판(한 맥 둘이) — 둘 다 놓고 흑 차례 조준.
private func agLocalAiming() -> AlkkagiGame {
    var game = AlkkagiGame()
    for (i, x) in [100.0, 200, 300, 400, 500].enumerated() { _ = game.placeStone(stoneID: i, at: AlkkagiVector(x: x, y: 470)) }
    _ = game.confirmPlacement()
    for (i, x) in [100.0, 200, 300, 400, 500].enumerated() { _ = game.placeStone(stoneID: 5 + i, at: AlkkagiVector(x: x, y: 130)) }
    _ = game.confirmPlacement()
    return game
}

/// 숨겨 놓기(온라인) — 내 돌만 · 흑 3개 / 백 2개 놓음.
private func agPlacing(_ color: AlkkagiGame.Player, ready: Bool = false) -> AlkkagiMatch {
    var stones = AlkkagiGame().stones.filter { $0.owner == color }
    for index in 0..<(color == .black ? 3 : 2) { stones[index].isPlaced = true }
    return AlkkagiMatch(id: agID(901), revision: 1, phase: .placing, currentPlayer: .black, myColor: color,
                        black: color == .black ? agMe : agMinsu, white: color == .black ? agMinsu : agMe,
                        stones: stones, deadlineMs: agNowMs + 18_000,
                        placementRevision: 3, myReady: ready, opponentReady: false, stake: 5, watchers: 0)
}

private func agAiming(current: AlkkagiGame.Player, shotCount: Int = 4) -> AlkkagiMatch {
    AlkkagiMatch(id: agID(900), revision: 9, phase: .aiming, currentPlayer: current, myColor: .black,
                 black: agMe, white: agMinsu, stones: agPlacedStones(), deadlineMs: agNowMs + 21_000, shotCount: shotCount,
                 placementRevision: 2, myReady: true, opponentReady: true, stake: 5,
                 myMissedTurns: 0, opponentMissedTurns: 0, forfeitAfter: 3, watchers: 0)
}

@MainActor
private func agOnline(_ match: AlkkagiMatch) -> (AlkkagiOnlineStore, AlkkagiLocalModel) {
    let store = AlkkagiOnlineStore(clock: { agWall0 })
    store.me = match.myColor == .black ? agMe : agMinsu
    store.hasLoadedLobby = true
    store.rubyBalance = 42
    store.ranking = AlkkagiRankingBoard(entries: [], me: nil)
    store.state = match
    let model = AlkkagiLocalModel()
    model.soundEnabled = false
    model.attachOnline(store)
    return (store, model)
}

/// 연습 판에서 지금 차례 돌 하나를 뒤로 당겨 쏘고, 굴림이 끝날 때까지 돌린다.
@MainActor
private func agShoot(_ model: AlkkagiLocalModel) {
    let side = model.game.currentPlayer
    let stone = model.game.stones.first { $0.owner == side && $0.isPlaced && !$0.isOut }!
    let back = side == .black ? 50.0 : -50.0
    model.aim(start: stone.position, translation: AlkkagiVector(x: 0, y: back))
    model.release()
    for _ in 0..<2_000 where model.game.phase == .rolling { _ = model.game.advance(dt: 0.02) }
}

// MARK: - 렌더 도구

@MainActor
private let agCharacters = AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs)

private var agBoardRect: CGRect {
    CGRect(x: BoardGameLayout.contentPadding,
           y: BoardGameLayout.contentPadding + BoardGameLayout.headerHeight + BoardGameLayout.headerSpacing,
           width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide)
}

@MainActor
private func agRender(_ store: AlkkagiOnlineStore, model: AlkkagiLocalModel? = nil, coach: Bool? = nil,
                      name: String) throws -> NSBitmapImageRep {
    let view = AlkkagiOnlinePanel(store: store, clipsOverflowInsteadOfScroll: true, previewModel: model,
                                  previewCharacters: agCharacters, previewCoach: coach)
        .environment(\.colorScheme, .dark)
    let bitmap = try #require(CheckRenderSettle.bitmap(view, scale: 2))
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "alkkagi-guide")
    return bitmap
}

private func agCount(_ bitmap: NSBitmapImageRep, _ rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    var hits = 0
    for y in stride(from: y0, through: y1, by: 2) {
        for x in stride(from: x0, through: x1, by: 2) {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { hits += 1 }
        }
    }
    return hits
}

/// 파란 칸(나무 위에 파랑 55%) — 파랑이 빨강보다 뚜렷이 크다(나무는 빨강 > 파랑).
private func agBlue(_ r: Int, _ g: Int, _ b: Int) -> Bool { b > r + 25 && b > 90 }
/// 초록 고리(`CheckTheme.working`).
private func agGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 150 && g > r + 50 && g > b + 10 }

@MainActor
@Suite("1:1 알까기 안내 — 돌 둘 곳 · 할 일 · 손 안내 · 처음 한 번", .serialized)
struct V03xxAlkkagiGuideTests {
    @Test func 파란_칸_경계는_실제로_둘_수_있는_경계와_같다() throws {
        // 옛 그림은 판 절반(300)을 칠해 300~320 에 두면 칠한 곳인데도 빨간 원이 떴다.
        let black = AlkkagiGame()
        #expect(black.phase == .placing && black.currentPlayer == .black)
        let edge = AlkkagiGuideDrawing.blackZoneTop
        #expect(black.canPlace(stoneID: 0, at: AlkkagiVector(x: 300, y: edge)))
        #expect(!black.canPlace(stoneID: 0, at: AlkkagiVector(x: 300, y: edge - 0.5)))
        let white = try #require(AlkkagiGame.restore(stones: AlkkagiGame().stones, currentPlayer: .white, phase: .placing))
        let top = AlkkagiGuideDrawing.whiteZoneBottom
        #expect(white.canPlace(stoneID: 5, at: AlkkagiVector(x: 300, y: top)))
        #expect(!white.canPlace(stoneID: 5, at: AlkkagiVector(x: 300, y: top + 0.5)))
    }

    @Test func 숨겨_놓기_안내는_내_칸이_어디인지_말한다() {
        let (_, black) = agOnline(agPlacing(.black))
        #expect(black.status == "아래 파란 칸에 내 돌 5개를 놓으세요 (3/5)")
        #expect(black.guideBandText == "내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 3/5")
        let (_, white) = agOnline(agPlacing(.white))
        #expect(white.status == "위 파란 칸에 내 돌 5개를 놓으세요 (2/5)")
        #expect(white.guideBandText == "내 진영(위 파란 칸)에 돌 5개를 놓으세요 · 2/5")
        // 다 놓고 준비 완료면 판 위 안내는 내려간다.
        let (_, ready) = agOnline(agPlacing(.black, ready: true))
        #expect(ready.status == "준비 완료 — 상대가 놓기를 기다려요" && ready.guideBandText == nil)
        // 연습 판(한 맥 둘이)은 흑 · 백 차례를 글에 넣는다.
        let local = AlkkagiLocalModel()
        #expect(local.status == "흑돌 차례 — 아래 파란 칸에 돌 5개를 놓으세요 (0/5)")
        #expect(AlkkagiGuideText.placeRejected.contains("파란 칸"))
    }

    @Test func 쏘기_차례_안내와_상대_카드() {
        let (_, mine) = agOnline(agAiming(current: .black))
        #expect(mine.status == "내 차례 — 내 돌을 뒤로 당겼다 놓으세요")
        #expect(mine.guideBandText == nil)
        let (_, first) = agOnline(agAiming(current: .black, shotCount: 0))
        #expect(first.status == "내 차례 — 내 돌을 뒤로 당겼다 놓으세요 (첫 수는 힘 60%까지)")
        let (_, theirs) = agOnline(agAiming(current: .white))
        #expect(theirs.status == "민수님이 쏠 차례예요 — 기다려 주세요")
        #expect(AlkkagiGuideText.aiming(player: nil, holding: true, firstShotLimited: false) == "놓으면 반대쪽으로 날아가요 · Esc로 취소")
        // 상대 카드가 차례이면 '쏘는 중' — 옛날엔 상대 카드에도 '내 차례예요'가 떴다(기준선: 내 카드).
        #expect(AlkkagiGuideText.cardMessage(simultaneousPlacement: false, ready: false, isMe: false, isOnline: true,
                                             active: true, placing: false) == "쏘는 중")
        #expect(AlkkagiGuideText.cardMessage(simultaneousPlacement: false, ready: false, isMe: true, isOnline: true,
                                             active: true, placing: false) == "내 차례예요")
        #expect(AlkkagiGuideText.cardMessage(simultaneousPlacement: false, ready: false, isMe: false, isOnline: false,
                                             active: true, placing: false) == "내 차례예요", "연습 판은 둘 다 '나'")
    }

    @Test func 손_안내는_내_차례_돌을_잡기_전에만() {
        let (_, mine) = agOnline(agAiming(current: .black))
        let hint = mine.pullHintStone
        #expect(hint?.owner == .black, "내 차례 · 안 잡음 → 내 돌에 손 안내")
        #expect(hint?.position.x == 300, "판 가운데에 가장 가까운 돌")
        let (_, theirs) = agOnline(agAiming(current: .white))
        #expect(theirs.pullHintStone == nil, "상대 차례엔 없다")
        let (_, placing) = agOnline(agPlacing(.black))
        #expect(placing.pullHintStone == nil, "숨겨 놓기엔 없다")
        // 돌을 잡으면 사라진다.
        let local = AlkkagiLocalModel()
        local.soundEnabled = false
        local.game = agLocalAiming()
        #expect(local.pullHintStone != nil)
        local.aim(start: AlkkagiVector(x: 300, y: 470), translation: AlkkagiVector(x: 0, y: 40))
        #expect(local.selectedID == 2 && local.pullHintStone == nil)
        local.finishGesture()
    }

    @Test func 손_안내는_세_번_쏘면_더_안_나오고_기억된다() {
        let defaults = CheckTestScratch.defaults()
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.guideDefaults = defaults
        model.game = agLocalAiming()
        for shot in 1...3 {
            #expect(model.pullHintStone != nil, "\(shot)번째 쏘기 전엔 보인다")
            #expect(model.pullHintStone?.owner == model.game.currentPlayer, "연습 판은 지금 차례 쪽 돌")
            agShoot(model)
            #expect(model.pullHintShots == shot)
        }
        #expect(model.game.phase == .aiming)
        #expect(model.pullHintStone == nil, "세 번 쏜 뒤엔 없다")
        #expect(defaults.integer(forKey: AlkkagiLocalModel.pullHintShotsKey) == 3)
        // 같은 기기(같은 저장)의 새 판 — 처음부터 없다. 기준선: 새 저장이면 보인다.
        let again = AlkkagiLocalModel()
        again.guideDefaults = defaults
        again.game = agLocalAiming()
        #expect(again.pullHintStone == nil)
        let fresh = AlkkagiLocalModel()
        fresh.guideDefaults = CheckTestScratch.defaults("fresh")
        fresh.game = agLocalAiming()
        #expect(fresh.pullHintStone != nil)
        // 저장이 없으면(nil — 시험 · 스냅숏) 이 판에서만 센다(표준 스위트에 안 쓴다).
        #expect(AlkkagiLocalModel().guideDefaults == nil)
    }

    @Test func 손_안내_움직임은_당겼다_놓는다() {
        let start = AlkkagiGuideDrawing.pullHintPhase(0)
        let mid = AlkkagiGuideDrawing.pullHintPhase(0.45)
        let held = AlkkagiGuideDrawing.pullHintPhase(1.0)
        let released = AlkkagiGuideDrawing.pullHintPhase(1.3)
        #expect(start.pull == 0 && mid.pull > 0.3 && mid.pull < 0.7 && held.pull == 1)
        #expect(released.pull == 0 && released.release > 0.5)
        let again = AlkkagiGuideDrawing.pullHintPhase(2.45)
        #expect(abs(again.pull - mid.pull) < 1e-9 && again.release == mid.release, "2초마다 되풀이")
    }

    @Test func 처음_한_번_따라_하기는_로비에서만_한_번() {
        let defaults = CheckTestScratch.defaults()
        func shows(lobby: Bool = true, preview: Bool? = nil, snapshot: Bool = false, dismissed: Bool = false,
                   defaults: UserDefaults?) -> Bool {
            AlkkagiFirstTimeCoach.shows(lobbyVisible: lobby, preview: preview, snapshot: snapshot, dismissed: dismissed,
                                        defaults: defaults)
        }
        #expect(shows(defaults: defaults), "처음 — 로비에 뜬다")
        #expect(!shows(lobby: false, defaults: defaults), "판 · 연습 · 관전 중엔 안 뜬다(시간이 흐른다)")
        #expect(!shows(dismissed: true, defaults: defaults), "이 창에서 닫았으면 안 뜬다")
        #expect(!shows(snapshot: true, defaults: defaults), "스냅숏은 preview 로만")
        #expect(shows(preview: true, snapshot: true, defaults: nil))
        #expect(!shows(defaults: nil), "저장이 없으면 띄우지 않는다")
        AlkkagiFirstTimeCoach.markSeen(defaults)
        #expect(!shows(defaults: defaults), "본 뒤엔 다시 저절로 안 뜬다")
        #expect(AlkkagiFirstTimeCoach.steps.count == 3)
    }

    // MARK: 렌더

    @Test func 렌더_숨겨_놓기는_내_칸만_파랗다() throws {
        let (blackStore, blackModel) = agOnline(agPlacing(.black))
        let black = try agRender(blackStore, model: blackModel, name: "1-place-black")
        let (whiteStore, whiteModel) = agOnline(agPlacing(.white))
        let white = try agRender(whiteStore, model: whiteModel, name: "2-place-white")
        let board = agBoardRect
        let upper = CGRect(x: board.minX, y: board.minY, width: board.width, height: board.height * 0.4)
        let lower = CGRect(x: board.minX, y: board.minY + board.height * 0.6, width: board.width, height: board.height * 0.4)
        let blackLower = agCount(black, lower, where: agBlue), blackUpper = agCount(black, upper, where: agBlue)
        let whiteLower = agCount(white, lower, where: agBlue), whiteUpper = agCount(white, upper, where: agBlue)
        print("[alk-guide] 파랑 흑 아래 \(blackLower) 위 \(blackUpper) · 백 아래 \(whiteLower) 위 \(whiteUpper)")
        #expect(blackLower > 20_000 && blackUpper < 500, "흑 — 아래만 파랗다")
        #expect(whiteUpper > 20_000 && whiteLower < 500, "백 — 위만 파랗다")
        // 조준(숨겨 놓기 아님)은 파랑이 없다.
        let (aimStore, aimModel) = agOnline(agAiming(current: .white))
        let aim = try agRender(aimStore, model: aimModel, name: "4-wait")
        #expect(agCount(aim, board, where: agBlue) < 500)
    }

    @Test func 렌더_내_차례엔_내_돌에_초록_고리() throws {
        let (mineStore, mineModel) = agOnline(agAiming(current: .black))
        let mine = try agRender(mineStore, model: mineModel, name: "3-myshot")
        let (theirStore, theirModel) = agOnline(agAiming(current: .white))
        let theirs = try agRender(theirStore, model: theirModel, name: "4-wait-board")
        let board = agBoardRect
        let lower = CGRect(x: board.minX, y: board.minY + board.height * 0.5, width: board.width, height: board.height * 0.5)
        let mineGreen = agCount(mine, lower, where: agGreen), theirGreen = agCount(theirs, lower, where: agGreen)
        print("[alk-guide] 초록 내 차례 \(mineGreen) · 상대 차례 \(theirGreen)")
        #expect(mineGreen > 400 && theirGreen < 50)
    }

    @Test func 렌더_처음_한_번_따라_하기() throws {
        let store = AlkkagiOnlineStore(clock: { agWall0 })
        store.me = agMe
        store.hasLoadedLobby = true
        store.rubyBalance = 42
        store.ranking = AlkkagiRankingBoard(entries: [], me: nil)
        let shown = try agRender(store, coach: true, name: "0-lobby-coach")
        let plain = try agRender(store, name: "0-lobby")
        let center = CGRect(x: BoardGameLayout.contentSize.width / 2 - 150, y: BoardGameLayout.contentSize.height / 2 - 60,
                            width: 300, height: 120)
        // 카드의 [알겠어요] 단추(파랑) · 글자 — 기준선(스냅숏 기본 = 안 띄움)과 갈린다.
        let lit = agCount(shown, CGRect(x: 0, y: 0, width: BoardGameLayout.contentSize.width,
                                        height: BoardGameLayout.contentSize.height), where: agBlue)
        let base = agCount(plain, center, where: { r, g, b in r + g + b > 600 })
        let card = agCount(shown, center, where: { r, g, b in r + g + b > 600 })
        print("[alk-guide] 따라 하기 파랑 \(lit) · 가운데 밝은 점 카드 \(card) · 로비 \(base)")
        #expect(card > base + 200)
    }
}
