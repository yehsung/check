import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// 산타 아잉이(크리스마스 기간 선물 — 대표 #d_3VZdglOgRABx "산타아잉이는 그냥 주고, 루돌프 아잉이는 따로 이벤트를 기획하자").
//  ① 코어: 내장 열셋째 · 마감 .santa · 선물 전용(종류 santa — 빼빼로와 같은 기간 선물) · 능력 번호 11 은 지역 두 센터까지 다 그리고 산타도 그릴
//     때만(판정 자리는 `ShopWire.protocolVersion` 하나) · 팔 접기 · 셰이더 글자 · 장식 조각 · 장식 굽기.
//  ② 선물 전선: 'santa' 해석(서비스 디코더 = snake → camel) · 번호 10 이하 빌드엔 섞여 와도 안 띄움 · 수령 needs_update(min 11) · 문구(대표 C).
//  ③ 맥 3D: 실제 앱 씬에 산타 마감(팔 접기 굽기 칸 + 무지개 합성 디퓨즈 + 산타 셰이더 + ckShadeMap + 장식 + 표식) · 렌더(배 빨강 · 수염 흰 ·
//     얼굴 살구빛 · 장화 검정) · 엔진 교체 왕복 · 그릴 수 있다(번들 → 11) · 초상 URL · 프레이밍(부유 · 울트라 산타 자세 — 스트레치 털 방울).
//  ④ 출시 게이트: 문구가 가안(`SantaGiftText.copyDecided` false)인 채로 맥 버전을 0.3.86 다음으로 올리면 빨갛다.
// 증거 PNG: `CHECK_SANTA_AING_EVIDENCE_DIR=<폴더>` — 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉과 나란히).

