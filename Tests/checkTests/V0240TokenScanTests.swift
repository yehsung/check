import AppKit
import Foundation
import Testing
@testable import check

// MARK: - v0.2.40: 토큰 스캔·업로드를 팝오버에서 떼어 근무 게이트로 옮긴 것의 회귀 그물
//
// 2026-09-02 프로덕션 결함. 토큰 사용량이 팝오버에 **이중으로** 묶여 있었다:
//   ① 스캔은 CheckMenuView 의 `.task { tokenUsage.runRefreshLoop() }` 에서만 킥됐다(TokenUsageStore.init 은 스캔을 안 켠다).
//   ② 업로드도 폴링 루프의 `if isMenuPresented { uploadTokenUsageIfNeeded() }` 뒤에 있었다.
// 그래서 메뉴바를 한 번도 안 여는 사람은 Claude/Codex 를 아무리 써도 서버에 0 으로 남았다. 월이 바뀌면 더 나빴다 —
// TokenUsageStore.init 의 스냅샷 복원이 `restored.month == 현재월` 에만 걸려 currentMonthUsage 가 nil 이 되고,
// 업로더의 `guard let usage, usage.total > 0` 이 그 nil 을 걸러 **그 달 내내 한 건도** 안 올라갔다.
// 실측: 활동 중인데 9월 행이 없는 사람 8명(8월에 1.6B·2.7B·3.2B 쓴 헤비 유저 포함), 한 명은 8월 17일 값에 2주째 얼어붙어 있었다.
//
// 이 파일이 지키는 것은 셋이다.
//   (a) 배경 스캔 게이트 — 팝오버가 닫혀 있어도 **근무 중이면** 스캔+업로드가 돈다. 그 밖(비근무·로그아웃·수집 거부)에는 안 돈다.
//   (b) 주기 — 평시 600초, 롤오버 60초. 롤오버가 계속 참이어도 60초 하한이 살아 있어야 매 틱 전량 순회가 되지 않는다.
//   (c) 하트비트 — 업로드가 총합 0 으로 침묵해도 "스캔이 돌았다"는 사실만은 나간다. 그 본문에 토큰 컬럼이 섞이면
//       PostgREST upsert 가 그 기기의 이번 달 누적치를 0 으로 민다(이 기능에서 가장 위험한 자리).
//
// 이 파일의 모든 테스트는 임시 홈의 픽스처만 읽는다(~/.claude·~/.codex 실데이터 금지) — 토큰 스토어를 반드시 주입한다.

// MARK: - 시각 상수

/// 스캔/판정 기준 시각. KST 2026-09-02 12:00 → 월 "2026-09". 자정 경계에서 멀어 ±600초를 흔들어도 날짜가 안 바뀐다.
private let v0240Sep = v0240UTC("2026-09-02T03:00:00Z")
/// **지난달** 기준 시각. KST 2026-08-20 12:00 → 월 "2026-08".
/// 토큰 스토어 시계를 여기에 묶고 폴링 `now` 를 9월에 두면, 스캔이 끝난 뒤에도 롤오버 판정이 참으로 남는다
/// (= KST 월초 자정 직후 실제로 열리는 창). 60초 하한이 없으면 그 상태에서 매 30초 틱마다 전량 순회가 돈다.
private let v0240Aug = v0240UTC("2026-08-20T03:00:00Z")

private func v0240UTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func v0240ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

// MARK: - 시계 상자

/// 테스트가 손으로 옮기는 시계. 스캐너 스로틀(minRefreshInterval 3초)을 열고 닫는 데 쓴다.
/// (@MainActor 스토어에서만 읽히므로 경합 없음 — 이 저장소의 V0238Clock 과 같은 관용구.)
private final class V0240Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 읽을 때마다 한 칸씩 앞으로 가는 시계 + 읽은 값 장부.
/// 쓰임: "관측값이 스캔 **시작**이 아니라 **완주** 시점에 찍히는가"를 결정적으로 가른다 — 시작과 끝이 같은 값을 주는
/// 고정 시계로는 그 둘을 절대 구분할 수 없다(스캔 중간을 노리는 경합 관측은 플레이키다).
private final class V0240SteppingClock {
    private(set) var now: Date
    private(set) var log: [Date] = []
    private let step: TimeInterval
    init(_ now: Date, step: TimeInterval = 1) {
        self.now = now
        self.step = step
    }
    func read() -> Date {
        let value = now
        log.append(value)
        now = now.addingTimeInterval(step)
        return value
    }
    func clearLog() { log.removeAll() }
}

// MARK: - 픽스처 (임시 홈)

