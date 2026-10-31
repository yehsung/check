#if os(iOS)
import CheckCore
import SwiftUI

// 폰 아잉 큐브 받침대(맥 `RummyRackView`·`RummyRackCues` 의 그림 — 입력은 없다. 손은 화면 전체 제스처 하나가 받는다).
// 그림 기준선을 쓰지 않고 칸 폭에 맞춘 값(`GamesRummyRackGeometry`)으로 그린다. **받침대 그림(`rummy-rack`)은 판 화면에 깔지 않는다**: 그림의 선반은 높이의 0.44·0.76 에 박혀 있어
// 두 선반 사이가 0.32H 인데, 타일 47pt 를 그 사이에 세우려면 받침대가 155pt 가 돼야 한다(세로 화면 칸은 118). 깔아 보니 그림 선반이 앞줄 타일 중간을 지나갔다 — 그래서 남색 유광 + 분홍 테두리 몸체(`GamesRummyRackFallback`)에 줄마다 선반을 그린다.
// 받침대 타일은 많아야 30장 남짓이라 `GamesRummyTile` 뷰를 그대로 쓴다(판과 다르다 — `GamesRummyTableCanvas` 머리말).

/// 받침대 테두리 빛 단계.
enum GamesRummyTurnGlowPhase: Equatable {
    /// 차례가 막 왔다(한 번 크게).
    case pulse
    /// 그 뒤 차례 내내 은은하게.
    case steady
}

struct GamesRummyRackPane: View {
    private struct KeyedTile: Identifiable {
        let id: String
        let tile: RummyTile
    }

    let model: GamesRummyMatchModel
    let tiles: [RummyTile]
    let layout: RummyRackLayout
    let geometry: GamesRummyRackGeometry
    /// 받침대에서 그대로 맞는 덩어리(밑줄 띠 + 점수).
    let rackMelds: [RummyRackMeld]
    let turnGlow: GamesRummyTurnGlowPhase?
    /// 방금 뽑은 타일(3초 빛남).
    let freshIDs: Set<Int>
    /// 정렬 시차(타일 id → 지연 · `GamesRummyRackMotion.sortStagger`).
    var stagger: [Int: TimeInterval] = [:]
    /// 뽑은 타일이 날아오는 중 · 내려앉았는가(`GamesRummyRackMotion.flight`). 동작 줄이기면 nil 이다.
    var flight: (ids: Set<Int>, landed: Bool)? = nil
    /// [뽑기] 칸 가운데(받침대 칸 좌표).
    var flightOrigin: CGPoint = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let preview = model.rackPreview
        let shown = preview?.layout ?? layout
        // 미리보기가 새 줄을 열면 그리는 기하만 그 줄 수로(칸은 굳어 있으니 타일이 줄어 담긴다 · 놓는 판정 기하는 그대로 — 끄는 동안 되먹임이 없게).
        let draw = preview.map { GamesRummyRackGeometry(size: geometry.size, rowCount: $0.layout.rowCount) } ?? geometry
        let refused = model.hoverRefused || model.refusedFlash
        let lifted = model.lift?.surface == .rack ? Set(model.lift?.ids ?? []) : []
        let keys = GamesRummyRackGeometry.motionKeys(tiles)
        ZStack(alignment: .topLeading) {
            GamesRummyRackFallback()
                .frame(width: geometry.size.width, height: geometry.size.height)
            GamesRummyRackLedges(geometry: draw)
            ForEach(Array((preview?.ghosts ?? []).enumerated()), id: \.offset) { _, slot in
                let frame = draw.frame(slot)
                RoundedRectangle(cornerRadius: RummyTileSize(draw.tileSize).corner, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .foregroundStyle(MobileTheme.accent)
                    .background(RoundedRectangle(cornerRadius: RummyTileSize(draw.tileSize).corner, style: .continuous)
                        .fill(MobileTheme.accent.opacity(0.18)))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            ForEach(tiles.map { KeyedTile(id: keys[$0.id] ?? "\($0.id)", tile: $0) }) { keyed in
                if let slot = shown.slot(of: keyed.tile.id) {
                    tileView(keyed.tile, frame: draw.frame(slot), hidden: preview != nil && model.draggingIDs.contains(keyed.tile.id),
                             lifted: lifted.contains(keyed.tile.id))
                }
            }
            GamesRummyRackMeldMarks(melds: preview?.melds ?? rackMelds, layout: shown, geometry: draw)
            if lifted.count > 1, let corner = liftedCorner(lifted, layout: shown, geometry: draw) {
                GamesRummyCountBadge(count: lifted.count)
                    .position(x: corner.x + 4, y: max(10, corner.y - 6))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .overlay {
            if let turnGlow, !refused {
                let pulse = turnGlow == .pulse
                // 굵기 · 번짐만 줄인다 — 불투명도를 이징으로 깎지 않는다.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MobileTheme.accent, lineWidth: pulse ? 4 : 2)
                    .shadow(color: MobileTheme.accent.opacity(0.7), radius: pulse ? 12 : 5)
                    .padding(1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: turnGlow)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RummyTilePalette.color(RummyTilePalette.invalid), lineWidth: refused ? 3 : 0)
                .padding(1)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GamesRummyText.rackSummary(tiles.count))
    }

    private func liftedCorner(_ ids: Set<Int>, layout: RummyRackLayout, geometry: GamesRummyRackGeometry) -> CGPoint? {
        let frames = tiles.filter { ids.contains($0.id) }.compactMap { layout.slot(of: $0.id).map(geometry.frame) }
        guard let top = frames.map(\.minY).min() else { return nil }
        guard let right = frames.filter({ abs($0.minY - top) < 1 }).map(\.maxX).max() else { return nil }
        return CGPoint(x: right, y: top - 5)
    }

    private func tileView(_ tile: RummyTile, frame: CGRect, hidden: Bool, lifted: Bool) -> some View {
        let size = RummyTileSize(frame.size)
        let fresh = freshIDs.contains(tile.id) && !lifted
        let inFlight = flight?.ids.contains(tile.id) == true
        let flying = inFlight && flight?.landed == false
        return GamesRummyTile(face: tile.face, size: frame.size, dimmed: model.draggingIDs.contains(tile.id))
            .overlay(RoundedRectangle(cornerRadius: size.corner + 1, style: .continuous)
                .stroke(MobileTheme.accent, lineWidth: lifted ? 2 : 0).padding(-1.5))
            .overlay(RoundedRectangle(cornerRadius: size.corner + 1, style: .continuous)
                .stroke(MobileTheme.pending, lineWidth: fresh ? 2.5 : 0).padding(-2))
            .offset(y: lifted ? -5 : 0)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 5, y: 4)
            .scaleEffect(flying ? 0.55 : 1)
            .rotationEffect(.degrees(flying ? -10 : 0))
            .position(flying ? flightOrigin : CGPoint(x: frame.midX, y: frame.midY))
            // 자리가 바뀔 때만 미끄러진다(정렬 · 끼워 넣기 미리보기 · 뽑기). 아래 불투명도는 이 애니메이션 밖이다 — 감추기는 곧바로.
            .animation(reduceMotion ? nil : (inFlight ? .spring(response: 0.45, dampingFraction: 0.72)
                                                       : .spring(response: 0.38, dampingFraction: 0.82).delay(stagger[tile.id] ?? 0)),
                       value: flying ? flightOrigin : CGPoint(x: frame.midX, y: frame.midY))
            .opacity(hidden ? 0 : 1)
    }
}

/// 타일이 서는 선반 — 줄마다 아래에 분홍빛 턱.
private struct GamesRummyRackLedges: View {
    let geometry: GamesRummyRackGeometry

    var body: some View {
        Canvas { context, size in
            for row in 0..<geometry.rowCount {
                let y = geometry.rowTop(row) + geometry.tileSize.height + 0.5
                let bar = CGRect(x: 6, y: y, width: size.width - 12, height: 2.5)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.25),
                             with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.80).opacity(0.75),
                                                                     Color(red: 0.62, green: 0.42, blue: 1.0).opacity(0.75)]),
                                                   startPoint: CGPoint(x: bar.minX, y: y), endPoint: CGPoint(x: bar.maxX, y: y)))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityHidden(true)
    }
}

