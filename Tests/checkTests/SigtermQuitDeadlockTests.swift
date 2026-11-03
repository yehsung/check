import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 근무 중 SIGTERM → '퇴근 정리 후 종료'의 교착(2026-11-03 실측 — 대표 맥 설치본 0.3.73).
//
// 사실: SIGTERM 처리기(`GracefulTerminationSignal`)는 메인 큐의 디스패치 소스다. 그 블록 안에서 `NSApp.terminate` 를 곧바로 부르면,
// 근무 중일 때 `applicationShouldTerminate` 가 `.terminateLater` 를 돌려주고 AppKit 은 응답이 올 때까지 **그 블록 안에서** 메인 런루프를
// 중첩해 돈다. 퇴근 정리는 `Task { @MainActor in finishWorkBeforeQuit(); NSApp.reply(...) }` — 메인 큐의 다음 차례를 기다리는데,
// 메인 큐는 지금 블록이 끝나야 다음 것을 꺼낸다. 그래서 정리도 응답도 영영 안 온다(실측: 메인 스레드 `GracefulTerminationSignal → terminate:
// → _shouldTerminate → mach_msg` 에서 멈춤 · 30초 근무 신호 끊김 · 서버 요청 0건).
//
// 이 파일은 그 구조를 테스트 프로세스에서 그대로 만든다: 진짜 SIGTERM 을 보내고, 처리기가 부르는 종료 문 안에서 AppKit 대역
// (`spinLikeTerminateLater` — 응답이 올 때까지 메인 런루프를 중첩해 돈다)이 퇴근 정리 Task 를 기다린다.

/// 처리기가 끝났는지 · 그 안에서 정리가 끝났는지(다른 실행 맥락에서 읽으므로 잠금).
private final class SQBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _done = false
    private var _replied = false
    private var _waited: TimeInterval = 0
    func finish(replied: Bool, waited: TimeInterval) {
        lock.lock(); _done = true; _replied = replied; _waited = waited; lock.unlock()
    }
    var done: Bool { lock.lock(); defer { lock.unlock() }; return _done }
    var replied: Bool { lock.lock(); defer { lock.unlock() }; return _replied }
    var waited: TimeInterval { lock.lock(); defer { lock.unlock() }; return _waited }
}

/// 메인 액터에서 세우고 읽는 깃발.
@MainActor
private final class SQFlag { var value = false }

/// AppKit `-[NSApplication terminate:]` 가 `.terminateLater` 를 받았을 때 하는 일의 대역 — 응답(깃발)이 올 때까지 **지금 자리에서**
/// 메인 런루프를 중첩해 돈다. 상한을 넘기면 포기하고 false.
@MainActor
private func spinLikeTerminateLater(until flag: SQFlag, limit: TimeInterval) -> (replied: Bool, waited: TimeInterval) {
    let start = Date()
    while !flag.value, Date().timeIntervalSince(start) < limit {
        _ = CFRunLoopRunInMode(.defaultMode, 0.02, true)
    }
    return (flag.value, Date().timeIntervalSince(start))
}

private func sqIsolatedDefaults() -> UserDefaults {
    let suiteName = CheckTestScratch.uniqueSuitePath()
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 스텁 네트워크에 물린, 로그인해 **근무 중인** 스토어(내가 연 세션).
@MainActor
private func sqWorkingStore(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: URLSession(configuration: .stubbed))
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: sqIsolatedDefaults())
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil,
                                    userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.startedAt = Date().addingTimeInterval(-3_600)
    store.currentSessionID = "own-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    return store
}

private func sqStopPatches(_ host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
    }.count
}

@Suite("근무 중 SIGTERM — 종료 대기에서 퇴근 정리가 돈다(교착 없음)", .serialized)
@MainActor
struct SigtermQuitDeadlockTests {

