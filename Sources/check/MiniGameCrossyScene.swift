import AppKit
import SceneKit
import CheckCore

// MARK: - 길건너 아잉이 — SceneKit 판 (v0.3.67)
//
// 규칙은 `CrossyGame`(코어 값 타입)에 있고, 이 파일은 그 값을 **읽어서 노드에 옮기기만** 한다. 판을 바꾸는 코드는
// 한 줄도 없다 — 그림이 규칙을 알기 시작하면 폰(다음 판)이 같은 판을 다르게 보게 된다.
//
// ── 화풍: 시안 B "비스듬한 블록" ───────────────────────────────────────────────────────────
// 사용자가 시안 셋(A 평면 · B 블록 · C 뒤에서) 중 B 를 골랐다(2026-10-27). 숫자의 출처는 시안 스크립트
// `v0367-crossy/drafts/render.swift` 의 `renderB`·`buildWorld(.block)` 이다:
//   · 정사영 카메라 · 내려다보는 각 56° · 옆 14° · 해(왼쪽 뒤 위) + 주변광 · 그림자 색 0.34 · 표본 1(각진 그림자).
//   · 각진 상자 차 · 통나무 · 나무 · 바위, 놀이 칸 밖은 같은 색을 22% 어둡게 + 경계 숲.
//   · 아잉이는 오버레이와 같은 `aing.scn`(unlit) — 판의 빛·그림자를 받지 않고 드리우지도 않는다. 그림자는 발밑
//     둥근 얼룩 하나다(해 그림자는 비스듬히 떨어져 '얼마나 떴나'가 안 읽힌다 — 시안 주석 그대로).
// **시안보다 카메라를 당겼다**(설계서 §0): 시안은 정사영 배율 4.4 · 아잉이 0.92칸이라 화면에서 약 35pt 였다.
// 여기서는 배율 3.1 · 아잉이 0.98칸 → 약 53pt(증거 PNG 에서 실측한 값은 시험 출력에 찍힌다). 대신 한 화면에 보이는
// 가로 폭이 약 6칸이라 카메라가 아잉이를 **가로로도** 따라간다(놀이 칸 9칸 중 어디서든 양옆 차가 보이게).
//
// ── 60Hz 예산 ────────────────────────────────────────────────────────────────────────────
// 줄 · 차 · 통나무 · 나무는 **노드 풀**에서 꺼내 쓰고 화면 밖으로 나가면 돌려준다. 모양(지오메트리)은 종류마다 한 번
// 만들어 `flattenedClone` 으로 한 덩어리로 굳히고 모든 노드가 나눠 쓴다(차 한 대 = 노드 하나 = 그리기 호출 몇 개).
// SCNView 는 `rendersContinuously = false` 라 노드가 안 바뀌면 그리지 않는다 — 판이 멈추면(정지 · 결과) GPU 도 쉰다.
// 그림자 맵은 2048(설계서 상한). 시안은 4096 이었지만 카메라를 당겨 그림자가 덮을 땅이 줄었다.

/// 판 한 장의 SceneKit 씬과 노드 풀. 화면(`CrossySceneView`)과 시험(오프스크린 `SCNRenderer`)이 같은 것을 쓴다.
///
/// `ObservableObject` 인 이유는 하나다 — 잎 뷰가 `@StateObject` 로 쥐어 **처음 한 번만** 만들게 하려고(그 이니셜라이저는
/// 자동 클로저다). `@State` 에 넣으면 허브가 잎 뷰를 다시 지을 때마다(정지 · 판 시작 · 주사율) 이 init 이 돌아 아잉이
/// 모델을 다시 읽는다(수십 ms — 판 도중의 끊김이다). 알리는 값(@Published)은 없다.
@MainActor
final class CrossyScene: ObservableObject {
    // MARK: 그림 상수(난이도와 무관)

    /// 정사영 배율(세로 반폭, 월드 단위). 시안 4.4 → 당김.
    static let orthographicScale: CGFloat = 3.1
    /// 카메라 각(시안 그대로).
    static let pitchDegrees: Float = 56
    static let yawDegrees: Float = 14
    /// 카메라 초점(아잉이 줄)을 화면 가운데보다 아래에 두는 거리 — 앞을 더 보게(줄 단위, 화면 위쪽 방향).
    static let lookAhead: Float = 1.35
    /// 카메라 가로 따라가기 한계(월드 x, 가운데 칸 기준 ±). 놀이 칸 끝에서 경계가 조금 보이는 자리다.
    static let cameraSwing: Float = 2.0
    /// 아잉이 키(월드 단위 = 칸). 시안 0.92 → 0.98.
    static let aingHeight: Float = 0.98
    /// 뛸 때 가장 높이 뜨는 높이(칸). 시안의 들어 올림 0.62 를 키에 맞춰 줄였다.
    static let hopLift: Float = 0.55
    /// 그림자 맵(설계서 상한 2048).
    static let shadowMapSize: CGFloat = 2048
    /// 화면에 세우는 줄 범위(카메라 줄 기준).
    static let rowsBehind = 5
    static let rowsAhead = 11
    /// 놀이 칸 밖까지 땅을 까는 반폭(월드).
    static let groundHalfWidth: Float = 16
    /// 바탕(캔버스 남색 — `CheckTheme.background` 시작색, 시안과 같다).
    static let backgroundHex: UInt32 = 0x1A1C26

