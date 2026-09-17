#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 지금 탭 화면(SPEC-ios §3.2 · 재디자인 B 01·02): 큰 제목 + 부제(날짜 · 팀) · 내 상태 카드(착용 캐릭터 초상 · 큰 타이머 · 이번 주 막대) ·
/// 오늘 할 일 · 지금 근무 중(우리 팀 경과 / 다른 팀 말 걸기). 스크롤하면 제목이 접히고 부제가 "5:10:00 · 이번 주 62%"로 바뀐다.
/// 경로는 `router.pathBinding(for: .now)`, 딥링크(`aingcheck://now` — 위젯 탭)는 `consumePendingRoute(for: .now)` 로 꺼낸다.
struct NowTab: View {
    let store: NowStore
    @State private var isGoalSheetPresented = false
    /// 큰 제목이 접혔는가(부제를 날짜 · 팀 → 시계 · 퍼센트로 바꾼다).
    @State private var isTitleCollapsed = false

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .now)) {
            ScrollViewReader { proxy in
                List {
                    if #available(iOS 26, *) {
                        // 부제는 내비 막대가 그린다(`NowNavigationSubtitle`).
                    } else {
                        // iOS 26 전에는 내비 부제가 없다 — 큰 제목 바로 아래 줄로 둔다(접힌 제목의 시계 부제는 없음).
                        Section {
                            Text(NowTab.expandedSubtitle(store: store))
                                .font(.subheadline)
                                .foregroundStyle(MobileTheme.label2)
                                .listRowInsets(EdgeInsets(top: 0, leading: MobileTheme.titleMargin, bottom: 0, trailing: MobileTheme.titleMargin))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    if let notice = store.notice {
                        Section {
                            InlineNotice(text: notice, kind: .warning)
                                .cardListPlainRow(top: 0, bottom: 0)
                        }
                    }
                    NowStatusSection(store: store, onEditGoal: { isGoalSheetPresented = true })
                    NowTodoSection(store: store)
                    NowWorkingSection(store: store)
                }
                #if DEBUG
                .task {
                    guard store.context.isDemo, NowDemoStage.stages().contains("working"), await NowDemoStage.waitForAttempt(store) else { return }
                    // 행이 그려질 틈(첫 응답 직후 스크롤하면 아직 없는 절로 가지 못한다).
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(NowTab.workingSectionID, anchor: .top)
                }
                #endif
                // grouped(셀이 화면 폭) — 카드는 행이 `cardSegmentRow` 로 직접 그린다(insetGrouped 는 셀을 시스템 반경으로 잘랐다).
                .listStyle(.grouped)
                .listSectionSpacing(.compact)
                // 묶음 이름 줄("우리 팀 · 3명")이 44pt 빈 행처럼 보이지 않게 — 다른 행은 내용이 이보다 높다.
                .environment(\.defaultMinListRowHeight, 26)
                .contentMargins(.top, NowTab.listTopMargin, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(MobileTheme.background.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.refreshNow() }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > NowTab.collapseOffset
                } action: { _, collapsed in
                    isTitleCollapsed = collapsed
                }
                .navigationTitle(NowText.title)
                .modifier(NowNavigationSubtitle(store: store, isCollapsed: isTitleCollapsed))
                .overlay(alignment: .bottom) { NowUndoToast(store: store) }
                .animation(.snappy, value: store.undoTodoID)
                .sheet(isPresented: $isGoalSheetPresented) {
                    NowGoalSheet(store: store)
                }
            }
        }
        .onAppear {
            consumeRoute()
            store.tabDidAppear()
        }
        .onChange(of: router.routeSerial) { consumeRoute() }
        #if DEBUG
        .task { await NowDemoStage.apply(store: store, openGoalSheet: { isGoalSheetPresented = true }) }
        #endif
    }

    static let workingSectionID = "now.working"
    /// 이만큼 내려가면 큰 제목이 접힌 것으로 본다(큰 제목 줄 높이 약 52pt).
    static let collapseOffset: CGFloat = 44
    /// 부제와 첫 카드 사이(시안 14pt) — grouped 목록의 첫 절 위 기본 틈을 줄인다.
    static let listTopMargin: CGFloat = 4

    /// 펼친 큰 제목 부제 "9월 17일 목요일 · 아잉 데모팀".
    static func expandedSubtitle(store: NowStore) -> String {
        NowText.expandedSubtitle(date: NowFormat.longDate(store.context.clock.now()), teamName: store.membership?.teamName)
    }

    private func consumeRoute() {
        // aingcheck://now(위젯 탭)는 탭 자체다 — 이 탭은 쌓는 화면이 없으니 꺼내 비우기만 한다(라우터가 이미 탭을 골랐다).
        _ = store.context.router.consumePendingRoute(for: .now)
    }
}

