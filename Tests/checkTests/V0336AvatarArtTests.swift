import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 프로필 캐릭터 그림·크롭(2026-09-21 사용자 요청 — 맥, 갈래 A).
//
// ① "크롭이 과하다" — 기준은 조영서 님이 직접 캡처해 올린 프로필 사진이다. 실측 **높이 = 원 지름의 1.018배 · 폭 0.80배**,
//    세로는 거의 가운데(위가 3.4% 잘리고 아래는 0.6% 남는다). 옛 값(정사각 1.20 · 아래로 +0.15)은 아래를 19~21% 잘라
//    발이 통째로 없어졌다(여섯 캐릭터 실측 — 전체 잘림 20~33%).
// ② "여기 나오는 기본 사진으로 해달라" — '캐릭터 고르기' 카드와 **같은 그림**(`CharacterCardArt`)을 프로필에도 쓴다.
// ③ "인상 쓰는 표정을 쓰지 마라" — 프로필로 읽히는 동그란 그림(팝오버 헤더 46pt 원)은 근무 여부와 무관하게 neutral.
//    **메뉴바 아이콘은 건드리지 않는다**(사용자 확인 전).
//
// 여기서 재는 것: 상자 계산(순수) · 그림 출처(같은 함수인가 · 아잉으로 접지 않는가) · 그려진 픽셀 · 소스 계약.

// MARK: - ① 상자 계산(순수 — 뷰 없이 값으로 검증한다)

@Suite("v0.3.36 아바타 상자 규칙(순수)")
struct V0336PortraitBoxTests {
    /// 여섯 캐릭터의 조인 그림 비(알파 상자 — 2026-09-21 실측, 아잉만 가로가 더 넓다).
    static let artSizes: [(id: String, size: CGSize)] = [
        ("fox", CGSize(width: 444, height: 512)),
        ("ghost", CGSize(width: 504, height: 512)),
        ("jellyfish", CGSize(width: 444, height: 512)),
        ("shiba", CGSize(width: 402, height: 512)),
        ("squirrel", CGSize(width: 373, height: 512)),
        ("aing", CGSize(width: 164, height: 154)),
    ]

