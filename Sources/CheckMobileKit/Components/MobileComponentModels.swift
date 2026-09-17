import CheckMobileShared
import CoreGraphics
import Foundation

// w15 기반 부품의 **순수 규칙**(플랫폼 무관 — macOS `swift test` 가 값으로 잰다). 그리는 쪽은 iOS 층 부품 파일들이다.

// MARK: - 루비

/// 루비 보석 크기·그림 선택. 보석은 `ruby.png` 하나(맥 원본 327px)를 세 문법(잔량 칩 · 가격 · 획득)으로 쓴다.
package enum RubyGlyph {
    /// 시안 보석 크기 단계(pt): 가격 칸 14 · 작은 칩·가격 17 · 20 · 큰 칩 24.
    package static let sizes: [CGFloat] = [14, 17, 20, 24]

    /// 그릴 픽셀 크기에 맞는 파일(확장자 뺀 이름). 축소본이 있으면 그걸 쓴다 — 327px 를 14pt 로 한 번에 줄이면 면이 뭉개진다.
    package static func assetName(pointSize: CGFloat, displayScale: CGFloat) -> String {
        let pixels = pointSize * max(displayScale, 1)
        if pixels <= 48 { return "ruby-48" }
        if pixels <= 96 { return "ruby-96" }
        return "ruby"
    }
}

/// 가격 표시 규칙.
package enum RubyPriceRule {
    /// 잔량이 가격보다 모자라면 흐리게. 잔량을 모르면(nil) 모자라다고 하지 않는다(막지 않는다 — 맥 0.3.29 규칙).
    package static func isShort(price: Int, balance: Int?) -> Bool {
        guard let balance else { return false }
        return balance < price
    }

    /// 읽기용 문장("루비 30개" · "루비 30개, 모자라요").
    package static func accessibilityText(price: Int, isShort: Bool) -> String {
        isShort ? "루비 \(price)개, 모자라요" : "루비 \(price)개"
    }
}

// MARK: - 근무 상태 · 캐릭터 표정

/// 사람 점·캐릭터 링이 말하는 근무 상태(뜻 색 한 벌).
package enum PresenceStatus: String, CaseIterable, Sendable {
    /// 근무 중(초록).
    case working
    /// 연결 끊김 · 대기(앰버).
    case pending
    /// 근무 안 함(청회색). 사람 행에서는 점을 그리지 않는다(B 규칙) — `PersonAvatar` 가 접는다.
    case off
}

/// 캐릭터 초상의 기분 = 근무 상태(맥 헤더 문법).
package enum CharacterMood: String, CaseIterable, Sendable {
    /// 근무 중 — 웃는 얼굴 + 초록 링 + 발광.
    case working
    /// 연결 끊김 — 웃는 얼굴 + 앰버 링.
    case lost
    /// 근무 안 함 — 시무룩 + 청회색 링.
    case off
    /// 상태 없음(상점 미리보기 · 고르기 타일) — 웃는 얼굴 · 링 없음 · 받침(surface2).
    case plain

    package var expression: AingCharacterArt.Expression {
        self == .off ? .negative : .neutral
    }

    /// 링 색 뜻(nil = 링 없음).
    package var ring: PresenceStatus? {
        switch self {
        case .working: return .working
        case .lost: return .pending
        case .off: return .off
        case .plain: return nil
        }
    }

    /// 위젯 스냅샷 상태 → 기분.
    package init(_ state: WidgetSnapshot.WorkState) {
        switch state {
        case .working: self = .working
        case .disconnected: self = .lost
        case .off: self = .off
        }
    }

    /// 링 두께(pt) — 시안 `max(2, 지름 × 0.04)`.
    package static func ringWidth(diameter: CGFloat) -> CGFloat {
        max(2, (diameter * 0.04).rounded(.toNearestOrEven))
    }

    /// 그림과 링 사이 틈(pt). 시안 2px.
    package static let ringGap: CGFloat = 2
}

/// 캐릭터 그림 고르기 — 192px 초상과 무대용 고해상(근무 중 표정만 있다).
package enum CharacterArtChoice: Equatable, Sendable {
    case portrait
    case stage

    /// 그릴 픽셀이 초상 원본(192px)을 넘고 **웃는 얼굴**이면 고해상 무대 그림. 시무룩은 원본이 192px 뿐이라 초상을 키운다.
    package static func choose(id: String, expression: AingCharacterArt.Expression, pointSize: CGFloat, displayScale: CGFloat) -> CharacterArtChoice {
        guard expression == .neutral, MobileArtNames.stageIDs.contains(AingCharacterArt.resolvedID(id)) else { return .portrait }
        return pointSize * max(displayScale, 1) > CGFloat(AingCharacterArt.portraitPixelSize) ? .stage : .portrait
    }
}

