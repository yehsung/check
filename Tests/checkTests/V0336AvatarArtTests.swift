import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 프로필 캐릭터 그림·크롭(2026-09-21 사용자 요청 — 맥, 갈래 A).
//
// ① "크롭이 과하다" — 기준은 조영서 님이 **프로필 사진으로 올린 그림**이다(110×130 JPG). 사진 아바타는 `scaledToFill` +
//    원형 자르기라, 그 사진 좌표에서 원은 지름 110px(=사진 폭) · 중심 (55, 65) 이다. 그 원을 기준으로 실루엣 상자를 재면
//    x 14~101 · y 8~119 — **높이 112px = 1.018 지름 · 폭 88px = 0.800 지름**, 위 끝 −0.518 · 아래 끝 +0.500.
//    레퍼런스도 5.4% 가 잘린다(위 15% 행 28.5% · **아래 15% 행 20.9%**) — "발끝이 남는다"가 아니라
//    발 가장자리도 잘리되 통째로 사라지지는 않는다는 뜻이다. 옛 값(정사각 1.20 · 아래로 +0.15)은 여섯 다
//    **아래 15% 행이 100%** 잘렸다(전체 잘림 19.9~33.3%).
// ② "카드에 나오는 기본 그림으로 해달라" — **크롭(①)만으로 충족된다.** 카드 그림(아틀라스 `frontIdle` 셀)과 프로필이 쓰는
//    `portrait-neutral.png` 는 같은 그림의 해상도 차이다(조인 비 실측 0.005 안에서 일치 — 아래 계약이 그것을 잰다).
//    한때 출처를 `CharacterCardArt.image` 로 바꿨다가 **되돌렸다**. 비용은 아래 `V0336AvatarArtBakeProbe.cost` 가 잰다
//    (실측 3회: 첫 페인트 메인스레드 **203ms 대 23ms** · 아틀라스 상주 **21.5MB** · 조인 그림 4.3MB 대 0.7MB).
//    거기에 초상 디코드 실패 시 그 함수가 아잉으로 접어 **남의 얼굴에 아잉이 서는** 회귀까지 온다.
// ③ "인상 쓰는 표정을 쓰지 마라" — 프로필로 읽히는 동그란 그림(팝오버 헤더 46pt 원)은 근무 여부와 무관하게 neutral.
//    **메뉴바 아이콘은 건드리지 않는다**(사용자 확인 전) — 그것도 아래에서 픽셀로 잰다.
//
// 여기서 재는 것: 상자 계산(순수) · 그림 출처(되돌림이 풀렸는가 · 아잉으로 접지 않는가) · 캐릭터별 얼굴 크기 편차 ·
// 그려진 픽셀 · 소스 계약.

// MARK: - ① 상자 계산(순수 — 뷰 없이 값으로 검증한다)

@Suite("v0.3.36 아바타 상자 규칙(순수)")
struct V0336PortraitBoxTests {
    /// 여섯 캐릭터의 **조인 초상**(`portrait-neutral.png` 를 알파 상자로 조인 것 — 2026-09-21 실측, 아잉만 가로가 더 넓다).
    /// 번들을 안 읽는 순수 표다. 실제 그림과 갈리지 않는지는 `V0336FaceScaleTests.상자_표가_실제_그림과_맞다` 가 본다.
    static let artSizes: [(id: String, size: CGSize)] = [
        ("fox", CGSize(width: 167, height: 192)),
        ("ghost", CGSize(width: 189, height: 192)),
        ("jellyfish", CGSize(width: 167, height: 192)),
        ("shiba", CGSize(width: 151, height: 192)),
        ("squirrel", CGSize(width: 140, height: 192)),
        ("aing", CGSize(width: 164, height: 154)),
    ]

