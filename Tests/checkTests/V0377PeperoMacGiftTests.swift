import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.77 — 빼빼로 아잉이 '빼빼로 데이' 선물의 **맥 배선**(그림 제외). 이슬(V0374IsulMacGiftStoreTests · V0374IsulMacScreensTests)과 같은 틀이다.
// 창은 훅을 갈아 끼워 센다(화면에 아무것도 안 뜬다) · 화면은 ImageRenderer(창 없이). 서버는 호스트별 스텁인데 서버 규칙을 흉내 낸다
// (`PeperoGiftServer` — pending: p<4 없음 · p=4 생일만(kind 키 없음) · p=5 생일 · 술 · p≥6 빼빼로까지, 먼저 지급된 것 하나 + kind ·
// claim 의 needs_update 문턱 생일 4 · 술 5 · 빼빼로 6). 재는 것:
//  ① 번호 6(빼빼로까지 그리는 빌드 — 그림이 붙은 뒤의 맥): 빼빼로 선물이 실행당 한 번 스스로 뜨고 · 고르기 없이 미리 골라 두고 · 본문 키 셋
//     (p_protocol 6) · 받은 뒤 보유 · 카드 거둠 · 종류 문구.
//  ② ★ 번호 5(지금의 맥 — 빼빼로 그림 없음): 빼빼로 선물은 안 뜬다(서버가 안 싣고, 섞여 와도 안 띄운다) · 같은 사람의 술 선물은 그대로 뜬다.
//  ③ 차례: 술과 빼빼로가 둘 다 열린 사람(번호 6)은 하나씩 — 술을 받고 닫으면 빼빼로가 한 번 스스로 뜬다.
//  ④ 받기 결과 문구 · 다시 열기 카드 기호 · 받는 창(초대장 화면 · 제목 · 높이 예산) · 상점 잠긴 칸(문구 · 정책 '모두에게').

private let ppPepero = CharacterCatalog.peperoAingID
private let ppIsul = CharacterCatalog.isulAingID
private let ppStrawberry = CharacterCatalog.cakeStrawberryAingID
private let ppChoco = CharacterCatalog.cakeChocoAingID
private let ppUser = "00000000-0000-0000-0000-0000000000f7"
private let ppPeperoID = "5e5e1111-0000-4000-8000-00000000b011"
private let ppDrinkID = "aa4eef81-0000-4000-8000-0000000000d7"

/// 창 훅 대역 — 띄운 횟수(키를 잡았는가) · 닫은 횟수 · 떠 있는가 · 팝오버로 돌아간 횟수.
@MainActor
private final class PeperoWindowSpy {
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

/// 서버 대역 — 이슬 서버(운영 20261108122000)의 규칙에 빼빼로 종류(최소 번호 6)를 더한 모양. 핸들러는 URLProtocol 스레드에서 돈다.
private final class PeperoGiftServer: @unchecked Sendable {
    struct Gift {
        let id: String
        let kind: String
        let options: [String]
        let note: String?
        var claimedWith: String?
    }

    private let lock = NSLock()
    private var _gifts: [Gift] = []
    private var _owned: Set<String> = []
    private var _pendingOverride: GomokuStubProtocol.Reply?

    var pendingOverride: GomokuStubProtocol.Reply? {
        get { lock.withLock { _pendingOverride } }
        set { lock.withLock { _pendingOverride = newValue } }
    }

    static func minProtocol(_ kind: String) -> Int {
        switch kind {
        case "drink": return 5
        case "pepero": return 6
        default: return 4
        }
    }

    func grant(id: String, kind: String, options: [String], note: String? = nil) {
        lock.withLock { _gifts.append(Gift(id: id, kind: kind, options: options, note: note)) }
    }

