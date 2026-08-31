import AppKit
import Metal
import SceneKit
import Testing
@testable import check

// MARK: - v0.2.38 "가벼워지기" β1 — 유휴 6fps · 보이지 않을 때만 렌더 정지 · 깜빡임 GPU 텍스처
//
// 계측으로 확정된 사실: 3D 캐릭터 상시 렌더가 유휴 CPU 의 ≈1.5%p 와 GPU 메모리 ≈100MB 를 차지했고,
// 깜빡임마다 SceneKit 이 CGImage→GPU 재변환을 했으며, 화면이 꺼지거나 잠긴 뒤에도 렌더가 돌았다.
// 제품 결정: 캐릭터는 근무 중 항상 살아 있어야 한다 — 부재로는 멈추지 않고 **보이지 않을 때만** 멈춘다.

// MARK: 테스트 보조

/// 테스트별 고정 이름의 격리 defaults(UUID 스위트는 실행마다 빈 plist 를 영구히 쌓는다 — V0236NudgeTests 규약).
private final class V0238Scratch {
    let suiteName: String
    let defaults: UserDefaults

    init(_ test: String) {
        suiteName = "check-v0238-overlay.\(test.replacingOccurrences(of: "()", with: ""))"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}

/// 콘솔 세션 판정 주입(잠금 아님 + 온콘솔). 테스트가 값을 바꾸고 호출 횟수를 센다.
@MainActor
private final class V0238ConsoleProbe {
    var usable = true
    private(set) var calls = 0
    func ask() -> Bool { calls += 1; return usable }
}

/// 깜빡임 스케줄러의 수면을 쥐는 게이트. 루프는 `wait()` 에 서고, 테스트가 `releaseOne()` 으로 tick 하나를 깨운다.
/// `sleepCalls` 로 "루프가 다시 잠들었다"(= 직전 tick 이 끝까지 돌았다)를 안다.
@MainActor
private final class V0238TickGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var sleepCalls = 0

    func wait() async {
        sleepCalls += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseOne() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

/// 실제 스토어 + 실제 컨트롤러. 워크스페이스/배포 노티 센터를 **사적인 인스턴스**로 주입해, 테스트가 시스템 노티와
/// 같은 이름으로 게시하면 컨트롤러의 옵저버가 그것을 받는다(전역 센터 오염 없음).
@MainActor
private final class V0238Harness {
    let scratch: V0238Scratch
    let store: WorkTimerStore
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let probe = V0238ConsoleProbe()
    let controller: CheckOverlayController

    init(_ test: String) {
        scratch = V0238Scratch(test)
        store = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
            defaults: scratch.defaults,
            workspaceNotifications: nil
        )
        let probe = self.probe
        controller = CheckOverlayController(
            store: store,
            notificationCenter: NotificationCenter(),
            defaults: scratch.defaults,
            workspaceNotifications: workspace,
            distributedNotifications: distributed,
            nudgeSessionUsable: { probe.ask() }
        )
    }

    var engine: ReactionEngine { controller.engine }

    func screensSleep() { workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
    func screensWake() { workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil) }
    func sessionResign() { workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil) }
    func sessionBecome() { workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil) }
    func lock() { distributed.post(name: CheckOverlayController.screenLockedNotification, object: nil) }
    func unlock() { distributed.post(name: CheckOverlayController.screenUnlockedNotification, object: nil) }

    func tearDown() {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
}

/// 씬을 만들고 엔진을 붙인다. `view` 가 있으면 GPU 텍스처 경로, nil 이면 CGImage 폴백 경로다.
/// ★ 호출자는 돌려받은 씬을 테스트 끝까지 **살려 둬야 한다**(withExtendedLifetime). 엔진은 노드·재질을 weak 로만
///   잡고 뷰에 씬을 얹지도 않으므로, 버리면 얼굴 재질이 즉시 죽어 디퓨즈 교체가 조용히 no-op 이 된다.
@MainActor
private func attachEngine(
    _ engine: ReactionEngine, view: SCNView?
) throws -> (scene: SCNScene, material: SCNMaterial) {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    // 얼굴 재질은 attach **전에** 찾는다 — attach 뒤에는 디퓨즈가 MTLTexture 로 바뀌어 CGImage 기준 탐색이 못 찾는다.
    let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
    engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
    return (scene, material)
}

/// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다(상한 있음). 이 스위트는 메인 액터가 통째로 수십 초
/// 밀리는 일이 있어(CheckOverlayWindow.ultraSleep 주석의 84초 실측 — 병렬 테스트의 USDZ 로드·감은 눈 인페인트가
/// 동기로 메인을 잡는다) 고정 sleep 한 번으로 판정하면 제품이 아니라 그날의 대기열을 시험하게 된다.
/// 상한도 **벽시계가 아니라 폴링 횟수**로 둔다: 내 20ms 타이머와 깜빡임의 120ms 타이머는 같은 혼잡한 대기열을
/// 기다리므로, 횟수 상한은 혼잡에 비례해 늘어나고 한산할 때는 최대 60초(3000×20ms)다.
@MainActor
private func waitUntil(maxPolls: Int = 3000, _ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<maxPolls {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

private func isCGImage(_ contents: Any?) -> Bool {
    guard let contents else { return false }
    return CFGetTypeID(contents as CFTypeRef) == CGImage.typeID
}

// MARK: - [Q3] 유휴 6fps + 깜빡임 승격·복귀 계약

@MainActor
@Test
func idleFPSIsSixAndBlinkPromotesThenRestores() async throws {
    // 살아있음 우선: 8 → 6. 4 는 부유(1.8s 왕복)가 끊겨 보일 수 있어 여기서 멈춘다.
    #expect(ReactionEngine.idleFPS == 6)
    #expect(ReactionEngine.activeFPS == 30)

    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_000_000) })
    let view = SCNView()
    let attached = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(attached) {} }
    // attach(idle)가 유휴값을 뷰에 박는다.
    #expect(view.preferredFramesPerSecond == 6)

    // 깜빡임: 0.12초는 6fps 로는 한 프레임도 안 잡히므로 그 순간만 30 으로 올렸다가 곧바로 되돌린다.
    // (blink 는 본문을 태스크로 미루므로 승격도 복귀도 폴링으로 본다 — 눈 감김 창은 0.12초라 20ms 폴링이면 잡힌다.)
    engine.renderActive = true
    let swapsBefore = engine.faceDiffuseTextureAssignments + engine.faceDiffuseCGImageAssignments
    engine.blink()
    let promoted = await waitUntil { view.preferredFramesPerSecond == ReactionEngine.activeFPS }
    #expect(promoted, "깜빡임이 FPS 를 30 으로 올리지 않았다: \(view.preferredFramesPerSecond)")
    let restored = await waitUntil {
        view.preferredFramesPerSecond == ReactionEngine.idleFPS
            && engine.faceDiffuseTextureAssignments + engine.faceDiffuseCGImageAssignments == swapsBefore + 2
    }
    #expect(restored, "깜빡임 뒤 FPS 가 유휴(6)로 돌아오지 않았다: \(view.preferredFramesPerSecond)")
    #expect(engine.state == .idle)
}

@MainActor
@Test
func blinkStaysQuietWhileRenderIsSuspended() async throws {
    // 아무도 못 보는 동안(화면 슬립·잠금) 깜빡임은 FPS 도 텍스처도 건드리지 않는다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_000_100) })
    let view = SCNView()
    let attached = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(attached) {} }
    engine.renderActive = true
    engine.renderSuspended = true
    let before = engine.faceDiffuseTextureAssignments
    engine.blink()
    // 물러났다면 태스크 자체가 없다 — 한 박자 기다려도 아무 변화가 없어야 한다.
    try? await Task.sleep(for: .milliseconds(250))
    #expect(view.preferredFramesPerSecond == ReactionEngine.idleFPS)
    #expect(engine.faceDiffuseTextureAssignments == before)
    #expect(engine.faceDiffuseCGImageAssignments == 0)

    // 재개되면 다시 깜빡인다(정지가 깜빡임을 영구히 죽이지 않는다).
    engine.renderSuspended = false
    engine.blink()
    let blinked = await waitUntil { engine.faceDiffuseTextureAssignments == before + 2 }
    #expect(blinked)
}

