import AppKit
import SceneKit
import Testing
@testable import check

// MARK: - 감은 눈(sleeping) 텍스처 커버 + 3D 감은 선 오버레이 + 드래그 방향 바라보기

// 아잉(aing.usdz)의 UV 는 저폴리라 두 눈이 아틀라스 여러 조각으로 심하게 흩어져 있다. 그래서 감은 눈은
// (1) isEye 전역 검출 + 입(진한 빨강) 보호 + 반복 인페인트로 **눈을 피부로 덮고**(SleepEyeTexture),
// (2) 얼굴 표면에 얹는 얇은 3D 선 노드로 **감은 선**을 그린다(CheckCharacter3DScene.closedEye…).
// 아래 결정적 테스트는 색 분류·커버 면적(변경/덩어리 가드)·씬 구조·엔진 토글·드래그 방향 히스테리시스를 검증한다.

// MARK: 색 분류(실측 색값 기반)

@Test
func sleepEyeColorClassifiersMatchSampledPixels() {
    // 피부(라벤더): 파랑>=빨강>초록의 시원한 밝은 보라.
    #expect(SleepEyeTexture.isSkin(223, 208, 253))
    #expect(SleepEyeTexture.isSkin(231, 218, 252))
    #expect(!SleepEyeTexture.isSkin(253, 253, 255)) // 눈 흰자(중성 흰색)는 피부 아님.
    #expect(!SleepEyeTexture.isSkin(250, 171, 200)) // 볼터치 분홍은 피부 아님.

    // 볼터치 분홍.
    #expect(SleepEyeTexture.isPink(250, 171, 200))
    #expect(!SleepEyeTexture.isPink(223, 208, 253))
    #expect(!SleepEyeTexture.isPink(150, 12, 47)) // 입 진빨강은 어두워 분홍 아님.

    // 눈(iris/흰자/하이라이트/속눈썹) = 피부도 분홍도 아님.
    #expect(SleepEyeTexture.isEye(2, 0, 1))       // 눈동자.
    #expect(SleepEyeTexture.isEye(253, 253, 255)) // 흰자.
    #expect(SleepEyeTexture.isEye(255, 238, 211)) // 하이라이트.
    #expect(!SleepEyeTexture.isEye(223, 208, 253)) // 피부.
    #expect(!SleepEyeTexture.isEye(250, 171, 200)) // 볼터치.

    // 입 진빨강: 초록이 매우 낮은 채도 높은 빨강. 갈색빛 눈동자(초록 68~76)와 볼터치 분홍은 아님.
    #expect(SleepEyeTexture.isMouthRed(150, 12, 47))
    #expect(SleepEyeTexture.isMouthRed(181, 39, 84))
    #expect(!SleepEyeTexture.isMouthRed(135, 73, 67)) // 갈색빛 눈동자 오검출 방지(초록 73).
    #expect(!SleepEyeTexture.isMouthRed(140, 71, 60)) // 눈 테두리 갈색.
    #expect(!SleepEyeTexture.isMouthRed(250, 171, 200)) // 볼터치 분홍.
    #expect(!SleepEyeTexture.isMouthRed(223, 208, 253)) // 피부.
}

// MARK: 형태학 유틸(dilate / largeComponents)

@Test
func dilateMaskGrowsByChebyshevRadius() {
    // 5x5 중앙 1픽셀을 반경 1 팽창 → 3x3 사각형.
    var mask = [Bool](repeating: false, count: 25)
    mask[2 * 5 + 2] = true
    let out = SleepEyeTexture.dilateMask(mask, rw: 5, rh: 5, radius: 1)
    var count = 0
    for y in 0..<5 { for x in 0..<5 where out[y * 5 + x] { count += 1 } }
    #expect(count == 9)
    #expect(out[1 * 5 + 1] && out[3 * 5 + 3] && out[2 * 5 + 2])
    #expect(!out[0])       // 모서리는 반경 밖.
    #expect(!out[4 * 5 + 4])
}

@Test
func largeComponentsDropsSmallBlobs() {
    // 6x6: 왼위 2x2 블록(4px) + 오른아래 단독 1px. minSize 3 → 블록만 남는다.
    let rw = 6, rh = 6
    var mask = [Bool](repeating: false, count: rw * rh)
    for y in 0..<2 { for x in 0..<2 { mask[y * rw + x] = true } }
    mask[5 * rw + 5] = true
    let out = SleepEyeTexture.largeComponents(mask, rw: rw, rh: rh, minSize: 3)
    #expect(out[0] && out[1] && out[rw] && out[rw + 1]) // 4px 블록 유지.
    #expect(!out[5 * rw + 5])                            // 단독 1px 제거.
}

