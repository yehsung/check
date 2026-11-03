import CoreGraphics
import Foundation

// 아잉 큐브 판의 순수 값 — 맥·폰 공용(0.3.71 맥 `RummyTableCanvas`·`RummyPanelMatch` 에서 폰 1.0.16 을 위해 옮겼다. 동작은 그대로다).
// 판은 논리 캔버스 1000×640(타일 40×56, `RummyTableLayout`)이고, 위치는 모두에게 같다(서버 `table_layout`).
// 그리는 자리·누르는 자리·놓는 자리가 한 변환(`RummyCanvasTransform`)에서 나온다.

/// 논리 캔버스 ↔ 테이블 칸 좌표(테이블 칸 왼쪽 위 원점). 순수 값.
package struct RummyCanvasTransform: Equatable, Sendable {
    package var scale: CGFloat
    /// 화면 원점(테이블 칸 좌표)에 오는 논리 점.
    package var logicalOrigin: CGPoint
    /// 그 논리 점이 놓이는 테이블 칸 좌표.
    package var screenOrigin: CGPoint

    package init(scale: CGFloat, logicalOrigin: CGPoint, screenOrigin: CGPoint) {
        self.scale = scale
        self.logicalOrigin = logicalOrigin
        self.screenOrigin = screenOrigin
    }

    package static let canvas = CGSize(width: RummyTableLayout.canvasWidth, height: RummyTableLayout.canvasHeight)

    package func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: screenOrigin.x + (p.x - logicalOrigin.x) * scale, y: screenOrigin.y + (p.y - logicalOrigin.y) * scale)
    }

    package func toLogical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: logicalOrigin.x + (p.x - screenOrigin.x) / scale, y: logicalOrigin.y + (p.y - screenOrigin.y) / scale)
    }

    package func rect(_ r: RummyRect) -> CGRect {
        let o = toScreen(CGPoint(x: r.x, y: r.y))
        return CGRect(x: o.x, y: o.y, width: CGFloat(r.width) * scale, height: CGFloat(r.height) * scale)
    }

    /// 캔버스 전체를 칸 가운데에 비율 유지로.
    package static func fit(viewport: CGSize, inset: CGFloat = 6) -> RummyCanvasTransform {
        let w = max(1, viewport.width - inset * 2), h = max(1, viewport.height - inset * 2)
        let scale = min(w / canvas.width, h / canvas.height)
        return RummyCanvasTransform(
            scale: scale, logicalOrigin: .zero,
            screenOrigin: CGPoint(x: (viewport.width - canvas.width * scale) / 2,
                                  y: (viewport.height - canvas.height * scale) / 2))
    }

    /// 놓인 묶음을 다 담는 사각형(+ 가로 두 장·세로 한 줄 여백)에 맞춰 확대. 배율은 [전체 맞춤, `maxScale`] 사이.
    /// 묶음이 없으면 캔버스 왼쪽 위 1/4 를 본다. 가로 구간은 되도록 캔버스 안으로 민다.
    /// 세로는 묶음을 칸 가운데에 둔다(사용자 10-31 "다음 판에 세로 가운데로" — 위 줄부터 채우는 판이 위로 붙어 아래가 비었다).
    /// 그래서 구간이 캔버스 위·아래로 나갈 수 있다 — 거기 놓아도 편집기 `clampInside` 가 캔버스 안으로 들인다.
    /// 여백 20(0.3.70 — 12 였다): [판 확대]가 기본이 되며 캔버스 왼끝(x 0) 묶음의 손잡이(묶음 왼쪽 13 단위 밖)가 판 테두리에
    /// 잘렸다(렌더 `rummy370-board-default`).
    package static func zoom(viewport: CGSize, content: [RummyRect], inset: CGFloat = 20, maxScale: CGFloat = 1) -> RummyCanvasTransform {
        let base = fit(viewport: viewport, inset: inset)
        var region: CGRect
        let bounds = content.first.map { first in content.dropFirst().reduce(Self.cg(first)) { $0.union(Self.cg($1)) } }
        if let bounds {
            region = bounds.insetBy(dx: -CGFloat(RummyTableLayout.tileWidth) * 2, dy: -CGFloat(RummyTableLayout.tileHeight) * 1.3)
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
                             y: bounds.map { $0.midY - span.height / 2 }
                                 ?? clampOrigin(region.midY, span: span.height, limit: canvas.height))
        return RummyCanvasTransform(scale: scale, logicalOrigin: origin, screenOrigin: CGPoint(x: inset, y: inset))
    }

    private static func cg(_ r: RummyRect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }
}

/// 판 위에 그릴 타일 한 장(편집 가능한 판 = 편집기 타일 id, 남의/확정 판 = id 없음).
package struct RummyBoardTile: Hashable, Sendable {
    package let id: Int?
    package let face: RummyFace
    package let highlighted: Bool

    package init(id: Int?, face: RummyFace, highlighted: Bool) {
        self.id = id
        self.face = face
        self.highlighted = highlighted
    }
}

