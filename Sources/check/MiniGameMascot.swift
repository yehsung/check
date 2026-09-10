import AppKit
import Metal
import os
import SceneKit

/// 플래피 캐릭터의 **옆모습 스프라이트 한 장**.
///
/// 오버레이가 쓰는 바로 그 3D 모델(`aing.scn` 우선 · `aing.usdz` 폴백)을, 오버레이가 드래그 방향을 볼 때
/// 쓰는 바로 그 각도(`ReactionEngine.dragFacingAngle`)로 돌려 오프스크린에서 **한 번** 굽고, 그 NSImage 를
/// 캐시해 게임 스프라이트 자리에 끼운다.
///
/// **왜 3D 여야 하는가.** 게임이 쓰던 `aing-neutral.png` 는 눈·입·볼터치가 몸통 중심에 대해 완전히 대칭인
/// 정면 얼굴이다. 좌우 반전도 회전도 "오른쪽을 본다"를 만들지 못한다. v0.2.48 은 그늘·반사광·목도리로
/// 방향'감'만 만들었고 사용자 판정은 "얼굴이 오른쪽을 봐야 한다"였다(2026-09-10). 얼굴을 진짜로 돌릴 수
/// 있는 출처는 3D 모델 하나뿐이고, 사용자가 기준으로 든 그림(드래그하면 돌아보는 오버레이 캐릭터)이
/// 정확히 그 출처다 — 같은 모델 · 같은 각도 · 같은 unlit 재질이라 두 화면의 캐릭터가 어긋나지 않는다.
///
/// **60Hz 예산.** 굽기는 프로세스 수명 동안 (크기 × 표정)당 한 번이다. 프레임마다 도는 것은 아무것도 없다.
///
/// **언제 굽는가 — 게임 캔버스가 처음 그려질 때다.** 미리 굽는 문(prewarm)을 따로 두지 않았다: 캔버스의
/// 첫 body 평가가 곧 첫 굽기라 창을 열기 전에 부를 자리가 사실상 없고, 앱 시작에서 굽는 것은 금물이다
/// (미니게임을 한 번도 열지 않는 실행이 대부분이다). 비용은 실측 — 프로세스에서 SceneKit·Metal 을 처음
/// 건드리는 경우 61~64ms, 그 뒤(바탕화면 오버레이 캐릭터가 이미 떠 있는 보통의 경우 포함) 13~15ms.
/// 즉 최악이 창 여는 순간의 한 프레임 정도이고, 그 다음부터는 캐시된 그림 한 장이다.
/// **헤드리스 안전.** Metal 디바이스·모델·알파 어느 하나라도 없으면 `nil` 을 돌려주고 호출부는 기존 PNG 로
/// 조용히 내려간다. 실패도 캐시한다(매 프레임 재시도하면 그게 곧 예산 초과다).
@MainActor
enum MiniGameMascot {
    /// 옆모습 y회전각. **오버레이와 같은 상수를 그대로 읽는다** — 여기에 숫자를 다시 적으면 언젠가
    /// 오버레이 캐릭터와 게임 캐릭터가 다른 각도로 돌아본다.
    static var facingAngle: CGFloat { ReactionEngine.dragFacingAngle }

    /// 구운 그림 안에서 캐릭터 실루엣이 차지해야 하는 비율(긴 변 기준).
    ///
    /// 0.85 는 `aing-neutral.png` 실측값이다(192² 안에서 알파 폭 0.854 · 높이 0.802). **이 값이 계약이다** —
    /// 스프라이트는 34pt 로 그려지는데 히트박스는 24pt 다. 구운 그림에서 캐릭터가 PNG 보다 크거나 작으면
    /// 그리는 몸과 죽는 몸의 어긋남이 바뀌어, 그림만 바꿨는데 "닿았는데 안 죽었다"는 체감이 달라진다.
    static let targetFill: CGFloat = 0.85

