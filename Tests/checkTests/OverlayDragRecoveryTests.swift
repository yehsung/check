import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check

// 실사용 신고("캐릭터가 드래그로 아예 안 움직인다 / 근무 종료-시작으로도 안 풀린다 / 울트라를 맞으면 풀린다")의
// 재현·회귀 방어.
//
// 이 파일이 지키는 것은 하나다: **캐릭터를 만지는 입력 사슬은 어떤 값이 굳어도 다음 마우스 이벤트에서
// 스스로 풀린다.** 사슬은 이렇게 생겼다.
//
//   마우스 이동 → (전역 or 로컬 모니터) → updateHitThrough → ignoresMouseEvents=false
//               → 패널이 클릭을 받음 → handleMouseDown → 드래그
//
// 앞쪽 값이 하나라도 굳으면 증상은 언제나 같다 — "캐릭터가 아무 반응이 없다". 그리고 지금까지 그 굳음을
// 풀어 주던 유일한 사건이 **다음 울트라**였다(격발 시작·종료가 못 박기·투영 캐시·격발 상태를 한꺼번에
// 리셋한다). 근무 종료·재시작은 그 값들을 건드리지 않는다 — 신고의 세 문장이 정확히 그 구조다.
//
// 조사 중 같은 머신에서 잰 수치는 각 테스트 주석에 남긴다(추측과 실측을 섞지 않기 위해).

// MARK: - 헬퍼

