#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 나 탭 화면(SPEC-ios §3.6 · w15 재디자인). 루트: **무대**(착용 캐릭터 · 이름 · 팀 · 센터 · 큰 루비 칩 · 근무 상태 · [캐릭터 바꾸기][상점])
/// → **기록**(회고 한 줄 + 12주 근무 · AI 토큰 잔디가 스크롤 없이 한눈에) → 프로필 · 제보 · 설정 그룹 → 지난주 근무 리듬.
/// 하위 화면은 `MeDestination` 을 `router.pathBinding(for: .me)` 에 쌓는다. 딥링크 `me` · `me/shop` · `me/settings` · `feedback[/<id>]`.
struct MeTab: View {
    let store: MeStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .me)) {
            MeHomeView(store: store)
                .navigationDestination(for: MeDestination.self) { destination in
                    switch destination {
                    case .shop: MeShopView(store: store)
                    case .characters: MeCharacterPickerView(store: store)
                    case .profile: MeProfileView(store: store)
                    case .feedback: MeFeedbackView(store: store)
                    case .settings: MeSettingsView(store: store)
                    }
                }
        }
        .onAppear {
            consumeRoute()
            if let destination = MeDemoHooks.takeInitialDestination() {
                router.push(destination, on: .me)
            }
            store.tabDidAppear()
        }
        .onDisappear { store.tabDidDisappear() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .me) {
            store.open(route)
        }
    }
}

// MARK: - 루트

struct MeHomeView: View {
    let store: MeStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    MeStageCard(store: store)
                        .id(MeAnchor.header)
                    MeRecordsCard(store: store)
                        .id(MeAnchor.records)
                    MeMenuGroup(store: store)
                        .id(MeAnchor.menu)
                    MeRhythmCard(store: store)
                        .id(MeAnchor.rhythm)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space1)
                .padding(.bottom, MobileTheme.space6)
            }
            .refreshable { await store.refreshRoot() }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(AingTab.me.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.context.router.push(MeDestination.settings, on: .me)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MobileTheme.label)
                    }
                    .accessibilityLabel(Text(MeText.settingsTitle))
                }
            }
            .onAppear { MeDemoHooks.scrollIfRequested(proxy) }
        }
    }
}

/// 루트 스크롤 앵커(데모 스크린샷이 아래 절을 찍을 때 쓴다).
enum MeAnchor: String {
    case header, records, tokenGrass, characters, menu, rhythm
}

// MARK: - 무대(A 09 구성)

/// 착용 캐릭터를 크게 세운 무대 카드. 캐릭터 132pt(원·링 없이 전신) + 발밑 빛(근무 상태 색) · 이름 · 팀 · 센터 · 큰 루비 칩(→ 상점) ·
/// 근무 상태 한 줄 · [캐릭터 바꾸기][상점]. 접근성 글자 크기에서는 캐릭터를 위로 올리고 버튼을 세로로 쌓는다.
struct MeStageCard: View {
    let store: MeStore
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 무대 캐릭터 크기(시안 A 112×126 · 명세 120~140).
    private let artSize: CGFloat = 132

