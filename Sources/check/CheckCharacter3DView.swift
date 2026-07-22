import AppKit
import Metal
import SceneKit
import SwiftUI

/// 아잉 3D 캐릭터 씬 구성.
///
/// 리소스 번들(`CheckResources.bundle`)의 `aing.usdz`를 로드하고, 마스코트 원색(보라)이 살도록 모든 재질을
/// unlit(`.constant`)로 바꾼 뒤, 바운딩박스를 기준으로 캐릭터를 살짝 내려다보는 구도로 프레임에 꽉 차게
/// 카메라를 배치한다. 여기에 느린 상하 부유(bob)와 아주 느린 살랑 회전(sway) 애니메이션을 붙인다.
///
/// 기본 PBR/조명에서는 텍스처가 허옇게 떠 마스코트 색이 사라지므로 반드시 `.constant`를 쓴다
/// (오프스크린 렌더로 확인: 조명 모델을 켜면 중앙 픽셀이 거의 흰색, `.constant`면 라벤더 보라).
enum CheckCharacter3DScene {
    /// 카메라 시야각(도). 거리 산정과 프레이밍에 공통으로 쓴다.
    static let fieldOfView: CGFloat = 40

    /// 번들에서 `aing.usdz`를 SCNScene으로 로드한다. 실패 시 nil.
    static func loadModelScene() -> SCNScene? {
        guard let url = CheckResources.bundle.url(forResource: "aing", withExtension: "usdz") else {
            return nil
        }
        return try? SCNScene(url: url, options: nil)
    }

    /// 리액션 wrapper 노드 이름. idle(부유/회전)은 wrapper 안쪽 캐릭터에, 리액션은 wrapper 에 걸어
    /// 서로 간섭하지 않게 한다. makeNSView 가 이 이름으로 wrapper 를 찾아 리액션 엔진에 연결한다.
    static let reactionWrapperName = "check.reactionWrapper"

    /// 드래그 방향 바라보기 전용 노드 이름. 리액션 wrapper(바깥, resetPose 가 euler 를 0 으로 리셋)와 idle
    /// 캐릭터(안쪽, 부유/살랑) 사이에 끼워, facing 회전이 리액션 resetPose·commuteStart y스핀과 충돌하지 않게 한다.
    static let facingWrapperName = "check.facingWrapper"

    /// 오버레이용으로 완성된 씬(재질 unlit·투명 배경·카메라·애니메이션 포함). 로드 실패 시 nil.
    static func makeScene(animated: Bool = true) -> SCNScene? {
        guard let scene = loadModelScene() else { return nil }
        // 씬 배경을 비워 패널 뒤(바탕화면/다른 앱)가 그대로 비치게 한다.
        scene.background.contents = nil
        applyUnlitMaterials(to: scene.rootNode)

        // 임포트된 캐릭터 루트(첫 자식). 없으면 카메라/애니메이션 없이 씬만 돌려준다.
        guard let character = scene.rootNode.childNodes.first else { return scene }

        // 캐릭터를 wrapper 로 감싼다: 리액션은 wrapper(바깥), idle 부유/회전은 캐릭터(안쪽)에 걸어
        // 둘이 같은 트랜스폼을 두고 다투지 않게 분리한다. 그 사이에 facing 노드를 끼워 드래그 방향 바라보기
        // 회전을 리액션/idle 과 독립시킨다(wrapper → facing → character).
        let wrapper = SCNNode()
        wrapper.name = reactionWrapperName
        let facing = SCNNode()
        facing.name = facingWrapperName
        character.removeFromParentNode()
        facing.addChildNode(character)
        wrapper.addChildNode(facing)
        scene.rootNode.addChildNode(wrapper)

        addFramingCamera(to: scene)
        addClosedEyeNodes(to: character)
        if animated {
            addIdleAnimations(to: character)
        }
        return scene
    }

    // MARK: - 감은 눈 오버레이 노드(sleeping 시 얼굴 눈 자리에 얹는 얇은 감은 선)

    /// 감은 눈 선 노드 이름(좌/우). 엔진이 sleeping 진입/이탈 시 이 노드의 isHidden 을 토글한다.
    static let closedEyeLeftName = "check.closedEye.L"
    static let closedEyeRightName = "check.closedEye.R"

    /// 두 눈의 얼굴 표면 3D 좌표(캐릭터 로컬). 오프스크린 hitTest 로 실측한 고정값(에셋 고정 배포물).
    /// 화면 왼눈 ← (-0.277,0.418,0.531), 오른눈 ← (0.250,0.434,0.526).
    static let closedEyeAnchors: [(name: String, position: SCNVector3)] = [
        (closedEyeLeftName, SCNVector3(-0.277, 0.418, 0.531)),
        (closedEyeRightName, SCNVector3(0.250, 0.434, 0.526))
    ]

