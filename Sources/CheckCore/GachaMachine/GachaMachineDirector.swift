import Foundation
import SwiftUI

// 기계의 감독(상태 + 시간표). 뷰는 `now` 를 받아 그림만 그리고, 상태는 전부 여기서 바뀐다.
//
// 시간에 기대는 전이(자동 회전 끝 → 커밋, 실패 2.4초 → 처음으로, [한 번 더] 0.42초 → 자동 회전, 장면이 멎는 순간)는
// **시계(`clock`)와 `advance(_:)`** 로 일어난다. 앱에서는 감독이 다음 할 일 시각에 스스로 깨어 `advance` 를 부르고,
// 시험은 시계를 손으로 넘기며 같은 함수를 부른다 — 그래서 상태 기계를 뷰 없이 몰 수 있다.

// MARK: - 수학 도우미

enum GMath {
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }
    /// a…b 구간에서 0→1 로 부드럽게.
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t)
    }
    static func ramp(_ a: Double, _ b: Double, _ x: Double) -> Double { clamp01((x - a) / (b - a)) }
    static func easeOutCubic(_ t: Double) -> Double { let u = 1 - clamp01(t); return 1 - u * u * u }
    static func easeInCubic(_ t: Double) -> Double { let u = clamp01(t); return u * u * u }
    static func easeInOutCubic(_ t: Double) -> Double {
        let u = clamp01(t); return u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    }
    static func easeOutBack(_ t: Double, _ s: Double = 1.7) -> Double {
        let u = clamp01(t) - 1; return 1 + (s + 1) * u * u * u + s * u * u
    }
    /// 감쇠 스프링 계단 응답: t<0 → 0, 이후 1 로 수렴(ζ<1 이면 넘쳤다 돌아온다).
    static func spring(_ t: Double, zeta: Double, freq: Double) -> Double {
        guard t > 0 else { return 0 }
        let w = 2 * .pi * freq
        let z = min(zeta, 0.999)
        let wd = w * sqrt(1 - z * z)
        return 1 - exp(-z * w * t) * (cos(wd * t) + z / sqrt(1 - z * z) * sin(wd * t))
    }
    /// 감쇠 사인: 쳤을 때의 떨림.
    static func ring(_ t: Double, freq: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        return exp(-decay * t) * sin(2 * .pi * freq * t)
    }
    static func ringCos(_ t: Double, freq: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        return exp(-decay * t) * cos(2 * .pi * freq * t)
    }
    static func bezier(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
                       y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    }
    /// `1 - smooth(a, b, x)` 를 0…x 로 적분한 값 — 잦아드는 회전(속도 × 봉투)의 각도. x ≥ b 면 상수(a + (b-a)/2).
    static func fadeIntegral(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard x > a else { return max(0, x) }
        let w = b - a
        let u = clamp01((x - a) / w)
        return a + w * u - w * (u * u * u - u * u * u * u / 2)
    }
}

/// 시드 고정 난수(연출 모양을 뽑기마다 바꾸되, 정지 화면은 재현 가능하게).
struct GRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func sign() -> Double { unit() < 0.5 ? -1 : 1 }
}

// MARK: - 배치(설계 좌표 380×460)

enum GLayout {
    static let size = CGSize(width: 380, height: 460)
    static let midX: CGFloat = 190

    // 몸통 그림(720×614 px)을 폭 260pt 로: k = 260/720
    static let bodyK: CGFloat = 260.0 / 720.0
    static let bodyOrigin = CGPoint(x: 60, y: 183)
    static let bodySize = CGSize(width: 260, height: 614 * bodyK)

    static let domeCenter = CGPoint(x: 190, y: 138)
    static let domeR: CGFloat = 96
    static let capRect = CGRect(x: 142, y: 12.5, width: 96, height: 39.2)

    /// 손잡이 소켓 중심(그림 358,222 px).
    static let knobCenter = CGPoint(x: 60 + 358 * bodyK, y: 183 + 222 * bodyK)
    static let knobR: CGFloat = 31
    static let notchR: CGFloat = 41

    /// 배출구 안쪽(그림 x233–490, y333–535 px).
    static let chuteRect = CGRect(x: 60 + 233 * bodyK, y: 183 + 333 * bodyK,
                                  width: (490 - 233) * bodyK, height: (535 - 333) * bodyK)
    static var chuteInside: CGPoint { CGPoint(x: chuteRect.midX, y: chuteRect.midY + 6) }
    static let tray = CGPoint(x: 190, y: 392)

