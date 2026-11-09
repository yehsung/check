import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 빼빼로 아잉이 3D 마감 (v0.3.77 — 빼빼로 데이 11-11 기간 선물 전용, 시안 P '상자에서 빼꼼')
//
// 빼빼로 아잉이는 아잉과 **같은 메시**(aing.scn) · **같은 몸 재질**이다(대표 결정 — 몸은 원래 아잉이 그대로, 장식만 붙인다). 마감은 둘뿐이다
// (그림 생성기 `scripts/make-pepero-aing.swift` 머리말 '앱이 할 일' 1–6):
//
//  ① 장식 — `PeperoDecor.make(sheet:)` 가 만든 `check.peperoDecor` 노드 하나(빨간 상자 `check.pepero.box` + 굵은 빼빼로 셋
//     `check.pepero.stick{L,R1,R2}`)를 **몸 메시 노드**(aing.scn 은 캐릭터 노드가 곧 메시 노드 — 변환이 단위라 물체 좌표 = 이 노드 좌표)의
//     자식으로 붙인다 → 부유 · 살랑 · 요 회전 · 반응 배율을 그대로 따른다. 자리는 고정 상수라 몸 hitTest 가 없다. 재질은 .constant(음영을
//     텍스처에 구웠다). 상자 바깥 벽의 인쇄는 **인쇄 판 한 장**(`aing_pepero-box.png` 1024² — `PeperoArt` 저장소: 디스크 캐시 → 번들 폴백)에서
//     굽는다. **아래 '생성기 사본' 구획은 생성기의 BEGIN/END pepero-decor 구획 글자 그대로다** — `V0377PeperoMac3DTests` 가 두 파일의 그 구획을
//     주석 · 공백을 걷어 맞댄다(생성기를 고치면 여기도 같이 — 안 그러면 빨갛다). 생성기는 `swift <파일 하나>` 로 도는 스크립트라 앱 모듈을
//     링크할 수 없고 앱은 스크립트를 못 읽으므로, 한 곳에 두는 길이 없어 이슬 `IsulCap` 과 같은 '두 벌 + 글자 맞대기 시험'으로 묶는다.
//  ② 표식 — 캐릭터 노드에 빈 노드 `markerName` 을 단다(엔진 `currentCharacterID` 가 아잉 · 이슬 · 케이크와 가른다 — 같은 메시라 종류로 못 가른다).
//
// ★ 굽기는 비싸다(상자 2048×768 텍스처 · 220×140 메시 + 막대 셋 256×1024 — 생성기 -O 실측 한 벌 0.73초). 그래서 **프로세스당 한 번** 만들고
//   씬마다 `clone()` 을 붙인다(지오메트리 · 재질을 나눠 쓴다). 원본은 **판 객체**에 묶인다 — 그림 저장소가 새 판을 받으면(`PeperoArt.absorb`)
//   판 객체가 바뀌어 다음 조회가 다시 굽는다(구울 사람이면 받은 쪽이 메인 밖에서 미리 굽는다). 시작 뒤 미리 굽기는 케이크 · 이슬과 같은 때
//   (시작 + 5초 · 메인 밖)지만 **입었거나 가진 사람만**이다(조정자 결정 11-04 — `PeperoPrewarmGate`: 13MB 를 모든 사람에게 굽지 않는다. 상점 상태가
//   늦게 와 가진 것이 확인되거나 선물을 받으면 그때 한 번). **메인은 굽지 않는다**(검토 수리 — `apply` ★): 원본이 아직 없으면 상자 없이 세우고
//   메인 밖에서 구워 붙인다(시작 5초 안에 오버레이가 서도 · 안 가진 사람이 남의 울트라로 처음 빼빼로를 맞아도 메인이 0.73초 멎지 않는다).
// ★ 장식은 몸이 아니다: 얼굴 재질 탐색(상자 텍스처 2048×768 · 막대 256×1024 는 '큰 CGImage 디퓨즈' 조건을 만족한다) · 몸 클릭 hitTest ·
//   리액션 진폭 · 클릭 프리체크 상자는 케이크 · 이슬과 **같은 자리**에서 `AingDecor`(장식 루트 이름 셋)로 뺀다.
// ★ 반응 배율(찌부 · 늘이기)은 리액션 wrapper(`CheckCharacter3DScene.reactionWrapperName`)에 걸린다(`ReactionEngine.runReaction` — `reactionNode`).
//   장식은 그 아래(wrapper → facing → 캐릭터 = 몸 메시 → 장식)라 몸과 **같은 변환**으로 찌그러진다 — 팔과 팔 구멍의 상대 자리가 그대로다
//   (생성기 메모 5 끝 줄의 확인 — `V0377PeperoMac3DTests.squashMovesTheDecorWithTheBody`). 몸 메시에만 거는 반응은 없다.
// ★ 팔 끝이 3/4 에서 상자 아래 선 밖으로 나오는 형상 문제는 **(가) 지금 그대로**다(정면 · 초상 기준 — 대표가 고른 시안 P 의 비례를 지킨다).
// ★ 프레이밍: 케이크처럼 내려 세우지 않는다. 장식 꼭대기(`PeperoDecor.topY` 1.0951 — 막대 끝)는 초코 불꽃(1.1839)보다 낮아 지금 앱 카메라
//   (몸만 보고 잡은 40°)로 부유 꼭대기(+0.07)에서도 위 여백이 남는다(생성기 실측 부유 0 → 0.065 · +0.07 → 0.044). 시험이 앱 경로 렌더로 다시 잰다.
// ★ 울트라 격발(945²)만은 기본 자세가 맞지 않는다(검토 수리): x −12° 끝은 밑에서 보는 구도라 상자 바닥 밑으로 몸이 보이고, z +34° · 올라간 끝은
//   막대가 프레임 위로 잘린다 — 엔진이 빼빼로에 `ReactionActions.UltraRagePose.pepero`(x 기울기 없음 · z 28° · 내내 extent × 0.11 내림)를 고른다.
// ★ 근무 시계 캡슐은 상자 아래로 내린다(`CheckOverlayCharacterView.peperoTimerVerticalFraction` — 0.49 는 상자 로고 자리다).
// ★ 감은 눈 · 울트라 교체: 몸 재질을 안 건드리므로 기본 아잉 갈래 그대로 돈다(감은 눈은 라벤더 원본에서 굽는다 — 무지개 갈래를 안 탄다).

