import CoreGraphics
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 판 채우기(v1.0.4 — 대표 답 #d_UIE0E5Aqqkxv "버린 패를 더 크게 (빈 판 채우기)") — **순수 값** 시험(그림 없음).
// 강 36×48 이 펠트 884×502 를 채우되, 강·부로가 가장 많은 국 끝에도 펠트 밖으로 나가거나 서로 겹치지 않는지 사각형으로 잰다.
// 최악 경우 = 네 자리 모두 강 `riverWorstCount`(27 — 첫 시험이 규칙에서 셈한다) · 리치 선언패 가로 · 울려 간 패 ·
// 네 사람 부로 넷(가장 긴 꼴 = 가로 패 있는 깡 넷 · 가깡·안깡 섞인 꼴) · 손 2장. 그림으로 보는 같은 장면은
// `V03xxMahjongPanelRenderTests.worstCaseRiversAndMeldsAllStandInsideTheFelt`.

@Suite("아잉 마작 판 채우기 — 강 36×48 · 최악 경우 겹침 0 · 펠트 안")
struct V03xxMahjongBoardFillTests {
    typealias L = MahjongMatchLayout
    typealias G = MahjongTableGeometry

    @Test("한 국 한 자리 강의 이론 최대 — 친·남 27 · 서·북 26 = riverWorstCount(산 70장 · 부로 넷 셈)")
    func riverWorstCountIsTheRuleBound() {
        // 없으면: 강 최대를 어림(예: 쯔모 18 + 자기 울음 4)으로 잡아, 남의 퐁이 차례를 건너뛰어 주는 국에서 강이 칸을 넘어도 초록이다.
        let bounds = mjfMaxDiscards()
        #expect(bounds == [27, 27, 26, 26], "자리별 강 최대 \(bounds)")
        #expect(bounds.max() == L.riverWorstCount)
        // 기준선: 아무도 울지 않으면 70장을 넷이 나눠 18·18·17·17 — 셈이 울음을 보지 않으면 이 값에 머문다.
        #expect(mjfMaxDiscards(maxMelds: 0) == [18, 18, 17, 17])
    }

    @Test("강 칸 넷 · 가운데 판 · 손 띠 셋이 서로 겹치지 않고 펠트 안(둥근 모서리 포함) · 펠트는 손·동작·자리 카드와 떨어져 있다")
    func lanesCenterAndStripsAreDisjointInsideTheFelt() throws {
        // 없으면: 칸 하나를 옮기다 바람개비가 엇갈려(예: 오른쪽 강 칸이 위 손 띠 줄까지 올라가) 패가 늘면 겹쳐도 초록이다.
        var parts: [(String, CGRect)] = [("가운데 판", L.center)]
        for compass in MahjongCompass.allCases {
            parts.append(("\(compass) 강 칸", L.riverLane(compass)))
            if let strip = L.handStripRect(compass) { parts.append(("\(compass) 손 띠", strip)) }
        }
        #expect(parts.count == 8)
        for (i, a) in parts.enumerated() {
            #expect(mjfInsideFelt(a.1), "\(a.0) \(a.1) 가 펠트 밖")
            for b in parts[(i + 1)...] { #expect(!mjfOverlaps(a.1, b.1), "\(a.0) 와 \(b.0) 가 겹친다") }
        }
        let felt = L.felt
        for other in [L.hand, L.actions, L.mySeat, L.leftSeat, L.rightSeat, L.topSeat, L.info, L.chromeLeft, L.chromeRight, L.aids] {
            #expect(!mjfOverlaps(felt, other), "펠트가 \(other) 와 겹친다")
        }
        // 가운데 판 안: 도라 다섯 칸(24×32, 칸 26)이 좌우 변의 리치봉(두께 6, 변에서 edgeInset) 띠 안쪽에 든다.
        let dora = MahjongCenterBoard.doraPitch * 4 + MahjongCenterBoard.doraSize.width
        #expect(dora == 128 && dora <= L.centerSide - 2 * (MahjongCenterBoard.edgeInset + 3), "도라 줄 \(dora) 가 리치봉 띠에 닿는다")
        // 가장 긴 손 띠(깡 넷 + 손 2장 = 472)가 띠 안에 든다.
        let longest = G.handStrip(count: 2, melds: mjfMelds(["minkan", "kakan", "minkan", "kakan"], seat: 1), compass: .left)
        let strip = try #require(L.handStripRect(.left))
        let span = mjfRects(longest).reduce(CGRect.null) { $0.union($1) }
        #expect(span.height == 472 && strip.contains(span), "가장 긴 손 띠 \(span) 가 띠 \(strip) 밖")
    }

    @Test("어느 방위든 0~27장 · 리치 가로 어디든 — 강 패가 제 칸 안 · 서로 안 겹침 · 줄은 6·6·나머지")
    func everyRiverCountStaysInItsLane() {
        // 없으면: 셋째 줄이 '넘치면 옆으로'만 늘어 좌우 강 21장째부터 펠트 아래로 빠지거나(세로 310 에 9장 324), 줄을 고르게 늘릴 때
        // 패가 겹쳐도 초록이다.
        #expect(G.riverRowCounts(18, compass: .bottom) == [6, 6, 6] && G.riverRowCounts(5, compass: .left) == [5])
        #expect(G.riverRowCounts(25, compass: .top) == [6, 6, 13] && G.riverRowCounts(20, compass: .right) == [6, 6, 8])
        #expect(G.riverRowCounts(21, compass: .left) == [6, 6, 8, 1] && G.riverRowCounts(27, compass: .right) == [6, 6, 8, 7])
        #expect(G.riverRowCounts(26, compass: .bottom) == [9, 9, 8] && G.riverRowCounts(27, compass: .top) == [9, 9, 9])
        var layouts = 0, bad = 0
        for compass in MahjongCompass.allCases {
            let lane = L.riverLane(compass)
            for count in 0...L.riverWorstCount {
                for riichi in Set([nil, 0, 5, 12, 20, count - 1]) where riichi.map({ $0 >= 0 && $0 < count }) ?? true {
                    let rects = mjfRects(G.river(mjfDiscards(count, riichi: riichi), compass: compass))
                    layouts += 1
                    if rects.count != count { bad += 1; Issue.record("\(compass) \(count)장: 패 \(rects.count)") }
                    for (i, a) in rects.enumerated() {
                        if !lane.contains(a) {
                            bad += 1
                            if bad <= 5 { Issue.record("\(compass) \(count)장(리치 \(String(describing: riichi))) \(i)째 \(a) 가 칸 \(lane) 밖") }
                        }
                        for b in rects[(i + 1)...] where mjfOverlaps(a, b) {
                            bad += 1
                            if bad <= 5 { Issue.record("\(compass) \(count)장(리치 \(String(describing: riichi))) \(a) 와 \(b) 가 겹친다") }
                        }
                    }
                }
            }
        }
        #expect(layouts > 400 && bad == 0, "배치 \(layouts) 가지 가운데 어긋남 \(bad)")
    }

    @Test("최악 경우 — 네 자리 강 27 · 리치 가로 · 부로 넷(깡) · 손 2장: 펠트 안 모든 패가 서로·가운데 판과 안 겹치고 펠트 안")
    func worstCaseTableHasNoOverlap() {
        // 없으면: 강 하나하나는 제 칸에 들어도, 칸 셈이나 손 띠 자리가 어긋나 '가장 많을 때'만 강이 옆 손 띠·가운데 판을 덮거나
        // 펠트 둥근 모서리 밖으로 삐져도 초록이다.
        for riichi in [0, 12, 20, L.riverWorstCount - 1] {
            for meldSet in [["minkan", "kakan", "minkan", "kakan"], ["kakan", "ankan", "minkan", "pon"]] {
                var parts: [(String, CGRect)] = [("가운데 판", L.center)]
                for compass in MahjongCompass.allCases {
                    let river = G.river(mjfDiscards(L.riverWorstCount, riichi: riichi, taken: [3, 10, 17]), compass: compass,
                                        highlightLast: compass == .left)
                    parts += mjfRects(river).enumerated().map { ("\(compass) 강 \($0.offset)", $0.element) }
                    let strip = G.handStrip(count: 2, melds: mjfMelds(meldSet, seat: compass.rawValue), compass: compass)
                    parts += mjfRects(strip).enumerated().map { ("\(compass) 손 띠 \($0.offset)", $0.element) }
                }
                #expect(parts.count == 1 + 4 * L.riverWorstCount + 3 * (2 + meldSet.reduce(0) { $0 + ($1 == "pon" ? 3 : 4) }))
                var problems = 0
                func report(_ text: String) {
                    problems += 1
                    if problems <= 5 { Issue.record("리치 \(riichi) \(meldSet): \(text)") }
                }
                for (i, a) in parts.enumerated() {
                    if !mjfInsideFelt(a.1) { report("\(a.0) \(a.1) 가 펠트 밖") }
                    let body = a.1.offsetBy(dx: L.felt.minX, dy: L.felt.minY)
                    for other in [L.hand, L.actions, L.mySeat, L.leftSeat, L.rightSeat, L.topSeat] where mjfOverlaps(body, other) {
                        report("\(a.0) 가 \(other) 에 닿는다")
                    }
                    for b in parts[(i + 1)...] where mjfOverlaps(a.1, b.1) { report("\(a.0) \(a.1) 와 \(b.0) \(b.1) 가 겹친다") }
                }
                #expect(problems == 0, "리치 \(riichi) \(meldSet): 펠트 밖·겹침 \(problems)")
            }
        }
    }
}

// MARK: - 도우미

/// 한 국 자리별(0 = 친) 버림 수의 상한(패 종류는 따지지 않는다). 살아 있는 산 70장(친의 첫 쯔모 포함). X 가 버리면 다음은
/// X+1 의 쯔모(산이 남았으면) 또는 아무 Y≠X 의 퐁·치(산이 남았고 Y 부로 < `maxMelds` — 치는 X+1 의 퐁과 같은 꼴). 마지막 패 뒤의
/// 버림은 울 수 없다. 깡은 산 한 장을 더 쓰므로 퐁보다 버림을 늘리지 못해 뺐다.
/// 표 `v[산 남은 수][부로 수 넷(진법 maxMelds+1)][방금 버린 X]` = 그다음 **자리 0** 이 더 버릴 수 있는 최대 — 산이 적은 쪽부터,
/// 같은 산에서는 부로가 많은 쪽부터 채운다(퐁은 산을 안 쓰고 부로만 는다). 규칙이 자리를 돌려도 같으므로 자리 t 의 최대는
/// 표 하나에서 '친 = 자리 −t' 로 읽는다(부로가 모두 0 인 첫 상태는 돌려도 같다).
private func mjfMaxDiscards(maxMelds: Int = 4, wall: Int = 70) -> [Int] {
    let base = maxMelds + 1, codes = base * base * base * base
    let places = [1, base, base * base, base * base * base]
    let callable = (0..<(codes * 4)).map { ($0 / 4 / places[$0 % 4]) % base < maxMelds }
    var table = [Int8](repeating: 0, count: wall * codes * 4)
    callable.withUnsafeBufferPointer { can in
        table.withUnsafeMutableBufferPointer { v in
            for left in 1..<wall {
                let here = left * codes * 4, before = (left - 1) * codes * 4
                var code = codes - 1
                while code >= 0 {
                    for x in 0..<4 {
                        let next = x == 3 ? 0 : x + 1
                        var best = Int(v[before + code * 4 + next]) + (next == 0 ? 1 : 0)
                        for y in 0..<4 where y != x && can[code * 4 + y] {
                            best = max(best, Int(v[here + (code + places[y]) * 4 + y]) + (y == 0 ? 1 : 0))
                        }
                        v[here + code * 4 + x] = Int8(best)
                    }
                    code -= 1
                }
            }
        }
    }
    // 친이 첫 쯔모(산 70 → 69) 뒤 버린다 — 자리 t 에게 친은 자리 −t.
    return (0..<4).map { t in (t == 0 ? 1 : 0) + Int(table[((wall - 1) * codes) * 4 + (4 - t) % 4]) }
}

/// 강 `count` 장(리치 선언패는 `riichi` 째 하나, `taken` 째들은 울려 간 패).
private func mjfDiscards(_ count: Int, riichi: Int?, taken: Set<Int> = []) -> [MahjongDiscard] {
    (0..<count).map { i in
        MahjongDiscard(tile: MahjongTile(id: (i * 5) % 136)!, tsumogiri: i % 4 == 3, riichi: i == riichi, taken: taken.contains(i))
    }
}

/// 부로 넷(종류 글자 순서대로). 가깡·대명깡·퐁은 가운데 패를 남에게서 받았고, 안깡은 받은 패가 없다.
private func mjfMelds(_ types: [String], seat: Int) -> [MahjongWireMeld] {
    types.enumerated().map { index, type in
        let kind = (seat * 8 + index * 2 + 1) % 34
        let tiles = (0..<(type == "pon" || type == "chi" ? 3 : 4)).map { MahjongTile(id: kind * 4 + $0)! }
        return MahjongWireMeld(type: type, tiles: tiles, called: type == "ankan" ? nil : tiles[1], fromSeat: type == "ankan" ? nil : (seat + 2) % 4)
    }
}

/// 띠 패 → 펠트 좌표 사각형(회전 반영).
private func mjfRects(_ tiles: [MahjongStripTile]) -> [CGRect] {
    tiles.map { tile in
        let size = tile.rotation % 2 == 0 ? tile.size.size : CGSize(width: tile.size.height, height: tile.size.width)
        return CGRect(origin: tile.origin, size: size)
    }
}

/// 넓이가 있는 겹침만(변이 닿는 것은 겹침이 아니다).
private func mjfOverlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
}

/// 펠트(펠트 좌표 884×502, 둥근 모서리 18 · 테두리 3 의 안쪽 1.5)의 안쪽에 사각형의 네 꼭짓점이 모두 든다.
private func mjfInsideFelt(_ rect: CGRect) -> Bool {
    let inner = CGRect(origin: .zero, size: MahjongMatchLayout.felt.size).insetBy(dx: 1.5, dy: 1.5)
    let radius: CGFloat = 18 - 1.5
    guard rect.minX >= inner.minX, rect.maxX <= inner.maxX, rect.minY >= inner.minY, rect.maxY <= inner.maxY else { return false }
    for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                  CGPoint(x: rect.maxX, y: rect.maxY)] {
        let cx = min(max(point.x, inner.minX + radius), inner.maxX - radius)
        let cy = min(max(point.y, inner.minY + radius), inner.maxY - radius)
        if hypot(point.x - cx, point.y - cy) > radius { return false }
    }
    return true
}