    /// 배출구 덮개(그림 x229–490, y329–424 px — 잰 값: 덮개 아래 테 y418–421, 안쪽 벽 x236·x483).
    /// 경첩은 위 가장자리다. 그림에서 이 칸을 잘라 돌리고, 원래 자리는 배출구 안쪽 색으로 덮는다.
    static let flapArt = CGRect(x: 229, y: 329, width: 261, height: 95)
    static var flapRect: CGRect {
        CGRect(x: bodyOrigin.x + flapArt.minX * bodyK, y: bodyOrigin.y + flapArt.minY * bodyK,
               width: flapArt.width * bodyK, height: flapArt.height * bodyK)
    }
    static let flapCorner: CGFloat = 26 * bodyK

    static let stageCenter = CGPoint(x: 190, y: 196)
    static let capsuleSmall: CGFloat = 36
    static let capsuleBig: CGFloat = 112

    static let shardChip = CGPoint(x: 54, y: 24)
    static let rubyChip = CGPoint(x: 322, y: 24)
    static let hintY: CGFloat = 436
}

// MARK: - 시간표

struct GDropTimes: Equatable {
    var emerge0, emerge1, land, jump0, jump1, total: Double
    static let normal = GDropTimes(emerge0: 0.02, emerge1: 0.26, land: 0.24, jump0: 0.44, jump1: 0.88, total: 0.94)
    static let gold = GDropTimes(emerge0: 0.40, emerge1: 0.66, land: 0.64, jump0: 0.86, jump1: 1.34, total: 1.40)
    /// 동작 줄이기: 배출구에서 미끄러져 나와(튀지 않음) 잠깐 머문 뒤 바로 공개로 넘어간다.
    static let reduced = GDropTimes(emerge0: 0.0, emerge1: 0.35, land: 0.35, jump0: 0.85, jump1: 0.85, total: 0.85)
}

enum GTiming {
    static let minShake = 0.70        // 한 바퀴 뒤 쿵·덜컹 최소 시간
    static let kickEvery = 0.55       // 응답을 기다리는 동안 덜컹 간격
    static let autoTurn = 0.95        // 손잡이 클릭 시 자동 회전
    static let goldBuild = 0.80       // 황금: 마지막 톡 → 터짐까지 모으기
    static let failHold = 2.4         // 실패 줄이 떠 있다가 처음으로
    static let againDelay = 0.42      // [한 번 더] → 자동 회전
    // 공개 이후(터진 순간 0)
    static let badgeAt = 0.36
    static let nameAt = 0.50
    static let dupCondense0 = 1.25, dupCondense1 = 1.80, dupFly1 = 2.35
    static let goldTitleAt = 0.85, goldSubAt = 1.20
    static func buttonsAt(_ kind: GachaRevealKind) -> Double {
        switch kind { case .new: 0.95; case .duplicate: 2.25; case .gold: 2.40 }
    }
    /// 조각 칩이 올라가는 때(공개 기준). 조각을 안 받았으면 nil.
    static func shardLandAt(_ outcome: GachaRevealOutcome, reduced: Bool) -> Double? {
        switch outcome.kind {
        case .duplicate: return reduced ? Reduced.dupSwap : dupFly1
        case .gold: return outcome.shardsGained > 0 ? (reduced ? Reduced.nameAt + 0.6 : goldSubAt + 0.2) : nil
        case .new: return nil
        }
    }
    /// 공개 뒤 한 번 일어나는 움직임(빛 고리 · 칩 튐 · "+1 조각" 글자 …)이 모두 끝나는 때.
    static func revealOneShotEnd(_ kind: GachaRevealKind) -> Double {
        switch kind { case .new: 1.6; case .duplicate: 3.9; case .gold: 2.9 }
    }

    // 동작 줄이기(흔들기·튀기·입자 없음 — 떨어짐 → 겹쳐 바뀌는 공개)
    enum Reduced {
        static let badgeAt = 0.15
        static let nameAt = 0.20
        static let fade = 0.35
        static let dupSwap = 1.0
        static func buttonsAt(_ kind: GachaRevealKind) -> Double {
            switch kind { case .new: 0.6; case .duplicate: 1.35; case .gold: 1.0 }
        }
        static func oneShotEnd(_ kind: GachaRevealKind) -> Double { buttonsAt(kind) + 0.5 }
    }

    /// 잔잔한 움직임(돔 속 들썩임 · 손잡이 까딱 · 캡슐 둥실 · 빛줄기 회전)은 마지막 일 뒤 이만큼 이어지다 잦아든다.
    /// 잦아든 뒤엔 **매 프레임 그리지 않는다**(TimelineView 를 멈춘다) — 창을 띄워 둔 채로 CPU 를 쓰지 않게.
    static let ambientGrace = 6.0
    static let ambientFade = 0.8
    static let revealAmbientGrace = 2.5
}

// MARK: - 단계

