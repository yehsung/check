import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 체스 **스토어**의 그물 없던 자리 — 2026-10-05 뮤테이션 실측으로 드러난 것만 담는다.
//
// 하네스는 `V0343ChessStoreTests` 와 **같은 규약**이다(실서버 픽스처 원문 · 오목 스텁 · 약참조 호스트 보관).
// 그 파일의 헬퍼는 file-private 이라 여기서 복사한다(저장소 규칙 — V0317ShopTests.stripped 와 같다).
//
// 여기서 메우는 구멍:
//   ⑤ 깃발 되묻기가 서버의 유예 **예산**을 무시하고 전역 2초로 굳어 있었다(white/black_grace_ms 가 죽은 칸)
//   ⑥ 늦게 온 옛 스냅숏 되돌림 가드에 그물이 없었다(가드를 지워도 126건 초록 — M4)
//   ⑦ 무승부 왕복(제안·수락·거절)에 결과를 재는 시험이 하나도 없었다(M17)
//   ⑧ `stale`·`illegal`·`retry` 뒤 '곧바로 다시 읽는다' 는 계약에 그물이 없었다(M18)
//   ⑩ `shouldPollWatch` 가 아무도 안 쓰는 **죽은 게이트**였다(M12)

// MARK: - 하네스 (복사)

