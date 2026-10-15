import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CheckCore

// v0.3.54 — 캡슐 뽑기 기계(CheckCore/GachaMachine). 맥 뽑기 창과 폰 전체 화면이 같은 기계를 띄운다.
//
// 감독(상태 기계)은 시계를 손으로 넘기며 뷰 없이 몬다(`autoSchedule = false` + `advance(_:)`) — 앱에서 감독이 스스로 깨어나
// 부르는 바로 그 함수다. 돈이 걸린 규칙을 잰다: 모자라면 `pull` 을 안 부른다 · 한 판에 한 번 · 실패는 공개 없이 처음으로 ·
// [한 번 더] 는 공개가 자리 잡은 뒤에만 · 황금 · 동작 줄이기. 그림 번들(다섯 장)이 실제 번들에 실렸는지도 잰다.
// 뷰 배선(멈춤 입력)은 동작으로 몰 수 없어 **주석을 걷어낸** 소스 계약으로 잰다.

// MARK: - 도우미

@MainActor
private final class GMClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ s: Double) { now = now.addingTimeInterval(s) }
}

@MainActor
private final class GMHaptics: GachaMachineHaptics {
    var events: [GachaMachineHapticEvent] = []
    func play(_ event: GachaMachineHapticEvent) { events.append(event) }
}

/// `pull` 이 몇 번 불렸고, 언제 무엇으로 끝날지 시험이 정한다.
@MainActor
private final class GMPullGate {
    var calls = 0
    private var pending: CheckedContinuation<GachaRevealOutcome, Error>?
    func pull() async throws -> GachaRevealOutcome {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func succeed(_ outcome: GachaRevealOutcome) { pending?.resume(returning: outcome); pending = nil }
    func fail(_ error: Error) { pending?.resume(throwing: error); pending = nil }
    var isWaiting: Bool { pending != nil }
}

private struct GMOtherError: Error {}

@MainActor
private struct GMRig {
    let d: GachaMachineDirector
    let clock: GMClock
    let haptics: GMHaptics
    let gate: GMPullGate
    var againCalls: () -> Int

    var now: Date { clock.now }
}

@MainActor
private func gmEnv(balance: Int = 500, cost: Int = 50, reduceMotion: Bool = false, blockedReason: String? = nil,
                   againEnabled: Bool = true, teaseChance: Double = 0, haptics: GMHaptics, gate: GMPullGate,
                   onAgain: @escaping () -> Void = {}) -> GachaMachineEnv {
    GachaMachineEnv(balance: balance, cost: cost, shards: 3, ruby: Image(systemName: "circle"), portrait: { _ in Image(systemName: "circle") },
                    art: .vector, teaseChance: teaseChance, haptics: haptics, pull: { try await gate.pull() },
                    onAgain: onAgain, onClose: {}, blockedReason: blockedReason, againEnabled: againEnabled,
                    isActive: true, reduceMotion: reduceMotion, onFrame: nil)
}

@MainActor
private func gmRig(balance: Int = 500, reduceMotion: Bool = false, blockedReason: String? = nil, againEnabled: Bool = true,
                   teaseChance: Double = 0) -> GMRig {
    let clock = GMClock()
    let haptics = GMHaptics()
    let gate = GMPullGate()
    let box = GMCounter()
    let d = GachaMachineDirector(clock: { [clock] in clock.now })
    d.autoSchedule = false
    d.update(env: gmEnv(balance: balance, reduceMotion: reduceMotion, blockedReason: blockedReason, againEnabled: againEnabled,
                        teaseChance: teaseChance, haptics: haptics, gate: gate, onAgain: { box.n += 1 }))
    return GMRig(d: d, clock: clock, haptics: haptics, gate: gate, againCalls: { box.n })
}

@MainActor private final class GMCounter { var n = 0 }

private let gmNew = GachaRevealOutcome(characterID: "fox", name: "여우", kind: .new, shardCount: 3)
private let gmDup = GachaRevealOutcome(characterID: "squirrel", name: "다람쥐", kind: .duplicate, shardCount: 4)
private let gmGold = GachaRevealOutcome(characterID: "aing_gold", name: "황금 아잉이", kind: .gold, shardCount: 3)

/// 손잡이 클릭(자동 회전) → 한 바퀴 끝 → 커밋(`pull` 부름).
@MainActor
private func gmTurn(_ r: GMRig) async {
    r.d.autoTurn()
    r.clock.advance(r.d.autoTurnDuration)
    r.d.advance(r.now)
    await Task.yield()
}

/// 돌고 있는 `pull` 을 끝내고 감독이 결과를 받을 때까지 기다린다.
@MainActor
private func gmResolve(_ r: GMRig, _ outcome: GachaRevealOutcome) async {
    for _ in 0..<50 where !r.gate.isWaiting { await Task.yield() }
    r.gate.succeed(outcome)
    await r.d.pullTask?.value
}

@MainActor
private func gmReject(_ r: GMRig, _ error: Error) async {
    for _ in 0..<50 where !r.gate.isWaiting { await Task.yield() }
    r.gate.fail(error)
    await r.d.pullTask?.value
}

/// 캡슐이 가운데 앉을 때까지 시계를 넘긴다(톡톡 단계).
@MainActor
private func gmToTapping(_ r: GMRig) {
    guard let ds = r.d.dropStart else { return }
    r.clock.now = max(r.now, ds.addingTimeInterval(r.d.drop.total + 0.01))
    r.d.advance(r.now)
}

@MainActor
private func gmTapThree(_ r: GMRig) {
    for _ in 0..<3 {
        r.d.press(r.now)
        r.clock.advance(0.2)
    }
}

/// `//` · `/* */` 주석을 걷어낸다(문자열 리터럴 안은 남긴다).
private func gmStripComments(_ source: String) -> String {
    var out = ""
    var inString = false, inLine = false, inBlock = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            if c == "\"", i == 0 || chars[i - 1] != "\\" { inString = false }
            out.append(c)
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}

private func gmSource(_ relative: String) throws -> String {
    gmStripComments(try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(relative), encoding: .utf8))
}

// MARK: - 상태 기계

@MainActor
@Suite("V0354 GachaMachine — 감독(상태 기계)")
struct V0354GachaMachineDirectorTests {
    @Test("루비가 모자라면 손잡이 · 커밋 · 끌기 어디로도 pull 을 부르지 않는다")
    func refusesWhenShortWithoutPulling() async {
        let r = gmRig(balance: 49)
        r.d.autoTurn()
        #expect(r.d.autoTurnStart == nil)
        r.d.commit()
        r.d.dragChanged(location: CGPoint(x: GLayout.knobCenter.x + 30, y: GLayout.knobCenter.y), translation: CGSize(width: 10, height: 0))
        r.d.dragEnded()
        r.clock.advance(2)
        r.d.advance(r.now)
        await Task.yield()
        #expect(r.gate.calls == 0)
        #expect(r.d.pullCount == 0)
        #expect(r.d.commitTime == nil)
        #expect(r.d.refuseTime != nil)
        #expect(r.haptics.events.contains(.refuse))
        #expect(r.d.phase(r.now) == .idle)
    }

