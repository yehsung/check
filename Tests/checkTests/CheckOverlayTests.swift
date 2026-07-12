import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check

// MARK: - J1: 오버레이 패널 설정

@MainActor
@Test
func overlayPanelIsConfiguredForClickThroughFloating() {
    let panel = CheckOverlayController.makePanel(size: CheckOverlayController.panelSize)

    // 항상 위(플로팅) + 클릭 통과(방해 금지 핵심).
    #expect(panel.level == .floating)
    #expect(panel.ignoresMouseEvents == true)

    // 투명 배경.
    #expect(panel.isOpaque == false)
    #expect(panel.hasShadow == false)
    #expect(panel.backgroundColor == NSColor.clear)

    // 비활성화되어도 숨지 않고, 플로팅 패널로 동작.
    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.isFloatingPanel == true)

    // 스타일: 테두리 없음 + 비활성 패널(키 입력 훔치지 않음).
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))

    // Space 전환/전체화면 유지 + 창 순환 제외.
    let behavior = panel.collectionBehavior
    #expect(behavior.contains(.canJoinAllSpaces))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.stationary))
    #expect(behavior.contains(.ignoresCycle))
}

@Test
func overlayFrameSitsAtTopRightWithMargin() {
    // 원점이 (100,50)이고 1440x900인 가상 visibleFrame에서 140x170 패널을 여백 24로 우상단에 놓는다.
    let visibleFrame = NSRect(x: 100, y: 50, width: 1_440, height: 900)
    let size = NSSize(width: 140, height: 170)
    let frame = CheckOverlayController.overlayFrame(in: visibleFrame, size: size, margin: 24)

    // 우측 정렬: 오른쪽 끝에서 (패널폭 + 여백)만큼 안쪽.
    #expect(frame.maxX == visibleFrame.maxX - 24)
    #expect(frame.minX == visibleFrame.maxX - size.width - 24)
    // 상단 정렬: visibleFrame 상단(메뉴바 바로 아래)에서 여백만큼 아래(맥 좌표계는 위가 maxY).
    #expect(frame.maxY == visibleFrame.maxY - 24)
    #expect(frame.minY == visibleFrame.maxY - size.height - 24)
    #expect(frame.size == size)
}

// MARK: - J2: 3D 씬 로드·재질

@MainActor
@Test
func aingModelLoadsFromBundleModuleAsScene() throws {
    let scene = try #require(
        CheckCharacter3DScene.loadModelScene(),
        "Bundle.module의 aing.usdz가 SCNScene으로 로드되어야 한다"
    )

    // 지오메트리가 하나 이상 존재해야 한다.
    var geometryCount = 0
    scene.rootNode.enumerateHierarchy { node, _ in
        if node.geometry != nil { geometryCount += 1 }
    }
    #expect(geometryCount >= 1)
}

@MainActor
@Test
func makeSceneAppliesUnlitMaterialsAndCamera() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))

    // 모든 재질이 unlit(.constant)여야 마스코트 원색이 산다(기본 조명이면 허옇게 뜸).
    var materialCount = 0
    scene.rootNode.enumerateHierarchy { node, _ in
        node.geometry?.materials.forEach { material in
            materialCount += 1
            #expect(material.lightingModel == .constant)
        }
    }
    #expect(materialCount >= 1)

    // 프레이밍 카메라가 추가되어야 한다.
    var hasCamera = false
    scene.rootNode.enumerateHierarchy { node, _ in
        if node.camera != nil { hasCamera = true }
    }
    #expect(hasCamera)

    // 배경은 비어 있어야(투명) 한다.
    #expect(scene.background.contents == nil)
}

// MARK: - J2: 근무 시간 표기

@Test
func overlayTimeFormatterFormatsHoursMinutesSeconds() {
    // 1시간 미만: MM:SS (MenuBarStatusFormatter.duration 재사용).
    #expect(CheckOverlayTimeFormatter.text(0) == "00:00")
    #expect(CheckOverlayTimeFormatter.text(65) == "01:05")
    #expect(CheckOverlayTimeFormatter.text(59 * 60 + 59) == "59:59")
    #expect(CheckOverlayTimeFormatter.text(1_800) == MenuBarStatusFormatter.duration(1_800))

    // 1시간 이상: HH:MM:SS (초까지 흐른다 — 메뉴바 HH:MM과 다름).
    #expect(CheckOverlayTimeFormatter.text(3_600) == "01:00:00")
    #expect(CheckOverlayTimeFormatter.text(3_661) == "01:01:01")
    #expect(CheckOverlayTimeFormatter.text(12 * 3_600 + 34 * 60 + 56) == "12:34:56")

    // 음수는 0으로 절단.
    #expect(CheckOverlayTimeFormatter.text(-10) == "00:00")
}

// MARK: - J3: isWorking 토글 시 패널 가시성 전환

