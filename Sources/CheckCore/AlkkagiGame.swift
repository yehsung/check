import Foundation

package struct AlkkagiVector: Codable, Equatable, Sendable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    package var length: Double { hypot(x, y) }

    package static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    package static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    package static func * (lhs: Self, rhs: Double) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

/// Local, fixed-step alkkagi rules in a 600-point board coordinate space.
package struct AlkkagiGame: Equatable, Sendable {
    package enum Player: String, Codable, CaseIterable, Sendable {
        case black, white

        package var opponent: Player { self == .black ? .white : .black }
    }

    package struct Stone: Codable, Identifiable, Equatable, Sendable {
        package let id: Int
        package let owner: Player
        package var position: AlkkagiVector
        package var velocity: AlkkagiVector
        package var isOut: Bool
        package var isPlaced: Bool

        package init(
            id: Int, owner: Player, position: AlkkagiVector,
            velocity: AlkkagiVector = AlkkagiVector(x: 0, y: 0), isOut: Bool = false,
            isPlaced: Bool = true
        ) {
            self.id = id
            self.owner = owner
            self.position = position
            self.velocity = velocity
            self.isOut = isOut
            self.isPlaced = isPlaced
        }
    }

    package enum Phase: Equatable, Sendable {
        case placing, aiming, rolling, finished
    }

    package enum Result: Equatable, Sendable {
        case winner(Player), draw
    }

    package struct Impact: Equatable, Sendable {
        package let position: AlkkagiVector
        package let strength: Double
        package let isRingOut: Bool
    }

    /// 감속 성질. 1/240초 걸음마다 속도에 `exp(-drag·dt)` 를 곱하고(공기 저항꼴), `friction·dt` 만큼 속력을 깎는다(바둑판 마찰꼴).
    /// **서버 `alkkagi_simulate` 와 같은 값이어야 한다** — 서버가 판정하고 앱은 같은 계산으로 다시 그린다. 바꾸면 서버 SQL 도 같이.
    /// friction 0 이면 원래(PR #9) 식과 비트 단위로 같다(곱 하나만 한다).
    package struct Physics: Hashable, Sendable {
        package var drag: Double
        package var friction: Double
        package init(drag: Double, friction: Double) { self.drag = drag; self.friction = friction }
        /// A 원래(기여 원본): 지수 감속만 — 빠르게 출발해 끝에서 길게 미끄러진다. 끝까지 약 2.8초 · 최대 약 740.
        package static let ice = Physics(drag: 2, friction: 0)
        /// B 바둑판 마찰: 감속 + 일정 마찰 — 사거리는 비슷하고(약 710) 끝에서 또렷이 선다. 끝까지 약 1.4초.
        package static let board = Physics(drag: 1.5, friction: 300)
        /// C 무겁게: 마찰을 키워 사거리가 짧다(약 470) — 멀리서 밀어내기 어렵다. 끝까지 약 0.9초.
        package static let heavy = Physics(drag: 2.2, friction: 500)
        /// 지금 앱 · 서버가 쓰는 값 — 대표 답 (B) 바둑판 마찰(#d_eeuXIRdSJWxL, 11-09). 서버 alkkagi_simulate 도 같은 값.
        package static let current = board
    }

    package static let boardSize: Double = 600
    package static let stoneRadius: Double = 20
    package static let maxPull: Double = 135
    package static let placementDuration: Double = 30
    package static let turnDuration: Double = 30

    package var stones: [Stone]
    package private(set) var currentPlayer: Player = .black
    package private(set) var phase: Phase = .placing
    package private(set) var placementRemaining: Double = placementDuration
    package private(set) var turnRemaining: Double = turnDuration
    package private(set) var result: Result?
    package private(set) var shotCount = 0
    /// 감속 성질(시안 영상 · 시험판이 바꿔 본다). 온라인 판은 늘 `Physics.current`(서버와 같은 값).
    package var physics: Physics = .current

    private static let fixedStep = 1.0 / 240.0
    private static let clockTolerance = 1e-9
    private static let impulseScale = 11.0
    private static let restSpeed = 6.0
    private var accumulatedTime = 0.0

    package init() {
        let columns: [Double] = [80, 190, 300, 410, 520]
        stones = Player.allCases.flatMap { player in
            columns.enumerated().map { column, x in
                Stone(id: column + (player == .black ? 0 : 5), owner: player,
                      position: AlkkagiVector(x: x, y: player == .black ? 460 : 140),
                      isPlaced: false)
            }
        }
    }

    /// Restores a server snapshot without advancing clocks, placing stones, or settling a shot.
    package static func restore(
        stones: [Stone], currentPlayer: Player, phase: Phase,
        placementRemaining: Double = placementDuration,
        turnRemaining: Double = turnDuration, result: Result? = nil, shotCount: Int = 0
    ) -> Self? {
        guard stones.count <= 10, Set(stones.map(\.id)).count == stones.count,
              shotCount >= 0, shotCount < Int.max,
              placementRemaining.isFinite, (0...placementDuration).contains(placementRemaining),
              turnRemaining.isFinite, (0...turnDuration).contains(turnRemaining),
              (phase == .finished) == (result != nil),
              stones.allSatisfy({ stone in
                  (0..<10).contains(stone.id)
                      && stone.owner == (stone.id < 5 ? .black : .white)
                      && stone.position.x.isFinite && stone.position.y.isFinite
                      && stone.velocity.x.isFinite && stone.velocity.y.isFinite
                      && stone.velocity.length.isFinite
                      && (stone.isOut || Self.isOnBoard(stone.position))
                      && (stone.isPlaced || (!stone.isOut && stone.velocity.length == 0))
              }) else { return nil }
        var game = Self()
        game.stones = stones
        game.currentPlayer = currentPlayer
        game.phase = phase
        game.placementRemaining = placementRemaining
        game.turnRemaining = turnRemaining
        game.result = result
        game.shotCount = shotCount
        return game
    }

    package func placedCount(_ player: Player) -> Int {
        stones.filter { $0.owner == player && $0.isPlaced && !$0.isOut }.count
    }

    package func canPlace(stoneID: Int, at position: AlkkagiVector) -> Bool {
        guard phase == .placing, position.x.isFinite, position.y.isFinite,
              let index = stones.firstIndex(where: { $0.id == stoneID }),
              stones[index].owner == currentPlayer, !stones[index].isOut,
              position.x >= Self.stoneRadius, position.x <= Self.boardSize - Self.stoneRadius,
              position.y >= Self.stoneRadius, position.y <= Self.boardSize - Self.stoneRadius,
              currentPlayer == .black ? position.y >= 320 : position.y <= 280
        else { return false }

        return stones.indices.allSatisfy { other in
            other == index || !stones[other].isPlaced || stones[other].isOut
                || (stones[other].position - position).length >= 2 * Self.stoneRadius + 2
        }
    }

    @discardableResult
    package mutating func placeStone(stoneID: Int, at position: AlkkagiVector) -> Bool {
        guard canPlace(stoneID: stoneID, at: position),
              let index = stones.firstIndex(where: { $0.id == stoneID }) else { return false }
        stones[index].position = position
        stones[index].velocity = AlkkagiVector(x: 0, y: 0)
        stones[index].isPlaced = true
        return true
    }

    @discardableResult
    package mutating func confirmPlacement() -> Bool {
        guard phase == .placing,
              stones.allSatisfy({ $0.owner != currentPlayer || $0.isPlaced }) else { return false }
        if currentPlayer == .black {
            currentPlayer = .white
            placementRemaining = Self.placementDuration
        } else {
            currentPlayer = .black
            placementRemaining = 0
            turnRemaining = Self.turnDuration
            phase = .aiming
        }
        return true
    }

    @discardableResult
    package mutating func shoot(stoneID: Int, pull: AlkkagiVector) -> Bool {
        let length = pull.length
        guard phase == .aiming, pull.x.isFinite, pull.y.isFinite,
              length.isFinite, length >= 6,
              let index = stones.firstIndex(where: { $0.id == stoneID }),
              stones[index].owner == currentPlayer, stones[index].isPlaced, !stones[index].isOut,
              Self.isOnBoard(stones[index].position) else { return false }

        let speed = min(length, Self.maxPull) * Self.impulseScale
        stones[index].velocity = pull * (-speed / length)
        accumulatedTime = 0
        shotCount += 1
        phase = .rolling
        return true
    }

    package mutating func advance(dt: Double) -> [Impact] {
        guard dt.isFinite, dt > 0 else { return [] }
        var timeLeft = dt
        while phase == .placing {
            guard timeLeft + Self.clockTolerance >= placementRemaining else {
                placementRemaining -= timeLeft
                return []
            }
            timeLeft = max(0, timeLeft - placementRemaining)
            placementRemaining = 0
            placeRemainingStones()
            guard confirmPlacement() else { return [] }
            if timeLeft == 0 { return [] }
        }
        if phase == .aiming {
            if timeLeft + Self.clockTolerance >= turnRemaining {
                let elapsed = max(0, timeLeft - turnRemaining)
                    .truncatingRemainder(dividingBy: 2 * Self.turnDuration)
                currentPlayer = currentPlayer.opponent
                if elapsed >= Self.turnDuration { currentPlayer = currentPlayer.opponent }
                turnRemaining = Self.turnDuration - elapsed.truncatingRemainder(dividingBy: Self.turnDuration)
            } else {
                turnRemaining -= timeLeft
            }
            return []
        }
        guard phase == .rolling else { return [] }
        // Bound catch-up after a suspended window; ordinary frames retain their remainder.
        accumulatedTime += min(dt, 0.25)
        var impacts: [Impact] = []
        while phase == .rolling, accumulatedTime + 1e-12 >= Self.fixedStep {
            accumulatedTime = max(0, accumulatedTime - Self.fixedStep)
            step(impacts: &impacts)
            if stones.allSatisfy({ !$0.isPlaced || $0.isOut || $0.velocity.length == 0 }) {
                finishShot()
            }
        }
        return impacts
    }

    package func remaining(_ player: Player) -> Int {
        stones.filter { $0.owner == player && !$0.isOut && (phase == .placing || $0.isPlaced) }.count
    }

    package mutating func reset() { self = Self() }

    private mutating func placeRemainingStones() {
        let spacing = 2 * Self.stoneRadius + 2
        let firstRow = currentPlayer == .black ? 320.0 : Self.stoneRadius
        let lastRow = currentPlayer == .black ? Self.boardSize - Self.stoneRadius : 280.0
        for index in stones.indices where stones[index].owner == currentPlayer && !stones[index].isPlaced {
            let id = stones[index].id
            if placeStone(stoneID: id, at: stones[index].position) { continue }
            // A fixed grid leaves ample fallback space for five stones without moving placed ones.
            placement: for y in stride(from: firstRow, through: lastRow, by: spacing) {
                for x in stride(from: Self.stoneRadius, through: Self.boardSize - Self.stoneRadius, by: spacing) {
                    if placeStone(stoneID: id, at: AlkkagiVector(x: x, y: y)) { break placement }
                }
            }
        }
    }

    private static func isOnBoard(_ position: AlkkagiVector) -> Bool {
        position.x >= 0 && position.x <= boardSize
            && position.y >= 0 && position.y <= boardSize
    }

    private mutating func step(impacts: inout [Impact]) {
        var timeLeft = Self.fixedStep
        moveStones(for: 0, impacts: &impacts)
        // Swept contacts prevent tunnelling, including oblique hits between fixed ticks.
        // The limit bounds work for a degenerate pile seeded through writable stone state.
        for _ in 0..<64 {
            var travel = timeLeft
            var contact: (Int, Int)?
            for first in stones.indices where stones[first].isPlaced && !stones[first].isOut {
                for second in stones.indices where second > first && stones[second].isPlaced && !stones[second].isOut {
                    guard let time = contactTime(first, second), time <= travel,
                          Self.isOnBoard(stones[first].position + stones[first].velocity * time),
                          Self.isOnBoard(stones[second].position + stones[second].velocity * time)
                    else { continue }
                    travel = time
                    contact = (first, second)
                }
            }

            moveStones(for: travel, impacts: &impacts)
            timeLeft = max(0, timeLeft - travel)
            guard let (first, second) = contact else { break }
            resolveContact(first, second, impacts: &impacts)
            // Overlap correction can itself push a center beyond the board.
            moveStones(for: 0, impacts: &impacts)
            if timeLeft <= 1e-12 { break }
        }

        let damping = exp(-physics.drag * Self.fixedStep)
        let friction = physics.friction * Self.fixedStep
        for index in stones.indices where stones[index].isPlaced && !stones[index].isOut {
            var velocity = stones[index].velocity * damping
            if friction > 0 {
                let speed = velocity.length
                velocity = speed > friction ? velocity * ((speed - friction) / speed) : AlkkagiVector(x: 0, y: 0)
            }
            stones[index].velocity = velocity.length < Self.restSpeed
                ? AlkkagiVector(x: 0, y: 0) : velocity
        }
    }

    private func contactTime(_ first: Int, _ second: Int) -> Double? {
        let delta = stones[second].position - stones[first].position
        let relative = stones[second].velocity - stones[first].velocity
        let diameter = 2 * Self.stoneRadius
        let separation = delta.x * delta.x + delta.y * delta.y - diameter * diameter
        if separation < -1e-7 { return 0 }
        let closing = delta.x * relative.x + delta.y * relative.y
        let speedSquared = relative.x * relative.x + relative.y * relative.y
        guard closing < 0, speedSquared > 0 else { return nil }
        let discriminant = closing * closing - speedSquared * separation
        guard discriminant >= 0 else { return nil }
        let time = (-closing - sqrt(discriminant)) / speedSquared
        return time >= -1e-10 ? max(0, time) : nil
    }

    private mutating func resolveContact(_ first: Int, _ second: Int, impacts: inout [Impact]) {
        let delta = stones[second].position - stones[first].position
        let distance = delta.length
        let relative = stones[second].velocity - stones[first].velocity
        let normal: AlkkagiVector
        if distance > 1e-10 {
            normal = delta * (1 / distance)
        } else if relative.length > 0 {
            normal = relative * (-1 / relative.length)
        } else {
            normal = AlkkagiVector(x: 1, y: 0)
        }
        let correction = normal * (max(0, 2 * Self.stoneRadius - distance) / 2)
        stones[first].position = stones[first].position - correction
        stones[second].position = stones[second].position + correction

        let closing = relative.x * normal.x + relative.y * normal.y
        guard closing < -1e-8 else { return }
        // Equal masses, restitution 0.92: conserve tangential motion and lose a little energy.
        let impulse = normal * (-closing * 1.92 / 2)
        stones[first].velocity = stones[first].velocity - impulse
        stones[second].velocity = stones[second].velocity + impulse
        impacts.append(Impact(position: (stones[first].position + stones[second].position) * 0.5,
                              strength: min(1, -closing / (Self.maxPull * Self.impulseScale)),
                              isRingOut: false))
    }

    private mutating func moveStones(for time: Double, impacts: inout [Impact]) {
        for index in stones.indices where stones[index].isPlaced && !stones[index].isOut {
            let start = stones[index].position
            let velocity = stones[index].velocity
            let end = start + velocity * time
            stones[index].position = end
            guard !Self.isOnBoard(end) else { continue }

            // Place the effect at the first crossed edge while retaining the departed center.
            var exitTime = time
            if end.x < 0, velocity.x < 0 { exitTime = min(exitTime, -start.x / velocity.x) }
            if end.x > Self.boardSize, velocity.x > 0 {
                exitTime = min(exitTime, (Self.boardSize - start.x) / velocity.x)
            }
            if end.y < 0, velocity.y < 0 { exitTime = min(exitTime, -start.y / velocity.y) }
            if end.y > Self.boardSize, velocity.y > 0 {
                exitTime = min(exitTime, (Self.boardSize - start.y) / velocity.y)
            }
            let edge = start + velocity * max(0, exitTime)
            impacts.append(Impact(position: AlkkagiVector(x: min(max(edge.x, 0), Self.boardSize),
                                                         y: min(max(edge.y, 0), Self.boardSize)),
                                  strength: min(1, velocity.length / (Self.maxPull * Self.impulseScale)),
                                  isRingOut: true))
            stones[index].isOut = true
            stones[index].velocity = AlkkagiVector(x: 0, y: 0)
        }
    }

    private mutating func finishShot() {
        let black = remaining(.black)
        let white = remaining(.white)
        if black == 0 || white == 0 {
            result = black == 0 && white == 0 ? .draw : .winner(black > 0 ? .black : .white)
            phase = .finished
        } else {
            currentPlayer = currentPlayer.opponent
            phase = .aiming
        }
        turnRemaining = Self.turnDuration
        accumulatedTime = 0
    }
}
