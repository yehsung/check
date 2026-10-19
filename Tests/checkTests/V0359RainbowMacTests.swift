import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.59 — 무지개 아잉이를 맥 앱 곳곳에 황금과 **같은 급**으로(사용자 2026-10-20: "캐릭터 추가해서 가챠에 추가해줘. 해당 캐릭터 확률은
// 2프로. 황금 아잉이를 3프로로 하향. 그리고 똑같이 20개 조각으로 살 수 있게.").
//
// 재는 것:
//  ① 코어 판정 — 결과 갈래(.rainbow) · 머리말 "무지개 아잉이!" · 확률표 줄(뽑기 전용 · 상점가 대신 "뽑기 또는 조각 20개" · 희귀 강조) ·
//     교환 목록(금 → 무지개 → 나머지) · 상점 구매 불가(서버 표식과 무관) · 기계 연출(황금과 같은 시간표 · 무지개 빛깔).
//  ② 맥 배선 — 초상 조회(메뉴바 · 카드 · 아바타 · 뽑기 결과가 아잉으로 접히지 않는다) · 아바타 자르기 · 고르기 목록 문(뽑기가 **그
//     캐릭터를** 낼 때만) · 잠긴 카드 → 뽑기 창 · 되돌림(unknown_character · not_owned) · 상점 카드.
//  ③ 화면 — 뽑기 패널 여덟 줄이 고정 높이 안 · 희귀 강조가 실제로 무지개빛 · p=2 소수 표 · 기계 공개 제목이 일곱 빛 · 뽑기 창 확률 판.
//  ④ 패키징 · 버전 — 대본 둘이 무지개 후광 칸 36장을 센다 · 0.3.59 / 112 · CHANGELOG 세 줄.
// 그림은 전부 화면 밖(ImageRenderer)이다. 미리보기 PNG 는 `CHECK_V0359_UI_STILLS_DIR` 가 있을 때만 쓴다.

// MARK: - 기준선 · 도우미

enum V0359RainbowBaseline {
    /// 맥 무지개 초상 두 장(메뉴바 · 카드 · 아바타가 쓰는 것)이 소스 트리에 있는가.
    static var macRainbowPortraitsInSourceTree: Bool {
        RainbowAingArt.portraitResourceNames.allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }
}

@MainActor
enum V0359UI {
    static let rainbow = CharacterCatalog.rainbowAingID
    static let gold = CharacterCatalog.goldAingID
    static let stillsDir = ProcessInfo.processInfo.environment["CHECK_V0359_UI_STILLS_DIR"]

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서비스 디코더와 같은 전략
        return decoder
    }

    /// 서버 흉내(`V0359RainbowStub`)가 그 번호에 주는 `gacha`.
    static func info(protocolVersion: Int, shards: Int = 3) -> GachaInfo? {
        guard let json = V0359RainbowStub.gachaJSON(protocolVersion: protocolVersion) else { return nil }
        var info = try? decoder().decode(GachaInfo.self, from: Data(json.utf8))
        info?.shards = shards
        return info
    }

    /// 서버처럼 여섯 장 + 황금(뽑기 전용 · 명목가 1000) + 번호 3 이면 무지개(같은 모양).
    static func shopRows(protocolVersion: Int, goldOwned: Bool = false, rainbowOwned: Bool = false) -> [ShopCharacterRow] {
        V0354GachaMacRenderTests.shopRows(goldOwned: goldOwned)
            + (protocolVersion >= 3 ? [ShopCharacterRow(id: rainbow, price: 1000, owned: rainbowOwned, gachaOnly: true)] : [])
    }

    /// 뽑기가 선 상점 스토어(세션 없음 — 네트워크 안 나감). `protocolVersion` 은 서버가 이 클라를 몇 번으로 봤는가(무지개 행 · 표 모양).
    static func store(protocolVersion: Int = 3, ruby: Int? = 120, shards: Int = 3, rainbowOwned: Bool = false,
                      function: String = #function, line: Int = #line) -> WorkTimerStore {
        let store = V0317ShopTests.plainStore(function: function, line: line)
        store.applyShopState(ShopStateResponse(rubyBalance: ruby, ultraBalance: 7, ultraPrice: 3, ultraBuyMax: 20,
                                               characters: shopRows(protocolVersion: protocolVersion, rainbowOwned: rainbowOwned)))
        store.rubyBalance = ruby
        store.gachaInfo = info(protocolVersion: protocolVersion, shards: shards)
        store.shopLoaded = true
        if rainbowOwned { store.ownedCharacterIDs.insert(rainbow) }
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 46, maxLength: 198))
        return store
    }

    static func result(_ id: String, duplicate: Bool) -> GachaPullResult {
        GachaPullResult(characterID: id, isDuplicate: duplicate, shardsGained: duplicate ? 1 : 0, shards: duplicate ? 4 : 3,
                        rubyBalance: 70, replayed: false)
    }

    static func save(_ rep: NSBitmapImageRep, _ name: String) {
        guard let stillsDir, let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(atPath: stillsDir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: stillsDir).appendingPathComponent(name))
    }

    static func save(_ image: CGImage, _ name: String) {
        save(NSBitmapImageRep(cgImage: image), name)
    }

    /// 2배로 그린 그림(배율 명시 — 기본값은 기계마다 갈린다).
    static func render(_ view: some View, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// 채도 · 밝기가 충분한 화소를 일곱 색상 칸(빨 · 주 · 노 · 초 · 파 · 남보 · 자홍)으로 센다. `rect` 는 그림 화소 좌표(위에서부터).
    static func hueCounts(_ image: CGImage, rect: CGRect? = nil, minSaturation: Double = 0.30, minValue: Double = 0.45) -> [Int] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return Array(repeating: 0, count: 7) }
        let box = (rect ?? CGRect(x: 0, y: 0, width: w, height: h)).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        var counts = Array(repeating: 0, count: 7)
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3]) / 255
                guard a > 0.5 else { continue }
                let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
                let mx = max(r, g, b), mn = min(r, g, b)
                guard mx >= minValue, mx > 0, (mx - mn) / mx >= minSaturation else { continue }
                var hue: Double
                if mx == r { hue = 60 * ((g - b) / (mx - mn)) } else if mx == g { hue = 60 * ((b - r) / (mx - mn) + 2) } else { hue = 60 * ((r - g) / (mx - mn) + 4) }
                if hue < 0 { hue += 360 }
                let bucket: Int
                switch hue {
                case 15..<40: bucket = 1
                case 40..<70: bucket = 2
                case 70..<170: bucket = 3
                case 170..<235: bucket = 4
                case 235..<290: bucket = 5
                case 290..<345: bucket = 6
                default: bucket = 0
                }
                counts[bucket] += 1
            }
        }
        return counts
    }

    /// 화소가 `minimum` 개 넘는 색상 칸 수.
    static func hueSpread(_ counts: [Int], minimum: Int = 6) -> Int {
        counts.filter { $0 >= minimum }.count
    }

    /// 채색 화소의 `share`(기본 2%) 넘게 차지하는 색상 칸 수 — 글자 그림자 · 테두리 같은 몇 줄 화소가 칸 수를 부풀리지 않게.
    static func dominantHues(_ counts: [Int], share: Double = 0.02) -> Int {
        let total = counts.reduce(0, +)
        guard total > 0 else { return 0 }
        return counts.filter { Double($0) >= share * Double(total) }.count
    }
}

