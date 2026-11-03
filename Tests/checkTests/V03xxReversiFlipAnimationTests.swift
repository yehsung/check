import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 뒤집기 그림(`ReversiFlipAnimation`) — 순수 값 계약. 갈래 C2. 설계서 §4.5.
//
// 어떤 프레임이든 `now` 하나로 결정되는 값이라 시계를 넣어 프레임을 직접 잰다(`withAnimation` 은 중간 프레임을 밖에서 못 본다).
// 지키는 것: t=0 옛 색 · 반을 지나면 새 색 · 불투명도 불변(언제나 두 극단색 중 하나) · 지연은 2차원 고리 거리 ·
// 돌 한 수(+ 패스)만 그림 · 다른 판 id·두 수 건너뜀·패스만·기록 구멍은 그림 없음 · 스토어는 창이 보일 때만 세운다.

private let rvT0 = Date(timeIntervalSince1970: 1_793_660_908)

private func rvStone(_ seq: Int, _ color: ReversiColor, _ idx: Int, _ flipped: [Int], auto: Bool = false) -> ReversiPly {
    ReversiPly(seq: seq, color: color, kind: .stone, idx: idx, flipped: flipped, auto: auto)
}

private func rvPass(_ seq: Int, _ color: ReversiColor) -> ReversiPly {
    ReversiPly(seq: seq, color: color, kind: .pass, idx: nil, flipped: [], auto: false)
}

private func rvMatch(_ id: String, count: Int, plies: [ReversiPly]) -> ReversiMatchState {
    ReversiMatchState(id: id, stake: 3, myColor: .black, opponent: ReversiUser(id: rvA, displayName: "상대"),
                      moveCount: count, plies: plies)
}

