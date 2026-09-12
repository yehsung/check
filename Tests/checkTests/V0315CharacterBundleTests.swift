import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import check

// v0.3.15 — **캐릭터 에셋이 번들에 폴더째 살아 들어갔는가**(갈래 2: 에셋 파이프라인).
//
// 여기서 지키는 건 세 가지고, 셋 다 실측으로 데인 자리다.
//
// 1. `.process("Resources")` 는 **하위 폴더를 평탄화하고 동명 파일이면 빌드가 죽는다.** 캐릭터가 둘 이상이면
//    전부 `atlas.png` 를 갖기 때문에 `Resources/` 안에 두는 순간 빌드가 깨진다. 그래서 캐릭터는
//    `Sources/check/Characters/` + `.copy` 다. `.copy` 는 구조를 보존하므로 **subdirectory 조회**로 읽는다 —
//    이 파일은 그 조회가 진짜로 되는지를 잰다(파일 목록이 아니라 `CheckResources.bundle` 해석기를 통과시켜서).
// 2. 그 `.copy` 가 **기존 아잉 리소스를 밀어내지 않았는가.** `aing.scn`·`aing-*.png` 조회가 그대로 성공해야 한다.
//    이게 이 작업의 가장 큰 위험이었다.
// 3. **모든 셀은 같은 크기다.** 런타임은 평면 크기를 `frontIdle` 첫 프레임 rect 하나로 정하고 그 뒤로는
//    UV(`contentsTransform`)만 바꾼다 — 상태마다 rect 종횡비가 다르면 옆모습이 정면 평면에 늘어붙는다.
//
// 갈래 1 의 Swift 타입(`CharacterManifest`)을 **일부러 import 하지 않는다.** 같은 타입으로 읽으면 스키마가
// 아니라 "그 타입이 자기 자신을 읽는가"를 재게 된다. 여기서는 `JSONSerialization` 으로 **키 이름과 모양을 직접**
// 확인한다 — 키가 하나만 어긋나도 런타임에 캐릭터가 통째로 안 뜨는 계약이라, 독립적으로 재는 값이 있다.

// MARK: - 픽스처

/// 파이프라인이 실제로 구운 스프라이트 캐릭터들. 새 캐릭터를 더하면 여기에 더한다.
private let v0315SpriteCharacterIDs = ["bot", "fox"]

/// 갈래 1 `CharacterManifest` 가 요구하는 키 집합 — **정확히 이것뿐**이어야 한다.
/// (없으면 디코드가 throw 하고, 오타가 섞이면 조용히 nil 로 접힌다. 양쪽 다 잡으려고 집합을 같다고 본다.)
private let v0315RootKeys: Set<String> = ["id", "displayName", "kind", "atlas", "portrait"]
private let v0315AtlasKeys: Set<String> = ["file", "width", "height", "states"]
private let v0315StateKeys: Set<String> = ["frames", "durationsMs", "loop"]
private let v0315RectKeys: Set<String> = ["x", "y", "w", "h"]
private let v0315PortraitKeys: Set<String> = ["neutral", "negative"]
private let v0315RequiredStates: Set<String> = ["frontIdle", "sideIdle", "sideWalk"]

/// 픽셀이 '내용'인지 가르는 알파 — 갈래 1 `SpriteAlphaMask` 의 기본 임계와 같은 값이다.
private let v0315OpaqueThreshold: UInt8 = 32

// MARK: - 헬퍼

private struct V0315Rect: Hashable {
    let x: Int, y: Int, w: Int, h: Int
}

/// `.copy` 로 들어간 캐릭터 파일을 **앱이 쓰는 그 해석기**로 찾는다.
private func v0315URL(_ id: String, _ name: String, _ ext: String) -> URL? {
    CheckResources.bundle.url(forResource: name, withExtension: ext, subdirectory: "Characters/\(id)")
}

private func v0315Manifest(_ id: String) throws -> [String: Any] {
    let url = try #require(
        v0315URL(id, "manifest", "json"),
        "번들에서 Characters/\(id)/manifest.json 을 찾을 수 있어야 한다 (.copy 가 폴더 구조를 보존했는가)"
    )
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any], "매니페스트 최상위는 객체여야 한다")
}

