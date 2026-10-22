import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.62 — 아잉이 이모티콘(요청: "메시지에 아잉이 이모티콘 만들어주세요").
//
// 이 스위트가 지키는 것은 넷이다.
//  ① **전선 규약**: 본문이 토큰과 **통째로** 같을 때만 그림이다. 앞뒤에 글자가 붙으면 그냥 텍스트고,
//     확성기(`📢 `)가 붙은 본문은 그림이 **되지 않는다**(의도대로다). NFD 로 들어온 한글도 참이어야 한다 —
//     그렇지 않으면 "보낸 화면에서는 그림, 받은 화면에서는 글자"가 된다.
//  ② **토큰 문자열 여섯 개**를 글자 그대로 못 박는다. 이 문자열은 서버를 안 고치고 쓰는 **유일한 계약**이라
//     한 글자만 바뀌어도 그 순간부터 두 버전이 서로의 그림을 글자로 본다. 화면 문구(`label`)를 다듬는
//     커밋이 전선을 조용히 바꾸지 못하게, 둘을 **따로** 재는 것이 요점이다.
//  ③ **그림 여섯 장이 번들에 실렸다.** 파일을 빠뜨린 배포본은 버전·공증 검사를 전부 통과한다.
//  ④ **화면이 그림 길로 간다.** 규칙만 재면 뷰가 그 규칙을 안 부르는 결함이 초록으로 지나간다
//     (이 저장소의 "두 겹 게이트" 함정 — 스토어를 풀어도 뷰가 막으면 아무것도 안 바뀐다).
//  ⑤ **글자만 들어가는 자리는 전부 같은 말을 한다**(검토 지적, v0.3.62). 캐릭터 도착 말풍선·팝오버 수신 줄·
//     신고 인용·그림 없는 폴백 — 네 자리 중 하나만 날것이면 한 버전 안에서 두 화면이 갈린다.
//
// ⚠️ **픽셀 색은 재지 않는다.** 번들의 PNG 는 512×512 로 구운 진짜 그림 여섯 장이지만
//    (`scripts/bake-aing-stickers.swift` · 88~102KB), 색·여백을 단언에 박으면 **그림을 고치는 커밋이
//    빨개진다**. 재는 것은 그림이 바뀌어도 그대로 참인 둘이다 — **그림을 그리는 길로 갔는가**
//    (글자 말풍선이 사라졌는가)와 **파일이 번들에 있는가**.
//
// 소스 계약은 전부 **주석을 걷어낸 뒤** 잰다(안 그러면 설명을 지워야만 초록이 된다).

// MARK: - 길잡이

private let asNow = Date(timeIntervalSince1970: 1_790_000_000)
private let asPeer = MessageReadFixture.peerA

/// 전선 토큰 8개 — **글자 그대로**. 여기를 코드에서 조립해 오면 이 테스트는 자기 자신을 재게 된다.
private let asTokens: [AingSticker: String] = [
    .joy: "[아잉:기쁨]",
    .heart: "[아잉:하트]",
    .sad: "[아잉:슬픔]",
    .angry: "[아잉:화남]",
    .sleepy: "[아잉:졸림]",
    .surprised: "[아잉:놀람]",
]

/// 화면 문구 여섯 개 — 토큰과 **따로** 적는다(머리말 ②).
private let asLabels: [AingSticker: String] = [
    .joy: "기쁨", .heart: "하트", .sad: "슬픔",
    .angry: "화남", .sleepy: "졸림", .surprised: "놀람",
]

private func asEntry(id: String, body: String, isMine: Bool = false) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: asPeer, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: asNow.addingTimeInterval(-60), isMine: isMine, readByPeer: nil, isUnread: nil
    )
}

private enum ASRenderError: Error { case failed }

/// `Binding<Bool>` 에 물릴 깃발 한 칸(테스트가 "눌렀더니 값이 바뀌었나"를 보는 자리).
@MainActor
private final class ASFlag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
    var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
private func asBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw ASRenderError.failed }
    return bitmap
}

/// 두 그림에서 다른 픽셀의 수.
private func asDiffCount(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return -1 }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            if d > 24 { count += 1 }
        }
    }
    return count
}

/// 두 그림이 **그 네모 안에서만** 다른 픽셀의 수와 **가로 경계**(들고 나는 값은 전부 pt — 안에서 scale 2 로 환산한다).
private func asDiffBox(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, box: CGRect) -> (count: Int, maxX: CGFloat) {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return (-1, -1) }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    let x0 = max(0, Int(box.minX * 2)), x1 = min(lhs.pixelsWide, Int(box.maxX * 2))
    let y0 = max(0, Int(box.minY * 2)), y1 = min(lhs.pixelsHigh, Int(box.maxY * 2))
    var count = 0, maxX = -1
    for y in y0..<max(y0, y1) {
        for x in x0..<max(x0, x1) {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            if d > 6 { count += 1; maxX = max(maxX, x) }
        }
    }
    return (count, CGFloat(maxX) / 2)
}

/// 두 그림이 다른 픽셀의 수와 **세로 경계**(pt 아니고 픽셀 — scale 2).
private func asDiffBand(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> (count: Int, minY: Int, maxY: Int) {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return (-1, -1, -1) }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0, minY = Int.max, maxY = -1
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            guard d > 6 else { continue }
            count += 1
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return (count, minY, maxY)
}

/// 말풍선 한 줄짜리 대화 한 판(스냅샷 갈래 — `ImageRenderer` 는 ScrollView 안쪽을 못 그린다).
@MainActor
private func asConversation(body: String) throws -> NSBitmapImageRep {
    let view = asConversationView(body: body)
        .frame(width: MessagePanelLayout.contentWidth, height: 150)
        .background(CheckTheme.background)
    return try asBitmap(view)
}

private func asSource(_ name: String) throws -> String {
    asStripComments(try String(
        contentsOf: CheckCoreSourceLayout.repoRoot
            .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)"),
        encoding: .utf8
    ))
}

/// `//`·`/* */` 주석을 걷어낸다(문자열 안의 `//` 는 남긴다).
private func asStripComments(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

/// 보조기술이 붙은 것처럼 AX 트리를 만들게 하고(`AXEnhancedUserInterface`) 자식들의 라벨을 전부 긁는다.
///
/// **왜 플래그가 필요한가**(2026-10-21 실측): 끈 채로는 `NSHostingView` 가 AX 자식을 **하나도** 만들지
/// 않는다 — `Text("안녕")` 조차 자식 0개라 "라벨이 없다"와 "트리가 없다"를 구별할 수 없다. 켜면 갈린다:
///   · `Image(decorative:).accessibilityLabel(...)` → 자식 **0개**(보이스오버가 아무 말도 안 한다)
///   · `Image(cg, scale:, label:)`                 → 자식 1개 · role=AXImage · 라벨 그대로
/// 플래그는 **앱 전체 설정**이라 재고 나서 되돌린다(켜고 끄기를 여러 번 해도 같은 답이 나온다 — 실측).
/// 창은 띄우지 않는다(호스팅 뷰만으로 같은 답이 나온다 — 알파 0 패널이 사용자 클릭을 먹는 사고를 피한다).
@MainActor
private func asAXProbe<T>(_ view: some View, width: CGFloat, height: CGFloat, _ body: ([NSObject]) -> T) -> T {
    let key = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    let app = NSApplication.shared
    app.accessibilitySetValue(true, forAttribute: key)
    defer { app.accessibilitySetValue(false, forAttribute: key) }

    let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()

    var nodes: [NSObject] = []
    func walk(_ node: Any, depth: Int) {
        guard depth < 12, let object = node as? NSObject else { return }
        nodes.append(object)
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        if object.responds(to: childrenSelector),
           let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] {
            for child in children { walk(child, depth: depth + 1) }
        }
    }
    walk(host, depth: 0)
    // **호스팅 뷰가 살아 있는 동안** 재고 누른다 — 트리를 밖으로 들고 나가면 누가 그 노드를 붙잡고 있는지 알 수 없다.
    let result = body(nodes)
    withExtendedLifetime(host) {}
    return result
}

/// 보조기술이 읽는 라벨. 빈 것은 버린다(요소가 아니라 그릇인 노드).
@MainActor
private func asAccessibilityLabels(_ view: some View, width: CGFloat, height: CGFloat) -> [String] {
    asAXProbe(view, width: width, height: height) { nodes in nodes.compactMap(asAXLabel) }
}