private func v0240TempDir(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0240-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

private func v0240Write(_ contents: String, to url: URL, modified: Date) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func v0240ClaudeUsageLine(id: String, at date: Date) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(v0240ISO(date))\",\"requestId\":\"req_\(id)\","
        + "\"message\":{\"id\":\"msg_\(id)\",\"usage\":{\"input_tokens\":100,\"output_tokens\":50,"
        + "\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}}}"
}

private func v0240ClaudeUserLine(at date: Date) -> String {
    "{\"type\":\"user\",\"timestamp\":\"\(v0240ISO(date))\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}"
}

private func v0240CodexLine(at date: Date) -> String {
    "{\"timestamp\":\"\(v0240ISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"total_token_usage\":{\"input_tokens\":900,\"cached_input_tokens\":0,"
        + "\"output_tokens\":100,\"total_tokens\":0}}}}"
}

/// 이 파일의 픽스처가 stat 되는 파일 수(claude 2 + codex 1). lastScanFileCount 오라클.
private let v0240FixtureFileCount = 3

/// 파일 3개를 심고 **총합 > 0** 을 만든다(업로드까지 도는 경로용). 라인 시각·mtime 모두 `at` 의 KST 월 안에 둔다 —
/// 스캐너의 프리필터가 mtime 으로 자르고 합계가 월 창으로 잘리기 때문이다.
private func v0240WriteBusyFixture(into home: URL, at date: Date) {
    let t = date.addingTimeInterval(-3_600)
    v0240Write(v0240ClaudeUsageLine(id: "a", at: t) + "\n",
               to: home.appendingPathComponent(".claude/projects/proj-a/a.jsonl"), modified: date)
    v0240Write(v0240ClaudeUsageLine(id: "b", at: t) + "\n",
               to: home.appendingPathComponent(".claude/projects/proj-b/b.jsonl"), modified: date)
    v0240Write(v0240CodexLine(at: t) + "\n",
               to: home.appendingPathComponent(".codex/sessions/2026/rollout-2026-01-01T00-00-00-aaaa.jsonl"),
               modified: date)
}

/// 파일 3개를 심되 **총합은 0** 이 되게 한다(= "AI CLI 를 켜 두긴 했는데 이번 달에 안 썼다").
/// claude 는 usage 없는 user 라인만, codex 는 유효 이벤트 하나(첫 관측은 기준선일 뿐 델타를 만들지 않는다).
/// 이 픽스처가 필요한 이유: 하트비트 단언을 총합 0 경로에서 재야 하고(업로드는 침묵), 그러면서도 scan_files 가
/// 0 이 아니어야 "0 == 0" 으로 우연히 통과하는 단언이 안 생긴다.
private func v0240WriteQuietFixture(into home: URL, at date: Date) {
    let t = date.addingTimeInterval(-3_600)
    v0240Write(v0240ClaudeUserLine(at: t) + "\n",
               to: home.appendingPathComponent(".claude/projects/proj-a/a.jsonl"), modified: date)
    v0240Write(v0240ClaudeUserLine(at: t) + "\n",
               to: home.appendingPathComponent(".claude/projects/proj-b/b.jsonl"), modified: date)
    v0240Write(v0240CodexLine(at: t) + "\n",
               to: home.appendingPathComponent(".codex/sessions/2026/rollout-2026-01-01T00-00-00-aaaa.jsonl"),
               modified: date)
}

private func v0240Defaults() -> UserDefaults {
    let name = "check-v0240-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - 조립

/// 팀 픽스처의 근무중 행(0002)이 '내 행'이 되지 않게 하는 계정 — 팀 상태 반영이 내 세션을 흡수해 요청 수를 흔들지 않게.
private let v0240UserID = "00000000-0000-0000-0000-000000000003"

/// 격리 토큰 스토어. 홈·캐시·defaults·알림센터를 전부 임시로 준다(실홈 스캔 금지 + 러너 .standard 오염 금지).
@MainActor
private func v0240TokenStore(home: URL, clock: @escaping () -> Date, snapshot: TokenUsageMonthly? = nil) -> TokenUsageStore {
    let defaults = v0240Defaults()
    if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: home,
        cacheURL: v0240TempDir("cache").appendingPathComponent("cache.json", isDirectory: false),
        clock: clock,
        notificationCenter: NotificationCenter()
    )
}

/// 스텁 네트워크에 물린 로그인·소속 확정 상태의 스토어. **팝오버는 닫혀 있다** — 이 파일이 재는 상태가 그것이다.
@MainActor
private func v0240Store(host: String, tokenUsage: TokenUsageStore) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: v0240Defaults(),
        workspaceNotifications: nil,
        tokenUsage: tokenUsage
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: v0240UserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    return store
}

@MainActor
private func v0240BeginWork(_ store: WorkTimerStore, at date: Date) {
    store.startedAt = date
    store.currentSessionID = "aaaaaaaa-0000-0000-0000-0000000000f0"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
}