    @Test func 높이를_지름에_맞추고_폭은_원본_비대로_따라간다() {
        // 세로가 긴 그림(시바 402×512)은 상한에 안 걸린다 — 높이가 1.03 지름, 폭은 비대로.
        let shiba = CGSize(width: 402, height: 512)
        for diameter in [16.0, 22.0, 26.0, 34.0, 64.0] as [CGFloat] {
            let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: shiba)
            #expect(abs(box.height - diameter * 1.03) < 1e-9, "\(diameter)pt 높이 \(box.height)")
            #expect(abs(box.width - diameter * 1.03 * (402.0 / 512.0)) < 1e-9)
            // 원본 비가 그대로 남는다(정사각 상자 + scaledToFit 으로 돌아가면 여기서 갈린다).
            #expect(abs(box.width / box.height - 402.0 / 512.0) < 1e-9)
            #expect(box.width <= diameter * AppUserAvatarArt.artMaxWidthFraction)
        }
    }

    @Test func 가로형은_상한에_걸려_폭을_고정하고_높이를_줄인다() {
        // 아잉(164×154 — 비 1.065)만 가로가 세로보다 넓다. 상한이 없으면 폭이 1.097 지름이 돼 팔이 좌우로 잘린다.
        let aing = CGSize(width: 164, height: 154)
        let diameter: CGFloat = 26
        let uncapped = diameter * AppUserAvatarArt.artHeightFraction * (164.0 / 154.0)
        #expect(uncapped > diameter * AppUserAvatarArt.artMaxWidthFraction, "상한에 안 걸리면 이 테스트는 무의미하다")

        let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: aing)
        #expect(abs(box.width - diameter * 1.02) < 1e-9, "폭 \(box.width)")
        #expect(abs(box.height - diameter * 1.02 * (154.0 / 164.0)) < 1e-9, "높이 \(box.height)")
        #expect(abs(box.width / box.height - 164.0 / 154.0) < 1e-9, "상한이 비를 망가뜨렸다")
        #expect(box.height < diameter * AppUserAvatarArt.artHeightFraction, "상한에 걸렸는데 높이가 안 줄었다")

        // 정사각(1:1)도 상한에 걸린다 — 1.03 폭이 상한 1.02 를 넘기 때문이다.
        let square = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: CGSize(width: 300, height: 300))
        #expect(abs(square.width - diameter * 1.02) < 1e-9 && abs(square.height - diameter * 1.02) < 1e-9)

        // 아주 납작한 그림(4:1)도 폭이 상한에서 멈춘다.
        let flat = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: CGSize(width: 400, height: 100))
        #expect(abs(flat.width - diameter * 1.02) < 1e-9)
        #expect(abs(flat.height - diameter * 1.02 / 4) < 1e-9)
    }

    @Test func 여섯_캐릭터_중_상한에_걸리는_것은_아잉뿐이다() {
        for (id, size) in Self.artSizes {
            let box = AppUserAvatarArt.portraitBox(diameter: 26, artSize: size)
            let capped = abs(box.height - 26 * AppUserAvatarArt.artHeightFraction) > 1e-9
            #expect(capped == (id == "aing"), "\(id) 가 상한에 \(capped ? "걸렸다" : "안 걸렸다")")
            // 어느 캐릭터든 원보다 크게 넘치지 않는다(레퍼런스는 1.018/0.80 이었다).
            #expect(box.height <= 26 * 1.03 + 1e-9 && box.width <= 26 * 1.02 + 1e-9)
        }
    }

    @Test func 세로_오프셋은_지름에_비례해_위로_올린다() {
        for diameter in [16.0, 26.0, 46.0, 64.0] as [CGFloat] {
            let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: CGSize(width: 402, height: 512))
            #expect(abs(box.offsetY - (-0.015 * diameter)) < 1e-9, "\(diameter)pt 오프셋 \(box.offsetY)")
            #expect(box.offsetY < 0, "아래로 내리면(옛 +0.15) 발이 잘린다")
        }
    }

    @Test func 지름에_선형이고_크기를_모르면_정사각으로_접는다() {
        let art = CGSize(width: 444, height: 512)
        let small = AppUserAvatarArt.portraitBox(diameter: 26, artSize: art)
        let big = AppUserAvatarArt.portraitBox(diameter: 52, artSize: art)
        #expect(abs(big.width - small.width * 2) < 1e-9 && abs(big.height - small.height * 2) < 1e-9)
        #expect(abs(big.offsetY - small.offsetY * 2) < 1e-9)

        // 크기를 모르는 그림(0·음수)은 정사각으로 접는다 — 0 크기 상자를 주면 그림이 통째로 사라진다.
        for broken in [CGSize.zero, CGSize(width: 0, height: 100), CGSize(width: -3, height: 5)] {
            let box = AppUserAvatarArt.portraitBox(diameter: 26, artSize: broken)
            #expect(box.width == 26 * AppUserAvatarArt.artHeightFraction && box.width == box.height, "\(broken)")
        }
        // 지름이 0 이어도 죽지 않는다(음수 지름은 0 으로).
        #expect(AppUserAvatarArt.portraitBox(diameter: 0, artSize: art).width == 0)
        #expect(AppUserAvatarArt.portraitBox(diameter: -10, artSize: .zero).width == 0)
    }
}

// MARK: - ② 그림 출처 — '캐릭터 고르기' 카드와 같은 함수

@MainActor
@Suite("v0.3.36 아바타 그림 출처")
struct V0336AvatarArtSourceTests {
    @Test func 프로필_그림은_카드_그림과_같은_함수의_같은_한_장이다() throws {
        for id in AppUserAvatarArt.knownIDs {
            let profile = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 프로필 그림이 없다")
            let card = try #require(CharacterCardArt.image(characterID: id), "\(id) 카드 그림이 없다")
            // 같은 캐시의 **같은 인스턴스**다 — 따로 디코드하면(옛 코드) 여기서 갈린다.
            #expect(profile === card, "\(id) 프로필과 카드가 다른 그림을 쓴다")
        }
    }

