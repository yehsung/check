@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **1:1 테트리스 대결 화면**(1.0.11 레인 C)의 못.
//
// 이 화면은 전부 `#if os(iOS)` 안이라 맥 스위트가 뷰를 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못
// 본다'). 그래서 셋으로 증명한다:
//   ① **결과 숫자** — 손가락 좌표부터 엔진 상태까지 실제로 구동한다(`GamesTetrisDuelTouch` 는 `#if` 가 없다).
//   ② **순수 표** — 입력 게이트 · 가속 경계 · 결과 사유·루비는 `GamesTetrisDuelChrome` 이 값으로 답한다.
//   ③ **소스 계약** — 뷰 몸통에서만 지킬 수 있는 것(경고 줄이 판 화면에 있다 · 기권은 확인 뒤에만 · 캔버스는
//      그림만 그린다)은 주석을 걷은 소스 글자로 잰다.
//
// 재는 것이 "함수를 불렀나"가 아니라 **"조각이 몇 칸 갔나 · 점수가 몇 점 올랐나 · 루비가 몇인가"** 임에 주의.

@MainActor
@Suite struct GamesTetrisDuelMatchTests {
    private nonisolated static let matchPath = "Sources/CheckMobileKit/Games/GamesTetrisDuelMatch.swift"
    private nonisolated static let canvasPath = "Sources/CheckMobileKit/Games/GamesTetrisDuelCanvas.swift"

    private nonisolated static let base: TimeInterval = 10_000
    private nonisolated static let wall = Date(timeIntervalSince1970: 1_800_000_000)

    /// L28 — 리셋 한도 2 · 재충전 없음(접지 예산 측정의 전제). 맥 규칙 테스트·솔로 폰 배선과 **같은 판**이다.
    private nonisolated static let level28Stack = [
        ".########.",
        ".########.",
        ".########.",
        ".########.",
        ".########.",
        ".########."
    ]

    // MARK: - 조각

    private nonisolated static func opponent(name: String = "테트라이벌") -> TetrisDuelUser {
        TetrisDuelUser(id: "00000000-0000-0000-0000-000000000011", displayName: name, avatarURL: nil,
                       characterID: nil, isWorking: true, isCapable: true, inMatch: true)
    }

    private nonisolated static func match(stake: Int = 5, finished: Bool = false,
                                          outcome: TetrisDuelOutcome? = nil,
                                          reason: TetrisDuelEndReason? = nil, delta: Int? = nil,
                                          board: TetrisDuelOpponentBoard = .empty,
                                          readyDeadline: Date? = nil) -> TetrisDuelMatchState {
        TetrisDuelMatchState(
            id: "7e7e0000-0000-4000-8000-000000000011", stake: stake, seed: 7, opponent: opponent(),
            acceptedAt: wall.addingTimeInterval(-6), readyDeadline: readyDeadline,
            startAt: nil, maxEnd: nil, meReady: true, opponentBoard: board, isFinished: finished,
            outcome: outcome, endReason: reason, rubyDelta: delta, finishedAt: finished ? wall : nil)
    }

    /// 판이 흐르는 스토어 — **시계 둘을 고정한다**(단조 시계가 고정이라 입력 사이에 중력이 끼지 않는다).
    private func playingStore(game: TetrisGame, simulated: TimeInterval = 0,
                              board: TetrisDuelOpponentBoard = .empty) -> TetrisDuelStore {
        let store = TetrisDuelStore()
        store.pollStepSeconds = 3_600
        store.gameLoopStepSeconds = 3_600          // 판 루프는 돌지 않는다 — 이 테스트가 tick 을 직접 부른다.
        store.clock = { Self.wall }
        store.uptime = { Self.base }
        let state = Self.match(board: board)
        store.match = state
        store.duel = TetrisDuelSession(seed: 7, startedGame: game, startAt: Self.base - simulated,
                                       simulated: simulated)
        store.duelMatchID = state.id
        store.phase = .playing
        store.syncStats()
        return store
    }

    private func chrome(_ store: TetrisDuelStore, match: TetrisDuelMatchState? = nil) -> GamesTetrisDuelChrome {
        GamesTetrisDuelChrome(match: match ?? store.match!, phase: store.phase, myStats: store.myStats,
                              notice: store.notice, connectionTrouble: store.connectionTrouble)
    }

    /// 떨어지는 조각의 **가장 왼쪽 열**(이동을 재는 자리).
    private func column(_ store: TetrisDuelStore) -> Int? {
        store.duel?.game.active?.cells.map(\.column).min()
    }

    private func row(_ store: TetrisDuelStore) -> Int? {
        store.duel?.game.active?.row
    }

    /// 빈 판 + 떨어지는 T 하나(이동·회전을 재기에 넉넉하다).
    private nonisolated static func freeGame() -> TetrisGame {
        TetrisGame(seed: 7, board: TetrisGame.emptyBoard(),
                   active: TetrisGame.ActivePiece(piece: .t, column: 4, row: 24),
                   next: [.i, .o, .s, .z, .l], heldPiece: nil, advance: 0, lines: 0)
    }

    // MARK: - ① 손가락 → 조각 (결과 숫자)

