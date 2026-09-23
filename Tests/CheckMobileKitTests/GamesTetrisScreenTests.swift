@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

/// v0.3.38 폰 테트리스 **화면과 그 주변** — 버튼 줄의 치수·발화 시점, 캔버스가 그림만 그린다는 것, 게임별로 갈린
/// 토큰 나이·출구·문구. 배선(손가락 → 엔진)은 `GamesTetrisWiringTests` 가 잰다.
///
/// 왜 모양을 **소스 텍스트**로 재는가: 폰 뷰는 전부 `#if os(iOS)` 안이라 macOS `swift test` 가 컴파일조차 하지 않는다.
/// 실제 컴파일은 `ios/scripts/build-sim.sh`(진짜 iOS SDK)가 확인하고, 여기서는 **컴파일돼도 틀릴 수 있는 것**
/// — 비율·높이·발화 시점·금지 모디파이어 — 만 잰다. `IntegrationContractTests.code(_:)` 는 주석을 걷어내고 주므로
/// 설명에 적힌 금지어는 안 걸린다(설명을 지워야 초록이 되는 테스트는 만들지 않는다).
///
/// ⚠️ 이 파일의 수는 전부 **설계에서 온 값**이다. 고치려면 설계부터 고쳐라:
///   · 버튼 셋 26 : 30 : 44 (쓸 폭 = 캔버스 폭 − 8 − 16) · 높이 48
///   · 즉시 내리기만 터치-업 인사이드, 홀드·반시계는 터치-다운 래치
///   · 캔버스 탭 = 시계 · 버튼 = 반시계
@MainActor
@Suite(.serialized) struct GamesTetrisScreenTests {
    private static let screenPath = "Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift"
    private static let canvasPath = "Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift"

    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    // MARK: - 버튼 줄(설계 F·G·H)

    @Test("버튼 셋의 폭은 26 : 30 : 44 이고 쓸 폭은 간격 8·16 을 뺀 나머지다 — 높이는 48")
    func theThreeButtonsSplitTheRowExactly() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 쓸 폭 W' = W − 8 − 16. 간격을 안 빼면 셋의 합이 캔버스보다 넓어져 마지막 버튼이 오른쪽으로 삐져나간다.
        #expect(screen.contains("width - MobileTheme.space2 - MobileTheme.space4"))
        for ratio in ["usable * 0.26", "usable * 0.30", "usable * 0.44"] {
            #expect(screen.components(separatedBy: ratio).count == 2, "버튼 폭 비율이 한 번씩 안 나온다: \(ratio)")
        }
        // 합이 1 이다 — 하나만 고치면 줄이 어긋난다(이 셋은 같이 움직여야 한다).
        #expect(abs(0.26 + 0.30 + 0.44 - 1.0) < 1e-9)
        #expect(screen.contains("static let height: CGFloat = 48"), "버튼 높이가 미니게임 행 높이 48 이 아니다")