/// 앱 번들 그림 이름(`Resources/Art`).
package enum MobileArtNames {
    /// 무대용 고해상(420px) 근무 중 표정이 있는 캐릭터(스프라이트 5종 — 아잉 원본은 192px 뿐이다).
    package static let stageIDs: Set<String> = ["fox", "ghost", "jellyfish", "shiba", "squirrel"]
    package static func stage(id: String) -> String { "stage-\(id)-neutral" }
    /// 플래피 아잉 옆모습(192px).
    package static let flappyAing = "aing-side"
    package static let all: [String] = ["ruby", "ruby-48", "ruby-96", flappyAing] + stageIDs.sorted().map(stage(id:))

    /// 번들 안 위치(`Resources/Art/<name>.png`). 없으면 nil.
    package static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Art")
    }
}

// MARK: - 잔디

/// 잔디 농도 규칙 — 맥 `ContributionGridView.level` 과 같다(나 탭 `MeText.gridLevel` 과 테스트가 대조).
package enum ContributionLevels {
    package static let levels = 4

    /// 0 이면 0단계, 분모의 1/4 마다 한 단계(올림 나눗셈), 상한 4.
    package static func level(value: Int, denominator: Int) -> Int {
        guard value > 0 else { return 0 }
        guard denominator > 0 else { return levels }
        return min(levels, (value * levels + denominator - 1) / denominator)
    }

    /// 칸 불투명도(시안 .30 · .55 · .78 · 1). 0단계는 트랙(`fill`) 이라 0.
    package static func opacity(level: Int) -> Double {
        switch level {
        case ...0: return 0
        case 1: return 0.30
        case 2: return 0.55
        case 3: return 0.78
        default: return 1
        }
    }
}

/// 잔디 칸 값: 주 × 요일(0=월…6=일)의 단계. nil = 미래(빈 테두리 칸).
package struct ContributionGridData: Equatable, Sendable {
    package let weeks: Int
    package let levels: [[Int?]]

    package init(weeks: Int, levels: [[Int?]]) {
        self.weeks = max(0, weeks)
        self.levels = levels
    }

    /// 원값(초·토큰) → 단계. `isFuture(주, 요일)` 이 참이면 nil.
    package init(weeks: Int, values: [[Int]], denominator: Int, isFuture: (Int, Int) -> Bool) {
        let columns = max(0, weeks)
        var grid: [[Int?]] = []
        for week in 0..<columns {
            var column: [Int?] = []
            for weekday in 0..<ContributionGridLayout.rows {
                if isFuture(week, weekday) {
                    column.append(nil)
                } else {
                    let value = values.indices.contains(week) && values[week].indices.contains(weekday) ? values[week][weekday] : 0
                    column.append(ContributionLevels.level(value: value, denominator: denominator))
                }
            }
            grid.append(column)
        }
        self.init(weeks: columns, levels: grid)
    }

    /// 기록 없음·불러오는 중·실패 자리: 칸은 전부 0단계(격자 자리를 그대로 지킨다 — 섹션을 한 줄로 접지 않는다).
    package static func blank(weeks: Int = ContributionGridLayout.defaultWeeks) -> ContributionGridData {
        ContributionGridData(weeks: weeks, levels: Array(repeating: Array(repeating: 0, count: ContributionGridLayout.rows), count: max(0, weeks)))
    }

    package func level(week: Int, weekday: Int) -> Int? {
        guard levels.indices.contains(week), levels[week].indices.contains(weekday) else { return 0 }
        return levels[week][weekday]
    }

    /// 0단계보다 진한 칸이 하나라도 있는가.
    package var hasActivity: Bool {
        levels.contains { $0.contains { ($0 ?? 0) > 0 } }
    }
}

/// 잔디 상태(격자는 늘 그린다 — 아래 한 줄만 바뀐다).
package enum ContributionGridPhase: Equatable, Sendable {
    /// 값이 있다(0 칸만 있어도 받은 값이면 여기 — 문구는 `hasActivity` 로 가른다).
    case ready
    /// 불러오는 중.
    case loading
    /// 마지막 조회 실패.
    case failed

    /// 격자 아래 한 줄(nil = 없음).
    package func caption(hasActivity: Bool) -> String? {
        switch self {
        case .ready: return hasActivity ? nil : ContributionGridText.empty
        case .loading: return MobileLoadText.retrying
        case .failed: return ContributionGridText.failed
        }
    }
}