@MainActor
private func v0240CancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

private let v0240DevicePath = "/rest/v1/token_usage_device_monthly"
private let v0240LegacyPath = "/rest/v1/token_usage_monthly"

private func v0240Count(host: String, path: String, method: String? = nil) -> Int {
    URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == path && (method == nil || $0.httpMethod == method)
    }.count
}

/// 해당 호스트로 나간 (요청, 본문) 쌍. 같은 경로에 업로드와 하트비트가 같이 가므로 본문으로 갈라 봐야 한다.
private func v0240Exchanges(host: String, path: String, method: String) -> [(request: URLRequest, body: String)] {
    zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == path && $0.0.httpMethod == method }
        .map { (request: $0.0, body: $0.1) }
}

// MARK: - (a) 배경 스캔 게이트 — 이번 수정의 전부

/// 팝오버가 닫혀 있어도 근무 중이면 스캔이 돌고, 그 결과가 서버까지 간다.
/// 이 하나가 빨강이면 v0.2.39 이전 상태다 — 메뉴바를 안 여는 사람의 사용량이 서버에서 영원히 0 이다.
/// 뮤테이션: WorkTimerStore 폴링 루프의 `else { refreshTokenUsageInBackgroundIfDue() }` 를 지우거나
///           refreshTokenUsageInBackgroundIfDue 를 no-op 으로 만들면 빨강.
@MainActor
@Test
func backgroundTokenScanRunsWhileWorkingEvenWithThePopoverClosed() async throws {
    let host = "v0240-bg-working"
    let home = v0240TempDir("bg-working-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))

    #expect(store.isMenuPresented == false, "이 테스트의 전제는 '팝오버가 닫혀 있다'다")
    #expect(tokenUsage.scanCount == 0, "init 은 스캔을 킥하지 않는다(전제)")

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)

    // 1) 스캔이 실제로 돌았다(뷰 루프 없이).
    #expect(tokenUsage.scanCount == 1)
    #expect(tokenUsage.lastScanFileCount == v0240FixtureFileCount)
    #expect(tokenUsage.lastScanAt == v0240Sep)
    #expect((tokenUsage.currentMonthUsage?.total ?? 0) > 0, "픽스처가 총합을 만들지 못했다(전제 붕괴)")

    // 2) 그 값이 서버까지 갔다 — 스캔만 돌고 업로드가 안 나가면 결함은 그대로다.
    #expect(store.lastUploadedUsage == tokenUsage.currentMonthUsage)
    #expect(v0240Count(host: host, path: v0240LegacyPath, method: "POST") == 1)
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 2, "사용량 upsert 1 + 하트비트 1")

    // 3) 스캔 사실(하트비트)까지 남았다.
    #expect(store.lastTokenScanHeartbeatAt == tokenUsage.lastScanAt)
    // 4) 다음 주기 판정 기준이 되는 스탬프도 찍혔다.
    #expect(store.lastBackgroundTokenScanAt == v0240Sep)
}

/// 비근무면 안 돈다. 쉬는 동안 1,600 파일 stat 순회를 돌리는 것은 v0.2.38 이 걷어낸 바로 그 비용이고,
/// 앱 시작부터 스캔이 돌지 않게 하던 옛 `isMenuPresented` 게이트의 의도를 `startedAt != nil` 이 승계한다.
@MainActor
@Test
func backgroundTokenScanStaysSilentWhenNotWorking() async {
    let host = "v0240-bg-idle"
    let home = v0240TempDir("bg-idle-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    #expect(store.startedAt == nil)

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)

    #expect(tokenUsage.scanCount == 0, "비근무인데 전량 파일 순회가 돌았다")
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
    #expect(store.lastBackgroundTokenScanAt == .distantPast, "가드 앞에서 스탬프가 찍혔다(다음 근무 시작이 10분 미뤄진다)")
}

