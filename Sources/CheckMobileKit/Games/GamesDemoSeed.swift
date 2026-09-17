#if DEBUG
import CheckCore
import Foundation

/// 데모 스크린샷 전용 장면 씨앗(DEBUG 전용 — Release 에서 컴파일되지 않는다).
///
/// 데모 모드(`-AingCheckDemo YES`)에서만 읽는다. 시뮬레이터에는 합성 탭을 넣지 않으므로(작업 규칙 §0-1) 판 도중·결과·시트 같은
/// 화면은 이 실행 인자로 **그 상태에서 시작**한다. 스토어 동작은 바꾸지 않는다 — 화면이 처음 그릴 상태만 정한다.
///
///     -AingCheckGamesDemo playing   미니게임: 판 도중(프레임 멈춤)
///     -AingCheckGamesDemo result    미니게임: 끝난 판의 점수 카드
///     -AingCheckGamesDemo preview   오목 대국: 미리보기 돌을 세운 채
///     -AingCheckGamesDemo stake     오목 로비: 판돈 시트
///     -AingCheckGamesDemo rules     오목: 규칙 시트
///     -AingCheckGamesDemo resign    오목 대국: 기권 확인
///     -AingCheckGamesDemo bottom    스크롤 화면을 맨 아래(채팅 · 지금 대결 중 · 순위 끝)에서 시작
enum GamesDemoSeed: String {
    case playing, result, preview, stake, rules, resign, bottom

    static let argument = "-AingCheckGamesDemo"

    static func current(isDemo: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> GamesDemoSeed? {
        guard isDemo, let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return GamesDemoSeed(rawValue: arguments[index + 1].lowercased())
    }

    /// 타이밍 바: 판 도중(4라운드, 마커가 목표 왼쪽을 지나는 중 · 앞 세 라운드는 명중) 또는 완주.
    static func timingBar(finished: Bool) -> TimingBarGame {
        var game = TimingBarGame(seed: 20_260_917)
        game.tap()
        let dt = 1.0 / 240.0
        for _ in 0..<(240 * 40) {
            if case .running(let round, let t) = game.phase {
                if !finished, round == 4 {
                    let (center, width) = game.target
                    if t > 0.2, game.markerPosition < center - width, game.markerPosition > center - width * 2.2 { break }
                } else {
                    let (center, _) = game.target
                    let move = 2 / TimingBarGame.period(round: round) * dt
                    if abs(game.markerPosition - center) <= move * (round % 3 == 0 ? 6 : 0.5) { game.tap() }
                }
            }
            if case .finished = game.phase { break }
            game.step(dt: dt)
        }
        return game
    }

    /// 플래피: 기둥 사이를 지나는 중(7점) 또는 12점에서 부딪힌 결과.
    static func flappy(finished: Bool) -> FlappyGame {
        var game = FlappyGame(seed: 917)
        game.flap()
        let dt = 1.0 / 120.0
        var sinceFlap = 0.0
        let stopAt = finished ? 12 : 7
        for _ in 0..<(120 * 120) {
            game.step(dt: dt)
            sinceFlap += dt
            if game.phase == .result { break }
            if !finished, game.score >= stopAt, game.lastScoreAt.map({ game.elapsed - $0 > 0.18 }) == true { break }
            guard game.phase == .running, game.score < stopAt || !finished else { continue }
            let birdLeft = game.bird.x - FlappyGame.hitboxSize / 2
            let next = game.pipes.first { $0.x + FlappyGame.pipeWidth >= birdLeft }
            let target = (next?.center(at: game.elapsed) ?? FlappyGame.height / 2) + 14
            if sinceFlap >= 0.12, game.bird.y > target, game.bird.vy > -40 {
                game.flap()
                sinceFlap = 0
            }
        }
        if finished {
            for _ in 0..<(120 * 10) where game.phase != .result { game.step(dt: dt) }
        }
        return game
    }
}
#endif
