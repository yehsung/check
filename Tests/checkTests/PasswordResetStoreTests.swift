import Foundation
import Testing
@testable import check

// MARK: - 재설정 전용 URLProtocol 스텁
//
// 공유 URLProtocolStub 을 고치지 않는 이유는 두 가지다.
// (1) 그 파일은 이 트랙의 소유가 아니다(동시에 다른 트랙이 편집 중이다).
// (2) 그 스텁은 **미등록 경로에 200 + 빈 본문**을 준다. /auth/v1/verify 는 세션 JSON 을 디코드해야 하므로
//     빈 본문이면 '정상 흐름' 테스트가 디코드 실패로 떨어져 검증하려던 것을 아무것도 못 본다.
//
// 등록 순서는 반드시 [이 클래스, URLProtocolStub] 이다 — URLSession 은 배열 순서대로 canInit 을 물어
// 첫 승자를 쓰는데 URLProtocolStub.canInit 은 무조건 true 이기 때문이다. 이 순서 덕분에 재설정 3경로만
// 여기서 가로채고, 그 밖의 왕복(멤버십·팀 상태·개인 기록)은 공유 스텁이 받는다 — 그래서 "그쪽으로 한 발도
// 나가지 않았다"를 `URLProtocolStub.requests(forHost:)` 가 비었는지로 곧장 셀 수 있다(유령 상태 판정의 축).
final class PasswordResetURLProtocolStub: URLProtocol {
    static let recoverPath = "/auth/v1/recover"
    static let verifyPath = "/auth/v1/verify"
    static let updateUserPath = "/auth/v1/user"

    /// verify 가 돌려주는 세션. 재설정은 이제 로그인을 만들지 않지만, 이 값이 **어디에도 새지 않았는지**
    /// (스토어 session·UserDefaults) 를 단언하려면 여전히 식별 가능한 고정값이어야 한다.
    static let userID = "00000000-0000-0000-0000-000000000002"
    static let accessToken = "otp-access-token"
    static let refreshToken = "otp-refresh-token"

    /// "delayed-" 접두어 호스트의 응답 지연(초). 공유 스텁(0.15)보다 훨씬 긴 이유는 취소 창을 넉넉히 벌리기
    /// 위해서다 — 창이 좁으면 '늦게 도착한 응답' 재현이 무음으로 깨진다(공유 스텁 주석의 그 사고).
    /// 취소 시점은 고정 수면이 아니라 `awaitRequestSent` 관측으로 잡으므로 이 값은 창의 **폭**만 정한다.
    /// 877개 스위트가 동시에 도는 최악의 스케줄 지연까지 삼키도록 1초를 쓴다(테스트 2개 × 1초의 비용).
    static let responseDelay: TimeInterval = 1.0
    static let delayedHostPrefix = "delayed-"

    private nonisolated(unsafe) static var recorded: [(host: String, path: String)] = []
    private static let stateLock = NSLock()

