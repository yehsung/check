import AppKit
import CoreGraphics
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// 2026-11-22 — 캐릭터 창이 "모든 Space" 소속을 잃으면(대표 맥 실측: 12개 중 2개) 다른 전체 화면 Space 에서 창이 통째로 없다.
// [캐릭터 표시]·찌르기 peek·울트라가 전부 같은 창을 올리기만 하고 아무것도 안 보였고, 앱을 다시 켜야 나았다.
//
// 여기 시험은 전부 **고장을 일부러 주입하고** 회복(또는 지켜야 할 비회복)을 단언한다.
//  · `OverlaySpaceRebuildTests`: 소속 질의를 주입(창 정체성으로 "망가짐"을 기억하는 가짜)해 감지·사다리·재생성·가드·배선을 잰다.
//    RP*: 표시 직전 수리 도중 재진입한 근무 전이(리뷰 지적 2·3) · HB*: 렌더러 박동 판별 로그(반론 D1·R5, 리뷰 지적 1).
//  · `OverlaySpaceRealWindowServerTests`: 진짜 윈도우 서버에서 **자기 시험 창**의 소속을 SkyLight 로 실제로 빼고(대표 맥과
//    같은 모양), 실제 경로가 고친 창의 **실제 소속**에 현재 Space 가 들었는지 잰다. 적용할 수 없는 맥이면 까닭을 남기고 건너뛴다.
// 패널은 전부 알파 0 · 클릭 통과(CheckMousePanel) · 캡처 제외이고 키 창이 되지 않는다(`CheckPanelVisibility`).

// MARK: - 도구

/// 주입 세계: 소속 질의 · 세션 판정 · 시계 · 수면 · 1단 수리를 한곳에서 쥔다.
///
/// "망가진 창"은 **강한 참조로** 기억한다 — 옛 창이 풀린 자리에 새 창이 같은 주소로 태어나면 ObjectIdentifier 가 겹쳐
/// 멀쩡한 새 창을 망가진 것으로 읽는다.
@MainActor
final class OSRWorld {
    static let missing = OverlaySpacePresence.missingCurrentSpace(spaces: [817, 4], current: 32)
    static let healthy = OverlaySpacePresence.onCurrentSpace(memberCount: 12, displaySpaceCount: 12)

    var sessionUsable = true
    var displaysAwake: Bool?
    var now = Date(timeIntervalSince1970: 2_000_000_000)
    var unknown = false
    var degradeAll = false
    var scripted: [OverlaySpacePresence?] = []
    var reapplyHeals = false
    /// 질의가 불릴 때마다(창을 받는다). 시험이 "그 순간" 상태를 엿보는 자리.
    var onPresence: ((NSWindow) -> Void)?
    private(set) var degradedWindows: [NSWindow] = []
    private(set) var presenceCalls = 0
    private(set) var reapplyCalls = 0
    /// 1단 수리가 불린 순간 그 창이 올라가 있었는가(표시 직전 수리는 false 여야 한다).
    private(set) var reapplyWhileVisible: [Bool] = []
    private(set) var sleepRequests: [Double] = []
    /// true 면 소속 확인 수면이 게이트에 선다(시험이 깨운다). false 면 즉시 돌아온다.
    var gated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var ultraWaiters: [CheckedContinuation<Void, Never>] = []

    func degrade(_ window: NSWindow) {
        if !degradedWindows.contains(where: { $0 === window }) { degradedWindows.append(window) }
    }

    func heal(_ window: NSWindow) {
        degradedWindows.removeAll { $0 === window }
    }

    func isDegraded(_ window: NSWindow) -> Bool {
        degradeAll || degradedWindows.contains { $0 === window }
    }

    func presence(of window: NSWindow) -> OverlaySpacePresence? {
        presenceCalls += 1
        onPresence?(window)
        if !scripted.isEmpty { return scripted.removeFirst() }
        if unknown { return nil }
        return isDegraded(window) ? Self.missing : Self.healthy
    }

    /// 1단 수리 직후(실제 재적용 뒤) 불린다. 시험이 "수리 도중 들어온 재통지"를 확정적으로 만드는 자리.
    var onReapply: ((NSWindow) -> Void)?

    func reapply(_ window: NSWindow) {
        reapplyCalls += 1
        reapplyWhileVisible.append(window.isVisible)
        OverlayPanelRepair.reapplyCollectionBehavior(window)
        if reapplyHeals { heal(window) }
        onReapply?(window)
    }

    func sleep(_ seconds: Double) async {
        sleepRequests.append(seconds)
        guard gated else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    var parkedSleepers: Int { waiters.count }

    func releaseOne() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    /// 울트라 정상 타이머·워치독을 세워 둔다(시험 도중 5초 원복이 끼어들지 않게). 끝에 `releaseUltra`.
    func ultraSleep() async {
        await withCheckedContinuation { ultraWaiters.append($0) }
    }

    func releaseUltra() {
        let pending = ultraWaiters
        ultraWaiters = []
        pending.forEach { $0.resume() }
    }
}

/// 실제 스토어 + 실제 컨트롤러. 워크스페이스·배포·화면 노티 센터는 **사적인 인스턴스**다(전역 센터 오염 없음).
@MainActor
final class OSRHarness {
    let world = OSRWorld()
    let store: WorkTimerStore
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let screens = NotificationCenter()
    let controller: CheckOverlayController

    init(function: String = #function) {
        let defaults = CheckTestScratch.defaults(function: function)
        store = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
            defaults: defaults,
            workspaceNotifications: nil
        )
        store.setOverlayEnabled(true)
        let world = self.world
        controller = CheckOverlayController(
            store: store,
            notificationCenter: screens,
            defaults: defaults,
            workspaceNotifications: workspace,
            distributedNotifications: distributed,
            nudgeSessionUsable: { world.sessionUsable }
        )
        controller.spacePresence = { world.presence(of: $0) }
        controller.spaceCheckSleep = { seconds in await world.sleep(seconds) }
        controller.panelRebuildClock = { world.now }
        controller.displaysAwake = { world.displaysAwake }
        controller.panelSpaceRepair = { world.reapply($0) }
        controller.ultraSleep = { _ in await world.ultraSleep() }
        controller.ultraWatchdogSleep = { _ in await world.ultraSleep() }
    }

    var panel: NSPanel { controller.panel }

    /// 스토어부터 근무 중으로 세우고 표시한다(스토어가 비근무면 첫 런루프의 SwiftUI 재통지가 방금 켠 표시를 끈다).
    func startWorking() {
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        controller.updateWorking(true)
    }

    func stopWorking() {
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        controller.updateWorking(false)
    }

    func postSpaceChange() { workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) }
    func lock() { distributed.post(name: CheckOverlayController.screenLockedNotification, object: nil) }
    func unlock() { distributed.post(name: CheckOverlayController.screenUnlockedNotification, object: nil) }
    func screensSleep() { workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
    func screensWake() { workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil) }
    func sessionBecome() { workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil) }
    func screenParametersChanged() { screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil) }

    func poke(_ name: String = "민수") {
        controller.handleReceivedPokes([ReceivedPoke(id: "p-\(name)", fromName: name, createdAt: Date(), kind: .normal)])
    }

    func ultra(_ name: String = "보낸이") {
        controller.handleReceivedPokes([ReceivedPoke(id: "u-\(name)", fromName: name, createdAt: Date(), kind: .ultra)])
    }

    /// 표시 → 숨김(인사 0.55초 뒤 내려간다). 숨긴 뒤에도 창은 "한 번 올라간 적 있는" 창이다.
    func showThenHide() async -> Bool {
        startWorking()
        stopWorking()
        let hidden = await osrWaitUntil { !self.panel.isVisible }
        // 인사 숨김 타이머(0.55초)가 다 지나가게 둔다 — 남아 있으면 뒤에 띄운 peek 를 그 타이머가 내린다.
        osrSpin(CheckOverlayController.farewellHideDeadline + 0.15)
        return hidden && !panel.isVisible
    }

    func tearDown() {
        world.gated = false
        world.releaseAll()
        world.releaseUltra()
        if controller.isUltraActive { controller.endUltraTakeover() }
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        controller.updateWorking(false)
        controller.panel.orderOut(nil)
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
}

/// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다. 상한은 벽시계가 아니라 폴링 횟수다(V0238OverlayTests 의 규약 —
/// 병렬 스위트의 긴 동기 작업이 메인을 수십 초 잡는 일이 있다).
@MainActor
func osrWaitUntil(maxPolls: Int = 1500, _ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<maxPolls {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// 메인 런루프를 돌린다(SwiftUI 갱신·CA 커밋·메인 큐 작업이 그 사이 처리된다).
@MainActor
func osrSpin(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
    }
}

@MainActor
func osrFirstSCNView(in view: NSView?) -> SCNView? {
    guard let view else { return nil }
    if let scn = view as? SCNView { return scn }
    for sub in view.subviews {
        if let found = osrFirstSCNView(in: sub) { return found }
    }
    return nil
}

// MARK: - 주입 시험

@Suite("OverlaySpaceRebuild", .serialized)
@MainActor
struct OverlaySpaceRebuildTests {

    // MARK: T1 — Space 전환 뒤 2회 연속 없음 → 1단(안 나음) → 2단 재생성

    @Test("T1 Space 전환 뒤 현재 Space 에서 빠진 창은 같은 자리·같은 내용의 새 창으로 갈아 끼워진다")
    func t1SpaceChangeRebuildsADegradedPanel() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        let content = try #require(old.contentView)
        let frame = old.frame
        let ignores = old.ignoresMouseEvents
        #expect(old.isVisible)

        h.world.degrade(old)
        h.postSpaceChange()
        let rebuilt = await osrWaitUntil { h.controller.panelRebuilds == 1 }
        #expect(rebuilt, "망가진 창을 다시 만들지 않았다")
        #expect(h.world.reapplyCalls == 1, "사다리 1단을 건너뛰었다")
        #expect(h.panel !== old, "창 객체가 그대로다")
        #expect(h.panel.isVisible, "새 창이 안 올라갔다")
        #expect(!old.isVisible, "옛 창이 남았다")
        #expect(old.contentView == nil)
        #expect(h.panel.contentView === content, "호스팅 뷰를 옮기지 않고 새로 만들었다")
        #expect(content.window === h.panel)
        #expect(h.panel.frame == frame, "자리가 바뀌었다")
        #expect(h.panel.ignoresMouseEvents == ignores)
        #expect(h.panel.collectionBehavior.contains(.canJoinAllSpaces))
        // 0.75초 뒤 재확인이 나았다고 기록한다(새 창은 가짜 세계에서 멀쩡하다).
        let verified = await osrWaitUntil { h.controller.lastSpaceRepairVerdict?.rung == .rebuild }
        #expect(verified)
        #expect(h.controller.lastSpaceRepairVerdict == .init(rung: .rebuild, healed: true))
        #expect(h.controller.spaceRepairStage == nil)
        #expect(h.controller.panelRebuilds == 1, "나은 창을 또 갈았다")
    }

    @Test("T1b 1단(collectionBehavior 재적용)이 나으면 창을 갈지 않는다")
    func t1bReapplyHealsWithoutRebuilding() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        h.world.reapplyHeals = true
        h.world.degrade(old)
        h.postSpaceChange()
        let verified = await osrWaitUntil { h.controller.lastSpaceRepairVerdict != nil }
        #expect(verified)
        #expect(h.controller.lastSpaceRepairVerdict == .init(rung: .reapplyCollectionBehavior, healed: true))
        #expect(h.world.reapplyCalls == 1)
        #expect(h.controller.panelRebuilds == 0, "1단이 나았는데 창을 갈았다")
        #expect(h.panel === old)
        #expect(old.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
                "재적용이 원래 값을 되돌려 놓지 않았다")
    }

    // MARK: T2 — SCNView·씬은 그대로 옮겨 탄다

    @Test("T2 재생성은 SCNView·씬·엔진 연결을 다시 만들지 않는다")
    func t2RebuildKeepsTheSameSCNViewAndScene() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let mounted = await osrWaitUntil { osrFirstSCNView(in: h.panel.contentView) != nil && h.controller.engine.hasAttachedView }
        try #require(mounted, "SCNView 가 마운트되지 않았다 — 이 시험이 아무것도 못 본다")
        let scn = try #require(osrFirstSCNView(in: h.panel.contentView))
        let scene = try #require(scn.scene)
        let attachedScene = h.controller.engine.attachedScene
        let old = h.panel

        #expect(h.controller.rebuildPanel(reason: .manual))
        osrSpin(0.3)
        #expect(h.panel !== old)
        let after = try #require(osrFirstSCNView(in: h.panel.contentView), "새 창에 SCNView 가 없다")
        #expect(after === scn, "SCNView 를 새로 만들었다 — 모델 재로드·감은눈 굽기가 다시 돈다")
        #expect(after.scene === scene, "씬이 바뀌었다")
        #expect(after.window === h.panel, "SCNView 가 새 창에 안 실렸다")
        #expect(h.controller.engine.attachedScene === attachedScene)
        #expect(h.controller.engine.hasAttachedView, "엔진이 창 없는 뷰를 잡고 있다")
        #expect(after.isPlaying, "옮긴 뒤 렌더 루프가 섰다")
    }

    // MARK: T3 — 울트라 중 재생성

    @Test("T3 울트라 중 재생성은 전체 화면 프레임·클릭 통과 못 박기를 유지하고, 원복은 새 창에서 원래 자리로 간다")
    func t3RebuildDuringUltraKeepsTheTakeover() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let smallFrame = h.panel.frame
        h.ultra()
        try #require(h.controller.isUltraActive, "격발이 안 섰다")
        let ultraFrame = h.panel.frame
        #expect(ultraFrame != smallFrame, "격발이 화면을 덮지 않았다 — 이 시험이 아무것도 못 본다")
        let old = h.panel

        // 격발이 예약한 확인(0.75초 · 2회)이 1단 → 재확인 → 2단을 탄다.
        h.world.degrade(old)
        let rebuilt = await osrWaitUntil { h.controller.panelRebuilds == 1 }
        #expect(rebuilt, "격발 중 망가진 창을 다시 만들지 않았다")
        #expect(h.world.reapplyCalls == 1)
        #expect(h.panel !== old)
        #expect(h.controller.isUltraActive, "재생성이 격발을 접었다")
        #expect(h.panel.frame == ultraFrame, "재생성이 전체 화면 프레임을 잃었다")
        #expect(h.controller.pinnedIgnoresMouseEventsValue == true)
        #expect(h.panel.ignoresMouseEvents == true, "못 박은 클릭 통과가 새 창에 안 실렸다")
        #expect(h.panel.isVisible)

        h.controller.endUltraTakeover()
        #expect(!h.controller.isUltraActive)
        #expect(h.panel.frame == smallFrame, "원복이 새 창을 원래 자리로 안 돌렸다")
        #expect(h.panel.isVisible)
        #expect(!old.isVisible, "원복이 옛 창을 다시 올렸다")
    }

    // MARK: T4 · T12 — 모름이면 아무것도, 있으면 아무것도

    @Test("T4 질의가 모르면(nil) 아무것도 안 하고 연속 놓침도 0 으로 돌린다")
    func t4UnknownPresenceDoesNothing() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        h.world.degrade(old)
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        h.world.unknown = true
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.unknown))
        #expect(h.controller.spaceMissStreak == 0, "모름이 연속 놓침을 이어 줬다")
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.unknown))
        #expect(h.world.reapplyCalls == 0)
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.panel === old)
        // 기준선: 모름이 걷히면 같은 고장이 두 번 만에 고쳐진다(위 결과가 "애초에 못 고치는 하네스"의 초록이 아니다).
        h.world.unknown = false
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .repaired(.reapplyCollectionBehavior))
    }

    @Test("T12 지금 Space 에 있으면(일부 Space 만이어도) 멀쩡한 창을 건드리지 않는다")
    func t12HealthyPanelIsLeftAlone() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        h.world.scripted = [OverlaySpaceProbe.evaluate(spaces: [817, 4], current: 4, displaySpaceCount: 12),
                            .onCurrentSpace(memberCount: 12, displaySpaceCount: 12),
                            .onCurrentSpace(memberCount: nil, displaySpaceCount: nil)]
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .onCurrentSpace, "2/12 이지만 현재 Space 가 있는 창을 고장으로 셌다")
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .onCurrentSpace)
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .onCurrentSpace)
        #expect(h.controller.spaceMissStreak == 0)
        #expect(h.world.reapplyCalls == 0)
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.panel === old)
    }

    // MARK: T5 · T6 · T7 · T13 — 가드

    @Test("T5 캐릭터를 꺼 둔 비근무 상태는 보여야 할 의도가 없어 고치지 않는다")
    func t5NoIntentNoRepair() async {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.store.setOverlayEnabled(false)
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        h.controller.updateWorking(false)
        let old = h.panel
        old.orderFrontRegardless()   // 의도 없이 올라가 있는 창(가장 나쁜 경우)도 고칠 대상이 아니다
        h.world.degrade(old)
        let before = h.world.sleepRequests.count
        h.postSpaceChange()
        let ran = await osrWaitUntil { h.world.sleepRequests.count >= before + 1 }
        #expect(ran, "Space 전환이 확인을 예약하지 않았다 — 아래 단언이 공허하다")
        osrSpin(0.05)
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.notIntendedVisible))
        #expect(h.world.reapplyCalls == 0)
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.panel === old)
        old.orderOut(nil)
    }

    @Test("T6 잠금 중에는 고치지 않고, 해제 노티 뒤 확인이 고친다")
    func t6LockedSessionDefersUntilUnlock() async {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        h.world.degrade(old)
        h.lock()
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.sessionUnusable))
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.sessionUnusable))
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.world.reapplyCalls == 0)
        #expect(h.world.presenceCalls == 1, "잠금 중에 소속을 물었다(표시 순간의 진단 한 번만 있어야 한다)")

        // 노티 없이 콘솔 판정만 '못 씀'이어도 같다.
        h.unlock()
        h.world.sessionUsable = false
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.sessionUnusable))
        h.world.sessionUsable = true

        // 해제 노티가 확인을 예약하고, 그 확인이 사다리를 끝까지 탄다.
        h.lock()
        h.unlock()
        let rebuilt = await osrWaitUntil { h.controller.panelRebuilds == 1 }
        #expect(rebuilt, "잠금 해제 뒤 확인이 망가진 창을 고치지 않았다")
        #expect(h.panel !== old)
        #expect(h.panel.isVisible)
    }

    @Test("T7 화면이 꺼진 동안(screensDidSleep)은 고치지 않는다")
    func t7ScreensAsleepDefers() async {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let old = h.panel
        h.world.degrade(old)
        h.screensSleep()
        let before = h.world.sleepRequests.count
        h.postSpaceChange()
        let ran = await osrWaitUntil { h.world.sleepRequests.count >= before + 1 }
        #expect(ran)
        osrSpin(0.05)
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .skipped(.sessionUnusable))
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.world.reapplyCalls == 0)
        // 기준선: 깨면(깨움 노티 → 확인 예약) 고친다.
        h.screensWake()
        let rebuilt = await osrWaitUntil { h.controller.panelRebuilds == 1 }
        #expect(rebuilt, "깨어난 뒤에도 고치지 않았다")
    }

    @Test("T13 드래그 중에는 미루고, 손을 떼면 고친다")
    func t13DragDefersRepair() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true   // 표시가 예약한 확인이 끼어들지 않게
        h.startWorking()
        let frame = h.panel.frame
        // 몸체 판정은 SCNView 가 섰는지에 따라 달라서, 실제로 드래그가 서는 점을 찾는다(패널이 따라 움직이면 선 것이다).
        var grabbed: NSPoint?
        let candidates = [0.5, 0.4, 0.6].flatMap { fx in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2].map { (fx, $0) } }
        for (fx, fy) in candidates {
            let point = NSPoint(x: frame.minX + frame.width * fx, y: frame.minY + frame.height * fy)
            h.controller.handleMouseDown(at: point)
            let before = h.panel.frame.origin
            h.controller.handleMouseDragged(at: NSPoint(x: point.x - 30, y: point.y - 30))
            if h.panel.frame.origin != before { grabbed = point; break }
            h.controller.handleMouseUp(at: point)
        }
        let point = try #require(grabbed, "드래그를 세우지 못했다 — 이 시험이 아무것도 못 본다")
        h.world.degrade(h.panel)
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .skipped(.busy))
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .skipped(.busy))
        #expect(h.world.reapplyCalls == 0)
        h.controller.handleMouseUp(at: NSPoint(x: point.x - 30, y: point.y - 30))
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .repaired(.reapplyCollectionBehavior))
    }

    // MARK: T8 · T9 — 2회 규칙 · 상한

    @Test("T8 2회 연속이어야 고친다 — [없음, 있음] 은 그대로, [없음, 없음] 은 고친다")
    func t8TwoConsecutiveMissesRequired() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.startWorking()
        h.world.scripted = [OSRWorld.missing, OSRWorld.healthy]
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .onCurrentSpace)
        #expect(h.controller.spaceMissStreak == 0)
        #expect(h.world.reapplyCalls == 0, "놓침 한 번에 고쳤다")
        h.world.scripted = [OSRWorld.missing, OSRWorld.missing]
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        #expect(h.world.reapplyCalls == 0, "놓침 한 번에 고쳤다")
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .repaired(.reapplyCollectionBehavior))
        #expect(h.world.reapplyCalls == 1)
        #expect(h.controller.spaceMissStreak == 0)
    }

    @Test("T9 재생성은 1시간에 3번에서 멈추고, 61분이 지나면 한 번 더 허용한다")
    func t9RebuildCapPerSlidingHour() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true   // 예약된 재확인이 스스로 돌지 않게 — 사다리를 손으로 민다
        h.startWorking()
        h.world.degradeAll = true

        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .repaired(.reapplyCollectionBehavior))
        #expect(h.controller.verifySpaceRepair(.reapplyCollectionBehavior) == false)
        #expect(h.controller.panelRebuilds == 1, "1단이 안 나았는데 2단으로 안 올랐다")
        for expected in 2...3 {
            h.world.now = h.world.now.addingTimeInterval(60)
            #expect(h.controller.runSpaceCheck(event: .blinkTick) == .miss(streak: 1))
            #expect(h.controller.runSpaceCheck(event: .blinkTick) == .repaired(.rebuild))
            #expect(h.controller.panelRebuilds == expected)
        }
        let capped = h.panel
        for _ in 0..<3 {
            #expect(h.controller.runSpaceCheck(event: .blinkTick) == .miss(streak: 1))
            #expect(h.controller.runSpaceCheck(event: .blinkTick) == .skipped(.capped))
        }
        #expect(h.controller.rebuildPanel(reason: .manual) == false, "상한이 직접 호출을 막지 않는다")
        #expect(h.controller.panelRebuilds == 3, "상한을 넘겨 다시 만들었다")
        #expect(h.panel === capped)
        #expect(h.panel.isVisible, "상한에 걸린 뒤 창을 내렸다")

        // 첫 재생성에서 61분 뒤 — 창이 하나 열린다.
        h.world.now = h.world.now.addingTimeInterval(61 * 60)
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .blinkTick) == .repaired(.rebuild))
        #expect(h.controller.panelRebuilds == 4)
    }

    // MARK: T10 — 표시 직전 갱신

    @Test("T10a 숨은 창이 망가졌으면 peek 는 올리기 전에 1단을 쓴다(창이 아직 안 보일 때)")
    func t10aPeekRepairsTheHiddenPanelBeforeOrderingIn() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        try #require(await h.showThenHide(), "숨김 준비가 안 됐다")
        osrSpin(0.2)
        let old = h.panel
        try #require(!old.isVisible)
        h.world.reapplyHeals = true
        h.world.degrade(old)
        // 재확인은 손으로 민다 — 런루프를 돌리면 숨어 있던 호스팅 뷰가 밀린 SwiftUI 재통지(updateWorking(false))를 흘려
        // peek 를 내리는데(이 기능과 무관한 기존 peek 동작), 그러면 재확인이 "창이 내려가 모름"을 본다.
        h.world.gated = true

        h.poke()
        #expect(h.controller.isPeekArmed)
        #expect(h.world.reapplyCalls == 1, "표시 직전 수리가 안 돌았다")
        #expect(h.world.reapplyWhileVisible == [false], "창을 올린 뒤에 고쳤다 — 첫 프레임을 놓친다")
        #expect(h.panel === old)
        #expect(h.panel.isVisible)
        #expect(h.controller.verifySpaceRepair(.reapplyCollectionBehavior) == true)
        #expect(h.controller.lastSpaceRepairVerdict == .init(rung: .reapplyCollectionBehavior, healed: true))
        #expect(h.controller.spaceRepairStage == nil)
        #expect(h.controller.panelRebuilds == 0, "1단이 나았는데 창을 갈았다")
    }

    @Test("T10b 1단을 이미 쓴 고장이면 peek 는 올리기 전에 새 창으로 갈고, 옛 창은 다시 안 올라간다")
    func t10bPeekRebuildsBeforeOrderingInWhenRungOneWasSpent() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        let old = try await osrSpendRungOneThenHide(h)
        h.poke()
        #expect(h.controller.panelRebuilds == 1, "표시 직전 재생성이 없었다")
        #expect(h.panel !== old)
        #expect(h.panel.isVisible)
        #expect(!old.isVisible, "옛(망가진) 창을 다시 올렸다")
        #expect(h.controller.isPeekArmed)
    }

    @Test("T10c 1단을 이미 쓴 고장이면 울트라는 덮기 전에 새 창으로 갈고, 첫 덮기가 새 창이다")
    func t10cUltraCoversWithTheRebuiltPanel() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        let old = try await osrSpendRungOneThenHide(h)
        var coverPanel: NSPanel?
        h.controller.onUltraWillCoverScreen = { [weak controller = h.controller] in coverPanel = controller?.panel }
        h.ultra()
        #expect(h.controller.isUltraActive)
        #expect(h.controller.panelRebuilds == 1)
        let covering = try #require(coverPanel)
        #expect(covering !== old, "망가진 옛 창으로 화면을 덮었다")
        #expect(covering === h.panel)
        #expect(h.panel.isVisible)
        #expect(!old.isVisible)
        #expect(h.controller.pinnedIgnoresMouseEventsValue == true)
        #expect(h.panel.ignoresMouseEvents == true)
    }

    @Test("T10d 한 번도 올린 적 없는 새 창은 표시 직전에 묻지 않는다(새 창의 빈 소속을 고장으로 읽지 않는다)")
    func t10dNeverShownPanelIsNotJudged() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.degradeAll = true
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        h.controller.updateWorking(true)
        #expect(h.world.reapplyCalls == 0, "안 올린 창을 표시 직전에 고쳤다")
        #expect(h.controller.panelRebuilds == 0)
        #expect(h.panel.isVisible)
    }

    // MARK: T11 — 래치는 저장·복원이다

    @Test("T11 updateWorking 안의 표시 직전 재생성 뒤에도 바깥 호출 끝까지 래치가 선다")
    func t11LatchSurvivesPreShowRebuildInsideUpdateWorking() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        let old = try await osrSpendRungOneThenHide(h)
        var outcomesAfterRebuild: [CheckOverlayController.SpaceCheckOutcome] = []
        var reentered = false
        h.world.onPresence = { [weak controller = h.controller] _ in
            guard let controller, controller.panel !== old, !reentered else { return }
            reentered = true
            // 표시 순간 진단이 질의를 부르는 자리는 아직 updateWorking 안이다 — 여기서 확인을 두드리면 "바쁨"이어야 한다.
            outcomesAfterRebuild.append(controller.runSpaceCheck(event: .blinkTick))
            reentered = false
        }
        h.startWorking()
        h.world.onPresence = nil
        #expect(h.controller.panelRebuilds == 1, "표시 직전 재생성이 안 일어났다 — 이 시험이 아무것도 못 본다")
        #expect(!outcomesAfterRebuild.isEmpty, "재생성 뒤 updateWorking 안에서 질의가 안 불렸다 — 이 시험이 아무것도 못 본다")
        #expect(outcomesAfterRebuild.allSatisfy { $0 == .skipped(.busy) },
                "재생성이 updateWorking 의 래치를 풀었다: \(outcomesAfterRebuild)")
        #expect(h.controller.runSpaceCheck(event: .blinkTick) != .skipped(.busy), "바깥 호출이 끝났는데도 래치가 남았다")
        #expect(h.panel.isVisible)
        #expect(h.controller.shouldBeVisible)
    }

    @Test("T11b 래치를 쥔 자리에서 부른 재생성은 그 래치를 풀지 않는다(호출자가 누구든 저장·복원)")
    func t11bRebuildNeverReleasesALatchItDidNotTake() throws {
        // T11 은 표시 직전 갱신 경로만 본다 — 그 갱신이 래치를 스스로 저장·복원하므로, 재생성 안의 복원이 깨져도 T11 은 초록이다.
        // 여기서는 래치 안(updateWorking 의 표시 순간 진단이 질의를 부르는 자리)에서 재생성을 **직접** 부른다.
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        var rebuilt = false
        var outcomes: [CheckOverlayController.SpaceCheckOutcome] = []
        h.world.onPresence = { [weak controller = h.controller] _ in
            guard let controller, !rebuilt else { return }
            rebuilt = true
            _ = controller.rebuildPanel(reason: .manual)
            outcomes.append(controller.runSpaceCheck(event: .blinkTick))
        }
        h.startWorking()
        h.world.onPresence = nil
        #expect(rebuilt, "updateWorking 안에서 질의가 안 불렸다 — 이 시험이 아무것도 못 본다")
        #expect(h.controller.panelRebuilds == 1)
        #expect(outcomes == [.skipped(.busy)], "재생성이 바깥 updateWorking 의 래치를 풀었다: \(outcomes)")
        #expect(h.controller.runSpaceCheck(event: .blinkTick) != .skipped(.busy), "바깥 호출이 끝났는데도 래치가 남았다")
        #expect(h.panel.isVisible)
    }

    // MARK: R1 — 호스팅 뷰를 옮긴 뒤 SwiftUI 재통지(런루프를 실제로 돌린다)

    @Test("R1a peek 중 재생성 뒤 런루프를 돌려도 peek·말풍선·창이 살아 있다")
    func r1PeekSurvivesRebuildAcrossRunLoopTurns() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        osrSpin(0.3)   // 첫 `.onChange(initial: true)` 를 먼저 흘려 보낸다(재생성 뒤의 재통지와 섞이지 않게)
        h.poke("지수")
        try #require(h.controller.isPeekArmed, "peek 가 안 섰다")
        let bubble = h.controller.engine.greetingText
        try #require(bubble != nil)
        osrSpin(0.2)
        try #require(h.controller.isPeekArmed && h.panel.isVisible, "재생성 전에 이미 peek 가 졌다 — 기준선이 틀렸다")

        let old = h.panel
        #expect(h.controller.rebuildPanel(reason: .manual))
        osrSpin(0.5)
        #expect(h.panel !== old)
        #expect(h.controller.isPeekArmed, "재생성 뒤 재통지가 peek 를 취소했다(반론 R1)")
        #expect(h.panel.isVisible, "재생성 뒤 재통지가 창을 내렸다(반론 R1)")
        #expect(h.controller.engine.greetingText == bubble, "말풍선이 지워졌다")
    }

    @Test("R1b 근무 중 재생성 뒤 런루프를 돌려도 출근 점프를 다시 재생하지 않는다")
    func r1WorkingRebuildDoesNotReplayCommuteStart() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        osrSpin(0.4)
        h.controller.engine.cancelActiveReaction()
        try #require(h.controller.engine.state == .idle, "기준선이 idle 이 아니다")
        let frame = h.panel.frame
        let old = h.panel

        #expect(h.controller.rebuildPanel(reason: .manual))
        osrSpin(0.5)
        #expect(h.panel !== old)
        #expect(h.controller.engine.state == .idle, "재생성 뒤 재통지가 리액션을 다시 걸었다: \(h.controller.engine.state)")
        #expect(h.panel.isVisible)
        #expect(h.panel.frame == frame)
        #expect(h.controller.shouldBeVisible)
    }

    @Test("R1c 재생성 직후의 같은 값 재통지는 삼키고, 유예가 지나면 평소대로 흐른다")
    func r1SameValueRenotifyIsSwallowedOnlyRightAfterARebuild() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        h.controller.updateWorking(false)
        h.poke()
        try #require(h.controller.isPeekArmed)
        #expect(h.controller.rebuildPanel(reason: .manual))
        // SwiftUI 가 다음 런루프에 흘릴 수 있는 그 재통지를 그대로 흉내 낸다.
        h.controller.updateWorking(false)
        #expect(h.controller.isPeekArmed, "재생성 직후 같은 값 재통지가 peek 를 취소했다")
        #expect(h.panel.isVisible)
        // 기준선: 유예가 지나면 같은 재통지가 peek 를 정리한다(삼킴이 시간에 묶여 있고, 문이 없으면 peek 가 진다는 증거).
        h.world.now = h.world.now.addingTimeInterval(CheckOverlayController.rebuildRenotifyGraceSeconds + 0.5)
        h.controller.updateWorking(false)
        #expect(!h.controller.isPeekArmed, "유예가 지났는데도 재통지를 삼켰다")
    }

    @Test("R1d 유예 중이라도 진짜 전이(근무 시작)는 통과한다")
    func r1RealTransitionPassesDuringGrace() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        h.controller.updateWorking(false)
        h.poke()
        #expect(h.controller.rebuildPanel(reason: .manual))
        h.startWorking()
        #expect(h.controller.shouldBeVisible, "유예가 진짜 근무 시작을 삼켰다")
        #expect(h.panel.isVisible)
    }

    @Test("R4 재생성 중 래치가 삼킨 진짜 전이는 재생성 끝에 맞춘다")
    func r4RebuildReconcilesIntendedVisibility() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        h.controller.updateWorking(false)
        h.poke()
        // 스토어는 근무 중이 됐는데 그 통지가 래치에 삼켜진 세계(재통지는 같은 값에는 다시 오지 않는다).
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        try #require(!h.controller.shouldBeVisible, "통지가 이미 와 버렸다 — 이 시험이 아무것도 못 본다")
        #expect(h.controller.rebuildPanel(reason: .manual))
        #expect(h.controller.shouldBeVisible, "재생성이 스토어와 어긋난 표시 의도를 그대로 뒀다")
        #expect(h.panel.isVisible)
    }

    // MARK: RP — 표시 직전 수리 중 재진입한 근무 전이(리뷰 지적 2·3)
    //
    // 표시 직전 수리는 beginPeek · beginUltraTakeover 한복판에서 돈다. 그때 스토어가 막 근무로 바뀌어 있으면(SwiftUI onChange 가
    // 아직 안 옴) 수리가 updateWorking 을 되불렀다 — 1단은 `CATransaction.flush()` 가 밀린 onChange 를 **동기로** 흘리고(이 맥 실측:
    // 숨은 창에서 flush 직후 shouldBeVisible 이 바뀌었다), 2단은 스토어 대조를 한다. 그 호출이 반쯤 세운 격발을 철거하고 함수가
    // 그대로 화면을 덮어, 원복할 사람이 없는 전체 화면 창이 남았다(수정 전 코드에서 RP1·RP2·RP2b 가 빨갰다).

    @Test("RP1 울트라 표시 직전 재생성(2단) 때 스토어가 이미 근무 중이어도 격발이 반쯤 철거된 채 남지 않는다")
    func rp1UltraPreShowRebuildWithPendingWorkTransitionStaysCoherent() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        let old = try await osrSpendRungOneThenHide(h)
        // 스토어는 근무 중이 됐는데 SwiftUI onChange 가 아직 안 온 세계(반론 R4 가 맞추려는 바로 그 어긋남).
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        try #require(!h.controller.shouldBeVisible, "통지가 이미 와 버렸다 — 이 시험이 아무것도 못 본다")
        h.ultra()
        #expect(h.controller.panelRebuilds == 1, "표시 직전 재생성이 안 일어났다 — 이 시험이 아무것도 못 본다")
        #expect(h.panel !== old)
        osrExpectUltraCoherent(h, "격발 직후")
        #expect(h.controller.isUltraActive, "격발이 다 세워지기도 전에 철거됐다")
        let settled = await osrWaitUntil { h.controller.shouldBeVisible }
        #expect(settled, "밀린 근무 전이를 끝내 맞추지 않았다")
        osrExpectUltraCoherent(h, "근무 전이 뒤")
        #expect(h.panel.isVisible)
        #expect(!old.isVisible)
    }

    @Test("RP2 울트라 표시 직전 1단 수리 도중 근무 전이가 들어와도 격발이 반쯤 철거된 채 남지 않는다")
    func rp2UltraPreShowReapplyWithReentrantWorkTransitionStaysCoherent() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        try #require(await h.showThenHide(), "숨김 준비가 안 됐다")
        osrSpin(0.2)
        let old = h.panel
        h.world.degrade(old)
        h.world.reapplyHeals = true
        h.world.gated = true
        // 1단의 CATransaction.flush() 가 밀린 SwiftUI onChange 를 그 자리에서 흘리는 세계를 확정적으로 만든다.
        var reentered = 0
        h.world.onReapply = { [weak controller = h.controller, store = h.store] _ in
            reentered += 1
            controller?.updateWorking(store.snapshot.isWorking)
        }
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        try #require(!h.controller.shouldBeVisible, "통지가 이미 와 버렸다 — 이 시험이 아무것도 못 본다")
        h.ultra()
        #expect(reentered == 1, "1단 수리가 안 돌았다 — 이 시험이 아무것도 못 본다")
        #expect(h.controller.panelRebuilds == 0)
        osrExpectUltraCoherent(h, "격발 직후")
        #expect(h.controller.isUltraActive, "격발이 다 세워지기도 전에 철거됐다")
        let settled = await osrWaitUntil { h.controller.shouldBeVisible }
        #expect(settled, "삼킨 근무 전이를 끝내 맞추지 않았다")
        osrExpectUltraCoherent(h, "근무 전이 뒤")
        #expect(h.panel.isVisible)
    }

    @Test("RP2b 시험 훅 없이 실제 1단 flush 가 흘린 onChange 도 격발을 철거하지 않고, 삼킨 전이는 끝난 뒤에 맞춘다")
    func rp2bRealFlushRenotifyIsDeferredNotLost() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        try #require(await h.showThenHide(), "숨김 준비가 안 됐다")
        osrSpin(0.2)
        h.world.degrade(h.panel)
        h.world.reapplyHeals = true
        h.world.gated = true
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        try #require(!h.controller.shouldBeVisible, "통지가 이미 와 버렸다 — 이 시험이 아무것도 못 본다")
        h.ultra()
        #expect(h.world.reapplyCalls == 1, "1단 수리가 안 돌았다 — 이 시험이 아무것도 못 본다")
        #expect(h.controller.panelRebuilds == 0, "1단 도중 흘린 onChange 가 표시 직전 재생성까지 겹쳐 불렀다")
        osrExpectUltraCoherent(h, "격발 직후")
        #expect(h.controller.isUltraActive, "격발이 다 세워지기도 전에 철거됐다")
        // flush 가 래치 안에서 흘린 onChange 는 SwiftUI 가 "이미 흘렸다"고 본다 — 다시 안 온다. 미뤄 둔 대조만이 맞춘다.
        let settled = await osrWaitUntil(maxPolls: 150) { h.controller.shouldBeVisible }
        #expect(settled, "래치가 삼킨 근무 전이가 영영 안 맞춰졌다(표시 의도가 스토어와 어긋난 채 남았다)")
        osrExpectUltraCoherent(h, "근무 전이 뒤")
        #expect(h.panel.isVisible)
    }

    @Test("RP3 peek 표시 직전 수리 도중 근무 전이가 들어와도 끝나면 근무 표시로 맞춰진다(1단 · 2단)")
    func rp3PeekPreShowRepairWithPendingWorkTransitionSettlesToWorking() async throws {
        // 1단
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            try #require(await h.showThenHide(), "숨김 준비가 안 됐다")
            osrSpin(0.2)
            h.world.degrade(h.panel)
            h.world.reapplyHeals = true
            h.world.gated = true
            h.world.onReapply = { [weak controller = h.controller, store = h.store] _ in
                controller?.updateWorking(store.snapshot.isWorking)
            }
            h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
            try #require(!h.controller.shouldBeVisible)
            h.poke()
            #expect(h.world.reapplyCalls == 1)
            #expect(h.controller.panelRebuilds == 0)
            #expect(h.panel.isVisible)
            let settled = await osrWaitUntil(maxPolls: 150) { h.controller.shouldBeVisible }
            #expect(settled, "삼킨 근무 전이를 맞추지 않았다")
            #expect(h.panel.isVisible)
            #expect(h.panel.frame.size == CheckOverlayController.panelSize)
        }
        // 2단
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            let old = try await osrSpendRungOneThenHide(h)
            h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
            try #require(!h.controller.shouldBeVisible)
            h.poke()
            #expect(h.controller.panelRebuilds == 1)
            #expect(h.panel !== old)
            #expect(h.panel.isVisible)
            let settled = await osrWaitUntil(maxPolls: 150) { h.controller.shouldBeVisible }
            #expect(settled, "삼킨 근무 전이를 맞추지 않았다")
            #expect(h.panel.isVisible)
            #expect(!old.isVisible)
        }
    }

    @Test("RP3b peek 표시 직전 1단의 실제 flush 가 흘린 onChange 는 수리 안에서 재생성을 겹쳐 부르지 않고, 끝난 뒤 근무 표시로 맞춘다")
    func rp3bPeekRealFlushDoesNotNestARebuildAndSettles() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        try #require(await h.showThenHide(), "숨김 준비가 안 됐다")
        osrSpin(0.2)
        let old = h.panel
        h.world.degrade(old)
        h.world.reapplyHeals = true
        h.world.gated = true
        h.store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        try #require(!h.controller.shouldBeVisible, "통지가 이미 와 버렸다 — 이 시험이 아무것도 못 본다")
        h.poke()
        #expect(h.world.reapplyCalls == 1, "1단 수리가 안 돌았다 — 이 시험이 아무것도 못 본다")
        // 래치가 없으면: flush 가 흘린 updateWorking(true) → 표시 전이의 표시 직전 갱신이 아직 안 나은 같은 창을 보고 → 1단을 이미
        // 썼으니 재생성 — 1단 한복판에 2단이 겹친다(시간당 3회 상한을 헛되이 태우고, 1단 재확인이 2단 재확인을 덮는다).
        #expect(h.controller.panelRebuilds == 0, "1단 도중 흘린 onChange 가 재생성을 겹쳐 불렀다")
        #expect(h.panel === old)
        #expect(h.panel.isVisible)
        let settled = await osrWaitUntil(maxPolls: 150) { h.controller.shouldBeVisible }
        #expect(settled, "래치가 삼킨 근무 전이가 영영 안 맞춰졌다(SwiftUI 는 이미 흘렸다고 본다)")
        #expect(h.panel.isVisible)
        #expect(h.panel.frame.size == CheckOverlayController.panelSize)
    }

    // MARK: HB — 렌더러 박동(반론 (c)·D1·R5 판별 로그)

    @Test("HB1 캐릭터 SCNView 의 렌더러 delegate 가 엔진의 프레임 계수기다")
    func hb1FrameCounterIsTheSCNViewDelegate() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let mounted = await osrWaitUntil(maxPolls: 300) { osrFirstSCNView(in: h.panel.contentView) != nil }
        try #require(mounted, "SCNView 가 안 섰다")
        let scn = try #require(osrFirstSCNView(in: h.panel.contentView))
        #expect((scn.delegate as AnyObject?) === h.controller.engine.renderFrameCounter,
                "프레임 계수기가 SCNView 에 안 꽂혔다 — 박동이 늘 0 프레임이라 멀쩡한 창이 '렌더 루프 죽음'으로 찍힌다")
        // 계수기는 렌더러 콜백 하나를 한 프레임으로 센다.
        let counter = OverlayRenderFrameCounter()
        counter.renderer(scn, didRenderScene: SCNScene(), atTime: 0)
        counter.renderer(scn, didRenderScene: SCNScene(), atTime: 0)
        #expect(counter.count == 2)
    }

    @Test("HB2 표시 · peek · 울트라 수신 · 재생성마다 2초 박동을 남기고, 그 창 동안 그린 프레임을 센다")
    func hb2HeartbeatFollowsEveryShowPath() async throws {
        #expect(CheckOverlayController.renderHeartbeatSeconds == 2.0)
        func arm(_ h: OSRHarness) {
            let counter = h.controller.engine.renderFrameCounter
            // 박동 창 동안 7 프레임을 그린 세계(실제 렌더러가 더 그려도 된다 — 하한만 본다).
            h.controller.renderHeartbeatSleep = { _ in for _ in 0..<7 { counter.noteFrame() } }
        }
        func beat(_ h: OSRHarness, _ label: String) async -> CheckOverlayController.RenderHeartbeat? {
            _ = await osrWaitUntil(maxPolls: 300) { h.controller.lastRenderHeartbeat?.label == label }
            return h.controller.lastRenderHeartbeat?.label == label ? h.controller.lastRenderHeartbeat : nil
        }
        // 표시
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            arm(h)
            h.startWorking()
            let b = await beat(h, "shown")
            #expect(b != nil, "표시 뒤 박동이 없다")
            #expect((b?.frames ?? 0) >= 7, "박동이 그 창의 프레임을 안 셌다: \(String(describing: b))")
            #expect(b?.renderActive == true)
        }
        // peek
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            arm(h)
            h.poke()
            let b = await beat(h, "peek shown")
            #expect(b != nil, "peek 뒤 박동이 없다")
            #expect((b?.frames ?? 0) >= 7)
        }
        // 울트라 수신
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            arm(h)
            h.ultra()
            let b = await beat(h, "ultra received")
            #expect(b != nil, "울트라 수신 뒤 박동이 없다")
            #expect((b?.frames ?? 0) >= 7)
        }
        // 재생성(반론 R5 — 옮겨 실은 SCNView 가 새 창에서 그리는가)
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            h.world.gated = true
            h.startWorking()
            arm(h)
            #expect(h.controller.rebuildPanel(reason: .manual))
            let b = await beat(h, "rebuild")
            #expect(b != nil, "재생성 뒤 박동이 없다")
            #expect((b?.frames ?? 0) >= 7)
        }
    }

    @Test("HB3 그려야 하는데 씬이 떨어져 있으면 '몸 없음', 몸은 있는데 0 프레임이면 '렌더 루프 죽음'으로 적는다")
    func hb3HeartbeatFlagsBodyMissingAndStalledRenderer() async throws {
        typealias B = CheckOverlayController.RenderHeartbeat
        // 순수 판정
        func b(frames: UInt64, active: Bool = true, suspended: Bool = false, scene: Bool = true, visible: Bool = true) -> B {
            B(label: "x", frames: frames, renderActive: active, renderSuspended: suspended,
              viewMounted: true, sceneAttached: scene, windowVisible: visible)
        }
        #expect(b(frames: 0).rendererStalled)
        #expect(!b(frames: 3).rendererStalled)
        #expect(!b(frames: 0, suspended: true).rendererStalled, "정지 사유가 있는데 렌더 루프 죽음으로 적었다")
        #expect(!b(frames: 0, active: false).rendererStalled, "숨긴 창을 렌더 루프 죽음으로 적었다")
        #expect(!b(frames: 0, visible: false).rendererStalled, "다른 창에 가려진 창을 렌더 루프 죽음으로 적었다")
        #expect(b(frames: 9, scene: false).bodyMissing)
        #expect(!b(frames: 9, active: false, scene: false).bodyMissing)
        #expect(!b(frames: 9, suspended: true, scene: false).bodyMissing)

        // 실제 컨트롤러: 씬을 떼면 같은 줄이 '몸 없음'이 된다
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let mounted = await osrWaitUntil(maxPolls: 300) { osrFirstSCNView(in: h.panel.contentView) != nil }
        try #require(mounted, "SCNView 가 안 섰다")
        let scn = try #require(osrFirstSCNView(in: h.panel.contentView))
        let healthy = h.controller.recordRenderHeartbeat("probe", since: h.controller.engine.renderFrameCounter.count)
        #expect(healthy.viewMounted && healthy.sceneAttached && !healthy.bodyMissing, "기준선: \(healthy)")
        let scene = scn.scene
        scn.scene = nil
        let missing = h.controller.recordRenderHeartbeat("probe", since: h.controller.engine.renderFrameCounter.count)
        scn.scene = scene
        #expect(!missing.sceneAttached)
        #expect(missing.bodyMissing, "씬이 떨어졌는데 몸 없음으로 안 적었다: \(missing)")
        #expect(h.controller.lastRenderHeartbeat == missing)
    }

    @Test("HB4 수리 재확인 줄은 수리 뒤 그린 프레임 수를 적는다(반론 R5)")
    func hb4RepairVerifyRecordsFramesSinceRepair() throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.startWorking()
        h.world.degrade(h.panel)
        h.world.reapplyHeals = true
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
        #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .repaired(.reapplyCollectionBehavior))
        let counter = h.controller.engine.renderFrameCounter
        for _ in 0..<5 { counter.noteFrame() }
        #expect(h.controller.verifySpaceRepair(.reapplyCollectionBehavior) == true)
        #expect((h.controller.lastSpaceRepairFrames ?? 0) >= 5, "재확인 줄이 수리 뒤 프레임을 안 셌다")
    }

    @Test("HB5 실제 SceneKit 이 표시된 캐릭터를 그리면 계수기가 오른다",
          .enabled(if: CGDisplayIsAsleep(CGMainDisplayID()) == 0, "메인 화면이 자고 있다 — 실제 렌더러가 안 돈다"))
    func hb5RealRendererAdvancesTheCounter() async throws {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.startWorking()
        let mounted = await osrWaitUntil(maxPolls: 300) { osrFirstSCNView(in: h.panel.contentView) != nil }
        try #require(mounted, "SCNView 가 안 섰다")
        let counter = h.controller.engine.renderFrameCounter
        let start = counter.count
        let advanced = await osrWaitUntil(maxPolls: 150) { counter.count > start }
        print("HB5 frames start=\(start) now=\(counter.count)")
        #expect(advanced, "표시 중인 SCNView 가 3초 동안 한 프레임도 안 그렸다(계수기 배선 또는 렌더러)")
    }

    // MARK: T14 · T15 — H2 렌더 정지 안전밸브

    @Test("T14 화면 슬립 사유는 displaysAwake 가 true 일 때만 깨움 노티 없이 걷힌다")
    func t14ScreensAsleepReleasedOnlyByDisplayEvidence() {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.screensSleep()
        #expect(h.controller.engine.renderSuspended)
        h.world.displaysAwake = nil
        #expect(h.controller.reconcileStaleRenderSuspension() == false)
        #expect(h.controller.engine.renderSuspended, "모름(nil)인데 걷었다")
        h.world.displaysAwake = false
        #expect(h.controller.reconcileStaleRenderSuspension() == false)
        #expect(h.controller.engine.renderSuspended, "디스플레이가 자는데 걷었다")
        h.world.displaysAwake = true
        #expect(h.controller.reconcileStaleRenderSuspension())
        #expect(h.controller.engine.renderSuspended == false, "깨어 있는데 정지가 남았다")
        #expect(h.controller.renderSuspendReasons.isEmpty)
        // 잠금이 겹쳐 있으면 디스플레이 근거로는 잠금을 걷지 않는다(콘솔 판정이 '잠금'이면 정지 유지).
        h.screensSleep()
        h.lock()
        h.world.sessionUsable = false
        #expect(h.controller.reconcileStaleRenderSuspension())
        #expect(h.controller.renderSuspendReasons == [.screenLocked])
        #expect(h.controller.engine.renderSuspended)
    }

    @Test("T15 표시 전이 · peek · 울트라 시작이 깜빡임 tick 없이 걸린 화면 슬립 사유를 걷는다")
    func t15ShowPathsRunTheValve() {
        // 표시 전이
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            h.screensSleep()
            h.world.displaysAwake = nil
            h.startWorking()
            #expect(h.controller.engine.renderSuspended, "기준선: 근거가 없으면 표시 전이도 걷지 않는다")
            h.stopWorking()
            h.world.displaysAwake = true
            h.startWorking()
            #expect(h.controller.engine.renderSuspended == false, "표시 전이가 걸린 사유를 걷지 않았다")
        }
        // peek
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            h.screensSleep()
            h.world.displaysAwake = true
            h.poke()
            #expect(h.controller.isPeekArmed)
            #expect(h.controller.engine.renderSuspended == false, "peek 가 걸린 사유를 걷지 않았다")
        }
        // 울트라
        do {
            let h = OSRHarness()
            defer { h.tearDown() }
            h.screensSleep()
            h.world.displaysAwake = true
            h.ultra()
            #expect(h.controller.isUltraActive)
            #expect(h.controller.engine.renderSuspended == false, "울트라가 걸린 사유를 걷지 않았다")
        }
    }

    // MARK: T16 — 순수 판정

    @Test("T16 순수 판정: 재생성 근거는 '현재 Space 빠짐' 하나이고, 공개 신호와 엇갈리면 모름이다")
    func t16PureRules() {
        typealias P = OverlaySpaceProbe
        #expect(P.evaluate(spaces: [817, 4], current: 32, displaySpaceCount: 12)
                == .missingCurrentSpace(spaces: [817, 4], current: 32))
        #expect(P.evaluate(spaces: [], current: 4, displaySpaceCount: 12) == .missingCurrentSpace(spaces: [], current: 4),
                "v0.2.27 보드 모양(빈 소속)이 고장으로 안 읽힌다")
        #expect(P.evaluate(spaces: Array(1...12), current: 4, displaySpaceCount: 12)
                == .onCurrentSpace(memberCount: 12, displaySpaceCount: 12))
        #expect(P.evaluate(spaces: [817, 4], current: 4, displaySpaceCount: 12)
                == .onCurrentSpace(memberCount: 2, displaySpaceCount: 12), "일부만 빠진 창(현재 Space 있음)을 고장으로 읽었다")

        // 공개 신호: 새 창(isOnActiveSpace true)은 언제나 '있음' — 새 창의 빈 소속을 막는 자리.
        #expect(!P.publicSaysMissing(isVisible: false, isOnActiveSpace: true, inActiveSpaceList: false))
        #expect(!P.publicSaysMissing(isVisible: true, isOnActiveSpace: true, inActiveSpaceList: true))
        #expect(P.publicSaysMissing(isVisible: true, isOnActiveSpace: false, inActiveSpaceList: false))
        #expect(!P.publicSaysMissing(isVisible: true, isOnActiveSpace: false, inActiveSpaceList: true))
        #expect(P.publicSaysMissing(isVisible: false, isOnActiveSpace: false, inActiveSpaceList: false),
                "내려 둔 망가진 창을 공개 신호가 못 본다")

        let degraded = P.SkyLightReading(spaces: [817, 4], current: 32, displaySpaceCount: 12)
        let fine = P.SkyLightReading(spaces: Array(1...12), current: 4, displaySpaceCount: 12)
        #expect(P.combine(skyLightAvailable: true, reading: degraded, publicMissing: true)
                == .missingCurrentSpace(spaces: [817, 4], current: 32))
        #expect(P.combine(skyLightAvailable: true, reading: degraded, publicMissing: false) == nil,
                "비공개·공개가 엇갈렸는데 고장으로 읽었다(반론 D3)")
        #expect(P.combine(skyLightAvailable: true, reading: fine, publicMissing: true)
                == .onCurrentSpace(memberCount: 12, displaySpaceCount: 12))
        #expect(P.combine(skyLightAvailable: true, reading: nil, publicMissing: true) == nil, "질의 실패를 고장으로 읽었다")
        #expect(P.combine(skyLightAvailable: false, reading: nil, publicMissing: true)
                == .missingCurrentSpace(spaces: nil, current: nil), "심볼이 없을 때 공개 신호로 안 돈다")
        #expect(P.combine(skyLightAvailable: false, reading: nil, publicMissing: false)
                == .onCurrentSpace(memberCount: nil, displaySpaceCount: nil))

        typealias C = CheckOverlayController
        #expect(C.spaceCheckGate(intendedVisible: false, orderedIn: true, sessionUsable: true, busy: false) == .notIntendedVisible)
        #expect(C.spaceCheckGate(intendedVisible: true, orderedIn: false, sessionUsable: true, busy: false) == .notOrderedIn)
        #expect(C.spaceCheckGate(intendedVisible: true, orderedIn: true, sessionUsable: false, busy: false) == .sessionUnusable)
        #expect(C.spaceCheckGate(intendedVisible: true, orderedIn: true, sessionUsable: true, busy: true) == .busy)
        #expect(C.spaceCheckGate(intendedVisible: true, orderedIn: true, sessionUsable: true, busy: false) == nil)
        let first = C.spaceMissVerdict(presence: OSRWorld.missing, priorMissStreak: 0)
        #expect(first.streak == 1 && first.repair == false, "놓침 한 번에 고친다")
        let second = C.spaceMissVerdict(presence: OSRWorld.missing, priorMissStreak: 1)
        #expect(second.streak == 2 && second.repair)
        let back = C.spaceMissVerdict(presence: OSRWorld.healthy, priorMissStreak: 1)
        #expect(back.streak == 0 && back.repair == false)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let three = [t0, t0.addingTimeInterval(10), t0.addingTimeInterval(20)]
        #expect(!C.repairBudgetAllows(three, limit: 3, now: t0.addingTimeInterval(30)))
        #expect(C.repairBudgetAllows(three, limit: 3, now: t0.addingTimeInterval(3601)))
    }

    // MARK: T17 — 배선

    @Test("T17 Space 전환은 0.75초 확인을 예약하고, 취소된 옛 확인은 깨어나도 아무것도 안 한다")
    func t17WiringAndCancelledChecksStayQuiet() async {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.world.gated = true
        h.startWorking()                      // 표시가 확인 하나를 예약한다(게이트에 선다)
        let parkedShow = await osrWaitUntil { h.world.parkedSleepers == 1 }
        #expect(parkedShow, "표시 전이가 확인을 예약하지 않았다")
        h.world.degrade(h.panel)
        let baseline = h.world.presenceCalls

        h.postSpaceChange()
        h.postSpaceChange()                   // 둘째가 첫째를 취소한다
        let parked = await osrWaitUntil { h.world.parkedSleepers == 3 }
        #expect(parked)
        #expect(h.world.sleepRequests.allSatisfy { $0 == CheckOverlayController.spaceCheckDelaySeconds })
        h.world.releaseOne()                  // 표시 확인(취소됨)
        h.world.releaseOne()                  // 첫 Space 확인(취소됨)
        osrSpin(0.05)
        #expect(h.world.presenceCalls == baseline, "취소된 확인이 깨어나 소속을 물었다(취소 = 즉시 실행 함정)")
        h.world.releaseOne()                  // 살아 있는 확인 → 놓침 1회 → 0.75초 더 잔다
        let missed = await osrWaitUntil { h.controller.spaceMissStreak == 1 && h.world.parkedSleepers == 1 }
        #expect(missed, "살아 있는 확인이 돌지 않았거나 두 번째 확인을 예약하지 않았다")
        #expect(h.world.presenceCalls == baseline + 1)
        h.world.releaseOne()                  // 두 번째 확인 → 1단 → 재확인 예약
        let repaired = await osrWaitUntil { h.world.reapplyCalls == 1 }
        #expect(repaired)

        // 해제 쪽 사건들도 확인을 예약한다(원인 후보 사건 — 진단 겸).
        let posts: [@MainActor () -> Void] = [h.unlock, h.screensWake, h.sessionBecome, h.screenParametersChanged]
        for post in posts {
            let before = h.world.sleepRequests.count
            post()
            let scheduled = await osrWaitUntil { h.world.sleepRequests.count > before }
            #expect(scheduled, "사건이 소속 확인을 예약하지 않았다")
        }
    }

    @Test("T17b 실제 수면(취소되면 즉시 돌아온다)에서도 취소된 확인은 실행되지 않는다")
    func t17bProductionSleepCancellationDoesNotRunTheCheck() async {
        let h = OSRHarness()
        defer { h.tearDown() }
        h.controller.spaceCheckSleep = { try? await Task.sleep(for: .seconds($0)) }
        h.startWorking()
        h.world.degrade(h.panel)
        let baseline = h.world.presenceCalls
        h.postSpaceChange()
        h.postSpaceChange()   // 첫 예약의 Task.sleep 이 취소로 즉시 깨어난다
        osrSpin(0.2)
        #expect(h.world.presenceCalls == baseline, "취소된 확인이 즉시 실행됐다")
    }
}

