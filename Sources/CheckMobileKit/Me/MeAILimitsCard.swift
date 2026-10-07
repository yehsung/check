#if os(iOS)
import CheckCore
import SwiftUI

// MARK: - 나 탭 「AI 리밋」 카드 (v0.3.45)
//
// 카드 경계 = **시간 범위 하나**라는 이 탭의 규칙(MeRecordsViews 머리말)에 리밋은 들어맞지 않는다 — 5시간 창과
// 주간 창이 한 제공자 안에 같이 있다. 그래서 범위가 아니라 **축**으로 카드를 가른다: 이 카드는 "지금 내 AI 한도"
// 하나를 말하고, 아래 토큰 줄은 같은 도구의 **다른 축**(우리가 센 누적)이라 구분선 밑에 둔다. 두 축을 한 바에
// 섞지 않는 것이 이 카드의 가장 중요한 규칙이다(`AILimits.swift` 머리말).
//
// 그리는 값은 **전부** `AILimitsStore.displayRows`(코어 규칙이 만든 `AILimitDisplay`)에서 온다. 이 파일은
// 퍼센트를 다시 반올림하지도, 나이를 다시 세지도, "이상" 을 붙이지도 않는다 — 그 순간 규칙이 둘이 되고, 뷰만
// 고친 화면은 스토어 테스트가 초록인 채 거짓을 그린다.
//
// 숨기기 규칙(2026-10-07 사용자 결정): 미연동 제공자는 줄을 만들지 않고, 하나도 없으면 안내 한 줄만 둔다.
// 설정 토글도 알림도 없다 — 사용자가 맥에서 그 도구에 로그인하면 저절로 나타난다.

/// 「AI 리밋」 카드. 제공자당 5시간 굵은 바 + 주간 얇은 바, 그 아래 기존 토큰 사용량.
struct MeAILimitsCard: View {
    let store: MeStore

    private var limits: AILimitsStore { store.aiLimits }

    var body: some View {
        let rows = limits.displayRows
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            header(summary: limits.fiveHourSummary)
            if rows.isEmpty {
                emptyLine
            } else {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    ForEach(rows) { row in
                        MeAILimitRow(row: row)
                    }
                }
                Text(MeText.aiLimitsCaption)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tokenBlock
        }
        .padding(MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
    }

