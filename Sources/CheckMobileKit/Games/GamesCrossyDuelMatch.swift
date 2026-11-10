#if os(iOS)
import CheckCore
import SceneKit
import SwiftUI

// 1:1 길건너 판 화면(폰 1.0.18). 맥 `CrossyDuelPanelMatch` 와 같은 규칙: 판 루프는 `store.tick()` 이 돌리고, 쓸기 = 그 방향 한 칸(`hop`) ·
// 탭 = 앞으로 한 칸(`forward`) — 혼자 하는 길건너와 같은 손짓(`CrossyGestureTracker`). 상대는 반투명 그림자(`opponentGhost` · 맥 0.3.82).
// 겹(결과 > 판정 기다림 > 부활 > 카운트다운)은 `CrossyDuelPhoneOverlay` 한 곳이 정한다.
struct GamesCrossyDuelMatchView: View {
    let store: GamesStore
    @State private var confirmingResign = false
    @State private var tracker = CrossyGestureTracker()
    @State private var gestureStart: (location: CGPoint, at: Date)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let duel = store.crossyDuel
        let phase = duel.phase
        let live = phase == .countdown || phase == .playing
        TimelineView(.animation(minimumInterval: 1.0 / Double(MiniGameFrameRate.baselineFPS), paused: !live)) { context in
            let snapshot = duel.raceSnapshot()
            VStack(spacing: MobileTheme.space3) {
                header(duel: duel, snapshot: snapshot)
                ZStack {
                    canvas(duel: duel, phase: phase)
                    overlay(duel: duel, phase: phase, snapshot: snapshot)
                }
                .aspectRatio(0.8, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .gesture(phase == .playing ? touch : nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(CrossyDuelPhoneText.touchLine))
                .accessibilityAction(named: Text("앞으로")) { duel.forward() }
                footer(duel: duel, phase: phase)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.space3)
            .onChange(of: context.date) { _, _ in duel.tick() }
        }
        .confirmationDialog(CrossyDuelPhoneText.resignWarning, isPresented: $confirmingResign, titleVisibility: .visible) {
            Button(CrossyDuelPhoneText.confirmResign, role: .destructive) { Task { await duel.resign() } }
            Button(CrossyDuelPhoneText.keepPlaying, role: .cancel) {}
        }
    }

    // MARK: 머리(점수 · 남은 시간 · 상대)

    private func header(duel: CrossyDuelStore, snapshot: CrossyDuelRaceSnapshot?) -> some View {
        let match = duel.match
        let name = match?.opponent.displayName ?? CrossyDuelPhoneText.opponentTitle
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CrossyDuelPhoneText.me).font(.caption).foregroundStyle(MobileTheme.label2)
                    Text("\(snapshot?.myScore ?? match?.myServerScore ?? 0)")
                        .font(.title2.weight(.heavy)).monospacedDigit()
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(CrossyDuelPhoneText.goalLine(snapshot?.goal ?? 100)).font(.caption).foregroundStyle(MobileTheme.label2)
                    if let remaining = snapshot?.remaining {
                        Text(CrossyDuelPhoneText.clock(remaining)).font(.headline).monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name).font(.caption).foregroundStyle(MobileTheme.label2).lineLimit(1)
                    Text("\(snapshot?.opponentScore ?? match?.opponentScore ?? 0)")
                        .font(.title2.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                }
            }
            if let snapshot {
                GamesCrossyDuelRaceBar(my: snapshot.myScore, opponent: snapshot.opponentScore, goal: snapshot.goal)
                HStack {
                    Text(CrossyDuelPhoneText.deathsLine(me: snapshot.myDeaths, opponent: snapshot.opponentDeaths))
                    Spacer()
                    if snapshot.opponentQuiet || duel.connectionTrouble {
                        Text(CrossyDuelPhoneText.opponentQuiet)
                    }
                }
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 판

    @ViewBuilder
    private func canvas(duel: CrossyDuelStore, phase: CrossyDuelPhase) -> some View {
        if phase == .countdown || phase == .playing || phase == .finished, let match = duel.match {
            GamesCrossyDuelSceneView(game: duel.duel?.game ?? CrossyGame(seed: UInt64(clamping: max(0, match.seed ?? 0)), rules: .duel),
                                     ghost: duel.opponentGhost, reduceMotion: reduceMotion)
        } else {
            ZStack {
                Color(red: 0.36, green: 0.62, blue: 0.33)
                VStack(spacing: 6) {
                    Text(CrossyDuelPhoneText.waitingTitle).font(.headline).foregroundStyle(.white)
                    if let deadline = duel.match?.readyDeadline {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(CrossyDuelPhoneText.waitingSubtitle(seconds: max(0, Int(deadline.timeIntervalSince(duel.clock()).rounded(.up)))))
                                .font(.footnote).foregroundStyle(.white.opacity(0.85)).monospacedDigit()
                        }
                    }
                    if duel.playingElsewhere {
                        Text(CrossyDuelPhoneText.otherDeviceSubtitle).font(.footnote).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
            }
        }
    }

    @ViewBuilder
    private func overlay(duel: CrossyDuelStore, phase: CrossyDuelPhase, snapshot: CrossyDuelRaceSnapshot?) -> some View {
        let match = duel.match
        switch CrossyDuelPhoneOverlay.resolve(phase: phase, isFinished: match?.isFinished ?? false, outcome: match?.outcome, snapshot: snapshot) {
        case .countdown(let digit)?, .respawn(let digit)?:
            Text(digit)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 6)
        case .waiting(let goal)?:
            Text(goal ? CrossyDuelPhoneText.goalWaiting : CrossyDuelPhoneText.timeWaiting)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
                .background(Capsule().fill(.black.opacity(0.45)))
        case .result?:
            if let match { GamesCrossyDuelResultCard(store: duel, match: match).padding(16) }
        case nil:
            EmptyView()
        }
    }

    // MARK: 아래(조작 안내 · 기권 · 로비로)

    @ViewBuilder
    private func footer(duel: CrossyDuelStore, phase: CrossyDuelPhase) -> some View {
        switch phase {
        case .finished:
            AingButton(CrossyDuelPhoneText.backToLobby, kind: .filled, size: .lg, fillsWidth: true) { duel.backToLobby() }
        case .playing, .countdown:
            HStack {
                Text(CrossyDuelPhoneText.touchLine)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                AingButton(CrossyDuelPhoneText.resign, kind: .gray, size: .sm) { confirmingResign = true }
                    .disabled(duel.isBusy || (duel.raceSnapshot()?.waitingForResult ?? false))
                    .fixedSize()
            }
        default:
            EmptyView()
        }
    }

    // MARK: 손짓 — 쓸기 = 그 방향 한 칸(떼기를 기다리지 않는다) · 짧은 탭 = 앞으로 한 칸

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if gestureStart == nil { gestureStart = (value.startLocation, Date()) }
                if let direction = tracker.drag(startLocation: value.startLocation, translation: value.translation) {
                    store.crossyDuel.hop(direction)
                }
            }
            .onEnded { value in
                let elapsed = gestureStart.map { Date().timeIntervalSince($0.at) } ?? 0
                if tracker.end(translation: value.translation, elapsed: elapsed) {
                    store.crossyDuel.forward()
                }
                gestureStart = nil
            }
    }
}