@MainActor
@Test
func overlayControllerTogglesVisibilityWithWorking() async {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    // 전역 노티 오염을 막기 위해 격리된 NotificationCenter를 쓴다.
    let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter())

    // 시작 시 숨김 의도.
    #expect(controller.shouldBeVisible == false)

    // 근무 시작 → 표시 의도. 실제 표시(isVisible)는 헤드리스 CI에서 불안정할 수 있어
    // 의도 상태(shouldBeVisible)를 1차로 검증하고, 표시가 됐다면 숨김 전환도 함께 확인한다.
    controller.updateWorking(true)
    #expect(controller.shouldBeVisible == true)

    let becameVisible = controller.panel.isVisible
    controller.updateWorking(false)
    // 숨김 의도는 즉시 뒤집힌다.
    #expect(controller.shouldBeVisible == false)
    if becameVisible {
        // 근무 종료 인사(꾸벅) 후 패널을 내리므로 숨김은 비동기다. 최대 1초 내 반드시 숨겨져야 한다.
        var hidden = false
        for _ in 0..<200 {
            if !controller.panel.isVisible {
                hidden = true
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(hidden)
    }
}

// MARK: - ACD-F1: 근무종료 인사 렌더 중 타이머 라벨 00:00 플래시 방지

@MainActor
@Test
func overlayTimerStaysVisibleDuringFarewellRender() {
    // 재현: 근무 종료 인사(commuteEnd) 0.55초 동안 isWorking 은 이미 false 지만 renderActive 는 true 다.
    // 이때 elapsedSeconds 를 0 으로 떨궈 라벨이 00:00 으로 플래시되던 결함 — renderActive 를 표시 판정에
    // 포함해 실제 오늘 누적을 계속 보여 줘야 한다.
    #expect(CheckOverlayRootView.showsTimer(isWorking: false, isOverlayEnabled: true, renderActive: true))
    // 근무 중에는 당연히 보인다.
    #expect(CheckOverlayRootView.showsTimer(isWorking: true, isOverlayEnabled: true, renderActive: false))
    // 오버레이가 꺼져(숨김) 있으면 renderActive 는 항상 false → 표시하지 않는다(A3 유휴 차단 목표 보존).
    #expect(CheckOverlayRootView.showsTimer(isWorking: false, isOverlayEnabled: false, renderActive: false) == false)
    // 완전 유휴(근무 아님·인사 렌더 아님)엔 표시하지 않아 매초 재평가 낭비를 만들지 않는다.
    #expect(CheckOverlayRootView.showsTimer(isWorking: false, isOverlayEnabled: true, renderActive: false) == false)
}

// MARK: - ACD-F5: attach 재생(지연 생성 래치로 attach 가 request 보다 늦게 실행돼도 소실 없음)

@MainActor
@Test
func attachReplaysPlayingReactionAndSetsActiveFPS() throws {
    // 재현: 지연 생성(래치)으로 attach 가 request(.commuteStart) 보다 늦게 실행된다. attach 시점에 아직
    // 재생 중(만료 전)이면 걸린 리액션 SCNAction 을 노드에 재생하고 FPS 를 활성(30)으로 올려야 한다.
    let now = Date(timeIntervalSince1970: 50_000)
    let engine = ReactionEngine(clock: { now }) // 고정 clock → commuteStart(0.6s) 만료 전 유지.
    #expect(engine.request(.commuteStart))
    #expect(engine.state == .playing(.commuteStart))

    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let root = scene.rootNode
    let wrapper = try #require(
        root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let view = SCNView()

    engine.attach(node: wrapper, sceneRoot: root, view: view)

    // 걸린 리액션이 노드에 재생된다(reactionActionKey="check.reaction" 액션이 걸림).
    #expect(wrapper.action(forKey: "check.reaction") != nil)
    // 재생 중이므로 FPS 를 활성(30)으로 올린다.
    #expect(view.preferredFramesPerSecond == ReactionEngine.activeFPS)
}

@MainActor
@Test
func attachAppliesDrowsyPoseAndIdleFPSWhileSleeping() throws {
    // 재현: sleeping 상태에서 attach 하면 가라앉은(drowsy) 포즈를 노드에 적용하고 FPS 는 유휴(8)로 둔다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 51_000) })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let root = scene.rootNode
    let wrapper = try #require(
        root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let view = SCNView()

    engine.attach(node: wrapper, sceneRoot: root, view: view)

    // 자는 포즈(drowsySink)가 노드에 걸린다.
    #expect(wrapper.action(forKey: "check.reaction") != nil)
    // 졸기는 느린 모션이라 유휴 FPS(8)를 유지한다.
    #expect(view.preferredFramesPerSecond == ReactionEngine.idleFPS)
    #expect(engine.state == .sleeping)

    engine.stopSleeping() // 정리: zzzTask 취소.
}

// MARK: - 시각 검증 스냅샷 덤프 (CHECK_OVERLAY_SNAPSHOT_DIR 지정 시에만 기록)

@MainActor
@Test
func dumpOverlaySnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_OVERLAY_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    // (a) 새 카메라 구도(살짝 내려다보는 각도)의 3D 렌더 — SCNRenderer 오프스크린.
    let scnPNG = try #require(CheckCharacter3DScene.renderSnapshotPNG())
    try scnPNG.write(to: base.appendingPathComponent("overlay-camera.png"))

    // 캐릭터 + 타이머 라벨 합성 목업 — SCN 렌더 이미지를 배경으로 두고 실제 라벨 컴포넌트를 얹는다
    // (SCNView는 AppKit 백킹이라 ImageRenderer가 직접 못 그리므로 렌더 이미지를 이미지로 합성한다).
    let scnImage = try #require(NSImage(data: scnPNG))

    // (b) 분 단위 목업 — 05:07 (MM:SS).
    try writeOverlayMock(seconds: 5 * 60 + 7, background: scnImage,
                         to: base.appendingPathComponent("overlay-minutes.png"))
    // (c) 장시간 목업 — 12:34:56 (HH:MM:SS). 캡슐 안에 잘림 없이 수납되는지 확인.
    try writeOverlayMock(seconds: 12 * 3_600 + 34 * 60 + 56, background: scnImage,
                         to: base.appendingPathComponent("overlay-hours.png"))
}

