import CoreGraphics
import Foundation
import SceneKit
import os

/// 2D 스프라이트 캐릭터 노드 — 아틀라스 텍스처를 입힌 평면 한 장.
///
/// 이 타입은 **평면만** 만든다. wrapper(리액션)·facing(방향)·카메라는 호출부가 지금 아잉에게 하는 그대로 붙인다
/// (`root → check.reactionWrapper → check.facingWrapper → 캐릭터`). 그래야 리액션 11종·클릭 통과·프레이밍이
/// 캐릭터 종류와 무관하게 **같은 코드**를 지난다(SCNAction 은 wrapper 에 걸리므로 자식이 메시든 평면이든 모른다 — 실측).
@MainActor
enum SpriteCharacterNode {
    /// 평면의 최장변 길이. **`aing.scn` bbox 실측값(x 폭 1.9210)이다. 바꾸지 마라.**
    ///
    /// 왜 이 숫자가 중요한가: `addFramingCamera` 는 씬 루트 bbox 에서, `ReactionEngine.attach` 의 `modelExtent` 는
    /// wrapper bbox 에서 각각 `max(dx,dy)` 를 **자동으로** 뽑는다. 즉 평면 크기 하나로 카메라 구도와 리액션 진폭이
    /// 동시에 따라온다. 아잉과 같은 값을 쓰면 두 곳 다 종전 그대로가 된다.
    nonisolated static let targetExtent: CGFloat = 1.9210

    /// 노드 이름. 나중에 씬에서 스프라이트 평면을 다시 찾기 위한 열쇠(프레임 교체·미러가 이 노드에 걸린다).
    static let nodeName = "check.spriteCharacter"

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 매니페스트 + 아틀라스 이미지로 캐릭터 노드 하나를 만든다. 스프라이트가 아니거나 에셋이 매니페스트와
    /// 어긋나면 nil(호출부는 아잉으로 접는다).
    static func make(manifest: CharacterManifest, atlas: CGImage) -> SCNNode? {
        guard manifest.kind == .sprite, let spec = manifest.atlas else { return nil }
        // 매니페스트가 말하는 아틀라스 크기와 실제 PNG 가 다르면 모든 프레임이 어긋난 채로 조용히 돈다.
        // 그 상태로 세우느니 아잉으로 접는 게 낫다(알파 마스크도 같은 이유로 nil 을 돌려준다).
        guard spec.width == atlas.width, spec.height == atlas.height else {
            logger.error("sprite atlas size mismatch id=\(manifest.id, privacy: .public) manifest=\(spec.width)x\(spec.height) image=\(atlas.width)x\(atlas.height)")
            return nil
        }
        guard let front = spec.states[CharacterManifest.StateKey.frontIdle],
              let first = front.frames.first else { return nil }

        // ★ 평면 크기는 **frontIdle 첫 프레임으로 한 번만** 정한다. 프레임마다 리사이즈하면 걷는 동안 캐릭터가
        //   커졌다 작아진다(픽스처 실측: 4족 passing 프레임이 18.7% 주저앉았다). 프레임 전환은 텍스처 좌표만 바꾼다.
        let size = planeSize(for: first)
        let plane = SCNPlane(width: size.width, height: size.height)

        let material = SCNMaterial()
        material.lightingModel = .constant       // 앱이 광원을 안 쓴다(아잉과 같은 unlit 규약).
        material.diffuse.contents = atlas
        material.isDoubleSided = true            // y 스핀(commuteStart·살랑) 중 뒷면이 보인다 — 카드 뒤집기처럼.
        material.transparencyMode = .aOne
        material.diffuse.wrapS = .clamp          // 셀 경계 밖을 물지 않게(이웃 프레임이 새어 들어오는 것을 막는다).
        material.diffuse.wrapT = .clamp
        // 픽셀아트는 **반드시** .nearest 다. .linear 로 두면 SceneKit 이 격자를 뭉개 픽셀아트의 유일한
        // 특징을 지운다(오버레이는 스프라이트를 확대해 그린다 — 192px 원본이 280×340 패널에 선다).
        let filter: SCNFilterMode = (manifest.pixelArt == true) ? .nearest : .linear
        material.diffuse.magnificationFilter = filter
        material.diffuse.minificationFilter = filter
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = nodeName
        apply(frame: first, mirrored: false, to: node,
              atlasSize: CGSize(width: spec.width, height: spec.height))
        return node
    }

