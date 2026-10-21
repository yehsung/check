#!/usr/bin/env swift
// 아잉이 이모티콘 그림 8장 굽기 (v0.3.62) — 말풍선 한 칸을 통째로 차지하는 512² 스티커.
//
// 사용법(저장소 어디서 불러도 된다 — 경로는 이 파일 위치에서 잡는다):
//   swift scripts/bake-aing-stickers.swift                     8장을 Sources/CheckCore/Resources/Stickers/ 에 덮어쓴다.
//   swift scripts/bake-aing-stickers.swift --sheet <폴더>       위에 더해 대조 시트 2장(밝은·어두운 배경)을 <폴더> 에 쓴다.
//   swift scripts/bake-aing-stickers.swift --dry-run <폴더>     저장소는 **안 건드리고** 8장을 <폴더> 에만 쓴다(시안 검토용).
//   (실측: 약 12초. `swift <파일>` 로 혼자 돈다 — 패키지 빌드(.build)를 전혀 건드리지 않는다.)
//
// ── 왜 이 그림을 3D 에서 굽는가 ────────────────────────────────────────────────────────────────────
// 아잉이 그림의 출처는 셋이다: 3D 모델(`aing.scn`) · 192² 초상 PNG 2장(`aing-neutral` / `aing-negative`) ·
// 스프라이트 아틀라스(다른 캐릭터들). 512² 스티커를 192² 초상에서 키우면 2.7배 확대라 뭉개진다. 그래서
// **오버레이·미니게임과 같은 3D 모델을 같은 구도로 오프스크린 렌더**한다. 카메라 숫자(FOV 40 · 위로
// 0.55×extent · 시선 아래로 0.16×extent · 거리 여유 1.4배)와 unlit(`.constant`) 재질은
// `CheckCharacter3DScene.addFramingCamera` / `applyUnlitMaterials` 그대로다 — 여기서 조명을 켜거나 구도를
// 새로 잡으면 대화창 아잉이가 바탕화면 아잉이와 다른 물건이 된다.
//
// ── 표정 8종을 어떻게 만드나 ───────────────────────────────────────────────────────────────────────
// 3D 에셋에는 **얼굴이 하나뿐이다**(눈 뜬 웃는 얼굴. 192² 초상의 시무룩은 평면 그림이라 3D 에 못 쓴다).
// 그래서 감정은 셋이 나른다:
//   ① 자세 — `CheckOverlayReactions.ReactionActions` 의 리액션 **정점 자세**를 그대로 가져온다
//      (폴짝 도약 스트레치 · 꾸벅 인사 x+20° · 졸기 가라앉기 x+14° · 부풀린 찌부 …). 앱이 이미 쓰는 어휘다.
//   ② 소품 — Core Graphics 로 직접 그린다. **이모지 글자를 박지 않는다**(폰트마다 다르게 나오고 애플
//      이모지는 재배포 문제가 있다). 하트·눈물·별·느낌표·💢·Z 전부 아래 경로 함수다.
//   ③ 얼굴 고치기 — 눈썹을 **더하고**(원래 눈썹이 없는 얼굴이라 덧그리기만 하면 된다), 졸림·놀람·슬픔·화남은
//      눈/입을 피부색으로 덮고 다시 그린다. 덮기는 `SleepEyeTexture` 의 발상(경계 피부에서 안으로 번지는
//      인페인트)을 **화면 좌표에서** 한 판이다 — UV 아틀라스가 저폴리라 눈 한쪽이 여러 조각으로 흩어져 있어
//      텍스처 공간에서 손대면 조각을 쫓아다녀야 하지만, 렌더된 그림에서는 타원 하나면 된다.
//
// 얼굴 좌표는 **매 장 렌더로 잰다**. 자세마다 얼굴이 기울고 멀어지므로 상수를 박으면 눈썹이 이마에서
// 떠다닌다. 굽기 전에 눈 2개·입 1개 자리에 원색 마커(빨강·초록·파랑, 빌보드·깊이 무시)를 꽂고 저해상 렌더로
// 무게중심을 재서 '얼굴 프레임'(눈축 u · 아래축 v · 눈 간격 sep)을 만든 뒤 마커를 빼고 본 렌더를 찍는다.
// 모든 얼굴 좌표·소품 좌표는 이 프레임의 (u, v) 로 적혀 있어 자세가 기울면 같이 기운다.
//
// ── 8장이 같은 카메라·같은 스케일이라는 계약 ────────────────────────────────────────────────────────
// 프레이밍(wrapper 의 배율·위치)은 **중립 자세에서 한 번** 수렴시키고 8장이 그 값을 공유한다
// (`MiniGameMascot.fitCharacterIntoFrame` 과 같은 수렴법, 목표 채움은 소품 자리를 남기려 0.62).
// 장마다 다시 맞추면 큰 소품이 붙은 장만 캐릭터가 작아져 대화창에서 들쭉날쭉해진다.
// 자세가 주는 위치·배율 차이는 **일부러 남긴 것**이다(도약은 위로, 졸기는 아래로) — 다만 ±0.08 모델 단위
// (≈13px) 안으로 묶는다. 굽기 끝에 8장의 알파 경계 상자를 찍으니 그 숫자로 확인하라.
//
// 산출물: Sources/CheckCore/Resources/Stickers/sticker-{joy,heart,sad,angry,sleepy,surprised}.png
//        512×512 · 투명 배경 · 장당 200KB 미만.

import AppKit
import CoreGraphics
import Metal
import SceneKit

// MARK: - 경로·인자

let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let modelURL = repoRoot.appendingPathComponent("Sources/check/Resources/aing.scn")
let stickerDir = repoRoot.appendingPathComponent("Sources/CheckCore/Resources/Stickers")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("bake-aing-stickers: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var sheetDir: URL?
var dryRunDir: URL?
do {
    var args = Array(CommandLine.arguments.dropFirst())
    while let arg = args.first {
        args.removeFirst()
        switch arg {
        case "--sheet":
            guard let path = args.first else { fail("--sheet 뒤에 폴더가 없다") }
            args.removeFirst(); sheetDir = URL(fileURLWithPath: path)
        case "--dry-run":
            guard let path = args.first else { fail("--dry-run 뒤에 폴더가 없다") }
            args.removeFirst(); dryRunDir = URL(fileURLWithPath: path)
        default:
            fail("모르는 인자: \(arg)")
        }
    }
}

// MARK: - 색 (앱에서 쓰는 값)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}
/// 가챠 창 라이트 테마 ink(`CheckGachaWindow` #6A4FC8). 선·Z·효과선의 기본색.
let inkPurple = srgb(0x6A4FC8)
/// 한 톤 밝은 보라 — 어두운 배경에서도 뜨게.
let litePurple = srgb(0x8B6BEF)
/// 색종이·하트의 분홍(앱 confetti 는 `NSColor.systemPink`).
let pink = srgb(0xFF6FA5)
let deepPink = srgb(0xE84C86)
/// 미니게임 금(#FFD24A) — 별·반짝임.
let gold = srgb(0xFFD24A)
let amber = srgb(0xF2A33C)
/// 눈물·물방울.
let sky = srgb(0x5BC8F5)
/// 💢 — 성남 표식.
let angerRed = srgb(0xF2485B)
/// 속눈썹처럼 진한 자주-검정(`CheckCharacter3DScene.closedEyeLineImage` 와 같은 색).
let lashInk = CGColor(srgbRed: 0.19, green: 0.12, blue: 0.17, alpha: 1)
/// 입 안쪽(렌더 실측 평균에 가까운 적갈색).
let mouthInk = srgb(0x8E2A3A)
/// 소품 테두리(흰 테) — 어두운 배경에서 보라·자주 소품이 묻히지 않게 두른다.
let haloWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)

