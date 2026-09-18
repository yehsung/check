import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 계정 삭제(SPEC-public-release 작업 C · 앱스토어 5.1.1(v)). 순서가 계약이다: 재인증(signIn) → `delete_my_account` → 로컬 정리.
/// 재인증이 거절되면 RPC 는 나가지 않고, RPC 가 실패하면(서버에 아직 없는 404 포함) 로컬은 한 칸도 지우지 않는다.
@MainActor
@Suite("계정 삭제(public-release C)")
struct MeAccountDeletionTests {
    nonisolated static let me = RankMeFixture.userID
    nonisolated static let rightPassword = "correct-horse"
    nonisolated static let freshAccess = "fresh-access-after-reauth"

    /// 재인증 스텁: 비밀번호가 맞으면 새 세션(로그인 응답 모양), 틀리면 GoTrue 의 400 `invalid_credentials`.
    nonisolated static func reauthResponder(_ request: MobileStubRequest) -> MobileStubResponse? {
        guard request.path == "/auth/v1/token", request.queryValue("grant_type") == "password" else { return nil }
        if request.jsonBody["password"] as? String == rightPassword {
            return BaseStub.authResponse(access: freshAccess, refresh: "fresh-refresh", userID: me)
        }
        return .json(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#, status: 400)
    }

    /// 지운 뒤 기기에 남으면 안 되는 것들이 전부 비었는가.
    private func expectLocalCleared(_ harness: RankMeHarness, sourceLocation: SourceLocation = #_sourceLocation) {
        let session = harness.model.session
        #expect(!session.isSignedIn && session.phase == .signedOut, sourceLocation: sourceLocation)
        #expect(session.session == nil && session.profile == nil, sourceLocation: sourceLocation)
        #expect(harness.storage.defaults.string(forKey: AingSharedKeys.userID) == nil, "공용 suite 의 userID 가 남았다", sourceLocation: sourceLocation)
        #expect(harness.storage.defaults.string(forKey: AingSharedKeys.email) == nil, "지운 계정 이메일이 로그인 칸에 남는다", sourceLocation: sourceLocation)
        #expect(session.storedEmail == nil, sourceLocation: sourceLocation)
        #expect(!FileManager.default.fileExists(atPath: harness.storage.widgetSnapshotURL.path), "위젯 스냅샷이 남았다", sourceLocation: sourceLocation)
        #expect(!session.hasPendingSignOutCleanup, "지운 계정의 토큰이 정리 장부(키체인)에 남았다", sourceLocation: sourceLocation)
        #expect(session.apnsToken == nil, "APNs 토큰이 남았다(푸시 코디네이터 reset 이 안 돌았다)", sourceLocation: sourceLocation)
    }

    /// 실패했으면 로그인 상태가 **한 칸도** 안 바뀌었는가.
    private func expectLocalIntact(_ harness: RankMeHarness, sourceLocation: SourceLocation = #_sourceLocation) {
        let session = harness.model.session
        #expect(session.isSignedIn && session.phase == .signedIn, sourceLocation: sourceLocation)
        #expect(session.userID == Self.me, sourceLocation: sourceLocation)
        #expect(harness.storage.defaults.string(forKey: AingSharedKeys.userID) == Self.me, sourceLocation: sourceLocation)
        #expect(session.storedEmail == "rankme@example.invalid", sourceLocation: sourceLocation)
        #expect(!harness.me.isDeletingAccount, sourceLocation: sourceLocation)
        #expect(harness.me.accountDeletionPassword.isEmpty == false, "실패했는데 입력을 지웠다(다시 치게 만든다)", sourceLocation: sourceLocation)
    }

    @Test("재인증 실패(틀린 비밀번호): RPC 미호출 · 로그인 상태 그대로 · 비밀번호 문구 · 빈 비밀번호는 요청 없이 안내")
    func wrongPasswordNeverCallsRPC() async throws {
        let harness = await RankMeHarness(label: "acct-wrong") { Self.reauthResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        store.accountDeletionPassword = ""
        #expect(!store.canDeleteAccount)
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == "비밀번호를 입력해 주세요")
        await harness.barrier()
        #expect(harness.requests(path: "/auth/v1/token", method: "POST").isEmpty, "빈 비밀번호로 재인증을 보냈다")

        store.accountDeletionPassword = "wrong"
        #expect(store.canDeleteAccount)
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == "비밀번호가 맞지 않아요")
        await harness.barrier()
        let reauth = harness.requests(path: "/auth/v1/token", method: "POST").filter { $0.queryValue("grant_type") == "password" }
        #expect(reauth.count == 1)
        #expect(reauth.first?.jsonBody["email"] as? String == "rankme@example.invalid", "저장된 이메일로 재인증한다")
        #expect(harness.requests(rpc: "delete_my_account").isEmpty, "재인증이 거절됐는데 삭제 RPC 가 나갔다")
        #expect(harness.requests.filter { $0.path == "/auth/v1/logout" }.isEmpty, "재인증이 실패했는데 로그아웃을 보냈다(세션이 없다)")
        expectLocalIntact(harness)
        #expect(!harness.model.session.isDeletingAccount)
        harness.expectNoForbiddenCalls()
    }

