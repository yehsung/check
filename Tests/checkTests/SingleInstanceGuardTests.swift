import AppKit
import Foundation
import Observation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.69 하나만 실행 — 같은 앱을 두 번 열면 아이콘이 둘 생기던 결함
//
// 2026-10-30 신고(맥 0.3.68): "로그인하지 않을 상태로 두번 열면 아이콘 2개 생겨요. (심지어 하나 로그인하고 했는데 나머지 하나는
// 자동으로 로그인 되는 것도 아님)". LaunchServices 는 사본 경로로 실행을 합쳐서, DMG 안 사본과 `/Applications` 사본(또는 `open -n`)은
// 프로세스 둘이 된다. 이 스위트가 재는 것:
//  ① 판정(`SingleInstanceGuard.decide`) — 갈래마다: 먼저 뜬 쪽에 양보 · 동시 실행에서 정확히 하나 · 물러남 재실행 인자 · 끝난 프로세스만 ·
//     탈출구 · 읽기 전용 자리 사본 교체 · 내가 읽기 전용 자리면 양보 · 실행 시각을 모르면 pid 순.
//  ② 실제 실행의 조립(`SingleInstanceState.live`)을 가짜 프로세스 목록으로 **그대로** 부른다 — 테스트 프로세스는 언제나 남는다.
//  ③ 상태와 실행(`resolve`) — 가짜 효과로: 기다리는 동안만 아이콘이 빠지고 남으면 들어간다(판정문 A) · 상대가 끝나면 남는다(B) ·
//     교체를 거절하면 양보로 떨어진다(C) · 종료가 시작된 실행은 답하지 않는다(B).
//  ④ 소스 계약(주석을 걷고) — 대기 갈래가 SIGTERM 설치 뒤 · 모든 배선 앞 · 아이콘 조건 · `deliverImmediately: true` · 다시 열기 · 종료 훅.

@Suite("하나만 실행 (v0.3.69)")
@MainActor
struct SingleInstanceGuardTests {

    // MARK: ① 판정

    @Test func 먼저_뜬_다른_실행이_있으면_그쪽에_양보한다() {
        let me = sigInstance(200, at: 5)
        let older = sigInstance(100, at: 0)
        #expect(sigDecide(me: me, others: [older, me]) == .deferTo(100))
        // 내가 먼저 떴으면 남는다(나중에 뜬 쪽이 양보한다).
        #expect(sigDecide(me: older, others: [older, me]) == .proceed)
    }

    @Test func 동시에_떠도_정확히_하나만_남는다() {
        // 같은 시각 — pid 가 작은 쪽이 남는다.
        let a = sigInstance(100, at: 0)
        let b = sigInstance(200, at: 0)
        let all = [a, b]
        let fromA = sigDecide(me: a, others: all)
        let fromB = sigDecide(me: b, others: all)
        #expect([fromA, fromB].filter { $0 == .proceed }.count == 1, "남는 쪽이 하나가 아니다: \(fromA) / \(fromB)")
        #expect(fromA == .proceed && fromB == .deferTo(100))
        // 시각과 pid 순서가 엇갈려도(pid 가 돌아 감긴 경우) 양쪽이 같은 하나를 고른다 — 먼저 뜬 쪽.
        let early = sigInstance(300, at: 0)
        let late = sigInstance(200, at: 1)
        let fromEarly = sigDecide(me: early, others: [early, late])
        let fromLate = sigDecide(me: late, others: [early, late])
        #expect(fromEarly == .proceed && fromLate == .deferTo(300))
        // 셋이 동시에 떠도 남는 쪽은 하나다.
        let trio = [sigInstance(10, at: 0), sigInstance(11, at: 0), sigInstance(12, at: 0)]
        let survivors = trio.filter { sigDecide(me: $0, others: trio) == .proceed }
        #expect(survivors.map(\.pid) == [10])
    }