/// 캐릭터 렌더 이미지를 배경으로 두고 실제 타이머 라벨 컴포넌트를 얹어 PNG로 저장한다(시각 검증용).
@MainActor
private func writeOverlayMock(seconds: Int, background: NSImage, to url: URL) throws {
    let mock = ZStack {
        Image(nsImage: background)
            .resizable()
            .scaledToFit()
        CheckOverlayTimerLabel(text: CheckOverlayTimeFormatter.text(seconds))
            .position(
                x: CheckOverlayController.panelSize.width / 2,
                y: CheckOverlayController.panelSize.height * CheckOverlayCharacterView.timerVerticalFraction
            )
    }
    .frame(width: CheckOverlayController.panelSize.width, height: CheckOverlayController.panelSize.height)

    let renderer = ImageRenderer(content: mock)
    renderer.scale = 3
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: url)
}

// MARK: - Wave7: 리액션 엔진 우선순위/쿨다운

@MainActor
@Test
func reactionEnginePrioritizesHigherAndIgnoresLowerWhilePlaying() {
    var now = Date(timeIntervalSince1970: 1_000)
    let engine = ReactionEngine(clock: { now })

    #expect(engine.state == .idle)

    // 마일스톤(2) 재생 중: 인사(1)·졸기(0)는 무시, hit(3)은 인터럽트.
    #expect(engine.request(.milestone))
    #expect(engine.state == .playing(.milestone))
    #expect(engine.request(.greeting(name: "철수")) == false)
    #expect(engine.request(.drowsy) == false)
    #expect(engine.state == .playing(.milestone))

    #expect(engine.request(.hit))
    #expect(engine.state == .playing(.hit))
    // 동순위(출퇴근=hit=3)는 인터럽트하지 않는다.
    #expect(engine.request(.commuteStart) == false)

    // hit 재생 길이가 지나면 idle 로 복귀한다(clock 기반 만료).
    now = now.addingTimeInterval(0.7)
    #expect(engine.state == .idle)
    // drowsy 는 일회성 재생이 아니라 지속 상태(sleeping)로 진입한다.
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)
}

@MainActor
@Test
func reactionEngineEnforcesHitCooldown() {
    var now = Date(timeIntervalSince1970: 2_000)
    let engine = ReactionEngine(clock: { now })

    #expect(engine.request(.hit))
    // 0.6초 이내 연타는 무시된다.
    now = now.addingTimeInterval(0.5)
    #expect(engine.request(.hit) == false)
    // 0.6초를 넘기면 다시 허용된다.
    now = now.addingTimeInterval(0.2) // 총 0.7초
    #expect(engine.request(.hit))
}

@MainActor
@Test
func reactionEngineReplacesBubbleWhenInterruptedByReactionWithOwnBubble() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 3_000) })
    #expect(engine.request(.greeting(name: "영희")))
    #expect(engine.greetingText == "영희님 출근!")

    // 더 높은 우선순위(hit)가 들어오면 그 리액션이 자기 말풍선("아얏!")으로 교체한다
    // (말풍선은 자체 타이머 소유 — 인터럽트가 강제로 비우지 않고, 새 리액션이 갈아끼운다).
    #expect(engine.request(.hit))
    #expect(engine.greetingText == "아얏!")
}

// MARK: - A6: 근무종료 인사 중 즉시 재시작 시 등장 리액션 씹힘 수정

@MainActor
@Test
func reactionEngineCommuteStartInterruptsCommuteEnd() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 45_000) })

    // 근무종료 인사("수고했어!") 재생 중.
    #expect(engine.request(.commuteEnd))
    #expect(engine.state == .playing(.commuteEnd))
    #expect(engine.greetingText == "수고했어!")

    // A6: 즉시 재시작하면 동순위(3)라도 등장 폴짝이 거부되지 않고 인터럽트 후 수용된다.
    #expect(engine.request(.commuteStart))
    #expect(engine.state == .playing(.commuteStart))
    // 잔류하던 "수고했어!" 말풍선이 "오늘도 화이팅!"으로 교체된다.
    #expect(engine.greetingText == "오늘도 화이팅!")
}

@MainActor
@Test
func reactionEngineCommuteEndDuringCommuteStartStaysRejected() {
    // 반대 방향(commuteStart 중 commuteEnd)은 기존 동순위 거부 규칙을 유지한다(A6 우회는 한 방향만).
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 46_000) })
    #expect(engine.request(.commuteStart))
    #expect(engine.request(.commuteEnd) == false)
    #expect(engine.state == .playing(.commuteStart))
}

// MARK: - Wave7: 마일스톤 1일 1회

@Test
func milestoneTrackerFiresOncePerKoreanDay() {
    let suiteName = "check-milestone-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    var tracker = MilestoneTracker(defaults: defaults)

    let day1 = kstDate(year: 2026, month: 7, day: 11, hour: 10)
    #expect(tracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: day1) == true)
    #expect(tracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: day1) == false)
    // 같은 날 다른 키는 독립적으로 한 번 터진다.
    #expect(tracker.fireIfNeeded(MilestoneTracker.hourFourKey, now: day1) == true)

    // 하루가 지나면 다시 터진다.
    let day2 = kstDate(year: 2026, month: 7, day: 12, hour: 1)
    #expect(tracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: day2) == true)

    // 새 인스턴스(재실행)라도 UserDefaults 기록으로 같은 날은 중복되지 않는다.
    var reopened = MilestoneTracker(defaults: defaults)
    #expect(reopened.fireIfNeeded(MilestoneTracker.hourOneKey, now: day2) == false)
}