        // 간격의 실제 수(8·16)는 토큰 쪽에 있다 — 토큰이 바뀌면 죽은 간격도 같이 바뀐다.
        let theme = try IntegrationContractTests.code("Sources/CheckMobileKit/Theme/MobileTheme.swift")
        #expect(theme.contains("space2: CGFloat = 8"))
        #expect(theme.contains("space4: CGFloat = 16"))
    }

    @Test("죽은 간격 16 — 두 Spacer 는 히트 영역이 없고 어느 버튼도 그 안으로 안 넓힌다")
    func theGapBetweenRotateAndHardDropIsDead() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 간격은 **Spacer**(히트 영역 없음)다. padding 으로 벌리면 그 자리가 이웃 버튼의 탭 영역이 된다.
        #expect(screen.components(separatedBy: "Spacer(minLength: 0).frame(width:").count == 3,
                "버튼 사이 간격이 두 개가 아니다")
        #expect(screen.contains(".frame(width: MobileTheme.space2)"))
        #expect(screen.contains(".frame(width: MobileTheme.space4)"))
        // 버튼의 탭 영역은 **자기 캡슐까지**다 — Rectangle 로 넓히면 죽은 간격이 살아난다.
        #expect(screen.contains("contentShape(Capsule())"))
        #expect(!screen.contains("hitTestPadding") && !screen.contains("contentShape(Rectangle().inset"))
    }

    @Test("즉시 내리기만 터치-업 인사이드 — 홀드·반시계는 터치-다운 래치(20G 에서 뗌을 기다릴 여유가 없다)")
    func onlyHardDropFiresOnTouchUp() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        #expect(screen.components(separatedBy: "firesOnTouchDown: true").count == 3, "터치-다운 버튼이 둘이 아니다")
        #expect(screen.components(separatedBy: "firesOnTouchDown: false").count == 2, "터치-업 버튼이 하나가 아니다")
        // 터치-업은 **표준 Button** 이다 — 손을 끌어 빼면 취소된다(잘못 누르면 그 판이 끝난다).
        #expect(screen.contains("Button(action: action)"))
        #expect(screen.contains("buttonStyle(TetrisControlButtonStyle"))
        // 확인창은 없다: L15 부터 락딜레이가 0.16초라 확인창 한 번이 그 예산 전부다.
        #expect(!screen.contains("confirmationDialog") && !screen.contains("alert("))
    }

    @Test("회전은 방향을 나눈다 — 캔버스 탭이 시계, 버튼이 반시계(둘 다 시계면 폰에서 반시계가 사라진다)")
    func theButtonRotatesTheOtherWay() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        #expect(screen.components(separatedBy: "rotate(clockwise: false)").count == 2, "반시계 버튼이 한 개가 아니다")
        // ★ 화면에는 `clockwise: true` 가 **없다**: 시계는 캔버스 탭이고 그 판정은 구동기 안에 있다.
        #expect(!screen.contains("rotate(clockwise: true)"), "버튼도 시계로 돌면 캔버스 탭과 겹쳐 자리 하나를 버린다")
        let controller = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesPlayController.swift")
        #expect(controller.contains("rotate(clockwise: true)"), "대조: 시계 회전이 구동기에서도 사라졌다")
        // 그 사실을 말하는 자리는 시작 카드뿐이다 — 빼면 아무도 시계 회전을 못 찾는다.
        #expect(GamesMiniGameText.howToPlay(.tetris).contains("탭해서 회전"))
        #expect(GamesMiniGameText.tetrisRotateCounterClockwise == "반시계")
    }

    @Test("홀드 소진은 **색**으로 말한다 — `.disabled()` 도, 채운 버튼도, 스케일 애니메이션도 없다")
    func aSpentHoldIsGreyedNotDisabled() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 이 값은 조각마다 꺼졌다 켜진다(판 후반 1.3조각/초) — 비활성으로 만들면 초당 한 번 넘게 깜빡이고
        // 보이스오버가 비활성 요소를 건너뛰어 버튼이 목록에서 사라졌다 나타났다 한다.
        #expect(!screen.contains(".disabled("))
        #expect(screen.contains("isSpent ? MobileTheme.label2 : MobileTheme.accent"))
        #expect(screen.contains("MobileTheme.accentTint"), "버튼이 틴트가 아니다")
        #expect(!screen.contains("kind: .filled") && !screen.contains("AingButtonStyle(.filled"),
                "이 화면에 채운 버튼을 뒀다(규약: 화면당 하나 · 여기는 0개다)")
        // 눌림은 색만 — 스케일 애니메이션이 없으니 reduceMotion 분기 자체가 필요 없다(설계 J).
        #expect(!screen.contains("scaleEffect") && !screen.contains("withAnimation"))
        // 소진 상태에서도 보이스오버 목록에는 남고 값만 붙는다.
        #expect(screen.contains("accessibilityValue(isSpent ? GamesMiniGameText.tetrisHoldSpent"))
        #expect(screen.contains("accessibilityAddTraits(.isButton)"))
    }

    @Test("접근성 글자 크기: 버튼 줄은 accessibility1 에서 멈추고 글자를 떨어뜨린다(아이콘·라벨은 남는다)")
    func theButtonRowSurvivesAccessibilityText() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 캔버스의 `...large` 상한은 캔버스에만 걸려 있다 — 버튼 줄은 시스템 글자를 그대로 따라가서 화면 밖으로 밀렸다.
        #expect(screen.contains("...DynamicTypeSize.accessibility1"))
        #expect(screen.contains("...DynamicTypeSize.large"), "대조: 캔버스 상한이 사라졌다")
        #expect(screen.contains("if !typeSize.isAccessibilitySize"), "AX 크기에서 글자를 안 떨어뜨린다")
        #expect(screen.contains(".lineLimit(1)") && screen.contains("minimumScaleFactor(0.8)"))
        // 아이콘 셋은 iOS 13 부터 있는 이름이다 — **없는 심벌 이름은 경고 없이 빈 칸이 된다.**
        for icon in ["\"square.on.square\"", "\"rotate.left\"", "\"arrow.down.to.line\""] {
            #expect(screen.components(separatedBy: icon).count == 2, "아이콘이 한 번씩 안 나온다: \(icon)")
        }
        #expect(screen.contains("size: 17, weight: .semibold") && screen.contains(".caption2.weight(.semibold)"))
    }

    // MARK: - 캔버스·햅틱·접근성

    @Test("햅틱은 네 채널뿐 — 이동 걸음·소프트드롭 걸음에는 serial 이 **없다**")
    func thereAreExactlyFourHapticChannels() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        #expect(screen.components(separatedBy: ".sensoryFeedback(").count == 5, "햅틱 채널이 넷이 아니다")
        for trigger in ["controller.tapSerial", "controller.hardDropSerial",
                        "controller.lineClearSerial", "controller.gameOverSerial"] {
            #expect(screen.contains("trigger: " + trigger), "채널이 빠졌다: \(trigger)")
        }
        // 걸음을 내는 자리(`feed`)는 serial 을 **아예 안 만진다** — L1 소프트드롭이 초당 56회, L5 는 213회다.
        let controller = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesPlayController.swift")
        let after = try #require(controller.components(separatedBy: "private func feed(_ step: TetrisGestureStep)").last)
        let body = try #require(after.components(separatedBy: "package func updateCellWidth").first)
        #expect(body.contains("tetris.setLeftHeld(true)") && body.contains("tetris.softDropOneCell()"),
                "대조: 걸음을 내는 자리를 못 찾았다(이 검사가 빈 문자열을 보고 있다)")
        // ⚠️ 가로 걸음은 **짝**이다(이 저장소 메모 '클라 게이트는 짝으로 있다'). 누름만 보고 뗌을 안 보면,
        //    뗌이 사라져 자동 반복이 살아남아도 — 즉 조각이 손을 뗀 뒤 혼자 벽까지 흘러도 — 이 검사는 초록이다.
        //    (실제 거동은 `theSidewaysStepIsSymmetricAndLeavesNoRepeat` 이 재고, 여기서는 짝의 **존재**만 못 박는다.)
        for side in ["Left", "Right"] {
            #expect(body.contains("tetris.set\(side)Held(true)") && body.contains("tetris.set\(side)Held(false)"),
                    "\(side) 가로 걸음의 짝이 깨졌다 — 누름과 뗌은 같은 호출 안에 연달아 있어야 한다")
        }
        #expect(!body.contains("Serial"), "걸음 하나하나가 햅틱을 울린다 — 탭틱이 낼 수 있는 속도가 아니다")
        for step in ["moveLeftOneCell() { feed(.moveLeft) }", "moveRightOneCell() { feed(.moveRight) }",
                     "softDropOneCell() { feed(.softDrop) }"] {
            #expect(controller.contains(step), "걸음이 공용 가드(feed)를 안 지난다: \(step)")
        }
    }

    @Test("접근성: 테트리스만 직접 조작 트레잇을 빼고, 액션은 **버튼이 없는 조작 셋**뿐이다")
    func voiceOverGetsMoveActionsButNoDuplicateButtons() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 셀이 15~18pt 인 판에서 눈 없이 겨냥하라는 뜻이라 실질 조작이 불가능하다. 두 게임에는 그대로 둔다.
        #expect(screen.contains("kind == .tetris ? [] : [.allowsDirectInteraction]"))
        for action in ["GamesMiniGameText.tetrisMoveLeft", "GamesMiniGameText.tetrisMoveRight",
                       "GamesMiniGameText.tetrisSoftDrop"] {
            #expect(screen.contains("Button(" + action + ")"), "이동 액션이 빠졌다: \(action)")
        }
        // 홀드·반시계·즉시 내리기는 **이미 진짜 버튼**이라 액션으로 또 내지 않는다(목록에 두 번 선다).
        for duplicated in ["Button(GamesMiniGameText.tetrisHold)", "Button(GamesMiniGameText.tetrisHardDrop)",
                           "Button(GamesMiniGameText.tetrisRotateCounterClockwise)"] {
            #expect(!screen.contains(duplicated), "진짜 버튼을 액션으로 또 냈다: \(duplicated)")
        }
        // 값에는 **느린 것만**(점수·레벨·줄). 조각·열·행은 이동 뒤 알림으로 말한다.
        #expect(screen.contains("GamesMiniGameText.tetrisValue(score:"))
        #expect(screen.contains("AccessibilityNotification.Announcement("))
        #expect(!screen.contains("tetrisValue(score: game.score, level: game.scoreLevel, lines: game.lines, column:"))
    }

    @Test("캔버스는 **그림만** 그린다 — 입력·시계·배치 복제본이 하나도 없다")
    func theCanvasOnlyDraws() throws {
        let canvas = try IntegrationContractTests.code(Self.canvasPath)
        // 배치·색은 코어 한 벌이다(맥과 폰이 같은 표를 읽어야 같은 판의 스크린샷 픽셀이 같다).
        #expect(canvas.components(separatedBy: "TetrisLayout.").count - 1 == 57)
        #expect(canvas.components(separatedBy: "TetrisPalette.").count - 1 == 9)
        for banned in ["struct TetrisLayout", "enum TetrisLayout", "struct TetrisPalette", "enum TetrisPalette"] {
            #expect(!canvas.contains(banned), "폰 전용 배치·색 표를 새로 만들었다: \(banned)")
        }
        // 입력·프레임 루프는 여기 없다(구동기와 TimelineView 의 일이다).
        for banned in ["TetrisKeyWatchdog", "syncHeldKeys", "setLeftHeld", "setSoftDropHeld",
                       "softDropOneCell", "controller", "Timer", "CACurrentMediaTime", "1.0 / 60.0"] {
            #expect(!canvas.contains(banned), "캔버스가 그림 밖의 일을 한다: \(banned)")
        }
        // 60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다(맥 파일 머리 주석의 금지 셋을 그대로 잇는다).
        for banned in ["addFilter", "drawLayer", ".blur(", "repeatForever"] {
            #expect(!canvas.contains(banned), "캔버스에 금지 연출이 들어갔다: \(banned)")
        }
        // 배경은 하늘만 — 능선은 하단 밴드 자리를 밝게 채워 글자와 겹친다.
        #expect(canvas.contains("terrain: false") && !canvas.contains("terrain: true"))
        #expect(canvas.contains("MiniGameStage.forTetrisAdvance(game.advance)"), "무대 인자가 advance 가 아니다")
    }

    @Test("캔버스 글자: 배율을 곱하고, 8pt 캡션 셋 대신 **자기설명형 값**을 쓴다(iOS 캡션 하한 10pt)")
    func theCanvasTextIsScaledAndSelfDescribing() throws {
        let canvas = try IntegrationContractTests.code(Self.canvasPath)
        // 맥은 HUD 글꼴에 배율을 안 곱한다. 폰 캔버스의 관용구는 곱하는 쪽이다 — 판이 커진 만큼 글자도 커져야 같은 그림이다.
        // ⚠️ "* scale" 만 세면 "14 * t.scale" 은 사이에 `t.` 가 있어 안 걸린다. 둘 다 센다.
        #expect(canvas.components(separatedBy: "* t.scale").count - 1 == 12)
        #expect(canvas.components(separatedBy: "* scale").count - 1 == 4)
        // 8 × 1.1747(SE) = 9.40pt 라 캡션 하한을 못 넘고, captionHeight 9 라 키우면 값 상자와 곧장 겹친다.
        #expect(!canvas.contains("size: 8") && !canvas.contains("size: 9"))
        #expect(canvas.contains("\"Lv \" + String(game.scoreLevel)"), "레벨 값이 자기설명형이 아니다")
        #expect(canvas.contains("String(game.lines) + \"줄\""), "줄 값이 자기설명형이 아니다")
        // 캡션 상자 바닥이 값 상자 꼭대기와 붙어 있다는 것이 '키울 수 없다'의 근거다 — 표가 바뀌면 여기가 먼저 빨개진다.
        #expect(TetrisLayout.levelCaptionY + TetrisLayout.captionHeight == TetrisLayout.levelValueY)
        #expect(TetrisLayout.linesCaptionY + TetrisLayout.captionHeight == TetrisLayout.linesValueY)
        // reduceMotion 은 **둘**에 내려간다(무대 배경 연출 · 판정 팝). 떨어지는 조각·고스트는 안 끈다.
        #expect(canvas.components(separatedBy: "reduceMotion: reduceMotion").count - 1 == 2)
        #expect(!canvas.contains("MiniGameKind.controlHint"),
                "정적 조작 안내를 쓰면 테트리스에 '클릭 또는 스페이스'가 나간다")
    }

    @Test("시작 래치가 켠 그 끌기의 end 는 삼킨다 — 한 번의 탭이 시작과 회전을 **둘 다** 하면 안 된다")
    func theDragThatStartedTheRoundDoesNotAlsoRotate() throws {
        // ★ 기준선(이건 실제로 돌린다): 구동기는 스스로 삼키지 않는다 — 판이 막 켜진 직후의 `end` 도 그대로 회전한다.
        //   `action()` 이 ready → running 으로 바꾼 직후라 탭 판정이 통과하기 때문이다. 그래서 삼키는 일이
        //   **화면 몫**이고, 아래 세 줄이 그 유일한 장치다(이 기준선이 없으면 아래 단언이 무엇을 막는지 알 수 없다).
        let controller = GamesPlayController(kind: .tetris, seed: 5)
        controller.updateCellWidth(20)
        controller.tap()
        let before = try #require(controller.tetris.active?.rotation)
        #expect(controller.canvasDragEnded(translation: .zero, at: Date()))
        #expect(controller.tetris.active?.rotation != before, "구동기가 이미 삼키고 있다 — 아래 화면 단언이 헛돈다")

        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 래치가 **판을 실제로 켰을 때만** 표시한다. 조건 없이 표시하면 진행 중이던 판의 탭까지 삼켜 회전이 사라진다.
        #expect(screen.contains(
            "if kind == .tetris, !wasPlaying, controller.isPlaying { swallowsTetrisDragEnd = value.startLocation }"))
        // 불리언이 아니라 **시작점**이다: `onEnded` 는 늘 오지 않는다(시스템 제스처·전화 수신으로 취소되면 안 온다).
        // 참인 채로 남으면 그다음 **멀쩡한 탭**의 회전이 대신 삼켜진다.
        #expect(screen.contains("@State private var swallowsTetrisDragEnd: CGPoint?"))
        #expect(screen.contains("guard swallowsTetrisDragEnd != value.startLocation else {"))
        #expect(!screen.contains("swallowsTetrisDragEnd = true") && !screen.contains("swallowsTetrisDragEnd: Bool"))
        // 갈래는 `kind` 가 아니라 **'진행 중인가'** 다 — 시작 화면에서는 테트리스도 래치가 판을 켠다
        // (트래커로만 받으면 tapMaxDuration 0.25초를 넘겨 천천히 뗀 사람에게 시작이 안 되고, 그건 '고장'으로 읽힌다).
        #expect(screen.contains("if kind == .tetris, controller.isPlaying {"))
        #expect(!screen.contains("if kind == .tetris {\n                    controller.canvasDragChanged"),
                "시작 화면에서도 트래커로 받는다 — 천천히 뗀 사람에게 판이 안 켜진다")
    }

    @Test("판이 **손가락 아래에서 끝나면** 그 접촉은 새 판을 못 켠다 — 시작 래치에 닿기 전에 소진된다")
    func aRoundThatEndsUnderTheFingerDoesNotRestartItself() throws {
        // ★ 기준선(이건 실제로 돌린다): 구동기는 스스로 막지 않는다 — 판이 끝난 뒤의 `tap()` 은 그대로 새 판을 켠다.
        //   그래서 "같은 손가락으로는 안 켜진다"가 **화면 몫**이고, 아래 소스 단언이 그 유일한 장치다.
        let controller = GamesPlayController(kind: .tetris, seed: 5)
        controller.updateCellWidth(20)
        controller.tap()
        controller.replaceForTesting(tetris: TetrisGame(seed: 5))
        #expect(!controller.isPlaying)
        controller.tap()
        #expect(controller.isPlaying, "구동기가 이미 막고 있다 — 아래 화면 단언이 헛돈다")

        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 트래커로 넘기는 접촉의 **시작점**을 들고 있어야 '이 손가락이 끌던 판이 끝났다'를 알아본다.
        #expect(screen.contains("@State private var tetrisPlayContact: CGPoint?"),
                "지금 조작 중인 접촉을 기억하지 않는다 — 판이 끝난 손가락을 알아볼 방법이 없다")
        #expect(screen.contains("tetrisPlayContact = value.startLocation"), "트래커로 넘기면서 접촉을 기록하지 않는다")
        #expect(screen.contains("if kind == .tetris, !controller.isPlaying, tetrisPlayContact == value.startLocation {"),
                "판이 끝난 그 접촉을 소진하지 않는다 — 같은 손가락의 다음 onChanged 가 시작 래치를 때린다")

        // 소진 표시는 **시작 래치보다 앞**이어야 한다. 뒤에 있으면 이미 새 판이 켜진 뒤라 아무것도 막지 못한다.
        let changed = try #require(screen.components(separatedBy: ".onChanged { value in").dropFirst().first,
                                   "캔버스 제스처의 onChanged 를 못 찾았다 — 이 검사가 빈 문자열을 보고 있다")
        let head = try #require(changed.components(separatedBy: ".onEnded").first)
        let consume = try #require(head.range(of: "tetrisPlayContact == value.startLocation"))
        let latch = try #require(head.range(of: "controller.tap()"))
        #expect(consume.lowerBound < latch.lowerBound, "소진 표시가 시작 래치 뒤에 있다 — 이미 새 판이 켜진 뒤다")

        // B5(같은 뿌리): 시작 래치가 켠 접촉은 `onEnded`(회전)뿐 아니라 **`onChanged`(이동·소프트드롭)도** 삼킨다.
        // 뗌만 삼키면 그 탭이 한 칸 폭 이상 흔들릴 때 새 판 첫 조각이 곧장 옆으로 간다.
        #expect(head.contains("swallowsTetrisDragEnd == value.startLocation { return }"),
                "래치가 켠 끌기의 **이동**을 안 삼킨다 — 뗌만 삼키면 B5 가 그대로 남는다")
        let swallow = try #require(head.range(of: "swallowsTetrisDragEnd == value.startLocation"))
        #expect(swallow.lowerBound < consume.lowerBound, "다 쓴 접촉 검사가 다른 갈래 뒤에 있다")
    }

    @Test("터치-다운 버튼의 눌림은 **접촉 신원**이다 — 취소로 `onEnded` 가 안 와도 다음 누름이 산다")
    func aCancelledTouchDoesNotKillTheTouchDownButtons() throws {
        let screen = try IntegrationContractTests.code(Self.screenPath)
        // 불리언 래치면 시스템 제스처·전화 한 번에 참인 채로 굳고, 그 버튼은 **화면을 떠날 때까지 죽는다.**
        #expect(screen.contains("@State private var pressedContact: CGPoint?"),
                "터치-다운 버튼의 눌림이 접촉 신원이 아니다")
        #expect(!screen.contains("@State private var isPressed = false") && !screen.contains("isPressed.toggle()"),
                "불리언 눌림 래치가 남아 있다 — 취소 한 번에 버튼이 영구히 죽는다")
        #expect(screen.contains("guard pressedContact != value.startLocation else { return }"),
                "같은 접촉의 두 번째 onChanged 가 또 발화한다(접촉당 한 번이어야 한다)")
        #expect(screen.contains("isPressed: pressedContact != nil"), "틴트가 눌림 상태를 안 따라간다")
        // 대조: 터치-업 쪽(즉시 내리기)은 표준 `Button` 이라 이 장치가 필요 없다 — 갈래가 살아 있는지 확인한다.
        #expect(screen.contains("if firesOnTouchDown {") && screen.contains("Button(action: action)"),
                "대조: 발화 시점 갈래가 사라졌다(이 검사가 헛돈다)")
    }

    @Test("`.inactive` 는 아무것도 안 한다 — 알림 센터를 내린 것으로 8분 판이 끝나면 안 된다")
    func pullingDownNotificationCentreDoesNotEndTheRound() throws {
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        let inactive = try #require(root.components(separatedBy: "case .inactive:").last)
        let head = String(inactive.prefix(200))
        #expect(head.contains("break"), "inactive 가 무언가를 한다")
        #expect(!head.contains("sceneDidEnterBackground"), "알림 센터를 내리면 판이 끝난다")
    }

    // MARK: - 게임별로 갈린 값(실제로 돌릴 수 있는 로직)

    @Test("토큰 재사용 나이: 테트리스는 12분에 죽고 플래피는 그 나이에 아직 살아 있다")
    func theTokenReuseAgeIsPerGame() async throws {
        #expect(MiniGameKind.tetris.roundTokenReuseSeconds == 12 * 60)
        #expect(MiniGameKind.flappy.roundTokenReuseSeconds == 20 * 60)
        #expect(MiniGameKind.timingBar.roundTokenReuseSeconds == 20 * 60)
        // 옛 상수는 **지우지 않았다**(기존 테스트가 그 이름을 읽는다) — 값만 새 칸을 가리킨다.
        #expect(GamesMiniGameHub.tokenRefreshSeconds == MiniGameKind.flappy.roundTokenReuseSeconds)
        // 검산: 서버 TTL 30 − 재사용 12 − 최장 판 8.7 = 여유 9.3분. 20분이면 여유가 1.3분뿐이다.
        #expect(30 * 60 - MiniGameKind.tetris.roundTokenReuseSeconds - 8.7 * 60 > 9 * 60)
        #expect(30 * 60 - MiniGameKind.flappy.roundTokenReuseSeconds - 8.7 * 60 < 2 * 60)

        let tetris = GamesHarness(label: "tetris-age")
        Self.configure(tetris)
        _ = gamesServeRoundTokens(tetris, prefix: "tok-age-t")
        await tetris.signIn()
        tetris.hub.openScreen(.tetris)
        #expect(await waits.wait { tetris.hub.roundToken == "tok-age-t-1" })
        tetris.clock.advance(12 * 60 - 60)
        #expect(tetris.hub.hasUsableRoundToken(for: .tetris), "12분 전인데 토큰을 버렸다")
        tetris.clock.advance(120)
        #expect(!tetris.hub.hasUsableRoundToken(for: .tetris), "12분이 지났는데 그 토큰을 또 쓴다 — 제출이 TTL 밖으로 나간다")
        await tetris.tearDown()

        // ★ 기준선이 다르다: **같은 나이**에서 플래피 토큰은 아직 쓸 만하다(안 그러면 이 검사가 게임별인지 알 수 없다).
        let flappy = GamesHarness(label: "flappy-age")
        Self.configure(flappy)
        _ = gamesServeRoundTokens(flappy, prefix: "tok-age-f")
        await flappy.signIn()
        flappy.hub.openScreen(.flappy)
        #expect(await waits.wait { flappy.hub.roundToken == "tok-age-f-1" })
        flappy.clock.advance(12 * 60 + 60)
        #expect(flappy.hub.hasUsableRoundToken(for: .flappy), "플래피까지 12분으로 줄었다 — 판이 짧은 게임의 여유를 버렸다")
        flappy.clock.advance(8 * 60)
        #expect(!flappy.hub.hasUsableRoundToken(for: .flappy))
        await flappy.tearDown()
    }

    @Test("로그아웃·화면 경합 정리는 테트리스 판을 **제출하지 않는다** — 같은 판을 뒤로가기로 끝내면 제출된다")
    func logoutAndScreenSwapThrowTheRoundAway() async throws {
        let harness = GamesHarness(label: "tetris-exits")
        Self.configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-exit")
        await harness.signIn()

        // ① 화면 경합 정리(다른 게임으로 갈아타기) — 아직 시작도 안 한 판을 치우는 자리다.
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken == "tok-exit-1" })
        let first = try #require(harness.hub.controller)
        first.tap()
        for _ in 0..<5 { first.softDropOneCell() }
        #expect(first.tetris.score == 5)
        harness.hub.openScreen(.flappy)
        await harness.barrier()
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "화면을 갈아타는 것만으로 점수가 나갔다")

        // ② 로그아웃 — 남의 계정으로 넘어가는 자리에서 앞 사람의 판을 제출하면 안 된다.
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken != nil })
        let second = try #require(harness.hub.controller)
        second.tap()
        for _ in 0..<4 { second.softDropOneCell() }
        harness.hub.reset()
        await harness.barrier()
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "로그아웃이 남의 계정에 점수를 올렸다")

        // ★ 기준선: **같은 플레이**를 뒤로가기로 끝내면 제출된다(그래야 위 둘이 '아무것도 안 한다'와 구별된다).
        harness.hub.openScreen(.tetris)
        #expect(await waits.wait { harness.hub.roundToken != nil })
        let third = try #require(harness.hub.controller)
        third.tap()
        for _ in 0..<4 { third.softDropOneCell() }
        harness.hub.closeScreen(.tetris)
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("제출 인편은 **세 게임 모두**에 걸린다 — 플래피 점수도 네트워크 실패에 그냥 사라지지 않는다")
    func thePendingSubmitCoversTheOtherGamesToo() async throws {
        let harness = GamesHarness(label: "flappy-pending")
        Self.configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-flap")
        let online = BaseLockedBox(false)
        harness.server.setDefault("minigame_submit_score") { _ in
            online.get() ? .json(#"{"status":"ok","best_score":12,"plays":1,"improved":true}"#) : .networkFailure()
        }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await waits.wait { harness.hub.roundToken == "tok-flap-1" })

        harness.hub.recordScore(kind: .flappy, score: 12)
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.hub.pendingSubmit?.token == "tok-flap-1", "플래피 점수가 네트워크 실패에 사라졌다")
        #expect(harness.hub.pendingSubmit?.kind == .flappy)

        // 연결이 돌아왔다. 사람이 앱을 나갔다가 다시 켠다 — 인편은 그때 다시 나간다.
        online.mutate { $0 = true }
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        #expect(await waits.wait { harness.server.requests("minigame_submit_score").count == 2 },
                "복귀했는데 인편을 다시 보내지 않았다")
        // ⚠️ 위 대기가 어긋나면 이 배열은 한 칸뿐이다. `[1]` 로 읽으면 `Index out of range`(signal 5)로
        //    **번들이 통째로 죽어** 뒤의 테스트가 아예 안 돌고 실패 목록도 안 찍힌다.
        let retry = try #require(harness.server.requests("minigame_submit_score").dropFirst().first,
                                 "재시도 요청이 없다 — 위 대기가 어긋났다")
        #expect(retry.bodyText.contains(#""p_token":"tok-flap-1""#), "재시도가 다른 토큰으로 나갔다")
        #expect(retry.bodyText.contains(#""p_game":"flappy""#))
        #expect(await waits.wait { harness.hub.pendingSubmit == nil })
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("문구는 **실제로 일어난 일**을 말한다 — 테트리스만 '여기까지 기록', 죽은 토큰은 복구를 약속하지 않는다")
    func theTextsSayWhatActuallyHappened() {
        // 테트리스에 "기록하지 않았어요"를 쓰면 거짓말이다 — 점수는 이미 나갔다.
        #expect(GamesMiniGameText.endedInBackground(.tetris) == "앱을 나가서 이번 판을 여기까지 기록했어요")
        for kind in [MiniGameKind.timingBar, .flappy] {
            #expect(GamesMiniGameText.endedInBackground(kind).contains("기록하지 않았어요"),
                    "\(kind.rawValue) 문구가 바뀌었다 — 이 둘은 지금도 점수를 버린다")
            #expect(GamesMiniGameText.endedInBackground(kind) != GamesMiniGameText.endedInBackground(.tetris))
        }
        // "다시 해 주세요"는 복구된다는 뜻인데 토큰이 죽었으면 그 판은 영영 못 올라간다.
        #expect(GamesMiniGameText.submitTokenDead != GamesMiniGameText.submitFailedConnection)
        #expect(GamesMiniGameText.submitFailedConnection.contains("다시 해 주세요"))
        #expect(!GamesMiniGameText.submitTokenDead.contains("다시 해 주세요"))
        // 캔버스 안내도 게임별로 갈렸다(테트리스만 탭이 회전이다).
        #expect(GamesMiniGameText.canvasAccessibility(.tetris).contains("회전"))
        #expect(!GamesMiniGameText.canvasAccessibility(.flappy).contains("회전"))
        // ⚠️ status 이름·need_seconds·elapsed_seconds 는 화면에 한 글자도 안 나간다(서버가 "위조 보조 도구"라고 경고해 뒀다).
        let shown = [GamesMiniGameText.submitTokenDead, GamesMiniGameText.submitRefused,
                     GamesMiniGameText.submitFailedConnection, GamesMiniGameText.endedInBackground(.tetris),
                     GamesMiniGameText.howToPlay(.tetris), GamesMiniGameText.canvasAccessibility(.tetris)]
        for text in shown {
            for leak in ["token_", "too_fast", "need_seconds", "elapsed_seconds", "invalid"] {
                #expect(!text.contains(leak), "화면 문구가 서버 진단을 흘린다: \(leak)")
            }
        }
    }

    // MARK: - 도우미

    private static let boardJSON = #"[{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":40,"best_at":"2026-09-23T04:00:00Z","plays":3,"center":"seoul"}]"#

    private static func configure(_ harness: GamesHarness) {
        harness.server.setDefault("minigame_board", json: boardJSON)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#)
    }
}