/// 로그아웃이면 안 돈다(보낼 곳도 없고 읽을 이유도 없다).
@MainActor
@Test
func backgroundTokenScanStaysSilentWhenSignedOut() async {
    let host = "v0240-bg-signed-out"
    let home = v0240TempDir("bg-signed-out-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))
    store.session = nil

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)

    #expect(tokenUsage.scanCount == 0)
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

/// 수집 거부(profiles.token_usage_collect=false)면 **스캔조차** 안 돈다 — 프라이버시 규약.
/// 서버 트리거가 어차피 버리므로 결과는 같지만, 거부한 사람 맥에서 로그 파일을 읽을 이유가 애초에 없다.
@MainActor
@Test
func backgroundTokenScanStaysSilentWhenCollectionIsOff() async {
    let host = "v0240-bg-collect-off"
    let home = v0240TempDir("bg-collect-off-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))
    store.tokenUsageCollect = false

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)

    #expect(tokenUsage.scanCount == 0, "수집 거부자 맥에서 로그 파일을 읽었다")
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

/// 조건이 참이 될 때까지 기다린다. **메인 액터에서, 벽시계가 아니라 재개 횟수로** 상한을 둔다 — 전체 스위트가 병렬로
/// 돌 때 다른 테스트가 메인 스레드를 수십 초씩 잡는데 관찰 대상(refresh 루프)이 메인 액터라, 글로벌 풀에서 벽시계로
/// 기다리면 굶주림 구간에 예산만 태우고 0건을 '실패'로 오판한다(이 저장소가 실제로 겪은 플레이키).
@MainActor
private func v0240WaitUntil(maxResumes: Int = 3_000, _ condition: () -> Bool) async {
    for _ in 0..<maxResumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// 실물 폴링 루프로 같은 계약을 본다 — 위 테스트들은 함수를 직접 부르므로, 루프에 **배선이 실제로 걸려 있는지**는
/// 여기서만 드러난다(소유 밖 파일인 WorkTimerStore.swift 의 `if isMenuPresented { 업로드 } else { 배경 스캔 }`).
/// 뮤테이션: 그 `else` 가지를 지우면 닫힘 구간이 0회 스캔이 되어 빨강 = 2026-09-02 결함 그대로다.
@MainActor
@Test
func refreshLoopBodyScansInTheBackgroundOnlyWhileWorkingWithThePopoverClosed() async {
    let host = "v0240-loop-wiring"
    let home = v0240TempDir("loop-wiring-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: Date().addingTimeInterval(-3_600))
    // 유휴가 아니라 근무 중이라 루프는 빠른 주기(슬라이스 1회)로 돈다 — 0.05초로 줄여 벽시계 없이 본문을 돌린다.
    store.refreshLoopSliceSeconds = 0.05

    // ① 팝오버가 **열려 있으면** 스캔의 소유자는 뷰 루프(CheckMenuView 의 runRefreshLoop)라 여기서는 업로드만 한다.
    //    뷰가 없는 이 테스트에서는 그래서 스캔이 0회다 — 이 대조군이 아래 ②가 else 가지 덕분임을 증명한다.
    store.isMenuPresented = true
    store.startStatusRefreshLoop()
    await v0240WaitUntil { URLProtocolStub.requests(forHost: host).count >= 2 }
    #expect(URLProtocolStub.requests(forHost: host).isEmpty == false, "루프 본문이 돌지 않았다(전제 붕괴)")
    #expect(tokenUsage.scanCount == 0, "팝오버가 열린 구간에서 폴링 루프가 스캔까지 떠안았다(뷰 루프와 이중 순회)")

    // ② 팝오버를 닫는다. 이제 그 뷰 루프가 없으므로 폴링 루프가 직접 스캔해야 한다.
    store.isMenuPresented = false
    await v0240WaitUntil { tokenUsage.scanCount >= 1 }
    // ★ scanCount 는 스캔이 **시작**할 때 오르고, lastScanFileCount/lastScanAt 은 **완주한 뒤에만** 채워진다
    //   (그 구분이 "안 씀"과 "스캐너 죽음"을 가르는 근거라 일부러 그렇게 만들었다). 그래서 시작 신호로
    //   기다린 뒤 완주 값을 단언하면 그 사이에 끼어 빨개진다 — 실제로 전체 스위트 부하에서 한 번 그랬다.
    //   완주 장벽을 명시적으로 넘고 나서 잰다.
    await tokenUsage.awaitScanCompletion()
    store.refreshTask?.cancel()

    #expect(tokenUsage.scanCount == 1, "닫힌 팝오버 + 근무 중인데 스캔이 돌지 않았다 — 메뉴바를 안 여는 사람의 사용량이 0 으로 남는다")
    #expect(tokenUsage.lastScanFileCount == v0240FixtureFileCount)
    // 스캔 사실이 서버까지 갔다(총합 0 픽스처라 나가는 것은 하트비트 하나뿐이다).
    await v0240WaitUntil { v0240Count(host: host, path: v0240DevicePath, method: "POST") >= 1 }
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1)
}

// MARK: - (b) 주기

/// 평시(이번 달 값을 이미 들고 있음) 주기는 600초다. **양쪽을 다 잰다** — 한쪽만 재면 부등호/상수 뮤턴트가 산다.
/// 599 를 재기 전에 스캐너 스로틀(3초)을 미리 열어 두는 것이 요령이다: 안 그러면 게이트가 잘못 통과해도
/// 스로틀이 대신 막아 주어 뮤턴트가 초록으로 살아남는다.
@MainActor
@Test
func steadyStateBackgroundScanPeriodIsSixHundredSecondsOnBothSides() async {
    let host = "v0240-period-600"
    let home = v0240TempDir("period-600-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    // 스냅샷을 심어 **첫 호출부터** 롤오버가 아니게 만든다(currentMonthUsage 가 nil 이면 60초 주기로 빠진다).
    let tokenUsage = v0240TokenStore(
        home: home, clock: { clock.now },
        snapshot: TokenUsageMonthly(month: "2026-09", claudeInput: 42)
    )
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))
    #expect(tokenUsage.currentMonthUsage?.month == "2026-09", "스냅샷 복원 실패(전제 붕괴)")

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)
    #expect(tokenUsage.scanCount == 1)
    #expect(store.lastBackgroundTokenScanAt == v0240Sep)

    // 599초: 스캐너 스로틀을 열어 둔 채로도 게이트가 막아야 한다.
    clock.now = v0240Sep.addingTimeInterval(599)
    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep.addingTimeInterval(599))
    #expect(tokenUsage.scanCount == 1, "평시 주기가 600초보다 짧다 — 닫힌 팝오버가 전량 순회를 더 자주 돈다")
    #expect(store.lastBackgroundTokenScanAt == v0240Sep, "주기 미달인데 스탬프가 갱신됐다(다음 주기가 밀린다)")

    // 600초: 정확히 경계에서 돈다(`>=` 가 `>` 로 바뀌면 여기가 빨강).
    clock.now = v0240Sep.addingTimeInterval(600)
    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep.addingTimeInterval(600))
    #expect(tokenUsage.scanCount == 2)
    #expect(store.lastBackgroundTokenScanAt == v0240Sep.addingTimeInterval(600))
}

