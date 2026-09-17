import CheckCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CheckMobileKit

/// 나 탭 캐릭터 카드 그림(박힌 HEIC)의 **드리프트 검사**와 **다시 굽기**.
///
/// - 평소: 맥 캐릭터 폴더(`Sources/check/Characters/<id>/manifest.json` + atlas, `Resources/aing-neutral.png`)를 다시 읽어 맥
///   `CharacterCardArt` 와 같은 규칙(frontIdle 첫 셀 → 알파>8 상자)으로 자른 크기가 박힌 값과 같은지, id·이름·픽셀아트 여부가 같은지,
///   박힌 그림이 디코드되고 알파가 살아 있는지 본다. 캐릭터가 늘거나 아틀라스가 다시 구워지면 빨개진다.
/// - `AING_REGENERATE_CHARACTER_CARDS=1 swift test --build-system native --filter MeCharacterCardTests` 면 `MeCharacterCardData.swift` 를 다시 쓴다.
@Suite("나 탭 캐릭터 카드(rankme)")
struct MeCharacterCardTests {
    static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let maxSide = 216

    struct Source {
        let id: String
        let displayName: String
        let pixelArt: Bool
        let crop: CGImage
    }

    struct Manifest: Decodable {
        struct Frame: Decodable { let x: Int; let y: Int; let w: Int; let h: Int }
        struct State: Decodable { let frames: [Frame] }
        struct Atlas: Decodable { let file: String; let states: [String: State] }
        let id: String
        let displayName: String
        let atlas: Atlas?
        let pixelArt: Bool?
    }

    static func loadImage(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// 맥 `CharacterCardArt.alphaBounds` 와 같은 규칙(프리멀티플라이 RGBA 로 그린 뒤 알파 > 8).
    static func alphaBounds(_ image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func transparentRatio(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var clear = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] < 8 { clear += 1 }
        return Double(clear) / Double(max(1, width * height))
    }

    static func sources() throws -> [Source] {
        let aing = try loadImage(repoRoot.appendingPathComponent("Sources/check/Resources/aing-neutral.png"))
        let aingBox = try #require(alphaBounds(aing))
        let aingCrop = try #require(aing.cropping(to: aingBox))
        var result = [Source(id: "aing", displayName: "아잉", pixelArt: false, crop: aingCrop)]
        let charactersDir = repoRoot.appendingPathComponent("Sources/check/Characters")
        let names = try FileManager.default.contentsOfDirectory(atPath: charactersDir.path).sorted()
        for name in names {
            let manifestURL = charactersDir.appendingPathComponent(name).appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            let atlasInfo = try #require(manifest.atlas)
            let atlas = try loadImage(charactersDir.appendingPathComponent(name).appendingPathComponent(atlasInfo.file))
            let frame = try #require(atlasInfo.states["frontIdle"]?.frames.first)
            let cell = try #require(atlas.cropping(to: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)))
            let box = try #require(alphaBounds(cell))
            let crop = try #require(cell.cropping(to: box))
            result.append(Source(id: manifest.id, displayName: manifest.displayName, pixelArt: manifest.pixelArt ?? false, crop: crop))
        }
        return result
    }

    static func scaledSize(_ image: CGImage) -> (Int, Int) {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return (image.width, image.height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(image.width) * scale).rounded())), max(1, Int((Double(image.height) * scale).rounded())))
    }

    @Test("드리프트: 박힌 카드가 맥 캐릭터 폴더와 같다(id·이름·픽셀아트·조인 상자·출력 크기)")
    func bundledCardsMatchMacAssets() throws {
        if ProcessInfo.processInfo.environment["AING_REGENERATE_CHARACTER_CARDS"] == "1" {
            try regenerate()
        }
        let sources = try Self.sources()
        #expect(MeCharacterCards.bundled.map(\.id) == sources.map(\.id), "캐릭터 목록이 갈렸다 — 다시 굽기")
        for source in sources {
            let card = try #require(MeCharacterCards.card(id: source.id), "\(source.id) 카드 없음")
            #expect(card.displayName == source.displayName)
            #expect(card.pixelArt == source.pixelArt)
            #expect(card.sourceCropWidth == source.crop.width && card.sourceCropHeight == source.crop.height, "\(source.id) 아틀라스가 바뀌었다")
            let (w, h) = Self.scaledSize(source.crop)
            #expect(card.pixelWidth == w && card.pixelHeight == h)
        }
        #expect(MeCharacterCards.knownIDs.first == CharacterCatalog.builtInAingID)
    }

    @Test("그림: 전부 디코드되고 크기가 맞고 알파가 살아 있다(모서리 투명)")
    func bundledCardsDecodeWithAlpha() throws {
        var total = 0
        for card in MeCharacterCards.bundled {
            total += card.heicBase64.count
            let image = try #require(MeCharacterCards.image(id: card.id), "\(card.id) 디코드 실패")
            #expect(image.width == card.pixelWidth && image.height == card.pixelHeight)
            #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst, "\(card.id) 알파가 사라졌다")
            // 조인 상자 안이라도 캐릭터 둘레(모서리)는 투명하다 — 알파가 날아가면 이 비율이 0 이 된다(HEIC 인코딩이 알파를 버리는 회귀).
            #expect(Self.transparentRatio(image) > 0.1, "\(card.id) 투명 픽셀이 없다(알파 손실 의심): \(Self.transparentRatio(image))")
        }
        #expect(total < 200_000, "박힌 그림이 너무 커졌다: \(total)")
        #expect(MeCharacterCards.image(id: "no-such-character") == nil)
    }

    @Test("접기: 서버 착용값 nil·공백·모르는 id → 아잉 · 아는 id 는 그대로 · 이름은 모르면 id")
    func equippedFolding() {
        #expect(MeCharacterCards.equippedID(fromServer: nil) == "aing")
        #expect(MeCharacterCards.equippedID(fromServer: "  ") == "aing")
        #expect(MeCharacterCards.equippedID(fromServer: "dragon") == "aing")
        #expect(MeCharacterCards.equippedID(fromServer: " fox ") == "fox")
        #expect(MeCharacterCards.displayName(for: "ghost") == "유령")
        #expect(MeCharacterCards.displayName(for: "dragon") == "dragon")
    }

    // MARK: 다시 굽기

    func regenerate() throws {
        var body = ""
        for source in try Self.sources() {
            let (w, h) = Self.scaledSize(source.crop)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .high
            context.draw(source.crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            let scaled = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            body += "        MeCharacterCard(\n"
            body += "            id: \"\(source.id)\", displayName: \"\(source.displayName)\", pixelArt: \(source.pixelArt),\n"
            body += "            sourceCropWidth: \(source.crop.width), sourceCropHeight: \(source.crop.height),\n"
            body += "            pixelWidth: \(w), pixelHeight: \(h),\n"
            body += "            heicBase64: \"\((data as Data).base64EncodedString())\"\n"
            body += "        ),\n"
        }
        let target = Self.repoRoot.appendingPathComponent("Sources/CheckMobileKit/Me/MeCharacterCardData.swift")
        let existing = try String(contentsOf: target, encoding: .utf8)
        let head = try #require(existing.range(of: "    static let bundled: [MeCharacterCard] = [\n"))
        let output = String(existing[..<head.upperBound]) + body + "    ]\n}\n"
        try output.write(to: target, atomically: true, encoding: .utf8)
    }
}
