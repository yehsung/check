import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 처리방침(docs/privacy.md)을 대국·집중 사실에 맞춘다.
//
// 대표 답(2026-11-03, 원문 · 되묻지 말 것) #d_x57oDD1VwQ1y: "이번 폰 판에 맞추기 (로그아웃 줄은 Windows 때)"
//   (반나절. 폰 출시 날 게시)
// 어긋났던 것(조사 misc · 둘째 질문 배경):
//   · 아잉 큐브 · 아잉 뒤집기 · 길건너 아잉이가 한 줄도 없었다.
//   · 1:1 대국 기록이 '수집하는 데이터'에 없고 계정 삭제 절에만 있었다.
//   · 계정 삭제 때 마감하는 대국이 오목·체스·테트리스뿐이었다(서버 delete_my_account 는 아잉 큐브 · 아잉 뒤집기도 정리한다 —
//     supabase/migrations/20261108200000_reversi.sql:2121 의 마지막 정의).
//   · "사람 목록에 담기는 것은 이 다섯 가지뿐"이 11-03 서버(20261108120500_app_user_directory_focus_mode)가 집중 여부를
//     모든 사용자에게 내리면서 거짓이 됐다.
// '맥 앱도 같이 로그아웃' 줄은 고치지 않는다(10-31 대표 답 "Windows 출시 때 한 번에").
//
// 문서는 아무도 되묻지 않으면 조용히 거짓이 된다(AILimitsMacTests.uploadedColumnsMatchTheTwoPublicDocuments 와 같은 까닭).
// 그래서 글자를 베끼지 않고 **코드 사실을 먼저 읽고**(명부 행이 focus_mode 를 읽는다 · 폰은 focus_mode 를 쓰지 않는다(MobileForbiddenCalls) ·
// 미니게임 목록 · 대국 게임 이름 · 판돈 셋) 그 사실을 처리방침이 말하는지 잰다. 코드 사실이 움직이면 이 시험이 빨개진다.
// 랜딩 /delete-account 의 같은 문장은 landing/lib/delete-account-page.test.ts ②-3 이 처리방침과 나란히 잰다.