// MARK: - ① 코어 판정

@MainActor
@Suite("v0.3.59 무지개 아잉이 — 뽑기 코어 판정")
struct V0359RainbowGachaRulesTests {
    @Test("결과 갈래: 무지개는 처음이든 중복이든 .rainbow · 머리말 '무지개 아잉이!' · 둘째 줄은 처음/조각 · 금 갈래는 그대로")
    func resultKindAndCopy() {
        let first = V0359UI.result(V0359UI.rainbow, duplicate: false)
        let again = V0359UI.result(V0359UI.rainbow, duplicate: true)
        #expect(first.kind == .rainbow && again.kind == .rainbow && first.isRainbow && !first.isGold)
        #expect(first.newlyOwnedID == V0359UI.rainbow && again.newlyOwnedID == nil)
        #expect(GachaText.rainbowHeadline == "무지개 아잉이!")
        #expect(GachaText.headline(for: first, name: "무지개 아잉이") == "무지개 아잉이!")
        #expect(GachaText.headline(for: again, name: "무지개 아잉이") == "무지개 아잉이!")
        #expect(GachaText.detail(for: first, name: "무지개 아잉이") == "새 캐릭터: 무지개 아잉이")
        #expect(GachaText.detail(for: again, name: "무지개 아잉이") == "이미 있는 무지개 아잉이 → 조각 +1")
        // 기준선: 금 · 평범한 캐릭터는 그대로다.
        #expect(V0359UI.result(V0359UI.gold, duplicate: false).kind == .gold)
        #expect(GachaText.headline(for: V0359UI.result(V0359UI.gold, duplicate: false), name: "황금 아잉이") == "황금 아잉이!")
        #expect(V0359UI.result("fox", duplicate: false).kind == .newCharacter)
        #expect(GachaText.detail(for: V0359UI.result("fox", duplicate: false), name: "여우") == nil)
        #expect(GachaText.rareHeadline(.newCharacter) == nil && GachaText.rareHeadline(.duplicate) == nil)
    }

    @Test("확률표(번호 3): 서버 순서 여덟 줄 · 무지개 2% · 황금 3% · 무지개는 뽑기 전용(상점가 대신 '뽑기 또는 조각 20개') · 강조는 .rainbow")
    func oddsRowsCarryTheRainbow() throws {
        let info = try #require(V0359UI.info(protocolVersion: 3))
        let rows = GachaRules.oddsRows(info: info, shopRows: V0359UI.shopRows(protocolVersion: 3)) { _ in nil }
        #expect(rows.map(\.characterID) == ["aing_gold", "aing_rainbow", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(rows.map(\.percentText) == ["3%", "2%", "24%", "24%", "14%", "14%", "11%", "8%"])
        let rainbow = try #require(rows.first { $0.characterID == V0359UI.rainbow })
        #expect(rainbow.name == "무지개 아잉이", "내장 이름으로 풀리지 않았다: \(rainbow.name)")
        #expect(rainbow.isGachaOnly && rainbow.shopPrice == nil && rainbow.priceText == "뽑기 또는 조각 20개")
        #expect(rainbow.shardCost == 20 && rainbow.isRainbow && !rainbow.isGold && rainbow.finish == .rainbow)
        #expect(rows.filter { $0.finish.isRare }.map(\.characterID) == [V0359UI.gold, V0359UI.rainbow])
        // 서버 표식이 빠지거나 false 로 와도(명목가 1000 그대로) 무지개는 루비 값으로 안 선다 — 금과 같은 규칙.
        let leaky = V0354GachaMacRenderTests.shopRows() + [ShopCharacterRow(id: V0359UI.rainbow, price: 1000, owned: false, gachaOnly: false)]
        let leakyRow = try #require(GachaRules.oddsRows(info: info, shopRows: leaky) { _ in nil }.first { $0.characterID == V0359UI.rainbow })
        #expect(leakyRow.isGachaOnly && leakyRow.shopPrice == nil && !leakyRow.priceText.contains("1000"))
    }

    @Test("확률표(번호 2 — 0.3.58 · 폰 1.0.9 가 받는 모양): 무지개 없음 · 소수 한 자리 3.1% · 24.5% … · 완전하다")
    func protocolTwoOddsRows() throws {
        let info = try #require(V0359UI.info(protocolVersion: 2))
        #expect(info.isUsable)
        let rows = GachaRules.oddsRows(info: info, shopRows: V0359UI.shopRows(protocolVersion: 2)) { _ in nil }
        #expect(!rows.contains { $0.characterID == V0359UI.rainbow })
        #expect(rows.map(\.percentText) == ["3.1%", "24.5%", "24.5%", "14.3%", "14.3%", "11.2%", "8.2%"])
    }

