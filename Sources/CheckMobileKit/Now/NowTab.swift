#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 지금 탭 화면(SPEC-ios §3.2): 날짜 머리 · 내 상태 카드(오늘 누적 · 이번 주 목표) · 오늘 할 일 · 지금 근무 중.
/// 경로는 `router.pathBinding(for: .now)`, 딥링크(`aingcheck://now` — 위젯 탭)는 `consumePendingRoute(for: .now)` 로 꺼낸다.
struct NowTab: View {
    let store: NowStore
    @State private var isGoalSheetPresented = false

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .now)) {
            ScrollViewReader { proxy in
                List {
                    if let notice = store.notice {
                        Section {
                            InlineNotice(text: notice, kind: .warning)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    NowStatusSection(store: store, onEditGoal: { isGoalSheetPresented = true })
                    NowTodoSection(store: store)
                    NowWorkingSection(store: store)
                        .id(NowTab.workingSectionID)
                }
                #if DEBUG
                .task {
                    guard store.context.isDemo, NowDemoStage.stages().contains("working"), await NowDemoStage.waitForData(store) else { return }
                    proxy.scrollTo(NowTab.workingSectionID, anchor: .top)
                }
                #endif
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                // 묶음 이름 줄("다른 팀")이 44pt 빈 행처럼 보이지 않게 — 다른 행은 내용이 이보다 높다.
                .environment(\.defaultMinListRowHeight, 30)
                .scrollContentBackground(.hidden)
                .background(MobileTheme.background.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.refreshNow() }
                .navigationTitle(NowText.title)
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

    private func consumeRoute() {
        // aingcheck://now(위젯 탭)는 탭 자체다 — 이 탭은 쌓는 화면이 없으니 꺼내 비우기만 한다(라우터가 이미 탭을 골랐다).
        _ = store.context.router.consumePendingRoute(for: .now)
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
        } header: {
            Text(MobileRelativeTime.headerDate(store.context.clock.now()))
                .font(.title3.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(MobileTheme.card)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.hasNoTeam {
            VStack(alignment: .leading, spacing: 6) {
                Text(NowText.noTeamTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.primaryText)
                Text(NowText.noTeamBody)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else if let card = store.myCard(now: now) {
            NowStatusCard(card: card, teamName: store.membership?.teamName, onEditGoal: onEditGoal)
        } else {
            LoadingRow()
        }
    }
}

struct NowStatusCard: View {
    let card: NowMyCard
    let teamName: String?
    let onEditGoal: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 접근성 글자 크기에서는 팀 이름을 아래 줄로 내린다 — 한 줄에 두면 상태 문구가 두 줄로 꺾이고 점이 어긋난다(스크린샷 실측).
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    statusLine
                    teamLabel
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    statusLine
                    Spacer(minLength: 8)
                    teamLabel
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(NowText.todayLabel)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.secondaryText)
                Text(NowFormat.clock(card.todaySeconds))
                    .font(MobileTheme.number(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(NowText.todayLabel) \(NowFormat.spokenDuration(card.todaySeconds))"))
            VStack(alignment: .leading, spacing: 8) {
                NowProgressBar(progress: card.progress, tint: card.isGoalComplete ? MobileTheme.working : MobileTheme.accent)
                HStack(alignment: .center, spacing: 8) {
                    Text(card.weekLine)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(action: onEditGoal) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileTheme.accent)
                            .padding(10)
                            .background(Circle().fill(MobileTheme.cardElevated))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(NowText.goalEdit))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 점은 글자와 같은 글꼴의 기호라 기준선에 앉고 글자 크기를 따라 커진다(고정 10pt 원은 AX 크기에서 글자 발치에 붙었다 — 스크린샷 실측).
            Image(systemName: "circle.fill")
                .font(.subheadline)
                .imageScale(.small)
                .foregroundStyle(card.isWorking ? (card.isStale ? MobileTheme.pending : MobileTheme.working) : MobileTheme.offWork)
                .accessibilityHidden(true)
            Text(card.isWorking ? NowText.workingOnMac : NowText.notWorking)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if card.isStale {
                NowChip(text: NowText.connectionLost, tint: MobileTheme.pending)
            }
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var teamLabel: some View {
        if let teamName {
            Text(teamName)
                .font(.caption)
                .foregroundStyle(MobileTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct NowProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MobileTheme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct NowChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
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
        let loading = !store.hasLoadedTeam && !store.hasNoTeam && !store.hasLoadedDirectory
        Section {
            if loading {
                LoadingRow()
            } else if people.isEmpty {
                Text(NowText.workingEmpty)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .padding(.vertical, 4)
            } else {
                if !teammates.isEmpty {
                    NowGroupLabel(text: store.membership?.teamName ?? NowText.ourTeam)
                    ForEach(teammates) { person in
                        NowWorkingRow(person: person, clock: store.context.clock)
                    }
                }
                if !others.isEmpty {
                    NowGroupLabel(text: NowText.otherTeams)
                    ForEach(others) { person in
                        NowWorkingRow(person: person, clock: store.context.clock)
                    }
                }
            }
        } header: {
            Text(NowText.workingTitle(count: people.count))
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(MobileTheme.card)
    }
}

struct NowGroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MobileTheme.secondaryText)
            .listRowInsets(EdgeInsets(top: 12, leading: MobileTheme.sideMargin, bottom: 0, trailing: MobileTheme.sideMargin))
            .listRowSeparator(.hidden, edges: .bottom)
            .accessibilityAddTraits(.isHeader)
    }
}

struct NowWorkingRow: View {
    let person: NowWorkingPerson
    let clock: MobileClock

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: person.name, url: person.avatarURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MobileTheme.primaryText)
                        .lineLimit(2)
                    CenterBadge(person.center)
                }
                if person.isStale {
                    Text(NowText.connectionLost)
                        .font(.caption)
                        .foregroundStyle(MobileTheme.pending)
                }
            }
            Spacer(minLength: 8)
            if person.isTeammate {
                // 경과 h:mm 는 분 단위라 1분마다만 다시 그린다. 신호가 끊긴 사람은 스토어가 멈춘 값을 준다.
                TimelineView(.everyMinute) { _ in
                    let seconds = elapsed(now: clock.now())
                    Text(NowFormat.hoursMinutes(seconds))
                        .font(MobileTheme.number(.body))
                        .monospacedDigit()
                        .foregroundStyle(person.isStale ? MobileTheme.pending : MobileTheme.working)
                        .fixedSize()
                        .accessibilityLabel(Text("근무 \(NowFormat.spokenDuration(seconds))째"))
                }
            } else {
                NowChip(text: NowText.workingChip, tint: MobileTheme.working)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func elapsed(now: Date) -> Int {
        if person.isStale { return person.elapsedSeconds ?? 0 }
        guard let startedAt = person.startedAt else { return person.elapsedSeconds ?? 0 }
        return max(0, Int(now.timeIntervalSince(startedAt)))
    }
}
#endif
