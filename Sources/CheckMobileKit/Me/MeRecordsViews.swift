#if os(iOS)
import CheckCore
import SwiftUI

// 기록(w15 재디자인): 회고 한 줄 + 12주 근무 잔디 · 12주 AI 토큰 잔디(한 카드 안, 나란히 — 좁거나 글자가 크면 위아래) + 지난주 근무 리듬.
// **기록이 없어도 격자를 그린다**(빈 칸 + "최근 12주 기록이 없어요"). 불러오는 중 · 실패도 격자 자리를 지키고 아래 한 줄만 바뀐다 —
// 예전 `recordsPlaceholder` 처럼 절 전체를 한 줄로 접지 않는다. 토큰 잔디는 수집을 끈 사람(`showsTokenGrid == false`)만 뺀다(안내 없음).

/// 잔디 두 벌의 상태: 한 번 받았으면 값(0 칸이면 빈 기록 문구), 못 받았으면 마지막 조회가 실패했는가로 실패 · 불러오는 중.
enum MeRecordsPhase {
    static func phase(_ state: MeLoadState) -> ContributionGridPhase {
        if state.hasLoaded { return .ready }
        return state.hasFailed ? .failed : .loading
    }
}

/// 기록 카드(시안 A 09 · B 10): "지난주 회고 [목표 달성]" · 큰 숫자 · 보조 한 줄 · 잔디 두 벌.
struct MeRecordsCard: View {
    let store: MeStore

    var body: some View {
        let state = store.recordsState
        let phase = MeRecordsPhase.phase(state)
        let retro = state.hasLoaded ? store.retroForDisplay : nil
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            retroBlock(retro: retro, loaded: state.hasLoaded)
            grids(phase: phase)
        }
        .padding(MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
    }