private func v0315Rects(_ state: [String: Any]) throws -> [V0315Rect] {
    let frames = try #require(state["frames"] as? [[String: Any]], "frames 는 rect 배열이어야 한다")
    return try frames.map { raw in
        #expect(Set(raw.keys) == v0315RectKeys, "rect 키는 x·y·w·h 뿐이어야 한다: \(Set(raw.keys))")
        let values = try v0315RectKeys.map { key -> (String, Int) in
            let number = try #require(raw[key] as? NSNumber, "rect.\(key) 는 수여야 한다")
            return (key, try #require(Int(exactly: number), "rect.\(key) 는 정수여야 한다"))
        }
        let map = Dictionary(uniqueKeysWithValues: values)
        return V0315Rect(x: map["x"]!, y: map["y"]!, w: map["w"]!, h: map["h"]!)
    }
}

/// 아틀라스를 **포맷을 강제한 컨텍스트**에 다시 그려 픽셀을 읽는다.
/// (`CGImage.dataProvider` 바이트를 그대로 믿으면 비트맵 포맷 가정이 깨진다 — RGBA 로 다시 그리는 게 안전하다.)
private func v0315AtlasAlpha(_ url: URL) throws -> (alpha: [UInt8], width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "아틀라스 PNG 를 열 수 있어야 한다")
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "아틀라스를 CGImage 로 디코드할 수 있어야 한다")
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(bytes.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }, "RGBA 컨텍스트를 만들 수 있어야 한다")
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let drawn = try #require(context.data, "그린 픽셀을 읽을 수 있어야 한다")
    let raw = drawn.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var alpha = [UInt8](repeating: 0, count: width * height)
    for index in 0..<(width * height) {
        alpha[index] = raw[index * 4 + 3]
    }
    return (alpha, width, height)
}

private func v0315PixelSize(_ url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "PNG 를 열 수 있어야 한다: \(url.lastPathComponent)")
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        "PNG 속성을 읽을 수 있어야 한다"
    )
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    return (width, height)
}

// MARK: - 테스트

@Suite struct V0315CharacterBundleTests {

    /// `.copy` 가 폴더 구조를 보존했는가 — 평탄화됐으면 subdirectory 조회가 전부 nil 이 된다.
    @Test func 캐릭터_폴더가_번들에_구조째_들어간다() throws {
        for id in v0315SpriteCharacterIDs {
            #expect(v0315URL(id, "manifest", "json") != nil, "\(id)/manifest.json")
            #expect(v0315URL(id, "atlas", "png") != nil, "\(id)/atlas.png")
            #expect(v0315URL(id, "portrait-neutral", "png") != nil, "\(id)/portrait-neutral.png")
            #expect(v0315URL(id, "portrait-negative", "png") != nil, "\(id)/portrait-negative.png")
        }
    }

    /// ★ 이 작업의 가장 큰 위험: `.copy("Characters")` 가 기존 `.process("Resources")` 산출물을 밀어냈는가.
    @Test func 아잉_리소스_조회가_그대로_산다() throws {
        let bundle = CheckResources.bundle
        #expect(bundle.url(forResource: "aing", withExtension: "scn") != nil, "aing.scn 이 번들 루트에 그대로 있어야 한다")
        #expect(bundle.url(forResource: "aing", withExtension: "usdz") != nil, "aing.usdz")
        for mood in [CheckMascotAssets.Mood.neutral, .negative] {
            let url = try #require(CheckMascotAssets.url(for: mood), "\(CheckMascotAssets.resourceName(for: mood)).png")
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(CheckMascotAssets.image(for: mood) != nil, "아잉 표정 PNG 가 NSImage 로 열려야 한다")
        }
    }