    @Test("① 재현: SIGTERM → 종료 대기(메인 런루프 중첩) 안에서 퇴근 정리가 끝나고 서버에 근무 종료가 남는다")
    func sigtermWhileWorkingFinishesTheWorkThenReplies() async {
        // 없으면(0.3.49~0.3.73): 처리기가 메인 큐 블록 안에서 종료를 불러, 정리 Task 가 한 번도 못 돌고 앱이 멈춘다.
        let host = "sigterm-finish-\(UUID().uuidString.prefix(6))".lowercased()
        let store = sqWorkingStore(host: host)
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel() }
        let box = SQBox()
        GracefulTerminationSignal.install {
            MainActor.assumeIsolated {
                // applicationShouldTerminate 의 근무 중 갈래와 같은 모양: 정리 Task 를 띄우고 .terminateLater → AppKit 이 기다린다.
                let replied = SQFlag()
                Task { @MainActor in
                    await store.finishWorkBeforeQuit(timeout: 3)
                    replied.value = true            // NSApp.reply(toApplicationShouldTerminate: true) 의 대역
                }
                let outcome = spinLikeTerminateLater(until: replied, limit: 4)
                box.finish(replied: outcome.replied, waited: outcome.waited)
            }
        }
        defer { GracefulTerminationSignal.uninstallForTesting() }

        kill(getpid(), SIGTERM)
        for _ in 0..<400 where !box.done { try? await Task.sleep(for: .milliseconds(20)) }

