import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.74 — 이슬 아잉이 '술 한잔' 선물의 맥 **화면**(창 없이 — ImageRenderer): 받는 창(초대장 — note 있음 · 없음 · 실패 한 줄 · 받은 뒤) ·
// 메뉴 팝오버 '다시 열기' 카드(종류 문구) · 상점 잠긴 칸 · 보유 칸 · 잠긴 칸 정책(가진 사람만이면 칸이 없다).
// ImageRenderer 함정: 첫 장은 이미지 로드 전이라 다르게 나온다 — 언제나 두 번 굽고 둘째를 쓴다(`isBitmap`). Menu 는 못 그린다(이 화면들엔 없다).
// 증거 PNG: `CHECK_V0374_MAC_EVIDENCE_DIR=<폴더>` 를 주면 떨군다(기본 실행은 안 쓴다).

private let scIsul = CharacterCatalog.isulAingID
private let scStrawberry = CharacterCatalog.cakeStrawberryAingID
private let scChoco = CharacterCatalog.cakeChocoAingID

private let scEvidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0374_MAC_EVIDENCE_DIR"]

private func scSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = scEvidenceDirectory else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
}

/// ImageRenderer 로 굽는다(배율 명시 · 두 번 굽고 둘째 — 저장소 함정). `width` 를 주면 그 폭으로(상점 패널).
@MainActor
private func isBitmap(_ view: some View, width: CGFloat? = nil) -> NSBitmapImageRep? {
    func once() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    _ = once()
    return once()
}

/// 받는 창 화면의 **자연 높이**(pt) — 창 폭에서 세로를 풀어(`.fixedSize`) 잰다. 창(`body`)은 고정 크기로 자르므로 그 그림으로는 넘침을
/// 못 잰다(언제나 창 크기다) — 자르기 전의 화면(`screen`)을 잰다.
@MainActor
private func scNaturalHeight(_ store: WorkTimerStore) throws -> CGFloat {
    let view = CheckCakeGiftWindowView(store: store, onClose: {}).screen
        .frame(width: CakeGiftWindowLayout.contentSize.width)
        .fixedSize(horizontal: false, vertical: true)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    _ = renderer.nsImage
    return try #require(renderer.nsImage, "자연 높이를 못 쟀다").size.height
}

private func scFingerprint(_ bitmap: NSBitmapImageRep) -> String {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

/// 회색 팔레트 밖의 유채색 픽셀 수(그림이 실제로 칠해졌는가).
private func scColorful(_ bitmap: NSBitmapImageRep) -> Int {
    V0317ShopTests.count(bitmap) { r, g, b in max(r, g, b) - min(r, g, b) > 40 }
}

private func scDrinkOffer(note: String?) -> CharacterGiftOffer {
    CharacterGiftOffer(id: "aa4eef81-0000-4000-8000-0000000000d1", options: [scIsul], note: note,
                       createdAt: "2026-11-08T12:00:00+00:00", kind: .drink)
}

private let scBirthdayOffer = CharacterGiftOffer(id: "6f1c2a7e-1d1f-4b0e-9a55-0c5d7f3b2a10", options: [scStrawberry, scChoco],
                                                 note: nil, createdAt: "2026-10-26T07:51:40+00:00")

/// 상점 줄(첫 격자 줄에 서게 셋 — 격자는 3열).
private func scShopRows(owned: Set<String>, includeIsul: Bool = true) -> [ShopCharacterRow] {
    var rows = [ShopCharacterRow(id: "fox", price: 60, owned: owned.contains("fox"), gachaOnly: false, giftOnly: false),
                ShopCharacterRow(id: CharacterCatalog.goldAingID, price: 1000, owned: owned.contains(CharacterCatalog.goldAingID),
                                 gachaOnly: true, giftOnly: false)]
    if includeIsul {
        rows.append(ShopCharacterRow(id: scIsul, price: 2002, owned: owned.contains(scIsul), gachaOnly: true, giftOnly: true))
    }
    return rows
}

@MainActor
private func scShopStore(owned: Set<String>, includeIsul: Bool = true, policy: GiftLockedCellPolicy = .everyone,
                         function: String = #function, line: Int = #line) -> WorkTimerStore {
    let store = V0317ShopTests.plainStore(function: function, line: line)
    store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                           ultraBuyMax: 20, characters: scShopRows(owned: owned, includeIsul: includeIsul)))
    store.shopLoaded = true
    store.ownedCharacterIDs = owned.union([CharacterCatalog.builtInAingID])
    store.drinkGiftCellPolicy = policy
    return store
}

