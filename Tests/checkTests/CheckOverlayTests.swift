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
func overlayTimeFormatterFormatsHoursMinutes() {
    // v0.2.43: 캐릭터 라벨은 **항상 HH:MM**(초 내림) — 메뉴바 제목과 같은 식(titleDuration). 종전엔 1시간 전 MM:SS,
    // 뒤 HH:MM:SS 로 초가 흘러 캐릭터를 켠 사람은 티커 감속이 영영 안 걸렸다(V0243MinuteTickTests).
    #expect(CheckOverlayTimeFormatter.text(0) == "00:00")
    #expect(CheckOverlayTimeFormatter.text(65) == "00:01")
    #expect(CheckOverlayTimeFormatter.text(59 * 60 + 59) == "00:59")
    #expect(CheckOverlayTimeFormatter.text(1_800) == MenuBarStatusFormatter.titleDuration(1_800))
    #expect(CheckOverlayTimeFormatter.text(3_600) == "01:00")
    #expect(CheckOverlayTimeFormatter.text(3_661) == "01:01")
    #expect(CheckOverlayTimeFormatter.text(12 * 3_600 + 34 * 60 + 56) == "12:34")
    // 팝오버 안 시계(duration)는 여전히 초를 흘린다 — 두 포맷터가 다른 것이 의도다.
    #expect(MenuBarStatusFormatter.duration(65) == "01:05")

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

// MARK: - A3 넛지 자동 근무 시작 (안내만 하고 즉시 시작)

@MainActor
@Test
func overlayNudgeAutoStartsWorkAndConsumesOverride() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    // 자격: 로그인 + 팀.
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 72_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )
    #expect(store.snapshot.isWorking == false)

    // 넛지 발동: 물어보지 않고 즉시 근무 시작 + 등장 말풍선 안내 오버라이드 세팅.
    controller.nudgeAutoStart()
    #expect(store.startedAt != nil)
    #expect(store.snapshot.isWorking == true)
    #expect(engine.commuteStartBubbleOverride?.text == CheckOverlayController.nudgeAutoStartText)
    #expect(engine.commuteStartBubbleOverride?.seconds == CheckOverlayController.nudgeAutoStartBubbleSeconds)

    // store 관찰 경로(SwiftUI)를 헤드리스로 모사: updateWorking(true) 가 등장 리액션을 처리하며 오버라이드를 소비한다.
    controller.updateWorking(true)
    #expect(controller.shouldBeVisible == true)
    #expect(engine.greetingText == CheckOverlayController.nudgeAutoStartText)
    #expect(engine.commuteStartBubbleOverride == nil) // 1회 소비 — 다음 수동 시작은 평소 문구.

    controller.updateWorking(false) // 정리.
    store.stop()
}

@MainActor
@Test
func overlayNudgeAutoStartIneligibleDoesNothing() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 73_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    // 로그아웃(session 없음) → 무발동.
    controller.nudgeAutoStart()
    #expect(store.startedAt == nil)
    #expect(engine.commuteStartBubbleOverride == nil)

    // 로그인은 됐지만 팀 미확정 → 무발동.
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    controller.nudgeAutoStart()
    #expect(store.startedAt == nil)
    #expect(engine.commuteStartBubbleOverride == nil)

    // 이미 근무중 → 무발동(오버라이드도 세팅되지 않는다).
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    store.start()
    controller.nudgeAutoStart()
    #expect(engine.commuteStartBubbleOverride == nil)
    store.stop()
}

@MainActor
@Test
func overlayNudgeAutoStartRunsRegardlessOfCharacterVisibility() {
    // 자동 시작은 끄고 켜는 설정이 아니라 앱의 기본 동작이다 — 캐릭터 표시(person 토글)를 어느 쪽으로 두든,
    // 로그인·팀 확정·비근무이기만 하면 발동해야 한다. 캐릭터를 켠 상태에서 먼저 확인한다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 74_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    store.setOverlayEnabled(true) // 캐릭터 켬.
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    controller.nudgeAutoStart()
    #expect(store.startedAt != nil)
    #expect(engine.commuteStartBubbleOverride?.text == CheckOverlayController.nudgeAutoStartText)
    store.stop()
    // 위 stop() 은 서브케이스 리셋이지 사용자 시나리오가 아니다 — v0.2.17부터 수동 종료는 자동 시작을
    // 억제하므로(그게 계약이다), 표시 설정 무관성만 보는 이 테스트에서는 억제를 풀고 다음 케이스로 간다.
    store.clearAutoStartSuppression()

    // 캐릭터를 끈 상태에서도 같은 자격이면 똑같이 발동한다(표시 설정은 자격에 섞이지 않는다).
    engine.commuteStartBubbleOverride = nil
    store.setOverlayEnabled(false)
    controller.nudgeAutoStart()
    #expect(store.startedAt != nil)
    #expect(store.snapshot.isWorking == true)
    store.stop()
}

@MainActor
@Test
func overlayNudgeAutoStartWorksWhileCharacterIsHidden() {
    // 회귀 지점: 자격이 `isOverlayEnabled` 를 AND 로 걸고 있어, 캐릭터를 숨기면(person 토글) 자동 근무 시작이
    // 영영 일어나지 않았다. docs/privacy.md 가 약속한 "캐릭터 표시와는 별개"를 실제로 지킨다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 75_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    // 캐릭터는 숨김 — 그래도 근무가 시작돼야 한다.
    store.setOverlayEnabled(false)
    controller.nudgeAutoStart()
    #expect(store.startedAt != nil)
    #expect(store.snapshot.isWorking == true)
    // 숨김 상태에서는 말풍선 오버라이드를 세우지 않는다 — 소비되지 않은 채 남아 있다가 몇 시간 뒤
    // 사용자가 캐릭터를 다시 켜는 순간 낡은 안내가 튀어나오면 안 된다.
    #expect(engine.commuteStartBubbleOverride == nil)
    controller.updateWorking(true)
    #expect(controller.shouldBeVisible == false) // 캐릭터는 여전히 숨김.
    #expect(engine.greetingText == nil)
    store.stop()
}

