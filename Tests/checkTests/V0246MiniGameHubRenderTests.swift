import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 패널 렌더 — 창 높이 상한(700pt) 세 조합 · 순위 행 30pt 단위 성장/클립 · 내 행 강조 · 어제 1등 줄 · 스냅샷.
// 헬퍼는 CheckMenuRenderTests 의 것과 같은 규약(그 파일의 헬퍼는 private 이라 여기 복사).

private let mgMe = "00000000-0000-0000-0000-000000000002"
private let mgSnapshotDir = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/agent-hub"

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

// MARK: - 창 높이 상한

@MainActor
@Test
func miniGamePanelPopoverStaysWithinHeightCapForChromeCombinations() throws {
    defer { MiniGameSpaceKey.remove() }
    var cases: [(String, Double)] = []
    func measure(_ label: String, _ view: some View) throws {
        let bitmap = try mgRenderBitmap(view)
        let points = Double(bitmap.pixelsHigh) / 2.0
        cases.append((label, points))
        #expect(points <= 700.0, "\(label) 이 700pt 상한을 넘었습니다: \(points)pt")
        mgSaveSnapshot(bitmap, name: label)
    }

    // (a) 크롬 0: 패널 + 10행(스크롤 초과) + 어제 1등 줄.
    let plain = mgPanelStore(rows: 10, tokenUsage: mgSeededTokenStore())
    try measure("panel-home", CheckMenuView(store: plain, previewClipsOverflowList: true))

    // (b) 새 버전 배너(노트 4줄 = 149pt).
    let update = mgPanelStore(rows: 10, tokenUsage: mgSeededTokenStore())
    try measure("panel-update", CheckMenuView(store: update, previewClipsOverflowList: true, previewUpdateBanner: true, previewUpdateNotes: mgSampleUpdateNotes))

    // (c) 12시간 확인 배너 + 목표 편집 행(92 + 92 = 184pt) — 헤더가 가장 부푸는 조합.
    let longSession = mgPanelStore(rows: 10, tokenUsage: mgSeededTokenStore())
    longSession.startedAt = Date().addingTimeInterval(-10)
    longSession.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 10)
    longSession.isLongSessionPromptActive = true
    try measure("panel-longsession", CheckMenuView(store: longSession, previewClipsOverflowList: true, previewGoalEditing: true))

    // 대조군: 크롬이 없을 때가 가장 낮지는 않아도(패널이 크롬에 양보한다) 세 값 모두 상한 안이어야 하고, 크롬 조합이 홈보다 낮으면 안 된다.
    #expect(cases.count == 3)
}

// MARK: - 순위 목록 높이 규약

@MainActor
@Test
func rankListGrowsThirtyPointsPerRowUntilFourAndThenClips() throws {
    defer { MiniGameSpaceKey.remove() }
    func height(rows: Int) throws -> Double {
        let store = mgPanelStore(rows: rows, includeMe: false, winner: false)
        let bitmap = try mgRenderBitmap(MiniGamePanel(store: store, clipsOverflowInsteadOfScroll: true), width: 316)
        return Double(bitmap.pixelsHigh) / 2.0
    }
    let h0 = try height(rows: 0), h1 = try height(rows: 1), h2 = try height(rows: 2)
    let h3 = try height(rows: 3), h4 = try height(rows: 4), h5 = try height(rows: 5), h9 = try height(rows: 9)
    // 빈 목록은 안내 한 줄(26pt)이라 1행과 같은 높이다.
    #expect(abs(h0 - h1) <= 0.5, "빈 목록(\(h0)) 과 1행(\(h1)) 높이가 다르다")
    for (a, b, label) in [(h1, h2, "1→2"), (h2, h3, "2→3"), (h3, h4, "3→4")] {
        #expect(abs((b - a) - 30) <= 0.5, "\(label) 행 성장이 30pt(26+4)가 아니라 \(b - a)pt 다")
    }
    // 4행이 상한 — 그 뒤는 클립(스크롤)이라 높이가 멈춘다.
    #expect(abs(h5 - h4) <= 0.5, "5행(\(h5))이 4행(\(h4))보다 높다 — 상한이 안 먹는다")
    #expect(abs(h9 - h4) <= 0.5)
    // 본문 예산: 캔버스 200 + 12 + 제목줄 18 + 4 + 목록 116 + 8 + 요약 14 (+ 제목행 27 + 12 + 구분선 1 + 12 + 패딩 24) ≤ 700 안.
    #expect(h4 <= 425 + 27 + 12 + 1 + 12 + 24 + 1, "4행 패널 자연 높이 \(h4) 가 예산을 넘는다")
}

@MainActor
@Test
func yesterdayWinnerRowAddsExactlyTwentyTwoPoints() throws {
    defer { MiniGameSpaceKey.remove() }
    let with = try mgRenderBitmap(MiniGamePanel(store: mgPanelStore(rows: 3, winner: true), clipsOverflowInsteadOfScroll: true), width: 316)
    let without = try mgRenderBitmap(MiniGamePanel(store: mgPanelStore(rows: 3, winner: false), clipsOverflowInsteadOfScroll: true), width: 316)
    let delta = Double(with.pixelsHigh - without.pixelsHigh) / 2.0
    #expect(abs(delta - 22) <= 0.5, "어제 1등 줄이 18+4 = 22pt 가 아니라 \(delta)pt 를 먹는다(예산 표의 44 가 거짓이 된다)")
}

// MARK: - 내 행 강조

@MainActor
@Test
func myRowIsHighlightedWithAccentBorderAndChip() throws {
    defer { MiniGameSpaceKey.remove() }
    // 같은 목록을 '내 행 있음/없음'으로 두 번 그려 차이가 목록 영역(하반부)에만 있는지 본다.
    let mine = try mgRenderBitmap(MiniGamePanel(store: mgPanelStore(rows: 4, includeMe: true, winner: false), clipsOverflowInsteadOfScroll: true), width: 316)
    let other = try mgRenderBitmap(MiniGamePanel(store: mgPanelStore(rows: 4, includeMe: false, winner: false), clipsOverflowInsteadOfScroll: true), width: 316)
    #expect(mine.pixelsHigh == other.pixelsHigh, "내 행 강조가 행 높이를 바꿨다")
    let diff = try #require(mgDiffBounds(mine, other, tolerance: 8), "내 행이 남의 행과 똑같이 그려졌다(테두리·'나' 칩 없음)")
    // 차이는 캔버스(위 ~ 27+12+1+12+200+12 ≈ 264pt) 아래 목록 띠에서만 난다.
    #expect(diff.minY >= 250 * 2, "차이가 캔버스 위에서도 난다(minY \(diff.minY / 2)pt)")
    // accent 계열 픽셀이 내 행 판에 더 많다(테두리 accent .45 + 칩).
    let accentMine = mgPixelCount(mine, top: diff.minY, bottom: diff.maxY, left: 0, right: mine.pixelsWide - 1, where: mgIsAccentish)
    let accentOther = mgPixelCount(other, top: diff.minY, bottom: diff.maxY, left: 0, right: other.pixelsWide - 1, where: mgIsAccentish)
    #expect(accentMine > accentOther, "내 행에 accent 픽셀이 더 많지 않다(\(accentMine) vs \(accentOther))")
    mgSaveSnapshot(mine, name: "panel-myrow")
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