/// 롤오버(이번 달 값이 아직 없다) 주기는 60초다. 서버에 이 달 행이 아예 없는 창을 10분씩 열어 둘 이유가 없다.
/// 여기서도 양쪽(59/60)을 다 재고, 59 를 재기 전에 스캐너 스로틀을 열어 둔다.
@MainActor
@Test
func rolledOverBackgroundScanPeriodIsSixtySecondsOnBothSides() async {
    let host = "v0240-period-60"
    let home = v0240TempDir("period-60-home")
    defer { try? FileManager.default.removeItem(at: home) }
    // 홈은 **지난달** 것이고 스캐너 시계도 지난달이다 → 스캔이 끝나도 currentMonthUsage.month 는 "2026-08" 이라
    // 9월의 폴링 `now` 기준으로 롤오버 판정이 계속 참이다(월초 자정 직후 실제로 열리는 창).
    v0240WriteBusyFixture(into: home, at: v0240Aug)
    let clock = V0240Clock(v0240Aug)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))
    #expect(tokenUsage.currentMonthUsage == nil, "롤오버 전제: 이번 달 값이 없다")

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)
    #expect(tokenUsage.scanCount == 1)
    #expect(tokenUsage.currentMonthUsage?.month == "2026-08", "스캔 뒤에도 롤오버 판정이 참이어야 하는 픽스처다")

    clock.now = v0240Aug.addingTimeInterval(59)
    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep.addingTimeInterval(59))
    #expect(tokenUsage.scanCount == 1, "롤오버 주기가 60초보다 짧다")

    clock.now = v0240Aug.addingTimeInterval(60)
    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep.addingTimeInterval(60))
    #expect(tokenUsage.scanCount == 2, "롤오버인데 60초 경계에서 안 돌았다 — 이 달 행이 계속 없는 상태로 남는다")
}

/// ★ 롤오버 판정이 **스캔 뒤에도 계속 참**인 상태에서 30초 틱을 여러 번 돌려도 스캔은 1회다.
/// 하한이 없으면(rolledOver 일 때 주기를 0 으로 두면) 그 사람 맥에서는 매 30초 틱마다 전량 순회가 돌아,
/// 이 함수가 아끼려던 비용을 정확히 정반대로 쓴다.
@MainActor
@Test
func rolledOverBackgroundScanKeepsTheSixtySecondFloorAcrossRepeatedTicks() async {
    let host = "v0240-rollover-floor"
    let home = v0240TempDir("rollover-floor-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Aug)
    let clock = V0240Clock(v0240Aug)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))

    // 폴링 루프가 실제로 도는 모양(30초 틱)을 60초 창 안에서 두 번 더 돌린다.
    for offset in [0.0, 30.0, 45.0, 59.0] {
        clock.now = v0240Aug.addingTimeInterval(offset)   // 스캐너 스로틀은 열어 둔다(하한을 재는 것이지 스로틀이 아니다)
        await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep.addingTimeInterval(offset))
    }

    #expect(tokenUsage.currentMonthUsage?.month == "2026-08", "롤오버가 계속 참이어야 하는 픽스처다(전제)")
    #expect(tokenUsage.scanCount == 1, "롤오버가 참인 동안 매 틱 전량 순회가 돌았다(60초 하한 소실)")
    #expect(store.lastBackgroundTokenScanAt == v0240Sep)
}

