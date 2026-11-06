import AppKit
import CheckRenderTestSupport
import Foundation
import Metal
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 길건너 **화면** 렌더(SPEC v1.3 §9.2 · §9.3 · §10.2 U 줄) — 로비 · 카운트다운 · 판 40:70 · 겹침 40:41 · 부활 3 ·
// 판정 기다림(100 · 3분) · 결과 승/패/무/no_show/void.
//
// 없으면 초록으로 지나가는 결함(각 시험 첫 줄 주석에 하나씩):
//   · 트랙 위 두 얼굴 점이 점수 비로 서지 않는다(상대 점수와 내 점수 자리가 뒤바뀌거나 한쪽이 고정) — 4:7 비를 픽셀로 잰다.
//   · 겹칠 때 낮은 점수가 위에 그려져 누가 앞인지 흐려진다(대표 카드 "겹치면 점수가 높은 쪽이 위").
//   · 내 점이 서버 me 점수(늦은 값)를 따라간다(CC-25) · 결과 카드 '나' 숫자가 Q3 답과 다르다(CC-4) ·
//     '얼림 + 부활' 이 한 장에 같이 뜬다(CC-20) · 남의 얼굴이 이니셜로 떨어진다(CC-7).
//
// 그림: 판 전체는 ImageRenderer(scale 2, `CheckRenderSettle` 로 굳힌 뒤)로 찍는다. **SCNView 는 ImageRenderer 가 빈 칸으로 그리므로**
// (MC:91) 3D 판은 오프스크린 `SCNRenderer` 로 따로 찍어 패널의 `previewCanvas` 로 넣는다 — 그 그림이 있으면 패널은 SCNView 를
// 마운트하지 않는다. PNG 는 `CHECK_SNAPSHOT_DIR`(없으면 임시 폴더) 바로 아래.
//
// 스토어는 네트워크 없는 `CrossyDuelStore(uptime:)`(host nil)이고, C1 표면의 `internal(set)` 값(`match` · `duel` · `phase` …)을
// `@testable` 로 직접 세운다. 단조 시계를 고정해 남은 시간·카운트다운이 매번 같은 그림이 된다.

// MARK: - 픽스처

private let cdWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let cdT: TimeInterval = 1_000
private let cdMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
private let cdSeed = 20_261_106

private func cdUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true,
                    inMatch: Bool = false, focused: Bool = false, character: String? = "fox") -> CrossyDuelUser {
    CrossyDuelUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
                   avatarURL: nil, characterID: character, isWorking: working, isCapable: capable,
                   inMatch: inMatch, isFocused: focused)
}

private let cdMinsu = cdUser("민수", 11, character: "fox")
private let cdJunho = cdUser("준호", 12, character: "squirrel")
private let cdSeoyeon = cdUser("서연", 16, character: "ghost")

/// 이 빌드가 초상을 그릴 수 있는 캐릭터 전부를 아는 표(앱의 `WorkTimerStore.appUserCharacters` 시작값과 같다).
@MainActor
private let cdCharacters = AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs)

@MainActor
private func cdStore() -> CrossyDuelStore {
    let store = CrossyDuelStore(clock: { cdWall0 }, uptime: { cdT })
    store.hasLoadedLobby = true
    store.rubyBalance = 42
    store.record = CrossyDuelRecord(wins: 7, losses: 3, draws: 1)
    return store
}

