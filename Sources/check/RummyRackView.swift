import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 받침대 (2판 §3 "받침대 위 2줄 랙")
//
// 받침대 그림(`RummyRackStand`) 위에 `RummyRackLayout` 의 자리(줄 · 반 칸)대로 타일을 얹는다. 타일 바닥은 그림의 선반
// 기준선(뒷줄 0.44H · 앞줄 0.76H), 가로는 그림의 7% 안쪽부터 반 칸(타일 폭/2) 간격. 줄이 3개 이상으로 넘치면 같은 선반 구간에
// 줄을 고르게 나눠 타일을 줄여 담는다(드문 경우 — 보이는 것이 잘리지 않는 쪽을 골랐다).
// 그리는 자리(`frame(_:)`)와 놓는 자리(`slot(tileLeft:centerY:tiles:)`)가 한 산식이다.

/// 받침대 기하(받침대 칸 왼쪽 위 원점). 순수 값.
struct RummyRackGeometry: Equatable {
    /// 받침대 타일 크기.
    static var tile: CGSize { RummyTileSize.rack.size }
    /// 기본 줄 수(창 레이아웃 항등식이 쓴다).
    static let rows = RummyRackLayout.baseRows
    /// 두 줄 사이(뒷줄 바닥 → 앞줄 위) 간격 — 그림 기준선에서 나온다.
    static var rowSpacing: CGFloat {
        (RummyRackArtMetrics.frontRowBottom - RummyRackArtMetrics.backRowBottom) * standHeight - tile.height
    }
    /// 받침대 높이 = 타일 높이 / 0.31(세로로 늘이지 않는다).
    static var standHeight: CGFloat { RummyRackArtMetrics.height(forTileHeight: tile.height) }
    /// 한 줄 16장 + 좌우 안쪽 여백.
    static func standWidth(height: CGFloat, tileWidth: CGFloat) -> CGFloat {
        let perRow = CGFloat(RummyRackLayout.halfColumnsPerRow / RummyRackLayout.tileSpan)
        return (perRow * tileWidth + RummyRackArtMetrics.sideInset(height: height) * 2).rounded()
    }
    static var standWidth: CGFloat { standWidth(height: standHeight, tileWidth: tile.width) }

    let height: CGFloat
    let rowCount: Int

    init(height: CGFloat = RummyRackGeometry.standHeight, rowCount: Int = RummyRackLayout.baseRows) {
        self.height = height
        self.rowCount = max(RummyRackLayout.baseRows, rowCount)
    }

    /// 줄이 넘치면 타일을 줄인다(2줄 = 1).
    var tileScale: CGFloat { rowCount <= 2 ? 1 : 2 / CGFloat(rowCount) }
    var tileSize: CGSize { CGSize(width: Self.tile.width * tileScale, height: Self.tile.height * tileScale) }
    var sideInset: CGFloat { RummyRackArtMetrics.sideInset(height: height) }
    var halfPitch: CGFloat { tileSize.width / CGFloat(RummyRackLayout.tileSpan) }

    func rowBottom(_ row: Int) -> CGFloat {
        if rowCount <= 2 {
            return (row <= 0 ? RummyRackArtMetrics.backRowBottom : RummyRackArtMetrics.frontRowBottom) * height
        }
        let top = (RummyRackArtMetrics.backRowBottom - RummyRackArtMetrics.tileHeight) * height
        let bottom = RummyRackArtMetrics.frontRowBottom * height
        return top + CGFloat(row + 1) * (bottom - top) / CGFloat(rowCount)
    }

    func rowCenter(_ row: Int) -> CGFloat { rowBottom(row) - tileSize.height / 2 }

    func frame(_ slot: RummyRackSlot) -> CGRect {
        CGRect(x: sideInset + CGFloat(slot.halfCol) * halfPitch, y: rowBottom(slot.row) - tileSize.height,
               width: tileSize.width, height: tileSize.height)
    }