    @Test("호스트가 막으면(업데이트 필요 등) 잔액이 넉넉해도 pull 을 부르지 않는다")
    func refusesWhenBlocked() async {
        let r = gmRig(balance: 5000, blockedReason: GachaText.needsUpdate)
        r.d.autoTurn()
        r.clock.advance(1)
        r.d.advance(r.now)
        r.d.commit()
        await Task.yield()
        #expect(r.gate.calls == 0)
        #expect(r.d.commitTime == nil)
    }

    @Test("한 판에 pull 은 한 번 — 도는 동안 다시 돌리기 · 커밋 · [한 번 더] 를 눌러도 더 부르지 않는다")
    func onePullPerTurn() async {
        let r = gmRig()
        await gmTurn(r)
        #expect(r.gate.calls == 1)
        #expect(r.d.pullInFlight)
        // 연타 · 다시 끌기 · 커밋 직접 호출 · [한 번 더]
        r.d.autoTurn()
        r.d.commit()
        r.d.dragChanged(location: CGPoint(x: GLayout.knobCenter.x + 30, y: GLayout.knobCenter.y), translation: CGSize(width: 10, height: 0))
        r.d.again()
        r.clock.advance(1)
        r.d.advance(r.now)
        await Task.yield()
        #expect(r.gate.calls == 1)
        #expect(r.d.pullCount == 1)
        await gmResolve(r, gmNew)
        #expect(!r.d.pullInFlight)
        #expect(r.d.result == gmNew)
        #expect(r.gate.calls == 1)
    }

    @Test("실패: 공개 없이 짧은 한 줄 → 2.4초 뒤 손잡이가 처음 자리로(캡슐 없음 · 다시 돌릴 수 있음)")
    func failureResetsWithoutReveal() async {
        let r = gmRig()
        await gmTurn(r)
        r.clock.advance(0.3)
        await gmReject(r, GachaRevealFailure(message: GachaText.unavailable))
        #expect(r.d.failText == GachaText.unavailable)
        #expect(r.d.result == nil)
        #expect(r.d.dropStart == nil)
        guard case .failed = r.d.phase(r.now) else { Issue.record("실패 단계가 아니다: \(r.d.phase(r.now))"); return }
        #expect(r.haptics.events.last == .refuse)
        // 실패 중엔 손잡이가 안 돈다
        r.d.autoTurn()
        #expect(r.d.autoTurnStart == nil)
        // 실패가 떠 있는 동안 어느 순간에도 공개가 아니다
        for step in stride(from: 0.0, through: 2.3, by: 0.1) {
            if case .reveal = r.d.phase(r.now.addingTimeInterval(step)) { Issue.record("실패한 뽑기를 공개했다 at \(step)") }
        }
        r.clock.advance(GTiming.failHold + 0.01)
        r.d.advance(r.now)
        #expect(r.d.phase(r.now) == .idle)
        #expect(r.d.commitTime == nil)
        #expect(r.d.knobAngle(r.now) < 1)
        // 다시 돌릴 수 있고, 그때 pull 은 새로 한 번
        await gmTurn(r)
        #expect(r.gate.calls == 2)
    }

    @Test("우리가 모르는 실패는 GachaText.pullFailed 로 말한다(루비가 깎였는지 모르므로 '그대로'라고 하지 않는다)")
    func unknownFailureUsesGenericLine() async {
        let r = gmRig()
        await gmTurn(r)
        await gmReject(r, GMOtherError())
        #expect(r.d.failText == GachaText.pullFailed)
        #expect(!r.d.failText.contains("그대로"))
    }

    @Test("판이 바뀐 뒤 늦게 온 결과는 버린다")
    func staleResultIsDropped() async {
        let r = gmRig()
        await gmTurn(r)
        r.d.resetPull(r.now)
        await gmResolve(r, gmGold)
        #expect(r.d.result == nil)
        #expect(r.d.phase(r.now) == .idle)
    }

    @Test("[한 번 더] 는 공개가 자리 잡은(버튼이 뜬) 뒤에만 — 그 전엔 무시, 뒤엔 한 번만 새 pull")
    func againOnlyAfterRevealSettles() async {
        let r = gmRig()
        await gmTurn(r)
        r.clock.advance(0.3)
        await gmResolve(r, gmNew)
        gmToTapping(r)
        #expect(r.d.phase(r.now) == .tapping(taps: 0))
        r.d.again()
        #expect(r.againCalls() == 0)
        gmTapThree(r)
        guard case .reveal(let t) = r.d.phase(r.now) else { Issue.record("공개가 아니다"); return }
        #expect(t < GTiming.buttonsAt(.new))
        r.d.again()
        #expect(r.againCalls() == 0)
        #expect(r.d.againAt == nil)
        #expect(!r.d.revealSettled(r.now))
        r.clock.advance(GTiming.buttonsAt(.new))
        #expect(r.d.revealSettled(r.now))
        r.d.again()
        r.d.again()   // 연타
        #expect(r.againCalls() == 1)
        #expect(r.d.againAt != nil)
        #expect(r.d.phase(r.now) == .idle)
        #expect(r.d.outgoing == gmNew)
        // 0.42초 뒤 저절로 돌고, 다 돌면 pull 한 번
        r.clock.advance(GTiming.againDelay)
        r.d.advance(r.now)
        #expect(r.d.autoTurnStart != nil)
        r.d.again()
        r.clock.advance(r.d.autoTurnDuration)
        r.d.advance(r.now)
        await Task.yield()
        #expect(r.gate.calls == 2)
    }

    @Test("[한 번 더] 를 호스트가 끄면 받지 않는다")
    func againDisabledByHost() async {
        let r = gmRig(againEnabled: false)
        await gmTurn(r)
        await gmResolve(r, gmNew)
        gmToTapping(r)
        gmTapThree(r)
        r.clock.advance(3)
        r.d.again()
        #expect(r.againCalls() == 0)
        #expect(r.d.againAt == nil)
        #expect(r.gate.calls == 1)
    }

    @Test("황금: 황금 낙하 시간표 → 톡 세 번 → 0.8초 모으기 → 공개(황금 짠 햅틱)")
    func goldPath() async {
        let r = gmRig(teaseChance: 0)
        await gmTurn(r)
        await gmResolve(r, gmGold)
        #expect(r.d.isGold)
        #expect(!r.d.tease)
        #expect(r.d.drop == GDropTimes.gold)
        gmToTapping(r)
        var old = r.d.beats(r.now)
        for _ in 0..<3 { r.d.press(r.now); r.clock.advance(0.15) }
        r.clock.advance(-0.15)
        guard case .building = r.d.phase(r.now) else { Issue.record("모으기가 아니다: \(r.d.phase(r.now))"); return }
        old = r.d.beats(r.now)
        r.clock.advance(GTiming.goldBuild + 0.01)
        let new = r.d.beats(r.now)
        r.d.emitBeats(old: old, new: new, now: r.now)
        guard case .reveal = r.d.phase(r.now) else { Issue.record("공개가 아니다"); return }
        #expect(r.haptics.events.contains(.goldReveal))
        #expect(r.d.buttonsAt(.gold) == GTiming.buttonsAt(.gold))
    }

