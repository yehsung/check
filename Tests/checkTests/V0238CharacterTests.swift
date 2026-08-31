import AppKit
import Darwin
import SceneKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.2.38 β2 "가벼워지기": 캐릭터 렌더 진짜 정지(Q2) + USDZ → .scn 프리베이크(M3)
//
// 계측으로 확정된 결함 둘을 재현·방어한다(수치는 같은 머신 실측, 추측과 섞지 않는다).
//
// Q2. 패널을 숨겨도(`isActive == false`) SCNView 렌더 루프가 계속 돌았다. `isPlaying=false`/`rendersContinuously=false`
//     는 idle 무한 SCNAction(부유·살랑)이 살아 있는 한 무력하다 — 하네스 7.2fps, 이 파일의 프로브 7.3fps(창을 orderOut
//     해도 같다). 루프가 사는 동안 GPU 풀 ≈100MB 가 붙들리고, 루프를 멈추면 즉시 회수된다(161→57MB). 캐릭터 루트를
//     `isPaused` 로 세우면 ~0.4초 꼬리 뒤 0fps 가 된다. 제품 결정: 근무 중 보일 때는 항상 살아 있고, 멈추는 건 안 보일
//     때뿐 — 표시 의도(isActive)와 정지 사유(engine.renderSuspended: 화면 슬립·잠금·세션 비활성)의 AND 다.
//
// M3. usdz 를 매 실행 런타임 임포트하면 USD/ModelIO 상주(+22~38MB) + USD 워커 스레드 11개 + 폴링 슬리퍼 1개가 실행
//     내내 남고, 2048² 텍스처를 디코드한 뒤 512 로 다시 줄인다. 프리베이크 .scn 은 NSKeyedUnarchiver 경로라 그 어느
//     것도 만들지 않는다(로드 65+78ms → 3ms, 스레드 +14 → +0). 단, .scn 은 임베드 텍스처를 `Data` 로 돌려주므로
//     "디퓨즈는 CGImage" 계약(엔진이 얼굴을 찾는 열쇠 — 깨지면 깜빡임·졸기 눈이 조용히 사라진다)을 로더가 지켜야 한다.

// MARK: - 헬퍼

/// 렌더 프레임 카운터. `didRenderScene` 은 SceneKit 렌더 스레드에서 오므로 락으로 센다.
final class V0238RenderCounter: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock(); count += 1; lock.unlock()
    }
    func reset() { lock.lock(); count = 0; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// 메인 런루프를 `seconds` 동안 돌린다(SceneKit 디스플레이 링크·SwiftUI 갱신이 그 사이에 처리된다).
@MainActor
private func v0238Spin(_ seconds: Double) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
}

/// 조건이 참이 될 때까지 20ms 씩 스핀한다. 예산은 **벽시계가 아니라 스핀 횟수**다(기본 500회 ≈ 10초의 '내' 런루프 시간):
/// 스위트가 병렬이라 다른 @MainActor 테스트의 긴 동기 작업(픽셀 루프 수십 초)이 내 스핀 **안에** 중첩 실행되는데,
/// 벽시계 마감이면 그 한 번의 중첩으로 예산이 통째로 타 버려 디스플레이 링크가 틱 할 기회를 한 번도 못 받는다
/// (실측: 감은눈 테스트와 같이 돌리면 15초 마감이 렌더 0회로 끝났다). 조건이 참이 되는 즉시 돌아온다.
@MainActor
private func v0238SpinUntil(maxSpins: Int = 500, _ condition: () -> Bool) -> Bool {
    for _ in 0..<maxSpins {
        if condition() { return true }
        v0238Spin(0.02)
    }
    return condition()
}

/// **절대 화면에 올리지 않는** 알파 0 창에 SCNView 를 담는다. 안 띄운 창에서도 SCNView 렌더 루프는 돈다
/// (같은 머신 실측: never-shown 창 8fps / 창 없음 0fps) — 이 저장소는 테스트가 데스크톱을 캐릭터로 도배한 사고가
/// 있어 창을 안 띄우는 길이 있으면 그 길로 간다.
@MainActor
private final class V0238RenderRig {
    let scene: SCNScene
    let view: SCNView
    let window: NSWindow
    let counter = V0238RenderCounter()