// MARK: 인페인트(피부 소스만 확산 → 어두운 번짐 0)

@Test
func inpaintFillsCoveredDarkSpotWithSurroundingSkin() {
    // 9x9 전부 피부(220,205,250), 중앙 3x3 을 어둡게 두고 cover 로 덮어 인페인트 → 다시 피부색이 되어야 한다.
    let w = 9, h = 9
    let bpr = w * 4
    let data = UnsafeMutablePointer<UInt8>.allocate(capacity: h * bpr)
    defer { data.deallocate() }
    for i in 0..<(w * h) {
        data[i * 4] = 220; data[i * 4 + 1] = 205; data[i * 4 + 2] = 250; data[i * 4 + 3] = 255
    }
    var cover = [Bool](repeating: false, count: w * h)
    for y in 3..<6 { for x in 3..<6 {
        let i = (y * w + x) * 4
        data[i] = 5; data[i + 1] = 2; data[i + 2] = 3 // 어두운 눈동자 흉내.
        cover[y * w + x] = true
    } }
    var buf = SleepEyeTexture.PixelBuffer(data: data, width: w, height: h)
    SleepEyeTexture.inpaint(&buf, cover: cover)
    // 중앙이 어둡지 않고 주변 피부색에 가깝게 채워졌는지.
    let (r, g, b) = buf.rgb(4, 4)
    #expect(r > 180 && g > 170 && b > 210)
    #expect(SleepEyeTexture.isSkin(r, g, b))
}

// MARK: 커버 면적/덩어리 가드 (실제 얼굴 텍스처)

@MainActor
@Test
func closedEyesTextureCoversEyesAndKeepsMouth() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
    let openCG = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
    let closedCG = try #require(CheckCharacter3DScene.makeClosedEyesImage(
        faceImage: openCG, geometry: SleepEyeExplore.faceGeometry(in: scene)))
    #expect(closedCG.width == openCG.width && closedCG.height == openCG.height)

    let open = SleepEyeExplore.rgbaBuffer(openCG)
    let closed = SleepEyeExplore.rgbaBuffer(closedCG)
    let w = openCG.width, h = openCG.height
    let total = w * h

    // (isEye 전체 개수는 화면에 안 보이는 머리카락이 지배하므로, "눈→피부로 바뀐" 변화로 커버를 측정한다.)
    var changed = 0, eyeToSkin = 0, mouthOpen = 0, mouthClosed = 0, mouthChanged = 0
    for i in 0..<total {
        let (r0, g0, b0) = (Int(open[i * 4]), Int(open[i * 4 + 1]), Int(open[i * 4 + 2]))
        let (r1, g1, b1) = (Int(closed[i * 4]), Int(closed[i * 4 + 1]), Int(closed[i * 4 + 2]))
        let didChange = abs(r0 - r1) > 6 || abs(g0 - g1) > 6 || abs(b0 - b1) > 6
        if didChange { changed += 1 }
        if didChange, SleepEyeTexture.isEye(r0, g0, b0), SleepEyeTexture.isSkin(r1, g1, b1) { eyeToSkin += 1 }
        if SleepEyeTexture.isMouthRed(r0, g0, b0) {
            mouthOpen += 1
            if didChange { mouthChanged += 1 }
        }
        if SleepEyeTexture.isMouthRed(r1, g1, b1) { mouthClosed += 1 }
    }

    // 눈이 실제로 피부로 덮였다: '눈→피부' 변화 픽셀이 의미 있는 면적(전체 0.2% 이상)이고, 변경의 유의한 몫이다.
    // (메시 기반 커버는 눈 표면 전체 — 눈두덩/안구 하이라이트 등 원래 '피부'로 분류되던 텍셀까지 — 를 조각별
    //  국소 밝은 피부색으로 평탄화하므로, 변경의 상당수가 '피부→피부'다. 그래서 '눈→피부' 비율은 0.2 이상이면 충분히 유의.)
    #expect(Double(eyeToSkin) > Double(total) * 0.002)
    #expect(Double(eyeToSkin) >= Double(changed) * 0.2)

    // 입(진한 빨강)은 손상 금지: 개수 90%+ 유지 + 입 픽셀 변경은 극소(15% 미만).
    #expect(mouthOpen > 0)
    #expect(Double(mouthClosed) >= Double(mouthOpen) * 0.90)
    #expect(Double(mouthChanged) < Double(mouthOpen) * 0.15)

    // 변경 면적은 국소적(눈 표면)이어야 한다 — 전체의 0.3%~14% 범위(전면 재도색/무작위 변형이 아님).
    // 메시 커버가 눈두덩까지 넉넉히 덮어 색 기반보다 넓지만 여전히 두 눈 자리에 국한된다(≈9.5%).
    let frac = Double(changed) / Double(total)
    #expect(frac > 0.003 && frac < 0.14)
}

