import Foundation
import Metal
import SceneKit
import Testing
@testable import check
@testable import CheckCore

/// 스프라이트(2D 평면) 캐릭터가 **3D 축 회전을 쓰지 않는다**는 계약.
///
/// **왜 필요한가**(2026-09-13 사용자 신고): "2d 니까 근무시작할때 한바퀴 도는거랑 끝날때 숙이는거가
/// 이상해." 스프라이트는 `SCNPlane` 이라 y축 회전은 **카드 뒤집기**로, x축 회전은 **납작해짐**으로 보인다.
/// 대체 동작은 `ReactionActions` 의 "2D 평면(스프라이트)용 대체 동작" 절에 있다.
///
/// 이 파일은 두 겹으로 지킨다 —
///   ① **재생 계약**: 액션을 실제로 돌려 euler.x/y 를 샘플링한다. Metal 이 필요하다.
///   ② **소스 계약**: flat 함수 본문에 x·y 회전 리터럴이 없다. 장치 없이도 돈다.
/// ①만 두면 헤드리스 러너에서 통째로 건너뛰어 계약이 사라지고, ②만 두면 `pokedAction(yaw:)` 처럼
/// 리터럴이 없는 경로를 놓친다. 둘 다 필요하다.
@Suite("v0.3.16 2D 캐릭터 리액션")
struct V0316Reaction2DTests {

    // MARK: - 재생 하네스