@MainActor
private func cdLobbyStore() -> CrossyDuelStore {
    let store = cdStore()
    store.users = [
        cdMinsu, cdJunho, cdSeoyeon,
        cdUser("태화", 14, inMatch: true),
        cdUser("옛버전사용자", 15, capable: false),
        cdUser("하늘", 17, working: false, focused: true),
        cdUser("가장긴별명열두글자입니다", 19),
    ]
    store.ranking = CrossyDuelRankingBoard(
        entries: [cdMinsu, cdJunho, cdSeoyeon].enumerated().map { index, user in
            CrossyDuelRankEntry(id: user.id, rank: index + 1, user: user, wins: 9 - index, losses: index, draws: 1,
                                points: 9 - index * 2)
        },
        me: CrossyDuelMyRank(rank: 4, wins: 7, losses: 3, draws: 1, points: 4), recordSince: cdWall0)
    store.incoming = [
        CrossyDuelInvite(id: "in-1", peer: cdMinsu, stake: 5, expiresAt: cdWall0.addingTimeInterval(48)),
        CrossyDuelInvite(id: "in-2", peer: cdJunho, stake: 3, expiresAt: cdWall0.addingTimeInterval(40)),
    ]
    store.outgoing = CrossyDuelInvite(id: "out-1", peer: cdSeoyeon, stake: 10, expiresAt: cdWall0.addingTimeInterval(31))
    return store
}

/// 1:1 판 엔진 — 같은 씨앗으로 열고 줄 `score` 에 세운다(재개와 같은 부활 자리 규칙).
private func cdGame(score: Int, deaths: Int = 2) -> CrossyGame {
    var game = CrossyGame(seed: UInt64(cdSeed), rules: .duel)
    game.begin()
    if score > 0 { game.restore(row: score, score: score, deaths: deaths) }
    return game
}

/// 부활 대기(`.over`) 판 — 줄 `score` 다음 찻길에서 차에 치인 뒤 `after` 초.
private func cdRespawnGame(score: Int, after: TimeInterval = 0.2) -> CrossyGame {
    var game = cdGame(score: score)
    let row = score + 1
    let x = Double(CrossyGame.startColumn)
    game.replaceLane(CrossyGame.Lane(row: row, kind: .road, direction: 1, speed: 2,
                                     movers: [CrossyGame.Mover(x: x - CrossyGame.carLength / 2, length: CrossyGame.carLength)]))
    game.placePlayerForTesting(row: row, x: x)
    var t = 0.0
    while game.death == nil, t < 2 {
        game.step(dt: 1.0 / 120)
        t += 1.0 / 120
    }
    var waited = 0.0
    while waited < after - 1e-9 {
        game.step(dt: 1.0 / 120)
        waited += 1.0 / 120
    }
    return game
}

private func cdMatch(stake: Int = 5, opponent: CrossyDuelUser = cdMinsu, myServer: Int = 0, opponentScore: Int = 0,
                     opponentDeaths: Int = 1, finished: Bool = false, outcome: CrossyDuelOutcome? = nil,
                     reason: CrossyDuelEndReason? = nil, finalMe: Int? = nil, finalOpponent: Int? = nil,
                     delta: Int? = nil, meReady: Bool = true, opponentReady: Bool = true) -> CrossyDuelMatchState {
    CrossyDuelMatchState(
        id: "c0de0000-0000-4000-8000-000000000067", stake: stake, seed: cdSeed, opponent: opponent,
        acceptedAt: cdWall0.addingTimeInterval(-30), readyDeadline: cdWall0.addingTimeInterval(24),
        meReady: meReady, opponentReady: opponentReady, myServerScore: myServer, opponentScore: opponentScore,
        opponentDeaths: opponentDeaths, isFinished: finished, outcome: outcome, endReason: reason,
        finalMyScore: finalMe, finalOpponentScore: finalOpponent, rubyDelta: delta,
        finishedAt: finished ? cdWall0 : nil)
}

/// 판 중 스토어. 판은 `elapsed` 초 전에 시작했다(남은 시간 = 180 − elapsed).
@MainActor
private func cdPlayingStore(game: CrossyGame, myServer: Int? = nil, opponentScore: Int, opponent: CrossyDuelUser = cdMinsu,
                            elapsed: TimeInterval = 19) -> CrossyDuelStore {
    let store = cdStore()
    store.match = cdMatch(opponent: opponent, myServer: myServer ?? game.score, opponentScore: opponentScore)
    store.duel = CrossyDuelSession(seed: cdSeed, startedGame: game, startAt: cdT - elapsed)
    store.phase = .playing
    return store
}