// ── 생성기 사본 시작 ─────────────────────────────────────────────────────────────────────────────────────────────────
// 아래 구획(장식 `PeperoDecor`)은 `scripts/make-pepero-aing.swift` 의 BEGIN/END pepero-decor 구획을 **글자 그대로** 옮겼다.
// 고치지 마라 — 생성기를 고치고 다시 옮겨라(`V0377PeperoMac3DTests.generatorRegionIsVerbatim`).
// BEGIN pepero-decor — 다음 단계(맥 3D 마감)가 이 구획을 글자 그대로 옮긴다(이슬 IsulCap 과 같은 길). 여기를 고치면 앱도 같이.

/// 빼빼로 상자 + 굵은 빼빼로 셋(시안 P '상자에서 빼꼼'). 전부 캐릭터 노드(= aing.scn 메시 노드, 변환 단위 — 물체 좌표, +z 앞 · +y 위) 기준 고정 자리.
/// 매개 곡면 → SCNGeometry + 음영을 구운 텍스처(몸 공간 고정 빛), unlit. 상자 바깥 벽의 인쇄는 인쇄 판(aing_pepero-box.png)에서 읽는다.
enum PeperoDecor {
    static let decorNodeName = "check.peperoDecor"
    static let boxNodeName = "check.pepero.box"

    // MARK: 상자 — 위가 열린 둥근 모서리 상자(직육면체의 민코프스키 둥글림)
    /// 가로 ±a(x) · 깊이 ±b(z, +z = 앞면) · 높이 y0…y1(위 테 꼭대기) · 모서리 반지름 r · 벽 두께 wall. 몸(aing.scn)은 y −0.847…0.849 ·
    /// 깊이 ±0.73 · 팔 포함 가로 ±0.962 — 상자 위 테(0.03)부터 위가 얼굴이다. 바닥은 몸 아래 끝보다 0.23 높다(앱 카메라는 위에서 내려다봐
    /// 앞 벽이 가린다 — 아래에서 보는 구도가 생기면 몸이 바닥을 뚫고 보인다).
    static let a: Float = 0.84
    static let b: Float = 0.765
    static let y0: Float = -0.62
    static let y1: Float = 0.03
    static let r: Float = 0.10
    static let wall: Float = 0.034
    /// 굽기 텍스처의 둘레(u) 해상도를 앞면에 몰아 준다(둘레 길이 가중 — 앞 3.2 : 뒤 1.4 : 옆 1.0 : 모서리 2.5).
    static let frontWeight: Float = 3.2
    static let backWeight: Float = 1.4
    static let sideWeight: Float = 1.0
    static let cornerWeight: Float = 2.5
    static let bakeWidth = 2048
    static let bakeHeight = 768
    static let meshU = 220
    static let meshV = 140

    // MARK: 인쇄 판 규약(aing_pepero-box.png)
    /// 판은 sheetWidth × sheetHeight 불투명 그림. 위(행 0)부터 앞면 · 뒷면 · 옆면 띠, 띠 사이 16줄은 이웃 띠 끝 줄을 되풀이한 여백.
    /// 앞 · 뒤 띠의 가로세로 비(1024 : 396 = 2.586)는 상자 앞면 2a : (y1 − y0) = 1.68 : 0.65 와 같다. 옆 띠(1024 : 200)는 옆면(1.53 : 0.65)보다
    /// 가로로 2.2배 늘어난 자리라 글자를 넣지 않는다(가로 띠 무늬만).
    static let sheetWidth = 1024
    static let sheetHeight = 1024
    static let frontRows = 0..<396
    static let backRows = 412..<808
    static let sideRows = 824..<1024

    enum Face { case front, back, side }

    /// 바깥 벽 점(상자 자기 좌표 = 물체 좌표) → (면, s, t). s = 그 면을 **바깥에서 볼 때** 왼 0 → 오른 1, t = 위 테 y1 에서 0 → 바닥 y0 에서 1.
    /// 면 고르기: 둥근 모서리에서는 앞 · 뒤 평면과 옆 평면 중 더 가까운 쪽(dz ≥ dx 면 앞 · 뒤). 앞 · 뒤 s 는 x 를 ±a 전체로, 옆 s 는 z 를 ±b 전체로 편다.
    static func printCoord(_ p: SIMD3<Float>) -> (face: Face, s: Double, t: Double) {
        let t = Double((y1 - p.y) / (y1 - y0))
        let dz = abs(p.z) - (b - r), dx = abs(p.x) - (a - r)
        if dz >= dx {
            let s = Double((p.x + a) / (2 * a))
            return p.z >= 0 ? (.front, s, t) : (.back, 1 - s, t)
        }
        let s = Double((p.z + b) / (2 * b))
        return (.side, p.x > 0 ? 1 - s : s, t)
    }

    /// (면, s, t) → 판 화소 좌표(가로 0…sheetWidth, 세로 0…sheetHeight, 위가 0). 띠 안 반 화소로 묶는다(여백까지 안 나간다).
    static func sheetPixel(_ face: Face, _ s: Double, _ t: Double) -> (x: Double, y: Double) {
        let rows: Range<Int>
        switch face {
        case .front: rows = frontRows
        case .back: rows = backRows
        case .side: rows = sideRows
        }
        let x = min(max(s, 0), 1) * Double(sheetWidth)
        let y = Double(rows.lowerBound) + min(max(t, 0), 1) * Double(rows.count)
        return (min(max(x, 0.5), Double(sheetWidth) - 0.5), min(max(y, Double(rows.lowerBound) + 0.5), Double(rows.upperBound) - 0.5))
    }

    // MARK: 팔 구멍(옆면 ±x — 몸 팔이 벽을 뚫고 나오는 자리)
    /// 옆 벽 위 (y, z) 타원: 가운데 (holeY, holeZ) · 반지름 (holeHY, holeHZ). 바깥 벽(|x| = a)에서 팔 단면은 y −0.616…−0.055 · z −0.161…0.126
    /// — 그것을 담는 가장 작은 타원(꼭대기 −0.035 는 위 노랑 띠 아래). 생성기가 메시로 다시 재서 단면 전체가 반지름 비 holeFit 안에 드는지 맞댄다.
    static let holeY: Float = -0.336
    static let holeZ: Float = -0.016
    static let holeHY: Float = 0.301
    static let holeHZ: Float = 0.178
    static let holeFit: Float = 0.955

