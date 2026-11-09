// 알까기 손맛 영상(검토용) — 같은 한 수를 프레임마다 그려 PNG 와 소리(WAV)로 남긴다. ALK_FEEL_DIR 이 없으면 아무것도 안 한다.
// 영상은 ffmpeg 로 묶는다(대표에게 개선 전후 · 감속 시안을 보이려고). 창은 띄우지 않는다(ImageRenderer).
import AppKit
import CheckCore
import Foundation
import SwiftUI
import Testing
@testable import check

@MainActor
@Suite("알까기 손맛 영상", .serialized)
struct AlkkagiFeelReelTests {
    /// 세게 부딪힌 다음 한 프레임(1/60초 — 최소 멈춤 30ms 보다 짧다)은 돌이 움직이지 않는다(멈칫). 기준선: 멈칫을 끄면 움직인다.
    @Test func strongHitFreezesTheNextFrame() {
        func movedAfterHit(hitStop: Bool) -> Bool {
            let model = AlkkagiLocalModel()
            model.soundEnabled = false
            model.hitStopEnabled = hitStop
            var hit = false
            model.soundTap = { strength, kind, _ in if kind == .hit, strength > 0.3 { hit = true } }
            for (i, x) in [100.0, 200, 300, 400, 500].enumerated() { _ = model.game.placeStone(stoneID: i, at: AlkkagiVector(x: x, y: 470)) }
            _ = model.game.confirmPlacement()
            for (i, p) in [(300.0, 170.0), (322, 112), (120, 120), (470, 200), (540, 90)].enumerated() {
                _ = model.game.placeStone(stoneID: 5 + i, at: AlkkagiVector(x: p.0, y: p.1))
            }
            _ = model.game.confirmPlacement()
            var now = 1_000.0
            model.tick(now: now)
            model.aim(start: AlkkagiVector(x: 300, y: 470), translation: AlkkagiVector(x: 0, y: AlkkagiGame.maxPull))
            model.release()
            for _ in 0..<120 where !hit { now += 1.0 / 60; model.tick(now: now) }
            let before = model.game.stones.map(\.position)
            now += 1.0 / 60; model.tick(now: now)
            return model.game.stones.map(\.position) != before
        }
        #expect(!movedAfterHit(hitStop: true), "멈칫: 세게 맞은 다음 프레임은 그대로")
        #expect(movedAfterHit(hitStop: false), "기준선: 멈칫을 끄면 다음 프레임에 움직인다")
    }

    /// 감속 시안: 같은 한 수에서 B(바둑판 마찰) · C(무겁게)는 A(지금)보다 일찍 선다 · C 는 덜 간다.
    @Test func decelerationPresetsDifferAsDescribed() {
        func roll(_ physics: AlkkagiGame.Physics) -> (seconds: Double, travel: Double) {
            var game = AlkkagiGame()
            game.physics = physics
            _ = game.placeStone(stoneID: 2, at: AlkkagiVector(x: 300, y: 560))
            for i in [0, 1, 3, 4] { _ = game.placeStone(stoneID: i, at: AlkkagiVector(x: Double(60 + i * 120), y: 500)) }
            _ = game.confirmPlacement()
            for i in 5...9 { _ = game.placeStone(stoneID: i, at: AlkkagiVector(x: Double(40 + (i - 5) * 50), y: 30)) }
            _ = game.confirmPlacement()
            _ = game.shoot(stoneID: 2, pull: AlkkagiVector(x: 0, y: 60))
            var seconds = 0.0
            while game.phase == .rolling && seconds < 10 { _ = game.advance(dt: 1.0 / 240); seconds += 1.0 / 240 }
            let y = game.stones.first { $0.id == 2 }!.position.y
            return (seconds, 560 - y)
        }
        let a = roll(.ice), b = roll(.board), c = roll(.heavy)
        #expect(b.seconds < a.seconds * 0.7 && c.seconds < b.seconds, "멈추는 데 걸린 시간 A \(a.seconds) · B \(b.seconds) · C \(c.seconds)")
        #expect(c.travel < b.travel && c.travel < a.travel, "간 거리 A \(a.travel) · B \(b.travel) · C \(c.travel)")
    }

