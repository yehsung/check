import Foundation

/// 캐릭터 한 종을 기술하는 매니페스트 — 번들 `Characters/<id>/manifest.json` 하나가 이 구조다.
///
/// 왜 데이터인가: 아잉(3D)은 `aing.scn` 과 코드에 박혀 있지만, 2D 스프라이트 캐릭터는 **에셋 파이프라인이 굽는
/// 산출물**이라 아틀라스 좌표·재생 순서·프레임 길이가 전부 바깥에서 온다. 이 값이 틀리면 화면에는 "캐릭터가 안
/// 보인다 / 걷다가 튄다" 로만 드러나고 어디가 틀렸는지 알 길이 없다. 그래서 **디코드 시점에 전부 검증해 throw**
/// 한다(조용히 깨진 캐릭터를 카탈로그에 들이지 않는다 — 카탈로그는 throw 한 캐릭터를 건너뛴다).
///
/// 좌표 규약: `Rect` 은 **픽셀·좌상단 원점**이다. 텍스처 UV 의 v 도 같은 방향(위→아래)이다
/// (scratchpad/planeprobe 실측: `py = uv.y × 높이`, 뒤집지 않는다). 두 규약이 같은 방향이라
/// rect → `contentsTransform` 변환이 부호 장난 없이 그대로 나온다.
struct CharacterManifest: Codable, Equatable, Sendable {
    /// 캐릭터 식별자. 번들 폴더 이름이자 UserDefaults 에 저장되는 선택 값이다.
    /// `[a-z0-9-]{1,32}` 로 좁힌 이유: 이 문자열이 그대로 경로 조각이 되므로 `..`·`/`·공백이 섞이면 안 된다.
    let id: String
    /// 사람이 읽는 이름("아잉"). 설정 화면 목록에 그대로 나간다.
    let displayName: String
    /// 렌더 갈래. 모르는 값은 디코드가 throw 하고 카탈로그가 건너뛴다 —
    /// 나중에 갈래가 늘어도 구버전 앱이 죽는 대신 그 캐릭터 하나만 목록에서 사라진다.
    let kind: Kind
    /// 스프라이트 아틀라스(스프라이트 전용). scene3D 면 반드시 nil.
    let atlas: Atlas?
    /// 메뉴바(18pt)·팝오버(46pt)용 정지 초상 2장(스프라이트 전용). scene3D 면 반드시 nil.
    let portrait: Portrait?

    enum Kind: String, Codable, Sendable {
        /// 아잉처럼 SceneKit 씬 파일을 그대로 쓰는 캐릭터.
        case scene3D
        /// 아틀라스 평면 한 장으로 서는 2D 캐릭터.
        case sprite
    }

    struct Atlas: Codable, Equatable, Sendable {
        /// 같은 폴더 안의 상대 파일명("atlas.png"). 경로 조각(`/`·선행 `.`)은 금지 — 번들 밖을 가리키지 못하게.
        let file: String
        /// 아틀라스 픽셀 크기. **실제 PNG 와 다르면** 프레임이 통째로 어긋나므로 로더가 교차 검증한다
        /// (`SpriteAlphaMask.init` · `SpriteCharacterNode.make`).
        let width: Int
        let height: Int
        /// 상태 이름 → 상태. 키는 `StateKey`(frontIdle / sideIdle / sideWalk). 모르는 키는 조용히 무시된다(전방 호환).
        let states: [String: State]
    }

    struct State: Codable, Equatable, Sendable {
        /// **재생 순서 그대로**. 같은 rect 가 여러 번 와도 된다(여우 걷기 = 0,1,2,1 — 픽스처 실측 결정).
        let frames: [Rect]
        /// 프레임별 노출 시간(밀리초). `frames` 와 길이가 같아야 한다.
        let durationsMs: [Int]
        /// 끝에서 처음으로 돌아가는가. false 면 마지막 프레임에서 멈춘다.
        let loop: Bool

        init(frames: [Rect], durationsMs: [Int], loop: Bool) {
            self.frames = frames
            self.durationsMs = durationsMs
            self.loop = loop
        }
    }