    /// 줄 종류별 땅 윗면 높이(시안 `laneTop` · 기찻길은 새로).
    static func groundTop(_ kind: CrossyGame.LaneKind) -> Float {
        switch kind {
        case .grass: 0
        case .road: -0.08
        case .river: -0.30
        case .rail: -0.04
        }
    }

    /// 아잉이가 서는 높이(강이면 통나무 윗면).
    static func standHeight(_ kind: CrossyGame.LaneKind?) -> Float {
        switch kind {
        case .grass, .none: 0
        case .road: -0.08
        case .river: -0.08
        case .rail: -0.04
        }
    }

    // MARK: 노드

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let world = SCNNode()
    private let sunNode = SCNNode()
    private let aingRoot = SCNNode()
    private let aingBody = SCNNode()
    private let blobNode: SCNNode
    private let splashNode: SCNNode
    /// 아잉이 모델을 읽었는가(못 읽으면 보라 공으로 대신한다 — 판은 그대로 돈다).
    private(set) var loadedModel = false

    private var rows: [Int: CrossyRowNode] = [:]
    private var rowPool: [CrossyRowNode] = []
    private var propPool: [String: [SCNNode]] = [:]
    private var moverPool: [String: [SCNNode]] = [:]
    private let palette = CrossyPalette.shared

    /// 지금 그린 판의 시드 — 새 판이면 줄을 전부 돌려받는다(같은 줄 번호에 다른 줄이 선다).
    private var seenRoundSeed: UInt64?
    /// 카메라 가로 자리(부드럽게 따라간다).
    private var cameraX: Float = 0
    private var lastElapsed: TimeInterval = 0
    /// 착지 순간(판 시계) — 짧은 납작 눌림을 그린다.
    private var landedAt: TimeInterval?
    private var wasHopping = false
    /// 새로 만든 노드 수(풀이 비어 있을 때만 는다) — 시험이 "풀이 실제로 재활용되는가"를 잰다.
    private(set) var madeRows = 0
    private(set) var madeProps = 0
    private(set) var madeMovers = 0

    init() {
        scene.background.contents = palette.color(Self.backgroundHex)
        scene.rootNode.addChildNode(world)

        // 카메라 — 정사영 · 시안 각.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(Self.orthographicScale)
        camera.projectionDirection = .vertical
        camera.zNear = 1
        camera.zFar = 120
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // 빛 — 주변광 + 해(왼쪽 뒤 위). 아잉이 몸은 unlit 이라 이 빛과 무관하다.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 430
        ambient.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 760
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowColor = NSColor(white: 0, alpha: 0.34)
        sun.shadowMapSize = CGSize(width: Self.shadowMapSize, height: Self.shadowMapSize)
        sun.shadowSampleCount = 1
        sun.shadowRadius = 1
        sun.automaticallyAdjustsShadowProjection = false
        sun.orthographicScale = 7
        sun.zNear = 0.1
        sun.zFar = 80
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        // 아잉이 — 발밑 둥근 그림자 + 몸.
        blobNode = SCNNode(geometry: palette.blobPlane)
        blobNode.eulerAngles.x = -.pi / 2
        blobNode.castsShadow = false
        world.addChildNode(blobNode)
        splashNode = SCNNode(geometry: palette.splashRing)
        splashNode.castsShadow = false
        splashNode.isHidden = true
        world.addChildNode(splashNode)
        aingRoot.addChildNode(aingBody)
        world.addChildNode(aingRoot)
        loadAing()
    }

    // MARK: 아잉이 모델

    private func loadAing() {
        guard let loaded = CheckCharacter3DScene.loadModelScene(order: CheckCharacter3DScene.ModelSource.allCases) else {
            // 모델이 없는 환경(번들 손상) — 판은 그대로 돌게 보라 공 하나로 대신한다.
            let fallback = SCNNode(geometry: palette.fallbackAing)
            fallback.simdPosition = SIMD3(0, Self.aingHeight / 2, 0)
            aingBody.addChildNode(fallback)
            return
        }
        let modelScene = loaded.scene
        // 오버레이와 **같은 함수**로 unlit 을 건다(MiniGameMascot.bake 와 같은 근거 — 색의 전부다).
        CheckCharacter3DScene.applyUnlitMaterials(to: modelScene.rootNode)
        guard let character = modelScene.rootNode.childNodes.first else { return }
        let (minB, maxB) = modelScene.rootNode.boundingBox
        let height = Float(maxB.y - minB.y)
        guard height > 0 else { return }
        character.removeFromParentNode()
        // 원점을 **발밑 가운데**로(시안 makeAing 과 같다) — 눌림·늘임이 발을 축으로 일어나게.
        let holder = SCNNode()
        holder.addChildNode(character)
        holder.simdPosition = SIMD3(-Float(minB.x + maxB.x) / 2, -Float(minB.y), -Float(minB.z + maxB.z) / 2)
        let scaler = SCNNode()
        scaler.addChildNode(holder)
        scaler.simdScale = SIMD3(repeating: Self.aingHeight / height)
        scaler.enumerateHierarchy { node, _ in node.castsShadow = false }
        aingBody.addChildNode(scaler)
        loadedModel = true
    }

    // MARK: 한 프레임