private func asAXLabel(_ node: NSObject) -> String? {
    let selector = NSSelectorFromString("accessibilityLabel")
    guard node.responds(to: selector),
          let text = node.perform(selector)?.takeUnretainedValue() as? String, !text.isEmpty else { return nil }
    return text
}

/// 보조기술이 **실제로 누른다**(`accessibilityPerformPress`). 돌려주는 것은 누름이 받아들여졌는가.
///
/// ⚠️ `perform(_:)` 로 부르면 안 된다 — BOOL 반환을 객체 포인터로 읽어 그 자리에서 죽는다(실측).
/// 그래서 IMP 를 반환형이 맞는 함수로 캐스팅해 부른다.
private func asAXPress(_ node: NSObject) -> Bool {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard node.responds(to: selector) else { return false }
    typealias PressFunction = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(node.method(for: selector), to: PressFunction.self)(node, selector)
}

/// 라벨이 `label` 인 요소를 **전부 찾아 눌러** 본다. (찾은 수, 눌림이 받아들여진 수).
@MainActor
private func asAXPressAll(_ view: some View, width: CGFloat, height: CGFloat, label: String) -> (found: Int, pressed: Int) {
    asAXProbe(view, width: width, height: height) { nodes in
        var found = 0, pressed = 0
        for node in nodes where asAXLabel(node) == label {
            found += 1
            if asAXPress(node) { pressed += 1 }
        }
        return (found, pressed)
    }
}

/// 말풍선 한 줄짜리 대화 한 판(AX·레이아웃 프로브가 같은 뷰를 쓰게).
@MainActor
private func asConversationView(body: String) -> MessageConversationView {
    let entries = [asEntry(id: "s1", body: body)]
    return MessageConversationView(
        items: MessageThreadBuilder.timeline(entries, now: asNow),
        peerUserID: asPeer,
        lastMessageID: entries.last?.id,
        clipsInsteadOfScrolling: true
    )
}

/// `from` 뒤부터 그 뒤 첫 `to` 직전까지.
private func asRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

@MainActor
@Suite("V0362AingSticker")
struct V0362AingStickerTests {

    // MARK: ① 전선 규약 — 통째로 같을 때만

    /// 파싱 표. **결과를 잰다** — 들어간 문자열 하나하나에 대해 나온 값이 무엇인가.
    @Test(arguments: [
        // (본문, 기대값 rawValue 또는 nil)
        ("[아잉:기쁨]", "joy"),
        ("[아잉:하트]", "heart"),
        ("[아잉:슬픔]", "sad"),
        ("[아잉:화남]", "angry"),
        ("[아잉:졸림]", "sleepy"),
        ("[아잉:놀람]", "surprised"),
        // 앞뒤 공백·개행만 있는 것은 **참**이다(`MessageBody.sanitized` 가 trim 한다).
        ("  [아잉:기쁨]  ", "joy"),
        ("\n[아잉:하트]\n", "heart"),
        ("\t[아잉:슬픔] ", "sad"),
        // 줄바꿈 없는 공백(U+00A0)도 `.whitespacesAndNewlines` 가 지우는 공백이다 — **싼 머리 검사가
        // 건너뛰는 집합이 그 집합과 같아야** 이 줄이 초록이다(`== " "` 로 좁히면 여기서 빨개진다).
        ("\u{00A0}[아잉:놀람]\u{00A0}", "surprised"),
        // 앞뒤에 **글자**가 붙으면 그냥 텍스트다(부분 치환 금지).
        ("[아잉:기쁨] 어때요?", nil),
        ("ㅋㅋ [아잉:기쁨]", nil),
        ("([아잉:기쁨])", nil),
        ("[아잉:기쁨][아잉:하트]", nil),
        // 2026-10-21 에 뺀 두 표정은 이제 **없는 이름**이다 — 머리만 같고 그림이 아니다.
        ("[아잉:굿]", nil),
        ("[아잉:박수]", nil),
        // 확성기는 서버가 앞에 `📢 ` 를 붙인다 → 토큰과 같지 않다 → 그림이 아니다.
        ("📢 [아잉:기쁨]", nil),
        // 머리만 같은 것, 없는 표정, 빈 본문.
        ("[아잉:없는것]", nil),
        ("[아잉:]", nil),
        ("[아잉:기쁨", nil),
        ("아잉:기쁨]", nil),
        ("", nil),
        ("   ", nil),
        ("기쁨", nil),
    ] as [(String, String?)])
    func 본문이_토큰과_통째로_같을_때만_이모티콘이다(body: String, expected: String?) {
        #expect(AingSticker.parse(body)?.rawValue == expected, "본문 \"\(body)\" 의 판정이 틀렸다")
    }

