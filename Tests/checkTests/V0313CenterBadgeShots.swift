import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.13 소속 센터 배지 — 육안 비교용 행 목록 스냅샷
//
// 부산센터 배포와 함께 사람 이름 옆·팀명 옆에 **소속 센터 배지**('부산'/'서울')를 달아야 한다.
// 후보 세 가지를 1× 로 나란히 놓고 고르기 위한 **기준선(배지 없음)** 하네스다.
//
// 왜 패널이 아니라 행 목록만 그리나: 배지가 바꾸는 것은 **한 행 안의 폭 예산**이다. 패널을 통째로 그리면
// 헤더·푸터·배너가 그림의 대부분을 먹어 세 후보의 차이가 눈에 안 들어온다(그리고 1× 에서 글자가 너무 작아진다).
// 그래서 이 파일은 네 화면의 행 5개씩만, 실제 프로덕션 이름·팀명으로 그린다.
//
// ★ 실제 데이터만 쓴다. 가상 이름을 넣으면 "우리 유저 이름에서 잘리는가"를 판단할 수 없다 —
//   프로덕션 최장 별명(천만번더들어도기분좋은말사랑해 142.72pt)과 2위(맥주밤거리엠버서더 85.63pt)가
//   반드시 들어가야 이 그림이 결정 근거가 된다.

/// 네 화면이 **공유하는** 시드. 변형끼리 비교 가능해야 하므로 이름·순서·센터 배정은 여기 한 곳에서만 정한다.
enum V0313CenterSeed {
    /// 사람 5명. 실제 프로덕션 별명 목록(names.txt)에서 골랐다 —
    /// 최장(15자) · 2위(9자) · 3자 둘 · 1자 하나로 길이 스펙트럼을 덮는다.
    /// **행 순서가 곧 센터 배정의 인덱스다.** 순서를 바꾸면 변형끼리 비교가 깨진다.
    static let names: [String] = [
        "천만번더들어도기분좋은말사랑해",   // 0 · 프로덕션 최장 별명 142.72pt
        "맥주밤거리엠버서더",               // 1 · 2위 85.63pt
        "킹예성",                          // 2 · 내 행('나' 칩 + 토큰판에선 '비공개' 칩까지)
        "조현준",                          // 3
        "윤"                               // 4 · 최단(1자)
    ]

    /// 팀 5개. 실제 팀명 목록(teams.txt)에서 골랐다 — 최장(Alpha Everyday 84.34pt)·2위(버디버디에서 팀 만 82.11pt) 포함.
    static let teams: [String] = [
        "버디버디에서 팀 만",   // 0 · 2위 82.11pt
        "낭만러너 김유정",      // 1
        "Alpha Everyday",      // 2 · 최장 84.34pt + '우리 팀' 칩 → 이 화면의 최악 조합
        "일단 돌아는 감",       // 3
        "AIng"                 // 4
    ]

    /// ★★ 센터 배정 — **0행과 3행이 부산, 나머지(1·2·4)가 서울.** 네 화면 전부 같은 규칙을 쓴다.
    /// 부산 초기 인원이 적은 현실을 5행에 옮긴 비율(2:3)이고, 사람 행과 팀 행에 **같은 인덱스 규칙**을 쓴다.
    /// 변형 3종은 이 상수를 그대로 읽어야 한다 — 배정이 갈리면 세 그림이 서로 다른 데이터를 비교하게 된다.
    static let busanRows: Set<Int> = [0, 3]

    /// 내 행 / 내 팀 행(칩이 붙는 행)의 인덱스. 셋 다 2행으로 맞춰 둔다 — 화면마다 칩 위치가 달라지면
    /// "칩이 붙은 행에서 배지가 어떻게 되는가"를 화면끼리 겹쳐 볼 수 없다.
    static let myRow = 2

    /// 0행이 부산인 이유: 최장 별명에 배지가 붙는 최악을 **반드시** 한 장에 담아야 한다.
    /// ('부산' 칩과 '서울' 칩은 둘 다 9pt bold 2글자 + 좌우 6pt 패딩 = 27.57pt 로 폭이 같으므로
    ///  배지를 양쪽 센터에 다 다는 변형에서는 어느 행이 부산인지가 폭에 영향을 주지 않는다.
    ///  다만 **부산에만** 배지를 다는 변형이 있을 수 있어, 최악 행을 부산에 두는 쪽이 안전하다.)
    static func center(row: Int) -> String { busanRows.contains(row) ? "부산" : "서울" }