// MARK: - [Q4][M6] renderSuspended — 사유별 상승, 전부 해제돼야 하강, 깨움 즉시 재개

@MainActor
@Test
func renderSuspendedRisesForEachReasonAlone() {
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    #expect(h.engine.renderSuspended == false)
    #expect(h.controller.renderSuspendReasons.isEmpty)

    // 화면 슬립 ↔ 깨움.
    h.screensSleep()
    #expect(h.engine.renderSuspended)
    #expect(h.controller.renderSuspendReasons == [.screensAsleep])
    h.screensWake()
    #expect(h.engine.renderSuspended == false)
    #expect(h.controller.renderSuspendReasons.isEmpty)

    // 잠금 ↔ 해제(비공개 배포 노티).
    h.lock()
    #expect(h.engine.renderSuspended)
    #expect(h.controller.renderSuspendReasons == [.screenLocked])
    h.unlock()
    #expect(h.engine.renderSuspended == false)

    // 빠른 사용자 전환.
    h.sessionResign()
    #expect(h.engine.renderSuspended)
    #expect(h.controller.renderSuspendReasons == [.sessionInactive])
    h.sessionBecome()
    #expect(h.engine.renderSuspended == false)
}

@MainActor
@Test
func renderSuspendedFallsOnlyWhenEveryReasonIsCleared() {
    // 뚜껑을 닫으면 슬립과 잠금이 겹쳐 온다. 먼저 풀리는 쪽(깨움 — 비밀번호 화면)이 재개시키면 안 된다.
    let h = V0238Harness(#function)
    defer { h.tearDown() }

    h.screensSleep()
    h.lock()
    h.sessionResign()
    #expect(h.engine.renderSuspended)
    #expect(h.controller.renderSuspendReasons == [.screensAsleep, .screenLocked, .sessionInactive])

    h.screensWake()
    #expect(h.engine.renderSuspended, "잠금·세션 사유가 남았는데 깨움만으로 재개했다(단일 Bool 훼손)")
    #expect(h.controller.renderSuspendReasons == [.screenLocked, .sessionInactive])

    h.unlock()
    #expect(h.engine.renderSuspended, "세션 비활성 사유가 남았는데 잠금 해제만으로 재개했다")

    h.sessionBecome()
    #expect(h.engine.renderSuspended == false)
    #expect(h.controller.renderSuspendReasons.isEmpty)

    // 같은 사유의 중복 게시는 멱등이다(잠금 노티가 두 번 와도 해제 한 번이면 풀린다).
    h.lock()
    h.lock()
    h.unlock()
    #expect(h.engine.renderSuspended == false)
}

@MainActor
@Test
func wakeResumesImmediatelyWithoutTouchingVisibilityIntent() {
    // 정지/재개는 표시 의도와 직교한다: 근무 중(표시)에 화면이 꺼져도 shouldBeVisible·renderActive 는 그대로고,
    // 깨어나면 **게시 직후 동기적으로** renderSuspended 만 내려간다(런루프 한 턴도 기다리지 않는다).
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    h.controller.updateWorking(true)
    defer { h.controller.updateWorking(false) }
    #expect(h.controller.shouldBeVisible)
    #expect(h.engine.renderActive)

    h.screensSleep()
    #expect(h.engine.renderSuspended)
    #expect(h.controller.shouldBeVisible, "정지가 표시 의도를 건드렸다")
    #expect(h.engine.renderActive, "정지가 renderActive 를 내렸다 — 재개 시 되살릴 것이 둘이 된다")
    #expect(h.controller.panel.isVisible)

    h.screensWake()
    #expect(h.engine.renderSuspended == false)
    #expect(h.controller.shouldBeVisible)
    #expect(h.engine.renderActive)

    // 반대 방향도 직교: 근무 종료(표시 의도 하강)는 정지 사유를 건드리지 않는다 — 잠긴 채 근무가 끝나고
    // 잠긴 채 다시 시작해도 여전히 정지 상태여야 한다.
    h.lock()
    h.controller.updateWorking(false)
    #expect(h.engine.renderSuspended)
    h.controller.updateWorking(true)
    #expect(h.engine.renderSuspended)
    h.unlock()
    #expect(h.engine.renderSuspended == false)
}

@MainActor
@Test
func missingDistributedCenterNeverSuspendsForLock() {
    // 비공개 이름이라 계약이 없다 — 출처가 없으면(nil) 잠금 사유는 영영 오르지 않고, 다른 사유는 그대로 동작한다.
    let scratch = V0238Scratch(#function)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: scratch.defaults,
        workspaceNotifications: nil
    )
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let workspace = NotificationCenter()
    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        defaults: scratch.defaults,
        workspaceNotifications: workspace,
        distributedNotifications: nil,
        nudgeSessionUsable: { true }
    )
    DistributedNotificationCenter.default().post(name: CheckOverlayController.screenLockedNotification, object: nil)
    #expect(controller.engine.renderSuspended == false)
    workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    #expect(controller.engine.renderSuspended)
    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    #expect(controller.engine.renderSuspended == false)
}

