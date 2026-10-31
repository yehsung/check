#if os(iOS)
import CheckCore
import SwiftUI

// 폰 아잉 큐브 로비·방이 함께 쓰는 줄: 받은 초대·공개 방 한 줄 · 판돈 고르기 · 사람 절 · [초대] 판돈 시트.
// 판정은 전부 `GamesRummyLobbyPlan`(맥 스위트가 값으로 잰다) — 여기는 배치만 한다.

/// 받은 초대 · 공개 방 한 줄(맥 `RummyJoinCard`). 초대는 버튼 둘을 아래 줄에(판돈이 걸린 수락·거절이라 크게 — 테트리스 받은 신청과 같다),
/// 공개 방은 사람 행처럼 한 줄에 [앉기]를 둔다(세 칸이 다 큰 버튼이면 첫 화면이 이 절로 찬다 — 실화면에서 봤다). 큰 글자에서는 쌓는다.
struct GamesRummyJoinableRow: View {
    let store: GamesStore
    let item: GamesRummyJoinable
    let isLast: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    private var rummy: RummyStore { store.rummy }

    private var block: GamesRummyLobbyPlan.JoinBlock? {
        GamesRummyLobbyPlan.joinBlock(item, balance: store.rubyBalance, hasRoom: rummy.myRoom != nil,
                                      isWorking: rummy.isWorking, blockedBy: store.rummyEntryBlock)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: MobileTheme.space3) { avatar; info }
                if !item.isInvite { joinButton(GamesRummyText.take, kind: .tinted, size: .md, fillsWidth: true) }
            } else if item.isInvite {
                HStack(spacing: MobileTheme.space3) {
                    avatar
                    info
                    Spacer(minLength: 0)
                    seatFaces
                }
            } else {
                // 좁으면(320pt · 긴 이름) 얼굴을 접는다 — 인원은 줄 글자가 말한다.
                ViewThatFits(in: .horizontal) {
                    openRow(showsFaces: true)
                    openRow(showsFaces: false)
                }
            }
            if item.isInvite { inviteButtons }
        }
        .padding(.horizontal, MobileTheme.cardPadding)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(MobileTheme.separator).frame(height: MobileTheme.hairline)
                    .padding(.leading, MobileTheme.cardPadding)
            }
        }
    }

    private func openRow(showsFaces: Bool) -> some View {
        HStack(spacing: MobileTheme.space3) {
            avatar
            info.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            if showsFaces { seatFaces }
            joinButton(GamesRummyText.take, kind: .tinted, size: .sm, fillsWidth: false)
                .fixedSize()
        }
    }

    private var avatar: some View {
        PersonAvatar(name: item.hostName, colorSeed: item.room.host?.id.uuidString.lowercased() ?? item.hostName,
                     url: item.room.host?.avatarUrl.flatMap(URL.init(string:)),
                     userID: item.room.host?.id.uuidString.lowercased(), size: 36,
                     characterHint: item.room.host?.character)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            PersonName(item.title)
            HStack(spacing: 4) {
                GamesStakeLine(stake: item.room.stake ?? 0, prefix: nil)
                Text("· \(item.seatsText)").monospacedDigit()
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            if let text = GamesRummyLobbyPlan.joinBlockText(block) {
                Text(text)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.danger)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.joinableAccessibility(title: item.title, stake: item.room.stake ?? 0, seats: item.seatsText))
        .accessibilityValue(GamesRummyLobbyPlan.joinBlockText(block) ?? "")
    }

    /// 앉은 사람 얼굴(겹침). 꾸밈이라 보이스오버는 건너뛴다 — 인원은 줄 글자가 말한다.
    private var seatFaces: some View {
        HStack(spacing: -6) {
            ForEach(item.joinedSeats.prefix(4)) { seat in
                PersonAvatar(name: seat.displayName ?? "?", colorSeed: seat.userId.uuidString.lowercased(),
                             url: seat.avatarUrl.flatMap(URL.init(string:)), userID: seat.userId.uuidString.lowercased(),
                             size: 22, characterHint: seat.character)
                    .overlay(Circle().stroke(MobileTheme.surface, lineWidth: 1.5))
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var inviteButtons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            AingButton(GamesRummyText.decline, kind: .gray, size: .md, fillsWidth: true) {
                rummy.decline(item.id)
            }
            .disabled(rummy.isWorking)
            joinButton(GamesRummyText.join, kind: .filled, size: .md, fillsWidth: true)
        }
    }

    private func joinButton(_ title: String, kind: AingButtonStyle.Kind, size: AingButtonMetrics.Size, fillsWidth: Bool) -> some View {
        AingButton(title, kind: kind, size: size, fillsWidth: fillsWidth) {
            guard block == nil else { return }
            rummy.join(item.id)
        }
        .disabled(block != nil)
    }
}

