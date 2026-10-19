import Foundation
import ImageIO
import SwiftUI

// 0.3.54 캡슐 뽑기 기계 — 맥 창 · 폰 전체 화면이 같은 뷰(`GachaMachineView`)를 띄운다.
// 이 파일은 호스트가 만지는 값들이다: 결과 · 실패 · 햅틱 · 그림 · 문구.
//
// ⚠️ 코어 스토어 결과(`GachaPullResult` · Gacha.swift)와 이름을 나눈다 — 기계 쪽은 전부 `GachaReveal…` / `GachaMachine…`.
// 스토어 결과를 연출 값으로 옮기는 길은 `GachaRevealOutcome(result:name:shardsBefore:)` 하나다.

// MARK: - 결과(서버가 정하고, 기계는 연출만 한다)

package enum GachaRevealKind: String, Sendable, Equatable {
    /// 처음 만난 캐릭터.
    case new
    /// 이미 있는 캐릭터 → 조각.
    case duplicate
    /// 황금 아잉이(처음이든 중복이든 — 중복이면 `shardsGained` 가 0 보다 크다).
    case gold
    /// 무지개 아잉이(v0.3.59 — 황금과 같은 희귀 연출, 빛깔만 무지개. 처음이든 중복이든).
    case rainbow

    /// 희귀 공개(어두운 무대 · 모으기 · 반짝 제목 — 황금 · 무지개)인가.
    package var isRare: Bool { self == .gold || self == .rainbow }
}

/// 기계가 보여 줄 결과 하나. 값은 전부 호스트가 서버 응답에서 옮겨 준다 — 기계는 숫자를 지어내지 않는다.
package struct GachaRevealOutcome: Sendable, Equatable {
    package var characterID: String
    /// 화면 이름("여우"). 호스트가 카탈로그에서 푼다.
    package var name: String
    package var kind: GachaRevealKind
    /// 뽑은 **뒤** 조각 수. 중복이면 "조각 N" 칩이 `shardCount - shardsGained` 에서 이 값으로 올라간다.
    package var shardCount: Int
    /// 이번에 얻은 조각(중복 = 보통 1, 처음 = 0).
    package var shardsGained: Int

    package init(characterID: String, name: String, kind: GachaRevealKind, shardCount: Int = 0, shardsGained: Int? = nil) {
        self.characterID = characterID
        self.name = name
        self.kind = kind
        self.shardCount = max(0, shardCount)
        self.shardsGained = max(0, shardsGained ?? (kind == .duplicate ? 1 : 0))
    }

    /// 스토어 결과(`GachaPullResult`)에서. `shardsBefore` 는 뽑기 **전** 화면의 조각 수 — 서버가 뒤 조각 수를 안 줬을 때만 쓴다.
    package init(result: GachaPullResult, name: String, shardsBefore: Int) {
        let kind: GachaRevealKind
        switch result.kind {
        case .gold: kind = .gold
        case .rainbow: kind = .rainbow
        case .newCharacter: kind = .new
        case .duplicate: kind = .duplicate
        }
        let gained = result.isDuplicate ? max(0, result.shardsGained) : 0
        self.init(characterID: result.characterID, name: name, kind: kind,
                  shardCount: result.shards ?? (max(0, shardsBefore) + gained), shardsGained: gained)
    }

    /// 칩이 연출 전에 보여 줄 조각 수.
    package var shardCountBefore: Int { max(0, shardCount - shardsGained) }
    /// 황금인데 이미 있던 것(조각만 받았다).
    package var isGoldDuplicate: Bool { kind == .gold && shardsGained > 0 }
    /// 희귀(황금 · 무지개)인데 이미 있던 것(조각만 받았다).
    package var isRareDuplicate: Bool { kind.isRare && shardsGained > 0 }
}

/// `pull` 이 던지는 실패. `message` 가 기계 아래 한 줄로 2.4초 뜬다(짧게).
/// 이 타입이 아닌 에러는 `GachaMachineText.pullFailed` 로 말한다.
package struct GachaRevealFailure: Error, Equatable, Sendable {
    package var message: String
    package init(message: String) { self.message = message }
}

// MARK: - 햅틱(플랫폼 몫은 프로토콜 뒤 — 맥은 아무것도 안 한다)

