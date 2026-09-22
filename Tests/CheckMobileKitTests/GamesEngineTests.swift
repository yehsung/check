@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 엔진 구동(탭 입력 → 상태 전이). 화면 없이 `GamesPlayController` 를 프레임 단위로 민다.
@MainActor
@Suite struct GamesEngineTests {
    private let start = MobileClock.demoInstant

    @Test("타이밍 바: 탭하면 시작(onStarted 1회) → 탭마다 라운드 정지 → 결과 표시 중 탭은 무시 → 10라운드 완주를 한 번만 알린다")
    func timingBarTapTransitions() {
        let controller = GamesPlayController(kind: .timingBar, seed: 42)
        var started = 0
        var finished: [Int] = []
        controller.onStarted = { started += 1 }
        controller.onFinished = { finished.append($0) }

        #expect(!controller.isPlaying)
        controller.tap()
        #expect(started == 1)
        #expect(controller.tapSerial == 1)
        guard case .running(round: 1, _) = controller.timing.phase else {
            Issue.record("시작 탭 뒤 1라운드가 아니다: \(controller.timing.phase)")
            return
        }
        // 첫 프레임은 기준만 잡는다 — t 가 흐르지 않는다.
        controller.tick(at: start)
        if case .running(_, let t) = controller.timing.phase { #expect(t == 0) }

        // 240Hz 로 민다 — 한 프레임에 마커가 움직이는 거리의 절반 안에서 멈추면 정중앙 근처다(10라운드 주기 0.425초에서도 90점대).
        let dt = 1.0 / 240.0
        var now = start
        var rounds = 0
        var ignoredTapChecked = false
        for _ in 0..<(240 * 60) {
            now = now.addingTimeInterval(dt)
            controller.tick(at: now)
            switch controller.timing.phase {
            case .running(let round, _):
                let (center, _) = controller.timing.target
                let frameMove = 2 / TimingBarGame.period(round: round) * dt
                if abs(controller.timing.markerPosition - center) <= frameMove / 2 + 1e-9 {
                    controller.tap()
                    rounds += 1
                }
            case .roundResult:
                if !ignoredTapChecked {
                    let serial = controller.tapSerial
                    let before = controller.timing
                    controller.tap()
                    #expect(controller.timing == before, "결과 표시 중 탭이 판을 바꿨다")
                    #expect(controller.tapSerial == serial, "무시된 탭에 햅틱을 울렸다")
                    ignoredTapChecked = true
                }
            case .finished, .ready:
                break
            }
            if case .finished = controller.timing.phase { break }
        }
        guard case .finished(let total) = controller.timing.phase else {
            Issue.record("10라운드를 끝내지 못했다: \(controller.timing.phase)")
            return
        }
        #expect(rounds == TimingBarGame.roundCount)
        #expect(total >= 900, "목표 한가운데 근처에서 멈췄는데 총점이 낮다: \(total)")
        #expect(finished == [total])
        #expect(controller.gameOverSerial == 1)
        #expect(!controller.isPlaying)
        // 끝난 뒤 프레임은 아무것도 다시 알리지 않는다.
        gamesDrive(controller, from: now, frames: 30)
        #expect(finished.count == 1)
        // 다시 탭하면 새 판(onStarted 2회째).
        controller.tap()
        #expect(started == 2)
        #expect(controller.timing.round == 1)
    }

    @Test("플래피: 탭하면 시작·점프 → 안 누르면 떨어져 게임오버(햅틱 1회) → 유예 중 탭 무시 → 결과를 한 번만 알린다(점수 0)")
    func flappyTapTransitions() {
        let controller = GamesPlayController(kind: .flappy, seed: 7)
        var started = 0
        var finished: [Int] = []
        controller.onStarted = { started += 1 }
        controller.onFinished = { finished.append($0) }

        controller.tap()
        #expect(started == 1)
        #expect(controller.flappy.phase == .running)
        #expect(controller.flappy.bird.vy == FlappyGame.flapVelocity)
        #expect(controller.tapSerial == 1)
        controller.tick(at: start)

        let over = gamesDrive(controller, from: start, frames: 600) { c in
            if case .over = c.flappy.phase { return true }
            return false
        }
        guard case .over = controller.flappy.phase else {
            Issue.record("바닥에 닿아도 게임오버가 아니다: \(controller.flappy.phase)")
            return
        }
        #expect(controller.gameOverSerial == 1)
        let serial = controller.tapSerial
        controller.tap()
        #expect(controller.tapSerial == serial, "유예 중 탭이 먹혔다")
        #expect(started == 1)

        gamesDrive(controller, from: over, frames: 60)
        #expect(controller.flappy.phase == .result)
        #expect(finished == [0])
        #expect(controller.gameOverSerial == 1)
        controller.tap()
        #expect(started == 2)
        #expect(controller.flappy.phase == .running)
    }

    @Test("판 버리기(앱이 background): 진행 중이면 시작 전으로 돌아가고 끝났다고 알리지 않는다 · 진행 중이 아니면 아무것도 안 한다")
    func abandonEndsWithoutReporting() {
        // 폰이 **실제로 여는** 게임만 돈다(`MiniGameKind.phoneCases`). 테트리스는 아직 폰 엔진이 없어
        // 구동기가 "진행 중이 아니다"만 돌려주므로, 여기 넣으면 `#expect(controller.isPlaying)` 에서 죽는다.
        // 모바일 세션이 `phoneCases` 에 `.tetris` 를 더하는 순간 아래 switch 의 `.tetris` 갈래가 빨개져
        // 이 테스트를 채우게 만든다 — 목록에서 뺀 채로는 새 게임이 조용히 검증 밖으로 빠지지 않는다.
        for kind in MiniGameKind.phoneCases {
            let controller = GamesPlayController(kind: kind, seed: 99)
            var finished: [Int] = []
            controller.onFinished = { finished.append($0) }
            #expect(!controller.abandon(), "\(kind): 시작 전인데 버렸다고 한다")
            controller.tap()
            controller.tick(at: start)
            gamesDrive(controller, from: start, frames: 10)
            #expect(controller.isPlaying)
            #expect(controller.abandon())
            #expect(!controller.isPlaying)
            switch kind {
            case .timingBar: #expect(controller.timing.phase == .ready)
            case .flappy: #expect(controller.flappy.phase == .ready)
            case .tetris:
                Issue.record("테트리스가 phoneCases 에 들어왔다 — GamesPlayController 의 테트리스 갈래와 이 단언을 채워라")
            }
            gamesDrive(controller, from: start.addingTimeInterval(1), frames: 120)
            #expect(finished.isEmpty, "\(kind): 버린 판을 끝났다고 알렸다 → 제출된다")
        }
    }

    @Test("dt 는 엔진 상한(1/30초)으로 잘린다 — 몇 초 멈췄다 돌아온 첫 프레임이 판을 한꺼번에 밀지 않는다")
    func longGapIsClamped() {
        let controller = GamesPlayController(kind: .flappy, seed: 3)
        controller.tap()
        controller.tick(at: start)
        controller.tick(at: start.addingTimeInterval(5))
        #expect(controller.flappy.elapsed <= FlappyGame.maxStep + 1e-9)
    }
}
