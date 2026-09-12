import AppKit
import CoreGraphics
import Foundation
import Metal
import SceneKit
import Testing
@testable import check

// MARK: - v0.3.15 스프라이트 캐릭터 코어
//
// 아잉(3D)을 한 줄도 안 건드리고 2D 스프라이트를 같은 오버레이 씬에 세우기 위한 **순수 코어**를 지킨다.
// 여기 모인 것들은 전부 "화면은 멀쩡해 보이는데 조용히 틀리는" 자리다:
//
//  ① UV v 규약(`py = v × 높이`, **뒤집지 않는다**). 실측으로 가른 값인데, 대칭 이미지로 테스트하면 두 규약이
//     **영원히** 구별되지 않는다(모서리는 어느 쪽이든 투명하다). 그래서 픽스처를 **위 절반만 불투명**으로 만든다.
//  ② 평면 크기는 frontIdle 첫 프레임으로 **한 번만** 정한다. 프레임마다 리사이즈하면 걷는 동안 캐릭터가
//     커졌다 작아진다(픽스처 실측: 4족 passing 이 18.7% 주저앉았다).
//  ③ 매니페스트 검증은 디코드 시점 — 깨진 캐릭터가 카탈로그에 들어가면 화면에서 "안 보인다"로만 드러난다.
//  ④ 아잉은 매니페스트 파일이 없어도 카탈로그에 있다. 번들에 캐릭터 폴더가 하나도 없는 빌드에서도 앱이 산다.
//  ⑤ 프레임 재생기의 경계는 반열린 구간 [시작, 끝) — 경계에서 한 칸 밀리면 루프가 첫/끝 프레임을 두 번 낸다.
//
// 규약의 근거는 scratchpad/planeprobe(평면 hitTest·UV 실측)와 scratchpad/v0315-core/xformprobe(텍스처 변환
// 렌더 실측)다. 이 파일의 마지막 테스트가 그 렌더 실측을 스위트 안으로 끌고 들어온다.

// MARK: - 픽스처

private let v0315DefaultAtlasJSON = """
{
  "file": "atlas.png",
  "width": 128,
  "height": 64,
  "states": {
    "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false },
    "sideWalk": {
      "frames": [{"x":64,"y":0,"w":64,"h":64},{"x":0,"y":0,"w":64,"h":64}],
      "durationsMs": [120,120], "loop": true
    }
  }
}
"""

private let v0315DefaultPortraitJSON = """
{ "neutral": "portrait-neutral.png", "negative": "portrait-negative.png" }
"""

/// 매니페스트 JSON 한 장. 조각을 갈아 끼워 "이 한 곳만 틀린" 입력을 만든다.
private func v0315JSON(
    id: String = "fox",
    displayName: String = "여우",
    kind: String = "sprite",
    atlas: String? = v0315DefaultAtlasJSON,
    portrait: String? = v0315DefaultPortraitJSON
) -> Data {
    var fields = [
        "\"id\": \"\(id)\"",
        "\"displayName\": \"\(displayName)\"",
        "\"kind\": \"\(kind)\""
    ]
    if let atlas { fields.append("\"atlas\": \(atlas)") }
    if let portrait { fields.append("\"portrait\": \(portrait)") }
    return Data("{ \(fields.joined(separator: ",\n")) }".utf8)
}

private func v0315Decode(_ data: Data) throws -> CharacterManifest {
    try JSONDecoder().decode(CharacterManifest.self, from: data)
}

/// 1상태 아틀라스 JSON(프레임 rect 를 직접 지정해 "아틀라스 밖" 같은 경우를 만든다).
private func v0315AtlasJSON(
    width: Int = 128,
    height: Int = 64,
    file: String = "atlas.png",
    states: String
) -> String {
    """
    { "file": "\(file)", "width": \(width), "height": \(height), "states": \(states) }
    """
}

private func v0315SpriteManifest(
    id: String = "fox",
    atlasWidth: Int = 128,
    atlasHeight: Int = 64,
    states: [String: CharacterManifest.State] = [
        CharacterManifest.StateKey.frontIdle: CharacterManifest.State(
            frames: [CharacterManifest.Rect(x: 0, y: 0, w: 64, h: 64)], durationsMs: [0], loop: false
        )
    ]
) -> CharacterManifest {
    CharacterManifest(
        id: id,
        displayName: "여우",
        kind: .sprite,
        atlas: CharacterManifest.Atlas(file: "atlas.png", width: atlasWidth, height: atlasHeight, states: states),
        portrait: CharacterManifest.Portrait(neutral: "portrait-neutral.png", negative: "portrait-negative.png")
    )
}

/// RGBA8(premultipliedLast) 아틀라스. **데이터 행 0 = 이미지 위쪽** — CGImage 의 규약 그대로다.
/// `alpha`/`color` 는 (x, y) 를 받는다(y 는 위에서부터).
private func v0315Atlas(
    width: Int,
    height: Int,
    color: (Int, Int) -> (UInt8, UInt8, UInt8) = { _, _ in (200, 40, 160) },
    alpha: (Int, Int) -> UInt8
) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let rgb = color(x, y)
            let a = alpha(x, y)
            let i = (y * width + x) * 4
            // premultiplied: 알파가 0이면 색도 0이어야 한다(포맷 규약을 어기면 CG 가 조용히 다르게 해석한다).
            let scale = Double(a) / 255
            bytes[i] = UInt8(Double(rgb.0) * scale)
            bytes[i + 1] = UInt8(Double(rgb.1) * scale)
            bytes[i + 2] = UInt8(Double(rgb.2) * scale)
            bytes[i + 3] = a
        }
    }
    let data = CFDataCreate(nil, bytes, bytes.count)!
    let provider = CGDataProvider(data: data)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