    @Test func 물러남_재실행_인자가_있으면_양보하지_않는다() {
        let me = sigInstance(200, at: 5)
        let older = sigInstance(100, at: 0)
        let arguments = ["/Applications/aing-check.app/Contents/MacOS/check",
                         AppStoreEditionRetirement.appStoreEditionArgument, "/Applications/AingCheck.app"]
        #expect(sigDecide(me: me, others: [older], arguments: arguments) == .proceed,
                "앱스토어 판 물러남의 자기 재실행이 곧 끝날 옛 인스턴스에 양보해 둘 다 사라진다")
        // 실제 재실행 인자(`relaunchArguments`)가 이 인자를 늘 담는다 — 인자 이름이 갈리면 예외가 헛돈다.
        let relaunch = AppStoreEditionRetirement.relaunchArguments(
            finishedWork: true, appStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"))
        #expect(sigDecide(me: me, others: [older], arguments: ["check"] + relaunch) == .proceed)
    }

    @Test func 끝난_프로세스와_나_자신만_있으면_혼자다() {
        let me = sigInstance(200, at: 5)
        let dead = sigInstance(100, at: 0, terminated: true)
        #expect(sigDecide(me: me, others: [dead, me]) == .proceed)
        #expect(sigDecide(me: me, others: []) == .proceed)
        #expect(sigDecide(me: me, others: [me]) == .proceed, "실행 중 앱 목록에 든 나 자신에게 양보한다")
    }

    @Test func 탈출구와_테스트_프로세스는_판정하지_않는다() {
        let me = sigInstance(200, at: 5)
        let older = sigInstance(100, at: 0)
        #expect(sigDecide(me: me, others: [older], allowsMultiple: true) == .proceed)
        #expect(sigDecide(me: me, others: [older], isRunningTests: true) == .proceed)
        #expect(SingleInstanceGuard.allowMultipleKey == "check.allowMultipleInstances")
    }

    @Test func 읽기_전용_자리의_사본이_떠_있고_내가_설치된_자리면_그쪽을_끝낸다() {
        let me = sigInstance(200, at: 5, path: "/Applications/aing-check.app")
        let dmg = sigInstance(100, at: 0, path: "/Volumes/aing-check/aing-check.app")
        #expect(sigDecide(me: me, others: [dmg, me]) == .replace(100))
        // 같은 그림을 DMG 쪽에서 보면 양보다 — 양쪽이 같은 하나(설치된 자리)를 남긴다.
        #expect(sigDecide(me: dmg, others: [dmg, me]) == .deferTo(200))
        // App Translocation 자리도 같다.
        let translocated = sigInstance(90, at: 0, path: "/private/var/folders/x1/abc/d/AppTranslocation/UUID/d/aing-check.app")
        #expect(sigDecide(me: me, others: [translocated]) == .replace(90))
    }

    @Test func 내가_읽기_전용_자리면_설치된_자리의_실행에_양보한다() {
        // 설치된 쪽이 나중에 떴어도 — DMG 사본이 남으면 업데이트가 막히고 디스크 이미지를 꺼낼 수 없다.
        let me = sigInstance(100, at: 0, path: "/Volumes/aing-check/aing-check.app")
        let installed = sigInstance(200, at: 5, path: "/Applications/aing-check.app")
        #expect(sigDecide(me: me, others: [installed]) == .deferTo(200))
    }

    @Test func 먼저_뜬_설치본이_있으면_읽기_전용_사본을_끝내지_않고_그쪽에_양보한다() {
        let me = sigInstance(300, at: 9, path: "/Applications/aing-check.app")
        let installed = sigInstance(100, at: 0, path: "/Users/u/Applications/aing-check.app")
        let dmg = sigInstance(200, at: 1, path: "/Volumes/aing-check/aing-check.app")
        #expect(sigDecide(me: me, others: [installed, dmg]) == .deferTo(100))
        // 남는 설치본의 관점에서는 읽기 전용 사본이 교체 대상이다(다음 회차에 다시 보면 나온다).
        #expect(sigDecide(me: installed, others: [installed, dmg, me]) == .replace(200))
    }

    @Test func 실행_시각을_모르면_pid_순으로_정한다() {
        let me = sigInstance(50, at: nil)
        let other = sigInstance(60, at: 0)
        #expect(sigDecide(me: me, others: [other]) == .proceed)
        #expect(sigDecide(me: other, others: [me]) == .deferTo(50))
        // 시각이 앞서도 상대 시각을 모르면 pid 로만 줄 세운다(양쪽이 같은 규칙을 써야 하나가 남는다).
        let early = sigInstance(70, at: 0)
        let unknown = sigInstance(60, at: nil)
        #expect(sigDecide(me: early, others: [unknown]) == .deferTo(60))
        #expect(sigDecide(me: unknown, others: [early]) == .proceed)
    }

