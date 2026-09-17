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
                                .cardListPlainRow(top: 0, bottom: 0)
                        }
                    }
                    NowStatusSection(store: store, onEditGoal: { isGoalSheetPresented = true })
                    NowTodoSection(store: store)
                    NowWorkingSection(store: store)
                        .id(NowTab.workingSectionID)
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
            // 카드 모양은 다른 탭의 `AingCard` 와 같게(반경 16 · 1px 테두리) — 시스템 절 모양을 쓰지 않는다.
            .cardSegmentRow(.single)
        } header: {
            Text(MobileRelativeTime.headerDate(store.context.clock.now()))
                .font(.title3.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
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
                        // 원은 글자 크기를 따르되 누르는 칸은 44pt 이상(원만 누르게 하면 기본 글자에서 36pt 였다 — 스크린샷 실측).
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileTheme.accent)
                            .padding(10)
                            .background(Circle().fill(MobileTheme.cardElevated))
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    // 칸은 44pt 로 키우되 카드 높이는 원(36pt) 기준 그대로 — 위아래 4pt 는 줄 간격 쪽으로 내민다.
                    .padding(.vertical, -4)
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
        let state = store.workingLoadState
        // 행 자리(카드 조각): [우리 팀 이름 · 팀원…] [다른 팀 · 사람…] 을 한 장으로 잇는다.
        let othersStart = teammates.isEmpty ? 0 : 1 + teammates.count
        let rowCount = othersStart + (others.isEmpty ? 0 : 1 + others.count)
        Section {
            if state == .loading {
                LoadingRow()
                    .cardSegmentRow(.single)
            } else if state == .failed {
                // 모르는데 "근무 중인 사람이 없어요"나 스피너를 보이지 않는다. 다시 시도는 내 카드 자리 버튼 · 당겨서 새로고침.
                LoadFailureRow(NowText.workingUnavailable, retry: nil)
                    .cardSegmentRow(.single)
            } else if people.isEmpty {
                Text(NowText.workingEmpty)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .cardSegmentRow(.single)
            } else {
                if !teammates.isEmpty {
                    NowGroupLabel(text: store.membership?.teamName ?? NowText.ourTeam, position: .of(index: 0, count: rowCount))
                    ForEach(Array(teammates.enumerated()), id: \.element.id) { offset, person in
                        NowWorkingRow(person: person, clock: store.context.clock)
                            .cardSegmentRow(.of(index: 1 + offset, count: rowCount))
                    }
                }
                if !others.isEmpty {
                    NowGroupLabel(text: NowText.otherTeams, position: .of(index: othersStart, count: rowCount))
                    ForEach(Array(others.enumerated()), id: \.element.id) { offset, person in
                        NowWorkingRow(person: person, clock: store.context.clock)
                            .cardSegmentRow(.of(index: othersStart + 1 + offset, count: rowCount))
                    }
                }
            }
        } header: {
            Text(NowText.workingTitle(count: state == .loaded ? people.count : nil))
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct NowGroupLabel: View {
    let text: String
    let position: CardSegmentPosition

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MobileTheme.secondaryText)
            .accessibilityAddTraits(.isHeader)
            .cardSegmentRow(
                position,
                padding: EdgeInsets(top: 12, leading: MobileTheme.cardPadding, bottom: 2, trailing: MobileTheme.cardPadding),
                separatorVisible: false
            )
    }
}

struct NowWorkingRow: View {
    let person: NowWorkingPerson
    let clock: MobileClock
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // 접근성 글자 크기: 한 줄에 아바타 · 이름 · 배지 · 시간을 두면 이름과 "서울"이 한 글자씩 세로로 꺾였다(AX5 스크린샷 실측).
                // 이름은 아바타 옆 한 줄을 통째로 쓰고, 배지 · 끊김 · 시간은 아랫줄로 내린다(줄바꿈이 필요하면 다시 아래로).
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        AvatarView(name: person.name, url: person.avatarURL, size: 36)
                        nameText
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) { detailItems }
                        VStack(alignment: .leading, spacing: 4) { detailItems }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    AvatarView(name: person.name, url: person.avatarURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            nameText
                            CenterBadge(person.center).fixedSize()
                        }
                        if person.isStale { staleText }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var nameText: some View {
        Text(person.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(MobileTheme.primaryText)
            .lineLimit(2)
    }

    private var staleText: some View {
        Text(NowText.connectionLost)
            .font(.caption)
            .foregroundStyle(MobileTheme.pending)
            .fixedSize()
    }

    @ViewBuilder
    private var detailItems: some View {
        CenterBadge(person.center).fixedSize()
        if person.isStale { staleText }
        trailing
    }

    @ViewBuilder
    private var trailing: some View {
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

    private func elapsed(now: Date) -> Int {
        if person.isStale { return person.elapsedSeconds ?? 0 }
        guard let startedAt = person.startedAt else { return person.elapsedSeconds ?? 0 }
        return max(0, Int(now.timeIntervalSince(startedAt)))
    }
}
#endif
