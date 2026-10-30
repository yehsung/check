import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 이모티콘 반응 (2판 설계서 §1.3 · §3 ⑧)
//
// [반응] 버튼 → 아잉이 이모티콘 여섯(`AingSticker` — 메시지 이모티콘과 같은 그림) → 보낸 사람 **자리에서** 말풍선 2.5초.
// 보내기·쿨다운(2초)·내 말풍선 즉시·메아리 무시는 코어(`sendReaction` · `reactionFeed`)가 한다. 여기는 그리기만 한다.
//
// ── 자리 위치를 받는 법 ──
// 말풍선 덮개는 **'자리 번호 → 앵커'** 만 받는 독립 뷰다(`RummyReactionOverlay(bubbles:anchors:)`). 자리를 그리는 쪽(판 화면의
// B 배치 자리 · 방 화면 의자 · 결과 줄)이 그 뷰에 `.rummyReactionAnchor(seatNo:)` 한 줄을 붙이면 창 루트의
// `.rummyReactionLayer(...)` 가 그 사각형 위에 말풍선을 세운다. 앵커를 안 단 자리는 B 배치의 방위(`RummySeatCompass`)로
// 창 안 기본 자리에 선다 — 판 화면이 앵커를 달기 전에도 말풍선이 사라지지 않게.

/// 그릴 말풍선 하나(코어 `RummyReactionEvent` 의 화면 값 — 렌더 시험이 직접 만들 수 있게 따로 둔다).
struct RummyReactionBubble: Identifiable, Equatable {
    let id: Int
    let seatNo: Int
    let sticker: AingSticker
    let isMine: Bool
    let receivedAt: Date

    init(id: Int, seatNo: Int, sticker: AingSticker, isMine: Bool, receivedAt: Date) {
        self.id = id
        self.seatNo = seatNo
        self.sticker = sticker
        self.isMine = isMine
        self.receivedAt = receivedAt
    }

    init(_ event: RummyReactionEvent) {
        self.init(id: event.id, seatNo: event.seatNo, sticker: event.sticker, isMine: event.isMine,
                  receivedAt: event.receivedAt)
    }
}

/// B 배치의 방위 — 나는 아래, 나머지는 내 다음 자리부터 시계 방향으로 왼 · 위 · 오른.
/// 둘이면 마주 보고(위), 셋이면 왼·오른, 넷이면 왼·위·오른.
enum RummySeatCompass: Equatable, CaseIterable {
    case bottom, left, top, right

    static func of(seatNo: Int, mySeatNo: Int?, seatNos: [Int]) -> RummySeatCompass {
        guard let mySeatNo, seatNo != mySeatNo else { return .bottom }
        let others = Array(Set(seatNos).subtracting([mySeatNo]))
            .sorted { relative($0, from: mySeatNo) < relative($1, from: mySeatNo) }
        guard let index = others.firstIndex(of: seatNo) else { return .top }
        switch others.count {
        case 1: return .top
        case 2: return index == 0 ? .left : .right
        default: return [RummySeatCompass.left, .top, .right][min(index, 2)]
        }
    }

    /// 내 자리에서 시계 방향으로 몇 칸(자리 번호 0~3).
    private static func relative(_ seat: Int, from mine: Int) -> Int { ((seat - mine) % 4 + 4) % 4 }

    /// 앵커가 없을 때의 창 안 기본 자리(pt, 창 1240×700 기준 — B 배치의 자리 띠 근처).
    var fallbackRect: CGRect {
        let size = RummyWindowLayout.contentSize
        switch self {
        case .bottom: return CGRect(x: size.width / 2 - 30, y: size.height - 150, width: 60, height: 60)
        case .left: return CGRect(x: 40, y: size.height / 2 - 60, width: 60, height: 60)
        case .top: return CGRect(x: size.width / 2 - 30, y: 70, width: 60, height: 60)
        case .right: return CGRect(x: size.width - 100, y: size.height / 2 - 60, width: 60, height: 60)
        }
    }
}

/// 자리 하나의 앵커 — 그 사각형과 말풍선을 세울 쪽(기본 위. 탁자 아래 자리처럼 위가 판이면 옆으로).
struct RummySeatAnchor {
    var rect: CGRect
    var edge: Edge = .top
}