/// 16비트/채널 아틀라스 — `CGDataProvider` 빠른 길이 **거절**하고 RGBA8 재드로 폴백으로 가는 포맷.
/// 이 길에서도 위/아래 방향이 보존되는지 확인하기 위한 픽스처다.
private func v0315Atlas16(width: Int, height: Int, alpha: (Int, Int) -> UInt16) -> CGImage {
    var words = [UInt16](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let a = alpha(x, y)
            let i = (y * width + x) * 4
            words[i] = a / 2; words[i + 1] = a / 4; words[i + 2] = a; words[i + 3] = a
        }
    }
    let data = words.withUnsafeBufferPointer { buffer in
        CFDataCreate(nil, UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self), buffer.count * 2)!
    }
    let provider = CGDataProvider(data: data)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

/// 임시 캐릭터 폴더를 만든다. `files` 는 파일명 → 내용.
@discardableResult
private func v0315WriteCharacter(root: URL, folder: String, manifest: Data?) -> URL {
    let dir = root.appendingPathComponent(folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let manifest {
        try? manifest.write(to: dir.appendingPathComponent("manifest.json"))
    }
    return dir
}

private func v0315TempRoot() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("v0315-characters-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Suite struct V0315CharacterCoreTests {

    // MARK: - ③ 매니페스트: 디코드 시점 검증

    @Test func 매니페스트_정상_스프라이트를_값_그대로_디코드한다() throws {
        let manifest = try v0315Decode(v0315JSON())
        #expect(manifest.id == "fox")
        #expect(manifest.displayName == "여우")
        #expect(manifest.kind == .sprite)
        let atlas = try #require(manifest.atlas)
        #expect(atlas.file == "atlas.png")
        #expect(atlas.width == 128 && atlas.height == 64)
        let walk = try #require(atlas.states[CharacterManifest.StateKey.sideWalk])
        #expect(walk.loop)
        #expect(walk.frames == [
            CharacterManifest.Rect(x: 64, y: 0, w: 64, h: 64),
            CharacterManifest.Rect(x: 0, y: 0, w: 64, h: 64)
        ])
        #expect(walk.durationsMs == [120, 120])
        #expect(manifest.portrait?.neutral == "portrait-neutral.png")
        #expect(manifest.portrait?.negative == "portrait-negative.png")
    }

    @Test func 매니페스트_같은_rect_를_반복하는_재생순서를_보존한다() throws {
        // 여우 걷기는 0,1,2,1 이다(픽스처 실측 결정). 중복 rect 를 "중복 제거"하는 순간 걸음이 3프레임으로 줄어든다.
        let states = """
        { "sideWalk": {
            "frames": [{"x":0,"y":0,"w":32,"h":64},{"x":32,"y":0,"w":32,"h":64},
                       {"x":64,"y":0,"w":32,"h":64},{"x":32,"y":0,"w":32,"h":64}],
            "durationsMs": [100,100,100,100], "loop": true },
          "frontIdle": { "frames": [{"x":0,"y":0,"w":32,"h":64}], "durationsMs": [0], "loop": false } }
        """
        let manifest = try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        let walk = try #require(manifest.atlas?.states[CharacterManifest.StateKey.sideWalk])
        #expect(walk.frames.count == 4)
        #expect(walk.frames[1] == walk.frames[3])
    }

    @Test func 매니페스트_프레임과_길이가_다르면_throw() {
        let states = """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64},{"x":64,"y":0,"w":64,"h":64}],
                         "durationsMs": [100], "loop": true } }
        """
        #expect(throws: CharacterManifestError.frameDurationMismatch(
            id: "fox", state: "frontIdle", frames: 2, durations: 1
        )) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        }
    }

    @Test func 매니페스트_아틀라스_밖_rect_는_throw() throws {
        // 오른쪽으로 1px 넘침 / 아래로 1px 넘침 / 음수 원점 / 크기 0 — 네 방향 전부.
        let cases: [(String, String)] = [
            ("오른쪽 초과", "{\"x\":65,\"y\":0,\"w\":64,\"h\":64}"),
            ("아래 초과", "{\"x\":0,\"y\":1,\"w\":64,\"h\":64}"),
            ("음수 원점", "{\"x\":-1,\"y\":0,\"w\":64,\"h\":64}"),
            ("폭 0", "{\"x\":0,\"y\":0,\"w\":0,\"h\":64}")
        ]
        for (label, rect) in cases {
            let states = "{ \"frontIdle\": { \"frames\": [\(rect)], \"durationsMs\": [0], \"loop\": false } }"
            #expect(throws: CharacterManifestError.rectOutsideAtlas(id: "fox", state: "frontIdle", index: 0),
                    "\(label) 가 통과했다") {
                try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
            }
        }
    }

    @Test func 매니페스트_빈_frames_는_throw() {
        let states = "{ \"frontIdle\": { \"frames\": [], \"durationsMs\": [], \"loop\": false } }"
        // frontIdle 이 비면 "필수 상태 없음"으로 먼저 걸린다(평면 크기를 못 정한다).
        #expect(throws: CharacterManifestError.missingRequiredState(id: "fox", state: "frontIdle")) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        }
        let withFront = """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false },
          "sideWalk": { "frames": [], "durationsMs": [], "loop": true } }
        """
        #expect(throws: CharacterManifestError.emptyFrames(id: "fox", state: "sideWalk")) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: withFront)))
        }
    }

    @Test func 매니페스트_frontIdle_이_없으면_throw() {
        let states = """
        { "sideWalk": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [100], "loop": true } }
        """
        #expect(throws: CharacterManifestError.missingRequiredState(id: "fox", state: "frontIdle")) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        }
    }

    @Test func 매니페스트_갈래와_에셋_조합이_어긋나면_throw() {
        // sprite 인데 아틀라스/초상이 없다 → 세울 수 없다.
        #expect(throws: CharacterManifestError.missingAtlas("fox")) {
            try v0315Decode(v0315JSON(atlas: nil))
        }
        #expect(throws: CharacterManifestError.missingPortrait("fox")) {
            try v0315Decode(v0315JSON(portrait: nil))
        }
        // scene3D 인데 아틀라스가 붙어 있다 → 아무도 안 읽는 데이터 = 거짓말이라 거절한다.
        #expect(throws: CharacterManifestError.unexpectedAtlas("aing")) {
            try v0315Decode(v0315JSON(id: "aing", kind: "scene3D", portrait: nil))
        }
        #expect(throws: CharacterManifestError.unexpectedPortrait("aing")) {
            try v0315Decode(v0315JSON(id: "aing", kind: "scene3D", atlas: nil))
        }
        // scene3D + 둘 다 없음 = 정상.
        #expect(throws: Never.self) {
            try v0315Decode(v0315JSON(id: "aing", displayName: "아잉", kind: "scene3D", atlas: nil, portrait: nil))
        }
    }

    @Test func 매니페스트_id_형식을_좁게_검사한다() {
        for bad in ["", "Fox", "fox_1", "fox/../etc", "여우", "fox 1", String(repeating: "a", count: 33)] {
            #expect(throws: CharacterManifestError.invalidID(bad), "'\(bad)' 가 통과했다") {
                try v0315Decode(v0315JSON(id: bad))
            }
        }
        for good in ["fox", "bot-2", "a", String(repeating: "a", count: 32)] {
            #expect(throws: Never.self, "'\(good)' 가 막혔다") { try v0315Decode(v0315JSON(id: good)) }
        }
    }

    @Test func 매니페스트_에셋_파일명은_폴더_밖을_못_가리킨다() {
        let escaped = v0315AtlasJSON(file: "../../aing.scn", states: """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false } }
        """)
        #expect(throws: CharacterManifestError.invalidAssetFileName(id: "fox", file: "../../aing.scn")) {
            try v0315Decode(v0315JSON(atlas: escaped))
        }
    }

    @Test func 매니페스트_여러_프레임인데_총길이가_0ms_면_throw() {
        // 화면은 멀쩡하고 아무 것도 안 빨개지는데 걷기가 영원히 첫 프레임에 멈춘다.
        let states = """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false },
          "sideWalk": { "frames": [{"x":0,"y":0,"w":64,"h":64},{"x":64,"y":0,"w":64,"h":64}],
                        "durationsMs": [0,0], "loop": true } }
        """
        #expect(throws: CharacterManifestError.zeroTotalDuration(id: "fox", state: "sideWalk")) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        }
        #expect(throws: CharacterManifestError.negativeDuration(id: "fox", state: "frontIdle", index: 0)) {
            try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: """
            { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [-1], "loop": false } }
            """)))
        }
    }

    @Test func 매니페스트_모르는_kind_는_throw_하고_모르는_상태키는_허용한다() throws {
        // 모르는 kind: 구버전 앱이 죽는 대신 그 캐릭터 하나만 목록에서 빠진다(카탈로그가 건너뛴다).
        #expect(throws: (any Error).self) {
            try v0315Decode(v0315JSON(kind: "hologram"))
        }
        // 모르는 상태 키: 나중에 상태가 늘어도 구버전이 그 캐릭터를 통째로 버리면 안 된다.
        let states = """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false },
          "backIdle": { "frames": [{"x":64,"y":0,"w":64,"h":64}], "durationsMs": [0], "loop": false } }
        """
        let manifest = try v0315Decode(v0315JSON(atlas: v0315AtlasJSON(states: states)))
        #expect(manifest.atlas?.states["backIdle"] != nil)
    }

    // MARK: - ④ 카탈로그: 아잉은 없어질 수 없다

    @Test func 카탈로그_캐릭터_폴더가_아예_없어도_아잉이_있다() {
        let catalog = CharacterCatalog.load(charactersDirectory: nil)
        #expect(catalog.allIDs == ["aing"])
        #expect(catalog.manifest(id: "aing")?.kind == .scene3D)
        #expect(catalog.manifest(id: "aing")?.displayName == "아잉")
        #expect(catalog.manifest(id: "aing")?.atlas == nil)
        // 실제 번들에서도 같다 — 캐릭터를 하나도 안 실은 빌드가 이 갈래의 기준선이다.
        let bundled = CharacterCatalog.load()
        #expect(bundled.allIDs.first == "aing")
        #expect(bundled.manifest(id: "aing")?.kind == .scene3D)
    }

    @Test func 카탈로그_깨진_캐릭터만_건너뛰고_나머지는_산다() throws {
        let root = v0315TempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        v0315WriteCharacter(root: root, folder: "fox", manifest: v0315JSON(id: "fox"))
        v0315WriteCharacter(root: root, folder: "bot", manifest: Data("{ not json".utf8))
        v0315WriteCharacter(root: root, folder: "cat", manifest: v0315JSON(id: "cat", atlas: v0315AtlasJSON(states: """
        { "frontIdle": { "frames": [{"x":0,"y":0,"w":999,"h":64}], "durationsMs": [0], "loop": false } }
        """)))                                                            // 아틀라스 밖 rect → 디코드 throw
        v0315WriteCharacter(root: root, folder: "dog", manifest: v0315JSON(id: "wolf"))  // 폴더명 ≠ id
        v0315WriteCharacter(root: root, folder: "empty", manifest: nil)                  // manifest.json 없음
        try Data("noise".utf8).write(to: root.appendingPathComponent("README.txt"))      // 폴더가 아닌 파일

        let catalog = CharacterCatalog.load(charactersDirectory: root)
        #expect(catalog.allIDs == ["aing", "fox"])
        #expect(catalog.manifest(id: "bot") == nil)
        #expect(catalog.manifest(id: "cat") == nil)
        #expect(catalog.manifest(id: "wolf") == nil)
    }

    @Test func 카탈로그_번들이_아잉_매니페스트를_실어도_내장_3D_가_이긴다() {
        let root = v0315TempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        v0315WriteCharacter(root: root, folder: "aing", manifest: v0315JSON(id: "aing", displayName: "가짜아잉"))

        let catalog = CharacterCatalog.load(charactersDirectory: root)
        // 폴백 대상이 스프라이트가 되면 "모르는 값 → 아잉" 안전망 자체가 스프라이트 파이프라인에 의존하게 된다.
        #expect(catalog.manifest(id: "aing")?.kind == .scene3D)
        #expect(catalog.manifest(id: "aing")?.displayName == "아잉")
        #expect(catalog.atlasURL(for: "aing") == nil)
    }

    @Test func 카탈로그_순서는_아잉_먼저_나머지는_정렬이다() {
        let catalog = CharacterCatalog(manifests: [
            v0315SpriteManifest(id: "zebra"), v0315SpriteManifest(id: "bot"), v0315SpriteManifest(id: "fox")
        ])
        #expect(catalog.allIDs == ["aing", "bot", "fox", "zebra"])
    }

    @Test func 카탈로그_에셋_URL_은_캐릭터_폴더_안을_가리킨다() throws {
        let root = v0315TempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = v0315WriteCharacter(root: root, folder: "fox", manifest: v0315JSON(id: "fox"))

        let catalog = CharacterCatalog.load(charactersDirectory: root)
        #expect(catalog.atlasURL(for: "fox") == dir.appendingPathComponent("atlas.png"))
        #expect(catalog.portraitURL(for: "fox", mood: .neutral) == dir.appendingPathComponent("portrait-neutral.png"))
        #expect(catalog.portraitURL(for: "fox", mood: .negative) == dir.appendingPathComponent("portrait-negative.png"))
        #expect(catalog.atlasURL(for: "없는캐릭터") == nil)
    }

    // MARK: - 선택 영속: 모르는 id 는 언제나 아잉

    @MainActor
    @Test func 선택_기본은_아잉이고_모르는_저장값은_아잉으로_접힌다() {
        let suiteName = "check-v0315-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = CharacterCatalog(manifests: [v0315SpriteManifest(id: "fox")])
        let selection = CharacterSelection(defaults: defaults, catalog: catalog)

        #expect(selection.selectedID == "aing")
        // 캐릭터를 뺀 빌드로 다운그레이드한 상황: 저장값은 남아 있지만 카탈로그에 없다.
        defaults.set("bot", forKey: CharacterSelection.defaultsKey)
        #expect(selection.selectedID == "aing")
        #expect(selection.selectedManifest.kind == .scene3D)
        // 저장값을 지우지는 않는다 — 그 캐릭터가 돌아오는 빌드에서 선택이 되살아나야 한다.
        #expect(defaults.string(forKey: CharacterSelection.defaultsKey) == "bot")
    }

    @MainActor
    @Test func 선택_카탈로그에_있는_것만_저장한다() {
        let suiteName = "check-v0315-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = CharacterCatalog(manifests: [v0315SpriteManifest(id: "fox")])
        let selection = CharacterSelection(defaults: defaults, catalog: catalog)

        #expect(selection.select("fox"))
        #expect(selection.selectedID == "fox")
        #expect(selection.selectedManifest.kind == .sprite)
        #expect(defaults.string(forKey: CharacterSelection.defaultsKey) == "fox")

        #expect(selection.select("모르는캐릭터") == false)
        #expect(defaults.string(forKey: CharacterSelection.defaultsKey) == "fox", "거절한 선택이 옛 값을 덮었다")
        #expect(selection.select("aing"))
        #expect(selection.selectedID == "aing")
    }

    // MARK: - ⑤ 프레임 재생기: 경계는 반열린 구간

    @Test func 재생기_경계에서_다음_프레임으로_넘어간다() {
        let state = CharacterManifest.State(
            frames: (0..<3).map { CharacterManifest.Rect(x: $0 * 32, y: 0, w: 32, h: 64) },
            durationsMs: [100, 100, 100], loop: true
        )
        let player = SpriteFramePlayer(state: state)
        #expect(player.totalDuration == 0.3)
        #expect(player.frameIndex(elapsed: 0) == 0)
        #expect(player.frameIndex(elapsed: 0.099) == 0)
        #expect(player.frameIndex(elapsed: 0.1) == 1, "경계는 [시작, 끝) — 정확히 0.1초면 다음 프레임이다")
        #expect(player.frameIndex(elapsed: 0.199) == 1)
        #expect(player.frameIndex(elapsed: 0.2) == 2)
        #expect(player.frameIndex(elapsed: 0.299) == 2)
        // 한 바퀴 경계: 0.3 은 두 바퀴째의 0초다(마지막 프레임을 두 번 내면 걸음이 절뚝인다).
        #expect(player.frameIndex(elapsed: 0.3) == 0)
        #expect(player.frameIndex(elapsed: 0.35) == 0)
        #expect(player.frameIndex(elapsed: 0.45) == 1)
        #expect(player.frameIndex(elapsed: 0.6) == 0, "두 바퀴를 정확히 돌면 다시 0번")
        #expect(player.frameIndex(elapsed: 3.05) == 0, "열 바퀴를 돌아도 누적 오차로 밀리지 않는다")
        #expect(player.frameIndex(elapsed: -1) == 0, "음수는 시작 프레임")
    }

    @Test func 재생기_논루프는_마지막_프레임에서_멈춘다() {
        let state = CharacterManifest.State(
            frames: (0..<3).map { CharacterManifest.Rect(x: $0 * 32, y: 0, w: 32, h: 64) },
            durationsMs: [100, 100, 100], loop: false
        )
        let player = SpriteFramePlayer(state: state)
        #expect(player.frameIndex(elapsed: 0.25) == 2)
        #expect(player.frameIndex(elapsed: 0.3) == 2)
        #expect(player.frameIndex(elapsed: 9_999) == 2)
    }

    @Test func 재생기_총길이가_0이면_항상_첫_프레임이다() {
        // 정지 상태(1프레임·0ms)는 정상 입력이다. 0 나눗셈으로 NaN 인덱스를 만들면 안 된다.
        let still = SpriteFramePlayer(state: CharacterManifest.State(
            frames: [CharacterManifest.Rect(x: 0, y: 0, w: 64, h: 64)], durationsMs: [0], loop: false
        ))
        #expect(still.totalDuration == 0)
        #expect(still.frameIndex(elapsed: 0) == 0)
        #expect(still.frameIndex(elapsed: 12.5) == 0)
        #expect(still.frameIndex(elapsed: .infinity) == 0)
        // 빈 상태(매니페스트 검증이 막지만, 메모리에서 만들어질 수는 있다)도 죽지 않는다.
        let empty = SpriteFramePlayer(state: CharacterManifest.State(frames: [], durationsMs: [], loop: true))
        #expect(empty.frameIndex(elapsed: 1) == 0)
    }

    @Test func 재생기_0121_재생순서를_그대로_돌려준다() {
        // 여우 걷기(픽스처 실측 결정): 접지A → passing → 접지B → passing.
        let passing = CharacterManifest.Rect(x: 32, y: 0, w: 32, h: 64)
        let state = CharacterManifest.State(
            frames: [
                CharacterManifest.Rect(x: 0, y: 0, w: 32, h: 64), passing,
                CharacterManifest.Rect(x: 64, y: 0, w: 32, h: 64), passing
            ],
            durationsMs: [110, 110, 110, 110], loop: true
        )
        let player = SpriteFramePlayer(state: state)
        let played = stride(from: 0.0, to: 0.44, by: 0.11).map { state.frames[player.frameIndex(elapsed: $0)] }
        #expect(played == state.frames)
        #expect(played[1] == played[3], "passing 프레임이 두 번 나와야 걸음이 된다")
    }

    // MARK: - ① 알파 마스크: v 를 뒤집으면 여기가 빨개진다

    /// ★ 이 갈래의 핵심 회귀 방지. **위 절반만 불투명한** 비대칭 픽스처가 아니면 두 UV 규약이 영원히 구별되지 않는다.
    @Test func 마스크_UV_v_를_뒤집지_않는다() throws {
        let height = 64
        let atlas = v0315Atlas(width: 64, height: height) { _, y in y < height / 2 ? 255 : 0 }

        // (정답지) 이 픽스처의 "데이터 행 0" 이 정말 이미지 위쪽인지 독립 경로로 확인한다.
        // NSBitmapImageRep 의 colorAt(y:) 은 y=0 이 이미지 위쪽이다(planeprobe 가 쓴 그 좌표계).
        let rep = NSBitmapImageRep(cgImage: atlas)
        #expect(rep.colorAt(x: 32, y: 2)?.alphaComponent == 1.0, "픽스처 위쪽이 불투명해야 한다")
        #expect(rep.colorAt(x: 32, y: 61)?.alphaComponent == 0.0, "픽스처 아래쪽이 투명해야 한다")

        let mask = try #require(SpriteAlphaMask(atlas: atlas, states: [:]))
        // ★ py = v × 높이. v 가 작을수록 이미지 **위쪽**이다(scratchpad/planeprobe/uvprobe.swift 실측).
        //   뒤집은 구현이면 이 두 줄이 정확히 반대로 나온다.
        #expect(mask.isOpaque(u: 0.5, v: 0.05), "v=0.05(위쪽)는 불투명해야 한다 — 실패하면 v 를 뒤집은 것이다")
        #expect(mask.isOpaque(u: 0.5, v: 0.95) == false, "v=0.95(아래쪽)는 투명해야 한다")
        #expect(mask.isOpaque(u: 0.5, v: 0.49))
        #expect(mask.isOpaque(u: 0.5, v: 0.51) == false)
        // 경계 끝값도 가장자리로 물려 읽는다(wrapS/T = .clamp 와 같은 규약).
        #expect(mask.isOpaque(u: 0, v: 0))
        #expect(mask.isOpaque(u: 1, v: 1) == false)
        #expect(mask.width == 64 && mask.height == 64)
    }

    @Test func 마스크_몸통은_불투명_여백은_투명이다() throws {
        // 가운데 원만 불투명한 캐릭터. 평면은 네모라 hitTest 는 모서리도 맞힌다 — 그 차이를 마스크가 만든다.
        let size = 64
        let atlas = v0315Atlas(width: size, height: size) { x, y in
            let dx = Double(x) - 31.5, dy = Double(y) - 31.5
            return (dx * dx + dy * dy) < 18 * 18 ? 255 : 0
        }
        let mask = try #require(SpriteAlphaMask(atlas: atlas, states: [:]))
        #expect(mask.isOpaque(u: 0.5, v: 0.5), "몸통 중앙")
        for (u, v) in [(0.02, 0.02), (0.98, 0.02), (0.02, 0.98), (0.98, 0.98)] {
            #expect(mask.isOpaque(u: CGFloat(u), v: CGFloat(v)) == false, "모서리 여백 (\(u),\(v))")
        }
    }

    @Test func 마스크_임계값_아래_알파는_투명으로_본다() throws {
        let atlas = v0315Atlas(width: 8, height: 8) { x, _ in x < 4 ? 20 : 200 }
        let low = try #require(SpriteAlphaMask(atlas: atlas, states: [:], threshold: 32))
        #expect(low.isOpaque(u: 0.1, v: 0.5) == false, "알파 20 은 임계값 32 아래라 투명")
        #expect(low.isOpaque(u: 0.9, v: 0.5))
        let permissive = try #require(SpriteAlphaMask(atlas: atlas, states: [:], threshold: 8))
        #expect(permissive.isOpaque(u: 0.1, v: 0.5), "임계값을 낮추면 알파 20 도 몸이다")
    }

    @Test func 마스크_매니페스트와_실제_아틀라스가_어긋나면_nil() throws {
        let atlas = v0315Atlas(width: 64, height: 64) { _, _ in 255 }
        // 팩 스크립트를 다시 돌리다 한쪽만 커밋한 상황: 매니페스트는 128 폭을 말하는데 PNG 는 64 다.
        let states = [CharacterManifest.StateKey.frontIdle: CharacterManifest.State(
            frames: [CharacterManifest.Rect(x: 64, y: 0, w: 64, h: 64)], durationsMs: [0], loop: false
        )]
        #expect(SpriteAlphaMask(atlas: atlas, states: states) == nil)
        // 아틀라스 안에 들어오는 rect 면 정상.
        let fitting = [CharacterManifest.StateKey.frontIdle: CharacterManifest.State(
            frames: [CharacterManifest.Rect(x: 0, y: 0, w: 64, h: 64)], durationsMs: [0], loop: false
        )]
        #expect(SpriteAlphaMask(atlas: atlas, states: fitting) != nil)
    }

    @Test func 마스크_포맷이_달라도_방향이_보존된다() throws {
        // 16비트/채널은 CGDataProvider 빠른 길이 거절하고 RGBA8 재드로 폴백으로 간다.
        // 그 길에서도 행 0 = 위쪽이 유지돼야 한다(안 그러면 특정 PNG 에서만 클릭이 상하로 뒤집힌다).
        let height = 64
        let atlas16 = v0315Atlas16(width: 64, height: height) { _, y in y < height / 2 ? 0xFFFF : 0 }
        let mask = try #require(SpriteAlphaMask(atlas: atlas16, states: [:]))
        #expect(mask.isOpaque(u: 0.5, v: 0.05))
        #expect(mask.isOpaque(u: 0.5, v: 0.95) == false)

        // 알파 채널이 없는 이미지는 전부 몸이다(투명 여백이라는 개념이 없다).
        let opaqueOnly = CGImage(
            width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: CFDataCreate(nil, [UInt8](repeating: 0, count: 8 * 32), 8 * 32)!)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let noAlpha = try #require(SpriteAlphaMask(atlas: opaqueOnly, states: [:]))
        #expect(noAlpha.isOpaque(u: 0.5, v: 0.5))
        #expect(noAlpha.isOpaque(u: 0.01, v: 0.99))
    }

    // MARK: - ② 노드: 크기는 아잉과 같고, 프레임이 바뀌어도 흔들리지 않는다

    @MainActor
    @Test func 노드_최장변이_아잉_bbox_와_같다() throws {
        let atlas = v0315Atlas(width: 128, height: 64) { _, _ in 255 }
        // 정사각 프레임.
        let square = try #require(SpriteCharacterNode.make(manifest: v0315SpriteManifest(), atlas: atlas))
        #expect(square.name == "check.spriteCharacter")
        let (minB, maxB) = square.boundingBox
        let extent = max(CGFloat(maxB.x - minB.x), CGFloat(maxB.y - minB.y))
        #expect(abs(extent - SpriteCharacterNode.targetExtent) < 1e-3,
                "카메라 구도(addFramingCamera)와 리액션 진폭(modelExtent)이 둘 다 이 값에서 나온다")
        #expect(abs(SpriteCharacterNode.targetExtent - 1.9210) < 1e-9, "aing.scn 실측값이다")

        // 세로로 긴 프레임: 최장변이 targetExtent, 나머지는 종횡비.
        let tall = try #require(SpriteCharacterNode.make(
            manifest: v0315SpriteManifest(atlasWidth: 64, atlasHeight: 128, states: [
                CharacterManifest.StateKey.frontIdle: CharacterManifest.State(
                    frames: [CharacterManifest.Rect(x: 0, y: 0, w: 32, h: 128)], durationsMs: [0], loop: false
                )
            ]),
            atlas: v0315Atlas(width: 64, height: 128) { _, _ in 255 }
        ))
        let plane = try #require(tall.geometry as? SCNPlane)
        #expect(abs(plane.height - SpriteCharacterNode.targetExtent) < 1e-3)
        #expect(abs(plane.width - SpriteCharacterNode.targetExtent / 4) < 1e-3, "32:128 종횡비가 보존돼야 한다")
    }

    @MainActor
    @Test func 노드_프레임을_바꿔도_평면_크기가_그대로다() throws {
        // ★ 픽스처 실측에서 4족 passing 프레임이 18.7% 주저앉은 그 결함. 크기는 frontIdle 첫 프레임으로 한 번만 정한다.
        let atlas = v0315Atlas(width: 128, height: 128) { _, _ in 255 }
        let node = try #require(SpriteCharacterNode.make(manifest: v0315SpriteManifest(atlasHeight: 128), atlas: atlas))
        let plane = try #require(node.geometry as? SCNPlane)
        let before = (plane.width, plane.height)
        let beforeBox = node.boundingBox

        // 크기가 전혀 다른 프레임(가로로 납작한 걷기 셀)을 먹인다.
        SpriteCharacterNode.apply(
            frame: CharacterManifest.Rect(x: 0, y: 64, w: 128, h: 40),
            mirrored: false, to: node, atlasSize: CGSize(width: 128, height: 128)
        )
        #expect(plane.width == before.0 && plane.height == before.1, "프레임 교체가 평면을 리사이즈했다")
        #expect(node.boundingBox.max.y == beforeBox.max.y)

        // 미러도 크기를 바꾸지 않는다(부호는 텍스처 변환에만 접힌다).
        SpriteCharacterNode.apply(
            frame: CharacterManifest.Rect(x: 0, y: 64, w: 128, h: 40),
            mirrored: true, to: node, atlasSize: CGSize(width: 128, height: 128)
        )
        #expect(plane.width == before.0 && plane.height == before.1)
        #expect(node.boundingBox.min.x == beforeBox.min.x && node.boundingBox.max.x == beforeBox.max.x)
    }

    @MainActor
    @Test func 노드_재질은_unlit_양면_알파_clamp_다() throws {
        let atlas = v0315Atlas(width: 128, height: 64) { _, _ in 255 }
        let node = try #require(SpriteCharacterNode.make(manifest: v0315SpriteManifest(), atlas: atlas))
        let material = try #require(node.geometry?.firstMaterial)
        #expect(material.lightingModel == .constant, "앱이 광원을 안 쓴다 — PBR 이면 캐릭터가 허옇게 뜬다")
        #expect(material.isDoubleSided, "y 스핀(commuteStart)에서 뒷면이 보인다")
        #expect(material.transparencyMode == .aOne)
        #expect(material.diffuse.wrapS == .clamp && material.diffuse.wrapT == .clamp,
                "clamp 가 아니면 셀 경계에서 이웃 프레임이 새어 들어온다")
        #expect(CFGetTypeID(material.diffuse.contents as CFTypeRef) == CGImage.typeID,
                "CF 불투명 타입은 as? 가 항상 성공하므로 typeID 로 판별한다")
    }

    @MainActor
    @Test func 노드_스프라이트가_아니거나_에셋이_어긋나면_nil() throws {
        let atlas = v0315Atlas(width: 128, height: 64) { _, _ in 255 }
        #expect(SpriteCharacterNode.make(manifest: CharacterCatalog.builtInAing, atlas: atlas) == nil,
                "3D 아잉은 이 경로로 만들지 않는다")
        // 매니페스트는 256 폭을 말하는데 PNG 는 128 — 모든 프레임이 어긋난 채 조용히 돌 바에는 아잉으로 접는다.
        #expect(SpriteCharacterNode.make(manifest: v0315SpriteManifest(atlasWidth: 256), atlas: atlas) == nil)
    }

    // MARK: - 텍스처 변환: contentsTransform 과 히트테스트 식이 갈리지 않는다

    @MainActor
    @Test func 변환_셀을_정확히_가리키고_미러는_x_부호로_접힌다() {
        let size = CGSize(width: 128, height: 64)
        let frame = CharacterManifest.Rect(x: 64, y: 0, w: 64, h: 64)   // 오른쪽 셀
        let transform = SpriteCharacterNode.contentsTransform(frame: frame, mirrored: false, atlasSize: size)
        // SceneKit 은 행벡터(uv' = uv × M) — 이동이 m41/m42 다.
        #expect(abs(transform.m11 - 0.5) < 1e-6)
        #expect(abs(transform.m22 - 1.0) < 1e-6)
        #expect(abs(transform.m41 - 0.5) < 1e-6)
        #expect(abs(transform.m42 - 0.0) < 1e-6)

        let mirrored = SpriteCharacterNode.contentsTransform(frame: frame, mirrored: true, atlasSize: size)
        #expect(abs(mirrored.m11 + 0.5) < 1e-6, "미러는 x 스케일 부호를 뒤집는다")
        #expect(abs(mirrored.m41 - 1.0) < 1e-6, "뒤집은 만큼 오프셋이 셀 오른쪽 끝으로 간다")
        #expect(abs(mirrored.m22 - transform.m22) < 1e-6, "세로는 건드리지 않는다")
    }

    @MainActor
    @Test func 변환_히트테스트_식이_contentsTransform_과_같다() {
        // 두 식이 갈리면 클릭 판정이 **다른 프레임의 알파**를 본다(걷는 동안만 클릭이 빗나가는 결함).
        let size = CGSize(width: 256, height: 128)
        let frames = [
            CharacterManifest.Rect(x: 0, y: 0, w: 64, h: 64),
            CharacterManifest.Rect(x: 64, y: 64, w: 128, h: 64),
            CharacterManifest.Rect(x: 192, y: 0, w: 64, h: 128)
        ]
        for frame in frames {
            for mirrored in [false, true] {
                let matrix = SpriteCharacterNode.contentsTransform(frame: frame, mirrored: mirrored, atlasSize: size)
                for uv in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.25, y: 0.75)] {
                    let byMatrix = CGPoint(x: uv.x * matrix.m11 + matrix.m41, y: uv.y * matrix.m22 + matrix.m42)
                    let byHelper = SpriteCharacterNode.atlasUV(
                        planeUV: uv, frame: frame, mirrored: mirrored, atlasSize: size
                    )
                    #expect(abs(byMatrix.x - byHelper.x) < 1e-6 && abs(byMatrix.y - byHelper.y) < 1e-6,
                            "frame=\(frame) mirrored=\(mirrored) uv=\(uv)")
                }
            }
        }
        // 정방향 코너 대응(★ v 를 뒤집지 않는다: uv.y=0 → 프레임 **위쪽** 줄).
        let frame = frames[1]
        let topLeft = SpriteCharacterNode.atlasUV(planeUV: .zero, frame: frame, mirrored: false, atlasSize: size)
        #expect(abs(topLeft.x - 0.25) < 1e-6 && abs(topLeft.y - 0.5) < 1e-6)
        let bottomRight = SpriteCharacterNode.atlasUV(
            planeUV: CGPoint(x: 1, y: 1), frame: frame, mirrored: false, atlasSize: size
        )
        #expect(abs(bottomRight.x - 0.75) < 1e-6 && abs(bottomRight.y - 1.0) < 1e-6)
        // 미러면 좌우 코너만 맞바뀌고 세로는 그대로다.
        let mirroredTopLeft = SpriteCharacterNode.atlasUV(planeUV: .zero, frame: frame, mirrored: true, atlasSize: size)
        #expect(abs(mirroredTopLeft.x - 0.75) < 1e-6 && abs(mirroredTopLeft.y - 0.5) < 1e-6)
    }

    /// 규약을 **픽셀로** 확정한다: 4색 아틀라스에서 한 셀을 지정해 실제로 렌더하고 화면 색을 읽는다.
    /// 계산으로 증명할 수 없는 유일한 부분(SceneKit 이 텍스처를 어느 방향으로 붙이는가)이 여기서 갈린다 —
    /// scratchpad/v0315-core/xformprobe 로 먼저 잰 것과 같은 실험이다.
    @MainActor
    @Test func 변환_실제_렌더가_지정한_셀을_그린다() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }   // GPU 없는 환경이면 건너뛴다.
        // 좌상 빨강 / 우상 초록 / 좌하 파랑 / 우하 노랑.
        let atlas = v0315Atlas(width: 128, height: 128, color: { x, y in
            switch (y < 64, x < 64) {
            case (true, true): return (255, 0, 0)
            case (true, false): return (0, 255, 0)
            case (false, true): return (0, 0, 255)
            case (false, false): return (255, 255, 0)
            }
        }, alpha: { _, _ in 255 })

        func rendered(frame: CharacterManifest.Rect, mirrored: Bool) throws -> [String] {
            let manifest = v0315SpriteManifest(atlasWidth: 128, atlasHeight: 128, states: [
                CharacterManifest.StateKey.frontIdle: CharacterManifest.State(
                    frames: [frame], durationsMs: [0], loop: false
                )
            ])
            let node = try #require(SpriteCharacterNode.make(manifest: manifest, atlas: atlas))
            SpriteCharacterNode.apply(frame: frame, mirrored: mirrored, to: node,
                                      atlasSize: CGSize(width: 128, height: 128))
            let scene = SCNScene()
            scene.background.contents = NSColor.black
            scene.rootNode.addChildNode(node)
            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 1.5      // 가시 높이 3.0 → 평면(1.921)이 화면의 64% 를 차지한다.
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 5)
            scene.rootNode.addChildNode(cameraNode)

            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = scene
            renderer.pointOfView = cameraNode
            renderer.autoenablesDefaultLighting = false
            let image = renderer.snapshot(atTime: 0, with: NSSize(width: 200, height: 200), antialiasingMode: .none)
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            // 사분면 중심(뷰 픽셀 y=0 이 위쪽): 좌상 · 우상 · 좌하 · 우하 순서.
            let w = rep.pixelsWide, h = rep.pixelsHigh
            return [(0.35, 0.35), (0.65, 0.35), (0.35, 0.65), (0.65, 0.65)].map { fx, fy in
                guard let c = rep.colorAt(x: Int(Double(w) * fx), y: Int(Double(h) * fy))?
                    .usingColorSpace(.deviceRGB) else { return "?" }
                let r = c.redComponent > 0.5, g = c.greenComponent > 0.5, b = c.blueComponent > 0.5
                if r && !g && !b { return "빨강" }
                if !r && g && !b { return "초록" }
                if !r && !g && b { return "파랑" }
                if r && g && !b { return "노랑" }
                return "기타"
            }
        }

        let whole = CharacterManifest.Rect(x: 0, y: 0, w: 128, h: 128)
        #expect(try rendered(frame: whole, mirrored: false) == ["빨강", "초록", "파랑", "노랑"],
                "★ v 를 뒤집으면 위아래가 바뀐다(파랑/노랑이 위로 온다)")
        #expect(try rendered(frame: CharacterManifest.Rect(x: 64, y: 0, w: 64, h: 64), mirrored: false)
                == ["초록", "초록", "초록", "초록"], "우상 셀만 그려야 한다")
        #expect(try rendered(frame: CharacterManifest.Rect(x: 0, y: 64, w: 64, h: 64), mirrored: false)
                == ["파랑", "파랑", "파랑", "파랑"], "좌하 셀만 그려야 한다")
        #expect(try rendered(frame: whole, mirrored: true) == ["초록", "빨강", "노랑", "파랑"],
                "미러는 좌우만 바꾼다(위아래는 그대로)")
    }
}
