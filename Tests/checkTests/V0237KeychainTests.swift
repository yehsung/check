import AppKit
import Foundation
import Testing
@testable import check

// MARK: - v0.2.37 G2: 토큰 금고(Keychain) 전환
//
// 재현하는 결함(전면 감사 P0): access/refresh 토큰이 UserDefaults 평문
// (~/Library/Preferences/kingcheck.plist)에 저장돼, 같은 맥의 비샌드박스 프로세스·Time Machine 백업·
// 공용 맥에서 refresh token 하나로 영구 계정 탈취가 가능했다.
//
// 여기 테스트는 전부 InMemoryTokenVault 를 주입한다 — 서명 안 된 테스트 러너에서 실제 키체인을
// 건드리면 안 된다(실 키체인 왕복은 별도 프로브로 실측했다: 파일 키체인 add/update/delete 전부 status 0,
// data protection 키체인은 entitlement 부재로 -34018 → KeychainTokenVault 주석의 채택 근거).

/// 저장 → 재시작 복원 왕복이 금고로만 돈다. defaults 평문(유출 지점)에는 토큰이 한 순간도 남지 않는다.
@MainActor
@Test
func persistedSessionRoundTripsThroughVaultNotDefaults() {
    let defaults = v0237IsolatedDefaults()
    let vault = InMemoryTokenVault()
    let store = v0237Store(defaults: defaults, vault: vault)
    let session = SupabaseSession(
        accessToken: "vault-access",
        refreshToken: "vault-refresh",
        userID: "00000000-0000-0000-0000-000000000002"
    )

    store.persistSession(session)

    // 비밀값은 금고에만 있다.
    #expect(vault.read(WorkTimerStore.accessTokenKey) == "vault-access")
    #expect(vault.read(WorkTimerStore.refreshTokenKey) == "vault-refresh")
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == nil)
    // 비밀 아닌 값(userID)은 여전히 defaults 다 — 금고로 옮길 이유가 없고, 소유권 판정 등이 계속 읽는다.
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == "00000000-0000-0000-0000-000000000002")

    // 재시작 상당: 같은 defaults + 같은 금고로 새 스토어를 세우면 그 세션이 그대로 살아난다.
    let relaunched = v0237Store(defaults: defaults, vault: vault)
    #expect(relaunched.isSignedIn)
    #expect(relaunched.session == session)
    #expect(relaunched.syncMessage == "동기화됨")
}

/// v0.2.36 이하가 defaults 에 남긴 토큰의 1회 자동 이행: 금고로 옮겨지고 defaults 잔존은 0 이 된다.
/// brew 업그레이드 사용자의 로그인 유지가 이 경로에 달렸다 — 이행 없이 금고만 보면 전원 로그아웃이다.
@MainActor
@Test
func legacyDefaultsTokensMigrateIntoVaultOnFirstRestore() {
    let defaults = v0237IsolatedDefaults()
    defaults.set("legacy-access", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("legacy-refresh", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let vault = InMemoryTokenVault()

    let store = v0237Store(defaults: defaults, vault: vault)

    // 업그레이드 첫 실행: 로그인이 유지된 채로,
    #expect(store.isSignedIn)
    #expect(store.session?.accessToken == "legacy-access")
    #expect(store.session?.refreshToken == "legacy-refresh")
    // 토큰은 금고로 옮겨졌고,
    #expect(vault.read(WorkTimerStore.accessTokenKey) == "legacy-access")
    #expect(vault.read(WorkTimerStore.refreshTokenKey) == "legacy-refresh")
    // defaults 평문 잔존은 0 이다(이 삭제가 이 수정의 목적 그 자체다).
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == nil)
    // 비밀 아닌 userID 는 이행 대상이 아니다.
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) != nil)

    // 두 번째 재시작(이행이 이미 끝난 맥): 같은 세션이 금고에서 그대로 복원된다(이행 멱등).
    let relaunched = v0237Store(defaults: defaults, vault: vault)
    #expect(relaunched.session == store.session)
}