// MARK: 국소 링 채움 — 각 커버 조각 내부색이 그 조각 바깥 링(피부)색과 사실상 일치

// 전역 평면 채움은 눈 주변 밝은 얼굴보다 어두워 커버 패치가 진한 보라로 떴다(실물 확인). 국소 링 기반
// 채움으로 각 조각을 '바로 바깥 링의 국소 피부색'에 맞춘다. 이 테스트는 최종 텍스처에서 각 커버 조각
// 내부 평균색 vs 그 조각 링(2~4px, 피부 텍셀) 평균색의 채널별 차이가 ≤ 4/255 임을 고정한다.
@MainActor
@Test
func coverPiecesMatchLocalRingColorWithinTolerance() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
    let openCG = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
    let geo = try #require(SleepEyeExplore.faceGeometry(in: scene))
    let w = openCG.width, h = openCG.height

    // 프로덕션과 동일한 앵커·반경으로 메시 눈 표면 UV 마스크 산출.
    let eyeMask = try #require(SleepEyeTexture.eyeUVCoverMask(
        geometry: geo, anchors: CheckCharacter3DScene.closedEyeAnchors.map { $0.position },
        width: w, height: h, radius: CheckCharacter3DScene.eyeCoverRadius))

    // 원본 버퍼로 커버 마스크(채우기 전 단계) 산출 — 프로덕션 coverEyes 와 같은 경로.
    var openBytes = SleepEyeExplore.rgbaBuffer(openCG)
    let (cover, _, meshBased): ([Bool], [Bool], Bool) = openBytes.withUnsafeMutableBufferPointer { p in
        let buf = SleepEyeTexture.PixelBuffer(data: p.baseAddress!, width: w, height: h)
        return SleepEyeTexture.computeCoverMask(in: buf, eyeMask: eyeMask)
    }
    #expect(meshBased) // 메시 마스크가 실제로 쓰였는지(폴백 아님) 확인.

    // 최종 텍스처(엔진·프로덕션과 동일 경로).
    let closedCG = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: openCG, geometry: geo))
    let closed = SleepEyeExplore.rgbaBuffer(closedCG)
    @inline(__always) func rgb(_ i: Int) -> (Int, Int, Int) {
        (Int(closed[i * 4]), Int(closed[i * 4 + 1]), Int(closed[i * 4 + 2]))
    }

    let comps = SleepEyeTexture.connectedComponents(cover, rw: w, rh: h)
    #expect(comps.count >= 2) // 최소 두 눈 조각.

    // 프로덕션 채움과 동일한 '진짜 밝은 피부' 임계 루마 — 링에서 어두운 눈두덩/속눈썹 텍셀(isSkin 은 통과하나
    // 실제 피부보다 어두움)을 배제해, 판정 기준(링색)이 진짜 얼굴 피부가 되게 한다. 원본 버퍼로 산출.
    let ringR = 3
    let brightThreshold: Int = openBytes.withUnsafeMutableBufferPointer { p in
        let buf = SleepEyeTexture.PixelBuffer(data: p.baseAddress!, width: w, height: h)
        return SleepEyeTexture.eyeRegionBrightSkin(in: buf, cover: cover, ringRadius: ringR).threshold
    }
    #expect(brightThreshold > 120) // 임계가 isSkin 하한(120)보다 위 — 어두운 텍셀을 실제로 걸러낸다.

    var testedPieces = 0
    for members in comps {
        // 육안에 유의미한 조각만 판정(수 px 잡티는 페더 잔여로 노이즈가 크다). 최소 30px.
        guard members.count >= 30 else { continue }
        // 내부 평균(최종 텍스처).
        var ir = 0, ig = 0, ib = 0
        for p in members { let (r, g, b) = rgb(p); ir += r; ig += g; ib += b }
        let ic = members.count
        let iar = Double(ir) / Double(ic), iag = Double(ig) / Double(ic), iab = Double(ib) / Double(ic)
        // 링 평균(조각 바로 바깥 2~4px, 커버 아님 & **밝은 피부** 텍셀만) — 최종 텍스처.
        var seen = Set<Int>()
        var rr = 0, rg = 0, rb = 0, rcnt = 0
        for p in members {
            let px = p % w, py = p / w
            for dy in -ringR...ringR {
                let ny = py + dy; if ny < 0 || ny >= h { continue }
                for dx in -ringR...ringR {
                    let nx = px + dx; if nx < 0 || nx >= w { continue }
                    let q = ny * w + nx
                    if cover[q] || seen.contains(q) { continue }
                    let (r, g, b) = rgb(q)
                    if SleepEyeTexture.isSkin(r, g, b) && SleepEyeTexture.luma(r, g, b) >= brightThreshold {
                        seen.insert(q); rr += r; rg += g; rb += b; rcnt += 1
                    }
                }
            }
        }
        guard rcnt > 0 else { continue } // 링에 밝은 피부 없는 조각은 전역 폴백 — 링 기준 판정 대상 아님.
        let rar = Double(rr) / Double(rcnt), rag = Double(rg) / Double(rcnt), rab = Double(rb) / Double(rcnt)
        let dr = abs(iar - rar), dg = abs(iag - rag), db = abs(iab - rab)
        // 진단 출력(필터 실행 시 로그에 보임): 조각크기 / 내부색 / 링색 / 채널차.
        print(String(format: "piece n=%d interior=(%.1f,%.1f,%.1f) ring=(%.1f,%.1f,%.1f) diff=(%.2f,%.2f,%.2f)",
                     members.count, iar, iag, iab, rar, rag, rab, dr, dg, db))
        #expect(dr <= 4.0 && dg <= 4.0 && db <= 4.0)
        testedPieces += 1
    }
    #expect(testedPieces >= 2) // 두 눈 조각은 반드시 판정됐다.
}

