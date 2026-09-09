import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 **창** 렌더 — 가로 2단(게임 | 오늘 순위) 스냅샷 · 순위 열 고정 폭 · 내 행 강조 · 어제 챔피언 카드 ·
// 팝오버에서 패널이 빠졌는데 홈 높이가 그대로인지(캡션 행 버튼은 남았다).
// v0.2.48 에 **일시정지 스크림**이 붙었다 — 정지 중 판이 비쳐 보이면 순위표 앞에서 다음 기둥을 외우는 것이 이득이 된다.
// 그래서 "스크림이 캔버스를 통째로 다시 칠하는가"를 픽셀로 잰다(디자인 작업에서 초록 테스트는 아무것도 증명하지 않는다 —
// 이 파일이 남기는 PNG 를 사람이 직접 본다).
// 헬퍼는 CheckMenuRenderTests 의 것과 같은 규약(그 파일의 헬퍼는 private 이라 여기 복사).

private let mgMe = "00000000-0000-0000-0000-000000000002"

/// 스냅샷 저장 위치. 기본은 이 실행의 임시 디렉터리이고 `CHECK_SNAPSHOT_DIR` 로 덮어쓴다.
/// 세션 전용 절대 경로를 소스에 박아 두면 퍼블릭 저장소에 개인 머신 경로가 남고, 다른 기계에서는
/// `try?` 가 조용히 no-op 이 되어 "스냅샷을 남긴다"는 약속이 거짓말이 된다(2026-09-10 지적).
enum MiniGameSnapshots {
    static func directory(_ sub: String) -> URL {
        let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
        return base.appendingPathComponent(sub, isDirectory: true)
    }

    static func save(_ bitmap: NSBitmapImageRep, name: String, sub: String) {
        let dir = directory(sub)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}

/// 창 콘텐츠 좌표에서의 캔버스 사각형(pt). 레이아웃 상수에서만 나온다 — 여기서 숫자를 손으로 적으면 두 벌이 된다.
@MainActor
private var mgCanvasRect: CGRect {
    CGRect(
        x: MiniGameWindowLayout.contentPadding,
        y: MiniGameWindowLayout.contentPadding + MiniGameWindowLayout.headerHeight + MiniGameWindowLayout.headerSpacing,
        width: MiniGameWindowLayout.canvasSize.width,
        height: MiniGameWindowLayout.canvasSize.height
    )
}

@MainActor
private func mgBoard(count: Int, includeMe: Bool) -> [MiniGameBoardEntry] {
    var entries: [MiniGameBoardEntry] = []
    for i in 0..<count {
        let isMe = includeMe && i == 1
        let userID: String = isMe ? mgMe : "u\(i)"
        let name: String = isMe ? "나야" : "멤버\(i)"
        let avatar: URL? = i == 0 ? CheckMascotAssets.url(for: .neutral) : nil
        let score: Int = 990 - i * 37
        let at = Date(timeIntervalSince1970: 1_788_800_000 + Double(i) * 60)
        entries.append(MiniGameBoardEntry(userID: userID, name: name, avatarURL: avatar, bestScore: score, bestAt: at, plays: i + 1))
    }
    return entries
}

@MainActor
private func mgPanelStore(rows: Int, includeMe: Bool = true, winner: Bool = true, tokenUsage: TokenUsageStore? = nil) -> WorkTimerStore {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = mgTeamStore(members: mgSteadyMembers(count: 8), now: now, tokenUsage: tokenUsage)
    store.isMiniGamePanelVisible = true
    store.miniGameBoard = mgBoard(count: rows, includeMe: includeMe)
    store.miniGameBoardLoaded = true
    if winner {
        store.miniGameYesterdayWinner = MiniGameWinner(day: "2026-09-07", userID: "u9", name: "어제왕", avatarURL: nil, score: 977, awarded: true)
    }
    return store
}

// MARK: - 창 콘텐츠 렌더(가로 2단)

@MainActor
private func mgWindowBitmap(
    _ store: WorkTimerStore,
    kind: MiniGameKind = .timingBar,
    pause: CheckMiniGameWindowView.PauseState = .none
) throws -> NSBitmapImageRep {
    store.miniGameKind = kind
    let view = CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true, initialPause: pause)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MGRenderError.failed }
    return bitmap
}

