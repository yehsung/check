import SwiftUI
import CheckCore

// MARK: - 아잉 마작 손 · 동작 열 · 내 시계 (SPEC §5.4)
//
//  · 손패 46×62, 13장 → 14pt → 쯔모패 → 12pt → 부로(오른쪽 끝, 34×46). 자동 정렬(id 순 = 만→통→삭→자패, 적5 는 5 자리).
//  · **한 번 눌러 버린다**(호버 8pt 들림 + 상태 줄 미리보기). '두 번 눌러 버리기'는 보조(기본 끔). 끌기·단축키 없음.
//  · 입력은 `SpatialTapGesture` + 누른 순간 그린 손(seen)을 같이 넘긴다 — 응답이 와서 손이 바뀐 뒤 옛 좌표로 다른 패를 버리지 않게.
//  · **버릴 수 있는 패·단추는 `store.myDecision` 에 있는 것만**(리치 무장이면 `decision.riichi` 만 밝다) — 클라 판정으로 켜지 않는다.
//  · 자리 비움 중 손패를 누르면 그 클릭을 '돌아왔어요'로 읽는다(CC-10 · D46).
//  · 내 시계만 숫자로 — MY SEAT 링이 5초를 줄이고, 다 쓰면 주황 "예비 20 → 0". 울기 프롬프트엔 ACTIONS 위 얇은 막대.
//    3초 미만이면 손패 칸 테두리 경고(깜빡임은 색으로 — 불투명도 아님). 잎은 `MahjongClock.remaining` 만 읽는다.
//  · ACTIONS 단추는 `Button`(제스처가 첫 클릭에 막혀도 단추는 눌린다 — CC-05).

/// 손 칸 배치(순수 — 시험이 되묻는다). 손 칸 좌표.
enum MahjongHandGeometry {
    struct Slot: Equatable {
        let tile: MahjongTile
        let rect: CGRect
        let isDrawn: Bool
    }

    static func slots(hand: [MahjongTile], drawn: MahjongTile?) -> [Slot] {
        let w = MahjongTileSize.hand.width, h = MahjongTileSize.hand.height
        var out: [Slot] = []
        var x: CGFloat = 0
        for tile in hand.sorted() {
            out.append(Slot(tile: tile, rect: CGRect(x: x, y: MahjongMatchLayout.handTileTop, width: w, height: h), isDrawn: false))
            x += w
        }
        if let drawn {
            x += MahjongMatchLayout.drawnGap
            out.append(Slot(tile: drawn, rect: CGRect(x: x, y: MahjongMatchLayout.handTileTop, width: w, height: h), isDrawn: true))
        }
        return out
    }

    /// 누른 자리(손 칸 좌표) → 그 순간 그린 손의 패.
    static func tile(at point: CGPoint, in slots: [Slot]) -> MahjongTile? {
        slots.first { $0.rect.insetBy(dx: 0, dy: -MahjongMatchLayout.hoverLift).contains(point) }?.tile
    }
}