    /// **NFD 로 들어온 한글도 참이다.** macOS 입력기·파인더에서 온 한글은 자모 분해로 들어와 바이트가 다른데,
    /// 거르지 못하면 보낸 쪽 화면에서는 그림이고 받은 쪽에서는 글자가 된다.
    ///
    /// 대조군이 실제로 다름을 먼저 못 박는다 — 두 문자열이 같은 바이트면 이 테스트는 영원히 공허한 초록이다.
    @Test func 자모_분해된_한글_토큰도_같은_이모티콘으로_읽힌다() {
        for sticker in AingSticker.allCases {
            let decomposed = sticker.token.decomposedStringWithCanonicalMapping
            #expect(Array(decomposed.unicodeScalars) != Array(sticker.token.unicodeScalars),
                    "\(sticker) 의 NFD 가 NFC 와 같은 바이트다 — 이 검사가 아무것도 안 잰다")
            #expect(AingSticker.parse(decomposed) == sticker, "\(sticker) 의 NFD 본문이 글자로 떨어진다")
            // 앞뒤 공백까지 섞인 실제 입력 모양.
            #expect(AingSticker.parse(" \(decomposed)\n") == sticker)
        }
    }

    /// 머리 검사(`tokenPrefix`)는 **싼 거름일 뿐**이고 혼자서 참을 내지 않는다.
    @Test func 토큰_머리만_같은_본문은_이모티콘이_아니다() {
        #expect(AingSticker.tokenPrefix == "[아잉:")
        for body in ["[아잉:없는것]", "[아잉:기쁨]다음", "[아잉:웃음]", "[아잉:기쁨]]"] {
            #expect(body.hasPrefix(AingSticker.tokenPrefix), "표본이 머리 검사를 안 지난다 — 검사가 공허하다")
            #expect(AingSticker.parse(body) == nil, "머리만 같은 \"\(body)\" 가 이모티콘이 됐다")
        }
        // 대조군: **머리가 다른** 본문은 머리 검사에서 끝난다(그 길이 실제로 쓰인다).
        #expect(!"📢 [아잉:기쁨]".hasPrefix(AingSticker.tokenPrefix))
    }

    /// **싼 머리 검사가 값을 바꾸지 않는다**(v0.3.62 검토 지적 ②).
    ///
    /// 머리 검사가 건너뛰는 집합과 `MessageBody.sanitized` 의 trim 집합은 **한 글자만 어긋날 수 있었다**:
    /// U+200B(ZWSP)는 유니코드 White_Space 속성이 거짓인데 `.whitespacesAndNewlines` 는 지운다
    /// (전 스칼라 전수 비교 실측 — 차이는 이 하나뿐). 그래서 `properties.isWhitespace` 로 거르던 동안
    /// ZWSP 로 시작하는 토큰은 머리 검사에서 떨어져 **그림이 글자로** 나갔다(머리 검사가 없던 코드는 그림이었다).
    ///
    /// 전수 비교가 아니라 **그 한 입력의 결과**로 잰다.
    @Test func 폭_없는_공백으로_시작하는_토큰도_그림이_된다() {
        let zwsp = "\u{200B}"
        // 대조 ①: trim 집합이 이 글자를 **실제로** 지운다(아니면 아래 기대값이 애초에 틀렸다).
        #expect(MessageBody.sanitized(zwsp + "[아잉:기쁨]") == "[아잉:기쁨]")
        // 대조 ②: 이 글자는 유니코드 White_Space 가 **아니다**(두 집합이 갈리던 바로 그 지점).
        #expect(Unicode.Scalar(0x200B).map { !$0.properties.isWhitespace } == true)

        #expect(AingSticker.parse(zwsp + "[아잉:기쁨]") == .joy, "ZWSP 로 시작하는 토큰이 글자로 떨어졌다")
        #expect(AingSticker.parse("[아잉:놀람]" + zwsp) == .surprised, "ZWSP 로 끝나는 토큰이 글자로 떨어졌다")
        #expect(AingStickerArt.drawable(for: zwsp + "[아잉:하트]")?.sticker == .heart, "그림 길로 안 간다")

        // 머리 검사의 **목적은 그대로**다: 평범한 본문은 여전히 그림이 아니다(가운데 ZWSP 도 토큰이 아니다).
        #expect(AingSticker.parse("점심 드셨어요?") == nil)
        #expect(AingSticker.parse("[아잉:\u{200B}기쁨]") == nil)
    }

    // MARK: ② 토큰 여섯 개 — 글자 그대로

    @Test func 토큰_여섯_개는_글자_그대로_서로_다르고_200자_상한_아래다() {
        #expect(AingSticker.allCases.count == 6)
        // case 선언 순서 = 그리드 순서 = 사용자가 보는 차례.
        #expect(AingSticker.allCases.map(\.rawValue)
                == ["joy", "heart", "sad", "angry", "sleepy", "surprised"])

        for sticker in AingSticker.allCases {
            #expect(sticker.token == asTokens[sticker], "\(sticker) 의 전선 토큰이 바뀌었다 — 구버전과 갈린다")
            #expect(sticker.label == asLabels[sticker], "\(sticker) 의 화면 문구가 바뀌었다")
            #expect(sticker.resourceName == "sticker-\(sticker.rawValue)")
            // 7 코드포인트(= 서버 char_length)라 200자 상한과 무관하다.
            #expect(sticker.token.unicodeScalars.count <= MessageBody.maxLength)
            // 서버가 보는 눈금으로 재어도 보낼 수 있는 본문이다(빈 칸·초과가 아니다).
            #expect(MessageBody.validate(sticker.token) == .ok(sticker.token),
                    "\(sticker) 의 토큰이 전송 사전 게이트를 못 지난다")
            // 정규화가 토큰을 건드리지 않는다(이미 NFC + trim 된 모양이어야 한다).
            #expect(MessageBody.sanitized(sticker.token) == sticker.token)
        }
        #expect(Set(AingSticker.allCases.map(\.token)).count == 6, "토큰이 서로 겹친다")
        #expect(Set(AingSticker.allCases.map(\.label)).count == 6, "화면 문구가 서로 겹친다")
        #expect(Set(AingSticker.allCases.map(\.resourceName)).count == 6, "그림 파일 이름이 서로 겹친다")
    }

    /// 글자만 들어가는 자리의 문구. **평범한 본문은 손대지 않는다**(그게 곧 "내 말이 화면에서 달라지는" 버그다).
    @Test func 글자_자리_미리보기는_아잉이_이름으로_읽히고_평범한_본문은_그대로다() {
        #expect(AingStickerText.preview(for: "[아잉:기쁨]") == "아잉이 기쁨")
        #expect(AingStickerText.preview(for: "  [아잉:놀람]  ") == "아잉이 놀람")
        for sticker in AingSticker.allCases {
            #expect(AingStickerText.preview(for: sticker.token) == "아잉이 \(sticker.label)")
            #expect(AingStickerText.accessibilityLabel(sticker) == "아잉이 \(sticker.label)")
            // 미리보기에 날것이 남아 있으면 안 된다.
            #expect(!AingStickerText.preview(for: sticker.token).contains(AingSticker.tokenPrefix))
        }
        // 대조군: 이모티콘이 아닌 본문은 **글자 하나도** 바뀌지 않는다(앞뒤 공백까지).
        for body in ["점심 드셨어요?", " 앞뒤 공백 ", "[아잉:기쁨] 어때요?", "📢 [아잉:기쁨]", ""] {
            #expect(AingStickerText.preview(for: body) == body, "평범한 본문 \"\(body)\" 가 바뀌었다")
        }
    }

    // MARK: ③ 그림 여섯 장이 번들에 실렸다

    /// **파일을 빠뜨린 배포본을 잡는 그물.** 번들에 없으면 URL 이 nil 이고, 그런 배포본은 버전·공증을 다 통과한다.
    @Test func 이모티콘_여섯_장이_번들에_실제로_실렸다() throws {
        _ = try #require(AIProviderArtwork.bundle, "check_CheckCore.bundle 을 못 찾았다")
        #expect(AingStickerArt.folderName == "Stickers")
        for sticker in AingSticker.allCases {
            let url = try #require(AingStickerArt.url(sticker), "\(sticker.resourceName).png 이 번들에 없다")
            #expect(url.lastPathComponent == "\(sticker.resourceName).png")
            let size = try #require(
                try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
                "\(sticker.resourceName).png 을 읽을 수 없다"
            )
            #expect(size > 0, "\(sticker.resourceName).png 이 빈 파일이다")
            // 읽어서 그릴 수 있다(**디코딩은 된다** — 색·크기는 보지 않는다. 머리말 ⚠️).
            #expect(AingStickerArt.image(sticker) != nil, "\(sticker.resourceName).png 을 그림으로 못 읽는다")
        }
        // 저장소 쪽에도 여섯 장이 있다(번들만 보면 옛 빌드 산출물로 초록이 될 수 있다).
        let folder = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/CheckCore/Resources/Stickers")
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") })
        #expect(onDisk == Set(AingSticker.allCases.map { "\($0.resourceName).png" }),
                "저장소의 그림 목록이 열거와 다르다: \(onDisk.sorted())")
    }

    /// 그림이 세 타깃(맥·폰·위젯)에 배달되는 선언. `.copy` 여야 한다 — `.process` 는 하위 폴더를 평탄화한다.
    @Test func 코어가_이모티콘_리소스를_선언한다() throws {
        let manifest = asStripComments(try String(
            contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8
        ))
        #expect(manifest.contains("name: \"CheckCore\""))
        #expect(manifest.contains(".copy(\"Resources/Stickers\")"),
                "CheckCore 가 이모티콘 리소스를 선언하지 않는다 — 폰·위젯이 그림을 못 본다")
    }

    /// 번들을 못 찾아도 **죽지 않는다**(맥 패키징이 번들 복사 한 줄을 빠뜨린 배포본에서 앱이 죽지 않게).
    @Test func 그림을_못_찾아도_죽지_않고_글자로_접힌다() throws {
        let core = try asSource("AingSticker.swift")
        #expect(!core.contains("Bundle.module"), "Bundle.module 은 못 찾으면 fatalError 다 — 직접 훑어라")
        #expect(!core.contains("fatalError"), "그림이 없다고 앱을 죽이지 않는다")
        #expect(core.contains("AIProviderArtwork.bundle"), "번들 탐색기를 두 벌로 만들었다")

        // 말풍선·그리드 칸 둘 다 "그림이 없으면 글자" 갈래를 갖는다.
        let view = try asSource("CheckMessageView.swift")
        #expect(view.contains("if let drawn = AingStickerArt.drawable(for: entry.body)"),
                "말풍선이 그림 없음을 안 가린다 — 번들이 깨진 배포본에서 빈 말풍선이 된다")
        let cell = try #require(asRegion(view, from: "private struct AingStickerGridCell: View {", to: "\n}\n"))
        #expect(cell.contains("Text(sticker.label)"), "그리드 칸이 그림을 못 읽으면 아무것도 없는 칸이 된다")
    }

    // MARK: ④ 화면이 그림 길로 간다

    /// **스티커 본문은 글자 말풍선을 그리지 않는다.**
    ///
    /// 기준선이 요점이다: `[아잉:기쁨.`(마지막 글자만 다른 **일반 텍스트**)과 `[아잉:기쁨,` 는 글자 하나만
    /// 다르므로 그림 차이가 아주 작다. 반면 토큰 본문은 캡슐 말풍선이 통째로 사라지고 그림 자리가 들어서므로
    /// 차이가 훨씬 크다. 색·픽셀 값을 보지 않으므로 **진짜 그림이 들어와도 이 부등식은 그대로 참이다**
    /// (그림이 생기면 차이는 더 커진다).
    @Test func 이모티콘_본문은_글자_말풍선_대신_그림_길로_간다() throws {
        let sticker = try asConversation(body: "[아잉:기쁨]")
        let plain = try asConversation(body: "[아잉:기쁨.")
        let plainTwin = try asConversation(body: "[아잉:기쁨,")

        let twinDiff = asDiffCount(plain, plainTwin)
        let stickerDiff = asDiffCount(sticker, plain)
        #expect(twinDiff >= 0 && stickerDiff >= 0, "렌더 크기가 서로 다르다 — 비교가 성립하지 않는다")
        // 글자 하나 차이(기준선)는 작다. 이 줄이 무너지면 아래 부등식은 아무 뜻이 없다.
        #expect(twinDiff < 200, "글자 하나 바뀐 기준선의 차이가 \(twinDiff)px — 기준선이 기준선 노릇을 못 한다")
        #expect(stickerDiff > twinDiff * 3 + 200,
                "토큰 본문이 일반 텍스트와 거의 같게 그려졌다(차이 \(stickerDiff)px, 기준선 \(twinDiff)px) — 글자 말풍선 그대로다")
    }

    /// 틀 높이 추정도 "그림 한 장"으로 센다. 글자처럼 한 줄(25pt)로 세면 120pt 그림이 틀 밖으로 밀린다.
    @Test func 틀_높이_추정이_이모티콘을_그림_한_장으로_센다() {
        func height(_ body: String) -> CGFloat {
            MessagePanelLayout.conversationContentHeight(
                MessageThreadBuilder.timeline([asEntry(id: "h1", body: body)], now: asNow)
            )
        }
        let stickerHeight = height("[아잉:기쁨]")
        // 기준선: **같은 글자 수**인데 이모티콘이 아닌 본문(한 줄짜리 텍스트 말풍선 + 날짜 구분선).
        let textHeight = height("[아잉:기쁨.")
        #expect(textHeight < 70, "기준선이 한 줄 말풍선이 아니다(\(textHeight)pt)")
        #expect(stickerHeight >= MessagePanelLayout.stickerSide,
                "이모티콘 한 장이 \(stickerHeight)pt 로 세어진다 — 그림(\(MessagePanelLayout.stickerSide)pt)이 틀 밖으로 밀린다")
        // 차이가 곧 "그림 한 장 − 글자 한 줄"이다(글자 한 줄 25pt → 95pt 안팎).
        #expect(stickerHeight - textHeight > 80,
                "그림을 글자처럼 센다(그림 \(stickerHeight)pt · 글자 \(textHeight)pt)")
        #expect(MessagePanelLayout.stickerSide >= 100 && MessagePanelLayout.stickerSide <= 160)
    }

    /// 고르는 그리드는 **여섯 칸**이고 열거 순서를 그대로 쓴다. 칸 크기는 폭과 남은 높이 **둘 다**를 본다 —
    /// 크롬이 대화를 76pt 까지 깎는 조합에서도 두 줄이 다 보여야 한다(아래 줄이 사라지면 기능이 없는 것과 같다).
    @Test func 그리드는_여섯_칸이고_좁은_높이에서도_두_줄이_선다() throws {
        #expect(AingStickerGridLayout.columns * AingStickerGridLayout.rows == AingSticker.allCases.count)

        let view = try asSource("CheckMessageView.swift")
        let grid = try #require(asRegion(view, from: "struct AingStickerGridView: View {", to: "private struct AingStickerGridCell"))
        #expect(grid.contains("ForEach(AingSticker.allCases"), "그리드가 여섯 칸을 열거에서 받지 않는다")
        #expect(grid.contains("onPick(sticker)"))

        // 넉넉한 높이에서는 **폭**이 칸을 정한다((292 − 여백 16 − 간격 12) / 3 = 88).
        // 높이가 정하는 값은 (250 − 크롬 48) / 2 = 101 이라 더 크다 — 둘 중 작은 쪽을 쓴다는 뜻이다.
        let roomy = AingStickerGridLayout.cellSide(availableHeight: MessagePanelLayout.conversationHeight)
        #expect(roomy > 70 && roomy < 100, "넉넉한 높이의 칸이 \(roomy)pt")
        #expect(AingStickerGridLayout.showsTitle(availableHeight: MessagePanelLayout.conversationHeight),
                "평소 높이에서 제목이 접힌다")

        // ★ 대화 자리가 어떤 높이로 깎여도 **여섯 칸이 그 안에 든다.** 76pt 는 크롬이 가장 클 때
        //   (배너 + 패치노트 4줄 + 주간 목표 편집)의 값이고, 거기서도 아래 줄이 잘리면 세 표정이 사라진다.
        for available in [
            MessagePanelLayout.minConversationHeight, 80, 95, 104, 120,
            MessagePanelLayout.conversationHeight
        ] as [CGFloat] {
            let side = AingStickerGridLayout.cellSide(availableHeight: available)
            let used = AingStickerGridLayout.usedHeight(availableHeight: available)
            #expect(side >= AingStickerGridLayout.minCell,
                    "\(available)pt 에서 칸이 과녁 최소치보다 작다(\(side)pt)")
            #expect(used <= available + 0.5,
                    "\(available)pt 에서 그리드가 \(used)pt 를 써서 아래 줄이 잘린다")
        }
        // 좁은 자리에서는 제목을 접고, 칸은 그래도 작아진다(높이 계산이 공허하지 않다는 대조).
        let tight = AingStickerGridLayout.cellSide(availableHeight: MessagePanelLayout.minConversationHeight)
        #expect(!AingStickerGridLayout.showsTitle(availableHeight: MessagePanelLayout.minConversationHeight),
                "76pt 에서 제목을 세우면 아래 줄이 잘린다")
        #expect(tight < roomy, "높이가 칸 크기를 전혀 안 깎는다 — 좁은 화면 계산이 공허하다")
        // 뷰도 같은 판정을 쓴다(상수를 뷰 안에 따로 적으면 좁은 화면만 조용히 깨진다).
        #expect(grid.contains("AingStickerGridLayout.showsTitle(availableHeight: availableHeight)"))
        #expect(grid.contains("AingStickerGridLayout.padding(availableHeight: availableHeight)"))
    }

    /// **아래 줄 세 칸이 실제로 그려진다.** 칸 크기 산식만 재면 "숫자는 맞는데 화면엔 없다"가 초록으로
    /// 지나간다(이 저장소의 함정: 단언은 부르는 자리를 재라).
    ///
    /// 그림 색을 보지 않는다 — 빈 바탕과 **다른 픽셀이 어느 띠에 있는가**만 본다. 그래서 그림 여섯 장을
    /// 다시 구워도 이 단언은 그대로 참이다(칸 바탕이 우리 것이라 그림과 무관하다).
    @Test(arguments: [MessagePanelLayout.conversationHeight, MessagePanelLayout.minConversationHeight])
    func 그리드는_주어진_높이_안에_여섯_칸을_실제로_그린다(available: CGFloat) throws {
        let size = CGSize(width: MessagePanelLayout.contentWidth, height: available)
        let blank = try asBitmap(
            Color.clear.frame(width: size.width, height: size.height).background(CheckTheme.background)
        )
        let drawn = try asBitmap(
            AingStickerGridView(availableHeight: available, onPick: { _ in }, onClose: {})
                .frame(width: size.width, height: size.height)
                .background(CheckTheme.background)
        )
        let band = asDiffBand(blank, drawn)
        #expect(band.count > 0, "\(available)pt 그리드가 아무것도 안 그렸다(노란 상자이거나 빈 판이다)")

        // 윗줄과 아랫줄이 **둘 다** 그려졌다: 그려진 띠가 그리드 두 줄의 중앙선을 가로지른다.
        let cell = AingStickerGridLayout.cellSide(availableHeight: available)
        let used = AingStickerGridLayout.usedHeight(availableHeight: available)
        let middle = Int((used - cell - AingStickerGridLayout.spacing / 2) * 2)   // scale 2
        #expect(band.minY < middle, "윗줄이 안 그려졌다(그려진 띠 \(band.minY)…\(band.maxY), 중앙선 \(middle))")
        #expect(band.maxY > middle, "아랫줄이 안 그려졌다(그려진 띠 \(band.minY)…\(band.maxY), 중앙선 \(middle))")
        // 주어진 높이를 넘겨 그리지 않았다(프레임이 잘라 주기 전에 산식이 이미 맞다).
        #expect(used <= available + 0.5)
    }

    /// **탈출구가 없는 조합이 하나도 없다**(v0.3.62 검토 지적 ①).
    ///
    /// 갇히는 길은 두 개가 겹쳐서 생겼다: 제목 줄이 접히는 좁은 크롬에서는 [x] 가 안 그려졌고(104pt 경계),
    /// 왕복 중에는 칸이 `.disabled` 라 "칸을 누르면 닫힌다"도, 입력칸 옆 토글도 잠겼다 — 탈출구 **0**.
    ///
    /// 모양이 아니라 **결과**로 잰다: 보조기술이 그 손잡이를 찾아 **실제로 눌러** `onClose` 가 불리는가.
    /// (소스에서 `.overlay` 한 줄을 지우면 좁은 높이 쪽이 "손잡이를 못 찾았다"로 빨개진다.)
    @Test(arguments: [
        MessagePanelLayout.minConversationHeight, 80, 95, 103, 104, 120, MessagePanelLayout.conversationHeight
    ] as [CGFloat], [true, false])
    func 어떤_높이_어떤_상태에서도_그리드를_닫을_길이_남는다(available: CGFloat, canSend: Bool) {
        var closed = 0
        let grid = AingStickerGridView(
            availableHeight: available, canSend: canSend, onPick: { _ in }, onClose: { closed += 1 }
        )
        let handle = asAXPressAll(
            grid, width: MessagePanelLayout.contentWidth, height: available,
            label: AingStickerText.closeGridLabel
        )
        #expect(handle.found >= 1,
                "높이 \(available)pt · 보낼 수 있음 \(canSend) 에서 닫기 손잡이가 화면에 없다 — 갇힌다")
        #expect(handle.pressed >= 1, "손잡이는 있는데 눌리지 않는다(\(available)pt · \(canSend))")
        #expect(closed >= 1, "눌렀는데 그리드가 닫히지 않는다(\(available)pt · \(canSend))")
    }

    /// **펼친 동안의 툴팁은 닫기를 먼저 말한다**(탈출구 셋째 짝 — v0.3.62 검토 지적 ①).
    ///
    /// 버튼이 눌리는지(`stickerCanToggle`)는 고쳐 놓고 **말**을 안 고치면, 눌리는 버튼이 "보내는 중이에요"라고
    /// 말해 사용자는 갇혔다고 읽는다. 그래서 `stickerHelp` 의 if 순서가 계약이다 — 그 값을 **결과로** 읽는다
    /// (순서를 뒤집으면 이 단언이 빨개진다. 파일 전체 substring 으로 재면 뒤집어도 초록이다).
    @Test(.gomokuDefaultsCleanup)
    func 펼친_동안의_툴팁은_못_누르는_사유보다_닫기를_먼저_말한다() {
        let (store, _) = makeMessageReadStore("v0362-help")
        store.selectedMessagePeerID = asPeer
        store.isSendingMessage = true
        #expect(!store.canSendStickerNow, "왕복 중인데 보낼 수 있다고 한다 — 아래 단언이 공허하다")

        let shown = MessageComposerView(store: store, rendersPlainText: true, stickerGridShown: .constant(true))
        #expect(shown.stickerCanToggle, "펼친 버튼이 안 눌린다 — 문구 단언의 전제가 깨졌다")
        #expect(shown.stickerHelp == AingStickerText.closeGridLabel,
                "펼쳐서 눌리는 버튼인데 못 누르는 사유를 말한다: \(shown.stickerHelp)")

        // 대조 — 접혀 있으면 사유를 말한다. 이게 없으면 "늘 닫기라고 말한다"도 통과한다.
        let hidden = MessageComposerView(store: store, rendersPlainText: true, stickerGridShown: .constant(false))
        #expect(!hidden.stickerCanToggle, "접혔는데 왕복 중에도 눌린다 — 전송 게이트가 사라졌다")
        #expect(hidden.stickerHelp != AingStickerText.closeGridLabel,
                "접혀 있는데 닫기를 말한다: \(hidden.stickerHelp)")
    }

    /// **왕복 중에도 작성기 옆 토글이 그리드를 닫는다**(탈출구 둘째 짝 — v0.3.62 검토 지적 ①).
    ///
    /// 펼친 뒤에 전송 왕복이 시작되면 이 버튼은 더 이상 "보내기 문"이 아니라 **닫기**다. 그때도 같이 잠그면
    /// 그리드 쪽 [x] 와 함께 길이 둘 다 막힌다. 모양이 아니라 **결과**로 잰다 — 눌러서 깃발이 내려가는가.
    @Test(.gomokuDefaultsCleanup)
    func 왕복_중에도_작성기_토글이_펼친_그리드를_닫는다() {
        let (store, _) = makeMessageReadStore("v0362-toggle")
        store.selectedMessagePeerID = asPeer
        store.isSendingMessage = true
        #expect(!store.canSendStickerNow, "왕복 중인데 보낼 수 있다고 한다 — 아래 단언이 공허하다")

        // ① 펼쳐 둔 상태: 못 보내도 눌리고, 눌리면 접힌다.
        let shown = ASFlag(true)
        let open = asAXPressAll(
            MessageComposerView(store: store, rendersPlainText: true, stickerGridShown: shown.binding),
            width: MessagePanelLayout.contentWidth, height: 140, label: AingStickerText.closeGridLabel
        )
        #expect(open.found == 1, "펼친 상태의 작성기에 닫기 손잡이가 없다(찾은 수 \(open.found))")
        #expect(!shown.value, "왕복 중이라 토글이 잠겼다 — 그리드 쪽 [x] 와 함께 탈출구가 0 이 된다")

        // ② 대조: 접혀 있으면 게이트는 그대로다(통째로 풀어 버린 것이 아니다).
        let hidden = ASFlag(false)
        let closed = asAXPressAll(
            MessageComposerView(store: store, rendersPlainText: true, stickerGridShown: hidden.binding),
            width: MessagePanelLayout.contentWidth, height: 140, label: AingStickerText.buttonLabel
        )
        #expect(closed.found == 1, "접힌 상태의 이모티콘 버튼을 못 찾았다")
        #expect(!hidden.value, "못 보내는 상태인데 그리드가 펼쳐졌다 — 전송 게이트가 사라졌다")
    }

    /// 제목이 접힌 자리의 [x] 는 **그려지기도** 한다 — AX 트리에만 있고 화면에 없으면 눈으로는 못 찾는다.
    /// 그리고 그 자리는 **여섯 칸 오른쪽 바깥**이라 칸을 하나도 안 가린다(겹침으로 두는 값).
    ///
    /// 칸의 오른쪽 끝은 **그림에서 잰다**: 좁은 자리의 `LazyVGrid` 는 남는 폭 안에서 가운데로 서기 때문에
    /// (실측 — 76pt 에서 칸 띠는 75…209.5pt) 산식으로 적으면 그 숫자가 조용히 틀린다.
    @Test func 제목을_접은_자리의_닫기_손잡이는_칸_바깥에_실제로_그려진다() throws {
        let available = MessagePanelLayout.minConversationHeight
        #expect(!AingStickerGridLayout.showsTitle(availableHeight: available), "이 높이는 제목을 접지 않는다 — 표본이 틀렸다")

        let width = MessagePanelLayout.contentWidth
        let blank = try asBitmap(Color.clear.frame(width: width, height: available).background(CheckTheme.background))
        let view = AingStickerGridView(availableHeight: available, canSend: false, onPick: { _ in }, onClose: {})
            .frame(width: width, height: available)
            .background(CheckTheme.background)
        _ = try asBitmap(view)   // ImageRenderer 는 첫 장을 다르게 굽는다 — 굳힌 뒤 본다.
        let drawn = try asBitmap(view)

        // ① 아래 줄 한 띠로 **칸의 오른쪽 끝**을 잰다(기준선 — 여기가 비면 아래 단언이 공허하다).
        let cell = AingStickerGridLayout.cellSide(availableHeight: available)
        let used = AingStickerGridLayout.usedHeight(availableHeight: available)
        let rowBand = CGRect(x: 0, y: used - cell + 4, width: width, height: max(4, cell - 8))
        let cells = asDiffBox(blank, drawn, box: rowBand)
        #expect(cells.count > 0, "아래 줄 네 칸이 안 그려졌다 — 칸의 오른쪽 끝을 잴 수 없다")

        // ② 그 **오른쪽 바깥 · 위쪽 띠**에 손잡이가 그려져 있다. 둘이 겹치지 않는 것이 이 단언의 절반이다.
        //    칸 가장자리의 앤티앨리어싱이 그 띠로 몇 px 새므로(손잡이를 지운 판에서 16px · 216.5pt 까지 —
        //    실측) "0 보다 크다"로는 모자란다: **오른쪽 끝에 붙어 있는가**를 함께 본다.
        let strip = CGRect(x: cells.maxX + 2, y: 0, width: width - cells.maxX - 2, height: 26)
        #expect(strip.width > 18, "칸이 오른쪽 끝까지 차서 손잡이 자리가 없다(칸 오른쪽 끝 \(cells.maxX)pt)")
        let handle = asDiffBox(blank, drawn, box: strip)
        #expect(handle.count > 50,
                "제목을 접은 자리에 [x] 가 안 그려졌다(칸 오른쪽 끝 \(cells.maxX)pt 바깥에 \(handle.count)px 뿐)")
        #expect(handle.maxX > width - 10,
                "손잡이가 오른쪽 끝에 안 붙어 있다(그려진 가장 오른쪽 \(handle.maxX)pt) — 칸을 가리는 자리로 옮겨졌다")
    }

    /// 위 프로브가 **공허하지 않다**: 같은 누름이 칸에서는 `canSend` 에 따라 갈린다(그러니 위 초록은
    /// "아무거나 눌러도 참"이 아니다). 못 보내는 동안 칸은 눌려도 아무 일이 없고, 닫기만 살아 있다.
    @Test(arguments: [true, false])
    func 보조기술_누름_프로브는_막힌_칸과_살아있는_닫기를_가른다(canSend: Bool) {
        var picked = 0
        let grid = AingStickerGridView(
            availableHeight: MessagePanelLayout.conversationHeight, canSend: canSend,
            onPick: { _ in picked += 1 }, onClose: {}
        )
        let cell = asAXPressAll(
            grid, width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.conversationHeight,
            label: AingStickerText.accessibilityLabel(.joy)
        )
        #expect(cell.found == 1, "칸을 못 찾았다 — 프로브가 그리드를 안 보고 있다")
        #expect(picked == (canSend ? 1 : 0),
                "보낼 수 있음 \(canSend) 인데 칸 누름이 \(picked) 번 먹혔다")
    }

    /// 보내는 길: 그리드 → `store.sendSticker` → **기존 전송 문**(`sendMessage(to:body:)`).
    /// 새 RPC·새 길을 뚫지 않았음을 소스로 못 박는다(서버 변경 0 이 이 기능 설계의 핵심이다).
    @Test func 이모티콘_전송은_기존_문을_지난다() throws {
        let view = try asSource("CheckMessageView.swift")
        #expect(view.contains("store.sendSticker(sticker)"), "그리드가 스토어 문을 안 지난다")
        #expect(view.contains("stickerGridShown"), "작성기에 이모티콘 버튼 배선이 없다")

        let store = asStripComments(try CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreMessages.swift"))
        let door = try #require(asRegion(store, from: "func sendSticker(", to: "\n    }"))
        #expect(door.contains("sendMessage(to: peer, body: sticker.token)"), "이모티콘이 기존 전송 문을 안 지난다")
        for forbidden in ["service.", "URLSession", "withSessionRetry", "Task {"] {
            #expect(!door.contains(forbidden), "이모티콘 전송이 \(forbidden) 로 새 길을 뚫었다")
        }
        // 서버·마이그레이션은 하나도 안 고쳤다 — 이모티콘은 평범한 텍스트 메시지다.
        #expect(!store.contains("p_sticker") && !store.contains("send_sticker"),
                "이모티콘 전용 서버 인자/함수가 생겼다 — 구버전을 끊는 변경이다")
    }

    /// 글자만 들어가는 자리(메뉴바 수신 표시 한 줄)가 **날것을 안 보여 준다**.
    @Test func 수신_표시_한_줄은_아잉이_이름으로_보여_준다() throws {
        let menu = try asSource("CheckMenuView.swift")
        let strip = try #require(asRegion(menu, from: "struct PokeMessageReceiptStrip: View {", to: "\n}\n"))
        #expect(strip.contains("Text(AingStickerText.preview(for: message.body))"),
                "수신 표시 줄이 본문을 날것으로 띄운다 — [아잉:기쁨] 이 그대로 보인다")
        #expect(!strip.contains("Text(message.body)"))
    }

    // MARK: 스토어 — 결과로 잰다

    /// `sendSticker` 가 **실제로 서버까지 간다**: `send_message` 1회 · 본문은 토큰 그대로.
    /// 대조군 둘: 상대를 안 골랐으면 0회 · 입력칸에 쓰던 글은 **살아남는다**.
    @Test(.gomokuDefaultsCleanup)
    func 이모티콘을_고르면_토큰_본문이_서버까지_가고_쓰던_글은_남는다() async {
        let (store, host) = makeMessageReadStore("v0362-sticker") { call, _ in
            call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#) : nil
        }

        // 대조: 상대를 안 골랐으면 아무것도 안 나간다(게이트가 살아 있다).
        #expect(!store.canSendStickerNow)
        store.sendSticker(.joy)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 0)

        store.selectedMessagePeerID = asPeer
        store.messageDraft = "쓰던 글"
        #expect(store.canSendStickerNow, "상대를 골랐는데 이모티콘을 못 보낸다")
        store.sendSticker(.surprised)
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "send_message") >= 1 && !store.isSendingMessage
        }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 1)
        let body = MessageReadStubProtocol.calls(host: host, rpc: "send_message").first?.json
        #expect(body?["p_body"] as? String == "[아잉:놀람]", "토큰이 아닌 본문이 나갔다: \(String(describing: body?["p_body"]))")
        #expect(body?["p_to"] as? String == asPeer)
        // ★ 입력칸은 그대로다. 비웠다면 이모티콘 한 장이 사용자가 쓰던 글을 지운 것이다(되돌릴 수 없다).
        #expect(store.messageDraft == "쓰던 글", "이모티콘이 쓰던 글을 지웠다")

        // 대조: **입력칸으로 보낸 글**은 예전처럼 비워진다(비우는 규칙을 같이 죽이지 않았다).
        store.sendDraftMessage()
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "send_message") >= 2 && !store.isSendingMessage
        }
        #expect(store.messageDraft == "", "성공했는데 초안이 남으면 다음 Enter 에 같은 말이 또 나간다")
    }

    // MARK: ⑤ 글자만 들어가는 자리 — 네 자리가 같은 말을 한다

    /// **캐릭터 도착 말풍선**(팝오버가 닫혀 있는 평시에 받는 사람이 보는 **유일한** 도착 신호).
    ///
    /// 변환이 호출부가 아니라 `messageBubbleText` **안**에 있어야 한다 — 호출부에 두면 다음에 생기는
    /// 호출부가 빠뜨린다(0.3.62 초안이 정확히 그렇게 갈렸다: 팝오버 한 줄만 고쳐지고 캐릭터는 날것).
    @Test func 캐릭터_도착_말풍선은_날것_토큰을_말하지_않는다() {
        for sticker in AingSticker.allCases {
            let text = CheckOverlayController.messageBubbleText(name: "민수", body: sticker.token)
            // 이름까지 붙은 **인라인** 갈래여야 한다(알림형이면 "✉️ 민수님 메시지 도착!" 이 되어 내용이 사라진다).
            #expect(text == "민수님: 아잉이 \(sticker.label)", "도착 말풍선이 \"\(text)\" 를 말한다")
            #expect(!text.contains(AingSticker.tokenPrefix), "도착 말풍선에 날것 토큰이 남았다: \(text)")
        }
        // 앞뒤 공백이 섞인 실제 전선 모양도 같다.
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: " [아잉:놀람]\n") == "민수님: 아잉이 놀람")
        // 대조군: 평범한 본문은 **글자 하나도** 바뀌지 않는다(바뀌면 그게 "내 말이 화면에서 달라지는" 버그다).
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: "화이팅") == "민수님: 화이팅")
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: "오늘 고생했어요") == "민수님: 오늘 고생했어요")
        // 빈 본문의 알림 갈래도 그대로다(preview 가 빈 글자를 건드리지 않는다).
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: "") == "✉️ 민수님 메시지 도착!")
    }

    /// **그림을 못 읽는 배포본의 글자 폴백**도 이름으로 읽힌다. 같은 저장소가 날것을 "깨진 메시지로
    /// 읽힌다"고 적어 둔 그 글자다 — 폴백의 목적(상대가 뭘 보냈는지 알게)은 이름이 더 잘 달성한다.
    @Test func 글자_말풍선_폴백도_아잉이_이름으로_읽힌다() throws {
        let view = try asSource("CheckMessageView.swift")
        let bubble = try #require(asRegion(view, from: "private var textBubble: some View {", to: "\n    }"))
        #expect(bubble.contains("Text(AingStickerText.preview(for: entry.body))"),
                "폴백 말풍선이 날것 토큰을 띄운다")
        // 우클릭 [복사]는 **날것 그대로**다(붙여넣어 다시 보내면 그림이 된다).
        #expect(view.contains("CheckPasteboard.copy(entry.body)"), "복사가 날것이 아니라 보기용 글자를 담는다")
    }

    /// **신고 시트의 인용 상자.** 사용자는 그림을 우클릭해 신고하는데, "무엇을 신고하는지 눈으로 확인하는
    /// 자리"에 `[아잉:기쁨]` 이 적히면 자기가 본 것과 다르다.
    ///
    /// 글자가 아니라 **그려진 결과**로 잰다: 토큰을 실은 시트와 "아잉이 기쁨"을 실은 시트가 **같은 그림**이면
    /// 그 상자가 preview 를 지난 것이다. 대조군(다른 글자를 실은 시트)이 달라야 이 단언이 공허하지 않다.
    @Test(.gomokuDefaultsCleanup)
    func 신고_인용_상자는_아잉이_이름으로_보여_준다() throws {
        func sheet(_ body: String) throws -> NSBitmapImageRep {
            let (store, _) = makeMessageReadStore("v0362-report")
            store.openMessagePanel(peer: asPeer)
            store.openReport(
                BlockReportTarget(peerID: asPeer, peerName: "민수", messageID: "m1", messageBody: body),
                surface: .message
            )
            let shown = try #require(store.blockReportSheet(on: .message), "신고 시트가 안 섰다")
            // 서버로 가는 증거는 **날것 그대로**다(운영자가 무엇이 오갔는지 보는 자리 — 여기는 안 건드린다).
            #expect(shown.target.messageBody == body)
            let view = BlockReportSheetView(store: store, sheet: shown)
                .frame(width: MessagePanelLayout.contentWidth)
                .background(CheckTheme.background)
            _ = try asBitmap(view)   // ImageRenderer 는 첫 장을 다르게 굽는다 — 굳힌 뒤 비교한다.
            return try asBitmap(view)
        }
        let token = try sheet("[아잉:기쁨]")
        let name = try sheet("아잉이 기쁨")
        let other = try sheet("[아잉:기쁨.")
        #expect(asDiffCount(token, name) == 0,
                "인용 상자가 토큰을 날것으로 띄운다(이름으로 띄운 판과 \(asDiffCount(token, name))px 다르다)")
        #expect(asDiffCount(other, name) > 0, "인용 상자가 본문을 아예 안 그린다 — 위 단언이 공허하다")
    }

    // MARK: 검토 수리 — 판정 한 자리 · 전송 게이트 · 보이스오버

    /// **그림을 그리는가**의 판정은 하나다. 말풍선 행과 틀 높이 추정이 각자 판정하면(`parse` 만 보는 쪽 ·
    /// `parse && image != nil` 을 보는 쪽) 번들이 깨진 배포본에서 갈린다 — 추정은 그림 한 장(122pt)으로
    /// 세는데 행은 글자 한 줄(25pt)로 접혀, 이모티콘 건수만큼 회색 빈 판이 쌓인다(2026-09-10 의 그 증상).
    @Test func 그림을_그리는가의_판정은_말풍선과_틀_높이_추정이_같은_하나다() throws {
        for sticker in AingSticker.allCases {
            let drawn = try #require(AingStickerArt.drawable(for: sticker.token), "\(sticker) 가 그림 길로 안 간다")
            #expect(drawn.sticker == sticker)
        }
        // 이모티콘이 아닌 본문은 그림이 아니다(평범한 말풍선 길).
        for body in ["[아잉:기쁨.", "[아잉:없는것]", "점심 드셨어요?", ""] {
            #expect(AingStickerArt.drawable(for: body) == nil, "\"\(body)\" 가 그림 길로 갔다")
        }

        let view = try asSource("CheckMessageView.swift")
        let estimate = try #require(asRegion(view, from: "static func conversationContentHeight(", to: "\n    }"))
        #expect(estimate.contains("AingStickerArt.drawable(for: entry.body)"),
                "틀 높이 추정이 말풍선과 다른 판정을 쓴다 — 그림을 못 읽는 배포본에서 회색 빈 판이 쌓인다")
        #expect(!estimate.contains("AingSticker.parse("), "추정이 아직 parse 만 본다(말풍선은 그림까지 본다)")
    }

    /// **열어 둔 그리드에서 고른 이모티콘이 삼켜지지 않는다.** 버튼만 흐려 두면, 펼친 **뒤에** 못 보내는
    /// 상태가 된 경우(글을 보낸 왕복 0.2~1.5초) 칸 여섯 개는 그대로라 누른 것이 조용히 사라진다.
    @Test(.gomokuDefaultsCleanup)
    func 못_보내는_동안_그리드_칸은_흐려지고_고른_것은_삼켜지지_않는다() throws {
        // ① 화면: 같은 높이·같은 칸인데 **보낼 수 있는가**로 그림이 달라진다(게이트가 픽셀까지 간다).
        let available = MessagePanelLayout.conversationHeight
        func grid(_ canSend: Bool) throws -> NSBitmapImageRep {
            let view = AingStickerGridView(
                availableHeight: available, canSend: canSend, onPick: { _ in }, onClose: {}
            )
            .frame(width: MessagePanelLayout.contentWidth, height: available)
            .background(CheckTheme.background)
            _ = try asBitmap(view)
            return try asBitmap(view)
        }
        #expect(asDiffCount(try grid(true), try grid(false)) > 0,
                "못 보내는 상태에서도 칸이 똑같이 보인다 — 버튼만 흐려졌다")

        // ② 스토어: 왕복 중에 고르면 **안 나가고**, 조용하지도 않다.
        let (store, host) = makeMessageReadStore("v0362-gate") { call, _ in
            call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#) : nil
        }
        store.selectedMessagePeerID = asPeer
        store.isSendingMessage = true
        store.messageNotice = WorkTimerStore.messageSentNotice   // 직전 전송의 결과가 그 자리에 남아 있다
        #expect(!store.canSendStickerNow)
        #expect(!store.sendSticker(.surprised), "왕복 중인데 이모티콘이 나갔다고 한다")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 0)
        #expect(store.messageNotice == AingStickerText.sendingNowNotice,
                "고른 이모티콘이 아무 안내 없이 삼켜졌다 — 직전 전송의 \"보냈어요\"만 남는다")
        // 대조: 보낼 수 있으면 참을 돌려준다(그리드는 그때만 접는다).
        store.isSendingMessage = false
        #expect(store.sendSticker(.joy))

        // ③ 뷰: 게이트를 칸까지 내리고, **보냈을 때만** 접는다.
        let view = try asSource("CheckMessageView.swift")
        #expect(view.contains("canSend: store.canSendStickerNow"), "그리드가 전송 게이트를 안 받는다")
        #expect(view.contains("if store.sendSticker(sticker) { stickerGridOpen = false }"),
                "못 보냈는데도 그리드를 접는다 — 눌렀다는 신호만 남고 이모티콘은 안 간다")
        let cell = try #require(asRegion(view, from: "private struct AingStickerGridCell: View {", to: "\n}\n"))
        #expect(cell.contains(".disabled(!canSend)"), "칸이 눌리는 채로 남았다")
    }

    /// **그림만 있는 말풍선이 보이스오버에서 빈 칸이 되지 않는다.**
    ///
    /// 꾸밈용 그림(`Image(decorative:)`)에 건 `.accessibilityLabel` 은 AX 요소가 없어 **버려진다**
    /// (실측은 `asAccessibilityLabels` 주석). 그래서 문구는 그림 안에 굽는다(`labeledImage`).
    @Test func 이모티콘_말풍선은_보이스오버가_읽는다() {
        let labels = asAccessibilityLabels(
            asConversationView(body: "[아잉:기쁨]"),
            width: MessagePanelLayout.contentWidth, height: 150
        )
        #expect(labels.contains("아잉이 기쁨"), "말풍선 그림에 보이스오버 문구가 없다(읽힌 라벨: \(labels))")
        // 대조군: 평범한 글 말풍선에는 그 문구가 없다(프로브가 아무 데서나 긁어 오는 것이 아니다).
        let plain = asAccessibilityLabels(
            asConversationView(body: "[아잉:기쁨."),
            width: MessagePanelLayout.contentWidth, height: 150
        )
        #expect(!plain.contains("아잉이 기쁨"), "평범한 글에서도 그 문구가 읽힌다 — 프로브가 공허하다")
    }

    /// 그리드를 펼치면 **밑에 가려진 대화가 보이스오버에서도 내려간다**(눈에만 가리면, 훑는 사람은 안 보이는
    /// 말풍선 본문·시각·'안 읽음'을 계속 듣고 여섯 칸이 어디서 시작하는지 알 수 없다).
    ///
    /// ★ **소스 substring 으로 재지 않는다**(v0.3.62 검토 지적 ③). `.accessibilityHidden(showsStickerGrid)`
    ///   한 줄이 있는지만 물으면, 그 **같은 한 줄**을 `.overlay{…}` 뒤로 옮겨 그리드까지 보이스오버에서
    ///   지워 버려도(고치려던 것보다 나쁘다) 그대로 초록이다. 그래서 실제 패널의 AX 트리를 읽어
    ///   **무엇이 남고 무엇이 사라졌는가**를 잰다 — 순서가 뒤집히면 여섯 칸이 통째로 사라져 빨개진다.
    ///
    /// 프로브가 대화 자리를 실제로 본다는 대조군이 필요해서, 이력이 **실패한** 화면을 쓴다
    /// (그 자리의 [다시 시도] 버튼이 AX 라벨을 내는 유일하게 확실한 요소다 — 말풍선 글자는 라벨이 없다).
    @Test(.gomokuDefaultsCleanup)
    func 그리드를_펼치면_가려진_대화는_보이스오버에서도_내려간다() throws {
        func labels(gridOpen: Bool) -> [String] {
            let (store, _) = makeMessageReadStore("v0362-ax")
            store.openMessagePanel(peer: asPeer)
            store.messageHistoryFailed = true   // 대화 자리에 [다시 시도] 가 선다(= 덮이는 쪽의 표식)
            return asAccessibilityLabels(
                CheckMessageView(
                    store: store, rendersPlainTextEditor: true, clipsOverflowInsteadOfScroll: true,
                    now: asNow, onBack: {}, pinsStickerGridOpen: gridOpen
                ),
                width: 316, height: 700
            )
        }
        let closed = labels(gridOpen: false)
        let open = labels(gridOpen: true)

        // 대조군: 접혀 있으면 대화 자리와 작성기가 **둘 다** 읽힌다(프로브가 공허하지 않다).
        #expect(closed.contains("다시 시도"), "접힌 화면에서 대화 자리가 안 읽힌다 — 프로브가 그 자리를 못 본다: \(closed)")
        #expect(closed.contains("뒤로") && closed.contains("보내기"), "접힌 화면에서 패널 크롬이 안 읽힌다: \(closed)")
        #expect(!closed.contains(AingStickerText.accessibilityLabel(.joy)), "접혀 있는데 칸이 읽힌다: \(closed)")

        // ① 덮개가 **살아 있다**: 여섯 칸과 닫기가 전부 읽힌다. `.accessibilityHidden` 을 `.overlay` **뒤**로
        //    옮기면 그리드까지 같이 내려가 이 여섯 줄이 통째로 빨개진다.
        for sticker in AingSticker.allCases {
            #expect(open.contains(AingStickerText.accessibilityLabel(sticker)),
                    "펼쳤는데 \(sticker) 칸이 보이스오버에 없다 — 덮개가 자기 자신까지 숨겼다: \(open)")
        }
        #expect(open.contains(AingStickerText.closeGridLabel), "펼친 화면에 닫기가 안 읽힌다: \(open)")

        // ② 덮인 것은 **내려간다**: 가려진 대화 자리도, 그리드 밖 크롬(뒤로·보내기)도 훑기에서 사라진다.
        #expect(!open.contains("다시 시도"), "가려진 대화가 보이스오버에 그대로 남았다: \(open)")
        // `.accessibilityAddTraits(.isModal)` 을 지우면 이 줄이 빨개진다(뮤테이션 실측).
        #expect(!open.contains("뒤로") && !open.contains("보내기"), "훑기가 여섯 칸 밖으로 샌다: \(open)")

        // ③ 위 ②는 `.isModal` 만으로도 참이다(뮤테이션 실측: `.accessibilityHidden` 한 줄을 **지우면**
        //    AX 트리는 그대로다 — 모달이 이미 형제를 쳐낸다). 그래서 그 줄이 **제자리에** 있는지는 따로
        //    못 박는다: 덮개는 `.isModal` 을 모르는 보조기술에도 덮개여야 하고, 자리를 잃으면(= `.overlay`
        //    뒤로 가면) ①이 빨개진다. 영역을 좁혀 **순서**로 재는 이유가 그것이다(파일 전체 substring 이 아니라).
        let source = try asSource("CheckMessageView.swift")
        let region = try #require(asRegion(source, from: "private var conversation: some View {", to: "private func conversationBody("))
        let hidden = try #require(region.range(of: ".accessibilityHidden(showsStickerGrid)"),
                                  "덮개가 밑의 대화를 보이스오버에서 안 내린다")
        let overlay = try #require(region.range(of: ".overlay {"), "그리드를 얹는 자리를 못 찾았다")
        #expect(hidden.lowerBound < overlay.lowerBound,
                "덮개 숨기기가 .overlay 뒤에 붙었다 — 그리드까지 같이 내려간다")
    }

    /// **초안 비우기는 "이 전송이 초안에서 나왔는가"로 가른다**(글자 비교가 아니다).
    ///  · 평범한 글: 왕복 중에 다음 문장을 이어 쳐도 **비워진다** — 남으면 다음 Enter 에 같은 말이 또 나간다.
    ///  · 이모티콘: 초안이 **우연히 그 토큰과 같아도** 안 지운다 — 왕복이 끝난 뒤라 되돌릴 수 없다.
    /// 두 줄이 서로 반대 방향이라, 가르는 기준을 글자 비교로 되돌리면 **둘 중 하나가 반드시** 빨개진다.
    @Test(.gomokuDefaultsCleanup)
    func 초안_비우기는_글자_비교가_아니라_초안_전송인지로_가른다() async {
        let (store, host) = makeMessageReadStore("v0362-draft") { call, _ in
            call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#) : nil
        }
        store.selectedMessagePeerID = asPeer

        // ① 초안 전송 — 왕복(무료 플랜 0.2~1.5초) 중에 다음 문장을 이어 친다(메신저에서 흔한 동작).
        store.messageDraft = "오늘 고생했어요"
        store.sendDraftMessage()
        store.messageDraft = "오늘 고생했어요다"
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "send_message") >= 1 && !store.isSendingMessage
        }
        #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
        #expect(store.messageDraft == "",
                "왕복 중에 한 글자를 더 쳤더니 보낸 말이 입력칸에 남았다 — 지우지 않고 Enter 를 누르면 또 나간다")

        // ② 이모티콘 전송 — 초안이 그 토큰과 **글자까지 같은** 경우.
        store.messageDraft = "[아잉:기쁨]"
        #expect(store.sendSticker(.joy))
        await messageReadWait {
            MessageReadStubProtocol.count(host: host, rpc: "send_message") >= 2 && !store.isSendingMessage
        }
        #expect(store.messageDraft == "[아잉:기쁨]", "이모티콘이 쓰던 글을 지웠다(글자가 같다는 이유로)")
    }
}