    @Test("성공: 재인증 → delete_my_account(새 토큰 · 본문 {}) → 로컬 정리 순서 · RPC 가 도는 동안은 로그인 상태 · 장부 없음 · 로그아웃 요청 없음")
    func successOrderIsReauthThenRPCThenLocalCleanup() async throws {
        let harness = await RankMeHarness(label: "acct-ok") { request in
            if request.rpcName == "delete_my_account" { return MobileStubResponse(status: 204, body: Data()) }
            return Self.reauthResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        let session = harness.model.session
        try WidgetSnapshotCodec.write(WidgetSnapshot(generatedAt: RankMeFixture.now), to: harness.storage.widgetSnapshotURL)
        session.updateAPNsToken(String(repeating: "ab", count: 32))
        // 실행 복원의 등록이 아직 돌고 있으면 토큰 변경 등록은 그 뒤에 줄 선다 — 둘 다 끝낸 뒤 기록을 비운다.
        await session.pendingDeviceRegistration?.value
        await session.pendingDeviceRegistration?.value
        #expect(session.apnsToken != nil, "전제: APNs 토큰이 있다")
        var reloads = 0
        session.reloadWidgetTimelines = { reloads += 1 }
        MobileStubURLProtocol.clearRequests(host: harness.host)

        let deleteHold = BaseHold.rpc("delete_my_account", host: harness.host)
        store.accountDeletionPassword = Self.rightPassword
        let task = Task { await store.deleteAccount() }
        #expect(await deleteHold.waitHeld(), "삭제 RPC 가 나가지 않았다")
        // RPC 가 서버에 가 있는 동안: 아직 로그인 상태 · 키체인 그대로 · 깃발 켜짐(재탭 방지).
        #expect(session.isSignedIn && session.userID == Self.me, "서버가 지우기 전에 로컬을 비웠다")
        #expect(harness.storage.defaults.string(forKey: AingSharedKeys.userID) == Self.me)
        #expect(store.isDeletingAccount && session.isDeletingAccount && !store.canDeleteAccount)
        #expect(await store.deleteAccount() == false, "도는 중에 또 눌렀는데 두 번째가 시작됐다")
        #expect(await deleteHold.releaseAndWaitDelivered())
        #expect(await task.value, "삭제가 실패로 끝났다: \(store.accountDeletionNotice ?? "-")")

        expectLocalCleared(harness)
        #expect(reloads == 1, "위젯을 새로 그리게 하지 않았다")
        #expect(!store.isDeletingAccount && store.accountDeletionPassword.isEmpty && store.accountDeletionNotice == nil, "reset 이 안 돌았다")
        #expect(harness.model.gomokuHost.rubyBalance == nil)

        let paths = harness.requests.map { $0.rpcName.map { "rpc/\($0)" } ?? $0.path }
        #expect(paths == ["/auth/v1/token", "rpc/delete_my_account"], "순서가 재인증 → 삭제여야 하고 그 뒤 서버 요청이 없어야 한다: \(paths)")
        let rpc = try #require(harness.requests(rpc: "delete_my_account").first)
        #expect(BaseStub.bearer(rpc) == "Bearer \(Self.freshAccess)", "재인증으로 받은 새 토큰으로 지운다")
        #expect(rpc.bodyText == "{}", "인자 없는 RPC 본문은 {} 다: \(rpc.bodyText)")
        #expect(harness.requests.filter { $0.path == "/auth/v1/logout" }.isEmpty, "지운 계정에 로그아웃을 보냈다(cascade 로 이미 없다)")
        harness.expectNoForbiddenCalls()
    }

    @Test("RPC 실패: 서버에 함수가 없으면(404) '아직' 문구 · 5xx 는 연결 문구 · 둘 다 로컬을 지우지 않고 재인증 세션만 닫는다")
    func rpcFailureKeepsLocal() async throws {
        let harness = await RankMeHarness(label: "acct-fail") { request in
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return Self.reauthResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.accountDeletionPassword = Self.rightPassword

        harness.enqueue("delete_my_account", .missingFunction("delete_my_account"))
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == "계정 삭제가 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요")
        expectLocalIntact(harness)
        await harness.barrier()
        let logoutsAfterMissing = harness.requests.filter { $0.path == "/auth/v1/logout" }
        #expect(logoutsAfterMissing.count == 1, "실패하면 재인증이 만든 두 번째 서버 세션을 닫아야 한다")
        #expect(BaseStub.bearer(try #require(logoutsAfterMissing.first)) == "Bearer \(Self.freshAccess)", "닫는 것은 재인증 세션이지 앱 세션이 아니다")
        #expect(logoutsAfterMissing.first?.queryValue("scope") == "local")

        harness.enqueue("delete_my_account", .json(#"{"message":"boom"}"#, status: 500))
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == MobileLoadText.checkConnection)
        expectLocalIntact(harness)

        harness.enqueue("delete_my_account", .networkFailure())
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == MobileLoadText.checkConnection)
        expectLocalIntact(harness)

        harness.enqueue("delete_my_account", .json(#"{"code":"P0001","message":"not signed in"}"#, status: 400))
        #expect(await store.deleteAccount() == false)
        #expect(store.accountDeletionNotice == "계정을 지우지 못했어요 — 잠시 뒤 다시 시도해 주세요")
        expectLocalIntact(harness)
        await harness.barrier()
        #expect(harness.requests(rpc: "delete_my_account").count == 4)
        #expect(harness.model.session.isSignedIn, "4xx 삭제 거절로 앱 세션이 로그아웃되면 안 된다")
        harness.expectNoForbiddenCalls()
    }

    @Test("진행 중 재탭 방지: 재인증이 떠 있는 동안 두 번째 호출은 즉시 false · 재인증 1회 · RPC 1회")
    func secondTapWhileRunningIsIgnored() async throws {
        let harness = await RankMeHarness(label: "acct-retap") { request in
            if request.rpcName == "delete_my_account" { return MobileStubResponse(status: 204, body: Data()) }
            return Self.reauthResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        let reauthHold = BaseHold.install(host: harness.host) { $0.path == "/auth/v1/token" && $0.queryValue("grant_type") == "password" }
        store.accountDeletionPassword = Self.rightPassword
        let first = Task { await store.deleteAccount() }
        #expect(await reauthHold.waitHeld())
        #expect(store.isDeletingAccount && !store.canDeleteAccount)
        #expect(await store.deleteAccount() == false)
        #expect(await store.deleteAccount() == false)
        #expect(await reauthHold.releaseAndWaitDelivered())
        #expect(await first.value)
        await harness.barrier()
        #expect(harness.requests(path: "/auth/v1/token", method: "POST").filter { $0.queryValue("grant_type") == "password" }.count == 1)
        #expect(harness.requests(rpc: "delete_my_account").count == 1)
        expectLocalCleared(harness)
    }

    @Test("시트를 닫으면 비밀번호·문구를 비운다 · 로그인 상태가 아니면 아무것도 보내지 않는다")
    func sheetDisappearClearsDraft() async throws {
        let harness = await RankMeHarness(label: "acct-sheet") { Self.reauthResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.accountDeletionPassword = "wrong"
        _ = await store.deleteAccount()
        #expect(store.accountDeletionNotice != nil)
        store.accountDeletionDidDisappear()
        #expect(store.accountDeletionPassword.isEmpty && store.accountDeletionNotice == nil)

        await harness.model.session.signOut()
        MobileStubURLProtocol.clearRequests(host: harness.host)
        store.accountDeletionPassword = Self.rightPassword
        #expect(!store.canDeleteAccount)
        #expect(await store.deleteAccount() == false)
        #expect(await harness.model.session.deleteAccount(password: Self.rightPassword) == .failed(.notSignedIn))
        await harness.barrier()
        #expect(harness.requests.isEmpty, "로그아웃 상태에서 요청이 나갔다: \(harness.requests.map(\.path))")
    }

    @Test("문구: 실패 갈래마다 원인과 할 일 · 지워지는 것 다섯 · 원문 서버 예외 없음")
    func texts() {
        #expect(MeText.deleteAccountItems == ["근무 기록", "메시지", "할 일", "캐릭터와 루비", "순위 기록"])
        #expect(MeText.deleteAccountFailure(.wrongPassword) == "비밀번호가 맞지 않아요")
        #expect(MeText.deleteAccountFailure(.network) == "연결을 확인하고 다시 시도해 주세요")
        #expect(MeText.deleteAccountFailure(.notSignedIn) == "다시 로그인 필요")
        #expect(MeText.deleteAccountFailure(.reauthRejected("이메일 확인 필요")) == "이메일 확인 필요")
        #expect(MeText.deleteAccountFailure(.serverNotReady).contains("아직"))
        #expect(MeText.deleteAccountFailure(.rejected).contains("다시 시도"))
        #expect(MeText.deleteAccountIrreversible.contains("되돌릴 수 없어요"))
        #expect(MeText.deleteAccountFeedbackNote.contains("제보"))
    }

    // MARK: 소스 계약(주석은 걷어내고 본다)

    @Test("소스 계약: 삭제를 부르는 화면은 시트 하나(설정 화면은 시트만 연다) · 시트에 비밀번호 입력 · 파괴 버튼 role · 진행 중 잠금 · 세션은 재인증 뒤에만 RPC")
    func sourceContracts() throws {
        let callers = try IntegrationContractTests.files(containing: ["store.deleteAccount()", ".deleteAccount()"], under: "Sources/CheckMobileKit")
        #expect(callers == ["Sources/CheckMobileKit/Me/MeAccountDeletionView.swift"], "삭제를 부르는 파일이 시트 밖에 있다: \(callers)")
        let settings = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        #expect(!settings.contains("deleteAccount("), "설정 화면이 시트 없이 삭제를 부른다")
        #expect(settings.contains("MeAccountDeletionSheet(store: store)"), "설정 화면이 삭제 시트를 열지 않는다")
        #expect(settings.contains("MeText.deleteAccount") && settings.contains("MobileTheme.danger"), "계정 삭제 행이 없거나 파괴적 색이 아니다")

        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAccountDeletionView.swift")
        #expect(sheet.contains("SecureField("), "비밀번호 재입력이 없다")
        #expect(sheet.contains("role: .destructive"), "영구 삭제 버튼에 파괴 역할이 없다")
        #expect(sheet.contains("kind: .destructive"), "영구 삭제 버튼이 파괴적 색이 아니다")
        #expect(!sheet.contains("kind: .filled"), "시트에 채운(파랑) 버튼이 있다 — 되돌릴 수 없는 동작은 파괴적 색이다")
        #expect(sheet.contains("isBusy: store.isDeletingAccount"), "진행 중 버튼 잠금이 없다")
        #expect(sheet.contains(".interactiveDismissDisabled(store.isDeletingAccount)"), "도는 중에 시트를 쓸어내려 닫을 수 있다")
        #expect(sheet.contains(".disabled(!store.canDeleteAccount)"))
        #expect(sheet.contains("guard store.canDeleteAccount else { return }"), "제출 가드가 비활성 하나뿐이다")
        #expect(sheet.contains("MeText.deleteAccountItems") && sheet.contains("MeText.deleteAccountIrreversible"), "지워지는 목록·되돌릴 수 없음 한 줄이 없다")
        #expect(!sheet.contains(".alert("), "확인이 시스템 알림창이다(재질 대비 — AingConfirmSheet 주석)")
        // 키보드의 '완료' 키는 키보드만 내린다 — 되돌릴 수 없는 동작은 [영구 삭제] 버튼 하나로만 나간다(키보드 닫기 습관 한 번에 계정이 지워지면 안 된다).
        // 로그인 폼의 `.onSubmit(signIn)` 은 되돌릴 수 있는 동작이라 같은 규칙을 쓰지 않는다.
        #expect(!sheet.contains(".onSubmit(confirm)"), "키보드 '완료' 키가 곧 영구 삭제다")
        #expect(sheet.contains(".onSubmit { passwordFocused = false }"), "비밀번호 칸의 제출 키가 키보드를 내리는 것 말고 다른 일을 한다")
        #expect(sheet.components(separatedBy: "confirm").count - 1 == 2, "confirm 은 정의(func)와 버튼 action 두 곳뿐이어야 한다 — 다른 곳에서 부르면 키보드·제스처가 삭제를 쏜다")

        // 세션: 재인증(signIn) 이 RPC(deleteMyAccount) 보다 먼저 · 로컬 정리는 로그아웃과 같은 한 함수(endSession).
        let session = try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionStore.swift")
        let function = try #require(session.range(of: "func deleteAccount(password: String)"))
        let body = session[function.upperBound...]
        let reauth = try #require(body.range(of: "service.signIn(email: email, password: password)"))
        let rpc = try #require(body.range(of: "service.deleteMyAccount(accessToken: reauth.accessToken)"))
        let cleanup = try #require(body.range(of: "endSession(cleanup: nil)"))
        #expect(reauth.lowerBound < rpc.lowerBound && rpc.lowerBound < cleanup.lowerBound, "순서: 재인증 → RPC → 로컬 정리")
        #expect(session.components(separatedBy: "clearLocalUserData()").count - 1 == 3, "로컬 정리는 정의 · endSession · expireSession 세 곳뿐(계정 삭제가 따로 흉내 내지 않는다)")
        #expect(session.components(separatedBy: "endSession(cleanup:").count - 1 == 3, "endSession 은 정의 · 로그아웃 · 계정 삭제 세 곳")
        #expect(session.components(separatedBy: "$0.append(cleanup)").count - 1 == 1, "장부 적기는 endSession 안 한 곳")

        // 코어: 맥 게이트 없는 본체에 · 로그인 토큰 필수(옵셔널 아님) · 경로.
        let core = try IntegrationContractTests.code("Sources/CheckCore/SupabaseWorkService.swift")
        #expect(core.contains("package func deleteMyAccount(accessToken: String) async throws"), "코어 서명이 바뀌었다(토큰이 옵셔널이면 anon 호출 문이 열린다)")
        #expect(core.contains("\"/rest/v1/rpc/delete_my_account\""))
        let macOnly = try IntegrationContractTests.code("Sources/CheckCore/SupabaseWorkServiceMacOnly.swift")
        #expect(!macOnly.contains("delete_my_account"), "계정 삭제가 맥 전용 조각에 있다(폰이 못 부른다)")
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("delete_my_account"))
    }
}