enum GPhase: Equatable {
    case idle
    case shaking(t: Double, pending: Bool)  // 한 바퀴 뒤(t=커밋 후 시간)
    case dropping(t: Double)
    case tapping(taps: Int)
    case building(t: Double)                // 황금만: 터지기 전 모으기
    case reveal(t: Double)
    case failed(t: Double)

    var key: Int {
        switch self {
        case .idle: 0; case .shaking: 1; case .dropping: 2; case .tapping: 3
        case .building: 4; case .reveal: 5; case .failed: 6
        }
    }
}

/// 시간에서 파생되는 '박자' — 바뀌는 순간 햅틱을 낸다.
struct GBeats: Equatable {
    var phaseKey = 0
    var kicks = 0
    var landed = false
    var shardLanded = false
    /// 자동 회전 중에 지난 톱니 수(-1 = 자동 회전 아님).
    var autoNotch = -1
}

// MARK: - 호스트 값(뷰가 매 그리기마다 넘긴다)

struct GachaMachineEnv {
    var balance: Int
    var cost: Int
    var shards: Int
    var ruby: Image
    var portrait: (String) -> Image
    var art: GachaMachineArt
    var teaseChance: Double
    var haptics: any GachaMachineHaptics
    var pull: @MainActor () async throws -> GachaRevealOutcome
    var onAgain: () -> Void
    var onClose: () -> Void
    /// 호스트가 막은 이유(업데이트 필요 · 서버에 뽑기 없음 …). 있으면 손잡이가 안 돌고 이 줄이 뜬다.
    var blockedReason: String?
    /// [한 번 더] 를 받을까(호스트가 끄면 흐리게 · 눌리지 않는다).
    var againEnabled: Bool = true
    var isActive: Bool
    var reduceMotion: Bool
    var onFrame: ((Date) -> Void)?

    var canPay: Bool { balance >= cost }
    var canPull: Bool { canPay && blockedReason == nil }
}

// MARK: - 감독

@MainActor @Observable
final class GachaMachineDirector {
    // 시계 · 호스트 값 · 깨우기
    @ObservationIgnored var clock: () -> Date = { Date() }
    @ObservationIgnored var env: GachaMachineEnv?
    /// 앱: 다음 할 일 시각에 스스로 깨어난다. 시험은 끄고 `advance(_:)` 를 손으로 부른다.
    @ObservationIgnored var autoSchedule = true
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored var debugLog: [String]?

    // 손잡이
    var angle: Double = 0
    var dragging = false
    @ObservationIgnored var pointerAngle: Double?
    @ObservationIgnored var dragMoved = false
    var lastNotch = 0
    var tickTime: Date?
    var releaseAngle: Double = 0
    var releaseTime: Date?
    var refuseTime: Date?
    /// 자동 회전(시간으로 정해진다 — 시작 각 · 시작 시각 · 길이).
    var autoTurnStart: Date?
    var autoTurnFrom: Double = 0
    var autoTurnDuration: Double = 0
    var touchedHandle = false

    // 뽑기
    var commitTime: Date?
    var result: GachaRevealOutcome?
    var dropStart: Date?
    @ObservationIgnored var skipWhenReady = false
    var tease = false
    var tapTimes: [Date] = []
    var burstTime: Date?
    var failTime: Date?
    var failText = ""
    var seed: UInt64 = 7
    var returnTime: Date?
    var outgoing: GachaRevealOutcome?
    var outgoingTime: Date?
    var againAt: Date?
    /// 결과가 도착한 때(공개에 처음 나올 그림을 이때 미리 한 번 그려 둔다).
    var arrivedAt: Date?
    var pressing = false
    /// 다시 보이기 시작한 순간의 박자. 다음 박자 변화는 (멈추기 전 박자가 아니라) 이것과 견준다 — 멈춘 동안 지나간 박자로
    /// 햅틱을 몰아 내지 않되, 멈춘 동안 아무것도 안 바뀌었으면 다음 실제 박자(공개 · 결과 알림)는 그대로 낸다.
    @ObservationIgnored var resyncBase: GBeats?
    @ObservationIgnored private var wasActive = true
    /// 안 보이기 시작한 때(보이면 nil). 공개가 이 뒤에 자리 잡았으면 사용자는 아직 결과를 못 본 것이다.
    @ObservationIgnored private(set) var hiddenSince: Date?
    /// 이번 판이 동작 줄이기로 도는가(커밋 순간의 설정을 쥔다 — 도중에 바꿔도 판이 안 꼬인다).
    var reduced = false
    /// 마지막으로 무슨 일이 있었던 때(잔잔한 움직임이 이 뒤로 `ambientGrace` 만큼 이어진다).
    var lastEvent: Date
    /// 지금 매 프레임 그려야 하는가(아니면 TimelineView 를 멈춘다).
    var framesWanted = true