    /// 제목 + 요약 칩. 요약은 **5시간 창만** 모은다(지금 막힐 위험을 말하는 자리다 — 주간은 줄마다 얇은 바가 말한다).
    /// 큰 글자에서 한 줄에 안 들어가면 칩을 아래로 내린다(말줄임 금지 — 이 탭의 다른 카드와 같은 갈래).
    private func header(summary: AILimitDisplay?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MobileTheme.space2) {
                titleText
                Spacer(minLength: MobileTheme.space1)
                if let summary { summaryChip(summary) }
            }
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                titleText
                if let summary { summaryChip(summary) }
            }
        }
    }

    private var titleText: some View {
        Text(MeText.aiLimitsTitle)
            .font(.headline)
            .foregroundStyle(MobileTheme.label)
            .accessibilityAddTraits(.isHeader)
    }

    /// 요약 칩은 **뜻 색을 쓰지 않는다**(이 탭 규칙: 색은 뜻으로만, 리밋은 경고가 아니다). 숫자는 규칙이 만든 글자 그대로.
    private func summaryChip(_ summary: AILimitDisplay) -> some View {
        AingChip(text: summary.valueText, tint: MobileTheme.label2, background: MobileTheme.fill)
            .accessibilityLabel(Text("\(MeText.aiLimitsTitle) \(summary.valueText), \(summary.captionText)"))
    }

    /// 아직 그릴 줄이 없다: 불러오는 중 · 실패 · 연동한 도구 없음. **셋을 섞지 않는다** —
    /// "연동 없음"을 실패로 말하면 맥을 안 쓰는 사용자에게 고장으로 읽힌다.
    @ViewBuilder
    private var emptyLine: some View {
        if limits.state.hasLoaded {
            Text(MeText.aiLimitsNoProviders)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        } else if limits.state.hasFailed {
            LoadFailureRow(MeText.aiLimitsFailed, isRetrying: limits.state.isLoading) {
                Task { await limits.load() }
            }
        } else {
            Text(MeText.aiLimitsLoading)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
        }
    }

    /// 기존 토큰 사용량(다른 축). 모르면(수집 꺼짐 · 아직 못 받음) **줄을 만들지 않는다** — 0 은 "안 썼다"는 거짓이다.
    @ViewBuilder
    private var tokenBlock: some View {
        let totals = limits.phoneTokenTotals()
        if let today = totals.today {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MeText.aiTokenTodayTitle)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Text(MeText.aiTokenValue(today))
                        .font(MobileTheme.number(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                }
                Spacer(minLength: MobileTheme.space2)
                if let recent = totals.recent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(MeText.aiTokenRecentTitle)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                        Text(MeText.aiTokenCompact(recent))
                            .font(MobileTheme.number(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
    }
}

/// 제공자 한 줄: [로고 타일] 이름 · 리셋 캡션 … 27% / 굵은 5시간 바 / 얇은 주간 바.
///
/// ★ 타일 옆에 **이름 글자가 반드시 있다**. 색만으로 제공자를 가르면 위젯 틴트 모드(색을 통째로 버린다)에서
/// 세 줄이 똑같아진다 — 폰 카드에는 틴트 모드가 없지만 색각 이상·흑백 스크린샷에서 같은 일이 생긴다.
private struct MeAILimitRow: View {
    let row: AILimitDisplayRow
    @Environment(\.dynamicTypeSize) private var typeSize

    /// ★ 머리 줄은 **대표 창**을 세운다 — `fiveHour` 를 무조건 머리로 쓰지 않는다(v0.3.45 P2).
    ///
    /// 5시간 창이 아예 없는 계정(주간만 오는 요금제 · 안티그래비티 실측)에서 초안은 `headLine(nil)` 을 불러
    /// 값·캡션을 **둘 다 건너뛰었다**. 같은 데이터로 맥은 `42% · 주간`, 위젯도 `42% · 주간` 을 세웠다 —
    /// 세 화면이 다른 말을 했다. 고르는 규칙은 뷰가 아니라 `AILimitDisplayRow.primaryWindow` 에 있다
    /// (이 뷰는 `#if os(iOS)` 라 맥 스위트가 한 줄도 재지 못한다 — 규칙이 뷰 안에 있으면 그물이 없다).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let primary = row.primaryWindow {
                headLine(primary)
                ProgressBar(fraction(primary.display), style: .ai, floorOnly: primary.display.floorOnly)
                    .accessibilityHidden(true)
            }
            // 주간이 이미 대표로 섰으면 같은 값을 두 번 그리지 않는다.
            if let weekly = row.secondaryWeekly {
                weeklyLine(weekly)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }

    /// 머리 줄: 타일 + 이름(+ 플랜) + 캡션 … [창 라벨] 값. 큰 글자에서는 캡션을 값 아래로 내리지 않고 **캡션을 뺀다**
    /// (캡션은 값의 신뢰도이고, 값과 이름이 먼저다 — 말줄임보다 조각 빼기가 이 저장소 규칙이다).
    private func headLine(_ primary: (display: AILimitDisplay, label: String)) -> some View {
        ViewThatFits(in: .horizontal) {
            headRow(primary, showsCaption: true)
            headRow(primary, showsCaption: false)
        }
    }

    private func headRow(_ primary: (display: AILimitDisplay, label: String), showsCaption: Bool) -> some View {
        HStack(alignment: .center, spacing: MobileTheme.space2) {
            AIProviderTile(provider: row.provider, size: tileSize)
            Text(nameText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .fixedSize(horizontal: showsCaption, vertical: false)
            if showsCaption {
                Text(primary.display.captionText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label3Text)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: MobileTheme.space1)
            // ★ 창 라벨은 **빼지 않는다**. 대표 창이 줄마다 다를 수 있어서(5시간 창이 없는 요금제가 있다)
            //   라벨 없이 숫자만 세우면 이 줄의 주간 42% 가 위 줄의 5시간 27% 와 같은 창으로 읽힌다.
            Text(primary.label)
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(1)
                .fixedSize()
            Text(primary.display.valueText)
                .font(MobileTheme.number(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// 주간은 **얇은 줄** 하나로(5시간이 크게, 주간이 얇게 — 2026-10-07 사용자 결정). 라벨·값은 작은 글자다.
    private func weeklyLine(_ display: AILimitDisplay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space1) {
                Text(AILimitWindow.weekly.displayName)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                Spacer(minLength: MobileTheme.space1)
                Text(display.valueText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            }
            ProgressBar(fraction(display), style: .ai, thin: true, floorOnly: display.floorOnly)
                .accessibilityHidden(true)
        }
        .padding(.leading, typeSize.isAccessibilitySize ? 0 : tileSize + MobileTheme.space2)
    }

    /// 타일 크기는 글자 크기를 따라간다(고정 pt 면 XXXL 에서 로고만 안 자란다).
    private var tileSize: CGFloat { typeSize.isAccessibilitySize ? 28 : 22 }

    /// 이름 + 플랜 라벨("Claude · max"). 플랜을 모르면 이름만.
    private var nameText: String {
        guard let plan = row.planLabel else { return row.provider.displayName }
        return "\(row.provider.displayName) · \(plan)"
    }

    /// 바 채우기 0…1. `percent` 가 nil(판정 불가)이면 **0 으로 그리지 않고** 빈 트랙만 남는다 —
    /// 0% 는 "안 썼다"는 단정이다(규칙이 값 글자를 `—` 로 주는 것과 같은 이유).
    private func fraction(_ display: AILimitDisplay) -> Double {
        guard let percent = display.percent else { return 0 }
        return percent / 100
    }

    /// 보이스오버: 창마다 한 문장(값 + 나이). 바는 숨기고 이 라벨 하나가 줄 전체를 말한다.
    private var label: String {
        row.visibleWindows
            .map { MeText.aiLimitAccessibility(provider: row.provider, display: $0) }
            .joined(separator: ", ")
    }
}
#endif