    @Test("황금 반전(평범한 캡슐 → 톡 두 번째에 황금)은 확률 1 이면 늘, 0 이면 없다")
    func goldTease() async {
        let r = gmRig(teaseChance: 1)
        await gmTurn(r)
        await gmResolve(r, gmGold)
        #expect(r.d.tease)
        #expect(r.d.drop == GDropTimes.normal)
        gmToTapping(r)
        r.d.press(r.now); r.clock.advance(0.2); r.d.press(r.now)
        #expect(r.haptics.events.contains(.goldFlip))
    }

    @Test("동작 줄이기: 톡톡 · 흔들기 없이 떨어짐 → 겹쳐 바뀌는 공개, 같은 결과 · 같은 글자, 잔잔한 움직임 0")
    func reduceMotionPath() async {
        let r = gmRig(reduceMotion: true, teaseChance: 1)
        r.d.autoTurn()
        #expect(r.d.autoTurnDuration <= 0.45)
        r.clock.advance(r.d.autoTurnDuration)
        r.d.advance(r.now)
        await Task.yield()
        #expect(r.d.reduced)
        await gmResolve(r, gmDup)
        #expect(!r.d.tease)                        // 반전 연출도 없다
        #expect(r.d.drop == GDropTimes.reduced)
        guard let ds = r.d.dropStart else { Issue.record("낙하가 없다"); return }
        #expect(r.d.burstTime == ds.addingTimeInterval(GDropTimes.reduced.total))
        // 떨어지는 동안 → 바로 공개(톡톡 단계를 거치지 않는다)
        for step in stride(from: 0.0, through: GDropTimes.reduced.total + 2, by: 0.05) {
            if case .tapping = r.d.phase(ds.addingTimeInterval(step)) { Issue.record("동작 줄이기에서 톡톡 단계 at \(step)") }
            #expect(r.d.ambient(ds.addingTimeInterval(step)) == 0)
        }
        r.clock.now = ds.addingTimeInterval(GDropTimes.reduced.total + 0.01)
        guard case .reveal = r.d.phase(r.now) else { Issue.record("공개가 아니다"); return }
        #expect(r.d.result == gmDup)
        #expect(GachaMachineText.announcement(gmDup) == "이미 있는 친구예요. 다람쥐 조각 +1")
        // 버튼 · [한 번 더] 시간표는 줄인 쪽
        r.clock.advance(GTiming.Reduced.buttonsAt(.duplicate))
        #expect(r.d.revealSettled(r.now))
        // 공개 뒤 조금 지나면 멎는다(매 프레임 그리지 않는다)
        #expect(r.d.quietAt(r.now) != nil)
    }

    @Test("손대지 않으면 잔잔한 움직임이 잦아들고 멎는다 — 멎은 뒤엔 깨어날 일도 없다")
    func idleGoesQuiet() {
        let r = gmRig()
        r.d.touched(r.now)
        #expect(r.d.framesWanted)
        #expect(r.d.ambient(r.now) == 1)
        let quiet = r.d.quietAt(r.now)
        #expect(quiet != nil)
        let q = quiet ?? r.now
        #expect(abs(q.timeIntervalSince(r.now) - (GTiming.ambientGrace + GTiming.ambientFade + 0.05)) < 0.001)
        r.clock.now = q
        r.d.advance(r.now)
        #expect(!r.d.framesWanted)
        #expect(r.d.ambient(r.now) == 0)
        #expect(r.d.nextWake(r.now) == nil)
        // 무슨 일이 생기면 다시 그린다
        r.d.autoTurn()
        #expect(r.d.framesWanted)
        #expect(r.d.quietAt(r.now) == nil)
    }

    @Test("시간만으로 단계가 넘어가도(떨어짐 → 톡톡) 깨어나 다시 보고 결국 멎는다")
    func timeOnlyPhaseChangeStillGoesQuiet() async {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmNew)
        // 떨어지는 동안: 멎는 때를 모른다 → 그래도 깨어날 때가 있어야 한다
        #expect(r.d.quietAt(r.now) == nil)
        let wake = r.d.nextWake(r.now)
        #expect(wake != nil)
        // 깨어날 때마다 advance — 손대지 않고 톡톡 단계에 들어가 기다리면 멎는다
        var t = r.now
        for _ in 0..<60 {
            guard let w = r.d.nextWake(t) else { break }
            t = w
            r.clock.now = t
            r.d.advance(t)
        }
        #expect(r.d.phase(r.now) == .tapping(taps: 0))
        #expect(!r.d.framesWanted)
        #expect(r.d.nextWake(r.now) == nil)
    }

    @Test("공개 뒤에도 멎는다(빛줄기 회전 · 둥실이 끝나면 정지 화면)")
    func revealGoesQuiet() async {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmDup)
        gmToTapping(r)
        gmTapThree(r)
        guard let b = r.d.burstTime, let q = r.d.quietAt(r.now) else { Issue.record("멎는 때가 없다"); return }
        let end = GTiming.revealOneShotEnd(.duplicate) + GTiming.revealAmbientGrace + GTiming.ambientFade
        #expect(abs(q.timeIntervalSince(b) - (end + 0.05)) < 0.01)
        #expect(r.d.ambient(q) == 0)
        r.clock.now = q
        r.d.advance(r.now)
        #expect(!r.d.framesWanted)
    }

    @Test("자동 회전 톱니 · 착지 · 공개 · 조각 햅틱은 박자가 바뀌는 순간 한 번씩")
    func beatsEmitHaptics() async {
        let r = gmRig()
        r.d.autoTurn()
        var old = r.d.beats(r.now)
        for _ in 0..<20 {
            r.clock.advance(r.d.autoTurnDuration / 20)
            let new = r.d.beats(r.now)
            r.d.emitBeats(old: old, new: new, now: r.now)
            old = new
        }
        let ratchets = r.haptics.events.filter { $0 == .ratchet }.count
        #expect(ratchets == 7)   // 45° 마다, 마지막(360°)은 커밋 쿵이 대신한다
        r.d.advance(r.now)
        await Task.yield()
        await gmResolve(r, gmDup)
        old = r.d.beats(r.now)
        gmToTapping(r)
        var new = r.d.beats(r.now)
        r.d.emitBeats(old: old, new: new, now: r.now)
        #expect(r.haptics.events.contains(.land))
        old = new
        gmTapThree(r)
        new = r.d.beats(r.now)
        r.d.emitBeats(old: old, new: new, now: r.now)
        #expect(r.haptics.events.filter { $0 == .reveal }.count == 1)
        old = new
        r.clock.advance(GTiming.dupFly1 + 0.1)
        new = r.d.beats(r.now)
        r.d.emitBeats(old: old, new: new, now: r.now)
        #expect(r.haptics.events.filter { $0 == .shard }.count == 1)
    }

    @Test("다시 보이기 시작한 첫 박자는 멈춘 동안 지나간 일로 햅틱을 몰아 내지 않는다 — 그 뒤의 실제 박자는 낸다")
    func resyncAfterInactive() async {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmDup)
        let dropping = r.d.beats(r.now)        // 마지막으로 그린 박자(떨어지기 전)
        var env = gmEnv(haptics: r.haptics, gate: r.gate)
        env.isActive = false
        r.d.update(env: env)
        // 안 보이는 동안 캡슐이 떨어져 착지했다(톡톡 단계)
        if let ds = r.d.dropStart { r.clock.now = ds.addingTimeInterval(r.d.drop.total + 2) }
        env.isActive = true
        r.d.update(env: env)
        let tapping = r.d.beats(r.now)
        #expect(tapping.landed && !dropping.landed, "전제: 멈춘 동안 박자가 바뀌었다(착지)")
        let before = r.haptics.events.count
        r.d.emitBeats(old: dropping, new: tapping, now: r.now)   // 다시 그린 첫 변화
        #expect(r.haptics.events.count == before, "멈춘 동안 지나간 착지로 햅틱을 냈다: \(r.haptics.events.suffix(2))")
        // 그 뒤 실제로 연 순간은 낸다
        gmTapThree(r)
        let reveal = r.d.beats(r.now)
        r.d.emitBeats(old: tapping, new: reveal, now: r.now)
        #expect(r.haptics.events.contains(.reveal))
    }
}

