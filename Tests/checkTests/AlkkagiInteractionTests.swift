import Testing
#if ALKKAGI_PLAYGROUND
@testable import AlkkagiPlayground
@testable import AlkkagiCore
#else
@testable import check
@testable import CheckCore
#endif

@Suite(.serialized)
@MainActor
struct AlkkagiInteractionTests {
    private func model() -> AlkkagiLocalModel {
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.tick(now: 100)
        return model
    }

    @Test("배치 제한시간을 넘긴 드래그로 다음 사람의 돌을 놓을 수 없다")
    func placementDragCannotContinueIntoTheNextPlayer() {
        let model = model()
        let start = AlkkagiVector(x: 80, y: 460)
        model.aim(start: start, translation: .init(x: 0, y: 0))
        model.tick(now: 130)
        #expect(model.game.currentPlayer == .white)
        model.aim(start: start, translation: .init(x: 0, y: -320))
        model.release()
        #expect(model.game.placedCount(.black) == 5)
        #expect(model.game.placedCount(.white) == 0)

        model.aim(start: .init(x: 80, y: 140), translation: .init(x: 0, y: 0))
        model.release()
        #expect(model.game.placedCount(.white) == 1)
    }

    @Test("시간이 끝나면 같은 시작점에 있는 상대 돌로 드래그가 이어지지 않는다")
    func aimingDragCannotSelectAnOpponentAfterTimeout() {
        let model = model()
        let placedBlack = model.game.placeStone(stoneID: 0, at: .init(x: 300, y: 325))
        #expect(placedBlack)
        _ = model.game.advance(dt: 30)
        let placedWhite = model.game.placeStone(stoneID: 5, at: .init(x: 300, y: 275))
        #expect(placedWhite)
        _ = model.game.advance(dt: 30)
        let start = AlkkagiVector(x: 300, y: 300)
        model.aim(start: start, translation: .init(x: 0, y: 80))
        #expect(model.selectedID == 0)
        model.tick(now: 130)
        #expect(model.game.currentPlayer == .white)
        model.aim(start: start, translation: .init(x: 0, y: -80))
        model.release()
        #expect(model.game.shotCount == 0)
        #expect(model.selectedID == nil)
    }

    @Test("두 번의 시간 초과로 같은 사람 차례가 되어도 오래된 발사는 취소된다")
    func delayedClockCancelsADragEvenWhenThePlayerIsUnchanged() {
        let model = model()
        _ = model.game.advance(dt: 89)
        #expect(model.game.turnRemaining == 1)
        let stone = model.game.stones[0]
        model.aim(start: stone.position, translation: .init(x: 0, y: 80))
        #expect(model.selectedID == stone.id)
        model.tick(now: 131)
        #expect(model.game.currentPlayer == .black)
        #expect(model.game.phase == .aiming)
        model.aim(start: stone.position, translation: .init(x: 0, y: 100))
        model.release()
        #expect(model.game.shotCount == 0)

        model.aim(start: stone.position, translation: .init(x: 0, y: 80))
        model.release()
        #expect(model.game.shotCount == 1)
    }

    @Test("취소한 제스처의 나머지 이동은 무시하고 다음 드래그는 허용한다")
    func cancelledGestureDoesNotFireOrBlockFutureGestures() {
        let model = model()
        _ = model.game.advance(dt: 60)
        let stone = model.game.stones[0]
        model.aim(start: stone.position, translation: .init(x: 0, y: 80))
        model.cancelAim()
        model.aim(start: stone.position, translation: .init(x: 0, y: 100))
        model.release()
        #expect(model.game.shotCount == 0)

        model.aim(start: stone.position, translation: .init(x: 0, y: 80))
        model.cancelAim()
        model.finishGesture() // SwiftUI가 포커스 상실로 제스처를 끝낸 경우
        model.aim(start: stone.position, translation: .init(x: 0, y: 80))
        model.release()
        #expect(model.game.shotCount == 1)
    }
}
