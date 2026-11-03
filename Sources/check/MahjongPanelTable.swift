import SwiftUI
import CheckCore

// MARK: - 아잉 마작 판 화면 (SPEC §5.2 판 · §5.3 탁자)
//
// 본문 1200×660(창 머리글 없음 — 큐브 0.3.70): INFO · CL [역][점수표] · TOP SEAT · CR [규칙][나가기] · AIDS · 좌우 자리 카드 ·
// FELT(884×502, 안에 536×502 탁자 덩어리) · MY SEAT · HAND · ACTIONS. 사각형은 모두 `MahjongMatchLayout` 한 곳.
//
// ── 탁자 약속 ──
//  · 방위 `MahjongSeatCompass` — 나 아래, **하가 오른쪽**, 대면 위, 상가 왼쪽(큐브와 반대).
//  · 강은 바람개비(주인 기준 왼쪽 모서리부터 6장씩 3줄, 셋째 줄은 넘치면 옆으로) · 강·상대 손 띠·도라 판은 **띠마다 Canvas 한 장**.
//  · 가운데 판: 국 이름 · 본장·공탁 · 남은 패 · 도라 5칸(열린 것만 앞면) · 네 변의 바람 · 리치봉 · **차례인 사람 쪽 변에 빛줄**
//    (phase turn 일 때만). `wait` 에는 아무 쪽도 아니고, 멈춤 끝(`wake_at_ms`)을 1.5초 넘기면 누구인지 없이 "기다리는 중…" 하나.
//  · 남의 시계는 링으로 그리지 않는다(남의 예비를 모른다 — CC-25). 차례인 남의 카드는 테두리 **색**만 느리게 맥동(숫자 없음).
//  · 펠트·칸·덮개는 중간 톤(최대 채널 ≤ 234, 최소 ≥ 56), 패 몸체만 극단 — `.shadow` 금지.

/// 펠트 색(중간 톤 — 렌더 감지기 규칙). 큐브 펠트(남보라)와 구별되는 청록.
enum MahjongFeltStyle {
    // 채널 폭 < 40 · 최대 ≤ 234 · 최소 ≥ 56 — 렌더 시험의 '잉크'(유채색·밝은 글자)로 세지지 않는 중간 톤.
    static let felt = Color(red: 0.24, green: 0.39, blue: 0.36)
    static let rim = Color(red: 0.32, green: 0.46, blue: 0.44)
    static let board = Color(red: 0.31, green: 0.45, blue: 0.43)
    static let boardRim = Color(red: 0.44, green: 0.58, blue: 0.56)
    static let glyph = Color(red: 0.86, green: 0.84, blue: 0.80)
}

/// 강·손 띠 배치(순수 — 시험이 되묻는다). 좌표는 탁자 덩어리(536×502) 좌표.
enum MahjongTableGeometry {
    static let riverTile = MahjongTileSize.river
    static let rowLength = 6

    /// 한 자리의 강 패들. `highlightLast` 면 마지막 패(울려 가지 않았으면)를 강조한다(방금 버린 사람).
    static func river(_ discards: [MahjongDiscard], compass: MahjongCompass, highlightLast: Bool = false) -> [MahjongStripTile] {
        let rect = MahjongMatchLayout.river(compass)
        let w = riverTile.width, h = riverTile.height
        let base = MahjongTileArtModel.rotation(for: compass)
        var out: [MahjongStripTile] = []
        var u: CGFloat = 0
        var row = 0
        for (index, discard) in discards.enumerated() {
            let nextRow = min(2, index / rowLength)
            if nextRow != row { row = nextRow; u = 0 }
            let sideways = discard.riichi == true
            let lw = sideways ? h : w, lh = sideways ? w : h
            let v = CGFloat(row) * h + (sideways ? h - w : 0)
            let screen: CGRect
            switch compass {
            case .bottom: screen = CGRect(x: rect.minX + u, y: rect.minY + v, width: lw, height: lh)
            case .top: screen = CGRect(x: rect.maxX - u - lw, y: rect.maxY - v - lh, width: lw, height: lh)
            case .right: screen = CGRect(x: rect.minX + v, y: rect.maxY - u - lw, width: lh, height: lw)
            case .left: screen = CGRect(x: rect.maxX - v - lh, y: rect.minY + u, width: lh, height: lw)
            }
            var state: MahjongTileState = discard.taken == true ? .taken : (discard.tsumogiri == true ? .tsumogiri : .normal)
            if highlightLast, index == discards.count - 1, discard.taken != true { state = .highlighted }
            out.append(MahjongStripTile(face: MahjongTileFace(discard.tile), size: riverTile, state: state,
                                        rotation: (base + (sideways ? 1 : 0)) % 4, origin: screen.origin))
            u += lw
        }
        return out
    }