// MARK: 씬 구조 (facing 노드 삽입 + 감은 눈 선 노드)

@MainActor
@Test
func sceneInsertsFacingNodeBetweenWrapperAndCharacter() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    // wrapper 의 직속 자식은 facing 노드(그 안에 idle 캐릭터).
    let facing = try #require(
        wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false)
    )
    #expect(!facing.childNodes.isEmpty) // facing 안에 캐릭터.
    // 리액션 resetPose 가 건드리는 wrapper 와, facing 은 서로 다른 노드여야 간섭이 없다.
    #expect(facing !== wrapper)
}

@MainActor
@Test
func sceneAddsHiddenClosedEyeNodes() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let left = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)
    )
    let right = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeRightName, recursively: true)
    )
    // 기본은 숨김(평상시 뜬 눈). sleeping 시 엔진이 켠다.
    #expect(left.isHidden)
    #expect(right.isHidden)
    // 얼굴 표면 앞(대략 좌우 대칭, 위쪽)에 놓였는지 개략 검증.
    #expect(left.position.x < 0 && right.position.x > 0)
    #expect(left.position.y > 0 && right.position.y > 0)

    // 감은 선은 눈 앵커(뜬 눈 세로 중앙)에서 `closedEyeLowering` 만큼 아래(-y)로 내려앉는다 — 눈꺼풀이
    // 하단 경계로 내려온 자연스러운 모습. 실제 배치 y 가 앵커 y 보다 정확히 그만큼 낮은지 검증한다.
    let lowering = CheckCharacter3DScene.closedEyeLowering
    #expect(lowering > 0) // 반드시 아래로 내려야 한다(눈 중앙에 뜨지 않게).
    let anchors = Dictionary(uniqueKeysWithValues:
        CheckCharacter3DScene.closedEyeAnchors.map { ($0.name, $0.position) })
    let leftAnchorY = try #require(anchors[CheckCharacter3DScene.closedEyeLeftName]).y
    let rightAnchorY = try #require(anchors[CheckCharacter3DScene.closedEyeRightName]).y
    #expect(abs(left.position.y - (leftAnchorY - lowering)) < 1e-4)
    #expect(abs(right.position.y - (rightAnchorY - lowering)) < 1e-4)
    // 내려앉은 뒤에도 여전히 앵커보다 낮아야 한다(중앙→하단 이동 방향 고정).
    #expect(left.position.y < leftAnchorY && right.position.y < rightAnchorY)
}

// MARK: 엔진 — sleeping 진입/이탈 시 감은 눈 텍스처·선 토글