    /// 그 호스트로 실제로 **나간** 재설정 요청 경로들(발사 순서). 사전 검증이 왕복을 막았는지 세는 자다.
    static func paths(forHost host: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.host == host }.map(\.path)
    }

    /// 그 호스트로 그 경로가 **몇 번째** 나갔는지(현재 요청 포함). "첫 시도만 거절" 시나리오의 판정에 쓴다.
    private static func callCount(host: String, path: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.host == host && $0.path == path }.count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let path = request.url?.path else { return false }
        return path == recoverPath || path == verifyPath || path == updateUserPath
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped = false

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.stateLock.lock()
        Self.recorded.append((host: host, path: path))
        Self.stateLock.unlock()

        let (statusCode, body) = Self.outcome(host: host, path: path)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(body.utf8))
        if host.hasPrefix(Self.delayedHostPrefix) {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {
        isStopped = true
    }

    private final class Delivery: @unchecked Sendable {
        let proto: PasswordResetURLProtocolStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: PasswordResetURLProtocolStub, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    /// 호스트 이름이 시나리오를 고른다(공유 스텁과 같은 규약).
    private static func outcome(host: String, path: String) -> (Int, String) {
        // 재발송 제한. 실서버 본문 그대로다 — 남은 초가 **문장 안에** 들어 있어야 서비스가 51 을 뽑아낸다.
        if host.contains("ratelimit"), path == recoverPath {
            return (
                429,
                #"{"code":429,"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after 51 seconds."}"#
            )
        }
        // 코드 불일치/만료. GoTrue 는 두 경우를 **같은 응답**으로 준다(계정 존재를 흘리지 않으려고).
        if host.contains("badcode"), path == verifyPath {
            return (403, #"{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#)
        }
        // 비밀번호 거절 → 재시도 성공. **첫 설정 시도만** 튕긴다: "거절돼도 보관 세션이 살아 있어 코드를 다시
        // 받지 않아도 된다"는 계약은 같은 흐름 안에서 실패 뒤 성공이 이어져야만 관측된다(verify 는 한 번뿐이어야 한다).
        if host.contains("rejectpass"), path == updateUserPath, callCount(host: host, path: path) == 1 {
            return (
                422,
                #"{"code":422,"error_code":"same_password","msg":"New password should be different from the old password."}"#
            )
        }
        if path == verifyPath {
            return (
                200,
                """
                {
                  "access_token": "\(accessToken)",
                  "refresh_token": "\(refreshToken)",
                  "user": { "id": "\(userID)" }
                }
                """
            )
        }
        // recover 는 계정이 없어도 200 이고, PUT /auth/v1/user 응답 본문은 서비스가 읽지 않는다.
        return (200, "{}")
    }
}

private extension URLSessionConfiguration {
    static var passwordResetStubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PasswordResetURLProtocolStub.self, URLProtocolStub.self]
        return configuration
    }
}

/// 카운트다운의 '틱'을 테스트가 쥐는 수동 시계 + 수면 게이트.
///
/// **왜 필요한가**: 재발송 카운트다운은 주입 clock 의 데드라인에서 남은 초를 매번 다시 계산한다. 시계를
/// 실시계로 두면 남은 초가 **테스트가 얼마나 느리게 도는지**에 따라 흔들린다 — 단독 실행에선 60, 전체
/// 스위트(877개) 부하에선 57 이 나왔다(실측 회귀). 시계를 얼면 그 축이 통째로 사라진다.
///
/// 두 모드가 필요한 이유: "발송 순간의 남은 초"를 단언하려면 카운트다운이 시작값에 **정지**해 있어야 하고,
/// "0 이 되면 다시 열린다"를 단언하려면 쿨다운을 **실시간 없이 소진**해야 한다. 그래서 release() 전에는 각 틱이
/// 시계를 건드리지 않고 취소 가능한 짧은 폴링으로만 대기하고, release() 뒤에는 각 틱이 시계를 즉시 앞으로 돌린다.
/// 어느 쪽이든 스토어가 Task 를 취소하면 그 자리에서 빠져나오므로 **테스트가 끝난 뒤 배경 Task 가 남지 않는다**
/// (기본 수면은 진짜 1초 Task.sleep 이라 최대 60초짜리 배경 루프를 스위트에 남겼다).
private final class CooldownTicker: @unchecked Sendable {
    /// 풀리기 전 대기 폴링 간격. 시계가 얼어 있어 **정확성은 이 값과 무관**하다 — 취소·해제에 반응하는
    /// 지연만 정한다(그래서 부하가 아무리 커져도 단언이 흔들리지 않는다).
    private static let pollInterval = Duration.milliseconds(5)

    private let lock = NSLock()
    private var current: Date
    private var released = false

    init(_ start: Date) { current = start }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// 이 시점부터 카운트다운이 실제로 흐른다(각 틱이 시계를 그만큼 앞으로 돌린다).
    func release() {
        lock.lock()
        defer { lock.unlock() }
        released = true
    }

    /// 다시 얼린다. 쿨다운 **두 단계**(첫 발송 5초 → 재전송 60초)를 한 테스트에서 보려면, 5초를 소진한 뒤
    /// 다시 얼고 나서 두 번째 카운트다운의 시작값을 읽어야 한다. 풀린 채로 두면 두 번째 카운트다운이
    /// 단언 전에 흘러 60 이 아니라 '그 사이 몇 틱 지난 값'이 잡힌다(무음 실패).
    func freeze() {
        lock.lock()
        defer { lock.unlock() }
        released = false
    }