@MainActor
@Test
func miniGameWindowDrawsTwoColumnsAtEveryStandardSize() throws {
    defer { MiniGameSpaceKey.remove() }
    let size = MiniGameWindowLayout.contentSize
    // 스펙이 요구한 여섯 장. 사람이 직접 열어 본다(두 단 정렬 · 314폭 잘림 · 금은동 · 스크림 · 470 넘침).
    let cases: [(String, MiniGameKind, Int, Bool, CheckMiniGameWindowView.PauseState)] = [
        ("window-rank", .timingBar, 6, true, .none),           // 순위 6명 + 어제 챔피언
        ("window-rank-scroll", .timingBar, 12, true, .none),   // 무스크롤 상한 초과(스크롤 대신 클립)
        ("window-quorum", .flappy, 4, false, .none),           // 정족수 미달 안내
        ("window-paused", .flappy, 6, true, .paused),          // 정지 카드
        ("window-resuming", .timingBar, 6, true, .resuming(3)) // 재개 카운트다운
    ]
    for (name, kind, rows, winner, pause) in cases {
        let store = mgPanelStore(rows: rows, winner: winner)
        let bitmap = try mgWindowBitmap(store, kind: kind, pause: pause)
        // 고정 크기를 그대로 채운다(넘치면 아래·오른쪽이 잘려 순위나 캔버스가 사라진다).
        #expect(bitmap.pixelsWide == Int(size.width) * 2, "\(name) 폭 \(bitmap.pixelsWide)px (기대 \(Int(size.width) * 2)px)")
        #expect(bitmap.pixelsHigh == Int(size.height) * 2, "\(name) 높이 \(bitmap.pixelsHigh)px (기대 \(Int(size.height) * 2)px)")
        mgSaveSnapshot(bitmap, name: name)
    }
    // 빈 순위 — 첫 실행에서 보게 될 그림.
    let empty = try mgWindowBitmap(mgEmptyBoardStore())
    #expect(empty.pixelsWide == Int(size.width) * 2 && empty.pixelsHigh == Int(size.height) * 2)
    mgSaveSnapshot(empty, name: "window-rank-empty")
}

@MainActor
@Test
func theRankColumnSitsBesideTheCanvasNotBelowIt() throws {
    defer { MiniGameSpaceKey.remove() }
    let size = MiniGameWindowLayout.contentSize
    // 순위 행이 있는 판과 빈 판의 차이는 **오른쪽 열**에서만 난다(아래가 아니라 옆이라는 증거).
    let filled = try mgWindowBitmap(mgPanelStore(rows: 6, includeMe: false, winner: true))
    let empty = try mgWindowBitmap(mgEmptyBoardStore())
    let diff = try #require(mgDiffBounds(filled, empty, tolerance: 8), "순위 행이 있으나 없으나 그림이 같다")
    let columnLeft = mgCanvasRect.maxX
    #expect(Double(diff.minX) / 2.0 >= columnLeft, "순위 차이가 캔버스 영역(x < \(columnLeft))까지 번졌다 — 2단이 아니다")
    // 그리고 그 차이는 창 세로 절반 위쪽에서 시작한다(아래에 깔린 목록이 아니다).
    #expect(Double(diff.minY) / 2.0 < size.height / 2, "순위 목록이 창 아래쪽에서 시작한다(minY \(Double(diff.minY) / 2.0)pt)")
}

