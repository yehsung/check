import AppKit
import CryptoKit
import Foundation
import os
import SceneKit
import simd
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.77 — 빼빼로 아잉이 맥 3D 가지 검토(화면 · 3D / 번호 · 회귀) 수리의 못. 지적마다 그 결함을 잡는 시험 하나다(되돌리면 빨갛다 —
// 수리 커밋이 되돌려 본 기록을 적었다). 실제 앱 씬(`makeScene`) · 엔진 · 저장소 · 대본을 그대로 쓴다. 네트워크 · 사용자 도메인은 안 탄다.
@MainActor
@Suite(.serialized) struct V0377PeperoReviewFixTests {
    static let pepero = CharacterCatalog.builtInPeperoAing
    static let id = CharacterCatalog.peperoAingID
    typealias Decor = PeperoDecor

    /// 메인에서 선 빼빼로 씬이 곧바로 장식을 갖게 원본을 먼저 구워 둔다(메인은 굽지 않는다 — 원본이 없으면 장식이 뒤에 붙는다).
    init() { _ = PeperoAingFinish.decorNode() }

    // MARK: 도구

    static func isLavender(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
        a > 200 && b > 170 && b > r + 12 && b > g + 20 && r > 120
    }

    static func isBoxRed(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
        a > 200 && r > 110 && g < 90 && b < 100 && r > g + 60
    }

    struct Shot {
        /// 열마다 가장 아래 상자 빨강 아래(+1 줄 띄고)의 라벤더 화소 수 — 상자 밑으로 비어져 나온 몸 · 팔.
        var below: Int
        /// 위 · 아래 여백(알파 상자 · 높이 비).
        var top: Double
        var bottom: Double
        var pixels: Int
    }

    static func shot(_ image: CGImage) -> Shot {
        let px = V0354GoldAingArtTests.rgba(image)
        let w = image.width, h = image.height
        var lowestRed = [Int](repeating: -1, count: w)
        var first = h, last = -1
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                if px[o + 3] > 8 { first = min(first, y); last = max(last, y) }
                if isBoxRed(Int(px[o]), Int(px[o + 1]), Int(px[o + 2]), Int(px[o + 3])) { lowestRed[x] = y }
            }
        }
        var below = 0
        for x in 0..<w where lowestRed[x] >= 0 {
            var y = lowestRed[x] + 2
            while y < h {
                let o = (y * w + x) * 4
                if isLavender(Int(px[o]), Int(px[o + 1]), Int(px[o + 2]), Int(px[o + 3])) { below += 1 }
                y += 1
            }
        }
        return Shot(below: below, top: Double(first) / Double(h), bottom: Double(h - 1 - last) / Double(h), pixels: w * h)
    }

    // MARK: ① 울트라 격발 자세(화면 · 3D medium 1)

    /// 이 자세의 rage 양 끝 · 임팩트 스트레치를 앱 씬 wrapper 에 걸어 그린다(`ReactionActions.ultraRageEndpoint` — 액션이 지나는 같은 값).
    static func ragePoses(_ pose: ReactionActions.UltraRagePose, extent: CGFloat) -> [(String, SCNVector3, SCNVector3, SCNVector3)] {
        let plus = ReactionActions.ultraRageEndpoint(sign: 1, pose: pose, extent: extent)
        let minus = ReactionActions.ultraRageEndpoint(sign: -1, pose: pose, extent: extent)
        return [("plus", plus.euler, plus.scale, plus.position),
                ("minus", minus.euler, minus.scale, minus.position),
                ("stretch", SCNVector3(0, 0, 0), ReactionActions.ultraImpactStretch, SCNVector3(0, -extent * pose.drop, 0))]
    }

    @Test("울트라 격발: 엔진은 빼빼로에만 빼빼로 자세를 고른다 — 그 자세의 rage 양 끝 · 임팩트 스트레치에서 막대가 프레임 안(위 ≥ 0.02) · 상자 밑 라벤더가 거의 없다(기본 자세면 위가 잘리고 밑으로 몸이 보인다 — 기준선)")
    func ultraRageKeepsTheBoxAndSticksInFrame() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let wrapper = try V0354GoldAing3DTests.wrapper(scene)
        let engine = ReactionEngine()
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
        #expect(engine.currentCharacterID == Self.id && engine.ultraRagePose == .pepero, "엔진이 빼빼로 자세를 안 고른다 — \(engine.ultraRagePose)")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInIsulAing, CharacterCatalog.builtInCakeChocoAing] {
            let s = try V0354GoldAing3DTests.scene(other)
            let e = ReactionEngine()
            e.attach(node: try V0354GoldAing3DTests.wrapper(s), sceneRoot: s.rootNode, view: nil)
            #expect(e.ultraRagePose == .standard, "\(other.id) 의 격발 자세가 바뀌었다")
        }
        #expect(ReactionActions.UltraRagePose.standard == .init(tiltX: 12, rollZ: 34, lift: 0.6, drop: 0), "기본 격발 자세가 바뀌었다")
        #expect(ReactionActions.UltraRagePose.pepero.tiltX == 0, "빼빼로 자세에 x 기울기가 있다 — 음수 끝이 밑에서 보는 구도라 상자 밑으로 몸이 보인다")

        let (lo, hi) = AingDecor.bodyBoundingBox(of: wrapper)
        let extent = CGFloat(max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z)))
        var shots: [String: Shot] = [:]
        for (label, pose) in [("pepero", engine.ultraRagePose), ("standard", ReactionActions.UltraRagePose.standard)] {
            for (name, euler, scale, position) in Self.ragePoses(pose, extent: extent) {
                wrapper.eulerAngles = euler
                wrapper.scale = scale
                wrapper.position = position
                for size in [CGSize(width: 280, height: 340), CGSize(width: 945, height: 945)] {
                    let image = try V0359Rainbow3DTests.render(scene, size: size)
                    let s = Self.shot(image)
                    shots["\(label)-\(name)-\(Int(size.width))"] = s
                    print(String(format: "[v0377-fix] 격발 %@ %@ %d: 상자 밑 라벤더 %d px(%.3f%%) · 위 %.3f · 아래 %.3f",
                                 label, name, Int(size.width), s.below, Double(s.below) * 100 / Double(s.pixels), s.top, s.bottom))
                    if Self.evidenceDirectory != nil { try V0377PeperoMac3DTests.write(image, "ultra-rage-\(label)-\(name)-\(Int(size.width)).png") }
                }
            }
        }
        wrapper.eulerAngles = SCNVector3(0, 0, 0)
        wrapper.scale = SCNVector3(1, 1, 1)
        wrapper.position = SCNVector3(0, 0, 0)
        for size in [280, 945] {
            for name in ["plus", "minus", "stretch"] {
                let s = try #require(shots["pepero-\(name)-\(size)"])
                #expect(s.top >= 0.02, "빼빼로 격발 \(name) \(size): 위 여백 \(s.top) — 막대가 프레임 위로 잘린다")
                #expect(s.bottom >= 0.1, "빼빼로 격발 \(name) \(size): 아래 여백 \(s.bottom) — 상자가 프레임 아래로 나간다")
                // 남는 몇십 px 는 기울어진 쪽 팔 끝(팔 구멍 (가) — 끌기 · 출근 스핀과 같은 대표 확인 항목)이다. 몸이 바닥 밑으로 보이던 x −12° 는
                // 280 에서 0.6–0.9 %, 945 에서 0.5–0.8 % 였다.
                #expect(Double(s.below) / Double(s.pixels) < 0.0015, "빼빼로 격발 \(name) \(size): 상자 밑 라벤더 \(s.below) px")
            }
            // 기준선: 기본 자세면 plus 끝 위가 잘리고(막대) minus 끝 밑으로 몸이 보인다 — 이 둘이 안 나오면 위 재기가 눈이 멀었다.
            let plus = try #require(shots["standard-plus-\(size)"]), minus = try #require(shots["standard-minus-\(size)"])
            #expect(plus.top < 0.005, "기준선: 기본 자세 plus \(size) 위 여백 \(plus.top) — 잘림을 못 잰다")
            #expect(Double(minus.below) / Double(minus.pixels) > 0.004, "기준선: 기본 자세 minus \(size) 상자 밑 라벤더 \(minus.below) — 못 잰다")
        }
    }

    @Test("울트라 격발 액션: 빼빼로 자세의 내려 세우기는 moveBy 쌍이라 5초 뒤 제자리(드리프트 0) · 총 길이 5초 그대로 · 기본 자세는 이동을 더하지 않는다")
    func ultraRageDropReturnsHome() throws {
        let pepero = ReactionActions.ultraPoked(extent: 1.921, pose: .pepero)
        let standard = ReactionActions.ultraPoked(extent: 1.921)
        #expect(abs(pepero.duration - 5.0) < 0.001 && abs(standard.duration - 5.0) < 0.001, "격발 길이 \(pepero.duration) · \(standard.duration)")
        let plus = ReactionActions.ultraRageEndpoint(sign: 1, pose: .pepero, extent: 1.921)
        let minus = ReactionActions.ultraRageEndpoint(sign: -1, pose: .pepero, extent: 1.921)
        #expect(abs(minus.position.y + 1.921 * 0.11) < 1e-4 && minus.position.x == 0, "minus 끝 자리 \(minus.position)")
        #expect(abs((plus.position.y - minus.position.y) - 1.921 * 0.06 * 0.6) < 1e-4, "plus · minus 높이 차가 흔들림과 다르다")
    }

    // MARK: ② 메인은 장식을 굽지 않는다(화면 · 3D medium 2)

    @Test("메인 굽기 금지: 원본이 없을 때 메인에서 선 빼빼로 씬은 곧바로 서고(상자 없이 · 표식은 있다) 메인 밖에서 구운 장식이 뒤에 붙는다 — 굽는 도중 선 둘째 씬도 자물쇠를 안 기다린다 · 한 번만 굽는다")
    func mainNeverBakesTheDecor() async throws {
        PeperoAingFinish.resetDecorCacheForTesting()
        defer { _ = PeperoAingFinish.decorNode() }
        var t = CFAbsoluteTimeGetCurrent()
        let first = try V0354GoldAing3DTests.scene(Self.pepero)
        let firstMs = (CFAbsoluteTimeGetCurrent() - t) * 1_000
        t = CFAbsoluteTimeGetCurrent()
        let second = try V0354GoldAing3DTests.scene(Self.pepero)
        let secondMs = (CFAbsoluteTimeGetCurrent() - t) * 1_000
        let builtOnMain = PeperoAingFinish.decorBuildsOnMainForTesting
        let pending = PeperoAingFinish.pendingAttachCountForTesting
        print(String(format: "[v0377-fix] 원본 없이 메인 씬: 첫 %.0fms · 굽는 중 둘째 %.0fms · 대기 %d", firstMs, secondMs, pending))
        #expect(!builtOnMain.contains(true), "메인이 장식을 구웠다 — \(builtOnMain)")
        let firstCharacter = try V0354GoldAing3DTests.character(first), secondCharacter = try V0354GoldAing3DTests.character(second)
        #expect(PeperoAingFinish.isPepero(firstCharacter) && PeperoAingFinish.isPepero(secondCharacter),
                "장식을 기다리는 동안 표식이 없다 — 엔진이 빼빼로를 아잉으로 읽는다")
        #expect(pending == 2, "메인 밖 굽기를 기다리는 씬이 \(pending) 이다(기대 2)")
        // debug 굽기는 ~20초다 — 메인이 굽거나 자물쇠를 기다리면 이 문턱을 넘는다.
        #expect(firstMs < 5_000 && secondMs < 5_000, "메인이 멎었다 — 첫 \(firstMs)ms · 둘째 \(secondMs)ms")
        let deadline = Date().addingTimeInterval(240)
        while PeperoAingFinish.pendingAttachCountForTesting > 0, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(PeperoAingFinish.pendingAttachCountForTesting == 0, "메인 밖 굽기가 4분 안에 안 끝났다")
        for scene in [first, second] {
            let decors = scene.rootNode.childNodes { node, _ in node.name == PeperoAingFinish.decorNodeName }
            #expect(decors.count == 1, "씬의 장식이 \(decors.count) 벌이다(기대 1)")
        }
        #expect(PeperoAingFinish.decorBuildCountForTesting == 1 && PeperoAingFinish.decorBuildsOnMainForTesting == [false],
                "두 씬이 각자 굽거나 메인에서 구웠다 — \(PeperoAingFinish.decorBuildsOnMainForTesting)")
        let third = try V0354GoldAing3DTests.scene(Self.pepero)
        #expect(V0377PeperoMac3DTests.decor(third) != nil && PeperoAingFinish.pendingAttachCountForTesting == 0, "원본이 있는데 셋째 씬이 기다린다")
    }

    // MARK: ③ 근무 시계 자리(화면 · 3D medium 3)

    @Test("근무 시계: 빼빼로를 입으면 라벨이 상자 아래 빈 자리에 선다(쉼 · 부유 꼭대기 모두 상자와 안 겹친다 · 패널 안) — 옛 자리 0.49 는 상자 로고를 덮는다(기준선) · 다른 캐릭터는 0.49 · 실제 뷰가 착용 캐릭터로 고른다")
    func timerSitsBelowThePeperoBox() throws {
        let panel = CheckOverlayController.panelSize
        let label = NSHostingView(rootView: CheckOverlayTimerLabel(text: "88:88")).fittingSize
        let half = Double(label.height) / 2 / Double(panel.height)
        let size = CGSize(width: panel.width * 2, height: panel.height * 2)
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let character = try V0354GoldAing3DTests.character(scene)
        var redTop = 1.0, redBottom = 0.0
        for dy: Float in [0, 0.07] {
            character.simdPosition.y = dy
            let image = try V0359Rainbow3DTests.render(scene, size: size)
            let px = V0354GoldAingArtTests.rgba(image)
            let w = image.width, h = image.height
            for y in 0..<h {
                var red = 0
                for x in 0..<w {
                    let o = (y * w + x) * 4
                    if Self.isBoxRed(Int(px[o]), Int(px[o + 1]), Int(px[o + 2]), Int(px[o + 3])) { red += 1 }
                }
                if red > w / 10 { redTop = min(redTop, Double(y) / Double(h)); redBottom = max(redBottom, Double(y + 1) / Double(h)) }
            }
        }
        character.simdPosition.y = 0
        let fraction = Double(CheckOverlayCharacterView.timerVerticalFraction(characterID: Self.id))
        print(String(format: "[v0377-fix] 상자 빨강 %.3f…%.3f · 라벨 높이 %.1fpt(반 %.3f) · 빼빼로 라벨 %.3f…%.3f", redTop, redBottom, label.height, half, fraction - half, fraction + half))
        #expect(redTop < redBottom && redBottom - redTop > 0.1, "전제: 상자 빨강 띠를 못 쟀다(\(redTop)…\(redBottom))")
        #expect(fraction - half >= redBottom + 0.01, "빼빼로 근무 시계(\(fraction - half)…)가 상자(…\(redBottom))와 겹친다")
        #expect(fraction + half <= 0.98, "빼빼로 근무 시계가 패널 아래로 나간다(…\(fraction + half))")
        // 기준선: 옛 자리 0.49 는 상자 빨강 띠와 겹친다(그래서 옮겼다).
        let old = Double(CheckOverlayCharacterView.timerVerticalFraction)
        #expect(old + half > redTop && old - half < redBottom, "기준선: 옛 자리 \(old) 가 상자와 안 겹친다 — 재기가 눈이 멀었다")
        for other in [CharacterCatalog.builtInAingID, CharacterCatalog.isulAingID, CharacterCatalog.goldAingID] {
            #expect(CheckOverlayCharacterView.timerVerticalFraction(characterID: other) == CheckOverlayCharacterView.timerVerticalFraction, "\(other) 의 시계 자리가 바뀌었다")
        }
        // 부르는 자리: 실제 오버레이 뷰(3D 는 아직 안 선 상태 — 라벨만 그린다)가 착용 캐릭터로 자리를 고른다.
        func capsuleCenter(_ worn: String) throws -> Double {
            let defaults = CheckTestScratch.defaults("v0377-timer-\(worn)")
            defaults.set(worn, forKey: CharacterSelection.defaultsKey)
            let view = CheckOverlayCharacterView(elapsedSeconds: 3_600 + 23 * 60, isActive: false, characterDefaults: defaults)
                .frame(width: panel.width, height: panel.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let px = V0354GoldAingArtTests.rgba(image)
            var rows = [Int]()
            for y in 0..<image.height {
                var ink = 0
                for x in 0..<image.width where px[(y * image.width + x) * 4 + 3] > 60 { ink += 1 }
                if ink > 20 { rows.append(y) }
            }
            let lo = try #require(rows.min(), "\(worn): 라벨이 안 그려졌다"), hi = try #require(rows.max())
            return (Double(lo + hi) / 2 + 0.5) / Double(image.height)
        }
        let worn = try capsuleCenter(Self.id), plain = try capsuleCenter(CharacterCatalog.builtInAingID)
        print(String(format: "[v0377-fix] 그려진 라벨 가운데: 빼빼로 %.3f · 아잉 %.3f", worn, plain))
        #expect(abs(worn - fraction) < 0.03, "빼빼로를 입었는데 그려진 라벨 가운데가 \(worn) 다(기대 \(fraction))")
        #expect(abs(plain - old) < 0.03, "아잉 라벨 가운데가 \(plain) 다(기대 \(old))")
    }

    // MARK: ④ 그림 저장소(화면 · 3D low 5 · 6)

    static func markedBox(alpha: UInt8 = 255) throws -> Data {
        var px = V0354GoldAingArtTests.rgba(try V0377PeperoMac3DTests.bundledBox())
        px[0] = 0; px[1] = 200; px[2] = 0; px[3] = alpha
        return try #require(NSBitmapImageRep(cgImage: CakeAingFinish.makeImage(px, 1024, 1024)).representation(using: .png, properties: [:]))
    }

    @Test("판 풀기 ↔ 받기 경합: 판을 고르고 잠그기 전 틈에 새 판을 받아도, 그 뒤 판은 새 판이다(옛 URL 을 풀어 프로세스 내내 굳히지 않는다)")
    func boxImageSeesAbsorbBetweenResolveAndLock() throws {
        let art = PeperoArt(cacheDirectory: try V0377PeperoMac3DTests.scratchCache("race"), readsCache: true, usesNetwork: false)
        let bundled = try #require(PeperoArt.bundledURL(.box))
        #expect(art.url(.box) == bundled, "전제: 처음엔 번들 판을 고른다")
        let fresh = try Self.markedBox()
        let fired = OSAllocatedUnfairLock(initialState: false)
        art.boxImageWillLockForTesting = { [art] in
            guard fired.withLock({ was in defer { was = true }; return !was }) else { return }
            _ = art.absorb(kind: .box, status: 200, data: fresh, etag: "\"race\"")
        }
        let image = try #require(art.boxImage())
        art.boxImageWillLockForTesting = nil
        #expect(fired.withLock { $0 }, "전제: 끼움 자리가 안 불렸다")
        #expect(art.url(.box) == art.cacheFile(.box))
        let px = V0354GoldAingArtTests.rgba(image)
        #expect(px[0] == 0 && px[1] == 200 && px[2] == 0, "새 판을 받았는데 옛 판(번들)을 풀어 굳혔다 — 첫 점 \(px[0]),\(px[1]),\(px[2])")
        #expect(art.boxImage() === image)
    }

    @Test("못 쓰는 판(투명 화소 하나)을 받으면 그 ETag 를 적어 다음 조건부 요청에 단다 — 매 실행 같은 판을 다시 받고 버리지 않는다 · 쓸 만한 캐시가 있으면 둘 다 · 고친 판을 올리면(새 ETag) 받는다")
    func rejectedBoxIsRememberedByETag() throws {
        let art = PeperoArt(cacheDirectory: try V0377PeperoMac3DTests.scratchCache("rejected"), readsCache: true, usesNetwork: false)
        let bundled = try #require(PeperoArt.bundledURL(.box))
        let holed = try Self.markedBox(alpha: 254)
        #expect(PeperoArt.outcome(status: 200, data: holed, kind: .box) == .keep, "전제: 투명 화소 판은 못 쓴다")
        #expect(art.absorb(kind: .box, status: 200, data: holed, etag: "\"bad1\"") == .keep)
        #expect(art.url(.box) == bundled)
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == "\"bad1\"",
                "거절한 판의 ETag 를 안 단다 — 매 실행 8MB 를 다시 받는다")
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-Modified-Since") == nil, "쓸 만한 캐시가 없는데 If-Modified-Since 를 단다")
        // 고친 판(새 ETag)은 받는다 — 메타는 새 판의 것으로 바뀐다.
        #expect(art.absorb(kind: .box, status: 200, data: try Self.markedBox(), etag: "\"v2\"") == .replace)
        #expect(art.url(.box) == art.cacheFile(.box))
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == "\"v2\"")
        // 쓸 만한 캐시 위에 또 못 쓰는 판 — 둘 다 단다(어느 쪽이 지금 판이든 304).
        #expect(art.absorb(kind: .box, status: 200, data: holed, etag: "\"bad2\"") == .keep)
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == "\"v2\", \"bad2\"")
        #expect(art.url(.box) == art.cacheFile(.box), "못 쓰는 판이 쓸 만한 캐시를 밀어냈다")
    }

    /// 올리기 전 점검(대표가 Storage 에 올릴 판 · 초상) — `CHECK_PEPERO_ART_CANDIDATE_DIR` 에 box.png · neutral.png · negative.png 를 두고 돌린다.
    nonisolated static let candidateDirectory = ProcessInfo.processInfo.environment["CHECK_PEPERO_ART_CANDIDATE_DIR"]

    @Test("올리기 전 점검: 후보 그림이 앱 판정(판 1024² 불투명 · 초상 정사각 128 이상 · 8MB 이하)을 지난다", .enabled(if: candidateDirectory != nil))
    func uploadCandidatesPassTheAppVerdict() throws {
        let dir = URL(fileURLWithPath: try #require(Self.candidateDirectory))
        var seen = 0
        for kind in PeperoArt.Kind.allCases {
            let file = dir.appendingPathComponent(kind.fileName)
            guard let data = try? Data(contentsOf: file) else { continue }
            seen += 1
            #expect(PeperoArt.isAcceptable(data: data, kind: kind), "\(file.path): 앱이 거절한다 — 올리면 조용히 번들로 선다")
        }
        #expect(seen > 0, "\(dir.path) 에 box.png · neutral.png · negative.png 가 하나도 없다")
    }

    // MARK: ⑤ 생성기 산출물 ↔ 구획 상수(화면 · 3D low 7)

    @Test("번들 인쇄 판의 띠 사이 여백이 구획 상수와 맞다 — 위 절반은 위 띠 끝 줄 · 아래 절반은 아래 띠 첫 줄의 되풀이(생성기 규약). 띠 상수만 바꾸고 판을 다시 안 구우면 빨갛다")
    func bundledSheetMatchesTheBandRows() throws {
        let sheet = try V0377PeperoMac3DTests.bundledBox()
        #expect(sheet.width == Decor.sheetWidth && sheet.height == Decor.sheetHeight)
        let px = V0354GoldAingArtTests.rgba(sheet)
        let rowBytes = sheet.width * 4
        func row(_ y: Int) -> ArraySlice<UInt8> { px[(y * rowBytes)..<((y + 1) * rowBytes)] }
        let bands = [Decor.frontRows, Decor.backRows, Decor.sideRows]
        #expect(bands.first?.lowerBound == 0 && bands.last?.upperBound == Decor.sheetHeight, "띠가 판 위아래 끝까지 안 간다")
        for i in 0..<(bands.count - 1) {
            let upper = bands[i], lower = bands[i + 1]
            let gap = upper.upperBound..<lower.lowerBound
            #expect(gap.count >= 2, "띠 사이 여백이 \(gap) 다")
            // ★ 띠 끝 몇 줄은 같은 빨강 테라(앞 끝 줄 == 뒤 첫 줄 — 실측) 테 안에서 띠를 몇 줄 옮겨도 이 맞대기는 못 본다. 그 구멍은 아래
            //   `generatorOutputsArePinnedToTheRegion`(구획 ↔ 번들 세 장 한 벌 핀)이 막는다.
            var mismatched = [Int]()
            for y in gap {
                let source = y < gap.lowerBound + gap.count / 2 ? upper.upperBound - 1 : lower.lowerBound
                if row(y) != row(source) { mismatched.append(y) }
            }
            #expect(mismatched.isEmpty, "번들 판 여백 \(gap) 의 줄 \(mismatched.prefix(6)) 이 띠 끝 줄 되풀이가 아니다 — 띠 상수를 바꿨으면 생성기로 판 · 초상을 다시 구워라")
        }
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// 생성기 산출물 핀 — 구획(`// BEGIN pepero-decor` … `// END`, 주석 · 공백 걷은 글)의 SHA-256 과 **그 구획으로 구운** 번들 세 장의 SHA-256 을
    /// 한 벌로 못 박는다(2026-11-04, 078df8ed 산출물). 구획(띠 행 · 막대 자리 · 상자 치수 · 색)을 바꾸면 판 · 초상을 다시 구워야 하는데, 글자 맞대기
    /// (`generatorRegionIsVerbatim`)는 두 파일을 **같이** 고치면 초록이라 PNG 를 다시 안 구워도 인쇄가 어긋난 채 지나갔다(검토 low 7).
    static let generatorOutputPin = (
        region: "def62bc96d1e85e7cc09eb9ec492604eba0b6750db751bf41948be183bf9209a",
        box: "a96da6eb2e6fa726ebfd4c5f33cb19b5de0a5fc549ebd29680b14eea9d102d42",
        neutral: "20c4e35de9851b8cfa3659a79c1aa09c900580b3c37b7314837e7815c7eaa961",
        negative: "394fa8b6269342d20bf66bc23ff6951f5c0504f1849471b3d7f6d12121766a1d")

    @Test("생성기 산출물 핀: 장식 구획과 번들 세 장(판 · 초상 둘)이 한 벌이다 — 구획만 고치고 그림을 다시 안 구우면(또는 그 반대) 빨갛다")
    func generatorOutputsArePinnedToTheRegion() throws {
        let script = try V0366CakeMac3DTests.source("scripts/make-pepero-aing.swift")
        let region = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.region(script, from: "// BEGIN pepero-decor", to: "// END pepero-decor"))
        let regionDigest = Self.sha256(Data(region.utf8))
        func file(_ kind: PeperoArt.Kind) throws -> String { Self.sha256(try Data(contentsOf: try #require(PeperoArt.bundledURL(kind)))) }
        let actual = (region: regionDigest, box: try file(.box), neutral: try file(.neutral), negative: try file(.negative))
        print("[v0377-fix] 생성기 산출물: 구획 \(actual.region) · 판 \(actual.box) · neutral \(actual.neutral) · negative \(actual.negative)")
        let advice = "생성기(scripts/make-pepero-aing.swift)를 다시 돌려 판 · 초상 세 장을 다시 굽고(Resources/aing_pepero-*.png) 앱 구획을 옮긴 뒤 이 핀 넷을 같이 갈아라"
        #expect(actual.region == Self.generatorOutputPin.region, "장식 구획이 핀과 다르다(\(actual.region)) — \(advice)")
        #expect(actual.box == Self.generatorOutputPin.box && actual.neutral == Self.generatorOutputPin.neutral && actual.negative == Self.generatorOutputPin.negative,
                "번들 그림이 핀과 다르다 — \(advice)")
        // 기준선: 구획 글 한 글자가 바뀌면 다른 값이다.
        #expect(Self.sha256(Data(region.replacingOccurrences(of: "frontRows = 0..<396", with: "frontRows = 0..<390").utf8)) != regionDigest,
                "기준선: 띠 행을 바꿔도 구획 값이 같다 — 핀이 헛돈다")
    }

    /// 이 노드 지오메트리의 정점(물체 좌표).
    static func positions(_ node: SCNNode) throws -> [SIMD3<Float>] {
        let geometry = try #require(node.geometry, "몸 메시에 지오메트리가 없다")
        let source = try #require(geometry.sources(for: .vertex).first)
        #expect(source.usesFloatComponents && source.bytesPerComponent == 4 && source.componentsPerVector >= 3)
        var out = [SIMD3<Float>]()
        out.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0..<source.vectorCount {
                let base = source.dataOffset + i * source.dataStride
                out.append(SIMD3(raw.load(fromByteOffset: base, as: Float.self),
                                 raw.load(fromByteOffset: base + 4, as: Float.self),
                                 raw.load(fromByteOffset: base + 8, as: Float.self)))
            }
        }
        return out
    }

    @Test("팔 구멍: 앱 번들 aing.scn 몸 메시의 바깥 벽(|x| = a ± 0.006) 근처 정점이 구멍 타원 반지름 비 holeFit 안 — 생성기 armSectionCheck 와 같은 식(메시나 hole 상수가 바뀌면 앱 시험이 잡는다)")
    func armSectionFitsTheHole() throws {
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        // 몸 메시 = 캐릭터 노드 아래 정점이 가장 많은 지오메트리(aing.scn 은 캐릭터 노드가 곧 메시 노드 — 변환 단위, 물체 좌표 = 장식 좌표).
        var body: SCNNode?
        try V0354GoldAing3DTests.character(scene).enumerateHierarchy { node, _ in
            guard let count = node.geometry?.sources(for: .vertex).first?.vectorCount else { return }
            if count > (body?.geometry?.sources(for: .vertex).first?.vectorCount ?? 0) { body = node }
        }
        let bodyNode = try #require(body, "몸 메시를 못 찾았다")
        #expect(simd_equal(bodyNode.simdWorldTransform, try V0354GoldAing3DTests.character(scene).simdWorldTransform), "몸 메시 좌표가 캐릭터 노드 좌표가 아니다")
        let near = try Self.positions(bodyNode).filter { abs(abs($0.x) - Decor.a) < 0.006 && $0.y < Decor.y1 }
        #expect(near.count >= 8, "팔 단면 정점이 \(near.count) 개다 — 메시가 바뀌었다")
        var worst: Float = 0
        for p in near {
            let ey = (p.y - Decor.holeY) / Decor.holeHY, ez = (p.z - Decor.holeZ) / Decor.holeHZ
            worst = max(worst, (ey * ey + ez * ez).squareRoot())
        }
        print(String(format: "[v0377-fix] 팔 단면 정점 %d 개 · 구멍 타원 반지름 비 최대 %.3f(어두운 속 %.3f · 생성기 실측 0.949)", near.count, worst, Decor.holeFit))
        #expect(worst <= Decor.holeFit, "팔 단면이 구멍 어두운 속 밖으로 나간다(\(worst) > \(Decor.holeFit)) — hole* 상수를 생성기와 같이 고쳐라")
        #expect(worst > 0.5, "기준선: 팔 단면이 구멍에 비해 너무 작다(\(worst)) — 다른 정점을 잰다")
    }

    // MARK: ⑥ 패키징 대본(번호 · 회귀 low 4)

    static func buildScriptSnippet(_ script: String) -> String? {
        let lines = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        guard let start = lines.firstIndex(where: { $0.hasPrefix("PEPERO_ART_DIR=") }),
              let loop = lines[start...].firstIndex(where: { $0.hasPrefix("for PEPERO_PNG in ") }),
              let end = lines[loop...].firstIndex(where: { $0 == "done" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    @Test("맥 패키징 대본(build-local.sh): 빼빼로 그림 세 장을 센다 — 다 있으면 지나가고 하나 빠지면 멈춘다 · 이름은 앱이 '그릴 수 있다'를 재는 그 셋")
    func buildScriptChecksThePeperoArt() throws {
        let text = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let snippet = try #require(Self.buildScriptSnippet(text), "build-local.sh 에 빼빼로 그림 확인 고리가 없다 — 그림이 빠진 .app 이 번호 5 로 나간다")
        let names = PeperoAingFinish.requiredResourceNames()
        #expect(Set(names) == ["aing_pepero-box", "aing_pepero-neutral", "aing_pepero-negative"])
        #expect(try V0355GoldHaloYawTests.runSnippet(snippet, present: names) == 0, "세 장이 다 있는데 멈춘다")
        for missing in names {
            #expect(try V0355GoldHaloYawTests.runSnippet(snippet, present: names.filter { $0 != missing }) != 0, "\(missing) 이 빠져도 지나간다")
        }
    }

    nonisolated static let evidenceDirectory = V0377PeperoMac3DTests.evidenceDirectory
}
