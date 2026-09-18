import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 가입 이메일 인증코드(w16 · SPEC-signup-otp 작업 P).
///
/// ★ 이 스위트의 **첫 두 테스트가 SPEC 의 핵심 요구**다 — 클라이언트는 서버 설정(`enable_confirmations`)을 켜기 **전에**
///   배포되므로 두 서버 모드를 다 견뎌야 한다:
///   - `legacyServerImmediateSessionNeverShowsCodeScreen`: 지금 서버(가입 즉시 세션) → 코드 화면을 띄우지 않는다. verify·resend 0건.
///   - `confirmationServerWithoutSessionEntersCodeThenJoinsAfterVerify`: 설정을 켠 서버(세션 없음) → 코드 화면, 팀 합류는 **verify 뒤**.
///
/// 나머지는 실측한 응답(2026-09-18 프로덕션에서 설정을 잠깐 켜고 직접 찍은 것)을 그대로 다룬다:
/// 이미 인증된 이메일은 422 가 아니라 `identities: []` 가짜 사용자 200 · 429 는 오류가 아니라 "몇 초 뒤 다시" ·
/// 틀린 코드와 만료가 같은 403 · **재전송은 앞 코드를 무효화한다** · 미확인 상태로 앱을 닫은 사람의 출구.
@MainActor
@Suite struct BaseSignUpConfirmTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let clock: BaseTestClock
        let service: SupabaseWorkService
        let session: MobileSessionStore
        let store: MobileSignUpStore
        /// 쿨다운 1초 대기가 기다리는 문(벽시계 없음). 열기 전엔 남은 초가 처음 값에 멈춰 있다.
        let sleepGate: BaseGate

        var requests: [MobileStubRequest] { baseRequests(host: host) }
        func count(path: String) -> Int { requests.filter { $0.path == path }.count }
        func count(rpc: String) -> Int { requests.filter { $0.rpcName == rpc }.count }
        func body(path: String) -> String { requests.first { $0.path == path }?.bodyText ?? "" }
        func lastBody(path: String) -> String { requests.last { $0.path == path }?.bodyText ?? "" }
        func paths() -> [String] { requests.map { $0.rpcName.map { "rpc/\($0)" } ?? $0.path } }

        @MainActor
        func tearDown() {
            store.cancelPendingWork()
            sleepGate.open()
            BaseStub.tearDown(host: host, storage: storage)
        }
    }

    nonisolated static let verifiedAccess = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), subject: "user-new", salt: "otp")

    /// **설정을 켠 서버의 가입 응답**: 봉투 없는 사용자 객체(access_token 없음 · email_confirmed_at null · identities 한 줄).
    /// 실측 1번 응답을 그대로 옮겼다 — 진짜 새 계정은 identities 가 비지 않는다(빈 배열은 "이미 인증된 계정"의 가짜 사용자다).
    nonisolated static let pendingUser = #"""
    {"id":"user-new","aud":"authenticated","role":"","email":"member@example.com","confirmation_sent_at":"2026-09-18T05:00:00Z","email_confirmed_at":null,"identities":[{"identity_id":"id-1","provider":"email"}]}
    """#
    /// **이미 인증된 이메일로 가입**: 422 가 아니라 200 + `identities: []` 인 가짜 사용자(실측 4번).
    nonisolated static let fakeUser = #"""
    {"id":"00000000-0000-0000-0000-000000000000","aud":"authenticated","role":"","email":"member@example.com","identities":[]}
    """#
    /// 429 over_email_send_rate_limit(실측 5번) — 남은 초가 본문에 들어 있다.
    nonisolated static func rateLimited(seconds: Int) -> MobileStubResponse {
        .json(#"{"code":429,"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after \#(seconds) seconds."}"#, status: 429)
    }
    /// 403 otp_expired(실측 6번) — 틀린 코드와 만료가 **같은 응답**이다.
    nonisolated static let otpExpired = MobileStubResponse.json(
        #"{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#,
        status: 403
    )

    /// 가입 넷(lookup · signup · join · create) + 인증코드 둘(verify · resend). 바꾸고 싶은 답만 넘긴다.
    /// `signup` 을 안 넘기면 **지금 서버**(가입 즉시 세션)다 — 기본이 곧 오늘의 프로덕션이어야 회귀가 눈에 띈다.
    static func server(
        signup: MobileStubResponse? = nil,
        verify: MobileStubResponse? = nil,
        resend: MobileStubResponse? = nil,
        join: MobileStubResponse? = nil,
        create: MobileStubResponse? = nil
    ) -> MobileStubURLProtocol.Responder {
        BaseSessionTests.happyServer(extra: { request in
            switch request.rpcName {
            case "lookup_team_by_code": return .json(BaseSignUpTests.previewRow)
            case "join_team": return join ?? .json(BaseSignUpTests.joinRow)
            case "create_team": return create ?? .json(BaseSignUpTests.createRow)
            default: break
            }
            switch request.path {
            case "/auth/v1/signup":
                return signup ?? BaseStub.authResponse(access: BaseSignUpTests.freshAccess, refresh: "refresh-new", userID: "user-new")
            case "/auth/v1/verify":
                return verify ?? BaseStub.authResponse(access: verifiedAccess, refresh: "refresh-otp", userID: "user-new")
            case "/auth/v1/resend":
                return resend ?? .json("{}")
            default:
                return nil
            }
        })
    }

    func makeHarness(createTeam: Bool = false, responder: @escaping MobileStubURLProtocol.Responder) async -> Harness {
        let host = BaseStub.makeHost("signup-otp")
        MobileStubURLProtocol.register(host: host, responder: responder)
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        let clock = BaseTestClock()
        let service = BaseStub.makeService(host: host)
        let session = MobileSessionStore(
            service: service,
            vault: vault,
            storage: storage,
            appInfo: BaseStub.appInfo,
            installationID: "11111111-2222-4333-8444-555555555555",
            clock: clock.clock
        )
        session.clientReleaseTimeoutSeconds = 0
        await session.launch()
        MobileStubURLProtocol.clearRequests(host: host)
        let store = MobileSignUpStore(session: session, createTeam: createTeam)
        let gate = BaseGate()
        store.sleep = { _ in await gate.wait() }
        return Harness(host: host, storage: storage, vault: vault, clock: clock, service: service, session: session, store: store, sleepGate: gate)
    }

    /// 맥 테스트(`fillJoinSignUpForm`)와 같은 입력 — 코드 미리보기까지 세워 둔다(가입이 시작될 수 있는 상태).
    func fillJoinForm(_ h: Harness) async {
        h.store.displayName = "영식"
        h.store.email = "Member@Example.com"
        h.store.password = "team-password"
        h.store.center = CenterLabel.seoul
        h.store.teamCode = "AINGTEAM"
        await h.store.previewTeamCode().value
    }

    // MARK: - 두 서버 모드(SPEC 의 핵심 요구 — 이 둘이 증명한다)

    @Test("지금 서버(가입 즉시 세션): 코드 화면을 띄우지 않고 예전과 같은 길로 간다 — verify·resend 는 한 발도 안 나간다")
    func legacyServerImmediateSessionNeverShowsCodeScreen() async throws {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        await fillJoinForm(h)

        await h.store.submit()?.value

        #expect(h.store.stage != .confirmCode, "지금 서버에서 코드 화면이 떴다")
        #expect(h.store.confirmSentEmail == "")
        #expect(h.store.resendSeconds == 0)
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.accessToken == BaseSignUpTests.freshAccess)
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/verify") == 0)
        #expect(h.count(path: "/auth/v1/resend") == 0)
        #expect(h.count(rpc: "join_team") == 1)
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("설정을 켠 서버(세션 없음): 코드 화면으로 가고 팀 합류는 verify 뒤에 — 코드 화면에 선 동안 join_team 은 0건")
    func confirmationServerWithoutSessionEntersCodeThenJoinsAfterVerify() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.pendingUser)))
        defer { h.tearDown() }
        await fillJoinForm(h)

        await h.store.submit()?.value

        // 1) 코드 화면. 주소는 **정규화**돼 있고(verify 가 같은 문자열을 써야 한다), 첫 잠금은 재설정과 같은 5초다.
        #expect(h.store.stage == .confirmCode)
        #expect(h.store.confirmSentEmail == "member@example.com")
        #expect(h.store.notice == MobileSignUpText.confirmSent)
        #expect(!h.store.noticeIsError, "발송 안내가 빨갛게 그려진다")
        #expect(h.store.resendSeconds == MobilePasswordResetStore.firstResendDelaySeconds)
        #expect(h.store.password == "", "계정은 만들어졌다 — 비밀번호를 화면에 남기지 않는다")
        #expect(h.store.primaryTitle == MobileSignUpText.verifyCode)
        #expect(h.session.phase == .signedOut)
        await baseBarrier(h.service)
        #expect(h.count(rpc: "join_team") == 0, "세션도 없이 팀에 합류를 시도했다")
        #expect(h.count(path: "/auth/v1/resend") == 0, "첫 메일은 가입 요청이 보냈다 — 여기서 또 보내지 않는다")

        // 버튼은 6자리가 찼을 때만 열린다(빈 코드로 왕복해 레이트리밋을 태우지 않는다).
        #expect(!h.store.isPrimaryEnabled(code: "12345"))
        #expect(h.store.isPrimaryEnabled(code: "123 456"))
        #expect(!h.store.canSubmit)
        #expect(h.store.submit() == nil, "코드 화면의 주 버튼이 submit() 으로 새면 팀 단계를 건너뛴다")

        // 2) 코드 입력(메일에서 복사한 공백은 관대하게) → 세션 → **그 뒤에** 팀 합류.
        await h.store.verifyCode("123 456")

        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.accessToken == Self.verifiedAccess)
        #expect(h.session.storedEmail == "member@example.com")
        #expect(h.vault.read(AingKeychain.accessTokenKey) == Self.verifiedAccess, "키체인에 저장됐다(로그인과 같은 길)")
        #expect(h.store.notice == nil)
        #expect(h.store.resendSeconds == 0)
        #expect(h.count(rpc: "join_team") == 1)
        #expect(h.count(path: "/auth/v1/signup") == 1, "계정을 또 만들었다")

        // verify 본문은 **type signup** 이다(recovery 면 서버가 403 을 주고 화면은 "코드가 틀렸다"고 거짓말한다).
        let verifyBody = h.body(path: "/auth/v1/verify")
        #expect(verifyBody.contains(#""type":"signup""#))
        #expect(verifyBody.contains(#""token":"123456""#))
        #expect(verifyBody.contains(#""email":"member@example.com""#))
        // 순서: signup → verify → join_team. 합류는 방금 받은 세션 토큰으로.
        let paths = h.paths()
        let signupIndex = try #require(paths.firstIndex(of: "/auth/v1/signup"))
        let verifyIndex = try #require(paths.firstIndex(of: "/auth/v1/verify"))
        let joinIndex = try #require(paths.firstIndex(of: "rpc/join_team"))
        #expect(signupIndex < verifyIndex && verifyIndex < joinIndex)
        #expect(h.requests.first { $0.rpcName == "join_team" }.map(BaseStub.bearer) == "Bearer \(Self.verifiedAccess)")
        #expect(h.body(path: "/rest/v1/rpc/join_team").contains(#""code":"AINGTEAM""#))
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("설정을 켠 서버 · 팀 만들기 모드도 같은 마무리를 지난다 — verify 뒤에 create_team, join_team 은 0건")
    func confirmationServerCreateModeCreatesTeamAfterVerify() async throws {
        let h = await makeHarness(createTeam: true, responder: Self.server(signup: .json(Self.pendingUser)))
        defer { h.tearDown() }
        h.store.displayName = "창립자"
        h.store.email = "founder@example.com"
        h.store.password = "team-password"
        h.store.center = CenterLabel.busan
        h.store.createTeamName = "새로운 팀"
        h.store.createTeamGoalHours = 50

        await h.store.submit()?.value
        #expect(h.store.stage == .confirmCode)
        await baseBarrier(h.service)
        #expect(h.count(rpc: "create_team") == 0)

        await h.store.verifyCode("654321")
        #expect(h.store.stage == .createdTeam(code: "X7K2M9Q4"))
        #expect(h.count(rpc: "create_team") == 1)
        #expect(h.count(rpc: "join_team") == 0)
        #expect(h.session.phase == .signedOut, "참여코드 카드 단계 — [시작하기] 전")

        await h.store.submit()?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.accessToken == Self.verifiedAccess)
    }

    // MARK: - 코드 화면 안에서

    @Test("틀린 코드와 만료는 같은 403 otp_expired — 문구도 하나이고 코드 화면에 머문다 · 6자리 미만은 왕복 전에 걸린다")
    func wrongCodeStaysOnCodeScreen() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.pendingUser), verify: Self.otpExpired))
        defer { h.tearDown() }
        await fillJoinForm(h)
        await h.store.submit()?.value
        #expect(h.store.stage == .confirmCode)

        await h.store.verifyCode("12345")
        #expect(h.store.notice == MobilePasswordResetText.invalidCode)
        #expect(h.store.noticeIsError)
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/verify") == 0, "6자리가 안 되는데 왕복했다")

        await h.store.verifyCode("000000")
        #expect(h.store.stage == .confirmCode, "코드가 틀렸다고 가입 폼으로 되돌리면 계정이 둘이 된다")
        #expect(h.store.notice == MobilePasswordResetText.codeRejected)
        #expect(h.count(path: "/auth/v1/verify") == 1)
        #expect(h.session.phase == .signedOut)
        #expect(h.count(rpc: "join_team") == 0)
        // 다시 받기는 그 화면에 있다(첫 잠금이 풀린 뒤).
        #expect(h.store.resendSeconds > 0)
    }

    @Test("재전송: 잠금 중엔 왕복 없음 · 풀리면 type signup 으로 나가고 **앞 코드 무효화**를 문구로 말한다 · 그 뒤 잠금은 60초")
    func resendInvalidatesPreviousCodeAndSaysSo() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.pendingUser)))
        defer { h.tearDown() }
        await fillJoinForm(h)
        await h.store.submit()?.value
        #expect(h.store.resendSeconds == 5)
        #expect(!h.store.isResendEnabled)
        #expect(h.store.resendTitle == "다시 받기 (5초)")

        await h.store.resendCode()
        #expect(h.store.notice == MobilePasswordResetText.cooldown)
        #expect(!h.store.noticeIsError, "쿨다운 안내가 빨갛게 그려진다")
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/resend") == 0, "잠금 중 헛왕복 — 서버 카운터만 밀어 대기를 늘린다")

        // 시계를 5초 넘기고 카운트다운을 한 틱 돌린다(벽시계 대기 없음).
        h.clock.advance(5)
        h.sleepGate.open()
        #expect(await baseWaitUntil { h.store.resendSeconds == 0 })
        #expect(h.store.isResendEnabled)
        #expect(h.store.resendTitle == "다시 받기")

        await h.store.resendCode()
        #expect(h.count(path: "/auth/v1/resend") == 1)
        let resendBody = h.body(path: "/auth/v1/resend")
        #expect(resendBody.contains(#""type":"signup""#))
        #expect(resendBody.contains(#""email":"member@example.com""#))
        // ★ 실측 7번: 재전송은 앞 코드를 무효화한다 — 그 사실이 문구에 없으면 사용자는 첫 메일의 코드를 계속 넣고 403 만 본다.
        #expect(h.store.notice == MobileSignUpText.confirmResent)
        #expect(h.store.notice?.contains("마지막 메일") == true)
        #expect(!h.store.noticeIsError)
        #expect(h.store.resendSeconds == MobilePasswordResetStore.resendCooldownSeconds, "재전송 뒤 잠금은 60초")
        #expect(h.store.stage == .confirmCode)
        #expect(h.session.phase == .signedOut)
    }

    @Test("재전송 429: 오류가 아니라 '이미 보냈어요' + **서버가 준 남은 초**로 잠근다")
    func resendRateLimitUsesServerSeconds() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.pendingUser), resend: Self.rateLimited(seconds: 47)))
        defer { h.tearDown() }
        await fillJoinForm(h)
        await h.store.submit()?.value
        h.clock.advance(5)
        h.sleepGate.open()
        #expect(await baseWaitUntil { h.store.resendSeconds == 0 })

        await h.store.resendCode()
        #expect(h.store.notice == MobilePasswordResetText.alreadySent)
        #expect(!h.store.noticeIsError, "429 를 오류로 그리면 사용자는 더 빨리 다시 눌러 대기를 늘린다")
        #expect(h.store.resendSeconds == 47, "남은 초는 서버가 진실이다")
        #expect(h.store.stage == .confirmCode)
    }

    @Test("가입 자체가 429: 오류(연결 확인)가 아니라 '조금 뒤에 다시' + 남은 초 · 계정 칸에 머문다")
    func signUpRateLimitSaysWaitNotNetworkError() async throws {
        let h = await makeHarness(responder: Self.server(signup: Self.rateLimited(seconds: 12)))
        defer { h.tearDown() }
        await fillJoinForm(h)

        await h.store.submit()?.value
        #expect(h.store.stage == .account)
        #expect(h.store.notice == MobileSignUpText.rateLimited(seconds: 12))
        #expect(h.store.notice != MobileSessionText.network, "429 를 연결 문제로 말하면 사용자는 인터넷을 의심한다")
        #expect(!h.store.noticeIsError)
        #expect(h.session.phase == .signedOut)
    }

    // MARK: - 미확인 상태로 앱을 닫은 사람의 출구(이게 없으면 그 계정은 영영 못 쓴다)

    @Test("이미 인증된 이메일로 가입: 200 + identities 빈 가짜 사용자를 '이미 가입된 이메일'로 판정하고 코드 화면 출구를 연다")
    func alreadyRegisteredFakeUserOffersExit() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.fakeUser)))
        defer { h.tearDown() }
        await fillJoinForm(h)

        await h.store.submit()?.value
        // 422 가 아니라 200 이다 — 세션 없음을 코드 화면으로 오해하면 영영 오지 않을 메일을 기다린다.
        #expect(h.store.stage == .account)
        #expect(h.store.notice == AuthErrorRules.message(for: SupabaseWorkServiceError.emailAlreadyRegistered, fallback: ""))
        #expect(h.store.offersConfirmationExit, "출구가 없으면 미확인 계정은 운영자가 풀어 주기 전까지 못 쓴다")
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/verify") == 0)

        // 출구 → 재전송 → 코드 화면. 계정은 이미 있으므로 signup 은 다시 나가지 않는다.
        await h.store.beginConfirmation(email: "  Member@Example.com ")
        #expect(h.store.stage == .confirmCode)
        #expect(h.store.confirmSentEmail == "member@example.com")
        #expect(h.count(path: "/auth/v1/resend") == 1)
        #expect(h.count(path: "/auth/v1/signup") == 1)
        #expect(h.store.notice == MobileSignUpText.confirmSent, "첫 발송이라 '앞 코드 무효화' 문구를 쓰면 거짓말이다")
        #expect(h.store.resendSeconds == MobilePasswordResetStore.firstResendDelaySeconds)
        #expect(!h.store.offersConfirmationExit, "코드 화면 안에서는 출구를 또 달지 않는다")

        // 코드가 통과하면 세션이 서고, 팀 칸이 비어 있으므로 무소속 화면에서 팀을 정한다(빈 코드로 join_team 을 부르지 않는다).
        h.store.teamCode = ""
        h.store.joinPreview = nil
        await h.store.verifyCode("123456")
        #expect(h.store.stage == .teamless)
        #expect(h.store.createdSession?.accessToken == Self.verifiedAccess)
        #expect(h.session.phase == .signedOut)
        #expect(h.count(rpc: "join_team") == 0, "빈 코드로 합류를 부르면 0행이 와 '다른 센터 팀' 이라고 거짓말한다")

        // 같은 화면에서 코드를 치면 로그인과 같은 길로 들어간다.
        h.store.teamCode = "AINGTEAM"
        await h.store.previewTeamCode().value
        await h.store.submit()?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.count(rpc: "join_team") == 1)
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("출구 판정은 코어 매퍼의 문장을 읽는다(로그인 화면의 '이메일 확인 필요' 포함) · 형식이 아닌 주소로는 코드 화면을 열지 않는다")
    func exitRulesFollowCoreMessages() async throws {
        #expect(MobileSignUpStore.offersConfirmationExit(for: AuthErrorRules.message(for: SupabaseWorkServiceError.emailNotConfirmed, fallback: "")))
        #expect(MobileSignUpStore.offersConfirmationExit(for: AuthErrorRules.message(for: SupabaseWorkServiceError.emailAlreadyRegistered, fallback: "")))
        #expect(!MobileSignUpStore.offersConfirmationExit(for: AuthErrorRules.message(for: SupabaseWorkServiceError.invalidLoginCredentials, fallback: "")))
        #expect(!MobileSignUpStore.offersConfirmationExit(for: MobileSessionText.network))

        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        await h.store.beginConfirmation(email: "no-at-sign")
        #expect(h.store.stage == .account, "코드 화면엔 주소 칸이 없다 — 형식이 틀리면 열지 않는다")
        #expect(h.store.notice == MobilePasswordResetText.invalidEmail)
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/resend") == 0)
    }

    @Test("화면을 떠나도 계정은 미확인으로 남고 카운트다운만 끊긴다 · 늦게 온 verify 응답이 사용자를 로그인시키지 않는다")
    func leavingScreenDropsPendingWorkNotTheAccount() async throws {
        let h = await makeHarness(responder: Self.server(signup: .json(Self.pendingUser)))
        defer { h.tearDown() }
        await fillJoinForm(h)
        await h.store.submit()?.value
        #expect(h.store.stage == .confirmCode)

        let hold = BaseHold.install(host: h.host) { $0.path == "/auth/v1/verify" }
        let verifying = Task { await h.store.verifyCode("123456") }
        #expect(await hold.waitHeld())

        // 화면을 떠났다 — 상태(단계·주소)는 그대로, 왕복 세대만 올라간다.
        h.store.cancelPendingWork()
        #expect(h.store.stage == .confirmCode)
        #expect(h.store.confirmSentEmail == "member@example.com")

        #expect(await hold.releaseAndWaitDelivered())
        await verifying.value
        await baseBarrier(h.service)
        #expect(h.session.phase == .signedOut, "닫은 화면의 늦은 응답이 그 사람을 로그인시켰다")
        #expect(h.count(rpc: "join_team") == 0)
    }

    // MARK: - 데모 라우트 · 픽스처

    @Test("데모 라우트: signup/confirm 은 로그아웃으로 시작해 코드 화면을 연다 · 기존 라우트는 그대로")
    func demoConfirmRoute() {
        #expect(MobileAuthRoute.demo("signup/confirm") == .signUpConfirm(email: MobileAuthRoute.demoEmail))
        #expect(MobileAuthRoute.demo("Signup/Confirm") == .signUpConfirm(email: MobileAuthRoute.demoEmail))
        #expect(MobileAuthRoute.demo("signup") == .signUp(createTeam: false))
        #expect(MobileAuthRoute.demo("signup/create") == .signUp(createTeam: true))
        #expect(MobileAuthRoute.startsSignedOut(demoRoute: "signup/confirm"))
        #expect(MobileAuthRoute.demoEmail == MobileDemo.email, "라우트가 여는 주소와 데모 계정 주소가 갈렸다")
    }

    @Test("데모 픽스처(session/_signup-confirm): 실제 디코드를 지나 세션 없는 가입 → 코드 화면 → 재전송 → verify → 합류")
    func demoFixturesDriveConfirmFlow() async throws {
        let host = BaseStub.makeHost("signup-confirm-demo")
        let index = MobileDemoFixtures.load()
        #expect(index.duplicateKeys.isEmpty, "\(index.duplicateKeys)")
        MobileStubURLProtocol.register(host: host) { index.response(for: $0, scenario: "signup-confirm") }
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let session = MobileSessionStore(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            installationID: MobileDemo.installationID,
            clock: .fixed(MobileClock.demoInstant)
        )
        session.clientReleaseTimeoutSeconds = 0
        await session.launch()
        #expect(session.phase == .signedOut)

        let gate = BaseGate()
        defer { gate.open() }
        let store = MobileSignUpStore(session: session)
        store.sleep = { _ in await gate.wait() }
        store.displayName = "민트"
        store.email = MobileDemo.email
        store.password = "demo-password"
        store.center = CenterLabel.seoul
        store.teamCode = "AING7K2Q"
        await store.previewTeamCode().value
        #expect(store.joinPreview?.name == "아잉 데모팀")

        // 이 장면의 가입 응답만 세션이 없다(설정을 켠 서버) — 코드 화면이 뜬다.
        await store.submit()?.value
        #expect(store.stage == .confirmCode)
        #expect(store.confirmSentEmail == MobileDemo.email)
        #expect(session.phase == .signedOut)

        await store.verifyCode("123456")
        #expect(session.phase == .signedIn)
        #expect(session.session?.userID == MobileDemo.userID)
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)
    }

    // MARK: - 소스 계약

    @Test("소스 계약: 코드 입력 부품은 한 벌(재설정·가입 공용) · 가입 화면은 재디자인 B 토큰 · 로그인 화면에 출구가 있다")
    func sourceContract() throws {
        let signUpView = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSignUpView.swift"))
        let resetView = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobilePasswordResetView.swift"))
        // 코드 칸을 복사해 두면 동작(.oneTimeCode 자동 채움 · 숫자 키패드 · 제출 키)이 한쪽에서만 고쳐진다.
        for view in [signUpView, resetView] {
            #expect(view.contains("MobileCodeEntryGroup("), "코드 입력 부품을 재사용하지 않는다")
            #expect(!view.contains(".textContentType(.oneTimeCode)"), "코드 칸을 화면 안에 다시 만들었다")
        }
        #expect(signUpView.components(separatedBy: "kind: .filled").count - 1 == 1, "가입 화면에 채운 버튼이 하나가 아니다")
        #expect(signUpView.contains("MobileResendRow(") && resetView.contains("MobileResendRow("), "다시 받기 줄도 한 벌이어야 한다")
        #expect(signUpView.contains("MobileSignUpText.confirmHelp"), "코드 화면에 '이미 인증된 계정' 도움말이 없다")
        // 큰 글자(AX3): 도움말 두 줄은 세로로만 고정한다 — 가로까지 고정하는 `fixedSize()` 는 화면 밖으로 잘린다(NowRedesign 실측).
        #expect(!signUpView.contains(".fixedSize()"))
        #expect(signUpView.contains(".fixedSize(horizontal: false, vertical: true)"))

        // 화면이 인증 왕복을 직접 하지 않는다(문구·가드는 스토어 한 곳).
        for banned in ["verifySignUpCode(", "resendSignUpCode(", "adoptSignedInSession("] {
            #expect(!signUpView.contains(banned), "가입 화면이 \(banned) 를 직접 부른다")
        }

        let login = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionViews.swift"))
        #expect(login.contains("offersConfirmationExit(for:"), "로그인 화면에 미확인 계정 출구가 없다")
        #expect(login.contains(".signUpConfirm(email:"), "출구가 코드 화면으로 가지 않는다")

        // 스토어: 세션이 생긴 뒤의 마무리는 **한 함수**다(두 벌로 갈라지면 한쪽만 고쳐지는 날이 온다).
        let store = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSignUpStore.swift"))
        #expect(store.components(separatedBy: "await performTeamStep(").count - 1 == 1, "팀 단계로 가는 길이 둘 이상이다")
        #expect(store.components(separatedBy: "await continueAfterSession(").count - 1 == 2, "즉시 세션·코드 확인이 같은 마무리를 타지 않는다")
    }
}