/// 두 단의 **본문 윗변이 같은 y 에서 시작**한다(2026-09-08 에 한 번 지적받은 지점 — 오른쪽 머리글만 낮아
/// 순위가 18pt 떠 있었다). 왼쪽은 정지 스크림이 바뀌는 사각형(= 캔버스)의 윗변으로, 오른쪽은 어제 챔피언 카드가
/// 나타나며 바뀌는 사각형의 윗변으로 잰다 — 둘 다 각 단의 첫 본문 요소다.
@MainActor
@Test
func bothColumnBodiesStartAtTheSameY() throws {
    defer { MiniGameSpaceKey.remove() }
    let bodyTop = mgCanvasRect.minY
    let scrim = try #require(mgDiffBounds(
        try mgWindowBitmap(mgPanelStore(rows: 6, winner: true), pause: .paused),
        try mgWindowBitmap(mgPanelStore(rows: 6, winner: true), pause: .none),
        tolerance: 8), "정지 스크림이 아무것도 안 바꾼다")
    let champion = try #require(mgDiffBounds(
        try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: true)),
        try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: false)),
        tolerance: 8), "어제 챔피언 카드가 아무것도 안 그린다")
    let left = Double(scrim.minY) / 2.0
    let right = Double(champion.minY) / 2.0
    #expect(abs(left - bodyTop) <= 2, "게임 열 본문이 \(left)pt 에서 시작한다(기대 \(bodyTop)pt)")
    #expect(abs(right - bodyTop) <= 2, "순위 열 본문이 \(right)pt 에서 시작한다(기대 \(bodyTop)pt)")
    #expect(abs(left - right) <= 2, "두 단 본문 윗변이 \(left) vs \(right) 로 어긋난다")
}

@MainActor
@Test
func theYesterdayChampionCardDrawsInTheRankColumnAndCostsOneRow() throws {
    defer { MiniGameSpaceKey.remove() }
    let with = MiniGameWindowLayout.layout(hasChampionRow: true)
    // 챔피언 카드는 48pt 를 먹으므로 무스크롤 행수가 한 줄 준다(10 → 9).
    #expect(MiniGameWindowLayout.visibleRows(hasChampionRow: false) == with.visibleRows + 1)

    let shown = try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: true))
    let hidden = try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: false))
    let diff = try #require(mgDiffBounds(shown, hidden, tolerance: 8), "어제 챔피언 카드가 아무것도 안 그린다")
    #expect(Double(diff.minX) / 2.0 >= mgCanvasRect.maxX, "어제 챔피언 카드가 순위 열 밖에 그려진다")
}

// MARK: - 내 행 강조

@MainActor
@Test
func myRowIsHighlightedWithAccentBorderAndChip() throws {
    defer { MiniGameSpaceKey.remove() }
    let mine = try mgWindowBitmap(mgPanelStore(rows: 4, includeMe: true, winner: false))
    let other = try mgWindowBitmap(mgPanelStore(rows: 4, includeMe: false, winner: false))
    #expect(mine.pixelsHigh == other.pixelsHigh, "내 행 강조가 창 높이를 바꿨다")
    let diff = try #require(mgDiffBounds(mine, other, tolerance: 8), "내 행이 남의 행과 똑같이 그려졌다(테두리·'나' 칩 없음)")
    let accentMine = mgPixelCount(mine, top: diff.minY, bottom: diff.maxY, left: diff.minX, right: diff.maxX, where: mgIsAccentish)
    let accentOther = mgPixelCount(other, top: diff.minY, bottom: diff.maxY, left: diff.minX, right: diff.maxX, where: mgIsAccentish)
    #expect(accentMine > accentOther, "내 행에 accent 픽셀이 더 많지 않다(\(accentMine) vs \(accentOther))")
    mgSaveSnapshot(mine, name: "window-myrow")
}