/// 롤오버면 `refreshNow()`(3초 스로틀 무시), 평시면 `refreshIfStale()`(스로틀 적용)이다.
/// 갈라 보는 법: 마지막 스캔에서 3초가 안 지난 상태로 배경 스캔을 부른다 — 스로틀을 타면 안 돌고, 무시하면 돈다.
/// 롤오버에서 스로틀을 타면 그 3초에 걸려 첫 스캔이 미뤄지고, 그러면 그 달 내내 0 으로 남는다(2026-09-02 결함).
@MainActor
@Test
func rolloverScansWithRefreshNowWhileSteadyStateGoesThroughTheStaleThrottle() async {
    // (1) 롤오버: 스로틀 창 안인데도 돈다.
    let rolloverHost = "v0240-refresh-now"
    let rolloverHome = v0240TempDir("refresh-now-home")
    defer { try? FileManager.default.removeItem(at: rolloverHome) }
    v0240WriteBusyFixture(into: rolloverHome, at: v0240Aug)
    let rolloverClock = V0240Clock(v0240Aug)
    let rolloverUsage = v0240TokenStore(home: rolloverHome, clock: { rolloverClock.now })
    let rolloverStore = v0240Store(host: rolloverHost, tokenUsage: rolloverUsage)
    defer { v0240CancelTasks(rolloverStore) }
    v0240BeginWork(rolloverStore, at: v0240Sep.addingTimeInterval(-3_600))

    await rolloverUsage.refreshIfStale()          // 직전 스캔(= 스로틀 창을 연다)
    #expect(rolloverUsage.scanCount == 1)
    await rolloverStore.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)   // 시계는 그대로 = 3초 미만
    #expect(rolloverUsage.scanCount == 2, "롤오버인데 3초 스로틀에 걸렸다 — 그 달 첫 스캔이 미뤄진다")

    // (2) 평시: 같은 조건에서 스로틀을 탄다(연타 방지가 살아 있다).
    let steadyHost = "v0240-refresh-if-stale"
    let steadyHome = v0240TempDir("refresh-if-stale-home")
    defer { try? FileManager.default.removeItem(at: steadyHome) }
    v0240WriteBusyFixture(into: steadyHome, at: v0240Sep)
    let steadyClock = V0240Clock(v0240Sep)
    let steadyUsage = v0240TokenStore(home: steadyHome, clock: { steadyClock.now })
    let steadyStore = v0240Store(host: steadyHost, tokenUsage: steadyUsage)
    defer { v0240CancelTasks(steadyStore) }
    v0240BeginWork(steadyStore, at: v0240Sep.addingTimeInterval(-3_600))

    await steadyUsage.refreshIfStale()
    #expect(steadyUsage.scanCount == 1)
    #expect(steadyUsage.currentMonthUsage?.month == "2026-09", "평시 전제: 이번 달 값을 들고 있다")
    await steadyStore.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)
    #expect(steadyUsage.scanCount == 1, "평시 경로가 refreshNow 를 쓴다 — 스로틀이 무의미해진다")
}

// MARK: - (c) 하트비트

/// 총합 0 이라 업로드가 게이트에서 되돌아가도 하트비트는 나간다.
/// 이게 없으면 서버에서 "Claude/Codex 를 안 쓴 사람"과 "스캐너가 죽은 사람"이 똑같이 '행 없음'으로 보인다 —
/// 2026-09-02 에 8명의 원인을 못 가른 것이 정확히 이 신호가 없어서였다.
@MainActor
@Test
func scanHeartbeatGoesOutEvenWhenTheUploadIsSkippedForZeroTotal() async {
    let host = "v0240-heartbeat-zero"
    let home = v0240TempDir("heartbeat-zero-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }
    v0240BeginWork(store, at: v0240Sep.addingTimeInterval(-3_600))

    await store.refreshTokenUsageInBackgroundIfDue(now: v0240Sep)

    // 전제: 스캔은 돌았고(파일 3개를 봤고) 총합은 0 이다.
    #expect(tokenUsage.scanCount == 1)
    #expect(tokenUsage.lastScanFileCount == v0240FixtureFileCount)
    #expect(tokenUsage.currentMonthUsage?.total == 0)
    // 업로드는 침묵한다(옛 표도 안 건드린다 — 총합 가드가 GET 보다 앞이다).
    #expect(store.lastUploadedUsage == nil)
    #expect(v0240Count(host: host, path: v0240LegacyPath) == 0)
    // 그래도 하트비트는 나갔다.
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1)
    #expect(store.lastTokenScanHeartbeatAt == tokenUsage.lastScanAt)
}

