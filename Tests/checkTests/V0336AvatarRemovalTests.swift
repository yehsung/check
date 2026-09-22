import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.36 프로필 사진 삭제(기본 캐릭터로 되돌리기)
//
// 이 스위트가 지키는 것은 일곱이고, 전부 **초록인 채로 틀릴 수 있는** 자리다:
//  ① PATCH 본문에 `avatar_url` 키가 **null 로 실린다**. Optional 을 합성 인코더에 맡기면 키가 빠져 `{}` 가 되고,
//     PostgREST 는 그걸 "아무 칸도 안 고침"으로 받아 **200** 을 준다 — 화면엔 성공, 표엔 옛 URL.
//  ② 스토리지 DELETE 가 PATCH 보다 **먼저** 나간다. 뒤집히면 표만 null 이 된 채 공개 버킷에 얼굴이 남는다.
//  ③ 파일 삭제 결과가 **세 갈래에서 두 갈래로** 접힌다: 2xx·404 는 "없다"(성공), 그 밖의 실패는 "남았다".
//     남았는데 "되돌렸어요"라고 말하면 공개 버킷의 얼굴을 지웠다고 거짓말하는 것이다.
//  ④ 결과가 **설정 행 안에** 뜬다. `syncMessage` 만 세우면 팝오버에만 보여서 설정 창에서 누른 사람은
//     성공도 실패도 못 본다.
//  ⑤ 설정 창 높이 계약이 **확인이 열린 상태**에서도 지켜진다. 확인 단계는 누른 뒤에만 존재하므로
//     평상 렌더만 재면 "누르는 순간 잘리는 창"이 초록으로 통과한다.
//  ⑥ 확인 단계는 **창을 넘어 살아남지 않는다**. 이 창은 닫아도 뷰가 파괴되지 않아(orderOut) 아무도 안 접으면
//     다음에 열 때 빨간 [되돌리기]가 이미 무장돼 있다.
//  ⑦ 로그인 전에는 눌리지 않고, 눌려도 **말은 한다**(조용히 아무 일도 안 하는 버튼을 두지 않는다).
//
// ⚠️ 본문 단언은 **JSONSerialization** 으로 읽는다. 기존 업로드 테스트처럼 `[String: String]` 로 디코드하면
//    null 에서 던져서, "키가 빠졌다"와 "null 이 실렸다"를 구분하기는커녕 둘 다 빨갛게 만든다.

// MARK: - 스텁

/// 경로별로 상태코드를 정해 주는 스텁. 스토리지 DELETE 를 404/403 으로 만들어 ③을 잰다.
///
/// ★ **버퍼는 전부 자물쇠 뒤에 있다**(`URLProtocolStub` 과 같은 규약). `startLoading()` 은 URLSession 의
///   워커 스레드에서 불리고 이 스위트의 테스트들은 swift-testing 이 **병렬로** 돌린다 — 잠그지 않은
///   `[URLRequest]` 에 append 하면 실제 데이터 경쟁이고, 배열 재할당 중에 겹치면 간헐적 크래시·요청 유실이다
///   (유실은 "요청이 안 나갔다"로 보여서 회귀와 구분되지 않는다). 그래서 저장소는 **private** 이고
///   밖에서는 아래 정적 헬퍼로만 만진다.
final class AvatarRemovalURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var requests: [URLRequest] = []
    private nonisolated(unsafe) static var bodiesByHost: [String: [Data]] = [:]
    private nonisolated(unsafe) static var storageStatusByHost: [String: Int] = [:]
    private nonisolated(unsafe) static var patchStatusByHost: [String: Int] = [:]
    private nonisolated(unsafe) static var patchGateByHost: [String: DispatchSemaphore] = [:]
    private static let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        // 요청은 **위에서 먼저 기록한다** — 문이 닫혀 있어도 테스트는 "요청이 나갔다"를 볼 수 있다.
        Self.record(request, host: host)

        let status: Int
        var body = Data()
        if path.hasPrefix("/storage/v1/object/avatars/") {
            status = Self.storageStatus(host)
        } else if path == "/rest/v1/profiles" {
            Self.patchGate(host)?.wait()
            status = Self.patchStatus(host)
        } else {
            // 팀 재조회가 **성공**해야 "문구를 refresh 뒤에 세운다"를 잴 수 있다. 빈 본문을 주면
            // 디코드가 던져서 문구가 "동기화 실패"로 갈리고, 그러면 순서 회귀를 못 잡는다(덮는 쪽이 사라진다).
            status = 200
            body = Data("[]".utf8)
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarRemovalURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: 자물쇠 뒤의 접근자

    private static func record(_ request: URLRequest, host: String) {
        let body = bodyData(from: request)
        stateLock.lock()
        defer { stateLock.unlock() }
        requests.append(request)
        bodiesByHost[host, default: []].append(body)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requests.filter { $0.url?.host == host }
    }

    static func bodies(forHost host: String) -> [Data] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bodiesByHost[host, default: []]
    }

    /// 호스트별 스토리지 DELETE 응답 코드. 없으면 200.
    static func setStorageStatus(_ status: Int, forHost host: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        storageStatusByHost[host] = status
    }

    /// 호스트별 profiles PATCH 응답 코드. 없으면 204.
    static func setPatchStatus(_ status: Int, forHost host: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        patchStatusByHost[host] = status
    }

    /// 호스트별 PATCH 응답 **지연 문**. 걸어 두면 `signal()` 하기 전까지 응답이 안 돌아온다 —
    /// "왕복이 날아가 있는 동안 세션이 갈렸다"를 재현하는 유일한 방법이다(V0334 의 gate 수법).
    static func setPatchGate(_ gate: DispatchSemaphore, forHost host: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        patchGateByHost[host] = gate
    }

    private static func storageStatus(_ host: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storageStatusByHost[host] ?? 200
    }

    private static func patchStatus(_ host: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return patchStatusByHost[host] ?? 204
    }

    private static func patchGate(_ host: String) -> DispatchSemaphore? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return patchGateByHost[host]
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
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
        return data
    }
}