    @Test func 읽기_전용_자리_판정은_업데이트_실행기와_같은_규칙이다() {
        for path in [
            "/Volumes/aing-check/aing-check.app",
            "/private/var/folders/x1/abc/d/AppTranslocation/UUID/d/aing-check.app",
            "/private/var/folders/x1/abc/T/aing-check.app",
        ] {
            #expect(SingleInstanceGuard.isTemporaryLocation(path), "\(path)")
            #expect(UpdateRunner.isReadOnlyLocation(path))
            // 업데이트 실행기의 속성이 같은 함수를 부른다(부르는 자리를 잰다).
            let runner = UpdateRunner(resolvePath: { $0 }, bundlePath: path, currentBuild: 1)
            #expect(runner.isRunningFromReadOnlyLocation)
        }
        for path in ["/Applications/aing-check.app", "/Users/u/Applications/aing-check.app"] {
            #expect(!SingleInstanceGuard.isTemporaryLocation(path), "\(path)")
            let runner = UpdateRunner(resolvePath: { $0 }, bundlePath: path, currentBuild: 1)
            #expect(!runner.isRunningFromReadOnlyLocation)
        }
    }

    // MARK: ② 실제 실행의 조립

    @Test func 테스트_프로세스에서는_언제나_남고_프로세스_목록을_묻지도_않는다() {
        #expect(CheckPanelVisibility.isRunningTests)
        var asked = 0
        let state = SingleInstanceState.live(
            arguments: ["check"],
            defaults: CheckTestScratch.defaults(),
            snapshot: {
                asked += 1
                return SingleInstanceGuard.Snapshot(me: sigInstance(200, at: 5), others: [sigInstance(100, at: 0)])
            }
        )
        #expect(state.launchDecision == .proceed && state.hasProceeded && state.menuBarInserted)
        #expect(!state.isPending && !state.terminatesImmediately)
        #expect(asked == 0, "테스트 프로세스가 실행 중 앱 목록을 묻는다")
    }

    @Test func 실제_실행의_조립은_먼저_뜬_실행을_보면_아이콘을_빼고_기다린다() {
        let defaults = CheckTestScratch.defaults()
        var asked = 0
        let older = SingleInstanceGuard.Snapshot(me: sigInstance(200, at: 5), others: [sigInstance(100, at: 0), sigInstance(200, at: 5)])
        let state = SingleInstanceState.live(arguments: ["check"], defaults: defaults, isRunningTests: false,
                                             snapshot: { asked += 1; return older })
        #expect(asked == 1)
        #expect(state.launchDecision == .deferTo(100))
        #expect(state.isPending && !state.menuBarInserted, "양보를 기다리는 실행에 아이콘이 들어간다")
        #expect(state.terminatesImmediately, "남지 않은 실행이 종료 때 퇴근 동기화를 탄다 — 남는 쪽 근무를 닫는다")
        // 혼자면 첫 렌더부터 아이콘이 있다.
        let alone = SingleInstanceState.live(arguments: ["check"], defaults: defaults, isRunningTests: false,
                                             snapshot: { SingleInstanceGuard.Snapshot(me: sigInstance(200, at: 5), others: [sigInstance(200, at: 5)]) })
        #expect(alone.hasProceeded && alone.menuBarInserted)
        // 물러남 재실행 인자는 실제 인자 목록에서 읽힌다.
        let relaunch = SingleInstanceState.live(
            arguments: ["check", AppStoreEditionRetirement.appStoreEditionArgument, "/Applications/AingCheck.app"],
            defaults: defaults, isRunningTests: false, snapshot: { older })
        #expect(relaunch.hasProceeded)
        // 탈출구 키는 표준 저장소에서 읽힌다 — 켜져 있으면 목록을 묻지도 않는다.
        defaults.set(true, forKey: SingleInstanceGuard.allowMultipleKey)
        asked = 0
        let escaped = SingleInstanceState.live(arguments: ["check"], defaults: defaults, isRunningTests: false,
                                               snapshot: { asked += 1; return older })
        #expect(escaped.hasProceeded && asked == 0)
    }

    // MARK: ③ 상태와 실행