    @Test func renderOneShot() throws {
        guard let dir = ProcessInfo.processInfo.environment["ALK_FEEL_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fps = 60.0
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        var sounds: [(time: Double, strength: Double, kind: AlkkagiFeedback.Kind)] = []
        var clock = 0.0
        model.soundTap = { strength, kind, _ in sounds.append((clock, strength, kind)) }
        // ALK_FEEL_PHYSICS = ice | board | heavy(감속 시안) · ALK_FEEL_HITSTOP = 0 이면 멈칫 끔
        let env = ProcessInfo.processInfo.environment
        model.hitStopEnabled = env["ALK_FEEL_HITSTOP"] != "0"
        // 흑 다섯 · 백 다섯 — 가운데 흑(2번)이 곧장 위로 쏘아 백 둘을 잇달아 맞히고 하나는 판 밖으로.
        for (i, x) in [100.0, 200, 300, 400, 500].enumerated() {
            let placed = model.game.placeStone(stoneID: i, at: AlkkagiVector(x: x, y: 470))
            #expect(placed)
        }
        let blackDone = model.game.confirmPlacement()
        #expect(blackDone)
        let whites: [(Double, Double)] = [(300, 170), (322, 112), (120, 120), (470, 200), (540, 90)]
        for (i, p) in whites.enumerated() {
            let placed = model.game.placeStone(stoneID: 5 + i, at: AlkkagiVector(x: p.0, y: p.1))
            #expect(placed)
        }
        let whiteDone = model.game.confirmPlacement()
        #expect(whiteDone && model.game.phase == .aiming)
        switch env["ALK_FEEL_PHYSICS"] {
        case "board": model.game.physics = .board
        case "heavy": model.game.physics = .heavy
        default: model.game.physics = .ice
        }
        let start = AlkkagiVector(x: 300, y: 470)
        var frame = 0
        func shot() throws {
            model.tick(now: 1_000 + clock)
            let view = AlkkagiGameView(model: model).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view.fixedSize())
            renderer.scale = 1.5
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent(String(format: "f%04d.png", frame)))
            frame += 1
            clock += 1 / fps
        }
        // 0.3초 가만히 → 0.6초 동안 당김(0 → 최대) → 0.15초 버팀 → 놓음 → 3.2초 굴러감
        for _ in 0..<Int(0.3 * fps) { try shot() }
        let pullFrames = Int(0.6 * fps)
        for k in 1...pullFrames {
            let pull = AlkkagiGame.maxPull * Double(k) / Double(pullFrames)
            model.aim(start: start, translation: AlkkagiVector(x: 0, y: pull))
            try shot()
        }
        for _ in 0..<Int(0.15 * fps) { try shot() }
        model.release()
        for _ in 0..<Int(3.2 * fps) { try shot() }
        // 소리: 울린 시각마다 앱과 같은 표본을 섞는다(44.1kHz · 16비트 · 단음)
        let rate = 44_100.0
        var mix = [Float](repeating: 0, count: Int(clock * rate) + 8_000)
        for s in sounds {
            let wave = AlkkagiFeedback.samples(strength: s.strength, kind: s.kind)
            let at = Int(s.time * rate)
            for (i, v) in wave.enumerated() where at + i < mix.count { mix[at + i] += v }
        }
        var data = Data()
        func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); le(UInt32(36 + mix.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(44_100)); le(UInt32(88_200)); le(UInt16(2)); le(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); le(UInt32(mix.count * 2))
        for v in mix { le(Int16(max(-1, min(1, v * 2.2)) * 32_000)) }
        try data.write(to: out.appendingPathComponent("sound.wav"))
        let log = sounds.map { String(format: "%.3f %.2f %@", $0.time, $0.strength, "\($0.kind)") }.joined(separator: "\n")
        try log.write(to: out.appendingPathComponent("sounds.txt"), atomically: true, encoding: .utf8)
        #expect(frame > 200)
    }
}
