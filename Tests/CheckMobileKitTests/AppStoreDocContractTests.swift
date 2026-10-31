import CheckCore
import CheckMobileShared
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

    /// `ios/project.yml` 의 빌드 설정 한 칸(`MARKETING_VERSION` 같은 정의 줄 — `$(...)` 참조 줄이 아니다).
    /// xcodegen 이 이 두 칸을 Info.plist 의 `CFBundleShortVersionString`·`CFBundleVersion` 으로 그대로 넣는다.
    static func projectSetting(_ key: String) throws -> String {
        let yml = try document("ios/project.yml")
        let line = try #require(yml.split(separator: "\n").first { $0.contains("\(key):") },
                                "ios/project.yml 에 \(key) 정의 줄이 없다")
        let value = line.split(separator: ":", maxSplits: 1).dropFirst().joined()
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
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
        // "1·2·3등에게 루비 N·N·N" 의 **현재형 문장**으로 잰다 — 근거 칸은 지난 값(10·5·3 · 그 전 20·10·5)도 적으므로 숫자 셋만 찾으면
        // 현재형을 옛 값으로 되돌려도 역사 쪽 글자에 걸려 초록이다(2026-10-22 에 상금이 20·10·5 로 돌아오며 생긴 구멍).
        #expect(contests[2].contains("1·2·3등에게 루비 \(prizes[0])·\(prizes[1])·\(prizes[2])"), "근거 칸의 상품 숫자가 코드와 다르다: \(contests[2])")
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
        // 모의 도박 근거 칸은 승자가 실제로 받는 루비를 말한다 — 1.0.8~1.0.12 는 수수료 10% 를 뗀 5/9/18,
        // 2026-10-22(서버 `20261023132000_duel_fee_off.sql`) 부터 수수료 없이 두 사람 몫 전부 6/10/20.
        let gambling = try Self.row(in: survey, containing: "모의 도박(Simulated Gambling)")
        let payouts = [3, 5, 10].map { DuelFee.winnerPayout(stake: $0) }
        #expect(payouts == [6, 10, 20], "전제: 손으로 적은 승자 수령표(수수료 없음)")
        #expect(gambling[2].contains("6/10/20") && gambling[2].contains("수수료 없이"), "모의 도박 근거가 지금 승자 수령을 말하지 않는다: \(gambling[2])")
        // 옛 현재형 문장("두 사람 몫에서 수수료 … 를 뺀")이 남으면 안 된다 — 지난 값은 '그 전' 으로만 적는다.
        #expect(!gambling[2].contains("두 사람 몫에서 수수료"), "모의 도박 근거가 아직 수수료를 지금 사실로 적는다: \(gambling[2])")
    }

    // MARK: 1.0.9 — 미션 절 이름(0.3.64 짝에서 「도전 미션」 → 「누적 미션」)

    /// 메모는 다음 제출로 **승계**된다 — 심사원이 찾아갈 절 이름은 앱 글자 그대로(`MeText.missionsTitle`)여야 한다.
    /// 옛 이름은 역사 괄호("titled 「…」 in 1.0.9–1.0.12")로만 남으므로, 낱말만 찾지 않고 **안내 문장 자리**의 「…」 를 잰다
    /// (낱말만 찾으면 안내가 옛 이름으로 돌아가도 역사 괄호의 새 이름에 걸려 초록이다).
    @Test("1.0.9: §0.1 나 줄 · §5.2 New in 1.0.9 블록 · §5.3 요약이 미션 절을 앱 글자 그대로(MeText.missionsTitle) 부른다")
    func missionSectionIsNamedAsTheAppNamesIt() throws {
        let title = MeText.missionsTitle
        let doc = try Self.document("docs/appstore.md")

        let scope = try Self.section(of: doc, heading: "### 0.1 실제 기능 범위")
        let me = try Self.row(in: scope, containing: "| 나 |")
        #expect(me[1].contains("→ \(title)("), "§0.1 나 줄의 절 순서가 앱의 미션 절 이름(\(title))을 쓰지 않는다")

        let notes = try Self.section(of: doc, heading: "### 5.2 노트 본문")
        let start = try #require(notes.range(of: "**New in 1.0.9"), "§5.2 에 New in 1.0.9 블록이 없다")
        let rest = notes[start.lowerBound...]
        let end = rest.range(of: "**New in 1.0.10")?.lowerBound ?? rest.endIndex
        let newIn109 = String(rest[..<end])
        #expect(newIn109.contains("a new **「\(title)」"), "§5.2 1.0.9 블록이 절을 앱 이름(\(title))으로 소개하지 않는다")
        #expect(newIn109.contains("scroll to 「\(title)」"), "§5.2 1.0.9 블록이 심사원을 화면에 없는 절 이름으로 보낸다")

        let korean = try Self.section(of: doc, heading: "### 5.3 노트 한국어 요약")
        let line = try #require(korean.split(separator: "\n").first { $0.contains("1.0.9 부터 보상은") }, "§5.3 에 1.0.9 받기 요약 줄이 없다")
        #expect(line.contains("나 탭 「\(title)」 절"), "§5.3 1.0.9 요약이 앱의 미션 절 이름(\(title))을 쓰지 않는다: \(line)")
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
        // 승자 수령은 코드(`DuelFee`)에서 읽는다 — 메모는 다음 제출로 **승계**되므로 1.0.11 블록도 지금 값을 말해야 한다
        // (2026-10-22 수수료 0 이전엔 "minus a 10% fee" 였다. 그 문장이 남으면 심사원이 화면과 다른 정산을 읽는다).
        let payouts = TetrisDuelStake.allCases.map { DuelFee.winnerPayout(stake: $0.rawValue) }
        let payoutPhrase = "\(payouts[0]), \(payouts[1]) or \(payouts[2]) rubies"
        for number in ["3, 5 or 10", payoutPhrase, "2 minutes", "15 seconds"] {
            #expect(newIn1011.contains(number), "§5.2 1.0.11 블록에 \(number) 가 없다")
        }
        if DuelFee.percent == 0 {
            #expect(!newIn1011.contains("% fee"), "수수료가 0 인데 §5.2 1.0.11 블록이 아직 수수료를 뗀다고 적는다")
        } else {
            #expect(newIn1011.contains("\(DuelFee.percent)% fee"), "§5.2 1.0.11 블록의 수수료가 코드(\(DuelFee.percent)%)와 다르다")
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

    // MARK: 1.0.12 — 아잉이 이모티콘

    /// 문서가 말하는 **장수·토큰 글자·'통째 일치'·'쓰기 0'** 은 전부 코드에서 읽을 수 있는 사실이다. 그래서 글자만 보지 않고
    /// 먼저 코드에서 읽어 맞춘다 — 토큰 한 글자가 바뀌거나 그림 한 장이 번들에서 빠지면 **심사 메모가 거짓이 되므로**
    /// 그 순간 빨개져야 한다(1.0.11 블록 시험과 같은 수법).
    @Test("1.0.12: §0.1 메시지 줄 · §5.2 New in · §5.3 요약 셋이 다 있고, 여섯 토큰·여섯 장·'통째 일치'·'서버 변경 0' 이 코드 사실과 맞고, 도박 어휘·자격증명이 없다")
    func aingStickersAreDocumentedAsSixBundledPicturesNotUGC() throws {
        // 대조 ① 여섯 종이고 토큰 문자열이 이것들이다(전선 계약 — 문서가 심사원에게 보여 주는 글자 그 자체다).
        let stickers = AingSticker.allCases
        #expect(stickers.count == 6, "전제: 여섯 종")
        #expect(stickers.map(\.token) == ["[아잉:기쁨]", "[아잉:하트]", "[아잉:슬픔]", "[아잉:화남]", "[아잉:졸림]", "[아잉:놀람]"],
                "전제: 여섯 토큰 글자")
        // 대조 ② 그림 여섯 장이 **번들에 실렸다** — 문서의 "앱 번들 안 여섯 장 · 아무것도 내려받지 않는다"의 근거다.
        for sticker in stickers {
            #expect(AingStickerArt.url(sticker) != nil,
                    "\(sticker.resourceName).png 이 번들에 없다 — 문서의 '번들 안 여섯 장'이 거짓이 된다")
        }
        // 대조 ③ 판정은 **통째 일치만**이고, 토큰은 기존 메시지 난간을 그대로 통과한다(= '새 쓰기 0' 의 근거).
        #expect(AingSticker.parse(AingSticker.joy.token) == .joy)
        #expect(AingSticker.parse("[아잉:기쁨] 안녕") == nil, "전제: 뒤에 글자가 붙으면 그냥 텍스트다")
        #expect(AingSticker.parse("ㅋㅋ [아잉:기쁨]") == nil, "전제: 앞에 글자가 붙으면 그냥 텍스트다")
        #expect(MessageBody.validate(AingSticker.joy.token) == .ok(AingSticker.joy.token),
                "토큰이 send_message 의 본문 난간을 그대로 통과해야 '같은 RPC · 서버 변경 0' 이 참이다")

        let doc = try Self.document("docs/appstore.md")

        // ① §0.1 기능 범위 표의 메시지 줄 — 심사팀이 "앱에 무엇이 있나" 를 읽는 자리.
        let scope = try Self.section(of: doc, heading: "### 0.1 실제 기능 범위")
        let messages = try Self.row(in: scope, containing: "| 메시지 |")
        #expect(messages[0] == "메시지", "표 모양이 바뀌었다: \(messages)")
        #expect(messages[1].contains("아잉이 이모티콘"), "메시지 줄이 이모티콘을 말하지 않는다: \(messages[1])")
        #expect(messages[1].contains("1.0.12"), "어느 버전에 들어왔는지가 없다")
        #expect(messages[1].contains("통째로 같을 때만"), "부분 치환이 아니라는 사실이 빠졌다 — 심사 메모의 전제다")
        #expect(messages[2].contains("send_message"), "쓰기 칸이 같은 RPC 를 말하지 않는다: \(messages[2])")
        // 이모티콘 전용 서버 쓰기는 **코드에 없다** — 쓰기 칸에 적으면 그 자체가 거짓이다.
        #expect(!messages[2].lowercased().contains("sticker") && !messages[2].contains("이모티콘 보내기"),
                "이모티콘 전용 서버 쓰기는 없다: \(messages[2])")

        // ② §5.2 심사원용 영어 메모 — 1.0.12 블록.
        let notes = try Self.section(of: doc, heading: "### 5.2 노트 본문")
        let start = try #require(notes.range(of: "**New in 1.0.12"), "§5.2 에 New in 1.0.12 블록이 없다")
        let rest = notes[start.lowerBound...]
        let end = rest.range(of: "**Screens that")?.lowerBound ?? rest.endIndex
        let newIn1012 = String(rest[..<end])
        // 여섯 토큰이 **글자 그대로** 있다(심사원이 화면에서 찾는 글자 · 코드가 바뀌면 여기가 먼저 빨개진다).
        for sticker in stickers {
            #expect(newIn1012.contains(sticker.token), "§5.2 1.0.12 블록에 토큰 \(sticker.token) 이 없다")
        }
        #expect(newIn1012.contains("exactly six (\(stickers.count))"),
                "메모가 말하는 장수가 코드(\(stickers.count))와 어긋난다")
        #expect(newIn1012.contains("only when its whole body is exactly one of six tokens"),
                "'통째로 같을 때만' 이 첫 문장에 없다 — 이게 심사 안전성의 근거다")
        #expect(newIn1012.contains("same `send_message`"), "같은 RPC 로 글자만 간다는 사실이 없다")
        #expect(newIn1012.contains("no server, network or data change"), "서버·전선 변경 0 이 없다")
        #expect(newIn1012.contains("Guideline 1.2") && newIn1012.contains("no upload"),
                "1.2 UGC 와 무관하다는 결론(업로드 경로 없음)이 없다")
        #expect(newIn1012.contains("one device") && newIn1012.contains("cannot message yourself"),
                "한 기기에서 확인하는 길과 '자기 자신에게는 못 보낸다' 는 제약이 없다")
        // ★ 자격증명은 이 문서에 **절대** 적지 않는다(§5.3 결정 그대로) — 실제 값이 흘러드는 쪽을 막는다.
        #expect(!newIn1012.contains("@") && !newIn1012.lowercased().contains("password"),
                "1.0.12 블록에 계정 정보 꼴 글자가 있다 — 둘째 계정은 ASC 심사 메모 칸에만 적는다")
        // ★ 도박 어휘·제공자 이름을 쓰지 않는다(1.0.11 블록 시험과 같은 목록).
        for word in ["gambl", "wager", "bet ", "betting", "casino", "jackpot", "cash prize",
                     "Supabase", "supabase", "Apple Pay"] {
            #expect(!newIn1012.contains(word), "§5.2 1.0.12 블록에 금지 낱말 '\(word)' 가 있다")
        }

        // ③ §5.3 한국어 요약 — 제출 전 결론이 여기 적혀 있어야 다음 사람이 §3·서버를 다시 손대지 않는다.
        let korean = try Self.section(of: doc, heading: "### 5.3 노트 한국어 요약")
        let summaryStart = try #require(korean.range(of: "- 1.0.12 는"), "§5.3 에 1.0.12 요약 줄이 없다")
        let summaryRest = korean[summaryStart.lowerBound...]
        let summaryEnd = summaryRest.range(of: "\n- 1.0.7")?.lowerBound ?? summaryRest.endIndex
        let summary1012 = String(summaryRest[..<summaryEnd])
        #expect(summary1012.contains("아잉이 이모티콘"))
        #expect(summary1012.contains("send_message"), "전선이 그대로라는 사실이 없다")
        for conclusion in ["통째로 같을 때만", "서버 상수 없음", "db push 없음", "연령 설문 그대로",
                           "1.2 UGC 조항과 무관", "ASC 심사 메모 칸에만"] {
            #expect(summary1012.contains(conclusion), "§5.3 1.0.12 요약에 '\(conclusion)' 결론이 없다")
        }
        // 1.0.11 에서 박은 결정(둘째 계정 자격증명은 ASC 칸에만)을 **바꾸지 않았다**.
        #expect(korean.contains("ASC 심사 메모 칸에만"))
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

    // MARK: 1.0.15 — 길건너 아잉이 폰 노출 · 미니게임 역대 순위 [오늘 | 역대]

    /// 이 판의 문서가 말하는 것은 **전부 코드에서 읽을 수 있는 사실**이다: 폰 미니게임이 넷이다 · 게임 이름 ·
    /// 딥링크 꼬리 · 조작 두 줄 · 자정 상품 셋과 정족수 · 가만히 있으면 끝나는 초 · 역대 순위 제목과 그 규칙 한 줄 ·
    /// 「순위」 탭은 오늘 하나다 · 제출 버전. 그래서 글자를 베끼지 않고 **먼저 코드에서 읽어 맞춘다** —
    /// 어느 하나가 움직이면 심사 메모가 거짓이 되므로 그 순간 빨개져야 한다(1.0.11·1.0.12 블록 시험과 같은 수법).
    ///
    /// ⚠️ §5.2 의 1.0.15 블록은 1.0.11·1.0.12 시험이 잘라 보는 구간("**New in 1.0.1x" ~ "**Screens that") **안**에 들어간다 —
    /// 그 두 시험의 금지 낱말 목록(gambl·wager·"bet "·betting·casino·jackpot·cash prize·Supabase·Apple Pay ·
    /// "@" · password · "% fee")이 이 블록에도 그대로 걸린다. 여기서 한 번 더 세는 것은 **블록 하나만** 보고 빨개지게
    /// 하려는 것이다(합쳐 보면 어느 판 블록이 더럽혀졌는지 모른다).
    @Test("1.0.15: §0 버전 칸 · §0.1 게임 줄 · §5.2 New in · §5.3 요약이 코드 사실(phoneCases 넷 · crossy.title · 상품 20·10·5 · allTime.boardTitle)과 맞고, 판돈 없는 혼자 게임이라고 말하고, 도박 어휘·자격증명이 없다")
    func crossyAndAllTimeBoardAreDocumentedAsSinglePlayerWithoutWagering() throws {
        // ── 대조: 이 계약의 전제가 되는 코드 사실(사라지면 문서와 함께 이 시험을 고친다) ──
        // ① 폰 목록에 길건너가 들어왔다 — 문서가 "폰에 있다" 고 말하는 근거 그 자체다.
        #expect(MiniGameKind.phoneCases.contains(.crossy), "전제: 폰 목록에 길건너가 있다(이게 1.0.15 의 몸통이다)")
        #expect(MiniGameKind.crossy.isPhoneSupported, "전제: 한 줄 판정도 같은 답을 준다")
        #expect(MiniGameKind.crossy.title == "길건너 아잉이", "전제: 앱 글자(문서가 이 이름으로 심사원을 보낸다)")
        // ② 혼자 하는 게임 셋과 **같은** 자정 상품이다(새 판돈·새 재화가 없다 = 연령 설문이 그대로인 근거).
        let prizes = GamesMiniGameText.rubyPrizes
        #expect(prizes == [20, 10, 5], "전제: 자정 상품 셋 — 문서의 숫자와 함께 맞춰라: \(prizes)")
        // ③ 역대 순위 글자는 코어 한 벌이다(맥·폰이 같은 말을 한다).
        #expect(MiniGameBoardScope.allTime.boardTitle == "역대 순위", "전제: 역대 순위 제목")
        #expect(RankingsText.miniGameRankTitle == MiniGameBoardScope.today.boardTitle,
                "전제: 「순위」 탭은 오늘 하나다 — 전환은 「게임」 탭에만 붙는다(사용자 결정 2026-10-30)")
        // ④ 가만히 있으면 끝난다 — 심사원이 한 판을 끝내는 길 하나다.
        #expect(CrossyGame.idleLimit == 9, "전제: 멈춰 있으면 끝나는 초")

        let scopeChips = "[\(MiniGameBoardScope.today.label) | \(MiniGameBoardScope.allTime.label)]"
        let deepLink = "\(AingRoute.scheme)://games/\(AingRoute.MiniGame.crossy.rawValue)"
        // 조작 두 줄의 아랫줄이 폰 것이다(`kind.howToPlay` + 줄바꿈 + 폰 조작) — 문서는 그 줄을 그대로 적는다.
        let controlLine = try #require(GamesMiniGameText.howToPlay(.crossy).split(separator: "\n").last.map { String($0) },
                                       "전제: 길건너 시작 카드가 조작 줄을 가진다")
        #expect(controlLine.contains("쓸어서") && controlLine.contains("탭하면"), "전제: 폰 조작 줄이 쓸기·탭 둘을 말한다")

        let doc = try Self.document("docs/appstore.md")

        // ── ⓞ §0 요약표의 버전 칸 — 제출 자료가 **어느 판을 내는지** 틀리면 그 아래 전부가 흔들린다.
        //    값은 손으로 적지 않고 `ios/project.yml` 에서 읽는다(xcodegen 이 Info.plist 에 그대로 넣는 두 칸).
        let marketingVersion = try Self.projectSetting("MARKETING_VERSION")
        let buildNumber = try Self.projectSetting("CURRENT_PROJECT_VERSION")
        let facts = try Self.section(of: doc, heading: "## 0. 앱 사실 요약")
        let versionRow = try Self.row(in: facts, containing: "| 버전 · 빌드 |")
        #expect(versionRow[1] == "`\(marketingVersion)` · `\(buildNumber)`",
                "§0 버전 칸이 ios/project.yml(\(marketingVersion) · \(buildNumber))과 다르다: \(versionRow[1])")

        // ── ① §0.1 기능 범위 표의 게임 줄 — 심사팀이 "앱에 무엇이 있나" 를 읽는 자리.
        let scope = try Self.section(of: doc, heading: "### 0.1 실제 기능 범위")
        let games = try Self.row(in: scope, containing: "| 게임 |")
        #expect(games[0] == "게임", "표 모양이 바뀌었다: \(games)")
        // 미니게임 수를 **낱말로** 잰다 — `phoneCases` 가 늘면 "넷" 이 거짓이 되고 여기가 먼저 빨개진다.
        let countWords = [2: "둘", 3: "셋", 4: "넷", 5: "다섯"]
        let countWord = try #require(countWords[MiniGameKind.phoneCases.count],
                                     "폰 미니게임이 \(MiniGameKind.phoneCases.count) 개다 — 낱말 표를 넓혀라")
        #expect(games[1].contains("미니게임 \(countWord)("),
                "게임 줄이 폰 미니게임 수(\(MiniGameKind.phoneCases.count) = \(countWord))를 말하지 않는다: \(games[1])")
        for kind in MiniGameKind.phoneCases {
            #expect(games[1].contains(kind.title), "게임 줄에 폰 미니게임 '\(kind.title)' 이 없다")
        }
        #expect(games[1].contains("1.0.15"), "길건너·역대가 어느 판에 들어왔는지가 없다")
        // ★ 표 칸 안에는 세로줄(`|`)을 **못 쓴다**: 마크다운이 그 자리에서 칸을 나누고 `row(in:)` 도 같은 글자로 쪼개므로
        //   `[오늘 | 역대]` 를 그대로 적으면 칸이 넷에서 다섯이 되고 **1.0.11 시험이 보는 칸 번호까지 밀린다**
        //   (쓰기 칸이 `tetris_report` 를 잃는다). 그래서 이 줄에서는 칩을 따로 적고, 묶는 것은 **칩 글자**다.
        #expect(games.count == 4, "게임 줄의 칸이 넷이 아니다 — 칸 안에 '|' 를 쓰면 뒤 칸 번호가 다 밀린다: \(games)")
        for chip in MiniGameBoardScope.allCases {
            #expect(games[1].contains("[\(chip.label)]"), "게임 줄에 순위 머리 칩 '[\(chip.label)]' 이 없다: \(games[1])")
        }
        #expect(games[1].contains(MiniGameBoardScope.allTime.boardTitle), "게임 줄이 역대 순위를 앱 제목으로 부르지 않는다")
        // 판돈이 **없는** 게임이라는 사실 — 1:1 셋과 가르는 자리다(§3 모의 도박 칸이 이 사실에 기대고 있다).
        #expect(games[1].contains("판돈이 없다"), "게임 줄이 길건너에 판돈이 없다는 사실을 말하지 않는다: \(games[1])")
        // 서버에 **쓰는** 것 칸: 길건너는 새 쓰기가 없고 역대 순위는 읽기 전용이다. 쓰기로 적으면 그 자체가 거짓이다.
        #expect(games[2].contains("새 쓰기 0"), "쓰기 칸이 1.0.15 에 새 쓰기가 없다는 사실을 말하지 않는다: \(games[2])")
        #expect(games[2].contains("minigame_alltime_board") && games[2].contains("읽기만"),
                "쓰기 칸이 역대 순위가 읽기 전용임을 말하지 않는다: \(games[2])")

        // 「순위」 탭 줄은 **건드리지 않았다** — 거긴 오늘 하나다(전환을 두 곳에 적으면 2.3.1 "설명과 다른 앱" 자리).
        let rankings = try Self.row(in: scope, containing: "| 순위 |")
        #expect(rankings[1].contains("미니게임(\(MiniGameBoardScope.today.label))"),
                "순위 줄이 '미니게임(오늘)' 을 말하지 않는다: \(rankings[1])")
        #expect(!rankings[1].contains(MiniGameBoardScope.allTime.label),
                "순위 탭엔 역대가 없다 — 줄에 적으면 심사원이 그 탭에서 찾다가 못 찾는다: \(rankings[1])")

        // ── ② §5.2 심사원용 영어 메모 — 1.0.15 블록.
        let notes = try Self.section(of: doc, heading: "### 5.2 노트 본문")
        let start = try #require(notes.range(of: "**New in 1.0.15"), "§5.2 에 New in 1.0.15 블록이 없다")
        let rest = notes[start.lowerBound...]
        let end = rest.range(of: "**Screens that")?.lowerBound ?? rest.endIndex
        let newIn1015 = String(rest[..<end])
        // 앱 안 이름(한글)을 적어야 심사원이 화면에서 찾는다.
        #expect(newIn1015.contains(MiniGameKind.crossy.title), "§5.2 1.0.15 블록에 앱 글자 '\(MiniGameKind.crossy.title)' 이 없다")
        // 심사원이 **어떻게 그 화면에 닿는지** — 탭 길과 딥링크 둘.
        #expect(newIn1015.contains("Games tab"), "메모가 심사원을 어느 탭으로 보내는지 안 적는다")
        #expect(newIn1015.contains(deepLink), "메모가 딥링크(\(deepLink))를 안 적는다")
        // 조작은 둘로 갈린다(쓸기 = 그 방향 한 칸 · 탭 = 앞으로 한 칸). 하나만 적으면 쓸기를 모르는 심사원은
        // 뒤·좌·우로 갈 길을 못 찾는다 — 그 금지가 `GamesMiniGameText.howToPlay` 주석에 있다.
        #expect(newIn1015.contains("Swipe") && newIn1015.contains("hops one square forward"),
                "메모가 조작 둘(쓸기·탭)을 안 적는다")
        #expect(newIn1015.contains("stands still for \(Int(CrossyGame.idleLimit)) seconds"),
                "메모가 판이 저절로 끝나는 \(Int(CrossyGame.idleLimit))초를 안 적는다 — 심사원이 한 판을 못 끝낸다")
        // 혼자 하는 게임이고 **아무것도 걸지 않는다** · 상품·정족수는 미니게임 셋과 같은 값이다.
        #expect(newIn1015.contains("played alone") && newIn1015.contains("no entry cost"),
                "§5.2 1.0.15 블록이 판돈 없는 혼자 게임이라는 사실을 안 적는다 — 1:1 셋과 가르는 자리다")
        #expect(newIn1015.contains("\(prizes[0]), \(prizes[1]) and \(prizes[2]) in-app rubies"),
                "§5.2 1.0.15 블록의 자정 상품이 코드(\(prizes))와 다르다")
        #expect(newIn1015.contains("a minimum of \(GamesMiniGameText.prizeQuorum) participants"),
                "정족수(\(GamesMiniGameText.prizeQuorum)명)를 빠뜨렸다")
        // 루비가 현금화 불가이고 앱 안 결제가 없다 — 판마다 되풀이하는 결론(1.0.11 블록과 같은 문장).
        #expect(newIn1015.contains("cannot be bought with money or cashed out"), "루비 환금 불가가 없다")
        #expect(newIn1015.contains("no in-app purchases"), "앱 안 결제 없음이 없다")
        // 역대 순위: 앱 제목 그대로 · 사람마다 한 줄 · 읽기 전용 · 「순위」 탭은 그대로.
        #expect(newIn1015.contains(scopeChips), "§5.2 1.0.15 블록이 전환 칩(\(scopeChips))을 안 적는다")
        #expect(newIn1015.contains(MiniGameBoardScope.allTime.boardTitle),
                "§5.2 1.0.15 블록이 역대 순위를 앱 제목('\(MiniGameBoardScope.allTime.boardTitle)')으로 부르지 않는다")
        #expect(newIn1015.contains("one row per person"), "역대가 사람마다 한 줄이라는 규칙이 없다")
        #expect(newIn1015.contains("read-only"), "역대가 읽기 전용이라는 사실이 없다")
        #expect(newIn1015.contains("unchanged — it still shows today only"),
                "메모가 「순위」 탭은 그대로라고 말하지 않는다 — 심사원이 거기서 역대를 찾는다")
        // 연령 설문 답이 **앞 판과 같다**는 결론.
        #expect(newIn1015.contains("age-rating answers in this submission are")
                && newIn1015.contains("the same as the previous version's"),
                "§5.2 1.0.15 블록이 연령 설문이 그대로라는 결론을 안 적는다(1.0.11 블록과 같은 맺음)")
        // ★ 자격증명은 이 문서에 **절대** 적지 않는다(1.0.11 결정 그대로).
        #expect(!newIn1015.contains("@") && !newIn1015.lowercased().contains("password"),
                "1.0.15 블록에 계정 정보 꼴 글자가 있다 — 자격증명은 ASC 심사 메모 칸에만 적는다")
        // ★ 도박 어휘·제공자 이름을 쓰지 않는다(1.0.11·1.0.12 블록 시험과 같은 목록).
        for word in ["gambl", "wager", "bet ", "betting", "casino", "jackpot", "cash prize",
                     "Supabase", "supabase", "Apple Pay"] {
            #expect(!newIn1015.contains(word), "§5.2 1.0.15 블록에 금지 낱말 '\(word)' 가 있다")
        }

        // ── ③ §5.3 한국어 요약 — 제출 전 결론이 여기 적혀 있어야 다음 사람이 §3·서버·설명문을 다시 손대지 않는다.
        let korean = try Self.section(of: doc, heading: "### 5.3 노트 한국어 요약")
        let summaryStart = try #require(korean.range(of: "- 1.0.15 는"), "§5.3 에 1.0.15 요약 줄이 없다")
        let summaryRest = korean[summaryStart.lowerBound...]
        let summaryEnd = summaryRest.range(of: "\n- 1.0.7")?.lowerBound ?? summaryRest.endIndex
        let summary1015 = String(summaryRest[..<summaryEnd])
        #expect(summary1015.contains(MiniGameKind.crossy.title), "§5.3 1.0.15 요약이 앱 글자를 쓰지 않는다")
        #expect(summary1015.contains(deepLink), "§5.3 1.0.15 요약이 같이 넓힌 딥링크를 안 적는다")
        #expect(summary1015.contains(controlLine), "§5.3 1.0.15 요약의 조작 줄이 앱 글자('\(controlLine)')와 다르다")
        #expect(summary1015.contains("판돈이 없다"), "§5.3 1.0.15 요약이 판돈 없는 혼자 게임이라는 사실을 안 적는다")
        #expect(summary1015.contains("루비 \(prizes[0])·\(prizes[1])·\(prizes[2])"),
                "§5.3 1.0.15 요약의 자정 상품이 코드(\(prizes))와 다르다")
        #expect(summary1015.contains("\(GamesMiniGameText.prizeQuorum)명"), "정족수를 빠뜨렸다")
        // 연령 설문이 **바뀌지 않는다**는 결론(이 판의 핵심 결론 — 없으면 다음 사람이 §3 을 다시 손댄다).
        #expect(summary1015.contains("바뀌지 않는다"), "§5.3 1.0.15 요약이 연령 설문이 그대로라는 결론을 안 적는다")
        // 역대 규칙 한 줄은 **맥 글자 그대로**다(같은 기능이 두 말을 하면 안 된다).
        #expect(summary1015.contains(GamesMiniGameText.allTimeRuleCaption),
                "§5.3 1.0.15 요약의 역대 규칙이 앱 글자('\(GamesMiniGameText.allTimeRuleCaption)')와 다르다")
        #expect(summary1015.contains(RankingsText.miniGameRankTitle) && summary1015.contains("「게임」 탭에만"),
                "§5.3 이 전환이 「게임」 탭에만 붙는다는 결정과 「순위」 탭 글자를 안 적는다")
        // AI 리밋 캡션은 앱 문장의 **일부**여야 한다(문장을 새로 쓰면 화면과 다른 말이 된다).
        let aiSentence = "요금제에 따라 창이 하나만 올 수 있어요."
        #expect(MeText.aiLimitsCaption.contains(aiSentence), "전제: AI 리밋 캡션의 둘째 문장")
        #expect(summary1015.contains(aiSentence), "§5.3 1.0.15 요약이 AI 리밋 캡션에 더한 문장을 안 적는다")
        // 일일 미션 아이콘 한 줄 — 기호도 내부 식별자도 코드에서 읽는다.
        #expect(summary1015.contains("`\(MeText.dailyMissionIcon(game: "rummy"))`"),
                "§5.3 1.0.15 요약의 아잉 큐브 아이콘이 코드(\(MeText.dailyMissionIcon(game: "rummy")))와 다르다")
        #expect(summary1015.contains("`rummy`"), "§5.3 이 내부 식별자가 rummy 라는 사실을 안 적는다")
        for conclusion in ["서버 변경 0", "마이그레이션 0", "새 RPC 0", "ASC 심사 메모 칸에만", "p_client_message_id"] {
            #expect(summary1015.contains(conclusion), "§5.3 1.0.15 요약에 '\(conclusion)' 결론이 없다")
        }
        // ★ 자격증명·도박 어휘 0건(한글 쪽 목록).
        #expect(!summary1015.contains("@") && !summary1015.lowercased().contains("password")
                && !summary1015.contains("비밀번호"),
                "§5.3 1.0.15 요약에 계정 정보 꼴 글자가 있다")
        for word in ["도박", "베팅", "gambl", "bet "] {
            #expect(!summary1015.contains(word), "§5.3 1.0.15 요약에 금지 낱말 '\(word)' 가 있다")
        }
    }
}
