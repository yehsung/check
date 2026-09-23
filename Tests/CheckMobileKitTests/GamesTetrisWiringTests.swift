@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

/// v0.3.38 폰 테트리스 **배선** — 손가락 → 구동기 → 엔진, 그리고 판이 끝나는 자리(뒤로가기·background·판 상한)와
/// 제출 인편. 화면(`#if os(iOS)`)은 macOS 에서 컴파일되지 않으므로 **모양은 소스 계약으로** 잰다.
///
/// 이 파일이 지키려는 것은 이 저장소가 실제로 데인 자리들이다:
///   · `interrupt()` 뒤에는 tick 이 안 온다 — 끝내는 자리에서 직접 알리지 않으면 점수가 **조용히 사라진다.**
///   · 제출 성공 갈래의 `submitNotice = nil` 이 출구에서 세운 안내를 지운다.
///   · 순위 재조회가 `activeKind == kind` 에 막혀 뒤로가기로 끝낸 판이 순위에 안 비친다.
///   · `token_used` 를 거절로 그리면 **이미 올라간 점수**를 못 올렸다고 말한다.
@MainActor
@Suite(.serialized) struct GamesTetrisWiringTests {
    // MARK: - 도우미

    private static let boardJSON = #"[{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":40,"best_at":"2026-09-23T04:00:00Z","plays":3,"center":"seoul"}]"#

    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`). 스위트 인스턴스는 테스트마다 새로 생기므로
    /// 이 값은 테스트 하나 안에서만 공유된다.
    private let waits = GamesWaitBudget()

    /// 1·10열이 빈 평평한 더미. advance 930 = 레벨 28(리셋 한도 2 · 재충전 없음 · 20G).
    /// 맥 규칙 테스트(`V0338TetrisRulesTests` 의 `level28Stack`)와 **같은 판**이다 — 같은 성질을 폰 배선에서 잰다.
    private static let level28Stack = [
        ".########.",
        ".########.",
        ".########.",
        ".########.",
        ".########.",
        ".########."
    ]

    private func configure(_ harness: GamesHarness, submit: String = #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#) {
        harness.server.setDefault("minigame_board", json: Self.boardJSON)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_submit_score", json: submit)
    }

    /// 시작된 테트리스 구동기 하나(화면 없이). 셀 폭은 실기 근사값 20pt.
    private func startedTetris(seed: UInt64 = 7, cellWidth: CGFloat = 20) -> GamesPlayController {
        let controller = GamesPlayController(kind: .tetris, seed: seed)
        controller.updateCellWidth(cellWidth)
        controller.tap()
        return controller
    }

    /// 조각이 차지한 가장 왼쪽 열(조각 원점이 아니라 **실제 칸**이라 조각 종류에 안 흔들린다).
    private func leftmostColumn(_ controller: GamesPlayController) -> Int? {
        controller.tetris.active?.cells.map { $0.column }.min()
    }

    // MARK: - 손가락 → 조각

    @Test("가로 끌기: 문턱을 넘은 배수만큼 **정확히 그만큼** 옆으로 간다(엔진 무수정 배선)")
    func draggingSidewaysMovesExactlyThatManyCells() throws {
        let controller = startedTetris()
        let before = try #require(leftmostColumn(controller))
        let start = CGPoint(x: 120, y: 200)
        // 셀 폭 20 × 2칸 = 40pt. 스폰 왼쪽 끝은 3열이라(어떤 조각이든) 왼쪽으로 **3칸까지만** 벽에 안 닿는다 —
        // 그래서 2칸 + 1칸으로 나눠 잰다. 4칸을 재면 벽에 막힌 것을 배선 결함으로 오해한다.
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: -40, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before - 2, "끌기 2칸이 \(before) → \(leftmostColumn(controller) ?? -1) 로 갔다")

        // 누적값이다 — 같은 손가락이 한 칸 더 가면 **한 칸만** 더 난다(두 칸이 아니다).
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: -60, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before - 3)

        // ★ 기준선이 다르다: 문턱 미만은 아무 일도 없다(이게 없으면 위 단언이 "늘 움직인다"와 구별이 안 된다).
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: -75, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before - 3, "문턱(20pt) 미만인데 칸이 움직였다")
        #expect(before == 3, "스폰 왼쪽 끝이 3열이 아니다 — 위 '벽까지 3칸' 전제가 깨졌다")
    }

    @Test("세로 끌기: 칸마다 한 칸 내려가고 **칸당 1점**이다(순위표는 맥과 한 표다)")
    func draggingDownSoftDropsAndScores() throws {
        let controller = startedTetris()
        let row = try #require(controller.tetris.active?.row)
        #expect(controller.tetris.score == 0)
        controller.canvasDragChanged(startLocation: .zero, translation: CGSize(width: 0, height: 60), at: Date())
        #expect(controller.tetris.active?.row == row + 3)
        #expect(controller.tetris.score == 3, "소프트드롭 점수가 폰에서만 빠졌다 — 맥과 한 순위표다")
        // 걸음에는 햅틱 serial 이 없다(L1 초당 56회 · L5 초당 213회 — 탭틱이 낼 수 없는 속도다).
        #expect(controller.tapSerial == 1, "이동·소프트드롭이 탭 serial 을 올렸다(시작 탭 1회만이어야 한다)")
    }

    @Test("캔버스 탭 = **시계 회전**(하드드롭이 아니다) · 걸음을 낸 끌기는 탭이 아니다")
    func aShortTapRotatesClockwise() throws {
        let controller = startedTetris()
        let before = try #require(controller.tetris.active?.rotation)
        let now = Date()
        controller.canvasDragChanged(startLocation: .zero, translation: .zero, at: now)
        let rotated = controller.canvasDragEnded(translation: CGSize(width: 2, height: 1), at: now.addingTimeInterval(0.1))
        #expect(rotated)
        #expect(controller.tetris.active?.rotation != before, "판 위 탭이 회전을 안 했다")
        // 맥은 같은 입력이 하드드롭이다 — 폰에서 그러면 조각을 돌리려던 손가락이 판을 끝낸다.
        #expect(controller.tetris.phase == .running)
        #expect(controller.hardDropSerial == 0, "캔버스 탭이 하드드롭으로 갔다")

        // ★ 기준선: 걸음을 낸 끌기는 탭이 아니다.
        let after = try #require(controller.tetris.active?.rotation)
        let drag = Date()
        controller.canvasDragChanged(startLocation: CGPoint(x: 9, y: 9), translation: CGSize(width: -60, height: 0), at: drag)
        let tapped = controller.canvasDragEnded(translation: CGSize(width: -60, height: 0), at: drag.addingTimeInterval(0.1))
        #expect(!tapped)
        #expect(controller.tetris.active?.rotation == after, "이동 끌기가 회전까지 했다")
    }

    @Test("취소된 끌기의 잠금·소비량이 다음 접촉으로 새지 않는다(없는 입력을 만들지 않는다)")
    func aCancelledDragDoesNotLeakIntoTheNext() throws {
        let controller = startedTetris()
        controller.canvasDragChanged(startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: -60, height: 0), at: Date())
        let moved = try #require(leftmostColumn(controller))
        // `onEnded` 가 안 왔다(시스템 제스처로 취소). 새 손가락은 translation 이 0 부터다.
        controller.canvasDragChanged(startLocation: CGPoint(x: 40, y: 300), translation: .zero, at: Date())
        #expect(leftmostColumn(controller) == moved, "손도 안 댄 이동이 만들어졌다 — 입력 상실보다 나쁜 입력 날조다")
    }

    // MARK: - 가로 걸음(양쪽 대칭 · 배선을 실제로 지난다)

    @Test("가로 한 걸음은 **양쪽 대칭**이다 — 오른쪽도 정확히 한 칸이고, 쌍이 끝나면 자동 반복이 안 남는다")
    func theSidewaysStepIsSymmetricAndLeavesNoRepeat() throws {
        // ⚠️ 이 테스트는 **배선을 실제로 지난다**(`moveRightOneCell()` → `feed(.moveRight)` → 엔진 쌍).
        //    엔진을 직접 부르는 계약 테스트(`aPressReleasePairMovesExactlyOneCellAndArmsNoRepeat`)는 `feed` 를
        //    한 번도 안 지나므로, 그 갈래를 통째로 `break` 로 무력화해도 초록이었다(뮤테이션 실측 · 빠른 게이트 63건).
        for direction in [-1, 1] {
            let controller = startedTetris()
            let start = try #require(leftmostColumn(controller))

            // ① 한 걸음 = 정확히 한 칸.
            if direction < 0 { controller.moveLeftOneCell() } else { controller.moveRightOneCell() }
            #expect(leftmostColumn(controller) == start + direction,
                    "\(direction < 0 ? "왼쪽" : "오른쪽") 한 걸음이 \(start) → \(leftmostColumn(controller) ?? -99) 로 갔다")

            // ② 두 걸음 = 정확히 두 칸(쌓이지도, 한 칸으로 접히지도 않는다).
            //    ⚠️ 세 걸음이 아닌 이유: 스폰 왼쪽 끝이 3열이라 왼쪽 세 걸음이면 **벽**이고, 그러면 아래 기준선
            //    (누른 채 두면 더 간다)이 벽에 막혀 헛돈다.
            direction < 0 ? controller.moveLeftOneCell() : controller.moveRightOneCell()
            let afterTwo = try #require(leftmostColumn(controller))
            #expect(afterTwo == start + 2 * direction, "두 걸음이 \(start) → \(afterTwo) 로 갔다")

            // ③ ★ **뗌**이 이 단언의 표적이다. `setXHeld(false)` 를 지우면 ①②는 그대로 초록인데(누름이 즉시 한 칸을
            //    준다) 자동 반복이 살아남아, 손을 뗀 뒤 DAS(0.167초)가 만기되며 조각이 **혼자 벽까지 흐른다.**
            let window = TetrisGame.dasSeconds * 2
            let frames = Int((window / TetrisGame.maxStep).rounded(.up)) + 1
            gamesDrive(controller, from: MobileClock.demoInstant, frames: frames, dt: TetrisGame.maxStep)
            #expect(leftmostColumn(controller) == afterTwo,
                    "걸음이 끝났는데 자동 반복이 살아남아 \(leftmostColumn(controller) ?? -99) 까지 흘렀다")

            // ★ 기준선이 다르다: **떼지 않으면** 같은 창에서 실제로 여러 칸이 간다(위 '안 흐른다'가 공허하지 않다).
            var held = controller.tetris
            if direction < 0 { held.setLeftHeld(true) } else { held.setRightHeld(true) }
            var elapsed = 0.0
            while elapsed < window {
                held.step(dt: TetrisGame.maxStep)
                elapsed += TetrisGame.maxStep
            }
            let heldColumn = held.active?.cells.map { $0.column }.min() ?? -99
            #expect(heldColumn != afterTwo,
                    "누른 채 둬도 안 움직인다(\(heldColumn)) — 이 비교의 기준선이 헛돈다(창이 DAS 보다 짧다)")
        }
    }

    @Test("가로 **끌기**도 양쪽 대칭이다 — 오른쪽으로 끈 만큼만 간다(왼쪽 단언의 거울)")
    func draggingRightMovesExactlyThatManyCells() throws {
        let controller = startedTetris()
        let before = try #require(leftmostColumn(controller))
        #expect(before == 3, "스폰 왼쪽 끝이 3열이 아니다 — 아래 '오른쪽으로 3칸' 전제가 깨졌다")
        let start = CGPoint(x: 120, y: 200)
        // 셀 폭 20 × 2칸. 오른쪽은 조각 폭(최대 4)까지 세도 3 + 2 + 4 = 9 열이라 벽에 안 닿는다.
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: 40, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before + 2, "오른쪽 끌기 2칸이 \(before) → \(leftmostColumn(controller) ?? -1) 로 갔다")

        // 누적값이다 — 같은 손가락이 한 칸 더 가면 한 칸만 더 난다.
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: 60, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before + 3)

        // ★ 기준선이 다르다: 문턱 미만은 아무 일도 없다.
        controller.canvasDragChanged(startLocation: start, translation: CGSize(width: 75, height: 0), at: Date())
        #expect(leftmostColumn(controller) == before + 3, "문턱(20pt) 미만인데 칸이 움직였다")

        // 그리고 되돌리면 되돌아온다(가로는 환불한다 — 손가락 위치가 곧 조각 위치).
        controller.canvasDragChanged(startLocation: start, translation: .zero, at: Date())
        #expect(leftmostColumn(controller) == before, "오른쪽으로 간 조각이 손가락을 되돌려도 안 돌아왔다")
    }

    @Test("폰 소프트드롭 걸음은 **접지 리셋 예산을 안 쓴다** — 폰에서만 칸마다 재충전되면 판 종료 보장이 무너진다")
    func thePhoneSoftDropStepNeverSpendsTheLockResetBudget() throws {
        // 지키는 것이 맥 타깃 1건(`softDropOneCellNeverSpendsTheLockResetBudget`)뿐이었다 — 폰 배선을 고치는 사람이
        // `CheckMobileKitTests` 만 돌리면 이 성질이 깨진 것을 못 본다. 그래서 **폰 배선을 지나는** 같은 측정을 둔다.
        //
        // L28: 리셋 한도 2 · 재충전 없음. 예산을 다 쓰면 **바닥에 닿는 순간 곧바로** 굳는다(락딜레이 0.205초를 못 쓴다).
        // 그래서 "닿은 직후 한 프레임 뒤에도 조각이 살아 있는가"가 곧 "예산이 남았는가"다.
        func fixture() -> TetrisGame {
            TetrisGame(seed: 11, board: TetrisGame.boardFixture(bottomRows: Self.level28Stack),
                       active: TetrisGame.ActivePiece(piece: .o, column: TetrisGame.spawnColumn,
                                                      row: TetrisGame.spawnRow),
                       advance: 930)
        }
        #expect(TetrisGame.lockResetLimit(forLevel: fixture().level) == 2, "리셋 한도 전제가 깨졌다")
        #expect(!TetrisGame.lockResetRefreshes(forLevel: fixture().level), "재충전이 켜져 있으면 이 측정이 헛돈다")

        /// 접지할 때까지 **폰 걸음으로만** 내린다. 반환값은 내려간 칸 수.
        func softDropToFloor(_ controller: GamesPlayController) -> Int {
            var cells = 0
            while !controller.tetris.isGrounded, cells < 40 {
                controller.softDropOneCell()
                cells += 1
            }
            return cells
        }

        // ① 손가락으로만 내렸다 — 예산을 한 번도 안 썼으므로 락딜레이를 그대로 받는다.
        let soft = GamesPlayController(kind: .tetris, seed: 11)
        soft.replaceForTesting(tetris: fixture())
        let cells = softDropToFloor(soft)
        #expect(cells >= 3, "\(cells)칸밖에 안 내려갔다 — 픽스처가 이미 바닥 근처다")
        #expect(soft.tetris.isGrounded)
        gamesDrive(soft, from: MobileClock.demoInstant, frames: 2, dt: 1.0 / 120.0)
        #expect(soft.tetris.active != nil, "소프트드롭 \(cells)칸이 리셋 예산을 썼다 — 닿자마자 굳었다")

        // ② ★ 기준선이 다르다: **가로 걸음 두 번**은 예산을 정말 쓴다(같은 배선·같은 자리인데 결과가 반대다).
        let shifted = GamesPlayController(kind: .tetris, seed: 11)
        shifted.replaceForTesting(tetris: fixture())
        shifted.moveLeftOneCell()
        shifted.moveRightOneCell()
        _ = softDropToFloor(shifted)
        #expect(shifted.tetris.isGrounded)
        gamesDrive(shifted, from: MobileClock.demoInstant, frames: 2, dt: 1.0 / 120.0)
        #expect(shifted.tetris.active == nil, "예산 2를 다 썼는데 안 굳었다 — 이 비교의 기준선이 헛돈다")
    }

    @Test("새 판은 **빈 트래커**로 시작한다 — 앞 끌기의 축 잠금·소비량이 첫 조각을 튀게 하지 않는다")
    func startingANewRoundClearsTheGestureTracker() throws {
        // ⚠️ `tap()` 의 `resetGesture()` 를 지워도 **69건 전부 초록**이었다(뮤테이션 실측) — 그 자리를 지키는
        //    테스트가 하나도 없었다. 여기가 그 자리다.
        let contact = CGPoint(x: 120, y: 200)
        let controller = startedTetris()
        // 진행 중 끌기: 오른쪽으로 두 칸(소비량 40pt). 축이 가로로 잠기고 트래커에 그 접촉이 남는다.
        controller.canvasDragChanged(startLocation: contact, translation: CGSize(width: 40, height: 0), at: Date())
        let moved = try #require(leftmostColumn(controller))
        #expect(moved == 5, "전제가 깨졌다 — 스폰 3열에서 오른쪽 두 칸이면 5열이다(\(moved))")

        // 판이 **이 손가락 아래에서** 끝났다(상한·탑아웃). `onEnded` 는 오지 않았다 —
        // 트래커에는 잠긴 축과 소비량 40pt 가 그대로 남아 있다.
        controller.replaceForTesting(tetris: TetrisGame(seed: 99))
        #expect(!controller.isPlaying)

        // 어느 경로로든 새 판이 켜졌다(화면 쪽 방어를 지나 온 탭 · 결과 카드의 [다시] · 보이스오버 액션).
        controller.tap()
        #expect(controller.isPlaying)
        let spawn = try #require(leftmostColumn(controller))

        // ★ 여기가 `resetGesture()` 다. 안 비우면 같은 시작점의 다음 `onChanged` 에서
        //   pending = 0 − 40 = −40 이 되어 **손도 안 댄 첫 조각이 곧장 두 칸 왼쪽으로 간다.**
        controller.canvasDragChanged(startLocation: contact, translation: .zero, at: Date())
        #expect(leftmostColumn(controller) == spawn,
                "새 판 첫 조각이 앞 끌기의 누적 이동으로 \(spawn) → \(leftmostColumn(controller) ?? -99) 로 튀었다")

        // ★ 기준선이 다르다: **같은 판 안**이라면 같은 입력이 실제로 두 칸을 만든다(위 단언이 공허하지 않다).
        let same = startedTetris()
        same.canvasDragChanged(startLocation: contact, translation: CGSize(width: 40, height: 0), at: Date())
        let there = try #require(leftmostColumn(same))
        same.canvasDragChanged(startLocation: contact, translation: .zero, at: Date())
        #expect(leftmostColumn(same) == there - 2,
                "같은 판 안에서도 안 움직인다 — 이 비교의 기준선이 헛돈다(트래커가 애초에 비어 있었다)")
    }

    // MARK: - 버튼 셋

    @Test("버튼: 반시계는 캔버스 탭과 **반대 방향** · 하드드롭은 굳힌다 · 소진된 홀드는 조용하다")
    func theThreeButtonsDoDifferentThings() throws {
        let controller = startedTetris()
        let spawn = try #require(controller.tetris.active?.rotation)
        controller.rotate(clockwise: false)
        #expect(controller.tetris.active?.rotation == spawn.counterClockwise, "버튼이 시계로 돌았다 — 폰에서 반시계가 사라진다")

        let holdSerial = controller.tapSerial
        controller.hold()
        #expect(controller.tetris.holdUsed)
        #expect(controller.tapSerial == holdSerial + 1)
        // 조각당 1회다 — 두 번째 누름은 엔진 no-op 이고 **serial 도 안 올린다**(소진된 홀드는 조용해야 한다).
        let spent = controller.tapSerial
        controller.hold()
        #expect(controller.tapSerial == spent, "소진된 홀드가 햅틱을 울렸다")

        controller.hardDrop()
        #expect(controller.hardDropSerial == 1)
        #expect(controller.tetris.active?.row ?? 0 <= TetrisGame.firstVisibleRow + 1, "하드드롭 뒤 새 조각이 위에서 시작하지 않았다")
        #expect(controller.tetris.score > 0, "하드드롭이 점수를 안 줬다")
    }

    // MARK: - 프레임 루프 **밖**의 햅틱(버튼 경로)

    @Test("[즉시 내리기]로 지운 줄도 묵직한 햅틱을 울린다 — 테트리스에서 제일 잦은 소거 경로다")
    func aHardDropClearIsCounted() throws {
        // 하드드롭은 락딜레이를 안 기다리고 **그 자리에서** 굳혀 줄을 지운다 — 프레임 루프 밖이라 `tick` 의 소거
        // 판정이 못 본다(다음 틱은 자기 `step` 직전 값을 기준으로 삼으므로 이미 오른 소거가 기준값에 들어간다).
        let controller = GamesPlayController(kind: .tetris, seed: 11)
        controller.replaceForTesting(tetris: TetrisGame(
            seed: 11, board: TetrisGame.boardFixture(bottomRows: ["########..", "########.."]),
            active: TetrisGame.ActivePiece(piece: .o, column: 7, row: TetrisGame.spawnRow)))
        // O 의 칸은 원점에서 dx 1·2 다 — 7열에 두면 8·9열(38·39행의 빈 두 칸)을 채운다.
        #expect(controller.lineClearSerial == 0)
        controller.hardDrop()
        #expect(controller.tetris.lastClear?.lines == 2, "전제가 깨졌다 — 이 하드드롭이 두 줄을 안 지웠다")
        #expect(controller.lineClearSerial == 1, "하드드롭 소거가 햅틱을 한 번도 안 울렸다")
        #expect(controller.hardDropSerial == 1)

        // ★ 기준선이 다르다: **소거 없는** 하드드롭은 묵직한 햅틱을 울리지 않는다(단단한 것만 울린다).
        let empty = GamesPlayController(kind: .tetris, seed: 11)
        empty.tap()
        empty.hardDrop()
        #expect(empty.hardDropSerial == 1)
        #expect(empty.lineClearSerial == 0, "소거가 0줄인 배치에 묵직한 햅틱이 울렸다")
    }

    @Test("홀드로 갈아탄 조각이 스폰에서 막혀 끝난 판도 게임오버 햅틱을 울린다")
    func aHoldThatBlocksOutIsCounted() throws {
        // 그 전이는 프레임 루프 **밖**(`spawn(fromHold:)` 의 블록아웃)이라 `tick` 의 게임오버 판정이 못 본다 —
        // 다음 틱은 `step` 전에 이미 `.over` 를 읽어 `wasOver` 로 접는다.
        var board = TetrisGame.emptyBoard()
        for row in (TetrisGame.spawnRow)..<TetrisGame.firstVisibleRow {
            board[row] = Array(repeating: TetrisGame.Piece.i, count: TetrisGame.columns)
        }
        let controller = GamesPlayController(kind: .tetris, seed: 11)
        controller.replaceForTesting(tetris: TetrisGame(
            seed: 11, board: board,
            active: TetrisGame.ActivePiece(piece: .t, column: 3, row: 30)))
        #expect(controller.gameOverSerial == 0)
        controller.hold()
        if case .over = controller.tetris.phase {} else {
            Issue.record("전제가 깨졌다 — 홀드로 갈아탄 조각이 스폰에서 안 막혔다(\(controller.tetris.phase))")
        }
        #expect(controller.gameOverSerial == 1, "홀드로 끝난 판에서만 게임오버 햅틱이 빠진다")

        // ★ 기준선이 다르다: 스폰 자리가 비어 있으면 같은 홀드가 판을 안 끝내고 햅틱도 없다.
        let alive = GamesPlayController(kind: .tetris, seed: 11)
        alive.tap()
        alive.hold()
        #expect(alive.tetris.holdUsed, "대조: 홀드가 아예 안 먹었다(이 비교의 기준선이 헛돈다)")
        #expect(alive.gameOverSerial == 0, "멀쩡한 홀드가 게임오버 햅틱을 울렸다")
    }

    // MARK: - 판을 끝내는 자리

    @Test("endRound(): 테트리스는 그 점수로 **확정해 알린다** — 판마다 한 번뿐")
    func endRoundConfirmsTheTetrisScoreExactlyOnce() throws {
        let controller = startedTetris()
        let recorder = Recorder()
        controller.onFinished = { recorder.scores.append($0) }
        for _ in 0..<5 { controller.softDropOneCell() }
        #expect(controller.tetris.score == 5)

        // ⚠️ `interrupt()` 뒤에는 tick 이 다시 오지 않는다(phase .result → isPlaying false → TimelineView 정지).
        // 여기서 직접 알리지 않으면 점수가 조용히 사라진다 — 그게 이 단언의 전부다.
        #expect(controller.endRound() == .confirmed(5))
        #expect(recorder.scores == [5])
        #expect(controller.tetris.phase == .result)
        #expect(!controller.isPlaying)

        // 두 번째 출구(화면을 떠나며 background 로도 감)는 아무 일도 하지 않는다.
        #expect(controller.endRound() == .none)
        #expect(recorder.scores == [5], "한 판을 두 번 제출했다")
    }

    @Test("endRound(): 기존 두 게임은 예전 그대로 **버린다**(알리지 않는다 = 제출도 없다)")
    func endRoundStillDiscardsTheOtherTwoGames() {
        for kind in [MiniGameKind.timingBar, .flappy] {
            let controller = GamesPlayController(kind: kind, seed: 11)
            let recorder = Recorder()
            controller.onFinished = { recorder.scores.append($0) }
            controller.tap()
            #expect(controller.isPlaying)
            #expect(controller.endRound() == .abandoned, "\(kind.rawValue) 가 제출 쪽으로 넘어갔다")
            #expect(recorder.scores.isEmpty, "\(kind.rawValue) 의 버린 판을 알렸다")
        }
    }

    @Test("abandon(): 테트리스도 **버린다** — 로그아웃·화면 경합 정리가 제출 쪽으로 넘어가면 안 된다")
    func abandonThrowsTheTetrisRoundAway() {
        let controller = startedTetris()
        let recorder = Recorder()
        controller.onFinished = { recorder.scores.append($0) }
        for _ in 0..<3 { controller.softDropOneCell() }
        #expect(controller.abandon())
        #expect(recorder.scores.isEmpty, "버린 판을 알렸다 — 로그아웃에서 남의 계정에 점수가 올라간다")
        #expect(controller.tetris.phase == .ready, "버린 자리에 결과 카드가 남았다")
        #expect(controller.tetris.score == 0)
    }

    // MARK: - 허브: 출구 · 인편 · 상한

    @Test("앱을 나가면 테트리스 판은 **여기까지 기록**된다 · 그 안내를 비동기 제출 성공이 지우지 않는다")
    func leavingTheAppRecordsTheTetrisRound() async throws {
        let harness = GamesHarness(label: "tetris-bg")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-bg")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-bg-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        for _ in 0..<7 { controller.softDropOneCell() }

        harness.model.sceneDidEnterBackground()
        #expect(!controller.isPlaying)
        #expect(harness.hub.submitNotice == GamesMiniGameText.endedInBackground(.tetris))
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        let submit = try #require(harness.server.requests("minigame_submit_score").first)
        #expect(submit.bodyText.contains(#""p_game":"tetris""#))
        #expect(submit.bodyText.contains(#""p_score":7"#))
        #expect(submit.bodyText.contains(#""p_token":"tok-bg-1""#))
        await harness.barrier()
        // ★ 여기가 함정이었다: 성공 갈래가 `submitNotice = nil` 이라 출구 안내를 지웠다.
        #expect(harness.hub.submitNotice == GamesMiniGameText.endedInBackground(.tetris),
                "제출 성공이 '여기까지 기록했어요'를 지웠다 — 사용자에겐 판이 조용히 사라진 것으로 보인다")
        #expect(harness.hub.pendingSubmit == nil)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("뒤로가기로 끝낸 판도 올라가고, **화면을 떠난 뒤에도** 순위를 다시 읽는다")
    func goingBackSubmitsAndStillRefreshesTheBoard() async throws {
        let harness = GamesHarness(label: "tetris-back")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-back")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-back-1" })
        #expect(await waits.wait { harness.hub.boards[.tetris]?.loaded == true })
        let boardReads = harness.server.requests("minigame_board").count
        let controller = try #require(harness.hub.controller)
        controller.tap()
        for _ in 0..<4 { controller.softDropOneCell() }

        harness.hub.closeScreen(.tetris)
        #expect(harness.hub.activeKind == nil)
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        // ★ 재조회가 `activeKind == kind` 에 막혀 있었다 — 뒤로가기로 끝낸 판은 그 가드 뒤라 순위가 안 갱신됐다.
        #expect(await waits.wait { harness.server.requests("minigame_board").count > boardReads },
                "화면을 떠난 뒤 제출은 했는데 순위를 다시 안 읽었다")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("`token_used` 는 **성공이다** — 응답만 유실된 첫 제출의 재시도이고, 그때 점수는 이미 올라가 있다")
    func aUsedTokenIsSuccessNotRefusal() async throws {
        let harness = GamesHarness(label: "tetris-used")
        configure(harness, submit: #"{"status":"token_used"}"#)
        _ = gamesServeRoundTokens(harness, prefix: "tok-used")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-used-1" })
        #expect(await waits.wait { harness.hub.boards[.tetris]?.loaded == true })
        let boardReads = harness.server.requests("minigame_board").count
        let controller = try #require(harness.hub.controller)
        controller.tap()
        controller.softDropOneCell()
        harness.hub.closeScreen(.tetris)

        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.hub.submitNotice == nil, "이미 올라간 점수를 '못 올렸어요'라고 말했다")
        #expect(harness.hub.pendingSubmit == nil, "성공인데 인편이 남아 영영 재시도한다")
        #expect(await waits.wait { harness.server.requests("minigame_board").count > boardReads })
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("네트워크로 실패한 제출은 **남는다** — 앱이 다시 켜지면 같은 토큰으로 한 번 더")
    func aNetworkFailureIsRetriedWhenTheAppComesBack() async throws {
        let harness = GamesHarness(label: "tetris-retry")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-net")
        let online = BaseLockedBox(false)
        harness.server.setDefault("minigame_submit_score") { _ in
            online.get() ? .json(#"{"status":"ok","best_score":9,"plays":1,"improved":true}"#) : .networkFailure()
        }
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-net-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        for _ in 0..<6 { controller.softDropOneCell() }

        harness.model.sceneDidEnterBackground()
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.hub.pendingSubmit?.token == "tok-net-1", "네트워크 실패에 점수가 그냥 사라졌다")
        #expect(harness.hub.pendingSubmit?.score == 6)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitFailedConnection)

        online.mutate { $0 = true }
        harness.model.sceneDidBecomeActive()
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 2 },
                "복귀했는데 인편을 다시 보내지 않았다")
        // ⚠️ 위 대기가 어긋나면 이 배열은 한 칸뿐이다. `[1]` 로 읽으면 `Index out of range`(signal 5)로 **번들이
        //    통째로 죽어** 뒤의 테스트가 아예 안 돌고 실패 목록도 안 찍힌다 — 결함 하나가 나머지 결과를 통째로 가린다.
        let retry = try #require(harness.server.requests("minigame_submit_score").dropFirst().first,
                                 "재시도 요청이 없다 — 위 대기가 어긋났다")
        #expect(retry.bodyText.contains(#""p_token":"tok-net-1""#), "재시도가 다른 토큰으로 나갔다 — 그러면 두 번 올라간다")
        #expect(retry.bodyText.contains(#""p_score":6"#))
        #expect(await waits.wait { harness.hub.pendingSubmit == nil })
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("제출이 실패해 **인편이 살아 있는 동안**에는 그 게임의 새 토큰을 받지 않는다 — 받으면 인편의 토큰이 죽는다")
    func aPrefetchDoesNotKillThePendingSubmitsToken() async throws {
        // 서버는 (사용자, 게임)당 **미사용 토큰을 한 행만** 두고 새 요청마다 갈아 끼운다(`minigame_rounds_one_open`).
        // 그래서 네트워크 실패로 인편을 남긴 직후 같은 게임의 새 토큰을 받으면 **방금 적어 둔 인편의 토큰이
        // 서버에서 사라진다** — 복귀 재시도는 `no_token`(terminal)을 받고 인편이 버려진다.
        //
        // ⚠️ 이 테스트는 스텁이 **호출마다 다른 토큰**을 줘야만 성립한다. 매번 같은 문자열을 주면 갈아 끼워져도
        //    바뀐 것이 없어 영원히 초록이다(저장소 메모 '비교 기준선이 달라야 한다').
        let harness = GamesHarness(label: "tetris-prefetch")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-pre")
        let online = BaseLockedBox(false)
        harness.server.setDefault("minigame_submit_score") { _ in
            online.get() ? .json(#"{"status":"ok","best_score":9,"plays":1,"improved":true}"#) : .networkFailure()
        }
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-pre-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        for _ in 0..<6 { controller.softDropOneCell() }

        harness.hub.closeScreen(.tetris)
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.hub.pendingSubmit?.token == "tok-pre-1", "네트워크 실패에 점수가 그냥 사라졌다")

        // ★ 여기가 전부다: 실패 갈래 꼬리의 프리페치가 그대로 나가면 토큰이 **둘**이 되고, 그 순간 서버에서
        //   tok-pre-1 은 죽는다(= 인편이 어떤 재시도로도 못 올라간다).
        #expect(tokens.get() == ["tok-pre-1"],
                "인편이 살아 있는데 같은 게임의 새 토큰을 받았다 — 인편의 토큰을 자기 손으로 죽였다: \(tokens.get())")
        #expect(harness.hub.roundToken == nil, "인편의 토큰을 갈아 끼운 새 토큰을 들고 있다")

        // 그렇다고 **토큰 없이 굳지도 않는다**: 인편이 비워지는 순간 새 토큰을 받는다.
        online.mutate { $0 = true }
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        #expect(await waits.wait { harness.hub.pendingSubmit == nil }, "복귀 재시도가 인편을 못 비웠다")
        #expect(await waits.wait { harness.hub.roundToken == "tok-pre-2" },
                "인편이 비었는데 다음 토큰을 못 받았다 — 이 게임이 토큰 없이 굳었다: \(tokens.get())")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("인편이 살아 있으면 **새 판이 그 인편을 밀어낸다** — 토큰 없이 굳지 않는다")
    func beginningARoundPushesTheStalePendingOut() async throws {
        let harness = GamesHarness(label: "tetris-begin")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-beg")
        let online = BaseLockedBox(false)
        harness.server.setDefault("minigame_submit_score") { _ in
            online.get() ? .json(#"{"status":"ok","best_score":9,"plays":1,"improved":true}"#) : .networkFailure()
        }
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-beg-1" })
        let first = try #require(harness.hub.controller)
        first.tap()
        first.softDropOneCell()
        harness.hub.closeScreen(.tetris)
        #expect(await waits.wait { harness.hub.pendingSubmit?.token == "tok-beg-1" })
        await harness.barrier()
        #expect(tokens.get() == ["tok-beg-1"], "인편이 살아 있는데 새 토큰이 나갔다")

        // 연결이 돌아왔고, 사람이 다시 화면을 열어 판을 시작한다. 프리페치는 인편에 막혀 비켜서므로,
        // **인편을 미는 것**(openScreen · beginRound)이 없으면 이 판은 끝까지 토큰이 없다.
        online.mutate { $0 = true }
        harness.hub.openScreen(.tetris)
        let second = try #require(harness.hub.controller)
        second.tap()
        #expect(await waits.wait { harness.hub.pendingSubmit == nil }, "새 판이 시작됐는데 앞 인편을 안 밀어냈다")
        #expect(await waits.wait { harness.hub.roundToken == "tok-beg-2" },
                "인편이 비워졌는데 새 토큰을 안 받았다 — 이 판은 제출할 토큰이 없다: \(tokens.get())")
        // 앞 판의 점수는 같은 토큰으로 실제로 올라갔다(밀어내기가 '조용히 버리기'가 아니다).
        let sent = harness.server.requests("minigame_submit_score").map(\.bodyText)
        #expect(sent.contains { $0.contains(#""p_token":"tok-beg-1""#) }, "앞 판이 어떤 토큰으로도 안 나갔다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("토큰이 죽은 거절은 '다시 해 주세요'로 말하지 않는다 — 그 판은 어떤 재시도로도 안 올라간다")
    func aDeadTokenDoesNotPromiseRecovery() async throws {
        let harness = GamesHarness(label: "tetris-dead")
        configure(harness, submit: #"{"status":"token_expired"}"#)
        _ = gamesServeRoundTokens(harness, prefix: "tok-dead")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-dead-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        controller.softDropOneCell()
        harness.hub.closeScreen(.tetris)

        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitTokenDead)
        #expect(harness.hub.submitNotice != GamesMiniGameText.submitFailedConnection, "없는 복구를 기다리게 한다")
        #expect(harness.hub.pendingSubmit == nil, "죽은 토큰을 영영 재시도한다")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("호출자 쪽 거절(`unauthorized`·`no_profile`)도 인편을 지운다 — 안 지우면 앱을 켤 때마다 영원히 다시 보낸다")
    func callerSideRefusalsClearThePendingSubmit() async throws {
        // 이 둘은 **토큰이 아니라 호출자 쪽 거절**이라 서버가 uid·프로필 검사에서 곧장 돌아오고 30분 TTL 판정까지
        // 가지도 않는다 — 스스로 `token_expired` 로 바뀌지 않는다. 지우지 않으면 스스로 빠져나올 길이 없다.
        // (대조군은 `aNetworkFailureIsRetriedWhenTheAppComesBack` — 네트워크 실패는 반대로 **남아서** 다시 나간다.)
        for status in ["unauthorized", "no_profile"] {
            let harness = GamesHarness(label: "tetris-\(status)")
            configure(harness, submit: #"{"status":"\#(status)"}"#)
            _ = gamesServeRoundTokens(harness, prefix: "tok-\(status)")
            await harness.signIn()
            harness.hub.openScreen(.tetris)
            #expect(await waits.wait { harness.hub.roundToken == "tok-\(status)-1" })
            let controller = try #require(harness.hub.controller)
            controller.tap()
            controller.softDropOneCell()
            harness.hub.closeScreen(.tetris)

            #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
            await harness.barrier()
            #expect(harness.hub.pendingSubmit == nil, "\(status): 인편이 남았다 — 앱을 켤 때마다 같은 토큰이 영원히 나간다")
            // 문구는 '토큰이 죽었다'가 아니라 '못 올렸다'다(그 판이 아니라 호출자가 거절당했다).
            #expect(harness.hub.submitNotice == GamesMiniGameText.submitRefused, "\(status): 문구가 다르다")

            // 실제로 다시 안 나간다: 앱을 나갔다 돌아와도 제출은 그대로 한 번뿐이다.
            harness.model.sceneDidEnterBackground()
            harness.model.sceneDidBecomeActive()
            await harness.barrier()
            #expect(harness.server.requests("minigame_submit_score").count == 1,
                    "\(status): 복귀 때 같은 토큰을 또 보냈다 — 이것이 영원히 반복된다")
            await harness.tearDown()
        }
    }

    @Test("인편 칸에서 **밀려나는** 앞 판을 조용히 버리지 않는다 — 마지막으로 한 번 더 보낸다")
    func aSupersededPendingIsSentOnceMore() async throws {
        // 인편 칸은 하나뿐이다. 게임이 다른 두 인편은 공존 못 한다 — 플래피 인편이 남은 채 테트리스 판이 끝나면
        // 예전에는 플래피 점수가 **재시도 한 번 없이** 사라졌다(그 판의 실패 안내마저 이미 지워진 뒤였다).
        //
        // ⚠️ 도달 경로는 **게임이 다른** 경우다: 같은 게임이면 A1 가드가 인편이 사는 동안 새 토큰을 막아
        //    `recordScore` 가 인편을 만들 토큰 자체를 못 얻는다.
        let harness = GamesHarness(label: "tetris-superseded")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-sup")
        // 플래피 제출만 끝까지 실패한다(인편이 살아 있어야 밀려나는 장면이 만들어진다).
        harness.server.setDefault("minigame_submit_score") { request in
            request.bodyText.contains(#""p_game":"flappy""#)
                ? .networkFailure()
                : .json(#"{"status":"ok","best_score":55,"plays":4,"improved":true}"#)
        }
        func flappySubmits() -> Int {
            harness.server.requests("minigame_submit_score").filter { $0.bodyText.contains(#""p_game":"flappy""#) }.count
        }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await waits.wait { harness.hub.roundToken == "tok-sup-1" })
        harness.hub.recordScore(kind: .flappy, score: 12)
        #expect(await waits.wait { harness.hub.pendingSubmit?.kind == .flappy })
        await harness.barrier()

        // 사람이 테트리스로 갈아타고 한 판 한다. 플래피 인편은 그대로 살아 있다.
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-sup-2" })
        #expect(harness.hub.pendingSubmit?.kind == .flappy, "테트리스 화면을 여는 것만으로 플래피 인편이 사라졌다")
        let before = flappySubmits()

        // ★ 여기가 전부다: 테트리스 점수가 인편 칸을 가져가면서 플래피 제출을 **한 번 더** 밀어 보낸다.
        //   보내지 않으면 그 점수는 어떤 경로로도 다시 나가지 않는다.
        harness.hub.recordScore(kind: .tetris, score: 7)
        #expect(harness.hub.pendingSubmit?.kind == .tetris, "인편 칸의 주인이 새 판으로 안 바뀌었다")
        #expect(await waits.wait { flappySubmits() > before },
                "밀려난 플래피 점수를 조용히 버렸다 — 재시도 한 번 없이 사라진다")
        let last = try #require(harness.server.requests("minigame_submit_score")
            .last { $0.bodyText.contains(#""p_game":"flappy""#) })
        #expect(last.bodyText.contains(#""p_token":"tok-sup-1""#), "밀려난 제출이 **다른 토큰**으로 나갔다")
        #expect(last.bodyText.contains(#""p_score":12"#), "밀려난 제출의 점수가 앞 판의 것이 아니다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("판 벽시계 상한 15분 — 늘어뜨린 판이 통째로 거절되기 전에 **판이 먼저 끝난다**")
    func theRoundHasAFifteenMinuteWallClockCap() async throws {
        let harness = GamesHarness(label: "tetris-cap")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-cap")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-cap-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        controller.softDropOneCell()
        // 상한은 **길이**로 내려온다. 절대 시각으로 찍으면 그걸 재는 `tick(at:)` 의 벽시계와 축이 갈린다.
        #expect(controller.roundLimitSeconds == GamesMiniGameHub.tetrisRoundLimitSeconds)

        // ★ 기준점은 **첫 틱**이 자기 축에서 잡는다. 여기서는 일부러 주입 시계와 한참 떨어진 시각으로 프레임을 준다 —
        //   예전처럼 `context.clock` 으로 마감을 찍었다면 이 첫 틱이 이미 마감 뒤라 판이 그 자리에서 죽는다.
        let frame = harness.clock.now.addingTimeInterval(9 * 24 * 3600)
        controller.tick(at: frame)
        #expect(controller.isPlaying, "주입 시계로 찍은 마감이 첫 프레임에 판을 죽였다 — 두 축이 섞였다")

        // ★ 기준선이 다르다: 상한 직전의 틱은 판을 끝내지 않는다.
        controller.tick(at: frame.addingTimeInterval(GamesMiniGameHub.tetrisRoundLimitSeconds - 1))
        #expect(controller.isPlaying, "상한 전에 판이 끝났다")

        controller.tick(at: frame.addingTimeInterval(GamesMiniGameHub.tetrisRoundLimitSeconds + 1))
        #expect(!controller.isPlaying)
        #expect(controller.tetris.phase == .result)
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 },
                "상한으로 끝낸 판을 제출하지 않았다")
        // 검산: 12(토큰 재사용) + 15(판) + 1(제출 여유) = 28 < 30(서버 TTL).
        #expect(MiniGameKind.tetris.roundTokenReuseSeconds + GamesMiniGameHub.tetrisRoundLimitSeconds + 60 < 30 * 60)
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("기존 두 게임에는 판 상한이 없다(테트리스만 건다)")
    func theOtherTwoGamesHaveNoWallClockCap() async throws {
        let harness = GamesHarness(label: "tetris-cap-others")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-none")
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await waits.wait { harness.hub.roundToken == "tok-none-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        #expect(controller.roundLimitSeconds == nil)
        await harness.tearDown()
    }

    // MARK: - 화면 모양(소스 계약 — `#if os(iOS)` 는 macOS 에서 컴파일되지 않는다)