    var body: some View {
        let mood = presence
        let id = store.equippedCharacterID
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                        stage(id: id, mood: mood)
                            .frame(maxWidth: .infinity)
                        identity(mood: mood)
                    }
                } else {
                    HStack(alignment: .center, spacing: MobileTheme.space2) {
                        stage(id: id, mood: mood)
                        identity(mood: mood)
                        Spacer(minLength: 0)
                    }
                }
            }
            if store.headerState.hasFailed, !store.headerState.hasLoaded {
                LoadFailureRow(MeText.headerLoadFailed, isRetrying: store.headerState.isLoading) {
                    Task { await store.loadHeader() }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MobileTheme.space2) { actions }
                VStack(spacing: MobileTheme.space2) { actions }
            }
        }
        .padding(.top, MobileTheme.space2)
        .padding([.horizontal, .bottom], MobileTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
    }

    /// 내 근무 상태: 지금 탭 내 카드(가장 새 값) → 없으면 위젯 스냅샷의 지난 값 → 둘 다 없으면 모름(nil).
    private var presence: CharacterMood? {
        if let card = store.context.links.now?.myCard(now: store.context.clock.now()) {
            return MeText.stageMood(isWorking: card.isWorking, isStale: card.isStale)
        }
        return store.context.widgetSnapshots.current?.me.map { CharacterMood($0.resolvedStatus) }
    }

    private func stage(id: String, mood: CharacterMood?) -> some View {
        ZStack(alignment: .bottom) {
            // 발밑 빛(시안 A .a-floor) — 색은 근무 상태 뜻 색(모르면 회색).
            Ellipse()
                .fill(RadialGradient(
                    colors: [floorTint(mood).opacity(0.45), floorTint(mood).opacity(0.12), .clear],
                    center: .center, startRadius: 0, endRadius: 62
                ))
                .frame(width: 122, height: 28)
                .accessibilityHidden(true)
            CharacterPortrait(id: id, mood: mood ?? .plain, size: artSize, framed: false)
                .shadow(color: .black.opacity(0.22), radius: 8, y: 6)
                .padding(.bottom, 10)
        }
        .frame(width: artSize + 6, height: artSize + 12)
    }

    private func floorTint(_ mood: CharacterMood?) -> Color {
        switch mood {
        case .working: return MobileTheme.workingDot
        case .lost: return MobileTheme.pendingDot
        case .off: return MobileTheme.offWorkDot
        case .plain, nil: return MobileTheme.label3
        }
    }

    private func identity(mood: CharacterMood?) -> some View {
        // 이메일은 프로필을 **받았는데** 별명이 비었을 때만 제목으로 쓴다 — 못 받은 채(오프라인) 이메일을 제목으로 세우던 결함(통합 검증 E-me).
        let email = store.headerState.hasLoaded ? store.context.session.profile?.email : nil
        let name = store.displayName ?? email ?? MeText.meFallbackName
        return VStack(alignment: .leading, spacing: 7) {
            Text(name)
                .font(MobileTheme.title(.title))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            teamLine
            RubyBalanceChip(store.rubyBalance, style: .large) {
                store.context.router.push(MeDestination.shop, on: .me)
            }
            .accessibilityHint(Text("상점 열기"))
            .padding(.vertical, -5)
            statusLine(mood: mood)
        }
    }

    /// 팀 이름 + 센터 배지(이름 뒤). 한 줄에 안 들어가면 배지를 아래 줄로(잘리지 않게).
    private var teamLine: some View {
        let team = Text(store.teamName ?? MeText.noTeam)
            .font(.subheadline)
            .foregroundStyle(MobileTheme.label2)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                team.lineLimit(1)
                CenterBadge(store.centerServerValue)
            }
            VStack(alignment: .leading, spacing: 4) {
                team.fixedSize(horizontal: false, vertical: true)
                CenterBadge(store.centerServerValue)
            }
        }
    }

    /// "● 근무 중 · 여우 착용 중". 착용값을 모르면 불러오는 중 · 실패 문구.
    private func statusLine(mood: CharacterMood?) -> some View {
        let wear: Text
        if store.equippedLoaded {
            wear = Text(MeText.wearing(MeCharacterCards.displayName(for: store.equippedCharacterID)))
                .foregroundStyle(MobileTheme.label2)
        } else if store.equippedLoadFailed {
            wear = Text(MeText.equippedLoadFailed).foregroundStyle(MobileTheme.pending)
        } else {
            wear = Text(MeText.loading).foregroundStyle(MobileTheme.label2)
        }
        let status = mood.flatMap(MeText.stageStatus)
        let line = status.map { Text($0).fontWeight(.semibold).foregroundStyle(statusColor(mood)) + Text(" · ").foregroundStyle(MobileTheme.label2) + wear } ?? wear
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let mood, let dot = mood.ring {
                StatusDot(dot)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            line
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusColor(_ mood: CharacterMood?) -> Color {
        switch mood {
        case .working: return MobileTheme.working
        case .lost: return MobileTheme.pending
        case .off: return MobileTheme.offWork
        case .plain, nil: return MobileTheme.label2
        }
    }

    @ViewBuilder
    private var actions: some View {
        AingButton(MeText.changeCharacter, systemImage: "person.crop.square", kind: .tinted, size: .md, fillsWidth: true) {
            store.context.router.push(MeDestination.characters, on: .me)
        }
        AingButton(MeText.shopTitle, systemImage: "bag", kind: .tinted, size: .md, fillsWidth: true) {
            store.context.router.push(MeDestination.shop, on: .me)
        }
    }
}

// MARK: - 메뉴 그룹(시안 B)

/// 프로필 · 제보 · 설정 — 인셋 그룹 한 장 안의 행(회색 기호 타일 · 제목 · 오른쪽 보조 글자 또는 '새 답장' · ›).
struct MeMenuGroup: View {
    let store: MeStore

    var body: some View {
        InsetGroup {
            row(.profile, title: MeText.profileTitle, detail: MeText.profileMenuDetail, systemImage: "person.fill", divider: .inset(Self.textInset))
            row(.feedback, title: MeText.feedbackTitle, detail: MeText.feedbackMenuDetail, systemImage: "exclamationmark.bubble.fill",
                showsReply: store.hasUnseenFeedbackReply, divider: .inset(Self.textInset))
            row(.settings, title: MeText.settingsTitle, detail: MeText.settingsMenuDetail, systemImage: "gearshape.fill", divider: .none)
        }
    }

    /// 구분선 시작 = 좌 여백 16 + 타일 30 + 틈 12.
    private static let textInset: CGFloat = MobileTheme.cardPadding + 30 + MobileTheme.space3

    private func row(_ destination: MeDestination, title: String, detail: String, systemImage: String, showsReply: Bool = false, divider: GroupRow<AnyView>.Divider) -> some View {
        Button {
            store.context.router.push(destination, on: .me)
        } label: {
            GroupRow(divider: divider, minHeight: 50) {
                AnyView(MeMenuRowContent(title: title, detail: detail, systemImage: systemImage, showsReply: showsReply))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MeRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(showsReply ? "새 답장이 있어요" : ""))
    }
}

private struct MeMenuRowContent: View {
    let title: String
    let detail: String
    let systemImage: String
    let showsReply: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(uiColor: .systemGray)))
            .accessibilityHidden(true)
        // 큰 글자에서 보조 글자가 제목을 밀어내면 보조 글자를 뺀다(제목·'새 답장'·› 는 남는다).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MobileTheme.space2) {
                titleText.lineLimit(1)
                Spacer(minLength: MobileTheme.space2)
                if showsReply { replyBadge } else { detailText.lineLimit(1) }
            }
            HStack(spacing: MobileTheme.space2) {
                titleText.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: MobileTheme.space2)
                if showsReply { replyBadge }
            }
        }
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MobileTheme.label3)
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(MobileTheme.label)
    }

    private var detailText: some View {
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(MobileTheme.label2)
    }

    private var replyBadge: some View {
        Text(MeText.feedbackReplyBadge)
            .font(.caption.weight(.bold))
            .foregroundStyle(MobileTheme.onAccentFill)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(Capsule().fill(MobileTheme.accentFill))
            .fixedSize()
    }
}