/// 격발 상태와 창 모양이 서로 맞는가. 격발 중이면 화면만 한 창 · 클릭 통과 못 박기 · 마감이 다 있어야 하고, 아니면 작은 창 ·
/// 못 박기 없음이어야 한다. "isUltraActive 는 false 인데 창은 화면만 하다"(원복할 사람이 없는 격발)를 잡는다.
@MainActor
func osrExpectUltraCoherent(_ h: OSRHarness, _ stage: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let c = h.controller
    let small = h.panel.frame.size == CheckOverlayController.panelSize
    if c.isUltraActive {
        #expect(!small, "\(stage): 격발 중인데 창이 작다", sourceLocation: sourceLocation)
        #expect(c.pinnedIgnoresMouseEventsValue == true, "\(stage): 격발 중인데 클릭 통과 못 박기가 없다", sourceLocation: sourceLocation)
        #expect(c.ultraDeadline != nil, "\(stage): 격발 중인데 마감이 없다", sourceLocation: sourceLocation)
        #expect(c.engine.isUltraActive, "\(stage): 컨트롤러는 격발 중인데 엔진은 아니다", sourceLocation: sourceLocation)
    } else {
        #expect(small, "\(stage): 격발이 끝났는데 창이 화면만 하다 \(h.panel.frame)", sourceLocation: sourceLocation)
        #expect(c.pinnedIgnoresMouseEventsValue == nil, "\(stage): 격발이 끝났는데 못 박기가 남았다", sourceLocation: sourceLocation)
        #expect(!c.engine.isUltraActive, "\(stage): 격발이 끝났는데 엔진은 격발 중이다", sourceLocation: sourceLocation)
    }
}

