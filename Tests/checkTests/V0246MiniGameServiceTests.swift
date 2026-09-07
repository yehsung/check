import Foundation
import Testing
@testable import check

// v0.2.46 미니게임 서비스 계약 — 요청 모양(경로·쿼리·본문 키)과 응답 디코드(소수초 유무·어제 1등·공개 여부).
// 스텁은 보낸 값을 되돌리고 시계가 안 흐른다(메모리) — 서버 정규화·자정 경계는 여기서 못 잡고 마이그레이션 프로브가 맡는다.

private func mgService(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
}

private func mgCanned(host: String, json: String) -> SupabaseWorkService {
    TokenBoardURLProtocol.setResponse(json, forHost: host)
    return SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon", session: TokenBoardURLProtocol.session())
}

@Test
func boardRequestOmitsTheDayKeyWhenNilAndSendsItWhenGiven() async throws {
    let service = mgService(host: "mg-svc-board-day")
    _ = try await service.fetchMiniGameBoard(accessToken: "t", kind: .timingBar, day: nil)
    _ = try await service.fetchMiniGameBoard(accessToken: "t", kind: .flappy, day: "2026-09-07")
    let bodies = URLProtocolStub.bodies(forHost: "mg-svc-board-day")
    #expect(bodies.count == 2)
    let first = try #require(try JSONSerialization.jsonObject(with: Data(bodies[0].utf8)) as? [String: Any])
    #expect(Set(first.keys) == ["p_game"], "p_day 가 nil 이면 키 자체가 빠져야 서버가 KST 오늘을 쓴다 — \(first.keys.sorted())")
    #expect(first["p_game"] as? String == "timing_bar")
    let second = try #require(try JSONSerialization.jsonObject(with: Data(bodies[1].utf8)) as? [String: Any])
    #expect(second["p_game"] as? String == "flappy")
    #expect(second["p_day"] as? String == "2026-09-07")
    let paths = URLProtocolStub.requests(forHost: "mg-svc-board-day").map { $0.url?.path ?? "" }
    #expect(paths == ["/rest/v1/rpc/minigame_board", "/rest/v1/rpc/minigame_board"])
}

@Test
func upsertRequestShapeMatchesThePostgrestContract() async throws {
    let service = mgService(host: "mg-svc-upsert")
    try await service.upsertMiniGameScore(accessToken: "t", userID: "u-1", kind: .timingBar, score: 880)
    let request = try #require(URLProtocolStub.requests(forHost: "mg-svc-upsert").first)
    #expect(request.url?.path == "/rest/v1/minigame_daily_scores")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.query == "on_conflict=user_id,game,day")
    #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=minimal")
    let body = try #require(try JSONSerialization.jsonObject(with: Data(URLProtocolStub.bodies(forHost: "mg-svc-upsert")[0].utf8)) as? [String: Any])
    #expect(Set(body.keys) == ["user_id", "game", "best_score"])
    #expect(body["best_score"] as? Int == 880)
    #expect(body["game"] as? String == "timing_bar")
}

@Test
func boardRowsDecodeFractionalAndWholeSecondTimestampsAndFillDefaults() async throws {
    let service = mgCanned(host: "mg-svc-decode", json: """
        [
          {"user_id":"a","display_name":"가","avatar_url":"https://example.com/a.jpg","best_score":900,"best_at":"2026-09-08T00:10:00.512345+00:00","plays":4},
          {"user_id":"b","display_name":"나","avatar_url":null,"best_score":850,"best_at":"2026-09-08T00:20:00Z","plays":2},
          {"user_id":"c","display_name":null,"avatar_url":null,"best_score":10,"best_at":null,"plays":null}
        ]
        """)
    let entries = try await service.fetchMiniGameBoard(accessToken: "t", kind: .timingBar)
    #expect(entries.count == 3)
    #expect(entries[0].bestAt != nil, "소수초 timestamptz 가 nil 로 흘렀다")
    #expect(entries[1].bestAt != nil, "소수초 없는 timestamptz 가 nil 로 흘렀다")
    #expect(entries[0].avatarURL?.absoluteString == "https://example.com/a.jpg")
    #expect(entries[2].name == "사용자" && entries[2].bestAt == nil && entries[2].plays == 0, "누락 컬럼은 기본값으로 접는다")
    #expect(TokenBoardURLProtocol.lastURL(forHost: "mg-svc-decode")?.path == "/rest/v1/rpc/minigame_board")
}

