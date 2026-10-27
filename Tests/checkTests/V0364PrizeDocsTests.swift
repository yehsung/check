import Foundation
import Testing
@testable import check

// v0.3.64 — 자정 상금이 10·5·3 → 20·10·5 로 돌아왔다(사용자 결정 2026-10-22). 코드 · 서버 · 앱스토어 문서는 시험이 지켰는데
// **공개 README 와 경제 계약 문서(`docs/ultra-economy.md`)** 는 아무도 재지 않아 옛 값 10·5·3 을 지금 값으로 적은 채 남았다
// (리베이스 검증이 찾았다). 두 문서의 **현재형 문장**을 맥 짝 상수 `CheckMiniGameWindowView.rubyPrizes` 에 묶는다.
//
// ★ 숫자 셋만 찾지 않는다 — 경제 문서의 상금 줄은 역사(울트라 10 → 20·10·5 → 10·5·3 → 20·10·5)도 같은 칸에 적어서,
//   숫자만 찾으면 현재형을 옛 값으로 되돌려도 역사 쪽 글자에 걸려 초록이다. 굵은 현재형 문장 자리와 서버 상수 칸을 잰다.
@MainActor
@Suite("v0.3.64 상금 문서 — README · 경제 계약이 짝 상수와 같은 값")
struct V0364PrizeDocsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func document(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    static var prizes: [Int] { CheckMiniGameWindowView.rubyPrizes }

    @Test("README 미니게임 절: '게임별 1·2·3등에게 루비 a·b·c개' 가 맥 짝 상수와 같다")
    func readmeStatesCurrentPrizes() throws {
        let p = Self.prizes
        #expect(p.count == 3, "전제: 1·2·3등 세 자리")
        let readme = try Self.document("README.md")
        let sentence = "**게임별 1·2·3등에게 루비 \(p[0])·\(p[1])·\(p[2])개**"
        #expect(readme.contains(sentence), "README 가 지금 상금(\(p))을 말하지 않는다 — 기대 문장: \(sentence)")
        // 현재형 문장은 하나뿐이다 — 옛 값 문장이 같이 남으면 읽는 사람은 어느 쪽이 지금인지 모른다.
        let anyPrizeSentence = try NSRegularExpression(pattern: #"게임별 1·2·3등에게 루비 [0-9]+·[0-9]+·[0-9]+개"#)
        let count = anyPrizeSentence.numberOfMatches(in: readme, range: NSRange(readme.startIndex..., in: readme))
        #expect(count == 1, "README 에 상금 현재형 문장이 \(count)개다(기대 1)")
    }

    @Test("경제 계약 §1 '미니게임 상금' 줄: 굵은 현재형 값과 서버 상수 칸이 맥 짝 상수와 같다")
    func economyContractStatesCurrentPrizes() throws {
        let p = Self.prizes
        let doc = try Self.document("docs/ultra-economy.md")
        let line = try #require(doc.split(separator: "\n").first { $0.hasPrefix("| 미니게임 상금 |") }, "경제 문서에 '미니게임 상금' 줄이 없다")
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        // 칸: ["", 규칙, 값, 서버의 단일 출처, ""]
        try #require(cells.count == 5, "표 모양이 바뀌었다: \(cells.count)칸")
        #expect(cells[2].hasPrefix("게임별 **1·2·3등에게 루비 \(p[0])·\(p[1])·\(p[2])**"),
                "값 칸의 현재형(굵은 글자)이 지금 상금(\(p))이 아니다: \(cells[2].prefix(40))")
        #expect(cells[3].contains("`ruby_prize_amounts()` = `{\(p[0]),\(p[1]),\(p[2])}`"),
                "서버 상수 칸이 지금 상금(\(p))이 아니다: \(cells[3].prefix(60))")
    }
}
