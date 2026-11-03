import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 맥 미니게임: 3-2-1 카운트다운도 정지 상한에 센다 (다음 맥 판)
//
// 구멍(모바일 개발이 코드를 읽고 찾음, 여기서 재현): 맥의 정지 감시는 카드(`.paused`)가 떠 있는 동안만
// 1초를 자고 나서 1을 더했다. 그래서
//   ① 카드 → [이어하기](3-2-1) → 1에서 ESC(다시 카드) 를 되풀이하면 3-2-1 동안의 시간이 하나도 안 쌓이고,
//   ② 카드에 1초도 안 머물고 넘기면 그 구간은 0초로 버려진다.
// 둘을 섞으면 판을 얼린 채 몇 시간을 둬도 5분 상한이 안 차서, 라운드 토큰이 TTL(30분)을 넘겨 점수를 잃는다.
// 폰(`GamesMiniGameHub.pausedSecondsUsed`)은 이미 **벽시계로 3-2-1 까지** 센다. 맥을 그 규칙에 맞춘다.
//
// 아래 시나리오는 화면이 실제로 밟는 상태 순서를 그대로 `MiniGamePauseMeter` 에 알린다
// (화면은 `pauseState` 를 바꿀 때마다 바로 뒤에서 `notePauseClock()` 으로 같은 값을 알린다 — 아래 소스 계약).

private typealias Pause = MiniGamePauseState
private let limit = TimeInterval(Pause.pauseLimitSeconds)

/// 화면이 밟는 순서를 시계와 함께 적는 작은 대본.
private struct PauseScript {
    var meter = MiniGamePauseMeter()
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    mutating func set(_ state: Pause) { meter.observe(state, at: now) }
    mutating func wait(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    var used: TimeInterval { meter.used(at: now) }
    var isOver: Bool { meter.isOver(at: now) }
}

@Suite("V0374 맥 정지 상한: 3-2-1 과 짧은 왕복도 센다")
struct V0374MiniGamePauseCountdownTests {

    @Test("재현 ①: 카드 ↔ 3-2-1 왕복만 되풀이해도 5분 상한이 찬다")
    func cardCountdownRoundTripsFillTheCap() {
        var s = PauseScript()
        s.set(.paused)
        var elapsed: TimeInterval = 0
        // 카드에 0.2초, 3-2-1 을 2.9초(1이 뜬 채 ESC). 10분 동안 되풀이한다.
        while elapsed < 2 * limit && !s.isOver {
            s.wait(0.2); elapsed += 0.2
            s.set(.resuming(Pause.countdownStart))
            s.wait(1); elapsed += 1
            s.set(.resuming(2))
            s.wait(1); elapsed += 1
            s.set(.resuming(1))
            s.wait(0.9); elapsed += 0.9
            s.set(.paused)       // 3-2-1 중 ESC = 다시 카드
        }
        #expect(s.isOver, "카드 ↔ 3-2-1 왕복으로 \(Int(elapsed))초를 얼려 뒀는데 상한 시계는 \(s.used)초다")
        #expect(elapsed <= limit + 4, "상한이 늦게 찼다: \(elapsed)초")
    }

    @Test("재현 ②: 1초 안의 짧은 정지를 되풀이해도 그 시간이 버려지지 않는다")
    func subSecondPausesAreNotDropped() {
        var s = PauseScript()
        for _ in 0..<100 {
            s.set(.paused)
            s.wait(0.9)
            s.set(.none)         // (카운트다운을 다 본 판이 잠깐 돌고)
            s.wait(0.1)
        }
        #expect(s.used >= 89.9, "0.9초 정지 100번이 \(s.used)초로 셌다 — 1초 미만 구간이 통째로 버려진다")
    }

    @Test("판 단위 누적: 정지 2분 → 3-2-1 → 판 재개를 두 번 하면 4분 6초다(3-2-1 포함, 도는 동안은 안 셈)")
    func theClockIsPerRoundAndIncludesTheCountdown() {
        var s = PauseScript()
        for _ in 1...2 {
            s.set(.paused)
            s.wait(120)
            s.set(.resuming(3)); s.wait(1)
            s.set(.resuming(2)); s.wait(1)
            s.set(.resuming(1)); s.wait(1)
            s.set(.none)
            s.wait(600)          // 판이 도는 10분은 안 센다
        }
        #expect(s.used == 2 * 123)
        #expect(!s.isOver)
    }