@Suite struct SantaAingCoreTests {
    static var macSantaPortraitsInSourceTree: Bool {
        SantaAingArt.portraitResourceNames.allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }
    /// 산타 그림이 다 소스 트리에 있는가 — 능력 번호 11 의 기준선(누적 사슬 시험이 이 값을 읽는다).
    static var macSantaArtInSourceTree: Bool {
        SantaAingArt.requiredResourceNames(for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    @Test("카탈로그: 산타 아잉이는 내장 열셋째(맨 끝) · 마감 .santa · 선물 전용(종류 santa) · 희귀 · 뽑기 · 조각 · 미션 · 지역 아님")
    func catalog() {
        #expect(CharacterCatalog.builtIns.last?.id == "aing_santa")
        #expect(CharacterCatalog.builtIns.count == 13)
        #expect(CharacterCatalog.santaAingID == "aing_santa" && SantaAingArt.characterID == "aing_santa")
        #expect(CharacterCatalog.builtInSantaAing.displayName == "산타 아잉이" && SantaAingArt.displayName == "산타 아잉이")
        #expect(CharacterCatalog.builtInSantaAing.kind == .scene3D)
        #expect(CharacterCatalog(entries: []).manifest(id: "aing_santa")?.kind == .scene3D)
        #expect(CharacterManifest.Finish(characterID: "aing_santa") == .santa)
        #expect(!CharacterManifest.Finish.santa.isRare && !CharacterManifest.Finish.santa.isCake)
        #expect(CharacterCatalog.isSantaAing("aing_santa"))
        for near in ["aing_santa ", "AING_SANTA", "santa", "aing_rudolph", "", nil] as [String?] {
            #expect(!CharacterCatalog.isSantaAing(near), "\(String(describing: near))")
        }
        #expect(CharacterCatalog.isGiftOnlyBuiltIn("aing_santa"))
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn("aing_santa") && !CharacterCatalog.isShardOnlyBuiltIn("aing_santa")
                && !CharacterCatalog.isMissionRewardBuiltIn("aing_santa") && !CharacterCatalog.isRegionAing("aing_santa"))
        #expect(CharacterCatalog.santaGiftBuiltInIDs == ["aing_santa"])
        #expect(CharacterCatalog.giftKind(ofBuiltIn: "aing_santa") == .santa)
        #expect(CharacterCatalog.giftOnlyBuiltInIDs.last == "aing_santa")
        #expect(Set(CharacterCatalog.giftOnlyBuiltInIDs) == Set(CharacterCatalog.builtIns.map(\.id).filter(CharacterCatalog.isGiftOnlyBuiltIn)))
        // 다른 뜻 자리(케이크 · 술 · 빼빼로 · 지역 · 뽑기)에는 섞이지 않는다.
        for list in [CharacterCatalog.birthdayGiftBuiltInIDs, CharacterCatalog.drinkGiftBuiltInIDs, CharacterCatalog.peperoGiftBuiltInIDs,
                     CharacterCatalog.regionGiftBuiltInIDs, CharacterCatalog.gachaOnlyBuiltInIDs, CharacterCatalog.shopBuiltInIDs] {
            #expect(!list.contains("aing_santa"), "\(list)")
        }
        // 루돌프(순록 아잉이)는 이 일에 없다(대표 — 따로 기획).
        #expect(!CharacterCatalog.builtIns.map(\.id).contains { $0.contains("rudolph") || $0.contains("reindeer") })
        // 상점 줄: 선물 전용 — 못 산다 · 뽑기 전용 아님(서버는 not_for_sale 갈래로 gacha_only 도 싣는다).
        let row = ShopCharacterRow(id: "aing_santa", price: 2007, owned: false, gachaOnly: true, giftOnly: true)
        #expect(row.isGiftOnly && !row.isPurchasable && !row.isGachaOnly)
    }

    @Test("능력 번호: 지역 두 센터까지 + 산타 → 11 · 산타가 없으면 10 · 산타만 있고 지역 하나 빠지면 9(누적) · 문턱 11")
    func protocolEleven() {
        let upToRegion = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "aing_isul", "aing_pepero", "aing_hwoo",
                          "aing_ruby", "aing_dev", "aing_busan", "aing_seoul"]
        #expect(ShopWire.santaProtocol == 11)
        #expect(ShopWire.santaCharacterIDs == ["aing_santa"])
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToRegion) == 10)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToRegion + ["aing_santa"]) == 11)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToRegion.filter { $0 != "aing_seoul" } + ["aing_santa"]) == 9,
                "지역 하나가 빠지면 산타가 있어도 11 은 커녕 10 도 못 보낸다")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: ["aing_santa"]) == 0)
        #expect(!ShopWire.supportsSantaGift(protocolVersion: 10) && ShopWire.supportsSantaGift(protocolVersion: 11))
        #expect(ShopWire.supportsRegionGift(protocolVersion: 11) && ShopWire.supportsPeperoGift(protocolVersion: 11), "번호는 누적이다")
        // 폰(산타 그림이 없다)은 지금 말하는 번호 그대로다 — 개발 아잉이까지 9(지역 · 산타 초상이 없다).
        let phoneLike = upToRegion.filter { !CharacterCatalog.isRegionAing($0) }
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: phoneLike) == ShopWire.devProtocol)
    }

    @Test("그릴 수 있다(코어): 맥 = 초상 둘 + 밝기 맵 · 폰 = 초상 둘 · 하나만 빠져도 못 그린다")
    func drawableDefinition() {
        #expect(SantaAingArt.requiredResourceNames(for: .mac) == ["aing_santa-neutral", "aing_santa-negative", "aing_rainbow-shade"])
        #expect(SantaAingArt.requiredResourceNames(for: .phone) == ["aing_santa-neutral", "aing_santa-negative"])
        #expect(SantaAingArt.isDrawable(on: .mac) { _ in true })
        for missing in SantaAingArt.requiredResourceNames(for: .mac) {
            #expect(!SantaAingArt.isDrawable(on: .mac) { $0 != missing }, "\(missing) 가 빠져도 그린다고 한다")
        }
        #expect(Self.macSantaArtInSourceTree, "산타 그림이 소스 트리에 없다 — scripts/make-santa-aing.swift 를 돌려라")
    }

    @Test("팔 접기: 지느러미 팔 정점만 몸 겉면으로(반지름 ≈ 몸 둘레) · 접힘 표시 · 얼굴 · 앞 · 위 · 아래 정점은 그대로 · 굽기 수 = 정점 수")
    func armFold() {
        let fin = SIMD3<Float>(0.93, -0.25, 0.0)
        let (q, flag) = SantaAingShape.collapse(fin)
        let r = (q.x * q.x + q.z * q.z).squareRoot()
        #expect(abs(r - SantaAingShape.bodyRadius(-0.25)) < 0.01, "팔 끝이 몸 겉면으로 안 왔다(\(r))")
        #expect(q.y == fin.y && flag > 0.9)
        for still in [SIMD3<Float>(0, 0.42, 0.53), SIMD3<Float>(0, -0.2, 0.70), SIMD3<Float>(0.3, 0.80, 0.0), SIMD3<Float>(0.6, -0.80, 0.0),
                      SIMD3<Float>(0.2, -0.3, -0.69)] {
            let (p, f) = SantaAingShape.collapse(still)
            #expect(p == still && f == 0, "\(still) 가 움직였다")
        }
        #expect(abs(SantaAingShape.bodyRadius(-0.85) - 0.069) < 1e-6 && abs(SantaAingShape.bodyRadius(0.0) - 0.730) < 1e-6)
        #expect(abs(SantaAingShape.bodyRadius(-0.025) - (0.733 + 0.730) / 2) < 1e-6, "표 사이는 선형 보간")
        let baked = SantaAingShape.bake([fin, SIMD3(0, 0.42, 0.53)])
        #expect(baked.count == 2 && baked.fold.count == 2)
        #expect(simd_length(baked.displacement[0]) > 0.1 && baked.displacement[1] == .zero)
        #expect(SantaAingShape.bake([fin]) == SantaAingShape.bake([fin]), "굽기가 결정적이지 않다")
    }

    @Test("셰이더 글자: 팔 접기(geometry 가 칸 1 · 2 로 옮김) · 잔점 지우기 · 빨간 몸 · 허리띠 · 수염 · 털 챙 · 털 단 · 홍조 · 얼굴은 β 로 지킨다")
    func shaderText() {
        let g = SantaAingShader.geometry
        for needle in ["_geometry.position.xyz = ckQ;", "_geometry.texcoords[1].x", "_geometry.texcoords[2].x", "_geometry.texcoords[2].y", "float3 ckFn;"] {
            #expect(g.contains(needle), "geometry: \(needle) 가 없다")
        }
        let f = SantaAingShader.fragment()
        for needle in ["in.ckFn.x", "ckKeepTex = 0.0;", "float ckDrop", "ckFlush = 1.0;", "float bdA;", "float brA;", "float hmA;",
                       "ckInFace ? ckBeta : 1.0", "ckShadeMap", "float ckTh = atan2(ckP.x, ckP.z);", "float rgArm = 0.0;"] {
            #expect(f.contains(needle), "fragment: \(needle) 가 없다")
        }
        #expect(!f.contains("ckLid"), "덮개 칠은 쓰지 않는다")
        #expect(SantaAingShader.fragment(faceOff: true).contains("bool ckInFace = false"))
        #expect(SantaAingShader.brim == (t0: 0.085, t1: 0.150) && SantaAingShader.hemFrom == 0.835 && SantaAingShader.belt == (t0: 0.600, t1: 0.665))
        #expect(SantaAingShader.red == 0xD8252D && SantaAingShader.peach == 0xFFD9C7 && SantaAingShader.black == 0x1E1F25)
        #expect(SantaAingDecor.decorNodeName == "check.santaDecor")
    }

    static func samplePieces() -> [SantaDecorPiece] {
        SantaAingDecor.pieces(crown: SIMD3(0, 0.849, -0.02), crownNormal: SIMD3(0, 1, 0),
                              mustacheRoots: (SIMD3(0.105, 0.282, 0.53), SIMD3(-0.105, 0.282, 0.53)), noseRoot: SIMD3(0, 0.322, 0.54))
    }

    @Test("장식 조각: 털 방울(정수리 위) · 콧수염 둘 · 코(분홍) · 장화 둘(몸 아래 앞 · 검정) · 둥근 팔 둘(소매 · 소맷부리 · 장갑) — 이름 · 자리 · 색")
    func decorPieces() {
        let pieces = Self.samplePieces()
        #expect(pieces.map(\.name) == ["check.santa.pompom", "check.santa.mustacheR", "check.santa.mustacheL", "check.santa.nose",
                                       "check.santa.bootR", "check.santa.bootL", "check.santa.sleeveR", "check.santa.cuffR", "check.santa.mittenR",
                                       "check.santa.sleeveL", "check.santa.cuffL", "check.santa.mittenL"])
        let byName = Dictionary(uniqueKeysWithValues: pieces.map { ($0.name, $0) })
        func at(_ n: String, _ u: Float = 0.5, _ v: Float = 0.5) -> SIMD3<Float> { byName["check.santa." + n]!.pos(u, v) }
        #expect(at("pompom", 0.5, 1).y > 1.0 && at("pompom", 0.5, 1).y < 1.12, "털 방울 꼭대기 \(at("pompom", 0.5, 1).y)")
        #expect(at("mustacheR").x > 0.05 && at("mustacheL").x < -0.05 && at("mustacheR").z > 0.5)
        #expect(at("nose", 0.25, 0.5).z > 0.55 && abs(at("nose", 0.25, 0.5).x) < 0.01, "코 앞 끝 \(at("nose", 0.25, 0.5))")
        for boot in ["bootR", "bootL"] { #expect(at(boot).y < -0.75 && at(boot).z > 0.2, "\(boot) 은 몸 아래 앞") }
        // 장갑 가운데(자기 y 축 양 극의 가운데).
        func middle(_ n: String) -> SIMD3<Float> { (at(n, 0.5, 0) + at(n, 0.5, 1)) / 2 }
        #expect(middle("mittenR").x > 0.80 && middle("mittenL").x < -0.80, "장갑은 몸 옆 바깥(\(middle("mittenR")))")
        #expect(middle("mittenR").y < -0.20 && middle("sleeveR").y < 0.04, "팔은 어깨에서 아래로 늘어진다")
        func srgb(_ c: SIMD3<Double>) -> SIMD3<Double> {
            func e(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
            return SIMD3(e(c.x), e(c.y), e(c.z))
        }
        let nose = srgb(byName["check.santa.nose"]!.albedo(0.5, 0.5))
        #expect(nose.x > 0.9 && nose.y < 0.7, "코가 분홍이 아니다(\(nose))")
        let boot = srgb(byName["check.santa.bootR"]!.albedo(0.5, 0.5))
        #expect(boot.max() < 0.2, "장화가 검정이 아니다(\(boot))")
        let sleeve = srgb(byName["check.santa.sleeveR"]!.albedo(0.5, 0.5))
        #expect(sleeve.x > 0.7 && sleeve.y < 0.25, "소매가 빨강이 아니다(\(sleeve))")
        let pom = srgb(byName["check.santa.pompom"]!.albedo(0.5, 0.9))
        #expect(pom.min() > 0.9, "털 방울 윗면이 흰색이 아니다(\(pom))")
    }

    @Test("장식 굽기: 격자 메시 수 · 바깥 법선 · 텍스처 크기 · 불투명 · 결정적 · 빛이 구워진다(방울 위 > 아래)")
    func decorBake() {
        let pieces = Self.samplePieces()
        var texels = 0
        let started = Date()
        for piece in pieces {
            let mesh = SantaDecorBake.mesh(piece)
            #expect(mesh.positions.count == (piece.nu + 1) * (piece.nv + 1) && mesh.normals.count == mesh.positions.count)
            #expect(mesh.indices.count == 6 * piece.nu * piece.nv)
            let tex = SantaDecorBake.texture(piece)
            #expect(tex.count == piece.texW * piece.texH * 4)
            #expect(stride(from: 3, to: tex.count, by: 4).allSatisfy { tex[$0] == 255 }, "\(piece.name): 불투명이 아니다")
            texels += piece.texW * piece.texH
        }
        print(String(format: "[santa-aing] 장식 %d 조각 · 텍셀 %d · 메시+굽기 %.0f ms(이 빌드 설정)", pieces.count, texels, Date().timeIntervalSince(started) * 1000))
        // 바깥 법선: 털 방울 가운데에서 표면으로 — 법선이 같은 쪽.
        let pom = pieces[0]
        let center = (pom.pos(0.5, 0.0) + pom.pos(0.5, 1.0)) / 2
        for (u, v) in [(0.1, 0.5), (0.4, 0.3), (0.8, 0.7)] as [(Float, Float)] {
            #expect(simd_dot(SantaDecorBake.normal(pom, u, v), pom.pos(u, v) - center) > 0, "털 방울 법선이 안을 본다")
        }
        #expect(SantaDecorBake.texture(pieces[3]) == SantaDecorBake.texture(pieces[3]), "굽기가 결정적이지 않다")
        let look = SantaDecorLook(ambient: 0.6, spec: 0, gloss: 10, wrap: 0.4, rim: 0)
        #expect(SantaDecorBake.lit(SIMD3(repeating: 0.5), SIMD3(0, 1, 0), look).x > SantaDecorBake.lit(SIMD3(repeating: 0.5), SIMD3(0, -1, 0), look).x)
    }
}