    // MARK: 색(sRGB 16진)
    static let red = 0xD7182A
    static let redDeep = 0x9E0E1C
    static let board = 0xEFE6D6
    static let boardDeep = 0x8C7F6E
    static let holeInk = 0x1E0A08
    static let cutEdge = 0xB08A62

    // MARK: 막대 — 상자 안 바닥 가까이에서 솟아 머리 옆으로(왼쪽 하나, 오른쪽 둘). 코팅(밀크 초코) 끝이 상자 테 위로 보인다.
    struct Stick {
        let name: String
        let base: SIMD3<Float>      // 아래 끝(물체 좌표)
        let dir: SIMD3<Float>       // 축 방향(정규화 전)
        let length: Float
        let spin: Float             // 자기 축 돌림(라디안 — 코팅 끝 물결 자리)
    }
    static let sticks: [Stick] = [
        Stick(name: "check.pepero.stickL", base: SIMD3(-0.60, -0.50, -0.50), dir: SIMD3(-0.11, 1, -0.02), length: 1.56, spin: 0.0),
        Stick(name: "check.pepero.stickR1", base: SIMD3(0.62, -0.50, -0.48), dir: SIMD3(0.10, 1, -0.02), length: 1.60, spin: 1.1),
        Stick(name: "check.pepero.stickR2", base: SIMD3(0.36, -0.50, -0.64), dir: SIMD3(0.03, 1, -0.06), length: 1.50, spin: 2.3),
    ]
    static let stickRadius: Float = 0.058       // 비스킷 심
    static let stickCoatThick: Float = 0.024    // 코팅 두께(코팅 반지름 0.082)
    static let stickCoatFrac: Float = 0.76      // 아래 끝부터 코팅이 덮는 비율(나머지 = 비스킷 손잡이)
    static let stickWave: Float = 0.014         // 코팅 끝 물결 높이
    static let coatBase = 0x7A4423
    static let coatDeep = 0x3B1B0B
    static let coatHi = 0xFFE4CC
    static let biscuit = 0xE7AE62
    static let biscuitDeep = 0xC48543
    static let biscuitEnd = 0xF0C98E
    /// 장식 꼭대기(물체 좌표 y) — 앱 프레이밍이 쓴다. 생성기가 실행 때 다시 재서 맞댄다.
    static let topY: Float = 1.0951

