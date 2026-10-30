import AppKit
import CheckCore
import Observation
import os

// MARK: - 하나만 실행 (v0.3.69)
//
// 2026-10-30 신고(맥 0.3.68): "로그인하지 않을 상태로 두번 열면 아이콘 2개 생겨요. (심지어 하나 로그인하고 했는데 나머지 하나는
// 자동으로 로그인 되는 것도 아님)". 앱 안에 '하나만 실행' 장치가 없었다. LaunchServices 는 번들 ID 가 아니라 **사본의 경로**로
// 실행을 합친다 — DMG 창 안의 사본(`/Volumes/…`)을 연 뒤 `/Applications` 사본을 또 열면(또는 `open -n`) `kingcheck` 이 둘 뜬다.
// 둘은 저장 세션을 시작할 때 한 번만 읽어서, 한쪽에서 로그인해도 다른 쪽은 그대로다. 둘 다 로그인돼 있으면 같은 갱신 토큰을
// 번갈아 돌리고, 전역 단축키 하나에 근무가 두 번 토글되고, 한 계정이 두 프로세스로 1:1 대결에 들어갈 수 있다.
//
//  · 판정(`SingleInstanceGuard.decide`)은 순수 함수다. 남을 자격 순서: **설치된 자리 > 읽기 전용·임시 자리**(DMG · App Translocation —
//    업데이트 실행기와 같은 규칙 `UpdateRunner.isReadOnlyLocation`), 그다음 **먼저 뜬 쪽**, 같으면 **pid 가 작은 쪽**. 실행 시각을
//    모르는 프로세스가 하나라도 있으면 pid 로만 줄 세운다. 양쪽이 같은 목록으로 같은 규칙을 쓰니 동시에 떠도 정확히 하나가 남는다.
//  · 결정은 **델리게이트가 만들어지는 순간**이다(`SingleInstanceState.live()` — 물러남 판정과 같은 때). 메뉴바 아이콘이 첫 렌더부터
//    이 값을 읽는다. 아이콘은 **양보·교체를 기다리는 동안에만** 빠지고, 남기로 정해지면 들어간다 — 아이콘 없이 도는 프로세스를
//    남기지 않는다(판정문 A).
//  · 양보(`.deferTo`): 먼저 뜬 쪽에 "팝오버를 열어 달라" 분산 알림을 보내고(`deliverImmediately: true` — 메뉴바 앱은 늘 비활성이라
//    없으면 보류된다) 그 프로세스가 끝나는지 잠깐 본다. 끝나면(마침 종료 중이었다) 내가 남는다(판정문 B — 0개가 되지 않게). 살아 있으면
//    나는 아무것도 하지 않고 끝난다.
//  · 교체(`.replace`): 읽기 전용 자리의 사본에 종료를 요청하고 기다린 뒤 내가 남는다. 거절하면 양보로 떨어진다(판정문 C).
//    DMG 안 사본이 남으면 업데이트가 막히고 디스크 이미지를 꺼낼 수 없고 재부팅하면 사라진다.
//  · 예외: 개발자 탈출구(`check.allowMultipleInstances` — 로컬 빌드도 번들 ID 가 `kingcheck` 이다), 테스트 프로세스, 앱스토어 판
//    물러남의 자기 재실행(`--check-retire-app-store-edition` — 옛 인스턴스가 곧 끝난다).
//
// ★ 앱스토어 판에서는 컴파일되지 않는다(물러남과 같은 울타리 — 그 판의 바이너리는 바꾸지 않는다).
#if !CHECK_MAS

/// 하나만 실행 판정(순수 함수). 프로세스 목록 · 알림 · 종료는 여기서 건드리지 않는다(호출자가 사실을 넘긴다).
enum SingleInstanceGuard {
    /// 같은 번들 ID 로 도는 프로세스 하나.
    struct Instance: Equatable, Sendable {
        var pid: pid_t
        /// LaunchServices 가 아는 실행 시각. LaunchServices 밖에서 띄우면 nil 일 수 있다 — 그러면 pid 로 줄 세운다.
        var launchDate: Date?
        /// 번들 자리(심링크를 걷은 곳 — `/Volumes/Macintosh HD/…` 는 `/…` 로 읽힌다).
        var bundlePath: String
        var isTerminated: Bool
    }

    enum Decision: Equatable, Sendable {
        /// 혼자다(또는 예외) — 평소대로 시작한다.
        case proceed
        /// 먼저 남을 자격이 있는 프로세스가 있다 — 그쪽 팝오버를 열고 나는 끝난다.
        case deferTo(pid_t)
        /// 읽기 전용·임시 자리의 사본이 떠 있고 나는 설치된 자리다 — 그쪽을 끝내고 내가 남는다.
        case replace(pid_t)
    }