/// 내비 부제(iOS 26+): 펼침 = 날짜 · 팀, 접힘 = 오늘 누적 시계 · 이번 주 퍼센트(접힌 동안만 1초마다 다시 센다).
private struct NowNavigationSubtitle: ViewModifier {
    let store: NowStore
    let isCollapsed: Bool
    @State private var tick = 0

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .navigationSubtitle(subtitle)
                .task(id: isCollapsed) {
                    guard isCollapsed else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        tick &+= 1
                    }
                }
        } else {
            content
        }
    }

    private var subtitle: String {
        _ = tick
        let now = store.context.clock.now()
        if isCollapsed, let card = store.myCard(now: now) {
            return NowText.collapsedSubtitle(clock: NowFormat.clock(card.todaySeconds), percent: card.percent)
        }
        return NowTab.expandedSubtitle(store: store)
    }
}

// MARK: - 절 머리

/// 목록 절 머리(시안 `.b-sh`): 19 bold 제목 + 오른쪽 보조 글자. 좌우 20 · 아래 8. 위는 16 — grouped 목록의 절 사이 틈이 더해져
/// 시안의 22pt 와 같은 간격이 된다(스크린샷 대조).
struct NowSectionHeader: View {
    let title: String
    let trailing: String?

    var body: some View {
        SectionHeader(title, trailing: trailing.map { .text($0) } ?? .none)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 16, leading: MobileTheme.titleMargin, bottom: 8, trailing: MobileTheme.titleMargin))
    }
}

// MARK: - 내 상태

struct NowStatusSection: View {
    let store: NowStore
    let onEditGoal: () -> Void

    var body: some View {
        Section {
            // 오늘 누적은 1초마다 폰이 센다(서버 세션 시작 시각 기준). 시각은 스토어 시계에서만 읽는다(데모는 멈춘 시계).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                content(now: store.context.clock.now())
            }
            .cardSegmentRow(.single, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.hasNoTeam {
            VStack(alignment: .leading, spacing: 6) {
                Text(NowText.noTeamTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                Text(NowText.noTeamBody)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else if let card = store.myCard(now: now) {
            NowStatusCard(card: card, characterID: store.displayedCharacterID, onEditGoal: onEditGoal)
        } else if store.teamLoadState == .failed {
            // 시도는 끝났는데 모른다(오프라인 · 5xx) — 도는 요청이 없는데 "불러오는 중"을 남기지 않는다.
            NowUnavailableRow(title: NowText.statusUnavailableTitle, isRetrying: store.isRefreshing) { store.refresh() }
        } else {
            LoadingRow()
        }
    }
}

/// 불러오지 못한 자리(스피너 대신): 공용 `LoadFailureRow`(경고 한 줄 + 44pt [다시 시도]) — 순위·나·게임 탭과 같은 모양.
/// 위쪽 안내 줄이 원인(네트워크 · 서버)을 말한다.
struct NowUnavailableRow: View {
    let title: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        LoadFailureRow(title, isRetrying: isRetrying, retry: retry)
            .padding(.vertical, 2)
    }
}

/// 상태 카드(시안 `.b-hero`): [초상 · 상태 글자 · 부제 · 목표 연필] / 큰 타이머 / 이번 주 줄 + 막대.
/// 초상의 표정·링과 상태 글자 색이 근무 상태를 말한다(초록 근무 중 · 앰버 연결 끊김 · 청회색 근무 안 함).
struct NowStatusCard: View {
    let card: NowMyCard
    let characterID: String?
    let onEditGoal: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            Text(NowFormat.clock(card.todaySeconds))
                .scaledFont(size: 48, weight: .semibold)
                .monospacedDigit()
                .kerning(-1)
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 12)
                .accessibilityLabel(Text("\(NowText.todayLabel) \(NowFormat.spokenDuration(card.todaySeconds))"))
            meter
                .padding(.top, 10)
        }
    }