    // MARK: 구운 조명
    /// ambient(바탕 밝기) · spec(반짝 세기) · gloss(날카로움) · wrap(감싸는 빛) · rim(가장자리 밝은 테) · axis(원기둥 축 — 길이 방향 곧은 반짝) · tint(반짝 색).
    struct Look {
        var ambient = 0.62, spec = 0.25, gloss = 24.0, wrap = 0.4, rim = 0.0
        var axis: SIMD3<Double>? = nil
        var tint = SIMD3<Double>(1, 1, 1)
    }
    static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
    static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))
    static let fillLight = simd_normalize(SIMD3<Double>(0.70, 0.25, 0.65))
    static let paper = Look(ambient: 0.60, spec: 0.34, gloss: 34, wrap: 0.40, rim: 0.12, tint: SIMD3(1, 0.95, 0.92))
    static let cardboard = Look(ambient: 0.78, spec: 0.04, gloss: 8, wrap: 0.6, rim: 0.0)

    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func lin(_ hex: Int) -> SIMD3<Double> {
        SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255))
    }
    static func srgbByte(_ v: Double) -> UInt8 {
        let c = min(max(v, 0), 1)
        let e = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (e * 255).rounded())))
    }
    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
    static func smoothF(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
    /// 결정적 해시(0…1) — 비스킷 고운 점.
    static func hash2(_ p: Int, _ q: Int, _ salt: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(p &* 73_856_093 ^ q &* 19_349_663 ^ salt &* 83_492_791))
        h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33; h = h &* 0xc4ceb9fe1a85ec53; h ^= h >> 33
        return Double(h % 1_000_003) / 1_000_003
    }

    static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
        let ndl = simd_dot(n, keyLight)
        let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
        let ao = 1 - 0.22 * max(-n.y, 0)
        var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
        func flat(_ v: SIMD3<Double>) -> SIMD3<Double> {
            guard let ax = look.axis else { return v }
            let p = v - ax * simd_dot(v, ax)
            return simd_length(p) < 1e-6 ? v : simd_normalize(p)
        }
        c += look.tint * (pow(max(simd_dot(n, flat(simd_normalize(keyLight + viewLight))), 0), look.gloss) * look.spec)
        c += look.tint * (pow(max(simd_dot(n, flat(simd_normalize(fillLight + viewLight))), 0), look.gloss * 1.4) * look.spec * 0.35)
        if look.rim > 0 { c += (albedo * 1.8 + look.tint * 0.15) * (pow(1 - max(simd_dot(n, viewLight), 0), 3) * look.rim) }
        return simd_clamp(c, .zero, SIMD3(repeating: 1))
    }

    typealias SurfaceFn = (Float, Float) -> SIMD3<Float>

    static func surfaceNormal(_ pos: SurfaceFn, _ u: Float, _ v: Float, closedU: Bool) -> SIMD3<Float> {
        func at(_ vv: Float) -> SIMD3<Float> {
            let e: Float = 1e-3
            let u0 = closedU ? u - e : max(u - e, 0), u1 = closedU ? u + e : min(u + e, 1)
            let v0 = max(vv - e, 0), v1 = min(vv + e, 1)
            return simd_cross(pos(u1, vv) - pos(u0, vv), pos(u, v1) - pos(u, v0))
        }
        var n = at(v)
        var nudge: Float = 0.004
        while simd_length(n) < 1e-9 && nudge < 0.1 { n = at(v < 0.5 ? v + nudge : v - nudge); nudge *= 2 }
        return simd_length(n) < 1e-12 ? SIMD3(0, 1, 0) : simd_normalize(n)
    }

    /// 매개 곡면 노드: 격자 nu × nv 메시 + texW × texH 구운 텍스처(텍셀마다 albedo 2×2 표본 평균 → 그 자리 법선 · look 으로 조명).
    static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: SurfaceFn,
                          albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, lookAt: (Double, Double, SIMD3<Float>) -> Look,
                          transform: simd_float4x4) -> SCNNode {
        let rot = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
        var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint]()
        for j in 0...nv { for i in 0...nu {
            let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
            let p = pos(u, v), n = surfaceNormal(pos, u, v, closedU: closedU)
            verts.append(SCNVector3(p.x, p.y, p.z)); norms.append(SCNVector3(n.x, n.y, n.z)); uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
        } }
        var idx = [UInt32]()
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) { for i in 0..<UInt32(nu) {
            let p = j * row + i, q = p + 1, s = p + row, t = s + 1
            idx += [p, q, s, q, t, s]
        } }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        var px = [UInt8](repeating: 255, count: texW * texH * 4)
        for y in 0..<texH { for x in 0..<texW {
            var acc = SIMD3<Double>(0, 0, 0)
            for sy in 0..<2 { for sx in 0..<2 {
                let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(texW), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(texH)
                acc += albedo(u, v, pos(Float(u), Float(v)))
            } }
            let uD = (Double(x) + 0.5) / Double(texW), vD = (Double(y) + 0.5) / Double(texH)
            let nw = rot * surfaceNormal(pos, Float(uD), Float(vD), closedU: closedU)
            let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), lookAt(uD, vD, pos(Float(uD), Float(vD))))
            let o = (y * texW + x) * 4
            px[o] = srgbByte(c.x); px[o + 1] = srgbByte(c.y); px[o + 2] = srgbByte(c.z)
        } }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &px, width: texW, height: texH, bitsPerComponent: 8, bytesPerRow: texW * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = ctx.makeImage()!
        material.diffuse.wrapS = closedU ? .repeat : .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.simdTransform = transform
        return node
    }

    // MARK: 상자 곡면
    enum Region { case outer, bottom, lip, inner, innerBottom }

    /// 둘레(u: 앞 가운데 → 오른쪽 → 뒤 → 왼쪽 → 앞 가운데) × 단면(v: 바닥 가운데 → 아래 둥근 모서리 → 바깥 벽 → 위 테(반원 입술) → 안쪽 벽 → 안쪽 바닥 가운데).
    struct Surface {
        let segs: [(len: Float, p0: SIMD2<Float>, p1: SIMD2<Float>, ang0: Float, ang1: Float)]
        let total: Float
        static let vCuts: [Float] = [0.05, 0.10, 0.62, 0.70, 0.94, 1.0]
        static let regions: [Region] = [.bottom, .outer, .outer, .lip, .inner, .innerBottom]
        init() {
            let ca = a - r, cb = b - r, ql = Float.pi / 2 * r
            var list: [(Float, SIMD2<Float>, SIMD2<Float>, Float, Float)] = []
            list.append((ca * frontWeight, SIMD2(0, cb), SIMD2(ca, cb), .pi / 2, .pi / 2))
            list.append((ql * cornerWeight, SIMD2(ca, cb), SIMD2(ca, cb), .pi / 2, 0))
            list.append((2 * cb * sideWeight, SIMD2(ca, cb), SIMD2(ca, -cb), 0, 0))
            list.append((ql * cornerWeight, SIMD2(ca, -cb), SIMD2(ca, -cb), 0, -.pi / 2))
            list.append((2 * ca * backWeight, SIMD2(ca, -cb), SIMD2(-ca, -cb), -.pi / 2, -.pi / 2))
            list.append((ql * cornerWeight, SIMD2(-ca, -cb), SIMD2(-ca, -cb), -.pi / 2, -.pi))
            list.append((2 * cb * sideWeight, SIMD2(-ca, -cb), SIMD2(-ca, cb), -.pi, -.pi))
            list.append((ql * cornerWeight, SIMD2(-ca, cb), SIMD2(-ca, cb), -.pi, -1.5 * .pi))
            list.append((ca * frontWeight, SIMD2(-ca, cb), SIMD2(0, cb), .pi / 2, .pi / 2))
            segs = list.map { (len: $0.0, p0: $0.1, p1: $0.2, ang0: $0.3, ang1: $0.4) }
            total = segs.reduce(0) { $0 + $1.len }
        }
        /// 둘레 u → (가운데 사각형 위 점, 바깥 법선(x, z)).
        func perimeter(_ u: Float) -> (SIMD2<Float>, SIMD2<Float>) {
            var x = (u - floor(u)) * total
            for sg in segs {
                if x <= sg.len {
                    let t = sg.len > 0 ? min(max(x / sg.len, 0), 1) : 0
                    let ang = sg.ang0 + (sg.ang1 - sg.ang0) * t
                    return (sg.p0 + (sg.p1 - sg.p0) * t, SIMD2(cos(ang), sin(ang)))
                }
                x -= sg.len
            }
            let sg = segs[segs.count - 1]
            return (sg.p1, SIMD2(cos(sg.ang1), sin(sg.ang1)))
        }
        func region(_ v: Float) -> Region {
            for (i, c) in Surface.vCuts.enumerated() where v <= c { return Surface.regions[i] }
            return Surface.regions[Surface.regions.count - 1]
        }
        func pos(_ u: Float, _ v: Float) -> SIMD3<Float> {
            let (c, n) = perimeter(u)
            func at(_ d: Float, _ y: Float, scale: Float = 1) -> SIMD3<Float> { let q = (c + n * d) * scale; return SIMD3(q.x, y, q.y) }
            func k(_ lo: Float, _ hi: Float) -> Float { min(max((v - lo) / (hi - lo), 0), 1) }
            let cuts = Surface.vCuts
            let rl = wall / 2, ri = r - wall
            if v <= cuts[0] { return at(0, y0, scale: k(0, cuts[0])) }
            if v <= cuts[1] { let ph = -Float.pi / 2 + k(cuts[0], cuts[1]) * Float.pi / 2; return at(r * cos(ph), y0 + r + r * sin(ph)) }
            if v <= cuts[2] { return at(r, y0 + r + k(cuts[1], cuts[2]) * (y1 - rl - y0 - r)) }
            if v <= cuts[3] { let ps = k(cuts[2], cuts[3]) * Float.pi; return at(r - rl + rl * cos(ps), y1 - rl + rl * sin(ps)) }
            if v <= cuts[4] { return at(ri, (y1 - rl) + k(cuts[3], cuts[4]) * ((y0 + wall) - (y1 - rl))) }
            return at(ri, y0 + wall, scale: 1 - k(cuts[4], 1))
        }
    }

    /// 인쇄 판 표본기(sRGB 바이트 → 선형, 쌍선형). 판 크기가 규약과 다르면 nil.
    struct SheetSampler {
        let px: [UInt8]
        init?(_ image: CGImage) {
            guard image.width == sheetWidth, image.height == sheetHeight else { return nil }
            var p = [UInt8](repeating: 0, count: sheetWidth * sheetHeight * 4)
            let ctx = CGContext(data: &p, width: sheetWidth, height: sheetHeight, bitsPerComponent: 8, bytesPerRow: sheetWidth * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
            px = p
        }
        func sample(_ face: Face, _ s: Double, _ t: Double) -> SIMD3<Double> {
            let (x, y) = sheetPixel(face, s, t)
            let fx = x - 0.5, fy = y - 0.5
            let ix = min(Int(fx), sheetWidth - 2), iy = min(Int(fy), sheetHeight - 2)
            let ax = fx - Double(ix), ay = fy - Double(iy)
            func at(_ cx: Int, _ cy: Int) -> SIMD3<Double> {
                let o = (cy * sheetWidth + cx) * 4
                return SIMD3(toLinear(Double(px[o]) / 255), toLinear(Double(px[o + 1]) / 255), toLinear(Double(px[o + 2]) / 255))
            }
            let top = at(ix, iy) * (1 - ax) + at(ix + 1, iy) * ax
            let bot = at(ix, iy + 1) * (1 - ax) + at(ix + 1, iy + 1) * ax
            return top * (1 - ay) + bot * ay
        }
    }

    /// 상자 구역별 바탕색(선형): 바깥 벽 = 인쇄 판(옆면은 한 단 어둡게 + 팔 구멍) · 바닥 짙은 빨강 · 위 테 흰 판지 · 안쪽 판지(깊을수록 그늘).
    static func paint(_ sheet: SheetSampler) -> (Region, SIMD3<Float>) -> SIMD3<Double> {
        let redDeepL = lin(redDeep), boardL = lin(board), boardDeepL = lin(boardDeep)
        let holeL = lin(holeInk), cutL = lin(cutEdge)
        return { region, p in
            switch region {
            case .outer:
                let (face, s, t) = printCoord(p)
                guard face == .side else { return sheet.sample(face, s, t) }
                var c = sheet.sample(face, s, t) * 0.92
                // 팔 구멍: 바깥 얕은 그늘 → 짙은 판지색 가는 자른 면 → 어두운 속(팔이 이 안을 채운다).
                let ey = Double((p.y - holeY) / holeHY), ez = Double((p.z - holeZ) / holeHZ)
                let e = (ey * ey + ez * ez).squareRoot()
                c = c * (1 - 0.22 * (1 - smooth(1.0, 1.10, e)))
                c = c + (cutL - c) * (1 - smooth(0.975, 0.995, e))
                c = c + (holeL - c) * (1 - smooth(Double(holeFit), Double(holeFit) + 0.02, e))
                return c
            case .bottom: return redDeepL
            case .lip: return boardL
            case .inner:
                let depth = Double((y1 - p.y) / (y1 - y0))
                return boardL + (boardDeepL - boardL) * min(1, depth * 1.25)
            case .innerBottom: return boardDeepL * 0.8
            }
        }
    }

    static func boxNode(_ sheet: SheetSampler) -> SCNNode {
        let surf = Surface()
        let albedo = paint(sheet)
        return pieceNode(name: boxNodeName, nu: meshU, nv: meshV, closedU: true, texW: bakeWidth, texH: bakeHeight,
                         pos: { u, v in surf.pos(u, v) },
                         albedo: { _, v, p in albedo(surf.region(Float(v)), p) },
                         lookAt: { _, v, _ in
                             switch surf.region(Float(v)) { case .inner, .innerBottom, .lip: return cardboard
                             default: return paper }
                         }, transform: matrix_identity_float4x4)
    }

    // MARK: 막대 곡면
    /// 막대 한 개: 자기 축 +y, 원점 = 아래 끝. 아래부터 stickCoatFrac 만큼 밀크 초코 코팅(끝 물결), 나머지 위쪽이 비스킷 손잡이(둥근 끝).
    static func stickNode(_ st: Stick) -> SCNNode {
        let q = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(st.dir)) * simd_quatf(angle: st.spin, axis: SIMD3(0, 1, 0))
        var transform = simd_float4x4(q)
        transform.columns.3 = SIMD4(st.base.x, st.base.y, st.base.z, 1)
        let rb = stickRadius, rc = stickRadius + stickCoatThick
        let sy0: Float = 0, sy1 = st.length
        let eTop = rb * 0.45
        let vA: Float = 0.05, vB: Float = 0.955, vC: Float = 0.978
        let edgeMean = sy0 + stickCoatFrac * st.length
        func edge(_ u: Float) -> Float { edgeMean + stickWave * (0.65 * sin(2 * .pi * u * 3 + 0.6) + 0.35 * sin(2 * .pi * u * 5 + 2.0)) }
        let pos: SurfaceFn = { u, v in
            var rr: Float, y: Float
            if v < vA {
                let phi = -Float.pi / 2 + (v / vA) * (Float.pi / 2)
                rr = rc * cos(phi); y = sy0 + rc + rc * sin(phi)
            } else if v < vB {
                y = (sy0 + rc) + (v - vA) / (vB - vA) * ((sy1 - eTop) - (sy0 + rc))
                let e = edge(u)
                let k = smoothF(e - 0.0035, e + 0.0035, y)
                let lip = 0.0022 * (1 - smoothF(0, 0.012, abs(y - (e - 0.006))))
                rr = rc + (rb - rc) * k + lip * (1 - k)
            } else if v < vC {
                let phi = (v - vB) / (vC - vB) * (Float.pi / 2)
                rr = rb - eTop + eTop * cos(phi); y = sy1 - eTop + eTop * sin(phi)
            } else {
                rr = (rb - eTop) * (1 - (v - vC) / (1 - vC)); y = sy1
            }
            let ang = 2 * Float.pi * u
            return SIMD3(rr * sin(ang), y, rr * cos(ang))
        }
        let coatC = lin(coatBase), coatD = lin(coatDeep)
        let bisc = lin(biscuit), biscD = lin(biscuitDeep), biscE = lin(biscuitEnd)
        func coated(_ u: Double, _ p: SIMD3<Float>) -> Double { 1 - smooth(-0.002, 0.002, Double(p.y - edge(Float(u)))) }
        let ax = simd_normalize(SIMD3<Double>(Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z)))
        let coatLook = Look(ambient: 0.52, spec: 0.80, gloss: 48, wrap: 0.30, rim: 0.35, axis: ax, tint: lin(coatHi))
        let biscLook = Look(ambient: 0.66, spec: 0.06, gloss: 10, wrap: 0.50, rim: 0.0, axis: ax)
        return pieceNode(name: st.name, nu: 64, nv: 300, closedU: true, texW: 256, texH: 1024, pos: pos,
                         albedo: { u, v, p in
                             let k = coated(u, p)
                             let ridge = pow(abs(cos(u * 2 * .pi * 9)), 8)
                             let iu = Int(u * 220), iy = Int(Double(p.y) * 600)
                             var bc = bisc + (biscD - bisc) * (0.25 * ridge + 0.35 * hash2(iu, iy, 5) * (hash2(iu, iy, 6) > 0.85 ? 1 : 0))
                             if v > Double(vB) { bc = bc + (biscE - bc) * smooth(Double(vB), Double(vC) + 0.01, v) }
                             let cc = coatC + (coatD - coatC) * 0.12 * smooth(Double(edgeMean), Double(sy0), Double(p.y))
                             return bc + (cc - bc) * k
                         },
                         lookAt: { u, _, p in coated(u, p) > 0.5 ? coatLook : biscLook }, transform: transform)
    }

    /// 장식 한 벌(상자 + 막대 셋). 판 크기가 규약과 다르면 nil(앱은 번들 판으로 되돌린다).
    static func make(sheet: CGImage) -> SCNNode? {
        guard let sampler = SheetSampler(sheet) else { return nil }
        let root = SCNNode()
        root.name = decorNodeName
        root.addChildNode(boxNode(sampler))
        for st in sticks { root.addChildNode(stickNode(st)) }
        return root
    }

    /// 장식 꼭대기(물체 좌표 y) — 정점을 자기 변환으로 옮겨 잰다.
    static func measuredTopY(_ decor: SCNNode) -> Float {
        var top: Float = -.infinity
        decor.enumerateHierarchy { node, _ in
            guard let src = node.geometry?.sources(for: .vertex).first else { return }
            let m = decor.simdConvertTransform(node.simdTransform, from: node.parent)
            src.data.withUnsafeBytes { raw in
                for i in 0..<src.vectorCount {
                    let o = src.dataOffset + i * src.dataStride
                    let p = SIMD4<Float>(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                         raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self), 1)
                    top = max(top, (m * p).y)
                }
            }
        }
        return top
    }
}

