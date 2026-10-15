import SwiftUI

// MARK: - 공개 뷰

/// 캡슐 뽑기 기계(0.3.54). 순수 SwiftUI — 맥 뽑기 창 · 폰 전체 화면이 같은 뷰를 띄운다.
///
/// 기계는 **호스트가 넘긴 값만 보여 준다** — 잔액 · 조각을 스스로 바꾸지 않는다.
/// - `balance`/`cost`: 루비 잔액과 한 번 값. 모자라면 손잡이가 안 돌고 안내가 뜬다(`pull` 을 부르지 않는다).
/// - `shards`: "조각 N" 칩(공개 중엔 결과의 `shardCountBefore` → `shardCount` 로 올라간다).
/// - `portrait`: 캐릭터 id → 초상.
/// - `art`: 기계 그림(배포본은 `.bundled` — 다섯 장 다 있어야 한다, 빠진 칸은 벡터).
/// - `isActive`: 보이는가. 창이 가려졌다 · 내려갔다 · 닫혔다(맥) / 앱이 뒤로 갔다 · 덮개가 내려갔다(폰) → `false`.
///   `false` 면 매 프레임 그리기를 멈춘다. 잔잔한 움직임도 손대지 않으면 몇 초 뒤 멎는다(그 뒤로 CPU 0).
/// - `blockedReason`: 호스트가 막은 이유(업데이트 필요 · 서버에 뽑기 없음 …). 있으면 손잡이가 안 돌고 이 줄이 뜬다.
/// - `againEnabled`: [한 번 더] 를 받을까.
/// - `pull`: 한 바퀴를 다 돌린 순간 **한 번** 부른다(돌고 있는 동안엔 다시 부르지 않는다). 던지면 한 줄
///   (`GachaRevealFailure.message`, 아니면 `GachaText.pullFailed`)을 2.4초 띄우고 처음으로 돌아간다 — 공개는 없다.
/// - `onAgain`: [한 번 더] 를 누른 순간(곧 손잡이가 저절로 돌아 `pull` 을 다시 부른다).
/// - `onClose`: [닫기].
package struct GachaMachineView: View {
    private let input: Input
    @State private var director: GachaMachineDirector
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var frameProbe: ((Date) -> Void)?

    struct Input {
        var balance: Int
        var cost: Int
        var shards: Int
        var ruby: Image
        var portrait: (String) -> Image
        var art: GachaMachineArt
        var teaseChance: Double
        var haptics: any GachaMachineHaptics
        var isActive: Bool
        var blockedReason: String?
        var againEnabled: Bool
        var pull: @MainActor () async throws -> GachaRevealOutcome
        var onAgain: () -> Void
        var onClose: () -> Void
    }

    package init(
        balance: Int,
        cost: Int = 50,
        shards: Int = 0,
        rubyIcon: Image,
        portrait: @escaping (String) -> Image,
        art: GachaMachineArt,
        goldTeaseChance: Double = 0.3,
        haptics: any GachaMachineHaptics = GachaMachineNoHaptics(),
        isActive: Bool = true,
        blockedReason: String? = nil,
        againEnabled: Bool = true,
        pull: @escaping @MainActor () async throws -> GachaRevealOutcome,
        onAgain: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        input = Input(balance: balance, cost: cost, shards: shards, ruby: rubyIcon, portrait: portrait, art: art,
                      teaseChance: goldTeaseChance, haptics: haptics, isActive: isActive, blockedReason: blockedReason,
                      againEnabled: againEnabled, pull: pull, onAgain: onAgain, onClose: onClose)
        _director = State(initialValue: GachaMachineDirector())
    }

    /// 데모 · 측정 · 시험: 바깥에서 만든 감독을 쓴다(같은 모듈 안에서만).
    func driven(by director: GachaMachineDirector) -> GachaMachineView {
        var copy = self
        copy._director = State(initialValue: director)
        return copy
    }

    /// 측정: 무대가 실제로 그려진 시각(같은 모듈 안에서만).
    func frameProbe(_ probe: @escaping (Date) -> Void) -> GachaMachineView {
        var copy = self
        copy.frameProbe = probe
        return copy
    }

    private func makeEnv() -> GachaMachineEnv {
        GachaMachineEnv(balance: input.balance, cost: input.cost, shards: input.shards, ruby: input.ruby,
                        portrait: input.portrait, art: input.art, teaseChance: input.teaseChance, haptics: input.haptics,
                        pull: input.pull, onAgain: input.onAgain, onClose: input.onClose,
                        blockedReason: input.blockedReason, againEnabled: input.againEnabled,
                        isActive: input.isActive, reduceMotion: systemReduceMotion, onFrame: frameProbe)
    }

    package var body: some View {
        let env = makeEnv()
        let d = director
        let _ = d.update(env: env)
        let theme = GachaMachineTheme.of(colorScheme)
        // 캡슐 그림은 처음 한 번 굽는다(같은 그림 묶음이면 창을 다시 열어도 다시 굽지 않는다).
        let sprites = GachaCapsuleSprites.shared(for: input.art)
        let running = env.isActive && d.framesWanted
        GachaMachineScaler {
            TimelineView(.animation(minimumInterval: nil, paused: !running)) { ctx in
                // 멈춘 동안 다시 그려지면(호스트 값이 바뀜) 멈춘 시각이 아니라 지금으로 그린다 — 멎은 화면이라 같은 그림이다.
                let now = running ? ctx.date : d.clock()
                let _ = env.onFrame?(now)
                GachaMachineStage(d: d, env: env, theme: theme, sprites: sprites, now: now)
            }
        }
        .onAppear {
            GachaMachineWarmup.runOnce(art: input.art)
            d.touched(d.clock())
        }
        .onDisappear { d.stop() }
        .onChange(of: input.isActive) { _, active in
            if active { d.touched(d.clock()) }
        }
        .onChange(of: systemReduceMotion) { _, _ in d.touched(d.clock()) }
        .onChange(of: input.balance) { _, _ in d.touched(d.clock()) }
        .onChange(of: input.blockedReason) { _, _ in d.touched(d.clock()) }
    }
}

/// 설계 무대(380×460)를 받은 자리에 비율 그대로 맞춰 가운데 둔다. 바탕 · 무대 조명 · 황금 어둠 · 섬광은 무대 밖까지
/// 번지게 그려(폰 세로 화면 · 다른 비율의 창에서 위아래가 비지 않게) 이 뷰의 테두리로 자른다.
struct GachaMachineScaler<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / GLayout.size.width, geo.size.height / GLayout.size.height)
            content
                .frame(width: GLayout.size.width, height: GLayout.size.height)
                .scaleEffect(s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
    }
}

// MARK: - 미리 데우기
//
// 공개 순간에 처음 쓰이는 것(한글 둥근 글꼴 대체 · 흐림 필터 · 더하기 합성 · 글자 가림)을 창이 뜰 때 화면 밖에서 한 번 그려 둔다.
// 결과 초상은 결과가 도착한 순간부터 무대에 (보이지 않게) 얹어 둔다 — `GachaMachineStage.prewarmLayer`.

@MainActor
enum GachaMachineWarmup {
    private static var done = false
    /// 마지막 데우기에 걸린 시간(초) — 측정용.
    private(set) static var lastSeconds: Double = 0

