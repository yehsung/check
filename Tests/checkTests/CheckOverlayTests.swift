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
func overlayControllerTogglesVisibilityWithWorking() {
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
    #expect(controller.shouldBeVisible == false)
    if becameVisible {
        #expect(controller.panel.isVisible == false)
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

// MARK: - Helpers

private func isolatedOverlayDefaults() -> UserDefaults {
    let suiteName = "check-overlay-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