    /// `pull` 이 돌고 있는가(돌고 있으면 새 판을 못 시작한다 — 두 번 깎이지 않게).
    private(set) var pullInFlight = false
    /// 지금까지 부른 `pull` 횟수(시험이 "한 판에 한 번"을 잰다).
    private(set) var pullCount = 0
    @ObservationIgnored private(set) var pullTask: Task<Void, Never>?
    /// 판 번호 — 판이 바뀐 뒤 늦게 온 결과는 버린다.
    @ObservationIgnored private var turn = 0

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
        lastEvent = clock()
    }

    var isGold: Bool { result?.kind == .gold }
    var drop: GDropTimes { reduced ? .reduced : ((isGold && !tease) ? .gold : .normal) }
    var goldBuild: Double { (isGold && !reduced) ? GTiming.goldBuild : 0 }

    // MARK: 단계 판정(순수)

    func phase(_ now: Date) -> GPhase {
        guard let commit = commitTime else { return .idle }
        if let f = failTime { return .failed(t: now.timeIntervalSince(f)) }
        let tc = now.timeIntervalSince(commit)
        guard let ds = dropStart, now >= ds else { return .shaking(t: tc, pending: result == nil) }
        let td = now.timeIntervalSince(ds)
        if td < drop.total { return .dropping(t: td) }
        guard let b = burstTime, now >= b else { return .tapping(taps: tapTimes.count) }
        let tb = now.timeIntervalSince(b)
        if tb < goldBuild { return .building(t: tb) }
        return .reveal(t: tb - goldBuild)
    }

    func buttonsAt(_ kind: GachaRevealKind) -> Double {
        reduced ? GTiming.Reduced.buttonsAt(kind) : GTiming.buttonsAt(kind)
    }

    /// 공개가 자리 잡았는가(버튼이 떴다) — [한 번 더] 는 이때부터만 받는다.
    func revealSettled(_ now: Date) -> Bool {
        guard case .reveal(let t) = phase(now), let r = result else { return false }
        return t >= buttonsAt(r.kind)
    }

    /// 루비가 나간(나가는 중인) 판의 결과를 사용자가 아직 못 봤다 — 왕복 중 · 공개 전 · 안 보이는 동안 공개가 자리 잡음.
    /// 호스트(맥 창)는 이 판이 있으면 다시 열 때 기계를 새로 세우지 않는다(새로 세우면 산 캡슐이 창에서 사라진다).
    func hasUnrevealedTurn(_ now: Date) -> Bool {
        if pullInFlight { return true }
        guard commitTime != nil, failTime == nil, let r = result else { return false }
        guard let b = burstTime else { return true }
        let settledAt = b.addingTimeInterval(goldBuild + buttonsAt(r.kind))
        if now < settledAt { return true }
        if let hs = hiddenSince { return settledAt > hs }
        return false
    }

    /// 덜컹 시각들(커밋 0 + 기다리는 동안 kickEvery 마다).
    func kickTimes(_ now: Date) -> [Double] {
        guard let commit = commitTime else { return [] }
        let tc = now.timeIntervalSince(commit)
        var end = tc
        if let ds = dropStart { end = min(end, ds.timeIntervalSince(commit)) }
        if let f = failTime { end = min(end, f.timeIntervalSince(commit)) }
        var out: [Double] = [0]
        var k = GTiming.minShake * 0.78
        while k < end - 0.02 { out.append(k); k += GTiming.kickEvery }
        return out
    }

    func beats(_ now: Date) -> GBeats {
        let ph = phase(now)
        var b = GBeats(phaseKey: ph.key, kicks: kickTimes(now).count)
        if let ds = dropStart { b.landed = now.timeIntervalSince(ds) >= drop.land }
        if case .reveal(let t) = ph, let r = result, let land = GTiming.shardLandAt(r, reduced: reduced) {
            b.shardLanded = t >= land
        }
        if autoTurnStart != nil { b.autoNotch = Int(knobAngle(now) / 45) }
        return b
    }

    // MARK: 손잡이 각도(표시)

    func autoTurnProgress(_ now: Date) -> Double? {
        guard let s = autoTurnStart else { return nil }
        return min(1, max(0, now.timeIntervalSince(s) / max(0.01, autoTurnDuration)))
    }

    func knobAngle(_ now: Date) -> Double {
        if commitTime != nil { return 360 }
        var a = angle
        if let p = autoTurnProgress(now) {
            // 손으로 돌리듯: 천천히 시작해 붙었다가 끝에서 살짝 늦춘다
            let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            a = autoTurnFrom + (360 - autoTurnFrom) * e
        } else if !dragging, let rt = releaseTime {
            let t = now.timeIntervalSince(rt)
            // 동작 줄이기: 튕기지 않고 미끄러져 돌아온다
            let k = (env?.reduceMotion ?? false) ? GMath.easeOutCubic(t / 0.35) : GMath.spring(t, zeta: 0.62, freq: 1.8)
            a = releaseAngle * (1 - k)
        }
        if let rf = refuseTime, !(env?.reduceMotion ?? false) {
            a += 9 * GMath.ring(now.timeIntervalSince(rf), freq: 5.5, decay: 5)
        }
        return a
    }

    func knobPop(_ now: Date) -> Double {
        guard let tt = tickTime, !(env?.reduceMotion ?? false) else { return 1 }
        let t = now.timeIntervalSince(tt)
        guard t < 0.2 else { return 1 }
        return 1 + 0.075 * sin(.pi * min(1, t / 0.17))
    }

    var dropPair: Int {
        var r = GRandom(seed)
        return Int(r.next() % UInt64(GPalette.capsulePairs.count))
    }

    // MARK: 잔잔한 움직임의 봉투(1 → 0 으로 잦아든다)

    /// 이 단계의 잔잔한 움직임 크기. 0 이면 정지 화면이다.
    func ambient(_ now: Date) -> Double {
        if reduced || (env?.reduceMotion ?? false) { return 0 }
        switch phase(now) {
        case .reveal(let t):
            guard let r = result else { return 0 }
            let end = GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace
            return 1 - GMath.smooth(end, end + GTiming.ambientFade, t)
        case .idle, .tapping:
            let s = now.timeIntervalSince(lastEvent)
            return 1 - GMath.smooth(GTiming.ambientGrace, GTiming.ambientGrace + GTiming.ambientFade, s)
        default:
            return 1
        }
    }

    // MARK: 언제 멎는가

    /// 지금 상태 그대로 두면 화면이 더는 안 바뀌기 시작하는 시각. nil = 계속 그려야 한다(기다림 · 떨어짐 …).
    func quietAt(_ now: Date) -> Date? {
        if dragging || autoTurnStart != nil || againAt != nil || pressing { return nil }
        let ph = phase(now)
        // 멎는 시각은 지금과 무관하다(마지막 움직임이 끝나는 때). 지금으로 시작하면 늘 '지금 + 여유' 라 영영 안 멎는다.
        var t = Date.distantPast
        func upTo(_ d: Date?) { if let d, d > t { t = d } }
        let reduce = env?.reduceMotion ?? false
        switch ph {
        case .idle:
            upTo(releaseTime?.addingTimeInterval(1.6))
            upTo(refuseTime?.addingTimeInterval(1.4))
            upTo(tickTime?.addingTimeInterval(0.25))
            upTo(returnTime?.addingTimeInterval(0.6))
            upTo(outgoingTime?.addingTimeInterval(0.4))
            if !reduce { upTo(lastEvent.addingTimeInterval(GTiming.ambientGrace + GTiming.ambientFade)) }
        case .tapping:
            if let last = tapTimes.last { upTo(last.addingTimeInterval(1.2)) }
            if let ds = dropStart { upTo(ds.addingTimeInterval(drop.total + 1.2)) }
            if !reduce && !reduced { upTo(lastEvent.addingTimeInterval(GTiming.ambientGrace + GTiming.ambientFade)) }
        case .reveal:
            guard let r = result, let b = burstTime else { return nil }
            let start = b.addingTimeInterval(goldBuild)
            if reduced || reduce {
                upTo(start.addingTimeInterval(GTiming.Reduced.oneShotEnd(r.kind)))
            } else {
                upTo(start.addingTimeInterval(GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace + GTiming.ambientFade))
            }
        case .shaking, .dropping, .building, .failed:
            return nil
        }
        return t.addingTimeInterval(0.05)
    }

    // MARK: 시간 전이

    /// 시계가 `now` 에 왔을 때 할 일을 한다(자동 회전 끝 → 커밋, 실패 → 처음으로, [한 번 더] → 자동 회전, 멎기).
    func advance(_ now: Date) {
        // 안 보이는 기계는 저절로 돌지 않는다 — 호스트가 isActive 를 내렸으면 커밋 전 예약을 거둔다(뷰의 onChange 보다
        // 이 깨우기가 먼저 올 수 있다). 맥 창은 닫아도 뷰가 안 사라져 `stop()` 이 안 불린다.
        if env?.isActive == false { cancelPendingTurn(now) }
        if let s = autoTurnStart, now >= s.addingTimeInterval(autoTurnDuration) {
            autoTurnStart = nil
            angle = 360
            commit(now)
        }
        if let a = againAt, now >= a {
            againAt = nil
            autoTurn(now)
        }
        if let f = failTime, now >= f.addingTimeInterval(GTiming.failHold) {
            resetPull(now)
        }
        let quiet = quietAt(now)
        let want = quiet.map { now < $0 } ?? true
        if framesWanted != want { framesWanted = want }
        reschedule(now)
    }

    /// 다음에 깨어날 시각.
    func nextWake(_ now: Date) -> Date? {
        var candidates: [Date] = []
        if let s = autoTurnStart { candidates.append(s.addingTimeInterval(autoTurnDuration)) }
        if let a = againAt { candidates.append(a) }
        if let f = failTime { candidates.append(f.addingTimeInterval(GTiming.failHold)) }
        if framesWanted {
            // 멎는 때를 알면 그때, 모르면(떨어짐 · 기다림 등 시간이 단계를 바꾸는 중) 0.5초마다 다시 본다 —
            // 안 그러면 떨어짐 → 톡톡처럼 시간만으로 넘어간 단계가 영영 멎지 않는다.
            candidates.append(quietAt(now) ?? now.addingTimeInterval(0.5))
        }
        return candidates.min()
    }

    private func reschedule(_ now: Date) {
        wakeTask?.cancel()
        wakeTask = nil
        guard autoSchedule, let wake = nextWake(now) else { return }
        let delay = max(0.001, wake.timeIntervalSince(now))
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.advance(self.clock())
        }
    }

    /// 무슨 일이 생겼다 — 다시 그리기 시작하고 다음 깨어날 때를 잡는다.
    func touched(_ now: Date) {
        lastEvent = now
        if !framesWanted { framesWanted = true }
        reschedule(now)
    }

    /// 뷰가 사라질 때. 돌고 있는 `pull` 은 끊지 않는다(서버 일은 호스트 몫이다) — 깨우기만 멈춘다.
    func stop() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    /// 안 보이게 됐다(맥 창 닫힘 · 최소화 · 완전히 가려짐 / 폰 덮개 · 앱이 뒤로 · 확률 시트). **커밋 전** 예약 — 손잡이의
    /// 자동 회전과 [한 번 더] — 을 거둔다: 안 보이는 동안 손잡이가 저절로 마저 돌아 루비를 쓰지 않게. 손잡이는 처음 자리로
    /// 미끄러진다. 이미 떠난 `pull` 은 그대로 둔다(서버 일은 호스트 몫 — 공개는 다시 보일 때 이어진다).
    func cancelPendingTurn(_ now: Date) {
        guard autoTurnStart != nil || againAt != nil else { return }
        if autoTurnStart != nil {
            let shown = knobAngle(now)
            autoTurnStart = nil
            if shown > 0.5 { releaseAngle = shown; releaseTime = now }
            angle = 0
            lastNotch = 0
        }
        againAt = nil
        touched(now)
    }

    // MARK: 리셋

    func resetPull(_ now: Date? = nil) {
        let now = now ?? clock()
        turn += 1
        commitTime = nil; result = nil; dropStart = nil; skipWhenReady = false
        tease = false; tapTimes = []; burstTime = nil; failTime = nil; reduced = false
        angle = 0; lastNotch = 0; releaseTime = nil; tickTime = nil; dragging = false
        autoTurnStart = nil; againAt = nil; arrivedAt = nil
        pointerAngle = nil
        touched(now)
    }

    // MARK: 호스트 값 · 박자

    /// 뷰가 그릴 때마다 넘기는 호스트 값. 관찰되지 않는 칸만 바꾼다(그리는 도중에 관찰 값을 바꾸지 않는다).
    func update(env newEnv: GachaMachineEnv) {
        let resumed = newEnv.isActive && !wasActive
        if !newEnv.isActive && wasActive { hiddenSince = clock() }
        if newEnv.isActive { hiddenSince = nil }
        wasActive = newEnv.isActive
        env = newEnv
        if resumed { resyncBase = beats(clock()) }
    }

    /// 박자가 바뀐 순간의 햅틱(덜컹 · 툭 · 짠 · 조각 · 자동 회전 톱니)과 결과 알림.
    func emitBeats(old: GBeats, new: GBeats, now: Date) {
        var old = old
        // 다시 보인 뒤 첫 변화: 멈추기 전 박자 대신 다시 보인 순간의 박자와 견준다(멈춘 동안 지나간 것은 안 낸다).
        if let base = resyncBase { resyncBase = nil; old = base }
        guard let env, env.isActive else { return }
        let h = env.haptics
        if new.kicks > old.kicks && new.kicks > 1 && !reduced { h.play(.rumble) }
        if new.landed && !old.landed { h.play(.land) }
        if new.phaseKey == GPhase.reveal(t: 0).key && old.phaseKey != new.phaseKey {
            h.play(isGold ? .goldReveal : .reveal)
            if let r = result {
                AccessibilityNotification.Announcement(GachaMachineText.announcement(r)).post()
            }
        }
        if new.shardLanded && !old.shardLanded { h.play(.shard) }
        if old.autoNotch >= 0, new.autoNotch > old.autoNotch {
            tickTime = now
            if new.autoNotch < 8 { h.play(.ratchet) }
        }
    }
}

