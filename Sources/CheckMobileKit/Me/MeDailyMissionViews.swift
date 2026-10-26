import CheckCore
import CheckMobileShared
import Foundation

// MARK: - 「일일 미션」 절 (폰 1.0.13 — 서버 v0.3.64 `daily` · 맥 `MissionPanel` 의 일일 묶음 미러)
//
// 사용자 결정(2026-10-22, 원문): "지금 미션을 일일미션, 주간미션, 누적미션 이렇게 3개로 나눠서 표시하는게 좋을듯. 이렇게 하고
// 일일미션에 미션들을 몇개 추가할려고 해. 미니게임 일반이랑 멀티 총 합쳐서 6개 있잖아. 그거 각각 하나마다 미션 넣어줘. 하루 1회
// 플레이 달성하면 루비 5개 주는걸로." 묻고 정한 것: **자정(KST)까지 [받기]를 안 누르면 사라진다**.
//
// 자리: 나 탭 루트에서 「이번 주 근무」 카드 **위**다(맥 미션 화면의 일일 → 주간 → 누적 순서를 폰에 그대로 옮긴다).
// 맥의 "근무 3시간마다 루비 3개" 줄은 폰에 없다 — 폰은 일일 6줄만 그린다(인수인계 §0).
//
// ── 이 파일이 지키는 것 ──
// ① **제목 · 보상 · 순서는 서버 글자**다(인수인계 §5-7). 이 파일에 "한 판 하기" 도 5 도 없다 — 서버가 게임 이름을 바꾸거나
//    일일 미션을 더해도 앱을 다시 낼 필요가 없게. 보상은 `RubyIcon` + "+5" 다(💎 글자 금지 — 계약 시험이 소스를 전부 센다).
// ② **버튼 · 연출은 누적 미션과 같은 부품**(`MeClaimButton` · `MeClaimBurstView`)이다. 새로 만들면 햅틱이 두 벌이 되어
//    한 번 받을 때 두 번 운다(`MeAchievementViews.swift` 머리말의 사고 — 햅틱은 `MeHomeView` 한 곳이다).
// ③ **그리는 값은 순수 값**이다(`MeDailyMissionSection` · `MeDailyMissionRowContent`). 폰 뷰는 `#if os(iOS)` 라 맥 스위트가
//    한 줄도 못 그리므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'), 무엇이 그려지는가를 **값으로** 재려면 판단이 뷰 밖에
//    있어야 한다. 뷰는 이 값을 읽어 배치만 한다.
// ④ **날을 넘긴 줄에는 [받기]가 없다.** 넘김 판정은 코어(`DailyMissionStatus.rows(serverNowMs:)`)가 하고, 이 파일은 그 줄만
//    그린다 — 그래서 받을 수(머리의 "받을 보상 N개")에도 어제 줄이 끼지 않는다(인수인계 §5-1 · §5-9).
// ⑤ **일일의 떠 있음 · 실패는 누적과 따로 센다**(인수인계 §5-8). 장부가 아예 두 벌이다(`MeStore.dailyMissionClaimsInFlight` ·
//    `dailyMissionClaimFailedKeys` — `MeStoreAchievements.swift`) — 그래서 한쪽 [전부 받기]가 성공해도 다른 쪽 줄의 실패
//    문장은 그대로 선다. 이 파일은 그 값을 읽기만 한다(`store.dailyMissionClaimDidFail(_:)` · `isClaimingDailyMission(_:)`).

// MARK: - 절을 어떻게 그리는가(순수)

