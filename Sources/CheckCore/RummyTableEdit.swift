import Foundation

// 아잉 큐브 3판(K3) — 판 편집 **손맛 규칙**. 맥·폰 공용 순수 값.
//
// 여기 규칙은 전부 화면 편집 규칙이다 — 판정과 무관하다(확정은 여전히 서버 R-16, 클라 짝은 `RummyRules.judgeTurn` 이
// 면만 보고 한다). 그래도 남의 작업 판·확정 판을 저마다 그리므로 **결정적**이어야 한다: 정수만, 동점은 번호·쪽 순서로 끊는다.
// 편집기(`RummyTurnEditor.moveBlock` · `moveSet`)가 부르고, 화면은 `RummyTurnEditor.previewDrop` 으로 놓기 전에 묻는다.
//
// ① 가운데 빼면 양쪽 유지(`split`): 묶음에서 타일을 빼면 남은 타일이 **이어진 토막마다** 따로 묶음이 된다. 토막의 점 =
//    원래 점 + 토막 첫 장의 원래 자리 × 타일폭 — 남은 타일은 화면에서 한 칸도 안 움직인다. 끝에서 빼면 짧아질 뿐이고
//    (왼끝을 빼면 점이 그만큼 오른쪽으로 — 역시 안 움직인다), 다 빼면 묶음이 사라진다. 그룹도 같은 규칙.
// ② 가까이 놓으면 붙기(`attachment`): 놓은 묶음의 한 끝이 다른 묶음의 반대 끝과 가로 |간격| ≤ `attachGap`(타일폭 0.6)
//    · 세로 차 ≤ `attachRise`(타일높이 0.5)이고, 이어 붙인 모양이 `RummyRules.isChainable`(같은 색 연속 · 같은 수 다른 색,
//    조커 와일드, 길이 무관)이면 그 끝에 합친다. 합친 묶음은 **원래 있던 쪽(붙는 대상)이 제자리**(`attachedPoint`).
//    여럿이면 |간격| → 세로 차 → 묶음 번호 → 오른끝 먼저. 간격이 음수(살짝 겹침)도 같은 거리로 본다.
//    묶음 위에 꽂아(③) 자란 묶음도 **자란 쪽 끝만** 같은 규칙으로 본다 — 가운데를 메우면 양쪽 토막이 다시 하나가 되고,
//    자동 배치로 곁에(여백 16) 있던 이웃과는 안 합친다. 빈 곳 놓기·묶음 옮기기도 **블록 끝마다 한 번만** 붙는다(붙은 대상의
//    반대 끝 곁 묶음까지 끌어오지 않는다). 첫 등록 전(R-12)엔 시작 판 타일이 든 묶음과는 붙지 않는다(붙으면
//    initial_table_touched 로 낼 수 없는 판이 저절로 된다). 둘 다 3판 검증에서 고쳤다(편집기 `attachAll`).
// ③ 알맞은 자리에 자동 삽입(`insertionIndex`): 묶음 위에 놓으면 결과가 유효(R-04~R-06) > 이어질 수 있는 모양이 되는
//    자리(이 순서 그대로 이어지는 자리 — 유효성만은 순서를 안 본다)에 넣는다. 그룹 모양(숫자 타일이 한 숫자)이면 **R-09 표시 순서
//    자리**(색 A→D, 조커 뒤 — 0.3.70: 옛 '오른끝'은 확정 뒤 서버 표시 순서로 바뀌며 타일이 튀었다).
//    런은 그런 자리 중 놓은 자리에 가장 가까운 곳(같으면 오른쪽). 맞는 자리가 없으면 놓은 자리 그대로(무효 표시는 판정 몫).
//    그리고 블록을 받은 묶음이 **맞는 세트가 되면 R-09 표시 순서로 늘어놓는다**(편집기 몫 — 런의 조커도 확정 뒤 자리로): 확정 전후·
//    남이 보는 작업 판이 같은 순서다. 기존 타일이 가장 많이 제자리인 쪽으로 민다(숫자 우선 — 조커는 뜻 따라 건너간다).
//    빼고 남은 토막도 맞는 세트면 표시 순서로(이웃은 안 건드린다 — 막히면 사각형 제자리에서 순서만, 0.3.70 검증).
// ④ 늘어난 묶음 앉히기(`settle`, 0.3.70 — 편집기 전용, 자동 배치 `place` 와 무관): 그 자리가 막히면 늘어난 장수만큼 안에서 옆으로
//    (왼쪽 먼저) 밀고, 그래도 막히면 만지던 묶음은 제자리에 두고 막은 이웃을 가장 가까운 빈자리로 비켜 놓는다. 결과 점은 작업
//    배치(`layout`)로 나가므로 모든 기기가 같은 판을 본다(남은 다시 계산하지 않는다).
// ⑤ 길게 눌러 집기(`pickRange`, 0.3.70): 판 묶음 타일을 길게 누르면 누른 타일에서 **가까운 끝까지**(⌥ 없이 쪼개기).