    init(scene: SCNScene) {
        self.scene = scene
        view = SCNView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        view.scene = scene
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = ReactionEngine.idleFPS
        view.delegate = counter
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 300, y: 300), size: view.frame.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = view
    }

    /// 이 뷰가 `frames` 프레임 이상 그릴 때까지 스핀한다(스핀 예산 `maxSpins`). 도달하면 true.
    func spinUntilRendered(atLeast frames: Int, maxSpins: Int = 750) -> Bool {
        v0238SpinUntil(maxSpins: maxSpins) { counter.value >= frames }
    }

    func teardown() {
        view.delegate = nil
        view.scene = nil
        window.contentView = nil
    }
}

@MainActor
private func firstSCNView(in view: NSView) -> SCNView? {
    if let scn = view as? SCNView { return scn }
    for sub in view.subviews {
        if let found = firstSCNView(in: sub) { return found }
    }
    return nil
}

@MainActor
private func wrapperNode(in scene: SCNScene?) -> SCNNode? {
    scene?.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
}

/// 씬에서 얼굴(큰 CGImage 디퓨즈) 재질을 찾는다 — ReactionEngine.locateSleepEyeTargets 와 같은 기준.
@MainActor
private func v0238FaceMaterial(in scene: SCNScene) -> SCNMaterial? {
    var found: SCNMaterial?
    scene.rootNode.enumerateHierarchy { node, stop in
        for material in node.geometry?.materials ?? [] {
            let contents = material.diffuse.contents
            guard let contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
            if (contents as! CGImage).width >= 256 { found = material; stop.pointee = true; return }
        }
    }
    return found
}

/// 씬 지문 — 두 출처의 로드 결과가 같은 모델인지 판정하는 축(노드 수·이름·정점/삼각형 수·바운딩박스).
private struct V0238Fingerprint: Equatable, CustomStringConvertible {
    var names: [String]
    var geometryCount: Int
    var vertexCounts: [Int]
    var primitiveCounts: [Int]
    var bbox: [Float]
    var description: String {
        "names=\(names) geos=\(geometryCount) verts=\(vertexCounts) prims=\(primitiveCounts) bbox=\(bbox)"
    }
}

@MainActor
private func v0238Fingerprint(_ scene: SCNScene) -> V0238Fingerprint {
    var names = [String](), verts = [Int](), prims = [Int](), geos = 0
    scene.rootNode.enumerateHierarchy { node, _ in
        names.append(node.name ?? "")
        if let geometry = node.geometry {
            geos += 1
            verts.append(geometry.sources(for: .vertex).first?.vectorCount ?? 0)
            prims.append(geometry.elements.reduce(0) { $0 + $1.primitiveCount })
        }
    }
    let (minB, maxB) = scene.rootNode.boundingBox
    let bbox = [minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z].map { (Float($0) * 10_000).rounded() / 10_000 }
    return V0238Fingerprint(names: names, geometryCount: geos, vertexCounts: verts, primitiveCounts: prims, bbox: bbox)
}

/// 씬의 모든 재질(순회 순서대로).
@MainActor
private func v0238Materials(in scene: SCNScene) -> [SCNMaterial] {
    var out = [SCNMaterial]()
    scene.rootNode.enumerateHierarchy { node, _ in out.append(contentsOf: node.geometry?.materials ?? []) }
    return out
}

/// CGImage → RGBA8(premultipliedLast) 바이트.
private func v0238RGBA(_ cg: CGImage) -> [UInt8] {
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}

