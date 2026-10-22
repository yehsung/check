#if os(iOS)
import CheckCore
import SwiftUI

// MARK: - 「도전 미션」 절 · [받기] 버튼 · 받기 연출 (폰 1.0.9 — 맥 0.3.58 `CheckAchievementRows.swift` 미러)
//
// 사장님 확정(2026-10-19, 원문): "미션에서 바로 받는게 아니라. 달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 해줘. 그래야
// 루비를 받는 재미가 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고. 3시간마다 루비 3개씩
// 주는것만 따로 버튼 없이 자동으로 지급되는걸로 냅두면 돼"
//
// 이 파일은 **그림만** 그린다. 제목 · 보조 문장 · 보상 · 목표 · 순서 · 받을 수는 전부 스토어가 서버 응답에서 내놓은 값이고
// (`MeStore.achievementSection` · `achievementRows` · `achievementClaimableCount` · `achievementClaimableRuby`),
// 판정도 전부 스토어다(`isClaimingAchievement` · `achievementClaimDidFail` · `claimBurst(series:)`). 그래서 이 파일에
// 미션 제목도, 50 · 20 · 10 같은 보상 숫자도 한 줄 없다 — 서버가 미션을 더해도 앱을 다시 낼 필요가 없게.
//
// ── 맥과 같은 규약 ──
//  · 절 자리: 「이번 주 근무」 카드 **바로 아래** · 「지난주」 기록 **위**(맥 [미션] 화면도 주간 게이지 → 도전 미션 순서다).
//  · 줄은 **계열마다 하나**(코어 `seriesRows`) — 받을 수 있는 단계를 위 단계가 가리지 않는다.
//  · 받기 **실패는 그 줄 안**에서 말한다(`MeText.claimFailed`). 토스트 · 알림창 · 절 위 안내줄은 쓰지 않는다
//    (맥이 검토에서 버린 방식 — 안내줄은 줄을 밀고, 아래쪽 줄을 누른 사람에겐 스크롤 밖이었다). [받기]는 그대로 남아
//    **다시 누르는 것이 재시도**다.
//  · 불러오는 중 · 실패에도 **자리를 지킨다**(`MeAchievementLayout.reserves` — 맥 `reservesViewport` 와 같은 처방).
//    맥은 첫 열기에 팝오버가 100pt 자랐다(검토 지적 2026-10-19). 폰에서는 절이 무대 바로 아래라 자라면 아래 카드가
//    통째로 내려앉는다 — 답이 오기 전에 받은 뒤와 비슷한 높이를 미리 잡는다.
//  · 연출은 짧고(0.9초) 꽃가루가 없으며 **동작 줄이기**를 따른다. 불투명도는 이징으로 깎지 않는다(저장소 메모
//    '이징으로 불투명도를 깎지 마라' — 같은 easeOut 으로 깎으면 밀려나기 전에 사라진다): 떠오름은 easeOut,
//    흐려짐은 떠오름이 거의 끝난 뒤 **짧은 직선**이다.
//  · 폰 규약: 루비는 💎 글자가 아니라 `RubyIcon` + "+N" 이고, 색 · 여백 · 모서리는 전부 `MobileTheme` 토큰이다.
//
// 햅틱(`.sensoryFeedback(.success, trigger: store.missionClaimBurstSerial)`)은 **나 탭 루트 한 곳**(`MeHomeView`)에만 있다.
// 여기와 주간 카드가 각자 달면 한 번 받을 때 두 번 운다. 루트에 다는 또 하나의 이유: 도전 미션 절이 없는 서버
// (`.hidden`)에서도 주간 [받기]의 연출은 울어야 한다.