    private var mood: CharacterMood {
        card.isWorking ? (card.isStale ? .lost : .working) : .off
    }

    @ViewBuilder
    private var top: some View {
        if typeSize.isAccessibilitySize {
            // 접근성 글자: 상태 글자가 초상 옆에서 한 글자씩 꺾이지 않게 아래 줄로 내린다.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    portrait
                    Spacer(minLength: 8)
                    editButton
                }
                stateText
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                portrait
                stateText
                Spacer(minLength: 8)
                editButton
            }
        }
    }

    private var portrait: some View {
        CharacterPortrait(id: characterID, mood: mood, size: 54)
    }

    private var stateText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.isWorking ? NowText.workingOnMac : NowText.notWorking)
                .font(.body.weight(.semibold))
                .foregroundStyle(stateColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(card.isStale ? MobileTheme.pending : MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateColor: Color {
        guard card.isWorking else { return MobileTheme.offWork }
        return card.isStale ? MobileTheme.pending : MobileTheme.working
    }

    private var subtitle: String {
        if card.isStale { return NowText.staleSubtitle }
        if card.isWorking, let started = card.sessionStartedAt { return NowText.sessionSince(NowFormat.clockTime(started)) }
        return NowText.offSubtitle
    }

    private var editButton: some View {
        Button(action: onEditGoal) {
            // 원 34pt(시안 `.b-ibtn`) · 누르는 칸 44pt.
            Image(systemName: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.label2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(MobileTheme.fill))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(-5)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(NowText.goalEdit))
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    weekText
                    Spacer(minLength: 8)
                    percentText
                }
                VStack(alignment: .leading, spacing: 2) {
                    weekText
                    percentText
                }
            }
            ProgressBar(card.progress, style: card.isGoalComplete ? .done : .accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.weekLine))
    }

    private var weekText: some View {
        let worked = Text(NowFormat.hoursMinutesText(card.weekSeconds))
            .fontWeight(.semibold)
            .foregroundStyle(MobileTheme.label)
        return Text("\(NowText.weekPrefix) \(worked) \(NowText.goalSuffix(hours: card.goalHours))")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var percentText: some View {
        Text("\(card.percent)%")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(card.isGoalComplete ? MobileTheme.working : MobileTheme.label)
            .fixedSize()
    }
}

// MARK: - 지금 근무 중

struct NowWorkingSection: View {
    let store: NowStore

    var body: some View {
        let now = store.context.clock.now()
        let people = store.workingPeople(now: now)
        let teammates = people.filter(\.isTeammate)
        let others = people.filter { !$0.isTeammate }
        let state = store.workingLoadState
        let header = NowSectionHeader(
            title: NowText.workingTitle(count: nil),
            trailing: state == .loaded ? NowText.peopleCount(people.count) : nil
        )
        if state != .loaded || people.isEmpty {
            Section {
                Group {
                    if state == .loading {
                        LoadingRow()
                    } else if state == .failed {
                        // 모르는데 "근무 중인 사람이 없어요"나 스피너를 보이지 않는다. 다시 시도는 내 카드 자리 버튼 · 당겨서 새로고침.
                        LoadFailureRow(NowText.workingUnavailable, retry: nil)
                    } else {
                        Text(NowText.workingEmpty)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                    }
                }
                .cardSegmentRow(.single)
                .id(NowTab.workingSectionID)
            } header: {
                header
            } footer: {
                NowWorkingFooter()
            }
        } else if !teammates.isEmpty, !others.isEmpty {
            // 우리 팀 · 다른 팀은 그룹 두 장(시안 02 — 사이 12pt).
            Section {
                NowWorkingGroup(store: store, label: NowText.ourTeam, people: teammates, anchorID: NowTab.workingSectionID)
            } header: {
                header
            }
            .listSectionSpacing(12)
            Section {
                NowWorkingGroup(store: store, label: NowText.otherTeams, people: others, anchorID: nil)
            } footer: {
                NowWorkingFooter()
            }
        } else {
            Section {
                NowWorkingGroup(store: store, label: teammates.isEmpty ? NowText.otherTeams : NowText.ourTeam, people: people, anchorID: NowTab.workingSectionID)
            } header: {
                header
            } footer: {
                NowWorkingFooter()
            }
        }
    }
}

