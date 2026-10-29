import CheckCore
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import os

/// 길건너 아잉이의 **폰 쪽 아잉이 모델 다리**(폰 1.0.15 D2) — `CrossyScene(aingLoader:)` 에 끼운다.
///
/// 맥은 `CrossyMacAing`(`Sources/check/MiniGameCrossyScene.swift`)이 `CheckCharacter3DScene` 으로 읽는다. 그 타입은
/// 맥 전용(모델 출처 둘 · 캐릭터 변종 · 얼굴 재질 찾기)이라 폰이 쓸 수 없고, 코어는 "노드 하나를 주는 함수"까지만 안다.
///
/// ── 왜 `#if os(iOS)` 가 없나 ───────────────────────────────────────────────────────────────
/// 이 파일에는 화면이 없다(SceneKit · CoreGraphics 뿐). 게이트를 걸지 않으면 macOS `swift test` 가 **번들에서
/// `Art/aing.scn` 이 실제로 풀리는지**까지 잰다(`GamesCrossyAingModelTests`) — 폰 뷰는 macOS 스위트가 컴파일조차
/// 안 하므로, 게이트를 걸면 모델 누락이 **출시까지 조용하다**(아잉이 대신 보라 공이 뛴다).
///
/// ── 모델 파일 ─────────────────────────────────────────────────────────────────────────────
/// `Sources/CheckMobileKit/Resources/Art/aing.scn`(4.74MB) — 맥 `Sources/check/Resources/aing.scn` 의 **사본**이다
/// (`Package.swift` 의 `.copy("Resources/Art")` 가 폴더째 번들에 넣으므로 패키지 선언은 안 고쳤다). git 은 내용이 같은
/// blob 을 공유하므로 저장소는 커지지 않는다. 코어 리소스로 올리지 **마라** — 그러면 맥 앱에 같은 파일이 두 벌 실린다.
///
/// ⚠️ 나중의 크기 최적화(네 방향 구운 PNG + unlit 평면 ≈80KB)는 **이번 판이 아니다** — 맥에서 렌더를 돌려 각도를
/// 사람이 봐야 한다(설계서 D2 의 각주).
/// `@MainActor` 인 까닭은 하나다 — `CrossyAingLoader` 가 `@MainActor () -> SCNNode?` 이고(씬이 메인 액터에 산다),
/// 그 다리에 끼울 함수가 같은 격리여야 한다. 밖에서 부르는 자리도 전부 화면·시험(메인)이다.
@MainActor
package enum GamesCrossyAing {
    /// 번들 안 모델 자리. **시험과 로더가 같은 상수를 지난다** — 갈리면 시험만 맞고 앱은 보라 공이 된다.
    package static let resourceName = "aing"
    package static let resourceExtension = "scn"
    package static let resourceSubdirectory = "Art"

    private static let logger = Logger(subsystem: "aingcheck", category: "minigame")

    /// 번들 안 모델 URL. 없으면 nil.
    package static func modelURL() -> URL? {
        Bundle.module.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: resourceSubdirectory)
    }

    /// `CrossyScene` 에 끼우는 다리. 읽은 씬의 **루트 노드**를 unlit 까지 걸어서 돌려준다 — 원점 옮기기 · 키 맞추기는
    /// 코어(`CrossyScene.loadAing`)가 맥과 같은 한 벌로 한다.
    ///
    /// 실패하면 nil 이고 코어가 보라 공으로 접는다. **그 접힘은 눈에 보여야 한다** — 번들에서 파일이 빠졌거나(커밋 누락 ·
    /// `.copy` 가 안 남김) 아카이브를 못 풀면 화면에는 아무 표시가 없고 판은 그대로 돌기 때문이다. 그래서 자리마다 로그를
    /// 남긴다(맥 `SpriteCharacterNode` 가 아틀라스 크기 불일치에 하는 것과 같은 결).
    package static func load() -> SCNNode? {
        guard let url = modelURL() else {
            logger.error("crossy aing model missing from bundle name=\(resourceName, privacy: .public).\(resourceExtension, privacy: .public)")
            return nil
        }
        guard let scene = try? SCNScene(url: url, options: nil) else {
            logger.error("crossy aing model unreadable name=\(resourceName, privacy: .public).\(resourceExtension, privacy: .public)")
            return nil
        }
        guard hasGeometry(scene.rootNode) else {
            logger.error("crossy aing model has no geometry — fell back to the placeholder")
            return nil
        }
        applyUnlitMaterials(to: scene.rootNode)
        return scene.rootNode
    }

    /// 지오메트리가 하나라도 있는가(부분 로드 · 손상 아카이브를 접기 위한 최소 건전성 — 맥
    /// `CheckCharacter3DScene.hasGeometry` 와 같은 판정이다).
    package static func hasGeometry(_ root: SCNNode) -> Bool {
        var found = false
        root.enumerateHierarchy { node, stop in
            if node.geometry != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// 모든 재질을 unlit(`.constant`)로 바꾼다 — **색의 전부다**(안 걸면 판의 해·주변광을 받아 허옇게 뜬다).
    ///
    /// 맥 `CheckCharacter3DScene.applyUnlitMaterials` 와 **다른 점이 둘**이다:
    /// ① **512px 다운스케일을 하지 않는다.** 프리베이크 `aing.scn` 은 이미 512 로 구워져 있다(`scripts/prebake-character.swift`)
    ///    — 맥의 다운스케일은 usdz 폴백(2048²)을 위한 것이고 폰에는 그 폴백이 없다.
    /// ② **얼굴 재질을 찾아 주지 않는다.** 맥이 디퓨즈를 CGImage 로 정규화하는 까닭은 리액션 엔진이 "큰 CGImage 디퓨즈"로
    ///    얼굴을 찾기 때문인데, 길건너에는 깜빡임·감은눈이 없다. 다만 아카이브가 임베드 PNG 를 `Data` 로 돌려주는 경우는
    ///    **SceneKit 이 그대로 못 그릴 수 있어** CGImage 로 바꿔 준다(아래 `normalizedTexture`).
    package static func applyUnlitMaterials(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                material.lightingModel = .constant
                if let image = normalizedTexture(material.diffuse.contents) {
                    material.diffuse.contents = image
                }
            }
        }
    }

    /// 디퓨즈가 인코딩 바이트(`Data` — `.scn` 아카이브가 임베드 이미지를 이렇게 돌려준다)면 CGImage 로 바꾼다.
    /// 그 밖(이미 CGImage · 색 · 알 수 없는 타입)은 nil = **건드리지 않는다**.
    package static func normalizedTexture(_ contents: Any?) -> CGImage? {
        guard let data = contents as? Data, !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width >= 8, image.height >= 8
        else { return nil }
        return image
    }
}
