import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 황금 아잉이 3D 마감 (v0.3.54)
//
// 황금 아잉이는 아잉과 **같은 메시**(aing.scn)다. 앱의 3D 경로는 전부 unlit(.constant)이고 조명이 없으므로, 금빛 음영은 아트 스크립트
// (`scripts/make-gold-aing.swift`)가 UV 공간 텍스처(`aing_gold-skin.png`)에 **미리 구워 두었다**. 앱이 하는 일은 두 가지뿐이다:
//
//  ① 디퓨즈 합성 — 텍셀마다 `isGoldSkin(원본) ? 금 피부 맵 : 원본`. 로드 때 한 번 하고 프로세스 내내 캐시한다(같은 메시·같은 텍스처라
//     울트라 교체·원복이 몇 번이 와도 다시 굽지 않는다).
//  ② 후광 판 — 몸 뒤에 세우는 빌보드 평면(`aing_gold-halo.png`). 크기·자리는 아트 스크립트 머리말의 규약 그대로:
//     가로 = 세로 = 2.0 × 바운딩박스 높이, 중심 = 바운딩박스 중심, renderingOrder −1, 깊이 읽기·쓰기 끔, 알파 블렌드.
//
// ★ 후광은 몸의 **지금 각도**를 따른다(v0.3.55). 정면 한 장만 세우면 몸이 옆으로 돌아도(드래그 ±40° · 살랑 ±8° · 찔림 스핀 ·
//   360°/720° 스핀) 빌보드라 정면 날개 윤곽이 그대로 남아, 달걀 모양 옆모습 뒤에 날개 모양 빛이 떴다(사용자 신고 2026-10-16).
//   그래서 몸 요 10° 마다 그 자세의 실루엣으로 구운 칸 36장(`GoldAingArt.haloCellResourceNames`)을 판 36개로 세우고, 렌더 프레임마다
//   제약(`haloCellTransform`)이 몸의 presentation 변환에서 카메라 기준 요·롤을 구해 **칸 하나만**(`haloCell` — 가장 가까운 칸, 단 쉬는
//   자세 0° · ±40° 둘레 ±9° 는 그 자세의 칸이라 idle 살랑 ±8° 동안 칸이 안 바뀐다) 몸 자리에 두고 나머지는
//   카메라 뒤로 치운다(절두체 컬링으로 그리지도 않는다 — 판 36개 실측 +0.015ms/프레임). 롤(찔림의 z 흔들림)은 그 판을 화면 안에서 같이
//   기울인다. 재질·텍스처는 만들 때 한 번 정하고 다시는 안 건드린다 — 제약은 SceneKit 렌더 스레드에서 돌기 때문에 거기서 하는 일은
//   **받은 변환과 부모의 presentation 을 읽어 변환 하나를 돌려주는 것뿐**이다(공유 상태 · 할당 · 텍스처 재업로드 없음).
//
// ★ 마스크는 `isGoldSkin`(아트 스크립트 · 시안의 피부 분류)이다 — `SleepEyeTexture.isSkin` 이 **아니다**(아키텍트 결정 2026-10-15).
//   isSkin 은 루마 > 120 · b > g+18 이라 이보다 좁아서, 그 마스크로 합성하면 날개 이음매·정수리 하이라이트 605 텍셀이 라벤더로 남는다
//   (art-preview/gold-aing-mask-compare.png). 이 텍스처에서 isSkin ⊂ isGoldSkin 이다. isSkin 은 감은 눈 파이프라인 전용으로 그대로 둔다.
//
// ★ 감은 눈은 **라벤더 원본에서 먼저 굽고** 그 결과에 같은 합성을 한다(`closedEyesImage`). 금 디퓨즈에서 바로 구우면 감은 눈
//   파이프라인의 색 분류(라벤더 피부)가 금 피부를 피부로 못 알아봐 눈꺼풀이 라벤더 얼룩이 된다(지도 함정 4). 커버는 라벤더 피부로
//   덮이므로 합성이 그 자리를 금으로 바꾼다.
//
// ★ 후광은 **몸의 크기 계산에 끼지 않는다.** 2H 짜리 판이 바운딩박스에 섞이면 카메라 프레이밍·리액션 진폭(`modelExtent`)·
//   몸 클릭 영역(투영 bbox)이 전부 두 배 가까이 부푼다. 그래서 판 지오메트리의 바운딩박스를 몸 중심의 점으로 덮어 쓰고, 클릭 판정
//   (`ReactionEngine.isBodyAtScreenPoint`)은 이 판의 카테고리 비트를 빼고 hitTest 한다 — 후광은 빛이지 몸이 아니다.
enum GoldAingFinish {
    /// 후광 노드 이름. 이 이름의 노드가 캐릭터 아래에 있으면 **그 캐릭터는 황금 아잉이다**(엔진의 `currentCharacterID` 판정).
    static let haloNodeName = "check.goldHalo"
    /// 후광 재질 이름 — 엔진의 얼굴 재질 탐색("큰 CGImage 디퓨즈")이 이 재질을 얼굴로 오인하지 않게 건너뛰는 표식.
    static let haloMaterialName = "check.goldHalo.material"
    /// 후광 판의 카테고리 비트. 몸 클릭 hitTest 가 이 비트를 뺀 마스크로 묻는다(기본 노드 카테고리는 1).
    static let haloCategoryBit: Int = 1 << 20
    /// 몸 클릭 hitTest 에 넣는 카테고리 마스크 — 후광 비트만 뺀 전부.
    static let bodyHitCategoryMask = NSNumber(value: UInt.max ^ UInt(haloCategoryBit))
    /// 후광 판 한 변 ÷ 몸 바운딩박스 높이(아트 스크립트 머리말: 2.0 × H, H = 1.695736 → 3.391472 모델 단위).
    static let haloSideOverBodyHeight: CGFloat = 2.0
    /// 후광 판의 렌더 순서(몸보다 먼저 그려 몸이 덮는다).
    static let haloRenderingOrder = -1
    /// 각도 칸 판 노드 이름의 앞부분(`check.goldHalo.cell.040` — 칸의 몸 요). 칸 판은 전부 `haloNodeName` 노드의 자식이다.
    static let haloCellNodePrefix = "check.goldHalo.cell."
    /// 고르지 않은 칸을 치우는 거리(몸 중심에서 카메라 쪽으로, 모델 단위). 앱 카메라는 몸에서 6 남짓이라 이만큼 가면 카메라 뒤 —
    /// 절두체 밖이라 컬링되고(그리기 호출 없음), 클릭 hitTest 에도 안 걸린다.
    static let haloHiddenDistance: Float = 10_000

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    // MARK: 피부 분류 · 합성(순수)

