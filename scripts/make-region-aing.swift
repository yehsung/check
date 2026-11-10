// 지역 아잉이 초상 생성기 — 부산 갈매기 아잉이(aing_busan) 맥 초상 두 장(192², 기본 · 시무룩)을 굽는다. 3D 마감은 앱(RegionAingFinish)이 한다.
// 시안 G1 '갈매기가 된 아잉이'(대표 결정 2026-11-10 #d_afa6DRyExPLp). 몸 셰이더 · 장식 조각은 CheckCore `RegionAing.swift` 한 곳 — 이 생성기는
// 그 파일을 같이 컴파일해 앱과 **같은 식**으로 3D 를 그린다.
//
// 사용법(저장소 루트에서):
//   swiftc -O -parse-as-library -package-name check -o <임시>/make-region-aing scripts/make-region-aing.swift Sources/CheckCore/CharacterKit/RegionAing.swift
//   <임시>/make-region-aing                  Sources/check/Resources/aing_busan-{neutral,negative}.png 를 쓴다.
//   <임시>/make-region-aing --out <폴더>     같은 두 장을 <폴더>/ 에 쓴다(같은 기계에서 두 번 돌려 바이트를 비교한다).
//
// 방법은 개발 아잉이 생성기(scripts/make-dev-aing.swift)와 같다: ① 기본 = 앱 구도 정면 3D 렌더(갈매기 셰이더 + 부리 · 발 · 꼬리깃)를 아잉 초상의
// 몸 상자에 맞춤 ② 시무룩 = 3D 눈 · 볼 · 부리는 그대로, 아잉 시무룩 초상의 **눈썹만** 얹음(입은 부리가 덮어 처진 입을 얹지 않는다). 창 · 네트워크 없음.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import simd

@main
struct MakeRegionAing {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var outDir = "Sources/check/Resources"
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1]; args.removeSubrange(i...(i + 1)) }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let res = "Sources/check/Resources"
        let neutral = Portrait.make(res: res)
        let aingNeutral = Img.load(res + "/aing-neutral.png"), aingNegative = Img.load(res + "/aing-negative.png")
        let fitted = Portrait.fit(neutral.image, to: aingNeutral, box: Portrait.box(of: neutral.image))
        let negative = Portrait.negative(render: fitted, aingNegative: aingNegative)
        let id = RegionAingArt.busanID
        Img.write(fitted, outDir + "/\(RegionAingArt.neutralPortraitResourceName(id)).png")
        Img.write(negative, outDir + "/\(RegionAingArt.negativePortraitResourceName(id)).png")
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

enum Decor {
    /// 장식 조각 → 정점 색 노드(몸 공간 빛을 정점 색으로 구움 — 개발 생성기의 끈과 같은 길).
    static func node(_ piece: GullDecorPiece) -> SCNNode {
        let nu = piece.nu, nv = piece.nv
        var verts = [SCNVector3](), cols = [SIMD4<Float>]()
        let key = simd_normalize(SIMD3<Float>(-0.30, 0.85, 0.45)), view = simd_normalize(SIMD3<Float>(0, 0.30, 1))
        func lin(_ hex: Int) -> SIMD3<Float> {
            func l(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return SIMD3(l(Float((hex >> 16) & 255) / 255), l(Float((hex >> 8) & 255) / 255), l(Float(hex & 255) / 255))
        }
        for j in 0...nv { for i in 0...nu {
            let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
            let p = piece.pos(u, v)
            let e: Float = 1e-3
            let u0 = piece.closedU ? u - e : max(u - e, 0), u1 = piece.closedU ? u + e : min(u + e, 1)
            let v0 = max(v - e, 0), v1 = min(v + e, 1)
            var n = simd_cross(piece.pos(u1, v) - piece.pos(u0, v), piece.pos(u, v1) - piece.pos(u, v0))
            n = simd_length(n) < 1e-9 ? SIMD3(0, 1, 0) : simd_normalize(n)
            verts.append(SCNVector3(p.x, p.y, p.z))
            let ndl = simd_dot(n, key)
            let diff = min(max((ndl + Float(piece.wrap)) / (1 + Float(piece.wrap)), 0), 1)
            let ao = 1 - 0.22 * max(-n.y, 0)
            var c = lin(piece.color(Double(u), Double(v))) * (Float(piece.ambient) + (1 - Float(piece.ambient)) * diff) * ao
            c += SIMD3(repeating: pow(max(simd_dot(n, simd_normalize(key + view)), 0), Float(piece.gloss)) * Float(piece.spec))
            cols.append(SIMD4(simd_clamp(c, .zero, SIMD3(repeating: 1)), 1))
        } }
        var idx = [UInt32]()
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) { for i in 0..<UInt32(nu) {
            let a = j * row + i, b = a + 1, c = a + row, d = c + 1
            idx += [a, b, c, b, d, c]
        } }
        let colData = cols.withUnsafeBufferPointer { Data(buffer: $0) }
        let colSrc = SCNGeometrySource(data: colData, semantic: .color, vectorCount: cols.count, usesFloatComponents: true,
                                       componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), colSrc], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor.white; m.isDoubleSided = true
        g.materials = [m]
        let node = SCNNode(geometry: g); node.name = piece.name
        return node
    }
}