    /// 갈래 1 `CharacterManifest` 의 키·타입 계약. 키 하나만 어긋나도 캐릭터가 통째로 안 뜬다.
    @Test func 매니페스트가_갈래1_스키마_그대로다() throws {
        for id in v0315SpriteCharacterIDs {
            let manifest = try v0315Manifest(id)
            #expect(Set(manifest.keys) == v0315RootKeys, "[\(id)] 최상위 키: \(Set(manifest.keys))")
            #expect(manifest["id"] as? String == id, "[\(id)] id 는 폴더 이름과 같아야 한다")
            let displayName = try #require(manifest["displayName"] as? String)
            #expect(!displayName.isEmpty, "[\(id)] displayName 이 비면 안 된다")
            #expect(manifest["kind"] as? String == "sprite", "[\(id)] kind 는 Kind.sprite 의 rawValue 여야 한다")

            let portrait = try #require(manifest["portrait"] as? [String: Any], "[\(id)] sprite 는 portrait 가 필수다")
            #expect(Set(portrait.keys) == v0315PortraitKeys)
            #expect(portrait["neutral"] as? String == "portrait-neutral.png")
            #expect(portrait["negative"] as? String == "portrait-negative.png")

            let atlas = try #require(manifest["atlas"] as? [String: Any], "[\(id)] sprite 는 atlas 가 필수다")
            #expect(Set(atlas.keys) == v0315AtlasKeys, "[\(id)] atlas 키: \(Set(atlas.keys))")
            #expect(atlas["file"] as? String == "atlas.png")

            let states = try #require(atlas["states"] as? [String: Any])
            #expect(Set(states.keys) == v0315RequiredStates, "[\(id)] 상태 키: \(Set(states.keys))")
            for (name, rawState) in states {
                let state = try #require(rawState as? [String: Any], "[\(id)] \(name)")
                #expect(Set(state.keys) == v0315StateKeys, "[\(id)] \(name) 키: \(Set(state.keys))")

                let rects = try v0315Rects(state)
                #expect(!rects.isEmpty, "[\(id)] \(name) 의 frames 가 비면 안 된다")

                let durations = try #require(state["durationsMs"] as? [NSNumber], "[\(id)] \(name).durationsMs")
                #expect(durations.count == rects.count, "[\(id)] \(name): frames 와 durationsMs 길이가 같아야 한다")
                for duration in durations {
                    let value = try #require(Int(exactly: duration), "[\(id)] \(name) 의 지속시간은 정수 ms 여야 한다")
                    #expect(value > 0, "[\(id)] \(name) 지속시간 \(value)")
                }

                // `loop` 은 JSON 불리언이어야 한다 — 0/1 로 쓰면 Codable Bool 디코드가 타입 불일치로 throw 한다.
                let loop = try #require(state["loop"], "[\(id)] \(name).loop")
                #expect(CFGetTypeID(loop as CFTypeRef) == CFBooleanGetTypeID(), "[\(id)] \(name).loop 은 true/false 여야 한다")
            }
        }
    }

