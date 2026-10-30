import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 판 캔버스 (2판 §3 "판 = 테이블 그림 위 자유 배치 캔버스")
//
// 판은 논리 캔버스 1000×640(타일 40×56, `RummyTableLayout`)이고, 위치는 모두에게 같다(서버 `table_layout`).
// 화면은 그 캔버스를 테이블 칸에 **비율 유지로 맞춘다**(`RummyCanvasTransform.fit`). [판 확대] 를 켜면 놓인 묶음을 다 담는
// 사각형(+ 여백)에 맞춰 크게 본다(`zoom` — 묶음은 하나도 안 잘린다). 그리는 자리·누르는 자리·놓는 자리가 이 한 변환에서 나온다.

/// 논리 캔버스 ↔ 테이블 칸 좌표(테이블 칸 왼쪽 위 원점). 순수 값.
struct RummyCanvasTransform: Equatable {
    var scale: CGFloat
    /// 화면 원점(테이블 칸 좌표)에 오는 논리 점.
    var logicalOrigin: CGPoint
    /// 그 논리 점이 놓이는 테이블 칸 좌표.
    var screenOrigin: CGPoint

    static let canvas = CGSize(width: RummyTableLayout.canvasWidth, height: RummyTableLayout.canvasHeight)

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: screenOrigin.x + (p.x - logicalOrigin.x) * scale, y: screenOrigin.y + (p.y - logicalOrigin.y) * scale)
    }

    func toLogical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: logicalOrigin.x + (p.x - screenOrigin.x) / scale, y: logicalOrigin.y + (p.y - screenOrigin.y) / scale)
    }

    func rect(_ r: RummyRect) -> CGRect {
        let o = toScreen(CGPoint(x: r.x, y: r.y))
        return CGRect(x: o.x, y: o.y, width: CGFloat(r.width) * scale, height: CGFloat(r.height) * scale)
    }

    /// 캔버스 전체를 칸 가운데에 비율 유지로.
    static func fit(viewport: CGSize, inset: CGFloat = 6) -> RummyCanvasTransform {
        let w = max(1, viewport.width - inset * 2), h = max(1, viewport.height - inset * 2)
        let scale = min(w / canvas.width, h / canvas.height)
        return RummyCanvasTransform(
            scale: scale, logicalOrigin: .zero,
            screenOrigin: CGPoint(x: (viewport.width - canvas.width * scale) / 2,
                                  y: (viewport.height - canvas.height * scale) / 2))
    }

    /// 놓인 묶음을 다 담는 사각형(+ 가로 두 장·세로 한 줄 여백)에 맞춰 확대. 배율은 [전체 맞춤, `maxScale`] 사이.
    /// 묶음이 없으면 캔버스 왼쪽 위 1/4 를 본다. 보이는 구간은 되도록 캔버스 안으로 민다.
    static func zoom(viewport: CGSize, content: [RummyRect], inset: CGFloat = 12, maxScale: CGFloat = 1) -> RummyCanvasTransform {
        let base = fit(viewport: viewport, inset: inset)
        var region: CGRect
        if let first = content.first {
            region = content.dropFirst().reduce(Self.cg(first)) { $0.union(Self.cg($1)) }
            region = region.insetBy(dx: -CGFloat(RummyTableLayout.tileWidth) * 2, dy: -CGFloat(RummyTableLayout.tileHeight) * 1.3)
        } else {
            region = CGRect(x: 0, y: 0, width: canvas.width / 2, height: canvas.height / 2)
        }
        region = region.intersection(CGRect(origin: .zero, size: canvas))
        let w = max(1, viewport.width - inset * 2), h = max(1, viewport.height - inset * 2)
        let scale = max(base.scale, min(maxScale, w / max(region.width, 1), h / max(region.height, 1)))
        // 묶음이 판 전체에 퍼져 확대할 것이 없으면 그냥 전체 맞춤(여백 6 — 맞춤과 같은 크기).
        if scale <= base.scale + 0.0001 { return fit(viewport: viewport) }
        // 칸 안쪽(여백 뺀) 구간이 보이는 논리 폭. 여백만큼은 펠트만 보인다(묶음이 칸 테두리에 붙지 않게).
        let span = CGSize(width: w / scale, height: h / scale)
        func clampOrigin(_ center: CGFloat, span: CGFloat, limit: CGFloat) -> CGFloat {
            let start = center - span / 2
            if span >= limit { return (limit - span) / 2 }
            return min(max(start, 0), limit - span)
        }
        let origin = CGPoint(x: clampOrigin(region.midX, span: span.width, limit: canvas.width),
                             y: clampOrigin(region.midY, span: span.height, limit: canvas.height))
        return RummyCanvasTransform(scale: scale, logicalOrigin: origin, screenOrigin: CGPoint(x: inset, y: inset))
    }

    private static func cg(_ r: RummyRect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }
}

