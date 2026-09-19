import Foundation
import Testing
@testable import check
@testable import CheckCore

// 기본 아바타 = 착용 캐릭터(SPEC 작업 F · 2026-09-20) — 코어 `AppUserCharacterDirectory` · `AppUserAvatar` · 행 디코드 ·
// `fetchAppUserCharacters` 전선. 마이그레이션 계약은 `AppUserCharactersMigrationTests` 가 따로 본다.
//
// 규칙(정본): 사진 → 착용 캐릭터(null = 아잉) → **모를 때만** 이니셜. 모르는 캐릭터 id 는 아잉으로 접지 않고 nil(이니셜).
// 서버에 함수가 없으면(404 PGRST202) 조용히 빈 표.
//
// 네트워크는 아래 `AppUserCharactersStubProtocol`(테스트별 고유 호스트)로 격리한다. 기존 스텁을 쓰지 않는 이유는 소유다.

private let aucMe = "00000000-0000-0000-0000-00000000c001"
private let aucPeer = "00000000-0000-0000-0000-00000000c002"
private let aucOther = "00000000-0000-0000-0000-00000000c003"
private let aucKnown = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]

// MARK: - 스텁 네트워크

final class AppUserCharactersStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int = 200
        var body: String = "[]"
    }

    struct Call: Sendable {
        let path: String
        let method: String
        let body: String
        let authorization: String?
        let apikey: String?
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: Reply] = [:]
    private nonisolated(unsafe) static var calls: [String: [Call]] = [:]

    static func register(host: String, reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = reply
        calls[host] = []
    }

    static func recorded(host: String) -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return calls[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppUserCharactersStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        lock.lock(); defer { lock.unlock() }
        return replies[host] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        var bodyData = request.httpBody ?? Data()
        if bodyData.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                bodyData.append(buffer, count: read)
            }
            stream.close()
        }
        Self.lock.lock()
        let reply = Self.replies[host] ?? Reply(status: 599, body: "")
        Self.calls[host, default: []].append(Call(
            path: request.url?.path ?? "",
            method: request.httpMethod ?? "",
            body: String(decoding: bodyData, as: UTF8.self),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            apikey: request.value(forHTTPHeaderField: "apikey")
        ))
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func aucService(_ label: String, reply: AppUserCharactersStubProtocol.Reply) -> (SupabaseWorkService, String) {
    let host = "auc-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    AppUserCharactersStubProtocol.register(host: host, reply: reply)
    return (SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: AppUserCharactersStubProtocol.session()
    ), host)
}

private func row(_ user: String?, _ character: String?) -> AppUserCharacterRow {
    AppUserCharacterRow(userId: user, character: character)
}

// MARK: - 접기 규칙

@Test
func 캐릭터표_null_과_공백은_아잉이고_아는_캐릭터는_그대로다() {
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [
        row(aucMe, nil), row(aucPeer, "  "), row(aucOther, "fox")
    ])
    #expect(directory.characterID(for: aucMe) == "aing", "안 고른 사람(null)은 아잉이다 — 이니셜로 남으면 사용자 요청이 안 풀린다")
    #expect(directory.characterID(for: aucPeer) == "aing", "공백도 '안 고름'이다(서버 set_character 와 같은 접기)")
    #expect(directory.characterID(for: aucOther) == "fox")
    #expect(directory.count == 3)
}

@Test
func 캐릭터표_모르는_캐릭터는_아잉이_아니라_nil_이다() {
    // 서버가 이 빌드 뒤에 새 캐릭터를 더한 날. 아잉으로 접으면 "그 사람이 아잉을 입었다"는 틀린 사실을 그린다.
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucPeer, "dragon"), row(aucOther, "Fox")])
    #expect(directory.characterID(for: aucPeer) == nil, "모르는 캐릭터를 아잉으로 단정했다(열거값 확장 함정)")
    #expect(directory.characterID(for: aucOther) == nil, "대소문자가 다른 id 는 다른 캐릭터다 — 지어내지 않는다")
    // 원문은 버리지 않는다(다음 빌드가 알게 되면 표를 다시 받지 않아도 된다).
    #expect(directory.equippedID(for: aucPeer) == "dragon")
    #expect(directory.avatar(for: aucPeer, photoURL: nil) == .initials)
}