    /// 자동 프레이밍 수렴 횟수와 프로브 해상도. 프로브는 알파 경계만 재므로 96px 로 충분하고, 세 번이면
    /// 남는 오차가 **프로브 격자 크기**(96px 에서 1px ≈ 1%)까지 내려간다 — 실측: 목표 0.85 대비 채움 0.859,
    /// 중심 0.5026. PNG 원본이 0.854×0.802 이니 그 안이다. 이 루프가 있는 이유는 모델이 바뀌거나 회전각이
    /// 바뀌어도 손으로 잰 상수를 다시 잴 필요가 없게 하려는 것이다.
    private static let framingPasses = 3
    private static let probePixels: CGFloat = 96

    /// 구운 그림의 한 변(px). **`aing-neutral.png` 와 같은 192** 다 — 같은 해상도로 맞춰야 두 경로
    /// (3D 옆모습 · PNG 폴백)가 같은 `.interpolation(.high)` 축소를 거쳐 같은 또렷함으로 그려진다.
    /// 게임에서 스프라이트는 34pt(캔버스 배율 포함 ≈40pt · 레티나 80px)로 줄여 그린다.
    static let spritePixels: CGFloat = 192

    private static let logger = Logger(subsystem: "kingcheck", category: "minigame.mascot")

    private struct Key: Hashable {
        let pixels: CGFloat
        let mood: CheckMascotAssets.Mood
    }

    /// 값이 `nil` 인 항목 = "구워 봤고 실패했다". 다시 시도하지 않는다.
    private static var cache: [Key: NSImage?] = [:]

    /// 마지막 굽기에 걸린 시간(ms)과 출처. 진단·테스트가 읽는다.
    private(set) static var lastBakeMilliseconds: Double?
    private(set) static var lastBakeSource: CheckCharacter3DScene.ModelSource?

    /// 오른쪽을 보는 옆모습 한 장. 못 구우면 nil(호출부는 PNG 로 내려간다).
    ///
    /// `.negative`(게임오버 시무룩)는 **일부러 nil 이다.** 3D 에셋에는 표정이 하나뿐이라, 옆모습 시무룩을
    /// 만들려면 없는 표정을 지어내야 한다. 죽은 뒤에는 기존 정면 시무룩 PNG 로 돌아가는 편이 낫다 —
    /// 그 순간은 어차피 90° 회전 낙하 + 붉은 플래시라 자세가 바뀌는 것이 튀지 않는다(facing-over 스냅샷).
    static func sideProfile(pixels: CGFloat = spritePixels,
                            mood: CheckMascotAssets.Mood = .neutral) -> NSImage? {
        guard mood == .neutral else { return nil }
        let key = Key(pixels: pixels, mood: mood)
        if let cached = cache[key] { return cached }
        let baked = bake(pixels: pixels, order: CheckCharacter3DScene.ModelSource.allCases)
        cache[key] = baked
        return baked
    }

    /// 테스트 전용: 캐시를 비운다(굽기 비용·폴백 경로를 반복 측정하려면 필요하다).
    static func resetCacheForTesting() {
        cache.removeAll()
        lastBakeMilliseconds = nil
        lastBakeSource = nil
    }

    // MARK: - 굽기

    /// 테스트 전용: 캐시를 건너뛰고 **지정한 출처만으로** 굽는다. 프리베이크 `.scn` 이 없는 머신이
    /// 타게 되는 usdz 폴백을 실제로 태워 보기 위한 문이다(그 경로가 그림·비용에서 어떻게 다른지).
    static func bakeForTesting(order: [CheckCharacter3DScene.ModelSource]) -> NSImage? {
        bake(pixels: spritePixels, order: order)
    }