    @Test func 스프라이트는_아틀라스_전신이다_초상_PNG_로_되돌아가면_빨개진다() throws {
        let catalog = CheckCharacter3DScene.catalog
        let sprites = AppUserAvatarArt.knownIDs.filter { catalog.manifest(id: $0)?.kind == .sprite }
        #expect(sprites.count >= 4, "스프라이트가 \(sprites.count) 종뿐이다 — 기준선을 확인하라")
        for id in sprites {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let cell = CharacterCardArt.tightened(try #require(CharacterCardArt.frontIdleCell(characterID: id)))
            #expect(art.width == cell.width && art.height == cell.height,
                    "\(id) 가 아틀라스 셀(\(cell.width)×\(cell.height))이 아니라 \(art.width)×\(art.height) 다")
            // 초상 PNG 는 192² 캔버스다 — 되돌아가면 높이가 192 이하로 떨어진다.
            #expect(art.height > 400, "\(id) 높이 \(art.height) — 초상 PNG(얼굴 크롭)로 되돌아갔다")
        }
    }

    @Test func 모르는_캐릭터는_아잉으로_접지_않는다() throws {
        // ★ 이 가드가 **일하고 있다**는 증거: 카드 그림 함수는 모르는 id 를 아잉으로 접는다(내 캐릭터용 규칙).
        //   그대로 부르면 남의 아바타에 아잉이 선다 — 그래서 `knownIDs` 로 먼저 끊는다.
        let aing = try #require(CharacterCardArt.image(characterID: CharacterCatalog.builtInAingID))
        let folded = try #require(CharacterCardArt.image(characterID: "dragon"), "카드 그림이 모르는 id 에 nil 을 준다면 이 검사는 무의미하다")
        #expect(folded.width == aing.width && folded.height == aing.height, "카드 그림이 모르는 id 를 아잉으로 접지 않는다")

        #expect(AppUserAvatarArt.portrait(characterID: "dragon") == nil)
        #expect(AppUserAvatarArt.portrait(characterID: "") == nil)
        #expect(AppUserAvatarArt.portrait(characterID: "AING") == nil, "id 는 소문자 정규화된 값만 온다")
        for id in AppUserAvatarArt.knownIDs {
            #expect(AppUserAvatarArt.portrait(characterID: id) != nil, "\(id) 를 안다고 해 놓고 못 그린다")
        }
        // 아는 캐릭터 목록은 번들 카탈로그 그대로다(빈 원이 서지 않게 — V0335 와 같은 계약).
        #expect(Set(AppUserAvatarArt.knownIDs) == Set(CheckMascotAssets.catalog.allIDs))
    }
}

// MARK: - ③ 그려진 픽셀 — 상자 규칙이 실제로 화면에 닿는가

@MainActor
@Suite("v0.3.36 아바타 렌더")
struct V0336AvatarRenderTests {
    /// 잉크(받침색과 확연히 다른 픽셀)의 상자와 위 여백을 잰다. 테두리 링(흰 18%)이 섞이지 않게 **원 안쪽 3px 을 뺀다**.
    struct Ink {
        var width: Double
        var height: Double
        /// 가운데 세로 띠에서 원 위 호까지 남은 빈틈(지름 대비). 옛 값(+0.15 아래로)은 머리 위가 비어 여기가 컸다.
        var topGap: Double
    }

