import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 **방**(설계서 §5). 맥 `RummyTableCard`·`RummyTableStage` 의 내용을 세로로 옮겼다: 맥은 가로 타원 양옆에 의자가 서지만(폭 740) 폰 폭엔 안 들어간다.
//
// ── 탁자 배치 ──
// `GamesRummyRoomStageLayout` 이 칸을 값으로 낸다(맥 스위트가 320·393·430pt 에서 겹침을 잰다 — 폰 뷰는 맥 스위트가 못 본다).
// 의자는 탁자 네 변에 걸터앉고, 저마다 카드 바탕이 있다: 절반은 펠트 위 · 절반은 화면 바탕 위라 바탕 없는 글자는 라이트·다크 어디서든 한쪽이 안 읽힌다.
// 의자 순서는 코어 `RummyTableSeating`(`[아래(나), 왼, 위, 오른]`) 한 곳이다 — 판 화면 상대 줄과 같은 차례다.
//
// ── 판정 ──
// 아래 `GamesRummyRoomPlan` 은 `#if os(iOS)` 밖이다. 나가기(방장 확인·손님 나가기)는 화면 `onExit` 한 곳이 가른다 — 이 파일이 `leave` 를 직접 부르지 않는다.

/// 방의 **순수 판정**.
package enum GamesRummyRoomPlan {
    /// [시작]은 **서버가 어차피 거절할 것**만 막는다: 2명 미만(`not_enough_players`) · 내 판돈 모자람(`insufficient`) · 다른 게임 중(`busy`) · 다른 동작 비행 중.
    /// 잔액을 모르면 막지 않는다.
    package static func canStart(joined: Int, stake: Int, balance: Int?, isWorking: Bool, blockedBy other: GamesBusyGame?) -> Bool {
        joined >= 2 && !isWorking && other == nil && GamesRummyLobbyPlan.affordable(stake: stake, balance: balance)
    }

    /// [시작] 글자. 1명일 때 "1명으로 시작"이라고 말하면 눌릴 것처럼 읽힌다.
    package static func startTitle(joined: Int) -> String {
        joined >= 2 ? GamesRummyText.startWith(joined) : GamesRummyText.start
    }

    /// 상금·분배 표시의 인원 — 혼자 앉아 있어도 2명 기준을 보인다(맥과 같다).
    package static func players(joined: Int) -> Int { max(joined, 2) }

    /// 서버 말(`notice`)이 없을 때 방 아래 안내 한 줄: 내 판돈 → 기다리는 까닭 순서.
    package static func hint(amHost: Bool, joined: Int, stake: Int, balance: Int?) -> String? {
        if !GamesRummyLobbyPlan.affordable(stake: stake, balance: balance) { return GamesRummyText.startBlockedShort }
        if !amHost { return GamesRummyText.startHintGuest }
        return joined >= 2 ? nil : GamesRummyText.startHintHost
    }

    /// 닫히기까지 남은 초(올림). 방이 아니면 nil.
    package static func remainingSeconds(_ remaining: TimeInterval?) -> Int? {
        remaining.map { max(0, Int($0.rounded(.up))) }
    }

    /// 남은 시간이 급한가(맥 `urgentBelow: 60` 과 같다).
    package static func isUrgent(seconds: Int) -> Bool { seconds <= 60 }
}

