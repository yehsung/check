import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.65 맥 **테트리스 관전 화면**(신규). 두 사람 판을 나란히 · 입력 0건 · 승자를 지어내지 않는다.
//
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다. **모양이 아니라 결과를 잰다** —
// 부품을 불렀는지가 아니라 "그 자리에 판이 그려졌는가 / 두 판이 서로 다른가 / 글자가 무엇을 말하는가" 다.
// ★ 픽셀 색은 재지 않는다.

// MARK: - 픽스처

private let twwFrozen = Date(timeIntervalSince1970: 2_000_000_000)
private let twwMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

private func twwUser(_ name: String, _ suffix: Int) -> TetrisDuelUser {
    TetrisDuelUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
                   avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true,
                   inMatch: true, isFocused: false)
}

private let twwA = twwUser("가나다", 30)
private let twwB = twwUser("라마바", 60)

/// 아래쪽이 찬 판(20행 × 10칸 글자판). 두 자리에 **다른** 판을 주어야 "한 판을 두 번 그렸다" 를 잡는다.
private let twwBoardLeft: String = (Array(repeating: "..........", count: 15) + [
    "....T.....", "...TTT....", "Z.......OO", "ZZ..SS..JJ", "GGGGG.GGGG",
]).joined()
private let twwBoardRight: String = (Array(repeating: "..........", count: 17) + [
    "IIII......", "L..JJJ....", "GGGG.GGGGG",
]).joined()

private func twwSide(_ user: TetrisDuelUser, board: String?, lines: Int = 4, pending: Int = 2,
                     attack: Int = 3, toppedOut: Bool = false) -> TetrisSpectateSide {
    let cells = board.flatMap(TetrisDuelBoard.decode)
    return TetrisSpectateSide(user: user, board: cells == nil ? nil : board, cells: cells,
                              lines: lines, pending: pending, attackSent: attack, toppedOut: toppedOut,
                              lastSeenAt: twwFrozen)
}

/// 관전 상태 한 벌. `winner` 는 **서버가 실어 주는 이긴 사람 uuid**(`match.winner`)다 — nil 이면 모르는 것이고,
/// 화면은 그때 승자를 말하지 않아야 한다. `result` 로 승자를 만들어 넣지 않는다(그게 P1 인 자리다).
private func twwWatch(
    a: TetrisSpectateSide = twwSide(twwA, board: twwBoardLeft),
    b: TetrisSpectateSide = twwSide(twwB, board: twwBoardRight, lines: 1, pending: 0, attack: 0),
    finished: Bool = false, result: String? = nil, winner: String? = nil,
    reason: TetrisDuelEndReason? = nil, hasServerState: Bool = true
) -> TetrisSpectateState {
    var watch = TetrisSpectateState(id: "live-0", faces: [twwA, twwB], stake: 5)
    watch.a = a
    watch.b = b
    watch.startedAt = twwFrozen
    watch.isFinished = finished
    watch.result = finished ? result : nil
    watch.winnerUserID = finished ? winner : nil
    watch.endReason = finished ? reason : nil
    watch.finishedAt = finished ? twwFrozen : nil
    watch.hasServerState = hasServerState
    return watch
}

@MainActor
private func twwStore(
    a: TetrisSpectateSide = twwSide(twwA, board: twwBoardLeft),
    b: TetrisSpectateSide = twwSide(twwB, board: twwBoardRight, lines: 1, pending: 0, attack: 0),
    finished: Bool = false, result: String? = nil, winner: String? = nil,
    reason: TetrisDuelEndReason? = nil,
    watchers: Int = 0, hasServerState: Bool = true, notice: String? = nil
) -> TetrisDuelStore {
    let store = twwBareStore()
    store.spectating = twwWatch(a: a, b: b, finished: finished, result: result, winner: winner,
                                reason: reason, hasServerState: hasServerState)
    store.spectatorCount = watchers
    store.notice = notice
    return store
}

/// 관전도 내 판도 안 세운 로비 스토어(두 상태를 손으로 세우는 시험이 이걸 쓴다).
@MainActor
private func twwBareStore() -> TetrisDuelStore {
    let store = TetrisDuelStore()
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    store.clock = { twwFrozen }
    store.hasLoadedLobby = true
    store.rankingEnabled = true
    store.spectatorFeaturesEnabled = true
    store.rubyBalance = 42
    store.record = TetrisDuelRecord(wins: 7, losses: 3, draws: 1)
    return store
}

/// 내 판 하나(진행 중). `match` 대입은 didSet 으로 관전을 내린다 — 둘을 동시에 세우려면 **이 뒤에** 관전을 적는다.
@MainActor
private func twwMatch() -> TetrisDuelMatchState {
    TetrisDuelMatchState(
        id: "7e7e0000-0000-4000-8000-000000000060", stake: 5, seed: 7, opponent: twwA,
        acceptedAt: twwFrozen, readyDeadline: twwFrozen.addingTimeInterval(24), startAt: nil, maxEnd: nil,
        meReady: true, opponentBoard: TetrisDuelOpponentBoard.empty, isFinished: false,
        outcome: nil, endReason: nil, rubyDelta: nil, finishedAt: nil)
}

@MainActor
private func twwPanel(_ store: TetrisDuelStore) -> some View {
    TetrisDuelPanel(store: store, me: { twwMe }, clipsOverflowInsteadOfScroll: true)
}

private enum TWWError: Error { case render }

@MainActor
private func twwBitmap(_ store: TetrisDuelStore) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: twwPanel(store).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw TWWError.render }
    return bitmap
}