    /// 놓을 자리: 맨 왼쪽 타일의 왼쪽 끝 x · 손의 y → 가장 가까운 반 칸과 줄(받침대 안으로 자른다).
    func slot(tileLeft x: CGFloat, centerY y: CGFloat, tiles: Int) -> RummyRackSlot {
        let maxHalf = max(0, RummyRackLayout.halfColumnsPerRow - RummyRackLayout.tileSpan * max(1, tiles))
        let half = Int(((x - sideInset) / halfPitch).rounded())
        let row = (0..<rowCount).min { abs(rowCenter($0) - y) < abs(rowCenter($1) - y) } ?? 0
        return RummyRackSlot(row: row, halfCol: min(max(half, 0), maxHalf))
    }

    /// 받침대 타일의 모션 키 — 면 글자 + 같은 면 순번(id 순). 차례가 바뀌어 편집기가 새 id 를 붙여도 같은 타일이 같은 뷰로 남아
    /// 제자리에서 부드럽게 옮겨진다.
    static func motionKeys(_ tiles: [RummyTile]) -> [Int: String] {
        var seen: [String: Int] = [:]
        var keys: [Int: String] = [:]
        for tile in tiles.sorted(by: { $0.id < $1.id }) {
            let n = seen[tile.face.text, default: 0]
            seen[tile.face.text] = n + 1
            keys[tile.id] = "\(tile.face.text)#\(n)"
        }
        return keys
    }
}

/// 뽑은 타일 날아 들어가기 상태.
struct RummyFlyIn: Equatable {
    let serial: Int
    let tileIDs: Set<Int>
    var landed: Bool
}

/// 받침대 칸 — 그림 + 타일 + 놓기 미리보기.
struct RummyRackView: View {
    private struct KeyedTile: Identifiable {
        let id: String
        let tile: RummyTile
    }

    let tiles: [RummyTile]
    let layout: RummyRackLayout
    let geometry: RummyRackGeometry
    let size: CGSize
    let draggingTileIDs: Set<Int>
    let liftedTileIDs: Set<Int>
    /// 길게 눌러 집은 장수 뱃지(덩어리 오른쪽 위 바깥).
    let liftBadge: (tileID: Int, count: Int)?
    /// 놓기 미리보기 자리(점선).
    let ghostSlots: [RummyRackSlot]
    /// 판 타일을 받침대로 끄는 중(R-14) — 빨간 테두리.
    let refused: Bool
    let stagger: [Int: Double]
    let flyIn: RummyFlyIn?
    /// 뽑기 버튼 가운데(받침대 칸 좌표) — 날아 들어오는 출발점.
    let flyOrigin: CGPoint
    let reduceMotion: Bool
    let onTileDrag: (Int, DragGesture.Value) -> Void
    let onTileDragEnd: (Int, DragGesture.Value) -> Void
    /// 0.3.70 끼워 넣기 미리보기: 받침대 위로 끄는 동안 놓으면 될 받침대(= 실제). 다른 타일은 이 자리로 비켜 서고, 끄는 타일은
    /// 원래 자리에서 감춘다(그 자리를 이웃이 채울 수 있다 — 놓을 자리는 점선 `ghostSlots`).
    var previewLayout: RummyRackLayout? = nil
    /// 0.3.70 방금 뽑은 타일(3초 빛남 — 동작 줄이기면 테두리만).
    var freshTileIDs: Set<Int> = []
    /// 0.3.70 받침대에서 그대로 맞는 덩어리(밑줄 띠 + 점수).
    var rackMelds: [RummyRackMeld] = []
    /// 0.3.70 첫 등록 전 '랙 묶음 합'(판 · 랙). nil 이면 안 보인다.
    var planPoints: (table: Int, rack: Int)? = nil
    /// 0.3.70 내 차례 테두리 빛.
    var turnGlow: RummyTurnGlowPhase? = nil

    private var shownLayout: RummyRackLayout { previewLayout ?? layout }

