import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 가입 확인(OTP) 전용 URLProtocol 스텁
//
// 공유 URLProtocolStub 은 `/auth/v1/signup` 에 **언제나 세션**을 준다(= 지금 서버). 가입 확인을 켠 서버의 응답(세션 없이
// 사용자 객체만) · verify(type signup) · resend 는 이 스텁이 가로채고, 그 밖의 왕복(멤버십·팀 상태·합류·만들기)은 공유 스텁이
// 받는다 — 등록 순서 [이 클래스, URLProtocolStub] 이 그 분담이다(URLProtocolStub.canInit 은 무조건 true 라 뒤에 둬야 한다).
//
// **가입 응답을 가로채는 호스트는 이름으로 고른다**: "confirm"(세션 없음 · 확인 메일 나감) · "fakeuser"(이미 인증된 기존 계정 —
// identities 빈 가짜 사용자) · "dup"(옛 서버의 422). 그 밖의 호스트는 공유 스텁으로 흘려 **지금 서버 모드**를 그대로 재현한다.
// 이 두 갈래가 이 파일의 핵심이다 — 클라이언트는 설정을 켜기 전에 먼저 배포된다(SPEC-signup-otp).
final class SignUpOTPURLProtocolStub: URLProtocol {
    static let signupPath = "/auth/v1/signup"
    static let verifyPath = "/auth/v1/verify"
    static let resendPath = "/auth/v1/resend"
    static let tokenPath = "/auth/v1/token"
    static let membershipsPath = "/rest/v1/memberships"

    /// 공유 스텁의 픽스처(멤버십·팀 상태)가 같은 사용자 id 를 쓴다.
    static let userID = "00000000-0000-0000-0000-000000000002"
    static let accessToken = "signup-verified-token"
    static let refreshToken = "signup-verified-refresh"

    static let responseDelay: TimeInterval = 1.0
    static let delayedHostPrefix = "delayed-"

    private nonisolated(unsafe) static var recorded: [(host: String, path: String, body: String)] = []
    private static let stateLock = NSLock()

    /// 그 호스트로 실제로 나간 요청 경로(발사 순서).
    static func paths(forHost host: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.host == host }.map(\.path)
    }

    /// 그 호스트·경로로 나간 본문들(발사 순서).
    static func bodies(forHost host: String, path: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.host == host && $0.path == path }.map(\.body)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let path = request.url?.path, let host = request.url?.host else { return false }
        switch path {
        case signupPath:
            return host.contains("confirm") || host.contains("fakeuser") || host.contains("dup")
        case verifyPath, resendPath:
            return true
        case tokenPath:
            return host.contains("unconfirmed")
        case membershipsPath:
            return host.contains("teamless")
        default:
            return false
        }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped = false

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let body = Self.bodyText(from: request)
        Self.stateLock.lock()
        Self.recorded.append((host: host, path: path, body: body))
        Self.stateLock.unlock()

        let (statusCode, responseBody) = Self.outcome(host: host, path: path)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(responseBody.utf8))
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
        let proto: SignUpOTPURLProtocolStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: SignUpOTPURLProtocolStub, response: HTTPURLResponse, data: Data) {
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

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
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
        return String(decoding: data, as: UTF8.self)
    }

    /// 가입 확인을 켠 서버가 세션 없이 돌려주는 **사용자 객체 그대로**(user 봉투 없음 — GoTrue signup.go). 실서버 키 모양이다.
    private static func bareUserJSON(identities: String) -> String {
        """
        {
          "id": "\(userID)",
          "aud": "authenticated",
          "role": "",
          "email": "member@example.com",
          "confirmation_sent_at": "2026-09-18T09:00:00Z",
          "app_metadata": { "provider": "email", "providers": ["email"] },
          "user_metadata": { "display_name": "영식", "center": "seoul" },
          "identities": \(identities),
          "created_at": "2026-09-18T09:00:00Z",
          "updated_at": "2026-09-18T09:00:00Z",
          "is_anonymous": false
        }
        """
    }

    private static let realIdentities = """
        [{ "identity_id": "5b1c0e4a-0000-4000-8000-000000000001", "id": "\(userID)", "user_id": "\(userID)", "provider": "email" }]
        """

    private static func outcome(host: String, path: String) -> (Int, String) {
        switch path {
        case signupPath:
            if host.contains("dup") {
                // 지금 서버(가입 즉시 확인)의 중복 가입 — 422 그대로.
                return (422, #"{"code":422,"error_code":"user_already_exists","msg":"User already registered"}"#)
            }
            if host.contains("fakeuser") {
                // 가입 확인을 켠 서버가 **이미 인증된 기존 계정**에 돌려주는 가짜 사용자 — identities 만 빈 배열이다.
                return (200, bareUserJSON(identities: "[]"))
            }
            return (200, bareUserJSON(identities: realIdentities))
        case verifyPath:
            if host.contains("badcode") {
                return (403, #"{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#)
            }
            return (
                200,
                """
                {
                  "access_token": "\(accessToken)",
                  "token_type": "bearer",
                  "expires_in": 3600,
                  "refresh_token": "\(refreshToken)",
                  "user": { "id": "\(userID)", "email": "member@example.com", "identities": \(realIdentities) }
                }
                """
            )
        case resendPath:
            if host.contains("ratelimit") {
                return (
                    429,
                    #"{"code":429,"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after 51 seconds."}"#
                )
            }
            // 계정이 없어도, 이미 인증된 계정이어도 빈 200 이다(GoTrue).
            return (200, "{}")
        case tokenPath:
            return (400, #"{"code":400,"error_code":"email_not_confirmed","msg":"Email not confirmed"}"#)
        case membershipsPath:
            return (200, "[]")
        default:
            return (200, "{}")
        }
    }
}

private extension URLSessionConfiguration {
    static var signUpOTPStubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SignUpOTPURLProtocolStub.self, URLProtocolStub.self]
        return configuration
    }
}

