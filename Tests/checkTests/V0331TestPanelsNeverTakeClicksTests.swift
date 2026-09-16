import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 테스트가 띄운 투명 패널이 사용자 클릭을 먹지 않는다 (2026-09-17 실사용 신고)
//
// "평소에도 특정 영역만 클릭이 안 된다", "오목판 한 영역만 안 놓인다". 같은 시각 사용자 화면에 테스트 프로세스
// (`swiftpm-testing-helper`)의 알파 0 · 레벨 3 창이 25개 떠 있었고, 실험 앱 실클릭으로 **ignoresMouseEvents=false 를 명시한
// 알파 0 떠 있는 패널은 클릭을 가로챈다**는 것을 확인했다. 할 일 보드(언제나 false)·캐릭터(몸체 위 false)가 그 모양이다.
// `CheckMousePanel` 은 테스트 실행에서 창 서버 값을 언제나 통과로 두고, 읽기는 의도한 값을 돌려준다.

@MainActor
@Test
func testPanelsKeepTheirIntendedMouseRuleButNeverTakeRealClicks() throws {
    #expect(CheckPanelVisibility.isRunningTests, "전제: 이 프로세스는 테스트 실행이다")

    let overlay = try #require(CheckOverlayController.makePanel(size: NSSize(width: 140, height: 170)) as? CheckMousePanel,
                               "캐릭터 패널이 CheckMousePanel 이 아니다 — 테스트 창이 다시 클릭을 먹는다")
    #expect(overlay.ignoresMouseEvents == true)
    overlay.ignoresMouseEvents = false          // 몸체 위 — 앱은 클릭을 받겠다고 정했다
    #expect(overlay.ignoresMouseEvents == false, "의도한 값이 사라지면 히트-스루 규칙 시험이 아무것도 못 잰다")
    #expect(overlay.windowServerIgnoresMouseEvents == true, "테스트 창이 창 서버에 '클릭 받음'을 내렸다 — 사용자 화면의 그 자리가 막힌다")
    overlay.ignoresMouseEvents = true
    #expect(overlay.ignoresMouseEvents == true)
    #expect(overlay.windowServerIgnoresMouseEvents == true)

    let board = CheckTodoBoardController.makePanel()
    #expect(board.ignoresMouseEvents == false, "할 일 보드는 클릭을 받는 창이다(의도)")
    #expect(board.windowServerIgnoresMouseEvents == true, "테스트가 띄운 할 일 보드가 사용자 클릭을 먹는다")
}