/// 붙는 쪽. 대상 묶음 기준이다.
package enum RummyAttachSide: String, Hashable, Sendable {
    /// 대상 왼끝 앞에(블록 + 대상).
    case left
    /// 대상 오른끝 뒤에(대상 + 블록).
    case right
}

/// ② 붙을 곳 — 대상 묶음 번호(넘겨준 `sets` 기준)와 쪽.
package struct RummyAttachment: Hashable, Sendable {
    package let set: Int
    package let side: RummyAttachSide

    package init(set: Int, side: RummyAttachSide) {
        self.set = set
        self.side = side
    }
}

/// ① 남은 토막 하나 — 원래 묶음 안 자리 구간과 그 토막의 왼쪽 위 점.
package struct RummySplitPiece: Hashable, Sendable {
    package let range: Range<Int>
    package let point: RummyPoint

    package init(range: Range<Int>, point: RummyPoint) {
        self.range = range
        self.point = point
    }
}

/// ③ 꽂을 자리 — `fits` 가 거짓이면 맞는 자리가 없어 놓은 자리 그대로다.
package struct RummyInsertion: Hashable, Sendable {
    package let index: Int
    package let fits: Bool

    package init(index: Int, fits: Bool) {
        self.index = index
        self.fits = fits
    }
}

/// 놓기 계획(놓기 전에 화면이 미리 그릴 것). 묶음 번호는 **옮기기 전 화면** 번호다(쪼개진 토막이면 그 원래 묶음).
package enum RummyDropPlan: Hashable, Sendable {
    /// 받침대로.
    case rack
    /// 묶음 `set` 의 `side` 끝에 붙는다(규칙 ②).
    case attach(set: Int, side: RummyAttachSide)
    /// 묶음 `set` 위에 놓아 `index` 자리에 꽂힌다(규칙 ③). `index` = 끌린 타일을 뺀 그 묶음에서 블록 첫 장의 자리.
    case insert(set: Int, index: Int)
    /// 새 묶음 — 놓일 왼쪽 위 점(스냅 뒤). 묶음 통째 옮기기(`moveSet`)가 안 붙으면 이것.
    case newSet(RummyPoint)
}

/// `previewDrop` · `previewMoveSet` 의 답: 계획 + 놓은 뒤 블록이 든 묶음(받침대행이면 nil).
package struct RummyDropPreview: Hashable, Sendable {
    package struct Landing: Hashable, Sendable {
        /// 놓은 **뒤** 판에서의 묶음 번호.
        package let set: Int
        /// 놓은 뒤 그 묶음의 면(화면 순).
        package let faces: [RummyFace]
        /// 놓은 뒤 그 묶음의 판 사각형(미리보기 윤곽).
        package let frame: RummyRect
        /// 그 묶음 안 블록 첫 장의 자리.
        package let blockStart: Int
        /// 그 묶음이 그대로 유효한 세트인가(R-04~R-06).
        package let valid: Bool
    }

    package let plan: RummyDropPlan
    package let landing: Landing?
}