/// 금·은·동 배지가 서로 **구분되게** 그려진다. 색만으로 정보를 주지 않으려고 배지 안에는 언제나 숫자가 있지만,
/// 세 색이 한 덩어리로 보이면 "순위표"라는 인상 자체가 죽는다.
@MainActor
@Test
func theTopThreeBadgesAreVisiblyDifferentFromEachOtherAndFromTheRest() throws {
    defer { MiniGameSpaceKey.remove() }
    let bitmap = try mgWindowBitmap(mgPanelStore(rows: 6, includeMe: false, winner: false))
    // 행 y(pt): 본문 윗변에서 (rowHeight + rowSpacing) 간격. 배지는 행 왼쪽 끝(패딩 5 + 반지름 11).
    let badgeX = MiniGameWindowLayout.contentPadding + MiniGameWindowLayout.canvasSize.width
        + MiniGameWindowLayout.columnSpacing + 5 + 11
    func badgeColor(rank: Int) -> (Int, Int, Int) {
        let top = mgCanvasRect.minY + CGFloat(rank - 1) * (MiniGameWindowLayout.rowHeight + MiniGameWindowLayout.rowSpacing)
        // 배지 원의 위쪽 가장자리 안쪽(숫자 글리프를 피한다).
        return mgPixel(bitmap, x: badgeX, y: top + MiniGameWindowLayout.rowHeight / 2 - 8)
    }
    let gold = badgeColor(rank: 1), silver = badgeColor(rank: 2), bronze = badgeColor(rank: 3), plain = badgeColor(rank: 5)
    func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }
    #expect(distance(gold, silver) > 60, "금·은이 구분되지 않는다 \(gold) vs \(silver)")
    #expect(distance(silver, bronze) > 60, "은·동이 구분되지 않는다 \(silver) vs \(bronze)")
    #expect(distance(gold, bronze) > 60, "금·동이 구분되지 않는다 \(gold) vs \(bronze)")
    // 4위부터는 투명 배지 — 메달 셋보다 훨씬 어둡다.
    for (name, medal) in [("금", gold), ("은", silver), ("동", bronze)] {
        #expect(medal.0 + medal.1 + medal.2 > plain.0 + plain.1 + plain.2 + 150,
                "\(name) 배지가 일반 배지와 비슷하다 \(medal) vs \(plain)")
    }
}

// MARK: - 일시정지 스크림은 판을 **통째로** 가린다

/// 순위표가 걸린 게임이라 정지해 놓고 다음 기둥을 외우는 것이 이득이 되면 안 된다 — 그게 이 스크림의 이유다.
/// 그래서 두 가지를 잰다: ① 스크림이 캔버스의 **네 변까지** 다시 칠하는가 ② 그 결과가 충분히 어두운가
/// (=밑그림이 비쳐 나오지 않는가). 카드·카운트다운 숫자가 있는 가운데는 빼고 위·아래 띠에서 잰다.
@MainActor
@Test
func thePauseScrimRepaintsTheWholeCanvasAndHidesTheBoard() throws {
    defer { MiniGameSpaceKey.remove() }
    let canvas = mgCanvasRect
    let store = mgPanelStore(rows: 6, winner: true)
    let playing = try mgWindowBitmap(store, kind: .flappy, pause: .none)
    let paused = try mgWindowBitmap(store, kind: .flappy, pause: .paused)
    let diff = try #require(mgDiffBounds(playing, paused, tolerance: 8), "정지해도 그림이 그대로다")

    // ① 스크림이 캔버스의 **네 변까지** 닿는다. 가운데만 덮는 카드였다면 가장자리 픽셀이 그대로다 —
    //    거기로 다음 기둥이 보이면 정지해 두는 것이 이득이 된다. (그림자 반경 10 을 빼고 안쪽 4pt 에서 잰다.)
    let inset: CGFloat = 4
    let edges: [(String, CGPoint)] = [
        ("왼쪽 변", CGPoint(x: canvas.minX + inset, y: canvas.midY)),
        ("오른쪽 변", CGPoint(x: canvas.maxX - inset, y: canvas.midY)),
        ("윗변", CGPoint(x: canvas.midX, y: canvas.minY + inset)),
        ("아랫변", CGPoint(x: canvas.midX, y: canvas.maxY - inset))
    ]
    for (name, point) in edges {
        let before = mgPixel(playing, x: point.x, y: point.y)
        let after = mgPixel(paused, x: point.x, y: point.y)
        #expect(before != after, "스크림이 캔버스 \(name)에 안 닿는다 \(before) → \(after)")
    }
    // 그리고 캔버스 밖으로는 (그림자 반경 10 + 오프셋 4 를 넘어) 새지 않는다 — 순위 열은 손대지 않는다.
    let rankLeft = canvas.maxX + MiniGameWindowLayout.columnSpacing
    #expect(Double(diff.maxX) / 2.0 < rankLeft, "정지가 순위 열까지 다시 칠했다(maxX \(Double(diff.maxX) / 2.0)pt)")
    #expect(Double(diff.minY) / 2.0 >= canvas.minY - 14, "정지가 헤더 행까지 번졌다(minY \(Double(diff.minY) / 2.0)pt)")
    #expect(Double(diff.maxY) / 2.0 <= canvas.maxY + 18, "정지가 하단 스트립까지 번졌다(maxY \(Double(diff.maxY) / 2.0)pt)")

    // ② 카드가 닿지 않는 위·아래 띠(각 50pt)에서 가장 밝은 픽셀도 어두워야 한다. panelElevated(0.21,0.22,0.29)에
    //    0.93 을 곱하면 밑그림이 아무리 밝아도 채널당 0.07×255 ≈ 18 밖에 못 올라온다.
    for band in [CGRect(x: canvas.minX + 4, y: canvas.minY + 4, width: canvas.width - 8, height: 50),
                 CGRect(x: canvas.minX + 4, y: canvas.maxY - 54, width: canvas.width - 8, height: 50)] {
        let brightest = mgBrightestChannel(paused, rect: band)
        #expect(brightest <= 110, "정지 중인데 캔버스 띠 \(band.origin.y)pt 에 밝기 \(brightest) 픽셀이 있다 — 판이 비쳐 보인다")
    }
}