/// 숨김 + "이번 고장에서 1단을 이미 썼다"(재확인 전에 근무가 끝났다)를 만든다. 망가진 옛 창을 돌려준다.
@MainActor
private func osrSpendRungOneThenHide(_ h: OSRHarness) async throws -> NSPanel {
    h.world.gated = true
    h.startWorking()
    let old = h.panel
    h.world.degrade(old)
    #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .miss(streak: 1))
    #expect(h.controller.runSpaceCheck(event: .spaceChanged) == .repaired(.reapplyCollectionBehavior))
    h.stopWorking()
    let hidden = await osrWaitUntil { !old.isVisible }
    osrSpin(CheckOverlayController.farewellHideDeadline + 0.15)   // 인사 숨김 타이머가 뒤의 peek 를 내리지 않게
    try #require(hidden && !old.isVisible, "숨김 준비가 안 됐다")
    try #require(h.controller.spaceRepairStage == .reapplyCollectionBehavior)
    try #require(h.panel === old)
    return old
}

// MARK: - 진짜 윈도우 서버 시험(자기 시험 창만 · 빼기만 · Space 전환 없음)

/// 시험 전용 고장 주입: 자기 창의 Space 소속을 SkyLight 로 뺀다(대표 맥 15027 과 같은 모양 — sticky 비트는 그대로,
/// 올라가 있음, 현재 Space 빠짐). 실측 규칙: 올라가 있는 동안은 빼기가 무시되고, 전부를 한 번에 빼면 무시된다.
enum OSRSkyLightFault {
    typealias RemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
    static let remove: RemoveWindowsFromSpaces? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let raw = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else { return nil }
        return unsafeBitCast(raw, to: RemoveWindowsFromSpaces.self)
    }()

    static var available: Bool { OverlaySpaceProbe.skyLightAvailable && remove != nil }

    /// 창을 내리고 → 현재가 아닌 Space 를 둘만 남기고 빼고 → 현재 Space 를 빼고 → 다시 올린다. 들어가지 않았으면 false.
    @MainActor
    static func dropCurrentSpace(of panel: NSWindow) async -> Bool {
        guard let sy = OverlaySpaceProbe.symbols, let remove,
              let before = OverlaySpaceProbe.skyLightReading(windowNumber: panel.windowNumber),
              before.spaces.contains(before.current)
        else { return false }
        let wid = NSNumber(value: panel.windowNumber)
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(200))
        let others = before.spaces.filter { $0 != before.current }
        let drop = Array(others.dropFirst(2))
        if !drop.isEmpty {
            remove(sy.mainConnection(), [wid] as CFArray, drop.map { NSNumber(value: $0) } as CFArray)
            try? await Task.sleep(for: .milliseconds(150))
        }
        remove(sy.mainConnection(), [wid] as CFArray, [NSNumber(value: before.current)] as CFArray)
        try? await Task.sleep(for: .milliseconds(150))
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(400))
        guard panel.isVisible, let after = OverlaySpaceProbe.skyLightReading(windowNumber: panel.windowNumber) else {
            return false
        }
        return !after.spaces.contains(after.current)
    }
}