// MARK: - 얼굴 프레임
//
// 마커 3개(눈 왼·오·입)의 화소 좌표로 만든 좌표계. (u, v) 는 **눈 간격(sep) 단위**이고 v 는 아래가 +.
// 자세가 기울면 축도 같이 기운다. 기준선(중립 자세 512² 렌더) 실측:
//   마커 눈왼 (199.5, 209.5) · 눈오 (306.5, 205.5) · 입 (253.5, 246.5) · sep 107.1 · 입거리/sep 0.364
//   홍채 중심 u=-0.397/+0.443 (v≈0.01) · 홍채 반지름 rx 0.30 ry 0.25 · 입 중심 u=-0.013 v=0.341
struct FaceFrame {
    let mid: CGPoint        // 두 눈 마커의 중점(화소, y 는 위가 +인 CG 좌표)
    let axis: CGVector      // 왼눈→오른눈 단위벡터
    let down: CGVector      // 입 방향 단위벡터(얼굴의 '아래')
    let sep: CGFloat        // 눈 간격(화소)

    /// (u, v) → 화소. u 는 눈축, v 는 아래축. 둘 다 sep 배율.
    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: mid.x + axis.dx * u * sep + down.dx * v * sep,
                y: mid.y + axis.dy * u * sep + down.dy * v * sep)
    }
    /// sep 배수를 화소 길이로.
    func len(_ s: CGFloat) -> CGFloat { s * sep }
    /// 얼굴 기울기(라디안) — 눈축이 수평에서 얼마나 돌았나. 눈썹·눈물 같은 소품을 같이 기울일 때 쓴다.
    var tilt: CGFloat { atan2(axis.dy, axis.dx) }
}

/// 홍채 중심의 프레임 좌표(실측). 좌우가 살짝 비대칭인 것은 모델이 정확히 좌우대칭이 아니어서다 —
/// 대칭으로 반올림하면 한쪽 눈 덮개가 0.5px 씩 어긋난다.
let irisLeftUV = CGPoint(x: -0.397, y: 0.009)
let irisRightUV = CGPoint(x: 0.443, y: 0.020)
let mouthUV = CGPoint(x: -0.013, y: 0.341)

// MARK: - 그리기 도우미

/// 흰 테를 두르고 채운다. 어두운 배경에서도 소품이 보이게 하는 장치다(캐릭터 본체는 연보라라 원래 보인다).
func glyph(_ ctx: CGContext, _ path: CGPath, fill: CGColor, halo: CGFloat = 5, haloColor: CGColor = haloWhite) {
    if halo > 0 {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(haloColor)
        ctx.setLineWidth(halo)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
}

/// 선을 긋는다(흰 테 포함).
func stroke(_ ctx: CGContext, _ path: CGPath, color: CGColor, width: CGFloat, halo: CGFloat = 4) {
    if halo > 0 {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(haloWhite)
        ctx.setLineWidth(width + halo)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func transformed(_ path: CGPath, _ t: CGAffineTransform) -> CGPath {
    var m = t
    return path.copy(using: &m) ?? path
}

/// 하트. 위 두 둥근 혹 + 아래 뾰족한 끝. size 는 가로폭.
func heartPath(center: CGPoint, size: CGFloat, angle: CGFloat = 0) -> CGPath {
    let w = size, h = size * 0.92
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -h * 0.5))                                   // 아래 끝
    p.addCurve(to: CGPoint(x: -w * 0.5, y: h * 0.18),
               control1: CGPoint(x: -w * 0.28, y: -h * 0.18),
               control2: CGPoint(x: -w * 0.5, y: -h * 0.02))
    p.addCurve(to: CGPoint(x: 0, y: h * 0.30),
               control1: CGPoint(x: -w * 0.5, y: h * 0.44),
               control2: CGPoint(x: -w * 0.18, y: h * 0.50))
    p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.18),
               control1: CGPoint(x: w * 0.18, y: h * 0.50),
               control2: CGPoint(x: w * 0.5, y: h * 0.44))
    p.addCurve(to: CGPoint(x: 0, y: -h * 0.5),
               control1: CGPoint(x: w * 0.5, y: -h * 0.02),
               control2: CGPoint(x: w * 0.28, y: -h * 0.18))
    p.closeSubpath()
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// 네 갈래 반짝임(✨ 모양) — 변이 오목한 별. r 은 긴 갈래 반지름.
func sparklePath(center: CGPoint, r: CGFloat, angle: CGFloat = 0, waist: CGFloat = 0.22) -> CGPath {
    let p = CGMutablePath()
    let k = r * waist
    p.move(to: CGPoint(x: 0, y: r))
    p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: k, y: k))
    p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: k, y: -k))
    p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -k, y: -k))
    p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: -k, y: k))
    p.closeSubpath()
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// 다섯 갈래 별.
func starPath(center: CGPoint, r: CGFloat, inner: CGFloat = 0.45, angle: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<10 {
        let rad = (i % 2 == 0) ? r : r * inner
        let a = .pi / 2 + CGFloat(i) * .pi / 5
        let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// 눈물 한 방울(위가 뾰족한 물방울).
func teardropPath(center: CGPoint, w: CGFloat, h: CGFloat, angle: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: h * 0.5))
    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: -h * 0.12), control: CGPoint(x: w * 0.30, y: h * 0.10))
    p.addQuadCurve(to: CGPoint(x: 0, y: -h * 0.5), control: CGPoint(x: w * 0.5, y: -h * 0.42))
    p.addQuadCurve(to: CGPoint(x: -w * 0.5, y: -h * 0.12), control: CGPoint(x: -w * 0.5, y: -h * 0.42))
    p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.5), control: CGPoint(x: -w * 0.30, y: h * 0.10))
    p.closeSubpath()
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// 💢 — 네 귀퉁이가 꺾인 성남 표식. 쐐기 4개를 90°씩 돌려 모은다(이모지 글자를 쓰지 않는다).
func angerMarkPath(center: CGPoint, size: CGFloat, angle: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    let s = size / 2
    for i in 0..<4 {
        let a = angle + CGFloat(i) * .pi / 2
        let t = CGAffineTransform(rotationAngle: a).concatenating(
            CGAffineTransform(translationX: center.x, y: center.y))
        let wedge = CGMutablePath()
        wedge.move(to: CGPoint(x: -s * 0.86, y: s * 0.30))
        wedge.addLine(to: CGPoint(x: -s * 0.30, y: s * 0.86))
        wedge.addLine(to: CGPoint(x: -s * 0.30, y: s * 0.46))
        wedge.addLine(to: CGPoint(x: -s * 0.46, y: s * 0.30))
        wedge.closeSubpath()
        p.addPath(wedge, transform: t)
    }
    return p
}