/// 화면에 절대 올리지 않는 창에 SCNView 를 담아 엔진에 붙인다.
/// `hasAttachedView` 는 `attachedView?.window != nil` 만 보므로 orderFront 는 필요 없다 —
/// 이 저장소는 테스트가 데스크톱을 캐릭터로 도배한 사고가 있어 창을 안 띄우는 길이 있으면 그 길로 간다.
@MainActor
private func attachOffscreenCharacter(
    to engine: ReactionEngine,
    viewSize: NSSize,
    windowOrigin: NSPoint = NSPoint(x: 300, y: 300)
) throws -> (NSWindow, SCNView) {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let root = scene.rootNode
    let wrapper = try #require(
        root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let view = SCNView(frame: NSRect(origin: .zero, size: viewSize))
    view.scene = scene
    let window = NSWindow(
        contentRect: NSRect(origin: windowOrigin, size: viewSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.alphaValue = 0
    window.contentView = view
    engine.attach(node: wrapper, sceneRoot: root, view: view)
    return (window, view)
}

/// 뷰 중앙(= 캐릭터가 서 있는 자리)의 스크린 좌표.
@MainActor
private func screenCenter(of view: SCNView) -> NSPoint {
    let local = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
    return view.window!.convertPoint(toScreen: view.convert(local, to: nil))
}

@MainActor
private func isolatedDragDefaults() -> UserDefaults {
    let name = "check-drag-recovery-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// 실제 패널 + 실제 SCNView 를 얹은 컨트롤러 픽스처. 몸체 판정(A1)이 **진짜 지오메트리**로 도는 상태여야
/// 이 파일의 주장이 성립한다 — 뷰가 없으면 `withinBody` 가 패널 프레임 폴백으로 떨어져 결함이 숨는다.
@MainActor
private final class DragRig {
    let engine = ReactionEngine()
    let store: WorkTimerStore
    let controller: CheckOverlayController

    init(ultraDeadlineSeconds: Double = 600, sleeps: (@Sendable (Double) async -> Void)? = nil) {
        store = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
            defaults: isolatedDragDefaults(),
            workspaceNotifications: nil
        )
        controller = CheckOverlayController(
            store: store,
            notificationCenter: NotificationCenter(),
            engine: engine,
            defaults: isolatedDragDefaults(),
            workspaceNotifications: nil,
            ultraDurationSeconds: 600,
            ultraDeadlineSeconds: ultraDeadlineSeconds
        )
        if let sleeps {
            controller.ultraSleep = sleeps
            controller.ultraWatchdogSleep = sleeps
        }
    }

    /// 근무중을 **스토어에서부터** 세운다(프로덕션에 존재하는 조합만 만든다 — UltraPokeOverlayTests 와 같은 규약).
    func startWorking() {
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        controller.updateWorking(true)
        layout()
    }

    func stopWorking() {
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        controller.updateWorking(false)
        layout()
    }

    /// SwiftUI 가 3D 뷰를 실제 크기로 붙이게 한다(실측: 패널 프레임 변경과 **같은 턴**에 SCNView 크기가 따라온다 —
    /// 격발 시작 직후 이미 1058×1058, 종료 직후 이미 140×170 이었다).
    func layout() {
        controller.panel.contentView?.layoutSubtreeIfNeeded()
    }

    func receiveUltra(id: String = "u1") {
        controller.handleReceivedPokes([
            ReceivedPoke(id: id, fromName: "이유성", createdAt: Date(), kind: .ultra)
        ])
        layout()
    }

    var bodyPoint: NSPoint {
        NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.midY)
    }

    /// 실제 드래그 그대로: 몸체에서 눌러 끌면 패널이 따라오는가(값으로 본다).
    func dragMovesPanel() -> Bool {
        let before = controller.panel.frame.origin
        let start = bodyPoint
        let end = NSPoint(x: start.x - 40, y: start.y - 40)
        controller.handleMouseDown(at: start)
        controller.handleMouseDragged(at: end)
        controller.handleMouseUp(at: end)
        return controller.panel.frame.origin != before
    }

    func teardown() {
        stopWorking()
        controller.panel.orderOut(nil)
    }
}

// MARK: - 원인 1: 몸체 투영 캐시는 **뷰 크기**에 매달려 있다(엔진 단위 실측)

/// 울트라는 SCNView 크기를 (화면 짧은 변 × 0.98) 정사각으로 바꿨다가 되돌린다(이 머신 1920×1080 에서
/// 140×170 → **1058×1058**). 엔진의 몸체 투영 캐시는 그 크기에서 계산한 **뷰-로컬 rect** 인데,
/// 처음에는 그 rect 를 크기와 무관하게 무기한 들고 있었다.
///
/// **그때 실측한 값**(이 테스트의 원형): 926 정사각에서 캐시를 채운 뒤 140×170 으로 줄이면
/// `isBodyAtScreenPoint(뷰 중앙)` 이 **false** 였다 — 캐릭터 정중앙조차 몸체가 아니라는 답이고,
/// 클릭·드래그가 통째로 죽는다. `invalidateBodyHitCache()` 를 부르면 곧바로 true 로 돌아왔다.
/// 즉 판정 자체는 멀쩡했고 **캐시 하나가 거짓말**이었다.
///
/// 지금은 캐시의 열쇠가 **계산할 때의 뷰 크기**라 그 상태가 성립하지 않는다: 크기가 달라지면 캐시를
/// 아예 안 쓴다. 그래서 이 테스트는 "무효화를 아무도 안 불러도 스스로 낫는가"를 못 박는다 —
/// 무효화 호출에 기대는 방어는 순서(격발 종료는 invalidate → setFrame 순이다)에 매달려 있었다.
@MainActor
@Test
func bodyProjectionCacheHealsItselfWhenViewSizeChanges() throws {
    let engine = ReactionEngine()
    let (window, view) = try attachOffscreenCharacter(to: engine, viewSize: NSSize(width: 926, height: 926))

    #expect(engine.isBodyAtScreenPoint(screenCenter(of: view)), "큰 뷰(격발 크기)에서 캐시가 박힌다")

    window.setFrame(NSRect(x: 300, y: 300, width: 140, height: 170), display: false)
    view.frame = NSRect(x: 0, y: 0, width: 140, height: 170)

    // ★ 아무도 invalidateBodyHitCache() 를 부르지 않는다. 그래도 몸체 판정이 살아 있어야 한다.
    #expect(
        engine.isBodyAtScreenPoint(screenCenter(of: view)),
        "뷰 크기가 바뀌면 옛 투영 캐시는 저절로 버려져야 한다(예전엔 여기서 false = 드래그·클릭 전멸)"
    )

    // 반대 방향(작은 뷰 → 큰 뷰)도 같은 이유로 성립해야 한다.
    window.setFrame(NSRect(x: 300, y: 300, width: 926, height: 926), display: false)
    view.frame = NSRect(x: 0, y: 0, width: 926, height: 926)
    #expect(engine.isBodyAtScreenPoint(screenCenter(of: view)), "되돌아가도 마찬가지다")
    window.contentView = nil
}