/// 도전 미션 절의 크기 규약(순수 — 받기 버튼 · 주간 카드가 같은 값을 쓴다).
enum MeAchievementLayout {
    /// 줄 하나의 최소 높이(아이콘 + 제목/막대/보조 세 줄). 큰 글자에서는 글자를 따라 자란다.
    static let rowMinHeight: CGFloat = 64
    static let rowSpacing: CGFloat = MobileTheme.space3
    /// [받기] 캡슐의 보이는 높이. 누름 영역은 `AingButtonMetrics.minimumTarget` 으로 따로 넓힌다.
    static let claimHeight: CGFloat = 32
    /// 받기 연출이 떠오르는 높이(pt) — 줄 안에서 끝난다(카드 밖으로 넘치지 않게).
    static let burstRise: CGFloat = 18
    /// 연출 전체 길이(초) · 흐려지는 꼬리 길이(초). 꼬리는 전체의 뒤 20% 다(떠오름이 거의 끝난 뒤).
    static let burstDuration: Double = 0.9
    static let burstFadeDuration: Double = 0.18

    /// 줄을 아직 모르는 동안(불러오는 중 · 한 번도 못 읽은 실패) 절이 미리 잡아 두는 줄 수.
    ///
    /// 지금 서버가 주는 계열 수와 같게 둔다. 서버가 미션을 더하거나 빼면 이 값이 한두 줄 어긋나는데, 그때 달라지는 것은
    /// **얼마나 덜 흔들리느냐**뿐이다(모자라면 조금 자라고 남으면 조금 줄어든다) — 그려지는 줄은 언제나 서버가 준 것이다.
    static let placeholderRows = 9

    /// 줄을 아직 모르는 상태인가(자리를 미리 잡는다).
    static func reserves(_ section: MeAchievementSection) -> Bool {
        switch section {
        case .loading, .failed: return true
        case .hidden, .loaded: return false
        }
    }

    /// 미리 잡아 둘 본문 높이.
    static var reservedHeight: CGFloat {
        CGFloat(placeholderRows) * rowMinHeight + CGFloat(placeholderRows - 1) * rowSpacing
    }
}

// MARK: - 절

/// 「도전 미션」 카드 — 머리(소제목 + 받을 보상 수 + [전부 받기]) + 계열마다 한 줄.
///
/// 네 갈래를 다 그린다: `.hidden`(서버에 기능이 없다 — 카드째 없다) · `.loading` · `.failed`(자리를 지키고 [다시 시도]) ·
/// `.loaded`. 자리는 `MeHomeView` 에서 「이번 주 근무」 바로 아래다.
struct MeAchievementsSection: View {
    let store: MeStore

    var body: some View {
        let section = store.achievementSection
        if section != .hidden {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                header(section)
                content(for: section)
            }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        }
    }

    /// 소제목 + 오른쪽 "받을 보상 N개" · [전부 받기]. 받을 것이 **둘 이상**일 때만 전부 받기를 준다 —
    /// 하나뿐이면 그 줄의 [받기]와 같은 일을 하는 버튼이 둘이 되어 어느 것을 눌러야 할지 묻게 된다.
    @ViewBuilder
    private func header(_ section: MeAchievementSection) -> some View {
        let claimable = store.achievementClaimableCount
        let hint = MeText.claimPendingHint(claimable)
        let title = Text(MeText.missionsTitle)
            .font(.headline)
            .foregroundStyle(MobileTheme.label)
            .accessibilityAddTraits(.isHeader)
        let trailing = HStack(spacing: MobileTheme.space2) {
            if let hint {
                Text(hint)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.accent)
                    .lineLimit(1)
            }
            if claimable > 1 { claimAllButton }
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: MobileTheme.space2) {
                title.lineLimit(1)
                Spacer(minLength: MobileTheme.space1)
                trailing
            }
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                title.fixedSize(horizontal: false, vertical: true)
                trailing
            }
        }
    }

    private var claimAllButton: some View {
        AingButton(MeText.claimAllButton, kind: .tinted, size: .sm,
                   isBusy: store.isClaimingAchievement(MeStore.achievementClaimAllSlot)) {
            store.claimAllAchievements()
        }
        .accessibilityLabel(Text(MeText.claimAllAccessibility(store.achievementClaimableRuby)))
    }

    @ViewBuilder
    private func content(for section: MeAchievementSection) -> some View {
        switch section {
        case .hidden:
            EmptyView()
        case .loading, .failed:
            // 자리를 지킨다 — 답이 오기 전에 카드가 한 줄로 쪼그라들었다가 아홉 줄로 자라면 아래 카드가 통째로 내려앉는다.
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                if section == .failed {
                    LoadFailureRow(MeText.missionsLoadFailed, isRetrying: store.achievementsState.isLoading) {
                        store.retryAchievements()
                    }
                } else {
                    LoadingRow(MeText.loading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: MeAchievementLayout.reservedHeight, alignment: .topLeading)
        case .loaded(let rows, _):
            VStack(alignment: .leading, spacing: MeAchievementLayout.rowSpacing) {
                ForEach(rows) { MeAchievementRow(store: store, mission: $0) }
            }
        }
    }
}