/// Z 한 글자(획 셋을 이은 선). 폰트를 쓰지 않는다 — 굽는 머신의 글꼴에 그림이 끌려가지 않게.
func zPath(center: CGPoint, size: CGFloat, angle: CGFloat = 0) -> CGPath {
    let s = size / 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -s, y: s))
    p.addLine(to: CGPoint(x: s, y: s))
    p.addLine(to: CGPoint(x: -s, y: -s))
    p.addLine(to: CGPoint(x: s, y: -s))
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// ❗ — 아래로 가늘어지는 막대 + 점.
func bangPath(center: CGPoint, height: CGFloat, angle: CGFloat = 0) -> (bar: CGPath, dot: CGPath) {
    let h = height, w = height * 0.26
    let bar = CGMutablePath()
    bar.move(to: CGPoint(x: -w * 0.5, y: h * 0.5))
    bar.addLine(to: CGPoint(x: w * 0.5, y: h * 0.5))
    bar.addLine(to: CGPoint(x: w * 0.22, y: -h * 0.12))
    bar.addLine(to: CGPoint(x: -w * 0.22, y: -h * 0.12))
    bar.closeSubpath()
    let dot = CGPath(ellipseIn: CGRect(x: -w * 0.30, y: -h * 0.50, width: w * 0.60, height: w * 0.60), transform: nil)
    let t = CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y))
    return (transformed(bar, t), transformed(dot, t))
}

/// 음표(머리 + 기둥 + 깃발).
func notePath(center: CGPoint, size: CGFloat, angle: CGFloat = 0) -> CGPath {
    let s = size
    let p = CGMutablePath()
    p.addEllipse(in: CGRect(x: -s * 0.46, y: -s * 0.56, width: s * 0.62, height: s * 0.46))
    let stem = CGMutablePath()
    stem.addRect(CGRect(x: s * 0.04, y: -s * 0.38, width: s * 0.12, height: s * 0.92))
    p.addPath(stem)
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: s * 0.16, y: s * 0.54))
    flag.addQuadCurve(to: CGPoint(x: s * 0.52, y: s * 0.10),
                      control: CGPoint(x: s * 0.56, y: s * 0.48))
    flag.addQuadCurve(to: CGPoint(x: s * 0.16, y: s * 0.30),
                      control: CGPoint(x: s * 0.36, y: s * 0.22))
    flag.closeSubpath()
    p.addPath(flag)
    return transformed(p, CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y)))
}

/// 효과선(가운데에서 방사). 놀람에 쓴다.
/// (`thumbsUpPaths`·`mittenPaths`·`notePath` 는 지금 아무도 안 쓴다 — 2026-10-21 에 뺀 `굿`·`박수` 의
///  소품이다. 지우지 않고 두는 이유는 그 둘을 되살리라는 말이 나오면 그림부터 다시 구워야 하기 때문이다.)
func burstPaths(center: CGPoint, count: Int, inner: CGFloat, outer: CGFloat,
                from: CGFloat = 0, to: CGFloat = .pi * 2, jitter: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<count {
        let f = count == 1 ? 0 : CGFloat(i) / CGFloat(count - 1)
        let a = from + (to - from) * f
        let r0 = inner * (1 + jitter * CGFloat((i % 3) - 1) * 0.1)
        let r1 = outer * (1 + jitter * CGFloat((i % 2) == 0 ? 1 : -1) * 0.12)
        p.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
        p.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
    }
    return p
}

/// 엄지 척 — 주먹(둥근 사각) + 위로 솟은 엄지(캡슐) + 손가락 마디 선. 피부색은 캐릭터와 같은 연보라.
/// 손이 없는 캐릭터라 **몸 옆에 떠 있는 손**으로 그린다(앱의 스프라이트 캐릭터들도 손이 몸에서 떨어져 있다).
func thumbsUpPaths(center: CGPoint, size: CGFloat, angle: CGFloat = 0) -> (fist: CGPath, thumb: CGPath, knuckles: CGPath) {
    let s = size
    let fist = CGPath(roundedRect: CGRect(x: -s * 0.40, y: -s * 0.48, width: s * 0.80, height: s * 0.74),
                      cornerWidth: s * 0.26, cornerHeight: s * 0.26, transform: nil)
    let thumb = CGPath(roundedRect: CGRect(x: -s * 0.38, y: s * 0.04, width: s * 0.32, height: s * 0.66),
                       cornerWidth: s * 0.16, cornerHeight: s * 0.16, transform: nil)
    let knuckles = CGMutablePath()
    for i in 0..<3 {
        let y = -s * 0.34 + CGFloat(i) * s * 0.22
        knuckles.move(to: CGPoint(x: -s * 0.12, y: y))
        knuckles.addLine(to: CGPoint(x: s * 0.26, y: y))
    }
    let t = CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y))
    return (transformed(fist, t), transformed(thumb, t), transformed(knuckles, t))
}

/// 박수 손 한 짝(손바닥 + 손가락 선). `mirror` 가 −1 이면 왼손.
func mittenPaths(center: CGPoint, size: CGFloat, angle: CGFloat, mirror: CGFloat) -> (palm: CGPath, fingers: CGPath) {
    let s = size
    let palm = CGPath(roundedRect: CGRect(x: -s * 0.36, y: -s * 0.44, width: s * 0.72, height: s * 0.88),
                      cornerWidth: s * 0.30, cornerHeight: s * 0.30, transform: nil)
    let fingers = CGMutablePath()
    for i in 0..<3 {
        let y = -s * 0.18 + CGFloat(i) * s * 0.24
        fingers.move(to: CGPoint(x: mirror * s * 0.02, y: y))
        fingers.addLine(to: CGPoint(x: mirror * s * 0.26, y: y))
    }
    let t = CGAffineTransform(rotationAngle: angle).concatenating(
        CGAffineTransform(translationX: center.x, y: center.y))
    return (transformed(palm, t), transformed(fingers, t))
}

// MARK: - 얼굴 고치기(덮기 + 다시 그리기)