/// 같은 성질을 **끝에서 끝까지**(격발 → 걷힘 → 드래그) 한 번 더 못 박는다. 순서는 실사용 그대로다:
/// 격발 중(전체화면)에 히트-스루 문이 한 번 두드려져 캐시가 큰 뷰로 채워지고 → 격발이 걷히고 → 사용자가 끈다.
///
/// **그리고 컨트롤러의 두 번째 겹**(패널 크기가 달라지면 묻기 전에 캐시를 버린다)이 살아 있는지 값으로 본다.
/// 엔진이 스스로 키잉하므로 이 겹은 동작으로는 관측되지 않는다 — 그래서 이 단언이 없으면 겹이 조용히
/// 사라져도 아무도 모른다(두 겹을 두기로 한 결정이 그대로 증발한다).
@MainActor
@Test
func dragSurvivesBodyHitCacheFilledWhileFullScreen() {
    let rig = DragRig()
    rig.startWorking()
    #expect(rig.dragMovesPanel(), "기준선: 평시엔 드래그가 된다")
    let smallPanel = rig.controller.panel.frame.size
    rig.controller.updateHitThrough(at: rig.bodyPoint)
    #expect(rig.controller.bodyHitCacheSizeValue == smallPanel, "평시 크기에서 물어봤다고 기록한다")

    rig.receiveUltra()
    #expect(rig.controller.isUltraActive)
    // 격발 중 히트-스루 문 두드리기 = 이 순간 캐시가 **전체화면 크기**로 채워진다.
    rig.controller.updateHitThrough(at: rig.bodyPoint)
    #expect(
        rig.controller.bodyHitCacheSizeValue == rig.controller.panel.frame.size,
        "격발 크기로 갱신됐다 = 두 번째 겹이 실제로 돌았다"
    )

    rig.controller.endUltraTakeover()
    rig.layout()
    #expect(rig.dragMovesPanel(), "격발이 걷힌 뒤에는 드래그가 살아 있어야 한다")
    #expect(rig.controller.bodyHitCacheSizeValue == smallPanel, "평시 크기로 되돌아왔다")
    rig.teardown()
}

// MARK: - 원인 2: 우리 앱이 활성이면 **전역 모니터가 침묵한다**

/// 히트-스루 기계의 유일한 입구가 전역 mouseMoved 모니터였다. 그런데 전역 모니터는 "남의 앱으로 배달되는
/// 이벤트"만 본다 — 실측(같은 머신, mouseMoved 12건 합성):
///   · 우리 앱 비활성: global=13 / local=0
///   · 우리 앱 **활성**: **global=0** / local=13
///   · 사용자가 다른 앱을 클릭: global 회복
/// 그리고 accessory 앱은 **창을 닫아도 활성이 풀리지 않는다**(실측: 창을 닫고 2초 뒤에도 isActive=true,
/// 다른 앱을 클릭한 순간에야 false). 설정 창은 `NSApp.activate()` 로 명시적으로 활성화하므로,
/// 로컬 모니터가 없으면 "설정을 한 번 열었더니 캐릭터가 안 움직인다"가 되고 **근무 종료·재시작으로도 안 풀린다**
/// (그 경로는 침묵 중인 전역 모니터를 다시 달 뿐이다).
@MainActor
@Test
func hitThroughHasALocalMonitorSoItSurvivesOurOwnAppBeingActive() {
    let rig = DragRig()
    #expect(rig.controller.hasLocalMouseMoveMonitor == false, "숨김 상태에선 모니터가 없다")

    rig.startWorking()
    #expect(rig.controller.hasMouseMoveMonitor, "전역: 다른 앱이 활성인 평시의 입구")
    #expect(rig.controller.hasLocalMouseMoveMonitor, "로컬: 우리 앱이 활성인 구간의 유일한 입구")

    rig.stopWorking()
    #expect(rig.controller.hasMouseMoveMonitor == false)
    #expect(rig.controller.hasLocalMouseMoveMonitor == false, "숨기면 둘 다 뗀다(누수 금지)")
    rig.controller.panel.orderOut(nil)
}

// MARK: - 원인 3: 상한을 넘긴 격발은 **다음 마우스 이벤트에서** 스스로 풀린다

