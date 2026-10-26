import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.66 — 케이크 아잉이 맥 **화면**: 상점 잠긴 칸 · 고르기 · 되돌림 · 아바타 눈금 · 메뉴 '다시 열기' 카드 · 축하 창.
// 재는 것은 화면이 부르는 판정의 **결과**다(상점 카드 = `ShopCardLine.of` · 상점 누르기 = `selectShopItem` · 고르기 잠긴 카드 =
// `openShopForLockedCharacter` · 아바타 = `AppUserAvatarArt.portrait` · 팝오버 = `CheckMenuView` 렌더 · 창 = `CheckCakeGiftWindowView` 렌더).
// 증거 PNG: `CHECK_V0366_MAC_EVIDENCE_DIR=<폴더>` 를 주면 떨군다(창 없음 — ImageRenderer).

private let scStrawberry = CharacterCatalog.cakeStrawberryAingID
private let scChoco = CharacterCatalog.cakeChocoAingID

/// 서버 순서 그대로의 상점 줄(값 · id 순 — 같은 값 2000 의 두 케이크가 초코 → 딸기로 온다).
private func scRows(owned: Set<String> = []) -> [ShopCharacterRow] {
    var rows: [ShopCharacterRow] = []
    for (id, price) in [("fox", 60), ("ghost", 60), ("jellyfish", 80), ("robot", 100), ("shiba", 60), ("squirrel", 60)] {
        rows.append(ShopCharacterRow(id: id, price: price, owned: owned.contains(id), gachaOnly: false, giftOnly: false))
    }
    rows.append(ShopCharacterRow(id: CharacterCatalog.goldAingID, price: 1000, owned: owned.contains(CharacterCatalog.goldAingID),
                                 gachaOnly: true, giftOnly: false))
    rows.append(ShopCharacterRow(id: CharacterCatalog.rainbowAingID, price: 1500, owned: owned.contains(CharacterCatalog.rainbowAingID),
                                 gachaOnly: true, giftOnly: false))
    rows.append(ShopCharacterRow(id: scChoco, price: 2000, owned: owned.contains(scChoco), gachaOnly: true, giftOnly: true))
    rows.append(ShopCharacterRow(id: scStrawberry, price: 2000, owned: owned.contains(scStrawberry), gachaOnly: true, giftOnly: true))
    return rows
}

@MainActor
private func scLoadedStore(owned: Set<String>, host: String? = nil, function: String = #function, line: Int = #line) -> WorkTimerStore {
    let store: WorkTimerStore
    if let host {
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            rpc == "character_gift_pending" ? .init(body: #"{"status":"ok"}"#) : nil
        }
        store = V0354GoldShopProtocolTests.store(host: host, label: host, function: function)
    } else {
        store = V0317ShopTests.plainStore(function: function, line: line)
    }
    store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                           ultraBuyMax: 20, characters: scRows(owned: owned)))
    store.shopLoaded = true
    return store
}

/// 번들 neutral 초상 원본(192²).
@MainActor
private func scNeutralPortrait(_ id: String) -> CGImage? {
    guard let url = CheckMascotAssets.portraitURL(for: .neutral, characterID: id),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// 증거 폴더(없으면 nil — 기본 실행은 안 쓴다).
private let scEvidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0366_MAC_EVIDENCE_DIR"]

private func scSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = scEvidenceDirectory else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
}

/// ImageRenderer 로 굽는다(배율 명시). **두 번 굽고 둘째를 쓴다** — 첫 장은 이미지 로드 전이라 다르게 나온다(저장소 함정).
@MainActor
private func scBitmap(_ view: some View, scale: CGFloat = 2) -> NSBitmapImageRep? {
    func once() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
    _ = once()
    return once()
}

private func scFingerprint(_ bitmap: NSBitmapImageRep) -> String {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
    return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined().prefix(16).description
}

/// 회색 팔레트 밖의 유채색 픽셀 수(그림이 실제로 칠해졌는가).
private func scColorful(_ bitmap: NSBitmapImageRep) -> Int {
    V0317ShopTests.count(bitmap) { r, g, b in max(r, g, b) - min(r, g, b) > 40 }
}