// MARK: - 안 보일 때 · 다시 보일 때(검토 S3)

@MainActor
@Suite("V0354 GachaMachine — 안 보일 때 돈이 안 나간다 · 다시 보일 때 박자")
struct V0354GachaMachineHiddenTests {
    @Test("자동 회전 중 안 보이게 되면(창 닫힘 · 최소화 · 가려짐) 커밋하지 않는다 — pull 0 · 손잡이는 처음 자리로 · 다시 보이면 새로 돌린다")
    func hiddenAutoTurnDoesNotPull() async {
        // 기준선: 보이는 채로 자동 회전이 끝나면 커밋한다(pull 한 번).
        let seen = gmRig()
        seen.d.autoTurn()
        seen.clock.advance(0.2)
        seen.clock.advance(seen.d.autoTurnDuration)
        seen.d.advance(seen.now)
        await Task.yield()
        #expect(seen.gate.calls == 1, "기준선: 보이는 채로 다 돈 손잡이가 pull 을 안 불렀다")

        let r = gmRig()
        var env = gmEnv(haptics: r.haptics, gate: r.gate)
        r.d.autoTurn()
        r.clock.advance(0.2)
        env.isActive = false
        r.d.update(env: env)          // 창을 닫았다 — 뷰가 다시 그리며 넘긴 값(맥은 닫아도 뷰가 안 사라진다)
        r.clock.advance(1.0)
        r.d.advance(r.now)            // 감독이 스스로 깨어 자동 회전 끝을 본다
        await Task.yield()
        #expect(r.gate.calls == 0, "안 보이는 기계가 손잡이를 마저 돌려 pull 을 불렀다 — 창 없이 루비 50 이 나간다")
        #expect(r.d.pullCount == 0)
        #expect(r.d.commitTime == nil && r.d.autoTurnStart == nil)
        r.clock.advance(2)
        #expect(r.d.knobAngle(r.now) < 1, "손잡이가 처음 자리로 안 돌아왔다(\(r.d.knobAngle(r.now)))")
        env.isActive = true
        r.d.update(env: env)
        await gmTurn(r)
        #expect(r.gate.calls == 1, "다시 보인 뒤 새로 돌린 판이 pull 을 안 불렀다")
    }

