#if os(iOS)
import CheckCore
import SwiftUI

// 아잉 마작 폰 판 화면(1.0.18 — **가로**, 큐브와 같은 '이 화면만 가로'). 맥 `MahjongTableView` 의 약속을 그대로 지킨다:
//  · **단추 · 버릴 수 있는 패는 `store.myDecision` 에 있는 것만** — 클라 판정으로 켜지 않는다. 판 · 부 · 점수는 늘 서버 값.
//  · 숨은 정보는 서버가 이미 걷었다 — 남의 손은 뒷면 수뿐. 남의 시계는 그리지 않는다(남의 예비를 모른다).
//  · 펠트(강 바람개비 · 상대 손 띠 · 가운데 판)는 맥 펠트 좌표 884×502 를 통째로 줄여 그린다(`GamesMahjongFeltGeometry`).
//  · 폰에서 다른 것: 호버가 없어 **두 번 눌러 버리기**(한 번 = 들기 · 미리보기, 한 번 더 = 버리기) · 움직임(미끄러짐) 없음 ·
//    반응(얼굴) 보내기 없음(받은 반응은 판에 그리지 않는다) · 패 그림 선택지 시트 없음(고른 'A 지금 그대로').
//
// 배치(가로 W×H): 왼쪽 열(정보 · [규칙] [나가기] · 왼쪽 상대 · 내 카드) | 가운데(맞은편 상대 띠 · 펠트) | 오른쪽 열(오른쪽 상대 · 보조 · 동작) ·
// 맨 아래 손패(오른쪽 열 앞까지).
struct GamesMahjongTableView: View {
    let store: GamesStore
    let onRules: () -> Void
    @State private var confirmingLeave = false

    private var mahjong: MahjongStore { store.mahjong }