private func twwDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect, threshold: Int = 24) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return -1 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return -1 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if (0..<min(3, spp)).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > threshold }) { count += 1 }
        }
    }
    return count
}

/// `rect` 안에서 거의 검지 않은(= 무언가 그려진) 픽셀 수. 관전 판 바닥은 거의 검다(`miniWellRGB`).
private func twwLit(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return -1 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2]) > 220 { count += 1 }
        }
    }
    return count
}

/// `rect` 안에서 **잉크 여부**가 다른 픽셀 수. 잉크 기준은 `twwLit` 과 같다(밝은 픽셀 = 글자·그림).
/// 색은 통째로 무시하므로 이 값은 **글자 모양**만 잰다 — 캡션을 평소 글자로 되돌리면서 **초록만 남긴** 변형
/// (`captionTint` 는 그대로 두고 `caption` 의 `didWin` 분기만 지우는 것)이 색 차이로 통과하는 것을 막는다.
private func twwShapeDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          lhs.samplesPerPixel >= 3 else { return -1 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return -1 }
    func lit(_ data: UnsafePointer<UInt8>, _ offset: Int) -> Bool {
        Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2]) > 220
    }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if lit(a, o) != lit(b, o) { count += 1 }
        }
    }
    return count
}

// MARK: - 자리 (레이아웃 상수에서만)

private typealias TWL = TetrisDuelWindowLayout

private var twwBodyTop: CGFloat { TWL.contentPadding + TWL.headerHeight + TWL.headerSpacing }

private func twwSideColumn(_ index: Int) -> CGRect {
    CGRect(x: TWL.contentPadding + CGFloat(index) * (TWL.spectateSideWidth + TWL.columnSpacing),
           y: twwBodyTop, width: TWL.spectateSideWidth, height: TWL.bodyHeight)
}

private var twwInfoColumn: CGRect {
    CGRect(x: TWL.contentPadding + (TWL.spectateSideWidth + TWL.columnSpacing) * 2, y: twwBodyTop,
           width: TWL.spectateInfoWidth, height: TWL.bodyHeight)
}

/// 판 하나의 자리 — **판 카드가 열 맨 위**다(이름 카드는 아래로 내려갔다). 카드 여백(12) 아래, 가로 가운데.
private func twwBoardRect(_ index: Int) -> CGRect {
    let column = twwSideColumn(index)
    let size = TWL.spectateBoardSize
    return CGRect(x: column.minX + (column.width - size.width) / 2,
                  y: column.minY + TWL.spectateCardPadding,
                  width: size.width, height: size.height)
}

/// 이름 카드 자리 — 열의 **맨 아래** 52pt. 명세 §4: 판이 먼저, 이름·숫자가 아래다.
private func twwNameCardRect(_ index: Int) -> CGRect {
    let column = twwSideColumn(index)
    return CGRect(x: column.minX, y: column.maxY - TWL.playerCardHeight,
                  width: column.width, height: TWL.playerCardHeight)
}

/// 열의 **맨 위** 52pt(= 이름 카드가 예전에 있던 자리). 지금은 판 카드의 윗부분이다.
private func twwColumnTopStrip(_ index: Int) -> CGRect {
    let column = twwSideColumn(index)
    return CGRect(x: column.minX, y: column.minY, width: column.width, height: TWL.playerCardHeight)
}

// MARK: - ① 세로 예산 (상수 항등식 — 깨지면 판이 카드를 뚫는다)

/// 없으면: 셀을 16 으로 올려 판이 카드를 8pt 뚫고 나가도, 열 폭 합이 창을 넘어가도 컴파일은 조용하다.
@Test
func v0364TetrisWatchLayoutFitsItsBudget() {
    let inner = TWL.spectateBoardCardHeight - TWL.spectateCardPadding * 2
    let need = TWL.spectateBoardSize.height + TWL.spectateBoardGap + TWL.spectateStatsHeight
    print("[관전 세로] 카드 안쪽 \(inner) · 필요 \(need)(판 \(TWL.spectateBoardSize.height))")
    #expect(need <= inner, "판 + 숫자가 카드 안쪽(\(inner))을 \(need - inner)pt 넘친다")
    // 가로: 두 열 + 오른쪽 열 + 간격 둘 = 본문 폭(상수 하나만 바꿔도 여기가 먼저 빨개진다).
    #expect(TWL.spectateSideWidth * 2 + TWL.spectateInfoWidth + TWL.columnSpacing * 2 == TWL.innerWidth)
    #expect(TWL.spectateInfoWidth > 0, "오른쪽 열 폭이 \(TWL.spectateInfoWidth) 다")
    // 판이 열 안에 든다(여백 포함).
    #expect(TWL.spectateBoardSize.width + TWL.spectateCardPadding * 2 <= TWL.spectateSideWidth)
    // 차례를 뒤집어도 합은 같다 — 이름 카드가 아래로 내려간다고 창이 자라면 안 된다.
    #expect(TWL.playerCardHeight + TWL.playerCardSpacing + TWL.spectateBoardCardHeight == TWL.bodyHeight)
}