/// 이 프로세스의 스레드 수(mach). 실패 시 -1.
private func v0238ThreadCount() -> Int {
    var list: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS else { return -1 }
    if let list {
        let size = vm_size_t(count) * vm_size_t(MemoryLayout<thread_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
    }
    return Int(count)
}

/// 메인 디스플레이가 깨어 있는가. SCNView 의 디스플레이 링크는 화면이 자면 **한 프레임도 틱 하지 않는다**(같은 머신 실측:
/// 화면 슬립 상태에서 활성 SCNView 가 15초간 0프레임, `caffeinate -u` 로 화면만 깨우면 — 세션은 잠긴 채로 — 곧바로 6~8fps).
/// 그래서 실제 프레임 수를 세는 테스트는 이 조건에서만 의미가 있다 — 잠든 화면에서 돌면 "정지 뷰 0회"가 아무 것도 증명하지
/// 못하므로 실패도 통과도 아닌 **건너뜀**으로 남긴다(`.enabled(if:)`). 이 조건이 바로 β1 이 renderSuspended 로 잡는 그 순간이다.
private var v0238DisplayIsAwake: Bool {
    CGDisplayIsAsleep(CGMainDisplayID()) == 0 && CGDisplayIsActive(CGMainDisplayID()) != 0
}

// MARK: - Q2 (a) 비활성 → 캐릭터 루트 isPaused=true · isPlaying=false, 재활성 → 복귀

@MainActor
@Test
func inactiveRenderStatePausesCharacterRootAndStopsPlaying() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene())
    let wrapper = try #require(wrapperNode(in: scene))
    let view = SCNView()
    view.scene = scene

    CheckCharacter3DView.applyRenderState(active: false, to: view)
    #expect(view.isPlaying == false)
    #expect(view.rendersContinuously == false)
    #expect(wrapper.isPaused, "비활성인데 캐릭터 루트가 서 있지 않다 — idle 무한 액션이 렌더 루프를 계속 깨운다")
    // 세우는 노드는 wrapper(리액션 액션 자리)이고, idle 액션은 그 자손(캐릭터)에 걸려 있어 함께 선다.
    #expect(CheckCharacter3DView.characterRootNode(in: scene) === wrapper)

    CheckCharacter3DView.applyRenderState(active: true, to: view)
    #expect(view.isPlaying)
    #expect(view.rendersContinuously)
    #expect(wrapper.isPaused == false, "재활성했는데 캐릭터가 얼어 있다")
}

@MainActor
@Test
func renderActiveIsTheANDOfIntentAndNotSuspended() {
    // β1 계약 식: 표시 의도 AND 정지 사유 없음. 어느 한쪽만으로는 살지 않는다.
    #expect(CheckCharacter3DView.renderActive(isActive: true, renderSuspended: false))
    #expect(CheckCharacter3DView.renderActive(isActive: true, renderSuspended: true) == false)
    #expect(CheckCharacter3DView.renderActive(isActive: false, renderSuspended: false) == false)
    #expect(CheckCharacter3DView.renderActive(isActive: false, renderSuspended: true) == false)
}

// MARK: - Q2 (b) renderSuspended=true 면 isActive=true 여도 정지, 해제 시 1 업데이트 내 재개

/// 컨테이너(CheckCharacter3DView) 단독 호스팅 — `engine.renderSuspended` 를 읽는 유일한 지점이 update 를 실제로
/// 다시 부르게 하는지(NSViewRepresentable 의 관찰 추적)를 값으로 고정한다.
@MainActor
@Test
func renderSuspendedStopsTheContainerEvenWhileActiveAndResumesOnRelease() throws {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let hosting = NSHostingView(rootView: CheckCharacter3DView(isActive: true, engine: engine))
    hosting.frame = NSRect(x: 0, y: 0, width: 140, height: 170)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    defer { window.contentView = nil }

    let scnView = try #require(firstSCNView(in: hosting), "호스팅 계층에 SCNView 가 없다")
    let wrapper = try #require(wrapperNode(in: scnView.scene))
    #expect(scnView.isPlaying)
    #expect(wrapper.isPaused == false)

    // 화면 슬립/잠금: 표시 의도(isActive=true)는 그대로인데 정지 사유가 올라온다.
    engine.renderSuspended = true
    #expect(v0238SpinUntil { scnView.isPlaying == false }, "renderSuspended=true 인데 렌더가 계속 돈다")
    #expect(wrapper.isPaused, "renderSuspended=true 인데 캐릭터 루트가 서 있지 않다")
    #expect(scnView.rendersContinuously == false)

    // 깨어남: 사유 하나만 내려가면 다음 갱신 한 번에 되살아난다.
    engine.renderSuspended = false
    hosting.layoutSubtreeIfNeeded()
    v0238Spin(0.05)
    #expect(scnView.isPlaying, "renderSuspended 해제 후 1 업데이트 안에 재개되지 않았다")
    #expect(wrapper.isPaused == false)
    #expect(scnView.rendersContinuously)
}