package enum RummyTableEdit {
    /// ② 붙기 가로 거리(단위) = 타일폭 0.6.
    package static let attachGap = RummyTableLayout.tileWidth * 3 / 5
    /// ② 붙기 세로 중심 차(단위) = 타일높이 0.5.
    package static let attachRise = RummyTableLayout.tileHeight / 2

    /// ① `count` 장 묶음(점 `point`)에서 `removed` 자리를 빼고 남는 이어진 토막들(왼쪽부터). 남는 게 없으면 빈 배열.
    package static func split(count: Int, point: RummyPoint, removing removed: Set<Int>) -> [RummySplitPiece] {
        var pieces: [RummySplitPiece] = []
        var start: Int?
        for index in 0...count {
            let kept = index < count && !removed.contains(index)
            if kept, start == nil { start = index }
            if !kept, let from = start {
                pieces.append(RummySplitPiece(
                    range: from..<index,
                    point: RummyPoint(x: point.x + from * RummyTableLayout.tileWidth, y: point.y)))
                start = nil
            }
        }
        return pieces
    }

    /// ② 사각형 `frame` 에 놓인 블록(면 `block`)이 묶음들(`sets` · `frames`, 같은 길이) 중 어느 끝에 붙는가. 없으면 nil.
    /// `sides` = 볼 쪽(대상 기준). 묶음 위에 꽂아 한쪽으로 자란 묶음은 자란 쪽만 본다(편집기 몫 — 원래 곁에 있던 이웃과는
    /// 안 합친다).
    package static func attachment(
        block: [RummyFace], frame: RummyRect, sets: [[RummyFace]], frames: [RummyRect],
        sides: [RummyAttachSide] = [.right, .left]
    ) -> RummyAttachment? {
        guard !block.isEmpty else { return nil }
        var best: (key: (Int, Int, Int, Int), hit: RummyAttachment)?
        for index in sets.indices where index < frames.count && !sets[index].isEmpty {
            let other = frames[index]
            let rise = abs(frame.y - other.y)
            guard rise <= attachRise else { continue }
            for side in [RummyAttachSide.right, .left] where sides.contains(side) {
                let gap = side == .right ? frame.x - other.maxX : other.x - frame.maxX
                guard abs(gap) <= attachGap else { continue }
                let joined = side == .right ? sets[index] + block : block + sets[index]
                guard RummyRules.isChainable(joined) else { continue }
                let key = (abs(gap), rise, index, side == .right ? 0 : 1)
                if let current = best, !(key < current.key) { continue }
                best = (key, RummyAttachment(set: index, side: side))
            }
        }
        return best?.hit
    }

    /// ② 합친 묶음의 점 — 대상(점 `target`)이 제자리다. 왼쪽에 붙으면 블록 장수만큼 왼쪽으로 늘어난다.
    package static func attachedPoint(target: RummyPoint, side: RummyAttachSide, blockCount: Int) -> RummyPoint {
        switch side {
        case .right: return target
        case .left: return RummyPoint(x: target.x - blockCount * RummyTableLayout.tileWidth, y: target.y)
        }
    }

    /// ③ 블록(`block`, 넘긴 순서 그대로 한 덩어리)을 묶음 `meld` 의 어디에 꽂을까. `preferred` = 놓은 자리(0…장수로 자른다).
    package static func insertionIndex(_ block: [RummyFace], into meld: [RummyFace], preferred: Int) -> RummyInsertion {
        let preferred = min(max(preferred, 0), meld.count)
        var bestTier: Int?
        var fits: [Int] = []
        for index in 0...meld.count {
            let result = Array(meld[..<index]) + block + Array(meld[index...])
            // `analyze` 는 순서를 안 본다(판정은 다중집합) — 자리는 순서를 보는 `isChainable` 이 가른다.
            guard RummyRules.isChainable(result) else { continue }
            let tier = RummyRules.analyze(result).valid ? 0 : 1
            if bestTier == nil || tier < bestTier! {
                bestTier = tier
                fits = [index]
            } else if tier == bestTier {
                fits.append(index)
            }
        }
        guard !fits.isEmpty else { return RummyInsertion(index: preferred, fits: false) }
        let numbers = Set((meld + block).compactMap(\.number))
        // 그룹 모양: R-09 표시 순서 자리(블록 첫 장보다 뒤에 올 첫 타일 앞 — 색 A→D, 조커 맨 뒤). 놓은 자리는 안 본다.
        let wanted = numbers.count == 1 ? (meld.firstIndex { block[0] < $0 } ?? meld.count) : preferred
        let best = fits.min { a, b in
            let da = abs(a - wanted), db = abs(b - wanted)
            return da != db ? da < db : a > b
        }!
        return RummyInsertion(index: best, fits: true)
    }

    /// ⑤ `count` 장 묶음에서 `index` 번째 타일을 길게 눌러 집을 구간 — 누른 타일에서 **가까운 끝까지**.
    ///   · 오른쪽 절반(타일 가운데가 묶음 가운데보다 오른쪽) → 그 타일부터 끝까지.
    ///   · 왼쪽 절반 → 처음부터 그 타일까지.
    ///   · 정확히 가운데(홀수 장의 가운데 타일) → 묶음 전체(두 끝이 같은 거리 — 어느 쪽도 고를 까닭이 없다).
    /// 끝 타일을 누르면 그 한 장이다(한 장 끌기와 같다). 묶음 통째는 손잡이가 맡는다. 반 칸 단위 정수 비교라 경계가 흔들리지 않는다.
    package static func pickRange(count: Int, pressed index: Int) -> Range<Int> {
        guard count > 0, (0..<count).contains(index) else { return 0..<0 }
        let center = 2 * index + 1  // 누른 타일 가운데 × 2 (묶음 가운데 × 2 = count)
        if center > count { return index..<count }
        if center < count { return 0..<(index + 1) }
        return 0..<count
    }

    /// ④ 늘어난 묶음 `index` 를 판에 앉힌 뒤 모든 묶음의 점. `frames[index]` = 바라는 자리(남은 타일 제자리), `grown` = 이번에
    /// 늘어난 장수(옆으로 밀 수 있는 거리 = 그 장수 × 타일폭 — 민 뒤에도 원래 타일 자리를 덮어 묶음이 멀리 튀지 않는다).
    ///   1. 판 안이고 안 겹치면 그대로.
    ///   2. 1 단위씩 넓혀 가며 옆으로 — 같은 거리면 **왼쪽 먼저**(오른쪽이 막혀 왼쪽으로 늘어나는 것).
    ///   3. 그래도 막히면 만지던 묶음은 제자리(판 밖으로 나가면 안으로만 당긴다)에 두고, 그와 겹치는 이웃을 번호 순으로 저마다
    ///      가장 가까운 빈자리(`RummyTableLayout.freeSpot` — 최소 거리)로 비켜 놓는다. 빈자리가 없는 이웃은 그대로(판이 꽉 찼다).
    /// 정수만 · 순서 고정이라 결정적이다. 편집기 전용(`place` 계약과 무관) — 결과는 작업 배치로 나간다.
    package static func settle(_ frames: [RummyRect], index: Int, grown: Int) -> [RummyPoint] {
        var points = frames.map(\.origin)
        guard frames.indices.contains(index) else { return points }
        func frame(_ j: Int) -> RummyRect {
            RummyRect(x: points[j].x, y: points[j].y, width: frames[j].width, height: frames[j].height)
        }
        func others(_ skip: Int) -> [RummyRect] { frames.indices.filter { $0 != skip }.map(frame) }
        let mine = frames[index]
        let obstacles = others(index)
        if RummyTableLayout.isClear(mine, among: obstacles) { return points }
        let reach = max(grown, 0) * RummyTableLayout.tileWidth
        if reach > 0 {
            for step in 1...reach {
                for x in [mine.x - step, mine.x + step] {
                    let moved = RummyRect(x: x, y: mine.y, width: mine.width, height: mine.height)
                    if RummyTableLayout.isClear(moved, among: obstacles) {
                        points[index] = moved.origin
                        return points
                    }
                }
            }
        }
        let tiles = mine.width / RummyTableLayout.tileWidth
        points[index] = RummyTableLayout.clampInside(mine.origin, tiles: tiles)
        let placed = frame(index)
        for j in frames.indices where j != index && RummyTableLayout.overlaps(frame(j), placed) {
            if let spot = RummyTableLayout.freeSpot(points[j], tiles: frames[j].width / RummyTableLayout.tileWidth,
                                                    among: others(j)) {
                points[j] = spot
            }
        }
        return points
    }
}