    @ViewBuilder
    private func retroBlock(retro: WeeklyRetro?, loaded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: MobileTheme.space2) {
                    titleText
                    Spacer(minLength: MobileTheme.space1)
                    if let retro { chip(retro) }
                }
                VStack(alignment: .leading, spacing: MobileTheme.space1) {
                    titleText
                    if let retro { chip(retro) }
                }
            }
            if let retro {
                Text(MeText.retroHeadline(retro))
                    .font(MobileTheme.number(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text(MeText.retroSummaryLine(retro))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loaded {
                Text(MeText.noRetro)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(MeText.retroTitle)
            .font(.headline)
            .foregroundStyle(MobileTheme.label)
            .accessibilityAddTraits(.isHeader)
    }

    private func chip(_ retro: WeeklyRetro) -> some View {
        retro.metGoal
            ? AingChip(text: MeText.retroChip(retro), tint: MobileTheme.working)
            : AingChip(text: MeText.retroChip(retro), tint: MobileTheme.label2, background: MobileTheme.fill)
    }

    @ViewBuilder
    private func grids(phase: ContributionGridPhase) -> some View {
        let loaded = store.recordsState.hasLoaded
        let retry: () -> Void = { Task { await store.loadRecords() } }
        let workData = loaded
            ? ContributionGridData(weeks: store.dailyGrid.weeks, values: store.dailyGrid.seconds,
                                   denominator: WorkDailyGrid.fullDaySeconds, isFuture: store.dailyGrid.isFuture(week:weekday:))
            : .blank()
        let work = ContributionGrid(
            title: MeText.workGrassTitle, axis: .work, data: workData, phase: phase,
            accessibilitySummary: loaded ? MeText.workGrassAccessibility(store.dailyGrid) : nil,
            retry: retry
        )
        if store.showsTokenGrid {
            let tokenData = loaded
                ? ContributionGridData(weeks: store.tokenGrid.weeks, values: store.tokenGrid.tokens,
                                       denominator: TokenDailyGrid.fullDayTokens, isFuture: store.tokenGrid.isFuture(week:weekday:))
                : .blank()
            ContributionGridPair {
                work
            } second: {
                // 실패 · 불러오는 중 문구는 두 격자에 같이 서지만 [다시 시도]는 한 번만(같은 조회다).
                ContributionGrid(
                    title: MeText.tokenGrassTitle, axis: .token, data: tokenData, phase: phase,
                    accessibilitySummary: loaded ? MeText.tokenGrassAccessibility(store.tokenGrid) : nil
                )
            }
            .id(MeAnchor.tokenGrass)
        } else {
            ContributionGridPair {
                work
            }
        }
    }
}

// MARK: - 근무 리듬

/// 지난주 근무 리듬(요일 × 시간). 근무 데이터라 잔디와 같은 **초록 사다리**(예전엔 파랑 — 같은 뜻을 두 색으로 그렸다, w14 비평 25).
/// 기록이 없어도 격자 자리는 지킨다.
struct MeRhythmCard: View {
    let store: MeStore

    var body: some View {
        let state = store.recordsState
        let phase = MeRecordsPhase.phase(state)
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            Text(MeText.heatmapTitle)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
                .accessibilityAddTraits(.isHeader)
            MeRhythmGrid(heatmap: state.hasLoaded ? store.heatmap : .empty, dimmed: phase != .ready)
                .opacity(phase == .loading ? 0.6 : 1)
                .accessibilityHidden(true)
            Text(caption(phase: phase))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }

    private func caption(phase: ContributionGridPhase) -> String {
        switch phase {
        case .ready: return MeText.rhythmCaption(store.heatmap)
        case .loading: return MeText.loading
        case .failed: return MeText.recordsFailed
        }
    }
}

/// 요일 행 × 24시간 열. 칸은 받은 폭에 맞춰 계산해 한 장의 캔버스로 그린다(168칸을 뷰로 만들지 않는다).
struct MeRhythmGrid: View {
    let heatmap: WorkRhythmHeatmap
    var dimmed = false
    /// 요일 글자 칸 폭(글자 크기를 따라 커진다).
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var hourLabelHeight: CGFloat = 15

    var body: some View {
        MeRhythmSizing(labelWidth: labelWidth, hourLabelHeight: hourLabelHeight) {
            Canvas { context, size in
                let cell = MeRhythmMetrics.cellSize(width: size.width, labelWidth: labelWidth)
                let gap = MeRhythmMetrics.gap
                let top = hourLabelHeight
                for hour in MeRhythmMetrics.markedHours {
                    let text = context.resolve(Text("\(hour)").font(.caption2).monospacedDigit().foregroundStyle(MobileTheme.label2))
                    context.draw(text, at: CGPoint(x: labelWidth + CGFloat(hour) * (cell + gap), y: 0), anchor: .topLeading)
                }
                let track = MobileTheme.fill
                for day in 0..<WorkRhythmHeatmap.dayCount {
                    let y = top + CGFloat(day) * (cell + gap)
                    if day % 2 == 0 {
                        let label = context.resolve(Text(MeText.dayNames[day]).font(.caption2).foregroundStyle(MobileTheme.label2))
                        context.draw(label, at: CGPoint(x: 0, y: y + cell / 2), anchor: .leading)
                    }
                    for hour in 0..<WorkRhythmHeatmap.hourCount {
                        let rect = CGRect(x: labelWidth + CGFloat(hour) * (cell + gap), y: y, width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: max(1.5, cell * 0.22), style: .continuous)
                        let seconds = heatmap.buckets.indices.contains(day) && heatmap.buckets[day].indices.contains(hour) ? heatmap.buckets[day][hour] : 0
                        let level = MeText.rhythmLevel(seconds: seconds)
                        if level == 0 || dimmed {
                            context.fill(path, with: .color(track))
                        } else {
                            context.fill(path, with: .color(ContributionAxis.work.tint.opacity(ContributionLevels.opacity(level: level))))
                        }
                    }
                }
            }
        }
    }
}

enum MeRhythmMetrics {
    static let markedHours: [Int] = [0, 6, 12, 18]
    static let gap: CGFloat = 2
    /// 칸 상한(잔디 상한 13 과 비슷하게 — 넓은 기기에서 격자가 화면을 먹지 않게).
    static let maximumCell: CGFloat = 13

    static func cellSize(width: CGFloat, labelWidth: CGFloat) -> CGFloat {
        let columns = CGFloat(WorkRhythmHeatmap.hourCount)
        let available = width - labelWidth - gap * (columns - 1)
        return max(3, min(maximumCell, available / columns))
    }

    static func height(width: CGFloat, labelWidth: CGFloat, hourLabelHeight: CGFloat) -> CGFloat {
        let rows = CGFloat(WorkRhythmHeatmap.dayCount)
        let cell = cellSize(width: width, labelWidth: labelWidth)
        return hourLabelHeight + cell * rows + gap * (rows - 1)
    }
}

/// 폭을 받아 격자 높이를 말한다(캔버스는 제안 크기를 다 먹으므로 높이를 여기서 정한다).
private struct MeRhythmSizing: Layout {
    let labelWidth: CGFloat
    let hourLabelHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 329
        return CGSize(width: width, height: MeRhythmMetrics.height(width: width, labelWidth: labelWidth, hourLabelHeight: hourLabelHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}
#endif
