import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 '이 기기가 연 판' 장부 단위 시험 — 가지 `fix/game-window-one-device`(62ecdf73 · 6e95a55a)의 `GameDeviceLedgerTests` 를
// `GameDeviceLedger(game: "reversi")` 로 옮긴 꼴. 사용자별 키 · 기한 · 상한 · 지우기 · 앱 defaults. 판정이 섞이면 놀던 기기가 창을
// 열거나(남는 기록) 판을 연 기기가 창을 못 연다(사라진 기록). 스토어 쪽 동작은 `ReversiWindowOneDeviceTests` 가 잰다.
private typealias RVLedgerUnderTest = GameDeviceLedger

@Suite("아잉 뒤집기 — 이 기기가 연 판 장부(GameDeviceLedger)")
struct ReversiDeviceLedgerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("적은 판만 연 판이다 · 사람마다 따로 · 로그인 전은 언제나 아니다 · 대소문자 무관")
    func ownershipIsPerUserAndCaseInsensitive() {
        var ledger = RVLedgerUnderTest(game: "reversi", ttlSeconds: 3_600)
        ledger.note("ABC-1", userID: "U1", now: t0)
        #expect(ledger.owns("abc-1", userID: "u1", now: t0))
        #expect(!ledger.owns("abc-2", userID: "u1", now: t0))
        #expect(!ledger.owns("abc-1", userID: "u2", now: t0), "다른 사람의 판을 자기 판으로 읽었다")
        #expect(!ledger.owns("abc-1", userID: nil, now: t0))
        ledger.note("x", userID: nil, now: t0)          // 로그인 전에는 적지 않는다
        #expect(!ledger.owns("x", userID: "u1", now: t0))
        ledger.note("", userID: "u1", now: t0)          // 빈 판 id 는 적지 않는다
        #expect(!ledger.owns("", userID: "u1", now: t0))
    }

    @Test("기한이 지나면 연 판이 아니다 · 처음 시각을 지킨다(다시 적어도 기한이 늘지 않는다)")
    func recordsExpire() {
        var ledger = RVLedgerUnderTest(game: "reversi", ttlSeconds: 100)
        ledger.note("m", userID: "u", now: t0)
        ledger.note("m", userID: "u", now: t0.addingTimeInterval(90))
        #expect(ledger.owns("m", userID: "u", now: t0.addingTimeInterval(100)))
        #expect(!ledger.owns("m", userID: "u", now: t0.addingTimeInterval(101)), "기한이 지난 기록이 살아 있다")
    }

    @Test("상한을 넘으면 오래된 것부터 버린다 · drop 은 그 판만 지운다 · defaults 에 쓰고 비면 키를 지운다", .gomokuDefaultsCleanup)
    @MainActor
    func limitDropAndDefaults() throws {
        let defaults = GomokuTestDefaults.make("rv-ledger")
        var ledger = RVLedgerUnderTest(game: "reversi", ttlSeconds: 3_600, limit: 2)
        ledger.defaults = defaults
        ledger.note("a", userID: "u", now: t0)
        ledger.note("b", userID: "u", now: t0.addingTimeInterval(1))
        ledger.note("c", userID: "u", now: t0.addingTimeInterval(2))
        let now = t0.addingTimeInterval(3)
        #expect(!ledger.owns("a", userID: "u", now: now) && ledger.owns("b", userID: "u", now: now)
                && ledger.owns("c", userID: "u", now: now))
        #expect(Set((defaults.dictionary(forKey: ledger.key(userID: "u")) ?? [:]).keys) == ["b", "c"])

        ledger.drop("b", userID: "u", now: now)
        #expect(!ledger.owns("b", userID: "u", now: now) && ledger.owns("c", userID: "u", now: now))
        ledger.drop("c", userID: "u", now: now)
        #expect(defaults.object(forKey: ledger.key(userID: "u")) == nil, "빈 장부의 키가 남았다")

        // 다른 값(다시 켠 앱)이 같은 defaults 를 읽는다.
        ledger.note("d", userID: "u", now: now)
        var reopened = RVLedgerUnderTest(game: "reversi", ttlSeconds: 3_600)
        reopened.defaults = defaults
        #expect(reopened.owns("d", userID: "u", now: now))
        var otherGame = RVLedgerUnderTest(game: "gomoku", ttlSeconds: 3_600)
        otherGame.defaults = defaults
        #expect(!otherGame.owns("d", userID: "u", now: now), "게임끼리 장부가 섞였다")
    }

    @Test("저장 키 · 값 모양이 GameDeviceLedger 와 같다 — 합칠 때 타입만 바꿔도 앱 defaults 에 적힌 기록을 그대로 읽는다", .gomokuDefaultsCleanup)
    @MainActor
    func storageShapeMatchesTheSharedLedger() throws {
        // 없으면: 다리가 키 접두나 값 모양을 조금만 달리 적어도(예: "reversi.owned.<id>" · 밀리초 값) 다리끼리는 초록이고,
        // `GameDeviceLedger` 로 바꿔 끼운 날 판 중이던 기기가 자기 판을 못 알아봐 창이 안 뜬다.
        let defaults = GomokuTestDefaults.make("rv-ledger-shape")
        var ledger = RVLedgerUnderTest(game: "reversi", ttlSeconds: 6 * 3_600)
        ledger.defaults = defaults
        #expect(ledger.key(userID: "AbC-User") == "reversi.ownedMatches.abc-user")
        #expect(ledger.game == "reversi" && ledger.ttlSeconds == 21_600 && ledger.limit == 8)
        ledger.note("M-ONE", userID: "AbC-User", now: t0)
        let stored = try #require(defaults.dictionary(forKey: "reversi.ownedMatches.abc-user") as? [String: Double])
        #expect(stored == ["m-one": t0.timeIntervalSince1970], "값 모양이 [판 id 소문자: epoch 초] 가 아니다: \(stored)")

        // 그 키에 바깥(그 가지의 장부 · 이전 실행)이 적은 기록도 자기 기록으로 읽는다.
        defaults.set(["m-two": t0.timeIntervalSince1970 + 5], forKey: "reversi.ownedMatches.abc-user")
        #expect(ledger.owns("M-TWO", userID: "abc-user", now: t0.addingTimeInterval(10)))
        #expect(!ledger.owns("m-one", userID: "abc-user", now: t0.addingTimeInterval(10)))
    }
}