private func v0336Service(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: AvatarRemovalURLProtocol.session()
    )
}

// MARK: - ① PATCH 본문의 null

@Test
func 사진_삭제_PATCH_는_avatar_url_에_null_을_싣는다() async throws {
    let host = "avatar-remove-null"
    let userID = "00000000-0000-0000-0000-000000000002"

    let outcome = try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)
    #expect(outcome == .removed)

    let requests = AvatarRemovalURLProtocol.requests(forHost: host)
    let patchIndex = try #require(requests.firstIndex {
        $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH"
    })
    #expect(requests[patchIndex].url?.query?.contains("id=eq.\(userID)") == true)
    #expect(requests[patchIndex].value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    #expect(requests[patchIndex].value(forHTTPHeaderField: "apikey") == "anon-test-key")

    // ★ JSONSerialization 으로 읽는다 — `[String: String]` 디코드는 null 에서 던져 "키가 빠졌다"와
    //   "null 이 실렸다"를 구분하지 못한다(이 스위트가 존재하는 이유가 그 구분이다).
    let patchData = try #require(AvatarRemovalURLProtocol.bodies(forHost: host).last)
    let object = try JSONSerialization.jsonObject(with: patchData)
    let fields = try #require(object as? [String: Any], "PATCH 본문이 JSON 객체가 아니다")

    #expect(fields.keys.contains("avatar_url"),
            "본문에 avatar_url 키가 없다 — encodeIfPresent 가 키를 뺐다(본문이 {} 면 서버는 200 을 주고 아무것도 안 고친다): \(String(decoding: patchData, as: UTF8.self))")
    #expect(fields["avatar_url"] is NSNull,
            "avatar_url 이 null 이 아니다: \(String(decoding: patchData, as: UTF8.self))")
    // 화이트리스트 밖 컬럼을 같이 보내면 그 PATCH 는 통째로 403 이 된다(20260804020000 의 컬럼 grant).
    #expect(fields.count == 1, "본문에 avatar_url 말고 다른 키가 있다: \(fields.keys.sorted())")
}

// MARK: - ② 파일 → 표 순서

@Test
func 스토리지_삭제가_프로필_PATCH_보다_먼저_나간다() async throws {
    let host = "avatar-remove-order"
    let userID = "00000000-0000-0000-0000-000000000002"

    try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)

    let requests = AvatarRemovalURLProtocol.requests(forHost: host)
    let storageIndex = try #require(requests.firstIndex {
        $0.url?.path == "/storage/v1/object/avatars/\(userID).jpg" && $0.httpMethod == "DELETE"
    })
    let patchIndex = try #require(requests.firstIndex {
        $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH"
    })
    // 뒤집히면 표만 null 이 되고 공개 버킷(`/object/public/avatars/<uid>.jpg`)에 얼굴이 남는다 — 개인정보 누수다.
    #expect(storageIndex < patchIndex,
            "PATCH 가 스토리지 DELETE 보다 먼저 나갔다(storage \(storageIndex) / patch \(patchIndex))")
    #expect(requests[storageIndex].value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    #expect(requests[storageIndex].value(forHTTPHeaderField: "apikey") == "anon-test-key")
}

// MARK: - ③ 파일 삭제 결과를 **가른다**

@Test
func 스토리지가_404_여도_프로필_PATCH_는_그대로_나가고_온전한_성공이다() async throws {
    let host = "avatar-remove-404"
    let userID = "00000000-0000-0000-0000-000000000002"
    AvatarRemovalURLProtocol.setStorageStatus(404, forHost: host)

    // 사진을 올린 적 없는 사람의 정상 경로다 — 던지면 그 사람은 이 버튼을 영영 못 쓴다.
    let outcome = try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)

    #expect(outcome == .removed, "404(지울 것이 없었다)를 '파일이 남았다'로 읽었다 — 사진 없는 사람에게 경고를 띄운다")
    let requests = AvatarRemovalURLProtocol.requests(forHost: host)
    #expect(requests.contains { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH" },
            "스토리지 404 가 PATCH 를 막았다 — 사진 없는 사람이 기본 캐릭터로 못 돌아간다")
}