private let sgFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private struct SGError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func sgText(_ name: String) throws -> String {
    try String(contentsOf: sgFixtureDirectory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

private func sgJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: sgFixtureDirectory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SGError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func sgCaller(_ name: String) throws -> String {
    let manifest = try sgJSON("_manifest")
    guard let fixtures = manifest["fixtures"] as? [String: Any],
          let entry = fixtures[name] as? [String: Any],
          let caller = entry["caller"] as? String else { throw SGError("\(name): 매니페스트에 caller 가 없다") }
    return caller
}

private func sgSerialize(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func sgHandler(_ map: [String: [String]]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"missing"}"#)
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

@MainActor
private enum SGRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다 — 버리면 host 가 nil 이 되어 요청이 한 건도 안 나간다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func sgStore(
    _ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler
) -> (ChessStore, String) {
    let host = "v0345-c-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0345-chess"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    SGRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600
    return (chess, host)
}

/// 픽스처의 `match` 와 `state.match` 를 **함께** 고친다(두 자리에 같은 행이 실려 온다 — 한쪽만 고치면 스토어가
/// 읽는 쪽이 옛 값이라 시험이 아무것도 안 잰다).
private func sgPatchedMatch(_ name: String, _ patch: [String: Any]) throws -> String {
    var fixture = try sgJSON(name)
    func apply(_ row: Any?) -> Any? {
        guard var dictionary = row as? [String: Any] else { return row }
        for (key, value) in patch { dictionary[key] = value }
        return dictionary
    }
    fixture["match"] = apply(fixture["match"])
    if var inner = fixture["state"] as? [String: Any] {
        inner["match"] = apply(inner["match"])
        fixture["state"] = inner
    }
    return sgSerialize(fixture)
}

/// 픽스처의 봉투 키(루트 · `state` 둘)를 함께 고친다 — 스토어는 `state` 쪽을 읽고, 사람은 루트를 읽는다.
private func sgPatchedEnvelope(_ name: String, match: [String: Any] = [:],
                               keys: [String: Any] = [:]) throws -> String {
    var fixture = try sgJSON(name)
    func applyMatch(_ row: Any?) -> Any? {
        guard var dictionary = row as? [String: Any] else { return row }
        for (key, value) in match { dictionary[key] = value }
        return dictionary
    }
    fixture["match"] = applyMatch(fixture["match"])
    for (key, value) in keys { fixture[key] = value }
    if var inner = fixture["state"] as? [String: Any] {
        inner["match"] = applyMatch(inner["match"])
        for (key, value) in keys { inner[key] = value }
        fixture["state"] = inner
    }
    return sgSerialize(fixture)
}

/// B(흑)가 보는 ply 6 국면 + **A 가 건 무승부 제안**. 실서버에 그 조합의 픽스처가 없어(제안 직후의 chess_state 를
/// 따로 뜨지 않았다) A 시점 픽스처의 봉투 키 셋만 B 시점으로 돌린다 — 판 행은 서버 원문 그대로다.
private func sgDrawOfferSeenByBlack() throws -> String {
    try sgPatchedEnvelope("chess_state__ok_mid_since0",
                          match: ["draw_offer_by": "aa000000-0000-4000-8000-0000000000a1"],
                          keys: ["my_color": "black", "legal_moves": NSNull()])
}

private func sgSquare(_ notation: String) throws -> ChessSquare {
    guard let square = ChessSquare(notation) else { throw SGError("칸 이름이 아니다: \(notation)") }
    return square
}

private let sgMidMatch = "9a7156f6-f055-4590-ba98-f537ead0a600"

@Suite("체스 스토어 — 그물 없던 자리(v0.3.44)")
struct V0345ChessStoreGapTests {

    // MARK: - ⑤ 깃발 되묻기는 **그 사람에게 남은** 유예 예산을 쓴다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func flagOverdueUsesTheServersPerSideGraceBudgetNotTheLobbyConstant() async throws {
        // 없으면: 예산을 이미 다 쓴 사람의 판은 서버에서 벌써 끝났는데 앱은 최대 2초를 더 기다리고 그 사이
        //        "상대 차례 · 0.0" 을 그린다(서버와 클라의 깃발 모형이 갈린다). `white/black_grace_ms` 는
        //        디코드만 되고 **어느 파일에서도 읽히지 않았다**(소스 전체 grep 0건).
        let name = "chess_state__ok_mid_since0"
        let fixture = try sgJSON(name)
        let serverNow = try #require(fixture["server_now_ms"] as? Double)

        // 흐른 시간 2,500ms · 남은 시간 1,000ms → 초과 1,500ms. 서버 규칙은 `초과 > 남은 예산` 이다.
        let left = 1_000, elapsed = 2_500.0
        func store(graceMs: Int) async throws -> ChessStore {
            let body = try sgPatchedMatch(name, [
                "white_ms_left": left, "white_grace_ms": graceMs,
                "turn_started_ms": serverNow - elapsed
            ])
            let (store, _) = sgStore("grace-\(graceMs)", me: try sgCaller(name),
                                     handler: sgHandler(["chess_state": [body]]))
            store.clock = { Date(timeIntervalSince1970: 1_791_200_000) }
            await store.refreshMatch(id: sgMidMatch)
            return store
        }

        let budgeted = try await store(graceMs: 2_000)      // 예산 2,000 → 1,500 ≤ 2,000 → 아직 아니다
        let spent = try await store(graceMs: 0)             // 예산 0     → 1,500 > 0     → 이미 지났다
        let budgetedMatch = try #require(budgeted.match)
        let spentMatch = try #require(spent.match)
        #expect(budgetedMatch.turn == .white && budgetedMatch.myColor == .white, "전제: 내(백) 차례다")

        // 디코드된 칸이 실제로 실려 왔다(= 서버가 주는 값이다).
        #expect(budgetedMatch.whiteGraceMs == 2_000)
        #expect(spentMatch.whiteGraceMs == 0)
        #expect(budgetedMatch.graceSecondsLeft(.white) == 2.0)
        #expect(spentMatch.graceSecondsLeft(.white) == 0)

        // 흐른 시간·남은 시간이 두 스토어에서 **같다**(갈림이 '예산' 하나로 좁혀진다).
        let now = budgeted.clock()
        let raw = budgetedMatch.clock.rawRemainingSeconds(.white, now: now)
        #expect(abs(raw - (Double(left) / 1000 - elapsed / 1000)) < 0.01, "전제: 초과분이 1.5초다(실측 \(-raw))")
        #expect(abs(spentMatch.clock.rawRemainingSeconds(.white, now: now) - raw) < 0.001)

        // ★ 기준선이 갈린다: 같은 시각·같은 시계인데 **예산만** 달라 답이 반대다.
        //   옛 코드(전역 2초)는 두 경우 **모두 false** 였다.
        #expect(!budgetedMatch.isFlagOverdue(now: now, graceSeconds: budgeted.graceSeconds))
        #expect(spentMatch.isFlagOverdue(now: now, graceSeconds: spent.graceSeconds))
        #expect(budgeted.graceSeconds == 2.0, "전제: 로비 전역 유예는 2초다(그래서 옛 코드가 둘 다 false 였다)")

        // 독립 산식으로 서버 규칙을 **다시 계산**해 같은 답인지 본다(duel.sql: `v_over > v_grace`).
        for (store, match) in [(budgeted, budgetedMatch), (spent, spentMatch)] {
            let over = elapsed - Double(left)
            let serverFlagged = over > Double(match.whiteGraceMs ?? 0)
            #expect(match.isFlagOverdue(now: now, graceSeconds: store.graceSeconds) == serverFlagged,
                    "클라 깃발 판정이 서버 규칙과 갈린다(초과 \(over)ms · 예산 \(match.whiteGraceMs ?? -1)ms)")
        }

        // 서버가 그 칸을 안 줬으면(옛 응답) 전역 값으로 떨어진다 — 폴백이 살아 있다.
        let legacy = try sgPatchedMatch(name, [
            "white_ms_left": left, "white_grace_ms": NSNull(), "turn_started_ms": serverNow - elapsed
        ])
        let (old, _) = sgStore("grace-legacy", me: try sgCaller(name),
                               handler: sgHandler(["chess_state": [legacy]]))
        old.clock = { Date(timeIntervalSince1970: 1_791_200_000) }
        await old.refreshMatch(id: sgMidMatch)
        let oldMatch = try #require(old.match)
        #expect(oldMatch.whiteGraceMs == nil)
        #expect(oldMatch.graceSecondsLeft(.white) == nil)
        #expect(!oldMatch.isFlagOverdue(now: now, graceSeconds: old.graceSeconds), "폴백이 전역 2초를 안 쓴다")

        // ★★ 그리고 **요청이 실제로 나간다**: 예산을 다 쓴 판만 조회로 서버에 신고한다.
        for (label, store, expected) in [("예산 남음", budgeted, 0), ("예산 0", spent, 1)] {
            store.isWindowVisible = true
            store.lastStateRequestAt = .distantPast
            let host = store.host?.service.projectURL.host ?? ""
            let before = GomokuStubProtocol.count(host: host, rpc: "chess_state")
            await store.pollTick(at: store.clock())
            let after = GomokuStubProtocol.count(host: host, rpc: "chess_state")
            print("[유예] \(label): 조회 \(after - before)건")
            #expect(after - before == expected,
                    "\(label) 인데 조회가 \(after - before)건 나갔다(기대 \(expected)) — 깃발 되묻기가 예산을 안 본다")
            store.stopPolling()
        }
    }

    // MARK: - ⑥ 늦게 온 **옛** 스냅숏은 판을 되돌리지 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func anOlderSnapshotArrivingLateDoesNotRewindTheBoard() async throws {
        // 없으면: 그 세 줄을 `if false { return .ignored }` 로 바꿔도 126건이 전부 초록이다(M4).
        //        도달 경로: 내 차례에 깃발+유예가 지나면 pollTick 이 refreshMatch 를 띄우고, 그 조회가 도는 중에도
        //        `isBusy` 가 false 라 사용자가 탭해 `send()` 를 보낼 수 있다(send 는 stateInFlight 를 안 본다).
        //        서버가 수를 받아 ply N+1 이 된 뒤, ply N 을 읽고 출발한 응답이 늦게 닿으면 방금 둔 수가 화면에서
        //        사라지고 시계가 한 수 전으로 되돌아간다.
        let mid = "chess_state__ok_mid_since0"          // ply 6 · 백(A) 차례
        let old = "chess_state__ok_initial_my_turn"     // **같은 판 id** 의 ply 0
        #expect(try sgCaller(mid) == (try sgCaller(old)), "전제: 두 픽스처를 같은 사람이 불렀다")

        let (store, host) = sgStore("rewind", me: try sgCaller(mid),
                                    handler: sgHandler(["chess_state": [try sgText(mid), try sgText(old)]]))
        await store.refreshMatch(id: sgMidMatch)
        let ahead = try #require(store.match)
        #expect(ahead.plyCount == 6 && ahead.moves.count == 6, "전제: 먼저 ply 6 을 들고 있다")
        let clockBefore = ahead.clock
        let fenBefore = ahead.fen

        // 두 번째 응답(ply 0)이 늦게 닿았다.
        await store.refreshMatch(id: sgMidMatch)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 2, "전제: 두 번째 조회가 실제로 나갔다")
        let after = try #require(store.match)
        #expect(after.plyCount == 6, "옛 스냅숏이 판을 ply \(after.plyCount) 로 되돌렸다")
        #expect(after.moves.count == 6, "방금 둔 수가 화면에서 사라졌다")
        #expect(after.fen == fenBefore, "판이 한 수 전 국면으로 되돌아갔다")
        #expect(after.clock == clockBefore, "시계가 한 수 전으로 되돌아갔다")
        #expect(store.phase == .playing)

        // ★ 기준선이 갈린다: **거꾸로** 읽으면 같은 두 응답이 판을 앞으로 옮긴다(옛 → 새는 적용된다).
        let (forward, _) = sgStore("rewind-fwd", me: try sgCaller(mid),
                                   handler: sgHandler(["chess_state": [try sgText(old), try sgText(mid)]]))
        await forward.refreshMatch(id: sgMidMatch)
        #expect(forward.match?.plyCount == 0, "전제: 먼저 ply 0 을 들고 있다")
        await forward.refreshMatch(id: sgMidMatch)
        #expect(forward.match?.plyCount == 6, "새 스냅숏이 적용되지 않는다 — 위 가드가 모든 응답을 버리고 있다")
        #expect(forward.match?.moves.count == 6)

        // 끝난 응답은 예외다(되돌릴 수 없는 사실) — ply 가 작아도 적용된다.
        let ended = "chess_state__end_timeout"
        let endedID = "c0de0000-0000-4000-8000-000000000a04"
        let (closing, _) = sgStore("rewind-end", me: try sgCaller(ended),
                                   handler: sgHandler(["chess_state": [try sgText(ended)]]))
        await closing.refreshMatch(id: endedID)
        #expect(closing.match?.isFinished == true, "끝난 응답이 적용되지 않았다")
    }

    // MARK: - ⑦ 무승부 왕복 — 제안의 **주인**과 세 응답

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theDrawRoundTripKnowsWhoOfferedAndWhatEachAnswerMeans() async throws {
        // 없으면: `drawOfferedByMe: offerBy != nil && offerBy == myID` → `false` 로 바꿔도 126건이 전부 초록이다(M17).
        //        그 한 토큰이 뒤집히면 **내가 보낸 제안이 나에게** "상대가 무승부를 제안했어요" + [수락]/[거절] 로 뜨고,
        //        누르면 서버가 no_offer 로 돌려보내며, 대국 화면 동작 줄이 그 갈래에 갇혀 [기권] 버튼이 사라진다.
        let mine = "chess_offer_draw__ok"                // A 가 제안했다(draw_offer_by = A)
        let theirs = "chess_offer_draw__offer_pending"   // B 가 보는 같은 판(draw_offer_by = A = 상대)

        // ① 내가 제안했다 → 내 제안이다. 화면은 [무승부 제안을 보냈어요] + [기권] 을 그린다.
        let (offerer, offererHost) = sgStore("draw-mine", me: try sgCaller(mine),
                                             handler: sgHandler(["chess_state": [try sgText("chess_state__ok_mid_since0")],
                                                                 "chess_offer_draw": [try sgText(mine)]]))
        await offerer.refreshMatch(id: sgMidMatch)
        #expect(offerer.match?.drawOfferBy == nil, "전제: 제안 전에는 제안이 없다")
        await offerer.offerDraw()
        let afterOffer = try #require(offerer.match)
        #expect(afterOffer.drawOfferBy == "aa000000-0000-4000-8000-0000000000a1")
        #expect(afterOffer.drawOfferedByMe, "내가 보낸 제안을 내 것으로 안 읽는다")
        #expect(!afterOffer.drawOfferedByOpponent,
                "내가 보낸 제안이 나에게 '상대가 무승부를 제안했어요' 로 뜬다 — 누르면 no_offer 로 거절되고 [기권] 이 사라진다")
        #expect(!afterOffer.isFinished, "제안만으로 판이 끝났다")
        #expect(GomokuStubProtocol.count(host: offererHost, rpc: "chess_offer_draw") == 1)

        // ② 상대가 제안했다 → 상대 제안이다(★ 기준선 갈림: 같은 `draw_offer_by` 인데 보는 사람이 달라 답이 반대다).
        let (receiver, _) = sgStore("draw-theirs", me: try sgCaller(theirs),
                                    handler: sgHandler(["chess_state": [try sgDrawOfferSeenByBlack()]]))
        await receiver.refreshMatch(id: sgMidMatch)
        let received = try #require(receiver.match)
        #expect(received.drawOfferBy == afterOffer.drawOfferBy, "전제: 두 사람이 같은 제안자를 본다")
        #expect(received.myColor != afterOffer.myColor, "전제: 두 사람이 다른 색이다")
        #expect(!received.drawOfferedByMe)
        #expect(received.drawOfferedByOpponent, "상대의 제안을 못 읽는다 — [무승부 수락]/[거절] 이 안 뜬다")
        #expect(afterOffer.drawOfferedByMe != received.drawOfferedByMe,
                "제안 주인 판정이 보는 사람에 따라 안 갈린다 — 이 단언들이 영원히 초록이다")

        // ③ 수락 → 판이 **무승부로 끝나고** 각자 판돈을 돌려받는다(돈 경로).
        let accept = "chess_respond_draw__accept_ok"
        let acceptID = "c0de0000-0000-4000-8000-000000000a06"
        // 씨앗은 **아직 안 끝난** 같은 판이어야 한다(끝난 판에서는 respondDraw 가 문 앞에서 돌아간다) —
        // 수락 응답 픽스처의 판 행을 `active` + A 의 제안으로 돌려 쓴다(판 id·사람·시계는 서버 원문 그대로).
        let acceptSeed = try sgPatchedEnvelope(accept, match: [
            "status": "active", "result": NSNull(), "end_reason": NSNull(), "finished_ms": NSNull(),
            "draw_offer_by": "aa000000-0000-4000-8000-0000000000a1"
        ])
        let (accepting, acceptHost) = sgStore("draw-accept", me: try sgCaller(accept),
                                              handler: sgHandler(["chess_state": [acceptSeed],
                                                                  "chess_respond_draw": [try sgText(accept)]]))
        await accepting.refreshMatch(id: acceptID)
        #expect(accepting.match?.isFinished == false, "전제: 수락할 판이 아직 진행 중이다")
        #expect(accepting.match?.drawOfferedByOpponent == true, "전제: 상대의 제안이 떠 있다")
        await accepting.respondDraw(accept: true)
        let drawn = try #require(accepting.match)
        #expect(drawn.isFinished)
        #expect(drawn.outcome == .draw, "합의 무승부가 승/패로 읽힌다 — 판돈 정산 문장이 거짓이 된다")
        #expect(drawn.endReason == .agreement)
        #expect(drawn.rubyDelta == 0, "무승부인데 루비가 \(drawn.rubyDelta ?? -999) 움직였다고 그린다")
        #expect(drawn.drawOfferBy == nil)
        #expect(!drawn.drawOfferedByMe && !drawn.drawOfferedByOpponent)
        #expect(accepting.rubyBalance == 115)
        #expect(accepting.phase == .result)
        #expect(ChessText.endReason(.agreement, outcome: .draw) == "무승부에 합의했어요")
        #expect(GomokuStubProtocol.count(host: acceptHost, rpc: "chess_respond_draw") == 1)

        // ④ 거절 → 제안만 사라지고 판은 **계속된다**(★ 기준선 갈림: 수락과 반대 답이다).
        let decline = "chess_respond_draw__decline_ok"
        let (declining, _) = sgStore("draw-decline", me: try sgCaller(decline),
                                     handler: sgHandler(["chess_state": [try sgDrawOfferSeenByBlack()],
                                                         "chess_respond_draw": [try sgText(decline)]]))
        await declining.refreshMatch(id: sgMidMatch)
        #expect(declining.match?.drawOfferedByOpponent == true, "전제: 거절할 제안이 떠 있다")
        await declining.respondDraw(accept: false)
        let continuing = try #require(declining.match)
        #expect(!continuing.isFinished, "거절했는데 판이 끝났다")
        #expect(continuing.drawOfferBy == nil, "거절했는데 제안이 남아 있다 — [수락]/[거절] 이 계속 뜬다")
        #expect(!continuing.drawOfferedByOpponent)
        #expect(declining.phase == .playing)
        #expect(declining.notice == ChessNoticeText.respondDraw(accept: false, .ok))

        // ⑤ 사라진 제안에 답했다 → 안내 한 줄이 이유를 말하고 판은 그대로다.
        let gone = "chess_respond_draw__no_offer"
        let (late, _) = sgStore("draw-gone", me: try sgCaller(gone),
                                handler: sgHandler(["chess_state": [try sgDrawOfferSeenByBlack()],
                                                    "chess_respond_draw": [try sgText(gone)]]))
        await late.refreshMatch(id: sgMidMatch)
        await late.respondDraw(accept: true)
        #expect(late.match?.isFinished == false)
        #expect(late.match?.drawOfferBy == nil)
        #expect(late.notice == ChessNoticeText.respondDraw(accept: true, .noOffer))
        #expect(late.notice != nil, "사라진 제안에 답했는데 화면이 아무 말도 안 한다")
        #expect(late.notice != declining.notice, "거절 성공과 '제안이 사라졌다' 가 같은 말을 한다")

        // ⑥ 로봇 판에는 무승부 왕복이 아예 없다(합의할 상대가 없다 — 서버로 한 건도 안 나간다).
        let (robot, robotHost) = sgStore("draw-ai", me: try sgCaller(mine),
                                         handler: sgHandler(["chess_offer_draw": [try sgText(mine)]]))
        robot.startAIMatch(humanColor: .white)
        #expect(robot.isAIMatch, "전제: 로봇 판이 섰다")
        await robot.offerDraw()
        await robot.respondDraw(accept: true)
        #expect(GomokuStubProtocol.count(host: robotHost, rpc: "chess_offer_draw") == 0)
        #expect(GomokuStubProtocol.count(host: robotHost, rpc: "chess_respond_draw") == 0)
    }

    // MARK: - ⑧ 판단이 서버와 갈리면 **곧바로 다시 읽는다**

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRefusedMoveIsFollowedByAnImmediateRefetchSoTheScreenAnswers() async throws {
        // 없으면: `case .stale, .notYourTurn, .notActive, .illegal, .retry: needsRefresh = true` → `false` 로 바꿔도
        //        126건이 전부 초록이다(M18). `ChessNoticeText.move(.stale)` 는 **의도적으로 nil** 이고 그 근거가
        //        "판이 바뀐 것은 곧바로 다시 불러와 화면이 답한다" 인데, 그 재조회를 재는 단언이 없었다 —
        //        끊기면 내 차례로 보이는 화면이 한 수 뒤처진 채 굳고(내 차례라 pollTick 의 waiting 분기도 안 돈다)
        //        탭마다 조용히 거절되는 '눌렀는데 반응 없음' 이 된다.
        let stale = "chess_move__stale"
        let seed = "chess_state__ok_initial_their_turn"       // B 가 보는 ply 0
        #expect(try sgCaller(stale) == (try sgCaller(seed)), "전제: 같은 사람(B)이 둘을 불렀다")

        let (store, host) = sgStore("refetch", me: try sgCaller(stale),
                                    handler: sgHandler([
                                        "chess_state": [try sgText(seed), try sgText("chess_state__ok_mid_since0")],
                                        "chess_move": [try sgText(stale)]
                                    ]))
        await store.refreshMatch(id: sgMidMatch)
        #expect(store.match?.plyCount == 0, "전제: 한 수 뒤처진 화면을 들고 있다")
        let before = GomokuStubProtocol.count(host: host, rpc: "chess_state")

        await store.send(ChessMove(from: try sgSquare("e7"), to: try sgSquare("e5")))
        let after = GomokuStubProtocol.count(host: host, rpc: "chess_state")
        print("[되읽기] stale 뒤 조회 \(after - before)건")
        #expect(after - before == 1,
                "stale 뒤에 다시 읽지 않았다 — 화면이 한 수 뒤처진 채 굳고 탭마다 조용히 거절된다")
        // `stale` 은 **아무 말도 안 한다**(그 근거가 바로 위 재조회다).
        #expect(ChessNoticeText.move(.stale) == nil, "stale 이 말을 하기 시작했다 — 재조회의 근거가 바뀌었다")
        #expect(store.notice == nil, "stale 에 안내줄이 떴다")
        // 그리고 화면이 **실제로 답했다**: 다시 읽은 판이 섰다.
        #expect(store.match?.plyCount == 6, "다시 읽었는데 화면이 안 따라왔다(ply \(store.match?.plyCount ?? -1))")
        #expect(store.isBusy == false)

        // ★ 기준선이 갈린다: **성공한 수**는 다시 읽지 않는다(상태를 응답에 실어 주므로 왕복이 없다).
        let ok = "chess_move__ok_white_first"
        let (good, goodHost) = sgStore("refetch-ok", me: try sgCaller(ok),
                                       handler: sgHandler([
                                           "chess_state": [try sgText("chess_state__ok_initial_my_turn")],
                                           "chess_move": [try sgText(ok)]
                                       ]))
        await good.refreshMatch(id: sgMidMatch)
        let okBefore = GomokuStubProtocol.count(host: goodHost, rpc: "chess_state")
        await good.send(ChessMove(from: try sgSquare("e2"), to: try sgSquare("e4")))
        #expect(GomokuStubProtocol.count(host: goodHost, rpc: "chess_state") == okBefore,
                "성공한 수마다 조회를 한 번 더 쏜다 — 블리츠에서 요청이 두 배가 된다")
        #expect(good.match?.plyCount == 1, "성공한 수가 화면에 안 섰다")
        #expect(good.notice == nil)

        // 거절 네 갈래 **전부**가 같은 계약을 지난다(한 갈래만 묶으면 나머지가 조용히 빠진다).
        for name in ["chess_move__illegal", "chess_move__not_your_turn",
                     "chess_move__not_active", "chess_move__retry_clock_skew"] {
            let seedName = try sgCaller(name) == (try sgCaller("chess_state__ok_initial_my_turn"))
                ? "chess_state__ok_initial_my_turn" : "chess_state__ok_initial_their_turn"
            let (refused, refusedHost) = sgStore("refetch-\(name.suffix(8))", me: try sgCaller(name),
                                                 handler: sgHandler([
                                                     "chess_state": [try sgText(seedName),
                                                                     try sgText("chess_state__ok_mid_since0")],
                                                     "chess_move": [try sgText(name)]
                                                 ]))
            await refused.refreshMatch(id: sgMidMatch)
            guard refused.match != nil else {
                #expect(Bool(false), "\(name): 씨앗 판이 안 섰다")
                continue
            }
            let base = GomokuStubProtocol.count(host: refusedHost, rpc: "chess_state")
            await refused.send(ChessMove(from: try sgSquare("e2"), to: try sgSquare("e4")))
            let delta = GomokuStubProtocol.count(host: refusedHost, rpc: "chess_state") - base
            print("[되읽기] \(name): 조회 \(delta)건 · 안내 \(refused.notice ?? "없음")")
            #expect(delta == 1, "\(name) 뒤에 다시 읽지 않았다")
        }
    }

    // MARK: - ⑩ `shouldPollWatch` 는 **실제 게이트**다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func shouldPollWatchIsTheOnlyGateThatDecidesWatchPolling() async throws {
        // 없으면: `shouldPollWatch` 의 `!watch.isFinished` 를 지워도 초록이다(M12) — 그 프로퍼티가 **아무도 안 쓰는
        //        죽은 게이트**이고 실제 폴링 판정이 `pollSpectatorFeatures` 안에 인라인으로 또 적혀 있었기 때문이다.
        //        같은 사실이 두 곳에 있고 한쪽은 검증되지 않는다(오목은 V0341 이 같은 프로퍼티를 세 줄로 잰다 — 비대칭).
        let active = "chess_watch__ok_seeded"
        let activeID = "c0de0000-0000-4000-8000-000000000a07"
        let (store, host) = sgStore("watch-gate", me: try sgCaller(active),
                                    handler: sgHandler(["chess_watch": [try sgText(active)]]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: activeID)
        await csGapWait { store.spectating?.black != nil }
        #expect(store.spectating?.isFinished == false, "전제: 진행 중 판을 보고 있다")
        #expect(store.shouldPollWatch, "진행 중 판을 보는데 폴링 게이트가 닫혀 있다")

        // 게이트가 열렸으면 **요청이 나간다**.
        store.watchRuntime.lastWatchRequestAt = .distantPast
        let before = GomokuStubProtocol.count(host: host, rpc: "chess_watch")
        await store.pollSpectatorFeatures(at: store.clock())
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == before + 1,
                "게이트가 열렸는데 관전 조회가 안 나갔다")

        // ★ 기준선이 갈린다: **끝난 판**이면 게이트가 닫히고 요청도 안 나간다(같은 창·같은 주 스위치).
        let tail = "chess_watch__ok_tail"
        let (closed, closedHost) = sgStore("watch-tail", me: try sgCaller(tail),
                                           handler: sgHandler(["chess_watch": [try sgText(tail)]]))
        closed.spectatorFeaturesEnabled = true
        closed.isWindowVisible = true
        closed.startWatching(matchID: sgMidMatch)
        await csGapWait { closed.spectating?.isFinished == true }
        #expect(closed.spectating != nil, "전제: 끝난 판의 꼬리를 보고 있다")
        #expect(closed.canPollSpectatorFeatures, "전제: 창·주 스위치는 열려 있다(갈림이 '끝남' 하나로 좁혀진다)")
        #expect(!closed.shouldPollWatch, "끝난 판인데 폴링 게이트가 열려 있다")
        closed.watchRuntime.lastWatchRequestAt = .distantPast
        let tailBefore = GomokuStubProtocol.count(host: closedHost, rpc: "chess_watch")
        await closed.pollSpectatorFeatures(at: closed.clock())
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_watch") == tailBefore,
                "끝난 판을 2초마다 계속 당긴다 — 게이트가 장식이다")

        // 같은 게이트가 '창이 다시 보였다' 경로에도 선다(두 소비자가 **한 술어**를 쓴다).
        closed.spectatorWindowDidShow(at: closed.clock())
        await csGapWait(60) { false }
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_watch") == tailBefore,
                "끝난 판인데 창을 다시 보이자 또 당긴다")
        store.watchRuntime.lastWatchRequestAt = .distantPast
        let showBefore = GomokuStubProtocol.count(host: host, rpc: "chess_watch")
        store.spectatorWindowDidShow(at: store.clock())
        await csGapWait { GomokuStubProtocol.count(host: host, rpc: "chess_watch") > showBefore }
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == showBefore + 1,
                "진행 중 판인데 창이 다시 보여도 안 당긴다 — 위 단언이 아무것도 안 잰다")
    }
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다).
@MainActor
private func csGapWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