    /// 감은 눈 선 노드 2개를 캐릭터(안쪽, idle 부유/살랑과 함께 움직임)에 자식으로 붙인다. 기본 숨김.
    /// UV 아틀라스가 저폴리로 눈을 여러 조각으로 흩어 텍스처에 깔끔한 감은 선을 그리기 어려우므로, 선은 얼굴
    /// 표면 바로 앞에 얹는 얇은 평면(빌보드 아닌 +Z 정면 — 칠해진 듯 자연스럽게)으로 그린다. 커버(텍스처)로 뜬 눈을
    /// 지우고 그 위에 이 선을 얹어 "감은 눈"을 완성한다.
    static func addClosedEyeNodes(to character: SCNNode) {
        let image = closedEyeLineImage()
        for (name, pos) in closedEyeAnchors {
            let node = makeClosedEyeNode(image: image)
            node.name = name
            // 표면보다 살짝 앞(+z)에 둬 z-파이팅/가림을 피한다.
            node.position = SCNVector3(pos.x, pos.y, pos.z + 0.035)
            node.isHidden = true
            character.addChildNode(node)
        }
    }

    /// 감은 선 평면 노드(unlit·알파·깊이버퍼 무시로 항상 위에). 정면(+Z)을 향해 얹혀 선이 화면상 수평으로 보인다.
    static func makeClosedEyeNode(image: NSImage, width: CGFloat = 0.34, height: CGFloat = 0.2) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.blendMode = .alpha
        // 얼굴 돌출(코/볼)에 가리지 않게 깊이 테스트를 끄고 렌더 순서를 뒤로 미룬다.
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 20
        return node
    }

    /// 감은 눈 선 이미지(투명 배경 + 진한 곡선). 가운데가 살짝 내려앉은 잔잔한 눈웃음(ᵕ) 느낌의 감은 눈.
    static func closedEyeLineImage(width: Int = 160, height: Int = 96) -> NSImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: NSSize(width: width, height: height)) }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let w = CGFloat(width), h = CGFloat(height)
        // CGContext 는 bottom-left 원점(y 위로 증가). 가운데가 아래로 내려앉은 곡선(ᵕ): 양 끝이 위, 중앙이 아래.
        let inset = w * 0.16
        let endY = h * 0.62, midY = h * 0.34
        let path = CGMutablePath()
        path.move(to: CGPoint(x: inset, y: endY))
        path.addQuadCurve(to: CGPoint(x: w - inset, y: endY), control: CGPoint(x: w / 2, y: midY))
        ctx.setStrokeColor(CGColor(red: 0.19, green: 0.12, blue: 0.17, alpha: 1)) // 속눈썹처럼 진한 자주-검정.
        ctx.setLineWidth(h * 0.16)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
        guard let cg = ctx.makeImage() else { return NSImage(size: NSSize(width: width, height: height)) }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    /// 모든 재질을 unlit(`.constant`)로 전환하고, 상주 텍스처를 다운스케일한다.
    ///
    /// 기본 조명에서 텍스처가 허옇게 뜨는 것을 막아 마스코트 원색을 보존한다. 아울러 원본 텍스처(2048²)를
    /// 패널 표시 크기(280×340@2x)에 맞춰 512px 로 줄여 상주 텍스처 메모리를 크게 절감한다(A8).
    static func applyUnlitMaterials(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                material.lightingModel = .constant
                if let downscaled = downscaledTexture(material.diffuse.contents) {
                    material.diffuse.contents = downscaled
                }
            }
        }
    }

    /// 텍스처 콘텐츠를 최대 `maxDimension`px 로 리샘플한 CGImage 로 돌려준다.
    /// NSImage/CGImage/파일 참조(URL·경로)만 처리하고, 이미 작거나 알 수 없는 타입이면 nil(교체하지 않음 — 무손실 no-op).
    static func downscaledTexture(_ contents: Any?, maxDimension: CGFloat = 512) -> CGImage? {
        guard let contents else { return nil }
        let source: CGImage?
        // 주의: CF 불투명 타입(CGImage)으로의 `as?` 캐스트는 실제 타입과 무관하게 성공하므로
        // (NSURL 도 삼켜 쓰레기 치수를 만든다) 반드시 CFGetTypeID 로 판별한다.
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            source = (contents as! CGImage)
        } else if let image = contents as? NSImage {
            source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let url = contents as? URL {
            source = decodeTextureURL(url)
        } else if let path = contents as? String {
            source = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            return nil
        }
        guard let cg = source else { return nil }
        // 디코드가 비정상 이미지(예: 아카이브 통짜 오독 → 1×512)를 내놓으면 교체하지 않는다(무손실 no-op).
        guard cg.width >= 8, cg.height >= 8 else { return nil }
        let maxSide = max(cg.width, cg.height)
        guard maxSide > Int(maxDimension) else { return nil }
        let scale = maxDimension / CGFloat(maxSide)
        let newWidth = max(1, Int((CGFloat(cg.width) * scale).rounded()))
        let newHeight = max(1, Int((CGFloat(cg.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// SceneKit 이 USDZ 내부 텍스처를 가리킬 때 쓰는 `...aing.usdz?offset=N&size=M` 아카이브 참조 URL 을
    /// 디코드한다. usdz 는 무압축(stored) zip 이라 해당 바이트 구간이 곧 이미지 파일 원본이다.
    /// 일반 파일 URL(쿼리 없음)은 그대로 이미지로 읽는다. 실패 시 nil(교체하지 않음).
    private static func decodeTextureURL(_ url: URL) -> CGImage? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let offset = items.first(where: { $0.name == "offset" })?.value.flatMap(Int.init),
              let size = items.first(where: { $0.name == "size" })?.value.flatMap(Int.init)
        else {
            return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        var fileComponents = components
        fileComponents.queryItems = nil
        guard let fileURL = fileComponents.url,
              offset >= 0, size > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL),
              let _ = try? handle.seek(toOffset: UInt64(offset)),
              let data = try? handle.read(upToCount: size),
              data.count == size
        else {
            return nil
        }
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// 바운딩박스를 기준으로, 캐릭터를 살짝 내려다보는 구도로 프레임에 꽉 차게 카메라를 배치한다.
    ///
    /// 카메라 Y를 캐릭터 중심보다 바운딩 높이의 0.4배 위로 올리고, 바라보는 지점(look target)은
    /// 중심보다 약간 아래로 내려 얼굴이 정면~살짝 위에서 자연스럽게 내려다보이게 한다.
    private static func addFramingCamera(to scene: SCNScene) {
        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        // 상하 부유·살랑 회전 + 내려다보는 각도로 잘리는 여유를 두고 꽉 차게. 최장변 기준 거리 산정 후 1.4배 여유.
        let extent = CGFloat(max(maxB.x - minB.x, maxB.y - minB.y))
        let distance = extent / (2 * tan(fieldOfView / 2 * .pi / 180)) * 1.4

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = fieldOfView
        camera.zNear = 0.01
        camera.zFar = 1_000
        cameraNode.camera = camera
        // 카메라를 캐릭터 중심보다 바운딩 높이의 0.4배 위로 올려 살짝 내려다보게 둔다.
        cameraNode.position = SCNVector3(center.x, center.y + extent * 0.55, CGFloat(maxB.z) + distance)
        // 바라보는 지점을 중심보다 아래(0.16배)로 내려 위에서 내려다보는 구도.
        let lookTarget = SCNVector3(center.x, center.y - extent * 0.16, center.z)
        cameraNode.look(at: lookTarget)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// 생동감을 위한 느린 상하 부유 + 아주 느린 살랑 회전을 무한 반복으로 붙인다.
    private static func addIdleAnimations(to node: SCNNode) {
        let up = SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 1.8)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.moveBy(x: 0, y: -0.07, z: 0, duration: 1.8)
        down.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([up, down])))

        let swayRight = SCNAction.rotateBy(x: 0, y: 0.14, z: 0, duration: 3.6)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateBy(x: 0, y: -0.28, z: 0, duration: 7.2)
        swayLeft.timingMode = .easeInEaseOut
        let swayBack = SCNAction.rotateBy(x: 0, y: 0.14, z: 0, duration: 3.6)
        swayBack.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([swayRight, swayLeft, swayBack])))
    }

    /// 오프스크린 PNG 렌더(시각 검증용). SCNRenderer로 씬을 그려 PNG Data를 돌려준다.
    static func renderSnapshotPNG(size: CGSize = CGSize(width: 280, height: 340)) -> Data? {
        guard let scene = makeScene(animated: false),
              let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// 자는(sleeping) 동안 쓰는 "감은 눈" 텍스처 생성기 — **눈을 피부로 덮는 부분**만 담당한다
/// (감은 선은 3D 오버레이 노드 `CheckCharacter3DScene.makeClosedEyeNode` 가 얹는다).
///
/// 아잉은 리깅/블렌드셰이프가 없어 눈꺼풀을 애니메이트할 수 없다. 그래서 sleeping 진입 시 디퓨즈 텍스처의 두 눈을
/// 주변 피부색(라벤더)으로 덮은 버전으로 통째로 교체하고, 깨면 원복한다.
///
/// 왜 ROI 가 아니라 전역 검출인가: 이 에셋(aing.usdz)의 UV 는 저폴리라 **한 눈이 아틀라스 여러 조각으로 심하게
/// 흩어져** 있다(왼눈은 아틀라스 상단·하단·우하단에 파편으로 분산, 오른눈과 입 조각까지 서로 얽힘). 오프스크린
/// 검수 결과 `isEye`(피부·분홍 아님) 픽셀은 화면상 **두 눈과 입에만** 존재하고 몸/귀 그림자는 전부 피부로
/// 분류되므로, "isEye 전역 검출 + 입 보호"가 파편을 일일이 ROI 로 쫓는 것보다 견고하다.
///
/// 커버 품질 핵심:
/// 1) 채우기는 경계(피부)에서 안쪽으로 번지는 **반복 평균 인페인트** — 국소 피부 그라디언트에 자연히 맞물려
///    이음새·흰 끼가 없다(단색 중앙값을 통째로 붓지 않는다).
/// 2) 입은 **진한 빨강(입 안쪽) 근처 보호막**으로 지킨다(볼터치 분홍은 밝아 보호 대상에서 빠지므로 눈 커버를
///    방해하지 않는다). 3) 안티에일리어싱 눈 테두리까지 살아남지 않게 커버 마스크를 공격적으로 팽창한다.
enum SleepEyeTexture {
    /// 원본 디퓨즈 CGImage 로부터 "눈을 덮은" 버전을 만든다. 해상도 무관. 실패 시 nil(교체 안 함).
    static func closedEyesImage(from original: CGImage) -> CGImage? {
        let w = original.width, h = original.height
        guard w >= 64, h >= 64 else { return nil }
        let bytesPerRow = w * 4
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: h * bytesPerRow)
        defer { buffer.deallocate() }
        guard let ctx = CGContext(
            data: buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(original, in: CGRect(x: 0, y: 0, width: w, height: h))
        var buf = PixelBuffer(data: buffer, width: w, height: h)
        coverEyes(in: &buf)
        return ctx.makeImage()
    }

    // MARK: - 픽셀 버퍼 래퍼(RGBA8, premultipliedLast). 좌표는 CGImage 와 동일(원점 좌상단).

    struct PixelBuffer {
        let data: UnsafeMutablePointer<UInt8>
        let width: Int
        let height: Int
        @inline(__always) func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
        @inline(__always) func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = index(x, y); return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        @inline(__always) func set(_ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int) {
            let i = index(x, y)
            data[i] = UInt8(clamping: r); data[i + 1] = UInt8(clamping: g)
            data[i + 2] = UInt8(clamping: b); data[i + 3] = 255
        }
    }

    // MARK: - 색 분류(실측 색값 기반)

    @inline(__always) static func luma(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (r * 299 + g * 587 + b * 114) / 1000
    }
    /// 라벤더 피부: 파랑>=빨강>초록의 시원한 보라빛에 충분히 밝다. (예: 223,208,253)
    @inline(__always) static func isSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        b >= r && r > g && b > g + 18 && luma(r, g, b) > 120
    }
    /// 볼터치 분홍: 빨강>파랑의 따뜻한 밝은 색. (예: 250,171,200) — 눈으로 오검출하지 않게 제외.
    @inline(__always) static func isPink(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        r > b && r > g + 40 && r > 200 && luma(r, g, b) > 120
    }
    /// 눈 픽셀(iris/흰자/하이라이트/속눈썹): 피부도 분홍도 아닌 것. 어둡거나(눈동자·속눈썹) 중성 흰색(흰자)이다.
    @inline(__always) static func isEye(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        !isSkin(r, g, b) && !isPink(r, g, b)
    }
    /// 입 안쪽 진한 빨강(예: 150,12,47 / 181,39,84). **초록이 매우 낮은** 채도 높은 붉은색이라, 갈색빛 눈동자·
    /// 속눈썹(초록 68~76)과 구분된다(실측: 입/머리 빨강 g≤61, iris 오검출 g≥68). 이 근처를 보호막으로 삼아
    /// 입(어두운 입술 라인 포함)이 눈 커버에 지워지지 않게 한다. (추가로 커버 단계에서 '큰 덩어리'만 보호에 쓴다.)
    @inline(__always) static func isMouthRed(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        r > 120 && g < 66 && b < 150 && r >= g + 55
    }

    // MARK: - 전역 눈 커버(입 보호 + 반복 인페인트)

    static func coverEyes(in buf: inout PixelBuffer) {
        let w = buf.width, h = buf.height, n = w * h
        var eye = [Bool](repeating: false, count: n)
        var red = [Bool](repeating: false, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = buf.rgb(x, y)
                let idx = y * w + x
                if isMouthRed(r, g, b) { red[idx] = true }
                else if isEye(r, g, b) { eye[idx] = true }
            }
        }
        // 입 보호막: 진한 빨강 중 '큰 덩어리'(입·머리)만 남겨(흩어진 iris 오검출 제거) 반경 R 팽창.
        // 이 안의 눈 픽셀은 덮지 않는다(입 손상 금지).
        let minRedComponent = max(30, w * h / 6000)
        let redBlobs = largeComponents(red, rw: w, rh: h, minSize: minRedComponent)
        let protectR = max(3, Int((CGFloat(w) * 0.012).rounded()))
        let protected = dilateMask(redBlobs, rw: w, rh: h, radius: protectR)
        // 커버 마스크 = 눈 & 보호막 밖. 안티에일리어싱 눈 테두리까지 공격적으로 팽창.
        var cover = [Bool](repeating: false, count: n)
        for i in 0..<n { cover[i] = eye[i] && !protected[i] }
        let dilateR = max(2, Int((CGFloat(w) * 0.008).rounded()))
        cover = dilateMask(cover, rw: w, rh: h, radius: dilateR)
        // 팽창이 입 보호막을 다시 침범하지 않게 한 번 더 뺀다.
        for i in 0..<n where protected[i] { cover[i] = false }
        inpaint(&buf, cover: cover)
    }

    /// 반복 평균 인페인트: 커버 픽셀을 '미지'로 두고, **피부색으로 분류된** 이웃(원 피부/이미 채운 픽셀)의 평균으로
    /// 경계부터 안쪽으로 번져 채운다. 어두운(눈동자·속눈썹)·보호된(입) 이웃은 소스에서 배제해 어두운 색이 번지지
    /// 않게 한다. 국소 피부색을 확산시키므로 그라디언트에 자연히 맞물려 이음새가 없다. 끝까지 못 채운 소수 픽셀은
    /// 전역 피부 중앙값으로 마감한다(어두운 잔존 0 보장).
    static func inpaint(_ buf: inout PixelBuffer, cover: [Bool]) {
        let w = buf.width, h = buf.height
        var unknown = cover
        var indices = [Int]()
        for i in 0..<(w * h) where unknown[i] { indices.append(i) }
        guard !indices.isEmpty else { return }
        var guardIter = 0
        while !indices.isEmpty && guardIter < 8192 {
            guardIter += 1
            var updates = [(Int, Int, Int, Int)]()
            updates.reserveCapacity(indices.count)
            for idx in indices {
                let x = idx % w, y = idx / w
                var sr = 0, sg = 0, sb = 0, cnt = 0
                var dy = -1
                while dy <= 1 {
                    var dx = -1
                    while dx <= 1 {
                        if !(dx == 0 && dy == 0) {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, nx < w, ny >= 0, ny < h, !unknown[ny * w + nx] {
                                let (r, g, b) = buf.rgb(nx, ny)
                                // 피부색 소스만 확산(어두운·붉은 이웃 배제 → 어두운 번짐 0).
                                if isSkin(r, g, b) { sr += r; sg += g; sb += b; cnt += 1 }
                            }
                        }
                        dx += 1
                    }
                    dy += 1
                }
                if cnt > 0 { updates.append((idx, sr / cnt, sg / cnt, sb / cnt)) }
            }
            if !updates.isEmpty {
                for (idx, r, g, b) in updates { buf.set(idx % w, idx / w, r, g, b); unknown[idx] = false }
                indices = indices.filter { unknown[$0] }
            } else {
                break // 더 번질 피부 소스가 없다 — 남은 픽셀은 아래 중앙값으로 마감.
            }
        }
        // 마감: 끝까지 못 채운 픽셀은 전역 피부 중앙값으로(어두운 잔존 방지).
        if !indices.isEmpty {
            var rs = [Int](), gs = [Int](), bs = [Int]()
            for i in stride(from: 0, to: w * h, by: 7) {
                let x = i % w, y = i / w
                let (r, g, b) = buf.rgb(x, y)
                if !cover[i], isSkin(r, g, b) { rs.append(r); gs.append(g); bs.append(b) }
            }
            if !rs.isEmpty {
                rs.sort(); gs.sort(); bs.sort()
                let mr = rs[rs.count / 2], mg = gs[gs.count / 2], mb = bs[bs.count / 2]
                for idx in indices { buf.set(idx % w, idx / w, mr, mg, mb) }
            }
        }
    }

    /// 체비셰프 반경 `radius` 팽창(사각 구조요소, 분리형 수평→수직). 마스크를 새 마스크로.
    static func dilateMask(_ mask: [Bool], rw: Int, rh: Int, radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        var horiz = [Bool](repeating: false, count: rw * rh)
        for y in 0..<rh {
            for x in 0..<rw where mask[y * rw + x] {
                let x0 = max(0, x - radius), x1 = min(rw - 1, x + radius)
                for nx in x0...x1 { horiz[y * rw + nx] = true }
            }
        }
        var out = [Bool](repeating: false, count: rw * rh)
        for y in 0..<rh {
            for x in 0..<rw where horiz[y * rw + x] {
                let y0 = max(0, y - radius), y1 = min(rh - 1, y + radius)
                for ny in y0...y1 { out[ny * rw + x] = true }
            }
        }
        return out
    }

    /// 4-이웃 연결요소 중 크기 `minSize` 이상만 남긴 마스크(작고 흩어진 오검출 덩어리 제거). BFS.
    static func largeComponents(_ mask: [Bool], rw: Int, rh: Int, minSize: Int) -> [Bool] {
        let n = rw * rh
        var label = [Int](repeating: 0, count: n)
        var out = [Bool](repeating: false, count: n)
        var stack = [Int]()
        var cur = 0
        for start in 0..<n where mask[start] && label[start] == 0 {
            cur += 1
            label[start] = cur
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var members = [Int]()
            while let p = stack.popLast() {
                members.append(p)
                let x = p % rw, y = p / rw
                if x > 0, mask[p - 1], label[p - 1] == 0 { label[p - 1] = cur; stack.append(p - 1) }
                if x < rw - 1, mask[p + 1], label[p + 1] == 0 { label[p + 1] = cur; stack.append(p + 1) }
                if y > 0, mask[p - rw], label[p - rw] == 0 { label[p - rw] = cur; stack.append(p - rw) }
                if y < rh - 1, mask[p + rw], label[p + rw] == 0 { label[p + rw] = cur; stack.append(p + rw) }
            }
            if members.count >= minSize { for m in members { out[m] = true } }
        }
        return out
    }
}

