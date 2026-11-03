import CheckCore
import CoreGraphics
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 이모티콘 반응(설계서 §6, 맥 `RummyReactionOverlay` 견본).
// [반응] → 아잉이 이모티콘 여섯 → 보낸 사람 **자리에서** 말풍선 2.5초. 보내기 · 쿨다운(2초) · 내 말풍선 즉시 · 메아리 무시는 코어(`sendReaction` · `reactionFeed`)가 한다.
//
// ── 말풍선 수명은 시각 비교로만 끝낸다 ──
// `.task`+`.id` 를 쓰지 않는다(맥 0.3.69 CPU 120% 사고 — 취소된 task 가 정체성을 또 바꾸는 고리). 뷰 정체성도 안 바꾼다.
// 그리는 프레임은 `TimelineView(.explicit(날짜들))` 이다: 날짜 목록이 마지막 말풍선의 만료 시각에서 끝나므로, 띄울 것이 없으면 **시계가 스스로 멈춘다**(빈 덮개가 30fps 로 돌지 않는다).
// 보일지 말지는 그 프레임마다 `받은 시각 + 2.5초` 와 스토어 시계를 비교할 뿐이다. 날짜는 `context.date` 가 아니라 `rummy.clock()` 으로 묻는다(데모 시계가 고정이다).

package enum GamesRummyReactionPlan {
    package static let lifetime: TimeInterval = 2.5
    package static let popIn: TimeInterval = 0.22
    package static let fadeOut: TimeInterval = 0.3
    /// 말풍선 몸 한 변 · 꼬리 길이(상대 카드 폭이 좁아 맥보다 작다).
    package static let bubbleSide: CGFloat = 56
    package static let tail: CGFloat = 7
    package static var bubbleHeight: CGFloat { bubbleSide + tail * 2 }
    private static let framesPerSecond: Double = 30

    /// 판 화면(가로)은 왼쪽 열 카드의 **오른쪽**으로 — 위아래로 띄우면 옆 카드를 가린다. 결과 화면(세로)은 줄의 위 · 아래다.
    package enum Side: Equatable, Sendable { case above, below, trailing }

    /// 지금 보일 말풍선 — 자리마다 가장 최근 것 하나, 받은 지 2.5초 안.
    package static func visible(_ feed: [RummyReactionEvent], at now: Date) -> [RummyReactionEvent] {
        var latest: [Int: RummyReactionEvent] = [:]
        for event in feed {
            let age = now.timeIntervalSince(event.receivedAt)
            guard age >= -0.5, age < lifetime else { continue }
            if let kept = latest[event.seatNo], kept.receivedAt > event.receivedAt { continue }
            latest[event.seatNo] = event
        }
        return latest.values.sorted { $0.seatNo < $1.seatNo }
    }

    /// 다시 그릴 날짜들. 마지막 말풍선이 만료되는 프레임 **하나 뒤**에서 끝난다 — 그 프레임이 말풍선을 지우고 시계는 멈춘다. 띄울 것이 없으면 빈 목록이다.
    package static func frames(feed: [RummyReactionEvent], clockNow: Date, wallNow: Date) -> [Date] {
        guard let last = visible(feed, at: clockNow).map(\.receivedAt).max() else { return [] }
        let remaining = last.addingTimeInterval(lifetime).timeIntervalSince(clockNow)
        guard remaining > 0 else { return [] }
        let count = Int((remaining * framesPerSecond).rounded(.up)) + 1
        return (1...count).map { wallNow.addingTimeInterval(Double($0) / framesPerSecond) }
    }

    /// 튀어나오기 — 0.22초 동안 0.5 → 1.08 → 1.
    package static func scale(age: TimeInterval) -> CGFloat {
        guard age < popIn else { return 1 }
        let t = max(0, age) / popIn
        let back = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2)
        return CGFloat(0.5 + 0.5 * back)
    }

    /// 마지막 0.3초 동안 **선형**으로 사라진다(이징으로 불투명도를 깎지 않는다).
    package static func opacity(age: TimeInterval) -> Double {
        let left = lifetime - age
        guard left < fadeOut else { return 1 }
        return max(0, left / fadeOut)
    }

    /// 가로 화면 = 카드 오른쪽. 세로 화면은 자리 위에 설 자리가 없으면 아래로.
    package static func side(for rect: CGRect, bounds: CGSize) -> Side {
        if GamesRummyMatchLayout.isLandscape(bounds) { return .trailing }
        return rect.minY < bubbleHeight + 8 ? .below : .above
    }

    /// 말풍선 중심. 꼬리 끝이 자리에서 3pt 떨어지고, 흐르는 축은 화면 안으로 들인다.
    package static func center(for rect: CGRect, side: Side, bounds: CGSize) -> CGPoint {
        let half = bubbleHeight / 2
        let inset = half + 2
        let x = min(max(rect.midX, inset), max(inset, bounds.width - inset))
        switch side {
        case .above: return CGPoint(x: x, y: rect.minY - 3 - half)
        case .below: return CGPoint(x: x, y: rect.maxY + 3 + half)
        case .trailing:
            return CGPoint(x: rect.maxX + 3 + half, y: min(max(rect.midY, inset), max(inset, bounds.height - inset)))
        }
    }
}

#if os(iOS)

// MARK: - 말풍선 덮개

