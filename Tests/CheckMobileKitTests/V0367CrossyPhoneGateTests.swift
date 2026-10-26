@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// v0.3.67 — 미니게임 넷째 "길건너 아잉이"(`crossy`)는 **맥 먼저**다(사용자 결정 2026-10-27 · 설계서 §0 · §3.3).
// 폰은 다음 판이라 이번에는 **보이지 않게 막기만** 한다. 막는 자리는 한 곳(`MiniGameKind.phoneCases` · `isPhoneSupported`)이고,
// 폰 허브 · 게임 탭 · 순위 칩 · 허브 요약이 전부 그 목록을 돈다(V0338 소스 계약이 그 자리를 잰다).
//
// 일일 미션 일곱 번째 줄("길건너 아잉이 한 판 하기")은 폰에도 **보인다** — 사용자 결정 "모두에게 보이기"(설계서 §2).
// 그 줄의 아이콘이 기본 별로 떨어지지 않는지(코어 `MiniGameKind.icon` 을 그대로 쓰는지)를 여기서 잰다.
// 폰 뷰(`#if os(iOS)`)의 망라 switch 는 macOS 스위트가 컴파일조차 못 한다 — `ios/scripts/build-sim.sh` 가 유일한 그물이다.

@MainActor
@Suite struct V0367CrossyPhoneGateTests {
    @Test("한 곳의 게이트: 폰 목록에 길건너가 없다 · isPhoneSupported 거짓 · 앞 셋은 그대로 보인다")
    func crossyIsHiddenOnThePhone() {
        #expect(MiniGameKind.allCases.contains(.crossy), "전제: 코어는 길건너를 안다(저장값 · 서버 응답 매핑용)")
        #expect(!MiniGameKind.phoneCases.contains(.crossy), "폰 목록에 길건너가 들어왔다 — 폰 화면 · 조작이 아직 없다")
        #expect(!MiniGameKind.crossy.isPhoneSupported)
        #expect(MiniGameKind.phoneCases == [.timingBar, .flappy, .tetris], "앞 셋의 폰 노출이 흔들렸다")
        #expect(MiniGameKind.phoneCases.allSatisfy { $0.isPhoneSupported })
    }

    @Test("딥링크도 안 넓혔다 — games/crossy 는 미니게임으로 안 풀린다(목록과 딥링크는 같이 넓힌다)")
    func deepLinkIsNotWidened() {
        #expect(AingRoute.MiniGame.allCases.map(\.rawValue) == ["timing", "flappy", "tetris"])
        #expect(AingRoute.MiniGame(rawValue: "crossy") == nil)
    }

    @Test("일일 미션 줄 아이콘: crossy → figure.walk(맥 종류 칩과 같은 기호) — 모르는 게임의 별로 떨어지지 않는다")
    func dailyMissionIconIsTheGameIcon() {
        #expect(MeText.dailyMissionIcon(game: "crossy") == "figure.walk")
        #expect(MeText.dailyMissionIcon(game: "crossy") != MeText.dailyMissionIcon(game: "no_such_game"))
    }

    @Test("망라 switch 의 crossy 갈래(폰 구동기 · 문구)는 판 없음으로 답한다 — 만들어지지 않는 길이라도 안전하다")
    func exhaustiveBranchesAreInert() {
        let controller = GamesPlayController(kind: .crossy, seed: 1)
        #expect(!controller.isPlaying && controller.score == 0)
        controller.tap()
        controller.tick(at: MobileClock.demoInstant)
        #expect(!controller.isPlaying, "폰 구동기가 길건너 판을 열었다")
        #expect(!controller.abandon())
        #expect(controller.endRound() == .none)
        #expect(!GamesMiniGameText.endedInBackground(.crossy).isEmpty)
        #expect(GamesMiniGameText.howToPlay(.crossy) == MiniGameKind.crossy.howToPlay)
        #expect(GamesMiniGameText.canvasAccessibility(.crossy).contains(MiniGameKind.crossy.title))
    }
}
