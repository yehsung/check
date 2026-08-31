import Foundation
import Testing
@testable import check

// v0.2.38 "가벼워지기" 트랙 δ — 네트워크 다이어트 계약 고정.
//
// 계측으로 확정된 사실(근무 중 30초마다 REST 7~8건, 송신 9.6KB/30s)을 줄이는 다섯 가지 수리를 요청 전수 기록
// (URLProtocolStub)으로 못 박는다:
//  [Q7]  닫힌 팝오버의 '마지막으로 본 패널'(리그·토큰 보드·콕찌르기 디렉토리)은 서버를 두드리지 않는다.
//  [Q8]  리얼타임 구독 중 take_pokes 폴링 주기 15 → 60초(미구독·킬스위치는 15초 유지).
//  [Q9]  폴링 세션은 URLCache 를 쓰지 않고, work_statuses select 에 email 이 없고, weekly select 가 3컬럼이다.
//  [Q10] 팝오버 재오픈 fast path 는 팀 상태가 15초 안이면 4 GET 을 건너뛴다.
//  [M8]  토큰 업로드의 옛 표 현재값 GET 은 KST 하루 1회다.
//
// 테스트 plist 는 **고정 이름**이다(UUID 접미어 없음) — 시작할 때 영속 도메인을 지워 이전 실행의 장부가 새지 않게 한다.
// 병렬 실행을 위해 테스트마다 서로 다른 고정 이름을 쓴다(같은 이름을 두 테스트가 공유하면 M8 장부가 섞인다).

private let stubUserID = "00000000-0000-0000-0000-000000000002"
/// 팀 픽스처의 근무중 행(0002)이 '내 행'이 되지 않게 하는 별도 계정 — 팀 상태 반영이 내 세션을 흡수해
/// 요청 수를 흔드는 것을 막는다(이 파일이 세는 것은 요청이지 흡수 동작이 아니다).
private let teammateUserID = "00000000-0000-0000-0000-000000000003"

private func fixedDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 스캔이 절대 일어나지 않는 토큰 스토어(빈 임시 홈) — setMenuPresented(true) 가 실홈 스캔을 켜지 않게 한다.
@MainActor
private func inertTokenStore(suiteName: String) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: fixedDefaults(suiteName + ".token"),
        homeDirectory: tmp.appendingPathComponent("check-v0238-token-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0238-token-cache-\(suiteName).json", isDirectory: false)
    )
}

/// 스텁 네트워크에 물린 로그인·소속 확정 상태의 스토어(로그인 흐름은 건너뛴다 — 기존 스위트 규약).
@MainActor
private func makeStore(
    host: String,
    suiteName: String,
    userID: String = stubUserID,
    urlSession: URLSession = URLSession(configuration: .stubbed)
) -> (WorkTimerStore, UserDefaults) {
    let defaults = fixedDefaults(suiteName)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: urlSession
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil,
        tokenUsage: inertTokenStore(suiteName: suiteName)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    return (store, defaults)
}

@MainActor
private func cancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

private func requestCount(host: String, path: String, method: String? = nil) -> Int {
    URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == path && (method == nil || $0.httpMethod == method)
    }.count
}

private let leaderboardPath = "/rest/v1/rpc/team_weekly_leaderboard"
private let tokenBoardPath = "/rest/v1/rpc/token_usage_board"
private let pokeDirectoryPath = "/rest/v1/rpc/app_user_directory"
private let workStatusesPath = "/rest/v1/work_statuses"
private let legacyTokenPath = "/rest/v1/token_usage_monthly"

private func panelRequestCounts(host: String) -> (leaderboard: Int, tokenBoard: Int, directory: Int) {
    (
        requestCount(host: host, path: leaderboardPath),
        requestCount(host: host, path: tokenBoardPath),
        requestCount(host: host, path: pokeDirectoryPath)
    )
}

/// 30초 refresh 루프 본문 중 패널 3줄(WorkTimerStore.startStatusRefreshLoop 의 호출 순서 그대로).
/// 루프 자체는 소유 밖 파일이라 본문을 그대로 재현한다 — 루프 배선은 아래 `refreshLoopBodySkipsPanelsWhileClosed` 가 실물로 확인한다.
@MainActor
private func runPanelRefreshSlice(_ store: WorkTimerStore) async {
    await store.refreshLeaderboardIfVisible()
    await store.refreshTokenBoardIfVisible()
    await store.refreshPokeDirectoryIfVisible()
}