    static func ink(_ rep: NSBitmapImageRep, plate: NSColor) throws -> Ink {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let cx = Double(w) / 2, cy = Double(h) / 2, radius = Double(min(w, h)) / 2
        let (pr, pg, pb) = (plate.redComponent * 255, plate.greenComponent * 255, plate.blueComponent * 255)
        var minX = w, maxX = -1, minY = h, maxY = -1
        var bandTop = h
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                guard dx * dx + dy * dy <= (radius - 3) * (radius - 3),
                      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let delta = abs(c.redComponent * 255 - pr) + abs(c.greenComponent * 255 - pg) + abs(c.blueComponent * 255 - pb)
                guard delta > 60 else { continue }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if abs(dx) < radius * 0.3, y < bandTop { bandTop = y }
            }
        }
        guard maxX >= minX, maxY >= minY, bandTop < h else { throw V0336Error.render }
        let diameter = radius * 2
        return Ink(width: Double(maxX - minX + 1) / diameter,
                   height: Double(maxY - minY + 1) / diameter,
                   topGap: (Double(bandTop) - (cy - radius)) / diameter)
    }

    /// 받침 원만 구워 그 색을 읽는다(V0335 의 `coverage` 와 같은 방법).
    static func plateColor(size: CGFloat) throws -> NSColor {
        let plate = try V0335AvatarCharacterRenderTests.bitmap(
            Circle().fill(AppUserAvatarArt.backdrop).frame(width: size, height: size))
        guard let color = plate.colorAt(x: plate.pixelsWide / 2, y: plate.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
            throw V0336Error.render
        }
        return color
    }

    /// 2026-09-21 실측(64pt @2x · 세 캐릭터). 그려진 폭이 상자 규칙과 ±0.01 지름 안에서 맞고, 머리가 원 위 호까지 닿는다.
    /// 옛 값(정사각 1.20 + scaledToFit · 아래로 +0.15)은 폭이 여우 0.922 · 시바 0.938 · 다람쥐 0.875 였고
    /// 위 빈틈이 0.047~0.086 이었다 — 머리 위가 비고 발이 아래로 잘려 나간 그 모습이다.
    @Test func 그려진_폭이_상자_규칙과_같고_머리가_원_위까지_닿는다() throws {
        let size: CGFloat = 64
        let plate = try Self.plateColor(size: size)
        for id in ["fox", "shiba", "squirrel"] {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let box = AppUserAvatarArt.portraitBox(
                diameter: size, artSize: CGSize(width: art.width, height: art.height))
            let rep = try V0335AvatarCharacterRenderTests.bitmap(
                AppUserAvatarFace(avatar: .character(id), name: "민수", size: size))
            let ink = try Self.ink(rep, plate: plate)
            #expect(abs(ink.width - box.width / size) < 0.03,
                    "\(id) 그려진 폭 \(ink.width) · 상자 \(box.width / size) — 뷰가 상자 규칙을 안 쓴다")
            #expect(ink.topGap < 0.035, "\(id) 머리 위가 \(ink.topGap) 비었다 — 그림이 아래로 내려갔다")
            #expect(ink.height > 0.90, "\(id) 세로 \(ink.height) — 원을 못 채운다")
        }
    }

    /// 26pt 에서도 얼굴이 읽혀야 한다(V0335 의 커버리지 계약과 같은 자리 — 전신으로 바꾸면서 작아지지 않았는지).
    @Test func 작은_원에서도_캐릭터가_원을_채운다() throws {
        for id in AppUserAvatarArt.knownIDs {
            let rep = try V0335AvatarCharacterRenderTests.bitmap(
                AppUserAvatarFace(avatar: .character(id), name: "민수", size: 26))
            let coverage = try V0335AvatarCharacterRenderTests.coverage(rep, size: 26)
            #expect(coverage > 0.85, "\(id) 26pt 커버리지 \(coverage)")
        }
    }
}

// MARK: - ④ 헤더 46pt 원의 표정 — 언제나 neutral