    /// 상대 손 띠: 뒷면 18×24 × `hand_count` + 부로 24×32(주인 기준 오른쪽 끝). 띠 가운데 맞춤.
    static func handStrip(count: Int, melds: [MahjongWireMeld], compass: MahjongCompass) -> [MahjongStripTile] {
        guard let rect = MahjongMatchLayout.handStripRect(compass) else { return [] }
        let base = MahjongTileArtModel.rotation(for: compass)
        // 주인 좌표의 한 줄: (면, 크기, 가로 눕힘, 앞 간격)
        var items: [(face: MahjongTileFace, size: MahjongTileSize, sideways: Bool, lead: CGFloat)] = []
        for _ in 0..<max(0, count) { items.append((.back, .back, false, 0)) }
        for (mi, meld) in melds.enumerated() {
            for (ti, tile) in meld.tiles.enumerated() {
                let closedEnd = meld.type == "ankan" && (ti == 0 || ti == meld.tiles.count - 1)
                let sideways = meld.called != nil && tile == meld.called
                items.append((closedEnd ? .back : MahjongTileFace(tile), .smallMeld, sideways,
                              ti == 0 ? (mi == 0 && count > 0 ? 8 : 4) : 0))
            }
        }
        func length(_ item: (face: MahjongTileFace, size: MahjongTileSize, sideways: Bool, lead: CGFloat)) -> CGFloat {
            item.lead + (item.sideways ? item.size.height : item.size.width)
        }
        let total = items.reduce(0) { $0 + length($1) }
        let along = compass == .top ? rect.width : rect.height
        var u = (along - total) / 2
        var out: [MahjongStripTile] = []
        for item in items {
            u += item.lead
            let lw = item.sideways ? item.size.height : item.size.width
            let lh = item.sideways ? item.size.width : item.size.height
            let across = (MahjongMatchLayout.handStrip - lh) / 2
            let screen: CGRect
            switch compass {
            case .top: screen = CGRect(x: rect.maxX - u - lw, y: rect.minY + across, width: lw, height: lh)
            case .right: screen = CGRect(x: rect.minX + across, y: rect.maxY - u - lw, width: lh, height: lw)
            case .left: screen = CGRect(x: rect.minX + across, y: rect.minY + u, width: lh, height: lw)
            case .bottom: screen = .zero
            }
            out.append(MahjongStripTile(face: item.face, size: item.size, rotation: (base + (item.sideways ? 1 : 0)) % 4,
                                        origin: screen.origin))
            u += lw
        }
        return out
    }
}

// MARK: - 판 화면

