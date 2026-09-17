#if os(iOS)
import SwiftUI

// 12주 잔디(주 열 × 요일 7행). **기록이 없어도 늘 격자를 그린다** — 빈 격자 + "최근 12주 기록이 없어요". 불러오는 중·실패도 격자 자리를
// 지킨 채 아래 한 줄만 바뀐다(섹션을 한 줄로 접지 않는다). 칸 크기는 받은 폭에 맞춰 계산한다(`ContributionGridLayout`).

/// 잔디 색축.
package enum ContributionAxis: String, CaseIterable, Sendable {
    /// 근무(초록 — workingDot 사다리).
    case work
    /// AI 토큰(보라 — aiToken 사다리).
    case token

    var tint: Color {
        switch self {
        case .work: return MobileTheme.workingDot
        case .token: return MobileTheme.aiToken
        }
    }
}

/// 격자 그림만(제목·문구 없음). 폭을 받아 칸 크기를 정하고 높이를 스스로 말한다.
package struct ContributionGridCanvas: View {
    private let data: ContributionGridData
    private let axis: ContributionAxis
    private let dimmed: Bool

    package init(data: ContributionGridData, axis: ContributionAxis, dimmed: Bool = false) {
        self.data = data
        self.axis = axis
        self.dimmed = dimmed
    }

    package var body: some View {
        ContributionGridSizing(columns: data.weeks) {
            Canvas { context, size in
                let columns = data.weeks
                guard columns > 0 else { return }
                let cell = ContributionGridLayout.cellSize(width: size.width, columns: columns)
                let gap = ContributionGridLayout.spacing
                let radius = max(1.5, cell * 0.22)
                let track = MobileTheme.fill
                let future = MobileTheme.separator
                for week in 0..<columns {
                    for weekday in 0..<ContributionGridLayout.rows {
                        let rect = CGRect(x: CGFloat(week) * (cell + gap), y: CGFloat(weekday) * (cell + gap), width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                        guard let level = data.level(week: week, weekday: weekday) else {
                            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous), with: .color(future), lineWidth: 1)
                            continue
                        }
                        if level <= 0 || dimmed {
                            context.fill(path, with: .color(track))
                        } else {
                            context.fill(path, with: .color(axis.tint.opacity(ContributionLevels.opacity(level: level))))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 격자 크기 잡기: 제안 폭에서 칸 크기를 구해 격자 폭·높이를 돌려준다(칸 상한에 걸리면 왼쪽 정렬로 좁아진다).
private struct ContributionGridSizing: Layout {
    let columns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(columns) * 12
        let cell = ContributionGridLayout.cellSize(width: width, columns: columns)
        return ContributionGridLayout.gridSize(cell: cell, columns: columns)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// 잔디 한 벌: 제목(작게) + 격자 + 아래 한 줄(없음 · 빈 기록 · 불러오는 중 · 실패 + 다시 시도).
///
///     ContributionGrid(title: "최근 12주 근무", axis: .work, data: data, phase: .ready)
///     ContributionGrid(title: "최근 12주 AI 토큰", axis: .token, data: .blank(), phase: .failed) { retry() }
package struct ContributionGrid: View {
    private let title: String
    private let axis: ContributionAxis
    private let data: ContributionGridData
    private let phase: ContributionGridPhase
    private let accessibilitySummary: String?
    private let retry: (() -> Void)?

    /// - Parameters:
    ///   - data: 값이 없으면 `.blank()`(0 칸 12주).
    ///   - accessibilitySummary: 읽기 요약("최근 12주 근무 120시간"). nil 이면 제목 + 문구.
    package init(
        title: String,
        axis: ContributionAxis,
        data: ContributionGridData,
        phase: ContributionGridPhase = .ready,
        accessibilitySummary: String? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.title = title
        self.axis = axis
        self.data = data.weeks > 0 ? data : .blank()
        self.phase = phase
        self.accessibilitySummary = accessibilitySummary
        self.retry = retry
    }

    package var body: some View {
        let caption = phase.caption(hasActivity: data.hasActivity)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            ContributionGridCanvas(data: data, axis: axis, dimmed: phase != .ready)
                .opacity(phase == .loading ? 0.6 : 1)
            if let caption {
                captionRow(caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text([title, accessibilitySummary ?? caption].compactMap { $0 }.joined(separator: ", ")))
    }

    @ViewBuilder
    private func captionRow(_ caption: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { captionParts(caption) }
            VStack(alignment: .leading, spacing: 4) { captionParts(caption) }
        }
    }

    @ViewBuilder
    private func captionParts(_ caption: String) -> some View {
        if phase == .loading {
            ProgressView().controlSize(.mini)
        } else if phase == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(MobileTheme.pending)
                .accessibilityHidden(true)
        }
        Text(caption)
            .font(.caption)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
        if phase == .failed, let retry {
            Button(MobileLoadText.retry, action: retry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MobileTheme.accent)
                .frame(minHeight: AingButtonMetrics.minimumTarget)
                .contentShape(Rectangle())
        }
    }
}

/// 잔디 두 벌(근무 · 토큰)을 폭에 맞춰 **나란히**, 좁거나 글자가 크면 **위아래로** — 어느 쪽이든 스크롤·가로 넘김 없이 한 카드 안.
/// 토큰 잔디가 없는 사람(운영자 설정 `token_usage_collect=false`)은 `second` 에 nil.
package struct ContributionGridPair<First: View, Second: View>: View {
    private let first: First
    private let second: Second?
    @Environment(\.dynamicTypeSize) private var typeSize

    package init(@ViewBuilder first: () -> First, second: (() -> Second)?) {
        self.first = first()
        self.second = second?()
    }

    package var body: some View {
        ContributionPairLayout(isAccessibilitySize: typeSize.isAccessibilitySize, hasSecond: second != nil) {
            first
            if let second { second }
        }
    }
}

extension ContributionGridPair where Second == EmptyView {
    package init(@ViewBuilder first: () -> First) {
        self.first = first()
        self.second = nil
    }
}

private struct ContributionPairLayout: Layout {
    let isAccessibilitySize: Bool
    let hasSecond: Bool

    private func sideBySide(_ width: CGFloat) -> Bool {
        hasSecond && ContributionGridLayout.pairSideBySide(width: width, isAccessibilitySize: isAccessibilitySize)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 329
        if sideBySide(width) {
            let half = (width - ContributionGridLayout.pairSpacing) / 2
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: half, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + ContributionGridLayout.pairSpacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if sideBySide(bounds.width) {
            let half = (bounds.width - ContributionGridLayout.pairSpacing) / 2
            for (index, subview) in subviews.enumerated() {
                let x = bounds.minX + CGFloat(index) * (half + ContributionGridLayout.pairSpacing)
                subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: half, height: nil))
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: nil))
            y += size.height + ContributionGridLayout.pairSpacing
        }
    }
}

/// "적음 ▢▢▢▢ 많음" 범례(선택).
package struct ContributionLegend: View {
    private let axis: ContributionAxis

    package init(axis: ContributionAxis) {
        self.axis = axis
    }

    package var body: some View {
        HStack(spacing: 3) {
            Text(ContributionGridText.less)
            ForEach(0...ContributionLevels.levels, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(level == 0 ? MobileTheme.fill : axis.tint.opacity(ContributionLevels.opacity(level: level)))
                    .frame(width: 9, height: 9)
            }
            Text(ContributionGridText.more)
        }
        .font(.caption2)
        .foregroundStyle(MobileTheme.label2)
        .accessibilityHidden(true)
    }
}
#endif
