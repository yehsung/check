import CheckCore
import Foundation
import Testing
@testable import check

// MARK: - AI 리밋: 근무 밖에도 읽는다 (2026-11-19 대표 결정 #d_wUQfi8Uo68gx)
//
// 대표 질문(11-18): "근무중 상태 아니어도 앱 켜져있으면 토큰 리밋 정확하게 확인하게끔 할 수 있나?"
// 그 전의 폴링 루프는 `isMenuPresented || isWorking` 일 때만 리밋 스토어를 불렀다. 그래서 근무 밖에 팝오버를
// 안 여는 동안에는 한 번도 안 읽어, 폰 '나' 탭·위젯이 마지막 근무 때 숫자에 멈춰 "27% 이상 · 3시간 전"이 됐다.
//
// 이 파일은 **실물 폴링 루프**로 잰다 — `refreshAILimitsIfNeeded` 를 직접 부르는 시험은 루프에 배선이 걸려 있는지
// 말해 주지 못한다(V0240 의 `refreshLoopBodyScansInTheBackgroundOnlyWhileWorkingWithThePopoverClosed` 와 같은 까닭).
//
// ★ 리더는 전부 가짜(러너 주입)다 — 실제 Claude 를 부르면 5분 5회 상한을 넘겨 사용자 계정이 5분간 잠긴다.
// ★ 서버도 가짜(URLProtocolStub 호스트)다 — 운영에 닿지 않는다.

/// 러너가 몇 번 불렸고 무엇을 물었는지 센다. 요청받은 제공자만 값을 돌려준다.
private final class IdleRunnerSpy: @unchecked Sendable {
    private(set) var requested: [Set<AILimitProvider>] = []
    var callCount: Int { requested.count }

    func runner() -> AILimitStore.Runner {
        { [self] now, providers in
            requested.append(providers)
            var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]
            for provider in providers {
                results[provider] = .success(AILimitProviderSnapshot(
                    provider: provider,
                    windows: [
                        AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27,
                                              resetsAt: now.addingTimeInterval(3_600),
                                              observedAt: now, source: .local),
                        AILimitWindowSnapshot(window: .weekly, usedPercent: 60,
                                              resetsAt: now.addingTimeInterval(86_400),
                                              observedAt: now, source: .local)
                    ],
                    planLabel: "max"
                ))
            }
            return AILimitReadOutcome(results: results)
        }
    }
}