/// 타원 안을 **경계 피부색으로 번지게** 채운다(눈·입 지우개).
///
/// `SleepEyeTexture` 가 텍스처에서 하는 '경계에서 안으로 번지는 평균 인페인트'를 화면 좌표에서 한 판이다.
/// 각 화소는 같은 행의 좌·우 경계색과 같은 열의 위·아래 경계색을 **거리 역수 가중 평균**으로 섞는다 —
/// 라벤더 피부가 매끈한 그라디언트라 이 한 겹이면 이음새가 보이지 않는다(단색으로 칠하면 동그란 자국이 남는다).
///
/// 함정 둘을 막아 둔다(1차 시안에서 실제로 났다):
/// ① **표본이 피부여야 한다.** 타원을 눈 그림자에 딱 맞춰 잡으면 경계 표본이 홍채 테두리라 어두운 색이
///    안으로 번져 네모난 얼룩이 생긴다. `isSkin` 으로 거르고(어두움·붉음·흰 하이라이트 배제) 아니면 그 방향으로
///    최대 `reach` 만큼 더 나가 찾는다. 네 방향이 다 실패하면 그 화소는 건드리지 않는다.
/// ② **가장자리는 섞는다.** 바깥 20% 구간에서 원본과 선형으로 섞어 타원 테두리가 선으로 보이지 않게 한다.
/// 읽기는 원본 사본에서, 쓰기는 ctx 에 한다(쓴 값을 다시 읽어 번지지 않게).
func inpaintEllipse(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat) {
    guard let base = ctx.data else { return }
    let w = ctx.width, h = ctx.height, rowBytes = ctx.bytesPerRow
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let total = rowBytes * h
    var source = [UInt8](repeating: 0, count: total)
    source.withUnsafeMutableBufferPointer { buffer in
        buffer.baseAddress!.update(from: bytes, count: total)
    }
    // CG 좌표(y 위) → 메모리 행(y 아래).
    let cx = Double(center.x), cy = Double(CGFloat(h) - center.y)
    let a = Double(rx), b = Double(ry)
    /// 라벤더 피부인가. 어두운 것(홍채·입 안쪽)·붉은 것(입술·볼터치)·흰 것(눈 하이라이트)을 모두 뺀다.
    /// 피부는 언제나 파랑이 초록보다 높다(실측 (230,214,249) · (209,193,254)) — 흰 하이라이트는 그 차가 0 이라 걸린다.
    func isSkin(_ s: (Double, Double, Double, Double)) -> Bool {
        let luma = 0.299 * s.0 + 0.587 * s.1 + 0.114 * s.2
        return s.3 > 240 && luma > 140 && (s.0 - s.1) < 34 && (s.2 - s.1) > 6
    }
    func pixel(_ x: Int, _ y: Int) -> (Double, Double, Double, Double)? {
        guard x >= 0, x < w, y >= 0, y < h else { return nil }
        let i = y * rowBytes + x * 4
        return (Double(source[i]), Double(source[i + 1]), Double(source[i + 2]), Double(source[i + 3]))
    }
    /// (x, y) 에서 (dx, dy) 방향으로 피부가 나올 때까지 걷는다. 못 찾으면 nil.
    func walk(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, reach: Int = 16) -> (color: (Double, Double, Double, Double), distance: Double)? {
        var px = x, py = y
        for step in 1...reach {
            px += dx; py += dy
            guard let c = pixel(px, py) else { return nil }
            if isSkin(c) { return (c, Double(step)) }
        }
        return nil
    }
    let y0 = max(0, Int(cy - b) - 1), y1 = min(h - 1, Int(cy + b) + 1)
    let x0 = max(0, Int(cx - a) - 1), x1 = min(w - 1, Int(cx + a) + 1)
    for y in y0...y1 {
        for x in x0...x1 {
            let u = (Double(x) - cx) / a, v = (Double(y) - cy) / b
            let d2 = u * u + v * v
            guard d2 <= 1 else { continue }
            // 이 행의 좌우 경계 · 이 열의 위아래 경계(타원 밖 2px 부터 피부를 찾는다).
            let halfX = a * (1 - v * v).squareRoot(), halfY = b * (1 - u * u).squareRoot()
            let xl = Int((cx - halfX).rounded()) - 2, xr = Int((cx + halfX).rounded()) + 2
            let yt = Int((cy - halfY).rounded()) - 2, yb = Int((cy + halfY).rounded()) + 2
            var acc = (r: 0.0, g: 0.0, b: 0.0, a: 0.0, w: 0.0)
            func add(_ found: (color: (Double, Double, Double, Double), distance: Double)?, _ gap: Double) {
                guard let found else { return }
                let weight = 1.0 / max(gap + found.distance, 1.0)
                acc.r += found.color.0 * weight; acc.g += found.color.1 * weight
                acc.b += found.color.2 * weight; acc.a += found.color.3 * weight
                acc.w += weight
            }
            add(walk(xl + 1, y, -1, 0), Double(x - xl))
            add(walk(xr - 1, y, 1, 0), Double(xr - x))
            add(walk(x, yt + 1, 0, -1), Double(y - yt))
            add(walk(x, yb - 1, 0, 1), Double(yb - y))
            guard acc.w > 0 else { continue }
            // 바깥 20% 는 원본과 섞어 테두리를 지운다.
            let blend = min(1.0, (1.0 - d2.squareRoot()) / 0.20)
            let i = y * rowBytes + x * 4
            func mix(_ fresh: Double, _ old: UInt8) -> UInt8 {
                UInt8(max(0, min(255, (fresh * blend + Double(old) * (1 - blend)).rounded())))
            }
            bytes[i] = mix(acc.r / acc.w, source[i])
            bytes[i + 1] = mix(acc.g / acc.w, source[i + 1])
            bytes[i + 2] = mix(acc.b / acc.w, source[i + 2])
            bytes[i + 3] = mix(acc.a / acc.w, source[i + 3])
        }
    }
}

/// 두 눈을 지운다(덮개 반지름은 홍채 실측 + 여유).
func eraseEyes(_ ctx: CGContext, _ face: FaceFrame) {
    for uv in [irisLeftUV, irisRightUV] {
        inpaintEllipse(ctx, center: face.point(uv.x, uv.y), rx: face.len(0.42), ry: face.len(0.37))
    }
}

/// 입을 지운다.
func eraseMouth(_ ctx: CGContext, _ face: FaceFrame) {
    inpaintEllipse(ctx, center: face.point(mouthUV.x, mouthUV.y), rx: face.len(0.32), ry: face.len(0.25))
}

/// 감은 눈 두 줄(ᵕ — 가운데가 내려앉은 눈웃음). `closedEyeLineImage` 와 같은 모양·같은 색이다.
func drawClosedEyes(_ ctx: CGContext, _ face: FaceFrame, droop: CGFloat = 0) {
    for uv in [irisLeftUV, irisRightUV] {
        let c = face.point(uv.x, uv.y + droop)
        let half = face.len(0.24)
        let dip = face.len(0.12)
        let p = CGMutablePath()
        let left = CGPoint(x: c.x - face.axis.dx * half, y: c.y - face.axis.dy * half)
        let right = CGPoint(x: c.x + face.axis.dx * half, y: c.y + face.axis.dy * half)
        let control = CGPoint(x: c.x + face.down.dx * dip * 2, y: c.y + face.down.dy * dip * 2)
        p.move(to: left)
        p.addQuadCurve(to: right, control: control)
        stroke(ctx, p, color: lashInk, width: face.len(0.075), halo: 0)
    }
}

