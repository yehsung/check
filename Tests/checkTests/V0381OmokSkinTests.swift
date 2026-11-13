import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 오목알 스킨(v0.3.81 — 대표 #d_UVBJ8vJua1jD 상점 루비 100 · #d_RR2dyBIHDMW5 상대에게도 보임 · #d_TFKnfZL40Ax6 6종).
// 다음 판: 대표 11-10 "네온 흑백 다이아 이렇게 3개 빼." → 주사위 · 고양이 · 픽셀(서버 20261111140000_omok_skins_trim).
//  ① 코어: 스킨 id = 서버 정의표 · 흑백 규칙(대표 "흑돌인지 백돌인지는 명확하게") — 일반 돌과 섞인 판의 밝기 대비 ≥ 4.5 ·
//     서버 선(상태 · 사기 · 끼기 · 대국 match.black_skin/white_skin) 해석.
//  ② 맥: 상점 칸 줄 · 문구(조사) · 스토어 사기 → 바로 낌 · 가진 칸 = 끼기 · 판 렌더(스킨이 그려진다).
// 증거 PNG: `CHECK_OMOK_SKIN_EVIDENCE_DIR=<폴더>` — 섞인 판 · 상점 칸.

/// 돌 하나를 실제 맥 판 반지름(칸 38.2pt × 0.46 · @2x)으로 그려 몸(반지름 0.92 안)의 평균 상대 휘도를 잰다(시안 도구와 같은 식).
private func omokMeanLuma(_ skin: OmokStoneSkin?, black: Bool) -> Double {
    let r: CGFloat = 38.2 * 0.46, scale: CGFloat = 2
    let side = Int(ceil(r * 2 * scale)) + 8
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(side)); ctx.scaleBy(x: scale, y: -scale)   // y 아래로(판과 같은 방향)
    let c = CGPoint(x: CGFloat(side) / scale / 2, y: CGFloat(side) / scale / 2)
    if let skin { skin.draw(in: ctx, center: c, radius: r, black: black, seed: 5) } else { OmokStoneArt.plain(ctx, c, r, black, 5) }
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    var sum = 0.0, n = 0.0
    for y in 0..<side { for x in 0..<side {
        let dx = (Double(x) + 0.5) / Double(scale) - Double(c.x), dy = (Double(y) + 0.5) / Double(scale) - Double(c.y)
        guard dx * dx + dy * dy < Double(r * r) * 0.85 else { continue }
        let i = (y * side + x) * 4
        guard Double(px[i + 3]) / 255 > 0.99 else { continue }
        sum += 0.2126 * lin(Double(px[i]) / 255) + 0.7152 * lin(Double(px[i + 1]) / 255) + 0.0722 * lin(Double(px[i + 2]) / 255)
        n += 1
    } }
    return n > 0 ? sum / n : -1
}

@Suite struct V0381OmokSkinCoreTests {
    @Test("스킨 id = 서버 정의표(omok_skin_defs) 순서 · 능력 번호 1 · 모르는 id 는 일반 돌")
    func ids() {
        #expect(OmokStoneSkin.allCases.map(\.rawValue) == ["dice", "cat", "pixel"])
        #expect(OmokStoneSkin.allCases.map(\.displayName) == ["주사위", "고양이", "픽셀"])
        #expect(OmokStoneSkin.protocolVersion == 1)
        #expect(OmokStoneSkin(wireValue: "dice") == .dice && OmokStoneSkin(wireValue: "Dice") == nil && OmokStoneSkin(wireValue: nil) == nil)
        // 내린 셋(0.3.81 에만 있던 id)은 모르는 id — 일반 돌로 접는다.
        #expect(["neon", "aing", "diamond"].allSatisfy { OmokStoneSkin(wireValue: $0) == nil })
        #expect(OmokStoneSkins(blackWire: "cat", whiteWire: "zzz") == OmokStoneSkins(black: .cat, white: nil))
        #expect(OmokStoneSkins(color: true, skin: .dice) == OmokStoneSkins(black: .dice) && OmokStoneSkins(color: false, skin: .dice) == OmokStoneSkins(white: .dice))
    }