    var body: some View {
        GeometryReader { proxy in
            if let payload = mahjong.table {
                if proxy.size.width > proxy.size.height {
                    content(payload: payload, size: proxy.size)
                } else {
                    GamesMahjongRotatingView(games: store)
                }
            }
        }
        .background(GamesMahjongPalette.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .hidesTabBar(for: .mahjongMatch)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(GamesMahjongPhoneText.leaveTitle, isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button(GamesMahjongPhoneText.leaveConfirm, role: .destructive) { leave() }
            Button(GamesMahjongPhoneText.stay, role: .cancel) {}
        } message: {
            Text(GamesMahjongPhoneText.leaveDetail)
        }
    }

    private func leave() {
        if mahjong.isPractice {
            mahjong.endPractice()
        } else {
            Task { await mahjong.leaveTable() }
            store.context.router.popToRoot(.games)
        }
    }

    @ViewBuilder
    private func content(payload: MahjongStatePayload, size: CGSize) -> some View {
        let layout = GamesMahjongTableLayout(size: size)
        let mySeat = payload.mySeat ?? 0
        let seat: (MahjongCompass) -> MahjongStateSeat? = { compass in
            let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
            return payload.seats?.first { $0.seatNo == number }
        }
        ZStack(alignment: .topLeading) {
            place(layout.info) { infoBox(payload) }
            place(layout.chrome) {
                // 4:6 으로 나눈다 — 반반이면 '연습 끝내기'(여섯 글자)가 테두리에 잘린다(11-10 캡처). '규칙'은 두 글자라 40% 로 넉넉하다.
                let gap: CGFloat = 6
                let usable = max(0, layout.chrome.width - gap)
                HStack(spacing: gap) {
                    smallButton(GamesMahjongText.rules, tint: MobileTheme.label2, action: onRules)
                        .frame(width: usable * 0.4)
                    smallButton(mahjong.isPractice ? GamesMahjongText.practiceEnd : GamesMahjongText.leave, tint: MobileTheme.danger) {
                        if mahjong.isPractice { mahjong.endPractice() } else { confirmingLeave = true }
                    }
                    .frame(width: usable * 0.6)
                }
            }
            if let left = seat(.left) {
                place(layout.leftSeat) { GamesMahjongSeatCard(store: mahjong, payload: payload, seat: left, mine: false) }
            }
            if let top = seat(.top) {
                place(layout.topSeat) { GamesMahjongSeatCard(store: mahjong, payload: payload, seat: top, mine: false, compact: true) }
            }
            if let right = seat(.right) {
                place(layout.rightSeat) { GamesMahjongSeatCard(store: mahjong, payload: payload, seat: right, mine: false) }
            }
            if let mine = seat(.bottom) {
                place(layout.mySeat) {
                    GamesMahjongSeatCard(store: mahjong, payload: payload, seat: mine, mine: true,
                                         me: GamesMeIdentity.current(store.context))
                }
            }
            place(layout.felt) { GamesMahjongFeltView(store: mahjong, payload: payload, scale: layout.feltScale) }
            place(layout.aids) { GamesMahjongAidsRow(store: mahjong) }
            place(layout.actions) { GamesMahjongActionsView(store: mahjong, payload: payload) }
            place(layout.hand) { GamesMahjongHandView(store: mahjong, payload: payload, tileHeight: layout.handTileHeight) }
            overlays(payload: payload, layout: layout)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func overlays(payload: MahjongStatePayload, layout: GamesMahjongTableLayout) -> some View {
        let felt = layout.felt
        if payload.match?.matchStatus == .finished {
            GamesMahjongMatchResultCard(store: store, payload: payload)
                .frame(width: min(layout.size.width - 32, 520), height: layout.size.height - 24)
                .offset(x: (layout.size.width - min(layout.size.width - 32, 520)) / 2, y: 12)
        } else if payload.match?.phase == "hand_end", let result = payload.lastHand {
            GamesMahjongHandResultCard(store: mahjong, payload: payload, result: result)
                .frame(width: felt.width + 40, height: felt.height + 10)
                .offset(x: felt.minX - 20, y: felt.minY - 5)
        }
        if let band = mahjong.roomBand {
            GamesMahjongRoomBand(store: mahjong, band: band)
                .frame(width: min(felt.width, 420))
                .offset(x: felt.midX - min(felt.width, 420) / 2, y: felt.minY + 6)
        }
    }

    private func infoBox(_ payload: MahjongStatePayload) -> some View {
        let match = payload.match
        return VStack(alignment: .leading, spacing: 0) {
            Text(GamesMahjongText.roundName(round: match?.round, handNo: match?.handNo))
                .font(.subheadline.weight(.heavy))
            HStack(spacing: 3) {
                if mahjong.isPractice {
                    Text(GamesMahjongText.practiceTitle).foregroundStyle(MobileTheme.working)
                } else {
                    RubyIcon(size: 10)
                    Text("\(match?.stake ?? 0)").fontWeight(.bold)
                }
                Text("· " + GamesMahjongText.format(match?.formatKind) + (match?.extension == true ? " · 연장" : ""))
                    .foregroundStyle(GamesMahjongPalette.secondary)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GamesMahjongPalette.panel))
    }

    private func smallButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func place<Content: View>(_ rect: CGRect, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// 판 색(펠트 · 칸 — 맥 `MahjongFeltStyle` 과 같은 중간 톤). 판 화면은 늘 어둡다(맥 창과 같다).
enum GamesMahjongPalette {
    static let background = Color(red: 0.10, green: 0.12, blue: 0.14)
    static let panel = Color(red: 0.16, green: 0.19, blue: 0.22)
    static let felt = Color(red: 0.24, green: 0.39, blue: 0.36)
    static let rim = Color(red: 0.32, green: 0.46, blue: 0.44)
    static let board = Color(red: 0.31, green: 0.45, blue: 0.43)
    static let boardRim = Color(red: 0.44, green: 0.58, blue: 0.56)
    static let glyph = Color(red: 0.86, green: 0.84, blue: 0.80)
    static let secondary = Color.white.opacity(0.62)
    static let accent = Color(red: 0.33, green: 0.67, blue: 1.0)
}

// MARK: - 자리 카드

struct GamesMahjongSeatCard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let seat: MahjongStateSeat
    let mine: Bool
    var compact = false
    var me: GamesMeIdentity? = nil

    private var isTurn: Bool { payload.match?.phase == "turn" && payload.match?.turnSeat == seat.seatNo }
    private var isBot: Bool { store.isPractice && seat.seatNo != payload.mySeat }
    private var name: String {
        if seat.deleted == true { return GamesMahjongText.deletedChip }
        if mine { return me?.name ?? seat.user?.displayName ?? "나" }
        return seat.user?.displayName ?? "?"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if compact {
                HStack(spacing: 6) {
                    avatar(22)
                    Text(name).font(.caption.weight(.semibold)).lineLimit(1)
                    score(15)
                    chips
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            } else if mine {
                HStack(spacing: 6) {
                    ZStack {
                        GamesMahjongClockRing(store: store, diameter: 44)
                        avatar(34)
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        score(17)
                        HStack(spacing: 2) { chips }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            } else {
                VStack(spacing: 3) {
                    avatar(30)
                    Text(name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    if isBot {
                        Text(GamesMahjongText.practiceBotTag).font(.system(size: 9, weight: .semibold)).foregroundStyle(MobileTheme.working)
                    }
                    score(16)
                    HStack(spacing: 2) { chips }
                }
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(GamesMahjongPalette.panel))
        .overlay(shape.strokeBorder(isTurn ? GamesMahjongPalette.accent : Color.white.opacity(0.10), lineWidth: isTurn ? 2 : 1))
        .opacity(seat.deleted == true ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private func avatar(_ size: CGFloat) -> some View {
        let id = seat.user?.userId ?? "seat-\(seat.seatNo)"
        return PersonAvatar(name: name, colorSeed: id, url: seat.user?.avatarUrl.flatMap(URL.init(string:)), userID: id, size: size,
                            characterHint: mine ? (me?.characterID ?? seat.user?.character) : seat.user?.character)
    }

    private func score(_ size: CGFloat) -> some View {
        Text(GamesMahjongText.score(seat.score))
            .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var chips: some View {
        GamesMahjongChip(text: GamesMahjongText.wind(seat.wind), tint: GamesMahjongPalette.secondary)
        if seat.isDealer == true { GamesMahjongChip(text: GamesMahjongText.dealerChip, tint: MobileTheme.pending) }
        if seat.riichi == true { GamesMahjongChip(text: GamesMahjongText.riichiChip, tint: GamesMahjongPalette.accent) }
        if seat.away == true { GamesMahjongChip(text: GamesMahjongText.autoChip, tint: MobileTheme.danger) }
    }
}

// MARK: - 내 시계(맥 `MahjongMyClock` 과 같은 판정)

@MainActor
enum GamesMahjongMyClock {
    struct Window {
        let started: Date
        let bankMs: Int
        let isCall: Bool
    }

    static func local(_ ms: Double?, store: MahjongStore) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1_000 + store.serverClockOffset)
    }

    static func window(store: MahjongStore) -> Window? {
        // '넉넉히' 연습판은 결정 시계 칸이 0 이다 — 링 · 막대 · 경고를 모두 숨긴다.
        if store.isPractice, store.practice?.timed == false { return nil }
        switch store.myDecision {
        case .turn(let turn)?:
            // 리치 자동 쯔모기리 차례(고를 것이 없다)는 시계를 그리지 않는다(맥 V3-05).
            if let notBefore = turn.notBeforeMs, turn.deadlineMs <= notBefore { return nil }
            guard let started = local(turn.startedMs, store: store) else { return nil }
            return Window(started: started, bankMs: turn.bankMs, isCall: false)
        case .call(let call)?:
            guard call.answered == nil, let started = local(call.startedMs, store: store) else { return nil }
            return Window(started: started, bankMs: call.bankMs, isCall: true)
        case nil:
            return nil
        }
    }
}

/// 내 카드 링 — 5초를 줄이고, 다 쓰면 주황 "예비 N".
struct GamesMahjongClockRing: View {
    let store: MahjongStore
    let diameter: CGFloat

    var body: some View {
        if let window = GamesMahjongMyClock.window(store: store) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let left = MahjongClock.remaining(started: window.started, bankMs: window.bankMs, now: store.clock())
                let inBank = left.baseLeft <= 0
                let fraction = inBank ? left.bankLeft / max(1, Double(MahjongClock.bankFullMs) / 1000)
                    : left.baseLeft / (Double(MahjongClock.baseMs) / 1000)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0, min(1, fraction)))
                        .stroke(inBank ? MobileTheme.pending : GamesMahjongPalette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if inBank {
                        Text("\(GamesMahjongText.reserve) \(Int(left.bankLeft.rounded(.up)))")
                            .font(.system(size: 8, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(MobileTheme.pending))
                            .offset(y: diameter / 2)
                    }
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }
}

// MARK: - 펠트

/// 펠트 — 맥 `MahjongFeltView`(강 · 상대 손 띠 · 가운데 판)를 펠트 좌표 그대로 그리고 `scale` 로 줄인다. 입력 없음.
struct GamesMahjongFeltView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let scale: CGFloat

    private var mySeat: Int { payload.mySeat ?? 0 }
    private var lastDiscarder: Int? { payload.events?.last(where: { $0.kind == "discard" })?.seat }

    var body: some View {
        let felt = GamesMahjongFeltLayout.felt.size
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(GamesMahjongPalette.felt)
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(GamesMahjongPalette.rim, lineWidth: 2)
            GamesMahjongTileStrip(tiles: allTiles().map(scaled), cornerLabels: store.aids.cornerLabels,
                                  accessibilityText: accessibilityLine)
                .frame(width: felt.width * scale, height: felt.height * scale)
            GamesMahjongCenterBoard(store: store, payload: payload, scale: scale)
                .frame(width: GamesMahjongFeltLayout.centerSide * scale, height: GamesMahjongFeltLayout.centerSide * scale)
                .offset(x: GamesMahjongFeltLayout.center.minX * scale, y: GamesMahjongFeltLayout.center.minY * scale)
        }
        .frame(width: felt.width * scale, height: felt.height * scale, alignment: .topLeading)
    }

    private func scaled(_ tile: GamesMahjongStripTile) -> GamesMahjongScaledTile {
        let r = tile.rect
        return GamesMahjongScaledTile(tile: tile, rect: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale))
    }

    private func allTiles() -> [GamesMahjongStripTile] {
        var out: [GamesMahjongStripTile] = []
        for compass in MahjongCompass.allCases {
            let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
            guard let seat = payload.seats?.first(where: { $0.seatNo == number }) else { continue }
            out += GamesMahjongFeltGeometry.river(seat.discards ?? [], compass: compass, highlightLast: lastDiscarder == seat.seatNo)
            if compass != .bottom {
                out += GamesMahjongFeltGeometry.handStrip(count: seat.handCount ?? 0, melds: seat.melds ?? [], compass: compass)
            }
        }
        return out
    }

    private var accessibilityLine: String {
        (payload.seats ?? []).map { seat in
            "\(seat.seatNo == mySeat ? "나" : (seat.user?.displayName ?? "?")) 버림패 \(seat.discards?.count ?? 0)장"
        }.joined(separator: ", ")
    }
}

/// 가운데 판 — 국 이름 · 본장 · 공탁 · 남은 패 · 도라 5칸 · 네 변의 바람 · 리치봉 · 차례 빛줄(맥 `MahjongCenterBoard`).
/// 글자는 줄인 펠트 안에서 읽히게 `1/scale` 만큼 키운 크기로 쓴다.
struct GamesMahjongCenterBoard: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let scale: CGFloat

    private var mySeat: Int { payload.mySeat ?? 0 }

    var body: some View {
        let match = payload.match
        let side = GamesMahjongFeltLayout.centerSide * scale
        let dora = (0..<5).map { index -> GamesMahjongScaledTile in
            let open = match?.doraIndicators ?? []
            let size = MahjongTileSize.smallMeld
            let w = size.width * scale * 0.95, h = size.height * scale * 0.95
            let tile = GamesMahjongStripTile(face: index < open.count ? MahjongTileFace(open[index]) : .back, size: size,
                                             origin: .zero)
            return GamesMahjongScaledTile(tile: tile, rect: CGRect(x: CGFloat(index) * (w + 1.5), y: 0, width: w, height: h))
        }
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GamesMahjongPalette.board)
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GamesMahjongPalette.boardRim, lineWidth: 1.5)
            VStack(spacing: 1) {
                Text(GamesMahjongText.roundName(round: match?.round, handNo: match?.handNo))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(GamesMahjongText.honba(match?.honba, kyotaku: match?.kyotaku))
                    .font(.system(size: 8, weight: .semibold))
                Text(GamesMahjongText.wall(match?.wallRemaining))
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                GamesMahjongTileStrip(tiles: dora, cornerLabels: false, accessibilityText: "도라 표시패 \(match?.doraIndicators?.count ?? 0)장")
                    .frame(width: (MahjongTileSize.smallMeld.width * scale * 0.95 + 1.5) * 5,
                           height: MahjongTileSize.smallMeld.height * scale * 0.95)
                    .padding(.top, 1)
            }
            .foregroundStyle(GamesMahjongPalette.glyph)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            ForEach(MahjongCompass.allCases, id: \.self) { compass in
                edge(compass, side: side)
            }
        }
    }

    @ViewBuilder
    private func edge(_ compass: MahjongCompass, side: CGFloat) -> some View {
        let number = MahjongSeatCompass.seat(at: compass, mySeat: mySeat)
        let seat = payload.seats?.first { $0.seatNo == number }
        let isTurn = payload.match?.phase == "turn" && payload.match?.turnSeat == number
        let angle = Angle.degrees(Double(-90 * MahjongTileArtModel.rotation(for: compass)))
        ZStack {
            if isTurn {
                Capsule().fill(GamesMahjongPalette.accent).frame(width: side * 0.9, height: 3).offset(y: side / 2 - 2.5)
            }
            Text(GamesMahjongText.windGlyphs[windIndex(seat?.wind)])
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(seat?.isDealer == true ? MobileTheme.pending : GamesMahjongPalette.glyph)
                .offset(x: -side / 2 + 9, y: side / 2 - 7)
                .opacity(seat?.wind == nil ? 0 : 1)
            if seat?.riichi == true {
                ZStack {
                    Capsule().fill(Color(red: 0.92, green: 0.90, blue: 0.86)).frame(width: side * 0.32, height: 3.5)
                    Circle().fill(MobileTheme.danger).frame(width: 2.5, height: 2.5)
                }
                .offset(x: side * 0.2, y: side / 2 - 7)
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(-angle)
    }

    private func windIndex(_ wire: String?) -> Int {
        switch wire {
        case "S": return 1
        case "W": return 2
        case "N": return 3
        default: return 0
        }
    }
}

/// 줄인 자리에 그릴 패 하나(펠트 좌표 패 + 화면 사각형).
struct GamesMahjongScaledTile: Hashable {
    let tile: GamesMahjongStripTile
    let rect: CGRect
}

/// 띠 한 장(Canvas 하나) — 패마다 캐시 비트맵을 사각형에 놓는다.
struct GamesMahjongTileStrip: View {
    let tiles: [GamesMahjongScaledTile]
    var cornerLabels: Bool = true
    var accessibilityText: String = ""

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let scale = displayScale
        let images: [(CGImage, CGRect)] = tiles.compactMap { item in
            let natural = GamesMahjongTileArt.imageSize(item.tile.size, rotation: item.tile.rotation)
            let factor = max(item.rect.width / max(1, natural.width), 0.1)
            guard let image = GamesMahjongTileArt.cgImage(item.tile.face, size: item.tile.size, state: item.tile.state,
                                                          rotation: item.tile.rotation, cornerLabels: cornerLabels,
                                                          scale: max(1, (scale * factor).rounded(.up)))
            else { return nil }
            return (image, item.rect)
        }
        Canvas { context, _ in
            for (image, rect) in images {
                context.draw(Image(decorative: image, scale: 1).resizable().interpolation(.high), in: rect)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .allowsHitTesting(false)
    }
}

// MARK: - 손

/// 손패(자동 정렬 — id 순) · 쯔모패(띄움) · 부로(오른쪽 끝). **두 번 눌러 버리기**가 폰 기본이다(한 번 = 들기 · 미리보기).
/// 버릴 수 있는 패는 결정의 목록만(리치 무장이면 리치 선언패만). 자리 비움 중 누르면 '돌아왔어요'로 읽는다(맥 CC-10).
struct GamesMahjongHandView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let tileHeight: CGFloat
    @State private var selected: MahjongTile?

    private var turn: MahjongDecision.Turn? {
        if case .turn(let turn) = store.myDecision { return turn }
        return nil
    }
    private var isAway: Bool { payload.myAway != nil || payload.mySeatRow?.away == true }
    private var allowed: Set<MahjongTile>? {
        guard let turn else { return nil }
        return Set(store.riichiArmed ? turn.riichi : turn.discard)
    }

    var body: some View {
        let tileW = tileHeight * MahjongTileSize.hand.width / MahjongTileSize.hand.height
        let hand = (payload.myHand ?? []).sorted()
        let drawn = payload.myDrawn
        let allowed = allowed
        VStack(alignment: .leading, spacing: 2) {
            GamesMahjongStatusLine(store: store, payload: payload, preview: selected)
                .frame(height: 16)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(hand.enumerated()), id: \.offset) { _, tile in
                    tileButton(tile, width: tileW, allowed: allowed)
                }
                if let drawn {
                    Spacer().frame(width: 8)
                    tileButton(drawn, width: tileW, allowed: allowed)
                }
                Spacer(minLength: 6)
                melds(tileHeight: tileHeight * 0.74)
            }
            .frame(height: tileHeight)
        }
        .onChange(of: store.decisionKey) { _, _ in selected = nil }
    }

    private func tileButton(_ tile: MahjongTile, width: CGFloat, allowed: Set<MahjongTile>?) -> some View {
        let can = allowed?.contains(tile) ?? false
        let state: MahjongTileState = allowed.map { $0.contains(tile) ? .normal : .disabled } ?? .normal
        let lifted = selected == tile
        return GamesMahjongTileView(face: MahjongTileFace(tile), size: .hand, state: state, cornerLabels: store.aids.cornerLabels,
                                    display: CGSize(width: width, height: tileHeight))
            .offset(y: lifted ? -6 : 0)
            .contentShape(Rectangle())
            .onTapGesture { tap(tile, can: can) }
            .accessibilityAddTraits(can ? .isButton : [])
            .accessibilityHint(can ? Text(GamesMahjongPhoneText.twoTapHint) : Text(""))
    }

    private func tap(_ tile: MahjongTile, can: Bool) {
        if isAway {
            Task { await store.comeBack() }
            return
        }
        guard can, !store.isWorking else { return }
        // 폰은 두 번 눌러 버리기가 기본이다(보조 '두 번 눌러 버리기'를 끄면 맥처럼 한 번에 — `aids.twoClickDiscard` 는 폰에서 켜짐으로 시작).
        if GamesMahjongPhoneAids.twoTap(store), selected != tile {
            selected = tile
            return
        }
        selected = nil
        Task { await store.discard(tile) }
    }

    @ViewBuilder
    private func melds(tileHeight: CGFloat) -> some View {
        let melds = payload.mySeatRow?.melds ?? []
        if !melds.isEmpty {
            let w = tileHeight * MahjongTileSize.meld.width / MahjongTileSize.meld.height
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(melds.enumerated().reversed()), id: \.offset) { _, meld in
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(meld.tiles.enumerated()), id: \.offset) { index, tile in
                            let closedEnd = meld.type == "ankan" && (index == 0 || index == meld.tiles.count - 1)
                            let sideways = meld.called != nil && tile == meld.called
                            GamesMahjongTileView(face: closedEnd ? .back : MahjongTileFace(tile), size: .meld, rotation: sideways ? 1 : 0,
                                                 cornerLabels: false,
                                                 display: sideways ? CGSize(width: tileHeight, height: w) : CGSize(width: w, height: tileHeight))
                        }
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("내 울음 \(melds.count)"))
        }
    }
}

