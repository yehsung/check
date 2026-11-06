// 루비 아잉이(aing_ruby) 초상 생성기 (v0.3.78) — 맥 초상 두 장(192², 기본 · 시무룩)을 굽는다. 3D 마감은 앱(RubyAingFinish)이 한다.
// 시안 7차 Y5 '배 띠 · 6:4'(대표 결정 2026-11-06 #d_YgODZOIrIg5y). 몸 모양 · 몸 셰이더는 CheckCore `RubyAingShape.swift` 한 곳 —
// 이 생성기는 그 파일을 같이 컴파일해 앱과 **같은 식**으로 3D 를 그린다(몸 모양이 바뀌어 2D 초상을 다시 칠하는 방식으로는 못 만든다).
//
// 사용법(저장소 루트에서):
//   swiftc -O -parse-as-library -package-name check -o <임시>/make-ruby-aing scripts/make-ruby-aing.swift Sources/CheckCore/CharacterKit/RubyAingShape.swift
//   <임시>/make-ruby-aing                  Sources/check/Resources/aing_ruby-{neutral,negative}.png 를 쓴다.
//   <임시>/make-ruby-aing --out <폴더>     같은 두 장을 <폴더>/ 에 쓴다(저장소는 안 건드린다 — 같은 기계에서 두 번 돌려 바이트를 비교한다).
//
// 입력(읽기만): Sources/check/Resources/aing.scn(메시 · 얼굴 디퓨즈) · aing_rainbow-shade.png(밝기 맵) · aing-neutral.png · aing-negative.png(192² 아잉 초상).
// 방법:
//   ① 기본 = 앱 구도 정면 3D 렌더(몸 빚기 + 보석 셰이더 — 앱과 같은 글자)를 아잉 초상(aing-neutral.png)의 몸 상자(폭 · 바닥)에 맞춰 192² 로.
//   ② 시무룩 = 같은 렌더에서 **바뀌는 자리(눈썹 · 입)만** 아잉 시무룩 초상에서 가져와 얹는다: 두 아잉 초상의 차이로 자리를 잡고, 눈 두 점으로
//      맞춘 닮음 변환으로 옮기고, 그 자리의 바탕은 '얼굴 없는 몸' 렌더(셰이더 faceOff)로 지운 뒤 시무룩 초상의 비피부 화소를 얹는다.
//   창을 띄우지 않는다(오프스크린 SCNRenderer). 네트워크를 쓰지 않는다.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import simd

@main
struct MakeRubyAing {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var outDir = "Sources/check/Resources"
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1]; args.removeSubrange(i...(i + 1)) }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let res = "Sources/check/Resources"
        let neutral = Portrait.make(faceOff: false, res: res)
        let bare = Portrait.make(faceOff: true, res: res)
        let aingNeutral = Img.load(res + "/aing-neutral.png"), aingNegative = Img.load(res + "/aing-negative.png")
        let fitted = Portrait.fit(neutral.image, to: aingNeutral, box: Portrait.box(of: neutral.image))
        let fittedBare = Portrait.fit(bare.image, to: aingNeutral, box: Portrait.box(of: neutral.image))
        let negative = Portrait.negative(ruby: fitted, bare: fittedBare, aingNeutral: aingNeutral, aingNegative: aingNegative)
        Img.write(fitted, outDir + "/aing_ruby-neutral.png")
        Img.write(negative, outDir + "/aing_ruby-negative.png")
    }
}

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }

enum Img {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static func load(_ path: String) -> CGImage {
        guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { fail("못 읽음: \(path)") }
        return i
    }
    static func bytes(_ image: CGImage, space: CGColorSpace = sRGB) -> [UInt8] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return px
    }
    static func make(_ px: [UInt8], _ w: Int, _ h: Int, space: CGColorSpace = sRGB) -> CGImage {
        var p = px
        return p.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }
    static func write(_ image: CGImage, _ path: String) {
        guard let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { fail("못 씀: \(path)") }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { fail("PNG 실패: \(path)") }
        print("썼다: \(path) \(image.width)×\(image.height)")
    }
    static func toLin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func toSRGB(_ v: Double) -> Double { let c = min(max(v, 0), 1); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
    /// 앱 `GoldAingFinish.isGoldSkin` 과 같은 식(0…255).
    static func isSkin(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        let mx = max(r, g, b), mn = min(r, g, b), sat = mx == 0 ? 0 : (mx - mn) / mx
        var hue = 0.0
        if mx != mn {
            if mx == r { hue = 60 * ((g - b) / (mx - mn)) } else if mx == g { hue = 60 * ((b - r) / (mx - mn) + 2) } else { hue = 60 * ((r - g) / (mx - mn) + 4) }
            if hue < 0 { hue += 360 }
        }
        let l = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10
    }
}

