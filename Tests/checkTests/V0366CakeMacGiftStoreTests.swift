import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.66 — 케이크 아잉이 생일 선물의 **맥 스토어 배선**(WorkTimerStoreCakeGift.swift). 서버는 호스트별 스텁(`GomokuStubProtocol`)이고
// 창은 훅(`CakeGiftWindowHooks`)을 갈아 끼워 센다 — 화면에 아무것도 안 뜬다. 재는 것은 **부르는 자리**의 결과다:
//  ① 박자: 앱 시작(저장 세션 활성화) · 로그인 마무리 · 상점 진입이 묻고, 15초 폴링(`localExpiryTick`)은 앞선 조회로부터 10분이 지났을 때만 묻는다.
//     능력 번호가 4 미만이면 묻지 않는다.
//  ② 축하 창: 열린 선물이 있으면 **실행당 한 번** 스스로(키를 잡지 않고) 띄운다 · 닫아도 선물은 남아 '다시 열기' 카드가 선다 · 카드의 [고르기]는
//     키를 잡고 띄운다 · 옛 서버(404)는 조용히 '선물 없음'.
//  ③ 수령: ok · replayed · already_claimed 는 받은 뒤 화면 + 보유 + 카드 거둠 + 상점 다시 읽기 · 실패 갈래는 문구 + 다시 시도 ·
//     본문 키 셋 · [지금 입기]는 기존 착용 경로(set_character).
//  ③-b 결론은 서버가(검토 수리): 결과를 모르는 수령 · 다른 기기 수령 뒤에도 창은 그리던 선물로 확인한다(replayed · already_claimed) · 보유를
//     다시 읽는다 · not_found 는 잠근다 · 수령 전에 떠난 낡은 조회는 카드를 되살리지 않는다 · 상점 보유와 선택지를 맞춘다 · 가입도 첫 조회를 한다.
//  ④ 로그아웃: 선물 상태가 다음 계정으로 새지 않는다(떠 있던 조회 응답도 버린다).

private let gcGiftID = "6f1c2a7e-1d1f-4b0e-9a55-0c5d7f3b2a10"
private let gcStrawberry = CharacterCatalog.cakeStrawberryAingID
private let gcChoco = CharacterCatalog.cakeChocoAingID
private let gcUser = "00000000-0000-0000-0000-0000000000d1"

/// 열린 선물 응답(설계서 §2-3 모양 그대로 — 선택지는 딸기 → 초코, created_at 은 마이크로초 + 오프셋).
private let gcPendingWithGift = #"{"status":"ok","gift":{"id":"\#(gcGiftID)","options":["aing_cake_strawberry","aing_cake_choco"],"note":null,"created_at":"2026-10-26T07:51:40.123456+00:00"}}"#
private let gcPendingNone = #"{"status":"ok"}"#
/// 함수가 없는 서버(PostgREST PGRST202 — 앱이 db push 보다 먼저 나간 창).
private let gcMissingFunction = #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.character_gift_pending(p_protocol) in the schema cache"}"#

/// 창 훅 대역 — 띄운 횟수 · 키를 잡았는가 · 닫은 횟수 · 떠 있는가.
@MainActor
private final class GiftWindowSpy {
    var shows: [Bool] = []
    var closes = 0
    var open = false

    var hooks: CakeGiftWindowHooks {
        CakeGiftWindowHooks(show: { [self] activating in shows.append(activating); open = true },
                            close: { [self] in closes += 1; open = false },
                            isOpen: { [self] in open })
    }
}