    @Test("폰 화면 배선: 캔버스 · 제스처 한 자리 · 버튼 셋 · 햅틱 네 채널 · 직접 조작 트레잇은 테트리스만 뺀다")
    func thePhoneScreenIsWired() throws {
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift")
        #expect(screen.contains("GamesTetrisCanvas(game: controller.tetris"), "테트리스 캔버스가 화면에 안 붙었다")
        #expect(!screen.contains("case .tetris:\n            Color.clear"), "캔버스 자리가 아직 빈 판이다")

        // 제스처는 **한 자리**다. 모디파이어 자체를 kind 로 가르면 뷰 정체성이 갈려 SwiftUI 가 제스처를 다시 만든다.
        #expect(screen.components(separatedBy: ".gesture(canvasDrag(").count == 2, "캔버스 제스처가 한 자리가 아니다")
        #expect(screen.contains("controller.canvasDragChanged(") && screen.contains("controller.canvasDragEnded("))
        #expect(screen.contains("swallowsTetrisDragEnd"), "시작 래치가 켠 판의 end 를 안 삼킨다 — 한 번의 탭이 시작과 회전을 둘 다 한다")

        // 햅틱 네 채널 — 이동·소프트드롭 채널은 **없다**.
        for trigger in ["controller.tapSerial", "controller.hardDropSerial", "controller.lineClearSerial", "controller.gameOverSerial"] {
            #expect(screen.contains("trigger: " + trigger), "햅틱 채널이 빠졌다: \(trigger)")
        }
        #expect(!screen.contains("moveSerial") && !screen.contains("softDropSerial"),
                "걸음마다 햅틱을 울린다 — L5 초당 213회는 탭틱이 낼 수 없는 속도다")

