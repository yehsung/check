import CheckCore
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

/// 잔디 색축. 상세 화면이 `MeDestination.grass(_:)` 의 연관값으로 들고 다니므로 **플랫폼 무관 자리**에 둔다
/// (그리는 색 `tint` 만 iOS 층 `ContributionGrid.swift` 의 확장에 남는다). `Hashable` 은 String raw 라 자동이지만
/// `MeDestination` 이 기대는 계약이라 적어 둔다.
package enum ContributionAxis: String, CaseIterable, Hashable, Sendable {
    /// 근무(초록 — workingDot 사다리).
    case work
    /// AI 토큰(보라 — aiToken 사다리).
    case token
}

/// 잔디 칸 값: 주 × 요일(0=월…6=일)의 단계. nil = 미래(빈 테두리 칸).
package struct ContributionGridData: Equatable, Sendable {
    package let weeks: Int
    package let levels: [[Int?]]
    /// 칸의 원값(초 · 토큰). 단계만 남기면 12분과 1시간 50분이 같은 1단계로 뭉개져 상세 화면이 말할 게 없다 —
    /// 맥 `ContributionGridView` 가 values 를 그대로 쥐는 것과 같은 모양이다(CheckComponents.swift:665).
    package let values: [[Int]]
    /// 0열의 월요일 00:00(KST). 고른 칸의 날짜 원점(맥 weekStart 와 같은 뜻).
    package let weekStart: Date

    package init(weeks: Int, levels: [[Int?]], values: [[Int]] = [], weekStart: Date = .distantPast) {
        self.weeks = max(0, weeks)
        self.levels = levels
        self.values = values
        self.weekStart = weekStart
    }

    /// 원값(초·토큰) → 단계. `isFuture(주, 요일)` 이 참이면 nil(원값도 0 으로 접는다 — 미래 칸 = 0 불변식).
    ///
    /// `weekStart` 에 **기본값을 주지 않는다** — 빠뜨려도 컴파일이 통과하면 상세 화면이 조용히 '1월 1일'을 말한다.
    package init(weeks: Int, values: [[Int]], weekStart: Date, denominator: Int, isFuture: (Int, Int) -> Bool) {
        let columns = max(0, weeks)
        var grid: [[Int?]] = []
        var raw: [[Int]] = []
        for week in 0..<columns {
            var column: [Int?] = []
            var rawColumn: [Int] = []
            for weekday in 0..<ContributionGridLayout.rows {
                if isFuture(week, weekday) {
                    column.append(nil)
                    rawColumn.append(0)
                } else {
                    let value = values.indices.contains(week) && values[week].indices.contains(weekday) ? values[week][weekday] : 0
                    column.append(ContributionLevels.level(value: value, denominator: denominator))
                    rawColumn.append(value)
                }
            }
            grid.append(column)
            raw.append(rawColumn)
        }
        self.init(weeks: columns, levels: grid, values: raw, weekStart: weekStart)
    }

    /// 기록 없음·불러오는 중·실패 자리: 칸은 전부 0단계(격자 자리를 그대로 지킨다 — 섹션을 한 줄로 접지 않는다).
    /// 원값은 전부 0, 원점은 `.distantPast` — 고를 칸이 없는 자리 격자라 안전하다.
    package static func blank(weeks: Int = ContributionGridLayout.defaultWeeks) -> ContributionGridData {
        let columns = max(0, weeks)
        return ContributionGridData(
            weeks: columns,
            levels: Array(repeating: Array(repeating: 0, count: ContributionGridLayout.rows), count: columns),
            values: Array(repeating: Array(repeating: 0, count: ContributionGridLayout.rows), count: columns)
        )
    }

    package func level(week: Int, weekday: Int) -> Int? {
        guard levels.indices.contains(week), levels[week].indices.contains(weekday) else { return 0 }
        return levels[week][weekday]
    }

    /// 칸의 원값(초·토큰). 범위 밖은 0 — 형이 어긋난 배열이 와도 크래시가 없다(맥 `value(week:weekday:)` 와 같은 규약).
    package func value(week: Int, weekday: Int) -> Int {
        guard values.indices.contains(week), values[week].indices.contains(weekday) else { return 0 }
        return values[week][weekday]
    }

    /// 0단계보다 진한 칸이 하나라도 있는가.
    package var hasActivity: Bool {
        levels.contains { $0.contains { ($0 ?? 0) > 0 } }
    }
}

/// 고른 칸. 튜플이 아닌 이유는 맥과 같다 — `@State` 비교에 Equatable 이 필요하다(CheckComponents.swift:682).
package struct ContributionCell: Equatable, Hashable, Sendable {
    package let week: Int
    package let weekday: Int

    package init(week: Int, weekday: Int) {
        self.week = week
        self.weekday = weekday
    }
}