    @Test("[한 번 더] 를 누른 뒤 0.42초 안에 안 보이게 되면 손잡이가 저절로 돌지 않는다 — pull 은 공개된 판 하나뿐")
    func hiddenAgainDoesNotPull() async {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmNew)
        gmToTapping(r)
        gmTapThree(r)
        r.clock.advance(GTiming.buttonsAt(.new))
        #expect(r.d.revealSettled(r.now))
        r.d.again()
        #expect(r.d.againAt != nil, "전제: [한 번 더] 가 예약됐다")
        var env = gmEnv(haptics: r.haptics, gate: r.gate)
        env.isActive = false
        r.d.update(env: env)
        r.clock.advance(GTiming.againDelay + 0.01)
        r.d.advance(r.now)
        r.clock.advance(GTiming.autoTurn + 0.01)
        r.d.advance(r.now)
        await Task.yield()
        #expect(r.gate.calls == 1, "안 보이는 동안 [한 번 더] 가 손잡이를 돌려 두 번째 pull 을 불렀다")
        #expect(r.d.againAt == nil && r.d.autoTurnStart == nil && r.d.commitTime == nil)
    }

    @Test("앱 배선 그대로(스스로 깨어남 · 실제 시계): 자동 회전 중 안 보이게 되면 깨어나도 pull 하지 않는다 — 보이는 기준선은 pull 한 번")
    func hiddenAutoTurnWithRealWakeups() async throws {
        for hide in [false, true] {
            let haptics = GMHaptics(), gate = GMPullGate()
            let d = GachaMachineDirector()
            var env = gmEnv(haptics: haptics, gate: gate)
            d.update(env: env)
            d.autoTurn()
            try await Task.sleep(for: .milliseconds(100))
            if hide {
                env.isActive = false
                d.update(env: env)
            }
            try await Task.sleep(for: .milliseconds(1_300))
            if hide {
                #expect(d.pullCount == 0 && gate.calls == 0, "닫은 창의 감독이 스스로 깨어 pull 을 불렀다(\(d.pullCount))")
            } else {
                #expect(d.pullCount == 1, "기준선: 보이는 감독이 스스로 깨어 커밋하지 않았다 — 위 '안 부름'이 아무것도 안 잰다")
            }
            gate.succeed(gmNew)
            await d.pullTask?.value
            d.stop()
        }
    }

    @Test("결과를 아직 못 본 판: 왕복 중 · 공개 전 · 안 보이는 동안 공개가 끝남은 참, 보는 채로 끝남 · 실패 · 대기는 거짓")
    func unrevealedTurnTracksWhatTheUserSaw() async {
        let r = gmRig()
        #expect(!r.d.hasUnrevealedTurn(r.now), "대기 중인 기계에 못 본 판이 있다고 한다")
        await gmTurn(r)
        #expect(r.d.hasUnrevealedTurn(r.now), "왕복 중인데 못 본 판이 없다고 한다")
        await gmResolve(r, gmNew)
        #expect(r.d.hasUnrevealedTurn(r.now), "결과가 왔지만 공개 전인데 없다고 한다")
        gmToTapping(r)
        #expect(r.d.hasUnrevealedTurn(r.now), "캡슐이 톡톡을 기다리는데 없다고 한다")
        gmTapThree(r)
        r.clock.advance(GTiming.buttonsAt(.new))
        #expect(!r.d.hasUnrevealedTurn(r.now), "보는 채로 공개가 끝났는데 못 봤다고 한다 — 다시 열면 지난 공개 화면이 남는다")
        var env = gmEnv(haptics: r.haptics, gate: r.gate)
        env.isActive = false
        r.d.update(env: env)
        r.clock.advance(5)
        #expect(!r.d.hasUnrevealedTurn(r.now), "보고 나서 닫았는데 못 봤다고 한다")

        // 동작 줄이기: 톡톡 없이 저절로 공개되므로, 흔들리는 중에 닫으면 안 보이는 동안 공개가 끝난다 → 못 본 판이다.
        let q = gmRig(reduceMotion: true)
        await gmTurn(q)
        var qEnv = gmEnv(reduceMotion: true, haptics: q.haptics, gate: q.gate)
        qEnv.isActive = false
        q.d.update(env: qEnv)
        await gmResolve(q, gmDup)
        q.clock.advance(10)
        #expect(q.d.revealSettled(q.now), "전제: 안 보이는 동안 공개가 자리 잡았다")
        #expect(q.d.hasUnrevealedTurn(q.now), "안 보이는 동안 끝난 공개를 본 것으로 친다 — 다시 열면 산 캡슐이 사라진다")
        qEnv.isActive = true
        q.d.update(env: qEnv)
        #expect(!q.d.hasUnrevealedTurn(q.now), "다시 보여 결과가 화면에 있는데 아직 못 봤다고 한다")

        // 실패한 판은 지킬 것이 없다(공개가 없다).
        let f = gmRig()
        await gmTurn(f)
        await gmReject(f, GMOtherError())
        #expect(!f.d.hasUnrevealedTurn(f.now))
    }

    @Test("톡톡 단계에서 잠깐 안 보였다 돌아와도(그동안 박자 그대로) 다음 실제 공개는 햅틱 · 결과 알림을 낸다")
    func resumeWithoutChangeKeepsTheNextLiveBeat() async {
        for pause in [false, true] {
            let r = gmRig()
            await gmTurn(r)
            await gmResolve(r, gmNew)
            gmToTapping(r)
            let tapping = r.d.beats(r.now)
            if pause {
                // 확률 보기 · 알림 센터 · 창 가림 — 톡톡은 사용자를 기다리니 멈춘 동안 박자가 안 바뀐다(onChange 가 안 불린다)
                var env = gmEnv(haptics: r.haptics, gate: r.gate)
                env.isActive = false
                r.d.update(env: env)
                r.clock.advance(3)
                env.isActive = true
                r.d.update(env: env)
                #expect(r.d.beats(r.now) == tapping, "전제: 멈춘 동안 박자가 그대로다")
            }
            r.haptics.events.removeAll()
            r.d.skipTaps(r.now)        // 보이스오버 '캡슐 열기' · 톡 세 번
            r.clock.advance(0.05)
            let reveal = r.d.beats(r.now)
            r.d.emitBeats(old: tapping, new: reveal, now: r.now)
            #expect(r.haptics.events.contains(.reveal),
                    "\(pause ? "멈췄다 돌아온 뒤" : "기준선"): 실제 공개 박자가 햅틱 · 알림을 안 냈다(\(r.haptics.events))")
        }
    }
}

// MARK: - 결과 옮기기 · 덮개 · 문구

@MainActor
@Suite("V0354 GachaMachine — 결과 · 덮개 · 문구")
struct V0354GachaMachineModelTests {
    @Test("스토어 결과 → 연출 결과: 갈래 · 조각(서버 값이 이긴다)")
    func outcomeFromStoreResult() {
        let dup = GachaPullResult(characterID: "fox", isDuplicate: true, shardsGained: 1, shards: 9, rubyBalance: 10, replayed: false)
        let o = GachaRevealOutcome(result: dup, name: "여우", shardsBefore: 2)
        #expect(o.kind == .duplicate)
        #expect(o.shardCount == 9)
        #expect(o.shardCountBefore == 8)
        let fresh = GachaPullResult(characterID: "shiba", isDuplicate: false, shardsGained: 0, shards: nil, rubyBalance: nil, replayed: false)
        let n = GachaRevealOutcome(result: fresh, name: "강아지", shardsBefore: 4)
        #expect(n.kind == .new)
        #expect(n.shardCount == 4)
        #expect(n.shardsGained == 0)
        let goldDup = GachaPullResult(characterID: CharacterCatalog.goldAingID, isDuplicate: true, shardsGained: 1, shards: 5,
                                      rubyBalance: nil, replayed: false)
        let g = GachaRevealOutcome(result: goldDup, name: "황금 아잉이", shardsBefore: 4)
        #expect(g.kind == .gold)
        #expect(g.isGoldDuplicate)
        #expect(GTiming.shardLandAt(g, reduced: false) != nil)
        #expect(GachaMachineText.goldSubtitle(g).contains("조각 +1"))
    }

