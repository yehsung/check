import CheckCore
import CoreGraphics
import Foundation

// 아잉 마작 폰 펠트 배치(1.0.18 — 순수, 맥 스위트가 잰다). 펠트 좌표 884×502 · 강 바람개비 · 상대 손 띠 · 가운데 판 자리는
// 맥 `MahjongMatchLayout`(Sources/check/CheckMahjongWindow.swift) · `MahjongTableGeometry`(MahjongPanelTable.swift)를 **글자 그대로**
// 옮겼다 — 같은 서버 판을 두 기기가 다른 자리로 그리지 않게. 폰은 이 펠트 한 장을 가로 화면에 맞춰 통째로 줄여 그린다(`scale`).

/// 띠 한 장에 놓을 패 하나(펠트 좌표 — 원래 크기).
package struct GamesMahjongStripTile: Hashable, Sendable {
    package let face: MahjongTileFace
    package let size: MahjongTileSize
    package var state: MahjongTileState = .normal
    package var rotation: Int = 0
    package let origin: CGPoint

    package init(face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState = .normal, rotation: Int = 0, origin: CGPoint) {
        self.face = face
        self.size = size
        self.state = state
        self.rotation = rotation
        self.origin = origin
    }

    /// 회전을 반영한 사각형.
    package var rect: CGRect {
        CGRect(origin: origin, size: rotation % 2 == 0 ? size.size : CGSize(width: size.height, height: size.width))
    }
}

package enum GamesMahjongFeltLayout {
    /// 맥 펠트 크기(펠트 좌표의 바깥 틀).
    package static let felt = CGRect(x: 0, y: 0, width: 884, height: 502)

    // MARK: 펠트 안 탁자(펠트 좌표 884×502) — (v1.0.4) 강 36×48 로 펠트를 채운다(대표 답 #d_UIE0E5Aqqkxv)
    //
    // 세로 4 + 위 손 띠 32 + 4 + 위 강 144 + 4 + 가운데 판 162 + 4 + 아래 강 144 + 4 = 502(내 손은 펠트 밖 — 아래 손 띠가 없다).
    // 가운데 판은 가로 가운데(x 361…523). 좌우 손 띠는 펠트 가장자리(x 4…36 · 848…880), 위 손 띠는 그 사이(x 40…844).
    // 강은 바람개비 — 네 강의 칸(`riverLane`)이 서로도, 가운데 판·손 띠와도 겹치지 않게 나뉜다:
    //   아래 {x ≥ 판 왼쪽, y ≥ 판 아래 + 4} · 오른쪽 {x ≥ 판 오른쪽 + 4, y ≤ 판 아래} · 위 {x ≤ 판 오른쪽, y ≤ 판 위 − 4} ·
    //   왼쪽 {x ≤ 판 왼쪽 − 4, y ≥ 판 위}. 패가 제 칸 안에만 서면 아무것과도 겹치지 않는다(최악 경우는 시험이 사각형으로 되묻는다).
    //   위아래 강은 세로가 꽉 차 3줄, 좌우 강은 가로 자리가 남아 4줄까지(`MahjongTableGeometry.riverRowCounts`).
    /// 펠트 가장자리 ↔ 손 띠 · 맨 바깥 강 줄.
    package static let feltInset: CGFloat = 4
    /// 상대 손 띠 두께(부로 24×32 가 선다).
    package static let handStrip: CGFloat = 32
    package static let gap: CGFloat = 4
    package static let centerSide: CGFloat = 162
    /// 강 패 한 장 36×48(30×40 의 1.2배).
    package static var riverTile: CGSize { MahjongTileSize.discard.size }
    /// 위아래 강 3줄 깊이(144).
    package static var riverDepth: CGFloat { riverTile.height * 3 }
    /// 한 국 한 자리 강의 이론 최대 — 산 70장 · 사람마다 부로 넷까지일 때, 셋이 퐁 12번을 몰아 주면 친·남 27장 · 서·북 26장
    /// (자기 울음만이면 21 · 한 사람이 더 울어 주면 24). 패 종류는 따지지 않은 상한이고 시험이 같은 셈을 되묻는다.
    package static let riverWorstCount = 27

    /// 가운데 판(펠트 좌표) — (361, 188, 162, 162).
    package static var center: CGRect {
        CGRect(x: (felt.width - centerSide) / 2, y: feltInset + handStrip + gap + riverDepth + gap, width: centerSide, height: centerSide)
    }

    /// 강 줄 수 한도 — 위아래 3(세로가 꽉 찼다) · 좌우 4(바깥에 한 줄 더 놓을 가로 자리가 있다).
    package static func riverMaxRows(_ compass: MahjongCompass) -> Int { compass == .left || compass == .right ? 4 : 3 }

    /// 방위별 강 칸(펠트 좌표). 첫 패는 주인 기준 왼쪽 = 가운데 판 모서리에 서고, 줄은 판 쪽에서 바깥으로 쌓인다.
    /// 아래 (361, 354, 483, 144) · 위 (40, 40, 483, 144) · 왼쪽 (165, 188, 192, 310) · 오른쪽 (527, 40, 192, 310).
    package static func riverLane(_ compass: MahjongCompass) -> CGRect {
        let c = center, edge = feltInset + handStrip + gap
        let rows = riverTile.height * CGFloat(riverMaxRows(compass))
        switch compass {
        case .bottom: return CGRect(x: c.minX, y: c.maxY + gap, width: felt.width - edge - c.minX, height: rows)
        case .top: return CGRect(x: edge, y: c.minY - gap - rows, width: c.maxX - edge, height: rows)
        case .right: return CGRect(x: c.maxX + gap, y: edge, width: rows, height: c.maxY - edge)
        case .left: return CGRect(x: c.minX - gap - rows, y: c.minY, width: rows, height: felt.height - feltInset - c.minY)
        }
    }

    /// 강 한 줄에 놓을 수 있는 장수 — 칸 길이에서 리치 가로 한 장 몫(48 − 36)을 뺀 만큼(위아래 13 · 좌우 8).
    package static func riverLaneTiles(_ compass: MahjongCompass) -> Int {
        let lane = riverLane(compass)
        let along = compass == .top || compass == .bottom ? lane.width : lane.height
        return Int((along - (riverTile.height - riverTile.width)) / riverTile.width)
    }

    /// 좌우 손 띠의 위아래 끝 여백 — 펠트 둥근 모서리(반지름 18)에 띠 꼭짓점이 걸리지 않게.
    package static let sideStripEndInset: CGFloat = 10

    /// 상대 손 띠(펠트 좌표). 나(아래)는 손이 펠트 밖이라 없다. 띠 안에서 패는 가운데 맞춤(가장 긴 꼴 — 깡 넷 + 손 2장 — 472).
    /// 위 (40, 4, 804, 32) · 왼쪽 (4, 10, 32, 482) · 오른쪽 (848, 10, 32, 482).
    package static func handStripRect(_ compass: MahjongCompass) -> CGRect? {
        let edge = feltInset + handStrip + gap, sideLength = felt.height - sideStripEndInset * 2
        switch compass {
        case .bottom: return nil
        case .top: return CGRect(x: edge, y: feltInset, width: felt.width - edge * 2, height: handStrip)
        case .left: return CGRect(x: feltInset, y: sideStripEndInset, width: handStrip, height: sideLength)
        case .right: return CGRect(x: felt.width - feltInset - handStrip, y: sideStripEndInset, width: handStrip, height: sideLength)
        }
    }
}