// MARK: - 동작

extension GachaMachineDirector {
    func dragChanged(location: CGPoint, translation: CGSize) {
        guard let env else { return }
        let now = clock()
        guard commitTime == nil, autoTurnStart == nil, againAt == nil else { return }
        touchedHandle = true
        if !env.canPull {
            if !dragging { dragging = true; refuse(now) }
            return
        }
        if !dragging {
            let shown = max(0, knobAngle(now))
            dragging = true
            dragMoved = false
            angle = shown
            releaseTime = nil
            lastNotch = Int(shown / 45)
            pointerAngle = nil
            touched(now)
        }
        if hypot(translation.width, translation.height) > 3 { dragMoved = true }
        let c = GLayout.knobCenter
        let dx = location.x - c.x, dy = location.y - c.y
        guard hypot(dx, dy) > 9 else { return }
        let a = atan2(dy, dx) * 180 / .pi
        guard let pa = pointerAngle else { pointerAngle = a; return }
        var delta = a - pa
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        pointerAngle = a
        debugLog?.append(String(format: "a=%.0f d=%.1f angle=%.0f", a, delta, angle))
        guard dragMoved, delta > 0 else { return }   // 톱니: 앞으로만
        angle = min(360, angle + min(delta, 60))
        notchCheck(now)
        if angle >= 350 { angle = 360; commit(now) }
    }