// MARK: - [M5] 깜빡임 텍스처 — GPU 텍스처 포인터 대입, CGImage 재변환 0회

@MainActor
@Test
func blinkSwapsMetalTexturesWithoutAnyCGImageAssignment() async throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return } // Metal 없는 환경은 폴백 테스트가 담당.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_000_200) })
    let view = SCNView()
    let attached = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(attached) {} }
    let material = attached.material

    // attach 가 뜬 눈/감은 눈 텍스처를 준비하고 뜬 눈 텍스처를 곧바로 재질에 얹는다 — 첫 프레임부터 CGImage 변환이 없다.
    #expect(engine.hasFaceTextures)
    #expect(engine.faceDiffuseCGImageAssignments == 0)
    let awakeTexture = try #require(material.diffuse.contents as? any MTLTexture)
    #expect(awakeTexture.pixelFormat == .rgba8Unorm_srgb || awakeTexture.pixelFormat == .bgra8Unorm_srgb,
            "unlit 재질에서 색이 같으려면 sRGB 포맷이어야 한다: \(awakeTexture.pixelFormat.rawValue)")
    #expect(awakeTexture.mipmapLevelCount > 1, "SceneKit 의 CGImage 경로처럼 밉맵이 있어야 축소 시 같은 그림이다")

    engine.renderActive = true
    let textureAssignmentsBefore = engine.faceDiffuseTextureAssignments
    engine.blink()
    // 감은 눈: 다른 MTLTexture 객체로 바뀌고(blink 본문은 태스크라 폴링), CGImage 는 한 번도 대입되지 않는다.
    let closedNow = await waitUntil {
        engine.faceDiffuseTextureAssignments == textureAssignmentsBefore + 1
    }
    #expect(closedNow, "깜빡임이 감은 눈 텍스처를 대입하지 않았다")
    let closed = try #require(material.diffuse.contents as? any MTLTexture)
    #expect(closed !== awakeTexture)
    #expect(engine.faceDiffuseCGImageAssignments == 0)

    // 복귀: 같은 뜬 눈 텍스처 객체로 돌아온다(새로 만들지 않는다).
    let restored = await waitUntil {
        (material.diffuse.contents as? any MTLTexture) === awakeTexture
    }
    #expect(restored, "깜빡임 뒤 뜬 눈 텍스처(같은 객체)로 돌아오지 않았다")
    #expect(engine.faceDiffuseTextureAssignments == textureAssignmentsBefore + 2)
    #expect(engine.faceDiffuseCGImageAssignments == 0)

    // 졸기 진입/이탈도 같은 경로다.
    engine.request(.drowsy)
    #expect((material.diffuse.contents as? any MTLTexture) === closed)
    engine.request(.wake)
    #expect((material.diffuse.contents as? any MTLTexture) === awakeTexture)
    #expect(engine.faceDiffuseCGImageAssignments == 0)
}

