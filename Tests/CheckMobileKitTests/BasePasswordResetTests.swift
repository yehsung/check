import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 비밀번호 재설정(w16 · SPEC 작업 B): 3단(발송 → 코드 → 새 비밀번호) 각각의 사전 검증·오류 문구(맥 상수 그대로) · 쿨다운 ·
/// 늦은 응답 무시 · 성공 뒤 세션 연결(로그인 성공과 같은 길) · 데모 픽스처.
@MainActor
@Suite struct BasePasswordResetTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let clock: BaseTestClock
        let service: SupabaseWorkService
        let session: MobileSessionStore
        let store: MobilePasswordResetStore
        /// 쿨다운 1초 대기가 기다리는 문(벽시계 없음). 열기 전엔 남은 초가 처음 값에 멈춰 있다.
        let sleepGate: BaseGate

        var requests: [MobileStubRequest] { baseRequests(host: host) }
        func count(path: String, method: String? = nil) -> Int {
            requests.filter { $0.path == path && (method == nil || $0.method.uppercased() == method) }.count
        }
        func body(path: String, method: String? = nil) -> String {
            requests.first { $0.path == path && (method == nil || $0.method.uppercased() == method) }?.bodyText ?? ""
        }
        @MainActor
        func tearDown() {
            store.cancel()
            sleepGate.open()
            BaseStub.tearDown(host: host, storage: storage)
        }
    }

    nonisolated static let recoveryAccess = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), subject: "user-r", salt: "recovery")

    static func server(
        recover: MobileStubResponse? = nil,
        verify: MobileStubResponse? = nil,
        update: MobileStubResponse? = nil
    ) -> MobileStubURLProtocol.Responder {
        BaseSessionTests.happyServer(extra: { request in
            switch request.path {
            case "/auth/v1/recover": return recover ?? .json("{}")
            case "/auth/v1/verify": return verify ?? BaseStub.authResponse(access: recoveryAccess, refresh: "refresh-r", userID: "user-r")
            case "/auth/v1/user": return update ?? .json(#"{"id":"user-r","email":"member@example.com"}"#)
            default: return nil
            }
        })
    }

    func makeHarness(email: String = "member@example.com", responder: @escaping MobileStubURLProtocol.Responder) async -> Harness {
        let host = BaseStub.makeHost("reset")
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
        let store = MobilePasswordResetStore(session: session, email: email, clock: clock.clock)
        let gate = BaseGate()
        store.sleep = { _ in await gate.wait() }
        return Harness(host: host, storage: storage, vault: vault, clock: clock, service: service, session: session, store: store, sleepGate: gate)
    }

    // MARK: - 1단 발송

    @Test("이메일 형식이 아니면 왕복 없이 안내 · 앞뒤 공백·대문자는 접는다")
    func rejectsImplausibleEmail() async {
        let h = await makeHarness(email: "  No-At ", responder: Self.server())
        defer { h.tearDown() }
        #expect(h.store.email == "no-at")
        #expect(!h.store.isPrimaryEnabled(code: "", newPassword: ""))
        await h.store.requestCode()
        #expect(h.store.phase == .enterEmail)
        #expect(h.store.message == MobilePasswordResetText.invalidEmail)
        #expect(h.store.noticeIsError)
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/recover") == 0)

        h.store.email = " Member@Example.COM "
        #expect(h.store.isPrimaryEnabled(code: "", newPassword: ""))
        await h.store.requestCode()
        #expect(h.store.email == "member@example.com")
        #expect(h.body(path: "/auth/v1/recover").contains(#""email":"member@example.com""#))
    }

    @Test("발송 성공: 코드 화면으로 · '메일을 보냈어요'(안내, 계정 유무를 말하지 않는다) · 첫 쿨다운 5초 · 쿨다운 중 재요청은 왕복 없음")
    func sendsCodeAndCoolsDown() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        await h.store.requestCode()
        #expect(h.store.phase == .enterCode)
        #expect(h.store.step == .code)
        #expect(h.store.message == MobilePasswordResetText.sent)
        #expect(!h.store.noticeIsError, "발송 안내가 빨갛게 그려진다")
        #expect(h.store.resendSeconds == MobilePasswordResetStore.firstResendDelaySeconds)
        #expect(!h.store.isResendEnabled)
        #expect(h.store.resendTitle == "다시 받기 (5초)")

        await h.store.requestCode()
        #expect(h.store.message == MobilePasswordResetText.cooldown)
        #expect(h.count(path: "/auth/v1/recover") == 1, "쿨다운 중 헛왕복")
        #expect(h.store.phase == .enterCode)
    }

    @Test("쿨다운은 시계 기준 데드라인으로 줄고 0 이 되면 재발송이 열린다 · 재발송 뒤는 60초")
    func cooldownFollowsClock() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        let clock = h.clock
        h.store.sleep = { _ in
            clock.advance(1)
            await Task.yield()
        }
        await h.store.requestCode()
        #expect(await baseWaitUntil { h.store.resendSeconds == 0 })
        #expect(h.store.isResendEnabled)

        h.store.sleep = { [gate = h.sleepGate] _ in await gate.wait() }
        await h.store.requestCode()
        #expect(h.count(path: "/auth/v1/recover") == 2)
        #expect(h.store.resendSeconds == MobilePasswordResetStore.resendCooldownSeconds)
    }

    @Test("발송 실패: 네트워크·5xx 는 연결 안내(이메일 화면) · 429 는 코드 화면 + 서버가 준 초 · 그 밖은 '보내지 못했어요'")
    func sendFailures() async {
        let offline = await makeHarness(responder: Self.server(recover: .networkFailure()))
        defer { offline.tearDown() }
        await offline.store.requestCode()
        #expect(offline.store.phase == .enterEmail)
        #expect(offline.store.message == MobilePasswordResetText.network)

        let down = await makeHarness(responder: Self.server(recover: .json(#"{"msg":"paused"}"#, status: 503)))
        defer { down.tearDown() }
        await down.store.requestCode()
        #expect(down.store.phase == .enterEmail)
        #expect(down.store.message == MobilePasswordResetText.network)

        let limited = await makeHarness(responder: Self.server(recover: .json(
            #"{"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after 37 seconds."}"#, status: 429
        )))
        defer { limited.tearDown() }
        await limited.store.requestCode()
        #expect(limited.store.phase == .enterCode, "429 = 방금 이미 보냈다 — 코드를 넣을 자리가 있어야 한다")
        #expect(limited.store.message == MobilePasswordResetText.alreadySent)
        #expect(limited.store.resendSeconds == 37, "남은 초는 서버가 진실이다")

        let refused = await makeHarness(responder: Self.server(recover: .json(#"{"msg":"Signups not allowed for this instance"}"#, status: 400)))
        defer { refused.tearDown() }
        await refused.store.requestCode()
        #expect(refused.store.phase == .enterEmail)
        #expect(refused.store.message == MobilePasswordResetText.sendFailed)
    }

    @Test("늦은 응답: 화면을 떠난(cancel) 뒤 도착한 발송 응답은 상태를 바꾸지 않는다")
    func staleResponseIgnoredAfterCancel() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        let hold = BaseHold.install(host: h.host) { $0.path == "/auth/v1/recover" }
        let request = Task { await h.store.requestCode() }
        #expect(await hold.waitHeld())
        #expect(h.store.phase == .sending)
        h.store.cancel()
        #expect(h.store.phase == .enterEmail)
        #expect(await hold.releaseAndWaitDelivered())
        await request.value
        #expect(h.store.phase == .enterEmail)
        #expect(h.store.message == nil)
        #expect(h.store.resendSeconds == 0)
    }

    // MARK: - 2단 코드

    @Test("코드: 6자리가 아니면 왕복 없이 안내 · 공백·하이픈은 떼고 recovery 로 검증 · 성공하면 새 비밀번호 화면")
    func verifyGuardsAndSucceeds() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        await h.store.requestCode()
        await h.store.verifyCode("12-34")
        #expect(h.store.phase == .enterCode)
        #expect(h.store.message == MobilePasswordResetText.invalidCode)
        #expect(!h.store.isPrimaryEnabled(code: "12-34", newPassword: ""))
        #expect(h.store.isPrimaryEnabled(code: "12 34 56", newPassword: ""))
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/verify") == 0)

        await h.store.verifyCode("12 34-56")
        #expect(h.store.phase == .enterNewPassword)
        #expect(h.store.step == .newPassword)
        #expect(h.store.message == nil)
        let body = h.body(path: "/auth/v1/verify")
        #expect(body.contains(#""token":"123456""#))
        #expect(body.contains(#""type":"recovery""#))
        #expect(body.contains(#""email":"member@example.com""#))

        // 이미 검증했으면 다시 보내지 않는다(OTP 는 1회용).
        await h.store.verifyCode("123456")
        #expect(h.store.phase == .enterNewPassword)
        #expect(h.count(path: "/auth/v1/verify") == 1)
    }

    @Test("코드 거절: 403 otp_expired 는 '맞지 않거나 만료' · 429 는 쿨다운 안내 · 네트워크는 연결 안내 — 전부 코드 화면에 머문다")
    func verifyFailures() async {
        for (response, expected) in [
            (MobileStubResponse.json(#"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#, status: 403), MobilePasswordResetText.codeRejected),
            (.json(#"{"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}"#, status: 429), MobilePasswordResetText.cooldown),
            (.networkFailure(), MobilePasswordResetText.network),
        ] {
            let h = await makeHarness(responder: Self.server(verify: response))
            defer { h.tearDown() }
            await h.store.requestCode()
            await h.store.verifyCode("123456")
            #expect(h.store.phase == .enterCode, "\(expected)")
            #expect(h.store.message == expected)
            // 쿨다운 안내는 실패가 아니다(맥 isInformational 과 같은 셋: 보냈어요 · 이미 보냈어요 · 조금 뒤에).
            #expect(h.store.noticeIsError == (expected != MobilePasswordResetText.cooldown), "\(expected)")
        }
    }

    // MARK: - 3단 새 비밀번호

    @Test("새 비밀번호: 6자 미만은 왕복 없이 · 서버 거절(조건)은 화면·세션 유지 · recovery 토큰이 죽으면 코드 화면으로")
    func newPasswordGuardsAndFailures() async {
        let weak = await makeHarness(responder: Self.server(update: .json(#"{"code":422,"msg":"Password should be at least 6 characters"}"#, status: 422)))
        defer { weak.tearDown() }
        await weak.store.requestCode()
        await weak.store.verifyCode("123456")
        await weak.store.submitNewPassword("abc")
        #expect(weak.store.message == MobilePasswordResetText.shortPassword)
        #expect(weak.store.phase == .enterNewPassword)
        await baseBarrier(weak.service)
        #expect(weak.count(path: "/auth/v1/user", method: "PUT") == 0)

        await weak.store.submitNewPassword("abcdef")
        #expect(weak.store.phase == .enterNewPassword, "비밀번호만 다시 받으면 되는 일 — 코드부터 다시 받게 하지 않는다")
        #expect(weak.store.message == MobilePasswordResetText.rejectedPassword)
        #expect(weak.session.phase == .signedOut)
        // 세션은 살아 있다: 다시 제출하면 verify 없이 PUT 이 한 번 더 나간다.
        await weak.store.submitNewPassword("abcdefg")
        #expect(weak.count(path: "/auth/v1/verify") == 1)
        #expect(weak.count(path: "/auth/v1/user", method: "PUT") == 2)

        let dead = await makeHarness(responder: Self.server(update: .json(#"{"error_code":"bad_jwt","msg":"invalid JWT: unable to parse"}"#, status: 403)))
        defer { dead.tearDown() }
        await dead.store.requestCode()
        await dead.store.verifyCode("123456")
        await dead.store.submitNewPassword("abcdef")
        #expect(dead.store.phase == .enterCode)
        #expect(dead.store.message == MobilePasswordResetText.codeRejected)
        // 죽은 세션은 버렸다 — 다음 검증은 서버로 다시 나간다.
        await dead.store.verifyCode("654321")
        #expect(dead.count(path: "/auth/v1/verify") == 2)
    }

    @Test("성공: PUT 은 recovery 토큰으로 · 그 세션을 로그인 성공과 같은 길로 잇는다(키체인 · 이메일 · 기기 등록) · 금지 호출 0")
    func successConnectsSession() async throws {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        await h.store.requestCode()
        await h.store.verifyCode("123456")
        await h.store.submitNewPassword("newpass1")

        #expect(h.store.phase == .done)
        #expect(h.store.message == nil)
        #expect(h.store.resendSeconds == 0)
        let put = try #require(h.requests.first { $0.path == "/auth/v1/user" && $0.method.uppercased() == "PUT" })
        #expect(BaseStub.bearer(put) == "Bearer \(Self.recoveryAccess)")
        #expect(put.bodyText.contains(#""password":"newpass1""#))

        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.userID == "user-r")
        #expect(h.session.session?.accessToken == Self.recoveryAccess)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == Self.recoveryAccess)
        #expect(h.vault.read(AingKeychain.refreshTokenKey) == "refresh-r")
        #expect(h.session.storedEmail == "member@example.com")
        #expect(h.session.signedInViaForm)
        await h.session.pendingDeviceRegistration?.value
        #expect(h.requests.filter { $0.rpcName == "register_device" }.count == 1)
        #expect(await baseWaitUntil { h.session.profile?.teamName == "테스트팀" })
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("데모 픽스처(session/): recover → verify → PUT user 가 디코드되어 로그인 상태가 된다(고유 호스트)")
    func demoFixturesDriveReset() async {
        let host = BaseStub.makeHost("reset-demo")
        let index = MobileDemoFixtures.load()
        MobileStubURLProtocol.register(host: host) { index.response(for: $0, scenario: "reset") }
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
        let store = MobilePasswordResetStore(session: session, email: MobileDemo.email, clock: .fixed(MobileClock.demoInstant))
        let gate = BaseGate()
        store.sleep = { _ in await gate.wait() }
        defer { store.cancel(); gate.open() }
        await store.requestCode()
        #expect(store.phase == .enterCode)
        await store.verifyCode("123456")
        #expect(store.phase == .enterNewPassword)
        await store.submitNewPassword("demo-password-2")
        #expect(store.phase == .done)
        #expect(session.phase == .signedIn)
        #expect(session.session?.userID == MobileDemo.userID)
        await session.pendingDeviceRegistration?.value
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)
    }
}
