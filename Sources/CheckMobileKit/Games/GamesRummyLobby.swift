import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 **로비**(설계서 §5). 맥 `RummyLobbyView` 의 내용을 폰 관례(테트리스·체스 로비: 머리 두 칸 · 탭 · 카드 절)로 다시 놓았다.
// 맥은 로비와 방이 한 화면이지만 폰은 코어 `phase` 로 갈린다 — 방은 `GamesRummyRoom.swift`.
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesRummyLobbyPlan`)은 `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 한 줄도 못 보므로 "모자란 판돈으로 방이 만들어졌다" · "다른 게임 중에 앉았다" 를 재는 그물을 걸 자리가 여기뿐이다.
// 버튼을 끄는 판단은 **서버가 어차피 거절할 것**만 본다(맥과 같다): 나머지 거절은 스토어 `notice` 가 말한다.
//
// ── 잔액 ──
// 서버 `rummy_create`·`rummy_join` 이 판돈을 잔액과 대 본다(`insufficient`). **잔액을 모르면 막지 않는다**(테트리스 `GamesTetrisStakeSelection` 과 같은 규약).
//
// ── 게이트 ──
// `rummy_capable` 은 **초대할 때만** 본다(설계서 §9) — 방 만들기·공개 방 참가는 서버 게이트가 닫혀 있어도 된다. 그래서 '업데이트 필요'는 사람 행의 [초대]만 막는다.

/// 받은 초대 또는 공개 방 한 줄.
package struct GamesRummyJoinable: Identifiable, Equatable, Sendable {
    package let room: RummyRoom
    package let isInvite: Bool
    package var id: UUID { room.id }

    package var joinedSeats: [RummyRoomSeat] { (room.seats ?? []).filter { $0.state == .joined } }
    package var maxSeats: Int { room.maxSeats ?? 4 }
    package var freeSeats: Int { max(0, maxSeats - joinedSeats.count) }
    package var hostName: String { room.host?.displayName ?? "?" }

    package var title: String {
        isInvite ? GamesRummyText.called(by: hostName) : GamesRummyText.publicTable(of: hostName)
    }

    package var seatsText: String {
        isInvite ? GamesRummyText.seats(joinedSeats.count, max: maxSeats) : GamesRummyText.freeSeats(freeSeats)
    }
}

