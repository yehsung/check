import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 **창** 렌더 — 가로 2단(게임 | 오늘 순위) 스냅샷 · 순위 열 고정 폭 · 내 행 강조 · 어제 1등 줄 ·
// 팝오버에서 패널이 빠졌는데 홈 높이가 그대로인지(캡션 행 버튼은 남았다).
// 헬퍼는 CheckMenuRenderTests 의 것과 같은 규약(그 파일의 헬퍼는 private 이라 여기 복사).

private let mgMe = "00000000-0000-0000-0000-000000000002"
private let mgSnapshotDir = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/agent-win"

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
private func mgWindowBitmap(_ store: WorkTimerStore, kind: MiniGameKind = .timingBar) throws -> NSBitmapImageRep {
    store.miniGameKind = kind
    let view = CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true)
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
    let cases: [(String, MiniGameKind, Int)] = [
        ("window-timing", .timingBar, 12),   // 순위가 넘치는 판(스크롤 대신 클립)
        ("window-flappy", .flappy, 4),
        ("window-large", .timingBar, 0)      // 빈 순위 — 첫 실행에서 보게 될 그림
    ]
    for (name, kind, rows) in cases {
        let store = rows > 0 ? mgPanelStore(rows: rows, winner: true) : mgEmptyBoardStore()
        let bitmap = try mgWindowBitmap(store, kind: kind)
        // 고정 크기를 그대로 채운다(넘치면 아래·오른쪽이 잘려 순위나 캔버스가 사라진다).
        #expect(bitmap.pixelsWide == Int(size.width) * 2, "\(name) 폭 \(bitmap.pixelsWide)px (기대 \(Int(size.width) * 2)px)")
        #expect(bitmap.pixelsHigh == Int(size.height) * 2, "\(name) 높이 \(bitmap.pixelsHigh)px (기대 \(Int(size.height) * 2)px)")
        mgSaveSnapshot(bitmap, name: name)
    }
}

@MainActor
@Test
func theRankColumnSitsBesideTheCanvasNotBelowIt() throws {
    defer { MiniGameSpaceKey.remove() }
    let size = MiniGameWindowLayout.contentSize
    let layout = MiniGameWindowLayout.layout(hasYesterdayRow: true)
    // 순위 행이 있는 판과 빈 판의 차이는 **오른쪽 열**에서만 난다(아래가 아니라 옆이라는 증거).
    let filled = try mgWindowBitmap(mgPanelStore(rows: 6, includeMe: false, winner: true))
    let empty = try mgWindowBitmap(mgEmptyBoardStore())
    let diff = try #require(mgDiffBounds(filled, empty, tolerance: 8), "순위 행이 있으나 없으나 그림이 같다")
    let columnLeft = MiniGameWindowLayout.contentPadding + layout.canvasSize.width
    #expect(Double(diff.minX) / 2.0 >= columnLeft, "순위 차이가 캔버스 영역(x < \(columnLeft))까지 번졌다 — 2단이 아니다")
    // 그리고 그 차이는 창 세로 절반 위쪽에서 시작한다(아래에 깔린 목록이 아니다).
    #expect(Double(diff.minY) / 2.0 < size.height / 2, "순위 목록이 창 아래쪽에서 시작한다(minY \(Double(diff.minY) / 2.0)pt)")
}

@MainActor
@Test
func theYesterdayWinnerRowDrawsInTheRankColumnAndCostsOneRow() throws {
    defer { MiniGameSpaceKey.remove() }
    let with = MiniGameWindowLayout.layout(hasYesterdayRow: true)
    // 고정 높이에 여유가 있어 어제 줄이 있어도 행수는 그대로다(둘 다 상한 10).
    #expect(MiniGameWindowLayout.visibleRows(hasYesterdayRow: false) == with.visibleRows)

    let shown = try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: true))
    let hidden = try mgWindowBitmap(mgPanelStore(rows: 3, includeMe: false, winner: false))
    let diff = try #require(mgDiffBounds(shown, hidden, tolerance: 8), "어제 1등 줄이 아무것도 안 그린다")
    #expect(Double(diff.minX) / 2.0 >= MiniGameWindowLayout.contentPadding + with.canvasSize.width,
            "어제 1등 줄이 순위 열 밖에 그려진다")
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

// MARK: - 캡션 행: 미니게임 버튼이 홈 높이를 바꾸지 않는다

@MainActor
@Test
func homePopoverHeightIsUnchangedByTheMiniGameButton() throws {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = mgTeamStore(members: mgPresenceMembers(now: now), now: now)
    let bitmap = try mgRenderBitmap(CheckMenuView(store: store))
    // CheckMenuRenderTests.settingsEntryIsDrawnInTheCaptionRowAndIsNotAMenu 와 같은 517pt 계약(18pt 소형 버튼 하나 더).
    #expect(bitmap.pixelsHigh == 517 * 2, "캡션 행에 버튼을 더했더니 홈 높이가 \(Double(bitmap.pixelsHigh) / 2)pt 로 변했다")
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

private let mgSampleUpdateNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

private enum MGRenderError: Error { case failed }

@MainActor
private func mgRenderBitmap(_ view: some View, width: CGFloat = 340, scale: CGFloat = 2) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = scale
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw MGRenderError.failed }
    return bitmap
}

@MainActor
private func mgSaveSnapshot(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = URL(fileURLWithPath: mgSnapshotDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
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
private func mgSeededTokenStore() -> TokenUsageStore {
    let defaults = mgIsolatedDefaults()
    let usage = TokenUsageMonthly(
        month: TokenUsageMonthKey.current(),
        claudeInput: 8_460_869, claudeOutput: 35_849_782,
        claudeCacheRead: 4_165_692_507, claudeCacheCreation: 200_802_730,
        codexInput: 145_068_307, codexOutput: 623_160
    )
    if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: TokenUsageStore.snapshotKey) }
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: defaults,
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

/// accent(파랑 계열)에 물든 픽셀: 파랑이 빨강보다 뚜렷이 높다.
private func mgIsAccentish(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    b > r + 40 && b > 90
}