/// 방 탁자의 칸(값). 폭만 받는다 — 높이는 고정이고 스크롤이 받는다.
package struct GamesRummyRoomStageLayout: Equatable, Sendable {
    package static let chair = CGSize(width: 88, height: 98)
    /// 위·아래 의자와 가운데 칸 사이.
    package static let gap: CGFloat = 6
    /// 가운데 칸 높이(상금 + 식 + 분배 세 줄).
    package static let centerHeight: CGFloat = 118

    package let width: CGFloat

    package init(width: CGFloat) { self.width = width }

    package var height: CGFloat { Self.chair.height * 2 + Self.centerHeight + Self.gap * 2 }

    /// 탁자 — 의자가 네 변에 절반씩 걸터앉는다.
    package var table: CGRect {
        CGRect(x: Self.chair.width / 2, y: Self.chair.height / 2,
               width: width - Self.chair.width, height: height - Self.chair.height)
    }

    /// 탁자 가운데 글자 칸 — 왼·오른 의자에 안 닿는 폭.
    package var center: CGRect {
        CGRect(x: Self.chair.width + Self.gap, y: Self.chair.height + Self.gap,
               width: width - (Self.chair.width + Self.gap) * 2, height: Self.centerHeight)
    }

    /// 의자 `index`(`[아래, 왼, 위, 오른]` — 코어 `RummyTableSeating`).
    package func chair(_ index: Int) -> CGRect {
        let size = Self.chair
        let midX = (width - size.width) / 2
        let midY = (height - size.height) / 2
        switch index {
        case 0: return CGRect(x: midX, y: height - size.height, width: size.width, height: size.height)
        case 1: return CGRect(x: 0, y: midY, width: size.width, height: size.height)
        case 2: return CGRect(x: midX, y: 0, width: size.width, height: size.height)
        default: return CGRect(x: width - size.width, y: midY, width: size.width, height: size.height)
        }
    }
}

#if os(iOS)

