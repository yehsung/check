import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.43 로봇 — 상점 RPC 의 능력 번호(`p_protocol`)와 404 폴백.
///
/// 이 스위트가 지키는 것은 **네 가지 사실**이다:
///  ① "robot 을 그릴 수 있다" ⟺ "1 을 보낸다"(양방향. 한쪽만 재면 상수 1 을 박아도 초록이다)
///  ② 서버가 아직 안 올라가도 상점이 산다(404 → 한 번 되묻기 → 잠시 옛 모양 → **만료 뒤 다시 묻기**)
///  ③ `needs_update` 는 "구매 실패" 가 아니라 자기 문장을 가진다(루비는 안 깎였다 — 사용자가 할 일은 업데이트다)
///  ④ 그 번호가 **목록과 구매 두 호출부에서** 전선에 실린다(한쪽만 실리면 게이트가 장식이다 — B12)
///
/// 단언은 전부 **실제로 나간 본문**(JSON 키·값)이나 **화면에 남은 문구**로 잰다. "인자를 넘겼다" 는 재지 않는다 —
/// 넘긴 값이 전선에 어떤 모양으로 실리는지가 이 변경의 전부다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
///
/// ★ **번들을 기준선으로 쓰지 않는 자리가 왜 따로 있나**: 맥 번들에는 아직 `Characters/robot/` 이 없다.
///   그래서 "번들이 기준선" 인 단언은 `키 없음 == true` / `본문 {} == true` 로 **퇴화**하고, 배선을 통째로 지운
///   코드가 내는 본문과 바이트가 같아진다(실측: 두 호출부의 `protocolVersion:` 을 지워도 37건 전부 초록).
///   그래서 `drawableCharacterIDs` 에 가짜 명단을 꽂아 **스토어의 진짜 경로를 1 쪽 분기로도** 돌린다.
@Suite("v0.3.43 로봇 상점 프로토콜")
struct V0343RobotShopProtocolTests {

    // MARK: - ① 파생 — "그릴 수 있다" 와 "1 을 보낸다" 는 서로 필요충분이다

    /// ★ **양방향으로 잰다.** 한 방향만 재면 `protocolVersion` 이 상수 1 을 돌려줘도(= 그림 없는 폰이 1 을 보내는
    ///   바로 그 사고) 초록이다. 기준선은 파생식도 카탈로그도 아니라 **소스 트리의 그림 파일**이다 —
    ///   같은 식으로 기대값을 만들면 그 테스트는 영원히 초록이다([[comparison-baseline-must-differ]]).
    @MainActor
    @Test("robot 을 그릴 수 있을 때만 1 을 보낸다 — 그림 파일이 유일한 기준선")
    func protocolIsDerivedFromBundledArtBothWays() async throws {
        // 기준선: 소스 트리에 robot 의 초상·아틀라스가 실제로 놓였는가(카탈로그를 묻지 않는다 — 아래 §⑤ 근거).
        let canDrawRobot = Self.robotArtInSourceTree

        // (가) 그릴 수 있다 → 1, 못 그린다 → 0. 숫자 둘을 다 못 박는다(0 쪽을 빼면 "늘 1" 도 통과한다).
        let host = "shop-new-\(UUID().uuidString.lowercased())"
        let store = Self.store(host: host)
        #expect(store.shopProtocolVersion == (canDrawRobot ? ShopWire.robotProtocol : ShopWire.legacyProtocol),
                Comment(rawValue: "그림 \(canDrawRobot) · 명단 \(store.drawableCharacterIDs) → \(store.shopProtocolVersion)"))