@Test
func 캐릭터표_표에_없는_사람과_빈_id_는_nil_이다() {
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe, "ghost")])
    #expect(directory.characterID(for: aucPeer) == nil, "표에 없는 사람(첫 조회 전·숨김 밖)을 아잉으로 지어냈다")
    #expect(directory.characterID(for: nil) == nil)
    #expect(directory.characterID(for: "   ") == nil)
    #expect(AppUserCharacterDirectory(knownIDs: aucKnown).characterID(for: aucMe) == nil, "빈 표(첫 조회 전)는 전원 모름이다")
}

@Test
func 캐릭터표_사용자_id_는_대소문자와_공백을_가리지_않는다() {
    // 서버는 소문자 uuid 를 주지만 UUID().uuidString 은 대문자다 — 한 호출부만 대문자로 넘겨도 영영 못 찾으면 안 된다.
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe.uppercased(), "shiba")])
    #expect(directory.characterID(for: aucMe) == "shiba")
    #expect(directory.characterID(for: " \(aucMe.uppercased()) ") == "shiba")
}

@Test
func 캐릭터표_아잉은_아는_목록이_비어도_늘_안다() {
    // null → 아잉으로 접는데 아잉을 모르면 표 전체가 이니셜이 된다(CharacterCatalog 의 안전망과 같다).
    let directory = AppUserCharacterDirectory(knownIDs: [String](), rows: [row(aucMe, nil), row(aucPeer, "fox")])
    #expect(directory.knownIDs == ["aing"])
    #expect(directory.characterID(for: aucMe) == "aing")
    #expect(directory.characterID(for: aucPeer) == nil)
}

@Test
func 캐릭터표_카탈로그로_만들면_카탈로그가_아는_것만_안다() {
    let catalog = CharacterCatalog(manifests: [CharacterManifest(id: "fox", displayName: "여우", kind: .sprite)])
    let directory = AppUserCharacterDirectory(catalog: catalog, rows: [row(aucMe, "fox"), row(aucPeer, "ghost"), row(aucOther, nil)])
    #expect(directory.knownIDs == ["aing", "fox"])
    #expect(directory.characterID(for: aucMe) == "fox")
    #expect(directory.characterID(for: aucPeer) == nil, "카탈로그(=그릴 수 있는 초상)에 없는 id 를 안다고 했다")
    #expect(directory.characterID(for: aucOther) == "aing")
}

// MARK: - 갈아 끼우기 · 즉시 반영 · 비우기

@Test
func 캐릭터표_새_응답은_통째로_갈아_끼운다() {
    var directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe, "fox"), row(aucPeer, "ghost")])
    directory.replace(with: [row(aucMe, "shiba"), row(nil, "fox"), row("", "fox")])
    #expect(directory.characterID(for: aucMe) == "shiba")
    #expect(directory.characterID(for: aucPeer) == nil, "새 표에서 빠진 사람(숨김 격리 밖·계정 삭제)의 옛 캐릭터가 남았다")
    #expect(directory.count == 1, "id 없는 행을 담았다")
    // 같은 id 가 두 번 오면 뒤의 것.
    directory.replace(with: [row(aucPeer, "fox"), row(aucPeer.uppercased(), "ghost")])
    #expect(directory.characterID(for: aucPeer) == "ghost")
    #expect(directory.count == 1)
}

@Test
func 캐릭터표_내_착용은_다음_조회_전에_바로_반영된다() {
    var directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe, nil), row(aucPeer, "fox")])
    directory.setEquipped("jellyfish", for: aucMe)
    #expect(directory.characterID(for: aucMe) == "jellyfish")
    directory.setEquipped("", for: aucMe)
    #expect(directory.characterID(for: aucMe) == "aing", "기본으로 되돌리기(빈 문자열)는 아잉이다")
    // 아직 표에 없던 나(첫 조회 전)도 바로 선다.
    var empty = AppUserCharacterDirectory(knownIDs: aucKnown)
    empty.setEquipped("squirrel", for: aucMe.uppercased())
    #expect(empty.characterID(for: aucMe) == "squirrel")
    // 빈 id 는 무시한다(열쇠 없는 칸을 만들지 않는다).
    empty.setEquipped("fox", for: "  ")
    #expect(empty.count == 1)
    #expect(directory.characterID(for: aucPeer) == "fox", "내 칸을 고치면서 남의 칸을 건드렸다")
}