/// 실제 합성(CheckOverlayCharacterView → CheckCharacter3DView) 에서도 같은 결과 — 루트 뷰가 넘기는 isActive
/// (renderActive) 는 true 인 채로 정지 사유만 흐른다.
@MainActor
@Test
func renderSuspendedFlowsThroughTheOverlayCharacterComposition() throws {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_100) })
    engine.renderActive = true
    let root = CheckOverlayCharacterView(elapsedSeconds: 0, isActive: true, showsTimer: false, engine: engine)
    let hosting = NSHostingView(rootView: root)
    hosting.frame = NSRect(x: 0, y: 0, width: 140, height: 170)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    defer { window.contentView = nil }
    #expect(v0238SpinUntil { firstSCNView(in: hosting) != nil }, "지연 마운트 후에도 SCNView 가 없다")
    let scnView = try #require(firstSCNView(in: hosting))
    let wrapper = try #require(wrapperNode(in: scnView.scene))
    #expect(v0238SpinUntil { scnView.isPlaying })

    engine.renderSuspended = true
    #expect(v0238SpinUntil { scnView.isPlaying == false && wrapper.isPaused })
    // 표시 의도는 건드리지 않았다 — 깨어나면 이 값 하나만 내려가면 된다.
    #expect(engine.renderActive)

    engine.renderSuspended = false
    #expect(v0238SpinUntil { scnView.isPlaying && wrapper.isPaused == false })
}

// MARK: - Q2 (c) 정지 중 didRenderScene 0회/초 (기존 테스트는 preferredFramesPerSecond 만 봤다)

