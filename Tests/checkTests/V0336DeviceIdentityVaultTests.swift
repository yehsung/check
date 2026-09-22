import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 2026-09-22: 설정(UserDefaults)이 죽은 맥에서 앱이 한 짓 두 가지
//
// 실제로 일어난 사고: `~/Library/Preferences` 에 테스트가 흘린 도메인 파일이 454,595개 쌓여 CFPrefs 가
// 통째로 죽었다(`defaults read com.apple.finder` 까지 EXIT=1, "Path not accessible" 10시간 1,612,469줄).
// **kingcheck.plist 자체는 13,603바이트로 온전했고 `plutil -lint` OK 였다** — 값은 디스크에 있는데 앱이
// 못 읽은 것이다. 잔재를 안 쌓는 근본 수리는 다른 자리(CheckTestScratch)의 일이고, 여기가 지키는 것은
// "못 읽는 맥에서 앱이 무엇을 하면 안 되는가" 둘이다.
//
//  (A) 유령 기기: resolveDeviceID 가 읽기 실패에 새 UUID 를 만들고 쓰기 실패도 못 알아채, 실행마다 새
//      기기로 토큰 사용량을 올렸다. token_usage_board 는 기기 행을 `group by d.user_id` 로 합산하므로
//      화면이 128.9억 → 258억(2배)이 됐다(서버 실측: 479DA7BE… 12:53 / EF016D4D… 13:08).
//  (B) 조용한 로그아웃: 키체인의 토큰은 멀쩡한데(cdat=20260831104908Z 그대로 = 8/31 이후 한 번도 안
//      지워졌다) userID 가 defaults 에만 있어, 읽기 실패 하나로 세션이 nil 이 되고 "로그인 필요"가 떴다.
//
// 결함을 되살리면 이 파일이 빨개진다(실측: 네 군데를 사고 당시 코드로 되돌리면 6개 중 5개가 빨개지고,
// 정상 맥을 재는 기준선 하나만 초록으로 남는다).
//
// **격리는 CheckTestScratch 로만 한다.** UUID 스위트 + removePersistentDomain 은 이 사고의 원인 그
// 자체다 — 실측으로 확인했다: 도메인을 지우고 plist 파일까지 지워도 cfprefsd 가 자기 메모리 사본을
// 나중에 다시 flush 해 파일이 되살아난다(이 파일의 초안이 그렇게 7개를 되살렸다). 스위트 이름을 절대
// 경로로 주면 plist 가 $TMPDIR 밑에 떨어져 Preferences 로 애초에 새지 않는다.

// MARK: - 픽스처

private let idUserID = "00000000-0000-0000-0000-000000000002"
private let idMonthlyPath = "/rest/v1/token_usage_device_monthly"
private let idLegacyMonthlyPath = "/rest/v1/token_usage_monthly"
private let idNow = Date(timeIntervalSince1970: 1_756_000_000)

/// **쓰기를 삼키는 defaults 대역.** 사고 당시의 CFPrefs 그대로다: `set` 이 아무 일도 하지 않고
/// (앱 로그 `Couldn't write values for keys ("check.deviceID") … Path not accessible`), 그래서
/// 되읽기가 nil 을 돌려준다. 읽기는 격리 스위트 그대로다.
private final class IdSwallowingDefaults: UserDefaults {
    override func set(_ value: Any?, forKey defaultName: String) {}
    override func set(_ value: Int, forKey defaultName: String) {}
    override func set(_ value: Double, forKey defaultName: String) {}
    override func set(_ value: Float, forKey defaultName: String) {}
    override func set(_ value: Bool, forKey defaultName: String) {}
    override func set(_ url: URL?, forKey defaultName: String) {}
    override func setValue(_ value: Any?, forKey key: String) {}
}

/// **디스크 쓰기만 실패하는 defaults 대역.** `set` 은 메모리 캐시에 남아 **되읽기가 성공하지만** 디스크로는
/// 내려가지 않는다 = 다음 실행엔 없다. CFPrefs 는 이렇게도 죽을 수 있어서(사고 로그의 "Path not accessible"
/// 는 디스크 쓰기 실패다) 되읽기 하나로는 부족하다 — `synchronize()` 가 false 를 말하는 그 자리를 못 박는다.
private final class IdUnflushableDefaults: UserDefaults {
    override func synchronize() -> Bool { false }
}