    @Test func 양보를_기다리다_상대가_끝나면_남고_아이콘이_들어간다() async {
        let probe = SIGEffectsProbe()
        probe.alive[100] = 3
        let state = SingleInstanceState(launchDecision: .deferTo(100))
        #expect(!state.menuBarInserted && state.isPending)
        let iconChanged = SIGObservationFlag()
        withObservationTracking { _ = state.menuBarInserted } onChange: { iconChanged.fired = true }
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(proceeds, "마침 종료 중이던 실행에 양보해 0개가 된다")
        #expect(state.hasProceeded && state.menuBarInserted && !state.terminatesImmediately)
        #expect(iconChanged.fired, "아이콘 조건이 관찰되지 않는다 — 남아도 아이콘이 안 들어간다")
        #expect(probe.presents == [100], "먼저 뜬 쪽에 팝오버를 열어 달라 알리지 않았다")
        #expect(probe.quits.isEmpty, "양보하면서 상대를 끝낸다")
        #expect(probe.redecideCalls == 1, "상대가 끝난 뒤 목록을 다시 보지 않는다")
        #expect(state.isServing)
    }

    @Test func 양보를_기다려도_상대가_살아_있으면_아이콘_없이_끝난다() async {
        let probe = SIGEffectsProbe()
        probe.alive[100] = .max
        let state = SingleInstanceState(launchDecision: .deferTo(100))
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(!proceeds)
        #expect(state.phase == .yielding && !state.menuBarInserted && state.terminatesImmediately && !state.isServing)
        #expect(probe.presents == [100] && probe.quits.isEmpty)
        // 기다린 시간은 양보 대기(근무 마무리 상한 3초 + 여유)만큼이다.
        let expected = Int((SingleInstanceGuard.deferralWaitSeconds / SingleInstanceGuard.pollSeconds).rounded(.up))
        #expect(probe.sleeps == expected)
        #expect(SingleInstanceGuard.deferralWaitSeconds > 3, "근무를 마무리하며 끝나는 실행(상한 3초)을 끝까지 못 기다린다")
        #expect(probe.redecideCalls == 0)
    }

    @Test func 읽기_전용_자리_사본을_끝내고_남는다() async {
        let probe = SIGEffectsProbe()
        probe.alive[7] = 2
        let state = SingleInstanceState(launchDecision: .replace(7))
        #expect(!state.menuBarInserted, "교체가 끝나기 전에 아이콘이 둘 선다")
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(proceeds && state.menuBarInserted)
        #expect(probe.quits == [7] && probe.presents.isEmpty)
    }

    @Test func 읽기_전용_자리_사본이_끝나지_않으면_양보로_떨어진다() async {
        let probe = SIGEffectsProbe()
        probe.alive[7] = .max
        let state = SingleInstanceState(launchDecision: .replace(7))
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(!proceeds, "거절한 사본과 둘이 남는다")
        #expect(probe.quits == [7] && probe.presents == [7], "끝내기를 거절한 쪽 팝오버를 열어 달라 알리지 않았다")
        #expect(state.phase == .yielding && !state.menuBarInserted)
        let replaceSteps = Int((SingleInstanceGuard.replaceWaitSeconds / SingleInstanceGuard.pollSeconds).rounded(.up))
        let deferSteps = Int((SingleInstanceGuard.deferralWaitSeconds / SingleInstanceGuard.pollSeconds).rounded(.up))
        #expect(probe.sleeps == replaceSteps + deferSteps)
    }

    @Test func 상대가_끝난_뒤_다시_본_목록에_또_있으면_그쪽에_양보한다() async {
        // 셋이 떠 있었다: 기다린 100 은 끝났지만 150 이 남아 있다 — 둘 다 남으면 안 된다.
        let probe = SIGEffectsProbe()
        probe.alive[100] = 1
        probe.alive[150] = .max
        probe.redecisions = [.deferTo(150)]
        let state = SingleInstanceState(launchDecision: .deferTo(100))
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(!proceeds)
        #expect(probe.presents == [100, 150])
    }

    @Test func 기다린_상대가_매번_사라지면_정해진_회차_뒤에_남는다() async {
        let probe = SIGEffectsProbe()
        probe.redecisions = [.deferTo(101), .deferTo(102), .deferTo(103)]
        let state = SingleInstanceState(launchDecision: .deferTo(100))
        let proceeds = await state.resolve(effects: probe.effects)
        #expect(proceeds && state.menuBarInserted, "아이콘 없이 도는 실행이 남는다")
        #expect(probe.presents.count == SingleInstanceGuard.maxRounds)
    }

