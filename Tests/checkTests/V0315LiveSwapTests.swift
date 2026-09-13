import AppKit
import SceneKit
import Testing
@testable import check

/// 설정에서 캐릭터를 바꿨을 때 **실행 중인 오버레이가 그 자리에서** 갈아 끼워지는가.
///
/// 이 배선이 없으면 선택은 저장되는데 화면은 앱을 다시 켤 때까지 옛 캐릭터로 남는다 —
/// 갈래별로 나눠 지으면 아무도 소유하지 않는 자리라, 실제로 마지막까지 비어 있었다.
@MainActor
@Suite("v0.3.15 실행 중 캐릭터 교체")
struct V0315LiveSwapTests {

    /// 진짜 SCNView + 진짜 씬 + attach 된 엔진. 교체는 노드 조작이라 화면이 필요 없다.
    private func mount(character: CharacterManifest) -> (CheckCharacter3DView, SCNView, ReactionEngine,
                                                         CheckCharacter3DView.Coordinator)? {
        let engine = ReactionEngine()
        let view = CheckCharacter3DView(isActive: true, engine: engine, characterRevision: 0)
        let scnView = SCNView()
        guard let scene = CheckCharacter3DScene.makeScene(
            animated: false, character: character,
            atlas: CheckCharacter3DScene.atlasImage(for: character)
        ) else { return nil }
        scnView.scene = scene
        guard let wrapper = scene.rootNode.childNode(
            withName: CheckCharacter3DScene.reactionWrapperName, recursively: false) else { return nil }
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: scnView)
        let coordinator = CheckCharacter3DView.Coordinator()
        coordinator.appliedCharacterRevision = 0
        return (view, scnView, engine, coordinator)
    }

    /// 씬에 지금 서 있는 캐릭터가 스프라이트인가(= `check.spriteCharacter` 노드가 있는가).
    private func isSprite(_ scnView: SCNView) -> Bool {
        guard let root = scnView.scene?.rootNode else { return false }
        return root.childNode(withName: SpriteCharacterNode.nodeName, recursively: true) != nil
    }

    private func defaults(_ id: String) -> (UserDefaults, String) {
        let suite = "v0315-liveswap-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.set(id, forKey: CharacterSelection.defaultsKey)
        return (store, suite)
    }

    @Test("선택이 바뀌면 실행 중인 씬이 그 자리에서 갈아 끼워진다")
    func revisionChangeSwapsTheLiveScene() throws {
        let catalog = CheckCharacter3DScene.catalog
        try #require(catalog.manifest(id: "fox") != nil, "번들에 여우가 없다 — 에셋 갈래가 빠졌다")
        var (view, scnView, _, coordinator) = try #require(mount(character: CharacterCatalog.builtInAing))
        #expect(isSprite(scnView) == false, "아잉으로 떠야 한다")

        let (store, suite) = defaults("fox")
        defer { store.removePersistentDomain(forName: suite) }
        view.characterDefaults = store
        view.characterRevision = 1           // 설정에서 골랐다 = 세대가 올랐다
        view.applyCharacterChangeIfNeeded(scnView, coordinator: coordinator)

        #expect(isSprite(scnView), "세대가 올랐는데 씬이 안 갈렸다 — 앱을 다시 켤 때까지 옛 캐릭터로 남는다")
        #expect(coordinator.appliedCharacterRevision == 1)
    }

    @Test("세대가 그대로면 아무것도 하지 않는다")
    func sameRevisionIsANoOp() throws {
        var (view, scnView, _, coordinator) = try #require(mount(character: CharacterCatalog.builtInAing))
        let (store, suite) = defaults("fox")
        defer { store.removePersistentDomain(forName: suite) }
        view.characterDefaults = store
        view.characterRevision = 0           // 안 바뀌었다
        view.applyCharacterChangeIfNeeded(scnView, coordinator: coordinator)
        #expect(isSprite(scnView) == false, "세대가 같은데 갈아 끼웠다 — 매 프레임 모델을 다시 세운다")
    }

    @Test("★ 격발 중에는 갈지 않고, 끝난 뒤에 반영한다")
    func ultraDefersTheSwap() throws {
        var (view, scnView, engine, coordinator) = try #require(mount(character: CharacterCatalog.builtInAing))
        let (store, suite) = defaults("fox")
        defer { store.removePersistentDomain(forName: suite) }
        view.characterDefaults = store
        view.characterRevision = 1

        // 격발 중 = 화면에 선 것이 **찌른 사람의 캐릭터**다. 여기서 갈아 끼우면 원복이 내 선택을 덮는다.
        engine.isUltraActive = true
        view.applyCharacterChangeIfNeeded(scnView, coordinator: coordinator)
        #expect(isSprite(scnView) == false, "격발 중에 갈아 끼웠다 — 원복이 이 선택을 덮어쓴다")
        #expect(coordinator.appliedCharacterRevision == 0, "세대를 올려 버리면 격발이 끝나도 영영 반영되지 않는다")

        // 격발이 끝나면 다음 갱신에서 반영된다.
        engine.isUltraActive = false
        view.applyCharacterChangeIfNeeded(scnView, coordinator: coordinator)
        #expect(isSprite(scnView), "격발이 끝났는데도 안 갈렸다")
        #expect(coordinator.appliedCharacterRevision == 1)
    }
}