@Test
func 스토리지_삭제가_403_이면_표는_비우되_파일이_남았다고_말한다() async throws {
    let host = "avatar-remove-storage-403"
    let userID = "00000000-0000-0000-0000-000000000002"
    AvatarRemovalURLProtocol.setStorageStatus(403, forHost: host)

    let outcome = try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)

    // 이 한 줄이 이 갈래의 전부다. `.removed` 면 공개 버킷에 얼굴이 남은 채 "되돌렸어요"가 뜬다.
    #expect(outcome == .tableClearedFileLeft,
            "파일 삭제가 403 인데 온전한 성공이라고 했다 — 공개 URL 로는 얼굴이 그대로 보인다")
    // 표는 그래도 비운다. 화면(팀 목록·순위판·오목)이 계속 옛 사진을 그리는 쪽이 더 나쁘다.
    #expect(AvatarRemovalURLProtocol.requests(forHost: host).contains {
        $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH"
    }, "파일 삭제 실패가 표 비우기까지 막았다")
}

@Test
func 스토리지_삭제_판정은_상태코드로_한다() async throws {
    // `send(...)` 의 오류 접기(serviceError)는 404 본문을 `.authMessage("Object not found")` 로 만들어
    // 403·5xx 와 구분되지 않게 한다 — 그래서 이 함수는 상태코드를 직접 본다. 그 계약을 값으로 못 박는다.
    let userID = "00000000-0000-0000-0000-000000000002"
    for (status, expected) in [(200, SupabaseWorkService.AvatarFileDeletion.gone),
                               (204, .gone),
                               (404, .gone),
                               (403, .left),
                               (500, .left)] {
        let host = "avatar-remove-file-\(status)"
        AvatarRemovalURLProtocol.setStorageStatus(status, forHost: host)
        let result = await v0336Service(host: host).deleteAvatarFile(accessToken: "t", userID: userID)
        #expect(result == expected, "스토리지 \(status) 를 \(result) 로 읽었다(기대 \(expected))")
    }
}

@Test
func 프로필_PATCH_가_실패하면_던진다() async throws {
    let host = "avatar-remove-patch-fail"
    let userID = "00000000-0000-0000-0000-000000000002"
    AvatarRemovalURLProtocol.setPatchStatus(403, forHost: host)

    // 표가 권위다. 여기를 삼키면 팀 목록·순위판·오목이 옛 사진을 계속 그리는데 화면은 "되돌렸어요"라고 말한다.
    await #expect(throws: (any Error).self) {
        try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)
    }
}

// MARK: - 덤: 캐시버스터는 초가 아니라 밀리초다

@Test
func 업로드_캐시버스터는_같은_초_안의_두_번째_업로드와_갈린다() async throws {
    let host = "avatar-remove-cachebuster"
    let userID = "00000000-0000-0000-0000-000000000002"
    let service = v0336Service(host: host)

    // "지우고 같은 초에 다시 올리기"는 실제 경로다(이 창이 생기면서 초 단위 버스터가 위험해졌다).
    let first = try await service.uploadAvatar(accessToken: "t", userID: userID, imageData: Data([0x01]))
    let second = try await service.uploadAvatar(accessToken: "t", userID: userID, imageData: Data([0x02]))

    #expect(first != second,
            "같은 초 안의 두 업로드가 같은 URL 을 냈다 — 디스크 캐시가 옛 사진을 그대로 그린다(\(first))")

    // 기존 계약(`SupabaseWorkServiceTests.uploadAvatarUploadsToStorageThenPatchesProfile` ·
    // 폰 `MeStoreTests.avatarUpload`)이 되묻는 모양을 여기서도 못 박는다: 공개 경로 + `?v=` 한 개.
    // 이 셋이 갈리면 저쪽 둘이 먼저 빨개지는데, 그때 "무엇이 계약이었나"를 여기서 읽을 수 있어야 한다.
    #expect(first.hasPrefix("http://\(host)/storage/v1/object/public/avatars/\(userID).jpg?v="))
    #expect(first.filter { $0 == "?" }.count == 1, "쿼리가 둘 이상이다: \(first)")

    // 시계 부분도 함께 못 박는다. 초 단위면 대략 1.7e9(10자리), 밀리초면 1.7e12(13자리) — **자릿수로** 잰다
    // (문자열 접두어 `?v=` 만 보는 기존 단언은 초 단위 회귀를 못 잡는다).
    let suffix = try #require(first.split(separator: "=").last)
    let stamp = try #require(Int(suffix.split(separator: "-").first ?? ""))
    #expect(stamp > 1_000_000_000_000,
            "캐시버스터의 시계가 초 단위다(\(stamp)) — 같은 초 안의 재업로드가 갈리지 않는다")
}

// MARK: - 맥 스토어 배선

