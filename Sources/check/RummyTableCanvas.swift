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

/// 판 위 놓기 미리보기(3판 — 편집기 `previewDrop`·`previewMoveSet` 의 계획을 그릴 값으로, 논리 좌표).
/// 놓기 전에 "어디에 어떻게 들어가는가"를 보인다: 붙을 끝에 자석 · 끼울 자리 캐럿 · 새 묶음 점선.
/// 색: 놓은 뒤 그 묶음이 맞는 세트면 초록(+ 체크), 아직 아니면 파랑.
enum RummyBoardPreview: Equatable {
    /// 묶음 위에 놓아 맞는 자리에 끼운다 — 캐럿(지금 화면의 논리 x) + 놓은 뒤 묶음 윤곽.
    case insert(set: Int, caretX: Int, landing: RummyRect, valid: Bool)
    /// 다른 묶음 끝에 붙는다 — 대상 묶음의 그 끝에 자석 + 블록이 들어갈 칸 점선.
    case attach(set: Int, side: RummyAttachSide, slots: RummyRect, landing: RummyRect, valid: Bool)
    /// 빈 곳에 새 묶음 · 묶음 옮기기 — 스냅된 자리 점선.
    case ghost(RummyRect)

    /// 미리보기가 가리키는 묶음(테두리를 밝힌다).
    var targetSet: Int? {
        switch self {
        case .insert(let set, _, _, _), .attach(let set, _, _, _, _): return set
        case .ghost: return nil
        }
    }

    /// 자석이 설 이음 x(논리) — 블록 칸의 대상 쪽 끝. 대상 오른끝에 붙으면 칸 왼쪽, 왼끝에 붙으면 칸 오른쪽.
    /// 대상이 지금 끌고 있는 묶음의 토막일 때(끝 타일을 빼서 제자리 곁에 다시 놓기 · 가운데 빼서 틈에 다시 놓기) 옮기기 전
    /// 묶음 끝(`frames[set]`)은 이음 자리가 아니다 — 늘 칸으로 잰다.
    var magnetSeamX: Int? {
        guard case .attach(_, let side, let slots, _, _) = self else { return nil }
        return side == .right ? slots.x : slots.maxX
    }

    /// 놓으면 그 묶음이 맞는 세트가 되는가(초록).
    var completes: Bool {
        switch self {
        case .insert(_, _, _, let valid), .attach(_, _, _, _, let valid): return valid
        case .ghost: return false
        }
    }

    /// 편집기 답 → 그릴 값. `meldTileIDs` = 지금 화면 묶음별 타일 id(화면 순), `frames` = 지금 묶음 사각형,
    /// `dragged` = 손에 든 타일(제자리에 흐리게 남아 있다 — 캐럿은 그것을 뺀 타일 사이에 선다). 받침대행·거절은 nil.
    static func make(_ preview: RummyDropPreview?, blockCount: Int, meldTileIDs: [[Int]], frames: [RummyRect],
                     dragged: Set<Int>) -> RummyBoardPreview? {
        guard let preview, let landing = preview.landing else { return nil }
        let w = RummyTableLayout.tileWidth
        switch preview.plan {
        case .rack: return nil
        case .newSet: return .ghost(landing.frame)
        case .attach(let set, let side):
            guard frames.indices.contains(set) else { return .ghost(landing.frame) }
            let slots = RummyRect(x: landing.frame.x + landing.blockStart * w, y: landing.frame.y,
                                  width: max(1, blockCount) * w, height: RummyTableLayout.tileHeight)
            return .attach(set: set, side: side, slots: slots, landing: landing.frame, valid: landing.valid)
        case .insert(let set, let index):
            guard frames.indices.contains(set), meldTileIDs.indices.contains(set) else { return .ghost(landing.frame) }
            let ids = meldTileIDs[set]
            let kept = ids.indices.filter { !dragged.contains(ids[$0]) }
            let slot: Int
            if kept.isEmpty {
                slot = 0
            } else if index < kept.count {
                slot = kept[max(0, index)]
            } else {
                slot = kept[kept.count - 1] + 1
            }
            return .insert(set: set, caretX: frames[set].x + slot * w, landing: landing.frame, valid: landing.valid)
        }
    }
}

/// 판 위 타일 한 장의 자리(논리 왼쪽 위). 타일마다 따로 그려야 묶음이 나뉘고 붙고 끼워질 때 **각 타일이** 제자리에서 미끄러진다.
private struct RummyPlacedTile: Identifiable {
    /// 모션 키 — 편집 중엔 타일 id(묶음을 건너가도 같은 타일), 남의/확정 판은 묶음 키 + 자리.
    let id: String
    let tile: RummyBoardTile
    let meld: Int
    let origin: CGPoint
}

