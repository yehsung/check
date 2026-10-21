import Foundation
import ImageIO
import SwiftUI

// MARK: - 아잉이 이모티콘 (v0.3.62) — 서버를 **하나도** 안 고치는 전선 규약
//
// 실사용 요청(0.3.61): "메시지에 아잉이 이모티콘 만들어주세요".
// 사용자 결정 둘: **말풍선 한 칸을 통째로 차지하는 큰 그림** · **아잉이 표정 여섯 종**.
// (처음엔 여덟이었다. `굿`·`박수` 는 아잉이에게 **없는 손**을 평면 소품으로 그려야 해서 3D 몸과 질감이 갈렸고,
//  2026-10-21 사용자가 그 두 장을 빼기로 했다 — 되살리려면 그림부터 다시 굽고 여기에 case 를 더하면 된다.)
//
// ## 왜 평범한 텍스트 메시지인가 — 이 설계의 핵심
// 이모티콘은 새 전선(새 컬럼·새 RPC·새 enum)을 쓰지 않는다. `send_message` 가 받는 **글자 그대로** 나가고,
// 본문이 아래 토큰과 **통째로 같을 때만** 받는 쪽이 그림으로 그린다. 그래서:
//   · **마이그레이션도 `db push` 도 필요 없다.** 서버 `send_message` 는 글자만 받고, `not_text` 난간은
//     방향 제어 문자·가운데 ZWSP·한글 채움만 막는다 — 대괄호와 한글은 그대로 통과한다.
//   · **구버전을 끊을 위험이 0이다.** 옛 맥 앱과 지금 폰 앱은 `[아잉:기쁨]` 이라는 **읽을 수 있는 글자**로 본다.
//     깨진 네모도, 빈 말풍선도 아니다. (쓰기 경로를 거두면 구버전이 끊긴다는 이 저장소의 사고 —
//     0.3.17 점수표 revoke — 와 정확히 반대쪽 선택이다.)
//   · **열거값 확장의 능력 협상이 필요 없다.** 모르는 값을 조용히 접는 길이 애초에 없다(모르면 글자다).
//
// ## 판정은 '통째로 같을 때만'이다
// `MessageBody.sanitized`(NFC + 앞뒤 trim)를 거친 문자열이 토큰과 **정확히 같을 때만** 참이다.
//   · 앞뒤에 글자가 붙으면 그냥 텍스트다. **부분 치환을 하지 마라** — 그건 "글 속 작은 아이콘"이고
//     사용자가 고른 쪽("말풍선 한 칸을 통째로")이 아니다.
//   · 확성기는 서버가 본문 앞에 `📢 ` 를 붙이므로 토큰과 같지 않다 → 그림이 되지 않는다(**의도대로다**).
//   · NFC 정규화를 거치는 이유: macOS 입력기·파인더에서 온 한글은 자모 분해(NFD)로 들어와 바이트가 다르다
//     (`MessageBody.sanitized` 주석의 실측). 거치지 않으면 "보낸 사람 화면에서는 그림인데 받은 화면에서는
//     글자"가 된다.
//
// ## 토큰 글자와 화면 글자를 **따로** 둔다
// `token`(전선)과 `label`(화면)을 한 switch 에서 파생시키지 않는다. 파생시키면 화면 문구를 다듬는 커밋이
// **전선 규약을 조용히 바꾼다** — 그 순간 먼저 올린 사람과 나중 올린 사람이 서로의 그림을 글자로 본다.
// 둘을 갈라 두고, 여섯 토큰 문자열은 테스트가 **글자 그대로** 못 박는다(V0362AingStickerTests).
//
// ## 그림은 왜 `CheckCore` 리소스인가
// 맥 앱·폰 앱·위젯이 **셋 다 링크하는 모듈은 여기뿐이다**(`AIProviderLogo.swift` 머리말의 같은 근거).
// `Package.swift` 의 `.copy("Resources/Stickers")` 가 `check_CheckCore.bundle/Stickers/` 로 실어 주고,
// 번들을 찾는 일은 제공자 마크의 탐색기(`AIProviderArtwork.bundle`)를 **그대로 재사용한다**.
// `Bundle.module` 은 쓰지 않는다 — 못 찾으면 `fatalError` 라, 맥 패키징이 번들 복사 한 줄을 빠뜨린
// 배포본에서 메시지를 여는 순간 앱째로 죽는다.