/// 조건이 참이 될 때까지 기다린다. **메인 액터에서, 벽시계가 아니라 재개 횟수로** 상한을 둔다 — 전체 스위트가 병렬로
/// 돌 때 다른 테스트(ImageRenderer 마운트 등)가 메인 스레드를 수십 초씩 잡는데, 관찰 대상(refresh 루프·load* Task)이
/// 전부 메인 액터다. 대기가 글로벌 풀에서 돌면 굶주림 구간에 예산만 다 태우고 0건을 '실패'로 오판한다(전체 스위트 실측 2회).
/// 메인 액터에서 재개 횟수로 세면 굶주린 만큼 관찰 대상과 함께 늦춰진다.
@MainActor
private func waitUntil(maxResumes: Int = 3_000, _ condition: () -> Bool) async {
    for _ in 0..<maxResumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - [Q7] 닫힌 팝오버는 마지막으로 본 패널을 두드리지 않는다

/// 패널 가시 플래그가 전부 true 여도 팝오버가 닫혀 있으면 30초 1주기에 세 패널 요청이 0건이고, 열려 있으면 각 1건이다.
/// 뮤테이션: refresh*IfVisible 의 `isMenuPresented` 가드를 지우면 닫힘 구간이 3건이 되어 빨강.
@MainActor
@Test
func closedPopoverDoesNotPollTheLastVisiblePanels() async {
    let host = "v0238-closed-panels"
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-closed-panels", userID: teammateUserID)
    defer { cancelTasks(store) }

    // 사용자가 리그/토큰 보드/콕찌르기 패널을 보다가 팝오버를 닫은 상태. 플래그는 '마지막으로 본 패널' 복원용이라
    // 닫혀도 내려가지 않는다 — 그래서 이 플래그만으로는 서버를 두드릴 이유가 되지 않는다.
    store.isMenuPresented = false
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true

    await runPanelRefreshSlice(store)
    let closed = panelRequestCounts(host: host)
    #expect(closed.leaderboard == 0, "닫힌 팝오버가 리그 RPC 를 두드렸다")
    #expect(closed.tokenBoard == 0, "닫힌 팝오버가 토큰 보드 RPC 를 두드렸다")
    #expect(closed.directory == 0, "닫힌 팝오버가 app_user_directory(6.4KB/37행)를 두드렸다")

    // 대조군: 열려 있으면 같은 1주기에 각 1건 — 가드가 '항상 막기'가 아니라 '닫힘만 막기'라는 증거.
    store.isMenuPresented = true
    await runPanelRefreshSlice(store)
    let open = panelRequestCounts(host: host)
    #expect(open.leaderboard == 1)
    #expect(open.tokenBoard == 1)
    #expect(open.directory == 1)
}

/// 실물 refresh 루프로 같은 계약을 본다: 닫힌 채 두 주기가 돌아(work_statuses 2건) 패널 요청은 0건이다.
/// 루프(WorkTimerStore.swift)는 소유 밖이라 고치지 않았다 — 게이트가 소유 파일의 함수 안에 있어도 배선이 통하는지 확인한다.
@MainActor
@Test
func refreshLoopBodySkipsPanelsWhileClosed() async {
    let host = "v0238-loop-closed-panels"
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-loop-closed", userID: teammateUserID)
    defer { cancelTasks(store) }
    store.isMenuPresented = false
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true
    // 유휴(비근무·닫힘) 주기는 슬라이스 10개라 0.05s × 10 = 0.5s 마다 본문이 돈다.
    store.refreshLoopSliceSeconds = 0.05

    store.startStatusRefreshLoop()
    // 본문은 순차라 work_statuses 가 2건이면 첫 본문의 패널 3줄은 이미 지나갔다.
    await waitUntil { requestCount(host: host, path: workStatusesPath, method: "GET") >= 2 }
    #expect(requestCount(host: host, path: workStatusesPath, method: "GET") >= 2, "루프 본문이 돌지 않았다(전제 붕괴)")

    let counts = panelRequestCounts(host: host)
    #expect(counts.leaderboard == 0)
    #expect(counts.tokenBoard == 0)
    #expect(counts.directory == 0)
}

/// 다시 열리는 순간의 1회 갱신은 기존 경로(setMenuPresented → load*)가 그대로 맡는다 — 닫힘 가드가 이 경로를
/// 막지 않는다(막으면 사용자는 닫기 전 화면을 낡은 채로 보게 된다).
@MainActor
@Test
func reopeningThePopoverKicksTheVisiblePanelExactlyOnce() async {
    let host = "v0238-reopen-kick"
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-reopen-kick", userID: teammateUserID)
    defer { cancelTasks(store) }
    store.isMenuPresented = false
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true

    store.setMenuPresented(true)
    await waitUntil {
        let c = panelRequestCounts(host: host)
        return c.leaderboard >= 1 && c.tokenBoard >= 1 && c.directory >= 1
    }
    // 뒤따르는 중복 킥이 없는지 잠깐 더 본다.
    try? await Task.sleep(for: .milliseconds(150))
    let counts = panelRequestCounts(host: host)
    #expect(counts.leaderboard == 1)
    #expect(counts.tokenBoard == 1)
    #expect(counts.directory == 1)
}

// MARK: - [Q8] 구독 중 take_pokes 폴링 60초, 그 외 15초

/// 주기 판정: 구독 중에만 60초. 킬스위치(전송자 없음 = `.idle(.disabled)`)·연결 중·재연결·실패·비근무는 15초.
/// 뮤테이션: pokePollIntervalSecondsNow 의 분기를 지우고 15 를 돌려주면 구독 단언이 빨강.
@MainActor
@Test
func pokePollIntervalIsSixtySecondsOnlyWhileTheRingIsSubscribed() {
    let (store, _) = makeStore(host: "v0238-poke-interval", suiteName: "check-v0238-network-poke-interval")
    defer { cancelTasks(store) }
    let now = Date()

    #expect(WorkTimerStore.pokePollIntervalSeconds == 15)
    #expect(WorkTimerStore.pokePollIntervalSecondsWhileSubscribed == 60)

    // 킬스위치/전송자 없음 — 출시 기본값. 이 앱은 v0.2.37 과 똑같이 15초다.
    #expect(store.realtimeState == .idle(.disabled))
    #expect(store.pokePollIntervalSecondsNow == 15)

    store.realtimeState = .subscribed(since: now, lastHeardAt: now)
    #expect(store.pokePollIntervalSecondsNow == 60, "구독 중 폴링은 안전망일 뿐이라 60초로 늦춘다(사장님 결정 Q8)")

    // 미구독의 모든 모양은 15초다 — 소켓이 없거나 흔들리는 동안 폴링이 유일한 전달 경로다.
    store.realtimeState = .connecting(attempt: 1, since: now)
    #expect(store.pokePollIntervalSecondsNow == 15)
    store.realtimeState = .reconnecting(Backoff(attempt: 1, retryAt: now, failingSince: now))
    #expect(store.pokePollIntervalSecondsNow == 15)
    store.realtimeState = .failed(Backoff(attempt: 3, retryAt: now, failingSince: now), .exhausted)
    #expect(store.pokePollIntervalSecondsNow == 15)
    store.realtimeState = .idle(.notWorking)
    #expect(store.pokePollIntervalSecondsNow == 15)
    store.realtimeState = .idle(.signedOut)
    #expect(store.pokePollIntervalSecondsNow == 15)

    // 억제 판정은 이번 릴리스에서도 손대지 않았다(상수 뒤에 그대로) — 주기만 바뀐다.
    store.realtimeState = .subscribed(since: now, lastHeardAt: now)
    #expect(store.pollingIsPausedByRealtime == false)
}

/// 루프가 **매 반복 앞에서** 주기를 다시 읽는다(전이는 다음 tick 부터). 주기 상수는 static 이라 실시간으로 잴 수 없어
/// 소스로 못 박는다(주석은 걷어내고 본다). 아울러 구독 신호 읽기는 단일 지점(realtimeRingIsSubscribed) 하나에서
/// 억제와 주기 둘로 갈라진다 — 같은 신호를 두 곳에서 따로 읽으면 한쪽만 고쳐진 날 반쪽 침묵이 된다.
@Test
func pokePollLoopReadsTheIntervalEveryIterationFromTheSingleRingSignal() throws {
    let code = strippingComments(
        try String(contentsOf: sourceURL("WorkTimerStorePoke.swift"), encoding: .utf8)
    )
    let collapsed = code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    #expect(
        collapsed.contains(
            "let interval = self?.pokePollIntervalSecondsNow ?? Self.pokePollIntervalSeconds try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(2))"
        ),
        "폴링 루프가 동적 주기를 읽지 않는다 — 구독 전이가 다음 tick 에 반영되지 않는다"
    )
    #expect(
        collapsed.contains("var pokePollIntervalSecondsNow: Double { realtimeRingIsSubscribed ? Self.pokePollIntervalSecondsWhileSubscribed : Self.pokePollIntervalSeconds }")
    )
    // 원신호 읽기는 한 곳(RealtimeLinkTests 의 계약과 같다), 파생은 선언 1 + 억제 1 + 주기 1 = 3.
    #expect(code.components(separatedBy: "realtimeState.isSubscribed").count - 1 == 1)
    #expect(code.components(separatedBy: "realtimeRingIsSubscribed").count - 1 == 3)
}