    @Test("끌기 한 칸이 조각을 **정확히 한 칸** 옮긴다 · 세 칸은 세 칸 · 되돌리면 되돌아온다")
    func oneDragCellMovesThePieceOneCell() throws {
        let store = playingStore(game: Self.freeGame())
        let touch = GamesTetrisDuelTouch(cellWidth: 20)
        let start = CGPoint(x: 100, y: 300)
        let before = try #require(column(store))

        touch.changed(startLocation: start, translation: CGSize(width: 20, height: 0), at: Self.wall, into: store)
        #expect(column(store) == before + 1, "한 칸 끌었는데 \(column(store).map(String.init) ?? "nil") 열이다")

        // 같은 끌기를 세 칸까지 이어 간다 — 누적 이동이라 **새로 생긴 두 칸**만 더 가야 한다.
        touch.changed(startLocation: start, translation: CGSize(width: 60, height: 0), at: Self.wall, into: store)
        #expect(column(store) == before + 3, "누적 60pt(세 칸)인데 \(column(store).map(String.init) ?? "nil") 열이다")

        // 손가락을 되돌리면 조각도 돌아온다(가로는 환불한다 — 손가락 위치가 곧 조각 위치).
        touch.changed(startLocation: start, translation: .zero, at: Self.wall, into: store)
        #expect(column(store) == before, "손가락을 되돌렸는데 조각이 안 돌아왔다")
    }

    @Test("한 걸음 뒤에 **키가 눌린 채 남지 않는다** — 0.5초가 흘러도 조각이 더 가지 않는다")
    func aGestureStepDoesNotLeaveAKeyHeld() throws {
        // ★ 이것이 `setLeftHeld` 로 흉내 내지 말라는 계약의 결과다(P9 · 코어 `moveRightOneCell` 주석).
        //   누름만 보내면 다음 틱마다 자동 반복이 조각을 계속 옮긴다 — 한 번의 끌기가 판 끝까지 민다.
        let store = playingStore(game: Self.freeGame())
        let touch = GamesTetrisDuelTouch(cellWidth: 20)
        touch.changed(startLocation: .zero, translation: CGSize(width: 20, height: 0), at: Self.wall, into: store)
        let after = try #require(column(store))

        // 0.5초(DAS 0.167초의 세 배)를 흘린다 — 눌린 키가 남아 있으면 여기서 여러 칸이 더 간다.
        store.tick(now: Self.base + 0.5)
        #expect(column(store) == after, "걸음 하나 뒤에 키가 눌린 채 남았다 — 0.5초에 \(column(store)! - after)칸 더 갔다")
    }

    @Test("아래로 끌기 한 칸 = **1점** · 접지 예산은 쓰지 않는다(기준선: 가로 걸음 둘은 정말 쓴다)")
    func softDropStepScoresOneAndKeepsTheLockBudget() throws {
        // L28: 리셋 한도 2 · 재충전 없음. 예산을 다 쓰면 **바닥에 닿는 순간 곧바로** 굳는다(락딜레이를 못 쓴다).
        // 그래서 "닿은 직후 한 프레임 뒤에도 조각이 살아 있는가" 가 곧 "예산이 남았는가" 다.
        func fixture() -> TetrisGame {
            TetrisGame(seed: 11, board: TetrisGame.boardFixture(bottomRows: Self.level28Stack),
                       active: TetrisGame.ActivePiece(piece: .o, column: TetrisGame.spawnColumn,
                                                      row: TetrisGame.spawnRow),
                       advance: 930)
        }
        #expect(TetrisGame.lockResetLimit(forLevel: fixture().level) == 2, "리셋 한도 전제가 깨졌다")
        #expect(!TetrisGame.lockResetRefreshes(forLevel: fixture().level), "재충전이 켜져 있으면 이 측정이 헛돈다")

        // ⓐ 점수: 한 칸이 1점이다.
        let scored = playingStore(game: Self.freeGame())
        let touch = GamesTetrisDuelTouch(cellWidth: 20)
        let scoreBefore = scored.duel?.game.score ?? -1
        let rowBefore = try #require(row(scored))
        touch.changed(startLocation: .zero, translation: CGSize(width: 0, height: 20), at: Self.wall, into: scored)
        #expect(row(scored) == rowBefore + 1, "아래로 한 칸 끌었는데 조각이 안 내려갔다")
        #expect(scored.duel?.game.score == scoreBefore + 1, "소프트드롭 한 칸이 1점이 아니다")

        /// 접지할 때까지 **손가락 걸음으로만** 내린다.
        func dropToFloor(_ store: TetrisDuelStore) -> Int {
            var cells = 0
            while store.duel?.game.isGrounded == false, cells < 40 {
                GamesTetrisDuelTouch.feed(.softDrop, into: store)
                cells += 1
            }
            return cells
        }

        // ⓑ 예산이 남는다 — 손가락으로만 내렸다.
        let soft = playingStore(game: fixture())
        let cells = dropToFloor(soft)
        #expect(cells >= 3, "\(cells)칸밖에 안 내려갔다 — 픽스처가 이미 바닥 근처다")
        #expect(soft.duel?.game.isGrounded == true)
        soft.tick(now: Self.base + 2.0 / 120.0)
        #expect(soft.duel?.game.active != nil, "소프트드롭 \(cells)칸이 리셋 예산을 썼다 — 닿자마자 굳었다")

        // ⓒ ★ 기준선이 다르다: **가로 걸음 두 번**은 예산을 정말 쓴다(같은 판·같은 자리인데 결과가 반대다).
        let shifted = playingStore(game: fixture())
        GamesTetrisDuelTouch.feed(.moveLeft, into: shifted)
        GamesTetrisDuelTouch.feed(.moveRight, into: shifted)
        _ = dropToFloor(shifted)
        #expect(shifted.duel?.game.isGrounded == true)
        shifted.tick(now: Self.base + 2.0 / 120.0)
        #expect(shifted.duel?.game.active == nil, "예산 2를 다 썼는데 안 굳었다 — 이 비교의 기준선이 헛돈다")
    }

