import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 지역 아잉이 — 우리 센터 선물의 맥 **화면**(창 없이 — ImageRenderer): 받는 창(초대장 — 부산 · 서울 각각, 제목에 센터 이름) · 받은 뒤 ·
// 상점 잠긴 칸('센터 선물') · 보유 칸 · 잠긴 칸을 누른 바(센터 선물 안내). 틀은 이슬(V0374IsulMacScreensTests)과 같다.
// 증거 PNG: `CHECK_REGION_AING_EVIDENCE_DIR=<폴더>` 를 주면 떨군다(기본 실행은 안 쓴다).

private let rgBusan = CharacterCatalog.busanAingID
private let rgEvidenceDirectory = ProcessInfo.processInfo.environment["CHECK_REGION_AING_EVIDENCE_DIR"]

private func rgSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = rgEvidenceDirectory else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
}

/// ImageRenderer 로 굽는다(배율 명시 · 두 번 굽고 둘째 — 저장소 함정).
@MainActor
private func rgBitmap(_ view: some View, width: CGFloat? = nil) -> NSBitmapImageRep? {
    func once() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    _ = once()
    return once()
}

private func rgFingerprint(_ bitmap: NSBitmapImageRep) -> String {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

private func rgColorful(_ bitmap: NSBitmapImageRep) -> Int {
    V0317ShopTests.count(bitmap) { r, g, b in max(r, g, b) - min(r, g, b) > 40 }
}

private func rgOffer(_ id: String = rgBusan, note: String? = nil) -> CharacterGiftOffer {
    CharacterGiftOffer(id: id == rgBusan ? "5b2f0c3e-0000-4000-8000-0000000000b5" : "5b2f0c3e-0000-4000-8000-0000000000c5",
                       options: [id], note: note, createdAt: "2026-11-10T12:00:00+00:00", kind: .region)
}

@MainActor
private func rgShopStore(owned: Set<String>, function: String = #function, line: Int = #line) -> WorkTimerStore {
    let store = V0317ShopTests.plainStore(function: function, line: line)
    let rows = [ShopCharacterRow(id: "fox", price: 60, owned: owned.contains("fox"), gachaOnly: false, giftOnly: false),
                ShopCharacterRow(id: CharacterCatalog.goldAingID, price: 1000, owned: false, gachaOnly: true, giftOnly: false),
                ShopCharacterRow(id: rgBusan, price: 2005, owned: owned.contains(rgBusan), gachaOnly: true, giftOnly: true)]
    store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                           ultraBuyMax: 20, characters: rows))
    store.shopLoaded = true
    store.ownedCharacterIDs = owned.union([CharacterCatalog.builtInAingID])
    return store
}

@MainActor
@Suite("지역 아잉이 — 맥 화면", .serialized)
struct RegionAingScreensTests {
    @Test("받는 창(우리 센터 선물): 부산 · 서울 각각 초대장 · 받은 뒤 — 제목에 그 센터 이름(\"부산센터 선물 도착!\") · 초상이 칠해진다 · 고를 것 없이 [받기]",
          arguments: [(CharacterCatalog.busanAingID, "부산", "busan"), (CharacterCatalog.seoulAingID, "서울", "seoul")])
    func inviteWindow(_ characterID: String, _ center: String, _ tag: String) throws {
        let size = CakeGiftWindowLayout.contentSize
        func shot(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try #require(rgBitmap(CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height)))
        }
        let store = V0366CakeMacScreensTests.menuStore("region-window-\(tag)")
        let offer = rgOffer(characterID)
        store.cakeGiftOffer = offer
        store.openCakeGiftWindow()
        #expect(store.cakeGiftPresented?.kind == .region && store.cakeGiftChoice == characterID && store.canConfirmCakeGift,
                "지역 선물인데 고르기가 남았다")
        #expect(store.cakeGiftWindowCopy == .region(center: center) && store.cakeGiftCardCopy == .region(center: center))
        #expect(store.cakeGiftWindowCopy.title == "\(center)센터 선물 도착!")
        #expect(store.cakeGiftCardCopy.reopenTitle == "\(center)센터 선물이 기다려요")
        #expect(CheckCakeGiftWindowController.title(presenting: store.cakeGiftPresented) == "\(center)센터 선물 도착!")
        let invite = try shot(store)
        store.applyCakeGiftClaim(.received(characterID: characterID, replayed: false), giftID: offer.id)
        #expect(store.cakeGiftReceivedID == characterID && store.ownedCharacterIDs.contains(characterID))
        let received = try shot(store)
        #expect(rgFingerprint(invite) != rgFingerprint(received))
        for (name, bitmap) in [("invite", invite), ("received", received)] {
            #expect(rgColorful(bitmap) > 2_000, "\(name): 초상이 안 칠해졌다(\(rgColorful(bitmap)))")
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): ImageRenderer '못 그림' 상자가 있다")
        }
        rgSave(invite, "region-window-\(tag)-invite.png")
        rgSave(received, "region-window-\(tag)-received.png")
    }

    @Test("상점 패널: 부산 잠긴 칸(안 가짐 — '센터 선물') · 보유 칸 · 잠긴 칸을 누른 바(센터 선물 안내) — 서로 다르고 칠해진다")
    func shopPanel() throws {
        let width = CheckMenuView.contentColumnWidth
        let lockedStore = rgShopStore(owned: [])
        let locked = try #require(rgBitmap(CheckShopPanel(store: lockedStore, onBack: {}), width: width))
        let ownedStore = rgShopStore(owned: [rgBusan])
        let owned = try #require(rgBitmap(CheckShopPanel(store: ownedStore, onBack: {}), width: width))
        let selectedStore = rgShopStore(owned: [])
        selectedStore.selectShopItem(.character(rgBusan))
        #expect(selectedStore.shopSelection == nil && selectedStore.shopNotice == RegionGiftText.lockedHint)
        let selected = try #require(rgBitmap(CheckShopPanel(store: selectedStore, onBack: {}), width: width))
        for (name, bitmap) in [("locked", locked), ("owned", owned), ("selected", selected)] {
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): '못 그림' 상자")
            #expect(rgColorful(bitmap) > 1_200, "\(name): 카드가 빈 상자다")
        }
        #expect(Set([locked, owned, selected].map(rgFingerprint)).count == 3, "잠긴 칸 · 보유 칸 · 안내 바 중 같은 그림이 있다")
        rgSave(locked, "region-shop-locked.png")
        rgSave(owned, "region-shop-owned.png")
        rgSave(selected, "region-shop-locked-selected.png")
    }
}