/// 없으면: 이름 카드를 판 **위**에 두어도(명세 §4 위반) 초록이다 — 열은 같은 높이라 상수 항등식으로는 안 잡힌다.
/// 그래서 **이름만 갈아** 어느 띠의 픽셀이 달라지는지 잰다: 아래 띠가 달라지고 판·윗 띠는 한 톨도 안 달라져야 한다.
@MainActor
@Test
func v0364TetrisWatchPutsTheNameCardBelowTheBoard() throws {
    let base = try twwBitmap(twwStore())
    // 같은 사람(id 동일) · 다른 이름. 이름 카드 말고는 아무것도 안 달라진다.
    let renamed = twwUser("가나다라마바사아", 30)
    let shot = try twwBitmap(twwStore(a: twwSide(renamed, board: twwBoardLeft)))

    let bottom = twwDiff(base, shot, rect: twwNameCardRect(0))
    let top = twwDiff(base, shot, rect: twwColumnTopStrip(0))
    let board = twwDiff(base, shot, rect: twwBoardRect(0))
    print("[이름 카드 자리] 아래 띠 \(bottom)px · 윗 띠 \(top)px · 판 \(board)px")
    #expect(bottom > 100, "이름을 갈았는데 열 **아래** 띠가 \(bottom)px 밖에 안 달라졌다 — 이름 카드가 아래에 없다")
    #expect(top == 0, "이름을 갈았는데 열 **맨 위**가 \(top)px 달라졌다 — 이름 카드가 아직 판 위에 있다")
    #expect(board == 0, "이름을 갈았는데 판이 흔들린다")
    // 판은 윗 띠 안에 실제로 그려져 있다(위가 비어 있어서 0 인 것이 아니다).
    #expect(twwLit(base, rect: twwColumnTopStrip(0)) > 100, "열 맨 위가 비어 있다 — 판이 거기 없다")
    #expect(twwLit(base, rect: twwNameCardRect(0)) > 100, "열 맨 아래가 비어 있다 — 이름 카드가 거기 없다")
    // 창은 한 톨도 안 자랐다(두 그림 모두 고정 크기 그대로).
    #expect(base.pixelsWide == Int(TWL.contentSize.width * 2) && base.pixelsHigh == Int(TWL.contentSize.height * 2),
            "창 크기가 \(base.pixelsWide)×\(base.pixelsHigh) 로 달라졌다")
}

// MARK: - ② 두 판을 **나란히** 그린다

/// 없으면: 한 자리만 그려도, 두 자리에 **같은 판**을 그려도(a 를 두 번 넘김) 초록이다 —
/// 관전자는 두 사람이 같은 판을 두는 것처럼 보게 된다.
@MainActor
@Test
func v0364TetrisWatchDrawsBothBoardsSideBySide() throws {
    let both = try twwBitmap(twwStore())
    let leftLit = twwLit(both, rect: twwBoardRect(0))
    let rightLit = twwLit(both, rect: twwBoardRect(1))
    print("[관전 판] 왼쪽 \(leftLit)px · 오른쪽 \(rightLit)px")
    #expect(leftLit > 400, "왼쪽 판이 비어 있다(\(leftLit)px)")
    #expect(rightLit > 400, "오른쪽 판이 비어 있다(\(rightLit)px)")

    // ★ 두 자리는 **서로 다른 판**이다: 한쪽 판만 갈면 그 자리만 바뀐다(둘이 한 값을 보면 둘 다 바뀐다).
    let leftChanged = try twwBitmap(twwStore(a: twwSide(twwA, board: twwBoardRight)))
    #expect(twwDiff(both, leftChanged, rect: twwBoardRect(0)) > 200, "왼쪽 판을 갈았는데 왼쪽이 안 바뀐다")
    #expect(twwDiff(both, leftChanged, rect: twwBoardRect(1)) == 0,
            "왼쪽 판을 갈았는데 **오른쪽**도 바뀐다 — 두 자리가 같은 값을 그린다")
    let rightChanged = try twwBitmap(twwStore(b: twwSide(twwB, board: twwBoardLeft, lines: 1, pending: 0, attack: 0)))
    #expect(twwDiff(both, rightChanged, rect: twwBoardRect(1)) > 200, "오른쪽 판을 갈았는데 오른쪽이 안 바뀐다")
    #expect(twwDiff(both, rightChanged, rect: twwBoardRect(0)) == 0, "오른쪽을 갈았는데 왼쪽도 바뀐다")
}

/// 없으면: 보고가 아직 없는 자리(board nil)·글자가 망가진 자리에서 화면이 서거나, 멀쩡한 반대쪽까지
/// 같이 사라져도 초록이다(스토어는 그 자리만 접는다 — 화면도 그래야 한다).
@MainActor
@Test
func v0364TetrisWatchSurvivesAMissingBoardAndKeepsTheOtherSide() throws {
    let healthy = try twwBitmap(twwStore())
    let missing = try twwBitmap(twwStore(a: twwSide(twwA, board: nil)))
    // 반대쪽 판은 **한 픽셀도** 안 달라진다.
    #expect(twwDiff(healthy, missing, rect: twwBoardRect(1)) == 0, "한쪽 판이 없으면 반대쪽까지 흔들린다")
    #expect(twwLit(missing, rect: twwBoardRect(1)) > 400, "반대쪽 판이 같이 사라졌다")
    // 빈 자리는 **빈 우물 + 안내 한 줄**이다(화면이 서지 않는다).
    let emptyLit = twwLit(missing, rect: twwBoardRect(0))
    print("[판 없음] 빈 자리 \(emptyLit)px · 정상 \(twwLit(healthy, rect: twwBoardRect(0)))px")
    #expect(emptyLit > 0, "빈 자리에 안내 한 줄도 없다")
    #expect(emptyLit < twwLit(healthy, rect: twwBoardRect(0)), "판이 없는데 조각이 그대로 그려진다")

    // 글자 집합이 어긋난 판(200글자인데 'X')도 같은 길이다 — 스토어가 nil 로 접고 화면은 선다.
    let alien = String(repeating: ".", count: 199) + "X"
    #expect(TetrisDuelBoard.decode(alien) == nil, "전제: 망가진 글자판은 디코드가 nil 이다")
    let alienShot = try twwBitmap(twwStore(a: twwSide(twwA, board: alien)))
    #expect(twwLit(alienShot, rect: twwBoardRect(1)) > 400, "망가진 판 하나가 반대쪽을 죽였다")
}