@MainActor
@Suite("v0.3.74 술 한잔 선물 — 맥 화면", .serialized)
struct V0374IsulMacScreensTests {
    // MARK: ① 받는 창 — 초대장

    @Test("받는 창(술 한잔): 초대장 note 있음 · 없음 · 실패 한 줄 · 받은 뒤 — 넷이 서로 다르고 이슬 초상이 칠해진다 · 생일 고르기 화면과 다르다")
    func inviteWindowScreens() throws {
        let size = CakeGiftWindowLayout.contentSize
        func shot(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try #require(isBitmap(CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height)))
        }
        let noted = V0366CakeMacScreensTests.menuStore("isul-window-note")
        noted.cakeGiftOffer = scDrinkOffer(note: "오늘 한잔 어때?")
        noted.openCakeGiftWindow()
        #expect(noted.cakeGiftPresented?.kind == .drink && noted.cakeGiftChoice == scIsul && noted.canConfirmCakeGift,
                "술 선물인데 고르기가 남았다(확인 단추가 잠김)")
        #expect(noted.cakeGiftWindowCopy == .drink)
        let inviteNote = try shot(noted)

        let plainStore = V0366CakeMacScreensTests.menuStore("isul-window-plain")
        plainStore.cakeGiftOffer = scDrinkOffer(note: nil)
        plainStore.openCakeGiftWindow()
        let invitePlain = try shot(plainStore)

        noted.cakeGiftNotice = DrinkGiftText.notice(for: .needsUpdate) { $0 }
        let failed = try shot(noted)
        noted.cakeGiftNotice = nil
        noted.applyCakeGiftClaim(.received(characterID: scIsul, replayed: false), giftID: scDrinkOffer(note: nil).id)
        #expect(noted.cakeGiftReceivedID == scIsul)
        let received = try shot(noted)

        let birthdayStore = V0366CakeMacScreensTests.menuStore("isul-window-birthday")
        birthdayStore.cakeGiftOffer = scBirthdayOffer
        birthdayStore.openCakeGiftWindow()
        let birthdayChoosing = try shot(birthdayStore)

