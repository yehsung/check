import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check

// 울트라 찌르기 **수신 측**(전체화면 격발 5초)의 회귀 방어.
//
// 이 파일이 지키는 것은 넷이다.
//  (1) 격발이 **가리되 막지는 않는가** — U3. 화면을 덮되 클릭·스크롤은 뒤 앱으로 그대로 통과해야 한다
//      (한때 클릭을 먹게 두었다가 실사용 확인 후 되돌린 결정이다).
//  (2) 그 덮임이 **반드시 걷히는가** — 이 기능의 유일한 치명 사고 모드는 '영영 안 걷힘'이다. 정상 타이머와
//      독립된 워치독이 그것을 이중으로 보장하고, 패널은 계속 .nonactivatingPanel 이라 사용자가
//      ⌘⌥Esc·⌘Tab·메뉴바로 스스로 빠져나갈 길이 남는다.
//  (3) 그 두 타이머가 **스스로 깨어나는가** — 값 판정만 밖에서 불러 보면 태스크 생성을 통째로 지워도
//      스위트가 초록이다(실제로 그랬다). 그래서 **수면을 주입해** 한쪽만 깨우고 다른 쪽은 재워 둔 채
//      확인한다(UltraSleepLog 참고 — 벽시계는 이 판정에서 완전히 빠졌다).
//  (4) 5초 뒤 **정확히 원래대로** 돌아오는가 — 프레임·표시 여부·클릭 통과·드래그로 저장한 자리까지.
//      격발 도중 화면 구성이 바뀌어도(모니터 연결/해상도 변경) 전체화면이 무너지지 않아야 한다.
//
// 헬퍼는 기존 파일들이 전부 private 이라 자기 복사본을 둔다(공용화하려고 남의 파일을 건드리지 않는다).

// MARK: - 헬퍼

private func isolatedUltraDefaults() -> UserDefaults {
    let suiteName = "check-ultra-overlay-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 격발 타이밍(초)은 **주입**한다. 기본값은 프로덕션 상수 그대로이고, 만료가 주제가 아닌 테스트만
/// `ultraNeverExpires` 로 그 축을 못 박는다.
///
/// "타이머가 스스로 깨어나는가"는 **초가 아니라 수면**을 갈아 끼워 본다(`controller.ultraSleep` /
/// `ultraWatchdogSleep`). 초를 짧게 주던 앞선 판은 제품이 아니라 그날의 메인 액터 대기열을 시험했다 —
/// 자세한 실측은 `UltraSleepLog` 주석에 있다.
@MainActor
private func makeUltraController(
    engine: ReactionEngine,
    notificationCenter: NotificationCenter = NotificationCenter(),
    ultraDurationSeconds: Double = CheckOverlayController.ultraSeconds,
    ultraDeadlineSeconds: Double
        = CheckOverlayController.ultraSeconds + CheckOverlayController.ultraWatchdogGrace
) -> (WorkTimerStore, CheckOverlayController) {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedUltraDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store,
        notificationCenter: notificationCenter,
        engine: engine,
        defaults: isolatedUltraDefaults(),
        workspaceNotifications: nil,
        ultraDurationSeconds: ultraDurationSeconds,
        ultraDeadlineSeconds: ultraDeadlineSeconds
    )
    return (store, controller)
}

private func ultraPoke(
    id: String = "u1",
    from name: String = "이유성",
    at date: Date
) -> ReceivedPoke {
    ReceivedPoke(id: id, fromName: name, createdAt: date, kind: .ultra)
}

/// 근무중을 **스토어에서부터** 세운다(그 다음에 컨트롤러로 흘린다).
///
/// `controller.updateWorking(true)` 만 부르면 컨트롤러는 '표시 중'인데 `store.snapshot` 은 '비근무'인,
/// **프로덕션에 존재할 수 없는** 조합이 된다 — 프로덕션에서 shouldBeVisible 은 언제나
/// `store.snapshot.isWorking && store.isOverlayEnabled` 라는 한 식에서만 나오기 때문이다.
/// 그 조합이 왜 위험한가: 격발이 패널을 화면 전체로 넓히면 NSHostingView 가 **그 자리에서** SwiftUI 루트 뷰를
/// 다시 평가하고, `.onChange(of: store.snapshot.isWorking, initial: true)` 가 격발 한복판에서
/// `onWorkingChange(false)` 를 흘린다. 두 값이 어긋나 있으면 그게 '근무 종료'로 읽혀 방금 세운 격발이
/// 즉시 철거된다(테스트만의 유령 전이다).
/// 픽스처를 프로덕션과 같은 방식으로 세우면 그 재통지가 '값이 같은 재통지'가 되고, 그래서 이 파일은
/// **"격발 중 SwiftUI 재통지가 들어와도 전체화면이 무너지지 않는다"** 까지 실제로 검증하게 된다.
@MainActor
private func startWorking(_ store: WorkTimerStore, _ controller: CheckOverlayController) {
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    controller.updateWorking(true)
}

/// 타이머 만료가 **주제가 아닌** 테스트가 주입하는 지속/마감(초). 실시간으로는 절대 만료되지 않는다.
///
/// 프로덕션 상수(5초/6초)를 그냥 쓰면 그 테스트들은 "격발이 아직 살아 있다"를 단언하면서 실제로는
/// **스위트가 5초 안에 자기 차례를 주는가**를 함께 시험하게 된다. 아래 waitUntilUltra 주석의 실측대로
/// 그 전제는 전체 실행에서 성립하지 않는다(메인 액터가 84초 밀렸다). 주제가 아닌 축은 아예 못 움직이게
/// 못 박아 두는 편이 테스트를 좁고 정확하게 만든다.
private let ultraNeverExpires: Double = 600

/// 격발 타이머 두 개에 주입할 수면. **벽시계를 테스트에서 도려내는 도구다.**
///
/// 앞선 판은 짧은 실시간 지속(0.3초)을 주입하고 "그 안에 걷히는가"를 벽시계로 기다렸다. 그건 제품이 아니라
/// **그날의 메인 액터 대기열**을 시험한다 — 이 스위트는 다수가 `@MainActor` 이고 ImageRenderer 렌더·첫 3D
/// 마운트 같은 **동기** 작업이 메인 스레드를 통째로 잡는다(실측: `Task.sleep(10ms)` 한 번이 84.15초 뒤 재개).
/// 그래서 단독 실행은 초록, 전체 실행만 빨간불이었다.
///
/// 수면을 쥐면 그 축이 통째로 사라진다. `instant` 는 요청된 초를 기록만 하고 곧바로 돌려주므로
/// **"타이머가 스스로 깨어나 원복하는가"** 라는 주장은 그대로 남고(아무도 밖에서 밀어 주지 않는다 —
/// 태스크가 자기 몸통을 끝까지 달려야만 걷힌다), `blocked` 는 이 테스트 안에서 절대 깨지 않아
/// **"걷은 것이 누구인가"** 를 산술적으로 못 박는다.
private final class UltraSleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: [Double] = []

    /// 요청된 수면(초) 기록. 기다림 없이 곧바로 반환한다.
    var instant: @Sendable (Double) async -> Void {
        { [self] seconds in record(seconds) }
    }

    /// 요청은 기록하되 **이 테스트 안에서는 영영 깨지 않는** 수면. 취소에는 정상적으로 반응한다
    /// (컨트롤러가 태스크를 취소하면 곧바로 풀리고, 뒤따르는 가드가 물러남을 책임진다).
    var blocked: @Sendable (Double) async -> Void {
        { [self] seconds in
            record(seconds)
            try? await Task.sleep(for: .seconds(ultraNeverExpires))
        }
    }

    private func record(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        seconds.append(value)
    }

    /// 이 수면에 들어온 요청들(초).
    var requested: [Double] {
        lock.lock(); defer { lock.unlock() }
        return seconds
    }
}