@MainActor
@Test
func headlessAttachKeepsCGImageFallback() async throws {
    // 뷰가 없으면(헤드리스) 텍스처를 만들지 않고 예전 CGImage 경로 그대로 — 기존 헤드리스 테스트가 디퓨즈에서
    // 픽셀을 읽어 검증하는 계약(CheckSleepEyesTests.reactionEngineTogglesClosedEyesOnSleepAndWake)을 지킨다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_000_300) })
    let attached = try attachEngine(engine, view: nil)
    defer { withExtendedLifetime(attached) {} }
    let material = attached.material
    #expect(engine.hasFaceTextures == false)
    #expect(isCGImage(material.diffuse.contents))

    engine.renderActive = true
    engine.blink()
    let closed = await waitUntil { engine.faceDiffuseCGImageAssignments == 1 }
    #expect(closed)
    #expect(engine.faceDiffuseTextureAssignments == 0)
    #expect(isCGImage(material.diffuse.contents))
    let restored = await waitUntil { engine.faceDiffuseCGImageAssignments == 2 }
    #expect(restored)
    #expect(engine.faceDiffuseTextureAssignments == 0)
    #expect(isCGImage(material.diffuse.contents))
}

@MainActor
@Test
func reattachWithSameDeviceReusesTexturesAndDifferentSceneRebuilds() throws {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_000_400) })
    let view = SCNView()
    let (scene, material) = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(scene) {} }
    let first = try #require(material.diffuse.contents as? any MTLTexture)

    // 같은 씬·같은 디바이스 재-attach: 텍스처를 다시 만들지 않는다(같은 객체가 그대로).
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
    #expect((material.diffuse.contents as? any MTLTexture) === first)

    // 다른 씬으로 교체: 새 얼굴 재질에서 다시 캡처하고 새 텍스처를 만든다(죽은 참조 고착 없음).
    let attached2 = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(attached2) {} }
    let second = try #require(attached2.material.diffuse.contents as? any MTLTexture)
    #expect(second !== first)
    #expect(engine.hasFaceTextures)
}

// MARK: - [M5] 렌더 동일성 — MTLTexture 디퓨즈와 CGImage 디퓨즈의 픽셀 diff ≤ 1%

/// SCNRenderer 스냅샷을 RGBA8 바이트로.
@MainActor
private func renderRGBA(_ renderer: SCNRenderer, size: CGSize) throws -> (pixels: [UInt8], width: Int, height: Int) {
    let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (px, w, h)
}

/// 한 채널이라도 `tolerance` 를 넘게 다른 픽셀의 비율.
private func differingFraction(_ a: [UInt8], _ b: [UInt8], tolerance: Int = 8) -> Double {
    precondition(a.count == b.count && a.count % 4 == 0)
    let total = a.count / 4
    var differing = 0
    for i in 0..<total {
        let j = i * 4
        if abs(Int(a[j]) - Int(b[j])) > tolerance
            || abs(Int(a[j + 1]) - Int(b[j + 1])) > tolerance
            || abs(Int(a[j + 2]) - Int(b[j + 2])) > tolerance
            || abs(Int(a[j + 3]) - Int(b[j + 3])) > tolerance {
            differing += 1
        }
    }
    return Double(differing) / Double(max(1, total))
}

@MainActor
@Test
func metalFaceTexturesRenderIdenticallyToCGImageDiffuse() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
    let awakeCG = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
    let sleepCG = try #require(CheckCharacter3DScene.makeClosedEyesImage(
        faceImage: awakeCG, geometry: SleepEyeExplore.faceGeometry(in: scene)))

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.autoenablesDefaultLighting = false
    let size = CGSize(width: 280, height: 340)

    material.diffuse.contents = awakeCG
    let awakeFromCG = try renderRGBA(renderer, size: size)
    material.diffuse.contents = try #require(ReactionEngine.makeFaceTexture(awakeCG, device: device))
    let awakeFromTexture = try renderRGBA(renderer, size: size)
    material.diffuse.contents = sleepCG
    let sleepFromCG = try renderRGBA(renderer, size: size)
    material.diffuse.contents = try #require(ReactionEngine.makeFaceTexture(sleepCG, device: device))
    let sleepFromTexture = try renderRGBA(renderer, size: size)

    #expect(awakeFromCG.width == awakeFromTexture.width && awakeFromCG.height == awakeFromTexture.height)
    let awakeDiff = differingFraction(awakeFromCG.pixels, awakeFromTexture.pixels)
    let sleepDiff = differingFraction(sleepFromCG.pixels, sleepFromTexture.pixels)
    // 대조군: 뜬 눈과 감은 눈은 실제로 달라야 한다 — 이게 0 이면 위 두 판정은 아무것도 재지 않은 것이다.
    let awakeVsSleep = differingFraction(awakeFromCG.pixels, sleepFromCG.pixels)
    print(String(format: "v0238 face texture diff: awake=%.4f%% sleep=%.4f%% (awake vs sleep=%.3f%%)",
                 awakeDiff * 100, sleepDiff * 100, awakeVsSleep * 100))
    #expect(awakeDiff <= 0.01, "뜬 눈: MTLTexture 렌더가 CGImage 렌더와 \(awakeDiff * 100)% 다르다(색공간/뒤집힘/밉맵)")
    #expect(sleepDiff <= 0.01, "감은 눈: MTLTexture 렌더가 CGImage 렌더와 \(sleepDiff * 100)% 다르다")
    #expect(awakeVsSleep > 0.0005, "대조군 실패: 뜬 눈과 감은 눈 렌더가 같다 — 비교가 공허하다")
}