/// 판 위에 그릴 타일 한 장(편집 가능한 판 = 편집기 타일 id, 남의/확정 판 = id 없음).
struct RummyBoardTile: Hashable {
    let id: Int?
    let face: RummyFace
    let highlighted: Bool
}

/// 판 위 묶음 하나(그릴 값).
struct RummyBoardMeld: Identifiable, Equatable {
    /// 모션 키 — 편집 중엔 첫 타일 id, 남의/확정 판은 면 글자 + 같은 키 안 순번(세트에는 id 가 없다).
    let id: String
    let tiles: [RummyBoardTile]
    let frame: RummyRect
    let invalid: Bool

    /// 모션 키 붙이기(면 글자 + 순번).
    static func faceKeys(_ sets: [[RummyFace]]) -> [String] {
        var seen: [String: Int] = [:]
        return sets.map { set in
            let key = RummyRules.compareKey(set).map(\.text).joined(separator: ",")
            let n = seen[key, default: 0]
            seen[key] = n + 1
            return "f:\(key)#\(n)"
        }
    }
}

/// 판 위 놓기 미리보기.
enum RummyBoardPreview: Equatable {
    /// 이 묶음의 이 자리에 끼운다(파랑 테두리 + 끼울 자리 막대).
    case meld(Int, index: Int)
    /// 빈 곳에 새 묶음 · 묶음 옮기기 — 스냅된 자리(논리)와 장수.
    case ghost(RummyRect)
}

/// 판 칸 — 펠트 위에 묶음을 논리 좌표대로. 끌기 손잡이·타일 끌기는 부르는 쪽(판 화면)의 닫힘으로 보낸다.
struct RummyTableCanvasView: View {
    let melds: [RummyBoardMeld]
    let transform: RummyCanvasTransform
    let size: CGSize
    /// 내 차례(손잡이 · 타일 끌기).
    let editable: Bool
    /// 끌려 나간 타일(흐리게).
    let draggingTileIDs: Set<Int>
    /// 길게 눌러 집힌 타일(들어 올림).
    let liftedTileIDs: Set<Int>
    /// 손잡이로 옮기는 중인 묶음.
    let movingSet: Int?
    let preview: RummyBoardPreview?
    let reduceMotion: Bool
    let onTileDrag: (Int, DragGesture.Value) -> Void
    let onTileDragEnd: (Int, DragGesture.Value) -> Void
    let onHandleDrag: (Int, DragGesture.Value) -> Void
    let onHandleDragEnd: (Int, DragGesture.Value) -> Void