/// 로그아웃/강제 로그아웃(clearPersistedSession)은 금고와 defaults 를 **둘 다** 지운다.
/// defaults 쪽은 키체인 고장 맥이 남긴 평문 사본(이행 보존 분기)까지 지워야 하는 자리다.
@MainActor
@Test
func clearPersistedSessionWipesBothVaultAndDefaults() {
    let defaults = v0237IsolatedDefaults()
    let vault = InMemoryTokenVault()
    let store = v0237Store(defaults: defaults, vault: vault)
    let session = SupabaseSession(
        accessToken: "vault-access",
        refreshToken: "vault-refresh",
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.session = session
    store.persistSession(session)
    // 키체인 고장 맥이 남겼을 평문 사본을 시뮬레이션한다(이행 보존 분기의 산출물).
    defaults.set("stale-plaintext-access", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("stale-plaintext-refresh", forKey: WorkTimerStore.refreshTokenKey)

    store.clearPersistedSession()

    #expect(!store.isSignedIn)
    #expect(vault.read(WorkTimerStore.accessTokenKey) == nil)
    #expect(vault.read(WorkTimerStore.refreshTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == nil)
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == nil)
}

/// 금고도 defaults 도 빈 맥(신규 설치)은 조용히 로그인 대기다 — 이행/폴백이 유령 세션을 만들지 않는다.
@MainActor
@Test
func emptyVaultAndEmptyDefaultsRequireLogin() {
    let store = v0237Store(defaults: v0237IsolatedDefaults(), vault: InMemoryTokenVault())
    #expect(!store.isSignedIn)
    #expect(store.session == nil)
    #expect(store.syncMessage == "로그인 필요")
}

/// refresh 없는 세션(access 만)의 저장·복원. 옛 defaults 경로의 removeObject 규약대로,
/// 앞 세션의 refresh 가 금고에 남지 않는다 — 남으면 다음 실행이 회전 전 토큰으로 grant 를 친다.
@MainActor
@Test
func refreshTokenlessSessionPersistsAndDropsStaleRefresh() {
    let defaults = v0237IsolatedDefaults()
    let vault = InMemoryTokenVault()
    let store = v0237Store(defaults: defaults, vault: vault)
    store.persistSession(SupabaseSession(
        accessToken: "first-access",
        refreshToken: "first-refresh",
        userID: "00000000-0000-0000-0000-000000000002"
    ))

    store.persistSession(SupabaseSession(
        accessToken: "second-access",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    ))

    #expect(vault.read(WorkTimerStore.accessTokenKey) == "second-access")
    #expect(vault.read(WorkTimerStore.refreshTokenKey) == nil)

    let relaunched = v0237Store(defaults: defaults, vault: vault)
    #expect(relaunched.isSignedIn)
    #expect(relaunched.session?.accessToken == "second-access")
    #expect(relaunched.session?.refreshToken == nil)
}

/// 키체인 write 가 고장 난 맥: 이행이 defaults 사본을 태우지 않고(다음 실행 재시도 여지),
/// 복원 폴백이 그 사본으로 로그인을 유지한다 — 업그레이드 첫 실행이 곧바로 로그아웃 화면이 되지 않는다.
@MainActor
@Test
func brokenVaultWriteKeepsLegacyDefaultsCopyAndStillRestores() {
    let defaults = v0237IsolatedDefaults()
    defaults.set("legacy-access", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("legacy-refresh", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let vault = InMemoryTokenVault()
    vault.failsWrites = true

    let store = v0237Store(defaults: defaults, vault: vault)

    #expect(store.isSignedIn)
    #expect(store.session?.accessToken == "legacy-access")
    #expect(store.session?.refreshToken == "legacy-refresh")
    // 사본이 살아 있다 — 확인(write 후 read 대조) 없이 지웠다면 이 맥의 마지막 토큰이 여기서 소실됐다.
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "legacy-access")
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == "legacy-refresh")
    #expect(vault.read(WorkTimerStore.accessTokenKey) == nil)
}

/// 금고 계약: write 실패 ⇒ read nil. 실패를 삼키고 **낡은 값**을 돌려주면 회전 전 refresh token 으로
/// grant 를 치게 되고 GoTrue reuse-detection 이 근무 중 강제 로그아웃을 만든다('없다'가 '낡았다'보다 낫다).
@Test
func inMemoryVaultWriteFailureLeavesReadNilNotStale() {
    let vault = InMemoryTokenVault()
    vault.write("v1", key: "k")
    #expect(vault.read("k") == "v1")

    vault.failsWrites = true
    vault.write("v2", key: "k")

    #expect(vault.read("k") == nil)
}

/// 테스트 프로세스의 기본 금고는 defaults 백킹(레거시 호환)이다. 이 판정이 조용히 거짓이 되면
/// 둘 중 하나가 터진다: 기본 금고가 Keychain 이면 서명 안 된 러너가 실제 키체인을 오염시키고,
/// InMemory 면 defaults 로 토큰을 시딩/단언하는 기존 스위트 전체가 빨개진다. 그래서 여기서 직접 되묻는다.
@MainActor
@Test
func testProcessDefaultVaultPreservesLegacyDefaultsContract() {
    #expect(CheckPanelVisibility.isRunningTests)
    let defaults = v0237IsolatedDefaults()
    #expect(WorkTimerStore.defaultTokenVault(defaults: defaults) is UserDefaultsTokenVault)

    // 금고 미주입 스토어의 저장은 v0.2.36 과 같은 자리(주입된 defaults)에 남는다 — 기존 스위트 초록의 근거.
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.persistSession(SupabaseSession(
        accessToken: "compat-access",
        refreshToken: "compat-refresh",
        userID: "00000000-0000-0000-0000-000000000002"
    ))
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "compat-access")
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == "compat-refresh")
}