/// 조건이 참이 될 때까지 **메인 액터를 놓아 주며** 기다린다.
///
/// 위 주입 수면과 짝이다: 성공 경로에는 벽시계가 **없다**. 즉시 반환하는 수면을 쓰면 남은 일은
/// "태스크가 실행될 차례를 얻는 것"뿐이라, 예산은 시간이 아니라 **기회 횟수**로 센다 — 메인 액터가 굶는
/// 동안에는 예산이 줄지 않고, 폭풍이 지나가 제어가 돌아온 바로 그 순간 조건을 다시 본다.
/// 평시에는 한두 바퀴 만에 돌아오므로 비용은 사실상 0이다.
///
/// `hardLimitSeconds` 는 제품이 정말 고장 났을 때(태스크 생성이 통째로 사라졌을 때) 스위트가 영영 멈추지
/// 않게 하는 마지막 안전선이지 판정 기준이 아니다.
@MainActor
@discardableResult
private func waitUntilUltra(
    opportunities: Int = 300,
    hardLimitSeconds: Double = 120,
    _ condition: () -> Bool
) async -> Bool {
    let hardLimit = Date().addingTimeInterval(hardLimitSeconds)
    for _ in 0..<opportunities {
        if condition() { return true }
        // 주입 수면은 비격리(nonisolated) async 라 협력 풀을 한 번 들렀다 온다. yield 만으로는 그 홉이
        // 끝났음을 보장하지 못하므로 아주 짧은 실수면을 한 번 더 끼운다 — 시간이 판정에 들어가는 게
        // 아니라 **다른 실행기에 한 바퀴 돌 틈을 주는 것**이 목적이다.
        await Task.yield()
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
        if Date() >= hardLimit { break }
    }
    return condition()
}

/// 근무 종료도 같은 이유로 스토어부터 내린다(컨트롤러만 내리면 위와 반대 방향의 유령 전이가 남는다).
@MainActor
private func stopWorking(_ store: WorkTimerStore, _ controller: CheckOverlayController) {
    store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    controller.updateWorking(false)
}

// MARK: - 엔진: 우선순위 4 · 5초 · 탈출구

@MainActor
@Test
func ultraPokedOutranksEveryOtherReaction() {
    // 울트라만 4다. 3 이었다면 재생 도중 도착한 팀원 인사·마일스톤·일반 찔림이 모션을 인터럽트해
    // "패널은 전체화면인데 캐릭터는 작은 까딱 인사를 하는" 기괴한 5초가 된다.
    let now = Date(timeIntervalSince1970: 500_000)
    let engine = ReactionEngine(clock: { now })
    let text = "이유성님의 울트라 찌르기!"
    #expect(engine.request(.ultraPoked(bubbleText: text)))

    #expect(engine.request(.poked(bubbleText: "김철수님이 콕 찔렀어요!")) == false)
    #expect(engine.request(.hit) == false)
    #expect(engine.request(.commuteStart) == false)
    #expect(engine.request(.commuteEnd) == false)
    #expect(engine.request(.milestone) == false)
    #expect(engine.request(.greeting(name: "김철수")) == false)
    #expect(engine.request(.drowsy) == false)
    #expect(engine.request(.wake) == false)

    // 어느 요청도 상태·말풍선을 흔들지 못했다.
    #expect(engine.state == .playing(.ultraPoked(bubbleText: text)))
    #expect(engine.greetingText == text)
}

@MainActor
@Test
func ultraPokedAcceptsRepeatUltraAndRefreshesBubble() {
    // 울트라는 자기 자신에게만 자리를 내준다(4 <= 4 라 예외가 없으면 두 번째 울트라가 조용히 씹힌다).
    let now = Date(timeIntervalSince1970: 501_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.request(.ultraPoked(bubbleText: "이유성님의 울트라 찌르기!")))
    #expect(engine.request(.ultraPoked(bubbleText: "김철수님의 울트라 찌르기!")))
    #expect(engine.state == .playing(.ultraPoked(bubbleText: "김철수님의 울트라 찌르기!")))
    #expect(engine.greetingText == "김철수님의 울트라 찌르기!")
}

@MainActor
@Test
func ultraPokedWakesFromSleeping() {
    // 자는 중에 도착해도 잠을 깨우고 격발한다 — 여기서 무시하면 밤샘 근무자에게만 울트라가 안 온다.
    let now = Date(timeIntervalSince1970: 502_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.request(.drowsy))
    #expect(engine.state == .sleeping)

    let text = "이유성님의 울트라 찌르기!"
    #expect(engine.request(.ultraPoked(bubbleText: text)))
    #expect(engine.state == .playing(.ultraPoked(bubbleText: text)))
}

@MainActor
@Test
func ultraPokedDurationIsFiveSeconds() {
    var now = Date(timeIntervalSince1970: 503_000)
    let engine = ReactionEngine(clock: { now })
    #expect(ReactionKind.ultraPoked(bubbleText: "").duration == 5.0)

    #expect(engine.request(.ultraPoked(bubbleText: "이유성님의 울트라 찌르기!")))
    now = now.addingTimeInterval(4.9)
    #expect(engine.state != .idle)          // 아직 격발 중.
    now = now.addingTimeInterval(0.2)       // 총 5.1초.
    #expect(engine.state == .idle)
}

@MainActor
@Test
func ultraPokedActionRunsFiveSeconds() {
    // 세 상수(ReactionKind.ultraPoked.duration / 액션 총 길이 / CheckOverlayController.ultraSeconds)가
    // 갈라지는 회귀를 잡는 유일한 지점. 하나만 바꾸면 모션이 잘리거나 빈 화면이 남는다.
    let action = ReactionActions.ultraPoked(extent: 1)
    #expect(abs(action.duration - 5.0) < 0.01)
    #expect(abs(action.duration - ReactionKind.ultraPoked(bubbleText: "").duration) < 0.01)
    #expect(abs(action.duration - CheckOverlayController.ultraSeconds) < 0.01)
}

@MainActor
@Test
func cancelActiveReactionLetsCommuteEndThrough() {
    // 우선순위 4 는 근무종료 인사(3)조차 막는다. 탈출구가 없으면 울트라 도중 근무를 끝냈을 때
    // 꾸벅 인사가 조용히 거부되고 "수고했어!"가 영영 안 뜬다.
    let now = Date(timeIntervalSince1970: 504_000)
    let engine = ReactionEngine(clock: { now })
    #expect(engine.request(.ultraPoked(bubbleText: "이유성님의 울트라 찌르기!")))
    #expect(engine.request(.commuteEnd) == false)

    engine.cancelActiveReaction()
    #expect(engine.state == .idle)
    #expect(engine.request(.commuteEnd))
    #expect(engine.greetingText == "수고했어!")

    // 멱등: 재생 중이 아닐 때 불러도 상태를 망가뜨리지 않는다.
    engine.cancelActiveReaction()
    engine.cancelActiveReaction()
    #expect(engine.state == .idle)
}

// MARK: - 순수 기하 · 문구

@MainActor
@Test
func ultraPanelFrameIsWholeScreenNotVisibleFrame() {
    // 요구는 "화면 정중앙을 싹 덮는다"다. visibleFrame 으로 '고치면' 메뉴바·독 자리만큼 중심이 밀려
    // 정중앙에 서지 않는다 — 그 회귀를 여기서 막는다.
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = NSRect(x: 0, y: 0, width: 1512, height: 982 - 37) // 메뉴바만큼 줄인 가짜 visibleFrame
    #expect(CheckOverlayController.ultraPanelFrame(in: screen) == screen)
    #expect(CheckOverlayController.ultraPanelFrame(in: screen) != visible)

    // 원점이 0 이 아닌 보조 모니터에서도 그 화면 전체다.
    let secondary = NSRect(x: -1920, y: 120, width: 1920, height: 1080)
    #expect(CheckOverlayController.ultraPanelFrame(in: secondary) == secondary)
}