/// 로비의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다.
package enum GamesRummyLobbyPlan {
    /// 판돈 표의 주인은 서버다. 로비를 받기 전에는 맥과 같은 기본값을 보인다.
    package static let defaultStakes = [3, 5, 10]

    package static func stakes(_ lobby: RummyLobby?) -> [Int] {
        guard let stakes = lobby?.stakes, !stakes.isEmpty else { return defaultStakes }
        return stakes
    }

    /// 이 판돈을 걸 수 있는가. **잔액을 모르면(nil) 막지 않는다** — 서버가 거절하면 그때 안내한다.
    package static func affordable(stake: Int, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake
    }

    // MARK: 받은 초대 + 공개 방

    /// 초대 먼저 · 서버 순서 · 같은 방은 한 번 · 지금 앉은 방은 뺀다(맥 `RummyLobbyView.joinables`).
    package static func joinables(lobby: RummyLobby?, myRoomID: UUID?) -> [GamesRummyJoinable] {
        let invites = (lobby?.invites ?? []).filter { $0.id != myRoomID }
        let invited = Set(invites.map(\.id))
        let rooms = (lobby?.publicRooms ?? []).filter { $0.id != myRoomID && !invited.contains($0.id) }
        return invites.map { GamesRummyJoinable(room: $0, isInvite: true) }
            + rooms.map { GamesRummyJoinable(room: $0, isInvite: false) }
    }

    /// [참가]·[앉기]를 막는 까닭(없으면 nil). 글자가 필요한 것은 `joinBlockText` 가 말한다 — 다른 게임은 로비 위 안내가 말한다.
    package enum JoinBlock: Equatable, Sendable {
        case otherGame, hasRoom, working, full, short
    }

    package static func joinBlock(_ item: GamesRummyJoinable, balance: Int?, hasRoom: Bool, isWorking: Bool,
                                  blockedBy other: GamesBusyGame?) -> JoinBlock? {
        if other != nil { return .otherGame }
        if hasRoom { return .hasRoom }
        if isWorking { return .working }
        if item.joinedSeats.count >= item.maxSeats { return .full }
        if !affordable(stake: item.room.stake ?? 0, balance: balance) { return .short }
        return nil
    }

    package static func joinBlockText(_ block: JoinBlock?) -> String? {
        switch block {
        case .full: return GamesRummyText.roomFullShort
        case .short: return GamesRummyText.stakeShortfall
        case .otherGame, .hasRoom, .working, nil: return nil
        }
    }

    // MARK: 새 탁자

    /// [탁자 열기]·시트의 [열고 부르기]를 막는 까닭(없으면 nil). 요청이 나가는 **마지막 문**이다 — 시트가 떠 있는 동안 판이 서거나 방이 생긴 틈도 막는다.
    package enum TableBlock: Equatable, Sendable {
        case otherGame, hasMatch, working, short
    }

    package static func tableBlock(stake: Int, balance: Int?, hasMatch: Bool, isWorking: Bool,
                                   blockedBy other: GamesBusyGame?) -> TableBlock? {
        if other != nil { return .otherGame }
        if hasMatch { return .hasMatch }
        if isWorking { return .working }
        return affordable(stake: stake, balance: balance) ? nil : .short
    }

    /// 판돈 칸을 눌렀다 — **값이 표 안에 있을 때만** 적는다(서버 표 밖 값이 `invalid` 로 튕기지 않게).
    package static func selecting(_ tapped: Int, current: Int, stakes: [Int]) -> Int {
        stakes.contains(tapped) ? tapped : current
    }

    // MARK: 사람 목록

    package struct People: Equatable, Sendable {
        package var ready: [RummyLobbyUser] = []
        package var busy: [RummyLobbyUser] = []
        package var outdated: [RummyLobbyUser] = []

        package var isEmpty: Bool { ready.isEmpty && busy.isEmpty && outdated.isEmpty }
    }

    /// 서버 정렬(근무 중 → 가능 → 이름)을 지키며 셋으로 나눈다. `capable` 이 nil 이면 **불가**로 읽는다(`RummyLobbyUser` 약속).
    package static func people(_ users: [RummyLobbyUser]) -> People {
        var result = People()
        for user in users {
            if user.capable != true {
                result.outdated.append(user)
            } else if user.inMatch == true || user.focusMode == true {
                result.busy.append(user)
            } else {
                result.ready.append(user)
            }
        }
        return result
    }

    /// 사람 행 부제: 구버전 > 게임 중 > 집중 > 근무 중 > 쉬는 중.
    package static func statusText(_ user: RummyLobbyUser) -> String {
        if user.capable != true { return GamesRummyText.statusOutdated }
        if user.inMatch == true { return GamesRummyText.statusInMatch }
        if user.focusMode == true { return GamesRummyText.statusFocus }
        return user.isWorking == true ? GamesRummyText.statusWorking : GamesRummyText.statusIdle
    }

    package enum PersonAction: Equatable, Sendable {
        case hidden
        case invite(enabled: Bool)
        case tag(String)
    }

    /// 사람 행 오른쪽. 방이 없으면 [초대](= 탁자 열고 부르기) · 내 방(방장)이면 [초대]·'초대함'·'참가함' · 남의 방이면 없음.
    /// 코어 스토어 동작은 한 번에 하나라 `isWorking` 이면 잠근다. 줄에 선 사람은 '부르는 중'.
    package static func personAction(user: RummyLobbyUser, room: RummyRoom?, amHost: Bool, isWorking: Bool,
                                     calling: [UUID], blockedBy other: GamesBusyGame?) -> PersonAction {
        if calling.contains(user.id) { return .tag(GamesRummyText.calling) }
        let canInvite = user.capable == true && user.inMatch != true && user.focusMode != true
            && !isWorking && other == nil
        guard let room else {
            return user.capable == true ? .invite(enabled: canInvite) : .hidden
        }
        guard amHost else { return .hidden }
        let seats = room.seats ?? []
        if let seat = seats.first(where: { $0.userId == user.id }) {
            switch seat.state {
            case .joined: return .tag(GamesRummyText.joined)
            case .invited: return .tag(GamesRummyText.invited)
            default: break
            }
        }
        guard user.capable == true else { return .hidden }
        let joined = seats.filter { $0.state == .joined }.count
        return .invite(enabled: canInvite && joined < (room.maxSeats ?? 4))
    }

    /// 사람 목록 자리를 무엇으로 채우는가. 받은 적이 있는지는 `lobby` 가 말한다(공용 규칙 — 들고 있는 줄을 실패로 지우지 않는다).
    package static func peoplePlaceholder(lobby: RummyLobby?, failed: Bool) -> MobileLoadKnowledge.Placeholder {
        MobileLoadKnowledge.placeholder(hasRows: !(lobby?.users ?? []).isEmpty, hasLoaded: lobby != nil, lastFailed: failed)
    }

    /// 머리 칸의 내 전적. 로비를 못 받았으면 "판 수 0"이라고 지어내지 않는다.
    package static func recordText(_ me: RummyLobbyMe?) -> String {
        guard let me else { return GamesRummyText.unknownNumber }
        return GamesRummyText.record(games: me.games, wins: me.wins)
    }

    /// 탭 글자. 받은 초대는 [사람] 탭 안에 있어서, 순위를 보는 동안 온 초대가 묻히지 않게 탭 글자가 말한다.
    package static func tabTitle(_ tab: GamesRummyLobbyTab, inviteCount: Int) -> String {
        tab == .people && inviteCount > 0 ? GamesRummyText.peopleTabWithInvites(inviteCount) : tab.title
    }

    /// 받은 초대·공개 방이 없다는 한 줄을 그려도 되는가 — 아직 모르거나 못 받았는데 "없어요" 쪽으로 말하지 않는다.
    package static func showsJoinEmpty(lobby: RummyLobby?, failed: Bool, count: Int) -> Bool {
        count == 0 && lobby != nil && !failed
    }
}