/// 시간 창을 벽시계가 아니라 **대조 뷰(canary)의 프레임 수**로 정한다. SCNView 렌더는 메인 스레드에서 돌고 스위트는
/// 병렬이라, 다른 @MainActor 테스트의 긴 동기 작업(픽셀 루프 수 초)이 끼면 벽시계 1초 동안 어느 뷰도 못 그린다 —
/// 그때 "정지 뷰 0회"는 아무 것도 증명하지 못한다. 같은 조건의 대조 뷰가 N 프레임을 그리는 동안 정지 뷰가 0회면,
/// 굶주림과 무관하게 정지가 진짜다(둘은 같은 디스플레이 틱을 받는다).
@MainActor
@Test(.enabled(if: v0238DisplayIsAwake, "화면이 자는 동안은 SCNView 디스플레이 링크가 틱 하지 않아 프레임을 셀 수 없다"))
func pausedCharacterRendersZeroFramesWhileACanaryKeepsRendering() throws {
    let paused = V0238RenderRig(scene: try #require(CheckCharacter3DScene.makeScene()))
    let canary = V0238RenderRig(scene: try #require(CheckCharacter3DScene.makeScene()))
    defer { paused.teardown(); canary.teardown() }
    for rig in [paused, canary] {
        #expect(rig.window.alphaValue == 0)
        #expect(rig.window.isVisible == false, "이 창은 화면에 올라가면 안 된다")
    }

    // 둘 다 활성: 유휴 fps 로 돈다(계측 감도 — 이게 안 오면 아래 0 은 무의미하다).
    CheckCharacter3DView.applyRenderState(active: true, to: paused.view)
    CheckCharacter3DView.applyRenderState(active: true, to: canary.view)
    #expect(paused.spinUntilRendered(atLeast: 2), "활성인데 렌더가 없다 — 계측 자체가 죽었다")
    #expect(canary.spinUntilRendered(atLeast: 2), "대조 뷰가 그리지 않는다 — 계측 자체가 죽었다")

    // 한쪽만 정지. 정지 직후 ~3프레임 꼬리(실측 0.07/0.21/0.34s)가 있으므로 대조 뷰가 8프레임을 더 그릴 때까지 흘려보낸 뒤,
    // 대조 뷰가 다시 5프레임을 그리는 창에서 정지 뷰의 렌더 횟수를 센다 → **0**.
    // isPaused 대입이 빠지면 idle 액션이 살아 정지 뷰도 대조 뷰와 같은 fps 로 돈다(실측 7.3fps).
    CheckCharacter3DView.applyRenderState(active: false, to: paused.view)
    canary.counter.reset()
    #expect(canary.spinUntilRendered(atLeast: 8), "정착 구간에서 대조 뷰가 멈췄다")
    paused.counter.reset()
    canary.counter.reset()
    #expect(canary.spinUntilRendered(atLeast: 5), "측정 구간에서 대조 뷰가 멈췄다")
    let pausedRenders = paused.counter.value
    #expect(pausedRenders == 0, "정지 중인데 대조 뷰 5프레임 동안 \(pausedRenders)회 그렸다 — 렌더 루프가 살아 있다(GPU 풀 ≈100MB 가 안 풀린다)")

    // 재활성: 바로 되살아난다.
    CheckCharacter3DView.applyRenderState(active: true, to: paused.view)
    paused.counter.reset()
    #expect(paused.spinUntilRendered(atLeast: 2), "재활성 후 렌더가 돌아오지 않았다")
}

// MARK: - M3 (d) .scn 로드 계약 = usdz 로드 계약

@MainActor
@Test
func prebakedSceneIsShippedAndPreferredByTheLoader() throws {
    // 산출물이 번들에 실려 있고(scripts/prebake-character.swift 를 돌린 결과), 기본 로더가 그것을 고른다.
    #expect(CheckCharacter3DScene.modelURL(for: .prebaked) != nil, "aing.scn 이 번들에 없다 — scripts/prebake-character.swift 를 실행해 산출물을 Resources 에 넣어라")
    #expect(CheckCharacter3DScene.modelURL(for: .usdz) != nil, "폴백 원본 aing.usdz 가 번들에 없다")
    #expect(CheckCharacter3DScene.ModelSource.allCases.first == .prebaked, "선언 순서가 로드 우선순위다 — 프리베이크가 먼저여야 한다")
    let loaded = try #require(CheckCharacter3DScene.loadModelScene(order: CheckCharacter3DScene.ModelSource.allCases))
    #expect(loaded.source == .prebaked)
}

@MainActor
@Test
func prebakedAndUSDZLoadTheSameModel() throws {
    let scn = try #require(CheckCharacter3DScene.loadModelScene(from: .prebaked), "aing.scn 로드 실패")
    let usdz = try #require(CheckCharacter3DScene.loadModelScene(from: .usdz), "aing.usdz 로드 실패")

    // 노드 수·이름·정점/삼각형 수·바운딩박스가 같다(임포트 직후, 베이크 전).
    let scnPrint = v0238Fingerprint(scn), usdzPrint = v0238Fingerprint(usdz)
    #expect(scnPrint == usdzPrint, "지문 불일치\n  scn:  \(scnPrint)\n  usdz: \(usdzPrint)")
    #expect(scnPrint.geometryCount >= 1)

    // 런타임 베이크(applyUnlitMaterials)를 양쪽에 태우면 재질 계약이 같아진다: .constant · CGImage · ≤512 · 같은 치수 · 같은 픽셀.
    CheckCharacter3DScene.applyUnlitMaterials(to: scn.rootNode)
    CheckCharacter3DScene.applyUnlitMaterials(to: usdz.rootNode)
    let scnMaterials = v0238Materials(in: scn), usdzMaterials = v0238Materials(in: usdz)
    #expect(scnMaterials.count == usdzMaterials.count)
    #expect(scnMaterials.count >= 1)
    var comparedTextures = 0
    for (a, b) in zip(scnMaterials, usdzMaterials) {
        #expect(a.lightingModel == .constant)
        #expect(b.lightingModel == .constant)
        let ca = a.diffuse.contents, cb = b.diffuse.contents
        guard let ca, let cb else {
            #expect(ca == nil && cb == nil, "한쪽만 디퓨즈가 있다")
            continue
        }
        #expect(CFGetTypeID(ca as CFTypeRef) == CGImage.typeID, ".scn 경로 디퓨즈가 CGImage 가 아니다(\(type(of: ca))) — 엔진이 얼굴을 못 찾는다")
        #expect(CFGetTypeID(cb as CFTypeRef) == CGImage.typeID, "usdz 경로 디퓨즈가 CGImage 가 아니다(\(type(of: cb)))")
        guard CFGetTypeID(ca as CFTypeRef) == CGImage.typeID, CFGetTypeID(cb as CFTypeRef) == CGImage.typeID else { continue }
        let ia = ca as! CGImage, ib = cb as! CGImage
        #expect(max(ia.width, ia.height) <= 512)
        #expect(max(ib.width, ib.height) <= 512)
        #expect(ia.width == ib.width && ia.height == ib.height, "텍스처 치수 불일치 scn=\(ia.width)x\(ia.height) usdz=\(ib.width)x\(ib.height)")
        guard ia.width == ib.width, ia.height == ib.height else { continue }
        // 픽셀: 프리베이크는 같은 리샘플 결과를 PNG(무손실)로 임베드했으므로 사실상 동일해야 한다.
        let pa = v0238RGBA(ia), pb = v0238RGBA(ib)
        var total = 0
        for i in 0..<pa.count { total += abs(Int(pa[i]) - Int(pb[i])) }
        let meanAbs = Double(total) / Double(pa.count)
        #expect(meanAbs <= 1.0, "텍스처 픽셀 평균 오차 \(meanAbs) — 프리베이크와 런타임 리샘플이 갈렸다(scripts/prebake-character.swift 재실행 필요)")
        comparedTextures += 1
    }
    #expect(comparedTextures >= 1, "비교한 텍스처가 없다")
}

@MainActor
@Test
func loaderFallsBackToUSDZWhenPrebakeIsMissingOrUnreadable() throws {
    // ① 프리베이크가 번들에 없는 경우(리소스 누락) → usdz.
    let missing = try #require(CheckCharacter3DScene.loadModelScene(
        order: CheckCharacter3DScene.ModelSource.allCases,
        url: { $0 == .prebaked ? nil : CheckCharacter3DScene.modelURL(for: $0) }
    ))
    #expect(missing.source == .usdz, "프리베이크가 없는데 usdz 로 내려가지 않았다")
    #expect(v0238Fingerprint(missing.scene).geometryCount >= 1)

    // ② 프리베이크가 있지만 못 읽는 경우(구버전 SceneKit 의 아카이브 거부·손상 다운로드) → usdz. 캐릭터가 사라지면 안 된다.
    let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("v0238-corrupt-\(UUID().uuidString).scn")
    try Data((0..<4_096).map { _ in UInt8.random(in: 0...255) }).write(to: corrupt)
    defer { try? FileManager.default.removeItem(at: corrupt) }
    let unreadable = try #require(CheckCharacter3DScene.loadModelScene(
        order: CheckCharacter3DScene.ModelSource.allCases,
        url: { $0 == .prebaked ? corrupt : CheckCharacter3DScene.modelURL(for: $0) }
    ))
    #expect(unreadable.source == .usdz, "손상된 프리베이크에서 usdz 로 내려가지 않았다")

    // ③ 둘 다 없으면 nil(캐릭터 없이 진행 — 종전과 같은 실패 모드).
    #expect(CheckCharacter3DScene.loadModelScene(order: CheckCharacter3DScene.ModelSource.allCases, url: { _ in nil }) == nil)
}