    private static func bake(pixels requested: CGFloat, order: [CheckCharacter3DScene.ModelSource]) -> NSImage? {
        let started = CFAbsoluteTimeGetCurrent()
        // Metal 이 없는 환경(헤드리스 테스트 러너·일부 원격 세션)에서는 SCNRenderer 를 만들 수 없다.
        // 여기서 조용히 물러나는 것이 이 타입의 안전장치 전부다.
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.notice("side profile skipped: no metal device")
            return nil
        }
        guard let loaded = CheckCharacter3DScene.loadModelScene(order: order) else {
            logger.notice("side profile skipped: no model")
            return nil
        }
        let scene = loaded.scene
        scene.background.contents = nil
        // 오버레이와 **같은 함수**로 unlit 을 건다. 기본 PBR/조명에서는 텍스처가 허옇게 떠 마스코트 보라가
        // 사라지므로 이 한 줄이 색의 전부다. 여기서만 쓰는 가벼운 판(조명 모델만 바꾸고 텍스처 정규화는
        // 건너뛰기)을 따로 두면 굽기가 ~2.7ms 빨라지지만(실측), 두 화면의 캐릭터가 다른 경로로 색을 얻게
        // 되고 usdz 폴백에서 2048² 텍스처가 그대로 디코드된다. 한 번 드는 2.7ms 로 살 값이 아니다.
        CheckCharacter3DScene.applyUnlitMaterials(to: scene.rootNode)
        guard let character = scene.rootNode.childNodes.first else { return nil }

        // 오버레이와 같은 구조(wrapper → facing → character)를 세워 facing 만 돌린다. 프레이밍 보정은
        // wrapper 에 걸어(scale·position) 회전이 자기 축을 벗어나지 않게 한다.
        let wrapper = SCNNode()
        let facing = SCNNode()
        character.removeFromParentNode()
        facing.addChildNode(character)
        wrapper.addChildNode(facing)
        scene.rootNode.addChildNode(wrapper)
        facing.eulerAngles = SCNVector3(0, facingAngle, 0)

        addFramingCamera(to: scene, framing: wrapper)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false

        guard fitCharacterIntoFrame(renderer: renderer, wrapper: wrapper) else {
            logger.notice("side profile skipped: empty probe render")
            return nil
        }

        let side = max(32, requested.rounded())
        let snapshot = renderer.snapshot(atTime: 0,
                                         with: CGSize(width: side, height: side),
                                         antialiasingMode: .multisampling4X)
        guard let cg = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              alphaBox(cg) != nil else { return nil }
        lastBakeMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        lastBakeSource = loaded.source
        logger.notice(
            "side profile baked source=\(loaded.source.rawValue, privacy: .public) ms=\(lastBakeMilliseconds ?? 0, format: .fixed(precision: 1), privacy: .public)"
        )
        // PNG 폴백과 같은 규약: 픽셀 수 = 포인트 수. SwiftUI 가 34pt 프레임으로 줄일 때 두 경로가 똑같이
        // 고품질 축소를 거친다(한쪽만 포인트 크기를 줄여 두면 그 경로만 미리 뭉개진 채 들어간다).
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    /// 오버레이와 **같은 구도**의 카메라(살짝 내려다봄)를 씬에 얹는다.
    ///
    /// 숫자(fov 40 · 카메라를 0.55×extent 올림 · 시선을 0.16×extent 내림 · 거리 여유 1.4배)는
    /// `CheckCharacter3DScene.addFramingCamera` 와 같은 구도다. 그 함수는 private 이라 부를 수 없고,
    /// 부를 수 있더라도 씬 루트 기준이라 카메라 노드까지 바운딩에 섞여 프레이밍이 망가진다 —
    /// 그래서 여기서는 **캐릭터 wrapper 의 바운딩박스만** 보고 잡는다.
    private static func addFramingCamera(to scene: SCNScene, framing wrapper: SCNNode) {
        let (minB, maxB) = wrapper.boundingBox
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        let extent = CGFloat(max(maxB.x - minB.x, maxB.y - minB.y))
        let fov = CheckCharacter3DScene.fieldOfView
        let distance = extent / (2 * tan(fov / 2 * .pi / 180)) * 1.4

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = fov
        // 정사각 렌더에서 자동 판정에 맡기면 macOS 버전에 따라 가로/세로 기준이 갈릴 수 있다 — 못 박는다.
        camera.projectionDirection = .vertical
        camera.zNear = 0.01
        camera.zFar = 1_000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(center.x, center.y + extent * 0.55, CGFloat(maxB.z) + distance)
        cameraNode.look(at: SCNVector3(center.x, center.y - extent * 0.16, center.z))
        scene.rootNode.addChildNode(cameraNode)
    }