/// 잔디 상세 화면 **전치 캘린더**의 기하: 가로 7열(요일) × 세로 N행(주).
///
/// 왜 전치하나 — 홈처럼 가로 13열을 유지하면 칸이 어떤 폭에서도 애플 최소 터치 대상 44pt 에 못 닿는다(폭 329 에 13열을
/// 상한 없이 넣어도 23.0pt). 전치하면 최악(iPhone SE 375 → 격자 폭 343)에서도 피치 49.0pt 다. 손가락이 이웃 날을
/// 조용히 집어 '틀린 값을 맞다고 믿는' 결함이 이 화면에서 가장 나쁜 실패다.
package enum ContributionCalendarLayout {
    /// 가로 열 = 요일 7.
    package static let columns = ContributionGridLayout.rows
    /// 칸 사이 틈(pt). 홈(2.5)보다 넓다 — 칸이 4배 크니 틈도 따라 커져야 격자로 읽힌다.
    package static let spacing: CGFloat = 4
    /// 애플 최소 터치 대상. 테스트가 세 폭에서 이 값을 지키는지 되묻는다.
    package static let minimumPitch: CGFloat = 44

    /// 한 칸의 피치(칸 + 틈). 격자 폭을 7로 나눈다.
    package static func pitch(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return width / CGFloat(columns)
    }

    /// 보이는 칸 한 변 = 피치 − 틈. **누름 영역은 피치 전체**다(틈까지 앞 칸에 귀속 — 못 누르는 자리가 없다).
    package static func cell(width: CGFloat) -> CGFloat {
        max(0, pitch(width: width) - spacing)
    }

    /// 주 행 하나의 높이(= 피치).
    package static func rowHeight(width: CGFloat) -> CGFloat {
        pitch(width: width)
    }

    /// 주 행 로컬 좌표의 x → 요일(0=월 … 6=일). 격자 밖·음수는 nil.
    /// 피치 나눗셈이 틈을 앞 칸에 귀속시킨다(맥 `ContributionGridView.cell(at:)` 와 같은 식, 라벨 보정만 없다).
    package static func weekday(atX x: CGFloat, width: CGFloat) -> Int? {
        let pitch = pitch(width: width)
        guard pitch > 0, x >= 0, x < pitch * CGFloat(columns) else { return nil }
        return min(columns - 1, Int(x / pitch))
    }

    /// 달 단위 구간 나누기: [(달, 그 달에 속한 주 인덱스 범위)]. 주의 대표 달은 **그 주 일요일의 달**로,
    /// 맥 월 라벨(`MeText.monthLabels`)과 같은 규칙이다 — 주가 달을 걸치면 끝나는 쪽에 붙인다.
    ///
    /// 달 라벨을 행 **왼쪽**에 두면 라벨 폭만큼 피치가 줄어 44pt 밑으로 떨어진다 — 그래서 Section 머리로 올린다.
    package static func monthSections(weekStart: Date, weeks: Int) -> [ContributionMonthSection] {
        guard weeks > 0 else { return [] }
        let calendar = TeamWeeklyGoal.kstCalendar
        var sections: [ContributionMonthSection] = []
        for week in 0..<weeks {
            guard let sunday = calendar.date(
                byAdding: .day,
                value: week * ContributionGridLayout.rows + ContributionGridLayout.rows - 1,
                to: weekStart
            ) else { continue }
            let month = calendar.component(.month, from: sunday)
            if let last = sections.last, last.month == month {
                sections[sections.count - 1] = ContributionMonthSection(month: month, weeks: last.weeks.lowerBound..<(week + 1))
            } else {
                sections.append(ContributionMonthSection(month: month, weeks: week..<(week + 1)))
            }
        }
        return sections
    }
}

/// 달 구간 한 덩어리(달 · 그 달에 속한 주 인덱스 범위). 튜플이 아닌 이유: Swift 는 튜플 키패스를 만들지 못해
/// `ForEach(..., id: \.weeks.lowerBound)` 가 컴파일되지 않는다.
package struct ContributionMonthSection: Equatable, Hashable, Sendable {
    package let month: Int
    package let weeks: Range<Int>

    package init(month: Int, weeks: Range<Int>) {
        self.month = month
        self.weeks = weeks
    }
}

/// 하루 이동(상세 화면 하단 막대 ‹ ›). 미래 칸은 건너뛰지 않고 **멈춘다**(오늘이 마지막 유효 칸이다).
package enum MeGrassSelection {
    /// `cell` 에서 `days` 일 옮긴 칸. 창(0 ..< weeks×7) 밖이거나 미래(오프셋 ≥ dayCount)면 nil → 버튼 비활성.
    package static func stepped(_ cell: ContributionCell, by days: Int, weeks: Int, dayCount: Int) -> ContributionCell? {
        let rows = ContributionGridLayout.rows
        let offset = cell.week * rows + cell.weekday + days
        guard offset >= 0, offset < weeks * rows, offset < dayCount else { return nil }
        return ContributionCell(week: offset / rows, weekday: offset % rows)
    }

    /// 화면을 열 때 미리 고를 칸 = 마지막 유효 칸(오늘). `dayCount` 가 0 이면 nil.
    package static func latest(weeks: Int, dayCount: Int) -> ContributionCell? {
        let rows = ContributionGridLayout.rows
        guard weeks > 0, dayCount > 0 else { return nil }
        let offset = min(dayCount, weeks * rows) - 1
        return ContributionCell(week: offset / rows, weekday: offset % rows)
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
    /// 잔디 창 폭(주) = 이번 주 + 지난 12주. 코어 `WorkDailyGrid.defaultWeeks` 와 **반드시 같다** — 다르면 못 받았을 때(.blank)
    /// 와 받았을 때 열 수가 달라 격자 폭이 한 칸 튄다(상세 화면에선 행 수·높이가 튄다).
    package static let defaultWeeks = 13
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
        /// 잔디 상세 — 자체 하단 값 막대를 가진다(막대 둘이 쌓이면 엄지 사정권이 좁아진다).
        case grassDetail
    }
}