/// 판돈 칸 셋 + 공개 여부 스위치 — 로비 새 탁자 카드와 [초대] 시트가 **같은 값**(`selectedStake` · `createPublic`)을 고친다.
/// 값을 코어에 두는 까닭: 결과 [한 판 더]도, 방 없이 [초대]도 그 값으로 방을 만든다.
struct GamesRummyTableOptions: View {
    let store: GamesStore
    /// 고르지 않은 칸의 바탕(카드 안은 `fill`, 시트 바탕 위는 `surface`).
    var tileFill: Color = MobileTheme.surface

    @Environment(\.dynamicTypeSize) private var typeSize

    private var rummy: RummyStore { store.rummy }
    private var stakes: [Int] { GamesRummyLobbyPlan.stakes(rummy.lobby) }

    var body: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space3) {
            // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(오목 AX 실측).
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 8) { ForEach(stakes, id: \.self) { stakeTile($0) } }
                } else {
                    HStack(spacing: 8) { ForEach(stakes, id: \.self) { stakeTile($0) } }
                }
            }
            Text(GamesRummyText.stakeCaption(rummy.selectedStake))
                .font(MobileTheme.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: Binding(get: { rummy.createPublic }, set: { rummy.createPublic = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(GamesRummyText.publicLabel)
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                    Text(rummy.createPublic ? GamesRummyText.publicOn : GamesRummyText.publicOff)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                }
            }
            .tint(MobileTheme.accentFill)
        }
    }

    private func stakeTile(_ stake: Int) -> some View {
        let isSelected = rummy.selectedStake == stake
        let affordable = GamesRummyLobbyPlan.affordable(stake: stake, balance: store.rubyBalance)
        let shape = RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous)
        return Button {
            rummy.selectedStake = GamesRummyLobbyPlan.selecting(stake, current: rummy.selectedStake, stakes: stakes)
        } label: {
            RubyPrice(stake, isShort: !affordable, gemSize: 18, style: .headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(shape.fill(isSelected ? MobileTheme.accentTint : tileFill))
                .overlay(shape.strokeBorder(isSelected ? MobileTheme.accent : Color.clear, lineWidth: 2))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        // 모자란 판돈도 **고를 수는 있다**(왜 안 되는지 카드가 말한다). 막으면 고른 값이 이미 모자란 창에서 빠져나올 말이 없다.
        .accessibilityLabel(GamesRummyText.stakeOption(stake))
        .accessibilityValue(isSelected ? GamesRummyText.selected : (affordable ? "" : GamesRummyText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 사람 절 — 초대 가능 · 지금은 바빠요 · 접힌 '업데이트 필요'. 로비 [사람] 탭과 방(방장)이 함께 쓴다.
struct GamesRummyPeopleSection: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    let onInvite: (RummyLobbyUser) -> Void

    @State private var outdatedExpanded = false

    private var rummy: RummyStore { store.rummy }
    private var people: GamesRummyLobbyPlan.People { GamesRummyLobbyPlan.people(rummy.lobby?.users ?? []) }
    private var room: RummyRoom? { rummy.myRoom }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(GamesRummyText.peopleCaption(inRoom: room != nil, amHost: RummyExitPolicy.amHost(rummy)))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space3)
            switch GamesRummyLobbyPlan.peoplePlaceholder(lobby: rummy.lobby, failed: rummy.lobbyLoadFailed) {
            case .rows:
                lists
            case .empty:
                message { Text(GamesRummyText.emptyUsers).font(.subheadline).foregroundStyle(MobileTheme.label2) }
            case .failed:
                message { LoadFailureRow(GamesRummyText.usersLoadFailed) { Task { await rummy.refreshLobby() } } }
            case .loading:
                message { LoadingRow(GamesRummyText.loadingUsers) }
            }
        }
        .onAppear {
            // 데모 스크린샷 전용: 합성 입력 없이 펴진 접기를 찍는 길.
            #if DEBUG
            if store.demoRummyRoute?.scene == .lobbyBusy { outdatedExpanded = true }
            #endif
        }
    }

    private func message(@ViewBuilder _ content: () -> some View) -> some View {
        InsetGroup {
            GroupRow(divider: .none) {
                content()
                Spacer(minLength: 0)
            }
        }
        .padding(.top, MobileTheme.space2)
    }

    @ViewBuilder
    private var lists: some View {
        let people = people
        if !people.ready.isEmpty {
            SectionHeader(GamesRummyText.readyHeader, trailing: .text(GamesRummyText.people(people.ready.count)), padded: true)
            InsetGroup { rows(people.ready, dimmed: false) }
        }
        if !people.busy.isEmpty {
            SectionHeader(GamesRummyText.busyHeader, trailing: .text(GamesRummyText.people(people.busy.count)), padded: true)
            InsetGroup { rows(people.busy, dimmed: true) }
        }
        if !people.outdated.isEmpty {
            InsetGroup {
                outdatedFold(count: people.outdated.count, hasRowsBelow: outdatedExpanded)
                if outdatedExpanded { rows(people.outdated, dimmed: true) }
            }
            .padding(.top, MobileTheme.space4)
        }
    }

    private func rows(_ users: [RummyLobbyUser], dimmed: Bool) -> some View {
        ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
            GamesRummyPersonRow(
                user: user,
                action: GamesRummyLobbyPlan.personAction(user: user, room: room, amHost: RummyExitPolicy.amHost(rummy),
                                                         isWorking: rummy.isWorking, calling: inviteQueue.pending,
                                                         blockedBy: store.rummyEntryBlock),
                dimmed: dimmed,
                isLast: index == users.count - 1,
                onInvite: { onInvite(user) }
            )
        }
    }

    private func outdatedFold(count: Int, hasRowsBelow: Bool) -> some View {
        Button {
            outdatedExpanded.toggle()
        } label: {
            GroupRow(divider: hasRowsBelow ? .inset(MobileTheme.cardPadding) : .none) {
                Image(systemName: "arrow.down.app")
                    .foregroundStyle(MobileTheme.pending)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(GamesRummyText.outdatedFold(count, expanded: outdatedExpanded))
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(GamesRummyText.outdatedHint)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: outdatedExpanded ? "chevron.down" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.label3Text)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// 사람 한 줄. 큰 글자: 버튼을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾인다(오목·체스 실측).
struct GamesRummyPersonRow: View {
    let user: RummyLobbyUser
    let action: GamesRummyLobbyPlan.PersonAction
    let dimmed: Bool
    let isLast: Bool
    let onInvite: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var name: String { user.displayName ?? "?" }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MobileTheme.space3) { avatar; info }
                    trailing
                }
            } else {
                avatar
                info
                Spacer(minLength: 8)
                trailing
            }
        }
    }

    private var avatar: some View {
        PersonAvatar(name: name, colorSeed: user.id.uuidString.lowercased(),
                     status: user.isWorking == true ? .working : nil,
                     url: user.avatarUrl.flatMap(URL.init(string:)), userID: user.id.uuidString.lowercased(), size: 36,
                     characterHint: user.character)
            .opacity(dimmed ? 0.55 : 1)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            PersonName(name)
            Text(GamesRummyLobbyPlan.statusText(user))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(user.capable == true ? MobileTheme.label2 : MobileTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        switch action {
        case .hidden:
            EmptyView()
        case .invite(let enabled):
            AingButton(GamesRummyText.invite, kind: enabled ? .tinted : .gray, size: .sm, action: onInvite)
                .fixedSize()
                .disabled(!enabled)
                .accessibilityHint(GamesRummyText.inviteHint(name: name))
        case .tag(let text):
            AingChip(text: text, tint: MobileTheme.working)
        }
    }
}

