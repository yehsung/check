import CheckCore
import Foundation
import Observation

/// 미니게임 한 판을 **돌리는** 것(엔진 구동). 규칙은 코어 `TimingBarGame`·`FlappyGame` 이고, 이 타입은 맥 게임 잎 뷰
/// (`TimingBarGameView`·`FlappyGameView`)가 `@State` 로 하던 일 — 탭 → 전이, 프레임 시각 → `step(dt:)`, 시작·끝 알림 — 을
/// 뷰 밖으로 꺼냈다. 그래서 macOS `swift test` 가 "탭 입력 → 상태 전이"를 화면 없이 구동한다.
///
/// 지키는 것(맥과 같다)
/// - **물리는 논리 좌표·시간 기준이다.** 화면 크기·주사율은 이 타입에 들어오지 않는다(등비 확대는 뷰의 일, dt 는 실제 경과).
///   dt 는 엔진의 `maxStep`(1/30초)으로 잘린다 — 앱이 멈췄다 돌아온 첫 프레임이 몇 초를 한꺼번에 흘리지 않는다.
/// - 시작 뒤 첫 프레임은 기준만 잡는다(정지해 있던 시간을 물려받지 않는다).
/// - 끝난 판은 **한 번만** 알린다(`onFinished`). 타이밍 바는 10라운드 완주, 플래피는 결과 확정(게임오버 유예 뒤).
/// - 폰 전용: `abandon()` — 앱이 background 로 가면 판을 끝내고 **알리지 않는다**(제출하지 않는다, SPEC-ios §3.5).
@MainActor
@Observable
package final class GamesPlayController {
    package let kind: MiniGameKind
    package private(set) var timing: TimingBarGame
    package private(set) var flappy: FlappyGame
    /// 탭이 판에 먹혔을 때마다 +1(가벼운 햅틱의 방아쇠).
    package private(set) var tapSerial = 0
    /// 게임오버·완주마다 +1(한 번짜리 햅틱의 방아쇠).
    package private(set) var gameOverSerial = 0

    /// 판이 **시작됐다**(탭으로 ready/결과 → 진행). 허브가 라운드 토큰을 챙긴다.
    @ObservationIgnored package var onStarted: (@MainActor () -> Void)?
    /// 유효하게 끝난 판의 점수. 판마다 한 번.
    @ObservationIgnored package var onFinished: (@MainActor (Int) -> Void)?

    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var reportedFinish = false
    @ObservationIgnored private var seedSource: UInt64

    package init(kind: MiniGameKind, seed: UInt64) {
        self.kind = kind
        seedSource = seed
        timing = TimingBarGame(seed: seed)
        flappy = FlappyGame(seed: seed)
    }

    // MARK: 읽기

    /// 프레임 루프가 돌아야 하는가.
    package var isPlaying: Bool {
        switch kind {
        case .timingBar: return timing.isPlaying
        case .flappy: return flappy.isPlaying
        // 폰에는 테트리스가 보이지 않는다(`MiniGameKind.phoneCases`) — 이 갈래로는 아무도 못 들어온다.
        // **모바일 세션이 여기를 채운다**(TetrisGame 을 이 타입에 물리고, 아래 다섯 갈래를 한꺼번에).
        // "진행 중이 아니다"로 두는 이유: 프레임 루프가 아예 안 돌고 `abandon()` 도 조용히 false 를 준다 —
        // 배선이 빠진 채 화면만 붙어도 **점수가 제출되지 않는다**(순위표를 더럽히지 않는 쪽으로 넘어진다).
        case .tetris: return false
        }
    }

    /// 지금(또는 마지막) 판의 점수.
    package var score: Int {
        switch kind {
        case .timingBar: return timing.total
        case .flappy: return flappy.score
        // 모바일 세션이 여기를 채운다(폰 미도달 — 위 isPlaying 주석).
        case .tetris: return 0
        }
    }

    // MARK: 입력

    /// 캔버스 탭(맥의 클릭·스페이스와 같은 한 번의 행동).
    package func tap() {
        let wasPlaying = isPlaying
        switch kind {
        case .timingBar:
            let before = timing
            timing.tap()
            if timing != before { tapSerial &+= 1 }
        case .flappy:
            let before = flappy.flapCount
            let beforePhase = flappy.phase
            flappy.flap()
            if flappy.flapCount != before || flappy.phase != beforePhase { tapSerial &+= 1 }
        // 모바일 세션이 여기를 채운다(폰 미도달 — 위 isPlaying 주석). 탭을 삼킨다: 햅틱도 시작 알림도 없다.
        case .tetris:
            break
        }
        if isPlaying, !wasPlaying {
            reportedFinish = false
            lastTick = nil
            onStarted?()
        }
    }

    /// 프레임 시각 한 번(뷰의 TimelineView 가 날짜가 바뀔 때 부른다).
    package func tick(at now: Date) {
        guard isPlaying else {
            lastTick = nil
            return
        }
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = now.timeIntervalSince(last)
        switch kind {
        case .timingBar:
            timing.step(dt: dt)
            if case .finished(let total) = timing.phase, !reportedFinish {
                reportedFinish = true
                gameOverSerial &+= 1
                onFinished?(total)
            }
        case .flappy:
            let wasRunning = flappy.phase == .running
            flappy.step(dt: dt)
            if wasRunning, case .over = flappy.phase { gameOverSerial &+= 1 }
            if flappy.phase == .result, !reportedFinish {
                reportedFinish = true
                onFinished?(flappy.score)
            }
        // 모바일 세션이 여기를 채운다(폰 미도달 — 위 isPlaying 주석). isPlaying 이 false 라 여기까지 오지도 않는다.
        case .tetris:
            break
        }
    }

    /// 판을 **기록 없이** 끝낸다(앱이 background 로 감 · 화면을 떠남). 시작 전 화면으로 돌아간다.
    /// 진행 중이 아니면 아무것도 하지 않는다(결과 카드는 그대로 둔다). 끝났다고 알리지 않는다 — 그래서 제출도 없다.
    /// - Returns: 진행 중인 판을 실제로 끝냈는가.
    @discardableResult
    package func abandon() -> Bool {
        guard isPlaying else { return false }
        reportedFinish = true
        lastTick = nil
        switch kind {
        case .timingBar:
            timing.invalidate()
        case .flappy:
            // 플래피 규칙에는 '무효'가 없다(interrupt 는 그 점수로 결과를 확정한다) — 새 판(시작 전)으로 갈아 끼운다.
            seedSource &+= 0x9E37_79B9
            flappy = FlappyGame(seed: seedSource)
        // 모바일 세션이 여기를 채운다(폰 미도달 — 위 isPlaying 주석). isPlaying 이 false 라 가드에서 이미 돌아간다.
        case .tetris:
            break
        }
        return true
    }

    #if DEBUG
    /// 테스트·데모 전용: 임의 상태에서 시작한다.
    package func replaceForTesting(timing: TimingBarGame? = nil, flappy: FlappyGame? = nil) {
        if let timing { self.timing = timing }
        if let flappy { self.flappy = flappy }
        lastTick = nil
        reportedFinish = !isPlaying
    }
    #endif
}
