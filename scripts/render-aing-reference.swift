// 아잉이 레퍼런스 한 장 — 앱과 같은 구도로 정면을 크게 굽는다(얼굴·소품은 손대지 않는다).
//
// 이모티콘을 구울 때 이미지 모델에 **"이게 아잉이다"** 하고 보여 줄 재료다. 카메라 숫자는
// `CheckCharacter3DScene.addFramingCamera` 와 같다 — 레퍼런스가 앱 화면과 다른 구도면 모델이
// 다른 각도의 캐릭터를 그려 놓고, 그게 말풍선에서 "닮았는데 다른 애"로 보인다.
// 조명은 켜지 않는다(`applyUnlitMaterials` 와 같은 한 줄) — 기본 조명에서는 텍스처가 허옇게 떠
// 마스코트 보라가 사라진다.
//
// 사용법: swift scripts/render-aing-reference.swift Sources/check/Resources/aing.scn <출력.png> [한변=1024]
import AppKit
import SceneKit
import Metal

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: render-aing-ref.swift <aing.scn> <out.png> [side]\n", stderr); exit(2) }
let modelURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let side = CGFloat(args.count > 3 ? Double(args[3]) ?? 1024 : 1024)

guard let device = MTLCreateSystemDefaultDevice() else { fputs("Metal 없음\n", stderr); exit(1) }
let scene = try SCNScene(url: modelURL, options: nil)
scene.background.contents = nil
scene.rootNode.enumerateHierarchy { node, _ in
    node.geometry?.materials.forEach { $0.lightingModel = .constant }
}
guard let character = scene.rootNode.childNodes.first else { fputs("캐릭터 노드 없음\n", stderr); exit(1) }
let wrapper = SCNNode(), facing = SCNNode()
character.removeFromParentNode()
facing.addChildNode(character)
wrapper.addChildNode(facing)
scene.rootNode.addChildNode(wrapper)

let (minB, maxB) = wrapper.boundingBox
let bodyCenter = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
let modelExtent = CGFloat(max(maxB.x - minB.x, maxB.y - minB.y))
let fov: CGFloat = 40
let cameraNode = SCNNode()
let camera = SCNCamera()
camera.fieldOfView = fov
camera.projectionDirection = .vertical
camera.zNear = 0.01
camera.zFar = 1_000
cameraNode.camera = camera
let distance = modelExtent / (2 * tan(fov / 2 * .pi / 180)) * 1.4
cameraNode.position = SCNVector3(bodyCenter.x, bodyCenter.y + modelExtent * 0.55, CGFloat(maxB.z) + distance)
cameraNode.look(at: SCNVector3(bodyCenter.x, bodyCenter.y - modelExtent * 0.16, bodyCenter.z))
scene.rootNode.addChildNode(cameraNode)

let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false
// 넉넉히 굽고 **캐릭터에 바짝 잘라** 낸다. 여백이 넓은 레퍼런스를 넣으면 모델이 디테일을 덜 보고
// 제 식대로 다시 디자인한다(실측: 여백 넓은 판은 귀 위치·몸통 비율이 눈에 띄게 어긋났다).
let image = renderer.snapshot(atTime: 0, with: CGSize(width: side * 2, height: side * 2), antialiasingMode: .multisampling4X)
guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fputs("렌더 실패\n", stderr); exit(1) }

let w = cg.width, h = cg.height
guard let probe = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let base = probe.data else { fputs("비트맵 실패\n", stderr); exit(1) }
probe.clear(CGRect(x: 0, y: 0, width: w, height: h))
probe.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = base.assumingMemoryBound(to: UInt8.self)
var minX = w, maxX = -1, minY = h, maxY = -1
for y in 0..<h {
    for x in 0..<w where px[y * probe.bytesPerRow + x * 4 + 3] > 8 {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX >= minX else { fputs("빈 렌더\n", stderr); exit(1) }
let cw = maxX - minX + 1, ch = maxY - minY + 1
let pad = Int(Double(max(cw, ch)) * 0.10)
let box = max(cw, ch) + pad * 2
guard let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: cw, height: ch)),
      let outCtx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8,
                             bytesPerRow: Int(side) * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("자르기 실패\n", stderr); exit(1)
}
outCtx.clear(CGRect(x: 0, y: 0, width: side, height: side))
outCtx.interpolationQuality = .high
let k = Double(side) / Double(box)
outCtx.draw(cropped, in: CGRect(x: (Double(side) - Double(cw) * k) / 2, y: (Double(side) - Double(ch) * k) / 2,
                                width: Double(cw) * k, height: Double(ch) * k))
guard let out = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("저장 준비 실패\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { fputs("저장 실패\n", stderr); exit(1) }
print("썼다: \(outURL.path) \(Int(side))x\(Int(side)) (캐릭터 \(cw)x\(ch) 를 바짝 잘라 담음)")
