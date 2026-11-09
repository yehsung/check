import Testing
@testable import AlkkagiCore

@Suite("Alkkagi game")
struct AlkkagiGameTests {
    @Test func blackPlacesFirstAndCannotShootOrConfirmAnIncompleteSetup() {
        var game = AlkkagiGame()
        #expect(game.phase == .placing && game.currentPlayer == .black)
        #expect(game.stones.count == 10)
        #expect(game.remaining(.black) == 5 && game.remaining(.white) == 5)
        #expect(game.placedCount(.black) == 0 && game.placedCount(.white) == 0)
        #expect(game.stones.allSatisfy { !$0.isPlaced && !$0.isOut && $0.velocity == vector(0, 0) })
        let initial = game
        #expect(game.shoot(stoneID: 0, pull: vector(0, 80)) == false)
        #expect(game.confirmPlacement() == false)
        #expect(game == initial)
        #expect(game.advance(dt: 7.5).isEmpty)
        #expect(game.placementRemaining == 22.5)
        #expect(game.turnRemaining == 30)
        #expect(game.stones == initial.stones)
    }

    @Test func placementRejectsWrongOwnersHalvesEdgesAndNonfiniteCoordinates() {
        var game = AlkkagiGame()
        for player in AlkkagiGame.Player.allCases {
            let id = player == .black ? 0 : 5
            let y = player == .black ? 460.0 : 140.0
            let wrongHalf = player == .black ? 319.99 : 280.01
            let outsideEdge = player == .black ? 580.01 : 19.99
            let before = game
            #expect(!game.canPlace(stoneID: -1, at: vector(300, y)))
            #expect(game.placeStone(stoneID: -1, at: vector(300, y)) == false)
            #expect(!game.canPlace(stoneID: player == .black ? 5 : 0, at: vector(300, y)))
            #expect(game.placeStone(stoneID: player == .black ? 5 : 0, at: vector(300, y)) == false)
            for position in [vector(300, wrongHalf), vector(19.99, y), vector(580.01, y),
                             vector(300, outsideEdge), vector(.nan, y), vector(300, .nan),
                             vector(.infinity, y), vector(300, -.infinity)] {
                #expect(!game.canPlace(stoneID: id, at: position))
                #expect(game.placeStone(stoneID: id, at: position) == false)
                #expect(game == before)
            }
            for stone in game.stones where stone.owner == player {
                #expect(game.placeStone(stoneID: stone.id, at: stone.position) == true)
            }
            #expect(game.confirmPlacement() == true)
        }
        #expect(game.phase == .aiming && game.currentPlayer == .black)
    }

    @Test func bothPlayersCanPlaceOnTheInclusiveBoardAndHalfBoundaries() {
        var game = AlkkagiGame()
        #expect(game.placeStone(stoneID: 0, at: vector(20, 320)) == true)
        #expect(game.placeStone(stoneID: 1, at: vector(580, 580)) == true)
        for stone in game.stones where stone.owner == .black && !stone.isPlaced {
            #expect(game.placeStone(stoneID: stone.id, at: stone.position) == true)
        }
        #expect(game.confirmPlacement() == true)
        #expect(game.placeStone(stoneID: 5, at: vector(20, 20)) == true)
        #expect(game.placeStone(stoneID: 6, at: vector(580, 280)) == true)
        for stone in game.stones where stone.owner == .white && !stone.isPlaced {
            #expect(game.placeStone(stoneID: stone.id, at: stone.position) == true)
        }
        #expect(game.confirmPlacement() == true)
        #expect(game.placedCount(.black) == 5 && game.placedCount(.white) == 5)
    }