/// 화면이 깨어 있고 SkyLight(읽기 + 시험용 빼기)가 있을 때만 돈다(화면이 자면 스위트가 얼어붙는 전례가 있다).
let osrRealWindowServerApplicable: Bool = OSRSkyLightFault.available && CGDisplayIsAsleep(CGMainDisplayID()) == 0

@Suite(
    "OverlaySpaceRealWindowServer",
    .serialized,
    .enabled(if: osrRealWindowServerApplicable, "SkyLight 심볼이 없거나 메인 화면이 자고 있다 — 진짜 윈도우 서버 시험을 건너뛴다")
)
@MainActor
struct OverlaySpaceRealWindowServerTests {

    /// 진짜 질의 · 짧은 실제 수면(커밋 25~55ms 보다 넉넉하게)으로 바꾼 하네스.
    private func realHarness(function: String = #function) -> OSRHarness {
        let h = OSRHarness(function: function)
        h.controller.spacePresence = { OverlaySpaceProbe.presence(of: $0) }
        h.controller.spaceCheckSleep = { _ in try? await Task.sleep(for: .milliseconds(300)) }
        h.controller.panelSpaceRepair = { OverlayPanelRepair.reapplyCollectionBehavior($0) }
        return h
    }

    /// 창이 현재 Space 에 있고 소속 수가 `full` 이 될 때까지 기다린다.
    private func waitHealthy(_ h: OSRHarness, full: Int?, timeout polls: Int = 300) async -> OverlaySpaceProbe.SkyLightReading? {
        var last: OverlaySpaceProbe.SkyLightReading?
        let ok = await osrWaitUntil(maxPolls: polls) {
            guard let reading = OverlaySpaceProbe.skyLightReading(windowNumber: h.panel.windowNumber) else { return false }
            last = reading
            return reading.spaces.contains(reading.current) && (full == nil || reading.spaces.count == full)
        }
        return ok ? last : nil
    }