    @Test("배출구 덮개: 캡슐이 오기 전 닫힘 → 지나는 동안 열림 → 지나간 뒤 닫힘(떨어짐 밖은 늘 닫힘)")
    func chuteFlapOpensOnlyForTheCapsule() {
        for (T, reduced) in [(GDropTimes.normal, false), (GDropTimes.gold, false), (GDropTimes.reduced, true)] {
            if T.emerge0 > 0.1 {
                #expect(GachaMachineStage.flapOpen(td: 0, drop: T, reduced: reduced) == 0)
            }
            let mid = (T.emerge0 + 0.09 + T.emerge1 - 0.03) / 2
            #expect(GachaMachineStage.flapOpen(td: mid, drop: T, reduced: reduced) > 0.95)
            let settled = GachaMachineStage.flapOpen(td: T.total, drop: T, reduced: reduced)
            #expect(abs(settled) < 0.02)
            var minimum = 1.0
            for td in stride(from: 0.0, through: T.total, by: 0.005) {
                minimum = min(minimum, GachaMachineStage.flapOpen(td: td, drop: T, reduced: reduced))
            }
            if reduced { #expect(minimum >= 0) } else { #expect(minimum < 0) }   // 동작 줄이기: 흔들림(안쪽으로 넘어감) 없음
        }
    }

    @Test("어두운 테마: 바탕 · 글자 · 칩이 밝은 테마와 다르고, 어두운 바탕엔 밝은 글자")
    func darkThemeDiffers() {
        func lum(_ c: Color) -> Double {
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            return 0.2126 * n.redComponent + 0.7152 * n.greenComponent + 0.0722 * n.blueComponent
        }
        let l = GachaMachineTheme.light, n = GachaMachineTheme.night
        #expect(lum(n.bgTop) < 0.2 && lum(n.bgBottom) < 0.2)
        #expect(lum(l.bgTop) > 0.9)
        #expect(lum(n.title) > 0.85 && lum(l.title) < 0.2)
        #expect(lum(n.chipText) > 0.85)
        #expect(lum(n.ink) > 0.6)
        #expect(lum(n.warn) > 0.5)
        // 조각 꼬리: 밝은 바탕에선 진한 보라(배경과 대비), 어두운 바탕에선 밝은 보라
        #expect(lum(l.shardTrail) < 0.5)
        #expect(lum(n.shardTrail) > 0.5)
        #expect(GachaMachineTheme.of(.dark).dark)
        #expect(!GachaMachineTheme.of(.light).dark)
    }

    @Test("공개 글자는 정상 · 동작 줄이기가 같다(결과 갈래별 알림 문장)")
    func announcementCopy() {
        #expect(GachaMachineText.announcement(gmNew) == "새 캐릭터! 여우")
        #expect(GachaMachineText.announcement(gmGold) == "황금 아잉이! 아주 드문 친구를 만났어요")
        #expect(GachaMachineText.title(gmGold) == GachaText.goldHeadline)
        #expect(GachaMachineText.pullFailed == GachaText.pullFailed)
    }
}

// MARK: - 그림 번들 · 배선 계약

@MainActor
@Suite("V0354 GachaMachine — 그림 번들 · 배선")
struct V0354GachaMachineBundleTests {
    @Test("CheckCore 번들에 기계 그림 다섯 장이 GachaMachine/ 폴더째 실린다 — 원본과 같은 바이트")
    func bundleHasFiveArtPNGs() throws {
        let bundle = try #require(AIProviderArtwork.bundle, "check_CheckCore.bundle 을 못 찾았다")
        for name in GachaMachineArtBundle.resourceNames {
            let url = try #require(bundle.url(forResource: name, withExtension: "png", subdirectory: GachaMachineArtBundle.folderName),
                                   "번들에 \(name).png 가 GachaMachine/ 아래 없다")
            let shipped = try Data(contentsOf: url)
            let source = try Data(contentsOf: CheckCoreSourceLayout.repoRoot
                .appendingPathComponent("Sources/CheckCore/Resources/GachaMachine/\(name).png"))
            #expect(shipped == source, "\(name).png 가 원본과 다르다")
            #expect(GachaMachineArtBundle.decodedImage(at: url) != nil)
        }
        #expect(GachaMachineArtBundle.resourceNames.count == 5)
    }

    @Test("배포 그림 묶음(.bundled)은 다섯 칸이 다 찬다 — 벡터는 안전망일 뿐")
    func bundledArtIsComplete() {
        #expect(GachaMachineArt.bundled.isComplete)
        #expect(!GachaMachineArt.vector.isComplete)
    }