/// 없으면: 탑아웃한 쪽을 흐리게 하지 않아도, 반대로 **두 쪽 다** 흐려져도 초록이다.
@MainActor
@Test
func v0364TetrisWatchDimsOnlyTheToppedOutSide() throws {
    let normal = try twwBitmap(twwStore())
    let dimmed = try twwBitmap(twwStore(a: twwSide(twwA, board: twwBoardLeft, toppedOut: true)))
    let leftChanged = twwDiff(normal, dimmed, rect: twwSideColumn(0))
    let rightChanged = twwDiff(normal, dimmed, rect: twwSideColumn(1))
    print("[탑아웃] 왼쪽 \(leftChanged)px · 오른쪽 \(rightChanged)px")
    #expect(leftChanged > 500, "탑아웃한 쪽이 그대로다(\(leftChanged)px)")
    #expect(rightChanged == 0, "탑아웃하지 않은 쪽까지 흐려진다(\(rightChanged)px)")
    // 흐려졌다 = 그 자리의 밝은 픽셀이 **줄었다**(색이 아니라 밝기로 잰다).
    #expect(twwLit(dimmed, rect: twwBoardRect(0)) < twwLit(normal, rect: twwBoardRect(0)),
            "탑아웃한 판이 더 밝거나 같다")
}

// MARK: - ③ 승자는 서버가 말해 줄 때만 말한다

/// 없으면: 서버가 이긴 사람 uuid(`match.winner`)를 실어 줘도 관전 화면이 "대결이 끝났어요" 만 말한다 —
/// 끝까지 본 사람이 **누가 이겼는지 모른 채** 나간다.
@Test
func v0364TetrisWatchNamesTheWinnerFromTheWinnerUserID() {
    let aWins = twwWatch(finished: true, result: "challenger_win", winner: twwA.id, reason: .topout)
    let bWins = twwWatch(finished: true, result: "challenger_win", winner: twwB.id, reason: .topout)
    #expect(aWins.aWon && !aWins.bWon, "전제: a 자리가 이겼다")
    #expect(bWins.bWon && !bWins.aWon, "전제: b 자리가 이겼다")

    let aLine = TetrisWatchStatusText.headline(aWins)
    let bLine = TetrisWatchStatusText.headline(bWins)
    print("[승자] a \(aLine) · b \(bLine)")
    #expect(aLine.contains(twwA.displayName), "a 가 이겼는데 이름을 안 말한다: \(aLine)")
    #expect(!aLine.contains(twwB.displayName), "a 가 이겼는데 b 를 말한다: \(aLine)")
    #expect(bLine.contains(twwB.displayName), "b 가 이겼는데 이름을 안 말한다: \(bLine)")
    #expect(!bLine.contains(twwA.displayName), "b 가 이겼는데 a 를 말한다: \(bLine)")
    // ★ 기준선 갈림: **같은 `result`** 인데 두 글자가 다르다 = 승자는 `result` 가 아니라 uuid 에서 나왔다.
    #expect(aLine != bLine, "두 승자가 같은 글자다 — 승자를 안 읽고 있다")
    #expect(aLine != TetrisDuelText.watchEnded && bLine != TetrisDuelText.watchEnded)

    // ★ **1인칭 금지.** 관전자에게 "이겼어요/졌어요" 는 누구 얘긴지 뜻이 없다(오목이 데인 자리).
    for line in [aLine, bLine] {
        #expect(!line.contains("이겼어요") && !line.contains("졌어요"), "승자 문장이 1인칭이다: \(line)")
        #expect(line != TetrisDuelText.outcomeTitle(.won) && line != TetrisDuelText.outcomeTitle(.lost))
    }

    // 모르는 uuid(두 자리 중 누구도 아님) → 승자를 말하지 않는다.
    let stranger = twwWatch(finished: true, result: "opponent_win",
                            winner: "00000000-0000-0000-0000-000000000999", reason: .topout)
    #expect(!stranger.aWon && !stranger.bWon, "전제: 모르는 uuid 는 두 자리 다 거짓이다")
    #expect(TetrisWatchStatusText.headline(stranger) == TetrisDuelText.watchEnded,
            "모르는 uuid 로 승자를 지목한다: \(TetrisWatchStatusText.headline(stranger))")

    // 이름을 아직 못 받은 자리(서버 행이 오기 전) → 빈 이름으로 "  승리" 를 적지 않는다.
    var nameless = TetrisSpectateSide.empty
    nameless.user = TetrisDuelUser(id: twwA.id, displayName: "   ", avatarURL: nil, characterID: nil,
                                   isWorking: false, isCapable: true, inMatch: true, isFocused: false)
    let blank = twwWatch(a: nameless, finished: true, winner: twwA.id, reason: .topout)
    #expect(blank.aWon, "전제: uuid 는 맞다")
    #expect(TetrisWatchStatusText.headline(blank) == TetrisDuelText.watchEnded,
            "이름이 비었는데 승자 줄을 적는다: \(TetrisWatchStatusText.headline(blank))")

    // 진행 중에는 승자 칸이 있어도 말하지 않는다(서버가 닫기 전에는 결과가 아니다).
    var live = twwWatch()
    live.winnerUserID = twwA.id
    #expect(TetrisWatchStatusText.headline(live) == TetrisDuelText.watching,
            "진행 중인데 승자를 말한다: \(TetrisWatchStatusText.headline(live))")
}

