import Foundation
import simd

// MARK: - 개발에 찌든 아잉이 (제보 11-08 · 시안 D2 '후드티 개발자')
//
// 제보(11-08) "'개발에 찌든 아잉이'가 갖고 싶어요" → 대표(11-10) "개발에 찌든 아잉이 에셋 시안 여러개 뽑아보자. 이거 구현해야겠어" →
// 시안 #d_NuLS5imieQds "D2 후드티 개발자". 원래 보라 아잉이 몸매 그대로 + 회색 후드티(머리까지 · 얼굴만 뚫림 · 캥거루 주머니) + 흰 끈 둘 +
// 다크서클 + 졸린 눈꺼풀. 시안 렌더러 `~/.claude/projects/-Users-yesung-check/dev-aing/parts-dev.swift.txt`(devHoodie · devDarkCircles ·
// devSleepyLids · devHoodStrings)의 식을 앱 몸 셰이더(`DevAingFinish`)와 초상 생성기(`scripts/make-dev-aing.swift`)가 같은 글자로 쓴다.
// 이 파일은 Foundation · simd 만 쓴다 — 생성기가 이 파일만 같이 컴파일한다.

/// 개발에 찌든 아잉이 그림 파일 이름 · "그릴 수 있다"의 판정. **파일 이름을 적는 곳은 여기 하나다.**
package nonisolated enum DevAingArt {
    package static let characterID = "aing_dev"
    package static let resourceExtension = "png"

    /// 초상(192×192). 이름 규칙은 `<id>-<표정>`.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 재료 — 무지개와 같이 쓰는 라벤더 밝기 맵(디퓨즈 합성 · 셰이더 인자 ckShadeMap). 후드 · 끈은 코드가 만든다.
    package static let shadeResourceName = "aing_rainbow-shade"
    package static var finishResourceNames: [String] { [shadeResourceName] }

    package enum Platform: Sendable { case mac, phone }

    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }

    // MARK: 후드 끈(장식 노드) — 얼굴 구멍 아래(y −0.07) 앞면 두 점에서 늘어진 흰 끈 + 끝 매듭.
    package static let stringXs: [Float] = [-0.11, 0.11]
    package static let stringTopY: Float = -0.07
    package static let stringLength: Float = 0.26
    package static let stringRadius: Float = 0.009
    package static let stringTipRadius: Float = 0.016
    package static let stringColor = 0xECEDF2
}

