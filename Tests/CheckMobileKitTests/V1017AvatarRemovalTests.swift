import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 프로필 사진 지우기(기본 캐릭터로 되돌리기) — 폰 1.0.17
//
// 폰에서 올린 사진을 폰에서 못 지웠다. 코어 `removeAvatar`(맥 0.3.36 과 같은 경로)를 부르고, 문구도 코어 `AvatarRemovalText` 한 벌이다.
// 스토어는 `#if os(iOS)` 밖이라 진짜 경로를 스텁 서버로 돈다. 뷰는 소스 계약으로만 잰다.
@MainActor
@Suite(.serialized) struct V1017AvatarRemovalTests {
    private nonisolated static let me = RankMeFixture.userID
    private nonisolated static let filePath = "/storage/v1/object/avatars/\(me).jpg"
    private nonisolated static let oldPhoto = "https://example.invalid/old.jpg"

    private nonisolated static func isHeaderGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/profiles" && request.method == "GET" && request.query.contains("avatar_url")
    }

    private static func harness(
        _ label: String,
        file: MobileStubResponse = MobileStubResponse(status: 204, body: Data()),
        patch: MobileStubResponse = MobileStubResponse(status: 204, body: Data())
    ) async -> RankMeHarness {
        await RankMeHarness(label: label) { request in
            if isHeaderGET(request) { return .json(#"[{"display_name":"새벽","avatar_url":"\#(oldPhoto)"}]"#) }
            if request.path == filePath, request.method == "DELETE" { return file }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return patch }
            return nil
        }
    }

    @Test("지우기: 파일 DELETE 뒤 avatar_url 을 null 로 PATCH · 기본 캐릭터로 돌아가고 성공을 말한다")
    func removes() async throws {
        let harness = await Self.harness("v1017-avatar-ok")
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadHeader()
        #expect(store.avatarURL?.absoluteString == Self.oldPhoto)

        await store.removeAvatar()

        #expect(store.avatarURL == nil, "사진 자리가 비지 않았다")
        #expect(store.avatarNotice == "기본 캐릭터로 되돌렸어요")
        #expect(!store.isAvatarNoticeError && !store.isAvatarNoticeWarning)
        #expect(!store.isRemovingAvatar)
        let patch = try #require(harness.requests(path: "/rest/v1/profiles", method: "PATCH").first)
        #expect(patch.query.contains("id=eq.\(Self.me)"))
        #expect(Set(patch.jsonBody.keys) == ["avatar_url"], "사진 말고 다른 칸을 고쳤다: \(patch.bodyText)")
        #expect(patch.jsonBody["avatar_url"] is NSNull, "null 이 아니다: \(patch.bodyText)")
        let order = harness.requests.map(\.path).filter { $0 == Self.filePath || $0 == "/rest/v1/profiles" }
        let fileIndex = try #require(order.firstIndex(of: Self.filePath))
        let lastTable = try #require(order.lastIndex(of: "/rest/v1/profiles"))
        #expect(fileIndex < lastTable, "표를 먼저 비우면 파일 실패를 말할 자리가 없다")
        harness.expectNoForbiddenCalls()
    }

    @Test("사진이 없던 사람: 스토리지 404 도 성공이다(되돌리기가 영영 실패하지 않는다)")
    func noPhotoIsStillSuccess() async {
        let harness = await Self.harness("v1017-avatar-none", file: .json(#"{"error":"not_found"}"#, status: 404))
        defer { harness.tearDown() }
        await harness.me.removeAvatar()
        #expect(harness.me.avatarNotice == "기본 캐릭터로 되돌렸어요")
        #expect(!harness.me.isAvatarNoticeError && !harness.me.isAvatarNoticeWarning)
    }

    @Test("파일만 남음: 표는 비었으니 사진 자리는 비고 · 성공이라고 말하지 않고 경고로 다시 시도를 말한다 · 다시 누를 수 있다")
    func fileLeftIsAWarning() async {
        let harness = await Self.harness("v1017-avatar-left", file: .json(#"{"error":"forbidden"}"#, status: 403))
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadHeader()
        await store.removeAvatar()
        #expect(store.avatarURL == nil)
        #expect(store.avatarNotice == "사진 파일이 아직 남아 있어요. 잠시 후 다시 시도해 주세요")
        #expect(store.isAvatarNoticeWarning && !store.isAvatarNoticeError)

        // 표가 비었는데(avatarURL nil) 파일이 남은 사람 — 사진 유무로 막으면 안내가 거짓말이 된다.
        let before = harness.requests.filter { $0.path == Self.filePath }.count
        await store.removeAvatar()
        #expect(harness.requests.filter { $0.path == Self.filePath }.count == before + 1, "사진이 비었다고 재시도를 막았다")
    }

    @Test("표를 못 비움: 사진은 그대로고 실패를 말한다(지웠다고 거짓말하지 않는다)")
    func patchFailureKeepsPhoto() async {
        let harness = await Self.harness("v1017-avatar-fail", patch: .json(#"{"message":"boom"}"#, status: 500))
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadHeader()
        await store.removeAvatar()
        #expect(store.avatarURL?.absoluteString == Self.oldPhoto, "못 지웠는데 사진이 사라졌다")
        #expect(store.avatarNotice == "사진을 지우지 못했어요")
        #expect(store.isAvatarNoticeError && !store.isAvatarNoticeWarning)
        #expect(!store.isRemovingAvatar)
    }

    @Test("지우기 전에 떠난 머리 GET 이 늦게 와도 지운 사진을 되살리지 않는다")
    func lateHeaderDoesNotResurrect() async throws {
        let harness = await Self.harness("v1017-avatar-late")
        defer { harness.tearDown() }
        let store = harness.me
        let hold = BaseHold.install(host: harness.host, Self.isHeaderGET)
        let header = Task { await store.loadHeader() }
        #expect(await hold.waitHeld())
        await store.removeAvatar()
        #expect(store.avatarURL == nil)
        #expect(await hold.releaseAndWaitDelivered())
        await header.value
        #expect(store.avatarURL == nil, "늦은 머리 응답이 지운 사진을 되살렸다")
    }

    @Test("연타는 요청 한 번 · 지우는 동안 올리기는 나가지 않는다")
    func oneAtATime() async throws {
        let harness = await Self.harness("v1017-avatar-once")
        defer { harness.tearDown() }
        let store = harness.me
        let hold = BaseHold.install(host: harness.host) { $0.path == Self.filePath && $0.method == "DELETE" }
        let first = Task { await store.removeAvatar() }
        #expect(await hold.waitHeld())
        #expect(store.isRemovingAvatar)
        await store.removeAvatar()
        await store.uploadAvatar(imageData: try MeStoreTests.pngData(width: 400, height: 400))
        #expect(await hold.releaseAndWaitDelivered())
        await first.value
        #expect(harness.requests.filter { $0.path == Self.filePath && $0.method == "DELETE" }.count == 1, "두 번 지웠다")
        #expect(harness.requests.filter { $0.path == Self.filePath && $0.method == "POST" }.isEmpty, "지우는 중에 올렸다")
        #expect(harness.requests(path: "/rest/v1/profiles", method: "PATCH").count == 1)
    }

    @Test("로그아웃(세대 교체) 뒤에는 앞 계정의 안내·깃발이 남지 않는다")
    func resetClears() async {
        let harness = await Self.harness("v1017-avatar-reset", file: .json(#"{"error":"forbidden"}"#, status: 403))
        defer { harness.tearDown() }
        let store = harness.me
        await store.removeAvatar()
        #expect(store.isAvatarNoticeWarning)
        store.reset()
        #expect(store.avatarNotice == nil && !store.isAvatarNoticeWarning && !store.isRemovingAvatar)
    }

    @Test("화면 계약: 확인을 받은 뒤에만 지운다 · 사진 유무로 감추지 않는다 · 파일 남음은 경고색")
    func viewContract() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeProfileView.swift")
        let dialog = try #require(view.range(of: ".confirmationDialog(AvatarRemovalText.action, isPresented: $confirmingAvatarRemoval"))
        let call = try #require(view.range(of: "await store.removeAvatar()"))
        #expect(dialog.upperBound <= call.lowerBound, "확인 대화상자 밖에서 지운다")
        #expect(view.components(separatedBy: "store.removeAvatar()").count == 2, "지우기를 부르는 자리는 확인의 [되돌리기] 하나다")
        #expect(view.contains("Button(AvatarRemovalText.confirm, role: .destructive)"))
        #expect(view.contains("Text(AvatarRemovalText.confirmDetail)"))
        #expect(view.contains("confirmingAvatarRemoval = true"))
        #expect(!view.contains("store.avatarURL != nil"), "버튼이 사진 유무를 본다")
        #expect(!view.contains("store.avatarURL == nil"), "버튼이 사진 유무를 본다")
        #expect(view.contains("store.isAvatarNoticeWarning ? .warning"), "파일 남음이 경고로 안 그려진다")
    }
}