/// **읽기도 쓰기도 죽은 defaults 대역.** 모든 조회가 nil 이다 — 디스크 가득참·plist 파손·CFPrefs 사망처럼
/// 이유가 무엇이든 "설정을 못 읽는 맥"의 최악값이다. 이 대역에서도 세션은 금고만으로 살아나야 한다.
private final class IdBlindDefaults: UserDefaults {
    override func object(forKey defaultName: String) -> Any? { nil }
    override func string(forKey defaultName: String) -> String? { nil }
    override func data(forKey defaultName: String) -> Data? { nil }
    override func set(_ value: Any?, forKey defaultName: String) {}
    override func set(_ value: Int, forKey defaultName: String) {}
    override func set(_ value: Double, forKey defaultName: String) {}
    override func set(_ value: Float, forKey defaultName: String) {}
    override func set(_ value: Bool, forKey defaultName: String) {}
    override func set(_ url: URL?, forKey defaultName: String) {}
    override func setValue(_ value: Any?, forKey key: String) {}
}

/// 대역들도 CheckTestScratch 의 절대 경로 스위트를 쓴다(= Preferences 에 안 샌다).
/// 같은 이름이 재실행마다 재사용되므로 **만들 때 비운다** — 특히 Unflushable 은 쓰기가 실제로 먹혀,
/// 안 비우면 지난 실행이 남긴 기기 ID 를 읽어 "이미 있음" 가지로 빠진다.
private func idDouble<T: UserDefaults>(_ make: (String) -> T?, _ label: String, _ function: String) -> T {
    let path = CheckTestScratch.suitePath(label, function: function)
    let defaults = make(path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

/// 테스트 러너가 **진짜 홈의 Claude/Codex 로그를 읽지 않게** 빈 임시 홈을 준 토큰 스토어.
@MainActor
private func idTokenStore(_ label: String, _ function: String) -> TokenUsageStore {
    let home = CheckTestScratch.directory("home-" + label, function: function)
    return TokenUsageStore(
        defaults: CheckTestScratch.defaults("tokens-" + label, function: function),
        homeDirectory: home,
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false),
        notificationCenter: NotificationCenter(),
        codexHomeResolver: { nil })
}

@MainActor
private func idStore(
    defaults: UserDefaults, vault: TokenVault, host: String, label: String, function: String = #function
) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed))
    return WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        tokenVault: vault,
        workspaceNotifications: nil,
        tokenUsage: idTokenStore(label, function))
}

@MainActor
private func idCancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel(); store.pokePollTask?.cancel()
}

/// 월간 업로드 게이트(총합 > 0)를 통과하는 최소 사용량.
private func idUsage() -> TokenUsageMonthly {
    var usage = TokenUsageMonthly(month: "2026-08")
    usage.windowStart = "2026-08-01"
    usage.claudeInput = 1_000
    return usage
}

@MainActor
private func idUploadStore(
    host: String, deviceID: String, label: String, function: String = #function
) -> WorkTimerStore {
    let defaults = CheckTestScratch.defaults(label, function: function)
    let store = idStore(defaults: defaults, vault: InMemoryTokenVault(), host: host, label: label, function: function)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: idUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    store.tokenUsageCollectLoaded = true
    store.deviceID = deviceID
    return store
}

// MARK: - A. 기기 신원

