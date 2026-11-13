import Foundation

// 아잉 마작 '보이는 장수' 한 곳(SPEC §4.5 끝 · CC-08). 상태 줄 '기다리는 패 [3만×2]' · 버림 미리보기 · 역 시트 · 봇 유효패가
// 모두 이것 하나만 부른다. 울린 패는 강에 `taken` 으로 남고 부로에도 들어가 두 번 세기 쉽다 — 강은 `taken == false` 만 센다.

package nonisolated enum MahjongVisibleTiles {
    /// 종류(0~33)별로 이 자리에서 보이는 장수(34칸).
    /// 강은 `taken == false` 만 · 부로 전부(가깡으로 더한 1장 포함) · 열린 도라 표시패 · 내 손 · 내가 뽑은 패.
    package static func counts(of payload: MahjongStatePayload) -> [Int] {
        var counts = Array(repeating: 0, count: 34)
        func add(_ tile: MahjongTile) { counts[tile.kind] += 1 }
        for seat in payload.seats ?? [] {
            for discard in seat.discards ?? [] where discard.taken != true { add(discard.tile) }
            for meld in seat.melds ?? [] { meld.tiles.forEach(add) }
        }
        (payload.match?.doraIndicators ?? []).forEach(add)
        (payload.myHand ?? []).forEach(add)
        if let drawn = payload.myDrawn { add(drawn) }
        return counts
    }

    /// 아직 안 보인 장수(종류마다 4장 − 보이는 장수, 0 아래로 내려가지 않는다).
    package static func unseen(kind: Int, in payload: MahjongStatePayload) -> Int {
        guard (0..<34).contains(kind) else { return 0 }
        return max(0, 4 - counts(of: payload)[kind])
    }
}