@MainActor
@Test
func staleCommuteStartOverrideFallsBackToDefaultBubble() {
    // 넛지 직후 곧바로 근무종료하면 SwiftUI onChange 병합으로 commuteStart 가 오지 않아 오버라이드가
    // 미소비로 남는다 — 다음 수동 출근에서 낡은 오버라이드(수명 초과)는 버려지고 평소 문구가 떠야 한다.
    var now = Date(timeIntervalSince1970: 80_000)
    let engine = ReactionEngine(clock: { now })
    engine.setCommuteStartBubbleOverride(text: "일하는 것 같아서 근무 시작했어요!", seconds: 8)

    // 수명(10초)을 넘긴 뒤의 수동 출근.
    now = now.addingTimeInterval(ReactionEngine.commuteStartOverrideLifetime + 1)
    engine.request(.commuteStart)
    #expect(engine.greetingText == "오늘도 화이팅!")
    #expect(engine.commuteStartBubbleOverride == nil) // 낡은 오버라이드도 반드시 비워진다.

    // 신선한 오버라이드는 그대로 소비된다(대조군).
    engine.setCommuteStartBubbleOverride(text: "안내", seconds: 8)
    now = now.addingTimeInterval(1)
    engine.request(.commuteStart)
    #expect(engine.greetingText == "안내")
    #expect(engine.commuteStartBubbleOverride == nil)
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

    // (b) 분 단위 목업 — 00:05 (HH:MM, v0.2.43 부터 초는 그리지 않는다).
    try writeOverlayMock(seconds: 5 * 60 + 7, background: scnImage,
                         to: base.appendingPathComponent("overlay-minutes.png"))
    // (c) 장시간 목업 — 12:34 (HH:MM). 캡슐 안에 잘림 없이 수납되는지 확인.
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

// MARK: - 업데이트 넛지 말풍선 (패널 표시 중 감지 시 버전당 1회)

@MainActor
@Test
func overlayShowsUpdateBubbleOncePerVersionWhileVisibleAndIdle() async {
    var now = Date(timeIntervalSince1970: 90_000)
    let engine = ReactionEngine(clock: { now })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    // 업데이트 가용 상태를 만든다: 현재 0.0.0 < 최신 v9.9.9. 스텁 fetch 로 latestVersion 을 채운다(네트워크 미접촉).
    let update = UpdateCheckStore(
        currentVersion: "0.0.0",
        fetcher: { _ in Data(#"{"tag_name":"v9.9.9"}"#.utf8) },
        clock: { now },
        defaults: isolatedOverlayDefaults()
    )
    await update.checkIfStale()
    #expect(update.isUpdateAvailable)

    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        engine: engine,
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil,
        updateCheck: update
    )

    // 미표시(패널 숨김) 상태에선 말풍선을 띄우지 않는다.
    #expect(controller.showUpdateBubbleIfNeeded() == false)

    controller.updateWorking(true)
    now = now.addingTimeInterval(0.7) // commuteStart 만료 → idle
    #expect(engine.state == .idle)

    // 표시 중 + idle + 업데이트 가용 + 미표시 → 말풍선 1회(문구·버전당 1회 확인).
    #expect(controller.showUpdateBubbleIfNeeded() == true)
    #expect(engine.greetingText == CheckOverlayController.updateBubbleText)
    // 같은 버전 재요청은 무시(영속 기록으로 도배 금지).
    #expect(controller.showUpdateBubbleIfNeeded() == false)

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

@MainActor
@Test
func overlayDragFacesHorizontalDirectionThenResetsOnUp() {
    var now = Date(timeIntervalSince1970: 64_000)
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
    #expect(engine.currentDragFacing == 0)

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    controller.handleMouseDown(at: center)

    // 오른쪽으로 크게 끌면(임계 초과) 오른쪽을 바라본다(+1).
    controller.handleMouseDragged(at: NSPoint(x: center.x + 30, y: center.y))
    #expect(engine.currentDragFacing == 1)

    // 방향을 반전해 왼쪽으로 충분히 끌면 왼쪽을 바라본다(-1).
    controller.handleMouseDragged(at: NSPoint(x: center.x - 30, y: center.y))
    #expect(engine.currentDragFacing == -1)

    // 놓으면 정면 복귀(0).
    controller.handleMouseUp(at: NSPoint(x: center.x - 30, y: center.y))
    #expect(engine.currentDragFacing == 0)

    controller.updateWorking(false)
}

@MainActor
@Test
func overlayDragFacingIgnoresMicroJitter() {
    var now = Date(timeIntervalSince1970: 65_000)
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

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)
    controller.handleMouseDown(at: center)
    // 이동 확정(임계 4pt 초과)은 되지만 수평 미세 떨림(±3pt 이내)이면 방향은 정면 유지.
    controller.handleMouseDragged(at: NSPoint(x: center.x + 1, y: center.y + 20))
    controller.handleMouseDragged(at: NSPoint(x: center.x - 2, y: center.y + 22))
    #expect(engine.currentDragFacing == 0)

    controller.handleMouseUp(at: NSPoint(x: center.x - 2, y: center.y + 22))
    controller.updateWorking(false)
}

// FIX: 드래그 facing 잔류 — 전역 mouseUp 유실로 방향이 남아 있어도, 새 handleMouseDown 은 진입 즉시 정면(0)에서
// 시작하고 기준점을 다시 잡는다(다음 판정이 새 제스처 기준으로 재개).
@MainActor
@Test
func overlayNewMouseDownResetsLeftoverFacingToFront() {
    var now = Date(timeIntervalSince1970: 66_000)
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

    let frame = controller.panel.frame
    let center = NSPoint(x: frame.midX, y: frame.midY)

    // 1) 오른쪽으로 끌어 +1 을 만든 뒤 mouseUp 을 '유실'시킨다(전역 up 유실 재현 — 방향이 +1 로 남는다).
    controller.handleMouseDown(at: center)
    controller.handleMouseDragged(at: NSPoint(x: center.x + 30, y: center.y))
    #expect(engine.currentDragFacing == 1)

    // 2) up 없이 새 제스처가 시작되면(handleMouseDown), 진입 즉시 정면(0)에서 시작해야 한다(잔류 방향 제거).
    controller.handleMouseDown(at: center)
    #expect(engine.currentDragFacing == 0)

    // 3) 새 기준점부터 방향 판정이 재개된다(왼쪽으로 끌면 -1).
    controller.handleMouseDragged(at: NSPoint(x: center.x - 30, y: center.y))
    #expect(engine.currentDragFacing == -1)

    controller.updateWorking(false)
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

// MARK: - 콕찌르기 수신: 움찔 모션 + 말풍선 + peek

@Test
func pokeBubbleTextFormatsSingleAndMultipleNames() {
    // 1명: "…님이 콕 찔렀어요!".
    #expect(CheckOverlayController.pokeBubbleText(names: ["이유성"]) == "이유성님이 콕 찔렀어요!")
    // 3명: 첫 이름 + "외 N명"(N=count-1). 첫 번째는 배치 순서 첫 이름.
    #expect(
        CheckOverlayController.pokeBubbleText(names: ["이유성", "김철수", "박영희"])
            == "이유성님 외 2명이 콕 찔렀어요!"
    )
    // 중복 이름도 카운트에 유지된다(2명 → 외 1명).
    #expect(CheckOverlayController.pokeBubbleText(names: ["이유성", "이유성"]) == "이유성님 외 1명이 콕 찔렀어요!")
}

@MainActor
@Test
func pokedReactionKindMatchesHitPriorityAndBoundedDuration() {
    // 즉시성: 찌름은 hit 와 동급 우선순위(3).
    #expect(ReactionKind.poked(bubbleText: "").priority == ReactionKind.hit.priority)
    // 화들짝 대소동 모션(≈2.35s)에 여유를 둔 duration. peek 창(8s) 안에 모션·말풍선이 모두 끝난다.
    let d = ReactionKind.poked(bubbleText: "").duration
    #expect(d >= 2.2 && d <= 2.6)
}

@MainActor
@Test
func reactionEngineAcceptsPokedFromIdleAndExpires() {
    var now = Date(timeIntervalSince1970: 39_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.state == .idle)

    // idle 에서 찌름 수락 → playing(.poked) + 말풍선 표시.
    let text = "이유성님이 콕 찔렀어요!"
    #expect(engine.request(.poked(bubbleText: text)))
    #expect(engine.state == .playing(.poked(bubbleText: text)))
    #expect(engine.greetingText == text)

    // 재생 길이가 지나면 idle 로 복귀(clock 기반 만료).
    now = now.addingTimeInterval(ReactionKind.poked(bubbleText: text).duration + 0.1)
    #expect(engine.state == .idle)
}

@MainActor
@Test
func reactionEnginePokedWakesFromSleeping() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 38_000) })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    // 자는 중 찔림 → 잠이 풀리고 이어서 움찔+말풍선이 재생된다(beginWake 화들짝이 아니라 통상 poked 경로).
    let text = "콕!"
    #expect(engine.request(.poked(bubbleText: text)))
    #expect(engine.state == .playing(.poked(bubbleText: text)))
    #expect(engine.greetingText == text)
}

