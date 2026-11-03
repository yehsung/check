import CheckCore
import CoreGraphics
import Foundation

// 폰 아잉 큐브 모션의 **순수 값**(설계서 §7). `#if os(iOS)` 밖이다 — 맥 스위트가 재는 자리. 그리기는 `GamesRummyTableCanvas`·`GamesRummyRackView` 이고, 모두 **동작 줄이기면 끈다**(뷰가 값을 부르지 않는다).
//   · 뽑기: [뽑기] 자리 → 받침대 빈자리 · 스프링 0.45초(`GamesRummyMatchLayout.drawOrigin`).
//   · 정렬: 25ms 시차 미끄러짐(`GamesRummyRackMotion.sortStagger`).
//   · 판 변화: 타일이 옛 자리에서 새 자리로 이동(`GamesRummyBoardMotion`). 판은 Canvas 한 장이라 타일별 뷰 애니메이션을 걸 수 없다 — 움직이는 타일만 Canvas 에서 숨기고 잠깐 뷰로 띄운다.
// 불투명도는 이징으로 깎지 않는다.

package enum GamesRummyRackMotion {
    /// 정렬 시차 한 칸.
    package static let staggerStep: TimeInterval = 0.025

    /// 정렬한 뒤의 읽는 순서대로 25ms 씩 늦는다(타일 id → 지연). 편집기를 사본으로 정렬해 본다.
    package static func sortStagger(_ editor: RummyTurnEditor, mode: RummyRackSort) -> [Int: TimeInterval] {
        var sorted = editor
        sorted.sortRack(mode)
        return Dictionary(uniqueKeysWithValues: sorted.rackLayout.readingOrder.enumerated().map { ($1, Double($0) * staggerStep) })
    }

    /// 지금 날아오는 중인 타일 — 받침대가 그릴 때 물어본다. `landedSerial` 까지 내려앉았고, `doneSerial` 이면 끝났다.
    package static func flight(lastDraw: RummyDrawEvent?, landedSerial: Int?, doneSerial: Int?, reduceMotion: Bool) -> (ids: Set<Int>, landed: Bool)? {
        guard !reduceMotion, let lastDraw, lastDraw.serial != doneSerial else { return nil }
        return (Set(lastDraw.tiles.map(\.tileID)), lastDraw.serial == landedSerial)
    }
}

extension GamesRummyMatchLayout {
    /// [뽑기] 칸의 가운데 — 받침대 칸 좌표로(뽑은 타일이 여기서 출발한다).
    package var drawOrigin: CGPoint { CGPoint(x: draw.midX - rack.minX, y: draw.midY - rack.minY) }
}

/// 판 변화 한 번 — 옛 자리에서 새 자리로 움직일 타일들.
package struct GamesRummyBoardMotion: Equatable, Sendable {
    /// 새 판에서의 자리(그동안 Canvas 가 이 칸을 그리지 않는다).
    package struct Slot: Hashable, Sendable {
        package let meld: Int
        package let tile: Int

        package init(meld: Int, tile: Int) {
            self.meld = meld
            self.tile = tile
        }
    }

    package struct Move: Identifiable, Equatable, Sendable {
        package let slot: Slot
        package let face: RummyFace
        package let highlighted: Bool
        /// 타일 왼쪽 위(논리 좌표).
        package let from: CGPoint
        package let to: CGPoint

        package var id: Slot { slot }
    }

    /// 이보다 많이 움직이면 뛰어넘는다(판을 통째로 다시 깐 차례 — 타일 뷰 수십 장을 띄우면 그것이 끊긴다).
    package static let maxMoves = 40

    package let moves: [Move]

    package var hidden: Set<Slot> { Set(moves.map(\.slot)) }

    private struct Placed {
        let slot: Slot
        let tile: RummyBoardTile
        let origin: CGPoint
    }

    private static func placed(_ melds: [RummyBoardMeld]) -> [Placed] {
        melds.enumerated().flatMap { index, meld in
            meld.tiles.enumerated().map { position, tile in
                Placed(slot: Slot(meld: index, tile: position), tile: tile,
                       origin: CGPoint(x: CGFloat(meld.frame.x) + CGFloat(position) * CGFloat(RummyTableLayout.tileWidth), y: CGFloat(meld.frame.y)))
            }
        }
    }

    /// 짝짓는 순서: ① 같은 id · 같은 면(편집 중) ② 면이 같고 자리가 같은 것(가만히 있었다 — 같은 면 둘이 엇갈려 날지 않게) ③ 남은 같은 면을 읽는 순서대로.
    /// 새로 생긴 타일(받침대에서 낸 것 · 남이 낸 것)은 옛 자리가 없어 그 자리에 바로 선다. `excluding` = 방금 손으로 놓은 타일(옛 자리에서 날아오면 안 된다).
    /// `landing` = 그 타일을 손이 놓은 자리(논리 좌표). 자동 붙기·끼우기로 들어갈 자리가 손 놓은 자리와 다르면 거기서 미끄러진다(맥 `land`) — 값이 없는 타일은 그 자리에 바로 선다.
    /// 움직일 것이 없거나 `maxMoves` 를 넘으면 nil.
    package static func make(from old: [RummyBoardMeld], to new: [RummyBoardMeld], excluding: Set<Int> = [],
                             landing: [Int: CGPoint] = [:]) -> GamesRummyBoardMotion? {
        guard !old.isEmpty, old != new else { return nil }
        var olds = placed(old)
        var news = placed(new)
        var moves: [Move] = []
        func move(_ from: Placed, _ to: Placed) {
            guard from.origin != to.origin else { return }
            moves.append(Move(slot: to.slot, face: to.tile.face, highlighted: to.tile.highlighted, from: from.origin, to: to.origin))
        }

        for entry in news {
            guard let id = entry.tile.id, excluding.contains(id), let from = landing[id], from != entry.origin else { continue }
            moves.append(Move(slot: entry.slot, face: entry.tile.face, highlighted: entry.tile.highlighted, from: from, to: entry.origin))
        }
        news.removeAll { $0.tile.id.map(excluding.contains) ?? false }
        olds.removeAll { $0.tile.id.map(excluding.contains) ?? false }

        var oldByID: [Int: Int] = [:]
        for (index, entry) in olds.enumerated() {
            if let id = entry.tile.id { oldByID[id] = index }
        }
        var usedOld = Set<Int>()
        var leftovers: [Placed] = []
        for entry in news {
            if let id = entry.tile.id, let index = oldByID[id], olds[index].tile.face == entry.tile.face {
                usedOld.insert(index)
                move(olds[index], entry)
            } else {
                leftovers.append(entry)
            }
        }
        var waiting: [RummyFace: [Placed]] = [:]
        for (index, entry) in olds.enumerated() where !usedOld.contains(index) {
            waiting[entry.tile.face, default: []].append(entry)
        }
        var unplaced: [Placed] = []
        for entry in leftovers {
            if let index = waiting[entry.tile.face]?.firstIndex(where: { $0.origin == entry.origin }) {
                waiting[entry.tile.face]?.remove(at: index)
            } else {
                unplaced.append(entry)
            }
        }
        for entry in unplaced {
            guard let from = waiting[entry.tile.face]?.first else { continue }
            waiting[entry.tile.face]?.removeFirst()
            move(from, entry)
        }
        guard !moves.isEmpty, moves.count <= maxMoves else { return nil }
        return GamesRummyBoardMotion(moves: moves)
    }
}