/// 깜빡임·졸기 감은 눈의 전제("얼굴 재질 = 큰 CGImage 디퓨즈")가 기본 경로(.scn)에서 실제로 성립하는지 — 엔진이 얼굴을
/// 찾았다면 졸기 진입이 디퓨즈를 감은 눈으로 바꾸고, 깨면 원복한다. .scn 의 `Data` 디퓨즈를 CGImage 로 정규화하지 않으면
/// 엔진은 얼굴을 못 찾고 디퓨즈는 그대로 남는다(아무 에러 없이 감은 눈만 사라지는 결함).
///
/// 두 경로를 다 본다: 헤드리스 attach(view 없음)는 CGImage 를 직접 갈아끼우고, Metal 디바이스가 있는 뷰로 attach 하면
/// (β1) 뜬 눈/감은 눈을 MTLTexture 로 한 번 올려 두고 그 객체를 대입한다 — 어느 쪽이든 **얼굴을 찾았어야** 일어난다.
@MainActor
@Test
func sleepEyesStillWorkOnThePrebakedPath() throws {
    #expect(CheckCharacter3DScene.loadModelScene(order: CheckCharacter3DScene.ModelSource.allCases)?.source == .prebaked)

    // ① 헤드리스(view 없음): CGImage 디퓨즈가 감은 눈 CGImage 로 바뀌고 원복된다.
    do {
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let wrapper = try #require(wrapperNode(in: scene))
        let face = try #require(v0238FaceMaterial(in: scene), "얼굴(큰 CGImage 디퓨즈) 재질을 못 찾았다 — .scn 디퓨즈가 CGImage 로 정규화되지 않았다")
        let awake = face.diffuse.contents as! CGImage
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_200) })
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
        #expect(engine.request(.drowsy))
        #expect(engine.state == .sleeping)
        let asleep = try #require(face.diffuse.contents)
        #expect(CFGetTypeID(asleep as CFTypeRef) == CGImage.typeID)
        let swappedToClosed = (asleep as AnyObject) !== (awake as AnyObject)
        #expect(swappedToClosed, "졸기에 들어갔는데 얼굴 디퓨즈가 그대로다 — 엔진이 얼굴을 못 찾았다")
        #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)?.isHidden == false)
        engine.stopSleeping()
        let restoredToAwake = (face.diffuse.contents as AnyObject) === (awake as AnyObject)
        #expect(restoredToAwake, "깼는데 뜬 눈 디퓨즈로 원복되지 않았다")
        #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)?.isHidden == true)
    }

    // ② Metal 디바이스가 있는 뷰로 attach(프로덕션 경로): 얼굴을 찾아 GPU 텍스처 쌍을 만들고, 졸기/기상이 그 둘을 오간다.
    do {
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let wrapper = try #require(wrapperNode(in: scene))
        let face = try #require(v0238FaceMaterial(in: scene))
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_300) })
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: SCNView())
        #expect(engine.hasFaceTextures, "Metal 뷰로 attach 했는데 얼굴 텍스처 쌍이 없다 — 얼굴 재질을 못 찾았다")
        let awake = try #require(face.diffuse.contents) as AnyObject
        #expect(engine.request(.drowsy))
        let asleep = try #require(face.diffuse.contents) as AnyObject
        let swappedToClosed = asleep !== awake
        #expect(swappedToClosed, "졸기에 들어갔는데 얼굴 디퓨즈가 그대로다")
        engine.stopSleeping()
        let restored = try #require(face.diffuse.contents) as AnyObject
        let restoredToAwake = restored === awake
        #expect(restoredToAwake, "깼는데 뜬 눈 텍스처로 원복되지 않았다")
    }
}