    /// 개발자 탈출구 — 참이면 판정하지 않는다(UI 없음 · `defaults write kingcheck check.allowMultipleInstances -bool true`).
    static let allowMultipleKey = "check.allowMultipleInstances"
    /// 나중에 뜬 사본이 남는 쪽에 "팝오버를 열어 달라"고 보내는 분산 알림. 대상은 `object`(pid 문자열)로 고른다.
    static let presentRequestNotification = Notification.Name("kingcheck.singleInstance.presentPopover")
    /// 양보하며 기다리는 시간. 남는 쪽이 마침 종료 중이면(근무 마무리 상한 3초) 그 사이에 끝난다 — 여유 2초.
    static let deferralWaitSeconds: Double = 5
    /// 교체하며 기다리는 시간. 읽기 전용 자리 사본이 근무 중이면 평소 종료처럼 마무리한다(상한 3초).
    static let replaceWaitSeconds: Double = 6
    /// 살아 있는지 다시 보는 간격.
    static let pollSeconds: Double = 0.1
    /// 기다린 상대가 사라질 때마다 목록을 다시 본다(셋 이상 떠 있을 때). 이 횟수를 넘기면 남는다 — 0개보다 2개가 낫다.
    static let maxRounds = 3

    static let logger = Logger(subsystem: "kingcheck", category: "singleInstance")

    /// 분산 알림의 `object` — 대상 pid 를 문자열로(분산 알림의 object 는 문자열이어야 한다).
    static func notificationObject(for pid: pid_t) -> String { String(pid) }

    /// 읽기 전용·임시 자리인가 — 업데이트 실행기(`isRunningFromReadOnlyLocation`)와 **같은 규칙**이다. 갈리면 "업데이트는 막는
    /// 자리인데 남기는 쪽으로 고른다" 같은 모순이 난다.
    static func isTemporaryLocation(_ bundlePath: String) -> Bool {
        UpdateRunner.isReadOnlyLocation(bundlePath)
    }

    /// 판정. `others` 에 나 자신이 섞여 있어도 된다(실행 중 앱 목록에는 내가 들어 있다 — pid 로 거른다).
    static func decide(
        me: Instance,
        others: [Instance],
        arguments: [String],
        allowsMultiple: Bool,
        isRunningTests: Bool
    ) -> Decision {
        // 테스트 프로세스는 판정하지 않는다 — 스위트가 스스로 끝나면 안 된다.
        if allowsMultiple || isRunningTests { return .proceed }
        // 앱스토어 판 물러남의 자기 재실행(`createsNewApplicationInstance`) — 옛 인스턴스가 곧 끝난다.
        if arguments.contains(AppStoreEditionRetirement.appStoreEditionArgument) { return .proceed }
        let live = others.filter { !$0.isTerminated && $0.pid != me.pid }
        guard !live.isEmpty else { return .proceed }
        let everyone = [me] + live
        let byPIDOnly = everyone.contains { $0.launchDate == nil }
        let ordered = everyone.sorted { precedes($0, $1, byPIDOnly: byPIDOnly) }
        guard let winner = ordered.first, winner.pid == me.pid else {
            return .deferTo(ordered[0].pid)
        }
        // 내가 남을 자격이 가장 앞이다. 읽기 전용 자리 사본이 떠 있으면 그쪽을 끝낸다(가장 앞선 것부터 — 나머지는 다음 회차).
        if let temporary = ordered.first(where: { $0.pid != me.pid && isTemporaryLocation($0.bundlePath) }) {
            return .replace(temporary.pid)
        }
        return .proceed
    }

    /// `a` 가 `b` 보다 남을 자격이 앞서는가 — 설치된 자리 > 임시 자리, 그다음 먼저 뜬 쪽, 같으면 pid 가 작은 쪽.
    static func precedes(_ a: Instance, _ b: Instance, byPIDOnly: Bool) -> Bool {
        let aTemporary = isTemporaryLocation(a.bundlePath)
        let bTemporary = isTemporaryLocation(b.bundlePath)
        if aTemporary != bTemporary { return !aTemporary }
        if !byPIDOnly, let aDate = a.launchDate, let bDate = b.launchDate, aDate != bDate { return aDate < bDate }
        return a.pid < b.pid
    }

    // MARK: 실제 실행의 사실

    /// 나와 같은 번들 ID 로 도는 프로세스들.
    struct Snapshot: Equatable, Sendable {
        var me: Instance
        var others: [Instance]
    }

