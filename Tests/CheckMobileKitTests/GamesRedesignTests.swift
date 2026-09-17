@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// w15 게임 탭 재디자인(시안 B 07·08·09): 승리선 · 새 문구 · 소스 계약(번개 없음 · 탭 막대 공용 수단 · 벌새 기호 없음 · 불투명 안내 카드).
@MainActor
@Suite struct GamesRedesignTests {
    private static func board(_ stones: [(String, GomokuColor)]) -> GomokuBoard {
        var board = GomokuBoard()
        for (notation, color) in stones { board[GomokuPoint(notation: notation)!] = color }
        return board
    }

    // MARK: - 승리선

    @Test("승리선: 마지막 수를 지나는 5목의 양 끝 — 가로 · 대각(↗) · 장목은 전체")
    func winLineEnds() throws {
        let row = Self.board([("D8", .white), ("E8", .white), ("F8", .white), ("G8", .white), ("H8", .white), ("C8", .black)])
        let rowEnds = try #require(GomokuPhoneWinLine.ends(board: row, lastMove: GomokuPoint(notation: "F8")))
        #expect(Set([rowEnds.from.notation, rowEnds.to.notation]) == ["D8", "H8"])

        let diagonal = Self.board([("D5", .black), ("E6", .black), ("F7", .black), ("G8", .black), ("H9", .black), ("I8", .white)])
        let diagonalEnds = try #require(GomokuPhoneWinLine.ends(board: diagonal, lastMove: GomokuPoint(notation: "H9")))
        #expect(Set([diagonalEnds.from.notation, diagonalEnds.to.notation]) == ["D5", "H9"])

        let overline = Self.board((0..<6).map { ("\(["A", "B", "C", "D", "E", "F"][$0])1", GomokuColor.white) })
        let overlineEnds = try #require(GomokuPhoneWinLine.ends(board: overline, lastMove: GomokuPoint(notation: "C1")))
        #expect(Set([overlineEnds.from.notation, overlineEnds.to.notation]) == ["A1", "F1"])
    }

    @Test("승리선 없음: 4목 · 빈 마지막 수 · 마지막 수 없음")
    func winLineAbsent() {
        let four = Self.board([("D8", .black), ("E8", .black), ("F8", .black), ("G8", .black)])
        #expect(GomokuPhoneWinLine.ends(board: four, lastMove: GomokuPoint(notation: "G8")) == nil)
        #expect(GomokuPhoneWinLine.ends(board: four, lastMove: GomokuPoint(notation: "A1")) == nil)
        #expect(GomokuPhoneWinLine.ends(board: four, lastMove: nil) == nil)
    }

    // MARK: - 문구

    @Test("흐른 시간을 말로: 35초째 · 1분 35초째 · 1시간 2분째")
    func elapsedPhrase() {
        #expect(GomokuPhoneText.elapsedPhrase(35) == "35초째")
        #expect(GomokuPhoneText.elapsedPhrase(95) == "1분 35초째")
        #expect(GomokuPhoneText.elapsedPhrase(3720) == "1시간 2분째")
        #expect(GomokuPhoneText.elapsedPhrase(-5) == "0초째")
    }

    @Test("상대 행 부제: 대국 중이면 누구와 · 업데이트 필요 · 근무 중/안 함")
    func opponentStatus() {
        let mint = GomokuUser(id: "m", displayName: "민트별", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true)
        let rabbit = GomokuUser(id: "r", displayName: "달토끼", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true)
        let live = GomokuLiveMatch(id: "x", a: mint, b: rabbit, stake: .ten, startedAt: Date(timeIntervalSince1970: 0))
        #expect(GomokuPhoneText.opponentStatus(for: mint, liveMatches: [live]) == "대국 중 · 달토끼와")
        #expect(GomokuPhoneText.opponentStatus(for: rabbit, liveMatches: [live]) == "대국 중 · 민트별과")
        #expect(GomokuPhoneText.opponentStatus(for: mint, liveMatches: []) == "대국 중")
        let old = GomokuUser(id: "o", displayName: "보리차", avatarURL: nil, characterID: nil, isWorking: false, isCapable: false, inMatch: false)
        #expect(GomokuPhoneText.opponentStatus(for: old, liveMatches: []) == GomokuPhoneText.needsUpdate)
        let off = GomokuUser(id: "c", displayName: "초코칩", avatarURL: nil, characterID: nil, isWorking: false, isCapable: true, inMatch: false)
        #expect(GomokuPhoneText.opponentStatus(for: off, liveMatches: []) == "근무 안 함")
        #expect(GomokuPhoneText.livePair(live) == "민트별 · 달토끼")
        #expect(GomokuPhoneText.withParticle("Mint") == "와")
    }