@Test
func yesterdayWinnerDecodesAwardedFlagAndEmptyMeansNoWinner() async throws {
    let awarded = mgCanned(host: "mg-svc-winner", json: """
        [{"day":"2026-09-07","user_id":"w","display_name":"우승","avatar_url":null,"score":990,"awarded":true}]
        """)
    let winner = try #require(try await awarded.fetchMiniGameYesterdayWinner(accessToken: "t", kind: .flappy))
    #expect(winner.day == "2026-09-07" && winner.userID == "w" && winner.name == "우승" && winner.score == 990 && winner.awarded)
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: "mg-svc-winner"))
    #expect(body.contains(#""p_game":"flappy""#))

    let pending = mgCanned(host: "mg-svc-winner-pending", json: """
        [{"day":"2026-09-07","user_id":"w","display_name":"우승","score":500}]
        """)
    let notYet = try #require(try await pending.fetchMiniGameYesterdayWinner(accessToken: "t", kind: .flappy))
    #expect(!notYet.awarded, "awarded 누락은 '아직 안 줌'")

    let none = mgCanned(host: "mg-svc-winner-none", json: "[]")
    #expect(try await none.fetchMiniGameYesterdayWinner(accessToken: "t", kind: .flappy) == nil)
}

@Test
func miniGamePublicGetUsesItsOwnSelectAndPatchSendsOneColumn() async throws {
    let service = mgService(host: "mg-svc-public")
    let value = try await service.fetchMiniGamePublic(accessToken: "t", userID: "u-1")
    #expect(value == nil, "스텁(컬럼 없는 서버)은 키를 안 주므로 nil = 공개 기본")
    try await service.updateMiniGamePublic(accessToken: "t", userID: "u-1", isPublic: false)
    let requests = URLProtocolStub.requests(forHost: "mg-svc-public")
    #expect(requests[0].httpMethod == "GET" && requests[0].url?.query?.contains("select=minigame_public") == true)
    #expect(requests[1].httpMethod == "PATCH" && requests[1].url?.query == "id=eq.u-1")
    let patch = try #require(try JSONSerialization.jsonObject(with: Data(URLProtocolStub.bodies(forHost: "mg-svc-public")[1].utf8)) as? [String: Any])
    #expect(Set(patch.keys) == ["minigame_public"] && patch["minigame_public"] as? Bool == false)
}

@Test
func boardSortingIsScoreThenEarliestThenName() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let entries = [
        MiniGameBoardEntry(userID: "late", name: "늦음", avatarURL: nil, bestScore: 500, bestAt: t0.addingTimeInterval(60), plays: 1),
        MiniGameBoardEntry(userID: "none", name: "모름", avatarURL: nil, bestScore: 500, bestAt: nil, plays: 1),
        MiniGameBoardEntry(userID: "early", name: "이름", avatarURL: nil, bestScore: 500, bestAt: t0, plays: 1),
        MiniGameBoardEntry(userID: "top", name: "꼴찌", avatarURL: nil, bestScore: 900, bestAt: nil, plays: 1)
    ]
    #expect(entries.sortedForMiniGameBoard().map(\.userID) == ["top", "early", "late", "none"])
}

@Test
func kstYesterdayKeyCrossesTheMidnightBoundaryInSeoulNotUTC() {
    // 2026-09-07 23:30 KST = 2026-09-07 14:30 UTC → 어제는 09-06. 30분 뒤(자정 지난 KST 00:00) → 어제는 09-07.
    let beforeMidnight = Date(timeIntervalSince1970: 1_788_791_400)   // 2026-09-07T14:30:00Z = 23:30 KST
    #expect(MiniGameDayKey.key(for: beforeMidnight) == "2026-09-07")
    #expect(MiniGameDayKey.yesterday(beforeMidnight) == "2026-09-06")
    let afterMidnight = beforeMidnight.addingTimeInterval(1_800)
    #expect(MiniGameDayKey.key(for: afterMidnight) == "2026-09-08")
    #expect(MiniGameDayKey.yesterday(afterMidnight) == "2026-09-07")
}