struct MahjongTableView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let me: ChessPlayerFace
    var hoverIndex: Int? = nil
    /// 반응 말풍선(§5.3) — 창 루트가 쥔 공급기.
    var feed = MahjongReactionFeed()
    /// 스냅샷 전용 시각(앱 nil).
    var fixedNow: Date? = nil
    let onRules: (MahjongRulesTab) -> Void
    var onToLobby: () -> Void = {}
    var onRematch: () -> Void = {}

    private var mySeat: Int { payload.mySeat ?? 0 }
    private var match: MahjongStateMatch? { payload.match }

    private func seat(_ compass: MahjongCompass) -> MahjongStateSeat? {
        let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
        return payload.seats?.first { $0.seatNo == number }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            place(MahjongMatchLayout.info) { MahjongInfoBox(store: store, payload: payload) }
            place(MahjongMatchLayout.chromeLeft) {
                HStack(spacing: 8) {
                    MahjongCapsuleButton(title: MahjongText.yaku, tint: CheckTheme.secondaryText, filled: false) { onRules(.yaku) }
                    MahjongCapsuleButton(title: MahjongText.scoreTable, tint: CheckTheme.secondaryText, filled: false) {
                        onRules(.scores)
                    }
                    if canReact {
                        MahjongReactionButton(store: store, feed: feed, payload: payload)
                            .frame(width: MahjongMatchLayout.reactionButtonWidth)
                    }
                }
                .padding(.vertical, 7)
            }
            place(MahjongMatchLayout.topSeat) { seatCard(.top, style: .top) }
            place(MahjongMatchLayout.chromeRight) {
                HStack(spacing: 8) {
                    MahjongCapsuleButton(title: MahjongText.rules, tint: CheckTheme.secondaryText, filled: false) { onRules(.rules) }
                    MahjongCapsuleButton(title: store.isPractice ? MahjongText.practiceEnd : MahjongText.leave,
                                         tint: CheckTheme.danger, filled: false) {
                        if store.isPractice { store.endPractice() } else { Task { await store.leaveTable() } }
                    }
                }
                .padding(.vertical, 7)
            }
            place(MahjongMatchLayout.aids) { MahjongAidsBox(store: store) }
            place(MahjongMatchLayout.leftSeat) { seatCard(.left, style: .side) }
            place(MahjongMatchLayout.rightSeat) { seatCard(.right, style: .side) }
            place(MahjongMatchLayout.felt) { MahjongFeltView(store: store, payload: payload, fixedNow: fixedNow) }
            place(MahjongMatchLayout.mySeat) { seatCard(.bottom, style: .mine) }
            place(MahjongMatchLayout.hand) {
                MahjongHandView(store: store, payload: payload, hoverIndex: hoverIndex, fixedNow: fixedNow)
            }
            place(MahjongMatchLayout.actions) { MahjongActionsView(store: store, payload: payload) }
            overlays
        }
        .frame(width: MahjongMatchLayout.bodySize.width, height: MahjongMatchLayout.bodySize.height, alignment: .topLeading)
        // 반응 말풍선 — 자리 카드 앵커(`rummyReactionAnchor`) 위(큐브 덮개 그대로, 방위는 `compass:` 클로저).
        .rummyReactionLayer(bubbles: feed.bubbles, compass: { MahjongReactionCompass.of(seat: $0, mySeat: mySeat) },
                            fixedNow: fixedNow)
        .onChange(of: payload.reactions, initial: true) { _, _ in
            feed.ingest(payload, now: store.clock(), serverOffset: store.serverClockOffset)
        }
    }

    /// 반응을 보낼 수 있는 판 — 루비 판이 진행 중일 때만(연습판은 스토어가 보내지 않는다).
    private var canReact: Bool { !store.isPractice && match?.matchStatus == .active }

    @ViewBuilder
    private var overlays: some View {
        let felt = MahjongMatchLayout.felt
        if match?.matchStatus == .finished {
            MahjongMatchResultCard(store: store, payload: payload, onToLobby: onToLobby, onRematch: onRematch)
                .frame(width: 640, height: 440)
                .offset(x: felt.midX - 320, y: felt.midY - 220)
        } else if match?.phase == "hand_end", let result = payload.lastHand {
            MahjongHandResultCard(store: store, payload: payload, result: result)
                .frame(width: MahjongMatchLayout.handResultSize.width, height: MahjongMatchLayout.handResultSize.height)
                .offset(x: felt.midX - MahjongMatchLayout.handResultSize.width / 2,
                        y: felt.midY - MahjongMatchLayout.handResultSize.height / 2)
        }
        if let band = store.roomBand {
            MahjongRoomBandView(store: store, band: band)
                .frame(width: 520)
                .offset(x: felt.midX - 260, y: felt.minY + 8)
        }
    }

    private func place<Content: View>(_ rect: CGRect, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder
    private func seatCard(_ compass: MahjongCompass, style: MahjongSeatCard.Style) -> some View {
        if let seat = seat(compass) {
            MahjongSeatCard(store: store, payload: payload, seat: seat, style: style, me: compass == .bottom ? me : nil)
                .rummyReactionAnchor(seatNo: seat.seatNo, edge: MahjongReactionCompass.edge(compass))
        } else {
            Color.clear
        }
    }
}

/// INFO: 국 이름 · 판 길이 · 판돈(연습이면 "연습").
private struct MahjongInfoBox: View {
    let store: MahjongStore
    let payload: MahjongStatePayload

    var body: some View {
        let match = payload.match
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(MahjongText.roundName(round: match?.round, handNo: match?.handNo))
                    .font(.headline)
                Text(MahjongText.format(match?.formatKind) + (match?.extension == true ? " · 연장" : ""))
                    .font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 4)
            if store.isPractice {
                MahjongChip(text: MahjongText.practiceTitle, tint: CheckTheme.working)
            } else {
                HStack(spacing: 3) {
                    RubyIcon(size: 12)
                    Text("\(match?.stake ?? 0)").font(.callout.weight(.bold))
                }
            }
        }
        .padding(.horizontal, 12)
        .background(MahjongCardBackground())
    }
}