    func handle(_ rpc: String, _ body: String) -> GomokuStubProtocol.Reply? {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        let p = json["p_protocol"] as? Int ?? 0
        switch rpc {
        case "character_gift_pending":
            if let fixed = pendingOverride { return fixed }
            return .init(body: pending(protocolVersion: p))
        case "claim_character_gift":
            return .init(body: claim(gift: json["p_gift"] as? String, character: json["p_character"] as? String, protocolVersion: p))
        case "shop_state":
            let owned = lock.withLock { _owned }
            var rows = [#"{"id":"fox","price":60,"owned":\#(owned.contains("fox")),"gacha_only":false,"gift_only":false}"#]
            rows += [ppChoco, ppStrawberry].map { #"{"id":"\#($0)","price":2000,"owned":\#(owned.contains($0)),"gacha_only":true,"gift_only":true}"# }
            if p >= 5 { rows.append(#"{"id":"\#(ppIsul)","price":2002,"owned":\#(owned.contains(ppIsul)),"gacha_only":true,"gift_only":true}"#) }
            if p >= 6 { rows.append(#"{"id":"\#(ppPepero)","price":2003,"owned":\#(owned.contains(ppPepero)),"gacha_only":true,"gift_only":true}"#) }
            return .init(body: #"{"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":["#
                         + rows.joined(separator: ",") + "]}")
        default:
            return nil
        }
    }

    private func pending(protocolVersion p: Int) -> String {
        lock.withLock {
            guard p >= 4 else { return #"{"status":"ok"}"# }
            let open = _gifts.filter { gift in
                gift.claimedWith == nil && Self.minProtocol(gift.kind) <= p && gift.options.contains { !_owned.contains($0) }
            }
            guard let gift = open.first else { return #"{"status":"ok"}"# }
            let options = gift.options.filter { !_owned.contains($0) }.map { "\"\($0)\"" }.joined(separator: ",")
            let note = gift.note.map { "\"\($0)\"" } ?? "null"
            let kind = p >= 5 ? #","kind":"\#(gift.kind)""# : ""
            return #"{"status":"ok","gift":{"id":"\#(gift.id)"\#(kind),"options":[\#(options)],"note":\#(note),"created_at":"2026-11-11T00:00:00+00:00"}}"#
        }
    }

    private func claim(gift giftID: String?, character: String?, protocolVersion p: Int) -> String {
        lock.withLock {
            guard let index = _gifts.firstIndex(where: { $0.id == giftID }) else { return #"{"status":"not_found"}"# }
            let gift = _gifts[index]
            let min = Self.minProtocol(gift.kind)
            if p < min { return #"{"status":"needs_update","min_protocol":\#(min)}"# }
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

/// 그릴 수 있는 캐릭터 — 번호 6(빼빼로까지) · 5(이슬까지, 빼빼로 뺌). 번호를 **주입**한다(그림이 붙은 뒤엔 번들 그대로가 6 — 5 는 옛 맥 흉내).
private func ppDrawable(_ protocolVersion: Int) -> [String] {
    // v0.3.78: 흑우까지 그리면(7) 번호 6 주입이 7 로 새지 않게 흑우도 뺀다.
    let base = WorkTimerStore.bundledDrawableCharacterIDs.filter {
        !ShopWire.peperoCharacterIDs.contains($0) && !ShopWire.isulCharacterIDs.contains($0) && !ShopWire.hwooCharacterIDs.contains($0) && !ShopWire.rubyCharacterIDs.contains($0)
            && !ShopWire.devCharacterIDs.contains($0)
    }
    switch protocolVersion {
    case ShopWire.devProtocol...: return base + ShopWire.isulCharacterIDs + ShopWire.peperoCharacterIDs + ShopWire.hwooCharacterIDs + ShopWire.rubyCharacterIDs
            + ShopWire.devCharacterIDs
    case ShopWire.rubyProtocol: return base + ShopWire.isulCharacterIDs + ShopWire.peperoCharacterIDs + ShopWire.hwooCharacterIDs + ShopWire.rubyCharacterIDs
    case ShopWire.hwooProtocol: return base + ShopWire.isulCharacterIDs + ShopWire.peperoCharacterIDs + ShopWire.hwooCharacterIDs
    case ShopWire.peperoProtocol: return base + ShopWire.isulCharacterIDs + ShopWire.peperoCharacterIDs
    case ShopWire.isulProtocol: return base + ShopWire.isulCharacterIDs
    default: return base
    }
}

@MainActor
private func ppStore(host: String, server: PeperoGiftServer, spy: PeperoWindowSpy, protocolVersion: Int,
                     function: String = #function) -> WorkTimerStore {
    GomokuStubProtocol.register(host: host) { rpc, body, _ in server.handle(rpc, body) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let scratch = CheckTestScratch.directory(host + "-tok", function: function)
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults("v0377-pepero-" + host, function: function),
                               tokenUsage: TokenUsageStore(defaults: CheckTestScratch.defaults(host + "-tok", function: function),
                                                           homeDirectory: scratch.appendingPathComponent("home", isDirectory: true),
                                                           cacheURL: scratch.appendingPathComponent("cache.json", isDirectory: false)))
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: ppUser)
    store.currentTeamID = "00000000-0000-0000-0000-0000000000ab"
    store.membershipConfirmed = true
    store.characterDefaults = CheckTestScratch.defaults("v0377-pepero-char-" + host, function: function)
    store.characterSync.broadcast = CharacterSelectionBroadcast()
    store.cakeGiftWindowHooks = spy.hooks
    store.drawableCharacterIDs = ppDrawable(protocolVersion)
    V0354CoreStub.retain(store)
    return store
}

private func ppHost(_ name: String) -> String {
    "v0377-pepero-\(name)-\(UUID().uuidString.lowercased().prefix(8))"
}

private func ppPendingCount(_ host: String) -> Int {
    GomokuStubProtocol.count(host: host, rpc: "character_gift_pending")
}

/// ImageRenderer 로 굽는다(배율 명시 · 두 번 굽고 둘째 — 저장소 함정 imagerenderer-first-two-renders-differ).
@MainActor
private func ppBitmap(_ view: some View) -> NSBitmapImageRep? {
    func once() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    _ = once()
    return once()
}

private func ppFingerprint(_ bitmap: NSBitmapImageRep) -> String {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

/// 받는 창 화면의 자연 높이(pt) — 자르기 전의 화면(`screen`)을 창 폭에서 세로를 풀어 잰다(V0374IsulMacScreensTests 와 같은 방법).
@MainActor
private func ppNaturalHeight(_ store: WorkTimerStore) throws -> CGFloat {
    let view = CheckCakeGiftWindowView(store: store, onClose: {}).screen
        .frame(width: CakeGiftWindowLayout.contentSize.width)
        .fixedSize(horizontal: false, vertical: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    _ = renderer.nsImage
    return try #require(renderer.nsImage, "자연 높이를 못 쟀다").size.height
}

private func ppOffer(note: String?) -> CharacterGiftOffer {
    CharacterGiftOffer(id: ppPeperoID, options: [ppPepero], note: note, createdAt: "2026-11-11T00:00:00+00:00", kind: .pepero)
}

/// 화면 시험용 스토어 — 메뉴 스토어(V0366) + **창 훅 대역**(진짜 창 · 팝오버 문을 안 건드린다) + 선물을 조회 결과로 받아 스스로 띄운 상태.
@MainActor
private func ppScreenStore(_ label: String, offer: CharacterGiftOffer, function: String = #function) -> (WorkTimerStore, PeperoWindowSpy) {
    let store = V0366CakeMacScreensTests.menuStore(label, function: function)
    let spy = PeperoWindowSpy()
    store.cakeGiftWindowHooks = spy.hooks
    store.applyCakeGiftPending(offer)
    return (store, spy)
}

@MainActor
@Suite("v0.3.77 빼빼로 데이 선물 — 맥 배선(그림 제외)", .serialized)
struct V0377PeperoMacGiftTests {
    // MARK: ① 번호 6 — 그림이 붙은 뒤의 맥

    @Test("번호 6: 빼빼로 선물이 실행당 한 번 스스로(키 안 잡음) · 고르기 없이 미리 골라 둠 · 받기 본문(p_protocol 6) · 받은 뒤 보유 · 카드 거둠")
    func peperoGiftAtSix() async throws {
        let host = ppHost("six")
        let server = PeperoGiftServer()
        server.grant(id: ppPeperoID, kind: "pepero", options: [ppPepero], note: "빼빼로 데이 축하해요")
        let spy = PeperoWindowSpy()
        let store = ppStore(host: host, server: server, spy: spy, protocolVersion: ShopWire.peperoProtocol)
        #expect(store.shopProtocolVersion == ShopWire.peperoProtocol, "전제: 번호 6 주입이 안 먹었다")
        await store.refreshCakeGift(reason: .launch)?.value

        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").first, "묻지 않았다")
        #expect(Set(call.json.keys) == ["p_protocol"] && call.json["p_protocol"] as? Int == ShopWire.peperoProtocol, "본문 \(call.json)")
        let offer = try #require(store.cakeGiftOffer, "빼빼로 선물을 못 읽었다")
        #expect(offer.kind == .pepero && offer.options == [ppPepero] && offer.note == "빼빼로 데이 축하해요")
        #expect(spy.shows == [false], "스스로 띄우기가 \(spy.shows) — 한 번 · 키를 안 잡아야 한다")
        #expect(store.cakeGiftChoice == ppPepero && store.canConfirmCakeGift, "고를 것이 없는 선물인데 확인 단추가 잠겼다")
        #expect(store.cakeGiftCardCopy == .pepero && store.cakeGiftWindowCopy == .pepero)
        #expect(CheckCakeGiftWindowController.title(presenting: store.cakeGiftPresented) == PeperoGiftText.title)

        await store.claimCakeGift()?.value
        let claim = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").last, "수령이 안 나갔다")
        #expect(Set(claim.json.keys) == ["p_gift", "p_character", "p_protocol"], "본문 \(claim.json)")
        #expect(claim.json["p_gift"] as? String == ppPeperoID && claim.json["p_character"] as? String == ppPepero
                && claim.json["p_protocol"] as? Int == ShopWire.peperoProtocol, "본문 \(claim.json)")
        #expect(store.cakeGiftReceivedID == ppPepero && store.cakeGiftNotice == nil)
        #expect(store.ownedCharacterIDs.contains(ppPepero))
        #expect(store.cakeGiftOffer == nil && !store.showsCakeGiftCard, "받았는데 다시 열기 카드가 남았다")
        #expect(store.characterPickerIDs.contains(ppPepero), "받은 빼빼로가 고르기에 안 선다")
    }

    // MARK: ② 번호 5 — 지금의 맥(빼빼로 그림 없음)

    @Test("번호 5: 빼빼로 선물은 안 뜬다(서버가 안 싣고 · 섞여 와도 안 띄운다) · 같은 사람의 술 선물은 그대로 뜬다")
    func protocolFiveNeverShowsPepero() async throws {
        let host = ppHost("five")
        let server = PeperoGiftServer()
        server.grant(id: ppPeperoID, kind: "pepero", options: [ppPepero])
        let spy = PeperoWindowSpy()
        let store = ppStore(host: host, server: server, spy: spy, protocolVersion: ShopWire.isulProtocol)
        #expect(store.shopProtocolVersion == ShopWire.isulProtocol && store.supportsDrinkGift, "전제: 번호 5 주입이 안 먹었다")
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending").first?.json["p_protocol"] as? Int == ShopWire.isulProtocol)
        #expect(store.cakeGiftOffer == nil && spy.shows.isEmpty && !store.showsCakeGiftCard, "번호 5 에 빼빼로 선물이 떴다")

        // 서버가 규칙을 어기고 번호 5 에 빼빼로 선물을 실어도(초안 전 · 잘못된 배포) 받을 수 없는 창은 안 띄운다.
        server.pendingOverride = .init(body: #"{"status":"ok","gift":{"id":"\#(ppPeperoID)","kind":"pepero","options":["aing_pepero"],"note":null}}"#)
        await store.refreshCakeGift(reason: .shop)?.value
        #expect(store.cakeGiftOffer == nil && spy.shows.isEmpty, "번호 5 에 섞여 온 빼빼로 선물을 띄웠다")
        server.pendingOverride = nil

        // 같은 사람에게 술 선물이 더 열리면(빼빼로가 먼저 지급됐어도) 번호 5 는 술 선물을 받는다 — 빼빼로가 술을 가리지 않는다.
        server.grant(id: ppDrinkID, kind: "drink", options: [ppIsul])
        await store.refreshCakeGift(reason: .periodic)?.value
        #expect(store.cakeGiftOffer?.kind == .drink && store.cakeGiftOffer?.id == ppDrinkID, "번호 5 의 술 선물이 빼빼로에 가렸다")
        #expect(spy.shows == [false] && store.cakeGiftWindowCopy == .drink)
    }

    // MARK: ③ 차례 — 술과 빼빼로가 둘 다 열린 사람(번호 6)

    @Test("번호 6 차례: 술 먼저(먼저 지급) — 받고 닫으면 빼빼로를 한 번 묻고 스스로 띄운다 · 빼빼로도 받는다")
    func drinkThenPeperoInTurn() async throws {
        let host = ppHost("turn")
        let server = PeperoGiftServer()
        server.grant(id: ppDrinkID, kind: "drink", options: [ppIsul])
        server.grant(id: ppPeperoID, kind: "pepero", options: [ppPepero])
        let spy = PeperoWindowSpy()
        let store = ppStore(host: host, server: server, spy: spy, protocolVersion: ShopWire.peperoProtocol)
        await store.refreshCakeGift(reason: .launch)?.value
        #expect(store.cakeGiftPresented?.kind == .drink && store.cakeGiftChoice == ppIsul && spy.shows == [false])
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == ppIsul)
        store.closeCakeGiftWindow()
        #expect(await V0354CoreStub.waitUntil { spy.shows.count == 2 }, "술을 받고 닫았는데 빼빼로 창이 안 떴다 — \(spy.shows)")
        #expect(spy.shows == [false, false] && store.cakeGiftPresented?.kind == .pepero && store.cakeGiftChoice == ppPepero)
        #expect(store.cakeGiftWindowCopy == .pepero && ppPendingCount(host) == 2)
        await store.claimCakeGift()?.value
        #expect(store.cakeGiftReceivedID == ppPepero && store.ownedCharacterIDs.isSuperset(of: [ppIsul, ppPepero]))
    }

    // MARK: ④ 결과 문구 · 카드 기호 · 받는 창 · 상점

    @Test("받기 결과: needs_update · not_found 는 빼빼로 묶음(생일과 같은 글자) · 받은 뒤 한 줄 · 카드 기호는 하트(셋 다 다르다)")
    func outcomesAndSymbols() {
        let (store, spy) = ppScreenStore("pepero-outcome", offer: ppOffer(note: nil))
        #expect(store.cakeGiftPresented?.kind == .pepero && spy.shows == [false])
        store.applyCakeGiftClaim(.needsUpdate, giftID: ppPeperoID)
        #expect(store.cakeGiftNotice == PeperoGiftText.notice(for: .needsUpdate) { $0 } && store.cakeGiftNotice == CakeGiftText.needsUpdate)
        store.applyCakeGiftClaim(.notFound, giftID: ppPeperoID)
        #expect(store.cakeGiftNotice == CakeGiftText.notFound && store.cakeGiftOffer == nil)
        #expect(CharacterGiftCopy.pepero.received(name: CharacterCatalog.peperoAingDisplayName) == "빼빼로 아잉이를 받았어요!")

        #expect(CharacterGiftKind.pepero.reopenSymbolName == "heart.fill")
        #expect(CharacterGiftKind.birthday.reopenSymbolName == "gift.fill" && CharacterGiftKind.drink.reopenSymbolName == "wineglass.fill",
                "생일 · 술 카드 기호가 바뀌었다")
        #expect(Set(CharacterGiftKind.allCases.map(\.reopenSymbolName)).count == CharacterGiftKind.allCases.count)
        for kind in CharacterGiftKind.allCases {
            #expect(NSImage(systemSymbolName: kind.reopenSymbolName, accessibilityDescription: nil) != nil, "\(kind) 기호가 이 OS 에 없다")
        }
        // 초대장 화면(고르기 없음)은 선택지가 하나인 종류 — 술 · 빼빼로. 생일은 고르기.
        #expect(!CharacterGiftKind.birthday.showsInviteScreen)
        #expect(CharacterGiftKind.drink.showsInviteScreen && CharacterGiftKind.pepero.showsInviteScreen)
        // 지역 아잉이(우리 센터 선물)는 내장이 둘(부산 · 서울)이지만 **한 사람의 선택지는 자기 센터 것 하나**다(서버가 고른다) — 초대장 화면.
        #expect(CharacterGiftKind.allCases.allSatisfy { $0.showsInviteScreen == ($0.builtInIDs.count == 1 || $0 == .region) })
    }

    @Test("받는 창(빼빼로): 초대장 화면 · 술 · 생일 화면과 다른 그림 · 긴 note + 실패 한 줄도 창 높이 안 · 제목은 빼빼로 · 화면 판정은 한 곳")
    func inviteWindow() throws {
        let size = CakeGiftWindowLayout.contentSize
        func shot(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try #require(ppBitmap(CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height)))
        }
        let (pepero, peperoSpy) = ppScreenStore("pepero-window", offer: ppOffer(note: "빼빼로 데이 축하해요"))
        #expect(peperoSpy.shows == [false] && pepero.cakeGiftPresented?.kind == .pepero, "전제: 빼빼로 선물이 안 섰다")
        #expect(pepero.cakeGiftChoice == ppPepero && pepero.canConfirmCakeGift, "빼빼로 선물인데 고르기가 남았다")
        let peperoShot = try shot(pepero)

        let (drink, _) = ppScreenStore("pepero-window-drink",
                                       offer: CharacterGiftOffer(id: ppDrinkID, options: [ppIsul], note: "빼빼로 데이 축하해요", kind: .drink))
        let drinkShot = try shot(drink)

        let (birthday, _) = ppScreenStore("pepero-window-birthday",
                                          offer: CharacterGiftOffer(id: "6f1c2a7e-1d1f-4b0e-9a55-0c5d7f3b2a10", options: [ppStrawberry, ppChoco]))
        #expect(birthday.cakeGiftChoice == nil, "전제: 생일은 고르기 화면")
        let birthdayShot = try shot(birthday)
        let prints = [peperoShot, drinkShot, birthdayShot].map(ppFingerprint)
        #expect(Set(prints).count == 3, "빼빼로 받는 창이 술 · 생일 화면과 같은 그림이다 — \(prints)")
        #expect(V0317ShopTests.longestYellowRun(peperoShot) < 24, "ImageRenderer '못 그림' 상자가 있다")

        // 높이 예산: 긴 두 줄 note + 실패 한 줄(최악)도 창 안(넘치면 고정 창이 [받기] 를 자른다).
        let (long, _) = ppScreenStore("pepero-window-long",
                                      offer: ppOffer(note: "오늘은 빼빼로 데이! 우리 팀 모두에게 마음을 담아 빼빼로 아잉이를 보내요. 늘 고마워요!"))
        long.cakeGiftNotice = PeperoGiftText.claimFailed
        let height = try ppNaturalHeight(long)
        #expect(height <= size.height && height > size.height / 2, "자연 높이 \(height)pt / 창 \(size.height)pt")

        #expect(CheckCakeGiftWindowController.title(presenting: pepero.cakeGiftPresented) == PeperoGiftText.title)
        #expect(CheckCakeGiftWindowController.title(for: .pepero) == PeperoGiftText.title)
        // 화면 판정 한 곳(`showsInviteScreen`) — 종류 하나를 박은 비교(`kind == .drink`)가 돌아오면 빼빼로가 생일 고르기 화면으로 선다.
        let window = V0351IfConfig.strippingComments(try V0374IsulMac3DTests.source("Sources/check/CheckCakeGiftWindow.swift"))
        #expect(window.contains("kind.showsInviteScreen"), "받는 창이 화면을 종류 판정으로 가르지 않는다")
        #expect(!window.contains("kind == .drink"), "받는 창이 술 한 종류만 초대장으로 세운다 — 빼빼로가 고르기 화면으로 선다")
    }

    @Test("상점: 빼빼로 잠긴 칸 문구 · 고르면 얻는 길(빼빼로) · [구매하기] 안 섬 · 정책 '모두에게'(상수) · 가진 사람만으로 뒤집으면 칸이 없다")
    func shopLockedCell() {
        let rows = [ShopCharacterRow(id: "fox", price: 60, owned: false, gachaOnly: false, giftOnly: false),
                    ShopCharacterRow(id: ppIsul, price: 2002, owned: false, gachaOnly: true, giftOnly: true),
                    ShopCharacterRow(id: ppPepero, price: 2003, owned: false, gachaOnly: true, giftOnly: true)]
        #expect(ShopCardLine.of(id: ppPepero, owned: false, rows: rows) == .giftLocked)
        #expect(ShopCardLine.giftLocked.tooltip(name: "빼빼로 아잉이", owned: false, gift: .pepero) == "빼빼로 아잉이 — \(PeperoGiftText.lockedHint)")
        #expect(ShopCardLine.giftLocked.accessibilityLabel(name: "빼빼로 아잉이", owned: false, gift: .pepero)
            == "빼빼로 아잉이 잠김, \(PeperoGiftText.lockedCaption) — \(PeperoGiftText.lockedHint)")
        #expect(ShopText.isGiftLockedHint(PeperoGiftText.lockedHint))
        #expect(!ShopText.barShowsBuyButton(selection: nil, notice: PeperoGiftText.lockedHint))

        // 정책: 상수는 '모두에게'(이슬과 같다) · 스토어 이음새의 기본값이 상수다.
        #expect(WorkTimerStore.peperoGiftLockedCellPolicy == .everyone)
        let ids: ([ShopCharacterRow]) -> [String] = { $0.map(\.id) }
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [], drinkPolicy: .everyone)) == ids(rows))
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [], drinkPolicy: .everyone, peperoPolicy: .ownersOnly))
            == ["fox", ppIsul], "빼빼로 정책이 빼빼로 칸을 못 거른다")
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [], drinkPolicy: .ownersOnly, peperoPolicy: .everyone))
            == ["fox", ppPepero], "술 정책이 빼빼로 칸까지 걸렀다(정책은 종류마다)")
        #expect(ids(WorkTimerStore.shopRowsApplyingGiftCellPolicy(rows, owned: [ppPepero], drinkPolicy: .everyone, peperoPolicy: .ownersOnly))
            == ids(rows), "가진 사람의 빼빼로 칸이 사라졌다")

        let store = V0317ShopTests.plainStore()
        #expect(store.peperoGiftCellPolicy == WorkTimerStore.peperoGiftLockedCellPolicy, "스토어 이음새의 기본값이 상수가 아니다")
        store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                               ultraBuyMax: 20, characters: rows))
        store.shopLoaded = true
        #expect(store.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id).contains(ppPepero), "'모두에게'인데 빼빼로 잠긴 칸이 없다")
        store.selectShopItem(.character(ppPepero))
        #expect(store.shopSelection == nil && store.shopNotice == PeperoGiftText.lockedHint, "잠긴 빼빼로 칸이 얻는 길을 말하지 않는다")
        store.peperoGiftCellPolicy = .ownersOnly
        #expect(!store.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id).contains(ppPepero))
        #expect(store.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id).contains(ppIsul), "빼빼로 정책이 이슬 칸을 걸렀다")
    }
}
