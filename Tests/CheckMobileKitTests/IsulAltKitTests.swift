import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 이슬 아잉이 대체 그림 꾸러미(`docs/plan/isul-alt/`)가 반려 당일에 그대로 쓸 수 있는 상태인지 잰다.
//
// 대표 답(원문, 2026-11-03 — 되묻지 말 것): #d_dk4IjWRZvFYR "그대로 + 대체 그림 미리 준비"(맥과 같은 그림. 5.2.1로 반려되면 되묻지 않고
// 대체 그림으로 바꿔 그날 다시 제출(지연 1~2일)).
//
// 꾸러미는 처음에 저장소 밖 작업 폴더에만 있었다(검토 지적 — 작업 폴더는 정리 때 통째로 지워진 이력이 있다). 저장소로 옮기면서 이 시험이
// 두 상태를 다 잰다:
//  · 바꿔 끼우기 **전**(지금): 대체 초상 두 장의 모양(알파) = 폰 초상 · 색은 다르다(대체 그림이 맞다) · 두 패치의 빼는 줄이 지금 파일에 그대로 있다
//    (패치가 붙는다 — 카드가 다시 구워지면 여기서 빨개져 꾸러미를 새로 구우라고 알린다) · 카드 base64 = 카드 HEIC = 146×150.
//  · 바꿔 끼운 **뒤**: 초상 둘 · 카드 한 줄 · 시험 패치가 **모두** 들어왔다(반쪽 교체 — 초상만 바꾸고 카드는 상표 그림 — 를 막는다).
//    카드를 맥 그림에서 다시 구운 판(검토 지적 — 그 전의 굽기 원천)도 여기서 빨개진다.

@MainActor
@Suite("IsulAltKit")
struct IsulAltKitTests {
    static let kit = "docs/plan/isul-alt"
    static let isul = CharacterCatalog.isulAingID

    static func url(_ relative: String) -> URL {
        BaseComponentTests.root.appendingPathComponent(relative)
    }

    static func text(_ relative: String) throws -> String {
        try String(contentsOf: url(relative), encoding: .utf8)
    }

    /// 패치의 빼는 줄(`-`)과 더하는 줄(`+`) — 머리(`---`/`+++`)는 뺀다.
    static func patchLines(_ relative: String) throws -> (removed: [String], added: [String]) {
        let lines = try text(relative).components(separatedBy: "\n")
        let removed = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.map { String($0.dropFirst()) }
        let added = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.map { String($0.dropFirst()) }
        return (removed, added)
    }

    static func lines(of relative: String) throws -> Set<String> {
        Set(try text(relative).components(separatedBy: "\n"))
    }

