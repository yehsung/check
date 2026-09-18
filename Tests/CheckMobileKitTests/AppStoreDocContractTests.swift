import Foundation
import Testing
@testable import CheckMobileKit

/// w16 제출 자료(`docs/appstore.md`) 검증이 찾은 결함의 수리 계약. 문서는 코드를 인용하므로 **문서의 결론이 코드 사실과
/// 어긋나면 빨개진다** — 애플의 정의 문구 자체는 외부 사실이라 여기서 못 재지만, 그 정의를 적용한 결론은
/// 코드 사실(환금 불가 재화의 판돈이 있다 · 자정 상품이 매일 있다)에서 따라 나오므로 그 **함의**를 묶는다.
///
/// - 모의 도박(Simulated Gambling) = "실제 돈이나 환금 가능한 재화 **없이** 거는 것" → 판돈이 있는 한 '예', 등급 13+ 이상.
/// - 경연(Contests) = "순위·보상을 두고 겨루는 행사"(실물 상품 조건 없음) → 매일 자정 상품이 있는 한 '예·잦음', 13+.
/// 출처: <https://developer.apple.com/help/app-store-connect/reference/age-ratings/> (2026-09-18 원문).
@Suite("w16 제출 자료 계약")
struct AppStoreDocContractTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func document(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// `heading` 으로 시작하는 절 — 다음 `##`/`###` 머리글 전까지.
    static func section(of doc: String, heading: String) throws -> String {
        let start = try #require(doc.range(of: heading), "절을 못 찾았다: \(heading)")
        let rest = doc[start.lowerBound...]
        let bodyStart = rest.firstIndex(of: "\n").map { rest.index(after: $0) } ?? rest.endIndex
        let body = rest[bodyStart...]
        let end = ["\n## ", "\n### "].compactMap { body.range(of: $0)?.lowerBound }.min() ?? body.endIndex
        return String(rest[..<end])
    }

    /// 마크다운 표에서 `needle` 이 든 첫 행의 칸들(양 끝 빈 칸 제거·trim).
    static func row(in section: String, containing needle: String) throws -> [String] {
        let line = try #require(section.split(separator: "\n").first { $0.contains(needle) }, "표 행을 못 찾았다: \(needle)")
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        return Array(cells.dropFirst().dropLast())
    }

    static func lobbyStakes() throws -> [Int] {
        let url = root.appendingPathComponent("Sources/CheckMobileKit/Demo/Fixtures/games/rpc.gomoku_lobby.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(object?["stakes"] as? [Int], "로비 픽스처에 stakes 가 없다")
    }

    // MARK: medium 1 — 연령 설문

    @Test("판돈(환금 불가 루비)이 있는 한 §3 모의 도박은 '예' · 자정 상품이 있는 한 경연은 '예' · 예상 등급은 13+")
    func ageRatingFollowsWageringFacts() throws {
        // 대조 — 코드 사실이 사라지면 이 계약의 전제도 사라진다(그때는 문서와 함께 이 테스트를 고친다).
        let stakes = try Self.lobbyStakes()
        #expect(stakes == [3, 5, 10], "오목 판돈이 바뀌었다 — 문서 §3 의 숫자와 함께 맞춰라: \(stakes)")
        let prizes = GamesMiniGameText.rubyPrizes
        #expect(prizes.count == 3 && prizes.allSatisfy { $0 > 0 }, "자정 상품이 사라졌다 — 경연 답이 달라진다: \(prizes)")

        let doc = try Self.document("docs/appstore.md")
        let survey = try Self.section(of: doc, heading: "## 3. 연령 등급 설문 예상 답")

        let gambling = try Self.row(in: survey, containing: "모의 도박(Simulated Gambling)")
        #expect(gambling[1].contains("예") && !gambling[1].contains("아니오"),
                "환금 불가 재화로 거는 것이 애플의 모의 도박 정의 그 자체다 — '아니오' 로 답하면 심사에서 등급이 정정된다: \(gambling[1])")
        #expect(gambling[1].contains("13+"), "모의 도박 '드묾' 은 13+ 다: \(gambling[1])")
        #expect(gambling[2].contains("\(stakes[0])/\(stakes[1])/\(stakes[2])"), "근거 칸의 판돈 숫자가 픽스처와 다르다: \(gambling[2])")

        let contests = try Self.row(in: survey, containing: "경연(Contests)")
        #expect(contests[1].contains("예") && !contests[1].contains("아니오") && !contests[1].contains("확인 필요"),
                "애플의 경연 정의엔 실물 상품 조건이 없다 — 순위·보상을 두고 겨루면 경연이다: \(contests[1])")
        #expect(contests[1].contains("13+"), "매일 자정 상품은 '잦음' 이라 13+ 다: \(contests[1])")
        #expect(contests[2].contains("\(prizes[0])·\(prizes[1])·\(prizes[2])"), "근거 칸의 상품 숫자가 코드와 다르다: \(contests[2])")
        #expect(contests[2].contains("\(GamesMiniGameText.prizeQuorum)명"), "정족수(\(GamesMiniGameText.prizeQuorum)명)를 빠뜨렸다: \(contests[2])")

        let verdict = try #require(survey.split(separator: "\n").first { $0.hasPrefix("예상 결과 등급") }, "예상 등급 줄이 없다")
        #expect(verdict.contains("**13+**") && !verdict.contains("**4+**"),
                "모의 도박·경연 어느 한쪽만으로도 13+ 인데 4+ 를 예상한다: \(verdict)")
    }

    // MARK: medium 2 — 처리방침의 오목 구멍

    @Test("§2.1 라벨이 오목을 수집 항목으로 신고하면, privacy.md 가 오목 데이터를 서술하거나 §7 위험 5 개정 목록이 그 구멍을 적어야 한다")
    func privacyGapForGomokuIsClosedOrTracked() throws {
        let doc = try Self.document("docs/appstore.md")
        let label = try Self.section(of: doc, heading: "### 2.1 수집함")
        let gomokuRows = label.split(separator: "\n").filter { $0.hasPrefix("|") && $0.contains("오목") }
        #expect(gomokuRows.count >= 2, "대조: 라벨 표가 오목 채팅·게임플레이를 신고하지 않는다 — 이 계약의 전제가 사라졌다")

        // 처리방침이 오목 **데이터**(채팅 본문·대국 기록·판돈)를 서술하는가 — 푸시 문장의 '오목 신청' 한 마디는 서술이 아니다.
        let privacy = try Self.document("docs/privacy.md")
        let described = ["판돈", "대국 채팅", "대국 기록"].contains { privacy.contains($0) }

        let risks = try Self.section(of: doc, heading: "## 7. 남은 위험 목록과 완화책")
        let risk5 = try Self.row(in: risks, containing: "| 5 | **처리방침")
        let tracked = risk5[1].contains("오목") && risk5[4].contains("오목")
            && ["판돈", "채팅"].allSatisfy { risk5[4].contains($0) }
        #expect(described || tracked,
                "라벨은 오목 채팅·판돈을 신고하는데 처리방침엔 항목이 없고(5.1.1(i)) 개정 목록도 그 구멍을 모른다")
    }
}