/// 상태 줄: 자리 비움 · 알림 · 리치 무장 · 들어 올린 패 미리보기 · 쿠이카에 · 기다리는 패 · 후리텐(맥 `MahjongStatusLine`).
struct GamesMahjongStatusLine: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let preview: MahjongTile?

    var body: some View {
        HStack(spacing: 6) {
            if let furiten = payload.myFuriten, !furiten.isEmpty {
                GamesMahjongChip(text: GamesMahjongText.furitenChip, tint: MobileTheme.danger)
            }
            Text(line)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private var turn: MahjongDecision.Turn? {
        if case .turn(let turn) = store.myDecision { return turn }
        return nil
    }

    /// 판 위 알림 줄에 올릴 코어 알림. 연습판은 서버 문과 상관없다 — 로비가 남긴 '곧 열려요'는 판 위에 띄우지 않는다
    /// (11-10 시뮬레이터 캡처: 서버 없이 연 연습판 손패 위에 '아잉 마작은 곧 열려요'가 떴다).
    private var tableNotice: String? {
        guard let notice = store.notice, notice != MahjongNoticeText.practiceIdleCallHint else { return nil }
        if store.isPractice, notice == MahjongNoticeText.unavailable { return nil }
        return notice
    }

    private var line: String {
        if payload.myAway != nil || payload.mySeatRow?.away == true { return MahjongNoticeText.away }
        if let notice = tableNotice { return notice }
        if store.riichiArmed { return GamesMahjongText.riichiArmedHint }
        if let preview, let turn, turn.discard.contains(preview) { return previewLine(discarding: preview) }
        if let turn, payload.mySeatRow?.riichi != true, payload.mySeatRow?.melds?.isEmpty == false {
            let all = (payload.myHand ?? []) + (payload.myDrawn.map { [$0] } ?? [])
            if turn.discard.count < all.count { return GamesMahjongText.kuikaeHint }
        }
        if let waits = payload.myWaits, !waits.isEmpty {
            return "\(GamesMahjongText.waitsTitle) " + waits.map {
                "\(MahjongTileArtModel.koreanName(kind: $0))×\(MahjongVisibleTiles.unseen(kind: $0, in: payload))"
            }.joined(separator: " · ")
        }
        if turn != nil, GamesMahjongPhoneAids.twoTap(store) { return GamesMahjongPhoneText.twoTapHint }
        return " "
    }

    private var color: Color {
        if payload.myAway != nil { return MobileTheme.pending }
        if tableNotice != nil { return MobileTheme.pending }
        if store.riichiArmed { return GamesMahjongPalette.accent }
        return .white
    }

    /// "이 패를 버리면 → 텐파이 · 3만×2" — 내 손으로만(샹텐 숫자는 보이지 않는다 — 맥과 같은 선).
    private func previewLine(discarding tile: MahjongTile) -> String {
        var all = (payload.myHand ?? []) + (payload.myDrawn.map { [$0] } ?? [])
        if let index = all.firstIndex(of: tile) { all.remove(at: index) }
        let melds = payload.mySeatRow?.melds?.count ?? 0
        let waits = MahjongHand.waits(MahjongTiles.counts34(all), melds: melds)
        guard !waits.isEmpty else { return "이 패를 버리면 → 아직 텐파이 아님 · 한 번 더 누르면 버려요" }
        return "이 패를 버리면 → 텐파이 · " + waits.map {
            "\(MahjongTileArtModel.koreanName(kind: $0))×\(MahjongVisibleTiles.unseen(kind: $0, in: payload))"
        }.joined(separator: " · ")
    }
}

// MARK: - 보조 · 동작

struct GamesMahjongAidsRow: View {
    let store: MahjongStore

    var body: some View {
        Menu {
            Toggle(GamesMahjongText.aidAutoWin, isOn: Binding(get: { store.aids.autoWin }, set: { store.aids.autoWin = $0 }))
            Toggle(GamesMahjongText.aidNoCalls, isOn: Binding(get: { store.aids.noCalls }, set: { store.aids.noCalls = $0 }))
            Toggle(GamesMahjongText.aidTsumogiri, isOn: Binding(get: { store.aids.tsumogiri }, set: { store.aids.tsumogiri = $0 }))
            Toggle(GamesMahjongPhoneText.aidTwoTap, isOn: Binding(get: { store.aids.twoClickDiscard }, set: { store.aids.twoClickDiscard = $0 }))
            Toggle(GamesMahjongPhoneText.aidCorner, isOn: Binding(get: { store.aids.cornerLabels }, set: { store.aids.cornerLabels = $0 }))
        } label: {
            let on = [store.aids.autoWin, store.aids.noCalls, store.aids.tsumogiri].filter { $0 }.count
            Label(on > 0 ? "\(GamesMahjongPhoneText.aidsTitle) \(on)" : GamesMahjongPhoneText.aidsTitle, systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GamesMahjongPalette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}

/// 동작 열(맥 `MahjongActionsView` 와 같은 갈래): 자리 비움 = [돌아왔어요] · 내 차례 = [쯔모][리치][깡][구종구패] ·
/// 울기 = [론] [퐁][깡][치] [넘기기](+ 내 시계 막대). 조합이 여럿이면(치 · 적5 퐁 · 대명깡) 고르는 줄을 연다.
struct GamesMahjongActionsView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    @State private var choiceKind: MahjongClaimKind?
    @State private var kanOpen = false

    enum CallButtonPlan: Equatable {
        case none
        case send([MahjongTile])
        case choose([[MahjongTile]])
    }

    static func plan(_ kind: MahjongClaimKind, _ call: MahjongDecision.Call) -> CallButtonPlan {
        let options = MahjongStore.options(of: kind, in: call)
        switch options.count {
        case 0: return .none
        case 1: return .send(options[0])
        default: return .choose(options)
        }
    }

    private var isAway: Bool { payload.myAway != nil || payload.mySeatRow?.away == true }
    private var busy: Bool { store.isWorking || store.isAnsweringCall }

    var body: some View {
        VStack(spacing: 6) {
            if isAway {
                away
            } else {
                switch store.myDecision {
                case .turn(let turn)?: turnContent(turn)
                case .call(let call)? where call.answered == nil: callContent(call)
                default: EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: store.decisionKey) { _, _ in choiceKind = nil; kanOpen = false }
    }

    private var away: some View {
        VStack(spacing: 6) {
            Text(GamesMahjongText.awayHint)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MobileTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let ready = GamesMahjongMyClock.local(payload.myAway?.backReadyMs, store: store)
                let wait = ready.map { Int($0.timeIntervalSince(store.clock()).rounded(.up)) } ?? 0
                button(wait > 0 ? GamesMahjongText.backIn(wait) : GamesMahjongText.comeBack, tint: MobileTheme.pending, height: 48,
                       enabled: wait <= 0) {
                    Task { await store.comeBack() }
                }
            }
        }
    }

    @ViewBuilder
    private func turnContent(_ turn: MahjongDecision.Turn) -> some View {
        let kans = turn.ankan.map { ($0, true) } + turn.kakan.map { ([$0], false) }
        if kanOpen, kans.count > 1 {
            ForEach(Array(kans.enumerated()), id: \.offset) { _, kan in
                button("\(GamesMahjongText.kan) \(MahjongTileArtModel.koreanName(kind: kan.0[0].kind))", tint: MobileTheme.working) {
                    kanOpen = false
                    Task { if kan.1 { await store.ankan(kan.0) } else { await store.kakan(kan.0[0]) } }
                }
            }
            button(GamesMahjongText.cancel, tint: GamesMahjongPalette.secondary, filled: false) { kanOpen = false }
        } else {
            if turn.tsumo { button(GamesMahjongText.tsumo, tint: MobileTheme.pending) { Task { await store.declareTsumo() } } }
            if !turn.riichi.isEmpty {
                if store.riichiArmed {
                    button(GamesMahjongText.cancel, tint: GamesMahjongPalette.accent, filled: false) { store.cancelRiichi() }
                } else {
                    button(GamesMahjongText.riichi, tint: GamesMahjongPalette.accent) { store.armRiichi() }
                }
            }
            if !kans.isEmpty {
                button(kans.count > 1 ? GamesMahjongText.kanMore : GamesMahjongText.kan, tint: MobileTheme.working) {
                    if kans.count > 1 { kanOpen = true; return }
                    let kan = kans[0]
                    Task { if kan.1 { await store.ankan(kan.0) } else { await store.kakan(kan.0[0]) } }
                }
            }
            if turn.kyuushu {
                button(GamesMahjongText.kyuushu, tint: GamesMahjongPalette.secondary, filled: false) { Task { await store.declareKyuushu() } }
            }
        }
    }

    @ViewBuilder
    private func callContent(_ call: MahjongDecision.Call) -> some View {
        if store.notice == MahjongNoticeText.practiceIdleCallHint {
            Text(MahjongNoticeText.practiceIdleCallHint)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MobileTheme.pending)
                .lineLimit(2)
        } else {
            GamesMahjongCallClockBar(store: store).frame(height: 4)
        }
        if let kind = choiceKind, case .choose(let options) = Self.plan(kind, call) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                GamesMahjongCallTilesButton(title: nil, tiles: pair, enabled: !busy) {
                    choiceKind = nil
                    Task { await store.call(kind, tiles: pair) }
                }
            }
            button(GamesMahjongText.cancel, tint: GamesMahjongPalette.secondary, filled: false) { choiceKind = nil }
        } else {
            if call.ron { button(GamesMahjongText.ron, tint: MobileTheme.pending) { Task { await store.call(.ron, tiles: []) } } }
            switch Self.plan(.pon, call) {
            case .send(let pon): button(GamesMahjongText.pon, tint: MobileTheme.working) { Task { await store.call(.pon, tiles: pon) } }
            case .choose: button("\(GamesMahjongText.pon) ▸", tint: MobileTheme.working) { choiceKind = .pon }
            case .none: EmptyView()
            }
            switch Self.plan(.minkan, call) {
            case .send(let kan): button(GamesMahjongText.kan, tint: MobileTheme.working) { Task { await store.call(.minkan, tiles: kan) } }
            case .choose: button("\(GamesMahjongText.kan) ▸", tint: MobileTheme.working) { choiceKind = .minkan }
            case .none: EmptyView()
            }
            switch Self.plan(.chi, call) {
            case .send(let chi):
                GamesMahjongCallTilesButton(title: GamesMahjongText.chi, tiles: chi, enabled: !busy) {
                    Task { await store.call(.chi, tiles: chi) }
                }
            case .choose: button("\(GamesMahjongText.chi) ▸", tint: MobileTheme.working) { choiceKind = .chi }
            case .none: EmptyView()
            }
            button(GamesMahjongText.pass, tint: GamesMahjongPalette.secondary, filled: false) { Task { await store.passCall() } }
        }
    }

    private func button(_ title: String, tint: Color, filled: Bool = true, height: CGFloat = 36, enabled: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(filled ? Color.white : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(filled ? tint : Color.clear))
                .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.8), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy || !enabled)
        .opacity(busy || !enabled ? 0.5 : 1)
    }
}

