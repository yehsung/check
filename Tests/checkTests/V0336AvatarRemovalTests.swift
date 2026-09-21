import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.36 프로필 사진 삭제(기본 캐릭터로 되돌리기)
//
// 이 스위트가 지키는 것은 넷이고, 전부 **초록인 채로 틀릴 수 있는** 자리다:
//  ① PATCH 본문에 `avatar_url` 키가 **null 로 실린다**. Optional 을 합성 인코더에 맡기면 키가 빠져 `{}` 가 되고,
//     PostgREST 는 그걸 "아무 칸도 안 고침"으로 받아 **200** 을 준다 — 화면엔 성공, 표엔 옛 URL.
//  ② 스토리지 DELETE 가 PATCH 보다 **먼저** 나간다. 뒤집히면 표만 null 이 된 채 공개 버킷에 얼굴이 남는다.
//  ③ 파일 삭제 실패(404 포함)는 삼키고 PATCH 는 그대로 나간다 = 사진 없는 사람도 되돌릴 수 있다.
//  ④ 설정 행의 2단 확인이 창 높이를 안 늘린다(확인 단계는 뷰 로컬 상태라 전체 렌더로는 절대 안 잡힌다).
//
// ⚠️ 본문 단언은 **JSONSerialization** 으로 읽는다. 기존 업로드 테스트처럼 `[String: String]` 로 디코드하면
//    null 에서 던져서, "키가 빠졌다"와 "null 이 실렸다"를 구분하기는커녕 둘 다 빨갛게 만든다.

// MARK: - 스텁

/// 경로별로 상태코드를 정해 주는 스텁. 스토리지 DELETE 를 404/403 으로 만들어 ③을 잰다.
final class AvatarRemovalURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodiesByHost: [String: [Data]] = [:]
    /// 호스트별 스토리지 DELETE 응답 코드. 없으면 200.
    nonisolated(unsafe) static var storageStatusByHost: [String: Int] = [:]
    /// 호스트별 profiles PATCH 응답 코드. 없으면 204.
    nonisolated(unsafe) static var patchStatusByHost: [String: Int] = [:]
    /// 호스트별 PATCH 응답 **지연 문**. 걸어 두면 `signal()` 하기 전까지 응답이 안 돌아온다 —
    /// "왕복이 날아가 있는 동안 세션이 갈렸다"를 재현하는 유일한 방법이다(V0334 의 gate 수법).
    nonisolated(unsafe) static var patchGateByHost: [String: DispatchSemaphore] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodiesByHost[request.url?.host ?? "", default: []].append(Self.bodyData(from: request))

        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let status: Int
        var body = Data()
        if path.hasPrefix("/storage/v1/object/avatars/") {
            status = Self.storageStatusByHost[host] ?? 200
        } else if path == "/rest/v1/profiles" {
            // 요청은 **위에서 이미 기록했다** — 문이 닫혀 있어도 테스트는 "요청이 나갔다"를 볼 수 있다.
            Self.patchGateByHost[host]?.wait()
            status = Self.patchStatusByHost[host] ?? 204
        } else {
            // 팀 재조회가 **성공**해야 "syncMessage 를 refresh 뒤에 세운다"를 잴 수 있다. 빈 본문을 주면
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

    static func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }

    static func bodies(forHost host: String) -> [Data] {
        bodiesByHost[host, default: []]
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

    try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)

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
}

// MARK: - ③ 사진이 없던 사람도 되돌릴 수 있다 / 표가 권위다

@Test
func 스토리지가_404_여도_프로필_PATCH_는_그대로_나가고_성공이다() async throws {
    let host = "avatar-remove-404"
    let userID = "00000000-0000-0000-0000-000000000002"
    AvatarRemovalURLProtocol.storageStatusByHost[host] = 404

    // 사진을 올린 적 없는 사람의 정상 경로다 — 던지면 그 사람은 이 버튼을 영영 못 쓴다.
    try await v0336Service(host: host).removeAvatar(accessToken: "access-token", userID: userID)

    let requests = AvatarRemovalURLProtocol.requests(forHost: host)
    #expect(requests.contains { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH" },
            "스토리지 404 가 PATCH 를 막았다 — 사진 없는 사람이 기본 캐릭터로 못 돌아간다")
}

