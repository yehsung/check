#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import UIKit
import UserNotifications

/// 설정: 공개 설정 · 알림(시스템 권한 + 종류별 3토글) · 팀 코드 공유 · 로그아웃 · 버전.
struct MeSettingsView: View {
    let store: MeStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onAppear {
                    if let target = MeDemoHooks.scrollTarget() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(target, anchor: .bottom) }
                    }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacySection
                pushSection
                teamSection
                    .id("team")
                accountSection
                Text(store.versionLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .id("version")
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { await store.loadSettings() }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MeText.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.settingsDidAppear()
            refreshAuthorization()
        }
        .onDisappear { store.settingsDidDisappear() }
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 알림을 켜고 돌아오면 바로 반영한다.
            if phase == .active { refreshAuthorization() }
        }
        .confirmationDialog(MeText.signOutConfirmTitle, isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button(MeText.signOut, role: .destructive) {
                Task { await store.signOut() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(MeText.signOutConfirmMessage)
        }
    }

    // MARK: 공개

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.privacySection)
            AingCard {
                toggleRow(
                    title: MeText.tokenPublicTitle,
                    detail: MeText.tokenPublicDetail,
                    isOn: Binding(get: { store.tokenUsagePublic }, set: { store.setTokenUsagePublic($0) }),
                    enabled: store.tokenUsagePublicLoaded
                )
                Divider().overlay(MobileTheme.separator)
                toggleRow(
                    title: MeText.miniGamePublicTitle,
                    detail: MeText.miniGamePublicDetail,
                    isOn: Binding(get: { store.miniGamePublic }, set: { store.setMiniGamePublic($0) }),
                    enabled: store.miniGamePublicLoaded
                )
                if store.privacyLoadFailed {
                    loadFailureRow(MeText.privacyLoadFailed)
                }
                if let notice = store.settingsNotice {
                    InlineNotice(text: notice, kind: .error)
                }
            }
        }
    }

    // MARK: 알림

    private var pushSection: some View {
        let authorization = store.pushAuthorization
        let prefs = store.displayedPushPrefs
        let togglesEnabled = authorization.allowsDelivery && prefs != nil && !store.isSavingPushPrefs
        return VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.pushSection)
            AingCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: authorization.allowsDelivery ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(authorization.allowsDelivery ? MobileTheme.working : MobileTheme.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authorization.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(MobileTheme.primaryText)
                        if let detail = authorization.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if authorization == .denied || authorization == .provisional {
                    Button(MeText.openSystemSettings) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                    .tint(MobileTheme.accent)
                }
                Divider().overlay(MobileTheme.separator)
                toggleRow(
                    title: MeText.pushMessageTitle,
                    detail: MeText.pushMessageDetail,
                    isOn: Binding(get: { prefs?.message ?? false }, set: { store.setPushPref(\.message, to: $0) }),
                    enabled: togglesEnabled
                )
                toggleRow(
                    title: MeText.pushGomokuTitle,
                    detail: MeText.pushGomokuDetail,
                    isOn: Binding(get: { prefs?.gomokuInvite ?? false }, set: { store.setPushPref(\.gomokuInvite, to: $0) }),
                    enabled: togglesEnabled
                )
                toggleRow(
                    title: MeText.pushFeedbackTitle,
                    detail: MeText.pushFeedbackDetail,
                    isOn: Binding(get: { prefs?.feedbackReply ?? false }, set: { store.setPushPref(\.feedbackReply, to: $0) }),
                    enabled: togglesEnabled
                )
                if prefs == nil, authorization.allowsDelivery {
                    InlineNotice(text: MeText.pushPrefsUnknown, kind: .info)
                }
                if let notice = store.pushPrefsNotice {
                    InlineNotice(text: notice, kind: .error)
                }
            }
        }
    }

    // MARK: 팀

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.teamSection)
            AingCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.teamName ?? MeText.noTeam)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.primaryText)
                    Spacer(minLength: 8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MeText.inviteCodeTitle)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.secondaryText)
                    Spacer(minLength: 8)
                    if let code = store.inviteCode {
                        Text(code)
                            .font(MobileTheme.number(.title3, weight: .bold))
                            .monospaced()
                            .foregroundStyle(MobileTheme.primaryText)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("팀 코드 \(code.map(String.init).joined(separator: " "))"))
                    } else {
                        Text(store.inviteCodeLoaded || (store.inviteCodeFailed && !store.isLoadingSettings) ? "—" : MeText.loading)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.secondaryText)
                    }
                }
                if store.inviteCodeFailed {
                    loadFailureRow(MeText.inviteCodeMissing)
                }
                if let code = store.inviteCode {
                    ShareLink(item: MeText.inviteShareMessage(teamName: store.teamName, code: code)) {
                        Label(MeText.inviteCodeShare, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AingPrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: 계정

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.accountSection)
            AingCard {
                if let email = store.context.session.profile?.email ?? store.context.session.storedEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .textSelection(.enabled)
                }
                Button(role: .destructive) {
                    confirmingSignOut = true
                } label: {
                    HStack {
                        if store.isSigningOut { ProgressView() }
                        Text(store.isSigningOut ? MeText.signingOut : MeText.signOut)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.danger.opacity(0.12)))
                    .foregroundStyle(MobileTheme.danger)
                }
                .buttonStyle(.plain)
                .disabled(store.isSigningOut)
            }
        }
    }

    // MARK: 조각

    /// 조회 실패 안내 + [다시 시도](SPEC-ios §0.5 — 원인과 할 일을 말한다). 당겨서 새로고침도 같은 조회다.
    private func loadFailureRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineNotice(text: text, kind: .warning)
            Button {
                store.retrySettings()
            } label: {
                if store.isLoadingSettings {
                    Text(MeText.loading)
                } else {
                    Label(MeText.retry, systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .tint(MobileTheme.accent)
            .disabled(store.isLoadingSettings)
        }
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MobileTheme.working)
        .disabled(!enabled)
    }

    private func refreshAuthorization() {
        Task { store.updatePushAuthorization(await MePushPermission.current()) }
    }
}

/// 시스템 알림 권한 읽기(읽기만 — 권한 **요청**은 푸시 코디네이터(D9)의 설명 시트가 한다).
enum MePushPermission {
    static func current() async -> MePushAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }
}
#endif