@MainActor
@Test
func reactionEngineRepokeInterruptsAndRefreshesBubble() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 47_000) })
    #expect(engine.request(.poked(bubbleText: "이유성님이 콕 찔렀어요!")))
    #expect(engine.greetingText == "이유성님이 콕 찔렀어요!")

    // 진행 중 찌름은 동순위(3)라도 새 찌름이 인터럽트해 새 문구로 갱신한다(배치마다 리액션 1회).
    #expect(engine.request(.poked(bubbleText: "김철수님이 콕 찔렀어요!")))
    #expect(engine.state == .playing(.poked(bubbleText: "김철수님이 콕 찔렀어요!")))
    #expect(engine.greetingText == "김철수님이 콕 찔렀어요!")
}

@MainActor
@Test
func overlayHandleReceivedPokesShowsBubbleForNonEmptyBatch() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 100_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    // 빈 배치는 무시(말풍선 없음).
    controller.handleReceivedPokes([])
    #expect(engine.greetingText == nil)

    // 숨김(비근무) 상태에서 수신 → peek 경로. 노드 미연결이라 움찔은 no-op 이지만 말풍선은 뜬다.
    let names = ["이유성", "김철수"]
    let pokes = [
        ReceivedPoke(id: "1", fromName: names[0], createdAt: Date(timeIntervalSince1970: 100_000)),
        ReceivedPoke(id: "2", fromName: names[1], createdAt: Date(timeIntervalSince1970: 99_999))
    ]
    controller.handleReceivedPokes(pokes)
    let expected = CheckOverlayController.pokeBubbleText(names: names)
    #expect(engine.greetingText == expected)
    #expect(engine.state == .playing(.poked(bubbleText: expected)))

    controller.updateWorking(false) // peek 태스크 취소 + 렌더 정리.
}

