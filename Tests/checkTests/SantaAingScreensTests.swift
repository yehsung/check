import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 산타 아잉이 — 크리스마스 선물의 맥 **화면**(창 없이 — ImageRenderer): 받는 창(초대장 — 고를 것 없이 [선물 열기]) · 받은 뒤 ·
// 상점 잠긴 칸('크리스마스 선물' — 모두에게) · 보유 칸 · 잠긴 칸을 누른 바(얻는 길 안내) · 메뉴 다시 열기 카드 문구. 틀은 지역 아잉이
// (RegionAingScreensTests)와 같다. 문구는 `SantaGiftText`(대표 #d_4wR1Qzn9OKmt "띵동! 산타 왔어요 🎁").
// 증거 PNG: `CHECK_SANTA_AING_EVIDENCE_DIR=<폴더>` 를 주면 떨군다(기본 실행은 안 쓴다).

private let stSanta = CharacterCatalog.santaAingID
private let stEvidenceDirectory = ProcessInfo.processInfo.environment["CHECK_SANTA_AING_EVIDENCE_DIR"]

private func stSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = stEvidenceDirectory else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
}

/// ImageRenderer 로 굽는다(배율 명시 · 두 번 굽고 둘째 — 저장소 함정).
@MainActor
private func stBitmap(_ view: some View, width: CGFloat? = nil) -> NSBitmapImageRep? {
    func once() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    _ = once()
    return once()
}

private func stFingerprint(_ bitmap: NSBitmapImageRep) -> String {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

private func stColorful(_ bitmap: NSBitmapImageRep) -> Int {
    V0317ShopTests.count(bitmap) { r, g, b in max(r, g, b) - min(r, g, b) > 40 }
}

private func stOffer(note: String? = nil) -> CharacterGiftOffer {
    CharacterGiftOffer(id: "5a17a000-0000-4000-8000-0000000000d1", options: [stSanta], note: note,
                       createdAt: "2026-12-24T00:00:00+00:00", kind: .santa)
}

@MainActor
private func stShopStore(owned: Set<String>, function: String = #function, line: Int = #line) -> WorkTimerStore {
    let store = V0317ShopTests.plainStore(function: function, line: line)
    let rows = [ShopCharacterRow(id: "fox", price: 60, owned: owned.contains("fox"), gachaOnly: false, giftOnly: false),
                ShopCharacterRow(id: CharacterCatalog.goldAingID, price: 1000, owned: false, gachaOnly: true, giftOnly: false),
                ShopCharacterRow(id: stSanta, price: 2007, owned: owned.contains(stSanta), gachaOnly: true, giftOnly: true)]
    store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                           ultraBuyMax: 20, characters: rows))
    store.shopLoaded = true
    store.ownedCharacterIDs = owned.union([CharacterCatalog.builtInAingID])
    return store
}