@MainActor
@Suite("v0.3.66 케이크 아잉이 — 맥 화면", .serialized)
struct V0366CakeMacScreensTests {
    // MARK: ① 상점 카드

    @Test("상점 카드 갈래: 안 가진 케이크 = 잠긴 칸(서버 표식이 없어도) · 가진 케이크 = 보통 보유 칸 · 금 = 뽑기 전용 · 여우 = 가격")
    func shopCardLines() {
        let rows = scRows(owned: [scChoco])
        #expect(ShopCardLine.of(id: scStrawberry, owned: false, rows: rows) == .giftLocked)
        #expect(ShopCardLine.of(id: scChoco, owned: true, rows: rows) == .price, "가진 케이크가 잠긴 칸이다")
        #expect(ShopCardLine.of(id: CharacterCatalog.goldAingID, owned: false, rows: rows) == .gachaOnly)
        #expect(ShopCardLine.of(id: CharacterCatalog.goldAingID, owned: true, rows: rows) == .gachaOnly, "가진 금은 '뽑기' 줄에 '보유'")
        #expect(ShopCardLine.of(id: "fox", owned: false, rows: rows) == .price)
        // 옛 서버 · 표식 없는 줄도 케이크 id 면 잠긴 칸(뽑기 전용으로 읽혀 '뽑기 또는 조각'을 말하지 않는다).
        let bare = [ShopCharacterRow(id: scStrawberry, price: 2000, owned: false)]
        #expect(ShopCardLine.of(id: scStrawberry, owned: false, rows: bare) == .giftLocked)
        #expect(ShopCardLine.of(id: scStrawberry, owned: false, rows: []) == .giftLocked)
        // 문구.
        let locked = ShopCardLine.giftLocked
        #expect(locked.tooltip(name: "딸기 케이크 아잉이", owned: false) == "딸기 케이크 아잉이 — \(CakeGiftText.lockedHint)")
        #expect(locked.accessibilityLabel(name: "딸기 케이크 아잉이", owned: false).contains(CakeGiftText.lockedCaption))
        #expect(!locked.tooltip(name: "딸기", owned: false).contains("사기") && !locked.tooltip(name: "딸기", owned: false).contains("뽑기 또는"))
        // 기존 문구는 글자 그대로(v0.3.54 의 삼항이 옮겨 왔다).
        #expect(ShopCardLine.price.tooltip(name: "여우", owned: false) == "여우 사기")
        #expect(ShopCardLine.price.tooltip(name: "여우", owned: true) == "여우 — 보유 중")
        #expect(ShopCardLine.gachaOnly.tooltip(name: "황금 아잉이", owned: false) == "황금 아잉이 — \(GachaText.gachaOnlyHint)")
        #expect(ShopCardLine.price.accessibilityLabel(name: "여우", owned: false) == "여우 사기")
        #expect(ShopCardLine.gachaOnly.accessibilityLabel(name: "황금 아잉이", owned: false) == "황금 아잉이, \(GachaText.gachaOnlyHint)")
        #expect(ShopCardLine.price.accessibilityLabel(name: "딸기", owned: true) == "딸기 보유 중")
    }