@MainActor
@Test
func overlayPokePeekPlaysEvenWhenCharacterHidden() {
    // 회귀 지점: 한때 beginPokePeek 에 isOverlayEnabled 가드가 있어, 캐릭터를 숨긴 사용자에게는 찔림이
    // 아무 표시 없이 소멸했다(v0.2.7 의 '숨김 시 peek' 축소). take_pokes 는 이미 원자적으로 소비한 뒤라
    // 다시 오지 않고 보낸 쪽은 쿨타임만 태우므로, 표시 설정과 무관하게 8초 peek 로 전달해야 한다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 110_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )
    store.setOverlayEnabled(false)

    let pokes = [ReceivedPoke(id: "1", fromName: "이유성", createdAt: Date(timeIntervalSince1970: 110_000))]
    controller.handleReceivedPokes(pokes)

    // 캐릭터를 꺼 뒀어도 움찔+말풍선이 재생되고, peek 동안만 렌더/창이 켜진다.
    let expected = CheckOverlayController.pokeBubbleText(names: ["이유성"])
    #expect(engine.greetingText == expected)
    #expect(engine.state == .playing(.poked(bubbleText: expected)))
    #expect(engine.renderActive)
    // 상시 표시 자격은 그대로 꺼져 있다 — peek 는 일시 토스트일 뿐 '캐릭터 켜기'가 아니다.
    #expect(controller.shouldBeVisible == false)

    controller.updateWorking(false) // peek 태스크 취소 + 렌더 정리.
}

// MARK: - 3글자 메시지 수신: 보낸이+본문 말풍선(찔림 채널 재사용) · 큐 순서 · 양보 규칙

@Test
func messageBubbleTextCarriesSenderAndBody() {
    // 보낸이와 내용이 **둘 다** 있어야 한다 — 3글자만 떠 있으면 받는 쪽에서 아무 뜻도 없다.
    #expect(CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅") == "이유성님: 화이팅")
    // 이모지 3글자(확장 자소 클러스터 기준)는 그대로 실린다 — 스칼라로 세면 국기/스킨톤이 쪼개져 잘려 나간다.
    #expect(CheckOverlayController.messageBubbleText(name: "김철수", body: "👍🏻🎉🇰🇷") == "김철수님: 👍🏻🎉🇰🇷")
    // 별명이 서버 상한(12)을 넘겨 오면 **별명**을 자른다. 안 자르면 lineLimit(2) 꼬리 잘림이 본문을 지운다
    // — 잘리는 쪽이 알맹이가 되는 것이 이 포맷의 유일한 함정이다.
    #expect(
        CheckOverlayController.messageBubbleText(name: String(repeating: "가", count: 20), body: "화이팅")
            == String(repeating: "가", count: WorkTimerStore.displayNameMaxLength) + "…님: 화이팅"
    )
    // 본문이 표시 상한을 넘겨 와도(상대 클라가 무엇을 보내든) 잘라 낸다 — 우리 폭 예산을 남이 정하지 못하게 한다.
    #expect(
        CheckOverlayController.messageBubbleText(name: "이유성", body: "가나다라마바사")
            == "이유성님: " + String("가나다라마바사".prefix(MessageBody.maxCharacters)) + "…"
    )
    // 본문이 비면 콜론만 남은 깨진 문구("이유성님: ") 대신 보낸이는 반드시 남긴다.
    #expect(CheckOverlayController.messageBubbleText(name: "이유성", body: "") == "이유성님이 메시지를 보냈어요!")
}

@Test
func messageBubbleFitsTwoLineBudget() {
    // 실측 못 박기. 말풍선은 `lineLimit(2)` 라 3줄이 되는 순간 꼬리(=본문)가 잘린다.
    // 현재 상한(별명 12 · 본문 MessageBody.maxCharacters=3)에서는 가장 넓은 조합도 2줄 안이지만
    // (한글 161.1 / 이모지 177.1 / 라틴 164.7pt < 188pt 예산), 본문 상한이 4가 되면 이모지 최악이
    // 191.1pt = 3줄로 넘어간다. 그때 이 테스트가 그 자리에서 빨개져 포맷을 함께 손보게 만든다.
    let longName = String(repeating: "가", count: 30)
    let worst = [
        CheckOverlayController.messageBubbleText(name: longName, body: String(repeating: "뷁", count: 30)),
        CheckOverlayController.messageBubbleText(name: longName, body: String(repeating: "🎉", count: 30)),
        CheckOverlayController.messageBubbleText(name: longName, body: String(repeating: "W", count: 30)),
        // 서버 상한을 그대로 지킨 정상 최악(별명 12 + 본문 3).
        CheckOverlayController.messageBubbleText(
            name: String(repeating: "가", count: WorkTimerStore.displayNameMaxLength), body: "화이팅")
    ]
    for text in worst {
        #expect(overlayBubbleLineCount(text) <= 2, "말풍선이 3줄이 되면 꼬리(본문)가 잘린다: \(text)")
    }
    // 평상시 조합은 한 줄에 다 들어간다(66.4pt).
    #expect(overlayBubbleLineCount(CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅")) == 1)
}

