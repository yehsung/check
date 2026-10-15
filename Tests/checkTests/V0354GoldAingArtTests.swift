import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import Testing
@testable import check

/// 0.3.54 황금 아잉이 그림 계약 — `scripts/make-gold-aing.swift` 산출물 6장(금 피부 맵 · 후광 · 초상 2 + 폰 사본 2).
/// 모양(파일·크기·알파)만 재지 않고, 앱이 그 그림으로 실제로 얻는 결과(초상 몸 색 통계, 감은 눈 커버를 합성한 텍셀 색)를 잰다.
/// 각 결과 단언에는 '지금 아잉'으로 같은 잣대를 돌린 기준선을 붙여, 잣대가 차이를 실제로 가르는지도 함께 확인한다.
@Suite struct V0354GoldAingArtTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let macDir = root.appendingPathComponent("Sources/check/Resources")
    static let phoneDir = root.appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits")
    static let expressions = ["neutral", "negative"]

    static func image(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(url.lastPathComponent) 를 못 연다")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "\(url.lastPathComponent) 디코드 실패")
    }

    /// RGBA8 premultipliedLast(sRGB) 바이트. 원점 좌상단.
    static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return px
    }

    static func borderAlpha(_ image: CGImage, ring: Int = 2) -> Double {
        let w = image.width, h = image.height, px = rgba(image)
        var m = 0
        for y in 0..<h { for x in 0..<w where x < ring || y < ring || x >= w - ring || y >= h - ring { m = max(m, Int(px[(y * w + x) * 4 + 3])) } }
        return Double(m) / 255
    }

    static func maxAlpha(_ image: CGImage) -> Double {
        Double(rgba(image).enumerated().filter { $0.offset % 4 == 3 }.map(\.element).max() ?? 0) / 255
    }

    // MARK: - 파일

    @Test("산출물 6장이 저장소에 있고, 맥 4장은 앱 리소스 번들에서 이름으로 찾힌다 · 크기와 알파가 맞다")
    func filesExistWithSizesAndAlpha() throws {
        let skin = try Self.image(Self.macDir.appendingPathComponent("aing_gold-skin.png"))
        #expect(skin.width == 512 && skin.height == 512, "금 피부 맵은 aing.scn 디퓨즈와 같은 512² 여야 UV 가 맞는다")
        #expect(Self.rgba(skin).enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 },
                "금 피부 맵은 모든 텍셀이 불투명해야 한다(합성은 RGB 만 갈아 끼운다)")

        let halo = try Self.image(Self.macDir.appendingPathComponent("aing_gold-halo.png"))
        #expect(halo.width == 512 && halo.height == 512)
        #expect(halo.alphaInfo != .none && halo.alphaInfo != .noneSkipLast && halo.alphaInfo != .noneSkipFirst, "후광에 알파가 없다")

        for e in Self.expressions {
            let mac = try Self.image(Self.macDir.appendingPathComponent("aing_gold-\(e).png"))
            #expect(mac.width == 192 && mac.height == 192, "초상 \(e) 은 192² (다른 캐릭터 초상과 같은 칸)")
            #expect(mac.alphaInfo != .none && mac.alphaInfo != .noneSkipLast && mac.alphaInfo != .noneSkipFirst, "초상 \(e) 알파 없음")
            #expect(FileManager.default.fileExists(atPath: Self.phoneDir.appendingPathComponent("aing_gold-\(e).png").path),
                    "폰·위젯 공용 번들에 aing_gold-\(e).png 사본이 없다")
        }
        // 앱은 Resources 를 `.process` 로 평탄화해 이름으로 찾는다 — 번들에 실제로 들어갔는지(파일만 있고 빌드에서 빠지는 일 방지).
        for name in ["aing_gold-skin", "aing_gold-halo", "aing_gold-neutral", "aing_gold-negative"] {
            #expect(CheckResources.bundle.url(forResource: name, withExtension: "png") != nil, "\(name).png 이 앱 리소스 번들에 없다")
        }
    }

    @Test("초상·후광 바깥 2px 알파 ≤ 0.04 — 후광이 프레임 안에서 사라진다(빈 그림이 아니라 진짜 빛이 있다)")
    func bordersFadeOut() throws {
        let halo = try Self.image(Self.macDir.appendingPathComponent("aing_gold-halo.png"))
        #expect(Self.borderAlpha(halo) <= 0.04, "후광 테두리 알파 \(Self.borderAlpha(halo))")
        // 기준선: 테두리가 0 인 게 '빈 그림'이라서가 아님 — 몸 둘레는 거의 불투명하게 빛난다.
        #expect(Self.maxAlpha(halo) > 0.9, "후광 PNG 가 비어 있다")
        for e in Self.expressions {
            let portrait = try Self.image(Self.macDir.appendingPathComponent("aing_gold-\(e).png"))
            #expect(Self.borderAlpha(portrait) <= 0.04, "초상 \(e) 테두리 알파 \(Self.borderAlpha(portrait))")
            // 기준선: 프레임 가장자리와 몸 사이(가로 가운데 줄, 몸 왼쪽 끝 바로 바깥)에 후광이 실제로 있다.
            let px = Self.rgba(portrait), w = portrait.width, y = portrait.height / 2
            let firstBody = try #require((0..<w).first { px[(y * w + $0) * 4 + 3] >= 250 }, "가운데 줄에 몸이 없다")
            let glow = Double(px[(y * w + max(0, firstBody - 4)) * 4 + 3]) / 255
            #expect(glow > 0.3, "초상 \(e) 몸 바로 바깥(4px) 후광 알파 \(glow) — 후광이 없다")
        }
    }

    @Test("폰 초상 사본은 맥 원본과 픽셀까지 같다(폰·위젯·맥이 같은 금색)")
    func phoneCopiesArePixelIdentical() throws {
        for e in Self.expressions {
            let mac = try Self.image(Self.macDir.appendingPathComponent("aing_gold-\(e).png"))
            let phone = try Self.image(Self.phoneDir.appendingPathComponent("aing_gold-\(e).png"))
            #expect(phone.width == mac.width && phone.height == mac.height)
            #expect(Self.rgba(phone) == Self.rgba(mac), "aing_gold-\(e) 폰 사본이 맥 원본과 다르다")
        }
    }

    // MARK: - 결과: 초상 몸 색

    /// ref measure.swift 와 같은 정의: 가운데 30–70% 상자, 알파 ≥ 250, r > g > b, (r − b)/r > 0.2 인 '금빛' 픽셀.
    struct BodyStats { var mean: (Double, Double, Double); var p10: Int; var p50: Int; var p90: Int; var n: Int }
    static func bodyStats(_ image: CGImage) -> BodyStats {
        let w = image.width, h = image.height, px = rgba(image)
        var sr = 0.0, sg = 0.0, sb = 0.0
        var lums = [Double]()
        for y in (h * 3 / 10)..<(h * 7 / 10) { for x in (w * 3 / 10)..<(w * 7 / 10) {
            let i = (y * w + x) * 4
            guard px[i + 3] >= 250 else { continue }
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            guard r > g, g > b, (r - b) / r > 0.2 else { continue }
            sr += r; sg += g; sb += b; lums.append(0.299 * r + 0.587 * g + 0.114 * b)
        } }
        guard !lums.isEmpty else { return BodyStats(mean: (0, 0, 0), p10: 0, p50: 0, p90: 0, n: 0) }
        lums.sort()
        func q(_ f: Double) -> Int { Int(lums[Int(Double(lums.count - 1) * f)]) }
        let n = Double(lums.count)
        return BodyStats(mean: (sr / n, sg / n, sb / n), p10: q(0.1), p50: q(0.5), p90: q(0.9), n: lums.count)
    }

    /// 사용자가 확정한 시안(target-body-512.png, 2026-10-15)을 같은 정의로 잰 값.
    static let targetMean = (240.0, 203.0, 103.0)
    static let targetLum = (166, 211, 235)

    static func matchesTarget(_ s: BodyStats) -> Bool {
        abs(s.mean.0 - targetMean.0) <= 8 && abs(s.mean.1 - targetMean.1) <= 8 && abs(s.mean.2 - targetMean.2) <= 8
            && abs(s.p10 - targetLum.0) <= 12 && abs(s.p50 - targetLum.1) <= 12 && abs(s.p90 - targetLum.2) <= 12
    }

    @Test("초상 몸 색이 확정 시안 통계(평균 RGB ±8 · 밝기 p10/p50/p90 ±12)와 맞는다 — 지금 아잉 초상은 같은 잣대에 걸린다")
    func portraitBodyColorMatchesTarget() throws {
        for e in Self.expressions {
            let gold = Self.bodyStats(try Self.image(Self.macDir.appendingPathComponent("aing_gold-\(e).png")))
            #expect(gold.n > 3_000, "초상 \(e) 측정 상자에 금빛 픽셀이 \(gold.n)개뿐")
            #expect(Self.matchesTarget(gold),
                    "초상 \(e): mean \(Int(gold.mean.0)) \(Int(gold.mean.1)) \(Int(gold.mean.2)) · lum \(gold.p10)/\(gold.p50)/\(gold.p90)")
            // 기준선: 라벤더 원본 초상은 같은 잣대를 통과하지 못한다(잣대가 색을 실제로 가른다).
            let plain = Self.bodyStats(try Self.image(Self.macDir.appendingPathComponent("aing-\(e).png")))
            #expect(!Self.matchesTarget(plain) && plain.n < gold.n / 3, "지금 아잉 초상(\(e))이 금 잣대를 통과한다 — 잣대가 무디다")
        }
    }

    // MARK: - 결과: 감은 눈 커버 합성

    /// 금 합성 마스크 — **앱 함수**(`GoldAingFinish.isGoldSkin`, 아트 스크립트 `isGoldSkin` 과 같은 식)를 부른다.
    /// 예전엔 여기 사본이 있었다 — 사본은 앱이 식을 바꿔도 초록이라 그림과 앱이 갈린 것을 못 잡는다(아키텍트 결정 2026-10-15).
    static func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        GoldAingFinish.isGoldSkin(r, g, b)
    }

    /// 앱의 합성(`GoldAingFinish.composite`) 그대로.
    static func composite(_ face: [UInt8], skin: [UInt8]) -> [UInt8] {
        GoldAingFinish.composite(face: face, skin: skin)
    }

    @MainActor
    @Test("감은 눈: 앱의 실제 커버(라벤더)를 금 피부 맵으로 합성하면 덮인 텍셀이 전부 금이 되고, 근처 둘레보다 어둡게 꺼지지 않는다")
    func closedEyeCoverCompositesToGold() throws {
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
        let openCG = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        let closedCG = try #require(CheckCharacter3DScene.makeClosedEyesImage(
            faceImage: openCG, geometry: SleepEyeExplore.faceGeometry(in: scene)))
        let skinCG = try Self.image(Self.macDir.appendingPathComponent("aing_gold-skin.png"))
        #expect(openCG.width == skinCG.width && openCG.height == skinCG.height, "얼굴 디퓨즈와 금 피부 맵 크기가 다르다")

        let open = SleepEyeExplore.rgbaBuffer(openCG), closed = SleepEyeExplore.rgbaBuffer(closedCG)
        let skin = SleepEyeExplore.rgbaBuffer(skinCG)
        let goldClosed = Self.composite(closed, skin: skin), goldOpen = Self.composite(open, skin: skin)
        let w = openCG.width, n = w * openCG.height

        // 커버 = 감은 눈 텍스처가 바꾼 텍셀.
        var covered = [Int]()
        for i in 0..<n where (0..<3).contains(where: { abs(Int(open[i * 4 + $0]) - Int(closed[i * 4 + $0])) > 6 }) { covered.append(i) }
        #expect(covered.count > 500, "감은 눈 커버가 \(covered.count) 텍셀뿐 — 커버 경로가 안 돌았다")

        func luma(_ px: [UInt8], _ i: Int) -> Int { (Int(px[i * 4]) * 299 + Int(px[i * 4 + 1]) * 587 + Int(px[i * 4 + 2]) * 114) / 1000 }
        /// 금(노랑 계열): 빨강·초록이 둘 다 파랑보다 20 이상 크다. 밝은 크림 금 (255,251,216) · 연두 끼 (254,255,158) 도 금.
        /// 라벤더는 파랑 ≥ 빨강이라 여기서 갈린다(금 피부 맵 전체 최소 r−b 38 · g−b 33 — 실측).
        func isGold(_ px: [UInt8], _ i: Int) -> Bool { let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2]); return r - b >= 20 && g - b >= 20 }
        func isLavender(_ px: [UInt8], _ i: Int) -> Bool { Self.isGoldSkin(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) }

        // 기준선: 합성 전 커버는 (거의) 전부 라벤더 피부이고 금은 하나도 없다.
        let lavender = covered.filter { isLavender(closed, $0) }
        #expect(lavender.count * 100 >= covered.count * 95, "커버 \(covered.count) 중 라벤더 피부 \(lavender.count) — 커버가 피부로 안 덮였다")
        #expect(!lavender.contains { isGold(closed, $0) }, "합성 전 라벤더 커버가 금으로 판정된다 — 기준선이 안 갈린다")
        // 결과: 합성하면 그 텍셀이 전부 금이다(금 피부 맵이 눈 자리까지 금으로 차 있다).
        let notGold = lavender.filter { !isGold(goldClosed, $0) }.count
        #expect(notGold == 0, "라벤더 커버 \(lavender.count) 중 합성 후 금이 아닌 텍셀 \(notGold)")

        // 결과: 커버 금이 '그 근처' 둘레 금보다 꺼지지 않는다(어두운 초승달 금지). 둘레 = 커버 밖 2–6텍셀의 피부.
        // 같은 잣대를 라벤더 원본 커버에도 돌려(기존 감은 눈 품질), 금이 그보다 1%p 넘게 나쁘지 않아야 한다.
        let h = n / w
        var coverSet = [Bool](repeating: false, count: n)
        for i in covered { coverSet[i] = true }
        func dilated(_ mask: [Bool], _ r: Int) -> [Bool] {
            var across = [Bool](repeating: false, count: n), out = [Bool](repeating: false, count: n)
            for i in 0..<n where mask[i] { let x = i % w, y = i / w; for xx in max(0, x - r)...min(w - 1, x + r) { across[y * w + xx] = true } }
            for i in 0..<n where across[i] { let x = i % w, y = i / w; for yy in max(0, y - r)...min(h - 1, y + r) { out[yy * w + x] = true } }
            return out
        }
        let outer = dilated(coverSet, 6), inner = dilated(coverSet, 1)
        let near = (0..<n).map { outer[$0] && !inner[$0] }
        func darkCount(_ face: [UInt8], _ cover: [UInt8], skinTest: ([UInt8], Int) -> Bool) -> Int {
            // 32텍셀 칸마다 둘레 피부 루마를 모으고, 칸 + 이웃 8칸의 중앙값을 '근처 둘레'로 쓴다.
            let block = 32, bw = (w + block - 1) / block, bh = (h + block - 1) / block
            var buckets = [[Int]](repeating: [], count: bw * bh)
            for i in 0..<n where near[i] && skinTest(face, i) { buckets[(i / w / block) * bw + (i % w) / block].append(luma(face, i)) }
            var median = [Int?](repeating: nil, count: bw * bh)
            for by in 0..<bh { for bx in 0..<bw {
                var local = [Int]()
                for yy in max(0, by - 1)...min(bh - 1, by + 1) { for xx in max(0, bx - 1)...min(bw - 1, bx + 1) { local += buckets[yy * bw + xx] } }
                if !local.isEmpty { local.sort(); median[by * bw + bx] = local[local.count / 2] }
            } }
            return lavender.filter { i in
                guard let m = median[((i / w) / block) * bw + (i % w) / block] else { return false }
                return luma(cover, i) < m - 30
            }.count
        }
        let darkGold = darkCount(goldOpen, goldClosed, skinTest: isGold)
        let darkPlain = darkCount(open, closed, skinTest: isLavender)
        #expect(darkGold * 100 <= darkPlain * 100 + lavender.count,
                "금 커버 중 근처 둘레보다 30 넘게 어두운 텍셀 \(darkGold) (라벤더 원본 \(darkPlain)) / \(lavender.count)")

        if let dir = ProcessInfo.processInfo.environment["CHECK_GOLD_RENDER_DIR"] {
            // 육안 확인용 덤프(환경변수가 있을 때만): 금 합성한 뜬 눈 · 감은 눈(선 없이 커버만) · 라벤더 감은 눈 — 앱 구도 렌더.
            let device = try #require(MTLCreateSystemDefaultDevice())
            for (name, px) in [("gold-open", goldOpen), ("gold-closed-cover", goldClosed), ("plain-closed-cover", closed)] {
                var copy = px
                let texture = copy.withUnsafeMutableBytes { raw in
                    CGContext(data: raw.baseAddress, width: w, height: n / w, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
                }
                material.diffuse.contents = try #require(texture)
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.autoenablesDefaultLighting = false
                let shot = renderer.snapshot(atTime: 0, with: CGSize(width: 280, height: 340), antialiasingMode: .multisampling4X)
                let data = try #require(shot.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}