/// 화면 루트의 `overlayPreferenceValue(GamesRummySeatAnchorKey.self)` 에 얹는다. 자리 앵커가 없는 자리의 반응은 그리지 않는다.
struct GamesRummyReactionLayer: View {
    let rummy: RummyStore
    let anchors: [Int: Anchor<CGRect>]
    /// 튀어나오기를 건너뛴다. 데모 시계가 고정이라 말풍선 나이가 늘 0 이다 — 그대로면 시작 크기(0.5배)로 굳은 모습만 찍힌다.
    var settled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let feed = rummy.reactionFeed
        GeometryReader { proxy in
            let bounds = proxy.size
            let rects = anchors.mapValues { proxy[$0] }
            TimelineView(.explicit(GamesRummyReactionPlan.frames(feed: feed, clockNow: rummy.clock(), wallNow: Date()))) { _ in
                let now = rummy.clock()
                ZStack(alignment: .topLeading) {
                    Color.clear
                    ForEach(GamesRummyReactionPlan.visible(feed, at: now)) { event in
                        if let rect = rects[event.seatNo] {
                            bubble(event, rect: rect, bounds: bounds, age: max(0, now.timeIntervalSince(event.receivedAt)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func anchor(_ side: GamesRummyReactionPlan.Side) -> UnitPoint {
        switch side {
        case .above: return .bottom
        case .below: return .top
        case .trailing: return .leading
        }
    }

    private func bubble(_ event: RummyReactionEvent, rect: CGRect, bounds: CGSize, age: TimeInterval) -> some View {
        let side = GamesRummyReactionPlan.side(for: rect, bounds: bounds)
        let name = rummy.match?.seats?.first { $0.seatNo == event.seatNo }?.displayName ?? "?"
        return GamesRummyReactionBubble(sticker: event.sticker, side: side)
            .scaleEffect(reduceMotion || settled ? 1 : GamesRummyReactionPlan.scale(age: age), anchor: anchor(side))
            .opacity(GamesRummyReactionPlan.opacity(age: age))
            .position(GamesRummyReactionPlan.center(for: rect, side: side, bounds: bounds))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GamesRummyText.reactionAccessibility(name: name, sticker: event.sticker.label))
    }
}

/// 말풍선 하나 — 흰 둥근 판 + 자리 쪽 꼬리 + 아잉이 이모티콘.
private struct GamesRummyReactionBubble: View {
    let sticker: AingSticker
    let side: GamesRummyReactionPlan.Side

    var body: some View {
        let body = GamesRummyReactionPlan.bubbleSide
        let tail = GamesRummyReactionPlan.tail
        ZStack {
            GamesRummyBubbleTail()
                .fill(Color.white)
                .frame(width: 14, height: tail)
                .rotationEffect(.degrees(tailAngle))
                .offset(tailOffset(reach: body / 2 + tail / 2 - 1))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .frame(width: body, height: body)
            GamesRummyStickerArt(sticker: sticker)
                .padding(5)
                .frame(width: body, height: body)
        }
        .frame(width: GamesRummyReactionPlan.bubbleHeight, height: GamesRummyReactionPlan.bubbleHeight)
    }

    private var tailAngle: Double {
        switch side {
        case .above: return 0
        case .below: return 180
        case .trailing: return 90
        }
    }

    private func tailOffset(reach: CGFloat) -> CGSize {
        switch side {
        case .above: return CGSize(width: 0, height: reach)
        case .below: return CGSize(width: 0, height: -reach)
        case .trailing: return CGSize(width: -reach, height: 0)
        }
    }
}

private struct GamesRummyBubbleTail: Shape {
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
private struct GamesRummyStickerArt: View {
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

// MARK: - 보내기 시트

/// 이모티콘 여섯(3×2). 쿨다운 2초 동안은 칸이 흐려진다 — 눌러도 안 간다는 것을 보인다(코어도 막는다).
private struct GamesRummyReactionGrid: View {
    let rummy: RummyStore
    let onSent: () -> Void

    private static let cell: CGFloat = 64
    private static let columnGap: CGFloat = 16
    /// 격자 폭(셋 + 틈) — 떠 있는 판은 이 폭으로 선다.
    static var width: CGFloat { cell * 3 + columnGap * 2 }

    var body: some View {
        VStack(spacing: 12) {
            Text(GamesRummyText.reactionTitle)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let ready = rummy.canReact(at: rummy.clock())
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.columnGap), count: 3), spacing: 12) {
                    ForEach(AingSticker.allCases, id: \.self) { sticker in
                        Button {
                            if rummy.sendReaction(sticker) { onSent() }
                        } label: {
                            GamesRummyStickerArt(sticker: sticker)
                                .padding(6)
                                .frame(width: Self.cell, height: Self.cell)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.fill))
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.4)
                        .accessibilityLabel(sticker.label)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// 결과 화면(세로)의 보내기 시트.
struct GamesRummyReactionPicker: View {
    let rummy: RummyStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GamesRummyReactionGrid(rummy: rummy, onSent: { dismiss() })
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(224)])
            .presentationDragIndicator(.visible)
    }
}

/// 판 화면(가로)의 보내기 판 — 시트는 가로 폰에서 화면을 다 덮어 판과 남은 초를 가린다. [반응] 옆에 작게 띄우고, 바깥을 누르면 닫힌다.
struct GamesRummyReactionPanel: View {
    let rummy: RummyStore
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel(SheetChromeText.close)
                .accessibilityAddTraits(.isButton)
            GamesRummyReactionGrid(rummy: rummy, onSent: onClose)
                .frame(width: GamesRummyReactionGrid.width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MobileTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MobileTheme.separator, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.top, GamesRummyMatchLayout.columnPadding)
                .padding(.trailing, GamesRummyMatchLayout.rightColumnWidth + GamesRummyMatchLayout.columnPadding)
        }
    }
}
#endif