@MainActor
@Test
func overlayShowsQueuedMessageAsPokeBubbleAndConsumesOne() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 120_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "이유성", body: "화이팅", createdAt: Date(timeIntervalSince1970: 120_000)),
        ReceivedMessage(id: "m2", fromName: "김철수", body: "ㅇㅋ", createdAt: Date(timeIntervalSince1970: 120_001))
    ]

    #expect(controller.showCurrentMessageBubble())
    // 새 말풍선 장치가 아니라 **찔림 리액션 그대로** 태운다 — 움찔 모션·6초 타이머·인터럽트 규칙을 함께 얻는다.
    let expected = CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅")
    #expect(engine.greetingText == expected)
    #expect(engine.state == .playing(.poked(bubbleText: expected)))
    // 한 폴링에 여러 건이 와도 **한 건만** 소비한다(나머지는 큐에 남아 자기 차례를 기다린다).
    #expect(store.receivedMessages.map(\.id) == ["m2"])

    store.receivedMessages = []
    controller.updateWorking(false)
}

@MainActor
@Test
func overlayMessageWaitsInsteadOfOverwritingExistingBubble() {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 121_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    // 업데이트 안내는 **버전당 1회**라 덮어쓰면 그 버전에 대해 영영 안 뜬다 — 메시지가 양보한다.
    engine.showBubble(CheckOverlayController.updateBubbleText, seconds: CheckOverlayController.updateBubbleSeconds)
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "이유성", body: "화이팅", createdAt: Date(timeIntervalSince1970: 121_000))
    ]

    #expect(controller.showCurrentMessageBubble() == false)
    #expect(engine.greetingText == CheckOverlayController.updateBubbleText)
    // ★ 핵심: 못 띄웠으면 **큐를 건드리지 않는다**. take_pokes 는 서버에서 원자 소비라 여기서 흘리면 영영 못 본다.
    #expect(store.receivedMessages.map(\.id) == ["m1"])

    // 말풍선이 스스로 꺼지면 그 다음 tick 에 뜬다(기다림은 손실이 아니다).
    engine.greetingText = nil
    #expect(controller.showCurrentMessageBubble())
    #expect(engine.greetingText == CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅"))
    #expect(store.receivedMessages.isEmpty)

    controller.updateWorking(false)
}

@MainActor
@Test
func overlayMessagePeeksWhenCharacterHidden() {
    // 캐릭터를 꺼 둔 사용자에게도 찔림과 **똑같이** peek 로 전달한다(v0.2.7 계약 그대로 — 강등하지 않는다).
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 122_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )
    store.setOverlayEnabled(false)
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "이유성", body: "화이팅", createdAt: Date(timeIntervalSince1970: 122_000))
    ]

    #expect(controller.showCurrentMessageBubble())
    let expected = CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅")
    #expect(engine.greetingText == expected)
    #expect(engine.state == .playing(.poked(bubbleText: expected)))
    #expect(engine.renderActive)                    // peek 동안만 렌더가 켜진다
    #expect(controller.shouldBeVisible == false)    // 상시 표시 자격은 그대로 꺼져 있다
    #expect(store.receivedMessages.isEmpty)

    controller.updateWorking(false) // peek 태스크 취소 + 렌더 정리.
}

@MainActor
@Test
func overlayMessagePumpDrainsQueueInArrivalOrderThenStops() async {
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 123_000) })
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )

    // tick 수면을 갈아 끼워 **말풍선이 스스로 꺼진 세계**를 만든다(프로덕션에선 엔진의 6초 타이머가 하는 일).
    // 실시간 1초를 기다리는 판으로는 이 계약을 검증할 수 없다 — 이 스위트는 메인 액터가 통째로 밀린다.
    let log = OverlayBubbleLog()
    controller.messageBubbleSleep = { _ in
        await MainActor.run {
            if let text = engine.greetingText { log.texts.append(text) }
            engine.greetingText = nil
            engine.cancelActiveReaction()   // 고정 clock 이라 재생이 스스로 만료되지 않는다.
        }
    }

    let base = Date(timeIntervalSince1970: 123_000)
    store.receivedMessages = [
        ReceivedMessage(id: "m1", fromName: "이유성", body: "화이팅", createdAt: base),
        ReceivedMessage(id: "m2", fromName: "김철수", body: "ㅇㅋ", createdAt: base.addingTimeInterval(1)),
        ReceivedMessage(id: "m3", fromName: "박영희", body: "굿", createdAt: base.addingTimeInterval(2))
    ]
    controller.drainMessagesIfNeeded()
    // 시간을 기다리지 않고 **메인 액터를 양보하며** 펌프가 끝나기를 기다린다(주입한 tick 은 즉시 깨어난다).
    for _ in 0..<200 {
        if store.receivedMessages.isEmpty && !controller.isDrainingMessages { break }
        await Task.yield()
    }

    // 한 건도 삼키지 않고 **도착 순서 그대로** 다 떴다(마지막 것만 띄우면 앞의 글자가 영영 사라진다).
    #expect(log.texts == [
        CheckOverlayController.messageBubbleText(name: "이유성", body: "화이팅"),
        CheckOverlayController.messageBubbleText(name: "김철수", body: "ㅇㅋ"),
        CheckOverlayController.messageBubbleText(name: "박영희", body: "굿")
    ])
    #expect(store.receivedMessages.isEmpty)
    // 큐가 비면 펌프는 **스스로 멈춘다** — 상시 루프가 남으면 유휴 0% 규약이 깨진다.
    #expect(controller.isDrainingMessages == false)

    controller.updateWorking(false)
}

