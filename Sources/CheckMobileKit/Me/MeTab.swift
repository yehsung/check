#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 나 탭 화면(SPEC-ios §3.6). 루트: 프로필 머리 · 루비 → 기록 → 캐릭터 → 프로필·제보·설정 줄.
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
                VStack(alignment: .leading, spacing: 20) {
                    MeHeaderCard(store: store)
                        .id(MeAnchor.header)
                    VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                        SectionHeader(MeText.recordsTitle)
                        MeRecordsSection(store: store)
                    }
                    .id(MeAnchor.records)
                    VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                        SectionHeader(MeText.charactersTitle)
                        MeCharacterSummaryCard(store: store)
                    }
                    .id(MeAnchor.characters)
                    MeMenuCard(store: store)
                        .id(MeAnchor.menu)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .refreshable { await store.refreshRoot() }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(AingTab.me.title)
            .onAppear { MeDemoHooks.scrollIfRequested(proxy) }
        }
    }
}

/// 루트 스크롤 앵커(데모 스크린샷이 아래 절을 찍을 때 쓴다).
enum MeAnchor: String {
    case header, records, tokenGrass, characters, menu
}

/// 프로필 머리: 사진 · 이름 · 팀 · 센터 · 루비.
struct MeHeaderCard: View {
    let store: MeStore
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let name = store.displayName ?? store.context.session.profile?.email ?? "나"
        AingCard {
            // 접근성 글자 크기에서는 사진을 위로 올리고 팀 이름·센터를 줄로 나눈다(가로 그대로면 팀 이름이 "아…"로 잘렸다 — 실측).
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    AvatarView(name: name, url: store.avatarURL, size: min(avatarSize, 96))
                    identity(name: name, stacked: true)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    AvatarView(name: name, url: store.avatarURL, size: avatarSize)
                    identity(name: name, stacked: false)
                    Spacer(minLength: 0)
                }
            }
            if store.headerState.hasFailed, !store.headerState.hasLoaded {
                InlineNotice(text: "프로필을 불러오지 못했어요 — 당겨서 다시 시도해 주세요", kind: .warning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func identity(name: String, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(MobileTheme.title(.title2))
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if stacked {
                team
                CenterBadge(store.centerServerValue)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    team
                    CenterBadge(store.centerServerValue)
                }
            }
            RubyLabel(store.rubyBalance, style: .headline)
        }
    }

    private var team: some View {
        Label(store.teamName ?? MeText.noTeam, systemImage: "person.3.fill")
            .font(.subheadline)
            .foregroundStyle(MobileTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 착용 캐릭터 + 고르기 · 상점 버튼.
struct MeCharacterSummaryCard: View {
    let store: MeStore
    @ScaledMetric(relativeTo: .title) private var artSize: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let id = store.equippedCharacterID
        AingCard {
            // 접근성 글자 크기에서는 그림을 위로 올린다 — 옆에 두면 커진 그림이 폭을 먹어 실패 안내가 두세 글자씩 꺾였다(AX5 실측).
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        MeCharacterArt(id: id)
                            .frame(width: min(artSize, 96), height: min(artSize, 96))
                        caption(id: id)
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        MeCharacterArt(id: id)
                            .frame(width: artSize, height: artSize)
                        caption(id: id)
                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            // 큰 글자에서 한 줄에 안 들어가면(한 버튼만 두 줄이 되어 높이가 갈리기 전에) 세로로 쌓는다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons(lineLimit: 1) }
                VStack(spacing: 10) { buttons(lineLimit: nil) }
            }
        }
    }

    private func caption(id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MeCharacterCards.displayName(for: id))
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(equippedCaption)
                .font(.subheadline)
                .foregroundStyle(store.equippedLoadFailed && !store.equippedLoaded ? MobileTheme.pending : MobileTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 착용 요약 둘째 줄: 알면 '착용 중' · 조회가 실패했으면 그 사실과 할 일 · 아직이면 '불러오는 중…'.
    private var equippedCaption: String {
        if store.equippedLoaded { return MeText.equipped }
        return store.equippedLoadFailed ? MeText.equippedLoadFailed : MeText.loading
    }

    @ViewBuilder
    private func buttons(lineLimit: Int?) -> some View {
        NavigationLink(value: MeDestination.characters) {
            Label(MeText.pickerTitle, systemImage: "person.crop.square")
                .lineLimit(lineLimit)
                .fixedSize(horizontal: lineLimit != nil, vertical: false)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AingPrimaryButtonStyle())
        NavigationLink(value: MeDestination.shop) {
            Label(MeText.shopTitle, systemImage: "bag.fill")
                .lineLimit(lineLimit)
                .fixedSize(horizontal: lineLimit != nil, vertical: false)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(MobileTheme.accent)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

/// 프로필 · 제보 · 설정 줄.
struct MeMenuCard: View {
    let store: MeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AingCard(padding: 0) {
            VStack(spacing: 0) {
                row(.profile, title: MeText.profileTitle, detail: "사진 · 별명", systemImage: "person.crop.circle")
                Divider().overlay(MobileTheme.separator)
                row(.feedback, title: MeText.feedbackTitle, detail: "버그 · 요청 보내기와 답장", systemImage: "exclamationmark.bubble", showsDot: store.hasUnseenFeedbackReply)
                Divider().overlay(MobileTheme.separator)
                row(.settings, title: MeText.settingsTitle, detail: "공개 · 알림 · 팀 코드 · 로그아웃", systemImage: "gearshape")
            }
        }
    }

    private func row(_ destination: MeDestination, title: String, detail: String, systemImage: String, showsDot: Bool = false) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(MobileTheme.accent)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    // 접근성 글자 크기에서는 '새 답장' 배지를 설명 아래 줄로 내린다(옆에 두면 배지가 폭을 먹어 제목·설명이 한 글자씩 세로로 쌓였다 — AX5 실측).
                    if showsDot, dynamicTypeSize.isAccessibilitySize {
                        replyBadge
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                if showsDot, !dynamicTypeSize.isAccessibilitySize {
                    replyBadge
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(showsDot ? "새 답장이 있어요" : ""))
    }

    private var replyBadge: some View {
        Text(MeText.feedbackReplyBadge)
            .font(.caption.weight(.bold))
            .foregroundStyle(MobileTheme.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(MobileTheme.accent))
            .fixedSize()
    }
}

/// 캐릭터 카드 그림(박힌 HEIC). 모르는 캐릭터는 자리표시.
struct MeCharacterArt: View {
    let id: String

    var body: some View {
        if let image = MeCharacterCards.image(id: id) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(MeCharacterCards.card(id: id)?.pixelArt == true ? .none : .high)
                .scaledToFit()
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(MobileTheme.secondaryText)
                .padding(8)
        }
    }
}

// MARK: - 데모 훅(DEBUG 전용)

/// 데모 스크린샷용: `-AingCheckDemoMeAnchor records|characters|menu` 이면 루트를 그 절까지 내린다.
/// 스토어 동작은 바꾸지 않는다(스크롤 위치만). Release 에서는 아무것도 하지 않는다.
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