    /// 금 합성 마스크 — `scripts/make-gold-aing.swift` 의 `isGoldSkin` 과 **같은 식**(색상 215–300° · 채도 0.05–0.75 · 루마 > 0.10).
    /// 아트 테스트(`V0354GoldAingArtTests`)도 이 함수를 부른다 — 식이 한 곳에만 있어야 그림과 앱이 갈리지 않는다.
    static func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        let rr = Double(r), gg = Double(g), bb = Double(b)
        let mx = max(rr, gg, bb), mn = min(rr, gg, bb)
        let sat = mx == 0 ? 0 : (mx - mn) / mx
        var hue = 0.0
        if mx != mn {
            if mx == rr {
                hue = 60 * ((gg - bb) / (mx - mn))
            } else if mx == gg {
                hue = 60 * ((bb - rr) / (mx - mn) + 2)
            } else {
                hue = 60 * ((rr - gg) / (mx - mn) + 4)
            }
            if hue < 0 { hue += 360 }
        }
        let lum = (0.299 * rr + 0.587 * gg + 0.114 * bb) / 255
        return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && lum > 0.10
    }

    /// 바이트 합성(RGBA8 premultipliedLast, 같은 크기): 원본 텍셀이 (금) 피부면 금 피부 맵의 RGB 로, 아니면 원본 그대로.
    /// 바뀐 텍셀은 불투명(255)으로 둔다 — 아트 스크립트 `composite(original:skin:)` 와 같은 정의.
    static func composite(face: [UInt8], skin: [UInt8]) -> [UInt8] {
        precondition(face.count == skin.count, "얼굴 디퓨즈와 금 피부 맵의 크기가 다르다")
        var out = face
        var o = 0
        while o < face.count {
            if isGoldSkin(Int(face[o]), Int(face[o + 1]), Int(face[o + 2])) {
                out[o] = skin[o]
                out[o + 1] = skin[o + 1]
                out[o + 2] = skin[o + 2]
                out[o + 3] = 255
            }
            o += 4
        }
        return out
    }

    /// CGImage → RGBA8 premultipliedLast 바이트(DeviceRGB — 앱 `SleepEyeTexture`·아트 스크립트와 같은 공간). 원점 좌상단.
    static func rgbaBytes(_ image: CGImage, width: Int? = nil, height: Int? = nil) -> [UInt8]? {
        let w = width ?? image.width, h = height ?? image.height
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? px : nil
    }

    /// 바이트 → CGImage. 아트 스크립트 `makeImage` 와 같은 sRGB 태그(그 경로로 시안과 맞댄 수치가 나왔다).
    static func makeImage(_ px: [UInt8], width: Int, height: Int) -> CGImage? {
        var copy = px
        return copy.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// 원본 디퓨즈에 금 피부 맵을 합성한 CGImage. 맵이 다른 크기면 원본 크기로 맞춰 읽는다(UV 는 정규화 좌표라 같다).
    static func compositeImage(original: CGImage, skin: CGImage) -> CGImage? {
        let w = original.width, h = original.height
        guard let face = rgbaBytes(original), let skinPx = rgbaBytes(skin, width: w, height: h) else { return nil }
        return makeImage(composite(face: face, skin: skinPx), width: w, height: h)
    }

    // MARK: 번들 자원

    /// 금 그림 한 장의 번들 URL(`GoldAingArt` 가 이름의 주인이다).
    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: GoldAingArt.resourceExtension)
    }

    /// 초상 URL(표정별).
    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? GoldAingArt.neutralPortraitResourceName : GoldAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 황금 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 금 피부 맵 + 후광). 상점 능력 번호 2 의 재료.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        GoldAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: 캐시(프로세스당 한 번)

    private struct Cache {
        var skin: CGImage??
        /// 후광 각도 칸 36장(창 합성 보정 끝). 빠진 칸은 0 칸(정면)으로 채운다. 정면이 없으면 nil.
        var haloCells: [CGImage]??
        /// 마지막으로 합성한 (라벤더 원본, 금 디퓨즈). 같은 메시·같은 텍스처라 한 벌이면 된다.
        var gold: (original: CGImage, gold: CGImage)?
        /// 위 금 디퓨즈의 감은 눈 판.
        var goldSleep: CGImage?
    }

    /// 잠금 + 상태. CGImage 는 불변이라 잠금 밖으로 넘겨도 안전하다(SceneKit·테스트가 아무 스레드에서나 부른다).
    private final class Locked: @unchecked Sendable {
        private let lock = NSLock()
        private var state = Cache()
        func withLock<R>(_ body: (inout Cache) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    private static let cache = Locked()

    private static func decode(_ name: String) -> CGImage? {
        guard let url = resourceURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func skinImage() -> CGImage? {
        if let hit = cache.withLock({ $0.skin }) { return hit }
        let made = decode(GoldAingArt.skinResourceName)
        cache.withLock { $0.skin = .some(made) }
        return made
    }

    /// 정면 후광(0 칸) 텍스처 — 번들 PNG 를 **창 합성 보정**(`windowCompensated`)해서 쓴다(캐시).
    static func haloImage() -> CGImage? {
        haloCellImages()?.first
    }

    /// 후광 각도 칸 36장(0 칸 = 정면 512², 나머지 160²) — 전부 창 합성 보정을 거친다(캐시, 프로세스당 한 번).
    /// 칸 하나가 번들에 없으면 그 자리는 정면으로 접는다(옛 동작 — 패키징 대본이 그런 빌드를 막는다). 정면이 없으면 nil.
    static func haloCellImages() -> [CGImage]? {
        if let hit = cache.withLock({ $0.haloCells }) { return hit }
        var memo = CompensationMemo()
        var made: [CGImage]?
        if let front = decode(GoldAingArt.haloResourceName).flatMap({ windowCompensated($0, memo: &memo) }) {
            var cells = [front]
            var missing: [String] = []
            for cell in 1..<GoldAingArt.haloCellCount {
                let name = GoldAingArt.haloResourceName(cell: cell)
                if let image = decode(name).flatMap({ windowCompensated($0, memo: &memo) }) {
                    cells.append(image)
                } else {
                    missing.append(name)
                    cells.append(front)
                }
            }
            if !missing.isEmpty {
                logger.error("gold halo: 각도 칸 \(missing.count, privacy: .public)장이 번들에 없다 — 정면 후광으로 접는다 \(missing.joined(separator: ","), privacy: .public)")
            }
            made = cells
        }
        cache.withLock { $0.haloCells = .some(made) }
        return made
    }

    // MARK: 창 합성 보정(후광)

    /// sRGB 부호화(0…1).
    static func srgbEncode(_ linear: Double) -> Double {
        let x = min(max(linear, 0), 1)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    /// sRGB 복호화(0…1).
    static func srgbDecode(_ encoded: Double) -> Double {
        let x = min(max(encoded, 0), 1)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    /// 반투명 텍셀 하나의 보정: 시안 색 C(sRGB, 프리멀티 아님) · 알파 A → 텍스처에 넣을 색 C' = sRGB(lin(C·A) / A).
    ///
    /// ★ 왜: SceneKit 은 반투명 픽셀을 **선형 공간에서 프리멀티한 뒤 sRGB 로 부호화**해 적는다 — 적히는 값 = sRGB(lin(C)·A)
    ///   (실측: C 1 · A 0.1 → 90/255, A 0.5 → 188/255). 투명 오버레이 창의 합성기는 그 값을 **sRGB 프리멀티**로 읽어
    ///   바탕 위에 더한다(표시 = 적힌 값 + 바탕·(1−A)). 그래서 보정 없이 그리면 옅은 꼬리(A 0.02~0.1)가 바탕을 4배쯤 밝혀
    ///   밝은 바탕에선 **흰 안개 덩어리가 판 끝에서 딱 끊기고**, 어두운 바탕에선 알파 1/255 경계가 윤곽선으로 보인다
    ///   (실제 투명 창 캡처 — scratchpad v0354/mac-preview/gold-window-capture-*.png). C' 를 넣으면 적히는 값이 C·A 가 되어
    ///   창에 보이는 것이 **시안 PNG 를 바탕 위에 그대로 얹은 것**과 같아진다(`V0354GoldAing3DTests` 가 시안과 맞댄다).
    ///   이 보정은 투명 창 전용이다 — 바탕을 씬 안에 깐 오프스크린 렌더(아트 --verify)에서는 후광이 조금 옅게 보인다.
    static func compensatedColor(_ color: Double, alpha: Double) -> Double {
        guard alpha > 0 else { return 0 }
        return srgbEncode(srgbDecode(color * alpha) / alpha)
    }

    /// SceneKit 이 텍셀(8비트 프리멀티 p/255 · 알파 k/255)로 적는 값(0…255): sRGB(lin(p/k)·k/255).
    static func writtenValue(premultiplied p: Int, alpha k: Int) -> Double {
        guard k > 0, p > 0 else { return 0 }
        return srgbEncode(srgbDecode(Double(p) / Double(k)) * Double(k) / 255) * 255
    }

    /// 한 채널의 8비트 프리멀티 값: 적히는 값이 목표(C·A)에 **가장 가까운** 정수. SceneKit 은 텍스처를 8비트 프리멀티로 올리므로
    /// (16비트로 줘도 같다 — 실측) 알파가 작은 꼬리에서는 고를 수 있는 값이 몇 개뿐이다. 반올림만 하면 A 2/255 에서 목표 2 대신 6 이
    /// 적히는 식으로 오차가 들쭉날쭉해 밝은 바탕에 **등고선**이 보였다(실측) — 그래서 이웃한 두 정수 중 실제로 더 가까운 쪽을 고른다
    /// (적히는 값은 p 에 대해 단조라 바닥·천장 둘만 보면 된다).
    static func premultipliedByte(color: Double, alpha k: Int) -> UInt8 {
        guard k > 0 else { return 0 }
        let a = Double(k) / 255
        let target = color * a * 255
        let ideal = compensatedColor(color, alpha: a) * Double(k)
        let low = max(0, min(k, Int(ideal.rounded(.down)))), high = min(k, low + 1)
        let lowError = abs(writtenValue(premultiplied: low, alpha: k) - target)
        let highError = abs(writtenValue(premultiplied: high, alpha: k) - target)
        return UInt8(highError < lowError ? high : low)
    }

    /// (알파, 색) 쌍 → 보정한 프리멀티 바이트. 쌍은 256×256 가지뿐이라 픽셀마다 pow 를 여섯 번 부르지 않게 쌍마다 한 번만 계산한다
    /// (첫 금 로드가 메인 스레드다). 후광 칸 36장이 같은 금빛 층이라 한 메모를 나눠 쓰면 대부분 이미 채워져 있다.
    struct CompensationMemo {
        var table = [Int16](repeating: -1, count: 256 * 256)
    }

    /// 후광 그림 전체를 보정한다(`premultipliedByte`). 결과는 8비트 sRGB 프리멀티 RGBA — SceneKit 이 그대로 올리는 꼴이다.
    static func windowCompensated(_ image: CGImage) -> CGImage? {
        var memo = CompensationMemo()
        return windowCompensated(image, memo: &memo)
    }

    static func windowCompensated(_ image: CGImage, memo: inout CompensationMemo) -> CGImage? {
        let w = image.width, h = image.height
        guard let straight = straightRGBA(image) else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var o = 0
        while o < straight.count {
            let k = Int(straight[o + 3])
            if k > 0 {
                for c in 0..<3 {
                    let key = k << 8 | Int(straight[o + c])
                    if memo.table[key] < 0 {
                        memo.table[key] = Int16(premultipliedByte(color: Double(straight[o + c]) / 255, alpha: k))
                    }
                    out[o + c] = UInt8(memo.table[key])
                }
                out[o + 3] = straight[o + 3]
            }
            o += 4
        }
        return out.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// 프리멀티가 아닌 RGBA8(sRGB) 바이트. PNG 디코드가 이미 그 꼴(알파 `.last` · 8비트)이면 그 바이트를 그대로 읽고(정밀도 손실 없음),
    /// 아니면 프리멀티 문맥에 그린 뒤 나눈다.
    static func straightRGBA(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        if image.alphaInfo == .last, image.bitsPerComponent == 8, image.bitsPerPixel == 32,
           image.bitmapInfo.intersection(.byteOrderMask).rawValue == 0 || image.bitmapInfo.contains(.byteOrder32Big),
           image.colorSpace?.name == CGColorSpace.sRGB,
           let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) {
            var out = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                let row = base + y * image.bytesPerRow
                for x in 0..<(w * 4) { out[y * w * 4 + x] = row[x] }
            }
            return out
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var o = 0
        while o < px.count {
            let a = Int(px[o + 3])
            if a > 0, a < 255 {
                for c in 0..<3 { px[o + c] = UInt8(min(255, (Int(px[o + c]) * 255 + a / 2) / a)) }
            }
            o += 4
        }
        return px
    }

    /// 라벤더 원본 → 금 디퓨즈(캐시). 처음 한 번만 굽고, 그 뒤로는 **같은 객체**를 돌려준다 — 엔진이 이 객체로 "이 얼굴은 금이다"를
    /// 알아본다(`lavenderOriginal(ofGoldFace:)`). 원본 크기가 바뀌면(다른 출처 폴백) 다시 굽는다.
    static func goldDiffuse(for original: CGImage) -> CGImage? {
        if let hit = cache.withLock({ state -> CGImage? in
            guard let gold = state.gold, gold.gold.width == original.width, gold.gold.height == original.height else { return nil }
            return gold.gold
        }) {
            return hit
        }
        guard let skin = skinImage(), let gold = compositeImage(original: original, skin: skin) else { return nil }
        return cache.withLock { state -> CGImage in
            // 경합으로 다른 쪽이 먼저 구웠으면 그것을 쓴다(한 객체여야 감은 눈 캐시가 맞는다).
            if let existing = state.gold, existing.gold.width == gold.width, existing.gold.height == gold.height {
                return existing.gold
            }
            state.gold = (original, gold)
            state.goldSleep = nil
            return gold
        }
    }

    /// 이 얼굴 디퓨즈가 우리가 구운 금 디퓨즈면 그 라벤더 원본(감은 눈을 굽는 재료), 아니면 nil.
    static func lavenderOriginal(ofGoldFace face: CGImage) -> CGImage? {
        cache.withLock { state in
            guard let gold = state.gold, gold.gold === face else { return nil }
            return gold.original
        }
    }

    /// 금 얼굴의 감은 눈 판 — **라벤더 원본으로 감은 눈을 굽고** 같은 합성을 한다(캐시).
    /// `lavenderClosedEyes` 는 라벤더 감은 눈 굽기(`CheckCharacter3DScene.lavenderClosedEyesImage`)다 — 주입은 테스트 이음새.
    static func closedEyesImage(
        goldFace: CGImage,
        original: CGImage,
        lavenderClosedEyes: (CGImage) -> CGImage?
    ) -> CGImage? {
        if let hit = cache.withLock({ state -> CGImage? in
            guard let gold = state.gold, gold.gold === goldFace else { return nil }
            return state.goldSleep
        }) {
            return hit
        }
        guard let skin = skinImage(),
              let lavenderClosed = lavenderClosedEyes(original),
              let goldClosed = compositeImage(original: lavenderClosed, skin: skin) else { return nil }
        cache.withLock { state in
            if let gold = state.gold, gold.gold === goldFace { state.goldSleep = goldClosed }
        }
        return goldClosed
    }

    /// 테스트 전용: 캐시를 비운다.
    static func resetCacheForTesting() {
        cache.withLock { $0 = Cache() }
    }

    // MARK: 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 금 마감을 입힌다: 얼굴 디퓨즈를 금으로 합성하고 몸 뒤에 후광 판을 세운다.
    /// **unlit 정규화(`applyUnlitMaterials`) 뒤에** 불러야 한다 — 얼굴 재질을 "큰 CGImage 디퓨즈"로 찾는다(엔진과 같은 규칙).
    /// 금 피부 맵이 없으면 아무것도 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 2 를 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        // 몸 크기는 **아무것도 붙이기 전에** 잰다(감은 눈 선·후광이 섞이지 않게).
        let body = character.boundingBox
        var composited = false
        character.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents,
                      CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                let face = contents as! CGImage
                guard face.width >= 256 else { continue }
                guard let gold = goldDiffuse(for: face) else { continue }
                material.diffuse.contents = gold
                composited = true
            }
        }
        guard composited else {
            logger.error("gold finish: 금 피부 맵 합성 실패 — 보라 아잉으로 선다")
            return false
        }
        character.addChildNode(makeHaloNode(bodyMin: body.min, bodyMax: body.max))
        return true
    }

    /// 후광 노드: 몸 바운딩박스 중심의 표식 노드(`haloNodeName`, 지오메트리 없음) 아래에 각도 칸 판 36개.
    /// 그림이 없으면 표식 노드만 남긴다(금 판정은 그대로 산다).
    static func makeHaloNode(bodyMin: SCNVector3, bodyMax: SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.name = haloNodeName
        node.categoryBitMask = haloCategoryBit
        let center = SCNVector3((bodyMin.x + bodyMax.x) / 2, (bodyMin.y + bodyMax.y) / 2, (bodyMin.z + bodyMax.z) / 2)
        node.position = center
        guard let cells = haloCellImages() else { return node }
        let side = CGFloat(bodyMax.y - bodyMin.y) * haloSideOverBodyHeight
        for (cell, image) in cells.enumerated() {
            node.addChildNode(makeHaloCellNode(cell: cell, image: image, side: side))
        }
        return node
    }

    /// 각도 칸 판 하나. 판·재질은 0.3.54 정면 판과 같고, 제약이 [빌보드 → 칸 고르기(`haloCellTransform`)] 다.
    static func makeHaloCellNode(cell: Int, image: CGImage, side: CGFloat) -> SCNNode {
        let node = SCNNode()
        node.name = haloCellNodePrefix + String(format: "%03d", cell * GoldAingArt.haloYawStepDegrees)
        let plane = SCNPlane(width: side, height: side)
        let material = SCNMaterial()
        material.name = haloMaterialName
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        plane.materials = [material]
        // 바운딩박스를 몸 중심의 점으로 덮어 쓴다 — 판이 몸 크기 계산(프레이밍·modelExtent·클릭 rect)에 끼지 않게.
        // 고른 칸은 몸 중심에 서고 몸 중심은 언제나 화면 안이라 절두체 컬링이 그 판을 지우지 않는다(치운 칸은 일부러 컬링된다).
        let tiny: CGFloat = 0.001
        plane.boundingBox = (min: SCNVector3(-tiny, -tiny, -tiny), max: SCNVector3(tiny, tiny, tiny))
        node.geometry = plane
        node.renderingOrder = haloRenderingOrder
        node.categoryBitMask = haloCategoryBit
        // ★ 렌더 스레드에서 돈다. 받은 변환(빌보드 결과 = 카메라 방향)과 부모(표식 노드)의 presentation 만 읽는다 — 리액션 SCNAction ·
        //   CAAnimation · 살랑 회전이 이 프레임에 몸을 어디로 돌렸는지는 presentation 에만 확실히 있다. 들어오는 변환의 위치·크기는
        //   믿지 않는다: SceneKit 은 제약 결과를 presentation 에 남겨 다음 프레임의 입력으로 쓰므로, 지난 프레임에 치운 칸은 카메라 뒤에서
        //   출발한다. 위치·크기는 언제나 표식 노드(= 몸)에서 다시 잰다.
        // 블록은 칸 번호(Int)만 잡는다 — 노드를 잡으면 노드 → 제약 → 블록 → 노드 고리가 생긴다.
        let select = SCNTransformConstraint(inWorldSpace: true) { evaluated, transform in
            guard let anchor = evaluated.parent?.presentation.simdWorldTransform else { return transform }
            return SCNMatrix4(haloCellTransform(billboard: simd_float4x4(transform), anchor: anchor, cell: cell))
        }
        node.constraints = [SCNBillboardConstraint(), select]
        return node
    }

    // MARK: 칸 고르기(순수 — 렌더 스레드의 제약이 부른다)

    /// 몸의 자세를 카메라 기준으로 나눈 것(라디안). 카메라 기준 회전 = Rz(roll) · Rx(tilt) · Ry(yaw).
    /// · yaw — 몸이 카메라 앞에서 제 위 축으로 돈 각(+ = 위에서 볼 때 반시계, 얼굴이 화면 오른쪽으로). 후광 칸을 고른다.
    /// · roll — 몸의 위 축이 화면 안에서 기운 각(+ = 반시계). 판을 화면 안에서 같이 기울인다.
    /// · tilt — 몸의 위 축이 카메라 쪽으로 넘어온 각. 앱 카메라는 위에서 내려다봐 서 있는 몸도 약 17° 다. 칸은 수평 시안 카메라로
    ///   구웠고(확정 정면도 그렇다) 끄덕임(인사 20°)용 칸은 없다 — yaw 를 구할 때 걷어 내기만 한다.
    struct HaloPose: Equatable {
        var yaw: Float
        var roll: Float
        var tilt: Float
    }

    /// `camera`: 빌보드 결과(축 = 화면 오른쪽 · 위 · 카메라 쪽, 크기가 섞여 있어도 된다). `body`: 몸(표식 노드)의 월드 변환.
    static func haloPose(camera: simd_float4x4, body: simd_float4x4) -> HaloPose {
        let right = axis(camera.columns.0), up = axis(camera.columns.1), toward = axis(camera.columns.2)
        let bodyUp = axis(body.columns.1), bodyForward = axis(body.columns.2)
        // 몸 축을 카메라 좌표로.
        let u = SIMD3(simd_dot(bodyUp, right), simd_dot(bodyUp, up), simd_dot(bodyUp, toward))
        let f = SIMD3(simd_dot(bodyForward, right), simd_dot(bodyForward, up), simd_dot(bodyForward, toward))
        // 위 축 = Rz(roll)·Rx(tilt)·(0,1,0) = (−sin roll · cos tilt, cos roll · cos tilt, sin tilt).
        let roll = atan2(-u.x, u.y)
        let tilt = asin(min(1, max(-1, u.z)))
        // 앞 축에서 roll · tilt 를 걷어 내면 Ry(yaw)·(0,0,1) = (sin yaw, 0, cos yaw) 가 남는다.
        let cr = cos(roll), sr = sin(roll)
        let unrolled = SIMD3(f.x * cr + f.y * sr, -f.x * sr + f.y * cr, f.z)
        let ct = cos(tilt), st = sin(tilt)
        let level = SIMD3(unrolled.x, unrolled.y * ct + unrolled.z * st, -unrolled.y * st + unrolled.z * ct)
        return HaloPose(yaw: atan2(level.x, level.z), roll: roll, tilt: tilt)
    }

    /// 몸 요(라디안, 아무 값 — 여러 바퀴 · 음수) → 칸(0…35). 360° 로 감고, 기본은 가장 가까운 칸(경계 ±5° 반올림)이다.
    /// 단 **쉬는 자세**(정면 0° · 드래그/보드 바라보기 ±40°) 둘레 ±`haloRestBandDegrees` 안은 그 자세의 칸이다 — 살랑(±8.02°)이
    /// 칸 경계(±5° · 35° · 45°)를 넘나들어, 가만히 선 몸 뒤에서 확정 정면 후광이 3.6초마다 10° 칸과 뒤바뀌며 윤곽이 튀었다(검토 지적).
    /// 띠 끝(9.02°)의 윤곽 오차는 정면 칸 기준 L1 0.0041 — 가장 가까운 칸 규칙의 최악(145° 0.0044)보다 작다(아트 파이프라인 실측).
    static func haloCell(yaw: Double) -> Int {
        guard yaw.isFinite else { return 0 }
        let degrees = remainder(yaw * 180 / .pi, 360)   // (−180, 180]
        let band = haloRestBandDegrees, side = haloSideRestDegrees
        if abs(degrees) <= band { return 0 }
        if abs(degrees - side) <= band { return nearestHaloCell(degrees: side) }
        if abs(degrees + side) <= band { return nearestHaloCell(degrees: -side) }
        return nearestHaloCell(degrees: degrees)
    }

    /// 쉬는 자세 띠의 반폭(도) = idle 살랑 한쪽 폭(`CheckCharacter3DScene.idleSwayRadians`, 8.02°) + 1°.
    static let haloRestBandDegrees: Double = Double(CheckCharacter3DScene.idleSwayRadians) * 180 / .pi + 1
    /// 옆으로 쉬는 자세(도) — 드래그 방향·보드 쪽 바라보기 스냅 각(`ReactionEngine.dragFacingAngle`, 테스트가 같은 값으로 묶는다).
    /// 칸 중심(10° 배수)이어야 그 자세에서 오차 0 이다.
    static let haloSideRestDegrees: Double = 40

    /// 도(아무 값) → 가장 가까운 칸. 반올림 · 360° 감기.
    private static func nearestHaloCell(degrees: Double) -> Int {
        let count = GoldAingArt.haloCellCount
        let k = Int((degrees / Double(GoldAingArt.haloYawStepDegrees)).rounded()) % count
        return k < 0 ? k + count : k
    }

    /// 칸 `cell` 판의 이 프레임 월드 변환. 몸 자세가 이 칸이면 몸 중심에 화면 정렬 + 몸의 롤만큼 기울여 세우고, 아니면 카메라 뒤로 치운다.
    /// 빌보드 결과에서는 **방향만** 쓴다(SceneKit 이 매 프레임 카메라에서 새로 정한다). 위치·크기(스쿼시·스트레치)는 몸(`anchor`)에서
    /// 잰다 — 들어온 위치·크기는 지난 프레임 이 함수의 결과가 남은 것이라, 그것을 다시 쓰면 오차가 쌓이거나 치운 자리에 머문다.
    static func haloCellTransform(billboard: simd_float4x4, anchor: simd_float4x4, cell: Int) -> simd_float4x4 {
        let pose = haloPose(camera: billboard, body: anchor)
        let right = axis(billboard.columns.0), up = axis(billboard.columns.1), toward = axis(billboard.columns.2)
        let scale = SIMD3(length(anchor.columns.0), length(anchor.columns.1), length(anchor.columns.2))
        let c = cos(pose.roll), s = sin(pose.roll)
        let rolledRight = right * c + up * s, rolledUp = up * c - right * s
        var position = SIMD3(anchor.columns.3.x, anchor.columns.3.y, anchor.columns.3.z)
        if haloCell(yaw: Double(pose.yaw)) != cell { position += toward * haloHiddenDistance }
        return simd_float4x4(SIMD4(rolledRight * scale.x, 0), SIMD4(rolledUp * scale.y, 0), SIMD4(toward * scale.z, 0), SIMD4(position, 1))
    }

    private static func axis(_ column: SIMD4<Float>) -> SIMD3<Float> {
        let v = SIMD3(column.x, column.y, column.z)
        let l = simd_length(v)
        return l > 0 ? v / l : v
    }

    private static func length(_ column: SIMD4<Float>) -> Float {
        simd_length(SIMD3(column.x, column.y, column.z))
    }

    /// 이 캐릭터 노드가 황금 아잉이인가(후광 표식이 붙어 있다).
    static func isGold(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: haloNodeName, recursively: false) != nil
    }
}
