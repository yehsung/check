import AppKit
import Foundation
import Metal
import SceneKit
import Testing
@testable import CheckCore
@testable import check

// 1:1 길건너 상대 반투명 그림자(11-10 대표 "부하 엄청 심하지 않다면 구현하자" — 제보 테트리스장인).
// 위치는 DB 를 거치지 않는 판 표시 프레임(Realtime Broadcast)의 **선택 칸**으로 싣는다 — 옛 앱(0.3.80 이하)은 모르는 키로 무시하고,
// 받는 쪽도 칸이 없거나 어긋나면 그림자만 버린다(점수 표시는 그대로). 움직였을 때만 0.2초 틈(초당 5장 상한), 그 밖은 예전 그대로.

private let cgMe = "00000000-0000-0000-0000-0000000000a1"
private let cgRival = "00000000-0000-0000-0000-0000000000b2"
private let cgTopic = "crossy_duel:c0de0000-0000-4000-8000-0000000000cd"
private let cgNoJitter: @Sendable (Double) -> Double = { $0 }

private func cgJoinedLink() -> CrossyDuelFrameLink {
    var link = CrossyDuelFrameLink(me: cgMe, opponent: cgRival, frameBase: 1_000)
    link.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cgTopic), reportMs: 1000, checkpointMs: 3000)
    _ = link.socketCommand(at: 0, matchStartedAt: 0, jitter: cgNoJitter)
    _ = link.apply(.joined, at: 0.1, jitter: cgNoJitter)
    return link
}

private func cgFrame(frame: Int, ghost: CrossyDuelGhost?) -> CrossyDuelFrame {
    CrossyDuelFrame(sender: cgRival, seq: 1, frame: frame, score: 4, deaths: 0, heardAgoMs: 100, ghost: ghost)
}

@Suite("V03xx 길건너 1:1 — 상대 반투명 그림자")
struct V03xxCrossyDuelGhostTests {
    @Test("그림자 칸을 싣고 되읽는다 — 없으면 nil(옛 앱), 모양이 어긋나면 그림자만 버리고 프레임은 받는다")
    func payloadRoundTripAndOldAppCompat() throws {
        let ghost = CrossyDuelGhost(x: 3.47, row: 12, facing: .left, dead: false)
        let frame = cgFrame(frame: 5, ghost: ghost)
        let body = frame.payload
        #expect(body["gx"] as? Int == 347 && body["gr"] as? Int == 12 && body["gf"] as? String == "left" && body["gd"] as? Int == 0)
        let decoded = try CrossyDuelFrame.decode(payload: body).get()
        #expect(decoded.ghost == ghost)
        #expect(decoded.score == 4)

        // 옛 앱이 보낸 프레임(그림자 칸 없음) — 그대로 받고 그림자는 nil. 키 수도 예전 7개 그대로.
        let old = cgFrame(frame: 6, ghost: nil)
        #expect(old.payload.count == 7, "그림자가 없는데 칸이 붙었다 — 옛 본문과 달라진다")
        #expect(try CrossyDuelFrame.decode(payload: old.payload).get().ghost == nil)

        // 어긋난 그림자(모르는 방향 · 터무니없는 값) — 프레임은 받고 그림자만 버린다.
        var bad = body
        bad["gf"] = "sideways"
        #expect(try CrossyDuelFrame.decode(payload: bad).get().ghost == nil)
        bad = body
        bad["gx"] = 999_999_999
        #expect(try CrossyDuelFrame.decode(payload: bad).get().ghost == nil)
    }

    @Test("움직였을 때만 0.2초 틈(초당 5장 상한) — 가만히 있으면 예전처럼 1초")
    func cadenceRisesOnlyWhileMoving() {
        var link = cgJoinedLink()
        let here = CrossyDuelGhost(x: 4, row: 0, facing: .forward, dead: false)
        #expect(link.frameDue(at: 1, live: true, changed: false, moved: link.movedSinceLastFrame(here)), "첫 프레임")
        _ = link.makeFrame(at: 1, seq: 1, score: 0, deaths: 0, ghost: here)
        #expect(!link.movedSinceLastFrame(here))
        #expect(!link.frameDue(at: 1.5, live: true, changed: false, moved: false), "가만히 있는데 1초 전에 보낸다")
        #expect(link.frameDue(at: 2.0, live: true, changed: false, moved: false), "가만히 있어도 1초면 보낸다(예전 그대로)")
        let hopped = CrossyDuelGhost(x: 4, row: 1, facing: .forward, dead: false)
        #expect(link.movedSinceLastFrame(hopped))
        #expect(!link.frameDue(at: 1.1, live: true, changed: false, moved: true), "0.2초 틈보다 빨리 보낸다")
        #expect(link.frameDue(at: 1.21, live: true, changed: false, moved: true), "움직였는데 0.2초가 지나도 안 보낸다")
        // 통나무 위 미끄러짐: 0.05칸 넘게 바뀌면 움직임, 그 아래는 아니다.
        #expect(!CrossyDuelGhost(x: 4.03, row: 0, facing: .forward, dead: false).moved(from: here))
        #expect(CrossyDuelGhost(x: 4.06, row: 0, facing: .forward, dead: false).moved(from: here))
        #expect(CrossyDuelGhost(x: 4, row: 0, facing: .forward, dead: true).moved(from: here), "죽음은 곧바로 알린다")
    }