    @Test func placementRequiresClearanceAndAllowsRepositioningWithoutCountingTwice() {
        var game = AlkkagiGame()
        // Another unplaced stone's suggestion does not reserve this position.
        #expect(game.placeStone(stoneID: 0, at: game.stones[1].position) == true)
        #expect(game.placeStone(stoneID: 0, at: vector(100, 400)) == true)
        let placed = game
        #expect(!game.canPlace(stoneID: 1, at: vector(141.99, 400)))
        #expect(game.placeStone(stoneID: 1, at: vector(141.99, 400)) == false)
        #expect(game == placed)
        #expect(game.canPlace(stoneID: 1, at: vector(142, 400)))
        #expect(game.placeStone(stoneID: 1, at: vector(142, 400)) == true)
        #expect(game.placeStone(stoneID: 0, at: vector(100, 400)) == true)
        #expect(game.placeStone(stoneID: 0, at: vector(100, 480)) == true)
        #expect(game.placedCount(.black) == 2)
        #expect(game.stones[0].position == vector(100, 480))
        #expect(game.stones[0].velocity == vector(0, 0) && !game.stones[0].isOut)
    }

    @Test func confirmationUsesTheCurrentPlayersActualStoneCountAndResetsTheNextClock() {
        var game = AlkkagiGame()
        game.stones = [
            stone(17, .black, 100, 460),
            AlkkagiGame.Stone(id: 29, owner: .black, position: vector(200, 460), isPlaced: false),
            AlkkagiGame.Stone(id: 40, owner: .white, position: vector(300, 140), isPlaced: false)
        ]
        #expect(game.advance(dt: 12).isEmpty)
        #expect(game.confirmPlacement() == false)
        #expect(game.placeStone(stoneID: 29, at: vector(200, 460)) == true)
        #expect(game.confirmPlacement() == true)
        #expect(game.phase == .placing && game.currentPlayer == .white)
        #expect(game.placementRemaining == 30)
        #expect(game.advance(dt: 4).isEmpty)
        #expect(game.placementRemaining == 26)
        #expect(game.confirmPlacement() == false)
        #expect(game.placeStone(stoneID: 17, at: vector(100, 460)) == false)
        #expect(game.shoot(stoneID: 17, pull: vector(0, 80)) == false)
        #expect(game.placeStone(stoneID: 40, at: vector(300, 140)) == true)
        #expect(game.confirmPlacement() == true)
        #expect(game.phase == .aiming && game.currentPlayer == .black)
        #expect(game.turnRemaining == 30 && game.shotCount == 0 && game.result == nil)
        #expect(game.shoot(stoneID: 17, pull: vector(0, 80)) == true)
    }

    @Test func placementAndConfirmationAreRejectedAfterSetup() {
        var game = readyGame()
        let aiming = game
        #expect(!game.canPlace(stoneID: 0, at: vector(300, 500)))
        #expect(game.placeStone(stoneID: 0, at: vector(300, 500)) == false)
        #expect(game.confirmPlacement() == false)
        #expect(game == aiming)
        #expect(game.shoot(stoneID: 0, pull: vector(0, 80)) == true)
        let rolling = game
        #expect(!game.canPlace(stoneID: 0, at: vector(300, 500)))
        #expect(game.placeStone(stoneID: 0, at: vector(300, 500)) == false)
        #expect(game.confirmPlacement() == false)
        #expect(game == rolling)
    }