@MainActor
private func cdFinishedStore(outcome: CrossyDuelOutcome?, reason: CrossyDuelEndReason, finalMe: Int, finalOpponent: Int,
                             delta: Int, local: Int?, meReady: Bool = true, opponentReady: Bool = true) -> CrossyDuelStore {
    let store = cdStore()
    store.match = cdMatch(myServer: finalMe, opponentScore: finalOpponent, finished: true, outcome: outcome, reason: reason,
                          finalMe: finalMe, finalOpponent: finalOpponent, delta: delta,
                          meReady: meReady, opponentReady: opponentReady)
    if let local {
        store.duel = CrossyDuelSession(seed: cdSeed, startedGame: cdGame(score: local), startAt: cdT - 120)
    }
    store.phase = .finished
    return store
}

// MARK: - 그림 도우미

private enum CDPanelRenderError: Error { case render }

/// 3D 판 한 장(344×356pt @2x) — 오프스크린 SCNRenderer. 씬은 한 벌을 돌려 쓴다(모델 읽기가 비싸다).
@MainActor
private enum CDScene {
    static let pixelSize = CGSize(width: 688, height: 712)
    static let scene = CrossyScene.mac()

    static func snapshot(_ game: CrossyGame) throws -> CGImage {
        scene.apply(game, reduceMotion: true)
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal 이 없다")
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        if cg.width == Int(pixelSize.width), cg.height == Int(pixelSize.height) { return cg }
        let ctx = try #require(CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
                                         bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(origin: .zero, size: pixelSize))
        return try #require(ctx.makeImage())
    }
}

/// 3D 대신 넣는 단색 판(688×712px) — 3D 가 필요 없는 재기 시험이 SCNView 를 마운트하지 않게(ImageRenderer 는 SCNView 를
/// 빈 칸으로 그린다 · 굽는 장마다 씬을 새로 읽는다).
@MainActor
private let cdFlatCanvas: CGImage = {
    let ctx = CGContext(data: nil, width: 688, height: 712, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.24, blue: 0.20, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 688, height: 712))
    return ctx.makeImage()!
}()

/// 패널 한 장(660×504 · scale 2). 판 화면이면 3D 를 `previewCanvas` 로 넣는다(`threeD` 가 거짓이면 단색 판).
@MainActor
private func cdRender(_ store: CrossyDuelStore, name: String? = nil, tab: CrossyDuelLobbyTab? = nil,
                      stakeTarget: CrossyDuelUser? = nil, stake: CrossyDuelStake? = nil,
                      confirmResign: Bool = false, threeD: Bool = true) throws -> NSBitmapImageRep {
    var canvas: CGImage?
    if store.phase != .lobby, let match = store.match {
        canvas = threeD ? try CDScene.snapshot(store.duel?.game ?? CrossyDuelCanvasLeaf.placeholder(match)) : cdFlatCanvas
    }
    let panel = CrossyDuelPanel(store: store, me: { cdMe }, clipsOverflowInsteadOfScroll: true,
                                previewStakeTarget: stakeTarget, previewStakeSelection: stake,
                                previewConfirmResign: confirmResign, previewLobbyTab: tab, previewCanvas: canvas,
                                previewCharacters: cdCharacters)
        .environment(\.colorScheme, .dark)
    guard let bitmap = CheckRenderSettle.bitmap(panel, scale: 2) else { throw CDPanelRenderError.render }
    if let name { cdSave(bitmap, name) }
    return bitmap
}

/// 경주 띠 한 장(순수 뷰 — 620×44 · scale 2).
@MainActor
private func cdBand(my: Int, opponent: Int, opponentUser: CrossyDuelUser = cdMinsu) throws -> CGImage {
    let band = CrossyDuelRaceBand(
        snapshot: CrossyDuelRaceSnapshot(myScore: my, opponentScore: opponent, goal: 100, myDeaths: 0, opponentDeaths: 0,
                                         remaining: 161),
        me: cdMe, myUserID: nil, opponent: opponentUser, isFinished: false)
        .background(CheckTheme.background)
        .environment(\.appUserCharacters, cdCharacters)
        .environment(\.colorScheme, .dark)
    let bitmap = try #require(CheckRenderSettle.bitmap(band, scale: 2))
    return try #require(bitmap.cgImage)
}