/// 카운트다운 틱을 테스트가 쥐는 수동 시계 + 수면 게이트(PasswordResetStoreTests 의 CooldownTicker 와 같은 기계 —
/// 이 저장소의 테스트 도구는 파일마다 private 사본을 둔다). 얼려 두면 각 틱이 시계를 건드리지 않고 짧게 폴링만 하고,
/// release() 뒤에는 틱마다 시계를 앞으로 돌려 쿨다운을 **실시간 0초로** 소진한다.
private final class SignUpCooldownTicker: @unchecked Sendable {
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

    func release() {
        lock.lock()
        defer { lock.unlock() }
        released = true
    }

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

    func tick(_ seconds: Double) async {
        while !isReleased {
            do { try await Task.sleep(for: Self.pollInterval) } catch { return }
        }
        advance(seconds)
        await Task.yield()
    }

    private func advance(_ seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// 스토어의 시계와 카운트다운 수면을 테스트가 쥔 것으로 갈아 끼운다. 가입 확인은 재설정과 **같은 주입 지점**을 쓴다
/// (clock · passwordResetSleep) — 그래서 이 한 줄이 양쪽 카운트다운에 통한다.
@MainActor
private func freezeSignUpCooldownClock(_ store: WorkTimerStore) -> SignUpCooldownTicker {
    let ticker = SignUpCooldownTicker(Date())
    store.clock = { ticker.now() }
    store.passwordResetSleep = { await ticker.tick($0) }
    return ticker
}

private func awaitSignUpRequestSent(path: String, host: String) async {
    for _ in 0..<3000 {
        if SignUpOTPURLProtocolStub.paths(forHost: host).contains(path) { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// 테스트마다 새 스위트(이름·자리 모두 `CheckTestScratch` 규약 — $TMPDIR, 테스트 신원에서 뽑은 이름).
private func isolatedDefaults(_ label: String = "", function: String = #function) -> UserDefaults {
    CheckTestScratch.defaults(label, function: function)
}

@MainActor
private func makeSignUpStore(host: String, function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .signUpOTPStubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults(host, function: function)
    )
    _ = freezeSignUpCooldownClock(store)
    return store
}

/// 코드 모드 가입 폼을 채운다(가입 버튼 활성 조건 전부 — 미리보기 확인 + 센터 선택).
@MainActor
private func fillJoinSignUpForm(_ store: WorkTimerStore) {
    store.email = "Member@Example.com"
    store.password = "team-password"
    store.displayName = "영식"
    store.isCreateTeamMode = false
    store.signupTeamCode = "AINGTEAM"
    store.joinPreview = TeamJoinPreview(teamID: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40, memberCount: 3)
    store.signupCenter = CenterLabel.seoul
}

@MainActor
private func stopBackground(_ store: WorkTimerStore) {
    store.cancelSignUpConfirmation()
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
}

/// 코드가 통과하기 **전**의 불변식: 세션도, 디스크도, 배경 작업도, 팀 왕복도 없다. 계정은 서버에만(미확인으로) 있다.
@MainActor
private func expectNotSignedInAndNoTeamRoundTrip(_ store: WorkTimerStore, host: String) {
    #expect(!store.isSignedIn)
    #expect(store.session == nil)
    #expect(store.defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(store.refreshTask == nil)
    #expect(!store.membershipConfirmed)
    #expect(store.currentTeamID == nil)
    let shared = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.path }
    #expect(!shared.contains("/rest/v1/rpc/join_team"))
    #expect(!shared.contains("/rest/v1/rpc/create_team"))
    #expect(!shared.contains("/rest/v1/memberships"))
}

@Suite struct SignUpConfirmStoreTests {
    // MARK: 두 서버 모드 — 이 두 테스트가 SPEC 의 핵심 요구를 증명한다

    /// **지금 서버**(가입 즉시 세션): 예전과 완전히 같다 — 코드 화면을 띄우지 않고 곧장 팀 합류로 간다.
    /// verify·resend 는 한 발도 나가지 않는다.
    @MainActor
    @Test
    func legacyServerWithImmediateSessionNeverShowsTheCodeScreen() async {
        let host = "signup-otp-legacy-join"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)

        await store.signUp()?.value

        #expect(store.signUpConfirmPhase == .idle)
        #expect(store.signUpConfirmEmail == "")
        #expect(store.isSignedIn)
        #expect(store.currentTeamID == URLProtocolStub.stubTeamID)
        #expect(store.syncMessage == "동기화됨")
        // 이 스텁은 세션이 있는 가입을 가로채지 않는다 — verify/resend 가 나갔다면 여기 기록된다.
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host).isEmpty)
        let shared = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.path }
        #expect(shared.contains("/auth/v1/signup"))
        #expect(shared.contains("/rest/v1/rpc/join_team"))
    }

    /// **가입 확인을 켠 서버**(세션 없음): 코드 화면으로 가고, 팀 합류는 코드가 통과해 세션이 생긴 **뒤에** 이어진다.
    /// 요청 순서 증거는 시점별 기록이다 — 코드 화면에 선 동안 join_team 은 0건, verify 뒤에야 1건.
    @MainActor
    @Test
    func confirmationServerWithoutSessionEntersCodeScreenThenJoinsTeamAfterVerify() async {
        let host = "signup-otp-confirm-join"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)

        await store.signUp()?.value

        // 1) 세션이 없으니 코드 화면. 주소는 정규화돼 있고(verify 가 같은 문자열을 써야 한다), 첫 잠금은 5초다.
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmEmail == "member@example.com")
        #expect(store.signUpConfirmMessage == WorkTimerStore.signUpConfirmSentMessage)
        #expect(store.signUpConfirmResendSeconds == WorkTimerStore.passwordResetFirstResendDelaySeconds)
        #expect(store.syncMessage == "확인 메일 필요")
        #expect(store.password == "")
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)
        // 가입 요청이 첫 메일을 보냈으므로 여기서 resend 를 또 내지 않는다.
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host) == ["/auth/v1/signup"])

        // 2) 코드 입력(복사해 온 코드의 공백은 관대하게).
        await store.verifySignUpCode(code: "123 456")

        // 3) 세션이 생기고 **그 뒤에** 팀 합류 — 즉시 세션이 온 가입과 같은 마무리다.
        #expect(store.signUpConfirmPhase == .idle)
        #expect(store.signUpConfirmMessage == nil)
        #expect(store.isSignedIn)
        #expect(store.session?.accessToken == SignUpOTPURLProtocolStub.accessToken)
        #expect(store.currentTeamID == URLProtocolStub.stubTeamID)
        #expect(store.syncMessage == "동기화됨")
        #expect(store.refreshTask != nil)
        // 영속: 다음 실행이 이 세션으로 살아난다(재설정과 달리 가입 세션은 로그인 세션이다).
        #expect(store.defaults.string(forKey: WorkTimerStore.accessTokenKey) == SignUpOTPURLProtocolStub.accessToken)
        #expect(store.defaults.string(forKey: WorkTimerStore.emailKey) == "member@example.com")
        #expect(store.defaults.string(forKey: WorkTimerStore.displayNameKey) == "영식")
        // 가입 때 실어 보낸 센터 미러도 즉시 세션 경로와 같이 선다.
        #expect(store.myCenter == CenterLabel.seoul)
        #expect(store.myCenterLoaded)

        // verify 본문은 type signup 이다(recovery 면 서버가 403 을 주고, 화면은 "코드가 틀렸다"고 거짓말한다).
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host) == ["/auth/v1/signup", "/auth/v1/verify"])
        let verifyBody = SignUpOTPURLProtocolStub.bodies(forHost: host, path: "/auth/v1/verify").first ?? ""
        #expect(verifyBody.contains(#""type":"signup""#))
        #expect(verifyBody.contains(#""token":"123456""#))
        #expect(verifyBody.contains(#""email":"member@example.com""#))
        let shared = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.path }
        #expect(shared.filter { $0 == "/rest/v1/rpc/join_team" }.count == 1)
        #expect(URLProtocolStub.bodyText(forHost: host).contains(#""code":"AINGTEAM""#))
    }

    /// 만들기 모드도 같은 마무리를 지난다 — 코드가 통과한 뒤 create_team 이 나가고 참여코드 카드가 선다.
    @MainActor
    @Test
    func confirmationServerCreateModeCreatesTeamAfterVerify() async {
        let host = "signup-otp-confirm-create"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        store.email = "founder@example.com"
        store.password = "team-password"
        store.displayName = "창립자"
        store.isCreateTeamMode = true
        store.createTeamName = "새로운 팀"
        store.createTeamGoalHours = 50
        store.signupCenter = CenterLabel.busan

        await store.signUp()?.value
        #expect(store.signUpConfirmPhase == .enterCode)
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)

        await store.verifySignUpCode(code: "654321")
        #expect(store.isSignedIn)
        #expect(store.createdTeamCode == "X7K2M9Q4")
        let shared = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.path }
        #expect(shared.contains("/rest/v1/rpc/create_team"))
        #expect(!shared.contains("/rest/v1/rpc/join_team"))
    }

    // MARK: 코드 화면 안에서

    /// 코드 틀림/만료: 코드 화면에 머물고(다시 받기가 거기 있다) 세션도 팀 왕복도 없다. 6자리 미만은 왕복 전에 걸린다.
    @MainActor
    @Test
    func wrongCodeStaysOnCodeScreenWithoutSession() async {
        let host = "signup-otp-confirm-badcode"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)
        await store.signUp()?.value
        #expect(store.signUpConfirmPhase == .enterCode)

        await store.verifySignUpCode(code: "12345")
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmMessage == WorkTimerStore.passwordResetInvalidCodeMessage)
        #expect(!SignUpOTPURLProtocolStub.paths(forHost: host).contains("/auth/v1/verify"))

        await store.verifySignUpCode(code: "000000")
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmMessage == WorkTimerStore.passwordResetCodeRejectedMessage)
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host).filter { $0 == "/auth/v1/verify" }.count == 1)
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)
    }

    /// 재전송: 첫 잠금 5초가 풀리면 `/auth/v1/resend`(type signup)가 나가고, 그 뒤 잠금은 60초다.
    /// 잠금 중 누르면 서버로 나가지 않는다.
    @MainActor
    @Test
    func resendUsesFiveThenSixtySecondCooldownAndHitsResendEndpoint() async {
        let host = "signup-otp-confirm-resend"
        let store = makeSignUpStore(host: host)
        let ticker = freezeSignUpCooldownClock(store)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)
        await store.signUp()?.value
        #expect(store.signUpConfirmResendSeconds == 5)

        // 잠금 중 — 왕복 없음, 안내만.
        await store.resendSignUpCode()
        #expect(!SignUpOTPURLProtocolStub.paths(forHost: host).contains("/auth/v1/resend"))
        #expect(store.signUpConfirmMessage == WorkTimerStore.passwordResetCooldownMessage)
        #expect(store.signUpConfirmPhase == .enterCode)

        ticker.release()
        await store.signUpConfirmCooldownTask?.value
        #expect(store.signUpConfirmResendSeconds == 0)
        ticker.freeze()

        await store.resendSignUpCode()
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmMessage == WorkTimerStore.signUpConfirmResentMessage)
        #expect(store.signUpConfirmResendSeconds == WorkTimerStore.passwordResetResendCooldownSeconds)
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host) == ["/auth/v1/signup", "/auth/v1/resend"])
        let body = SignUpOTPURLProtocolStub.bodies(forHost: host, path: "/auth/v1/resend").first ?? ""
        #expect(body.contains(#""type":"signup""#))
        #expect(body.contains(#""email":"member@example.com""#))
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)
    }

    /// 429 는 서버가 준 남은 초가 우선이다(가입 요청의 첫 메일이 60초 안이면 서버가 그렇게 답한다).
    @MainActor
    @Test
    func rateLimitedResendAdoptsServerSeconds() async {
        let host = "signup-otp-confirm-ratelimit"
        let store = makeSignUpStore(host: host)
        let ticker = freezeSignUpCooldownClock(store)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)
        await store.signUp()?.value
        ticker.release()
        await store.signUpConfirmCooldownTask?.value
        ticker.freeze()

        await store.resendSignUpCode()
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmMessage == WorkTimerStore.passwordResetAlreadySentMessage)
        #expect(store.signUpConfirmResendSeconds == 51)
    }

    /// ★ 코드를 한 번 틀리면 [다시 받기]가 **영영 안 풀리던** 결함의 회귀.
    ///
    /// 카운트다운은 세대를 캡처해 매 틱 가드했는데, 검증(verifySignUpCode)이 왕복마다 그 세대를 올린다. 그래서 403 한 번에
    /// 카운트다운이 남은 초를 0 으로 내리지 못한 채 빠져나가고, 화면엔 회색 "다시 받기 (47초)" 가 굳었다 — 그 화면에서
    /// 재전송은 다시 열리지 않고 탈출구는 "로그인으로 돌아가기"뿐인데 화면이 그걸 말해 주지 않는다.
    ///
    /// 재는 것: 재전송 → 60초 → 틀린 코드 403 → 남은 초가 **계속 줄어 0** 이 되고 [다시 받기]가 실제로 다시 나간다.
    @MainActor
    @Test
    func failedVerifyKeepsTheResendCountdownRunning() async {
        let host = "signup-otp-confirm-badcode-cooldown"
        let store = makeSignUpStore(host: host)
        let ticker = freezeSignUpCooldownClock(store)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)
        await store.signUp()?.value
        #expect(store.signUpConfirmPhase == .enterCode)

        // 첫 잠금 5초를 실시간 없이 소진하고 재전송 — 이제 60초 잠금이다.
        ticker.release()
        await store.signUpConfirmCooldownTask?.value
        ticker.freeze()
        await store.resendSignUpCode()
        #expect(store.signUpConfirmResendSeconds == WorkTimerStore.passwordResetResendCooldownSeconds)
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host).filter { $0 == "/auth/v1/resend" }.count == 1)

        // 그 60초 안에 코드를 한 번 틀린다(403). 화면은 코드 화면에 머문다.
        await store.verifySignUpCode(code: "000000")
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmMessage == WorkTimerStore.passwordResetCodeRejectedMessage)
        // 틀렸다고 잠금이 풀리지도 않는다(서버 간격은 그대로다) — 굳는 것과 풀리는 것은 다른 결함이다.
        #expect(store.signUpConfirmResendSeconds > 0)

        // 카운트다운은 그 뒤로도 살아 있어야 한다: 남은 초가 0 까지 내려가고 버튼이 다시 열린다.
        ticker.release()
        await store.signUpConfirmCooldownTask?.value
        #expect(store.signUpConfirmResendSeconds == 0)
        ticker.freeze()
        #expect(
            PasswordResetFormModel(
                phase: .enterCode, email: "", code: "", newPassword: "",
                resendSeconds: store.signUpConfirmResendSeconds, message: nil, purpose: .signUpConfirmation
            ).isResendEnabled
        )

        // 회색으로 굳은 버튼이 아니다 — 실제로 한 발 더 나간다.
        await store.resendSignUpCode()
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host).filter { $0 == "/auth/v1/resend" }.count == 2)
    }

    /// 취소 뒤 **늦게 도착한 검증 성공**이 사람을 로그인시키지 않는다 — 닫힌 흐름의 세션은 버려진다.
    @MainActor
    @Test
    func cancelledVerifyDoesNotSignInWhenLateSuccessArrives() async {
        let host = "delayed-signup-otp-confirm-cancel"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)
        await store.signUp()?.value
        #expect(store.signUpConfirmPhase == .enterCode)

        let verify = Task { await store.verifySignUpCode(code: "123456") }
        await awaitSignUpRequestSent(path: "/auth/v1/verify", host: host)
        #expect(store.signUpConfirmPhase == .verifying)

        // 핸들을 떼어 놓고 취소한다 — 왕복이 끝까지 살아 성공 응답이 실제로 도착한다(세대 가드만이 막는다).
        store.signUpConfirmTask = nil
        store.cancelSignUpConfirmation()
        #expect(store.signUpConfirmPhase == .idle)
        await verify.value

        #expect(store.signUpConfirmPhase == .idle)
        #expect(store.signUpConfirmEmail == "")
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)
    }

    // MARK: 영영 막히지 않는 출구

    /// "이미 가입된 이메일"에는 **출구를 달지 않는다**(2026-09-18 배포 전 검토). 그 계정은 인증을 마친 계정이라
    /// 재전송해도 메일이 나가지 않는데 화면만 "새 코드를 보냈어요"라고 말한다 — 그 사람이 할 일은 로그인이다.
    /// 출구 자체가 도는지는 아래 "이메일 확인 필요" 테스트가 끝까지 잰다.
    @MainActor
    @Test
    func alreadyRegisteredDoesNotOfferTheCodeExit() async {
        let host = "signup-otp-dup-exit"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)

        await store.signUp()?.value
        #expect(store.syncMessage == "이미 가입된 이메일")
        #expect(store.signUpConfirmPhase == .idle)
        #expect(!WorkTimerStore.offersSignUpConfirmationExit(for: store.syncMessage),
                "오지 않을 메일을 기다리게 하는 출구다 — 이 문구엔 달지 않는다")
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host) == ["/auth/v1/signup"], "재전송이 나가면 안 된다")
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)
    }

    /// 출구를 **직접** 열었을 때의 흐름(로그인 카드의 "이메일 확인 필요"가 부르는 길과 같은 함수다):
    /// 재전송 → 코드 입력 → 세션 → 팀 합류(폼에 남은 팀 코드로).
    @MainActor
    @Test
    func theExitResendsAndVerifiesAndJoinsWithTheFormCode() async {
        let host = "signup-otp-dup-exit-flow"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)

        await store.signUp()?.value

        // 출구: 로그인 카드의 링크가 지금 입력된 이메일을 그대로 넘긴다.
        await store.beginSignUpConfirmation(email: store.email)
        #expect(store.signUpConfirmPhase == .enterCode)
        #expect(store.signUpConfirmEmail == "member@example.com")
        #expect(store.signUpConfirmMessage == WorkTimerStore.signUpConfirmResentMessage)
        #expect(store.signUpConfirmResendSeconds == WorkTimerStore.passwordResetFirstResendDelaySeconds)
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host) == ["/auth/v1/signup", "/auth/v1/resend"])
        expectNotSignedInAndNoTeamRoundTrip(store, host: host)

        await store.verifySignUpCode(code: "123456")
        #expect(store.isSignedIn)
        #expect(store.currentTeamID == URLProtocolStub.stubTeamID)
        #expect(store.defaults.string(forKey: WorkTimerStore.displayNameKey) == "영식")
    }

    /// 로그인으로 들어온 미확인 계정("이메일 확인 필요")도 같은 출구다. 팀 코드를 친 적이 없으니 합류 왕복은 없고
    /// **무소속으로 확정**된다 — 기존 무소속 패널(isTeamless)이 그 사람을 받는다.
    @MainActor
    @Test
    func unconfirmedLoginOffersExitAndLandsTeamlessWithoutTeamRoundTrip() async {
        let host = "signup-otp-unconfirmed-teamless"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        store.email = "member@example.com"
        store.password = "team-password"

        await store.signIn()?.value
        #expect(store.syncMessage == "이메일 확인 필요")
        #expect(WorkTimerStore.offersSignUpConfirmationExit(for: store.syncMessage))
        #expect(!store.isSignedIn)

        await store.beginSignUpConfirmation(email: store.email)
        #expect(store.signUpConfirmPhase == .enterCode)
        await store.verifySignUpCode(code: "123456")

        #expect(store.isSignedIn)
        #expect(store.isTeamless)
        #expect(store.membershipConfirmed)
        // 별명을 모르니 디스크의 별명은 세우지 않는다(서버 정본은 가입 때 섰다).
        #expect(store.defaults.string(forKey: WorkTimerStore.displayNameKey) == nil)
        let shared = URLProtocolStub.requests(forHost: host).compactMap { $0.url?.path }
        #expect(!shared.contains("/rest/v1/rpc/join_team"))
        #expect(!shared.contains("/rest/v1/rpc/create_team"))
    }

    /// 형식이 아닌 이메일로는 코드 화면을 열지 않는다(주소 칸이 없는 화면에 가두지 않는다) — 로그인 카드의 상태줄로 말한다.
    @MainActor
    @Test
    func exitRefusesImplausibleEmailWithoutOpeningTheCodeScreen() async {
        let host = "signup-otp-confirm-badmail"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }

        await store.beginSignUpConfirmation(email: "member")
        #expect(store.signUpConfirmPhase == .idle)
        #expect(store.syncMessage == WorkTimerStore.passwordResetInvalidEmailMessage)
        #expect(SignUpOTPURLProtocolStub.paths(forHost: host).isEmpty)
    }

    /// 가입 확인을 켠 서버는 **이미 인증된 기존 계정**의 가입에 200 + identities 빈 가짜 사용자를 준다. 그걸 코드 화면으로
    /// 보내면 오지 않을 메일을 기다린다 — 옛 서버의 422 와 같은 "이미 가입된 이메일"이어야 한다.
    @MainActor
    @Test
    func fakeUserResponseIsReportedAsAlreadyRegisteredNotAsCodeScreen() async {
        let host = "signup-otp-fakeuser"
        let store = makeSignUpStore(host: host)
        defer { stopBackground(store) }
        fillJoinSignUpForm(store)

        await store.signUp()?.value
        #expect(store.syncMessage == "이미 가입된 이메일")
        #expect(store.signUpConfirmPhase == .idle)
        #expect(!store.isSignedIn)
    }

    // MARK: 화면(순수 값)

    /// 가입 확인은 재설정의 **코드 화면 하나만** 빌린다: 재전송 왕복(sending) 중에도 이메일 화면으로 물러나지 않고,
    /// 부제는 "재설정"이 아니며, 발송 안내 둘은 안내(회색)로 그려진다.
    @Test
    func signUpConfirmationBorrowsOnlyTheCodeScreen() {
        func model(_ phase: PasswordResetPhase, message: String? = nil) -> PasswordResetFormModel {
            PasswordResetFormModel(
                phase: phase, email: "", code: "482913", newPassword: "", resendSeconds: 0, message: message,
                purpose: .signUpConfirmation
            )
        }
        #expect(model(.enterCode).step == .code)
        #expect(model(.verifying).step == .code)
        #expect(model(.sending).step == .code)
        #expect(model(.enterCode).headerSubtitle == "이메일 인증")
        #expect(model(.enterCode).primaryTitle == "코드 확인")
        #expect(model(.enterCode).primaryAction == .verifyCode(code: "482913"))
        #expect(model(.enterCode).showsResend)
        #expect(model(.sending).isBusy)
        #expect(model(.sending).noticeText == "코드 보내는 중")
        // 재설정 쪽은 그대로다(purpose 기본값) — 같은 phase 가 이메일 화면이다.
        #expect(PasswordResetFormModel(phase: .sending, email: "", code: "", newPassword: "", resendSeconds: 0, message: nil).step == .email)

        // 단계 매핑: 재전송은 sending, 나머지는 이름 그대로.
        #expect(SignUpConfirmPhase.idle.otpPanelPhase == .idle)
        #expect(SignUpConfirmPhase.enterCode.otpPanelPhase == .enterCode)
        #expect(SignUpConfirmPhase.verifying.otpPanelPhase == .verifying)
        #expect(SignUpConfirmPhase.resending.otpPanelPhase == .sending)
    }

    /// 코드 화면이 **말해야 하는 사실**. 두 앱이 같은 메일을 설명하므로 폰(MobileSignUpText)과 같은 낱말·띄어쓰기를 쓴다.
    ///
    /// ★ 재전송은 **앞 코드를 즉시 무효화한다**(프로덕션 실측). 첫 메일이 늦게 도착한 사람이 그 코드를 넣으면 403 인데,
    /// 안내가 그 사실을 말하지 않으면 왜 틀렸는지 알 길이 없다.
    @MainActor
    @Test
    func codeScreenNoticesMatchThePhoneAndSayTheOldCodeIsVoid() {
        // 첫 안내 — 폰과 같은 문장(낱말·띄어쓰기까지).
        #expect(WorkTimerStore.signUpConfirmSentMessage == "인증 코드를 보냈어요 · 안 오면 스팸함을 확인해 주세요")
        // 재전송 안내 — 앞 코드가 죽었다는 사실이 여기 있어야 한다.
        #expect(WorkTimerStore.signUpConfirmResentMessage == "새 코드를 보냈어요 · 앞 코드는 이제 쓸 수 없어요, 마지막 메일의 코드를 넣어 주세요")
        // "이미 인증된 계정" 이야기는 재전송 결과와 무관하게 늘 참이라 재전송 안내가 아니라 고정 안내 줄로 간다
        // (재전송을 눌러야만 보이면, 누르지 않은 사람은 영영 못 본다).
        #expect(!WorkTimerStore.signUpConfirmResentMessage.contains("이미 인증"))
        #expect(WorkTimerStore.signUpConfirmHelpMessage == "이미 인증을 마친 계정이면 메일이 오지 않아요 · 그때는 로그인해 주세요")

        // 고정 안내 줄은 가입 확인 코드 화면에만, 그리고 그 화면의 **모든 단계**에 붙는다(재전송 왕복 중에도 사라지지 않는다).
        func model(_ phase: PasswordResetPhase, _ purpose: OTPPanelPurpose) -> PasswordResetFormModel {
            PasswordResetFormModel(
                phase: phase, email: "", code: "", newPassword: "", resendSeconds: 0, message: nil, purpose: purpose
            )
        }
        #expect(model(.enterCode, .signUpConfirmation).codeScreenHelpText == WorkTimerStore.signUpConfirmHelpMessage)
        #expect(model(.verifying, .signUpConfirmation).codeScreenHelpText == WorkTimerStore.signUpConfirmHelpMessage)
        #expect(model(.sending, .signUpConfirmation).codeScreenHelpText == WorkTimerStore.signUpConfirmHelpMessage)
        // 재설정엔 "이미 인증된 계정"이라는 개념이 없다 — 그 화면엔 붙지 않는다.
        #expect(model(.enterCode, .passwordReset).codeScreenHelpText == nil)
        #expect(model(.enterNewPassword, .passwordReset).codeScreenHelpText == nil)
    }

    @MainActor
    @Test
    func signUpConfirmationNoticesAreInformationalAndExitLinkCarriesTheEmail() {
        #expect(PasswordResetFormModel.isInformational(WorkTimerStore.signUpConfirmSentMessage))
        #expect(PasswordResetFormModel.isInformational(WorkTimerStore.signUpConfirmResentMessage))
        #expect(!PasswordResetFormModel.isInformational(WorkTimerStore.passwordResetCodeRejectedMessage))

        // 출구는 **미확인 계정**을 뜻하는 두 문구에만 달린다. "이미 가입된 이메일"은 인증을 마친 계정이라
        // 재전송해도 메일이 안 간다 — 달면 오지 않을 메일을 기다리게 한다(2026-09-18 배포 전 검토).
        #expect(!WorkTimerStore.offersSignUpConfirmationExit(for: "이미 가입된 이메일"))
        #expect(WorkTimerStore.offersSignUpConfirmationExit(for: "이메일 확인 필요"))
        #expect(WorkTimerStore.offersSignUpConfirmationExit(for: "확인 메일 필요"))
        #expect(!WorkTimerStore.offersSignUpConfirmationExit(for: "로그인 필요"))
        #expect(!WorkTimerStore.offersSignUpConfirmationExit(for: "로그인 정보 오류"))

        final class Box: @unchecked Sendable { var received: [String] = [] }
        let box = Box()
        let link = SignUpConfirmEntryLink(email: "  member@example.com\n") { box.received.append($0) }
        link.press()
        #expect(box.received == ["member@example.com"])
    }

    // MARK: 코어 서비스

    /// verify 는 type signup · resend 는 type signup 이고, 거절은 재설정과 같은 값으로 재분류된다.
    @Test
    func coreSignUpOTPCallsUseSignupTypeAndReclassifyLikePasswordReset() async throws {
        let host = "signup-otp-core"
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        let session = try await service.verifySignUpCode(email: "member@example.com", code: "123456")
        #expect(session.accessToken == SignUpOTPURLProtocolStub.accessToken)
        #expect(session.refreshToken == SignUpOTPURLProtocolStub.refreshToken)
        #expect(session.userID == SignUpOTPURLProtocolStub.userID)
        #expect((SignUpOTPURLProtocolStub.bodies(forHost: host, path: "/auth/v1/verify").first ?? "").contains(#""type":"signup""#))

        try await service.resendSignUpCode(email: "member@example.com")
        #expect((SignUpOTPURLProtocolStub.bodies(forHost: host, path: "/auth/v1/resend").first ?? "").contains(#""type":"signup""#))

        let badCode = SupabaseWorkService(
            projectURL: URL(string: "http://signup-otp-core-badcode")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        do {
            _ = try await badCode.verifySignUpCode(email: "member@example.com", code: "000000")
            Issue.record("틀린 코드는 던져야 한다")
        } catch let error as SupabaseWorkServiceError {
            #expect(error == .otpInvalidOrExpired)
        }

        let limited = SupabaseWorkService(
            projectURL: URL(string: "http://signup-otp-core-ratelimit")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        do {
            try await limited.resendSignUpCode(email: "member@example.com")
            Issue.record("429 는 던져야 한다")
        } catch let error as SupabaseWorkServiceError {
            #expect(error == .rateLimited(retryAfterSeconds: 51))
        }
    }

    /// 세션 없는 가입 응답은 user 봉투가 아니라 **사용자 객체 그대로**다 — 그 모양이 nil 로 접히고, identities 빈 가짜
    /// 사용자는 .emailAlreadyRegistered 로 던져진다. 봉투 모양(지금 서버)은 종전대로 세션이다.
    @Test
    func signUpDecodesBothResponseShapes() async throws {
        let confirm = SupabaseWorkService(
            projectURL: URL(string: "http://signup-otp-core-confirm")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        let none = try await confirm.signUp(email: "member@example.com", password: "team-password", displayName: "영식")
        #expect(none == nil)

        let fake = SupabaseWorkService(
            projectURL: URL(string: "http://signup-otp-core-fakeuser")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        do {
            _ = try await fake.signUp(email: "member@example.com", password: "team-password", displayName: "영식")
            Issue.record("identities 빈 가짜 사용자는 던져야 한다")
        } catch let error as SupabaseWorkServiceError {
            #expect(error == .emailAlreadyRegistered)
        }

        let legacy = SupabaseWorkService(
            projectURL: URL(string: "http://signup-otp-core-legacy")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .signUpOTPStubbed)
        )
        let session = try await legacy.signUp(email: "member@example.com", password: "team-password", displayName: "영식")
        #expect(session?.accessToken == "signed-up-token")
    }

    // MARK: 소스 계약

    /// 두 경로(즉시 세션 · 코드 검증)가 **같은 마무리 함수** 하나를 지난다. 팀 합류/만들기 호출은 그 함수 안에만 있다 —
    /// 어느 쪽에서든 다시 직접 부르기 시작하면 두 벌이 되고, 한쪽만 고쳐지는 날이 온다.
    @Test
    func bothSignUpPathsEndInTheSameCompletion() throws {
        let auth = signUpStripped(try signUpSource("Sources/check/WorkTimerStoreAuth.swift"))
        let otp = signUpStripped(try signUpSource("Sources/check/WorkTimerStoreSignUpOTP.swift"))
        let menu = signUpStripped(try signUpSource("Sources/check/CheckMenuView.swift"))

        #expect(signUpOccurrences(of: "await joinTeamAfterSignup()", in: auth) == 1)
        #expect(signUpOccurrences(of: "await createTeamAfterSignup()", in: auth) == 1)
        #expect(signUpOccurrences(of: "await completeSignUp(", in: auth) == 1)
        #expect(signUpOccurrences(of: "await completeSignUp(", in: otp) == 1)
        #expect(!otp.contains("joinTeamAfterSignup"))
        #expect(!otp.contains("createTeamAfterSignup"))
        // nil 세션 갈래는 코드 화면으로 간다(옛 "확인 메일 필요" 한 줄로 끝나지 않는다).
        #expect(auth.contains("enterSignUpConfirmation(email: email, displayName: displayName, center: center)"))

        // 화면 배선: 코드 화면은 재설정 패널을 purpose 만 바꿔 빌리고, 로그인 카드에는 출구가 달린다.
        #expect(menu.contains("store.signUpConfirmPhase != .idle"))
        #expect(menu.contains("purpose: .signUpConfirmation"))
        #expect(menu.contains("SignUpConfirmEntryLink(email: store.email)"))
        #expect(menu.contains("store.beginSignUpConfirmation(email: email)"))
        #expect(menu.contains("WorkTimerStore.offersSignUpConfirmationExit(for: store.syncMessage)"))
        // 취소는 로그인 모드로 돌아간다(링크 글자 "로그인으로 돌아가기"와 같은 뜻).
        #expect(menu.contains("store.cancelSignUpConfirmation()"))
    }
}

// MARK: - 소스 계약 도우미(파일마다 private 사본을 두는 저장소 규약)

private func signUpSource(_ relative: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 저장소 루트
    return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
}

private func signUpOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// 주석(//, /* */)을 걷어낸 코드. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다(하우스 규칙).
/// 문자열 리터럴 안의 `//` 는 보존해야 하므로 따옴표 상태를 추적한다.
private func signUpStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let next = source.index(after: index) < source.endIndex ? source[source.index(after: index)] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = source.index(after: index) }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true
        } else if c == "/", next == "*" {
            inBlock = true
            index = source.index(after: index)
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}