@Test
func 프로필_PATCH_가_실패하면_던진다() async throws {
    let host = "avatar-remove-patch-fail"
    let userID = "00000000-0000-0000-0000-000000000002"
    AvatarRemovalURLProtocol.patchStatusByHost[host] = 403

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

    // 시계 부분도 함께 못 박는다. 초 단위면 대략 1.7e9(10자리), 밀리초면 1.7e12(13자리) — **자릿수로** 잰다
    // (문자열 접두어 `?v=` 만 보는 기존 단언은 초 단위 회귀를 못 잡는다).
    let suffix = try #require(first.split(separator: "=").last)
    let stamp = try #require(Int(suffix.split(separator: "-").first ?? ""))
    #expect(stamp > 1_000_000_000_000,
            "캐시버스터의 시계가 초 단위다(\(stamp)) — 같은 초 안의 재업로드가 갈리지 않는다")
}

// MARK: - 맥 스토어 배선

@MainActor
private func v0336Store(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: AvatarRemovalURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: UserDefaults(suiteName: "v0336-store-\(UUID().uuidString)")!
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    // 팀 재조회가 실제로 나가도록 소속을 세운다(성공 경로가 refreshTeamStatus 를 타는지 보려면 필요하다).
    store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
    store.membershipConfirmed = true
    return store
}

/// 성공 문구는 **팀 재조회 뒤**에 세워야 한다. `refreshTeamStatus` 가 성공 경로 끝에서 syncMessage 를
/// "동기화됨"으로 덮으므로, 앞에 두면 안내가 눈에 보이기도 전에 사라진다(별명 저장·사진 업로드와 같은 회귀).
@MainActor
@Test
func 되돌리기_성공_문구는_팀_재조회_뒤에_선다() async throws {
    let host = "avatar-remove-store-ok"
    let store = v0336Store(host: host)
    store.syncMessage = "시작값"

    await store.performAvatarRemoval()

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
func 되돌리기_실패_문구는_사유를_말하고_연타_가드를_푼다() async throws {
    let host = "avatar-remove-store-fail"
    AvatarRemovalURLProtocol.patchStatusByHost[host] = 403
    let store = v0336Store(host: host)
    store.syncMessage = "시작값"

    await store.performAvatarRemoval()

    #expect(store.syncMessage != "시작값", "실패를 말하지 않았다")
    #expect(store.syncMessage != AvatarRemovalText.successMessage, "실패인데 성공 문구가 섰다")
    #expect(!store.isRemovingAvatar, "실패 뒤에 연타 가드가 잠긴 채 남았다 — 다시 시도할 수 없다")
}

/// 연타 가드. 없으면 확인 버튼 두 번에 두 요청이 나가고, 늦게 온 쪽이 방금 세운 문구를 덮는다.
@MainActor
@Test
func 왕복_중에는_두_번째_되돌리기가_안_나간다() async throws {
    let host = "avatar-remove-store-reentry"
    let store = v0336Store(host: host)
    store.isRemovingAvatar = true

    await store.performAvatarRemoval()

    #expect(AvatarRemovalURLProtocol.requests(forHost: host).isEmpty,
            "왕복 중인데 두 번째 요청이 나갔다")
}

/// 로그아웃(세대 증가) 뒤에 도착한 응답은 **다음 계정 화면**에 문구를 남기지 않는다.
@MainActor
@Test
func 로그아웃_뒤에_도착한_되돌리기_응답은_다음_계정을_안_건드린다() async throws {
    let host = "avatar-remove-store-generation"
    // PATCH 응답을 붙잡아 둔다. 문 없이 Task 만 띄우면 세대 증가가 **왕복이 시작되기도 전에** 일어나
    // 이 테스트는 영원히 초록이다(가드를 지워도 통과한다 — 실제로 그렇게 한 번 통과했다).
    let gate = DispatchSemaphore(value: 0)
    AvatarRemovalURLProtocol.patchGateByHost[host] = gate
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
    await task.value

    #expect(store.syncMessage == "시작값",
            "세대가 갈렸는데 문구를 세웠다(\(store.syncMessage)) — 다음 계정 화면에 남의 안내가 뜬다")
}

// MARK: - ④ 설정 행: 2단 확인이 창 높이를 안 늘린다