@MainActor
@Test
func bakedTextureNormalizesEncodedDataToCGImageWithoutResampling() throws {
    // .scn 아카이브가 돌려주는 형태(512² PNG Data)는 축소 없이 CGImage 로만 정규화된다.
    let scn = try #require(CheckCharacter3DScene.loadModelScene(from: .prebaked))
    let raw = try #require(v0238Materials(in: scn).first?.diffuse.contents)
    #expect(raw is Data, "프리베이크 디퓨즈가 Data 가 아니면 이 테스트의 전제가 바뀐 것이다(\(type(of: raw)))")
    let decoded = try #require(CheckCharacter3DScene.decodedTexture(raw))
    #expect(max(decoded.width, decoded.height) <= 512, "프리베이크 텍스처가 512 를 넘는다 — 리샘플 없이 실렸다")
    let baked = try #require(CheckCharacter3DScene.downscaledTexture(raw), "Data 디퓨즈가 CGImage 로 정규화되지 않았다")
    #expect(baked.width == decoded.width && baked.height == decoded.height, "이미 ≤512 인 텍스처를 또 리샘플했다")
    // 이미 CGImage 이고 충분히 작으면 교체하지 않는다(무손실 no-op).
    #expect(CheckCharacter3DScene.downscaledTexture(baked) == nil)
    // 알 수 없는 타입/쓰레기 바이트는 nil(교체하지 않음).
    #expect(CheckCharacter3DScene.downscaledTexture(NSColor.red) == nil)
    #expect(CheckCharacter3DScene.downscaledTexture(Data([0, 1, 2, 3])) == nil)
}

// MARK: - M3 (e) .scn 경로는 USD 워커 스레드를 만들지 않는다

@MainActor
@Test
func prebakedLoadAddsNoThreadsInProcess() throws {
    // 같은 프로세스 안의 델타. (USD 풀이 다른 테스트로 이미 떠 있어도 .scn 로드가 스레드를 더 만들지 않는다는 사실은 그대로 성립한다.
    // 풀이 **아예 안 뜬다**는 강한 주장은 아래 별도 프로세스 프로브가 한다.)
    _ = SCNScene() // SceneKit 자체 초기화는 기준선에 넣는다.
    let before = v0238ThreadCount()
    #expect(before > 0)
    let scene = try #require(CheckCharacter3DScene.loadModelScene(from: .prebaked))
    CheckCharacter3DScene.applyUnlitMaterials(to: scene.rootNode)
    let after = v0238ThreadCount()
    #expect(after - before <= 2, ".scn 로드가 스레드를 \(after - before)개 만들었다(USD 워커 풀은 +11~14)")
}