    func dragEnded() {
        let now = clock()
        guard dragging else { return }
        dragging = false
        guard let env, env.canPull, commitTime == nil else { touched(now); return }
        if !dragMoved { autoTurn(now); return }
        if angle > 0.5 {
            releaseAngle = angle; releaseTime = now
            angle = 0; lastNotch = 0
        }
        touched(now)
    }

    /// 손잡이 끌기가 **취소됐다**(전화 · 시스템 알림 · 창이 내려감 — SwiftUI 는 취소에 `onEnded` 를 안 부른다).
    /// 놓은 것과 달리 클릭으로 치지 않는다(저절로 돌지 않는다 — 루비가 안 나간다). 손잡이는 처음 자리로 미끄러진다.
    func dragCancelled() {
        let now = clock()
        guard dragging else { return }
        dragging = false
        pointerAngle = nil
        if commitTime == nil, angle > 0.5 {
            releaseAngle = angle; releaseTime = now
            angle = 0; lastNotch = 0
        }
        touched(now)
    }

    func notchCheck(_ now: Date) {
        let n = Int(angle / 45)
        if n > lastNotch {
            lastNotch = n; tickTime = now
            if n < 8 { env?.haptics.play(.ratchet) }
        }
    }

    func refuse(_ now: Date) {
        refuseTime = now
        env?.haptics.play(.refuse)
        touched(now)
    }