@MainActor
@Test
func ultraRestoreRejectsFrameOffAllScreens() {
    // 5초 사이 모니터를 뽑으면 저장 프레임이 허공을 가리킨다. 그대로 복귀시키면 캐릭터가 존재하지 않는
    // 좌표로 돌아가 재실행 전까지 영영 안 보인다.
    let frame = NSRect(x: 100, y: 100, width: 140, height: 170)
    #expect(CheckOverlayController.canRestore(frame: frame, screens: []) == false)
    #expect(CheckOverlayController.canRestore(
        frame: frame, screens: [NSRect(x: 2_000, y: 2_000, width: 1_000, height: 1_000)]
    ) == false)
    #expect(CheckOverlayController.canRestore(
        frame: frame, screens: [NSRect(x: 0, y: 0, width: 1_512, height: 982)]
    ))
    // 여러 화면 중 하나라도 겹치면 복귀 가능.
    #expect(CheckOverlayController.canRestore(frame: frame, screens: [
        NSRect(x: 2_000, y: 2_000, width: 100, height: 100),
        NSRect(x: 0, y: 0, width: 1_512, height: 982)
    ]))
}

@MainActor
@Test
func ultraSideUsesShortestEdge() {
    // 정사각 한 변은 항상 짧은 변 기준이다(가로 긴 화면/세로 긴 화면 결과가 같아야 모니터마다 캐릭터
    // 크기가 달라지지 않는다).
    let expected = 945 * CheckOverlayCharacterView.ultraSideRatio
    #expect(abs(CheckOverlayCharacterView.ultraSide(viewSize: CGSize(width: 1512, height: 945)) - expected) < 0.0001)
    #expect(abs(CheckOverlayCharacterView.ultraSide(viewSize: CGSize(width: 945, height: 1512)) - expected) < 0.0001)
    #expect(abs(CheckOverlayCharacterView.ultraSide(viewSize: CGSize(width: 1000, height: 1000)) - 980) < 0.0001)
    // 레이아웃 전(0×0) 에도 음수/0 프레임을 만들지 않는다.
    #expect(CheckOverlayCharacterView.ultraSide(viewSize: .zero) >= 1)
}

@MainActor
@Test
func ultraCharacterBoxEqualsViewSizeWhenNotUltra() {
    // 누가 다시 if/else 구조로 '정리'하면 평시 140×170 레이아웃이 정사각으로 바뀐다 — 평시 값이
    // 뷰 크기와 **완전히 동일**함을 못 박는다.
    let view = CGSize(width: 140, height: 170)
    #expect(CheckOverlayCharacterView.characterBoxSize(viewSize: view, isUltra: false) == view)

    let ultra = CheckOverlayCharacterView.characterBoxSize(
        viewSize: CGSize(width: 1512, height: 945), isUltra: true
    )
    #expect(ultra.width == ultra.height)     // 정사각.
    #expect(abs(ultra.width - 945 * CheckOverlayCharacterView.ultraSideRatio) < 0.0001)
}

@MainActor
@Test
func ultraBubbleTextFormatsSoloAndMixedBatch() {
    #expect(CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: 0) == "이유성님의 울트라 찌르기!")
    #expect(CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: 2)
        == "이유성님의 울트라 찌르기! (외 2명)")
    // 음수는 나올 수 없지만(배치 크기 - 1) 들어와도 인원수를 덧붙이지 않는다.
    #expect(CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: -1) == "이유성님의 울트라 찌르기!")
}

// MARK: - 컨트롤러: 격발은 가리되 **막지 않는다**, 그리고 반드시 걷는다

