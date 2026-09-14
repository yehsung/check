import Foundation
import Testing
@testable import check

// MARK: - v0.3.22 설정의 '자동 근무 시작' 스위치
//
// 사장님 결정(2026-09-15): 자동 시작만 사용자가 끌 수 있다. 자동 **종료**는 공정성 장치라 스위치를 두지 않는다 —
// 끄면 켜 둔 채 퇴근한 맥이 근무·순위·보상을 부풀리고, 끈 사람만 이득이라 결국 모두가 끄게 된다.
//
// 이 파일이 지키는 것(전부 초록인 채로 틀릴 수 있는 자리다):
//  ① 기본은 켜짐이고, 끈 값은 다음 실행에도 남는다. 안 남으면 brew 업데이트 한 번에 설정이 조용히 풀린다.
//  ② 끄면 실제 사용 5분이 몇 번을 차도 근무가 저절로 시작되지 않는다 — 켜면 같은 입력으로 시작된다(대조군).
//  ③ 30분 자동 재개도 같은 관문 뒤에 있다. 재개 호출자가 넛지 발동 밖으로 새면 끈 사람의 옛 세션이 되살아난다.
//  ④ 설정 창에 스위치가 있고 스토어 세터로 이어진다. 자동 종료 스위치는 없다.

/// 테스트별 고정 이름의 격리 defaults(V0236Scratch 와 같은 규약 — UUID 스위트는 실행마다 빈 plist 를 쌓는다).
private final class V0322Scratch {
    let suiteName: String
    let defaults: UserDefaults

    init(_ test: String) {
        suiteName = "check-v0322-autostart.\(test.replacingOccurrences(of: "()", with: ""))"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}

/// 네트워크를 전부 URLProtocolStub 으로 막은 스토어. 프로덕션 호출 없음.
@MainActor
private func v0322Store(defaults: UserDefaults) -> WorkTimerStore {
    WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://v0322-autostart-tests")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

/// 실제 스토어 + 실제 컨트롤러를 관통하는 하네스(V0236ControllerHarness 와 같은 모양). 넛지의 시간·입력·세션 판정만
/// 주입해 발화 → 자동 시작을 결정적으로 돌린다.
@MainActor
private final class V0322ControllerHarness {
    var now = Date()
    var idle: TimeInterval = 10
    let scratch: V0322Scratch
    let store: WorkTimerStore

    lazy var controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        defaults: scratch.defaults,
        workspaceNotifications: nil,
        nudgeIdleSeconds: { [weak self] in self?.idle ?? 999 },
        nudgeClock: { [weak self] in self?.now ?? .distantPast },
        nudgeSessionUsable: { true } // 실제 잠금 판정 금지(잠긴 원격 맥에서 전 tick 무적립).
    )

    init(_ test: String = #function) {
        scratch = V0322Scratch(test)
        store = v0322Store(defaults: scratch.defaults)
        // 넛지 자격의 나머지(로그인 + 팀 + 비근무)는 전부 채운다 — 판정을 가르는 것이 스위치 하나뿐이어야 한다.
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "10000000-0000-0000-0000-000000003220"
        store.clock = { [weak self] in self?.now ?? Date() }
        store.inputSessionUsable = { true }
        store.meaningfulIdleSeconds = { 0 }
    }

    /// n 회 tick 하며 매 tick 전에 주입 클록을 60초 진행시킨다(실사용 60초 주기 모사).
    func run(_ count: Int) {
        for _ in 0..<count {
            now = now.addingTimeInterval(NudgeScheduler.checkInterval)
            controller.nudgeScheduler.tick()
        }
    }

    /// 루프를 끄고 스토어가 띄운 태스크를 회수한다(잔여 태스크 금지).
    func cleanup() {
        store.session = nil
        controller.updateWorking(false)
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
        store.drainInFlight?.cancel()
    }
}

@MainActor
struct V0322AutoWorkStartToggleTests {
    // MARK: ① 기본 켜짐 · 재실행 생존