// MARK: - [M6 후속] 해제 노티 유실 안전밸브 — 잠금/세션 사유는 콘솔 세션 판정으로 걷어낸다(한 방향)

@MainActor
@Test
func staleLockAndSessionReasonsAreReleasedByTheConsoleProbe() {
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    h.probe.usable = false
    h.lock()
    h.sessionResign()
    #expect(h.engine.renderSuspended)

    // 판정이 '잠금'이면 그대로 둔다.
    #expect(h.controller.reconcileStaleRenderSuspension() == false)
    #expect(h.engine.renderSuspended)
    #expect(h.controller.renderSuspendReasons == [.screenLocked, .sessionInactive])

    // 해제 노티 없이 판정만 '사용 가능'이 되면 두 사유 다 걷어낸다.
    h.probe.usable = true
    #expect(h.controller.reconcileStaleRenderSuspension())
    #expect(h.engine.renderSuspended == false)
    #expect(h.controller.renderSuspendReasons.isEmpty)
}

@MainActor
@Test
func consoleProbeNeverTouchesScreensAsleepAndIsNotAskedWithoutReleasableReasons() {
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    h.probe.usable = true

    // 사유가 없으면 판정을 묻지도 않는다(평시 비용 0). 반대 방향(판정은 잠금인데 사유 없음)도 세우지 않는다.
    h.probe.usable = false
    #expect(h.controller.reconcileStaleRenderSuspension() == false)
    #expect(h.probe.calls == 0)
    #expect(h.engine.renderSuspended == false)

    // 디스플레이 슬립은 밸브 대상이 아니다 — 묻지도, 걷어내지도 않는다.
    h.probe.usable = true
    h.screensSleep()
    #expect(h.controller.reconcileStaleRenderSuspension() == false)
    #expect(h.probe.calls == 0)
    #expect(h.engine.renderSuspended)

    // 슬립 + 잠금이 겹친 채 해제 노티가 유실되면 잠금만 걷어내고 슬립은 남는다 → 여전히 정지.
    h.lock()
    #expect(h.controller.reconcileStaleRenderSuspension())
    #expect(h.probe.calls == 1)
    #expect(h.controller.renderSuspendReasons == [.screensAsleep])
    #expect(h.engine.renderSuspended)
    h.screensWake()
    #expect(h.engine.renderSuspended == false)
}