/// 없으면: `result` 로 승자를 역산하는 코드를 넣어도 초록이다 — 관전 봉투에는 challenger 표시가 없어
/// 'challenger_win' 이 **어느 자리**인지 알 수 없다(둘일 때 맞는 식이 셋째 경우에 거짓말한다).
@Test
func v0364TetrisWatchNeverNamesAWinnerFromResultAlone() {
    // ★ 전제: `winnerUserID` 는 **nil** 이다(승자 칸을 모르는 옛 서버). 그 창에서도 `result` 만으로
    //    한쪽을 지목하면 안 된다 — 'challenger_win' 이 a 인지 b 인지는 관전 봉투에 없다.
    var base = TetrisSpectateState(id: "m", faces: [twwA, twwB], stake: 5)
    base.hasServerState = true
    base.a = twwSide(twwA, board: twwBoardLeft)
    base.b = twwSide(twwB, board: twwBoardRight)

    var live = base
    var challengerWin = base, opponentWin = base, draw = base
    challengerWin.isFinished = true
    challengerWin.result = "challenger_win"
    challengerWin.endReason = .topout
    opponentWin.isFinished = true
    opponentWin.result = "opponent_win"
    opponentWin.endReason = .topout
    draw.isFinished = true
    draw.result = "draw"
    draw.endReason = .timeCap
    live.isFinished = false

    // ★ 계약: 두 승리 글자는 **같다**(누가 이겼는지 모르므로 말하지 않는다).
    #expect(TetrisWatchStatusText.headline(challengerWin) == TetrisWatchStatusText.headline(opponentWin),
            "승자를 역산하고 있다: \(TetrisWatchStatusText.headline(challengerWin)) vs \(TetrisWatchStatusText.headline(opponentWin))")
    // ★ 기준선 갈림: 그래도 **무승부는 다르고 진행 중도 다르다**(같으면 위 단언이 영원히 초록이다).
    #expect(TetrisWatchStatusText.headline(draw) != TetrisWatchStatusText.headline(challengerWin))
    #expect(TetrisWatchStatusText.headline(live) != TetrisWatchStatusText.headline(challengerWin))
    #expect(TetrisWatchStatusText.headline(draw) == TetrisDuelText.watchDraw)
    #expect(TetrisWatchStatusText.headline(live) == TetrisDuelText.watching)
    // 사람 이름이 승패 문장에 끼지 않는다.
    for state in [challengerWin, opponentWin, draw] {
        let line = TetrisWatchStatusText.headline(state) + TetrisWatchStatusText.detail(state, notice: nil)
        #expect(!line.contains(twwA.displayName) && !line.contains(twwB.displayName), "결과 문장이 이름을 말한다: \(line)")
    }
    // 첫 응답 전에는 "불러오고 있어요" 다(진행 중과도 갈린다).
    var loading = base
    loading.hasServerState = false
    #expect(TetrisWatchStatusText.headline(loading) == TetrisDuelText.watchLoading)
    #expect(TetrisWatchStatusText.headline(loading) != TetrisWatchStatusText.headline(live))
}

/// 없으면: 관전 절 어딘가에 `result == "challenger_win"` 분기를 새로 적어도, 그 분기가 지금은 두 자리를
/// 같게 그려서 그림 시험을 통과하는 동안 초록이다(다음 사람이 거기에 이름을 붙이면 P1 이 된다).
@Test
func v0364TetrisWatchSourceNeverMentionsChallengerResultStrings() throws {
    let source = v0364StripComments(
        try String(contentsOf: v0364RepoURL("Sources/check/TetrisDuelPanel.swift"), encoding: .utf8))
    // ★ 끝 표시는 **주석이 아닌 줄**이어야 한다 — 이 저장소는 소스를 읽기 전에 주석을 걷는다(`// MARK:` 는 사라진다).
    let section = try #require(v0364Between(source, "enum TetrisWatchStatusText {",
                                            "private struct TetrisDuelStakePrompt: View {"),
                               "관전 절을 못 찾았다")
    for token in ["challenger_win", "opponent_win", "challenger", "isMine("] {
        #expect(!section.contains(token), "관전 절이 \(token) 를 읽는다 — 관전 봉투에 없는 것을 아는 척한다")
    }
    // 승자는 **자리 술어**로만 읽는다.
    #expect(section.contains(".aWon") && section.contains(".bWon"), "관전 절이 승자 술어를 안 쓴다")
    // 무승부 한 글자만 `result` 를 본다(그 값은 자리를 지목하지 않는다).
    #expect(section.components(separatedBy: "watch.result").count - 1 == 1,
            "관전 절이 `result` 를 한 번 넘게 읽는다")
}

/// 없으면: 관전 사유를 **1인칭**(`endReason(_, outcome:)`)으로 써도 초록이다 — 관전자가 패자의 문장
/// ("기권했어요")을 읽는다(체스가 2026-10-05 에 고친 그것).
@Test
func v0364TetrisWatchReasonIsThirdPersonAndNeverTheLoserVoice() {
    for reason in TetrisDuelEndReason.allCases {
        let third = TetrisWatchStatusText.reason(reason)
        #expect(!third.isEmpty, "\(reason) 의 관전 사유가 비어 있다")
        #expect(third != TetrisDuelNoticeText.endReason(reason, outcome: .lost),
                "\(reason) 의 관전 사유가 패자 1인칭 그대로다: \(third)")
        #expect(third != TetrisDuelNoticeText.endReason(reason, outcome: .won),
                "\(reason) 의 관전 사유가 승자 1인칭 그대로다: \(third)")
        // 관전 사유에 "내" 주어가 없다(1인칭 어휘 '상대' 는 내 기준일 때만 뜻이 있다).
        #expect(!third.contains("상대"), "\(reason): 관전 사유에 '상대' 가 있다 — 누구의 상대인가")
    }
    // ★ 기준선 갈림: 사유마다 다른 글자다(전부 같으면 위 단언이 아무것도 안 잰다).
    let all = Set(TetrisDuelEndReason.allCases.map(TetrisWatchStatusText.reason))
    #expect(all.count >= 5, "여섯 사유가 \(all.count)가지 글자뿐이다")
    #expect(TetrisWatchStatusText.reason(nil) == "", "모르는 사유를 지어낸다")
}