/// 아잉이 이모티콘 여섯 종. **case 순서가 고르는 그리드의 순서다**(사용자가 보는 차례 = 이 차례).
///
/// `rawValue` 는 그림 파일 이름의 꼬리이고(`sticker-<rawValue>.png`) 전선에는 나가지 않는다 —
/// 전선에 나가는 것은 `token` 뿐이다.
package enum AingSticker: String, CaseIterable, Sendable {
    case joy
    case heart
    case sad
    case angry
    case sleepy
    case surprised

    /// 토큰의 머리. **"이모티콘인 것 같다"를 싸게 묻는 자리**다(목록 미리보기·구버전 분기가 여섯 개를 다 비교하지 않게).
    /// 이것만으로 참을 내지 마라 — `[아잉:없는것]` 도 이 머리를 갖는다. 판정은 언제나 `parse` 다.
    package static let tokenPrefix = "[아잉:"

    /// 전선에 나가는 본문. **이 문자열은 계약이다** — 한 글자라도 바꾸면 그 순간부터 같은 그림을
    /// 보내는 두 버전이 서로를 글자로 본다. 길이는 7 코드포인트라 200자 상한과 무관하다.
    ///
    /// `label` 로 조립하지 않는 이유는 머리말("토큰 글자와 화면 글자를 따로 둔다")에 있다.
    package var token: String {
        switch self {
        case .joy: return "[아잉:기쁨]"
        case .heart: return "[아잉:하트]"
        case .sad: return "[아잉:슬픔]"
        case .angry: return "[아잉:화남]"
        case .sleepy: return "[아잉:졸림]"
        case .surprised: return "[아잉:놀람]"
        }
    }

    /// 화면에 쓰는 한국어 이름. 그리드 칸의 툴팁·보이스오버와 목록 미리보기가 이 말을 쓴다.
    /// **전선이 아니다** — 여기를 다듬어도 주고받는 글자는 그대로다.
    package var label: String {
        switch self {
        case .joy: return "기쁨"
        case .heart: return "하트"
        case .sad: return "슬픔"
        case .angry: return "화남"
        case .sleepy: return "졸림"
        case .surprised: return "놀람"
        }
    }

    /// 번들 그림 이름(확장자 없음). `Resources/Stickers/sticker-joy.png` 의 `sticker-joy`.
    package var resourceName: String { "sticker-\(rawValue)" }

    /// 본문이 이모티콘 하나인가. **통째로 같을 때만** 참이다(머리말 "판정은 '통째로 같을 때만'이다").
    ///
    /// 머리 검사로 먼저 거르는 것은 값 때문이 아니라 비용 때문이다 — 메시지 목록이 본문마다 이걸 부르고
    /// (틀 높이 추정이 전수로, 말풍선 행이 한 번 더), 그 뒤의 `MessageBody.sanitized` 는 본문 길이만큼의
    /// 사본을 만든다. 이모티콘이 아닌 본문(거의 전부)은 **첫 글자에서** 끝난다.
    ///
    /// ⚠️ 앞에 둘 수 있는 것은 **정규화와 무관한 검사뿐이다.** `hasPrefix(tokenPrefix)` 를 앞으로 당기면
    ///    자모 분해(NFD)로 들어온 한글 본문이 그 자리에서 빠져나간다 — 그 본문도 그림이어야 한다
    ///    (머리말 "NFC 정규화를 거치는 이유" · 테스트 `자모_분해된_한글_토큰도_같은_이모티콘으로_읽힌다`).
    ///    그래서 보는 것은 **첫 글자가 `[` 인가** 하나다: `[` 는 ASCII 라 정규화가 건드리지 않고, 앞뒤 공백은
    ///    아래 trim 이 지울 몫이라 건너뛴다.
    ///
    /// ⚠️ **건너뛰는 집합은 아래 trim 과 글자 하나까지 같은 집합이어야 한다**(`headSkipSet`). 유니코드
    ///    White_Space 속성(`properties.isWhitespace`)으로 재면 **딱 하나가 어긋난다** — U+200B(ZWSP)는
    ///    그 속성이 거짓인데 `.whitespacesAndNewlines` 는 지운다(전 스칼라 전수 비교 실측: 차이는 이 하나뿐).
    ///    그 한 글자 때문에 `"\u{200B}[아잉:기쁨]"` 이 머리 검사에서 떨어져 **그림이 글자가 됐다**
    ///    (v0.3.62 검토 지적 ②). 싼 검사가 값을 바꾸면 그건 더 이상 싼 검사가 아니다.
    package static func parse(_ body: String) -> AingSticker? {
        guard let head = body.unicodeScalars.first(where: { !headSkipSet.contains($0) }), head == "[" else {
            return nil
        }
        let normalized = MessageBody.sanitized(body)
        guard normalized.hasPrefix(tokenPrefix) else { return nil }
        return allCases.first { $0.token == normalized }
    }

    /// 머리 검사가 건너뛰는 집합. **`MessageBody.sanitized` 의 trim 집합 그 자체다** — 같은 뜻의 다른
    /// 표현을 쓰지 않는 것이 요점이라(위 ⚠️), 여기를 `properties.isWhitespace` 로 되돌리면 ZWSP 하나가
    /// 다시 어긋난다. `static let` 인 이유는 비용이다(`CharacterSet` 을 본문마다 새로 만들지 않게).
    private static let headSkipSet = CharacterSet.whitespacesAndNewlines
}