/// 눈썹 두 줄. `slope` 가 +면 안쪽 끝이 올라간다(슬픔 ╱╲), −면 안쪽이 내려온다(화남 ╲╱).
/// `lift` 는 눈 위로 얼마나 띄울지(sep 단위).
func drawBrows(_ ctx: CGContext, _ face: FaceFrame, slope: CGFloat, lift: CGFloat, length: CGFloat = 0.30,
               width: CGFloat = 0.065, color: CGColor = lashInk) {
    for (index, uv) in [irisLeftUV, irisRightUV].enumerated() {
        let inward: CGFloat = index == 0 ? 1 : -1      // 얼굴 안쪽 방향(왼눈은 +u 쪽이 안쪽)
        let c = face.point(uv.x, uv.y - lift)
        let half = face.len(length / 2)
        let rise = face.len(slope)
        let inner = CGPoint(x: c.x + face.axis.dx * half * inward - face.down.dx * rise,
                            y: c.y + face.axis.dy * half * inward - face.down.dy * rise)
        let outer = CGPoint(x: c.x - face.axis.dx * half * inward + face.down.dx * rise * 0.35,
                            y: c.y - face.axis.dy * half * inward + face.down.dy * rise * 0.35)
        let mid = CGPoint(x: (inner.x + outer.x) / 2 - face.down.dx * face.len(0.04),
                          y: (inner.y + outer.y) / 2 - face.down.dy * face.len(0.04))
        let p = CGMutablePath()
        p.move(to: outer)
        p.addQuadCurve(to: inner, control: mid)
        stroke(ctx, p, color: color, width: face.len(width), halo: 0)
    }
}

/// 입을 다시 그린다. `curve` 가 −면 찡그린 입(∩), +면 웃는 입(∪). `open` 이 0 보다 크면 벌린 입(타원).
func drawMouth(_ ctx: CGContext, _ face: FaceFrame, curve: CGFloat, width: CGFloat = 0.30, thickness: CGFloat = 0.07,
               openWidth: CGFloat = 0, openHeight: CGFloat = 0) {
    let c = face.point(mouthUV.x, mouthUV.y)
    if openWidth > 0 {
        // 벌린 입(놀람) — 타원 하나. 바깥은 어두운 입술색, 안쪽은 그대로 둬 단순하게.
        let w = face.len(openWidth), h = face.len(openHeight)
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        let t = CGAffineTransform(rotationAngle: face.tilt).concatenating(
            CGAffineTransform(translationX: c.x, y: c.y))
        glyph(ctx, transformed(p, t), fill: mouthInk, halo: 0)
        return
    }
    let half = face.len(width / 2)
    let dip = face.len(curve)
    let left = CGPoint(x: c.x - face.axis.dx * half, y: c.y - face.axis.dy * half)
    let right = CGPoint(x: c.x + face.axis.dx * half, y: c.y + face.axis.dy * half)
    let control = CGPoint(x: c.x + face.down.dx * dip * 2, y: c.y + face.down.dy * dip * 2)
    let p = CGMutablePath()
    p.move(to: left)
    p.addQuadCurve(to: right, control: control)
    stroke(ctx, p, color: mouthInk, width: face.len(thickness), halo: 0)
}

// MARK: - 씬 세우기(앱과 같은 구도)

guard let device = MTLCreateSystemDefaultDevice() else { fail("Metal 장치가 없다 — 오프스크린 렌더를 못 한다") }
guard FileManager.default.fileExists(atPath: modelURL.path) else { fail("모델이 없다: \(modelURL.path)") }
let scene: SCNScene
do { scene = try SCNScene(url: modelURL, options: nil) } catch { fail("모델 로드 실패: \(error)") }
scene.background.contents = nil
// 앱 `applyUnlitMaterials` 와 같은 한 줄. 기본 조명에서는 텍스처가 허옇게 떠 마스코트 보라가 사라진다.
// (리샘플은 하지 않는다 — .scn 은 이미 512 로 구워져 있다.)
scene.rootNode.enumerateHierarchy { node, _ in
    node.geometry?.materials.forEach { $0.lightingModel = .constant }
}
guard let character = scene.rootNode.childNodes.first else { fail("캐릭터 노드가 없다") }

// 오버레이와 같은 골격: wrapper(프레이밍) → facing(자세) → character.
let wrapper = SCNNode(), facing = SCNNode()
character.removeFromParentNode()
facing.addChildNode(character)
wrapper.addChildNode(facing)
scene.rootNode.addChildNode(wrapper)

let (minB, maxB) = wrapper.boundingBox
let bodyCenter = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
let modelExtent = CGFloat(max(maxB.x - minB.x, maxB.y - minB.y))
let fieldOfView: CGFloat = 40
let cameraNode = SCNNode()
do {
    let camera = SCNCamera()
    camera.fieldOfView = fieldOfView
    // 정사각 렌더에서 자동 판정에 맡기면 macOS 버전에 따라 가로/세로 기준이 갈린다 — 못 박는다(MiniGameMascot 과 같은 이유).
    camera.projectionDirection = .vertical
    camera.zNear = 0.01
    camera.zFar = 1_000
    cameraNode.camera = camera
    let distance = modelExtent / (2 * tan(fieldOfView / 2 * .pi / 180)) * 1.4
    cameraNode.position = SCNVector3(bodyCenter.x, bodyCenter.y + modelExtent * 0.55, CGFloat(maxB.z) + distance)
    cameraNode.look(at: SCNVector3(bodyCenter.x, bodyCenter.y - modelExtent * 0.16, bodyCenter.z))
    scene.rootNode.addChildNode(cameraNode)
}

let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false

func render(_ side: CGFloat, antialiased: Bool) -> CGImage {
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side),
                                  antialiasingMode: antialiased ? .multisampling4X : .none)
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("렌더 실패") }
    return cg
}

/// 알파가 있는 화소의 경계 상자(정규화, 원점 좌하단). 비었으면 nil.
func alphaBox(_ cg: CGImage) -> CGRect? {
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let base = ctx.data else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var minX = w, maxX = -1, minRow = h, maxRow = -1
    for row in 0..<h {
        let offset = row * ctx.bytesPerRow
        for x in 0..<w where bytes[offset + x * 4 + 3] > 24 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if row < minRow { minRow = row }
            if row > maxRow { maxRow = row }
        }
    }
    guard maxX >= minX, maxRow >= minRow else { return nil }
    return CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(h - 1 - maxRow) / CGFloat(h),
                  width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxRow - minRow + 1) / CGFloat(h))
}

// 프레이밍 수렴 — **중립 자세에서 한 번만**. 8장이 이 배율·위치를 공유한다(위 머리말의 계약).
let targetFill: CGFloat = 0.62
do {
    let modelWidth = CGFloat(maxB.x - minB.x), modelHeight = CGFloat(maxB.y - minB.y)
    var scale: CGFloat = 1
    var offset = CGPoint.zero
    for _ in 0..<4 {
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.position = SCNVector3(offset.x, offset.y, 0)
        guard let box = alphaBox(render(96, antialiased: false)) else { fail("프레이밍 프로브가 비었다") }
        offset.x -= (box.midX - 0.5) * modelWidth * scale / box.width
        offset.y -= (box.midY - 0.5) * modelHeight * scale / box.height
        scale = min(max(scale * (targetFill / max(box.width, box.height)), 0.02), 50)
    }
    wrapper.scale = SCNVector3(scale, scale, scale)
    wrapper.position = SCNVector3(offset.x, offset.y, 0)
    print(String(format: "[프레이밍] 배율 %.4f 오프셋 (%.4f, %.4f) 목표채움 %.2f", scale, offset.x, offset.y, targetFill))
}

// MARK: - 얼굴 마커로 프레임 재기