// END pepero-decor
// ── 생성기 사본 끝 ───────────────────────────────────────────────────────────────────────────────────────────────────

enum PeperoAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 장식 루트 이름(생성기 `PeperoDecor.decorNodeName` — "check.peperoDecor"). 이 노드 **아래 전부**가 장식이다(`AingDecor.isDecor`).
    static var decorNodeName: String { PeperoDecor.decorNodeName }

    /// "이 캐릭터 노드는 빼빼로다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다). 엔진의 `currentCharacterID` 가 읽는다.
    static let markerName = "check.peperoAing"

    // MARK: - 번들 자원 · 그릴 수 있다

    /// 빼빼로를 그리는 데 필요한 **번들** 그림 — 인쇄 판 폴백 + 초상 두 장(`PeperoArt` 의 번들 사본). 몸은 아잉 재질 그대로라 더 없다.
    /// 디스크 캐시(운영 Storage 에서 받은 새 그림)는 '그릴 수 있다'의 재료가 아니다 — 번들 폴백이 늘 있어야 캐시가 지워져도 선다.
    static func requiredResourceNames() -> [String] {
        PeperoArt.Kind.allCases.map(\.bundleName)
    }

    /// 이 빌드가 빼빼로를 그릴 수 있는가 — 위 세 장이 **실재**한다(이슬 규약). 상점 능력 번호 6(`ShopWire.protocolVersion`)의 재료다.
    static func isDrawable(resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames().allSatisfy(resourceExists)
    }

    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        isDrawable { name in
            guard let url = CakeAingFinish.resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 장식(프로세스당 한 번 — 판이 바뀌면 다시)

    /// 원본 하나 + 그 원본을 구운 판 + 새로 구운 횟수(시험 관찰). 자물쇠 안에서 굽는다 — 두 스레드가 같이 찾아도 한 번만 굽는다.
    private struct TemplateState {
        var template: SCNNode?
        var sheet: CGImage?
        var builds = 0
        /// 원본을 구운 스레드가 메인이었는가(굽기마다 하나 — 시험 전용 관찰).
        var onMain: [Bool] = []
    }

    private static let templateState = OSAllocatedUnfairLock(uncheckedState: TemplateState())

    /// 장식 사본(루트 이름 `decorNodeName`). 판(`sheet` — 기본은 그림 저장소가 고른 인쇄 판)이 원본을 구운 판과 **같은 객체**면 사본만 주고,
    /// 다르면(저장소가 새 판을 받았다) 그 판으로 다시 굽는다. 판이 규약(1024²)과 다르거나 없으면 nil(빼빼로는 장식 없이 아잉으로 선다).
    /// 원본은 **어느 씬에도 붙지 않은** 새 노드라 어느 스레드에서 불러도 된다(이슬 · 케이크 `decorNode` 주석과 같은 이유).
    static func decorNode(sheet: CGImage? = PeperoArt.current.boxImage()) -> SCNNode? {
        templateState.withLockUnchecked { state -> SCNNode? in
            guard let sheet else {
                logger.error("pepero finish: 인쇄 판이 없다 — 장식 없이 선다")
                return nil
            }
            if let template = state.template, state.sheet === sheet { return template.clone() }
            let started = CFAbsoluteTimeGetCurrent()
            guard let template = PeperoDecor.make(sheet: sheet) else {
                logger.error("pepero finish: 인쇄 판 크기가 규약과 다르다(\(sheet.width)×\(sheet.height)) — 장식 없이 선다")
                return nil
            }
            let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            let onMain = Thread.isMainThread
            // 런 루프가 없는 스레드에서 만들면 SceneKit 의 암묵 트랜잭션이 열린 채 남는다 — 닫는다(케이크 · 이슬 `decorNode` 와 같은 이유).
            if !onMain { SCNTransaction.flush() }
            logger.notice("pepero decor built ms=\(ms, format: .fixed(precision: 1), privacy: .public) main=\(onMain, privacy: .public)")
            state.template = template
            state.sheet = sheet
            state.builds += 1
            state.onMain.append(onMain)
            return template.clone()
        }
    }

    /// 메인에서 부르는 길: 원본이 **이미** 이 판으로 구워져 있으면 사본, 아니면 nil — 원본이 없거나 다른 스레드가 굽는 중(자물쇠가 잡혀 있다)이면
    /// **기다리지 않고** nil 이다. 굽기(release 0.73초 · debug 20초)를 메인이 떠안거나 자물쇠 앞에서 멎지 않게 한다(`apply` 의 ★ 메인 굽기 금지).
    static func readyDecorNode(sheet: CGImage) -> SCNNode? {
        let ready = templateState.withLockIfAvailableUnchecked { state -> SCNNode? in
            guard let template = state.template, state.sheet === sheet else { return nil }
            return template.clone()
        }
        return ready ?? nil
    }

    /// 메인 밖에서 구운 장식을 메인으로 넘기는 상자(SCNNode 는 Sendable 이 아니다 — 아직 어느 씬에도 안 붙은 새 노드 · 붙일 몸 노드를 한 번 넘길 뿐이다).
    private struct NodeHandoff: @unchecked Sendable { let node: SCNNode? }

    /// 굽기를 기다리며 장식 없이 선 몸 노드 수(시험 관찰 — 붙이면 준다).
    private static let pendingAttachState = OSAllocatedUnfairLock(initialState: 0)

    /// 시험 전용: 메인 밖 굽기를 기다리는 장식 붙이기 수.
    static var pendingAttachCountForTesting: Int { pendingAttachState.withLock { $0 } }

    /// 원본이 아직 없을 때(메인): 메인 밖에서 굽고(다른 스레드가 굽는 중이면 그 끝을 기다린다 — 같은 원본) 메인으로 돌아와 몸 메시 노드에 붙인다.
    /// 그 사이 씬은 상자 없이 아잉 몸으로 선다(release 0.73초). 이미 붙어 있으면(같은 노드에 두 번 불렸다) 더 안 붙인다.
    /// 판은 부른 자리의 저장소(`art` — 작업 지역 시험 저장소가 GCD 스레드로 안 따라가므로 잡아 넘긴다)에서 고른다.
    private static func attachWhenBaked(to bodyNode: SCNNode, art: PeperoArt) {
        pendingAttachState.withLock { $0 += 1 }
        let body = NodeHandoff(node: bodyNode)
        DispatchQueue.global(qos: .userInitiated).async {
            let decor = NodeHandoff(node: decorNode(sheet: art.boxImage()))
            DispatchQueue.main.async {
                defer { pendingAttachState.withLock { $0 -= 1 } }
                guard let bodyNode = body.node, let decor = decor.node,
                      bodyNode.childNode(withName: decorNodeName, recursively: false) == nil else { return }
                bodyNode.addChildNode(decor)
                logger.notice("pepero decor attached after off-main bake")
            }
        }
    }

    /// 시험 전용: 지금까지 원본을 새로 구운 횟수.
    static var decorBuildCountForTesting: Int { templateState.withLockUnchecked { $0.builds } }

    /// 시험 전용: 원본을 구운 스레드가 메인이었는가(굽기마다 하나).
    static var decorBuildsOnMainForTesting: [Bool] { templateState.withLockUnchecked { $0.onMain } }

    /// 시험 전용: 장식 원본을 버린다(굽기 기록도).
    static func resetDecorCacheForTesting() {
        templateState.withLockUnchecked { $0 = TemplateState() }
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 빼빼로 마감을 입힌다: 몸 메시 노드(얼굴 재질 — 큰 CGImage 디퓨즈 — 을 가진 장식 밖 첫 노드)에 장식 사본을
    /// 붙이고 표식을 단다. **몸 재질은 한 비트도 안 바꾼다**(원래 아잉). 내려 세우지 않는다(머리말 ★ 프레이밍). 금 · 무지개 · 케이크 · 이슬과
    /// 같은 순서(unlit 정규화 뒤 · 감은 눈 노드 앞 — 프레이밍 카메라는 몸만 보고 먼저 섰다)로 부른다. 메시가 없으면(메인 밖에서는 판도) 아무것도
    /// 안 바꾸고 false.
    /// ★ 메인 굽기 금지(검토 수리): 메인에서 불렸는데 원본이 아직 없으면(시작 5초 안의 미리 굽기 전 · 그 굽기 도중 · 새 판을 받은 직후) 여기서 굽지
    ///   않는다 — 예전엔 `makeNSView → makeScene` 이 메인에서 상자 2048×768 을 구웠다(release 0.73초 · debug 20초, 굽는 중이면 같은 자물쇠 앞에서
    ///   같은 길이로 멎었다). 이제 표식만 먼저 달고 상자 없이 세운 뒤, 메인 밖에서 구워 다 되면 메인으로 와서 붙인다(`attachWhenBaked`).
    ///   메인 밖에서 불리면(시험 · 미리 굽기 경로) 예전처럼 그 자리에서 굽고 붙인다.
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        var bodyNode: SCNNode?
        character.enumerateHierarchy { node, stop in
            guard !AingDecor.isDecor(node) else { return }
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID,
                      (contents as! CGImage).width >= 256 else { continue }
                bodyNode = node
                stop.pointee = true
                return
            }
        }
        guard let bodyNode else {
            logger.error("pepero finish: 얼굴 재질을 못 찾았다 — 아잉으로 선다")
            return false
        }
        if Thread.isMainThread {
            let art = PeperoArt.current
            if let sheet = art.boxImageIfDecoded(), let decor = readyDecorNode(sheet: sheet) {
                bodyNode.addChildNode(decor)
            } else {
                attachWhenBaked(to: bodyNode, art: art)
            }
        } else {
            guard let decor = decorNode() else { return false }
            bodyNode.addChildNode(decor)
        }
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    /// 이 캐릭터 노드가 빼빼로인가(표식).
    static func isPepero(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }
}