// MARK: - 0.3.62 체인지로그 (내용만)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → 0.3.61 → 0.3.62 → …).
// 0.3.63 이 올라가며 그 둘은 `V0363StickerArtTests.swift` 의 `v0363VersionAndChangelog` 로 넘겼다 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다(0.3.62 가 실제로 그렇게 걸렸다).
// 여기는 0.3.62 섹션의 **내용**만 지킨다(이미 배포된 역사라 바뀌면 안 된다).
@Test("CHANGELOG 0.3.62 는 두 줄(사용자 말투) · 0.3.61 보다 위")
func v0362VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.62\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 2, "항목 \(items)")
    #expect(items.contains { $0.contains("이모티콘") }, "이모티콘을 안 알린다: \(items)")
    #expect(items.contains { $0.contains("멈춰") }, "게임이 안 끝나고 멈추는 변화를 안 알린다: \(items)")
    #expect(items.allSatisfy { $0.count <= 40 }, "배너 폭에서 잘릴 만큼 긴 줄이 있다: \(items)")
    // 사용자 문구에 내부 어휘를 쓰지 않는다. `스티커` 도 막는다 — 한국어 화면에서는 **이모티콘** 한 낱말로 간다
    // (두 낱말이 섞이면 같은 물건을 두 이름으로 부르는 화면이 된다).
    for banned in ["스티커", "토큰", "번들", "포커스", "PNG", "서버", "테스트", "CheckCore"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(changelog.range(of: "## 0.3.62")!.lowerBound < changelog.range(of: "## 0.3.61")!.lowerBound,
            "0.3.62 섹션이 0.3.61 보다 아래에 있다")
}
