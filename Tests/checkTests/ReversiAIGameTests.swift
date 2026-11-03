import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 AI 판(`ReversiAIGame`) — 로컬 판의 차례·시계·연속 자동 착수 규칙.
//
// 서버 1:1 과 같은 규칙이어야 하는 자리(사용자 결정 DEC:18·20, rules.md V-09·V-13·V-14):
//  · 사람 차례 30초가 지나면 사람 합법 수 가운데 무작위 자동 착수, 연속 3회면 사람 패(abandoned) — 단 세 번째 수로 판이 자연히 끝나면 자연 결과.
//  · 사람 직접 착수는 연속 횟수를 0 으로, **자동 패스는 시계·연속 횟수 어디에도 안 들어간다**.
//  · 사람이 둘 곳이 없으면 AI 차례가 연달아 온다(오목과 달리 정상 경로).
//  · 창이 안 보이면 사람 시계를 멈춘다(pause/resume).
// 연속 횟수의 정답지는 cases.json `streak` S01~S05 다 — 이 판에서 그대로 재현한다(AI 쪽 사건은 AI 의 보통 수로 옮긴다: AI 에겐 시계가 없다).

@Suite("아잉 뒤집기 AI 판 — 차례 · 30초 자동 착수 · 연속 3회 패 · 자동 패스 · 시계 멈춤")
struct ReversiAIGameTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// S03 재현 자리(흑 차례): 흑 55 → 백 47 → **흑 둘 곳 없음(자동 패스)** → 백 5 → 흑 6 → 백 14 → 흑 13 이 판을 끝내지 않는다.
    /// reference.py 로 무작위 대국에서 찾은 국면(씨앗 20261103).
    static let passBoard = "bwwwb...bwwwb...bbbwbbbbbbwwbbbbbbbwbwwbbbwwbww.bbbbbbw.wwwwwwww"
    static let passMoves = [55, 47, 5, 6, 14, 13]
    /// S05 재현 자리(백 차례): 백 48 → 흑 42 → 백 10 → 흑 37 → 백 38 이 흑을 전멸시킨다(0:64). 백 45·46 은 판을 안 끝낸다.
    static let endBoard = "................w.b......wbwwwww..wbw....w.ww....bbbw..........."
    static let endMoves = [48, 42, 10, 37, 38]

    func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    // MARK: 사건 재생기(cases.json streak)

    struct Run {
        var game: ReversiAIGame
        var abandonedAt: Int?
    }

    /// streak 사건을 AI 판에 옮긴다. 사람 색 사건: auto → `autoPlaceHuman`, move → `playHuman`. AI 색 사건(auto·move): `playAI`.
    /// pass 사건은 동작이 아니라 **직전 수의 결과**다 — 기록 끝이 그 색의 pass 줄인지 확인만 한다.
    /// `targets` 가 있으면 돌 사건마다 그 칸을 차례로 둔다(없으면 합법 수 가운데 첫 칸).
    func run(_ events: [[ReversiCorpus.Token]], human: ReversiColor, board: ReversiBoard = .start, turn: ReversiColor = .black,
             targets: [Int]? = nil, label: String) throws -> Run {
        var state = Run(game: ReversiAIGame(humanColor: human, board: board, turn: turn, startedAt: Self.t0))
        var queue = targets ?? []
        for (i, event) in events.enumerated() {
            guard let kind = event.first?.text, let colorText = event.dropFirst().first?.text,
                  let color = ReversiColor(rawValue: colorText) else {
                throw ReversiFixtureError("\(label) 사건 \(i): 모양을 못 읽었다 \(event)")
            }
            let now = at(Double(i + 1) * 31)
            if kind == "pass" {
                let last = state.game.plies.last
                #expect(last?.kind == .pass && last?.color == color && last?.auto == false, "\(label) 사건 \(i): \(color) 자동 패스 줄이 없다")
                continue
            }
            guard state.game.turn == color else {
                throw ReversiFixtureError("\(label) 사건 \(i): \(color) 차례가 아니다(지금 \(String(describing: state.game.turn)))")
            }
            let legal = state.game.legalMoves
            let target = targets == nil ? legal[0] : queue.removeFirst()
            if color == human {
                if kind == "auto" {
                    let index = try #require(legal.firstIndex(of: target), "\(label) 사건 \(i): \(target) 가 합법 수가 아니다")
                    #expect(state.game.autoPlaceHuman(at: now, randomIndex: { _ in index }) == target, "\(label) 사건 \(i)")
                } else {
                    #expect((try? state.game.playHuman(target, at: now).get()) != nil, "\(label) 사건 \(i): 사람 수 \(target) 불법")
                }
            } else {
                #expect(state.game.playAI(target, at: now) == true, "\(label) 사건 \(i): AI 수 \(target) 불법")
            }
            if state.abandonedAt == nil, state.game.endReason == .abandoned { state.abandonedAt = i }
            if event.count > 2, event[2] == .flag(true) {
                #expect(state.game.isFinished && state.game.endReason != .abandoned, "\(label) 사건 \(i): 이 수로 판이 자연히 끝나야 한다")
            }
        }
        return state
    }

    /// cases.json 기대(사람 색 하나로 투영)와 맞세운다.
    func expectStreak(_ run: Run, _ expected: ReversiCorpus.StreakExpected, human: ReversiColor, label: String) {
        #expect(run.game.humanAutoStreak == expected.streak[human.rawValue], "\(label) 연속 횟수")
        if expected.abandoned == human.rawValue {
            #expect(run.abandonedAt == expected.atEvent, "\(label) abandoned 사건 번호")
            #expect(run.game.result?.rawValue == expected.result, "\(label) 결과")
            #expect(run.game.endReason?.rawValue == expected.endReason, "\(label) 끝 사유")
            #expect(run.game.score == nil, "\(label): abandoned 는 점수 없이 승패만(V-15)")
        } else {
            #expect(run.abandonedAt == nil, "\(label): abandoned 가 아니어야 한다")
            #expect(run.game.endReason != .abandoned, "\(label)")
        }
    }

    // MARK: 시험

    // 없으면: AI 판 id 가 uuid 처럼 보이거나 머리말 판정이 느슨하면 스토어가 AI 판 요청을 서버로 보낸다(서버 경로 차단의 근거).
    @Test("판 id — \"ai-\" 머리말 · 판마다 다름 · 서버 uuid·nil·대문자 머리말은 AI 판이 아님")
    func aiMatchIdentity() {
        let a = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        let b = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        #expect(a.id.hasPrefix("ai-") && a.id != b.id)
        #expect(ReversiAIGame.isAIMatchID(a.id))
        #expect(ReversiAIGame.isAIMatchID("ai-1"))
        #expect(!ReversiAIGame.isAIMatchID(UUID().uuidString.lowercased()))
        #expect(!ReversiAIGame.isAIMatchID(nil))
        #expect(!ReversiAIGame.isAIMatchID("AI-1"))
        #expect(ReversiAIGame(humanColor: .white, startedAt: Self.t0, id: "ai-fixed").id == "ai-fixed")
    }

    // 없으면: 흑 선(V-04)·사람 시계의 시작이 틀려도(백인데 시계가 돎) 화면이 엉뚱한 마감을 그린다.
    @Test("새 판 — 흑 선, 사람이 흑이면 시계가 30초로 돌고 백이면 시계 없음(AI 차례)")
    func newGameStartsWithBlack() {
        let black = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        #expect(black.board == .start && black.turn == .black && black.plies.isEmpty && black.moveCount == 0)
        #expect(black.turnStartedAt == Self.t0)
        #expect(black.humanDeadline() == at(30))
        #expect(black.legalMoves == [19, 26, 37, 44])
        let white = ReversiAIGame(humanColor: .white, startedAt: Self.t0)
        #expect(white.turn == .black && white.aiColor == .black)
        #expect(white.humanDeadline() == nil, "기준선: AI 차례엔 사람 시계가 없다")
        #expect(white.humanRemaining(at: at(10)) == nil)
        #expect(!white.isFinished && white.result == nil && white.endReason == nil && white.score == nil)
    }

    // 없으면: 사람 수가 차례·판을 잘못 넘기거나, 불법 수가 판을 바꾸거나, 직접 착수가 연속 횟수를 안 지운다.
    @Test("사람 착수 — 합법이면 기록·차례 넘김·연속 횟수 0, 불법·남의 차례면 판 그대로")
    func humanMove() throws {
        var game = ReversiAIGame(humanColor: .black, board: .start, turn: .black, startedAt: Self.t0, humanAutoStreak: 2)
        #expect(game.playHuman(0, at: at(5)) == .failure(.noFlip))
        #expect(game.playHuman(27, at: at(5)) == .failure(.occupied))
        #expect(game.playHuman(64, at: at(5)) == .failure(.outOfRange))
        #expect(game.plies.isEmpty && game.board == .start && game.humanAutoStreak == 2, "불법 수는 아무것도 안 바꾼다")
        let outcome = try game.playHuman(19, at: at(5)).get()
        #expect(outcome.flipped == [27])
        #expect(game.plies == [ReversiPly(seq: 1, color: .black, kind: .stone, idx: 19, flipped: [27], auto: false)])
        #expect(game.humanAutoStreak == 0, "직접 착수는 연속 횟수를 0 으로")
        #expect(game.turn == .white && game.turnStartedAt == at(5) && game.humanDeadline() == nil)
        #expect(game.lastStoneIdx == 19 && game.autoStones.isEmpty)
        let before = game
        #expect(game.playHuman(20, at: at(6)) == .failure(.outOfRange), "AI 차례에 사람 수")
        #expect(game == before)
    }

    // 없으면: 엔진이 낸 규칙 밖 수가 판을 깨거나, 대타(무작위 합법 수)가 AI 차례 밖에서도 나온다.
    @Test("AI 착수 — 규칙 밖이면 false·판 그대로, 대타는 AI 합법 수에서만")
    func aiMove() {
        var game = ReversiAIGame(humanColor: .white, startedAt: Self.t0)
        let before = game
        #expect(game.playAI(0, at: at(1)) == false)
        #expect(game.playAI(64, at: at(1)) == false)
        #expect(game == before)
        #expect(game.randomAIFallback(randomIndex: { $0 - 1 }) == 44)
        #expect(game.randomAIFallback(randomIndex: { _ in 99 }) == 44, "범위 밖 지수는 끝으로 접는다")
        #expect(game.playAI(44, at: at(2)) == true)
        #expect(game.turn == .white && game.humanDeadline() == at(32))
        #expect(game.randomAIFallback(randomIndex: { _ in 0 }) == nil, "사람 차례엔 대타가 없다")
        #expect(game.playAI(43, at: at(3)) == false, "사람 차례에 AI 수")
    }

    // 없으면: 사람이 둘 곳 없을 때 판이 사람 차례에 멈추거나(스토어가 AI 를 다시 안 부름), 자동 패스가 사람 시계·연속 횟수를 건드린다.
    // 기준선: 시작 판에서 AI 가 두면 곧바로 사람 차례 — 패스 자리와 결과가 갈린다.
    @Test("사람 자동 패스 뒤 AI 연속 차례 — pass 줄(auto=false) · 사람 시계 없음 · 연속 횟수 그대로")
    func humanPassGivesAIConsecutiveTurns() throws {
        let p = try ReversiCorpusFile.board(Self.passBoard, "passBoard")
        let afterHuman = try ReversiRules.play(p, color: .black, idx: 55).get().board
        var game = ReversiAIGame(humanColor: .black, board: afterHuman, turn: .white, startedAt: Self.t0, humanAutoStreak: 2)
        #expect(game.playAI(47, at: at(3)) == true)
        #expect(game.plies.map(\.kind) == [.stone, .pass])
        #expect(game.plies.last == ReversiPly(seq: 2, color: .black, kind: .pass, idx: nil, flipped: [], auto: false))
        #expect(game.turn == .white, "사람이 둘 곳이 없어 AI 가 이어 둔다")
        #expect(game.humanDeadline() == nil && game.humanRemaining(at: at(100)) == nil)
        #expect(game.humanAutoStreak == 2, "자동 패스는 연속 횟수를 건드리지 않는다")
        #expect(game.moveCount == 2)
        #expect(game.playAI(5, at: at(9)) == true)
        #expect(game.turn == .black && game.turnStartedAt == at(9) && game.humanDeadline() == at(39), "사람 시계는 AI 의 두 번째 수부터")
        #expect(game.humanAutoStreak == 2)

        var baseline = ReversiAIGame(humanColor: .white, startedAt: Self.t0)
        #expect(baseline.playAI(19, at: at(3)) == true)
        #expect(baseline.plies.map(\.kind) == [.stone] && baseline.turn == .white && baseline.humanDeadline() == at(33))
    }

    // 없으면: AI 가 둘 곳 없을 때 사람 차례가 이어지면서 사람 시계가 새로 시작하지 않는다(옛 마감으로 곧바로 자동 착수).
    @Test("AI 자동 패스 — 사람이 이어 두고, 사람 시계는 그 수부터 새로 30초")
    func aiPassRestartsHumanClock() throws {
        let e01 = try ReversiCorpusFile.load().hand("E01")
        var game = ReversiAIGame(humanColor: .black, board: try ReversiCorpusFile.board(e01.board, "E01"), turn: .black, startedAt: Self.t0)
        _ = try game.playHuman(2, at: at(20)).get()
        #expect(game.plies.map(\.kind) == [.stone, .pass] && game.plies.last?.color == .white)
        #expect(game.turn == .black && game.humanDeadline() == at(50))
    }

    // 없으면: 30초 자동 착수가 사람 합법 수 밖을 두거나, 기록에 auto 가 안 남거나(화면 회색 점), 연속 횟수가 안 오른다.
    @Test("30초 자동 착수 — 마감 판정 · 합법 수 가운데 지정 지수 · auto 기록 · 연속 횟수 +1")
    func thirtySecondAutoPlace() {
        var game = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        #expect(!game.isHumanClockExpired(at: at(29.999)))
        #expect(game.isHumanClockExpired(at: at(30)))
        #expect(game.humanRemaining(at: at(12)) == 18)
        var other = game
        #expect(game.autoPlaceHuman(at: at(30), randomIndex: { $0 - 1 }) == 44)
        #expect(other.autoPlaceHuman(at: at(30), randomIndex: { _ in 0 }) == 19, "기준선: 지수가 다르면 다른 칸")
        #expect(game.plies == [ReversiPly(seq: 1, color: .black, kind: .stone, idx: 44, flipped: [36], auto: true)])
        #expect(game.humanAutoStreak == 1 && game.autoStones == [44] && game.turn == .white)
        #expect(game.humanDeadline() == nil && !game.isHumanClockExpired(at: at(1000)))
        let before = game
        #expect(game.autoPlaceHuman(at: at(31), randomIndex: { _ in 0 }) == nil, "AI 차례엔 자동 착수 없음")
        #expect(game == before)
        var clamped = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        #expect(clamped.autoPlaceHuman(at: at(30), randomIndex: { _ in -7 }) == 19, "음수 지수는 0 으로 접는다")
    }

    // 없으면: 연속 횟수 규칙(직접 착수 0 · 자동 패스 무시 · 사람마다 따로 · 세 번째에 패 · 자연 종료 우선)이 서버 정답지와 갈린다.
    @Test("연속 자동 착수 S01~S05 — cases.json streak 을 AI 판에서 재현")
    func streakCasesReplay() throws {
        let corpus = try ReversiCorpusFile.load()
        let pass = try ReversiCorpusFile.board(Self.passBoard, "passBoard")
        let end = try ReversiCorpusFile.board(Self.endBoard, "endBoard")
        var checked: [String] = []
        for item in corpus.streak {
            let projections: [(ReversiColor, ReversiBoard, ReversiColor, [Int]?)]
            switch item.id {
            case "S01", "S02": projections = [(.black, .start, .black, nil)]
            case "S03": projections = [(.black, pass, .black, Self.passMoves)]
            case "S04": projections = [(.black, .start, .black, nil), (.white, .start, .black, nil)]
            case "S05": projections = [(.white, end, .white, Self.endMoves)]
            default:
                Issue.record("모르는 streak 사례 \(item.id) — 이 시험에 투영을 더하라")
                continue
            }
            for (human, board, turn, targets) in projections {
                let label = "\(item.id)(사람 \(human))"
                let result = try run(item.events, human: human, board: board, turn: turn, targets: targets, label: label)
                expectStreak(result, item.expected, human: human, label: label)
                checked.append(label)
            }
        }
        #expect(checked.count == 6, "\(checked)")
    }

    // 없으면: 세 번째 자동 착수가 판을 끝낼 때 abandoned 가 자연 결과를 덮어쓴다(서버 reversi__play 순서와 갈림).
    // 기준선: 같은 판에서 세 번째 자동 착수만 판을 안 끝내는 칸(45)으로 바꾸면 사람 패(abandoned).
    @Test("자연 종료 우선 — 세 번째 자동 착수로 전멸이면 자연 결과(0:64 백 승), 안 끝나면 abandoned")
    func naturalEndBeatsAbandon() throws {
        let end = try ReversiCorpusFile.board(Self.endBoard, "endBoard")
        func play(lastAuto: Int) throws -> ReversiAIGame {
            var game = ReversiAIGame(humanColor: .white, board: end, turn: .white, startedAt: Self.t0)
            let steps = [(48, true), (42, false), (10, true), (37, false), (lastAuto, true)]
            for (n, (idx, human)) in steps.enumerated() {
                if human {
                    let index = try #require(game.legalMoves.firstIndex(of: idx), "\(idx) 가 합법 수가 아니다")
                    #expect(game.autoPlaceHuman(at: at(Double(n + 1) * 31), randomIndex: { _ in index }) == idx)
                } else {
                    #expect(game.playAI(idx, at: at(Double(n + 1) * 31)) == true)
                }
            }
            return game
        }
        let natural = try play(lastAuto: 38)
        #expect(natural.humanAutoStreak == 3)
        #expect(natural.isFinished && natural.endReason == .wipeout && natural.result == .whiteWin)
        #expect(natural.score == ReversiScore(black: 0, white: 64, result: .whiteWin))
        #expect(natural.winner == .white && natural.finishedAt == at(155))
        let abandoned = try play(lastAuto: 45)
        #expect(abandoned.humanAutoStreak == 3)
        #expect(abandoned.isFinished && abandoned.endReason == .abandoned && abandoned.result == .blackWin)
        #expect(abandoned.score == nil && abandoned.turn == nil && abandoned.turnStartedAt == nil)
    }

    // 없으면: 창을 숨긴 동안 사람 시계가 계속 돌아 돌아오자마자 자동 착수되거나, 멈춘 동안 AI 수 뒤 시작한 사람 차례가 그냥 돈다.
    @Test("시계 멈춤 — 남은 초 보존 · 이으면 마감을 민다 · AI 차례에 멈추면 다음 사람 차례도 멈춘 채 30초")
    func pauseAndResume() throws {
        var game = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        game.pause(at: at(10))
        #expect(game.isClockPaused && game.humanDeadline() == nil)
        #expect(game.humanRemaining(at: at(500)) == 20)
        #expect(!game.isHumanClockExpired(at: at(1000)))
        game.pause(at: at(50))
        #expect(game.humanRemaining(at: at(500)) == 20, "두 번 멈춰도 처음 남은 초")
        game.resume(at: at(100))
        #expect(!game.isClockPaused && game.humanDeadline() == at(120) && game.turnStartedAt == at(90))
        #expect(game.humanRemaining(at: at(110)) == 10)
        game.resume(at: at(200))
        #expect(game.humanDeadline() == at(120), "멈추지 않은 시계를 이어도 그대로")
        let running = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        #expect(running.humanDeadline() == at(30), "기준선: 안 멈춘 판은 30초에 마감")

        var aiFirst = ReversiAIGame(humanColor: .white, startedAt: Self.t0)
        aiFirst.pause(at: at(1))
        #expect(aiFirst.playAI(19, at: at(5)) == true)
        #expect(aiFirst.turn == .white && aiFirst.humanDeadline() == nil && aiFirst.humanRemaining(at: at(400)) == 30)
        aiFirst.resume(at: at(60))
        #expect(aiFirst.humanDeadline() == at(90))

        var done = ReversiAIGame(humanColor: .black, startedAt: Self.t0)
        done.resign(at: at(3))
        done.pause(at: at(4))
        #expect(!done.isClockPaused, "끝난 판은 멈추지 않는다")
    }

    // 없으면: 기권이 점수를 남기거나(V-15), 끝난 판에 수가 또 들어간다.
    @Test("기권 — 사람 패 · 점수 없음 · 끝난 판은 더 안 바뀐다")
    func resign() {
        var game = ReversiAIGame(humanColor: .white, startedAt: Self.t0)
        #expect(game.playAI(19, at: at(1)) == true)
        game.resign(at: at(7))
        #expect(game.isFinished && game.turn == nil && game.result == .blackWin && game.endReason == .resign && game.score == nil)
        #expect(game.finishedAt == at(7) && game.winner == .black)
        let before = game
        game.resign(at: at(9))
        #expect(game.playHuman(20, at: at(9)) == .failure(.outOfRange))
        #expect(game.playAI(20, at: at(9)) == false)
        #expect(game.autoPlaceHuman(at: at(9), randomIndex: { _ in 0 }) == nil)
        #expect(game == before)
    }

    // 없으면: 검증·렌더용 시작 판에서 차례 주인이 둘 곳이 없으면 판이 그 자리에 멈춘다(불변식 위반을 V-09 로 접지 않음).
    @Test("주어진 판으로 시작 — 둘 곳 없는 차례는 패스 한 줄로 넘기고, 둘 다 없으면 바로 자연 종료")
    func boardInitFoldsStuckTurn() throws {
        let corpus = try ReversiCorpusFile.load()
        let e02 = try ReversiCorpusFile.board(try corpus.hand("E02").board, "E02")
        let passed = ReversiAIGame(humanColor: .black, board: e02, turn: .black, startedAt: Self.t0)
        #expect(passed.plies == [ReversiPly(seq: 1, color: .black, kind: .pass, idx: nil, flipped: [], auto: false)])
        #expect(passed.turn == .white && !passed.isFinished)
        let normal = ReversiAIGame(humanColor: .black, board: e02, turn: .white, startedAt: Self.t0)
        #expect(normal.plies.isEmpty && normal.turn == .white, "기준선: 둘 곳 있는 차례면 그대로")
        let e05 = try ReversiCorpusFile.board(try corpus.hand("E05").board, "E05")
        let over = ReversiAIGame(humanColor: .white, board: e05, turn: .black, startedAt: Self.t0)
        #expect(over.isFinished && over.endReason == .noMoves && over.score == ReversiScore(black: 63, white: 1, result: .blackWin))
    }

    // 없으면: AI 판의 기록(돌·패스 줄 순서와 seq)·자연 종료(점수·사유)가 실전 판에서 서버 기록과 갈려도 손 사례만으로는 모른다.
    @Test("기보 200판을 AI 판으로 재생 — 기록 줄(돌 + 패스) · seq · 마지막 판 · 결과 · 끝 사유 · 점수")
    func wthorSampleThroughAIGame() throws {
        let games = try ReversiCorpusFile.load().wthorSample
        for (n, sample) in games.enumerated() {
            let label = sample.id
            let human: ReversiColor = n.isMultiple(of: 2) ? .black : .white
            var game = ReversiAIGame(humanColor: human, startedAt: Self.t0)
            let moves = try ReversiCorpusFile.indices(sample.moves, label)
            var expectedKinds: [ReversiPly.Kind] = []
            for (k, idx) in moves.enumerated() {
                let now = at(Double(k + 1))
                if game.turn == human {
                    #expect((try? game.playHuman(idx, at: now).get()) != nil, "\(label) \(k): 사람 수 불법")
                } else {
                    #expect(game.playAI(idx, at: now) == true, "\(label) \(k): AI 수 불법")
                }
                expectedKinds.append(.stone)
                if sample.passesBefore.contains(k + 1) { expectedKinds.append(.pass) }
            }
            #expect(game.plies.map(\.kind) == expectedKinds, "\(label) 기록 줄")
            #expect(game.plies.map(\.seq) == Array(1...game.plies.count), "\(label) seq")
            #expect(game.plies.compactMap(\.idx) == moves, "\(label) 돌 칸")
            for (prev, ply) in zip(game.plies, game.plies.dropFirst()) where ply.kind == .pass {
                #expect(ply.color == prev.color.opponent, "\(label): 패스는 방금 둔 사람의 상대")
            }
            #expect(game.isFinished && game.board.string == sample.finalBoard, "\(label) 마지막 판")
            #expect(game.result?.rawValue == sample.result && game.endReason?.rawValue == sample.end, "\(label) 결과·사유")
            #expect(game.score.map { ReversiCorpus.Pair(black: $0.black, white: $0.white) } == sample.score, "\(label) 점수")
            #expect(game.humanAutoStreak == 0 && game.autoStones.isEmpty)
        }
    }
}
