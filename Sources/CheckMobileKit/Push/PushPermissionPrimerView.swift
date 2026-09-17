#if os(iOS)
import SwiftUI

/// 알림 권한 설명 시트(SPEC-ios §5 "설명 시트 먼저"). 시스템 권한 창은 한 번만 뜨므로, 무엇을 알려 주는지 먼저 말하고 고르게 한다.
/// 큰 글자에서는 내용이 스크롤되고 버튼 두 개는 아래에 붙어 있다.
struct PushPermissionPrimerView: View {
    let coordinator: PushCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(PushText.primerTitle)
                        .font(MobileTheme.title(.title2))
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                    Text(PushText.primerBody)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize()
                }

                AingCard {
                    ForEach(PushKind.allCases, id: \.self) { kind in
                        PushKindRow(kind: kind)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    note(PushText.primerMacNote, systemImage: "desktopcomputer")
                    note(PushText.primerSettingsNote, systemImage: "gearshape")
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button {
                    Task { await coordinator.primerAllow() }
                } label: {
                    Text(PushText.primerAllow).fixedSize()
                }
                .buttonStyle(AingPrimaryButtonStyle())
                .disabled(coordinator.isRequestingAuthorization)

                Button {
                    coordinator.primerLater()
                } label: {
                    Text(PushText.primerLater)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        // 터치 높이 44pt 이상(HIG). 글자 높이 + 세로 여백만으로는 기본 글자 크기에서 40pt 였다(push-verify 발견 5 실측).
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(coordinator.isRequestingAuthorization)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(MobileTheme.background)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .tint(MobileTheme.accent)
    }

    private func note(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(MobileTheme.label2)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize()
        }
    }
}

/// 알림 종류 한 줄(아이콘 · 이름 · 설명).
private struct PushKindRow: View {
    let kind: PushKind
    /// 글자 크기를 따라 커진다(큰 글자에서 아이콘이 원 밖으로 넘치지 않게).
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 접근성 글자 크기에서는 위 정렬: 줄이 길어져도 아이콘이 제목 옆에 있다(가운데 정렬이면 버튼 뒤로 숨는다 — 스크린샷 실측).
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.body.weight(.semibold))
                // 접근성 크기에서 원이 글자 폭을 먹지 않게 상한(실측: 상한 없이 두면 설명이 두 글자씩 줄바꿈).
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(tint)
                .frame(width: min(iconSize, 48), height: min(iconSize, 48))
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.settingTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize()
                Text(kind.settingDetail)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch kind {
        case .message: return MobileTheme.accent
        case .gomokuInvite: return MobileTheme.working
        case .feedbackReply: return MobileTheme.aiToken
        }
    }
}

private extension Text {
    /// 줄바꿈해서 끝까지 보인다(큰 글자에서 말줄임 금지).
    func fixedSize() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
#endif