    @Test("교환 목록: 금 → 무지개 → 나머지(확률표 순서) — 서버가 무지개를 뒤에 · 금을 가운데 줘도 · 둘 다 20개 · 가지면 '보유'")
    func exchangeListPutsRareFirst() throws {
        let info = try #require(V0359UI.info(protocolVersion: 3, shards: 21))
        let rows = GachaRules.exchangeRows(info: info, ownedIDs: ["squirrel"]) { _ in nil }
        #expect(rows.map(\.characterID).prefix(2) == [V0359UI.gold, V0359UI.rainbow])
        #expect(rows.first { $0.characterID == V0359UI.rainbow }?.availability == .available(cost: 20))
        #expect(rows.count == 8, "교환 목록 \(rows.map(\.characterID))")
        // 서버 순서가 뒤섞여 와도.
        var shuffled = info
        shuffled.odds = [GachaOddsEntry(characterID: "fox", percent: 24), GachaOddsEntry(characterID: V0359UI.gold, percent: 3),
                         GachaOddsEntry(characterID: "squirrel", percent: 24), GachaOddsEntry(characterID: "shiba", percent: 14),
                         GachaOddsEntry(characterID: "ghost", percent: 14), GachaOddsEntry(characterID: "jellyfish", percent: 11),
                         GachaOddsEntry(characterID: "robot", percent: 8), GachaOddsEntry(characterID: V0359UI.rainbow, percent: 2)]
        let again = GachaRules.exchangeRows(info: shuffled, ownedIDs: [V0359UI.rainbow]) { _ in nil }
        #expect(again.map(\.characterID) == [V0359UI.gold, V0359UI.rainbow, "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(again[1].availability == .owned)
        // 번호 2 표엔 무지개가 없다 — 금만 맨 위.
        let two = GachaRules.exchangeRows(info: try #require(V0359UI.info(protocolVersion: 2)), ownedIDs: []) { _ in nil }
        #expect(two.first?.characterID == V0359UI.gold && !two.contains { $0.characterID == V0359UI.rainbow })
    }

    @Test("상점 구매 불가: 무지개 줄은 서버 표식 · 값과 무관하게 isPurchasable 거짓 · 내장 뽑기 전용 판정 한 곳(금 · 무지개만)")
    func rainbowIsNeverPurchasable() {
        for flag in [true, false, nil] as [Bool?] {
            #expect(!ShopCharacterRow(id: V0359UI.rainbow, price: 1000, owned: false, gachaOnly: flag).isPurchasable, "\(String(describing: flag))")
        }
        #expect(ShopCharacterRow(id: "fox", price: 60, owned: false, gachaOnly: false).isPurchasable, "기준선: 여우는 산다")
        #expect(CharacterCatalog.isGachaOnlyBuiltIn(V0359UI.rainbow) && CharacterCatalog.isGachaOnlyBuiltIn(V0359UI.gold))
        for other in ["aing", "fox", "robot", "AING_RAINBOW", " aing_rainbow", "", nil] as [String?] {
            #expect(!CharacterCatalog.isGachaOnlyBuiltIn(other), "\(other ?? "nil")")
        }
        #expect(CharacterCatalog.gachaOnlyBuiltInIDs == [V0359UI.gold, V0359UI.rainbow])
        #expect(CharacterManifest.Finish(characterID: V0359UI.rainbow) == .rainbow && CharacterManifest.Finish(characterID: nil) == .standard)
        #expect(CharacterManifest.Finish.rainbow.isRare && CharacterManifest.Finish.gold.isRare && !CharacterManifest.Finish.standard.isRare)
    }

    @Test("기계 결과: 무지개는 .rainbow(희귀) · 제목 '무지개 아잉이!' · 배지 없음 · 부제 · 읽어 줄 문장 · 시간표는 황금과 같다")
    func machineOutcomeAndTiming() {
        let first = GachaRevealOutcome(result: V0359UI.result(V0359UI.rainbow, duplicate: false), name: "무지개 아잉이", shardsBefore: 3)
        let again = GachaRevealOutcome(result: V0359UI.result(V0359UI.rainbow, duplicate: true), name: "무지개 아잉이", shardsBefore: 3)
        #expect(first.kind == .rainbow && first.kind.isRare && !first.isGoldDuplicate && !first.isRareDuplicate)
        #expect(again.isRareDuplicate && again.shardsGained == 1)
        #expect(GachaMachineText.title(first) == "무지개 아잉이!" && GachaMachineText.badge(first) == nil)
        #expect(GachaMachineText.goldSubtitle(first) == "아주 드문 친구를 만났어요")
        #expect(GachaMachineText.goldSubtitle(again) == "이미 있는 친구예요 · 조각 +1")
        #expect(GachaMachineText.announcement(first) == "무지개 아잉이! 아주 드문 친구를 만났어요")
        // 기준선: 금의 문장은 그대로다.
        let gold = GachaRevealOutcome(result: V0359UI.result(V0359UI.gold, duplicate: false), name: "황금 아잉이", shardsBefore: 3)
        #expect(GachaMachineText.announcement(gold) == "황금 아잉이! 아주 드문 친구를 만났어요")
        for reduced in [false, true] {
            #expect(GTiming.shardLandAt(again, reduced: reduced) == GTiming.shardLandAt(
                GachaRevealOutcome(characterID: V0359UI.gold, name: "", kind: .gold, shardCount: 4, shardsGained: 1), reduced: reduced))
        }
        #expect(GTiming.buttonsAt(.rainbow) == GTiming.buttonsAt(.gold) && GTiming.Reduced.buttonsAt(.rainbow) == GTiming.Reduced.buttonsAt(.gold))
        #expect(GTiming.revealOneShotEnd(.rainbow) == GTiming.revealOneShotEnd(.gold))
        #expect(GRare(.rainbow) == .rainbow && GRare(.gold) == .gold && GRare(.new) == nil && GRare(.duplicate) == nil)
    }
}

// MARK: - ② 기계(감독) — 무지개도 황금과 같은 희귀 판

@MainActor private final class RBClock {
    var now = Date(timeIntervalSinceReferenceDate: 830_000_000)
    func advance(_ s: Double) { now = now.addingTimeInterval(s) }
}

@MainActor private final class RBHaptics: GachaMachineHaptics {
    var events: [GachaMachineHapticEvent] = []
    func play(_ event: GachaMachineHapticEvent) { events.append(event) }
}

@MainActor private final class RBGate {
    private var pending: CheckedContinuation<GachaRevealOutcome, Error>?
    func pull() async throws -> GachaRevealOutcome { try await withCheckedThrowingContinuation { pending = $0 } }
    func succeed(_ outcome: GachaRevealOutcome) { pending?.resume(returning: outcome); pending = nil }
    var isWaiting: Bool { pending != nil }
}

