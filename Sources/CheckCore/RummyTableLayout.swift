import Foundation

// 아잉 큐브 2판 — 판(테이블) 자유 배치 모델(설계서 v2 §1.1 · §2.1). 맥·폰 공용 순수 값.
//
// 논리 캔버스는 1000×640 단위, 타일 한 장은 40×56 단위, 묶음(세트)은 가로 한 줄(회전 없음)이다.
// 위치 = 묶음 **왼쪽 위** `[x, y]` 정수. 서버는 겹침·폭을 따지지 않고 범위만 정리한다(배치는 꾸밈) — 겹치지 않게 놓는 것은
// 클라 몫이고, 그 규칙(자동 배치 · 놓기 스냅 · 길이 변화)은 **모든 클라가 같은 결과**를 내야 한다(남의 작업 판·확정 판의
// 빈 자리를 저마다 채운다). 그래서 여기 함수는 전부 결정적이다: 부동소수 없음, 정렬 키는 내용(면) → 원래 번호.
//
// 겹침 판정은 **여백(`clearance`) 16 단위**를 둔다 — 딱 붙은 두 묶음이 한 묶음으로 읽히지 않게. 격자는 8 단위.

/// 판 위 한 점(논리 단위, 정수). 와이어에선 `[x, y]` 두 칸 배열이다.
package struct RummyPoint: Hashable, Sendable, Codable, CustomStringConvertible {
    package var x: Int
    package var y: Int

    package init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    package var description: String { "[\(x),\(y)]" }

    /// `[int, int]` 이고 서버 정리 범위(0…1000 · 0…640) 안일 때만 읽는다 — 아니면 throw(목록 쪽이 그 칸만 nil 로 접는다).
    package init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Int.self)
        let y = try container.decode(Int.self)
        guard container.isAtEnd, RummyTableLayout.acceptsWire(x: x, y: y) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "rummy point"))
        }
        self.init(x: x, y: y)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// 와이어의 배치 목록 `[[x,y]|null]` — `state.table_layout` · `state.draft.layout` · 요청 `p_layout`.
/// **디코드는 throw 하지 않는다**(와이어 규약 ①): 배열이 아니면 빈 목록, 원소가 `[int,int]`(범위 안)가 아니면 그 칸만 nil.
/// 길이가 묶음 수와 다르면 `RummyTableLayout.sanitize` 가 통째로 nil 로 본다(서버 정리 규칙과 같다).
package struct RummyLayout: Hashable, Sendable, Codable, ExpressibleByArrayLiteral {
    package var points: [RummyPoint?]

    package init(_ points: [RummyPoint?]) {
        self.points = points
    }

    package init(arrayLiteral elements: RummyPoint?...) {
        points = elements
    }

    private struct Lenient: Decodable {
        let point: RummyPoint?
        init(from decoder: any Decoder) throws {
            point = try? RummyPoint(from: decoder)
        }
    }

    package init(from decoder: any Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            points = []
            return
        }
        var read: [RummyPoint?] = []
        while !container.isAtEnd {
            if (try? container.decodeNil()) == true {
                read.append(nil)
            } else if let lenient = try? container.decode(Lenient.self) {
                read.append(lenient.point)
            } else {
                break
            }
        }
        points = read
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for point in points {
            if let point { try container.encode(point) } else { try container.encodeNil() }
        }
    }
}

/// 판 위 사각형(논리 단위). 오른쪽·아래 끝은 열린 구간이다(`maxX` 는 포함하지 않는다).
package struct RummyRect: Hashable, Sendable {
    package var x: Int
    package var y: Int
    package var width: Int
    package var height: Int

    package init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var maxX: Int { x + width }
    package var maxY: Int { y + height }
    package var origin: RummyPoint { RummyPoint(x: x, y: y) }

    package func contains(_ point: RummyPoint) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }
}