/// 없으면: 끝난 판의 `result` 가 그림을 가른다(= 승자를 역산한다)는 사실이 글자 시험만으로는 안 잡힌다 —
/// 화면 어딘가에서 역산하면 여기서 두 그림이 갈린다.
@MainActor
@Test
func v0364TetrisWatchFinishedScreenIsTheSameForEitherWinner() throws {
    let challenger = try twwBitmap(twwStore(finished: true, result: "challenger_win", reason: .topout))
    let opponent = try twwBitmap(twwStore(finished: true, result: "opponent_win", reason: .topout))
    let draw = try twwBitmap(twwStore(finished: true, result: "draw", reason: .timeCap))
    let whole = CGRect(x: 0, y: 0, width: TWL.contentSize.width, height: TWL.contentSize.height)
    let winnerDiff = twwDiff(challenger, opponent, rect: whole)
    let drawDiff = twwDiff(challenger, draw, rect: twwInfoColumn)
    print("[끝난 판] 승자 갈림 \(winnerDiff)px · 무승부 갈림 \(drawDiff)px")
    #expect(winnerDiff == 0, "challenger_win 과 opponent_win 의 그림이 \(winnerDiff)px 다르다 — 승자를 역산한다")
    // ★ 기준선 갈림: 무승부는 **다르게** 보인다(안 다르면 위 단언은 '아무것도 안 그린다' 로도 통과한다).
    #expect(drawDiff > 200, "무승부와 승부가 같은 화면이다(\(drawDiff)px)")

    // ★ 둘째 기준선: 서버가 **이긴 사람 uuid** 를 실으면 같은 `result` 인데도 그림이 갈린다.
    //   (안 갈리면 위 `winnerDiff == 0` 은 "끝난 판은 늘 똑같이 그린다" 로도 통과한다.)
    let aWon = try twwBitmap(twwStore(finished: true, result: "challenger_win", winner: twwA.id, reason: .topout))
    let bWon = try twwBitmap(twwStore(finished: true, result: "challenger_win", winner: twwB.id, reason: .topout))
    let named = twwDiff(aWon, bWon, rect: whole)
    print("[승자 uuid] a↔b 갈림 \(named)px · 승자 없음↔a \(twwDiff(challenger, aWon, rect: whole))px")
    #expect(named > 200, "이긴 사람 uuid 가 반대인데 화면이 \(named)px 밖에 안 다르다 — 승자를 안 그린다")
    #expect(twwDiff(challenger, aWon, rect: whole) > 200, "승자를 알려 줬는데 모를 때와 같은 화면이다")
    // 판 자리는 승자 표시에 흔들리지 않는다(글자만 갈린다).
    #expect(twwDiff(aWon, bWon, rect: twwBoardRect(0)) == 0, "승자가 갈리자 판 그림이 흔들린다")
    #expect(twwDiff(aWon, bWon, rect: twwBoardRect(1)) == 0, "승자가 갈리자 판 그림이 흔들린다")
}

