import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.54 리뷰 수정 — 검증된 결함 넷의 회귀 테스트(설계서 review-findings).
//  ① 울트라 3D↔3D 교체(아잉 ↔ 황금 아잉이) 뒤 원복된 캐릭터가 눈을 못 감았다(얼굴이 MTLTexture 라 재탐색이 못 찾았다).
//  ② 연달아 뽑으면 첫 뽑기 뒤 상점 다시 읽기가 둘째 뽑기보다 늦게 도착해 잔량·보유·조각을 되돌렸다.
//  ③ 뽑기 없는 서버에서도 캐릭터 고르기·상점 자리표시에 황금 아잉이가 서서 막다른 길로 안내했다 · 옛 서버의 unknown_character 를
//     안 되돌렸다 · 되돌림 안내가 금에게 "상점에서 살 수 있어요"라고 했다.
// (④ 팝오버 700pt 는 `V0354GachaMacRenderTests.worstCasePopoverWithGacha` 가 잰다.)

// MARK: - ① 울트라 3D↔3D 왕복 뒤의 감은 눈

@MainActor
@Suite struct V0354UltraEyeRoundTripTests {
    struct Mounted {
        let controller: CheckOverlayController
        let view: SCNView
    }

    /// 얼굴 재질(큰 CGImage 디퓨즈 · 후광 판 제외). attach 전에 잡는다 — attach 뒤에는 MTLTexture 라 CGImage 로 못 찾는다.
    static func faceMaterial(in scene: SCNScene) -> SCNMaterial? {
        var found: SCNMaterial?
        scene.rootNode.enumerateHierarchy { node, stop in
            for material in node.geometry?.materials ?? [] where material.name != GoldAingFinish.haloMaterialName {
                if let cg = SleepEyeExplore.cgImage(from: material.diffuse.contents), cg.width >= 256 {
                    found = material
                    stop.pointee = true
                    return
                }
            }
        }
        return found
    }