    var body: some View {
        let tile = RummyTileSize.canvas(scale: transform.scale)
        ZStack(alignment: .topLeading) {
            RummyTableSurface()
                .frame(width: size.width, height: size.height)
            ZStack(alignment: .topLeading) {
                if case .ghost(let rect)? = preview {
                    let frame = transform.rect(rect)
                    RoundedRectangle(cornerRadius: 6 * max(transform.scale, 0.6), style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(CheckTheme.accent)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CheckTheme.accent.opacity(0.16)))
                        .frame(width: frame.width + 4, height: frame.height + 4)
                        .position(x: frame.midX, y: frame.midY)
                }
                ForEach(Array(melds.enumerated()), id: \.element.id) { index, meld in
                    meldView(meld, index: index, tile: tile)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func meldView(_ meld: RummyBoardMeld, index: Int, tile: RummyTileSize) -> some View {
        let frame = transform.rect(meld.frame)
        let invalidColor = RummyTilePalette.color(RummyTilePalette.invalid)
        let targetIndex: Int? = { if case .meld(index, let at)? = preview { return at }; return nil }()
        let targeted = targetIndex != nil
        let pad = max(2, 3 * transform.scale)
        let moving = movingSet == index
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: pad * 2, style: .continuous)
                .fill(meld.invalid ? invalidColor.opacity(0.16) : Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: pad * 2, style: .continuous)
                    .stroke(meld.invalid ? invalidColor : (targeted ? CheckTheme.accent : Color.white.opacity(0.08)),
                            lineWidth: meld.invalid || targeted ? 2 : 1))
                .frame(width: frame.width + pad * 2, height: frame.height + pad * 2)
                .offset(x: -pad, y: -pad)
            HStack(spacing: 0) {
                ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, boardTile in
                    tileView(boardTile, size: tile)
                        .frame(width: CGFloat(RummyTableLayout.tileWidth) * transform.scale,
                               height: CGFloat(RummyTableLayout.tileHeight) * transform.scale)
                }
            }
            if let at = targetIndex {
                Capsule()
                    .fill(CheckTheme.accent)
                    .frame(width: 3, height: frame.height + 4)
                    .offset(x: CGFloat(at) * CGFloat(RummyTableLayout.tileWidth) * transform.scale - 1.5, y: -2)
            }
            if editable {
                handle(index: index, height: frame.height)
                    .offset(x: -max(9, 13 * transform.scale), y: 0)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .opacity(moving ? 0.35 : 1)
        .position(x: frame.midX, y: frame.midY)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: frame)
    }

    @ViewBuilder
    private func tileView(_ boardTile: RummyBoardTile, size: RummyTileSize) -> some View {
        let inner = RummyTileSize(CGSize(width: size.size.width - max(1, size.size.width * 0.05),
                                         height: size.size.height - max(1, size.size.width * 0.05)))
        let lifted = boardTile.id.map(liftedTileIDs.contains) ?? false
        let view = RummyTileView(face: boardTile.face, size: inner, highlighted: boardTile.highlighted,
                                 dimmed: boardTile.id.map(draggingTileIDs.contains) ?? false)
            .overlay(RoundedRectangle(cornerRadius: inner.corner + 1, style: .continuous)
                .stroke(CheckTheme.accent, lineWidth: lifted ? 2 : 0).padding(-1.5))
            .offset(y: lifted ? -4 : 0)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 5, y: 4)
        if editable, let id = boardTile.id {
            view.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(RummyMatchView.space))
                .onChanged { onTileDrag(id, $0) }
                .onEnded { onTileDragEnd(id, $0) })
        } else {
            view
        }
    }

    /// 묶음 손잡이(왼쪽 끝) — 잡고 끌면 묶음 통째 위치 이동.
    private func handle(index: Int, height: CGFloat) -> some View {
        let width = max(7, 9 * transform.scale)
        return VStack(spacing: max(2, height * 0.08)) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Color.white.opacity(0.75)).frame(width: max(2.5, width * 0.36))
            }
        }
        .frame(width: width, height: height * 0.86)
        .background(Capsule().fill(Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
        .offset(y: height * 0.07)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(RummyMatchView.space))
            .onChanged { onHandleDrag(index, $0) }
            .onEnded { onHandleDragEnd(index, $0) })
        .checkTooltip("잡고 끌면 묶음을 옮겨요")
    }
}