    /// 결정적 렌더를 위한 고정 '오늘'(KST). 토큰 행의 "오늘 +N" 줄이 실행 날짜에 따라 0 으로 바뀌지 않게 한다.
    static let todayKey = "2026-09-12"
}

// MARK: - 스냅샷 저장 (CHECK_SNAPSHOT_DIR 규약 — V0249MessageWindowTests 와 같은 관례)

/// 저장 위치. 기본은 이 실행의 임시 디렉터리이고 `CHECK_SNAPSHOT_DIR` 로 덮어쓴다 —
/// 세션 전용 절대 경로를 소스에 박아 두면 퍼블릭 저장소에 개인 머신 경로가 남는다.
enum V0313Snapshots {
    static var directory: URL {
        ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0313", isDirectory: true)
    }

    @discardableResult
    static func save(_ bitmap: NSBitmapImageRep, name: String) -> URL? {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = dir.appendingPathComponent(name)
        try? png.write(to: url)
        return url
    }
}

private enum V0313RenderError: Error { case failed }

// MARK: - 렌더 · 잉크 검사

/// 행 목록을 패널 배경에 얹어 자연 크기로 그린다. **scale 은 언제나 명시**한다 —
/// ImageRenderer 의 기본 배율은 환경(주 디스플레이 backingScaleFactor)에 따라 갈려,
/// 안 주면 1× 를 달라고 했는데 2× 가 나오거나 그 반대가 된다(1× 로 눈으로 고르겠다는 요구와 직결).
@MainActor
private func v0313Bitmap(_ list: some View, scale: CGFloat) throws -> NSBitmapImageRep {
    let view = list
        .padding(12)
        .background(CheckTheme.background)
        .fixedSize()
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0313RenderError.failed }
    return bitmap
}

/// 같은 크기의 **배경만** 그린 비트맵. 배경이 그라디언트라 "한 픽셀을 배경색으로 삼는" 잉크 탐지는
/// 통째로 거짓말한다 — 그래서 기준을 그림 하나로 둔다(V0249 스위트와 같은 근거).
@MainActor
private func v0313BlankBitmap(matching bitmap: NSBitmapImageRep, scale: CGFloat) throws -> NSBitmapImageRep {
    let view = Color.clear
        .frame(width: CGFloat(bitmap.pixelsWide) / scale, height: CGFloat(bitmap.pixelsHigh) / scale)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let blank = NSBitmapImageRep(data: tiff)
    else { throw V0313RenderError.failed }
    return blank
}

/// 배경과 눈에 띄게 다른 픽셀의 비율. 0 이면 그림이 비었다(빈 PNG·전부 투명·행이 안 그려짐).
private func v0313InkRatio(_ bitmap: NSBitmapImageRep, blank: NSBitmapImageRep) -> Double {
    guard let lhs = bitmap.bitmapData, let rhs = blank.bitmapData,
          bitmap.pixelsWide == blank.pixelsWide, bitmap.pixelsHigh == blank.pixelsHigh,
          bitmap.samplesPerPixel >= 3, blank.samplesPerPixel >= 3
    else { return 0 }
    var different = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let a = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
            let b = y * blank.bytesPerRow + x * blank.samplesPerPixel
            let dr = abs(Int(lhs[a]) - Int(rhs[b]))
            let dg = abs(Int(lhs[a + 1]) - Int(rhs[b + 1]))
            let db = abs(Int(lhs[a + 2]) - Int(rhs[b + 2]))
            if max(dr, max(dg, db)) > 10 { different += 1 }
        }
    }
    return Double(different) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
}

/// 밝은 픽셀 수(글리프가 실제로 래스터화됐는가). 이 앱은 어두운 배경 + 흰 글자라 밝기로 글자를 가른다.
/// 카드 채움(fieldFill = black 0.20)만 그려지고 글자가 빠지는 경우를 이 숫자가 가른다.
private func v0313BrightPixelCount(_ bitmap: NSBitmapImageRep, threshold: Int = 150) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
            let luma = (Int(data[o]) * 299 + Int(data[o + 1]) * 587 + Int(data[o + 2]) * 114) / 1000
            if luma >= threshold { count += 1 }
        }
    }
    return count
}