private func cdSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots/crossy-duel", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: base.appendingPathComponent("crossy-duel-\(name).png"))
}

/// `rect`(pt) 안에서 `target` 과 채널마다 `tolerance` 안쪽인 픽셀들의 x 범위(px)와 개수.
private func cdInk(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int = 40,
                   in rect: CGRect) -> (minX: Int, maxX: Int, count: Int) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, -1, -1) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    var minX = Int.max, maxX = -1, count = 0
    guard x0 <= x1, y0 <= y1 else { return (minX, maxX, 0) }
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if abs(Int(data[o]) - target.0) <= tolerance, abs(Int(data[o + 1]) - target.1) <= tolerance,
               abs(Int(data[o + 2]) - target.2) <= tolerance {
                minX = min(minX, x); maxX = max(maxX, x); count += 1
            }
        }
    }
    return (minX, maxX, count)
}

/// 아주 밝은(거의 흰) 픽셀 수 — 큰 겹 숫자의 잉크.
private func cdBright(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Int {
    cdInk(bitmap, near: (250, 250, 250), tolerance: 10, in: rect).count
}

// 테마 색(sRGB 0~255). 띠의 얼굴 점 테두리: 나 = accent(파랑) · 상대 = pending(주황).
private let cdBlue = (84, 171, 255)
private let cdOrange = (255, 184, 84)

/// 띠 안 얼굴 점 **윗 호**만 보는 줄(트랙 선 · 눈금 · 깃발 · 얼굴 안쪽을 피한다 — 테두리 바깥 2pt 만).
private func cdArcRows(bandTop: CGFloat) -> (minY: CGFloat, maxY: CGFloat) {
    let mid = bandTop + CrossyDuelWindowLayout.raceBandHeight / 2
    let outer = CrossyDuelRaceTrackLayout.dotDiameter / 2
    return (mid - outer + 0.2, mid - CrossyDuelRaceTrackLayout.faceDiameter / 2 - 0.4)
}

/// 띠 안 트랙 구간(점수 글자 · 시계를 빼고 점이 설 수 있는 x 만).
private func cdTrackScanRect(bandLeft: CGFloat, bandTop: CGFloat) -> CGRect {
    let rows = cdArcRows(bandTop: bandTop)
    let start = bandLeft + CrossyDuelRaceTrackLayout.trackStartX - CrossyDuelRaceTrackLayout.dotDiameter / 2 - 1
    let end = bandLeft + CrossyDuelRaceTrackLayout.trackEndX(bandWidth: CrossyDuelWindowLayout.innerWidth)
        + CrossyDuelRaceTrackLayout.dotDiameter / 2 + 1
    return CGRect(x: start, y: rows.minY, width: end - start, height: rows.maxY - rows.minY)
}

/// 한 색 점의 중심 x(pt) — 윗 호의 좌우 끝 가운데.
private func cdDotCenter(_ bitmap: NSBitmapImageRep, color: (Int, Int, Int), bandLeft: CGFloat, bandTop: CGFloat) -> CGFloat? {
    let ink = cdInk(bitmap, near: color, in: cdTrackScanRect(bandLeft: bandLeft, bandTop: bandTop))
    guard ink.count > 0 else { return nil }
    return (CGFloat(ink.minX + ink.maxX) / 2 + 0.5) / 2
}

// MARK: - 시험

@MainActor
@Suite("1:1 길건너 — 화면 렌더(SPEC §9.2 · §9.3)", .serialized)
struct V03xxCrossyDuelPanelRenderTests {

    // MARK: 증거 PNG

    @Test("증거: 로비 · 카운트다운 · 판 40:70 · 겹침 40:41 · 부활 3 · 판정 기다림 · 결과 다섯 — 노란 상자 0 · 비지 않음")
    func evidenceStills() throws {
        // 없으면: Picker·TextField 가 섞여 ImageRenderer 가 노란 상자로 그리거나, 한 장면이 통째로 빈 그림이어도 초록이다.
        var shots: [(String, NSBitmapImageRep)] = []
        shots.append(("01-lobby", try cdRender(cdLobbyStore(), name: "01-lobby")))
        shots.append(("02-lobby-ranking", try cdRender(cdLobbyStore(), name: "02-lobby-ranking", tab: .ranking)))
        shots.append(("03-stake", try cdRender(cdLobbyStore(), name: "03-stake", stakeTarget: cdMinsu, stake: .five)))

        let countdown = cdStore()
        countdown.match = cdMatch()
        var session = CrossyDuelSession(seed: cdSeed)
        session.syncStart(startAtMs: 2_500, serverNowMs: 0, localNow: cdT)
        countdown.duel = session
        countdown.phase = .countdown
        shots.append(("04-countdown", try cdRender(countdown, name: "04-countdown")))

        shots.append(("05-play-40-70", try cdRender(cdPlayingStore(game: cdGame(score: 40), opponentScore: 70),
                                                   name: "05-play-40-70")))
        shots.append(("06-overlap-40-41", try cdRender(cdPlayingStore(game: cdGame(score: 40), opponentScore: 41),
                                                      name: "06-overlap-40-41")))
        shots.append(("07-respawn-3", try cdRender(cdPlayingStore(game: cdRespawnGame(score: 40), opponentScore: 52),
                                                  name: "07-respawn-3")))
        shots.append(("08-waiting-goal", try cdRender(cdPlayingStore(game: cdGame(score: 100, deaths: 3), opponentScore: 87,
                                                                     elapsed: 151), name: "08-waiting-goal")))
        shots.append(("09-waiting-time", try cdRender(cdPlayingStore(game: cdGame(score: 64, deaths: 4), opponentScore: 71,
                                                                     elapsed: 181), name: "09-waiting-time")))
        shots.append(("10-confirm-resign", try cdRender(cdPlayingStore(game: cdGame(score: 22), opponentScore: 30),
                                                       name: "10-confirm-resign", confirmResign: true)))

        shots.append(("11-result-win", try cdRender(
            cdFinishedStore(outcome: .win, reason: .goal, finalMe: 100, finalOpponent: 87, delta: 5, local: 100),
            name: "11-result-win")))
        shots.append(("12-result-loss", try cdRender(
            cdFinishedStore(outcome: .loss, reason: .goal, finalMe: 95, finalOpponent: 100, delta: -5, local: 97),
            name: "12-result-loss")))
        shots.append(("13-result-draw", try cdRender(
            cdFinishedStore(outcome: .draw, reason: .timeCap, finalMe: 64, finalOpponent: 64, delta: 0, local: 64),
            name: "13-result-draw")))
        shots.append(("14-result-noshow", try cdRender(
            cdFinishedStore(outcome: .draw, reason: .noShow, finalMe: 0, finalOpponent: 0, delta: 0, local: nil,
                            meReady: true, opponentReady: false),
            name: "14-result-noshow")))
        shots.append(("15-result-void", try cdRender(
            cdFinishedStore(outcome: .draw, reason: .void, finalMe: 31, finalOpponent: 22, delta: 0, local: 31),
            name: "15-result-void")))

        let full = CGRect(origin: .zero, size: CrossyDuelWindowLayout.contentSize)
        for (name, bitmap) in shots {
            #expect(bitmap.pixelsWide == Int(CrossyDuelWindowLayout.contentSize.width * 2)
                    && bitmap.pixelsHigh == Int(CrossyDuelWindowLayout.contentSize.height * 2), "\(name) 크기")
            #expect(cdInk(bitmap, near: (255, 204, 0), tolerance: 12, in: full).count == 0,
                    "\(name): 노란 상자(TextField·Picker 자리)가 섞였다")
            #expect(cdBright(bitmap, in: full) > 200, "\(name): 글자 잉크가 거의 없다 — 빈 그림")
        }
    }

    // MARK: 트랙

    @Test("트랙 위 두 얼굴 점 중심 x 비(트랙 시작 기준) = 점수 비 4:7 — 기준선 70:40 은 7:4 로 갈린다")
    func faceDotsStandAtScoreRatio() throws {
        // 없으면: 두 점이 점수와 다른 자리(고정 · 뒤바뀜 · 상대 점이 내 점수를 따라감)에 서도 초록이다.
        let band = CrossyDuelWindowLayout.raceBandRect
        let start = band.minX + CrossyDuelRaceTrackLayout.trackStartX
        func ratio(my: Int, opponent: Int) throws -> CGFloat {
            let bitmap = try cdRender(cdPlayingStore(game: cdGame(score: my), opponentScore: opponent), threeD: false)
            let mine = try #require(cdDotCenter(bitmap, color: cdBlue, bandLeft: band.minX, bandTop: band.minY), "내 점 못 찾음")
            let theirs = try #require(cdDotCenter(bitmap, color: cdOrange, bandLeft: band.minX, bandTop: band.minY),
                                      "상대 점 못 찾음")
            return (mine - start) / (theirs - start)
        }
        let shown = try ratio(my: 40, opponent: 70)
        #expect(abs(shown - 40.0 / 70.0) < 0.03, "40:70 의 점 비가 \(shown) — 4:7(0.571) 이어야 한다")
        let baseline = try ratio(my: 70, opponent: 40)
        #expect(abs(baseline - 70.0 / 40.0) < 0.08, "기준선 70:40 의 점 비가 \(baseline)")
        #expect(abs(shown - baseline) > 1, "두 입력의 그림이 갈리지 않는다 — 단언이 아무것도 안 잰다")
    }

    @Test("겹침 40:41 이면 상대 점이 위 — 기준선 41:40 은 내 점이 위 · 같으면 내가 위")
    func higherScoreDotIsOnTop() throws {
        // 없으면: 겹칠 때 낮은 점수가 위에 그려져(그리는 순서 고정) 누가 앞인지 흐려진다.
        let band = CrossyDuelWindowLayout.raceBandRect
        let rect = cdTrackScanRect(bandLeft: band.minX, bandTop: band.minY)
        func inks(my: Int, opponent: Int) throws -> (blue: Int, orange: Int) {
            let bitmap = try cdRender(cdPlayingStore(game: cdGame(score: my), opponentScore: opponent), threeD: false)
            return (cdInk(bitmap, near: cdBlue, in: rect).count, cdInk(bitmap, near: cdOrange, in: rect).count)
        }
        let overlap = try inks(my: 40, opponent: 41)
        #expect(overlap.orange > overlap.blue * 3 / 2, "40:41 에서 상대(주황) 점이 위가 아니다 — 파랑 \(overlap.blue) · 주황 \(overlap.orange)")
        let baseline = try inks(my: 41, opponent: 40)
        #expect(baseline.blue > baseline.orange * 3 / 2, "기준선 41:40 에서 내(파랑) 점이 위가 아니다 — 파랑 \(baseline.blue) · 주황 \(baseline.orange)")
        #expect(!CrossyDuelRaceTrackLayout.opponentOnTop(myScore: 40, opponentScore: 40), "같으면 내가 위")
        #expect(CrossyDuelRaceTrackLayout.opponentOnTop(myScore: 40, opponentScore: 41))
    }

    @Test("내 점은 로컬 엔진 값 — 로컬 40 · 서버 me 38 이면 40 자리(기준선 38 자리와 7pt 넘게 갈린다)")
    func myDotFollowsTheLocalEngine() throws {
        // 없으면: 내 점이 서버 me(늦게 오는 값)를 따라가 내가 뛴 칸이 2~5초 늦게 트랙에 선다(CC-25).
        let band = CrossyDuelWindowLayout.raceBandRect
        let bitmap = try cdRender(cdPlayingStore(game: cdGame(score: 40), myServer: 38, opponentScore: 70), threeD: false)
        let mine = try #require(cdDotCenter(bitmap, color: cdBlue, bandLeft: band.minX, bandTop: band.minY))
        let at40 = band.minX + CrossyDuelRaceTrackLayout.centerX(score: 40, goal: 100, bandWidth: band.width)
        let at38 = band.minX + CrossyDuelRaceTrackLayout.centerX(score: 38, goal: 100, bandWidth: band.width)
        #expect(at40 - at38 > 7, "전제: 두 기준 자리가 갈려야 단언이 뜻이 있다(\(at40 - at38)pt)")
        #expect(abs(mine - at40) < 1.5, "내 점이 \(mine) — 로컬 40 자리 \(at40) 가 아니다(서버 38 자리 \(at38))")
    }

    @Test("상대 얼굴은 착용 캐릭터로 — 이니셜(캐릭터 없음)과 갈린다 · 같은 입력 두 장은 같다")
    func opponentFaceIsTheCharacterNotInitials() throws {
        // 없으면: 띠의 남의 얼굴이 이니셜로 떨어진다(characterHint 를 안 넘기거나 표 짝이 빠짐, CC-7).
        let withCharacter = try cdBand(my: 20, opponent: 70)
        let again = try cdBand(my: 20, opponent: 70)
        let initials = try cdBand(my: 20, opponent: 70, opponentUser: cdUser("민수", 11, character: nil))
        let x = CrossyDuelRaceTrackLayout.centerX(score: 70, goal: 100, bandWidth: CrossyDuelWindowLayout.innerWidth)
        let face = CGRect(x: (x - 12) * 2, y: (22 - 12) * 2, width: 48, height: 48)
        let a = try #require(withCharacter.cropping(to: face))
        let b = try #require(again.cropping(to: face))
        let c = try #require(initials.cropping(to: face))
        let same = try #require(CheckRenderDiff(a, b))
        let differ = try #require(CheckRenderDiff(a, c))
        #expect(same.looksSame, "같은 입력 두 장이 갈렸다: \(same)")
        #expect(differ.looksDifferent, "캐릭터 얼굴과 이니셜이 같은 그림이다 — 착용 캐릭터를 안 그린다: \(differ)")
    }

    // MARK: 겹 · 결과

    @Test("겹 우선순위: 결과 > 판정 기다림 > 부활 > 카운트다운 — '얼림 + .over' 에 부활 숫자 없음")
    func overlayPriority() {
        // 없으면: 3분 얼림·100 기다림이 엔진 `.over` 남은 값과 겹쳐 부활 "2" 가 판정 카드와 같이 뜬다(CC-20).
        let over = CrossyDuelRaceSnapshot(myScore: 40, opponentScore: 50, goal: 100, myDeaths: 2, opponentDeaths: 1,
                                          remaining: 30, respawnIn: 1.6)
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: over)
                == .respawn("2"), "기준선: 얼지 않은 판의 .over 는 부활 숫자")
        var frozen = over
        frozen.frozen = true
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: frozen)
                == .waiting(goal: false), "얼었는데 부활 숫자가 뜬다")
        var timeUp = over
        timeUp.remaining = 0
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: timeUp)
                == .waiting(goal: false), "3분이 끝났는데 부활 숫자가 뜬다")
        var goal = over
        goal.myScore = 100
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: goal)
                == .waiting(goal: true))
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .finished, isFinished: true, outcome: .win, snapshot: goal)
                == .result(.win))
        let counting = CrossyDuelRaceSnapshot(myScore: 0, opponentScore: 0, goal: 100, myDeaths: 0, opponentDeaths: 0,
                                              countdown: 2.2, remaining: 180)
        #expect(CrossyDuelCanvasOverlay.resolve(phase: .countdown, isFinished: false, outcome: nil, snapshot: counting)
                == .countdown("3"))
    }

    @Test("부활 겹은 큰 숫자 3 — 같은 판에서 3분이 끝나면(얼림) 숫자 대신 판정 카드")
    func respawnDigitRendersAndYieldsToWaiting() throws {
        // 없으면: 부활 숫자가 그림에 안 나오거나, 얼림과 같이 그려진다(위 순수 규칙을 뷰가 안 쓰는 경우).
        let canvas = CrossyDuelWindowLayout.canvasRect
        let digitBox = CGRect(x: canvas.midX - 30, y: canvas.midY - 60, width: 60, height: 70)
        let respawn = try cdRender(cdPlayingStore(game: cdRespawnGame(score: 40), opponentScore: 52), threeD: false)
        let frozen = try cdRender(cdPlayingStore(game: cdRespawnGame(score: 40), opponentScore: 52, elapsed: 181), threeD: false)
        let digitInk = cdBright(respawn, in: digitBox)
        let frozenInk = cdBright(frozen, in: digitBox)
        #expect(digitInk > 400, "부활 숫자 잉크가 \(digitInk) — 큰 숫자가 안 그려졌다")
        #expect(frozenInk < digitInk / 3, "얼었는데 부활 숫자 자리에 잉크가 남았다(\(frozenInk) vs \(digitInk))")
    }

    @Test("결과 카드 '나' 숫자 — Q3 (가): goal 로 진 판만 max(final, 로컬) · 그 밖은 final")
    func resultMyScoreFollowsQ3() {
        // 없으면: 상대 goal 로 진 판에서 '나 95'(서버가 마지막 보고까지만 안 값)가 떠 내가 본 97 과 어긋난다 — 또는 그 규칙이
        //        다른 사유에도 번져 기록과 다른 숫자가 뜬다(CC-4).
        #expect(CrossyDuelText.resultMyScore(finalMe: 95, local: 97, reason: .goal, outcome: .loss) == 97)
        #expect(CrossyDuelText.resultMyScore(finalMe: 95, local: 97, reason: .timeCap, outcome: .loss) == 95, "기준선: 3분 끝 패")
        #expect(CrossyDuelText.resultMyScore(finalMe: 100, local: 100, reason: .goal, outcome: .win) == 100)
        #expect(CrossyDuelText.resultMyScore(finalMe: 95, local: 90, reason: .goal, outcome: .loss) == 95, "로컬이 작으면 final")
        #expect(CrossyDuelText.resultMyScore(finalMe: 95, local: nil, reason: .goal, outcome: .loss) == 95)
    }

    @Test("결과 사유 · 루비 줄 문구 — no_show 셋 · void · 무승부 루비 줄")
    func resultCopy() {
        // 없으면: no_show 가 누가 준비 안 했는지 못 가르거나(CC-12), void 가 빈 줄로 나간다(CS-2).
        #expect(CrossyDuelNoticeText.endReason(.noShow, outcome: .draw, meReady: true, opponentReady: false)
                == "상대가 준비하지 않아 판돈을 돌려받았어요")
        #expect(CrossyDuelNoticeText.endReason(.noShow, outcome: .draw, meReady: false, opponentReady: true)
                == "준비하지 않아 판이 열리지 않았어요 · 판돈은 돌려받았어요")
        #expect(CrossyDuelNoticeText.endReason(.void, outcome: .draw) == "판이 무효가 되어 판돈을 돌려받았어요")
        #expect(CrossyDuelText.rubyLine(5) == "+5")
        #expect(CrossyDuelText.rubyLine(-5) == "−5")
        #expect(CrossyDuelText.rubyLine(0) == "0 · 판돈을 돌려받았어요")
        #expect(CrossyDuelText.finalScoreLine(me: 100, opponent: 87) == "나 100 : 상대 87")
        #expect(CrossyDuelText.clock(161) == "2:41")
        #expect(CrossyDuelText.clock(0) == "0:00")
        #expect(!CrossyDuelResultCard.showsScores(cdMatch(finished: true, reason: .noShow)))
        #expect(CrossyDuelResultCard.showsScores(cdMatch(finished: true, reason: .void)))
    }
}