/// 감독을 시계로 몰아 공개 직전(세 번째 톡)까지 데려간다. 초상은 맥 창이 쓰는 그 문(`CheckGachaWindowView.portrait`).
@MainActor
private func rbRevealDirector(_ outcome: GachaRevealOutcome, art: GachaMachineArt = .vector,
                              teaseChance: Double = 0) async -> (GachaMachineDirector, RBClock, RBHaptics) {
    let clock = RBClock(), haptics = RBHaptics(), gate = RBGate()
    let d = GachaMachineDirector(clock: { [clock] in clock.now })
    d.autoSchedule = false
    d.update(env: GachaMachineEnv(balance: 500, cost: 50, shards: 3, ruby: Image(systemName: "diamond.fill"),
                                  portrait: { CheckGachaWindowView.portrait($0) }, art: art, teaseChance: teaseChance,
                                  haptics: haptics, pull: { try await gate.pull() }, onAgain: {}, onClose: {},
                                  blockedReason: nil, againEnabled: true, isActive: true, reduceMotion: false, onFrame: nil))
    d.autoTurn()
    clock.advance(d.autoTurnDuration)
    d.advance(clock.now)
    for _ in 0..<50 where !gate.isWaiting { await Task.yield() }
    gate.succeed(outcome)
    await d.pullTask?.value
    if let ds = d.dropStart {
        clock.now = max(clock.now, ds.addingTimeInterval(d.drop.total + 0.01))
        d.advance(clock.now)
    }
    for _ in 0..<3 {
        d.press(clock.now)
        clock.advance(0.2)
    }
    return (d, clock, haptics)
}

@MainActor
@Suite("v0.3.59 무지개 아잉이 — 캡슐 기계")
struct V0359RainbowMachineTests {
    static let rainbow = GachaRevealOutcome(characterID: V0359UI.rainbow, name: "무지개 아잉이", kind: .rainbow, shardCount: 3)
    static let gold = GachaRevealOutcome(characterID: V0359UI.gold, name: "황금 아잉이", kind: .gold, shardCount: 3)
    static let fox = GachaRevealOutcome(characterID: "fox", name: "여우", kind: .new, shardCount: 3)

    static func stage(_ d: GachaMachineDirector, scheme: ColorScheme, now: Date, art: GachaMachineArt = .vector) -> CGImage? {
        guard let env = d.env else { return nil }
        let view = GachaMachineStage(d: d, env: env, theme: .of(scheme), sprites: GachaCapsuleSprites.shared(for: art), now: now)
            .environment(\.colorScheme, scheme)
        return V0359UI.render(view, scale: 2)
    }

    @Test("감독: 무지개는 희귀 판이다 — 늦게 떨어짐(.gold 시간표) · 모으기 · 빛깔 .rainbow · 금은 .gold · 여우는 평범")
    func directorTreatsRainbowAsRare() async throws {
        let (rd, _, _) = await rbRevealDirector(Self.rainbow)
        #expect(rd.isRare && !rd.isGold && rd.rare == .rainbow)
        #expect(rd.drop == GDropTimes.gold && rd.goldBuild == GTiming.goldBuild)
        let (gd, _, _) = await rbRevealDirector(Self.gold)
        #expect(gd.isRare && gd.isGold && gd.rare == .gold && gd.drop == GDropTimes.gold)
        let (fd, _, _) = await rbRevealDirector(Self.fox)
        #expect(!fd.isRare && fd.rare == nil && fd.drop == GDropTimes.normal && fd.goldBuild == 0)
    }

    @Test("공개 그림: 무지개 제목은 일곱 빛(주된 색상 칸 ≥ 5) · 황금 제목은 금빛 한 계열(≤ 2) — 밝은 · 어두운 외관 둘 다")
    func revealTitleIsRainbow() async throws {
        var spreads: [String: Int] = [:]
        for scheme in [ColorScheme.dark, .light] {
            let look = scheme == .dark ? "dark" : "light"
            for (label, outcome) in [("rainbow", Self.rainbow), ("gold", Self.gold)] {
                let (d, _, _) = await rbRevealDirector(outcome, art: .bundled)
                let burst = try #require(d.burstTime)
                let start = burst.addingTimeInterval(d.goldBuild)
                // 제목(무대 y≈306 — 2배 그림 612) 띠.
                let titleRect = CGRect(x: 60, y: 580, width: 640, height: 64)
                let settled = try #require(Self.stage(d, scheme: scheme, now: start.addingTimeInterval(3.0), art: .bundled))
                let counts = V0359UI.hueCounts(settled, rect: titleRect)
                spreads["\(label)-\(look)"] = V0359UI.dominantHues(counts)
                print("[v0359-machine] \(label) \(look) 제목 색상 칸 \(counts)")
                V0359UI.save(settled, "machine-\(label)-reveal-settled-\(look).png")
                for (tag, t) in [("burst", 0.18), ("title", 1.3)] {
                    if let frame = Self.stage(d, scheme: scheme, now: start.addingTimeInterval(t), art: .bundled) {
                        V0359UI.save(frame, "machine-\(label)-reveal-\(tag)-\(look).png")
                    }
                }
                // 톡톡 단계(세 번째 톡 직전 — 희귀 캡슐이 보인다).
                if let tap = Self.stage(d, scheme: scheme, now: burst.addingTimeInterval(-0.15), art: .bundled) {
                    V0359UI.save(tap, "machine-\(label)-tapping-\(look).png")
                }
            }
        }
        print("[v0359-machine] 제목 색상 칸 수 \(spreads.sorted { $0.key < $1.key })")
        #expect((spreads["rainbow-dark"] ?? 0) >= 5 && (spreads["rainbow-light"] ?? 0) >= 5, "무지개 제목이 일곱 빛이 아니다: \(spreads)")
        #expect((spreads["gold-dark"] ?? 9) <= 2 && (spreads["gold-light"] ?? 9) <= 2, "기준선: 금 제목이 여러 빛이다(잣대가 안 가른다): \(spreads)")
    }

    @Test("무지개 캡슐 그림: 구운 반쪽 둘이 금 · 평범한 캡슐과 다르고, 위(빨·주·노)와 아래(초·파·남보)가 다른 색 칸이다")
    func rainbowCapsuleSprites() throws {
        let sprites = GachaCapsuleSprites.shared(for: .bundled)
        func cg(_ image: Image) -> CGImage? { V0359UI.render(image.resizable().frame(width: 128, height: 128), scale: 1) }
        let top = try #require(cg(sprites.rainbowTop)), bottom = try #require(cg(sprites.rainbowBottom))
        let goldTop = try #require(cg(sprites.goldTop))
        let topCounts = V0359UI.hueCounts(top), bottomCounts = V0359UI.hueCounts(bottom), goldCounts = V0359UI.hueCounts(goldTop)
        print("[v0359-capsule] 위 \(topCounts) · 아래 \(bottomCounts) · 금 위 \(goldCounts)")
        // 위 반쪽: 빨 · 주 · 노 칸이 차고 파 · 남보는 거의 없다. 아래 반쪽은 그 반대.
        #expect(topCounts[0] + topCounts[1] + topCounts[2] > 3 * (topCounts[4] + topCounts[5] + 1), "위 반쪽 \(topCounts)")
        #expect(bottomCounts[3] + bottomCounts[4] + bottomCounts[5] > 3 * (bottomCounts[0] + bottomCounts[1] + 1), "아래 반쪽 \(bottomCounts)")
        #expect(V0359UI.hueSpread(goldCounts, minimum: 40) <= 2, "기준선: 금 캡슐이 여러 빛이다 \(goldCounts)")
        V0359UI.save(top, "capsule-rainbow-top.png")
        V0359UI.save(bottom, "capsule-rainbow-bottom.png")
    }
}