@Test
func 캐릭터표_비우면_앞_계정의_표가_남지_않는다() {
    var directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe, "fox"), row(aucPeer, "ghost")])
    directory.removeAll()
    #expect(directory.isEmpty)
    #expect(directory.characterID(for: aucMe) == nil && directory.characterID(for: aucPeer) == nil)
    #expect(directory.knownIDs == Set(aucKnown), "빌드의 사실(아는 캐릭터)까지 지웠다")
    #expect(directory == AppUserCharacterDirectory(knownIDs: aucKnown))
}

// MARK: - 아바타 우선순위

@Test
func 아바타는_사진_캐릭터_이니셜_순이고_사진이_실패하면_캐릭터로_떨어진다() throws {
    let photo = try #require(URL(string: "https://example.invalid/avatars/me.png"))
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: [row(aucMe, nil), row(aucPeer, "fox"), row(aucOther, "dragon")])

    // ① 사진이 있으면 사진 — 캐릭터가 있어도.
    #expect(directory.avatar(for: aucPeer, photoURL: photo) == .photo(photo, fallbackCharacterID: "fox"))
    // 사진이 실패하면 이니셜이 아니라 캐릭터(지금은 이니셜로 떨어진다 — SPEC 이 고치라는 것).
    #expect(directory.avatar(for: aucPeer, photoURL: photo).afterPhotoFailure == .character("fox"))
    // 안 고른 사람의 사진이 실패하면 아잉.
    #expect(directory.avatar(for: aucMe, photoURL: photo).afterPhotoFailure == .character("aing"))
    // 모르는 캐릭터·모르는 사람의 사진이 실패하면 그때만 이니셜.
    #expect(directory.avatar(for: aucOther, photoURL: photo).afterPhotoFailure == .initials)
    #expect(directory.avatar(for: "nobody", photoURL: photo).afterPhotoFailure == .initials)

    // ② 사진이 없으면 캐릭터.
    #expect(directory.avatar(for: aucMe, photoURL: nil) == .character("aing"))
    #expect(directory.avatar(for: aucPeer, photoURL: nil) == .character("fox"))
    // ③ 캐릭터를 모를 때만 이니셜.
    #expect(directory.avatar(for: aucOther, photoURL: nil) == .initials)
    #expect(directory.avatar(for: nil, photoURL: nil) == .initials)
    // 사진이 아닌 판정은 실패 폴백이 자기 자신이다.
    #expect(AppUserAvatar.character("fox").afterPhotoFailure == .character("fox"))
    #expect(AppUserAvatar.initials.afterPhotoFailure == .initials)
}

// MARK: - 행 디코드(관대함)

@Test
func 캐릭터표_행_디코드는_한_행이_이상해도_배열이_죽지_않는다() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let body = """
    [
      {"user_id": "\(aucMe.uppercased())", "character": "fox"},
      {"user_id": "\(aucPeer)", "character": null},
      {"user_id": "\(aucOther)"},
      {"user_id": 42, "character": "ghost"},
      {"character": "ghost"},
      {"user_id": "   ", "character": "ghost"},
      {"user_id": "00000000-0000-0000-0000-00000000c004", "character": 7},
      null,
      "junk"
    ]
    """
    let rows = try decoder.decode([AppUserCharacterRow].self, from: Data(body.utf8))
    #expect(rows.count == 9, "원소 수가 줄었다 — 한 원소 때문에 배열 디코드가 흔들렸다")
    #expect(rows[0] == row(aucMe, "fox"), "user id 를 소문자로 접지 않았다")
    #expect(rows[1] == row(aucPeer, nil))
    #expect(rows[2] == row(aucOther, nil), "character 키가 없으면 nil(= 아잉)이다")
    #expect(rows[3].userId == nil && rows[4].userId == nil && rows[5].userId == nil)
    #expect(rows[6] == row("00000000-0000-0000-0000-00000000c004", nil), "타입이 어긋난 캐릭터는 nil 로 접어야 한다")
    #expect(rows[7] == row(nil, nil) && rows[8] == row(nil, nil))
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: rows)
    #expect(directory.count == 4)
    #expect(directory.characterID(for: aucOther) == "aing")
}