    /// SCNAction 을 헤드리스로 진행시킨다.
    ///
    /// ⚠️ `SCNRenderer.update(atTime:)` 은 **액션 클럭을 돌리지 않는다**(실측: y 가 6 스텝 내내 0 이었다).
    ///    `isPlaying = true` 를 줘도 같다. 실제로 진행시키는 것은 `snapshot(atTime:...)` 뿐이다
    ///    (같은 실측에서 y 가 0 → 6.28 = 2π 로 정확히 돌았다). 8×8 로 찍으므로 비용도 무시할 만하다.
    @MainActor
    private static func samples(of action: SCNAction, steps: Int = 24) -> [SCNVector3]? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scene = SCNScene()
        let node = SCNNode()
        node.geometry = SCNPlane(width: 1, height: 1)
        scene.rootNode.addChildNode(node)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        node.runAction(action)
        var out: [SCNVector3] = []
        let dt = max(action.duration, 0.01) / Double(steps - 1)
        for index in 0..<steps {
            _ = renderer.snapshot(atTime: Double(index) * dt,
                                  with: CGSize(width: 8, height: 8), antialiasingMode: .none)
            out.append(node.eulerAngles)
        }
        return out
    }

    /// 착용 캐릭터별 엔진. `id` 가 nil 이면 아잉(3D).
    @MainActor
    private static func engine(_ id: String?) throws -> ReactionEngine {
        let scene: SCNScene
        if let id {
            let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
            let manifest = try #require(catalog.manifest(id: id), "번들에 \(id) 가 없다")
            let atlas = try #require(CheckCharacter3DScene.atlasImage(for: manifest))
            scene = try #require(CheckCharacter3DScene.makeScene(animated: false,
                                                                character: manifest, atlas: atlas))
        } else {
            scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
        }
        let wrapper = try #require(
            scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        let engine = ReactionEngine()
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
        return engine
    }

    /// 사용자가 지목한 둘 + 같은 결함을 갖고 있던 나머지.
    private static let flatKinds: [ReactionKind] = [.commuteStart, .commuteEnd,
                                                    .poked(bubbleText: "x"), .goalAchieved]

    // MARK: - ① 재생 계약

    @MainActor
    @Test("스프라이트로 나가는 동작에는 x·y 회전이 한 톨도 없다 (실제 재생)")
    func spriteActionsNeverRotateOutOfPlane() throws {
        let sprite = try Self.engine("shiba")
        #expect(sprite.isSpriteCharacter, "스프라이트를 붙였는데 엔진이 3D 로 본다 — 갈림길이 통째로 죽는다")
        for kind in Self.flatKinds {
            let action = try #require(sprite.reactionAction(for: kind))
            guard let euler = Self.samples(of: action) else { return }   // Metal 없음 → ② 가 지킨다
            let maxX = euler.map { abs(CGFloat($0.x)) }.max() ?? 0
            let maxY = euler.map { abs(CGFloat($0.y)) }.max() ?? 0
            #expect(maxX < 1e-4, "\(kind) 가 스프라이트에서 x축으로 \(maxX)rad 눕는다 — 납작해진다")
            #expect(maxY < 1e-4, "\(kind) 가 스프라이트에서 y축으로 \(maxY)rad 돈다 — 카드 뒤집기가 된다")
            // 평면이라도 **동작 자체는 살아 있어야** 한다(z 로 옮겼지 지운 게 아니다).
            let maxZ = euler.map { abs(CGFloat($0.z)) }.max() ?? 0
            #expect(maxZ > 1e-3, "\(kind) 가 스프라이트에서 아무 회전도 안 한다 — 옮긴 게 아니라 지웠다")
        }
    }

    @MainActor
    @Test("★ 기준선이 실제로 다르다 — 아잉은 종전대로 x·y 로 움직인다")
    func aingStillRotatesOutOfPlane() throws {
        // 이 테스트가 없으면 위 테스트는 "원래부터 x·y 를 안 쓴다"로도 초록이 되어 아무것도 안 지킨다.
        // 동시에 이것이 **아잉 무변화의 직접 증거**다.
        let aing = try Self.engine(nil)
        #expect(aing.isSpriteCharacter == false, "아잉인데 스프라이트로 봤다")
        var movedOutOfPlane = 0
        for kind in Self.flatKinds {
            let action = try #require(aing.reactionAction(for: kind))
            guard let euler = Self.samples(of: action) else { return }
            let out = max(euler.map { abs(CGFloat($0.x)) }.max() ?? 0,
                          euler.map { abs(CGFloat($0.y)) }.max() ?? 0)
            if out > 1e-3 { movedOutOfPlane += 1 }
        }
        #expect(movedOutOfPlane == Self.flatKinds.count,
                Comment(rawValue: "아잉의 \(Self.flatKinds.count)개 중 \(movedOutOfPlane)개만 x·y 로 움직인다 — "
                        + "3D 쪽을 같이 평면화했거나, 애초에 평면화할 게 없던 동작을 목록에 넣었다"))
    }

    @MainActor
    @Test("졸기 가라앉기도 갈린다 — 자는 내내 유지되는 포즈라 여기가 제일 위험하다")
    func drowsySinkIsFlatForSprites() throws {
        // ⚠️ **엔진을 거쳐서** 받아야 한다. 팩토리(`ReactionActions.flatDrowsySink`)를 직접 부르면
        //    엔진의 갈림길을 통째로 지워도 초록이다 — 실제로 그 뮤테이션(M2)이 살아남았다.
        //    졸기는 `reactionAction(for:)` 이 nil 을 주는 유일한 kind 라 갈림길이 따로 있고, 그래서 따로 문다.
        guard let flat = Self.samples(of: try Self.engine("shiba").drowsySinkAction()),
              let solid = Self.samples(of: try Self.engine(nil).drowsySinkAction()) else { return }
        #expect((flat.map { abs(CGFloat($0.x)) }.max() ?? 0) < 1e-4)
        #expect((flat.map { abs(CGFloat($0.y)) }.max() ?? 0) < 1e-4)
        #expect((flat.map { abs(CGFloat($0.z)) }.max() ?? 0) > 1e-3, "평면인데 기울지도 않는다")
        #expect((solid.map { abs(CGFloat($0.x)) }.max() ?? 0) > 1e-3, "아잉 졸기가 안 숙인다 — 3D 를 같이 고쳤다")
    }

    @MainActor
    @Test("flat 동작은 identity 로 시작해 identity 로 끝난다(이 파일의 잔상 금지 규약)")
    func flatActionsLeaveNoResidue() throws {
        // drowsySink 는 **의도적으로** 자세를 유지하는 지속 상태라 제외한다(drowsyRise/wake 가 복원한다).
        let actions: [(String, SCNAction)] = [
            ("flatCommuteStart", ReactionActions.flatCommuteStart(hop: 0.6)),
            ("flatCommuteEnd", ReactionActions.flatCommuteEnd()),
            ("flatPoked", ReactionActions.flatPoked(extent: 1.9)),
            ("flatGoalAchieved", ReactionActions.flatGoalAchieved(hop: 0.65))
        ]
        for (name, action) in actions {
            guard let euler = Self.samples(of: action) else { return }
            let first = try #require(euler.first), last = try #require(euler.last)
            for (label, value) in [("시작", first), ("끝", last)] {
                #expect(abs(CGFloat(value.x)) < 1e-4 && abs(CGFloat(value.y)) < 1e-4
                        && abs(CGFloat(value.z)) < 1e-3,
                        "\(name) 의 \(label) 자세가 identity 가 아니다 — 기운 잔상이 남는다")
            }
        }
    }

    @MainActor
    @Test("flat 과 3D 의 길이가 같다 — ReactionKind.duration 이 원본에 맞춰져 있다")
    func flatAndSolidDurationsMatch() {
        let pairs: [(String, SCNAction, SCNAction)] = [
            ("commuteStart", ReactionActions.commuteStart(hop: 0.6), ReactionActions.flatCommuteStart(hop: 0.6)),
            ("commuteEnd", ReactionActions.commuteEnd(), ReactionActions.flatCommuteEnd()),
            ("poked", ReactionActions.poked(extent: 1.9), ReactionActions.flatPoked(extent: 1.9)),
            ("goalAchieved", ReactionActions.goalAchieved(hop: 0.65), ReactionActions.flatGoalAchieved(hop: 0.65)),
            ("drowsySink", ReactionActions.drowsySink(tilt: 0.35), ReactionActions.flatDrowsySink(tilt: 0.35))
        ]
        for (name, solid, flat) in pairs {
            #expect(abs(solid.duration - flat.duration) < 0.01,
                    Comment(rawValue: "\(name): 3D \(solid.duration)s vs 평면 \(flat.duration)s — "
                            + "길어지면 재생 도중 만료되고 짧아지면 빈 시간이 남는다"))
        }
        // 재생 길이 계약도 평면 쪽에서 그대로 성립해야 한다.
        #expect(ReactionKind.goalAchieved.duration >= ReactionActions.flatGoalAchieved(hop: 0.65).duration)
        #expect(ReactionKind.commuteStart.duration >= ReactionActions.flatCommuteStart(hop: 0.6).duration)
    }

    // MARK: - ② 소스 계약 (Metal 없이도 돈다)

    @MainActor
    @Test("flat 함수 본문에 x·y 회전 리터럴이 없다")
    func flatSourceUsesOnlyZRotation() throws {
        // ⚠️ 소스 계약은 **주석을 걷어낸 뒤** 검사한다. 안 그러면 설명을 지워야만 초록이 되는 테스트가 된다
        //    (이 저장소가 실제로 밟은 함정이다).
        let raw = try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayReactions.swift")
        let source = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")

        let names = ["flatCommuteStart", "flatCommuteEnd", "flatDrowsySink", "flatGoalAchievedSwing"]
        for name in names {
            let body = try #require(Self.functionBody(named: name, in: source), "\(name) 을 소스에서 못 찾았다")
            #expect(body.contains("rotate"), "\(name) 에 회전이 아예 없다 — 이 검사가 헛돈다")
            // 이 절의 모든 회전은 반드시 `rotateTo(x: 0, y: 0, z: …)` 꼴이어야 한다.
            var scan = body[...]
            while let hit = scan.range(of: "rotate") {
                let rest = scan[hit.lowerBound...]
                #expect(rest.hasPrefix("rotateTo(x: 0, y: 0, z: "),
                        "\(name) 에 평면에서 깨지는 회전이 있다: \(rest.prefix(60))")
                scan = scan[hit.upperBound...]
            }
        }
    }

    /// `func <name>(` 부터 중괄호 균형이 맞을 때까지의 본문. 문자열 리터럴이 없는 코드라 단순 카운팅으로 충분하다.
    private static func functionBody(named name: String, in source: String) -> String? {
        guard let start = source.range(of: "func \(name)(") else { return nil }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
