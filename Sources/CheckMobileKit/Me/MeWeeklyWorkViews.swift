#if os(iOS)
import CheckCore
import SwiftUI

/// 「이번 주 근무」 카드(v0.3.55 · 폰 1.0.8(19)) — 무대(루비 칩) 바로 아래.
///
/// 게이지는 **지금 퀘스트 하나**다(CheckCore `WeeklyWorkGauge` — 맥 줄과 한 벌 · 사장님 늦은 변경 2026-10-16):
/// 제목 "이번 주 근무 · 40시간 달성하기" → 값 "23시간 12분 / 40시간" + 보상 보석 "+50" → 막대(이번 주 누적 ÷ 퀘스트 시간) →
/// 세 칸 칩(받은 칸 = 체크 + 초록, 보조) → 규칙 한 줄. 마지막 칸을 넘으면 "이번 주 근무 완료" · 초록으로 가득 찬 막대 ·
/// "+N 받았어요"(장부에 들어간 합만)로 바뀌고 다음 목표는 없다.
///
/// 값은 전부 서버(`weekly_work_status()`)가 준 것이다 — 칸 시간·루비를 박지 않는다. 서버에 함수가 없으면 카드가 통째로 빠진다
/// (`store.showsWeeklyWork`). 새로 받은 칸이 있으면 머리 오른쪽에 초록 '+N 받음' 칩이 서고 성공 햅틱이 한 번 운다
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
        let gauge = status?.gauge
        return VStack(alignment: .leading, spacing: MobileTheme.space2) {
            header(gauge)
            if let status, let gauge {
                valueLine(status, gauge)
                ProgressBar(gauge.fill, style: gauge.isComplete ? .done : .accent)
                    .padding(.vertical, 2)
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

    /// 제목(지금 퀘스트 · 완료) + (방금 받았으면) '+N 받음'. 큰 글자에서는 칩을 아래 줄로.
    @ViewBuilder
    private func header(_ gauge: WeeklyWorkGauge?) -> some View {
        let title = Text(MeText.weeklyHeadline(gauge))
            .font(.headline)
            .foregroundStyle(MobileTheme.label)
            .accessibilityAddTraits(.isHeader)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                title.lineLimit(1)
                Spacer(minLength: MobileTheme.space1)
                grantChip
            }
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                title.fixedSize(horizontal: false, vertical: true)
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

    /// 값 한 줄: 진행 중 "23시간 12분 / 40시간" + 보석 "+50", 완료 "61시간 03분" + 보석 "+270 받았어요"(장부 합 · 0 이면 보석 없음).
    @ViewBuilder
    private func valueLine(_ status: WeeklyWorkStatus, _ gauge: WeeklyWorkGauge) -> some View {
        let value = Text(MeText.weeklyGaugeValue(worked: status.displayWorkedSeconds, gauge: gauge))
            .font(MobileTheme.number(.headline, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
        let gem = MeText.weeklyGaugeGem(gauge)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MobileTheme.space2) {
                value.lineLimit(1)
                Spacer(minLength: MobileTheme.space1)
                if let gem { gemLabel(gem, done: gauge.isComplete) }
            }
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                value.fixedSize(horizontal: false, vertical: true)
                if let gem { gemLabel(gem, done: gauge.isComplete) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MeText.weeklyGaugeAccessibility(worked: status.displayWorkedSeconds, gauge: gauge)))
    }

    private func gemLabel(_ text: String, done: Bool) -> some View {
        HStack(spacing: 2) {
            RubyIcon(size: 14)
            Text(text)
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(done ? MobileTheme.working : MobileTheme.label)
        }
        .fixedSize()
    }

    /// 세 칸 칩(보조 — 게이지가 주인공이다) — 칩은 **제 글자만큼** 넓고 사이 틈이 줄을 채운다. 같은 폭으로 나누면 체크가 붙은
    /// 받은 칩만 글자가 잘렸다("20…" — 시뮬레이터 실측). 한 줄에 안 들어가면(큰 글자 · 좁은 기기) 세로로 쌓는다.
    @ViewBuilder
    private func tierChips(_ status: WeeklyWorkStatus) -> some View {
        let tiers = status.tiers
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
    let tier: WeeklyWorkStatus.Tier

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