/// 마커 앵커(모델 좌표). 눈 둘은 앱 `closedEyeAnchors` 자리(z 를 0.05 앞으로 — 표면에 묻히지 않게),
/// 입은 렌더로 맞춘 자리다(실측: 중립 512² 에서 입 중심과 1px 안).
let markerAnchors: [(SCNVector3, (CGFloat, CGFloat, CGFloat))] = [
    (SCNVector3(-0.277, 0.418, 0.581), (1, 0, 0)),
    (SCNVector3(0.250, 0.434, 0.576), (0, 1, 0)),
    (SCNVector3(-0.013, 0.218, 0.550), (0, 0, 1))
]

func makeMarkerNodes() -> [SCNNode] {
    markerAnchors.map { anchor, rgb in
        let plane = SCNPlane(width: 0.04, height: 0.04)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = anchor
        node.renderingOrder = 50
        // 빌보드라 자세가 기울어도 마커가 선으로 찌그러지지 않는다(무게중심을 안정되게 잡으려고).
        node.constraints = [SCNBillboardConstraint()]
        return node
    }
}

/// 마커를 꽂은 저해상 렌더에서 세 점의 무게중심을 재 얼굴 프레임을 만든다.
func measureFace(side: CGFloat) -> FaceFrame {
    let nodes = makeMarkerNodes()
    nodes.forEach { character.addChildNode($0) }
    defer { nodes.forEach { $0.removeFromParentNode() } }
    let cg = render(side, antialiased: false)
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let base = ctx.data else { fail("마커 측정 비트맵 실패") }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var sums = [(x: 0.0, y: 0.0, n: 0.0), (x: 0.0, y: 0.0, n: 0.0), (x: 0.0, y: 0.0, n: 0.0)]
    for row in 0..<h {
        for x in 0..<w {
            let i = row * ctx.bytesPerRow + x * 4
            let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2]), a = Double(bytes[i + 3])
            guard a > 200 else { continue }
            var index: Int? = nil
            if r > 180, g < 70, b < 70 { index = 0 }
            if g > 180, r < 70, b < 70 { index = 1 }
            if b > 180, r < 70, g < 70 { index = 2 }
            guard let index else { continue }
            sums[index].x += Double(x); sums[index].y += Double(row); sums[index].n += 1
        }
    }
    var points = [CGPoint]()
    for (index, s) in sums.enumerated() {
        guard s.n > 0 else { fail("마커 \(index) 가 안 보인다 — 자세가 얼굴을 돌려 버렸나?") }
        // 메모리 행(위가 0) → CG 좌표(아래가 0).
        points.append(CGPoint(x: CGFloat(s.x / s.n), y: CGFloat(h) - CGFloat(s.y / s.n)))
    }
    let left = points[0], right = points[1], mouth = points[2]
    let mid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
    let sep = hypot(right.x - left.x, right.y - left.y)
    guard sep > 1 else { fail("눈 간격이 0 이다") }
    let axis = CGVector(dx: (right.x - left.x) / sep, dy: (right.y - left.y) / sep)
    let dv = CGVector(dx: mouth.x - mid.x, dy: mouth.y - mid.y)
    let dlen = hypot(dv.dx, dv.dy)
    guard dlen > 1 else { fail("입 거리가 0 이다") }
    let down = CGVector(dx: dv.dx / dlen, dy: dv.dy / dlen)
    return FaceFrame(mid: mid, axis: axis, down: down, sep: sep)
}

// MARK: - 자세