/// 이 기능의 유일한 치명 사고 모드는 "격발이 영영 안 걷힘"이다. 그때 `isUltraActive` 는 true 로 남고
/// `handleMouseDown` · `withinBody` 가 **둘 다** 드래그를 거부하며, 클릭 통과도 true 로 못 박힌 채다.
/// 정상 타이머(ultraTask)와 워치독(ultraWatchdogTask)이 **둘 다 죽은 세계**를 여기서 실제로 만든다
/// (두 수면을 이 테스트 안에서 절대 깨지 않게 주입 — 아무도 밖에서 밀어 주지 않는다).
/// 그 세계에서도 사용자가 캐릭터 위로 마우스를 움직이는 순간 격발이 걷히고 드래그가 돌아와야 한다.
@MainActor
@Test
func overstayedUltraReleasesItselfOnTheNextMouseEvent() {
    // 마감이 이미 지난 격발(=0초 상한)로 만들고, 두 타이머는 영영 재운다.
    let blocked: @Sendable (Double) async -> Void = { _ in
        try? await Task.sleep(for: .seconds(600))
    }
    let rig = DragRig(ultraDeadlineSeconds: 0, sleeps: blocked)
    rig.startWorking()
    rig.receiveUltra()
    #expect(rig.controller.isUltraActive, "격발이 섰다(그리고 아무 타이머도 깨지 않는다)")
    #expect(rig.controller.pinnedIgnoresMouseEventsValue == true)

    // 사용자가 캐릭터 위로 마우스를 움직인다 — 그것만으로 풀려야 한다.
    rig.controller.updateHitThrough(at: rig.bodyPoint)
    rig.layout()

    #expect(rig.controller.isUltraActive == false, "상한을 넘긴 격발은 마우스 이벤트에서 스스로 걷힌다")
    #expect(rig.controller.pinnedIgnoresMouseEventsValue == nil, "못 박기도 함께 풀린다")
    #expect(rig.dragMovesPanel(), "드래그가 돌아온다")
    rig.teardown()
}

/// 반대쪽 못 박기 — **마감 전에는 절대 걷지 않는다.** 이 방어가 격발을 조기 종료시키면 5초 연출이 사라지고
/// 보낸 사람의 하루 몫이 증발한다(이 파일이 재통지·farewell·peek 를 하나씩 막아 온 이유와 같은 손실).
/// 게다가 격발 중 드래그를 허용하면 화면만 한 패널이 끌려가 saveOffset 이 전체화면 기준 오프셋을 영속해
/// 사용자가 캐릭터를 두었던 자리가 영영 날아간다.
@MainActor
@Test
func liveUltraIsNeverCutShortByMouseEvents() {
    let rig = DragRig(ultraDeadlineSeconds: 600)   // 이 테스트 안에서는 절대 만료되지 않는다.
    rig.startWorking()
    let placed = rig.controller.panel.frame
    rig.receiveUltra()
    #expect(rig.controller.isUltraActive)

    // 마우스를 아무리 움직이고 눌러도 격발은 살아 있어야 한다.
    for _ in 0..<5 {
        rig.controller.updateHitThrough(at: rig.bodyPoint)
        rig.controller.handleMouseDown(at: rig.bodyPoint)
        rig.controller.handleMouseDragged(at: NSPoint(x: rig.bodyPoint.x - 200, y: rig.bodyPoint.y - 200))
        rig.controller.handleMouseUp(at: NSPoint(x: rig.bodyPoint.x - 200, y: rig.bodyPoint.y - 200))
    }
    #expect(rig.controller.isUltraActive, "마감 전 격발은 마우스로 걷히지 않는다")
    #expect(rig.controller.pinnedIgnoresMouseEventsValue == true)

    rig.controller.endUltraTakeover()
    rig.layout()
    #expect(rig.controller.panel.frame == placed, "격발 중 마우스질이 캐릭터 자리를 오염시키지 않았다")
    rig.teardown()
}

// MARK: - 원인 4: 유실된 mouseUp 이 히트-스루를 영구 정지시키지 않는다

/// `updateHitThrough` 는 드래그 중 값이 흔들리지 않도록 `!isDragCandidate` 로 자신을 막는다. 그런데
/// mouseUp 은 유실될 수 있고(다른 Space·앱 전환·창 유실 — 이 파일이 여러 곳에서 이미 전제한 사실),
/// 유실되면 그 가드가 **영구 정지**가 된다: 후보가 안 내려가니 통과값이 갱신되지 않고, 갱신이 없으니
/// 패널이 클릭을 못 받고, 클릭을 못 받으니 다음 mouseUp 도 영영 안 온다.
/// 버튼이 실제로 눌려 있지 않으면 그 후보는 유령이므로 다음 마우스 이동에서 버린다.
@MainActor
@Test
func lostMouseUpDoesNotFreezeHitThroughForever() {
    let rig = DragRig()
    rig.startWorking()

    // 드래그 중 mouseUp 유실.
    rig.controller.handleMouseDown(at: rig.bodyPoint)
    rig.controller.handleMouseDragged(at: NSPoint(x: rig.bodyPoint.x - 30, y: rig.bodyPoint.y - 10))
    // (up 없음)

    // 커서가 몸체 위로 지나간다 → 통과 해제가 다시 살아나야 한다.
    rig.controller.panel.ignoresMouseEvents = true
    rig.controller.updateHitThrough(at: rig.bodyPoint)
    #expect(
        rig.controller.panel.ignoresMouseEvents == false,
        "유령 드래그 후보가 히트-스루를 영구 정지시키면 안 된다"
    )
    #expect(rig.dragMovesPanel(), "드래그도 그대로 살아 있다")
    rig.teardown()
}