    /// 시험의 전제 — 시험 창이 놓인 화면의 현재 Space 와 그 화면의 Space 수(리뷰 지적 5).
    ///
    /// 이 스위트는 사용자가 쓰는 맥에서 돈다. 시험 도중 사용자가 Space 를 옮기거나(주입이 남겨 둔 두 Space 로 가면 "없음" 단언이
    /// 깨진다) 전체 화면을 열고 닫으면(Space 수가 바뀌어 `full` 비교가 깨진다) 전제가 무너진다 — 그때는 실패가 아니라 **취소**다.
    private struct SpaceLayout: Equatable, CustomStringConvertible {
        let current: UInt64
        let displaySpaceCount: Int?
        var description: String { "current=\(current) spaces=\(displaySpaceCount.map(String.init) ?? "?")" }
    }

    private func layout(of panel: NSWindow) -> SpaceLayout? {
        OverlaySpaceProbe.skyLightReading(windowNumber: panel.windowNumber)
            .map { SpaceLayout(current: $0.current, displaySpaceCount: $0.displaySpaceCount) }
    }

    /// 단언 직전에 부른다: 전제가 그대로가 아니면 취소한다.
    private func cancelIfLayoutChanged(_ h: OSRHarness, since baseline: SpaceLayout) throws {
        let now = layout(of: h.panel)
        guard now == baseline else {
            print("OverlaySpaceRealWindowServer: 시험 도중 Space 구성이 바뀌었다(\(baseline) → \(now.map(\.description) ?? "nil")) — 취소")
            try Test.cancel("the Space layout changed during the test (user activity)")
        }
    }

