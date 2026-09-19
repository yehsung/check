#if DEBUG
import CheckCore
import Foundation

/// 데모: **AI 대국 장면**(1.0.1 스크린샷용 — DEBUG 전용, Release 에서 컴파일되지 않는다).
///
/// 라우트(`-AingCheckDemoRoute`)는 `AingRoute` 가 모르는 **데모 전용 표기**다 — AI 대국은 서버 판이 아니라 딥링크로 열 대상이 없고,
/// 푸시·위젯 URL 모양(`AingRoute`, 위젯과 함께 쓰는 CheckMobileShared)에 데모 때문에 새 값을 더하지 않는다. 앱 모델이 이 표기를
/// 오목 로비로 연 뒤(`MobileAppModel.openDemoRouteIfNeeded`), 오목 화면이 나타나며 장면을 세운다(`GamesGomokuScreen.applyDemoSeed`).
/// 시뮬레이터에 합성 탭을 넣지 않으므로(작업 규칙) 판은 **대본**으로 둔다 — 스토어 동작은 바꾸지 않고 사람이 누를 문(`place`)을 부른다.
///
///     games/gomoku/ai            대국: 사람 흑 · 대본 세 수 + AI 의 답(진짜 엔진) 뒤 내 차례
///     games/gomoku/ai/white      대국: 사람 백(AI 흑이 천원에 먼저 둔다) · 같은 식
///     games/gomoku/ai/thinking   대국: 두 수를 주고받은 뒤 AI 가 **생각 중인 채로** 멈춘다("생각 중" 표시 장면)
///     games/gomoku/ai/result     결과: 사람 흑이 가로 5목으로 이긴 판(AI 는 가장자리에 두는 대역 — 결과 화면을 빨리 세우려고)
///     games/gomoku/ai/pick       로비 + 돌 색 시트
///
/// 서버에는 한 건도 안 간다 — AI 판은 코어가 서버 경로를 막고(`GomokuAIGame.idPrefix`), 로비·받은함만 평소처럼 픽스처를 읽는다.
package enum MobileDemoGomokuAI {
    package enum Scene: Equatable, Sendable {
        case pick
        case playing(GomokuColor)
        case thinking
        case result
    }

    /// 데모 라우트 → 장면. AI 장면이 아니면 nil.
    package static func scene(route: String?) -> Scene? {
        guard let route else { return nil }
        let parts = route.lowercased().split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "games", parts[1] == "gomoku", parts[2] == "ai" else { return nil }
        switch parts.count == 3 ? "" : parts[3] {
        case "": return .playing(.black)
        case "white": return .playing(.white)
        case "thinking": return .thinking
        case "result": return .result
        case "pick": return .pick
        default: return nil
        }
    }

    /// 이 실행의 장면(데모가 아니면 nil).
    package static func scene(isDemo: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Scene? {
        guard isDemo else { return nil }
        return scene(route: MobileDemo.launchRoute(arguments: arguments))
    }

    /// 대본의 사람 수 후보(앞에서부터 빈 합법 칸). 흑은 천원 둘레, 백은 AI 의 천원 옆.
    static let blackScript = ["H8", "I9", "G9", "J7", "G7", "I7", "H10"]
    static let whiteScript = ["I9", "G7", "I7", "G9", "H10", "J8"]
    /// 결과 장면: 흑 가로 5목(H8~L8) · AI 대역은 1열 가장자리(막지 않는다).
    static let winningScript = ["H8", "I8", "J8", "K8", "L8"]
    static let edgeReplies = ["A1", "A3", "A5", "A7", "A9", "A11", "A13", "A15", "C1", "C15"]
    /// 동점 수 고르기 씨앗(스크린샷을 다시 찍어도 같은 수가 나오게 — 시간으로 끊기는 깊이는 기기마다 다를 수 있다).
    static let tieBreakSeed: UInt64 = 20_260_920

    /// 장면을 세운다. 오목 화면이 보이고 로비가 열릴 때까지 기다렸다가(최대 약 5초) AI 판을 시작하고 대본을 둔다.
    /// 이미 AI 판이 있으면(화면을 다시 열었다) 아무것도 안 한다. 돌 색 시트(`pick`)는 화면이 띄운다.
    @MainActor
    package static func play(_ scene: Scene, games: GamesStore) async {
        let gomoku = games.context.gomoku
        guard scene != .pick, gomoku.aiGame == nil else { return }
        guard await wait(turns: 100, { games.isGomokuScreenVisible && gomoku.hasLoadedInbox && gomoku.canStartAIMatch }) else { return }
        games.aiThinker.limits.tieBreakSeed = tieBreakSeed

        switch scene {
        case .pick:
            return
        case .playing(let color):
            gomoku.startAIMatch(humanColor: color)
            await placeScript(color == .black ? blackScript : whiteScript, moves: 3, games: games)
        case .thinking:
            gomoku.startAIMatch(humanColor: .black)
            await placeScript(blackScript, moves: 2, games: games)
            // 여기부터 AI 는 화면을 떠날 때까지 생각만 한다(취소 문을 볼 때까지 도는 대역 엔진).
            games.aiThinker.engine = { _, _, _, isCancelled in
                while !isCancelled() { Thread.sleep(forTimeInterval: 0.05) }
                return nil
            }
            await placeScript(Array(blackScript.dropFirst(2)), moves: 1, waitsForReply: false, games: games)
        case .result:
            let replies = edgeReplies.compactMap { GomokuPoint(notation: $0) }
            games.aiThinker.engine = { board, _, _, _ in replies.first { board[$0] == nil } }
            gomoku.startAIMatch(humanColor: .black)
            await placeScript(winningScript, moves: winningScript.count, games: games)
        }
    }

    /// 사람 차례마다 후보 중 첫 빈 합법 칸을 둔다(사람이 누르는 문 그대로 — `GomokuStore.place`).
    @MainActor
    private static func placeScript(_ script: [String], moves: Int, waitsForReply: Bool = true, games: GamesStore) async {
        let gomoku = games.context.gomoku
        var remaining = script.compactMap { GomokuPoint(notation: $0) }
        for _ in 0..<moves {
            // AI 의 답(진짜 엔진은 최대 약 1.5초 + 최소 표시 0.6초)을 기다린다.
            guard await wait(turns: 200, { isHumanTurn(gomoku) }) else { return }
            guard let match = gomoku.match,
                  let index = remaining.firstIndex(where: { isPlayable($0, board: match.board, color: match.myColor) })
            else { return }
            let point = remaining.remove(at: index)
            await gomoku.place(point)
            if gomoku.match?.isFinished == true { return }
        }
        if waitsForReply { _ = await wait(turns: 200, { isHumanTurn(gomoku) }) }
    }

    @MainActor
    private static func isHumanTurn(_ gomoku: GomokuStore) -> Bool {
        guard gomoku.isAIMatch, let match = gomoku.match, !match.isFinished else { return false }
        return match.turn == match.myColor
    }

    private static func isPlayable(_ point: GomokuPoint, board: GomokuBoard, color: GomokuColor) -> Bool {
        switch GomokuRules.judge(board: board, point: point, color: color) {
        case .legal, .win: return true
        default: return false
        }
    }

    /// 50ms 씩 `turns` 번까지 조건을 기다린다.
    @MainActor
    private static func wait(turns: Int, _ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<turns {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
#endif