    private var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    /// 스토어에 주입할 수면.
    func tick(_ seconds: Double) async {
        while !isReleased {
            // 취소되면 throw → 여기서 곧장 반환하고 카운트다운 루프도 함께 끝난다.
            do { try await Task.sleep(for: Self.pollInterval) } catch { return }
        }
        advance(seconds)
        await Task.yield()
    }

    /// 시계 전진. 별도 동기 메서드인 이유는 Swift 6 가 async 문맥에서 NSLock.lock() 을 금지하기 때문이다.
    private func advance(_ seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// 스토어의 시계와 카운트다운 수면을 테스트가 쥔 것으로 갈아 끼운다. **이 파일의 모든 테스트가 이걸 지난다** —
/// 하나라도 실시계로 남으면 스위트가 무거워지는 순간 그 테스트부터 빨개진다(이미 한 번 그렇게 깨졌다).
///
/// 시작 시각을 고정 날짜가 아니라 `Date()` 로 잡는 이유: 이 파일이 검증하는 것은 **경과**(남은 초)이지 달력이
/// 아니고, 스토어 초기화는 잠자기·자동 마감·주간 집계처럼 '지금이 언제인가'에 민감한 판정을 함께 지난다.
/// 임의의 과거로 옮기면 이 파일과 무관한 축에서 흔들릴 여지만 생긴다.
@MainActor
private func freezeCooldownClock(_ store: WorkTimerStore) -> CooldownTicker {
    let ticker = CooldownTicker(Date())
    store.clock = { ticker.now() }
    store.passwordResetSleep = { await ticker.tick($0) }
    return ticker
}

/// 그 요청이 실제로 **나갈 때까지** 기다린다(고정 수면 대신 관측). 고정 수면은 부하에서 창이 좁아져
/// 취소가 응답보다 늦게 도착하는 순간 테스트가 무음으로 뒤집힌다 — 관측은 그 축을 없앤다.
private func awaitRequestSent(path: String, host: String) async {
    for _ in 0..<3000 {
        if PasswordResetURLProtocolStub.paths(forHost: host).contains(path) { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-password-reset-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// **비로그인** 상태의 스텁 스토어. 세션을 미리 꽂지 않는 것이 핵심이다 — 재설정이 끝나도 여전히
/// 로그아웃이어야 한다는 것이 이 파일의 핵심 계약이라, 시작점이 반드시 로그아웃이어야 그 차이가 보인다.
@MainActor
private func makeResetStore(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .passwordResetStubbed)
    )
    return WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
}

/// 재설정이 끝난 뒤 **로그인도, 백그라운드도 시작되지 않았다**를 한곳에서 못 박는다.
///
/// 이 묶음이 따로 있는 이유: "자동 로그인을 뺐다"는 화면(phase)만 봐서는 확인되지 않는다. 세션이 디스크에
/// 남으면 다음 실행이 그 토큰으로 살아나고, 폴링/하트비트만 새어 시작되면 **로그아웃 화면인데 배경은 도는**
/// 유령 상태가 된다. 그 둘은 눈에 안 보이므로 반드시 값으로 센다.
@MainActor
private func expectNoSessionAndNoBackground(_ store: WorkTimerStore, host: String) {
    #expect(!store.isSignedIn)
    #expect(store.session == nil)
    // 영속 금지: 이 셋 중 하나라도 남으면 다음 실행의 restoreSession 이 recovery 토큰으로 로그인한다.
    #expect(store.defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(store.defaults.string(forKey: WorkTimerStore.emailKey) == nil)
    // completeSignIn 안에서만 시작되는 것들 — 하나라도 켜져 있으면 그 경로가 어딘가로 샜다는 뜻이다.
    #expect(store.refreshTask == nil)
    #expect(store.pokePollTask == nil)
    #expect(store.tickerTask == nil)
    #expect(!store.membershipConfirmed)
    #expect(store.currentTeamID == nil)
    // 멤버십·팀 상태·개인 기록은 전부 공유 스텁이 받는 경로다. 한 발이라도 나갔으면 여기서 잡힌다.
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@Suite struct PasswordResetStoreTests {
    /// 정상 흐름 전체: 이메일 → **코드만** → **새 비밀번호만** → 로그인 화면 복귀(로그인되지 않는다).
    ///
    /// 화면이 둘로 갈린 것과 자동 로그인이 빠진 것을 한 흐름에서 함께 본다 — 이 둘은 같은 동선의 앞뒤라
    /// 따로 떼면 "코드는 통과했는데 그 뒤 화면이 뭐였는지"를 아무도 단언하지 않는 틈이 생긴다.
    @MainActor
    @Test
    func fullResetFlowSplitsScreensAndReturnsToLogin() async {
        let host = "otp-happy"
        let store = makeResetStore(host: host)
        // 시계를 얼려 둔다(release 하지 않는다) — 아래 "발송 직후 남은 초" 단언이 전체 스위트 부하에서
        // 밀려 빨개진 회귀의 수리 지점이다. 얼린 시계에서는 데드라인 재계산이 항상 시작값을 준다.
        _ = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }
        #expect(!store.isSignedIn)

        store.beginPasswordReset(email: "  Member@Example.com ")
        #expect(store.passwordResetPhase == .enterEmail)
        // 로그인 폼 값을 그대로 받되 정규화해 둔다 — 발송과 검증이 같은 문자열이어야 GoTrue 가 같은 사용자로 본다.
        #expect(store.passwordResetEmail == "member@example.com")

        await store.requestPasswordResetCode(email: store.passwordResetEmail)
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetSentMessage)
        // **첫 발송**은 5초만 잠근다(맨 처음 메일은 실제로 안 올 수 있다). 60초가 아니다.
        #expect(store.passwordResetResendSeconds == WorkTimerStore.passwordResetFirstResendDelaySeconds)

        // ── 1단계: 코드만. 메일에서 복사한 코드에 공백이 섞여 와도 통과해야 한다(붙여넣기를 관대하게).
        await store.verifyPasswordResetCode(code: "123 456")

        // 코드가 통과하면 비밀번호 화면으로 넘어간다 — 그리고 **아직 로그인이 아니다**.
        #expect(store.passwordResetPhase == .enterNewPassword)
        #expect(store.passwordResetMessage == nil)
        // recovery 세션은 손에 쥐고만 있다(스토어 세션도, 디스크도 아니다).
        #expect(store.passwordResetVerifiedSession?.accessToken == PasswordResetURLProtocolStub.accessToken)
        expectNoSessionAndNoBackground(store, host: host)
        // 비밀번호 왕복은 아직 한 발도 나가지 않았다(두 화면이 정말 갈렸다는 뜻이다).
        #expect(!PasswordResetURLProtocolStub.paths(forHost: host).contains(PasswordResetURLProtocolStub.updateUserPath))

        // ── 2단계: 새 비밀번호만.
        await store.submitNewPassword("new-password")

        // 성공해도 **로그인하지 않는다** — 사용자가 새 비밀번호로 직접 로그인해야 한다.
        expectNoSessionAndNoBackground(store, host: host)

        // 재설정 화면은 통째로 닫히고 상태가 전부 청소된다(보관 세션도 함께 버려진다).
        #expect(store.passwordResetPhase == .idle)
        #expect(store.passwordResetMessage == nil)
        #expect(store.passwordResetEmail == "")
        #expect(store.passwordResetResendSeconds == 0)
        #expect(store.passwordResetVerifiedSession == nil)

        // 로그인 화면이 사용자를 맞이하는 방식: 이메일은 채워져 있고, 옛 비밀번호는 지워져 있고, 안내가 떠 있다.
        #expect(store.email == "member@example.com")
        #expect(store.password == "")
        #expect(store.syncMessage == WorkTimerStore.passwordResetChangedSignInMessage)

        // 실제로 3단계를 순서대로 밟았다(브라우저·딥링크 없이 앱 안에서 끝났다는 뜻).
        #expect(PasswordResetURLProtocolStub.paths(forHost: host) == ["/auth/v1/recover", "/auth/v1/verify", "/auth/v1/user"])
    }

    /// 비밀번호가 거절되면(이전과 동일 등) **비밀번호 화면에 머물고 보관 세션을 버리지 않는다.**
    /// 값만 고쳐 다시 누르면 코드 재입력 없이(=verify 왕복 없이) 통과해야 한다 — OTP 는 1회용이라
    /// 여기서 세션을 버리면 "비밀번호를 잘못 골랐다"는 이유로 코드부터 다시 받아야 한다.
    @MainActor
    @Test
    func rejectedPasswordStaysOnNewPasswordAndKeepsVerifiedSession() async {
        let host = "otp-rejectpass"
        let store = makeResetStore(host: host)
        _ = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")
        await store.verifyPasswordResetCode(code: "123456")
        #expect(store.passwordResetPhase == .enterNewPassword)

        // 1) 서버가 거절 — 화면도 세션도 그대로다.
        await store.submitNewPassword("old-password")
        #expect(store.passwordResetPhase == .enterNewPassword)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetRejectedPasswordMessage)
        #expect(store.passwordResetVerifiedSession?.accessToken == PasswordResetURLProtocolStub.accessToken)

        // 2) 사전 검증(6자 미만)에서 튕겨도 마찬가지다 — 서버로 나가지도 않는다.
        let beforeShort = PasswordResetURLProtocolStub.paths(forHost: host).count
        await store.submitNewPassword("12345")
        #expect(store.passwordResetPhase == .enterNewPassword)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetShortPasswordMessage)
        #expect(PasswordResetURLProtocolStub.paths(forHost: host).count == beforeShort)
        #expect(store.passwordResetVerifiedSession != nil)

        // 3) 값만 고쳐 다시 누르면 통과한다.
        await store.submitNewPassword("brand-new-password")
        #expect(store.passwordResetPhase == .idle)
        #expect(store.email == "member@example.com")
        #expect(store.syncMessage == WorkTimerStore.passwordResetChangedSignInMessage)
        expectNoSessionAndNoBackground(store, host: host)

        // 핵심 증거: verify 는 **한 번뿐**이다(=보관 세션을 재사용했다). 두 번이면 사용자가 코드를 다시
        // 받아야 했다는 뜻이고, 그 코드는 이미 소모돼 받을 수도 없다.
        let paths = PasswordResetURLProtocolStub.paths(forHost: host)
        #expect(paths.filter { $0 == PasswordResetURLProtocolStub.verifyPath }.count == 1)
        #expect(paths.filter { $0 == PasswordResetURLProtocolStub.updateUserPath }.count == 2)
    }

    /// 코드 틀림/만료: enterCode 에 머문다(비밀번호 화면으로 넘어가지 않는다). 설정 왕복은 아예 나가지 않는다.
    @MainActor
    @Test
    func wrongOrExpiredCodeStaysOnEnterCode() async {
        let host = "otp-badcode"
        let store = makeResetStore(host: host)
        // 단언이 카운트다운을 읽지는 않지만 얼려 둔다 — 기본 수면은 진짜 1초 Task.sleep 이라 테스트가 끝난 뒤에도
        // 최대 60초짜리 배경 루프를 스위트에 남긴다(부하를 키워 다른 테스트의 시간 의존을 깨우는 원인).
        _ = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetPhase == .enterCode)

        await store.verifyPasswordResetCode(code: "000000")

        // 화면을 이메일 단계로 되돌리지도, 비밀번호 단계로 넘기지도 않는다 — [다시 받기]가 있는 곳이 이 화면이다.
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetCodeRejectedMessage)
        #expect(store.passwordResetVerifiedSession == nil)
        // 검증에서 튕겼으니 비밀번호 설정 왕복은 없었다(있었다면 남의 계정 비밀번호를 바꿀 뻔했다는 뜻이다).
        #expect(!PasswordResetURLProtocolStub.paths(forHost: host).contains(PasswordResetURLProtocolStub.updateUserPath))
        expectNoSessionAndNoBackground(store, host: host)

        // 세션이 없으면 비밀번호 설정은 시작조차 못 한다 — 코드 화면으로 되돌려 다시 받게 한다.
        await store.submitNewPassword("new-password")
        #expect(store.passwordResetPhase == .enterCode)
        #expect(!PasswordResetURLProtocolStub.paths(forHost: host).contains(PasswordResetURLProtocolStub.updateUserPath))
    }

