// 산타 아잉이 초상 생성기 — 산타 아잉이(aing_santa) 맥 초상 두 장(192², 기본 · 시무룩)을 굽는다. 3D 마감은 앱(SantaAingFinish)이 한다.
// 시안 S3 '수염 산타'(대표 #d_3VZdglOgRABx "산타아잉이는 그냥 주고"). 팔 접기 · 몸 셰이더 · 장식 조각 · 장식 굽기는 CheckCore `SantaAing.swift`
// 한 곳 — 이 생성기는 그 파일을 같이 컴파일해 앱과 **같은 식**으로 3D 를 그린다.
//
// 사용법(저장소 루트에서 — 네트워크 없이 돈다):
//   swiftc -O -parse-as-library -package-name check -o <임시>/make-santa-aing scripts/make-santa-aing.swift Sources/CheckCore/CharacterKit/SantaAing.swift
//   <임시>/make-santa-aing                  Sources/check/Resources/aing_santa-{neutral,negative}.png 를 쓴다.
//   <임시>/make-santa-aing --out <폴더>     같은 두 장을 <폴더>/ 에 쓴다(같은 기계에서 두 번 돌려 바이트를 비교한다).
//
// 방법은 서울의 밤 생성기(scripts/make-region-aing.swift)와 같다: ① 기본 = 앱 구도 정면 3D 렌더(팔 접기 + 산타 셰이더 + 장식)를 아잉 초상의
// 몸 상자에 맞춤 ② 시무룩 = 3D 눈 · 볼은 그대로, 웃는 입만 지우고 아잉 시무룩 초상의 눈썹 · 처진 입을 얹음 — 단 **장식(콧수염 · 코 · 털 방울 ·
// 팔 · 장화) 화소는 건드리지 않는다**(장식 없는 렌더와 맞대 가린다 — 처진 입이 콧수염 위에 그려지지 않게). 처진 입 자리는 거의 콧수염이 덮어
// 시무룩 초상은 '웃는 입이 사라지고 눈썹이 처진' 얼굴이 된다(부산 갈매기의 '입은 부리가 덮는다'와 같은 결). 창 · 네트워크 없음.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import simd

@main
struct MakeSantaAing {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var outDir = "Sources/check/Resources"
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1]; args.removeSubrange(i...(i + 1)) }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let res = "Sources/check/Resources"
        let aingNeutral = Img.load(res + "/aing-neutral.png"), aingNegative = Img.load(res + "/aing-negative.png")
        let render = Portrait.make(res: res, faceOff: false, decor: true)
        let bare = Portrait.make(res: res, faceOff: true, decor: true)
        let bareNoDecor = Portrait.make(res: res, faceOff: true, decor: false)
        let box = Portrait.box(of: render)
        let fit = Portrait.fit(render, to: aingNeutral, box: box)
        let bareFit = Portrait.fit(bare, to: aingNeutral, box: box)
        let noDecorFit = Portrait.fit(bareNoDecor, to: aingNeutral, box: box)
        let negative = Portrait.negative(render: fit, bare: bareFit, noDecor: noDecorFit, aingNegative: aingNegative)
        Img.write(fit, outDir + "/\(SantaAingArt.neutralPortraitResourceName).png")
        Img.write(negative, outDir + "/\(SantaAingArt.negativePortraitResourceName).png")
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
    /// 장식 조각 → 노드(앱 `SantaAingFinish.node` 와 같은 메시 · 같은 구운 텍스처 — CheckCore `SantaDecorBake`).
    static func node(_ piece: SantaDecorPiece) -> SCNNode {
        let mesh = SantaDecorBake.mesh(piece)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                                      SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                                      SCNGeometrySource(textureCoordinates: mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })],
                            elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
        let px = SantaDecorBake.texture(piece)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Img.make(px, piece.texW, piece.texH)
        m.diffuse.wrapS = piece.closedU ? .repeat : .clamp
        m.diffuse.wrapT = .clamp
        m.diffuse.mipFilter = .linear
        g.materials = [m]
        let node = SCNNode(geometry: g)
        node.name = piece.name
        return node
    }
}