package enum ContributionGridText {
    package static let empty = "최근 12주 기록이 없어요"
    package static let failed = "기록을 불러오지 못했어요"
    package static let less = "적음"
    package static let more = "많음"
}

/// 잔디 칸 크기 — 주어진 폭에 12열이 딱 맞게. 나 탭 무대 아래 두 격자를 한 화면에 두는 계산이 여기 있다.
package enum ContributionGridLayout {
    package static let rows = 7
    package static let defaultWeeks = 12
    /// 칸 사이 틈(시안 2.5pt).
    package static let spacing: CGFloat = 2.5
    /// 칸이 이보다 크면 격자가 화면을 먹는다(세로로 쌓일 때 상한 — 나란히 둘 때 칸 약 10.8pt 와 너무 달라 보이지 않게).
    package static let maximumCell: CGFloat = 13
    /// 두 격자를 나란히 둘 때 칸이 이보다 작으면 위아래로 쌓는다.
    package static let minimumSideBySideCell: CGFloat = 8
    /// 두 격자 사이 틈.
    package static let pairSpacing: CGFloat = 16

    /// 폭 `width` 에 `columns` 열을 넣을 때의 칸 한 변(상한 `maximumCell`, 0 이상).
    package static func cellSize(width: CGFloat, columns: Int, spacing: CGFloat = spacing, maximum: CGFloat = maximumCell) -> CGFloat {
        guard columns > 0, width > 0 else { return 0 }
        let raw = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return max(0, min(maximum, raw))
    }

    /// 칸 크기에서 격자 전체 크기.
    package static func gridSize(cell: CGFloat, columns: Int, rows: Int = rows, spacing: CGFloat = spacing) -> CGSize {
        guard columns > 0, rows > 0 else { return .zero }
        return CGSize(width: cell * CGFloat(columns) + spacing * CGFloat(columns - 1),
                      height: cell * CGFloat(rows) + spacing * CGFloat(rows - 1))
    }

    /// 두 격자(근무 · 토큰)를 나란히 둘지. 큰 글자(접근성 크기)면 제목이 두 줄로 부서지니 쌓는다.
    package static func pairSideBySide(width: CGFloat, columns: Int = defaultWeeks, isAccessibilitySize: Bool) -> Bool {
        guard !isAccessibilitySize else { return false }
        let half = (width - pairSpacing) / 2
        return cellSize(width: half, columns: columns, maximum: .greatestFiniteMagnitude) >= minimumSideBySideCell
    }
}

// MARK: - 버튼

/// 버튼 3단(채움 50 · 틴트 40 · 글자 30) — 보이는 높이. 누름 영역은 늘 44 이상(작은 버튼은 투명 여백으로 채운다).
package enum AingButtonMetrics {
    package enum Size: String, CaseIterable, Sendable {
        case lg, md, sm

        /// 보이는 높이(pt, 기본 글자 크기 — 큰 글자에서는 글자를 따라 자란다).
        package var height: CGFloat {
            switch self {
            case .lg: return 50
            case .md: return 40
            case .sm: return 30
            }
        }

        package var horizontalPadding: CGFloat {
            switch self {
            case .lg: return 22
            case .md: return 18
            case .sm: return 13
            }
        }
    }

    package static let minimumTarget: CGFloat = 44
    /// 비활성 투명도(라이트). 다크는 투명도 대신 옅은 칠 + 보조 글자(시안 다크 보정 — 38% 는 2.8:1).
    package static let disabledOpacity: Double = 0.38

    /// 누름 영역 높이.
    package static func targetHeight(for size: Size) -> CGFloat {
        max(size.height, minimumTarget)
    }
}

// MARK: - 진행 막대

package enum ProgressBarRule {
    /// 0…1 로 자른다(NaN·음수 = 0).
    package static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }
}

// MARK: - 탭 막대

/// 탭 막대를 숨기는 화면(시안 B: **목록 화면에만** 탭 막대 — 자체 하단 막대·몰입 화면은 숨긴다).
/// 대화 · 오목 대국 · 상점 · 미니게임 플레이가 `.hidesTabBar(for:)`(iOS 층 `SheetChrome.swift`)를 쓴다. 규칙이 한 곳이어야 화면마다 갈리지 않는다.
package enum TabBarPolicy {
    package enum Screen: String, CaseIterable, Sendable {
        case conversation
        case gomokuMatch
        case shop
        case miniGamePlay
    }
}