/// 별도 프로세스에서 .scn 만 먼저 로드했을 때 스레드가 늘지 않고, 대조로 usdz 를 이어 로드하면 USD 워커 풀(+11~14)이
/// 뜨는지 — 이 프로세스에서는 다른 테스트가 usdz 를 먼저 건드릴 수 있어 순서에 독립인 증명은 새 프로세스뿐이다.
/// swift 인터프리터(`xcrun swift`)로 작은 프로브를 돌린다(같은 머신 ~5~10초).
@Test
func prebakedLoadSpawnsNoUSDThreadPoolInAFreshProcess() throws {
    let scn = try #require(CheckCharacter3DScene.modelURL(for: .prebaked))
    let usdz = try #require(CheckCharacter3DScene.modelURL(for: .usdz))
    let probe = """
    import SceneKit
    import Darwin
    func threadCount() -> Int {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS else { return -1 }
        if let list { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(count) * vm_size_t(MemoryLayout<thread_t>.size)) }
        return Int(count)
    }
    _ = SCNScene()
    let base = threadCount()
    let scn = try! SCNScene(url: URL(fileURLWithPath: CommandLine.arguments[1]), options: nil)
    var geos = 0
    scn.rootNode.enumerateHierarchy { n, _ in if n.geometry != nil { geos += 1 } }
    let afterSCN = threadCount()
    _ = try! SCNScene(url: URL(fileURLWithPath: CommandLine.arguments[2]), options: nil)
    let afterUSDZ = threadCount()
    print("geos=\\(geos) base=\\(base) scn_delta=\\(afterSCN - base) usdz_delta=\\(afterUSDZ - afterSCN)")
    """
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("v0238-thread-probe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("probe.swift")
    try probe.write(to: script, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swift", script.path, scn.path, usdz.path]
    // 테스트 러너의 DYLD_* 주입이 인터프리터에 새지 않게 걷어낸다.
    process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
    let stdout = Pipe(), stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let out = String(decoding: outData, as: UTF8.self)
    let err = String(decoding: errData, as: UTF8.self)
    #expect(process.terminationStatus == 0, "프로브 실패(exit \(process.terminationStatus)):\n\(err)")

    func value(_ key: String) -> Int? {
        out.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .first { $0.hasPrefix(key + "=") }
            .flatMap { Int($0.dropFirst(key.count + 1)) }
    }
    let geos = try #require(value("geos"), "프로브 출력 해석 실패: \(out)")
    let scnDelta = try #require(value("scn_delta"))
    let usdzDelta = try #require(value("usdz_delta"))
    #expect(geos >= 1)
    #expect(scnDelta <= 1, ".scn 로드가 새 프로세스에서 스레드를 \(scnDelta)개 만들었다")
    #expect(usdzDelta >= 6, "대조군(usdz)이 USD 워커 풀을 만들지 않았다(\(usdzDelta)) — 계측 감도가 죽었다")
    print("[v0238] thread probe: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
}

// MARK: - [부수] 첫 표시 지연 계측(로드 시간 전후) — 단언은 하지 않고 수치만 남긴다

@MainActor
@Test
func measureModelLoadTimesForBothSources() throws {
    func best(_ source: CheckCharacter3DScene.ModelSource) throws -> Double {
        var bestMs = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let scene = try #require(CheckCharacter3DScene.loadModelScene(from: source))
            CheckCharacter3DScene.applyUnlitMaterials(to: scene.rootNode)
            bestMs = min(bestMs, (CFAbsoluteTimeGetCurrent() - t0) * 1_000)
        }
        return bestMs
    }
    let usdzMs = try best(.usdz)
    let scnMs = try best(.prebaked)
    let t0 = CFAbsoluteTimeGetCurrent()
    _ = try #require(CheckCharacter3DScene.makeScene())
    let makeSceneMs = (CFAbsoluteTimeGetCurrent() - t0) * 1_000
    print(String(format: "[v0238] load+bake best-of-3: usdz %.1fms · scn %.1fms · makeScene(default) %.1fms", usdzMs, scnMs, makeSceneMs))
    #expect(scnMs > 0 && usdzMs > 0)
}
