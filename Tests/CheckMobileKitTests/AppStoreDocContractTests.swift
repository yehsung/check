import CheckCore
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

    // MARK: 1.0.8 — 루트 상자(캐릭터 뽑기)

    @Test("뽑기가 앱에 있는 한 §3 루트 상자는 '예' · 현금 결제 없음 · 확률을 보여 주는 자리(앱 문구 그대로)를 근거 칸이 말한다")
    func lootBoxFollowsGachaFacts() throws {
        // 대조 — 코드 사실: 데모 상점(심사·스크린샷이 보는 화면)이 뽑기를 싣고, 그 확률표가 합 100% 다(= 폰이 뽑기 카드를 세운다).
        let url = Self.root.appendingPathComponent("Sources/CheckMobileKit/Demo/Fixtures/me/_me-shop/rpc.shop_state.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let gacha = try #require(object?["gacha"] as? [String: Any], "데모 상점에 뽑기가 없다 — 이 계약의 전제가 사라졌다")
        let odds = try #require(gacha["odds"] as? [[String: Any]])
        #expect(odds.compactMap { $0["percent"] as? Int }.reduce(0, +) == 100, "데모 확률표 합이 100 이 아니다")
        let price = try #require(gacha["price"] as? Int)

        let doc = try Self.document("docs/appstore.md")
        let survey = try Self.section(of: doc, heading: "## 3. 연령 등급 설문 예상 답")
        let lootBox = try Self.row(in: survey, containing: "루트 상자")
        #expect(lootBox[1].contains("예") && !lootBox[1].contains("아니오"),
                "확률로 캐릭터가 나오는 뽑기가 있는데 루트 상자를 '아니오'로 답한다: \(lootBox[1])")
        #expect(lootBox[1].contains("현금 결제 없음") && lootBox[1].contains("확률 앱 안 공개"), "답 칸: \(lootBox[1])")
        #expect(lootBox[2].contains(GachaText.oddsButton), "근거 칸이 확률을 보여 주는 자리(앱 버튼 '\(GachaText.oddsButton)')를 말하지 않는다")
        #expect(lootBox[2].contains(GachaText.title), "근거 칸이 앱의 뽑기 이름('\(GachaText.title)')을 쓰지 않는다")
        #expect(lootBox[2].contains("\(price) 루비"), "근거 칸의 1회 값이 데모 상점(\(price))과 다르다")
        // 모의 도박 근거 칸도 1.0.8 수수료를 말한다(이긴 쪽이 '두 사람 몫' 전부를 받는다고 쓰면 거짓이다).
        let gambling = try Self.row(in: survey, containing: "모의 도박(Simulated Gambling)")
        let payouts = [3, 5, 10].map { 2 * $0 - DuelFee.fee(stake: $0) }
        #expect(payouts == [5, 9, 18], "전제: 손으로 적은 승자 수령표")
        #expect(gambling[2].contains("수수료 10%") && gambling[2].contains("5/9/18"), "모의 도박 근거가 수수료 뒤 상금을 말하지 않는다")
    }

    // MARK: 1.0.11 — 1:1 테트리스

    @Test("1.0.11: §0.1 게임 탭 줄 · §5.2 New in · §5.3 한글 요약 셋이 다 있고, 숫자가 코드 사실과 맞고, 도박 어휘가 없다")
    func tetrisDuelIsDocumentedWithoutWageringLanguage() throws {
        // 대조 — 코드 사실(이 전제가 사라지면 문서의 결론도 같이 고친다).
        #expect([2, 3, 4].map { TetrisGame.attackLines(lines: $0) } == [1, 2, 4], "전제: 공격 표(D2)")
        #expect(TetrisDuelStake.allCases.map(\.rawValue) == [3, 5, 10], "전제: 판돈 집합")
        #expect(TetrisDuelSession.rampStartSeconds == 120, "전제: 2분 뒤 가속(D7)")

        let doc = try Self.document("docs/appstore.md")

        // ① §0.1 기능 범위 표의 게임 탭 줄 — 심사팀이 "앱에 무엇이 있나" 를 읽는 자리다.
        let scope = try Self.section(of: doc, heading: "### 0.1 실제 기능 범위")
        let games = try Self.row(in: scope, containing: "| 게임 |")
        // 칸 넷: [탭 이름, 화면에 있는 것, 서버에 **쓰는** 것, 근거].
        #expect(games[0] == "게임", "표 모양이 바뀌었다: \(games)")
        #expect(games[1].contains("1:1 테트리스"), "게임 탭 줄이 1:1 테트리스를 말하지 않는다: \(games[1])")
        #expect(games[1].contains("1.0.11"), "어느 버전에 들어왔는지가 없다")
        #expect(games[2].contains("tetris_report"), "서버에 쓰는 것 칸에 판 보고가 없다: \(games[2])")

        // ② §5.2 심사원용 영어 메모 — 1.0.11 블록.
        let notes = try Self.section(of: doc, heading: "### 5.2 노트 본문")
        let start = try #require(notes.range(of: "**New in 1.0.11"), "§5.2 에 New in 1.0.11 블록이 없다")
        let rest = notes[start.lowerBound...]
        let end = rest.range(of: "**Screens that")?.lowerBound ?? rest.endIndex
        let newIn1011 = String(rest[..<end])
        #expect(newIn1011.contains("1:1 테트리스"), "앱 안 이름(한글)을 적어야 심사원이 화면에서 찾는다")
        for number in ["3, 5 or 10", "10%", "2 minutes", "15 seconds"] {
            #expect(newIn1011.contains(number), "§5.2 1.0.11 블록에 \(number) 가 없다")
        }
        // 공격 표가 문서와 엔진에서 같은 숫자여야 한다(2→1 · 3→2 · 4→4).
        #expect(newIn1011.contains("Clearing 2 lines at once drops 1 extra row"), "공격 표 첫 줄이 다르다")
        #expect(newIn1011.contains("3 lines drops 2, and 4 lines drops 4"), "공격 표 둘째·셋째가 다르다")
        // ★ 제출일에 서버 상수를 22 로 내렸다 — 메모는 심사원이 **할 수 있는 것**을 정확히 적는다(기기 둘 · 데모 계정 둘).
        //   "못 한다"로 되돌아가면 거짓이 되므로 옛 문구가 남아 있는지도 같이 본다.
        #expect(newIn1011.contains("Two demo accounts on two devices can play a real match"),
                "메모가 두 계정·두 기기 대결 방법을 안 적는다")
        #expect(!newIn1011.contains("not enabled in this build"), "상수를 내렸는데 메모가 아직 못 한다고 적는다")
        // ★ 도박을 연상시키는 어휘와 제공자 이름을 쓰지 않는다(사용자 지시 · 루비는 앱 안 재화다).
        for word in ["gambl", "wager", "bet ", "betting", "casino", "jackpot", "cash prize",
                     "Supabase", "supabase", "Apple Pay"] {
            #expect(!newIn1011.contains(word), "§5.2 1.0.11 블록에 금지 낱말 '\(word)' 가 있다")
        }

        // ③ §5.3 한글 요약 — 내부 확인용이지만 **제출 전 결정**이 여기 적혀 있어야 한다.
        let korean = try Self.section(of: doc, heading: "### 5.3 노트 한국어 요약")
        let line = try #require(korean.split(separator: "\n").first { $0.contains("1.0.11") },
                                "§5.3 에 1.0.11 요약 줄이 없다")
        #expect(line.contains("1:1 테트리스"))
        #expect(korean.contains("tetris_ios_min_build"), "§5.3 이 폰 능력을 가르는 서버 상수와 그 값을 안 적는다")
        // ★ 둘째 데모 계정은 ASC 칸에만 — 이 문서에 자격증명을 적는 쪽으로 되돌아가지 않게 결정을 박아 둔다.
        #expect(korean.contains("ASC 심사 메모 칸에만"), "§5.3 이 둘째 계정 자격증명을 어디 적는지 안 적는다")
        #expect(korean.contains("판 중에 앱을 나가면 져요"), "§5.3 이 P7 경고 한 줄을 안 적는다")
        // 연령 설문의 답은 **바뀌지 않는다**(판돈·수수료가 오목·체스와 같은 값이다) — 그 결론을 적어야 다음 사람이
        // §3 을 다시 손대지 않는다.
        #expect(korean.contains("바뀌지 않는다"), "§5.3 이 연령 설문이 그대로라는 결론을 안 적는다")
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