// MARK: - [Q9] 폴링 세션 캐시 끔 + select 축소

/// 폴링 세션 구성: URLCache 없음 + 로컬 캐시 무시. 기본 생성자의 서비스가 정확히 이 세션을 쓴다.
/// 아바타 이미지는 이 세션이 아니라 URLSession.shared 로 받는다(디스크 캐시 의존) — 그 배선이 그대로인지도 본다.
@Test
func pollingSessionDoesNotWriteResponsesToURLCache() async throws {
    let configuration = SupabaseWorkService.defaultSession.configuration
    #expect(configuration.urlCache == nil, "폴링 응답이 URLCache(sqlite)에 매번 쓰인다")
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    // 타임아웃 규약은 그대로다(30초 폴링·90초 신선도와 정합).
    #expect(configuration.timeoutIntervalForRequest == 15)
    #expect(configuration.timeoutIntervalForResource == 30)

    let service = SupabaseWorkService(projectURL: URL(string: "http://v0238-default-session")!, anonKey: "anon-test-key")
    let session = await service.session
    #expect(session === SupabaseWorkService.defaultSession)

    let avatar = try String(contentsOf: sourceURL("CheckAvatarView.swift"), encoding: .utf8)
    #expect(avatar.contains("URLSession.shared.data(from: url)"), "아바타 로더가 공유 세션(디스크 캐시)에서 떨어졌다")
}