    /// 표시 → 첫 커밋 뒤 소속이 현재 Space 를 담을 때까지. 안 되면 이 맥에서는 적용할 수 없다(건너뜀).
    /// 건강한 소속 수와, 그때의 Space 구성(전제)을 돌려준다.
    private func showAndMeasure(_ h: OSRHarness) async throws -> (full: Int, layout: SpaceLayout) {
        h.startWorking()
        guard let healthy = await waitHealthy(h, full: nil, timeout: 100) else {
            print("OverlaySpaceRealWindowServer: 새로 띄운 창이 현재 Space 를 끝내 못 받았다 — 건너뜀")
            try Test.cancel("fresh panel never reported the current Space")
        }
        return (healthy.spaces.count, SpaceLayout(current: healthy.current, displaySpaceCount: healthy.displaySpaceCount))
    }

    /// 주입하는 동안은 컨트롤러 자신의 확인이 끼어들지 않게 세션을 '못 씀'으로 둔다(주입 직후 단언이 이미 고쳐진 창을 보지 않게).
    /// 시험이 고칠 차례에 `sessionUsable = true` 로 되돌린다.
    private func inject(_ h: OSRHarness, baseline: SpaceLayout) async throws {
        h.world.sessionUsable = false
        guard await OSRSkyLightFault.dropCurrentSpace(of: h.panel) else {
            try cancelIfLayoutChanged(h, since: baseline)
            print("OverlaySpaceRealWindowServer: 윈도우 서버가 주입한 소속 빼기를 받지 않았다(단일 Space 맥 등) — 건너뜀")
            try Test.cancel("injection did not take")
        }
        try cancelIfLayoutChanged(h, since: baseline)
    }