    /// 프레임·미러를 적용한다. **평면 크기는 절대 건드리지 않는다**(위 주석 참조) — 바뀌는 건 텍스처 좌표뿐이다.
    static func apply(frame: CharacterManifest.Rect, mirrored: Bool, to node: SCNNode, atlasSize: CGSize) {
        guard let material = node.geometry?.firstMaterial else { return }
        material.diffuse.contentsTransform = contentsTransform(
            frame: frame, mirrored: mirrored, atlasSize: atlasSize
        )
    }

    /// 프레임 종횡비를 지키면서 최장변을 `targetExtent` 로 맞춘 평면 크기.
    nonisolated static func planeSize(for frame: CharacterManifest.Rect) -> CGSize {
        let w = CGFloat(frame.w)
        let h = CGFloat(frame.h)
        guard w > 0, h > 0 else { return CGSize(width: targetExtent, height: targetExtent) }
        if w >= h {
            return CGSize(width: targetExtent, height: targetExtent * h / w)
        }
        return CGSize(width: targetExtent * w / h, height: targetExtent)
    }

    /// 셀 하나를 평면 전체에 앉히는 텍스처 변환. 미러는 **x 스케일 부호**로 같은 행렬에 접는다(왼쪽 걷기 = 추가 에셋 0).
    ///
    /// 행렬을 `SCNMatrix4MakeScale`/`Translate` 조합이 아니라 성분으로 직접 쓴다: SceneKit 은 행벡터 규약
    /// (uv' = uv × M)이라 이동이 m41/m42 에 들어간다. 조합 함수는 곱하는 순서(이동이 스케일 앞이냐 뒤냐)에 따라
    /// 의미가 뒤집혀 "왜 셀이 하나씩 밀렸지" 를 만드는 자리라, 식을 눈에 보이게 둔다.
    ///
    /// 정방향: `u' = u·(w/W) + x/W`, `v' = v·(h/H) + y/H` — **v 를 뒤집지 않는다**(rect 도 UV 도 위→아래).
    /// 미러:   `u' = (1-u)·(w/W) + x/W = -u·(w/W) + (x+w)/W`.
    nonisolated static func contentsTransform(
        frame: CharacterManifest.Rect, mirrored: Bool, atlasSize: CGSize
    ) -> SCNMatrix4 {
        guard atlasSize.width > 0, atlasSize.height > 0, frame.w > 0, frame.h > 0 else {
            return SCNMatrix4Identity
        }
        let scaleX = CGFloat(frame.w) / atlasSize.width
        let scaleY = CGFloat(frame.h) / atlasSize.height
        let offsetX = mirrored
            ? CGFloat(frame.x + frame.w) / atlasSize.width
            : CGFloat(frame.x) / atlasSize.width
        let offsetY = CGFloat(frame.y) / atlasSize.height

        var transform = SCNMatrix4Identity
        transform.m11 = mirrored ? -scaleX : scaleX
        transform.m22 = scaleY
        transform.m41 = offsetX
        transform.m42 = offsetY
        return transform
    }

    /// 평면 UV(hitTest 의 `textureCoordinates(withMappingChannel: 0)`) → 아틀라스 전체 UV.
    ///
    /// `contentsTransform` 과 **같은 식이어야 한다**. hitTest 는 재질 변환이 적용되기 **전**의 지오메트리 UV 를 준다
    /// (실측: scratchpad/v0315-core/hituvprobe — 0.5 스케일 변환을 걸어도 uv 가 0.172/0.828 로 그대로였다). 그래서
    /// 알파 마스크(`SpriteAlphaMask.isOpaque`)로 넘기기 전에 여기서 현재 프레임·미러를 다시 먹인다. 두 식이 갈리면
    /// 클릭 판정이 **다른 프레임의 알파**를 본다(걷는 동안만 클릭이 빗나가는, 재현하기 지독한 결함).
    nonisolated static func atlasUV(
        planeUV: CGPoint, frame: CharacterManifest.Rect, mirrored: Bool, atlasSize: CGSize
    ) -> CGPoint {
        guard atlasSize.width > 0, atlasSize.height > 0, frame.w > 0, frame.h > 0 else { return planeUV }
        let u = mirrored ? (1 - planeUV.x) : planeUV.x
        return CGPoint(
            x: (u * CGFloat(frame.w) + CGFloat(frame.x)) / atlasSize.width,
            y: (planeUV.y * CGFloat(frame.h) + CGFloat(frame.y)) / atlasSize.height
        )
    }
}