enum Portrait {
    static let renderSize = 1024

    /// 앱 구도(정면) 3D 렌더 — 몸 빚기 + 보석 셰이더. 투명 배경 sRGB 프리멀티.
    static func make(res: String) -> (image: CGImage, size: Int) {
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
        material.shaderModifiers = [.geometry: GullAingShader.geometry, .fragment: GullAingShader.fragment()]
        material.setValue(SCNMaterialProperty(contents: shade), forKey: GullAingShader.shadeMapKey)
        // 갈매기 장식(앱 RegionAingFinish 와 같은 조각 — CheckCore GullAingDecor).
        let hits = body.hitTestWithSegment(from: SCNVector3(GullAingDecor.beakX, GullAingDecor.beakY, 2), to: SCNVector3(GullAingDecor.beakX, GullAingDecor.beakY, -2),
                                           options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let h = hits.max(by: { $0.localCoordinates.z < $1.localCoordinates.z }) else { fail("부리 자리를 못 쟀다") }
        let beakRoot = SIMD3<Float>(Float(h.localCoordinates.x), Float(h.localCoordinates.y), Float(h.localCoordinates.z))
        for piece in GullAingDecor.pieces(beakRoot: beakRoot) { body.addChildNode(Decor.node(piece)) }
        // 카메라: 앱 구도(원래 몸 상자 — 몸을 빚기 전에 잰다).
        let (a, b) = body.boundingBox
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
    static func eyes(_ image: CGImage, skipCenter: Bool) -> (SIMD2<Double>, SIMD2<Double>) {
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
            // 부리(가운데 띠 — 검은 띠 · 빨간 점)는 눈이 아니다.
            if skipCenter && abs(Double(x) - cx) < Double(b.x1 - b.x0) * 0.10 { continue }
            if Double(x) < cx { sL += SIMD2(Double(x), Double(y)); nL += 1 } else { sR += SIMD2(Double(x), Double(y)); nR += 1 }
        } }
        guard nL > 4, nR > 4 else { fail("눈을 못 찾았다(\(nL) · \(nR))") }
        _ = h
        return (sL / nL, sR / nR)
    }

