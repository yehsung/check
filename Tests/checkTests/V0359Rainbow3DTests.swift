import AppKit
import ImageIO
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.59 — 무지개 아잉이 3D(맥). 실제 앱 씬(`CheckCharacter3DScene.makeScene` · 교체 경로 · 엔진)을 오프스크린으로 그려 **결과**를 잰다:
//  · 마감이 선다: 얼굴 재질에 몸 셰이더 · 디퓨즈 = 밝기 맵 합성 · 후광 36칸(금과 같은 판 규약) — 아잉 · 황금에는 없다(기준선).
//  · GPU 셰이더가 기준 구현(`RainbowAingArt.bodyColorLinear`)과 같은 색을 낸다 — 높이 지도 · 라벤더 렌더로 조각마다 맞댄다(뒤집은 높이는 걸린다).
//  · 떠돌이 삼각형 점이 없다: 창 크기 · 울트라 크기에서 0 — 금처럼 UV 맵에 구운 판(기준선)은 같은 잣대에서 점이 난다.
//  · 후광 칸이 몸 요를 따른다 · 감은 눈(엔진 CGImage 경로 · 뷰가 있는 GPU 텍스처 경로)도 무지개다 · 울트라 교체가 아잉 · 황금 · 무지개를 가른다 ·
//    후광은 클릭 판정에서 빠진다.
//
// 미리보기: `CHECK_V0359_STILLS_DIR=<폴더>` 를 주면 앱 구도(어둡 · 밝 바탕) · 요 0/40/90/180 · 울트라 945² · 감은 눈 스틸을 떨군다(창 없음).

@MainActor
@Suite struct V0359Rainbow3DTests {
    static let rainbow = CharacterCatalog.builtInRainbowAing
    static let gold = CharacterCatalog.builtInGoldAing
    static let aing = CharacterCatalog.builtInAing

    // MARK: 도구

    static func scene(_ manifest: CharacterManifest = rainbow) throws -> SCNScene {
        try V0354GoldAing3DTests.scene(manifest)
    }

