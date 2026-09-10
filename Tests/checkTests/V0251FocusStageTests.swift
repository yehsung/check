import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.2.51 집중 모드 2단 (클라이언트만 — 서버 불변)
//
// 사용자 지시(2026-09-11): 1단 = 3시간 뒤 자동 해제, 2단 = 끌 때까지 계속, 버튼 한 번 = 1단 · 두 번 = 2단.
// 같은 날 결정: 만료는 **클라가** 한다(앱이 켜져 있을 때 PATCH false). 서버는 profiles.focus_mode 불리언 그대로다.
// 그리고: 업데이트 전부터 켜 둔 사람(서버 true + 이 맥에 기록 없음)은 **2단**으로 둔다.
//
// 이 파일의 스텁은 그 서버 계약만 흉내 낸다 — PATCH 가 2xx 면 서버값이 바뀌고, GET 은 그 값을 돌려준다.

/// 이 파일 전용 스텁. 공용 URLProtocolStub 에는 profiles PATCH 를 실패시키는 손잡이가 없고, 호스트별 서버값을
/// 쥐지도 않는다(그리고 여러 스위트가 공유하는 전역이다). 그래서 상태를 여기서 따로 쥔다. 호스트는 테스트마다 다르다.
private final class FocusStageStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var serverFocus: [String: Bool] = [:]
    nonisolated(unsafe) private static var patchStatus: [String: Int] = [:]
    nonisolated(unsafe) private static var focusPatches: [String: [Bool]] = [:]

    static func setServerFocus(_ value: Bool, host: String) { lock.withLock { serverFocus[host] = value } }
    static func setPatchStatus(_ code: Int, host: String) { lock.withLock { patchStatus[host] = code } }
    /// 이 호스트로 나간 **집중 모드** PATCH 본문들(순서대로). 버전 보고(app_build) PATCH 는 세지 않는다.
    static func patches(host: String) -> [Bool] { lock.withLock { focusPatches[host] ?? [] } }
    static func serverValue(host: String) -> Bool { lock.withLock { serverFocus[host] ?? false } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let body = Self.bodyData(of: request)
        let (status, data): (Int, Data) = Self.lock.withLock {
            if path == "/rest/v1/profiles", method == "PATCH" {
                guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                      let focus = (object["focus_mode"] ?? object["focusMode"]) as? Bool
                else { return (204, Data()) }
                Self.focusPatches[host, default: []].append(focus)
                let code = Self.patchStatus[host] ?? 204
                if (200..<300).contains(code) { Self.serverFocus[host] = focus }
                return (code, Data())
            }
            if path == "/rest/v1/profiles", method == "GET" {
                let focus = Self.serverFocus[host] ?? false
                return (200, Data(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":\#(focus)}]"#.utf8))
            }
            return (200, Data("[]".utf8))
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// 주입 시계. 켤 때와 판정할 때 **같은 시계**를 쓰는 것이 계약이라, 테스트는 벽시계 없이 3시간을 건너뛴다.
private final class StageClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private let stageUserA = "00000000-0000-0000-0000-00000000000a"
private let stageUserB = "00000000-0000-0000-0000-00000000000b"
private let stageT0 = Date(timeIntervalSince1970: 1_789_000_000)
private let threeHours = WorkTimerStore.focusTimedDuration

private func freshStageDefaults() -> (UserDefaults, String) {
    let suite = "check-focus-stage-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}

@MainActor
private func makeStageStore(host: String, defaults: UserDefaults, clock: StageClock, userID: String = stageUserA) -> WorkTimerStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FocusStageStub.self]
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: configuration)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.clock = { clock.now }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    return store
}

/// 날아가는 집중 모드 PATCH 가 끝나고 조건이 설 때까지 기다린다. **시간을 재는 것이 아니라 완료를 기다린다**
/// — 단언에 벽시계가 섞이지 않는다(판정 시각은 전부 StageClock 이다).
@MainActor
private func settle(_ store: WorkTimerStore, _ condition: () -> Bool = { true }) async -> Bool {
    for _ in 0..<800 {
        if store.focusPatchInFlight == nil, condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return store.focusPatchInFlight == nil && condition()
}

/// "요청이 **안** 나갔다"를 말하기 전의 여유. 떠 있는 Task 가 있었다면 이 사이에 스텁에 닿는다.
@MainActor
private func quiesce(_ store: WorkTimerStore) async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(60))
    _ = await settle(store)
}

@MainActor
@Suite struct V0251FocusStageTests {

    // MARK: 1) 판정 표

    /// 스펙 표 그대로: off · 1단 남음 · 1단 만료 경계(정확히 until) · 2단 · 기록 없음(기존 사용자) · 서버 false 인데 기록만 남은 행.
    @Test func focusStageTableCoversEveryRow() {
        let until = stageT0.addingTimeInterval(threeHours)
        let timed = FocusStageRecord(stage: .timed, until: until)
        let always = FocusStageRecord(stage: .always, until: nil)

        #expect(FocusStagePolicy.stage(serverOn: false, record: nil, now: stageT0) == .off)
        // 서버 false 인데 기록만 남은 행 — 기록이 뭐라 하든 off(다른 맥에서 껐거나 서버가 덮었다).
        #expect(FocusStagePolicy.stage(serverOn: false, record: timed, now: stageT0) == .off)
        #expect(FocusStagePolicy.stage(serverOn: false, record: always, now: stageT0) == .off)
        // 1단 남음.
        #expect(FocusStagePolicy.stage(serverOn: true, record: timed, now: stageT0) == .timed)
        #expect(FocusStagePolicy.stage(serverOn: true, record: timed, now: until.addingTimeInterval(-1)) == .timed)
        // 만료 경계: **정확히 until 에서** 끝난다.
        #expect(FocusStagePolicy.stage(serverOn: true, record: timed, now: until) == .off)
        #expect(FocusStagePolicy.isExpired(timed, now: until))
        #expect(!FocusStagePolicy.isExpired(timed, now: until.addingTimeInterval(-1)))
        // 2단.
        #expect(FocusStagePolicy.stage(serverOn: true, record: always, now: until.addingTimeInterval(86_400)) == .always)
        // 기록 없음(업데이트 전부터 켜 둔 사람) → 2단. 2026-09-11 사용자 지시.
        #expect(FocusStagePolicy.stage(serverOn: true, record: nil, now: stageT0) == .always)
        // 깨진 1단(until 없음)은 무기한이 아니라 끝난 것으로 본다.
        #expect(FocusStagePolicy.stage(serverOn: true, record: FocusStageRecord(stage: .timed, until: nil), now: stageT0) == .off)
    }

    /// 스토어의 파생값이 같은 표를 읽는다 — 서버 미러(focusMode) + **지금 로그인한 사람의** 기록.
    @Test func storeStageDerivesFromServerMirrorAndThisUsersRecord() {
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: "focus-stage-derive", defaults: defaults, clock: clock)
        let until = stageT0.addingTimeInterval(threeHours)

        // 서버 false + 기록만 남음 → off.
        store.writeFocusStageRecord(FocusStageRecord(stage: .timed, until: until), for: stageUserA)
        #expect(store.focusMode == false)
        #expect(store.focusStage(now: stageT0) == .off)
        // 서버 true + 1단 → 남음 / 경계에서 off.
        store.focusMode = true
        #expect(store.focusStage(now: stageT0) == .timed)
        #expect(store.focusStage(now: until) == .off)
        // 서버 true + 2단.
        store.writeFocusStageRecord(FocusStageRecord(stage: .always, until: nil), for: stageUserA)
        #expect(store.focusStage(now: until) == .always)
        // 서버 true + 기록 없음 → 2단.
        store.writeFocusStageRecord(nil, for: stageUserA)
        #expect(store.focusStage(now: stageT0) == .always)
        // 로그인하지 않았으면 off — 기록은 사용자별이라 읽을 주인이 없다.
        store.session = nil
        #expect(store.focusStage(now: stageT0) == .off)
    }

    // MARK: 3) 순환

    /// 세 번 누르면 off → 1단 → 2단 → off. **1단 → 2단에서는 PATCH 가 나가지 않는다**(서버는 이미 true).
    @Test func threePressesCycleOffTimedAlwaysOffAndTheAlwaysStepSendsNoPatch() async {
        let host = "focus-stage-cycle"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)
        #expect(store.focusStage(now: clock.now) == .off)

        store.cycleFocusStage()
        #expect(store.focusStage(now: clock.now) == .timed, "낙관 반영: 서버 왕복 전에 1단이 보여야 한다")
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })
        #expect(FocusStageStub.patches(host: host) == [true])
        #expect(store.focusStageRecord(for: stageUserA) == FocusStageRecord(stage: .timed, until: stageT0.addingTimeInterval(threeHours)))

        clock.advance(5)
        store.cycleFocusStage()
        #expect(store.focusStage(now: clock.now) == .always)
        #expect(store.focusPatchInFlight == nil, "1단 → 2단에서 요청이 만들어졌다")
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host) == [true], "1단 → 2단에서 PATCH 가 나갔다 — 서버는 이미 true 다.")
        #expect(store.focusStageRecord(for: stageUserA) == FocusStageRecord(stage: .always, until: nil))

        store.cycleFocusStage()
        #expect(store.focusStage(now: clock.now) == .off)
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 2 })
        #expect(FocusStageStub.patches(host: host) == [true, false])
        #expect(store.focusStageRecord(for: stageUserA) == nil)
        #expect(FocusStageStub.serverValue(host: host) == false)
    }

    /// 1초 안에 세 번 눌러도 요청은 **한 번에 하나**이고, 서버에는 마지막 의도(off)가 남는다.
    /// 병렬로 쏘면 true 와 false 중 나중에 커밋된 쪽이 남아 화면(off)과 서버(on)가 갈릴 수 있다.
    @Test func rapidPressesSendOneRequestAtATimeAndEndOnTheLastIntent() async {
        let host = "focus-stage-rapid"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)

        store.cycleFocusStage()
        store.cycleFocusStage()
        store.cycleFocusStage()
        #expect(store.focusStage(now: clock.now) == .off)
        #expect(await settle(store) { FocusStageStub.patches(host: host).count >= 2 })
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host) == [true, false])
        #expect(FocusStageStub.serverValue(host: host) == false)
        #expect(store.focusModeServerValue == false)
        #expect(store.focusStageRecord(for: stageUserA) == nil)
    }

    // MARK: 2) 만료

    /// 시계를 3시간 넘겨 틱 → PATCH false 가 **정확히 한 번**. 틱은 1초마다 오지만 요청은 하나다.
    @Test func timedStageExpiresOnTickWithExactlyOnePatchFalse() async {
        let host = "focus-stage-expire"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)
        store.cycleFocusStage()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })
        let until = stageT0.addingTimeInterval(threeHours)

        // 1초 전: 아직 1단이다. 요청 없음.
        clock.now = until.addingTimeInterval(-1)
        store.tick()
        await quiesce(store)
        #expect(store.focusStage(now: clock.now) == .timed)
        #expect(FocusStageStub.patches(host: host) == [true])

        // 경계: 화면은 곧바로 off, 요청은 한 건.
        clock.now = until
        store.tick()
        #expect(store.focusMode == false)
        for _ in 0..<5 {
            clock.advance(1)
            store.tick()
        }
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 2 })
        for _ in 0..<3 {
            clock.advance(1)
            store.tick()
        }
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host) == [true, false], "만료 PATCH false 가 정확히 한 번이 아니다")
        #expect(store.focusStage(now: clock.now) == .off)
        #expect(store.focusStageRecord(for: stageUserA) == nil, "성공한 만료 뒤에 1단 기록이 남았다")
        #expect(store.pokeNotice == nil, "사용자가 누르지 않은 만료에 실패 안내가 떴다")
    }

    /// 만료 PATCH 가 실패하면: 60초 전엔 재시도 없음 · 60초 뒤 재시도 · 그동안 화면이 **다시 켜지지 않는다**.
    @Test func expiryFailureRetriesNoSoonerThanSixtySecondsAndNeverRelightsTheButton() async {
        let host = "focus-stage-expire-fail"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)
        store.cycleFocusStage()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })
        let until = stageT0.addingTimeInterval(threeHours)

        FocusStageStub.setPatchStatus(500, host: host)   // 무료 플랜 일시정지 같은 5xx
        clock.now = until
        store.tick()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 2 })
        #expect(store.focusMode == false, "만료 PATCH 실패가 화면을 다시 켰다(원복 깜빡임)")
        #expect(store.focusStage(now: clock.now) == .off)
        #expect(store.pokeNotice == nil)
        // 성공할 때까지 기록은 남는다 — 지우면 앱 재시작 때 '서버 true + 기록 없음' = 2단으로 되살아난다.
        #expect(store.focusStageRecord(for: stageUserA)?.stage == .timed)
        #expect(store.focusExpiryRetryAt == until.addingTimeInterval(60))

        // 59초: 틱도, 폴링(설정 로드 포함)도 재시도하지 않는다.
        clock.now = until.addingTimeInterval(59)
        store.tick()
        await store.localExpiryTick()
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host).count == 2, "60초 전에 재시도했다")
        #expect(store.focusMode == false)

        // 60초: 재시도 한 건.
        clock.now = until.addingTimeInterval(60)
        store.tick()
        store.tick()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 3 })
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host) == [true, false, false])
        #expect(store.focusMode == false, "재시도 실패가 화면을 다시 켰다")
        #expect(store.focusExpiryRetryAt == until.addingTimeInterval(120))

        // 서버가 살아나면 다음 재시도에서 끝난다.
        FocusStageStub.setPatchStatus(204, host: host)
        clock.now = until.addingTimeInterval(120)
        store.tick()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 4 })
        #expect(store.focusStageRecord(for: stageUserA) == nil)
        #expect(store.focusExpiryRetryAt == nil)
        #expect(FocusStageStub.serverValue(host: host) == false)
    }

    /// 앱 재시작 흉내: 같은 defaults 로 새 스토어 + 서버 true + 만료된 기록 → **설정 로드 직후** PATCH false.
    @Test func restartWithExpiredRecordPatchesFalseRightAfterSettingsLoad() async {
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let hostBefore = "focus-stage-restart-before"
        do {
            let first = makeStageStore(host: hostBefore, defaults: defaults, clock: clock)
            first.cycleFocusStage()
            #expect(await settle(first) { FocusStageStub.patches(host: hostBefore).count == 1 })
        }

        // 앱이 꺼진 채 3시간 1초. 서버에는 true 가 남아 있다(앱이 꺼져 있어 아무도 끄지 않았다 — 설계상 괜찮은 상태).
        let hostAfter = "focus-stage-restart-after"
        FocusStageStub.setServerFocus(true, host: hostAfter)
        clock.now = stageT0.addingTimeInterval(threeHours + 1)
        let second = makeStageStore(host: hostAfter, defaults: defaults, clock: clock)
        // 설정 로드 전의 틱은 아무것도 보내지 않는다(서버값을 모르고, 화면도 꺼짐이다).
        second.tick()
        await quiesce(second)
        #expect(FocusStageStub.patches(host: hostAfter).isEmpty)

        await second.loadTokenUsagePrivacyIfNeeded()
        #expect(second.focusMode == false, "끝난 1단이 설정 로드 직후 켜진 채로 보였다")
        #expect(await settle(second) { FocusStageStub.patches(host: hostAfter).count == 1 })
        #expect(FocusStageStub.patches(host: hostAfter) == [false])
        #expect(second.focusStage(now: clock.now) == .off)
        #expect(second.focusStageRecord(for: stageUserA) == nil)
    }

    /// 재시작했는데 1단이 아직 남았으면 요청 없이 **이어서 센다**(같은 시계로 적은 until 그대로).
    @Test func restartWithLiveTimedRecordContinuesCountingWithoutRequests() async {
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let hostBefore = "focus-stage-resume-before"
        do {
            let first = makeStageStore(host: hostBefore, defaults: defaults, clock: clock)
            first.cycleFocusStage()
            #expect(await settle(first) { FocusStageStub.patches(host: hostBefore).count == 1 })
        }
        let hostAfter = "focus-stage-resume-after"
        FocusStageStub.setServerFocus(true, host: hostAfter)
        clock.now = stageT0.addingTimeInterval(3_600)
        let second = makeStageStore(host: hostAfter, defaults: defaults, clock: clock)
        await second.loadTokenUsagePrivacyIfNeeded()
        await quiesce(second)
        #expect(second.focusStage(now: clock.now) == .timed)
        #expect(second.focusStageFace(now: clock.now) == FocusStageFace(stage: .timed, remainingSeconds: 7_200))
        #expect(FocusStageStub.patches(host: hostAfter).isEmpty)
    }

    /// 틱이 멈춘 사람(비근무 + 팝오버 닫힘)의 1단도 풀린다 — 깨어날 때, 그리고 상시 도는 수신 폴링에서.
    @Test func wakeAndPollExpireTimedStageEvenWhenTheTickerIsIdle() async {
        let until = stageT0.addingTimeInterval(threeHours)

        let wakeHost = "focus-stage-wake"
        let (wakeDefaults, _) = freshStageDefaults()
        let wakeClock = StageClock(stageT0)
        let waking = makeStageStore(host: wakeHost, defaults: wakeDefaults, clock: wakeClock)
        waking.cycleFocusStage()
        #expect(await settle(waking) { FocusStageStub.patches(host: wakeHost).count == 1 })
        wakeClock.now = until.addingTimeInterval(9 * 3_600)   // 켜 두고 덮개를 닫은 다음 날 아침
        waking.handleWake(at: wakeClock.now)
        #expect(waking.focusMode == false)
        #expect(await settle(waking) { FocusStageStub.patches(host: wakeHost).count == 2 })
        #expect(FocusStageStub.patches(host: wakeHost) == [true, false])

        let pollHost = "focus-stage-poll"
        let (pollDefaults, _) = freshStageDefaults()
        let pollClock = StageClock(stageT0)
        let polling = makeStageStore(host: pollHost, defaults: pollDefaults, clock: pollClock)
        polling.cycleFocusStage()
        #expect(await settle(polling) { FocusStageStub.patches(host: pollHost).count == 1 })
        // 설정은 이미 받았다고 둔다 — 이 폴링의 만료 확인 자체를 본다(설정 로드 경로는 재시작 테스트가 본다).
        polling.tokenUsageCollectLoaded = true
        pollClock.now = until.addingTimeInterval(30)
        await polling.localExpiryTick()
        #expect(await settle(polling) { FocusStageStub.patches(host: pollHost).count == 2 })
        #expect(FocusStageStub.patches(host: pollHost) == [true, false])
        #expect(polling.focusStage(now: pollClock.now) == .off)
    }

    // MARK: 계정 교체

    /// A 의 1단 기록이 B 화면에 안 보인다. A 가 다시 로그인하면 이어진다.
    @Test func accountSwitchDoesNotLeakPreviousUsersTimedStage() async {
        let host = "focus-stage-account"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock, userID: stageUserA)
        store.cycleFocusStage()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })
        #expect(store.focusStage(now: clock.now) == .timed)

        // A 로그아웃 → 같은 맥에서 B 로그인. B 는 서버에 집중 모드를 켜 둔 기존 사용자다 —
        // A 의 기록이 새면 B 화면이 '1단 · 남은 시간'으로 보인다.
        store.clearPersistedSession()
        #expect(store.focusMode == false, "로그아웃 뒤에도 앞 사람의 켜짐이 남았다")
        #expect(store.focusStage(now: clock.now) == .off)
        store.session = SupabaseSession(accessToken: "access-token-b", refreshToken: nil, userID: stageUserB)
        FocusStageStub.setServerFocus(true, host: host)
        await store.loadTokenUsagePrivacyIfNeeded()
        await quiesce(store)
        #expect(store.focusStage(now: clock.now) == .always, "A 의 1단이 B 화면에 샜다")
        #expect(store.focusStageFace(now: clock.now) == FocusStageFace(stage: .always))
        #expect(store.focusStageRecord(for: stageUserB) == nil)
        // 로그아웃은 A 의 기록을 지우지 않는다.
        #expect(store.focusStageRecord(for: stageUserA)?.stage == .timed)

        // A 가 다시 로그인하면 남은 시간 그대로 이어진다.
        store.clearPersistedSession()
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: stageUserA)
        clock.advance(600)
        await store.loadTokenUsagePrivacyIfNeeded()
        await quiesce(store)
        #expect(store.focusStage(now: clock.now) == .timed)
        #expect(store.focusStageFace(now: clock.now).remainingSeconds == Int(threeHours) - 600)
        #expect(FocusStageStub.patches(host: host) == [true], "계정 교체가 요청을 만들었다")
    }

    // MARK: 기존 사용자 전환 — 2단(always)

    /// 서버 true + 이 맥에 기록 없음 → **always** · PATCH 0건 · 시간이 흘러도 · 재시작해도 always.
    /// (2026-09-11 사용자 지시. 앞 판의 "1단으로 전환해 3시간 센다"와 "한 번만 전환" 표지는 폐기됐다.)
    @Test func legacyServerOnWithoutRecordStaysAlwaysWithZeroPatchesAcrossRestart() async {
        let host = "focus-stage-legacy"
        FocusStageStub.setServerFocus(true, host: host)
        let (defaults, suite) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)

        await store.loadTokenUsagePrivacyIfNeeded()
        #expect(store.focusMode)
        #expect(store.focusStage(now: clock.now) == .always)

        // 열 시간이 흘러도 풀리지 않는다 — 틱·깨어남·폴링 어디서도 요청 0건.
        clock.advance(10 * 3_600)
        store.tick()
        store.handleWake(at: clock.now)
        await store.localExpiryTick()
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host).isEmpty, "기록 없는 기존 사용자에게 요청이 나갔다")
        #expect(store.focusStage(now: clock.now) == .always)
        // 기록도, '전환했다'는 표지도 쓰지 않는다 — 기록이 없다는 것 자체가 always 의 뜻이다.
        let focusKeys = (defaults.persistentDomain(forName: suite) ?? [:]).keys.filter { $0.lowercased().contains("focus") }
        #expect(focusKeys.isEmpty, "기존 사용자에게 집중 모드 키가 쓰였다: \(focusKeys)")

        // 재시작해도 always.
        let restarted = makeStageStore(host: host, defaults: defaults, clock: clock)
        await restarted.loadTokenUsagePrivacyIfNeeded()
        await quiesce(restarted)
        #expect(restarted.focusStage(now: clock.now) == .always)
        #expect(FocusStageStub.patches(host: host).isEmpty)
    }

    // MARK: 설정 로드

    /// 설정 로드가 서버 false 를 가져오면 로컬 기록을 지운다(다른 맥에서 껐거나 서버가 덮었다).
    @Test func settingsLoadWithServerOffClearsTheLocalRecord() async {
        let host = "focus-stage-server-off"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)
        store.cycleFocusStage()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })

        FocusStageStub.setServerFocus(false, host: host)
        store.tokenUsageCollectLoaded = false
        await store.loadTokenUsagePrivacyIfNeeded()
        #expect(store.focusMode == false)
        #expect(store.focusStage(now: clock.now) == .off)
        #expect(store.focusStageRecord(for: stageUserA) == nil)
        await quiesce(store)
        #expect(FocusStageStub.patches(host: host) == [true], "서버 꺼짐을 받고 요청을 만들었다")
    }

    /// GET 이 나간 뒤에 누른 것이 서버에 닿았으면, 늦게 도착한 GET(더 낡은 false)이 방금 켠 1단을 덮지 않는다.
    @Test func staleSettingsResponseDoesNotOverrideAPressThatReachedTheServer() async {
        let host = "focus-stage-stale-get"
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: host, defaults: defaults, clock: clock)
        let serialBeforeGet = store.focusIntentSerial
        store.cycleFocusStage()
        #expect(await settle(store) { FocusStageStub.patches(host: host).count == 1 })

        store.applyServerFocusMode(false, intentSerialAtRequest: serialBeforeGet)
        #expect(store.focusStage(now: clock.now) == .timed)
        #expect(store.focusStageRecord(for: stageUserA)?.stage == .timed)
    }

    // MARK: 4) 버튼 뷰

    /// 성능 규약: 버튼 잎의 읽기는 **1단일 때만** 시계를 평가한다. 꺼짐·2단에서 시계를 읽으면 그 잎이 초침에 관찰
    /// 등록돼 보일 것이 없는데도 매초 다시 그려진다.
    @Test func faceReadsTheClockOnlyInTheTimedStage() {
        let (defaults, _) = freshStageDefaults()
        let clock = StageClock(stageT0)
        let store = makeStageStore(host: "focus-stage-face", defaults: defaults, clock: clock)
        var clockReads = 0
        func readClock() -> Date {
            clockReads += 1
            return clock.now
        }

        #expect(store.focusStageFace(now: readClock()) == .off)
        #expect(clockReads == 0)

        store.focusMode = true   // 기록 없음 → 2단
        #expect(store.focusStageFace(now: readClock()) == FocusStageFace(stage: .always))
        store.writeFocusStageRecord(FocusStageRecord(stage: .always, until: nil), for: stageUserA)
        #expect(store.focusStageFace(now: readClock()) == FocusStageFace(stage: .always))
        #expect(clockReads == 0, "꺼짐/2단에서 시계를 읽었다 — 버튼 잎이 매초 돈다")

        store.writeFocusStageRecord(FocusStageRecord(stage: .timed, until: stageT0.addingTimeInterval(2 * 3_600 + 12 * 60)), for: stageUserA)
        #expect(store.focusStageFace(now: readClock()) == FocusStageFace(stage: .timed, remainingSeconds: 2 * 3_600 + 12 * 60))
        #expect(clockReads == 1)
    }

    @Test func remainingTimeTextAndTooltipsSayWhatTheNextPressDoes() {
        #expect(FocusModeButtonText.remaining(seconds: 2 * 3_600 + 12 * 60) == "2시간 12분")
        #expect(FocusModeButtonText.remaining(seconds: 2 * 3_600 + 12 * 60 + 59) == "2시간 12분")
        #expect(FocusModeButtonText.remaining(seconds: 3 * 3_600) == "3시간")
        #expect(FocusModeButtonText.remaining(seconds: 3 * 3_600 - 1) == "2시간 59분")
        #expect(FocusModeButtonText.remaining(seconds: 42 * 60) == "42분")
        #expect(FocusModeButtonText.remaining(seconds: 3_599) == "59분")
        #expect(FocusModeButtonText.remaining(seconds: 60) == "1분")
        #expect(FocusModeButtonText.remaining(seconds: 59) == "곧 해제")
        #expect(FocusModeButtonText.remaining(seconds: 0) == "곧 해제")

        #expect(FocusModeButtonText.help(.off) == "누르면 3시간 집중")
        #expect(FocusModeButtonText.help(.timed) == "한 번 더 누르면 끌 때까지 계속")
        #expect(FocusModeButtonText.help(.always) == "누르면 집중 모드 해제")

        // v0.3.01: 버튼 글자는 단계 이름, 남은 시간은 툴팁이 말한다.
        #expect(FocusModeButtonText.label(.off) == "집중")
        #expect(FocusModeButtonText.label(FocusStageFace(stage: .timed, remainingSeconds: 7_920)) == "1단")
        #expect(FocusModeButtonText.label(FocusStageFace(stage: .always)) == "2단")
        #expect(FocusModeButtonText.tooltip(FocusStageFace(stage: .timed, remainingSeconds: 2 * 3_600 + 12 * 60))
                == "1단 · 2시간 12분 남음 — 한 번 더 누르면 끌 때까지 계속")
        #expect(FocusModeButtonText.tooltip(.off) == "집중 모드 꺼짐 — 누르면 3시간 집중")
        #expect(FocusModeButtonText.tooltip(FocusStageFace(stage: .always)) == "2단 · 끌 때까지 계속 — 누르면 집중 모드 해제")
    }

    /// 색만으로 알리지 않는다: 어느 두 단계 사이에도 바탕 농도·달·글자 중 **최소 두 갈래**가 달라야 한다.
    @Test func everyPairOfStagesDiffersInAtLeastTwoNonColorChannels() {
        let faces = [
            FocusStageFace.off,
            FocusStageFace(stage: .timed, remainingSeconds: 2 * 3_600 + 12 * 60),
            FocusStageFace(stage: .timed, remainingSeconds: 30),
            FocusStageFace(stage: .always)
        ]
        for a in faces {
            for b in faces where a.stage != b.stage {
                let styleA = FocusModeButtonStyle(stage: a.stage)
                let styleB = FocusModeButtonStyle(stage: b.stage)
                var channels = 0
                if styleA.fillLevel != styleB.fillLevel { channels += 1 }
                if styleA.icon != styleB.icon { channels += 1 }
                if FocusModeButtonText.label(a) != FocusModeButtonText.label(b) { channels += 1 }
                #expect(channels >= 2, "\(a.stage) ↔ \(b.stage) 가 색 말고 \(channels)갈래만 다르다")
            }
        }
        #expect(FocusModeButtonStyle(stage: .off).fillLevel == 0)
        #expect(FocusModeButtonStyle(stage: .timed).fillLevel == 1)
        #expect(FocusModeButtonStyle(stage: .always).fillLevel == 2)
    }

    /// 옛 달 아이콘 자리에 그대로 들어간다: 높이는 IconButton 과 같고, 넓어진 폭을 반영해도 제목 행 힌트가 말줄임되지 않는다.
    ///
    /// ★ 늘어난 폭(extra = 이 버튼 50 - 옛 IconButton 27)은 **예산이 아직 이 버튼을 세지 않을 때만** 뺀다(2026-09-11 검토 지적).
    ///   배선 전 예산(PokeTitleRowWidthBudget)은 `iconButtonWidth * 2`(옛 27pt 두 개)라, 여기서 extra 를 빼야 배선 뒤의 행을 잰다.
    ///   배선 때 예산이 `CheckFocusModeButton.width` 를 쓰게 바뀌면 extra 는 이미 빠져 있다. 그때 또 빼면 23pt 가 두 번 빠져,
    ///   실제 행은 들어가는데(힌트 80/73/77pt ≥ 71) 이 테스트만 병합 직후 빨개진다(검토 담당이 사본 배선으로 재현 — 6 issues).
    ///   **"무조건 extra 를 뺀다"로 되돌리지 마라.** 뒤로 버튼 때문에 `iconButtonWidth` 는 27 로 남으므로, 50pt 를 반영하는
    ///   어떤 예산 변경이든 같은 이중 차감이 난다.
    ///   분기는 예산 조립식을 이 테스트에 베껴 값으로 가르지 않고 **주석을 걷어낸 소스**로 가른다 — 베끼면 누가 제목 행에
    ///   항목을 더할 때마다 이 테스트만 따로 낡는다. 폭은 언제나 예산 함수가 계산한 값에서 출발한다.
    @Test func buttonFitsTheOldIconSlotOfThePokeTitleRow() throws {
        typealias Budget = PokeTitleRowWidthBudget
        #expect(CheckFocusModeButton.height == 27)

        let menuCode = strippingFocusSourceComments(
            try String(contentsOf: focusCheckSourceURL("CheckMenuView.swift"), encoding: .utf8)
        )
        let budgetBody = try #require(
            focusDeclarationBody("enum PokeTitleRowWidthBudget", in: menuCode),
            "CheckMenuView.swift 에서 PokeTitleRowWidthBudget 을 못 찾았다 — 옮겼으면 이 경로를 따라가라"
        )
        let panelBody = try #require(
            focusDeclarationBody("struct PokePanel", in: menuCode),
            "CheckMenuView.swift 에서 PokePanel(콕 찌르기 제목 행)을 못 찾았다 — 옮겼으면 이 경로를 따라가라"
        )
        let budgetCountsButton = budgetBody.contains("CheckFocusModeButton.width")
        let rowUsesButton = panelBody.contains("CheckFocusModeButton(")
        // 짝 게이트: 제목 행에 이 버튼을 꽂는 배선과, 예산이 이 버튼 폭을 세는 변경은 **한 묶음**이다. 한쪽만 들어가면
        // UltraPokeButtonTests/UltraPokeTests 의 힌트 폭 단언이 23pt 거짓 여유(또는 거짓 부족)를 믿고 판정한다.
        // 예산에 50 을 숫자로 베껴 넣어도 여기서 빨개진다 — 버튼 폭이 바뀌면 예산이 저절로 따라가야 해서다.
        #expect(
            rowUsesButton == budgetCountsButton,
            "제목 행의 CheckFocusModeButton 사용(\(rowUsesButton)) ≠ 예산의 CheckFocusModeButton.width 사용(\(budgetCountsButton)) — 배선과 예산 변경은 함께 들어가야 한다"
        )
        // 예산의 두 조합(숫자 배지 · 무제한 배지)이 **같은 버튼 폭**을 센다. 위 소스 판정은 "예산 어딘가에 버튼 폭이 있다"만
        // 보므로, 한 함수만 고친 반쪽 수정은 이 대조가 잡는다(둘의 차이가 배지 폭 차이에서 23pt 어긋난다).
        for digits in [1, 2] {
            #expect(
                Budget.hintWidth(digits: digits) - Budget.hintWidthWhenUnlimited
                    == Budget.unlimitedBadgeWidth - Budget.badgeWidth(digits: digits),
                "hintWidth 와 hintWidthWhenUnlimited 가 서로 다른 버튼 폭을 센다(잔량 \(digits)자리)"
            )
        }

        let extra = budgetCountsButton ? 0 : CheckFocusModeButton.width - Budget.iconButtonWidth
        let glyph = Budget.koreanCaptionGlyphWidth
        let rows: [(String, CGFloat)] = [
            ("잔량 1자리", Budget.hintWidth(digits: 1) - extra),
            ("잔량 2자리", Budget.hintWidth(digits: 2) - extra),
            ("무제한 ∞", Budget.hintWidthWhenUnlimited - extra)
        ]
        for (name, hint) in rows {
            #expect(hint >= Budget.longestHintWidth,
                    "\(name): 힌트에 \(hint)pt 남는다 — 가장 긴 힌트(\(Budget.longestHintWidth)pt)가 말줄임된다")
            // 잔량 0 일 때의 힌트("미션으로 충전")도 한글 글자수로 들어가야 한다.
            #expect(Int(hint / glyph) >= UltraBalanceText.empty.count,
                    "\(name): 힌트 자리에 한글 \(Int(hint / glyph))자 — '\(UltraBalanceText.empty)'가 말줄임된다")
        }
        // 한 줄 캡슐(v0.3.01): 달(9pt ≈ 10) + 간격 3 + 가장 넓은 글자(caption2 bold) + 좌우 여백 4×2 가 폭 안에 든다.
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        let labels = ["집중", "1단", "2단"]
        let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        #expect(10 + 3 + widest + 8 <= CheckFocusModeButton.width, "버튼 글자(\(widest)pt)가 캡슐 폭을 넘는다")
    }

    @Test func reduceMotionTurnsTheStageTransitionOff() {
        #expect(FocusModeButtonStyle.transition(reduceMotion: true) == nil)
        #expect(FocusModeButtonStyle.transition(reduceMotion: false) != nil)
    }

    /// 픽셀: 세 단계가 **같은 크기**로 그려지고(제목 행이 단계마다 흔들리지 않는다) 서로 다른 그림이다.
    /// 기준선(꺼짐)과 비교 대상이 실제로 다른 입력이어야 이 비교가 뜻을 갖는다.
    @Test func threeStagesRenderAtTheSameSizeAsDifferentPictures() throws {
        let faces = [FocusStageFace.off, FocusStageFace(stage: .timed, remainingSeconds: 7_920), FocusStageFace(stage: .always)]
        let bitmaps = try faces.map { face in
            try #require(renderFocusBitmap(CheckFocusModeFace(face: face, reduceMotion: true, action: {}), scale: 2))
        }
        for bitmap in bitmaps {
            #expect(bitmap.pixelsWide == Int(CheckFocusModeButton.width * 2))
            #expect(bitmap.pixelsHigh == Int(CheckFocusModeButton.height * 2))
        }
        let pngs = bitmaps.map { $0.representation(using: .png, properties: [:]) }
        #expect(pngs[0] != pngs[1])
        #expect(pngs[1] != pngs[2])
        #expect(pngs[0] != pngs[2])
    }

    /// 눈으로 보는 증거. `CHECK_FOCUS_SNAPSHOT_DIR` 이 있을 때만 쓴다(평소 실행은 파일을 만들지 않는다).
    /// 실제 잎 경로(CheckFocusModeButton → MenuClockLeaf)로 그리고, 옛 달 아이콘 자리(제목 행)에 끼워 폭까지 본다.
    @Test func dumpFocusStageSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_FOCUS_SNAPSHOT_DIR"] else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let shots: [(String, String, FocusStageFace, Bool)] = [
            ("focus-off.png", "꺼짐", .off, false),
            ("focus-timed-2h12m.png", "1단 · 2시간 12분", FocusStageFace(stage: .timed, remainingSeconds: 2 * 3_600 + 12 * 60), false),
            ("focus-timed-soon.png", "1단 · 곧 해제", FocusStageFace(stage: .timed, remainingSeconds: 42), false),
            ("focus-always.png", "2단 · 계속", FocusStageFace(stage: .always), false),
            ("focus-reduce-motion.png", "동작 줄이기 · 1단 · 2시간 12분", FocusStageFace(stage: .timed, remainingSeconds: 2 * 3_600 + 12 * 60), true)
        ]
        for (file, caption, face, reduces) in shots {
            let bitmap = try #require(renderFocusBitmap(focusTitleRowPreview(face, caption: caption, reduceMotion: reduces), scale: 3))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: base.appendingPathComponent(file))
        }
        // 세 단계를 한 장에 — 나란히 놓고 구분되는지 본다.
        let strip = VStack(spacing: 0) {
            ForEach(Array(shots.prefix(4).enumerated()), id: \.offset) { _, shot in
                focusTitleRowPreview(shot.2, caption: shot.1, reduceMotion: false)
            }
        }
        let stripBitmap = try #require(renderFocusBitmap(strip, scale: 3))
        try #require(stripBitmap.representation(using: .png, properties: [:]))
            .write(to: base.appendingPathComponent("focus-stages-strip.png"))
    }
}