@MainActor
@Test
func overlayUltraNeverBlocksInputAndDetachesHitThroughMachinery() {
    // ★ 이 웨이브의 핵심. 격발은 "가리기"이지 "막기"가 아니다.
    //   한때 클릭을 먹게(ignoresMouseEvents=false) 두었다가 실사용 확인 후 되돌렸다 — 화면만 한 패널이
    //   이벤트를 먹으면 **캐릭터 뒤만이 아니라 화면 전체**의 클릭과 **스크롤까지** 5초 동안 죽는다.
    //   연출 하나가 남의 작업을 통째로 멈추는 것은 과하다.
    //   그런데 A1 히트-스루 기계(updateHitThrough)는 커서가 몸체 위면 클릭을 받으려고 값을 뒤집는다.
    //   화면을 덮은 거대 몸체에서는 그 판정이 커서 위치마다 뒤집혀 "막다 말다" 하는 최악이 된다.
    //   그래서 기계를 떼고 값을 통과로 못 박는다 — **두 방어선이 모두 살아 있어야** 한다.
    let now = Date(timeIntervalSince1970: 600_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)

    // 전제 기록: 헤드리스에서 전역 모니터 설치가 실패할 수 있으므로 단언이 아니라 기록으로 둔다.
    // 아래 두 단언(떼어냄 / 못 박음)은 전제와 무관하게 항상 참이어야 한다.
    let hadMonitor = controller.hasMouseMoveMonitor
    #expect(controller.panel.ignoresMouseEvents)   // 평시에도 클릭 통과가 기본값.

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(controller.hasMouseMoveMonitor == false)         // ① 60Hz 토글 기계를 뗐다.
    #expect(controller.pinnedIgnoresMouseEventsValue == true) // ② 통과로 못 박았다.
    #expect(controller.panel.ignoresMouseEvents)              // ③ 클릭·스크롤이 뒤 앱으로 그대로 간다.

    // 히트-스루 경로가 살아서 값을 뒤집으려 해도 못 박은 값이 이긴다(이게 없으면 막다 말다 한다).
    // 커서를 격발 패널 한복판에 두고 불러도 여전히 통과여야 한다 — 거대 몸체 위라 원래라면 뒤집힌다.
    controller.updateHitThrough(at: NSPoint(x: 5, y: 5))
    #expect(controller.panel.ignoresMouseEvents)
    controller.updateHitThrough(at: CGPoint(x: controller.panel.frame.midX, y: controller.panel.frame.midY))
    #expect(controller.panel.ignoresMouseEvents)
    controller.restorePassThroughAfterExit()
    #expect(controller.panel.ignoresMouseEvents)

    // 격발 중 마우스 다운이 들어와도(로컬 이벤트 경로가 한 프레임 먼저 도착하는 경우) 드래그가 시작되지
    // 않는다. 화면만 한 패널이 드래그되면 saveOffset 이 전체화면 기준 오프셋을 영속해 사용자가 캐릭터를
    // 두었던 자리가 영영 날아간다. 프레임이 그대로인 것으로 확인한다(isDragCandidate 는 private).
    let frameBeforeDrag = controller.panel.frame
    controller.handleMouseDown(at: CGPoint(x: frameBeforeDrag.midX, y: frameBeforeDrag.midY))
    controller.handleMouseDragged(at: CGPoint(x: frameBeforeDrag.midX + 120, y: frameBeforeDrag.midY + 120))
    #expect(controller.panel.frame == frameBeforeDrag)

    controller.endUltraTakeover()
    #expect(controller.isUltraActive == false)
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)   // 못 박기 해제 — 평소 토글로 복귀.
    #expect(controller.panel.ignoresMouseEvents)               // 클릭 통과 유지.
    #expect(controller.hasMouseMoveMonitor == hadMonitor)      // 격발 전 상태로 정확히 복원.

    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraKeepsNonactivatingPanelSoUserCanEscape() {
    // ★ 안전밸브 1. 5초 동안 화면을 막는 것은 의도지만, 그 사이에도 사용자가 스스로 빠져나갈 수 있어야 한다.
    //   .nonactivatingPanel 이 유지되어야 클릭이 우리 앱을 활성화하지 않아 ⌘⌥Esc(강제 종료)·⌘Tab 이 살아 있고,
    //   레벨이 .floating 에 머물러야 메뉴바(더 높은 레벨)로 근무 종료라는 탈출로가 남는다.
    //   여기서 .screenSaver 로 올리거나 makeKey 를 부르는 '개선'이 들어오면 사용자가 갇힌다.
    let now = Date(timeIntervalSince1970: 601_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(controller.panel.styleMask.contains(.nonactivatingPanel))
    #expect(controller.panel.styleMask.contains(.borderless))
    #expect(controller.panel.level == .floating)
    #expect(controller.panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(controller.panel.isKeyWindow == false)   // 키보드 포커스를 뺏지 않는다.

    controller.endUltraTakeover()
    #expect(controller.panel.styleMask.contains(.nonactivatingPanel))
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraWatchdogRestoresEvenIfMainTimerNeverFires() throws {
    // ★ 안전밸브 2 — **값 판정** 쪽. 격발의 유일한 치명 사고 모드는 '영영 안 걷힘'이다(화면이 덮인 채 남고
    //   전체화면 프레임이 다음 근무 시작까지 따라온다). 정상 원복(ultraTask)이 취소·유실로 죽은 세계를
    //   재현한다: 5초 타이머는 아직 울리지 않았는데 마감 시각만 지난 상태에서 판정을 부른다 →
    //   **그것만으로** 전부 원복되어야 한다.
    //   (태스크가 **스스로 깨어나는지**는 이 테스트가 못 본다 — 아래
    //    overlayUltraWatchdogTaskWakesItselfWithNoOnePushingIt 가 그 몫이다.)
    let now = Date(timeIntervalSince1970: 602_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    let before = controller.panel.frame

    let t0 = Date()
    controller.handleReceivedPokes([ultraPoke(at: now)])
    let elapsed = Date().timeIntervalSince(t0)   // 첫 3D 마운트가 메인 스레드를 잡고 있던 시간이 여기 들어온다.
    #expect(controller.isUltraActive)

    let deadline = try #require(controller.ultraDeadline)
    // 마감 상한은 반드시 정상 원복보다 뒤다. 앞에 두면 워치독이 정상 재생을 잘라먹는다.
    #expect(controller.ultraDeadlineSeconds > controller.ultraDurationSeconds)
    // 그리고 마감은 **격발이 시작된 시각** 기준이다(호출이 얼마나 걸렸든 그만큼 뒤로 밀리지 않는다).
    // 벽시계 `timeIntervalSinceNow` 로 재면 이 성질을 못 본다 — 밀린 마감도 "지금부터 6초"로 보이기 때문.
    #expect(deadline >= t0.addingTimeInterval(controller.ultraDeadlineSeconds))
    #expect(deadline <= t0.addingTimeInterval(controller.ultraDeadlineSeconds + max(0.05, elapsed * 0.5)))

    // 마감 전에는 개입하지 않는다(안 그러면 격발이 조기에 잘린다).
    #expect(controller.enforceUltraDeadline(now: deadline.addingTimeInterval(-0.01)) == false)
    #expect(controller.isUltraActive)

    // 마감이 지나면 정상 타이머와 무관하게 전부 걷힌다.
    #expect(controller.enforceUltraDeadline(now: deadline))
    #expect(controller.isUltraActive == false)
    #expect(controller.ultraDeadline == nil)
    #expect(controller.panel.frame == before)                   // 프레임 원복.
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)    // 못 박기 해제.
    #expect(controller.panel.ignoresMouseEvents)                // 클릭 통과 복원 = 화면을 되찾았다.
    #expect(engine.isUltraActive == false)

    // 멱등: 이미 걷힌 뒤 다시 불러도 아무 일도 없다.
    #expect(controller.enforceUltraDeadline(now: deadline.addingTimeInterval(60)) == false)
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraGrowsPanelToWholeScreen() {
    let now = Date(timeIntervalSince1970: 603_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)

    controller.handleReceivedPokes([ultraPoke(at: now)])

    let expected = CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: 0)
    #expect(controller.isUltraActive)
    // 캐릭터가 놓인 화면 **전체**(visibleFrame 이 아니라 frame)로 넓어졌다.
    #expect(NSScreen.screens.contains { $0.frame == controller.panel.frame })
    #expect(engine.isUltraActive)          // 뷰가 정사각 레이아웃으로 갈아탈 근거.
    #expect(engine.renderActive)
    #expect(engine.state == .playing(.ultraPoked(bubbleText: expected)))
    #expect(engine.greetingText == expected)

    controller.endUltraTakeover()
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraPlaysEvenWhenCharacterHidden() {
    // 캐릭터를 꺼 둔 사용자에게도 전체화면 격발이 그대로 뜬다(강등하지 않는다는 사용자 결정).
    // take_pokes 가 이미 원자 소비했고 보낸이는 하루치 몫을 태웠으므로 여기서 버리면 영영 사라진다.
    let now = Date(timeIntervalSince1970: 604_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(false)

    controller.handleReceivedPokes([ultraPoke(at: now)])

    let expected = CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: 0)
    #expect(controller.isUltraActive)
    #expect(engine.state == .playing(.ultraPoked(bubbleText: expected)))
    #expect(engine.renderActive)
    // 상시 표시 자격은 그대로 꺼져 있다 — 격발은 5초짜리 토스트이지 '캐릭터 켜기'가 아니다.
    #expect(controller.shouldBeVisible == false)

    controller.endUltraTakeover()
    #expect(engine.renderActive == false)   // 꺼져 있던 상태로 정확히 되돌아간다.
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraRestoresExactFrameAndHiddenState() {
    let now = Date(timeIntervalSince1970: 605_000)
    let engine = ReactionEngine(clock: { now })
    let (_, controller) = makeUltraController(engine: engine)
    // 비근무(숨김) 상태에서 수신 → 5초 뒤 다시 숨어야 한다.
    let before = controller.panel.frame

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(controller.panel.frame != before)

    controller.endUltraTakeover()
    #expect(controller.isUltraActive == false)
    #expect(controller.panel.frame == before)
    #expect(controller.panel.isVisible == false)
    #expect(engine.renderActive == false)
    #expect(engine.isUltraActive == false)
    #expect(engine.greetingText == nil)
    // 격발 잔상이 작은 패널로 따라오지 않는다.
    #expect(engine.state == .idle)
}

@MainActor
@Test
func overlayUltraIgnoresDragAndKeepsDraggedPosition() {
    // 사용자가 캐릭터를 옮겨 둔 자리는 격발 5초를 건너 그대로 살아남아야 한다. 격발 중 드래그를 받으면
    // 화면만 한 패널이 마우스를 따라 움직이고, 업 시점의 saveOffset 이 전체화면 기준 오프셋을 영속해
    // 사용자가 둔 자리가 영영 날아간다.
    var now = Date(timeIntervalSince1970: 606_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    now = now.addingTimeInterval(0.7)   // commuteStart 만료 → idle

    // 화면 안쪽으로 30pt 끌어다 둔다.
    let start = controller.panel.frame
    let center = NSPoint(x: start.midX, y: start.midY)
    let moved = NSPoint(x: center.x - 30, y: center.y - 30)
    controller.handleMouseDown(at: center)
    controller.handleMouseDragged(at: moved)
    controller.handleMouseUp(at: moved)
    let dragged = controller.panel.frame
    #expect(dragged.origin != start.origin)

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    let fullscreen = controller.panel.frame

    // 격발 중 드래그 시도는 통째로 무시된다(패널이 따라 움직이지 않는다).
    controller.handleMouseDown(at: NSPoint(x: fullscreen.midX, y: fullscreen.midY))
    controller.handleMouseDragged(at: NSPoint(x: fullscreen.midX - 120, y: fullscreen.midY - 120))
    controller.handleMouseUp(at: NSPoint(x: fullscreen.midX - 120, y: fullscreen.midY - 120))
    #expect(controller.panel.frame == fullscreen)
    // 클릭도 리액션을 만들지 않는다(막는 게 목적 — 때리기·조기 해제 둘 다 없다).
    #expect(controller.isUltraActive)

    controller.endUltraTakeover()
    #expect(controller.panel.frame == dragged)   // 끌어다 둔 그 자리로 정확히 복귀.
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraSwallowsNormalPokeWhileActive() {
    // 격발 중 도착한 일반 찔림은 화면을 흔들지 않는다(엔진도 4 > 3 으로 거부하지만, 상태를 흔들기 전에 막는다).
    let now = Date(timeIntervalSince1970: 607_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)

    controller.handleReceivedPokes([ultraPoke(at: now)])
    let expected = CheckOverlayController.ultraBubbleText(name: "이유성", otherCount: 0)
    let fullscreen = controller.panel.frame

    controller.handleReceivedPokes([ReceivedPoke(id: "n1", fromName: "김철수", createdAt: now)])
    #expect(engine.greetingText == expected)                                  // 문구 그대로.
    #expect(engine.state == .playing(.ultraPoked(bubbleText: expected)))      // 모션 그대로.
    #expect(controller.panel.frame == fullscreen)                             // 창도 그대로.

    controller.endUltraTakeover()
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraRefreshedBySecondUltra() async throws {
    // 격발 중 두 번째 울트라 → 문구 교체 + 5초 타이머 리셋(창이 접히는 시각이 뒤로 밀린다).
    let now = Date(timeIntervalSince1970: 608_000)
    let engine = ReactionEngine(clock: { now })
    // 주제는 '세대 검사'다 — 5초 만료가 이 테스트 안에서 일어나면 안 된다(ultraNeverExpires 주석 참고).
    let (store, controller) = makeUltraController(
        engine: engine,
        ultraDurationSeconds: ultraNeverExpires,
        ultraDeadlineSeconds: ultraNeverExpires
    )
    store.setOverlayEnabled(true)
    startWorking(store, controller)

    controller.handleReceivedPokes([ultraPoke(id: "u1", from: "이유성", at: now)])
    let firstDeadline = try #require(controller.ultraDeadline)
    let fullscreen = controller.panel.frame

    controller.handleReceivedPokes([ultraPoke(id: "u2", from: "김철수", at: now)])
    let secondDeadline = try #require(controller.ultraDeadline)

    #expect(controller.isUltraActive)
    #expect(engine.greetingText == CheckOverlayController.ultraBubbleText(name: "김철수", otherCount: 0))
    #expect(secondDeadline >= firstDeadline)          // 타이머 리셋(뒤로 밀림).
    #expect(controller.panel.frame == fullscreen)     // 프레임은 다시 잡지 않는다(재확대 깜빡임 없음).
    // 같은 배치에 일반 찔림이 섞여 있으면 인원수만 덧붙는다.
    controller.handleReceivedPokes([
        ultraPoke(id: "u3", from: "박영희", at: now),
        ReceivedPoke(id: "n1", fromName: "김철수", createdAt: now)
    ])
    #expect(engine.greetingText == CheckOverlayController.ultraBubbleText(name: "박영희", otherCount: 1))

    // ★ 리셋할 때마다 취소되는 옛 워치독은 **즉시** 깨어난다(Task.sleep 은 취소 시 곧바로 throw 한다).
    //   세대 검사가 없으면 그 옛 워치독이 방금 시작한 격발을 0.00초 만에 잘라먹는다 — 두 번째 울트라가
    //   화면에 뜨자마자 사라지는 사고다. 여기서 한 틱 흘려보내고 여전히 살아 있는지 본다.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(controller.isUltraActive)
    #expect(engine.greetingText == CheckOverlayController.ultraBubbleText(name: "박영희", otherCount: 1))

    controller.endUltraTakeover()
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayWorkEndCancelsUltraAndRestoresFrame() {
    // 근무 종료가 격발 도중에 오면 즉시 접고 인사 경로로 넘긴다. 이 줄이 없으면 화면을 덮은 채로 인사가
    // 재생되고, 프레임이 전체화면인 채 남아 다음 근무 시작 때 캐릭터가 화면 전체로 뜬다.
    let now = Date(timeIntervalSince1970: 609_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    let before = controller.panel.frame

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    // 인사 경로는 창이 실제로 떠 있을 때만 탄다. 헤드리스에서 표시가 불안정할 수 있어 전제를 기록해 둔다
    // (기존 overlayControllerTogglesVisibilityWithWorking 의 관용구).
    let wasOnScreen = controller.panel.isVisible

    stopWorking(store, controller)
    #expect(controller.isUltraActive == false)
    #expect(controller.panel.frame == before)
    #expect(controller.ultraDeadline == nil)
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)
    #expect(controller.panel.ignoresMouseEvents)
    #expect(engine.isUltraActive == false)
    // 울트라가 비켜났으므로 근무종료 인사(우선순위 3)가 수용된다 — "수고했어!"가 실제로 뜬다.
    // 이 두 줄이 없으면 "격발 중 근무 종료 → 인사 없이 그냥 사라짐" 회귀를 아무도 못 잡는다.
    if wasOnScreen {
        #expect(engine.state == .playing(.commuteEnd))
        #expect(engine.greetingText == "수고했어!")
    } else {
        #expect(engine.state == .idle)   // 표시된 적 없으면 인사 없이 정리만 된다(기존 계약).
    }
}

@MainActor
@Test
func overlayUltraSurvivesFarewellWatchdog() async {
    // 근무 종료 직후 꼬리 회수(flushPokesOnWorkEnd)로 도착한 울트라가 0.55초 farewell 워치독의
    // orderOut 에 지워지면, 보낸 사람의 하루치 몫이 0.5초 만에 증발한다.
    let now = Date(timeIntervalSince1970: 610_000)
    let engine = ReactionEngine(clock: { now })
    // 주제는 farewell 워치독이지 격발 만료가 아니다 — 만료 축을 못 박아 둔다(ultraNeverExpires 주석 참고).
    let (store, controller) = makeUltraController(
        engine: engine,
        ultraDurationSeconds: ultraNeverExpires,
        ultraDeadlineSeconds: ultraNeverExpires
    )
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    stopWorking(store, controller)   // beginFarewellHide 가동
    // 인사 워치독이 실제로 걸린 실행에서만 이 테스트가 무언가를 시험한다(창이 화면에 안 올라갔으면
    // updateWorking 이 else 분기로 빠져 farewellTask 가 아예 없다). 전제를 기록해 둔다.
    let farewellArmed = controller.panel.isVisible

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(engine.renderActive)

    // ★ **여기가 실제로 났던 사고를 잡는 자리다.** beginUltraTakeover 의 `farewellTask?.cancel()` 은
    //   막으려던 일을 오히려 **앞당겨** 일으켰다: `try? await Task.sleep` 은 취소되는 순간 throw 하고
    //   `try?` 가 그걸 삼키므로, 잠들어 있던 태스크가 그 자리에서 finishHide 로 내려간다.
    //   실측(단독 실행 재현): 격발 20ms 뒤 renderActive=false·panel.isVisible=false — 전체화면이 뜨자마자
    //   지워지고 남은 5초 동안 렌더까지 멈춘 채 남았다(isUltraActive 만 true 라 아무도 못 알아챈다).
    //   0.55초를 기다린 뒤에야 보는 아래 단언은 그 사고를 **가끔만** 잡았다(창이 실제로 떠 있는 실행에서만).
    //   취소 직후의 한 바퀴를 여기서 먼저 본다 — 가드가 사라지면 이 줄이 매번 빨개진다.
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(controller.isUltraActive)
    #expect(engine.renderActive, "인사 워치독 취소가 곧바로 finishHide 를 태웠다 — 격발이 뜨자마자 지워진다")
    if farewellArmed {
        #expect(controller.panel.isVisible, "격발 중인 전체화면이 orderOut 됐다")
    }

    try? await Task.sleep(for: .seconds(CheckOverlayController.farewellHideDeadline + 0.2))
    #expect(controller.isUltraActive)          // 0.55초에 접히지 않았다.
    #expect(engine.renderActive)

    controller.endUltraTakeover()
    #expect(controller.isUltraActive == false)
    #expect(engine.renderActive == false)      // 격발 전 상태(숨김)로 정확히 복귀.
}

// MARK: - 격발 중 화면 구성이 바뀌어도 전체화면이 무너지지 않는다

@MainActor
@Test
func overlayUltraSurvivesScreenParameterChange() async {
    // ★ 실증된 사고: 모니터 연결·해상도 변경·독 자동숨김 토글이 격발 5초 안에 오면
    //   didChangeScreenParametersNotification → reposition() 이 무조건 140×170 으로 setFrame 해
    //   **패널만 구석으로 쪼그라들고 isUltraActive 는 true 로 남는다** — 작은 창에 거대 레이아웃과
    //   큰 말풍선이 갇힌 5초. 통지 경로를 실제로 태워서 그 회귀를 막는다.
    let now = Date(timeIntervalSince1970: 611_000)
    let engine = ReactionEngine(clock: { now })
    let screenChanges = NotificationCenter()
    // 주제는 reposition 의 격발 가드다 — 만료 축을 못 박아 둔다(ultraNeverExpires 주석 참고).
    let (store, controller) = makeUltraController(
        engine: engine,
        notificationCenter: screenChanges,
        ultraDurationSeconds: ultraNeverExpires,
        ultraDeadlineSeconds: ultraNeverExpires
    )
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    let before = controller.panel.frame

    controller.handleReceivedPokes([ultraPoke(at: now)])
    let fullscreen = controller.panel.frame
    #expect(controller.isUltraActive)
    #expect(fullscreen != before)

    // 관찰자는 통지를 Task 로 메인에 던지므로 한 틱 흘려보낸다.
    screenChanges.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(120))

    #expect(controller.isUltraActive)                       // 격발은 그대로 살아 있고
    #expect(controller.panel.frame.size != CheckOverlayController.panelSize)  // 기본 크기로 쪼그라들지 않았다
    #expect(controller.panel.frame == fullscreen)           // 같은 화면이면 같은 전체화면을 다시 잡는다
    #expect(NSScreen.screens.contains { $0.frame == controller.panel.frame })

    // 동기 경로(직접 호출)도 같다 — 통지 타이밍에 기대지 않고 성질 자체를 못 박는다.
    controller.reposition()
    #expect(controller.panel.frame == fullscreen)

    controller.endUltraTakeover()
    #expect(controller.panel.frame == before)
    // 격발이 끝나면 reposition 은 평소대로 기본 크기로 다시 잡는다(위 가드가 영구 차단이 아니다).
    controller.reposition()
    #expect(controller.panel.frame.size == CheckOverlayController.panelSize)
    stopWorking(store, controller)
}

// MARK: - 타이머가 **스스로** 깨어나는가 (태스크 생성을 지우면 빨간불이어야 한다)

@MainActor
@Test
func overlayUltraWatchdogTaskWakesItselfWithNoOnePushingIt() async throws {
    // ★ 커버리지 구멍 메우기. 기존 워치독 테스트는 enforceUltraDeadline 을 **밖에서 직접 부르는** 값 판정만
    //   본다 — armUltraRestore 에서 `ultraWatchdogTask = Task {...}` 생성을 통째로 지워도 초록이었다.
    //   안전밸브의 2차 방어선이 삭제돼도 무음이라는 뜻이다. 여기서는 아무도 밀어 주지 않는다:
    //   정상 원복 타이머는 이 테스트 안에서 영영 깨지 않게 재워 두고(blocked), 워치독의 수면만 즉시
    //   돌려준다 — 그러면 걷을 수 있는 주체는 **워치독 하나뿐**이라 "걷혔다 = 워치독이 스스로 깨어났다"가
    //   산술적으로 성립한다.
    //
    //   지속/마감은 **프로덕션 상수 그대로** 둔다. 앞선 판은 짧은 실시간 값(0.3초)을 주입하고 벽시계로
    //   기다렸는데, 그건 제품이 아니라 그날의 메인 액터 대기열을 시험했다(UltraSleepLog 주석 참고).
    //   수면을 쥐면 짧게 줄일 이유가 사라지고, 덤으로 **워치독이 실제로 몇 초를 요청했는가**까지 잴 수 있다.
    let now = Date(timeIntervalSince1970: 612_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    let mainSleep = UltraSleepLog()
    let watchdogSleep = UltraSleepLog()
    controller.ultraSleep = mainSleep.blocked        // 정상 타이머는 이 테스트 안에서 영영 안 깬다.
    controller.ultraWatchdogSleep = watchdogSleep.instant
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    let before = controller.panel.frame

    let t0 = Date()
    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(controller.ultraDeadline != nil)

    let lifted = await waitUntilUltra { controller.isUltraActive == false }
    #expect(lifted)
    #expect(controller.ultraDeadline == nil)
    #expect(controller.panel.frame == before)                 // 프레임 원복.
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)  // 못 박기 해제.
    #expect(controller.panel.ignoresMouseEvents)              // 클릭 통과 복원.
    #expect(engine.isUltraActive == false)

    // 걷은 것은 워치독이다 — 정상 타이머의 수면은 요청만 되고 **한 번도 돌아오지 않았다**.
    #expect(mainSleep.requested == [controller.ultraDurationSeconds])
    // 그리고 워치독은 고정 상수가 아니라 **마감까지 남은 시간**을 잤다. 마운트 블로킹(실측 debug 3.4초)이
    // 그만큼 깎아 내므로 상한은 마감 상수, 하한은 '그 블로킹을 뺀 나머지'다 — 누가 다시 고정 상수로
    // 되돌리면(=elapsed 와 무관해지면) 위쪽이 빨개진다.
    let elapsed = Date().timeIntervalSince(t0)
    let requested = try #require(watchdogSleep.requested.first)
    #expect(watchdogSleep.requested.count == 1)
    #expect(requested <= controller.ultraDeadlineSeconds)
    #expect(requested >= controller.ultraDeadlineSeconds - elapsed - 0.05)
    stopWorking(store, controller)
}

@MainActor
@Test
func overlayUltraMainTimerWakesItselfWellBeforeWatchdog() async throws {
    // 같은 구멍의 반대쪽. 메인 `ultraTask = Task {...}` 생성을 지워도 기존 테스트는 전부 초록이었다
    // (워치독이 여유 뒤에 걷어 주니 '언젠가는' 원복되긴 한다 — 그래서 아무도 못 잡는다).
    // 정상 원복이 **스스로** 일어나는지는 여기서만 본다.
    //
    // 그래서 워치독을 이 테스트가 절대 닿을 수 없는 곳에 둔다. 앞선 판은 그걸 '만료되지 않는 초'로 했는데,
    // 그러면 정상 타이머 쪽은 반대로 짧은 실시간 값이 되어 벽시계에 매달렸다(그 한 줄 때문에 전체 실행에서만
    // 빨간불이었다 — UltraSleepLog 주석의 실측). 이제는 **수면 자체**를 가른다: 워치독은 영영 안 깨는
    // 수면을 받고, 정상 타이머의 수면만 즉시 돌아온다. 걷을 수 있는 주체가 정상 타이머 하나뿐이라
    // "걷혔다 = 정상 타이머가 스스로 깨어났다"가 시간과 무관하게 성립한다.
    let now = Date(timeIntervalSince1970: 613_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)
    let mainSleep = UltraSleepLog()
    let watchdogSleep = UltraSleepLog()
    controller.ultraSleep = mainSleep.instant
    controller.ultraWatchdogSleep = watchdogSleep.blocked   // 워치독은 이 테스트 안에서 영영 안 깬다.
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    let before = controller.panel.frame

    controller.handleReceivedPokes([ultraPoke(at: now)])
    #expect(controller.isUltraActive)
    #expect(controller.ultraDeadline != nil)

    let lifted = await waitUntilUltra { controller.isUltraActive == false }
    #expect(lifted)
    #expect(controller.ultraDeadline == nil)
    #expect(controller.panel.frame == before)
    #expect(controller.panel.ignoresMouseEvents)
    #expect(engine.isUltraActive == false)

    // 걷은 것은 정상 타이머다 — 워치독 수면은 요청만 되고 한 번도 돌아오지 않았다.
    #expect(watchdogSleep.requested.count == 1)
    // 그리고 정상 타이머가 잔 시간은 **주입값이 아니라 프로덕션 지속(5초)** 그대로다. 짧은 값을 심어야만
    // 검증되던 시절이 끝났으므로, 이 줄이 그 상수까지 함께 못 박는다.
    #expect(mainSleep.requested == [controller.ultraDurationSeconds])
    #expect(controller.ultraDurationSeconds == CheckOverlayController.ultraSeconds)
    stopWorking(store, controller)
}

// MARK: - 마감은 '화면을 덮은 순간' 기준이다

@MainActor
@Test
func overlayUltraDeadlineIsAnchoredAtTakeoverStartNotAfterMount() throws {
    // ★ 실증된 사고: 마감을 setFrame·orderFront·engine.request 가 **끝난 뒤** 잡으면, 3D 뷰가 한 번도
    //   마운트되지 않은 경로(캐릭터를 꺼 둔 사용자에게 울트라가 오는 배달 계약)에서 setFrame 안의
    //   USDZ 로드 + 텍스처 생성이 동기로 돌며 메인 스레드를 멈춘 시간만큼 상한이 통째로 밀린다
    //   (같은 머신 실측: release setFrame 0.130s → 총 5.17s / debug 3.456s → **총 8.68s, 6초 상한 초과**).
    let now = Date(timeIntervalSince1970: 614_000)
    let engine = ReactionEngine(clock: { now })
    let (store, controller) = makeUltraController(engine: engine)

    // 주입 기본값이 프로덕션 상수와 갈라지지 않았다(테스트용 짧은 값이 그대로 배포되는 것도 여기서 막는다).
    #expect(controller.ultraDurationSeconds == CheckOverlayController.ultraSeconds)
    #expect(controller.ultraDeadlineSeconds
        == CheckOverlayController.ultraSeconds + CheckOverlayController.ultraWatchdogGrace)

    store.setOverlayEnabled(true)
    startWorking(store, controller)

    let t0 = Date()
    controller.handleReceivedPokes([ultraPoke(at: now)])
    let elapsed = Date().timeIntervalSince(t0)
    let deadline = try #require(controller.ultraDeadline)

    // 마감은 t0(격발 시작) + 상한이다. 걸린 시간(elapsed)만큼 뒤로 밀리면 안 된다 — 상한에 elapsed 를
    // 묶어 두었으므로, 마운트가 오래 걸린 실행일수록 이 단언이 더 날카롭게 조인다(빠른 실행에서는 두
    // 방식의 차이가 물리적으로 안 보인다 — 그때는 상한이 밀려도 무해하다는 뜻이기도 하다).
    #expect(deadline >= t0.addingTimeInterval(controller.ultraDeadlineSeconds))
    #expect(deadline <= t0.addingTimeInterval(controller.ultraDeadlineSeconds + max(0.05, elapsed * 0.5)))

    controller.endUltraTakeover()
    stopWorking(store, controller)
}


// MARK: - 미션 보상 통지(.ultraCharged) — 배달 경로 셋과 그 경계
//
// 이 절이 지키는 것은 하나다: **서버가 이미 올린 재화를 사용자가 모른 채 지나가지 않는다.**
// 보상은 찔림과 다르게 재전송이 없다 — `ultra_wallet_sync` 의 grantedNow 는 그 sync 응답 한 번에만 실리고
// (장부 유니크 인덱스가 두 번째 적립을 막는다), 그 다음 sync 부터는 claimed=true 일 뿐 grantedNow=false 다.
// 그래서 이 통지가 어느 상태에서 죽으면 "잔량이 늘었다"는 사실은 사용자가 패널을 열 때까지 침묵한다.
//
// 배달 경로는 셋이고, 경계는 **컨트롤러가 아니라 엔진이** 정한다.
//   (a) 표시 중       → engine.request 만(정상 경로가 창 수명을 소유)
//   (b) 숨김          → peek(8초 창을 새로 무장)
//   (c) 엔진이 거부   → **아무것도 하지 않는다**(창도 안 띄운다)
// (c) 가 이 절의 핵심이다. 앞선 판은 창부터 띄우고 요청은 나중에 했고, 그래서 거부되면 창만 떴다 지고
// 알맹이는 사라졌다(CheckOverlayController.showCurrentMessageBubble 주석이 그 손실을 기록해 두었다).

/// 엔진 clock 을 테스트가 손으로 민다. 보상 통지의 경계 중 하나(격발 리액션은 만료됐는데 컨트롤러 격발은
/// 아직 살아 있는 1초 창 — ultraSeconds 5 vs ultraSeconds+ultraWatchdogGrace 6)를 만들려면 시간이 움직여야 한다.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }

    var reader: @Sendable () -> Date {
        { [self] in now }
    }
}

@MainActor
@Test
func rewardTriggerIsWiredFromStoreToOverlay() {
    // 배선 자체를 못 박는다. 스토어는 grantedNow 를 본 그 자리에서 `onRewardTrigger?(.ultraCharged)` 를
    // 쏘는데(WorkTimerStorePoke), 컨트롤러가 그 구멍을 안 막고 있으면 **아무 일도 일어나지 않고 아무도 모른다**.
    // 콜백이 nil 이면 `?.` 가 조용히 삼키기 때문에 서버·스토어·엔진이 전부 초록인 채로 사용자만 침묵을 겪는다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 700_000) })
    let (store, controller) = makeUltraController(engine: engine)

    // 콜백을 nil 검사로 보지 않고 **실제로 쏴 본다.** 함수 타입은 nil 비교가 컴파일러 진단에 걸리고,
    // 무엇보다 "구멍이 막혔다"보다 "그 구멍으로 연출이 나왔다"가 지키고 싶은 사실이다.
    store.onRewardTrigger?(.ultraCharged)
    #expect(
        engine.greetingText == "울트라 +1!",
        "컨트롤러가 onRewardTrigger 를 배선하지 않았다 — `?.` 가 조용히 삼켜 아무도 모른다"
    )
    #expect(engine.state == .playing(.ultraCharged))

    controller.updateWorking(false)   // peek 태스크 취소 + 렌더 정리.
}

@MainActor
@Test
func rewardPeeksWhenOverlayIsHidden() {
    // 비근무·캐릭터 표시 꺼짐 — 찔림과 **똑같이** 8초 peek 로 전달한다. 이 경로를 shouldBeVisible 게이트로
    // 막으면(onReactionTrigger 처럼) 근무를 끝낸 뒤 도착한 보상이 통째로 사라진다. 미션 판정은 서버가
    // 세션을 닫으며 하므로 **근무 종료 직후가 오히려 흔한 도착 시각**이다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 701_000) })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(false)

    #expect(controller.panel.isVisible == false)
    controller.presentReward(.ultraCharged)

    #expect(engine.greetingText == "울트라 +1!")
    #expect(engine.renderActive, "peek 동안 렌더가 켜져야 연출이 그려진다")
    #expect(controller.panel.isVisible, "숨김 상태에서 보상이 창을 못 띄웠다 — 사용자는 아무것도 못 본다")
    #expect(controller.isPeekArmed, "8초 퇴장 타이머가 없으면 창이 그대로 남는다")
    // peek 는 일시 토스트일 뿐 '캐릭터 켜기'가 아니다.
    #expect(controller.shouldBeVisible == false)

    controller.updateWorking(false)
}

@MainActor
@Test
func rewardDoesNotArmPeekWhileNormallyVisible() {
    // 표시 중이면 **창 수명은 정상 경로의 것**이다. 여기서 peek 를 무장하면 8초 뒤 그 타이머가 깨어나
    // `shouldBeVisible` 가드에 막혀 물러나기는 하지만, 그 사이 도착한 다른 peek 의 퇴장을 자기가 취소해
    // 창을 남기는 등 두 소유자가 겹친다. 정상 경로에서는 움찔+말풍선만이 답이다.
    let clock = ManualClock(Date(timeIntervalSince1970: 702_000))
    let engine = ReactionEngine(clock: clock.reader)
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    #expect(controller.panel.isVisible, "픽스처가 표시 중을 만들지 못했다")
    // 근무 시작은 출근 인사(.commuteStart, 우선순위 3)를 재생한다. 그게 살아 있으면 보상(3)이 3 <= 3 에
    // 걸려 거부되고, 이 테스트는 '경로 선택'이 아니라 '엔진 우선순위'를 시험하게 된다 — 주제가 아닌 축은
    // 재운다(이 파일의 ultraNeverExpires 와 같은 규약).
    clock.advance(ReactionKind.commuteStart.duration + 0.1)
    #expect(engine.state == .idle, "픽스처: 출근 인사가 끝난 뒤여야 한다")

    controller.presentReward(.ultraCharged)

    #expect(engine.greetingText == "울트라 +1!")
    #expect(engine.state == .playing(.ultraCharged))
    #expect(controller.isPeekArmed == false, "표시 중인데 peek 타이머를 세웠다 — 창 소유자가 둘이 된다")

    stopWorking(store, controller)
}

@MainActor
@Test
func rewardOpensNoWindowWhenTheEngineRefuses() {
    // ★ 회귀 지점. 앞선 판의 peek 는 `engine.request` 의 반환값을 보지 않고 **창부터 띄웠다**.
    //   그래서 재생 중이라 요청이 거부되면 창만 떴다 8초 뒤 지고, 사용자는 빈 캐릭터가 잠깐 튀어나왔다
    //   사라지는 것만 본다. 보상에서는 그 손실이 더 나쁘다 — 재화는 이미 올라갔고 재전송이 없다.
    //
    //   여기서 만드는 상태는 실제로 존재한다: 근무 종료 인사(.commuteEnd, 우선순위 3)가 재생 중이고
    //   패널은 이미 숨김으로 내려간 그 구간이다. 보상(3)은 3 <= 3 에 걸리고 예외 셋 중 어디에도
    //   해당하지 않는다(active 가 .poked 도, 보상도, commuteEnd→commuteStart 재시작도 아니다).
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 703_000) })
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(false)

    #expect(engine.request(.commuteEnd), "픽스처: 근무 종료 인사가 재생 중이어야 한다")
    #expect(controller.panel.isVisible == false)

    controller.presentReward(.ultraCharged)

    #expect(engine.state == .playing(.commuteEnd), "거부됐어야 할 요청이 재생을 갈아치웠다")
    #expect(engine.greetingText != "울트라 +1!")
    #expect(controller.panel.isVisible == false, "거부됐는데 창을 띄웠다 — 빈 캐릭터가 튀어나왔다 사라진다")
    #expect(controller.isPeekArmed == false, "띄우지도 않은 창에 퇴장 타이머를 걸었다")
    #expect(engine.renderActive == false)

    controller.updateWorking(false)
}

@MainActor
@Test
func rewardIsSwallowedDuringUltraTakeoverEvenAfterItsReactionExpired() {
    // 격발 중에는 삼킨다 — 전체화면 발광 위에 작은 말풍선을 겹치지 않는다(handleReceivedPokes 와 같은 규약).
    //
    // ★ 이 테스트가 시계를 미는 이유: 엔진 리액션(.ultraPoked)은 5.0초에 만료되는데 컨트롤러 격발은
    //   워치독 여유까지 6.0초다. 그 **1초 창**에서는 엔진이 idle 이라 우선순위(4)가 더 이상 아무것도
    //   막아 주지 않는다 — `isUltraActive` 가드가 유일한 방어다. 시계를 밀지 않으면 우선순위가 대신
    //   막아 주어 가드를 지워도 초록인, 아무것도 안 지키는 테스트가 된다.
    let clock = ManualClock(Date(timeIntervalSince1970: 704_000))
    let engine = ReactionEngine(clock: clock.reader)
    let (store, controller) = makeUltraController(
        engine: engine,
        ultraDurationSeconds: ultraNeverExpires,
        ultraDeadlineSeconds: ultraNeverExpires
    )
    store.setOverlayEnabled(false)   // 캐릭터를 꺼 뒀어도 격발은 그대로 재생된다(사용자 결정).

    controller.handleReceivedPokes([ultraPoke(at: clock.now)])
    #expect(controller.isUltraActive)
    let ultraText = engine.greetingText

    // 격발 리액션만 만료시킨다. 컨트롤러 격발은 그대로 살아 있다(주입 상한이 아직 멀다).
    clock.advance(ReactionKind.ultraPoked(bubbleText: "").duration + 0.1)
    #expect(engine.state == .idle, "픽스처: 엔진 리액션이 만료돼 우선순위 방어가 사라진 창이어야 한다")
    #expect(controller.isUltraActive, "픽스처: 컨트롤러 격발은 아직 살아 있어야 한다")

    controller.presentReward(.ultraCharged)

    #expect(engine.greetingText == ultraText, "격발 말풍선을 보상 통지가 갈아치웠다")
    #expect(engine.state == .idle, "격발 중에 보상 연출이 끼어들었다")
    #expect(controller.isPeekArmed == false, "격발 창 수명을 peek 타이머가 가로챘다")

    controller.endUltraTakeover()
    controller.updateWorking(false)
}

@MainActor
@Test
func rewardLeavesTheInputPinAloneOnEveryPath() {
    // ★ 이 작업의 안전 증거. v0.2.32 의 드래그 사망 사고가 정확히 이 계층(클릭 통과 못 박기)에서 났다.
    //   보상 통지는 창을 띄우고 리액션을 걸지만 **입력에 대해서는 아무 말도 하지 않아야 한다** —
    //   못 박기(pinnedIgnoresMouseEvents)가 non-nil 이 되는 순간 히트-스루 기계가 통째로 멈추고
    //   캐릭터는 클릭도 드래그도 받지 못한다. 격발만이 그 값을 만질 자격이 있다.
    let clock = ManualClock(Date(timeIntervalSince1970: 705_000))
    let engine = ReactionEngine(clock: clock.reader)
    let (store, controller) = makeUltraController(
        engine: engine,
        ultraDurationSeconds: ultraNeverExpires,
        ultraDeadlineSeconds: ultraNeverExpires
    )

    // (a) 숨김 peek 경로.
    store.setOverlayEnabled(false)
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)
    controller.presentReward(.ultraCharged)
    #expect(controller.isPeekArmed, "픽스처: 이 경로가 실제로 peek 를 탔어야 한다")
    #expect(controller.pinnedIgnoresMouseEventsValue == nil, "peek 보상이 클릭 통과를 못 박았다")

    // (b) 정상 표시 경로.
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    #expect(controller.pinnedIgnoresMouseEventsValue == nil)
    controller.presentReward(.ultraCharged)
    #expect(controller.pinnedIgnoresMouseEventsValue == nil, "표시 중 보상이 클릭 통과를 못 박았다")

    // (c) 격발 중 경로 — 못 박기는 격발의 것이라 **true 그대로**여야 한다(보상이 풀어서도 안 된다).
    controller.handleReceivedPokes([ultraPoke(at: clock.now)])
    #expect(controller.pinnedIgnoresMouseEventsValue == true, "픽스처: 격발이 못 박기를 세웠어야 한다")
    controller.presentReward(.ultraCharged)
    #expect(controller.pinnedIgnoresMouseEventsValue == true, "보상이 격발의 못 박기를 풀었다 — 5초가 막다 말다 한다")

    controller.endUltraTakeover()
    #expect(controller.pinnedIgnoresMouseEventsValue == nil, "격발이 걷히면 못 박기도 함께 풀린다")
    stopWorking(store, controller)
}