/// work_statuses select 에 email 이 없고(개인정보를 37행 × 30초로 실어 나르던 것), weekly select 는
/// `user_id,started_at,ended_at` 세 컬럼뿐이다. 활성 세션 조회는 그대로다(이번 범위 밖).
@Test
func teamStatusSelectsDropEmailAndWeeklyExtras() async throws {
    let host = "v0238-select-diet"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    _ = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

    let statusRequest = try #require(URLProtocolStub.requests(forHost: host).first { $0.url?.path == workStatusesPath })
    let statusQuery = try #require(statusRequest.url?.query)
    #expect(!statusQuery.contains("email"), "work_statuses 가 여전히 email 을 요청한다: \(statusQuery)")
    let statusItems = try #require(URLComponents(url: statusRequest.url!, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(statusItems.contains(URLQueryItem(
        name: "select", value: "user_id,status,updated_at,last_seen_at,active_session_id,profiles(display_name,avatar_url)"
    )))

    let weeklyRequest = try #require(URLProtocolStub.requests(forHost: host).first {
        $0.url?.path == "/rest/v1/work_sessions" && $0.url?.query?.contains("ended_at=not.is.null") == true
    })
    let weeklyItems = try #require(URLComponents(url: weeklyRequest.url!, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(weeklyItems.contains(URLQueryItem(name: "select", value: "user_id,started_at,ended_at")))
    #expect(!weeklyItems.contains { $0.name == "select" && $0.value?.contains("duration_seconds") == true })

    let activeRequest = try #require(URLProtocolStub.requests(forHost: host).first {
        $0.url?.path == "/rest/v1/work_sessions" && $0.url?.query?.contains("ended_at=is.null") == true
    })
    let activeItems = try #require(URLComponents(url: activeRequest.url!, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(activeItems.contains(URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds")))
}