/// ★ **밑그림 무관성** — 위 '밝기 밴드'가 못 잡는 것을 잡는다.
///
/// 2026-09-10 뮤테이션 실증: 불투명 바닥층(`CheckTheme.panel`)을 지우고 `panelElevated.opacity(0.93)` 하나만
/// 남겨도 위 두 단언은 **전부 초록**이었다(밑그림이 7% 만큼 비쳐 나오는데도). 그 판의 스냅샷에는 정지 카드
/// 왼쪽 위에 마스코트가 유령처럼 비쳤고, 원본과 43,255 픽셀이 달랐다. 저자가 이미 겪었다고 주석에 적어 둔
/// 회귀인데(MiniGamePanel.swift pauseOverlay) 그걸 막는 단언이 없었다.
///
/// 그래서 밝기가 아니라 **의존성**을 잰다: 캔버스 내용이 완전히 다른 두 판(플래피 · 타이밍 바)을 각각 정지 화면으로
/// 그렸을 때 캔버스 픽셀이 **한 점도 달라지지 않아야** 한다. 밑그림이 1%라도 새면 두 장이 갈리므로,
/// 불투명도를 낮추든 층을 하나 빼든 즉시 빨개진다.
///
/// 재개 카운트다운(`.resuming(3)`)을 쓰는 이유: 정지 **카드**는 게임마다 부제가 다르다(플래피 = 기둥 수 ·
/// 타이밍 바 = 판 무효). 카운트다운 화면은 두 게임이 글자 하나까지 같아서 "밑그림 말고는 아무것도 다르지 않다"가
/// 성립한다 — 그 화면도 같은 스크림 두 층 위에 그려진다.
@MainActor
@Test
func thePauseScrimMakesTheCanvasIndependentOfWhateverWasUnderneath() throws {
    defer { MiniGameSpaceKey.remove() }
    let store = mgPanelStore(rows: 6, winner: true)
    let flappy = try mgWindowBitmap(store, kind: .flappy, pause: .resuming(3))
    let timing = try mgWindowBitmap(store, kind: .timingBar, pause: .resuming(3))

    // 먼저 두 판이 실제로 다른 그림이라는 것부터 확인한다(안 다르면 이 테스트는 아무것도 안 잰다).
    let playingFlappy = try mgWindowBitmap(store, kind: .flappy, pause: .none)
    let playingTiming = try mgWindowBitmap(store, kind: .timingBar, pause: .none)
    #expect(mgDiffBounds(playingFlappy, playingTiming, tolerance: 8) != nil,
            "두 게임의 캔버스가 같은 그림이다 — 이 대조군으로는 밑그림 누수를 못 잰다")

    // 캔버스 안쪽에서 두 정지 화면을 픽셀로 비교한다. 모서리 라운딩(반지름 14)의 호는 뺀다 —
    // 거기는 스크림이 아니라 창 배경과 섞이는 자리라 래스터라이즈 반올림으로 채널 4까지 흔들린다(실측).
    let canvas = mgCanvasRect.insetBy(dx: 16, dy: 16)
    let worst = mgMaxChannelDifference(flappy, timing, rect: canvas)
    #expect(worst <= 2,
            "정지 화면이 밑에 깔린 판에 따라 달라진다(채널 최대 차 \(worst)) — 스크림이 판을 다 못 지웠다")
}