enum Portrait {
    static let renderSize = 1024

    static func hitFront(_ body: SCNNode, x: Float, y: Float) -> SIMD3<Float> {
        let hits = body.hitTestWithSegment(from: SCNVector3(x, y, 2), to: SCNVector3(x, y, -2), options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let h = hits.max(by: { $0.localCoordinates.z < $1.localCoordinates.z }) else { fail("앞면 자리를 못 쟀다 (\(x), \(y))") }
        return SIMD3(Float(h.localCoordinates.x), Float(h.localCoordinates.y), Float(h.localCoordinates.z))
    }

    static func crown(_ body: SCNNode) -> (SIMD3<Float>, SIMD3<Float>) {
        let x = SantaAingDecor.crownX, z = SantaAingDecor.crownZ
        let hits = body.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, -3, z), options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let top = hits.max(by: { $0.localCoordinates.y < $1.localCoordinates.y }) else { fail("정수리 자리를 못 쟀다") }
        let n = top.localNormal
        var nn = simd_normalize(SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
        if nn.y < 0 { nn = -nn }
        return (SIMD3(Float(top.localCoordinates.x), Float(top.localCoordinates.y), Float(top.localCoordinates.z)), nn)
    }

    /// 몸 지오메트리에 팔 접기 굽기를 칸 1 · 2 로 더한다(앱 `SantaAingFinish.geometry(_:adding:)` 와 같은 꼴).
    static func folded(_ g: SCNGeometry) -> SCNGeometry {
        guard let vertex = g.sources(for: .vertex).first, let uv = g.sources(for: .texcoord).first else { fail("몸 정점이 없다") }
        var pos = [SIMD3<Float>](repeating: .zero, count: vertex.vectorCount)
        vertex.data.withUnsafeBytes { raw in
            for i in 0..<vertex.vectorCount {
                let b = vertex.dataOffset + i * vertex.dataStride
                pos[i] = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                               raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
            }
        }
        let baked = SantaAingShape.bake(pos)
        let n = baked.count
        var c1 = [Float](repeating: 0, count: n * 2), c2 = c1
        for i in 0..<n {
            c1[i * 2] = baked.displacement[i].x; c1[i * 2 + 1] = baked.displacement[i].y
            c2[i * 2] = baked.displacement[i].z; c2[i * 2 + 1] = baked.fold[i]
        }
        func source(_ a: [Float]) -> SCNGeometrySource {
            SCNGeometrySource(data: a.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        }
        let others = g.sources.filter { $0.semantic != .vertex && $0.semantic != .texcoord }
        let made = SCNGeometry(sources: [vertex, uv, source(c1), source(c2)] + others, elements: g.elements)
        made.materials = g.materials
        return made
    }

    /// 앱 구도(정면) 3D 렌더 — 팔 접기 + 산타 셰이더(+ 장식). 투명 배경 sRGB 프리멀티.
    static func make(res: String, faceOff: Bool, decor: Bool) -> CGImage {
        guard let scene = try? SCNScene(url: URL(fileURLWithPath: res + "/aing.scn"), options: nil) else { fail("aing.scn 을 못 읽었다") }
        scene.background.contents = NSColor.clear
        var bodyNode: SCNNode?
        scene.rootNode.enumerateHierarchy { n, s in if n.geometry != nil { bodyNode = n; s.pointee = true } }
        guard let body = bodyNode, let g = body.geometry, let material = g.materials.first else { fail("몸 메시가 없다") }
        // 카메라: 앱 구도(원래 몸 상자 — 장식 · 팔 접기 전에 잰다).
        let (a, b) = body.boundingBox
        let mn = SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z)), mx = SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z))
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
        material.shaderModifiers = [.geometry: SantaAingShader.geometry, .fragment: SantaAingShader.fragment(faceOff: faceOff)]
        material.setValue(SCNMaterialProperty(contents: shade), forKey: SantaAingShader.shadeMapKey)
        if decor {
            let (c, n) = crown(body)
            let gap = SantaAingDecor.mustacheGap, y = SantaAingDecor.mustacheY
            for piece in SantaAingDecor.pieces(crown: c, crownNormal: n,
                                               mustacheRoots: (hitFront(body, x: gap, y: y), hitFront(body, x: -gap, y: y)),
                                               noseRoot: hitFront(body, x: 0, y: SantaAingDecor.noseY)) {
                body.addChildNode(Decor.node(piece))
            }
        }
        body.geometry = folded(g)
        let center = (mn + mx) / 2, extent = max(mx.x - mn.x, mx.y - mn.y)
        let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.fieldOfView = 40; cam.camera!.zNear = 0.01; cam.camera!.zFar = 1000
        cam.simdPosition = SIMD3(center.x, center.y + extent * 0.55, mx.z + distance)
        cam.simdLook(at: SIMD3(center.x, center.y - extent * 0.16, center.z))
        scene.rootNode.addChildNode(cam)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        let shot = r.snapshot(atTime: 0, with: CGSize(width: renderSize, height: renderSize), antialiasingMode: .multisampling4X)
        return straightened(shot)
    }

    static func decoded(_ contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
        if let d = contents as? Data, let s = CGImageSourceCreateWithData(d as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
        if let i = contents as? NSImage { return i.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if let u = contents as? URL { return NSImage(contentsOf: u)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        return nil
    }

    /// 스냅숏의 '선형 프리멀티를 sRGB 로 부호화한' 반투명 화소를 바른 sRGB 프리멀티로(지역 · 개발 생성기와 같다).
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
        let srcCX = Double(b.x0 + b.x1 + 1) / 2, srcBottom = Double(b.y1 + 1)
        let dstCX = Double(rb.x0 + rb.x1 + 1) / 2, dstBottom = Double(rb.y1 + 1)
        let dw = Double(image.width) * scale, dh = Double(image.height) * scale
        let left = dstCX - srcCX * scale
        let topRow = dstBottom - srcBottom * scale
        ctx.draw(image, in: CGRect(x: left, y: Double(H) - topRow - dh, width: dw, height: dh))
        return ctx.makeImage()!
    }

    /// 눈 두 점(진한 화소 덩어리 중심 — 얼굴 위 절반 · 좌우). `skipCenter` 면 가운데 띠(입 · 코)를 뺀다.
    static func eyes(_ image: CGImage, skipCenter: Bool) -> (SIMD2<Double>, SIMD2<Double>) {
        let px = Img.bytes(image), w = image.width
        let b = box(of: image)
        let cx = Double(b.x0 + b.x1) / 2
        var sL = SIMD2<Double>(0, 0), nL = 0.0, sR = SIMD2<Double>(0, 0), nR = 0.0
        let yTop = b.y0 + (b.y1 - b.y0) * 15 / 100, yBot = b.y0 + (b.y1 - b.y0) * 55 / 100
        for y in yTop..<yBot { for x in b.x0...b.x1 {
            let i = (y * w + x) * 4
            guard px[i + 3] > 250 else { continue }
            let l = (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255
            guard l < 0.22 else { continue }
            if skipCenter && abs(Double(x) - cx) < Double(b.x1 - b.x0) * 0.10 { continue }
            if Double(x) < cx { sL += SIMD2(Double(x), Double(y)); nL += 1 } else { sR += SIMD2(Double(x), Double(y)); nR += 1 }
        } }
        guard nL > 4, nR > 4 else { fail("눈을 못 찾았다(\(nL) · \(nR))") }
        return (sL / nL, sR / nR)
    }

    /// 시무룩: 3D 의 눈 · 볼 · 장식은 그대로, 웃는 입만 지우고 아잉 시무룩 초상의 눈썹 · 처진 입을 얹는다(개발 · 서울 생성기와 같은 식).
    /// ★ 장식 화소(장식 있는 렌더와 장식 없는 렌더가 다른 자리)는 지우지도 얹지도 않는다 — 처진 입이 콧수염 위에 그려지지 않게.
    static func negative(render: CGImage, bare: CGImage, noDecor: CGImage, aingNegative: CGImage) -> CGImage {
        let W = render.width, H = render.height
        let rp = Img.bytes(render), bp = Img.bytes(bare), np = Img.bytes(noDecor)
        let ag = Img.bytes(aingNegative)
        let aw = aingNegative.width, ah = aingNegative.height
        let (gL, gR) = eyes(aingNegative, skipCenter: false), (rL, rR) = eyes(render, skipCenter: true)
        let eA = simd_length(gR - gL), eR = simd_length(rR - rL)
        let s = eR / eA
        let gMid = (gL + gR) / 2, rMid = (rL + rR) / 2
        // 장식 가림(장식이 덮은 화소 — 둘레를 넓히면 콧수염 바로 밑 웃는 입까지 가려 못 지운다).
        var decorMask = [Bool](repeating: false, count: W * H)
        for k in 0..<(W * H) {
            let d = abs(Int(bp[k * 4]) - Int(np[k * 4])) + abs(Int(bp[k * 4 + 1]) - Int(np[k * 4 + 1])) + abs(Int(bp[k * 4 + 2]) - Int(np[k * 4 + 2]))
                + abs(Int(bp[k * 4 + 3]) - Int(np[k * 4 + 3]))
            if d > 24 { decorMask[k] = true }
        }
        let decor = decorMask
        print("장식 화소 \(decor.filter { $0 }.count)")
        func skinAt(_ i: Int) -> Bool { Img.isSkin(Double(ag[i * 4]), Double(ag[i * 4 + 1]), Double(ag[i * 4 + 2])) }
        func isBrow(_ x: Double, _ y: Double) -> Bool {
            let dx = (x - gMid.x) / eA, dy = (y - gMid.y) / eA
            return dy > -0.62 && dy < -0.295 && abs(dx) < 0.85
        }
        func isMouth(_ x: Double, _ y: Double) -> Bool {
            let dx = (x - gMid.x) / eA, dy = (y - gMid.y) / eA
            return dy > 0.06 && dy < 0.62 && abs(dx) < 0.30
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
        var out = rp
        // ① 웃는 입 지우기: 두 눈 사이 아래 가운데 띠에서 기본 렌더가 '얼굴 없는 몸'과 다른 화소(+ 둘레 2)를 몸으로(장식 화소는 뺀다).
        var erase = [Bool](repeating: false, count: W * H)
        for y in 0..<H { for x in 0..<W {
            let i = (y * W + x) * 4
            guard rp[i + 3] > 250, !decor[y * W + x] else { continue }
            let dx = (Double(x) + 0.5 - rMid.x) / eR, dy = (Double(y) + 0.5 - rMid.y) / eR
            guard dy > 0.10 && dy < 0.75 && abs(dx) < 0.32 else { continue }
            let d = abs(Int(rp[i]) - Int(bp[i])) + abs(Int(rp[i + 1]) - Int(bp[i + 1])) + abs(Int(rp[i + 2]) - Int(bp[i + 2]))
            if d > 30 { erase[y * W + x] = true }
        } }
        print("지울 화소 \(erase.filter { $0 }.count)")
        var grownErase = erase
        for y in 0..<H { for x in 0..<W where erase[y * W + x] {
            for dy in -2...2 { for dx in -2...2 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < W, yy < H, !decor[yy * W + xx] { grownErase[yy * W + xx] = true }
            } }
        } }
        // 지운 자리는 둘레(기본 렌더의 몸 화소 — 장식 화소는 빼고)에서 번져 채운다.
        var col = (0..<(W * H)).map { k in SIMD3(Double(rp[k * 4]), Double(rp[k * 4 + 1]), Double(rp[k * 4 + 2])) }
        var known = (0..<(W * H)).map { !grownErase[$0] && !decor[$0] }
        var todo = (0..<(W * H)).filter { grownErase[$0] }
        while !todo.isEmpty {
            var next: [Int] = [], fills: [(Int, SIMD3<Double>)] = []
            for k in todo {
                let x = k % W, y = k / W
                var sum = SIMD3<Double>(0, 0, 0), n = 0.0
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, yy >= 0, xx < W, yy < H, known[yy * W + xx] else { continue }
                    sum += col[yy * W + xx]; n += 1
                }
                if n > 0 { fills.append((k, sum / n)) } else { next.append(k) }
            }
            if fills.isEmpty { break }
            for (k, c) in fills { col[k] = c; known[k] = true }
            todo = next
        }
        for _ in 0..<12 {
            var smooth = col
            for k in 0..<(W * H) where grownErase[k] {
                let x = k % W, y = k / W
                var sum = SIMD3<Double>(0, 0, 0), n = 0.0
                for dy in -1...1 { for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, yy >= 0, xx < W, yy < H, !decor[yy * W + xx] else { continue }
                    sum += col[yy * W + xx]; n += 1
                } }
                if n > 0 { smooth[k] = sum / n }
            }
            col = smooth
        }
        for k in 0..<(W * H) where grownErase[k] {
            out[k * 4] = UInt8(min(max(col[k].x.rounded(), 0), 255)); out[k * 4 + 1] = UInt8(min(max(col[k].y.rounded(), 0), 255))
            out[k * 4 + 2] = UInt8(min(max(col[k].z.rounded(), 0), 255))
        }
        func luma(_ c: SIMD3<Double>) -> Double { 0.299 * c.x + 0.587 * c.y + 0.114 * c.z }
        func coreColor(_ inside: (Double, Double) -> Bool) -> SIMD3<Double> {
            var px: [SIMD3<Double>] = []
            for y in 0..<ah { for x in 0..<aw where inside(Double(x) + 0.5, Double(y) + 0.5) {
                let i = (y * aw + x) * 4
                guard ag[i + 3] > 250 else { continue }
                let c = SIMD3(Double(ag[i]), Double(ag[i + 1]), Double(ag[i + 2]))
                guard luma(c) < luma(localSkin(x, y)) - 25 else { continue }
                px.append(c)
            } }
            guard !px.isEmpty else { fail("시무룩 초상에서 획을 못 찾았다") }
            let dark = px.sorted { luma($0) < luma($1) }.prefix(max(1, px.count / 4))
            return dark.reduce(SIMD3<Double>(0, 0, 0), +) / Double(dark.count)
        }
        let browCore = coreColor(isBrow), mouthCore = coreColor(isMouth)
        // ② 눈썹 · 처진 입 얹기(시무룩 초상 → 산타, 눈 두 점 닮음 변환의 역으로 표본 · 눈썹만 browLift 만큼 위로). 장식 화소는 건너뛴다.
        for y in 0..<H { for x in 0..<W {
            let i = (y * W + x) * 4
            guard rp[i + 3] > 250, !decor[y * W + x] else { continue }
            let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
            let am = gMid + (p - rMid) / s
            let ab = gMid + (p + SIMD2(0, browLift) - rMid) / s
            let a: SIMD2<Double>
            if isMouth(am.x, am.y) { a = am } else if isBrow(ab.x, ab.y) { a = ab } else { continue }
            let ax = Int(a.x), ay = Int(a.y)
            guard ax >= 0, ay >= 0, ax < aw, ay < ah else { continue }
            let f = sampleA(a.x, a.y)
            guard f.w > 250 else { continue }
            let feat = SIMD3(f.x, f.y, f.z)
            let skinHere = localSkin(ax, ay)
            let core = isMouth(am.x, am.y) ? mouthCore : browCore
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