/// 없으면: `TetrisDuelSpectateSide` 의 `if didWin { return TetrisDuelText.watchWinnerCaption }` **한 줄을 지워도**
/// 아무 시험도 안 문다 — 승자 **머리글**(오른쪽 열)은 글자 시험이 물지만 판 아래 **이름 카드 캡션**은 아무도
/// 안 물어, 승자 표시가 **절반만 소실된 채** 배포된다. 위의 그림 시험("a↔b 갈림 > 200")은 머리글 글자 변화
/// 하나로도 통과한다.
///
/// 사각형을 어떻게 잡았는가: `twwNameCardRect(0)` — **a 열의 맨 아래 52pt**(열 x·폭은 `spectateSideWidth` ·
/// `columnSpacing` · `contentPadding` 에서, 높이는 `playerCardHeight` 에서 끌어온다. 숫자를 손으로 박지 않는다).
/// 그 안에 든 것은 a 의 초상 · 이름 · 캡션 한 줄뿐이다 — 승자 머리글은 오른쪽 정보 열이라 **사각형 밖**이고,
/// 판 카드는 그 위라 섞이지 않는다. 같은 장면에서 **이긴 사람 uuid 한 칸만** 바꾸므로, a 카드가 갈리는 유일한
/// 까닭은 a 의 캡션이다.
@MainActor
@Test
func v0364TetrisWatchWinnerCaptionLandsOnTheWinnersOwnNameCard() throws {
    let noWinner = try twwBitmap(twwStore(finished: true, result: "challenger_win", reason: .topout))
    let aWon = try twwBitmap(twwStore(finished: true, result: "challenger_win", winner: twwA.id, reason: .topout))
    let bWon = try twwBitmap(twwStore(finished: true, result: "challenger_win", winner: twwB.id, reason: .topout))

    // a 카드: 한쪽은 "승리", 다른 쪽은 평소 캡션("대결 끝")이다.
    let aCard = twwNameCardRect(0), bCard = twwNameCardRect(1)
    let aDrawn = twwDiff(aWon, bWon, rect: aCard)
    let aShape = twwShapeDiff(aWon, bWon, rect: aCard)
    print("[승자 캡션] a 카드 색 \(aDrawn)px · 모양 \(aShape)px")
    #expect(aDrawn > 100, "이긴 사람이 반대인데 a 의 이름 카드가 \(aDrawn)px 밖에 안 다르다 — 캡션이 승리를 안 말한다")
    // ★ **색만** 갈리는 것으로는 안 된다: 캡션 글자 자체가 달라야 한다(색을 무시하고 모양만 재는 값).
    //   실측: 지금 480px · `caption` 의 `didWin` 줄만 지우고 `captionTint` 를 남기면 44px 로 떨어진다
    //   (색 갈림은 613px 로 남아 위 단언은 그대로 통과한다 — 이 줄이 그 변형을 잡는 유일한 자리다).
    #expect(aShape > 200, "a 카드의 캡션 **모양**이 \(aShape)px 밖에 안 다르다 — 글자는 그대로고 색만 바뀌었다")

    // b 카드도 **거울처럼** 갈린다(한쪽에만 캡션을 달아도 반쪽 소실이다).
    let bDrawn = twwDiff(aWon, bWon, rect: bCard)
    let bShape = twwShapeDiff(aWon, bWon, rect: bCard)
    print("[승자 캡션] b 카드 색 \(bDrawn)px · 모양 \(bShape)px")
    #expect(bDrawn > 100, "b 의 이름 카드가 \(bDrawn)px 밖에 안 다르다")
    #expect(bShape > 200, "b 카드의 캡션 모양이 \(bShape)px 밖에 안 다르다")

    // ★ 기준선 갈림(정확히 **이긴 자리만** 바뀐다): 승자를 모를 때와 견주면 **이긴 쪽 카드만** 달라지고
    //   진 쪽 카드는 한 픽셀도 안 달라진다. 캡션을 두 카드에 다 달면(didWin 을 무시하면) 여기가 빨개진다.
    #expect(twwDiff(noWinner, aWon, rect: aCard) > 100, "a 가 이겼는데 승자를 모를 때와 a 카드가 같다")
    #expect(twwDiff(noWinner, aWon, rect: bCard) == 0, "a 가 이겼는데 **b** 카드까지 바뀐다 — 캡션이 자리를 안 가린다")
    #expect(twwDiff(noWinner, bWon, rect: bCard) > 100, "b 가 이겼는데 승자를 모를 때와 b 카드가 같다")
    #expect(twwDiff(noWinner, bWon, rect: aCard) == 0, "b 가 이겼는데 **a** 카드까지 바뀐다")

    // 판은 승자 캡션에 흔들리지 않는다(카드 안 글자 한 줄만 갈린다).
    #expect(twwDiff(aWon, bWon, rect: twwBoardRect(0)) == 0, "승자 캡션이 판을 흔든다")
    #expect(twwDiff(aWon, bWon, rect: twwBoardRect(1)) == 0, "승자 캡션이 판을 흔든다")
}

// MARK: - ④ 관전자 수 · 화면 전환

/// 없으면: 관전 화면의 오른쪽 열에서 관전자 수를 빼도 초록이다.
@MainActor
@Test
func v0364TetrisWatchInfoColumnShowsTheWatcherCount() throws {
    let zero = try twwBitmap(twwStore(watchers: 0))
    let three = try twwBitmap(twwStore(watchers: 3))
    let fifteen = try twwBitmap(twwStore(watchers: 15))
    let drawn = twwDiff(zero, three, rect: twwInfoColumn)
    let counted = twwDiff(three, fifteen, rect: twwInfoColumn)
    print("[관전자 수] 0↔3 \(drawn)px · 3↔15 \(counted)px")
    #expect(drawn > 100, "관전 화면에 관전자 수가 \(drawn)px 밖에 안 뜬다")
    #expect(counted > 0, "3 과 15 가 같은 그림이다")
    // 판 자리는 안 흔들린다(오른쪽 열만 바뀐다).
    #expect(twwDiff(zero, three, rect: twwBoardRect(0)) == 0, "관전자 수가 바뀌자 판이 흔들린다")
    #expect(twwDiff(zero, three, rect: twwBoardRect(1)) == 0, "관전자 수가 바뀌자 판이 흔들린다")
}