// MARK: - 미리 굽기 문(가진 사람 · 입은 사람만 — 조정자 결정 11-04)

/// 빼빼로 장식 미리 굽기의 문. 상자 2048×768 + 막대 셋(≈ 13MB · release ~0.7초)을 **모든 사람에게** 굽지 않는다 — 지금 입었거나(로컬 저장
/// 선택값 — 상점 상태 전에도 안다) 가진 사람만 시작 뒤 메인 밖에서 한 번 굽는다. 그 밖의 사람은 빼빼로 씬이 처음 필요할 때(남의 울트라 ·
/// 처음 입기) 메인 밖에서 굽고 그동안 상자가 ~0.7초 늦게 붙는다(`PeperoAingFinish.apply` ★ — 메인은 여전히 굽지 않는다).
///
/// 문을 여는 자리는 셋이다: ① 앱 시작(`arm` — 입었다 · 가졌다, 그리고 '이 시각 전엔 굽지 않는다' = 시작 + 5초 — 케이크 · 이슬 미리 굽기와 같은 때) ·
/// ② 상점 상태가 늦게 와 가진 것이 확인됐다(`WorkTimerStore.applyShopState`) · ③ 선물을 받았다(`WorkTimerStore.applyCakeGiftClaim`).
/// 굽기는 **프로세스당 한 번**이다 — 둘째 요청부터는 처음 건 손잡이를 돌려준다(상점 상태는 여러 번 온다). 시작이 문을 열기 전에 온 요청은
/// 기억만 했다가 시작이 열 때 건다(앱에서는 상점 응답이 시작보다 늦게 오지만, 차례가 바뀌어도 잃지 않는다). 그래서 앱 시작이 없는 시험
/// 프로세스에서는 공용 문이 아무것도 굽지 않는다 — 시험은 자기 문(`init(bake:)`)을 만들어 스토어에 끼운다.
final class PeperoPrewarmGate: @unchecked Sendable {
    /// 앱의 문(스토어 기본값 · 앱 시작 · 그림 저장소가 쓴다).
    static let shared = PeperoPrewarmGate(bake: liveBake)