@MainActor
@Suite("산타 아잉이 — 맥 화면", .serialized)
struct SantaAingScreensTests {
    @Test("받는 창(크리스마스 선물): 초대장 → 받은 뒤 — 제목 · 카드 문구는 산타 묶음 · 초상이 칠해진다 · 고를 것 없이 [선물 열기] · 운영자 한 줄")
    func inviteWindow() throws {
        let size = CakeGiftWindowLayout.contentSize
        func shot(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
            try #require(stBitmap(CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height)))
        }
        let store = V0366CakeMacScreensTests.menuStore("santa-window")
        let offer = stOffer(note: "올해도 고생 많았어요")
        store.cakeGiftOffer = offer
        store.openCakeGiftWindow()
        #expect(store.cakeGiftPresented?.kind == .santa && store.cakeGiftChoice == stSanta && store.canConfirmCakeGift,
                "크리스마스 선물인데 고르기가 남았다")
        #expect(store.cakeGiftWindowCopy == .santa && store.cakeGiftCardCopy == .santa)
        #expect(store.cakeGiftWindowCopy.title == SantaGiftText.title && store.cakeGiftWindowCopy.confirmButton == SantaGiftText.confirmButton)
        #expect(store.cakeGiftCardCopy.reopenTitle == SantaGiftText.reopenTitle)
        #expect(CheckCakeGiftWindowController.title(presenting: store.cakeGiftPresented) == SantaGiftText.title)
        let invite = try shot(store)
        store.applyCakeGiftClaim(.received(characterID: stSanta, replayed: false), giftID: offer.id)
        #expect(store.cakeGiftReceivedID == stSanta && store.ownedCharacterIDs.contains(stSanta))
        let received = try shot(store)
        #expect(stFingerprint(invite) != stFingerprint(received))
        for (name, bitmap) in [("invite", invite), ("received", received)] {
            #expect(stColorful(bitmap) > 2_000, "\(name): 초상이 안 칠해졌다(\(stColorful(bitmap)))")
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): ImageRenderer '못 그림' 상자가 있다")
        }
        stSave(invite, "santa-window-invite.png")
        stSave(received, "santa-window-received.png")
    }

    @Test("수령 실패 줄: 산타 선물의 needs_update · 알 수 없음은 생일과 같은 글자(산타 묶음의 notice) · 선물은 열린 채")
    func claimFailureNotice() {
        let store = V0366CakeMacScreensTests.menuStore("santa-notice")
        let offer = stOffer()
        store.cakeGiftOffer = offer
        store.openCakeGiftWindow()
        store.applyCakeGiftClaim(.needsUpdate, giftID: offer.id)
        #expect(store.cakeGiftNotice == CakeGiftText.needsUpdate && store.cakeGiftOffer?.id == offer.id, "업데이트 필요인데 선물이 닫혔다")
        store.applyCakeGiftClaim(.failed(status: "weird"), giftID: offer.id)
        #expect(store.cakeGiftNotice == SantaGiftText.claimFailed)
    }

    @Test("상점 패널: 산타 잠긴 칸(안 가짐 — '크리스마스 선물' · 모두에게) · 보유 칸 · 잠긴 칸을 누른 바(얻는 길) — 서로 다르고 칠해진다")
    func shopPanel() throws {
        let width = CheckMenuView.contentColumnWidth
        let lockedStore = stShopStore(owned: [])
        #expect(lockedStore.shopGridRows(catalog: CheckMascotAssets.catalog).contains { $0.id == stSanta }, "안 가진 사람에게도 잠긴 칸이 서야 한다")
        let locked = try #require(stBitmap(CheckShopPanel(store: lockedStore, onBack: {}), width: width))
        let ownedStore = stShopStore(owned: [stSanta])
        let owned = try #require(stBitmap(CheckShopPanel(store: ownedStore, onBack: {}), width: width))
        let selectedStore = stShopStore(owned: [])
        selectedStore.selectShopItem(.character(stSanta))
        #expect(selectedStore.shopSelection == nil && selectedStore.shopNotice == SantaGiftText.lockedHint)
        let selected = try #require(stBitmap(CheckShopPanel(store: selectedStore, onBack: {}), width: width))
        for (name, bitmap) in [("locked", locked), ("owned", owned), ("selected", selected)] {
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): '못 그림' 상자")
            #expect(stColorful(bitmap) > 1_200, "\(name): 카드가 빈 상자다")
        }
        #expect(Set([locked, owned, selected].map(stFingerprint)).count == 3, "잠긴 칸 · 보유 칸 · 안내 바 중 같은 그림이 있다")
        stSave(locked, "santa-shop-locked.png")
        stSave(owned, "santa-shop-owned.png")
        stSave(selected, "santa-shop-locked-selected.png")
    }

    @Test("초상(아바타 · 카드): 번들 초상 두 장이 칠해지고(빨강 · 흰색 · 살구빛) 기본 ↔ 시무룩이 다르다")
    func portraits() throws {
        let neutral = try #require(CheckMascotAssets.image(for: .neutral, characterID: stSanta)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let negative = try #require(CheckMascotAssets.image(for: .negative, characterID: stSanta)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(neutral.width == 192 && neutral.height == 192 && negative.width == 192)
        let a = V0354GoldAingArtTests.rgba(neutral), b = V0354GoldAingArtTests.rgba(negative)
        var red = 0, white = 0, differ = 0
        for i in stride(from: 0, to: a.count, by: 4) where a[i + 3] > 250 {
            let r = Int(a[i]), g = Int(a[i + 1]), bl = Int(a[i + 2])
            if r > 170 && g < 80 && bl < 80 { red += 1 }
            if r > 225 && g > 225 && bl > 225 { white += 1 }
            if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 30 { differ += 1 }
        }
        print("[santa-aing] 초상 빨강 \(red) · 흰색 \(white) · 시무룩과 다른 화소 \(differ)")
        #expect(red > 1_200 && white > 2_000, "초상이 산타 빨강 · 흰 수염이 아니다(빨강 \(red) · 흰 \(white))")
        #expect(differ > 20, "기본과 시무룩이 거의 같다(\(differ))")
        let box = try #require(CharacterCardArt.alphaBounds(neutral))
        #expect(box.width == 165 && box.height == 173, "초상 알파 상자 \(box) — V0336 표와 맞춰라")
    }
}
