import SwiftUI
import CheckCore

// MARK: - 아잉 마작 '처음이에요' 4장 안내 (SPEC §5.7 · UX:441 보조 #14)
//
//  · 첫 연습판을 **시작할 때** 한 번: 연습 시작 시트의 [연습 시작]이 처음이면 안내 덮개를 먼저 띄우고, 마지막 장(또는 건너뛰기·바깥
//    누름)에서 '봤음'을 적은 뒤 연습판을 연다. 판이 열리기 전이라 '실전처럼 5+20' 시계가 안내를 읽는 동안 돌지 않는다
//    (스토어에 '안내 중 멈춤' 문이 없어도 된다).
//  · '봤음'은 UserDefaults 한 키(`seenKey`). 시험은 시험 전용 스위트를 넘긴다(`MahjongPanel.guideDefaults`) — 표준 스위트에 쓰지 않는다.
//  · [규칙] 창의 [처음이에요 다시 보기]로 언제든 다시 본다(그때는 연습판을 열지 않는다).
//  · 네 장 = 목표(4몸통 1머리) · 역이 하나 있어야 화료 · 버리기·울기 · 리치 — 글은 규칙 창 첫 네 줄과 한 곳(`MahjongRulesText.rules`).

/// 연습판을 열 값(형식 · '실전처럼').
struct MahjongPracticeLaunch: Equatable {
    let format: MahjongFormat
    let timed: Bool
}

enum MahjongFirstTimeGuide {
    /// '처음이에요'를 본 적이 있다(참이면 다시 저절로 띄우지 않는다).
    static let seenKey = "check.mahjong.firstTimeGuideSeen"

    struct Page: Equatable {
        let title: String
        let detail: String
        /// 예시 손(`MahjongTiles.parse` 표기). 빈 글이면 그림 없음.
        let example: String
    }

    /// 네 장 — 글은 규칙 창 첫 네 줄 그대로, 그림 없는 줄(버리기·울기 · 리치)에는 안내용 예시 손을 붙인다.
    static let pages: [Page] = {
        let rules = MahjongRulesText.rules
        let extra = ["", "", "345m777p", "123m456p789s1112z"]
        return (0..<4).map { index in
            let row = rules[index]
            return Page(title: row.title, detail: row.detail, example: row.example.isEmpty ? extra[index] : row.example)
        }
    }()

    static func hasSeen(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: seenKey) }

    static func markSeen(_ defaults: UserDefaults) { defaults.set(true, forKey: seenKey) }

    /// [연습 시작]을 눌렀다 — 처음이면 안내 덮개(끝나면 `launch` 로 연다), 아니면 nil(바로 연다).
    static func overlayBeforePractice(_ launch: MahjongPracticeLaunch, defaults: UserDefaults) -> MahjongOverlay? {
        hasSeen(defaults) ? nil : .firstTime(page: 0, launch: launch)
    }

    /// 안내를 닫는다(마지막 장 · 건너뛰기 · 바깥 누름 모두) — '봤음'을 적고, 연습 시작에서 왔으면 그 판을 연다.
    static func finish(launch: MahjongPracticeLaunch?, defaults: UserDefaults, start: (MahjongPracticeLaunch) -> Void) {
        markSeen(defaults)
        if let launch { start(launch) }
    }

    /// 덮개의 다음 장(끝이면 nil — 닫는다).
    static func next(after page: Int) -> Int? { page + 1 < pages.count ? page + 1 : nil }
}

extension MahjongText {
    static let guideNext = "다음"
    static let guidePrevious = "이전"
    static let guideSkip = "건너뛰기"
    static let guideStartPractice = "연습 시작"
    static let guideDone = "다 봤어요"
    static let guideReopen = "처음이에요 다시 보기"

    static func guidePage(_ page: Int, of count: Int) -> String { "\(page + 1)/\(count)" }
}

/// 안내 카드 한 장(덮개 가운데). 장 번호는 덮개 값(`MahjongOverlay.firstTime(page:launch:)`)이 쥔다 — 렌더 시험이 장마다 굽는다.
struct MahjongFirstTimeGuideSheet: View {
    static let size = CGSize(width: 640, height: 400)

    let page: Int
    let launch: MahjongPracticeLaunch?
    let onPage: (Int) -> Void
    let onFinish: () -> Void

    var body: some View {
        let pages = MahjongFirstTimeGuide.pages
        let index = max(0, min(pages.count - 1, page))
        let current = pages[index]
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                MahjongChip(text: MahjongText.firstTimeTitle, tint: CheckTheme.working, filled: true)
                Text(MahjongText.guidePage(index, of: pages.count))
                    .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                Spacer()
                MahjongCapsuleButton(title: MahjongText.guideSkip, tint: CheckTheme.secondaryText, filled: false, height: 28,
                                     action: onFinish)
                    .frame(width: 90)
            }
            Text(current.title).font(.title2.weight(.heavy)).foregroundStyle(CheckTheme.pending)
            Text(current.detail).font(.body).foregroundStyle(CheckTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            example(current.example)
                .frame(maxWidth: .infinity, minHeight: 60)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { dot in
                    Capsule().fill(dot == index ? CheckTheme.accent : CheckTheme.border)
                        .frame(width: dot == index ? 22 : 8, height: 8)
                }
                Spacer()
                if index > 0 {
                    MahjongCapsuleButton(title: MahjongText.guidePrevious, tint: CheckTheme.secondaryText, filled: false) {
                        onPage(index - 1)
                    }
                    .frame(width: 100)
                }
                if let next = MahjongFirstTimeGuide.next(after: index) {
                    MahjongCapsuleButton(title: MahjongText.guideNext, tint: CheckTheme.accent) { onPage(next) }
                        .frame(width: 120)
                } else {
                    MahjongCapsuleButton(title: launch == nil ? MahjongText.guideDone : MahjongText.guideStartPractice,
                                         tint: CheckTheme.working, action: onFinish)
                        .frame(width: 120)
                }
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(CheckTheme.panelElevated))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CheckTheme.working.opacity(0.6), lineWidth: 2))
    }

    @ViewBuilder
    private func example(_ text: String) -> some View {
        if let tiles = MahjongTiles.parse(text), !tiles.isEmpty {
            let size = MahjongTileSize.meld
            MahjongTileStrip(tiles: tiles.enumerated().map { MahjongStripTile(face: MahjongTileFace($1), size: size,
                                                                              origin: CGPoint(x: CGFloat($0) * size.width, y: 0)) },
                             size: CGSize(width: CGFloat(tiles.count) * size.width, height: size.height), cornerLabels: true,
                             accessibilityText: "\(MahjongText.firstTimeTitle) 예시 손 \(tiles.count)장")
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