    @Test("톡 누르기는 **시계 회전**이다 · 8pt 넘게 움직였거나 0.25초를 넘겨 뗐으면 아무 일도 안 난다")
    func tapRotatesClockwise() throws {
        let store = playingStore(game: Self.freeGame())
        let touch = GamesTetrisDuelTouch(cellWidth: 20)
        let before = try #require(store.duel?.game.active?.rotation)
        touch.changed(startLocation: .zero, translation: CGSize(width: 2, height: 2), at: Self.wall, into: store)
        #expect(touch.ended(translation: CGSize(width: 2, height: 2),
                            at: Self.wall.addingTimeInterval(0.1), into: store), "탭으로 안 읽혔다")
        #expect(store.duel?.game.active?.rotation != before, "탭이 회전을 안 했다")

        // 천천히 뗀 손가락(0.4초)은 탭이 아니다 — 애매한 입력을 아무 동작으로도 확정하지 않는다.
        let slow = playingStore(game: Self.freeGame())
        let slowTouch = GamesTetrisDuelTouch(cellWidth: 20)
        let slowBefore = try #require(slow.duel?.game.active?.rotation)
        slowTouch.changed(startLocation: .zero, translation: CGSize(width: 2, height: 0), at: Self.wall, into: slow)
        #expect(!slowTouch.ended(translation: CGSize(width: 2, height: 0),
                                 at: Self.wall.addingTimeInterval(0.4), into: slow))
        #expect(slow.duel?.game.active?.rotation == slowBefore, "0.4초 만에 뗀 손가락이 회전했다")
    }

    // MARK: - ② 입력 게이트 · 가속 경계 (순수 표 + 스토어)

    @Test("탑아웃이면 화면이 입력을 **안 보내고**, 보내도 엔진이 안 받는다")
    func topOutStopsInput() throws {
        // ⓐ 화면 게이트: 탑아웃한 판은 입력을 받지 않는다.
        let store = playingStore(game: Self.freeGame())
        #expect(chrome(store).acceptsInput, "판이 흐르는데 입력이 꺼져 있다 — 이 비교의 기준선이 헛돈다")
        store.myStats = TetrisDuelMyStats(lines: 3, attackSent: 1, pendingGarbage: 0, levelFloor: 1,
                                          toppedOut: true)
        #expect(!chrome(store).acceptsInput, "탑아웃인데 화면이 입력을 보낸다")

        // ⓑ 엔진 게이트(화면이 가드를 잊었을 때의 그물): 끝난 판은 걸음을 먹지 않는다.
        let over = playingStore(game: TetrisGame(seed: 7, board: TetrisGame.emptyBoard(),
                                                 active: TetrisGame.ActivePiece(piece: .t, column: 4, row: 24),
                                                 phase: .over(hold: 1)))
        let before = column(over)
        GamesTetrisDuelTouch.feed(.moveRight, into: over)
        GamesTetrisDuelTouch.feed(.softDrop, into: over)
        #expect(column(over) == before, "탑아웃한 판에서 조각이 움직였다")

        // ⓒ 준비·카운트다운·끝에서도 꺼져 있다(판이 흐르는 동안만 참이다).
        for phase in [TetrisDuelPhase.ready, .countdown] {
            let waiting = playingStore(game: Self.freeGame())
            waiting.phase = phase
            #expect(!chrome(waiting).acceptsInput, "\(phase) 에서 입력이 켜져 있다")
        }
        let finished = playingStore(game: Self.freeGame())
        finished.phase = .finished
        #expect(!chrome(finished, match: Self.match(finished: true, outcome: .won, reason: .topout,
                                                    delta: 4)).acceptsInput)
    }

    @Test("가속 표시는 **120초 경계**에서 선다 — 그 전엔 안 서고, 넘으면 레벨 10부터다(D7)")
    func speedUpAppearsAtTwoMinutes() throws {
        // 먼저 산식(D7): t<120 → 1 · 120 → 10 · 130 → 11 · 상한 28.
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: 119.999) == 1)
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: 120) == 10)
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: 130) == 11)
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: 10_000) == 28)

        // ★ 그리고 **판을 실제로 흘려** 경계를 넘긴다(표시는 `myStats.levelFloor` 가 정한다).
        let store = playingStore(game: Self.freeGame(), simulated: 119.5)
        store.tick(now: Self.base + 0.4)                       // 119.9초 — 아직 아니다
        #expect(store.myStats?.levelFloor == 1, "119.9초에 벌써 가속 바닥이 올랐다")
        #expect(!chrome(store).showsSpeedUp, "120초 전에 가속 표시가 섰다")

        store.tick(now: Self.base + 0.7)                       // 120.2초 — 여기서 선다
        #expect(store.myStats?.levelFloor == 10, "120초를 넘겼는데 바닥이 \(store.myStats?.levelFloor ?? -1) 이다")
        let crossed = chrome(store)
        #expect(crossed.showsSpeedUp, "120초를 넘겼는데 가속 표시가 안 섰다")
        #expect(crossed.speedLevel == 10)

        // 끝난 판에서는 내린다(그 자리에 결과가 선다).
        store.phase = .finished
        #expect(!chrome(store, match: Self.match(finished: true, outcome: .lost, reason: .topout)).showsSpeedUp)
    }

    @Test("판 시계: 흐르는 동안은 단조 시계 · **끝난 판은 엔진에 흘린 시간에서 멈춘다**")
    func theClockStopsWhenTheMatchEnds() {
        #expect(GamesTetrisDuelChrome.elapsedSeconds(stage: .playing, matchElapsed: 74.2, simulated: 74.0) == 74.2)
        // 끝난 판을 단조 시계로 재면 결과 화면에서도 경과가 자란다 — 엔진 시간에서 멈춰야 한다.
        #expect(GamesTetrisDuelChrome.elapsedSeconds(stage: .finished, matchElapsed: 300, simulated: 212) == 212)
        #expect(GamesTetrisDuelChrome.elapsedSeconds(stage: .countdown, matchElapsed: -2.4, simulated: 0) == 0)
        // 카운트다운 숫자는 올림이고 1 아래로 안 내려간다(0 을 보여 주면 '시작했는데 안 움직인다'가 된다).
        #expect(GamesTetrisDuelChrome.countdownDigit(remaining: 2.4) == 3)
        #expect(GamesTetrisDuelChrome.countdownDigit(remaining: 0.2) == 1)
        #expect(GamesTetrisDuelChrome.countdownDigit(remaining: nil) == 1)
        // 준비 남은 초: 마감을 모르면 서버 기본값 30.
        #expect(GamesTetrisDuelChrome.readySecondsLeft(deadline: nil, now: Self.wall) == 30)
        #expect(GamesTetrisDuelChrome.readySecondsLeft(deadline: Self.wall.addingTimeInterval(23.2),
                                                       now: Self.wall) == 24)
        #expect(GamesTetrisDuelChrome.readySecondsLeft(deadline: Self.wall.addingTimeInterval(-5),
                                                       now: Self.wall) == 0)
    }

    @Test("상대 줄: 침묵 5초면 '상대 연결 확인 중' · 준비 전과 끝난 판은 침묵이 아니다")
    func opponentPresenceLine() {
        let ready = TetrisDuelOpponentBoard(cells: TetrisDuelOpponentBoard.emptyCells, hasBoard: true, lines: 4,
                                            attackSent: 2, pending: 1, toppedOut: false, ready: true)
        #expect(GamesTetrisDuelChrome.opponentIsSilent(silenceSeconds: 4.9, opponentReady: true, stage: .playing)
                == false)
        #expect(GamesTetrisDuelChrome.opponentIsSilent(silenceSeconds: 5.0, opponentReady: true, stage: .playing))
        // 아직 준비 전인 상대는 침묵이 아니다 — 그때는 "들어오는 중" 이라고 말해야 한다.
        #expect(!GamesTetrisDuelChrome.opponentIsSilent(silenceSeconds: 30, opponentReady: false, stage: .waiting))
        #expect(!GamesTetrisDuelChrome.opponentIsSilent(silenceSeconds: 30, opponentReady: true, stage: .finished))

        #expect(GamesTetrisDuelChrome.opponentStatus(board: ready, stage: .playing) == TetrisPhoneText.playingNow)
        #expect(GamesTetrisDuelChrome.opponentStatus(board: ready, stage: .waiting) == TetrisPhoneText.ready)
        #expect(GamesTetrisDuelChrome.opponentStatus(board: ready, stage: .finished)
                == TetrisPhoneText.finishedPresence)
        #expect(GamesTetrisDuelChrome.opponentStatus(board: .empty, stage: .waiting) == TetrisPhoneText.notReady)
        let dead = TetrisDuelOpponentBoard(cells: TetrisDuelOpponentBoard.emptyCells, hasBoard: true, lines: 0,
                                           attackSent: 0, pending: 0, toppedOut: true, ready: true)
        #expect(GamesTetrisDuelChrome.opponentStatus(board: dead, stage: .playing)
                == TetrisPhoneText.toppedOutTitle)
    }

    // MARK: - ③ 결과 카드 (사유·루비가 state 와 맞는다)

    @Test("결과 카드: 사유는 **코어 표**이고 루비는 서버 값 우선 · 없으면 승 +순이익 · 패 −판돈 · 무 0")
    func theResultCardMatchesTheServerState() {
        // 서버가 말한 루비가 있으면 그것이 답이다(수수료 식이 서버에서 바뀌어도 화면이 안 거짓말한다).
        let given = GamesTetrisDuelChrome.result(Self.match(stake: 10, finished: true, outcome: .won,
                                                            reason: .topout, delta: 18))
        #expect(given.title == "이겼어요")
        #expect(given.reason == "상대가 꼭대기까지 쌓였어요")
        #expect(given.rubyDelta == 18 && given.rubyDeltaText == "+18")
        #expect(given.tone == .good && !given.isDraw)

        // 없으면 같은 식으로 센다: 3 → +2 · 5 → +4 · 10 → +8(`DuelFee.winnerNet`).
        for stake in [3, 5, 10] {
            let won = GamesTetrisDuelChrome.result(Self.match(stake: stake, finished: true, outcome: .won,
                                                              reason: .resign, delta: nil))
            #expect(won.rubyDelta == DuelFee.winnerNet(stake: stake), "판돈 \(stake) 승리 순이익이 틀렸다")
            #expect(won.reason == "상대가 기권했어요")
            let lost = GamesTetrisDuelChrome.result(Self.match(stake: stake, finished: true, outcome: .lost,
                                                               reason: .resign, delta: nil))
            #expect(lost.rubyDelta == -stake && lost.rubyDeltaText == "-\(stake)")
            #expect(lost.title == "졌어요" && lost.reason == "기권했어요" && lost.tone == .bad)
        }

        // 사유 다섯 × 내 기준(승자면 주어가 '상대'). **코어 표와 글자가 같아야 한다** — 두 벌로 쓰면 맥과 갈린다.
        let cases: [(TetrisDuelEndReason, TetrisDuelOutcome?, Int)] = [
            (.topout, .lost, -5), (.resign, .won, 4), (.disconnect, .won, 4), (.disconnect, .lost, -5),
            (.disconnect, .draw, 0), (.timeCap, .draw, 0), (.noShow, .draw, 0), (.abandoned, .won, 4)
        ]
        for (reason, outcome, delta) in cases {
            let result = GamesTetrisDuelChrome.result(Self.match(finished: true, outcome: outcome,
                                                                 reason: reason, delta: nil))
            #expect(result.reason == TetrisDuelNoticeText.endReason(reason, outcome: outcome),
                    "\(reason) 사유가 코어 표와 다르다")
            #expect(result.rubyDelta == delta, "\(reason)/\(String(describing: outcome)) 루비가 \(result.rubyDelta) 다")
            #expect(result.title == TetrisPhoneText.outcomeTitle(outcome))
        }
        // 무승부는 회색이고 0 이다(±0 을 '+0' 으로 쓰면 받은 것처럼 읽힌다).
        let draw = GamesTetrisDuelChrome.result(Self.match(finished: true, outcome: .draw, reason: .timeCap))
        #expect(draw.isDraw && draw.tone == .quiet && draw.rubyDeltaText == "0")
        #expect(draw.reason == "시간 초과 — 판돈을 돌려받았어요")
    }

    @Test("끝난 판은 결과를 들고 흐르는 판은 안 든다 · 덮개는 준비·카운트다운·탑아웃·결과에만 선다")
    func theChromeKnowsWhenTheMatchIsOver() {
        let live = playingStore(game: Self.freeGame())
        let liveChrome = chrome(live)
        #expect(liveChrome.result == nil && liveChrome.stage == .playing)
        #expect(!liveChrome.showsBoardOverlay, "판이 흐르는데 덮개가 선다")
        #expect(liveChrome.canResign, "흐르는 판에서 기권을 못 한다")

        // 서버가 닫은 판은 **phase 가 아직 playing 이어도** 끝난 판이다(응답이 먼저 닿는 쪽이 이긴다).
        let closed = chrome(live, match: Self.match(finished: true, outcome: .won, reason: .topout, delta: 4))
        #expect(closed.stage == .finished && closed.result != nil)
        #expect(!closed.canResign, "끝난 판에 기권 버튼이 남았다")
        #expect(!closed.showsLeaveWarning, "끝난 판에 '나가면 져요' 가 남았다")
        #expect(closed.showsBoardOverlay)

        // 카운트다운 중에도 기권은 된다(서버가 받는다 — 판돈은 수락 때 이미 걷혔다).
        let countdown = playingStore(game: Self.freeGame())
        countdown.phase = .countdown
        #expect(chrome(countdown).canResign, "카운트다운 중에 기권이 막혔다")
        #expect(chrome(countdown).showsBoardOverlay)
    }

    // MARK: - ★ 판 중 경고 (P7)

    @Test("★ '판 중에 앱을 나가면 져요' 가 **판 화면에 있다** — 규칙 시트에만 두면 안 된다")
    func theLeaveWarningLivesOnTheBoardScreen() throws {
        // ① 문구가 **경고**다(맥은 같은 자리에서 "창을 가리거나 내려도 판은 계속 흘러가요" 로 안심시킨다 —
        //    폰에 그 말을 옮기면 거짓말이다. 앱이 멈추면 판 루프가 멎고 서버가 15초 침묵에 그쪽 패로 닫는다).
        #expect(TetrisPhoneText.leaveWarning == "판 중에 앱을 나가면 져요")
        #expect(TetrisPhoneText.leaveWarning.contains("져요"), "이 자리는 안심이 아니라 경고다")

        // ② 흐르는 판·준비·카운트다운에서 **늘** 보인다. 끝난 판에서만 내린다.
        for phase in [TetrisDuelPhase.ready, .countdown, .playing] {
            let store = playingStore(game: Self.freeGame())
            store.phase = phase
            #expect(chrome(store).showsLeaveWarning, "\(phase) 에서 경고가 사라졌다")
        }

        // ③ 그리고 판 화면이 **실제로 그 글자를 그린다**(값만 참이고 화면에 없으면 아무것도 막지 못한다).
        let code = try IntegrationContractTests.code(Self.matchPath)
        #expect(code.contains("TetrisPhoneText.leaveWarning"), "판 화면이 경고 문구를 안 그린다")
        #expect(code.contains("if chrome.showsLeaveWarning"), "경고를 그리는 조건이 표를 안 지난다")
        // 규칙 시트(로비 레인)에만 있는 글자가 아니라는 것 — 이 파일 안에 있다는 것이 그 증거다.
        #expect(code.contains("exclamationmark.triangle.fill"), "경고에 눈에 걸리는 기호가 없다")
    }

    @Test("판을 멈추거나 시계를 되감는 길이 **없다**(D10) · 따라잡기 상한은 코어가 30초로 쥔다")
    func theBoardNeverPausesOrRewinds() throws {
        let code = try IntegrationContractTests.code(Self.matchPath)
        // 판을 멈추는 길(일시정지·시계 되감기)을 화면이 만들지 않는다.
        for banned in ["pause()", "store.tetris.duel =", "tetris.duel =", "startAt =", "simulated ="] {
            #expect(!code.contains(banned), "화면이 판 시계를 건드린다: \(banned)")
        }
        // ★ 그리고 코어의 사실을 되묻는다(이 숫자가 바뀌면 경고 문구의 근거가 바뀐다):
        //   앱이 멈췄다 돌아오면 따라잡기는 **30초까지만** 돌고 그 너머는 버린다.
        #expect(TetrisDuelSession.maxCatchUpSeconds == 30)
        var session = TetrisDuelSession(seed: 7, startedGame: Self.freeGame(), startAt: 0, simulated: 0)
        session.advance(to: 100)                      // 100초 만에 돌아왔다
        #expect(session.droppedSeconds == 70, "버린 시간이 \(session.droppedSeconds)초다 — 상한 30초가 아니다")
        #expect(session.simulated >= 100 - 0.001, "판 시계가 지금보다 뒤에 서 있다(되감겼다)")
    }

    // MARK: - 기권은 확인 뒤에만

    @Test("기권: 버튼은 **확인 시트만 띄우고**, RPC 를 부르는 자리는 그 시트의 [기권하기] 하나뿐이다")
    func resignNeedsASecondTap() throws {
        let code = try IntegrationContractTests.code(Self.matchPath)
        // ① RPC 를 부르는 자리가 **하나**다.
        #expect(code.components(separatedBy: "tetris.resign()").count - 1 == 1,
                "기권 RPC 호출 자리가 하나가 아니다")
        // ② 그 하나는 확인 시트의 onConfirm 안이다(시트 블록 뒤에 온다).
        let sheet = try #require(code.range(of: "AingConfirmSheet("))
        let call = try #require(code.range(of: "await tetris.resign()"))
        #expect(sheet.lowerBound < call.lowerBound, "기권 RPC 가 확인 시트 밖에서 나간다")
        // ③ 버튼이 하는 일은 깃발 세우기뿐이다.
        #expect(code.contains("confirmsResign = true"), "기권 버튼이 확인을 안 받는다")
        // ④ 확인창이 아니라 **불투명 시트**다(iOS 26 에서 확인 대화상자는 위쪽 말풍선으로 떠 [계속하기]가 가렸다).
        for banned in ["confirmationDialog", "alert("] {
            #expect(!code.contains(banned), "확인을 \(banned) 로 받는다 — 공용 시트만 쓴다")
        }
        // ⑤ 문구 넷이 표에서 온다.
        #expect(code.contains("TetrisPhoneText.resignConfirmTitle") && code.contains("TetrisPhoneText.resignWarning")
                && code.contains("TetrisPhoneText.confirmResign") && code.contains("TetrisPhoneText.keepPlaying"))
        #expect(TetrisPhoneText.resignWarning.contains("판돈"), "확인 본문이 무엇을 잃는지 말하지 않는다")
        // ⑥ 조작 버튼 셋에는 확인이 **없다**(락딜레이 0.16초가 그 예산 전부다 — 바로 내리기에도 넣지 마라).
        #expect(code.contains("tetris.hardDrop()") && code.components(separatedBy: "AingConfirmSheet(").count - 1 == 1)
    }

    // MARK: - 조작 셋 · 캔버스 계약

    @Test("조작 셋은 **코어 문 셋**으로만 엔진을 민다 · 버튼 셋은 솔로와 같고 글자는 규칙 표와 묶여 있다")
    func theControlsUseTheCoreDoors() throws {
        let code = try IntegrationContractTests.code(Self.matchPath)
        // 걸음 셋 → 코어 문 셋. `setLeftHeld` 류로 흉내 내지 않는다(P9).
        #expect(code.contains("case .moveLeft: store.moveLeftOneCell()"))
        #expect(code.contains("case .moveRight: store.moveRightOneCell()"))
        #expect(code.contains("case .softDrop: store.softDropOneCell()"))
        for banned in ["setLeftHeld", "setRightHeld", "setSoftDropHeld"] {
            #expect(!code.contains(banned), "화면이 눌림으로 이동을 흉내 낸다: \(banned)")
        }
        // 버튼 셋 = 홀드 · 반대로 · 바로 내리기(하드드롭에는 **제스처가 없다** — 오인식 한 번이 판 종료다).
        #expect(code.contains("tetris.hold()") && code.contains("tetris.rotate(clockwise: false)"))
        #expect(code.contains("TetrisPhoneText.holdButton") && code.contains("TetrisPhoneText.rotateCounterButton")
                && code.contains("TetrisPhoneText.hardDropButton"))
        // 제스처가 부르는 것은 이동 셋과 **시계** 회전뿐이다.
        #expect(code.components(separatedBy: "rotate(clockwise: true)").count - 1 == 2,
                "시계 회전 자리가 둘(탭 · 보이스오버 기본 액션)이 아니다")
        // 버튼 글자와 규칙 표의 꺾쇠 안 말이 **같다**(한쪽만 고치면 규칙과 버튼이 다른 이름을 부른다).
        let bracketed = TetrisPhoneText.controls.map(\.gesture).filter { $0.hasPrefix("[") }
        #expect(bracketed == ["[" + TetrisPhoneText.holdButton + "]",
                              "[" + TetrisPhoneText.rotateCounterButton + "]",
                              "[" + TetrisPhoneText.hardDropButton + "]"],
                "버튼 글자가 규칙 표와 갈렸다: \(bracketed)")
        // 보이스오버 이동 액션은 **솔로와 같은 표**를 쓴다(같은 조작을 두 이름으로 부르지 않는다).
        #expect(code.contains("GamesMiniGameText.tetrisMoveLeft") && code.contains("GamesMiniGameText.tetrisMoveRight")
                && code.contains("GamesMiniGameText.tetrisSoftDrop"))
        // 버튼이 이미 있는 조작은 액션으로 **중복시키지 않는다**.
        for banned in ["GamesMiniGameText.tetrisHold", "GamesMiniGameText.tetrisHardDrop"] {
            #expect(!code.contains(banned), "버튼에 있는 조작을 보이스오버 액션에 또 뒀다: \(banned)")
        }
    }

    @Test("판을 읽는 자리는 `TimelineView` 안 하나뿐이고, 프레임 루프는 **화면이 보일 때만** 돈다")
    func theBoardIsReadOnlyInsideTheTimeline() throws {
        let code = try IntegrationContractTests.code(Self.matchPath)
        // 판(`duel.game`)을 읽는 자리: 잎 안의 한 번 + 보이스오버 알림 둘 + 홀드 소진 하나.
        // ★ 핵심은 **본문 배치에서 안 읽는다**는 것 — 관찰 대상이 아니라 프레임마다 바뀌는 값이다.
        #expect(code.contains("let game = tetris.duel?.game ?? Self.placeholder"))
        // ★ `paused: !live` 만 찾으면 **경과 시계 잎**의 같은 글자에 가려 판 루프의 멈춤 조건이 사라져도 초록이다
        //    (뮤테이션 실측에서 살아남았다). 그래서 판 루프의 **그 한 줄 전체**를 공백을 접어 재고,
        //    글자 수(넷)로 잎들까지 함께 센다.
        let flat = code.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        #expect(flat.contains("minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz), "
                              + "paused: !live)"), "판 프레임 루프에 멈춤 조건이 없다")
        #expect(code.components(separatedBy: "paused: ").count - 1 == 4, "멈춤 조건이 잎 넷에 다 있지 않다")
        #expect(code.contains("tetris.isWindowVisible && (chrome.stage == .countdown || chrome.stage == .playing)"),
                "화면이 안 보이는데도 프레임 루프가 돈다")
        #expect(code.components(separatedBy: "TimelineView(").count - 1 == 4,
                "TimelineView 가 넷(판 · 경과 · 준비 · 상대)이 아니다")
        #expect(code.contains("tetris.tick()"), "프레임마다 판을 지금까지 밀지 않는다")
        // 제스처는 **한 자리**다(모디파이어를 갈라 붙이면 뷰 정체성이 갈려 진행 중인 끌기가 끊긴다).
        #expect(code.components(separatedBy: ".gesture(boardDrag(").count - 1 == 1)
        // 화면을 떠나거나 앱이 내려가면 눌린 것을 놓는다.
        #expect(code.components(separatedBy: "tetris.releaseAllKeys()").count - 1 == 2,
                "화면 사라짐·앱 내려감 둘 다에서 키를 놓지 않는다")
        #expect(code.contains("touch.reset()"))
    }

    @Test("캔버스는 **그림만** 그린다 — 입력·시계·배치 복제본이 없고 금지 연출도 없다")
    func theDuelCanvasOnlyDraws() throws {
        let canvas = try IntegrationContractTests.code(Self.canvasPath)
        // 판·미니 판은 **코어 painter 한 벌**이 그린다(방해 줄 회색·미터가 그 안에 있다).
        #expect(canvas.contains("TetrisBoardPainter.drawGame(game, into: &canvas, size: size, reduceMotion: reduceMotion)"))
        #expect(canvas.contains("TetrisBoardPainter.drawMiniBoard(cells, into: &canvas, size: size, cell: Self.cell)"))
        // 미터·회색을 **직접 칠하지 않는다**(painter 가 `garbageMask` 로 가른다).
        for banned in ["drawMeter", "garbageMask", "isGarbage", "meterRect", "TetrisDuelPalette.garbageColor"] {
            #expect(!canvas.contains(banned), "캔버스가 방해 줄·미터를 직접 칠한다: \(banned)")
        }
        // 배치·색은 코어 표 한 벌이다.
        #expect(canvas.contains("TetrisLayout.") && canvas.contains("TetrisMiniBoardLayout.boardSize(cell: cell)"))
        // 셀 수는 표가 쥔다 — 캔버스가 숫자를 다시 적으면 둘이 갈린다.
        #expect(canvas.contains("GamesTetrisDuelChrome.miniBoardCell"), "캔버스가 미니 판 셀을 표에서 안 읽는다")
        #expect(!canvas.contains("cell: CGFloat = "), "캔버스가 셀 수를 다시 적었다")
        for banned in ["struct TetrisLayout", "enum TetrisLayout", "struct TetrisPalette", "enum TetrisPalette",
                       "struct TetrisMiniBoardLayout"] {
            #expect(!canvas.contains(banned), "폰 전용 배치·색 표를 새로 만들었다: \(banned)")
        }
        // 입력·프레임 루프·스토어는 여기 없다.
        for banned in ["store.", "TimelineView", "Timer", "CACurrentMediaTime", "1.0 / 60.0", "setLeftHeld",
                       "softDropOneCell", "TetrisGestureTracker", "DragGesture"] {
            #expect(!canvas.contains(banned), "캔버스가 그림 밖의 일을 한다: \(banned)")
        }
        // 60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다(솔로·맥과 같은 금지 셋).
        for banned in ["addFilter", "drawLayer", ".blur(", "repeatForever"] {
            #expect(!canvas.contains(banned), "캔버스에 금지 연출이 들어갔다: \(banned)")
        }
        // 글꼴은 배율을 곱하고(폰 관용구), 8·9pt 캡션은 쓰지 않는다(iOS 캡션 하한 10pt).
        // ⚠️ "* scale" 만 세면 "14 * t.scale" 은 사이에 `t.` 가 있어 안 걸린다 — 솔로 계약과 같게 **둘 다** 센다.
        #expect(canvas.components(separatedBy: "* t.scale").count - 1 == 7)
        #expect(canvas.components(separatedBy: "* scale").count - 1 == 4)
        #expect(!canvas.contains("size: 8") && !canvas.contains("size: 9"))
        // 값 자리는 자기설명형이고 문구는 표에서 온다.
        #expect(canvas.contains("TetrisPhoneText.levelValue(game.difficultyLevel)"))
        #expect(canvas.contains("TetrisPhoneText.linesValue(game.lines)"))
        #expect(TetrisPhoneText.levelValue(7) == "Lv 7" && TetrisPhoneText.linesValue(12) == "12줄")
        #expect(TetrisPhoneText.incomingLines(3) == "들어올 줄 3")
    }

    // MARK: - 상대 미니 판 (셀 값 · 대비)

    @Test("상대 미니 판: 셀 **5pt** · 세로가 폰 머리글에 들어간다 · 가비지 회색이 우물 대비 3:1 을 넘는다")
    func theMiniBoardFitsAndReads() {
        // ① 셀은 4~6 사이에서 고른 5다. 맥 기본 9pt 는 세로 184pt 라 폰 머리글에 안 들어간다.
        #expect(TetrisMiniBoardLayout.cell == 9, "맥 기본값이 바뀌었다 — 폰 값을 고른 근거(184pt)가 흔들린다")
        #expect(TetrisMiniBoardLayout.boardSize(cell: 9).height == 184)
        // ★ **화면이 쓰는 그 상수**를 읽는다. 5 를 여기 다시 적으면 상수를 9 로 되돌린 뮤테이션이 살아남는다(실측).
        let cell = GamesTetrisDuelChrome.miniBoardCell
        #expect(cell == 5, "미니 판 셀이 \(cell)pt 다")
        #expect((4...6).contains(cell), "4~6 밖의 셀은 칸 모양이나 판 폭 둘 중 하나를 깨뜨린다")
        let size = TetrisMiniBoardLayout.boardSize(cell: cell)
        #expect(size == CGSize(width: 54, height: 104), "미니 판 크기가 \(size) 다")
        // 머리글 예산: SE(375×667)에서 쓸 세로가 554pt 이고 판·조작 줄·경고 줄이 그 안에 다 서야 한다.
        // 미니 판이 이 선을 넘으면 판이 300pt 아래로 깎여 조작 감도가 솔로와 크게 갈린다(P11).
        #expect(size.height <= GamesTetrisDuelChrome.miniBoardHeightBudget,
                "미니 판이 머리글 예산(\(GamesTetrisDuelChrome.miniBoardHeightBudget)pt)을 넘는다")

        // ② 가비지 회색 대비 — **실제 색 값으로** 센다(눈으로 '회색이네' 하고 넘기면 안 되는 자리다).
        let contrast = Self.contrastRatio(TetrisDuelPalette.garbageRGB, TetrisDuelPalette.miniWellRGB)
        #expect(contrast >= 3, "가비지 회색이 미니 우물 위에서 \(contrast):1 이다 — 3:1 아래다")
        // 기준선이 다르다: 같은 식으로 잰 **어두운 조각**(J 파랑)은 이 우물 위에서 훨씬 낮다.
        let piece = Self.contrastRatio((r: 0.29, g: 0.42, b: 0.95), TetrisDuelPalette.miniWellRGB)
        #expect(piece < contrast, "이 측정이 모든 색을 통과시킨다 — 기준선이 헛돈다")
    }

    /// WCAG 상대 휘도 대비(소수 둘째 자리까지). 순수 계산 — 색 표가 바뀌면 이 수가 바뀐다.
    private nonisolated static func contrastRatio(_ a: (r: Double, g: Double, b: Double),
                                                  _ b: (r: Double, g: Double, b: Double)) -> Double {
        func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        let first = luminance(a)
        let second = luminance(b)
        let ratio = (max(first, second) + 0.05) / (min(first, second) + 0.05)
        return (ratio * 100).rounded() / 100
    }

    @Test("미니 판은 **위쪽 상대 줄 안**이다 — 내 판 옆에 세우지 않는다(P11: 캔버스 폭이 곧 조작 감도)")
    func theMiniBoardStandsInTheOpponentRow() throws {
        let code = try IntegrationContractTests.code(Self.matchPath)
        // 미니 판을 그리는 자리는 상대 줄 하나다.
        #expect(code.components(separatedBy: "GamesTetrisDuelMiniBoard(cells:").count - 1 == 1)
        // 내 판은 **남은 세로를 aspect-fit** 으로 먹는다(옆에 아무것도 세우지 않는다).
        #expect(code.contains("aspectRatio(TetrisLayout.logicalSize.width / TetrisLayout.logicalSize.height, contentMode: .fit)"))
        // 한 칸 문턱은 **그려진 배율**에서 온다(한 출처 — 논리 13 × 배율).
        #expect(code.contains("touch.updateCellWidth(TetrisLayout.cell * resolved)"))
        #expect(code.contains("min(box.size.width / TetrisLayout.logicalSize.width,"))
        // 문턱 계산이 실제로 옳은가: 셀 20pt 문턱이면 20pt 끌기가 한 칸이다(위 ① 테스트가 그 결과를 잰다).
        let touch = GamesTetrisDuelTouch(cellWidth: TetrisLayout.cell)
        touch.updateCellWidth(TetrisLayout.cell * 1.1747)      // SE 배율
        #expect(TetrisLayout.cell * 1.1747 > 15, "SE 배율에서 한 칸 문턱이 15pt 아래다")
    }
}