// MARK: - Wave7: 팀원 출근 인사 전이 감지

@Test
func greetingDetectorExcludesFirstLoadAndSelfAndAppliesCooldown() {
    var detector = TeammateGreetingDetector()
    let selfID = "00000000-0000-0000-0000-000000000002"
    let t0 = Date(timeIntervalSince1970: 10_000)

    // 첫 로드: 이미 근무 중인 팀원/본인 모두 인사하지 않는다(인사 폭탄 금지).
    let first = detector.detect(
        members: [member("a", .working), member(selfID, .working)],
        selfID: selfID, now: t0
    )
    #expect(first.isEmpty)

    // a 가 offWork 로 바뀐 뒤 working 으로 전이 → 인사.
    _ = detector.detect(members: [member("a", .offWork)], selfID: selfID, now: t0.addingTimeInterval(10))
    let greet1 = detector.detect(members: [member("a", .working)], selfID: selfID, now: t0.addingTimeInterval(20))
    #expect(greet1 == ["a-name"])

    // 10분 이내 재전이는 쿨다운으로 무시.
    _ = detector.detect(members: [member("a", .offWork)], selfID: selfID, now: t0.addingTimeInterval(30))
    let greet2 = detector.detect(members: [member("a", .working)], selfID: selfID, now: t0.addingTimeInterval(40))
    #expect(greet2.isEmpty)

    // 10분이 지나면 다시 인사.
    _ = detector.detect(members: [member("a", .offWork)], selfID: selfID, now: t0.addingTimeInterval(650))
    let greet3 = detector.detect(members: [member("a", .working)], selfID: selfID, now: t0.addingTimeInterval(660))
    #expect(greet3 == ["a-name"])

    // 본인이 offWork→working 으로 바뀌어도 인사하지 않는다.
    _ = detector.detect(members: [member(selfID, .offWork)], selfID: selfID, now: t0.addingTimeInterval(700))
    let greetSelf = detector.detect(members: [member(selfID, .working)], selfID: selfID, now: t0.addingTimeInterval(710))
    #expect(greetSelf.isEmpty)
}

// MARK: - Wave7: 졸기 시간창 판정(시각 주입)

@Test
func drowsyWindowCoversNightHoursOnly() {
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 11, hour: 23)))
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 12, hour: 0)))
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 12, hour: 2, minute: 30)))
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 12, hour: 4, minute: 59)))
    // 05:00 이후, 낮, 22:59 는 창 밖.
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 12, hour: 5)) == false)
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 12, hour: 13)) == false)
    #expect(DrowsyWindow.contains(kstDate(year: 2026, month: 7, day: 11, hour: 22, minute: 59)) == false)
}

@Test
func drowsyIntervalStaysWithin90Plus30Seconds() {
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<50 {
        let interval = DrowsyWindow.nextInterval(using: &rng)
        #expect(interval >= DrowsyWindow.minInterval)
        #expect(interval <= DrowsyWindow.maxInterval)
    }
}

@MainActor
@Test
func reactionParticleAndTextFactoriesAreConfigured() {
    // 색종이 버스트: 버스트 방출(birthRate>0), 반복 없음(버스트 후 제거), 짧은 방출.
    let confetti = ReactionActions.confettiSystem()
    #expect(confetti.birthRate > 0)
    #expect(confetti.loops == false)
    #expect(confetti.emissionDuration > 0)
    #expect(confetti.isLightingEnabled == false)

    // 💤 Z: SCNText, unlit(마스코트 색과 무관하게 흰색 유지).
    let z = ReactionActions.makeZNode(extent: 2)
    #expect(z.geometry is SCNText)
    #expect(z.geometry?.firstMaterial?.lightingModel == .constant)
}

// MARK: - Wave7: 때리면 아파하기 (클릭 프레임 판정)

@MainActor
@Test
func overlayControllerReactsToClickInsidePanelOnly() {
    var now = Date(timeIntervalSince1970: 20_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter(), engine: engine)
    controller.updateWorking(true)
    // 표시 시 commuteStart 가 재생 중이므로, 그 길이를 넘겨 idle 로 만든 뒤 클릭을 판정한다.
    now = now.addingTimeInterval(0.7)
    #expect(engine.state == .idle)

    let frame = controller.panel.frame
    let outside = NSPoint(x: frame.minX - 500, y: frame.minY - 500)
    controller.handleClick(at: outside)
    #expect(engine.state == .idle)

    let inside = NSPoint(x: frame.midX, y: frame.midY)
    controller.handleClick(at: inside)
    #expect(engine.state == .playing(.hit))

    controller.updateWorking(false) // 전역 모니터 해제(정리).
}

// MARK: - 드래그 이동: 클릭 vs 드래그 판정 / 클램프 / 오프셋 영속

