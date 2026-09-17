#if os(iOS)
import CheckCore
import SwiftUI

/// 기록 절: 자리 문구 또는 (회고 카드 · 12주 근무 잔디 · 12주 AI 토큰 잔디 · 지난주 근무 리듬).
struct MeRecordsSection: View {
    let store: MeStore

    var body: some View {
        if let placeholder = store.recordsPlaceholder {
            AingCard {
                if store.recordsState.isLoading, !store.recordsState.hasLoaded {
                    LoadingRow(placeholder)
                } else {
                    HStack(spacing: 10) {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if store.recordsState.hasFailed {
                            Button {
                                Task { await store.loadRecords() }
                            } label: {
                                Label(MeText.retry, systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .tint(MobileTheme.accent)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                MeRetroCard(retro: store.retroForDisplay)
                AingCard {
                    MeGridHeader(title: MeText.workGrassTitle, systemImage: "leaf.fill", tint: MobileTheme.working)
                    MeContributionGrid(
                        weeks: store.dailyGrid.weeks,
                        values: store.dailyGrid.seconds,
                        weekStart: store.dailyGrid.weekStart,
                        isFuture: store.dailyGrid.isFuture(week:weekday:),
                        denominator: WorkDailyGrid.fullDaySeconds,
                        tint: MobileTheme.working
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(MeText.workGrassAccessibility(store.dailyGrid)))
                }
                if store.showsTokenGrid {
                    AingCard {
                        MeGridHeader(title: MeText.tokenGrassTitle, systemImage: "sparkles", tint: MobileTheme.aiToken)
                        MeContributionGrid(
                            weeks: store.tokenGrid.weeks,
                            values: store.tokenGrid.tokens,
                            weekStart: store.tokenGrid.weekStart,
                            isFuture: store.tokenGrid.isFuture(week:weekday:),
                            denominator: TokenDailyGrid.fullDayTokens,
                            tint: MobileTheme.aiToken
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(MeText.tokenGrassAccessibility(store.tokenGrid)))
                    }
                    .id(MeAnchor.tokenGrass)
                }
                AingCard {
                    MeGridHeader(title: MeText.heatmapTitle, systemImage: "square.grid.3x3.fill", tint: MobileTheme.accent, showsLegend: false)
                    MeHeatmapGrid(heatmap: store.heatmap)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text([MeText.heatmapTitle, MeText.peakLine(store.heatmap) ?? MeText.noRetro].joined(separator: ", ")))
                    if let peak = MeText.peakLine(store.heatmap) {
                        Text(peak)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// 지난주 회고 카드(맥 InsightsPanel.retroCard).
struct MeRetroCard: View {
    let retro: WeeklyRetro?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AingCard {
            // 접근성 글자 크기에서는 '목표 달성' 칩을 제목 아래 줄로 내린다(가로 그대로면 칩이 폭을 다 먹어 제목이 한 글자씩 세로로 섰다 — AX5 실측).
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    titleLabel
                    if let retro, retro.metGoal { metGoalChip }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleLabel
                    Spacer(minLength: 4)
                    if let retro, retro.metGoal { metGoalChip }
                }
            }
            if let retro {
                Text(MeText.retroTotal(retro))
                    .font(MobileTheme.number(.title2, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.primaryText)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MobileTheme.track)
                        Capsule()
                            .fill(retro.metGoal ? MobileTheme.working : MobileTheme.accent)
                            .frame(width: max(0, proxy.size.width * MeText.retroProgress(retro)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(MeText.retroGoalLine(retro))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(retro.metGoal ? MobileTheme.working : MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let delta = MeText.retroDeltaLine(retro) {
                    Text(delta)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                }
                Text(MeText.retroDetailLine(retro))
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(MeText.noRetro)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleLabel: some View {
        Label(MeText.retroTitle, systemImage: "calendar.badge.clock")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(MobileTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metGoalChip: some View {
        Label(MeText.metGoalChip, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(MobileTheme.working)
            .fixedSize()
    }
}

struct MeGridHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsLegend = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 4)
                if showsLegend { MeGridLegend(tint: tint) }
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                if showsLegend { MeGridLegend(tint: tint) }
            }
        }
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(MobileTheme.primaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "적음 ▢▢▢▢ 많음".
struct MeGridLegend: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("적음")
            ForEach(0...MeText.gridLevels, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(level == 0 ? MobileTheme.track : tint.opacity(MeText.gridOpacity(level: level)))
                    .frame(width: 10, height: 10)
            }
            Text("많음")
        }
        .font(.caption2)
        .foregroundStyle(MobileTheme.secondaryText)
        .accessibilityHidden(true)
    }
}

/// 12주 잔디(주 열 × 요일 행). 칸은 폭에 맞춰 정사각으로 늘어난다(`Grid` 가 유연한 칸에 폭을 나눠 준다).
struct MeContributionGrid: View {
    let weeks: Int
    let values: [[Int]]
    let weekStart: Date
    let isFuture: (Int, Int) -> Bool
    let denominator: Int
    let tint: Color

    private static let dayLabels = ["월", "", "수", "", "금", "", ""]

    var body: some View {
        let months = MeText.monthLabels(weekStart: weekStart, weeks: weeks)
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(0..<max(0, weeks), id: \.self) { week in
                    Text(months.indices.contains(week) ? months[week].map { "\($0)월" } ?? "" : "")
                        .font(.caption2)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 0, alignment: .leading)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
            ForEach(0..<WorkRhythmHeatmap.dayCount, id: \.self) { weekday in
                GridRow {
                    Text(Self.dayLabels[weekday])
                        .font(.caption2)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    ForEach(0..<max(0, weeks), id: \.self) { week in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(week: week, weekday: weekday))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func color(week: Int, weekday: Int) -> Color {
        if isFuture(week, weekday) { return Color.clear }
        let value = values.indices.contains(week) && values[week].indices.contains(weekday) ? values[week][weekday] : 0
        let level = MeText.gridLevel(value: value, denominator: denominator)
        return level == 0 ? MobileTheme.track : tint.opacity(MeText.gridOpacity(level: level))
    }
}

/// 지난주 근무 리듬(요일 행 × 시간 열, 파랑). 한 칸 3600초가 가장 진하다.
struct MeHeatmapGrid: View {
    let heatmap: WorkRhythmHeatmap

    private static let markedHours: Set<Int> = [0, 6, 12, 18]

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(0..<WorkRhythmHeatmap.hourCount, id: \.self) { hour in
                    Text(Self.markedHours.contains(hour) ? "\(hour)" : "")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 0, alignment: .leading)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
            ForEach(0..<WorkRhythmHeatmap.dayCount, id: \.self) { day in
                GridRow {
                    Text(MeText.dayNames[day])
                        .font(.caption2)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    ForEach(0..<WorkRhythmHeatmap.hourCount, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(day: day, hour: hour))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func color(day: Int, hour: Int) -> Color {
        let seconds = heatmap.buckets.indices.contains(day) && heatmap.buckets[day].indices.contains(hour) ? heatmap.buckets[day][hour] : 0
        let value = MeText.heatmapIntensity(seconds: seconds)
        return value > 0 ? MobileTheme.accent.opacity(0.20 + 0.80 * value) : MobileTheme.track
    }
}
#endif