// MARK: - 줄

/// 도전 미션 한 줄(계열 하나) — 아이콘 · 제목 + 보상("+50") · 진행 막대 · 보조 문장 + 오른쪽 상태.
///  · 진행 중  → 오른쪽에 진행 숫자("23/50").
///  · 받을 수 있음 → 오른쪽에 [받기 +N](누르는 중이면 그 줄만 스피너 · 눌리지 않는다). 실패하면 보조 문장 자리가 말한다.
///  · 받음     → 오른쪽에 "✓ 받음"(체크 기호는 화면이 그린다 — 주간 칸 칩과 같은 관용구).
struct MeAchievementRow: View {
    let store: MeStore
    let mission: AchievementStatus.Mission

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = mission.state
        let tint = state == .claimed ? MobileTheme.working : MobileTheme.accent
        // 받기가 실패했으면 보조 문장 자리가 말한다 — 줄 높이 · 자리는 그대로라 아무것도 밀리지 않고, 누른 그 줄에서 보인다.
        // [받기]가 서 있을 때만이다(그 사이 다른 기기에서 받았으면 실패는 더 뜻이 없다).
        let failed = state == .claimable && store.achievementClaimDidFail(mission.key)
        HStack(alignment: .center, spacing: MobileTheme.space3) {
            icon(tint: tint)
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                titleLine(state: state, tint: tint)
                ProgressBar(mission.fraction, style: state == .claimed ? .done : .accent, thin: true)
                    .accessibilityHidden(true)
                captionLine(state: state, failed: failed)
            }
            if state == .claimable {
                MeClaimButton(amount: mission.reward, inFlight: store.isClaimingAchievement(mission.key)) {
                    store.claimAchievement(key: mission.key)
                }
            }
        }
        .padding(.vertical, MobileTheme.space1)
        .frame(maxWidth: .infinity, minHeight: MeAchievementLayout.rowMinHeight, alignment: .leading)
        // 받기 연출은 줄(**계열**) 자리에 선다 — 콕 10 을 받아 이 줄이 콕 50 으로 바뀌어도 "+5"는 같은 자리에서 떠오른다.
        .overlay(alignment: .trailing) {
            if let burst = store.claimBurst(series: mission.series) {
                MeClaimBurstView(amount: burst.amount, reduceMotion: reduceMotion)
                    .id(burst.serial)
            }
        }
        // 버튼이 있으면 그 버튼이 따로 눌려야 한다(합치면 줄 전체가 한 요소가 돼 버튼 동작이 묻힌다).
        .accessibilityElement(children: state == .claimable ? .contain : .combine)
        .accessibilityLabel(Text(MeText.missionAccessibility(mission)))
    }

    private func icon(tint: Color) -> some View {
        Image(systemName: MeText.missionIcon(mission.key))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }

    /// 제목 + (받을 수 있는 줄이 아니면) 보상 "💎+50". 받을 수 있는 줄은 버튼이 같은 숫자를 말하므로 칩을 감춘다 —
    /// 칩 "+50" 옆 버튼 "+50" 은 어느 것이 지금 받는 루비인지 헷갈린다(맥과 같은 판단).
    @ViewBuilder
    private func titleLine(state: AchievementStatus.RowState, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
            Text(mission.title)
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MobileTheme.space1)
            if state != .claimable, let reward = MeText.missionReward(mission.reward) {
                HStack(spacing: 2) {
                    RubyIcon(size: 14)
                    Text(reward)
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                .fixedSize()
            }
        }
    }

    /// 보조 문장(서버 글자 · 실패면 실패 문장) + 오른쪽 상태("23/50" · "✓ 받음").
    @ViewBuilder
    private func captionLine(state: AchievementStatus.RowState, failed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
            Text(failed ? MeText.claimFailed : mission.detail)
                .font(.caption)
                .foregroundStyle(failed ? MobileTheme.pending : MobileTheme.label3Text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: MobileTheme.space1)
            switch state {
            case .claimed:
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.heavy))
                    Text(MeText.claimedMark)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(MobileTheme.working)
                .fixedSize()
            case .inProgress:
                Text(MeText.missionProgress(mission))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            case .claimable:
                EmptyView()
            }
        }
    }
}

