import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CheckCore

// v0.3.54 · 폰 1.0.8 — 캡슐 기계의 터짐 빛이 무대 테두리에서 잘리지 않는가.
//
// 폰 세로 화면은 무대(380×460)보다 위아래가 길다. 빛줄기 · 금 고리는 `Canvas` 로 그리는데, **실제 화면(창 · 기기)에서 Canvas 는
// 제 테두리로 잘린다** — ImageRenderer 는 안 잘라서 무대 그림 시험(`V0354GachaMachineRenderTests`)에선 안 보였다. 시뮬레이터에서
// 황금 공개를 찍어 보니 빛이 무대 위아래 테두리에서 가로줄로 뚝 끊겼다(reveal-stills/phone-cover-03 · 04, 고치기 전).
//
// 그래서 여기서는 ImageRenderer 가 아니라 **창에 얹힌 NSHostingView 를 `cacheDisplay` 로 뜬다**(기기와 같이 Canvas 를 자르는 길).
// 창은 모든 화면 밖(-30000)에 두고 마우스를 받지 않으며 키가 되지 않는다(사장님 규칙 — 화면에 아무것도 안 뜬다).
// 잰 값: 무대 바로 위 띠와 바로 안 띠의 밝기 — 잘리면 위 띠는 바탕(어둠)뿐이라 안 띠보다 훨씬 어둡다.

@MainActor
private final class BleedClock { var now = Date(timeIntervalSinceReferenceDate: 800_000_000) }

@MainActor
private final class BleedGate {
    private var pending: CheckedContinuation<GachaRevealOutcome, Error>?
    func pull() async throws -> GachaRevealOutcome { try await withCheckedThrowingContinuation { pending = $0 } }
    func succeed(_ outcome: GachaRevealOutcome) { pending?.resume(returning: outcome); pending = nil }
    var isWaiting: Bool { pending != nil }
}

private final class BleedProbeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Suite("V0354 GachaMachine — 터짐 빛이 무대 밖까지(폰 세로 화면)", .serialized)
struct V0354GachaMachineBleedTests {
    /// 무대 위아래로 더 보이는 폭(설계 좌표) — 폰 세로 화면처럼.
    static let extra: CGFloat = 120

    /// 황금 공개 0.5초(빛줄기가 한창) 감독.
    private func goldRevealDirector() async throws -> (GachaMachineDirector, GachaMachineEnv, Date) {
        let clock = BleedClock()
        let gate = BleedGate()
        let d = GachaMachineDirector(clock: { [clock] in clock.now })
        d.autoSchedule = false
        let env = GachaMachineEnv(balance: 500, cost: 50, shards: 3, ruby: Image(systemName: "circle"),
                                  portrait: { _ in Image(systemName: "circle") }, art: .vector, teaseChance: 0,
                                  haptics: GachaMachineNoHaptics(), pull: { try await gate.pull() }, onAgain: {}, onClose: {},
                                  blockedReason: nil, againEnabled: true, isActive: true, reduceMotion: false, onFrame: nil)
        d.update(env: env)
        d.autoTurn()
        clock.now = clock.now.addingTimeInterval(d.autoTurnDuration)
        d.advance(clock.now)
        for _ in 0..<50 where !gate.isWaiting { await Task.yield() }
        gate.succeed(GachaRevealOutcome(characterID: "aing_gold", name: "황금 아잉이", kind: .gold, shardCount: 3))
        await d.pullTask?.value
        let ds = try #require(d.dropStart)
        clock.now = max(clock.now, ds.addingTimeInterval(d.drop.total + 0.01))
        d.advance(clock.now)
        d.skipTaps(clock.now)
        let burst = try #require(d.burstTime)
        clock.now = burst.addingTimeInterval(GTiming.goldBuild + 0.5)
        guard case .reveal = d.phase(clock.now) else {
            Issue.record("황금 공개가 아니다: \(d.phase(clock.now))")
            throw CancellationError()
        }
        return (d, env, clock.now)
    }

    /// 무대를 위아래로 `extra` 씩 더 긴 판 가운데 놓고 **창에서** 뜬다(Canvas 가 잘리는 실제 그리기 길).
    private func captureInWindow(_ d: GachaMachineDirector, _ env: GachaMachineEnv, now: Date, scheme: ColorScheme) async throws -> NSBitmapImageRep {
        let size = CGSize(width: GLayout.size.width, height: GLayout.size.height + 2 * Self.extra)
        let stage = GachaMachineStage(d: d, env: env, theme: .of(scheme), sprites: GachaCapsuleSprites.shared(for: .vector), now: now)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
        let window = BleedProbeWindow(contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        let hosting = NSHostingView(rootView: stage)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        // 화면 밖에서만 앞으로(활성화 · 키 없음). 모든 화면의 테두리 밖인지 먼저 잰다.
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) }, "프로브 창이 화면 안에 걸친다")
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(10)) }
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// 무대 좌표(무대 왼쪽 위가 원점, 위로 넘치면 음수) 띠의 평균 밝기(0…1).
    private func meanLuma(_ rep: NSBitmapImageRep, stageY y0: CGFloat, _ y1: CGFloat, x0: CGFloat = 60, x1: CGFloat = 320) -> Double {
        let scaleX = CGFloat(rep.pixelsWide) / rep.size.width
        let scaleY = CGFloat(rep.pixelsHigh) / rep.size.height
        var sum = 0.0, n = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let px = Int(x * scaleX), py = Int((y + Self.extra) * scaleY)
                if let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) {
                    sum += 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                    n += 1
                }
                x += 4
            }
            y += 2
        }
        return n == 0 ? 0 : sum / Double(n)
    }

    @Test("황금 공개의 빛이 무대 위 테두리에서 끊기지 않는다 — 테두리 바로 위 띠가 바로 안 띠만큼 밝다(밝은 · 어두운 모드)")
    func goldBurstIsNotCutAtStageTop() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let (d, env, now) = try await goldRevealDirector()
            let rep = try await captureInWindow(d, env, now: now, scheme: scheme)
            #expect(rep.pixelsWide > 0 && rep.pixelsHigh > 0)
            // 테두리 바로 위 · 바로 아래의 얇은 띠(칩 두 개를 비켜 가운데 x 110…270). 빛이 이어지면 거의 같고, 잘리면 위는 바탕뿐이다.
            let inside = meanLuma(rep, stageY: 2, 8, x0: 110, x1: 270)
            let above = meanLuma(rep, stageY: -8, -2, x0: 110, x1: 270)
            // 기준선: 빛이 닿지 않는 맨 위(무대 중심에서 300 넘게 떨어진 띠)는 어둡다 — 잴 그림이 실제로 그려졌다는 뜻.
            let far = meanLuma(rep, stageY: -Self.extra + 2, -Self.extra + 12)
            #expect(inside > far + 0.05, "\(scheme): 빛이 그려지지 않았다(안 \(inside) · 먼 곳 \(far))")
            #expect(above > inside * 0.9,
                    "\(scheme): 무대 위 테두리에서 빛이 잘렸다 — 위 \(String(format: "%.3f", above)) · 안 \(String(format: "%.3f", inside))")
        }
    }
}