/// ImageRenderer 의 "못 그림" 표식(샛노란 상자 255,204,0)이 있는가. 있으면 그 자리는 픽셀 커버리지가 0이라
/// 무엇을 고쳐도 그림으로 확인할 수 없다(ImageRenderer 는 Menu·ScrollView 내용·TextField 를 못 그린다).
private func v0313HasUnavailablePlaceholder(_ bitmap: NSBitmapImageRep) -> Bool {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return false }
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
            if data[o] >= 240, data[o + 1] >= 195, data[o + 2] <= 40 { return true }
        }
    }
    return false
}

// MARK: - 화면별 폭·행높이 (앱의 패널이 실제로 주는 값 — 여기서 발명하지 않는다)

private enum V0313Layout {
    /// 본문 열 316 − 팀 카드 padding 12×2 = 292(PokePanel·TokenBoardPanel·LeaderboardPanel 공통).
    static let popoverRowWidth: CGFloat = 292
    /// 미니게임 창 순위 열(MiniGameWindowLayout.rankWidth = 314).
    static let miniGameRowWidth: CGFloat = MiniGameWindowLayout.rankWidth

    /// PokePanel.rowHeight / rowSpacing.
    static let pokeRowHeight: CGFloat = 48
    static let pokeRowSpacing: CGFloat = 8
    /// TokenBoardPanel.rowHeight / rowSpacing.
    static let tokenRowHeight: CGFloat = 62
    static let tokenRowSpacing: CGFloat = 8
    /// LeaderboardPanel.rowHeight / rowSpacing.
    static let leagueRowHeight: CGFloat = 58
    static let leagueRowSpacing: CGFloat = 10
    /// MiniGameWindowLayout.rowHeight / rowSpacing.
    static let miniGameRowHeight: CGFloat = MiniGameWindowLayout.rowHeight
    static let miniGameRowSpacing: CGFloat = MiniGameWindowLayout.rowSpacing
}

// MARK: - ① 콕찌르기 목록 (PokeRow · 292pt · 이름 몫 81.05pt · 축소계수 없음)

/// 근무/자리비움 배분: 최장 이름 행(0)에 **더 넓은** '자리비움' 칩(35.95pt)을 붙여 최악을 한 장에 담는다.
private let v0313PokeWorking: [Bool] = [false, true, true, false, true]

@MainActor
private func v0313PokeList() -> some View {
    VStack(spacing: V0313Layout.pokeRowSpacing) {
        ForEach(Array(V0313CenterSeed.names.enumerated()), id: \.offset) { index, name in
            // ★변형: 여기서 배지를 그린다 — PokeDirectoryEntry 에 센터 필드를 더하거나
            //        PokeDirectoryRowView 에 `center:` 인자를 더한 뒤 여기서 V0313CenterSeed.center(row: index) 를 넘긴다.
            PokeDirectoryRowView(
                entry: PokeDirectoryEntry(
                    userID: "v0313-u\(index)",
                    name: name,
                    avatarURL: nil,          // 원격 아바타는 ImageRenderer 가 못 불러온다 — 이니셜로 고정(결정적)
                    isWorking: v0313PokeWorking[index]
                ),
                cooldownRemaining: { 0 },
                canPoke: true,
                ultraBalance: 3,
                center: V0313CenterSeed.center(row: index),
                onPoke: {},
                onUltra: {},
                onOpenMessages: {},
                hasUnreadMessages: index == 1
            )
            .frame(width: V0313Layout.popoverRowWidth, height: V0313Layout.pokeRowHeight)
        }
    }
}

// MARK: - ② 토큰 순위판 (TokenBoardRowView · 292pt · 이름줄 121pt · 축소 0.75 · 캡션줄 있음)

/// 캡션줄("Claude … · Codex …")이 **반드시** 붙도록 두 종류 모두 0 이 아닌 값을 준다 —
/// 캡션이 없으면 VStack 이 한 줄로 줄어들어 이 화면의 폭 예산 자체가 달라진다(숫자 열 캡 88pt 도 안 걸린다).
/// 총합은 내림차순으로 둬서 실제 순위판처럼 읽히게 했다.
private struct V0313TokenSeed {
    let claude: Int
    let codex: Int
    let today: Int
}