/// 없으면: 관전 상태가 서도 로비가 그대로 그려지거나(관전 화면이 아무 데도 안 선다), 반대로 내 판이
/// 섰는데도 관전이 화면을 차지해도 초록이다.
///
/// ★ 셋째 단언이 이 시험의 본론이다: `match` 와 `spectating` 이 **동시에 참인 한 틱**을 손으로 세워
///   **렌더해서** 어느 쪽이 그려지는지 잰다(`TetrisDuelPanel.content` 의 분기 차례를 뒤집으면 빨개진다).
///   스토어가 관전을 내린다는 사실만 되물으면 화면 차례가 뒤집혀도 초록이다 — 실제로 그랬다.
@MainActor
@Test
func v0364TetrisWatchTakesTheLobbySlotButNeverBeatsMyOwnMatch() throws {
    let whole = CGRect(x: 0, y: 0, width: TWL.contentSize.width, height: TWL.contentSize.height)
    let watching = try twwBitmap(twwStore())
    let lobbyShot = try twwBitmap(twwBareStore())
    #expect(twwDiff(watching, lobbyShot, rect: whole) > 20_000, "관전 상태인데 로비와 같은 화면이다")

    // 내 판이 서면 관전은 내려간다 — 그것을 **스토어가** 한다(화면은 그 결과를 그릴 뿐이다).
    let mine = twwStore()
    mine.match = twwMatch()
    #expect(mine.spectating == nil, "내 판이 섰는데 관전이 살아 있다 — 두 화면이 동시에 참이 된다")
    #expect(mine.spectatorCount == 0, "관전자 수가 남의 판의 것으로 남았다")
    mine.phase = .playing
    let mineShot = try twwBitmap(mine)
    #expect(twwDiff(mineShot, watching, rect: whole) > 20_000, "전제: 내 판 화면과 관전 화면은 전혀 다르다")
    #expect(twwDiff(mineShot, lobbyShot, rect: whole) > 20_000, "전제: 내 판 화면과 로비도 전혀 다르다")

    // ★ 두 상태가 동시에 참인 한 틱. `match` 를 **먼저** 적어 didSet 을 지나보낸 뒤 관전을 손으로 세운다.
    let both = twwBareStore()
    both.match = twwMatch()
    both.phase = .playing
    both.spectating = twwWatch()
    #expect(both.match != nil && both.spectating != nil, "전제: 두 상태가 동시에 섰다")
    let bothShot = try twwBitmap(both)
    let vsMine = twwDiff(bothShot, mineShot, rect: whole)
    let vsWatch = twwDiff(bothShot, watching, rect: whole)
    print("[동시 상태] 내 판과 \(vsMine)px · 관전과 \(vsWatch)px")
    #expect(vsMine == 0, "둘 다 섰는데 내 판이 아닌 것이 그려졌다(내 판 화면과 \(vsMine)px 다르다)")
    #expect(vsWatch > 20_000, "둘 다 섰는데 관전 화면이 그려졌다")
}

// MARK: - ⑤ 입력 0건 (소스 계약)

/// 없으면: 관전 판에 탭·버튼·제스처가 끼어도 초록이다 — 관전자는 아무것도 쓰지 못해야 한다.
/// (그 자리는 보이지 않는 입력이라 그림으로는 못 잡는다.)
@Test
func v0364TetrisWatchBoardHasNoInputHandlersAtAll() throws {
    let source = v0364StripComments(
        try String(contentsOf: v0364RepoURL("Sources/check/TetrisDuelPanel.swift"), encoding: .utf8))
    let board = try #require(v0364Between(source, "private struct TetrisDuelSpectateSide: View {",
                                          "private struct TetrisDuelSpectateInfo: View {"),
                             "관전 자리 뷰를 못 찾았다")
    for token in ["Button(", "onTapGesture", ".gesture(", "DragGesture", "onHover", "TetrisDuelActionButton",
                  "onLongPressGesture", "TapGesture"] {
        #expect(!board.contains(token), "관전 판 자리에 입력이 있다: \(token)")
    }
    // 판 그림은 **기존 한 벌**을 쓴다(새로 그리면 방해 줄 회색이 언젠가 한쪽에서만 바뀐다).
    #expect(board.contains("TetrisBoardPainter.drawMiniBoard("), "관전 판이 기존 그리기를 안 쓴다")
    #expect(board.contains("cell: TetrisDuelWindowLayout.spectateBoardCell"), "관전 판이 셀 상수를 안 쓴다")

    // 바깥 틀에도 입력이 없다 — 유일한 입력은 오른쪽 열의 [나가기] 하나다.
    let root = try #require(v0364Between(source, "private struct TetrisDuelSpectateView: View {",
                                         "private struct TetrisDuelSpectateSide: View {"))
    for token in ["Button(", "onTapGesture", ".gesture("] {
        #expect(!root.contains(token), "관전 틀에 입력이 있다: \(token)")
    }
    let info = try #require(v0364Between(source, "private struct TetrisDuelSpectateInfo: View {",
                                         "private struct TetrisDuelStakePrompt: View {"))
    #expect(info.contains("store.leaveWatch()"), "[나가기] 가 `leaveWatch` 를 안 부른다 — 로비 목록이 낡은 채 돌아온다")
    #expect(!info.contains("store.startWatching("), "관전 화면이 또 관전을 건다")
    // 이 열만 **글자 문구**다("3명이 보고 있어요") — 자리가 넉넉한데 숫자만 두면 무엇의 N 인지 안 읽힌다.
    #expect(info.contains("showsCaption: true"), "관전 열의 관전자 수가 숫자만이다")
}

/// 없으면: `showsCaption` 을 무시하고 언제나 숫자만 그려도 초록이다(쓰이지 않는 손잡이가 된다).
@MainActor
@Test
func v0364WatcherChipCaptionFormDrawsMoreThanTheBareNumber() throws {
    func shot(_ caption: Bool) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content: WatcherCountChip(count: 3, height: 24, showsCaption: caption)
                .frame(width: 200, height: 30, alignment: .leading)
                .background(Color.black)
                .fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { throw TWWError.render }
        return bitmap
    }
    let whole = CGRect(x: 0, y: 0, width: 200, height: 30)
    let bare = try shot(false)
    let caption = try shot(true)
    let bareLit = twwLit(bare, rect: whole), captionLit = twwLit(caption, rect: whole)
    print("[관전자 문구] 숫자 \(bareLit)px · 문구 \(captionLit)px")
    #expect(captionLit > bareLit + 200, "문구 갈래가 숫자 갈래와 \(captionLit - bareLit)px 밖에 안 다르다")
    #expect(WatcherCountText.caption(3) == "3명이 보고 있어요")
}