/// 울기 프롬프트 위 얇은 막대(내 시계).
struct GamesMahjongCallClockBar: View {
    let store: MahjongStore

    var body: some View {
        if let window = GamesMahjongMyClock.window(store: store) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = MahjongClock.remaining(started: window.started, bankMs: window.bankMs, now: store.clock())
                let inBank = left.baseLeft <= 0
                let fraction = inBank ? left.bankLeft / (Double(MahjongClock.bankFullMs) / 1000)
                    : left.baseLeft / (Double(MahjongClock.baseMs) / 1000)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(inBank ? MobileTheme.pending : GamesMahjongPalette.accent)
                            .frame(width: proxy.size.width * max(0, min(1, fraction)))
                    }
                }
            }
        }
    }
}

/// 울기 단추 + 쓰일 내 패 작게(치 · 조합 고르기).
struct GamesMahjongCallTilesButton: View {
    let title: String?
    let tiles: [MahjongTile]
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if let title {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                }
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    GamesMahjongTileView(face: MahjongTileFace(tile), size: .smallMeld, cornerLabels: false,
                                         display: CGSize(width: 17, height: 23))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(MobileTheme.working))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(Text(([title ?? GamesMahjongText.chi] + tiles.map { MahjongTileFace($0).spokenName }).joined(separator: " ")))
    }
}