/// 판 칸 — 펠트 위에 묶음을 논리 좌표대로. 끌기 손잡이·타일 끌기는 부르는 쪽(판 화면)의 닫힘으로 보낸다.
///
/// 모션(동작 줄이기면 전부 끈다): 타일은 id 로 잡아 자리가 바뀌면 스프링으로 미끄러진다 — 가운데를 빼서 나뉘어도 남은 타일은
/// 제자리(편집기 규칙 ①), 끼우면 밀려난 타일만 옆으로, 붙으면 받은 묶음 상자가 늘어난다. 방금 놓은 타일은 `arrivals`(손을 놓은
/// 자리)에서 출발해 들어갈 자리로 미끄러진다 — 맞는 자리로 자동 배치되는 것이 눈에 보이게.
struct RummyTableCanvasView: View {
    static let slide = Animation.spring(response: 0.38, dampingFraction: 0.84)

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
    /// 방금 놓은 타일의 출발 자리(논리 왼쪽 위) — 이 한 장면만 거기 그리고 다음 장면에서 제자리로 미끄러진다.
    let arrivals: [Int: CGPoint]
    /// 방금 놓은 타일 — 묶음 상자 모션 키에서 뺀다(앞에 붙거나 끼워도 상자가 새로 생기지 않고 늘어나게).
    let recentTileIDs: Set<Int>
    let reduceMotion: Bool
    let onTileDrag: (Int, DragGesture.Value) -> Void
    let onTileDragEnd: (Int, DragGesture.Value) -> Void
    let onHandleDrag: (Int, DragGesture.Value) -> Void
    let onHandleDragEnd: (Int, DragGesture.Value) -> Void

    private var tileW: CGFloat { CGFloat(RummyTableLayout.tileWidth) * transform.scale }
    private var tileH: CGFloat { CGFloat(RummyTableLayout.tileHeight) * transform.scale }
    private var pad: CGFloat { max(2, 3 * transform.scale) }