@MainActor
@Suite("v0.3.36 헤더 원 표정")
struct V0336HeaderMoodTests {
    @Test func 근무_중이_아니어도_헤더_원은_웃는_얼굴이다() throws {
        // ⚠️ 기준선이 실제로 달라야 한다: 두 표정이 **다른 파일**이고 그림이 실제로 다른지부터 본다.
        let neutralURL = try #require(CheckMascotAssets.url(for: .neutral))
        let negativeURL = try #require(CheckMascotAssets.url(for: .negative))
        #expect(neutralURL != negativeURL)
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        let fixed = try V0335AvatarCharacterRenderTests.bitmap(
            CheckMascotView(snapshot: off, mood: .neutral).frame(width: 46, height: 46))
        let byStatus = try V0335AvatarCharacterRenderTests.bitmap(
            CheckMascotView(snapshot: off).frame(width: 46, height: 46))
        #expect(V0335AvatarCharacterRenderTests.meanDifference(fixed, byStatus) > 3,
                "근무 여부로 고른 얼굴과 neutral 이 같은 픽셀이다 — 이 비교로는 아무것도 못 가른다")
        // 박은 표정은 근무 중 얼굴과 같다(글로우만 다르다 — 얼굴이 있는 위쪽 60% 만 본다).
        let working = try V0335AvatarCharacterRenderTests.bitmap(
            CheckMascotView(snapshot: WorkStatusSnapshot(status: .working, elapsedSeconds: 60), mood: .neutral)
                .frame(width: 46, height: 46))
        #expect(V0336HeaderMoodTests.faceDifference(fixed, working) < V0336HeaderMoodTests.faceDifference(fixed, byStatus),
                "근무 중 아님(neutral 고정)의 얼굴이 근무 중 얼굴보다 시무룩한 얼굴에 가깝다")

        // 진짜 헤더(버튼)도 같은 얼굴이다 — 배선이 끊기면 여기서 잡힌다.
        let (store, _) = makeMessageReadStore("v0336-header")
        store.characterDefaults = GomokuTestDefaults.make("v0336-header-\(UUID().uuidString.prefix(6))")
        store.snapshot = off
        let header = try V0335AvatarCharacterRenderTests.bitmap(
            CharacterEntryButton(store: store, broadcast: CharacterSelectionBroadcast()))
        #expect(Self.faceDifference(header, fixed) < Self.faceDifference(header, byStatus),
                "헤더 원이 근무 여부를 따라 시무룩해진다")
    }

    /// 얼굴이 있는 위쪽 60% 만 비교한다(아래쪽은 헤더 버튼의 붓 배지가 있다).
    static func faceDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 255 }
        var total = 0.0, count = 0
        for y in 0..<(a.pixelsHigh * 3 / 5) {
            for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent)
                    + abs(p.blueComponent - q.blueComponent)
                count += 3
            }
        }
        return count == 0 ? 255 : total / Double(count) * 255
    }
}

// MARK: - ⑤ 소스 계약(주석을 걷어내고 본다)

@MainActor
@Suite("v0.3.36 소스 계약")
struct V0336AvatarSourceContractTests {
    @Test func 프로필_그림_출처는_카드_그림_함수_한_곳이다() throws {
        let sources = try V0325TooltipTests.strippedSources()
        let avatar = try #require(sources["CheckAvatarView.swift"])
        // 카드와 같은 함수 한 줄. 따로 디코드하던 옛 길(ImageIO)은 남아 있으면 안 된다.
        #expect(avatar.contains("return CharacterCardArt.image(characterID: characterID)"))
        #expect(!avatar.contains("CGImageSourceCreate"), "초상 PNG 를 따로 디코드하는 길이 남았다")
        // 모르는 캐릭터를 먼저 끊는 가드(없으면 카드 그림이 아잉으로 접어 남의 아바타에 아잉이 선다).
        #expect(avatar.contains("guard knownIDs.contains(characterID) else { return nil }"))

        // 뷰가 상자 규칙을 쓴다: 폭·높이를 직접 주고(정사각 + scaledToFit 이 아니다) 위로 올린다.
        let face = try #require(V0325TooltipTests.between(avatar, "struct CharacterAvatarFace: View {", "enum AppUserAvatarArt {"))
        #expect(face.contains("AppUserAvatarArt.portraitBox("))
        #expect(face.contains(".frame(width: box.width, height: box.height)"))
        #expect(face.contains(".offset(y: box.offsetY)"))
        #expect(!face.contains("scaledToFit"), "정사각 상자 + scaledToFit 으로 되돌아갔다")
        // 상수는 이름이 있고 값이 정해져 있다(레퍼런스 실측 1.018/0.80 · 잘림 5.4% 에서 고른 값).
        #expect(avatar.contains("static let artHeightFraction: CGFloat = 1.03"))
        #expect(avatar.contains("static let artMaxWidthFraction: CGFloat = 1.02"))
        #expect(avatar.contains("static let artOffsetFraction: CGFloat = -0.015"))
    }