@MainActor
@Test
func lostUnlockNotificationResumesOnTheNextBlinkTick() async {
    // 잠금 노티는 왔는데 해제 노티가 안 왔다. 표시 중 도는 깜빡임 tick 이 콘솔 세션 판정으로 사유를 걷어내
    // 최대 한 주기 뒤 재개된다(판정이 잠금이면 유지). 수면을 게이트로 쥐어 tick 을 결정적으로 깨운다.
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    let gate = V0238TickGate()
    h.controller.blinkSleep = { _ in await gate.wait() }
    // 스토어를 실제로 근무 중으로 둔다 — 첫 await 에서 런루프가 돌면 패널의 SwiftUI 루트가
    // `.onChange(of: store.snapshot.isWorking, initial: true)` 로 updateWorking 을 되부르는데, 스토어가 비근무면
    // 그 되부름이 방금 켠 표시를 끄고 깜빡임 루프를 첫 tick 전에 취소한다.
    h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    h.controller.updateWorking(true)
    defer {
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        h.controller.updateWorking(false)
        gate.releaseAll() // 서 있던 루프를 깨워 취소를 보게 한다.
    }
    let parked = await waitUntil { gate.sleepCalls == 1 }
    #expect(parked, "깜빡임 루프가 게이트에 서지 않았다")

    h.lock()
    #expect(h.engine.renderSuspended)

    // 판정: 아직 잠금 → tick 이 돌아도 유지.
    h.probe.usable = false
    gate.releaseOne()
    let tickedOnce = await waitUntil { gate.sleepCalls == 2 }
    #expect(tickedOnce)
    #expect(h.engine.renderSuspended, "판정이 잠금인데 tick 이 사유를 걷어냈다")

    // 판정: 사용 가능(해제 노티는 끝내 안 옴) → 다음 tick 에 재개.
    h.probe.usable = true
    gate.releaseOne()
    let tickedTwice = await waitUntil { gate.sleepCalls == 3 }
    #expect(tickedTwice)
    #expect(h.engine.renderSuspended == false, "해제 노티가 유실됐는데 다음 tick 에 재개되지 않았다")
    #expect(h.controller.renderSuspendReasons.isEmpty)
    #expect(h.controller.shouldBeVisible)
}

// MARK: - [β2 실측 후속] 정지 중엔 졸기 진입·💤 스폰·모션/파티클을 걸지 않는다 — 파티클은 isPaused 를 무시하고 렌더 루프를 깨운다

/// 씬 루트 직계 자식 중 이름이 `name` 인 노드 수(💤 컨테이너·색종이 방출구 등 일시 노드 계수).
@MainActor
private func transientCount(in scene: SCNScene, named name: String) -> Int {
    scene.rootNode.childNodes.filter { $0.name == name }.count
}

@MainActor
@Test
func drowsyEntryIsRefusedWhileRenderIsSuspended() throws {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_100_000) })
    let attached = try attachEngine(engine, view: nil)
    defer { withExtendedLifetime(attached) {}; engine.stopSleeping() }
    let scene = attached.scene
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let leftEye = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)
    )

    engine.renderSuspended = true
    #expect(engine.request(.drowsy) == false, "정지 중 졸기 진입을 수용했다")
    #expect(engine.state == .idle)
    #expect(wrapper.action(forKey: "check.reaction") == nil)
    #expect(leftEye.isHidden)
    #expect(transientCount(in: scene, named: "check.reaction.zzz") == 0)

    // 재개되면 평소대로 잔다.
    engine.renderSuspended = false
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)
    #expect(wrapper.action(forKey: "check.reaction") != nil)
    #expect(!leftEye.isHidden)
}

@MainActor
@Test
func canEnterDrowsyIsFalseWhileSuspendedAtTheController() {
    let h = V0238Harness(#function)
    defer { h.tearDown() }
    h.controller.updateWorking(true)
    defer { h.controller.updateWorking(false) }
    h.engine.cancelActiveReaction() // 등장 폴짝(commuteStart, 0.6s 실시간)을 끊어 idle 로 — 판정은 정지 사유만 본다.
    #expect(h.controller.canEnterDrowsy)
    h.screensSleep()
    #expect(h.controller.canEnterDrowsy == false, "화면이 꺼졌는데 졸기 스케줄러가 진입하려 한다")
    h.screensWake()
    #expect(h.controller.canEnterDrowsy)
}

@MainActor
@Test
func zzzBurstIsSkippedWhileSuspendedAndResumesAfterwards() async throws {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 1_100_100) })
    let attached = try attachEngine(engine, view: nil)
    let gate = V0238TickGate()
    engine.zzzSleep = { _ in await gate.wait() }
    defer {
        withExtendedLifetime(attached) {}
        engine.stopSleeping()   // zzzTask 취소
        gate.releaseAll()       // 서 있던 루프를 깨워 취소를 보게 한다.
    }
    let scene = attached.scene
    let zzz = "check.reaction.zzz"

    // 잠들면 첫 tick 에 💤 한 뭉치가 뜨고 루프는 게이트에 선다.
    #expect(engine.request(.drowsy))
    let firstBurst = await waitUntil { gate.sleepCalls == 1 }
    #expect(firstBurst)
    #expect(transientCount(in: scene, named: zzz) == 1)

    // 정지: 주기가 지나도(tick 이 돌아도) 스폰하지 않는다 — 타이머는 살아서 다시 게이트에 선다.
    engine.renderSuspended = true
    gate.releaseOne()
    let tickedSuspended = await waitUntil { gate.sleepCalls == 2 }
    #expect(tickedSuspended, "정지 중 💤 루프가 죽었다(타이머는 살아 있어야 한다)")
    #expect(transientCount(in: scene, named: zzz) == 1, "정지 중 💤 를 스폰했다 — 파티클이 렌더 루프를 깨운다")
    #expect(engine.state == .sleeping)

    // 재개: 다음 tick 에 다시 스폰한다.
    engine.renderSuspended = false
    gate.releaseOne()
    let tickedResumed = await waitUntil { gate.sleepCalls == 3 }
    #expect(tickedResumed)
    #expect(transientCount(in: scene, named: zzz) == 2)
}