    @Test("자동 근무 시작은 기본으로 켜져 있고, 끈 값은 다음 실행에도 남는다")
    func autoWorkStartDefaultsOnAndSurvivesRelaunch() {
        let scratch = V0322Scratch(#function)

        let first = v0322Store(defaults: scratch.defaults)
        #expect(first.autoWorkStartEnabled, "기본값이 꺼짐이다 — 업데이트하는 순간 모든 사람의 자동 시작이 멈춘다")

        first.setAutoWorkStartEnabled(false)
        #expect(!first.autoWorkStartEnabled)

        let relaunched = v0322Store(defaults: scratch.defaults)
        #expect(!relaunched.autoWorkStartEnabled, "끈 값이 재실행에 되살아났다 — brew 업데이트 한 번이면 설정이 풀린다")

        relaunched.setAutoWorkStartEnabled(true)
        let again = v0322Store(defaults: scratch.defaults)
        #expect(again.autoWorkStartEnabled)

        // 키 이름을 못 박는다. 바꾸면 이미 끈 사람의 설정이 아무 말 없이 켜짐으로 돌아간다.
        #expect(WorkTimerStore.autoWorkStartEnabledKey == "check.work.autoStartEnabled")
    }

    // MARK: ② 끄면 실제 사용으로 시작되지 않는다 (켜면 같은 입력으로 시작 — 대조군)

    @Test("자동 근무 시작을 끄면 30분을 써도 근무가 시작되지 않고, 켜면 5분 만에 시작된다")
    func switchingOffKeepsRealUseFromStartingWork() {
        let h = V0322ControllerHarness()
        defer { h.cleanup() }

        h.store.setAutoWorkStartEnabled(false)
        h.run(30)
        #expect(h.store.startedAt == nil, "끈 사람의 근무가 저절로 시작됐다")
        #expect(!h.store.snapshot.isWorking)
        // 자격이 없는 동안에는 적립도 하지 않는다 — 적립이 남아 있으면 켜는 순간 곧바로 발동한다.
        #expect(h.controller.nudgeScheduler.activeMinutes == 0)

        // 대조군: 같은 하네스·같은 입력에서 켜면 5분 만에 시작된다. 이 단언이 없으면 위 단언은
        // 하네스가 애초에 발화를 못 하는 세계에서도 초록이다(비교 기준선이 달라야 한다).
        h.store.setAutoWorkStartEnabled(true)
        h.run(4)
        #expect(h.store.startedAt == nil, "켠 직후 5분을 채우기 전에 시작됐다 — 꺼져 있던 동안 적립한 것이다")
        h.run(1)
        #expect(h.store.startedAt != nil)
        #expect(h.store.snapshot.isWorking)
    }

    // MARK: ③ 30분 자동 재개도 같은 관문 뒤에 있다

    @Test("30분 자동 재개는 넛지 발동 한 곳에서, 자격 가드 뒤에서만 불린다")
    func thirtyMinuteResumeSitsBehindTheSameGate() throws {
        // 재개는 비동기 왕복이라 "끄면 재개가 안 일어난다"를 동기 단언으로 가를 수 없다. 대신 구조를 못 박는다:
        // 재개 호출자가 nudgeAutoStart 하나뿐이고 그 안에서 자격 가드 뒤에 있으면, ②가 증명한 스위치가 재개도 막는다.
        let overlay = v0322StrippingComments(try String(contentsOf: v0322SourceURL("CheckOverlayWindow.swift"), encoding: .utf8))
        let function = try #require(overlay.range(of: "func nudgeAutoStart()"), "넛지 발동 함수가 사라졌다")
        let body = overlay[function.upperBound...]
        let guardLine = try #require(body.range(of: "guard isNudgeEligible else { return }"), "넛지 발동이 자격을 다시 보지 않는다")
        let resume = try #require(body.range(of: "store.resumeRecentlyClosedSession()"), "넛지 발동이 재개를 부르지 않는다")
        #expect(guardLine.lowerBound < resume.lowerBound, "재개가 자격 가드보다 먼저 불린다 — 끈 사람의 옛 세션이 되살아난다")

        let eligibility = try #require(overlay.range(of: "private var isNudgeEligible: Bool {"))
        let eligibilityBody = overlay[eligibility.upperBound...].prefix(600)
        #expect(eligibilityBody.contains("store.autoWorkStartEnabled"), "넛지 자격에 스위치가 없다")

        let calls = try v0322CountInSources("resumeRecentlyClosedSession()")
            - (try v0322CountInSources("func resumeRecentlyClosedSession()"))
        #expect(calls == 1, "재개를 부르는 곳이 \(calls)군데다 — 넛지 발동 밖의 호출은 자동 시작 스위치를 우회한다")
    }

    // MARK: ④ 설정 창 배선 · 자동 종료 스위치는 없다

    @Test("설정 창에 자동 근무 시작 스위치가 있고, 자동 근무 종료 스위치는 없다")
    func settingsWindowOffersOnlyTheAutoStartSwitch() throws {
        let source = v0322StrippingComments(try String(contentsOf: v0322SourceURL("CheckSettingsView.swift"), encoding: .utf8))
        let title = try #require(source.range(of: "title: \"자동 근무 시작\""), "설정 창에 자동 근무 시작 스위치가 없다")
        let row = source[title.upperBound...].prefix(300)
        #expect(row.contains("isOn: autoWorkStartBinding"))
        #expect(source.contains("get: { store.autoWorkStartEnabled }"))
        #expect(source.contains("set: { store.setAutoWorkStartEnabled($0) }"))

        // 사장님 결정이다. 다시 넣으려면 이 줄보다 먼저 WorkTimerStore.autoWorkStartEnabled 주석의 근거를 뒤집어라.
        #expect(!source.contains("자동 근무 종료"), "자동 종료 스위치가 생겼다 — 순위·보상 공정성 장치를 사용자가 끌 수 있게 된다")

        // 세터를 부르는 곳은 설정 창 하나뿐이다. 두 번째 집이 생기면 두 스위치가 서로 다른 값을 그린다.
        let setters = try v0322CountInSources("setAutoWorkStartEnabled(")
            - (try v0322CountInSources("func setAutoWorkStartEnabled("))
        #expect(setters == 1, "자동 근무 시작 세터를 부르는 곳이 \(setters)군데다")
    }
}

// MARK: - 헬퍼

/// 소스 파일 URL(이 테스트 파일에서 저장소 루트로 올라간다).
private func v0322SourceURL(_ name: String) -> URL {
    v0322SourcesDirectory().appendingPathComponent(name)
}

private func v0322SourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)   // Tests/checkTests/V0322AutoWorkStartToggleTests.swift
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // (repo root)
        .appendingPathComponent("Sources/check")
}

/// Sources/check 의 모든 .swift 에서 주석을 걷어낸 뒤 needle 이 나오는 횟수.
private func v0322CountInSources(_ needle: String) throws -> Int {
    let directory = v0322SourcesDirectory()
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
    return try names.reduce(0) { total, name in
        let code = v0322StrippingComments(try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
        return total + code.components(separatedBy: needle).count - 1
    }
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드(V0320ServerReleaseTests 의 srStrippingComments 와 같은 규칙 —
/// 이 저장소의 소스 계약 도구는 파일마다 private 사본을 둔다). 걷어내지 않으면 설명문의 낱말이 단언에 걸린다.
private func v0322StrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}