private let v0313TokenSeeds: [V0313TokenSeed] = [
    .init(claude: 19_660_000_000, codex: 2_540_000, today: 184_300_000),   // "Claude 196.6억 · Codex 254만"
    .init(claude: 4_560_000_000, codex: 12_340_000, today: 51_200_000),    // "Claude 45.6억 · Codex 1,234만"
    .init(claude: 823_400_000, codex: 45_600_000, today: 7_310_000),       // 내 행 — "Claude 8.2억 · Codex 4,560만"
    .init(claude: 120_000_000, codex: 3_400_000, today: 902_000),          // "Claude 1.2억 · Codex 340만"
    .init(claude: 8_432, codex: 1_200, today: 0)                           // "Claude 8,432 · Codex 1,200"
]

@MainActor
private func v0313TokenList() -> some View {
    VStack(spacing: V0313Layout.tokenRowSpacing) {
        ForEach(Array(V0313CenterSeed.names.enumerated()), id: \.offset) { index, name in
            let seed = v0313TokenSeeds[index]
            // ★변형: 여기서 배지를 그린다 — TokenBoardEntry 에 센터 필드를 더하거나
            //        TokenBoardRowView 에 `center:` 인자를 더한 뒤 V0313CenterSeed.center(row: index) 를 넘긴다.
            TokenBoardRowView(
                entry: TokenBoardEntry(
                    userID: "v0313-u\(index)",
                    name: name,
                    avatarURL: nil,
                    total: seed.claude + seed.codex,
                    claudeInput: seed.claude,
                    claudeOutput: 0,
                    claudeCacheRead: 0,
                    claudeCacheCreation: 0,
                    codexInput: seed.codex,
                    codexOutput: 0,
                    todayTotal: seed.today,
                    todayDate: V0313CenterSeed.todayKey
                ),
                center: V0313CenterSeed.center(row: index),
                isMe: index == V0313CenterSeed.myRow,
                // 내 행에는 '비공개' 칩까지 붙인다 — '나'(19.79) + '비공개'(35.35) 가 함께 붙은 행이
                // 이 화면에서 이름 몫이 가장 좁은 자리이고(121 → 53.86pt), 배지가 더해지면 20.29pt 가 된다.
                showsPrivateChip: index == V0313CenterSeed.myRow,
                showsToday: true,
                todayKey: V0313CenterSeed.todayKey
            )
            .frame(width: V0313Layout.popoverRowWidth, height: V0313Layout.tokenRowHeight)
        }
    }
}

// MARK: - ③ 팀 리그 (LeaderboardRow · 292pt · 팀명 몫 138.78pt · 축소계수 없음)

private struct V0313TeamSeed {
    let goalHours: Int
    let members: Int
    let working: Int
    let averageHours: Double
}

/// 평균 내림차순(리그 정렬 규약과 같은 방향)으로 둔다. 2행(내 팀)이 최장 팀명 'Alpha Everyday' 다.
private let v0313TeamSeeds: [V0313TeamSeed] = [
    .init(goalHours: 40, members: 5, working: 3, averageHours: 38),
    .init(goalHours: 35, members: 4, working: 1, averageHours: 31),
    .init(goalHours: 45, members: 7, working: 4, averageHours: 26),   // 내 팀 — '우리 팀' 칩(37.84pt)
    .init(goalHours: 30, members: 3, working: 0, averageHours: 18),
    .init(goalHours: 40, members: 9, working: 2, averageHours: 7)
]