// MARK: - ③ 맥 배선 — 초상 · 아바타 · 고르기 · 되돌림

@MainActor
@Suite("v0.3.59 무지개 아잉이 — 맥 배선")
struct V0359RainbowMacTests {
    static let rainbow = V0359UI.rainbow

    static func pixels(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        px.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return px
    }

    @Test("초상 조회: 메뉴바 · 카드 · 뽑기 결과 · 남의 아바타가 무지개 초상 파일을 찾는다(아잉으로 접히지 않는다)")
    func portraitsResolveToRainbowFiles() throws {
        #expect(CheckMascotAssets.portraitURL(for: .neutral, characterID: Self.rainbow)?.lastPathComponent == "aing_rainbow-neutral.png")
        #expect(CheckMascotAssets.portraitURL(for: .negative, characterID: Self.rainbow)?.lastPathComponent == "aing_rainbow-negative.png")
        // 카탈로그에 없는 카탈로그(무지개 항목이 빠진 메모리 카탈로그)에서는 nil — 내장 항목이 있을 때만 준다(금과 같은 가드).
        #expect(CharacterCatalog(manifests: []).portraitURL(for: Self.rainbow, mood: .neutral) != nil, "내장 항목은 늘 있다")
        let aing = try #require(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.builtInAingID)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rainbow = try #require(CheckMascotAssets.image(for: .neutral, characterID: Self.rainbow)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(Self.pixels(aing) != Self.pixels(rainbow), "무지개 초상이 아잉 그림으로 접혔다")
        // 뽑기 결과 초상(창의 기계가 공개에 쓰는 문)도 무지개다.
        let machine = try #require(V0359UI.render(CheckGachaWindowView.portrait(Self.rainbow).resizable().frame(width: 96, height: 96), scale: 1))
        #expect(V0359UI.hueSpread(V0359UI.hueCounts(machine), minimum: 15) >= 4, "뽑기 결과 초상이 무지개빛이 아니다")
        // 카드 그림(고르기 · 상점 격자)도.
        let card = try #require(CharacterCardArt.image(characterID: Self.rainbow))
        let aingCard = try #require(CharacterCardArt.image(characterID: CharacterCatalog.builtInAingID))
        #expect(Self.pixels(card) != Self.pixels(aingCard))
    }