/// 근무 시간 라벨(캡슐). 모노스페이스 숫자에 반투명 캡슐 배경을 얹어 캐릭터 위에서도 읽히게 한다.
struct CheckOverlayTimerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .fixedSize()
    }
}

/// 3D 캐릭터를 그리는 SCNView 래퍼.
///
/// 배경은 투명하고, 전력 배려를 위해 유휴 8fps(리액션 재생 중에만 30fps)·저(低) 안티에일리어싱으로 둔다.
/// `isActive == false`(패널 숨김)일 때는 `isPlaying=false`/`rendersContinuously=false`로 렌더 루프를 멈춘다.
struct CheckCharacter3DView: NSViewRepresentable {
    /// true일 때만 렌더 루프/애니메이션을 돌린다. 패널 숨김 시 false → 정지(전력 절약).
    var isActive: Bool
    /// 리액션 엔진. makeNSView 에서 wrapper 노드/씬 루트를 연결한다(없으면 리액션 없이 idle 만).
    var engine: ReactionEngine?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = CheckCharacter3DScene.makeScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        // 전력 배려: 안티에일리어싱 최소(2X). FPS 는 유휴(8) 기본값으로 시작하고, 엔진이 리액션 재생 중에만
        // 30 으로 올렸다가 되돌린다(attach 가 뷰를 받아 상태에 맞춰 조절).
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = ReactionEngine.idleFPS
        view.isPlaying = isActive
        view.rendersContinuously = isActive
        if let engine,
           let root = scene?.rootNode,
           let wrapper = root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false) {
            engine.attach(node: wrapper, sceneRoot: root, view: view)
        }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.isPlaying = isActive
        view.rendersContinuously = isActive
    }
}