/// 경주 띠 — 두 사람이 목표(100점)까지 어디쯤인지(맥 `CrossyDuelRaceBand` 의 폰 꼴 · 한 줄 두 점).
struct GamesCrossyDuelRaceBar: View {
    let my: Int
    let opponent: Int
    let goal: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = { (score: Int) -> CGFloat in CGFloat(min(max(0, score), max(1, goal))) / CGFloat(max(1, goal)) }
            ZStack(alignment: .leading) {
                Capsule().fill(MobileTheme.fill).frame(height: 6)
                Circle().fill(MobileTheme.label2).frame(width: 12, height: 12)
                    .offset(x: max(0, fraction(opponent) * width - 6))
                Circle().fill(MobileTheme.accent).frame(width: 14, height: 14)
                    .offset(x: max(0, fraction(my) * width - 7))
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// 결과 카드(맥 `CrossyDuelResultCard` 와 같은 내용 · 폰 색).
struct GamesCrossyDuelResultCard: View {
    let store: CrossyDuelStore
    let match: CrossyDuelMatchState

    var body: some View {
        let delta = CrossyDuelPhoneText.rubyDelta(match)
        let tint: Color = match.outcome == .win ? MobileTheme.working : (match.outcome == .loss ? MobileTheme.danger : MobileTheme.label2)
        let reason = CrossyDuelNoticeText.endReason(match.endReason, outcome: match.outcome,
                                                    meReady: match.meReady, opponentReady: match.opponentReady)
        VStack(spacing: 8) {
            Text(CrossyDuelPhoneText.outcomeTitle(match.outcome))
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
            if !reason.isEmpty {
                Text(reason).font(.footnote).foregroundStyle(MobileTheme.label2).multilineTextAlignment(.center)
            }
            if match.endReason != .noShow {
                Text(CrossyDuelPhoneText.finalScoreLine(me: match.finalMyScore ?? store.duel?.game.score ?? match.myServerScore,
                                                        opponent: match.finalOpponentScore ?? match.opponentScore))
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                RubyIcon(size: 16)
                Text(CrossyDuelPhoneText.rubyLine(delta))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? MobileTheme.working : (delta < 0 ? MobileTheme.danger : MobileTheme.label2))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// 3D 판(혼자 하는 길건너의 `CrossyScene` 과 같은 씬) + 상대 반투명 그림자(`ghostTarget`).
struct GamesCrossyDuelSceneView: View {
    let game: CrossyGame
    let ghost: CrossyDuelGhost?
    let reduceMotion: Bool
    @StateObject private var scene = CrossyScene(aingLoader: GamesCrossyAing.load)

    var body: some View {
        GamesCrossyDuelSCNView(scene: scene, game: game, ghost: ghost, reduceMotion: reduceMotion)
    }
}

private struct GamesCrossyDuelSCNView: UIViewRepresentable {
    let scene: CrossyScene
    let game: CrossyGame
    let ghost: CrossyDuelGhost?
    let reduceMotion: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue),
        ])
        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = CrossyPalette.shared.color(CrossyScene.backgroundHex)
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        view.isPlaying = false
        view.preferredFramesPerSecond = MiniGameFrameRate.baselineFPS
        view.isUserInteractionEnabled = false
        view.prepare(scene.prewarmShapes, completionHandler: nil)
        scene.ghostTarget = ghost
        scene.apply(game, reduceMotion: reduceMotion)
        return view
    }

    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.scene = nil
    }

    func updateUIView(_ view: SCNView, context: Context) {
        scene.ghostTarget = ghost
        scene.apply(game, reduceMotion: reduceMotion)
    }
}
#endif