    /// 지금 이 프로세스와 같은 번들 ID 의 프로세스들(LaunchServices). 번들 ID 가 없으면(`swift run` 같은 개발 실행) 다른 것을
    /// 보지 않는다 — 설치된 앱에 양보해 스스로 꺼지면 안 된다.
    @MainActor
    static func liveSnapshot() -> Snapshot {
        let current = NSRunningApplication.current
        let me = Instance(
            pid: current.processIdentifier,
            launchDate: current.launchDate,
            bundlePath: resolvedPath(Bundle.main.bundleURL),
            isTerminated: false
        )
        guard let identifier = Bundle.main.bundleIdentifier else { return Snapshot(me: me, others: []) }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).map { app in
            Instance(
                pid: app.processIdentifier,
                launchDate: app.launchDate,
                bundlePath: app.bundleURL.map(resolvedPath) ?? "",
                isTerminated: app.isTerminated
            )
        }
        return Snapshot(me: me, others: others)
    }

    static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    /// 실제 실행의 판정 — 탈출구 키 · 테스트 프로세스면 프로세스 목록을 **묻지도 않는다**.
    @MainActor
    static func currentDecision(
        arguments: [String],
        defaults: UserDefaults,
        isRunningTests: Bool,
        snapshot: @MainActor () -> Snapshot
    ) -> Decision {
        let allowsMultiple = defaults.bool(forKey: allowMultipleKey)
        guard !allowsMultiple, !isRunningTests else { return .proceed }
        let facts = snapshot()
        return decide(me: facts.me, others: facts.others, arguments: arguments, allowsMultiple: allowsMultiple,
                      isRunningTests: isRunningTests)
    }
}

// MARK: - 부수 효과(주입 가능)

/// 판정을 실행에 옮기는 문들. 실제로는 `.live(...)`(분산 알림 · `NSRunningApplication`)이고 테스트는 가짜를 넣는다.
struct SingleInstanceEffects {
    /// 그 프로세스에 "팝오버를 열어 달라"고 알린다.
    var requestPresent: @MainActor (pid_t) -> Void
    /// 그 프로세스에 종료를 요청한다(평소 종료 — 근무 중이면 그쪽이 마무리한다).
    var requestQuit: @MainActor (pid_t) -> Void
    /// 그 프로세스가 아직 살아 있는가.
    var isRunning: @MainActor (pid_t) -> Bool
    /// 기다린 상대가 사라진 뒤 목록을 다시 본 판정.
    var redecide: @MainActor () -> SingleInstanceGuard.Decision
    /// 기다리기(테스트가 실제로 자지 않게).
    var sleep: @Sendable (Double) async -> Void

    @MainActor
    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> SingleInstanceEffects {
        SingleInstanceEffects(
            requestPresent: { pid in
                // 이 실행은 막 떠서 앞에 있다. macOS 14 의 협조적 활성화에서는 앞의 앱이 넘겨주지 않으면 남는 쪽의 `activate()` 가
                // 먹지 않는다 — 그러면 팝오버는 떠도 한글이 자모로 박힌다(`WindowTopAnchor.activateForKeyboardInput` 주석).
                if let target = NSRunningApplication(processIdentifier: pid) { NSApp.yieldActivation(to: target) }
                DistributedNotificationCenter.default().postNotificationName(
                    SingleInstanceGuard.presentRequestNotification,
                    object: SingleInstanceGuard.notificationObject(for: pid),
                    userInfo: nil,
                    deliverImmediately: true
                )
            },
            requestQuit: { pid in
                _ = NSRunningApplication(processIdentifier: pid)?.terminate()
            },
            isRunning: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
                return !app.isTerminated
            },
            redecide: {
                SingleInstanceGuard.currentDecision(
                    arguments: arguments,
                    defaults: defaults,
                    isRunningTests: CheckPanelVisibility.isRunningTests,
                    snapshot: SingleInstanceGuard.liveSnapshot
                )
            },
            sleep: { seconds in try? await Task.sleep(for: .seconds(seconds)) }
        )
    }
}

// MARK: - 이 실행의 상태 (관찰 가능 — 메뉴바 아이콘이 읽는다)

/// 이 실행이 남는가. **델리게이트가 만들어지는 순간** 첫 판정을 한다 — `CheckApp.body` 가 첫 렌더부터 `menuBarInserted` 를
/// 읽어야 해서 `applicationDidFinishLaunching` 까지 기다릴 수 없다. 기다리는 동안(`.pending`)만 아이콘이 빠지고, 남기로 정해지면
/// (`.proceeding`) 들어간다. 양보로 끝나면(`.yielding`) 그대로 종료한다.
@Observable
@MainActor
final class SingleInstanceState {
    enum Phase: Equatable {
        case pending(SingleInstanceGuard.Decision)
        case proceeding
        case yielding
    }

