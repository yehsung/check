import Foundation
import Testing
@testable import check

// MARK: - 탭 순간 화면이 본 판을 로그로 남긴다 (v0.3.31 진단 — 2026-09-17 재발)
//
// 사용자: "화면은 내 차례였고 다른 칸엔 미리보기가 떴는데 한 영역만 안 놓였다."
// 같은 순간 스토어는 그 클릭을 not-your-turn 으로 거절했고 서버도 상대 차례였다. 화면이 옛 판을 그린 것인지
// 차례를 잘못 읽은 것인지 가를 값이 없어서, 탭마다 화면의 판과 스토어의 판을 나란히 적는다. **동작은 바꾸지 않는다**
// (사용자 결정: 화면에 띄우지 말고 로그만).

private let tdOpponent = GomokuUser(
    id: "00000000-0000-0000-0000-00000000000b", displayName: "라이벌", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: false
)

private func tdMatch(id: String = "match-1", moves: Int, turn: GomokuColor?, finished: Bool = false) -> GomokuMatchState {
    GomokuMatchState(
        id: id, stake: 5, myColor: .white, opponent: tdOpponent, board: GomokuBoard(),
        lastMove: nil, moveCount: moves, turn: turn, deadline: Date().addingTimeInterval(25),
        isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
    )
}

@Test
func seenTurnDiffersOnlyWhenTheMatchMovesOrTurnDiffer() {
    let seen = GomokuSeenTurn(tdMatch(moves: 7, turn: .white))
    #expect(!seen.differs(from: tdMatch(moves: 7, turn: .white)))
    #expect(seen.differs(from: tdMatch(moves: 8, turn: .black)), "화면은 백 차례 7수, 스토어는 흑 차례 8수 — 03:30 의 그 모양")
    #expect(seen.differs(from: tdMatch(moves: 7, turn: .black)))
    #expect(seen.differs(from: tdMatch(id: "match-2", moves: 7, turn: .white)))
    #expect(seen.differs(from: nil))
}

/// 화면은 내 차례(백·7수)를 그렸는데 스토어는 이미 상대 차례(흑·8수) — 한 번 적고, 판정은 스토어 값(not-your-turn)이다.
@MainActor
@Test
func aTapSeenOnAStaleBoardIsLoggedButJudgedByTheStore() async throws {
    let store = GomokuStore()
    store.match = tdMatch(moves: 8, turn: .black)
    store.phase = .playing
    let point = try #require(GomokuPoint(x: 6, y: 4))

    await store.place(point, seen: GomokuSeenTurn(tdMatch(moves: 7, turn: .white)))
    #expect(store.tapDivergenceCount == 1, "화면과 스토어가 다른 판을 봤는데 기록이 없다")
    #expect(store.notice == GomokuNoticeText.tapRefusal(.notYourTurn), "판정이 화면 값으로 바뀌었다 — 진단은 동작을 바꾸면 안 된다")
    #expect(!store.isBusy, "서버로 나가면 안 되는 착수가 왕복을 시작했다")

    // 같은 판을 본 탭은 적지 않는다.
    await store.place(point, seen: GomokuSeenTurn(tdMatch(moves: 8, turn: .black)))
    #expect(store.tapDivergenceCount == 1)
    // 화면 값을 안 싣는 옛 호출부도 그대로 돈다.
    await store.place(point)
    #expect(store.tapDivergenceCount == 1)
}

@Test
func transitionLineIsWrittenOnlyWhenMovesTurnOrFinishChange() {
    let a = tdMatch(moves: 7, turn: .white)
    #expect(GomokuStore.matchTransitionLine(from: a, to: a) == nil, "같은 판을 다시 받는 되맞춤마다 줄이 쌓인다")
    var clockOnly = a
    clockOnly.deadline = Date().addingTimeInterval(3)
    #expect(GomokuStore.matchTransitionLine(from: a, to: clockOnly) == nil, "시계만 바뀌어도 줄이 생긴다")
    #expect(GomokuStore.matchTransitionLine(from: a, to: tdMatch(moves: 8, turn: .black))
            == "state moves=7→8 turn=white→black finished=false sameMatch=true")
    #expect(GomokuStore.matchTransitionLine(from: nil, to: a) == "state moves=-→7 turn=none→white finished=false sameMatch=false")
    #expect(GomokuStore.matchTransitionLine(from: a, to: tdMatch(moves: 7, turn: nil, finished: true)) != nil)
    #expect(GomokuStore.matchTransitionLine(from: nil, to: nil) == nil)
}

/// 소스 계약: 판 탭이 화면의 판을 싣지 않거나, `match` 가 바뀔 때 줄을 안 쓰면 위 시험이 다 초록인 채로 로그가 비어 있다.
@Test
func theBoardTapCarriesWhatTheScreenDrewAndMatchChangesAreLogged() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func stripped(_ name: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/check/\(name)"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            guard let comment = line.range(of: "//") else { return line }
            return line[..<comment.lowerBound]
        }.joined(separator: "\n")
    }
    let panel = try stripped("GomokuPanel.swift")
    #expect(panel.contains("let seen = GomokuSeenTurn(match)"))
    #expect(panel.contains("await store.place(point, seen: seen)"), "판 탭이 화면의 판을 넘기지 않는다")
    let store = try stripped("GomokuStore.swift")
    let decl = try #require(store.range(of: "var match: GomokuMatchState? {"), "match 에 관찰자가 없다")
    let tail = store[decl.upperBound...].prefix(300)
    #expect(tail.contains("didSet"))
    #expect(tail.contains("Self.matchTransitionLine(from: oldValue, to: match)"))
    #expect(store.contains("if let seen, seen.differs(from: match) { noteTapDivergence(seen, at: point) }"))
}