// MARK: - 전선

@MainActor
@Test
func 캐릭터표_조회는_빈_본문으로_부르고_id_없는_행을_버린다() async throws {
    let (service, host) = aucService("ok", reply: .init(body: """
    [{"user_id":"\(aucMe)","character":null},{"user_id":"\(aucPeer)","character":"ghost"},{"character":"fox"}]
    """))
    let rows = try await service.fetchAppUserCharacters(accessToken: "user-token")
    #expect(rows == [row(aucMe, nil), row(aucPeer, "ghost")])
    let calls = AppUserCharactersStubProtocol.recorded(host: host)
    #expect(calls.count == 1)
    let call = try #require(calls.first)
    #expect(call.path == "/rest/v1/rpc/app_user_characters")
    #expect(call.path == SupabaseWorkService.appUserCharactersPath)
    #expect(call.method == "POST")
    // 인자 없는 RPC — 본문은 `{}` 다(키가 하나라도 붙으면 PostgREST 가 다른 서명을 찾다 PGRST202 로 떨어진다).
    let json = try #require(try JSONSerialization.jsonObject(with: Data(call.body.utf8)) as? [String: Any])
    #expect(json.isEmpty, "본문에 키가 붙었다: \(call.body)")
    // 로그인 토큰으로만 부른다(anon 실행권이 없다).
    #expect(call.authorization == "Bearer user-token")
    #expect(call.apikey == "anon-test-key")
}

@MainActor
@Test
func 캐릭터표_함수가_없는_서버는_조용히_빈_표다() async throws {
    // db push 전에 앱이 먼저 나간 창. PostgREST 의 실제 PGRST202 본문 모양.
    let pgrst202 = #"{"code":"PGRST202","details":"Searched for the function public.app_user_characters without parameters or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.","hint":null,"message":"Could not find the function public.app_user_characters without parameters in the schema cache"}"#
    let (service, _) = aucService("missing", reply: .init(status: 404, body: pgrst202))
    let rows = try await service.fetchAppUserCharacters(accessToken: "t")
    #expect(rows.isEmpty)
    // 본문 없는 404(프록시 등)도 같은 뜻으로 받는다(폰 기기 등록과 같은 두 모양).
    let (bare, _) = aucService("missing-bare", reply: .init(status: 404, body: ""))
    #expect(try await bare.fetchAppUserCharacters(accessToken: "t").isEmpty)
    // 빈 표로 만든 디렉터리는 전원 이니셜 — 지금 화면 그대로다.
    let directory = AppUserCharacterDirectory(knownIDs: aucKnown, rows: rows)
    #expect(directory.avatar(for: aucMe, photoURL: nil) == .initials)
}

@MainActor
@Test
func 캐릭터표_일시_장애는_던진다_빈_표로_접지_않는다() async throws {
    // 빈 표로 접으면 호출부가 가진 표를 갈아 끼워 모든 아바타가 이니셜로 깜빡인다 — 던져서 "지금 표 유지"를 고르게 한다.
    let (unavailable, _) = aucService("5xx", reply: .init(status: 503, body: #"{"message":"upstream"}"#))
    await #expect(throws: SupabaseWorkServiceError.invalidResponse(503)) {
        _ = try await unavailable.fetchAppUserCharacters(accessToken: "t")
    }
    let (expired, _) = aucService("401", reply: .init(status: 401, body: #"{"code":"PGRST301","message":"JWT expired"}"#))
    await #expect(throws: SupabaseWorkServiceError.sessionExpired) {
        _ = try await expired.fetchAppUserCharacters(accessToken: "t")
    }
    // 배열이 아닌 응답(모양이 통째로 바뀐 서버)도 던진다.
    let (odd, _) = aucService("object", reply: .init(body: #"{"status":"unauthorized"}"#))
    await #expect(throws: (any Error).self) {
        _ = try await odd.fetchAppUserCharacters(accessToken: "t")
    }
}