    /// 앱이 굽는 것 — 그림 저장소가 고른 판으로 장식 원본(`PeperoAingFinish.decorNode` — 이미 그 판으로 구웠으면 사본만 준다).
    static let liveBake: @Sendable () -> Void = { _ = PeperoAingFinish.decorNode() }

    private struct State {
        /// 시작이 정한 '이 시각 전엔 굽지 않는다'. nil = 시작이 아직 문을 안 열었다(요청은 `wanted` 로 기억만 한다).
        var notBefore: DispatchTime?
        /// 구울 사람으로 확인됐다(입었다 · 가졌다 · 방금 받았다).
        var wanted = false
        /// 건 미리 굽기(프로세스당 하나).
        var work: DispatchWorkItem?
        /// 미리 굽기를 건 횟수(새 판 다시 굽기 포함 — 시험 관찰).
        var scheduled = 0
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let bake: @Sendable () -> Void

    init(bake: @escaping @Sendable () -> Void) {
        self.bake = bake
    }

    /// 미리 구울 사람인가 — 지금 입었거나(`wornID` — 로컬 저장 선택값) 가진 목록에 빼빼로가 있다.
    static func wants(wornID: String, ownedIDs: Set<String>) -> Bool {
        wornID == CharacterCatalog.peperoAingID || ownedIDs.contains(CharacterCatalog.peperoAingID)
    }