/// 아잉 큐브 방 — 탁자 · 안내 · [시작]·[나가기] · 부를 사람(방장).
/// 입력: `store` · `inviteQueue` · `onExit`([나가기] — 방장 확인·손님 나가기는 화면 한 곳이 가른다).
struct GamesRummyRoomView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    let onExit: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private static let peopleAnchor = "rummy-room-people"

    private var rummy: RummyStore { store.rummy }
    private var room: RummyRoom? { rummy.myRoom }
    private var amHost: Bool { RummyExitPolicy.amHost(rummy) }
    private var joined: Int { (room?.seats ?? []).filter { $0.state == .joined }.count }
    private var stake: Int { room?.stake ?? 0 }

    private var chairs: [RummyTableChair] {
        let me = GamesMeIdentity.current(store.context)
        let myID = store.context.session.session.flatMap { UUID(uuidString: $0.userID) }
        return GamesRummySeating.chairs(room: room, myUserID: myID, myName: me.name ?? GamesRummyText.me,
                                        myAvatarURL: nil, myCharacter: me.characterID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    table { withAnimation { proxy.scrollTo(Self.peopleAnchor, anchor: .top) } }
                    hint
                    actions
                    if amHost {
                        GamesRummyPeopleSection(store: store, inviteQueue: inviteQueue) { user in
                            inviteQueue.invite(user.id, store: rummy)
                        }
                        .padding(.top, MobileTheme.space2)
                        .id(Self.peopleAnchor)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
            .refreshable { await rummy.refreshLobby() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { rummy.rulesShown = true } label: { Image(systemName: "book") }
                        .accessibilityLabel(GamesRummyText.rulesButton)
                }
            }
        }
    }

    // MARK: 머리

    /// 판돈 · 공개 여부 · 닫히기까지. 좁으면(320pt · 큰 글자) 남은 시간이 아래 줄로 내려간다.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
                Spacer(minLength: 4)
                GamesRummyRoomCountdown(rummy: rummy)
            }
            VStack(alignment: .leading, spacing: 6) {
                chips
                GamesRummyRoomCountdown(rummy: rummy)
            }
        }
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            AingChip(text: GamesRummyText.stake(stake), tint: MobileTheme.goldText)
            AingChip(text: room?.isPublic == true ? GamesRummyText.publicOn : GamesRummyText.publicOff,
                     tint: room?.isPublic == true ? MobileTheme.working : MobileTheme.label2,
                     background: room?.isPublic == true ? nil : MobileTheme.fill)
        }
        .fixedSize()
    }

    // MARK: 탁자

    @ViewBuilder
    private func table(onInviteTap: @escaping () -> Void) -> some View {
        if typeSize.isAccessibilitySize {
            // 큰 글자: 둘러앉은 그림에는 글자가 안 들어간다(의자 88pt) — 줄로 푼다. 상금·분배는 위에 말한다.
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                potText(onFelt: false)
                InsetGroup {
                    let visible = chairs.filter { $0.kind == .person }
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, chair in
                        GamesRummySeatRow(chair: chair, isLast: index == visible.count - 1)
                    }
                }
            }
            .padding(.top, MobileTheme.space3)
        } else {
            GeometryReader { geometry in
                GamesRummyTableStage(layout: GamesRummyRoomStageLayout(width: geometry.size.width), chairs: chairs,
                                     inviteHint: amHost, onInviteTap: onInviteTap) {
                    potText(onFelt: true)
                }
            }
            .frame(height: GamesRummyRoomStageLayout(width: 0).height)
            .padding(.top, MobileTheme.space3)
        }
    }

    /// 상금(판돈 × 인원) + 등수 분배(순수익). 펠트는 라이트·다크 모두 어둡다.
    private func potText(onFelt: Bool) -> some View {
        let players = GamesRummyRoomPlan.players(joined: joined)
        let primary: Color = onFelt ? .white : MobileTheme.label
        let secondary: Color = onFelt ? .white.opacity(0.82) : MobileTheme.label2
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                RubyIcon(size: 17, scalesWithText: !onFelt)
                Text(GamesRummyText.potTotal(stake: stake, players: players))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(primary)
            }
            Text(GamesRummyText.potFormula(stake: stake, players: players))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(secondary)
            VStack(spacing: 1) {
                ForEach(GamesRummyText.splitLines(players: players, stake: stake), id: \.self) { line in
                    Text(line)
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(secondary)
            .padding(.top, 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: 안내 · 동작

    @ViewBuilder
    private var hint: some View {
        if let notice = rummy.notice {
            // '초대를 보냈어요' 만 좋은 소식이다 — 나머지는 전부 거절·실패 말이다.
            InlineNotice(text: notice, kind: notice == RummyNoticeText.invited ? .info : .warning)
                .padding(.top, MobileTheme.rowSpacing)
        } else if let playing = store.rummyEntryBlock {
            InlineNotice(text: ChessPhoneText.entryBlockNotice(playing: playing.text, blocked: .rummy) ?? "", kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        } else if let text = GamesRummyRoomPlan.hint(amHost: amHost, joined: joined, stake: stake, balance: store.rubyBalance) {
            Text(text)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    private var actions: some View {
        VStack(spacing: MobileTheme.space2) {
            if amHost {
                AingButton(GamesRummyRoomPlan.startTitle(joined: joined), systemImage: "play.fill", kind: .filled, size: .lg,
                           fillsWidth: true) {
                    rummy.startGame()
                }
                .disabled(!GamesRummyRoomPlan.canStart(joined: joined, stake: stake, balance: store.rubyBalance,
                                                       isWorking: rummy.isWorking, blockedBy: store.rummyEntryBlock))
            }
            AingButton(GamesRummyText.leave, systemImage: "rectangle.portrait.and.arrow.right", kind: .gray, size: .md,
                       fillsWidth: true, action: onExit)
                .disabled(rummy.isWorking)
        }
        .padding(.top, MobileTheme.rowSpacing)
    }
}

/// 닫히기까지 남은 시간 — **잎 뷰**(초 단위 값은 잎만 읽는다 · 스토어 규약 ⑦). 시각은 `rummy.clock()` 으로 묻는다: 데모의 시계는 고정이라 `TimelineView` 날짜를 쓰면 데모 방이 늘 0초로 그려진다.
private struct GamesRummyRoomCountdown: View {
    let rummy: RummyStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let seconds = GamesRummyRoomPlan.remainingSeconds(rummy.roomRemaining(at: rummy.clock())) {
                let urgent = GamesRummyRoomPlan.isUrgent(seconds: seconds)
                HStack(spacing: 4) {
                    Image(systemName: "hourglass").accessibilityHidden(true)
                    Text(GamesRummyText.closesIn(seconds)).monospacedDigit()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(urgent ? MobileTheme.danger : MobileTheme.label2)
                .fixedSize()
            }
        }
    }
}

/// 둘러앉은 탁자. 칸은 `GamesRummyRoomStageLayout` 이 낸다.
private struct GamesRummyTableStage<Center: View>: View {
    let layout: GamesRummyRoomStageLayout
    let chairs: [RummyTableChair]
    let inviteHint: Bool
    let onInviteTap: () -> Void
    @ViewBuilder let center: Center

    var body: some View {
        ZStack(alignment: .topLeading) {
            GamesRummyTableSurface(cornerRadius: 44)
                .frame(width: layout.table.width, height: layout.table.height)
                .offset(x: layout.table.minX, y: layout.table.minY)
            center
                .frame(width: layout.center.width, height: layout.center.height)
                .offset(x: layout.center.minX, y: layout.center.minY)
            ForEach(Array(chairs.prefix(4).enumerated()), id: \.offset) { index, chair in
                let frame = layout.chair(index)
                GamesRummyChairView(chair: chair, inviteHint: inviteHint, onInviteTap: onInviteTap)
                    .frame(width: frame.width, height: frame.height)
                    .anchorPreference(key: GamesRummySeatAnchorKey.self, value: .bounds) { anchor in
                        chair.seatNo.map { [$0: anchor] } ?? [:]
                    }
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }
}

private struct GamesRummyChairView: View {
    let chair: RummyTableChair
    let inviteHint: Bool
    let onInviteTap: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous) }

    var body: some View {
        switch chair.kind {
        case .person: person
        case .empty: empty
        }
    }

    private var person: some View {
        VStack(spacing: 3) {
            PersonAvatar(name: chair.name, colorSeed: chair.userID?.uuidString.lowercased() ?? chair.name,
                         url: chair.avatarURL.flatMap(URL.init(string:)), userID: chair.userID?.uuidString.lowercased(),
                         size: 40, characterHint: chair.character)
                .opacity(chair.dimmed ? 0.5 : 1)
                .overlay(alignment: .top) {
                    if chair.isHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MobileTheme.gold)
                            .offset(y: -9)
                            .accessibilityHidden(true)
                    }
                }
            Text(chair.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tag = chair.tag {
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(chair.dimmed ? MobileTheme.label2 : (chair.isHost ? MobileTheme.goldText : MobileTheme.working))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(chair.isMe ? MobileTheme.accent : MobileTheme.separator, lineWidth: chair.isMe ? 1.5 : MobileTheme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.chairAccessibility(name: chair.name, tag: chair.tag))
    }

    /// 빈 의자. 방장이면 눌러서 아래 '부를 사람'으로 간다 — [초대]라고 적어 놓고 안 눌리면 고장으로 읽힌다.
    @ViewBuilder
    private var empty: some View {
        if inviteHint {
            Button(action: onInviteTap) { emptyBody(GamesRummyText.emptyChairInvite, tint: MobileTheme.accent, showsPlus: true) }
                .buttonStyle(.plain)
        } else {
            // 손님의 빈자리엔 [+]가 없다 — 눌리지 않는 자리다.
            emptyBody(GamesRummyText.emptySeat, tint: MobileTheme.label2, showsPlus: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func emptyBody(_ title: String, tint: Color, showsPlus: Bool) -> some View {
        VStack(spacing: 4) {
            if showsPlus {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(title).font(.caption.weight(.bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).foregroundStyle(tint.opacity(0.7)))
        .contentShape(shape)
    }
}

/// 큰 글자의 자리 한 줄.
private struct GamesRummySeatRow: View {
    let chair: RummyTableChair
    let isLast: Bool

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            PersonAvatar(name: chair.name, colorSeed: chair.userID?.uuidString.lowercased() ?? chair.name,
                         url: chair.avatarURL.flatMap(URL.init(string:)), userID: chair.userID?.uuidString.lowercased(),
                         size: 36, characterHint: chair.character)
                .opacity(chair.dimmed ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                PersonName(chair.name)
                if let tag = chair.tag {
                    Text(tag)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#endif