    @Test("흑백 규칙: 스킨 흑은 짙고 백은 밝다 — 일반 돌과 섞인 판의 대비 ≥ 4.5(일반끼리 ≈ 7.9) · 스킨끼리도 ≥ 4.5")
    func blackStaysBlackWhiteStaysWhite() {
        let plainB = omokMeanLuma(nil, black: true), plainW = omokMeanLuma(nil, black: false)
        func ratio(_ light: Double, _ dark: Double) -> Double { (light + 0.05) / (dark + 0.05) }
        #expect(ratio(plainW, plainB) > 7)
        for skin in OmokStoneSkin.allCases {
            let b = omokMeanLuma(skin, black: true), w = omokMeanLuma(skin, black: false)
            print("[v0381 skin] \(skin.rawValue) 흑 \(String(format: "%.3f", b)) 백 \(String(format: "%.3f", w)) · 섞인 판 \(String(format: "%.1f", ratio(plainW, b))) / \(String(format: "%.1f", ratio(w, plainB)))")
            #expect(b >= 0 && w >= 0, "\(skin): 그림이 비었다")
            #expect(ratio(plainW, b) >= 4.5, "\(skin): 스킨 흑이 일반 백과 덜 갈린다")
            #expect(ratio(w, plainB) >= 4.5, "\(skin): 스킨 백이 일반 흑과 덜 갈린다")
            #expect(ratio(w, b) >= 4.5, "\(skin): 같은 스킨의 흑백이 덜 갈린다")
            for other in OmokStoneSkin.allCases where other != skin {
                #expect(ratio(omokMeanLuma(other, black: false), b) >= 4.5, "\(skin) 흑 vs \(other) 백")
            }
        }
    }