// MARK: - 받기 버튼 · 연출(도전 미션 줄 · 이번 주 근무 카드가 **같은 버튼**을 쓴다)

/// [받기 💎+50]. 강조 채움 캡슐 + 흰 글자(이 카드에서 누를 것은 이것이다). 떠 있으면 스피너로 바뀌고 눌리지 않는다
/// (두 번 눌러도 요청 하나 — 스토어도 따로 막는다). 누름 영역은 보이는 높이와 상관없이 늘 44pt 이상이다.
struct MeClaimButton: View {
    let amount: Int
    var inFlight: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if inFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MobileTheme.onAccentFill)
                } else {
                    Text(MeText.claimButton)
                        .font(.footnote.weight(.bold))
                    RubyIcon(size: 14)
                    Text(MeText.claimAmount(amount))
                        .font(.footnote.weight(.heavy))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(MobileTheme.onAccentFill)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, MobileTheme.space3)
            .frame(minHeight: MeAchievementLayout.claimHeight)
            .background(Capsule().fill(MobileTheme.accentFill))
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .opacity(inFlight ? 0.6 : 1)
        .frame(minHeight: AingButtonMetrics.minimumTarget)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(MeText.claimAccessibility(amount)))
    }
}

/// 받기 연출 — "+N" 알약이 그 자리에서 톡 떠올랐다가 사라진다(0.9초 · 꽃가루 없음 · 한 번 재생하고 끝).
/// 다시 재생하려면 부르는 쪽이 `.id(burst.serial)` 로 새로 만든다.
///
/// **불투명도를 이징으로 깎지 않는다**(저장소 메모): 떠오름은 `easeOut`, 흐려짐은 떠오름이 거의 끝난 뒤 시작하는
/// **짧은 직선**이라 알약이 밀려나기 **전에** 사라지지 않는다. 동작 줄이기면 떠오름 · 커짐 없이 제자리에서 흐려지기만 한다.
struct MeClaimBurstView: View {
    let amount: Int
    let reduceMotion: Bool

    @State private var risen = false
    @State private var faded = false

    var body: some View {
        HStack(spacing: 3) {
            RubyIcon(size: 14)
            Text(MeText.claimAmount(amount))
                .font(MobileTheme.roundedNumber(.footnote, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.working)
        }
        .fixedSize()
        .padding(.horizontal, MobileTheme.space2)
        .frame(minHeight: 26)
        // 불투명 바탕 — 떠오르는 동안 아래 줄 글자("✓ 받음")와 겹쳐 읽히지 않게.
        .background(Capsule().fill(MobileTheme.surface2))
        .overlay(Capsule().stroke(MobileTheme.working.opacity(0.55), lineWidth: 1))
        .scaleEffect(risen || reduceMotion ? 1 : 0.7)
        .offset(y: risen && !reduceMotion ? -MeAchievementLayout.burstRise : 0)
        .opacity(faded ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                risen = true
            } else {
                withAnimation(.easeOut(duration: MeAchievementLayout.burstDuration)) { risen = true }
            }
            withAnimation(.linear(duration: MeAchievementLayout.burstFadeDuration)
                .delay(MeAchievementLayout.burstDuration - MeAchievementLayout.burstFadeDuration)) {
                faded = true
            }
        }
    }
}
#endif
