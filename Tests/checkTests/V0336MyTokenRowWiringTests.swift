import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.36 후속 — **배선에 행동 테스트를 붙인다.**
//
// 왜 이 파일이 생겼나(2026-09-22 검증): 5be21fc 의 수리는 순수 함수(`TokenRowDisplayRule`)와 JSON 왕복,
// 그리고 `CheckMenuView` 의 **인자 문자열**까지만 테스트가 닿아 있었다. 정작 그 값을 서버에서 받아 와
// 스토어에 심고 디스크에 남기는 자리 — `loadMyTokenRowIfDue` · `performLoadTokenBoard` 의 내 행 채집 ·
// `init` 복원 · 로그아웃/달 바뀜의 비움 — 은 **어느 테스트도 실행하지 않았다**.
// 즉 `myTokenRow` 가 프로덕션에서 영영 nil 이어도 전 스위트가 초록이고, 11명 화면은 하나도 안 바뀐다.
// (이 저장소가 '클라 게이트는 짝으로 있다'로 부르는 그 실패 모양이다.)
//
// 여기서 고정하는 것:
//  ⓐ 팝오버를 여는 것만으로 보드 RPC 가 **실제로 나간다**(이번 달로, 정확히 1회).
//  ⓑ 그 응답의 내 행이 `myTokenRow` 에 들어가고 UserDefaults 에 남는다.
//  ⓒ 그 값이 **팝오버 행이 그리는 픽셀**이 된다(네트워크 → 스토어 → 뷰 전 구간 한 줄로).
//  ⓓ 재시작 복원은 **이번 달 + 내 것**일 때만. 아니면 값도 키도 버린다.
//  ⓔ 로그아웃·달 바뀜에서 값·스탬프·영속본이 함께 비워진다.
//  ⓕ 순위판을 연 사람은 보드 응답에서 내 행을 덤으로 집어 온다 — **이번 달을 보고 있을 때만**.
//  ⓖ '행 없음'과 '조회 실패'를 가르는 규칙(`outcomeForMyRow`).

// MARK: - 고정 응답 스텁

/// 보드 RPC 응답만 호스트별 캔으로 돌려주고 **경로별 요청을 전부 센다**. 다른 경로는 빈 배열 200 이다
/// (팝오버 열림은 보드 말고도 여러 경로를 두드리는데, 그 응답들은 이 파일의 주장과 무관하다).
///
/// `URLProtocolStub` 을 안 쓰는 이유: 그쪽은 `token_usage_board` 에 빈 `Data()` 를 돌려줘 디코드가 던진다
/// (= 스토어의 catch 로 떨어진다). 그 스텁으로는 "응답의 내 행이 심긴다"를 한 글자도 확인할 수 없다.
final class MyTokenRowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var boardJSONByHost: [String: String] = [:]
    private nonisolated(unsafe) static var boardStatusByHost: [String: Int] = [:]
    private nonisolated(unsafe) static var requestsByHost: [String: [(path: String, body: String)]] = [:]

    /// 호스트별 캔을 세운다(테스트마다 고유 호스트 — 병렬 실행이 서로의 픽스처를 못 덮는다).
    private nonisolated(unsafe) static var boardDelayByHost: [String: TimeInterval] = [:]

    /// `boardDelay` 는 **요청이 기록된 뒤** 응답만 늦춘다 — 그래야 테스트가 "요청은 나갔고 응답은 아직"인
    /// 구간을 잡아 그 사이에 계정 전환 같은 사건을 끼워 넣을 수 있다.
    static func configure(host: String, boardJSON: String, boardStatus: Int = 200, boardDelay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        boardJSONByHost[host] = boardJSON
        boardStatusByHost[host] = boardStatus
        boardDelayByHost[host] = boardDelay
        requestsByHost[host] = []
    }

    static func requests(host: String, path: String) -> [(path: String, body: String)] {
        lock.lock(); defer { lock.unlock() }
        return (requestsByHost[host] ?? []).filter { $0.path == path }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MyTokenRowURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let body = Self.bodyText(from: request)
        Self.lock.lock()
        Self.requestsByHost[host, default: []].append((path, body))
        let isBoard = path == myRowBoardPath
        let json = isBoard ? (Self.boardJSONByHost[host] ?? "[]") : "[]"
        let status = isBoard ? (Self.boardStatusByHost[host] ?? 200) : 200
        let delay = isBoard ? (Self.boardDelayByHost[host] ?? 0) : 0
        Self.lock.unlock()

        // URLSession 의 로더 스레드만 붙잡는다(메인 액터가 아니다) — 그 사이 테스트는 계속 돈다.
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let myRowBoardPath = "/rest/v1/rpc/token_usage_board"

// MARK: - 픽스처

private let myRowUserID = "d5fd403e-b857-4792-9b3b-269f84d47de1"
private let myRowOtherUserID = "b9af636b-123d-4dee-ac58-bbd147ff7910"
/// 서버 total = claude 1,081,155,290 + codex_effective 1,288,774,633 + 안티그래비티 474,733,497.
/// `codex_account_month` 1,191,490,526 은 **이미 나눈 내 몫**(2026-09-22 프로덕션 읽기 그대로 — V0336 골든 벡터와 같은 행).
private let myRowTotal = 2_844_663_420
private let myRowAccountShare = 1_191_490_526

/// 보드 응답. 달은 호출 시점의 이번 달로 맞춘다(행 자체엔 달이 없다 — 달은 요청 인자가 정한다).
private func myRowBoardJSON(includingMe: Bool = true) -> String {
    let mine = """
    {"user_id":"\(myRowUserID)","display_name":"ㅂ보예성","avatar_url":null,
     "claude_input":7966,"claude_output":4062560,"claude_cache_read":1054514044,"claude_cache_creation":22570720,
     "codex_input":1294176063,"codex_output":5798903,"total":\(myRowTotal),
     "today_total":46102503,"today_date":"2026-09-22","codex_cache_read":1249377024,
     "codex_account_month":\(myRowAccountShare),"codex_effective":1288774633,"center":"seoul"}
    """
    let other = """
    {"user_id":"\(myRowOtherUserID)","display_name":"향룡","avatar_url":null,
     "claude_input":644,"claude_output":237106,"claude_cache_read":71486887,"claude_cache_creation":3175361,
     "codex_input":1940374290,"codex_output":9572544,"total":3132426288,
     "today_total":0,"today_date":"2026-09-22","codex_cache_read":1887328128,
     "codex_account_month":2454958224,"codex_effective":3057526290,"center":"seoul"}
    """
    // 순서가 계약이다: **남의 행이 0번째**다. 내 행을 앞에 두면 행 고르기(`first(where:)` → `first`)를
    // 망가뜨려도 이 파일 전체가 초록이다(2026-09-22 변종 실험으로 확인 — 1,266건 전부 통과했다).
    return "[\(includingMe ? "\(other),\(mine)" : other)]"
}

/// 서비스가 쓰는 것과 **같은 디코더 규약**(convertFromSnakeCase)으로 위 응답을 엔트리로 만든다.
private func myRowEntries(includingMe: Bool = true) -> [TokenBoardEntry] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = (try? decoder.decode([TokenBoardRow].self, from: Data(myRowBoardJSON(includingMe: includingMe).utf8))) ?? []
    return rows.toTokenBoardEntries()
}