/// 서버 대역의 상태(스레드 간 공유 — 핸들러는 URLProtocol 스레드에서 돈다).
private final class GiftServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _pending: GomokuStubProtocol.Reply = .init(body: gcPendingWithGift)
    private var _claim: GomokuStubProtocol.Reply = .init(body: #"{"status":"ok","character_id":"aing_cake_strawberry","replayed":false}"#)
    private var _owned: Set<String> = []

    var pending: GomokuStubProtocol.Reply {
        get { lock.withLock { _pending } }
        set { lock.withLock { _pending = newValue } }
    }
    var claim: GomokuStubProtocol.Reply {
        get { lock.withLock { _claim } }
        set { lock.withLock { _claim = newValue } }
    }
    var owned: Set<String> {
        get { lock.withLock { _owned } }
        set { lock.withLock { _owned = newValue } }
    }

    func handle(_ rpc: String, _ body: String) -> GomokuStubProtocol.Reply? {
        switch rpc {
        case "character_gift_pending":
            return pending
        case "claim_character_gift":
            let reply = claim
            // 받았으면 그 케이크를 보유로 올린다(다음 shop_state 가 그것을 말한다).
            if reply.status == 200, let json = try? JSONSerialization.jsonObject(with: Data(reply.body.utf8)) as? [String: Any],
               let id = json["character_id"] as? String {
                owned.insert(id)
            }
            return reply
        case "shop_state":
            let owned = self.owned
            let rows = [gcStrawberry, gcChoco].map { id in
                #"{"id":"\#(id)","price":2000,"owned":\#(owned.contains(id)),"gacha_only":true,"gift_only":true}"#
            }
            return .init(body: #"{"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":["#
                         + #"{"id":"fox","price":60,"owned":false,"gacha_only":false,"gift_only":false},"# + rows.joined(separator: ",") + "]}")
        case "set_character":
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
            let id = json?["p_id"] as? String ?? ""
            return .init(body: #"{"status":"ok","character":"\#(id)"}"#)
        case "/auth/v1/token":
            return .init(body: #"{"access_token":"refreshed-token","refresh_token":"next-refresh","user":{"id":"\#(gcUser)"}}"#)
        default:
            return nil
        }
    }
}

@MainActor
private func gcInertTokenStore(_ label: String, function: String) -> TokenUsageStore {
    let scratch = CheckTestScratch.directory(label + "-cake-token", function: function)
    return TokenUsageStore(defaults: CheckTestScratch.defaults(label + "-cake-token", function: function),
                           homeDirectory: scratch.appendingPathComponent("home", isDirectory: true),
                           cacheURL: scratch.appendingPathComponent("cache.json", isDirectory: false))
}

/// 로그인 + 팀 확정 상태의 스토어(서버 = 스텁 호스트). `signedIn: false` 면 세션 없이 — 시작 · 로그인 경로가 세운다.
@MainActor
private func gcStore(host: String, server: GiftServer, spy: GiftWindowSpy, signedIn: Bool = true,
                     defaults: UserDefaults? = nil, function: String = #function) -> WorkTimerStore {
    GomokuStubProtocol.register(host: host) { rpc, body, _ in server.handle(rpc, body) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: defaults ?? CheckTestScratch.defaults("v0366-gift-" + host, function: function),
                               tokenUsage: gcInertTokenStore(host, function: function))
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: gcUser)
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
    }
    store.characterDefaults = CheckTestScratch.defaults("v0366-gift-char-" + host, function: function)
    store.characterSync.broadcast = CharacterSelectionBroadcast()
    store.cakeGiftWindowHooks = spy.hooks
    V0354CoreStub.retain(store)
    return store
}

private func gcHost(_ name: String) -> String {
    "v0366-gift-\(name)-\(UUID().uuidString.lowercased().prefix(8))"
}

@MainActor
private func gcStopLoops(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 요청이 **안 나갔음**을 말하기 전의 짧은 여유(나갔다면 이 사이에 스텁에 기록된다).
private func gcQuiet() async {
    try? await Task.sleep(for: .milliseconds(150))
}

@MainActor
@Suite("v0.3.66 생일 선물 — 맥 스토어 배선", .serialized)
struct V0366CakeMacGiftStoreTests {
    // MARK: ① 조회

    @Test("선물 없음: 묻되(p_protocol 4) 창도 카드도 서지 않는다")
    func noGiftShowsNothing() async throws {
        let host = gcHost("none")
        let server = GiftServer()
        server.pending = .init(body: gcPendingNone)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        #expect(store.shopProtocolVersion == ShopWire.cakeProtocol, "전제: 이 빌드는 케이크를 그린다(능력 번호 \(store.shopProtocolVersion))")
        await store.refreshCakeGift(reason: .launch)?.value
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").first, "묻지 않았다")
        #expect(Set(call.json.keys) == ["p_protocol"] && call.json["p_protocol"] as? Int == ShopWire.cakeProtocol, "본문 \(call.json)")
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard)
        #expect(spy.shows.isEmpty, "선물이 없는데 창을 띄웠다")
    }

    @Test("열린 선물: 실행당 한 번 스스로 띄운다(키를 잡지 않는다) · 닫아도 카드가 남는다 · 다시 물어도 또 안 띄운다 · [고르기]는 키를 잡는다")
    func giftShowsOncePerLaunchAndLeavesTheCard() async throws {
        let host = gcHost("once")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        #expect(!store.showsCakeGiftCard, "기준선: 묻기 전부터 카드가 섰다")
        await store.refreshCakeGift(reason: .launch)?.value
        let offer = try #require(store.cakeGiftOffer, "선물을 못 읽었다")
        #expect(offer.id == gcGiftID && offer.options == [gcStrawberry, gcChoco])
        #expect(spy.shows == [false], "스스로 띄우기가 \(spy.shows) — 한 번 · 키를 안 잡아야 한다")
        #expect(store.cakeGiftPresented == offer && store.cakeGiftChoice == nil, "선택지가 둘인데 미리 골라 뒀다")
        #expect(store.showsCakeGiftCard)

        // 고르지 않고 닫는다 → 선물은 남는다('다시 열기' 카드).
        store.closeCakeGiftWindow()
        #expect(spy.closes == 1 && !spy.open)
        #expect(store.cakeGiftOffer == offer && store.showsCakeGiftCard, "닫았더니 선물 카드가 사라졌다")

        // 같은 실행에서 다시 물어도(상점 진입 · 주기) 스스로는 또 안 띄운다.
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") == 2)
        #expect(spy.shows == [false], "같은 실행에서 두 번 띄웠다 — \(spy.shows)")

        // 카드의 [고르기] — 사용자가 누른 것이라 키를 잡는다.
        store.openCakeGiftWindow()
        #expect(spy.shows == [false, true], "다시 열기가 \(spy.shows)")

        // 새 실행(새 스토어)은 다시 한 번 띄운다.
        let spy2 = GiftWindowSpy()
        let next = gcStore(host: host, server: server, spy: spy2)
        await next.refreshCakeGift(reason: .launch)?.value
        #expect(spy2.shows == [false], "다음 실행에서 안 띄웠다")
    }

    @Test("선택지가 하나면(하나는 이미 가졌다) 미리 골라 둔다 · 선택지 밖 id 는 못 고른다")
    func singleOptionIsPreselected() async throws {
        let host = gcHost("single")
        let server = GiftServer()
        server.pending = .init(body: #"{"status":"ok","gift":{"id":"\#(gcGiftID)","options":["aing_cake_choco"],"note":"생일 축하해!","created_at":"2026-10-26T07:51:40+00:00"}}"#)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(store.cakeGiftChoice == gcChoco && store.canConfirmCakeGift)
        #expect(store.cakeGiftPresented?.note == "생일 축하해!")
        store.chooseCakeGift(gcStrawberry)
        #expect(store.cakeGiftChoice == gcChoco, "선택지에 없는 딸기를 골랐다")
    }

    @Test("옛 서버(404 PGRST202)는 조용히 '선물 없음' — 알던 선물도 내린다 · 5xx 는 아는 선물을 그대로 둔다")
    func oldServerIsQuietlyNoGift() async throws {
        let host = gcHost("404")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(store.cakeGiftOffer != nil, "기준선: 선물을 못 읽었다")

        server.pending = .init(status: 500, body: #"{"message":"boom"}"#)
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer != nil, "5xx 에 선물 카드가 사라졌다 — 결과를 모르는데 지웠다")

        server.pending = .init(status: 404, body: gcMissingFunction)
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "404 에 카드가 남았다")
        #expect(store.cakeGiftNotice == nil, "옛 서버에 문구를 띄웠다")

        // 처음부터 404 인 서버: 아무것도 안 뜬다.
        let quietHost = gcHost("404-fresh")
        let quiet = GiftServer()
        quiet.pending = .init(status: 404, body: gcMissingFunction)
        let quietSpy = GiftWindowSpy()
        let fresh = gcStore(host: quietHost, server: quiet, spy: quietSpy)
        await fresh.refreshCakeGift(reason: .launch)?.value
        #expect(fresh.cakeGiftOffer == nil && quietSpy.shows.isEmpty && fresh.cakeGiftNotice == nil)
    }

    @Test("능력 번호가 4 미만인 빌드(케이크 하나라도 못 그림)는 묻지 않는다")
    func protocolBelowFourDoesNotAsk() async throws {
        let host = gcHost("p3")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        store.drawableCharacterIDs = WorkTimerStore.bundledDrawableCharacterIDs.filter { $0 != gcChoco }
        #expect(store.shopProtocolVersion == ShopWire.rainbowProtocol, "전제: 초코를 빼면 3 이다")
        #expect(store.refreshCakeGift(reason: .launch) == nil)
        store.toggleShopPanel()
        await gcQuiet()
        #expect(GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") == 0, "케이크를 못 그리는 빌드가 선물을 물었다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "shop_state") >= 1, "기준선: 상점 진입이 아무것도 안 불렀다 — 시험이 헛돈다")
    }

    // MARK: ② 부르는 자리 · 박자

    @Test("부르는 자리: 앱 시작(저장 세션 활성화) · 로그인 마무리 · 상점 진입이 각각 묻는다")
    func entryPointsAsk() async throws {
        // 앱 시작.
        do {
            let host = gcHost("launch")
            let server = GiftServer()
            let spy = GiftWindowSpy()
            let defaults = CheckTestScratch.defaults("v0366-gift-launch")
            defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
            defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
            defaults.set(gcUser, forKey: WorkTimerStore.userIDKey)
            let store = gcStore(host: host, server: server, spy: spy, signedIn: false, defaults: defaults)
            defer { gcStopLoops(store) }
            #expect(store.shouldActivateOnLaunch, "전제: 저장 세션이 복원되지 않았다")
            await store.activateStoredSessionOnLaunch()?.value
            #expect(await V0354CoreStub.waitUntil { store.cakeGiftOffer != nil }, "앱 시작이 선물을 안 물었다")
            #expect(spy.shows == [false])
        }
        // 로그인 마무리.
        do {
            let host = gcHost("signin")
            let server = GiftServer()
            let spy = GiftWindowSpy()
            let store = gcStore(host: host, server: server, spy: spy, signedIn: false)
            defer { gcStopLoops(store) }
            await store.completeSignIn(SupabaseSession(accessToken: "signed-in", refreshToken: "r", userID: gcUser), email: "a@example.com")
            #expect(await V0354CoreStub.waitUntil { store.cakeGiftOffer != nil }, "로그인이 선물을 안 물었다")
            #expect(spy.shows == [false])
        }
        // 상점 진입(여는 순간만 — 닫을 때는 안 묻는다).
        do {
            let host = gcHost("shop")
            let server = GiftServer()
            server.pending = .init(body: gcPendingNone)
            let spy = GiftWindowSpy()
            let store = gcStore(host: host, server: server, spy: spy)
            store.toggleShopPanel()
            #expect(store.isShopPanelVisible)
            #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") == 1 },
                    "상점 진입이 선물을 안 물었다")
            #expect(await V0354CoreStub.waitUntil { !store.cakeGiftChecking })
            store.toggleShopPanel()
            #expect(!store.isShopPanelVisible)
            await gcQuiet()
            #expect(GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") == 1, "상점을 닫을 때도 물었다")
        }
    }

    @Test("주기(15초 폴링 localExpiryTick): 한 번도 안 물었으면 안 묻는다 · 앞선 조회로부터 10분이 지나야 묻는다 · 상점 진입도 시계를 다시 맞춘다")
    func periodicCheckIsThrottledToTenMinutes() async throws {
        let host = gcHost("tick")
        let server = GiftServer()
        server.pending = .init(body: gcPendingNone)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        let t0 = Date(timeIntervalSince1970: 1_793_000_000)
        var now = t0
        store.clock = { now }
        func pendingCount() -> Int { GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") }
        func tick(at seconds: TimeInterval) async {
            now = t0.addingTimeInterval(seconds)
            await store.localExpiryTick()
            _ = await V0354CoreStub.waitUntil { !store.cakeGiftChecking }
            await gcQuiet()
        }

        // 첫 조회는 시작 · 로그인의 몫이다 — 폴링은 0건.
        await tick(at: 0)
        #expect(pendingCount() == 0, "한 번도 안 물었는데 폴링이 물었다")

        await store.refreshCakeGift(reason: .launch)?.value
        #expect(pendingCount() == 1)
        await tick(at: 599)
        #expect(pendingCount() == 1, "10분 안에 다시 물었다")
        await tick(at: 600)
        #expect(pendingCount() == 2, "10분이 지났는데 안 물었다")
        await tick(at: 615)
        #expect(pendingCount() == 2, "15초 뒤에 또 물었다")

        // 상점 진입(10분 문 없음)이 시계를 다시 맞춘다 — 그 뒤 10분이 기준이다.
        now = t0.addingTimeInterval(900)
        store.toggleShopPanel()
        #expect(await V0354CoreStub.waitUntil { pendingCount() == 3 }, "상점 진입이 안 물었다")
        _ = await V0354CoreStub.waitUntil { !store.cakeGiftChecking }
        await tick(at: 1_200)
        #expect(pendingCount() == 3, "상점 진입 뒤 5분인데 폴링이 물었다")
        await tick(at: 1_500)
        #expect(pendingCount() == 4, "상점 진입 뒤 10분인데 안 물었다")

        // 순수 문.
        #expect(!WorkTimerStore.cakeGiftCheckIsDue(last: nil, now: t0))
        #expect(!WorkTimerStore.cakeGiftCheckIsDue(last: t0, now: t0.addingTimeInterval(599.9)))
        #expect(WorkTimerStore.cakeGiftCheckIsDue(last: t0, now: t0.addingTimeInterval(600)))
    }

    // MARK: ③ 수령

    @Test("받기 ok: 본문 키 셋 · 받은 뒤 화면 · 보유 · 카드 거둠 · 상점 다시 읽기 · [지금 입기]는 기존 착용 경로(set_character)")
    func claimOkWearsThroughTheExistingPath() async throws {
        let host = gcHost("ok")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(!store.canConfirmCakeGift, "고르기 전에 확인 단추가 눌린다")
        #expect(store.claimCakeGift() == nil, "고르기 전에 받으러 나갔다")
        store.chooseCakeGift(gcStrawberry)
        #expect(store.canConfirmCakeGift)
        let shopBefore = GomokuStubProtocol.count(host: host, rpc: "shop_state")
        await store.claimCakeGift()?.value

        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").last, "수령이 안 나갔다")
        #expect(Set(call.json.keys) == ["p_gift", "p_character", "p_protocol"], "본문 \(call.json)")
        #expect(call.json["p_gift"] as? String == gcGiftID && call.json["p_character"] as? String == gcStrawberry
                && call.json["p_protocol"] as? Int == ShopWire.cakeProtocol, "본문 \(call.json)")
        #expect(store.cakeGiftReceivedID == gcStrawberry, "받은 뒤 화면으로 안 넘어갔다")
        #expect(store.cakeGiftNotice == nil)
        #expect(store.ownedCharacterIDs.contains(gcStrawberry))
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "받았는데 다시 열기 카드가 남았다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") > shopBefore }, "받은 뒤 상점을 다시 안 읽었다")
        #expect(await V0354CoreStub.waitUntil { store.shopLoaded })
        #expect(store.shopCharacters.first { $0.id == gcStrawberry }?.owned == true, "다시 읽은 상점이 보유를 모른다")
        #expect(store.isCharacterUnlocked(gcStrawberry))
        #expect(store.characterPickerIDs.contains(gcStrawberry), "받은 케이크가 고르기에 안 선다")
        #expect(!store.characterPickerIDs.contains(gcChoco), "안 가진 초코가 고르기에 섰다(조정자 결정: 가진 사람에게만)")
        #expect(GomokuStubProtocol.count(host: host, rpc: "set_character") == 0, "수령이 착용까지 바꿨다(설계서 §2-4 — 착용은 따로)")

        // [지금 입기]
        let revision = store.characterSync.broadcast.revision
        store.wearCakeGift()
        let selected = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).selectedID
        #expect(selected == gcStrawberry, "로컬 착용이 \(selected)")
        #expect(store.characterSync.broadcast.revision == revision + 1 && store.characterSync.broadcast.selectedID == gcStrawberry,
                "착용 방송이 안 울렸다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "set_character") == 1 }, "서버 착용(set_character)이 안 나갔다")
        #expect(GomokuStubProtocol.calls(host: host, rpc: "set_character").last?.json["p_id"] as? String == gcStrawberry)
        #expect(spy.closes >= 1 && store.cakeGiftReceivedID == nil, "[지금 입기] 뒤 창이 안 닫혔다")
    }

    @Test("받기 replayed(같은 선택 재응답) · already_claimed(다른 기기에서 다른 케이크) — 둘 다 받은 뒤 화면 · 카드 거둠",
          arguments: ["replayed", "already_claimed"])
    func claimReplayAndAlreadyClaimed(kind: String) async throws {
        let host = gcHost(kind)
        let server = GiftServer()
        server.claim = kind == "replayed"
            ? .init(body: #"{"status":"ok","character_id":"aing_cake_strawberry","replayed":true}"#)
            : .init(body: #"{"status":"already_claimed","character_id":"aing_cake_choco"}"#)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.chooseCakeGift(gcStrawberry)
        await store.claimCakeGift()?.value
        let expected = kind == "replayed" ? gcStrawberry : gcChoco
        #expect(store.cakeGiftReceivedID == expected, "\(kind): 받은 뒤 화면이 \(store.cakeGiftReceivedID ?? "nil")")
        #expect(store.ownedCharacterIDs.contains(expected))
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "\(kind): 카드가 남았다")
        #expect(store.cakeGiftNotice == nil)
    }

    @Test("받기 실패 갈래: 문구를 보이고 선물은 그대로(다시 시도) — 단 not_found 는 선물을 거둔다",
          arguments: ["needs_update", "invalid_choice", "not_found", "404", "500"])
    func claimFailuresSpeakAndAllowRetry(kind: String) async throws {
        let host = gcHost("fail-\(kind)")
        let server = GiftServer()
        switch kind {
        case "needs_update": server.claim = .init(body: #"{"status":"needs_update","min_protocol":4}"#)
        case "invalid_choice": server.claim = .init(body: #"{"status":"invalid_choice"}"#)
        case "not_found": server.claim = .init(body: #"{"status":"not_found"}"#)
        case "404": server.claim = .init(status: 404, body: #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.claim_character_gift(p_character, p_gift, p_protocol) in the schema cache"}"#)
        default: server.claim = .init(status: 500, body: #"{"message":"boom"}"#)
        }
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.chooseCakeGift(gcChoco)
        await store.claimCakeGift()?.value
        let expectedNotice: String = switch kind {
        case "needs_update": CakeGiftText.needsUpdate
        case "invalid_choice": CakeGiftText.invalidChoice
        case "not_found": CakeGiftText.notFound
        case "404": CakeGiftText.unavailable
        default: CakeGiftText.claimFailed
        }
        #expect(store.cakeGiftNotice == expectedNotice, "\(kind): 문구 \(store.cakeGiftNotice ?? "nil")")
        #expect(store.cakeGiftReceivedID == nil && !store.ownedCharacterIDs.contains(gcChoco), "\(kind): 실패했는데 받았다고 한다")
        if kind == "not_found" {
            #expect(store.cakeGiftOffer == nil, "not_found 인데 다시 열기 카드가 남았다")
            #expect(!store.canConfirmCakeGift, "끝난 선물에 확인 단추가 그대로 눌린다 — 같은 실패만 되풀이한다")
        } else {
            #expect(store.cakeGiftOffer != nil && store.showsCakeGiftCard, "\(kind): 결과를 모르거나 안 받았는데 카드가 사라졌다")
            #expect(store.canConfirmCakeGift, "\(kind): 다시 시도할 수 없다")
        }
        // 다시 시도(서버가 이번엔 받아 준다) — 같은 선택으로 받는다.
        if kind != "not_found" {
            server.claim = .init(body: #"{"status":"ok","character_id":"aing_cake_choco","replayed":false}"#)
            await store.claimCakeGift()?.value
            #expect(store.cakeGiftReceivedID == gcChoco && store.cakeGiftNotice == nil, "\(kind): 다시 시도가 안 받았다")
            #expect(GomokuStubProtocol.count(host: host, rpc: "claim_character_gift") == 2)
        }
    }

    // MARK: ③-b 결론은 서버가 — 창은 자기가 그리는 선물로 확인한다 (검토 수리)

    @Test("결과를 모르는 수령(502 — 서버엔 커밋됐다) 뒤 조회가 '선물 없음': 창의 확인 단추는 잠기지 않고 · 보유를 다시 읽고 · 다시 누르면 replayed 로 받은 뒤 화면")
    func lostClaimResponseStillConfirmsThroughTheServer() async throws {
        let host = gcHost("lost-502")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(spy.open, "기준선: 축하 창이 안 떴다")
        store.chooseCakeGift(gcChoco)
        server.claim = .init(status: 502, body: #"{"message":"bad gateway"}"#)
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftNotice == CakeGiftText.claimFailed && store.canConfirmCakeGift, "기준선: 502 뒤 다시 시도 화면이 아니다")

        // 서버는 수령을 커밋했다 — 응답만 잃었다. 다음 조회는 '없음', 상점은 초코를 가졌다고 말한다.
        server.owned = [gcChoco]
        server.pending = .init(body: gcPendingNone)
        server.claim = .init(body: #"{"status":"ok","character_id":"aing_cake_choco","replayed":true}"#)
        let shopBefore = GomokuStubProtocol.count(host: host, rpc: "shop_state")
        await store.refreshCakeGift(reason: .periodic)?.value
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "선물이 없다는데 카드가 남았다")
        #expect(store.canConfirmCakeGift, "창이 '다시 시도해 주세요'를 말하는데 확인 단추가 잠겼다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") > shopBefore },
                "그리던 선물이 조회에서 사라졌는데 보유를 다시 안 읽었다")
        #expect(await V0354CoreStub.waitUntil { store.ownedCharacterIDs.contains(gcChoco) }, "다시 읽은 보유가 초코를 모른다")

        // 다시 누른다 — 서버의 결론(replayed)이 받은 뒤 화면으로 데려간다.
        await store.claimCakeGift()?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "claim_character_gift") == 2, "다시 누른 수령이 안 나갔다")
        #expect(store.cakeGiftReceivedID == gcChoco && store.cakeGiftNotice == nil, "받은 뒤 화면이 아니다 — \(store.cakeGiftReceivedID ?? "nil") · \(store.cakeGiftNotice ?? "nil")")
        #expect(!store.canConfirmCakeGift)
    }

    @Test("창이 떠 있는 동안 다른 기기에서 먼저 받음: 맥 단추는 회색이 아니고 · 누르면 already_claimed 가 받은 뒤 화면(받은 케이크)으로")
    func claimedElsewhereWhileTheWindowIsOpen() async throws {
        let host = gcHost("elsewhere")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.chooseCakeGift(gcStrawberry)
        #expect(spy.open && store.canConfirmCakeGift)

        // 폰이 초코로 받았다.
        server.owned = [gcChoco]
        server.pending = .init(body: gcPendingNone)
        server.claim = .init(body: #"{"status":"already_claimed","character_id":"aing_cake_choco"}"#)
        await store.refreshCakeGift(reason: .periodic)?.value
        #expect(!store.showsCakeGiftCard)
        #expect(store.canConfirmCakeGift, "다른 기기에서 받은 뒤 맥 확인 단추가 말없이 잠겼다")
        #expect(await V0354CoreStub.waitUntil { store.ownedCharacterIDs.contains(gcChoco) }, "보유를 다시 안 읽었다")

        await store.claimCakeGift()?.value
        let sent = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").last)
        #expect(sent.json["p_gift"] as? String == gcGiftID && sent.json["p_character"] as? String == gcStrawberry, "그리던 선물로 확인하지 않았다 — \(sent.json)")
        #expect(store.cakeGiftReceivedID == gcChoco, "받은 뒤 화면이 받은 케이크(초코)가 아니다 — \(store.cakeGiftReceivedID ?? "nil")")
        #expect(store.cakeGiftNotice == nil)
    }

    @Test("not_found 로 끝난 선물에는 확인 단추가 잠긴다(같은 결론만 되풀이) — 조회가 같은 선물을 다시 말해도 카드가 안 선다")
    func notFoundSettlesTheGift() async throws {
        let host = gcHost("settled-404")
        let server = GiftServer()
        server.claim = .init(body: #"{"status":"not_found"}"#)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.chooseCakeGift(gcStrawberry)
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftNotice == CakeGiftText.notFound && !store.canConfirmCakeGift)
        #expect(store.claimCakeGift() == nil, "끝난 선물에 수령이 또 나간다")
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "결론 난 선물을 말하는 조회가 카드를 되살렸다")
    }

    @Test("수령 전에 떠난 조회가 수령 뒤에 도착해도 '다시 열기' 카드가 되살아나지 않는다 — 다른(새) 선물은 그대로 선다")
    func staleLookupDoesNotReviveTheCard() async throws {
        let host = gcHost("stale")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(store.cakeGiftOffer?.id == gcGiftID)

        // 둘째 조회는 받기 **전**의 서버 값(열린 선물)을 늦게 준다.
        server.pending = .init(body: gcPendingWithGift, delay: 0.6)
        let stale = store.refreshCakeGift(reason: .shop)
        #expect(stale != nil, "기준선: 둘째 조회가 안 떠났다")
        store.chooseCakeGift(gcStrawberry)
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == gcStrawberry && !store.showsCakeGiftCard, "기준선: 받지 못했다")
        await stale?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") == 2, "기준선: 낡은 조회가 도착하지 않았다")
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "받은 뒤 도착한 낡은 조회가 '다시 열기' 카드를 되살렸다")
        #expect(store.cakeGiftReceivedID == gcStrawberry, "낡은 조회가 받은 뒤 화면을 흔들었다")

        // 정말 새 선물(다른 id)은 선다 — 결론 난 id 만 버린다.
        let nextID = "7a2b3c4d-0000-4000-8000-00000000abcd"
        server.pending = .init(body: #"{"status":"ok","gift":{"id":"\#(nextID)","options":["aing_cake_choco"],"note":null,"created_at":"2027-10-26T07:51:40+00:00"}}"#)
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer?.id == nextID && store.showsCakeGiftCard, "새 선물까지 버렸다")
    }

    // MARK: ③-c 다른 기기에서 받은 선물 — 보유와 맞추기

    @Test("상점 상태를 읽으면 열린 선물의 선택지를 보유와 맞춘다 — 하나 남으면 그것만(미리 골라 둠), 남는 게 없으면 선물 · 카드를 거둔다")
    func ownershipReconcilesTheOpenGift() async throws {
        let host = gcHost("reconcile")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.closeCakeGiftWindow()
        #expect(store.showsCakeGiftCard && store.cakeGiftOffer?.options == [gcStrawberry, gcChoco])

        // 다른 기기에서 딸기를 얻었다(이 선물과 무관하게라도 — 보유는 줄지 않는다). 상점만 다시 읽는다.
        server.owned = [gcStrawberry]
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { store.ownedCharacterIDs.contains(gcStrawberry) })
        #expect(store.cakeGiftOffer?.options == [gcChoco], "가진 딸기가 선택지에 남았다 — \(store.cakeGiftOffer?.options ?? [])")
        #expect(store.showsCakeGiftCard, "고를 것이 남았는데 카드가 내려갔다")
        store.openCakeGiftWindow()
        #expect(store.cakeGiftPresented?.options == [gcChoco] && store.cakeGiftChoice == gcChoco, "하나 남은 선택지를 미리 골라 두지 않았다")
        store.closeCakeGiftWindow()

        // 초코도 가졌다(다른 기기에서 받았다) — 고를 것이 없다.
        server.owned = [gcStrawberry, gcChoco]
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { store.ownedCharacterIDs.contains(gcChoco) })
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "다 가졌는데 선물 · 카드가 남았다")

        // 그 뒤 조회가(서버가 아직 모르고) 같은 선물을 말해도 보유로 걸러 안 선다.
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "다 가진 선물을 조회가 되살렸다")
    }

    // MARK: ③-d 가입 마무리

    @Test("가입 마무리도 선물을 묻는다(로그인과 같은 첫 조회) — 그래서 그 실행에서도 10분 주기가 돈다")
    func signUpAsksAndArmsThePeriodicCheck() async throws {
        let host = gcHost("signup")
        let server = GiftServer()
        server.pending = .init(body: gcPendingNone)
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy, signedIn: false)
        defer { gcStopLoops(store) }
        let t0 = Date(timeIntervalSince1970: 1_793_000_000)
        var now = t0
        store.clock = { now }
        func pendingCount() -> Int { GomokuStubProtocol.count(host: host, rpc: "character_gift_pending") }

        await store.completeSignUp(SupabaseSession(accessToken: "signed-up", refreshToken: "r", userID: gcUser),
                                   email: "new@example.com", displayName: "새사람", center: nil)
        #expect(store.isSignedIn, "전제: 가입이 세션을 세우지 않았다")
        #expect(await V0354CoreStub.waitUntil { pendingCount() == 1 }, "가입 마무리가 선물을 안 물었다")
        _ = await V0354CoreStub.waitUntil { !store.cakeGiftChecking }
        #expect(store.cakeGiftLastCheckAt == t0)

        now = t0.addingTimeInterval(599)
        await store.localExpiryTick()
        await gcQuiet()
        #expect(pendingCount() == 1, "10분 안에 다시 물었다")
        now = t0.addingTimeInterval(600)
        await store.localExpiryTick()
        #expect(await V0354CoreStub.waitUntil { pendingCount() == 2 }, "가입으로 세션을 얻은 실행에서 10분 주기가 안 돈다")
    }

    // MARK: ④ 로그아웃

    @Test("로그아웃: 창 · 선물 · 선택 · 받은 뒤 화면 · 문구를 비운다 — 떠 있던 조회 응답도 다음 계정에 안 붙는다")
    func signOutClearsTheGift() async throws {
        let host = gcHost("signout")
        let server = GiftServer()
        let spy = GiftWindowSpy()
        let store = gcStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        store.chooseCakeGift(gcStrawberry)
        #expect(store.showsCakeGiftCard && spy.open, "기준선: 선물 창이 안 떴다")
        store.signOut(notifyServer: false)
        #expect(store.cakeGiftOffer == nil && store.cakeGiftPresented == nil && store.cakeGiftChoice == nil
                && store.cakeGiftReceivedID == nil && store.cakeGiftNotice == nil && !store.showsCakeGiftCard, "로그아웃이 선물을 안 비웠다")
        #expect(!spy.open, "로그아웃했는데 축하 창이 떠 있다")
        #expect(store.cakeGiftLastCheckAt == nil)

        // 떠 있던 조회: 응답이 로그아웃 뒤에 와도 버린다.
        let lateHost = gcHost("signout-late")
        let late = GiftServer()
        late.pending = .init(body: gcPendingWithGift, delay: 0.3)
        let lateSpy = GiftWindowSpy()
        let lateStore = gcStore(host: lateHost, server: late, spy: lateSpy)
        let inFlight = lateStore.refreshCakeGift(reason: .launch)
        #expect(inFlight != nil)
        lateStore.signOut(notifyServer: false)
        await inFlight?.value
        #expect(lateStore.cakeGiftOffer == nil && lateSpy.shows.isEmpty, "로그아웃 전에 떠난 조회가 선물을 세웠다")

        // 다음 계정(선물 없음)이 로그인하면 카드가 없다.
        late.pending = .init(body: gcPendingNone)
        lateStore.session = SupabaseSession(accessToken: "next", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000d2")
        await lateStore.refreshCakeGift(reason: .signIn)?.value
        #expect(lateStore.cakeGiftOffer == nil && !lateStore.showsCakeGiftCard)
    }
}