    @Test("받은 그림자 — 최근 2.5초 안 · 살아 있을 때만 보이고, 판이 끝나면 숨는다")
    func receivedGhostVisibility() {
        var link = cgJoinedLink()
        #expect(link.opponentGhost(at: 1) == nil)
        let ghost = CrossyDuelGhost(x: 2.5, row: 7, facing: .right, dead: false)
        #expect(link.receive(cgFrame(frame: 10, ghost: ghost), at: 1) == nil)
        #expect(link.opponentGhost(at: 1.2) == ghost)
        #expect(link.opponentGhost(at: 3.4) == ghost)
        #expect(link.opponentGhost(at: 3.6) == nil, "2.5초 넘게 끊겼는데 옛 자리에 그림자가 남는다")
        #expect(link.receive(cgFrame(frame: 11, ghost: CrossyDuelGhost(x: 2.5, row: 7, facing: .right, dead: true)), at: 4) == nil)
        #expect(link.opponentGhost(at: 4.1) == nil, "죽은 상대의 그림자가 남는다")
        #expect(link.receive(cgFrame(frame: 12, ghost: ghost), at: 5) == nil)
        #expect(link.opponentGhost(at: 5.1) == ghost)
        #expect(link.receive(cgFrame(frame: 13, ghost: nil), at: 6) == nil)
        #expect(link.opponentGhost(at: 6.1) == nil, "옛 앱 상대(그림자 칸 없음)인데 그림자가 남는다")
    }

    @Test("판 그림: 그림자는 반투명으로 받은 자리를 따라가고, 없음 · 그려진 줄 밖이면 숨는다")
    @MainActor
    func sceneDrawsAndHidesTheGhost() {
        let scene = CrossyScene(aingLoader: { nil })
        var game = CrossyGame(seed: 7, rules: .duel)
        game.begin()
        scene.apply(game, reduceMotion: false)
        #expect(scene.ghostStateForTesting.hidden, "상대가 없는데 그림자가 보인다")

        scene.ghostTarget = CrossyDuelGhost(x: 5, row: 2, facing: .forward, dead: false)
        scene.apply(game, reduceMotion: false)
        let first = scene.ghostStateForTesting
        #expect(!first.hidden)
        #expect(abs(first.position.x - 1) < 0.01 && abs(first.position.z + 2) < 0.01, "받은 자리(x 5 → 1, 2줄 → z −2)가 아니다")
        #expect(CrossyScene.ghostOpacity > 0.2 && CrossyScene.ghostOpacity < 0.6, "반투명이 아니다")

        // 한 칸 옮기면 곧바로 뛰지 않고 따라간다(지수 — 몇 프레임 뒤 거의 닿는다).
        scene.ghostTarget = CrossyDuelGhost(x: 6, row: 2, facing: .right, dead: false)
        for _ in 0..<30 {
            game.step(dt: 1.0 / 60)
            scene.apply(game, reduceMotion: false)
        }
        #expect(abs(scene.ghostStateForTesting.position.x - 2) < 0.05, "따라가지 않는다")

        scene.ghostTarget = CrossyDuelGhost(x: 6, row: 400, facing: .forward, dead: false)
        scene.apply(game, reduceMotion: false)
        #expect(scene.ghostStateForTesting.hidden, "그려진 줄 밖인데 보인다")
        scene.ghostTarget = nil
        scene.apply(game, reduceMotion: false)
        #expect(scene.ghostStateForTesting.hidden)
    }
}

// MARK: - 그림 증거(실제 아잉이 모델 · 오프스크린 SCNRenderer) — CHECK_SNAPSHOT_DIR/crossy-duel-ghost/ 에 남긴다

@Suite("V03xx 길건너 1:1 — 상대 반투명 그림자 그림", .serialized)
struct V03xxCrossyDuelGhostRenderTests {
    @MainActor
    private static func snapshot(_ scene: CrossyScene, _ game: CrossyGame) throws -> CGImage {
        scene.apply(game, reduceMotion: true)
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal 이 없다")
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 688, height: 712), antialiasingMode: .multisampling4X)
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    @Test("그림자가 있으면 판에 반투명 아잉이가 하나 더 선다(없을 때와 픽셀이 다르다)")
    @MainActor
    func ghostShowsUpInTheRender() throws {
        let scene = CrossyScene.mac()
        var game = CrossyGame(seed: 7, rules: .duel)
        game.begin()
        scene.ghostTarget = nil
        let without = try Self.snapshot(scene, game)
        scene.ghostTarget = CrossyDuelGhost(x: 6, row: 2, facing: .forward, dead: false)
        let with = try Self.snapshot(scene, game)
        let a = NSBitmapImageRep(cgImage: without), b = NSBitmapImageRep(cgImage: with)
        MiniGameSnapshots.save(a, name: "no-ghost.png", sub: "crossy-duel-ghost")
        MiniGameSnapshots.save(b, name: "ghost.png", sub: "crossy-duel-ghost")
        var differ = 0
        for y in stride(from: 0, to: min(a.pixelsHigh, b.pixelsHigh), by: 2) {
            for x in stride(from: 0, to: min(a.pixelsWide, b.pixelsWide), by: 2) {
                guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
                if abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent) > 0.08 { differ += 1 }
            }
        }
        #expect(differ > 200, "그림자를 넣었는데 판이 거의 같다(다른 점 \(differ))")
    }
}