package enum GachaMachineHapticEvent: Equatable, Sendable {
    /// 손잡이 45° 톱니.
    case ratchet
    /// 루비 부족 · 막힘 · 실패.
    case refuse
    /// 한 바퀴 완료 · 기계 쿵.
    case commit
    /// 기다리는 동안 덜컹.
    case rumble
    /// 캡슐이 배출구에 떨어짐.
    case land
    /// 캡슐 톡톡 1...3.
    case tap(Int)
    /// 평범한 캡슐이 황금(무지개)으로 바뀜(반전 연출). 무지개도 같은 박자다 — 폰 햅틱 switch 가 이 어휘를 다 안다.
    case goldFlip
    /// 캡슐 터짐.
    case reveal
    /// 황금(무지개) 터짐.
    case goldReveal
    /// 조각이 칩에 들어감.
    case shard
}

@MainActor
package protocol GachaMachineHaptics {
    func play(_ event: GachaMachineHapticEvent)
}

package struct GachaMachineNoHaptics: GachaMachineHaptics {
    package init() {}
    package func play(_ event: GachaMachineHapticEvent) {}
}

// MARK: - 그림(없으면 벡터로 그린다)

/// 기계·캡슐 래스터 레이어. 하나라도 nil 이면 그 부분은 벡터 도형으로 그린다.
/// 유리 돔은 늘 벡터다(생성 그림은 유리 투명도를 못 살려 뒤 캡슐이 안 비쳤다).
package struct GachaMachineArt {
    /// 몸통(유리 돔·손잡이 제외, 배출구·덮개 포함).
    package var body: Image?
    /// 손잡이(정면, 중심 기준으로 돌린다).
    package var knob: Image?
    /// 흰 캡슐 한 알(위·아래 반쪽을 뷰가 잘라서 물들인다).
    package var capsule: Image?
    /// 황금 캡슐 한 알.
    package var goldCapsule: Image?
    /// 돔 뚜껑.
    package var cap: Image?
    /// 미리 구운 캡슐 그림 캐시의 열쇠(같은 열쇠면 창을 다시 열어도 다시 굽지 않는다).
    package var cacheKey: String

    package init(body: Image? = nil, knob: Image? = nil, capsule: Image? = nil, goldCapsule: Image? = nil, cap: Image? = nil,
                 cacheKey: String = "custom") {
        self.body = body
        self.knob = knob
        self.capsule = capsule
        self.goldCapsule = goldCapsule
        self.cap = cap
        self.cacheKey = cacheKey
    }

    package static var vector: GachaMachineArt { GachaMachineArt(cacheKey: "vector") }

    /// 다섯 장 다 있는가(배포본은 참이어야 한다 — 벡터는 그림이 빠졌을 때의 안전망일 뿐이다).
    package var isComplete: Bool { body != nil && knob != nil && capsule != nil && goldCapsule != nil && cap != nil }

    /// `check_CheckCore.bundle/GachaMachine/*.png`. 한 번 읽어 둔다. 못 찾으면 그 칸만 nil(벡터).
    @MainActor package static var bundled: GachaMachineArt { GachaMachineArtBundle.art }
}

/// 번들 그림 읽기. `Bundle.module` 은 못 찾으면 `fatalError` 라 쓰지 않는다 — 제공자 마크와 같은 탐색기
/// (`AIProviderArtwork.bundle`, 같은 `check_CheckCore.bundle`)를 쓴다.
package enum GachaMachineArtBundle {
    /// `.copy("Resources/GachaMachine")` 라 번들 안에 이 폴더째 들어간다.
    package static let folderName = "GachaMachine"
    /// 번들에 있어야 하는 다섯 장(확장자 뺀 이름).
    package static let resourceNames = ["gacha_body", "gacha_knob", "gacha_capsule", "gacha_capsule_gold", "gacha_cap"]

    package static func url(_ name: String) -> URL? {
        let bundle = AIProviderArtwork.bundle
        return bundle?.url(forResource: name, withExtension: "png", subdirectory: folderName)
            ?? bundle?.url(forResource: name, withExtension: "png")
    }

    /// 읽으면서 바로 푼다(`kCGImageSourceShouldCacheImmediately`) — 첫 그리기에서 PNG 를 푸느라 프레임이 밀리지 않게.
    package static func decodedImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldCache: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    @MainActor private static var cached: GachaMachineArt?

    @MainActor static var art: GachaMachineArt {
        if let cached { return cached }
        func image(_ name: String) -> Image? {
            guard let url = url(name), let cg = decodedImage(at: url) else { return nil }
            return Image(decorative: cg, scale: 1)
        }
        let art = GachaMachineArt(body: image("gacha_body"), knob: image("gacha_knob"), capsule: image("gacha_capsule"),
                                  goldCapsule: image("gacha_capsule_gold"), cap: image("gacha_cap"), cacheKey: "bundled")
        cached = art
        return art
    }
}