    /// 판 값 하나를 노드에 옮긴다. 판이 같으면 노드도 같다(이 함수는 판을 바꾸지 않는다).
    func apply(_ game: CrossyGame, reduceMotion: Bool) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }

        if seenRoundSeed != game.roundSeed {
            // 새 판 — 줄을 전부 돌려받고 카메라를 시작 자리로.
            for row in rows.keys.sorted() { releaseRow(row) }
            seenRoundSeed = game.roundSeed
            cameraX = clampedCameraX(for: game.playerVisual.x)
            landedAt = nil
            wasHopping = false
        }
        let dt = max(0, min(0.1, game.elapsed - lastElapsed))
        lastElapsed = game.elapsed

        let focusRow = Int(game.cameraRow.rounded(.down))
        let wanted = (focusRow - Self.rowsBehind)...(focusRow + Self.rowsAhead)
        for row in rows.keys where !wanted.contains(row) { releaseRow(row) }
        for row in wanted {
            guard let lane = game.lane(at: row) else {
                releaseRow(row)
                continue
            }
            let node = rows[row] ?? acquireRow(lane: lane, game: game)
            update(node, lane: lane, game: game)
        }

        updateAing(game, reduceMotion: reduceMotion)
        updateCamera(game, dt: dt)
    }

    // MARK: 줄 풀

    private func acquireRow(lane: CrossyGame.Lane, game: CrossyGame) -> CrossyRowNode {
        let node: CrossyRowNode
        if let pooled = rowPool.popLast() {
            node = pooled
        } else {
            node = CrossyRowNode()
            madeRows += 1
        }
        let next = game.lane(at: lane.row + 1)
        let dark = lane.row & 1 == 0
        node.slab.geometry = palette.slab(lane.kind, darkRow: dark, outside: false)
        node.leftOutside.geometry = palette.slab(lane.kind, darkRow: dark, outside: true)
        node.rightOutside.geometry = node.leftOutside.geometry
        let top = Self.groundTop(lane.kind)
        node.slab.simdPosition = SIMD3(0, top - CrossyPalette.slabDepth / 2, 0)
        let outsideCenter = 4.5 + (Self.groundHalfWidth - 4.5) / 2
        node.leftOutside.simdPosition = SIMD3(-outsideCenter, top - CrossyPalette.slabDepth / 2, 0)
        node.rightOutside.simdPosition = SIMD3(outsideCenter, top - CrossyPalette.slabDepth / 2, 0)
        // 무늬: 찻길끼리 붙은 경계의 점선 · 강 물결 · 기찻길 침목과 레일 · 풀밭 경계 숲.
        switch lane.kind {
        case .road:
            node.decor.geometry = next?.kind == .road ? palette.roadDashes : nil
            node.decor.simdPosition = SIMD3(0, top + 0.005, -0.5)
        case .river:
            node.decor.geometry = palette.riverWaves(variant: lane.row & 1)
            node.decor.simdPosition = SIMD3(0, top + 0.004, 0)
        case .rail:
            node.decor.geometry = palette.railTrack
            node.decor.simdPosition = SIMD3(0, top, 0)
        case .grass:
            node.decor.geometry = palette.borderForest(variant: lane.row & 1)
            node.decor.simdPosition = SIMD3(0, 0, 0)
        }
        // 풀밭 물건(놀이 칸 안).
        if lane.kind == .grass {
            for column in 0..<CrossyGame.columns {
                guard let prop = lane.props[column] else { continue }
                let key = palette.propKey(prop, column: column, row: lane.row)
                let geometry = palette.prop(key)
                let propNode = take(&propPool, key) {
                    madeProps += 1
                    return SCNNode(geometry: geometry)
                }
                propNode.simdPosition = SIMD3(Float(column) - 4, 0, 0)
                node.node.addChildNode(propNode)
                node.props.append((key, propNode))
            }
        }
        // 움직이는 것.
        if lane.kind == .road || lane.kind == .river {
            for mover in lane.movers {
                let key = lane.kind == .road ? palette.vehicleKey(mover) : palette.logKey(mover)
                let geometry = lane.kind == .road ? palette.vehicle(key) : palette.log(key)
                let moverNode = take(&moverPool, key) {
                    madeMovers += 1
                    return SCNNode(geometry: geometry)
                }
                node.node.addChildNode(moverNode)
                node.movers.append((key, moverNode))
            }
        }
        if lane.kind == .rail {
            node.train.geometry = palette.train
            node.leftSignal.isHidden = false
            node.rightSignal.isHidden = false
        } else {
            node.train.geometry = nil
            node.leftSignal.isHidden = true
            node.rightSignal.isHidden = true
        }
        node.node.simdPosition = SIMD3(0, 0, -Float(lane.row))
        world.addChildNode(node.node)
        rows[lane.row] = node
        return node
    }

    private func releaseRow(_ row: Int) {
        guard let node = rows.removeValue(forKey: row) else { return }
        for (key, prop) in node.props {
            prop.removeFromParentNode()
            propPool[key, default: []].append(prop)
        }
        for (key, mover) in node.movers {
            mover.removeFromParentNode()
            moverPool[key, default: []].append(mover)
        }
        node.props.removeAll()
        node.movers.removeAll()
        node.node.removeFromParentNode()
        rowPool.append(node)
    }

    private func take(_ pool: inout [String: [SCNNode]], _ key: String, make: () -> SCNNode) -> SCNNode {
        if let node = pool[key]?.popLast() { return node }
        return make()
    }

    /// 줄의 움직이는 부분(차 · 통나무 · 기차 · 경고등 · 물결).
    private func update(_ node: CrossyRowNode, lane: CrossyGame.Lane, game: CrossyGame) {
        let top = Self.groundTop(lane.kind)
        switch lane.kind {
        case .road, .river:
            for (index, mover) in lane.movers.enumerated() where index < node.movers.count {
                let moverNode = node.movers[index].node
                let center = Float(mover.x + mover.length / 2) - 4
                moverNode.simdPosition = SIMD3(center, lane.kind == .road ? top : 0, 0)
                moverNode.eulerAngles.y = lane.direction < 0 ? .pi : 0
            }
            if lane.kind == .river {
                // 물결은 흐름 쪽으로 천천히(무늬 간격으로 감아 이음매가 안 보이게).
                let drift = Float((game.elapsed * lane.velocity * 0.35).truncatingRemainder(dividingBy: Double(CrossyPalette.waveSpacing)))
                node.decor.simdPosition = SIMD3(drift, top + 0.004, 0)
            }
        case .rail:
            if let train = lane.train {
                node.train.isHidden = false
                node.train.simdPosition = SIMD3(Float(train.x + train.length / 2) - 4, top, 0)
                node.train.eulerAngles.y = lane.direction < 0 ? .pi : 0
            } else {
                node.train.isHidden = true
            }
            // 경고등: 켜진 동안 0.15초 간격으로 깜빡인다(판 시계 — 정지하면 같이 멈춘다).
            // 기둥(놀이 칸 양끝 밖)은 카메라를 당긴 화면에서 자주 화면 밖이다 — 그래서 **레일 자체**도 같은 박자로 붉게
            // 깜빡인다(첫 증거 PNG 에서 기둥이 한 번도 안 보였다). 아잉이가 어디 있든 지금 건너려는 줄이 경고를 말한다.
            let blinkOn = lane.isTrainWarning && Int(game.elapsed / 0.15) % 2 == 0
            let lamp = blinkOn ? palette.lampOn : palette.lampOff
            node.leftLamp.geometry = lamp
            node.rightLamp.geometry = lamp
            node.decor.geometry = blinkOn ? palette.railTrackWarning : palette.railTrack
        case .grass:
            break
        }
    }

    // MARK: 아잉이

    private func updateAing(_ game: CrossyGame, reduceMotion: Bool) {
        let visual = game.playerVisual
        var x = Float(visual.x) - 4
        var z = -Float(visual.row)
        let kindHere: CrossyGame.LaneKind? = game.lane(at: Int(visual.row.rounded()))?.kind
        var y = Self.standHeight(kindHere)
        if let hop = game.hop {
            let fromY = Self.standHeight(game.lane(at: hop.fromRow)?.kind)
            let toY = Self.standHeight(game.lane(at: hop.toRow)?.kind)
            y = fromY + (toY - fromY) * Float(hop.progress)
        }
        let lift = reduceMotion ? 0 : Float(visual.lift) * Self.hopLift
        // 뛰는 중 늘이기(시안 0.90 · 1.13) · 착지 직후 0.08초 눌림.
        var scaleXZ: Float = 1
        var scaleY: Float = 1
        if game.hop != nil {
            wasHopping = true
            if !reduceMotion {
                let s = Float(sin(Double.pi * (game.hop?.progress ?? 0)))
                scaleY = 1 + 0.13 * s
                scaleXZ = 1 - 0.10 * s
            }
        } else if wasHopping {
            wasHopping = false
            landedAt = game.elapsed
        }
        if let landed = landedAt, !reduceMotion, game.hop == nil {
            let t = (game.elapsed - landed) / 0.08
            if t < 1 {
                let squash = Float(sin(Double.pi * t))
                scaleY = 1 - 0.12 * squash
                scaleXZ = 1 + 0.08 * squash
            }
        }
        // 얼굴이 보이게 튼다 — 앞·뒤는 시안처럼 카메라 쪽(−8°), 옆은 그쪽으로 55°(얼굴 반쪽이 남는 각).
        var yaw = Self.facingYaw(game.player.facing)
        var roll: Float = 0
        var pitch: Float = 0
        var opacity: CGFloat = 1
        var splash: (x: Float, z: Float, t: Double)?

        if let death = game.death {
            x = Float(death.x) - 4
            z = -Float(death.row)
            let t = max(0, game.elapsed - death.at)
            let kind = game.lane(at: death.row)?.kind
            y = Self.standHeight(kind)
            let ease = Float(min(1, t / 0.12))
            switch death.cause {
            case .car:
                // 납작 — 0.12초 만에 눌려 붙고 그대로 남는다.
                scaleY = 1 - 0.82 * ease
                scaleXZ = 1 + 0.35 * ease
                yaw = Self.facingYaw(.forward)
            case .water, .carriedOff:
                // 첨벙 — 가라앉는다. 물결 고리가 퍼진다.
                let sink = Float(min(1, t / 0.55))
                y = Self.groundTop(.river) - 0.9 * sink * sink
                opacity = CGFloat(max(0, 1 - sink))
                splash = (x, z, t)
            case .train:
                // 튕겨 날아간다 — 기차 쪽으로 · 위로 · 돌면서.
                let fly = Float(min(t, 0.9))
                x += Float(death.pushDirection) * 7.5 * fly
                y += 3.2 * fly - 3.0 * fly * fly
                roll = Float(death.pushDirection) * -11 * fly
                opacity = t > 0.9 ? 0 : 1
            case .leftBehind:
                // 놓침 — 뒤로 넘어지며 화면 아래로 빠진다.
                let fall = Float(min(1, t / 0.7))
                pitch = 1.3 * fall
                z += 1.6 * fall * fall
                y -= 0.4 * fall * fall
                opacity = CGFloat(max(0, 1 - fall))
            }
            if reduceMotion {
                // 동작 줄이기: 움직이는 연출 없이 그 자리에서 사라진다(사유는 결과 카드 글자가 말한다).
                scaleXZ = 1; scaleY = 1; roll = 0; pitch = 0
                x = Float(death.x) - 4
                z = -Float(death.row)
                y = Self.standHeight(kind)
                opacity = CGFloat(max(0, 1 - t / 0.4))
            }
        }

        aingRoot.simdPosition = SIMD3(x, y + lift, z)
        aingBody.simdScale = SIMD3(scaleXZ, scaleY, scaleXZ)
        aingBody.eulerAngles = SCNVector3(CGFloat(pitch), CGFloat(yaw), CGFloat(roll))
        aingRoot.opacity = opacity

        // 발밑 그림자 — 뛰면 작고 옅어진다(시안 0.92 → 0.64). 물에 빠지면 없다.
        let ground = y
        let liftShare = Float(visual.lift)
        let blobScale = 1 - 0.30 * liftShare
        blobNode.simdPosition = SIMD3(x, ground + 0.006, z)
        blobNode.simdScale = SIMD3(blobScale, blobScale, 1)
        blobNode.opacity = (game.death?.cause == .water || game.death?.cause == .carriedOff || game.death?.cause == .train)
            ? 0 : CGFloat(1 - 0.3 * liftShare) * opacity

        if let splash, !reduceMotion {
            let p = min(1, splash.t / 0.6)
            splashNode.isHidden = p >= 1
            splashNode.simdPosition = SIMD3(splash.x, Self.groundTop(.river) + 0.01, splash.z)
            let s = Float(0.4 + 1.4 * p)
            splashNode.simdScale = SIMD3(s, 1, s)
            splashNode.opacity = CGFloat(0.9 * (1 - p))
        } else {
            splashNode.isHidden = true
        }
    }

    /// 몸을 트는 각(라디안, y 축). 모델의 얼굴은 +z(카메라 쪽)다.
    static func facingYaw(_ direction: CrossyGame.Direction) -> Float {
        switch direction {
        case .forward, .back: -8 * .pi / 180
        case .left: -55 * .pi / 180
        case .right: 55 * .pi / 180
        }
    }

    // MARK: 카메라

    private func clampedCameraX(for x: Double) -> Float {
        min(Self.cameraSwing, max(-Self.cameraSwing, Float(x) - 4))
    }

    private func updateCamera(_ game: CrossyGame, dt: TimeInterval) {
        let wantedX = clampedCameraX(for: game.death.map { $0.x } ?? game.playerVisual.x)
        // 가로는 부드럽게(통나무를 타는 동안 화면이 같이 미끄러지게) — 세로는 규칙의 카메라를 그대로 쓴다.
        let k = Float(min(1, dt * 6))
        cameraX += (wantedX - cameraX) * k
        let pitch = Self.pitchDegrees * .pi / 180
        let yaw = Self.yawDegrees * .pi / 180
        let up = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let focus = SIMD3<Float>(cameraX, 0, -Float(game.cameraRow))
        let target = focus + up * Self.lookAhead
        cameraNode.simdPosition = target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 40
        cameraNode.simdLook(at: target)
        // 해는 카메라 초점을 따라간다 — 그림자 상자(정사영 7)가 언제나 보이는 땅을 덮게.
        sunNode.simdPosition = target + simd_normalize(SIMD3<Float>(-4, 10, 5)) * 30
        sunNode.simdLook(at: target)
    }

    #if DEBUG
    /// 시험 전용: 지금 쓰는 줄 · 풀에 쉬는 줄 · 풀에 쉬는 물체 수(노드 풀이 실제로 재활용되는지 잰다).
    var poolCountsForTesting: (activeRows: Int, pooledRows: Int, pooledProps: Int, pooledMovers: Int) {
        (rows.count, rowPool.count, propPool.values.reduce(0) { $0 + $1.count },
         moverPool.values.reduce(0) { $0 + $1.count })
    }

    /// 시험 전용: 아잉이 몸의 지금 배율 · 위치(뛰기 늘이기 · 죽음 연출이 실제로 걸리는지).
    var aingTransformForTesting: (position: SIMD3<Float>, scale: SIMD3<Float>, opacity: CGFloat) {
        (aingRoot.simdPosition, aingBody.simdScale, aingRoot.opacity)
    }

    var sunForTesting: SCNLight? { sunNode.light }

    /// 시험 전용: 아잉이 몸(과 발밑 그림자)을 숨긴다 — 숨긴 판과 견주어 화면에서 아잉이가 차지한 크기를 잰다.
    func setAingHiddenForTesting(_ hidden: Bool, includingShadow: Bool = true) {
        aingRoot.isHidden = hidden
        if includingShadow { blobNode.isHidden = hidden }
    }

    /// 시험 전용: 발밑 그림자만 숨긴다(몸 크기를 그림자 없이 재려고).
    func setShadowHiddenForTesting(_ hidden: Bool) {
        blobNode.isHidden = hidden
    }
    #endif
}