    @Test("Package.swift 는 GachaMachine 그림을 .copy 로 싣는다, 맥 패키징 둘은 CheckCore 번들을 통째로 복사하고 조립한 앱 안에서 다섯 장을 센다")
    func packagingCarriesTheArt() throws {
        let pkg = try gmSource("Package.swift")
        #expect(pkg.contains(#".copy("Resources/GachaMachine")"#))
        #expect(!pkg.contains(#".process("Resources/GachaMachine")"#))
        let local = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let mas = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/package-mas.sh"), encoding: .utf8)
        #expect(Self.packagingProblems(local: local, mas: mas) == [])
        // 비교 기준선(달라야 한다): 복사 고리에서 CheckCore 를 뺀 대본은 빨개야 한다. 설명 주석 · 서명 고리에 이름이 남아 있어도.
        let localDropped = local.replacingOccurrences(of: "for BUNDLE_NAME in check_check.bundle check_CheckCore.bundle; do",
                                                      with: "for BUNDLE_NAME in check_check.bundle; do")
        #expect(localDropped != local, "전제: 변형이 build-local.sh 의 복사 고리를 찾았다")
        #expect(!Self.packagingProblems(local: localDropped, mas: mas).isEmpty,
                "build-local.sh 복사 고리에서 CheckCore 번들을 빼도 초록이다 — 주석 속 이름이 대신 맞는다")
        let masDropped = Self.replacingFirst("for TARGET in check CheckCore; do", with: "for TARGET in check; do", in: mas)
        #expect(masDropped != mas, "전제: 변형이 package-mas.sh 의 복사 고리를 찾았다")
        #expect(!Self.packagingProblems(local: local, mas: masDropped).isEmpty,
                "package-mas.sh 복사 고리에서 CheckCore 번들을 빼도 초록이다 — 서명 고리의 같은 줄이 대신 맞는다")
    }

    /// 맥 패키징 대본 둘이 CheckCore 번들을 앱 Resources 로 복사하는가. 셸 `#` 주석 줄은 걷어내고, **복사 줄을 감싼 고리**의
    /// 머리를 본다(대본의 다른 고리 — 서명 — 에 같은 이름이 있어도 복사를 대신하지 못한다).
    static func packagingProblems(local: String, mas: String) -> [String] {
        func code(_ script: String) -> [String] {
            script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        }
        func loopHead(enclosing copyLine: String, in lines: [String]) -> String? {
            guard let at = lines.firstIndex(where: { $0.contains(copyLine) }) else { return nil }
            return lines[..<at].last { $0.trimmingCharacters(in: .whitespaces).hasPrefix("for ") }
        }
        var problems: [String] = []
        let localHead = loopHead(enclosing: #"cp -R "$RESOURCE_BUNDLE" "$RES_DIR/""#, in: code(local))
        if !(localHead?.contains("check_CheckCore.bundle") ?? false) {
            problems.append("build-local.sh: 복사 고리에 check_CheckCore.bundle 이 없다(\(localHead ?? "복사 줄 없음"))")
        }
        let masHead = loopHead(enclosing: #"cp -R "$SRC_BUNDLE" "$RES_DIR/""#, in: code(mas))
        if !(masHead?.contains("CheckCore") ?? false) {
            problems.append("package-mas.sh: 복사 고리에 CheckCore 가 없다(\(masHead ?? "복사 줄 없음"))")
        }
        // 조립한 앱 안에서 그림 다섯 장을 센다(대본이 멈춘다) — 이름은 코어가 찾는 이름 그대로.
        for (name, script) in [("build-local.sh", local), ("package-mas.sh", mas)] {
            let lines = code(script)
            guard lines.contains(where: { $0.contains(#"GACHA_ART_DIR="$RES_DIR/check_CheckCore.bundle/Contents/Resources/GachaMachine""#) }),
                  let head = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("for GACHA_PNG in ") }) else {
                problems.append("\(name): 조립한 앱 안의 뽑기 그림 확인이 없다")
                continue
            }
            let listed = head.trimmingCharacters(in: .whitespaces).dropFirst("for GACHA_PNG in ".count)
                .split(separator: ";").first.map { $0.split(separator: " ").map(String.init) } ?? []
            if Set(listed) != Set(GachaMachineArtBundle.resourceNames) {
                problems.append("\(name): 확인하는 그림 이름 \(listed) ≠ 코어 \(GachaMachineArtBundle.resourceNames)")
            }
        }
        return problems
    }

    private static func replacingFirst(_ target: String, with replacement: String, in text: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    @Test("뷰 배선: 보이지 않으면(isActive=false) · 멎었으면 TimelineView 를 멈춘다, 동작 줄이기는 시스템 설정을 따른다")
    func viewPausesWhenInactive() throws {
        let view = try gmSource("Sources/CheckCore/GachaMachine/GachaMachineView.swift")
        #expect(view.contains("let running = env.isActive && d.framesWanted"))
        #expect(view.contains("TimelineView(.animation(minimumInterval: nil, paused: !running))"))
        #expect(view.contains("@Environment(\\.accessibilityReduceMotion) private var systemReduceMotion"))
        #expect(view.contains("reduceMotion: systemReduceMotion"))
        // 기계 안의 TimelineView 는 하나뿐(다른 매 프레임 고리가 없다)
        let all = try ["GachaMachineView.swift", "GachaMachinePieces.swift", "GachaMachineEffects.swift", "GachaMachineDirector.swift"]
            .map { try gmSource("Sources/CheckCore/GachaMachine/\($0)") }.joined()
        #expect(all.components(separatedBy: "TimelineView(").count - 1 == 1)
        #expect(!all.contains(".repeatForever"))
    }
}

// MARK: - 그림(밝은 · 어두운)

@MainActor
@Suite("V0354 GachaMachine — 무대 그림")
struct V0354GachaMachineRenderTests {
    private func render(_ d: GachaMachineDirector, scheme: ColorScheme, now: Date) -> CGImage? {
        guard let env = d.env else { return nil }
        let stage = GachaMachineStage(d: d, env: env, theme: .of(scheme), sprites: GachaCapsuleSprites.shared(for: .vector), now: now)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: stage)
        renderer.scale = 1
        return renderer.cgImage
    }

    /// 칸 안 밝기(최소 · 최대 · 평균, 0…1).
    private func luma(_ image: CGImage, _ rect: CGRect) -> (min: Double, max: Double, mean: Double) {
        let w = Int(rect.width), h = Int(rect.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -rect.minX, y: -(CGFloat(image.height) - rect.maxY), width: CGFloat(image.width), height: CGFloat(image.height)))
        var lo = 1.0, hi = 0.0, sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let v = (0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255
            lo = min(lo, v); hi = max(hi, v); sum += v
        }
        return (lo, hi, sum / Double(w * h))
    }

    private func meanLuma(_ image: CGImage, _ rect: CGRect) -> Double { luma(image, rect).mean }

    @Test("대기 화면: 어두운 모드는 바탕이 어둡고 밝은 모드는 밝다(같은 감독 · 같은 시각)")
    func idleLightAndDark() throws {
        let r = gmRig()
        r.d.touched(r.now)
        let light = try #require(render(r.d, scheme: .light, now: r.now))
        let dark = try #require(render(r.d, scheme: .dark, now: r.now))
        #expect(light.width == Int(GLayout.size.width))
        let corner = CGRect(x: 4, y: 60, width: 30, height: 60)
        #expect(meanLuma(light, corner) > 0.85)
        #expect(meanLuma(dark, corner) < 0.25)
    }

    @Test("중복 조각 비행: 밝은 바탕엔 진한 테두리 · 꼬리, 어두운 바탕엔 밝은 결정 — 바탕과 확실히 갈린다")
    func shardFlightReadableOnLightAndDark() async throws {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmDup)
        gmToTapping(r)
        gmTapThree(r)
        let b = try #require(r.d.burstTime)
        let q = 0.5
        let at = b.addingTimeInterval(GTiming.dupCondense1 + q * (GTiming.dupFly1 - GTiming.dupCondense1))
        let p = GMath.bezier(GLayout.stageCenter, CGPoint(x: 40, y: 190), GLayout.shardChip, GMath.easeInOutCubic(q))
        let gemBox = CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)
        let bgBox = CGRect(x: p.x - 50, y: p.y - 5, width: 10, height: 10)
        let light = try #require(render(r.d, scheme: .light, now: at))
        let lg = luma(light, gemBox), lb = luma(light, bgBox)
        // 밝은 바탕: 결정의 진한 테두리가 바탕보다 확실히 어둡다(전에는 흰 빛 · 옅은 보라뿐이라 묻혔다)
        #expect(lg.min < lb.mean - 0.45, "밝은: 결정 최저 \(lg.min) · 바탕 \(lb.mean)")
        let dark = try #require(render(r.d, scheme: .dark, now: at))
        let dg = luma(dark, gemBox), db = luma(dark, bgBox)
        #expect(dg.max > db.mean + 0.4, "어두운: 결정 최고 \(dg.max) · 바탕 \(db.mean)")
        // 칩: 들어온 순간 칩이 번쩍(밝은 바탕에서도 칩 테가 진한 보라로)
        let landed = try #require(render(r.d, scheme: .light, now: b.addingTimeInterval(GTiming.dupFly1 + 0.05)))
        let before = try #require(render(r.d, scheme: .light, now: b.addingTimeInterval(GTiming.dupFly1 - 0.4)))
        // 칩 위 테두리 띠(글자는 피한다)
        let chip = CGRect(x: GLayout.shardChip.x - 30, y: GLayout.shardChip.y - 19, width: 60, height: 9)
        #expect(luma(landed, chip).mean < luma(before, chip).mean - 0.1, "칩 띠: 들어온 뒤 \(luma(landed, chip).mean) · 전 \(luma(before, chip).mean)")
    }

    // MARK: 글자 대비(WCAG — 작은 글자 4.5:1 · 큰 글자 3:1)

    private func render2x(_ d: GachaMachineDirector, scheme: ColorScheme, now: Date) -> CGImage? {
        guard let env = d.env else { return nil }
        let stage = GachaMachineStage(d: d, env: env, theme: .of(scheme), sprites: GachaCapsuleSprites.shared(for: .vector), now: now)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: stage)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 칸 안 화소의 WCAG 상대 휘도([행][열], 위에서부터).
    private func relLums(_ image: CGImage, _ rect: CGRect) -> [[Double]] {
        let w = Int(rect.width), h = Int(rect.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -rect.minX, y: -(CGFloat(image.height) - rect.maxY), width: CGFloat(image.width), height: CGFloat(image.height)))
        func ch(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return (0..<h).map { y in
            (0..<w).map { x in
                let i = (y * w + x) * 4
                return 0.2126 * ch(px[i]) + 0.7152 * ch(px[i + 1]) + 0.0722 * ch(px[i + 2])
            }
        }
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    @Test("톡톡 단계의 '건너뛰기'(보이스오버 '캡슐 열기'의 보이는 짝) 글자가 알약 바탕과 4.5:1 이상 — 밝은 · 어두운 둘 다")
    func skipLabelContrast() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let r = gmRig()
            await gmTurn(r)
            await gmResolve(r, gmNew)
            gmToTapping(r)
            r.clock.advance(1.0)   // 안내가 다 떠오른 뒤
            let image = try #require(render2x(r.d, scheme: scheme, now: r.now))
            // 알약 안쪽(글자 + 알약 바탕만): 가운데 (336, hintY), 글자 폭 ≈ 48pt · 알약 ≈ 68×25pt
            let box = CGRect(x: (336 - 28) * 2, y: (GLayout.hintY - 7) * 2, width: 56 * 2, height: 14 * 2)
            let lums = relLums(image, box).flatMap { $0 }
            let c = Self.contrast(lums.max() ?? 0, lums.min() ?? 0)
            print("[v0354-contrast] 건너뛰기 \(scheme): \(String(format: "%.2f", c)):1")
            #expect(c >= 4.5, "\(scheme): '건너뛰기' 대비 \(String(format: "%.2f", c)):1 — 작은 글자는 4.5:1 이상이어야 한다")
        }
    }

    @Test("밝은 테마: 중복 결과 글줄의 '+1'(24pt 굵은 큰 글자)이 공개 바탕과 3:1 이상")
    func duplicateGainContrast() async throws {
        let r = gmRig()
        await gmTurn(r)
        await gmResolve(r, gmDup)
        gmToTapping(r)
        gmTapThree(r)
        let b = try #require(r.d.burstTime)
        let image = try #require(render2x(r.d, scheme: .light, now: b.addingTimeInterval(3.0)))
        // 결과 글줄(가운데 y = 300, 24pt): 열마다 가장 어두운 값 → 바탕(중앙값)보다 확실히 어두운 마지막 열이 '+1' 의 '1' 오른쪽 끝
        let band = relLums(image, CGRect(x: 0, y: (300 - 9) * 2, width: GLayout.size.width * 2, height: 18 * 2))
        let columns = (0..<band[0].count).map { x in band.map { $0[x] }.min() ?? 1 }
        let background = columns.sorted()[columns.count / 2]
        let right = try #require(columns.lastIndex { $0 < background - 0.12 }, "글줄을 못 찾았다")
        let glyph = columns[max(0, right - 9)...right].min() ?? 1
        let besideRange = min(columns.count - 1, right + 6)...min(columns.count - 1, right + 30)
        let beside = columns[besideRange].sorted()[besideRange.count / 2]
        let c = Self.contrast(beside, glyph)
        print("[v0354-contrast] +1 light: \(String(format: "%.2f", c)):1 (글자 \(glyph) · 바탕 \(beside) · 끝 열 \(right))")
        #expect(c >= 3.0, "'+1' 대비 \(String(format: "%.2f", c)):1 — 큰 글자도 3:1 이상이어야 한다")
    }
}

