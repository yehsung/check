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
//     교체를 거절하면 양보로 떨어진다(C) · 종료가 시작된 실행은 답하지 않는다(B) · 다시 열기는 남은 뒤 유예가 지나야 연다.
//  ④ 소스 계약(주석을 걷고) — 대기 갈래가 SIGTERM 설치 뒤 · 모든 배선 앞 · 아이콘 조건 · `deliverImmediately: true` · 다시 열기 · 종료 훅.
//  ⑤ 스토어(진짜 `WorkTimerStore` — 서버 호출 수 · 저장본으로) — 기다리는 동안 깨어남·인편이 서버를 치지 않는다 · 기다리다 남으면
//     상대가 끝나며 남긴 큐·토큰을 다시 읽는다.

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

    @Test func 탈출구를_켠_실행은_없는_것으로_치고_양보도_교체도_하지_않는다() {
        let me = sigInstance(400, at: 9, path: "/Applications/aing-check.app")
        let local = sigInstance(300, at: 0, path: "/Users/dev/check/dist/aing-check.app")
        let tag = SingleInstanceGuard.exemptionTag(local)
        #expect(tag == "300|/Users/dev/check/dist/aing-check.app")
        #expect(sigDecide(me: me, others: [local, me]) == .deferTo(300), "대조군이 헛돈다 — 먼저 뜬 로컬 빌드에 원래 양보한다")
        #expect(sigDecide(me: me, others: [local, me], exempt: [tag]) == .proceed,
                "탈출구를 켠 로컬 빌드에 설치본이 양보해 조용히 꺼진다")
        // 읽기 전용 자리에서 탈출구로 띄운 실행도 끝내지 않는다.
        let dmgDev = sigInstance(301, at: 0, path: "/Volumes/aing-check/aing-check.app")
        #expect(sigDecide(me: me, others: [dmgDev], exempt: [SingleInstanceGuard.exemptionTag(dmgDev)]) == .proceed)
        // 같은 pid 를 다시 받은 다른 자리의 실행은 가리지 않는다(남은 줄이 설치본을 숨기지 않는다).
        let reused = sigInstance(300, at: 0, path: "/Users/u/Applications/aing-check.app")
        #expect(sigDecide(me: me, others: [reused], exempt: [tag]) == .deferTo(300))
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
        // 탈출구 키는 표준 저장소에서 읽힌다 — 켜져 있으면 판정 없이 남고, 자기를 탈출구 목록에 적는다(그래서 목록을 한 번 본다).
        defaults.set(true, forKey: SingleInstanceGuard.allowMultipleKey)
        asked = 0
        let escaped = SingleInstanceState.live(arguments: ["check"], defaults: defaults, isRunningTests: false,
                                               snapshot: { asked += 1; return older })
        #expect(escaped.hasProceeded && asked == 1)
        #expect(defaults.stringArray(forKey: SingleInstanceGuard.exemptInstancesKey) == ["200|/Applications/aing-check.app"])
    }

    @Test func 탈출구로_띄운_로컬_빌드_뒤에_설치본이_다시_떠도_그쪽에_양보하지_않는다() {
        // 같은 저장소(번들 ID kingcheck)를 쓰는 두 실행. 로컬 빌드는 탈출구를 인자 영역으로만 켠다 — 설치본에는 그 키가 없다.
        let shared = CheckTestScratch.defaults()
        let local = sigInstance(300, at: 0, path: "/Users/dev/check/dist/aing-check.app")
        let installed = sigInstance(400, at: 9, path: "/Applications/aing-check.app")
        let both = SingleInstanceGuard.Snapshot(me: installed, others: [local, installed])
        // 지난 실행이 남긴 줄 — 지금 떠 있지 않은 것은 로컬 빌드가 뜰 때 걷힌다.
        shared.set(["999|/Users/dev/check/dist/aing-check.app"], forKey: SingleInstanceGuard.exemptInstancesKey)
        shared.set(true, forKey: SingleInstanceGuard.allowMultipleKey)
        let localState = SingleInstanceState.live(arguments: ["check"], defaults: shared, isRunningTests: false,
                                                  snapshot: { SingleInstanceGuard.Snapshot(me: local, others: [local]) })
        #expect(localState.hasProceeded)
        #expect(shared.stringArray(forKey: SingleInstanceGuard.exemptInstancesKey) == ["300|/Users/dev/check/dist/aing-check.app"])
        // 설치본이 다시 뜬다(brew 재실행 · 로그인 · 다시 열기) — 탈출구 키는 로컬 빌드의 인자 영역에만 있었다.
        shared.removeObject(forKey: SingleInstanceGuard.allowMultipleKey)
        let installedState = SingleInstanceState.live(arguments: ["check"], defaults: shared, isRunningTests: false,
                                                      snapshot: { both })
        #expect(installedState.hasProceeded && installedState.menuBarInserted,
                "설치본이 탈출구를 켠 로컬 빌드에 양보해 조용히 꺼진다: \(installedState.launchDecision)")
        // 기다린 상대가 사라진 뒤의 다시 판정(`redecide` 가 부르는 함수)도 같은 목록을 읽는다.
        #expect(SingleInstanceGuard.currentDecision(arguments: ["check"], defaults: shared, isRunningTests: false,
                                                    snapshot: { both }) == .proceed)
        // 대조군: 목록이 없으면 같은 그림에서 로컬 빌드에 양보한다(이 시험이 헛돌지 않는다).
        let bare = SingleInstanceState.live(arguments: ["check"], defaults: CheckTestScratch.defaults("bare"),
                                            isRunningTests: false, snapshot: { both })
        #expect(bare.launchDecision == .deferTo(300))
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

    @Test func 다시_열기는_남은_뒤_유예가_지나야_팝오버를_연다() async throws {
        let launched = Date()
        let state = SingleInstanceState(launchDecision: .proceed, now: launched)
        #expect(state.isServing)
        #expect(!state.acceptsReopen(now: launched.addingTimeInterval(2)),
                "brew 원클릭 끝의 open -a(이미 떠 있는 새 판에 온다)가 팝오버를 열어 키보드를 뺏는다")
        #expect(state.acceptsReopen(now: launched.addingTimeInterval(SingleInstanceGuard.reopenGraceSeconds)))
        state.beginTerminating()
        #expect(!state.acceptsReopen(now: launched.addingTimeInterval(600)), "끝나는 실행이 다시 열기에 팝오버를 연다")
        // 기다리는 실행은 다시 열기에 답하지 않고, 기다리다 남으면 그 시각부터 유예를 센다.
        let waiting = SingleInstanceState(launchDecision: .deferTo(100))
        #expect(!waiting.acceptsReopen(now: Date().addingTimeInterval(600)))
        let probe = SIGEffectsProbe()
        probe.alive[100] = 1
        #expect(await waiting.resolve(effects: probe.effects))
        let resolvedAt = try #require(waiting.proceededAt)
        #expect(!waiting.acceptsReopen(now: resolvedAt.addingTimeInterval(1)))
        #expect(waiting.acceptsReopen(now: resolvedAt.addingTimeInterval(SingleInstanceGuard.reopenGraceSeconds)))
        // 사람이 막 띄운 앱을 또 여는 창은 짧아야 한다(그 사이 다시 열기는 아무 일도 안 한다).
        #expect(SingleInstanceGuard.reopenGraceSeconds >= 10 && SingleInstanceGuard.reopenGraceSeconds <= 30)
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
        #expect(resolve.contains("let store = store store.awaitingAnotherInstance = true Task { @MainActor in if await state.resolve(effects: .live()) { store.resumeAfterAnotherInstance() continueLaunching() } else { NSApp.terminate(nil) } }"),
                "기다리는 동안 스토어 대기 표식 · 남으면 저장 상태 다시 읽기 → 시작 이어 가기 · 양보면 종료로 이어지지 않는다: \(resolve)")
    }

    @Test func 메뉴바_아이콘_삽입은_하나만_실행_상태에도_묶여_있다() throws {
        let raw = try sigSource("CheckApp.swift")
        let lines = raw.components(separatedBy: "\n")
        let inserted = lines.filter { $0.contains("MenuBarExtra(isInserted:") }
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy {
            $0.contains("get: { appDelegate.retirement.menuBarInserted && appDelegate.singleInstance.menuBarInserted }")
        }, "아이콘 삽입이 하나만 실행 상태를 읽지 않는다 — 양보할 실행에도 아이콘이 선다: \(inserted)")
        // 쓰기(사용자가 ⌘-끌기로 뺐다 → 종료)도 남기로 정해진 실행에서만 판단한다.
        #expect(sigCollapsed(raw).contains("set: { inserted in guard appDelegate.singleInstance.menuBarInserted, appDelegate.retirement.shouldQuitAfterMenuBarWrite(inserted: inserted) else { return }"),
                "아이콘을 빼 둔 대기 중의 쓰기를 사용자가 뺀 것으로 읽는다")
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
        #expect(helper.contains("requestQuit: { pid in guard let target = NSRunningApplication(processIdentifier: pid), !target.isTerminated, target.bundleIdentifier == Bundle.main.bundleIdentifier else { return } _ = kill(pid, SIGTERM) }"),
                "교체가 SIGTERM(0.3.49 부터 평소 종료 · 근무 마무리)이 아니거나 보내기 전에 같은 앱인지 보지 않는다")
        #expect(!helper.contains(".terminate()"),
                "종료 Apple Event 로 교체한다 — 공증 판(hardened runtime · 자동화 자격 없음)에서 막히면 DMG 사본이 남고 설치본이 꺼진다")
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
        #expect(reopen == "{ if singleInstance.acceptsReopen(now: Date()) { presentForAnotherLaunch() } return false }",
                "다시 열기가 유예 없이 팝오버를 연다 — brew 원클릭 끝의 open -a 가 키보드를 뺏는다: \(reopen)")
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

    @Test func 깨어남_처리는_대기_표식을_서버로_가는_어느_가지보다_먼저_본다() throws {
        // ⑤ 의 행동 시험은 깨어남 → 인편 경로로 재서 인편 쪽 게이트만으로도 초록이다 — 깨어남의 다른 가지(재연결 · 집중 모드 만료
        // PATCH)까지 막는지는 자리로 잰다.
        let store = sigCollapsed(try sigSource("WorkTimerStore.swift"))
        let wake = try #require(sigBlock(after: "func handleWake(at date: Date = Date())", in: store))
        let gate = try #require(wake.range(of: "guard !awaitingAnotherInstance else { return }"), "기다리는 실행이 깨어나며 서버를 친다")
        for branch in ["beginWakeGate()", "realtimeApply(.didWake, at: date)", "retryMiniGamePendingSubmitIfAny()",
                       "evaluateFocusStageExpiry(now: clock())"] {
            let site = try #require(wake.range(of: branch), "깨어남에 [\(branch)] 가 없다")
            #expect(gate.upperBound <= site.lowerBound, "[\(branch)] 가 대기 표식보다 먼저다")
        }
        let miniGame = sigCollapsed(try sigSource("WorkTimerStoreMiniGame.swift"))
        let retry = try #require(sigBlock(after: "func retryMiniGamePendingSubmitIfAny(fromTrigger: Bool = true)", in: miniGame))
        #expect(retry.hasPrefix("{ #if !CHECK_MAS guard !awaitingAnotherInstance else { return } #endif loadMiniGamePendingSubmitsIfNeeded()"),
                "기다리는 실행이 남는 실행의 인편을 읽어 민다: \(retry.prefix(120))")
    }

    // MARK: ⑤ 스토어

    @Test func 기다리는_실행의_스토어는_깨어나도_인편을_밀지_않고_남으면_민다() async throws {
        let userID = "00000000-0000-0000-0000-000000000002"
        let pending = MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 7, token: "tok-sig-wake",
                                            tokenIssuedAt: Date(), recordedAt: Date(), attempts: 0)
        let host = "sig-wake-awaiting"
        let store = sigSignedInStore(host: host)
        defer { sigStop(store) }
        try #require(store.session?.userID == userID)
        store.defaults.set(try JSONEncoder().encode([pending]), forKey: WorkTimerStore.miniGamePendingKey(userID: userID))
        store.awaitingAnotherInstance = true
        store.handleWake(at: Date())                 // 덮개를 여닫았다
        store.retryMiniGamePendingSubmitIfAny()      // 그 밖의 방아쇠
        await sigSettle { false }
        #expect(URLProtocolStub.requests(forHost: host).isEmpty,
                "기다리는 실행이 저장 세션으로 서버를 쳤다 — 남는 실행과 갱신 토큰을 나눠 돌린다")

        // 남기로 정해지면 같은 스토어 · 같은 인편이 실제로 나간다(대조군 — 이 시험이 헛돌지 않는다).
        store.resumeAfterAnotherInstance()
        #expect(!store.awaitingAnotherInstance)
        store.handleWake(at: Date())
        await sigSettle { URLProtocolStub.requests(forHost: host).contains { $0.url?.path == "/rest/v1/rpc/minigame_submit_score" } }
        #expect(URLProtocolStub.requests(forHost: host).contains { $0.url?.path == "/rest/v1/rpc/minigame_submit_score" },
                "대조군이 헛돈다 — 남은 실행의 깨어남이 인편을 안 밀었다")
    }

    @Test func 기다리다_남은_실행은_상대가_끝나며_남긴_큐와_토큰을_다시_읽는다() throws {
        let userID = "00000000-0000-0000-0000-000000000002"
        let store = sigSignedInStore(host: "sig-resume")
        defer { sigStop(store) }
        try #require(store.session?.refreshToken == "old-refresh-token")
        store.awaitingAnotherInstance = true
        // 이 실행의 init **뒤에** 상대가 끝났다 — 근무를 마무리하며(오프라인) 퇴근 항목을 큐에 넣고, 마무리 왕복에서 토큰을 돌렸다.
        let othersStop = PendingWorkItem(id: UUID(), operation: .stop(durationSeconds: 3_600), sessionID: UUID().uuidString.lowercased(),
                                         sessionStartedAt: Date().addingTimeInterval(-3_600), endedAt: Date(), ownerUserID: userID)
        store.defaults.set(try JSONEncoder().encode([othersStop]), forKey: WorkTimerStore.pendingWorkQueueKey)
        store.tokenVault.write("rotated-access-token", key: WorkTimerStore.accessTokenKey)
        store.tokenVault.write("rotated-refresh-token", key: WorkTimerStore.refreshTokenKey)

        store.resumeAfterAnotherInstance()
        #expect(!store.awaitingAnotherInstance)
        #expect(store.session?.refreshToken == "rotated-refresh-token", "낡은 갱신 토큰으로 시작한다 — 재사용으로 읽혀 로그아웃된다")
        #expect(store.session?.accessToken == "rotated-access-token" && store.session?.userID == userID)
        #expect(store.workStateOwnerUserID == userID)
        #expect(store.pendingItems == [othersStop])
        // 이 실행의 다음 변경(큐는 바뀔 때마다 통째로 저장한다)이 와도 상대의 퇴근 항목이 남는다.
        let mine = PendingWorkItem(id: UUID(), operation: .start, sessionID: UUID().uuidString.lowercased(),
                                   sessionStartedAt: Date(), endedAt: nil, ownerUserID: userID)
        store.pendingItems.append(mine)
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: store.defaults) == [othersStop, mine])

        // 대조군: 다시 읽지 않은 스토어는 같은 순서에서 상대의 퇴근 항목을 덮어 지운다(이 시험이 헛돌지 않는다).
        let control = sigSignedInStore(host: "sig-resume-control")
        defer { sigStop(control) }
        control.defaults.set(try JSONEncoder().encode([othersStop]), forKey: WorkTimerStore.pendingWorkQueueKey)
        control.pendingItems.append(mine)
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: control.defaults) == [mine])
    }

    @Test func 하나만_실행은_전부_앱스토어_판_울타리_안에_있다() throws {
        let needles = ["singleInstance", "SingleInstance", "listenForAnotherLaunch", "anotherLaunchAskedToPresent",
                       "presentForAnotherLaunch", "resolveAnotherInstance", "applicationShouldHandleReopen",
                       "awaitingAnotherInstance", "resumeAfterAnotherInstance"]
        var hits = 0
        var storeHits = 0
        for name in ["CheckApp.swift", "SingleInstanceGuard.swift", "WorkTimerStore.swift", "WorkTimerStoreMiniGame.swift"] {
            let source = try sigSource(name)
            let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
            for (index, line) in source.components(separatedBy: "\n").enumerated() where needles.contains(where: line.contains) {
                hits += 1
                if name.hasPrefix("WorkTimerStore") { storeHits += 1 }
                #expect(excluded.contains(index), "앱스토어 판에서도 컴파일되는 하나만 실행 코드: \(name):\(index + 1) \(line)")
            }
        }
        #expect(hits >= 15 && storeHits >= 4, "검사가 헛돈다(\(hits)곳 · 스토어 \(storeHits)곳)")
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
                       allowsMultiple: Bool = false, isRunningTests: Bool = false,
                       exempt: Set<String> = []) -> SingleInstanceGuard.Decision {
    SingleInstanceGuard.decide(me: me, others: others, arguments: arguments, allowsMultiple: allowsMultiple,
                               isRunningTests: isRunningTests, exempt: exempt)
}

/// 저장 세션이 있는 스토어(토큰이 저장소에 있다 — `resumeAfterAnotherInstance` 가 다시 읽는 자리). 서버는 스텁이다.
@MainActor
private func sigSignedInStore(host: String, function: String = #function) -> WorkTimerStore {
    let defaults = CheckTestScratch.defaults(host, function: function)
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    return WorkTimerStore(
        service: SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                     session: URLSession(configuration: .stubbed)),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

@MainActor
private func sigStop(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.pokePollTask?.cancel()
}

@MainActor
private func sigSettle(_ done: () -> Bool) async {
    for _ in 0..<50 {
        if done() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
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