    static func halo(_ scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: RainbowAingFinish.haloNodeName, recursively: true)
    }

    /// 얼굴(몸 메시) 재질. 디퓨즈가 CGImage 든 MTLTexture(뷰가 있으면 엔진이 GPU 텍스처로 바꾼다)든 찾는다 — 후광 판(같은 크기의
    /// CGImage 디퓨즈)은 재질 이름으로 건너뛴다(엔진의 얼굴 탐색과 같은 규칙).
    static func faceMaterial(_ scene: SCNScene) throws -> SCNMaterial {
        var found: SCNMaterial?
        scene.rootNode.enumerateHierarchy { node, stop in
            guard let geometry = node.geometry, !(geometry is SCNPlane) else { return }
            for material in geometry.materials where material.name != GoldAingFinish.haloMaterialName {
                let contents = material.diffuse.contents
                let isFace = SleepEyeExplore.cgImage(from: contents).map { $0.width >= 256 } ?? (contents is MTLTexture)
                if isFace { found = material; stop.pointee = true; return }
            }
        }
        return try #require(found)
    }

    /// 앱 카메라로 오프스크린 렌더(배경 투명). `modifiers` 를 주면 그동안만 얼굴 재질의 셰이더를 갈아 끼운다(.some(nil) = 셰이더 없음).
    static func render(_ scene: SCNScene, size: CGSize, antialiasing: SCNAntialiasingMode = .multisampling4X,
                       modifiers: [SCNShaderModifierEntryPoint: String]?? = nil, at time: TimeInterval = 0) throws -> CGImage {
        let material = try faceMaterial(scene)
        let saved = material.shaderModifiers
        if let modifiers { material.shaderModifiers = modifiers }
        defer { if modifiers != nil { material.shaderModifiers = saved } }
        let renderer = SCNRenderer(device: try #require(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        let shot = renderer.snapshot(atTime: time, with: size, antialiasingMode: antialiasing)
        return try #require(shot.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.cgImage)
    }

    /// 그림 자신의 색공간 그대로의 RGBA8 프리멀티 바이트(색 변환 없음 — 높이 지도를 되읽을 때).
    static func rawRGBA(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return px
    }

    static func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func linearToByte(_ v: Double) -> Int {
        let x = min(max(v, 0), 1)
        return Int(((x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055) * 255).rounded())
    }

    /// 몸 높이 지도 셰이더: R = t, G = fract(16t) — 8비트 두 채널로 1/4096 정밀도(아트 스크립트 heightMap 과 같은 꼴).
    static let heightModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: RainbowAingFinish.geometryShader,
        .fragment: "#pragma varyings\nfloat3 rbP;\n#pragma body\n"
            + String(format: "float rbT = clamp((%.6f - in.rbP.y) / %.6f, 0.0, 1.0);\n", RainbowAingArt.bodyTop, RainbowAingArt.bodyHeight)
            + "_output.color = float4(rbT, fract(rbT * 16.0), 0.0, 1.0);\n",
    ]

    static func decodeHeight(_ px: [UInt8], _ i: Int) -> Double {
        let coarse = srgbToLinear(Double(px[i * 4]) / 255), fine = srgbToLinear(Double(px[i * 4 + 1]) / 255)
        return ((coarse * 16 - fine).rounded() + fine) / 16
    }

    /// 라벤더 렌더(셰이더 없음)에서 '안쪽 피부' 픽셀: 그 자리와 반경 `radius` 안이 전부 불투명한 피부(isGoldSkin).
    /// `pureHue` 를 주면 라벤더 색상(OKLab, 피부 중앙값 ± 그 폭)까지 요구한다 — 눈썹 · 속눈썹의 옅은 붓 자국(피부 판정은 지나지만 갈색이
    /// 섞인 픽셀)을 빼서, 떠돌이 점 잣대가 얼굴 그림의 결이 아니라 **띠 색이 틀린 점**만 보게 한다.
    static func interiorSkin(_ lavender: [UInt8], width w: Int, height h: Int, radius: Int, pureHue: Double? = nil) -> [Bool] {
        var skin = [Bool](repeating: false, count: w * h)
        var hues = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) where lavender[i * 4 + 3] == 255 {
            skin[i] = GoldAingFinish.isGoldSkin(Int(lavender[i * 4]), Int(lavender[i * 4 + 1]), Int(lavender[i * 4 + 2]))
            if skin[i], pureHue != nil { hues[i] = V0359RainbowArtTests.oklch(lavender[i * 4], lavender[i * 4 + 1], lavender[i * 4 + 2]).h }
        }
        if let band = pureHue {
            let median = (0..<(w * h)).filter { skin[$0] }.map { hues[$0] }.sorted()
            let centre = median.isEmpty ? 0 : median[median.count / 2]
            for i in 0..<(w * h) where skin[i] && V0359RainbowArtTests.hueDistance(hues[i], centre) > band { skin[i] = false }
        }
        var out = [Bool](repeating: false, count: w * h)
        for y in radius..<(h - radius) { for x in radius..<(w - radius) where skin[y * w + x] {
            var all = true
            outer: for dy in -radius...radius { for dx in -radius...radius where !skin[(y + dy) * w + x + dx] { all = false; break outer } }
            out[y * w + x] = all
        } }
        return out
    }

    /// 떠돌이 점 세기: 안쪽 피부 픽셀의 OKLab 색상이 둘레(반경 3, 안쪽 피부만, 자기 제외)의 원형 평균에서 15° 넘게 벗어나면 점.
    /// 무지개 기울기는 앱 구도에서도 픽셀당 1.5° 안팎이라 매끈한 띠는 안 걸리고, 다른 띠 색 한 점(수십 도)만 걸린다.
    static func speckCount(_ image: CGImage, interior: [Bool]) -> Int {
        speckPixels(image, interior: interior).count
    }

    static func speckPixels(_ image: CGImage, interior: [Bool]) -> [(x: Int, y: Int, hue: Double, mean: Double)] {
        let w = image.width, h = image.height, px = V0354GoldAingArtTests.rgba(image)
        var hue = [Double](repeating: 0, count: w * h), chroma = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) where interior[i] {
            let c = V0359RainbowArtTests.oklch(px[i * 4], px[i * 4 + 1], px[i * 4 + 2])
            hue[i] = c.h; chroma[i] = c.C
        }
        var found: [(x: Int, y: Int, hue: Double, mean: Double)] = []
        for y in 3..<(h - 3) { for x in 3..<(w - 3) where interior[y * w + x] && chroma[y * w + x] > 0.03 {
            var sx = 0.0, sy = 0.0
            for dy in -3...3 { for dx in -3...3 where (dx != 0 || dy != 0) && interior[(y + dy) * w + x + dx] {
                let hh = hue[(y + dy) * w + x + dx] * .pi / 180
                sx += cos(hh); sy += sin(hh)
            } }
            var mean = atan2(sy, sx) * 180 / .pi
            if mean < 0 { mean += 360 }
            if V0359RainbowArtTests.hueDistance(hue[y * w + x], mean) > 15 { found.append((x, y, hue[y * w + x], mean)) }
        } }
        return found
    }

    // MARK: ① 마감이 선다

    @Test("무지개 씬: 얼굴 재질에 몸 셰이더 · 디퓨즈 = 밝기 맵 합성(피부만) · 후광 36칸 — 아잉·황금 씬에는 셰이더도 무지개 표식도 없다")
    func finishIsApplied() throws {
        let scene = try Self.scene()
        let material = try Self.faceMaterial(scene)
        #expect(material.lightingModel == .constant)
        #expect(material.shaderModifiers?[.fragment] == RainbowAingFinish.fragmentShader)
        #expect(material.shaderModifiers?[.geometry] == RainbowAingFinish.geometryShader)
        for other in [Self.aing, Self.gold] {
            let otherScene = try Self.scene(other)
            #expect((try Self.faceMaterial(otherScene).shaderModifiers ?? [:]).isEmpty, "\(other.id) 에 무지개 셰이더가 걸렸다")
            #expect(Self.halo(otherScene) == nil, "\(other.id) 에 무지개 후광이 섰다")
        }
        #expect(scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true) == nil, "무지개에 금 후광이 섰다")

        // 디퓨즈: 라벤더 원본의 피부 텍셀만 밝기 맵 텍셀로, 장식은 그대로.
        let original = SleepEyeExplore.rgbaBuffer(try V0354GoldAing3DTests.faceImage(try Self.scene(Self.aing)))
        let face = SleepEyeExplore.rgbaBuffer(try V0354GoldAing3DTests.faceImage(scene))
        let shade = SleepEyeExplore.rgbaBuffer(try V0359RainbowArtTests.image(RainbowAingArt.shadeResourceName))
        var skin = 0, skinOff = 0, decoration = 0, decorationChanged = 0
        for o in stride(from: 0, to: original.count, by: 4) {
            if GoldAingFinish.isGoldSkin(Int(original[o]), Int(original[o + 1]), Int(original[o + 2])) {
                skin += 1
                if (0..<3).contains(where: { abs(Int(face[o + $0]) - Int(shade[o + $0])) > 2 }) { skinOff += 1 }
            } else {
                decoration += 1
                if (0..<3).contains(where: { abs(Int(face[o + $0]) - Int(original[o + $0])) > 2 }) { decorationChanged += 1 }
            }
        }
        #expect(skin > 100_000 && skinOff == 0, "피부 \(skin) 중 밝기 맵과 다른 텍셀 \(skinOff)")
        #expect(decoration > 1_000 && decorationChanged == 0, "장식 \(decoration) 중 바뀐 텍셀 \(decorationChanged)")

        // 후광: 캐릭터 노드 아래 표식 + 칸 36개(금과 같은 판 규약 · 같은 재질 이름 · 같은 카테고리 비트), 그림은 무지개 칸.
        let marker = try #require(Self.halo(scene))
        #expect(marker.parent === (try V0354GoldAing3DTests.character(scene)))
        #expect(marker.childNodes.count == 36 && marker.categoryBitMask == GoldAingFinish.haloCategoryBit)
        let cells = try #require(RainbowAingFinish.haloCellImages())
        for (index, cell) in marker.childNodes.enumerated() {
            let plane = try #require(cell.geometry as? SCNPlane)
            #expect(abs(plane.width - 3.391472) < 0.001 && abs(plane.height - 3.391472) < 0.001)
            #expect(cell.renderingOrder == -1 && cell.categoryBitMask == GoldAingFinish.haloCategoryBit)
            #expect(cell.constraints?.first is SCNBillboardConstraint)
            let m = try #require(plane.firstMaterial)
            #expect(m.name == GoldAingFinish.haloMaterialName && m.blendMode == .alpha && !m.writesToDepthBuffer && !m.readsFromDepthBuffer)
            let isRainbowCell = (m.diffuse.contents as AnyObject) === (cells[index] as AnyObject)
            #expect(isRainbowCell, "칸 \(index) 의 그림이 무지개 칸이 아니다")
        }
        // 몸 크기 계산에 안 낀다(카메라 · 바운딩박스가 아잉과 같다).
        let plain = try Self.scene(Self.aing)
        let camera = try #require(V0354GoldAing3DTests.cameraNode(scene)), plainCamera = try #require(V0354GoldAing3DTests.cameraNode(plain))
        #expect(simd_distance(camera.simdPosition, plainCamera.simdPosition) < 1e-4, "후광이 프레이밍을 밀었다")
        let box = try V0354GoldAing3DTests.wrapper(scene).boundingBox, plainBox = try V0354GoldAing3DTests.wrapper(plain).boundingBox
        #expect(abs((box.max.y - box.min.y) - (plainBox.max.y - plainBox.min.y)) < 0.01 && abs((box.max.x - box.min.x) - (plainBox.max.x - plainBox.min.x)) < 0.01)
    }

    // MARK: ② GPU 셰이더 = 기준 구현

    @Test("셰이더 결과가 기준 구현(높이 · 밝기 → 색)과 같다 — 안쪽 피부 조각마다 맞대기 · 뒤집은 높이(기준선)는 걸린다")
    func shaderMatchesTheReferenceFormula() throws {
        let scene = try Self.scene()
        try #require(Self.halo(scene)).isHidden = true
        let size = CGSize(width: 280, height: 340)
        let rainbow = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size, antialiasing: .none))
        let lavender = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size, antialiasing: .none, modifiers: .some(nil)))
        let heights = Self.rawRGBA(try Self.render(scene, size: size, antialiasing: .none, modifiers: Self.heightModifiers))
        let w = Int(size.width), h = Int(size.height)
        let interior = Self.interiorSkin(lavender, width: w, height: h, radius: 1)
        var compared = 0, within = 0, peak = 0, flippedFar = 0
        var tMin = 1.0, tMax = 0.0
        for i in 0..<(w * h) where interior[i] {
            let lin = SIMD3(Self.srgbToLinear(Double(lavender[i * 4]) / 255), Self.srgbToLinear(Double(lavender[i * 4 + 1]) / 255),
                            Self.srgbToLinear(Double(lavender[i * 4 + 2]) / 255))
            let dL = RainbowAingArt.oklabLightness(linear: lin) - RainbowAingArt.lightnessReference
            let t = Self.decodeHeight(heights, i)
            tMin = min(tMin, t); tMax = max(tMax, t)
            let expected = RainbowAingArt.bodyColorLinear(heightT: t, dL: dL)
            let diff = (0..<3).map { abs(Self.linearToByte(expected[$0]) - Int(rainbow[i * 4 + $0])) }.max() ?? 255
            compared += 1
            if diff <= 3 { within += 1 }
            peak = max(peak, diff)
            let flipped = RainbowAingArt.bodyColorLinear(heightT: 1 - t, dL: dL)
            if (0..<3).map({ abs(Self.linearToByte(flipped[$0]) - Int(rainbow[i * 4 + $0])) }).max()! > 12 { flippedFar += 1 }
        }
        print("[v0359-3d] 셰이더 vs 기준 구현: 안쪽 피부 \(compared)px 중 ≤3 \(within) · 최대 \(peak) · 높이 범위 \(String(format: "%.3f…%.3f", tMin, tMax)) · 뒤집은 높이 >12 \(flippedFar)")
        #expect(compared > 10_000, "맞댄 조각이 \(compared) 개뿐")
        #expect(within * 1000 >= compared * 995, "≤3 인 조각 \(within)/\(compared) — 셰이더가 기준 구현과 갈렸다")
        #expect(peak <= 10, "최대 차 \(peak)")
        #expect(tMin < 0.2 && tMax > 0.8, "높이 지도가 몸 위아래를 덮지 않는다(\(tMin)…\(tMax))")
        #expect(flippedFar * 2 > compared, "기준선이 안 갈린다: 뒤집은 높이로도 \(compared - flippedFar) 조각이 맞는다")
    }

    // MARK: ③ 떠돌이 삼각형 점

    /// 금처럼 UV 공간에 구운 판(기준선): 텍셀마다 메시 위치(덮는 삼각형들의 평균 — 시안 bakeField 와 같은 래스터)로 띠 색을 정해 피부 텍셀에
    /// 굽고 셰이더 없이 그린다. 다른 UV 섬의 텍셀을 같이 쓰는 삼각형이 그 자리에 엉뚱한 띠 색을 받는다.
    static func bakedRainbowFace(_ scene: SCNScene) throws -> CGImage {
        let face = try V0354GoldAing3DTests.faceImage(scene)
        let S = face.width
        let (ySum, weight) = try Self.uvRaster(scene, size: S)
        var px = SleepEyeExplore.rgbaBuffer(face)
        for i in 0..<(S * S) where weight[i] > 0
            && GoldAingFinish.isGoldSkin(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) {
            let lin = SIMD3(Self.srgbToLinear(Double(px[i * 4]) / 255), Self.srgbToLinear(Double(px[i * 4 + 1]) / 255),
                            Self.srgbToLinear(Double(px[i * 4 + 2]) / 255))
            let t = (RainbowAingArt.bodyTop - ySum[i] / weight[i]) / RainbowAingArt.bodyHeight
            let color = RainbowAingArt.bodyColorLinear(heightT: t, dL: RainbowAingArt.oklabLightness(linear: lin) - RainbowAingArt.lightnessReference)
            for c in 0..<3 { px[i * 4 + c] = UInt8(Self.linearToByte(color[c])) }
        }
        return try #require(GoldAingFinish.makeImage(px, width: S, height: S))
    }

    /// 얼굴 메시를 UV 공간(size²)에 래스터: 텍셀마다 덮는 삼각형들의 물체 좌표 y 합과 덮은 횟수(0 = 메시가 안 쓰는 UV 틈).
    static func uvRaster(_ scene: SCNScene, size S: Int) throws -> (ySum: [Double], weight: [Double]) {
        let geometry = try #require(SleepEyeExplore.faceGeometry(in: scene))
        let vs = try #require(geometry.sources(for: .vertex).first), ts = try #require(geometry.sources(for: .texcoord).first)
        let element = try #require(geometry.elements.first)
        #expect(vs.usesFloatComponents && vs.bytesPerComponent == 4 && ts.bytesPerComponent == 4)
        let n = vs.vectorCount
        var ys = [Float](repeating: 0, count: n), uv = [SIMD2<Float>](repeating: .zero, count: n)
        vs.data.withUnsafeBytes { raw in
            for i in 0..<n { ys[i] = raw.loadUnaligned(fromByteOffset: vs.dataOffset + i * vs.dataStride + 4, as: Float.self) }
        }
        ts.data.withUnsafeBytes { raw in
            for i in 0..<n {
                let b = ts.dataOffset + i * ts.dataStride
                uv[i] = SIMD2(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self))
            }
        }
        var index = [Int]()
        element.data.withUnsafeBytes { raw in
            for k in 0..<(element.primitiveCount * 3) {
                index.append(element.bytesPerIndex == 2 ? Int(raw.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self))
                                                         : Int(raw.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self)))
            }
        }
        var ySum = [Double](repeating: 0, count: S * S), weight = [Double](repeating: 0, count: S * S)
        for t in stride(from: 0, to: index.count, by: 3) {
            let i0 = index[t], i1 = index[t + 1], i2 = index[t + 2]
            let a = uv[i0] * Float(S), b = uv[i1] * Float(S), c = uv[i2] * Float(S)
            let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            if abs(area) < 1e-12 { continue }
            let x0 = max(0, Int(floor(min(a.x, b.x, c.x) - 0.5))), x1 = min(S - 1, Int(ceil(max(a.x, b.x, c.x) - 0.5)))
            let y0 = max(0, Int(floor(min(a.y, b.y, c.y) - 0.5))), y1 = min(S - 1, Int(ceil(max(a.y, b.y, c.y) - 0.5)))
            if x0 > x1 || y0 > y1 { continue }
            for y in y0...y1 { for x in x0...x1 {
                let px = Float(x) + 0.5, py = Float(y) + 0.5
                let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
                let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
                let w2 = 1 - w0 - w1
                if w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4 { continue }
                ySum[y * S + x] += Double(ys[i0] * w0 + ys[i1] * w1 + ys[i2] * w2)
                weight[y * S + x] += 1
            } }
        }
        return (ySum, weight)
    }

    @Test("떠돌이 삼각형 점: 창 크기(280×340) · 울트라(945²)에서 셰이더 경로는 0 — UV 에 구운 판(기준선)은 울트라에서 점이 난다")
    func noStrayTriangleSpecks() throws {
        let scene = try Self.scene()
        try #require(Self.halo(scene)).isHidden = true
        let material = try Self.faceMaterial(scene)
        let face = material.diffuse.contents
        let baked = try Self.bakedRainbowFace(scene)
        var report = [String]()
        for size in [CGSize(width: 280, height: 340), CGSize(width: 945, height: 945)] {
            let w = Int(size.width), h = Int(size.height)
            let lavender = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size, modifiers: .some(nil)))
            let interior = Self.interiorSkin(lavender, width: w, height: h, radius: 3, pureHue: 15)
            let shaderImage = try Self.render(scene, size: size)
            let shaderSpecks = Self.speckPixels(shaderImage, interior: interior)
            let shader = shaderSpecks.count
            if !shaderSpecks.isEmpty {
                print("[v0359-3d] 셰이더 점 \(w)×\(h): \(shaderSpecks.prefix(10).map { "(\($0.x),\($0.y)) h \(Int($0.hue))° vs \(Int($0.mean))°" })")
                if let dir = ProcessInfo.processInfo.environment["CHECK_V0359_STILLS_DIR"] {
                    try? NSBitmapImageRep(cgImage: shaderImage).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("debug-speck-\(w).png"))
                }
            }
            material.diffuse.contents = baked
            let bakedCount = Self.speckCount(try Self.render(scene, size: size, modifiers: .some(nil)), interior: interior)
            material.diffuse.contents = face
            report.append("\(w)×\(h): 셰이더 \(shader) · 구운 판 \(bakedCount) (안쪽 피부 \(interior.filter { $0 }.count)px)")
            #expect(shader == 0, "\(w)×\(h): 셰이더 경로에 떠돌이 점 \(shader)")
            if w == 945 { #expect(bakedCount > 0, "기준선이 안 갈린다: 구운 판에서도 점 0(울트라)") }
        }
        print("[v0359-3d] 떠돌이 점 — " + report.joined(separator: " / "))
    }

    // MARK: ④ 후광 칸이 몸 요를 따른다

    @Test("후광 칸: 몸 요 0 · 40 · 90 · 180 · −40° 에서 그 칸 하나만 몸 자리에 선다(금과 같은 고르기) · 교체로 세운 무지개도 같다")
    func haloCellFollowsYaw() throws {
        let scene = try Self.scene()
        let facing = try V0355GoldHaloYawTests.facing(scene)
        let marker = try #require(Self.halo(scene))
        let shooter = try V0355GoldHaloYawTests.Shooter(scene, pointOfView: V0354GoldAing3DTests.cameraNode(scene))
        func visible() -> [Int] {
            let anchor = marker.presentation.simdWorldPosition
            return marker.childNodes.enumerated().compactMap { index, node in
                let world = node.presentation.simdWorldTransform
                let size = simd_length(SIMD3(world.columns.0.x, world.columns.0.y, world.columns.0.z))
                return simd_distance(node.presentation.simdWorldPosition, anchor) < 0.5 && size > 0.01 ? index : nil
            }
        }
        for (degrees, cell) in [(0.0, 0), (40, 4), (90, 9), (180, 18), (-40, 32)] {
            facing.eulerAngles = SCNVector3(0, CGFloat(degrees * .pi / 180), 0)
            _ = try shooter.shot(at: 0)
            #expect(visible() == [cell], "요 \(degrees)° 에서 칸 \(visible())")
        }
        // 울트라 교체 경로(makeCharacterNode)로 세운 무지개.
        let plain = try Self.scene(Self.aing)
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(plain), sceneRoot: plain.rootNode, view: nil)
        #expect(engine.swapCharacter(to: Self.rainbow, in: plain) != nil)
        let swappedMarker = try #require(Self.halo(plain))
        #expect(swappedMarker.childNodes.count == 36)
        try V0355GoldHaloYawTests.facing(plain).eulerAngles = SCNVector3(0, CGFloat(90 * Double.pi / 180), 0)
        _ = try V0355GoldHaloYawTests.Shooter(plain, pointOfView: V0354GoldAing3DTests.cameraNode(plain)).shot(at: 0)
        let anchor = swappedMarker.presentation.simdWorldPosition
        let shown = swappedMarker.childNodes.enumerated().compactMap { index, node -> Int? in
            let world = node.presentation.simdWorldTransform
            return simd_distance(node.presentation.simdWorldPosition, anchor) < 0.5
                && simd_length(SIMD3(world.columns.0.x, world.columns.0.y, world.columns.0.z)) > 0.01 ? index : nil
        }
        #expect(shown == [9], "교체로 세운 무지개 90° 에서 칸 \(shown)")
    }

    // MARK: ⑤ 감은 눈

    /// 눈 앵커(화면 왼눈)를 렌더 좌표로 — 원점 좌상단.
    static func eyePixel(_ scene: SCNScene, size: CGSize) throws -> (Int, Int) {
        let renderer = SCNRenderer(device: try #require(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        let character = try V0354GoldAing3DTests.character(scene)
        let world = character.convertPosition(CheckCharacter3DScene.closedEyeAnchors[0].position, to: nil)
        let p = renderer.projectPoint(world)
        // projectPoint 는 렌더 크기의 뷰포트 좌표(원점 왼쪽 아래)다.
        return (Int(p.x.rounded()), Int((size.height - p.y).rounded()))
    }

    static func averageColor(_ px: [UInt8], width w: Int, at point: (Int, Int), radius: Int = 1) -> (UInt8, UInt8, UInt8) {
        var s = [0, 0, 0], n = 0
        for dy in -radius...radius { for dx in -radius...radius {
            let o = ((point.1 + dy) * w + point.0 + dx) * 4
            for c in 0..<3 { s[c] += Int(px[o + c]) }
            n += 1
        } }
        return (UInt8(s[0] / n), UInt8(s[1] / n), UInt8(s[2] / n))
    }

    @Test("감은 눈(엔진 · CGImage 경로): 덮인 눈 자리가 밝기 맵 텍셀 → 렌더에서 그 높이의 무지개 · 셰이더는 그대로 · 깨면 눈이 돌아온다")
    func closedEyesAreRainbow() throws {
        var now = Date(timeIntervalSince1970: 90_000)
        let engine = ReactionEngine(clock: { now })
        let scene = try Self.scene()
        let material = try Self.faceMaterial(scene)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let shade = SleepEyeExplore.rgbaBuffer(try V0359RainbowArtTests.image(RainbowAingArt.shadeResourceName))
        let eyeX = 235, eyeY = 392   // 오른눈 아틀라스 픽셀(512 기준 — 금 시험과 같은 자리)
        let awake = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        #expect(SleepEyeTexture.isEye(awake.0, awake.1, awake.2), "기준선: 뜬 눈 자리가 눈이 아니다")
        let size = CGSize(width: 280, height: 340)
        let eye = try Self.eyePixel(scene, size: size)
        let awakeRender = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size))
        let awakeColor = Self.averageColor(awakeRender, width: Int(size.width), at: eye)

        engine.request(.drowsy)
        #expect(engine.state == .sleeping)
        let asleep = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        let o = (eyeY * 512 + eyeX) * 4
        #expect(GoldAingFinish.isGoldSkin(asleep.0, asleep.1, asleep.2), "감은 눈 자리 \(asleep) 가 피부 판정 밖 — 셰이더가 무지개로 못 칠한다")
        #expect(abs(asleep.0 - Int(shade[o])) <= 2 && abs(asleep.1 - Int(shade[o + 1])) <= 2 && abs(asleep.2 - Int(shade[o + 2])) <= 2,
                "감은 눈 자리 \(asleep) ≠ 밝기 맵 \((shade[o], shade[o + 1], shade[o + 2])) — 라벤더 원본에서 굽고 합성하지 않았다")
        #expect(material.shaderModifiers?[.fragment] == RainbowAingFinish.fragmentShader, "졸 때 셰이더가 빠졌다")
        let closedRender = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size))
        let closedColor = Self.averageColor(closedRender, width: Int(size.width), at: eye)
        let closed = V0359RainbowArtTests.oklch(closedColor.0, closedColor.1, closedColor.2)
        let open = V0359RainbowArtTests.oklch(awakeColor.0, awakeColor.1, awakeColor.2)
        // 기준선: 셰이더 없이(디퓨즈 그대로) 그리면 같은 자리가 라벤더다.
        let lavenderRender = V0354GoldAingArtTests.rgba(try Self.render(scene, size: size, modifiers: .some(nil)))
        let lavenderColor = Self.averageColor(lavenderRender, width: Int(size.width), at: eye)
        let lavender = V0359RainbowArtTests.oklch(lavenderColor.0, lavenderColor.1, lavenderColor.2)
        print(String(format: "[v0359-3d] 눈 자리(%d,%d): 뜬 눈 L %.2f · 감은 눈 L %.2f C %.3f h %.0f° · 셰이더 없이 h %.0f°",
                     eye.0, eye.1, open.L, closed.L, closed.C, closed.h, lavender.h))
        #expect(open.L < 0.5, "기준선: 뜬 눈 자리가 어둡지 않다(L \(open.L)) — 눈 좌표가 틀렸다")
        #expect(closed.L > 0.75 && closed.C > 0.05, "감은 눈 자리 L \(closed.L) C \(closed.C) — 무지개 피부가 아니다")
        #expect(V0359RainbowArtTests.hueDistance(closed.h, lavender.h) > 60, "감은 눈 자리 색상 \(closed.h)° 가 라벤더(\(lavender.h)°)와 같다")
        #expect(V0359RainbowArtTests.hueDistance(lavender.h, 290) < 30, "기준선이 라벤더가 아니다(\(lavender.h)°)")

        engine.request(.wake)
        let woken = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        #expect(SleepEyeTexture.isEye(woken.0, woken.1, woken.2), "깬 뒤 눈이 안 돌아왔다")
        now = now.addingTimeInterval(1)
    }

    @Test("감은 눈(뷰가 있는 GPU 텍스처 경로 — 깜빡임이 쓰는 길): 얼굴이 MTLTexture 로 바뀌어도 셰이더가 표본을 읽어 눈 자리가 무지개다")
    func blinkOnGPUTexturePathIsRainbow() throws {
        let engine = ReactionEngine()
        let scene = try Self.scene()
        let size = CGSize(width: 280, height: 340)
        let view = SCNView(frame: NSRect(origin: .zero, size: NSSize(width: size.width / 2, height: size.height / 2)))
        view.scene = scene
        view.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        view.antialiasingMode = .none
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: view)
        #expect(engine.hasFaceTextures, "뷰가 있는데 얼굴 GPU 텍스처가 안 섰다(이 시험이 그 길을 안 지난다)")
        let eye = try Self.eyePixel(scene, size: size)
        engine.request(.drowsy)
        #expect(engine.faceDiffuseTextureAssignments > 0, "감은 눈이 GPU 텍스처로 안 바뀌었다")
        let shot = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let px = V0354GoldAingArtTests.rgba(shot)
        let scale = Double(shot.width) / Double(size.width)
        let point = (Int(Double(eye.0) * scale), Int(Double(eye.1) * scale))
        let color = Self.averageColor(px, width: shot.width, at: point)
        let c = V0359RainbowArtTests.oklch(color.0, color.1, color.2)
        print(String(format: "[v0359-3d] GPU 텍스처 경로 감은 눈(%d×%d @%d,%d): L %.2f C %.3f h %.0f°", shot.width, shot.height, point.0, point.1, c.L, c.C, c.h))
        #expect(c.L > 0.75 && c.C > 0.05 && V0359RainbowArtTests.hueDistance(c.h, 290) > 60, "GPU 텍스처 경로 감은 눈 자리가 무지개가 아니다(\(c))")
        engine.request(.wake)
    }

    // MARK: ⑥ 울트라

    @Test("엔진은 아잉 · 황금 · 무지개를 가른다 — 교체 · 원복 왕복에서도 무지개 표식 · 셰이더가 따라온다")
    func engineTellsRainbowApart() throws {
        let engine = ReactionEngine()
        let scene = try Self.scene()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        #expect(engine.currentCharacterID == CharacterCatalog.rainbowAingID)
        let stashed = try #require(engine.swapCharacter(to: Self.gold, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.goldAingID, "황금으로 갈아입었는데 \(engine.currentCharacterID)")
        let goldModifiers = try Self.faceMaterial(scene).shaderModifiers ?? [:]
        #expect(Self.halo(scene) == nil && goldModifiers.isEmpty)
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.rainbowAingID)
        let restoredFragment = try Self.faceMaterial(scene).shaderModifiers?[.fragment]
        #expect(Self.halo(scene) != nil && restoredFragment == RainbowAingFinish.fragmentShader)
        _ = try #require(engine.swapCharacter(to: Self.aing, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    }

    @Test("울트라: 무지개 착용자가 아잉 · 황금에게 맞으면 갈아입고 끝나면 무지개로 · 아잉 착용자가 무지개에게 맞으면 후광 달린 무지개가 선다")
    func ultraSwapsTheRainbow() throws {
        // ★ 원복 단언은 '보낸이 = 아잉'(무지개 쪽) · '받는이 = 아잉'(둘째 고리) 갈래에서만 한다: 이 하네스는 격발이 덮는 순간 패널 자기 뷰가
        //   새 씬을 세우는데(지연 마운트), 그 씬은 시험 프로세스의 `.standard` 선택(= 아잉)으로 선다. 그래서 보낸이가 아잉이 아니면 둘째
        //   갈아입기가 그 새 아잉 씬에서 떼어 낸 노드를 맡아 원복이 아잉이 된다 — 앱에서는 그 씬이 착용 캐릭터로 서므로 생기지 않는 하네스 결이다.
        //   (금 V0354 시험도 같은 이유로 '아잉에게 맞음' · '아잉이 맞음' 두 갈래만 원복을 잰다.)
        for sender in [nil, CharacterCatalog.goldAingID] as [String?] {
            let controller = try V0354UltraHarness.mounted(receiver: Self.rainbow)
            #expect(controller.engine.currentCharacterID == CharacterCatalog.rainbowAingID, "기준선이 무지개가 아니다")
            var atCover: String?
            controller.onUltraWillCoverScreen = { [weak controller] in atCover = controller?.engine.currentCharacterID }
            controller.handleReceivedPokes([V0354UltraHarness.ultra(from: sender)])
            #expect(controller.isUltraActive)
            #expect(atCover == (sender ?? CharacterCatalog.builtInAingID), "화면을 덮을 때 \(atCover ?? "nil") — 보낸이 \(sender ?? "아잉")")
            controller.endUltraTakeover()
            if sender == nil {
                #expect(controller.engine.currentCharacterID == CharacterCatalog.rainbowAingID, "원복이 무지개를 안 돌려놨다")
            }
            controller.updateWorking(false)
        }
        for receiver in [Self.aing, Self.gold] {
            let controller = try V0354UltraHarness.mounted(receiver: receiver)
            controller.handleReceivedPokes([V0354UltraHarness.ultra(from: CharacterCatalog.rainbowAingID)])
            #expect(controller.isUltraActive)
            #expect(controller.engine.currentCharacterID == CharacterCatalog.rainbowAingID,
                    "\(receiver.id) 화면에 무지개가 안 섰다(\(controller.engine.currentCharacterID))")
            let scene = try #require(controller.engine.attachedScene)
            #expect(Self.halo(scene) != nil, "찌른 사람의 무지개 아잉이에 후광이 없다")
            #expect((try Self.faceMaterial(scene).shaderModifiers?[.fragment]) == RainbowAingFinish.fragmentShader, "울트라 무지개에 셰이더가 없다")
            controller.endUltraTakeover()
            if receiver.id == CharacterCatalog.builtInAingID {
                #expect(controller.engine.currentCharacterID == receiver.id, "원복 \(controller.engine.currentCharacterID) ≠ \(receiver.id)")
            }
            controller.updateWorking(false)
        }
    }

    // MARK: ⑦ 클릭

    @Test("몸 클릭 hitTest 는 무지개 후광 판을 뺀다 — 몸 밖 · 후광 안 점은 안 맞고 몸 가운데는 맞는다(마스크 없으면 판이 맞는다)")
    func bodyHitTestIgnoresTheHalo() throws {
        let scene = try Self.scene()
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 280, height: 340))
        view.scene = scene
        view.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = view.snapshot()
        let wrapper = try V0354GoldAing3DTests.wrapper(scene)
        let outside = NSPoint(x: 8, y: 170), center = NSPoint(x: 140, y: 170)
        func hits(_ point: NSPoint, mask: Bool) -> [SCNHitTestResult] {
            var options: [SCNHitTestOption: Any] = [.rootNode: wrapper, .boundingBoxOnly: false, .ignoreHiddenNodes: true]
            if mask { options[.categoryBitMask] = GoldAingFinish.bodyHitCategoryMask }
            return view.hitTest(point, options: options)
        }
        #expect(hits(outside, mask: true).isEmpty, "몸 밖 · 후광 안 점이 몸으로 맞았다")
        #expect(hits(center, mask: true).contains { $0.node.categoryBitMask != GoldAingFinish.haloCategoryBit }, "몸 가운데가 안 맞는다")
        // 기준선: 같은 자리에 장치 없는 판을 세우면(마스크 없이) 맞는다 — 점이 판 위라는 증거.
        let marker = try #require(Self.halo(scene))
        let side = try #require(marker.childNodes.first?.geometry as? SCNPlane).width
        let probe = SCNNode(geometry: SCNPlane(width: side, height: side))
        probe.position = marker.position
        try #require(marker.parent).addChildNode(probe)
        _ = view.snapshot()
        #expect(hits(outside, mask: false).contains { $0.node === probe }, "기준선: 몸 밖 점에서 장치 없는 판이 안 맞는다")
        probe.removeFromParentNode()
    }

    // MARK: ⑧ 그릴 수 있다

    @Test("그릴 수 있는 목록 · 3D 마감 판정: 번들 그대로 무지개가 든다 · 마감 그림 하나만 빠져도 못 그린다")
    func drawableInTheBundle() {
        #expect(RainbowAingFinish.isDrawable())
        #expect(CheckMascotAssets.drawableCharacterIDs().contains(CharacterCatalog.rainbowAingID))
        #expect(!RainbowAingArt.isDrawable(on: .mac) { $0 != RainbowAingArt.shadeResourceName })
        #expect(!RainbowAingArt.isDrawable(on: .mac) { $0 != RainbowAingArt.haloResourceName })
        #expect(RainbowAingFinish.portraitURL(for: .neutral)?.lastPathComponent == "aing_rainbow-neutral.png")
        #expect(RainbowAingFinish.portraitURL(for: .negative)?.lastPathComponent == "aing_rainbow-negative.png")
    }

    // MARK: ⑨ 미리보기 스틸(사람이 보는 그림 — 기본 실행에서는 꺼져 있다)

    nonisolated static let stillsDirectory = ProcessInfo.processInfo.environment["CHECK_V0359_STILLS_DIR"]

    static func onBackground(_ image: CGImage, _ rgb: (Double, Double, Double)) throws -> CGImage {
        let w = image.width, h = image.height
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return try #require(ctx.makeImage())
    }

    @Test("미리보기: 앱 구도 어둡·밝 바탕 · 요 0/40/90/180 · 울트라 945² · 감은 눈 스틸", .enabled(if: stillsDirectory != nil))
    func writeStills() throws {
        let dir = URL(fileURLWithPath: try #require(Self.stillsDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dark = (28.0 / 255, 28.0 / 255, 30.0 / 255), light = (242.0 / 255, 242.0 / 255, 247.0 / 255)
        func write(_ image: CGImage, _ name: String) throws {
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
        }
        var tiles: [(String, CGImage, CGImage)] = []
        let app = CGSize(width: 280, height: 340)
        for degrees in [0, 40, 90, 180] {
            let scene = try Self.scene()
            try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(Double(degrees) * .pi / 180), 0)
            let raw = try Self.render(scene, size: app)
            let d = try Self.onBackground(raw, dark), l = try Self.onBackground(raw, light)
            try write(raw, "rainbow-yaw\(degrees)-raw.png"); try write(d, "rainbow-yaw\(degrees)-dark.png"); try write(l, "rainbow-yaw\(degrees)-light.png")
            tiles.append(("yaw\(degrees)", d, l))
        }
        // 감은 눈 비교용(같은 엔진 경로의 아잉 · 황금 — 덮인 눈 둘레 결이 무지개만의 것인지 본다).
        for other in [Self.aing, Self.gold] {
            let scene = try Self.scene(other)
            let engine = ReactionEngine()
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            engine.request(.drowsy)
            try write(try Self.onBackground(try Self.render(scene, size: CGSize(width: 945, height: 945)), dark),
                      "compare-\(other.id)-ultra945-closed-eyes-dark.png")
        }
        // 감은 눈(엔진 경로).
        do {
            let scene = try Self.scene()
            let engine = ReactionEngine()
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            engine.request(.drowsy)
            let raw = try Self.render(scene, size: app)
            let d = try Self.onBackground(raw, dark), l = try Self.onBackground(raw, light)
            try write(d, "rainbow-closed-eyes-dark.png"); try write(l, "rainbow-closed-eyes-light.png")
            tiles.append(("closed", d, l))
            let ultraClosed = try Self.render(scene, size: CGSize(width: 945, height: 945))
            try write(try Self.onBackground(ultraClosed, dark), "rainbow-ultra945-closed-eyes-dark.png")
        }
        // 울트라 크기.
        let ultra = try Self.render(try Self.scene(), size: CGSize(width: 945, height: 945))
        try write(try Self.onBackground(ultra, dark), "rainbow-ultra945-dark.png")
        try write(try Self.onBackground(ultra, light), "rainbow-ultra945-light.png")
        // 한 장 시트(위 어둡 · 아래 밝).
        let w = tiles.count * 280, h = 680
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (i, tile) in tiles.enumerated() {
            ctx.draw(tile.1, in: CGRect(x: i * 280, y: 340, width: 280, height: 340))
            ctx.draw(tile.2, in: CGRect(x: i * 280, y: 0, width: 280, height: 340))
        }
        try write(try #require(ctx.makeImage()), "rainbow-sheet.png")
    }
}