@MainActor
private func v0336Store(host: String, signedIn: Bool = true,
                        function: String = #function, line: Int = #line) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: AvatarRemovalURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        // 이름은 UUID 가 아니라 **테스트 신원**에서, 자리는 $TMPDIR(`CheckTestScratch` 머리 주석).
        // 옛 본문은 정리 코드가 아예 없어 실행마다 ~/Library/Preferences 에 plist 를 하나씩 남겼다.
        defaults: CheckTestScratch.defaults("store-L\(line)", function: function)
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    }
    // 팀 재조회가 실제로 나가도록 소속을 세운다(성공 경로가 refreshTeamStatus 를 타는지 보려면 필요하다).
    store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
    store.membershipConfirmed = true
    return store
}

/// 성공 문구는 **팀 재조회 뒤**에 세워야 한다. `refreshTeamStatus` 가 성공 경로 끝에서 syncMessage 를
/// "동기화됨"으로 덮으므로, 앞에 두면 안내가 눈에 보이기도 전에 사라진다(별명 저장·사진 업로드와 같은 회귀).
@MainActor
@Test
func 되돌리기_성공_문구는_팀_재조회_뒤에_행과_팝오버_양쪽에_선다() async throws {
    let host = "avatar-remove-store-ok"
    let store = v0336Store(host: host)
    store.syncMessage = "시작값"

    #expect(await store.performAvatarRemoval())

    // ★ 행 안의 한 줄. 이게 없으면 설정 창에서 누른 사람은 성공을 **보지 못한다**(syncMessage 는 팝오버에만 뜬다).
    #expect(store.avatarRemovalNotice == AvatarRemovalText.successMessage)
    #expect(store.avatarRemovalNoticeTone == .success)
    #expect(store.syncMessage == AvatarRemovalText.successMessage)
    #expect(!store.isRemovingAvatar, "왕복이 끝났는데 연타 가드가 안 풀렸다")
    // 팀 재조회가 **PATCH 뒤에** 실제로 나갔다는 증거. 이 단언이 없으면 refreshTeamStatus 를 통째로 빼먹어도
    // 위 문구 단언만으로 통과해, 팀 목록의 내 얼굴이 다음 폴링까지 옛 사진으로 남는다.
    let last = try #require(AvatarRemovalURLProtocol.requests(forHost: host).last)
    #expect(last.url?.path != "/rest/v1/profiles",
            "마지막 요청이 아직 PATCH 다 — 팀 재조회가 안 나갔다")
}

@MainActor
@Test
func 파일이_남으면_되돌렸다고_말하지_않는다() async throws {
    let host = "avatar-remove-store-file-left"
    AvatarRemovalURLProtocol.setStorageStatus(403, forHost: host)
    let store = v0336Store(host: host)

    #expect(await store.performAvatarRemoval() == false, "파일이 남았는데 성공을 돌려줬다")

    #expect(store.avatarRemovalNotice == AvatarRemovalText.fileLeftMessage)
    #expect(store.avatarRemovalNotice != AvatarRemovalText.successMessage,
            "공개 버킷에 얼굴이 남았는데 '되돌렸어요'라고 말했다")
    #expect(store.avatarRemovalNoticeTone == .warning, "파일이 남은 것은 성공도 실패도 아니다")
    // 푸터(한 줄)는 짧은 쪽을 쓴다 — 긴 문장은 뒤가 잘리고 하필 "다시 시도해 주세요"가 잘린다(검토 지적 ①).
    // 정본은 설정 행(avatarRemovalNotice)이고, 푸터는 곁눈질용 요약이다.
    #expect(store.syncMessage == AvatarRemovalText.shortForFooter(AvatarRemovalText.fileLeftMessage))
    #expect(store.syncMessage != AvatarRemovalText.fileLeftMessage, "푸터에 긴 문장이 그대로 갔다")
    #expect(store.syncMessage.count < AvatarRemovalText.fileLeftMessage.count)
    // 행 문구는 다시 시도할 길을 말해야 한다 — 사용자가 할 수 있는 일이 그것뿐이다.
    #expect(AvatarRemovalText.fileLeftMessage.contains("다시 시도"))
}

@MainActor
@Test
func 되돌리기_실패_문구는_사유를_말하고_연타_가드를_푼다() async throws {
    let host = "avatar-remove-store-fail"
    AvatarRemovalURLProtocol.setPatchStatus(403, forHost: host)
    let store = v0336Store(host: host)
    store.syncMessage = "시작값"

    #expect(await store.performAvatarRemoval() == false)

    #expect(store.avatarRemovalNotice != nil, "실패를 행에서 말하지 않았다")
    #expect(store.avatarRemovalNotice != AvatarRemovalText.successMessage, "실패인데 성공 문구가 섰다")
    #expect(store.avatarRemovalNoticeTone == .failure)
    #expect(store.syncMessage != "시작값", "팝오버에도 실패를 말하지 않았다")
    #expect(!store.isRemovingAvatar, "실패 뒤에 연타 가드가 잠긴 채 남았다 — 다시 시도할 수 없다")
}

