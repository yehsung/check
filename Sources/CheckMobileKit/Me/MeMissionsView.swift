#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 「미션」 화면 + 루트 [미션] 줄 (폰 1.0.13)
//
// 사용자 지시(2026-10-23, 원문): "폰에서 나 탭에 미션들 쭈루룩 다 나열하니까 칸이 너무 길어져. 미션 창 버튼 두고 그거 누르면
// 미션 페이지 따로 있게 해줘"
//
// 루트에서 나간 것은 **둘**이다 — 「이번 주 근무」 카드와 「도전 미션」 절. 재 보면 절이 9줄(계열마다 하나 ·
// `MeAchievementLayout.placeholderRows`)이고 줄 최소 높이 64 + 틈 12 라 본문만 ≈ 672pt, 거기에 주간 카드(게이지 · 칩 ·
// [받기] · 규칙 ≈ 200pt)가 더해져 루트가 화면 두 장을 넘었다.
//
// 도전 미션만 옮기고 주간 카드를 루트에 남기지 **않은** 까닭(되돌리면 이것들이 돌아온다):
//  · 탭 막대 나 탭 배지가 이미 **둘을 합친 수**다(`MeStore.missionClaimableCount` = 도전 미션 + 주간 단계). 주간만 루트에
//    남기면 배지 "1"을 보고 들어온 사람에게 그것이 루트에 있는지 이 화면에 있는지 알 길이 없다 — 배지가 가리키는 곳이 둘로 갈린다.
//  · 맥 [미션] 화면(`MissionPanel` — 3시간 줄 → 이번 주 근무 → 도전 미션, 사용자 지시 2026-10-16)이 이미 그 둘을 담는다.
//    폰이 다르게 가르면 같은 사람이 두 기계에서 다른 곳을 찾는다.
//  · 둘은 **같은 [받기] 버튼**(`MeClaimButton`)과 **같은 받기 햅틱**(`missionClaimBurstSerial`)을 쓴다. 갈라 두면 햅틱을
//    두 화면에 달아야 하고, 그러면 "한 번 받고 두 번 운다"가 되돌아온다(그 결함이 0.3.58 에 햅틱을 한 곳으로 모은 까닭이다).
//
// 즉 "미션"은 **루비를 받는 곳 전부**이고 들어가는 문은 하나다.
//
// 이 파일은 **그림만** 그린다. 두 카드는 자기 안에서 자기 상태(불러오는 중 · 실패 · 숨김)를 다 그리므로 그 분기를 여기서
// 다시 쓰지 않는다. 줄을 세울지 · 화면이 비었는지도 스토어가 판정한다(`showsMissionsRow` · `missionsPageIsEmpty`) —
// 화면이 `weeklyWorkAvailable` 같은 반쪽 값을 직접 보면 줄과 카드가 서로 다른 말을 한다.

// MARK: - 루트의 줄

/// 루트 [미션] 줄 — 누르면 미션 화면을 쌓는다(`MeDestination.missions`).
///
/// 모양은 메뉴 그룹 행(`MeMenuGroup` · `MeMenuRowContent`)의 관용구를 **그대로** 쓴다: `InsetGroup` +
/// `GroupRow(divider: .none, minHeight: 50)` + `MeRowButtonStyle` + 큰 글자 `ViewThatFits` + 줄 전체 한 요소.
/// 메뉴 그룹에 끼워 넣지 않고 자기 그룹 한 장으로 서는 까닭: 자리가 **루비 칩 바로 아래**여야 한다(루비가 어디서 오는지
/// 머리 옆에서 보인다) — 메뉴 그룹은 루트의 마지막이다.
///
/// 서버에 주간·도전 미션이 **둘 다 없으면 줄이 아예 안 선다**(`store.showsMissionsRow`) — 1.0.12 까지 카드 둘이 통째로
/// 빠지던 것과 같은 규약이다. 그래서 눌러 들어갔더니 빈 화면인 일은 없다(옛 서버 · 로그인 전).
struct MeMissionsRow: View {
    let store: MeStore