/// 펌프 tick 마다 그때 떠 있던 말풍선 문구를 모아 두는 상자(@Sendable 클로저에서 쓰려면 참조 타입이어야 한다).
@MainActor
final class OverlayBubbleLog {
    var texts: [String] = []
}

/// CheckGreetingBubble 과 **같은 조건**으로 실제 줄 수를 센다: `.caption2` rounded semibold(10pt),
/// 텍스트 가용 폭 94pt(= 캡슐 maxWidth 110 − 좌우 패딩 8×2). SwiftUI 레이아웃을 헤드리스로 재는 가장 가까운 대역이다.
private func overlayBubbleLineCount(_ text: String, maxWidth: CGFloat = 94) -> Int {
    let size = NSFont.preferredFont(forTextStyle: .caption2).pointSize
    var font = NSFont.systemFont(ofSize: size, weight: .semibold)
    if let descriptor = font.fontDescriptor.withDesign(.rounded) {
        font = NSFont(descriptor: descriptor, size: size) ?? font
    }
    let storage = NSTextStorage(string: text, attributes: [.font: font])
    let container = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    let layout = NSLayoutManager()
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    var lines = 0
    var index = 0
    while index < layout.numberOfGlyphs {
        var range = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
        index = NSMaxRange(range)
        lines += 1
    }
    return lines
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
    // v0.2.38 β2: 기본 로더는 프리베이크 aing.scn(텍스처가 이미 512 로 구워진 네이티브 아카이브)을 우선 읽으므로,
    // 이 테스트가 보는 '아카이브 참조 텍스처' 경로는 usdz 출처를 명시해야만 지나간다.
    let scene = try #require(CheckCharacter3DScene.loadModelScene(from: .usdz))
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

// MARK: - 스위트가 사용자 화면을 덮지 않는다

/// ★ 이 파일이 검증하는 것 중 **유일하게 제품 동작이 아닌** 계약이다. 그래도 여기 있어야 한다 —
///   깨지는 방식이 "테스트가 빨개진다"가 아니라 "개발자 데스크톱이 3D 캐릭터와 전체화면 울트라로
///   도배된다"이고, 그건 아무도 자동으로 알아채지 못하기 때문이다(실사용 신고: "개발 과정 중에 계속
///   캐릭터나 여러 요소들로 내 컴퓨터가 도배돼").
///
/// 왜 창을 안 만들거나 안 띄우는 길로 가지 않았는지, 왜 알파 0인지는 `CheckPanelVisibility` 주석에 있다.
/// 여기서는 그 결정이 **실제로 서 있는지**만 값으로 확인한다. 판정(`isRunningTests`)이 조용히 false 가
/// 되면 — 실행 방식이 바뀌어 표식이 사라지는 것이 가장 흔한 경로다 — 첫 줄에서 곧바로 빨개진다.
@MainActor
@Test
func overlayPanelStaysInvisibleToTheUserWhileTesting() {
    // 판정 자체. `swift test` 로 여기까지 왔다면 이건 반드시 참이다.
    #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 죽었다 — 아래 창들이 전부 사용자 화면에 뜬다")
    #expect(CheckPanelVisibility.panelAlpha == 0)
    #expect(CheckPanelVisibility.productionAlpha == 1)   // 프로덕션 값은 손대지 않았다.

    // 생성 경로가 하나뿐임을 확인한다(팩토리를 우회해 만든 패널이 있으면 여기서 안 걸리므로,
    // 아래에서 컨트롤러가 실제로 쓰는 패널까지 함께 본다).
    #expect(CheckOverlayController.makePanel(size: CheckOverlayController.panelSize).alphaValue == 0)

    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedOverlayDefaults(),
        workspaceNotifications: nil
    )
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 700_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedOverlayDefaults(), workspaceNotifications: nil
    )
    #expect(controller.panel.alphaValue == 0)

    // ① 근무중 캐릭터 — 창은 실제로 화면에 올라가지만(orderFrontRegardless) 눈에는 안 보인다.
    store.setOverlayEnabled(true)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    controller.updateWorking(true)
    #expect(controller.shouldBeVisible)
    #expect(controller.panel.alphaValue == 0, "근무중 캐릭터가 사용자 화면에 보인다")

    // ② 전체화면 울트라 — 사용자가 가장 크게 겪는 것이 이것이다(1920×1080 이 5초간 화면을 덮는다).
    //    **기하는 그대로**여야 한다: 알파로 숨기기를 고른 이유가 바로 이 단언을 살려 두기 위해서다.
    controller.handleReceivedPokes([
        ReceivedPoke(id: "u1", fromName: "이유성", createdAt: Date(timeIntervalSince1970: 700_000), kind: .ultra)
    ])
    #expect(controller.isUltraActive)
    #expect(NSScreen.screens.contains { $0.frame == controller.panel.frame })   // 기하는 진짜 그대로
    #expect(controller.panel.alphaValue == 0, "전체화면 울트라가 사용자 화면을 덮었다")

    controller.endUltraTakeover()
    #expect(controller.panel.alphaValue == 0, "격발 원복이 알파를 되살렸다")

    // ③ 숨김 상태 peek(비근무인데 찔림이 와서 잠깐 뜨는 경로)도 같다.
    store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    controller.updateWorking(false)
    controller.handleReceivedPokes([
        ReceivedPoke(id: "n1", fromName: "김철수", createdAt: Date(timeIntervalSince1970: 700_000))
    ])
    #expect(controller.panel.alphaValue == 0, "peek 가 사용자 화면에 보인다")
}