    /// `V0354UltraHarness.mounted` 와 같은 모양(근무 중 컨트롤러 + **Metal SCNView** 에 붙인 씬)이되 그 뷰를 함께 돌려준다.
    static func mount(receiver: CharacterManifest, function: String = #function) throws -> Mounted {
        let defaults = CheckTestScratch.defaults("v0354-eye-roundtrip-" + receiver.id, function: function)
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
                                   defaults: defaults, workspaceNotifications: nil)
        store.setOverlayEnabled(true)
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter())
        controller.updateWorking(true)
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: receiver))
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        view.scene = scene
        let wrapper = try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        controller.engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
        return Mounted(controller: controller, view: view)
    }

    static func manifest(_ id: String) -> CharacterManifest {
        CharacterCatalog.isGoldAing(id) ? CharacterCatalog.builtInGoldAing : CharacterCatalog.builtInAing
    }

    /// (받는 사람 캐릭터, 찌른 사람 캐릭터) — nil 은 캐릭터 이전 버전(= 아잉).
    nonisolated static let roundTrips: [(String, String?)] = [
        (CharacterCatalog.builtInAingID, CharacterCatalog.goldAingID),   // 아잉 → 황금 → 아잉
        (CharacterCatalog.goldAingID, CharacterCatalog.builtInAingID),   // 황금 → 아잉 → 황금
        (CharacterCatalog.goldAingID, nil)                              // 황금 → (옛 앱 = 아잉) → 황금
    ]

    /// 지금 엔진이 붙어 있는 씬의 캐릭터 얼굴 재질(후광 제외 · GPU 텍스처 또는 큰 CGImage 디퓨즈). attach 뒤라 MTLTexture 일 수 있다.
    static func attachedFace(_ engine: ReactionEngine) -> SCNMaterial? {
        guard let scene = engine.attachedScene,
              let wrapper = scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false),
              let facing = wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false),
              let character = facing.childNodes.first else { return nil }
        var found: SCNMaterial?
        character.enumerateHierarchy { node, stop in
            for material in node.geometry?.materials ?? [] where material.name != GoldAingFinish.haloMaterialName {
                let contents = material.diffuse.contents
                let isTexture = (contents as AnyObject?).map { ($0 as? any MTLTexture) != nil } ?? false
                let isFace = isTexture || (SleepEyeExplore.cgImage(from: contents).map { $0.width >= 256 } ?? false)
                if isFace {
                    found = material
                    stop.pointee = true
                    return
                }
            }
        }
        return found
    }

    /// 결과를 잰다: 깜빡임·졸기 자원이 살아 있고, 졸면 얼굴이 감은 눈 **GPU 텍스처**로 바뀌고, 깨면 뜬 눈으로 돌아온다.
    static func expectEyesWork(_ engine: ReactionEngine, face: SCNMaterial, _ label: String) {
        #expect(engine.hasFaceTextures, "\(label): 원복 뒤 GPU 얼굴 텍스처가 없다 — 깜빡이지 않고 졸면 뜬 눈 위에 감은 눈 선이 선다")
        let awake = face.diffuse.contents as AnyObject?
        #expect(awake != nil)
        #expect(engine.request(.drowsy), "\(label): 졸기를 거절했다")
        #expect(engine.state == .sleeping)
        let asleep = face.diffuse.contents as AnyObject?
        #expect(asleep !== awake, "\(label): 졸았는데 얼굴이 그대로다(뜬 눈) — 감은 눈 선만 뜬 눈 위에 그려진다")
        #expect(asleep.map { ($0 as? any MTLTexture) != nil } ?? false, "\(label): 감은 눈이 GPU 텍스처가 아니다 — 텍스처 경로가 끊겼다")
        engine.request(.wake)
        #expect((face.diffuse.contents as AnyObject?) === awake, "\(label): 깼는데 뜬 눈으로 안 돌아왔다")
    }

    /// 리뷰가 짚은 그 경로: **같은 Metal 뷰**에서 3D 캐릭터를 3D 캐릭터로 갈아입었다가(`swapCharacter`) 떼어 둔 노드를 도로 붙인다
    /// (`restoreCharacterNode`) — 울트라 격발 · 원복이 엔진에 시키는 일 그대로다.
    @Test("엔진 왕복(같은 Metal 뷰): 아잉 → 황금 → 아잉 · 황금 → 아잉 → 황금 뒤에도 원래 캐릭터가 눈을 감고 뜬다",
          arguments: [(CharacterCatalog.builtInAingID, CharacterCatalog.goldAingID),
                      (CharacterCatalog.goldAingID, CharacterCatalog.builtInAingID)])
    func engineRoundTripKeepsTheEyes(receiverID: String, otherID: String) throws {
        let engine = ReactionEngine()
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: Self.manifest(receiverID)))
        let face = try #require(Self.faceMaterial(in: scene))
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        view.scene = scene
        let wrapper = try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
        #expect(view.device != nil, "전제: Metal 디바이스가 없다 — 앱의 GPU 텍스처 경로를 못 잰다")
        #expect(engine.hasFaceTextures, "기준선: 교체 전부터 GPU 얼굴 텍스처가 없다 — 이 테스트가 재는 경로가 아니다")
        #expect(engine.currentCharacterID == receiverID)

        let stashed = try #require(engine.swapCharacter(to: Self.manifest(otherID)))
        #expect(engine.currentCharacterID == otherID, "전제: 3D→3D 교체가 안 일어났다")
        #expect(engine.hasFaceTextures, "교체해 세운 캐릭터에 GPU 얼굴 텍스처가 없다")
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == receiverID)
        #expect(Self.attachedFace(engine) === face, "원복된 것이 처음 그 노드가 아니다")
        Self.expectEyesWork(engine, face: face, "\(receiverID) → \(otherID) → \(receiverID)")

        // 두 번째 왕복도 같다(맡겨 둔 자원이 한 번 쓰고 사라지지 않는다). 깨기 연출을 걷고 시작한다(격발 원복과 같은 순서).
        engine.cancelActiveReaction()
        let again = try #require(engine.swapCharacter(to: Self.manifest(otherID)))
        #expect(engine.restoreCharacterNode(again))
        Self.expectEyesWork(engine, face: face, "두 번째 왕복")

        // 자다가 맞은 격발: 졸던 내 캐릭터가 떨어지고(감은 선 켜짐) → 새 캐릭터에서 깬다 → 원복. 돌아온 얼굴은 뜬 눈이고 감은 선은 꺼져 있다.
        engine.cancelActiveReaction()
        let awakeTexture = face.diffuse.contents as AnyObject?
        #expect(engine.request(.drowsy))
        let asleepFace = face.diffuse.contents as AnyObject?
        #expect(asleepFace != nil && asleepFace !== awakeTexture, "기준선: 졸았는데 얼굴이 그대로다")
        let sleepingNode = try #require(engine.swapCharacter(to: Self.manifest(otherID)))
        engine.request(.wake)
        engine.cancelActiveReaction()
        #expect(engine.restoreCharacterNode(sleepingNode))
        #expect((face.diffuse.contents as AnyObject?) === awakeTexture, "자다 맞은 격발 뒤 돌아온 얼굴이 뜬 눈 텍스처가 아니다")
        let lines = [CheckCharacter3DScene.closedEyeLeftName, CheckCharacter3DScene.closedEyeRightName]
            .compactMap { sleepingNode.childNode(withName: $0, recursively: true) }
        #expect(lines.count == 2 && lines.allSatisfy { $0.isHidden }, "돌아온 캐릭터의 뜬 눈 위에 감은 눈 선이 남았다")
    }

    /// 실제 격발 경로(받은 울트라 → 덮기 → 원복). 덮는 순간 오버레이 뷰가 처음 서면 엔진이 그 뷰로 옮겨 가므로, 재는 얼굴은
    /// 원복 뒤 **지금 붙어 있는** 캐릭터의 것이다.
    @Test("울트라 3D↔3D 왕복(받은 울트라 → 원복) 뒤에도 내 캐릭터가 눈을 감는다 — GPU 얼굴 텍스처가 남고, 졸면 얼굴이 바뀌고, 깨면 돌아온다",
          arguments: Self.roundTrips)
    func eyesSurviveTheUltraRoundTrip(receiverID: String, senderID: String?) throws {
        let mounted = try Self.mount(receiver: Self.manifest(receiverID))
        let engine = mounted.controller.engine
        defer { mounted.controller.updateWorking(false) }
        #expect(mounted.view.device != nil, "전제: Metal 디바이스가 없다 — 앱의 GPU 텍스처 경로를 못 잰다")
        #expect(engine.currentCharacterID == receiverID)
        #expect(engine.hasFaceTextures, "기준선: 격발 전부터 GPU 얼굴 텍스처가 없다 — 이 테스트가 재는 경로가 아니다")

        mounted.controller.handleReceivedPokes([V0354UltraHarness.ultra(from: senderID)])
        #expect(mounted.controller.isUltraActive)
        #expect(engine.currentCharacterID != receiverID, "전제: 3D→3D 교체가 안 일어났다(\(engine.currentCharacterID))")
        mounted.controller.endUltraTakeover()
        #expect(engine.currentCharacterID == receiverID, "원복이 내 캐릭터를 안 돌려놨다")
        print("[v0354-fix] 울트라 왕복 \(receiverID) ← \(senderID ?? "nil"): 원복 뒤 엔진 씬이 처음 씬인가 \(engine.attachedScene === mounted.view.scene)")
        let face = try #require(Self.attachedFace(engine), "원복된 캐릭터의 얼굴 재질을 못 찾았다")
        Self.expectEyesWork(engine, face: face, "\(receiverID) ← \(senderID ?? "nil")")
    }
}

