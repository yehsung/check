#if os(iOS)
import CheckCore
import SceneKit
import SwiftUI

// 길건너 아잉이 한 프레임의 그림(폰 1.0.15 D6) — 맥 `Sources/check/MiniGameCrossy.swift` 의 겹 순서를 그대로 옮겼다.
// 그릴 것을 새로 만들지 않았다: 3D 판(`CrossyScene`)·색·모양은 **코어 한 벌**이고 맥과 폰이 같이 읽는다
// (`Sources/CheckCore/CrossyScene.swift`). 그래서 같은 판의 스크린샷 둘은 카메라까지 같다.
//
// ── 겹 셋(맥과 같은 순서) ─────────────────────────────────────────────────────────────────
// ① 아래: SCNView 한 장(`UIViewRepresentable`). ② 그 위: SwiftUI 점수 글자. ③ 맨 위: **폰 공용** 카드
// (`GamesOverlayCard` — 맥 `MiniGameOverlayCard` 를 끌어오지 않았다. 폰 카드는 불투명·손가락 기호·배율을 타는
// 자기 규약이 있다). 점수를 3D 로 그리지 않는 까닭은 테트리스가 글자를 Canvas 밖에 둔 것과 같다 — 글자는
// SwiftUI 가 제일 잘 그리고 `.monospacedDigit()` 같은 규약이 그대로 산다.
//
// ── 맥과 다른 점 셋 ───────────────────────────────────────────────────────────────────────
// ① **글꼴·자리에 배율을 곱한다.** 맥 HUD 는 실제 pt(28 · y 31)인데, 그 값은 344×356 캔버스 기준이다. 폰 캔버스는
//    폭이 기기마다 다르므로 논리 292×302 로 환산해 곱한다: 28 × 292/344 = 23.8 → 24, 31 × 302/356 = 26.3 → 26.
// ② **창 가려짐 대신 `scenePhase`.** 맥은 `NSWindow.occlusionState` 를 보고 노드 갱신을 건너뛴다. 폰에 그 개념이
//    없으므로 background 면 건너뛴다(복귀하면 환경값이 바뀌어 body 가 다시 평가되고 그때 한 번 옮긴다).
// ③ **키보드가 없다.** 조작(쓸기·탭)은 `GamesPlayController` 가 들고 있고 이 뷰는 **그림만** 그린다 —
//    세 캔버스와 같은 계약이다(`game` · `bestScore` · `reduceMotion` + 주사율).
//
// ── 그대로 지킨 예산(맥 파일 머리 주석) ───────────────────────────────────────────────────
// · `rendersContinuously = false` — 노드가 안 바뀌면 그리지 않는다(판이 멈추면 GPU 도 쉰다).
// · `preferredFramesPerSecond` 는 **주사율에서 온다**(리터럴 60 금지 — `MiniGameFrameRate`).
// · 모양은 뷰가 처음 설 때 GPU 로 미리 올린다(`prepare`) — 첫 기찻길·첫 트럭 색이 판 **도중**에 올라가지 않게.
// · 화면에서 내려가면 씬을 **놓는다**(`dismantleUIView`) — 안 그러면 그림자 맵·MSAA 버퍼·노드 풀이 뷰가
//   해제될 때까지 산다(맥 검토 지적과 같은 자리).
// · SwiftUI 반복 애니메이션(`repeatForever`) 금지.

/// 길건너 캔버스(3D 판 + 점수 글자 + 시작/결과 카드). 세 캔버스와 같은 서명 + 주사율 하나.
struct GamesCrossyCanvas: View {
    let game: CrossyGame
    let bestScore: Int
    let reduceMotion: Bool
    /// SCNView 의 그리기 상한 — 판 루프와 같은 주사율의 약수(`MiniGameFrameRate`, 리터럴 60 금지).
    var framesPerSecond: Int = MiniGameFrameRate.baselineFPS

    /// 3D 판(노드 풀 · 아잉이 모델 포함). 캔버스가 사는 동안 **하나**다 — 새 판은 같은 씬에서 줄만 갈아 끼운다.
    /// `@StateObject` 라 처음 한 번만 만든다(`@State` 면 프레임마다 아잉이 모델 4.7MB 를 다시 읽는다).
    @StateObject private var scene = CrossyScene(aingLoader: GamesCrossyAing.load)
    @Environment(\.scenePhase) private var scenePhase

    /// 점수 글자 크기·세로 중심(논리 pt — 위 머리 주석 ①의 환산값).
    private static let scoreFontSize: CGFloat = 24
    private static let scoreCenterY: CGFloat = 26
    /// 카드·점수의 강조색 — 풀밭 위에서 뜨는 따뜻한 노랑. 맥 `CrossyHUD.tint` 와 **같은 값**이다
    /// (무대가 없는 게임이라 한 색이다 — `MiniGameStage` 를 안 쓴다).
    private static let tint = Color(red: 1.0, green: 0.84, blue: 0.40)

