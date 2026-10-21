import CheckGoldenSupport
import Testing
@testable import CheckCore

// C-X2(W0-b): V0360 대본 조종사를 **연산 기록**으로 바꿔도 같은 판이 나오는가.
// 조종사를 돌리며 연산을 적고(GoldenTetrisRecorder), 그 기록만 새 판에 다시 넣어(GoldenTetrisReplay) 매 프레임 해시를 접는다.
// 박힌 해시 넷은 V0360TetrisSoloGoldenTests.swift 의 값 그대로다 — 여기서 고치지 않는다(그 파일이 기준이다).
// 이 시험이 초록이어야 W1-a 가 `tetris/scripted-*` 골든을 조종사 없이(연산 RLE + 64프레임 체크포인트) 낼 수 있다.

@Suite("GoldenExport _base — C-X2 조종사 → 연산 기록 재생이 V0360 해시 넷과 같다")
struct GoldenExportReplayW0b {
    struct Script: Sendable {
        var id: String
        var seed: UInt64
        var advance: Int?
        var dt: Double
        var maxFrames: Int
        var actEvery: Int
        var expectedHash: UInt64
    }

    /// V0360TetrisSoloGoldenTests 의 대본 A~D(시드 · dt · 프레임 상한 · 손 간격 · 해시).
    static let scripts: [Script] = [
        Script(id: "A", seed: 20_261_020, advance: nil, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4, expectedHash: 0x64cd_f7c7_36fc_a8b9),
        Script(id: "B", seed: 7_777, advance: nil, dt: 1.0 / 32.0, maxFrames: 32 * 3_600, actEvery: 2, expectedHash: 0xb8cf_1911_16c8_9774),
        Script(id: "C", seed: 330, advance: 330, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4, expectedHash: 0xd30f_b21e_622f_28c6),
        Script(id: "D", seed: 930, advance: 930, dt: 1.0 / 128.0, maxFrames: 128 * 600, actEvery: 8, expectedHash: 0x6519_e5cd_f43b_db8c),
    ]

    static let checkpointEvery = 64

    @Test("대본 A~D: 조종사 해시 = 연산만 재생한 해시 = V0360 박힌 해시, 64프레임 체크포인트도 전부 같다",
          arguments: GoldenExportReplayW0b.scripts.map(\.id))
    func replayMatchesPilot(id: String) throws {
        let script = try #require(Self.scripts.first { $0.id == id })
        let pilot: GoldenTetrisPilot.Result
        if let advance = script.advance {
            pilot = GoldenTetrisPilot.fromAdvance(advance, seed: script.seed, dt: script.dt, maxFrames: script.maxFrames,
                                                  actEvery: script.actEvery, checkpointEvery: Self.checkpointEvery)
        } else {
            pilot = GoldenTetrisPilot.fromNewGame(seed: script.seed, dt: script.dt, maxFrames: script.maxFrames,
                                                  actEvery: script.actEvery, checkpointEvery: Self.checkpointEvery)
        }
        // RLE 왕복도 같은 연산열이어야 한다(골든에는 RLE 글자만 실린다).
        let rle = GoldenTetrisRLE.encode(pilot.frames)
        let decoded = try GoldenTetrisRLE.decode(rle)
        #expect(decoded == pilot.frames, "\(id): RLE 왕복이 연산열을 바꿨다")
        let replay = GoldenTetrisReplay.run(start: pilot.start, preOps: pilot.preOps, frames: decoded, dt: script.dt,
                                            checkpointEvery: Self.checkpointEvery)
        let opCount = pilot.frames.reduce(0) { $0 + $1.count }
        print("[C-X2] \(id) frames=\(pilot.trace.frames) ops=\(opCount) preOps=\(pilot.preOps.map(\.rawValue)) "
              + "rleBytes=\(rle.utf8.count) checkpoints=\(pilot.trace.checkpoints.count) "
              + "pilot=\(GoldenBits.hex64(pilot.trace.hash)) replay=\(GoldenBits.hex64(replay.hash)) "
              + "v0360=\(GoldenBits.hex64(script.expectedHash))")
        #expect(pilot.trace.hash == script.expectedHash, "\(id): 기록하며 돈 조종사가 V0360 과 다른 판을 냈다 — 기록기가 판을 건드린다")
        #expect(replay.hash == script.expectedHash, "\(id): 연산만 재생한 판이 V0360 해시와 다르다")
        #expect(replay.frames == pilot.trace.frames, "\(id): 재생 프레임 수 \(replay.frames) ≠ 조종사 \(pilot.trace.frames)")
        if let first = zip(pilot.trace.checkpoints, replay.checkpoints).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
            let from = first.offset * Self.checkpointEvery
            Issue.record("\(id): 처음 갈린 체크포인트 구간 [\(from), \(from + Self.checkpointEvery)]")
        }
        #expect(replay.checkpoints.count == pilot.trace.checkpoints.count)
        #expect(replay.game.board == pilot.trace.game.board && replay.game.score == pilot.trace.game.score,
                "\(id): 끝 판·점수가 갈렸다")
    }

    /// 대조(기준선이 다른 입력): 연산 하나를 빼면 해시가 달라야 한다 — 재생이 연산을 실제로 쓰는지.
    @Test("대조: 대본 C 의 연산 하나(첫 ACT)를 지우면 재생 해시가 V0360 과 달라진다")
    func droppingOneOpChangesTheHash() throws {
        let script = try #require(Self.scripts.first { $0.id == "C" })
        let pilot = GoldenTetrisPilot.fromAdvance(script.advance!, seed: script.seed, dt: script.dt,
                                                  maxFrames: script.maxFrames, actEvery: script.actEvery,
                                                  checkpointEvery: Self.checkpointEvery)
        var frames = pilot.frames
        let at = try #require(frames.firstIndex { $0.contains(.act) }, "대본 C 에 ACT 가 없다")
        frames[at].removeAll { $0 == .act }
        let replay = GoldenTetrisReplay.run(start: pilot.start, preOps: pilot.preOps, frames: frames, dt: script.dt,
                                            checkpointEvery: Self.checkpointEvery)
        #expect(replay.hash != script.expectedHash, "연산 하나를 지워도 해시가 같다 — 재생이 연산을 안 본다")
    }
}