@MainActor
@Test
func rewardStillPeeksWhenIntentSaysVisibleButTheWindowIsNot() {
    // 정상 경로 판정이 `shouldBeVisible` **만** 보면 안 되는 이유. 그 값은 **의도**이고 실제 창이 아니다 —
    // 둘이 어긋나는 구간이 실재한다(근무 시작 직후 프레임 전이, 화면 구성 변경으로 창이 내려간 뒤,
    // 격발 원복 도중). 그 구간에서 request 만 하면 연출이 **아무도 못 보는 곳에서 소진**되고,
    // 보상은 재전송이 없으므로 그대로 사라진다. handleReceivedPokes(:886)가 같은 이유로 두 값을 함께 본다.
    //
    // (이 단언이 없으면 `panel.isVisible` 조건을 지워도 스위트가 초록이었다 — 실제로 확인하고 이 테스트를 얹었다.)
    let clock = ManualClock(Date(timeIntervalSince1970: 706_000))
    let engine = ReactionEngine(clock: clock.reader)
    let (store, controller) = makeUltraController(engine: engine)
    store.setOverlayEnabled(true)
    startWorking(store, controller)
    clock.advance(ReactionKind.commuteStart.duration + 0.1)

    // 의도는 '표시', 실제 창은 내려가 있는 구간.
    controller.panel.orderOut(nil)
    #expect(controller.shouldBeVisible, "픽스처: 의도는 표시여야 한다")
    #expect(controller.panel.isVisible == false, "픽스처: 실제 창은 내려가 있어야 한다")

    controller.presentReward(.ultraCharged)

    #expect(controller.panel.isVisible, "창이 내려간 사이 보상이 아무도 못 보는 곳에서 소진됐다")
    #expect(engine.greetingText == "울트라 +1!")

    stopWorking(store, controller)
}