/// 개발에 찌든 아잉이 몸 셰이더. 틀(β 얼굴 지키기 · 타원체 법선 · sRGB 섞기 · 피부 텍셀은 몸 색 그대로)은 루비 `RubyAingShader` 와 같고,
/// 무늬가 보라 몸 + 후드 + 주머니 + 다크서클 + 졸린 눈꺼풀이다. 눈꺼풀은 얼굴 그림(눈)을 **덮어야** 해서 출력 끝에 덮개 칠(ckLid)을 더한다.
package nonisolated enum DevAingShader {
    package static let bodyTop = 0.848950
    package static let bodyHeight = 1.695736
    package static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
    package static let skinYRef = 0.56530
    package static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    package static let shadeMapKey = "ckShadeMap"

    // 색(sRGB 16진) — 시안 D2.
    package static let bodyColor = 0xCFBAFE        // 원래 보라
    package static let hoodColor = 0x8E929E        // 회색 후드
    package static let hoodTrim = 0x6F7380         // 얼굴 구멍 테
    package static let pocketColor = 0x7E8290      // 캥거루 주머니
    package static let darkCircleColor = 0x56428C
    package static let lashColor = 0x3B2A4E
    /// 눈 가운데(물체 x, y) — 앱 감은 눈 앵커와 같은 자리.
    package static let eyes: [(Double, Double)] = [(-0.270, 0.418), (0.250, 0.434)]
    /// 눈꺼풀이 덮는 몫(위에서부터) · 바깥 꼬리 처짐.
    package static let lidCover = 0.38
    package static let lidDroop = 0.25

    static func f5(_ v: Double) -> String { String(format: "%.5f", v) }
    static func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func f5hex(_ hex: Int) -> String {
        f5v(SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255)))
    }

    package static let geometry = """
    #pragma varyings
    float3 ckVP;
    float2 ckUV;
    float3 ckVN;
    float3 ckVE;
    #pragma body
    out.ckVP = _geometry.position.xyz;
    out.ckVE = (scn_node.modelViewTransform * float4(_geometry.position.xyz, 1.0)).xyz;
    out.ckUV = _geometry.texcoords[0];
    float3 ckG = (_geometry.position.xyz - float3(0.0, 0.001, 0.0)) / (\(f5v(ellipsoid)) * \(f5v(ellipsoid)));
    out.ckVN = (scn_node.normalTransform * float4(ckG, 0.0)).xyz;
    """

    /// 보라 몸(원래 아잉 색 + 은은한 반짝).
    static let purple = """
    ckBase = \(f5hex(bodyColor));
    ckShadeMix = 1.0;
    {
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float g1 = pow(max(dot(ckVn, L), 0.0), 90.0);
        float g2 = pow(max(dot(ckVn, L), 0.0), 9.0);
        float rim = pow(1.0 - ckNV, 3.0);
        float hiF = 1.0 - 0.85 * ckFace;
        ckAdd += float3(1.0, 0.97, 1.0) * (g1 * 0.55 + g2 * 0.06) * hiF;
        ckAdd += \(f5hex(0xA88BFF)) * rim * 0.10;
    }
    """

    /// 후드: 몸 전체(얼굴 구멍만 뺌) 회색 천 + 구멍 테 + 배 앞 캥거루 주머니(박음질).
    static let hood = """
    {
        float hx = ckP.x / 0.50;
        float hy = (ckP.y - 0.30) / 0.36;
        float d = hx * hx + hy * hy;
        float front = smoothstep(0.0, 0.18, ckP.z);
        float aaD = max(fwidth(d), 1e-4);
        float open = (1.0 - smoothstep(1.0 - aaD, 1.0 + aaD, d)) * front;
        float hood = 1.0 - open;
        float trimK = (1.0 - smoothstep(1.16 - aaD, 1.16 + aaD, d)) * front * hood;
        float3 hc = \(f5hex(hoodColor));
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float sh = pow(max(dot(ckVn, L), 0.0), 6.0);
        hc = hc * (0.95 + 0.25 * sh);
        ckBase = mix(ckBase, mix(hc, \(f5hex(hoodTrim)), trimK), hood);
        ckAdd *= 1.0 - hood * 0.85;
        ckAdd += float3(1.0) * pow(1.0 - ckNV, 3.0) * 0.06 * hood;
        ckShadeMix = mix(ckShadeMix, 0.9, hood);
    }
    {
        float2 q = float2(ckP.x / 0.34, (ckP.y + 0.47) / 0.15);
        float d = max(abs(q.x), abs(q.y));
        float front = smoothstep(0.30, 0.45, ckP.z);
        float aa = max(fwidth(d), 1e-4);
        float inside = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * front;
        float stitch = (1.0 - smoothstep(0.0, 0.035, abs(d - 0.93))) * front * step(0.5, fract((ckP.x + ckP.y) * 38.0));
        ckBase = mix(ckBase, \(f5hex(pocketColor)), inside * 0.9);
        ckBase = mix(ckBase, ckBase * 0.70, stitch * inside);
    }
    """

    /// 다크서클: 눈 아래 그늘 + 눈 밑 반달 선(피부에만 — 눈 그림은 β 로 지켜진다).
    static var darkCircles: String {
        var s = "{\n    float dc = 0.0;\n"
        for (ex, ey) in eyes {
            s += """
                {
                    float2 q = float2((ckP.x - (\(f5(ex)))) / 0.150, (ckP.y - (\(f5(ey - 0.120)))) / 0.068);
                    float d = dot(q, q);
                    dc = max(dc, 0.55 * (1.0 - smoothstep(0.15, 1.0, d)) * smoothstep(0.25, 0.40, ckP.z));
                    float2 r = float2((ckP.x - (\(f5(ex)))) / 0.125, (ckP.y - (\(f5(ey - 0.010)))) / 0.130);
                    float rr = length(r);
                    float aa = max(fwidth(rr), 1e-4);
                    float band = smoothstep(1.10 - aa, 1.10 + aa, rr) * (1.0 - smoothstep(1.24 - aa, 1.24 + aa, rr));
                    float lower = smoothstep(-0.25, -0.55, r.y / max(rr, 1e-3)) * (1.0 - smoothstep(0.80, 0.98, abs(r.x) / max(rr, 1e-3)));
                    dc = max(dc, band * lower * smoothstep(0.25, 0.40, ckP.z));
                }

            """
        }
        s += "    ckBase = mix(ckBase, \(f5hex(darkCircleColor)), dc * 0.85);\n}\n"
        return s
    }

    /// 졸린 눈꺼풀: 눈 위쪽 lidCover 만큼을 피부로 덮고(ckLid) 가장자리에 속눈썹 선. 선은 **눈 그림이 있는 텍셀에만**(1 − β) —
    /// 감은 눈(깜빡임 · 졸기 텍스처)에서는 눈 그림이 피부로 덮여 선이 저절로 사라진다(감은 눈 선 판과 두 줄이 되지 않게).
    static var sleepyLids: String {
        var s = """
        {
            float3 lidSkin = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
            float lidA = 0.0, lineA = 0.0;

        """
        for (i, (ex, ey)) in eyes.enumerated() {
            let out = i == 0 ? -1.0 : 1.0
            s += """
                {
                    float rx = 0.118, ry = 0.135;
                    float2 e = float2((ckP.x - (\(f5(ex)))) / rx, (ckP.y - (\(f5(ey)))) / ry);
                    float inEye = (1.0 - smoothstep(0.95, 1.15, dot(e, e))) * smoothstep(0.25, 0.40, ckP.z);
                    float outer = clamp((ckP.x - (\(f5(ex)))) * \(f5(out)) / rx, 0.0, 1.0);
                    float edge = \(f5(ey)) + ry * (1.0 - 2.0 * \(f5(lidCover))) - \(f5(lidDroop)) * ry * outer * outer;
                    float aa = max(fwidth(ckP.y), 1e-4);
                    float above = smoothstep(edge - aa, edge + aa, ckP.y);
                    lidA = max(lidA, inEye * above);
                    float lw = 0.011;
                    float ln = (1.0 - smoothstep(lw - aa, lw + aa, abs(ckP.y - edge))) * (1.0 - smoothstep(1.00, 1.20, dot(e, e))) * smoothstep(0.25, 0.40, ckP.z);
                    lineA = max(lineA, ln);
                }

            """
        }
        s += """
            lineA *= clamp(1.0 - ckBeta, 0.0, 1.0);
            ckLidCol = mix(clamp(lidSkin, float3(0.0), float3(1.0)), \(f5hex(lashColor)), lineA);
            ckLid = max(lidA, lineA);
        }

        """
        return s
    }

    package static var pattern: String { purple + hood + darkCircles + sleepyLids }

    /// 몸 출력 — 루비와 같은 식 + 끝에 눈꺼풀 덮개(ckLid — 얼굴 그림까지 덮는다). `faceOff` = 얼굴 상자를 끈다(초상 생성기의 '얼굴 없는 몸').
    package static func bodyOutput(faceOff: Bool = false) -> String {
        """
        float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
        bool ckInFace = \(faceOff ? "false" : "ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62");
        float ckB = ckInFace ? ckBeta : 1.0;
        float3 ckCc = clamp(ckCol, float3(0.0), float3(1.0));
        float3 ckCe = 255.0 * select(1.055 * pow(ckCc, float3(1.0 / 2.4)) - 0.055, ckCc * 12.92, ckCc <= float3(0.0031308));
        float3 ckOe = clamp((\(faceOff ? "ckSe" : "ckPe") + ckB * (ckCe - ckSe)) / 255.0, float3(0.0), float3(1.0));
        float ckSkinish = (1.0 - smoothstep(10.0, 28.0, length(ckDv))) * ckB;
        ckOe = mix(ckOe, ckCe / 255.0, ckSkinish);
        float3 ckOut = select(pow((ckOe + 0.055) / 1.055, float3(2.4)), ckOe / 12.92, ckOe <= float3(0.04045));
        ckOut = mix(ckOut, ckLidCol.x < 0.0 ? ckCc : ckLidCol, clamp(ckLid, 0.0, 1.0));
        _output.color = float4(ckOut, 1.0);
        """
    }

    package static func fragment(faceOff: Bool = false) -> String {
        """
        #pragma arguments
        texture2d<float> ckShadeMap;
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        float3 ckVN;
        float3 ckVE;
        #pragma body
        constexpr sampler ckSmp(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
        float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 ckSL = clamp(ckShadeMap.sample(ckSmp, in.ckUV).rgb, float3(0.0), float3(1.0));
        float3 ckPe = 255.0 * select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
        float3 ckSe = 255.0 * select(1.055 * pow(ckSL, float3(1.0 / 2.4)) - 0.055, ckSL * 12.92, ckSL <= float3(0.0031308));
        float3 ckDv = ckPe - ckSe;
        float3 ckKs = \(String(format: "float3(%.2f, %.2f, %.2f)", blushSRGB.x, blushSRGB.y, blushSRGB.z)) - ckSe;
        float ckAk = dot(ckDv, ckKs) / max(1e-6, dot(ckKs, ckKs));
        float ckRes = length(ckDv - clamp(ckAk, 0.0, 1.0) * ckKs);
        float3 ckAd = ckDv / min(-ckSe, float3(-1e-3));
        float3 ckAb = ckDv / max(float3(255.0) - ckSe, float3(1e-3));
        float3 ckAc = select(ckAb, ckAd, ckDv < float3(0.0));
        float ckCover = clamp(max(ckAc.r, max(ckAc.g, ckAc.b)), 0.0, 1.0);
        float3 ckF = ckSe + ckDv / max(ckCover, 1e-3);
        float ckFY = dot(ckF, float3(0.299, 0.587, 0.114)) / 255.0;
        float ckFm = min(ckF.r, min(ckF.g, ckF.b)) / 255.0;
        float ckTrust = max(1.0 - smoothstep(0.19, 0.25, ckFY), smoothstep(0.88, 0.95, ckFm));
        float ckOld = clamp(1.0 - length(ckDv) / 80.0, 0.0, 1.0);
        float ckBeta = (ckRes <= 20.0 && ckAk > -0.1 && ckAk < 1.1) ? 1.0 - clamp(ckAk, 0.0, 1.0) : mix(ckOld, 1.0 - ckCover, ckTrust);
        float ckShade = clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f5(skinYRef)), 0.40, 1.45);
        float3 ckP = in.ckVP;
        float3 ckVn = normalize(in.ckVN);
        float3 ckEye = normalize(-in.ckVE);
        float ckNV = min(abs(dot(ckVn, ckEye)), 1.0);
        float ckFx = ckP.x / 0.60;
        float ckFy = (ckP.y - 0.34) / 0.30;
        float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckShadeMix = 1.0;
        float ckLid = 0.0;
        float3 ckLidCol = float3(-1.0);
        \(pattern)
        \(bodyOutput(faceOff: faceOff))
        """
    }
}

