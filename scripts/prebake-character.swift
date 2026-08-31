#!/usr/bin/env swift
// 아잉 캐릭터 프리베이크(v0.2.38 M3): aing.usdz → aing.scn
//
// 사용법:  swift scripts/prebake-character.swift [입력.usdz] [출력.scn]
// 기본값:  Sources/check/Resources/aing.usdz → Sources/check/Resources/aing.scn (저장소 루트에서 실행)
//
// 무엇을 굽나: 런타임 `CheckCharacter3DScene.applyUnlitMaterials` 가 매 실행마다 하던 일 — 모든 재질을 unlit(.constant)
// 으로 바꾸고, usdz 아카이브 참조 텍스처(...usdz?offset=N&size=M, 2048²)를 디코드해 512px 로 리샘플 — 을 한 번만 하고
// 그 결과 씬을 SceneKit 네이티브 아카이브(.scn)로 저장한다. 앱은 .scn 을 우선 읽고(USD/ModelIO 상주·USD 워커 스레드
// 11개·2048² 디코드 전부 회피) 없거나 못 읽으면 usdz 로 폴백한다.
//
// 이 스크립트는 앱 모듈을 링크하지 않는다(단독 실행). 그래서 리샘플 알고리즘(deviceRGB · premultipliedLast · .high)을
// 런타임과 **같게** 여기 한 번 더 적는다 — 둘이 갈리면 Tests/checkTests/V0238CharacterTests.swift 의 ".scn 계약 = usdz 계약"
// 테스트(노드·바운딩박스·재질·텍스처 치수·픽셀 비교)가 빨개진다.
//
// 어떤 것은 굽지 않나: 리액션 wrapper/facing 노드·카메라·감은 눈 노드·idle 액션은 런타임 `makeScene` 이 두 출처에
// 동일하게 얹는다. 산출물은 "임포트 직후 + 재질 베이크"까지만이라 로더가 출처를 구분할 필요가 없다.

import AppKit
import SceneKit

let args = CommandLine.arguments
let inputPath = args.count > 1 ? args[1] : "Sources/check/Resources/aing.usdz"
let outputPath = args.count > 2 ? args[2] : "Sources/check/Resources/aing.scn"
let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)
let maxDimension: CGFloat = 512

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("prebake-character: " + message + "\n").data(using: .utf8)!)
    exit(1)
}
func now() -> Double { CFAbsoluteTimeGetCurrent() }

// MARK: - 텍스처 디코드/리샘플(런타임 CheckCharacter3DScene 과 동일 알고리즘)

/// `...aing.usdz?offset=N&size=M` 아카이브 참조 URL 디코드(usdz 는 stored zip 이라 그 구간이 곧 이미지 원본).
func decodeArchiveURL(_ url: URL) -> CGImage? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems,
          let offset = items.first(where: { $0.name == "offset" })?.value.flatMap(Int.init),
          let size = items.first(where: { $0.name == "size" })?.value.flatMap(Int.init)
    else {
        return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    var fileComponents = components
    fileComponents.queryItems = nil
    guard let fileURL = fileComponents.url, offset >= 0, size > 0,
          let handle = try? FileHandle(forReadingFrom: fileURL),
          (try? handle.seek(toOffset: UInt64(offset))) != nil,
          let data = try? handle.read(upToCount: size), data.count == size
    else { return nil }
    return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func decodedTexture(_ contents: Any?) -> CGImage? {
    guard let contents else { return nil }
    let source: CGImage?
    if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
        source = (contents as! CGImage)
    } else if let image = contents as? NSImage {
        source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    } else if let url = contents as? URL {
        source = decodeArchiveURL(url)
    } else if let path = contents as? String {
        source = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    } else if let data = contents as? Data {
        source = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    } else {
        return nil
    }
    guard let cg = source, cg.width >= 8, cg.height >= 8 else { return nil }
    return cg
}