    @Test("같은 상태를 거듭 알려도 시계가 되돌아가거나 두 번 세지 않는다")
    func observingTheSameStateTwiceChangesNothing() {
        var s = PauseScript()
        s.set(.paused); s.wait(30)
        s.set(.paused); s.wait(30)
        s.set(.resuming(3)); s.set(.resuming(3)); s.wait(3)
        s.set(.none); s.set(.none); s.wait(100)
        #expect(s.used == 63)
    }

    @Test("빈 시계는 0이고, 상한은 5분에서 찬다")
    func theCapIsFiveMinutes() {
        var s = PauseScript()
        #expect(s.used == 0)
        s.set(.paused); s.wait(limit - 0.5)
        #expect(!s.isOver)
        s.wait(0.5)
        #expect(s.isOver)
    }

    // MARK: 화면 배선(소스 계약 — 주석은 걷고 잰다)

    @Test("화면은 pauseState 를 바꾸는 모든 자리 바로 뒤에서 시계에 알린다")
    func everyPauseStateWriteIsReportedToTheClock() throws {
        let lines = try v0374Stripped(v0374Source("MiniGamePanel.swift"))
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let writes = lines.indices.filter { lines[$0].hasPrefix("pauseState = ") }
        #expect(writes.count >= 7, "전제: 상태를 바꾸는 자리가 \(writes.count)곳뿐이다")
        for i in writes {
            #expect(i + 1 < lines.count && lines[i + 1] == "notePauseClock()",
                    "'\(lines[i])' 뒤에 notePauseClock() 이 없다 — 그 구간이 상한 시계에서 빠진다")
        }
    }

    @Test("[이어하기] 를 눌렀어도 이미 넘었으면 풀어 주지 않는다(폰과 같다)")
    func anOverdueRoundDoesNotThawOnResume() throws {
        let panel = try v0374Stripped(v0374Source("MiniGamePanel.swift"))
        let resume = try v0374Region(after: "private func beginResume()", in: panel)
        let guardLine = "if isPlaying, PauseState.quittingKeepsTheScore(store.miniGameKind), pauseMeter.isOver() {"
        #expect(resume.contains(guardLine), "넘긴 판을 3-2-1 로 풀어 준다")
        let guardAt = try #require(resume.range(of: guardLine)).lowerBound
        let countdownAt = try #require(resume.range(of: "pauseState = .resuming(PauseState.countdownStart)")).lowerBound
        #expect(guardAt < countdownAt, "카운트다운을 먼저 시작하고 나서 상한을 본다")
        #expect(resume.contains("quitRound()"), "넘긴 판을 그 점수로 접지 않는다")
    }
}

// MARK: - 소스 읽기 도우미

private enum V0374Error: Error { case region(String) }

private func v0374Source(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// 주석을 걷어낸다(설명을 지워야만 초록이 되는 시험이 되지 않게).
private func v0374Stripped(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                guard let end = rest.range(of: "*/") else { rest = ""; break }
                rest = rest[end.upperBound...]
                inBlock = false
            } else if let open = rest.range(of: "/*"), rest.range(of: "//").map({ open.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<open.lowerBound]
                rest = rest[open.upperBound...]
                inBlock = true
            } else if let comment = rest.range(of: "//") {
                kept += rest[..<comment.lowerBound]
                rest = ""
            } else {
                kept += rest
                rest = ""
            }
        }
        output += kept + "\n"
    }
    return output
}

private func v0374Region(after anchor: String, in source: String) throws -> String {
    guard let anchorRange = source.range(of: anchor) else { throw V0374Error.region("닻 없음: \(anchor)") }
    var index = anchorRange.upperBound
    while index < source.endIndex, source[index] != "{" { index = source.index(after: index) }
    guard index < source.endIndex else { throw V0374Error.region("블록 없음: \(anchor)") }
    var depth = 0
    let start = index
    while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" { depth -= 1; if depth == 0 { return String(source[start...index]) } }
        index = source.index(after: index)
    }
    throw V0374Error.region("닫힘 없음: \(anchor)")
}