    var body: some View {
        ZStack {
            CrossySceneUIView(scene: scene, game: game, reduceMotion: reduceMotion,
                              framesPerSecond: framesPerSecond, isVisible: scenePhase != .background)
            scoreLayer
            overlayCard
        }
    }

    // MARK: 점수 글자

    @ViewBuilder
    private var scoreLayer: some View {
        if showsTopScore {
            GeometryReader { geo in
                let t = MiniGameProjection(container: geo.size)
                Text("\(game.score)")
                    .font(.system(size: Self.scoreFontSize * t.scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.94))
                    // 그림자 두 겹은 장식이 아니라 가독성이다(밝은 풀밭 · 하늘색 강 위) — 맥과 같은 처리.
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.40), radius: 7)
                    .position(x: geo.size.width / 2, y: t.y(Self.scoreCenterY))
            }
            .allowsHitTesting(false)
        }
    }

    private var showsTopScore: Bool {
        switch game.phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    // MARK: 시작 · 결과 카드

    /// 카드는 **가운데**다(맥과 같다). 배율 0.82 는 세 캔버스가 쓰는 값이다.
    ///
    /// 결과 줄은 코어 한 벌(`CrossyResultText.subtitle`)이다 — 맥 결과 카드와 **같은 문장**이어야 한다
    /// (사유 + 최고/신기록). 여기서 새로 적으면 같은 기능이 두 말을 한다.
    @ViewBuilder
    private var overlayCard: some View {
        GeometryReader { geo in
            let scale = MiniGameProjection(container: geo.size).scale
            Group {
                switch game.phase {
                case .ready:
                    GamesOverlayCard(
                        title: MiniGameKind.crossy.title,
                        subtitle: GamesMiniGameText.howToPlay(.crossy),
                        action: GamesMiniGameText.startAction,
                        icon: MiniGameKind.crossy.icon,
                        tint: Self.tint, scale: scale * 0.82)
                case .result:
                    GamesOverlayCard(
                        title: String(game.score) + "점",
                        titleIsScore: true,
                        subtitle: CrossyResultText.subtitle(score: game.score, best: bestScore, cause: game.death?.cause),
                        subtitleIsHighlighted: game.score > bestScore,
                        action: GamesMiniGameText.againAction,
                        icon: MiniGameKind.crossy.icon,
                        tint: Self.tint, scale: scale * 0.82)
                case .running, .over:
                    EmptyView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - SCNView 다리

/// SCNView 한 장. **터치를 받지 않는다**(`isUserInteractionEnabled = false`) — 캔버스의 쓸기·탭은 화면의
/// `DragGesture` 가 받아야 하는데, UIKit 뷰가 위에 있으면 SwiftUI 제스처가 그 아래로 못 간다
/// (저장소 메모 '테스트 패널이 클릭을 가로챈다'와 같은 기전이다).
private struct CrossySceneUIView: UIViewRepresentable {
    let scene: CrossyScene
    let game: CrossyGame
    let reduceMotion: Bool
    var framesPerSecond: Int = MiniGameFrameRate.baselineFPS
    /// 화면이 지금 보이는가(background 면 거짓). 맥의 창 가려짐 처리에 대응하는 폰 자리다.
    let isVisible: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue),
        ])
        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = CrossyPalette.shared.color(CrossyScene.backgroundHex)
        // 모서리는 뷰 층에서도 깎는다 — SwiftUI 의 `.clipShape` 가 메탈 층까지 가면을 씌운다는 보장이 없다.
        // 14 는 화면 캔버스 테두리 반지름(`GamesMiniGameScreen.canvas`)과 같은 수다.
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        // 바뀐 프레임만 그린다 — 판이 멈추면 그리기도 멈춘다(유휴 0%).
        view.rendersContinuously = false
        view.isPlaying = false
        view.preferredFramesPerSecond = framesPerSecond
        view.isUserInteractionEnabled = false
        // 모양을 GPU 에 미리 올린다(백그라운드). 모양 자체는 `CrossyScene.init` 이 이미 만들었다.
        view.prepare(scene.prewarmShapes, completionHandler: nil)
        scene.apply(game, reduceMotion: reduceMotion)
        return view
    }

    /// 화면에서 내려갈 때(뒤로가기 · 다른 게임 · 로그아웃) 씬을 놓는다 — 맥 `dismantleNSView` 와 같은 일이다.
    /// SCNView 가 씬을 쥐고 있으면 그림자 맵 · MSAA 버퍼 · 노드 풀이 뷰가 해제될 때까지 산다.
    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.scene = nil
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.preferredFramesPerSecond != framesPerSecond { view.preferredFramesPerSecond = framesPerSecond }
        // background 면 노드를 안 건드린다 — 바뀐 게 없으니 SCNView 도 안 그린다. 복귀하면 `scenePhase` 가 바뀌어
        // body 가 다시 평가되고 여기서 마지막 판을 한 번 옮긴다.
        guard isVisible else { return }
        scene.apply(game, reduceMotion: reduceMotion)
    }
}
#endif
