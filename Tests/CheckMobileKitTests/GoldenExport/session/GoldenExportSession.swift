// 원본: 없음 — W2-a G7 세션 시나리오 골든(G §2-3 W2-a ⑧ · C§5.2 G7 · contract/README.md §2-5 의 C-X9 조건).
import CheckCore
import CheckGoldenSupport
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// G7 세션 시나리오(C-X9 로 정한 모양): 스토어 동작 열 + 스텁 응답 열 + 조작 시계 → **요청 모음**(본문을 정규 JSON 으로 파싱 ·
// 순서 없는 모음 — 동시에 떠나는 기기 등록과 소속 읽기는 부하에서 순서가 뒤집힌다) + **끝 상태**. Kotlin(core/session
// `SessionScenarioGoldenTest`)이 같은 시나리오를 가상 시간 위 MockEngine 으로 돌려 같은 모음·끝 상태가 나오는지 대조한다.
//
// 플랫폼 접기(양쪽이 같은 규칙으로 접는다 — spec.normalization):
//   · 기기 등록 RPC: iOS `register_device`(본문의 p_platform 을 뺀다) ≡ Android `register_device_fcm`(K5) → 경로 `<device-registration>`.
//     이 시나리오는 푸시 토큰이 없어 두 본문 모두 p_installation_id · p_app_build · p_app_version 셋이다(iOS 는 토큰이 없으면 환경도 뺀다).
//   · client_release 본문의 p_platform → `<PLATFORM>`(iOS "ios" · Android "android" — C§3.2 C-2 주입).
//   · 토큰 → 자리표시(<ANON> · <OLD> · <FRESH1> · <FRESH2>). 쿼리는 디코드한 [이름, 값] 쌍 순서대로.

@MainActor
@Suite("GoldenExportSession W2-a — G7 세션 시나리오(요청 모음 + 끝 상태)")
struct GoldenExportSession {
    static let installationID = "11111111-2222-4333-8444-555555555555"

    /// 시나리오 한 판의 재료.
    struct Run {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let service: SupabaseWorkService
        let session: MobileSessionStore
        let placeholders: [(String, String)]
    }

    func makeRun(_ label: String, placeholders: [(String, String)],
                 respond: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse) -> Run {
        let host = BaseStub.makeHost("g7-\(label)")
        MobileStubURLProtocol.register(host: host, responder: respond)
        let storage = BaseStub.makeStorage(label)
        let vault = InMemoryTokenVault()
        let clock = BaseTestClock()
        let service = BaseStub.makeService(host: host)
        let session = MobileSessionStore(service: service, vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                                         installationID: Self.installationID, clock: clock.clock)
        session.clientReleaseTimeoutSeconds = 0
        return Run(host: host, storage: storage, vault: vault, service: service, session: session,
                   placeholders: placeholders + [("stub-anon-key", "<ANON>"), (host, "golden.invalid")])
    }

    func seed(_ run: Run, access: String, refresh: String) {
        run.vault.write(access, key: AingKeychain.accessTokenKey)
        run.vault.write(refresh, key: AingKeychain.refreshTokenKey)
        run.storage.defaults.set("user-1", forKey: AingSharedKeys.userID)
        run.storage.defaults.set("a@b.co", forKey: AingSharedKeys.email)
    }