/// 연타 가드. 없으면 확인 버튼 두 번에 두 요청이 나가고, 늦게 온 쪽이 방금 세운 문구를 덮는다.
@MainActor
@Test
func 왕복_중에는_두_번째_되돌리기가_안_나간다() async throws {
    let host = "avatar-remove-store-reentry"
    let store = v0336Store(host: host)
    store.isRemovingAvatar = true

    #expect(await store.performAvatarRemoval() == false)

    #expect(AvatarRemovalURLProtocol.requests(forHost: host).isEmpty,
            "왕복 중인데 두 번째 요청이 나갔다")
}

/// ⑦ 로그인 전. 요청은 안 나가되 **화면은 말한다**.
@MainActor
@Test
func 로그인_전에_누르면_요청_없이_안내만_뜬다() async throws {
    let host = "avatar-remove-store-signed-out"
    let store = v0336Store(host: host, signedIn: false)

    #expect(await store.performAvatarRemoval() == false)

    #expect(AvatarRemovalURLProtocol.requests(forHost: host).isEmpty, "로그인 전인데 요청이 나갔다")
    #expect(store.avatarRemovalNotice == AvatarRemovalText.signedOutMessage,
            "눌러도 아무 일도 안 일어나는 버튼이 됐다(\(store.avatarRemovalNotice ?? "nil"))")
}

/// 로그아웃(세대 증가) 뒤에 도착한 응답은 **다음 계정 화면**에 문구를 남기지 않는다.
@MainActor
@Test
func 로그아웃_뒤에_도착한_되돌리기_응답은_다음_계정을_안_건드린다() async throws {
    let host = "avatar-remove-store-generation"
    // PATCH 응답을 붙잡아 둔다. 문 없이 Task 만 띄우면 세대 증가가 **왕복이 시작되기도 전에** 일어나
    // 이 테스트는 영원히 초록이다(가드를 지워도 통과한다 — 실제로 그렇게 한 번 통과했다).
    let gate = DispatchSemaphore(value: 0)
    AvatarRemovalURLProtocol.setPatchGate(gate, forHost: host)
    let store = v0336Store(host: host)
    store.syncMessage = "시작값"

    let task = Task { @MainActor in await store.performAvatarRemoval() }
    // PATCH 가 실제로 나갈 때까지(스토리지 DELETE + PATCH = 2건) 기다린다.
    var spins = 0
    while AvatarRemovalURLProtocol.requests(forHost: host).count < 2, spins < 100_000 {
        await Task.yield()
        spins += 1
    }
    #expect(spins < 100_000, "PATCH 가 나가지 않았다 — 이 테스트는 아무것도 재지 못했다")

    // 여기서 로그아웃/계정 전환이 일어난다(스토어 규약: sessionGeneration 이 곧 '그 계정의 화면').
    store.sessionGeneration &+= 1
    gate.signal()
    _ = await task.value

    #expect(store.syncMessage == "시작값",
            "세대가 갈렸는데 문구를 세웠다(\(store.syncMessage)) — 다음 계정 화면에 남의 안내가 뜬다")
    #expect(store.avatarRemovalNotice == nil, "세대가 갈렸는데 행에 문구를 세웠다")
}

// MARK: - ⑥ 확인 단계는 창을 넘어 살아남지 않는다

@MainActor
@Test
func 설정_창을_닫거나_다시_열면_되돌리기_확인이_접힌다() throws {
    let store = v0336Store(host: "avatar-remove-window")
    let controller = CheckSettingsWindowController(stuckWindowCheckSeconds: 60)
    controller.configure(store: store, content: { _ in AnyView(EmptyView()) })

    // 닫기: 사용자가 확인을 연 채 창을 닫았다.
    store.isConfirmingAvatarRemoval = true
    store.avatarRemovalNotice = AvatarRemovalText.successMessage
    controller.close()
    #expect(!store.isConfirmingAvatarRemoval,
            "확인을 연 채 닫았더니 그대로 남았다 — 다음에 열면 빨간 [되돌리기]가 이미 무장돼 있다")
    #expect(store.avatarRemovalNotice == nil, "지난번 결과 한 줄이 다음 열기까지 남았다")

    // 열기: 닫기를 거치지 않은 경로(창 재생성·복구)로 상태가 살아남아도 여는 순간 접힌다.
    store.isConfirmingAvatarRemoval = true
    controller.show()
    defer { controller.close() }
    #expect(!store.isConfirmingAvatarRemoval, "창을 다시 열었는데 확인이 무장된 채였다")
}

@MainActor
@Test
func 로그아웃은_되돌리기_행을_처음_상태로_되돌린다() throws {
    let store = v0336Store(host: "avatar-remove-signout")
    store.isConfirmingAvatarRemoval = true
    store.avatarRemovalNotice = AvatarRemovalText.failureMessage
    store.avatarRemovalNoticeTone = .failure

    store.resetAvatarRemovalRow()

    #expect(!store.isConfirmingAvatarRemoval)
    #expect(store.avatarRemovalNotice == nil)
    #expect(store.avatarRemovalNoticeTone == .success)
}

