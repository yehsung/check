import CheckCore
import CoreGraphics
import Foundation
#if os(iOS)
import CheckMobileShared
import SwiftUI
#endif

// 폰 1:1 테트리스 **대결 화면**(맥 `TetrisDuelPanel` 의 대결 절 · 폰 체스 `GamesChessMatch` 문법).
// 단계는 넷이다: 준비 대기 → 카운트다운 3·2·1 → 판 → 결과 카드. 단계를 정하는 것은 코어
// (`store.tetris.phase`)이고 이 파일은 **그리기와 손가락 전달**만 한다.
//
// ── 이 파일 위쪽 절반은 왜 `#if os(iOS)` 밖인가 ─────────────────────────────────────────────
// 폰 뷰는 맥 스위트가 한 줄도 못 본다(CheckMobileKit 의 절반이 `#if os(iOS)` — 저장소 메모 '폰 뷰는 맥
// 스위트가 못 본다'). 그런데 이 화면에는 **틀리면 판돈이 갈리는 판정**이 있다(입력을 받는가 · 결과 사유와
// 루비 · 기권 확인). 그래서 그 판정을 뷰 몸통이 아니라 **순수 표**(`GamesTetrisDuelChrome`)와 **순수 상자**
// (`GamesTetrisDuelTouch`)에 두고, 폰 없이도 값으로 재게 한다(체스 대국 화면이 먼저 쓴 구조다).
//
// ── 지키는 계약 ─────────────────────────────────────────────────────────────────────────────
//  ① ★ **판(`store.tetris.duel`)은 관찰 대상이 아니다**(`@ObservationIgnored`). 프레임마다 바뀌는 값이라
//     관찰하면 그 값을 읽는 모든 뷰가 매 걸음 무효화된다. 그래서 판 칸·떨어지는 조각을 읽는 자리는
//     **`TimelineView` 안 하나뿐**이고(`board(…)`), 조각이 굳을 때만 바뀌는 숫자는 관찰 가능한
//     `store.tetris.myStats` 로 읽는다. 맥 창의 머리 주석·잎 뷰와 같은 규율이다.
//  ② **프레임 루프는 화면이 보일 때만 돈다**(`paused:`). 판은 화면과 무관하게 스토어의 판 루프가 0.05초로
//     민다(D10) — 이 뷰의 틱은 "더 자주 그리기" 일 뿐이고 같은 시각이면 아무 일도 안 한다(따라잡기).
//  ③ **시간을 읽는 자리는 잎 뷰 셋뿐이다**(경과 시계 · 준비 남은 초 · 상대 침묵). 본문에서 초를 읽으면
//     그 값을 쓰는 모든 형제가 매초 다시 그려진다.
//  ④ ★ **"판 중에 앱을 나가면 져요" 는 판 위에 늘 있다**(P7 · `showsLeaveWarning`). 규칙 시트에만 두면 안
//     된다 — 판 중에 전화가 와서 나가는 사람은 규칙을 읽지 않는다. 사실 관계도 확인해 뒀다: iOS 가 앱을
//     멈추면 판 루프 Task 가 멎고 서버는 15초 침묵에 그쪽 패로 닫으며(D5), 돌아오면 따라잡기가 **30초까지만**
//     돌고 그 너머는 `droppedSeconds` 로 버린다(`TetrisDuelSession.advance`). 그래서 판을 멈추거나 시계를
//     되감지 않는다(D10 — 가리는 이득이 없어야 한다). 화면이 말하는 것이 유일한 방어다.
//  ⑤ **하드드롭에 제스처를 주지 않는다**(P9 — 솔로의 결정 그대로: 소프트드롭 끌기와 구분이 어렵고 오인식
//     한 번이 곧 판 종료다). 끌기·탭은 `TetrisGestureTracker`(순수) 가 판정하고, 엔진에 한 칸을 먹이는 길은
//     코어 문 셋(`moveLeftOneCell`·`moveRightOneCell`·`softDropOneCell`)뿐이다 — `setLeftHeld` 로 흉내 내지 마라.
//  ⑥ **조작 버튼에 확인 대화상자를 넣지 않는다**(바로 내리기에도): L15 부터 20G 라 조각이 스폰과 같은 틱에
//     접지하고 락딜레이가 0.16초다 — 확인창 한 번이 그 예산 전부다. **기권만** 확인을 받는다(판돈을 잃는다).
//  ⑦ **판돈·전적·루비는 서버가 말한 값만 쓴다.** 결과 카드의 사유는 코어 표(`TetrisDuelNoticeText.endReason`)
//     이고 루비 증감은 `match.rubyDelta`(없으면 `DuelFee` 로 같은 식) 다 — 맥과 같은 말·같은 숫자여야 한다.
//
// 탭 막대는 이 화면이 **숨기지 않는다**: `TabBarPolicy.Screen` 에 테트리스 갈래가 없고, 그 표는 이 레인의
// 파일이 아니다(갈래를 더하면 그 목록을 핀 박은 `BaseComponentTests` 가 빨개진다 — 남의 테스트다).
// 대신 배치가 **세로 예산을 스스로 맞춘다**(`boardBox` 의 aspect-fit): 막대를 숨기는 날 49pt 가 생기면
// 판이 그만큼 커질 뿐 이 파일은 고칠 데가 없다.

// MARK: - 색의 뜻

/// 화면 표가 말하는 색. `MobileTheme` 은 iOS 전용이라 이 표에 `Color` 를 둘 수 없다 — **뜻만** 두고 뷰가 토큰으로 옮긴다.
package enum GamesTetrisDuelTone: Equatable, Sendable {
    /// 초록 — 이김 · 내가 보낸 공격.
    case good
    /// 빨강 — 짐 · 꼭대기 · 들어올 줄.
    case bad
    /// 앰버 — 기다림 · 가속 · 연결 확인 중.
    case warn
    /// 회색 — 무승부 · 보조.
    case quiet
}

// MARK: - 화면 표 (순수 — 판돈이 갈리는 판정은 전부 여기)