    func scrub(_ text: String, _ run: Run) -> String {
        run.placeholders.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// 요청 하나 → 정규 모양(위 플랫폼 접기).
    func normalized(_ request: MobileStubRequest, _ run: Run) -> GoldenJSON {
        var path = request.path
        var body: GoldenJSON = .null
        let text = scrub(request.bodyText, run)
        if !text.isEmpty, case .object(var members)? = try? GoldenJSON.parse(Data(text.utf8)) {
            if request.rpcName == "register_device" {
                path = "/rest/v1/rpc/<device-registration>"
                members["p_platform"] = nil
            }
            if request.rpcName == "client_release", members["p_platform"] != nil {
                members["p_platform"] = .string("<PLATFORM>")
            }
            body = .object(members)
        } else if !text.isEmpty {
            body = (try? GoldenJSON.parse(Data(text.utf8))) ?? .string(text)
        }
        let items = request.query.isEmpty ? [] : (URLComponents(string: "https://x/?\(request.query)")?.queryItems ?? [])
        return [
            "method": .string(request.method),
            "path": .string(path),
            "query": .array(items.map { .array([.string($0.name), .string(scrub($0.value ?? "", run))]) }),
            "authorization": .string(scrub(BaseStub.bearer(request), run)),
            "body": body,
        ]
    }

    /// 요청 모음(정규 글자 순서로 정렬 — 순서 없는 비교).
    func requestMultiset(_ run: Run) throws -> GoldenJSON {
        let items = try baseRequests(host: run.host).map { normalized($0, run) }.map { ($0, try $0.canonicalText()) }
        return .array(items.sorted { GoldenJSON.keyPrecedes($0.1, $1.1) }.map(\.0))
    }

    func phaseName(_ phase: MobileSessionPhase) -> String {
        switch phase {
        case .launching: return "launching"
        case .needsUpdate(let minBuild): return "needsUpdate:\(minBuild)"
        case .signedOut: return "signedOut"
        case .signedIn: return "signedIn"
        }
    }

    func endState(_ run: Run, extra: [String: GoldenJSON] = [:]) -> GoldenJSON {
        let s = run.session
        var members: [String: GoldenJSON] = [
            "phase": .string(phaseName(s.phase)),
            "generation": .int(s.generation),
            "access": run.vault.read(AingKeychain.accessTokenKey).map { .string(scrub($0, run)) } ?? .null,
            "refresh": run.vault.read(AingKeychain.refreshTokenKey).map { .string(scrub($0, run)) } ?? .null,
            "email": s.storedEmail.map(GoldenJSON.string) ?? .null,
            "notice": s.notice.map(GoldenJSON.string) ?? .null,
            "teamName": s.profile?.teamName.map(GoldenJSON.string) ?? .null,
            "ledger": .int(MobileSignOutCleanupLedger.load(run.vault).count),
            "refreshCalls": .int(baseRequests(host: run.host).filter { $0.path == "/auth/v1/token" && $0.queryValue("grant_type") == "refresh_token" }.count),
        ]
        for (key, value) in extra { members[key] = value }
        return .object(members)
    }

    func finish(_ run: Run) async {
        await run.session.pendingDeviceRegistration?.value
        await run.session.pendingSignOutCleanup?.value
        await baseBarrier(run.service)
    }

    // MARK: - 시나리오

    /// ① C-X9 시나리오: 실행(만료 20초 전 → 조정자 갱신) → 기기 등록·소속 읽기 → 401 → 갱신 → 재시도 → 로그아웃(unregister → logout?scope=local).
    func launchRefreshRetrySignOut() async throws -> GoldenJSON {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(20), salt: "old")
        let fresh1 = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "fresh1")
        let fresh2 = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), salt: "fresh2")
        let refreshCount = BaseLockedBox(0)
        let run = makeRun("cx9", placeholders: [(old, "<OLD>"), (fresh1, "<FRESH1>"), (fresh2, "<FRESH2>")]) { request in
            if request.path == "/auth/v1/token" {
                var n = 0
                refreshCount.mutate { $0 += 1; n = $0 }
                return n == 1 ? BaseStub.authResponse(access: fresh1, refresh: "refresh-1", userID: "user-1")
                              : BaseStub.authResponse(access: fresh2, refresh: "refresh-2", userID: "user-1")
            }
            if request.rpcName == "my_team_invite_code" {
                return BaseStub.bearer(request) == "Bearer \(fresh2)" ? .json(#"[{"invite_code":"ABC123"}]"#) : BaseStub.jwtExpired
            }
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
            default: break
            }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: old, refresh: "refresh-old")
        await run.session.launch()
        await run.session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { run.session.profile?.teamName == "테스트팀" }
        let code = try await run.session.withMobileSessionRetry { current in
            try await run.service.fetchMyInviteCode(accessToken: current.accessToken)
        }
        let teamBeforeSignOut = run.session.profile?.teamName
        await run.session.signOut()
        await finish(run)
        return [
            "id": "launch-refresh-401-retry-signout",
            "requests": try requestMultiset(run),
            "end": endState(run, extra: [
                "inviteCode": code.map(GoldenJSON.string) ?? .null,
                "teamNameBeforeSignOut": teamBeforeSignOut.map(GoldenJSON.string) ?? .null,
            ]),
        ]
    }

    /// ② 실행 직후 갱신이 치명(invalid_grant) → 로컬만 비우고 로그아웃(세대 +1 · 이메일은 남긴다 · 서버 정리 없음).
    func launchFatalRefresh() async throws -> GoldenJSON {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(20), salt: "old")
        let run = makeRun("fatal", placeholders: [(old, "<OLD>")]) { request in
            if request.rpcName == "client_release" { return BaseStub.releaseOK }
            if request.path == "/auth/v1/token" { return BaseStub.invalidGrant }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: old, refresh: "refresh-old")
        await run.session.launch()
        await finish(run)
        return ["id": "launch-refresh-fatal", "requests": try requestMultiset(run), "end": endState(run)]
    }

    /// ③ 실행 직후 갱신이 일시(503) → 세션 유지(옛 토큰으로 등록·소속 읽기 — 비행기 모드로 켠 폰이 로그아웃되지 않는다, C§4 #40).
    func launchTransientRefresh() async throws -> GoldenJSON {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(20), salt: "old")
        let run = makeRun("transient", placeholders: [(old, "<OLD>")]) { request in
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            default: break
            }
            if request.path == "/auth/v1/token" { return .json(#"{"message":"upstream"}"#, status: 503) }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: old, refresh: "refresh-old")
        await run.session.launch()
        await run.session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { run.session.profile?.teamName == "테스트팀" }
        await finish(run)
        return ["id": "launch-refresh-transient", "requests": try requestMultiset(run), "end": endState(run)]
    }

    /// ④ 로그아웃 때 access 가 만료(401) → 장부의 refresh 로 **한 번** 갱신 → unregister 다시 → 새 토큰으로 logout?scope=local.
    func signOutWithExpiredAccess() async throws -> GoldenJSON {
        let run = makeRun("signout401", placeholders: []) { request in
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "unregister_device":
                return BaseStub.bearer(request) == "Bearer access-0" ? BaseStub.jwtExpired : .json(#"{"status":"ok","removed":true}"#)
            default: break
            }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: "cleanup-access", refresh: "cleanup-refresh", userID: "user-1") }
            if request.path == "/auth/v1/logout" {
                return BaseStub.bearer(request) == "Bearer cleanup-access" ? .json("{}") : BaseStub.jwtExpired
            }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: "access-0", refresh: "r0")
        await run.session.launch()
        await run.session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { run.session.profile?.teamName == "테스트팀" }
        await run.session.signOut()
        await finish(run)
        return ["id": "signout-expired-access-ledger-refresh", "requests": try requestMultiset(run), "end": endState(run)]
    }

    /// ⑤ 계정 삭제: 재인증(저장된 이메일 + 비밀번호) → 사진 → delete_my_account(재인증 토큰) → 장부 없는 로컬 정리.
    func deleteAccount() async throws -> GoldenJSON {
        let run = makeRun("delete", placeholders: []) { request in
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "delete_my_account": return .json("null")
            default: break
            }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: "reauth-access", refresh: "reauth-refresh", userID: "user-1") }
            if request.path.hasPrefix("/storage/v1/object/avatars/") { return .json("{}") }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: "access-0", refresh: "r0")
        await run.session.launch()
        await run.session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { run.session.profile?.teamName == "테스트팀" }
        let outcome = await run.session.deleteAccount(password: "pw")
        await finish(run)
        return [
            "id": "delete-account-order",
            "requests": try requestMultiset(run),
            "end": endState(run, extra: ["deleted": .bool(outcome == .deleted)]),
        ]
    }

    /// ⑥ 최소 빌드보다 낮다 → 업데이트 화면에서 멈춘다(복원·인증 요청 0).
    func launchBelowMinimumBuild() async throws -> GoldenJSON {
        let run = makeRun("minbuild", placeholders: []) { request in
            if request.rpcName == "client_release" {
                return .json(#"{"status":"ok","platform":"ios","min_build":5,"latest_build":7,"notes":null}"#)
            }
            return .missingFunction(request.path)
        }
        defer { BaseStub.tearDown(host: run.host, storage: run.storage) }
        seed(run, access: "access-0", refresh: "r0")
        await run.session.launch()
        await finish(run)
        return [
            "id": "launch-below-min-build",
            "requests": try requestMultiset(run),
            "end": endState(run, extra: ["latestBuild": run.session.latestBuild.map(GoldenJSON.int) ?? .null]),
        ]
    }

    @Test("G7 세션 시나리오 6판 — Kotlin core/session 이 같은 요청 모음 · 끝 상태를 내야 한다")
    func sessionScenarios() async throws {
        let cases: [GoldenJSON] = [
            try await launchRefreshRetrySignOut(),
            try await launchFatalRefresh(),
            try await launchTransientRefresh(),
            try await signOutWithExpiredAccess(),
            try await deleteAccount(),
            try await launchBelowMinimumBuild(),
        ]
        goldenEmit(GoldenFile(
            golden: "session/scenarios",
            equivalence: .discrete,
            swiftSources: [
                "Sources/CheckMobileKit/Session/MobileSessionStore.swift",
                "Sources/CheckCore/SessionRefreshCoordinator.swift",
                "Sources/CheckMobileKit/Session/MobileSignOutCleanup.swift",
                "Sources/CheckMobileKit/Session/MobileDeviceService.swift",
                "Sources/CheckCore/TokenVault.swift",
                "Sources/CheckCore/AuthErrorRules.swift",
            ],
            spec: [
                "shape": "case 하나 = 시나리오 한 판. requests = 받은 요청을 정규화해 정규 글자 순서로 정렬한 모음(순서 없는 비교 — C-X9). end = 끝 상태.",
                "request": "method · path · query([이름, 값] 디코드 쌍, 순서대로) · authorization(토큰은 자리표시) · body(정규 JSON, 본문 없으면 null)",
                "normalization": "iOS register_device(본문 p_platform 제거) ≡ Android register_device_fcm(K5) → path /rest/v1/rpc/<device-registration>. client_release 본문 p_platform → <PLATFORM>. 토큰 → <ANON> · <OLD>(만료 20초 전 JWT) · <FRESH1>(+3600) · <FRESH2>(+7200). 호스트 → golden.invalid",
                "clock": "2026-09-17 14:05:00 KST(1789621500) 에 멈춘 시계 — 조정자 갱신 조건(만료 60초 전)만 시각을 본다",
                "app": "build 1 · version 0.1.0 · 설치 id 11111111-2222-4333-8444-555555555555 · 푸시 토큰 없음 · client_release 상한 없음",
                "end": "phase(launching|needsUpdate:N|signedOut|signedIn) · generation · access/refresh(금고, 자리표시) · email(저장된 이메일) · notice · teamName · ledger(정리 장부 줄 수) · refreshCalls(grant_type=refresh_token 수) + 시나리오별 칸",
            ],
            cases: cases
        ))
    }
}