@MainActor
private func v0313LeagueList() -> some View {
    VStack(spacing: V0313Layout.leagueRowSpacing) {
        ForEach(Array(V0313CenterSeed.teams.enumerated()), id: \.offset) { index, team in
            let seed = v0313TeamSeeds[index]
            // ★변형: 여기서 배지를 그린다 — TeamLeaderboardEntry 에 센터 필드를 더하거나
            //        LeaderboardRow 에 `center:` 인자를 더한 뒤 V0313CenterSeed.center(row: index) 를 넘긴다.
            LeaderboardRow(
                entry: TeamLeaderboardEntry(
                    id: "v0313-t\(index)",
                    name: team,
                    weeklyGoalHours: seed.goalHours,
                    totalSeconds: Int(seed.averageHours * 3600) * seed.members,
                    workingCount: seed.working,
                    memberCount: seed.members
                ),
                center: V0313CenterSeed.center(row: index),
                isMyTeam: index == V0313CenterSeed.myRow
            )
            .frame(width: V0313Layout.popoverRowWidth, height: V0313Layout.leagueRowHeight)
        }
    }
}

// MARK: - ④ 미니게임 순위 (MiniGameRankRow · 314pt · 이름 몫 178pt · 축소 0.75)

private let v0313MiniGameScores: [Int] = [980, 864, 733, 610, 402]

@MainActor
private func v0313MiniGameList() -> some View {
    VStack(spacing: V0313Layout.miniGameRowSpacing) {
        ForEach(Array(V0313CenterSeed.names.enumerated()), id: \.offset) { index, name in
            // ★변형: 여기서 배지를 그린다 — MiniGameBoardEntry 에 센터 필드를 더하거나
            //        MiniGameRankRow 에 `center:` 인자를 더한 뒤 V0313CenterSeed.center(row: index) 를 넘긴다.
            MiniGameRankRow(
                rank: index + 1,
                entry: MiniGameBoardEntry(
                    userID: "v0313-u\(index)",
                    name: name,
                    avatarURL: nil,
                    bestScore: v0313MiniGameScores[index],
                    bestAt: Date(timeIntervalSince1970: 1_789_000_000 + Double(index) * 600),
                    plays: 12 - index
                ),
                center: V0313CenterSeed.center(row: index),
                isMe: index == V0313CenterSeed.myRow
            )
            .frame(width: V0313Layout.miniGameRowWidth, height: V0313Layout.miniGameRowHeight)
        }
    }
}

// MARK: - 기준선 8장 (4화면 × scale 1·2)

/// 화면 하나를 1×·2× 두 번 그려 저장하고, **그림이 비지 않았음을 픽셀로 증명**한다.
/// (빈 PNG·전부 투명·노란 상자가 나오면 하네스가 틀린 것이다 — 그때 이 단언들이 먼저 빨개진다.)
@MainActor
private func v0313CaptureBaseline(
    screen: String,
    expectedPointWidth: CGFloat,
    expectedPointHeight: CGFloat,
    list: some View
) throws {
    for scale in [CGFloat(1), CGFloat(2)] {
        let bitmap = try v0313Bitmap(list, scale: scale)

        // (1) 크기가 의도한 pt × 배율이다. scale 을 명시하지 않으면 여기서 먼저 갈린다.
        #expect(
            bitmap.pixelsWide == Int((expectedPointWidth * scale).rounded()),
            "\(screen) \(Int(scale))x 폭이 \(bitmap.pixelsWide)px 다(기대 \(Int((expectedPointWidth * scale).rounded()))px)"
        )
        #expect(
            abs(bitmap.pixelsHigh - Int((expectedPointHeight * scale).rounded())) <= Int(scale),
            "\(screen) \(Int(scale))x 높이가 \(bitmap.pixelsHigh)px 다(기대 \(Int((expectedPointHeight * scale).rounded()))px)"
        )

        // (2) 배경만 그린 같은 크기 그림과 다른 픽셀이 충분히 많다 = 행이 실제로 그려졌다.
        let blank = try v0313BlankBitmap(matching: bitmap, scale: scale)
        let ink = v0313InkRatio(bitmap, blank: blank)
        // 하한 0.08 의 근거(실측): 이 앱의 카드 채움은 `fieldFill = black 0.20` 이라 어두운 배경 위에서
        // **채움 자체가 배경과 거의 안 다르다** — 그림의 대부분은 '배경과 같은' 픽셀로 나온다.
        // 실제 기준선은 poke 15~16% · token 13~15% · league 17~19% · minigame 26~28% 였다(글자·테두리·칩·아바타).
        // 행이 아예 안 그려지면 이 값은 0 에 붙으므로, 0.08 은 '비었다'와 '그려졌다'를 충분히 가른다.
        #expect(ink > 0.08, "\(screen) \(Int(scale))x 가 거의 비어 있다(배경과 다른 픽셀 \(Int(ink * 100))%)")

        // (3) 밝은 픽셀(글자)이 있다 = 카드 채움만 그려지고 글리프가 빠진 그림이 아니다.
        let bright = v0313BrightPixelCount(bitmap)
        #expect(bright > 200, "\(screen) \(Int(scale))x 에 글자가 안 보인다(밝은 픽셀 \(bright)개)")

        // (4) '못 그림' 노란 상자가 없다 = 이 행들에 ImageRenderer 가 못 그리는 위젯이 없다.
        #expect(!v0313HasUnavailablePlaceholder(bitmap), "\(screen) \(Int(scale))x 에 노란 '못 그림' 상자가 있다")

        let saved = V0313Snapshots.save(bitmap, name: "base_\(screen)_\(Int(scale))x.png")
        #expect(saved != nil, "\(screen) \(Int(scale))x PNG 저장에 실패했다")
        // 실행 로그에 크기를 남긴다 — ls -l 만으로는 '비지 않았음'을 못 본다.
        print("[v0313] base_\(screen)_\(Int(scale))x.png \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)px ink=\(Int(ink * 100))% bright=\(bright)")
    }
}