/// 격리 defaults. 고정 이름이라 개수는 유계지만 그 이름 그대로는 ~/Library/Preferences 에 항목을
/// 만들므로, 같은 이름을 $TMPDIR 절대 경로로 옮긴다(CheckTestScratch 주석의 2026-09-22 사고).
/// 이름이 1:1 로 유지되니 `seeded(_:)` 가 심고 다른 스토어가 읽는 "같은 스위트" 단언은 그대로다.
private func myRowDefaults(_ suiteName: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: suiteName)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

/// 스캔이 절대 일어나지 않는 토큰 스토어(빈 임시 홈) — 팝오버 열림이 개발자의 실홈을 훑지 않게 한다.
@MainActor
private func myRowInertTokenStore(_ suiteName: String, usage: TokenUsageMonthly? = nil) -> TokenUsageStore {
    let defaults = myRowDefaults(suiteName + ".token")
    if let usage, let data = try? JSONEncoder().encode(usage) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: tmp.appendingPathComponent("check-v0336-myrow-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0336-myrow-cache-\(suiteName).json", isDirectory: false)
    )
}

@MainActor
private func myRowStore(
    host: String,
    suiteName: String,
    userID: String = myRowUserID,
    defaults: UserDefaults? = nil,
    tokenUsage: TokenUsageStore? = nil,
    signedIn: Bool = true
) -> (WorkTimerStore, UserDefaults) {
    let resolved = defaults ?? myRowDefaults(suiteName)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MyTokenRowURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: resolved,
        workspaceNotifications: nil,
        tokenUsage: tokenUsage ?? myRowInertTokenStore(suiteName)
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.membershipConfirmed = true
    }
    return (store, resolved)
}