@Test
func clampedOriginKeepsPanelInsideVisibleFrame() {
    let visible = NSRect(x: 0, y: 0, width: 1_000, height: 800)
    let size = NSSize(width: 140, height: 170)

    // 좌하단 밖으로 나간 origin 은 (minX, minY) 로 당겨진다.
    let low = CheckOverlayController.clampedOrigin(NSPoint(x: -50, y: -50), panelSize: size, in: visible)
    #expect(low.x == 0)
    #expect(low.y == 0)

    // 우상단 밖으로 나간 origin 은 (maxX-width, maxY-height) 로 당겨진다(패널 전체가 안에 들도록).
    let high = CheckOverlayController.clampedOrigin(NSPoint(x: 5_000, y: 5_000), panelSize: size, in: visible)
    #expect(high.x == visible.maxX - size.width)
    #expect(high.y == visible.maxY - size.height)

    // 이미 안쪽이면 그대로.
    let inside = CheckOverlayController.clampedOrigin(NSPoint(x: 300, y: 200), panelSize: size, in: visible)
    #expect(inside.x == 300)
    #expect(inside.y == 200)
}

@Test
func overlayFrameAppliesSavedTopRightOffset() {
    let visible = NSRect(x: 0, y: 0, width: 1_000, height: 800)
    let size = NSSize(width: 140, height: 170)

    // 오프셋 없음(nil) → 기존 기본 우상단(여백 24)과 동일.
    let none = CheckOverlayController.overlayFrame(offset: nil, in: visible, size: size, margin: 24)
    #expect(none == CheckOverlayController.overlayFrame(in: visible, size: size, margin: 24))

    // 오프셋 [100, 60] → 우상단에서 dx=100, dy=60 만큼 안쪽.
    let framed = CheckOverlayController.overlayFrame(offset: [100, 60], in: visible, size: size, margin: 24)
    #expect(framed.maxX == visible.maxX - 100)
    #expect(framed.maxY == visible.maxY - 60)
    #expect(framed.size == size)

    // 화면 밖으로 나가는 오프셋은 클램프되어 프레임 전체가 visibleFrame 안에 남는다.
    let clamped = CheckOverlayController.overlayFrame(offset: [-500, -500], in: visible, size: size, margin: 24)
    #expect(clamped.minX >= visible.minX)
    #expect(clamped.minY >= visible.minY)
    #expect(clamped.maxX <= visible.maxX)
    #expect(clamped.maxY <= visible.maxY)
}

@MainActor
@Test
func overlaySmallMoveIsTreatedAsClick() {
    var now = Date(timeIntervalSince1970: 60_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine, defaults: isolatedOverlayDefaults()
    )
    controller.updateWorking(true)
    now = now.addingTimeInterval(0.7) // commuteStart 만료 → idle
    #expect(engine.state == .idle)

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    let nudged = NSPoint(x: center.x + 3, y: center.y) // 3pt < 4pt 임계 → 클릭.
    controller.handleMouseDown(at: center)
    controller.handleMouseDragged(at: nudged)
    controller.handleMouseUp(at: nudged)

    // 임계 미만 이동 → 업 시점에 hit 발화, 위치 불변.
    #expect(engine.state == .playing(.hit))
    #expect(controller.panel.frame.origin == frame.origin)

    controller.updateWorking(false)
}

@MainActor
@Test
func overlayLargeMoveDragsWithoutHit() {
    var now = Date(timeIntervalSince1970: 61_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine, defaults: isolatedOverlayDefaults()
    )
    controller.updateWorking(true)
    now = now.addingTimeInterval(0.7) // commuteStart 만료 → idle
    #expect(engine.state == .idle)

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    // 화면 안쪽(좌하단)으로 30pt 이동 → 임계 초과, 클램프 없음.
    let moved = NSPoint(x: center.x - 30, y: center.y - 30)
    controller.handleMouseDown(at: center)
    controller.handleMouseDragged(at: moved)
    controller.handleMouseUp(at: moved)

    // 임계 초과 → hit 미발화(여전히 idle), origin 이 delta 만큼 이동.
    #expect(engine.state == .idle)
    #expect(controller.panel.frame.origin.x == frame.origin.x - 30)
    #expect(controller.panel.frame.origin.y == frame.origin.y - 30)

    controller.updateWorking(false)
}

@MainActor
@Test
func overlayWakesOnDownUpClickWhileSleeping() {
    var now = Date(timeIntervalSince1970: 62_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine, defaults: isolatedOverlayDefaults()
    )
    controller.updateWorking(true)
    now = now.addingTimeInterval(0.7)
    #expect(engine.state == .idle)

    engine.request(.drowsy)
    #expect(engine.state == .sleeping)

    // 자는 중 이동 없는 클릭(down→up) → wake 유지(회귀 확인).
    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    controller.handleMouseDown(at: center)
    controller.handleMouseUp(at: center)
    #expect(engine.state == .playing(.wake))
    #expect(engine.greetingText == "깜빡 졸았다!")

    controller.updateWorking(false)
}

@MainActor
@Test
func overlayDragOffsetRoundTripsAcrossControllers() {
    let shared = isolatedOverlayDefaults()
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 63_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine, defaults: shared
    )
    controller.updateWorking(true)

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    let moved = NSPoint(x: center.x - 40, y: center.y - 25)
    controller.handleMouseDown(at: center)
    controller.handleMouseDragged(at: moved)
    controller.handleMouseUp(at: moved)

    // 드래그 종료 → 우상단 오프셋 2개가 저장된다.
    let saved = shared.array(forKey: CheckOverlayController.overlayOffsetKey) as? [Double]
    #expect(saved?.count == 2)

    let draggedOrigin = controller.panel.frame.origin
    controller.updateWorking(false)

    // 같은 defaults 로 만든 새 컨트롤러는 init 의 reposition 에서 같은 위치를 복원한다.
    let store2 = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let restored = CheckOverlayController(
        store: store2, notificationCenter: NotificationCenter(), defaults: shared
    )
    #expect(abs(restored.panel.frame.origin.x - draggedOrigin.x) < 0.5)
    #expect(abs(restored.panel.frame.origin.y - draggedOrigin.y) < 0.5)
}

