#if os(iOS)
import SwiftUI

/// 알림 권한 설명 시트(SPEC-ios §5 "설명 시트 먼저"). 시스템 권한 창은 한 번만 뜨므로, 무엇을 알려 주는지 먼저 말하고 고르게 한다.
/// 재디자인 B: 종 든 아잉 · 가운데 제목 · 알림 종류 인셋 그룹(기호는 모두 파랑 틴트 — 초록·보라는 근무·AI 토큰 뜻이라 쓰지 않는다) ·
/// 아래 막대에 채운 [알림 켜기] 하나 + 글자 [나중에]. 내용은 남는 높이 가운데에 모이고, 큰 글자에서는 스크롤된다.
struct PushPermissionPrimerView: View {
    let coordinator: PushCoordinator

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: MobileTheme.space4)
                    content
                    Spacer(minLength: MobileTheme.space4)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                // 폭은 화면 폭으로 못 박는다 — 유연한 틀(maxWidth)만 두면 큰 글자에서 자식의 이상 폭(520)으로 커져 글자가 화면 밖으로 잘렸다(AX3 실측).
                .frame(width: min(proxy.size.width, 520))
                .frame(width: proxy.size.width)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: MobileTheme.space1) {
                AingButton(PushText.primerAllow, kind: .filled, size: .lg, fillsWidth: true) {
                    Task { await coordinator.primerAllow() }
                }
                .disabled(coordinator.isRequestingAuthorization)

                AingButton(PushText.primerLater, kind: .plain, size: .md, fillsWidth: true) {
                    coordinator.primerLater()
                }
                .disabled(coordinator.isRequestingAuthorization)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space3)
            .padding(.bottom, MobileTheme.space2)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(MobileTheme.background)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .tint(MobileTheme.accent)
    }

    private var content: some View {
        VStack(spacing: 0) {
            CharacterPortrait(id: nil, mood: .plain, size: 88, badge: .symbol("bell.fill"), ringGap: MobileTheme.background, framed: false)
                .accessibilityHidden(true)

            VStack(spacing: MobileTheme.space2) {
                Text(PushText.primerTitle)
                    .font(MobileTheme.title(.title2))
                    .foregroundStyle(MobileTheme.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(PushText.primerBody)
                    .font(.body)
                    .foregroundStyle(MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, MobileTheme.space4)

            InsetGroup {
                ForEach(Array(PushKind.allCases.enumerated()), id: \.element) { index, kind in
                    GroupRow(
                        divider: index == PushKind.allCases.count - 1 ? .none : .inset(PushKindRow.textLeading),
                        minHeight: 60
                    ) {
                        PushKindRow(kind: kind)
                    }
                }
            }
            .padding(.top, MobileTheme.space6)

            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                note(PushText.primerMacNote, systemImage: "desktopcomputer")
                note(PushText.primerSettingsNote, systemImage: "gearshape")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space3)
        }
    }

    private func note(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 알림 종류 한 줄(기호 원 · 이름 · 설명). 기호 원은 모두 파랑 틴트 — 종류를 색으로 가르지 않는다(색은 뜻으로만).
private struct PushKindRow: View {
    let kind: PushKind
    /// 원 36 + 간격 12 + 좌 16 = 글자 시작점(구분선 시작).
    static let textLeading: CGFloat = 64
    /// 글자 크기를 따라 커진다(큰 글자에서 기호가 원 밖으로 넘치지 않게).
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 접근성 글자 크기에서는 위 정렬: 줄이 길어져도 기호가 제목 옆에 있다(가운데 정렬이면 버튼 뒤로 숨는다 — 스크린샷 실측).
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.body.weight(.semibold))
                // 접근성 크기에서 원이 글자 폭을 먹지 않게 상한(실측: 상한 없이 두면 설명이 두 글자씩 줄바꿈).
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(MobileTheme.accent)
                .frame(width: min(iconSize, 48), height: min(iconSize, 48))
                .background(Circle().fill(MobileTheme.accentTint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.settingTitle)
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.settingDetail)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#endif