    /// 손잡이 클릭(끌지 않음) · 보이스오버 동작 → 저절로 한 바퀴. 끝나는 순간(`advance`) 커밋한다.
    func autoTurn(_ now: Date? = nil) {
        let now = now ?? clock()
        guard commitTime == nil, autoTurnStart == nil, !pullInFlight else { return }
        guard let env, env.canPull else { refuse(now); return }
        let start = max(0, knobAngle(now))
        touchedHandle = true
        releaseTime = nil
        angle = start
        lastNotch = Int(start / 45)
        autoTurnFrom = start
        autoTurnDuration = max(0.15, GTiming.autoTurn * (360 - start) / 360)
        if env.reduceMotion { autoTurnDuration = min(autoTurnDuration, 0.45) }
        autoTurnStart = now
        touched(now)
    }

    /// 한 바퀴를 다 돌렸다 → `pull` 을 **한 번** 부른다.
    func commit(_ now: Date? = nil) {
        let now = now ?? clock()
        guard commitTime == nil, !pullInFlight else { return }
        guard let env, env.canPull else { refuse(now); angle = 0; return }
        commitTime = now
        reduced = env.reduceMotion
        seed = UInt64.random(in: 1...UInt64.max)
        angle = 360
        dragging = false
        autoTurnStart = nil
        result = nil; dropStart = nil; tapTimes = []; burstTime = nil; failTime = nil
        tease = false; skipWhenReady = false; arrivedAt = nil
        outgoing = nil
        returnTime = nil
        env.haptics.play(.commit)
        touched(now)
        turn += 1
        let myTurn = turn
        let pull = env.pull
        pullInFlight = true
        pullCount += 1
        pullTask = Task { @MainActor [weak self] in
            do {
                let r = try await pull()
                guard let self else { return }
                self.pullInFlight = false
                guard self.turn == myTurn, self.commitTime != nil else { return }
                self.arrive(r, self.clock())
            } catch {
                guard let self else { return }
                self.pullInFlight = false
                guard self.turn == myTurn, self.commitTime != nil else { return }
                let message = (error as? GachaRevealFailure)?.message ?? GachaMachineText.pullFailed
                self.fail(message, self.clock())
            }
        }
    }