    /// 저해상도 프로브를 몇 번 돌려 캐릭터가 프레임 한가운데에서 `targetFill` 만큼 차지하도록
    /// wrapper 의 배율·위치를 수렴시킨다. 캐릭터가 한 픽셀도 안 그려지면 false(호출부는 PNG 로 내려간다).
    ///
    /// **왜 손으로 잰 상수를 안 쓰나.** 40° 로 돌린 실루엣의 폭·중심은 정면과 다르고, 각도나 모델을 손대면
    /// 또 달라진다. 손으로 잰 값을 박아 두면 다음 사람이 각도만 바꿔도 캐릭터가 프레임 밖으로 나가거나
    /// 작아지는데, 그건 스냅샷을 다시 찍기 전에는 안 보인다. 프로브는 굽는 순간 딱 세 번이다.
    private static func fitCharacterIntoFrame(renderer: SCNRenderer, wrapper: SCNNode) -> Bool {
        let (minB, maxB) = wrapper.boundingBox
        let modelWidth = CGFloat(maxB.x - minB.x), modelHeight = CGFloat(maxB.y - minB.y)
        guard modelWidth > 0, modelHeight > 0 else { return false }
        var scale: CGFloat = 1
        var offset = CGPoint.zero
        var converged = false

        for _ in 0..<framingPasses {
            wrapper.scale = SCNVector3(scale, scale, scale)
            wrapper.position = SCNVector3(offset.x, offset.y, 0)
            let probe = renderer.snapshot(atTime: 0,
                                          with: CGSize(width: probePixels, height: probePixels),
                                          antialiasingMode: .none)
            guard let cg = probe.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let box = alphaBox(cg) else { return converged }
            converged = true
            // 화면에서 캐릭터가 차지한 비율 → 월드 단위 환산 계수(폭·높이 각각).
            let worldPerFrameX = modelWidth * scale / box.width
            let worldPerFrameY = modelHeight * scale / box.height
            offset.x -= (box.midX - 0.5) * worldPerFrameX
            offset.y -= (box.midY - 0.5) * worldPerFrameY
            let correction = targetFill / max(box.width, box.height)
            scale = min(max(scale * correction, 0.02), 50)
        }
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.position = SCNVector3(offset.x, offset.y, 0)
        return converged
    }

    /// 알파가 있는 픽셀의 경계 상자를 **정규화 좌표**로 돌려준다. 완전히 비었으면 nil.
    ///
    /// 원점은 **좌하단**이다 — 월드 +Y(위)와 같은 방향이라 프레이밍 보정이 부호를 뒤집지 않아도 된다.
    /// (비트맵 메모리는 첫 행이 그림의 **위**쪽이므로 여기서 한 번 뒤집어 둔다. 이 뒤집기를 빠뜨리면
    /// 중심 보정이 반대로 걸려 캐릭터가 프레임 밖으로 밀려난다.)
    nonisolated static func alphaBox(_ cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = ctx.data else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let rowBytes = ctx.bytesPerRow
        var minX = w, maxX = -1, minRow = h, maxRow = -1
        for row in 0..<h {
            let offset = row * rowBytes
            for x in 0..<w where bytes[offset + x * 4 + 3] > 24 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
            }
        }
        guard maxX >= minX, maxRow >= minRow else { return nil }
        // 메모리 행 → 아래에서 잰 y 로 뒤집는다.
        let bottomFromBottom = h - 1 - maxRow
        return CGRect(x: CGFloat(minX) / CGFloat(w),
                      y: CGFloat(bottomFromBottom) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w),
                      height: CGFloat(maxRow - minRow + 1) / CGFloat(h))
    }
}