/// 이모티콘 문구 한 벌. **문구를 뷰마다 적지 않는다** — 맥·폰·알림이 같은 말을 써야 하고,
/// 한 군데만 고쳐지는 날이 반드시 온다.
package enum AingStickerText {
    /// 고르는 그리드의 제목.
    package static let gridTitle = "아잉이 이모티콘"
    /// 입력칸 옆 버튼의 보이스오버·툴팁.
    package static let buttonLabel = "아잉이 이모티콘 보내기"
    /// 그리드를 접는 버튼의 보이스오버·툴팁.
    package static let closeGridLabel = "이모티콘 닫기"

    /// 못 보내는 상태에서 칸을 고른 경우의 한 줄(= 왕복 중). **조용히 닫지 않는 것이 요점이다** —
    /// 직전 전송의 "메시지를 보냈어요"가 그 자리에 남아 있으면 사용자는 이모티콘도 나간 줄 안다.
    /// 어휘는 이모티콘 버튼 툴팁("보내는 중이에요")과 **같은 쪽**을 쓴다(사유가 두 어휘면 한쪽이 낡는다).
    package static let sendingNowNotice = "보내는 중이에요. 잠시 후 다시 눌러 주세요"

    /// 그림 한 장의 보이스오버("아잉이 기쁨"). 말풍선 안의 그림에도 이 문구가 붙는다 —
    /// 그림만 있는 말풍선은 보이스오버에서 **빈 칸**이 되기 때문이다.
    package static func accessibilityLabel(_ sticker: AingSticker) -> String { "아잉이 \(sticker.label)" }

    /// **글자만 들어가는 자리**에 쓸 한 줄. 대화 목록 한 줄 · 안 읽음 요약 · 메뉴바 도착 알림처럼
    /// 그림을 그릴 수 없는 곳에서 `[아잉:기쁨]` 이 **날것으로** 나오면 안 된다("아잉이 기쁨"으로 읽힌다).
    ///
    /// 이모티콘이 아니면 **원문을 손대지 않고 그대로** 돌려준다 — 이 함수가 평범한 메시지를 건드리면
    /// 그게 곧 "내가 보낸 말이 화면에서 달라지는" 버그다.
    package static func preview(for body: String) -> String {
        guard let sticker = AingSticker.parse(body) else { return body }
        return accessibilityLabel(sticker)
    }
}