    @Test("아바타: 아는 캐릭터에 무지개 · 후광 초상이라 금처럼 몸 상자 + 8% 로 자른다(164×155) · 같은 인스턴스를 다시 준다")
    func avatarUsesBodyFramedRainbow() throws {
        #expect(AppUserAvatarArt.knownIDs.contains(Self.rainbow))
        let art = try #require(AppUserAvatarArt.portrait(characterID: Self.rainbow))
        #expect(art.width == 164 && art.height == 155, "무지개 아바타 \(art.width)×\(art.height)")
        let url = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: Self.rainbow))
        let raw = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let alphaBox = CharacterCardArt.tightened(raw)
        #expect(art.width < alphaBox.width && art.height < alphaBox.height, "기준선: 빛까지 조인 \(alphaBox.width)×\(alphaBox.height)")
        #expect(AppUserAvatarArt.portrait(characterID: Self.rainbow) === art)
        // 원 안에 그린 얼굴(26pt · 46pt)도 저장한다 — 미리보기.
        let ids = AppUserAvatarArt.knownIDs
        let row = HStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                VStack(spacing: 4) {
                    AppUserAvatarFace(avatar: .character(id), name: id, size: 46)
                    AppUserAvatarFace(avatar: .character(id), name: id, size: 26)
                }
            }
        }
        .padding(10)
        .background(CheckTheme.panel)
        let still = try #require(V0359UI.render(row, scale: 3))
        V0359UI.save(still, "avatars-all-characters.png")
    }

    @Test("고르기 목록 문: 무지개는 뽑기가 **그 캐릭터를** 낼 때(번호 3 표) · 가졌을 때 · 서버 행이 있을 때 · 로드 전에만 선다")
    func pickerListsRainbowOnlyWhenObtainable() {
        let three = V0359UI.store(protocolVersion: 3)
        #expect(three.gachaOffers(Self.rainbow) && three.isCharacterListed(Self.rainbow))
        // 번호 2 표(서버가 무지개를 안 냄) + 서버 목록에도 없음 → 안 선다. 금은 선다(기준선).
        let two = V0359UI.store(protocolVersion: 2)
        #expect(two.isGachaAvailable && !two.gachaOffers(Self.rainbow))
        #expect(!two.isCharacterListed(Self.rainbow) && two.isCharacterListed(V0359UI.gold))
        #expect(!two.characterPickerIDs.contains(Self.rainbow) && two.characterPickerIDs.contains(V0359UI.gold))
        // 가졌으면 선다(다른 기기에서 뽑은 사람).
        two.ownedCharacterIDs.insert(Self.rainbow)
        #expect(two.isCharacterListed(Self.rainbow))
        // 순수 본체: 로드 전 · 서버 행.
        #expect(WorkTimerStore.isCharacterListed(Self.rainbow, shopLoaded: false, gachaAvailable: false, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed(Self.rainbow, shopLoaded: true, gachaAvailable: false, owned: [],
                                                 rows: [ShopCharacterRow(id: Self.rainbow, price: 1000, owned: false, gachaOnly: true)]))
        #expect(!WorkTimerStore.isCharacterListed(Self.rainbow, shopLoaded: true, gachaAvailable: false, owned: [], rows: []))
        // 상점 자리표시 격자도 같은 규칙.
        let empty = V0317ShopTests.plainStore()
        empty.applyShopState(ShopStateResponse(rubyBalance: 120, characters: []))
        empty.shopLoaded = true
        #expect(!empty.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id).contains(Self.rainbow))
    }

    @Test("잠긴 무지개 카드: 뽑기가 무지개를 내면 뽑기 창 · 안 내면(번호 2 표) 상점 + 얻는 길 한 줄 · 여우는 상점만(기준선)")
    func lockedRainbowOpensTheGachaWindow() {
        let three = V0359UI.store(protocolVersion: 3)
        var shows = 0
        three.gachaWindowHooks = GachaWindowHooks(show: { shows += 1 }, close: {})
        three.openShopForLockedCharacter(Self.rainbow)
        #expect(shows == 1 && !three.isShopPanelVisible, "번호 3: 무지개 카드가 뽑기 창을 안 열었다")

        let two = V0359UI.store(protocolVersion: 2)
        var twoShows = 0
        two.gachaWindowHooks = GachaWindowHooks(show: { twoShows += 1 }, close: {})
        two.openShopForLockedCharacter(Self.rainbow)
        #expect(twoShows == 0 && two.isShopPanelVisible && two.shopNotice == GachaText.gachaOnlyHint,
                "번호 2: 무지개가 없는 뽑기 창을 열었다(\(twoShows)) · 안내 \(two.shopNotice ?? "nil")")
        two.closeShopPanel()
        two.openShopForLockedCharacter("fox")
        #expect(twoShows == 0 && two.isShopPanelVisible && two.shopNotice != GachaText.gachaOnlyHint)
    }

    @Test("상점: 무지개 카드를 고르면 [구매하기] 대신 뽑기 패널 · 억지로 골라도 안 산다 · 값은 어디에도 nil · 되돌림 안내는 뽑기 문구")
    func shopNeverSellsRainbow() {
        let store = V0359UI.store(protocolVersion: 3)
        store.isShopPanelVisible = true
        #expect(store.shopPrice(of: Self.rainbow) == nil, "자물쇠 배지 · 하단 바가 명목가 1000 을 말한다")
        #expect(WorkTimerStore.isGachaOnly(Self.rainbow, rows: []), "목록에 아직 없어도 무지개는 뽑기 전용")
        store.selectShopItem(.character(Self.rainbow))
        #expect(store.shopSelection == nil && store.isGachaPanelOpen)
        store.shopSelection = .character(Self.rainbow)
        store.confirmShopPurchase()
        #expect(store.shopNotice == GachaText.gachaOnlyHint && store.purchasingID == nil)
        #expect(WorkTimerStore.revertNotice(for: Self.rainbow, rows: []) == WorkTimerStore.gachaOnlyRevertNotice)
        #expect(store.gachaShardCost(of: Self.rainbow) == 20)
        #expect(GachaText.gachaOnlyPrice(shardCost: store.gachaShardCost(of: Self.rainbow)) == "뽑기 또는 조각 20개")
    }

    @Test("되돌림: 무지개를 모르는 서버(unknown_character)도 not_owned 처럼 아잉으로 되돌리고 얻는 길을 말한다")
    func unknownRainbowRevertsToAing() async throws {
        let (store, selection) = await V0354GoldPickerGateTests.push(Self.rainbow, reply: #"{"status":"unknown_character","id":"aing_rainbow"}"#,
                                                                     label: "unknown-rainbow")
        #expect(selection.selectedID == CharacterCatalog.builtInAingID, "옛 서버가 무지개를 모르는데 로컬은 무지개 그대로다")
        #expect(store.syncMessage.contains(GachaText.gachaOnlyHint), "안내 \(store.syncMessage)")
        let (notOwned, notOwnedSelection) = await V0354GoldPickerGateTests.push(Self.rainbow, reply: #"{"status":"not_owned","id":"aing_rainbow"}"#,
                                                                                label: "not-owned-rainbow")
        #expect(notOwnedSelection.selectedID == CharacterCatalog.builtInAingID)
        #expect(notOwned.syncMessage == WorkTimerStore.gachaOnlyRevertNotice)
    }

    @Test("뽑기 결과 → 기계 연출 값: 무지개는 .rainbow · 패널 한 줄 '방금 · 무지개 아잉이!'(중복이면 조각 줄)")
    func revealOutcomeAndPanelLine() throws {
        let result = V0359UI.result(Self.rainbow, duplicate: false)
        let outcome = try WorkTimerStore.revealOutcome(for: .answered(.pulled(result)), shardsBefore: 3) { _ in "무지개 아잉이" }
        #expect(outcome.kind == .rainbow && outcome.characterID == Self.rainbow)
        #expect(GachaPanelText.lastResult(result, name: "무지개 아잉이") == "방금 · 무지개 아잉이!")
        #expect(GachaPanelText.lastResult(V0359UI.result(Self.rainbow, duplicate: true), name: "무지개 아잉이")
                == "방금 · 이미 있는 무지개 아잉이 → 조각 +1")
        #expect(V0359UI.store().gachaDisplayName(Self.rainbow) == "무지개 아잉이")
    }
}

// MARK: - ④ 화면 — 뽑기 패널 · 상점 카드 · 뽑기 창 · 고르기

@MainActor
@Suite("v0.3.59 무지개 아잉이 — 화면")
struct V0359RainbowScreenTests {
    static let width = V0354GachaMacRenderTests.width - 24

    static func panel(_ store: WorkTimerStore, natural: Bool = false) -> some View {
        CheckGachaPanel(store: store, measuresNaturalHeight: natural).background(CheckTheme.panel)
    }

    static func panelImage(_ store: WorkTimerStore) throws -> CGImage {
        let rep = try #require(V0354GachaMacRenderTests.settledBitmap(Self.panel(store).frame(width: Self.width), width: Self.width))
        return try #require(rep.cgImage)
    }

