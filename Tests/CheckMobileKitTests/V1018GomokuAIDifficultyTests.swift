@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 오목 AI 연습 난이도(대표 11-10 "몇수앞까지 계산할지에 제한" · 맥 0.3.82 과 같은 글자 · 쉬움 2 · 보통 6 · 어려움).
@Suite("폰 1.0.18 — 오목 AI 난이도")
struct V1018GomokuAIDifficultyTests {
    @Test("글자: 이름 셋 · 몇 수 앞 · 판 머리 칩 — 맥과 같다")
    func copy() {
        #expect(GomokuAIDifficulty.allCases.map(GomokuPhoneText.aiDifficultyName) == ["쉬움", "보통", "어려움"])
        #expect(GomokuPhoneText.aiDifficultyDepth(.easy) == "2수 앞까지" && GomokuPhoneText.aiDifficultyDepth(.normal) == "6수 앞까지")
        #expect(GomokuPhoneText.aiDifficultyDepth(.hard) == "끝까지 계산")
        #expect(GomokuPhoneText.aiStakeChip(.normal) == "AI 대국 · 보통 · 기록 없음")
        #expect(GomokuPhoneText.aiDifficultyTitle == "난이도 · AI가 몇 수 앞까지 계산할지")
    }

    @Test("배선: 돌 색 시트가 난이도를 고르고(setAIDifficulty) · 판 머리가 그 판의 난이도를 말한다 — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuAIViews.swift").filter { !$0.isWhitespace }
        #expect(sheet.contains("store.setAIDifficulty($0)") && sheet.contains("difficultyPicker"))
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift").filter { !$0.isWhitespace }
        #expect(match.contains("GamesAIMatchLine(difficulty:store.context.gomoku.aiGame?.difficulty??store.context.gomoku.aiDifficulty)"))
        #expect(match.contains("Text(GomokuPhoneText.aiStakeChip(difficulty))"))
    }
}