/// 팀원 출근 인사 말풍선. 캐릭터 왼쪽 위에 뜨는 반투명 캡슐(꼬리 포함). 3초 후 엔진이 텍스트를 비우면 사라진다.
struct CheckGreetingBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(.black.opacity(0.85))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .frame(maxWidth: 110, alignment: .leading)
    }
}

/// 근무 시작 제안(넛지) 말풍선. 인사 말풍선(CheckGreetingBubble) 스타일을 그대로 재사용하되, 탭하면 근무를
/// 시작하는 버튼이다. 캐릭터 왼쪽 위(인사 위치)에 뜬다.
struct CheckNudgePromptBubble: View {
    static let text = "근무 시작할까요?"
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CheckGreetingBubble(text: Self.text)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

/// 넛지 말풍선의 실제 프레임(SwiftUI 좌표, top-left)을 상위로 올리는 PreferenceKey. 컨트롤러가 이 값을
/// AppKit 좌표로 뒤집어 hitTest 클릭 영역으로 쓴다. nil 이면 말풍선 없음(클릭 영역 제거).
struct NudgeBubbleFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// SwiftUI↔AppKit 사각형 좌표 변환(순수 함수). 부분 클릭 영역 계산의 결정적 검증 지점.
enum BubbleHitGeometry {
    /// SwiftUI 좌표(top-left 원점, y 아래로 증가)의 사각형을, 높이 `containerHeight` 인 AppKit 좌표
    /// (bottom-left 원점, y 위로 증가)로 y 반전 변환한다.
    static func appKitRect(fromSwiftUI rect: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: containerHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// 3D 캐릭터 + 근무 시간 라벨 합성. 라벨은 얼굴(볼) 바로 아래 몸통 중상부에 얹는다.
/// 리액션 엔진을 관찰해 팀원 출근 인사 말풍선(및 근무 시작 제안 넛지 말풍선)을 캐릭터 왼쪽 위에 겹쳐 띄운다.
struct CheckOverlayCharacterView: View {
    /// 근무 시간 라벨의 세로 위치 비율(0=상단, 1=하단). 볼 아래 몸통 중상부(얼굴은 안 가림)에 오도록 54%.
    static let timerVerticalFraction: CGFloat = 0.49
    /// 넛지 말풍선 프레임 측정용 좌표 공간 이름(콘텐츠 top-left 기준).
    static let nudgeCoordinateSpace = "check.nudgePanel"

    let elapsedSeconds: Int
    let isActive: Bool
    /// 타이머 라벨 표시 여부(넛지 중에는 false — 00:00 캡슐이 뜨지 않게). 루트 뷰가 showsTimer 로 판정해 넘긴다.
    var showsTimer: Bool = true
    var engine: ReactionEngine?
    /// 넛지 말풍선 탭 콜백(컨트롤러가 store.start 로 잇는다).
    var onNudgeTap: (() -> Void)?
    /// 넛지 말풍선 프레임(SwiftUI 좌표) 변화 콜백. @MainActor 클로저라 @Sendable 경계(onPreferenceChange)를
    /// 넘어 안전하게 캡처된다.
    var onNudgeBubbleFrame: (@MainActor (CGRect?) -> Void)?

    /// 3D 뷰 지연 생성 래치. 한 번이라도 표시된 뒤에는 계속 마운트해 둔다(파괴-재생성은 Metal 전역 메모리를
    /// 거의 회수하지 못하므로). 첫 표시 전까지는 SCNView+USDZ+Metal 로드를 미뤄 유휴 RSS 를 절감한다.
    @State private var hasEverShown = false

    var body: some View {
        GeometryReader { geo in
            // 렌더 루프는 엔진의 renderActive(패널 표시~근무종료 인사)로 몬다. 엔진이 없으면 isActive 로 폴백한다.
            let renderActive = engine?.renderActive ?? isActive
            let nudgeActive = engine?.nudgePromptActive == true
            ZStack(alignment: .topLeading) {
                if renderActive || hasEverShown {
                    CheckCharacter3DView(isActive: renderActive, engine: engine)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                if showsTimer {
                    CheckOverlayTimerLabel(text: CheckOverlayTimeFormatter.text(elapsedSeconds))
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * Self.timerVerticalFraction
                        )
                }
                if nudgeActive {
                    CheckNudgePromptBubble(onTap: { onNudgeTap?() })
                        .background(
                            GeometryReader { bubbleGeo in
                                Color.clear.preference(
                                    key: NudgeBubbleFramePreferenceKey.self,
                                    value: bubbleGeo.frame(in: .named(Self.nudgeCoordinateSpace))
                                )
                            }
                        )
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .transition(.opacity)
                } else if let engine, let greeting = engine.greetingText {
                    CheckGreetingBubble(text: greeting)
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .id(greeting)
                }
            }
            .coordinateSpace(name: Self.nudgeCoordinateSpace)
            .animation(.easeInOut(duration: 0.25), value: engine?.greetingText)
            .animation(.easeInOut(duration: 0.25), value: nudgeActive)
            .onChange(of: renderActive, initial: true) { _, active in
                if active { hasEverShown = true }
            }
            .onPreferenceChange(NudgeBubbleFramePreferenceKey.self) { [onNudgeBubbleFrame] rect in
                // onPreferenceChange 액션은 @Sendable — @MainActor 클로저(onNudgeBubbleFrame)와 CGRect 만
                // 캡처(둘 다 Sendable)해 MainActor 로 넘긴다.
                guard let onNudgeBubbleFrame else { return }
                Task { @MainActor in onNudgeBubbleFrame(rect) }
            }
        }
    }
}

/// 오버레이 패널의 SwiftUI 루트. store를 관찰해 근무 상태 변화 시 콜백으로 패널 표시/숨김을 알린다.
///
/// `store.snapshot`을 body에서 읽어 관찰을 등록하고, `isWorking` 변화를 `onChange`로 컨트롤러에 전달한다.
/// `elapsedSeconds`는 store의 1초 틱을 그대로 따라가므로 라벨이 실시간으로 흐른다.
struct CheckOverlayRootView: View {
    let store: WorkTimerStore
    var engine: ReactionEngine?
    var onWorkingChange: (Bool) -> Void
    /// 넛지 말풍선 탭 콜백(컨트롤러가 store.start 로 잇는다).
    var onNudgeTap: (() -> Void)?
    /// 넛지 말풍선 프레임 변화 콜백(컨트롤러가 hitTest 클릭 영역으로 잇는다).
    var onNudgeBubbleFrame: (@MainActor (CGRect?) -> Void)?

    /// 타이머 라벨을 실제 오늘 누적으로 보여줄지 판정한다. 근무 중이거나, 근무를 막 멈췄어도 근무종료 인사가
    /// 아직 렌더 중(renderActive)이면 실제 시간을 유지해 인사 0.55초 동안 라벨이 00:00 으로 플래시되지 않게 한다.
    /// renderActive 는 숨김 시 항상 false 라, 유휴에서 body 가 매초 재평가되던 낭비를 없애는 목표는 보존된다.
    /// 넛지 중(비근무·nudgeActive)에는 아직 근무 전이라 캡슐이 00:00 으로 뜨지 않게 숨긴다.
    static func showsTimer(isWorking: Bool, isOverlayEnabled: Bool, renderActive: Bool, nudgeActive: Bool = false) -> Bool {
        isOverlayEnabled && (isWorking || renderActive) && !(nudgeActive && !isWorking)
    }

    var body: some View {
        // 오버레이가 실제로 보일 때만 todayDuration 을 읽어 관찰을 건다. 꺼짐/숨김 상태에서 근무중이어도
        // 매초 displayNow 변화로 body 가 재평가되던 낭비를 없앤다(보일 때만 라벨이 초 단위로 흐른다).
        let showing = Self.showsTimer(
            isWorking: store.snapshot.isWorking,
            isOverlayEnabled: store.isOverlayEnabled,
            renderActive: engine?.renderActive == true,
            nudgeActive: engine?.nudgePromptActive == true
        )
        return CheckOverlayCharacterView(
            elapsedSeconds: showing ? store.todayDuration : 0,
            isActive: store.snapshot.isWorking,
            showsTimer: showing,
            engine: engine,
            onNudgeTap: onNudgeTap,
            onNudgeBubbleFrame: onNudgeBubbleFrame
        )
        .onChange(of: store.snapshot.isWorking, initial: true) { _, working in
            onWorkingChange(working)
        }
        // 캐릭터 표시 토글이 근무 중에 바뀌어도 즉시 반영되도록 같은 콜백을 태운다.
        .onChange(of: store.isOverlayEnabled) { _, _ in
            onWorkingChange(store.snapshot.isWorking)
        }
        // 로그인 상태 변화(로그아웃/재로그인)에 맞춰 넛지 스케줄러 가동/정지를 재평가한다(같은 콜백 재사용).
        .onChange(of: store.isSignedIn) { _, _ in
            onWorkingChange(store.snapshot.isWorking)
        }
    }
}

/// 오버레이 근무 시간 표기. 1시간 이상은 HH:MM:SS, 미만은 MM:SS.
///
/// 1시간 미만 구간은 `MenuBarStatusFormatter.duration`(MM:SS)을 그대로 재사용하고,
/// 1시간 이상은 초까지 흐르도록 HH:MM:SS로 확장한다(메뉴바 라벨은 HH:MM이라 별도).
enum CheckOverlayTimeFormatter {
    static func text(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        guard safe >= 3_600 else {
            return MenuBarStatusFormatter.duration(safe)
        }
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let secs = safe % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