    static func runOnce(art: GachaMachineArt) {
        guard !done else { return }
        done = true
        let t0 = Date()
        let content = ZStack {
            GLightBurst(t: 0.3, gold: false, center: CGPoint(x: 60, y: 60), dark: false, spin: 0)
            GLightBurst(t: 0.3, gold: true, center: CGPoint(x: 60, y: 60), dark: true, spin: 0)
                .blendMode(.plusLighter)
            VStack(spacing: 2) {
                Text("새 캐릭터! 이미 있는 친구예요 건너뛰기 닫기").font(.system(size: 14, weight: .bold, design: .rounded))
                Text("여우 다람쥐 강아지 유령 해파리 로봇 조각 +1").font(.system(size: 24, weight: .heavy, design: .rounded))
                GShimmerTitle(text: GachaText.goldHeadline, size: 30, t: 0.5)
                Text("아주 드문 친구를 만났어요 두근두근 손잡이를 돌려서 뽑기").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("한 번 더 · 루비가 모자라요 0123456789").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("톡톡 눌러서 열기 조금 더! 마지막 한 번! -50 +1").font(.system(size: 13, weight: .heavy, design: .rounded))
                GShardGem(size: 30, glow: 1, outline: .black)
            }
        }
        .frame(width: 120, height: 120)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        _ = renderer.cgImage
        lastSeconds = Date().timeIntervalSince(t0)
    }
}

// MARK: - 무대(시간 → 그림)

struct GachaMachineStage: View {
    let d: GachaMachineDirector
    let env: GachaMachineEnv
    let theme: GachaMachineTheme
    var sprites: GachaCapsuleSprites?
    let now: Date

    static let space = "gachaMachineStage"
    /// 무대 밖으로 번지는 폭(설계 좌표). 세로 폰(393×852)이면 위아래로 ≈ 180 이 필요하다 — 넉넉히.
    static let bleed: CGFloat = 900
    private static var bleedSize: CGSize {
        CGSize(width: GLayout.size.width + 2 * bleed, height: GLayout.size.height + 2 * bleed)
    }
    /// 무대 좌표 → 번진 판 안의 단위 좌표.
    static func bleedUnit(_ p: CGPoint) -> UnitPoint {
        UnitPoint(x: (p.x + bleed) / bleedSize.width, y: (p.y + bleed) / bleedSize.height)
    }
    /// 무대 밖까지 덮는 판(가운데 = 무대 가운데).
    private func fullBleed<V: View>(_ v: V) -> some View {
        v.frame(width: Self.bleedSize.width, height: Self.bleedSize.height)
            .position(x: GLayout.size.width / 2, y: GLayout.size.height / 2)
            .allowsHitTesting(false)
    }