/// 일일 미션 절의 상태 — **갈래는 둘뿐**이다. 불러오는 중 · 실패 갈래가 없는 까닭: 일일은 누적 미션과 **같은 응답**(`daily`)으로
/// 오고, 그 응답이 오기 전에는 이 서버에 일일 미션이 있는지조차 모른다(옛 서버는 영영 없다). 자리를 미리 잡으면 옛 서버에서
/// 빈 카드가 섰다가 사라진다 — 그래서 모르는 동안에는 **아무것도 그리지 않는다**(누적 절은 그 자리에서 자리를 잡는다).
package enum MeDailyMissionSection: Equatable, Sendable {
    /// 그리지 않는다 — 이 서버엔 일일 미션이 없다(옛 서버 · `daily` 가 null · 해석 실패) · 아직 한 번도 못 읽었다 · 줄이 0개다.
    case hidden
    /// 줄(sort 순 — 코어가 정렬한다) + 지금 받을 수 있는 줄의 수 · 루비 합(**날을 넘긴 줄은 빠진 뒤**다).
    case loaded(rows: [DailyMissionStatus.Mission], claimableCount: Int, claimableRuby: Int)

    /// 응답의 `daily` 와 **서버 시각 추정값**에서 고른다. 날이 끝났으면 코어가 줄을 새 날의 모양(진행 0 · [받기] 없음)으로
    /// 바꿔 주므로, 받을 수를 여기서 다시 세면 어제 줄이 저절로 빠진다.
    package static func make(daily: DailyMissionStatus?, serverNowMs: Int?) -> MeDailyMissionSection {
        guard let daily else { return .hidden }
        let rows = daily.rows(serverNowMs: serverNowMs)
        guard !rows.isEmpty else { return .hidden }
        let claimable = rows.filter(\.row.isClaimable)
        return .loaded(rows: rows, claimableCount: claimable.count,
                       claimableRuby: claimable.reduce(0) { $0 + $1.row.reward })
    }

    /// 그려지는 줄(안 그리면 빈 배열).
    package var rows: [DailyMissionStatus.Mission] {
        if case .loaded(let rows, _, _) = self { return rows }
        return []
    }

    /// 머리 오른쪽 "받을 보상 N개" · 탭 배지가 세는 수.
    package var claimableCount: Int {
        if case .loaded(_, let count, _) = self { return count }
        return 0
    }

    package var claimableRuby: Int {
        if case .loaded(_, _, let ruby) = self { return ruby }
        return 0
    }
}

/// 일일 줄 하나에 **실제로 그려지는 것**(순수). 뷰는 이 값을 배치만 한다 — 그래서 맥 스위트가 "무엇이 그려지는가"를 값으로 잰다.
///
/// 세 상태의 그림(인수인계 §4):
///  · 진행 중  → 보상 칩 `RubyIcon +5` + 오른쪽 진행 "0/1"
///  · 받을 수 있음 → [받기 `RubyIcon` +5] 캡슐(칩은 감춘다 — 칩 "+5" 옆 버튼 "+5" 는 어느 것이 지금 받는 루비인지 헷갈린다)
///  · 받음     → 보상 칩 + 오른쪽 "✓ 받음"(체크 기호는 뷰가 그린다)
package struct MeDailyMissionRowContent: Equatable, Sendable {
    /// SF Symbol — 그 게임이 폰에서 이미 쓰는 기호(`MeText.dailyMissionIcon`).
    package let icon: String
    /// 서버 글자 그대로.
    package let title: String
    /// 보상 칩 글자("+5"). [받기] 가 서는 줄에서는 nil(버튼이 같은 숫자를 말한다).
    package let rewardChip: String?
    /// [받기] 금액. nil 이면 버튼이 없다(미달성 · 받음 · 날을 넘긴 줄).
    package let claimAmount: Int?
    /// 오른쪽 진행 숫자("0/1"). 받을 수 있거나 받은 줄에서는 nil.
    package let progress: String?
    /// 받은 줄의 "받음" 글자(체크 기호는 뷰). 아니면 nil.
    package let claimedMark: String?
    /// 보조 문장 — 서버 글자, 받기가 실패했으면 그 줄 안의 실패 문장이다(토스트 · 알림창 · 안내줄을 쓰지 않는다).
    package let caption: String
    /// 보조 문장이 실패 문장인가(색이 갈린다).
    package let showsFailure: Bool
    /// 진행 막대(0…1).
    package let fraction: Double
    /// 받은 줄인가(아이콘 · 막대 색이 갈린다).
    package let isClaimed: Bool
    /// 줄 전체 보이스오버(누적 줄과 같은 말투).
    package let accessibilityLabel: String

    /// `failed` = 이 줄의 마지막 받기가 실패했는가(스토어가 센다). **[받기] 가 선 줄에서만** 실패를 말한다 —
    /// 그 사이 다른 기기에서 받았으면 실패는 더 뜻이 없고, 버튼이 없으면 다시 누를 수도 없다.
    package static func make(mission: DailyMissionStatus.Mission, failed: Bool = false) -> MeDailyMissionRowContent {
        let row = mission.row
        let state = row.state
        let showsFailure = state == .claimable && failed
        return MeDailyMissionRowContent(
            icon: MeText.dailyMissionIcon(game: mission.game),
            title: row.title,
            rewardChip: state == .claimable ? nil : MeText.missionReward(row.reward),
            claimAmount: state == .claimable ? row.reward : nil,
            progress: state == .inProgress ? MeText.missionProgress(row) : nil,
            claimedMark: state == .claimed ? MeText.claimedMark : nil,
            caption: showsFailure ? MeText.claimFailed : row.detail,
            showsFailure: showsFailure,
            fraction: row.fraction,
            isClaimed: state == .claimed,
            accessibilityLabel: MeText.missionAccessibility(row)
        )
    }
}