    @Test func 높이를_지름에_맞추고_폭은_원본_비대로_따라간다() {
        // 세로가 긴 그림(시바 151×192)은 상한에 안 걸린다 — 높이가 1.03 지름, 폭은 비대로.
        let shiba = CGSize(width: 151, height: 192)
        for diameter in [16.0, 22.0, 26.0, 34.0, 64.0] as [CGFloat] {
            let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: shiba)
            #expect(abs(box.height - diameter * 1.03) < 1e-9, "\(diameter)pt 높이 \(box.height)")
            #expect(abs(box.width - diameter * 1.03 * (151.0 / 192.0)) < 1e-9)
            // 원본 비가 그대로 남는다(정사각 상자 + scaledToFit 으로 돌아가면 여기서 갈린다).
            #expect(abs(box.width / box.height - 151.0 / 192.0) < 1e-9)
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
            let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: CGSize(width: 151, height: 192))
            #expect(abs(box.offsetY - (-0.015 * diameter)) < 1e-9, "\(diameter)pt 오프셋 \(box.offsetY)")
            #expect(box.offsetY < 0, "아래로 내리면(옛 +0.15) 발이 잘린다")
        }
    }

    @Test func 지름에_선형이고_크기를_모르면_정사각으로_접는다() {
        let art = CGSize(width: 167, height: 192)
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

// MARK: - ② 그림 출처 — neutral 초상 PNG 한 장(되돌림을 못 박는다)

@MainActor
@Suite("v0.3.36 아바타 그림 출처")
struct V0336AvatarArtSourceTests {
    @Test func 프로필_그림은_neutral_초상을_조인_것이고_캐릭터당_한_장이다() throws {
        for id in AppUserAvatarArt.knownIDs {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 프로필 그림이 없다")
            let url = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: id))
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let raw = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(raw.width == 192 && raw.height == 192, "\(id) 초상 캔버스가 192² 가 아니다(\(raw.width)×\(raw.height))")
            let tight = CharacterCardArt.tightened(raw)
            #expect(art.width == tight.width && art.height == tight.height,
                    "\(id) 프로필이 \(art.width)×\(art.height) 인데 조인 초상은 \(tight.width)×\(tight.height) 다")
            // 캐릭터당 한 번만 디코드·조인한다 — 두 번째 조회는 같은 인스턴스다(행은 hover·갱신마다 다시 그려진다).
            #expect(AppUserAvatarArt.portrait(characterID: id) === art, "\(id) 가 매번 다시 디코드된다")
        }
    }

    /// **출처를 카드 그림으로 바꿀 이유가 없다는 증거.** 둘은 같은 그림의 해상도 차이다 —
    /// 조인 실루엣의 가로/세로 비가 0.005 안에서 같고(실측 최대차 0.0026 — 여우), 그래서 `portraitBox` 도 같은 상자를 준다.
    /// 어느 날 아틀라스를 다른 자세로 다시 구우면 이 비가 벌어지고, 그때는 "같은 그림"이라는 이 근거부터 다시 재야 한다.
    @Test func 카드_그림과_초상은_같은_그림의_해상도_차이다() throws {
        let catalog = CheckCharacter3DScene.catalog
        let sprites = AppUserAvatarArt.knownIDs.filter { catalog.manifest(id: $0)?.kind == .sprite }
        #expect(sprites.count >= 4, "스프라이트가 \(sprites.count) 종뿐이다 — 기준선을 확인하라")
        for id in sprites {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let cell = CharacterCardArt.tightened(try #require(CharacterCardArt.frontIdleCell(characterID: id)))
            // 해상도는 **달라야** 한다(초상 192² · 셀 512 높이) — 같으면 '해상도 차이'라는 말이 뜻을 잃는다.
            #expect(cell.height > art.height + 100, "\(id) 셀 높이 \(cell.height) 와 초상 \(art.height) 가 너무 가깝다")
            let artRatio = Double(art.width) / Double(art.height)
            let cellRatio = Double(cell.width) / Double(cell.height)
            #expect(abs(artRatio - cellRatio) < 0.005, "\(id) 비가 초상 \(artRatio) · 셀 \(cellRatio) 로 갈렸다")
            // 상자 규칙의 결과까지 같다 = 출처를 바꿔도 화면이 안 달라진다.
            let a = AppUserAvatarArt.portraitBox(diameter: 26, artSize: CGSize(width: art.width, height: art.height))
            let b = AppUserAvatarArt.portraitBox(diameter: 26, artSize: CGSize(width: cell.width, height: cell.height))
            #expect(abs(a.width - b.width) < 0.12 && abs(a.height - b.height) < 0.12, "\(id) \(a) vs \(b)")
        }
    }

    @Test func 모르는_캐릭터와_깨진_초상은_아잉이_아니라_nil_이다() throws {
        #expect(AppUserAvatarArt.portrait(characterID: "dragon") == nil)
        #expect(AppUserAvatarArt.portrait(characterID: "") == nil)
        #expect(AppUserAvatarArt.portrait(characterID: "AING") == nil, "id 는 소문자 정규화된 값만 온다")

        // ★ 이 불변식이 **일하고 있다**는 증거: 폴백이 있는 이웃 함수들은 같은 id 에 아잉을 돌려준다.
        //   프로필이 그 함수들 중 하나를 타는 순간(2026-09-21 에 실제로 그랬다) 남의 얼굴에 아잉이 선다.
        let aing = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.builtInAingID))
        let cardFold = try #require(CharacterCardArt.image(characterID: "dragon"),
                                    "카드 그림이 모르는 id 에 nil 을 준다면 이 검사는 무의미하다")
        #expect(cardFold.width == aing.width && cardFold.height == aing.height, "카드 그림이 모르는 id 를 아잉으로 접지 않는다")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: "dragon") != nil, "마스코트 경로도 아잉으로 접는다")

        for id in AppUserAvatarArt.knownIDs {
            #expect(AppUserAvatarArt.portrait(characterID: id) != nil, "\(id) 를 안다고 해 놓고 못 그린다")
        }
        // 아는 캐릭터 목록은 번들 카탈로그 그대로다(빈 원이 서지 않게 — V0335 와 같은 계약).
        #expect(Set(AppUserAvatarArt.knownIDs) == Set(CheckMascotAssets.catalog.allIDs))
    }
}

