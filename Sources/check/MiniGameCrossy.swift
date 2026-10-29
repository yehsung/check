import AppKit
import SceneKit
import SwiftUI
import CheckCore

// MARK: - 길건너 아잉이 (v0.3.67) — 잎 뷰
//
// 미니게임 넷째. 규칙은 `CrossyGame`(코어 순수 값)에, 3D 판은 `CrossyScene`(**코어** —
// Sources/CheckCore/CrossyScene.swift, 폰 1.0.15 에서 옮겼다), 아잉이 모델 다리는 `CrossyMacAing`
// (MiniGameCrossyScene.swift)에, 이 파일에는 **틀**만 있다 — 프레임 루프 · 입력 · 점수 글자 · 시작/결과 카드.
// 허브(미니게임 창)는 `MiniGameHost` 와 `MiniGameInput` 만 건네고 이 뷰는 그 둘 말고는 아무것도 읽지 않는다
// (플래피 · 타이밍 바 · 테트리스와 **같은 계약** — MiniGame.swift 머리 주석).
//
// ── 겹 ───────────────────────────────────────────────────────────────────────────────────
// 맨 아래가 SceneKit(`CrossySceneView` — SCNView 한 장), 그 위가 SwiftUI 점수 글자, 맨 위가 공용 카드
// (`MiniGameOverlayCard`). 점수를 3D 로 그리지 않는 이유는 테트리스가 글자를 Canvas 밖에 둔 것과 같다 —
// 글자는 SwiftUI 가 제일 잘 그리고 `.monospacedDigit()` 같은 규약도 그대로 산다. 대신 이 판은 `ImageRenderer` 로
// 통째로 못 찍는다(SCNView 는 빈 칸으로 나온다) — 3D 증거는 오프스크린 `SCNRenderer` 로 따로 찍는다(V0367CrossyTests).
//
// ── 프레임 루프 ──────────────────────────────────────────────────────────────────────────
// 다른 게임과 같은 `TimelineView(.animation(paused:))` 하나다 — 진행 중(running · 죽음 연출)일 때만 돌고,
// 시작 전 · 결과 · 허브의 정지 뒤엔 멈춘다(유휴 0%). 틱마다 판 값이 바뀌면 `CrossySceneView.updateNSView` 가 그 값을
// 노드에 옮기고, SCNView 는 `rendersContinuously = false` 라 **바뀐 프레임만** 그린다. 창이 가려지면(occlusion)
// 노드 갱신 자체를 건너뛴다 — 판이 돌아도 GPU 는 쉰다.
//
// ⚠️ 여기에 SwiftUI 반복 애니메이션(`repeatForever`)을 넣지 마라(플래피 v0.2.48 의 교훈 — 창을 닫아도 컴포지터가 돈다).

struct CrossyGameView: View {
    let host: MiniGameHost
    let input: MiniGameInput

    @State private var game: CrossyGame
    @State private var lastTick: Date?
    /// 3D 판(노드 풀 포함). 뷰가 사는 동안 하나다 — 새 판은 같은 씬에서 줄만 갈아 끼운다.
    /// `@StateObject` 라 **처음 한 번만** 만든다(`CrossyScene` 머리 주석 — `@State` 면 다시 지을 때마다 모델을 다시 읽는다).
    /// `.mac()` 이 맥의 아잉이 모델 다리를 끼운다(`CrossyMacAing`) — 로더는 코어에서 **필수 인자**다.
    @StateObject private var scene = CrossyScene.mac()

    init(host: MiniGameHost, input: MiniGameInput, initialGame: CrossyGame? = nil) {
        self.host = host
        self.input = input
        // 시드는 시각에서 — 판마다 다른 길. 시험은 initialGame 으로 고정한다.
        let seed = UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        _game = State(initialValue: initialGame ?? CrossyGame(seed: seed))
    }

