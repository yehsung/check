@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 오목·체스 '이 기기가 연 판' 장부(2026-11-03 — `GameDeviceLedger`)가 **폰 앱 저장소**에 떨어지는가.
//
// 창(폰은 판 화면)은 판을 연 기기에서만 저절로 열린다. 그 판정 장부가 프로세스 안에만 살면, 판 중에 앱을 다시 켠 폰이
// 자기 판을 못 알아봐 화면이 안 열리고 시계를 흘린다(오목 흑 30초 · 체스 10분). 배선은 `MobileAppModel` 의 두 줄이다 —
// 지우면 컴파일도 코어 시험도 초록이라 여기서 저장소 키로 잰다(테트리스 `GamesTetrisDuelWiringTests` 9절과 같은 꼴).

@MainActor
@Suite(.serialized) struct GamesOneDeviceLedgerWiringTests {

    @Test("오목·체스 장부가 앱 저장소(App Group defaults)에 떨어진다 — 다시 켠 폰의 새 스토어도 같은 판을 자기 판으로 읽는다")
    func ledgersLandInAppStorage() async {
        let harness = GamesHarness(label: "one-device-ledger")
        await harness.signIn()
        let user = GamesHarness.userID
        harness.model.gomoku.noteOwnsMatch("m-gomoku-owned")
        harness.model.chess.noteOwnsMatch("m-chess-owned")

        // `storage.defaults` 는 부를 때마다 새 인스턴스다 — 같은 스위트에 떨어졌는지로 잰다.
        let gomokuKey = harness.model.gomoku.deviceLedger.key(userID: user)
        let chessKey = harness.model.chess.deviceLedger.key(userID: user)
        #expect(gomokuKey != chessKey, "두 게임이 한 키를 나눠 쓴다 — 판 id 는 게임 표마다 따로다")
        #expect(harness.storage.defaults.dictionary(forKey: gomokuKey)?.keys.contains("m-gomoku-owned") == true,
                "오목 장부가 앱 저장소에 안 떨어진다 — 판 중에 다시 켠 폰이 자기 판의 화면을 안 연다")
        #expect(harness.storage.defaults.dictionary(forKey: chessKey)?.keys.contains("m-chess-owned") == true,
                "체스 장부가 앱 저장소에 안 떨어진다")

        // 다시 켠 앱 = 같은 저장소를 읽는 새 스토어.
        var reopened = GameDeviceLedger(game: "gomoku", ttlSeconds: 6 * 3_600)
        reopened.defaults = harness.storage.defaults
        #expect(reopened.owns("m-gomoku-owned", userID: user, now: harness.model.gomoku.clock()))
        #expect(!reopened.owns("m-gomoku-owned", userID: "someone-else", now: harness.model.gomoku.clock()),
                "장부가 사람을 안 가린다 — 계정을 바꾼 폰이 앞 사람의 판을 연다")
        await harness.tearDown()
    }
}