// MARK: - ② 연달아 뽑기 — 늦은 상점 다시 읽기가 새 값을 되돌리지 않는다

@MainActor
@Suite struct V0354GachaRaceTests {
    static func host(_ label: String) -> String { "v0354-race-\(label)-\(UUID().uuidString.prefix(8))".lowercased() }

    /// 첫 뽑기(여우 · 잔량 70) 뒤의 상점 다시 읽기(n=1)를 **늦게**(2초) 준다 — 그 사이 둘째 동작이 끝난다. 그 조회가 나간 시점의 서버는
    /// 첫 뽑기 직후다(잔량 70 · 여우 보유). 그 뒤 조회(n≥2)는 둘째 동작 뒤의 사실(`later`)을 곧바로 준다.
    static func register(host: String, initialShards: Int = 3, staleShards: Int = 3, later: String,
                         secondPull: String? = nil, exchange: String? = nil) {
        let first = #"{"status":"ok","character_id":"fox","duplicate":false,"shards_gained":0,"shards":\#(staleShards),"ruby_balance":70,"price":50,"replayed":false}"#
        GomokuStubProtocol.register(host: host) { rpc, _, index in
            switch rpc {
            case "shop_state":
                switch index {
                case 0: return .init(body: V0354GachaStub.shopStateJSON(ruby: 120, shards: initialShards, owned: ["squirrel"]))
                case 1: return .init(body: V0354GachaStub.shopStateJSON(ruby: 70, shards: staleShards, owned: ["squirrel", "fox"]),
                                     delay: 2.0)
                default: return .init(body: later, delay: 0.05)
                }
            case "gacha_pull":
                return .init(body: index == 0 ? first : (secondPull ?? #"{"status":"invalid"}"#))
            case "gacha_exchange":
                return .init(body: exchange ?? #"{"status":"invalid"}"#)
            case "megaphone_info":
                return .init(body: #"{"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":10,"max_length":198}"#)
            default: return nil
            }
        }
    }

    /// 첫 뽑기를 끝내고, 그 뒤의 상점 다시 읽기가 **아직 떠 있는** 상태까지 간다.
    static func firstPull(_ store: WorkTimerStore, host: String) async {
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult?.characterID == "fox" })
        #expect(store.rubyBalance == 70)
    }

    /// 늦은 조회가 도착해 처리되고 상점 읽기가 모두 끝날 때까지.
    static func settle(_ store: WorkTimerStore, host: String) async -> Bool {
        await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") >= 2 && !store.shopLoading }
    }

    struct SecondPull: Sendable, CustomTestStringConvertible {
        let label: String
        let body: String
        let characterID: String
        let ruby: Int
        let shards: Int
        let owned: Set<String>
        var testDescription: String { label }
    }

    /// 둘째 뽑기 두 갈래: 중복(조각이 갈린다) · 새 캐릭터(보유가 갈린다). 잔량은 둘 다 20(늦은 조회는 70).
    nonisolated static let secondPulls: [SecondPull] = [
        SecondPull(label: "중복 다람쥐 → 조각 4",
                   body: #"{"status":"ok","character_id":"squirrel","duplicate":true,"shards_gained":1,"shards":4,"ruby_balance":20}"#,
                   characterID: "squirrel", ruby: 20, shards: 4, owned: ["aing", "squirrel", "fox"]),
        SecondPull(label: "새 유령 → 보유",
                   body: #"{"status":"ok","character_id":"ghost","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":20}"#,
                   characterID: "ghost", ruby: 20, shards: 3, owned: ["aing", "squirrel", "fox", "ghost"])
    ]

    @Test("[한 번 더] 연타: 첫 뽑기 뒤 늦게 온 상점 다시 읽기가 둘째 뽑기의 잔량·조각·보유를 되돌리지 않는다", arguments: Self.secondPulls)
    func lateRefetchDoesNotRollBackTheSecondPull(_ second: SecondPull) async throws {
        let host = Self.host("pull")
        Self.register(host: host,
                      later: V0354GachaStub.shopStateJSON(ruby: second.ruby, shards: second.shards,
                                                          owned: second.owned.subtracting(["aing"])),
                      secondPull: second.body)
        let store = await V0354GachaStub.loadedStore(host: host, label: "race-pull")
        await Self.firstPull(store, host: host)
        // 결과가 뜨자마자 다시 누른다 — 첫 뽑기 뒤의 상점 다시 읽기는 아직 떠 있다.
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult?.characterID == second.characterID })
        #expect(store.rubyBalance == second.ruby, "둘째 뽑기 응답을 안 옮겼다")
        #expect(store.shopLoading && GomokuStubProtocol.count(host: host, rpc: "shop_state") == 2,
                "전제: 첫 뽑기 뒤의 다시 읽기가 둘째 뽑기 전에 이미 끝났다 — 경합을 못 만들었다")