/// 절 아래 한 줄 "근무 시작과 종료는 맥 앱에서 해요"(시안 `.b-foot`).
struct NowWorkingFooter: View {
    var body: some View {
        Text(NowText.workingFooter)
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 8, leading: MobileTheme.titleMargin, bottom: 12, trailing: MobileTheme.titleMargin))
    }
}

/// 한 그룹(인셋 그룹 한 장): 이름 줄 "우리 팀 · 3명" + 사람 줄들. 구분선은 글자 시작점(64pt)부터.
struct NowWorkingGroup: View {
    let store: NowStore
    let label: String
    let people: [NowWorkingPerson]
    /// 데모 장면 `working` 이 스크롤해 갈 자리(첫 그룹만).
    let anchorID: String?

    static let dividerLeading: CGFloat = 64

    var body: some View {
        let count = people.count + 1
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(NowText.peopleCount(people.count))
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(MobileTheme.label2)
        .cardSegmentRow(
            .of(index: 0, count: count),
            padding: EdgeInsets(top: 12, leading: MobileTheme.cardPadding, bottom: 4, trailing: MobileTheme.cardPadding),
            dividerLeading: Self.dividerLeading
        )
        .id(anchorID ?? label)
        ForEach(Array(people.enumerated()), id: \.element.id) { offset, person in
            NowWorkingRow(person: person, clock: store.context.clock) {
                store.context.router.open(.message(peerID: person.id))
            }
            .cardSegmentRow(.of(index: 1 + offset, count: count), dividerLeading: Self.dividerLeading)
        }
    }
}

/// 사람 한 줄(시안 B 사람 행): 이니셜 원 + 상태 점(초록 · 앰버) · 이름 뒤 센터 배지 · (끊김 부제) · 오른쪽 = 우리 팀 경과 / 다른 팀 말 걸기.
struct NowWorkingRow: View {
    let person: NowWorkingPerson
    let clock: MobileClock
    let onTalk: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // 접근성 글자 크기: 한 줄에 아바타 · 이름 · 배지 · 시간을 두면 이름이 한 글자씩 세로로 꺾였다(AX5 스크린샷 실측).
                // 첫 줄은 아바타 · 이름(+ 다른 팀 말 걸기 버튼), 끊김 부제와 우리 팀 경과는 아랫줄로 내린다.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        avatar
                        PersonName(person.name, center: person.center)
                        if !person.isTeammate {
                            Spacer(minLength: 8)
                            trailing
                        }
                    }
                    if person.isStale { staleText }
                    if person.isTeammate { trailing }
                }
            } else {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        PersonName(person.name, center: person.center)
                        if person.isStale { staleText }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    private var avatar: some View {
        PersonAvatar(name: person.name, status: person.isStale ? .pending : .working, url: person.avatarURL, size: 36)
    }

    private var staleText: some View {
        let relative = person.lastSeenAt.map { MobileRelativeTime.text(for: $0, now: clock.now()) }
        return Text(NowText.staleLastSeen(relative))
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.pending)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        if person.isTeammate {
            // 경과는 분 단위라 1분마다만 다시 그린다. 신호가 끊긴 사람은 스토어가 멈춘 값을 준다.
            TimelineView(.everyMinute) { _ in
                let seconds = elapsed(now: clock.now())
                Text(NowFormat.hoursMinutesText(seconds))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
                    .accessibilityLabel(Text("근무 \(NowFormat.spokenDuration(seconds))째"))
            }
        } else {
            Button(action: onTalk) {
                Image(systemName: "bubble.left")
                    .font(.body)
                    // 기호는 XXXL 에서 멈춘다(누르는 칸은 44pt 그대로) — 접근성 크기에서 카드 끝을 넘었다(AX3 실측).
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(MobileTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.vertical, -4)
            .padding(.trailing, -12)
            .accessibilityLabel(Text(NowText.talkTo(person.name)))
        }
    }

    private func elapsed(now: Date) -> Int {
        if person.isStale { return person.elapsedSeconds ?? 0 }
        guard let startedAt = person.startedAt else { return person.elapsedSeconds ?? 0 }
        return max(0, Int(now.timeIntervalSince(startedAt)))
    }
}
#endif
