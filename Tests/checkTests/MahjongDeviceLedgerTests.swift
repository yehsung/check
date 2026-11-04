@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 장부(`GameDeviceLedger(game: "mahjong")` — 버그 개선 가지 원문 바이트, SPEC §4.7 D24). 그 가지의
// `GameDeviceLedgerTests.swift` 는 베끼지 않는다(같은 이름 추가가 병합 때 갈린다) — 마작이 쓰는 동작만 여기서 잰다.

@Suite("아잉 마작 장부 — 사용자별 키 · 기한 6시간 · 상한 8 · defaults 에 산다")
struct MahjongDeviceLedgerTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("사용자별 키 mahjong.ownedMatches.<uid> · 다른 계정은 못 본다 · defaults 를 같이 쓰면 다시 켠 앱도 안다",
          .gomokuDefaultsCleanup)
    func perUserKeyAndPersistence() {
        // 없으면: 같은 맥에서 계정을 바꾼 다음 사람이 앞 사람의 판 창을 띄우거나, 앱을 다시 켠 기기가 자기 판을 못 알아본다.
        let defaults = GomokuTestDefaults.make("mj-ledger")
        var ledger = GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600)
        ledger.defaults = defaults
        ledger.note("ABC", userID: "User-1", now: Self.t0)
        #expect(ledger.key(userID: "User-1") == "mahjong.ownedMatches.user-1")
        #expect(defaults.dictionary(forKey: "mahjong.ownedMatches.user-1")?["abc"] != nil)
        #expect(ledger.owns("abc", userID: "user-1", now: Self.t0) && !ledger.owns("abc", userID: "user-2", now: Self.t0))
        var reopened = GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600)
        reopened.defaults = defaults
        #expect(reopened.owns("abc", userID: "user-1", now: Self.t0))
        #expect(!GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600).owns("abc", userID: "user-1", now: Self.t0),
                "기준선: defaults 없는 새 장부는 모른다")
        reopened.drop("abc", userID: "user-1", now: Self.t0)
        #expect(defaults.dictionary(forKey: "mahjong.ownedMatches.user-1") == nil)
        #expect(!GameDeviceLedger(game: "mahjong", ttlSeconds: 1).owns("abc", userID: nil, now: Self.t0), "로그인 전 0")
    }

    @Test("기한 6시간 — 끝을 못 본 기록은 지난 뒤 저절로 빠진다")
    func expiresAfterSixHours() {
        // 없으면: 앱을 끈 채 끝난 판 기록이 남아, 같은 id 가 다시 쓰일 리 없더라도 장부가 무한히 쌓인다.
        var ledger = GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600)
        ledger.note("m1", userID: "u", now: Self.t0)
        #expect(ledger.owns("m1", userID: "u", now: Self.t0.addingTimeInterval(6 * 3_600 - 1)))
        #expect(!ledger.owns("m1", userID: "u", now: Self.t0.addingTimeInterval(6 * 3_600 + 1)))
    }

    @Test("상한 8 — 새것부터 여덟만")
    func keepsTheEightNewest() {
        // 없으면: 장부가 끝없이 자라 defaults 한 키가 판 id 수천 개를 든다.
        var ledger = GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600)
        for n in 0..<10 { ledger.note("m\(n)", userID: "u", now: Self.t0.addingTimeInterval(Double(n))) }
        let now = Self.t0.addingTimeInterval(20)
        #expect(!ledger.owns("m0", userID: "u", now: now) && !ledger.owns("m1", userID: "u", now: now))
        #expect((2..<10).allSatisfy { ledger.owns("m\($0)", userID: "u", now: now) })
    }

    @Test("스토어 도우미 — 만들기·참가·시작 ok 와 보낼 때 적고, 끝·닫힘·접음에 걷는다(장부 키는 스토어 게임 이름)")
    @MainActor
    func storeHelpersWrapTheLedger() throws {
        // 없으면: 스토어가 장부를 다른 게임 이름으로 만들어 오목·체스 기록과 섞이거나, 끝난 판 기록이 남는다.
        let store = MahjongStore()
        #expect(store.deviceLedger.game == "mahjong" && store.deviceLedger.ttlSeconds == 6 * 3_600)
        #expect(store.deviceLedger.limit == 8)
        #expect(!store.ownsMatch("x"), "호스트(세션)가 없으면 언제나 아니다")
    }
}