    @Test func 종료가_시작된_실행은_다른_사본에_답하지_않는다() {
        let state = SingleInstanceState(launchDecision: .proceed)
        #expect(state.isServing)
        state.beginTerminating()
        #expect(!state.isServing, "끝나는 실행이 팝오버를 연다")
        // 기다리는 실행은 처음부터 답하지 않는다.
        #expect(!SingleInstanceState(launchDecision: .deferTo(1)).isServing)
    }

    // MARK: ④ 소스 계약

    @Test func 대기_갈래는_SIGTERM_설치_뒤_모든_배선_앞이고_남으면_시작을_다시_탄다() throws {
        let app = sigCollapsed(try sigSource("CheckApp.swift"))
        let launch = try #require(sigBlock(after: "func applicationDidFinishLaunching(_ notification: Notification)", in: app))
        let signal = try #require(launch.range(of: "GracefulTerminationSignal.install()"))
        let branch = try #require(launch.range(of: "if singleInstance.isPending {"), "앱 시작에 하나만 실행 갈래가 없다")
        #expect(signal.upperBound <= branch.lowerBound, "SIGTERM 마무리보다 하나만 실행 갈래가 먼저다")
        let branchBody = try #require(sigBlock(after: "if singleInstance.isPending", in: launch))
        #expect(branchBody == "{ resolveAnotherInstance(then: { [weak self] in self?.applicationDidFinishLaunching(notification) }) return }",
                "대기 갈래가 판정만 실행에 옮기고 곧장 돌아가지 않는다: \(branchBody)")
        for wiring in [
            "if let appStoreEdition = retirement.launchAppStoreEdition {", "startWatchingForAppStoreEdition()",
            "overlayController = CheckOverlayController(", "wireTodoBoard()", "wireSettingsWindow()", "wireGomoku()",
            "wireChess()", "wireTetrisDuel()",
            "workShortcut = WorkShortcutCoordinator(store: store, registrar: CarbonWorkShortcutRegistrar())",
            "updateCheck.startServerWatch()", "LoginItemRegistrar.registerIfNeeded(",
            "store.activateStoredSessionOnLaunch()", "masOnboarding = MacAppStoreOnboardingController(store: store)",
            "listenForAnotherLaunch()",
        ] {
            let site = try #require(launch.range(of: wiring), "앱 시작에 [\(wiring)] 가 없다")
            #expect(branch.upperBound <= site.lowerBound, "[\(wiring)] 가 하나만 실행 갈래보다 먼저다 — 양보할 실행에서도 돈다")
        }
        // 델리게이트가 실제 실행의 판정을 만들고, 남으면 시작을 잇고 양보하면 끝낸다.
        let delegate = try #require(sigBlock(after: "final class AppDelegate: NSObject, NSApplicationDelegate", in: app))
        #expect(delegate.contains("let singleInstance = SingleInstanceState.live()"))
        let resolve = try #require(sigBlock(after: "private func resolveAnotherInstance(then continueLaunching: @escaping @MainActor () -> Void)", in: app))
        #expect(resolve.contains("if await state.resolve(effects: .live()) { continueLaunching() } else { NSApp.terminate(nil) }"),
                "판정 결과가 시작 이어 가기 · 종료로 이어지지 않는다: \(resolve)")
    }

    @Test func 메뉴바_아이콘_삽입은_하나만_실행_상태에도_묶여_있다() throws {
        let raw = try sigSource("CheckApp.swift")
        let lines = raw.components(separatedBy: "\n")
        let inserted = lines.filter { $0.contains("MenuBarExtra(isInserted:") }
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy {
            $0.contains("get: { appDelegate.retirement.menuBarInserted && appDelegate.singleInstance.menuBarInserted }")
        }, "아이콘 삽입이 하나만 실행 상태를 읽지 않는다 — 양보할 실행에도 아이콘이 선다: \(inserted)")
        // 상태의 아이콘 조건은 '남기로 정해졌다' 하나다(기다리는 동안만 빠진다).
        let helper = sigCollapsed(try sigSource("SingleInstanceGuard.swift"))
        #expect(helper.contains("var menuBarInserted: Bool { hasProceeded }"))
    }

    @Test func 팝오버_요청은_즉시_배달로_보내고_받고_다시_열기도_팝오버를_연다() throws {
        let helper = sigCollapsed(try sigSource("SingleInstanceGuard.swift"))
        let presentStart = try #require(helper.range(of: "requestPresent: { pid in"), "실제 효과에 팝오버 요청 문이 없다")
        let presentEnd = try #require(helper.range(of: "requestQuit: { pid in", range: presentStart.upperBound..<helper.endIndex))
        let request = helper[presentStart.upperBound..<presentEnd.lowerBound]
        #expect(request.contains("DistributedNotificationCenter.default().postNotificationName( SingleInstanceGuard.presentRequestNotification, object: SingleInstanceGuard.notificationObject(for: pid), userInfo: nil, deliverImmediately: true )"),
                "팝오버 요청이 즉시 배달이 아니다 — 늘 비활성인 메뉴바 앱에서 알림이 보류된다: \(request)")
        // 앞에 선 이 실행이 활성화를 넘겨야 남는 쪽 팝오버가 키 입력을 받는다(협조적 활성화) — 알림보다 먼저다.
        let yield = try #require(request.range(of: "NSApp.yieldActivation(to: target)"), "활성화를 넘기지 않는다")
        let post = try #require(request.range(of: "postNotificationName("))
        #expect(yield.upperBound <= post.lowerBound)
        #expect(helper.contains("requestQuit: { pid in _ = NSRunningApplication(processIdentifier: pid)?.terminate() }"),
                "교체가 평소 종료가 아니다(강제 종료면 근무 마무리가 돌지 않는다)")
        let app = sigCollapsed(try sigSource("CheckApp.swift"))
        let listen = try #require(sigBlock(after: "private func listenForAnotherLaunch()", in: app))
        #expect(listen.contains("name: SingleInstanceGuard.presentRequestNotification"))
        #expect(listen.contains("object: SingleInstanceGuard.notificationObject(for: ProcessInfo.processInfo.processIdentifier)"),
                "대상 pid 로 거르지 않는다 — 셋째 사본의 요청에 둘 다 팝오버를 연다")
        #expect(listen.contains("suspensionBehavior: .deliverImmediately"))
        let handler = try #require(sigBlock(after: "@objc private func anotherLaunchAskedToPresent(_ notification: Notification)", in: app))
        #expect(handler == "{ presentForAnotherLaunch() }")
        let reopen = try #require(sigBlock(after: "func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool", in: app),
                                  "다시 열기 처리가 없다 — 같은 사본을 다시 열면 화면에 아무 변화가 없다")
        #expect(reopen == "{ presentForAnotherLaunch() return false }")
        let present = try #require(sigBlock(after: "private func presentForAnotherLaunch()", in: app))
        let serving = try #require(present.range(of: "guard singleInstance.isServing, !store.retiredForAppStoreEdition else { return }"),
                                   "종료 중인 실행도 팝오버를 연다")
        let popover = try #require(present.range(of: "WindowTopAnchor.presentMenuPopover()"), "팝오버를 여는 문을 부르지 않는다")
        #expect(serving.upperBound <= popover.lowerBound)
    }

    @Test func 종료_훅과_활성화_훅은_남지_않은_실행을_거른다() throws {
        let app = sigCollapsed(try sigSource("CheckApp.swift"))
        let terminate = try #require(sigBlock(after: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply", in: app))
        let begin = try #require(terminate.range(of: "singleInstance.beginTerminating()"), "종료가 시작돼도 다른 사본에 계속 답한다")
        let immediate = try #require(terminate.range(of: "if singleInstance.terminatesImmediately { return .terminateNow }"),
                                     "양보하는 실행이 퇴근 동기화를 탄다 — 남는 쪽 근무를 닫는다")
        let ownGuard = try #require(terminate.range(of: "guard store.isSignedIn, store.startedAt != nil, !store.adoptedRemoteSession else {"))
        #expect(begin.upperBound <= immediate.lowerBound && immediate.upperBound <= ownGuard.lowerBound)
        let active = try #require(sigBlock(after: "func applicationDidBecomeActive(_ notification: Notification)", in: app))
        let gate = try #require(active.range(of: "guard singleInstance.hasProceeded else { return }"),
                                "두 번째 사본이 실행되며 활성화될 때 저장 세션으로 인편을 민다")
        let retry = try #require(active.range(of: "store.retryMiniGamePendingSubmitIfAny()"))
        #expect(gate.upperBound <= retry.lowerBound)
    }

    @Test func 하나만_실행은_전부_앱스토어_판_울타리_안에_있다() throws {
        let needles = ["singleInstance", "SingleInstance", "listenForAnotherLaunch", "anotherLaunchAskedToPresent",
                       "presentForAnotherLaunch", "resolveAnotherInstance", "applicationShouldHandleReopen"]
        var hits = 0
        for name in ["CheckApp.swift", "SingleInstanceGuard.swift"] {
            let source = try sigSource(name)
            let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
            for (index, line) in source.components(separatedBy: "\n").enumerated() where needles.contains(where: line.contains) {
                hits += 1
                #expect(excluded.contains(index), "앱스토어 판에서도 컴파일되는 하나만 실행 코드: \(name):\(index + 1) \(line)")
            }
        }
        #expect(hits >= 15, "검사가 헛돈다(\(hits)곳)")
    }
}