    /// 수리 재확인이 끝날 때까지(healed 가 정해질 때까지) 기다린다.
    private func waitVerdict(_ h: OSRHarness) async -> CheckOverlayController.SpaceRepairVerdict? {
        _ = await osrWaitUntil(maxPolls: 200) { h.controller.lastSpaceRepairVerdict?.healed != nil }
        return h.controller.lastSpaceRepairVerdict
    }

    @Test("실제: 주입한 소속 상실을 감지하고, 실제 경로(Space 전환 확인)의 1단이 현재 Space 를 되돌린다 · 내렸다 올리기로는 안 낫는다")
    func realDegradationIsDetectedAndHealedByTheScheduledPath() async throws {
        let h = realHarness()
        defer { h.tearDown() }
        let (full, baseline) = try await showAndMeasure(h)
        try await inject(h, baseline: baseline)
        let panel = h.panel
        #expect(OverlaySpaceProbe.presence(of: panel)?.isMissing == true, "감지기가 실제 고장을 못 봤다")
        #expect(OverlaySpaceProbe.publicSaysMissing(panel), "공개 신호가 실제 고장을 못 봤다")
        #expect(panel.isVisible, "AppKit 은 올라가 있다고 믿어야 한다(대표 맥과 같은 모양)")
        // 내렸다 올리기는 수리가 아니다(16:42 실측 · v0.2.27).
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(200))
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(300))
        try cancelIfLayoutChanged(h, since: baseline)
        #expect(OverlaySpaceProbe.presence(of: panel)?.isMissing == true, "다시 올리기가 저절로 고쳤다 — 주입이 실측 모양이 아니다")

        h.world.sessionUsable = true
        h.controller.scheduleSpaceCheck(.spaceChanged)
        let healed = await waitHealthy(h, full: full)
        let verdict = await waitVerdict(h)
        try cancelIfLayoutChanged(h, since: baseline)
        #expect(healed != nil, "실제 경로가 현재 Space 를 되돌리지 못했다")
        if let healed { #expect(healed.spaces.count == full) }
        // 리뷰 지적 4: 고친 것이 **1단**이어야 한다. 1단이 실제 창에서 죽으면 2단(재생성)이 대신 고쳐 예전엔 이 시험이 초록이었다
        // (flush 를 지운 변이로 재현) — 그러면 모든 고장이 R1 위험·시간당 3회 상한을 지닌 재생성으로 간다.
        #expect(verdict == .init(rung: .reapplyCollectionBehavior, healed: true),
                "1단(collectionBehavior 재적용)이 실제 창을 못 고쳤다: \(String(describing: verdict))")
        #expect(h.controller.panelRebuilds == 0, "1단이 못 고쳐 재생성으로 넘어갔다")
        #expect(h.panel === panel)
        print("OverlaySpaceRealWindowServer scheduled: full=\(full) verdict=\(String(describing: verdict)) rebuilds=\(h.controller.panelRebuilds)")
    }

    @Test("실제: 1단(collectionBehavior 재적용) 하나만으로 실제 소속에 현재 Space 가 돌아온다 — 2단 없이")
    func realReapplyAloneRestoresMembership() async throws {
        let h = realHarness()
        defer { h.tearDown() }
        let (full, baseline) = try await showAndMeasure(h)
        try await inject(h, baseline: baseline)
        let panel = h.panel
        try #require(OverlaySpaceProbe.presence(of: panel)?.isMissing == true, "주입 뒤인데 감지기가 '있음'이라 한다")
        let behavior = panel.collectionBehavior
        OverlayPanelRepair.reapplyCollectionBehavior(panel)
        #expect(panel.collectionBehavior == behavior, "1단이 원래 collectionBehavior 를 되돌려 놓지 않았다")
        let healed = await waitHealthy(h, full: full, timeout: 100)
        try cancelIfLayoutChanged(h, since: baseline)
        #expect(healed != nil, "1단이 실제 창의 현재 Space 를 되돌리지 못했다(두 대입이 따로 커밋되지 않았다?)")
        #expect(h.panel === panel)
        #expect(h.controller.panelRebuilds == 0)
        print("OverlaySpaceRealWindowServer reapply: full=\(full) healed=\(String(describing: healed))")
    }

    @Test("실제: 재생성한 새 창의 실제 소속에 현재 Space 가 들고, 그 화면의 Space 전부다")
    func realRebuiltPanelJoinsTheCurrentSpace() async throws {
        let h = realHarness()
        defer { h.tearDown() }
        let (full, baseline) = try await showAndMeasure(h)
        try await inject(h, baseline: baseline)
        let old = h.panel
        let content = try #require(old.contentView)
        #expect(h.controller.rebuildPanel(reason: .manual))
        #expect(h.panel !== old)
        let healed = await waitHealthy(h, full: full)
        try cancelIfLayoutChanged(h, since: baseline)
        #expect(healed != nil, "새 창이 현재 Space 를 못 받았다")
        if let healed {
            #expect(healed.spaces.contains(healed.current))
            #expect(healed.spaces.count == full)
        }
        #expect(h.panel.contentView === content)
        #expect(content.window === h.panel)
        #expect(!old.isVisible)
        #expect(OverlaySpaceProbe.presence(of: h.panel) == .onCurrentSpace(memberCount: full, displaySpaceCount: healed?.displaySpaceCount))
        print("OverlaySpaceRealWindowServer rebuild: full=\(full) new=\(String(describing: healed))")
    }

    @Test("실제: 숨은 채 망가진 창은 다음 표시(근무 시작) 직전 1단으로 고쳐져 현재 Space 에 뜬다")
    func realHiddenDegradedPanelIsFixedBeforeTheNextShow() async throws {
        let h = realHarness()
        defer { h.tearDown() }
        let (full, baseline) = try await showAndMeasure(h)
        try await inject(h, baseline: baseline)
        h.stopWorking()
        let hidden = await osrWaitUntil(maxPolls: 200) { !h.panel.isVisible }
        try #require(hidden, "숨김 준비가 안 됐다")
        try cancelIfLayoutChanged(h, since: baseline)
        guard OverlaySpaceProbe.presence(of: h.panel)?.isMissing == true else {
            print("OverlaySpaceRealWindowServer: 숨은 망가진 창을 감지기가 못 봤다 — 이 맥에서 숨은 창 판정이 다르다, 건너뜀")
            try Test.cancel("hidden degraded panel not reported missing")
        }
        osrSpin(CheckOverlayController.farewellHideDeadline + 0.15)
        h.world.sessionUsable = true
        let panel = h.panel
        h.startWorking()
        #expect(h.panel.isVisible)
        let healed = await waitHealthy(h, full: full)
        let verdict = await waitVerdict(h)
        try cancelIfLayoutChanged(h, since: baseline)
        #expect(healed != nil, "표시 직전 수리 뒤에도 현재 Space 에 없다")
        // 리뷰 지적 4: 표시 직전 수리도 1단이 실제로 고쳐야 한다(숨은 창에서 — 프로브 실측과 같은 모양).
        #expect(verdict == .init(rung: .reapplyCollectionBehavior, healed: true),
                "표시 직전 1단이 실제 창을 못 고쳤다: \(String(describing: verdict))")
        #expect(h.controller.panelRebuilds == 0, "표시 직전 1단이 못 고쳐 재생성으로 넘어갔다")
        #expect(h.panel === panel)
        print("OverlaySpaceRealWindowServer preShow: full=\(full) rebuilds=\(h.controller.panelRebuilds) verdict=\(String(describing: verdict))")
    }
}