// MARK: - 원인 5(예방): 보상 통지는 입력 사슬에 손대지 않는다
//
// 이 파일의 세 원인은 전부 "창을 만지는 새 기능이 입력 사슬의 값 하나를 굳혔다"였다. v0.2.34 는 그 계층에
// 새 손님을 하나 들인다 — 미션 보상 통지(.ultraCharged)는 격발처럼 **숨김 상태에서도 창을 띄운다**.
// 격발과 다른 점은 자격이다: 격발은 클릭 통과를 못 박을 이유가 있지만(전체화면을 5초 덮는다),
// 보상은 140×170 캐릭터가 잠깐 나타났다 사라지는 것뿐이라 입력에 대해 할 말이 없다.
//
// 그래서 여기서는 값이 아니라 **결과**로 본다: 보상이 지나간 뒤에도 사용자가 캐릭터를 실제로 끌 수 있는가.
// (값 단언은 UltraPokeOverlayTests.rewardLeavesTheInputPinAloneOnEveryPath 가 세 경로 전부에 건다.)

@MainActor
@Test
func rewardNotificationLeavesDragWorking() {
    let rig = DragRig()
    rig.startWorking()
    #expect(rig.dragMovesPanel(), "픽스처: 시작 시점에 드래그가 살아 있어야 한다")

    let monitors = (rig.controller.hasMouseMoveMonitor, rig.controller.hasLocalMouseMoveMonitor)

    // (a) 표시 중 보상.
    rig.controller.presentReward(.ultraCharged)
    rig.layout()
    #expect(rig.controller.pinnedIgnoresMouseEventsValue == nil, "보상이 클릭 통과를 못 박았다")
    #expect(
        (rig.controller.hasMouseMoveMonitor, rig.controller.hasLocalMouseMoveMonitor) == monitors,
        "보상이 히트-스루 모니터를 떼거나 붙였다 — 이 파일의 원인 2가 그대로 재발한다"
    )
    #expect(rig.dragMovesPanel(), "표시 중 보상 뒤 드래그가 죽었다")

    // (b) 숨김 peek 보상 → 다시 근무. 창을 띄우는 쪽 경로가 값을 굳히면 여기서 드러난다.
    rig.stopWorking()
    rig.controller.presentReward(.ultraCharged)
    rig.layout()
    #expect(rig.controller.pinnedIgnoresMouseEventsValue == nil, "peek 보상이 클릭 통과를 못 박았다")
    rig.startWorking()
    #expect(rig.dragMovesPanel(), "peek 보상 뒤 드래그가 죽었다")

    rig.teardown()
}

// MARK: - v0.2.35: 자리 비움 복원 안내가 입력 사슬에 손대지 않는다
//
// v0.2.35 는 `nudgeAutoStart()` 에 새 분기를 하나 들인다 — 복원 가능한 자동 마감이 있으면 등장 말풍선을
// 다른 문구로 갈아 끼운다. 이 파일의 세 사고는 전부 "창을 만지는 새 기능이 입력 사슬의 값 하나를 굳혔다"
// 였고, v0.2.32 의 드래그 사망도 정확히 이 계층에서 났다. 그래서 새 분기가 지나간 뒤에도
//
//   ① 못 박기(pinnedIgnoresMouseEvents)가 서지 않고,
//   ② 히트-스루 모니터 구성이 그대로이고,
//   ③ 사용자가 캐릭터를 **실제로 끌 수 있는지**
//
// 를 값과 결과 양쪽으로 본다. 그리고 복원 분기와 평소 분기의 입력 상태가 **서로 같다**는 것까지 본다 —
// "복원 대상이 있는 사람만 캐릭터가 안 움직인다"는 재발 형태를 이 대조가 막는다.