        #expect(await Self.settle(store, host: host))
        #expect(store.rubyBalance == second.ruby,
                "잔량 \(String(describing: store.rubyBalance)) — 첫 뽑기 직후 값(70)으로 되돌아갔다(서버는 \(second.ruby))")
        #expect(store.gachaShards == second.shards, "조각 \(String(describing: store.gachaShards)) — 서버는 \(second.shards)")
        #expect(store.ownedCharacterIDs == second.owned,
                "보유 \(store.ownedCharacterIDs.sorted()) — 서버는 \(second.owned.sorted())")
    }

    @Test("뽑기 직후 교환: 늦게 온 상점 다시 읽기가 방금 교환한 캐릭터·조각을 되돌리지 않는다")
    func lateRefetchDoesNotRollBackAnExchange() async throws {
        let host = Self.host("exchange")
        Self.register(host: host, initialShards: 5, staleShards: 5,
                      later: V0354GachaStub.shopStateJSON(ruby: 70, shards: 1, owned: ["squirrel", "fox", "ghost"]),
                      exchange: #"{"status":"ok","character_id":"ghost","shards":1,"cost":4,"replayed":false}"#)
        let store = await V0354GachaStub.loadedStore(host: host, label: "race-exchange")
        await Self.firstPull(store, host: host)
        store.exchangeGacha("ghost")
        #expect(await V0354CoreStub.waitUntil { store.gachaExchangingID == nil })
        #expect(store.ownedCharacterIDs.contains("ghost") && store.gachaShards == 1, "교환 응답을 안 옮겼다")
        #expect(store.shopLoading && GomokuStubProtocol.count(host: host, rpc: "shop_state") == 2,
                "전제: 첫 뽑기 뒤의 다시 읽기가 교환 전에 이미 끝났다 — 경합을 못 만들었다")

        #expect(await Self.settle(store, host: host))
        #expect(store.ownedCharacterIDs.contains("ghost"), "방금 교환한 유령이 다시 잠겼다(보유 \(store.ownedCharacterIDs.sorted()))")
        #expect(store.gachaShards == 1, "조각 \(String(describing: store.gachaShards)) — 교환 전 값(5)으로 되돌아갔다")
        #expect(store.rubyBalance == 70)
    }
}