    @Test("허브 '오늘 내 순위' 부제: 1등 · 참여 수 — 모르면 불러오는 중 · 실패 · 빈 순위는 아무도 안 했다")
    func hubRankSubtitle() {
        var board = GamesMiniGameBoard()
        #expect(GamesText.hubRankSubtitle(board: board) == GamesMiniGameText.loadingCaption)
        board.failed = true
        #expect(GamesText.hubRankSubtitle(board: board) == GamesMiniGameText.failedCaption)
        board.failed = false
        board.loaded = true
        #expect(GamesText.hubRankSubtitle(board: board) == "오늘은 아직 아무도 안 했어요")
        board.entries = [
            MiniGameBoardEntry(userID: "a", name: "민트별", avatarURL: nil, bestScore: 962, bestAt: nil, plays: 3),
            MiniGameBoardEntry(userID: "b", name: "구름빵", avatarURL: nil, bestScore: 918, bestAt: nil, plays: 2)
        ]
        #expect(GamesText.hubRankSubtitle(board: board) == "1위 민트별 962점 · 2명 참여")
    }

    @Test("내 차례 꼬리: 미리보기 칸이 있으면 그 칸, 없으면 규칙 한 줄 · 판돈 꼬리 · 남은 초")
    func turnHints() {
        #expect(GomokuPhoneText.myTurnHint(preview: GomokuPoint(notation: "I8")) == "I8 한 번 더 누르면 둬요")
        #expect(GomokuPhoneText.myTurnHint(preview: nil) == GomokuPhoneText.placeHint)
        #expect(GomokuPhoneText.stakeGainSuffix(5) == " · 이기면 +5")
        #expect(GomokuPhoneText.remainingPhrase(41.2) == "42초 남음")
        #expect(GomokuPhoneText.playerSubtitle(color: .white, isWorking: true) == "백 · 근무 중")
        #expect(GomokuPhoneText.myWaitingLine(color: .black) == "흑 · 상대 차례예요")
    }

    // MARK: - 소스 계약

    @Test("게임 탭 소스: 번개 '도전' 없음 · 탭 막대는 공용 수단으로만 · 벌새 기호 없음 · 옛 작은 버튼 스타일 없음")
    func sourceContracts() throws {
        let games = "Sources/CheckMobileKit/Games"
        #expect(try IntegrationContractTests.files(containing: ["\"bolt.fill\""], under: games).isEmpty, "번개는 울트라 전용이다")
        #expect(try IntegrationContractTests.files(containing: ["toolbar(.hidden, for: .tabBar)"], under: games).isEmpty,
                "탭 막대 숨김은 공용 hidesTabBar(for:) 로")
        #expect(try IntegrationContractTests.files(containing: ["MiniGameKind.flappy.icon", "bird.fill"], under: games).isEmpty,
                "플래피는 실제 아잉 옆모습(벌새 기호 금지)")
        #expect(try IntegrationContractTests.files(containing: ["GamesCompactButtonStyle"], under: games).isEmpty)

        let match = try IntegrationContractTests.code("\(games)/GamesGomokuMatch.swift")
        #expect(match.components(separatedBy: "hidesTabBar(for: .gomokuMatch)").count == 3, "대국·결과 둘 다 탭 막대를 숨긴다")
        #expect(match.contains("CharacterPortrait("), "플레이어는 캐릭터 초상")
        #expect(match.contains("GamesGomokuChatDrawer("), "대화는 판과 함께 보이는 서랍")
        let screen = try IntegrationContractTests.code("\(games)/GamesMiniGameScreen.swift")
        #expect(screen.contains("hidesTabBar(for: .miniGamePlay)"))
        let kit = try IntegrationContractTests.code("\(games)/GamesCanvasKit.swift")
        #expect(kit.contains(".fill(CheckTheme.panelElevated)") && !kit.contains("panelElevated.opacity("), "안내 카드는 불투명")
        let sheets = try IntegrationContractTests.code("\(games)/GamesGomokuSheets.swift")
        #expect(sheets.components(separatedBy: "SheetHeader(").count == 3, "판돈·규칙 시트 머리는 공용 SheetHeader")
        #expect(!sheets.contains("GomokuPhoneText.cancel"), "판돈 시트에 닫는 길은 ✕ 하나")
    }
}