    @Test("서버 선: 상태 해석(모르는 id 버림 · 이름 없으면 번들 이름) · applying · 본문 키(null 포함) · 대국 칸 black_skin/white_skin")
    func wire() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"status":"ok","ruby_balance":150,"equipped":"cat","skins":[{"id":"cat","name":"고양이","price":100,"owned":true,"equipped":true},{"id":"dice","price":100,"owned":false,"equipped":false},{"id":"neon","name":"네온","price":100,"owned":false,"equipped":false}]}"#
        let state = try decoder.decode(OmokSkinsState.self, from: Data(json.utf8))
        #expect(state.isOK && state.rubyBalance == 150 && state.equipped == .cat)
        #expect(state.rows.map(\.skin) == [.cat, .dice] && state.rows[1].name == "주사위", "내린 id(neon)는 버린다")
        let bought = state.applying(owned: .dice, equipped: .dice, rubyBalance: 50)
        #expect(bought.equipped == .dice && bought.rubyBalance == 50)
        #expect(bought.rows.map(\.owned) == [true, true] && bought.rows.map(\.equipped) == [false, true])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        func text(_ v: some Encodable) throws -> String { String(decoding: try encoder.encode(v), as: UTF8.self) }
        #expect(try text(OmokSkinsStateRequest()) == #"{"p_protocol":1}"#)
        #expect(try text(OmokSkinBuyRequest(skin: .cat)) == #"{"p_protocol":1,"p_skin":"cat"}"#)
        #expect(try text(OmokSkinSetRequest(skin: nil)) == #"{"p_skin":null}"#)
        #expect(try text(OmokSkinSetRequest(skin: .pixel)) == #"{"p_skin":"pixel"}"#)
        let row = try decoder.decode(GomokuMatchRow.self, from: Data(#"{"id":"m","black_skin":"cat","white_skin":null}"#.utf8))
        #expect(OmokStoneSkins(blackWire: row.blackSkin, whiteWire: row.whiteSkin) == OmokStoneSkins(black: .cat))
        let gone = try decoder.decode(GomokuMatchRow.self, from: Data(#"{"id":"m","black_skin":"neon","white_skin":"diamond"}"#.utf8))
        #expect(OmokStoneSkins(blackWire: gone.blackSkin, whiteWire: gone.whiteSkin) == .plain, "내린 스킨은 일반 돌")
        let old = try decoder.decode(GomokuMatchRow.self, from: Data(#"{"id":"m"}"#.utf8))
        #expect(OmokStoneSkins(blackWire: old.blackSkin, whiteWire: old.whiteSkin) == .plain, "옛 서버는 일반 돌")
    }
}

@MainActor
@Suite struct V0381OmokSkinMacTests {
    @Test("상점 칸 줄: 착용 중 › 보유 › 값 · 문구 조사(으로/로 · 을/를)")
    func cardLineAndCopy() {
        #expect(OmokSkinCardLine.of(owned: true, equipped: true, price: 100) == .equipped)
        #expect(OmokSkinCardLine.of(owned: true, equipped: false, price: 100) == .owned)
        #expect(OmokSkinCardLine.of(owned: false, equipped: false, price: 100) == .price(100))
        #expect(OmokSkinShopText.equipped(.pixel) == "내 돌을 픽셀로 바꿨어요")
        #expect(OmokSkinShopText.equipped(.dice) == "내 돌을 주사위로 바꿨어요")
        #expect(OmokSkinShopText.equipped(.cat) == "내 돌을 고양이로 바꿨어요")
        #expect(OmokSkinShopText.equipped(nil) == "내 돌을 일반 돌로 바꿨어요")
        #expect(OmokSkinShopText.alreadyEquipped(.dice) == "이미 주사위를 쓰고 있어요")
        #expect(OmokSkinShopText.alreadyEquipped(.pixel) == "이미 픽셀을 쓰고 있어요")
        #expect(ShopText.barTitle(selection: .omokSkin(.cat), catalog: CharacterCatalog(manifests: [])) == "오목알 스킨 · 고양이")
    }
}

// MARK: - 스토어(스텁 서버)

private final class OmokSkinServer: @unchecked Sendable {
    private let lock = NSLock()
    private var ruby = 250
    private var owned: Set<String> = []
    private var equipped: String?

    func handle(_ rpc: String, _ body: String) -> GomokuStubProtocol.Reply? {
        lock.lock(); defer { lock.unlock() }
        let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        func state() -> String {
            let rows = OmokStoneSkin.allCases.map { s in
                #"{"id":"\#(s.rawValue)","price":100,"owned":\#(owned.contains(s.rawValue)),"equipped":\#(equipped == s.rawValue)}"#
            }.joined(separator: ",")
            return #"{"status":"ok","ruby_balance":\#(ruby),"equipped":\#(equipped.map { "\"\($0)\"" } ?? "null"),"skins":[\#(rows)]}"#
        }
        switch rpc {
        case "omok_skins_state": return .init(body: state())
        case "buy_omok_skin":
            let skin = args["p_skin"] as? String ?? ""
            if owned.contains(skin) { return .init(body: #"{"status":"already_owned","skin":"\#(skin)","ruby_balance":\#(ruby)}"#) }
            guard ruby >= 100 else { return .init(body: #"{"status":"insufficient","skin":"\#(skin)","need":100,"have":\#(ruby),"ruby_balance":\#(ruby)}"#) }
            ruby -= 100; owned.insert(skin); equipped = skin
            return .init(body: #"{"status":"ok","skin":"\#(skin)","price":100,"ruby_balance":\#(ruby),"equipped":"\#(skin)"}"#)
        case "set_omok_skin":
            let skin = args["p_skin"] as? String
            if let skin, !owned.contains(skin) { return .init(body: #"{"status":"not_owned","skin":"\#(skin)"}"#) }
            equipped = skin
            return .init(body: #"{"status":"ok","equipped":\#(skin.map { "\"\($0)\"" } ?? "null")}"#)
        default: return nil
        }
    }
}

@MainActor
private func omokStore(host: String, server: OmokSkinServer, function: String = #function) -> WorkTimerStore {
    GomokuStubProtocol.register(host: host) { rpc, body, _ in server.handle(rpc, body) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let scratch = CheckTestScratch.directory(host + "-token", function: function)
    let token = TokenUsageStore(defaults: CheckTestScratch.defaults(host + "-token", function: function),
                                homeDirectory: scratch.appendingPathComponent("home", isDirectory: true),
                                cacheURL: scratch.appendingPathComponent("cache.json", isDirectory: false))
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults(host, function: function), tokenUsage: token)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000a1")
    store.rubyBalance = 250
    V0354CoreStub.retain(store)
    return store
}

@MainActor
private func omokWait(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor
@Suite(.serialized) struct V0381OmokSkinStoreTests {
    @Test("상태 → 안 가진 칸 = 하단 바에 담김(값 100) → [구매하기] = 사기 · 바로 낌 · 잔량 150 · AI 판 내 돌 → 가진 칸 = 끼기 · 일반 돌 = 빼기")
    func buyThenEquip() async throws {
        let host = "v0381-omok-\(UUID().uuidString.lowercased().prefix(8))"
        let server = OmokSkinServer()
        let store = omokStore(host: host, server: server)
        await store.loadOmokSkins()?.value
        #expect(store.omokSkins?.rows.count == 3 && store.omokSkins?.equipped == nil)
        store.selectOmokSkin(.cat)
        #expect(store.shopSelection == .omokSkin(.cat) && store.shopSelectionPrice == 100 && store.canConfirmShopPurchase)
        #expect(GomokuStubProtocol.count(host: host, rpc: "buy_omok_skin") == 0, "카드 탭으로 사면 안 된다")
        store.confirmShopPurchase()
        await omokWait { store.purchasingID == nil && store.omokSkins?.equipped == .cat }
        #expect(store.omokSkins?.equipped == .cat && store.rubyBalance == 150 && store.shopSelection == nil)
        #expect(store.shopNotice == "샀어요! 이제 내 돌은 고양이")
        #expect(store.gomoku.aiStoneSkin == .cat, "AI 판의 내 돌이 낀 스킨을 따라가야 한다")
        // 가진 칸(고양이)을 다시 누르면 '이미 쓰는 중' · 일반 돌 칸은 빼기.
        store.selectOmokSkin(.cat)
        #expect(store.shopNotice == "이미 고양이를 쓰고 있어요" && GomokuStubProtocol.count(host: host, rpc: "set_omok_skin") == 0)
        await store.equipOmokSkin(nil)?.value
        #expect(store.omokSkins?.equipped == nil && store.gomoku.aiStoneSkin == nil && store.shopNotice == "내 돌을 일반 돌로 바꿨어요")
        let body = GomokuStubProtocol.calls(host: host, rpc: "set_omok_skin").last?.json
        #expect(body?.keys.sorted() == ["p_skin"] && body?["p_skin"] is NSNull)
        let buy = try #require(GomokuStubProtocol.calls(host: host, rpc: "buy_omok_skin").first?.json)
        #expect(buy["p_skin"] as? String == "cat" && buy["p_protocol"] as? Int == 1)
    }
}

// MARK: - 렌더(창 없음 — ImageRenderer)

@MainActor
@Suite(.serialized) struct V0381OmokSkinRenderTests {
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_OMOK_SKIN_EVIDENCE_DIR"]

    static func png(_ view: some View) throws -> Data {
        let bitmap = try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    static func board(_ skins: OmokStoneSkins) -> GomokuBoard {
        var board = GomokuBoard()
        let moves: [(Int, Int)] = [(7, 7), (8, 7), (8, 8), (6, 6), (9, 9), (10, 10), (7, 8), (6, 8), (7, 9), (7, 10), (8, 9), (6, 9)]
        for (i, m) in moves.enumerated() {
            if let p = GomokuPoint(x: m.0, y: m.1) { board[p] = i % 2 == 0 ? .black : .white }
        }
        _ = skins
        return board
    }

    @Test("판: 스킨을 넘기면 일반 판과 다른 그림 · 흑 고양이 + 백 일반(섞인 판) · 흑 일반 + 백 픽셀 증거")
    func boardRendersSkins() throws {
        let geometry = GomokuBoardGeometry(side: 304)
        func render(_ skins: OmokStoneSkins) throws -> Data {
            try Self.png(GomokuBoardView(board: Self.board(skins), geometry: geometry, lastMove: GomokuPoint(x: 6, y: 9),
                                         stoneSkins: skins).environment(\.colorScheme, .dark))
        }
        let plain = try render(.plain)
        let mixA = try render(OmokStoneSkins(black: .cat))
        let mixB = try render(OmokStoneSkins(white: .pixel))
        let both = try render(OmokStoneSkins(black: .dice, white: .cat))
        #expect(plain != mixA && plain != mixB && mixA != mixB && both != mixA)
        if let dir = Self.evidenceDirectory {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try plain.write(to: URL(fileURLWithPath: "\(dir)/board-plain.png"))
            try mixA.write(to: URL(fileURLWithPath: "\(dir)/board-cat-black.png"))
            try mixB.write(to: URL(fileURLWithPath: "\(dir)/board-pixel-white.png"))
            try both.write(to: URL(fileURLWithPath: "\(dir)/board-dice-vs-cat.png"))
        }
    }

    @Test("상점 칸 그림: 일반 돌 + 스킨 셋 — 서로 다른 그림")
    func previews() throws {
        let cells: [OmokStoneSkin?] = [nil] + OmokStoneSkin.allCases
        let images = try cells.map { try Self.png(OmokSkinPreview(skin: $0).frame(width: 80, height: 56)) }
        #expect(Set(images).count == images.count)
        if let dir = Self.evidenceDirectory {
            let strip = HStack(spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, skin in
                    VStack(spacing: 4) {
                        OmokSkinPreview(skin: skin).frame(width: 80, height: 56)
                        Text(OmokSkinShopText.name(skin)).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    }
                }
            }.padding(10).background(Color(white: 0.12))
            try Self.png(strip).write(to: URL(fileURLWithPath: "\(dir)/shop-skins.png"))
        }
    }
}

@MainActor
@Suite(.serialized) struct V0381OmokSkinPanelTests {
    @Test("상점: [캐릭터 | 오목알] 탭 — 오목알 탭도 같은 패널 높이 · 고른 칸에 하단 바 [구매하기] · 스킨 상점이 없는 서버면 탭 없음")
    func shopTabKeepsHeight() throws {
        func panel(_ tab: ShopTab, unavailable: Bool = false, pick: OmokStoneSkin? = nil) throws -> NSBitmapImageRep {
            let store = V0317ShopTests.plainStore()
            store.applyShopState(ShopStateResponse(rubyBalance: 250, ultraBalance: 1, ultraPrice: 3,
                                                   characters: V0317ShopTests.rows(ownedIDs: [], limit: 14)))
            store.shopLoaded = true
            store.applyOmokSkins(OmokSkinsState(rubyBalance: 250, equipped: .cat, rows: OmokStoneSkin.allCases.map {
                OmokSkinsState.Row(skin: $0, price: 100, owned: $0 == .cat || $0 == .pixel, equipped: $0 == .cat)
            }))
            store.omokSkinsUnavailable = unavailable
            store.shopTab = tab
            if let pick { store.selectOmokSkin(pick) }
            return try #require(V0317ShopTests.bitmap(CheckShopPanel(store: store, clipsOverflowInsteadOfScroll: true, onBack: {}).environment(\.colorScheme, .dark), width: 340))
        }
        let characters = try panel(.characters)
        let skins = try panel(.omokSkins, pick: .dice)
        let legacy = try panel(.characters, unavailable: true)
        let skinsNoPick = try panel(.omokSkins)
        let charsPick = try panel(.characters, pick: .dice)
        print("[v0381 shop] 오목알(고름 없음) \(skinsNoPick.pixelsHigh / 2) · 캐릭터 탭에서 스킨 고름 \(charsPick.pixelsHigh / 2)")
        print("[v0381 shop] 높이 캐릭터 \(characters.pixelsHigh / 2) · 오목알 \(skins.pixelsHigh / 2) · 탭 없음 \(legacy.pixelsHigh / 2)")
        #expect(characters.pixelsHigh == skins.pixelsHigh, "오목알 탭이 패널 높이를 흔든다")
        #expect(abs(characters.pixelsHigh - legacy.pixelsHigh) <= 2, "탭 머리가 예전 소제목보다 높다")
        if let dir = V0381OmokSkinRenderTests.evidenceDirectory {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try #require(skins.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(dir)/shop-panel-skins.png"))
            try #require(characters.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(dir)/shop-panel-characters.png"))
        }
    }
}