// MARK: - 미니게임 입구는 홈 팝오버의 높이를 바꾸지 않는다

/// 미니게임 입구가 어디에 있든 **팝오버 높이는 517pt 그대로**여야 한다.
///
/// 통합 갱신(2026-09-10): 입구가 **캡션 행 → 오른쪽 세로 레일**로 이사했다(설정·내 기록·콕찌르기·팀 현황·울트라와
/// 한 벌). 그래서 이 테스트가 재는 사실이 둘로 늘었다.
///  · 높이 517pt: 예전 계약 그대로다. 레일은 본문 **오른쪽에 나란히** 서므로 세로 예산을 1pt 도 안 먹는다 —
///    그게 이 배치를 고른 이유이고, 여기가 빨개지면 레일이 창 높이를 결정하기 시작했다는 뜻이다
///    (짝: CheckMenuRenderTests.settingsEntryMovedToTheSideRailAndIsStillNotAMenu · sideRailNeverDecidesTheWindowHeight).
///  · 폭 414pt: 본문 316 + 간격 10 + 레일 64 + 바깥 padding 24. 미니게임 입구가 레일에 **실제로 실렸다**는
///    증거다(레일이 안 붙으면 340 으로 떨어진다).
///
/// 폭을 밖에서 씌우지 않는다 — `mgRenderNaturalBitmap` 위 주석 참고. 예전처럼 340 을 강제하면 414 짜리
/// 내용이 그 안에 넘쳐 높이만 우연히 517 로 맞는 **거짓 초록**이 된다.
@MainActor
@Test
func homePopoverHeightIsUnchangedByTheMiniGameButton() throws {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = mgTeamStore(members: mgPresenceMembers(now: now), now: now)
    let bitmap = try mgRenderNaturalBitmap(CheckMenuView(store: store))
    #expect(bitmap.pixelsHigh == 517 * 2, "미니게임 입구가 홈 높이를 \(Double(bitmap.pixelsHigh) / 2)pt 로 바꿨다")
    #expect(bitmap.pixelsWide == 414 * 2, "메인 팝오버 폭이 \(Double(bitmap.pixelsWide) / 2)pt 다 — 레일이 안 붙었다")
}

@MainActor
private func mgEmptyBoardStore() -> WorkTimerStore {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = mgTeamStore(members: mgSteadyMembers(count: 8), now: now)
    store.isMiniGamePanelVisible = true
    store.miniGameBoardLoaded = true
    store.miniGameYesterdayWinner = MiniGameWinner(day: "2026-09-07", userID: "u9", name: "어제왕", avatarURL: nil, score: 977, awarded: true)
    return store
}

// MARK: - 헬퍼(복사본)

private enum MGRenderError: Error { case failed }

/// 폭을 **밖에서 강제하지 않는** 렌더(2026-09-10 통합).
///
/// `CheckMenuView` 는 자기 폭을 스스로 정한다 — 메인 화면 414(본문 316 + 세로 레일 64), 로그인·무소속 340.
/// 아래 `mgRenderBitmap` 처럼 340 을 씌우면 414 짜리 내용이 그 안에 가운데 정렬로 넘쳐 레일이 그림 밖으로
/// 밀린다(실앱에서는 창이 그 자리를 잘라낸다 — CheckApp 에서 `.frame(width: 340)` 을 지운 이유와 같은 결함).
/// 팝오버 전체를 그리는 자는 반드시 이쪽을 쓴다. 캔버스처럼 크기가 고정된 뷰는 아래 것을 그대로 쓰면 된다.
@MainActor
private func mgRenderNaturalBitmap(_ view: some View, scale: CGFloat = 2) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = scale
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MGRenderError.failed }
    return bitmap
}

