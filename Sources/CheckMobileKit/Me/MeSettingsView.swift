#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import UIKit

/// 설정: 공개 설정 · 알림(푸시 코디네이터 — 시스템 권한 · 알림 켜기 · 종류별 3토글) · 화면 모드 · 팀 코드 공유 · 로그아웃 · 버전.
struct MeSettingsView: View {
    let store: MeStore
    @Environment(\.scenePhase) private var scenePhase
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
                appearanceSection
                    .id("appearance")
                teamSection
                    .id("team")
                accountSection
                Text(store.versionLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
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

    /// 알림: 권한 상태 · 권한 요청(알림 켜기) · 설정 앱 · 종류별 3토글 — 전부 푸시 코디네이터 공개 API(나 탭은 따로 저장하지 않는다).
    /// 토글은 권한이 있고 서버값을 알 때만 켠다. 저장은 코디네이터가 직렬로 보내므로 저장 중에도 다른 토글을 누를 수 있다.
    @ViewBuilder
    private var pushSection: some View {
        if let push = store.push {
            let authorization = push.authorization
            let togglesEnabled = authorization.allowsDelivery && push.knowsPrefs
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                SectionHeader(MeText.pushSection)
                AingCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: authorization.allowsDelivery ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(authorization.allowsDelivery ? MobileTheme.working : MobileTheme.label2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authorization.meTitle)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(MobileTheme.label)
                            if let detail = authorization.meDetail {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if push.isSavingPrefs {
                            ProgressView()
                                .accessibilityLabel(Text("알림 설정 저장 중"))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    switch authorization {
                    case .notDetermined:
                        Button {
                            Task { await push.enableNotifications() }
                        } label: {
                            Label(PushText.settingsEnable, systemImage: "bell.badge")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(AingPrimaryButtonStyle())
                        .disabled(push.isRequestingAuthorization)
                    case .denied, .provisional:
                        Button(MeText.openSystemSettings) {
                            push.openSystemSettings()
                        }
                        .buttonStyle(AingSecondaryButtonStyle())
                    case .unknown, .authorized, .ephemeral:
                        EmptyView()
                    }
                    Divider().overlay(MobileTheme.separator)
                    ForEach(PushKind.allCases, id: \.self) { kind in
                        toggleRow(
                            title: kind.settingTitle,
                            detail: MeText.pushDetail(kind),
                            isOn: Binding(
                                get: { push.isEnabled(kind) },
                                set: { enabled in Task { await push.setPreference(kind, enabled: enabled) } }
                            ),
                            enabled: togglesEnabled
                        )
                    }
                    if !push.knowsPrefs, authorization.allowsDelivery {
                        InlineNotice(text: MeText.pushPrefsUnknown, kind: .info)
                    }
                    if let notice = push.prefsNotice {
                        InlineNotice(text: notice, kind: .error)
                    }
                }
            }
        }
    }

    // MARK: 화면 모드

    /// 시스템 설정 따르기(기본) · 라이트 · 다크 — 고른 행에 체크. 행 전체가 44pt 이상 누름 영역이고, 큰 글자에서는 제목이 줄바꿈한다.
    /// 알림 절 바로 아래(이 기기에 딸린 설정끼리), 계정에 딸린 팀 · 계정 절 위에 둔다.
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.appearanceSection)
            AingCard {
                VStack(spacing: 0) {
                    ForEach(Array(MobileAppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                        if index > 0 {
                            Divider().overlay(MobileTheme.separator)
                        }
                        appearanceRow(mode)
                    }
                }
            }
            Text(MeText.appearanceWidgetNote)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func appearanceRow(_ mode: MobileAppearanceMode) -> some View {
        let isSelected = store.appearanceMode == mode
        return Button {
            store.selectAppearance(mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: MeText.appearanceSymbol(mode))
                    .font(.body)
                    .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label2)
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
                Text(MeText.appearanceTitle(mode))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: 팀

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(MeText.teamSection)
            AingCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.teamName ?? MeText.noTeam)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                    Spacer(minLength: 8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MeText.inviteCodeTitle)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Spacer(minLength: 8)
                    if let code = store.inviteCode {
                        Text(code)
                            .font(MobileTheme.number(.title3, weight: .bold))
                            .monospaced()
                            .foregroundStyle(MobileTheme.label)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("팀 코드 \(code.map(String.init).joined(separator: " "))"))
                    } else {
                        Text(store.inviteCodeLoaded || (store.inviteCodeFailed && !store.isLoadingSettings) ? "—" : MeText.loading)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
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
                        .foregroundStyle(MobileTheme.label2)
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

    /// 조회 실패 안내 + [다시 시도](SPEC-ios §0.5 — 원인과 할 일을 말한다). 공용 `LoadFailureRow`(44pt 버튼). 당겨서 새로고침도 같은 조회다.
    private func loadFailureRow(_ text: String) -> some View {
        LoadFailureRow(text, isRetrying: store.isLoadingSettings) { store.retrySettings() }
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MobileTheme.working)
        .disabled(!enabled)
    }

    /// 권한 다시 읽기(표시 · 설정 앱에서 돌아왔을 때) — 코디네이터가 읽고, 받을 수 있으면 원격 등록까지 한다.
    private func refreshAuthorization() {
        guard let push = store.push else { return }
        Task { await push.refreshAuthorization() }
    }
}
#endif
