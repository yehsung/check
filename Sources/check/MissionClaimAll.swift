import CheckCore
import SwiftUI

// MARK: - 미션 [모두 받기] — 묶음 머리의 한 번에 받기(제보 11-17, 서울: "미션 루비 모두 수령 기능 좀 추가해주세요")
//
// 대표 답(11-18): "찌르기 칸 · 모두 받기는 고치기" — 다음 맥 판.
// 사장님 원래 뜻(2026-10-19 — "달성하면 받는 버튼이 생기고 그거 누르면 받아지게끔 … 루비를 받는 재미")은 **줄마다 [받기]** 다.
// 그래서 줄의 [받기]는 그대로 두고, 받을 것이 **둘 이상**일 때만 묶음 머리 오른쪽 "받을 보상 N개" 자리에 [N개 모두 받기]를 세운다
// (하나뿐이면 그 줄의 [받기]와 같은 일을 하는 버튼이 둘이 된다 — 폰 [전부 받기]와 같은 규칙).
//
//  · 묶음은 둘: **일일 미션**(`daily_mission_claim(null)`) · **누적 미션**(`achievement_claim(null)`). 주간은 원래 한 버튼이 전부 받는다.
//  · 낱말은 '모두 받기'(제보 원문 "모두 수령"에 맞췄다 — 폰은 '전부 받기'). 두 묶음이 같은 낱말이다.
//  · 수는 **그 버튼이 실제로 받는 수**다. 누적의 캐릭터 보상(개발 아잉이 · `achievement_character_claim`)은 키 없는 받기가 주지
//    않으므로 세지 않는다 — 머리가 "3개 모두 받기"라 해 놓고 둘만 받으면 거짓이다(캐릭터 줄은 제 [받기]가 그대로 선다).
//    누적은 계열로 접기 **전**의 수다(콕 10 · 50 을 둘 다 채웠으면 한 줄이어도 2 — 키 없는 받기가 둘 다 받는다).
//  · 떠 있음: 그 묶음에 떠 있는 받기가 하나라도 있으면 흐려지고 눌리지 않는다. 모두 받기가 떠 있으면 줄의 [받기]도 흐려진다
//    (기존 자리 `WorkTimerStore.achievementClaimAllSlot` — `MissionClaimContext.isInFlight(_:group:)`).
//  · 받은 뒤: 스토어가 기존 규약대로 줄마다 연출 하나 · 말풍선은 합계로 한 번(`celebrateAchievementClaims` · `celebrateDailyMissionClaims`)
//    · 실패는 받을 수 있던 줄 전부의 보조 문장(`markAchievementClaim(nil)` · `markDailyMissionClaim(nil)`). 자정 넘김도 스토어 그대로다.
//  · 새 요청은 받기 그 자체뿐이다 — 이 파일은 네트워크를 모른다. 서버 변경 없음.
//  · 머리 높이 20pt · 폭 292pt 안(일일 머리는 "자정에 초기화 · 안 받으면 사라져요"와 같이 선다 — 시험이 잰다). 버튼은 머리 줄의
//    글자 자리를 바꾸지 않게 overlay 로 선다(버튼이 있든 없든 제목 · 안내 글자는 같은 자리다).

/// [모두 받기]가 받는 묶음.
enum MissionClaimAllGroup: Equatable, Sendable {
    /// 일일 미션 — `daily_mission_claim(p_key: null)`.
    case daily
    /// 누적 미션(루비 미션만) — `achievement_claim(p_key: null)`.
    case achievement
}

/// [모두 받기]의 문구(순수).
enum MissionClaimAllText {
    /// 버튼 낱말 — 두 묶음이 같다(제보 "모두 수령" · 폰은 '전부 받기').
    static let action = "모두 받기"

    /// 버튼 글자 "3개 모두 받기" — 수는 그 버튼이 실제로 받는 수다.
    static func button(_ count: Int) -> String { "\(max(0, count))개 \(action)" }

    /// 보이스오버 "받을 보상 3개 모두 받기".
    static func accessibility(_ count: Int) -> String { "받을 보상 \(button(count))" }
}

/// 묶음 머리에 설 [N개 모두 받기] 하나(순수 값). 받을 수가 `minimumCount` 보다 적으면 만들지 않는다(nil — 버튼이 없다).
struct MissionClaimAllOffer: Equatable, Sendable {
    let group: MissionClaimAllGroup
    /// 이 버튼이 받는 수(키 없는 받기가 실제로 받는 줄 수).
    let count: Int