enum Portrait {
    static let renderSize = 1024

    /// 앱 구도(정면) 3D 렌더 — 몸 빚기 + 보석 셰이더. 투명 배경 sRGB 프리멀티.
    static func make(faceOff: Bool, res: String) -> (image: CGImage, size: Int) {
        guard let scene = try? SCNScene(url: URL(fileURLWithPath: res + "/aing.scn"), options: nil) else { fail("aing.scn 을 못 읽었다") }
        scene.background.contents = NSColor.clear
        var bodyNode: SCNNode?
        scene.rootNode.enumerateHierarchy { n, s in if n.geometry != nil { bodyNode = n; s.pointee = true } }
        guard let body = bodyNode, let g = body.geometry, let material = g.materials.first else { fail("몸 메시가 없다") }
        // 디퓨즈: 원래 얼굴 텍스처의 피부 텍셀만 밝기 맵으로(앱 RainbowAingFinish.rainbowDiffuse 와 같은 합성).
        let shade = Img.load(res + "/aing_rainbow-shade.png")
        guard let original = decoded(material.diffuse.contents) else { fail("얼굴 디퓨즈가 없다") }
        let o = Img.bytes(original, space: CGColorSpaceCreateDeviceRGB()), s = Img.bytes(shade, space: CGColorSpaceCreateDeviceRGB())
        guard original.width == shade.width, original.height == shade.height else { fail("밝기 맵 크기가 디퓨즈와 다르다") }
        var comp = o
        for i in 0..<(original.width * original.height) where Img.isSkin(Double(o[i * 4]), Double(o[i * 4 + 1]), Double(o[i * 4 + 2])) {
            comp[i * 4] = s[i * 4]; comp[i * 4 + 1] = s[i * 4 + 1]; comp[i * 4 + 2] = s[i * 4 + 2]; comp[i * 4 + 3] = 255
        }
        material.lightingModel = .constant
        material.diffuse.contents = Img.make(comp, original.width, original.height, space: CGColorSpaceCreateDeviceRGB())
        material.shaderModifiers = [.geometry: RubyAingShader.geometry, .fragment: RubyAingShader.fragment(faceOff: faceOff)]
        material.setValue(SCNMaterialProperty(contents: shade), forKey: RubyAingShader.shadeMapKey)
        // 몸 빚기 칸(앱 RubyAingFinish.geometry(_:adding:) 와 같은 배치).
        let vs = g.sources(for: .vertex).first!, uv = g.sources(for: .texcoord).first!
        var pos = [SIMD3<Float>](repeating: .zero, count: vs.vectorCount)
        vs.data.withUnsafeBytes { raw in
            for i in 0..<vs.vectorCount {
                let b = vs.dataOffset + i * vs.dataStride
                pos[i] = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                               raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
            }
        }
        let baked = RubyAingShape.bake(pos)
        let n = pos.count
        var c1 = [Float](repeating: 0, count: n * 2), c2 = c1, c3 = c1
        for i in 0..<n {
            c1[i * 2] = baked.displacement[i].x; c1[i * 2 + 1] = baked.displacement[i].y
            c2[i * 2] = baked.displacement[i].z; c2[i * 2 + 1] = baked.edge[i]
            c3[i * 2] = baked.arm[i]; c3[i * 2 + 1] = baked.facet[i]
        }
        func src(_ a: [Float]) -> SCNGeometrySource {
            SCNGeometrySource(data: a.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        }
        let ng = SCNGeometry(sources: [vs, uv, src(c1), src(c2), src(c3)], elements: g.elements)
        ng.materials = g.materials
        // 카메라: 앱 구도(원래 몸 상자 — 몸을 빚기 전에 잰다).
        let (a, b) = scene.rootNode.boundingBox
        body.geometry = ng
        let mn = SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z)), mx = SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z))
        let center = (mn + mx) / 2, extent = max(mx.x - mn.x, mx.y - mn.y)
        let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.fieldOfView = 40; cam.camera!.zNear = 0.01; cam.camera!.zFar = 1000
        cam.simdPosition = SIMD3(center.x, center.y + extent * 0.55, mx.z + distance)
        cam.simdLook(at: SIMD3(center.x, center.y - extent * 0.16, center.z))
        scene.rootNode.addChildNode(cam)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        let shot = r.snapshot(atTime: 0, with: CGSize(width: renderSize, height: renderSize), antialiasingMode: .multisampling4X)
        return (straightened(shot), renderSize)
    }

    static func decoded(_ contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
        if let d = contents as? Data, let s = CGImageSourceCreateWithData(d as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
        if let i = contents as? NSImage { return i.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if let u = contents as? URL { return NSImage(contentsOf: u)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        return nil
    }

    /// 스냅숏의 '선형 프리멀티를 sRGB 로 부호화한' 반투명 화소를 바른 sRGB 프리멀티로(케이크 · 시안 렌더러와 같다).
    static func straightened(_ image: NSImage) -> CGImage {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fail("렌더 실패") }
        var px = Img.bytes(cg)
        for i in 0..<(cg.width * cg.height) {
            let a = Double(px[i * 4 + 3]) / 255
            if a >= 1 { continue }
            if a <= 0 { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; continue }
            for c in 0..<3 {
                let l = min(Img.toLin(Double(px[i * 4 + c]) / 255) / a, 1)
                px[i * 4 + c] = UInt8(min(255, (Img.toSRGB(l) * a * 255).rounded()))
            }
        }
        return Img.make(px, cg.width, cg.height)
    }

    static func box(of image: CGImage, threshold: UInt8 = 8) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        let px = Img.bytes(image), w = image.width, h = image.height
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > threshold { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        return (x0, x1, y0, y1)
    }

    /// 렌더(`box` = 몸 상자)를 아잉 초상의 몸 상자에 맞춘다 — 폭을 같게 · 바닥을 같게 · 가운데 맞춤(192², 다른 초상과 같은 몸 크기).
    static func fit(_ image: CGImage, to reference: CGImage, box b: (x0: Int, x1: Int, y0: Int, y1: Int)) -> CGImage {
        let rb = box(of: reference)
        let W = reference.width, H = reference.height
        let scale = Double(rb.x1 - rb.x0 + 1) / Double(b.x1 - b.x0 + 1)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: Img.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        // CG 는 아래가 원점: 그림 위쪽 행 y → CG y' = H − y.
        let srcCX = Double(b.x0 + b.x1 + 1) / 2, srcBottom = Double(b.y1 + 1)
        let dstCX = Double(rb.x0 + rb.x1 + 1) / 2, dstBottom = Double(rb.y1 + 1)
        let dw = Double(image.width) * scale, dh = Double(image.height) * scale
        let left = dstCX - srcCX * scale
        let topRow = dstBottom - srcBottom * scale                       // 그림 위쪽 행 좌표(위 원점)
        ctx.draw(image, in: CGRect(x: left, y: Double(H) - topRow - dh, width: dw, height: dh))
        return ctx.makeImage()!
    }

    /// 눈 두 점(진한 화소 덩어리 중심 — 얼굴 위 절반 · 좌우).
    static func eyes(_ image: CGImage) -> (SIMD2<Double>, SIMD2<Double>) {
        let px = Img.bytes(image), w = image.width, h = image.height
        let b = box(of: image)
        let cx = Double(b.x0 + b.x1) / 2
        var sL = SIMD2<Double>(0, 0), nL = 0.0, sR = SIMD2<Double>(0, 0), nR = 0.0
        let yTop = b.y0 + (b.y1 - b.y0) * 15 / 100, yBot = b.y0 + (b.y1 - b.y0) * 55 / 100
        for y in yTop..<yBot { for x in b.x0...b.x1 {
            let i = (y * w + x) * 4
            guard px[i + 3] > 250 else { continue }
            let l = (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255
            guard l < 0.22 else { continue }
            if Double(x) < cx { sL += SIMD2(Double(x), Double(y)); nL += 1 } else { sR += SIMD2(Double(x), Double(y)); nR += 1 }
        } }
        guard nL > 4, nR > 4 else { fail("눈을 못 찾았다(\(nL) · \(nR))") }
        _ = h
        return (sL / nL, sR / nR)
    }

    /// 시무룩: 아잉 두 초상이 다른 자리(눈썹 · 입)만 시무룩 초상에서 옮겨 얹는다. 나머지(눈 · 볼터치 · 보석 몸)는 루비 기본 그대로.
    static func negative(ruby: CGImage, bare: CGImage, aingNeutral: CGImage, aingNegative: CGImage) -> CGImage {
        let W = ruby.width, H = ruby.height
        let rp = Img.bytes(ruby), bp = Img.bytes(bare)
        let an = Img.bytes(aingNeutral), ag = Img.bytes(aingNegative)
        let aw = aingNeutral.width, ah = aingNeutral.height
        let (aL, aR) = eyes(aingNeutral), (rL, rR) = eyes(ruby)
        let s = simd_length(rR - rL) / simd_length(aR - aL)
        let aMid = (aL + aR) / 2, rMid = (rL + rR) / 2
        // 바뀌는 자리(아잉 좌표) — 두 초상의 색이 다르고 **어느 한쪽이 피부가 아닌**(눈썹 · 입) 화소. 둘 다 피부면 음영 차이일 뿐이라 뺀다. 2 화소 넓힘.
        func skinAt(_ px: [UInt8], _ i: Int) -> Bool { Img.isSkin(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) }
        var changed = [Bool](repeating: false, count: aw * ah)
        for i in 0..<(aw * ah) {
            let d = abs(Int(an[i * 4]) - Int(ag[i * 4])) + abs(Int(an[i * 4 + 1]) - Int(ag[i * 4 + 1])) + abs(Int(an[i * 4 + 2]) - Int(ag[i * 4 + 2]))
            // 얼굴 자리만(눈 사이 거리 e 로: 가로 ±1.1e · 눈 위 0.7e ~ 눈 아래 1.0e) — 실루엣 가장자리의 차이를 줍지 않는다.
            let e = simd_length(aR - aL), x = Double(i % aw), y = Double(i / aw)
            let inFace = abs(x - aMid.x) < 1.1 * e && y > aMid.y - 0.7 * e && y < aMid.y + 1.0 * e
            changed[i] = inFace && d > 36 && ag[i * 4 + 3] > 250 && (!skinAt(ag, i) || !skinAt(an, i))
        }
        var grown = changed
        for y in 0..<ah { for x in 0..<aw where changed[y * aw + x] {
            for dy in -2...2 { for dx in -2...2 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < aw, yy < ah { grown[yy * aw + xx] = true }
            } }
        } }
        // 시무룩 초상의 둘레 피부색(반지름 5 안 피부 화소 평균) — 비피부 정도(알파)의 기준.
        var localSkin = [SIMD3<Double>](repeating: SIMD3(200, 190, 240), count: aw * ah)
        for y in 0..<ah { for x in 0..<aw where grown[y * aw + x] {
            var sum = SIMD3<Double>(0, 0, 0), n = 0.0
            for dy in -6...6 { for dx in -6...6 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < aw, yy < ah else { continue }
                let j = yy * aw + xx
                if ag[j * 4 + 3] > 250 && skinAt(ag, j) { sum += SIMD3(Double(ag[j * 4]), Double(ag[j * 4 + 1]), Double(ag[j * 4 + 2])); n += 1 }
            } }
            if n > 0 { localSkin[y * aw + x] = sum / n }
        } }
        func sampleA(_ px: [UInt8], _ x: Double, _ y: Double) -> SIMD4<Double> {
            let fx = min(max(x - 0.5, 0), Double(aw - 1)), fy = min(max(y - 0.5, 0), Double(ah - 1))
            let ix = min(Int(fx), aw - 2), iy = min(Int(fy), ah - 2), tx = fx - Double(ix), ty = fy - Double(iy)
            func p(_ xx: Int, _ yy: Int) -> SIMD4<Double> { let i = (yy * aw + xx) * 4; return SIMD4(Double(px[i]), Double(px[i + 1]), Double(px[i + 2]), Double(px[i + 3])) }
            return (p(ix, iy) * (1 - tx) + p(ix + 1, iy) * tx) * (1 - ty) + (p(ix, iy + 1) * (1 - tx) + p(ix + 1, iy + 1) * tx) * ty
        }
        var out = rp
        for y in 0..<H { for x in 0..<W {
            let i = (y * W + x) * 4
            guard rp[i + 3] > 250 else { continue }
            // 루비 좌표 → 아잉 좌표(닮음 변환의 역).
            let a = aMid + (SIMD2(Double(x) + 0.5, Double(y) + 0.5) - rMid) / s
            let ax = Int(a.x), ay = Int(a.y)
            guard ax >= 0, ay >= 0, ax < aw, ay < ah, grown[ay * aw + ax] else { continue }
            let f = sampleA(ag, a.x, a.y)
            let feat = SIMD3(f.x, f.y, f.z)
            let alpha = min(max((simd_length(feat - localSkin[ay * aw + ax]) - 12) / 40, 0), 1)
            let base = SIMD3(Double(bp[i]), Double(bp[i + 1]), Double(bp[i + 2]))
            let c = base + (feat - base) * alpha
            out[i] = UInt8(min(max(c.x.rounded(), 0), 255)); out[i + 1] = UInt8(min(max(c.y.rounded(), 0), 255)); out[i + 2] = UInt8(min(max(c.z.rounded(), 0), 255))
        } }
        return Img.make(out, W, H)
    }
}