    var body: some View {
        let tile = RummyTileSize.canvas(scale: transform.scale)
        let boxes = melds.enumerated().map { (key: boxKey($0.element), index: $0.offset, meld: $0.element) }
        ZStack(alignment: .topLeading) {
            RummyTableSurface()
                .frame(width: size.width, height: size.height)
            ZStack(alignment: .topLeading) {
                if let preview { previewUnder(preview) }
                ForEach(boxes, id: \.key) { box($0.meld, index: $0.index) }
                ForEach(placedTiles) { tileView($0, size: tile) }
                if editable {
                    ForEach(boxes, id: \.key) { handle(index: $0.index, frame: $0.meld.frame) }
                }
                if let preview { previewOver(preview) }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: 값

    /// 묶음 상자 모션 키 — 방금 놓은 타일을 뺀 가장 작은 타일 id(다 방금 놓은 것이면 그중 가장 작은 것). 앞에 붙거나 끼워도,
    /// 가운데를 빼서 나뉘어도 원래 상자(왼 토막)는 키가 그대로라 늘고 주는 것으로 보인다. 남의/확정 판은 면 글자 키.
    private func boxKey(_ meld: RummyBoardMeld) -> String {
        let ids = meld.tiles.compactMap(\.id)
        guard let anchor = ids.filter({ !recentTileIDs.contains($0) }).min() ?? ids.min() else { return meld.id }
        return "b\(anchor)"
    }

    private var placedTiles: [RummyPlacedTile] {
        let w = CGFloat(RummyTableLayout.tileWidth)
        return melds.enumerated().flatMap { index, meld in
            meld.tiles.enumerated().map { slot, tile in
                RummyPlacedTile(id: tile.id.map { "t\($0)" } ?? "\(meld.id)/\(slot)", tile: tile, meld: index,
                                origin: CGPoint(x: CGFloat(meld.frame.x) + CGFloat(slot) * w, y: CGFloat(meld.frame.y)))
            }
        }
    }

    private func tint(valid: Bool) -> Color { valid ? CheckTheme.working : CheckTheme.accent }

    // MARK: 묶음 상자 · 타일 · 손잡이

    private func box(_ meld: RummyBoardMeld, index: Int) -> some View {
        let frame = transform.rect(meld.frame)
        let invalidColor = RummyTilePalette.color(RummyTilePalette.invalid)
        let targeted = preview?.targetSet == index
        let targetColor = tint(valid: preview?.completes == true)
        return RoundedRectangle(cornerRadius: pad * 2, style: .continuous)
            .fill(meld.invalid ? invalidColor.opacity(0.16) : Color.black.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: pad * 2, style: .continuous)
                .stroke(targeted ? targetColor : (meld.invalid ? invalidColor : Color.white.opacity(0.08)),
                        lineWidth: meld.invalid || targeted ? 2 : 1))
            .frame(width: frame.width + pad * 2, height: frame.height + pad * 2)
            .opacity(movingSet == index ? 0.35 : 1)
            .position(x: frame.midX, y: frame.midY)
            .animation(reduceMotion ? nil : Self.slide, value: meld.frame)
    }

    @ViewBuilder
    private func tileView(_ placed: RummyPlacedTile, size: RummyTileSize) -> some View {
        let boardTile = placed.tile
        let inner = RummyTileSize(CGSize(width: size.size.width - max(1, size.size.width * 0.05),
                                         height: size.size.height - max(1, size.size.width * 0.05)))
        let lifted = boardTile.id.map(liftedTileIDs.contains) ?? false
        let start = reduceMotion ? nil : boardTile.id.flatMap { arrivals[$0] }
        let origin = start ?? placed.origin
        let screen = transform.toScreen(origin)
        let view = RummyTileView(face: boardTile.face, size: inner, highlighted: boardTile.highlighted,
                                 dimmed: boardTile.id.map(draggingTileIDs.contains) ?? false)
            .overlay(RoundedRectangle(cornerRadius: inner.corner + 1, style: .continuous)
                .stroke(CheckTheme.accent, lineWidth: lifted ? 2 : 0).padding(-1.5))
            .offset(y: lifted ? -4 : 0)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 5, y: 4)
            .frame(width: tileW, height: tileH)
            .opacity(movingSet == placed.meld ? 0.35 : 1)
        Group {
            if editable, let id = boardTile.id {
                view.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(RummyMatchView.space))
                    .onChanged { onTileDrag(id, $0) }
                    .onEnded { onTileDragEnd(id, $0) })
            } else {
                view
            }
        }
        .position(x: screen.x + tileW / 2, y: screen.y + tileH / 2)
        // 출발 장면은 손을 놓은 자리에 바로 — 다음 장면(출발 자리가 빠짐)부터 스프링.
        .animation(reduceMotion || start != nil ? nil : Self.slide, value: origin)
    }

    /// 묶음 손잡이(왼쪽 끝) — 잡고 끌면 묶음 통째 위치 이동.
    private func handle(index: Int, frame logical: RummyRect) -> some View {
        let frame = transform.rect(logical)
        let width = max(7, 9 * transform.scale)
        let height = frame.height
        return VStack(spacing: max(2, height * 0.08)) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Color.white.opacity(0.75)).frame(width: max(2.5, width * 0.36))
            }
        }
        .frame(width: width, height: height * 0.86)
        .background(Capsule().fill(Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(RummyMatchView.space))
            .onChanged { onHandleDrag(index, $0) }
            .onEnded { onHandleDragEnd(index, $0) })
        .checkTooltip("잡고 끌면 묶음을 옮겨요")
        .opacity(movingSet == index ? 0.35 : 1)
        .position(x: frame.minX - max(9, 13 * transform.scale) + width / 2, y: frame.midY)
        .animation(reduceMotion ? nil : Self.slide, value: logical)
    }

    // MARK: 놓기 미리보기

    /// 타일 아래: 새 묶음 점선 · 붙을 칸 점선 · 끼운 뒤 묶음 윤곽.
    @ViewBuilder
    private func previewUnder(_ preview: RummyBoardPreview) -> some View {
        switch preview {
        case .ghost(let rect):
            dashed(rect, color: CheckTheme.accent, fill: 0.16, grow: 2)
        case .attach(_, _, let slots, _, let valid):
            dashed(slots, color: tint(valid: valid), fill: 0.2, grow: 1)
        case .insert(_, _, let landing, let valid):
            dashed(landing, color: tint(valid: valid), fill: 0.1, grow: pad + 3)
        }
    }

    /// 타일 위: 끼울 자리 캐럿 · 붙을 끝 자석 · 맞는 세트가 되면 체크.
    @ViewBuilder
    private func previewOver(_ preview: RummyBoardPreview) -> some View {
        switch preview {
        case .ghost:
            EmptyView()
        case .insert(let set, let caretX, let landing, let valid):
            if let frame = melds.indices.contains(set) ? transform.rect(melds[set].frame) : nil {
                let x = transform.toScreen(CGPoint(x: CGFloat(caretX), y: 0)).x
                RummyInsertCaret(color: tint(valid: valid), height: frame.height + pad * 2 + 8)
                    .position(x: x, y: frame.midY)
            }
            if valid { checkBadge(landing) }
        case .attach(_, let side, let slots, let landing, let valid):
            // 자석은 **실제 이음 자리**(블록 칸의 대상 쪽 끝)에 — 대상이 끌어 온 묶음의 토막이면 옮기기 전 묶음 끝과 다르다.
            let frame = transform.rect(slots)
            RummyMagnetSeam(color: tint(valid: valid), height: frame.height + pad * 2 + 6, side: side,
                            badge: max(20, 26 * transform.scale))
                .position(x: transform.toScreen(CGPoint(x: CGFloat(preview.magnetSeamX ?? slots.x), y: 0)).x, y: frame.midY)
            if valid { checkBadge(landing) }
        }
    }

    private func dashed(_ rect: RummyRect, color: Color, fill: Double, grow: CGFloat) -> some View {
        let frame = transform.rect(rect)
        return RoundedRectangle(cornerRadius: 6 * max(transform.scale, 0.6), style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(fill)))
            .frame(width: frame.width + grow * 2, height: frame.height + grow * 2)
            .position(x: frame.midX, y: frame.midY)
    }

    /// 놓으면 맞는 세트가 된다 — 놓은 뒤 묶음 오른쪽 위 초록 체크.
    private func checkBadge(_ landing: RummyRect) -> some View {
        let frame = transform.rect(landing)
        let d = max(14, 18 * transform.scale)
        return Image(systemName: "checkmark")
            .font(.system(size: d * 0.55, weight: .black))
            .foregroundStyle(Color.black.opacity(0.8))
            .frame(width: d, height: d)
            .background(Circle().fill(CheckTheme.working))
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .position(x: frame.maxX + pad, y: frame.minY - pad)
    }
}

