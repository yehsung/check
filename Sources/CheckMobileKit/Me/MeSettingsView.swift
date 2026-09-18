#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import UIKit

/// 설정: 공개 설정 · 알림(푸시 코디네이터 — 시스템 권한 · 알림 켜기 · 종류별 3토글) · 화면 모드 · 팀 코드 공유 · 로그아웃 · 계정 삭제 · 버전.
///
/// w15 정돈: 절마다 인셋 그룹 한 장 안의 행(구분선 0.5pt) · 토글은 **파랑**(초록은 근무 중·달성 전용 — w14 비평 30) · 알림 권한을
/// 아직 정하지 않았거나 꺼져 있으면 종류별 토글은 **꺼진 모양으로** 흐리게 선다(켜진 채 흐린 모양이 '켜졌는데 고장'처럼 읽혔다) ·
/// 채운 버튼은 [알림 켜기] 하나(팀 코드 공유는 틴트) · 맨 아래 버전 줄은 탭 막대와 띄운다.
///
/// 계정 삭제(앱스토어 5.1.1(v)): 계정 절 맨 아래 빨간 글자 행 하나 — 누르면 시트(`MeAccountDeletionSheet`)가 무엇이 지워지는지 ·
/// 되돌릴 수 없음 · 비밀번호 재입력 · [영구 삭제] 를 묻는다. **이 화면은 삭제를 부르지 않는다**(시트만 부른다 — 소스 계약).
struct MeSettingsView: View {
    let store: MeStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var showsAccountDeletion = false

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
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                privacySection
                pushSection
                appearanceSection
                    .id("appearance")
                teamSection
                    .id("team")
                accountSection
                policyRow
                Text(store.versionLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, MobileTheme.space4)
                    .padding(.bottom, MobileTheme.space6)
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
        // 계정 삭제는 확인 대화상자가 아니라 **시트**다 — 지워지는 것의 목록과 비밀번호 입력이 들어가야 하고, 기권 확인과 같은 이유로
        // 알림창의 재질·시스템 빨강을 피한다(`AingConfirmSheet` 주석). 도는 중에는 시트가 닫히지 않는다.
        .sheet(isPresented: $showsAccountDeletion) {
            MeAccountDeletionSheet(store: store) { showsAccountDeletion = false }
        }
    }

    // MARK: 공개

    private var privacySection: some View {
        section(MeText.privacySection) {
            InsetGroup {
                GroupRow(divider: .inset(MobileTheme.cardPadding), minHeight: MobileTheme.rowHeightTwoLine) {
                    toggleRow(
                        title: MeText.tokenPublicTitle,
                        detail: MeText.tokenPublicDetail,
                        isOn: Binding(get: { store.tokenUsagePublic }, set: { store.setTokenUsagePublic($0) }),
                        enabled: store.tokenUsagePublicLoaded
                    )
                }
                GroupRow(divider: store.privacyLoadFailed || store.settingsNotice != nil ? .inset(MobileTheme.cardPadding) : .none, minHeight: MobileTheme.rowHeightTwoLine) {
                    toggleRow(
                        title: MeText.miniGamePublicTitle,
                        detail: MeText.miniGamePublicDetail,
                        isOn: Binding(get: { store.miniGamePublic }, set: { store.setMiniGamePublic($0) }),
                        enabled: store.miniGamePublicLoaded
                    )
                }
                if store.privacyLoadFailed {
                    GroupRow(divider: store.settingsNotice != nil ? .inset(MobileTheme.cardPadding) : .none) {
                        loadFailureRow(MeText.privacyLoadFailed)
                    }
                }
                if let notice = store.settingsNotice {
                    GroupRow(divider: .none) {
                        InlineNotice(text: notice, kind: .error)
                    }
                }
            }
        }
    }

    // MARK: 알림

    /// 알림: 권한 상태 · 권한 요청(알림 켜기) · 설정 앱 · 종류별 3토글 — 전부 푸시 코디네이터 공개 API(나 탭은 따로 저장하지 않는다).
    /// 토글은 권한이 있고 서버값을 알 때만 켠다. 저장은 코디네이터가 직렬로 보내므로 저장 중에도 다른 토글을 누를 수 있다.
    /// 권한이 없으면(미결정 · 꺼짐) 토글은 **꺼진 모양**으로 보인다 — 알림이 오지 않는다는 사실 그대로(서버 선호값은 건드리지 않는다).
    @ViewBuilder
    private var pushSection: some View {
        if let push = store.push {
            let authorization = push.authorization
            let togglesEnabled = authorization.allowsDelivery && push.knowsPrefs
            section(MeText.pushSection) {
                InsetGroup {
                    GroupRow(divider: .inset(MobileTheme.cardPadding), minHeight: MobileTheme.rowHeightTwoLine) {
                        VStack(alignment: .leading, spacing: MobileTheme.space3) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: authorization.allowsDelivery ? "bell.badge.fill" : "bell.slash.fill")
                                    .foregroundStyle(authorization.allowsDelivery ? MobileTheme.accent : MobileTheme.label2)
                                    .frame(minWidth: 22)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(authorization.meTitle)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(MobileTheme.label)
                                        .fixedSize(horizontal: false, vertical: true)
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
                                AingButton(PushText.settingsEnable, systemImage: "bell.badge", kind: .filled, size: .md, fillsWidth: true,
                                           isBusy: push.isRequestingAuthorization) {
                                    Task { await push.enableNotifications() }
                                }
                            case .denied, .provisional:
                                AingButton(MeText.openSystemSettings, kind: .tinted, size: .md, fillsWidth: true) {
                                    push.openSystemSettings()
                                }
                            case .unknown, .authorized, .ephemeral:
                                EmptyView()
                            }
                        }
                    }
                    ForEach(Array(PushKind.allCases.enumerated()), id: \.element) { index, kind in
                        let isLast = index == PushKind.allCases.count - 1 && !(!push.knowsPrefs && authorization.allowsDelivery) && push.prefsNotice == nil
                        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding), minHeight: MobileTheme.rowHeightTwoLine) {
                            toggleRow(
                                title: kind.settingTitle,
                                detail: MeText.pushDetail(kind),
                                isOn: Binding(
                                    get: { togglesEnabled && push.isEnabled(kind) },
                                    set: { enabled in Task { await push.setPreference(kind, enabled: enabled) } }
                                ),
                                enabled: togglesEnabled
                            )
                        }
                    }
                    if !push.knowsPrefs, authorization.allowsDelivery {
                        GroupRow(divider: push.prefsNotice == nil ? .none : .inset(MobileTheme.cardPadding)) {
                            InlineNotice(text: MeText.pushPrefsUnknown, kind: .info)
                        }
                    }
                    if let notice = push.prefsNotice {
                        GroupRow(divider: .none) {
                            InlineNotice(text: notice, kind: .error)
                        }
                    }
                }
            }
        }
    }

    // MARK: 화면 모드

    /// 시스템 설정 따르기(기본) · 라이트 · 다크 — 고른 행에 체크. 행 전체가 44pt 이상 누름 영역이고, 큰 글자에서는 제목이 줄바꿈한다.
    /// 알림 절 바로 아래(이 기기에 딸린 설정끼리), 계정에 딸린 팀 · 계정 절 위에 둔다.
    private var appearanceSection: some View {
        section(MeText.appearanceSection, footer: MeText.appearanceWidgetNote) {
            InsetGroup {
                ForEach(Array(MobileAppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                    appearanceRow(mode, isLast: index == MobileAppearanceMode.allCases.count - 1)
                }
            }
        }
    }

    private func appearanceRow(_ mode: MobileAppearanceMode, isLast: Bool) -> some View {
        let isSelected = store.appearanceMode == mode
        return Button {
            store.selectAppearance(mode)
        } label: {
            GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 24 + MobileTheme.space3)) {
                Image(systemName: MeText.appearanceSymbol(mode))
                    .font(.body)
                    .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label2)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(MeText.appearanceTitle(mode))
                    .font(.body)
                    .foregroundStyle(MobileTheme.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: MobileTheme.space2)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MeRowButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: 팀

    private var teamSection: some View {
        section(MeText.teamSection) {
            InsetGroup {
                GroupRow {
                    Text(store.teamName ?? MeText.noTeam)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: MobileTheme.space2)
                }
                GroupRow(divider: store.inviteCodeFailed || store.inviteCode != nil ? .inset(MobileTheme.cardPadding) : .none) {
                    Text(MeText.inviteCodeTitle)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Spacer(minLength: MobileTheme.space2)
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
                    GroupRow(divider: store.inviteCode != nil ? .inset(MobileTheme.cardPadding) : .none) {
                        loadFailureRow(MeText.inviteCodeMissing)
                    }
                }
                if let code = store.inviteCode {
                    GroupRow(divider: .none) {
                        ShareLink(item: MeText.inviteShareMessage(teamName: store.teamName, code: code)) {
                            Label(MeText.inviteCodeShare, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(AingButtonStyle(.tinted, size: .md, fillsWidth: true))
                    }
                }
            }
        }
    }

    // MARK: 계정

    private var accountSection: some View {
        section(MeText.accountSection) {
            InsetGroup {
                if let email = store.context.session.profile?.email ?? store.context.session.storedEmail {
                    GroupRow {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                GroupRow(divider: .inset(MobileTheme.cardPadding)) {
                    AingButton(store.isSigningOut ? MeText.signingOut : MeText.signOut, kind: .destructive, size: .md, fillsWidth: true,
                               isBusy: store.isSigningOut) {
                        confirmingSignOut = true
                    }
                }
                // 계정 삭제 행: 글자만 빨강(`danger`)인 목록 행 — 로그아웃(틴트 캡슐)보다 한 단 낮은 무게. 두 개를 다 캡슐로 두면
                // 되돌릴 수 없는 쪽이 되돌릴 수 있는 쪽과 같은 무게로 읽힌다. 누르는 곳은 행 전체(44pt — 행의 위아래 여백을 버튼이 갖는다).
                GroupRow(divider: .none, padding: EdgeInsets(top: 0, leading: MobileTheme.cardPadding, bottom: 0, trailing: MobileTheme.cardPadding)) {
                    Button {
                        showsAccountDeletion = true
                    } label: {
                        HStack(spacing: MobileTheme.space3) {
                            Text(MeText.deleteAccount)
                                .font(.body)
                                .foregroundStyle(MobileTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: MobileTheme.space2)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(MobileTheme.label3)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: AingButtonMetrics.minimumTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSigningOut || store.isDeletingAccount)
                }
            }
        }
    }

    /// 개인정보 처리방침 링크(앱스토어 5.1.1(i) — 처리방침은 **스토어 메타데이터와 앱 안 둘 다**에 있어야 한다).
    /// 절 머리가 없다: 설정 목록의 끝, 버전 줄 바로 위에 붙는 한 행이다(로그아웃·계정 삭제 같은 '하는 일'이 아니라 '읽는 것'이라
    /// 계정 절 안에 섞지 않았다). 주소는 저장소 docs/ 를 GitHub Pages 로 켜 만든 것이다.
    private var policyRow: some View {
        InsetGroup {
            GroupRow(divider: .none, padding: EdgeInsets(top: 0, leading: MobileTheme.cardPadding, bottom: 0, trailing: MobileTheme.cardPadding)) {
                Button {
                    openURL(MeText.privacyPolicyURL)
                } label: {
                    HStack(spacing: MobileTheme.space3) {
                        Text(MeText.privacyPolicy)
                            .font(.body)
                            .foregroundStyle(MobileTheme.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: MobileTheme.space2)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MobileTheme.label3)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: AingButtonMetrics.minimumTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 조각

    /// 절 머리(19 bold · 좌우 20) + 본문 + 선택 꼬리말.
    private func section<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            SectionHeader(title)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space3)
            content()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            }
        }
    }

    /// 조회 실패 안내 + [다시 시도](SPEC-ios §0.5 — 원인과 할 일을 말한다). 공용 `LoadFailureRow`(44pt 버튼). 당겨서 새로고침도 같은 조회다.
    private func loadFailureRow(_ text: String) -> some View {
        LoadFailureRow(text, isRetrying: store.isLoadingSettings) { store.retrySettings() }
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MobileTheme.accentFill)
        .disabled(!enabled)
    }

    /// 권한 다시 읽기(표시 · 설정 앱에서 돌아왔을 때) — 코디네이터가 읽고, 받을 수 있으면 원격 등록까지 한다.
    private func refreshAuthorization() {
        guard let push = store.push else { return }
        Task { await push.refreshAuthorization() }
    }
}
#endif