        #expect(box.done, "SIGTERM 이 종료 문으로 이어지지 않았다")
        #expect(box.replied, "교착 — 종료 대기 \(String(format: "%.2f", box.waited))초 동안 퇴근 정리가 한 번도 못 돌았다")
        #expect(sqStopPatches(host) == 1, "서버에 근무 종료(PATCH work_sessions)가 \(sqStopPatches(host))건 — 1건이어야 한다")
        #expect(store.startedAt == nil, "근무가 안 끝났다")
    }

    @Test("② 상한: 서버가 늦으면 상한 시간 뒤에 응답한다(근무 종료 요청은 이미 나갔다) — 종료가 서버를 기다리며 멈추지 않는다")
    func sigtermWhileWorkingRepliesAfterTheCapWhenTheServerIsSlow() async {
        // `delayed-` 호스트는 응답을 0.15초 늦게 준다. 상한 0.05초면 응답보다 먼저 끝나야 한다(앱의 상한은 3초 — finishWorkBeforeQuit 기본값).
        let host = "\(URLProtocolStub.alwaysDelayedHostPrefix)sigterm-cap-\(UUID().uuidString.prefix(6))".lowercased()
        let store = sqWorkingStore(host: host)
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel() }
        let box = SQBox()
        GracefulTerminationSignal.install {
            MainActor.assumeIsolated {
                let replied = SQFlag()
                Task { @MainActor in
                    await store.finishWorkBeforeQuit(timeout: 0.05)
                    replied.value = true
                }
                let outcome = spinLikeTerminateLater(until: replied, limit: 4)
                box.finish(replied: outcome.replied, waited: outcome.waited)
            }
        }
        defer { GracefulTerminationSignal.uninstallForTesting() }

        kill(getpid(), SIGTERM)
        for _ in 0..<400 where !box.done { try? await Task.sleep(for: .milliseconds(20)) }

        #expect(box.done && box.replied, "상한이 지나도 응답이 없다(\(String(format: "%.2f", box.waited))초)")
        #expect(box.waited < 1.0, "상한 0.05초인데 \(String(format: "%.2f", box.waited))초를 기다렸다")
        #expect(sqStopPatches(host) == 1, "근무 종료 요청이 안 나갔다 — 상한은 '기다림'을 자르는 것이지 요청을 거르는 것이 아니다")
    }

    @Test("③ 처리기 · 메뉴바 빼기 · 옮기기 종료가 쓰는 문: 메인 큐 블록 안에서 불러도 종료 대기 중 정리가 돈다 — 문 없이 같은 자리에서 부르면 교착(기준선)")
    func terminationRequestEscapesTheQueueBlock() async {
        // 메뉴바 아이콘 빼기(`DispatchQueue.main.async`) · 옮기기 뒤 종료(Task) 는 신호가 아니어도 같은 교착 모양이었다.
        @MainActor func run(viaRequest: Bool) async -> SQBox {
            let box = SQBox()
            DispatchQueue.main.async {
                let body: @MainActor @Sendable () -> Void = {
                    let replied = SQFlag()
                    Task { @MainActor in replied.value = true }     // 퇴근 정리 Task 대역
                    let outcome = spinLikeTerminateLater(until: replied, limit: viaRequest ? 4 : 0.6)
                    box.finish(replied: outcome.replied, waited: outcome.waited)
                }
                if viaRequest {
                    AppTerminationRequest.performOutsideQueueBlock(body)
                } else {
                    MainActor.assumeIsolated { body() }
                }
            }
            for _ in 0..<400 where !box.done { try? await Task.sleep(for: .milliseconds(20)) }
            return box
        }
        let fixed = await run(viaRequest: true)
        #expect(fixed.done && fixed.replied, "문을 지나도 종료 대기 중 정리가 못 돌았다")
        // ★ 기준선: 문 없이 큐 블록 안에서 곧바로 — 0.6초 동안 정리가 한 번도 못 돈다(위 초록이 문 덕인지 가린다).
        let bare = await run(viaRequest: false)
        #expect(bare.done && !bare.replied, "기준선이 안 갈린다 — 큐 블록 안에서도 정리가 돌았다면 위 시험은 아무것도 안 잰다")
    }

    @Test("④ 실제 신호가 처리기로 온다 — 기본 처분(즉사) 대신 종료 문이 불린다(옛 CheckUpdateCheckTests 의 시험을 옮겼다)")
    func sigtermRunsTheGracefulTerminationPathInsteadOfKillingUsOutright() async {
        let box = SQBox()
        GracefulTerminationSignal.install { box.finish(replied: true, waited: 0) }
        defer { GracefulTerminationSignal.uninstallForTesting() }
        kill(getpid(), SIGTERM)
        for _ in 0..<100 where !box.done { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(box.done, "SIGTERM 이 평소 종료 절차로 이어지지 않았다")
    }

    @Test("⑤ 소스 계약: 같은 신호를 쓰는 업데이트 · 하나만 실행 교체가 SIGTERM 을 보내고, 앱이 그 처리기를 달며, 큐 블록·Task 안의 종료는 문을 지난다")
    func signalSendersAndQueueTerminationsUseTheFixedPath() throws {
        func source(_ name: String) throws -> String {
            let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Sources/check", isDirectory: true)
            let text = try String(contentsOf: dir.appendingCheckSourcePath(name), encoding: .utf8)
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        let update = try source("CheckUpdateCheck.swift")
        #expect(update.contains("kill -TERM \"$APP_PID\""), "DMG 업데이트 스크립트가 SIGTERM 으로 끝내지 않는다 — 받는 쪽 시험(①②)이 그 길을 못 잰다")
        #expect(update.contains("AppTerminationRequest.performOutsideQueueBlock { onTerminate() }"),
                "SIGTERM 처리기가 종료 문을 큐 블록 안에서 곧바로 부른다 — 근무 중 교착")
        let single = try source("SingleInstanceGuard.swift")
        #expect(single.contains("_ = kill(pid, SIGTERM)"), "하나만 실행 교체가 SIGTERM 을 안 보낸다")
        let app = try source("CheckApp.swift")
        #expect(app.contains("GracefulTerminationSignal.install()"), "앱이 SIGTERM 처리기를 달지 않는다")
        #expect(app.contains("AppTerminationRequest.terminate()"), "메뉴바 아이콘 빼기 종료가 문을 안 지난다")
        let move = try source("MoveToApplications.swift")
        #expect(move.contains("terminate: { AppTerminationRequest.terminate() }"), "옮기기 뒤 종료가 문을 안 지난다")
        // 큐 블록 안에서 곧바로 끝내는 옛 모양이 Sources/check 어디에도 다시 생기지 않게.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/check", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        for file in files {
            let text = try source(file).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            #expect(!text.contains("DispatchQueue.main.async { NSApp.terminate(nil) }"), "\(file) 가 큐 블록 안에서 곧바로 끝낸다")
        }
    }
}