/// 대결 화면이 그리는 것을 **값으로** 내놓는 표. 뷰는 이 표를 배치만 한다.
///
/// 시간에 따라 매초 바뀌는 값(경과 초 · 준비 남은 초 · 상대 침묵)은 **여기 들어오지 않는다** — 그 셋은
/// 잎 뷰가 아래 `static` 순수 함수로 그때그때 센다(계약 ③).
package struct GamesTetrisDuelChrome: Equatable, Sendable {
    /// 지금 어느 단계인가(코어 `TetrisDuelPhase` 에서 왔고 `.lobby` 는 이 화면이 뜨지 않는 단계다).
    package enum Stage: Equatable, Sendable { case waiting, countdown, playing, finished }

    /// 끝난 판 한 장.
    package struct Result: Equatable, Sendable {
        /// 이겼어요 / 졌어요 / 무승부예요.
        package let title: String
        /// 끝난 이유(코어 표 — 맥과 같은 문장).
        package let reason: String
        /// 이 판으로 내 루비가 변한 양. 서버가 말한 값이 있으면 그것이고, 없으면 승패에서 같은 식으로 센다.
        package let rubyDelta: Int
        package let rubyDeltaText: String
        package let tone: GamesTetrisDuelTone
        package let isDraw: Bool
    }

    /// 상대 보고가 이만큼 끊기면 "상대 연결 확인 중" 을 띄운다(서버 침묵 판정 15초의 1/3 — 1초 하트비트 서넛을
    /// 놓친 자리. 맥 `TetrisDuelOpponentPresence.silenceHintSeconds` 와 같은 값이다).
    package nonisolated static let opponentSilenceHintSeconds: TimeInterval = 5
    /// 준비 마감을 모를 때 보여 줄 기본 남은 초(서버 `tetris_ready_timeout_seconds()`).
    package nonisolated static let readyTimeoutSeconds = 30

    /// 상대 미니 판 한 칸(pt). **여기 있는 까닭**: 이 수가 판 폭을 깎고 판 폭이 곧 제스처 한 칸 문턱이다(P11) —
    /// 뷰에만 두면 맥 스위트가 못 보고(폰 뷰는 `#if os(iOS)`) 아무도 안 재는 수가 된다.
    ///
    /// ── 왜 5pt 인가(검산) ───────────────────────────────────────────────────────────────────
    /// 맥 기본값 9pt 는 세로 `9 × 20 + 2 × 2 = 184pt` 라 폰 머리글에 안 들어간다(SE 375×667 에서 쓸 세로가
    /// 554pt 뿐이고 그 안에 머리 띠 · 상대 줄 · 판 · 경고 줄 · 조작 줄이 다 서야 한다). 세 값을 재 봤다:
    ///   · 4pt → 44×84.  판 폭이 가장 넉넉하지만(SE 332pt) 0.5pt 안쪽 여백 뒤 칸이 **3pt** 라 여백이 칸의 12% 를
    ///     먹고, 0.5pt 격자선이 칸 틈과 비슷해져 "몇 줄 쌓였나" 가 흐려진다.
    ///   · **5pt → 54×104.** 칸이 4pt(여백 10%)로 남고 SE 판 폭이 343 → 304pt(−11%) 로만 줄어든다.
    ///     812pt 이상 화면(iOS 18 기기 대부분)에서는 **전혀 줄지 않는다**.
    ///   · 6pt → 64×124. 가장 잘 보이지만 SE 판 폭이 288pt(−16%)까지 줄어 한 칸 문턱이 12.8pt 가 된다
    ///     (솔로 폰 SE 가 15.3pt 다 — 같은 손가락에 감도가 달라진다).
    /// 가비지 회색은 미니 우물 대비 **7.26:1** 이다(테스트가 실제 색 값으로 센다 — 요구 3:1 의 두 배 넘는다).
    package nonisolated static let miniBoardCell: CGFloat = 5
    /// 미니 판이 머리글에서 먹을 수 있는 세로 상한(pt). 이 선을 넘으면 판이 300pt 아래로 깎인다.
    package nonisolated static let miniBoardHeightBudget: CGFloat = 110

    package let stage: Stage
    package let stake: Int
    /// "5 · 이기면 +5" — 이기면 받는 **순이익**(`DuelFee.winnerNet` — v0.3.64 부터 수수료 0)이라 결과 카드의 루비와 같은 숫자다.
    package let stakeLine: String
    /// ★ 화면이 손가락·버튼을 엔진으로 보내는가. 준비·카운트다운·탑아웃·끝에서는 거짓이다.
    /// 코어(`TetrisDuelSession.isLive`)가 이미 막지만 **화면도 눌림을 안 보내는 쪽**이 맞다 — 보내는 화면은
    /// 막는 쪽이 한 줄 바뀌면 조용히 되살아난다.
    package let acceptsInput: Bool
    /// ★ 판 위에 늘 보이는 경고(P7 · 계약 ④). 끝난 판에서만 내린다(그때는 나가도 잃을 것이 없다).
    package let showsLeaveWarning: Bool
    /// 2분이 지나 가속이 걸렸다(D7 — 레벨 바닥이 1 을 넘었다). 끝난 판에서는 내린다.
    package let showsSpeedUp: Bool
    /// 가속 바닥(표시용 — 10초마다 오른다).
    package let speedLevel: Int
    /// 내 보고가 연달아 실패하는 중(= 내 연결).
    package let connectionTrouble: Bool
    /// 상대 판 숫자 셋(스냅숏 — 보고 응답에서만 바뀐다).
    package let opponentLines: Int
    package let opponentAttack: Int
    package let opponentPending: Int
    /// 상대 이름.
    package let opponentName: String
    /// 상대가 꼭대기에 닿았다(미니 판 위 글자).
    package let opponentToppedOut: Bool
    /// 내가 꼭대기에 닿았다 — 판 위 덮개가 서고 입력이 끊긴다.
    package let toppedOut: Bool
    /// [기권] 을 그리는가. **카운트다운 중에도 참이다**(서버가 받는다 — D4 뒤의 판은 이미 판돈을 걷었다).
    package let canResign: Bool
    package let result: Result?
    /// 안내 한 줄(코어 `notice` — 신청·기권 응답 문구). 없으면 nil.
    package let notice: String?
    /// 같은 계정의 **다른 기기**가 두는 판이다(코어 `playingElsewhere` · 0.3.69 한 판 한 기기). 이 폰에는 구동기가 없어
    /// 단계가 `.waiting` 에 머문다 — 그래서 덮개가 "상대를 기다리는 중 · 앱을 켜 둔 채" 대신 그 사실을 말하고,
    /// "판 중에 앱을 나가면 져요" 를 걸지 않는다(이 폰이 나가도 아무도 지지 않는다). 끝난 판에서는 거짓이다.
    package let playingElsewhere: Bool

    /// - Parameters:
    ///   - match: 서버가 말한 판.
    ///   - phase: 코어 흐름.
    ///   - myStats: 내 판 숫자(조각이 굳을 때만 바뀐다). 판 구동기가 없으면 nil.
    ///   - playingElsewhere: 코어 `playingElsewhere`(다른 기기가 두는 판).
    package init(match: TetrisDuelMatchState, phase: TetrisDuelPhase, myStats: TetrisDuelMyStats?,
                 notice: String?, connectionTrouble: Bool, playingElsewhere: Bool = false) {
        let finished = match.isFinished || phase == .finished
        let stage: Stage
        switch phase {
        case .playing: stage = finished ? .finished : .playing
        case .countdown: stage = finished ? .finished : .countdown
        case .ready: stage = finished ? .finished : .waiting
        // `.lobby` 로 떨어지는 길은 실질적으로 없다(이 화면은 판이 있을 때만 선다) — 떨어지면 끝난 판으로 읽는다.
        case .finished, .lobby: stage = .finished
        }
        self.stage = stage
        stake = match.stake
        stakeLine = TetrisPhoneText.stakeLine(match.stake)
        toppedOut = myStats?.toppedOut ?? false
        // ★ 입력은 **판이 흐르는 동안만**이다. 탑아웃한 판은 서버 응답을 기다리는 중이고 조각이 없다.
        acceptsInput = stage == .playing && !(myStats?.toppedOut ?? false)
        let elsewhere = playingElsewhere && stage != .finished
        self.playingElsewhere = elsewhere
        showsLeaveWarning = stage != .finished && !elsewhere
        let floor = myStats?.levelFloor ?? 1
        showsSpeedUp = floor > 1 && stage != .finished
        speedLevel = floor
        self.connectionTrouble = connectionTrouble && stage != .finished
        opponentLines = match.opponentBoard.lines
        opponentAttack = match.opponentBoard.attackSent
        opponentPending = match.opponentBoard.pending
        opponentName = match.opponent.displayName
        opponentToppedOut = match.opponentBoard.toppedOut
        canResign = stage != .finished
        result = finished ? Self.result(match) : nil
        // 덮개 카드 제목이 이미 그 안내다 — 같은 줄을 판 밑에 두 번 쓰지 않는다(맥 `detail` 과 같은 규칙).
        self.notice = elsewhere && notice == TetrisDuelNoticeText.otherDevice ? nil : notice
    }

    /// 끝난 판 한 장(순수). 사유는 **코어 표**이고 루비는 서버 값 우선이다(계약 ⑦).
    package nonisolated static func result(_ match: TetrisDuelMatchState) -> Result {
        let outcome = match.outcome
        let delta: Int
        if let given = match.rubyDelta {
            delta = given
        } else {
            switch outcome {
            case .won?: delta = DuelFee.winnerNet(stake: match.stake)
            case .lost?: delta = -match.stake
            case .draw?, nil: delta = 0
            }
        }
        let tone: GamesTetrisDuelTone
        switch outcome {
        case .won?: tone = .good
        case .lost?: tone = .bad
        case .draw?, nil: tone = .quiet
        }
        return Result(title: TetrisPhoneText.outcomeTitle(outcome),
                      reason: TetrisDuelNoticeText.endReason(match.endReason, outcome: outcome),
                      rubyDelta: delta, rubyDeltaText: TetrisPhoneText.rubyDelta(delta),
                      tone: tone, isDraw: outcome == .draw)
    }

    /// 판 위 덮개가 설 자리인가 — 준비·카운트다운·탑아웃·결과. 판이 흐르는 동안에는 아무것도 덮지 않는다.
    package var showsBoardOverlay: Bool {
        switch stage {
        case .waiting, .countdown, .finished: return true
        case .playing: return toppedOut
        }
    }

    /// 판 그림의 보이스오버 한 줄. **느린 값만**(지운 줄 · 들어올 줄) — 조각·행·열은 L1 0.355초/칸으로 바뀌어
    /// 읽어 주는 동안 이미 틀린 값이 된다(솔로 캔버스와 같은 규약).
    package nonisolated static func boardAccessibility(lines: Int, pendingGarbage: Int) -> String {
        "\(TetrisPhoneText.myBoardLabel), \(TetrisPhoneText.linesTitle) \(lines), "
            + "\(TetrisPhoneText.incomingLinesTitle) \(pendingGarbage)"
    }

    // MARK: 시간을 읽는 셋 — **잎 뷰 전용**(계약 ③)

    /// 판 시계가 보여 줄 경과초. 끝난 판은 **엔진에 흘린 판 시간**에서 멈춘다 — 단조 시계로 재면 결과 화면에서도
    /// 경과가 계속 자란다(맥이 같은 자리에서 고친 것).
    package nonisolated static func elapsedSeconds(stage: Stage, matchElapsed: TimeInterval?,
                                                   simulated: TimeInterval?) -> TimeInterval {
        if stage == .finished { return max(0, simulated ?? 0) }
        return max(0, matchElapsed ?? 0)
    }

    /// 카운트다운 숫자(3·2·1). 남은 초를 **올림**해서 1 아래로 안 내려간다 — 0 을 보여 주면 "시작했는데 안 움직인다"가 된다.
    package nonisolated static func countdownDigit(remaining: TimeInterval?) -> Int {
        max(1, Int((remaining ?? 0).rounded(.up)))
    }

    /// 준비 마감까지 남은 초. 마감을 모르면 서버 기본값(30).
    package nonisolated static func readySecondsLeft(deadline: Date?, now: Date) -> Int {
        guard let deadline else { return readyTimeoutSeconds }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    /// 상대 보고가 끊겼는가. 끝난 판·아직 준비 전인 상대는 **침묵이 아니다**(그때는 할 말이 따로 있다).
    package nonisolated static func opponentIsSilent(silenceSeconds: TimeInterval?, opponentReady: Bool,
                                                     stage: Stage) -> Bool {
        guard stage != .finished, opponentReady else { return false }
        return (silenceSeconds ?? 0) >= opponentSilenceHintSeconds
    }

    /// 상대 상태 한 줄. "준비 완료" 는 판이 서기 전까지만 — 판 중·끝난 뒤에도 남으면 상대가 아직 안 들어온 것처럼 읽힌다.
    package nonisolated static func opponentStatus(board: TetrisDuelOpponentBoard, stage: Stage) -> String {
        if board.toppedOut { return TetrisPhoneText.toppedOutTitle }
        if !board.ready { return TetrisPhoneText.notReady }
        switch stage {
        case .finished: return TetrisPhoneText.finishedPresence
        case .playing: return TetrisPhoneText.playingNow
        case .waiting, .countdown: return TetrisPhoneText.ready
        }
    }
}

// MARK: - 손가락 (순수 상자 — 맥 스위트가 좌표부터 조각까지 구동한다)

/// 판 위 한 손가락(끌기·탭)을 엔진 걸음으로 옮긴다. 뷰 `@State` 가 **참조로** 들고 있다.
///
/// ── 왜 뷰 `@State` 의 값(구조체)이 아니라 상자인가 ──────────────────────────────────────────
/// ① `TetrisGestureTracker` 는 값 타입이고 `drag(…)` 이 소비량을 쓴다 — `@State` 에 값으로 두면 **터치
///    이벤트마다 body 가 재평가된다**(120Hz). 참조 상자에 쓰면 뷰가 무효화되지 않는다.
/// ② `DragGesture.Value` 에는 **시작 시각이 없다**(`time`·`location`·`startLocation`·`translation`·`velocity`
///    뿐) — 탭 판정의 elapsed 를 내려면 누군가 첫 `time` 을 기억해야 한다. 그 자리가 여기다.
/// ③ 이 타입에는 `#if os(iOS)` 가 없다 — 그래서 macOS `swift test` 가 **손가락 좌표 → 조각 위치**를 화면 없이
///    구동한다. 솔로 폰은 같은 일을 `GamesPlayController` 가 한다(그 파일은 이 레인이 건드리지 않는다).
package final class GamesTetrisDuelTouch {
    private var tracker: TetrisGestureTracker
    /// 지금 따라가는 접촉의 시작점 — 새 끌기를 알아보는 기준(`onEnded` 는 늘 오지 않는다).
    private var startLocation: CGPoint?
    private var startedAt: Date?

    package init(cellWidth: CGFloat = TetrisLayout.cell) {
        tracker = TetrisGestureTracker(thresholds: TetrisGestureThresholds(cellWidth: cellWidth))
    }

    /// 한 칸 문턱을 화면 셀 폭으로 갈아 끼운다(논리 13 × 그려진 배율 — P11).
    package func updateCellWidth(_ width: CGFloat) {
        tracker.updateCellWidth(width)
    }

    /// `onChanged` — 새로 생긴 걸음을 **그 자리에서** 엔진에 먹인다.
    ///
    /// ⚠️ 걸음 사이·가로 걸음의 누름/뗌 쌍 사이에 `tick`·`advance` 를 끼우지 마라 — 그 순간 자동 반복이
    /// 살아나 한 걸음이 여러 칸이 된다(코어 `moveLeftOneCell` 주석의 그 자리다). 코어 문 하나가 쌍을 통째로 쥔다.
    @MainActor
    package func changed(startLocation: CGPoint, translation: CGSize, at time: Date, into store: TetrisDuelStore) {
        if self.startLocation != startLocation {
            self.startLocation = startLocation
            startedAt = time
        }
        for step in tracker.drag(startLocation: startLocation, translation: translation) {
            Self.feed(step, into: store)
        }
    }

    /// `onEnded` — 탭(8pt 미만 · 0.25초 안)이면 **시계 회전**이다.
    /// - Returns: 이 끌기가 탭이었는가(회전을 시도했는가).
    @MainActor
    @discardableResult
    package func ended(translation: CGSize, at time: Date, into store: TetrisDuelStore) -> Bool {
        let elapsed = startedAt.map { max(0, time.timeIntervalSince($0)) } ?? 0
        startLocation = nil
        startedAt = nil
        guard tracker.end(translation: translation, elapsed: elapsed) else { return false }
        store.rotate(clockwise: true)
        return true
    }

    /// 화면이 사라졌다·앱이 내려갔다·판이 끝났다 — 잠금과 소비량을 비운다(안 비우면 앞 끌기의 축 잠금이 다음 판으로 샌다).
    package func reset() {
        _ = tracker.end(translation: .zero, elapsed: 0)
        startLocation = nil
        startedAt = nil
    }

    /// 걸음 하나 → 코어 문 하나. **`setLeftHeld` 로 흉내 내지 마라**(P9): 제스처는 거리를 주고 눌린 시간을 주지 않는다.
    @MainActor
    package static func feed(_ step: TetrisGestureStep, into store: TetrisDuelStore) {
        switch step {
        case .moveLeft: store.moveLeftOneCell()
        case .moveRight: store.moveRightOneCell()
        case .softDrop: store.softDropOneCell()
        }
    }
}

#if os(iOS)

// MARK: - 대결 화면

/// 준비 → 카운트다운 → 판 → 결과 한 화면. 로비 레인이 `store.tetris.phase != .lobby` 일 때 이 뷰를 그린다
/// (**이 이름과 초기화 서명은 계약이다** — 바꾸면 로비가 안 컴파일된다).
///
/// 배치(위에서 아래로): 머리 띠(판돈 · 경과 · 가속 · 기권) → 상대 줄(미니 판 + 숫자) → **내 판** →
/// 경고 줄(★ P7) → 조작 셋 또는 결과 카드. 판은 남은 세로를 **aspect-fit** 으로 먹으므로 작은 화면에서도
/// 조작 줄이 잘리지 않는다(체스가 데인 자리: 큰 글자에서 아래 버튼이 화면 마지막 픽셀까지 칠해진 채 잘렸다).
struct GamesTetrisDuelMatchView: View {
    let store: GamesStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshHz = MiniGameFrameRate.baselineFPS
    @State private var confirmsResign = false
    /// 판 위 한 손가락. **관찰 대상이 아닌 참조 상자**라 터치마다 body 가 다시 돌지 않는다.
    @State private var touch = GamesTetrisDuelTouch()

    /// 판 구동기가 아직 없을 때(시드를 받기 전) 그릴 빈 판 — 맥 창과 같은 자리표시다.
    private static let placeholder = TetrisGame(seed: 0)

    private var tetris: TetrisDuelStore { store.tetris }

    var body: some View {
        if let match = tetris.match {
            matchBody(match: match,
                      chrome: GamesTetrisDuelChrome(match: match, phase: tetris.phase, myStats: tetris.myStats,
                                                    notice: tetris.notice,
                                                    connectionTrouble: tetris.connectionTrouble,
                                                    playingElsewhere: tetris.playingElsewhere))
                // 탭 막대를 숨긴다(체스·오목 판과 같은 수단 · `TabBarPolicy.tetrisMatch`). 까닭이 더 세다:
                // 판 시간이 단조 시계로 흐르므로(D10) 탭을 잘못 눌러 나가면 **안 보이는 채로 조각이 계속
                // 떨어진다** — 판돈이 걸린 판이다. 작은 화면(SE)에서는 그 49pt 가 판 폭으로 돌아온다.
                .hidesTabBar(for: .tetrisMatch)
        }
    }

    private func matchBody(match: TetrisDuelMatchState, chrome: GamesTetrisDuelChrome) -> some View {
        VStack(spacing: MobileTheme.space2) {
            topStrip(chrome)
            opponentRow(match: match, chrome: chrome)
            boardBox(chrome: chrome)
            if chrome.showsLeaveWarning {
                warningRow(chrome)
            }
            if let notice = chrome.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let result = chrome.result {
                resultCard(result)
            } else {
                controls(chrome)
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, MobileTheme.space2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MobileTheme.background.ignoresSafeArea())
        .onAppear { refreshHz = GamesDisplay.maximumFramesPerSecond }
        // 화면을 떠나면 눌린 것을 놓고 손가락 상태를 비운다. **기권이 아니다** — 판은 서버에서 계속 흐른다
        // (수명은 로비 레인의 `tetrisScreenDidDisappear()` 가 쥔다).
        .onDisappear {
            touch.reset()
            tetris.releaseAllKeys()
        }
        // app background: 판은 멎지만(그래서 경고 줄이 있다) 눌린 것은 놓는다 — 돌아왔을 때 유령 입력이 남지 않게.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            touch.reset()
            tetris.releaseAllKeys()
        }
        .onChange(of: match.id) { _, _ in
            confirmsResign = false
            touch.reset()
        }
        // 확인은 **불투명 시트**로(오목·체스가 데인 자리 — 확인 대화상자는 iOS 26 에서 위쪽 말풍선으로 떠
        // [계속하기]가 안 보였고, 알림창은 재질이 색을 빨아들여 대비가 1.9:1 이었다).
        .sheet(isPresented: $confirmsResign) {
            AingConfirmSheet(
                title: TetrisPhoneText.resignConfirmTitle,
                message: TetrisPhoneText.resignWarning,
                confirmTitle: TetrisPhoneText.confirmResign,
                cancelTitle: TetrisPhoneText.keepPlaying,
                onConfirm: {
                    confirmsResign = false
                    Task { await tetris.resign() }
                },
                onCancel: { confirmsResign = false })
        }
    }

    // MARK: 머리 띠

    /// 판돈 · 경과 시계(잎) · 가속 칩 · [기권]. 좁은 화면(SE 343pt)에서 가속 칩이 **짧은 꼴로 접힌다** —
    /// 보이스오버는 접히기 전 문장을 그대로 읽는다.
    private func topStrip(_ chrome: GamesTetrisDuelChrome) -> some View {
        HStack(spacing: MobileTheme.space2) {
            chip(icon: nil, tint: MobileTheme.label) {
                HStack(spacing: 3) {
                    RubyIcon(size: 13)
                    Text(chrome.stakeLine)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TetrisPhoneText.stakeTitle) \(chrome.stakeLine)")
            // 내 판을 보고 있는 사람 수(0.3.65 — 명세 §3 '대국자 본인 화면: 판돈 칩 줄에 같이').
            // 0 이면 서지 않으므로 띠의 폭 예산(SE 에서 칩 넷)은 **관전자가 붙을 때만** 한 칸 늘어난다.
            GamesWatcherBadge(count: tetris.spectatorCount, font: .footnote.weight(.semibold))
            GamesTetrisDuelElapsedLeaf(store: tetris, stage: chrome.stage)
            if chrome.showsSpeedUp {
                speedChip(chrome)
            }
            Spacer(minLength: 0)
            if chrome.canResign {
                AingButton(TetrisPhoneText.resign, systemImage: "flag", kind: .destructive, size: .sm,
                           role: .destructive) {
                    confirmsResign = true
                }
                // ★ **줄이 깨지지 않는다**(`fixedSize` + 우선권). 안 걸면 SE(375pt)에서 칩이 넷일 때
                //   (판돈 · 경과 · 가속 · 기권) HStack 이 이 버튼부터 좁혀 글자가 "기 / 권" 두 줄로 쪼개진다 —
                //   헤드리스 스틸로 실제로 그 꼴을 봤다(`se-light-match-speedup`). 가속 칩이 먼저 짧은 꼴로
                //   접히는 것이 맞다(레벨은 판 안에도 "Lv N" 으로 있다).
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .accessibilityHint(TetrisPhoneText.resignWarning)
            }
        }
        // 머리 띠는 판 예산을 깎는 자리라 큰 글자에서도 한 줄을 지킨다(값은 칩 안에서 줄어든다).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func speedChip(_ chrome: GamesTetrisDuelChrome) -> some View {
        ViewThatFits(in: .horizontal) {
            chipText(TetrisPhoneText.speedUp + " · " + TetrisPhoneText.speedLevel(chrome.speedLevel))
            chipText(TetrisPhoneText.speedLevel(chrome.speedLevel))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TetrisPhoneText.speedUp + " " + TetrisPhoneText.speedLevel(chrome.speedLevel))
    }

    private func chipText(_ text: String) -> some View {
        chip(icon: "hare.fill", tint: MobileTheme.pending) {
            Text(text).monospacedDigit().lineLimit(1)
        }
    }

    private func chip<Content: View>(icon: String?, tint: Color,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).accessibilityHidden(true)
            }
            content()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, MobileTheme.space2)
        .frame(minHeight: 28)
        .background(Capsule().fill(MobileTheme.fill))
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: 상대 줄 (미니 판은 **위쪽 상대 줄 안**이다 — P11)

    /// 미니 판(54×104) + 이름 · 상태(잎) · 숫자 셋. 미니 판을 **내 판 옆에 세우지 않는다** — 세우면 캔버스가
    /// 좁아져 제스처 한 칸 문턱(= 화면 셀 폭)이 바뀐다.
    private func opponentRow(match: TetrisDuelMatchState, chrome: GamesTetrisDuelChrome) -> some View {
        HStack(alignment: .top, spacing: MobileTheme.space3) {
            ZStack {
                GamesTetrisDuelMiniBoard(cells: match.opponentBoard.cells)
                if chrome.opponentToppedOut {
                    Text(TetrisPhoneText.toppedOutTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MobileTheme.danger)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            VStack(alignment: .leading, spacing: MobileTheme.space1) {
                HStack(spacing: 6) {
                    CharacterPortrait(id: match.opponent.characterID,
                                      mood: match.opponent.isWorking ? .working : .off, size: 26)
                    Text(chrome.opponentName)
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                GamesTetrisDuelPresenceLeaf(store: tetris, board: match.opponentBoard, stage: chrome.stage)
                Spacer(minLength: 0)
                stat(TetrisPhoneText.linesTitle, chrome.opponentLines, tint: MobileTheme.label)
                stat(TetrisPhoneText.attackTitle, chrome.opponentAttack, tint: MobileTheme.working)
                stat(TetrisPhoneText.incomingLinesTitle, chrome.opponentPending,
                     tint: chrome.opponentPending > 0 ? MobileTheme.danger : MobileTheme.label2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: GamesTetrisDuelMiniBoard.size.height)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// 숫자 한 줄(제목 왼쪽 · 값 오른쪽).
    private func stat(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MobileTheme.label2)
            Spacer(minLength: 2)
            Text(String(value))
                .font(MobileTheme.roundedNumber(.subheadline, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 내 판

    /// 판 상자 — 남은 세로를 **aspect-fit** 으로 먹는다(292:302). 그래서 작은 화면에서는 판이 줄어들고
    /// 조작 줄·경고 줄은 **언제나 화면 안**이다. 한 칸 문턱은 그려진 배율에서 그때 다시 센다(한 출처).
    private func boardBox(chrome: GamesTetrisDuelChrome) -> some View {
        GeometryReader { box in
            let scale = min(box.size.width / TetrisLayout.logicalSize.width,
                            box.size.height / TetrisLayout.logicalSize.height)
            board(chrome: chrome)
                .frame(width: box.size.width, height: box.size.height)
                .onChange(of: scale, initial: true) { _, resolved in
                    touch.updateCellWidth(TetrisLayout.cell * resolved)
                }
        }
        .aspectRatio(TetrisLayout.logicalSize.width / TetrisLayout.logicalSize.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ★ 판을 읽는 **유일한** 자리(계약 ①). 프레임마다 `store.tetris.tick()` 을 불러 판을 지금까지 미는데,
    /// 판 루프가 0.05초마다 같은 일을 하므로 이 틱이 없어도 판은 흐른다(화면이 숨으면 이쪽이 멈춘다 — 계약 ②).
    private func board(chrome: GamesTetrisDuelChrome) -> some View {
        let live = tetris.isWindowVisible && (chrome.stage == .countdown || chrome.stage == .playing)
        return TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz),
                                       paused: !live)) { context in
            let game = tetris.duel?.game ?? Self.placeholder
            ZStack {
                GamesTetrisDuelCanvas(game: game, reduceMotion: reduceMotion)
                if chrome.showsBoardOverlay {
                    overlay(chrome)
                }
            }
            .onChange(of: context.date) { _, _ in
                tetris.tick()
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MobileTheme.separator, lineWidth: 1))
        .contentShape(Rectangle())
        // ⚠️ `.gesture` 는 **이 자리 하나**다. `if chrome.acceptsInput` 으로 모디파이어 자체를 갈라 붙이면 뷰
        //    정체성이 갈려 SwiftUI 가 제스처를 다시 만든다(진행 중인 끌기가 통째로 끊긴다) — 갈래는 클로저 **안**이다.
        .gesture(boardDrag(chrome))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesTetrisDuelChrome.boardAccessibility(lines: tetris.myStats?.lines ?? 0,
                                                                     pendingGarbage: tetris.myStats?.pendingGarbage ?? 0))
        // 기본 액션은 **시계 회전**이다(탭과 같다). 판 어디든 겨냥하라는 뜻이 아니므로 직접 조작 트레잇은 걸지 않는다 —
        // 셀이 13~15pt 인 판에서 눈 없이 겨냥하는 것은 실질 조작이 아니다(솔로와 같은 판단).
        .accessibilityAction { if chrome.acceptsInput { tetris.rotate(clockwise: true) } }
        .accessibilityActions { moveActions(chrome) }
        // 판 안 글자는 판 배율을 따른다 — 시스템 글자 크기에 끌려가면 판을 넘친다.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    /// 판 위 한 번의 접촉. 솔로와 달리 **시작 래치가 없다**(대결 판은 서버가 켠다) — 탭은 회전뿐이다.
    private func boardDrag(_ chrome: GamesTetrisDuelChrome) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard chrome.acceptsInput else { return }
                touch.changed(startLocation: value.startLocation, translation: value.translation,
                              at: value.time, into: tetris)
            }
            .onEnded { value in
                guard chrome.acceptsInput else {
                    touch.reset()
                    return
                }
                touch.ended(translation: value.translation, at: value.time, into: tetris)
            }
    }

    /// 보이스오버 이동 액션 셋. **버튼이 이미 있는 조작은 중복시키지 않는다**(홀드·반대로·바로 내리기는 진짜 버튼이다).
    @ViewBuilder
    private func moveActions(_ chrome: GamesTetrisDuelChrome) -> some View {
        if chrome.acceptsInput {
            Button(GamesMiniGameText.tetrisMoveLeft) { announceColumn { tetris.moveLeftOneCell() } }
            Button(GamesMiniGameText.tetrisMoveRight) { announceColumn { tetris.moveRightOneCell() } }
            Button(GamesMiniGameText.tetrisSoftDrop) { announceDrop() }
        }
    }

    private func announceColumn(_ move: () -> Void) {
        move()
        guard let column = tetris.duel?.game.active?.cells.map({ $0.column }).min() else { return }
        AccessibilityNotification.Announcement(GamesMiniGameText.tetrisColumnAnnouncement(column + 1)).post()
    }

    private func announceDrop() {
        let before = tetris.duel?.game.active?.row
        tetris.softDropOneCell()
        let moved = tetris.duel?.game.active?.row != before
        AccessibilityNotification.Announcement(GamesMiniGameText.tetrisDropAnnouncement(moved: moved)).post()
    }

    // MARK: 판 위 덮개

    @ViewBuilder
    private func overlay(_ chrome: GamesTetrisDuelChrome) -> some View {
        switch chrome.stage {
        case .waiting where chrome.playingElsewhere:
            // 같은 계정의 다른 기기가 두는 판 — 이 폰에는 판이 없다(코어가 구동기를 안 만든다). 기다리라는 말 대신 사실을
            // 말한다(맥 대결 창의 같은 갈래와 같은 카드 · 색도 같은 `CheckTheme.accent` — 카드 기본값).
            GamesOverlayCard(title: TetrisDuelNoticeText.otherDevice,
                             subtitle: TetrisPhoneText.otherDeviceSubtitle,
                             action: TetrisPhoneText.otherDeviceAction,
                             icon: "macbook.and.iphone", scale: 0.9)
        case .waiting:
            // 남은 초는 **잎**이 센다(계약 ③) — 카드 한 장만 매초 다시 그려진다.
            GamesTetrisDuelWaitLeaf(store: tetris) { seconds in
                GamesOverlayCard(title: TetrisPhoneText.waitingTitle,
                                 subtitle: TetrisPhoneText.waitingSubtitle(seconds: seconds),
                                 action: TetrisPhoneText.waitingAction,
                                 icon: "hourglass", tint: MobileTheme.pending, scale: 0.9)
            }
        case .countdown:
            let digit = GamesTetrisDuelChrome.countdownDigit(remaining: tetris.countdownSeconds())
            VStack(spacing: 2) {
                Text(String(digit))
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                Text(TetrisPhoneText.startingSoon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TetrisPhoneText.startingSoon) \(digit)")
        case .playing:
            // 탑아웃 — 내 판은 끝났고 서버 응답을 기다리는 중이다(입력도 이때 끊긴다).
            GamesOverlayCard(title: TetrisPhoneText.toppedOutTitle,
                             subtitle: TetrisPhoneText.toppedOutSubtitle,
                             action: TetrisPhoneText.playingNow,
                             icon: "exclamationmark.triangle.fill", tint: MobileTheme.danger, scale: 0.9)
        case .finished:
            // 결과는 **아래 카드**가 말한다(판은 그대로 보인다 — 마지막 판이 눈에 남아야 한다). 여기는 판을 어둡게만 덮는다.
            Color.black.opacity(0.35).allowsHitTesting(false)
        }
    }

    // MARK: 경고 줄 (★ P7 — 판 위에 늘 있다)

    /// 내 이름 + ★ "판 중에 앱을 나가면 져요" + 연결 확인 중. 경고가 **먼저** 자리를 가진다(이름은 줄어든다).
    private func warningRow(_ chrome: GamesTetrisDuelChrome) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MobileTheme.space2) {
            Text(meLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MobileTheme.label2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(0)
            Spacer(minLength: 0)
            if chrome.connectionTrouble {
                Label(TetrisPhoneText.connectionTrouble, systemImage: "wifi.exclamationmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MobileTheme.danger)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Label(TetrisPhoneText.leaveWarning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(MobileTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
    }

    /// 머리글의 내 이름("나" 는 이름을 모를 때의 이름이다 — 게임 탭이 아는 값만 쓴다, 새 서버 호출 없음).
    private var meLabel: String {
        let me = GamesMeIdentity.current(store.context)
        guard let name = me.name else { return TetrisPhoneText.me }
        return name + " · " + TetrisPhoneText.me
    }

    // MARK: 조작 셋 · 결과 카드

    /// [홀드][반대로][바로 내리기] — 솔로와 **같은 셋**이고 간격을 뺀 쓸 폭을 26 : 30 : 44 로 나눈다.
    /// 확인 대화상자는 없다(계약 ⑥). 판이 살아 있지 않으면 눌려도 아무 일이 없다(화면 가드 + 코어 `isLive`).
    private func controls(_ chrome: GamesTetrisDuelChrome) -> some View {
        GeometryReader { row in
            let usable = max(0, row.size.width - MobileTheme.space2 - MobileTheme.space4)
            HStack(spacing: 0) {
                GamesTetrisDuelControlButton(title: TetrisPhoneText.holdButton, icon: "square.on.square",
                                             width: usable * 0.26,
                                             isSpent: tetris.duel?.game.holdUsed ?? false,
                                             firesOnTouchDown: true) {
                    guard chrome.acceptsInput else { return }
                    tetris.hold()
                }
                // 죽은 간격이다 — Spacer 는 히트 영역이 없다(버튼 쪽으로 넓히지 마라).
                Spacer(minLength: 0).frame(width: MobileTheme.space2)
                GamesTetrisDuelControlButton(title: TetrisPhoneText.rotateCounterButton, icon: "rotate.left",
                                             width: usable * 0.30, firesOnTouchDown: true) {
                    guard chrome.acceptsInput else { return }
                    tetris.rotate(clockwise: false)
                }
                Spacer(minLength: 0).frame(width: MobileTheme.space4)
                GamesTetrisDuelControlButton(title: TetrisPhoneText.hardDropButton, icon: "arrow.down.to.line",
                                             width: usable * 0.44, firesOnTouchDown: false) {
                    guard chrome.acceptsInput else { return }
                    tetris.hardDrop()
                }
            }
            .frame(width: row.size.width)
        }
        .frame(height: GamesTetrisDuelControlButton.height)
        // 판 안 글자와 달리 버튼 줄은 시스템 글자를 따라가되, 접근성 크기에서 화면 밖으로 밀리지 않게 막는다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// 승/패/무 · 사유 · 루비 증감 · [로비로]. 판은 **그대로 위에 남는다**(마지막 판이 보인다).
    private func resultCard(_ result: GamesTetrisDuelChrome.Result) -> some View {
        InsetGroup {
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                HStack(spacing: MobileTheme.space2) {
                    Image(systemName: Self.icon(result.tone))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Self.color(result.tone))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(MobileTheme.title(.title3))
                            .foregroundStyle(Self.color(result.tone))
                        if !result.reason.isEmpty {
                            Text(result.reason)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        RubyIcon(size: 20)
                            .opacity(result.rubyDelta < 0 ? 0.5 : 1)
                        Text(result.rubyDeltaText)
                            .font(MobileTheme.number(.title3, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(result.rubyDelta > 0 ? MobileTheme.working
                                             : (result.rubyDelta < 0 ? MobileTheme.danger : MobileTheme.label))
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                }
                AingButton(TetrisPhoneText.backToLobby, kind: .gray, size: .md, fillsWidth: true) {
                    tetris.backToLobby()
                }
            }
            .padding(MobileTheme.cardPadding)
        }
    }

    private static func color(_ tone: GamesTetrisDuelTone) -> Color {
        switch tone {
        case .good: return MobileTheme.working
        case .bad: return MobileTheme.danger
        case .warn: return MobileTheme.pending
        case .quiet: return MobileTheme.label2
        }
    }

    private static func icon(_ tone: GamesTetrisDuelTone) -> String {
        switch tone {
        case .good: return "trophy.fill"
        case .bad: return "xmark.circle.fill"
        case .warn: return "hourglass"
        case .quiet: return "equal.circle.fill"
        }
    }
}

// MARK: - 잎 뷰 셋 (시간을 읽는 **유일한** 자리 — 계약 ③)

/// 경과 시계. 화면이 안 보이거나 판이 아니면 멈춘다.
struct GamesTetrisDuelElapsedLeaf: View {
    let store: TetrisDuelStore
    let stage: GamesTetrisDuelChrome.Stage

    var body: some View {
        let live = store.isWindowVisible && stage == .playing
        TimelineView(.animation(minimumInterval: 0.5, paused: !live)) { _ in
            let elapsed = GamesTetrisDuelChrome.elapsedSeconds(stage: stage,
                                                               matchElapsed: store.matchElapsedSeconds(),
                                                               simulated: store.duel?.simulated)
            HStack(spacing: 4) {
                Image(systemName: "timer").accessibilityHidden(true)
                Text(TetrisPhoneText.clock(elapsed)).monospacedDigit()
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(MobileTheme.label)
            .padding(.horizontal, MobileTheme.space2)
            .frame(minHeight: 28)
            .background(Capsule().fill(MobileTheme.fill))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TetrisPhoneText.elapsedTitle) \(TetrisPhoneText.clock(elapsed))")
        }
    }
}

/// 준비 마감까지 남은 초를 1초마다 센다(덮개 카드 한 장만 다시 그린다).
struct GamesTetrisDuelWaitLeaf<Content: View>: View {
    let store: TetrisDuelStore
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !store.isWindowVisible)) { _ in
            content(GamesTetrisDuelChrome.readySecondsLeft(deadline: store.match?.readyDeadline,
                                                           now: store.clock()))
        }
    }
}

/// 상대 상태 한 줄 — 준비 · 대결 중 · 대결 끝 · 꼭대기 · **상대 연결 확인 중**(침묵 초를 읽는 자리가 여기뿐이다).
struct GamesTetrisDuelPresenceLeaf: View {
    let store: TetrisDuelStore
    let board: TetrisDuelOpponentBoard
    let stage: GamesTetrisDuelChrome.Stage

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !store.isWindowVisible || stage == .finished)) { _ in
            let silent = GamesTetrisDuelChrome.opponentIsSilent(silenceSeconds: store.opponentSilenceSeconds(),
                                                                opponentReady: board.ready, stage: stage)
            Text(silent ? TetrisPhoneText.opponentSilent
                        : GamesTetrisDuelChrome.opponentStatus(board: board, stage: stage))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(silent ? MobileTheme.pending : MobileTheme.label2)
                .lineLimit(1)
        }
    }
}

// MARK: - 조작 버튼

/// 조작 버튼 한 개 — 아이콘 위 + 글자 아래 · 높이 48 · **틴트**. 솔로 폰(`GamesMiniGameScreen` 의
/// `TetrisControlButton`)과 **같은 계약**이다: 눌림은 색만 · 채운 버튼 없음 · 홀드와 반대로는 터치-다운,
/// 바로 내리기만 터치-업.
///
/// ⚠️ 솔로 버튼을 **재사용하지 못한다**: 그 타입은 솔로 화면 파일의 `private` 이고 그 파일은 1.0.11 에서
/// **한 글자도 건드리지 않는다**(설계 P1 — 솔로 판은 비트 단위로 그대로여야 한다). 그래서 같은 계약을 여기
/// 한 벌 더 둔다. 두 벌이 갈리지 않게 **발화 시점과 래치 모양을 테스트가 묶어 둔다.**
struct GamesTetrisDuelControlButton: View {
    /// 48 — `MobileTheme` 행 높이 표의 '미니게임 행' 값(솔로 버튼과 같은 수).
    static let height: CGFloat = 48

    let title: String
    let icon: String
    let width: CGFloat
    var isSpent = false
    let firesOnTouchDown: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// 지금 누르고 있는 접촉의 **시작점**(없으면 nil). 불리언 래치가 아니다 — `onEnded` 는 늘 오지 않고
    /// (시스템 제스처·전화 수신으로 취소되면 안 온다) 참인 채로 굳으면 그 버튼이 화면을 떠날 때까지 죽는다.
    @State private var pressedContact: CGPoint?

    var body: some View {
        if firesOnTouchDown {
            label
                .modifier(GamesTetrisDuelControlChrome(width: width, isSpent: isSpent,
                                                       isPressed: pressedContact != nil))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // 같은 접촉의 두 번째 `onChanged` 는 손가락이 움직인 것뿐이다(발화는 접촉당 한 번).
                            guard pressedContact != value.startLocation else { return }
                            pressedContact = value.startLocation
                            action()
                        }
                        .onEnded { _ in pressedContact = nil }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(isSpent ? TetrisPhoneText.holdSpent : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
        } else {
            Button(action: action) { label }
                .buttonStyle(GamesTetrisDuelControlButtonStyle(width: width))
                .accessibilityLabel(title)
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityHidden(true)
            // 접근성 글자 크기에서는 글자를 떨어뜨리고 아이콘만 남긴다(보이스오버 라벨은 그대로다).
            if !typeSize.isAccessibilitySize {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// 버튼 판(캡슐 · 48 · 틴트). 눌림·소진을 **색으로만** 말한다 — `.disabled()` 를 쓰지 않는다(조각마다 꺼졌다
/// 켜지는 값이라 보이스오버가 비활성 요소를 건너뛰며 버튼이 목록에서 사라졌다 나타났다 한다).
private struct GamesTetrisDuelControlChrome: ViewModifier {
    let width: CGFloat
    var isSpent = false
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSpent ? MobileTheme.label2 : MobileTheme.accent)
            .frame(width: width, height: GamesTetrisDuelControlButton.height)
            .background(Capsule().fill(isSpent ? Color.clear : MobileTheme.accentTint))
            .overlay {
                if isSpent { Capsule().strokeBorder(MobileTheme.separator, lineWidth: 1) }
            }
            .opacity(isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// 터치-업 인사이드 버튼(바로 내리기)의 모양. 눌림은 `ButtonStyle` 이 알려 준다.
private struct GamesTetrisDuelControlButtonStyle: ButtonStyle {
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GamesTetrisDuelControlChrome(width: width, isPressed: configuration.isPressed))
    }
}

#endif