/// 그룹 행 누름 모양: 누르는 동안 옅은 칠.
struct MeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? MobileTheme.fill2 : Color.clear)
    }
}

// MARK: - 데모 훅(DEBUG 전용)

/// 데모 스크린샷용: `-AingCheckDemoMeAnchor records|menu|rhythm` 이면 루트를 그 절까지 내린다.
/// 스토어 동작은 바꾸지 않는다(스크롤 위치만). Release 에서는 아무것도 하지 않는다.
///
/// 기록 없는 계정 장면: `-AingCheckDemoRoute me/` — 라우트 해석은 `me` 와 같고(끝 `/` 는 빈 조각이라 버려진다) 픽스처 장면 이름만
/// `me-` 가 된다(`Demo/Fixtures/me/_me-/` — 완료 세션 0 · 토큰 0 · 근무 안 함 · 기본 캐릭터). 빈 잔디 격자 스크린샷용.
@MainActor
enum MeDemoHooks {
    private static var initialDestinationTaken = false

    /// 실행당 한 번만 꺼낸다(탭을 오갈 때마다 다시 쌓지 않게).
    static func takeInitialDestination() -> MeDestination? {
        guard !initialDestinationTaken else { return nil }
        initialDestinationTaken = true
        return initialDestination()
    }

    static func scrollIfRequested(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard let raw = argument("-AingCheckDemoMeAnchor"), let anchor = MeAnchor(rawValue: raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        #endif
    }

    /// 하위 화면 안에서 아래로 내릴 앵커 이름(`-AingCheckDemoMeScroll <id>`).
    static func scrollTarget() -> String? {
        #if DEBUG
        return argument("-AingCheckDemoMeScroll")
        #else
        return nil
        #endif
    }

    /// 상점에서 미리 골라 둘 캐릭터(`-AingCheckDemoMeSelect <id>`) — 구매 막대·미리 보기 스크린샷용(고르기만, 사지 않는다).
    static func shopSelection() -> String? {
        #if DEBUG
        return argument("-AingCheckDemoMeSelect")
        #else
        return nil
        #endif
    }

    /// 루트 대신 열 하위 화면(`-AingCheckDemoMeScreen characters|profile`) — 라우트가 없는 화면을 찍을 때.
    static func initialDestination() -> MeDestination? {
        #if DEBUG
        switch argument("-AingCheckDemoMeScreen") {
        case "characters": return .characters
        case "profile": return .profile
        case "shop": return .shop
        case "feedback": return .feedback
        case "settings": return .settings
        default: return nil
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static func argument(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}
#endif