/// AIDS: 자동 화료 · 울지 않기 · 쯔모기리(보조 — 기기에 저장, 서버 판정과 무관).
private struct MahjongAidsBox: View {
    let store: MahjongStore

    var body: some View {
        HStack(spacing: 6) {
            toggle(MahjongText.aidAutoWin, on: store.aids.autoWin) { store.aids.autoWin.toggle() }
            toggle(MahjongText.aidNoCalls, on: store.aids.noCalls) { store.aids.noCalls.toggle() }
            toggle(MahjongText.aidTsumogiri, on: store.aids.tsumogiri) { store.aids.tsumogiri.toggle() }
        }
        .padding(.vertical, 8)
    }

    private func toggle(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(on ? .bold : .regular))
                .foregroundStyle(on ? Color.white : CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? CheckTheme.accent.opacity(0.7) : CheckTheme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 자리 카드

/// 자리 카드(큐브 `RummySeatCard` `.side/.top/.mine` 꼴 — private 라 베꼈다). 남의 카드엔 링·숫자가 없다(CC-25).
struct MahjongSeatCard: View {
    enum Style { case side, top, mine }

    let store: MahjongStore
    let payload: MahjongStatePayload
    let seat: MahjongStateSeat
    let style: Style
    /// 내 자리면 내 얼굴(앱 배선 값).
    var me: ChessPlayerFace?

    private var isMine: Bool { style == .mine }
    private var isTurn: Bool { payload.match?.phase == "turn" && payload.match?.turnSeat == seat.seatNo }
    private var name: String { seat.deleted == true ? MahjongText.deletedChip : (me?.name ?? seat.user?.displayName ?? "?") }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            switch style {
            case .top: top
            case .side: side
            case .mine: mine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(CheckTheme.panel.opacity(0.9)))
        .overlay {
            if isTurn, !isMine {
                // 남의 차례 — 테두리 색만 느리게 맥동(불투명도 아님, 숫자 없음).
                MahjongTick(store: store, interval: 0.25) { now in
                    let phase = (sin(now.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
                    shape.stroke(Color(red: 0.33 + 0.42 * phase, green: 0.67 - 0.05 * phase, blue: 1.0 - 0.45 * phase),
                                 lineWidth: 2)
                }
            } else {
                shape.stroke(isTurn ? CheckTheme.accent : CheckTheme.border, lineWidth: isTurn ? 2 : 1)
            }
        }
        .opacity(seat.deleted == true ? 0.55 : 1)
    }

    private func avatar(_ size: CGFloat) -> some View {
        CheckAvatarView(name: name, userID: seat.user?.userId,
                        avatarURL: (me?.avatarURL) ?? seat.user?.avatarUrl.flatMap(URL.init(string:)), size: size,
                        characterHint: me?.characterID ?? seat.user?.character)
    }

    @ViewBuilder
    private var chips: some View {
        MahjongChip(text: MahjongText.wind(seat.wind), tint: CheckTheme.secondaryText)
        if seat.isDealer == true { MahjongChip(text: MahjongText.dealerChip, tint: CheckTheme.pending, filled: true) }
        if seat.riichi == true { MahjongChip(text: MahjongText.riichiChip, tint: CheckTheme.accent, filled: true) }
        if seat.away == true { MahjongChip(text: MahjongText.autoChip, tint: CheckTheme.danger) }
    }

    private var score: some View {
        Text(MahjongText.score(seat.score))
            .font(.system(size: style == .top ? 17 : 20, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var top: some View {
        HStack(spacing: 8) {
            avatar(30)
            Text(name).font(.callout.weight(.semibold)).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
            score
            HStack(spacing: 3) { chips }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private var side: some View {
        VStack(spacing: 8) {
            avatar(52)
            Text(name).font(.callout.weight(.semibold)).lineLimit(1)
            score
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    MahjongChip(text: MahjongText.wind(seat.wind), tint: CheckTheme.secondaryText)
                    if seat.isDealer == true { MahjongChip(text: MahjongText.dealerChip, tint: CheckTheme.pending, filled: true) }
                }
                HStack(spacing: 3) {
                    if seat.riichi == true { MahjongChip(text: MahjongText.riichiChip, tint: CheckTheme.accent, filled: true) }
                    if seat.away == true { MahjongChip(text: MahjongText.autoChip, tint: CheckTheme.danger) }
                }
            }
        }
        .padding(10)
    }

    private var mine: some View {
        HStack(spacing: 8) {
            ZStack {
                MahjongMyClockRing(store: store, payload: payload, diameter: 56)
                avatar(44)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                score
                HStack(spacing: 3) {
                    MahjongChip(text: MahjongText.wind(seat.wind), tint: CheckTheme.secondaryText)
                    if seat.isDealer == true { MahjongChip(text: MahjongText.dealerChip, tint: CheckTheme.pending, filled: true) }
                }
                if seat.riichi == true || seat.away == true {
                    HStack(spacing: 3) {
                        if seat.riichi == true { MahjongChip(text: MahjongText.riichiChip, tint: CheckTheme.accent, filled: true) }
                        if seat.away == true { MahjongChip(text: MahjongText.autoChip, tint: CheckTheme.danger) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - 펠트

struct MahjongFeltView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    /// 스냅샷 전용 시각(움직임 한 장) — 앱 nil.
    var fixedNow: Date? = nil

    private var mySeat: Int { payload.mySeat ?? 0 }

    /// 방금 버린 사람(사건 꼬리의 마지막 버림).
    private var lastDiscarder: Int? {
        payload.events?.last(where: { $0.kind == "discard" })?.seat
    }

    var body: some View {
        let block = CGSize(width: MahjongMatchLayout.blockWidth, height: MahjongMatchLayout.blockHeight)
        let origin = MahjongMatchLayout.blockOrigin
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MahjongFeltStyle.felt)
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MahjongFeltStyle.rim, lineWidth: 3)
            ZStack(alignment: .topLeading) {
                // 강·상대 손 띠 — 움직임(버림·울기·깡)이 있을 때만 프레임이 돈다. 펠트에는 입력이 없다.
                MahjongMotionFrames(store: store, payload: payload, fixedNow: fixedNow) { motion, now in
                    ZStack(alignment: .topLeading) {
                        ForEach(MahjongCompass.allCases, id: \.self) { compass in
                            if let seat = seatRow(compass) {
                                seatStrips(seat, compass: compass, motion: motion, now: now, block: block)
                            }
                        }
                    }
                    .frame(width: block.width, height: block.height, alignment: .topLeading)
                }
                MahjongCenterBoard(store: store, payload: payload)
                    .frame(width: MahjongMatchLayout.centerSide, height: MahjongMatchLayout.centerSide)
                    .offset(x: MahjongMatchLayout.center.minX, y: MahjongMatchLayout.center.minY)
            }
            .frame(width: block.width, height: block.height, alignment: .topLeading)
            .offset(x: origin.x, y: origin.y)
        }
    }

    private func seatRow(_ compass: MahjongCompass) -> MahjongStateSeat? {
        let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
        return payload.seats?.first { $0.seatNo == number }
    }

    /// 한 자리의 강 + (남이면) 손 띠. 움직이는 패(방금 버린 패 · 방금 운 부로)는 띠에서 빼 따로 끝 자리 + 어긋남으로 그린다.
    @ViewBuilder
    private func seatStrips(_ seat: MahjongStateSeat, compass: MahjongCompass, motion: MahjongMotion?, now: Date,
                            block: CGSize) -> some View {
        let river = MahjongTableGeometry.river(seat.discards ?? [], compass: compass, highlightLast: lastDiscarder == seat.seatNo)
        let discarding = motion.flatMap { $0.kind == .discard && $0.to.compass == compass && !river.isEmpty ? $0 : nil }
        MahjongTileStrip(tiles: discarding == nil ? river : Array(river.dropLast()), size: block,
                         cornerLabels: store.aids.cornerLabels,
                         accessibilityText: "\(compassName(compass)) 버림패 \(seat.discards?.count ?? 0)장")
        if let discarding, let last = river.last {
            MahjongMovingTile(tile: last, offset: MahjongMotionPlan.offset(discarding, now: now),
                              tilt: MahjongMotionPlan.tilt(discarding, discard: seat.discards?.last, now: now),
                              cornerLabels: store.aids.cornerLabels)
                .frame(width: block.width, height: block.height, alignment: .topLeading)
        }
        if compass != .bottom {
            let strip = MahjongTableGeometry.handStrip(count: seat.handCount ?? 0, melds: seat.melds ?? [], compass: compass)
            let melding = motion.flatMap { MahjongMotionPlan.movesNewestMeld($0, compass: compass, melds: seat.melds ?? []) ? $0 : nil }
            let moving = melding == nil ? 0 : min(strip.count, seat.melds?.last?.tiles.count ?? 0)
            MahjongTileStrip(tiles: Array(strip.dropLast(moving)), size: block, cornerLabels: false,
                             accessibilityText: "\(compassName(compass)) 손 \(seat.handCount ?? 0)장 · 울음 \(seat.melds?.count ?? 0)")
            if let melding, moving > 0 {
                MahjongTileStrip(tiles: Array(strip.suffix(moving)), size: block, cornerLabels: false)
                    .offset(MahjongMotionPlan.offset(melding, now: now))
                    .accessibilityHidden(true)
            }
        }
    }

    private func compassName(_ compass: MahjongCompass) -> String {
        switch compass {
        case .bottom: "내"
        case .right: "오른쪽 상대"
        case .top: "맞은편 상대"
        case .left: "왼쪽 상대"
        }
    }
}

/// 가운데 판 200×200.
struct MahjongCenterBoard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload

    private var mySeat: Int { payload.mySeat ?? 0 }

    var body: some View {
        let match = payload.match
        let side = MahjongMatchLayout.centerSide
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(MahjongFeltStyle.board)
            RoundedRectangle(cornerRadius: 14).stroke(MahjongFeltStyle.boardRim, lineWidth: 2)
            VStack(spacing: 4) {
                Text(MahjongText.roundName(round: match?.round, handNo: match?.handNo))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(MahjongFeltStyle.glyph)
                Text(MahjongText.honba(match?.honba, kyotaku: match?.kyotaku))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(MahjongFeltStyle.glyph)
                Text(MahjongText.wall(match?.wallRemaining))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(MahjongFeltStyle.glyph)
                MahjongTileStrip(tiles: doraTiles(match?.doraIndicators ?? []), size: CGSize(width: 166, height: 40),
                                 cornerLabels: false, accessibilityText: "도라 표시패 \(match?.doraIndicators?.count ?? 0)장")
                    .padding(.top, 2)
                waiting.frame(height: 16)
            }
            ForEach(MahjongCompass.allCases, id: \.self) { compass in
                edge(compass, side: side)
            }
        }
    }

    /// 도라 5칸 — 열린 것만 앞면, 나머지 뒷면.
    private func doraTiles(_ open: [MahjongTile]) -> [MahjongStripTile] {
        (0..<5).map { index in
            MahjongStripTile(face: index < open.count ? MahjongTileFace(open[index]) : .back, size: .river,
                             origin: CGPoint(x: CGFloat(index) * 34, y: 0))
        }
    }

    /// `wait` 가 멈춤 끝을 1.5초 넘기면 "기다리는 중…"(누구인지 없이 — CC-11). 그 전엔 없다.
    @ViewBuilder
    private var waiting: some View {
        if payload.match?.phase == "wait", let wake = MahjongClockMath.local(payload.match?.wakeAtMs, store: store) {
            MahjongTick(store: store, interval: 0.5) { now in
                Text(now.timeIntervalSince(wake) >= 1.5 ? MahjongText.waitingOthers : " ")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(MahjongFeltStyle.glyph)
            }
        } else {
            Text(" ").font(.system(size: 12))
        }
    }

    /// 한 변: 그 자리 바람 · 리치봉 · 차례 빛줄(phase turn 일 때만).
    @ViewBuilder
    private func edge(_ compass: MahjongCompass, side: CGFloat) -> some View {
        let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
        let seat = payload.seats?.first { $0.seatNo == number }
        let isTurn = payload.match?.phase == "turn" && payload.match?.turnSeat == number
        let angle = Angle.degrees(Double(-90 * MahjongTileArtModel.rotation(for: compass)))
        ZStack {
            if isTurn {
                Capsule().fill(CheckTheme.accent).frame(width: 150, height: 5).offset(y: side / 2 - 4)
            }
            Text(windGlyph(seat?.wind))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(seat?.isDealer == true ? CheckTheme.pending : MahjongFeltStyle.glyph)
                .offset(x: -side / 2 + 22, y: side / 2 - 16)
            if seat?.riichi == true {
                ZStack {
                    Capsule().fill(Color(red: 0.92, green: 0.90, blue: 0.86)).frame(width: 56, height: 6)
                    Circle().fill(CheckTheme.danger).frame(width: 4, height: 4)
                }
                .offset(x: 30, y: side / 2 - 16)
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(-angle)
    }

    private func windGlyph(_ wire: String?) -> String {
        switch wire {
        case "E": "東"
        case "S": "南"
        case "W": "西"
        case "N": "北"
        default: ""
        }
    }
}