    /// 델리게이트가 만들어질 때의 판정.
    let launchDecision: SingleInstanceGuard.Decision
    private(set) var phase: Phase
    /// 종료가 시작됐다 — 다른 사본의 "팝오버를 열어 달라"에 더는 답하지 않는다(판정문 B).
    private(set) var isTerminating = false

    init(launchDecision: SingleInstanceGuard.Decision) {
        self.launchDecision = launchDecision
        self.phase = launchDecision == .proceed ? .proceeding : .pending(launchDecision)
    }

    /// 실제 실행의 판정(실행 인자 · 표준 UserDefaults · 테스트 프로세스 여부 · LaunchServices). 테스트는 `snapshot` 에 가짜를 넣어
    /// **이 함수를 그대로** 부른다.
    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        isRunningTests: Bool = CheckPanelVisibility.isRunningTests,
        snapshot: @MainActor () -> SingleInstanceGuard.Snapshot = SingleInstanceGuard.liveSnapshot
    ) -> SingleInstanceState {
        let decision = SingleInstanceGuard.currentDecision(
            arguments: arguments, defaults: defaults, isRunningTests: isRunningTests, snapshot: snapshot
        )
        if decision != .proceed {
            SingleInstanceGuard.logger.notice("같은 앱이 이미 떠 있다 — 판정: \(String(describing: decision), privacy: .public)")
        }
        return SingleInstanceState(launchDecision: decision)
    }

    /// 아직 판정을 실행에 옮기지 않았다(양보·교체를 기다린다). 시작 처리는 이 동안 아무 배선도 하지 않는다.
    var isPending: Bool {
        if case .pending = phase { return true }
        return false
    }

    /// 남기로 정해졌다(혼자이거나 예외).
    var hasProceeded: Bool { phase == .proceeding }

    /// 메뉴바 아이콘을 넣는가 — 남기로 정해졌을 때만. 기다리는 동안은 빠지고, 남으면 들어간다.
    var menuBarInserted: Bool { hasProceeded }

    /// 종료 요청을 곧바로 받아들이는가 — 남지 않은 실행은 세션을 살린 적이 없어 마무리할 것이 없다. 여기서 평소 종료(퇴근 동기화)를
    /// 타면 남는 쪽이 하고 있는 근무를 이 실행이 닫는다.
    var terminatesImmediately: Bool { !hasProceeded }

    /// 다른 사본의 "팝오버를 열어 달라"·다시 열기에 답하는가.
    var isServing: Bool { hasProceeded && !isTerminating }

    /// 종료가 시작됐다(`applicationShouldTerminate`).
    func beginTerminating() {
        isTerminating = true
    }

    /// 판정을 실행에 옮긴다. 참이면 남는다(시작 처리를 이어 간다), 거짓이면 양보했다(호출자가 끝낸다).
    func resolve(effects: SingleInstanceEffects) async -> Bool {
        var decision = launchDecision
        for round in 0..<SingleInstanceGuard.maxRounds {
            if round > 0 { decision = effects.redecide() }
            switch decision {
            case .proceed:
                phase = .proceeding
                return true
            case .replace(let pid):
                phase = .pending(decision)
                effects.requestQuit(pid)
                if await waitUntilGone(pid, seconds: SingleInstanceGuard.replaceWaitSeconds, effects: effects) { continue }
                // 끝내기를 거절했다 — 양보로 떨어진다(판정문 C). 둘이 남는 것보다 먼저 뜬 쪽을 남기는 게 낫다.
                SingleInstanceGuard.logger.notice("읽기 전용 자리의 사본이 끝나지 않는다 — 양보한다")
                if await deferral(to: pid, effects: effects) { continue }
                phase = .yielding
                return false
            case .deferTo(let pid):
                phase = .pending(decision)
                if await deferral(to: pid, effects: effects) { continue }
                phase = .yielding
                return false
            }
        }
        // 기다린 상대가 매번 사라졌다 — 남는다(0개가 되는 것보다 2개가 낫다).
        phase = .proceeding
        return true
    }

    /// 그쪽 팝오버를 열어 달라고 알리고, 그 프로세스가 끝나는지 본다. 끝났으면 참(다시 판정한다).
    private func deferral(to pid: pid_t, effects: SingleInstanceEffects) async -> Bool {
        effects.requestPresent(pid)
        return await waitUntilGone(pid, seconds: SingleInstanceGuard.deferralWaitSeconds, effects: effects)
    }

    private func waitUntilGone(_ pid: pid_t, seconds: Double, effects: SingleInstanceEffects) async -> Bool {
        let steps = Int((seconds / SingleInstanceGuard.pollSeconds).rounded(.up))
        for _ in 0..<steps {
            if !effects.isRunning(pid) { return true }
            await effects.sleep(SingleInstanceGuard.pollSeconds)
        }
        return !effects.isRunning(pid)
    }
}

#endif
