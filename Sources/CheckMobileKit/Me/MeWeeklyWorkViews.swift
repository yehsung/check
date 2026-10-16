#if os(iOS)
import CheckCore
import SwiftUI

/// 「이번 주 근무」 카드(v0.3.55 · 폰 1.0.8(19)) — 무대(루비 칩) 바로 아래. 이번 주 누적 · 다음 칸까지 막대 · 세 칸 칩 · 규칙 한 줄.
///
/// 값은 전부 서버(`weekly_work_status()`)가 준 것이다 — 칸 시간·루비를 박지 않는다(`MeWeeklyWork.swift`). 서버에 함수가 없으면
/// 카드가 통째로 빠진다(`store.showsWeeklyWork`). 새로 받은 칸이 있으면 머리 오른쪽에 초록 '+N 받음' 칩이 서고 성공 햅틱이 한 번 운다
/// (`weeklyGrantSerial` — 나 탭에서 들어온 지급만 울린다. 탭이 안 보일 때 들어온 것은 칩만 남아 다음에 열 때 보인다).
struct MeWeeklyWorkCard: View {
    let store: MeStore

    var body: some View {
        if store.showsWeeklyWork {
            card
                .sensoryFeedback(.success, trigger: store.weeklyGrantSerial)
        }
    }

    private var card: some View {
        let status = store.weeklyWork
        return VStack(alignment: .leading, spacing: MobileTheme.space2) {
            header(status)
            if let status {
                ProgressBar(WeeklyWorkRules.progress(status), style: WeeklyWorkRules.allClaimed(status) ? .done : .accent)
                    .padding(.vertical, 2)
                nextLine(status)
                tierChips(status)
            } else {
                Text(store.weeklyWorkState.hasFailed ? MeText.weeklyLoadFailed : MeText.loading)
                    .font(.footnote)
                    .foregroundStyle(store.weeklyWorkState.hasFailed ? MobileTheme.pending : MobileTheme.label2)
            }
            Text(MeText.weeklyRule)
                .font(.caption)
                .foregroundStyle(MobileTheme.label3Text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
    }

    /// "이번 주 근무 · 23시간 12분" + (방금 받았으면) '+N 받음'. 큰 글자에서는 숫자를 아래 줄로.
    @ViewBuilder
    private func header(_ status: WeeklyWorkStatusDTO?) -> some View {
        let title = Text(MeText.weeklyTitle)
            .font(.headline)
            .foregroundStyle(MobileTheme.label)
            .accessibilityAddTraits(.isHeader)
        let hours = status.map { Text(MeText.weeklyHours($0.workedSeconds)) }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                title.lineLimit(1)
                if let hours {
                    hours
                        .font(MobileTheme.number(.headline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                }
                Spacer(minLength: MobileTheme.space1)
                grantChip
            }
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                title.fixedSize(horizontal: false, vertical: true)
                if let hours {
                    hours
                        .font(MobileTheme.number(.headline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                }
                grantChip
            }
        }
    }

    @ViewBuilder
    private var grantChip: some View {
        if let notice = store.weeklyGrantNotice {
            RubyGain(notice.ruby, suffix: MeText.weeklyGrantSuffix, style: .chip)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// 다음 칸 한 줄: "40시간 되면 💎+50" · 넘었는데 아직이면 "40시간 채웠어요 · 곧 들어와요" · 다 받았으면 "이번 주 보상 다 받았어요 💎+270".
    @ViewBuilder
    private func nextLine(_ status: WeeklyWorkStatusDTO) -> some View {
        if WeeklyWorkRules.allClaimed(status) {
            let total = WeeklyWorkRules.totalRuby(status)
            gemLine(lead: MeText.weeklyAllDone, ruby: total, tint: MobileTheme.working)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(MeText.weeklyAllDoneAccessibility(totalRuby: total)))
        } else if let next = WeeklyWorkRules.nextTier(status) {
            if WeeklyWorkRules.isNextTierPending(status) {
                Text(MeText.weeklyPending(hours: next.hours))
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                gemLine(lead: MeText.weeklyNextLead(hours: next.hours), ruby: next.ruby, tint: MobileTheme.label)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(MeText.weeklyNextAccessibility(hours: next.hours, ruby: next.ruby)))
            }
        }
    }

    private func gemLine(lead: String, ruby: Int, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(lead)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                RubyIcon(size: 14)
                Text(MeText.weeklyRubyGain(ruby))
                    .font(.system(.subheadline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .fixedSize()
        }
    }

    /// 세 칸 칩 — 칩은 **제 글자만큼** 넓고 사이 틈이 줄을 채운다. 같은 폭으로 나누면 체크가 붙은 받은 칩만 글자가 잘렸다
    /// ("20…" — 시뮬레이터 실측). 한 줄에 안 들어가면(큰 글자 · 좁은 기기) 세로로 쌓는다.
    @ViewBuilder
    private func tierChips(_ status: WeeklyWorkStatusDTO) -> some View {
        let tiers = WeeklyWorkRules.sortedTiers(status)
        if !tiers.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(tiers.enumerated()), id: \.element.hours) { index, tier in
                        if index > 0 { Spacer(minLength: MobileTheme.space2) }
                        MeWeeklyTierChip(tier: tier)
                    }
                }
                VStack(alignment: .leading, spacing: MobileTheme.space1) {
                    ForEach(tiers, id: \.hours) { MeWeeklyTierChip(tier: $0) }
                }
            }
        }
    }
}

/// 칸 칩 하나 "20시간 💎20". 받았으면 체크 + 초록 바탕(초록은 '받음'에만), 아직이면 회색 바탕. 글자는 잘리지 않는다(`fixedSize`).
private struct MeWeeklyTierChip: View {
    let tier: WeeklyWorkStatusDTO.Tier

    var body: some View {
        HStack(spacing: 3) {
            if tier.claimed {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(MobileTheme.working)
            }
            Text(MeText.weeklyTierHours(tier.hours))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tier.claimed ? MobileTheme.working : MobileTheme.label2)
                .lineLimit(1)
            RubyIcon(size: 14)
                .opacity(tier.claimed ? 1 : 0.75)
            Text("\(tier.ruby)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tier.claimed ? MobileTheme.working : MobileTheme.label2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Capsule().fill(tier.claimed ? MobileTheme.workingTint : MobileTheme.fill))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MeText.weeklyTierAccessibility(hours: tier.hours, ruby: tier.ruby, claimed: tier.claimed)))
    }
}
#endif