/// 서버가 email 을 안 주는 응답(= 새 select 의 실제 모양)을 그대로 디코드하고, 이름 폴백은 '팀원' 하나다.
/// 옛 서버가 email 을 끼워 보내도 깨지지 않는다(Optional 유지).
@Test
func profileRowDecodesWithoutEmailAndFallsBackToTeamMemberName() async throws {
    let host = "v0238-scripted-profiles"
    V0238ScriptedURLProtocol.set(
        path: workStatusesPath,
        json: """
        [
          {"user_id": "u1", "status": "working", "updated_at": "2026-08-31T01:00:00Z", "last_seen_at": null,
           "active_session_id": null, "profiles": {"display_name": "영식", "avatar_url": null}},
          {"user_id": "u2", "status": "off_work", "updated_at": null, "last_seen_at": null,
           "active_session_id": null, "profiles": null},
          {"user_id": "u3", "status": "off_work", "updated_at": null, "last_seen_at": null,
           "active_session_id": null, "profiles": {"display_name": "옛서버", "email": "legacy@example.com", "avatar_url": null}}
        ]
        """,
        forHost: host
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0238ScriptedURLProtocol.session()
    )
    let members = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)
    #expect(members.map(\.id) == ["u1", "u2", "u3"])
    #expect(members.map(\.name) == ["영식", "팀원", "옛서버"])

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let bare = try decoder.decode(ProfileRow.self, from: Data(#"{"display_name":"영식","avatar_url":null}"#.utf8))
    #expect(bare.email == nil)
}

// MARK: - [Q10] 팝오버 재오픈 fast path 의 팀 상태 15초 스로틀

/// 마지막 팀 상태 수신이 15초 안이면 재오픈이 팀 상태 GET 을 내지 않고(첫 프레임은 캐시), 16초 뒤 재오픈은 1건 낸다.
/// 뮤테이션: activateStoredSession fast path 의 `guard !teamStatusIsFresh` 를 지우면 14초 단언이 2가 되어 빨강.
@MainActor
@Test
func reopenWithinFifteenSecondsSkipsTeamStatusAndAfterSixteenRefetches() async {
    let host = "v0238-reopen-throttle"
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-reopen-throttle", userID: teammateUserID)
    defer { cancelTasks(store) }
    #expect(WorkTimerStore.teamStatusReopenThrottleSeconds == 15)

    // 실행 킥이 이미 끝난 스토어(fast path 전제). 시계는 주입해 '15초 안/밖'을 벽시계 없이 가른다.
    store.hasActivatedStoredSession = true
    let t0 = Date()
    store.clock = { t0 }
    #expect(store.lastTeamStatusAt == .distantPast)

    // 30초 폴링이 방금 팀 상태를 받아 둔 상태.
    await store.refreshTeamStatus()
    #expect(requestCount(host: host, path: workStatusesPath, method: "GET") == 1)
    #expect(store.lastTeamStatusAt == t0)

    // 14초 뒤 재오픈 → 팀 상태 GET 0건(캐시로 그린다).
    store.clock = { t0.addingTimeInterval(14) }
    await store.activateStoredSession()
    #expect(requestCount(host: host, path: workStatusesPath, method: "GET") == 1, "15초 안 재오픈이 팀 상태 4 GET 을 다시 냈다")

    // 16초 뒤 재오픈 → 1건.
    store.clock = { t0.addingTimeInterval(16) }
    await store.activateStoredSession()
    #expect(requestCount(host: host, path: workStatusesPath, method: "GET") == 2)
    #expect(store.lastTeamStatusAt == t0.addingTimeInterval(16))
}

/// 실패한 수신은 스탬프를 찍지 않는다 — 직전 폴링이 실패했으면 재오픈은 스로틀과 무관하게 다시 받는다.
/// (스로틀의 근거는 '방금 받은 값이 있다'이지 '방금 시도했다'가 아니다.)
@MainActor
@Test
func failedTeamStatusDoesNotArmTheReopenThrottle() async {
    let host = "v0238-reopen-failed"
    // work_statuses 만 500 — 팀 상태 수신이 실패하는 폴링을 재현한다(요청 기록은 같은 프로토콜이 남긴다).
    V0238ScriptedURLProtocol.setStatus(500, path: workStatusesPath, forHost: host)
    let (store, _) = makeStore(
        host: host, suiteName: "check-v0238-network-reopen-failed", userID: teammateUserID,
        urlSession: V0238ScriptedURLProtocol.session()
    )
    defer { cancelTasks(store) }
    store.hasActivatedStoredSession = true
    let t0 = Date()
    store.clock = { t0 }

    await store.refreshTeamStatus()
    #expect(V0238ScriptedURLProtocol.count(path: workStatusesPath, forHost: host) == 1)
    #expect(store.lastTeamStatusAt == .distantPast, "실패한 수신이 스탬프를 찍었다")
    #expect(store.teamStatusIsFresh(now: t0) == false)

    store.clock = { t0.addingTimeInterval(5) }
    await store.activateStoredSession()
    #expect(V0238ScriptedURLProtocol.count(path: workStatusesPath, forHost: host) == 2)
}

/// 측면 표의 주인 확인: 해제된 스토어의 스탬프가 같은 주소를 물려받은 새 스토어에 새지 않는다(테스트 격리 계약).
@MainActor
@Test
func teamStatusStampDoesNotLeakBetweenStores() {
    let (a, _) = makeStore(host: "v0238-stamp-a", suiteName: "check-v0238-network-stamp-a")
    let (b, _) = makeStore(host: "v0238-stamp-b", suiteName: "check-v0238-network-stamp-b")
    defer { cancelTasks(a); cancelTasks(b) }
    let now = Date()
    a.lastTeamStatusAt = now
    #expect(a.lastTeamStatusAt == now)
    #expect(b.lastTeamStatusAt == .distantPast)
    #expect(a.teamStatusIsFresh(now: now.addingTimeInterval(14)))
    #expect(a.teamStatusIsFresh(now: now.addingTimeInterval(15)) == false)
}

/// memberships / my_team_invite_code 는 재오픈마다가 아니라 기존 60초 스로틀(refreshTeamMetaIfStale)로만 나간다.
@MainActor
@Test
func teamMetaReopenStaysBehindTheSixtySecondThrottle() async {
    let host = "v0238-team-meta-throttle"
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-team-meta", userID: teammateUserID)
    defer { cancelTasks(store) }
    #expect(WorkTimerStore.teamMetaRefreshThrottleSeconds == 60)
    let membershipsPath = "/rest/v1/memberships"
    let t0 = Date()

    store.refreshTeamMetaIfStale(now: t0)
    await waitUntil { requestCount(host: host, path: membershipsPath, method: "GET") >= 1 }
    store.refreshTeamMetaIfStale(now: t0.addingTimeInterval(30))
    store.refreshTeamMetaIfStale(now: t0.addingTimeInterval(59))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(requestCount(host: host, path: membershipsPath, method: "GET") == 1)

    store.refreshTeamMetaIfStale(now: t0.addingTimeInterval(61))
    await waitUntil { requestCount(host: host, path: membershipsPath, method: "GET") >= 2 }
    #expect(requestCount(host: host, path: membershipsPath, method: "GET") == 2)
}

// MARK: - [M8] 옛 표 현재값 GET 은 KST 하루 1회

/// 같은 날 두 번의 업로드(값 변경 + 60초 경과)에 옛 표 GET 은 1건이고, 옛 표 POST 는 두 번 다 나간다.
/// 날짜(KST)가 바뀌면 다시 1건 읽는다. 뮤테이션: 장부 조회를 지우면 두 번째 업로드가 GET 을 내어 빨강.
@MainActor
@Test
func legacyTokenTotalGetGoesOutOncePerKstDay() async throws {
    let host = "v0238-legacy-once-a-day"
    let (store, defaults) = makeStore(host: host, suiteName: "check-v0238-network-legacy-once")
    defer { cancelTasks(store) }
    // KST 정오(자정 경계에서 멀다) — 하루 뒤도 같은 시각이라 날짜 경계 판정이 흔들리지 않는다.
    let t0 = try #require(ISO8601DateFormatter().date(from: "2026-08-31T03:00:00Z"))

    func legacyGets() -> Int { requestCount(host: host, path: legacyTokenPath, method: "GET") }
    func legacyPosts() -> Int { requestCount(host: host, path: legacyTokenPath, method: "POST") }

    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 100), now: t0)
    #expect(legacyGets() == 1)
    #expect(legacyPosts() == 1)
    // 장부: 이 계정·이 달·오늘 — 마지막에 내가 쓴 값(100)으로 올라가 있다.
    #expect(defaults.string(forKey: WorkTimerStore.legacyTokenTotalLedgerKey) == "\(stubUserID)|2026-08|2026-08-31|100")

    // 같은 날, 값 변경 + 70초 → 업로드는 나가지만 옛 표 GET 은 나가지 않는다.
    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 200), now: t0.addingTimeInterval(70))
    #expect(legacyGets() == 1, "옛 표 현재값 GET 이 같은 날 두 번 나갔다(분당 1건으로 되돌아간 것)")
    #expect(legacyPosts() == 2)
    #expect(store.legacyTokenTotalKnownToday(userID: stubUserID, month: "2026-08", now: t0.addingTimeInterval(70)) == 200)

    // 내 값이 장부보다 **작아지면**(로그 정정) 옛 표는 건드리지 않는다 — 옛 코드가 서버 행을 읽어 거절하던 것과 같은 결과.
    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 150), now: t0.addingTimeInterval(140))
    #expect(legacyGets() == 1)
    #expect(legacyPosts() == 2)

    // 다음 날(KST) 첫 업로드는 다시 한 번 읽는다.
    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 300), now: t0.addingTimeInterval(86_400))
    #expect(legacyGets() == 2)
    #expect(legacyPosts() == 3)

    // 다른 계정/다른 달의 장부는 없는 것으로 본다(계정 전환·월 경계에서 남의 값과 비교하지 않는다).
    #expect(store.legacyTokenTotalKnownToday(userID: "someone-else", month: "2026-08", now: t0.addingTimeInterval(86_400)) == nil)
    #expect(store.legacyTokenTotalKnownToday(userID: stubUserID, month: "2026-09", now: t0.addingTimeInterval(86_400)) == nil)
}