    static func alpha(_ pixels: [UInt8]) -> [UInt8] {
        stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    static func shippedPortrait(_ expression: AingCharacterArt.Expression) throws -> URL {
        try #require(AingCharacterArt.portraitURL(id: isul, expression: expression), "이슬 \(expression) 초상이 번들에 없다")
    }

    static func kitPortrait(_ expression: AingCharacterArt.Expression) -> URL {
        url("\(kit)/\(isul)-\(expression.rawValue).png")
    }

    /// 바꿔 끼운 판인가 — 번들 무표정 초상이 꾸러미 것과 픽셀까지 같으면.
    static func isSwapped() throws -> Bool {
        try BaseComponentTests.pixels(shippedPortrait(.neutral)) == BaseComponentTests.pixels(kitPortrait(.neutral))
    }

    @Test("꾸러미 파일이 저장소 안에 다 있다 — 초상 둘 · 카드 HEIC 와 base64 · 패치 둘 · 예비 스크립트 · 절차서")
    func kitFilesAreInTheRepository() throws {
        for name in ["aing_isul-neutral.png", "aing_isul-negative.png", "card-aing_isul.heic", "card-aing_isul.heic.base64.txt",
                     "MeCharacterCardData-alt.patch", "BaseComponentTests-alt.patch", "swap-card.py", "README.md"] {
            #expect(FileManager.default.fileExists(atPath: Self.url("\(Self.kit)/\(name)").path), "\(Self.kit)/\(name) 가 없다 — 반려 당일 다시 구워야 한다")
        }
        let readme = try Self.text("\(Self.kit)/README.md")
        #expect(readme.contains("#d_dk4IjWRZvFYR") && readme.contains("A=docs/plan/isul-alt"), "절차서가 저장소 안 경로를 안 가리킨다")
        #expect(readme.contains("git apply \"$A/MeCharacterCardData-alt.patch\"") && readme.contains("git apply \"$A/BaseComponentTests-alt.patch\""))
        #expect(!readme.contains("참" + "이슬"), "절차서에 상표 글자가 있다")
    }

    @Test("대체 그림: 모양(알파)은 폰 초상과 같고 색은 다르다 — 아바타 틀 · 카드 조인 상자가 그대로인 근거 · 바꿔 끼운 판이면 둘 다 들어왔다")
    func altPortraitsKeepShapeAndDifferInColor() throws {
        let swapped = try Self.isSwapped()
        for expression in AingCharacterArt.Expression.allCases {
            let kit = try BaseComponentTests.pixels(Self.kitPortrait(expression))
            let shipped = try BaseComponentTests.pixels(Self.shippedPortrait(expression))
            #expect(kit.count == shipped.count, "\(expression) 크기가 다르다")
            #expect(Self.alpha(kit) == Self.alpha(shipped), "\(expression) 대체 그림의 모양(알파)이 폰 초상과 다르다 — 틀 · 카드 상자가 흔들린다")
            if swapped {
                #expect(kit == shipped, "바꿔 끼운 판인데 \(expression) 초상이 대체 그림이 아니다(반쪽 교체)")
            } else {
                #expect(kit != shipped, "\(expression) 대체 그림이 지금 그림과 같다 — 상표를 뺀 그림이 아니다")
                // 지금 판의 폰 초상 = 맥 원본(상표 그림)이다 — 대체 그림은 그것과 달라야 한다.
                let mac = try BaseComponentTests.pixels(Self.url("Sources/check/Resources/\(Self.isul)-\(expression.rawValue).png"))
                #expect(kit != mac && Self.alpha(kit) == Self.alpha(mac))
            }
        }
    }

    @Test("카드: 꾸러미 base64 = 꾸러미 HEIC · 크기가 박힌 이슬 카드와 같다 · 카드 패치가 지금 카드 표에 붙는다(바꿔 끼운 판이면 대체 카드가 박혔다)")
    func cardPatchMatchesTheCardTable() throws {
        let base64 = try Self.text("\(Self.kit)/card-aing_isul.heic.base64.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let heic = try Data(contentsOf: Self.url("\(Self.kit)/card-aing_isul.heic"))
        #expect(Data(base64Encoded: base64) == heic, "카드 base64 와 HEIC 가 서로 다르다")
        let source = try #require(CGImageSourceCreateWithData(heic as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let card = try #require(MeCharacterCards.card(id: Self.isul))
        #expect(image.width == card.pixelWidth && image.height == card.pixelHeight, "대체 카드 크기가 박힌 이슬 카드와 다르다")

        let patch = try Self.patchLines("\(Self.kit)/MeCharacterCardData-alt.patch")
        try #require(patch.removed.count == 1 && patch.added.count == 1, "카드 패치가 이슬 한 줄만 바꾸지 않는다")
        #expect(patch.added[0].contains("heicBase64: \"\(base64)\""), "카드 패치가 꾸러미 카드를 넣지 않는다")
        let table = try Self.lines(of: "Sources/CheckMobileKit/Me/MeCharacterCardData.swift")
        if try Self.isSwapped() {
            #expect(card.heicBase64 == base64, "바꿔 끼운 판인데 이슬 카드가 대체 카드가 아니다 — 초상만 바뀌고 카드는 상표 그림이다(맥 그림에서 다시 구웠나)")
            #expect(table.contains(patch.added[0]))
        } else {
            #expect(table.contains(patch.removed[0]),
                    "카드 패치의 빼는 줄이 카드 표에 없다 — 카드가 다시 구워졌다. 반려 당일엔 swap-card.py 로 바꾸고, 지금 꾸러미 패치를 새로 만들어 둬라")
            #expect(card.heicBase64 != base64, "지금 판인데 이슬 카드가 이미 대체 카드다")
        }
    }

    @Test("시험 패치: 폰 초상 = 맥 원본 대조의 그 줄이 지금 파일에 그대로 있다(붙는다) · 바꿔 끼운 판이면 이슬 갈래가 들어왔다")
    func testPatchStillApplies() throws {
        let patch = try Self.patchLines("\(Self.kit)/BaseComponentTests-alt.patch")
        try #require(patch.removed.count == 1, "시험 패치의 빼는 줄이 하나가 아니다")
        let lines = try Self.lines(of: "Tests/CheckMobileKitTests/BaseComponentTests.swift")
        if try Self.isSwapped() {
            for added in patch.added where !added.trimmingCharacters(in: .whitespaces).isEmpty {
                #expect(lines.contains(added), "바꿔 끼운 판인데 시험 패치 줄이 없다: \(added)")
            }
        } else {
            #expect(lines.contains(patch.removed[0]), "시험 패치의 빼는 줄이 BaseComponentTests 에 없다 — 패치가 안 붙는다(README 의 손으로 옮기는 길)")
        }
        #expect(patch.added.contains { $0.contains("CharacterCatalog.isulAingID") }, "시험 패치가 이슬만 가르지 않는다")
    }
}