// MARK: - 얻는 길 — 도전 미션 '누적 근무 100시간'(v0.3.81 · 대표 #d_OwYy6Avg5alV)

/// 개발에 찌든 아잉이를 얻는 미션의 문구 · 계약 값(순수 — 맥 · 폰이 같은 글자를 쓴다). 서버 정본은
/// `20261111120000_aing_dev_mission.sql`(정의표 `achievement_character_defs()` · 받기 `achievement_character_claim`).
/// 대표 원문: "미션보상으로 가자. 총 누적근무시간 100시간 이상달성. (이미 달성한 사람들은 바로 받는걸로.)"
package enum DevAingMission {
    /// 서버 정의표의 키 — 받기 요청이 싣는다(줄 제목 · 목표는 응답이 말한다).
    package static let key = "work100"
    /// 상점 · 고르기 잠긴 칸의 아래 줄(자물쇠 옆).
    package static let lockedCaption = "미션 보상"
    /// 잠긴 칸을 눌렀을 때 · 말풍선 — 얻는 길.
    package static let lockedHint = "누적 미션 '누적 근무 100시간'을 채우면 받아요"
    /// 미션 줄의 진행 숫자("37/100시간").
    package static func count(progress: Int, target: Int) -> String { "\(max(0, progress))/\(max(1, target))시간" }
    /// 받기 성공 한 줄(미션 화면 안내줄 — 캐릭터는 [캐릭터]에서 입는다).
    package static func received(name: String) -> String { "\(name)를 받았어요! [캐릭터]에서 입어 보세요" }
    /// 받기 버튼 보이스오버("받기, 개발에 찌든 아잉이").
    package static func claimAccessibility(name: String) -> String { "받기, \(name)" }
}