// MARK: - Wave8: 졸기 = 지속 상태(때려야 깸)

@MainActor
@Test
func reactionEngineSleepPersistsUntilWoken() {
    var now = Date(timeIntervalSince1970: 30_000)
    let engine = ReactionEngine(clock: { now })

    // drowsy 요청은 일회성 재생이 아니라 sleeping 지속 상태로 진입한다.
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 아무리 시간이 지나도 자동으로 깨지 않는다(만료 없음).
    now = now.addingTimeInterval(3_600)
    #expect(engine.state == .sleeping)
    now = now.addingTimeInterval(24 * 3_600)
    #expect(engine.state == .sleeping)
}

@MainActor
@Test
func reactionEngineWakesOnClickWithBubble() {
    var now = Date(timeIntervalSince1970: 31_000)
    let engine = ReactionEngine(clock: { now })

    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 자는 중 클릭 → wake(화들짝) + "깜빡 졸았다!". hit 쿨다운과 무관하게 즉시 수용된다.
    #expect(engine.request(.wake))
    #expect(engine.state == .playing(.wake))
    #expect(engine.greetingText == "깜빡 졸았다!")

    // 화들짝 지속시간이 지나면 idle 로 복귀한다(깨어난 뒤 idle).
    now = now.addingTimeInterval(0.5)
    #expect(engine.state == .idle)
}

@MainActor
@Test
func reactionEngineIgnoresGreetingWhileSleeping() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 32_000) })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 자는데 팀원 인사는 하지 않는다 — 무시(재생 안 함), 상태·말풍선 불변.
    #expect(engine.request(.greeting(name: "철수")) == false)
    #expect(engine.state == .sleeping)
    #expect(engine.greetingText == nil)
}

@MainActor
@Test
func reactionEngineCommuteEndInterruptsSleep() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 33_000) })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 근무 종료는 자는 중이어도 즉시 인터럽트 → 꾸벅 인사 + "수고했어!".
    #expect(engine.request(.commuteEnd))
    #expect(engine.state == .playing(.commuteEnd))
    #expect(engine.greetingText == "수고했어!")
}

@MainActor
@Test
func reactionEngineMilestoneWakesAndPlays() {
    var now = Date(timeIntervalSince1970: 34_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 축하는 자는 중이면 깨우면서 재생(인터럽트 허용).
    #expect(engine.request(.milestone))
    #expect(engine.state == .playing(.milestone))

    // 마일스톤이 끝나면 idle 로 복귀한다(다시 졸 수 있게).
    now = now.addingTimeInterval(1.7)
    #expect(engine.state == .idle)
}

@MainActor
@Test
func reactionEngineReDrowsyWhileSleepingIsNoop() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 35_000) })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 자는 중 재-졸기 요청은 no-op(이미 자고 있음).
    #expect(engine.request(.drowsy) == false)
    #expect(engine.state == .sleeping)
}

@MainActor
@Test
func reactionEngineHitCooldownNormalAfterWake() {
    var now = Date(timeIntervalSince1970: 36_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.request(.drowsy))
    #expect(engine.request(.wake))
    #expect(engine.state == .playing(.wake))

    // 화들짝이 끝나 idle 로 복귀. wake 는 hit 쿨다운을 소모하지 않는다.
    now = now.addingTimeInterval(0.5)
    #expect(engine.state == .idle)
    #expect(engine.request(.hit))            // 첫 hit 즉시 허용.
    now = now.addingTimeInterval(0.3)        // 쿨다운(0.6) 이내
    #expect(engine.request(.hit) == false)
    now = now.addingTimeInterval(0.5)        // 총 0.8 → 쿨다운 해제 + hit 만료(idle)
    #expect(engine.request(.hit))
}

@MainActor
@Test
func overlayControllerWakesInsteadOfHitWhileSleeping() {
    var now = Date(timeIntervalSince1970: 37_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter(), engine: engine)
    controller.updateWorking(true)
    now = now.addingTimeInterval(0.7) // commuteStart 만료 → idle
    #expect(engine.state == .idle)

    // 자는 상태로 진입.
    engine.request(.drowsy)
    #expect(engine.state == .sleeping)

    // 자는 중 패널 안 클릭 → handleClick 이 state 를 보고 hit 대신 wake 로 분기.
    let frame = controller.panel.frame
    controller.handleClick(at: NSPoint(x: frame.midX, y: frame.midY))
    #expect(engine.state == .playing(.wake))
    #expect(engine.greetingText == "깜빡 졸았다!")

    controller.updateWorking(false) // 전역 모니터 해제(정리).
}

// MARK: - Wave8: 말풍선 4종(텍스트/지속시간/타이머)