struct Pose {
    var euler = SCNVector3(0, 0, 0)            // 라디안 — x+ 는 앞으로 꾸벅, z+ 는 화면상 반시계
    var position = SCNVector3(0, 0, 0)         // 모델 단위
    var scale = SCNVector3(1, 1, 1)
}
func degrees(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

/// 웃는 눈(∪ — 위로 휜 활). 기쁨·박수에서 뜬 눈을 이것으로 갈아 끼운다.
func drawHappyEyes(_ ctx: CGContext, _ face: FaceFrame) {
    for uv in [irisLeftUV, irisRightUV] {
        let c = face.point(uv.x, uv.y + 0.03)
        let half = face.len(0.26)
        let rise = face.len(0.17)
        let left = CGPoint(x: c.x - face.axis.dx * half, y: c.y - face.axis.dy * half)
        let right = CGPoint(x: c.x + face.axis.dx * half, y: c.y + face.axis.dy * half)
        let control = CGPoint(x: c.x - face.down.dx * rise * 2, y: c.y - face.down.dy * rise * 2)
        let p = CGMutablePath()
        p.move(to: left)
        p.addQuadCurve(to: right, control: control)
        stroke(ctx, p, color: lashInk, width: face.len(0.085), halo: 0)
    }
}

/// 하트 눈 — 홍채 자리에 하트 둘.
func drawHeartEyes(_ ctx: CGContext, _ face: FaceFrame) {
    for uv in [irisLeftUV, irisRightUV] {
        glyph(ctx, heartPath(center: face.point(uv.x, uv.y), size: face.len(0.46), angle: face.tilt),
              fill: deepPink, halo: 0)
    }
}

// MARK: - 스티커 표

/// 소품 그리기 단계. 몸 **뒤**(back)와 **앞**(front)을 갈라, 색종이는 뒤로 하트는 앞으로 보낸다.
typealias PropDraw = (CGContext, FaceFrame, CGFloat) -> Void   // (그릴 곳, 얼굴 프레임, 한 변 px)

struct Sticker {
    let id: String
    let label: String          // 대조 시트에 적을 한국어
    let pose: Pose
    var face: ((CGContext, FaceFrame) -> Void)? = nil
    var back: PropDraw? = nil
    var front: PropDraw? = nil
}

/// 색종이 한 장(기울어진 둥근 사각).
func confetti(_ ctx: CGContext, at p: CGPoint, size: CGFloat, angle: CGFloat, color: CGColor) {
    let rect = CGRect(x: -size / 2, y: -size * 0.35, width: size, height: size * 0.7)
    let path = CGPath(roundedRect: rect, cornerWidth: size * 0.16, cornerHeight: size * 0.16, transform: nil)
    glyph(ctx, transformed(path, CGAffineTransform(rotationAngle: angle)
        .concatenating(CGAffineTransform(translationX: p.x, y: p.y))), fill: color, halo: 2.5)
}

/// 화면 비율(0…1, y 는 위가 +) → 화소. **떠 있는 소품은 전부 이 좌표로 둔다.**
/// 얼굴 프레임(u, v)으로 두면 자세가 기울 때 같이 기우는 대신 프레임 밖으로 밀려 잘린다(1차 시안에서 실제로 잘렸다).
/// 얼굴에 붙은 것(눈썹·눈물·입)과 몸에 붙은 것(엄지·박수 손)만 프레임 좌표를 쓴다.
func at(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> CGPoint { CGPoint(x: x * side, y: y * side) }

let stickers: [Sticker] = [
    // ── 기쁨 — 도약 정점(goalAchieved 의 launch 0.88/1.24 를 스티커용으로 눅인 값) + 색종이 ──────────
    Sticker(
        id: "joy", label: "기쁨",
        pose: Pose(euler: SCNVector3(0, 0, 0),
                   position: SCNVector3(0, 0.07, 0),
                   scale: SCNVector3(0.93, 1.13, 0.93)),
        face: { ctx, face in
            // 활짝 웃는 눈(∪)으로 바꾼다 — 뜬 눈 + 웃는 입보다 '신난다'가 한눈에 읽힌다.
            eraseEyes(ctx, face)
            drawHappyEyes(ctx, face)
        },
        back: { ctx, _, side in
            let colors = [pink, gold, srgb(0x7ADBB5), litePurple, srgb(0xFF9F68)]
            let spots: [(CGFloat, CGFloat, CGFloat)] = [        // (x, y, 기울기) — 화면 비율
                (0.11, 0.86, 0.5), (0.27, 0.93, -0.9), (0.45, 0.955, 0.2),
                (0.70, 0.92, 1.1), (0.86, 0.845, -0.4), (0.075, 0.66, -1.2),
                (0.92, 0.63, 0.8), (0.14, 0.42, 0.3), (0.88, 0.37, -0.7)
            ]
            for (index, spot) in spots.enumerated() {
                confetti(ctx, at: at(spot.0, spot.1, side),
                         size: side * (index % 3 == 0 ? 0.052 : 0.042), angle: spot.2,
                         color: colors[index % colors.count])
            }
        },
        front: { ctx, _, side in
            // 머리 양옆 위로 솟는 반짝임 둘 — 도약의 방향을 거든다.
            glyph(ctx, sparklePath(center: at(0.175, 0.755, side), r: side * 0.055), fill: gold, halo: 4)
            glyph(ctx, sparklePath(center: at(0.845, 0.70, side), r: side * 0.040), fill: gold, halo: 3.5)
        }
    ),

    // ── 하트 — 살짝 기운 자세 + 하트 눈 + 떠오르는 하트 셋 ─────────────────────────────────────
    Sticker(
        id: "heart", label: "하트",
        pose: Pose(euler: SCNVector3(0, 0, degrees(7)),
                   position: SCNVector3(0, 0.01, 0),
                   scale: SCNVector3(1, 1, 1)),
        face: { ctx, face in
            eraseEyes(ctx, face)
            drawHeartEyes(ctx, face)
        },
        front: { ctx, _, side in
            glyph(ctx, heartPath(center: at(0.805, 0.80, side), size: side * 0.135, angle: -0.22), fill: pink, halo: 5)
            glyph(ctx, heartPath(center: at(0.895, 0.615, side), size: side * 0.080, angle: 0.25), fill: deepPink, halo: 4)
            glyph(ctx, heartPath(center: at(0.145, 0.735, side), size: side * 0.070, angle: 0.30), fill: pink, halo: 4)
        }
    ),


    // ── 슬픔 — 처진 자세(drowsySink 의 x+14° 와 같은 방향) + 시무룩 눈썹·입 + 눈물 ─────────────────
    Sticker(
        id: "sad", label: "슬픔",
        pose: Pose(euler: SCNVector3(degrees(11), 0, degrees(-3)),
                   position: SCNVector3(0, -0.05, 0),
                   scale: SCNVector3(1.04, 0.95, 1.04)),
        face: { ctx, face in
            eraseMouth(ctx, face)
            drawMouth(ctx, face, curve: -0.085, width: 0.26)
            // 눈썹은 **덧그리기**다(이 얼굴에는 원래 눈썹이 없다). 안쪽 끝이 올라간 ╱╲ 가 슬픔이다.
            drawBrows(ctx, face, slope: 0.17, lift: 0.46)
        },
        front: { ctx, face, side in
            // 눈물 두 방울 — 눈 아래에서 볼을 타고.
            glyph(ctx, teardropPath(center: face.point(0.60, 0.42), w: side * 0.055, h: side * 0.085,
                                    angle: face.tilt), fill: sky, halo: 3.5)
            glyph(ctx, teardropPath(center: face.point(-0.62, 0.30), w: side * 0.040, h: side * 0.062,
                                    angle: face.tilt), fill: sky, halo: 3)
        }
    ),

    // ── 화남 — 부풀려 눌러앉은 자세(ultraPoked 의 plus 1.14/0.88) + 💢 ──────────────────────────
    Sticker(
        id: "angry", label: "화남",
        pose: Pose(euler: SCNVector3(0, 0, 0),
                   position: SCNVector3(0, -0.02, 0),
                   scale: SCNVector3(1.12, 0.90, 1.12)),
        face: { ctx, face in
            eraseMouth(ctx, face)
            drawMouth(ctx, face, curve: -0.10, width: 0.28, thickness: 0.08)
            // 안쪽 끝이 내려온 ╲╱ 가 화남이다.
            drawBrows(ctx, face, slope: -0.19, lift: 0.44, length: 0.34, width: 0.075)
        },
        front: { ctx, _, side in
            glyph(ctx, angerMarkPath(center: at(0.805, 0.825, side), size: side * 0.150), fill: angerRed, halo: 5)
            glyph(ctx, angerMarkPath(center: at(0.155, 0.725, side), size: side * 0.090), fill: angerRed, halo: 4)
        }
    ),

    // ── 졸림 — 가라앉은 자세(drowsySink: x+14°·아래로) + 감은 눈 + Z Z Z ────────────────────────
    Sticker(
        id: "sleepy", label: "졸림",
        pose: Pose(euler: SCNVector3(degrees(13), 0, degrees(4)),
                   position: SCNVector3(0, -0.06, 0),
                   scale: SCNVector3(1.03, 0.97, 1.03)),
        face: { ctx, face in
            eraseEyes(ctx, face)
            eraseMouth(ctx, face)
            drawClosedEyes(ctx, face, droop: 0.05)
            drawMouth(ctx, face, curve: 0.03, width: 0.17, thickness: 0.055)
        },
        front: { ctx, _, side in
            // 머리 위 오른쪽 빈 코너에서 커지며 떠오르는 Z 셋(앱 spawnZzzBurst 와 같은 자리·같은 방향).
            let zs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [   // (x, y, 크기, 기울기) — 화면 비율
                (0.675, 0.715, 0.050, 0.10), (0.775, 0.805, 0.072, -0.12), (0.875, 0.900, 0.098, 0.14)
            ]
            for z in zs {
                stroke(ctx, zPath(center: at(z.0, z.1, side), size: side * z.2, angle: z.3),
                       color: litePurple, width: side * z.2 * 0.26, halo: side * z.2 * 0.17)
            }
        }
    ),

    // ── 놀람 — 화들짝 튀어오른 자세(poked 의 launch 0.90/1.22) + ❗ + 놀람선 ──────────────────────
    Sticker(
        id: "surprised", label: "놀람",
        pose: Pose(euler: SCNVector3(degrees(-4), 0, degrees(-5)),
                   position: SCNVector3(0, 0.06, 0),
                   scale: SCNVector3(0.91, 1.16, 0.91)),
        face: { ctx, face in
            eraseMouth(ctx, face)
            drawMouth(ctx, face, curve: 0, openWidth: 0.26, openHeight: 0.34)
            // 눈 위로 높이 치켜올린 눈썹(수평에 가깝게) — 놀람의 관용 기호다.
            drawBrows(ctx, face, slope: 0.03, lift: 0.60, length: 0.26, width: 0.060)
        },
        back: { ctx, _, side in
            // 머리 둘레 놀람선(위쪽 반원만).
            stroke(ctx, burstPaths(center: at(0.50, 0.575, side), count: 9,
                                   inner: side * 0.265, outer: side * 0.325,
                                   from: degrees(20), to: degrees(160)),
                   color: litePurple, width: side * 0.013, halo: 0)
        },
        front: { ctx, _, side in
            let (bar, dot) = bangPath(center: at(0.845, 0.835, side), height: side * 0.195, angle: 0.16)
            glyph(ctx, bar, fill: angerRed, halo: 5)
            glyph(ctx, dot, fill: angerRed, halo: 5)
        }
    ),

]

// MARK: - 굽기

func writePNG(_ cg: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG 인코딩 실패: \(url.path)") }
    do { try data.write(to: url) } catch { fail("쓰기 실패 \(url.path): \(error)") }
}

let outputSide: CGFloat = 512
/// 본 렌더는 2배(1024)로 찍어 512 로 줄인다 — MSAA 4x 만으로는 귀 끝·눈 테두리에 계단이 남는다.
let renderSide: CGFloat = 1024

struct Baked {
    let sticker: Sticker
    let image: CGImage
    let box: CGRect        // 알파 경계(정규화) — 소품 포함
    let bodyBox: CGRect    // 몸만(소품 합성 전 렌더) — '8장이 같은 배율'은 이 숫자로 본다
    let bytes: Int
}
var baked = [Baked]()

for sticker in stickers {
    facing.eulerAngles = sticker.pose.euler
    facing.position = sticker.pose.position
    facing.scale = sticker.pose.scale

    let face = measureFace(side: outputSide)
    let body = render(renderSide, antialiased: true)

    guard let ctx = CGContext(data: nil, width: Int(outputSide), height: Int(outputSide), bitsPerComponent: 8,
                              bytesPerRow: Int(outputSide) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("합성 비트맵 실패") }
    ctx.clear(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    sticker.back?(ctx, face, outputSide)
    ctx.draw(body, in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
    sticker.face?(ctx, face)
    sticker.front?(ctx, face, outputSide)
    guard let image = ctx.makeImage() else { fail("합성 이미지 실패") }

    let directory = dryRunDir ?? stickerDir
    if dryRunDir != nil {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let url = directory.appendingPathComponent("sticker-\(sticker.id).png")
    writePNG(image, to: url)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
    guard let box = alphaBox(image) else { fail("\(sticker.id): 알파가 비었다") }
    guard let bodyBox = alphaBox(body) else { fail("\(sticker.id): 몸 렌더가 비었다") }
    baked.append(Baked(sticker: sticker, image: image, box: box, bodyBox: bodyBox, bytes: bytes))
    print(String(format: "[%@] %@  전체 x %.3f…%.3f y %.3f…%.3f (폭 %.3f 높이 %.3f) · 몸만 폭 %.3f 높이 %.3f 중심 (%.3f, %.3f) · %d bytes",
                 sticker.id, sticker.label,
                 box.minX, box.maxX, box.minY, box.maxY, box.width, box.height,
                 bodyBox.width, bodyBox.height, bodyBox.midX, bodyBox.midY, bytes))
}

// 8장이 같은 크기인지 숫자로 확인(머리말의 계약). **몸만** 기준이다 — 소품까지 포함한 상자는
// 색종이가 많은 장이 당연히 크므로 배율 증거가 되지 못한다.
do {
    func spread(_ v: [CGFloat], _ label: String) {
        print(String(format: "[검사] %@ %.3f…%.3f (차 %.3f = %.1fpx)", label, v.min()!, v.max()!,
                     v.max()! - v.min()!, (v.max()! - v.min()!) * outputSide))
    }
    spread(baked.map { $0.bodyBox.width }, "몸 폭  ")
    spread(baked.map { $0.bodyBox.height }, "몸 높이")
    spread(baked.map { $0.bodyBox.midX }, "몸 중심x")
    spread(baked.map { $0.bodyBox.midY }, "몸 중심y")
    // 소품이 프레임 밖으로 새면 대화창에서 잘려 보인다(1차 시안에서 하트·Z·엄지가 실제로 잘렸다).
    let margin: CGFloat = 0.012
    let clipped = baked.filter { $0.box.minX < margin || $0.box.minY < margin
                                 || $0.box.maxX > 1 - margin || $0.box.maxY > 1 - margin }
    if clipped.isEmpty {
        print(String(format: "[검사] 8장 모두 사방 여백 %.1fpx 이상 — 잘린 소품 없음", margin * outputSide))
    } else {
        print("[경고] 프레임 가장자리에 닿은 장: " + clipped.map { $0.sticker.id }.joined(separator: ", "))
    }
    let heavy = baked.filter { $0.bytes > 200_000 }
    if heavy.isEmpty {
        print("[검사] 파일 크기 전부 200KB 미만 (최대 \(baked.map { $0.bytes }.max() ?? 0) bytes)")
    } else {
        print("[경고] 200KB 를 넘은 장: " + heavy.map { "\($0.sticker.id)=\($0.bytes)" }.joined(separator: ", "))
    }
}

// MARK: - 대조 시트(사용자에게 보여 줄 물건 — 저장소에는 안 쓴다)

if let sheetDir {
    try? FileManager.default.createDirectory(at: sheetDir, withIntermediateDirectories: true)
    func makeSheet(dark: Bool) -> CGImage {
        let cell: CGFloat = 256, labelBand: CGFloat = 46, pad: CGFloat = 14
        let cols = 4, rows = 2
        let width = CGFloat(cols) * cell + pad * CGFloat(cols + 1)
        let height = CGFloat(rows) * (cell + labelBand) + pad * CGFloat(rows + 1)
        let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(dark ? srgb(0x1C1730) : srgb(0xF7F4FF))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (index, item) in baked.enumerated() {
            let col = index % cols, row = index / cols
            let x = pad + CGFloat(col) * (cell + pad)
            let y = height - pad - CGFloat(row) * (cell + labelBand + pad) - cell
            // 말풍선처럼 한 칸을 통째로 차지하는지 보이게 옅은 칸을 깐다.
            ctx.setFillColor(dark ? srgb(0x2A2347) : srgb(0xFFFFFF))
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            ctx.draw(item.image, in: CGRect(x: x, y: y, width: cell, height: cell))
            let text = "\(item.sticker.label)  [아잉:\(item.sticker.label)]"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: dark ? NSColor.white : NSColor.black
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: x + (cell - size.width) / 2, y: y - labelBand + 14),
                                    withAttributes: attributes)
        }
        NSGraphicsContext.current = previous
        return ctx.makeImage()!
    }
    writePNG(makeSheet(dark: false), to: sheetDir.appendingPathComponent("contact-sheet.png"))
    writePNG(makeSheet(dark: true), to: sheetDir.appendingPathComponent("contact-sheet-dark.png"))
    print("[시트] \(sheetDir.appendingPathComponent("contact-sheet.png").path) · contact-sheet-dark.png")
}

print("[완료] \(baked.count)장")