    var body: some View {
        if store.showsMissionsRow {
            InsetGroup {
                Button {
                    store.context.router.push(MeDestination.missions, on: .me)
                } label: {
                    GroupRow(divider: .none, minHeight: 50) {
                        // 받을 보상 수는 **탭 막대 배지와 같은 함수**를 지난다(`missionClaimableCount` — 도전 미션 + 주간).
                        // 반쪽 값(`achievementClaimableCount`)을 쓰면 배지는 "1"인데 줄은 아무 말도 안 하는 날이 온다.
                        AnyView(MeMissionsRowContent(pendingHint: MeText.claimPendingHint(store.missionClaimableCount)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(MeRowButtonStyle())
                // 줄 전체가 한 요소다 — 보이스오버가 "미션, 받을 보상 2개, 버튼"을 한 줄로 읽는다(메뉴 행과 같은 처방).
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// 줄의 내용(타일 · 제목 · 배지 또는 보조 글자 · ›) — `MeMenuRowContent` 와 같은 모양이다.
private struct MeMissionsRowContent: View {
    /// "받을 보상 2개"(`MeText.claimPendingHint`) — 받을 것이 없으면 nil 이고 그 자리에 보조 글자가 선다.
    let pendingHint: String?

    var body: some View {
        // 기호는 맥 레일 [미션] 칸과 같은 `checklist` 다(같은 곳을 가리키는 그림은 두 기계에서 같아야 한다).
        // 타일 색만 메뉴 그룹(회색 `systemGray`)과 다르다: 여기는 **받을 것이 있는 곳**이고 루비 칩 바로 아래 서는 줄이다.
        Image(systemName: "checklist")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(MobileTheme.accent))
            .accessibilityHidden(true)
        // 큰 글자에서 보조 글자가 제목을 밀어내면 보조 글자를 뺀다(`MeMenuRowContent` 와 같은 처방).
        // **배지는 버리지 않는다** — 받을 것이 있다는 사실이 이 줄을 누를 까닭이고, 그것을 버리면 루비를 못 받고 지나간다.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MobileTheme.space2) {
                titleText.lineLimit(1)
                Spacer(minLength: MobileTheme.space2)
                if let pendingHint { badge(pendingHint) } else { detailText.lineLimit(1) }
            }
            HStack(spacing: MobileTheme.space2) {
                titleText.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: MobileTheme.space2)
                if let pendingHint { badge(pendingHint) }
            }
        }
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MobileTheme.label3)
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(MeText.missionsPageTitle)
            .font(.body)
            .foregroundStyle(MobileTheme.label)
    }

    private var detailText: some View {
        Text(MeText.missionsRowDetail)
            .font(.subheadline)
            .foregroundStyle(MobileTheme.label2)
    }

    /// 받을 보상 수 캡슐(제보 줄의 '새 답장' 배지와 같은 모양 · 같은 토큰). 글자 색은 `onAccentFill` 이다 — `accentFill`
    /// 위에 `label` 을 올리면 다크에서 읽히지 않는다.
    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(MobileTheme.onAccentFill)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(Capsule().fill(MobileTheme.accentFill))
            .fixedSize()
    }
}

// MARK: - 화면

/// 「미션」 화면(1.0.13) — 「일일 미션」 → 「이번 주 근무」 → 「누적 미션」 세 묶음.
/// **맥 0.3.64 [미션] 화면과 같은 순서**다(두 기계에서 같은 순서를 본다). 주간·누적은 루트에서 옮겨 온 것이고
/// 일일은 1.0.13 에 새로 생겼다.
///
/// 하위 화면 스크롤 깃발(`MeDemoHooks.scrollTarget()`)은 쓰지 않는다 — 이 화면은 두 카드뿐이라 짧다.
/// 당겨서 새로 고치기는 **이 화면에 있는 둘만** 다시 읽는다(`store.refreshMissions()` — 루트 새로고침이 아니다).
struct MeMissionsView: View {
    let store: MeStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                // 1.0.13 세 묶음은 **맥 0.3.64 미션 화면과 같은 순서**다 — 일일 → 이번 주 → 누적.
                // 범위가 좁은 쪽부터 넓어진다(오늘 → 이번 주 → 통산). 한때 일일 절이 나 탭 루트의 주간 카드
                // 위에 서 있었는데, 그건 사용자가 고치라고 한 "쭈루룩 나열"을 하나 더 늘리는 일이었다
                // (`MeTab.swift` 의 ★ 주석). 셋 다 서버에 기능이 없으면 자기 절이 통째로 빠진다.
                MeDailyMissionsSection(store: store)
                MeWeeklyWorkCard(store: store)
                MeAchievementsSection(store: store)
                if store.missionsPageIsEmpty {
                    // 줄을 눌러 들어온 뒤 빈 화면이 되는 일은 없다(둘 다 없으면 루트 줄 자체가 안 선다 —
                    // `showsMissionsRow`). 하지만 들어온 **뒤** 서버가 기능을 잃거나 세션이 끊길 수는 있어서,
                    // 그때 아무 말도 없는 흰 화면이 남지 않게 한 줄이 선다.
                    Text(MeText.missionsEmpty)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MobileTheme.space6)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space1)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable { await store.refreshMissions() }
        // 받기 성공 햅틱 — **이 한 곳**이다(1.0.13 에 나 탭 루트에서 여기로 옮겼다). 주간 카드와 도전 미션 절이 각자 달면
        // 한 번 받을 때 두 번 운다(그 결함이 0.3.58 에 햅틱을 한 곳으로 모은 까닭이다). 루트가 아니라 이 화면인 까닭은
        // 하나다: [받기] 버튼이 이제 루트에 **하나도 없다** — 루트에 남겨 두면 영원히 울지 않는 수식어가 된다.
        .sensoryFeedback(.success, trigger: store.missionClaimBurstSerial)
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MeText.missionsPageTitle)
    }
}
#endif