struct MahjongHandView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    var hoverIndex: Int? = nil
    /// 스냅샷 전용 시각(내 부로 움직임 한 장) — 앱 nil.
    var fixedNow: Date? = nil

    @State private var hovered: Int?
    @State private var selected: MahjongTile?

    private var turn: MahjongDecision.Turn? {
        if case .turn(let turn) = store.myDecision { return turn }
        return nil
    }

    private var isAway: Bool { payload.myAway != nil || payload.mySeatRow?.away == true }

    /// 지금 버릴 수 있는 패(id) — 결정의 목록만. 리치 무장이면 리치 선언패만.
    private var allowed: Set<MahjongTile>? {
        guard let turn else { return nil }
        return Set(store.riichiArmed ? turn.riichi : turn.discard)
    }

    var body: some View {
        let slots = MahjongHandGeometry.slots(hand: payload.myHand ?? [], drawn: payload.myDrawn)
        let allowed = allowed
        let hover = hoverIndex ?? hovered
        ZStack(alignment: .topLeading) {
            MahjongStatusLine(store: store, payload: payload, hoverTile: hover.flatMap { slots.indices.contains($0) ? slots[$0].tile : nil })
                .frame(width: MahjongMatchLayout.hand.width, height: MahjongMatchLayout.statusLineHeight, alignment: .leading)
            ForEach(Array(slots.enumerated()), id: \.element.tile) { index, slot in
                let state: MahjongTileState = allowed.map { $0.contains(slot.tile) ? .normal : .disabled } ?? .normal
                let lift: CGFloat = (hover == index && allowed?.contains(slot.tile) == true) || selected == slot.tile
                    ? MahjongMatchLayout.hoverLift : 0
                MahjongTileView(face: MahjongTileFace(slot.tile), size: .hand, state: state, cornerLabels: store.aids.cornerLabels)
                    .offset(x: slot.rect.minX, y: slot.rect.minY - lift)
            }
            melds(after: slots.last?.rect.maxX ?? 0)
            MahjongTurnWarning(store: store, payload: payload)
        }
        .frame(width: MahjongMatchLayout.hand.width, height: MahjongMatchLayout.hand.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovered = slots.firstIndex { $0.rect.insetBy(dx: 0, dy: -MahjongMatchLayout.hoverLift).contains(point) }
            case .ended:
                hovered = nil
            }
        }
        .gesture(SpatialTapGesture().onEnded { value in
            tap(at: value.location, seen: slots)
        })
        .onChange(of: store.decisionKey) { _, _ in selected = nil }
    }

    /// 누름 — 누른 순간 그린 손(seen)으로 패를 정한다.
    private func tap(at point: CGPoint, seen: [MahjongHandGeometry.Slot]) {
        if isAway {
            Task { await store.comeBack() }
            return
        }
        guard let tile = MahjongHandGeometry.tile(at: point, in: seen), let allowed, allowed.contains(tile),
              !store.isWorking
        else { return }
        if store.aids.twoClickDiscard, selected != tile {
            selected = tile
            return
        }
        selected = nil
        Task { await store.discard(tile) }
    }

    /// 부로(오른쪽 끝, 34×46 — 운 패는 가로).
    @ViewBuilder
    private func melds(after x: CGFloat) -> some View {
        let melds = payload.mySeatRow?.melds ?? []
        if !melds.isEmpty {
            let tiles = Self.meldTiles(melds, rightEdge: MahjongMatchLayout.hand.width,
                                       top: MahjongMatchLayout.handTileTop + MahjongTileSize.hand.height - MahjongTileSize.meld.height)
            // 방금 운 부로(마지막 묶음 = 가장 왼쪽)만 따로 미끄러진다 — 이 TimelineView 는 부로 띠만 감싼다(입력은 바깥 ZStack).
            MahjongMotionFrames(store: store, payload: payload, fixedNow: fixedNow) { motion, now in
                let melding = motion.flatMap { MahjongMotionPlan.movesNewestMeld($0, compass: .bottom, melds: melds) ? $0 : nil }
                let moving = melding == nil ? 0 : min(tiles.count, melds.last?.tiles.count ?? 0)
                ZStack(alignment: .topLeading) {
                    MahjongTileStrip(tiles: Array(tiles.dropLast(moving)), size: MahjongMatchLayout.hand.size, cornerLabels: false,
                                     accessibilityText: "내 울음 \(melds.count)")
                    if let melding, moving > 0 {
                        MahjongTileStrip(tiles: Array(tiles.suffix(moving)), size: MahjongMatchLayout.hand.size, cornerLabels: false)
                            .offset(MahjongMotionPlan.offset(melding, now: now))
                            .accessibilityHidden(true)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 내 부로를 손 칸 오른쪽 끝에서부터 왼쪽으로(첫 부로가 가장 오른쪽).
    static func meldTiles(_ melds: [MahjongWireMeld], rightEdge: CGFloat, top: CGFloat) -> [MahjongStripTile] {
        var out: [MahjongStripTile] = []
        var x = rightEdge
        for meld in melds {
            var group: [MahjongStripTile] = []
            var width: CGFloat = 0
            for (index, tile) in meld.tiles.enumerated() {
                let closedEnd = meld.type == "ankan" && (index == 0 || index == meld.tiles.count - 1)
                let sideways = meld.called != nil && tile == meld.called
                let w = sideways ? MahjongTileSize.meld.height : MahjongTileSize.meld.width
                let y = sideways ? top + MahjongTileSize.meld.height - MahjongTileSize.meld.width : top
                group.append(MahjongStripTile(face: closedEnd ? .back : MahjongTileFace(tile), size: .meld,
                                              rotation: sideways ? 1 : 0, origin: CGPoint(x: width, y: y)))
                width += w
            }
            x -= width
            out += group.map { MahjongStripTile(face: $0.face, size: $0.size, rotation: $0.rotation,
                                                origin: CGPoint(x: $0.origin.x + x, y: $0.origin.y)) }
            x -= 6
        }
        return out
    }
}

/// 상태 줄 20: 자리 비움 · 알림 · 리치 무장 · 쿠이카에 · 호버 미리보기 · 기다리는 패 · 후리텐.
private struct MahjongStatusLine: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let hoverTile: MahjongTile?

    var body: some View {
        HStack(spacing: 8) {
            if let furiten = payload.myFuriten, !furiten.isEmpty {
                MahjongChip(text: MahjongText.furitenChip, tint: CheckTheme.danger, filled: true)
            }
            Text(line).font(.caption.weight(.semibold)).foregroundStyle(lineColor).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var turn: MahjongDecision.Turn? {
        if case .turn(let turn) = store.myDecision { return turn }
        return nil
    }

    private var line: String {
        if payload.myAway != nil || payload.mySeatRow?.away == true { return MahjongNoticeText.away }
        // 울기 안내('[넘기기]를 누르면 계속돼요')는 [넘기기] 바로 위 ACTIONS 칸이 보인다 — 두 번 쓰지 않는다.
        if let notice = store.notice, notice != MahjongNoticeText.practiceIdleCallHint { return notice }
        if store.riichiArmed { return MahjongText.riichiArmedHint }
        if let hoverTile, let turn, turn.discard.contains(hoverTile) { return preview(discarding: hoverTile) }
        if let turn, payload.mySeatRow?.riichi != true, payload.mySeatRow?.melds?.isEmpty == false {
            let all = (payload.myHand ?? []) + (payload.myDrawn.map { [$0] } ?? [])
            if turn.discard.count < all.count { return MahjongText.kuikaeHint }
        }
        if let waits = payload.myWaits, !waits.isEmpty {
            return "\(MahjongText.waitsTitle) " + waits.map { "\(MahjongTileArtModel.koreanName(kind: $0))×\(MahjongVisibleTiles.unseen(kind: $0, in: payload))" }
                .joined(separator: " · ")
        }
        return " "
    }

    private var lineColor: Color {
        if payload.myAway != nil { return CheckTheme.pending }
        if let notice = store.notice, notice != MahjongNoticeText.practiceIdleCallHint { return CheckTheme.pending }
        if store.riichiArmed { return CheckTheme.accent }
        return CheckTheme.primaryText
    }

    /// "이 패를 버리면 → 텐파이 · 3만×2" — 내 손으로만(샹텐 숫자는 보이지 않는다, UX:446-452).
    private func preview(discarding tile: MahjongTile) -> String {
        var all = (payload.myHand ?? []) + (payload.myDrawn.map { [$0] } ?? [])
        if let index = all.firstIndex(of: tile) { all.remove(at: index) }
        let melds = payload.mySeatRow?.melds?.count ?? 0
        let waits = MahjongHand.waits(MahjongTiles.counts34(all), melds: melds)
        guard !waits.isEmpty else { return "이 패를 버리면 → 아직 텐파이 아님" }
        return "이 패를 버리면 → 텐파이 · " + waits.map {
            "\(MahjongTileArtModel.koreanName(kind: $0))×\(MahjongVisibleTiles.unseen(kind: $0, in: payload))"
        }.joined(separator: " · ")
    }
}

/// 3초 미만이면 손패 칸 테두리 경고 — 깜빡임은 **색**으로(주황 ↔ 빨강), 불투명도 아님.
private struct MahjongTurnWarning: View {
    let store: MahjongStore
    let payload: MahjongStatePayload

    var body: some View {
        if let window = MahjongMyClock.window(store: store) {
            MahjongTick(store: store, interval: 0.25) { now in
                let left = MahjongMyClock.secondsLeft(window, now: now)
                if left > 0, left < 3 {
                    let flip = Int(now.timeIntervalSinceReferenceDate * 4) % 2 == 0
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(flip ? CheckTheme.danger : CheckTheme.pending, lineWidth: 3)
                        .frame(width: MahjongMatchLayout.hand.width, height: MahjongMatchLayout.hand.height - 18)
                        .offset(y: 18)
                }
            }
        }
    }
}

// MARK: - 내 시계

/// 내 결정의 시계 칸(서버 ms → 기기 시각).
@MainActor
enum MahjongMyClock {
    struct Window {
        let started: Date
        let bankMs: Int
        let isCall: Bool
    }

    static func window(store: MahjongStore) -> Window? {
        // '넉넉히' 연습판은 결정 시계 칸이 0 이다(C3) — 링·막대·3초 경고를 모두 숨긴다(1970 기준 '예비 0' 이 뜨지 않게).
        if store.isPractice, store.practice?.timed == false { return nil }
        switch store.myDecision {
        case .turn(let turn)?:
            // 리치 자동 쯔모기리 차례(쯔모·암깡 선택지 없음)는 서버 마감이 not_before(시작 + 멈춤)다 — 고를 것이 없고 버림은 곧 나간다.
            //   시계(5초 + 예비)를 그리면 25초를 세다 0.7초에 사라진다(검증 V3-05) — 링 · 막대 · 3초 경고를 그리지 않는다.
            if let notBefore = turn.notBeforeMs, turn.deadlineMs <= notBefore { return nil }
            guard let started = MahjongClockMath.local(turn.startedMs, store: store) else { return nil }
            return Window(started: started, bankMs: turn.bankMs, isCall: false)
        case .call(let call)?:
            guard call.answered == nil, let started = MahjongClockMath.local(call.startedMs, store: store) else { return nil }
            return Window(started: started, bankMs: call.bankMs, isCall: true)
        case nil:
            return nil
        }
    }

    static func secondsLeft(_ window: Window, now: Date) -> Double {
        let left = MahjongClock.remaining(started: window.started, bankMs: window.bankMs, now: now)
        return left.baseLeft + left.bankLeft
    }
}

/// MY SEAT 링 — 5초를 줄이고, 다 쓰면 주황으로 "예비 N". 결정이 없으면 아무것도 그리지 않는다.
struct MahjongMyClockRing: View {
    let store: MahjongStore
    let payload: MahjongStatePayload
    let diameter: CGFloat

    var body: some View {
        if let window = MahjongMyClock.window(store: store) {
            MahjongTick(store: store, interval: 0.5) { now in
                let left = MahjongClock.remaining(started: window.started, bankMs: window.bankMs, now: now)
                let inBank = left.baseLeft <= 0
                let fraction = inBank ? left.bankLeft / max(1, Double(MahjongClock.bankFullMs) / 1000)
                    : left.baseLeft / (Double(MahjongClock.baseMs) / 1000)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0, min(1, fraction)))
                        .stroke(inBank ? CheckTheme.pending : CheckTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if inBank {
                        Text("\(MahjongText.reserve) \(Int(left.bankLeft.rounded(.up)))")
                            .font(.system(size: 9, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(CheckTheme.pending))
                            .offset(y: diameter / 2)
                    }
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }
}

// MARK: - ACTIONS 236×96

struct MahjongActionsView: View {
    let store: MahjongStore
    let payload: MahjongStatePayload

    /// 조합 고르기 줄이 열린 울기 종류(치 조합 · 적5 퐁·대명깡 — 검증 V3-07). nil = 닫힘.
    @State private var choiceKind: MahjongClaimKind?
    @State private var kanOpen = false

    /// 울기 단추 하나가 하는 일. 조합이 하나면 그 패로 바로 보내고, 둘 이상이면(치 조합 · 적5 를 쓸지 고르는 퐁 · 대명깡) 고르기 줄.
    enum CallButtonPlan: Equatable {
        case none
        case send([MahjongTile])
        case choose([[MahjongTile]])
    }

    /// 검증 V3-07: 퐁 · 대명깡 단추가 첫 조합을 박아 보내면 적5 를 낼지 고를 수 없었다 — 치와 같은 규칙으로 고른다.
    static func plan(_ kind: MahjongClaimKind, _ call: MahjongDecision.Call) -> CallButtonPlan {
        let options = MahjongStore.options(of: kind, in: call)
        switch options.count {
        case 0: return .none
        case 1: return .send(options[0])
        default: return .choose(options)
        }
    }

    private var isAway: Bool { payload.myAway != nil || payload.mySeatRow?.away == true }

    var body: some View {
        VStack(spacing: 4) {
            if isAway {
                awayContent
            } else {
                switch store.myDecision {
                case .turn(let turn)?: turnContent(turn)
                case .call(let call)? where call.answered == nil: callContent(call)
                default: Spacer(minLength: 0)
                }
            }
        }
        .frame(width: MahjongMatchLayout.actions.width, height: MahjongMatchLayout.actions.height, alignment: .top)
        .onChange(of: store.decisionKey) { _, _ in choiceKind = nil; kanOpen = false }
    }

    // MARK: 자리 비움 — 큰 [돌아왔어요]

    private var awayContent: some View {
        VStack(spacing: 6) {
            Text(MahjongText.awayHint).font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.pending).lineLimit(1)
                .minimumScaleFactor(0.8)
            if let ready = MahjongClockMath.local(payload.myAway?.backReadyMs, store: store) {
                MahjongTick(store: store, interval: 0.5) { now in
                    let wait = Int(ready.timeIntervalSince(now).rounded(.up))
                    MahjongCapsuleButton(title: wait > 0 ? MahjongText.backIn(wait) : MahjongText.comeBack,
                                         tint: CheckTheme.pending, height: 56, isEnabled: wait <= 0 && !store.isWorking) {
                        Task { await store.comeBack() }
                    }
                }
            } else {
                MahjongCapsuleButton(title: MahjongText.comeBack, tint: CheckTheme.pending, height: 56,
                                     isEnabled: !store.isWorking) {
                    Task { await store.comeBack() }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: 내 차례 — [쯔모][리치] / [깡 ▸][구종구패]

    @ViewBuilder
    private func turnContent(_ turn: MahjongDecision.Turn) -> some View {
        let kans = turn.ankan.map { ($0, true) } + turn.kakan.map { ([$0], false) }
        if kanOpen, kans.count > 1 {
            VStack(spacing: 4) {
                ForEach(Array(kans.enumerated()), id: \.offset) { _, kan in
                    action("\(MahjongText.kan) \(MahjongTileArtModel.koreanName(kind: kan.0[0].kind))", CheckTheme.working) {
                        kanOpen = false
                        Task { if kan.1 { await store.ankan(kan.0) } else { await store.kakan(kan.0[0]) } }
                    }
                }
                action(MahjongText.cancel, CheckTheme.secondaryText, filled: false) { kanOpen = false }
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if turn.tsumo { action(MahjongText.tsumo, CheckTheme.pending) { Task { await store.declareTsumo() } } }
                    if !turn.riichi.isEmpty {
                        if store.riichiArmed {
                            action(MahjongText.cancel, CheckTheme.accent, filled: false) { store.cancelRiichi() }
                        } else {
                            action(MahjongText.riichi, CheckTheme.accent) { store.armRiichi() }
                        }
                    }
                }
                .frame(height: 40)
                HStack(spacing: 6) {
                    if !kans.isEmpty {
                        action(kans.count > 1 ? MahjongText.kanMore : MahjongText.kan, CheckTheme.working) {
                            if kans.count > 1 { kanOpen = true; return }
                            let kan = kans[0]
                            Task { if kan.1 { await store.ankan(kan.0) } else { await store.kakan(kan.0[0]) } }
                        }
                    }
                    if turn.kyuushu {
                        action(MahjongText.kyuushu, CheckTheme.secondaryText, filled: false) { Task { await store.declareKyuushu() } }
                    }
                }
                .frame(height: 40)
            }
            .padding(.top, 4)
        }
    }

    // MARK: 울기 — [론] / [퐁][깡][치] / [넘기기] + 시계 막대

    @ViewBuilder
    private func callContent(_ call: MahjongDecision.Call) -> some View {
        if store.notice == MahjongNoticeText.practiceIdleCallHint {
            // '넉넉히' 연습판 울기 안내 한 줄(C3 — 5초 뒤) — [넘기기] 위. 이때는 시계 막대가 없다(넉넉히).
            Text(MahjongNoticeText.practiceIdleCallHint)
                .font(.caption2.weight(.semibold)).foregroundStyle(CheckTheme.pending)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 12)
        } else {
            MahjongCallClockBar(store: store)
                .frame(height: 4)
        }
        if let kind = choiceKind, case .choose(let options) = Self.plan(kind, call) {
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                    MahjongCallTilesButton(title: nil, tiles: pair, isEnabled: !store.isWorking && !store.isAnsweringCall) {
                        choiceKind = nil
                        Task { await store.call(kind, tiles: pair) }
                    }
                }
            }
            .frame(height: 28)
            action(MahjongText.cancel, CheckTheme.secondaryText, filled: false) { choiceKind = nil }
                .frame(height: 28)
        } else {
            HStack(spacing: 4) {
                if call.ron { action(MahjongText.ron, CheckTheme.pending) { Task { await store.call(.ron, tiles: []) } } }
            }
            .frame(height: call.ron ? 28 : 0)
            HStack(spacing: 4) {
                switch Self.plan(.pon, call) {
                case .send(let pon): action(MahjongText.pon, CheckTheme.working) { Task { await store.call(.pon, tiles: pon) } }
                case .choose: action("\(MahjongText.pon) ▸", CheckTheme.working) { choiceKind = .pon }
                case .none: EmptyView()
                }
                switch Self.plan(.minkan, call) {
                case .send(let kan): action(MahjongText.kan, CheckTheme.working) { Task { await store.call(.minkan, tiles: kan) } }
                case .choose: action("\(MahjongText.kan) ▸", CheckTheme.working) { choiceKind = .minkan }
                case .none: EmptyView()
                }
                // 치는 쓰일 내 패 두 장을 작게 붙인다(§5.4). 조합이 여럿이면 ▸ 로 고르는 줄을 연다(그 줄도 패 그림 — 퐁 · 깡도 같다).
                switch Self.plan(.chi, call) {
                case .send(let chi):
                    MahjongCallTilesButton(title: MahjongText.chi, tiles: chi,
                                           isEnabled: !store.isWorking && !store.isAnsweringCall) {
                        Task { await store.call(.chi, tiles: chi) }
                    }
                case .choose: action("\(MahjongText.chi) ▸", CheckTheme.working) { choiceKind = .chi }
                case .none: EmptyView()
                }
            }
            .frame(height: call.pon.isEmpty && call.minkan.isEmpty && call.chi.isEmpty ? 0 : 28)
            action(MahjongText.pass, CheckTheme.secondaryText, filled: false) { Task { await store.passCall() } }
                .frame(height: 28)
        }
    }

    private func action(_ title: String, _ tint: Color, filled: Bool = true, _ perform: @escaping () -> Void) -> some View {
        MahjongCapsuleButton(title: title, tint: tint, filled: filled, height: 28,
                             isEnabled: !store.isWorking && !store.isAnsweringCall, action: perform)
            .frame(maxHeight: .infinity)
    }
}

/// 울기 프롬프트 위 얇은 막대(내 시계).
private struct MahjongCallClockBar: View {
    let store: MahjongStore

    var body: some View {
        if let window = MahjongMyClock.window(store: store) {
            MahjongTick(store: store, interval: 0.25) { now in
                let left = MahjongClock.remaining(started: window.started, bankMs: window.bankMs, now: now)
                let inBank = left.baseLeft <= 0
                let fraction = inBank ? left.bankLeft / (Double(MahjongClock.bankFullMs) / 1000)
                    : left.baseLeft / (Double(MahjongClock.baseMs) / 1000)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(inBank ? CheckTheme.pending : CheckTheme.accent)
                            .frame(width: proxy.size.width * max(0, min(1, fraction)))
                    }
                }
            }
        }
    }
}

/// 울기 단추 + 쓰일 내 패 작게(치 — §5.4). 패는 24×32 를 0.72 로 줄여 28pt 단추 안에 세운다.
struct MahjongCallTilesButton: View {
    static let tileScale: CGFloat = 0.72

    let title: String?
    let tiles: [MahjongTile]
    var tint: Color = CheckTheme.working
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        let size = MahjongTileSize.smallMeld
        Button(action: action) {
            HStack(spacing: 3) {
                if let title {
                    Text(title).font(.callout.weight(.bold)).foregroundStyle(Color.white).lineLimit(1)
                }
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    MahjongTileView(face: MahjongTileFace(tile), size: size, cornerLabels: false)
                        .scaleEffect(Self.tileScale)
                        .frame(width: size.width * Self.tileScale, height: size.height * Self.tileScale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .frame(height: 28)
        .accessibilityLabel(([title ?? MahjongText.chi] + tiles.map { MahjongTileFace($0).spokenName }).joined(separator: " "))
    }
}