// MARK: - 렌더 헬퍼(이 파일 전용)

@MainActor
private func renderFocusBitmap(_ view: some View, scale: CGFloat) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

/// 콕 찌르기 패널 제목 행 복제(CheckMenuView.PokePanel 의 행 구성 그대로 — 뒤로 · 제목 · **집중 버튼** · Spacer · 잔량 배지 · 힌트).
/// 본문 열 316pt · 패널 padding 12 — 옛 달 아이콘 자리에 들어갔을 때 폭이 맞는지 픽셀로 본다.
@MainActor
private func focusTitleRowPreview(_ face: FocusStageFace, caption: String, reduceMotion: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(caption)
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText)
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: "뒤로", action: {})
            Text("콕 찌르기")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            CheckFocusModeButton(read: { face }, action: {}, reduceMotion: reduceMotion)
            Spacer(minLength: 6)
            UltraBalanceBadge(balance: 3, action: {})
            Text(UltraBalanceText.hint(balance: 3))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize()
        }
        .padding(12)
        .frame(width: 316)
        .panelStyle()
    }
    .padding(10)
    .background(Color(red: 0.10, green: 0.11, blue: 0.15))
}

// MARK: - 소스 판정 헬퍼(이 파일 전용)

/// `Sources/check/<name>` 경로. 테스트 파일 위치(#filePath)에서 상대로 찾는다.
private func focusCheckSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 저장소 루트
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안은 남긴다.
/// 걷어내지 않으면 "옛 IconButton 을 CheckFocusModeButton 으로 바꿨다" 같은 **설명 주석**이 소스 판정을 뒤집어,
/// 초록으로 만들려면 설명을 지워야 하는 테스트가 된다(하우스 규칙).
private func strippingFocusSourceComments(_ source: String) -> String {
    var result = ""
    var inString = false, inLineComment = false, inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let c = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else {
            if c == "\"" { inString = true }
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

/// `declaration`(예: "enum PokeTitleRowWidthBudget")의 본문 `{ … }` 안쪽. 이름 바로 뒤가 식별자 글자면 다른 선언이다
/// ("struct PokePanel" 이 "struct PokePanelNoticeLine" 에 걸리지 않게). 범위를 좁혀야 파일 전체 contains 의 오탐을 피한다.
private func focusDeclarationBody(_ declaration: String, in code: String) -> String? {
    var searchStart = code.startIndex
    while let found = code.range(of: declaration, range: searchStart..<code.endIndex) {
        searchStart = found.upperBound
        if found.upperBound < code.endIndex {
            let following = code[found.upperBound]
            if following.isLetter || following.isNumber || following == "_" { continue }
        }
        guard let open = code[found.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < code.endIndex {
            switch code[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(code[code.index(after: open)..<index]) }
            default: break
            }
            index = code.index(after: index)
        }
        return nil
    }
    return nil
}