    @Test func placementTimeoutAutofillsLegallyAndDeterministicallyWithoutMovingPlacedStones() {
        var game = AlkkagiGame()
        #expect(game.placeStone(stoneID: 0, at: vector(190, 460)) == true)
        #expect(game.placeStone(stoneID: 2, at: vector(20, 320)) == true)
        let placed = game.stones.filter(\.isPlaced)
        var repeated = game
        #expect(game.advance(dt: 30).isEmpty)
        #expect(repeated.advance(dt: 30).isEmpty)
        #expect(game == repeated)
        #expect(game.phase == .placing && game.currentPlayer == .white)
        #expect(game.placementRemaining == 30)
        #expect(game.placedCount(.black) == 5 && game.placedCount(.white) == 0)
        #expect(game.stones[1].position != vector(190, 460))
        #expect(game.advance(dt: 30).isEmpty)
        #expect(game.phase == .aiming && game.currentPlayer == .black)
        #expect(game.turnRemaining == 30 && game.shotCount == 0 && game.result == nil)
        #expect(game.stones.allSatisfy { $0.isPlaced && !$0.isOut && $0.velocity == vector(0, 0) })
        for stone in placed { #expect(game.stones.first { $0.id == stone.id } == stone) }
        for first in game.stones {
            #expect((20...580).contains(first.position.x))
            #expect((20...580).contains(first.position.y))
            #expect(first.owner == .black ? first.position.y >= 320 : first.position.y <= 280)
            for second in game.stones where second.id > first.id {
                #expect((first.position - second.position).length >= 42)
            }
        }
    }

    @Test func countdownsCarryElapsedTimeAcrossBothPlacementsAndMultipleTurnPasses() {
        var single = AlkkagiGame()
        var chunked = single
        #expect(single.advance(dt: 61.75).isEmpty)
        for dt in [12.5, 17.5, 31.75] { #expect(chunked.advance(dt: dt).isEmpty) }
        #expect(single == chunked)
        #expect(single.phase == .aiming && single.currentPlayer == .black)
        #expect(single.turnRemaining == 28.25)
        let placed = single.stones
        #expect(single.advance(dt: 28.25).isEmpty)
        #expect(single.currentPlayer == .white && single.turnRemaining == 30)
        #expect(single.advance(dt: 61.25).isEmpty)
        #expect(single.currentPlayer == .white && single.turnRemaining == 28.75)
        #expect(single.stones == placed && single.shotCount == 0 && single.result == nil)
    }

    @Test(arguments: [30, 144])
    func regularFramesExpirePlacementAndAimingAtTheirDeadlines(framesPerSecond: Int) {
        var game = AlkkagiGame()
        for _ in 0..<(30 * framesPerSecond) { #expect(game.advance(dt: 1.0 / Double(framesPerSecond)).isEmpty) }
        #expect(game.phase == .placing && game.currentPlayer == .white)
        #expect(abs(game.placementRemaining - 30) < 1e-9)
        for _ in 0..<(30 * framesPerSecond) { #expect(game.advance(dt: 1.0 / Double(framesPerSecond)).isEmpty) }
        #expect(game.phase == .aiming && game.currentPlayer == .black)
        #expect(abs(game.turnRemaining - 30) < 1e-9)
        let placed = game.stones
        for _ in 0..<(30 * framesPerSecond) { #expect(game.advance(dt: 1.0 / Double(framesPerSecond)).isEmpty) }
        #expect(game.currentPlayer == .white)
        #expect(abs(game.turnRemaining - 30) < 1e-9)
        #expect(game.stones == placed && game.shotCount == 0 && game.result == nil)
    }

    @Test func aimingTimeoutPassesWithoutShootingOrForfeitingAndAllowsTheNextPlayerToShoot() {
        var game = readyGame()
        let stones = game.stones
        #expect(game.advance(dt: 29.5).isEmpty)
        #expect(game.currentPlayer == .black && game.turnRemaining == 0.5)
        #expect(game.advance(dt: 0.5).isEmpty)
        #expect(game.phase == .aiming && game.currentPlayer == .white && game.turnRemaining == 30)
        #expect(game.stones == stones && game.shotCount == 0 && game.result == nil)
        #expect(game.shoot(stoneID: 0, pull: vector(8, 0)) == false)
        #expect(game.shoot(stoneID: 5, pull: vector(8, 0)) == true)
    }

    @Test func rollingPausesTheClockAndSettlingGivesTheNextPlayerAFullTurn() {
        var game = readyGame()
        // 약한 한 수가 1초 넘게 굴러야 시계 멈춤을 잴 수 있다 — 기본 감속(B 바둑판 마찰)은 0.24초에 서므로 원래 감속(A)으로 잰다.
        game.physics = .ice
        #expect(game.advance(dt: 29.5).isEmpty)
        #expect(game.shoot(stoneID: 0, pull: vector(8, 0)) == true)
        for _ in 0..<4 { #expect(game.advance(dt: 0.25).isEmpty) }
        #expect(game.phase == .rolling && game.currentPlayer == .black)
        #expect(game.turnRemaining == 0.5)
        #expect(settle(&game).isEmpty)
        #expect(game.phase == .aiming && game.currentPlayer == .white)
        #expect(game.turnRemaining == 30)
        #expect(game.advance(dt: 1.25).isEmpty)
        #expect(game.turnRemaining == 28.75 && game.currentPlayer == .white)
    }

    @Test func invalidClockDurationsLeaveSetupAndAimingUntouched() {
        for var game in [AlkkagiGame(), readyGame()] {
            let before = game
            for dt in [0.0, -1, .nan, .infinity, -.infinity] {
                #expect(game.advance(dt: dt).isEmpty)
                #expect(game == before)
            }
        }
    }

    @Test func aLargeFiniteElapsedTimeKeepsClocksBoundedWithoutCreatingAShot() {
        var game = AlkkagiGame()
        #expect(game.advance(dt: .greatestFiniteMagnitude).isEmpty)
        #expect(game.phase == .aiming && game.stones.allSatisfy(\.isPlaced))
        #expect(game.turnRemaining > 0 && game.turnRemaining <= 30)
        #expect(game.turnRemaining.isFinite && game.placementRemaining.isFinite)
        #expect(game.result == nil && game.shotCount == 0)
    }

    @Test func unplacedStonesCannotShootCollideMoveDelaySettlingOrPreventAWin() {
        var control = scenario([stone(0, .black, 140, 300), stone(1, .white, 220, 300)])
        var game = control
        let unplaced = [
            AlkkagiGame.Stone(id: 2, owner: .white, position: vector(180, 300),
                              velocity: vector(200_000, 0), isPlaced: false),
            AlkkagiGame.Stone(id: 3, owner: .black, position: vector(400, 500),
                              velocity: vector(-200_000, 0), isPlaced: false)
        ]
        game.stones += unplaced
        #expect(game.remaining(.black) == 1 && game.remaining(.white) == 1)
        #expect(game.shoot(stoneID: 3, pull: vector(-135, 0)) == false)
        #expect(game.shoot(stoneID: 0, pull: vector(-135, 0)) == true)
        #expect(control.shoot(stoneID: 0, pull: vector(-135, 0)) == true)
        #expect(settle(&game) == settle(&control))
        #expect(Array(game.stones.prefix(2)) == control.stones)
        #expect(Array(game.stones.suffix(2)) == unplaced)
        #expect(game.phase == .finished && game.result == .winner(.black))
        #expect(game.remaining(.white) == 0)
    }

    @Test func illegalShotsLeaveTheTurnUntouched() {
        var game = readyGame()
        let initial = game
        #expect(game.shoot(stoneID: -1, pull: vector(0, 80)) == false)
        #expect(game.shoot(stoneID: 5, pull: vector(0, 80)) == false)
        for pull in [vector(0, 0), vector(3, 4), vector(.nan, 80),
                     vector(80, .infinity), vector(-.infinity, 0)] {
            #expect(game.shoot(stoneID: 0, pull: pull) == false)
            #expect(game == initial)
        }

        game.stones[0].isOut = true
        let withRemovedStone = game
        #expect(game.shoot(stoneID: 0, pull: vector(0, 80)) == false)
        #expect(game == withRemovedStone)
        game.stones[1].position.x = -1
        let withOutsideCenter = game
        #expect(game.shoot(stoneID: 1, pull: vector(0, 80)) == false)
        #expect(game == withOutsideCenter)
    }

    @Test func pullPointsOppositeTheImpulseAndClampsWithoutChangingDirection() {
        var clamped = readyGame()
        var excessive = readyGame()
        let pull = vector(81, 108)
        #expect(clamped.shoot(stoneID: 0, pull: pull) == true)
        #expect(excessive.shoot(stoneID: 0, pull: pull * 100) == true)
        #expect(clamped == excessive)
        let velocity = clamped.stones[0].velocity
        #expect(velocity.x < 0 && velocity.y < 0)
        #expect(abs(velocity.x / velocity.y - pull.x / pull.y) < 1e-12)

        var softer = readyGame()
        #expect(softer.shoot(stoneID: 0, pull: pull * 0.5) == true)
        #expect(abs(softer.stones[0].velocity.length * 2 - velocity.length) < 1e-9)
        let rolling = clamped
        #expect(clamped.shoot(stoneID: 1, pull: vector(0, 90)) == false)
        #expect(clamped == rolling)
    }

    @Test func aHeadOnCollisionTransfersMotionAndEmitsOneContact() {
        var game = scenario([
            stone(0, .black, 140, 300), stone(1, .white, 220, 300)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(-60, 0)) == true)
        var impacts: [AlkkagiGame.Impact] = []
        for _ in 0..<3 { impacts += game.advance(dt: 1.0 / 30) }
        #expect(impacts.count == 1)
        #expect(impacts.allSatisfy { !$0.isRingOut && $0.strength > 0 && $0.strength <= 1 })
        #expect(game.stones[1].position.x > 220)
        #expect(game.stones[1].velocity.x > game.stones[0].velocity.x * 10)
        #expect(game.stones.allSatisfy { abs($0.position.y - 300) < 1e-9 })
        #expect(game.stones[0].velocity.x >= 0)
    }

    @Test func aFastGrazingShotCannotPassBetweenFixedTicks() {
        var game = scenario([
            stone(0, .black, 100, 300), stone(1, .white, 103, 339.99)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(-135, 0)) == true)
        let impacts = game.advance(dt: 1.0 / 240)
        // Both endpoints of an unchecked tick miss this shallow contact.
        #expect(impacts.count == 1)
        #expect(impacts.allSatisfy { !$0.isRingOut })
        #expect(game.stones[1].velocity.y > 0)
        #expect(game.stones[0].velocity.y < 0)
        #expect((game.stones[1].position - game.stones[0].position).length >= 40 - 1e-8)
    }

    @Test func aFastSeededStoneTransfersMotionBeforeCrossingTheBoard() {
        var game = scenario([
            stone(0, .black, 100, 300), stone(1, .white, 300, 300)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(-135, 0)) == true)
        game.stones[0].velocity = vector(200_000, 0)
        let impacts = game.advance(dt: 1.0 / 240)
        #expect(impacts.count == 2)
        #expect(impacts.first?.isRingOut == false)
        #expect(impacts.last?.isRingOut == true)
        #expect(game.stones[1].isOut)
        #expect(!game.stones[0].isOut)
        #expect(game.phase == .rolling)
        #expect(game.result == nil)
        #expect(impacts.allSatisfy { (0...1).contains($0.strength) })
    }

    @Test func aSelfRingoutLosesWithoutBouncingAndFinishedShotsAreRejected() {
        var game = scenario([
            stone(0, .black, 10, 300), stone(1, .white, 500, 500)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(70, 0)) == true)
        let impacts = game.advance(dt: 1.0 / 30)
        #expect(game.stones[0].isOut)
        #expect(game.stones[0].position.x < 0)
        #expect(game.stones[0].velocity == vector(0, 0))
        #expect(game.remaining(.black) == 0 && game.remaining(.white) == 1)
        #expect(game.phase == .finished)
        #expect(game.result == .winner(.white))
        #expect(impacts.count == 1)
        #expect(impacts.first?.isRingOut == true)
        #expect(impacts.first?.position.x == 0)
        let finished = game
        #expect(game.shoot(stoneID: 1, pull: vector(40, 0)) == false)
        #expect(game.advance(dt: 1).isEmpty)
        #expect(game == finished)
    }

    @Test func protrudingStonesStayInUntilTheirCentersCrossTheEdge() {
        var game = scenario([
            stone(0, .black, 5, 300), stone(1, .white, 0, 100)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(6, 0)) == true)
        #expect(game.advance(dt: 1.0 / 240).isEmpty)
        #expect(game.stones[0].position.x > 0 && game.stones[0].position.x < 5)
        #expect(game.stones.allSatisfy { !$0.isOut })
        let impacts = settle(&game)
        #expect(impacts.filter(\.isRingOut).count == 1)
        #expect(!game.stones[1].isOut)
        #expect(game.result == .winner(.white))
    }

    @Test func losingBothLastStonesInTheSameTickIsADraw() {
        var white = stone(1, .white, 2, 100)
        white.velocity = vector(-440, 0)
        var game = scenario([stone(0, .black, 598, 300), white])
        #expect(game.shoot(stoneID: 0, pull: vector(-40, 0)) == true)
        let impacts = game.advance(dt: 1.0 / 30)
        #expect(impacts.filter(\.isRingOut).count == 2)
        #expect(game.phase == .finished)
        #expect(game.result == .draw)
        #expect(game.remaining(.black) == 0 && game.remaining(.white) == 0)
    }

    @Test func theLastSurvivorCanStillSelfRingoutLaterInTheShot() {
        var white = stone(1, .white, 1, 100)
        white.velocity = vector(-500, 0)
        var game = scenario([stone(0, .black, 300, 300), white])
        #expect(game.shoot(stoneID: 0, pull: vector(-100, 0)) == true)
        let firstImpacts = game.advance(dt: 1.0 / 60)
        #expect(firstImpacts.filter(\.isRingOut).count == 1)
        #expect(game.remaining(.white) == 0 && game.remaining(.black) == 1)
        #expect(game.phase == .rolling)
        #expect(game.result == nil)
        #expect(game.currentPlayer == .black)
        let laterImpacts = settle(&game)
        #expect(laterImpacts.filter(\.isRingOut).count == 1)
        #expect(game.result == .draw)
    }

    @Test func restingOverlapsSeparateWithoutInventingAnImpact() {
        var game = scenario([
            stone(0, .black, 100, 500), stone(1, .white, 300, 300),
            stone(2, .white, 310, 300)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(0, -10)) == true)
        #expect(game.advance(dt: 1.0 / 240).isEmpty)
        #expect((game.stones[2].position - game.stones[1].position).length >= 40 - 1e-8)
        #expect(game.stones[1].velocity == vector(0, 0))
        #expect(game.stones[2].velocity == vector(0, 0))
    }

    @Test func coincidentMovingCentersResolveWithoutNonfiniteState() {
        var game = scenario([
            stone(0, .black, 300, 300), stone(1, .white, 300, 300)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(0, 20)) == true)
        let impacts = game.advance(dt: 1.0 / 240)
        #expect(impacts.count == 1)
        #expect((game.stones[1].position - game.stones[0].position).length >= 40 - 1e-8)
        #expect(game.stones.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite
                && $0.velocity.x.isFinite && $0.velocity.y.isFinite
        })
    }

    @Test func aSettledShotPassesTheTurnExactlyOnceAndAllowsTheNextShot() {
        var game = scenario([
            stone(0, .black, 300, 460), stone(1, .white, 300, 140)
        ])
        #expect(game.shoot(stoneID: 0, pull: vector(8, 0)) == true)
        #expect(game.phase == .rolling && game.currentPlayer == .black)
        #expect(settle(&game).isEmpty)
        #expect(game.phase == .aiming && game.currentPlayer == .white)
        #expect(game.result == nil && game.shotCount == 1)
        #expect(game.stones.allSatisfy { $0.velocity == vector(0, 0) })
        #expect(game.turnRemaining == 30)
        let settledStones = game.stones
        #expect(game.advance(dt: 1).isEmpty)
        #expect(game.turnRemaining == 29)
        #expect(game.stones == settledStones)
        let waiting = game
        #expect(game.shoot(stoneID: 0, pull: vector(8, 0)) == false)
        #expect(game == waiting)
        #expect(game.shoot(stoneID: 1, pull: vector(-8, 0)) == true)
        #expect(settle(&game).isEmpty)
        #expect(game.phase == .aiming && game.currentPlayer == .black)
        #expect(game.shotCount == 2)
    }

    @Test func invalidFrameDurationsDoNotAdvanceOrEmitEffects() {
        var game = readyGame()
        #expect(game.shoot(stoneID: 0, pull: vector(0, 80)) == true)
        let rolling = game
        for dt in [0.0, -1, .nan, .infinity, -.infinity] {
            #expect(game.advance(dt: dt).isEmpty)
            #expect(game == rolling)
        }
    }

    @Test func thirtyAnd144FramesPerSecondProduceTheSameShot() {
        var slower = scenario([
            stone(0, .black, 300, 460), stone(1, .white, 300, 140),
            stone(2, .white, 120, 100)
        ])
        #expect(slower.shoot(stoneID: 0, pull: vector(0, 135)) == true)
        var faster = slower
        var slowImpacts: [AlkkagiGame.Impact] = []
        var fastImpacts: [AlkkagiGame.Impact] = []
        for _ in 0..<(30 * 3) { slowImpacts += slower.advance(dt: 1.0 / 30) }
        for _ in 0..<(144 * 3) { fastImpacts += faster.advance(dt: 1.0 / 144) }
        #expect(slower.phase == .aiming && slower.currentPlayer == .white)
        #expect(slower.phase == faster.phase && slower.currentPlayer == faster.currentPlayer)
        #expect(slower.result == faster.result && slower.shotCount == faster.shotCount)
        #expect(slowImpacts.contains { !$0.isRingOut })
        #expect(slowImpacts.contains { $0.isRingOut })
        #expect(slowImpacts.count == fastImpacts.count)
        for (slow, fast) in zip(slower.stones, faster.stones) {
            #expect(slow.isOut == fast.isOut)
            #expect((slow.position - fast.position).length < 1e-8)
            #expect((slow.velocity - fast.velocity).length < 1e-8)
        }
        for (slow, fast) in zip(slowImpacts, fastImpacts) {
            #expect(slow.isRingOut == fast.isRingOut)
            #expect((slow.position - fast.position).length < 1e-8)
            #expect(abs(slow.strength - fast.strength) < 1e-8)
        }
    }

    @Test func resetRestoresTheBoardAndClearsAnUnfinishedSubstep() {
        var game = AlkkagiGame()
        let initial = game
        completePlacement(&game)
        #expect(game.shoot(stoneID: 0, pull: vector(0, 90)) == true)
        #expect(game.advance(dt: 1.0 / 480).isEmpty)
        game.reset()
        #expect(game == initial)
        completePlacement(&game)
        #expect(game.shoot(stoneID: 0, pull: vector(0, 90)) == true)
        let position = game.stones[0].position
        #expect(game.advance(dt: 1.0 / 480).isEmpty)
        #expect(game.stones[0].position == position)
        #expect(game.advance(dt: 1.0 / 480).isEmpty)
        #expect(game.stones[0].position.y < position.y)
    }

    private func vector(_ x: Double, _ y: Double) -> AlkkagiVector {
        AlkkagiVector(x: x, y: y)
    }

    private func stone(_ id: Int, _ owner: AlkkagiGame.Player, _ x: Double, _ y: Double) -> AlkkagiGame.Stone {
        AlkkagiGame.Stone(id: id, owner: owner, position: vector(x, y))
    }

    private func readyGame() -> AlkkagiGame {
        var game = AlkkagiGame()
        completePlacement(&game)
        return game
    }

    private func completePlacement(_ game: inout AlkkagiGame) {
        for _ in 0..<2 {
            for stone in game.stones where stone.owner == game.currentPlayer {
                #expect(game.placeStone(stoneID: stone.id, at: stone.position) == true)
            }
            #expect(game.confirmPlacement() == true)
        }
    }

    private func scenario(_ stones: [AlkkagiGame.Stone]) -> AlkkagiGame {
        var game = AlkkagiGame()
        game.stones = stones
        #expect(game.confirmPlacement() == true)
        #expect(game.confirmPlacement() == true)
        return game
    }

    private func settle(_ game: inout AlkkagiGame) -> [AlkkagiGame.Impact] {
        var impacts: [AlkkagiGame.Impact] = []
        for _ in 0..<600 where game.phase == .rolling {
            impacts += game.advance(dt: 1.0 / 60)
        }
        #expect(game.phase != .rolling, "A shot must reach rest within ten seconds")
        return impacts
    }
}