    var body: some View {
        let ph = d.phase(now)
        ZStack(alignment: .topLeading) {
            background
            machine(ph)
            spotlight(ph)
            goldDim(ph)
            prewarmLayer(ph)
            capsuleLayer(ph)
            revealLayer(ph)
            outgoingLayer
            textLayer(ph)
            chips(ph)
            buttons(ph)
            flash(ph)
        }
        .frame(width: GLayout.size.width, height: GLayout.size.height)
        .coordinateSpace(name: Self.space)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !d.pressing { d.pressing = true; d.press() }
                }
                .onEnded { _ in d.pressEnded() }
        )
        .onChange(of: d.beats(now)) { old, new in d.emitBeats(old: old, new: new, now: now) }
    }

    // MARK: 공통 값

    private var t: Double { now.timeIntervalSinceReferenceDate }
    /// 이 판이 동작 줄이기인가(커밋 순간의 설정) · 지금 설정이 동작 줄이기인가.
    private var still: Bool { d.reduced || env.reduceMotion }

    private func recede(_ ph: GPhase) -> Double {
        switch ph {
        case .dropping(let td):
            if d.reduced { return GMath.smooth(d.drop.land, d.drop.total, td) }
            return GMath.smooth(d.drop.jump0 - 0.06, d.drop.jump1 - 0.1, td)
        case .tapping, .building, .reveal: return 1
        case .idle:
            if let rt = d.returnTime { return 1 - GMath.smooth(0, 0.5, now.timeIntervalSince(rt)) }
            return 0
        default: return 0
        }
    }

    private var goldShown: Bool {
        guard d.isGold else { return false }
        return !d.tease || d.tapTimes.count >= 2 || d.burstTime != nil
    }

    private func revealT(_ ph: GPhase) -> Double? {
        if case .reveal(let t) = ph { return t }
        return nil
    }

    // MARK: 배경

    private var background: some View {
        fullBleed(ZStack {
            // 무대 위 끝 = bgTop, 아래 끝 = bgBottom, 그 밖은 끝 색 그대로
            LinearGradient(colors: [theme.bgTop, theme.bgBottom],
                           startPoint: Self.bleedUnit(CGPoint(x: GLayout.midX, y: 0)),
                           endPoint: Self.bleedUnit(CGPoint(x: GLayout.midX, y: GLayout.size.height)))
            RadialGradient(colors: [theme.bgGlow, .clear], center: Self.bleedUnit(CGPoint(x: GLayout.midX, y: 0.28 * GLayout.size.height)),
                           startRadius: 10, endRadius: 260)
        })
    }

    // MARK: 기계

    private func machine(_ ph: GPhase) -> some View {
        let r = recede(ph)
        var ox = 0.0, oy = 0.0, squash = 0.0
        let kicks = d.kickTimes(now)
        if !still, let commit = d.commitTime {
            let tc = now.timeIntervalSince(commit)
            for (i, kt) in kicks.enumerated() {
                let tau = tc - kt
                guard tau >= 0, tau < 1.2 else { continue }
                let amp = i == 0 ? 1.0 : 0.5
                oy += amp * 5 * GMath.ringCos(tau, freq: 6, decay: 10)
                ox += amp * 3 * GMath.ring(tau, freq: 13, decay: 8)
                squash += amp * 0.03 * GMath.ringCos(tau, freq: 6, decay: 10)
            }
        }
        if !still, case .failed(let tf) = ph { ox += 6 * GMath.ring(tf, freq: 7, decay: 6) }
        let ambient = d.ambient(now)
        let knobA = d.knobAngle(now)
        let canPull = env.canPull
        let idle = ph == .idle
        // 처음 보는 사람에게: 손잡이가 가끔 살짝 '돌려 봐' 하고 까딱인다(잔잔한 움직임이 잦아들면 멈춘다)
        let nudge = (idle && !d.touchedHandle && canPull) ? ambient * 10 * pow(max(0, sin(2 * .pi * t / 2.8)), 14) : 0
        let lit: Int = d.commitTime != nil ? 8 : min(8, Int((knobA + 0.5) / 45))
        let litAlpha: Double = d.commitTime.map { 1 - GMath.smooth(0.35, 1.0, now.timeIntervalSince($0)) } ?? 1
        let hintAlpha = idle && canPull ? (1 - GMath.smooth(4, 40, knobA)) * (1 - r) * (d.dragging ? 0.4 : 1) : 0
        let scale = still ? 1.0 : 1 - 0.06 * r

        return ZStack(alignment: .topLeading) {
            // 바닥 그림자
            Ellipse().fill(Color.black.opacity(theme.floorShadow))
                .frame(width: 236, height: 18).blur(radius: 7)
                .position(x: GLayout.midX, y: 404)

            GDomeView(now: domeNow(r), kicks: kicks, commitTime: d.commitTime, art: env.art, sprites: sprites,
                      ambient: ambient, still: still, theme: theme)
                .position(GLayout.domeCenter)

            capView
                .position(x: GLayout.capRect.midX, y: GLayout.capRect.midY)

            GMachineBody(art: env.art)
                .position(x: GLayout.bodyOrigin.x + GLayout.bodySize.width / 2,
                          y: GLayout.bodyOrigin.y + GLayout.bodySize.height / 2)

            GChuteFlap(art: env.art, open: flapOpen(ph))

            chuteGlow(ph)

            notchRing(lit: lit, alpha: litAlpha)
                .position(GLayout.knobCenter)

            GHintArc(now: now, radius: GLayout.notchR + 11, opacity: hintAlpha, flow: ambient)
                .frame(width: 150, height: 150)
                .position(GLayout.knobCenter)

            GKnob(art: env.art)
                .rotationEffect(.degrees(knobA + nudge))
                .scaleEffect(d.knobPop(now))
                .shadow(color: GPalette.hex(0x4B3592, 0.28), radius: 3, y: 2.5)
                .saturation(canPull ? 1 : 0.35)
                .opacity(canPull ? 1 : 0.8)
                .position(GLayout.knobCenter)

            // 손잡이 잡는 자리(보이지 않음)
            Circle().fill(Color.white.opacity(0.001))
                .frame(width: 112, height: 112)
                .position(GLayout.knobCenter)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { v in d.dragChanged(location: v.location, translation: v.translation) }
                        .onEnded { _ in d.dragEnded() }
                )
                .allowsHitTesting(idle && d.autoTurnStart == nil && d.againAt == nil)
                .accessibilityElement()
                .accessibilityLabel(GachaMachineText.handleLabel())
                .accessibilityHint(GachaMachineText.handleHint(cost: env.cost))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { d.autoTurn() }
        }
        .frame(width: GLayout.size.width, height: GLayout.size.height)
        .scaleEffect(CGSize(width: scale + squash * 0.4, height: scale - squash), anchor: UnitPoint(x: 0.5, y: 0.88))
        .offset(x: ox, y: oy + (still ? 0 : 6 * r))
        .opacity(1 - 0.76 * r)
        .blur(radius: 3.5 * r)
    }

    /// 기계가 뒤로 완전히 물러나면(흐릿) 돔 속 들썩임을 멈춘다 — 안 보이는 움직임에 매 프레임 그리지 않게.
    private func domeNow(_ r: Double) -> Date {
        if r >= 0.999, let ds = d.dropStart { return ds.addingTimeInterval(max(0, d.drop.jump1 - 0.1)) }
        return now
    }

    @ViewBuilder private var capView: some View {
        if let cap = env.art.cap {
            cap.resizable().interpolation(.high)
                .frame(width: GLayout.capRect.width, height: GLayout.capRect.height)
        } else {
            ZStack {
                Capsule().fill(LinearGradient(colors: [GPalette.hex(0xE3D6FF), GPalette.hex(0xBCA3F6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 20).offset(y: 9)
                Circle().fill(LinearGradient(colors: [GPalette.hex(0xE8DDFF), GPalette.hex(0xB79CF5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22).offset(y: -8)
            }
            .frame(width: GLayout.capRect.width, height: GLayout.capRect.height)
        }
    }

    private func notchRing(lit: Int, alpha: Double) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = (-90 + 45 * Double(i + 1)) * .pi / 180
                let on = i < lit
                Circle()
                    .fill(on ? Color.white : Color.white.opacity(0.42))
                    .frame(width: on ? 7 : 5.5, height: on ? 7 : 5.5)
                    .shadow(color: on ? GPalette.hex(0x8E6BFF, 0.9 * alpha) : .clear, radius: on ? 4 : 0)
                    .opacity(on ? max(0.42, alpha) : 1)
                    .offset(x: cos(a) * GLayout.notchR, y: sin(a) * GLayout.notchR)
            }
        }
        .frame(width: 120, height: 120)
        .allowsHitTesting(false)
    }

    private func flapOpen(_ ph: GPhase) -> Double {
        guard case .dropping(let td) = ph else { return 0 }
        return Self.flapOpen(td: td, drop: d.drop, reduced: d.reduced)
    }

    /// 배출구 덮개(0 닫힘 … 1 활짝, 음수 = 안쪽으로 살짝 넘어감): 캡슐이 나오기 직전에 젖혀져 지나가는 동안 열려 있고,
    /// 지나간 뒤 탁 닫히며 살짝 흔들린다(동작 줄이기: 흔들림 없이 닫힘). 떨어지는 단계 밖에서는 늘 0.
    static func flapOpen(td: Double, drop T: GDropTimes, reduced: Bool) -> Double {
        let opened = GMath.easeOutCubic(GMath.ramp(T.emerge0 - 0.05, T.emerge0 + 0.07, td))
        let closeStart = T.emerge1 - 0.02
        guard td >= closeStart else { return opened }
        let tau = td - closeStart
        if reduced { return 1 - GMath.smooth(0, 0.25, tau) }
        if tau < 0.12 { return 1 - GMath.easeInCubic(tau / 0.12) }
        return -0.16 * GMath.ring(tau - 0.12, freq: 4, decay: 9)
    }

    /// 황금: 캡슐이 나오기 전부터 배출구가 금빛으로 샌다.
    @ViewBuilder private func chuteGlow(_ ph: GPhase) -> some View {
        if case .dropping(let td) = ph, d.isGold, !d.tease, td < d.drop.emerge1 + 0.3 {
            let a = GMath.smooth(0, 0.3, td) * (1 - GMath.smooth(d.drop.emerge1 - 0.05, d.drop.emerge1 + 0.3, td))
            let flicker = still ? 1 : 0.78 + 0.22 * sin(2 * .pi * 6 * td)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(GPalette.gold.opacity(0.55 * a * flicker))
                    .frame(width: GLayout.chuteRect.width - 6, height: GLayout.chuteRect.height - 6)
                    .blur(radius: 6)
                    .blendMode(.plusLighter)
                Circle()
                    .fill(RadialGradient(colors: [GPalette.goldLight.opacity(0.9 * a * flicker), GPalette.gold.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 150, height: 150)
                    .blendMode(.plusLighter)
            }
            .position(x: GLayout.chuteRect.midX, y: GLayout.chuteRect.midY + 6)
            .allowsHitTesting(false)
        }
    }

    // MARK: 무대 조명

    /// 일반 뽑기의 무대: 가장자리가 가라앉아 빛이 보이게 한다.
    @ViewBuilder private func spotlight(_ ph: GPhase) -> some View {
        let r = recede(ph)
        let burstBoost = revealT(ph).map { GMath.easeOutCubic($0 / 0.3) } ?? 0
        let a = min(1, 0.8 * r + 0.2 * burstBoost)
        if a > 0.01 {
            fullBleed(RadialGradient(stops: theme.spotlight, center: Self.bleedUnit(GLayout.stageCenter), startRadius: 0, endRadius: 400))
                .opacity(a)
        }
    }

    private func dimAmount(_ ph: GPhase) -> Double {
        if d.isGold {
            switch ph {
            case .dropping(let td): return d.tease ? 0 : 0.42 * GMath.smooth(0, 0.5, td)
            case .tapping:
                if d.tease {
                    guard d.tapTimes.count >= 2 else { return 0 }
                    return 0.45 * GMath.smooth(0, 0.3, now.timeIntervalSince(d.tapTimes[1]))
                }
                return 0.45
            case .building(let tb): return GMath.lerp(0.45, 0.84, GMath.smooth(0, 0.6, tb))
            case .reveal(let rt): return d.reduced ? GMath.lerp(0.42, 0.84, GMath.smooth(0, 0.35, rt)) : 0.84
            default: break
            }
        }
        if ph == .idle, d.outgoing?.kind == .gold, let rt = d.returnTime {
            return 0.84 * (1 - GMath.smooth(0, 0.45, now.timeIntervalSince(rt)))
        }
        return 0
    }

    @ViewBuilder private func goldDim(_ ph: GPhase) -> some View {
        let a = dimAmount(ph)
        if a > 0.005 {
            // 가운데는 덜, 가장자리는 더 — 회색 장막 대신 깊은 자줏빛 비네트
            let focus: UnitPoint = {
                if case .dropping = ph { return Self.bleedUnit(CGPoint(x: GLayout.midX, y: 0.72 * GLayout.size.height)) }
                return Self.bleedUnit(GLayout.stageCenter)
            }()
            fullBleed(ZStack {
                RadialGradient(colors: [GPalette.hex(0x2A1460, min(1, a * 0.72)), GPalette.hex(0x140A2E, min(1, a * 1.12))],
                               center: focus, startRadius: 20, endRadius: 360)
                RadialGradient(colors: [GPalette.hex(0x7A5212, 0.5 * a), .clear], center: focus,
                               startRadius: 10, endRadius: 260)
            })
        }
    }

    // MARK: 미리 그려 두기(보이지 않게)

    /// 결과가 도착하면(터지기 ≥ 1.6초 전) 공개에 처음 나올 것을 무대에 거의 투명하게 얹는다 — 초상 그림을 풀어 올리고
    /// 흐림 · 더하기 합성 · 글자 가림을 이 창에서 한 번 그려, 터지는 순간의 첫 그리기가 프레임을 밀지 않게 한다.
    /// 초상은 공개 직전까지 계속(값싼 그림 한 장), 무거운 빛 효과는 도착 뒤 잠깐만 그린다.
    /// 측정용 스위치(전 · 후 비교). 앱에서는 늘 켜져 있다.
    static var prewarmEnabled = true

    @ViewBuilder private func prewarmLayer(_ ph: GPhase) -> some View {
        switch ph {
        case .shaking, .dropping, .tapping, .building:
            if Self.prewarmEnabled, let r = d.result {
                let gold = r.kind == .gold
                let size: CGFloat = gold ? 172 : 150
                let effects = d.arrivedAt.map { now.timeIntervalSince($0) < 0.25 } ?? false
                ZStack(alignment: .topLeading) {
                    env.portrait(r.characterID)
                        .resizable().interpolation(.high)
                        .frame(width: size, height: size)
                        .shadow(color: effects ? (gold ? GPalette.gold.opacity(0.5) : GPalette.hex(0x5B3FB8, 0.25)) : .clear,
                                radius: effects ? (gold ? 18 : 10) : 0, y: effects && !gold ? 6 : 0)
                        .position(GLayout.stageCenter)
                    if effects {
                        GLightBurst(t: 0.25, gold: gold, center: GLayout.stageCenter, dark: gold || theme.raysOnDark, spin: 0)
                            .frame(width: GLayout.size.width, height: GLayout.size.height)
                            .blendMode(gold ? .plusLighter : .normal)
                        revealTexts(r, 3.0)
                        if r.shardsGained > 0 {
                            GShardGem(size: 40, glow: 1, outline: theme.shardOutline).position(GLayout.stageCenter)
                        }
                    }
                }
                .frame(width: GLayout.size.width, height: GLayout.size.height)
                .opacity(0.004)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        default:
            EmptyView()
        }
    }

    // MARK: 캡슐

    struct Pose {
        var c: CGPoint
        var d: CGFloat
        var sx: Double = 1
        var sy: Double = 1
        var rot: Double = 0
        var alpha: Double = 1
        var bright: Double = 0
    }

    private func capsulePose(_ ph: GPhase) -> Pose? {
        guard let ds = d.dropStart, now >= ds else { return nil }
        switch ph { case .dropping, .tapping, .building: break; default: return nil }
        let td = now.timeIntervalSince(ds)
        let T = d.drop
        var p = Pose(c: GLayout.tray, d: GLayout.capsuleSmall)
        if d.reduced {
            // 동작 줄이기: 배출구에서 미끄러져 나와 쟁반에 앉는다(튀거나 돌지 않는다)
            let e = GMath.easeOutCubic(GMath.ramp(T.emerge0, T.emerge1, td))
            p.c = GMath.lerp(GLayout.chuteInside, GLayout.tray, e)
            p.d = GLayout.capsuleSmall * GMath.lerp(0.62, 1, e)
            p.bright = GMath.lerp(-0.45, 0, e)
            p.alpha = GMath.ramp(0, 0.3, e)
            return p
        }
        if td < T.jump0 {
            let e = GMath.ramp(T.emerge0, T.emerge1, td)
            let start = GLayout.chuteInside
            p.c = CGPoint(x: GMath.lerp(start.x, GLayout.tray.x, e),
                          y: GMath.lerp(start.y, GLayout.tray.y, GMath.easeInCubic(e)) - 12 * sin(.pi * e))
            p.d = GLayout.capsuleSmall * GMath.lerp(0.62, 1, GMath.easeOutCubic(e))
            p.bright = GMath.lerp(-0.45, 0, e)
            p.alpha = GMath.ramp(0, 0.2, e)
            p.rot = GMath.lerp(-50, 0, GMath.easeOutCubic(e))
            let tau = td - T.land
            if tau > 0 {
                let s = 0.22 * GMath.ringCos(tau, freq: 4.5, decay: 11)
                p.sx += s; p.sy -= s
                p.c.y -= 5 * abs(GMath.ring(tau, freq: 2.6, decay: 7))
            }
            // 뛰기 직전 웅크림
            let tc = td - (T.jump0 - 0.08)
            if tc > 0 { let s = 0.14 * sin(.pi * min(1, tc / 0.08)); p.sx += s * 0.6; p.sy -= s }
        } else {
            let q = GMath.ramp(T.jump0, T.jump1, td)
            let e = 0.5 * (GMath.easeInOutCubic(q) + GMath.easeOutCubic(q))
            let ctrl = CGPoint(x: 300, y: 95)
            p.c = GMath.bezier(GLayout.tray, ctrl, GLayout.stageCenter, e)
            p.d = GLayout.capsuleSmall + (GLayout.capsuleBig - GLayout.capsuleSmall) * GMath.smooth(0, 1, q)
            p.rot = -360 * e
            // 공중에서 살짝 늘어남
            let air = sin(.pi * q)
            p.sy += 0.08 * air; p.sx -= 0.05 * air
            let tau = td - T.jump1
            if tau > 0 {
                let s = 0.16 * GMath.ringCos(tau, freq: 3.2, decay: 8)
                p.sx += s; p.sy -= s
                // 둥실(잔잔한 움직임 — 잦아들면 제자리)
                let ramp = GMath.smooth(0.2, 0.8, tau) * d.ambient(now)
                p.c.y += 3.5 * sin(2 * .pi * 0.55 * tau) * ramp
                p.rot += 2.5 * sin(2 * .pi * 0.4 * tau) * ramp
            }
        }
        if let last = d.tapTimes.last {
            let tau = now.timeIntervalSince(last)
            let k = d.tapTimes.count
            let amp = [0.75, 0.95, 1.15][min(k, 3) - 1]
            let s = 0.17 * amp * GMath.ringCos(tau, freq: 3.6, decay: 9)
            p.sx += s; p.sy -= s
            p.c.x += 7 * amp * GMath.ring(tau, freq: 9, decay: 9)
            p.rot += 7 * amp * GMath.ring(tau, freq: 6, decay: 8)
        }
        if case .building(let tb) = ph {
            let k = tb / GTiming.goldBuild
            p.c.x += (1.2 + 4 * k) * sin(2 * .pi * 23 * tb)
            p.c.y += (0.8 + 2 * k) * sin(2 * .pi * 19 * tb + 1)
            p.d *= 1 + 0.12 * GMath.easeInCubic(k)
            p.bright = 0.22 * k
        }
        return p
    }

    @ViewBuilder private func capsuleLayer(_ ph: GPhase) -> some View {
        if let p = capsulePose(ph) {
            let pair = d.dropPair
            let cracks = GCracks.make(seed: d.seed)
            let gold = goldShown
            let taps = d.tapTimes.count
            let lastTau = d.tapTimes.last.map { now.timeIntervalSince($0) } ?? 9
            let tapFlash = exp(-6 * lastTau)
            let buildK: Double = { if case .building(let tb) = ph { return tb / GTiming.goldBuild }; return 0 }()
            // 금빛이 은은하게 숨 쉰다(잔잔한 움직임 — 잦아들면 가운데 값)
            let goldPulse = 0.5 + 0.5 * sin(2 * .pi * 1.6 * t) * d.ambient(now)
            let halo: Double = {
                if gold {
                    let base = 0.55 + 0.2 * goldPulse + 0.12 * Double(taps) + 0.4 * buildK
                    return min(1.4, base) * p.alpha
                }
                return min(1, 0.22 * Double(taps) + 0.35 * tapFlash * (taps > 0 ? 1 : 0))
            }()
            let beams = Double(taps) * 0.55 + 0.3 * tapFlash * (taps > 0 ? 1 : 0) + 1.2 * buildK
            let crackGlow = Double(taps) * 0.45 + 0.4 * tapFlash + 1.0 * buildK
            let flipT: Double? = (d.tease && d.tapTimes.count >= 2) ? now.timeIntervalSince(d.tapTimes[1]) : nil
            let goldMix: Double = gold ? (flipT.map { GMath.smooth(0, 0.22, $0) } ?? 1) : 0
            let recedeNow = recede(ph)

            ZStack {
                // 바닥 그림자(무대 위에서)
                Ellipse().fill(Color.black.opacity((theme.dark ? 0.32 : 0.16) * recedeNow))
                    .frame(width: p.d * 0.75, height: p.d * 0.13)
                    .blur(radius: 5)
                    .position(x: p.c.x, y: GLayout.stageCenter.y + GLayout.capsuleBig * 0.62)

                if halo > 0.001 || beams > 0.001 {
                    GLeakLight(cracks: cracks, tapTimes: d.tapTimes, now: now, intensity: beams, halo: halo,
                               gold: gold, capsuleD: p.d)
                        .frame(width: p.d * 3.4, height: p.d * 3.4)
                        .rotationEffect(.degrees(p.rot))
                        .position(p.c)
                        .blendMode(gold ? .plusLighter : .normal)
                }

                ZStack {
                    GHeroBall(d: p.d, pair: pair, gold: false, art: env.art, sprites: sprites)
                        .opacity(1 - goldMix)
                    if goldMix > 0 {
                        GHeroBall(d: p.d, pair: pair, gold: true, art: env.art, sprites: sprites)
                            .opacity(goldMix)
                    }
                    if gold {
                        Circle().fill(RadialGradient(colors: [GPalette.goldLight.opacity(0.35 * goldPulse), .clear],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: p.d * 0.5))
                            .blendMode(.plusLighter)
                            .frame(width: p.d, height: p.d)
                    }
                    if taps > 0 {
                        GCrackOverlay(cracks: cracks, tapTimes: d.tapTimes, now: now, glow: crackGlow, gold: gold)
                            .frame(width: p.d, height: p.d)
                        // 톡 칠 때마다 안쪽이 환해진다
                        Circle().fill(RadialGradient(colors: [Color.white.opacity(0.55 * tapFlash + 0.3 * buildK), .clear],
                                                     center: .center, startRadius: 0, endRadius: p.d * 0.55))
                            .frame(width: p.d, height: p.d)
                            .blendMode(.plusLighter)
                    }
                }
                .brightness(p.bright)
                .scaleEffect(x: p.sx, y: p.sy)
                .rotationEffect(.degrees(p.rot))
                .position(p.c)
                .opacity(p.alpha)

                // 반전: 황금으로 바뀌는 순간 빛 고리
                if let ft = flipT, ft < 0.7 {
                    Circle()
                        .stroke(GPalette.goldLight.opacity(0.9 * (1 - ft / 0.7)), lineWidth: 10 * (1 - ft / 0.7) + 1)
                        .frame(width: p.d * (1 + 1.6 * GMath.easeOutCubic(ft / 0.7)), height: p.d * (1 + 1.6 * GMath.easeOutCubic(ft / 0.7)))
                        .blur(radius: 3)
                        .blendMode(.plusLighter)
                        .position(p.c)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: 공개(터짐 · 캐릭터 · 조각)

    @ViewBuilder private func revealLayer(_ ph: GPhase) -> some View {
        if let rt = revealT(ph), let r = d.result {
            let gold = r.kind == .gold
            ZStack {
                if d.reduced {
                    reducedReveal(r, rt)
                } else {
                    GLightBurst(t: rt, gold: gold, center: GLayout.stageCenter, dark: gold || theme.raysOnDark,
                                spin: burstSpin(r, rt))
                        .frame(width: GLayout.size.width, height: GLayout.size.height)
                        .blendMode(gold ? .plusLighter : .normal)
                    capsuleHalves(r, rt)
                    character(r, rt)
                    if r.kind == .duplicate { shardFlight(rt) }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 빛줄기 회전 각: 처음엔 돌다가 잔잔한 움직임이 잦아드는 동안 같이 멈춘다(각속도 × 봉투의 적분 — 튀지 않는다).
    private func burstSpin(_ r: GachaRevealOutcome, _ rt: Double) -> Double {
        let speed = r.kind == .gold ? 0.10 : 0.16
        let end = GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace
        return speed * GMath.fadeIntegral(end, end + GTiming.ambientFade, rt)
    }

    @ViewBuilder private func capsuleHalves(_ r: GachaRevealOutcome, _ rt: Double) -> some View {
        if rt < 0.8 {
            let gold = r.kind == .gold
            let center = GLayout.stageCenter
            let pair = d.dropPair
            let capD = GLayout.capsuleBig * (gold ? 1.12 : 1)
            let g = 900.0
            let k = gold ? 1.15 : 1.0
            let fade = 1 - GMath.smooth(0.18, gold ? 0.7 : 0.55, rt)
            GHeroHalf(upper: true, d: capD, pair: pair, gold: gold, art: env.art, sprites: sprites)
                .rotationEffect(.degrees(-230 * rt * k))
                .scaleEffect(1 + 0.15 * rt)
                .position(x: center.x - 150 * rt * k, y: center.y - 320 * rt * k + 0.5 * g * rt * rt)
                .opacity(fade)
            GHeroHalf(upper: false, d: capD, pair: pair, gold: gold, art: env.art, sprites: sprites)
                .rotationEffect(.degrees(170 * rt * k))
                .scaleEffect(1 + 0.15 * rt)
                .position(x: center.x + 125 * rt * k, y: center.y + 30 * rt * k + 0.5 * g * rt * rt)
                .opacity(fade)
        }
    }

    /// 동작 줄이기의 공개: 쟁반의 캡슐이 사라지며 캐릭터가 겹쳐 나타난다(튀기 · 빛줄기 · 고리 · 조각 비행 없음).
    @ViewBuilder private func reducedReveal(_ r: GachaRevealOutcome, _ rt: Double) -> some View {
        let gold = r.kind == .gold
        let fade = GTiming.Reduced.fade
        GLightBurst(t: rt, gold: gold, center: GLayout.stageCenter, dark: gold || theme.raysOnDark, spin: 0, reduced: true)
            .frame(width: GLayout.size.width, height: GLayout.size.height)
            .blendMode(gold ? .plusLighter : .normal)
        if rt < fade {
            GHeroBall(d: GLayout.capsuleSmall, pair: d.dropPair, gold: gold, art: env.art, sprites: sprites)
                .opacity(1 - GMath.ramp(0, fade, rt))
                .position(GLayout.tray)
        }
        let cond = r.kind == .duplicate ? GMath.smooth(GTiming.Reduced.dupSwap, GTiming.Reduced.dupSwap + fade, rt) : 0
        let size: CGFloat = gold ? 172 : 150
        env.portrait(r.characterID)
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .saturation(1 - cond)
            .opacity(GMath.ramp(0, fade, rt) * GMath.lerp(1, 0.25, cond))
            .shadow(color: gold ? GPalette.gold.opacity(0.5) : GPalette.hex(0x5B3FB8, 0.25), radius: gold ? 18 : 10, y: gold ? 0 : 6)
            .position(GLayout.stageCenter)
    }

    @ViewBuilder private func character(_ r: GachaRevealOutcome, _ rt: Double) -> some View {
        let gold = r.kind == .gold
        let delay = gold ? 0.08 : 0.02
        let s0 = gold ? 0.3 : 0.25
        let sp = GMath.spring(rt - delay, zeta: gold ? 0.42 : 0.40, freq: gold ? 1.6 : 2.3)
        let rise = GMath.spring(rt - delay, zeta: 0.5, freq: gold ? 1.5 : 2.0)
        let scale = s0 + (1 - s0) * sp
        // 둥실(잔잔한 움직임 — 잦아들면 제자리)
        let bob = -4 * sin(2 * .pi * 0.45 * (rt - 0.8)) * GMath.smooth(0.7, 1.3, rt) * d.ambient(now)
        let cond = r.kind == .duplicate ? GMath.smooth(GTiming.dupCondense0, GTiming.dupCondense1, rt) : 0
        let size: CGFloat = gold ? 172 : 150
        env.portrait(r.characterID)
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .saturation(1 - cond)
            .brightness(0.5 * sin(.pi * min(1, cond * 1.15)))
            .opacity(GMath.ramp(delay, delay + 0.08, rt) * GMath.lerp(1, 0.2, cond))
            .scaleEffect(scale * (1 - 0.12 * cond))
            .shadow(color: gold ? GPalette.gold.opacity(0.5) : GPalette.hex(0x5B3FB8, 0.25), radius: gold ? 18 : 10, y: gold ? 0 : 6)
            .position(x: GLayout.stageCenter.x, y: GLayout.stageCenter.y + 26 * (1 - rise) + bob)
    }

    /// 중복: 캐릭터의 빛이 모여 결정이 되고, 칩으로 날아간다. 밝은 바탕에서도 읽히게 진한 보라 꼬리 · 테두리를 둔다.
    @ViewBuilder private func shardFlight(_ rt: Double) -> some View {
        let c0 = GTiming.dupCondense0, c1 = GTiming.dupCondense1
        let fly1 = GTiming.dupFly1
        if rt > c0 && rt < fly1 {
            let gather = GMath.smooth(c0, c1, rt)
            let born = GMath.easeOutBack(GMath.ramp(c0 + 0.6 * (c1 - c0), c1 + 0.05, rt))
            let q = GMath.ramp(c1, fly1, rt)
            let ctrl = CGPoint(x: 40, y: 190)
            let path = { (x: Double) in GMath.bezier(GLayout.stageCenter, ctrl, GLayout.shardChip, GMath.easeInOutCubic(x)) }
            let size = GMath.lerp(46, 18, GMath.easeInCubic(q)) * born
            let orbR = GMath.lerp(120, 34, GMath.easeInOutCubic(gather)) * GMath.lerp(1, 0.5, q)
            let orbA = (0.25 + 0.7 * gather) * (1 - 0.4 * q)
            ZStack {
                // 빛 꼬리(진한 보라 → 옅게)
                if q > 0 {
                    ForEach(1..<7, id: \.self) { i in
                        let qq = max(0, q - Double(i) * 0.04)
                        let k = 1 - Double(i) / 7
                        Circle().fill(theme.shardTrail.opacity(0.55 * k))
                            .frame(width: size * (1.0 - Double(i) * 0.1), height: size * (1.0 - Double(i) * 0.1))
                            .blur(radius: 2.5)
                            .position(path(qq))
                    }
                }
                Circle().fill(RadialGradient(colors: [Color.white.opacity(orbA), GPalette.hex(0xD6C4FF, 0.75 * orbA),
                                                      theme.shardOrbEdge.opacity(0.45 * orbA), theme.shardOrbEdge.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: orbR))
                    .frame(width: orbR * 2, height: orbR * 2)
                    .position(path(q))
                if born > 0.01 {
                    GShardGem(size: size, glow: 1, outline: theme.shardOutline)
                        .rotationEffect(.degrees(-20 + 380 * GMath.easeInOutCubic(q)))
                        .position(path(q))
                }
            }
        }
    }

    @ViewBuilder private var outgoingLayer: some View {
        if let o = d.outgoing, let ot = d.outgoingTime {
            let tt = now.timeIntervalSince(ot)
            if tt < 0.35 {
                let size: CGFloat = o.kind == .gold ? 172 : 150
                env.portrait(o.characterID)
                    .resizable().interpolation(.high)
                    .frame(width: size, height: size)
                    .opacity(o.kind == .duplicate ? 0.2 * max(0, 1 - tt / 0.3) : max(0, 1 - tt / 0.3))
                    .scaleEffect(still ? 1 : 1 - 0.25 * tt / 0.35)
                    .position(GLayout.stageCenter)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 글자

    @ViewBuilder private func textLayer(_ ph: GPhase) -> some View {
        ZStack {
            bottomHint(ph)
            if case .tapping(let n) = ph { tapHint(n, ph) }
            if case .reveal(let rt) = ph, let r = d.result {
                revealTexts(r, rt)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(GachaMachineText.announcement(r))
            }
        }
        .frame(width: GLayout.size.width, height: GLayout.size.height)
    }

    private func warnPill<Content: View>(_ content: Content, rf: Double) -> some View {
        content
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.warn)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(theme.pillFill))
            .frame(maxWidth: 344)
            .offset(x: still ? 0 : 6 * GMath.ring(rf, freq: 7, decay: 7))
            .scaleEffect(still ? 1 : 1 + 0.06 * exp(-8 * rf))
    }

    @ViewBuilder private func bottomHint(_ ph: GPhase) -> some View {
        let r = recede(ph)
        switch ph {
        case .idle:
            let rf = d.refuseTime.map { now.timeIntervalSince($0) } ?? 9
            if let reason = env.blockedReason {
                warnPill(Text(reason), rf: rf)
                    .opacity(1 - r)
                    .position(x: GLayout.midX, y: GLayout.hintY)
                    .allowsHitTesting(false)
            } else if env.canPay {
                HStack(spacing: 4) {
                    Text(GachaMachineText.idleHint())
                    env.ruby.resizable().interpolation(.high).frame(width: 15, height: 15)
                    Text("\(env.cost)")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.ink)
                .opacity((1 - r) * (d.dragging ? 0.5 : 1))
                .position(x: GLayout.midX, y: GLayout.hintY)
                .allowsHitTesting(false)
            } else {
                warnPill(HStack(spacing: 4) {
                    Text(GachaMachineText.shortHead)
                    env.ruby.resizable().interpolation(.high).frame(width: 15, height: 15)
                    Text(GachaMachineText.shortTail(cost: env.cost))
                }, rf: rf)
                .opacity(1 - r)
                .position(x: GLayout.midX, y: GLayout.hintY)
                .allowsHitTesting(false)
            }
        case .shaking(let tc, let pending):
            if pending && tc > 0.9 {
                let dots = Int((tc * 3).truncatingRemainder(dividingBy: 4))
                Text(GachaMachineText.waiting + String(repeating: "·", count: still ? 3 : dots))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .scaleEffect(still ? 1 : 1 + 0.05 * sin(2 * .pi * 1.6 * tc))
                    .opacity(GMath.smooth(0.9, 1.2, tc))
                    .frame(width: 120, alignment: .leading)
                    .offset(x: 28)
                    .position(x: GLayout.midX, y: GLayout.hintY)
                    .allowsHitTesting(false)
            }
        case .failed(let tf):
            warnPill(Text(d.failText), rf: 9)
                .opacity(GMath.smooth(0, 0.15, tf) * (1 - GMath.smooth(GTiming.failHold - 0.3, GTiming.failHold, tf)))
                .position(x: GLayout.midX, y: GLayout.hintY)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func tapHint(_ n: Int, _ ph: GPhase) -> some View {
        let arrive = d.dropStart.map { now.timeIntervalSince($0) - d.drop.jump1 } ?? 0
        let a = GMath.smooth(0.1, 0.4, arrive)
        let dark = goldShown || dimAmount(ph) > 0.3 || theme.dark
        let ink = (goldShown || dimAmount(ph) > 0.3) ? Color.white : theme.ink
        VStack(spacing: 7) {
            Text(n == 0 ? GachaMachineText.tapFirst : (n == 1 ? GachaMachineText.tapSecond : GachaMachineText.tapLast))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .scaleEffect(1 + 0.04 * sin(2 * .pi * 1.2 * t) * d.ambient(now))
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(i < n ? ink : ink.opacity(0.28)).frame(width: 7, height: 7)
                }
            }
        }
        .opacity(a)
        .position(x: GLayout.midX, y: 300)
        .allowsHitTesting(false)
        .accessibilityHidden(true)

        // 건너뛰기(보이스오버는 이걸로 캡슐을 연다)
        Button { d.skipTaps() } label: {
            Text(GachaMachineText.skip)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill((dark ? Color.white : GPalette.lavDeep).opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GachaMachineText.openCapsule)
        .opacity(a)
        .position(x: 336, y: GLayout.hintY)
    }

    /// 공개 글자. 정상 연출과 동작 줄이기가 **같은 글자**를 쓴다(시각 · 움직임만 다르다).
    @ViewBuilder func revealTexts(_ r: GachaRevealOutcome, _ rt: Double) -> some View {
        let reduced = d.reduced
        let badgeAt = reduced ? GTiming.Reduced.badgeAt : GTiming.badgeAt
        let nameAt = reduced ? GTiming.Reduced.nameAt : GTiming.nameAt
        let badgeT = rt - badgeAt
        let badgeS = reduced ? 1 : 0.5 + 0.5 * GMath.spring(badgeT, zeta: 0.45, freq: 2.6)
        let badgeA = GMath.ramp(0, reduced ? 0.25 : 0.1, badgeT)
        let nameA = GMath.ramp(nameAt, nameAt + (reduced ? 0.3 : 0.2), rt)
        let nameY = reduced ? 0 : 8 * (1 - GMath.easeOutCubic((rt - nameAt) / 0.3))
        switch r.kind {
        case .new:
            badge(GachaMachineText.badge(r) ?? "", filled: true)
                .scaleEffect(badgeS).opacity(badgeA)
                .position(x: GLayout.midX, y: 92)
            Text(GachaMachineText.title(r))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.title)
                .opacity(nameA).offset(y: nameY)
                .position(x: GLayout.midX, y: 300)
        case .duplicate:
            badge(GachaMachineText.badge(r) ?? "", filled: false)
                .scaleEffect(badgeS).opacity(badgeA)
                .position(x: GLayout.midX, y: 92)
            let swap = reduced ? GTiming.Reduced.dupSwap : GTiming.dupCondense1
            let fadeLen = reduced ? GTiming.Reduced.fade : 0.16
            let out = GMath.ramp(swap - (reduced ? 0 : 0.15), swap + (reduced ? fadeLen : 0), rt)
            let inn = GMath.ramp(swap - (reduced ? 0 : 0.04), swap + fadeLen, rt)
            ZStack {
                Text(r.name)
                    .opacity(1 - out)
                    .offset(y: reduced ? 0 : -12 * GMath.easeInCubic(out))
                HStack(spacing: 6) {
                    Text(GachaMachineText.shardLine(r))
                    Text(GachaMachineText.shardGain(r)).foregroundStyle(theme.accent)
                }
                .opacity(inn)
                .offset(y: reduced ? 0 : 12 * (1 - GMath.easeOutCubic(inn)))
                .scaleEffect(reduced ? 1 : 0.92 + 0.08 * GMath.spring(rt - swap, zeta: 0.45, freq: 2.6))
            }
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(theme.title)
            .opacity(nameA).offset(y: nameY)
            .position(x: GLayout.midX, y: 300)
        case .gold:
            let titleAt = reduced ? GTiming.Reduced.nameAt : GTiming.goldTitleAt
            let subAt = reduced ? GTiming.Reduced.nameAt + 0.3 : GTiming.goldSubAt
            let tt = rt - titleAt
            GShimmerTitle(text: GachaMachineText.title(r), size: 30, t: max(0, rt - titleAt - 0.3), passes: reduced ? 0 : 2)
                .scaleEffect(reduced ? 1 : 0.6 + 0.4 * GMath.spring(tt, zeta: 0.45, freq: 2.0))
                .opacity(GMath.ramp(0, reduced ? 0.3 : 0.15, tt))
                .position(x: GLayout.midX, y: 306)
            Text(GachaMachineText.goldSubtitle(r))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(GPalette.goldLight.opacity(0.9))
                .opacity(GMath.ramp(subAt, subAt + 0.3, rt))
                .position(x: GLayout.midX, y: 340)
        }
    }

    private func badge(_ s: String, filled: Bool) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Color.white : theme.badgeText)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                Capsule().fill(filled
                    ? AnyShapeStyle(LinearGradient(colors: [GPalette.hex(0xB197FF), GPalette.hex(0x8C6CF2)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(theme.badgeFill))
            )
            .overlay(Capsule().stroke(filled ? Color.white.opacity(0.5) : theme.chipStroke.opacity(theme.dark ? 1 : 0), lineWidth: 1))
            .shadow(color: GPalette.hex(0x7B5CE6, filled ? 0.45 : 0.18), radius: 8, y: 2)
    }

    // MARK: 칩

    @ViewBuilder private func chips(_ ph: GPhase) -> some View {
        let shardInfo: (count: Int, landT: Double?) = {
            if let r = d.result, let land = GTiming.shardLandAt(r, reduced: d.reduced) {
                if case .reveal(let rt) = ph, rt >= land { return (r.shardCount, rt - land) }
                return (r.shardCountBefore, nil)
            }
            if let r = d.result { return (r.shardCount, nil) }
            return (env.shards, nil)
        }()
        let lt = shardInfo.landT
        let pulse = (lt.map { 1 + 0.32 * GMath.ringCos($0, freq: 2.6, decay: 7) } ?? 1)
        let glow = lt.map { exp(-2.2 * $0) } ?? 0
        GShardChip(count: shardInfo.count, pulse: still ? 1 : pulse, glow: glow, theme: theme)
            .animation(still ? nil : .snappy(duration: 0.25), value: shardInfo.count)
            .position(GLayout.shardChip)
            .allowsHitTesting(false)
        if let lt, lt < 1.6 {
            // 들어온 순간 칩에서 퍼지는 고리(동작 줄이기: 없음)
            if !still, lt < 0.6 {
                let p = lt / 0.6
                Capsule()
                    .stroke(theme.shardTrail.opacity(0.85 * pow(1 - p, 1.4)), lineWidth: 3 * (1 - p) + 1)
                    .frame(width: 84 + 50 * GMath.easeOutCubic(p), height: 28 + 30 * GMath.easeOutCubic(p))
                    .position(GLayout.shardChip)
                    .allowsHitTesting(false)
            }
            Text(GachaMachineText.chipGain(d.result ?? GachaRevealOutcome(characterID: "", name: "", kind: .duplicate)))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.accentStrong)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(theme.chipFill))
                .overlay(Capsule().stroke(theme.chipStroke, lineWidth: 1))
                .offset(y: 30 + (still ? 0 : 8 * GMath.easeOutCubic(lt / 0.8)))
                .opacity(GMath.ramp(0, 0.1, lt) * (1 - GMath.smooth(1.0, 1.6, lt)))
                .position(GLayout.shardChip)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        let ct = d.commitTime.map { now.timeIntervalSince($0) }
        GRubyChip(balance: env.balance, ruby: env.ruby,
                  pulse: still ? 1 : (ct.map { 1 + 0.08 * GMath.ringCos($0, freq: 3, decay: 9) } ?? 1), theme: theme)
            .animation(still ? nil : .snappy(duration: 0.3), value: env.balance)
            .position(GLayout.rubyChip)
            .allowsHitTesting(false)
        if let ct, ct < 1.1, d.failTime == nil {
            Text("-\(env.cost)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.spend)
                .offset(y: 22 + (still ? 6 : 14 * GMath.easeOutCubic(ct / 0.9)))
                .opacity(GMath.ramp(0, 0.08, ct) * (1 - GMath.smooth(0.6, 1.1, ct)))
                .position(GLayout.rubyChip)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: 버튼

    @ViewBuilder private func buttons(_ ph: GPhase) -> some View {
        if case .reveal(let rt) = ph, let r = d.result {
            let b = d.buttonsAt(r.kind)
            let a = GMath.ramp(b, b + (d.reduced ? 0.3 : 0.22), rt)
            if a > 0 {
                let dark = r.kind == .gold
                let canAgain = env.canPull && env.againEnabled && !d.pullInFlight
                HStack(spacing: 10) {
                    Button { d.again() } label: {
                        HStack(spacing: 5) {
                            if env.blockedReason == nil && env.canPay {
                                Text(GachaMachineText.again)
                                env.ruby.resizable().interpolation(.high).frame(width: 16, height: 16)
                                Text("\(env.cost)")
                            } else if env.blockedReason == nil {
                                Text(GachaMachineText.againShort)
                            } else {
                                Text(GachaMachineText.againBlocked)
                            }
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 170, height: 46)
                        .background(Capsule().fill(LinearGradient(colors: [GPalette.hex(0xB197FF), GPalette.hex(0x8B6BF0)],
                                                                  startPoint: .top, endPoint: .bottom)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: GPalette.hex(0x6A4FC8, 0.35), radius: 10, y: 4)
                        .opacity(canAgain ? 1 : 0.55)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(GachaMachinePressStyle(still: still))
                    .disabled(!canAgain)
                    .accessibilityLabel(GachaMachineText.againLabel(cost: env.cost))
                    .accessibilityHint(canAgain ? "" : (env.blockedReason ?? GachaMachineText.againShort))

                    Button { env.onClose() } label: {
                        Text(GachaMachineText.close)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(dark ? Color.white : theme.closeText)
                            .frame(width: 104, height: 46)
                            .background(Capsule().fill(dark ? Color.white.opacity(0.14) : theme.closeFill))
                            .overlay(Capsule().stroke(dark ? Color.white.opacity(0.25) : theme.closeStroke, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GachaMachinePressStyle(still: still))
                }
                .opacity(a)
                .offset(y: d.reduced ? 0 : 16 * (1 - GMath.spring(rt - b, zeta: 0.6, freq: 2.4)))
                .position(x: GLayout.midX, y: 404)
                .allowsHitTesting(a > 0.5)
            }
        }
    }

    // MARK: 섬광

    @ViewBuilder private func flash(_ ph: GPhase) -> some View {
        // 일반: 흰 섬광(밝은 바탕) · 옅은 라벤더(어두운 바탕). 황금: 더하기 합성의 따뜻한 빛 — 어두운 무대를 회색으로 씻지 않는다.
        // 동작 줄이기: 섬광 없음.
        let gold = d.isGold
        let a: Double = {
            if d.reduced { return 0 }
            switch ph {
            case .reveal(let rt):
                return gold ? 0.95 * exp(-4.5 * rt) : theme.flashPeak * exp(-7.5 * rt)
            case .building(let tb):
                return gold ? 0.22 * GMath.smooth(GTiming.goldBuild - 0.3, GTiming.goldBuild, tb) : 0
            case .tapping:
                if d.tease, d.tapTimes.count >= 2 { return 0.45 * exp(-9 * now.timeIntervalSince(d.tapTimes[1])) }
                return 0
            default: return 0
            }
        }()
        if a > 0.005 {
            if gold {
                fullBleed(RadialGradient(colors: [GPalette.hex(0xFFE7A6), GPalette.hex(0xFFC94A, 0.85), GPalette.hex(0xB07A10, 0.5)],
                                         center: Self.bleedUnit(GLayout.stageCenter), startRadius: 0, endRadius: 380))
                    .opacity(a)
                    .blendMode(.plusLighter)
            } else {
                fullBleed(theme.flash)
                    .opacity(a)
            }
        }
    }
}

struct GachaMachinePressStyle: ButtonStyle {
    var still = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !still ? 0.94 : 1)
            .opacity(configuration.isPressed && still ? 0.8 : 1)
            .animation(still ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