/// 넛지 자격(로그인 + 팀)을 세운다.
@MainActor
private func armDragNudgeEligibility(_ store: WorkTimerStore) {
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
}

/// 복원 창 안의 자동 마감 하나를 심는다.
@MainActor
private func armDragRestorableSession(_ store: WorkTimerStore, now: Date) {
    store.awayStateOwnerUserID = "me"
    store.awayRestorable = AwayRestorableSession(
        sessionID: "20000000-0000-0000-0000-0000000000aa",
        startedAt: now.addingTimeInterval(-6 * 3_600),
        endedAt: now.addingTimeInterval(-3 * 3_600),
        autoClosedAt: now.addingTimeInterval(-3 * 3_600),
        reason: .away,
        expiresAt: now.addingTimeInterval(3 * 3_600),
        remainingSeconds: 3 * 3_600
    )
}

/// 입력 사슬의 상태 한 벌(값 비교용).
private struct InputGateState: Equatable {
    let pinned: Bool?
    let ignoresMouseEvents: Bool
    let globalMonitor: Bool
    let localMonitor: Bool
}

@MainActor
@Test
func awayRestoreNudgeLeavesTheInputChainUntouched() {
    let now = Date(timeIntervalSince1970: 1_800_300_000)

    @MainActor
    func gates(_ rig: DragRig) -> InputGateState {
        InputGateState(
            pinned: rig.controller.pinnedIgnoresMouseEventsValue,
            ignoresMouseEvents: rig.controller.panel.ignoresMouseEvents,
            globalMonitor: rig.controller.hasMouseMoveMonitor,
            localMonitor: rig.controller.hasLocalMouseMoveMonitor
        )
    }

    /// 넛지 발동 → SwiftUI 관찰 경로 모사까지 한 벌로 돈다. 반환값은 발동 직전/직후/표시 후의 게이트 상태.
    @MainActor
    func run(restorable: Bool) -> (before: InputGateState, afterNudge: InputGateState, afterShow: InputGateState, dragged: Bool, rig: DragRig) {
        let rig = DragRig()
        armDragNudgeEligibility(rig.store)
        rig.store.setOverlayEnabled(true)
        if restorable { armDragRestorableSession(rig.store, now: now) }

        let before = gates(rig)
        rig.controller.nudgeAutoStart()
        let afterNudge = gates(rig)
        // 자동 시작이 스토어를 근무중으로 바꿨다 — 프로덕션과 같은 순서로 컨트롤러에 흘린다.
        rig.controller.updateWorking(true)
        rig.layout()
        return (before, afterNudge, gates(rig), rig.dragMovesPanel(), rig)
    }

    let plain = run(restorable: false)
    let withRestore = run(restorable: true)

    // ① 못 박기는 어느 경로에서도 서지 않는다(값 불변). v0.2.32 의 드래그 사망이 정확히 이 값이었다.
    #expect(plain.before.pinned == nil, "픽스처: 시작 시점에 못 박기가 없어야 한다")
    #expect(withRestore.before.pinned == nil, "픽스처: 시작 시점에 못 박기가 없어야 한다")
    #expect(withRestore.afterNudge.pinned == nil, "복원 안내가 클릭 통과를 못 박았다")
    #expect(withRestore.afterShow.pinned == nil, "복원 안내 뒤 표시 경로가 클릭 통과를 못 박았다")

    // ② 복원 분기와 평소 분기의 입력 상태가 완전히 같다 — 새 분기는 문구만 바꾼다.
    #expect(withRestore.afterNudge == plain.afterNudge, "복원 분기가 발동 직후 입력 상태를 갈랐다")
    #expect(withRestore.afterShow == plain.afterShow, "복원 분기가 표시 후 입력 상태를 갈랐다")

    // ③ 픽스처가 실제로 복원 경로를 탔는가(같다는 단언이 '둘 다 아무 일도 안 했다'로 통과하지 않게).
    #expect(withRestore.rig.store.awayRestorePromptPending, "픽스처: 복원 경로를 타지 않았다")
    #expect(!plain.rig.store.awayRestorePromptPending)

    // ④ 값이 아니라 결과. 복원 안내를 받은 사람도 캐릭터를 끌 수 있어야 한다.
    #expect(plain.dragged, "픽스처: 평소 경로에서 드래그가 살아 있어야 한다")
    #expect(withRestore.dragged, "복원 안내 뒤 드래그가 죽었다")

    plain.rig.teardown()
    withRestore.rig.teardown()
}