    /// 시무룩: 3D 의 눈 · 볼 · 부리는 그대로 두고 아잉 시무룩 초상의 **눈썹만** 얹는다(입은 부리가 덮는다 — 처진 입을 얹지 않는다).
    /// 자리는 시무룩 초상 자신의 눈 두 점 → 렌더 눈 두 점 닮음 변환으로 잡는다(개발 · 루비 생성기와 같은 길). 눈 찾기는 가운데 띠(부리)를 뺀다.
    static func negative(render: CGImage, aingNegative: CGImage) -> CGImage {
        let W = render.width, H = render.height
        let rp = Img.bytes(render)
        let ag = Img.bytes(aingNegative)
        let aw = aingNegative.width, ah = aingNegative.height
        let (gL, gR) = eyes(aingNegative, skipCenter: false), (rL, rR) = eyes(render, skipCenter: true)
        let eA = simd_length(gR - gL), eR = simd_length(rR - rL)
        let s = eR / eA
        let gMid = (gL + gR) / 2, rMid = (rL + rR) / 2
        func skinAt(_ i: Int) -> Bool { Img.isSkin(Double(ag[i * 4]), Double(ag[i * 4 + 1]), Double(ag[i * 4 + 2])) }
        func isBrow(_ x: Double, _ y: Double) -> Bool {
            let dx = (x - gMid.x) / eA, dy = (y - gMid.y) / eA
            return dy > -0.62 && dy < -0.295 && abs(dx) < 0.85
        }
        let browLift = 0.09 * eR
        func localSkin(_ x: Int, _ y: Int) -> SIMD3<Double> {
            var sum = SIMD3<Double>(0, 0, 0), n = 0.0
            for dy in -6...6 { for dx in -6...6 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < aw, yy < ah else { continue }
                let j = yy * aw + xx
                if ag[j * 4 + 3] > 250 && skinAt(j) { sum += SIMD3(Double(ag[j * 4]), Double(ag[j * 4 + 1]), Double(ag[j * 4 + 2])); n += 1 }
            } }
            return n > 0 ? sum / n : SIMD3(200, 190, 240)
        }
        func sampleA(_ x: Double, _ y: Double) -> SIMD4<Double> {
            let fx = min(max(x - 0.5, 0), Double(aw - 1)), fy = min(max(y - 0.5, 0), Double(ah - 1))
            let ix = min(Int(fx), aw - 2), iy = min(Int(fy), ah - 2), tx = fx - Double(ix), ty = fy - Double(iy)
            func p(_ xx: Int, _ yy: Int) -> SIMD4<Double> { let i = (yy * aw + xx) * 4; return SIMD4(Double(ag[i]), Double(ag[i + 1]), Double(ag[i + 2]), Double(ag[i + 3])) }
            return (p(ix, iy) * (1 - tx) + p(ix + 1, iy) * tx) * (1 - ty) + (p(ix, iy + 1) * (1 - tx) + p(ix + 1, iy + 1) * tx) * ty
        }
        func luma(_ c: SIMD3<Double>) -> Double { 0.299 * c.x + 0.587 * c.y + 0.114 * c.z }
        var px: [SIMD3<Double>] = []
        for y in 0..<ah { for x in 0..<aw where isBrow(Double(x) + 0.5, Double(y) + 0.5) {
            let i = (y * aw + x) * 4
            guard ag[i + 3] > 250 else { continue }
            let c = SIMD3(Double(ag[i]), Double(ag[i + 1]), Double(ag[i + 2]))
            guard luma(c) < luma(localSkin(x, y)) - 25 else { continue }
            px.append(c)
        } }
        guard !px.isEmpty else { fail("시무룩 초상에서 눈썹을 못 찾았다") }
        let dark = px.sorted { luma($0) < luma($1) }.prefix(max(1, px.count / 4))
        let core = dark.reduce(SIMD3<Double>(0, 0, 0), +) / Double(dark.count)
        var out = rp
        for y in 0..<H { for x in 0..<W {
            let i = (y * W + x) * 4
            guard rp[i + 3] > 250 else { continue }
            let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
            let a = gMid + (p + SIMD2(0, browLift) - rMid) / s
            guard isBrow(a.x, a.y) else { continue }
            let ax = Int(a.x), ay = Int(a.y)
            guard ax >= 0, ay >= 0, ax < aw, ay < ah else { continue }
            let f = sampleA(a.x, a.y)
            guard f.w > 250 else { continue }
            let feat = SIMD3(f.x, f.y, f.z)
            let skinHere = localSkin(ax, ay)
            let lSkin = luma(skinHere), lCore = luma(core)
            let alpha = min(max((lSkin - luma(feat)) / max(lSkin - lCore, 1) * 1.15 - 0.08, 0), 1)
            guard alpha > 0 else { continue }
            let base = SIMD3(Double(out[i]), Double(out[i + 1]), Double(out[i + 2]))
            let c = base + (core - base) * alpha
            out[i] = UInt8(min(max(c.x.rounded(), 0), 255)); out[i + 1] = UInt8(min(max(c.y.rounded(), 0), 255)); out[i + 2] = UInt8(min(max(c.z.rounded(), 0), 255))
        } }
        return Img.make(out, W, H)
    }
}
