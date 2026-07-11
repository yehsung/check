import AppKit
import Metal
import SceneKit
import SwiftUI

/// 아잉 3D 캐릭터 씬 구성.
///
/// 번들(`Bundle.module`)의 `aing.usdz`를 로드하고, 마스코트 원색(보라)이 살도록 모든 재질을
/// unlit(`.constant`)로 바꾼 뒤, 바운딩박스를 기준으로 캐릭터를 살짝 내려다보는 구도로 프레임에 꽉 차게
/// 카메라를 배치한다. 여기에 느린 상하 부유(bob)와 아주 느린 살랑 회전(sway) 애니메이션을 붙인다.
///
/// 기본 PBR/조명에서는 텍스처가 허옇게 떠 마스코트 색이 사라지므로 반드시 `.constant`를 쓴다
/// (오프스크린 렌더로 확인: 조명 모델을 켜면 중앙 픽셀이 거의 흰색, `.constant`면 라벤더 보라).
enum CheckCharacter3DScene {
    /// 카메라 시야각(도). 거리 산정과 프레이밍에 공통으로 쓴다.
    static let fieldOfView: CGFloat = 40

    /// 번들에서 `aing.usdz`를 SCNScene으로 로드한다. 실패 시 nil.
    static func loadModelScene() -> SCNScene? {
        guard let url = Bundle.module.url(forResource: "aing", withExtension: "usdz") else {
            return nil
        }
        return try? SCNScene(url: url, options: nil)
    }

    /// 리액션 wrapper 노드 이름. idle(부유/회전)은 wrapper 안쪽 캐릭터에, 리액션은 wrapper 에 걸어
    /// 서로 간섭하지 않게 한다. makeNSView 가 이 이름으로 wrapper 를 찾아 리액션 엔진에 연결한다.
    static let reactionWrapperName = "check.reactionWrapper"

    /// 오버레이용으로 완성된 씬(재질 unlit·투명 배경·카메라·애니메이션 포함). 로드 실패 시 nil.
    static func makeScene(animated: Bool = true) -> SCNScene? {
        guard let scene = loadModelScene() else { return nil }
        // 씬 배경을 비워 패널 뒤(바탕화면/다른 앱)가 그대로 비치게 한다.
        scene.background.contents = nil
        applyUnlitMaterials(to: scene.rootNode)

        // 임포트된 캐릭터 루트(첫 자식). 없으면 카메라/애니메이션 없이 씬만 돌려준다.
        guard let character = scene.rootNode.childNodes.first else { return scene }

        // 캐릭터를 wrapper 로 감싼다: 리액션은 wrapper(바깥), idle 부유/회전은 캐릭터(안쪽)에 걸어
        // 둘이 같은 트랜스폼을 두고 다투지 않게 분리한다.
        let wrapper = SCNNode()
        wrapper.name = reactionWrapperName
        character.removeFromParentNode()
        wrapper.addChildNode(character)
        scene.rootNode.addChildNode(wrapper)

        addFramingCamera(to: scene)
        if animated {
            addIdleAnimations(to: character)
        }
        return scene
    }

    /// 모든 재질을 unlit(`.constant`)로 전환한다.
    ///
    /// 기본 조명에서 텍스처가 허옇게 뜨는 것을 막아 마스코트 원색을 보존한다.
    static func applyUnlitMaterials(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                material.lightingModel = .constant
            }
        }
    }

    /// 바운딩박스를 기준으로, 캐릭터를 살짝 내려다보는 구도로 프레임에 꽉 차게 카메라를 배치한다.
    ///
    /// 카메라 Y를 캐릭터 중심보다 바운딩 높이의 0.4배 위로 올리고, 바라보는 지점(look target)은
    /// 중심보다 약간 아래로 내려 얼굴이 정면~살짝 위에서 자연스럽게 내려다보이게 한다.
    private static func addFramingCamera(to scene: SCNScene) {
        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        // 상하 부유·살랑 회전 + 내려다보는 각도로 잘리는 여유를 두고 꽉 차게. 최장변 기준 거리 산정 후 1.4배 여유.
        let extent = CGFloat(max(maxB.x - minB.x, maxB.y - minB.y))
        let distance = extent / (2 * tan(fieldOfView / 2 * .pi / 180)) * 1.4

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = fieldOfView
        camera.zNear = 0.01
        camera.zFar = 1_000
        cameraNode.camera = camera
        // 카메라를 캐릭터 중심보다 바운딩 높이의 0.4배 위로 올려 살짝 내려다보게 둔다.
        cameraNode.position = SCNVector3(center.x, center.y + extent * 0.55, CGFloat(maxB.z) + distance)
        // 바라보는 지점을 중심보다 아래(0.16배)로 내려 위에서 내려다보는 구도.
        let lookTarget = SCNVector3(center.x, center.y - extent * 0.16, center.z)
        cameraNode.look(at: lookTarget)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// 생동감을 위한 느린 상하 부유 + 아주 느린 살랑 회전을 무한 반복으로 붙인다.
    private static func addIdleAnimations(to node: SCNNode) {
        let up = SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 1.8)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.moveBy(x: 0, y: -0.07, z: 0, duration: 1.8)
        down.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([up, down])))

        let swayRight = SCNAction.rotateBy(x: 0, y: 0.14, z: 0, duration: 3.6)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateBy(x: 0, y: -0.28, z: 0, duration: 7.2)
        swayLeft.timingMode = .easeInEaseOut
        let swayBack = SCNAction.rotateBy(x: 0, y: 0.14, z: 0, duration: 3.6)
        swayBack.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([swayRight, swayLeft, swayBack])))
    }

    /// 오프스크린 PNG 렌더(시각 검증용). SCNRenderer로 씬을 그려 PNG Data를 돌려준다.
    static func renderSnapshotPNG(size: CGSize = CGSize(width: 280, height: 340)) -> Data? {
        guard let scene = makeScene(animated: false),
              let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// 근무 시간 라벨(캡슐). 모노스페이스 숫자에 반투명 캡슐 배경을 얹어 캐릭터 위에서도 읽히게 한다.
struct CheckOverlayTimerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .fixedSize()
    }
}