    /// 앱 시작이 부른다: '이 시각 전엔 굽지 않는다'를 `delay` 초 뒤로 세우고, 구울 사람이면(입었다 · 가졌다 · 그 전에 요청이 왔다) 그때 메인 밖에서
    /// 굽도록 건다. 반환 = 건 굽기(안 구울 사람이면 nil — 시험이 끝을 기다리는 손잡이).
    @discardableResult
    func arm(after delay: TimeInterval, wornID: String, ownedIDs: Set<String>) -> DispatchWorkItem? {
        state.withLockUnchecked { state in
            state.notBefore = .now() + max(0, delay)
            if Self.wants(wornID: wornID, ownedIDs: ownedIDs) { state.wanted = true }
            return scheduleLocked(&state)
        }
    }

    /// 가진 것이 확인된 자리(상점 상태 · 선물 받기)가 부른다. 이미 걸었으면 그 손잡이를 돌려준다(다시 안 건다). 시작이 아직 문을 안 열었으면 기억만
    /// 하고 nil.
    @discardableResult
    func request() -> DispatchWorkItem? {
        state.withLockUnchecked { state in
            state.wanted = true
            return scheduleLocked(&state)
        }
    }

    /// 그림 저장소가 새 판을 받았다(`PeperoArt.absorb`) — 구울 사람이면 그 판으로 메인 밖에서 다시 굽는다(시작이 정한 시각 뒤). 안 구울 사람은
    /// 새 판도 미리 굽지 않는다(다음 빼빼로 씬이 메인 밖에서 굽는다). 시작이 아직 문을 안 열었으면 시작이 걸 굽기가 그때의 판으로 굽는다.
    func rebakeForNewSheet(_ body: @escaping @Sendable () -> Void) {
        state.withLockUnchecked { state in
            guard state.wanted, let notBefore = state.notBefore else { return }
            state.scheduled += 1
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: max(notBefore, .now()), execute: DispatchWorkItem(qos: .utility, block: body))
        }
    }

    /// 시험 관찰: 미리 굽기를 건 횟수.
    var scheduledCount: Int { state.withLockUnchecked { $0.scheduled } }

    private func scheduleLocked(_ state: inout State) -> DispatchWorkItem? {
        if let work = state.work { return work }
        guard state.wanted, let notBefore = state.notBefore else { return nil }
        let work = DispatchWorkItem(qos: .utility, block: bake)
        state.work = work
        state.scheduled += 1
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: max(notBefore, .now()), execute: work)
        return work
    }
}