/// **쓰기가 확인되지 않는 맥에서는 새 기기 ID 를 만들지 않는다.** 되읽어 확인이 안 되면 그 UUID 는 이번
/// 실행에서만 존재하는 유령이고, 그 유령으로 올린 행 하나가 순위표를 두 배로 만든다.
/// 결함을 되살리면(= 확인 가드를 지우면) resolveDeviceID 가 UUID 를 돌려줘 이 테스트가 빨개진다.
@MainActor
@Test
func identityGateWithholdsDeviceIDWhenDefaultsSwallowsTheWrite() {
    let defaults = idDouble(IdSwallowingDefaults.init(suiteName:), "swallow", #function)

    #expect(WorkTimerStore.resolveDeviceID(defaults: defaults) == nil)
    // 두 번 불러도 여전히 없다 — "실행마다 새 ID" 가 정확히 사고의 모양이었다.
    #expect(WorkTimerStore.resolveDeviceID(defaults: defaults) == nil)

    // 이 맥에서 실제로 세워지는 스토어도 신원이 없다고 말한다.
    let store = idStore(
        defaults: defaults, vault: InMemoryTokenVault(), host: "v0336-identity-withheld", label: "swallow")
    defer { idCancelTasks(store) }
    #expect(store.deviceID.isEmpty)
    #expect(store.hasDeviceIdentity == false)

    // 같은 사고의 다른 얼굴: 쓰기가 **메모리 캐시엔 남아 되읽기는 성공**하지만 디스크로 안 내려가는 맥.
    // 되읽기만 보면 "저장됐다"로 읽히지만 다음 실행엔 없다 = 실행마다 새 ID 다. 여기도 신원 없음이어야 한다.
    let unflushable = idDouble(IdUnflushableDefaults.init(suiteName:), "unflushable", #function)
    #expect(unflushable.string(forKey: WorkTimerStore.deviceIDKey) == nil)
    #expect(WorkTimerStore.resolveDeviceID(defaults: unflushable) == nil)
}

/// **정상 맥의 동작은 그대로다**: 없으면 한 번 만들어 저장하고, 다음부터는 그 값을 그대로 돌려준다.
/// (기준선이 위 테스트와 달라야 위 테스트가 "언제나 nil" 로 초록인 가짜가 아님이 선다.)
@MainActor
@Test
func identityGateMintsDeviceIDOnceOnHealthyDefaults() {
    let defaults = CheckTestScratch.defaults("fresh")

    let minted = WorkTimerStore.resolveDeviceID(defaults: defaults)
    #expect(minted != nil)
    #expect(minted?.isEmpty == false)
    #expect(defaults.string(forKey: WorkTimerStore.deviceIDKey) == minted)
    // 두 번째 호출은 새로 만들지 않는다.
    #expect(WorkTimerStore.resolveDeviceID(defaults: defaults) == minted)

    // 이미 값이 있는 맥은 그 값을 그대로 쓴다(덮어쓰지 않는다).
    let seeded = CheckTestScratch.defaults("seeded")
    seeded.set("MAC-EXISTING", forKey: WorkTimerStore.deviceIDKey)
    #expect(WorkTimerStore.resolveDeviceID(defaults: seeded) == "MAC-EXISTING")

    let store = idStore(
        defaults: seeded, vault: InMemoryTokenVault(), host: "v0336-identity-minted", label: "seeded")
    defer { idCancelTasks(store) }
    #expect(store.deviceID == "MAC-EXISTING")
    #expect(store.hasDeviceIdentity)
}

/// **신원 없는 실행은 토큰 사용량을 한 줄도 올리지 않는다.** 새 원장(기기별)도, 옛 표도 나가지 않는다.
/// 게이트를 지우면 첫 단언이 빨개진다.
@MainActor
@Test
func identityGateSkipsTokenUploadWithoutDeviceID() async {
    let blindHost = "v0336-upload-blind-\(UUID().uuidString.lowercased())"
    let blindStore = idUploadStore(host: blindHost, deviceID: "", label: "blind")
    defer { idCancelTasks(blindStore) }

    await blindStore.uploadTokenUsageIfNeeded(usage: idUsage(), account: nil, accountStatus: nil, now: idNow)

    let blindRequests = URLProtocolStub.requests(forHost: blindHost)
    let blindMonthly = blindRequests.filter { $0.url?.path == idMonthlyPath }
    let blindLegacy = blindRequests.filter { $0.url?.path == idLegacyMonthlyPath }
    #expect(blindMonthly.count == 0)
    #expect(blindLegacy.count == 0)
    // 게이트 앞에서 되돌아갔으므로 업로드 장부도 그대로다(다음 실행이 정상이면 즉시 올라간다).
    #expect(blindStore.lastUploadedUsage == nil)

    // 기준선: **같은 픽스처에 신원만 있으면** 그 업로드는 실제로 나간다. 이게 없으면 위 단언은
    // "원래 아무것도 안 나가는 경로" 를 재는 가짜 초록이 된다.
    let liveHost = "v0336-upload-live-\(UUID().uuidString.lowercased())"
    let liveStore = idUploadStore(host: liveHost, deviceID: "MAC-A", label: "live")
    defer { idCancelTasks(liveStore) }

    await liveStore.uploadTokenUsageIfNeeded(usage: idUsage(), account: nil, accountStatus: nil, now: idNow)

    let liveMonthly = URLProtocolStub.requests(forHost: liveHost)
        .filter { $0.url?.path == idMonthlyPath && $0.httpMethod == "POST" }
    #expect(liveMonthly.count >= 1)
    let liveBodies = zip(URLProtocolStub.requests(forHost: liveHost), URLProtocolStub.bodies(forHost: liveHost))
        .filter { $0.0.url?.path == idMonthlyPath && $0.0.httpMethod == "POST" }
        .map(\.1)
    #expect(liveBodies.contains { $0.contains("MAC-A") })
}

// MARK: - B. 세션의 두 조각

/// **defaults 가 전부 nil 을 주는 맥에서도 세션이 살아난다.** 토큰과 userID 가 같은 금고에 있기 때문이다.
/// userID 를 defaults 에서만 읽던 시절로 되돌리면 이 테스트가 "로그인 필요" 로 빨개진다.
@MainActor
@Test
func sessionVaultRestoresSessionWhenDefaultsReadsAreAllNil() {
    let vault = InMemoryTokenVault()
    vault.write("vault-access", key: WorkTimerStore.accessTokenKey)
    vault.write("vault-refresh", key: WorkTimerStore.refreshTokenKey)
    vault.write(idUserID, key: WorkTimerStore.userIDKey)

    // 순수 복원 계약.
    let blind = idDouble(IdBlindDefaults.init(suiteName:), "blind", #function)
    let restored = WorkTimerStore.restoredSession(from: blind, vault: vault)
    #expect(restored?.accessToken == "vault-access")
    #expect(restored?.refreshToken == "vault-refresh")
    #expect(restored?.userID == idUserID)

    // 화면까지: 이 맥은 로그인 화면으로 떨어지지 않는다(사고 당시엔 여기가 "로그인 필요" 였다).
    let store = idStore(defaults: blind, vault: vault, host: "v0336-session-blind", label: "blind")
    defer { idCancelTasks(store) }
    #expect(store.isSignedIn)
    #expect(store.session?.userID == idUserID)
    #expect(store.syncMessage == "동기화됨")
}

/// **기존 사용자 이행**: defaults 에만 userID 가 있던 맥은 복원되면서 금고로 옮겨 적힌다.
/// 이 한 줄이 없으면 이번 수정은 이미 설치된 맥에 다음 사고까지 아무 효과가 없다.
@MainActor
@Test
func sessionVaultMirrorsLegacyDefaultsUserIDIntoVault() {
    let defaults = CheckTestScratch.defaults("legacy")
    let vault = InMemoryTokenVault()
    vault.write("vault-access", key: WorkTimerStore.accessTokenKey)
    defaults.set(idUserID, forKey: WorkTimerStore.userIDKey)
    #expect(vault.read(WorkTimerStore.userIDKey) == nil)

    let store = idStore(defaults: defaults, vault: vault, host: "v0336-session-migrate", label: "legacy")
    defer { idCancelTasks(store) }

    #expect(store.isSignedIn)
    #expect(store.session?.userID == idUserID)
    // 금고로 옮겨 적혔고,
    #expect(vault.read(WorkTimerStore.userIDKey) == idUserID)
    // defaults 사본은 **남는다** — 비밀이 아니고, 소유 계정 판정 등이 계속 읽는다.
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == idUserID)

    // 이행의 값어치: 다음 실행에서 defaults 가 죽어도 그 사용자는 로그아웃되지 않는다.
    let blind = idDouble(IdBlindDefaults.init(suiteName:), "blind", #function)
    let relaunched = idStore(
        defaults: blind, vault: vault, host: "v0336-session-migrate-relaunch", label: "blind")
    defer { idCancelTasks(relaunched) }
    #expect(relaunched.isSignedIn)
    #expect(relaunched.session?.userID == idUserID)
}

/// **로그아웃은 금고의 userID 도 지운다.** 안 지우면 다음 사람이 로그인하기 전 재시작했을 때
/// restoredSession 이 앞사람 신원으로 세션을 세운다.
@MainActor
@Test
func sessionVaultClearsUserIDOnSignOut() {
    let defaults = CheckTestScratch.defaults("signout")
    let vault = InMemoryTokenVault()
    let store = idStore(defaults: defaults, vault: vault, host: "v0336-session-signout", label: "signout")
    let session = SupabaseSession(accessToken: "vault-access", refreshToken: "vault-refresh", userID: idUserID)
    store.session = session
    store.persistSession(session)
    // 저장 시점에 두 자리 다 채워져 있다(persistSession 의 계약).
    #expect(vault.read(WorkTimerStore.userIDKey) == idUserID)
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == idUserID)

    store.signOut()
    idCancelTasks(store)

    #expect(vault.read(WorkTimerStore.userIDKey) == nil)
    #expect(vault.read(WorkTimerStore.accessTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == nil)

    // 재시작해도 앞사람 신원이 남아 있지 않다.
    let relaunched = idStore(
        defaults: defaults, vault: vault, host: "v0336-session-signout-relaunch", label: "relaunch")
    defer { idCancelTasks(relaunched) }
    #expect(!relaunched.isSignedIn)
    #expect(relaunched.session == nil)
}

// MARK: - C. 기기 식별자가 들어가는 나머지 서버 쓰기 네 자리
//
// 2026-09-22 적대 검증이 이 파일의 구멍을 짚었다: 위 A 절이 잡는 게이트는 **월간 업로드 한 곳뿐**이고,
// 나머지 네 자리(스캔 하트비트 · upsertStatusDevice · reportDeviceInput · work_tick 의 p_device_id)를
// 통째로 지워도 412개 테스트가 EXIT=0 이었다. 계약이 없는 게이트는 다음 사람이 지운다.
//
// 가장 나쁜 자리는 work_tick 이다. 유령 ID 를 실으면 서버가 그 ID 로 기기 행을 써서 **진짜 소유 맥이
// 자기 세션을 남의 것으로 보고 물러난다**. 그래서 여기서는 "안 나간다"가 아니라 "나가되 기기 칸만
// 비었다"를 건다 — 틱을 통째로 막으면 근무 기록이 끊긴다(서버 RPC 는 p_device_id 가 null 이면 기기
// 행을 건드리지 않는다: supabase/migrations/20260831120000_work_tick_rpc.sql:131·155).
//
// **모든 단언은 기준선과 짝이다.** 같은 픽스처에 MAC-A 를 넣으면 그 요청이 실제로 나가고 본문에 그
// 값이 있다. 짝이 없으면 "원래 아무것도 안 나가는 경로"를 재는 가짜 초록이 된다(이 저장소에서 실제로
// 나온 실패 모양이다 — comparison-baseline-must-differ).

private let idDevicePath = "/rest/v1/work_status_devices"
private let idStatusPath = "/rest/v1/work_statuses"
private let idTickPath = "/rest/v1/rpc/work_tick"
private let idOwnedSessionID = "a0000000-0000-0000-0000-0000000000f1"

/// 그 호스트로 나간 (요청, 본문) 쌍. work_status_devices 한 경로에 소유 주장과 입력 보고가 **둘 다**
/// 가므로 개수만으로는 무엇이 나갔는지 못 가른다 — 본문까지 들고 와야 한다.
private func idExchanges(host: String, path: String, method: String = "POST") -> [(request: URLRequest, body: String)] {
    zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == path && $0.0.httpMethod == method }
        .map { (request: $0.0, body: $0.1) }
}

/// 호스트 이름은 실행마다 새로 만든다 — URLProtocolStub 의 기록은 **프로세스 전역**이라 고정 이름을
/// 쓰면 다른 테스트(또는 같은 파일의 앞 케이스)가 남긴 요청이 내 개수에 섞인다.
private func idHost(_ tag: String) -> String { "v0336-\(tag)-\(UUID().uuidString.lowercased())" }

/// 근무 중 · 팀 확정 · 입력 관측이 있는 스토어. `adopted` 가 true 면 흡수 맥(남의 세션을 미러링 중)이다.
@MainActor
private func idWorkStore(
    host: String, deviceID: String, adopted: Bool = false, label: String, function: String = #function
) -> WorkTimerStore {
    let defaults = CheckTestScratch.defaults(label, function: function)
    let store = idStore(defaults: defaults, vault: InMemoryTokenVault(), host: host, label: label, function: function)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: idUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    // 신원은 **생성 뒤에** 덮어쓴다. 생성자는 CheckTestScratch 의 성한 defaults 에서 진짜 ID 를 하나
    // 만들어 놓으므로, 여기서 덮지 않으면 "신원 없음" 케이스가 조용히 "신원 있음"이 된다.
    store.deviceID = deviceID
    store.startedAt = idNow.addingTimeInterval(-3_600)
    store.currentSessionID = idOwnedSessionID
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.adoptedRemoteSession = adopted
    // 서버가 last_input_at 을 아는 버전 + 이미 관측된 입력 하나 — reportDeviceInput 의 두 전제다.
    store.awayServerSupported = true
    store.lastMeaningfulInputAt = idNow.addingTimeInterval(-60)
    return store
}

/// **신원 없는 실행은 스캔 사실도 서버에 남기지 않는다.** 이 하트비트는 사용량 행과 같은 기기 키로
/// 들어가므로 유령 ID 로 보내면 "스캔은 도는데 값이 없는 기기"가 그 사람 화면에 실행마다 하나씩 쌓인다.
@MainActor
@Test
func identityGateSilencesScanHeartbeatWithoutDeviceID() async {
    let blindHost = idHost("scanhb-blind")
    let blind = idWorkStore(host: blindHost, deviceID: "", label: "scanhb-blind")
    defer { idCancelTasks(blind) }
    await blind.tokenUsage.refreshIfStale()

    // 전제: 스캔은 실제로 돌았다(보고할 사실이 있다). 이게 nil 이면 아래 침묵은 게이트의 공이 아니다.
    #expect(blind.tokenUsage.lastScanAt != nil)
    #expect(blind.tokenUsageCollect)

    await blind.sendTokenScanHeartbeatIfNeeded(now: idNow)

    #expect(idExchanges(host: blindHost, path: idMonthlyPath).isEmpty)
    // 도장도 안 찍힌다 — 다음 실행이 성한 맥이면 그 스캔이 그대로 보고된다.
    #expect(blind.lastTokenScanHeartbeatAt == nil)

    // 기준선: 같은 픽스처에 신원만 있으면 그 하트비트는 실제로 나가고 본문에 그 기기가 있다.
    let liveHost = idHost("scanhb-live")
    let live = idWorkStore(host: liveHost, deviceID: "MAC-A", label: "scanhb-live")
    defer { idCancelTasks(live) }
    await live.tokenUsage.refreshIfStale()
    #expect(live.tokenUsage.lastScanAt != nil)

    await live.sendTokenScanHeartbeatIfNeeded(now: idNow)

    let beats = idExchanges(host: liveHost, path: idMonthlyPath)
    #expect(beats.count == 1)
    #expect(beats.first?.body.contains(#""device_id":"MAC-A""#) == true)
    #expect(live.lastTokenScanHeartbeatAt == live.tokenUsage.lastScanAt)
}

/// **신원 없는 실행은 기기별 소유 주장(work_status_devices)을 남기지 않는다.** 유령 행이 쌓이면 상대
/// 맥의 반납 판정 재료가 실행마다 다른 기기로 흩어진다.
///
/// 이 테스트의 핵심은 두 번째 단언이다: **생존신호 자체는 나갔다.** 그게 없으면 "가드 앞에서 통째로
/// 멈춘" 가짜 초록과 구별이 안 된다 — 근무 생존신호가 끊기면 10분 뒤 스캐빈저가 그 근무를 마감한다.
@MainActor
@Test
func identityGateSilencesStatusDeviceClaimWithoutDeviceID() async {
    let blindHost = idHost("claim-blind")
    let blind = idWorkStore(host: blindHost, deviceID: "", label: "claim-blind")
    defer { idCancelTasks(blind) }

    await blind.sendHeartbeatIfWorking()

    #expect(idExchanges(host: blindHost, path: idDevicePath).isEmpty)
    #expect(idExchanges(host: blindHost, path: idStatusPath).count == 1)

    // 기준선.
    let liveHost = idHost("claim-live")
    let live = idWorkStore(host: liveHost, deviceID: "MAC-A", label: "claim-live")
    defer { idCancelTasks(live) }

    await live.sendHeartbeatIfWorking()

    let claims = idExchanges(host: liveHost, path: idDevicePath)
    #expect(claims.count == 1)
    #expect(claims.first?.body.contains(#""device_id":"MAC-A""#) == true)
    // 소유 주장이 맞다(입력 보고가 아니다) — 세션 칸이 실려 있다.
    #expect(claims.first?.body.contains(#""session_id":"\#(idOwnedSessionID)""#) == true)
    #expect(idExchanges(host: liveHost, path: idStatusPath).count == 1)
}

/// **신원 없는 흡수 맥은 입력 보고도 거른다.** 실행마다 새 기기 행이 생기면 away 판정 재료가 유령들에게
/// 흩어져, 서버의 max(last_input_at) 규칙이 진짜 입력을 못 본다.
@MainActor
@Test
func identityGateSilencesDeviceInputReportWithoutDeviceID() async {
    let blindHost = idHost("input-blind")
    let blind = idWorkStore(host: blindHost, deviceID: "", adopted: true, label: "input-blind")
    defer { idCancelTasks(blind) }

    await blind.sendHeartbeatIfWorking()

    #expect(idExchanges(host: blindHost, path: idDevicePath).isEmpty)
    // 흡수 맥은 원래 이 한 요청 말고는 아무 말도 하지 않는다(생존신호를 대신 보내면 아무도 못 닫는
    // 세션이 된다) — 그래서 여기서는 "전부 침묵"이 맞고, 아래 기준선이 그 침묵의 값을 증명한다.
    #expect(URLProtocolStub.requests(forHost: blindHost).isEmpty)

    // 기준선.
    let liveHost = idHost("input-live")
    let live = idWorkStore(host: liveHost, deviceID: "MAC-A", adopted: true, label: "input-live")
    defer { idCancelTasks(live) }

    await live.sendHeartbeatIfWorking()

    let reports = idExchanges(host: liveHost, path: idDevicePath)
    #expect(reports.count == 1)
    #expect(reports.first?.body.contains(#""device_id":"MAC-A""#) == true)
    #expect(reports.first?.body.contains(#""last_input_at":"#) == true)
    // 입력 보고가 맞다(소유 주장이 아니다) — 세션/생존 칸이 없다.
    #expect(reports.first?.body.contains(idOwnedSessionID) == false)
    #expect(idExchanges(host: liveHost, path: idStatusPath).isEmpty)
}

/// **work_tick 은 나가되 기기 칸만 비운다.** 여기만 규약이 다르다: 틱을 막으면 근무 기록이 통째로
/// 끊기지만, 유령 ID 를 실으면 서버가 그 ID 로 기기 행을 써서 진짜 소유 맥이 자기 세션을 남의 것으로
/// 보고 물러난다. 그래서 "안 나간다"가 아니라 "나간다 + p_device_id 가 null 이다"를 건다.
///
/// 소유 맥 가지와 흡수 맥 가지를 **둘 다** 잰다 — 두 자리에 각각 삼항 연산자가 있어, 한쪽만 재면
/// 다른 쪽을 지워도 초록이다.
@MainActor
@Test
func identityGateSendsWorkTickWithNullDeviceIDAndKeepsTheHeartbeat() async {
    // (1) 소유 맥 · 신원 없음.
    let ownedBlindHost = idHost("tick-owned-blind")
    let ownedBlind = idWorkStore(host: ownedBlindHost, deviceID: "", label: "tick-owned-blind")
    defer { idCancelTasks(ownedBlind) }

    _ = await ownedBlind.workTickIfPossible()

    let ownedBlindTicks = idExchanges(host: ownedBlindHost, path: idTickPath)
    #expect(ownedBlindTicks.count == 1)
    #expect(ownedBlindTicks.first?.body.contains(#""p_device_id":null"#) == true)
    #expect(ownedBlindTicks.first?.body.contains("MAC") == false)
    // 근무는 계속된다 — 하트비트 칸과 세션 칸은 그대로다(이 둘이 없으면 근무 기록이 끊긴다).
    #expect(ownedBlindTicks.first?.body.contains(#""p_heartbeat":true"#) == true)
    #expect(ownedBlindTicks.first?.body.contains(#""p_session_id":"\#(idOwnedSessionID)""#) == true)

    // (2) 소유 맥 기준선.
    let ownedLiveHost = idHost("tick-owned-live")
    let ownedLive = idWorkStore(host: ownedLiveHost, deviceID: "MAC-A", label: "tick-owned-live")
    defer { idCancelTasks(ownedLive) }

    _ = await ownedLive.workTickIfPossible()

    let ownedLiveTicks = idExchanges(host: ownedLiveHost, path: idTickPath)
    #expect(ownedLiveTicks.count == 1)
    #expect(ownedLiveTicks.first?.body.contains(#""p_device_id":"MAC-A""#) == true)

    // (3) 흡수 맥 · 신원 없음. 이 가지는 세션 칸이 원래 null 이고 기기 칸만 실린다 — 그래서 유령 ID 가
    //     들어가면 서버가 보는 것은 "이 기기가 입력 중"이라는 거짓 하나뿐이다.
    let adoptedBlindHost = idHost("tick-adopted-blind")
    let adoptedBlind = idWorkStore(host: adoptedBlindHost, deviceID: "", adopted: true, label: "tick-adopted-blind")
    defer { idCancelTasks(adoptedBlind) }

    _ = await adoptedBlind.workTickIfPossible()

    let adoptedBlindTicks = idExchanges(host: adoptedBlindHost, path: idTickPath)
    #expect(adoptedBlindTicks.count == 1)
    #expect(adoptedBlindTicks.first?.body.contains(#""p_device_id":null"#) == true)
    #expect(adoptedBlindTicks.first?.body.contains("MAC") == false)
    #expect(adoptedBlindTicks.first?.body.contains(#""p_heartbeat":true"#) == true)
    #expect(adoptedBlindTicks.first?.body.contains(#""p_session_id":null"#) == true)

    // (4) 흡수 맥 기준선.
    let adoptedLiveHost = idHost("tick-adopted-live")
    let adoptedLive = idWorkStore(host: adoptedLiveHost, deviceID: "MAC-A", adopted: true, label: "tick-adopted-live")
    defer { idCancelTasks(adoptedLive) }

    _ = await adoptedLive.workTickIfPossible()

    let adoptedLiveTicks = idExchanges(host: adoptedLiveHost, path: idTickPath)
    #expect(adoptedLiveTicks.count == 1)
    #expect(adoptedLiveTicks.first?.body.contains(#""p_device_id":"MAC-A""#) == true)
    #expect(adoptedLiveTicks.first?.body.contains(#""p_session_id":null"#) == true)
}

// MARK: - D. 새로 로그인한 사람도 defaults 가 죽은 재시작을 넘긴다
//
// 위 B 절의 세 테스트는 **금고에 userID 가 이미 있다는 전제에서 출발한다**(직접 write 하거나, 옛
// defaults 에서 이행되거나). persistSession 이 금고에도 쓴다는 사실은 sessionVaultClearsUserIDOnSignOut
// 의 *사전조건*으로만 존재했다 — 그 테스트를 지우면 이 줄이 무방비가 되고, 그러면 "이 버전에서 처음
// 로그인한 사람"만 정확히 사고 당시의 조용한 로그아웃으로 되돌아간다(기존 사용자는 이행이 구제한다).
// 그 사람의 경로를 처음부터 끝까지 한 테스트로 꿴다.

/// **금고 빈 상태 → 로그인 → defaults 가 전부 nil 인 재시작 → 로그인 유지.**
/// 이 테스트가 `persistSession` 의 금고 쓰기 한 줄의 **단독 게이트**다.
@MainActor
@Test
func sessionVaultKeepsFreshLoginAcrossARestartWhereDefaultsDies() {
    let vault = InMemoryTokenVault()
    let defaults = CheckTestScratch.defaults("fresh-login")

    // ① 아무것도 없는 새 맥. 금고도 defaults 도 비어 있다.
    #expect(vault.read(WorkTimerStore.userIDKey) == nil)
    #expect(vault.read(WorkTimerStore.accessTokenKey) == nil)
    let fresh = idStore(defaults: defaults, vault: vault, host: "v0336-fresh-login", label: "fresh-login")
    defer { idCancelTasks(fresh) }
    #expect(!fresh.isSignedIn)

    // ② 로그인. 앱이 실제로 부르는 그 함수 하나만 부른다(테스트가 금고를 직접 채우면 계약이 사라진다).
    let session = SupabaseSession(accessToken: "fresh-access", refreshToken: "fresh-refresh", userID: idUserID)
    fresh.session = session
    fresh.persistSession(session, email: "me@example.com")

    // ③ 재시작 — 이번엔 defaults 가 죽어 모든 조회가 nil 이다(디스크 가득참·plist 파손·CFPrefs 사망).
    let dead = idDouble(IdBlindDefaults.init(suiteName:), "dead", #function)
    #expect(dead.string(forKey: WorkTimerStore.userIDKey) == nil)
    let relaunched = idStore(defaults: dead, vault: vault, host: "v0336-fresh-relaunch", label: "dead")
    defer { idCancelTasks(relaunched) }

    // ④ 로그인이 유지되고, 신원이 **그 사람 것**이다. (userID 가 defaults 에만 있던 시절엔 여기가
    //    "로그인 필요" 였다 — 키체인의 토큰은 멀쩡한데도.)
    #expect(relaunched.isSignedIn)
    #expect(relaunched.session?.userID == idUserID)
    #expect(relaunched.session?.accessToken == "fresh-access")
    #expect(relaunched.session?.refreshToken == "fresh-refresh")
}