@MainActor
private func myRowCancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 조건이 참이 될 때까지 **메인 액터에서** 기다린다(V0238NetworkTests 와 같은 규약 — 관찰 대상이 전부 메인 액터라
/// 글로벌 풀에서 기다리면 굶주림 구간에 예산만 태우고 0건을 실패로 오판한다).
@MainActor
private func myRowWaitUntil(maxResumes: Int = 1_500, _ condition: () -> Bool) async {
    for _ in 0..<maxResumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - ⓐⓑ 팝오버를 여는 것만으로 내 행이 서버에서 온다

/// 뮤테이션: `loadMyTokenRowIfDue` 를 no-op 으로 만들거나 `myTokenRow` 대입을 지우면 이 테스트가 빨갛다.
@MainActor
@Test
func v0336OpeningThePopoverFetchesMyBoardRowOnceAndKeepsIt() async throws {
    let host = "v0336-myrow-open"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())
    let (store, defaults) = myRowStore(host: host, suiteName: "check-v0336-myrow-open")
    defer { myRowCancelTasks(store) }

    // 전제: 아직 아무것도 없다. (이 줄이 없으면 아래 단언이 '원래 있던 값'을 볼 수도 있다.)
    #expect(store.myTokenRow == nil)
    #expect(defaults.data(forKey: WorkTimerStore.myTokenRowKey) == nil)
    #expect(!store.isTokenBoardVisible, "순위판이 열려 있으면 팝오버 경로는 일부러 쏘지 않는다(전제)")

    store.setMenuPresented(true)
    await myRowWaitUntil { store.myTokenRow != nil }

    // ⓐ 보드 RPC 가 실제로 나갔다 — **이번 달로, 정확히 1회**.
    let boardRequests = MyTokenRowURLProtocol.requests(host: host, path: myRowBoardPath)
    #expect(boardRequests.count == 1, "팝오버 한 번 열림에 보드 RPC 가 \(boardRequests.count)회 나갔다(무거운 RPC 다)")
    #expect(boardRequests.first?.body.contains("\"p_month\":\"\(TokenUsageMonthKey.current())\"") == true,
            "팝오버 행은 언제나 이번 달이다 — 요청 인자가 그렇지 않다")

    // ⓑ 응답의 **내 행**이 심겼다(남의 행이 아니라).
    let row = try #require(store.myTokenRow)
    #expect(row.userID == myRowUserID)
    #expect(row.total == myRowTotal)
    #expect(row.month == TokenUsageMonthKey.current())
    #expect(row.codexAccountShare == myRowAccountShare, "잔디 비율의 분자가 계정 원본으로 바뀌었다")

    // 디스크에도 남는다(재시작 첫 프레임의 깜빡임을 없애는 자리).
    let persisted = try #require(defaults.data(forKey: WorkTimerStore.myTokenRowKey))
    #expect(try JSONDecoder().decode(TokenRowServerValue.self, from: persisted) == row)

    // 300초 스로틀: 바로 다시 열어도 같은 RPC 를 또 쏘지 않는다.
    store.setMenuPresented(false)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(150))
    #expect(MyTokenRowURLProtocol.requests(host: host, path: myRowBoardPath).count == 1)
}

// MARK: - ⓒ 네트워크 → 스토어 → **픽셀** 한 줄로

/// 짝 게이트의 끝까지: 서버가 준 숫자가 팝오버 행에 **그려지는** 숫자와 같은가.
/// 기준 그림은 '서버 total 을 로컬만으로 그린 거울 행'이다 — 부등호가 아니라 등호로 재야 렌더 흔들림이
/// 단언을 만족시키지 못한다(V0336SharedCodexDisplayTests 의 측정 주석 참조).
@MainActor
@Test
func v0336TheFetchedRowIsTheNumberTheMenuRowDraws() async throws {
    let host = "v0336-myrow-pixels"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())
    let suite = "check-v0336-myrow-pixels"

    // 이 맥의 로컬 산식은 **분배 전 계정 원본**을 그린다(수리 전 화면). 거울과 달라야 기준선이 성립한다.
    var bloated = TokenUsageMonthly(month: TokenUsageMonthKey.current())
    bloated.claudeInput = 7_966
    bloated.claudeOutput = 4_062_560
    bloated.claudeCacheRead = 1_054_514_044
    bloated.claudeCacheCreation = 22_570_720
    bloated.codexInput = 1_294_176_063
    bloated.codexOutput = 5_798_903
    bloated.codexCacheRead = 1_249_377_024
    bloated.antigravityInput = 474_733_497
    let tokenStore = myRowInertTokenStore(suite, usage: bloated)

    var mirrorUsage = TokenUsageMonthly(month: TokenUsageMonthKey.current())
    mirrorUsage.claudeInput = myRowTotal          // displayTotal(account: nil) == 서버 total
    let mirrorStore = myRowInertTokenStore(suite + ".mirror", usage: mirrorUsage)

    let (store, _) = myRowStore(host: host, suiteName: suite, tokenUsage: tokenStore)
    defer { myRowCancelTasks(store) }

    store.setMenuPresented(true)
    await myRowWaitUntil { store.myTokenRow != nil }
    #expect(store.myTokenRow?.total == myRowTotal, "스토어가 안 채워졌다(아래 픽셀 단언의 전제)")

    // CheckMenuView 가 조립하는 것과 **같은 인자**로 행을 만든다(CheckMenuView.swift:392~395).
    @MainActor
    func renderAll() throws -> (wired: Data, mirror: Data, local: Data) {
        (
            try myRowRenderPNG(CheckTokenUsageRow(store: store.tokenUsage,
                                                  serverRow: store.myTokenRow,
                                                  userID: store.session?.userID)),
            try myRowRenderPNG(CheckTokenUsageRow(store: mirrorStore)),
            try myRowRenderPNG(CheckTokenUsageRow(store: store.tokenUsage))
        )
    }
    _ = try renderAll()                            // 버리는 1회전(ImageRenderer 정착 — 측정 근거는 V0336 파일 주석)
    let shot = try renderAll()

    #expect(shot.local != shot.mirror, "수리 전 로컬 그림과 서버 total 그림이 같으면 이 테스트는 아무것도 못 잡는다")
    #expect(shot.wired == shot.mirror, "서버에서 받아 스토어에 심은 숫자가 화면에 안 닿는다")
}