    var body: some View {
        let keys = RummyRackGeometry.motionKeys(tiles)
        let tileSize = RummyTileSize(geometry.tileSize)
        let shown = shownLayout
        ZStack(alignment: .topLeading) {
            RummyRackStand()
                .frame(width: size.width, height: size.height)
            ForEach(Array(ghostSlots.enumerated()), id: \.offset) { _, slot in
                let frame = geometry.frame(slot)
                RoundedRectangle(cornerRadius: tileSize.corner, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .foregroundStyle(CheckTheme.accent)
                    .background(RoundedRectangle(cornerRadius: tileSize.corner, style: .continuous)
                        .fill(CheckTheme.accent.opacity(0.18)))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            ForEach(tiles.map { KeyedTile(id: keys[$0.id] ?? "\($0.id)", tile: $0) }) { keyed in
                if let slot = shown.slot(of: keyed.tile.id) {
                    tileView(keyed.tile, slot: slot, size: tileSize)
                }
            }
            RummyRackMeldMarks(melds: rackMelds, layout: shown, geometry: geometry)
            // 장수 뱃지는 집은 덩어리 **오른쪽 위 바깥**에 하나 — 누른 타일에 달면 이웃 타일 숫자를 가린다(10-30 사용자 지적).
            if let badge = liftBadge, badge.count > 1, let corner = liftedCorner {
                RummyCountBadge(count: badge.count)
                    .position(x: corner.x + 6, y: corner.y - 8)
                    .zIndex(1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            // 첫 등록 전 '랙 묶음 합' — 뒷줄 위 난간 오른쪽(타일을 가리지 않는다).
            if let plan = planPoints {
                RummyRackPlanTag(table: plan.table, rack: plan.rack)
                    .padding(.trailing, geometry.sideInset)
                    .padding(.top, max(1, (geometry.rowBottom(0) - geometry.tileSize.height - 17) / 2))
            }
        }
        .overlay {
            if let turnGlow, !refused {
                RummyTurnGlow(phase: turnGlow)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: turnGlow)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RummyTilePalette.color(RummyTilePalette.invalid), lineWidth: refused ? 3 : 0)
                .padding(2)
        )
    }

    /// 집은 덩어리의 오른쪽 위(들어 올림 5pt 반영). 덩어리가 두 줄에 걸치면 윗줄 기준.
    private var liftedCorner: CGPoint? {
        let frames = tiles.filter { liftedTileIDs.contains($0.id) }
            .compactMap { shownLayout.slot(of: $0.id).map(geometry.frame) }
        guard let top = frames.map(\.minY).min() else { return nil }
        let topRow = frames.filter { abs($0.minY - top) < 1 }
        guard let right = topRow.map(\.maxX).max() else { return nil }
        return CGPoint(x: right, y: top - 5)
    }

    @ViewBuilder
    private func tileView(_ tile: RummyTile, slot: RummyRackSlot, size: RummyTileSize) -> some View {
        let frame = geometry.frame(slot)
        let flying = flyIn.map { $0.tileIDs.contains(tile.id) && !$0.landed } ?? false
        let lifted = liftedTileIDs.contains(tile.id)
        let fresh = freshTileIDs.contains(tile.id) && !lifted
        // 끼워 넣기 미리보기 중엔 끄는 타일을 원래 자리에서 감춘다(이웃이 그 자리로 비켜 설 수 있다).
        let hidden = previewLayout != nil && draggingTileIDs.contains(tile.id)
        let center = flying ? flyOrigin : CGPoint(x: frame.midX, y: frame.midY)
        RummyTileView(face: tile.face, size: size, dimmed: draggingTileIDs.contains(tile.id))
            .overlay(RoundedRectangle(cornerRadius: size.corner + 1, style: .continuous)
                .stroke(CheckTheme.accent, lineWidth: lifted ? 2 : 0).padding(-1.5))
            .overlay(RoundedRectangle(cornerRadius: size.corner + 1, style: .continuous)
                .stroke(RummyCueStyle.fresh, lineWidth: fresh ? 2.5 : 0).padding(-2))
            .shadow(color: RummyCueStyle.fresh.opacity(fresh && !reduceMotion ? 0.9 : 0), radius: 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: fresh)
            .opacity(hidden ? 0 : 1)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(RummyMatchView.space))
                .onChanged { onTileDrag(tile.id, $0) }
                .onEnded { onTileDragEnd(tile.id, $0) })
            .offset(y: lifted ? -5 : 0)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 5, y: 4)
            .scaleEffect(flying ? 0.55 : 1)
            .rotationEffect(.degrees(flying ? -10 : 0))
            .position(center)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)
                .delay(stagger[tile.id] ?? 0), value: center)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72), value: flying)
    }
}

/// 집은 장수 뱃지.
struct RummyCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 20)
            .background(Circle().fill(CheckTheme.accent))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}
