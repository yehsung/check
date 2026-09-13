import ImageIO
import Foundation
import Testing
@testable import check

/// 갈래 1(코어)과 갈래 2(에셋)의 **이음매**를 잰다.
///
/// 왜 따로 두는가: 두 갈래를 병렬로 지었더니 각자 반쪽만 검증했다 — 코어는 임시 폴더로,
/// 에셋은 `Bundle` API 로. **"코어의 카탈로그가 에셋의 `.copy("Characters")` 산출물을 실제로 잡는가"**
/// 는 둘이 한자리에 모인 뒤에야 잴 수 있고, 아무도 못 본 자리였다. 여기가 그 자리다.
///
/// 이 파일이 빨개지는 대표적인 경우:
/// · `Package.swift` 의 `.copy("Characters")` 가 빠지거나 `.process` 로 바뀐다(폴더가 평탄화된다)
/// · 팩 스크립트의 출력 경로·파일명이 바뀐다
/// · 카탈로그의 `charactersSubdirectory` 가 바뀐다
@Suite("v0.3.15 캐릭터 이음매")
struct V0315CharacterSeamTests {

    @MainActor
    @Test("번들의 캐릭터 폴더가 카탈로그에 그대로 잡힌다")
    func bundledCharactersLoadIntoCatalog() throws {
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        // 아잉은 매니페스트 파일이 없어도 **언제나** 있다(내장 3D).
        #expect(catalog.allIDs.first == CharacterCatalog.builtInAingID)
        #expect(catalog.manifest(id: "aing")?.kind == .scene3D)
        // 번들에 구운 스프라이트 둘.
        for id in ["fox", "bot"] {
            let manifest = try #require(catalog.manifest(id: id), "번들에서 \(id) 를 못 찾았다 — .copy 산출물이 카탈로그에 안 잡힌다")
            #expect(manifest.kind == .sprite)
            #expect(try #require(catalog.atlasURL(for: id)).isFileURL)
            #expect(catalog.portraitURL(for: id, mood: .neutral) != nil)
            #expect(catalog.portraitURL(for: id, mood: .negative) != nil)
        }
    }

    @MainActor
    @Test("아틀라스가 실제로 열리고 매니페스트 rect 가 그 안에 있다")
    func atlasBytesMatchTheManifest() throws {
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        for id in ["fox", "bot"] {
            let manifest = try #require(catalog.manifest(id: id))
            let atlas = try #require(manifest.atlas)
            let url = try #require(catalog.atlasURL(for: id))
            let data = try Data(contentsOf: url)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            // 매니페스트가 적은 크기와 **실제 PNG 픽셀**이 같아야 한다. 팩 스크립트를 다시 돌리고
            // 한쪽만 커밋하면 여기서 갈린다(런타임엔 UV 가 어긋난 채 조용히 그려진다).
            #expect(image.width == atlas.width, "\(id): 매니페스트 폭 \(atlas.width) vs PNG \(image.width)")
            #expect(image.height == atlas.height, "\(id): 매니페스트 높이 \(atlas.height) vs PNG \(image.height)")
            for (name, state) in atlas.states {
                for (index, rect) in state.frames.enumerated() {
                    #expect(rect.x >= 0 && rect.y >= 0, "\(id).\(name)[\(index)] 음수 좌표")
                    #expect(rect.x + rect.w <= image.width, "\(id).\(name)[\(index)] 가 아틀라스 오른쪽을 넘는다")
                    #expect(rect.y + rect.h <= image.height, "\(id).\(name)[\(index)] 가 아틀라스 아래를 넘는다")
                }
            }
        }
    }

    @MainActor
    @Test("아잉 리소스는 캐릭터 폴더가 생겨도 그대로 잡힌다")
    func aingResourcesSurviveTheNewCopyRule() throws {
        // `.copy("Characters")` 가 `.process("Resources")` 를 밀어내지 않는다는 계약.
        // 이게 깨지면 기본 캐릭터가 통째로 사라진다 — 새 기능이 아니라 **기존 앱**이 죽는 자리다.
        let bundle = CheckResources.bundle
        #expect(bundle.url(forResource: "aing", withExtension: "scn") != nil)
        #expect(bundle.url(forResource: "aing", withExtension: "usdz") != nil)
        #expect(bundle.url(forResource: "aing-neutral", withExtension: "png") != nil)
        #expect(bundle.url(forResource: "aing-negative", withExtension: "png") != nil)
    }

    @MainActor
    @Test("픽셀아트 캐릭터는 재질 필터가 .nearest 다")
    func pixelArtUsesNearestFiltering() throws {
        // 앱 재질 필터와 팩 스크립트 리샘플은 **짝이다** — 둘 중 하나만 픽셀아트를 알면 소용없다.
        // 여기서는 앱 쪽 절반을 잰다(굽는 쪽은 `--pixel-art` 가 manifest 에 적는다).
        let atlas = CharacterManifest.Atlas(
            file: "atlas.png", width: 64, height: 32,
            states: [CharacterManifest.StateKey.frontIdle: .init(
                frames: [.init(x: 0, y: 0, w: 32, h: 32)], durationsMs: [100], loop: true)]
        )
        let pixel = CharacterManifest(id: "px", displayName: "픽셀", kind: .sprite, atlas: atlas,
                                      portrait: .init(neutral: "n.png", negative: "g.png"), pixelArt: true)
        let smooth = CharacterManifest(id: "sm", displayName: "부드", kind: .sprite, atlas: atlas,
                                       portrait: .init(neutral: "n.png", negative: "g.png"), pixelArt: nil)
        let image = try #require(solidAtlas(width: 64, height: 32))

        let pixelNode = try #require(SpriteCharacterNode.make(manifest: pixel, atlas: image))
        let pixelMat = try #require(pixelNode.geometry?.firstMaterial)
        #expect(pixelMat.diffuse.magnificationFilter == .nearest,
                "픽셀아트인데 확대 필터가 .linear 다 — SceneKit 이 격자를 뭉갠다")
        #expect(pixelMat.diffuse.minificationFilter == .nearest)

        let smoothNode = try #require(SpriteCharacterNode.make(manifest: smooth, atlas: image))
        let smoothMat = try #require(smoothNode.geometry?.firstMaterial)
        #expect(smoothMat.diffuse.magnificationFilter == .linear, "픽셀아트가 아닌데 .nearest 로 굳었다")
    }

    /// 테스트용 단색 아틀라스(알파 1).
    private func solidAtlas(width: Int, height: Int) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    @MainActor
    @Test("선택은 번들 캐릭터를 받아들이고 모르는 값은 아잉으로 접는다")
    func selectionAcceptsBundledAndFoldsUnknown() throws {
        let suite = "v0315-seam-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = CharacterSelection(defaults: defaults, catalog: .load(bundle: CheckResources.bundle))
        #expect(selection.selectedID == CharacterCatalog.builtInAingID)
        #expect(selection.select("fox"))
        #expect(selection.selectedID == "fox")
        // 번들에 없는 id 는 저장조차 되지 않는다.
        #expect(selection.select("ghost-that-does-not-exist") == false)
        #expect(selection.selectedID == "fox")
    }
}