        // (나) 그 값이 **전선에 실제로 나가는지**. 스토어의 진짜 경로(loadShopState)로 보낸다.
        store.loadShopState()
        #expect(await Self.waitUntil { store.shopLoaded || store.shopFailed }, "상점 조회가 안 끝났다")
        let body = try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath)))

        // 필요충분 ①: p_protocol 키가 실렸다 ⟺ robot 을 그릴 수 있다.
        #expect(body.keys.contains("p_protocol") == canDrawRobot,
                Comment(rawValue: "본문 \(body) · 그릴 수 있나 \(canDrawRobot)"))
        // 필요충분 ②: 그 값이 1 이다 ⟺ robot 을 그릴 수 있다.
        #expect((body["p_protocol"] as? Int == ShopWire.robotProtocol) == canDrawRobot)
        // 필요충분 ③: 본문이 옛 모양 `{}` 다 ⟺ robot 을 못 그린다. (키를 다른 이름으로 실어도 여기서 잡힌다.)
        #expect(body.isEmpty == !canDrawRobot, Comment(rawValue: "본문 \(body)"))
    }

    /// 파생 함수 자체의 양방향 — 집합에 robot 이 **있을 때만** 1 이다.
    /// (위 테스트는 지금 번들 상태 하나만 지난다. 그림이 구워지기 전에도 1 쪽 분기가 돌아야 한다.)
    @Test("파생 함수는 robot 이 들어 있을 때만 1 이다")
    func derivationAnswersBothBranches() {
        let withoutRobot = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: withoutRobot) == 0)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: withoutRobot + ["robot"]) == 1)
        // 비슷한 이름에 반응하면 안 된다(옛 금지 이름 `bot` · 접두사 겹침 · 대문자).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: ["bot", "robots", "ROBOT"]) == 0)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: []) == 0)
    }

    // MARK: - ④ 스토어의 두 호출부 — 번들 상태와 무관하게 양쪽 분기를 돌린다

    /// ★ **이 테스트가 배선을 지키는 그물이다.** 번들에 robot 이 없는 지금, 위 ① 의 세 단언은 전부
    ///   "키 없음·본문 `{}`" 로 퇴화해 **배선을 지운 코드와 바이트가 같다**. 여기서는 가짜 명단을 꽂아
    ///   `loadShopState()`·`buyCharacter(_:)` 의 진짜 경로를 **1 쪽으로도** 돌리고, 나간 본문을 JSON 으로 연다.
    ///
    ///   물리는 변형(전부 실측): 두 호출부의 `protocolVersion:` 삭제(①a) · 구매만 삭제(①c, '게이트가 장식') ·
    ///   구매만 `legacyProtocol` 로 바꾸기 · `shopProtocolVersion` 을 상수로 바꾸기(⑨).
    @MainActor
    @Test("목록과 구매가 **같은 번호**를 전선에 싣는다 — 명단에 robot 이 있는 쪽·없는 쪽 둘 다")
    func bothCallSitesCarryTheSameProtocolOnTheWire() async throws {
        // ── 1 쪽: 그림이 실린 출하 모양(그림이 번들에 들어오는 날의 상태를 명단으로 만든다) ──
        let newHost = "shop-new-\(UUID().uuidString.lowercased())"
        let drawing = Self.store(host: newHost)
        drawing.drawableCharacterIDs = ["aing", "fox", "robot"]
        #expect(drawing.shopProtocolVersion == ShopWire.robotProtocol, "명단에 robot 이 있는데 0 을 고른다")

        drawing.loadShopState()
        #expect(await Self.waitUntil { drawing.shopLoaded || drawing.shopFailed }, "상점 조회가 안 끝났다")
        let listNew = try Self.json(try #require(Self.lastBody(host: newHost, path: Self.shopStatePath)))
        #expect(Set(listNew.keys) == ["p_protocol"], Comment(rawValue: "목록 본문 \(listNew)"))
        #expect(listNew["p_protocol"] as? Int == 1, Comment(rawValue: "목록 본문 \(listNew)"))
        // 결과까지: 1 을 보냈으니 서버가 robot 행을 내려 주고 카드가 선다(본문만 보고 끝내지 않는다).
        #expect(drawing.shopCharacters.map(\.id).contains("robot"),
                Comment(rawValue: "목록 \(drawing.shopCharacters.map(\.id))"))

        drawing.buyCharacter("robot")
        #expect(await Self.waitUntil { drawing.purchasingID == nil }, "구매가 안 끝났다")
        let buyNew = try Self.json(try #require(Self.lastBody(host: newHost, path: Self.buyCharacterPath)))
        #expect(Set(buyNew.keys) == ["p_id", "p_protocol"], Comment(rawValue: "구매 본문 \(buyNew)"))
        #expect(buyNew["p_id"] as? String == "robot")
        #expect(buyNew["p_protocol"] as? Int == 1, Comment(rawValue: "구매 본문 \(buyNew) — 목록 1·구매 0 이면 게이트가 장식이다"))

        // ── 0 쪽: 그림이 없는 빌드(지금 맥·폰). 키가 **없어야** 한다 ──
        let oldHost = "shop-new-\(UUID().uuidString.lowercased())"
        let blind = Self.store(host: oldHost)
        blind.drawableCharacterIDs = ["aing", "fox"]
        #expect(blind.shopProtocolVersion == ShopWire.legacyProtocol, "명단에 robot 이 없는데 1 을 고른다")

        blind.loadShopState()
        #expect(await Self.waitUntil { blind.shopLoaded || blind.shopFailed }, "상점 조회가 안 끝났다")
        let listOld = try Self.json(try #require(Self.lastBody(host: oldHost, path: Self.shopStatePath)))
        #expect(listOld.isEmpty, Comment(rawValue: "목록 본문 \(listOld)"))
        #expect(blind.shopCharacters.map(\.id).contains("robot") == false,
                Comment(rawValue: "0 을 보냈는데 robot 카드가 섰다: \(blind.shopCharacters.map(\.id))"))

        blind.buyCharacter("fox")
        #expect(await Self.waitUntil { blind.purchasingID == nil }, "구매가 안 끝났다")
        let buyOld = try Self.json(try #require(Self.lastBody(host: oldHost, path: Self.buyCharacterPath)))
        #expect(Set(buyOld.keys) == ["p_id"], Comment(rawValue: "구매 본문 \(buyOld)"))
    }

    // MARK: - ② 두 모양의 본문 — 문자열 포함이 아니라 JSON 키·값으로 잰다

    @Test("새 모양·옛 모양 본문의 키와 값")
    func requestBodiesCarryExactKeys() async throws {
        let host = "shop-new-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)

        // 새 모양: shop_state 는 p_protocol 하나만, buy_character 는 p_id + p_protocol 둘만.
        _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        let shopNew = try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath)))
        #expect(Set(shopNew.keys) == ["p_protocol"], Comment(rawValue: "\(shopNew)"))
        #expect(shopNew["p_protocol"] as? Int == 1)

        _ = try await service.buyCharacter(accessToken: "t", id: "robot",
                                          protocolVersion: ShopWire.robotProtocol)
        let buyNew = try Self.json(try #require(Self.lastBody(host: host, path: Self.buyCharacterPath)))
        #expect(Set(buyNew.keys) == ["p_id", "p_protocol"], Comment(rawValue: "\(buyNew)"))
        #expect(buyNew["p_id"] as? String == "robot")
        #expect(buyNew["p_protocol"] as? Int == 1)

        // 옛 모양: 키가 **없어야** 한다. 0 을 실으면 뜻은 같아도 아직 안 올라간 서버에서 공짜로 404 를 맞는다.
        let legacyHost = "shop-new-\(UUID().uuidString.lowercased())"
        let legacyService = Self.service(host: legacyHost)
        _ = try await legacyService.fetchShopState(accessToken: "t")
        let shopOld = try Self.json(try #require(Self.lastBody(host: legacyHost, path: Self.shopStatePath)))
        #expect(shopOld.isEmpty, Comment(rawValue: "\(shopOld)"))

        _ = try await legacyService.buyCharacter(accessToken: "t", id: "fox")
        let buyOld = try Self.json(try #require(Self.lastBody(host: legacyHost, path: Self.buyCharacterPath)))
        #expect(Set(buyOld.keys) == ["p_id"], Comment(rawValue: "\(buyOld)"))
        #expect(buyOld["p_id"] as? String == "fox")
    }

    // MARK: - ③ 404 폴백 — 서버가 아직 안 올라가도 상점이 산다

    /// ★ 이 겹이 없으면 `{"p_protocol":1}` 을 보내는 앱에서 **상점이 통째로 죽는다**(잔량·가격·보유 전부).
    ///   그래서 스텁이 실제로 PGRST202 404 를 돌려주고, **되묻는 본문**과 **그 다음 호출의 첫 본문**을 둘 다 잰다.
    ///
    /// ⚠️ 건수 단언 뒤에 바로 색인하면 안 된다. swift-testing 의 `#expect` 는 **기록만 하고 넘어가므로**
    ///   `bodies[1]` 은 "빨개진다"가 아니라 `Index out of range` → signal 5 → **checkTests 프로세스가 죽는다**
    ///   (실측: 233건이 그 지점에서 중단돼 뒤 순번은 아예 돌지 않았다). 끊는 자리는 `try #require` 다.
    @Test("404 를 만나면 한 번 되묻고, 그 뒤로는 처음부터 옛 모양으로 보낸다")
    func fallsBackOnceThenRemembers() async throws {
        let host = "shop-old-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)

        // ① 새 모양 → 404 → 옛 모양으로 되묻기. 호출부는 성공으로 본다(상점이 산다).
        let first = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(first.rubyBalance == 100, "폴백 응답을 못 읽었다 — 되묻기가 돌지 않았다")
        var bodies = Self.bodies(host: host, path: Self.shopStatePath)
        try #require(bodies.count == 2, Comment(rawValue: "요청 \(bodies)"))
        #expect(try Self.json(bodies[0])["p_protocol"] as? Int == 1, "첫 요청이 새 모양이 아니다")
        #expect(try Self.json(bodies[1]).isEmpty, Comment(rawValue: "되묻기 본문이 `{}` 가 아니다: \(bodies[1])"))

        // ② 같은 서비스로 다시 → **처음부터** 옛 모양. 404 를 매번 두 번 맞지 않는다.
        _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        bodies = Self.bodies(host: host, path: Self.shopStatePath)
        try #require(bodies.count == 3, Comment(rawValue: "되묻기가 또 돌았다: \(bodies)"))
        #expect(try Self.json(bodies[2]).isEmpty, Comment(rawValue: "세 번째 요청이 옛 모양이 아니다: \(bodies[2])"))

        // ③ 깃발은 목록·구매가 **함께** 쓴다(마이그레이션 한 장이 두 서명을 같이 바꾼다).
        //    따로 두면 "목록은 새 모양, 구매는 옛 모양" 조합이 생기고 그건 서버에 없는 상태다.
        _ = try await service.buyCharacter(accessToken: "t", id: "fox", protocolVersion: ShopWire.robotProtocol)
        let buys = Self.bodies(host: host, path: Self.buyCharacterPath)
        try #require(buys.count == 1, Comment(rawValue: "구매가 404 를 또 맞았다: \(buys)"))
        #expect(Set(try Self.json(buys[0]).keys) == ["p_id"], Comment(rawValue: "\(buys[0])"))
    }

    /// ★ **깃발은 영구적이면 안 된다.** F0 이 고른 배포 순서는 **앱 먼저**(db push 는 CLI 계정 교체 대기)다 —
    ///   그림이 실린 0.3.43 이 db push 전에 상점을 한 번 열면 깃발이 서고, 영구 깃발이면 그 뒤 db push 가 끝나도
    ///   **그 실행 동안 영영** 옛 모양만 나가 robot 카드를 못 본다. `service` 는 프로세스와 수명이 같고 메뉴바 앱은
    ///   몇 주 산다 — 복구 수단이 앱 재시작뿐이었다. 그래서 '서버·앱 순서 무관'(B15)이 선택된 순서에서 깨졌다.
    ///
    /// 재는 방법: 스텁 서버를 **실행 중에** 업그레이드하고 바늘을 재확인 간격만큼 돌린다. 결과는 본문 세 개가
    /// 아니라 **사용자가 보는 목록**으로 잰다.
    @Test("db push 가 실행 중에 끝나면, 재확인 간격 뒤 robot 이 보인다 — 앱 재시작이 필요 없다")
    func flagExpiresSoMidRunDBPushIsPickedUp() async throws {
        let host = "shop-upgrade-\(UUID().uuidString.lowercased())"
        let hands = Self.Hands(start: Date(timeIntervalSince1970: 1_760_000_000))
        let service = Self.service(host: host, clock: hands.read)

        // ① db push 전: 404 → 되묻기 → 옛 목록. robot 은 없다.
        let before = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(before.characters?.map(\.id) == ["fox"], Comment(rawValue: "\(before.characters?.map(\.id) ?? [])"))

        // ② db push 가 끝났다(사용자가 CLI 계정을 바꿔 적용). 앱은 돌고 있는 그대로다.
        ShopProtocolURLProtocol.markServerUpgraded(host: host)

        // ③ 간격 안에서는 깃발을 믿는다 — 헛왕복 절감이 사라지지 않았다는 것도 함께 잰다.
        hands.advance(by: SupabaseWorkService.shopProtocolRecheckInterval - 1)
        let during = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(during.characters?.map(\.id) == ["fox"], "간격 안인데 새 모양을 또 보냈다")
        let midBodies = Self.bodies(host: host, path: Self.shopStatePath)
        #expect(midBodies.count == 3, Comment(rawValue: "요청 \(midBodies)"))
        #expect(try Self.json(try #require(midBodies.last)).isEmpty, "간격 안의 요청이 옛 모양이 아니다")

        // ④ 간격을 넘기면 **다시 묻는다** → 새 서버가 robot 을 내려 준다(재시작 없이).
        hands.advance(by: 2)
        let after = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(after.characters?.map(\.id) == ["fox", "robot"],
                Comment(rawValue: "재확인 뒤에도 옛 목록이다: \(after.characters?.map(\.id) ?? [])"))
        let lastBody = try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath)))
        #expect(lastBody["p_protocol"] as? Int == 1, Comment(rawValue: "\(lastBody)"))

        // ⑤ 그리고 구매도 새 모양으로 간다(목록만 되살아나면 "최신 앱인데 업데이트하라"는 말을 듣는다).
        _ = try await service.buyCharacter(accessToken: "t", id: "robot", protocolVersion: ShopWire.robotProtocol)
        let buy = try Self.json(try #require(Self.lastBody(host: host, path: Self.buyCharacterPath)))
        #expect(buy["p_protocol"] as? Int == 1, Comment(rawValue: "\(buy)"))
    }

    /// ★ **되묻기까지 실패한 서버는 '함수 없음'의 증거가 아니다.** 함수가 없는 게 아니라 서버가 아픈 경우
    ///   (게이트웨이가 둘 다 404) 에도 깃발이 서면, 멀쩡해진 뒤에도 재확인 간격 내내 robot 이 안 보인다.
    ///   깃발을 세우는 자격은 "되묻기가 **성공했다**" 이다.
    @Test("되묻기까지 실패하면 깃발이 서지 않는다 — 다음 호출이 다시 새 모양으로 묻는다")
    func failedFallbackDoesNotSetTheFlag() async throws {
        let host = "shop-sick-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        }
        let first = Self.bodies(host: host, path: Self.shopStatePath)
        try #require(first.count == 2, Comment(rawValue: "되묻기를 안 했다: \(first)"))

        // 서버가 나았다. 깃발이 섰다면 여기서 옛 모양이 나가고 robot 을 못 본다.
        ShopProtocolURLProtocol.markServerUpgraded(host: host)
        let healed = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(healed.characters?.map(\.id) == ["fox", "robot"],
                Comment(rawValue: "아픈 서버 한 번에 앱이 강등됐다: \(healed.characters?.map(\.id) ?? [])"))
        let body = try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath)))
        #expect(body["p_protocol"] as? Int == 1, Comment(rawValue: "\(body)"))
    }

    /// ★ **본문이 PGRST202 가 아닌 404 는 '함수 없음'이 아니다.** 프록시·게이트웨이가 본문을 바꾼 404(HTML 404 로
    ///   실측)로 깃발이 서면, 함수가 멀쩡히 있는 새 서버에서 robot 이 사라진다. 되묻기는 해도(상점은 살려야 한다)
    ///   **기억하지는 않는다**.
    @Test("HTML 404 는 되묻기만 하고 기억하지 않는다")
    func proxyHTML404DoesNotPoisonTheFlag() async throws {
        let host = "shop-htmlold-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)

        _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        let first = Self.bodies(host: host, path: Self.shopStatePath)
        try #require(first.count == 2, Comment(rawValue: "되묻기를 안 했다: \(first)"))

        // 프록시가 지나갔다(= 서버는 원래 새 서명을 안다). 다음 호출이 새 모양이어야 robot 이 보인다.
        ShopProtocolURLProtocol.markServerUpgraded(host: host)
        let second = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(second.characters?.map(\.id) == ["fox", "robot"],
                Comment(rawValue: "HTML 404 한 번에 앱이 강등됐다: \(second.characters?.map(\.id) ?? [])"))
        let body = try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath)))
        #expect(body["p_protocol"] as? Int == 1, Comment(rawValue: "\(body)"))
    }

    /// ★ **기준선이 실제로 다르다**: 404 가 아닌 실패에는 폴백이 번지지 않는다. 안 가르면
    ///   "권한이 회수된 서버"에 옛 모양을 한 번 더 보내 같은 거절을 두 번 받고, 원인이 안 보인다.
    @Test("404 가 아닌 실패는 되묻지 않는다")
    func otherFailuresDoNotFallBack() async throws {
        let host = "shop-denied-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)
        await #expect(throws: (any Error).self) {
            _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        }
        let bodies = Self.bodies(host: host, path: Self.shopStatePath)
        try #require(bodies.count == 1, Comment(rawValue: "403 인데 되물었다: \(bodies)"))
        #expect(try Self.json(bodies[0])["p_protocol"] as? Int == 1)
    }

    /// 주석과 보고서가 **실제보다 강하게** 말하지 않도록 고정한다. "404 당 되묻기 한 번"은 **순차** 호출의 말이고,
    /// 목록·구매가 동시에 첫 호출이면 액터 재진입으로 각자 404 를 맞는다(헛왕복 한 번). 직렬화하지 않은 이유는
    /// `shopProtocolUnsupportedAt` 주석에 있다 — 그 자리를 잘못 풀면 상점이 영구 정지한다.
    ///
    /// 이 건수가 1·1 로 바뀌면 **첫 질문이 직렬화됐다는 뜻**이다. 그건 개선이지만, 그때는
    /// `shopProtocolUnsupportedAt` 의 ⚠️ 문장이 거짓이 되므로 **같이 지워야 한다**(이 빨강이 그 신호다).
    @Test("동시에 첫 호출이면 404 를 두 번 맞는다 — 그래도 그 뒤로는 둘 다 옛 모양이다")
    func concurrentFirstCallsEachPayOne404() async throws {
        let host = "shop-old-\(UUID().uuidString.lowercased())"
        let service = Self.service(host: host)

        async let list = service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        async let buy = service.buyCharacter(accessToken: "t", id: "fox", protocolVersion: ShopWire.robotProtocol)
        _ = try await (list, buy)

        let listBodies = Self.bodies(host: host, path: Self.shopStatePath)
        let buyBodies = Self.bodies(host: host, path: Self.buyCharacterPath)
        #expect(listBodies.count == 2, Comment(rawValue: "목록 \(listBodies)"))
        #expect(buyBodies.count == 2, Comment(rawValue: "구매 \(buyBodies)"))

        // 그 뒤로는 둘 다 처음부터 옛 모양이다(헛왕복은 딱 한 번이다).
        _ = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        _ = try await service.buyCharacter(accessToken: "t", id: "fox", protocolVersion: ShopWire.robotProtocol)
        #expect(try Self.json(try #require(Self.lastBody(host: host, path: Self.shopStatePath))).isEmpty)
        #expect(Set(try Self.json(try #require(Self.lastBody(host: host, path: Self.buyCharacterPath))).keys) == ["p_id"])
        #expect(Self.bodies(host: host, path: Self.shopStatePath).count == 3, "되묻기가 또 돌았다")
        #expect(Self.bodies(host: host, path: Self.buyCharacterPath).count == 3, "되묻기가 또 돌았다")
    }

    // MARK: - ⑤ "그림이 실렸다"의 신호 — manifest.json 한 장은 그림이 아니다

    /// ★ **매니페스트만 넣은 번들에서 `shopProtocolVersion == 1` 이 되는 것을 실측했다.** 그 빌드는 서버에
    ///   robot 카드를 달라고 말하고, 카드는 회색 `person.crop.circle` + 이름 "로봇" 으로 뜨며 **살 수 있다** —
    ///   C1 의 "돈만 내고 아무 일도 안 생긴다"가 한 칸 좁아진 채 돌아온다. 카탈로그는 `manifest.json` 한 장만
    ///   요구하므로 `catalog.allIDs` 는 "그림이 실렸다"의 증거가 아니다.
    ///
    ///   그래서 파생의 재료는 `CheckMascotAssets.drawableCharacterIDs`(초상 둘 + 아틀라스의 **파일 실재**)다.
    ///   여기서는 임시 폴더에 두 가지 번들을 실제로 만들어 **양쪽 분기를 다 돌린다**(모양이 아니라 결과).
    @Test("매니페스트만 든 캐릭터 폴더는 1 을 만들지 않는다 — 그림 파일이 다 있을 때만 1 이다")
    func manifestAloneIsNotArt() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v0343-art-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // ① 매니페스트만(그림 0장) — 카탈로그는 robot 을 알지만 그릴 수는 없다.
        let bare = root.appendingPathComponent("bare/robot", isDirectory: true)
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try Self.robotManifest.write(to: bare.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let bareCatalog = CharacterCatalog.load(charactersDirectory: root.appendingPathComponent("bare", isDirectory: true))
        // 기준선이 실제로 다르다: 카탈로그는 "안다"고 말한다(= 옛 재료라면 1 을 보냈다).
        #expect(bareCatalog.allIDs.contains("robot"), "카탈로그가 매니페스트를 안 읽었다 — 이 검사가 무의미해진다")
        let bareDrawable = CheckMascotAssets.drawableCharacterIDs(catalog: bareCatalog)
        #expect(bareDrawable.contains("robot") == false, Comment(rawValue: "그릴 수 있다고 했다: \(bareDrawable)"))
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: bareDrawable) == ShopWire.legacyProtocol,
                "그림 없이 1 을 보낸다 — 서버가 robot 카드를 내려 주고 회색 카드가 팔린다")

        // ② 그림 네 장이 다 있는 번들 — 여기서는 1 이어야 한다(안 그러면 그림을 넣어도 아무에게도 안 보인다).
        let full = root.appendingPathComponent("full/robot", isDirectory: true)
        try FileManager.default.createDirectory(at: full, withIntermediateDirectories: true)
        try Self.robotManifest.write(to: full.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        for file in ["atlas.png", "portrait-neutral.png", "portrait-negative.png"] {
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: full.appendingPathComponent(file))
        }
        let fullCatalog = CharacterCatalog.load(charactersDirectory: root.appendingPathComponent("full", isDirectory: true))
        let fullDrawable = CheckMascotAssets.drawableCharacterIDs(catalog: fullCatalog)
        #expect(fullDrawable.contains("robot"), Comment(rawValue: "그림이 다 있는데 못 그린다고 했다: \(fullDrawable)"))
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: fullDrawable) == ShopWire.robotProtocol)

        // ③ 한 장만 빼도 0 이다(초상 한쪽·아틀라스 각각). 세 파일이 전부 요구되는지 낱개로 잰다.
        for missing in ["atlas.png", "portrait-neutral.png", "portrait-negative.png"] {
            let partial = root.appendingPathComponent("no-\(missing)/robot", isDirectory: true)
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
            try Self.robotManifest.write(to: partial.appendingPathComponent("manifest.json"),
                                         atomically: true, encoding: .utf8)
            for file in ["atlas.png", "portrait-neutral.png", "portrait-negative.png"] where file != missing {
                try Data([0x89, 0x50, 0x4E, 0x47]).write(to: partial.appendingPathComponent(file))
            }
            let catalog = CharacterCatalog.load(charactersDirectory: root.appendingPathComponent("no-\(missing)",
                                                                                                isDirectory: true))
            let drawable = CheckMascotAssets.drawableCharacterIDs(catalog: catalog)
            #expect(drawable.contains("robot") == false,
                    Comment(rawValue: "\(missing) 가 없는데 그릴 수 있다고 했다: \(drawable)"))
        }

        // ④ 지금 실린 다섯 종은 전부 '그릴 수 있다'여야 한다 — 규칙이 너무 좁으면 멀쩡한 캐릭터가 사라진다.
        let bundled = CheckMascotAssets.drawableCharacterIDs()
        for id in ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"] {
            #expect(bundled.contains(id), Comment(rawValue: "\(id) 가 빠졌다: \(bundled)"))
        }
    }

    // MARK: - ③ needs_update — 화면이 사용자 말로 바꾼다

    /// 서버는 robot 을 0 으로 사려는 호출을 `needs_update` 로 거절하고 **루비를 깎지 않는다**.
    /// `default:` 의 "구매 실패" 로 떨어지면 사용자는 돈이 빠졌는지도, 자기가 할 일이 업데이트인지도 모른다.
    @MainActor
    @Test("needs_update 는 전용 문구를 남기고 루비·보유를 건드리지 않는다")
    func needsUpdateSpeaksItsOwnSentence() async throws {
        let store = Self.store(host: "shop-needsupdate-\(UUID().uuidString.lowercased())")
        store.applyShopState(ShopStateResponse(rubyBalance: 500, ultraBalance: 7, ultraPrice: 3,
                                               characters: [ShopCharacterRow(id: "robot", price: 100, owned: false)]))
        store.shopLoaded = true

        store.buyCharacter("robot")
        #expect(await Self.waitUntil { store.purchasingID == nil && store.shopNotice != nil }, "구매가 안 끝났다")

        #expect(store.shopNotice == WorkTimerStore.needsUpdateNotice,
                Comment(rawValue: "문구가 \(store.shopNotice ?? "nil") 다 — needs_update 가 '구매 실패' 로 뭉개졌다"))
        #expect(store.shopNotice != "구매 실패")
        #expect(store.rubyBalance == 500, "거절인데 잔량이 바뀌었다")
        #expect(store.ownedCharacterIDs.contains("robot") == false, "거절인데 보유로 기입됐다")

        // ★ 스토어 칸만 재면 '클라 게이트는 짝으로 있다' 를 다시 밟는다 — 하단 바가 그 문장을 **실제로 고르는지**
        //   까지 잰다. 잔량이 모자란 상황을 같이 주고도 안내가 이긴다(안내가 뒤로 밀리면 사용자는 영영 못 읽는다).
        #expect(ShopText.barDetail(notice: store.shopNotice, selection: .character("robot"),
                                   price: 100, balance: 0) == WorkTimerStore.needsUpdateNotice,
                "하단 바가 needs_update 문구 대신 다른 줄을 고른다")
    }

    /// 문구가 상점의 다른 문장들과 같은 말투인지(종결 `-요`) + 서로 다른 문장인지.
    @Test("문구는 상점 말투를 따르고 다른 어휘와 겹치지 않는다")
    func noticeMatchesShopVoice() {
        let notice = WorkTimerStore.needsUpdateNotice
        #expect(notice.hasSuffix("요"))
        #expect(notice.contains("업데이트"), "무엇을 하면 되는지 안 말한다")
        #expect(notice != WorkTimerStore.alreadyOwnedNotice && notice != WorkTimerStore.pickSomethingNotice)
        #expect(notice != "구매 실패")
    }

    // MARK: - 헬퍼

    static let shopStatePath = "/rest/v1/rpc/shop_state"
    static let buyCharacterPath = "/rest/v1/rpc/buy_character"

    /// 번들·카탈로그를 거치지 않는 기준선: **소스 트리에 robot 의 그림 네 장이 놓였는가.**
    /// (파생의 재료와 같은 식으로 기대값을 만들면 그 단언은 영원히 초록이다.)
    static var robotArtInSourceTree: Bool {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check/Characters/robot", isDirectory: true)
        return ["manifest.json", "atlas.png", "portrait-neutral.png", "portrait-negative.png"].allSatisfy {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    /// 임시 번들용 매니페스트(실제 5종과 같은 모양 — 아틀라스·초상을 **선언**한다).
    static let robotManifest = #"""
    {"id":"robot","displayName":"로봇","kind":"sprite",
     "atlas":{"file":"atlas.png","width":4,"height":4,
              "states":{"frontIdle":{"frames":[{"x":0,"y":0,"w":4,"h":4}],"durationsMs":[1000],"loop":true}}},
     "portrait":{"neutral":"portrait-neutral.png","negative":"portrait-negative.png"},
     "pixelArt":false}
    """#

    /// 시계 바늘. 깃발 만료는 **시간**이 조건이라 5분을 실제로 기다릴 수 없다.
    final class Hands: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(start: Date) { value = start }
        func advance(by seconds: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            value = value.addingTimeInterval(seconds)
        }
        var read: @Sendable () -> Date {
            { [self] in lock.lock(); defer { lock.unlock() }; return value }
        }
    }

    static func service(host: String, clock: (@Sendable () -> Date)? = nil) -> SupabaseWorkService {
        SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                            anonKey: "anon-test-key",
                            session: ShopProtocolURLProtocol.session(),
                            clock: clock ?? { Date() })
    }

    @MainActor
    static func store(host: String, function: String = #function) -> WorkTimerStore {
        let store = WorkTimerStore(service: service(host: host),
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("v0343-" + host, function: function))
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
        // 착용 캐릭터도 격리한다 — 전역을 건드리면 병렬 스위트가 빨개진다(V0317 스위트와 같은 근거).
        store.characterDefaults = CheckTestScratch.defaults("v0343-char-" + host, function: function)
        return store
    }

    static func bodies(host: String, path: String) -> [String] {
        ShopProtocolURLProtocol.records(forHost: host).filter { $0.path == path }.map(\.body)
    }

    static func lastBody(host: String, path: String) -> String? {
        bodies(host: host, path: path).last
    }

    /// 본문을 **JSON 으로 열어** 키·값을 잰다. `contains("p_id")` 류는 키 이름이 값 안에 들어 있어도 통과한다.
    static func json(_ text: String) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(any as? [String: Any], Comment(rawValue: "JSON 객체가 아니다: \(text)"))
    }

    /// 응답 반영이 Task 라 결과가 나타날 때까지 짧게 폴링한다(기존 스위트 관용구).
    /// `@MainActor` 다 — 조건이 읽는 것은 메인 액터 스토어이고, 안 묶으면 클로저가 격리를 건너며 빨개진다.
    @MainActor
    @discardableResult
    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// 상점 `p_protocol` 전용 스텁. 시나리오는 **호스트가 고르고**, 응답은 **요청 본문이 고른다** —
/// 전역 카운터로 "첫 요청/둘째 요청"을 가르면 병렬 스위트가 서로의 순번을 먹어 무음으로 뒤집힌다
/// (`TakePokesArgumentURLProtocol` 주석의 그 사고). 본문 분기는 그 상태가 아예 없다.
///
/// 예외가 하나 있다: `markServerUpgraded(host:)` 는 **테스트가 명시적으로** 서버를 올리는 문이다
/// (db push 가 실행 중에 끝나는 창·프록시가 지나간 창은 그 전이가 없으면 재현할 수 없다). 요청 수를 세지 않고
/// 호스트별로 한 번 켜지는 깃발이라 순번 공유 사고가 생기지 않는다.
final class ShopProtocolURLProtocol: URLProtocol {
    struct Record: Sendable { let path: String; let body: String }

    private nonisolated(unsafe) static var recordsByHost: [String: [Record]] = [:]
    private nonisolated(unsafe) static var upgradedHosts: Set<String> = []
    private static let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShopProtocolURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func records(forHost host: String) -> [Record] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recordsByHost[host, default: []]
    }

    /// 이 호스트의 서버가 **지금부터** 새 서명을 안다(db push 가 끝났다 · 프록시가 지나갔다 · 서버가 나았다).
    static func markServerUpgraded(host: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        upgradedHosts.insert(host)
    }

    private static func isUpgraded(_ host: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return upgradedHosts.contains(host)
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let body = Self.bodyText(from: request)
        Self.stateLock.lock()
        Self.recordsByHost[host, default: []].append(Record(path: path, body: body))
        Self.stateLock.unlock()

        let (statusCode, json) = Self.outcome(host: host, path: path, body: body)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func outcome(host: String, path: String, body: String) -> (Int, String) {
        // PostgREST 가 **인자 집합으로 함수를 못 찾았을 때**의 실제 문구. "schema cache" 를 포함하므로
        // 공용 매핑이 `.databaseSchemaMissing` 으로 분류한다 — 폴백이 잡는 신호가 바로 이것이다.
        let notFound = #"{"code":"PGRST202","message":"Could not find the function public.shop_state(p_protocol) in the schema cache","hint":"Perhaps you meant to call the function public.shop_state"}"#
        // 프록시·게이트웨이가 본문을 바꾼 404(실측). PGRST202 가 아니므로 `.invalidResponse(404)` 로 올라간다.
        let proxyNotFound = "<html><head><title>404 Not Found</title></head><body>nginx</body></html>"
        let newShape = body.contains("p_protocol")
        let upgraded = isUpgraded(host)

        if host.hasPrefix("shop-denied") {
            // 함수는 있는데 실행 권한이 없는 서버. 폴백이 여기까지 번지면 안 된다.
            return (403, #"{"code":"42501","message":"permission denied for function shop_state"}"#)
        }
        if host.hasPrefix("shop-sick"), !upgraded {
            // 함수가 없는 게 아니라 **서버가 아프다** — 옛 모양도 안 된다. 깃발이 서면 안 되는 자리다.
            return newShape ? (404, notFound) : (500, #"{"message":"upstream connect error"}"#)
        }
        if host.hasPrefix("shop-htmlold"), !upgraded, newShape {
            return (404, proxyNotFound)
        }
        if host.hasPrefix("shop-old") || (host.hasPrefix("shop-upgrade") && !upgraded), newShape {
            return (404, notFound)
        }
        switch path {
        case V0343RobotShopProtocolTests.shopStatePath:
            // 새 서버는 `p_protocol >= 1` 에만 robot 행을 내려 준다(서버 soft 게이트 `min_protocol = 1`).
            let rows = newShape
                ? #"[{"id":"fox","price":30,"owned":false},{"id":"robot","price":100,"owned":false}]"#
                : #"[{"id":"fox","price":30,"owned":false}]"#
            return (200, #"{"ruby_balance":100,"ultra_balance":7,"ultra_price":3,"ultra_buy_max":20,"characters":\#(rows)}"#)
        case V0343RobotShopProtocolTests.buyCharacterPath:
            if host.hasPrefix("shop-needsupdate") {
                return (200, #"{"status":"needs_update","character":"robot"}"#)
            }
            return (200, #"{"status":"ok","character":"fox","price":30,"ruby_balance":70}"#)
        default:
            return (200, "[]")
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
}