/// 끼울 자리 캐럿 — 타일 사이에 서는 빛나는 세로 막대(위아래 둥근 머리).
private struct RummyInsertCaret: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(color).frame(width: 9, height: 9)
            Capsule().fill(color).frame(width: 4, height: max(8, height - 18))
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .overlay(Capsule().fill(Color.white.opacity(0.7)).frame(width: 1.4, height: max(4, height - 22)))
        .shadow(color: color.opacity(0.9), radius: 6)
        .frame(width: 12, height: height)
    }
}

/// 붙을 끝 자석 — 대상 묶음 끝에 빛나는 이음 막대 + 그 위에 말굽자석 배지(열린 쪽이 블록이 붙는 쪽).
private struct RummyMagnetSeam: View {
    let color: Color
    let height: CGFloat
    let side: RummyAttachSide
    let badge: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(color).frame(width: 5, height: height)
                .shadow(color: color.opacity(0.95), radius: 7)
                .shadow(color: color.opacity(0.6), radius: 14)
            RummyMagnetShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: badge * 0.17, lineCap: .butt, lineJoin: .round))
                .overlay(RummyMagnetTips().fill(Color(white: 0.2)))
                .frame(width: badge * 0.56, height: badge * 0.6)
                // 🧲 처럼 비스듬히 — 열린 쪽이 블록이 붙는 쪽 위로.
                .rotationEffect(.degrees(side == .right ? 45 : -45))
                .frame(width: badge, height: badge)
                .background(Circle().fill(color))
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(y: -height / 2 - badge * 0.3)
        }
        .frame(width: badge, height: height)
    }
}

/// 말굽(위가 열린 U) — 다리 둘 + 아래 둥근 굽.
private struct RummyMagnetShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.15
        let left = rect.minX + inset, right = rect.maxX - inset
        let bend = rect.minY + rect.height * 0.4
        let bottom = rect.maxY - inset
        var p = Path()
        p.move(to: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: bend))
        p.addCurve(to: CGPoint(x: right, y: bend),
                   control1: CGPoint(x: left, y: bend + (bottom - bend) * 4 / 3),
                   control2: CGPoint(x: right, y: bend + (bottom - bend) * 4 / 3))
        p.addLine(to: CGPoint(x: right, y: rect.minY))
        return p
    }
}

/// 말굽 다리 끝(극) — 어두운 띠.
private struct RummyMagnetTips: Shape {
    func path(in rect: CGRect) -> Path {
        let leg = rect.width * 0.3
        let h = rect.height * 0.2
        var p = Path()
        p.addRect(CGRect(x: rect.minX, y: rect.minY, width: leg, height: h))
        p.addRect(CGRect(x: rect.maxX - leg, y: rect.minY, width: leg, height: h))
        return p
    }
}
