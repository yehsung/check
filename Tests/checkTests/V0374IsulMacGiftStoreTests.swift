import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.74 — 이슬 아잉이 '술 한잔' 선물의 **맥 스토어 배선**(WorkTimerStoreCakeGift.swift — 종류를 아는 박자). 창은 훅을 갈아 끼워 센다
// (화면에 아무것도 안 뜬다). 서버는 호스트별 스텁인데, 응답을 고정하지 않고 **서버 갈래가 하네스로 확인한 규칙**을 그대로 흉내 낸다
// (`IsulGiftServer` — pending: p<4 없음 · p=4 생일만(kind 키 없음) · p≥5 먼저 지급된 것 하나 + kind · claim 의 needs_update 문턱 ·
// 선택지 · replayed · already_claimed · not_found). 재는 것:
//  ① 술 선물: 실행당 한 번 스스로(키 안 잡음) · 고르기 없이 미리 골라 둠 · [짠 받기] 본문 키 셋(p_protocol 5) · 받은 뒤 보유 · 카드 거둠 ·
//     상점 다시 읽기 · [지금 입기]는 기존 착용 경로.
//  ② 받기 결과: ok · replayed · needs_update · invalid_choice · not_found 의 화면 상태와 문구(종류 문구 묶음).
//  ③ 차례: 생일과 술이 둘 다 열린 사람은 하나씩 — 받고 창을 닫으면 다음 선물을 묻고 한 번 스스로 띄운다 · 받지 않고 닫으면 묻지 않는다 ·
//     조회가 떠 있는 동안 결론이 나면 그 조회 뒤에 한 번 더 묻는다.
//  ④ 번호 4(이슬을 못 그리는 빌드): 술 선물이 안 뜬다(서버가 안 싣고, 섞여 와도 안 띄운다) · 생일 흐름의 요청 수가 0.3.73 그대로('다음 선물' 없음).
//  ⑤ 상점: 잠긴 칸 문구가 종류마다 · 잠긴 칸 정책 상수 두 값(모두에게 · 가진 사람만).

private let isIsul = CharacterCatalog.isulAingID
private let isStrawberry = CharacterCatalog.cakeStrawberryAingID
private let isChoco = CharacterCatalog.cakeChocoAingID
private let isUser = "00000000-0000-0000-0000-0000000000f1"
private let isBirthdayID = "11111111-1d1f-4b0e-9a55-0c5d7f3b2a10"
private let isDrinkID = "aa4eef81-0000-4000-8000-0000000000d1"

/// 창 훅 대역 — 띄운 횟수(키를 잡았는가) · 닫은 횟수 · 떠 있는가 · 팝오버로 돌아간 횟수.
@MainActor
private final class IsulWindowSpy {
    var shows: [Bool] = []
    var closes = 0
    var open = false
    var returns = 0

    var hooks: CakeGiftWindowHooks {
        CakeGiftWindowHooks(show: { [self] activating in shows.append(activating); open = true },
                            close: { [self] in closes += 1; open = false },
                            isOpen: { [self] in open },
                            returnToPopover: { [self] in returns += 1 })
    }
}

/// 서버 대역 — 서버 갈래가 하네스로 확인한 규칙(작업 지시 '서버 전선')을 그대로 흉내 낸다. 핸들러는 URLProtocol 스레드에서 돈다.
private final class IsulGiftServer: @unchecked Sendable {
    struct Gift {
        let id: String
        let kind: String
        let options: [String]
        let note: String?
        let createdAt: String
        var claimedWith: String?
    }

    private let lock = NSLock()
    private var _gifts: [Gift] = []
    private var _owned: Set<String> = []
    private var _claimOverride: GomokuStubProtocol.Reply?
    private var _pendingOverride: GomokuStubProtocol.Reply?
    private var _pendingDelay: TimeInterval = 0

    var owned: Set<String> {
        get { lock.withLock { _owned } }
        set { lock.withLock { _owned = newValue } }
    }
    /// 받기 응답을 이 값으로 고정한다(서버 상태는 안 움직인다) — 결과 갈래 하나씩 잴 때.
    var claimOverride: GomokuStubProtocol.Reply? {
        get { lock.withLock { _claimOverride } }
        set { lock.withLock { _claimOverride = newValue } }
    }
    /// 조회 응답을 이 값으로 고정한다 — 서버가 규칙을 어긴 모양(번호 4 에 술 선물)을 흉내 낼 때.
    var pendingOverride: GomokuStubProtocol.Reply? {
        get { lock.withLock { _pendingOverride } }
        set { lock.withLock { _pendingOverride = newValue } }
    }
    /// 조회 응답을 늦춘다(조회가 떠 있는 동안 결론이 나는 경합).
    var pendingDelay: TimeInterval {
        get { lock.withLock { _pendingDelay } }
        set { lock.withLock { _pendingDelay = newValue } }
    }

    func grant(id: String, kind: String, options: [String], note: String? = nil, createdAt: String) {
        lock.withLock { _gifts.append(Gift(id: id, kind: kind, options: options, note: note, createdAt: createdAt)) }
    }