/// 이모티콘 그림을 번들에서 읽는 자리.
///
/// ## 못 찾으면 `nil` 이다 — 죽지 않는다
/// `Bundle.module` 의 `fatalError` 를 쓰지 않는 이유는 `AIProviderArtwork` 머리말과 같다: 맥 패키징이
/// `check_CheckCore.bundle` 을 **손으로** 복사하므로(`scripts/build-local.sh` 의 `RESOURCE_BUNDLES`),
/// 그 한 줄을 빠뜨린 배포본은 버전·심볼·공증 검사를 전부 통과한다.
///
/// ★ **그림이 없을 때의 폴백은 "이름 글자로 읽어 준다"다.** 호출부(말풍선·그리드 칸)가 `nil` 을 받으면
///   평범한 텍스트 말풍선으로 접고, 그 글자는 날것 토큰이 아니라 `AingStickerText.preview` 를 지난
///   "아잉이 기쁨"이다 — 번들이 깨진 배포본에서 **빈 말풍선**이 되는 쪽이 훨씬 나쁘고(사용자는 상대가 뭘
///   보냈는지 알 길이 없고, 그 증상은 "메시지가 안 와요"로 신고된다), 날것 대괄호는 "깨진 메시지"로 읽힌다.
package enum AingStickerArt {
    /// `.copy` 라 번들 루트가 아니라 이 폴더 안에 들어간다.
    package static let folderName = "Stickers"

    /// 그림 파일의 URL. **테스트가 "번들에 진짜 실렸는가"를 이걸로 묻는다**(파일을 빠뜨린 배포본을 잡는 그물).
    ///
    /// 번들은 제공자 마크의 탐색기를 그대로 쓴다 — 같은 `check_CheckCore.bundle` 이라 후보 목록을 두 벌
    /// 둘 이유가 없다(두 벌이면 한쪽만 고쳐지는 날이 온다).
    package static func url(_ sticker: AingSticker) -> URL? {
        let bundle = AIProviderArtwork.bundle
        return bundle?.url(forResource: sticker.resourceName, withExtension: "png", subdirectory: folderName)
            ?? bundle?.url(forResource: sticker.resourceName, withExtension: "png")
    }

    /// 이 본문을 **그림으로 그리는가** — 그리면 표정과 그릴 그림을 함께 돌려준다.
    ///
    /// ★ **판정하는 자리는 이 함수 하나다**(v0.3.62 검토 지적). 말풍선 행과 틀 높이 추정이 각자
    ///   판정하면(`parse` 만 보는 쪽 · `parse && image != nil` 을 보는 쪽) 번들이 깨진 배포본에서
    ///   둘이 갈린다 — 추정은 그림 한 장(122pt)으로 세는데 행은 글자 한 줄(25pt)로 접혀서, 이모티콘
    ///   건수만큼 회색 빈 판이 쌓인다(2026-09-10 에 고친 그 증상이 그대로 돌아온다).
    ///   그래서 두 자리가 **이 하나**를 부른다(이 저장소의 "판정은 한 자리" 규약).
    ///
    /// 돌려주는 그림에는 **보이스오버 문구가 박혀 있다**(아래 `labeledImage` 의 실측 근거).
    package static func drawable(for body: String) -> (sticker: AingSticker, art: Image)? {
        guard let sticker = AingSticker.parse(body), let art = labeledImage(sticker) else { return nil }
        return (sticker, art)
    }

    /// 보이스오버가 **읽는** 그림(말풍선 몫).
    ///
    /// ★ `Image(decorative:)` + `.accessibilityLabel` 은 **문구가 버려진다.** 2026-10-21 실측
    ///   (AXEnhancedUserInterface 를 켠 NSHostingView 의 AX 자식 덤프):
    ///     · `Image(decorative:).accessibilityLabel("아잉이 기쁨")` → **자식 0개**(보이스오버가 아무 말도 안 한다)
    ///     · `Image(cg, scale:, label:)`                        → 자식 1개 · role=AXImage · label="아잉이 기쁨"
    ///   decorative 그림은 AX 요소가 아니고, 요소가 아닌 뷰에 붙인 라벨은 요소를 만들어 주지 않는다.
    ///   그림만 있는 말풍선은 그러면 보이스오버에서 **빈 칸**이 된다 — `accessibilityLabel` 주석이
    ///   막으려던 바로 그 상태다.
    package static func labeledImage(_ sticker: AingSticker) -> Image? {
        cgImage(sticker).map { Image($0, scale: 1, label: Text(AingStickerText.accessibilityLabel(sticker))) }
    }

    /// 꾸밈용 그림(그리드 칸 몫). **문구를 굽지 않는다** — 칸은 `Button` 이 라벨을 들고 있어서,
    /// 그림에도 문구가 있으면 같은 말을 두 번 읽는다.
    package static func image(_ sticker: AingSticker) -> Image? {
        cgImage(sticker).map { Image(decorative: $0, scale: 1) }
    }

    /// 그릴 수 있는 원본. **한 번 읽어 캐시한다** — 메시지 목록이 본문마다 부르는 자리다.
    /// 없음(`nil`)도 캐시한다(없는 파일을 매 프레임 다시 찾지 않게).
    ///
    /// `Image` 가 아니라 `CGImage` 를 캐시하는 이유: 같은 그림을 **꾸밈용**과 **읽히는 용**으로 두 번
    /// 감싸야 하는데(위 두 함수), `Image` 를 캐시하면 둘 중 하나는 캐시를 못 쓰거나 캐시가 두 벌이 된다.
    /// PNG 를 푸는 비용은 여기 한 번이고, 감싸는 비용은 구조체 하나다.
    package static func cgImage(_ sticker: AingSticker) -> CGImage? { cache.image(sticker, load: load) }

    /// 읽으면서 바로 푼다(`kCGImageSourceShouldCacheImmediately`) — 첫 그리기에서 PNG 를 푸느라
    /// 말풍선이 한 프레임 늦게 뜨지 않게(캡슐 뽑기 기계와 같은 수법).
    ///
    /// `NSImage`/`UIImage` 로 갈라 쓰지 않는 이유: `CGImage` 는 두 플랫폼이 같고, 이 파일에는
    /// `#if canImport(AppKit)` 분기가 하나도 없는 편이 폰 쪽을 고칠 때 안전하다.
    private static func load(_ sticker: AingSticker) -> CGImage? {
        guard let url = url(sticker), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldCache: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    private static let cache = StickerImageCache()

    /// 캐시는 잠금으로 직렬화한다(`Image` 든 `CGImage` 든 `static var` 로 그냥 들 수 없다).
    ///
    /// ⚠️ **잠금을 잡은 채 `load` 를 부른다.** 그 안에서 거치는 번들 탐색기는 **다른 잠금**을 쓰므로
    /// 자기 자신을 다시 잠그지 않는다(`AIProviderArtwork.ArtworkCache` 가 잠금을 둘로 나눈 그 이유를
    /// 여기서도 지킨다 — `NSLock` 은 재귀가 아니다).
    private final class StickerImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private var images: [AingSticker: CGImage?] = [:]

        func image(_ sticker: AingSticker, load: (AingSticker) -> CGImage?) -> CGImage? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = images[sticker] { return cached }
            let value = load(sticker)
            images[sticker] = .some(value)
            return value
        }
    }
}