// MARK: - 문구(해요체 · 짧게 · GachaText 와 같은 말투)

package nonisolated enum GachaMachineText {
    static func idleHint() -> String { "손잡이를 돌려서 뽑기 ·" }
    static let shortHead = "루비가 모자라요 ·"
    static func shortTail(cost: Int) -> String { "\(cost)개부터 뽑을 수 있어요" }
    static let waiting = "두근두근"
    static let tapFirst = "톡톡 눌러서 열기"
    static let tapSecond = "조금 더!"
    static let tapLast = "마지막 한 번!"
    static let skip = "건너뛰기"
    static let again = "한 번 더 ·"
    static let againShort = "루비가 모자라요"
    static let againBlocked = "한 번 더"
    static let close = "닫기"
    static let shardPlus = "조각"
    /// 이 타입이 아닌 실패(`GachaRevealFailure` 가 아니다)의 한 줄 — 루비가 깎였는지 모르므로 "그대로"라고 말하지 않는다.
    package static let pullFailed = GachaText.pullFailed

    // 결과(정상 연출 · 동작 줄이기가 **같은 글자**를 쓴다)
    static func badge(_ outcome: GachaRevealOutcome) -> String? {
        switch outcome.kind {
        case .new: return "새 캐릭터!"
        case .duplicate: return "이미 있는 친구예요"
        case .gold, .rainbow: return nil
        }
    }
    /// 희귀 결과의 머리말("황금 아잉이!" · "무지개 아잉이!"). 희귀가 아니면 nil.
    static func rareHeadline(_ kind: GachaRevealKind) -> String? {
        switch kind {
        case .gold: return GachaText.goldHeadline
        case .rainbow: return GachaText.rainbowHeadline
        case .new, .duplicate: return nil
        }
    }
    static func title(_ outcome: GachaRevealOutcome) -> String {
        rareHeadline(outcome.kind) ?? outcome.name
    }
    /// 중복의 둘째 이름("다람쥐 조각 +1").
    static func shardLine(_ outcome: GachaRevealOutcome) -> String { "\(outcome.name) 조각" }
    static func shardGain(_ outcome: GachaRevealOutcome) -> String { "+\(max(1, outcome.shardsGained))" }
    /// 희귀(황금 · 무지개) 결과의 부제 — 둘이 같은 말이다.
    static func goldSubtitle(_ outcome: GachaRevealOutcome) -> String {
        outcome.isRareDuplicate ? "이미 있는 친구예요 · 조각 +\(outcome.shardsGained)" : "아주 드문 친구를 만났어요"
    }
    static func chipGain(_ outcome: GachaRevealOutcome) -> String { "+\(max(1, outcome.shardsGained)) 조각" }

    /// 공개가 끝났을 때 읽어 줄 한 문장(보이스오버 · 결과 요소의 이름). 정상 연출과 동작 줄이기가 같다.
    package static func announcement(_ outcome: GachaRevealOutcome) -> String {
        switch outcome.kind {
        case .new: return "새 캐릭터! \(outcome.name)"
        case .duplicate: return "이미 있는 친구예요. \(outcome.name) 조각 \(shardGain(outcome))"
        case .gold, .rainbow: return "\(title(outcome)) \(goldSubtitle(outcome))"
        }
    }

    static func handleLabel() -> String { "뽑기 손잡이" }
    static func handleHint(cost: Int) -> String { "두 번 탭하면 루비 \(cost)개로 한 번 뽑아요" }
    static func rubyLabel(_ balance: Int) -> String { "루비 \(balance)개" }
    static func shardLabel(_ count: Int) -> String { "조각 \(count)개" }
    static let openCapsule = "캡슐 열기"
    static func againLabel(cost: Int) -> String { "한 번 더 뽑기 · 루비 \(cost)개" }
}
