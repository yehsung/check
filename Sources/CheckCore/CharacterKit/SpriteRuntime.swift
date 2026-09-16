import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import os

/// 스프라이트 캐릭터 한 마리의 **살아 있는 상태** — 지금 어느 상태(frontIdle/sideIdle/sideWalk)의 몇 번 프레임을,
/// 뒤집어서 그리고 있는가. 코어(`SpriteFramePlayer`·`SpriteAlphaMask`·`SpriteCharacterNode`)는 전부 순수하거나
/// 무상태라, 그 셋을 한 캐릭터 분량으로 묶어 들고 있는 자리가 하나 필요하다. 여기가 그 자리다.
///
/// **왜 홀더가 따로 있어야 하나.** 상태를 들고 있지 않으면 호출부마다 "지금 프레임이 몇 번인지"를 각자 기억하게 되고
/// (오버레이의 방향 전환 · 걷기 틱 · 클릭 알파 판정 · 미니게임 옆모습이 전부 같은 값을 봐야 한다), 그 순간
/// **클릭 판정이 화면에 그려진 것과 다른 프레임의 알파를 보는** 결함이 열린다. 특히 `isOpaque(planeUV:)` 는
/// `SpriteCharacterNode.atlasUV` 를 반드시 거쳐야 하는데(hitTest 가 주는 UV 는 `contentsTransform` 적용 **전**이다 —
/// 1차 웨이브 실측), 그 변환에 필요한 frame·mirrored 가 바로 여기 있는 값이다. 통로를 하나로 묶어 두면 두 식이 갈릴 수 없다.
///
/// **폴백은 여기 한 곳에서 접는다.** `sideIdle`/`sideWalk` 가 매니페스트에 없는 캐릭터(정면만 있는 캐릭터)는
/// 상태 요청을 `frontIdle` 로 접는다. 호출부마다 `?? frontIdle` 을 쓰면 언젠가 한 곳이 빠져 "옆을 보라고 했는데
/// 아무 프레임도 없다"가 되고, 그건 화면에서 캐릭터가 **사라지는** 것으로만 드러난다.
///
/// 스레드: SceneKit 노드를 만지므로 `@MainActor`.
@MainActor
package final class SpriteRuntime {
    /// 이 런타임이 대변하는 캐릭터. `kind == .sprite` 가 보장된다(아니면 init 이 nil).
    package let manifest: CharacterManifest
    /// 아틀라스 이미지. 재질 디퓨즈에 그대로 들어가는 바로 그 객체다.
    package let atlas: CGImage
    /// 아틀라스 전체의 1비트 불투명 마스크(클릭이 "몸"에 맞았는지 판정).
    package let mask: SpriteAlphaMask

    /// 매니페스트의 아틀라스 스펙(크기·상태). `manifest.atlas!` 를 매번 풀지 않으려고 잡아 둔다.
    private let spec: CharacterManifest.Atlas
    /// 상태별 재생 시계. 상태 하나당 한 번만 만든다(프레임 끝 시각 누적은 생성 비용이 전부다).
    private let players: [String: SpriteFramePlayer]

    /// 지금 재생 중인 상태 키. **요청값이 아니라 폴백까지 접힌 결과값**이다 —
    /// `sideWalk` 를 요청해도 그 상태가 매니페스트에 없으면 여기엔 `frontIdle` 이 들어간다.
    /// (요청값을 담아 두면 `currentFrame` 이 가리키는 상태와 이 값이 갈려, 로그·테스트가 거짓말을 한다.)
    package private(set) var stateKey: String
    /// 수평 미러 여부. 왼쪽 옆모습은 오른쪽 프레임을 뒤집어 만든다(추가 에셋 0 — DECISIONS).
    package private(set) var mirrored: Bool
    /// 현재 상태 안에서의 프레임 번호.
    package private(set) var frameIndex: Int

    /// 현재 상태가 시작된 시각(호출부가 주는 시계). `tick` 은 이 값으로부터의 경과로 프레임을 뽑는다.
    package private(set) var stateStartedAt: TimeInterval

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    // MARK: - 생성

    /// 매니페스트 + 아틀라스 파일 URL. 실패하면 nil — **호출부는 아잉으로 폴백한다.**
    ///
    /// 실패 갈래를 모두 nil 로 접는 이유: 여기서 throw 해 봐야 호출부가 할 수 있는 일은 "아잉으로 내려간다" 하나뿐이고,
    /// 갈래별 처리를 요구하면 그 분기가 호출부마다 복제된다. 대신 어느 갈래로 떨어졌는지는 로그로 남긴다.
    package convenience init?(manifest: CharacterManifest, atlasURL: URL) {
        guard let image = Self.decodeImage(at: atlasURL) else {
            Self.logger.error("sprite atlas unreadable id=\(manifest.id, privacy: .public)")
            return nil
        }
        self.init(manifest: manifest, atlas: image)
    }

    /// 이미 디코드된 아틀라스로 만든다(씬 교체·테스트가 같은 CGImage 를 재사용한다).
    package init?(manifest: CharacterManifest, atlas: CGImage) {
        guard manifest.kind == .sprite, let spec = manifest.atlas else { return nil }
        // 매니페스트가 말하는 크기와 실제 PNG 가 다르면 모든 프레임이 어긋난 채 조용히 돈다.
        // `SpriteCharacterNode.make` 와 **같은 판정**이라 노드는 서고 런타임만 없는 반쪽 상태가 생기지 않는다.
        guard spec.width == atlas.width, spec.height == atlas.height else {
            Self.logger.error("sprite atlas size mismatch id=\(manifest.id, privacy: .public) manifest=\(spec.width)x\(spec.height) image=\(atlas.width)x\(atlas.height)")
            return nil
        }
        guard let mask = SpriteAlphaMask(atlas: atlas, states: spec.states) else {
            Self.logger.error("sprite alpha mask bake failed id=\(manifest.id, privacy: .public)")
            return nil
        }
        // frontIdle 은 매니페스트 검증이 이미 강제한다(없으면 디코드가 throw). 그래도 메모리 픽스처로 만든
        // 매니페스트가 들어올 수 있으므로 여기서 한 번 더 막는다 — 없으면 그릴 프레임이 하나도 없다.
        guard spec.states[CharacterManifest.StateKey.frontIdle]?.frames.isEmpty == false else { return nil }

        self.manifest = manifest
        self.atlas = atlas
        self.mask = mask
        self.spec = spec
        self.players = spec.states.mapValues { SpriteFramePlayer(state: $0) }
        self.stateKey = CharacterManifest.StateKey.frontIdle
        self.mirrored = false
        self.frameIndex = 0
        self.stateStartedAt = 0
    }

    // MARK: - 읽기

    /// 지금 그려야 할 셀. 상태·프레임이 어떤 이유로든 범위를 벗어나면 frontIdle 첫 프레임으로 접는다
    /// (nil 을 돌려주면 호출부가 "안 그린다"를 택하게 되고, 그건 캐릭터가 사라지는 것이다).
    package var currentFrame: CharacterManifest.Rect {
        guard let state = spec.states[stateKey], state.frames.isEmpty == false else {
            return spec.states[CharacterManifest.StateKey.frontIdle]?.frames.first
                ?? CharacterManifest.Rect(x: 0, y: 0, w: spec.width, h: spec.height)
        }
        return state.frames[min(max(frameIndex, 0), state.frames.count - 1)]
    }

    /// 아틀라스 픽셀 크기. `SpriteCharacterNode` 의 변환 함수들이 전부 이 값을 받는다.
    package var atlasSize: CGSize { CGSize(width: spec.width, height: spec.height) }

    /// 상태 하나의 한 바퀴 길이(초). 없는 상태면 폴백된 상태의 길이.
    package func totalDuration(of key: String) -> TimeInterval {
        players[resolve(key)]?.totalDuration ?? 0
    }

    /// 요청한 상태가 매니페스트에 **실제로** 있는가(폴백 없이). 2-B 가 "이 캐릭터는 걷기를 가졌나"를 물을 자리.
    package func hasState(_ key: String) -> Bool {
        spec.states[key]?.frames.isEmpty == false
    }

    // MARK: - 상태 전환

    /// 상태 전환. **같은 (상태, 미러) 재호출은 no-op** — 프레임을 0 으로 되돌리지 않는다.
    ///
    /// 이 no-op 가드가 계약인 이유: 드래그 중 `setDragFacing` 은 **매 마우스 이벤트마다** 같은 방향을 다시 준다.
    /// 가드가 없으면 걷기가 매 프레임 0번으로 리셋돼 **영원히 첫 프레임**에 머문다(= 걷지 않는 것으로 보인다).
    /// 비교는 **폴백이 접힌 뒤**의 키로 한다 — sideIdle 도 sideWalk 도 frontIdle 로 접히는 캐릭터라면
    /// 둘 사이를 오가도 실제로 바뀌는 것이 없으므로 리셋할 이유도 없다.
    package func setState(_ key: String, mirrored: Bool, now: TimeInterval) {
        let resolved = resolve(key)
        guard resolved != stateKey || mirrored != self.mirrored else { return }
        stateKey = resolved
        self.mirrored = mirrored
        stateStartedAt = now
        frameIndex = players[resolved]?.frameIndex(elapsed: 0) ?? 0
    }

    /// 프레임 진행. **바뀌었으면 true** — 호출부는 그때만 노드를 갱신한다(매 틱 재질을 건드리면
    /// 유휴 6fps 에서도 쓸데없는 GPU 작업이 깔린다).
    @discardableResult
    package func tick(now: TimeInterval) -> Bool {
        guard let player = players[stateKey] else { return false }
        let next = player.frameIndex(elapsed: now - stateStartedAt)
        guard next != frameIndex else { return false }
        frameIndex = next
        return true
    }

    // MARK: - 알파 · 노드

    /// 평면 UV → 알파. **`atlasUV` 를 반드시 거친다.**
    ///
    /// hitTest 의 `textureCoordinates(withMappingChannel: 0)` 은 재질 변환이 걸리기 **전**의 지오메트리 UV 를 준다
    /// (1차 웨이브 실측). 그걸 마스크에 그대로 먹이면 아틀라스 **전체** 기준으로 조회해 엉뚱한 프레임의 알파를 본다 —
    /// 걷는 동안에만 클릭이 빗나가는, 재현하기 지독한 결함이다.
    package func isOpaque(planeUV: CGPoint) -> Bool {
        let uv = SpriteCharacterNode.atlasUV(
            planeUV: planeUV, frame: currentFrame, mirrored: mirrored, atlasSize: atlasSize
        )
        return mask.isOpaque(u: uv.x, v: uv.y)
    }

    /// 노드에 현재 프레임·미러를 반영한다. 평면 크기는 건드리지 않는다(프레임마다 리사이즈하면
    /// 걷는 동안 캐릭터가 커졌다 작아진다 — 1차 웨이브 실측).
    package func applyToNode(_ node: SCNNode) {
        SpriteCharacterNode.apply(frame: currentFrame, mirrored: mirrored, to: node, atlasSize: atlasSize)
    }

    /// 이 런타임의 캐릭터 평면 노드를 새로 만든다(현재 프레임까지 반영해서).
    package func makeNode() -> SCNNode? {
        guard let node = SpriteCharacterNode.make(manifest: manifest, atlas: atlas) else { return nil }
        applyToNode(node)
        return node
    }

    // MARK: - 내부

    /// 요청 상태를 **실제로 존재하는** 상태로 접는다. 폴백은 이 함수 하나뿐이다.
    private func resolve(_ key: String) -> String {
        if spec.states[key]?.frames.isEmpty == false { return key }
        return CharacterManifest.StateKey.frontIdle
    }

    /// 아틀라스 PNG 를 CGImage 로. `NSImage` 를 거치지 않는 이유: 표현(rep) 선택이 화면 배율에 따라 달라져
    /// 매니페스트가 말한 픽셀 크기와 다른 것을 돌려줄 수 있다. ImageIO 로 **파일이 가진 픽셀 그대로** 읽는다.
    package nonisolated static func decodeImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