@MainActor
@Test
func reactionEngineTogglesClosedEyesOnSleepAndWake() throws {
    var now = Date(timeIntervalSince1970: 70_000)
    let engine = ReactionEngine(clock: { now })
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
    // 오른눈 아틀라스 픽셀(512 기준). 평상시엔 눈(어두움), 감은 눈 텍스처에선 피부로 덮인다.
    let eyeX = 235, eyeY = 392
    let awakeEye = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
    #expect(SleepEyeTexture.isEye(awakeEye.0, awakeEye.1, awakeEye.2))
    engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)

    let left = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)
    )
    #expect(left.isHidden) // 평상시 숨김.

    // 졸기 진입 → 감은 선 표시 + 얼굴 디퓨즈가 감은 눈 버전(눈 자리가 피부)으로 교체.
    engine.request(.drowsy)
    #expect(engine.state == .sleeping)
    #expect(!left.isHidden)
    let sleepEye = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
    #expect(SleepEyeTexture.isSkin(sleepEye.0, sleepEye.1, sleepEye.2))

    // 클릭으로 깨우기 → 원복(선 숨김 + 눈 자리 다시 눈).
    engine.request(.wake)
    #expect(left.isHidden)
    let wokenEye = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
    #expect(SleepEyeTexture.isEye(wokenEye.0, wokenEye.1, wokenEye.2))
}

// MARK: 엔진 — setDragFacing (== 가드)

@MainActor
@Test
func reactionEngineSetDragFacingGuardsSameDirection() {
    let engine = ReactionEngine()
    #expect(engine.currentDragFacing == 0)

    engine.setDragFacing(1)
    #expect(engine.currentDragFacing == 1)
    // 같은 방향 재호출은 no-op(상태 유지).
    engine.setDragFacing(1)
    #expect(engine.currentDragFacing == 1)

    engine.setDragFacing(-1)
    #expect(engine.currentDragFacing == -1)

    engine.setDragFacing(0)
    #expect(engine.currentDragFacing == 0)

    // 부호만 본다(±1 로 정규화).
    engine.setDragFacing(5)
    #expect(engine.currentDragFacing == 1)
}

// MARK: 드래그 방향 히스테리시스(순수 로직)

@Test
func dragFacingHysteresisNeedsThresholdAndResistsJitter() {
    var h = DragFacingHysteresis()
    // 첫 update 는 기준점만 잡고 정면 유지.
    #expect(h.update(x: 100) == 0)
    // 임계(3pt) 미만 미세 이동은 방향 변화 없음.
    #expect(h.update(x: 102) == 0)
    #expect(h.update(x: 101) == 0)
    // 오른쪽으로 임계 초과 → +1.
    #expect(h.update(x: 106) == 1)
    // 계속 오른쪽 → +1 유지.
    #expect(h.update(x: 110) == 1)
    // 반전: 직전 판정 지점(110)에서 임계 미만 왼쪽은 아직 +1.
    #expect(h.update(x: 108) == 1)
    // 임계 초과 왼쪽 → -1.
    #expect(h.update(x: 104) == -1)
    // 리셋 → 정면 + 기준점 초기화.
    h.reset()
    #expect(h.direction == 0)
    #expect(h.update(x: 500) == 0) // 리셋 후 첫 update 는 기준점만.
}

// MARK: - 렌더 덤프(육안 검증 루프). CHECK_SLEEP_RENDER_DIR 지정 시에만 기록.