private enum MyRowRenderError: Error { case failed }

@MainActor
private func myRowRenderPNG(_ view: some View) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: 292).fixedSize())
    renderer.scale = 3
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
    else { throw MyRowRenderError.failed }
    return png
}

// MARK: - ⓓ 재시작 복원은 '이번 달 + 내 것'일 때만

@MainActor
@Test
func v0336MyTokenRowIsRestoredOnlyWhenItIsMineAndThisMonth() throws {
    let host = "v0336-myrow-restore"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())

    /// 이전 실행이 남긴 모양 그대로 defaults 를 만든다(세션은 금고가 아니라 defaults 로 복원된다 —
    /// 테스트 프로세스의 기본 금고가 `UserDefaultsTokenVault` 다).
    func seeded(_ suite: String, row: TokenRowServerValue, sessionUserID: String) throws -> UserDefaults {
        let defaults = myRowDefaults(suite)
        defaults.set("access-token", forKey: WorkTimerStore.accessTokenKey)
        defaults.set(sessionUserID, forKey: WorkTimerStore.userIDKey)
        defaults.set(try JSONEncoder().encode(row), forKey: WorkTimerStore.myTokenRowKey)
        return defaults
    }

    let myEntry = try #require(myRowEntries().first { $0.userID == myRowUserID })
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
    let mine = try #require(TokenRowServerValue(entry: myEntry, month: TokenUsageMonthKey.current(), fetchedAt: fetchedAt))

    // ① 이번 달 + 내 것 → 살아난다(재시작 첫 프레임에 부푼 로컬값이 떴다 떨어지는 깜빡임을 없애는 자리).
    let suiteA = "check-v0336-myrow-restore-ok"
    let defaultsA = try seeded(suiteA, row: mine, sessionUserID: myRowUserID)
    let (storeA, _) = myRowStore(host: host, suiteName: suiteA, defaults: defaultsA, signedIn: false)
    defer { myRowCancelTasks(storeA) }
    #expect(storeA.session?.userID == myRowUserID, "세션이 복원되지 않았다(이 테스트의 전제)")
    #expect(storeA.myTokenRow == mine)

    // ② 지난달 행 → 버리고 키도 지운다(남기면 달이 바뀐 뒤에도 지난달 총합이 행에 굳는다).
    let suiteB = "check-v0336-myrow-restore-stale-month"
    let lastMonth = try #require(TokenRowServerValue(entry: myEntry, month: "2026-01", fetchedAt: fetchedAt))
    let defaultsB = try seeded(suiteB, row: lastMonth, sessionUserID: myRowUserID)
    let (storeB, _) = myRowStore(host: host, suiteName: suiteB, defaults: defaultsB, signedIn: false)
    defer { myRowCancelTasks(storeB) }
    #expect(storeB.myTokenRow == nil)
    #expect(defaultsB.data(forKey: WorkTimerStore.myTokenRowKey) == nil, "버린 행의 키가 디스크에 남았다")

    // ③ 남의 행 → 버린다(계정 전환 뒤 첫 프레임에 앞 사람 숫자가 뜨지 않게).
    let suiteC = "check-v0336-myrow-restore-other-user"
    let defaultsC = try seeded(suiteC, row: mine, sessionUserID: myRowOtherUserID)
    let (storeC, _) = myRowStore(host: host, suiteName: suiteC, defaults: defaultsC, signedIn: false)
    defer { myRowCancelTasks(storeC) }
    #expect(storeC.session?.userID == myRowOtherUserID)
    #expect(storeC.myTokenRow == nil)
    #expect(defaultsC.data(forKey: WorkTimerStore.myTokenRowKey) == nil)
}

