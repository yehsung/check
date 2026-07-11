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
    #expect(engine.request(.drowsy))
    #expect(engine.state == .playing(.drowsy))
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
func reactionEngineClearsGreetingBubbleWhenInterrupted() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 3_000) })
    #expect(engine.request(.greeting(name: "영희")))
    #expect(engine.greetingText == "영희님 출근!")

    // 더 높은 우선순위(hit)가 들어오면 말풍선도 함께 사라진다.
    #expect(engine.request(.hit))
    #expect(engine.greetingText == nil)
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
        #expect(interval >= 60)
        #expect(interval <= 120)
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
    // (d) 졸기 순간 + 💤 Z 노드(머리 위 오른쪽 빈 코너에서 위로 떠오르는 중간 프레임).
    // Z 는 흰색 반투명이라 투명 배경에선 안 보이므로, 바탕화면을 흉내 낸 어두운 배경 위에서 확인한다.
    try writePosedSnapshot(
        to: base.appendingPathComponent("reaction-drowsy.png"),
        background: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.34, alpha: 1)
    ) { wrapper, extent in
        wrapper.eulerAngles = SCNVector3(ReactionActions.radians(-14), 0, 0)
        wrapper.position = SCNVector3(0, -extent * 0.06, 0)
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

    // (e) 팀원 출근 인사 말풍선(SwiftUI 합성). 캐릭터 렌더를 배경으로 실제 말풍선 컴포넌트를 얹는다.
    let scnPNG = try #require(CheckCharacter3DScene.renderSnapshotPNG())
    let scnImage = try #require(NSImage(data: scnPNG))
    let mock = ZStack(alignment: .topLeading) {
        Image(nsImage: scnImage)
            .resizable()
            .scaledToFit()
        CheckGreetingBubble(text: "지훈님 출근!")
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
    try png.write(to: base.appendingPathComponent("reaction-greeting.png"))
}

/// wrapper 노드에 정지 포즈를 적용한 SCN 오프스크린 렌더를 PNG 로 저장한다(리액션 중간 포즈 육안 확인용).
@MainActor
private func writePosedSnapshot(
    to url: URL,
    size: CGSize = CGSize(width: 280, height: 340),
    background: NSColor? = nil,
    pose: (_ wrapper: SCNNode, _ extent: CGFloat) -> Void
) throws {
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
    let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
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