    /// 버튼이 서는 최소 수 — 하나뿐이면 그 줄의 [받기]와 같은 일을 하는 버튼이 둘이 된다.
    static let minimumCount = 2

    static func make(group: MissionClaimAllGroup, count: Int) -> MissionClaimAllOffer? {
        count >= minimumCount ? MissionClaimAllOffer(group: group, count: count) : nil
    }

    /// 일일 묶음 — 미션 화면이 그리는 일일 줄에서 센다(하루가 끝난 줄은 이미 [받기]가 없다 · 머리 "받을 보상 N개"와 같은 셈).
    /// 스토어의 키 없는 일일 받기(`claimDailyMission(key: nil)`)가 받는 줄과 같은 집합이다(둘 다 `rows(serverNowMs:)` 의 받을 줄).
    static func daily(_ missions: [DailyMissionStatus.Mission]?) -> MissionClaimAllOffer? {
        make(group: .daily, count: (missions ?? []).filter(\.row.isClaimable).count)
    }

    /// 누적 묶음 — 절 상태에서 센다(`AchievementSectionState.claimAllCount` — 캐릭터 보상 제외 · 계열로 접기 전).
    static func achievement(_ state: AchievementSectionState) -> MissionClaimAllOffer? {
        make(group: .achievement, count: state.claimAllCount)
    }
}

extension AchievementSectionState {
    /// 키 없는 누적 받기(`achievement_claim(null)`)가 받는 수 = 받을 루비 미션 수(계열로 접기 **전** — `AchievementStatus.claimable`).
    /// `claimableCount` 는 캐릭터 보상 줄까지 센 수(머리 "받을 보상 N개" · 레일 배지)이고, 캐릭터 줄은 접지 않고 전부 `rows` 에 서므로
    /// 그 줄의 받을 것을 빼면 루비 몫만 남는다. 절이 줄을 모르면 0.
    var claimAllCount: Int {
        guard case .loaded(let rows, let claimable) = self else { return 0 }
        let character = rows.filter { $0.characterID != nil && $0.isClaimable }.count
        return max(0, claimable - character)
    }
}

extension MissionClaimContext {
    /// 그 묶음의 키 없는 받기를 부른다.
    func claimAll(_ group: MissionClaimAllGroup) {
        switch group {
        case .daily: claimAllDaily()
        case .achievement: claimAllAchievements()
        }
    }

    /// 그 묶음에 떠 있는 받기가 하나라도 있는가 — [모두 받기]가 흐려진다(같은 줄을 두 요청이 함께 잡지 않게. 모두 받기가 떠 있으면
    /// 줄 쪽은 `isInFlight(_:group:)` 가 이미 막는다 — 스토어 자리 `achievementClaimAllSlot`). 누적은 캐릭터 받기도 같은 집합이다.
    func isClaimAllBusy(_ group: MissionClaimAllGroup) -> Bool {
        switch group {
        case .daily: return !dailyInFlightKeys.isEmpty
        case .achievement: return !inFlightKeys.isEmpty
        }
    }
}

/// 묶음 머리의 [N개 모두 받기]. 줄의 [받기](`MissionClaimButton`)와 같은 그라데이션 캡슐이되 머리 줄(20pt) 안에 들게 작다.
/// 떠 있으면 흐려지고 눌리지 않는다(스토어도 같은 묶음의 모두 받기를 두 번 보내지 않는다).
struct MissionClaimAllButton: View {
    let offer: MissionClaimAllOffer
    var busy: Bool = false
    let action: () -> Void

    @State private var hovering = false

    /// 버튼 높이 — 머리 줄(20pt)의 아래 끝에 맞춰 선다(위 여백 6pt 중 2pt 를 쓴다 · 머리 밖으로 안 나간다).
    static let height: CGFloat = 16

    var body: some View {
        Button(action: action) {
            Text(MissionClaimAllText.button(offer.count))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: Self.height)
                .background(Capsule().fill(CheckTheme.gaugeGradient))
                // hover 는 흰색을 얇게 덧칠한다(줄 [받기]와 같은 관용구).
                .overlay(Capsule().fill(Color.white.opacity(hovering && !busy ? 0.12 : 0)))
                // 테두리는 안쪽으로(strokeBorder) — 가운데 선이면 0.5pt 가 머리 20pt 밖으로 번진다(시험이 잰다).
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
        .onHover { hovering = $0 }
        .accessibilityLabel(MissionClaimAllText.accessibility(offer.count))
    }
}