// MARK: - ⓔ 로그아웃 · 달 바뀜에서 비워진다

@MainActor
@Test
func v0336SignOutAndMonthRolloverClearMyTokenRow() async throws {
    // 로그아웃: 값·스탬프·영속본이 함께 내려간다(사람에 묶인 숫자다).
    let hostA = "v0336-myrow-signout"
    MyTokenRowURLProtocol.configure(host: hostA, boardJSON: myRowBoardJSON())
    let (storeA, defaultsA) = myRowStore(host: hostA, suiteName: "check-v0336-myrow-signout")
    defer { myRowCancelTasks(storeA) }
    await storeA.loadMyTokenRowIfDue(force: true)
    #expect(storeA.myTokenRow != nil, "비움을 보려면 먼저 채워져야 한다(전제)")

    storeA.signOut()
    #expect(storeA.myTokenRow == nil)
    #expect(defaultsA.data(forKey: WorkTimerStore.myTokenRowKey) == nil)
    #expect(storeA.lastMyTokenRowFetchAt == .distantPast, "스탬프가 남으면 다음 사람의 첫 조회가 300초 막힌다")

    // 달 바뀜: 앱을 켜 둔 채 달이 넘어간 뒤 순위판을 열면(= 보고 있던 달 ≠ 이번 달) 행의 서버값도 함께 버린다.
    let hostB = "v0336-myrow-rollover"
    MyTokenRowURLProtocol.configure(host: hostB, boardJSON: myRowBoardJSON())
    let (storeB, defaultsB) = myRowStore(host: hostB, suiteName: "check-v0336-myrow-rollover")
    defer { myRowCancelTasks(storeB) }
    await storeB.loadMyTokenRowIfDue(force: true)
    #expect(storeB.myTokenRow != nil)

    storeB.tokenBoardMonth = "2026-01"      // 지난달을 보던 상태(앱이 켜진 채 달이 넘어간 모양)
    storeB.toggleTokenBoard()               // 여는 순간 현재 달로 되맞춘다
    #expect(storeB.myTokenRow == nil, "달이 바뀌었는데 지난달 총합이 팝오버 행에 굳었다")
    #expect(defaultsB.data(forKey: WorkTimerStore.myTokenRowKey) == nil)
}

// MARK: - ⓕ 순위판 응답에서 덤으로 집어 오되, 이번 달일 때만

@MainActor
@Test
func v0336BoardPageHarvestsMyRowOnlyWhileLookingAtThisMonth() async throws {
    let host = "v0336-myrow-harvest"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())
    let (store, _) = myRowStore(host: host, suiteName: "check-v0336-myrow-harvest")
    defer { myRowCancelTasks(store) }

    // ① 이번 달 보드를 받으면 내 행이 덤으로 들어온다(팝오버가 같은 무거운 RPC 를 한 번 더 쏘지 않게).
    store.tokenBoardMonth = TokenUsageMonthKey.current()
    await store.performLoadTokenBoard()
    #expect(store.tokenBoard.count == 2, "보드 자체가 안 채워졌다(전제)")
    #expect(store.myTokenRow?.total == myRowTotal)
    #expect(store.lastMyTokenRowFetchAt != .distantPast, "스탬프를 안 찍으면 팝오버가 같은 RPC 를 곧바로 또 쏜다")

    // ② ‹ 로 지난달을 보는 중이면 그 응답은 팝오버가 쓸 값이 **아니다**.
    store.myTokenRow = nil
    store.tokenBoardMonth = "2026-01"
    await store.performLoadTokenBoard()
    #expect(store.tokenBoard.count == 2, "지난달 조회 자체는 성공해야 한다(전제)")
    #expect(store.myTokenRow == nil, "지난달 보드를 보다 닫으면 팝오버가 지난달 총합을 그린다")
}

// MARK: - ⓖ '행 없음'과 '조회 실패'를 가른다

