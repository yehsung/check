import Foundation

/// Real Swift engine output for comparison with the PostgreSQL implementation.
@main
struct AlkkagiPhysicsFixtures {
    static func main() throws {
        var seed: UInt64 = 0xA1_2026_1108
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
        func row(_ stone: AlkkagiGame.Stone) -> [String: Any] {
            ["id": stone.id, "owner": stone.owner.rawValue,
             "position": ["x": stone.position.x, "y": stone.position.y],
             "velocity": ["x": stone.velocity.x, "y": stone.velocity.y],
             "isOut": stone.isOut, "isPlaced": stone.isPlaced]
        }
        var fixtures: [[String: Any]] = []
        for index in 0..<160 {
            var game = AlkkagiGame()
            _ = game.advance(dt: 60)
            if index < 156 {
                for i in game.stones.indices {
                    game.stones[i].position.x += (random() - 0.5) * 54
                    game.stones[i].position.y += (random() - 0.5) * 120
                }
            } else {
                let positions: [[AlkkagiVector]] = [
                    [.init(x: 100, y: 300), .init(x: 170, y: 340)],
                    [.init(x: 20, y: 300), .init(x: 70, y: 300)],
                    [.init(x: 550, y: 300), .init(x: 590, y: 300)],
                    [.init(x: 300, y: 300), .init(x: 300, y: 300)]
                ]
                game.stones = [
                    .init(id: 0, owner: .black, position: positions[index - 156][0]),
                    .init(id: 5, owner: .white, position: positions[index - 156][1])
                ]
            }
            let initial = game.stones.map(row)
            let angle = random() * 2 * Double.pi
            let strength = 6 + random() * 180
            let pull = index >= 156 ? AlkkagiVector(x: -135, y: 0)
                : AlkkagiVector(x: cos(angle) * strength, y: sin(angle) * strength)
            let stoneID = index < 156 ? index % 5 : 0
            precondition(game.shoot(stoneID: stoneID, pull: pull))
            var steps = 0
            while game.phase == .rolling && steps < 2_400 {
                _ = game.advance(dt: 1.0 / 240)
                steps += 1
            }
            precondition(game.phase != .rolling)
            let result: Any
            switch game.result {
            case .winner(let player): result = player.rawValue
            case .draw: result = "draw"
            case nil: result = NSNull()
            }
            fixtures.append(["name": "fixture-\(index)", "stones": initial,
                             "stone_id": stoneID, "pull": ["x": pull.x, "y": pull.y],
                             "expected": ["stones": game.stones.map(row), "steps": steps, "result": result]])
        }
        let data = try JSONSerialization.data(withJSONObject: fixtures, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
