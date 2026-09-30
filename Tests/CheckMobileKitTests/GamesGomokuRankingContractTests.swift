// `@testable` 로 받는다 — `GomokuRankEntry`·`GomokuUser` 는 `package` 타입이지만 **멤버와이즈 초기화는 internal** 이라
// 그냥 `import` 로는 세울 수 없다(같은 폴더 `GamesGomokuSpectateWiringTests` 와 같은 길).
@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 오목 **순위 행이 승점만 띄우지 못하게** 막는 못(0.3.41 폰).
//
// ── 왜 이 파일이 따로 있는가 ──
// 사용자가 명시적으로 지시했다: "순위 정렬은 승점(승 − 패)이지만 **행에 승·패·무를 같이 띄워야** 한다. 승점만 보여주면 안 된다."
// 구현은 지키고 있는데(`GamesGomokuRanking.swift` 의 `pointsText` + `recordText`) **그걸 재는 테스트가 한 건도 없었다** —
// 누가 `recordText` 를 떼어내 "승점만" 상태로 되돌려도 폰 스위트가 초록이었다(맥 `V0327GomokuPanelRenderTests` 는 맥 문구만 잰다).
// 금지된 상태로 조용히 되돌아갈 길을 여기서 닫는다.
//
// ── 잴 수 있는 길이 둘뿐이다 ──
// 순위 행 뷰는 `#if os(iOS)` 안이라 **맥 스위트가 컴파일조차 못 한다**(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
// 뷰를 세워 픽셀·문자열을 재는 길은 없다. 그래서 둘로 나눠 잰다:
//   1. **문구 계약**(값) — `GomokuPhoneText` 는 `#if` 밖이라 맥에서 값으로 부를 수 있다. 전적 문장이 세 숫자를 다 싣는지.
//   2. **소스 계약**(글자) — 행 뷰 소스를 읽어 승점과 전적이 **한 칸에 같이** 실리는 것을 잰다.
//
// ── 소스 계약의 관용구 ──
// 주석은 반드시 걷어낸다(`stripComments` · `IntegrationContractTests.code(_:)` 와 같은 하우스 규칙). 안 걷으면 이 파일 머리말처럼
// 설명문에 `recordText` 라고 적어 둔 것만으로 초록이 되고, **설명을 지워야 빨개지는** 거꾸로 된 테스트가 된다.
// 단언은 **부르는 자리**를 잰다 — 한 줄짜리 정확 문자열 일치는 다음 사람이 줄바꿈만 해도 깨진다(이 저장소에서 실제로 그 사고가 있었다:
// `bbcb515`). 그래서 조각 둘(`pointsText` · `recordText`)을 따로 확인하고, '같은 칸'은 **중괄호 짝**으로 판정한다.
@Suite struct GamesGomokuRankingContractTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let rankingPath = "Sources/CheckMobileKit/Games/GamesGomokuRanking.swift"

    // MARK: - 1. 문구 계약(값으로 잰다)

    @Test("전적 문장은 승·패·무 세 숫자를 다 싣는다 · 승점은 부호 있는 짧은 꼴")
    func recordTextCarriesAllThreeNumbers() {
        // ★ 사용자 지시의 알맹이: 세 숫자가 다 있어야 한다. 0 도 지우지 않는다("0무" 를 빼면 무승부가 없는 판과 못 받은 값이 같아진다).
        #expect(GomokuPhoneText.record(wins: 6, losses: 2, draws: 1) == "6승 2패 1무")
        #expect(GomokuPhoneText.record(wins: 0, losses: 0, draws: 0) == "0승 0패 0무")
        // 승점은 부호를 보이게. 음수 기호는 루비 변화와 같은 '−'(U+2212) 이고 0 은 부호가 없다(맥 `GomokuText.signedPoints` 와 같은 꼴).
        #expect(GomokuPhoneText.signedPoints(4) == "+4")
        #expect(GomokuPhoneText.signedPoints(-2) == "−2")
        #expect(GomokuPhoneText.signedPoints(0) == "0")
        #expect(GomokuPhoneText.points(4) == "승점 +4")
        // 대조: 승점 문장과 전적 문장은 **다른 문장**이다. 한쪽이 다른 쪽을 삼키면(예: `record` 가 승점만 내주면) 아래 소스 계약이
        // 초록인 채로 화면이 승점만 말할 수 있다.
        #expect(GomokuPhoneText.points(4) != GomokuPhoneText.record(wins: 6, losses: 2, draws: 1))
    }

    @Test("내 순위 한 줄과 보이스오버 라벨도 승점과 전적을 같이 말한다(승점만 읽히지 않는다)")
    func myRankLineAndAccessibilityCarryRecord() {
        let mine = GomokuMyRank(rank: 12, wins: 6, losses: 2, draws: 1, points: 4)
        #expect(GomokuPhoneText.myRankLine(mine) == "12위 · 승점 +4 · 6승 2패 1무")
        // 0판(순위 밖)이어도 전적은 남는다 — 숫자가 다 0 인 것을 보여 주는 게 "순위 밖" 한 마디보다 정확하다.
        let zero = GomokuMyRank(rank: nil, wins: 0, losses: 0, draws: 0, points: 0)
        #expect(GomokuPhoneText.myRankLine(zero) == "순위 밖 · 0승 0패 0무")

        // 보이스오버는 행을 `children: .ignore` + 조립한 라벨로 읽는다 — 즉 **이 라벨이 전적을 안 실으면 눈이 아닌 사람에게는
        // 승점만 있는 화면**이다. 글자 그대로가 아니라 두 조각이 다 들어 있는지를 본다(문장 순서는 바뀌어도 된다).
        let entry = GomokuRankEntry(
            id: "p-mint", rank: 3,
            user: GomokuUser(id: "p-mint", displayName: "민트별", avatarURL: nil, characterID: nil,
                             isWorking: false, isCapable: true, inMatch: false, center: "서울"),
            wins: 6, losses: 2, draws: 1, points: 4
        )
        let label = GomokuPhoneText.rankRowAccessibility(entry, isMe: false)
        #expect(label.contains(GomokuPhoneText.points(4)), "보이스오버 라벨에 승점이 없다: \(label)")
        #expect(label.contains(GomokuPhoneText.record(wins: 6, losses: 2, draws: 1)), "보이스오버 라벨에 전적이 없다: \(label)")
    }

    // MARK: - 2. 소스 계약(행 뷰를 읽어서 잰다)

    @Test("순위 행은 승점과 전적을 한 칸에 같이 그린다 — 큰 글자 가지와 보통 가지 **둘 다**")
    func rankRowDrawsPointsAndRecordTogetherInBothBranches() throws {
        let code = try Self.code(Self.rankingPath)
        // 대조: 파일·타입 이름이 바뀌면 아래 단언이 통째로 헛돈다(이름이 안 잡히면 `#require` 가 여기서 빨개진다).
        #expect(code.contains("struct GamesGomokuRankingSection: View"), "순위 절 타입 이름이 바뀌었다 — 이 파일의 단언이 헛돈다")

        let row = try #require(Self.block(after: "private struct GamesGomokuRankRow: View", in: code),
                               "순위 행 타입 `GamesGomokuRankRow` 본문을 못 찾았다")
        // 두 조각이 **정의**되어 있고 각자 제 문장을 부른다. 조각 이름만 보면 `recordText` 가 승점을 내주도록 바뀐 것을 놓친다.
        let points = try #require(Self.block(after: "private var pointsText", in: row.body), "`pointsText` 조각이 없다")
        let record = try #require(Self.block(after: "private var recordText", in: row.body), "`recordText` 조각이 없다")
        #expect(points.body.contains("GomokuPhoneText.signedPoints("), "승점 조각이 `signedPoints` 를 안 쓴다")
        #expect(record.body.contains("GomokuPhoneText.record(wins:"), "전적 조각이 `record(wins:losses:draws:)` 를 안 쓴다")

        // 행 본문 = 레이아웃. Dynamic Type 에 따라 가지가 둘이고, **둘 다** 두 조각을 그려야 한다.
        // 한쪽만 재면 나머지 가지에서 전적이 사라진 채 초록이 된다(접근성 글자 크기 쪽은 특히 아무도 안 본다).
        let body = try #require(Self.block(after: "var body: some View", in: row.body), "행 뷰 `body` 를 못 찾았다")
        let big = try #require(Self.block(after: "if typeSize.isAccessibilitySize", in: body.body),
                               "큰 글자 가지(`isAccessibilitySize`)를 못 찾았다")
        let plain = try #require(Self.block(after: "else", in: String(body.body[big.end...])),
                                 "보통 글자 가지(`else`)를 못 찾았다")
        // 기준선이 달라야 한다(저장소 메모) — 두 가지가 같은 글자면 자른 자리가 틀린 것이고, 그러면 아래 단언은 한 가지만 두 번 잰 셈이다.
        #expect(big.body != plain.body, "두 레이아웃 가지가 같은 글자다 — 자른 자리가 틀렸다")

        for (name, branch) in [("큰 글자", big.body), ("보통 글자", plain.body)] {
            // 조각 둘을 **따로** 확인한다(한 줄 정확 일치가 아니라 — 줄바꿈으로 깨지지 않게).
            #expect(branch.contains("pointsText"), "\(name) 가지에 승점이 없다")
            #expect(branch.contains("recordText"), "★ \(name) 가지에 전적이 없다 — 사용자가 금지한 '승점만' 상태다")
            // '같은 칸'은 중괄호 짝으로 판정한다: 승점을 **가장 가까이 감싸는** 통 안에 전적도 있어야 한다.
            // 통 자체는 스택이어야 한다(가로든 세로든) — 승점만 남기고 전적을 다른 화면·시트로 옮기는 길도 이걸로 막힌다.
            let box = try #require(Self.innermostBlock(around: "pointsText", in: branch),
                                   "\(name) 가지에서 승점을 감싸는 통을 못 찾았다")
            #expect(box.body.contains("recordText"),
                    "★ \(name) 가지에서 전적이 승점과 같은 칸에 없다 — 통 안: \(box.body.trimmingCharacters(in: .whitespacesAndNewlines))")
            #expect(box.head.contains("Stack"), "\(name) 가지에서 승점·전적을 담은 통이 스택이 아니다 — 통 머리: \(box.head)")
        }
    }

    @Test("목록 밖 내 순위 줄은 승점·전적을 다 실은 조립 문장 하나를 쓴다(승점만 있는 문장으로 못 바꾼다)")
    func myRankRowUsesTheAssembledLine() throws {
        let code = try Self.code(Self.rankingPath)
        let section = try #require(Self.block(after: "struct GamesGomokuRankingSection: View", in: code),
                                   "순위 절 본문을 못 찾았다")
        let myRank = try #require(Self.block(after: "private var myRankRow", in: section.body), "`myRankRow` 조각이 없다")
        // `myRankLine` 은 위 값 테스트가 "…위 · 승점 +4 · 6승 2패 1무" 로 못 박아 뒀다. 그래서 이 줄이 그 문장을 쓰는 한
        // 전적이 빠질 길이 없다 — 대신 `points(` 만 직접 부르는 식으로 갈아치우면 여기서 빨개진다.
        #expect(myRank.body.contains("GomokuPhoneText.myRankLine("), "내 순위 줄이 조립 문장(`myRankLine`)을 안 쓴다")
        #expect(!myRank.body.contains("GomokuPhoneText.points("), "내 순위 줄이 승점만 직접 그린다 — 전적이 빠질 길이 열렸다")
    }

    // MARK: - 도우미

    /// 주석을 걷어낸 소스(하우스 규칙 — `IntegrationContractTests.code(_:)` 와 같은 길).
    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// `needle` **뒤** 첫 `{` 부터 짝이 맞는 `}` **앞**까지. `end` 는 그 닫는 괄호 다음이라 이어서 `else` 가지를 잘라낼 수 있다.
    /// 문자열 리터럴 안의 중괄호는 세지 않는다 — 이 파일이 읽는 뷰 소스에 그런 리터럴은 없다(있으면 위 `#require` 가 어긋나 빨개진다).
    static func block(after needle: String, in code: String) -> (body: String, end: String.Index)? {
        guard let hit = code.range(of: needle) else { return nil }
        return balanced(from: hit.upperBound, in: code)
    }

    /// `index` 이후 첫 `{` 의 짝을 찾는다.
    private static func balanced(from index: String.Index, in code: String) -> (body: String, end: String.Index)? {
        guard let open = code[index...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 {
                    let after = code.index(after: i)
                    return (String(code[code.index(after: open)..<i]), after)
                }
            }
            i = code.index(after: i)
        }
        return nil
    }

    /// `needle` 을 **가장 가까이 감싸는** 중괄호 블록. `head` 는 여는 괄호 바로 앞 글자들(통의 이름 — `HStack(spacing: 8)` 같은 꼴)이고,
    /// 줄 단위가 아니라 끝 120 글자를 준다 — 여는 괄호를 다음 줄로 내리는 서식 변경만으로 깨지지 않게.
    static func innermostBlock(around needle: String, in code: String) -> (head: String, body: String)? {
        guard let hit = code.range(of: needle) else { return nil }
        var depth = 0
        var i = hit.lowerBound
        var open: String.Index?
        while i > code.startIndex {
            i = code.index(before: i)
            if code[i] == "}" {
                depth += 1
            } else if code[i] == "{" {
                if depth == 0 { open = i; break }
                depth -= 1
            }
        }
        guard let open, let box = balanced(from: open, in: code) else { return nil }
        let head = String(code[code.startIndex..<open].suffix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, box.body)
    }
}