// MARK: - 도우미

private func sigInstance(_ pid: pid_t, at seconds: Double?, path: String = "/Applications/aing-check.app",
                         terminated: Bool = false) -> SingleInstanceGuard.Instance {
    SingleInstanceGuard.Instance(
        pid: pid,
        launchDate: seconds.map { Date(timeIntervalSinceReferenceDate: 800_000_000 + $0) },
        bundlePath: path,
        isTerminated: terminated
    )
}

private func sigDecide(me: SingleInstanceGuard.Instance, others: [SingleInstanceGuard.Instance], arguments: [String] = ["check"],
                       allowsMultiple: Bool = false, isRunningTests: Bool = false) -> SingleInstanceGuard.Decision {
    SingleInstanceGuard.decide(me: me, others: others, arguments: arguments, allowsMultiple: allowsMultiple,
                               isRunningTests: isRunningTests)
}

/// `withObservationTracking(onChange:)` 이 @Sendable 클로저라 지역 변수를 못 쓴다. 발화는 대입 스레드(메인)에서 동기적으로
/// 일어나므로 잠금 없이 안전하다(그 사실 때문에 `@unchecked` 다 — V0248 의 깃발과 같다).
private final class SIGObservationFlag: @unchecked Sendable {
    var fired = false
}

/// 가짜 효과: 알림 · 종료 요청을 적고, 살아 있음은 pid 마다 남은 횟수로 답한다(0 이면 끝났다). 자지 않는다.
@MainActor
private final class SIGEffectsProbe {
    var presents: [pid_t] = []
    var quits: [pid_t] = []
    var alive: [pid_t: Int] = [:]
    var redecisions: [SingleInstanceGuard.Decision] = []
    var redecideCalls = 0
    var sleeps = 0

