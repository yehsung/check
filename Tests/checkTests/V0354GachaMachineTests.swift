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

    @Test("다시 보이기 시작한 첫 박자는 햅틱을 몰아 내지 않는다")
    func resyncAfterInactive() async {
        let r = gmRig()
        var env = gmEnv(haptics: r.haptics, gate: r.gate)
        env.isActive = false
        r.d.update(env: env)
        env.isActive = true
        r.d.update(env: env)
        let before = r.haptics.events.count
        r.d.emitBeats(old: GBeats(phaseKey: 3), new: GBeats(phaseKey: 5, landed: true, shardLanded: true), now: r.now)
        #expect(r.haptics.events.count == before)
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

    @Test("Package.swift 는 GachaMachine 그림을 .copy 로 싣는다, 맥 패키징 둘은 CheckCore 번들을 통째로 복사한다")
    func packagingCarriesTheArt() throws {
        let pkg = try gmSource("Package.swift")
        #expect(pkg.contains(#".copy("Resources/GachaMachine")"#))
        #expect(!pkg.contains(#".process("Resources/GachaMachine")"#))
        let local = try gmSource("scripts/build-local.sh")
        #expect(local.contains("check_CheckCore.bundle"))
        #expect(local.contains(#"cp -R "$RESOURCE_BUNDLE" "$RES_DIR/""#))
        let mas = try gmSource("scripts/package-mas.sh")
        #expect(mas.contains("for TARGET in check CheckCore"))
        #expect(mas.contains(#"cp -R "$SRC_BUNDLE" "$RES_DIR/""#))
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
}