/// 2026-09-22 사용자 결정: 서버가 **응답은 했는데 내 행이 없으면** 비우고 로컬로 되돌린다. 네트워크·서버 실패는 유지한다.
/// 낡음 시한(오프라인 N시간 같은 것)은 넣지 않는다.
///
/// 왜 필요한가: 토큰 수집을 끈 사람의 행은 서버가 purge 한다. 지금 코드는 그때 조용한 no-op 이라 팝오버가
/// **서버에 더 이상 없는 숫자**를 계속 그린다(같은 화면의 잔디는 비어 있어 한 화면이 두 사실을 말한다).
@Test
func v0336MissingRowClearsWhileAFailedFetchKeeps() throws {
    let month = "2026-09"
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let withMe = myRowEntries()
    let withoutMe = myRowEntries(includingMe: false)

    // ① 내 행이 있다 → 그 값으로 갈아끼운다.
    let myEntry = try #require(withMe.first { $0.userID == myRowUserID })
    let expected = try #require(TokenRowServerValue(entry: myEntry, month: month, fetchedAt: now))
    #expect(TokenRowDisplayRule.outcomeForMyRow(
        entries: withMe, userID: myRowUserID, month: month, fetchedAt: now) == .adopt(expected))
    // 전제이자 계약: 내 행은 **0번째가 아니다**. 이게 깨지면 `first(where:)` 를 `first` 로 바꿔도 초록이 된다.
    #expect(withMe.first?.userID == myRowOtherUserID,
            "픽스처가 내 행을 앞에 뒀다 — 행 고르기 뮤테이션이 살아난다")

    // ② 서버는 응답했는데 내 행이 없다 → **비운다**(수집을 끈 사람의 purge 된 행 — 2026-09 기준 1명).
    #expect(TokenRowDisplayRule.outcomeForMyRow(entries: withoutMe, userID: myRowUserID, month: month, fetchedAt: now) == .clear)
    // 빈 응답도 같다(아무도 안 올린 달의 모양).
    #expect(TokenRowDisplayRule.outcomeForMyRow(entries: [], userID: myRowUserID, month: month, fetchedAt: now) == .clear)

    // ③ 내 행은 왔는데 구버전 RPC(codex_effective 없음) → **유지**한다. 비우면 그 순간 팝오버가
    //    분배 전 로컬값으로 돌아간다(이 릴리스가 고친 바로 그 화면) — '행이 사라졌다'와는 다른 사실이다.
    let legacyDecoder = JSONDecoder()
    legacyDecoder.keyDecodingStrategy = .convertFromSnakeCase
    let legacy = try legacyDecoder.decode(
        [TokenBoardRow].self,
        from: Data(myRowBoardJSON().replacingOccurrences(of: "\"codex_effective\":1288774633,", with: "").utf8)
    ).toTokenBoardEntries()
    #expect(legacy.first { $0.userID == myRowUserID }?.hasServerCodexEffective == false, "전제: 구버전 응답이 맞다")
    #expect(TokenRowDisplayRule.outcomeForMyRow(entries: legacy, userID: myRowUserID, month: month, fetchedAt: now) == .keep)

    // ④ **조회 실패는 이 함수에 오지 않는다.** 실패를 '행 없음'으로 접으면 비행기 모드에서 숫자가 로컬로 튄다 —
    //    스토어의 catch 가 이 열거값을 아예 만들지 않는 것이 그 계약이고, 소스가 그걸 지키는지 여기서 되묻는다.
    let sync = myRowStrippingComments(
        try String(contentsOf: myRowSourceURL("WorkTimerStoreSync.swift"), encoding: .utf8)
    )
    let body = try #require(myRowFunctionBody(of: "func loadMyTokenRowIfDue", in: sync))
    let catchRange = try #require(body.range(of: "} catch {"))

    // ⑤ **짝 단언이 먼저다.** 아래 두 줄은 '없음'만 주장하는데, 판정 함수가 이 파일에 아예 안 쓰이면 둘 다
    //    자동으로 참이 된다(= 규칙을 프로덕션에 안 붙여도 초록). 있어야 할 자리에 있는지부터 못 박는다.
    let doPart = body[..<catchRange.lowerBound]
    #expect(doPart.contains("TokenRowDisplayRule.outcomeForMyRow"),
            "do 블록이 판정 함수를 부르지 않는다 — 규칙이 정의만 되고 프로덕션에 안 붙어 있다")
    #expect(doPart.contains("applyMyTokenRowOutcome("),
            "판정을 집행하는 자리가 없다 — 규칙의 .clear/.keep 이 화면에 닿지 않는다")
    #expect(sync.contains("func applyMyTokenRowOutcome(_ outcome: MyTokenRowOutcome)"),
            "집행 함수가 사라졌다(판정과 집행을 다시 do/catch 사이에 흩뿌린 모양)")
    let harvest = try #require(myRowFunctionBody(of: "func performLoadTokenBoard", in: sync))
    #expect(harvest.contains("applyMyTokenRowOutcome(TokenRowDisplayRule.outcomeForMyRow"),
            "순위판의 덤 채집이 같은 규칙을 지나지 않는다 — 두 경로가 다른 판정을 한다")

    // ⑥ 그리고 **실패 경로에는 없어야 한다**(위 ⑤ 가 참인 상태에서만 이 두 줄이 뜻을 가진다).
    let catchPart = catchRange.upperBound
    #expect(!body[catchPart...].contains("outcomeForMyRow"),
            "실패 경로가 판정 함수를 부른다 — 그러면 네트워크 실패가 '행 없음'으로 읽힌다")
    #expect(!body[catchPart...].contains("myTokenRow ="),
            "실패 경로가 myTokenRow 를 건드린다 — 오프라인에서 공유 계정 사용자의 숫자가 로컬값으로 튄다")
}