    /// 아틀라스 PNG 가 실제로 열리고, 매니페스트가 말하는 크기와 같고, 모든 rect 가 그 안에 있다.
    @Test func 아틀라스가_열리고_모든_rect_가_그_안에_있다() throws {
        for id in v0315SpriteCharacterIDs {
            let manifest = try v0315Manifest(id)
            let atlas = try #require(manifest["atlas"] as? [String: Any])
            let declaredWidth = try #require(atlas["width"] as? Int)
            let declaredHeight = try #require(atlas["height"] as? Int)

            let url = try #require(v0315URL(id, "atlas", "png"))
            let size = try v0315PixelSize(url)
            #expect(size.width == declaredWidth && size.height == declaredHeight,
                    "[\(id)] 아틀라스 실제 크기 \(size) 가 매니페스트 \(declaredWidth)x\(declaredHeight) 와 달라선 안 된다")

            let states = try #require(atlas["states"] as? [String: Any])
            for (name, rawState) in states {
                for rect in try v0315Rects(try #require(rawState as? [String: Any])) {
                    #expect(rect.w > 0 && rect.h > 0, "[\(id)] \(name) rect 가 비었다: \(rect)")
                    #expect(rect.x >= 0 && rect.y >= 0
                            && rect.x + rect.w <= declaredWidth && rect.y + rect.h <= declaredHeight,
                            "[\(id)] \(name) rect \(rect) 가 아틀라스(\(declaredWidth)x\(declaredHeight)) 밖이다")
                }
            }
        }
    }

    /// ★ 모든 셀이 같은 크기여야 한다. 런타임 평면은 `frontIdle` 첫 프레임으로만 정해지고 그 뒤로는 UV 만 바뀐다 —
    ///   상태마다 rect 종횡비가 다르면 옆모습이 정면 평면에 늘어붙는다(에셋만으로 막을 수 있는 결함이라 여기서 막는다).
    @Test func 모든_셀이_같은_크기다() throws {
        for id in v0315SpriteCharacterIDs {
            let manifest = try v0315Manifest(id)
            let atlas = try #require(manifest["atlas"] as? [String: Any])
            let states = try #require(atlas["states"] as? [String: Any])
            var sizes: Set<String> = []
            for (_, rawState) in states {
                for rect in try v0315Rects(try #require(rawState as? [String: Any])) {
                    sizes.insert("\(rect.w)x\(rect.h)")
                }
            }
            #expect(sizes.count == 1, "[\(id)] 셀 크기가 여럿이다: \(sizes.sorted())")
        }
    }

    /// 여우는 **0,1,2,1** 이다(낮은 passing f3 이 18.7% 주저앉아 버렸다 — 같은 rect 를 다시 가리켜 되돌아온다).
    /// 로봇은 4프레임 전부 서로 다르다.
    @Test func 여우는_0_1_2_1_로_돌고_로봇은_네_프레임을_다_쓴다() throws {
        let fox = try #require(try v0315Manifest("fox")["atlas"] as? [String: Any])
        let foxWalk = try v0315Rects(try #require((fox["states"] as? [String: Any])?["sideWalk"] as? [String: Any]))
        #expect(foxWalk.count == 4, "여우 sideWalk 는 4프레임 재생이다")
        #expect(foxWalk[1] == foxWalk[3], "여우는 2번째 프레임으로 되돌아온다(0,1,2,1)")
        #expect(Set(foxWalk).count == 3, "여우가 굽는 실제 프레임은 3장이다(f3 는 아틀라스에 없다)")

        let bot = try #require(try v0315Manifest("bot")["atlas"] as? [String: Any])
        let botWalk = try v0315Rects(try #require((bot["states"] as? [String: Any])?["sideWalk"] as? [String: Any]))
        #expect(botWalk.count == 4 && Set(botWalk).count == 4, "로봇은 0,1,2,3 — 4장 다 다르다")
    }

    /// 옆모습 idle 은 **걷기 프레임 중 접지가 아닌 passing 프레임**을 재사용한다(추가 에셋 0).
    @Test func 옆모습_idle_은_걷기_프레임을_재사용한다() throws {
        for id in v0315SpriteCharacterIDs {
            let atlas = try #require(try v0315Manifest(id)["atlas"] as? [String: Any])
            let states = try #require(atlas["states"] as? [String: Any])
            let idle = try v0315Rects(try #require(states["sideIdle"] as? [String: Any]))
            let walk = try v0315Rects(try #require(states["sideWalk"] as? [String: Any]))
            #expect(idle.count == 1, "[\(id)] 옆모습 idle 은 한 장이다")
            #expect(walk.contains(idle[0]), "[\(id)] 옆모습 idle rect 가 걷기 프레임 중 하나여야 한다: \(idle[0])")
        }
    }

    /// 메뉴바(18pt)·팝오버(46pt) 가 쓰는 표정 PNG 는 pair-lock 된 192² 그대로다.
    @Test func 표정_PNG_는_192_정사각이다() throws {
        for id in v0315SpriteCharacterIDs {
            for name in ["portrait-neutral", "portrait-negative"] {
                let url = try #require(v0315URL(id, name, "png"), "[\(id)] \(name).png")
                let size = try v0315PixelSize(url)
                #expect(size.width == 192 && size.height == 192, "[\(id)] \(name) 크기 \(size)")
            }
        }
    }

    /// 셀이 비어 있지 않고, 셀 사이 여백(gutter)이 정말로 투명한가.
    /// (diffuse 가 clamp + linear 라 셀 경계에서 이웃 셀이 번진다 — 번져 들어오는 쪽이 투명이어야 안전하다.)
    @Test func 셀에_내용이_있고_경계_여백이_투명하다() throws {
        for id in v0315SpriteCharacterIDs {
            let atlas = try #require(try v0315Manifest(id)["atlas"] as? [String: Any])
            let states = try #require(atlas["states"] as? [String: Any])
            let url = try #require(v0315URL(id, "atlas", "png"))
            let (alpha, width, _) = try v0315AtlasAlpha(url)

            var seen: Set<V0315Rect> = []
            for (name, rawState) in states {
                for rect in try v0315Rects(try #require(rawState as? [String: Any])) where seen.insert(rect).inserted {
                    var opaque = 0
                    for row in 0..<rect.h {
                        for column in 0..<rect.w where alpha[(rect.y + row) * width + rect.x + column] > v0315OpaqueThreshold {
                            opaque += 1
                        }
                    }
                    let coverage = Double(opaque) / Double(rect.w * rect.h)
                    #expect(coverage > 0.05, "[\(id)] \(name) 셀 \(rect) 이 사실상 비었다(커버리지 \(coverage))")

                    // 사방 1px 테두리는 완전 투명이어야 한다(여백을 2px 뒀으니 테두리는 넉넉히 안쪽이다).
                    var border: UInt8 = 0
                    for column in 0..<rect.w {
                        border = max(border, alpha[rect.y * width + rect.x + column])
                        border = max(border, alpha[(rect.y + rect.h - 1) * width + rect.x + column])
                    }
                    for row in 0..<rect.h {
                        border = max(border, alpha[(rect.y + row) * width + rect.x])
                        border = max(border, alpha[(rect.y + row) * width + rect.x + rect.w - 1])
                    }
                    #expect(border == 0, "[\(id)] \(name) 셀 \(rect) 테두리에 내용이 닿았다(알파 \(border)) — 이웃 셀로 번진다")
                }
            }
        }
    }
}