    func handle(_ rpc: String, _ body: String) -> GomokuStubProtocol.Reply? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        switch rpc {
        case "character_gift_pending":
            if let fixed = pendingOverride { return fixed }
            return .init(body: pending(protocolVersion: json["p_protocol"] as? Int ?? 0), delay: pendingDelay)
        case "claim_character_gift":
            if let fixed = claimOverride { return fixed }
            return .init(body: claim(gift: json["p_gift"] as? String, character: json["p_character"] as? String,
                                     protocolVersion: json["p_protocol"] as? Int ?? 0))
        case "shop_state":
            let owned = self.owned
            var rows = [#"{"id":"fox","price":60,"owned":\#(owned.contains("fox")),"gacha_only":false,"gift_only":false}"#]
            rows += [isChoco, isStrawberry].map { #"{"id":"\#($0)","price":2000,"owned":\#(owned.contains($0)),"gacha_only":true,"gift_only":true}"# }
            rows.append(#"{"id":"\#(isIsul)","price":2002,"owned":\#(owned.contains(isIsul)),"gacha_only":true,"gift_only":true}"#)
            return .init(body: #"{"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":["#
                         + rows.joined(separator: ",") + "]}")
        case "set_character":
            let id = json["p_id"] as? String ?? ""
            return .init(body: #"{"status":"ok","character":"\#(id)"}"#)
        default:
            return nil
        }
    }

    /// `character_gift_pending(p_protocol)` — p<4 없음 · p=4 생일만(kind 키 없음) · p≥5 먼저 지급된 것 하나 + kind. 안 가진 선택지가 없는 선물은 건너뛴다.
    private func pending(protocolVersion p: Int) -> String {
        lock.withLock {
            guard p >= 4 else { return #"{"status":"ok"}"# }
            let open = _gifts.filter { gift in
                gift.claimedWith == nil && (p >= 5 || gift.kind == "birthday") && gift.options.contains { !_owned.contains($0) }
            }
            guard let gift = open.first else { return #"{"status":"ok"}"# }
            let options = gift.options.filter { !_owned.contains($0) }.map { "\"\($0)\"" }.joined(separator: ",")
            let note = gift.note.map { "\"\($0)\"" } ?? "null"
            let kind = p >= 5 ? #","kind":"\#(gift.kind)""# : ""
            return #"{"status":"ok","gift":{"id":"\#(gift.id)"\#(kind),"options":[\#(options)],"note":\#(note),"created_at":"\#(gift.createdAt)"}}"#
        }
    }

    /// `claim_character_gift(p_gift, p_character, p_protocol)` — 서버 전선 표 그대로.
    private func claim(gift giftID: String?, character: String?, protocolVersion p: Int) -> String {
        lock.withLock {
            guard let index = _gifts.firstIndex(where: { $0.id == giftID }) else { return #"{"status":"not_found"}"# }
            let gift = _gifts[index]
            if p < 4 { return #"{"status":"needs_update","min_protocol":4}"# }
            if gift.kind == "drink", p < 5 { return #"{"status":"needs_update","min_protocol":5}"# }
            if let claimed = gift.claimedWith {
                return claimed == character
                    ? #"{"status":"ok","character_id":"\#(claimed)","replayed":true}"#
                    : #"{"status":"already_claimed","character_id":"\#(claimed)"}"#
            }
            guard let character, gift.options.contains(character), !_owned.contains(character) else {
                return #"{"status":"invalid_choice"}"#
            }
            _gifts[index].claimedWith = character
            _owned.insert(character)
            return #"{"status":"ok","character_id":"\#(character)","replayed":false}"#
        }
    }
}

@MainActor
private func isTokenStore(_ label: String, function: String) -> TokenUsageStore {
    let scratch = CheckTestScratch.directory(label + "-isul-token", function: function)
    return TokenUsageStore(defaults: CheckTestScratch.defaults(label + "-isul-token", function: function),
                           homeDirectory: scratch.appendingPathComponent("home", isDirectory: true),
                           cacheURL: scratch.appendingPathComponent("cache.json", isDirectory: false))
}

/// 그릴 수 있는 캐릭터 — 번호 5(이슬까지) · 4(이슬 뺌). 이 워크트리의 번들은 이슬 3D 마감 전이라 번호를 **주입**한다.
private func isDrawable(_ protocolVersion: Int) -> [String] {
    // v0.3.77: 번들이 빼빼로까지 그리면(6) 번호 5 주입이 6 으로 새지 않게 빼빼로도 뺀다.
    let base = WorkTimerStore.bundledDrawableCharacterIDs.filter { !ShopWire.isulCharacterIDs.contains($0) && !ShopWire.peperoCharacterIDs.contains($0) }
    return protocolVersion >= ShopWire.isulProtocol ? base + ShopWire.isulCharacterIDs : base
}

/// 로그인 + 팀 확정 상태의 스토어(서버 = 스텁 호스트 · 능력 번호 주입).
@MainActor
private func isStore(host: String, server: IsulGiftServer, spy: IsulWindowSpy, protocolVersion: Int = ShopWire.isulProtocol,
                     function: String = #function) -> WorkTimerStore {
    GomokuStubProtocol.register(host: host) { rpc, body, _ in server.handle(rpc, body) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults("v0374-isul-" + host, function: function),
                               tokenUsage: isTokenStore(host, function: function))
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: isUser)
    store.currentTeamID = "00000000-0000-0000-0000-0000000000ab"
    store.membershipConfirmed = true
    store.characterDefaults = CheckTestScratch.defaults("v0374-isul-char-" + host, function: function)
    store.characterSync.broadcast = CharacterSelectionBroadcast()
    store.cakeGiftWindowHooks = spy.hooks
    store.drawableCharacterIDs = isDrawable(protocolVersion)
    V0354CoreStub.retain(store)
    return store
}

private func isHost(_ name: String) -> String {
    "v0374-isul-\(name)-\(UUID().uuidString.lowercased().prefix(8))"
}

/// 요청이 **안 나갔음**을 말하기 전의 짧은 여유(나갔다면 이 사이에 스텁에 기록된다).
private func isQuiet() async {
    try? await Task.sleep(for: .milliseconds(150))
}

private func isPendingCount(_ host: String) -> Int {
    GomokuStubProtocol.count(host: host, rpc: "character_gift_pending")
}

@MainActor
@Suite("v0.3.74 술 한잔 선물 — 맥 스토어 배선", .serialized)
struct V0374IsulMacGiftStoreTests {
    // MARK: ① 술 선물 — 띄우기 · 받기 · 입기

    @Test("술 선물: 번호 5 로 묻고 · 실행당 한 번 스스로(키 안 잡음) · 고르기 없이 이슬을 미리 골라 둔다 · 카드 · 창 문구는 술 한잔")
    func drinkGiftShowsOnceWithoutChoosing() async throws {
        let host = isHost("show")
        let server = IsulGiftServer()
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], note: "오늘 한잔 어때?", createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        #expect(store.shopProtocolVersion == ShopWire.isulProtocol && store.supportsDrinkGift, "전제: 번호 5 주입이 안 먹었다")
        await store.refreshCakeGift(reason: .launch)?.value

        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").first, "묻지 않았다")
        #expect(Set(call.json.keys) == ["p_protocol"] && call.json["p_protocol"] as? Int == ShopWire.isulProtocol, "본문 \(call.json)")
        let offer = try #require(store.cakeGiftOffer, "술 선물을 못 읽었다")
        #expect(offer.kind == .drink && offer.id == isDrinkID && offer.options == [isIsul] && offer.note == "오늘 한잔 어때?")
        #expect(spy.shows == [false], "스스로 띄우기가 \(spy.shows) — 한 번 · 키를 안 잡아야 한다")
        #expect(store.cakeGiftPresented == offer && store.cakeGiftChoice == isIsul && store.canConfirmCakeGift,
                "고를 것이 없는 선물인데 확인 단추가 잠겼다")
        #expect(store.showsCakeGiftCard && store.cakeGiftCardCopy == .drink && store.cakeGiftWindowCopy == .drink)
        #expect(store.cakeGiftCardCopy.reopenTitle == DrinkGiftText.reopenTitle && store.cakeGiftCardCopy.reopenButton == DrinkGiftText.reopenButton)
        #expect(CheckCakeGiftWindowController.title(for: offer.kind) == DrinkGiftText.title)
        #expect(CheckCakeGiftWindowController.title(for: .birthday) == CakeGiftText.title
                && CheckCakeGiftWindowController.title(for: nil) == CheckCakeGiftWindowController.windowTitle)

        // 받지 않고 닫는다 → 선물은 남는다 · 다음 선물을 묻지 않는다(서버는 같은 선물을 다시 줄 뿐이다).
        store.closeCakeGiftWindow()
        await isQuiet()
        #expect(store.cakeGiftOffer == offer && store.showsCakeGiftCard, "닫았더니 카드가 사라졌다")
        #expect(isPendingCount(host) == 1, "받지 않고 닫았는데 다시 물었다")

        // 같은 실행에서 다시 물어도 또 안 띄운다 · [받기] 카드는 키를 잡고 띄운다.
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(spy.shows == [false], "같은 실행에서 두 번 띄웠다 — \(spy.shows)")
        store.openCakeGiftWindow()
        #expect(spy.shows == [false, true] && store.cakeGiftChoice == isIsul)
    }

    @Test("술 선물 받기 ok: 본문 키 셋(p_protocol 5 · aing_isul) · 받은 뒤 화면 · 보유 · 카드 거둠 · 상점 다시 읽기 · [지금 입기]는 set_character")
    func drinkClaimOkWearsThroughTheExistingPath() async throws {
        let host = isHost("ok")
        let server = IsulGiftServer()
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        let shopBefore = GomokuStubProtocol.count(host: host, rpc: "shop_state")
        await store.claimCakeGift()?.value

        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").last, "수령이 안 나갔다")
        #expect(Set(call.json.keys) == ["p_gift", "p_character", "p_protocol"], "본문 \(call.json)")
        #expect(call.json["p_gift"] as? String == isDrinkID && call.json["p_character"] as? String == isIsul
                && call.json["p_protocol"] as? Int == ShopWire.isulProtocol, "본문 \(call.json)")
        #expect(store.cakeGiftReceivedID == isIsul && store.cakeGiftNotice == nil, "받은 뒤 화면으로 안 넘어갔다")
        #expect(store.ownedCharacterIDs.contains(isIsul))
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "받았는데 다시 열기 카드가 남았다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") > shopBefore }, "받은 뒤 상점을 다시 안 읽었다")
        #expect(await V0354CoreStub.waitUntil { store.shopCharacters.first { $0.id == isIsul }?.owned == true }, "다시 읽은 상점이 보유를 모른다")
        #expect(store.characterPickerIDs.contains(isIsul), "받은 이슬이 고르기에 안 선다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "set_character") == 0, "수령이 착용까지 바꿨다")
        #expect(isPendingCount(host) == 1, "창이 떠 있는데(받은 뒤 화면) 다음 선물을 물었다")

        // [지금 입기] — 기존 착용 경로(로컬 저장 → 방송 → 서버 set_character). 창을 닫고 다음 선물을 한 번 묻는다(없음).
        let revision = store.characterSync.broadcast.revision
        store.wearCakeGift()
        let selected = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).selectedID
        #expect(selected == isIsul, "로컬 착용이 \(selected)")
        #expect(store.characterSync.broadcast.revision == revision + 1 && store.characterSync.broadcast.selectedID == isIsul)
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "set_character") == 1 }, "서버 착용이 안 나갔다")
        #expect(GomokuStubProtocol.calls(host: host, rpc: "set_character").last?.json["p_id"] as? String == isIsul)
        #expect(spy.closes >= 1 && store.cakeGiftReceivedID == nil)
        #expect(await V0354CoreStub.waitUntil { isPendingCount(host) == 2 }, "받고 닫았는데 다음 선물을 안 물었다")
        _ = await V0354CoreStub.waitUntil { !store.cakeGiftChecking }
        #expect(store.cakeGiftOffer == nil && spy.shows == [false], "다음 선물이 없는데 무언가 떴다 — \(spy.shows)")
    }

    // MARK: ② 받기 결과 갈래

    @Test("술 선물 받기 결과: replayed 는 받은 뒤 화면 · needs_update · invalid_choice 는 문구 + 선물 그대로 · not_found 는 잠그고 카드 거둠",
          arguments: ["replayed", "needs_update", "invalid_choice", "not_found", "502"])
    func drinkClaimOutcomes(status: String) async throws {
        let host = isHost("outcome-\(status)")
        let server = IsulGiftServer()
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let reply: String = switch status {
        case "replayed": #"{"status":"ok","character_id":"aing_isul","replayed":true}"#
        case "needs_update": #"{"status":"needs_update","min_protocol":5}"#
        case "502": #"{"message":"bad gateway"}"#
        default: #"{"status":"\#(status)"}"#
        }
        server.claimOverride = status == "502" ? .init(status: 502, body: reply) : .init(body: reply)
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        let offer = try #require(store.cakeGiftOffer)
        await store.claimCakeGift()?.value
        switch status {
        case "replayed":
            #expect(store.cakeGiftReceivedID == isIsul && store.cakeGiftNotice == nil)
            #expect(store.ownedCharacterIDs.contains(isIsul) && !store.showsCakeGiftCard)
        case "needs_update":
            #expect(store.cakeGiftNotice == DrinkGiftText.notice(for: .needsUpdate) { $0 } && store.cakeGiftNotice == CakeGiftText.needsUpdate)
            #expect(store.cakeGiftReceivedID == nil && !store.ownedCharacterIDs.contains(isIsul), "needs_update 인데 받은 것으로 적었다")
            #expect(store.cakeGiftOffer == offer && store.showsCakeGiftCard && store.canConfirmCakeGift, "선물이 그대로 열려 있어야 한다")
        case "502":
            // 결과를 모르는 수령 — 문구는 술 한잔 묶음의 실패 줄(검토 수리 G3 — 생일 묶음을 박지 않는다) · 다시 누를 수 있다.
            #expect(CharacterGiftCopy.drink.claimFailed == DrinkGiftText.claimFailed
                    && CharacterGiftCopy.birthday.claimFailed == CakeGiftText.claimFailed)
            #expect(store.cakeGiftNotice == CharacterGiftKind.drink.copy.claimFailed, "실패 줄이 \(store.cakeGiftNotice ?? "nil")")
            #expect(store.cakeGiftReceivedID == nil && store.cakeGiftOffer == offer && store.canConfirmCakeGift, "다시 누를 수 없다")
        case "invalid_choice":
            #expect(store.cakeGiftNotice == CakeGiftText.invalidChoice)
            #expect(store.cakeGiftReceivedID == nil && store.cakeGiftOffer == offer && store.showsCakeGiftCard)
        default:
            #expect(store.cakeGiftNotice == CakeGiftText.notFound)
            #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard && !store.canConfirmCakeGift, "끝난 선물에 확인 단추 · 카드가 남았다")
            #expect(store.claimCakeGift() == nil, "끝난 선물에 수령이 또 나간다")
        }
    }

    // MARK: ③ 차례 — 생일과 술이 둘 다 열렸다

    @Test("생일과 술이 둘 다 열린 사람: 먼저 지급된 생일부터 · 받고 닫으면 다음(술)을 묻고 한 번 스스로 띄운다 · 받지 않고 닫으면 안 묻는다 · 다 받으면 끝")
    func birthdayThenDrinkInSequence() async throws {
        let host = isHost("seq")
        let server = IsulGiftServer()
        server.grant(id: isBirthdayID, kind: "birthday", options: [isStrawberry, isChoco], createdAt: "2026-11-01T09:00:00+00:00")
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], note: "오늘 한잔 어때?", createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        let birthday = try #require(store.cakeGiftOffer, "선물을 못 읽었다")
        #expect(birthday.kind == .birthday && birthday.id == isBirthdayID && birthday.options == [isStrawberry, isChoco])
        #expect(spy.shows == [false] && store.cakeGiftCardCopy == .birthday && store.cakeGiftChoice == nil)

        // 받지 않고 닫는다 — 서버는 같은 생일 선물을 줄 뿐이라 묻지 않는다(술은 아직 안 보인다).
        store.closeCakeGiftWindow()
        await isQuiet()
        #expect(isPendingCount(host) == 1 && store.cakeGiftOffer == birthday)

        // [고르기] → 딸기 → 받기. 받은 뒤 화면이 떠 있는 동안은 묻지 않는다(다음 창을 겹치지 않는다).
        store.openCakeGiftWindow()
        store.chooseCakeGift(isStrawberry)
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == isStrawberry)
        await isQuiet()
        #expect(isPendingCount(host) == 1, "받은 뒤 화면이 떠 있는데 다음 선물을 물었다")

        // 닫는다 → 팝오버로 한 번 돌아가고 · 다음 선물(술)을 묻고 · 이 실행에서 처음 본 선물이라 한 번 스스로 띄운다(키 안 잡음).
        store.closeCakeGiftWindow()
        #expect(spy.returns == 1, "카드로 연 창이 팝오버로 안 돌아갔다")
        #expect(await V0354CoreStub.waitUntil { store.cakeGiftOffer?.kind == .drink }, "생일을 받고 닫았는데 술 선물이 안 왔다")
        let drink = try #require(store.cakeGiftOffer)
        #expect(drink.id == isDrinkID && drink.note == "오늘 한잔 어때?")
        let pendingCall = try #require(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").last)
        #expect(pendingCall.json["p_protocol"] as? Int == ShopWire.isulProtocol)
        #expect(spy.shows == [false, true, false], "다음 선물 띄우기가 \(spy.shows)")
        #expect(store.cakeGiftPresented == drink && store.cakeGiftChoice == isIsul && store.cakeGiftReceivedID == nil)
        #expect(store.cakeGiftCardCopy == .drink && store.cakeGiftWindowCopy == .drink)

        // 술을 받고 닫는다 → 한 번 더 묻고 없음 → 아무것도 안 뜬다.
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == isIsul)
        store.closeCakeGiftWindow()
        #expect(spy.returns == 1, "스스로 띄운 창이 팝오버로 돌아갔다")
        #expect(await V0354CoreStub.waitUntil { isPendingCount(host) == 3 }, "술까지 받았는데 마지막 확인을 안 물었다")
        _ = await V0354CoreStub.waitUntil { !store.cakeGiftChecking }
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard && spy.shows == [false, true, false])
        #expect(store.ownedCharacterIDs.isSuperset(of: [isStrawberry, isIsul]))
    }

    @Test("받는 사이에 창을 닫았으면 결론 즉시 다음 선물을 묻는다 · 조회가 떠 있으면 그 뒤에 한 번 더 묻는다(겹쳐 쏘지 않는다)")
    func followUpWhenClosedEarlyAndWhileChecking() async throws {
        let host = isHost("early")
        let server = IsulGiftServer()
        server.grant(id: isBirthdayID, kind: "birthday", options: [isChoco], createdAt: "2026-11-01T09:00:00+00:00")
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(store.cakeGiftChoice == isChoco, "전제: 선택지 하나면 미리 골라 둔다")

        // 늦게 오는 조회를 하나 띄워 둔다(결론 **전**의 서버 값 — 생일이 아직 열려 있다).
        server.pendingDelay = 0.6
        let slow = store.refreshCakeGift(reason: .shop)
        #expect(slow != nil && store.cakeGiftChecking, "전제: 둘째 조회가 안 떠났다")
        // 스텁은 요청이 **닿는 순간** 본문을 정한다 — 받기 RPC 가 먼저 닿으면 느린 조회가 이미 술을 싣고 와
        // '떠 있던 조회 뒤 한 번 더'를 재지 못한다(셋째 조회가 기다림보다 늦게 닿아 2 에서 빨강, 11-03 한 번).
        #expect(await V0354CoreStub.waitUntil { isPendingCount(host) == 2 }, "전제: 느린 조회가 스텁에 안 닿았다")
        // 받는 사이 창을 닫는다(빨간 점) — 결론이 아직 없으니 이 닫기는 묻지 않는다.
        let claim = store.claimCakeGift()
        store.closeCakeGiftWindow()
        await claim?.value
        #expect(store.ownedCharacterIDs.contains(isChoco), "전제: 받지 못했다")
        // 결론이 났고 창은 닫혀 있다 → 지금 묻고 싶지만 조회가 떠 있다 → 깃발만(겹쳐 쏘지 않는다).
        #expect(isPendingCount(host) == 2, "조회가 떠 있는데 겹쳐 쐈다(\(isPendingCount(host)))")
        server.pendingDelay = 0
        await slow?.value
        // 느린 조회가 끝나면 한 번 더 묻는다 → 술 선물.
        #expect(await V0354CoreStub.waitUntil { store.cakeGiftOffer?.kind == .drink }, "떠 있던 조회 뒤에 다음 선물을 안 물었다")
        #expect(isPendingCount(host) == 3)
        #expect(spy.shows.last == false && spy.shows.count == 2, "술 선물 띄우기가 \(spy.shows)")
    }

    @Test("받은 뒤 화면이 떠 있는 동안 조회가 다음 선물을 돌려주면 '띄웠음'으로 적지 않는다 — 닫으면 다음 선물 창이 한 번 뜬다(검토 수리)")
    func nextGiftArrivingUnderTheReceivedScreenShowsAfterClose() async throws {
        let host = isHost("under")
        let server = IsulGiftServer()
        server.grant(id: isBirthdayID, kind: "birthday", options: [isChoco], createdAt: "2026-11-01T09:00:00+00:00")
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(spy.shows == [false] && store.cakeGiftChoice == isChoco, "전제: 생일을 스스로 띄우고 하나 남은 선택지를 미리 골랐다")
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == isChoco && spy.open, "전제: 받은 뒤 화면이 떠 있다")

        // 받은 뒤 화면이 떠 있는 동안 상점 진입 조회가 다음 선물(술)을 돌려준다 — 겹쳐 띄우지 않고, '띄웠음'으로도 적지 않는다.
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer?.id == isDrinkID && store.showsCakeGiftCard, "전제: 조회가 다음 선물을 못 읽었다")
        #expect(spy.shows == [false], "받은 뒤 화면 위로 다음 창을 겹쳤다 — \(spy.shows)")
        #expect(!store.cakeGiftAutoShownIDs.contains(isDrinkID), "띄우지 않은 선물을 '띄웠음'으로 적었다 — 닫은 뒤에도 안 뜬다")

        // 닫는다 → 다음 선물 되묻기가 같은 선물을 받아 이번엔 스스로 띄운다(키 안 잡음).
        store.closeCakeGiftWindow()
        #expect(await V0354CoreStub.waitUntil { spy.shows.count == 2 }, "닫았는데 다음 선물 창이 안 떴다 — \(spy.shows)")
        #expect(spy.shows == [false, false] && store.cakeGiftPresented?.id == isDrinkID && store.cakeGiftChoice == isIsul)
        #expect(store.cakeGiftAutoShownIDs.contains(isDrinkID) && isPendingCount(host) == 3, "조회 \(isPendingCount(host))번")


        // 짝: 열린 창이 **같은** 선물을 그리면(받은 뒤 화면에서 카드의 [받기] 로 연 술 선물) 그것은 띄운 것이다 — 조회가 그 선물을 말하면
        // '띄웠음'으로 적고, 고르지 않고 닫은 뒤 다시 물어도 스스로 또 띄우지 않는다(실행당 한 번).
        let host2 = isHost("under-same")
        let server2 = IsulGiftServer()
        server2.grant(id: isBirthdayID, kind: "birthday", options: [isChoco], createdAt: "2026-11-01T09:00:00+00:00")
        server2.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let spy2 = IsulWindowSpy()
        let store2 = isStore(host: host2, server: server2, spy: spy2)
        await store2.refreshCakeGift(reason: .launch)?.value
        await store2.claimCakeGift()?.value
        await store2.refreshCakeGift(reason: .shop)?.value
        #expect(store2.cakeGiftReceivedID == isChoco && store2.cakeGiftOffer?.id == isDrinkID && spy2.shows == [false], "전제")
        store2.openCakeGiftWindow()
        #expect(spy2.shows == [false, true] && store2.cakeGiftPresented?.id == isDrinkID && store2.cakeGiftReceivedID == nil)
        await store2.refreshCakeGift(reason: .shop)?.value
        #expect(store2.cakeGiftAutoShownIDs.contains(isDrinkID), "같은 선물을 그리는 창인데 '띄웠음'으로 안 적었다")
        store2.closeCakeGiftWindow()
        await store2.refreshCakeGift(reason: .periodic)?.value
        #expect(spy2.shows == [false, true], "이미 본 선물을 닫은 뒤 다시 물었더니 스스로 또 띄웠다 — \(spy2.shows)")
    }

    @Test("로그아웃 · 다른 계정: 앞 계정이 가진 이슬로 새 계정의 술 선물을 거르지 않는다 — 이 계정의 상점을 읽기 전엔 보유로 안 거른다(검토 수리)")
    func previousAccountOwnershipDoesNotSwallowTheDrinkGift() async throws {
        let host = isHost("switch")
        let server = IsulGiftServer()
        server.owned = [isIsul]
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy)
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { store.ownedCharacterIDs.contains(isIsul) }, "전제: 앞 계정의 이슬 보유를 못 읽었다")
        store.signOut(notifyServer: false)
        #expect(store.ownedCharacterIDs.contains(isIsul), "전제: 로그아웃 뒤에도 보유 집합이 남는다(이 시험이 재는 자리)")

        // 다음 사람(이슬 없음)에게 술 선물이 열려 있다.
        server.owned = []
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        store.session = SupabaseSession(accessToken: "access-token-b", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000f2")
        store.membershipConfirmed = true
        await store.refreshCakeGift(reason: .signIn)?.value
        #expect(store.cakeGiftOffer?.id == isDrinkID && store.showsCakeGiftCard, "앞 계정의 보유로 새 계정의 술 선물을 걸렀다")
        #expect(spy.shows.last == false && store.cakeGiftPresented?.id == isDrinkID, "새 계정의 술 선물이 안 떴다 — \(spy.shows)")

        // 이 계정의 상점을 읽으면 그 보유로 맞춘다(여전히 이슬 없음 → 선물 그대로).
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { !store.ownedCharacterIDs.contains(isIsul) }, "새 계정의 상점을 못 읽었다")
        #expect(store.cakeGiftOffer?.id == isDrinkID)
    }

    // MARK: ④ 번호 4 — 이슬을 못 그리는 빌드

    @Test("번호 4: 서버는 생일만 준다 — 술 선물만 열린 사람에겐 아무것도 안 뜬다 · 서버가 섞어 보내도 안 띄운다")
    func protocolFourNeverShowsTheDrinkGift() async throws {
        let host = isHost("p4")
        let server = IsulGiftServer()
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], note: "오늘 한잔 어때?", createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy, protocolVersion: ShopWire.cakeProtocol)
        #expect(store.shopProtocolVersion == ShopWire.cakeProtocol && !store.supportsDrinkGift, "전제: 번호 4 주입이 안 먹었다")
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").first?.json["p_protocol"] as? Int == ShopWire.cakeProtocol)
        #expect(store.cakeGiftOffer == nil && spy.shows.isEmpty && !store.showsCakeGiftCard, "번호 4 에 술 선물이 떴다")

        // 서버가 규칙을 어기고 번호 4 에 술 선물을 실어도(초안 전 · 잘못된 배포) 받을 수 없는 창은 안 띄운다.
        server.pendingOverride = .init(body: #"{"status":"ok","gift":{"id":"\#(isDrinkID)","kind":"drink","options":["aing_isul"],"note":null,"created_at":"2026-11-08T12:00:00+00:00"}}"#)
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer == nil && spy.shows.isEmpty && !store.showsCakeGiftCard, "번호 4 에 섞여 온 술 선물을 띄웠다")
    }

    @Test("번호 4 의 생일 흐름은 0.3.73 그대로: 받고 닫아도 '다음 선물'을 묻지 않는다(요청 수가 같다)")
    func protocolFourBirthdayFlowIsUnchanged() async throws {
        let host = isHost("p4-cake")
        let server = IsulGiftServer()
        server.grant(id: isBirthdayID, kind: "birthday", options: [isStrawberry, isChoco], createdAt: "2026-11-01T09:00:00+00:00")
        server.grant(id: isDrinkID, kind: "drink", options: [isIsul], createdAt: "2026-11-08T12:00:00+00:00")
        let spy = IsulWindowSpy()
        let store = isStore(host: host, server: server, spy: spy, protocolVersion: ShopWire.cakeProtocol)
        await store.refreshCakeGift(reason: .launch)?.value
        let birthday = try #require(store.cakeGiftOffer)
        #expect(birthday.kind == .birthday && spy.shows == [false])
        store.chooseCakeGift(isChoco)
        await store.claimCakeGift()?.value
        let claim = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").last)
        #expect(claim.json["p_protocol"] as? Int == ShopWire.cakeProtocol)
        #expect(store.cakeGiftReceivedID == isChoco)
        store.wearCakeGift()
        await isQuiet()
        #expect(isPendingCount(host) == 1, "번호 4 빌드가 받은 뒤 다시 물었다(0.3.73 은 묻지 않는다)")
        #expect(store.cakeGiftOffer == nil && spy.shows == [false] && !store.cakeGiftFollowUpQueued)
        // 받는 창을 그대로 두고(받은 뒤) 결론이 나도 번호 4 에선 아무 깃발도 안 선다.
        #expect(store.followUpCakeGiftIfNeeded() == nil && !store.cakeGiftFollowUpQueued)
    }

    // MARK: ⑤ 상점 — 잠긴 칸 문구 · 정책

    @Test("상점 문구: 이슬을 누르면 술 한잔 안내 · 케이크는 생일 안내 그대로 · 되돌림 · 말풍선 · 읽기 이름도 종류 문구")
    func shopNoticesSpeakTheGiftKind() {
        let rows = [ShopCharacterRow(id: isStrawberry, price: 2000, owned: false, gachaOnly: true, giftOnly: true),
                    ShopCharacterRow(id: isIsul, price: 2002, owned: false, gachaOnly: true, giftOnly: true)]
        #expect(WorkTimerStore.giftCopy(for: isIsul) == .drink && WorkTimerStore.giftCopy(for: isChoco) == .birthday)
        #expect(WorkTimerStore.giftCopy(for: "server_only_gift") == .birthday, "표식으로만 선물 전용인 모르는 id 는 생일(0.3.66 선례)")
        #expect(WorkTimerStore.revertNotice(for: isIsul, rows: rows) == "아직 없는 캐릭터라 기본으로 돌아갔어요 — " + DrinkGiftText.lockedHint)
        #expect(WorkTimerStore.revertNotice(for: isStrawberry, rows: rows) == WorkTimerStore.giftOnlyRevertNotice)
        #expect(ShopCardLine.of(id: isIsul, owned: false, rows: rows) == .giftLocked)
        #expect(ShopCardLine.of(id: isIsul, owned: true, rows: rows) == .price, "가진 이슬은 보통 보유 칸")
        #expect(ShopCardLine.giftLocked.tooltip(name: "이슬 아잉이", owned: false, gift: .drink) == "이슬 아잉이 — \(DrinkGiftText.lockedHint)")
        #expect(ShopCardLine.giftLocked.accessibilityLabel(name: "이슬 아잉이", owned: false, gift: .drink)
                == "이슬 아잉이 잠김, \(DrinkGiftText.lockedCaption) — \(DrinkGiftText.lockedHint)")
        #expect(ShopCardLine.giftLocked.tooltip(name: "딸기", owned: false) == "딸기 — \(CakeGiftText.lockedHint)", "기본은 생일 그대로")
        #expect(!ShopText.barShowsBuyButton(selection: nil, notice: DrinkGiftText.lockedHint))
        #expect(!ShopText.barShowsBuyButton(selection: nil, notice: CakeGiftText.lockedHint))
        #expect(ShopText.barShowsBuyButton(selection: nil, notice: nil) && ShopText.barShowsBuyButton(selection: nil, notice: "샀어요!"))

        let store = V0317ShopTests.plainStore()
        store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 0, ultraPrice: 3, ultraBuyMax: 20, characters: rows))
        store.shopLoaded = true
        store.selectShopItem(.character(isIsul))
        #expect(store.shopSelection == nil && store.shopNotice == DrinkGiftText.lockedHint, "이슬 잠긴 칸이 \(store.shopNotice ?? "nil")")
        store.selectShopItem(.character(isStrawberry))
        #expect(store.shopSelection == nil && store.shopNotice == CakeGiftText.lockedHint)
    }

    @Test("잠긴 칸 정책 상수: 기본 = 모두에게(케이크 선례) · 뒤집으면 가진 사람만 — 케이크 · 다른 줄은 두 값 모두 그대로")
    func lockedCellPolicyBothValues() {
        #expect(WorkTimerStore.drinkGiftLockedCellPolicy == .everyone, "기본은 케이크 선례('모두에게 잠긴 칸')다")
        let rows = [ShopCharacterRow(id: "fox", price: 60, owned: false),
                    ShopCharacterRow(id: isStrawberry, price: 2000, owned: false, gachaOnly: true, giftOnly: true),
                    ShopCharacterRow(id: isChoco, price: 2000, owned: true, gachaOnly: true, giftOnly: true),
                    ShopCharacterRow(id: isIsul, price: 2002, owned: false, gachaOnly: true, giftOnly: true)]
        let ids = { (rows: [ShopCharacterRow]) in rows.map(\.id) }
        // 모두에게: 한 칸도 안 건드린다.
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [], drinkPolicy: .everyone)) == ids(rows))
        // 가진 사람만: 안 가진 이슬만 빠진다(안 가진 딸기 케이크는 그대로 — 생일은 정책 밖).
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [], drinkPolicy: .ownersOnly)) == ["fox", isStrawberry, isChoco])
        // 가졌으면 선다(서버 owned 또는 이 맥이 아는 보유).
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [isIsul], drinkPolicy: .ownersOnly)) == ids(rows))
        var ownedRows = rows
        ownedRows[3] = ShopCharacterRow(id: isIsul, price: 2002, owned: true, gachaOnly: true, giftOnly: true)
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(ownedRows, owned: [], drinkPolicy: .ownersOnly)) == ids(rows))

        // 격자가 부르는 자리(`shopGridRows`)도 같은 정책을 탄다 — 스토어 이음새로 두 값을 다 잰다.
        let store = V0317ShopTests.plainStore()
        store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 0, ultraPrice: 3, ultraBuyMax: 20, characters: rows))
        store.shopLoaded = true
        #expect(store.drinkGiftCellPolicy == WorkTimerStore.drinkGiftLockedCellPolicy, "스토어 이음새의 기본값이 상수가 아니다")
        let catalog = CheckCharacter3DScene.catalog
        #expect(store.shopGridRows(catalog: catalog).map(\.id).contains(isIsul), "모두에게: 안 가진 이슬 잠긴 칸이 안 섰다")
        store.drinkGiftCellPolicy = .ownersOnly
        #expect(!store.shopGridRows(catalog: catalog).map(\.id).contains(isIsul), "가진 사람만: 안 가진 이슬이 섰다")
        #expect(store.shopGridRows(catalog: catalog).map(\.id).contains(isStrawberry), "가진 사람만 정책이 케이크까지 숨겼다")
        store.ownedCharacterIDs.insert(isIsul)
        #expect(store.shopGridRows(catalog: catalog).map(\.id).contains(isIsul), "가진 사람만: 가진 이슬이 안 섰다")
    }
}
