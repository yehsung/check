import CheckCore
import CoreGraphics
import Foundation
import Observation

/// 미니게임 한 판을 **돌리는** 것(엔진 구동). 규칙은 코어 `TimingBarGame`·`FlappyGame`·`TetrisGame` 이고, 이 타입은 맥 게임 잎 뷰
/// (`TimingBarGameView`·`FlappyGameView`·`TetrisGameView`)가 `@State` 로 하던 일 — 탭 → 전이, 프레임 시각 → `step(dt:)`,
/// 시작·끝 알림 — 을 뷰 밖으로 꺼냈다. 그래서 macOS `swift test` 가 "탭 입력 → 상태 전이"를 화면 없이 구동한다.
///
/// 지키는 것(맥과 같다)
/// - **물리는 논리 좌표·시간 기준이다.** 화면 크기·주사율은 이 타입에 들어오지 않는다(등비 확대는 뷰의 일, dt 는 실제 경과).
///   dt 는 엔진의 `maxStep` 으로 잘린다 — 앱이 멈췄다 돌아온 첫 프레임이 몇 초를 한꺼번에 흘리지 않는다.
///   ⚠️ 그 상한은 **게임마다 다르다**: 타이밍 바·플래피는 1/30초, 테트리스는 **1/20초**다. 24Hz·30Hz 화면의 프레임 간격이
///   1/30 과 같거나 커서, 1/30 을 쓰면 매 프레임이 깎여 판이 실시간보다 느리게 돈다(근거표는 `TetrisGame.maxStep`).
/// - 시작 뒤 첫 프레임은 기준만 잡는다(정지해 있던 시간을 물려받지 않는다).
/// - 끝난 판은 **한 번만** 알린다(`onFinished`). 타이밍 바는 10라운드 완주, 플래피는 결과 확정(게임오버 유예 뒤),
///   테트리스는 `.result` 전이(탑아웃 유예 뒤 · `interrupt()` 포함 — 맥 잎 뷰의 `onChange(of: game.phase)` 와 같은 자리).
/// - 폰 전용 출구가 **둘**이다. 뜻이 다르므로 함수도 둘이다:
///   · `abandon()` — 판을 **기록 없이 버린다**(로그아웃 · 화면 경합 정리). 알리지 않으므로 제출도 없다.
///   · `endRound()` — 판을 **끝낸다**(뒤로가기 · 앱이 background 로 감). 타이밍 바·플래피는 버리는 것과 같고,
///     **테트리스만 그 자리에서 점수를 확정해 알린다**(까닭은 `endRound()` 주석 — 폰에서 background 는 비용이
///     0.05초뿐인 무한 일시정지라 살려 두면 순위표가 통째로 흔들린다).
///
/// 폰 테트리스 입력(끌기·탭)의 **판정도 여기 있다**(`canvasDragChanged`·`canvasDragEnded`). 트래커를 뷰 `@State` 에
/// 두지 않은 이유가 셋이다:
/// ① `DragGesture.Value` 에는 **시작 시각이 없다**(`time`·`location`·`startLocation`·`translation`·`velocity`·
///    `predictedEnd*` 뿐) — 탭 판정의 elapsed 를 내려면 누군가 첫 `time` 을 기억해야 한다.
/// ② 트래커는 값 타입이고 `drag(...)` 이 소비량을 쓴다 — 뷰 `@State` 에 두면 **터치 이벤트마다 body 가 재평가된다**(120Hz).
/// ③ 이 파일과 `GamesTetrisGesture.swift` 에는 `#if os(iOS)` 가 **없다** — 여기 두면 macOS `swift test` 가
///    손가락 좌표부터 조각 위치까지 화면 없이 구동한다.
@MainActor
@Observable
package final class GamesPlayController {
    /// `endRound()` 가 무엇을 했는가. 허브가 이 값으로 안내 문구를 고른다.
    package enum EndOutcome: Equatable, Sendable {
        /// 끝낼 판이 없었다(진행 중이 아니다 — 결과 카드는 그대로 둔다).
        case none
        /// 기록 없이 끝냈다(타이밍 바·플래피). 알리지 않았으므로 제출도 없다.
        case abandoned
        /// 그 점수로 **확정**했다(테트리스). `onFinished` 는 이 함수 안에서 이미 불렸다.
        case confirmed(Int)
    }

    package let kind: MiniGameKind
    package private(set) var timing: TimingBarGame
    package private(set) var flappy: FlappyGame
    package private(set) var tetris: TetrisGame
    /// 탭이 판에 먹혔을 때마다 +1(가벼운 햅틱의 방아쇠). **판이 실제로 바뀌었을 때만** 올린다 —
    /// 소진된 홀드·못 도는 회전은 조용해야 한다.
    package private(set) var tapSerial = 0
    /// 게임오버·완주마다 +1(한 번짜리 햅틱의 방아쇠).
    package private(set) var gameOverSerial = 0
    /// 하드드롭마다 +1(테트리스 — 단단한 햅틱). 이동·소프트드롭에는 **serial 이 없다**:
    /// 소프트드롭은 L1 에서 초당 56회, L5 에서 213회라 탭틱 엔진이 낼 수 있는 속도가 아니다.
    package private(set) var hardDropSerial = 0
    /// 줄을 **실제로 지운** 배치마다 +1(테트리스 — 묵직한 햅틱). 소거 없는 배치는 올리지 않는다.
    package private(set) var lineClearSerial = 0

    /// 판이 **시작됐다**(탭으로 ready/결과 → 진행). 허브가 라운드 토큰을 챙긴다.
    @ObservationIgnored package var onStarted: (@MainActor () -> Void)?
    /// 유효하게 끝난 판의 점수. 판마다 한 번.
    @ObservationIgnored package var onFinished: (@MainActor (Int) -> Void)?

    /// 이 판의 **벽시계 상한**(초 · 폰 테트리스만 — 허브가 `beginRound` 에서 건넨다. 기존 두 게임은 nil).
    /// 상한을 지나면 `tick(at:)` 이 판을 끝낸다(`endRound()`). 사용자 스위치로 주지 않는다.
    ///
    /// ⚠️ **절대 시각이 아니라 길이다.** 예전에는 허브가 `context.clock.now() + 15분` 으로 찍은 `Date` 를 건넸는데,
    /// 그 마감을 재는 `tick(at:)` 의 `now` 는 `TimelineView` 가 주는 **실제 벽시계**다. 축이 둘로 섞여 있어서
    /// 시계를 주입한 빌드(데모·테스트)에서는 마감이 **이미 지난 과거**로 찍혀 판이 첫 프레임에 죽었다.
    /// 길이로 받으면 기준점을 `tick` 이 자기 축에서 잡으므로 축이 하나뿐이고, 어느 시계를 주입하든 판은 15분을 산다.
    ///
    /// 반대쪽(주입 시계)으로 통일하지 않은 이유: `tick` 의 `now` 는 화면(`TimelineView`)이 주는 값이라 구동기가
    /// 바꿀 자리가 없다. 바꿀 수 있는 쪽 하나를 그 축으로 옮기는 것이 **유일한** 한 축 통일이다.
    @ObservationIgnored package var roundLimitSeconds: TimeInterval?

    /// 위 길이를 **tick 축**에서 절대 시각으로 굳힌 값. 판마다 첫 틱이 잡고, 새 판·출구가 비운다.
    @ObservationIgnored private var roundDeadline: Date?

    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var reportedFinish = false
    @ObservationIgnored private var seedSource: UInt64

    // MARK: 테트리스 제스처(폰 전용 · 화면 없이 구동된다)

    @ObservationIgnored private var gesture = TetrisGestureTracker(
        thresholds: TetrisGestureThresholds(cellWidth: TetrisLayout.cell))
    /// 지금 따라가는 접촉의 시작점·첫 프레임 시각. 시작점이 바뀌면 새 접촉이다(`onEnded` 는 늘 오지 않는다).
    @ObservationIgnored private var gestureStartLocation: CGPoint?
    @ObservationIgnored private var gestureStartedAt: Date?

    package init(kind: MiniGameKind, seed: UInt64) {
        self.kind = kind
        seedSource = seed
        timing = TimingBarGame(seed: seed)
        flappy = FlappyGame(seed: seed)
        tetris = TetrisGame(seed: seed)
    }

    // MARK: 읽기

    /// 프레임 루프가 돌아야 하는가.
    package var isPlaying: Bool {
        switch kind {
        case .timingBar: return timing.isPlaying
        case .flappy: return flappy.isPlaying
        case .tetris: return tetris.isPlaying
        }
    }

    /// 지금(또는 마지막) 판의 점수.
    package var score: Int {
        switch kind {
        case .timingBar: return timing.total
        case .flappy: return flappy.score
        case .tetris: return tetris.score
        }
    }

    // MARK: 입력

    /// 캔버스 탭(맥의 클릭·스페이스와 같은 한 번의 행동).
    ///
    /// ⚠️ 테트리스만 뜻이 갈린다: 진행 중이면 **시계 회전**이다(반시계는 버튼, 하드드롭도 버튼 — 설계 G).
    /// 맥처럼 `game.action()` 을 그대로 부르면 판 위 탭 한 번이 **하드드롭**이 되어, 조각을 돌리려던 손가락이
    /// 판을 끝낸다. 시작 전·결과 카드에서만 `action()`(= 새 판)이다.
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
        case .tetris:
            if tetris.isPlaying {
                rotate(clockwise: true)
            } else {
                let before = tetris
                tetris.action()
                if tetris != before { tapSerial &+= 1 }
            }
        }
        if isPlaying, !wasPlaying {
            reportedFinish = false
            lastTick = nil
            // 새 판의 상한 기준점은 **이 판의 첫 틱**이 다시 잡는다 — 앞 판의 기준점을 물려받으면 즉사한다.
            roundDeadline = nil
            // ⚠️ **이 줄을 지우지 마라.** 앞 끌기의 축 잠금·소비량이 남은 채 새 판이 켜지면, 다음 `onChanged` 의
            //    `translation` 은 0 부터인데 `consumed` 는 옛 값이라 `pending = 0 − consumed` 가 큰 반대 부호가 된다 —
            //    **손도 안 댄 첫 조각이 곧장 옆으로 가거나 바닥까지 소프트드롭된다.** 화면 쪽 방어
            //    (`GamesMiniGameScreen` 의 접촉 소진 표시)와 **짝**이다: 저쪽은 같은 손가락을 막고, 여기는
            //    어느 경로로 새 판이 켜지든 트래커를 비운다.
            resetGesture()
            onStarted?()
        }
    }

    /// 회전. 캔버스 탭이 시계, 버튼이 반시계다(설계 G — 버튼도 시계면 자리 하나를 버리고 반시계가 폰에서 사라진다).
    package func rotate(clockwise: Bool) {
        guard kind == .tetris else { return }
        let before = tetris.active
        tetris.rotate(clockwise: clockwise)
        if tetris.active != before { tapSerial &+= 1 }
    }

    /// 홀드(조각당 1회). 소진됐으면 엔진이 no-op 이고 **serial 도 안 올린다** — 눌러도 조용하다.
    ///
    /// 갈아탄 조각이 스폰 자리에서 막히면 **그 자리에서 판이 끝난다**(`spawn(fromHold:)` 의 블록아웃).
    /// 그 전이는 프레임 루프 **밖**에서 일어나므로 `tick` 의 게임오버 판정이 못 본다 — 다음 틱은 `step` 전에
    /// 이미 `.over` 를 읽어 `wasOver` 로 접는다. 그래서 여기서 직접 센다(안 그러면 이 경로에서만 `.error` 햅틱이 빠진다).
    package func hold() {
        guard kind == .tetris else { return }
        let before = tetris.holdUsed
        let beforePiece = tetris.active
        let mark = tetrisHapticMark()
        tetris.holdCurrentPiece()
        if tetris.holdUsed != before || tetris.active != beforePiece { tapSerial &+= 1 }
        noteTetrisHaptics(since: mark)
    }

    /// [즉시 내리기] 버튼. **진행 중일 때만** — 시작·다시는 캔버스가 한다(버튼이 판을 켜면 켜자마자 한 조각이 떨어진다).
    ///
    /// 하드드롭은 락딜레이를 안 기다리고 **그 자리에서** 굳혀 줄을 지운다 — 프레임 루프 밖이라 `tick` 의 소거
    /// 판정이 못 본다(다음 틱은 `step` 직전 값을 기준으로 삼으므로 이미 오른 소거가 기준값에 들어간다).
    /// 여기서 안 세면 설계 K 의 묵직한 햅틱이 **테트리스에서 제일 잦은 소거 경로**에서 통째로 빠진다.
    package func hardDrop() {
        guard kind == .tetris, tetris.phase == .running else { return }
        let mark = tetrisHapticMark()
        tetris.action()
        hardDropSerial &+= 1
        noteTetrisHaptics(since: mark)
    }

    /// 엔진을 **프레임 루프 밖에서** 건드리기 직전의 햅틱 기준점(마지막 소거 시각 · 이미 끝난 판인가).
    private func tetrisHapticMark() -> (clearedAt: TimeInterval?, wasOver: Bool) {
        var wasOver = false
        if case .over = tetris.phase { wasOver = true }
        return (tetris.lastClear?.at, wasOver)
    }

    /// 기준점 뒤에 **새로 생긴** 소거·게임오버를 센다. `tick(at:)` 의 테트리스 갈래와 **같은 판정 한 벌**이다 —
    /// 버튼·탭은 프레임 루프를 안 지나므로 여기서 세지 않으면 그 경로의 햅틱이 없다.
    /// 두 번 세지 않는다: `tick` 은 자기 `step(dt:)` **직전** 값을 기준으로 잡으므로 여기서 이미 오른 것은 그 기준에 든다.
    /// (`lastClear` 는 소거가 0줄인 배치에도 적힌다 — 그래서 `lines > 0` 이 있어야 한다.)
    private func noteTetrisHaptics(since mark: (clearedAt: TimeInterval?, wasOver: Bool)) {
        if let clear = tetris.lastClear, clear.lines > 0, clear.at != mark.clearedAt { lineClearSerial &+= 1 }
        if !mark.wasOver, case .over = tetris.phase { gameOverSerial &+= 1 }
    }

    /// 가로 한 칸 — **엔진 무수정**이다. 누름과 뗌을 **같은 호출 안에서 연달아** 준다:
    /// `updateRepeat(pressed:)` 가 `shift(by:)` 를 즉시 하고 뗌은 이동을 안 주므로, 쌍 사이에 시간이 안 흘러
    /// DAS(0.167초)가 만기될 수 없고 쌍이 끝나면 반복 상태가 완전히 원상복구된다.
    /// ⚠️ **쌍 사이에 `step(dt:)` 을 끼우지 마라** — 그 순간 자동 반복이 살아나 한 번의 걸음이 여러 칸이 된다.
    ///
    /// 이 배선은 엔진 내부 구현에 기대므로 계약 테스트가 못 박는다 —
    /// **이 함수를 실제로 지나는** `theSidewaysStepIsSymmetricAndLeavesNoRepeat`(`GamesTetrisWiringTests`)이다.
    /// ⚠️ 엔진을 직접 부르는 쪽(`aPressReleasePairMovesExactlyOneCellAndArmsNoRepeat` · 맥 타깃)은 `feed` 를
    /// **한 번도 안 지난다**: 뗌을 지워도, `.moveRight` 갈래를 통째로 `break` 로 무력화해도 초록이었다(뮤테이션 실측).
    /// 엔진 계약과 이 배선은 서로를 대신하지 못한다 — 둘 다 있어야 한다.
    package func moveLeftOneCell() { feed(.moveLeft) }
    package func moveRightOneCell() { feed(.moveRight) }
    /// 세로 한 칸(엔진 `softDropOneCell` — 한 칸 · 1점 · 접지 리셋 예산 안 씀 · 중력 되감기).
    package func softDropOneCell() { feed(.softDrop) }

    private func feed(_ step: TetrisGestureStep) {
        guard kind == .tetris, tetris.phase == .running else { return }
        switch step {
        case .moveLeft:
            tetris.setLeftHeld(true)
            tetris.setLeftHeld(false)
        case .moveRight:
            tetris.setRightHeld(true)
            tetris.setRightHeld(false)
        case .softDrop:
            tetris.softDropOneCell()
        }
    }

    // MARK: 테트리스 제스처

    /// 화면 배율이 정해졌다(또는 바뀌었다) — 한 칸 문턱은 **화면 셀 폭**이다(논리 13 × 배율).
    package func updateCellWidth(_ width: CGFloat) {
        gesture.updateCellWidth(width)
    }

    /// `DragGesture.onChanged` — 시작점부터의 누적 이동을 그대로 넘기면 새로 생긴 걸음이 엔진에 먹는다.
    /// 시각(`value.time`)은 **탭 판정용**이다: 첫 프레임의 시각을 기억해 뒀다가 `canvasDragEnded` 에서 elapsed 를 낸다.
    package func canvasDragChanged(startLocation: CGPoint, translation: CGSize, at time: Date) {
        guard kind == .tetris else { return }
        if gestureStartLocation != startLocation {
            gestureStartLocation = startLocation
            gestureStartedAt = time
        }
        for step in gesture.drag(startLocation: startLocation, translation: translation) { feed(step) }
    }

    /// `DragGesture.onEnded` — 탭(8pt 미만 · 0.25초 안)이면 **시계 회전**이다.
    /// - Returns: 이 끌기가 탭이었는가(회전을 시도했는가).
    @discardableResult
    package func canvasDragEnded(translation: CGSize, at time: Date) -> Bool {
        guard kind == .tetris else { return false }
        let elapsed = gestureStartedAt.map { max(0, time.timeIntervalSince($0)) } ?? 0
        gestureStartLocation = nil
        gestureStartedAt = nil
        guard gesture.end(translation: translation, elapsed: elapsed) else { return false }
        rotate(clockwise: true)
        return true
    }

    /// 새 판·출구에서 트래커를 비운다. 안 비우면 앞 끌기의 축 잠금·소비량이 다음 판으로 샌다.
    private func resetGesture() {
        _ = gesture.end(translation: .zero, elapsed: 0)
        gestureStartLocation = nil
        gestureStartedAt = nil
    }

    // MARK: 프레임

    /// 프레임 시각 한 번(뷰의 TimelineView 가 날짜가 바뀔 때 부른다).
    package func tick(at now: Date) {
        guard isPlaying else {
            lastTick = nil
            return
        }
        // 판 상한은 **가드 뒤 · dt 계산 앞**이다: 첫 프레임(기준만 잡는 프레임)에서도 걸려야
        // 앱이 오래 멈춰 있다 돌아온 그 순간에 판이 끝난다.
        // 기준점도 **여기서** 잡는다 — 그래야 마감과 그걸 재는 `now` 가 같은 축에 있다(`roundLimitSeconds` 주석).
        if kind == .tetris, let limit = roundLimitSeconds {
            let deadline = roundDeadline ?? now.addingTimeInterval(limit)
            roundDeadline = deadline
            if now >= deadline {
                endRound()
                return
            }
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
        case .tetris:
            // 소거·게임오버 햅틱 판정은 버튼 경로(`hardDrop()`·`hold()`)와 **한 벌**이다.
            let mark = tetrisHapticMark()
            tetris.step(dt: dt)
            noteTetrisHaptics(since: mark)
            // 맥 잎 뷰의 `onChange(of: game.phase)` 와 같은 자리 — `.result` 로 들어간 순간이 확정이다.
            if tetris.phase == .result, !reportedFinish {
                reportedFinish = true
                onFinished?(tetris.score)
            }
        }
    }

    // MARK: 출구

    /// 판을 **기록 없이** 버린다(로그아웃 · 화면 경합 정리). 시작 전 화면으로 돌아간다.
    /// 진행 중이 아니면 아무것도 하지 않는다(결과 카드는 그대로 둔다). 끝났다고 알리지 않는다 — 그래서 제출도 없다.
    ///
    /// ⚠️ **뒤로가기·background 는 여기가 아니라 `endRound()` 다.** 셋의 의도가 다르다: 로그아웃은 남의 계정에
    /// 점수를 올리면 안 되고, 화면 경합 정리는 아직 시작도 안 한 판을 치우는 것이고, 뒤로가기·background 는
    /// 사람이 **실제로 쌓아 올린 판**이다. 여기에 테트리스 제출을 넣으면 그 셋이 한꺼번에 제출 쪽으로 넘어간다.
    /// - Returns: 진행 중인 판을 실제로 끝냈는가.
    @discardableResult
    package func abandon() -> Bool {
        guard isPlaying else { return false }
        reportedFinish = true
        lastTick = nil
        // 상한은 **길이와 기준점 둘 다** 비운다 — 다음 판의 길이는 허브가 `beginRound` 에서 다시 건네고,
        // 기준점은 그 판의 첫 틱이 다시 잡는다.
        roundLimitSeconds = nil
        roundDeadline = nil
        resetGesture()
        switch kind {
        case .timingBar:
            timing.invalidate()
        case .flappy:
            // 플래피 규칙에는 '무효'가 없다(interrupt 는 그 점수로 결과를 확정한다) — 새 판(시작 전)으로 갈아 끼운다.
            seedSource &+= 0x9E37_79B9
            flappy = FlappyGame(seed: seedSource)
        case .tetris:
            // 테트리스도 같다(`interrupt()` 는 확정이다) — 버리려면 새 판으로 갈아 끼워야 한다.
            seedSource &+= 0x9E37_79B9
            tetris = TetrisGame(seed: seedSource)
        }
        return true
    }

    /// 판을 **끝낸다**(화면을 떠남 · 앱이 background 로 감). 기존 두 게임은 `abandon()` 과 같고,
    /// **테트리스는 그 자리에서 점수를 확정해 알린다.**
    ///
    /// ⚠️ 왜 테트리스만 다른가: 폰에서 background 는 지금 **비용 0 의 무한 일시정지**다. 복귀 첫 프레임의 dt 는
    /// `maxStep`(테트리스 1/20)으로 잘리므로 몇 분을 나가 있어도 판이 잃는 것은 0.05초(L1 에서 0.141칸 —
    /// 한 칸도 안 내려간다)뿐이다. 맥은 스크림 + 3-2-1 + 5분 상한으로 그 구멍을 막았지만 폰에는 스크림조차 없고
    /// 앱 전환기 스냅숏에 판이 그대로 남는다. 그래서 나가는 순간 **여기까지의 점수로 확정**한다.
    ///
    /// ⚠️ `interrupt()` 뒤에는 **tick 이 다시 오지 않는다**: phase 가 `.result` → `isPlaying` false →
    /// `TimelineView(paused:)` 가 멈춘다. 맥은 `.onChange(of: game.phase)` 가 알리지만 폰 구동기에는 그 관찰자가
    /// 없다 — 여기서 직접 `onFinished` 를 부르지 않으면 **점수가 조용히 사라진다.**
    @discardableResult
    package func endRound() -> EndOutcome {
        guard isPlaying else { return .none }
        switch kind {
        case .timingBar, .flappy:
            return abandon() ? .abandoned : .none
        case .tetris:
            reportedFinish = true
            lastTick = nil
            roundLimitSeconds = nil
            roundDeadline = nil
            resetGesture()
            tetris.interrupt()
            tetris.releaseAllKeys()
            let score = tetris.score
            onFinished?(score)
            return .confirmed(score)
        }
    }

    #if DEBUG
    /// 테스트·데모 전용: 임의 상태에서 시작한다.
    package func replaceForTesting(timing: TimingBarGame? = nil, flappy: FlappyGame? = nil, tetris: TetrisGame? = nil) {
        if let timing { self.timing = timing }
        if let flappy { self.flappy = flappy }
        if let tetris { self.tetris = tetris }
        lastTick = nil
        reportedFinish = !isPlaying
    }
    #endif
}