// MARK: - 크리스마스 선물 — 해석 · 게이트 · 문구

@Suite struct SantaGiftWireTests {
    static let giftID = "5a17a000-0000-4000-8000-0000000000c1"

    static func host(_ label: String) -> String {
        "santa-aing-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    }

    @Test("종류: 'santa' 원문 정확히 · 내장 = 산타 하나 · 문턱 11 · 초대장 화면 · 다시 열기 기호 · 문구 묶음은 다른 종류와 다르다")
    func kind() {
        #expect(CharacterGiftKind(wireValue: "santa") == .santa && CharacterGiftKind.santa.wireValue == "santa")
        for odd in ["Santa", " santa", "santa ", "christmas", "rudolph", "산타", "", nil] as [String?] {
            #expect(CharacterGiftKind(wireValue: odd) == nil, "\(String(describing: odd))")
        }
        #expect(CharacterGiftKind.santa.builtInIDs == ["aing_santa"])
        #expect(CharacterGiftKind.santa.minProtocol == 11)
        #expect(!CharacterGiftKind.santa.isSupported(protocolVersion: 10) && CharacterGiftKind.santa.isSupported(protocolVersion: 11))
        #expect(CharacterGiftKind(builtInID: "aing_santa") == .santa)
        #expect(CharacterGiftKind.santa.copy == .santa && CharacterGiftKind.santa.copy(for: "aing_santa") == .santa)
        #expect(CharacterGiftKind.santa.showsInviteScreen)
        #expect(CharacterGiftKind.santa.reopenSymbolName == "snowflake")
        #expect(Set(CharacterGiftKind.allCases.map(\.reopenSymbolName)).count == CharacterGiftKind.allCases.count)
        let others: [CharacterGiftCopy] = [.birthday, .drink, .pepero, .region]
        #expect(!others.contains { $0.lockedCaption == SantaGiftText.lockedCaption || $0.lockedHint == SantaGiftText.lockedHint })
    }

    @Test("해석(서비스 디코더 — snake → camel 함정): 산타 선물 + 산타 → 하나 · created_at 을 읽는다 · 다른 종류 id 는 버린다 · 산타 id 가 없으면 선물 없음 · kind 없는 옛 모양에 산타만 → 없음")
    func offerDecodes() throws {
        let decoder = V0354GachaWireTests.decoder()
        func pending(_ json: String) throws -> CharacterGiftPendingResponse {
            try decoder.decode(CharacterGiftPendingResponse.self, from: Data(json.utf8))
        }
        let ok = try pending(#"{"status":"ok","gift":{"id":"\#(Self.giftID)","kind":"santa","options":["aing_santa","aing_pepero"],"note":"메리 크리스마스","created_at":"2026-12-24T00:00:00Z"}}"#)
        #expect(ok.offer == CharacterGiftOffer(id: Self.giftID, options: ["aing_santa"], note: "메리 크리스마스", createdAt: "2026-12-24T00:00:00Z", kind: .santa))
        #expect(ok.offer?.createdAt == "2026-12-24T00:00:00Z", "created_at 이 snake → camel 로 안 읽혔다")
        #expect(try pending(#"{"status":"ok","gift":{"id":"g","kind":"santa","options":["aing_pepero","aing_isul"]}}"#).offer == nil)
        #expect(try pending(#"{"status":"ok","gift":{"id":"g","options":["aing_santa"]}}"#).offer == nil, "kind 없는 옛 모양(생일)에 산타만")
        #expect(try pending(#"{"status":"ok","gift":{"id":"g","kind":"pepero","options":["aing_santa","aing_pepero"]}}"#).offer?.options == ["aing_pepero"],
                "빼빼로 선물에 산타가 섞이면 버린다")
        // 수령 응답(snake 키 character_id · min_protocol).
        let claim = try decoder.decode(CharacterGiftClaimResponse.self, from: Data(#"{"status":"ok","character_id":"aing_santa","replayed":false}"#.utf8))
        #expect(CharacterGiftClaimOutcome(response: claim, requestedID: "aing_santa") == .received(characterID: "aing_santa", replayed: false))
        let old = try decoder.decode(CharacterGiftClaimResponse.self, from: Data(#"{"status":"needs_update","min_protocol":11}"#.utf8))
        #expect(old.minProtocol == 11)
        let outcome = CharacterGiftClaimOutcome(response: old, requestedID: "aing_santa")
        #expect(outcome == .needsUpdate && !outcome.settlesGift)
        #expect(SantaGiftText.notice(for: outcome) { $0 } == CakeGiftText.needsUpdate)
    }

    @Test("서비스 게이트: 번호 11 만 산타 선물을 띄운다 · 10 이하엔 섞여 와도 안 띄운다 · 요청은 {p_protocol} 하나")
    func servicePendingByProtocol() async throws {
        let host = Self.host("pending")
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            guard rpc == "character_gift_pending" else { return nil }
            // 일부러 번호와 무관하게 산타 선물을 싣는다(서버가 잘못 실어도 클라가 막는지 잰다).
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","gift":{"id":"g-santa","kind":"santa","options":["aing_santa"],"note":null}}"#)
        }
        let service = V0354GachaWireTests.service(host: host)
        #expect(try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.peperoProtocol) == nil)
        #expect(try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.regionProtocol) == nil,
                "번호 10(산타 그림이 없는 빌드)은 산타를 못 그린다 — 받을 수 없는 창을 띄우지 않는다")
        let eleven = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.santaProtocol)
        #expect(eleven == CharacterGiftOffer(id: "g-santa", options: ["aing_santa"], kind: .santa))
        let calls = GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending")
        #expect(calls.map { $0.json["p_protocol"] as? Int } == [6, 10, 11])
        #expect(calls.allSatisfy { Set($0.json.keys) == ["p_protocol"] })
    }

    /// 받는 창 문구 — 대표 결정 #d_4wR1Qzn9OKmt "C 띵동! 산타 왔어요 🎁"(깜짝 방문 느낌, 단추 '선물 열기'). 다시 열기 카드는 그 말투에 맞춤.
    @Test("santaGiftCopyDecided — 받는 창 문구는 대표 결정 C(띵동! 산타 왔어요 🎁 · 선물 열기)")
    func santaGiftCopyDecided() {
        #expect(SantaGiftText.title == "띵동! 산타 왔어요 🎁")
        #expect(SantaGiftText.body == "착한 아잉이에게 산타가 찾아왔어요")
        #expect(SantaGiftText.confirmButton == "선물 열기")
        #expect(SantaGiftText.reopenTitle == "띵동! 산타 선물이 기다려요 🎁")
        #expect(SantaGiftText.reopenButton == "선물 열기")
        #expect(SantaGiftText.lockedCaption == "크리스마스 선물")
        #expect(SantaGiftText.lockedHint == "크리스마스에만 주는 선물이에요. 루비나 뽑기로는 얻을 수 없어요.")
        #expect(SantaGiftText.wearNowButton == CakeGiftText.wearNowButton && SantaGiftText.closeButton == CakeGiftText.closeButton)
        #expect(SantaGiftText.claimFailed == CakeGiftText.claimFailed)
        #expect(SantaGiftText.received(name: SantaAingArt.displayName) == "산타 아잉이를 받았어요!")
        let copy = CharacterGiftCopy.santa
        #expect(copy.title == SantaGiftText.title && copy.body == SantaGiftText.body && copy.confirmButton == SantaGiftText.confirmButton
                && copy.lockedCaption == SantaGiftText.lockedCaption && copy.lockedHint == SantaGiftText.lockedHint
                && copy.reopenTitle == SantaGiftText.reopenTitle && copy.reopenButton == SantaGiftText.reopenButton)
        #expect(SantaGiftText.copyDecided, "문구는 대표 결정으로 정해졌다(#d_4wR1Qzn9OKmt) — copyDecided 가 false 로 돌아가면 출시 게이트가 다시 잠긴다")
    }

    /// 출시 게이트(검토 지적 — 가안 문구는 게이트를 지나 판에 실린다: 위 시험은 가안을 적어 둘 뿐이라 가안이 나가도 초록이다).
    /// 산타 코드가 든 맥 판은 받는 창 · 잠긴 칸 안내를 싣는다(서버 행이 들어오면 잠긴 칸은 모두가 본다). 그래서 문구가 정해지기 전에
    /// 맥 버전을 0.3.86(산타 전 마지막 판) 다음으로 올리면 여기가 빨갛다 — 문구를 정하거나, 그 판에서 산타를 빼야 낸다.
    /// 정해진 뒤(`SantaGiftText.copyDecided` true)에는 임시 표시 셋이 `SantaGift.swift` · `CharacterGiftCopy.santa` 주석에서 걷혔는지 본다.
    @Test("santaGiftCopyDecidedBeforeNextRelease — 문구가 정해지기 전엔 0.3.86 다음 맥 판을 못 낸다 · 정해지면 임시 표시가 걷혔다")
    func santaGiftCopyDecidedBeforeNextRelease() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        let key = "<key>CFBundleShortVersionString</key><string>"
        let start = try #require(squashed.range(of: key)).upperBound
        let end = try #require(squashed[start...].range(of: "</string>")).lowerBound
        let version = String(squashed[start..<end])
        let parts = version.split(separator: ".").map { Int($0) }
        try #require(parts.count == 3 && parts.allSatisfy { $0 != nil }, "맥 버전 '\(version)' 을 못 읽었다")
        let beyondLastSantaFreeRelease = [0, 3, 86].lexicographicallyPrecedes(parts.compactMap { $0 })

        let markers = ["가안", "결정 대기", "출시 전 교체"]
        let source = try String(contentsOf: root.appendingPathComponent("Sources/CheckCore/SantaGift.swift"), encoding: .utf8)
        let copyLines = try String(contentsOf: root.appendingPathComponent("Sources/CheckCore/CharacterGift.swift"), encoding: .utf8)
            .components(separatedBy: "\n").filter { $0.contains("산타") || $0.contains("SantaGiftText") }
        #expect(!copyLines.isEmpty, "CharacterGiftCopy.santa 줄을 못 찾았다 — 표시 검사가 눈이 멀었다")
        if SantaGiftText.copyDecided {
            for marker in markers {
                #expect(!source.contains(marker), "문구가 정해졌는데 SantaGift.swift 에 임시 표시 '\(marker)' 가 남았다")
                #expect(!copyLines.contains { $0.contains(marker) }, "문구가 정해졌는데 CharacterGiftCopy.santa 주석에 '\(marker)' 가 남았다")
            }
        } else {
            #expect(source.contains("출시 전 교체"), "copyDecided 가 false 인데 SantaGift.swift 의 임시 표시가 없다 — 값과 주석이 어긋났다")
            #expect(!beyondLastSantaFreeRelease,
                    "맥 버전 \(version): 산타 아잉이 문구가 아직 가안이다(대표 결정 대기) — 문구를 정해 SantaGiftText 를 바꾸고 copyDecided 를 true 로 하거나, 이 판에서 산타를 뺀다")
        }
    }
}