@MainActor
@Test
func reactionBubbleDurationsMatchSpec() {
    // perform 이 참조하는 지속시간 상수(사용자 확정 사양)를 결정적으로 검증한다.
    #expect(ReactionEngine.commuteStartBubbleSeconds == 5)   // 오늘도 화이팅!
    #expect(ReactionEngine.hitBubbleSeconds == 1.2)          // 아얏!
    #expect(ReactionEngine.commuteEndBubbleSeconds == 2)     // 수고했어!
    #expect(ReactionEngine.greetingBubbleSeconds == 3)       // <이름>님 출근!
    #expect(ReactionEngine.wakeBubbleSeconds == 2.5)         // 깜빡 졸았다!
}

@MainActor
@Test
func reactionBubblesShowExpectedText() {
    // 시작: commuteStart → "오늘도 화이팅!".
    let start = ReactionEngine(clock: { Date(timeIntervalSince1970: 40_000) })
    #expect(start.request(.commuteStart))
    #expect(start.greetingText == "오늘도 화이팅!")

    // 평소 때리기: hit → "아얏!".
    let hit = ReactionEngine(clock: { Date(timeIntervalSince1970: 41_000) })
    #expect(hit.request(.hit))
    #expect(hit.greetingText == "아얏!")

    // 종료: commuteEnd → "수고했어!".
    let end = ReactionEngine(clock: { Date(timeIntervalSince1970: 42_000) })
    #expect(end.request(.commuteEnd))
    #expect(end.greetingText == "수고했어!")

    // 팀원 인사: greeting → "<이름>님 출근!".
    let greet = ReactionEngine(clock: { Date(timeIntervalSince1970: 43_000) })
    #expect(greet.request(.greeting(name: "지훈")))
    #expect(greet.greetingText == "지훈님 출근!")
}

@MainActor
@Test
func showBubbleResetsTimerAndSelfExpires() async {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 44_000) })

    // 긴 말풍선을 띄운 뒤 곧바로 짧은 말풍선으로 교체하면, 이전 타이머는 리셋되고 새 텍스트가 즉시 반영된다.
    engine.showBubble("오래", seconds: 100)
    #expect(engine.greetingText == "오래")
    engine.showBubble("잠깐", seconds: 0.15)
    #expect(engine.greetingText == "잠깐")

    // 새 타이머(0.15s)만 살아 있어 그 뒤 자체 소멸한다(이전 100s 타이머가 살아 있었다면 계속 보였을 것).
    var cleared = false
    for _ in 0..<50 {
        try? await Task.sleep(for: .milliseconds(20))
        if engine.greetingText == nil {
            cleared = true
            break
        }
    }
    #expect(cleared)
}

// MARK: - Wave7: 시각 검증 스냅샷 덤프 (CHECK_REACTION_SNAPSHOT_DIR 지정 시에만 기록)

@MainActor
@Test
func dumpReactionSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_REACTION_SNAPSHOT_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    // (a) 찌부 순간(때리면 아파하기): scaleY 0.62 / scaleX·Z 1.28.
    try writePosedSnapshot(to: base.appendingPathComponent("reaction-squash.png")) { wrapper, _ in
        wrapper.scale = SCNVector3(1.28, 0.62, 1.28)
    }
    // (b) 꾸벅 순간(근무 종료 인사): x축 -20°.
    try writePosedSnapshot(to: base.appendingPathComponent("reaction-bow.png")) { wrapper, _ in
        wrapper.eulerAngles = SCNVector3(ReactionActions.radians(-20), 0, 0)
    }
    // (c) 폴짝 순간(근무 시작/마일스톤): 위로 점프.
    try writePosedSnapshot(to: base.appendingPathComponent("reaction-hop.png")) { wrapper, extent in
        wrapper.position = SCNVector3(0, extent * 0.32, 0)
    }
    // (d) 자는 유지 자세(sleeping) + 💤 Z 노드. drowsySink 의 정지 포즈(앞으로 +14° 숙임, y -tilt*0.33)를 재현.
    // Z 는 흰색 반투명이라 투명 배경에선 안 보이므로, 바탕화면을 흉내 낸 어두운 배경 위에서 확인한다.
    try writePosedSnapshot(
        to: base.appendingPathComponent("reaction-sleeping.png"),
        background: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.34, alpha: 1)
    ) { wrapper, extent in
        let tilt = extent * 0.18
        wrapper.eulerAngles = SCNVector3(ReactionActions.radians(14), 0, 0) // 앞으로 숙임(forward lean).
        wrapper.position = SCNVector3(0, -tilt * 0.33, 0)
        if let root = wrapper.parent {
            for i in 0..<3 {
                let z = ReactionActions.makeZNode(extent: extent)
                z.opacity = 0.85
                z.position = SCNVector3(
                    extent * (0.3 + Double(i) * 0.05),
                    extent * (0.25 + Double(i) * 0.16),
                    extent * 0.1
                )
                root.addChildNode(z)
            }
        }
    }

    // (e) wake 순간(화들짝): 상체가 스냅으로 곧게 펴지며 살짝 튀어오른 프레임 + "깜빡 졸았다!" 말풍선.
    let wakeImage = try posedSCNImage { wrapper, extent in
        wrapper.eulerAngles = SCNVector3(0, 0, 0)
        wrapper.position = SCNVector3(0, extent * 0.18 * 0.12, 0) // 튀어오름 정점(bounceUp).
    }
    try writeBubbleComposite(
        background: wakeImage, bubbleText: "깜빡 졸았다!",
        to: base.appendingPathComponent("reaction-wake.png")
    )

    // (f) 등장 포즈(commuteStart 폴짝) + "오늘도 화이팅!" 말풍선.
    let hopImage = try posedSCNImage { wrapper, extent in
        wrapper.position = SCNVector3(0, extent * 0.32, 0)
    }
    try writeBubbleComposite(
        background: hopImage, bubbleText: "오늘도 화이팅!",
        to: base.appendingPathComponent("reaction-fighting.png")
    )

    // (g) 팀원 출근 인사 말풍선(SwiftUI 합성). 기본 구도(idle) 렌더 위에 실제 말풍선 컴포넌트를 얹는다.
    let scnPNG = try #require(CheckCharacter3DScene.renderSnapshotPNG())
    let scnImage = try #require(NSImage(data: scnPNG))
    try writeBubbleComposite(
        background: scnImage, bubbleText: "지훈님 출근!",
        to: base.appendingPathComponent("reaction-greeting.png")
    )
}