    /// 쿨다운 두 단계: **첫 발송 뒤 5초, 재전송 뒤 60초.**
    /// 5초가 필요한 이유는 첫 메일이 실제로 안 오는 일이 있어서고, 그 뒤 60초는 서버(GoTrue)가 강제하는 간격이다.
    @MainActor
    @Test
    func firstSendUnlocksInFiveSecondsThenResendLocksForSixty() async {
        let host = "otp-resend"
        let store = makeResetStore(host: host)
        let ticker = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetResendSeconds == 5)
        #expect(WorkTimerStore.passwordResetFirstResendDelaySeconds == 5)

        // 5초를 실시간 없이 소진한 뒤 **다시 얼어야** 두 번째 카운트다운의 시작값을 흔들림 없이 읽는다.
        ticker.release()
        await store.passwordResetCooldownTask?.value
        #expect(store.passwordResetResendSeconds == 0)
        ticker.freeze()

        // 재전송 — 이번엔 60초다. 같은 값을 두 번 쓰지 않는다는 것이 이 테스트의 전부다.
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetResendSeconds == WorkTimerStore.passwordResetResendCooldownSeconds)
        #expect(store.passwordResetResendSeconds == 60)
        #expect(PasswordResetURLProtocolStub.paths(forHost: host) == ["/auth/v1/recover", "/auth/v1/recover"])

        // 흐름을 다시 시작하면 차수도 0 으로 돌아간다 — 안 그러면 두 번째 흐름의 첫 발송이 60초로 잠긴다.
        store.cancelPasswordReset()
        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetResendSeconds == WorkTimerStore.passwordResetFirstResendDelaySeconds)
    }

    /// 429 는 **서버가 준 남은 초가 우선**이다. 서버의 `Minimum interval per user` 가 우리 5초보다 길면
    /// (지금 60초로 설정돼 있다) 우리 값을 그대로 쓰는 순간 사용자는 열린 버튼을 눌러 429 만 한 번 더 맞는다.
    /// 주입 시계 + 주입 수면이라 51초를 실시간으로 기다리지 않는다.
    @MainActor
    @Test
    func rateLimitedSendUsesServerSecondsOverLocalCooldown() async {
        let host = "otp-ratelimit"
        let store = makeResetStore(host: host)
        let ticker = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")

        // 429 여도 코드 입력 화면으로 넘긴다 — 메일은 이미 가는 중인데 이메일 화면에 붙잡아 두면
        // 받은 코드를 넣을 자리가 없다.
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetAlreadySentMessage)
        // 첫 발송이지만 로컬 기본값(5초)이 아니라 **서버가 말한 51초**로 잠긴다.
        #expect(store.passwordResetResendSeconds == 51)
        #expect(store.passwordResetResendSeconds != WorkTimerStore.passwordResetFirstResendDelaySeconds)

        // 쿨다운 중 [다시 받기]는 **서버로 나가지 않는다** — 헛왕복은 서버 카운터만 밀어 대기를 늘린다.
        let beforeRetry = PasswordResetURLProtocolStub.paths(forHost: host).count
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(PasswordResetURLProtocolStub.paths(forHost: host).count == beforeRetry)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetCooldownMessage)

        // 여기서 시계를 푼다 — 이 시점부터 각 틱이 시계를 1초씩 앞으로 돌려 51초를 **실시간 0초로** 소진한다.
        ticker.release()
        await store.passwordResetCooldownTask?.value
        #expect(store.passwordResetResendSeconds == 0)

        // 0 이 되면 다시 받을 수 있다 — 이번엔 요청이 실제로 나간다.
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(PasswordResetURLProtocolStub.paths(forHost: host).count == beforeRetry + 1)
    }

    /// 사전 검증: 이메일 형식·코드 6자리는 **서버 왕복 전에** 걸린다.
    @MainActor
    @Test
    func invalidInputIsRejectedBeforeAnyRequest() async {
        let host = "otp-validation"
        let store = makeResetStore(host: host)
        // 중간에 발송이 한 번 성공하므로 여기도 얼려 둔다(배경 루프를 스위트에 남기지 않는다).
        _ = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        // 1) 이메일 형식 — 왕복도, 쿨다운도 태우지 않는다.
        store.beginPasswordReset(email: "member")
        await store.requestPasswordResetCode(email: "member")
        #expect(store.passwordResetPhase == .enterEmail)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetInvalidEmailMessage)
        #expect(store.passwordResetResendSeconds == 0)
        #expect(PasswordResetURLProtocolStub.paths(forHost: host).isEmpty)

        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetPhase == .enterCode)
        let afterSend = PasswordResetURLProtocolStub.paths(forHost: host)

        // 2) 코드 자릿수 — 검증 왕복이 나가지 않고 코드 화면에 머문다.
        await store.verifyPasswordResetCode(code: "12345")
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetInvalidCodeMessage)
        #expect(PasswordResetURLProtocolStub.paths(forHost: host) == afterSend)
        expectNoSessionAndNoBackground(store, host: host)
    }

    /// 취소 후 **늦게 도착한 검증 성공 응답**이 흐름을 되살리지 않는다.
    ///
    /// Task 취소가 요청을 끊어 주는 것에 기대지 않는다: 핸들을 먼저 떼어 놓고 취소하면 왕복이 끝까지 살아서
    /// 성공 응답이 **실제로 도착한다**. 그래도 세대 가드가 상태를 되살리지 못하는지가 이 테스트의 전부다
    /// (이 코드베이스가 낡은 응답의 스냅백으로 여러 번 다친 그 지점이다). 되살아나면 사용자가 닫은 화면이
    /// 비밀번호 입력 단계로 다시 열리고, 그 안에 앞 사람의 recovery 세션이 들어 있게 된다.
    @MainActor
    @Test
    func cancelledVerifyDoesNotAdvanceWhenLateSuccessArrives() async {
        let host = "delayed-otp-cancel"
        let store = makeResetStore(host: host)
        _ = freezeCooldownClock(store)
        defer { store.cancelPasswordReset() }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")
        #expect(store.passwordResetPhase == .enterCode)

        let verify = Task { await store.verifyPasswordResetCode(code: "123456") }
        // 고정 수면 대신 **요청이 나갔음을 관측**한 뒤 취소한다. 고정 80ms 는 부하에서 창을 좁혀
        // (요청이 아직 안 떴는데 취소하거나, 응답이 먼저 도착하거나) 테스트를 무음으로 뒤집는다.
        await awaitRequestSent(path: PasswordResetURLProtocolStub.verifyPath, host: host)
        #expect(store.passwordResetPhase == .verifying)

        store.passwordResetTask = nil
        store.cancelPasswordReset()
        #expect(store.passwordResetPhase == .idle)

        // verify 는 in-flight 왕복이 끝나야 반환한다 = 늦은 성공 응답이 전부 처리된 뒤다.
        await verify.value

        // 취소가 청소한 상태를 늦은 응답이 되살리지 않았다.
        #expect(store.passwordResetPhase == .idle)
        #expect(store.passwordResetMessage == nil)
        #expect(store.passwordResetEmail == "")
        #expect(store.passwordResetVerifiedSession == nil)
        expectNoSessionAndNoBackground(store, host: host)
    }

    /// sending 중 취소도 항상 가능하고, 그 뒤 도착하는 발송 응답이 화면을 코드 입력으로 되돌리지 않는다.
    @MainActor
    @Test
    func cancelDuringSendingReturnsToIdle() async {
        let host = "delayed-otp-sending-cancel"
        let store = makeResetStore(host: host)
        _ = freezeCooldownClock(store)

        store.beginPasswordReset(email: "member@example.com")
        let send = Task { await store.requestPasswordResetCode(email: "member@example.com") }
        // 고정 수면이 아니라 관측으로 취소 시점을 잡는다(부하에서 창이 좁아지지 않게).
        await awaitRequestSent(path: PasswordResetURLProtocolStub.recoverPath, host: host)
        #expect(store.passwordResetPhase == .sending)

        store.passwordResetTask = nil
        store.cancelPasswordReset()
        await send.value

        #expect(store.passwordResetPhase == .idle)
        #expect(store.passwordResetMessage == nil)
        #expect(store.passwordResetEmail == "")
        #expect(store.passwordResetResendSeconds == 0)
    }
}