// MARK: - ⓖ-2 purge 된 행은 비우고, 조회 실패는 지킨다 (규칙이 아니라 **스토어**로)

/// 위 ⓖ 는 순수 함수를 재고, 여기는 그 판정이 **스토어와 디스크까지 실제로 집행되는지**를 잰다.
/// 패치와 이 테스트는 한 묶음이다 — 집행부(`applyMyTokenRowOutcome`)만 있고 이 회차가 없으면
/// 다음 회귀에서 `.clear` 가 조용한 no-op 으로 되돌아가도 아무도 안 잡는다.
@MainActor
@Test
func v0336PurgedRowClearsTheStoreWhileAFailedFetchKeepsIt() async throws {
    // ① 서버는 응답했는데 내 행이 없다(수집을 끈 사람의 purge 된 행) → 값·영속본이 함께 내려간다.
    let hostA = "v0336-myrow-purged"
    MyTokenRowURLProtocol.configure(host: hostA, boardJSON: myRowBoardJSON())
    let (storeA, defaultsA) = myRowStore(host: hostA, suiteName: "check-v0336-myrow-purged")
    defer { myRowCancelTasks(storeA) }
    await storeA.loadMyTokenRowIfDue(force: true)
    #expect(storeA.myTokenRow != nil, "비움을 보려면 먼저 채워져야 한다(전제)")
    #expect(defaultsA.data(forKey: WorkTimerStore.myTokenRowKey) != nil, "전제")

    MyTokenRowURLProtocol.configure(host: hostA, boardJSON: myRowBoardJSON(includingMe: false))
    await storeA.loadMyTokenRowIfDue(force: true)
    #expect(storeA.myTokenRow == nil, "서버에 더 이상 없는 숫자를 팝오버가 계속 그린다(잔디는 비어 있는 채로)")
    #expect(defaultsA.data(forKey: WorkTimerStore.myTokenRowKey) == nil,
            "영속본이 남으면 다음 실행 첫 프레임이 그 숫자를 되살린다")

    // ② 조회 실패는 **들고 있던 값을 지킨다**. 비우면 비행기 모드에서 공유 계정 사용자의 숫자가 로컬값으로 튄다.
    let hostB = "v0336-myrow-failed-fetch"
    MyTokenRowURLProtocol.configure(host: hostB, boardJSON: myRowBoardJSON())
    let (storeB, defaultsB) = myRowStore(host: hostB, suiteName: "check-v0336-myrow-failed-fetch")
    defer { myRowCancelTasks(storeB) }
    await storeB.loadMyTokenRowIfDue(force: true)
    let held = try #require(storeB.myTokenRow)

    MyTokenRowURLProtocol.configure(host: hostB, boardJSON: "{\"message\":\"boom\"}", boardStatus: 500)
    await storeB.loadMyTokenRowIfDue(force: true)
    #expect(storeB.myTokenRow == held, "조회 실패를 '행 없음'으로 읽었다")
    #expect(defaultsB.data(forKey: WorkTimerStore.myTokenRowKey) != nil, "실패가 영속본을 지웠다")
}

// MARK: - ⓗ 늦게 도착한 응답 · 달 출처 (변종 K · R · S 를 닫는 세 회차)

/// **K**: 팝오버 행의 달 출처는 `TokenUsageMonthKey.current()` 다. `tokenBoardMonth`(‹ › 로 움직인다)를 쓰면
/// 순위판을 지난달에 세워 둔 사람의 팝오버가 지난달 총합을 조회한다. 소스에 ★로 적힌 그 실수를 회차로 잡는다.
@MainActor
@Test
func v0336ThePopoverRowAsksForThisMonthEvenWhileTheBoardSitsOnAPastMonth() async throws {
    let host = "v0336-myrow-month-source"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())
    let (store, _) = myRowStore(host: host, suiteName: "check-v0336-myrow-month-source")
    defer { myRowCancelTasks(store) }

    // 순위판은 ‹ 로 지난달에 세워 둔 채 **닫혀 있다**(열려 있으면 이 경로는 일부러 쏘지 않는다).
    store.tokenBoardMonth = "2026-01"
    #expect(!store.isTokenBoardVisible, "전제")

    await store.loadMyTokenRowIfDue(force: true)

    let requests = MyTokenRowURLProtocol.requests(host: host, path: myRowBoardPath)
    #expect(requests.count == 1, "조회가 나가지 않았다(전제)")
    #expect(requests.first?.body.contains("\"p_month\":\"\(TokenUsageMonthKey.current())\"") == true,
            "팝오버 행이 순위판이 보고 있던 달로 조회했다")
    #expect(requests.first?.body.contains("\"p_month\":\"2026-01\"") == false, "지난달로 나갔다")
    #expect(store.myTokenRow?.month == TokenUsageMonthKey.current(), "심긴 행의 달이 이번 달이 아니다")
}