/// 다른 맥이 올려 둔 더 큰 옛 행(200M)을 읽은 날은 그 값이 장부에 남아, 하루 종일 그보다 작은 내 값으로 덮어쓰지 않는다
/// (GET 없이도 '깎기 금지' 게이트가 유지된다).
@MainActor
@Test
func legacyLedgerKeepsTheBiggerRowOfAnotherMacForTheDay() async throws {
    let host = "legacy-bigger-v0238-ledger"   // 스텁: 옛 행 total 200,000,000
    let (store, _) = makeStore(host: host, suiteName: "check-v0238-network-legacy-bigger")
    defer { cancelTasks(store) }
    let t0 = try #require(ISO8601DateFormatter().date(from: "2026-08-31T03:00:00Z"))

    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 2_000_000), now: t0)
    #expect(requestCount(host: host, path: legacyTokenPath, method: "GET") == 1)
    #expect(requestCount(host: host, path: legacyTokenPath, method: "POST") == 0)
    #expect(store.legacyTokenTotalKnownToday(userID: stubUserID, month: "2026-08", now: t0) == 200_000_000)

    await store.uploadTokenUsageIfNeeded(usage: TokenUsageMonthly(month: "2026-08", claudeInput: 3_000_000), now: t0.addingTimeInterval(70))
    #expect(requestCount(host: host, path: legacyTokenPath, method: "GET") == 1)
    #expect(requestCount(host: host, path: legacyTokenPath, method: "POST") == 0, "장부의 200M 을 무시하고 옛 행을 깎았다")
    // 새 기기별 표 업로드는 두 번 다 정상이다.
    #expect(requestCount(host: host, path: "/rest/v1/token_usage_device_monthly", method: "POST") == 2)
}