@Suite("AI 리밋 — 근무 밖에도 폴링 루프가 읽는다(11-19)")
@MainActor
struct AILimitIdleRefreshTests {
    private func defaults(_ function: String = #function, line: Int = #line) -> UserDefaults {
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 로그인했고 기기 신원이 있고 **근무 중이 아니며 팝오버도 닫힌** 맥. 리밋 스토어 시계는 실제 시각이다 —
    /// 루프가 `refreshAILimitsIfNeeded()` 를 기본 인자(`Date()`)로 부르므로 스토어도 같은 시계로 재야 한다.
    private func idleStore(host: String, defaults: UserDefaults, limits: AILimitStore) -> WorkTimerStore {
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults,
            workspaceNotifications: nil,
            aiLimits: limits
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        // 기기 신원은 지어내지 않고 있는 것을 쓴다(관례: '기기 신원을 지어내지 마라').
        store.deviceID = "MAC-IDLE-1119"
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.membershipConfirmed = true
        store.isMenuPresented = false
        // 유휴 루프는 슬라이스 10번을 자고 본문을 돈다 — 0.05초로 줄여 0.5초마다 본문이 돌게 한다.
        store.refreshLoopSliceSeconds = 0.05
        return store
    }

    private func cancelTasks(_ store: WorkTimerStore) {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
        store.session = nil
    }

    /// 조건이 참이 될 때까지 기다린다. 벽시계가 아니라 **재개 횟수**로 상한을 둔다 — 병렬 스위트에서 메인 액터가
    /// 굶주리는 구간에 예산만 태우고 오판하지 않게(V0240 `v0240WaitUntil` 과 같은 관용구).
    private func waitUntil(maxResumes: Int = 3_000, _ condition: () -> Bool) async {
        for _ in 0..<maxResumes {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func requestCount(host: String, path: String) -> Int {
        URLProtocolStub.requests(forHost: host).filter { $0.url?.path == path }.count
    }

    /// 루프 본문이 돈 흔적 — 리밋 표 밖으로 나간 요청 수. 본문마다 팀 상태 요청(work_tick, 또는 그것이 꺼졌으면
    /// 옛 팀 상태 조회)이 적어도 하나 나가고, 루프 밖에서 나가는 요청은 시작할 때 한두 번뿐이다.
    private func bodyRequestCount(host: String) -> Int {
        URLProtocolStub.requests(forHost: host).filter {
            let path = $0.url?.path ?? ""
            return path != SupabaseWorkService.aiLimitsPath && path != SupabaseWorkService.aiLimitsPrefsPath
        }.count
    }

    private func paths(host: String) -> String {
        URLProtocolStub.requests(forHost: host).map { $0.url?.path ?? "?" }.joined(separator: " ")
    }

    /// 없으면: 근무 밖에 팝오버를 안 여는 동안 리밋을 한 번도 안 읽고 안 올린다 — 폰·위젯 숫자가 멈춘다.
    /// 뮤테이션: 루프의 호출을 `if isMenuPresented || snapshot.isWorking` 으로 다시 감싸면 러너 0회 = 빨강.
    @Test
    func idleLoopReadsAndUploadsLimitsWithoutWorkOrPopover() async {
        let host = "ailimit-idle-reads"
        let defaults = defaults()
        let spy = IdleRunnerSpy()
        let limits = AILimitStore(defaults: defaults, clock: { Date() }, runner: spy.runner())
        let store = idleStore(host: host, defaults: defaults, limits: limits)
        defer { cancelTasks(store) }
        #expect(store.snapshot.isWorking == false, "전제: 근무 중이 아니다")
        #expect(store.isMenuPresented == false, "전제: 팝오버가 닫혀 있다")

        store.startStatusRefreshLoop()
        await waitUntil { spy.callCount >= 1 }
        #expect(spy.callCount >= 1, "근무 밖 · 팝오버 닫힘인데 루프가 리밋을 안 읽었다 — 폰·위젯 숫자가 멈춘다")

        // 읽은 숫자가 서버(가짜)까지 간다 — 폰·위젯이 보는 길이다.
        await waitUntil { requestCount(host: host, path: SupabaseWorkService.aiLimitsPath) >= 1 }
        #expect(requestCount(host: host, path: SupabaseWorkService.aiLimitsPath) >= 1,
                "근무 밖에 읽은 리밋이 서버에 안 올라갔다")
        #expect(store.snapshot.isWorking == false, "시험 도중 근무가 시작됐다(전제 붕괴)")
    }

    /// 없으면: 게이트를 걷은 뒤 루프 본문마다 제공자를 두드려 Claude 의 5분 5회 상한을 넘긴다(계정 5분 잠김).
    /// 주기는 스토어의 10분 간격이 쥔다 — 본문이 여러 번 돌아도 그 안이면 러너는 한 번뿐이다.
    @Test
    func idleLoopKeepsTheStoreIntervalAcrossManyBodies() async {
        let host = "ailimit-idle-interval"
        let defaults = defaults()
        let spy = IdleRunnerSpy()
        let limits = AILimitStore(defaults: defaults, clock: { Date() }, runner: spy.runner())
        let store = idleStore(host: host, defaults: defaults, limits: limits)
        defer { cancelTasks(store) }

        store.startStatusRefreshLoop()
        await waitUntil { spy.callCount >= 1 }
        #expect(spy.callCount == 1, "전제: 첫 본문에서 한 번 읽었다")
        // 본문이 몇 번 더 돌 때까지 기다린다(본문마다 팀 상태 요청이 나간다).
        let atFirstRead = bodyRequestCount(host: host)
        await waitUntil { bodyRequestCount(host: host) >= atFirstRead + 4 }
        #expect(bodyRequestCount(host: host) >= atFirstRead + 4, "루프 본문이 더 돌지 않았다(전제 붕괴): \(paths(host: host))")
        #expect(spy.callCount == 1, "10분 간격 안에서 본문마다 다시 읽었다 — Claude 5분 5회 상한을 넘긴다")
    }

    /// 없으면: 게이트를 걷은 뒤 보기 스위치를 끈 사람의 로그인 정보까지 근무 밖에 계속 읽는다(처리방침 위반).
    @Test
    func idleLoopReadsNothingWhenTheMasterSwitchIsOff() async {
        let host = "ailimit-idle-master-off"
        let defaults = defaults()
        let spy = IdleRunnerSpy()
        let limits = AILimitStore(defaults: defaults, clock: { Date() }, runner: spy.runner())
        limits.setMasterEnabled(false)
        let store = idleStore(host: host, defaults: defaults, limits: limits)
        defer { cancelTasks(store) }

        store.startStatusRefreshLoop()
        await waitUntil { bodyRequestCount(host: host) >= 5 }
        #expect(bodyRequestCount(host: host) >= 5, "루프 본문이 돌지 않았다(전제 붕괴): \(paths(host: host))")
        #expect(spy.callCount == 0, "리밋 보기를 껐는데 근무 밖 루프가 로그인 정보를 읽었다")
    }
}