    @Test("상점 격자: 서버 순서(초코 → 딸기)를 딸기 → 초코로 바로 세운다 — 다른 줄은 한 칸도 안 옮긴다")
    func shopGridPutsStrawberryFirst() {
        let store = scLoadedStore(owned: [])
        let ids = store.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id)
        let server = scRows().map(\.id)
        #expect(server.suffix(2) == [scChoco, scStrawberry], "기준선: 서버 순서가 이미 딸기 먼저다 — 시험이 헛돈다")
        #expect(ids.suffix(2) == [scStrawberry, scChoco], "격자 끝 \(ids.suffix(2))")
        #expect(Array(ids.dropLast(2)) == Array(server.dropLast(2)), "다른 줄이 움직였다")
    }

    @Test("상점에서 잠긴 케이크를 누르면 고르지 않고 얻는 길만 말한다 · 사러 나가지 않는다 · 가진 케이크는 '이미 갖고 있어요'")
    func lockedCakeSpeaksTheWayAndNeverBuys() async throws {
        let host = "v0366-shop-locked-\(UUID().uuidString.lowercased().prefix(8))"
        let store = scLoadedStore(owned: [scChoco], host: host)
        store.selectShopItem(.character(scStrawberry))
        #expect(store.shopSelection == nil, "잠긴 칸이 골라졌다 — 하단 바에 [구매하기]가 선다")
        #expect(store.shopNotice == CakeGiftText.lockedHint)
        // 낡은 선택이 남아 있어도(다른 갈래로 골라 둔 뒤 목록이 바뀐 창) 하단 [구매하기]는 사러 나가지 않는다 — 구매로 가는 문은 이것 하나다(V0317).
        store.shopSelection = .character(scStrawberry)
        store.confirmShopPurchase()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(GomokuStubProtocol.count(host: host, rpc: "buy_character") == 0, "케이크를 사러 나갔다")
        #expect(store.shopNotice == CakeGiftText.lockedHint)
        // 가진 케이크.
        store.selectShopItem(.character(scChoco))
        #expect(store.shopNotice == WorkTimerStore.alreadyOwnedNotice)
        // 기준선: 여우는 골라진다(잠금이 모든 카드를 막는 게 아니다).
        store.selectShopItem(.character("fox"))
        #expect(store.shopSelection == .character("fox"))
    }

    // MARK: ② 고르기 · 되돌림

    @Test("고르기: 케이크는 가진 사람에게만 선다 · 잠긴 케이크 카드(다른 길로 닿아도)는 상점을 열고 '생일 선물' 을 말한다(뽑기 창 아님)")
    func pickerAndLockedCardRouteToTheGiftHint() async throws {
        let host = "v0366-picker-\(UUID().uuidString.lowercased().prefix(8))"
        let store = scLoadedStore(owned: [scStrawberry], host: host)
        store.ownedCharacterIDs = [scStrawberry]
        #expect(store.characterPickerIDs.contains(scStrawberry) && !store.characterPickerIDs.contains(scChoco),
                "고르기 \(store.characterPickerIDs)")
        var gachaOpened = 0
        store.gachaWindowHooks = GachaWindowHooks(show: { gachaOpened += 1 }, close: {})
        store.openShopForLockedCharacter(scChoco)
        #expect(store.isShopPanelVisible, "상점이 안 열렸다")
        #expect(store.shopNotice == CakeGiftText.lockedHint, "얻는 길이 \(store.shopNotice ?? "nil")")
        #expect(gachaOpened == 0, "케이크 잠긴 카드가 뽑기 창을 열었다")
        // 읽기 이름.
        #expect(CheckCharacterPanel.lockedLabel(scChoco, name: "초코 케이크 아잉이") == "초코 케이크 아잉이 잠김 — \(CakeGiftText.lockedHint)")
        #expect(CheckCharacterPanel.lockedLabel(CharacterCatalog.goldAingID, name: "황금 아잉이") == "황금 아잉이 잠김 — \(GachaText.gachaOnlyHint)")
        #expect(CheckCharacterPanel.lockedLabel("fox", name: "여우") == "여우 잠김 — 상점에서 사기")
    }

    @Test("고르기: 입고 있는 케이크 카드는 상점을 읽기 전 · 오프라인 · 낡은 보유에서도 선다(입고 있으면 가진 것이다) — 안 입은 케이크는 여전히 안 선다")
    func wornCakeStaysInThePickerBeforeTheShopLoads() throws {
        let store = V0317ShopTests.plainStore()
        store.characterDefaults = CheckTestScratch.defaults("v0366-worn-cake")
        // 시작 직후(상점 미로드 · 보유 = 아잉뿐) — 아무 케이크도 안 입었으면 둘 다 안 선다(기준선).
        #expect(!store.shopLoaded && store.ownedCharacterIDs == [CharacterCatalog.builtInAingID])
        #expect(!store.characterPickerIDs.contains(scStrawberry) && !store.characterPickerIDs.contains(scChoco), "기준선: 안 입은 케이크가 섰다")
        // 딸기를 입고 있다(다른 기기 · 지난 실행에서 받아 입었다).
        #expect(CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).select(scStrawberry))
        #expect(store.characterPickerIDs.contains(scStrawberry), "상점을 읽기 전에 입고 있는 케이크 카드가 숨었다 — \(store.characterPickerIDs)")
        #expect(!store.characterPickerIDs.contains(scChoco), "안 입은 초코까지 섰다(가진 사람에게만)")
        #expect(store.isCharacterUnlocked(scStrawberry), "로드 전에 입은 케이크가 잠겼다")
        // 착용 관용은 고르기 몫이다 — 상점 자리표시 격자(로드 전)에 입은 케이크가 잠긴 칸으로 서지 않는다.
        #expect(!store.shopGridRows(catalog: CheckCharacter3DScene.catalog).contains { $0.id == scStrawberry },
                "상점 자리표시 격자에 입은 케이크가 '생일 선물 전용' 잠긴 칸으로 섰다")
        // 오프라인(상점 읽기 실패).
        store.shopFailed = true
        #expect(store.characterPickerIDs.contains(scStrawberry), "오프라인에서 입고 있는 케이크 카드가 숨었다")
        // 상점은 읽었지만 이 맥의 보유가 낡았다(다른 기기에서 받아 입은 뒤 이 맥은 아직 모른다).
        store.shopFailed = false
        store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                               ultraBuyMax: 20, characters: scRows()))
        store.shopLoaded = true
        #expect(!store.ownedCharacterIDs.contains(scStrawberry), "전제: 보유가 딸기를 안다")
        #expect(store.characterPickerIDs.contains(scStrawberry), "입은 케이크 카드가 낡은 보유에 숨었다")
        // 다른 것으로 갈아입으면 가지지 않은 케이크는 다시 안 선다.
        #expect(CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).select("fox"))
        #expect(!store.characterPickerIDs.contains(scStrawberry), "안 입고 안 가진 케이크가 섰다")
        // 순수 문.
        #expect(WorkTimerStore.isCharacterListed(scChoco, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: scChoco))
        #expect(!WorkTimerStore.isCharacterListed(scChoco, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: scStrawberry))
    }

    @Test("되돌림: 케이크를 모르는 서버(unknown_character) · 안 가진 케이크(not_owned)는 아잉으로 되돌리고 얻는 길(생일 선물)을 말한다",
          arguments: ["unknown_character", "not_owned"])
    func revertSpeaksTheGiftWay(status: String) async throws {
        let (store, selection) = await V0354GoldPickerGateTests.push(scChoco, reply: #"{"status":"\#(status)","id":"aing_cake_choco"}"#,
                                                                     label: "v0366-\(status)")
        #expect(selection.selectedID == CharacterCatalog.builtInAingID, "\(status): 케이크가 그대로 남았다")
        #expect(store.syncMessage.contains(CakeGiftText.lockedHint), "\(status): 안내 \(store.syncMessage)")
        #expect(!store.syncMessage.contains(GachaText.gachaOnlyHint) && !store.syncMessage.contains("상점에서"), "\(status): 거짓 안내 \(store.syncMessage)")
        #expect(WorkTimerStore.revertNotice(for: scChoco, rows: []) == WorkTimerStore.giftOnlyRevertNotice)
    }

    // MARK: ③ 아바타

    @Test("아바타: 케이크는 장식을 빼고 몸 상자 + 8% 로 자른다 — 금 · 무지개와 같은 눈금(자른 크기 · 26pt 귀 폭) · 장식까지 조인 것보다 위가 짧다")
    func avatarFaceMatchesTheAingVariants() throws {
        let gold = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.goldAingID))
        /// 26pt 원에서의 **몸** 귀 폭(알파 > 250 — 금의 후광 · 케이크 가장자리 번짐을 빼고 같은 잣대로).
        func bodyEarWidth(_ id: String) throws -> Double {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let box = AppUserAvatarArt.portraitBox(diameter: 26, artSize: CGSize(width: art.width, height: art.height))
            let ext = V0336FaceScaleTests.rowExtents(art, alphaAbove: 250)
            let top = try #require(ext.prefix(max(1, ext.count / 2)).max())
            return Double(top) * Double(box.width) / Double(art.width)
        }
        let goldEar = try bodyEarWidth(CharacterCatalog.goldAingID)
        let aingEar = try bodyEarWidth(CharacterCatalog.builtInAingID)
        #expect(AppUserAvatarArt.framing(characterID: CharacterCatalog.goldAingID) == .bodyFramed)
        #expect(AppUserAvatarArt.framing(characterID: CharacterCatalog.builtInAingID) == .tight)
        for id in [scStrawberry, scChoco] {
            #expect(AppUserAvatarArt.framing(characterID: id) == .cakeBodyFramed)
            let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 아바타 그림이 없다")
            #expect(abs(art.width - gold.width) <= 3 && abs(art.height - gold.height) <= 3,
                    "\(id) 자른 크기 \(art.width)×\(art.height) ≠ 금 \(gold.width)×\(gold.height) — 얼굴 눈금이 갈린다")
            let ear = try bodyEarWidth(id)
            print(String(format: "[v0366-avatar] %@ 26pt 귀 폭 %.2f · 금 %.2f · 아잉 %.2f", id, ear, goldEar, aingEar))
            #expect(abs(ear - goldEar) < 0.6, "\(id) 26pt 얼굴 폭 \(ear) ≠ 금 \(goldEar)")
            // 기준선: 알파 상자(장식까지)로 조이면 위로 길어진다 — 이 차이가 없으면 장식을 몸으로 친 것이다.
            let raw = try #require(scNeutralPortrait(id), "\(id) 초상을 못 읽었다")
            let alphaBox = CharacterCardArt.tightened(raw)
            #expect(alphaBox.height > art.height + 5, "\(id) 장식까지 조인 높이 \(alphaBox.height) · 자른 높이 \(art.height)")
        }
        // 몸 비(`cakeBodyAspect`)의 근거: 같은 0.88 배율 금 초상의 몸 상자(알파 > 250).
        let goldRaw = try #require(scNeutralPortrait(CharacterCatalog.goldAingID))
        let body = try #require(CharacterCardArt.alphaBounds(goldRaw, threshold: 250))
        #expect(abs(body.height / body.width - CharacterCardArt.cakeBodyAspect) < 0.01, "금 몸 비 \(body.height / body.width)")
    }

    @Test("증거: 26pt 아바타 — 아잉 · 황금 · 무지개 · 딸기 · 초코 나란히(얼굴 크기가 같다)")
    func avatarRowEvidence() throws {
        let ids = [CharacterCatalog.builtInAingID, CharacterCatalog.goldAingID, CharacterCatalog.rainbowAingID, scStrawberry, scChoco]
        let row = HStack(spacing: 10) {
            ForEach(ids, id: \.self) { id in
                VStack(spacing: 4) {
                    AppUserAvatarFace(avatar: .character(id), name: "민수", size: 26)
                    AppUserAvatarFace(avatar: .character(id), name: "민수", size: 46)
                }
            }
        }
        .padding(10)
        .background(CheckTheme.panel)
        let bitmap = try #require(scBitmap(row, scale: 4))
        #expect(scColorful(bitmap) > 2_000, "아바타가 칠해지지 않았다")
        scSave(bitmap, "avatar-26pt-row.png")
    }

    // MARK: ④ 메뉴 '다시 열기' 카드

    /// 로그인 + 팀 확정 상태의 팝오버 스토어(배너 판정의 전제).
    static func menuStore(_ label: String, function: String = #function) -> WorkTimerStore {
        let store = WorkTimerStore(service: SupabaseWorkService(projectURL: URL(string: "http://v0366-menu-\(label)")!, anonKey: "anon-test-key",
                                                                session: GomokuStubProtocol.session()),
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("v0366-menu-" + label, function: function),
                                   tokenUsage: TokenUsageStore(defaults: CheckTestScratch.defaults("v0366-menu-tok-" + label, function: function),
                                                               homeDirectory: CheckTestScratch.directory("v0366-menu-" + label, function: function)
                                                                .appendingPathComponent("home", isDirectory: true),
                                                               cacheURL: CheckTestScratch.directory("v0366-menu-" + label, function: function)
                                                                .appendingPathComponent("cache.json", isDirectory: false)))
        store.isMenuPresented = true
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000e1")
        store.displayNow = Date(timeIntervalSince1970: 1_793_000_000)
        store.currentTeamID = "10000000-0000-0000-0000-000000000001"
        store.teamName = "아잉팀"
        store.teamMembers = (0..<4).map { i in
            TeamMemberStatus(id: "aaaaaaaa-0000-0000-0000-\(String(format: "%012d", i))", name: "멤버\(i)", status: .offWork,
                             updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
        }
        store.cakeGiftWindowHooks = CakeGiftWindowHooks(show: { _ in }, close: {}, isOpen: { false })
        return store
    }

    static let offer = CharacterGiftOffer(id: "6f1c2a7e-1d1f-4b0e-9a55-0c5d7f3b2a10", options: [scStrawberry, scChoco], note: nil,
                                          createdAt: "2026-10-26T07:51:40+00:00")

    @Test("팝오버: 열린 선물이 있으면 '다시 열기' 카드 한 줄이 선다 · 답장 배너엔 지고 새 버전 안내는 이긴다 · 받으면 내려간다")
    func reopenCardInThePopover() throws {
        let plainStore = Self.menuStore("plain")
        let plain = try #require(scBitmap(CheckMenuView(store: plainStore)))
        let giftStore = Self.menuStore("gift")
        giftStore.cakeGiftOffer = Self.offer
        let gift = try #require(scBitmap(CheckMenuView(store: giftStore)))
        #expect(gift.pixelsHigh > plain.pixelsHigh, "선물이 있는데 팝오버에 카드가 안 섰다(\(gift.pixelsHigh) vs \(plain.pixelsHigh))")
        scSave(gift, "menu-reopen-card.png")

        // 답장 배너가 이긴다(한 번에 하나) — 둘 다 세우면 답장만 그린 그림과 같다.
        let replyStore = Self.menuStore("reply")
        replyStore.showsFeedbackReplyBanner = true
        let reply = try #require(scBitmap(CheckMenuView(store: replyStore)))
        let bothStore = Self.menuStore("both")
        bothStore.showsFeedbackReplyBanner = true
        bothStore.cakeGiftOffer = Self.offer
        let both = try #require(scBitmap(CheckMenuView(store: bothStore)))
        #expect(scFingerprint(reply) != scFingerprint(gift), "전제: 답장 배너와 선물 카드가 같은 그림이다")
        #expect(scFingerprint(both) == scFingerprint(reply), "답장과 선물이 함께 그려졌거나 선물이 답장을 이겼다")

        // 새 버전 안내는 진다 — 선물이 그 자리를 가져간다.
        let updateStore = Self.menuStore("update")
        let update = try #require(scBitmap(CheckMenuView(store: updateStore, previewUpdateBanner: true)))
        let giftUpdateStore = Self.menuStore("gift-update")
        giftUpdateStore.cakeGiftOffer = Self.offer
        let giftUpdate = try #require(scBitmap(CheckMenuView(store: giftUpdateStore, previewUpdateBanner: true)))
        #expect(scFingerprint(update) != scFingerprint(gift), "전제: 업데이트 배너와 선물 카드가 같은 그림이다")
        #expect(scFingerprint(giftUpdate) == scFingerprint(gift), "새 버전 안내가 선물 카드를 밀어냈다")

        // 받으면(선물이 끝나면) 내려간다.
        giftStore.applyCakeGiftClaim(.received(characterID: scStrawberry, replayed: false), giftID: Self.offer.id)
        #expect(!giftStore.showsCakeGiftCard)
        let after = try #require(scBitmap(CheckMenuView(store: giftStore)))
        #expect(after.pixelsHigh == plain.pixelsHigh, "받았는데 카드가 남았다")
    }

    // MARK: ⑤ 축하 창 · 상점 패널 그림(증거 겸 — 결과가 서로 다르고 칠해졌는가)

    @Test("축하 창: 고르기(두 초상 크게) · 고른 뒤(확인 단추 켜짐) · 받은 뒤 — 세 화면이 서로 다르고 초상이 칠해진다")
    func giftWindowScreens() throws {
        let store = Self.menuStore("window")
        store.cakeGiftOffer = Self.offer
        store.openCakeGiftWindow()
        #expect(store.cakeGiftPresented == Self.offer)
        let size = CakeGiftWindowLayout.contentSize
        func shot() throws -> NSBitmapImageRep {
            try #require(scBitmap(CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height)))
        }
        let choosing = try shot()
        #expect(!store.canConfirmCakeGift)
        store.chooseCakeGift(scStrawberry)
        let picked = try shot()
        #expect(store.canConfirmCakeGift)
        store.cakeGiftNotice = CakeGiftText.claimFailed
        let failed = try shot()
        store.cakeGiftNotice = nil
        store.applyCakeGiftClaim(.received(characterID: scStrawberry, replayed: false), giftID: Self.offer.id)
        let received = try shot()
        let prints = [choosing, picked, failed, received].map(scFingerprint)
        #expect(Set(prints).count == 4, "축하 창 화면 넷 중 같은 그림이 있다 — \(prints)")
        for (name, bitmap) in [("choosing", choosing), ("picked", picked), ("received", received)] {
            #expect(scColorful(bitmap) > 4_000, "\(name): 초상이 안 칠해졌다(\(scColorful(bitmap)))")
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): ImageRenderer '못 그림' 상자가 있다")
        }
        scSave(choosing, "gift-window-choosing.png")
        scSave(picked, "gift-window-picked.png")
        scSave(failed, "gift-window-failed.png")
        scSave(received, "gift-window-received.png")
    }

    @Test("상점 패널: 잠긴 케이크 칸을 고르면 하단 바에 [구매하기] 가 서지 않고 얻는 길(lockedHint)을 말한다 — 여우를 고르면 [구매하기] 가 선다(기준선)")
    func lockedCakeBarHasNoBuyButton() throws {
        // 하단 바의 판정(뷰가 부르는 그 함수).
        #expect(!ShopText.barShowsBuyButton(selection: nil, notice: CakeGiftText.lockedHint))
        #expect(ShopText.barShowsBuyButton(selection: nil, notice: nil), "기준선: 아무것도 안 고른 바는 [구매하기] 자리를 지킨다")
        #expect(ShopText.barShowsBuyButton(selection: .character("fox"), notice: nil))

        func panel(_ select: String?) throws -> (WorkTimerStore, NSBitmapImageRep) {
            let store = scLoadedStore(owned: [])
            let keep: Set<String> = ["fox", CharacterCatalog.goldAingID, scChoco, scStrawberry]
            store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                                   ultraBuyMax: 20, characters: scRows().filter { keep.contains($0.id) }))
            store.ownedCharacterIDs = [CharacterCatalog.builtInAingID]
            if let select { store.selectShopItem(.character(select)) }
            let bitmap = try #require(V0317ShopTests.bitmap(CheckShopPanel(store: store, onBack: {}), width: CheckMenuView.contentColumnWidth))
            return (store, bitmap)
        }
        let (lockedStore, locked) = try panel(scStrawberry)
        #expect(lockedStore.shopSelection == nil && lockedStore.shopNotice == CakeGiftText.lockedHint, "전제: 잠긴 칸을 고른 상태가 아니다")
        let (_, idle) = try panel(nil)
        let (foxStore, fox) = try panel("fox")
        #expect(foxStore.shopSelection == .character("fox"))
        #expect(locked.pixelsHigh == idle.pixelsHigh, "잠긴 칸 안내가 하단 바 높이를 바꿨다(\(locked.pixelsHigh) vs \(idle.pixelsHigh))")
        // 하단 바 오른쪽 끝(단추 자리)에서 [구매하기] 캡슐의 테두리를 찾는다: 캡슐 위 · 아래 테두리는 바탕과 다른 색이 **가로로 길게 이어진**
        // 줄이다(흐린 단추도 1pt 테두리가 있다). 글자는 획마다 끊겨 그만큼 길게 이어지지 않는다 — 잠긴 칸 안내 두 줄이 그 자리까지 와도 단추로 안 읽힌다.
        func longestRun(_ bitmap: NSBitmapImageRep) -> Int {
            let scale = 2
            let barHeight = Int(CheckShopPanel.purchaseBarHeight) * scale
            let y1 = bitmap.pixelsHigh - 12 * scale, y0 = y1 - barHeight
            let x1 = bitmap.pixelsWide - 12 * scale - 10 * scale, x0 = x1 - 70 * scale
            guard let fill = bitmap.colorAt(x: x0, y: y0 + barHeight / 2)?.usingColorSpace(.deviceRGB) else { return -1 }
            var longest = 0
            for y in (y0 + 6)..<(y1 - 6) {
                var run = 0
                for x in x0..<x1 {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { run = 0; continue }
                    let d = abs(c.redComponent - fill.redComponent) + abs(c.greenComponent - fill.greenComponent) + abs(c.blueComponent - fill.blueComponent)
                    run = d > 0.03 ? run + 1 : 0
                    longest = max(longest, run)
                }
            }
            return longest
        }
        let idleRun = longestRun(idle), foxRun = longestRun(fox), lockedRun = longestRun(locked)
        print("[v0366-shop-bar] 단추 자리 가장 긴 가로 줄(px): 안 고름 \(idleRun) · 여우 \(foxRun) · 잠긴 케이크 \(lockedRun)")
        #expect(idleRun >= 60 && foxRun >= 60, "기준선: [구매하기] 캡슐 테두리가 안 잡힌다 — 시험이 헛돈다(\(idleRun) · \(foxRun))")
        #expect(lockedRun < 30, "잠긴 케이크를 골랐는데 하단 바에 [구매하기] 단추가 남았다(가로 줄 \(lockedRun)px)")
        #expect(scFingerprint(locked) != scFingerprint(idle), "잠긴 칸 안내가 하단 바에 안 섰다")
        #expect(V0317ShopTests.longestYellowRun(locked) < 24, "'못 그림' 상자")
        scSave(locked, "shop-panel-locked-selected.png")
    }

    @Test("상점 패널: 잠긴 케이크 칸(안 가짐) · 보유 칸(가짐) — 서로 다르고 카드가 칠해진다")
    func shopPanelScreens() throws {
        var shots: [String: NSBitmapImageRep] = [:]
        for (name, owned) in [("locked", Set<String>()), ("owned", Set([scStrawberry]))] {
            let store = scLoadedStore(owned: owned)
            // 격자 첫 줄에 케이크가 서게 줄을 줄인다(여우 · 금 · 초코 · 딸기 — 격자는 딸기 → 초코로 세운다). 열한 줄이면 케이크가
            // 넷째 줄이라 패널 높이 예산 밖(스크롤 아래)으로 나가 그림에 안 잡힌다.
            let keep: Set<String> = ["fox", CharacterCatalog.goldAingID, scChoco, scStrawberry]
            store.applyShopState(ShopStateResponse(rubyBalance: 3_000, ultraBalance: 7, ultraPrice: V0317ShopTests.realUltraPrice,
                                                   ultraBuyMax: 20, characters: scRows(owned: owned).filter { keep.contains($0.id) }))
            store.ownedCharacterIDs = owned
            let bitmap = try #require(V0317ShopTests.bitmap(CheckShopPanel(store: store, onBack: {}), width: CheckMenuView.contentColumnWidth))
            #expect(V0317ShopTests.longestYellowRun(bitmap) < 24, "\(name): '못 그림' 상자")
            #expect(scColorful(bitmap) > 1_200, "\(name): 카드가 빈 상자다")
            shots[name] = bitmap
            scSave(bitmap, "shop-panel-\(name).png")
        }
        let locked = try #require(shots["locked"]), owned = try #require(shots["owned"])
        #expect(scFingerprint(locked) != scFingerprint(owned), "잠긴 칸과 보유 칸이 같은 그림이다")
    }
}

// MARK: - 릴리스 게이트 (v0.3.66)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → … → 0.3.65 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.66 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
@Test("버전 0.3.66 / 119 · CHANGELOG 0.3.66 가 맨 위(케이크 아잉이 · 골라 받기 · 4줄 이하 · 배너 폭 안)")
func v0366VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.66</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>119</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.66\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0366] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "뽑기"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("케이크 아잉이") && $0.contains("생일") }, "케이크 아잉이 줄이 없다")
    #expect(items.contains { $0.contains("딸기") && $0.contains("초코") && $0.contains("골라") }, "골라 받기 줄이 없다")
    #expect(changelog.range(of: "## 0.3.66")!.lowerBound < changelog.range(of: "## 0.3.65")!.lowerBound,
            "0.3.66 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