@MainActor
@Test
func dumpSleepEyeRenders() throws {
    guard let dir = ProcessInfo.processInfo.environment["CHECK_SLEEP_RENDER_DIR"] else { return }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let device = try #require(MTLCreateSystemDefaultDevice())

    // 평상시(뜬 눈).
    let openScene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    try renderScene(openScene, device: device, to: base.appendingPathComponent("sleep-eyes-open-v2.png"))

    // 드래그 방향 바라보기: facing y±40°.
    if let facing = openScene.rootNode.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: true) {
        facing.eulerAngles = SCNVector3(0, ReactionEngine.dragFacingAngle, 0)
        try renderScene(openScene, device: device, to: base.appendingPathComponent("facing-plus.png"))
        facing.eulerAngles = SCNVector3(0, -ReactionEngine.dragFacingAngle, 0)
        try renderScene(openScene, device: device, to: base.appendingPathComponent("facing-minus.png"))
        facing.eulerAngles = SCNVector3(0, 0, 0)
    }

    // sleeping(감은 눈): 얼굴 디퓨즈를 감은 눈 텍스처로 교체 + 감은 선 노드 표시.
    let sleepScene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let material = try #require(SleepEyeExplore.faceMaterial(in: sleepScene))
    let openCG = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
    // 감은 눈 텍스처는 엔진·프로덕션과 동일 경로(메시 기반 눈 표면 UV 마스크로 눈두덩/안구 하이라이트까지 커버).
    let closedCG = try #require(CheckCharacter3DScene.makeClosedEyesImage(
        faceImage: openCG, geometry: SleepEyeExplore.faceGeometry(in: sleepScene)))
    material.diffuse.contents = closedCG
    // 커버 품질 판정용: 감은 선을 숨긴 채(선이 흔적을 가리지 않도록) 정면 렌더 — 눈 자리가 주변 피부와
    // 구분되지 않아야 합격(유령 눈두덩/링 금지).
    try renderScene(sleepScene, device: device, to: base.appendingPathComponent("sleep-eyes-cover-only.png"))
    sleepScene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)?.isHidden = false
    sleepScene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeRightName, recursively: true)?.isHidden = false
    try renderScene(sleepScene, device: device, to: base.appendingPathComponent("sleep-eyes-closed-v2.png"))

    // 실제 sleeping 자세(앞으로 숙임)에서도 감은 선이 눈에 붙어 따라오는지.
    if let wrapper = sleepScene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false) {
        wrapper.eulerAngles = SCNVector3(ReactionActions.radians(14), 0, 0)
        wrapper.position = SCNVector3(0, -0.18 * 0.33, 0)
        try renderScene(sleepScene, device: device, to: base.appendingPathComponent("sleep-eyes-drowsy-pose.png"))
    }
    #expect(true)
}

@MainActor
private func renderScene(_ scene: SCNScene, device: MTLDevice, to url: URL,
                         size: CGSize = CGSize(width: 280, height: 340)) throws {
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.autoenablesDefaultLighting = false
    let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: url)
}

// MARK: - 테스트 보조

enum SleepEyeExplore {
    /// 씬에서 얼굴(큰 CGImage 디퓨즈) 재질을 찾는다.
    static func faceMaterial(in scene: SCNScene) -> SCNMaterial? {
        var found: SCNMaterial?
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { m in
                if found == nil, let cg = cgImage(from: m.diffuse.contents), cg.width >= 256 { found = m }
            }
        }
        return found
    }

    /// 얼굴 재질을 소유한 지오메트리(메시 기반 눈 커버 마스크 산출용).
    static func faceGeometry(in scene: SCNScene) -> SCNGeometry? {
        var found: SCNGeometry?
        scene.rootNode.enumerateHierarchy { node, stop in
            guard let geo = node.geometry else { return }
            if geo.materials.contains(where: { (cgImage(from: $0.diffuse.contents)?.width ?? 0) >= 256 }) {
                found = geo; stop.pointee = true
            }
        }
        return found
    }

    static func cgImage(from contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            return (contents as! CGImage)
        } else if let image = contents as? NSImage {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if let url = contents as? URL {
            return decodeArchiveURL(url)
        } else if let path = contents as? String {
            return NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return nil
    }

    /// usdz 아카이브 참조 URL(...usdz?offset=N&size=M)을 원본 해상도로 디코드.
    static func decodeArchiveURL(_ url: URL) -> CGImage? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let offset = items.first(where: { $0.name == "offset" })?.value.flatMap(Int.init),
              let size = items.first(where: { $0.name == "size" })?.value.flatMap(Int.init) else {
            return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        var fileComponents = components
        fileComponents.queryItems = nil
        guard let fileURL = fileComponents.url,
              let handle = try? FileHandle(forReadingFrom: fileURL),
              (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.read(upToCount: size) else {
            return nil
        }
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// CGImage 를 RGBA8(premultipliedLast) 바이트 배열로.
    static func rgbaBuffer(_ cg: CGImage) -> [UInt8] {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return px
    }

    /// 재질의 현재 디퓨즈 CGImage 에서 (x,y) 픽셀 RGB 를 읽는다(감은 눈 텍스처 교체/원복 검증용).
    static func diffusePixel(_ material: SCNMaterial, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        guard let cg = cgImage(from: material.diffuse.contents) else { return (0, 0, 0) }
        let buf = rgbaBuffer(cg)
        let i = (y * cg.width + x) * 4
        guard i + 2 < buf.count else { return (0, 0, 0) }
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
    }
}