// MARK: - ②' 캐릭터별 얼굴 크기 편차 (검토 지적 "3배 갈린다"에 대한 실측)

@MainActor
@Suite("v0.3.36 캐릭터별 얼굴 크기")
struct V0336FaceScaleTests {
    /// 조인 그림의 **행별 가로 폭**(알파 > 8). `CharacterCardArt.alphaBounds` 와 같은 규약(좌상단 원점)으로 한 번 그려 읽는다.
    static func rowExtents(_ image: CGImage) -> [Int] {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0..<h).map { y in
            let row = y * w * 4
            var lo = -1, hi = -1
            for x in 0..<w where pixels[row + x * 4 + 3] > 8 {
                if lo < 0 { lo = x }
                hi = x
            }
            return lo < 0 ? 0 : hi - lo + 1
        }
    }

    /// 26pt 원에 그려질 때의 **귀 끝 사이 폭**(위 절반에서 가장 넓은 행) — 캐릭터를 알아보는 크기의 대리값이다.
    static func earWidthPt(_ id: String, diameter: CGFloat = 26) -> Double? {
        guard let art = AppUserAvatarArt.portrait(characterID: id), art.width > 0 else { return nil }
        let box = AppUserAvatarArt.portraitBox(diameter: diameter, artSize: CGSize(width: art.width, height: art.height))
        let ext = rowExtents(art)
        guard let top = ext.prefix(max(1, ext.count / 2)).max() else { return nil }
        return Double(top) * Double(box.width) / Double(art.width)
    }

    /// 검토 지적: "얼굴 크기가 캐릭터마다 3배 갈리는데 이를 막던 계약이 무력화됐다."
    ///
    /// **직접 쟀다(2026-09-21, 26pt 원 기준 귀 끝 사이 폭 pt).**
    /// - 새 규칙(높이 1.03 · 폭 상한 1.02): 다람쥐 19.4 · 여우 19.8 · 시바 20.8 · 유령 21.9 · 아잉 23.0 · 해파리 23.3 → **1.20배**
    /// - 옛 규칙(정사각 1.20 + scaledToFit · 아래로 0.15): 22.6 ~ 27.1 → **1.20배** (편차는 그대로, 전부 더 컸을 뿐)
    /// - 레퍼런스(조영서 캡처): 20.6 — 여섯이 만드는 띠(19.4~23.3) 안이다.
    /// 즉 **3배로 갈리지 않고**, 편차도 옛 규칙과 같다. 두 규칙 다 캐릭터마다 **같은 기준**(조인 실루엣)으로 한 번에
    /// 키우기 때문이다 — 얼굴 크기 차이는 그림 자체의 차이(아잉은 머리만, 시바는 전신)이지 규칙이 만든 것이 아니다.
    /// 그래도 편차 상한은 **계약으로 남긴다**: 언젠가 캐릭터별 보정을 넣으면 여기서 먼저 빨개진다.
    @Test func 얼굴_크기는_캐릭터마다_1_3배_안에서만_갈리고_원을_넘지_않는다() throws {
        var widths: [(String, Double)] = []
        for id in AppUserAvatarArt.knownIDs.sorted() {
            widths.append((id, try #require(Self.earWidthPt(id), "\(id) 를 못 쟀다")))
        }
        #expect(widths.count == 6, "\(widths.count) 종만 쟀다")
        let values = widths.map(\.1)
        let lo = try #require(values.min()), hi = try #require(values.max())
        #expect(hi / lo < 1.30, "얼굴 폭이 \(hi / lo) 배 갈렸다 — \(widths)")
        // 레퍼런스 20.6pt 둘레에 모여야 한다. 위쪽(0.95 지름)을 넘으면 옛 규칙처럼 과하게 키운 것이다(옛 최대 27.1 = 1.04 지름).
        #expect(lo > 26 * 0.70, "가장 작은 얼굴이 \(lo)pt — 26pt 에서 못 알아본다. \(widths)")
        #expect(hi < 26 * 0.95, "가장 큰 얼굴이 \(hi)pt — 원을 넘도록 키웠다. \(widths)")
    }

    /// 순수 스위트가 쓰는 크기 표(`V0336PortraitBoxTests.artSizes`)가 **실제 번들 그림과 같은지** 본다.
    /// 표가 낡으면 순수 테스트는 초록인 채로 실제 화면만 달라진다(아틀라스 셀 크기를 적어 두면 그런 일이 난다).
    @Test func 상자_표가_실제_그림과_맞다() throws {
        for (id, size) in V0336PortraitBoxTests.artSizes {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 그림이 없다")
            #expect(CGFloat(art.width) == size.width && CGFloat(art.height) == size.height,
                    "\(id) 표는 \(size) 인데 실제는 \(art.width)×\(art.height) 다")
        }
        #expect(Set(V0336PortraitBoxTests.artSizes.map(\.id)) == Set(AppUserAvatarArt.knownIDs))
    }

    /// 크기 편차의 **뿌리**: 상자 높이는 여섯이 지름 대비 거의 같아야 한다(아잉만 가로 상한에 걸려 조금 작다).
    /// 실측 0.958(아잉) ~ 1.030(나머지 다섯) = 1.075배. 캐릭터마다 다른 배율을 쓰기 시작하면 여기가 먼저 벌어진다.
    @Test func 상자_높이는_여섯이_거의_같다() throws {
        var heights: [(String, CGFloat)] = []
        for id in AppUserAvatarArt.knownIDs.sorted() {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let box = AppUserAvatarArt.portraitBox(diameter: 26, artSize: CGSize(width: art.width, height: art.height))
            heights.append((id, box.height / 26))
        }
        let values = heights.map(\.1)
        let lo = try #require(values.min()), hi = try #require(values.max())
        #expect(lo > 0.94 && hi <= AppUserAvatarArt.artHeightFraction + 1e-9, "\(heights)")
        #expect(hi / lo < 1.10, "상자 높이가 \(hi / lo) 배 갈렸다 — \(heights)")
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

    /// 2026-09-21 실측(64pt @2x · 여섯 캐릭터 전부). 그려진 폭이 상자 규칙과 ±0.03 지름 안에서 맞고, 머리가 원 위 호까지 닿는다.
    ///
    /// **임계 0.043 은 옛 값과 새 값의 한가운데다.** 2026-09-21 실측 위 빈틈(64pt @2x 렌더, 지름 대비):
    /// - 새 규칙 **0.0234~0.0312**(여섯 — 여우만 0.0312, 나머지 다섯은 0.0234)
    /// - 옛 규칙(정사각 1.20 + scaledToFit · 아래로 +0.15) **0.0469~0.0859**
    /// 0.035(여유 0.5px)로 조이면 옛 규칙을 더 잘 잡는 것도 아니면서 병합 한 번에 깨진다 — 지키려는 사실은
    /// "머리 위가 옛날처럼 비어 있지 않다"이지 "0.5px 안에 있다"가 아니다. 0.043 은 5행(0.0391)과 6행(0.0469) 사이 —
    /// 새 값(최대 4행)에 한 행 여유를 주고 옛 값(최소 6행)은 0.5px 차로 계속 잡는다. 앞서 쓴
    /// 옛 값 아래로 2.0px(@128px 비트맵)다.
    /// 옛 규칙은 그려진 폭도 달랐다(여우 0.922 · 시바 0.938 · 다람쥐 0.875) — 정사각 상자라 원본 비를 잃었다.
    @Test func 그려진_폭이_상자_규칙과_같고_머리가_원_위까지_닿는다() throws {
        let size: CGFloat = 64
        let plate = try Self.plateColor(size: size)
        for id in AppUserAvatarArt.knownIDs.sorted() {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id))
            let box = AppUserAvatarArt.portraitBox(
                diameter: size, artSize: CGSize(width: art.width, height: art.height))
            let rep = try V0335AvatarCharacterRenderTests.bitmap(
                AppUserAvatarFace(avatar: .character(id), name: "민수", size: size))
            let ink = try Self.ink(rep, plate: plate)
            // 폭은 **원보다 좁은 그림에서만** 상자와 맞다 — 아잉(1.020)·유령(1.014)은 원이 좌우를 깎아 낸다.
            if box.width <= size * 0.95 {
                #expect(abs(ink.width - box.width / size) < 0.03,
                        "\(id) 그려진 폭 \(ink.width) · 상자 \(box.width / size) — 뷰가 상자 규칙을 안 쓴다")
            }
            #expect(ink.topGap < 0.043, "\(id) 머리 위가 \(ink.topGap) 비었다 — 그림이 아래로 내려갔다(옛 규칙은 0.047~0.086)")
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

    /// 메뉴바 아이콘은 **그대로** 근무 여부를 따른다 — 소스 문자열이 아니라 픽셀로 잰다(③ 의 반쪽).
    /// 헤더만 neutral 로 박았으므로, 여기가 같아지면 상태 표시가 통째로 사라진 것이다.
    @Test func 메뉴바_아이콘은_여전히_근무_여부로_얼굴이_바뀐다() throws {
        let working = WorkStatusSnapshot(status: .working, elapsedSeconds: 60)
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        let a = try #require(CheckMascotAssets.menuBarImage(for: working))
        let b = try #require(CheckMascotAssets.menuBarImage(for: off))
        #expect(a === CheckMascotAssets.menuBarImage(for: .neutral), "근무 중이 웃는 얼굴이 아니다")
        #expect(b === CheckMascotAssets.menuBarImage(for: .negative), "근무 중 아님이 시무룩한 얼굴이 아니다")
        // 그림이 실제로 다른가(같은 파일이면 이 비교는 아무것도 못 가른다 — 기준선 규칙).
        let pa = try Self.rep(a), pb = try Self.rep(b)
        #expect(V0335AvatarCharacterRenderTests.meanDifference(pa, pb) > 3,
                "메뉴바가 근무 여부와 상관없이 같은 얼굴이다")
        #expect(a.size == CheckMascotAssets.menuBarSize && b.size == CheckMascotAssets.menuBarSize)
    }

    static func rep(_ image: NSImage) throws -> NSBitmapImageRep {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { throw V0336Error.render }
        return rep
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
    @Test func 프로필_그림_출처는_neutral_초상_한_곳이고_폴백이_없다() throws {
        let sources = try V0325TooltipTests.strippedSources()
        let avatar = try #require(sources["CheckAvatarView.swift"])
        // 초상 URL 을 직접 열어 디코드한다 — 폴백이 있는 함수를 타지 않는다.
        #expect(avatar.contains("CheckMascotAssets.portraitURL(for: .neutral, characterID: characterID)"))
        #expect(avatar.contains("CGImageSourceCreateWithURL(url as CFURL, nil)"))
        #expect(avatar.contains("CharacterCardArt.tightened(raw)"))
        // ★ 되돌림(2026-09-21)을 못 박는다: 이 둘은 모르는 id·깨진 PNG 를 **아잉으로 접는다**.
        #expect(!avatar.contains("CharacterCardArt.image("), "카드 그림 출처로 되돌아갔다 — 초상 실패가 아잉이 된다")
        #expect(!avatar.contains("CheckMascotAssets.image("), "아잉으로 폴백하는 내 캐릭터 경로를 남의 아바타가 탄다")

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

        // 헤더가 실제로 이 뷰를 그린다(파일 목록을 통째로 고정하지 않는다 — 다른 갈래가 뷰를 하나 더 쓰기 시작해도
        // 이 계약이 지키려는 사실, 즉 "헤더가 neutral 을 넘긴다"는 위 두 줄이 그대로 지킨다).
        let sites = sources.filter { $0.value.contains("CheckMascotView(") }.keys.sorted()
        #expect(sites.contains("CheckCharacterPanel.swift"), "헤더가 마스코트 뷰를 안 그린다: \(sites)")

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

    /// ② 되돌림의 근거가 된 **비용**을 다시 잰다(머리 주석의 +ms · MB 는 이 값이다).
    /// 캐시를 비우고 여섯 캐릭터를 한 번에 만드는 시간 = 팝오버에 아바타가 처음 뜨는 순간 메인스레드가 쓰는 시간이다.
    ///
    ///     CHECK_V0336_BAKE=/…/after swift test --filter V0336AvatarArtBake
    @Test("그림 출처 비용을 잰다", .enabled(if: v0336BakeDir != nil))
    func cost() throws {
        let dir = try #require(v0336BakeDir)
        let ids = AppUserAvatarArt.knownIDs.sorted()

        // ① 카드 그림(아틀라스 전신) — 아틀라스 디코드 + 셀 자르기 + 알파 상자.
        CheckCharacter3DScene.resetCharacterCachesForTesting()
        CharacterCardArt.resetCacheForTesting()
        var cardBytes = 0
        let cardStart = Date()
        for id in ids { cardBytes += (CharacterCardArt.image(characterID: id).map { $0.width * $0.height * 4 }) ?? 0 }
        let cardMs = Date().timeIntervalSince(cardStart) * 1000

        // ② 지금 쓰는 길 — 192² 초상 디코드 + 알파 상자(`AppUserAvatarArt.portrait` 와 같은 작업).
        var portraitBytes = 0
        let portraitStart = Date()
        for id in ids {
            guard let url = CheckMascotAssets.portraitURL(for: .neutral, characterID: id),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let raw = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let tight = CharacterCardArt.tightened(raw)
            portraitBytes += tight.width * tight.height * 4
        }
        let portraitMs = Date().timeIntervalSince(portraitStart) * 1000

        // ③ 아틀라스가 상주하는 바이트(캐시에 남는다 — 카드를 안 열어도 아바타가 열면 들어온다).
        var atlasBytes = 0
        for id in ids {
            guard let manifest = CheckCharacter3DScene.catalog.manifest(id: id),
                  let atlas = CheckCharacter3DScene.atlasImage(for: manifest) else { continue }
            atlasBytes += atlas.width * atlas.height * 4
        }

        let json = """
        {"cardMs": \(cardMs), "portraitMs": \(portraitMs), \
        "atlasMB": \(Double(atlasBytes) / 1_048_576), \
        "cardArtMB": \(Double(cardBytes) / 1_048_576), \
        "portraitArtMB": \(Double(portraitBytes) / 1_048_576)}
        """
        try json.write(toFile: "\(dir)/cost.json", atomically: true, encoding: .utf8)
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