        let prints = [inviteNote, invitePlain, failed, received, birthdayChoosing].map(scFingerprint)
        #expect(Set(prints).count == 5, "받는 창 화면 중 같은 그림이 있다 — \(prints)")
        for (name, bitmap) in [("invite-note", inviteNote), ("invite-plain", invitePlain), ("received", received)] {
            #expect(scColorful(bitmap) > 4_000, "\(name): 초상이 안 칠해졌다(\(scColorful(bitmap)))")
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): ImageRenderer '못 그림' 상자가 있다")
        }
        // 창 높이 예산(검토 수리): 긴 두 줄 note + 실패 한 줄이 겹친 최악의 초대장 · 받은 뒤 · 생일 고르기(실패 한 줄)의 자연 높이가 창 높이
        // 안이다(넘치면 고정 창이 위아래를 잘라 [받을게요] 가 잘린다). 기준선: 잰 값이 진짜 화면 높이다(창의 절반 이상).
        let long = V0366CakeMacScreensTests.menuStore("isul-window-long")
        long.cakeGiftOffer = scDrinkOffer(note: "오늘 저녁 일곱 시, 회사 앞 포장마차에서 우리 팀 다 같이 한잔 어때요? 꼭 와요!")
        long.openCakeGiftWindow()
        long.cakeGiftNotice = DrinkGiftText.claimFailed
        let inviteHeight = try scNaturalHeight(long)
        long.cakeGiftNotice = nil
        let plainHeight = try scNaturalHeight(plainStore)
        let receivedHeight = try scNaturalHeight(noted)
        birthdayStore.cakeGiftNotice = CakeGiftText.claimFailed
        let birthdayHeight = try scNaturalHeight(birthdayStore)
        print("[v0374-screens] 자연 높이 초대장(긴 note + 실패) \(inviteHeight) · 초대장(note 없음) \(plainHeight) · 받은 뒤 \(receivedHeight) · 생일(실패) \(birthdayHeight) / 창 \(size.height)")
        for (name, height) in [("invite-long", inviteHeight), ("invite-plain", plainHeight), ("received", receivedHeight), ("birthday-failed", birthdayHeight)] {
            #expect(height <= size.height, "\(name): 자연 높이 \(height)pt 가 창 높이 \(size.height)pt 를 넘는다 — 단추가 잘린다")
            #expect(height > size.height / 2, "\(name): 잰 높이 \(height)pt 가 화면 높이가 아니다(시험이 헛돈다)")
        }
        #expect(inviteHeight > plainHeight, "긴 두 줄 note + 실패 한 줄이 높이를 안 늘렸다(\(inviteHeight) vs \(plainHeight)) — 시험이 헛돈다")

        // 창 제목(검토 수리): `show()` 가 쓰는 제목 결정 = 그리는 선물의 종류 제목(순수 함수) · `show()` 가 그 함수를 그리는 선물로 부른다.
        #expect(CheckCakeGiftWindowController.title(presenting: noted.cakeGiftPresented) == DrinkGiftText.title)
        #expect(CheckCakeGiftWindowController.title(presenting: birthdayStore.cakeGiftPresented) == CakeGiftText.title)
        #expect(CheckCakeGiftWindowController.title(presenting: nil) == CheckCakeGiftWindowController.windowTitle)
        let window = V0351IfConfig.strippingComments(try V0374IsulMac3DTests.source("Sources/check/CheckCakeGiftWindow.swift"))
        let show = try V0366CakeMac3DTests.region(window, from: "func show(activating", to: "func close()")
        #expect(show.contains("window.title = Self.title(presenting: wiring?.store.cakeGiftPresented)"), "show() 가 그리는 선물로 제목을 안 정한다")
        #expect(show.components(separatedBy: "window.title =").count == 2, "show() 가 제목을 두 번 쓴다")
        scSave(inviteNote, "isul-window-invite-note.png")
        scSave(invitePlain, "isul-window-invite-plain.png")
        scSave(failed, "isul-window-invite-failed.png")
        scSave(received, "isul-window-received.png")
    }

    // MARK: ② 메뉴 팝오버 '다시 열기' 카드

    @Test("팝오버 '다시 열기' 카드: 술 선물은 술 한잔 문구 — 생일 카드와 높이는 같고 그림은 다르다 · 받으면 내려간다")
    func reopenCardSpeaksTheKind() throws {
        let plainStore = V0366CakeMacScreensTests.menuStore("isul-menu-plain")
        let plain = try #require(isBitmap(CheckMenuView(store: plainStore)))
        let drinkStore = V0366CakeMacScreensTests.menuStore("isul-menu-drink")
        drinkStore.cakeGiftOffer = scDrinkOffer(note: "오늘 한잔 어때?")
        #expect(drinkStore.showsCakeGiftCard && drinkStore.cakeGiftCardCopy.reopenTitle == DrinkGiftText.reopenTitle
                && drinkStore.cakeGiftCardCopy.reopenButton == DrinkGiftText.reopenButton)
        #expect(CharacterGiftKind.drink.reopenSymbolName != CharacterGiftKind.birthday.reopenSymbolName)
        #expect(CharacterGiftKind.birthday.reopenSymbolName == "gift.fill", "생일 카드 기호가 바뀌었다(0.3.66 그대로여야 한다)")
        let drink = try #require(isBitmap(CheckMenuView(store: drinkStore)))
        let birthdayStore = V0366CakeMacScreensTests.menuStore("isul-menu-birthday")
        birthdayStore.cakeGiftOffer = scBirthdayOffer
        #expect(birthdayStore.cakeGiftCardCopy == .birthday)
        let birthday = try #require(isBitmap(CheckMenuView(store: birthdayStore)))
        #expect(drink.pixelsHigh > plain.pixelsHigh, "술 선물이 있는데 카드가 안 섰다(\(drink.pixelsHigh) vs \(plain.pixelsHigh))")
        #expect(drink.pixelsHigh == birthday.pixelsHigh, "술 카드와 생일 카드의 높이가 다르다(한 줄 배너여야 한다)")
        #expect(scFingerprint(drink) != scFingerprint(birthday), "술 카드가 생일 카드와 같은 그림이다(종류 문구가 안 탔다)")
        #expect(V0317ShopTests.longestYellowRun(drink) < 24, "'못 그림' 상자")
        scSave(drink, "isul-menu-reopen-card.png")

        drinkStore.applyCakeGiftClaim(.received(characterID: scIsul, replayed: false), giftID: scDrinkOffer(note: nil).id)
        #expect(!drinkStore.showsCakeGiftCard)
        let after = try #require(isBitmap(CheckMenuView(store: drinkStore)))
        #expect(after.pixelsHigh == plain.pixelsHigh, "받았는데 카드가 남았다")
    }

    // MARK: ③ 상점 — 잠긴 칸 · 보유 칸 · 정책

    @Test("상점 패널: 이슬 잠긴 칸(안 가짐) · 보유 칸(가짐) · 잠긴 칸을 누른 바(술 한잔 안내) — 서로 다르고 칠해진다")
    func shopPanelScreens() throws {
        let width = CheckMenuView.contentColumnWidth
        let lockedStore = scShopStore(owned: [])
        let locked = try #require(isBitmap(CheckShopPanel(store: lockedStore, onBack: {}), width: width))
        let ownedStore = scShopStore(owned: [scIsul])
        let owned = try #require(isBitmap(CheckShopPanel(store: ownedStore, onBack: {}), width: width))
        let selectedStore = scShopStore(owned: [])
        selectedStore.selectShopItem(.character(scIsul))
        #expect(selectedStore.shopSelection == nil && selectedStore.shopNotice == DrinkGiftText.lockedHint)
        #expect(!ShopText.barShowsBuyButton(selection: selectedStore.shopSelection, notice: selectedStore.shopNotice))
        let selected = try #require(isBitmap(CheckShopPanel(store: selectedStore, onBack: {}), width: width))
        for (name, bitmap) in [("locked", locked), ("owned", owned), ("selected", selected)] {
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): '못 그림' 상자")
            #expect(scColorful(bitmap) > 1_200, "\(name): 카드가 빈 상자다")
        }
        #expect(Set([locked, owned, selected].map(scFingerprint)).count == 3, "잠긴 칸 · 보유 칸 · 안내 바 중 같은 그림이 있다")
        #expect(locked.pixelsHigh == selected.pixelsHigh, "잠긴 칸 안내가 하단 바 높이를 바꿨다")
        scSave(locked, "isul-shop-locked.png")
        scSave(owned, "isul-shop-owned.png")
        scSave(selected, "isul-shop-locked-selected.png")
    }

    @Test("잠긴 칸 정책 '가진 사람만': 안 가진 사람의 상점은 이슬 줄이 없는 상점과 같은 그림 · 가진 사람은 보유 칸 그대로")
    func ownersOnlyPolicyHidesTheLockedCell() throws {
        let width = CheckMenuView.contentColumnWidth
        let hidden = try #require(isBitmap(CheckShopPanel(store: scShopStore(owned: [], policy: .ownersOnly), onBack: {}), width: width))
        let without = try #require(isBitmap(CheckShopPanel(store: scShopStore(owned: [], includeIsul: false), onBack: {}), width: width))
        let everyone = try #require(isBitmap(CheckShopPanel(store: scShopStore(owned: []), onBack: {}), width: width))
        #expect(scFingerprint(hidden) == scFingerprint(without), "가진 사람만인데 안 가진 사람에게 이슬 칸이 섰다")
        #expect(scFingerprint(everyone) != scFingerprint(without), "전제: 모두에게 정책의 잠긴 칸이 그림에 안 잡힌다")
        let ownedHidden = try #require(isBitmap(CheckShopPanel(store: scShopStore(owned: [scIsul], policy: .ownersOnly), onBack: {}),
                                                width: width))
        let ownedEveryone = try #require(isBitmap(CheckShopPanel(store: scShopStore(owned: [scIsul]), onBack: {}), width: width))
        #expect(scFingerprint(ownedHidden) == scFingerprint(ownedEveryone), "가진 사람의 보유 칸이 정책에 흔들렸다")
        scSave(hidden, "isul-shop-owners-only.png")
    }
}
