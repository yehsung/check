import AppKit
import ImageIO
import Metal
import os
import SceneKit
import SwiftUI

/// 아잉 3D 캐릭터 씬 구성.
///
/// 리소스 번들(`CheckResources.bundle`)의 캐릭터 모델을 로드하고, 마스코트 원색(보라)이 살도록 모든 재질을
/// unlit(`.constant`)로 바꾼 뒤, 바운딩박스를 기준으로 캐릭터를 살짝 내려다보는 구도로 프레임에 꽉 차게
/// 카메라를 배치한다. 여기에 느린 상하 부유(bob)와 아주 느린 살랑 회전(sway) 애니메이션을 붙인다.
///
/// 기본 PBR/조명에서는 텍스처가 허옇게 떠 마스코트 색이 사라지므로 반드시 `.constant`를 쓴다
/// (오프스크린 렌더로 확인: 조명 모델을 켜면 중앙 픽셀이 거의 흰색, `.constant`면 라벤더 보라).
///
/// 모델 출처는 둘이다(v0.2.38 M3). 빌드 머신에서 미리 구운 `aing.scn`(`scripts/prebake-character.swift` 산출물 —
/// unlit·512 텍스처 베이크까지 끝난 SceneKit 네이티브 아카이브)을 우선 읽고, 없거나 못 읽으면 원본 `aing.usdz` 로
/// 폴백한다. usdz 런타임 임포트는 USD/ModelIO 를 상주시키고(+22~38MB) USD 워커 스레드 11개 + 폴링 슬리퍼 1개를
/// 실행 내내 남기며 2048² 텍스처를 디코드한 뒤 512 로 다시 줄이지만, .scn 은 NSKeyedUnarchiver 경로라 그 어느 것도
/// 만들지 않는다(같은 머신 실측: 로드 65ms + 베이크 78ms → 로드 3ms + PNG 디코드 ~40ms, 스레드 +14 → +0).
enum CheckCharacter3DScene {
    /// 카메라 시야각(도). 거리 산정과 프레이밍에 공통으로 쓴다.
    static let fieldOfView: CGFloat = 40

    /// 번들 모델 출처. **선언 순서가 곧 로드 우선순위**다(프리베이크 → 원본 폴백).
    enum ModelSource: String, CaseIterable {
        /// `scripts/prebake-character.swift` 가 만든 SceneKit 네이티브 아카이브(unlit·512 텍스처 베이크 완료).
        case prebaked = "scn"
        /// 원본 USDZ. 프리베이크가 없거나(구버전 SceneKit 이 새 아카이브를 거부하는 경우 포함) 못 읽을 때의 폴백.
        case usdz = "usdz"
    }

    /// 두 출처가 공유하는 리소스 이름(`aing.scn` / `aing.usdz`).
    static let modelResourceName = "aing"

    /// 출처의 번들 URL. 번들에 없으면 nil.
    static func modelURL(for source: ModelSource) -> URL? {
        CheckResources.bundle.url(forResource: modelResourceName, withExtension: source.rawValue)
    }

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 번들 모델을 SCNScene 으로 로드한다(프리베이크 우선, usdz 폴백). 실패 시 nil.
    static func loadModelScene() -> SCNScene? {
        loadModelScene(order: ModelSource.allCases)?.scene
    }

    /// 특정 출처 하나만 로드한다(계약 테스트·계측용). 실패 시 nil.
    static func loadModelScene(from source: ModelSource) -> SCNScene? {
        loadModelScene(order: [source])?.scene
    }

    /// 출처를 `order` 순서로 시도해 처음 성공한 씬과 그 출처를 돌려준다. `url` 은 출처→URL 해석기 — 테스트가
    /// "프리베이크 없음/손상"을 주입해 폴백을 강제할 수 있게 분리했다.
    ///
    /// 로드가 throw 하거나 지오메트리가 하나도 없으면 실패로 보고 다음 출처로 넘어간다. 프리베이크는 빌드 머신의
    /// SceneKit 이 쓴 아카이브라, 더 오래된 macOS(LSMinimumSystemVersion 14)의 SceneKit 이 거부할 가능성을 배제할
    /// 수 없다 — 그 경우에도 캐릭터가 사라지는 대신 종전 usdz 경로로 내려간다. 출처·소요를 로그로 남겨 배포 후
    /// `log show --predicate 'subsystem == "kingcheck" AND category == "character"'` 로 어느 경로를 탔는지 확인한다.
    static func loadModelScene(
        order: [ModelSource],
        url: (ModelSource) -> URL? = { CheckCharacter3DScene.modelURL(for: $0) }
    ) -> (scene: SCNScene, source: ModelSource)? {
        for source in order {
            guard let fileURL = url(source) else { continue }
            let started = CFAbsoluteTimeGetCurrent()
            guard let scene = try? SCNScene(url: fileURL, options: nil), hasGeometry(scene) else {
                logger.error("character model unreadable source=\(source.rawValue, privacy: .public)")
                continue
            }
            let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            logger.notice(
                "character model loaded source=\(source.rawValue, privacy: .public) ms=\(ms, format: .fixed(precision: 1), privacy: .public)"
            )
            return (scene, source)
        }
        return nil
    }

