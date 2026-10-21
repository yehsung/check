import CheckCore
import CheckGoldenSupport
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// C-X9(W0-b 실험): 세션 스토어 시나리오(G7 후보)가 비동기 경합 없이 **결정적**인가.
// 실행(만료 임박 → 조정자 갱신) → 소속 읽기·기기 등록 → 401 → 갱신 → 재시도 → 로그아웃 을 20번 돌려
// (요청 기록 + 끝 상태)를 정규 JSON 으로 만들고, 서로 다른 바이트가 몇 벌인지 센다.
//
// 실험이라 **기본으로는 돌지 않는다**(`CHECK_GOLDEN_EXPERIMENTS=1` 일 때만). 결과가 "결정적이 아니다"여도 그것이 답이고,
// 기본 스위트에 넣으면 부하에 따라 흔들리는 단언이 된다. 결과 수치는 W0-b 완료 보고(C-X9)에 적었다.

@MainActor
@Suite("GoldenExperiment W0-b — C-X9 세션 시나리오 20회 바이트 동일성",
       .enabled(if: ProcessInfo.processInfo.environment["CHECK_GOLDEN_EXPERIMENTS"] == "1"))
struct GoldenExperimentSessionW0b {
    static let runs = 20

    /// 한 번의 시나리오. 토큰은 자리표시로 바꿔 싣는다(호스트·JWT 바이트가 실행마다 같아도 사람이 읽게).
    func runOnce() async throws -> (ordered: GoldenJSON, canonicalOrdered: GoldenJSON, canonicalMultiset: GoldenJSON) {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(20), salt: "old")
        let fresh1 = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "fresh1")
        let fresh2 = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), salt: "fresh2")
        let refreshCount = BaseLockedBox(0)
        let host = BaseStub.makeHost("cx9")
        MobileStubURLProtocol.register(host: host) { request in
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
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let vault = InMemoryTokenVault()
        vault.write(old, key: AingKeychain.accessTokenKey)
        vault.write("refresh-old", key: AingKeychain.refreshTokenKey)
        storage.defaults.set("user-1", forKey: AingSharedKeys.userID)
        let clock = BaseTestClock()
        let service = BaseStub.makeService(host: host)
        let session = MobileSessionStore(service: service, vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                                         installationID: "11111111-2222-4333-8444-555555555555", clock: clock.clock)
        session.clientReleaseTimeoutSeconds = 0

        await session.launch()
        await session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { session.profile?.teamName == "테스트팀" }
        let code = try await session.withMobileSessionRetry { current in
            try await service.fetchMyInviteCode(accessToken: current.accessToken)
        }
        await session.signOut()
        await baseBarrier(service)

        let placeholders = [(old, "<OLD>"), (fresh1, "<FRESH1>"), (fresh2, "<FRESH2>"), (host, "<HOST>")]
        func scrub(_ text: String) -> String {
            placeholders.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        }
        let requests: [GoldenJSON] = baseRequests(host: host).map { request in
            [
                "method": .string(request.method),
                "path": .string(request.path),
                "query": .string(scrub(request.query)),
                "authorization": .string(scrub(BaseStub.bearer(request))),
                "body": .string(scrub(request.bodyText)),
            ]
        }
        let end: GoldenJSON = [
            "phase": .string(String(describing: session.phase)),
            "generation": .int(session.generation),
            "inviteCode": .string(code ?? "nil"),
            "access": .string(scrub(vault.read(AingKeychain.accessTokenKey) ?? "nil")),
            "refresh": .string(vault.read(AingKeychain.refreshTokenKey) ?? "nil"),
            "refreshCalls": .int(refreshCount.get()),
        ]
        // 본문을 정규 JSON 으로 다시 쓴 판(키 순서를 지운다 — JSONEncoder 는 .sortedKeys 가 없으면 키 순서가 실행마다 다를 수 있다).
        let canonical: [GoldenJSON] = baseRequests(host: host).map { request in
            let body = scrub(request.bodyText)
            let parsed = body.isEmpty ? GoldenJSON.string("") : ((try? GoldenJSON.parse(Data(body.utf8))) ?? .string(body))
            return [
                "method": .string(request.method),
                "path": .string(request.path),
                "query": .string(scrub(request.query)),
                "authorization": .string(scrub(BaseStub.bearer(request))),
                "body": parsed,
            ]
        }
        let sortedCanonical = try canonical.map { ($0, try $0.canonicalText()) }
            .sorted { GoldenJSON.keyPrecedes($0.1, $1.1) }.map(\.0)
        return (["requests": .array(requests), "end": end],
                ["requests": .array(canonical), "end": end],
                ["requests": .array(sortedCanonical), "end": end])
    }

    @Test("C-X9: 같은 시나리오 20회 — 순서 그대로의 기록과 순서를 뺀 기록이 각각 몇 벌인가")
    func sessionScenarioIsDeterministic() async throws {
        var ordered: [String: Int] = [:]
        var canonicalOrdered: [String: Int] = [:]
        var multiset: [String: Int] = [:]
        var sample = ""
        for _ in 0..<Self.runs {
            let (a, b, c) = try await runOnce()
            let text = try a.canonicalText()
            if sample.isEmpty { sample = text }
            ordered[text, default: 0] += 1
            canonicalOrdered[try b.canonicalText(), default: 0] += 1
            multiset[try c.canonicalText(), default: 0] += 1
        }
        print("[C-X9] runs=\(Self.runs) distinctOrdered=\(ordered.count) distinctCanonicalBodyOrdered=\(canonicalOrdered.count) "
              + "distinctCanonicalBodyMultiset=\(multiset.count) orderedCounts=\(ordered.values.sorted(by: >)) "
              + "canonicalOrderedCounts=\(canonicalOrdered.values.sorted(by: >)) multisetCounts=\(multiset.values.sorted(by: >))")
        if ordered.count > 1 {
            let variants = ordered.keys.sorted()
            for (index, variant) in variants.prefix(3).enumerated() {
                let paths = (try? GoldenJSON.parse(Data(variant.utf8))).flatMap { v in
                    (try? GoldenJSON.parse(Data(variants[0].utf8))).flatMap { GoldenJSON.firstDifference(v, $0) }
                } ?? "-"
                print("[C-X9] variant \(index) ×\(ordered[variant]!) firstDifferenceFromVariant0=\(paths)")
                print("[C-X9] variant-text \(index):\n\(variant)")
            }
        }
        print("[C-X9] sample:\n\(sample)")
        // 시나리오가 실제로 401 → 갱신 → 재시도 · 로그아웃을 지났는가(빈 시나리오면 '결정적'이 공짜로 나온다).
        #expect(sample.contains("rpc/my_team_invite_code") && sample.contains("/auth/v1/logout"))
        #expect(sample.contains("\"refreshCalls\": 2"), "갱신이 두 번(실행 직후 + 401 뒤) 일어나지 않았다")
    }
}