/// 3D 캐릭터를 그리는 SCNView 래퍼.
///
/// 배경은 투명하고, 전력 배려를 위해 `preferredFramesPerSecond=20`·저(低) 안티에일리어싱으로 둔다.
/// `isActive == false`(패널 숨김)일 때는 `isPlaying=false`/`rendersContinuously=false`로 렌더 루프를 멈춘다.
struct CheckCharacter3DView: NSViewRepresentable {
    /// true일 때만 렌더 루프/애니메이션을 돌린다. 패널 숨김 시 false → 정지(전력 절약).
    var isActive: Bool
    /// 리액션 엔진. makeNSView 에서 wrapper 노드/씬 루트를 연결한다(없으면 리액션 없이 idle 만).
    var engine: ReactionEngine?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = CheckCharacter3DScene.makeScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        // 전력 배려: 안티에일리어싱 최소(2X), 프레임 상한 20.
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 20
        view.isPlaying = isActive
        view.rendersContinuously = isActive
        if let engine,
           let root = scene?.rootNode,
           let wrapper = root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false) {
            engine.attach(node: wrapper, sceneRoot: root)
        }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.isPlaying = isActive
        view.rendersContinuously = isActive
    }
}

/// 팀원 출근 인사 말풍선. 캐릭터 왼쪽 위에 뜨는 반투명 캡슐(꼬리 포함). 3초 후 엔진이 텍스트를 비우면 사라진다.
struct CheckGreetingBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(.black.opacity(0.85))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .frame(maxWidth: 110, alignment: .leading)
    }
}

/// 3D 캐릭터 + 근무 시간 라벨 합성. 라벨은 얼굴(볼) 바로 아래 몸통 중상부에 얹는다.
/// 리액션 엔진을 관찰해 팀원 출근 인사 말풍선을 캐릭터 왼쪽 위에 겹쳐 띄운다(패널 폭 안 수납).
struct CheckOverlayCharacterView: View {
    /// 근무 시간 라벨의 세로 위치 비율(0=상단, 1=하단). 볼 아래 몸통 중상부(얼굴은 안 가림)에 오도록 54%.
    static let timerVerticalFraction: CGFloat = 0.49

    let elapsedSeconds: Int
    let isActive: Bool
    var engine: ReactionEngine?

    var body: some View {
        GeometryReader { geo in
            // 렌더 루프는 엔진의 renderActive(패널 표시~근무종료 인사)로 몬다. 엔진이 없으면 isActive 로 폴백한다.
            let renderActive = engine?.renderActive ?? isActive
            ZStack(alignment: .topLeading) {
                CheckCharacter3DView(isActive: renderActive, engine: engine)
                    .frame(width: geo.size.width, height: geo.size.height)
                CheckOverlayTimerLabel(text: CheckOverlayTimeFormatter.text(elapsedSeconds))
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height * Self.timerVerticalFraction
                    )
                if let engine, let greeting = engine.greetingText {
                    CheckGreetingBubble(text: greeting)
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .id(greeting)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: engine?.greetingText)
        }
    }
}

/// 오버레이 패널의 SwiftUI 루트. store를 관찰해 근무 상태 변화 시 콜백으로 패널 표시/숨김을 알린다.
///
/// `store.snapshot`을 body에서 읽어 관찰을 등록하고, `isWorking` 변화를 `onChange`로 컨트롤러에 전달한다.
/// `elapsedSeconds`는 store의 1초 틱을 그대로 따라가므로 라벨이 실시간으로 흐른다.
struct CheckOverlayRootView: View {
    let store: WorkTimerStore
    var engine: ReactionEngine?
    var onWorkingChange: (Bool) -> Void

    var body: some View {
        CheckOverlayCharacterView(
            elapsedSeconds: store.todayDuration,
            isActive: store.snapshot.isWorking,
            engine: engine
        )
        .onChange(of: store.snapshot.isWorking, initial: true) { _, working in
            onWorkingChange(working)
        }
        // 캐릭터 표시 토글이 근무 중에 바뀌어도 즉시 반영되도록 같은 콜백을 태운다.
        .onChange(of: store.isOverlayEnabled) { _, _ in
            onWorkingChange(store.snapshot.isWorking)
        }
    }
}

/// 오버레이 근무 시간 표기. 1시간 이상은 HH:MM:SS, 미만은 MM:SS.
///
/// 1시간 미만 구간은 `MenuBarStatusFormatter.duration`(MM:SS)을 그대로 재사용하고,
/// 1시간 이상은 초까지 흐르도록 HH:MM:SS로 확장한다(메뉴바 라벨은 HH:MM이라 별도).
enum CheckOverlayTimeFormatter {
    static func text(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        guard safe >= 3_600 else {
            return MenuBarStatusFormatter.duration(safe)
        }
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let secs = safe % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