    func arrive(_ r: GachaRevealOutcome, _ now: Date) {
        result = r
        arrivedAt = now
        let teaseChance = env?.teaseChance ?? 0
        tease = !reduced && r.kind == .gold && Double.random(in: 0..<1) < teaseChance
        guard let commit = commitTime else { return }
        let earliest = commit.addingTimeInterval(GTiming.minShake)
        dropStart = skipWhenReady ? now.addingTimeInterval(-drop.total) : max(now, earliest)
        if reduced, let ds = dropStart {
            // 톡톡 없이 떨어짐 → 겹쳐 바뀌는 공개
            burstTime = ds.addingTimeInterval(drop.total)
        }
        touched(now)
    }

    func fail(_ message: String, _ now: Date) {
        failTime = now
        failText = message
        env?.haptics.play(.refuse)
        touched(now)
    }

    /// 화면 아무 데나 누름: 자동 구간은 빨리 감기, 톡톡 구간은 톡.
    func press(_ now: Date? = nil) {
        let now = now ?? clock()
        switch phase(now) {
        case .shaking(_, let pending):
            if pending { skipWhenReady = true } else { dropStart = now.addingTimeInterval(-drop.total) }
            if reduced, let ds = dropStart, !pending { burstTime = ds.addingTimeInterval(drop.total) }
        case .dropping:
            dropStart = now.addingTimeInterval(-drop.total)
            if reduced { burstTime = now }
        case .tapping(let n):
            crackTap(n, now)
        case .building:
            burstTime = now.addingTimeInterval(-GTiming.goldBuild)
        case .reveal(let t):
            guard let r = result, let b = burstTime else { return }
            let target = buttonsAt(r.kind) + (r.kind == .duplicate && !reduced ? 0.15 : 0)
            if t < target - 0.05 { burstTime = b.addingTimeInterval(-(target - t)) }
        default:
            return
        }
        touched(now)
    }

    /// 누름이 끝났다(누르는 동안엔 멎지 않는다).
    func pressEnded() {
        pressing = false
        touched(clock())
    }

    func crackTap(_ n: Int, _ now: Date) {
        guard n < 3 else { return }
        if let last = tapTimes.last, now.timeIntervalSince(last) < 0.11 { return }
        tapTimes.append(now)
        let k = tapTimes.count
        env?.haptics.play(.tap(k))
        if k == 2 && tease { env?.haptics.play(.goldFlip) }
        if k >= 3 { burstTime = now }
    }

    func skipTaps(_ now: Date? = nil) {
        let now = now ?? clock()
        guard case .tapping = phase(now) else { return }
        burstTime = isGold ? now.addingTimeInterval(-goldBuild) : now
        touched(now)
    }

    /// [한 번 더]. 공개가 자리 잡은 뒤에만 받는다 — 0.42초 뒤 손잡이가 저절로 돈다(그때 `pull`).
    func again(_ now: Date? = nil) {
        let now = now ?? clock()
        guard revealSettled(now), !pullInFlight, againAt == nil else { return }
        guard let env, env.canPull, env.againEnabled else { refuse(now); return }
        outgoing = result
        outgoingTime = now
        resetPull(now)
        returnTime = now
        env.onAgain()
        againAt = now.addingTimeInterval(GTiming.againDelay)
        touched(now)
    }
}

// MARK: - 색(테마와 무관한 캡슐·금색)

enum GPalette {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }
    static let lav = hex(0xCFBAFE)
    static let lavDeep = hex(0x9979E6)
    static let lavInk = hex(0x6A4FC8)
    static let plum = hex(0x2D2150)
    static let gold = hex(0xFFD24A)
    static let goldDeep = hex(0xE5A200)
    static let goldLight = hex(0xFFF2C2)

    static let capsulePairs: [(Color, Color)] = [
        (hex(0xFF8FC0), hex(0x6FC4FF)), (hex(0x78E0BC), hex(0xFFB15A)), (hex(0xB79BFF), hex(0xFFD84F)),
        (hex(0x6FD0FF), hex(0xFF7B8F)), (hex(0xFFD45E), hex(0x9C7BFF)), (hex(0x8EE58E), hex(0xFF8FC0)),
        (hex(0xFFA36B), hex(0x62CFE8)),
    ]
}