/// 주석을 걷은 소스(문자열 리터럴 안의 `//` 는 이 파일에 없다).
private func rvSourceWithoutComments(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CheckCore/\(name)")
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

@Suite("아잉 뒤집기 뒤집기 그림 — 순수 값")
struct V03xxReversiFlipAnimationTests {

    @Test func 시작엔_옛_색_반을_지나면_새_색() {
        // 없으면: 첫 프레임부터 새 색이거나(뒤집힘이 안 보인다) 끝까지 옛 색이어도(판과 그림이 어긋난다) 초록이다.
        let anim = ReversiFlipAnimation(matchID: "m", startedAt: rvT0, placedIdx: 19, color: .black, flipped: [27])
        #expect(anim.displayedColor(idx: 27, now: rvT0) == .white)
        #expect(anim.xScale(idx: 27, now: rvT0) == 1)
        let half = rvT0.addingTimeInterval(ReversiFlipAnimation.flipDuration / 2)
        #expect(anim.displayedColor(idx: 27, now: half.addingTimeInterval(-0.01)) == .white)
        #expect(anim.displayedColor(idx: 27, now: half.addingTimeInterval(0.001)) == .black)
        #expect(anim.xScale(idx: 27, now: half.addingTimeInterval(0.001)) < 0.02)
        let end = rvT0.addingTimeInterval(ReversiFlipAnimation.flipDuration + 0.001)
        #expect(anim.displayedColor(idx: 27, now: end) == .black)
        #expect(abs(anim.xScale(idx: 27, now: end) - 1) < 0.000_001)
        #expect(anim.isFinished(now: end))
        #expect(anim.isFinished(now: end.addingTimeInterval(-0.02)) == false)
        // 놓은 칸·무관한 칸은 그림이 없다(판 그대로).
        #expect(anim.displayedColor(idx: 19, now: half) == nil)
        #expect(anim.progress(idx: 0, now: half) == nil)
        #expect(anim.xScale(idx: 0, now: half) == 1)
    }

    @Test func 지연은_놓은_칸에서의_2차원_고리_거리다() {
        // 없으면: 1차원 idx 차로 거리를 재서 h1(7)과 a2(8)를 이웃으로 보는(행 끝 넘김, V-01) 구현도 초록이다.
        let wrap = ReversiFlipAnimation(matchID: "m", startedAt: rvT0, placedIdx: 7, color: .white, flipped: [8])
        #expect(abs((wrap.delays[8] ?? -1) - 6 * ReversiFlipAnimation.ringDelay) < 0.000_001)
        let diagonal = ReversiFlipAnimation(matchID: "m", startedAt: rvT0, placedIdx: 0, color: .black, flipped: [9, 18, 27])
        #expect(diagonal.delays[9] == 0)
        #expect(abs((diagonal.delays[18] ?? -1) - ReversiFlipAnimation.ringDelay) < 0.000_001)
        #expect(abs((diagonal.delays[27] ?? -1) - 2 * ReversiFlipAnimation.ringDelay) < 0.000_001)
        #expect(abs(diagonal.duration - (2 * ReversiFlipAnimation.ringDelay + ReversiFlipAnimation.flipDuration)) < 0.000_001)
        // 늦게 시작하는 칸은 앞 칸이 반을 넘었을 때도 아직 옛 색이다.
        let t = rvT0.addingTimeInterval(ReversiFlipAnimation.flipDuration / 2 + 0.01)
        #expect(diagonal.displayedColor(idx: 9, now: t) == .black)
        #expect(diagonal.displayedColor(idx: 27, now: t) == .white)
    }

    @Test func 불투명도는_건드리지_않는다() throws {
        // 없으면: 이징으로 불투명도를 깎는 구현(밀려나기 전에 사라진다 — 렌더 감지기가 돌을 못 센다)도 초록이다.
        let anim = ReversiFlipAnimation(matchID: "m", startedAt: rvT0, placedIdx: 0, color: .black, flipped: [1, 2, 3, 9, 18])
        var t = rvT0
        while t <= rvT0.addingTimeInterval(anim.duration) {
            for idx in anim.flipped {
                let color = anim.displayedColor(idx: idx, now: t)
                #expect(color == .black || color == .white, "칸 \(idx) 가 \(t.timeIntervalSince(rvT0))초에 색이 없다")
            }
            t = t.addingTimeInterval(0.01)
        }
        let source = try rvSourceWithoutComments("ReversiFlipAnimation.swift").lowercased()
        #expect(!source.contains("opacity"))
        #expect(!source.contains("alpha"))
    }

    @Test func 돌_한_수와_그_뒤_패스만_그린다() {
        // 없으면: 두 수를 한 장으로 미끄러뜨리거나(판이 거짓말) · 패스만 온 응답에도 그림이 서거나 · 다른 판으로 바뀐 화면 전환이
        // 애니메이션으로 둔갑해도 초록이다.
        let before = rvMatch("m", count: 4, plies: [])
        let one = rvMatch("m", count: 5, plies: [rvStone(5, .black, 19, [27])])
        let made = ReversiFlipAnimation.make(from: before, to: one, at: rvT0)
        #expect(made?.placedIdx == 19)
        #expect(made?.flipped == [27])
        #expect(made?.color == .black)
        #expect(made?.matchID == "m")
        let withPass = rvMatch("m", count: 6, plies: [rvStone(5, .black, 2, [1]), rvPass(6, .white)])
        #expect(ReversiFlipAnimation.make(from: before, to: withPass, at: rvT0)?.flipped == [1])
        let twoStones = rvMatch("m", count: 6, plies: [rvStone(5, .black, 19, [27]), rvStone(6, .white, 18, [27])])
        #expect(ReversiFlipAnimation.make(from: before, to: twoStones, at: rvT0) == nil)
        let passOnly = rvMatch("m", count: 5, plies: [rvPass(5, .black)])
        #expect(ReversiFlipAnimation.make(from: before, to: passOnly, at: rvT0) == nil)
        let otherMatch = rvMatch("other", count: 5, plies: [rvStone(5, .black, 19, [27])])
        #expect(ReversiFlipAnimation.make(from: before, to: otherMatch, at: rvT0) == nil)
        #expect(ReversiFlipAnimation.make(from: nil, to: one, at: rvT0) == nil)
        let shrunk = rvMatch("m", count: 3, plies: [])
        #expect(ReversiFlipAnimation.make(from: before, to: shrunk, at: rvT0) == nil)
        let hole = rvMatch("m", count: 5, plies: [])                       // 수 번호는 올랐는데 기록이 없다
        #expect(ReversiFlipAnimation.make(from: before, to: hole, at: rvT0) == nil)
        let three = rvMatch("m", count: 7, plies: [rvStone(5, .black, 19, [27]), rvPass(6, .white), rvPass(7, .black)])
        #expect(ReversiFlipAnimation.make(from: before, to: three, at: rvT0) == nil)
    }
}

@Suite("아잉 뒤집기 뒤집기 그림 — 스토어가 세우는 자리")
@MainActor
struct V03xxReversiFlipStoreTests {

    @Test(.gomokuDefaultsCleanup)
    func 창이_보일_때_한_수만_그림이_서고_안_보이면_안_선다() throws {
        // 없으면: 보이지 않는 창에서 그림이 서서 TimelineView 가 배터리를 먹거나, 판이 나아가도 그림이 안 서도 초록이다.
        let (store, _) = makeReversiStore("flip", me: rvB, handler: rvHandler([:]))
        store.isWindowVisible = true
        store.applyState(try rvState("reversi_state__my_turn"))
        #expect(store.flip == nil)                                         // 첫 적재는 그림이 아니다
        store.applyState(try rvState("reversi_move__ok"))
        let flip = try #require(store.flip)
        #expect(flip.matchID == rvMainMatch)
        #expect(flip.placedIdx == 19)
        #expect(flip.flipped == [27])
        #expect(flip.color == .black)
        // 수가 그대로인 폴링 응답은 그림을 다시 세우지도 지우지도 않는다.
        store.applyState(try rvState("reversi_move__ok"), requestedSince: 1)
        #expect(store.flip == flip)
        store.windowDidHide()
        #expect(store.flip == nil)

        // 기준선: 창이 안 보이면 같은 진행에 그림이 없다.
        let (hidden, _) = makeReversiStore("flip-hidden", me: rvB, handler: rvHandler([:]))
        hidden.applyState(try rvState("reversi_state__my_turn"))
        hidden.applyState(try rvState("reversi_move__ok"))
        #expect(hidden.match?.moveCount == 1)
        #expect(hidden.flip == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func AI_판도_같은_그림_문을_지난다() async throws {
        // 없으면: 1:1 판만 그림이 서고 AI 판의 수는 순간이동해도 초록이다(깔때기 하나가 빠진 모양).
        let (store, _) = makeReversiStore("flip-ai", me: rvB, handler: rvHandler([:]))
        store.aiMoveChooser = { _, _ in
            try? await Task.sleep(for: .seconds(3_600))
            return nil
        }
        store.isWindowVisible = true
        store.startAIMatch(humanColor: .black)
        #expect(store.flip == nil)
        await store.place(19)
        #expect(store.flip?.placedIdx == 19)
        #expect(store.flip?.flipped == [27])
    }
}