    /// 아틀라스 안의 한 셀. **픽셀·좌상단 원점.**
    struct Rect: Codable, Equatable, Sendable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        init(x: Int, y: Int, w: Int, h: Int) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    struct Portrait: Codable, Equatable, Sendable {
        let neutral: String
        let negative: String

        init(neutral: String, negative: String) {
            self.neutral = neutral
            self.negative = negative
        }
    }

    /// 상태 키 상수. 문자열을 갈래마다 따로 적으면 팩 스크립트와 런타임이 소리 없이 갈린다.
    enum StateKey {
        /// 정면 idle. **평면 크기의 기준**이라 스프라이트에 반드시 있어야 한다.
        static let frontIdle = "frontIdle"
        /// 90° 옆모습 idle(방향만 잡고 멈춰 있을 때).
        static let sideIdle = "sideIdle"
        /// 90° 옆모습 걷기(드래그로 이동 중).
        static let sideWalk = "sideWalk"
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, kind, atlas, portrait
    }

    /// 검증 없는 메모리 생성자(내장 아잉·테스트 픽스처용). 파일에서 오는 값은 반드시 `init(from:)` 을 지나야 한다.
    init(id: String, displayName: String, kind: Kind, atlas: Atlas? = nil, portrait: Portrait? = nil) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.atlas = atlas
        self.portrait = portrait
    }

    /// **검증은 여기서 한 번에 한다.** 디코드 성공이 곧 "이 캐릭터는 화면에 세울 수 있다"는 뜻이어야
    /// 카탈로그·노드·마스크가 각자 방어 코드를 다시 쓰지 않는다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.atlas = try container.decodeIfPresent(Atlas.self, forKey: .atlas)
        self.portrait = try container.decodeIfPresent(Portrait.self, forKey: .portrait)
        try validate()
    }

    /// 매니페스트 불변식. 어기면 throw.
    func validate() throws {
        guard Self.isValidID(id) else { throw CharacterManifestError.invalidID(id) }
        guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CharacterManifestError.emptyDisplayName(id)
        }

        switch kind {
        case .scene3D:
            // 3D 는 씬 파일이 전부다. 아틀라스·초상이 붙어 있으면 그 데이터는 아무도 안 읽는다 = 거짓말이라 거절.
            guard atlas == nil else { throw CharacterManifestError.unexpectedAtlas(id) }
            guard portrait == nil else { throw CharacterManifestError.unexpectedPortrait(id) }
        case .sprite:
            guard let atlas else { throw CharacterManifestError.missingAtlas(id) }
            guard let portrait else { throw CharacterManifestError.missingPortrait(id) }
            try Self.validateAssetFile(atlas.file, id: id)
            try Self.validateAssetFile(portrait.neutral, id: id)
            try Self.validateAssetFile(portrait.negative, id: id)
            guard atlas.width > 0, atlas.height > 0 else {
                throw CharacterManifestError.invalidAtlasSize(id)
            }
            // 평면 크기를 정하는 기준 상태라 없으면 캐릭터를 세울 수 없다.
            guard let front = atlas.states[StateKey.frontIdle], front.frames.isEmpty == false else {
                throw CharacterManifestError.missingRequiredState(id: id, state: StateKey.frontIdle)
            }
            // 상태 순회는 키 정렬 순서로 — 어떤 오류가 먼저 보고될지 결정적이어야 테스트가 흔들리지 않는다
            // (Dictionary 순회 순서는 실행마다 다르다).
            for key in atlas.states.keys.sorted() {
                guard let state = atlas.states[key] else { continue }
                try Self.validate(state: state, key: key, id: id, atlas: atlas)
            }
        }
    }

    private static func validate(state: State, key: String, id: String, atlas: Atlas) throws {
        guard state.frames.isEmpty == false else {
            throw CharacterManifestError.emptyFrames(id: id, state: key)
        }
        guard state.frames.count == state.durationsMs.count else {
            throw CharacterManifestError.frameDurationMismatch(
                id: id, state: key, frames: state.frames.count, durations: state.durationsMs.count
            )
        }
        for (index, ms) in state.durationsMs.enumerated() where ms < 0 {
            throw CharacterManifestError.negativeDuration(id: id, state: key, index: index)
        }
        // 프레임이 둘 이상인데 합이 0ms 면 애니메이션이 **영원히 첫 프레임에 멈춘다**. 화면은 멀쩡해 보이고
        // 아무 것도 안 빨개지는 전형적인 "조용한 오류"라 여기서 잡는다(1프레임 정지 상태는 정상이므로 허용).
        if state.frames.count > 1, state.durationsMs.reduce(0, +) <= 0 {
            throw CharacterManifestError.zeroTotalDuration(id: id, state: key)
        }
        for (index, rect) in state.frames.enumerated() {
            guard rect.w > 0, rect.h > 0, rect.x >= 0, rect.y >= 0,
                  rect.x + rect.w <= atlas.width, rect.y + rect.h <= atlas.height else {
                throw CharacterManifestError.rectOutsideAtlas(id: id, state: key, index: index)
            }
        }
    }

    /// id 문자 집합: 소문자·숫자·하이픈 1~32자.
    static func isValidID(_ id: String) -> Bool {
        guard (1...32).contains(id.count) else { return false }
        return id.allSatisfy { character in
            guard let ascii = character.asciiValue else { return false }
            return (ascii >= 97 && ascii <= 122) || (ascii >= 48 && ascii <= 57) || ascii == 45
        }
    }

    /// 에셋 파일명: 비어 있지 않고 경로 구분자·선행 점이 없어야 한다(번들 폴더 밖을 가리키지 못하게).
    private static func validateAssetFile(_ name: String, id: String) throws {
        guard name.isEmpty == false,
              name.contains("/") == false,
              name.contains("\\") == false,
              name.hasPrefix(".") == false else {
            throw CharacterManifestError.invalidAssetFileName(id: id, file: name)
        }
    }
}