// MARK: - 맥 3D

@MainActor @Suite struct SantaAingMac3DTests {
    static let santa = CharacterCatalog.builtInSantaAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_SANTA_AING_EVIDENCE_DIR"]

    static let decorNames = ["check.santa.pompom", "check.santa.mustacheR", "check.santa.mustacheL", "check.santa.nose", "check.santa.bootR",
                             "check.santa.bootL", "check.santa.sleeveR", "check.santa.cuffR", "check.santa.mittenR", "check.santa.sleeveL",
                             "check.santa.cuffL", "check.santa.mittenL"]

    @Test("씬: 몸 = 팔 접기 칸(1 · 2) + 무지개 합성 + 산타 셰이더 + ckShadeMap · 장식 열둘(장식 판정) · 표식 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.santa)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == SantaAingShader.fragment(), "산타 셰이더가 안 걸렸다")
        #expect(material.shaderModifiers?[.geometry] == SantaAingShader.geometry)
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil)
        let shade = try #require(material.value(forKey: SantaAingShader.shadeMapKey) as? SCNMaterialProperty)
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage())
        // 팔 접기: 칸 0(원래 UV) 뒤에 칸 1 · 2 가 붙고, 접힌 정점(팔)이 있다.
        let body = try V0381DevAingMac3DTests.bodyGeometry(scene)
        let texcoords = body.sources(for: .texcoord)
        #expect(texcoords.count == 3, "텍스처 좌표 칸이 \(texcoords.count) — 팔 접기 굽기가 안 실렸다")
        let baked = try #require(SantaAingFinish.baked(for: body))
        #expect(baked.count == body.sources(for: .vertex).first?.vectorCount)
        #expect(baked.fold.contains { $0 > 0.9 } && baked.displacement.contains { simd_length($0) > 0.1 }, "접힌 팔 정점이 없다")
        #expect(SantaAingFinish.isSanta(character))
        let decor = try #require(scene.rootNode.childNode(withName: SantaAingFinish.decorNodeName, recursively: true))
        #expect(decor.childNodes.map(\.name) == Self.decorNames)
        #expect(decor.childNodes.allSatisfy(AingDecor.isDecor))
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInDevAing, CharacterCatalog.builtInBusanAing] {
            let s = try V0354GoldAing3DTests.scene(other)
            #expect(!SantaAingFinish.isSanta(try V0354GoldAing3DTests.character(s)), "\(other.id) 에 산타 표식")
            #expect(s.rootNode.childNode(withName: SantaAingFinish.decorNodeName, recursively: true) == nil, "\(other.id) 에 산타 장식")
        }
    }

    @Test("렌더: 배 아래는 빨강 · 가슴은 흰 수염 · 얼굴은 살구빛 · 장화는 검정 · 털 방울은 흰색 — 셰이더 없으면 배가 보라")
    func rendersSanta() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.santa)
        let image = try V0359Rainbow3DTests.render(scene, size: Self.appSize)
        let px = V0354GoldAingArtTests.rgba(image)
        let w = image.width
        let character = try V0354GoldAing3DTests.character(scene)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        func pixel(_ local: SCNVector3) -> (Int, Int) {
            let p = renderer.projectPoint(character.convertPosition(local, to: nil))
            return (Int(p.x.rounded()), Int((Self.appSize.height - p.y).rounded()))
        }
        func oklch(_ img: [UInt8], _ local: SCNVector3) -> (L: Double, C: Double, h: Double) {
            let c = V0359Rainbow3DTests.averageColor(img, width: w, at: pixel(local), radius: 1)
            return V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        }
        let belly = oklch(px, SCNVector3(0.45, -0.42, 0.52))
        let beard = oklch(px, SCNVector3(0.0, -0.05, 0.73))
        let face = oklch(px, SCNVector3(0.0, 0.52, 0.58))
        let boot = oklch(px, SCNVector3(0.25, -0.80, 0.48))
        let pompom = oklch(px, SCNVector3(0.0, 1.0, 0.0))
        print(String(format: "[santa-aing] 배 L %.2f C %.3f h %.0f° · 수염 L %.2f C %.3f · 얼굴 L %.2f C %.3f h %.0f° · 장화 L %.2f · 방울 L %.2f C %.3f",
                     belly.L, belly.C, belly.h, beard.L, beard.C, face.L, face.C, face.h, boot.L, pompom.L, pompom.C))
        #expect(belly.C > 0.12 && V0359RainbowArtTests.hueDistance(belly.h, 25) < 25, "배가 산타 빨강이 아니다(\(belly))")
        #expect(beard.L > 0.80 && beard.C < 0.05, "가슴이 흰 수염이 아니다(\(beard))")
        #expect(face.L > 0.80 && face.C > 0.02 && V0359RainbowArtTests.hueDistance(face.h, 50) < 35, "얼굴이 살구빛이 아니다(\(face))")
        #expect(boot.L < 0.35, "장화가 검정이 아니다(\(boot))")
        #expect(pompom.L > 0.85 && pompom.C < 0.04, "털 방울이 흰색이 아니다(\(pompom))")
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        let plainBelly = oklch(plain, SCNVector3(0.45, -0.42, 0.52))
        #expect(V0359RainbowArtTests.hueDistance(plainBelly.h, 25) > 60, "기준선: 셰이더 없는 배가 이미 빨강이다(\(plainBelly))")
        if Self.evidenceDirectory != nil { try Self.write(image, "santa-front-app-size.png") }
    }

    @Test("엔진은 산타 아잉이를 가른다 — 아잉 → 산타 교체(울트라 경로)에 셰이더 · 팔 접기 · 장식 · 표식이 따라오고 원복하면 사라진다")
    func engineSwaps() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: Self.santa, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.santaAingID, "\(engine.currentCharacterID)")
        #expect(scene.rootNode.childNode(withName: SantaAingFinish.decorNodeName, recursively: true) != nil)
        #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.fragment] == SantaAingShader.fragment())
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
        #expect(scene.rootNode.childNode(withName: SantaAingFinish.decorNodeName, recursively: true) == nil)
    }

    @Test("그릴 수 있다: 번들 그대로 산타가 든다 → 능력 번호 11 · 산타가 빠지면 10 · 초상 URL · 192²")
    func drawable() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.santaAingID), "\(drawable)")
        #expect(SantaAingFinish.isDrawable())
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.santaProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == ShopWire.santaProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.santaAingID }) == ShopWire.regionProtocol)
        #expect(V0317ShopTests.plainStore().shopProtocolVersion == ShopWire.santaProtocol, "맥 상점 · 선물 조회가 11 을 싣는다")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.santaAingID, mood: .neutral)?.lastPathComponent == "aing_santa-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.santaAingID, mood: .negative)?.lastPathComponent == "aing_santa-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.santaAingID)?.size.width == 192)
        #expect(CheckMascotAssets.image(for: .negative, characterID: CharacterCatalog.santaAingID)?.size.width == 192)
    }

    // MARK: 프레이밍(검토 지적 — 머리말 ★ 프레이밍은 부유 쉼 자세만 맞댔고, 울트라 자세는 아무도 안 쟀다)

    @Test("프레이밍: 부유 꼭대기(요 0 · ±40°)에서 털 방울이 프레임 안(위 ≥ 0.02) · 울트라는 엔진이 산타 자세(내려 세움)를 골라 rage 양 끝 · 임팩트 스트레치에서도 위 ≥ 0.02 · 아래 ≥ 0.1 — 기본 자세면 스트레치에서 털 방울이 잘린다(기준선)")
    func framingKeepsThePompomInside() throws {
        // ① 부유(쉼 · 꼭대기 +0.07) — 케이크 · 빼빼로와 같은 잣대(위 ≥ 0.02). 쉼 · 부유는 내려 세우지 않는다.
        for yaw in [0.0, 40.0, -40.0] {
            let up = try V0366CakeMac3DTests.frame(Self.santa, float: true, yawDegrees: yaw)
            let rest = try V0366CakeMac3DTests.frame(Self.santa, float: false, yawDegrees: yaw)
            print(String(format: "[santa-aing] 부유 요 %.0f°: 꼭대기 위 %.3f · 쉼 아래 %.3f", yaw, up.top, rest.bottom))
            #expect(up.top >= 0.02, "요 \(yaw)°: 부유 꼭대기에서 털 방울 위 여유 \(up.top) — 잘린다")
            #expect(rest.bottom >= 0.2, "요 \(yaw)°: 쉼 자세 장화 아래 여유 \(rest.bottom)")
        }

        // ② 울트라 — 엔진이 산타에 산타 자세를 고른다(기울기 · 흔들림은 기본 그대로, 내려 세우기만 더한다). 다른 캐릭터 자세는 그대로.
        let scene = try V0354GoldAing3DTests.scene(Self.santa)
        let wrapper = try V0354GoldAing3DTests.wrapper(scene)
        let engine = ReactionEngine()
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
        #expect(engine.currentCharacterID == CharacterCatalog.santaAingID && engine.ultraRagePose == .santa, "엔진이 산타 자세를 안 고른다 — \(engine.ultraRagePose)")
        let santaPose = ReactionActions.UltraRagePose.santa, standard = ReactionActions.UltraRagePose.standard
        #expect(santaPose.tiltX == standard.tiltX && santaPose.rollZ == standard.rollZ && santaPose.lift == standard.lift && santaPose.drop > 0,
                "산타 자세는 기본 기울기 · 흔들림에 내려 세우기만 더한다 — \(santaPose)")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInIsulAing, CharacterCatalog.builtInBusanAing] {
            let s = try V0354GoldAing3DTests.scene(other)
            let e = ReactionEngine()
            e.attach(node: try V0354GoldAing3DTests.wrapper(s), sceneRoot: s.rootNode, view: nil)
            #expect(e.ultraRagePose == .standard, "\(other.id) 의 격발 자세가 바뀌었다")
        }
        // 내려 세우기는 moveBy 쌍이라 5초 뒤 제자리 · 총 길이 5초 그대로(빼빼로와 같은 액션 길).
        #expect(abs(ReactionActions.ultraPoked(extent: 1.921, pose: .santa).duration - 5.0) < 0.001)

        let (lo, hi) = AingDecor.bodyBoundingBox(of: wrapper)
        let extent = CGFloat(max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z)))
        var shots: [String: V0377PeperoReviewFixTests.Shot] = [:]
        for (label, pose) in [("santa", santaPose), ("standard", standard)] {
            for (name, euler, scale, position) in V0377PeperoReviewFixTests.ragePoses(pose, extent: extent) {
                wrapper.eulerAngles = euler
                wrapper.scale = scale
                wrapper.position = position
                for size in [CGSize(width: 280, height: 340), CGSize(width: 945, height: 945)] {
                    let image = try V0359Rainbow3DTests.render(scene, size: size)
                    let s = V0377PeperoReviewFixTests.shot(image)
                    shots["\(label)-\(name)-\(Int(size.width))"] = s
                    print(String(format: "[santa-aing] 울트라 %@ %@ %d: 위 %.3f · 아래 %.3f", label, name, Int(size.width), s.top, s.bottom))
                    if Self.evidenceDirectory != nil { try Self.write(image, "santa-ultra-\(label)-\(name)-\(Int(size.width)).png") }
                }
            }
        }
        wrapper.eulerAngles = SCNVector3(0, 0, 0)
        wrapper.scale = SCNVector3(1, 1, 1)
        wrapper.position = SCNVector3(0, 0, 0)
        for size in [280, 945] {
            for name in ["plus", "minus", "stretch"] {
                let s = try #require(shots["santa-\(name)-\(size)"])
                #expect(s.top >= 0.02, "산타 격발 \(name) \(size): 위 여백 \(s.top) — 털 방울이 프레임 위로 잘린다")
                #expect(s.bottom >= 0.1, "산타 격발 \(name) \(size): 아래 여백 \(s.bottom) — 장화가 프레임 아래로 나간다")
            }
            // 기준선: 기본 자세면 임팩트 스트레치에서 털 방울이 위 가장자리에 닿는다(실측 0.000 — 투영으로는 프레임 높이의 0.042 넘는다).
            // 이것이 안 나오면 위 재기가 눈이 멀었거나 내려 세우기가 필요 없어졌다.
            let undropped = try #require(shots["standard-stretch-\(size)"])
            #expect(undropped.top < 0.005, "기준선: 기본 자세 스트레치 \(size) 위 여백 \(undropped.top) — 잘림을 못 잰다")
        }
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉 나란히)", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let big = CGSize(width: 560, height: 680)
        for (tag, manifest) in [("santa", Self.santa), ("aing", CharacterCatalog.builtInAing)] {
            let scene = try V0354GoldAing3DTests.scene(manifest)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-1-front.png")
            let facing = try V0355GoldHaloYawTests.facing(scene)
            facing.eulerAngles = SCNVector3(0, CGFloat(35.0 * .pi / 180), 0)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-2-three-quarter.png")
            facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-3-back.png")
            facing.eulerAngles = SCNVector3(0, 0, 0)
            let material = try V0359Rainbow3DTests.faceMaterial(scene)
            let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            let closed = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: try V0381DevAingMac3DTests.bodyGeometry(scene),
                                                                               character: try V0354GoldAing3DTests.character(scene)))
            material.diffuse.contents = closed
            for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = false }
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-4-closed-eyes.png")
            let engine = ReactionEngine()
            let from = try V0354GoldAing3DTests.scene(tag == "aing" ? Self.santa : CharacterCatalog.builtInAing)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(from), sceneRoot: from.rootNode, view: nil)
            _ = try #require(engine.swapCharacter(to: manifest, in: from))
            try Self.write(try V0359Rainbow3DTests.render(from, size: big), "\(tag)-5-ultra-swap.png")
        }
    }
}