/// 소스 계약: (1) 레거시 호환 금고와 키체인 금고의 생성 지점은 defaultTokenVault 단 한 곳이고, 그 분기는
/// isRunningTests 로만 갈린다 — 프로덕션이 UserDefaultsTokenVault 를 잡거나 테스트가 Keychain 을 잡는
/// 조립 실수를 소스에서 봉한다. (2) 프로덕션 소스 어디에도 토큰 키로의 defaults.set 이 없다 —
/// 평문 유출(P0)을 한 줄 되살리는 회귀를 막는다. 주석은 걷어내고 센다(설명문이 계약을 흔들지 않게).
@Test
func tokenVaultAssemblySourceContract() throws {
    var defaultsBackedConstructions = 0
    var keychainConstructions = 0
    for url in try v0237SourceFiles() {
        let stripped = v0237StrippingComments(try String(contentsOf: url, encoding: .utf8))
        defaultsBackedConstructions += v0237Occurrences(of: "UserDefaultsTokenVault(", in: stripped)
        keychainConstructions += v0237Occurrences(of: "KeychainTokenVault(", in: stripped)
        for line in stripped.split(separator: "\n") where line.contains("defaults.set(") {
            #expect(
                !line.contains("accessTokenKey") && !line.contains("refreshTokenKey"),
                "토큰이 defaults 평문으로 돌아갔다: \(url.lastPathComponent): \(line)"
            )
        }
    }
    #expect(defaultsBackedConstructions == 1)
    #expect(keychainConstructions == 1)

    // 그 유일한 생성 지점(defaultTokenVault 본문)이 isRunningTests 로 갈린다.
    let storeSource = v0237StrippingComments(
        try String(contentsOf: v0237SourceURL("WorkTimerStore.swift"), encoding: .utf8)
    )
    guard let bodyStart = storeSource.range(of: "static func defaultTokenVault"),
          let bodyEnd = storeSource.range(of: "}", range: bodyStart.upperBound..<storeSource.endIndex)
    else {
        Issue.record("defaultTokenVault 를 소스에서 찾지 못했다")
        return
    }
    let body = String(storeSource[bodyStart.upperBound..<bodyEnd.lowerBound])
    #expect(body.contains("CheckPanelVisibility.isRunningTests"))
    #expect(body.contains("UserDefaultsTokenVault(defaults: defaults)"))
    #expect(body.contains("KeychainTokenVault()"))
}

// MARK: - 헬퍼

/// 잠자기 옵저버 없이, 스텁도 네트워크도 필요 없는 스토어(여기 테스트는 활성화를 태우지 않아 요청 0건).
@MainActor
private func v0237Store(defaults: UserDefaults, vault: TokenVault) -> WorkTimerStore {
    WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        tokenVault: vault,
        workspaceNotifications: nil
    )
}

private func v0237IsolatedDefaults() -> UserDefaults {
    let suiteName = "check-v0237-keychain-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func v0237SourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/checkTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("Sources/check/\(name)")
}

private func v0237SourceFiles() throws -> [URL] {
    let root = v0237SourceURL("WorkTimerStore.swift").deletingLastPathComponent()
    return try FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
}

private func v0237Occurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다
/// (RealtimeLinkTests 의 소스 계약 헬퍼와 같은 규약 — private 라 파일마다 사본을 둔다).
private func v0237StrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
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