        // 접근성: 테트리스만 직접 조작 트레잇을 뺀다(셀 15~18pt 를 눈 없이 겨냥할 수 없다).
        #expect(screen.contains("kind == .tetris ? [] : [.allowsDirectInteraction]"))
        #expect(screen.contains("AccessibilityNotification.Announcement("), "이동 액션 뒤에 아무 말도 안 한다")
        // 값에는 느린 것만 — 조각·열·행은 보이스오버가 자기 말을 끊는다.
        #expect(screen.contains("GamesMiniGameText.tetrisValue(score:"))

        // 버튼 줄: 아이콘 셋 · 채운 버튼 0 · `.disabled()` 금지 · AX 크기 상한.
        for icon in ["\"square.on.square\"", "\"rotate.left\"", "\"arrow.down.to.line\""] {
            #expect(screen.contains(icon), "버튼 아이콘이 없다: \(icon) — 없는 심벌 이름은 경고 없이 빈 칸이 된다")
        }
        #expect(!screen.contains(".disabled("), "홀드를 비활성으로 만들었다 — 조각마다 깜빡이고 보이스오버 목록에서 사라진다")
        #expect(!screen.contains("kind: .filled") && !screen.contains("AingButtonStyle(.filled"),
                "화면에 채운 버튼을 뒀다(규약: 화면당 하나 · 여기는 0개다)")
        #expect(screen.contains("...DynamicTypeSize.accessibility1"), "버튼 줄이 접근성 글자 크기에서 화면 밖으로 밀린다")
        #expect(!screen.contains("confirmationDialog") && !screen.contains("alert("),
                "즉시 내리기에 확인창을 달았다 — L15 락딜레이 0.16초가 그 예산 전부다")
        // 눌림은 **색만** 바꾼다(스케일 애니메이션이 없으니 reduceMotion 분기도 필요 없다).
        #expect(!screen.contains("scaleEffect"), "버튼 눌림에 스케일 애니메이션을 썼다")
    }

    @Test("출구는 셋이 다르다: 뒤로가기·background 만 endRound(), 로그아웃·경합 정리는 abandon() 그대로")
    func theThreeExitsStayApart() throws {
        let hub = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGameHub.swift")
        #expect(hub.components(separatedBy: "controller?.endRound()").count == 2, "endRound 호출부가 둘이 아니다(closeScreen)")
        #expect(hub.contains("switch controller.endRound()"), "appDidEnterBackground 가 endRound 를 안 쓴다")
        // `abandon()` 은 **둘**이다: openScreen(경합 정리) · reset(로그아웃). 여기에 테트리스 제출이 섞이면
        // 로그아웃이 남의 계정에 점수를 올린다.
        #expect(hub.components(separatedBy: "controller?.abandon()").count == 3,
                "abandon 호출부가 둘이 아니다 — 로그아웃·화면전환이 제출 쪽으로 넘어갔거나 사라졌다")
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(store.contains("miniGames.retryPendingSubmitIfAny()"), "복귀 재시도가 스토어에 안 걸렸다")
        #expect(store.contains("miniGames.appDidEnterBackground()"))
    }

    @Test("노출 플립은 아직이다 — phoneCases 와 딥링크를 **둘 다** 안 건드렸다")
    func theFlipIsStillClosed() throws {
        // 서버 마이그레이션이 실서버에 올라가기 전에 노출하면 `minigame_start_round('tetris')` 가 invalid 를 줘서
        // 전원이 판을 돌리는데 기록이 하나도 안 남는다.
        #expect(MiniGameKind.phoneCases == [.timingBar, .flappy])
        // 한쪽만 넓히면 `routeStep` 이 `.timing 이 아니면 플래피`로 접어 테트리스 딥링크가 조용히 오배달된다.
        #expect(AingRoute.MiniGame.allCases.map(\.rawValue) == ["timing", "flappy"])
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(store.contains("game == .timing ? .timingBar : .flappy"), "대조: 접는 자리가 사라졌다(이 검사가 헛돈다)")
        // 타일은 **그려 뒀다** — 플립 한 줄이면 켜지는 상태다(빈 타일이 남아 있으면 안 된다).
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.contains("case .tetris: tetris(geo.size)"), "테트리스 타일 그림이 비어 있다")
        #expect(tab.contains("LazyVGrid(columns: Self.tileColumns"), "타일이 아직 한 줄짜리 HStack 이다 — 셋이 되면 넘친다")
        #expect(tab.contains("MiniGameKind.phoneCases"), "타일이 폰 목록을 안 돈다")
    }
}

/// `onFinished` 가 몇 번 · 무슨 값으로 불렸는지 모은다(지역 var 캡처 대신 — 의도를 이름으로 남긴다).
@MainActor
private final class Recorder {
    var scores: [Int] = []
}