/// 같은 스캔(같은 lastScanAt)은 한 번만 보고하고, 새 스캔이면 다시 보고한다.
@MainActor
@Test
func scanHeartbeatIsSentOncePerScanAndAgainForANewScan() async {
    let host = "v0240-heartbeat-once"
    let home = v0240TempDir("heartbeat-once-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }

    await tokenUsage.refreshIfStale()
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1)
    #expect(store.lastTokenScanHeartbeatAt == v0240Sep)

    // 같은 스캔을 다시 부르면 변경 게이트가 막는다(같은 사실을 두 번 쓰지 않는다).
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep.addingTimeInterval(600))
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1, "같은 스캔이 두 번 보고됐다")

    // 새 스캔이면 다시 나간다 — 안 그러면 '언제 마지막으로 돌았나'가 첫 스캔에서 영영 얼어붙는다.
    clock.now = v0240Sep.addingTimeInterval(600)
    await tokenUsage.refreshIfStale()
    #expect(tokenUsage.lastScanAt == v0240Sep.addingTimeInterval(600))
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep.addingTimeInterval(600))
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 2)
}

/// 전송이 실패하면 도장이 안 찍혀 다음 주기가 같은 스캔을 그대로 다시 보고한다(실패는 조용히 삼킨다).
@MainActor
@Test
func scanHeartbeatFailureLeavesNoStampSoTheNextCycleRetries() async {
    let host = "v0240-hb-fails-retry"   // 스텁: 이 호스트의 token_usage_device_monthly 는 500
    let home = v0240TempDir("heartbeat-retry-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }

    await tokenUsage.refreshIfStale()
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1)
    #expect(store.lastTokenScanHeartbeatAt == nil, "실패에도 도장이 찍혔다 — 이 스캔은 영영 서버에 안 남는다")
    #expect(store.syncMessage != "동기화 실패", "하트비트 실패가 화면 문구를 세웠다(진단 신호일 뿐 기능이 아니다)")

    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep.addingTimeInterval(600))
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 2, "다음 주기가 재시도하지 않았다")
}

/// ★★ 하트비트 본문에 토큰 컬럼이 **하나도** 없다.
/// PostgREST upsert 는 본문에 온 컬럼만 SET 하고 본문에 없는 컬럼은 건드리지 않는다. 하트비트는 총합 0 일 때도
/// 나가므로 토큰 컬럼을 0 으로 실으면 **그 기기의 이번 달 누적치를 통째로 0 으로 민다** — 이 기능에서 가장 위험한 자리다.
/// 그래서 스텁이 받은 실제 JSON 의 **키 집합**을 문자 그대로 못 박는다. 누군가 TokenUsageUpsertRequest 를
/// 재사용하는 순간(그 타입은 토큰 컬럼을 갖고 있다) 여기가 빨강이 된다.
@MainActor
@Test
func scanHeartbeatBodyCarriesExactlyTheFiveContractKeysAndNoTokenColumns() async throws {
    let host = "v0240-heartbeat-body"
    let home = v0240TempDir("heartbeat-body-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }

    await tokenUsage.refreshIfStale()
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)

    let exchanges = v0240Exchanges(host: host, path: v0240DevicePath, method: "POST")
    #expect(exchanges.count == 1)
    let exchange = try #require(exchanges.first)
    let object = try #require(
        try JSONSerialization.jsonObject(with: Data(exchange.body.utf8)) as? [String: Any]
    )

    // 키 집합이 정확히 다섯. 하나라도 더 있으면 그 컬럼이 서버에서 SET 된다.
    #expect(Set(object.keys) == ["user_id", "month", "device_id", "last_scan_at", "scan_files"],
            "하트비트 본문 키: \(object.keys.sorted())")
    // 토큰 컬럼은 이름을 하나하나 되묻는다 — 위 단언이 느슨해지는 날에도 이 목록이 남게.
    for forbidden in [
        "claude_input", "claude_output", "claude_cache_read", "claude_cache_creation",
        "codex_input", "codex_output", "total", "today_total", "today_date"
    ] {
        #expect(object[forbidden] == nil, "하트비트가 \(forbidden) 을 실었다 — 그 기기의 이번 달 누적치가 0 으로 밀린다")
    }

    // 값도 계약대로다.
    #expect(object["user_id"] as? String == v0240UserID)
    #expect(object["month"] as? String == TokenUsageIncrementalScanner.kstMonthString(v0240Sep))
    // 기기 식별자가 사용량 원장의 것과 같아야 한다 — 어긋나면 "스캔은 도는데 값이 없는 기기"가 유령으로 하나 더 보인다.
    #expect(object["device_id"] as? String == store.deviceID)
    #expect(store.deviceID.isEmpty == false)
    #expect(object["scan_files"] as? Int == tokenUsage.lastScanFileCount)
    #expect(tokenUsage.lastScanFileCount == v0240FixtureFileCount, "scan_files 가 0 이면 위 단언이 우연히 통과한다")
    let sentScanAt = try #require(object["last_scan_at"] as? String)
    #expect(ISO8601DateFormatter().date(from: sentScanAt) == tokenUsage.lastScanAt)

    // 경로 규약(행이 없으면 insert, 있으면 이 두 컬럼만 갱신).
    let query = try #require(exchange.request.url?.query)
    #expect(query.contains("on_conflict=user_id,month,device_id")
            || query.contains("on_conflict=user_id%2Cmonth%2Cdevice_id"), "on_conflict 질의: \(query)")
}