/// 매니페스트 검증 실패 이유. 카탈로그가 로그로 남기므로 **어느 캐릭터의 어느 상태인지**까지 담는다.
enum CharacterManifestError: Error, Equatable, CustomStringConvertible {
    case invalidID(String)
    case emptyDisplayName(String)
    case unexpectedAtlas(String)
    case unexpectedPortrait(String)
    case missingAtlas(String)
    case missingPortrait(String)
    case invalidAtlasSize(String)
    case invalidAssetFileName(id: String, file: String)
    case missingRequiredState(id: String, state: String)
    case emptyFrames(id: String, state: String)
    case frameDurationMismatch(id: String, state: String, frames: Int, durations: Int)
    case negativeDuration(id: String, state: String, index: Int)
    case zeroTotalDuration(id: String, state: String)
    case rectOutsideAtlas(id: String, state: String, index: Int)

    var description: String {
        switch self {
        case .invalidID(let id): return "id 형식이 아니다: '\(id)'"
        case .emptyDisplayName(let id): return "[\(id)] displayName 이 비었다"
        case .unexpectedAtlas(let id): return "[\(id)] scene3D 인데 atlas 가 있다"
        case .unexpectedPortrait(let id): return "[\(id)] scene3D 인데 portrait 가 있다"
        case .missingAtlas(let id): return "[\(id)] sprite 인데 atlas 가 없다"
        case .missingPortrait(let id): return "[\(id)] sprite 인데 portrait 가 없다"
        case .invalidAtlasSize(let id): return "[\(id)] atlas 크기가 0 이하다"
        case .invalidAssetFileName(let id, let file): return "[\(id)] 에셋 파일명이 잘못됐다: '\(file)'"
        case .missingRequiredState(let id, let state): return "[\(id)] 필수 상태 '\(state)' 가 없다"
        case .emptyFrames(let id, let state): return "[\(id)/\(state)] frames 가 비었다"
        case .frameDurationMismatch(let id, let state, let frames, let durations):
            return "[\(id)/\(state)] frames(\(frames)) 와 durationsMs(\(durations)) 길이가 다르다"
        case .negativeDuration(let id, let state, let index): return "[\(id)/\(state)] durationsMs[\(index)] 가 음수다"
        case .zeroTotalDuration(let id, let state): return "[\(id)/\(state)] 프레임이 여럿인데 총 길이가 0ms 다"
        case .rectOutsideAtlas(let id, let state, let index): return "[\(id)/\(state)] frames[\(index)] 가 아틀라스 밖이다"
        }
    }
}