// MARK: - 헬퍼 (소스 계약·스크립트 응답)

private func sourceURL(_ name: String, in directory: String = "Sources/check") -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("\(directory)/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func strippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let iterator = Array(source)
    var index = 0
    while index < iterator.count {
        let c = iterator[index]
        let next: Character? = index + 1 < iterator.count ? iterator[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

/// 경로별 JSON 을 그대로 돌려주는 최소 스텁(호스트 격리). 미등록 경로는 빈 배열.
final class V0238ScriptedURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [String: String] = [:]   // "host path" → json
    private nonisolated(unsafe) static var statuses: [String: Int] = [:]       // "host path" → HTTP status
    private nonisolated(unsafe) static var counts: [String: Int] = [:]         // "host path" → 요청 수

    static func set(path: String, json: String, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        responses["\(host) \(path)"] = json
    }

    static func setStatus(_ status: Int, path: String, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        statuses["\(host) \(path)"] = status
    }

    static func count(path: String, forHost host: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts["\(host) \(path)", default: 0]
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V0238ScriptedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = "\(request.url?.host ?? "") \(request.url?.path ?? "")"
        Self.lock.lock()
        let json = Self.responses[key] ?? "[]"
        let status = Self.statuses[key] ?? 200
        Self.counts[key, default: 0] += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