/// 받침대에서 그대로 맞는 덩어리 — 타일 아랫단에 초록 띠 + 점수.
private struct GamesRummyRackMeldMarks: View {
    let melds: [RummyRackMeld]
    let layout: RummyRackLayout
    let geometry: GamesRummyRackGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(melds.enumerated()), id: \.offset) { _, meld in
                if let frame = frame(of: meld) {
                    Text(verbatim: "\(meld.points)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: frame.width, height: frame.height)
                        .background(Capsule().fill(MobileTheme.working))
                        .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 띠 자리: 덩어리 가로(양끝 4pt 안쪽) · 타일 아랫단 5pt 위부터 11pt(줄 사이 틈이 좁아 밖에 따로 둘 자리가 없다).
    private func frame(of meld: RummyRackMeld) -> CGRect? {
        let frames = meld.tileIDs.compactMap { layout.slot(of: $0).map(geometry.frame) }
        guard let first = frames.first, let last = frames.last else { return nil }
        return CGRect(x: first.minX + 4, y: first.maxY - 5, width: last.maxX - first.minX - 8, height: 11)
    }
}

/// 집은 장수 배지.
struct GamesRummyCountBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 20, minHeight: 20)
            .background(Circle().fill(MobileTheme.accentFill))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
    }
}

/// 손에 든 타일 — **이 뷰만 손가락 자리를 읽는다**(`model.drag`). 받침대·판은 손이 움직여도 다시 그려지지 않는다.
struct GamesRummyFloatingBlock: View {
    let model: GamesRummyMatchModel
    let context: GamesRummyTouchContext

    var body: some View {
        if let drag = model.drag {
            let current = context.with(viewport: model.viewport)
            let tile = GamesRummyFloatingLayout.tileSize(drag, current)
            let frames = GamesRummyFloatingLayout.frames(drag, tile: tile, tableScale: current.viewport.scale)
            let refused = model.hoverRefused
            ZStack(alignment: .topLeading) {
                ForEach(Array(drag.tiles.enumerated()), id: \.element.id) { index, tile in
                    let frame = frames[index]
                    GamesRummyTile(face: tile.face, size: frame.size)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 8, y: 6)
            // 아래 놓을 자리 점선이 비쳐 보이게(1.25 배라 점선이 타일 뒤에 다 숨는다).
            .opacity(0.82)
            .overlay(alignment: .topLeading) {
                if let last = frames.last {
                    if refused {
                        Image(systemName: "nosign")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(RummyTilePalette.color(RummyTilePalette.invalid))
                            .background(Circle().fill(Color.white).padding(-1))
                            .position(x: last.maxX, y: last.minY)
                    } else if drag.tiles.count > 1 {
                        GamesRummyCountBadge(count: drag.tiles.count)
                            .position(x: last.maxX, y: last.minY)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
#endif