/// 자리 번호 → 그 자리 사각형(앵커) · 말풍선 쪽.
struct RummySeatAnchorKey: PreferenceKey {
    static let defaultValue: [Int: (anchor: Anchor<CGRect>, edge: Edge)] = [:]
    static func reduce(value: inout [Int: (anchor: Anchor<CGRect>, edge: Edge)],
                       nextValue: () -> [Int: (anchor: Anchor<CGRect>, edge: Edge)]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// 이 뷰가 `seatNo` 자리다 — 그 사람의 반응 말풍선이 이 뷰의 `edge` 쪽에 선다. nil 이면 아무것도 안 한다.
    func rummyReactionAnchor(seatNo: Int?, edge: Edge = .top) -> some View {
        anchorPreference(key: RummySeatAnchorKey.self, value: .bounds) { anchor in
            seatNo.map { [$0: (anchor: anchor, edge: edge)] } ?? [:]
        }
    }

    /// 창 루트에 한 번: 자리 앵커를 모아 말풍선 덮개를 얹는다. `compass` 는 앵커 없는 자리의 기본 방위.
    func rummyReactionLayer(bubbles: [RummyReactionBubble], compass: @escaping (Int) -> RummySeatCompass,
                            fixedNow: Date?) -> some View {
        overlayPreferenceValue(RummySeatAnchorKey.self) { anchors in
            GeometryReader { proxy in
                RummyReactionOverlay(bubbles: bubbles,
                                     anchors: anchors.mapValues { RummySeatAnchor(rect: proxy[$0.anchor], edge: $0.edge) },
                                     compass: compass, fixedNow: fixedNow)
            }
            .allowsHitTesting(false)
        }
    }
}

/// 말풍선 덮개 — 자리 번호 → 앵커 사각형만 받는다(어느 화면 배치에도 얹힌다).
struct RummyReactionOverlay: View {
    static let lifetime: TimeInterval = 2.5
    static let popIn: TimeInterval = 0.22
    static let fadeOut: TimeInterval = 0.3

    let bubbles: [RummyReactionBubble]
    let anchors: [Int: RummySeatAnchor]
    var compass: (Int) -> RummySeatCompass = { _ in .top }
    var fixedNow: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expiryTick = 0

    /// 지금 보일 말풍선 — 자리마다 가장 최근 것 하나, 받은 지 2.5초 안.
    static func visible(_ bubbles: [RummyReactionBubble], at now: Date) -> [RummyReactionBubble] {
        var latest: [Int: RummyReactionBubble] = [:]
        for bubble in bubbles {
            let age = now.timeIntervalSince(bubble.receivedAt)
            guard age >= -0.5, age < lifetime else { continue }
            if let kept = latest[bubble.seatNo], kept.receivedAt > bubble.receivedAt { continue }
            latest[bubble.seatNo] = bubble
        }
        return latest.values.sorted { $0.seatNo < $1.seatNo }
    }

    var body: some View {
        if let fixedNow {
            layer(at: fixedNow)
        } else {
            let live = !Self.visible(bubbles, at: Date()).isEmpty
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
                layer(at: context.date)
            }
            // 마지막 말풍선이 끝나면 한 번 다시 그려 시계를 멈춘다(빈 덮개가 30fps 로 돌지 않게).
            .task(id: bubbles.last?.id) {
                try? await Task.sleep(for: .seconds(Self.lifetime + 0.1))
                expiryTick &+= 1
            }
            .id(expiryTick)
        }
    }

    private func layer(at now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Self.visible(bubbles, at: now)) { bubble in
                let anchor = anchors[bubble.seatNo] ?? RummySeatAnchor(rect: compass(bubble.seatNo).fallbackRect)
                let side = Self.side(for: anchor)
                let age = max(0, now.timeIntervalSince(bubble.receivedAt))
                RummyReactionBubbleView(sticker: bubble.sticker, pointsTo: side)
                    .scaleEffect(reduceMotion ? 1 : Self.scale(age: age), anchor: Self.unitPoint(side))
                    .opacity(Self.opacity(age: age))
                    .position(Self.center(for: anchor.rect, side: side))
            }
        }
    }

    /// 말풍선이 앵커의 어느 쪽에 서는가. 위인데 창 위 끝에 붙어 있으면 아래로 뒤집는다.
    static func side(for anchor: RummySeatAnchor) -> Edge {
        if anchor.edge == .top, anchor.rect.minY < RummyReactionBubbleView.height + 10 { return .bottom }
        return anchor.edge
    }

    /// 말풍선 중심(꼬리 끝이 앵커에서 6pt).
    static func center(for rect: CGRect, side: Edge) -> CGPoint {
        let half = RummyReactionBubbleView.height / 2
        switch side {
        case .top: return CGPoint(x: rect.midX, y: rect.minY - 6 - half)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY + 6 + half)
        case .leading: return CGPoint(x: rect.minX - 6 - half, y: rect.midY)
        case .trailing: return CGPoint(x: rect.maxX + 6 + half, y: rect.midY)
        }
    }

    /// 튀어나오는 기준점 = 꼬리 끝(앵커 쪽).
    static func unitPoint(_ side: Edge) -> UnitPoint {
        switch side {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }

    /// 튀어나오기 — 0.22초 동안 0.5 → 1.08 → 1(살짝 넘쳤다 돌아온다).
    static func scale(age: TimeInterval) -> CGFloat {
        guard age < popIn else { return 1 }
        let t = age / popIn
        let back = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2)
        return CGFloat(0.5 + 0.5 * back)
    }

    /// 마지막 0.3초 동안 **선형**으로 사라진다(이징으로 불투명도를 깎지 않는다).
    static func opacity(age: TimeInterval) -> Double {
        let left = lifetime - age
        guard left < fadeOut else { return 1 }
        return max(0, left / fadeOut)
    }
}