// MARK: - ⑤ 창 높이 계약: 확인이 **열린 상태**도 예산 안이다

/// 이 테스트가 이 스위트의 배포 차단 지점이다.
///
/// 앞선 판(v0.3.36 1차)은 행을 **카드 안쪽 폭보다 16pt 좁게** 그렸다(`row.padding(8)` 에 `frame(width: 328)`
/// 을 걸면 행에 남는 폭은 312 다). 312 에서는 평소 설명도 두 줄로 접혀 두 상태가 **둘 다 59pt** 였고,
/// "확인 단계는 높이를 안 바꾼다"는 단언이 초록으로 통과했다. 실제로 놓이는 폭 328 에서는 46 → 59,
/// 즉 **13pt 가 자란다** — 누르는 순간 창 맨 아래가 그만큼 잘린다.
///
/// 그래서 여기서는 **설정 화면 전체를 네 상태로 그려서** 잰다. 확인 단계가 스토어 상태라 가능한 일이다
/// (뷰 `@State` 였다면 전체 렌더는 영원히 평상 상태만 그린다 — 앞선 판이 씨앗 인자를 둬야 했던 이유).
@MainActor
@Test
func 설정_창은_되돌리기_확인이_열린_상태에서도_예산_안이다() throws {
    for admin in [false, true] {
        let budget = admin
            ? CheckSettingsView.adminContentHeight
            : CheckSettingsWindowController.defaultContentSize.height

        var heights: [String: CGFloat] = [:]
        for state in V0336RowState.allCases {
            let height = try v0336SettingsHeight(admin: admin, state: state)
            heights[state.label] = height
            #expect(height <= budget,
                    "관리자=\(admin) · \(state.label) 상태의 설정 콘텐츠가 \(height)pt 다 — 예산 \(budget)pt 를 넘어 맨 아래 행이 잘린다")
        }

        let plain = try #require(heights[V0336RowState.plain.label])
        let confirming = try #require(heights[V0336RowState.confirming.label])
        // 닫힌 상태와 열린 상태를 **둘 다** 못 박는다. 열린 쪽만 재면 평상 상태가 조용히 자라도 안 걸리고,
        // 닫힌 쪽만 재면 앞선 판과 같은 구멍이 다시 열린다.
        #expect(confirming - plain == AvatarRemovalSettingsRow.maxExtraHeight,
                "확인을 열면 \(confirming - plain)pt 자란다 — 선언값 \(AvatarRemovalSettingsRow.maxExtraHeight)pt 와 갈렸다(관리자=\(admin))")
        #expect(plain < confirming, "확인 단계가 평상보다 크지 않다 — 두 상태가 같은 그림이면 이 비교는 아무것도 못 잰다")
    }
}

/// 행 하나만 **실제로 놓이는 폭**에서 그린다. 노란 상자(ImageRenderer 가 못 그린 자리)가 하나라도 있으면
/// 위 높이 비교는 "같은 노란 상자 둘"을 비교하는 셈이 된다.
@MainActor
@Test
func 되돌리기_행은_실제_폭에서_네_상태_모두_픽셀로_그려진다() throws {
    for state in V0336RowState.allCases {
        let bitmap = try v0336RowBitmap(state: state)
        #expect(v0336YellowPixelCount(bitmap) == 0, "\(state.label) 상태에 '못 그림' 노란 상자가 있다")
        let height = CGFloat(bitmap.pixelsHigh) / 2
        // 행 하나가 창 예산을 먹지 않는지도 함께 잰다(V0316 의 선택기 행과 같은 상한).
        #expect(height <= 90, "\(state.label) 상태의 행이 \(height)pt 다 — 한 행이 창 높이 예산을 먹는다")
        v0336Save(bitmap, name: "v0336-avatar-row-\(state.fileName).png")
    }

    // 행 단독으로 잰 자람도 선언값과 같아야 한다(전체 렌더와 행 렌더가 같은 사실을 말하는지).
    // **두 폭에서 잰다**: 계약 폭(창 폭 하한 380 → 카드 안쪽 328)과 **기본 창이 실제로 여는 폭**
    // (defaultContentSize.width 420 → 카드 안쪽 368). 앞선 판이 312 에서만 재다 놓친 자리라, 여기서는
    // 사람이 실제로 보는 폭도 함께 못 박는다(둘 다 46 → 59, 실측 2026-09-21).
    for width in [v0336CardContentWidth, CheckSettingsWindowController.defaultContentSize.width - 14 * 2 - 12 * 2] {
        let plain = CGFloat(try v0336RowBitmap(state: .plain, width: width).pixelsHigh) / 2
        let confirming = CGFloat(try v0336RowBitmap(state: .confirming, width: width).pixelsHigh) / 2
        #expect(confirming - plain == AvatarRemovalSettingsRow.maxExtraHeight,
                "폭 \(width) 에서 행 단독 자람이 \(confirming - plain)pt 다 — 선언값 \(AvatarRemovalSettingsRow.maxExtraHeight)pt 와 갈렸다")
        #expect(plain < confirming, "폭 \(width) 에서 두 상태가 같은 높이다 — 이 폭에서는 아무것도 재지 못한다")
    }

    // 설정 화면 전체도 평상·확인 두 장 남긴다(사람이 눈으로 보는 증거).
    v0336Save(try v0336SettingsBitmap(admin: false, state: .plain), name: "v0336-settings-plain.png")
    v0336Save(try v0336SettingsBitmap(admin: false, state: .confirming), name: "v0336-settings-confirming.png")
    v0336Save(try v0336SettingsBitmap(admin: false, state: .fileLeft), name: "v0336-settings-file-left.png")
}