/// 하트비트도 짝으로 막힌다: 로그아웃·수집 거부·"이번 실행에서 스캔이 한 번도 안 끝남" 셋 다 요청 0건이다.
/// (배경 스캔이 이미 앞에서 막지만, 이 함수만 따로 불려도 프라이버시 규약이 깨지지 않아야 한다.)
@MainActor
@Test
func scanHeartbeatStaysSilentWhenSignedOutOrOptedOutOrTheScannerNeverRan() async {
    let host = "v0240-heartbeat-gates"
    let home = v0240TempDir("heartbeat-gates-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteQuietFixture(into: home, at: v0240Sep)
    let clock = V0240Clock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.now })
    let store = v0240Store(host: host, tokenUsage: tokenUsage)
    defer { v0240CancelTasks(store) }

    // ① 스캔이 한 번도 안 끝났다 — 보고할 사실이 없다.
    #expect(tokenUsage.lastScanAt == nil)
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath) == 0)

    await tokenUsage.refreshIfStale()

    // ② 수집 거부.
    store.tokenUsageCollect = false
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath) == 0, "수집 거부자의 스캔 사실이 서버로 나갔다")
    store.tokenUsageCollect = true

    // ③ 로그아웃.
    let signedIn = store.session
    store.session = nil
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath) == 0)

    // 대조군: 게이트가 전원의 하트비트를 죽이는 방향으로 잘못 서지 않았다.
    store.session = signedIn
    await store.sendTokenScanHeartbeatIfNeeded(now: v0240Sep)
    #expect(v0240Count(host: host, path: v0240DevicePath, method: "POST") == 1)
}

// MARK: - 관측값

/// lastScanFileCount / lastScanAt 은 스캔이 **완주한 뒤에만** 채워진다.
/// 시작 시점에 찍으면 중간에 죽은 스캔도 "돌았다"로 보여, 서버에서 "안 씀(파일 0)"과 "스캐너 죽음(미갱신)"을
/// 가르는 구분이 통째로 무너진다 — 하트비트의 존재 이유가 사라진다.
///
/// 재는 법: 읽을 때마다 1초씩 나아가는 시계를 준다. 스캔 시작에서 한 번, 완주에서 또 한 번 읽으므로
/// 완주 시각은 반드시 시작 시각보다 크다. 고정 시계로는 두 자리가 같은 값을 내어 구분 자체가 불가능하고,
/// 스캔 중간을 노려 관측하는 방식은 플레이키다.
@MainActor
@Test
func scanObservablesAreFilledOnlyAfterTheScanCompletes() async throws {
    let home = v0240TempDir("observables-home")
    defer { try? FileManager.default.removeItem(at: home) }
    v0240WriteBusyFixture(into: home, at: v0240Sep)
    let clock = V0240SteppingClock(v0240Sep)
    let tokenUsage = v0240TokenStore(home: home, clock: { clock.read() })

    // 스캔 전: 둘 다 비어 있다. lastScanAt == nil 이 "이 프로세스에서 스캔이 한 번도 안 끝났다"의 유일한 표현이다.
    #expect(tokenUsage.lastScanAt == nil)
    #expect(tokenUsage.lastScanFileCount == 0)

    clock.clearLog()
    await tokenUsage.refreshIfStale()

    // 첫 시계 읽기가 startScan 의 것(= 스캔 시작 시각)이다.
    let scanStartedAt = try #require(clock.log.first)
    let scanFinishedAt = try #require(tokenUsage.lastScanAt)
    #expect(scanFinishedAt > scanStartedAt,
            "관측 시각이 스캔 시작 시점에 찍혔다 — 중간에 죽은 스캔도 '돌았다'로 보인다")
    #expect(tokenUsage.lastScanFileCount == v0240FixtureFileCount)
}
