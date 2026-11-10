import Foundation
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 선후 맞춤 — 판의 첫 수(흑)는 힘이 60%(당김 81)까지(대표 #d_5KuZ3DGTw6BY "흑 첫 수 힘 60%로 — 다음 맥 판(0.3.84)에").
// 규칙은 입력에 건다: 조준 화살(맥)과 서버(저장 전에 줄임). 물리(`shoot`)는 그대로다 — 서버 `alkkagi_simulate` 대조가 안 바뀐다.
// 서버 초안: `ALKKAGI_FIRST_SHOT_SQL=<파일>` → 없으면 체인 폴더의 `*_alkkagi_first_shot.sql`. `ALKKAGI_REQUIRE_MIGRATION=1` 이면 없을 때 빨강.

private func afsPlaced() -> AlkkagiGame {
    var game = AlkkagiGame()
    for (i, x) in [100.0, 200, 300, 400, 500].enumerated() { _ = game.placeStone(stoneID: i, at: AlkkagiVector(x: x, y: 470)) }
    _ = game.confirmPlacement()
    for (i, x) in [100.0, 200, 300, 400, 500].enumerated() { _ = game.placeStone(stoneID: 5 + i, at: AlkkagiVector(x: x, y: 130)) }
    _ = game.confirmPlacement()
    return game
}

private func afsDraftURL() -> URL? {
    if let path = ProcessInfo.processInfo.environment["ALKKAGI_FIRST_SHOT_SQL"], !path.isEmpty {
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    let directory = CheckCoreSourceLayout.repoRoot.appendingPathComponent("supabase/migrations")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.sorted().last { $0.hasSuffix("_alkkagi_first_shot.sql") }.map { directory.appendingPathComponent($0) }
}

private let afsRequired = ProcessInfo.processInfo.environment["ALKKAGI_REQUIRE_MIGRATION"] == "1"

@Suite("1:1 알까기 첫 수 힘 60%")
struct V03xxAlkkagiFirstShotTests {
    @Test func 판의_첫_수_흑만_당김_81_그_뒤와_백이_먼저면_135() {
        #expect(AlkkagiGame.firstShotMaxPull == 81 && AlkkagiGame.firstShotMaxPull == AlkkagiGame.maxPull * 0.6)
        var game = afsPlaced()
        #expect(game.phase == .aiming && game.currentPlayer == .black && game.shotCount == 0)
        #expect(game.shotPullLimit == 81 && game.isFirstShotLimited)
        let shot = game.shoot(stoneID: 2, pull: AlkkagiVector(x: 0, y: 40))
        #expect(shot)
        for _ in 0..<400 where game.phase == .rolling { _ = game.advance(dt: 0.05) }
        #expect(game.phase == .aiming && game.currentPlayer == .white)
        #expect(game.shotPullLimit == AlkkagiGame.maxPull && !game.isFirstShotLimited, "두 번째 수(백)는 그대로")

        // 흑이 첫 차례를 놓쳐 백이 먼저 쏘게 되면(0수 · 백 차례) 백은 그대로 — 그때는 백이 먼저 쏘는 쪽이다.
        var timedOut = afsPlaced()
        _ = timedOut.advance(dt: AlkkagiGame.turnDuration + 0.01)
        #expect(timedOut.currentPlayer == .white && timedOut.shotCount == 0)
        #expect(timedOut.shotPullLimit == AlkkagiGame.maxPull)
        // 배치 중에는 상한이 없다(쏠 수 없는 때).
        #expect(AlkkagiGame().shotPullLimit == AlkkagiGame.maxPull)
    }

    @Test func 물리는_그대로_shoot_은_당김을_자르지_않는다() {
        // 규칙은 입력(화살 · 서버 저장)에 있다 — 엔진 물리를 바꾸면 서버 alkkagi_simulate 대조(160가지)가 어긋난다.
        var full = afsPlaced()
        var capped = afsPlaced()
        let a = full.shoot(stoneID: 2, pull: AlkkagiVector(x: 0, y: AlkkagiGame.maxPull))
        let b = capped.shoot(stoneID: 2, pull: AlkkagiVector(x: 0, y: AlkkagiGame.firstShotMaxPull))
        #expect(a && b)
        #expect(full.stones[2].velocity.length > capped.stones[2].velocity.length * 1.6, "엔진은 받은 당김 그대로")
    }

    @MainActor
    @Test func 연습_판_화살이_첫_수에는_81에서_멈추고_안내가_나온다() {
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.game = afsPlaced()
        model.tick(now: 1_000)
        model.aim(start: AlkkagiVector(x: 300, y: 470), translation: AlkkagiVector(x: 0, y: 400))
        #expect(model.selectedID == 2)
        #expect(abs(model.pull.length - 81) < 1e-9, "첫 수 화살 \(model.pull.length)")
        #expect(model.status.contains("60%"), "\(model.status)")
        model.finishGesture()

        // 두 번째 수부터는 135 까지.
        let model2 = AlkkagiLocalModel()
        model2.soundEnabled = false
        model2.game = AlkkagiGame.restore(stones: afsPlaced().stones, currentPlayer: .black, phase: .aiming,
                                          placementRemaining: 0, shotCount: 1)!
        model2.tick(now: 1_000)
        model2.aim(start: AlkkagiVector(x: 300, y: 470), translation: AlkkagiVector(x: 0, y: 400))
        #expect(abs(model2.pull.length - AlkkagiGame.maxPull) < 1e-9, "두 번째 수 화살 \(model2.pull.length)")
        #expect(!model2.status.contains("60%"), "\(model2.status)")
    }

    @Test(.enabled(if: afsDraftURL() != nil || afsRequired))
    func 서버_초안이_같은_상한_81_을_판의_첫_수_흑에만_건다() throws {
        guard let url = afsDraftURL() else {
            Issue.record("첫 수 상한 서버 초안이 없다(ALKKAGI_FIRST_SHOT_SQL) — ALKKAGI_REQUIRE_MIGRATION=1")
            return
        }
        let sql = try String(contentsOf: url, encoding: .utf8)
        #expect(sql.contains("as $fn$ select 81.0::double precision $fn$;"), "서버 상한이 앱 firstShotMaxPull(81)과 다르다")
        #expect(sql.contains("if m.shot_count = 0 and m.current_player = ''black''"), "판의 첫 수(흑)에만 거는 조건이 없다")
        #expect(sql.contains("v_anchor constant text := '          -- Authorization and the current, server-owned board precede the physics call.';"),
                "물리 호출 앞 앵커가 아니다")
        #expect(!sql.contains("alkkagi_simulate(") || !sql.contains("create or replace function public.alkkagi_simulate"),
                "물리 함수를 다시 만들면 안 된다")
    }
}