// MARK: - v0.2.34: 목표 달성 / 미션 보상 연출
//
// 사용자 신고는 "주간 목표 달성이 1시간 근무와 똑같아 보인다"였다. 아래 테스트는 그 '똑같음'이
// 되돌아오는 경로(연출을 milestone 으로 되돌리기, 파티클을 색종이로 되돌리기, 말풍선 떼기)를 막는다.

@MainActor
@Test
func goalAchievedIsNotMilestoneInDisguise() {
    // ① 우선순위·길이가 마일스톤과 다르다.
    #expect(ReactionKind.goalAchieved.priority > ReactionKind.milestone.priority)
    #expect(ReactionKind.ultraCharged.priority > ReactionKind.milestone.priority)
    // 4는 전체화면 점거(ultraPoked)의 자리다 — 거기까지 올리면 안 된다.
    #expect(ReactionKind.goalAchieved.priority < ReactionKind.ultraPoked(bubbleText: "울트라!").priority)
    #expect(ReactionKind.ultraCharged.priority < ReactionKind.ultraPoked(bubbleText: "울트라!").priority)
    #expect(ReactionKind.goalAchieved.duration != ReactionKind.milestone.duration)
    #expect(ReactionKind.ultraCharged.duration != ReactionKind.milestone.duration)

    // ② 모션이 다르다. 마일스톤은 폴짝 2회(0.88s)뿐이고, 목표 달성은 공중 정지 0.35s 가 들어가 2.02s 다.
    //    "떠 있는 순간"이 있느냐가 흑백 화면에서도 갈리는 축이다.
    let goal = ReactionActions.goalAchieved(hop: 1.0)
    let milestone = ReactionActions.milestone(hop: 1.0)
    #expect(goal.duration > milestone.duration + 1.0)
    #expect(abs(goal.duration - 2.02) < 0.01)
    // 재생 길이(duration)는 액션 길이를 담아야 한다 — 짧으면 모션 도중 idle 로 만료된다.
    #expect(ReactionKind.goalAchieved.duration >= goal.duration)
    let charged = ReactionActions.ultraCharged()
    #expect(abs(charged.duration - 1.72) < 0.01)
    #expect(ReactionKind.ultraCharged.duration >= charged.duration)

    // ③ 파티클이 다르다 — 색이 아니라 **방향·회전·블렌드·방출 길이** 네 축이 반대다.
    let confetti = ReactionActions.confettiSystem()
    let spark = ReactionActions.goalSparkSystem()
    #expect(confetti.acceleration.y < 0)          // 색종이는 떨어진다
    #expect(spark.acceleration.y > 0)             // 스파크는 솟는다
    #expect(confetti.particleAngularVelocity > 0) // 색종이는 돈다
    #expect(spark.particleAngularVelocity == 0)   // 스파크는 곧게 솟는다
    #expect(confetti.blendMode == .alpha)
    #expect(spark.blendMode == .additive)
    #expect(spark.emissionDuration > confetti.emissionDuration)
    #expect(spark.spreadingAngle < confetti.spreadingAngle)
    #expect(spark.birthRate > 0)
    #expect(spark.loops == false)
    #expect(spark.isLightingEnabled == false)
}

@MainActor
@Test
func rewardParticleVelocitiesAreNeverNegative() {
    // 음수 속도(설계 원안의 particleVelocity = -1.1)는 이 저장소에 선례가 0이고, SceneKit 이 클램프하면
    // 파티클이 하나도 안 보여도 값 검증은 초록이다. 수렴은 방출구를 오므리는 SCNAction 이 만든다.
    #expect(ReactionActions.goalSparkSystem().particleVelocity > 0)
    let charge = ReactionActions.ultraChargeSystem(extent: 2)
    #expect(charge.particleVelocity > 0)
    #expect(charge.particleVelocityVariation >= 0)
    // 방출 껍질은 모델 크기에 비례한다(extent 0 이어도 반경이 0 이 되지 않게 하한을 둔다).
    #expect(ReactionActions.ultraChargeSystem(extent: 0).emitterShape is SCNSphere)
    #expect(charge.blendMode == .additive)
    #expect(charge.loops == false)
}

@MainActor
@Test
func rewardReactionsSpeakTheirReasonWhileMilestoneStaysSilent() {
    // 말풍선이 없다는 것이 "구분이 안 된다"의 절반이었다. 축하·보상은 글자로 이유를 말한다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 90_000) })
    #expect(engine.request(.milestone))
    #expect(engine.greetingText == nil, "마일스톤에 말풍선이 생기면 목표 달성과의 구분이 흐려진다")

    let goalEngine = ReactionEngine(clock: { Date(timeIntervalSince1970: 91_000) })
    #expect(goalEngine.request(.goalAchieved))
    #expect(goalEngine.greetingText == "주간 목표 달성!")

    let chargeEngine = ReactionEngine(clock: { Date(timeIntervalSince1970: 92_000) })
    #expect(chargeEngine.request(.ultraCharged))
    #expect(chargeEngine.greetingText == "울트라 +1!")
}

// MARK: - blocker UI-3: 보상 재생 중 도착한 찌름이 사라지면 안 된다