/// 풀에서 꺼내 쓰는 줄 한 장(땅 · 바깥 땅 둘 · 무늬 · 물건 · 움직이는 것 · 기차 · 경고등).
@MainActor
final class CrossyRowNode {
    let node = SCNNode()
    let slab = SCNNode()
    let leftOutside = SCNNode()
    let rightOutside = SCNNode()
    let decor = SCNNode()
    let train = SCNNode()
    let leftSignal = SCNNode()
    let rightSignal = SCNNode()
    let leftLamp = SCNNode()
    let rightLamp = SCNNode()
    var props: [(key: String, node: SCNNode)] = []
    var movers: [(key: String, node: SCNNode)] = []

    init() {
        for child in [slab, leftOutside, rightOutside, decor, train, leftSignal, rightSignal] { node.addChildNode(child) }
        train.isHidden = true
        let palette = CrossyPalette.shared
        leftSignal.geometry = palette.signalPost
        rightSignal.geometry = palette.signalPost
        // 경고등 기둥은 놀이 칸 바로 밖(양끝) · 줄 앞쪽 끝에 선다 — 카메라가 어느 쪽에 있어도 하나는 보인다.
        leftSignal.simdPosition = SIMD3(-5.0, -0.04, 0.36)
        rightSignal.simdPosition = SIMD3(5.0, -0.04, 0.36)
        leftLamp.simdPosition = SIMD3(0, CrossyPalette.signalHeight, 0.08)
        rightLamp.simdPosition = SIMD3(0, CrossyPalette.signalHeight, 0.08)
        leftSignal.addChildNode(leftLamp)
        rightSignal.addChildNode(rightLamp)
        leftSignal.isHidden = true
        rightSignal.isHidden = true
    }
}