// MARK: - 몸짓 취소(검토 S3)

@MainActor
@Suite("V0354 GachaMachine — 누름 · 손잡이 끌기가 취소돼도 풀린다")
struct V0354GachaMachineGestureTests {
    @Test("누름 · 손잡이 끌기는 취소(전화 · 시스템 알림 · 창 닫기)돼도 풀린다 — onEnded 는 취소에 안 온다, GestureState 가 되돌린다(주석 걷은 소스)")
    func gesturesResetOnCancellation() throws {
        let view = try gmSource("Sources/CheckCore/GachaMachine/GachaMachineView.swift")
        #expect(view.contains("@GestureState private var stageHeld = false"), "무대 누름에 취소를 아는 상태가 없다")
        #expect(view.contains("@GestureState private var knobHeld = false"), "손잡이 끌기에 취소를 아는 상태가 없다")
        #expect(view.contains(".updating($stageHeld)") && view.contains(".updating($knobHeld)"))
        #expect(view.contains("if !held, d.pressing { d.pressEnded() }"), "무대 누름이 취소되면 pressing 이 안 풀린다")
        #expect(view.contains("d.dragCancelled()"), "손잡이 끌기가 취소되면 dragging 이 안 풀린다")
    }

    @Test("손잡이 끌기 취소: 클릭으로 치지 않는다(저절로 안 돌고 pull 0) · 손잡이는 처음 자리로 · 기계가 멎는다 — 놓기(기준선)는 클릭이면 돈다")
    func cancelledKnobDragNeitherTurnsNorPulls() async {
        let knob = GLayout.knobCenter
        // 기준선(달라야 한다): 움직이지 않고 놓으면 클릭 — 저절로 한 바퀴.
        let click = gmRig()
        click.d.dragChanged(location: CGPoint(x: knob.x + 20, y: knob.y), translation: .zero)
        click.d.dragEnded()
        #expect(click.d.autoTurnStart != nil, "기준선: 클릭이 손잡이를 안 돌렸다")

        // 같은 누름이 취소되면 아무 일도 안 일어난다.
        let tap = gmRig()
        tap.d.dragChanged(location: CGPoint(x: knob.x + 20, y: knob.y), translation: .zero)
        tap.d.dragCancelled()
        #expect(!tap.d.dragging && tap.d.autoTurnStart == nil, "취소된 누름을 클릭으로 쳐서 손잡이를 돌렸다")

        // 반쯤 돌리다 취소: 커밋 없음 · 손잡이는 처음 자리로 · 손대지 않으면 멎는다.
        let r = gmRig()
        var p = CGPoint(x: knob.x + 30, y: knob.y)
        r.d.dragChanged(location: p, translation: .zero)
        for step in 1...6 {
            let a = Double(step) * 30 * .pi / 180
            p = CGPoint(x: knob.x + 30 * cos(a), y: knob.y + 30 * sin(a))
            r.d.dragChanged(location: p, translation: CGSize(width: 10, height: 10))
        }
        #expect(r.d.angle > 90 && r.d.dragging, "전제: 손잡이를 반쯤 돌렸다(\(r.d.angle)°)")
        r.d.dragCancelled()
        r.d.advance(r.now)
        await Task.yield()
        #expect(!r.d.dragging && r.d.commitTime == nil && r.d.autoTurnStart == nil && r.gate.calls == 0)
        r.clock.advance(2)
        #expect(r.d.knobAngle(r.now) < 1, "손잡이가 처음 자리로 안 돌아왔다(\(r.d.knobAngle(r.now))°)")
        r.clock.advance(GTiming.ambientGrace + GTiming.ambientFade)
        r.d.advance(r.now)
        #expect(!r.d.framesWanted, "취소한 뒤 손대지 않았는데 기계가 계속 매 프레임 그린다")
    }
}