    @Test("뽑기 패널: 번호 3(여덟 줄) · 번호 2(소수 일곱 줄) · 결과 · 교환 여덟 칸이 전부 고정 높이 안 — 무지개 줄은 무지개빛, 금 줄은 금빛")
    func panelFitsAndColoursTheRainbow() throws {
        var spreads: [String: [Int]] = [:]
        let cases: [(String, Int, GachaPanelMode, String?)] = [
            ("odds-p3", 3, .odds, nil), ("odds-p2-decimal", 2, .odds, nil), ("pull-p3", 3, .pull, nil),
            ("pull-result-rainbow", 3, .pull, V0359UI.rainbow), ("pull-result-fox", 3, .pull, "fox"),
            ("exchange-p3", 3, .exchange, nil),
        ]
        for (name, version, mode, resultID) in cases {
            let store = V0359UI.store(protocolVersion: version, shards: name == "exchange-p3" ? 21 : 3, function: #function + name)
            store.isShopPanelVisible = true
            store.openGachaPanel(mode: mode)
            if let resultID {
                store.gachaLastResult = V0359UI.result(resultID, duplicate: false)
                store.ownedCharacterIDs.insert(resultID)
            }
            let natural = try #require(V0317ShopTests.height(Self.panel(store, natural: true), width: Self.width))
            #expect(natural <= CheckGachaPanel.height + 0.5, "\(name): 내용 \(natural)pt 가 패널 \(CheckGachaPanel.height)pt 를 넘는다")
            let image = try Self.panelImage(store)
            #expect(abs(CGFloat(image.height) / 2 - CheckGachaPanel.height) < 1, "\(name): 높이 \(image.height / 2)")
            spreads[name] = V0359UI.hueCounts(image)
            V0359UI.save(image, "gacha-panel-\(name).png")
            if name == "odds-p3" || name == "pull-result-rainbow" || name == "exchange-p3" {
                let shop = try #require(V0354GachaMacRenderTests.settledBitmap(CheckShopPanel(store: store, onBack: {}),
                                                                             width: V0354GachaMacRenderTests.width))
                V0359UI.save(shop, "gacha-shop-\(name).png")
            }
        }
        print("[v0359-panel] 색상 칸 \(spreads.sorted { $0.key < $1.key })")
        // 확률표: 번호 3 표엔 무지개 줄이 있어 빨 · 초 · 파 칸이 번호 2 표(금 줄뿐)보다 확실히 많다.
        let p3 = try #require(spreads["odds-p3"]), p2 = try #require(spreads["odds-p2-decimal"])
        for bucket in [0, 3, 4] {
            #expect(p3[bucket] > p2[bucket] + 12, "확률표 칸 \(bucket): 번호 3 \(p3[bucket]) · 번호 2 \(p2[bucket]) — 무지개 줄이 무지개빛이 아니다")
        }
        // 결과 한 줄: 무지개면 그 줄이 무지개빛(여우 결과 = 흰 글자가 기준선).
        let rb = try #require(spreads["pull-result-rainbow"]), fx = try #require(spreads["pull-result-fox"])
        #expect(rb[3] + rb[4] + rb[0] > fx[3] + fx[4] + fx[0] + 30, "결과 한 줄이 무지개빛이 아니다: 무지개 \(rb) · 여우 \(fx)")
        // 확률표 줄 내용(무지개 줄 · 소수 표기).
        let three = V0359UI.store(protocolVersion: 3)
        let lines = CheckGachaPanel(store: three).oddsLines
        #expect(lines.map(\.name) == ["황금 아잉이", "무지개 아잉이", "여우", "다람쥐", "강아지", "유령", "해파리", "로봇"])
        #expect(lines[1].isRainbow && lines[1].percentText == "2%" && lines[1].priceText == "뽑기 또는 조각 20개")
        let two = CheckGachaPanel(store: V0359UI.store(protocolVersion: 2)).oddsLines
        #expect(two.map(\.percentText) == ["3.1%", "24.5%", "24.5%", "14.3%", "14.3%", "11.2%", "8.2%"])
        // 교환 여덟 칸: 금 → 무지개 맨 위.
        three.gachaInfo?.shards = 21
        #expect(CheckGachaPanel(store: three).exchangeLines.map(\.id).prefix(2) == [V0359UI.gold, V0359UI.rainbow])
    }

    @Test("상점 격자의 무지개 카드: 안 가졌으면 '뽑기 또는 조각 20개'(무지개빛) · 가지면 '보유' — 렌더에서 무지개빛이 갈린다")
    func shopCardRainbowCopy() throws {
        func shop(_ owned: Bool) throws -> CGImage {
            let store = V0359UI.store(protocolVersion: 3, rainbowOwned: owned, function: #function + "\(owned)")
            // 격자는 두 줄까지만 보이고(나머지는 스크롤) 희귀 둘은 셋째 줄이다 — 그림에 담으려고 맨 앞으로 옮긴다(서버 순서와 무관한 배치).
            let rows = V0359UI.shopRows(protocolVersion: 3, rainbowOwned: owned)
            let rare = rows.filter { CharacterCatalog.isGachaOnlyBuiltIn($0.id) }
            store.applyShopState(ShopStateResponse(rubyBalance: 120, ultraBalance: 7, ultraPrice: 3, ultraBuyMax: 20,
                                                   characters: rare + rows.filter { !rare.contains($0) },
                                                   gacha: V0359UI.info(protocolVersion: 3)))
            store.isShopPanelVisible = true
            let rep = try #require(V0354GachaMacRenderTests.settledBitmap(CheckShopPanel(store: store, clipsOverflowInsteadOfScroll: true, onBack: {}),
                                                                        width: V0354GachaMacRenderTests.width))
            return try #require(rep.cgImage)
        }
        let locked = try shop(false), owned = try shop(true)
        V0359UI.save(locked, "shop-rainbow-card-locked.png")
        V0359UI.save(owned, "shop-rainbow-card-owned.png")
        let a = V0359UI.hueCounts(locked), b = V0359UI.hueCounts(owned)
        print("[v0359-shop] 잠김 \(a) · 보유 \(b)")
        // 빨 · 초 칸(가진 카드의 테두리 강조색 = 파랑 계열이라 그 칸은 뺀다).
        #expect(a[0] + a[3] > b[0] + b[3] + 8, "무지개 카드 문구가 무지개빛이 아니다: 잠김 \(a) · 보유 \(b)")
    }

    @Test("뽑기 창 확률 판(밝은 · 어두운): 여덟 줄 · 무지개 줄이 무지개빛 — 번호 2 판(무지개 없음)과 색이 갈린다")
    func windowOddsSheet() throws {
        var counts: [String: [Int]] = [:]
        for scheme in [ColorScheme.light, .dark] {
            for version in [3, 2] {
                let store = V0359UI.store(protocolVersion: version, ruby: 420, function: #function + "\(scheme)\(version)")
                store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
                let state = GachaWindowState()
                state.showsOdds = true
                let view = CheckGachaWindowView(store: store, state: state, onClose: {})
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color.black : Color.white)
                let image = try #require(V0359UI.render(view, scale: 2))
                let look = scheme == .dark ? "dark" : "light"
                // 판 가운데 띠(판 폭 320 · 창 420 — 가운데 50…370, 2배).
                let sheet = CGRect(x: 100, y: 200, width: 640, height: 704)
                counts["p\(version)-\(look)"] = V0359UI.hueCounts(image, rect: sheet, minValue: 0.30)
                V0359UI.save(image, "gacha-window-odds-p\(version)-\(look).png")
            }
        }
        print("[v0359-window] 확률 판 색상 칸 \(counts.sorted { $0.key < $1.key })")
        for look in ["light", "dark"] {
            let three = try #require(counts["p3-\(look)"]), two = try #require(counts["p2-\(look)"])
            #expect(three[3] + three[4] + three[0] > two[3] + two[4] + two[0] + 20, "\(look): 무지개 줄이 무지개빛이 아니다 \(three) · \(two)")
        }
    }

    @Test("캐릭터 고르기: 무지개를 가졌으면 고를 수 있는 카드(체크) · 안 가졌고 뽑기가 내면 잠긴 카드 · 번호 2 표면 카드가 없다")
    func characterPanelStills() throws {
        func picker(_ store: WorkTimerStore, selected: String?, label: String) throws -> NSBitmapImageRep {
            store.isCharacterPanelVisible = true
            let defaults = V0317ShopTests.isolatedDefaults("v0359-picker-" + label)
            if let selected { defaults.set(selected, forKey: CharacterSelection.defaultsKey) }
            let view = CheckMenuView(store: store, previewClipsOverflowList: true, characterDefaults: defaults)
            return try #require(V0354GachaMacRenderTests.settledBitmap(view, width: CheckMenuView.mainWindowWidth))
        }
        func pickerStore(_ version: Int, owned: Bool, label: String) -> WorkTimerStore {
            let store = V0317ShopTests.teamStore(members: 2, service: V0317ShopTests.offlineService("v0359-picker-\(label)"),
                                                 function: #function + label)
            store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: V0359UI.shopRows(protocolVersion: version, rainbowOwned: owned),
                                                   gacha: V0359UI.info(protocolVersion: version)))
            store.shopLoaded = true
            if owned { store.ownedCharacterIDs.insert(V0359UI.rainbow) }
            return store
        }
        let ownedStore = pickerStore(3, owned: true, label: "owned")
        #expect(ownedStore.isCharacterUnlocked(V0359UI.rainbow) && ownedStore.characterPickerIDs.contains(V0359UI.rainbow))
        let owned = try picker(ownedStore, selected: V0359UI.rainbow, label: "owned")
        let lockedStore = pickerStore(3, owned: false, label: "locked")
        #expect(!lockedStore.isCharacterUnlocked(V0359UI.rainbow) && lockedStore.characterPickerIDs.contains(V0359UI.rainbow))
        #expect(lockedStore.shopPrice(of: V0359UI.rainbow) == nil, "잠긴 카드 배지가 명목가를 말한다")
        let locked = try picker(lockedStore, selected: nil, label: "locked")
        let twoStore = pickerStore(2, owned: false, label: "p2")
        #expect(!twoStore.characterPickerIDs.contains(V0359UI.rainbow))
        let two = try picker(twoStore, selected: nil, label: "p2")
        V0359UI.save(owned, "picker-rainbow-owned-selected.png")
        V0359UI.save(locked, "picker-rainbow-locked.png")
        V0359UI.save(two, "picker-protocol2-no-rainbow.png")
        // 그림 기준선: 무지개 카드가 선 고르기(잠김)는 무지개 카드가 없는 고르기(번호 2)와 다른 그림이다.
        #expect(V0354GoldPickerGateTests.differingPixels(locked, two) > 500)
    }
}