@MainActor
@Test
func v0313BaselinePokeRows() throws {
    try v0313CaptureBaseline(
        screen: "poke",
        expectedPointWidth: V0313Layout.popoverRowWidth + 24,
        expectedPointHeight: V0313Layout.pokeRowHeight * 5 + V0313Layout.pokeRowSpacing * 4 + 24,
        list: v0313PokeList()
    )
}

@MainActor
@Test
func v0313BaselineTokenRows() throws {
    try v0313CaptureBaseline(
        screen: "token",
        expectedPointWidth: V0313Layout.popoverRowWidth + 24,
        expectedPointHeight: V0313Layout.tokenRowHeight * 5 + V0313Layout.tokenRowSpacing * 4 + 24,
        list: v0313TokenList()
    )
}

@MainActor
@Test
func v0313BaselineLeagueRows() throws {
    try v0313CaptureBaseline(
        screen: "league",
        expectedPointWidth: V0313Layout.popoverRowWidth + 24,
        expectedPointHeight: V0313Layout.leagueRowHeight * 5 + V0313Layout.leagueRowSpacing * 4 + 24,
        list: v0313LeagueList()
    )
}

@MainActor
@Test
func v0313BaselineMiniGameRows() throws {
    try v0313CaptureBaseline(
        screen: "minigame",
        expectedPointWidth: V0313Layout.miniGameRowWidth + 24,
        expectedPointHeight: V0313Layout.miniGameRowHeight * 5 + V0313Layout.miniGameRowSpacing * 4 + 24,
        list: v0313MiniGameList()
    )
}

/// 센터 배정이 **2 부산 : 3 서울** 이라는 것, 그리고 사람/팀 행에 같은 인덱스 규칙을 쓴다는 것을 못 박는다.
/// 변형 세 벌이 이 상수를 각자 손보면 세 그림이 서로 다른 데이터를 비교하게 된다 — 그 사고를 여기서 막는다.
@Test
func v0313CenterAssignmentIsTwoBusanThreeSeoul() {
    #expect(V0313CenterSeed.names.count == 5)
    #expect(V0313CenterSeed.teams.count == 5)
    #expect(V0313CenterSeed.busanRows == [0, 3])
    #expect((0..<5).filter { V0313CenterSeed.center(row: $0) == "부산" } == [0, 3])
    #expect((0..<5).filter { V0313CenterSeed.center(row: $0) == "서울" } == [1, 2, 4])
    // 실제 프로덕션 최장 별명·팀명이 들어 있어야 이 그림이 판단 근거가 된다.
    #expect(V0313CenterSeed.names.contains("천만번더들어도기분좋은말사랑해"))
    #expect(V0313CenterSeed.names.contains("맥주밤거리엠버서더"))
    #expect(V0313CenterSeed.teams.contains("Alpha Everyday"))
    #expect(V0313CenterSeed.teams.contains("버디버디에서 팀 만"))
}