/// 말풍선 하나 — 흰 둥근 판 + 앵커 쪽 꼬리 + 아잉이 이모티콘. 틀은 꼬리를 포함한 정사각(`height`)이다.
struct RummyReactionBubbleView: View {
    static let side: CGFloat = 64
    static let tail: CGFloat = 8
    static var height: CGFloat { side + tail * 2 }

    let sticker: AingSticker
    /// 말풍선이 앵커의 어느 쪽에 섰는가(꼬리는 그 반대쪽 = 앵커를 향한다).
    var pointsTo: Edge = .top

    var body: some View {
        ZStack {
            RummyBubbleTail()
                .fill(Color.white)
                .frame(width: 16, height: Self.tail)
                .rotationEffect(tailRotation)
                .offset(tailOffset)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .frame(width: Self.side, height: Self.side)
            RummyStickerArt(sticker: sticker)
                .padding(6)
                .frame(width: Self.side, height: Self.side)
        }
        .frame(width: Self.height, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("반응 \(sticker.label)")
    }

    /// 꼬리 기본 모양은 아래를 가리킨다(말풍선이 앵커 위에 섰을 때).
    private var tailRotation: Angle {
        switch pointsTo {
        case .top: return .degrees(0)
        case .bottom: return .degrees(180)
        case .leading: return .degrees(-90)
        case .trailing: return .degrees(90)
        }
    }

    private var tailOffset: CGSize {
        let d = Self.side / 2 + Self.tail / 2 - 1
        switch pointsTo {
        case .top: return CGSize(width: 0, height: d)
        case .bottom: return CGSize(width: 0, height: -d)
        case .leading: return CGSize(width: d, height: 0)
        case .trailing: return CGSize(width: -d, height: 0)
        }
    }
}

private struct RummyBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 이모티콘 그림(메시지 이모티콘과 같은 그림). 그림이 없으면 이름 글자.
struct RummyStickerArt: View {
    let sticker: AingSticker

    var body: some View {
        if let art = AingStickerArt.image(sticker) {
            art.resizable().interpolation(.high).scaledToFit()
        } else {
            Text(sticker.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.7))
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - 보내기

/// [반응] 버튼 — 누르면 이모티콘 여섯을 띄우고, 고르면 보내고 닫는다(쿨다운 2초 안이면 코어가 무시한다).
struct RummyReactionButton: View {
    let store: RummyStore
    var height: CGFloat = 30

    @State private var picking = false

    var body: some View {
        TetrisDuelActionButton(title: "반응", icon: "face.smiling", style: .outline, height: height,
                               isEnabled: store.match != nil, action: { picking.toggle() })
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                RummyReactionPicker { sticker in
                    store.sendReaction(sticker)
                    picking = false
                }
            }
    }
}

/// 이모티콘 여섯(3×2). `AingSticker` case 순서 = 고르는 순서(메시지 그리드와 같다).
struct RummyReactionPicker: View {
    static let cell: CGFloat = 56
    let onPick: (AingSticker) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 8), count: 3), spacing: 8) {
            ForEach(AingSticker.allCases, id: \.self) { sticker in
                Button { onPick(sticker) } label: {
                    RummyStickerArt(sticker: sticker)
                        .padding(5)
                        .frame(width: Self.cell, height: Self.cell)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08)))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sticker.label)
            }
        }
        .padding(12)
    }
}