/// 방 없이 누른 [초대]의 판돈 시트(폰 체스·테트리스 `…StakeSheet` 와 같은 모양). 판돈은 **시작할 때** 걷는다 — 여기서 빠지지 않는다.
/// 체스·테트리스와 달리 처음부터 판돈이 골라져 있다: 이 값은 로비 새 탁자 카드에 늘 보이고, 코어가 쥔 한 값이다.
struct GamesRummyInviteSheet: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    let target: RummyLobbyUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var rummy: RummyStore { store.rummy }
    private var name: String { target.displayName ?? "?" }

    private var block: GamesRummyLobbyPlan.TableBlock? {
        GamesRummyLobbyPlan.tableBlock(stake: rummy.selectedStake, balance: store.rubyBalance,
                                       hasMatch: rummy.match != nil || rummy.myRoom != nil,
                                       isWorking: rummy.isWorking, blockedBy: store.rummyEntryBlock)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GamesRummyText.inviteSheetTitle, subtitle: GamesRummyText.inviteSheetPrompt(name: name),
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        GroupRow(divider: .none, minHeight: 64) {
                            PersonAvatar(name: name, colorSeed: target.id.uuidString.lowercased(),
                                         status: target.isWorking == true ? .working : nil,
                                         url: target.avatarUrl.flatMap(URL.init(string:)),
                                         userID: target.id.uuidString.lowercased(), size: 44, characterHint: target.character)
                            VStack(alignment: .leading, spacing: 1) {
                                PersonName(name)
                                Text(GamesRummyText.createHint)
                                    .font(MobileTheme.rowSubtitle)
                                    .foregroundStyle(MobileTheme.label2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    GamesRummyTableOptions(store: store)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    HStack(spacing: 6) {
                        Text(GamesRummyText.myRuby)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                        if let balance = store.rubyBalance {
                            RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                        } else {
                            Text(GamesRummyText.unknownNumber).font(.footnote).foregroundStyle(MobileTheme.label2)
                        }
                    }
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    if block == .short, let balance = store.rubyBalance {
                        Text(GamesRummyText.stakeShort(stake: rummy.selectedStake, balance: balance))
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
            AingButton(GamesRummyText.openAndCall(stake: rummy.selectedStake), kind: .filled, size: .lg, fillsWidth: true) {
                guard block == nil else { return }
                dismiss()
                inviteQueue.invite(target.id, store: rummy)
            }
            .disabled(block != nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        // 큰 글자: 중간 높이에는 판돈 칸이 안 들어와 사람 카드와 버튼만 보였다(실화면에서 봤다).
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

#endif