/// **R**: 달 바뀜을 넘어 도착한 응답은 버린다. 진짜 시계를 돌릴 수 없으므로 같은 어긋남을 주입한 시계로 만든다 —
/// 조회는 '그때의 달'로 나가고(`now` 45일 전 = 반드시 다른 달), 도착 시점의 이번 달은 그것과 다르다.
/// 재확인(`month == TokenUsageMonthKey.current()`)이 없으면 지난달 총합이 팝오버 행에 심긴다.
@MainActor
@Test
func v0336ARowFetchedForAnotherMonthIsDroppedOnArrival() async throws {
    let host = "v0336-myrow-stale-month"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON())
    let (store, defaults) = myRowStore(host: host, suiteName: "check-v0336-myrow-stale-month")
    defer { myRowCancelTasks(store) }

    let issuedAt = Date().addingTimeInterval(-45 * 86_400)      // 45 > 31 이라 언제 돌려도 다른 달이다
    let staleMonth = TokenUsageMonthKey.current(issuedAt)
    #expect(staleMonth != TokenUsageMonthKey.current(), "전제: 45일 전은 다른 달이다")

    await store.loadMyTokenRowIfDue(force: true, now: issuedAt)

    let requests = MyTokenRowURLProtocol.requests(host: host, path: myRowBoardPath)
    #expect(requests.first?.body.contains("\"p_month\":\"\(staleMonth)\"") == true,
            "조회가 '그때의 달'로 나가지 않았다(이 회차의 전제)")
    #expect(store.myTokenRow == nil, "이번 달이 아닌 달의 행이 팝오버에 심겼다")
    #expect(defaults.data(forKey: WorkTimerStore.myTokenRowKey) == nil, "지난달 행이 디스크에 남았다")
}

/// **S**: 계정 전환(sessionGeneration)을 넘어 도착한 응답은 버린다.
/// 가드가 없으면 로그아웃한 맥의 팝오버 행 영속본에 **앞 사람 숫자**가 남고, 다음 사람의 첫 프레임에 그게 뜬다.
@MainActor
@Test
func v0336ALateBoardResponseNeverLandsAfterTheAccountChanged() async throws {
    let host = "v0336-myrow-late-response"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: myRowBoardJSON(), boardDelay: 0.6)
    let (store, defaults) = myRowStore(host: host, suiteName: "check-v0336-myrow-late-response")
    defer { myRowCancelTasks(store) }

    let flight = Task { await store.loadMyTokenRowIfDue(force: true) }
    await myRowWaitUntil { !MyTokenRowURLProtocol.requests(host: host, path: myRowBoardPath).isEmpty }
    #expect(store.myTokenRow == nil, "전제: 요청은 나갔고 응답은 아직이다")

    store.signOut()             // 세대가 올라간다(clearPersistedSession) — 이 시점 이후 완료되는 Task 는 무효다
    await flight.value

    #expect(store.myTokenRow == nil, "계정이 갈린 뒤 도착한 응답이 앞 사람 숫자를 팝오버에 심었다")
    #expect(defaults.data(forKey: WorkTimerStore.myTokenRowKey) == nil, "앞 사람 숫자가 디스크에 남았다")
}

// MARK: - 소스 계약 헬퍼(주석은 걷어내고 본다 — 안 그러면 설명을 지워야만 초록이 된다)

private func myRowSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
}

/// `func …` 선언부터 중괄호 균형이 맞는 자리까지.
private func myRowFunctionBody(of declaration: String, in source: String) -> Substring? {
    guard let start = source.range(of: declaration),
          let open = source.range(of: "{", range: start.upperBound..<source.endIndex)
    else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" {
            depth -= 1
            if depth == 0 { return source[open.upperBound..<index] }
        }
        index = source.index(after: index)
    }
    return nil
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다).
private func myRowStrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var index = source.startIndex
    while index < source.endIndex {
        let character = source[index]
        let next = source.index(after: index)
        let peek = next < source.endIndex ? source[next] : nil
        if inLineComment {
            if character == "\n" { inLineComment = false; result.append(character) }
        } else if inBlockComment {
            if character == "*", peek == "/" { inBlockComment = false; index = next }
        } else if inString {
            result.append(character)
            if character == "\\", peek != nil { result.append(peek!); index = next }
            else if character == "\"" { inString = false }
        } else if character == "/", peek == "/" {
            inLineComment = true
            index = next
        } else if character == "/", peek == "*" {
            inBlockComment = true
            index = next
        } else {
            if character == "\"" { inString = true }
            result.append(character)
        }
        index = source.index(after: index)
    }
    return result
}