@MainActor
@Test
func rewardPlaybackYieldsToIncomingPokeButNotToLowerReactions() {
    // take_pokes 는 이미 원자적으로 소비를 끝냈고 호출부는 request 의 반환값을 읽지 않는다 —
    // 여기서 거부되면 그 찌름의 글자는 복구 불가로 증발한다. 보상에는 배지·미션 행·notice 라는
    // 지속 증거가 따로 있으므로 **양보하는 쪽은 보상**이다.
    for reward in [ReactionKind.goalAchieved, ReactionKind.ultraCharged] {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 93_000) })
        #expect(engine.request(reward))
        #expect(engine.state == .playing(reward))
        #expect(engine.request(.poked(bubbleText: "김철수님이 콕!")))
        #expect(engine.state == .playing(.poked(bubbleText: "김철수님이 콕!")))
        #expect(engine.greetingText == "김철수님이 콕!")
    }

    // 반대로 하위 순위(팀원 인사 1 · 오늘 4시간 2)는 보상을 인터럽트하지 못한다.
    // 인사는 15초 폴링마다 흔하게 오고, 보상 말풍선은 재화가 늘었다는 즉시 증거의 전부다.
    for reward in [ReactionKind.goalAchieved, ReactionKind.ultraCharged] {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 94_000) })
        #expect(engine.request(reward))
        #expect(engine.request(.greeting(name: "영희")) == false)
        #expect(engine.request(.milestone) == false)
        #expect(engine.state == .playing(reward))
    }
}

@MainActor
@Test
func sleepingIsInterruptedByRewardReactions() {
    // 자는 동안 목표를 달성하거나 보상을 받은 사용자에게 연출이 통째로 사라지면 안 된다
    // (`.drowsy/.greeting` 무시 가지에 잘못 넣으면 정확히 그렇게 된다).
    for reward in [ReactionKind.goalAchieved, ReactionKind.ultraCharged] {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 95_000) })
        #expect(engine.request(.drowsy))
        #expect(engine.state == .sleeping)
        #expect(engine.request(reward))
        #expect(engine.state == .playing(reward))
        engine.stopSleeping()
    }
}

// MARK: - 새 파티클 노드가 씬에 쌓이지 않는다 (removeTransientNodes 등록)

@MainActor
@Test
func rewardParticleNodesAreRegisteredForRemoval() throws {
    // removeTransientNodes 의 이름 배열에 새 파티클 이름을 안 넣으면 인터럽트 뒤에도 방출구 노드가
    // 씬에 남아 다음 연출 위에 겹쳐 뜨고, 반복되면 계속 쌓인다.
    for reward in [ReactionKind.goalAchieved, ReactionKind.ultraCharged] {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 96_000) })
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let root = scene.rootNode
        let wrapper = try #require(
            root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
        )
        engine.attach(node: wrapper, sceneRoot: root, view: SCNView())

        let emitterCount = { root.childNodes.filter { !$0.particleSystems.isNilOrEmpty }.count }
        #expect(emitterCount() == 0)
        #expect(engine.request(reward))
        #expect(emitterCount() == 1, "보상 연출이 파티클을 하나도 안 뿌렸다")

        // 동순위 찌름이 보상을 인터럽트한다 → interruptCurrent → removeTransientNodes.
        // 찌름은 파티클을 뿌리지 않으므로 남아 있으면 그건 지워지지 않은 잔여물이다.
        #expect(engine.request(.poked(bubbleText: "콕!")))
        #expect(emitterCount() == 0, "인터럽트 후에도 파티클 방출구가 씬에 남았다")
    }
}

@MainActor
@Test
func ultraChargeConvergesByCollapsingItsEmitter() throws {
    // 수렴을 음수 속도로 만들지 않는 대신, 방출 껍질을 오므리는 액션이 그 일을 한다.
    // 이 액션이 없으면 파란 스파크가 그냥 제자리에서 흩어져 '흡수'로 읽히지 않는다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 97_000) })
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let root = scene.rootNode
    let wrapper = try #require(
        root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    engine.attach(node: wrapper, sceneRoot: root, view: SCNView())

    #expect(engine.request(.ultraCharged))
    let emitter = try #require(root.childNodes.first { !$0.particleSystems.isNilOrEmpty })
    let collapse = try #require(emitter.action(forKey: ReactionEngine.ultraChargeCollapseKey))
    #expect(abs(collapse.duration - 0.70) < 0.001)

    // 목표 달성 쪽은 오므리지 않는다(솟는 분수라 방출구가 제자리여야 한다) — 두 연출이 서로 베끼지 않았다.
    let goalEngine = ReactionEngine(clock: { Date(timeIntervalSince1970: 98_000) })
    let goalScene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let goalRoot = goalScene.rootNode
    let goalWrapper = try #require(
        goalRoot.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    goalEngine.attach(node: goalWrapper, sceneRoot: goalRoot, view: SCNView())
    #expect(goalEngine.request(.goalAchieved))
    let goalEmitter = try #require(goalRoot.childNodes.first { !$0.particleSystems.isNilOrEmpty })
    #expect(goalEmitter.action(forKey: ReactionEngine.ultraChargeCollapseKey) == nil)
}

@MainActor
@Test
func attachReplaysRewardReactionsThatArrivedBeforeTheSceneExisted() throws {
    // reactionAction(for:) 에 새 case 를 nil 로 두면 지연 생성(래치) 중 도착한 축하·보상이 모션 없이
    // 지나간다 — attach 재생 경로가 그것을 잡는다.
    for reward in [ReactionKind.goalAchieved, ReactionKind.ultraCharged] {
        let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 99_000) })
        #expect(engine.request(reward))
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let root = scene.rootNode
        let wrapper = try #require(
            root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
        )
        let view = SCNView()
        engine.attach(node: wrapper, sceneRoot: root, view: view)
        #expect(wrapper.action(forKey: "check.reaction") != nil, "attach 가 걸린 보상 모션을 재생하지 않았다")
        #expect(view.preferredFramesPerSecond == ReactionEngine.activeFPS)
    }
}

private extension Optional where Wrapped == [SCNParticleSystem] {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