    var effects: SingleInstanceEffects {
        SingleInstanceEffects(
            requestPresent: { [unowned self] pid in presents.append(pid) },
            requestQuit: { [unowned self] pid in quits.append(pid) },
            isRunning: { [unowned self] pid in
                guard let left = alive[pid], left > 0 else { return false }
                alive[pid] = left == .max ? .max : left - 1
                return true
            },
            redecide: { [unowned self] in
                redecideCalls += 1
                return redecisions.isEmpty ? .proceed : redecisions.removeFirst()
            },
            sleep: { [unowned self] _ in await MainActor.run { sleeps += 1 } }
        )
    }
}

private func sigSource(_ name: String) throws -> String {
    V0351IfConfig.strippingComments(try String(contentsOf: CheckCoreSourceLayout.macDirectory.appendingPathComponent(name), encoding: .utf8))
}

private func sigCollapsed(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `anchor` 뒤 첫 `{` 부터 짝이 맞는 `}` 까지(양 끝 포함). 문자열 리터럴 안의 괄호는 건너뛴다.
private func sigBlock(after anchor: String, in source: String) -> String? {
    guard let hit = source.range(of: anchor), let open = source[hit.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var index = open
    while index < source.endIndex {
        let c = source[index]
        if inString {
            if c == "\\" {
                index = source.index(after: index)
                if index == source.endIndex { break }
            } else if c == "\"" {
                inString = false
            }
        } else if c == "\"" {
            inString = true
        } else if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