#if os(iOS)

/// 아잉 큐브 로비 — 받은 초대·공개 방 · 머리 두 칸 · 안내 · 새 탁자 · 탭 [사람 | 순위].
/// 입력: `store`(`store.rummy` · `store.rummyEntryBlock` · `store.context`) · `inviteQueue` · `tab`.
struct GamesRummyLobbyView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    @Binding var tab: GamesRummyLobbyTab

    /// [초대] → 판돈 시트의 대상(방이 없을 때만 — 방이 있으면 곧바로 부른다).
    @State private var inviteTarget: RummyLobbyUser?

    private var rummy: RummyStore { store.rummy }
    private var myUserID: String? { store.context.session.session?.userID.lowercased() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ★ 탭이 **위**다(테트리스·체스는 절 아래). 큐브 로비는 받은 초대·공개 방·새 탁자가 더 있어서 절 아래에 두면 [순위]가 첫 화면에서 안 보였다(실화면에서 봤다).
                summary
                notice
                blockedByOtherGame
                tabPicker
                switch tab {
                case .people:
                    joinSection
                    newTable
                    GamesRummyPeopleSection(store: store, inviteQueue: inviteQueue, onInvite: invite)
                case .ranking:
                    GamesRummyRankingSection(store: rummy, myUserID: myUserID)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await rummy.refreshLobby()
            if tab == .ranking { await rummy.loadRanking() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { rummy.rulesShown = true } label: { Image(systemName: "book") }
                    .accessibilityLabel(GamesRummyText.rulesButton)
            }
        }
        .sheet(item: $inviteTarget) { target in
            GamesRummyInviteSheet(store: store, inviteQueue: inviteQueue, target: target)
        }
        // 방이 서면 로비가 사라진다 — 열려 있던 시트를 들고 있으면 로비로 돌아올 때 되살아난다.
        .onChange(of: rummy.phase) { _, _ in inviteTarget = nil }
        .onAppear(perform: applyDemoSheet)
        .onChange(of: rummy.lobby != nil) { _, _ in applyDemoSheet() }
    }

    /// 데모 스크린샷 전용: `games/rummy/lobby/sheet` 면 첫 초대 가능한 사람의 판돈 시트를 연다(합성 입력 없이 시트를 찍는 길). Release 에서는 한 줄도 돌지 않는다.
    private func applyDemoSheet() {
        #if DEBUG
        guard store.demoRummyRoute?.scene == .lobbySheet, inviteTarget == nil else { return }
        inviteTarget = GamesRummyLobbyPlan.people(rummy.lobby?.users ?? []).ready.first
        #endif
    }

    /// 방이 없으면 판돈을 고르는 시트를 먼저 연다(설계서 §5). 방이 있으면 줄이 곧바로 부른다.
    private func invite(_ user: RummyLobbyUser) {
        if rummy.myRoom == nil {
            inviteTarget = user
        } else {
            inviteQueue.invite(user.id, store: rummy)
        }
    }

    // MARK: 받은 초대 + 공개 방

    /// ★ [사람] 탭 맨 위다. 받은 초대가 이 화면에서 가장 급한 사실이다(폰엔 맥의 전역 배너가 없다).
    @ViewBuilder
    private var joinSection: some View {
        let items = GamesRummyLobbyPlan.joinables(lobby: rummy.lobby, myRoomID: rummy.myRoom?.id)
        if !items.isEmpty {
            SectionHeader(GamesRummyText.joinHeader, trailing: .text(GamesRummyText.places(items.count)), padded: true)
            InsetGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GamesRummyJoinableRow(store: store, item: item, isLast: index == items.count - 1)
                }
            }
        }
    }

    // MARK: 머리 두 칸

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(GamesRummyText.recordLabel) {
                    Text(GamesRummyLobbyPlan.recordText(rummy.lobby?.me))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(GamesRummyText.myRuby) {
                    if let balance = store.rubyBalance {
                        RubyPrice(balance, isShort: false, style: .headline)
                    } else {
                        Text(GamesRummyText.unknownNumber).font(.headline).foregroundStyle(MobileTheme.label)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, MobileTheme.rowSpacing)
    }

    private func summaryCell(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            value()
        }
        .padding(.horizontal, MobileTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notice: some View {
        if let text = rummy.notice {
            InlineNotice(text: text, kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        } else if let text = store.rummyLeftByTabNotice {
            // 스스로 나온 사실을 말하는 줄이라 경고가 아니다.
            InlineNotice(text: text, kind: .info)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    /// 한 사람 한 판 — 버튼만 흐려 두면 **왜**인지 알 길이 없다. 두 줄(왜 · 언제 풀리는지)은 문구 표가 조립한다.
    @ViewBuilder
    private var blockedByOtherGame: some View {
        if let playing = store.rummyEntryBlock {
            InlineNotice(text: ChessPhoneText.entryBlockNotice(playing: playing.text, blocked: .rummy) ?? "", kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    // MARK: 새 탁자

    private var newTable: some View {
        let block = GamesRummyLobbyPlan.tableBlock(stake: rummy.selectedStake, balance: store.rubyBalance,
                                                   hasMatch: rummy.match != nil || rummy.myRoom != nil,
                                                   isWorking: rummy.isWorking, blockedBy: store.rummyEntryBlock)
        let showsJoinEmpty = GamesRummyLobbyPlan.showsJoinEmpty(
            lobby: rummy.lobby, failed: rummy.lobbyLoadFailed,
            count: GamesRummyLobbyPlan.joinables(lobby: rummy.lobby, myRoomID: rummy.myRoom?.id).count)
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(GamesRummyText.newTable, padded: true)
            InsetGroup {
                GamesRummyTableOptions(store: store, tileFill: MobileTheme.fill)
                    .padding(MobileTheme.cardPadding)
                VStack(alignment: .leading, spacing: MobileTheme.space2) {
                    if block == .short, let balance = store.rubyBalance {
                        Text(GamesRummyText.stakeShort(stake: rummy.selectedStake, balance: balance))
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AingButton(GamesRummyText.openTable, systemImage: "plus", kind: .filled, size: .md, fillsWidth: true) {
                        guard block == nil else { return }
                        rummy.createRoom()
                    }
                    .disabled(block != nil)
                }
                .padding(.horizontal, MobileTheme.cardPadding)
                .padding(.bottom, MobileTheme.cardPadding)
            }
            if showsJoinEmpty {
                Text(GamesRummyText.joinEmpty)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    .padding(.top, MobileTheme.space2)
            }
        }
    }

    // MARK: 탭 둘

    private var tabPicker: some View {
        Picker(GamesRummyText.title, selection: $tab) {
            ForEach(GamesRummyLobbyTab.allCases, id: \.self) { value in
                Text(GamesRummyLobbyPlan.tabTitle(value, inviteCount: rummy.incomingInvites.count)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.top, MobileTheme.rowSpacing)
        // 탭을 고른 그 순간. 판정은 한 곳이다(뷰가 단계·중복을 다시 적지 않는다).
        .onChange(of: tab) { _, value in GamesRummyRankingPlan.refreshIfNeeded(rummy, tab: value) }
    }
}

#endif