/// 판 위 묶음 하나(그릴 값).
package struct RummyBoardMeld: Identifiable, Equatable, Sendable {
    /// 모션 키 — 편집 중엔 첫 타일 id, 남의/확정 판은 면 글자 + 같은 키 안 순번(세트에는 id 가 없다).
    package let id: String
    package let tiles: [RummyBoardTile]
    package let frame: RummyRect
    package let invalid: Bool

    package init(id: String, tiles: [RummyBoardTile], frame: RummyRect, invalid: Bool) {
        self.id = id
        self.tiles = tiles
        self.frame = frame
        self.invalid = invalid
    }

    /// 모션 키 붙이기(면 글자 + 순번).
    package static func faceKeys(_ sets: [[RummyFace]]) -> [String] {
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
package enum RummyBoardPreview: Equatable, Sendable {
    /// 묶음 위에 놓아 맞는 자리에 끼운다 — 캐럿(지금 화면의 논리 x) + 놓은 뒤 묶음 윤곽.
    case insert(set: Int, caretX: Int, landing: RummyRect, valid: Bool)
    /// 다른 묶음 끝에 붙는다 — 대상 묶음의 그 끝에 자석 + 블록이 들어갈 칸 점선.
    case attach(set: Int, side: RummyAttachSide, slots: RummyRect, landing: RummyRect, valid: Bool)
    /// 빈 곳에 새 묶음 · 묶음 옮기기 — 스냅된 자리 점선.
    case ghost(RummyRect)

    /// 미리보기가 가리키는 묶음(테두리를 밝힌다).
    package var targetSet: Int? {
        switch self {
        case .insert(let set, _, _, _), .attach(let set, _, _, _, _): return set
        case .ghost: return nil
        }
    }

    /// 자석이 설 이음 x(논리) — 블록 칸의 대상 쪽 끝. 대상 오른끝에 붙으면 칸 왼쪽, 왼끝에 붙으면 칸 오른쪽.
    /// 대상이 지금 끌고 있는 묶음의 토막일 때(끝 타일을 빼서 제자리 곁에 다시 놓기 · 가운데 빼서 틈에 다시 놓기) 옮기기 전
    /// 묶음 끝(`frames[set]`)은 이음 자리가 아니다 — 늘 칸으로 잰다.
    package var magnetSeamX: Int? {
        guard case .attach(_, let side, let slots, _, _) = self else { return nil }
        return side == .right ? slots.x : slots.maxX
    }

    /// 첫 등록 전(R-12) 판 묶음에 꽂기: 세트는 맞아도 차례가 `initial_table_touched` 로 막힌다 — 초록·체크(맞음)를 거둔다
    /// (파랑 = 아직 아님). 3판 검증: 등록 전 판 묶음 위로 끌면 초록 체크가 떠서 놓고 [완료]를 눌러야 막히는 것을 알았다.
    package func beforeInitial(touchesTable: Bool) -> RummyBoardPreview {
        guard touchesTable, case .insert(let set, let caretX, let landing, true) = self else { return self }
        return .insert(set: set, caretX: caretX, landing: landing, valid: false)
    }

    /// 놓으면 그 묶음이 맞는 세트가 되는가(초록).
    package var completes: Bool {
        switch self {
        case .insert(_, _, _, let valid), .attach(_, _, _, _, let valid): return valid
        case .ghost: return false
        }
    }

    /// 편집기 답 → 그릴 값. `meldTileIDs` = 지금 화면 묶음별 타일 id(화면 순), `frames` = 지금 묶음 사각형,
    /// `dragged` = 손에 든 타일(제자리에 흐리게 남아 있다 — 캐럿은 그것을 뺀 타일 사이에 선다). 받침대행·거절은 nil.
    package static func make(_ preview: RummyDropPreview?, blockCount: Int, meldTileIDs: [[Int]], frames: [RummyRect],
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

/// 상대 자리 배치 — 나 다음 사람부터 왼쪽 → 위 → 오른쪽(둘이면 위, 셋이면 왼·오른). 순수.
package struct RummySeatArrangement: Equatable, Sendable {
    package var left: Int?
    package var top: Int?
    package var right: Int?

    package init(left: Int? = nil, top: Int? = nil, right: Int? = nil) {
        self.left = left
        self.top = top
        self.right = right
    }

    /// 내 다음 차례부터 차례 순서(폰 상대 줄이 가로로 늘어놓는다).
    package var turnOrder: [Int] { [left, top, right].compactMap { $0 } }

    /// `seatNos` = 판의 자리 번호들, `mine` = 내 자리.
    package static func arrange(seatNos: [Int], mine: Int?) -> RummySeatArrangement {
        let sorted = seatNos.sorted()
        guard let mine, let at = sorted.firstIndex(of: mine) else {
            let others = sorted
            return place(others)
        }
        let others = Array(sorted[(at + 1)...] + sorted[..<at])
        return place(others)
    }

    private static func place(_ others: [Int]) -> RummySeatArrangement {
        switch others.count {
        case 0: return RummySeatArrangement()
        case 1: return RummySeatArrangement(top: others[0])
        case 2: return RummySeatArrangement(left: others[0], right: others[1])
        default: return RummySeatArrangement(left: others[0], top: others[1], right: others[2])
        }
    }
}

/// 받침대 칸 산식 — 놓을 자리 판정이 받침대에 묻는 두 가지(타일 폭 · 왼쪽 끝 x + 손의 y → 자리). 맥 `RummyRackGeometry` · 폰 `GamesRummyRackGeometry`.
package protocol RummyRackDropGeometry {
    var dropTileWidth: CGFloat { get }
    func slot(tileLeft x: CGFloat, centerY y: CGFloat, tiles: Int) -> RummyRackSlot
}

/// 놓을 자리 판정(순수). 재료는 칸 사각형 둘(받침대 · 판 — 같은 화면 좌표)·변환·배치와 "내 차례인가" 뿐이다 — 놓아도 되는가는 편집기·서버가 정한다.
package enum RummyDropResolver {
    /// 판 묶음 누르기 여유(논리 단위) — 묶음 사이 틈(16)의 반 남짓.
    package static let meldSlack = CGSize(width: 10, height: 10)

    /// 타일 묶음(`count` 장, 손에 `grabIndex` 번째)을 `pointer`(화면 좌표)에 놓으면.
    /// `skipMeld` = 묶음 하나를 통째로 끄는 중이면 그 묶음(자기 위에 놓기 = 위치 이동으로 본다).
    package static func target(pointer: CGPoint, grabIndex: Int, count: Int, rackRect: CGRect, tableRect: CGRect,
                               canvas: RummyCanvasTransform, table: RummyTableLayout, rack: some RummyRackDropGeometry,
                               isMyTurn: Bool, skipMeld: Int? = nil) -> RummyDropTarget? {
        if rackRect.contains(pointer) {
            let local = CGPoint(x: pointer.x - rackRect.minX, y: pointer.y - rackRect.minY)
            let left = local.x - (CGFloat(grabIndex) + 0.5) * rack.dropTileWidth
            return .rackSlot(rack.slot(tileLeft: left, centerY: local.y, tiles: count))
        }
        guard isMyTurn, tableRect.contains(pointer) else { return nil }
        let logical = canvas.toLogical(CGPoint(x: pointer.x - tableRect.minX, y: pointer.y - tableRect.minY))
        for (index, frame) in table.frames.enumerated() where index != skipMeld {
            let zone = CGRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width),
                              height: CGFloat(frame.height)).insetBy(dx: -meldSlack.width, dy: -meldSlack.height)
            guard zone.contains(logical) else { continue }
            var at = 0
            for tile in 0..<table.counts[index] {
                if let f = table.tileFrame(set: index, tile: tile), CGFloat(f.x) + CGFloat(f.width) / 2 < logical.x { at += 1 }
            }
            return .meld(index, index: at)
        }
        let w = CGFloat(RummyTableLayout.tileWidth), h = CGFloat(RummyTableLayout.tileHeight)
        return .newMeldAt(clampedTopLeft(CGPoint(x: logical.x - (CGFloat(grabIndex) + 0.5) * w, y: logical.y - h / 2),
                                         tiles: count))
    }

    /// 손잡이로 묶음을 끌어 `pointer` 에 놓으면 — 판 위면 새 왼쪽 위(잡은 자리 오프셋 `grab` 을 뺀다), 밖이면 nil.
    package static func setTarget(pointer: CGPoint, grab: CGPoint, tiles: Int, tableRect: CGRect,
                                  canvas: RummyCanvasTransform) -> RummyPoint? {
        guard tableRect.contains(pointer) else { return nil }
        let logical = canvas.toLogical(CGPoint(x: pointer.x - tableRect.minX, y: pointer.y - tableRect.minY))
        return clampedTopLeft(CGPoint(x: logical.x - grab.x, y: logical.y - grab.y), tiles: tiles)
    }

    package static func clampedTopLeft(_ p: CGPoint, tiles: Int) -> RummyPoint {
        let maxX = RummyTableLayout.canvasWidth - RummyTableLayout.width(tiles: tiles)
        let maxY = RummyTableLayout.canvasHeight - RummyTableLayout.tileHeight
        return RummyPoint(x: min(max(Int(p.x.rounded()), 0), max(0, maxX)),
                          y: min(max(Int(p.y.rounded()), 0), max(0, maxY)))
    }
}