/// 강·손 띠 배치(순수 — 시험이 되묻는다). 좌표는 펠트(884×502) 좌표.
package enum GamesMahjongFeltGeometry {
    package static let riverTile = MahjongTileSize.discard
    package static let rowLength = 6

    /// 줄마다 패 수(판 쪽 줄부터). 6 · 6 · 나머지 — 셋째 줄은 칸 끝(`riverLaneTiles` — 위아래 13 · 좌우 8)까지 옆으로 늘고,
    /// 좌우 강은 그다음을 바깥 넷째 줄에 잇는다(앞 줄의 패는 움직이지 않는다). 그래도 넘치면(위아래 강 26장부터 — 이론 최대
    /// `riverWorstCount` 27) 줄 수 한도 안에서 줄을 고르게 늘린다(⌈n ÷ 줄 수⌉, 읽는 순서는 그대로). 27장까지는 늘 칸 안이다.
    package static func riverRowCounts(_ count: Int, compass: MahjongCompass) -> [Int] {
        let lane = GamesMahjongFeltLayout.riverLaneTiles(compass), rows = GamesMahjongFeltLayout.riverMaxRows(compass)
        let caps = [rowLength, rowLength] + Array(repeating: lane, count: rows - 2)
        let widened = count > caps.reduce(0, +) ? caps.map { max($0, (count + rows - 1) / rows) } : caps
        var left = max(0, count)
        var out: [Int] = []
        for cap in widened where left > 0 {
            out.append(min(cap, left))
            left -= min(cap, left)
        }
        return out
    }

    /// 한 자리의 강 패들. `highlightLast` 면 마지막 패(울려 가지 않았으면)를 강조한다(방금 버린 사람).
    package static func river(_ discards: [MahjongDiscard], compass: MahjongCompass, highlightLast: Bool = false) -> [GamesMahjongStripTile] {
        let rect = GamesMahjongFeltLayout.riverLane(compass)
        let w = riverTile.width, h = riverTile.height
        let base = MahjongTileArtModel.rotation(for: compass)
        var rowOf: [Int] = []
        for (row, length) in riverRowCounts(discards.count, compass: compass).enumerated() {
            rowOf += Array(repeating: row, count: length)
        }
        var out: [GamesMahjongStripTile] = []
        var u: CGFloat = 0
        var row = 0
        for (index, discard) in discards.enumerated() {
            let nextRow = index < rowOf.count ? rowOf[index] : row
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
            out.append(GamesMahjongStripTile(face: MahjongTileFace(discard.tile), size: riverTile, state: state,
                                        rotation: (base + (sideways ? 1 : 0)) % 4, origin: screen.origin))
            u += lw
        }
        return out
    }

    /// 상대 손 띠: 뒷면 18×24 × `hand_count` + 부로 24×32(주인 기준 오른쪽 끝). 띠 가운데 맞춤.
    package static func handStrip(count: Int, melds: [MahjongWireMeld], compass: MahjongCompass) -> [GamesMahjongStripTile] {
        guard let rect = GamesMahjongFeltLayout.handStripRect(compass) else { return [] }
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
        var out: [GamesMahjongStripTile] = []
        for item in items {
            u += item.lead
            let lw = item.sideways ? item.size.height : item.size.width
            let lh = item.sideways ? item.size.width : item.size.height
            let across = (GamesMahjongFeltLayout.handStrip - lh) / 2
            let screen: CGRect
            switch compass {
            case .top: screen = CGRect(x: rect.maxX - u - lw, y: rect.minY + across, width: lw, height: lh)
            case .right: screen = CGRect(x: rect.minX + across, y: rect.maxY - u - lw, width: lh, height: lw)
            case .left: screen = CGRect(x: rect.minX + across, y: rect.minY + u, width: lh, height: lw)
            case .bottom: screen = .zero
            }
            out.append(GamesMahjongStripTile(face: item.face, size: item.size, rotation: (base + (item.sideways ? 1 : 0)) % 4,
                                        origin: screen.origin))
            u += lw
        }
        return out
    }
}