@MainActor
@Test
func 되돌리기_행은_확인_단계에서도_같은_높이다() throws {
    // 확인 단계는 **뷰 로컬 상태**라 설정 화면 전체 렌더로는 절대 안 그려진다 — 씨앗으로 직접 그린다.
    let plain = try v0336RowBitmap(confirming: false)
    let confirming = try v0336RowBitmap(confirming: true)

    let plainHeight = CGFloat(plain.pixelsHigh) / 2
    let confirmHeight = CGFloat(confirming.pixelsHigh) / 2
    #expect(plainHeight == confirmHeight,
            "평소 \(plainHeight)pt · 확인 \(confirmHeight)pt — 누르는 순간 창이 그만큼 모자라 맨 아래 행이 잘린다")

    // ImageRenderer 는 Menu/Picker/TextField 를 못 그리고 그 자리에 샛노란 상자를 박는다. 이 행에 그게 있으면
    // 위 높이 비교는 "같은 노란 상자 둘"을 비교하는 셈이 된다.
    #expect(v0336YellowPixelCount(plain) == 0, "평소 상태에 '못 그림' 노란 상자가 있다")
    #expect(v0336YellowPixelCount(confirming) == 0, "확인 상태에 '못 그림' 노란 상자가 있다")

    v0336Save(plain, name: "v0336-avatar-row-plain.png")
    v0336Save(confirming, name: "v0336-avatar-row-confirming.png")
}

@MainActor
@Test
func 되돌리기_행의_문구는_사진_유무를_묻지_않는다() throws {
    // 이 행은 사진이 있든 없든 늘 보이고 늘 눌린다(없으면 404 를 삼키고 표를 null 로 덮는다).
    // 문구가 "사진이 있으면…" 으로 바뀌면 그 약속이 화면에서 깨진 것이다.
    #expect(!AvatarRemovalText.detail.contains("사진이 있"))
    #expect(AvatarRemovalText.action == "기본 캐릭터로 되돌리기")
    #expect(AvatarRemovalText.successMessage == "기본 캐릭터로 되돌렸어요")
    #expect(AvatarRemovalText.failureMessage == "사진을 지우지 못했어요")

    // 소스로 못 박는다: 행이 사진 유무(avatarURL)로 자신을 감추거나 잠그면 무소속·캐시 지연 사용자가 탈출구를 잃는다.
    // 주석을 **걷어내고** 본다(하우스 규칙) — 안 걷어내면 "왜 사진 유무를 안 묻는가"를 적어 둔 설명 자체가
    // 이 단언을 빨갛게 만들고, 그러면 설명을 지워야만 초록이 되는 테스트가 된다.
    let source = try CheckCoreSourceLayout.joinedSplitSource("CheckSettingsView.swift")
    let start = try #require(source.range(of: "struct AvatarRemovalSettingsRow: View {"))
    let end = try #require(source.range(of: "MARK: - 근무 시작", range: start.upperBound..<source.endIndex))
    let body = v0336StrippingSwiftComments(String(source[start.upperBound..<end.lowerBound]))
    #expect(!body.contains("avatarURL"), "행이 사진 유무를 읽는다 — 사진이 없는 사람의 되돌리기 버튼이 사라진다")
    // 버튼 활성은 왕복 중(isRemovingAvatar)만 본다 — 다른 조건이 붙으면 위 약속이 조용히 깨진다.
    #expect(body.contains("enabled: !isRemoving"), "되돌리기 버튼의 활성 조건이 바뀌었다")
}

// MARK: - 헬퍼

private enum V0336Error: Error { case renderFailed }

/// 렌더 전용 스토어(서비스가 필요 없다 — 이 행은 왕복 중 여부만 읽는다).
@MainActor
private func v0336RenderStore() -> WorkTimerStore {
    WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: UserDefaults(suiteName: "v0336-render-\(UUID().uuidString)")!
    )
}

/// 행 하나만, **설정 카드 안쪽 폭**에서 그린다(창 380 − 바깥 여백 14×2 − 카드 여백 12×2 = 328).
/// 실제로 놓이는 폭에서 재야 줄바꿈이 같다(V0316 과 같은 규약).
@MainActor
private func v0336RowBitmap(confirming: Bool) throws -> NSBitmapImageRep {
    let row = AvatarRemovalSettingsRow(store: v0336RenderStore(), confirmingSeed: confirming)
    let renderer = ImageRenderer(content: row.padding(8).background(CheckTheme.panel).frame(width: 328))
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0336Error.renderFailed }
    return bitmap
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