// MARK: - 모양 · 색(한 번 만들어 나눠 쓴다)

/// 판의 모든 모양. 종류마다 **한 번** 만들고 굳혀(flattenedClone) 노드들이 나눠 쓴다.
@MainActor
final class CrossyPalette {
    static let shared = CrossyPalette()

    static let slabDepth: Float = 1.6
    static let waveSpacing: Float = 2.1
    static let signalHeight: Float = 1.02

    /// 차 색(시안: 파랑 · 루비 · 금 · 청록 + 주황).
    static let carColors: [UInt32] = [0x3A7BF0, 0xE0479E, 0xF2B632, 0x35C2A0, 0xF06A3C]

    private var cache: [String: SCNGeometry] = [:]

    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = CGFloat((a >> shift) & 0xFF), y = CGFloat((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    private func material(_ hex: UInt32, constant: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color(hex)
        m.lightingModel = constant ? .constant : .lambert
        return m
    }

    private func cached(_ key: String, _ make: () -> SCNGeometry) -> SCNGeometry {
        if let hit = cache[key] { return hit }
        let made = make()
        cache[key] = made
        return made
    }

    /// 상자 하나를 부모에 단다(시안 `box` 와 같다 — 모서리 각).
    @discardableResult
    private func box(_ parent: SCNNode, _ size: SIMD3<Float>, _ at: SIMD3<Float>, _ hex: UInt32) -> SCNNode {
        let g = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
        g.materials = [material(hex)]
        let n = SCNNode(geometry: g)
        n.simdPosition = at
        parent.addChildNode(n)
        return n
    }

    /// 여러 상자를 한 지오메트리로 굳힌다.
    private func flattened(_ build: (SCNNode) -> Void) -> SCNGeometry {
        let root = SCNNode()
        build(root)
        return root.flattenedClone().geometry ?? SCNGeometry()
    }

    // MARK: 땅

    private func laneHex(_ kind: CrossyGame.LaneKind, darkRow: Bool) -> UInt32 {
        switch kind {
        case .grass: darkRow ? 0x9AD35B : 0x8FCA50
        case .road: 0x575D6B
        case .river: 0x52BDF2
        case .rail: 0x6E6862
        }
    }

    func slab(_ kind: CrossyGame.LaneKind, darkRow: Bool, outside: Bool) -> SCNGeometry {
        cached("slab.\(kind.rawValue).\(darkRow).\(outside)") {
            let base = laneHex(kind, darkRow: darkRow)
            // 놀이 칸 밖은 같은 색을 22% 어둡게 — 크로시 로드식 경계(시안 그대로).
            let hex = outside ? mix(base, 0x000000, 0.22) : base
            let width = outside ? CGFloat(CrossyScene.groundHalfWidth - 4.5) : 9
            let g = SCNBox(width: width, height: CGFloat(Self.slabDepth), length: 1.0, chamferRadius: 0)
            g.materials = [material(hex)]
            return g
        }
    }

    var roadDashes: SCNGeometry {
        cached("road.dashes") {
            flattened { root in
                var x: Float = -CrossyScene.groundHalfWidth + 0.3
                while x < CrossyScene.groundHalfWidth {
                    box(root, SIMD3(0.5, 0.02, 0.08), SIMD3(x, 0, 0), 0xE6E9EF)
                    x += 1.0
                }
            }
        }
    }

    func riverWaves(variant: Int) -> SCNGeometry {
        cached("river.waves.\(variant)") {
            flattened { root in
                var seed = UInt64(977 &* UInt64(variant + 1) &+ 13)
                var x: Float = -CrossyScene.groundHalfWidth - Self.waveSpacing
                while x < CrossyScene.groundHalfWidth + Self.waveSpacing {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let fx = Float((seed >> 33) % 1000) / 1000, fz = Float((seed >> 20) % 1000) / 1000
                    box(root, SIMD3(0.45, 0.01, 0.06), SIMD3(x + fx * 0.8, 0, -0.3 + fz * 0.6), 0xB5E7FF)
                    x += Self.waveSpacing
                }
            }
        }
    }

    var railTrack: SCNGeometry { railTrack(warning: false) }

    /// 경고 중 레일(빛을 안 받는 붉은 레일 — 그늘에서도 같은 빨강).
    var railTrackWarning: SCNGeometry { railTrack(warning: true) }

    private func railTrack(warning: Bool) -> SCNGeometry {
        cached("rail.track.\(warning)") {
            flattened { root in
                var x: Float = -CrossyScene.groundHalfWidth
                while x <= CrossyScene.groundHalfWidth {
                    box(root, SIMD3(0.20, 0.05, 0.82), SIMD3(x, 0.025, 0), 0x8A6A4C)    // 침목
                    x += 0.5
                }
                for z: Float in [-0.22, 0.22] {
                    let rail = box(root, SIMD3(2 * CrossyScene.groundHalfWidth, 0.06, 0.06), SIMD3(0, 0.08, z),
                                   warning ? 0xFF4A4A : 0xC9CED6)   // 레일
                    if warning { rail.geometry?.firstMaterial?.lightingModel = .constant }
                }
            }
        }
    }

    /// 경계 숲(놀이 칸 밖 양옆 세 칸씩) — 두 갈래를 줄 홀짝으로 번갈아 쓴다.
    func borderForest(variant: Int) -> SCNGeometry {
        cached("border.\(variant)") {
            flattened { root in
                for x in [-7, -6, -5, 5, 6, 7] where (variant + x) & 1 == 0 || abs(x) >= 6 {
                    let height = abs(x) == 6 ? 1.3 : ((variant + abs(x)) % 3 == 0 ? 1.0 : 0.8)
                    // 상자를 루트에 **바로** 단다 — 중간 노드에 자리를 주면 flattenedClone 이 그 자리를 버려 여섯 그루가
                    // x = 0 한 자리에 겹쳤다(첫 증거 PNG 에서 화면 한가운데를 가르는 나무 기둥으로 보였다).
                    buildTree(root, height: Float(height), at: SIMD3(Float(x), 0, 0))
                }
            }
        }
    }

    // MARK: 풀밭 물건

    func propKey(_ prop: CrossyGame.Prop, column: Int, row: Int) -> String {
        switch prop {
        case .tree(let height): "tree.\(min(2, max(0, height)))"
        case .rock: "rock"
        }
    }

    func prop(_ key: String) -> SCNGeometry {
        cached("prop.\(key)") {
            flattened { root in
                switch key {
                case "tree.0": buildTree(root, height: 0.8)
                case "tree.2": buildTree(root, height: 1.3)
                case "rock":
                    box(root, SIMD3(0.62, 0.32, 0.54), SIMD3(0, 0.16, 0), 0xA3A9B3)
                    box(root, SIMD3(0.36, 0.14, 0.34), SIMD3(-0.06, 0.39, 0.02), 0xB9BEC7)
                default: buildTree(root, height: 1.0)
                }
            }
        }
    }

    private func buildTree(_ root: SCNNode, height h: Float, at offset: SIMD3<Float> = .zero) {
        box(root, SIMD3(0.26, 0.30, 0.26), offset + SIMD3(0, 0.15, 0), 0x7A4F2E)
        let fh = 0.55 * h + 0.2
        box(root, SIMD3(0.72, fh, 0.72), offset + SIMD3(0, 0.30 + fh / 2, 0), 0x4CAF50)
        box(root, SIMD3(0.50, 0.22, 0.50), offset + SIMD3(0, 0.30 + fh + 0.11, 0), 0x5CC060)
    }

    // MARK: 차 · 통나무 · 기차

    func vehicleKey(_ mover: CrossyGame.Mover) -> String {
        "\(mover.isTruck ? "truck" : "car").\(((mover.variant % Self.carColors.count) + Self.carColors.count) % Self.carColors.count)"
    }

    /// 차 한 대(앞 = +x). 길이는 규칙 상수 그대로다 — 그리는 길이 = 충돌 길이.
    func vehicle(_ key: String) -> SCNGeometry {
        cached("vehicle.\(key)") {
            let parts = key.split(separator: ".")
            let truck = parts.first == "truck"
            let hex = Self.carColors[Int(parts.last ?? "0") ?? 0]
            return flattened { v in
                if truck {
                    let L = Float(CrossyGame.truckLength)
                    let boxLen = L * 0.66
                    let cabLen = L - boxLen - 0.06
                    for x in [-L / 2 + 0.35, -L / 2 + 0.85, L / 2 - 0.35] {
                        for z: Float in [-0.40, 0.40] { box(v, SIMD3(0.32, 0.32, 0.12), SIMD3(x, 0.16, z), 0x2A2D36) }
                    }
                    box(v, SIMD3(boxLen, 0.86, 0.84), SIMD3(-L / 2 + boxLen / 2, 0.24 + 0.43, 0), 0xF3F4F7)
                    let cabX = L / 2 - cabLen / 2
                    box(v, SIMD3(cabLen, 0.62, 0.80), SIMD3(cabX, 0.24 + 0.31, 0), hex)
                    box(v, SIMD3(cabLen * 0.55, 0.22, 0.82), SIMD3(cabX + 0.04, 0.24 + 0.42, 0), 0x2C3A58)
                    box(v, SIMD3(0.04, 0.24, 0.64), SIMD3(L / 2 + 0.005, 0.24 + 0.42, 0), 0x2C3A58)
                } else {
                    let L = Float(CrossyGame.carLength)
                    for x in [-L * 0.30, L * 0.30] {
                        for z: Float in [-0.40, 0.40] { box(v, SIMD3(0.32, 0.32, 0.12), SIMD3(x, 0.16, z), 0x2A2D36) }
                    }
                    box(v, SIMD3(L, 0.42, 0.80), SIMD3(0, 0.16 + 0.21, 0), hex)
                    box(v, SIMD3(0.82 * L / 1.5, 0.36, 0.70), SIMD3(-0.10, 0.58 + 0.18, 0), 0xF4F6FA)
                    box(v, SIMD3(0.86 * L / 1.5, 0.17, 0.74), SIMD3(-0.10, 0.58 + 0.17, 0), 0x2C3A58)
                }
                let length = Float(truck ? CrossyGame.truckLength : CrossyGame.carLength)
                for z: Float in [-0.26, 0.26] {
                    box(v, SIMD3(0.04, 0.09, 0.16), SIMD3(length / 2 + 0.01, 0.44, z), hex == 0xF2B632 ? 0xFFF2C2 : 0xF2B632)
                    box(v, SIMD3(0.04, 0.08, 0.14), SIMD3(-length / 2 - 0.01, 0.44, z), 0xE0475A)
                }
            }
        }
    }

    func logKey(_ mover: CrossyGame.Mover) -> String {
        "log.\(Int(mover.length.rounded()))"
    }

    func log(_ key: String) -> SCNGeometry {
        cached("mover.\(key)") {
            let len = Float(Int(key.split(separator: ".").last ?? "3") ?? 3)
            return flattened { n in
                box(n, SIMD3(len, 0.34, 0.72), SIMD3(0, -0.25, 0), 0x8F5C36)
                box(n, SIMD3(len - 0.3, 0.02, 0.18), SIMD3(0, -0.07, -0.12), 0xA8703F)
                for s: Float in [-1, 1] { box(n, SIMD3(0.03, 0.30, 0.66), SIMD3(s * (len / 2 + 0.005), -0.25, 0), 0xD39C67) }
            }
        }
    }

    /// 기차(앞 = +x) — 기관차 하나 + 객차 셋, 길이 = 규칙 상수.
    var train: SCNGeometry {
        cached("train") {
            flattened { t in
                let L = Float(CrossyGame.trainLength)
                let carLen: Float = L / 4
                for i in 0..<4 {
                    let cx = -L / 2 + carLen * (Float(i) + 0.5)
                    let engine = i == 3
                    box(t, SIMD3(carLen - 0.12, 0.95, 0.86), SIMD3(cx, 0.22 + 0.475, 0), engine ? 0xE0475A : 0xF3F4F7)
                    box(t, SIMD3(carLen - 0.12, 0.10, 0.88), SIMD3(cx, 0.22 + 0.62, 0), engine ? 0xF3F4F7 : 0x3A7BF0)
                    // 창 띠
                    box(t, SIMD3(carLen - 0.6, 0.20, 0.88), SIMD3(cx, 0.22 + 0.80, 0), 0x2C3A58)
                    for x in [cx - carLen / 2 + 0.5, cx + carLen / 2 - 0.5] {
                        for z: Float in [-0.36, 0.36] { box(t, SIMD3(0.30, 0.26, 0.10), SIMD3(x, 0.13, z), 0x2A2D36) }
                    }
                }
                box(t, SIMD3(0.04, 0.16, 0.5), SIMD3(L / 2 - 0.05, 0.6, 0), 0xFFF2C2)
            }
        }
    }

    var signalPost: SCNGeometry {
        cached("signal.post") {
            flattened { p in
                box(p, SIMD3(0.08, Self.signalHeight, 0.08), SIMD3(0, Self.signalHeight / 2, 0), 0x3A3F4A)
                box(p, SIMD3(0.32, 0.22, 0.12), SIMD3(0, Self.signalHeight, 0), 0x2A2D36)
            }
        }
    }

    /// 경고등(켜짐은 빛을 안 받는 붉은 빛 — 그늘에서도 같은 빨강).
    var lampOn: SCNGeometry {
        cached("lamp.on") {
            let g = SCNBox(width: 0.24, height: 0.14, length: 0.04, chamferRadius: 0)
            g.materials = [material(0xFF4A4A, constant: true)]
            return g
        }
    }

    var lampOff: SCNGeometry {
        cached("lamp.off") {
            let g = SCNBox(width: 0.24, height: 0.14, length: 0.04, chamferRadius: 0)
            g.materials = [material(0x5A2A2A)]
            return g
        }
    }

    // MARK: 아잉이 곁

    /// 발밑 둥근 그림자(가운데 진하고 가장자리로 사라지는 원 — 시안 blobImage).
    var blobPlane: SCNGeometry {
        cached("blob") {
            let plane = SCNPlane(width: 0.86, height: 0.86)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Self.blobImage(alpha: 0.55)
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
            plane.materials = [m]
            return plane
        }
    }

    var splashRing: SCNGeometry {
        cached("splash") {
            let ring = SCNTorus(ringRadius: 0.36, pipeRadius: 0.035)
            ring.materials = [material(0xFFFFFF, constant: true)]
            return ring
        }
    }

    var fallbackAing: SCNGeometry {
        cached("aing.fallback") {
            let s = SCNSphere(radius: CGFloat(CrossyScene.aingHeight / 2))
            s.materials = [material(0xC8B6F2, constant: true)]
            return s
        }
    }

    static func blobImage(alpha: CGFloat) -> CGImage? {
        let n = 128
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: [
                CGColor(colorSpace: space, components: [0, 0, 0, alpha])!,
                CGColor(colorSpace: space, components: [0, 0, 0, alpha * 0.75])!,
                CGColor(colorSpace: space, components: [0, 0, 0, 0])!,
              ] as CFArray, locations: [0, 0.55, 1])
        else { return nil }
        let c = CGPoint(x: n / 2, y: n / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(n) / 2, options: [])
        return ctx.makeImage()
    }
}