/// 가로 판 칸(순수 — 크기에서 계산). 펠트는 맥 884×502 를 `feltScale` 로 줄인 크기.
package struct GamesMahjongTableLayout {
    package let size: CGSize

    package init(size: CGSize) { self.size = size }
    package static let sideWidth: CGFloat = 118
    package static let gap: CGFloat = 6
    package static let topStrip: CGFloat = 30
    package static let handHeight: CGFloat = 66

    package var sideW: CGFloat { Self.sideWidth }
    package var centerX: CGFloat { sideW + Self.gap }
    package var centerW: CGFloat { size.width - (sideW + Self.gap) * 2 }
    package var handTop: CGFloat { size.height - Self.handHeight }
    package var feltScale: CGFloat {
        let availW = centerW
        let availH = handTop - Self.topStrip - Self.gap * 2
        return max(0.2, min(availW / GamesMahjongFeltLayout.felt.width, availH / GamesMahjongFeltLayout.felt.height))
    }
    package var felt: CGRect {
        let w = GamesMahjongFeltLayout.felt.width * feltScale, h = GamesMahjongFeltLayout.felt.height * feltScale
        let top = Self.topStrip + Self.gap
        let availH = handTop - Self.gap - top
        return CGRect(x: centerX + (centerW - w) / 2, y: top + max(0, (availH - h) / 2), width: w, height: h)
    }
    package var info: CGRect { CGRect(x: 0, y: 0, width: sideW, height: 34) }
    package var chrome: CGRect { CGRect(x: 0, y: 38, width: sideW, height: 26) }
    package var mySeat: CGRect { CGRect(x: 0, y: handTop - 74, width: sideW, height: 70) }
    package var leftSeat: CGRect { CGRect(x: 0, y: 70, width: sideW, height: max(60, mySeat.minY - 74)) }
    package var topSeat: CGRect { CGRect(x: centerX + centerW * 0.15, y: 0, width: centerW * 0.7, height: Self.topStrip) }
    package var rightSeat: CGRect { CGRect(x: size.width - sideW, y: 0, width: sideW, height: 96) }
    package var aids: CGRect { CGRect(x: size.width - sideW, y: 100, width: sideW, height: 26) }
    package var actions: CGRect { CGRect(x: size.width - sideW, y: 130, width: sideW, height: size.height - 130) }
    package var hand: CGRect { CGRect(x: 0, y: handTop, width: size.width - sideW - Self.gap, height: Self.handHeight) }
    /// 손패 높이(상태 줄 16 아래). 좁은 화면이면 열네 장 + 쯔모 간격이 손 칸에 들도록 줄인다.
    package var handTileHeight: CGFloat {
        let byHeight = Self.handHeight - 18
        let byWidth = (hand.width - 8) / 14 * MahjongTileSize.hand.height / MahjongTileSize.hand.width
        return max(20, min(byHeight, byWidth))
    }
}