@MainActor
private func mgRenderBitmap(_ view: some View, width: CGFloat = 340, scale: CGFloat = 2) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = scale
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MGRenderError.failed }
    return bitmap
}

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차. 0 이면 한 바이트도 다르지 않다.
private func mgMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) {
                worst = max(worst, abs(Int(a[offset + channel]) - Int(b[offset + channel])))
            }
        }
    }
    return worst
}

@MainActor
private func mgSaveSnapshot(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "window")
}

private func mgIsolatedDefaults() -> UserDefaults {
    let suiteName = "v0246-mg-render-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func mgInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: mgIsolatedDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-mg-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-mg-token-cache-\(id).json", isDirectory: false)
    )
}

@MainActor
private func mgTeamStore(members: [TeamMemberStatus], now: Date, tokenUsage: TokenUsageStore? = nil) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: mgIsolatedDefaults(),
        tokenUsage: tokenUsage ?? mgInertTokenStore()
    )
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mgMe)
    store.displayNow = now
    store.teamMembers = members
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    return store
}

@MainActor
private func mgSteadyMembers(count: Int) -> [TeamMemberStatus] {
    (0..<count).map { i in
        TeamMemberStatus(
            id: "aaaaaaaa-0000-0000-0000-\(String(format: "%012d", i))",
            name: "멤버\(i)", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600
        )
    }
}

@MainActor
private func mgPresenceMembers(now: Date) -> [TeamMemberStatus] {
    [
        TeamMemberStatus(id: mgMe, name: "영식", status: .working, updatedAt: nil, currentSessionStartedAt: now.addingTimeInterval(-3_661), weeklyDurationSeconds: 14_400, avatarURL: CheckMascotAssets.url(for: .neutral)),
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000003", name: "민수", status: .working, updatedAt: now.addingTimeInterval(-420), currentSessionStartedAt: now.addingTimeInterval(-7_620), weeklyDurationSeconds: 28_800, lastSeenAt: now.addingTimeInterval(-420)),
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000001", name: "yesung", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200)
    ]
}

private func mgDiffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, tolerance: Int = 0) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let offset = y * bpr + x * spp
            var differs = false
            for sample in 0..<min(spp, 3) where abs(Int(pa[offset + sample]) - Int(pb[offset + sample])) > tolerance { differs = true; break }
            if differs { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, minY, maxX, maxY)
}

private func mgPixelCount(_ bitmap: NSBitmapImageRep, top: Int, bottom: Int, left: Int, right: Int, where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let y0 = max(0, top), y1 = min(bitmap.pixelsHigh - 1, bottom)
    let x0 = max(0, left), x1 = min(bitmap.pixelsWide - 1, right)
    guard y0 <= y1, x0 <= x1 else { return 0 }
    var count = 0
    for y in y0...y1 { for x in x0...x1 {
        let offset = y * bpr + x * spp
        if predicate(Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])) { count += 1 }
    } }
    return count
}

/// pt 좌표(스케일 2 가정)의 한 픽셀 색.
private func mgPixel(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, 0, 0) }
    let px = min(max(Int(x * 2), 0), bitmap.pixelsWide - 1)
    let py = min(max(Int(y * 2), 0), bitmap.pixelsHigh - 1)
    let offset = py * bitmap.bytesPerRow + px * bitmap.samplesPerPixel
    return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
}

/// pt 사각형 안에서 가장 밝은 채널 값(스크림이 밑그림을 덮었는지 재는 지점).
private func mgBrightestChannel(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var brightest = 0
    for y in y0...y1 { for x in x0...x1 {
        let offset = y * bpr + x * spp
        for sample in 0..<3 { brightest = max(brightest, Int(data[offset + sample])) }
    } }
    return brightest
}

/// accent(파랑 계열)에 물든 픽셀: 파랑이 빨강보다 뚜렷이 높다.
private func mgIsAccentish(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    b > r + 40 && b > 90
}