    var body: some View {
        // 프레임 상한은 **화면 주사율에서 온다**(`MiniGameFrameRate` — 리터럴 1/60 금지, 소스 계약이 막는다).
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz),
                                paused: !game.isPlaying || host.isPaused)) { context in
            canvas
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, _ in act { $0.action() } }
        // 뛰기는 **누른 순서 그대로** 엔진에 넣는다 — 한 갱신에 둘 이상 눌렸어도 접지 않는다(`MiniGameInput.hops(since:)`).
        // 엔진이 한 칸만 줄 세우므로 셋째부터는 엔진이 버린다(그것은 규칙이다 — 화면이 미리 거르지 않는다).
        .onChange(of: input.hopCount) { old, _ in
            for direction in input.hops(since: old) { act { $0.input(direction) } }
        }
        .onChange(of: host.interruptToken) { _, _ in
            game.interrupt()
        }
        .onChange(of: game.isPlaying) { _, playing in
            host.onPlayingChanged(playing)
        }
        // 진행 중 점수를 허브의 장부에 알린다(v0.3.67) — 칩 전환 · 창 닫기처럼 이 뷰가 토큰을 못 보고 사라지는 접기에서도
        // 정지 카드가 약속한 "지금까지의 점수가 기록돼요" 가 지켜지게(`WorkTimerStore.settleMiniGameLiveRound`).
        .onChange(of: game.score) { _, score in host.onScoreChanged(score) }
        .onChange(of: game.phase) { old, new in
            // 결과 확정은 판마다 한 번 — running/over → result 전이가 그 순간이다(interrupt 포함).
            if new == .result, old != .result { host.onFinished(game.score) }
        }
    }

    /// 입력 하나. 정지 중엔 허브가 입력을 안 올리지만(스크림) 한 번 더 막는다 — 얼어 있는 판이 뛰면 정지가 아니다.
    private func act(_ change: (inout CrossyGame) -> Void) {
        guard !host.isPaused else { return }
        let wasPlaying = game.isPlaying
        change(&game)
        // 새 판 첫 프레임은 정지해 있던 동안의 시간을 물려받지 않는다.
        if !wasPlaying, game.isPlaying { lastTick = nil }
    }

    private func tick(_ now: Date) {
        // 프로브는 가드 **앞**이다 — 재는 것이 "프레임 루프가 돌았는가"다(플래피와 같은 규약).
        MiniGameFrameProbe.note()
        guard game.isPlaying, !host.isPaused else { lastTick = nil; return }
        defer { lastTick = now }
        guard let last = lastTick else { return }
        game.step(dt: now.timeIntervalSince(last))
    }

    // MARK: 그림

    private var canvas: some View {
        ZStack {
            CrossySceneView(scene: scene, game: game, reduceMotion: host.reduceMotion,
                            framesPerSecond: MiniGameFrameRate.targetFPS(forRefreshRate: host.refreshHz))
            CrossyHUD(game: game, bestScore: host.bestScore)
        }
        // 모서리만 창 모양대로 잘라 낸다(플래피와 같은 10pt).
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 글자 겹(점수 · 카드)

/// 3D 위에 얹는 SwiftUI 겹 — 위 가운데 점수와 시작/결과 카드. **ImageRenderer 로 찍을 수 있는 쪽**이라 시험이 이 겹만
/// 따로 그려 3D 스냅숏 위에 겹친다(증거 PNG).
struct CrossyHUD: View {
    let game: CrossyGame
    let bestScore: Int

    /// 점수 글자의 세로 중심(pt, 캔버스 위에서). 시안 B 의 점수 자리(62px @2x).
    static let scoreCenterY: CGFloat = 31
    /// 카드 · 행동 알약의 강조색 — 풀밭 위에서 뜨는 따뜻한 노랑(무대가 없는 게임이라 한 색이다).
    static let tint = Color(red: 1.0, green: 0.84, blue: 0.40)
    /// 시작 카드 행동 문구. 클릭 · 스페이스 · 방향키가 다 시작이다(`CrossyGame.action` · `input`).
    static let startAction = "클릭 · 스페이스 · 방향키로 시작"
    /// 결과 카드 행동 문구. 다시 하기는 클릭 · 스페이스뿐이다 — 방향키는 결과 화면에서 무시한다(엔진 `input` 주석).
    static let retryAction = "클릭 · 스페이스로 다시"

    var body: some View {
        ZStack {
            if showsTopScore {
                GeometryReader { geo in
                    Text("\(game.score)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.94))
                        // 그림자 두 겹은 장식이 아니라 가독성이다(밝은 풀밭 · 하늘색 강 위) — 플래피 점수와 같은 처리.
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                        .shadow(color: .black.opacity(0.40), radius: 7)
                        .position(x: geo.size.width / 2, y: Self.scoreCenterY)
                }
                .allowsHitTesting(false)
            }
            overlayCard
        }
    }

    private var showsTopScore: Bool {
        switch game.phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    /// 결과 카드 가운데 줄 — 무엇에 끝났는가 + 최고(또는 신기록).
    /// **글자는 코어 한 벌**(`CrossyResultText`)이다 — 폰 1.0.15 의 결과 카드가 같은 문장을 쓴다(두 벌로 적으면 갈린다).
    static func resultSubtitle(score: Int, best: Int, cause: CrossyGame.DeathCause?) -> String {
        CrossyResultText.subtitle(score: score, best: best, cause: cause)
    }

    @ViewBuilder
    private var overlayCard: some View {
        switch game.phase {
        case .ready:
            MiniGameOverlayCard(
                title: MiniGameKind.crossy.title,
                subtitle: MiniGameKind.crossy.howToPlay,
                action: Self.startAction,
                icon: MiniGameKind.crossy.icon,
                tint: Self.tint
            )
        case .result:
            MiniGameOverlayCard(
                title: String(game.score) + "점",
                titleIsScore: true,
                subtitle: Self.resultSubtitle(score: game.score, best: bestScore, cause: game.death?.cause),
                subtitleIsHighlighted: game.score > bestScore,
                action: Self.retryAction,
                icon: MiniGameKind.crossy.icon,
                tint: Self.tint
            )
        case .running, .over:
            EmptyView()
        }
    }
}

// MARK: - SCNView 다리

/// SCNView 한 장. 마우스는 **받지 않는다**(`hitTest → nil`) — 캔버스 클릭은 허브의 DragGesture 가 받아야
/// 하는데(마우스 다운 = 앞으로 한 칸), AppKit 뷰가 위에 있으면 SwiftUI 제스처가 그 아래로 못 간다.
struct CrossySceneView: NSViewRepresentable {
    let scene: CrossyScene
    let game: CrossyGame
    let reduceMotion: Bool
    /// SCNView 의 그리기 상한 — 판 루프와 같은 주사율의 약수(`MiniGameFrameRate`, 리터럴 60 금지).
    var framesPerSecond: Int = MiniGameFrameRate.baselineFPS

    func makeNSView(context: Context) -> CrossySCNView {
        let view = CrossySCNView(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue),
        ])
        view.scene = scene.scene
        view.crossyScene = scene
        view.pointOfView = scene.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = CrossyPalette.shared.color(CrossyScene.backgroundHex)
        // 모서리는 뷰 층에서도 깎는다 — SwiftUI 의 `.clipShape` 가 AppKit 뷰(메탈 층)까지 가면을 씌운다는 보장이 없다.
        // 14 는 허브 캔버스 테두리 반지름(MiniGamePanel `canvasStack`)이다 — 안쪽 10 보다 바깥 14 가 보이는 모서리다.
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        // 바뀐 프레임만 그린다 — 판이 멈추면 그리기도 멈춘다(유휴 0%).
        view.rendersContinuously = false
        view.isPlaying = false
        view.preferredFramesPerSecond = framesPerSecond
        // 모양을 GPU 에 미리 올린다(백그라운드 — 판 도중 첫 등장에서 올리지 않게). 모양 자체는 `CrossyScene.init` 이 이미 만들었다.
        view.prepare(scene.prewarmShapes, completionHandler: nil)
        scene.apply(game, reduceMotion: reduceMotion)
        return view
    }

    /// 화면에서 내려갈 때(창 닫힘 · 다른 게임 · 계정 전환) 씬을 놓는다(v0.3.67) — SCNView 가 씬을 쥐고 있으면 그림자 맵 ·
    /// MSAA 버퍼 · 노드 풀이 뷰가 해제될 때까지 산다. 밀린 판 · 판 참조도 비운다(가려짐 관찰은 창에서 떨어질 때 거둔다).
    static func dismantleNSView(_ view: CrossySCNView, coordinator: ()) {
        view.pending = nil
        view.crossyScene = nil
        view.scene = nil
    }

    func updateNSView(_ view: CrossySCNView, context: Context) {
        // 창이 가려졌으면(다른 창 뒤 · 다른 데스크톱) 노드를 안 건드린다 — 바뀐 게 없으니 SCNView 도 안 그린다.
        // 다시 보이는 순간 `CrossySCNView` 가 마지막 판을 한 번 옮긴다(아래 occlusion 처리).
        view.pending = (game, reduceMotion)
        if view.preferredFramesPerSecond != framesPerSecond { view.preferredFramesPerSecond = framesPerSecond }
        guard view.isOnScreen else { return }
        scene.apply(game, reduceMotion: reduceMotion)
    }
}

/// 마우스를 통과시키고, 창이 안 보이는 동안 노드 갱신을 멈추는 SCNView.
final class CrossySCNView: SCNView {
    /// 이 뷰가 그리는 판(약한 참조 — 주인은 잎 뷰의 @State 다).
    weak var crossyScene: CrossyScene?
    /// 창이 가려진 동안 밀린 마지막 판(다시 보이면 한 번 옮긴다).
    var pending: (game: CrossyGame, reduceMotion: Bool)?
    private var occlusionObserver: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 창이 실제로 화면에 보이는가(가려짐 · 최소화 · 숨김이면 거짓). 창에 안 붙었으면 거짓.
    var isOnScreen: Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 창에서 떨어지면(nil) 관찰도 거둔다 — 죽은 뷰를 깨우는 관찰자가 남지 않게.
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOnScreen, let pending = self.pending else { return }
                self.crossyScene?.apply(pending.game, reduceMotion: pending.reduceMotion)
            }
        }
    }
}