// MARK: - ③ 뽑기 없는 서버의 황금 아잉이 — 고르기 · 상점 자리표시 · 되돌리기

@MainActor
@Suite struct V0354GoldPickerGateTests {
    static let gold = CharacterCatalog.goldAingID

    /// 서버가 주는 여섯 줄(금 없음) — 뽑기 마이그레이션 전 서버 모양.
    static var oldServerRows: [ShopCharacterRow] {
        V0354GachaMacRenderTests.shopRows().filter { !CharacterCatalog.isGoldAing($0.id) }
    }

    enum Server: String, CaseIterable {
        /// 상점을 아직 못 읽었다(로드 전엔 아무것도 안 막는다 — 다른 캐릭터와 같은 관용).
        case notLoaded
        /// 뽑기 없는 서버: gacha 키 없음 · 금 행 없음.
        case oldServer
        /// 뽑기 있는 서버.
        case gacha
        /// gacha 키는 없지만 서버가 금 행을 말한다(능력 번호로 뽑기만 닫힌 경우).
        case listedRow
        /// 뽑기 없는 서버지만 내가 금을 가졌다.
        case owned
    }

    static func store(_ server: Server, function: String = #function) -> WorkTimerStore {
        let store = V0317ShopTests.teamStore(members: 2, service: V0317ShopTests.offlineService("v0354-gold-gate-\(server.rawValue)"),
                                             function: function + server.rawValue)
        guard server != .notLoaded else { return store }
        let rows = server == .listedRow ? V0354GachaMacRenderTests.shopRows() : Self.oldServerRows
        store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: rows))
        store.shopLoaded = true
        if server == .gacha {
            store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: V0354GachaMacRenderTests.shopRows(),
                                                   gacha: V0354GachaMacRenderTests.info()))
        }
        if server == .owned { store.ownedCharacterIDs.insert(Self.gold) }
        return store
    }

    static func pickerBitmap(_ store: WorkTimerStore, label: String) throws -> NSBitmapImageRep {
        store.isCharacterPanelVisible = true
        let view = CheckMenuView(store: store, previewClipsOverflowList: true,
                                 characterDefaults: V0317ShopTests.isolatedDefaults("v0354-gold-gate-" + label))
        return try #require(V0354GachaMacRenderTests.settledBitmap(view, width: CheckMenuView.mainWindowWidth))
    }

    /// 두 그림에서 갈린 픽셀 수(채널 차 > 8 — 렌더 잡음 밖).
    static func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return Int.max }
        var count = 0
        for y in stride(from: 0, to: a.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: a.pixelsWide, by: 2) {
                guard let p = a.colorAt(x: x, y: y), let q = b.colorAt(x: x, y: y) else { continue }
                let d = max(abs(p.redComponent - q.redComponent), abs(p.greenComponent - q.greenComponent),
                            abs(p.blueComponent - q.blueComponent))
                if d * 255 > 8 { count += 1 }
            }
        }
        return count
    }

    @Test("캐릭터 고르기: 뽑기 없는 서버(gacha 키·금 행 없음)에서는 황금 아잉이 카드가 안 선다 — 뽑기가 있거나 · 가졌거나 · 서버가 금 행을 주거나 · 로드 전이면 선다")
    func pickerListsGoldOnlyWhenObtainable() throws {
        let expected: [Server: Bool] = [.notLoaded: true, .oldServer: false, .gacha: true, .listedRow: true, .owned: true]
        for server in Server.allCases {
            let ids = Self.store(server).characterPickerIDs
            #expect(ids.contains(Self.gold) == expected[server], "\(server): 고르기 목록 \(ids)")
            // 금 말고는 그대로다(번들 순서 · 아잉 먼저). 무지개(v0.3.59)는 이 픽스처의 어느 서버도 내지 않아(확률표 · 상점 목록에 없음 ·
            // 안 가짐) 같은 문에 걸려 빠진다 — 무지개 쪽 판정은 `V0359RainbowMacTests` 가 잰다.
            let plain = { (id: String) in id != Self.gold && !CharacterCatalog.isRainbowAing(id) }
            #expect(ids.filter(plain) == CheckCharacter3DScene.catalog.allIDs.filter(plain), "\(server)")
            #expect(ids.contains(CharacterCatalog.rainbowAingID) == (server == .notLoaded), "\(server): 무지개 \(ids)")
        }
        // 화면: 옛 서버의 고르기는 뽑기 서버의 고르기와 **다른 그림**이다(금 카드가 빠져 카드가 한 칸씩 당겨진다).
        // 기준선 — 같은 조건을 두 번 그리면 같다(렌더 잡음이 아니라 카드 목록이 그림을 가른다는 증거).
        let old = try Self.pickerBitmap(Self.store(.oldServer), label: "old")
        let gacha = try Self.pickerBitmap(Self.store(.gacha), label: "gacha")
        let gachaAgain = try Self.pickerBitmap(Self.store(.gacha, function: "again"), label: "gacha-again")
        let same = Self.differingPixels(gacha, gachaAgain), moved = Self.differingPixels(old, gacha)
        print("[v0354-fix] 고르기 그림 차: 뽑기 서버 두 번 \(same)px · 옛 서버 vs 뽑기 서버 \(moved)px")
        #expect(same < 50, "기준선: 같은 조건 두 그림이 \(same)px 갈린다 — 이 비교는 잡음이다")
        #expect(moved > same + 500, "옛 서버의 고르기에 금 카드가 그대로 섰다(그림 차 \(moved)px)")
    }

    @Test("상점 자리표시 격자(서버 목록이 비었을 때)도 같은 규칙 — 읽었는데 뽑기가 없으면 금 칸이 없다 · 로드 전엔 있다")
    func shopPlaceholderFollowsTheSameRule() throws {
        let loadedEmpty = V0317ShopTests.plainStore()
        loadedEmpty.applyShopState(ShopStateResponse(rubyBalance: 120, characters: []))
        loadedEmpty.shopLoaded = true
        #expect(loadedEmpty.shopCharacters.isEmpty, "전제: 서버 목록이 비어 자리표시를 그린다")
        let placeholder = loadedEmpty.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id)
        #expect(!placeholder.contains(Self.gold), "뽑기 없는 서버의 상점 자리표시에 금 칸이 섰다: \(placeholder)")
        #expect(!placeholder.isEmpty && !placeholder.contains(CharacterCatalog.builtInAingID))

        let notLoaded = V0317ShopTests.plainStore()
        #expect(notLoaded.shopGridRows(catalog: CheckCharacter3DScene.catalog).map(\.id).contains(Self.gold),
                "로드 전 자리표시는 아무것도 안 막는다(다른 캐릭터와 같은 관용)")
        // 서버 목록이 있으면 서버 목록 그대로다(금 행이 없으면 없다).
        let server = Self.store(.oldServer)
        #expect(server.shopGridRows(catalog: CheckCharacter3DScene.catalog) == server.shopCharacters)
    }

    /// set_character 응답을 스텁으로 주고 금(또는 기준선 캐릭터)을 민다.
    static func push(_ id: String, reply: String, label: String, function: String = #function) async -> (WorkTimerStore, CharacterSelection) {
        let host = "v0354-push-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
        TokenBoardURLProtocol.setResponse(reply, forHost: host)
        let store = V0317ShopTests.stubStore(host: host, function: function + label)
        store.characterDefaults.set(id, forKey: CharacterSelection.defaultsKey)
        let selection = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog)
        #expect(selection.selectedID == id, "준비 실패 — 기준선이 아잉이면 이 테스트는 공허하다")
        store.syncMessage = "시작값"
        await store.pushCharacter(id, announcesFailure: false)
        return (store, selection)
    }

    @Test("뽑기 없는 서버가 금 착용을 unknown_character 로 거절하면 아잉으로 되돌린다(not_owned 와 같다) — 다른 캐릭터의 unknown_character 는 그대로 둔다")
    func unknownGoldRevertsToAing() async throws {
        let (store, selection) = await Self.push(Self.gold, reply: #"{"status":"unknown_character","id":"aing_gold"}"#, label: "unknown-gold")
        #expect(selection.selectedID == CharacterCatalog.builtInAingID,
                "옛 서버가 금을 모르는데 로컬은 금 그대로다 — 내 화면엔 금, 남에게는 아잉")
        #expect(store.syncMessage.contains(GachaText.gachaOnlyHint), "되돌린 사실·얻는 길을 안 말했다: \(store.syncMessage)")
        // 기준선: 금이 아닌(루비로 파는) 캐릭터의 unknown_character 는 되돌리지 않는다(앱 번들과 서버 명단이 갈린 것 — 기존 계약).
        // 무지개(v0.3.59)는 금과 같은 쪽이다(`V0359RainbowMacTests`) — 기준선에서 뺀다.
        let fox = try #require(CheckCharacter3DScene.catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID && !CharacterCatalog.isGachaOnlyBuiltIn($0) })
        let (_, other) = await Self.push(fox, reply: #"{"status":"unknown_character","id":"x"}"#, label: "unknown-other")
        #expect(other.selectedID == fox)
    }

    @Test("not_owned 되돌림 안내: 금은 뽑기 문구('뽑기나 조각 교환으로 얻을 수 있어요'), 상점 캐릭터는 그대로 '상점에서 살 수 있어요'")
    func revertNoticeSaysHowToGetGold() async throws {
        let (goldStore, goldSelection) = await Self.push(Self.gold, reply: #"{"status":"not_owned","id":"aing_gold"}"#, label: "not-owned-gold")
        #expect(goldSelection.selectedID == CharacterCatalog.builtInAingID)
        let notice = goldStore.syncMessage
        #expect(notice.contains(GachaText.gachaOnlyHint), "금 되돌림 안내 '\(notice)' — 얻는 길(뽑기·조각)을 안 말한다")
        #expect(!notice.contains("상점에서 살 수 있어요"), "금 되돌림 안내 '\(notice)' — 금은 상점에서 못 산다")
        let fox = try #require(CheckCharacter3DScene.catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID && !CharacterCatalog.isGachaOnlyBuiltIn($0) })
        let (foxStore, _) = await Self.push(fox, reply: #"{"status":"not_owned","id":"x"}"#, label: "not-owned-fox")
        #expect(foxStore.syncMessage == WorkTimerStore.notOwnedRevertNotice)
    }
}