@Suite("1.0.17 처리방침 — 대국·집중 사실")
struct V1017PrivacyPolicyFactsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func privacyLines() throws -> [String] {
        let text = try String(contentsOf: root.appendingPathComponent("docs/privacy.md"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// `prefix` 로 시작하는 첫 줄(항목 한 줄).
    static func line(_ lines: [String], prefix: String) throws -> String {
        try #require(lines.first { $0.hasPrefix(prefix) }, "처리방침에 '\(prefix)' 줄이 없다")
    }

    /// `start` 로 시작하는 줄부터 다음 빈 줄 전까지(계정 삭제 절의 한 덩이).
    static func block(_ lines: [String], start: String) throws -> [String] {
        let at = try #require(lines.firstIndex { $0.hasPrefix(start) }, "처리방침에 '\(start)' 덩이가 없다")
        let rest = lines[at...]
        let end = rest.dropFirst().firstIndex { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? rest.endIndex
        return Array(lines[at..<end])
    }

    /// `heading` 머리글 아래 절(다음 `#` 머리글 전까지).
    static func section(_ lines: [String], heading: String) throws -> [String] {
        let at = try #require(lines.firstIndex { $0 == heading }, "처리방침에 '\(heading)' 절이 없다")
        let end = lines[(at + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
        return Array(lines[at..<end])
    }

    /// 대국 게임 화면 이름 — 폰 '한 사람 한 판' 갈래(코어 글자)와 아잉 뒤집기 이름. "1:1 테트리스" 는 처리방침이 "1:1 …" 을
    /// 앞에 한 번만 적으므로 게임 이름만 떼어 본다. 이 목록에 게임이 늘면(새 대국) 처리방침도 함께 고쳐야 빨강이 풀린다.
    static func duelGameNames() -> [String] {
        let busy = ChessPhoneText.BusyGame.allCases.map { $0.gameName.replacingOccurrences(of: "1:1 ", with: "") }
        var names = busy
        if !names.contains(ReversiNoticeText.gameName) { names.append(ReversiNoticeText.gameName) }
        return names
    }

    // MARK: ① 사람 목록 — 여섯 가지(집중 모드 포함)

    @Test("① 명부 행이 focus_mode 를 읽는 한, 처리방침의 사람 목록은 집중 모드를 포함한 '여섯 가지'를 말하고 '다섯 가지'는 사라졌다")
    func directoryListsFocusModeAsSixthItem() throws {
        // 전제: 앱이 서버 명부의 focus_mode 칸을 읽는다(20261108120500 — 11-03 운영 적용).
        let json = #"{"user_id":"u1","display_name":"이름","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul","status_message":null,"focus_mode":true}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(PokeDirectoryRow.self, from: Data(json.utf8))
        #expect(row.focusMode == true, "전제: 명부 행이 focus_mode 를 읽지 않는다 — 이 계약의 전제가 사라졌다")

        let lines = try Self.privacyLines()
        let bullet = try Self.line(lines, prefix: "- 콕 찌르기 대상 목록:")
        for item in ["별명", "아바타", "소속 센터", "지금 근무 중인지", "상태메시지", "집중 모드인지"] {
            #expect(bullet.contains(item), "사람 목록 줄에 '\(item)' 이 없다: \(bullet)")
        }
        #expect(bullet.contains("여섯 가지뿐"), "사람 목록이 담는 것의 수(여섯)를 단정하지 않는다: \(bullet)")
        #expect(!bullet.contains("다섯 가지"), "11-03 부터 거짓인 '다섯 가지' 가 남았다: \(bullet)")

        // 같은 절에 대국 로비·순위표 줄이 있고, 거기서도 집중 모드와 '빼는 설정 없음'을 말한다.
        let everyoneStart = try #require(lines.firstIndex { $0.hasPrefix("**같은 앱을 쓰는 모든 사용자에게 보이는 것**") })
        let everyoneEnd = try #require(lines[everyoneStart...].firstIndex { $0.hasPrefix("**나만 보는 것**") })
        let lobby = try #require(lines[everyoneStart..<everyoneEnd].first { $0.hasPrefix("- 대국 로비와 대국 순위표:") },
                                 "'모든 사용자에게 보이는 것' 절에 대국 로비·순위표 줄이 없다")
        #expect(lobby.contains("집중 모드인지"), "대국 로비가 집중 여부를 싣는다는 말이 없다: \(lobby)")
        #expect(lobby.contains("대국 순위표에서 나를 빼는 설정이 없습니다"), "순위표 비공개 설정이 없다는 사실을 적지 않는다: \(lobby)")
    }

    // MARK: ② 집중 모드 — 받지도 보내지도

    @Test("② 서버가 sender_focused 로 거절하는 한, 처리방침은 집중 모드 항목을 두고 '나도 보낼 수 없다'와 '모두에게 보인다'를 말한다")
    func focusModeItemSaysBothDirectionsAndVisibility() throws {
        // 전제: 보낸 사람 집중 거절(20261108121000)을 앱이 자기 갈래로 읽는다(메시지 · 찌르기).
        let response = try JSONDecoder().decode(PokeSendResponse.self, from: Data(#"{"status":"sender_focused"}"#.utf8))
        #expect(MessageSendOutcome(response: response) == .senderFocused, "전제: 메시지 보낸이 집중 거절을 앱이 모른다")
        #expect(PokeSendOutcome(response: response) == .senderFocused, "전제: 찌르기 보낸이 집중 거절을 앱이 모른다")

        let lines = try Self.privacyLines()
        let focus = try Self.line(lines, prefix: "- 집중 모드(")
        #expect(focus.contains("나도 남에게 콕 찌르기·1:1 메시지를 보낼 수 없습니다"), "보낸 사람 쪽 막힘이 없다: \(focus)")
        #expect(focus.contains("같은 앱을 쓰는 모든 사용자"), "집중 여부가 모두에게 보인다는 말이 없다: \(focus)")
        #expect(focus.contains("확성기"), "집중 중에도 확성기는 나간다는 예외가 없다: \(focus)")
        #expect(focus.contains("맥이 꺼져 있으면"), "맥이 꺼진 채 1단이 끝나면 켜짐으로 남는다는 사실이 없다: \(focus)")

        let pokes = try Self.line(lines, prefix: "- 콕 찌르기 기록(")
        #expect(pokes.contains("받지도 보내지도"), "찌르기 줄이 '받지 않는다'만 말한다: \(pokes)")
        let messages = try Self.line(lines, prefix: "- 1:1 메시지(")
        #expect(messages.contains("내가 집중 모드일 때는 보낼 수 없습니다"), "메시지 줄에 보낸 사람 집중 막힘이 없다: \(messages)")
    }

    @Test("③ 폰이 focus_mode 를 쓰지 않는 한(PATCH 금지 칸), '폰이 하지 않는 것' 절이 집중 모드를 켜고 끄지 않는다고 말한다")
    func phoneSectionSaysPhoneDoesNotToggleFocus() throws {
        #expect(MobileForbiddenCalls.forbiddenProfileColumns.contains("focus_mode"),
                "전제: 폰이 focus_mode 를 쓸 수 있게 됐다 — 대표 답 #d_ldP912RctnTt('안내만, 단추 없음')이 바뀌었으면 처리방침과 함께 고쳐라")
        let lines = try Self.privacyLines()
        let phone = try Self.section(lines, heading: "### 폰이 하지 않는 것").joined(separator: "\n")
        #expect(phone.contains("집중 모드를 켜고 끄지 않습니다"), "폰 절이 집중 모드 단추가 없다는 것을 적지 않는다")
        #expect(phone.contains("폰에서도 1:1 메시지를 보낼 수 없습니다"), "맥에서 켠 집중이 폰 보내기도 막는다는 것을 적지 않는다")
    }

    // MARK: ④ 대국 기록 — 수집 항목

    @Test("④ '수집하는 데이터'에 대국 기록 항목이 있고, 코드의 대국 게임 이름 전부 · 판돈 셋 · 채팅 · 보관 기간 · 관전 · AI 연습을 말한다")
    func duelRecordsAreACollectedItem() throws {
        let stakes = try AppStoreDocContractTests.lobbyStakes()
        #expect(stakes.count == 3, "전제: 로비 판돈이 셋이 아니다: \(stakes)")
        let names = Self.duelGameNames()
        #expect(names.contains(GamesRummyText.title) && names.contains(ReversiNoticeText.gameName), "전제: 게임 이름 목록: \(names)")

        let lines = try Self.privacyLines()
        let duel = try Self.line(lines, prefix: "- 대국 기록(")
        for name in names { #expect(duel.contains(name), "대국 기록 항목에 '\(name)' 이 없다") }
        #expect(duel.contains("\(stakes[0])·\(stakes[1])·\(stakes[2])"), "대국 기록 항목의 판돈 숫자가 로비와 다르다: \(stakes)")
        for fact in ["대국 채팅", "30일", "1일", "관전", "AI 연습"] {
            #expect(duel.contains(fact), "대국 기록 항목에 '\(fact)' 가 없다")
        }
        // 루비 줄의 늘고 주는 사유에 대국이 있다.
        let ruby = try Self.line(lines, prefix: "- 루비 잔량과 재화 기록(")
        #expect(ruby.contains("대국에 루비를 걸면"), "루비 줄의 '줄어든다'에 대국이 없다: \(ruby)")
        #expect(ruby.contains("대국에서 이기거나"), "루비 줄의 '늘어난다'에 대국이 없다: \(ruby)")
    }

    @Test("⑤ 미니게임 항목이 코드의 미니게임 전부(MiniGameKind.allCases)를 이름으로 적는다")
    func miniGameItemNamesEveryKind() throws {
        let lines = try Self.privacyLines()
        let mini = try Self.line(lines, prefix: "- 미니게임 일별 최고기록")
        for kind in MiniGameKind.allCases {
            #expect(mini.contains(kind.title), "미니게임 항목에 '\(kind.title)' 이 없다")
        }
    }

    // MARK: ⑥ 계정 삭제 절

    @Test("⑥ 계정 삭제 절이 대국 게임 전부를 지우고 정리한다고 말한다 — 1:1 은 '진 것으로', 아잉 큐브는 '기권' · 로그아웃 줄은 그대로")
    func deletionSectionCoversEveryGame() throws {
        let lines = try Self.privacyLines()
        let names = Self.duelGameNames()
        let deleted = try Self.block(lines, start: "지워지는 것:").joined(separator: "\n")
        for name in names { #expect(deleted.contains(name), "지워지는 것에 '\(name)' 이 없다") }

        let also = try Self.block(lines, start: "같이 처리되는 것:")
        let duel = try #require(also.first { $0.contains("내가 진 것으로") }, "1:1 진행 중 판 정리 줄이 없다")
        // 여럿이 하는 판(아잉 큐브 · 아잉 마작 — 1.0.18)은 '진 것으로'가 아니라 제 줄이 따로 있다.
        for name in names where name != GamesRummyText.title && name != MahjongNoticeText.gameName {
            #expect(duel.contains(name), "1:1 진행 중 판 정리 줄에 '\(name)' 이 없다: \(duel)")
        }
        #expect(also.contains { $0.contains(MahjongNoticeText.gameName) && $0.contains("자리 비움") && $0.contains("1위") },
                "아잉 마작 진행 중 판 정리(자리 비움 · 몫은 1위) 줄이 없다")
        #expect(also.contains { $0.contains(GamesRummyText.title) && $0.contains("기권") }, "아잉 큐브 진행 중 판 정리(기권) 줄이 없다")
        #expect(also.contains { $0.hasPrefix("- **끝난 대국**") && $0.contains("상대의 전적") },
                "끝난 1:1 판이 함께 지워져 상대 전적에서도 빠진다는 줄이 없다")

        // 10-31 대표 답 "Windows 출시 때 한 번에" — 이번 판은 이 줄을 고치지 않는다(Windows 때 이 기대도 함께 고친다).
        #expect(deleted.contains("되돌릴 수 없고, 맥 앱도 같이 로그아웃됩니다."),
                "'맥 앱도 같이 로그아웃' 줄은 Windows 출시 때 고치기로 했다 — 이번 판에서 바뀌었다")
    }
}