@MainActor
@Test
func reactionsRequestedWhileSuspendedKeepStateButRunNoMotionAndExpiredOnesAreClearedOnResume() throws {
    var now = Date(timeIntervalSince1970: 1_100_200)
    let engine = ReactionEngine(clock: { now })
    let view = SCNView()
    let attached = try attachEngine(engine, view: view)
    defer { withExtendedLifetime(attached) {} }
    let scene = attached.scene
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    engine.renderActive = true

    // 정지 중 요청: 숨김 패널 규약처럼 **수용**(상태·말풍선·우선순위 유지)하되 모션·파티클은 걸지 않는다.
    engine.renderSuspended = true
    #expect(engine.request(.milestone))
    #expect(engine.state == .playing(.milestone))
    #expect(wrapper.action(forKey: "check.reaction") == nil, "정지 중 wrapper 에 모션을 걸었다")
    #expect(transientCount(in: scene, named: "check.reaction.confetti") == 0, "정지 중 색종이 파티클을 방출했다")
    now = now.addingTimeInterval(ReactionKind.milestone.duration + 1)
    #expect(engine.request(.poked(bubbleText: "콕")))
    #expect(engine.greetingText == "콕", "정지 중에도 말풍선은 남아야 한다(보낸 몫은 증발하지 않는다)")
    #expect(wrapper.action(forKey: "check.reaction") == nil)
    now = now.addingTimeInterval(ReactionKind.poked(bubbleText: "콕").duration + 1)
    engine.renderSuspended = false
    #expect(engine.state == .idle)
    #expect(wrapper.action(forKey: "check.reaction") == nil)

    // 정지 **전에** 걸린 모션이 정지 중 만료되면 재개 순간 정리된다(첫 프레임에 뒤늦게 튀지 않게).
    #expect(engine.request(.hit))
    #expect(wrapper.action(forKey: "check.reaction") != nil)
    wrapper.position = SCNVector3(0, 0.2, 0) // 재생 도중의 포즈를 흉내낸다.
    engine.renderSuspended = true
    now = now.addingTimeInterval(ReactionKind.hit.duration + 1)
    engine.renderSuspended = false
    #expect(engine.state == .idle)
    #expect(wrapper.action(forKey: "check.reaction") == nil, "정지 중 만료된 모션이 재개 뒤에도 남아 있다")
    #expect(wrapper.position.y == 0, "재개 정리가 포즈를 identity 로 되돌리지 않았다")
    #expect(view.preferredFramesPerSecond == ReactionEngine.idleFPS)

    // 대조군: 만료 전이면 그대로 이어서 재생한다(정리하지 않는다).
    now = now.addingTimeInterval(ReactionKind.hit.duration + 1) // hit 쿨다운 통과
    #expect(engine.request(.hit))
    engine.renderSuspended = true
    engine.renderSuspended = false
    #expect(engine.state == .playing(.hit))
    #expect(wrapper.action(forKey: "check.reaction") != nil, "만료 전 모션까지 걷어냈다")
}