/// 판 하나의 배치(묶음마다 장수와 왼쪽 위 점). 값 자체가 결정적 자동 배치의 결과다 — 같은 입력이면 어느 기기든 같다.
package struct RummyTableLayout: Equatable, Sendable {
    // MARK: 상수(설계서 v2 §1.1)

    package static let canvasWidth = 1000
    package static let canvasHeight = 640
    package static let tileWidth = 40
    package static let tileHeight = 56
    /// 자동 배치·스냅 격자(단위).
    package static let grid = 8
    /// 두 묶음 사이 최소 여백(단위). 이보다 가까우면 "겹침"이다.
    package static let clearance = 16

    /// 묶음마다 장수(판 순서).
    package let counts: [Int]
    /// 묶음마다 왼쪽 위 점(판 순서, `counts` 와 같은 길이).
    package let points: [RummyPoint]

    package init(counts: [Int], points: [RummyPoint]) {
        precondition(counts.count == points.count, "counts/points 길이")
        self.counts = counts
        self.points = points
    }

    /// 와이어 판 + 와이어 배치 → 빈 자리를 채운 배치(`place`).
    package init(sets: [[RummyFace]], layout: RummyLayout?) {
        self.init(counts: sets.map(\.count), points: Self.place(sets: sets, layout: layout))
    }

    package static let empty = RummyTableLayout(counts: [], points: [])

    /// 묶음 `setIndex` 의 사각형. 없는 번호면 nil.
    package func frame(of setIndex: Int) -> RummyRect? {
        guard points.indices.contains(setIndex) else { return nil }
        return Self.frame(at: points[setIndex], tiles: counts[setIndex])
    }

    package var frames: [RummyRect] {
        zip(points, counts).map { Self.frame(at: $0, tiles: $1) }
    }

    /// 한 점을 덮는 묶음(뒤에 놓인 것이 위 — 마지막부터 찾는다). 화면의 누르기 판정용.
    package func setIndex(at point: RummyPoint) -> Int? {
        frames.lastIndex { $0.contains(point) }
    }

    /// 묶음 안 `tileIndex` 번째 타일의 사각형(판 좌표).
    package func tileFrame(set setIndex: Int, tile tileIndex: Int) -> RummyRect? {
        guard let frame = frame(of: setIndex), (0..<counts[setIndex]).contains(tileIndex) else { return nil }
        return RummyRect(x: frame.x + tileIndex * Self.tileWidth, y: frame.y, width: Self.tileWidth, height: Self.tileHeight)
    }

    /// `tiles` 장짜리 묶음을 `point` 가까이 놓을 때의 자리(가장 가까운 빈자리, 8 단위 격자). `excluding` 은 장애물에서 뺄 묶음
    /// (자기 자신을 옮길 때). 화면은 놓는 순간 한 번 부른다(끄는 동안 미리보기에 써도 된다 — 줄당 O(묶음 수)).
    package func snap(_ point: RummyPoint, tiles: Int, excluding: Int? = nil) -> RummyPoint {
        Self.snap(point, tiles: tiles, among: obstacles(excluding: excluding))
    }

    private func obstacles(excluding: Int?) -> [RummyRect] {
        frames.enumerated().compactMap { $0.offset == excluding ? nil : $0.element }
    }

    // MARK: - 정적 규칙

    /// 서버 정리 규칙과 같은 범위: 0 ≤ x ≤ 1000, 0 ≤ y ≤ 640.
    package static func acceptsWire(x: Int, y: Int) -> Bool {
        (0...canvasWidth).contains(x) && (0...canvasHeight).contains(y)
    }

    package static func width(tiles: Int) -> Int { max(tiles, 1) * tileWidth }

    package static func frame(at point: RummyPoint, tiles: Int) -> RummyRect {
        RummyRect(x: point.x, y: point.y, width: width(tiles: tiles), height: tileHeight)
    }

    /// 캔버스 안에 통째로 들어가는가.
    package static func fits(_ frame: RummyRect) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.maxX <= canvasWidth && frame.maxY <= canvasHeight
    }

    /// 두 묶음이 여백(`clearance`) 안으로 들어오는가 — 붙어 보이면 겹침이다.
    package static func overlaps(_ a: RummyRect, _ b: RummyRect) -> Bool {
        a.x < b.maxX + clearance && a.maxX + clearance > b.x && a.y < b.maxY + clearance && a.maxY + clearance > b.y
    }

    /// 캔버스 안이고 어느 장애물과도 안 겹친다.
    package static func isClear(_ frame: RummyRect, among others: [RummyRect]) -> Bool {
        fits(frame) && !others.contains { overlaps(frame, $0) }
    }

    /// 와이어 배치를 묶음 수에 맞춘다: 없거나 길이가 다르면 전부 nil(서버 규칙), 아니면 그대로.
    package static func sanitize(_ layout: RummyLayout?, setCount: Int) -> [RummyPoint?] {
        guard let layout, layout.points.count == setCount else { return Array(repeating: nil, count: setCount) }
        return layout.points
    }

    /// 서버 정리는 왼쪽 위 점만 범위(0…1000·0…640)로 본다 — `[999,640]` 도 통과한다(v2 실출력 `state_with_layout`).
    /// 그대로 그리면 묶음이 판 밖에 놓여 안 보이므로, 묶음이 캔버스를 넘으면 **안으로 당긴다**(오른쪽·아래 끝에 붙인다).
    /// 같은 입력이면 어느 기기든 같은 답이다.
    package static func clampInside(_ point: RummyPoint, tiles: Int) -> RummyPoint {
        let w = width(tiles: tiles)
        return RummyPoint(x: min(max(point.x, 0), max(canvasWidth - w, 0)),
                          y: min(max(point.y, 0), canvasHeight - tileHeight))
    }

    /// **결정적 자동 배치.** 주어진 점은 그대로 두고(겹쳐 있어도 — 남이 놓은 자리다), nil 자리만 채운다:
    /// 기존 묶음과 안 겹치는 첫 자리(행 우선 스캔, 8 단위 격자). 채우는 차례는 **내용 순**(긴 묶음 먼저 → 면 글자 → 원래 번호)이라
    /// 묶음 순서를 섞어 넣어도 각 묶음이 받는 자리는 같다(같은 면의 묶음 둘은 서로 바뀔 수 있지만 보이는 판은 같다).
    package static func place(sets: [[RummyFace]], layout: RummyLayout?) -> [RummyPoint] {
        let counts = sets.map(\.count)
        let given = sanitize(layout, setCount: sets.count).enumerated().map { index, point in
            point.map { clampInside($0, tiles: counts[index]) }
        }
        var obstacles: [RummyRect] = []
        for (index, point) in given.enumerated() {
            if let point { obstacles.append(frame(at: point, tiles: counts[index])) }
        }
        let missing = given.indices.filter { given[$0] == nil }
        let keys = sets.map { RummyRules.compareKey($0).map(\.text).joined(separator: " ") }
        let order = missing.sorted { a, b in
            if counts[a] != counts[b] { return counts[a] > counts[b] }
            if keys[a] != keys[b] { return keys[a] < keys[b] }
            return a < b
        }
        var result = given
        for index in order {
            let point = firstFree(tiles: counts[index], among: obstacles)
            result[index] = point
            obstacles.append(frame(at: point, tiles: counts[index]))
        }
        return result.map { $0 ?? RummyPoint(x: 0, y: 0) }
    }

    /// 행 우선 스캔(위 → 아래, 왼 → 오른, 8 단위)으로 처음 나오는 빈 자리. 판이 꽉 찼으면 여백 없이 한 번 더,
    /// 그래도 없으면 왼쪽 아래 구석(겹쳐도 — 판 밖으로는 안 나간다).
    package static func firstFree(tiles: Int, among obstacles: [RummyRect]) -> RummyPoint {
        let w = width(tiles: tiles)
        for gap in [clearance, 0] {
            for y in rowStarts {
                if let x = nearestFreeX(rowY: y, width: w, near: 0, among: obstacles, gap: gap) {
                    return RummyPoint(x: x, y: y)
                }
            }
        }
        return RummyPoint(x: 0, y: rowStarts.last ?? 0)
    }

    /// 놓기 스냅: `point` 에서 가장 가까운(유클리드) 빈 격자점. 같으면 위 → 왼쪽. 빈 곳이 없으면 `firstFree` 와 같은 대체.
    package static func snap(_ point: RummyPoint, tiles: Int, among obstacles: [RummyRect]) -> RummyPoint {
        freeSpot(point, tiles: tiles, among: obstacles) ?? firstFree(tiles: tiles, among: obstacles)
    }

    /// `snap` 의 빈자리 찾기만(0.3.70) — 여백 16 → 여백 0 순으로 `point` 에서 가장 가까운 빈 격자점, **없으면 nil**(구석으로 안 보낸다).
    /// 편집기가 판이 꽉 찼을 때 구석에 겹쳐 놓는 대신 이웃을 비켜 놓으려고 쓴다(`RummyTableEdit.settle`). `place` 는 안 쓴다.
    package static func freeSpot(_ point: RummyPoint, tiles: Int, among obstacles: [RummyRect]) -> RummyPoint? {
        let w = width(tiles: tiles)
        for gap in [clearance, 0] {
            var best: (distance: Int, point: RummyPoint)?
            for y in rowStarts {
                guard let x = nearestFreeX(rowY: y, width: w, near: point.x, among: obstacles, gap: gap) else { continue }
                let dx = x - point.x, dy = y - point.y
                let distance = dx * dx + dy * dy
                if best == nil || distance < best!.distance {
                    best = (distance, RummyPoint(x: x, y: y))
                }
            }
            if let best { return best.point }
        }
        return nil
    }

    /// 길이가 바뀐 묶음의 새 자리: 지금 자리에서 오른쪽으로 늘어난 사각형이 들어가면 그대로, 막히면(판 밖·겹침) 가장 가까운 빈자리.
    package static func refit(_ point: RummyPoint, tiles: Int, among obstacles: [RummyRect]) -> RummyPoint {
        if isClear(frame(at: point, tiles: tiles), among: obstacles) { return point }
        return snap(point, tiles: tiles, among: obstacles)
    }

    /// 격자 행의 y 들(0, 8, … , 640 − 56 이하).
    private static let rowStarts: [Int] = Array(stride(from: 0, through: canvasHeight - tileHeight, by: grid))

    /// 한 행(y)에서 폭 `w` 묶음이 놓일 수 있는 격자 x 중 `near` 에 가장 가까운 것(같으면 작은 쪽). 없으면 nil.
    /// 막힌 x 는 장애물마다 열린 구간 (ox − gap − w, ox + ow + gap) 이다 — 빈 x 의 최근접점은 `near` 의 격자 반올림이거나
    /// 막힌 구간 바로 바깥의 격자점이므로 그 후보만 대 본다(줄당 O(장애물²), 장애물 ≤ 수십).
    private static func nearestFreeX(rowY y: Int, width w: Int, near: Int, among obstacles: [RummyRect], gap: Int) -> Int? {
        let maxX = canvasWidth - w
        guard maxX >= 0 else { return nil }
        let rowTop = y, rowBottom = y + tileHeight
        var blocked: [(lo: Int, hi: Int)] = []  // 막힌 x 의 닫힌 구간 [lo, hi]
        for other in obstacles where rowTop < other.maxY + gap && rowBottom + gap > other.y {
            blocked.append((other.x - gap - w + 1, other.maxX + gap - 1))
        }
        func free(_ x: Int) -> Bool {
            x >= 0 && x <= maxX && !blocked.contains { x >= $0.lo && x <= $0.hi }
        }
        func floorGrid(_ v: Int) -> Int { Int((Double(v) / Double(grid)).rounded(.down)) * grid }
        func ceilGrid(_ v: Int) -> Int { Int((Double(v) / Double(grid)).rounded(.up)) * grid }
        let lastGrid = floorGrid(maxX)
        var candidates: [Int] = [floorGrid(near), ceilGrid(near), 0, lastGrid]
        for range in blocked {
            candidates.append(floorGrid(range.lo - 1))
            candidates.append(ceilGrid(range.hi + 1))
        }
        var best: Int?
        for raw in candidates {
            let x = min(max(raw, 0), lastGrid)
            guard free(x) else { continue }
            if let current = best {
                let d = abs(x - near), dc = abs(current - near)
                if d < dc || (d == dc && x < current) { best = x }
            } else {
                best = x
            }
        }
        return best
    }
}
