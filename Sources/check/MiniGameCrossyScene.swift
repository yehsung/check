import SceneKit
import CheckCore

// MARK: - 길건너 아잉이 — 맥의 아잉이 모델 다리 (폰 1.0.15 D1 · D2)
//
// 판(씬 · 노드 풀 · 모양 · 색)은 **코어로 옮겼다**: `Sources/CheckCore/CrossyScene.swift`. 맥과 폰이 그 한 벌을
// 같이 쓴다(복사가 아니라 옮김 — 두 벌이 되면 폰이 같은 판을 다르게 본다). 이 파일에 남은 것은 하나다:
// **아잉이 모델을 어디서 어떻게 읽는가.**
//
// 왜 코어로 안 끌어왔나: 읽는 타입(`CheckCharacter3DScene`)이 모델 출처 둘(프리베이크 `aing.scn` · usdz 폴백)과
// 재질 unlit 정규화, 그리고 캐릭터 변종(황금 · 케이크 · 스프라이트)을 전부 아는 **맥 전용** 타입이다. 코어는
// "노드 하나를 주는 함수"(`CrossyAingLoader`)까지만 알면 되고, 그 경계가 맥·폰이 갈리는 **유일한** 자리다.
//
// ⚠️ 그림(뷰 다리)은 `MiniGameCrossy.swift` 에 있다 — `CrossySceneView`(NSViewRepresentable) · `CrossySCNView` · `CrossyHUD`.

/// 맥이 `CrossyScene` 에 끼우는 아잉이 모델 다리.
@MainActor
enum CrossyMacAing {
    /// 오버레이와 **같은 경로**로 읽는다(프리베이크 `aing.scn` 우선 · usdz 폴백) + 오버레이와 **같은 함수**로 unlit 을
    /// 건다(`MiniGameMascot.bake` 와 같은 근거 — 색의 전부다). 못 읽으면 nil 이고 코어가 보라 공으로 대신한다.
    ///
    /// 돌려주는 것은 **읽은 씬의 루트 노드**다. 원점 옮기기 · 키 맞추기 · 그림자 끄기는 코어(`CrossyScene.loadAing`)가
    /// 한 벌로 한다 — 맥과 폰이 같은 비율로 서야 하므로 그 계산을 여기로 가져오지 마라.
    static func load() -> SCNNode? {
        guard let loaded = CheckCharacter3DScene.loadModelScene(order: CheckCharacter3DScene.ModelSource.allCases) else {
            return nil
        }
        CheckCharacter3DScene.applyUnlitMaterials(to: loaded.scene.rootNode)
        return loaded.scene.rootNode
    }
}

extension CrossyScene {
    /// 맥 판 하나. **맥에서는 언제나 이것으로 만든다** — 앱(`CrossyGameView`)과 시험(오프스크린 `SCNRenderer`)이
    /// **같은 로더**를 지나야 시험이 앱을 증명한다(갈라지면 증거 PNG 가 앱이 아닌 것을 찍는다).
    ///
    /// 코어의 `init(aingLoader:)` 는 **기본값이 없다** — 로더를 빠뜨리면 컴파일이 막는다(폰 1.0.15 D2 수정).
    @MainActor
    static func mac() -> CrossyScene { CrossyScene(aingLoader: CrossyMacAing.load) }
}