/// wrapper 노드에 정지 포즈를 적용한 SCN 오프스크린 렌더 NSImage 를 만든다(리액션 중간 포즈 육안 확인용).
@MainActor
private func posedSCNImage(
    size: CGSize = CGSize(width: 280, height: 340),
    background: NSColor? = nil,
    pose: (_ wrapper: SCNNode, _ extent: CGFloat) -> Void
) throws -> NSImage {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let device = try #require(MTLCreateSystemDefaultDevice())
    if let background {
        scene.background.contents = background
    }
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let (minB, maxB) = wrapper.boundingBox
    let extent = CGFloat(max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z)))
    pose(wrapper, extent > 0 ? extent : 1)

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.autoenablesDefaultLighting = false
    return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
}

/// posedSCNImage 렌더를 PNG 로 저장한다(리액션 중간 포즈 육안 확인용).
@MainActor
private func writePosedSnapshot(
    to url: URL,
    size: CGSize = CGSize(width: 280, height: 340),
    background: NSColor? = nil,
    pose: (_ wrapper: SCNNode, _ extent: CGFloat) -> Void
) throws {
    let image = try posedSCNImage(size: size, background: background, pose: pose)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: url)
}

/// 캐릭터 렌더 이미지를 배경으로 두고 실제 말풍선 컴포넌트(CheckGreetingBubble)를 캐릭터 왼쪽 위에 얹어 저장한다.
@MainActor
private func writeBubbleComposite(background: NSImage, bubbleText: String, to url: URL) throws {
    let mock = ZStack(alignment: .topLeading) {
        Image(nsImage: background)
            .resizable()
            .scaledToFit()
        CheckGreetingBubble(text: bubbleText)
            .padding(.leading, 4)
            .padding(.top, 8)
    }
    .frame(width: CheckOverlayController.panelSize.width, height: CheckOverlayController.panelSize.height)
    let renderer = ImageRenderer(content: mock)
    renderer.scale = 3
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: url)
}

// MARK: - Helpers

private func isolatedOverlayDefaults() -> UserDefaults {
    let suiteName = "check-overlay-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 지정한 KST 시각의 Date 를 만든다(시간창/1일1회 판정 테스트용).
private func kstDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

private func member(_ id: String, _ status: WorkStatus) -> TeamMemberStatus {
    TeamMemberStatus(id: id, name: "\(id)-name", status: status, updatedAt: nil, currentSessionStartedAt: nil)
}

// MARK: - 캐릭터 가시성 픽셀 회귀 (A8 텍스처 다운스케일이 재질을 깨면 렌더가 비어 버린다)

@MainActor
@Test
func characterSceneRendersVisiblePixels() throws {
    // 오프스크린 렌더 중앙 영역에 불투명·유채(비백색) 픽셀이 실제로 존재해야 한다.
    // 텍스처 교체가 잘못되면(아카이브 URL 오독 → 1×512 쓰레기) 캐릭터가 투명/백색으로 사라져 실패한다.
    let png = try #require(CheckCharacter3DScene.renderSnapshotPNG())
    let image = try #require(NSImage(data: png))
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let w = bitmap.pixelsWide
    let h = bitmap.pixelsHigh
    var colored = 0
    for x in stride(from: w / 3, to: 2 * w / 3, by: 4) {
        for y in stride(from: h / 3, to: 2 * h / 3, by: 4) {
            guard let raw = bitmap.colorAt(x: x, y: y),
                  let c = raw.usingColorSpace(.deviceRGB) else { continue }
            if c.alphaComponent > 0.5, c.brightnessComponent < 0.97 {
                colored += 1
            }
        }
    }
    #expect(colored > 20)
}

@MainActor
@Test
func usdzArchiveTextureDownscalesToSaneDimensions() throws {
    // 실제 usdz 의 아카이브 참조 텍스처(...usdz?offset=&size=)가 정상 치수(≥8px, ≤512px)로
    // 다운스케일되는지 검증한다. 참조 해석이 깨지면 no-op(nil)으로 떨어져 found 가 false 가 된다.
    let scene = try #require(CheckCharacter3DScene.loadModelScene())
    var found = false
    scene.rootNode.enumerateHierarchy { node, _ in
        node.geometry?.materials.forEach { material in
            if let cg = CheckCharacter3DScene.downscaledTexture(material.diffuse.contents) {
                #expect(cg.width >= 8)
                #expect(cg.height >= 8)
                #expect(max(cg.width, cg.height) <= 512)
                found = true
            }
        }
    }
    #expect(found)
}