@MainActor
@Test
func 되돌리기_행의_문구는_사진_유무를_묻지_않는다() throws {
    // 이 행은 사진이 있든 없든 늘 보이고 늘 눌린다(없으면 404 를 "없다"로 읽고 표를 null 로 덮는다).
    // 문구가 "사진이 있으면…" 으로 바뀌면 그 약속이 화면에서 깨진 것이다.
    #expect(!AvatarRemovalText.detail.contains("사진이 있"))
    #expect(AvatarRemovalText.action == "기본 캐릭터로 되돌리기")
    #expect(AvatarRemovalText.successMessage == "기본 캐릭터로 되돌렸어요")
    #expect(AvatarRemovalText.failureMessage == "사진을 지우지 못했어요")
    // 파일이 남은 갈래는 성공·실패 어느 문구와도 **달라야** 한다(같으면 갈래가 화면에서 사라진다).
    #expect(AvatarRemovalText.fileLeftMessage != AvatarRemovalText.successMessage)
    #expect(AvatarRemovalText.fileLeftMessage != AvatarRemovalText.failureMessage)

    // 소스로 못 박는다: 행이 사진 유무(avatarURL)로 자신을 감추거나 잠그면 무소속·캐시 지연 사용자가 탈출구를 잃는다.
    // 주석을 **걷어내고** 본다(하우스 규칙) — 안 걷어내면 "왜 사진 유무를 안 묻는가"를 적어 둔 설명 자체가
    // 이 단언을 빨갛게 만들고, 그러면 설명을 지워야만 초록이 되는 테스트가 된다.
    let source = try CheckCoreSourceLayout.joinedSplitSource("CheckSettingsView.swift")
    let start = try #require(source.range(of: "struct AvatarRemovalSettingsRow: View {"))
    let end = try #require(source.range(of: "MARK: - 근무 시작", range: start.upperBound..<source.endIndex))
    let body = v0336StrippingSwiftComments(String(source[start.upperBound..<end.lowerBound]))
    #expect(!body.contains("avatarURL"), "행이 사진 유무를 읽는다 — 사진이 없는 사람의 되돌리기 버튼이 사라진다")
    // 버튼 활성은 왕복 중(isRemovingAvatar)과 **로그인 여부**만 본다. 다른 조건이 붙으면 위 약속이 조용히 깨진다.
    #expect(body.contains("enabled: !isRemoving && !signedOut"), "되돌리기 버튼의 활성 조건이 바뀌었다")
    // 확인 단계가 뷰 `@State` 로 돌아가면 창을 닫아도 남는다(v0.3.36 검토 지적 ④).
    #expect(!body.contains("@State"),
            "확인 단계가 다시 뷰 로컬 상태가 됐다 — 창을 닫아도 빨간 [되돌리기]가 무장된 채로 남는다")
    #expect(body.contains("store.isConfirmingAvatarRemoval"), "확인 단계를 스토어에서 읽지 않는다")
}

// MARK: - 헬퍼

// 이름이 갈래 A 의 V0336AvatarArtTests 와 겹쳐(그쪽은 internal) 병합에서 재선언 오류가 났다 — 이 파일 쪽을 좁힌다.
private enum V0336RemovalError: Error { case renderFailed }

/// 행이 가질 수 있는 네 상태. **렌더 테스트가 이 전부를 돈다** — 하나라도 빠지면 그 상태의 높이는 아무도 안 잰다.
enum V0336RowState: CaseIterable {
    case plain
    case confirming
    case fileLeft
    case failure

    var label: String {
        switch self {
        case .plain: return "평상"
        case .confirming: return "확인"
        case .fileLeft: return "파일 남음"
        case .failure: return "실패"
        }
    }

    var fileName: String {
        switch self {
        case .plain: return "plain"
        case .confirming: return "confirming"
        case .fileLeft: return "file-left"
        case .failure: return "failure"
        }
    }
}