// MARK: - 화면

#if os(iOS)
import SwiftUI

/// 「일일 미션」 카드 — 머리(소제목 + "받을 보상 N개") + 회색 안내 한 줄 + 일일 줄(sort 순).
///
/// 갈래는 둘이다(`MeDailyMissionSection`): 그릴 것이 없으면 **카드째 없다**. 자리: 「이번 주 근무」 카드 **위**.
struct MeDailyMissionsSection: View {
    let store: MeStore

    var body: some View {
        let section = store.dailyMissionSection
        if case .loaded(let rows, let claimableCount, _) = section {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                header(claimableCount: claimableCount)
                VStack(alignment: .leading, spacing: MeAchievementLayout.rowSpacing) {
                    ForEach(rows) { MeDailyMissionRow(store: store, mission: $0) }
                }
            }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        }
    }

    /// 소제목 + 오른쪽 "받을 보상 N개", 그 아래 회색 한 줄 "자정에 초기화 · 안 받으면 사라져요".
    /// [전부 받기] 는 **없다** — 일일은 줄마다 5루비라 한 번에 받는 것보다 그 줄에서 받는 손맛이 요점이다(맥도 없다).
    @ViewBuilder
    private func header(claimableCount: Int) -> some View {
        VStack(alignment: .leading, spacing: MobileTheme.space1) {
            HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
                Text(MeText.dailyMissionsTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: MobileTheme.space1)
                if let hint = MeText.claimPendingHint(claimableCount) {
                    Text(hint)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.accent)
                        .lineLimit(1)
                }
            }
            Text(MeText.dailyMissionsResetNote)
                .font(.caption)
                .foregroundStyle(MobileTheme.label3Text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

/// 일일 미션 한 줄 — 아이콘 · 제목 + 보상 칩 · 진행 막대 · 보조 문장 + 오른쪽 상태 · [받기].
///
/// 그리는 값은 전부 `MeDailyMissionRowContent`(순수)에서 온다. 버튼과 연출은 누적 미션 줄과 **같은 부품**이다.
struct MeDailyMissionRow: View {
    let store: MeStore
    let mission: DailyMissionStatus.Mission

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = MeDailyMissionRowContent.make(mission: mission,
                                                    failed: store.dailyMissionClaimDidFail(mission.key))
        let tint = content.isClaimed ? MobileTheme.working : MobileTheme.accent
        HStack(alignment: .center, spacing: MobileTheme.space3) {
            icon(content.icon, tint: tint)
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                titleLine(content, tint: tint)
                ProgressBar(content.fraction, style: content.isClaimed ? .done : .accent, thin: true)
                    .accessibilityHidden(true)
                captionLine(content)
            }
            if let amount = content.claimAmount {
                MeClaimButton(amount: amount, inFlight: store.isClaimingDailyMission(mission.key)) {
                    store.claimDailyMission(key: mission.key)
                }
            }
        }
        .padding(.vertical, MobileTheme.space1)
        .frame(maxWidth: .infinity, minHeight: MeAchievementLayout.rowMinHeight, alignment: .leading)
        .overlay(alignment: .trailing) {
            if let burst = store.dailyClaimBurst(key: mission.key) {
                MeClaimBurstView(amount: burst.amount, reduceMotion: reduceMotion)
                    .id(burst.serial)
            }
        }
        .accessibilityElement(children: content.claimAmount != nil ? .contain : .combine)
        .accessibilityLabel(Text(content.accessibilityLabel))
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func titleLine(_ content: MeDailyMissionRowContent, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
            Text(content.title)
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MobileTheme.space1)
            if let reward = content.rewardChip {
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

    @ViewBuilder
    private func captionLine(_ content: MeDailyMissionRowContent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
            Text(content.caption)
                .font(.caption)
                .foregroundStyle(content.showsFailure ? MobileTheme.pending : MobileTheme.label3Text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: MobileTheme.space1)
            if let mark = content.claimedMark {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.heavy))
                    Text(mark)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(MobileTheme.working)
                .fixedSize()
            } else if let progress = content.progress {
                Text(progress)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            }
        }
    }
}
#endif