// MARK: - 방 띠 · 돌기

/// 연습 중 "방 3/4 · 남은 7:12 · [방 보기]" — 넷째가 앉으면 "4명이 모였어요 [시작]"(방장).
struct GamesMahjongRoomBand: View {
    let store: MahjongStore
    let band: MahjongRoomBand

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3.fill").foregroundStyle(band.readyToStart ? MobileTheme.working : GamesMahjongPalette.accent)
            if band.readyToStart {
                Text(GamesMahjongText.roomBandReady).font(.caption.weight(.bold)).foregroundStyle(MobileTheme.working)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(GamesMahjongText.roomBand(joined: band.joined, seconds: max(0, Int(band.expiresAt.timeIntervalSince(store.clock())))))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            Spacer(minLength: 4)
            if band.readyToStart, store.isHost {
                Button(GamesMahjongText.start) { Task { await store.start() } }
                    .font(.caption.weight(.bold))
                    .disabled(!store.canStart || store.isWorking)
            }
            Button(GamesMahjongText.roomViewButton) { store.showRoom() }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(GamesMahjongPalette.panel))
        .overlay(Capsule().strokeBorder(band.readyToStart ? MobileTheme.working : GamesMahjongPalette.accent.opacity(0.6),
                                        lineWidth: band.readyToStart ? 2 : 1))
    }
}

/// 세로로 불렸을 때(기기가 돌기를 기다리는 동안) — 큐브와 같이 1.5초마다 다시 청한다.
struct GamesMahjongRotatingView: View {
    let games: GamesStore
    @State private var retryTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: MobileTheme.space2) {
            ProgressView()
            Text(GamesMahjongPhoneText.rotating).font(.footnote).foregroundStyle(MobileTheme.label2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            retryTask?.cancel()
            retryTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(GamesRummyOrientationRule.retryInterval))
                    guard !Task.isCancelled else { return }
                    GamesRummyOrientationLock.apply(games.rummyInterfaceOrientation)
                }
            }
        }
        .onDisappear { retryTask?.cancel() }
    }
}
#endif