/// 렌더 전용 스토어. **로그인 상태로 만든다** — 로그아웃 상태로 그리면 이 행은 버튼이 잠긴 다른 그림이고,
/// 그러면 사용자가 실제로 보는 가장 높은 상태를 한 번도 안 재게 된다.
///
/// `function`·`line` 은 **호출 지점**에서 평가되는 기본 인자라 호출자를 안 고치고 자기 신원을 준다.
/// 받아서 이어 넘겨야 한다 — 안 그러면 이름이 `v0336RenderStore` 로 굳어 전부 한 스위트다.
/// 한 테스트가 네 상태를 나란히 그리므로 `state` 도 함께 이름에 넣는다.
@MainActor
private func v0336RenderStore(state: V0336RowState,
                              function: String = #function,
                              line: Int = #line) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("render-\(state.fileName)-L\(line)", function: function)
    )
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "me")
    switch state {
    case .plain:
        break
    case .confirming:
        store.isConfirmingAvatarRemoval = true
    case .fileLeft:
        store.avatarRemovalNotice = AvatarRemovalText.fileLeftMessage
        store.avatarRemovalNoticeTone = .warning
    case .failure:
        store.avatarRemovalNotice = AvatarRemovalText.failureMessage
        store.avatarRemovalNoticeTone = .failure
    }
    return store
}

/// 행이 **실제로 놓이는 폭**(설정 카드 안쪽). 창 폭 하한(preferredWidth) − 바깥 여백 14×2 − 카드 여백 12×2.
/// 숫자를 손으로 적지 않고 계약에서 끌어오는 것이 요점이다 — 여백이 바뀌면 이 값도 따라 움직여야 한다.
/// (높이 계약은 언제나 **폭 하한**에서 잰다: 폭이 넓어지면 줄바꿈이 줄어 콘텐츠는 같거나 작아진다.)
@MainActor private var v0336CardContentWidth: CGFloat { CheckSettingsView.preferredWidth - 14 * 2 - 12 * 2 }

@MainActor
private func v0336RowBitmap(state: V0336RowState, width: CGFloat? = nil,
                            function: String = #function) throws -> NSBitmapImageRep {
    let row = AvatarRemovalSettingsRow(store: v0336RenderStore(state: state, function: function))
    // ★ `frame` 은 **행에** 건다. 패딩 바깥에 걸면 행에 남는 폭이 패딩만큼(16pt) 줄어 줄바꿈이 달라진다 —
    //   앞선 판이 확인 단계의 자람을 통째로 놓친 원인이 정확히 이 한 줄이었다.
    let content = row.frame(width: width ?? v0336CardContentWidth).padding(8).background(CheckTheme.panel)
    let renderer = ImageRenderer(content: content)
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0336RemovalError.renderFailed }
    return bitmap
}

/// 설정 화면 **전체**를 창 폭 하한에서 그린다(V0316 과 같은 규약 — 단축키 안내 한 줄까지 켠 가장 높은 상태).
@MainActor
private func v0336SettingsBitmap(admin: Bool, state: V0336RowState,
                                 function: String = #function) throws -> NSBitmapImageRep {
    let store = v0336RenderStore(state: state, function: function)
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    store.ultraUnlimited = admin
    store.workShortcutStatus = .conflict
    // 한 테스트가 admin·state 를 바꿔 이 그림을 셋까지 그린다 — 둘 다 이름에 넣어 갈라 둔다.
    let tag = "settings-\(admin)-\(state.fileName)"
    let suiteName = CheckTestScratch.suitePath(tag, function: function)
    let defaults = CheckTestScratch.defaults(tag, function: function)
    // `removeSuite(named:)` 는 검색 목록에서 빼기만 한다 — 정리로 세지 마라. 진짜 정리는 만들 때 했다.
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
    let renderer = ImageRenderer(
        content: CheckSettingsView(store: store, launchAtLoginSeed: false, characterDefaults: defaults)
            .frame(width: CheckSettingsView.preferredWidth)
    )
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0336RemovalError.renderFailed }
    return bitmap
}

@MainActor
private func v0336SettingsHeight(admin: Bool, state: V0336RowState) throws -> CGFloat {
    CGFloat(try v0336SettingsBitmap(admin: admin, state: state).pixelsHigh) / 2
}

/// ImageRenderer 의 "못 그림" 표식(샛노란 상자, 실측 255/204/0) 픽셀 수.
private func v0336YellowPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if Int(data[o]) >= 240 && Int(data[o + 1]) >= 195 && Int(data[o + 2]) <= 40 { count += 1 }
        }
    }
    return count
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙). 문자열 리터럴 안의 `//` 는 남긴다 —
/// URL 문자열이 주석으로 오인되면 그 뒤 코드가 통째로 검사에서 사라진다.
private func v0336StrippingSwiftComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if character == "\n" {
                inLineComment = false
                result.append(character)
            }
        } else if inBlockComment {
            if character == "*", next == "/" {
                inBlockComment = false
                index += 1
            }
        } else if inString {
            if character == "\"", previous != "\\" { inString = false }
            result.append(character)
        } else if character == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if character == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else if character == "\"" {
            inString = true
            result.append(character)
        } else {
            result.append(character)
        }
        previous = character
        index += 1
    }
    return result
}

private func v0336Save(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0336", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}