// MARK: - ⑤ 패키징 · 버전

@MainActor
@Suite("v0.3.59 무지개 아잉이 — 패키징 · 버전")
struct V0359RainbowPackagingTests {
    /// 대본에서 무지개 후광 칸 확인 조각(`RAINBOW_ART_DIR=` 줄부터 그 뒤 첫 고리의 `done` 까지)을 꺼낸다.
    static func snippet(_ script: String) -> String? {
        let lines = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        guard let start = lines.firstIndex(where: { $0.hasPrefix("RAINBOW_ART_DIR=") }),
              let loop = lines[start...].firstIndex(where: { $0.hasPrefix("for HALO_DEG in ") }),
              let end = lines[loop...].firstIndex(where: { $0 == "done" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    @Test("맥 패키징 대본 둘: 무지개 후광 칸 36장을 센다 — 다 있으면 지나가고 한 장 빠지면 멈춘다 · 금 칸만 있으면 멈춘다")
    func packagingChecksRainbowCells() throws {
        #expect(RainbowAingArt.haloCellResourceNames.count == 36)
        for script in ["scripts/build-local.sh", "scripts/package-mas.sh"] {
            let text = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(script), encoding: .utf8)
            let snippet = try #require(Self.snippet(text), "\(script): 무지개 후광 칸 확인 고리가 없다")
            let run = { (present: [String]) throws -> Int32 in try V0355GoldHaloYawTests.runSnippet(snippet, present: present) }
            #expect(try run(RainbowAingArt.haloCellResourceNames) == 0, "\(script): 36장이 다 있는데 멈춘다")
            for missing in [RainbowAingArt.haloResourceName, RainbowAingArt.haloResourceName(cell: 9), RainbowAingArt.haloResourceName(cell: 35)] {
                #expect(try run(RainbowAingArt.haloCellResourceNames.filter { $0 != missing }) != 0, "\(script): \(missing) 이 빠져도 지나간다")
            }
            #expect(try run(GoldAingArt.haloCellResourceNames) != 0, "\(script): 금 칸만 있는데 지나간다")
            // 금 고리는 그대로 남았다(금 조각이 무지개 고리를 삼키지 않는다).
            #expect(V0355GoldHaloYawTests.haloCheckSnippet(text)?.contains("aing_gold-halo") == true)
        }
        // 실제 소스 트리에 36장이 다 있다(번들 그림이 빠진 채 대본만 고친 게 아니다).
        for name in RainbowAingArt.haloCellResourceNames {
            #expect(V0354CoreArtBaseline.macResourceExists(name), "\(name).png 이 소스 트리에 없다")
        }
    }

    @Test("버전 0.3.59 / 112 · CHANGELOG 0.3.59 는 사용자 말투 세 줄(무지개 2% · 황금 3% · 조각 20개)")
    func versionAndChangelog() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.59</string>"))
        #expect(squashed.contains("<key>CFBundleVersion</key><string>112</string>"))
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.59\n") })
        let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(items.count == 3, "항목 \(items)")
        #expect(items.contains { $0.contains("무지개 아잉이") && $0.contains("2%") })
        #expect(items.contains { $0.contains("황금 아잉이") && $0.contains("3%") })
        #expect(items.contains { $0.contains("조각 20개") })
        // 첫 섹션이다(릴리스 스크립트가 맨 위 버전을 쓴다).
        #expect(changelog.range(of: "## 0.3.59")!.lowerBound < changelog.range(of: "## 0.3.58")!.lowerBound)
    }
}