func resampled(_ cg: CGImage, maxDimension: CGFloat) -> CGImage? {
    let maxSide = max(cg.width, cg.height)
    guard maxSide > Int(maxDimension) else { return nil }
    let scale = maxDimension / CGFloat(maxSide)
    let newWidth = max(1, Int((CGFloat(cg.width) * scale).rounded()))
    let newHeight = max(1, Int((CGFloat(cg.height) * scale).rounded()))
    guard let context = CGContext(
        data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    return context.makeImage()
}

// MARK: - 씬 지문(검증용)

struct Fingerprint: Equatable, CustomStringConvertible {
    var names: [String]
    var vertexCounts: [Int]
    var primitiveCounts: [Int]
    var bbox: [Float]
    var description: String {
        "nodes=\(names.count) names=\(names) verts=\(vertexCounts) prims=\(primitiveCounts) bbox=\(bbox)"
    }
}
func fingerprint(_ scene: SCNScene) -> Fingerprint {
    var names = [String](), verts = [Int](), prims = [Int]()
    scene.rootNode.enumerateHierarchy { node, _ in
        names.append(node.name ?? "")
        if let geometry = node.geometry {
            verts.append(geometry.sources(for: .vertex).first?.vectorCount ?? 0)
            prims.append(geometry.elements.reduce(0) { $0 + $1.primitiveCount })
        }
    }
    let (minB, maxB) = scene.rootNode.boundingBox
    let bbox = [minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z].map { (Float($0) * 10_000).rounded() / 10_000 }
    return Fingerprint(names: names, vertexCounts: verts, primitiveCounts: prims, bbox: bbox)
}

// MARK: - 1) 로드

guard FileManager.default.fileExists(atPath: inputURL.path) else { fail("입력이 없다: \(inputURL.path)") }
var t0 = now()
let scene: SCNScene
do { scene = try SCNScene(url: inputURL, options: nil) } catch { fail("usdz 로드 실패: \(error)") }
let loadMs = (now() - t0) * 1_000
let before = fingerprint(scene)
print("[load] \(inputURL.lastPathComponent) \(String(format: "%.1f", loadMs))ms  \(before)")

// MARK: - 2) 베이크(unlit + 512 리샘플, CGImage 로)

t0 = now()
var materialCount = 0, bakedCount = 0
scene.rootNode.enumerateHierarchy { node, _ in
    node.geometry?.materials.forEach { material in
        materialCount += 1
        material.lightingModel = .constant
        guard let decoded = decodedTexture(material.diffuse.contents) else { return }
        let baked = resampled(decoded, maxDimension: maxDimension) ?? decoded
        material.diffuse.contents = baked
        bakedCount += 1
        print("[bake] \(node.name ?? "-"): \(decoded.width)x\(decoded.height) → \(baked.width)x\(baked.height)")
    }
}
let bakeMs = (now() - t0) * 1_000
guard materialCount > 0, bakedCount > 0 else { fail("베이크할 재질/텍스처가 없다(materials=\(materialCount), baked=\(bakedCount))") }
print("[bake] materials=\(materialCount) baked=\(bakedCount) \(String(format: "%.1f", bakeMs))ms")

// MARK: - 3) 저장

try? FileManager.default.removeItem(at: outputURL)
t0 = now()
guard scene.write(to: outputURL, options: nil, delegate: nil, progressHandler: nil) else { fail("write(to:) 실패: \(outputURL.path)") }
let writeMs = (now() - t0) * 1_000
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? -1
print("[write] \(outputURL.path) \(bytes) bytes (\(String(format: "%.2f", Double(bytes) / 1_048_576)) MiB) \(String(format: "%.1f", writeMs))ms")

// MARK: - 4) 재로드 검증(로더 계약: 지문 동일 · 재질 .constant · 텍스처 ≤512 로 디코드 가능)

t0 = now()
let reloaded: SCNScene
do { reloaded = try SCNScene(url: outputURL, options: nil) } catch { fail("산출물 재로드 실패: \(error)") }
let reloadMs = (now() - t0) * 1_000
let after = fingerprint(reloaded)
guard after == before else { fail("지문 불일치\n  before: \(before)\n  after:  \(after)") }
var problems = [String]()
reloaded.rootNode.enumerateHierarchy { node, _ in
    node.geometry?.materials.forEach { material in
        if material.lightingModel != .constant { problems.append("\(node.name ?? "-"): lightingModel=\(material.lightingModel.rawValue)") }
        guard let cg = decodedTexture(material.diffuse.contents) else {
            problems.append("\(node.name ?? "-"): 디퓨즈 디코드 불가(\(type(of: material.diffuse.contents as Any)))"); return
        }
        if max(cg.width, cg.height) > Int(maxDimension) { problems.append("\(node.name ?? "-"): 텍스처 \(cg.width)x\(cg.height) > \(Int(maxDimension))") }
    }
}
guard problems.isEmpty else { fail("재로드 검증 실패:\n  " + problems.joined(separator: "\n  ")) }
print("[verify] reload \(String(format: "%.1f", reloadMs))ms · 지문 동일 · 재질 .constant · 텍스처 ≤\(Int(maxDimension)) ✓")
print("[summary] usdz(load+bake) \(String(format: "%.1f", loadMs + bakeMs))ms → scn(load) \(String(format: "%.1f", reloadMs))ms, 산출물 \(bytes) bytes")