    @Test func 헤더_46pt_원은_neutral_고정이고_메뉴바_표정_규칙은_그대로다() throws {
        let sources = try V0325TooltipTests.strippedSources()
        let panel = try #require(sources["CheckCharacterPanel.swift"])
        let entry = try #require(V0325TooltipTests.between(panel, "struct CharacterEntryButton: View {", ".buttonStyle(.plain)"))
        #expect(entry.contains("CheckMascotView(") && entry.contains("mood: .neutral"), "헤더 원이 표정을 안 박았다")

        // 마스코트 뷰: 안 주면 종전대로 근무 여부를 따른다(메뉴바와 같은 규칙).
        let mascot = try #require(sources["CheckMascotView.swift"])
        #expect(mascot.contains("CheckMascotAssets.image(for: mood ?? CheckMascotAssets.mood(for: snapshot))"))

        // 프로덕션에서 이 마스코트를 그리는 자리는 헤더 하나뿐이다 — 다른 자리가 생기면 표정 규칙을 다시 정해야 한다.
        let sites = sources.filter { $0.value.contains("CheckMascotView(") }.keys.sorted()
        #expect(sites == ["CheckCharacterPanel.swift"], "\(sites)")

        // ★ 메뉴바는 **그대로** 근무 여부를 따른다(사용자 확인 전까지 건드리지 않는다).
        #expect(try #require(sources["CheckMascotAssets.swift"]).contains("snapshot.isWorking ? .neutral : .negative"))
        #expect(try #require(sources["CheckMenuView.swift"]).contains("CheckMascotAssets.menuBarImage(for: snapshot)"))
    }
}

// MARK: - 증거 굽기(게이트)

/// 눈으로 볼 비교 시트를 굽는 도구다 — 검증이 아니다. 상시 스위트에서 돌면 테스트마다 PNG 수십 장을 쓴다.
/// **파일 스코프**에 둔다: `@MainActor` 스위트의 static 은 `@Test` trait 의 Sendable 클로저에서 못 읽는다.
///
///     CHECK_V0336_BAKE=/…/impl/after swift test --filter V0336AvatarArtBake
private let v0336BakeDir = ProcessInfo.processInfo.environment["CHECK_V0336_BAKE"]

@MainActor
@Suite("v0.3.36 아바타 그림 굽기(게이트)")
struct V0336AvatarArtBakeProbe {
    /// 비교 시트에 쓰는 크기. 16·22·26·34 는 실제 호출부 크기, 64 는 눈으로 볼 확대다.
    static let sizes: [CGFloat] = [16, 22, 26, 34, 64]

    @Test("아바타·헤더 렌더를 굽는다", .enabled(if: v0336BakeDir != nil))
    func bake() throws {
        let dir = try #require(v0336BakeDir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let ids = AppUserAvatarArt.knownIDs.sorted()
        #expect(ids.count == 6, "캐릭터가 \(ids.count) 종이다")

        for id in ids {
            // ① 원본 그림 한 장(알파 상자로 조인 것) — 파이썬이 이 알파로 폭·높이·잘린 비율을 잰다.
            let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 그림이 없다")
            try Self.writePNG(art, to: "\(dir)/art-\(id).png")
            // ② 원 안에 넣은 아바타(@2x).
            for size in Self.sizes {
                let view = AppUserAvatarFace(avatar: .character(id), name: "민수", size: size)
                try Self.writeView(view, to: "\(dir)/avatar-\(id)-\(Int(size))pt.png")
            }
        }

        // ③ 팝오버 헤더의 46pt 원 — '근무 중 아님'과 '근무 중'을 나란히. 표정이 갈리면 여기서 보인다.
        let (store, _) = makeMessageReadStore("v0336-bake")
        store.characterDefaults = GomokuTestDefaults.make("v0336-bake-\(UUID().uuidString.prefix(6))")
        for id in ["aing", "shiba"] {
            try CheckMascotAssets.$characterIDOverride.withValue(id) {
                store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
                try Self.writeView(CharacterEntryButton(store: store, broadcast: CharacterSelectionBroadcast()),
                                   to: "\(dir)/header-\(id)-offwork.png")
                store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
                try Self.writeView(CharacterEntryButton(store: store, broadcast: CharacterSelectionBroadcast()),
                                   to: "\(dir)/header-\(id)-working.png")
            }
        }
    }

    /// 뷰 한 장을 @2x 로 굽는다. 배경은 패널 단색 — 그라디언트면 같은 그림끼리도 배경이 달라진다(V0335 와 같은 규칙).
    static func writeView(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view.fixedSize().background(CheckTheme.panel))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { throw V0336Error.render }
        try png.write(to: URL(fileURLWithPath: path))
    }

    /// CGImage 한 장을 그대로(알파 유지) PNG 로 쓴다.
    static func writePNG(_ image: CGImage, to path: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw V0336Error.render }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

enum V0336Error: Error {
    case render
}