    /// 로드된 씬에 지오메트리가 하나라도 있는가(부분 로드/손상 아카이브를 폴백으로 넘기기 위한 최소 건전성).
    private static func hasGeometry(_ scene: SCNScene) -> Bool {
        var found = false
        scene.rootNode.enumerateHierarchy { node, stop in
            if node.geometry != nil { found = true; stop.pointee = true }
        }
        return found
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

    /// 감은 선을 눈 앵커(눈 세로 중앙)에서 아래로 내리는 로컬 Y 오프셋. 앵커는 뜬 눈의 세로 중앙이라, 그대로
    /// 얹으면 감은 선이 눈 한가운데에 떠 부자연스럽다. 감은 눈꺼풀이 내려온 모습이 되도록 눈 영역 세로 높이의
    /// 절반가량(하단 경계)만큼 내린다. 값은 오프스크린 렌더 육안 반복으로 잡았다: 280×340 렌더에서 뜬 눈 세로
    /// span≈[92..121]px(≈29px), 선 중앙이 하단 1/3(y≥111)에 앉도록 조정. 1px ≈ 0.0084 로컬유닛이라 앵커
    /// 중앙(선 y≈104) 대비 약 11px 하강해 선 중앙 y≈116(하단 경계)에 위치한다.
    static let closedEyeLowering: CGFloat = 0.095

    /// 감은 눈 커버 시, 눈 앵커(3D) 근처 삼각형을 UV 로 채워 '눈 표면' 마스크를 만들 때의 반경(캐릭터-로컬 유닛).
    /// 눈 하나를 넉넉히 감싸되 코/볼로 넘치지 않는 값 — 오프스크린 렌더 육안 반복으로 튜닝(눈 반경 여유 포함).
    /// 0.24 에서 선 없는 렌더의 유령 눈두덩이 사실상 사라진다(더 작으면 눈두덩 링 잔존, 더 크면 과커버).
    static let eyeCoverRadius: Float = 0.24

    /// 얼굴 디퓨즈의 눈을 피부로 덮은 "감은 눈" 텍스처를 만든다. 메시 지오메트리로 눈 표면 UV 마스크를 산출해
    /// `SleepEyeTexture` 에 넘긴다(색 분류가 놓치는 눈두덩/안구 하이라이트까지 덮어 유령 눈두덩 제거). 지오메트리가
    /// 없거나 마스크 산출 실패면 nil 마스크로 넘어가 색 기반 폴백으로 동작한다. 엔진·테스트가 공통으로 쓴다.
    static func makeClosedEyesImage(faceImage: CGImage, geometry: SCNGeometry?) -> CGImage? {
        let mask = geometry.flatMap {
            SleepEyeTexture.eyeUVCoverMask(
                geometry: $0, anchors: closedEyeAnchors.map { $0.position },
                width: faceImage.width, height: faceImage.height, radius: eyeCoverRadius
            )
        }
        return SleepEyeTexture.closedEyesImage(from: faceImage, eyeMask: mask)
    }

    /// 감은 눈 선 노드 2개를 캐릭터(안쪽, idle 부유/살랑과 함께 움직임)에 자식으로 붙인다. 기본 숨김.
    /// UV 아틀라스가 저폴리로 눈을 여러 조각으로 흩어 텍스처에 깔끔한 감은 선을 그리기 어려우므로, 선은 얼굴
    /// 표면 바로 앞에 얹는 얇은 평면(빌보드 아닌 +Z 정면 — 칠해진 듯 자연스럽게)으로 그린다. 커버(텍스처)로 뜬 눈을
    /// 지우고 그 위에 이 선을 얹어 "감은 눈"을 완성한다. 선은 앵커(눈 세로 중앙)에서 `closedEyeLowering` 만큼
    /// 아래로 내려 눈 하단 경계(내려온 눈꺼풀)에 앉힌다.
    static func addClosedEyeNodes(to character: SCNNode) {
        let image = closedEyeLineImage()
        for (name, pos) in closedEyeAnchors {
            let node = makeClosedEyeNode(image: image)
            node.name = name
            // 표면보다 살짝 앞(+z)에 둬 z-파이팅/가림을 피하고, 눈 세로 중앙에서 하단 경계로 내린다(-y).
            node.position = SCNVector3(pos.x, pos.y - closedEyeLowering, pos.z + 0.035)
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

    /// 모든 재질을 unlit(`.constant`)로 전환하고, 디퓨즈를 **CGImage 로 정규화**하며 상주 텍스처를 다운스케일한다.
    ///
    /// 기본 조명에서 텍스처가 허옇게 뜨는 것을 막아 마스코트 원색을 보존한다. 아울러 원본 텍스처(2048²)를
    /// 패널 표시 크기(280×340@2x)에 맞춰 512px 로 줄여 상주 텍스처 메모리를 크게 절감한다(A8).
    ///
    /// **CGImage 정규화가 계약이다.** ReactionEngine 은 얼굴 재질을 "큰 CGImage 디퓨즈"로 찾아 깜빡임·졸기 감은 눈을
    /// 만든다. usdz 는 아카이브 참조 URL 을, 프리베이크 .scn 은 임베드 PNG `Data` 를 디퓨즈로 돌려주므로, 어느 출처든
    /// 여기서 CGImage 로 통일하지 않으면 얼굴을 못 찾아 깜빡임·감은 눈이 **조용히** 사라진다(테스트 없이는 아무도 모른다).
    static func applyUnlitMaterials(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                material.lightingModel = .constant
                if let baked = downscaledTexture(material.diffuse.contents) {
                    material.diffuse.contents = baked
                }
            }
        }
    }

    /// 디퓨즈 콘텐츠의 베이크 결과 — `maxDimension` 초과면 그 크기로 리샘플한 CGImage, 이하면 CGImage 로 **정규화만** 한 것
    /// (usdz 의 2048² 아카이브 참조 URL → 512² CGImage, 프리베이크 .scn 의 512² PNG Data → 512² CGImage).
    /// 이미 CGImage 이고 충분히 작으면 nil(교체 불필요 — 무손실 no-op). 디코드 불가·비정상 치수·알 수 없는 타입도 nil(교체하지 않음).
    static func downscaledTexture(_ contents: Any?, maxDimension: CGFloat = 512) -> CGImage? {
        guard let decoded = decodedTexture(contents) else { return nil }
        if let smaller = resampled(decoded, maxDimension: maxDimension) { return smaller }
        return isCGImage(contents) ? nil : decoded
    }

    /// 재질 콘텐츠를 CGImage 로 디코드한다. CGImage/NSImage/파일 참조(URL·경로)/인코딩 바이트(Data — .scn 아카이브가
    /// 임베드 이미지를 이렇게 돌려준다)만 처리하고, 알 수 없는 타입이나 비정상 치수(<8px — 예: 아카이브 통짜 오독 → 1×512)면 nil.
    static func decodedTexture(_ contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        let source: CGImage?
        // 주의: CF 불투명 타입(CGImage)으로의 `as?` 캐스트는 실제 타입과 무관하게 성공하므로
        // (NSURL 도 삼켜 쓰레기 치수를 만든다) 반드시 CFGetTypeID 로 판별한다.
        if isCGImage(contents) {
            source = (contents as! CGImage)
        } else if let image = contents as? NSImage {
            source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let url = contents as? URL {
            source = decodeTextureURL(url)
        } else if let path = contents as? String {
            source = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let data = contents as? Data {
            source = decodeTextureData(data)
        } else {
            return nil
        }
        guard let cg = source, cg.width >= 8, cg.height >= 8 else { return nil }
        return cg
    }

    private static func isCGImage(_ contents: Any?) -> Bool {
        guard let contents else { return false }
        return CFGetTypeID(contents as CFTypeRef) == CGImage.typeID
    }

    /// 최장변이 `maxDimension` 을 넘으면 그 크기로 리샘플한 CGImage, 아니면 nil(이미 충분히 작다).
    private static func resampled(_ cg: CGImage, maxDimension: CGFloat) -> CGImage? {
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

    /// 인코딩된 이미지 바이트(PNG 등)를 ImageIO 로 디코드한다. 실패 시 nil.
    private static func decodeTextureData(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
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
    ///
    /// `eyeMask`(선택): 메시 지오메트리로 산출한 '눈 표면' UV 마스크(아틀라스 크기와 동일). 주면 색 분류 대신
    /// 이 영역을 덮는다 — 저폴리 UV 로 흩어진 눈 조각과, **색으로는 피부로 분류돼 놓치던 눈두덩/안구 하이라이트**
    /// 까지 정확히 포함해 감은 상태에서 '유령 눈두덩'이 남지 않는다. 없으면(nil) 색 기반 폴백(구버전).
    static func closedEyesImage(from original: CGImage, eyeMask: [Bool]? = nil) -> CGImage? {
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
        coverEyes(in: &buf, eyeMask: eyeMask)
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

    // MARK: - 전역 눈 커버(입 보호 + 국소 링 채움)

    static func coverEyes(in buf: inout PixelBuffer, eyeMask: [Bool]? = nil) {
        let w = buf.width, h = buf.height, n = w * h
        let (cover, protected, meshBased) = computeCoverMask(in: buf, eyeMask: eyeMask)
        // 채우기.
        let ringRadius = 3
        var brightThreshold = 0
        if meshBased {
            // 메시 커버는 '눈 표면' 전체(눈두덩 음영 텍셀 포함)를 덮는다. 커버를 조각(연결요소)별로 **바로 바깥
            // 링의 진짜 밝은 피부색**으로 채운다. 전역 피부 중앙값은 턱/볼 그림자까지 섞여 눈 주변 밝은 얼굴보다
            // 어두워 커버 패치가 진한 보라로 떠 보였다(실물 확인). 조각 링 중 밝은 피부만(어두운 눈두덩 텍셀 배제)
            // 취해 채우면 모든 조각이 주변 얼굴과 사실상 같은 밝은 피부가 된다.
            let (bt, ref) = eyeRegionBrightSkin(in: buf, cover: cover, ringRadius: ringRadius)
            brightThreshold = bt
            fillCoverFromLocalRing(&buf, cover: cover, brightThreshold: bt, fallback: ref, ringRadius: ringRadius)
        } else {
            // 폴백: 커버를 '미지'로 두고 주변 피부색을 경계에서 안쪽으로 번져 채운다(그라디언트에 자연히 맞물림).
            inpaint(&buf, cover: cover)
        }
        // 페더링(이음새만 녹임): 국소 링 채움이 경계색을 이미 링에 맞춰 두므로, 커버 **전체**가 아니라
        // 경계 밴드(annulus)만 박스 블러해 남은 1px 이음새·에일리어싱을 녹인다. 커버 전체를 페더하면 바깥
        // 넓은 밴드까지 섞여 조각 내부가 국소 링보다 어두워진다(실측 4↑). 깊은 내부는 채움값(≈링)을 유지.
        // **어두운 텍셀 배제(skip)가 핵심**: skip 에 입·볼뿐 아니라 커버 밖 **어두운(밝은 피부 임계 미만) 텍셀**
        // (눈두덩/속눈썹)을 넣는다. 안 그러면 아틀라스상 얇은 조각이 페더 밴드에 통째로 들어가 인접 어두운 눈
        // 텍셀과 평균돼 다시 어두워진다(실측: skip 누락 시 조각이 채움 후에도 5↓ 어두워짐).
        let featherR = max(2, Int((CGFloat(w) * 0.010).rounded()))
        let seamOuter = dilateMask(cover, rw: w, rh: h, radius: featherR)
        let deepInner = erodeMask(cover, rw: w, rh: h, radius: featherR)
        var skip = protected
        if meshBased {
            for i in 0..<n where !cover[i] && !protected[i] {
                let (r, g, b) = buf.rgb(i % w, i / w)
                if luma(r, g, b) < brightThreshold { skip[i] = true }   // 어두운 눈두덩/속눈썹 텍셀 배제.
            }
        }
        var feather = [Bool](repeating: false, count: n)
        // 타깃: 경계 밴드 중 (커버 ∪ 밝은 피부)만 — 어두운 텍셀은 밝히지 않는다(배경/머리 오염 방지).
        for i in 0..<n where seamOuter[i] && !deepInner[i] && !skip[i] { feather[i] = true }
        featherBlur(&buf, region: feather, skip: skip, kernelRadius: 2, iterations: 3)
    }

    /// coverEyes 가 채우기 전에 쓰는 커버/보호 마스크를 산출한다(색 검출 → 보호막 → 커버 결정까지).
    /// 채우기·페더와 분리해 테스트가 '조각별 색차'를 재려고 같은 커버 마스크를 재사용할 수 있게 노출한다.
    /// 반환: (cover=피부로 덮을 텍셀, protected=입·볼 보호 텍셀, meshBased=메시 마스크 사용 여부).
    static func computeCoverMask(in buf: PixelBuffer, eyeMask: [Bool]? = nil)
        -> (cover: [Bool], protected: [Bool], meshBased: Bool) {
        let w = buf.width, h = buf.height, n = w * h
        // 보호막(입·볼)은 항상 색으로 검출 — 눈 커버가 이들을 지우지 않게.
        var eye = [Bool](repeating: false, count: n)
        var red = [Bool](repeating: false, count: n)
        var pink = [Bool](repeating: false, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = buf.rgb(x, y)
                let idx = y * w + x
                if isMouthRed(r, g, b) { red[idx] = true }
                else if isPink(r, g, b) { pink[idx] = true }
                else if isEye(r, g, b) { eye[idx] = true }
            }
        }
        // 입 보호막: 진한 빨강 중 '큰 덩어리'(입·머리)만 남겨(흩어진 iris 오검출 제거) 반경 R 팽창.
        let minRedComponent = max(30, w * h / 6000)
        let redBlobs = largeComponents(red, rw: w, rh: h, minSize: minRedComponent)
        let protectR = max(3, Int((CGFloat(w) * 0.012).rounded()))
        let mouthProtect = dilateMask(redBlobs, rw: w, rh: h, radius: protectR)
        // 보호막 = 입(진빨강) ∪ 볼터치(분홍). 커버/페더가 볼을 지우거나 붉은/분홍을 번지게 하지 않게 뺀다.
        var protected = mouthProtect
        for i in 0..<n where pink[i] { protected[i] = true }

        // 커버 영역 결정.
        var cover: [Bool]
        let baseR = max(2, Int((CGFloat(w) * 0.008).rounded()))
        let meshBased = (eyeMask?.count == n)
        if let eyeMask, meshBased {
            // 메시 기반(정공법): 눈 앵커 근처 삼각형의 UV 를 채운 영역이 곧 '눈 표면'. 색 분류로는 피부색이라
            // 놓치던 눈두덩/안구 하이라이트까지 포함한다. 단, 화면 눈이 심하게 미니피케이션돼 한 화면 픽셀이
            // 여러 텍셀에 대응 → 삼각형 래스터가 텍셀 단위 '레이스 홀'을 남기고, 그 틈이 렌더에서 유령으로 비친다.
            // 그래서 닫힘(작은 틈 메움) → 구멍 채움(둘러싸인 홀 완전 제거) → 팽창(경계 여유)으로 **솔리드**하게 만든다.
            let solidR = max(3, Int((CGFloat(w) * 0.014).rounded()))
            cover = closeMask(eyeMask, rw: w, rh: h, radius: solidR)
            cover = fillHoles(cover, rw: w, rh: h)
            cover = dilateMask(cover, rw: w, rh: h, radius: baseR)
            // 하이브리드 보강: 삼각형 래스터가 놓친 **떠도는 눈 텍셀**(안구 하이라이트/속눈썹 등 isEye)이 눈 영역
            // 근처에 남아 밝은 유령 호(arc)로 비칠 수 있다. 메시 영역을 넓게 팽창한 '눈 근방' 안의 isEye 텍셀을
            // 커버에 합쳐 잡는다(근방 한정이라 화면 밖 머리카락 isEye 는 안 건드림). 구멍도 다시 채운다.
            let nearR = max(6, Int((CGFloat(w) * 0.028).rounded()))
            let nearEye = dilateMask(cover, rw: w, rh: h, radius: nearR)
            for i in 0..<n where nearEye[i] && eye[i] { cover[i] = true }
            cover = fillHoles(cover, rw: w, rh: h)
        } else {
            // 폴백(지오메트리 없음): 색 기반 isEye + 음영 링 기하 확장(구버전 — 유령이 일부 남을 수 있음).
            cover = [Bool](repeating: false, count: n)
            for i in 0..<n { cover[i] = eye[i] && !protected[i] }
            cover = dilateMask(cover, rw: w, rh: h, radius: baseR)
            let ringR = max(4, Int((CGFloat(w) * 0.032).rounded()))
            cover = dilateMask(cover, rw: w, rh: h, radius: ringR)
        }
        for i in 0..<n where protected[i] { cover[i] = false }
        return (cover, protected, meshBased)
    }

    // MARK: - 국소 링 기반 커버 채움(조각별 조화 확산)

    /// 눈 주변 '진짜 밝은 피부'를 추정한다. 커버 바로 바깥 링(dilate `ringRadius`, 커버 제외)의 isSkin 텍셀 중
    /// **루마 임계값 이상**만 취한다. 임계값 = 링 피부 루마 중앙값 − 12: 저폴리 UV 상 눈두덩/속눈썹이 링에
    /// 새어든 어두운 텍셀(isSkin 은 통과하나 실제 피부보다 12↑ 어두움)을 배제하고 진짜 얼굴 피부만 남긴다.
    /// 반환: (임계 루마, 임계 이상 피부 평균색=폴백). 임계 이상 피부가 없으면 전역 피부 중앙값 폴백(임계 0).
    static func eyeRegionBrightSkin(in buf: PixelBuffer, cover: [Bool], ringRadius: Int)
        -> (threshold: Int, ref: (Int, Int, Int)) {
        let w = buf.width, h = buf.height, n = w * h
        let band = dilateMask(cover, rw: w, rh: h, radius: max(1, ringRadius))
        var lumas = [Int]()
        for i in 0..<n where band[i] && !cover[i] {
            let (r, g, b) = buf.rgb(i % w, i / w)
            if isSkin(r, g, b) { lumas.append(luma(r, g, b)) }
        }
        guard !lumas.isEmpty else { return (0, skinMedian(in: buf, exclude: cover)) }
        lumas.sort()
        let threshold = lumas[lumas.count / 2] - 12
        var sr = 0, sg = 0, sb = 0, c = 0
        for i in 0..<n where band[i] && !cover[i] {
            let (r, g, b) = buf.rgb(i % w, i / w)
            if isSkin(r, g, b) && luma(r, g, b) >= threshold { sr += r; sg += g; sb += b; c += 1 }
        }
        guard c > 0 else { return (0, skinMedian(in: buf, exclude: cover)) }
        return (threshold, (sr / c, sg / c, sb / c))
    }

    /// 커버를 조각(아틀라스에 흩어진 연결요소)별로, 그 조각 **바로 바깥 링의 '진짜 밝은 피부' 텍셀 평균색**으로
    /// 평탄 채움한다(조각마다 국소 밝은 피부색 — 눈 주변 얼굴색). 마감 이음새는 coverEyes 의 경계 페더가 녹인다.
    ///
    /// 왜 국소 링인가: 전역 피부 중앙값 평면 채움은 턱/볼 그림자까지 섞여 눈 주변 밝은 얼굴보다 어두워, 커버
    /// 패치가 주변보다 진한 보라로 떠 보였다(실물 확인). 각 조각 바로 바깥 링은 그 조각이 화면에서 얹히는 눈
    /// 자리의 **주변 얼굴 피부**이므로, 그 링 평균으로 조각을 채우면 주변과 사실상 같은 색이 된다.
    ///
    /// **밝기 필터가 핵심**: 저폴리 UV 라 한 눈이 아틀라스 여러 조각으로 흩어지는데, 작은 조각의 링에는
    /// 눈두덩/속눈썹의 **어두운 텍셀이 섞여 든다**(isSkin 은 루마>120 이라 이들도 '피부'로 통과 — 실측 루마 121~190).
    /// 이걸 링 시드로 쓰면 그 조각만 어둡게 채워져 화면 눈 자리에 **진한 보라 얼룩**이 남는다(실측: 렌더에서
    /// 주변보다 14↓). 그래서 링 시드를 `eyeRegionBrightSkin` 이 구한 **밝기 임계값 이상의 피부만**으로 거른다 —
    /// 진짜 눈 주변 얼굴 피부(루마 195~237)만 남아 모든 조각이 주변과 일치하는 밝은 피부로 채워진다.
    /// 밝은 피부 시드가 없는 조각만 전역 밝은 피부(fallback) 폴백.
    ///
    /// (조화 확산이 아니라 조각 평탄 채움인 이유: 이 UV 는 아틀라스 인접≠화면 인접이라 조각 내부로 확산하면
    ///  인접 어두운 텍셀 쪽으로 경계값이 끌려 조각 평균이 링보다 어두워졌다(실측 5↓). 조각은 화면상 좁아
    ///  내부 그라디언트가 거의 없으므로 링 평균 평탄 채움이 색 일치·검증(내부평균≈링평균)에 모두 유리하다.)
    ///
    /// `pullToRef`: 조각 링 평균을 전역 밝은 피부(fallback)로 당기는 비율. 같은 UV 인접≠화면 인접 문제로,
    /// 아틀라스에서 어두운 이웃을 링으로 갖는 조각이 화면상 밝은 눈 자리에 얹혀 국소 링만 쓰면 주변보다 어둡게
    /// 남는다(실측 렌더 3↓). 전역 밝은 눈주변 피부로 절반 당기면 화면 눈 자리가 주변과 더 균일해진다(실측 렌더
    /// 3↓→2↓). 1.0(완전 전역)이면 화면은 완벽하나 조각-링 정량검증이 흩어진 조각에서 4↑로 깨져, 0.5 로 둔다.
    ///
    /// 성능: 커버 텍셀(수천) 한정 스캔이라 512² 에서도 수 ms. 지오메트리당 1회 생성 규약 유지.
    static func fillCoverFromLocalRing(_ buf: inout PixelBuffer, cover: [Bool],
                                       brightThreshold: Int, fallback: (Int, Int, Int),
                                       ringRadius: Int = 3, pullToRef: Float = 0.5) {
        let w = buf.width, h = buf.height, n = w * h
        // 링에 밝은 피부가 없는 조각용 폴백색(전역 밝은 피부).
        let (gmr, gmg, gmb) = fallback
        let comps = connectedComponents(cover, rw: w, rh: h)
        var isRing = [Bool](repeating: false, count: n)   // 조각마다 재사용(끝에 리셋 — 링 텍셀 중복 집계 방지).
        let rr = max(1, ringRadius)
        for members in comps {
            // 1) 링 시드 수집: 멤버의 ringRadius 체비셰프 이웃 중 커버 아님 & **밝은 피부**(임계 이상).
            //    (링 텍셀은 항상 커버 밖 → 다른 조각을 채워도 값이 안 바뀌므로 조각 처리 순서와 무관.)
            var ringList = [Int]()
            for p in members {
                let px = p % w, py = p / w
                var dy = -rr
                while dy <= rr {
                    let ny = py + dy
                    if ny >= 0 && ny < h {
                        var dx = -rr
                        while dx <= rr {
                            let nx = px + dx
                            if nx >= 0 && nx < w {
                                let q = ny * w + nx
                                if !cover[q] && !isRing[q] {
                                    let (r, g, b) = buf.rgb(nx, ny)
                                    if isSkin(r, g, b) && luma(r, g, b) >= brightThreshold {
                                        isRing[q] = true; ringList.append(q)
                                    }
                                }
                            }
                            dx += 1
                        }
                    }
                    dy += 1
                }
            }
            // 2) 링에 밝은 피부가 없으면 그 조각만 전역 밝은 피부 폴백.
            if ringList.isEmpty {
                for p in members { buf.set(p % w, p / w, gmr, gmg, gmb) }
                continue
            }
            // 3) 밝은 링 평균으로 조각 전체를 평탄 채움(반올림).
            var sr = 0, sg = 0, sb = 0
            for q in ringList { let (r, g, b) = buf.rgb(q % w, q / w); sr += r; sg += g; sb += b }
            let rc = ringList.count
            let lr = Float(sr) / Float(rc), lg = Float(sg) / Float(rc), lb = Float(sb) / Float(rc)
            // 전역 밝은 피부(fallback)로 pullToRef 만큼 당긴다: 저폴리 UV 는 아틀라스 인접≠화면 인접이라, 화면상
            // 밝은 눈 자리에 얹히는 조각이 아틀라스에선 어두운 이웃을 링으로 갖는 경우가 있다(국소 링만 쓰면 그
            // 조각이 화면에서 주변보다 어둡게 남음). 전역 밝은 눈주변 피부로 조금 당겨 화면 균일도를 높인다.
            let f = min(max(pullToRef, 0), 1)
            let mr = Int((lr * (1 - f) + Float(gmr) * f).rounded())
            let mg = Int((lg * (1 - f) + Float(gmg) * f).rounded())
            let mb = Int((lb * (1 - f) + Float(gmb) * f).rounded())
            for p in members { buf.set(p % w, p / w, mr, mg, mb) }
            for q in ringList { isRing[q] = false }
        }
    }

    /// 4-이웃 연결요소들을 각 요소의 픽셀 인덱스 배열로 반환(BFS). 조각별 처리(국소 링 채움·색차 검증)에 쓴다.
    static func connectedComponents(_ mask: [Bool], rw: Int, rh: Int) -> [[Int]] {
        let n = rw * rh
        var label = [Bool](repeating: false, count: n) // 방문 표시.
        var comps = [[Int]]()
        var stack = [Int]()
        for start in 0..<n where mask[start] && !label[start] {
            label[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var members = [Int]()
            while let p = stack.popLast() {
                members.append(p)
                let x = p % rw, y = p / rw
                if x > 0, mask[p - 1], !label[p - 1] { label[p - 1] = true; stack.append(p - 1) }
                if x < rw - 1, mask[p + 1], !label[p + 1] { label[p + 1] = true; stack.append(p + 1) }
                if y > 0, mask[p - rw], !label[p - rw] { label[p - rw] = true; stack.append(p - rw) }
                if y < rh - 1, mask[p + rw], !label[p + rw] { label[p + rw] = true; stack.append(p + rw) }
            }
            comps.append(members)
        }
        return comps
    }

    // MARK: - 메시 기반 눈 UV 커버 마스크(색 분류가 놓치는 눈두덩/안구 하이라이트까지 정확히 덮는다)

    /// 눈 앵커(3D, 캐릭터-로컬) 근처 삼각형들의 UV 를 아틀라스 픽셀에 래스터화해 '눈 표면' 마스크를 만든다.
    ///
    /// 왜 메시인가: 이 저폴리 UV 는 한 눈이 아틀라스 여러 조각으로 흩어지고, 화면상 눈 영역이 심하게 미니피케이션
    /// 돼(한 화면 픽셀이 여러 텍셀에 대응) 색·화면샘플 기반 마스크로는 조각을 다 못 잡는다. 반면 눈 앵커 3D 근처
    /// 삼각형을 UV 공간에서 **통짜로 채우면** 눈 표면의 모든 텍셀(피부색으로 분류돼 놓치던 눈두덩/안구 하이라이트
    /// 포함)을 빠짐없이 덮는다 → 감은 상태 유령 눈두덩이 사라진다. 지오메트리 소스는 노드 포즈와 무관(앵커와 같은
    /// 로컬 좌표계)하므로 변환 없이 그대로 쓴다. 실패(소스 없음/삼각형 아님) 시 nil → 색 기반 폴백.
    static func eyeUVCoverMask(geometry: SCNGeometry, anchors: [SCNVector3],
                              width: Int, height: Int, radius: Float) -> [Bool]? {
        guard let vsrc = geometry.sources(for: .vertex).first,
              let tsrc = geometry.sources(for: .texcoord).first,
              let element = geometry.elements.first,
              element.primitiveType == .triangles else { return nil }
        let verts = readFloat3(vsrc)
        let uvs = readFloat2(tsrc)
        guard !verts.isEmpty, uvs.count == verts.count else { return nil }
        let indices = readTriangleIndices(element)
        guard indices.count >= 3 else { return nil }
        var mask = [Bool](repeating: false, count: width * height)
        let anch = anchors.map { (Float($0.x), Float($0.y), Float($0.z)) }
        let r2 = radius * radius
        let triCount = indices.count / 3
        for t in 0..<triCount {
            let i0 = indices[t * 3], i1 = indices[t * 3 + 1], i2 = indices[t * 3 + 2]
            guard i0 < verts.count, i1 < verts.count, i2 < verts.count else { continue }
            let v0 = verts[i0], v1 = verts[i1], v2 = verts[i2]
            // 삼각형 정점 중 하나라도 어느 앵커 반경 내면 포함(경계 삼각형까지 빠짐없이).
            var near = false
            for a in anch where dist2(v0, a) <= r2 || dist2(v1, a) <= r2 || dist2(v2, a) <= r2 {
                near = true; break
            }
            if !near { continue }
            let p0 = uvPixel(uvs[i0], width, height)
            let p1 = uvPixel(uvs[i1], width, height)
            let p2 = uvPixel(uvs[i2], width, height)
            // UV 시접(seam)을 가로지르는 비정상적으로 큰 삼각형은 건너뛴다(아틀라스 넓은 span 오염 방지).
            let spanX = max(p0.0, p1.0, p2.0) - min(p0.0, p1.0, p2.0)
            let spanY = max(p0.1, p1.1, p2.1) - min(p0.1, p1.1, p2.1)
            if spanX > width / 4 || spanY > height / 4 { continue }
            fillTriangle(p0, p1, p2, into: &mask, width: width, height: height)
        }
        return mask
    }

    @inline(__always)
    private static func dist2(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> Float {
        let dx = a.0 - b.0, dy = a.1 - b.1, dz = a.2 - b.2
        return dx * dx + dy * dy + dz * dz
    }

    /// UV(0..1) → 아틀라스 픽셀. V 는 뒤집지 않는다(실측: v·h 가 CGImage 행 원점 좌상단과 일치). 밖은 클램프.
    @inline(__always)
    private static func uvPixel(_ uv: (Float, Float), _ w: Int, _ h: Int) -> (Int, Int) {
        let u = min(max(uv.0, 0), 1), v = min(max(uv.1, 0), 1)
        return (min(w - 1, Int(u * Float(w))), min(h - 1, Int(v * Float(h))))
    }

    /// 삼각형 채우기(스캔라인 + 바리센트릭). 아주 작은 삼각형도 놓치지 않게 세 꼭짓점 픽셀은 항상 찍는다.
    private static func fillTriangle(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int),
                                     into mask: inout [Bool], width: Int, height: Int) {
        for p in [a, b, c] where p.0 >= 0 && p.0 < width && p.1 >= 0 && p.1 < height {
            mask[p.1 * width + p.0] = true
        }
        let minx = max(0, min(a.0, b.0, c.0)), maxx = min(width - 1, max(a.0, b.0, c.0))
        let miny = max(0, min(a.1, b.1, c.1)), maxy = min(height - 1, max(a.1, b.1, c.1))
        if minx > maxx || miny > maxy { return }
        let denom = (b.1 - c.1) * (a.0 - c.0) + (c.0 - b.0) * (a.1 - c.1)
        if denom == 0 { return } // 퇴화 삼각형은 꼭짓점만(위에서 처리).
        let fd = Float(denom)
        for y in miny...maxy {
            for x in minx...maxx {
                let w0 = Float((b.1 - c.1) * (x - c.0) + (c.0 - b.0) * (y - c.1)) / fd
                let w1 = Float((c.1 - a.1) * (x - c.0) + (a.0 - c.0) * (y - c.1)) / fd
                let w2 = 1 - w0 - w1
                if w0 >= 0, w1 >= 0, w2 >= 0 { mask[y * width + x] = true }
            }
        }
    }

    /// SCNGeometrySource(float3)를 [(x,y,z)] 로 읽는다(stride/offset 준수).
    private static func readFloat3(_ src: SCNGeometrySource) -> [(Float, Float, Float)] {
        let stride = src.dataStride, offset = src.dataOffset, cnt = src.vectorCount
        var out = [(Float, Float, Float)](); out.reserveCapacity(cnt)
        src.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<cnt {
                let p = base.advanced(by: offset + i * stride).assumingMemoryBound(to: Float.self)
                out.append((p[0], p[1], p[2]))
            }
        }
        return out
    }

    /// SCNGeometrySource(float2 texcoord)를 [(u,v)] 로 읽는다.
    private static func readFloat2(_ src: SCNGeometrySource) -> [(Float, Float)] {
        let stride = src.dataStride, offset = src.dataOffset, cnt = src.vectorCount
        var out = [(Float, Float)](); out.reserveCapacity(cnt)
        src.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<cnt {
                let p = base.advanced(by: offset + i * stride).assumingMemoryBound(to: Float.self)
                out.append((p[0], p[1]))
            }
        }
        return out
    }

    /// 삼각형 요소의 인덱스를 [Int] 로 읽는다(UInt32/UInt16 지원).
    private static func readTriangleIndices(_ e: SCNGeometryElement) -> [Int] {
        let count = e.primitiveCount * 3
        var out = [Int](); out.reserveCapacity(count)
        e.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            if e.bytesPerIndex == 4 {
                let p = base.assumingMemoryBound(to: UInt32.self)
                for i in 0..<count { out.append(Int(p[i])) }
            } else if e.bytesPerIndex == 2 {
                let p = base.assumingMemoryBound(to: UInt16.self)
                for i in 0..<count { out.append(Int(p[i])) }
            }
        }
        return out
    }

    /// 커버 경계 페더링 — `region` 픽셀을 반복 박스 블러(±`kernelRadius`)로 확산해 남은 눈두덩 음영/이음새가
    /// 주변 밝은 피부색으로 수렴하게 한다. 각 반복은 현재 버퍼를 읽어 새 값을 한꺼번에 반영(제자리 갱신 편향 방지).
    /// `skip` 이웃(입·볼)은 평균에서 빼 붉은/분홍이 번지지 않게 하고, region 은 skip 을 이미 제외했으므로
    /// 대상으로도 안 쓴다. region 바깥 밝은 피부(원본)를 소스로 끌어와 반복할수록 부드러운 그라데이션이 된다.
    /// 반복·커널은 커버 영역 한정이라 512² 전체가 아닌 수천 픽셀만 돌아 비용이 작다(1회 생성 규약 유지).
    static func featherBlur(_ buf: inout PixelBuffer, region: [Bool], skip: [Bool],
                            kernelRadius: Int = 1, iterations: Int) {
        let w = buf.width, h = buf.height
        let kr = max(1, kernelRadius)
        var targets = [Int]()
        for i in 0..<(w * h) where region[i] { targets.append(i) }
        guard !targets.isEmpty, iterations > 0 else { return }
        for _ in 0..<iterations {
            var updates = [(Int, Int, Int, Int)]()
            updates.reserveCapacity(targets.count)
            for idx in targets {
                let x = idx % w, y = idx / w
                var sr = 0, sg = 0, sb = 0, cnt = 0
                var dy = -kr
                while dy <= kr {
                    var dx = -kr
                    while dx <= kr {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < w, ny >= 0, ny < h {
                            let ni = ny * w + nx
                            if !skip[ni] {
                                let (r, g, b) = buf.rgb(nx, ny)
                                sr += r; sg += g; sb += b; cnt += 1
                            }
                        }
                        dx += 1
                    }
                    dy += 1
                }
                if cnt > 0 { updates.append((idx, sr / cnt, sg / cnt, sb / cnt)) }
            }
            for (idx, r, g, b) in updates { buf.set(idx % w, idx / w, r, g, b) }
        }
    }

    /// 커버 밖 '피부' 픽셀의 전역 중앙값(밝은 이마/볼 피부색). 어두운 눈두덩·눈·입·볼 색에 오염되지 않게
    /// isSkin 만 표본으로 삼는다. 표본이 없으면 안전한 라벤더 기본값.
    static func skinMedian(in buf: PixelBuffer, exclude cover: [Bool]) -> (Int, Int, Int) {
        let w = buf.width, h = buf.height
        var rs = [Int](), gs = [Int](), bs = [Int]()
        var i = 0
        while i < w * h {
            if !cover[i] {
                let (r, g, b) = buf.rgb(i % w, i / w)
                if isSkin(r, g, b) { rs.append(r); gs.append(g); bs.append(b) }
            }
            i += 3 // 3픽셀 간격 표본(비용 절감, 중앙값엔 충분).
        }
        guard !rs.isEmpty else { return (207, 186, 254) }
        rs.sort(); gs.sort(); bs.sort()
        return (rs[rs.count / 2], gs[gs.count / 2], bs[bs.count / 2])
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

    /// 체비셰프 반경 `radius` 침식(팽창의 쌍대 — 여집합을 팽창 후 다시 여집합).
    /// 이미지 경계 밖은 전경으로 간주해(dilateMask 가 클램프) 경계에 닿은 마스크는 안 깎인다 — 눈 블롭은
    /// 아틀라스 내부라 무관하고, 닫힘(팽창→침식)에서 내부 작은 구멍만 메우려는 목적에 맞다.
    static func erodeMask(_ mask: [Bool], rw: Int, rh: Int, radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        var comp = [Bool](repeating: false, count: rw * rh)
        for i in 0..<(rw * rh) { comp[i] = !mask[i] }
        let grown = dilateMask(comp, rw: rw, rh: rh, radius: radius)
        var out = [Bool](repeating: false, count: rw * rh)
        for i in 0..<(rw * rh) { out[i] = !grown[i] }
        return out
    }

    /// 닫힘(팽창→침식): 마스크의 작은 구멍/틈(레이스)을 메워 솔리드하게. 전체 크기는 거의 안 키운다.
    static func closeMask(_ mask: [Bool], rw: Int, rh: Int, radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        return erodeMask(dilateMask(mask, rw: rw, rh: rh, radius: radius), rw: rw, rh: rh, radius: radius)
    }

    /// 마스크 내부 구멍 채우기: 테두리에서 4-이웃 BFS 로 '바깥 배경'을 표시하고, 배경도 마스크도 아닌(둘러싸인)
    /// 픽셀을 마스크로 채운다. 눈 블롭 속 미니피케이션 레이스 홀을 완전히 메운다.
    static func fillHoles(_ mask: [Bool], rw: Int, rh: Int) -> [Bool] {
        let n = rw * rh
        var outside = [Bool](repeating: false, count: n)
        var stack = [Int]()
        // 테두리의 비마스크 픽셀에서 시작.
        for x in 0..<rw {
            for y in [0, rh - 1] {
                let i = y * rw + x
                if !mask[i], !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        for y in 0..<rh {
            for x in [0, rw - 1] {
                let i = y * rw + x
                if !mask[i], !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        while let p = stack.popLast() {
            let x = p % rw, y = p / rw
            if x > 0 { let q = p - 1; if !mask[q], !outside[q] { outside[q] = true; stack.append(q) } }
            if x < rw - 1 { let q = p + 1; if !mask[q], !outside[q] { outside[q] = true; stack.append(q) } }
            if y > 0 { let q = p - rw; if !mask[q], !outside[q] { outside[q] = true; stack.append(q) } }
            if y < rh - 1 { let q = p + rw; if !mask[q], !outside[q] { outside[q] = true; stack.append(q) } }
        }
        var out = mask
        for i in 0..<n where !mask[i] && !outside[i] { out[i] = true } // 둘러싸인 구멍 = 채움.
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
/// 배경은 투명하고, 전력 배려를 위해 유휴 fps(리액션 재생 중에만 30fps)·저(低) 안티에일리어싱으로 둔다.
///
/// 렌더 활성은 `isActive && !engine.renderSuspended` 다(v0.2.38 β1/β2 계약). `isActive` 는 표시 의도(패널 표시~
/// 근무종료 인사), `renderSuspended` 는 "지금 아무도 못 보는 순간"(화면 슬립·잠금·세션 비활성)이다. 캐릭터는 근무 중
/// 보일 때는 항상 살아 있어야 하므로 멈추는 건 이 둘 중 하나가 꺼졌을 때뿐이다.
///
/// 비활성이면 `applyRenderState` 가 렌더 루프를 **진짜로** 멈춘다. `isPlaying=false`/`rendersContinuously=false` 만으로는
/// idle 무한 SCNAction(부유·살랑)이 살아 있어 SCNView 가 계속 그렸다(같은 머신 실측 7.3fps — 창을 orderOut 해도 같다).
/// 캐릭터 루트 노드를 `isPaused` 로 세워야 ~0.4초 꼬리 뒤 0fps 가 되고, 그때 렌더 루프가 붙들던 GPU 풀(≈100MB)이
/// 회수된다. 마지막 프레임은 화면에 그대로 남는다(슬립/잠금 정지에서 중요 — 깨어나면 그 자리에서 이어진다).
struct CheckCharacter3DView: NSViewRepresentable {
    /// 표시 의도. 패널 숨김 시 false → 정지(전력 절약).
    var isActive: Bool
    /// 리액션 엔진. makeNSView 에서 wrapper 노드/씬 루트를 연결한다(없으면 리액션 없이 idle 만).
    var engine: ReactionEngine?

    /// 렌더 활성 판정(순수 함수, β1 계약 식). 표시 의도가 있고 정지 사유가 없을 때만 true.
    static func renderActive(isActive: Bool, renderSuspended: Bool) -> Bool {
        isActive && !renderSuspended
    }

    /// `engine.renderSuspended` 를 읽는 **유일한 지점**. @Observable 읽기라 값이 바뀌면 SwiftUI 가 updateNSView 를
    /// 다시 부른다(NSViewRepresentable 의 make/update 도 관찰 추적 범위 안이다 — V0238CharacterTests 가 호스팅 뷰로 확인).
    private var effectiveActive: Bool {
        Self.renderActive(isActive: isActive, renderSuspended: engine?.renderSuspended ?? false)
    }

    /// 정지/재개가 세우고 푸는 캐릭터 루트 = 리액션 wrapper(그 아래 facing → idle 캐릭터). 리액션 액션은 wrapper 에,
    /// idle 무한 액션은 안쪽 캐릭터에 걸리므로 wrapper 하나를 세우면 캐릭터의 모든 액션이 선다. 엔진이 씬 루트에 다는
    /// 일시 파티클 노드(색종이·💤)는 **일부러 포함하지 않는다** — 파티클 시스템은 어느 노드/씬 isPaused 로도 멈추지
    /// 않고(실측), 자가 제거 액션까지 세우면 정지 중 노드만 남는다. 짧은 수명이 다하면 스스로 사라지고 루프도 선다.
    /// wrapper 가 없으면(임포트 실패로 캐릭터 없는 씬) 씬 루트.
    static func characterRootNode(in scene: SCNScene?) -> SCNNode? {
        guard let scene else { return nil }
        return scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
            ?? scene.rootNode
    }

    /// 렌더 루프 게이트 — isPlaying/rendersContinuously 와 캐릭터 루트 isPaused 를 **한 곳에서 짝으로** 내리고 올린다.
    /// 재개는 isPaused 해제 → isPlaying 순(정지 중 쌓인 액션이 첫 프레임부터 이어지게), 정지는 그 역순.
    static func applyRenderState(active: Bool, to view: SCNView) {
        let root = characterRootNode(in: view.scene)
        if active {
            root?.isPaused = false
            view.isPlaying = true
            view.rendersContinuously = true
        } else {
            view.isPlaying = false
            view.rendersContinuously = false
            root?.isPaused = true
        }
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = CheckCharacter3DScene.makeScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        // 전력 배려: 안티에일리어싱 최소(2X). FPS 는 유휴 기본값으로 시작하고, 엔진이 리액션 재생 중에만
        // 30 으로 올렸다가 되돌린다(attach 가 뷰를 받아 상태에 맞춰 조절).
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = ReactionEngine.idleFPS
        Self.applyRenderState(active: effectiveActive, to: view)
        if let engine,
           let root = scene?.rootNode,
           let wrapper = root.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false) {
            engine.attach(node: wrapper, sceneRoot: root, view: view)
        }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        Self.applyRenderState(active: effectiveActive, to: view)
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

/// 울트라 격발 전용 말풍선. 기존 CheckGreetingBubble 은 caption2·maxWidth 110 이라 전체화면에서는
/// 화면 구석의 먼지처럼 보인다 — 같은 시각 언어(흰 캡슐 + 그림자)를 유지한 채 크기만 키운다.
struct CheckUltraBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(.black.opacity(0.88))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .shadow(color: .black.opacity(0.30), radius: 10, y: 3)
            .frame(maxWidth: 520)
    }
}

/// 3D 캐릭터 + 근무 시간 라벨 합성. 라벨은 얼굴(볼) 바로 아래 몸통 중상부에 얹는다.
/// 리액션 엔진을 관찰해 팀원 출근 인사·근무 시작 안내 등 말풍선을 캐릭터 왼쪽 위에 겹쳐 띄운다.
struct CheckOverlayCharacterView: View {
    /// 근무 시간 라벨의 세로 위치 비율(0=상단, 1=하단). 볼 아래 몸통 중상부(얼굴은 안 가림)에 오도록 54%.
    static let timerVerticalFraction: CGFloat = 0.49

    /// 울트라 격발 시 캐릭터가 설 정사각형 한 변의 비율(뷰 짧은 변 기준).
    static let ultraSideRatio: CGFloat = 0.98

    /// 순수 함수 — 헤드리스로 고정한다.
    /// **정사각인 이유**: SCNCamera.projectionDirection 이 .automatic 이라(씬은 fieldOfView 만 세운다),
    /// 뷰가 가로로 길면 FOV(40°)가 가로축에 걸리는지 세로축에 걸리는지에 따라 캐릭터 크기가 달라진다
    /// (모니터 비율마다 다른 크기). 정사각에서는 두 해석의 결과가 같아 어떤 화면에서도 같은 크기가 나온다.
    /// 덤: drawable 이 1512x945 대신 945x945 라 5초간의 GPU/RSS 스파이크가 작다.
    static func ultraSide(
        viewSize: CGSize,
        ratio: CGFloat = CheckOverlayCharacterView.ultraSideRatio
    ) -> CGFloat {
        max(1, min(viewSize.width, viewSize.height) * ratio)
    }

    /// 캐릭터 3D 상자의 크기(순수 함수). 평시엔 **뷰 크기 그대로**(지금과 완전히 동일한 값), 격발 중엔
    /// 짧은 변의 98% 정사각. body 가 이 값만 갈아끼우고 **뷰 구조는 건드리지 않는다** — if/else 로 가르면
    /// NSViewRepresentable 아이덴티티가 바뀌어 SCNView 가 파괴·재생성되고, makeNSView 가 USDZ 재로드 +
    /// 전 재질 순회를, engine.attach 가 감은눈 텍스처(연결성분 라벨링)를 메인 스레드에서 다시 만든다 —
    /// 5초 안에 두 번. 게다가 재-attach 가 .playing 을 보고 5초 액션을 t=0 부터 다시 걸어 잦아듦이 잘린다.
    static func characterBoxSize(viewSize: CGSize, isUltra: Bool) -> CGSize {
        guard isUltra else { return viewSize }
        let side = ultraSide(viewSize: viewSize)
        return CGSize(width: side, height: side)
    }

    let elapsedSeconds: Int
    let isActive: Bool
    /// 타이머 라벨 표시 여부. 루트 뷰가 showsTimer 로 판정해 넘긴다.
    var showsTimer: Bool = true
    var engine: ReactionEngine?

    /// 3D 뷰 지연 생성 래치. 한 번이라도 표시된 뒤에는 계속 마운트해 둔다(파괴-재생성은 Metal 전역 메모리를
    /// 거의 회수하지 못하므로). 첫 표시 전까지는 SCNView+USDZ+Metal 로드를 미뤄 유휴 RSS 를 절감한다.
    @State private var hasEverShown = false

    var body: some View {
        GeometryReader { geo in
            // 렌더 루프는 엔진의 renderActive(패널 표시~근무종료 인사)로 몬다. 엔진이 없으면 isActive 로 폴백한다.
            let renderActive = engine?.renderActive ?? isActive
            let ultra = engine?.isUltraActive == true
            // 격발 중엔 짧은 변의 98% 정사각, 평시엔 뷰 전체(= 지금과 완전히 동일한 값).
            // **격발/평시를 구조로 가르지 말 것** — 이유는 characterBoxSize 주석에.
            let charBox = Self.characterBoxSize(viewSize: geo.size, isUltra: ultra)
            ZStack(alignment: .topLeading) {
                if renderActive || hasEverShown {
                    CheckCharacter3DView(isActive: renderActive, engine: engine)
                        .frame(width: charBox.width, height: charBox.height)
                        // 평시엔 안쪽 frame 과 같은 값이라 무영향, 격발 중엔 정사각을 화면 정중앙에 앉힌다.
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                // 타이머 라벨은 격발 중 숨긴다 — 전체화면 한복판의 작은 MM:SS 는 정보도 장식도 아니고,
                // 라벨 위치가 높이의 49%라 거대 캐릭터의 배 한가운데 박힌다. 조건만 바뀌므로 안전하다.
                if showsTimer && !ultra {
                    CheckOverlayTimerLabel(text: CheckOverlayTimeFormatter.text(elapsedSeconds))
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * Self.timerVerticalFraction
                        )
                }
                if let engine, let greeting = engine.greetingText {
                    // 말풍선만은 if/else 로 갈라도 안전하다(순수 Text 뷰라 재생성 비용이 0).
                    if ultra {
                        CheckUltraBubble(text: greeting)
                            .position(
                                x: geo.size.width / 2,
                                y: max(40, geo.size.height / 2 - charBox.height / 2 + 56)
                            )
                            .id(greeting)
                    } else {
                        CheckGreetingBubble(text: greeting)
                            .padding(.leading, 4)
                            .padding(.top, 8)
                            .transition(.opacity)
                            .id(greeting)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: engine?.greetingText)
            .onChange(of: renderActive, initial: true) { _, active in
                if active { hasEverShown = true }
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

    /// 타이머 라벨을 실제 오늘 누적으로 보여줄지 판정한다. 근무 중이거나, 근무를 막 멈췄어도 근무종료 인사가
    /// 아직 렌더 중(renderActive)이면 실제 시간을 유지해 인사 0.55초 동안 라벨이 00:00 으로 플래시되지 않게 한다.
    /// renderActive 는 숨김 시 항상 false 라, 유휴에서 body 가 매초 재평가되던 낭비를 없애는 목표는 보존된다.
    static func showsTimer(isWorking: Bool, isOverlayEnabled: Bool, renderActive: Bool) -> Bool {
        isOverlayEnabled && (isWorking || renderActive)
    }

    var body: some View {
        // 오버레이가 실제로 보일 때만 누적을 읽어 관찰을 건다. 꺼짐/숨김 상태에서 근무중이어도
        // 매초 시계 변화로 body 가 재평가되던 낭비를 없앤다(보일 때만 라벨이 초 단위로 흐른다).
        let showing = Self.showsTimer(
            isWorking: store.snapshot.isWorking,
            isOverlayEnabled: store.isOverlayEnabled,
            renderActive: engine?.renderActive == true
        )
        // ★ 라벨은 **오버레이 시계**(overlayNow → overlayTodayDuration)를 따른다(v0.2.38 M1). `store.todayDuration` 은
        //   팝오버 시계(displayNow) 파생인데, 그 시계는 팝오버가 **열려 있을 때만** 매초 갱신되므로 그대로 두면 팝오버가
        //   닫힌 동안 캐릭터 라벨이 멈춘다. overlayNow 는 이 패널이 보일 때(오버레이 켜짐 && 근무 중)만 티커가 대입하므로
        //   숨김 상태의 헛재평가도 없다(V0238ClockTests 가 두 시계의 분리를 고정한다).
        return CheckOverlayCharacterView(
            elapsedSeconds: showing ? store.overlayTodayDuration : 0,
            isActive: store.snapshot.isWorking,
            showsTimer: showing,
            engine: engine
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
