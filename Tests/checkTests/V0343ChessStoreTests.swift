import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 — 체스 스토어(`ChessStore`) 계약. **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이고 **응답 본문은 실서버 픽스처 원문**이다(`Fixtures/chess-rpc/*.json` — 전용 로컬 Postgres 에
// 마이그레이션 두 장을 올려 RPC 를 실제로 부른 jsonb). 스텁이 추측한 모양을 먹이면 "스토어는 초록인데 운영에서
// 안 되는" 자리가 그대로 남는다 — 픽스처 계약(V0343ChessFixtureContractTests)이 그 원문을 봉투 키·독립 산식으로
// 이미 검증했으므로, 여기서는 **그 원문을 먹였을 때 스토어가 무엇이 되는가**만 본다.
//
// 하네스는 오목 것을 **그대로 쓴다**(`GomokuStubProtocol` · `GomokuTestDefaults`). 베껴 두 벌을 만들면
// 한쪽만 고쳐지는 날이 온다 — 그 URLProtocol 은 rpc 이름을 가리지 않고 호스트로만 가른다(체스 호출도 그대로 잡힌다).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).
//
// ★ 기준선이 갈리는지 확인했다(두 분기가 동시에 참인 입력이 없으면 그 단언은 영원히 초록이다):
//   · `legal_moves` — 20개(내 차례 초기) · 3개(체크) · null(상대 차례·끝난 판) → ①②③
//   · `in_check` — false · true · null(끝난 판) → ③
//   · 종국 — 패배(timeout) · 무승부(timeout_insufficient) → ④
//   · 승격 — 네 갈래로 **묻는** 수 · 곧바로 **보내는** 수 → ⑤
//   · 창 — 보임 · 안 보임 · 가려짐 셋이 다른 답을 낸다 → ⑦
//   · 경로 — AI 판은 요청 0, 같은 동작이 1:1 에서는 요청 1 → ⑨
//   · 주 스위치 — 꺼짐 0 · 켜짐 1 → ⑪
//   · me.rank — 숫자 · null → ⑪

// MARK: - 하네스

/// 픽스처 폴더. 픽스처 계약 테스트와 같은 자리를 본다.
private let csFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private struct CSError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 픽스처 **원문**(서버가 낸 글자 그대로 — 다시 직렬화하지 않는다).
private func csText(_ name: String) throws -> String {
    try String(contentsOf: csFixtureDirectory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

private func csJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: csFixtureDirectory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CSError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

/// 그 픽스처를 **누가 불렀는가**(매니페스트). 테스트 세션의 user id 가 이 사람이어야 `my_color`·신청 방향이 맞는다 —
/// 손으로 적어 두면 픽스처를 다시 뽑는 날 조용히 어긋난다.
private func csCaller(_ name: String) throws -> String {
    let manifest = try csJSON("_manifest")
    guard let fixtures = manifest["fixtures"] as? [String: Any],
          let entry = fixtures[name] as? [String: Any],
          let caller = entry["caller"] as? String else {
        throw CSError("\(name): 매니페스트에 caller 가 없다")
    }
    return caller
}

/// 매니페스트의 씨앗 국면(판을 표에 심은 픽스처의 **출발 FEN**).
private func csSeedFEN(_ matchID: String) throws -> String {
    let manifest = try csJSON("_manifest")
    guard let seeds = manifest["seeds"] as? [String: Any],
          let seed = seeds[matchID] as? [String: Any], let fen = seed["fen"] as? String else {
        throw CSError("\(matchID): 매니페스트에 씨앗 FEN 이 없다")
    }
    return fen
}

private func csSerialize(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// 서버에 그 함수가 아직 없을 때 PostgREST 가 내는 **실제 404 본문 모양**(db push 전 창).
/// 이 글자가 중요하다: `serviceError` 는 "schema cache" 를 보고 `.databaseSchemaMissing` 으로 접는다 —
/// 짧게 줄여 쓰면 그냥 `invalidResponse(404)` 가 되어 "서버가 아직 안 올라갔다" 갈래를 **한 번도 안 지난다**.
private func csPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
        + #""message":"Could not find the function public."# + function
        + #" in the schema cache"}"#
}

/// rpc 이름 → 응답 본문 목록(같은 rpc 의 n 번째 호출이 n 번째 본문을 받고, 모자라면 마지막 것이 반복된다).
/// 표에 없는 rpc 는 **PGRST202** 로 답한다(서버가 그 함수를 아직 모르는 창).
private func csHandler(_ map: [String: [String]]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: csPGRST202(rpc))
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

@MainActor
private enum CSRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다(제품 계약 — 순환 참조 금지). 테스트가 버리면
    /// 곧바로 해제되어 host 가 nil 이 되고 **요청이 한 건도 안 나간다**(오목에서 실제로 그렇게 빨개졌다).
    static var stores: [WorkTimerStore] = []
}

/// 체스 스토어 한 벌 + 그 스텁 호스트 이름. `me` 는 픽스처를 부른 사람이어야 한다(`csCaller`).
@MainActor
private func makeChessStore(
    _ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler
) -> (ChessStore, String) {
    let host = "v0343-c-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let defaults = GomokuTestDefaults.make("v0343-chess")
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults, workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    CSRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    // 실루프를 재우고 `pollTick(at:)` 을 직접 밟아 결정적으로 본다(오목 관용구).
    chess.pollStepSeconds = 3_600
    return (chess, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다 — 오목 실측).
@MainActor
private func csWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func csSquare(_ notation: String) throws -> ChessSquare {
    guard let square = ChessSquare(notation) else { throw CSError("칸 이름이 아니다: \(notation)") }
    return square
}

@Suite("체스 스토어 — 실서버 픽스처를 먹였을 때의 결과")
struct V0343ChessStoreTests {

    // MARK: - ① 초기 국면 · 내 차례

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func initialMyTurnFixtureBecomesPlayableWhiteBoard() async throws {
        // 없으면: 봉투를 디코드만 하고 판·차례·시계·합법 수를 하나도 안 옮겨도 초록이다.
        let name = "chess_state__ok_initial_my_turn"
        let fixture = try csJSON(name)
        let (store, host) = makeChessStore("init", me: try csCaller(name),
                                           handler: csHandler(["chess_state": [try csText(name)]]))
        await store.refreshMatch(id: fixture["match"].flatMap { ($0 as? [String: Any])?["id"] as? String })

        let match = try #require(store.match)
        #expect(store.phase == .playing)
        #expect(!match.isFinished)
        #expect(match.myColor == .white)
        #expect(match.turn == .white)
        #expect(match.isMyTurn)
        #expect(match.plyCount == 0)
        #expect(match.stake == 5)
        #expect(match.moves.isEmpty)
        #expect(match.lastMove == nil)
        #expect(!match.isInCheck)
        #expect(match.drawOfferBy == nil)
        #expect(!match.drawOfferedByMe)
        #expect(!match.drawOfferedByOpponent)

        // 판은 서버 FEN 을 **읽어서** 섰다(그리기까지 갈 수 있다).
        let position = try #require(match.position)
        #expect(match.fen == fixture["match"].flatMap { ($0 as? [String: Any])?["fen"] as? String })
        #expect(position.sideToMove == .white)
        #expect(position.fen == match.fen)

        // 합법 수는 **서버가 준 것**이고, 그 집합이 로컬 규칙의 답과 같다(초기 국면은 20수).
        let serverLegal = try #require(fixture["legal_moves"] as? [String])
        #expect(match.legalMoves.map(\.uci).sorted() == serverLegal.sorted())
        #expect(match.legalMoves.count == 20)
        #expect(ChessRules.legalMoves(in: position).map(\.uci).sorted() == serverLegal.sorted())

        // 시계: 서버 네 값으로 보간한다. 차례 시작 순간이면 둘 다 5분이고 마감은 시작 + 남은 시간이다.
        let turnStarted = try #require(store.deviceDate(
            serverMs: (fixture["match"] as? [String: Any])?["turn_started_ms"] as? Double))
        #expect(match.clock.whiteMsLeft == 300_000)
        #expect(match.clock.blackMsLeft == 300_000)
        #expect(match.clock.incrementMs == 3_000)
        #expect(match.clock.running == .white)
        #expect(abs(match.clock.remainingSeconds(.white, now: turnStarted) - 300) < 0.001)
        #expect(abs(match.clock.remainingSeconds(.black, now: turnStarted) - 300) < 0.001)
        // 10초 뒤에는 **백만** 줄어 있다(보간이 차례쪽에만 걸린다).
        let later = turnStarted.addingTimeInterval(10)
        #expect(abs(match.clock.remainingSeconds(.white, now: later) - 290) < 0.001)
        #expect(abs(match.clock.remainingSeconds(.black, now: later) - 300) < 0.001)
        let deadline = try #require(match.clock.deadline)
        #expect(abs(deadline.timeIntervalSince(turnStarted) - 300) < 0.001)

        #expect(store.rubyBalance == 95)
        #expect(match.opponent.displayName == "체스지유")
        #expect(match.opponent.characterID == "shiba")
        #expect(store.selection == nil)
        #expect(store.promotion == nil)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1)
    }

    // MARK: - ② 합법 수의 주인은 서버다(상대 차례는 비어 있다)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func opponentTurnHasNoHighlightAndTapIsRefusedWithoutLocalFallback() async throws {
        // 없으면: 서버가 null 을 줬는데 클라가 `ChessRules` 로 만들어 그려도(= 상대 차례에 하이라이트가 떠도) 초록이다.
        let mine = "chess_state__ok_initial_my_turn"
        let theirs = "chess_state__ok_initial_their_turn"
        let matchID = "9a7156f6-f055-4590-ba98-f537ead0a600"

        let (a, _) = makeChessStore("legal-mine", me: try csCaller(mine),
                                    handler: csHandler(["chess_state": [try csText(mine)]]))
        await a.refreshMatch(id: matchID)
        let (b, hostB) = makeChessStore("legal-theirs", me: try csCaller(theirs),
                                        handler: csHandler(["chess_state": [try csText(theirs)]]))
        await b.refreshMatch(id: matchID)

        let other = try #require(b.match)
        #expect(other.myColor == .black)
        #expect(other.turn == .white)
        #expect(!other.isMyTurn)
        #expect(other.legalMoves.isEmpty)
        // ★ 같은 국면을 로컬 규칙에 물으면 **비어 있지 않다** — 그래서 위 빈 배열은 "서버 값을 쓴다" 는 증거다.
        let otherPosition = try #require(other.position)
        #expect(!ChessRules.legalMoves(in: otherPosition).isEmpty)

        // ★★ 저장된 배열이 비었다는 것은 **모양**이다. 뷰가 하이라이트로 그리고 `tap` 이 보낼 수를 고르는 자리는
        //    `targets(from:)`·`legalMoves(from:to:)` 둘이고, **그 둘이 빈 서버 값을 로컬 규칙으로 메우면**
        //    "앱은 둘 수 있다는데 서버가 거절한다" 가 된다. 그래서 결과를 잰다 — 내 차례인데 서버가 합법 수를
        //    안 준 **저하 봉투**로 재야 `isMyTurn` 가드에 가리지 않는다(상대 차례 봉투로는 그 가드가 먼저 막아
        //    이 계약을 한 번도 지나지 않는다).
        //    2026-10-05 뮤테이션 실측: 이 묶음이 없으면 두 함수에 로컬 폴백을 심어도 V0343 체스 27건이 전부 초록이었다.
        var degraded = try csJSON(mine)
        degraded["legal_moves"] = nil
        if var inner = degraded["state"] as? [String: Any] {
            inner["legal_moves"] = nil
            degraded["state"] = inner
        }
        let (c, hostC) = makeChessStore("legal-degraded", me: try csCaller(mine),
                                        handler: csHandler(["chess_state": [csSerialize(degraded)]]))
        await c.refreshMatch(id: matchID)
        let degradedMatch = try #require(c.match)
        let e2 = try csSquare("e2")
        let e4 = try csSquare("e4")
        #expect(degradedMatch.isMyTurn, "저하 봉투에서도 내 차례라야 합법 수의 주인을 묻는 자리에 닿는다")
        #expect(degradedMatch.legalMoves.isEmpty)
        // 기준선: 같은 국면을 로컬 규칙에 물으면 e2e4 가 **있다**. 아래 두 단언은 그래서 뜻을 가진다.
        let degradedPosition = try #require(degradedMatch.position)
        #expect(ChessRules.legalMoves(in: degradedPosition).contains(ChessMove(from: e2, to: e4)))
        #expect(c.targets(from: e2).isEmpty, "서버가 안 준 수를 클라가 만들어 하이라이트를 켰다")
        #expect(c.legalMoves(from: e2, to: e4).isEmpty, "서버가 안 준 수를 클라가 만들어 보낼 수 있게 했다")
        // 그 칸을 눌러도 고르기가 서지 않고 요청이 안 나간다(거절은 이유를 남긴다).
        await c.tap(e2)
        #expect(c.selection == nil)
        #expect(c.notice == ChessNoticeText.cannotMove)
        #expect(GomokuStubProtocol.count(host: hostC, rpc: "chess_move") == 0)

        // 상대 차례에 판을 눌러도 요청이 안 나가고 상태줄이 이유를 말한다.
        await b.tap(try csSquare("e7"))
        #expect(b.selection == nil)
        #expect(b.notice == ChessNoticeText.notYourTurn)
        #expect(GomokuStubProtocol.count(host: hostB, rpc: "chess_move") == 0)

        // ★ 기준선 갈림: 같은 판·같은 ply 인데 두 사람의 답이 다르다.
        let mineMatch = try #require(a.match)
        #expect(mineMatch.id == other.id)
        #expect(mineMatch.plyCount == other.plyCount)
        #expect(mineMatch.legalMoves.count == 20)
        #expect(mineMatch.legalMoves.count != other.legalMoves.count)
        #expect(mineMatch.myColor != other.myColor)
        // 같은 질문에 서버가 합법 수를 **준** 쪽은 칸을 켠다 — 두 분기가 동시에 참인 입력이 없으면
        // 위 `isEmpty` 셋은 영원히 초록이다(기준선 갈림).
        #expect(a.targets(from: e2) == [try csSquare("e3"), e4])
        #expect(!a.targets(from: e2).isEmpty && c.targets(from: e2).isEmpty)
        #expect(a.match?.fen == degradedMatch.fen, "두 스토어가 같은 국면이라야 갈림이 '서버 값 유무' 하나로 좁혀진다")
    }

    // MARK: - ③ 체크 · in_check 세 값

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func inCheckFixtureNarrowsLegalMovesAndTheThreeBaselinesDiffer() async throws {
        // 없으면: in_check 를 항상 false 로 둬도(체크 경고가 영영 안 떠도) 초록이다.
        let check = "chess_state__ok_in_check"
        let fixture = try csJSON(check)
        let (store, _) = makeChessStore("check", me: try csCaller(check),
                                        handler: csHandler(["chess_state": [try csText(check)]]))
        await store.refreshMatch(id: "c0de0000-0000-4000-8000-000000000a0a")

        let match = try #require(store.match)
        #expect(match.isInCheck)
        #expect(match.isMyTurn)
        #expect(match.legalMoves.count == 3)
        let checkLegal = try #require(fixture["legal_moves"] as? [String])
        #expect(match.legalMoves.map(\.uci).sorted() == checkLegal.sorted())
        // 독립 산식: 서버가 준 FEN 을 Swift 가 혼자 판정해도 체크이고 수는 셋이다.
        let position = try #require(match.position)
        #expect(ChessRules.isInCheck(position))
        #expect(ChessRules.legalMoves(in: position).count == 3)

        // ★ 기준선 갈림: 세 픽스처의 in_check 가 {false, true, 끝난 판} 셋으로 갈린다.
        let initial = "chess_state__ok_initial_my_turn"
        let (plain, _) = makeChessStore("check-plain", me: try csCaller(initial),
                                        handler: csHandler(["chess_state": [try csText(initial)]]))
        await plain.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        let ended = "chess_state__end_timeout"
        let (over, _) = makeChessStore("check-over", me: try csCaller(ended),
                                       handler: csHandler(["chess_state": [try csText(ended)]]))
        await over.refreshMatch(id: "c0de0000-0000-4000-8000-000000000a04")

        let plainMatch = try #require(plain.match)
        let overMatch = try #require(over.match)
        #expect(plainMatch.isInCheck == false)
        #expect(overMatch.isInCheck == false)       // 끝난 판은 서버가 null → false
        #expect(overMatch.isFinished)
        #expect(plainMatch.isFinished == false)
        // 셋이 같은 값이면(= 갈림이 사라졌으면) 위 단언들이 아무것도 재지 않는다.
        #expect(Set([match.isInCheck, plainMatch.isInCheck]).count == 2)
    }

    // MARK: - ④ 종국 둘(패배 · FIDE 6.9 무승부)이 다른 답을 낸다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func timeoutLossAndTimeoutDrawProduceDifferentOutcomes() async throws {
        // 없으면: 두 종국을 한 사유로 접어도(시간패 무승부를 패배로 그려도) 초록이다.
        let loss = "chess_state__end_timeout"
        let draw = "chess_state__end_timeout_insufficient"

        let (lost, _) = makeChessStore("end-loss", me: try csCaller(loss),
                                       handler: csHandler(["chess_state": [try csText(loss)]]))
        await lost.refreshMatch(id: "c0de0000-0000-4000-8000-000000000a04")
        let (drawn, _) = makeChessStore("end-draw", me: try csCaller(draw),
                                        handler: csHandler(["chess_state": [try csText(draw)]]))
        await drawn.refreshMatch(id: "c0de0000-0000-4000-8000-000000000a05")

        let a = try #require(lost.match)
        #expect(lost.phase == .result)
        #expect(a.isFinished)
        #expect(a.myColor == .black)                 // 깃발은 백이 떨어뜨렸고 결과는 white_win
        #expect(a.outcome == .lost)
        #expect(a.endReason == .timeout)
        #expect(a.endReason?.isDraw == false)
        #expect(a.rubyDelta == -5)
        #expect(a.legalMoves.isEmpty)
        #expect(a.turn == nil)
        #expect(a.clock.running == nil)
        // 끝난 판의 시계는 **멈춘다** — 두 다른 '지금' 에 같은 값을 그린다.
        let t0 = Date(timeIntervalSince1970: 1_791_182_800)
        #expect(a.clock.remainingSeconds(.black, now: t0)
                == a.clock.remainingSeconds(.black, now: t0.addingTimeInterval(600)))
        #expect(a.isFlagOverdue(now: t0.addingTimeInterval(86_400), graceSeconds: 2) == false)

        let b = try #require(drawn.match)
        #expect(drawn.phase == .result)
        #expect(b.outcome == .draw)
        #expect(b.endReason == .timeoutInsufficient)
        #expect(b.endReason?.isDraw == true)
        #expect(b.rubyDelta == 0)

        // 독립 재판정: 깃발 쪽은 매니페스트에서 읽고, FIDE 6.9 를 `ChessRules` 가 혼자 판정한다.
        let manifest = try csJSON("_manifest")
        let entry = try #require((manifest["fixtures"] as? [String: Any])?[draw] as? [String: Any])
        let drawFlaggedText = try #require(entry["flagged"] as? String)
        let flagged = try #require(ChessColor(rawValue: drawFlaggedText))
        let drawPosition = try #require(b.position)
        #expect(flagged == .white)
        #expect(ChessRules.timeoutRuling(position: drawPosition, flagged: flagged)
                == .drawByInsufficientMaterial)
        // 같은 술어를 패배 쪽 판에 물으면 **다른 답**이 나온다(이 둘이 같으면 위 단언이 영원히 초록이다).
        let lossEntry = try #require((manifest["fixtures"] as? [String: Any])?[loss] as? [String: Any])
        let lossFlaggedText = try #require(lossEntry["flagged"] as? String)
        let lossFlagged = try #require(ChessColor(rawValue: lossFlaggedText))
        let lossPosition = try #require(a.position)
        #expect(ChessRules.timeoutRuling(position: lossPosition, flagged: lossFlagged)
                == .loss(flagged: lossFlagged))

        // ★ 기준선 갈림(결과 축).
        #expect(a.outcome != b.outcome)
        #expect(a.endReason?.isDraw != b.endReason?.isDraw)
        #expect(a.rubyDelta != b.rubyDelta)
    }

    // MARK: - ⑤ 입력 2단 · 승격은 한 단 더 묻는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func promotionAsksBeforeSendingAndPlainMoveDoesNot() async throws {
        // 없으면: 폰이 8랭크에 닿을 때 서버가 네 수를 줬는데 클라가 하나를 **골라 버려도**(사용자가 못 고르고
        // 늘 퀸이 되어도, 또는 아무 수도 안 나가도) 초록이다.
        let promo = "chess_move__ok_promotion"
        let promoMatchID = "c0de0000-0000-4000-8000-000000000a0b"
        let seedFEN = try csSeedFEN(promoMatchID)
        let seedPosition = try #require(ChessPosition(fen: seedFEN))

        // 착수 **직전** 상태는 픽스처에 없다(픽스처는 둔 뒤다). 그래서 실제 응답 봉투의 키를 그대로 쓰고
        // 판·수 번호·차례만 매니페스트 씨앗으로 되돌린다. `legal_moves` 는 지어내지 않고 서버와 **같은 규칙**
        // (`ChessRules.legalMoves`, 픽스처 계약 ③ 이 두 답이 같음을 이미 증명했다)으로 만든다.
        var before = try csJSON(promo)
        var beforeMatch = try #require(before["match"] as? [String: Any])
        beforeMatch["fen"] = seedFEN
        beforeMatch["ply_count"] = 98
        beforeMatch["turn"] = "white"
        beforeMatch["result"] = NSNull()
        beforeMatch["end_reason"] = NSNull()
        beforeMatch["winner"] = NSNull()
        beforeMatch["finished_ms"] = NSNull()
        beforeMatch["status"] = "active"
        before["match"] = beforeMatch
        before["moves"] = []
        before["legal_moves"] = ChessRules.legalMoves(in: seedPosition).map(\.uci).sorted()
        before["in_check"] = false
        before.removeValue(forKey: "san")
        before.removeValue(forKey: "outcome")
        before.removeValue(forKey: "repetition")
        before.removeValue(forKey: "state")

        let (store, host) = makeChessStore(
            "promo", me: try csCaller(promo),
            handler: csHandler(["chess_state": [csSerialize(before)], "chess_move": [try csText(promo)]]))
        await store.refreshMatch(id: promoMatchID)
        let seeded = try #require(store.match)
        #expect(seeded.plyCount == 98)
        #expect(seeded.isMyTurn)

        // 1단: 폰을 고른다. 갈 수 있는 칸은 a8 하나(승격 네 갈래가 같은 칸이다).
        await store.tap(try csSquare("a7"))
        let selection = try #require(store.selection)
        #expect(selection.from == (try csSquare("a7")))
        #expect(selection.targets == [try csSquare("a8")])
        #expect(store.promotion == nil)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_move") == 0)

        // 2단: 도착 칸을 눌렀는데 **아직 수가 안 나간다** — 네 말 중 고르는 단계가 뜬다.
        await store.tap(try csSquare("a8"))
        let prompt = try #require(store.promotion)
        #expect(prompt.from == (try csSquare("a7")))
        #expect(prompt.to == (try csSquare("a8")))
        #expect(prompt.choices == [.queen, .rook, .bishop, .knight])
        #expect(store.selection == nil)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_move") == 0, "고르기 전에 수가 나갔다")

        // 3단: 퀸을 고르면 그 수가 간다. 본문의 UCI·낙관적 동시성 토큰까지 결과로 잰다.
        await store.choosePromotion(.queen)
        #expect(store.promotion == nil)
        let calls = GomokuStubProtocol.calls(host: host, rpc: "chess_move")
        #expect(calls.count == 1)
        #expect(calls.first?.json["p_uci"] as? String == "a7a8q")
        #expect(calls.first?.json["p_expected_ply"] as? Int == 98)
        #expect(calls.first?.json["p_match_id"] as? String == promoMatchID)

        // 응답이 판을 한 수 앞으로 옮긴다(기보·마지막 수·FEN 전부 서버 값).
        let after = try #require(store.match)
        #expect(after.plyCount == 99)
        #expect(after.moves.last?.san == "a8=Q+")
        #expect(after.moves.last?.move.promotion == .queen)
        #expect(after.lastMove?.uci == "a7a8q")
        #expect(after.fen == "Q3k3/8/8/8/8/8/8/4K3 b - - 0 50")
        #expect(after.isInCheck)
        // 피셔 시계: 쓴 시간을 빼고 가산을 더한 값이 그대로 왔다.
        #expect(after.moves.last?.msLeft == 212_084)
        #expect(after.moves.last?.msSpent == 916)
        #expect(after.moves.last?.msLeft == 210_000 - 916 + 3_000)

        // ★ 기준선 갈림: 승격이 아닌 수는 **묻지 않고 곧바로** 나간다.
        let initial = "chess_state__ok_initial_my_turn"
        let (plain, plainHost) = makeChessStore(
            "promo-plain", me: try csCaller(initial),
            handler: csHandler(["chess_state": [try csText(initial)],
                                "chess_move": [try csText("chess_move__ok_white_first")]]))
        await plain.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        await plain.tap(try csSquare("e2"))
        await plain.tap(try csSquare("e4"))
        #expect(plain.promotion == nil, "승격이 아닌 수에 고르기 창이 떴다")
        let plainCalls = GomokuStubProtocol.calls(host: plainHost, rpc: "chess_move")
        #expect(plainCalls.count == 1)
        #expect(plainCalls.first?.json["p_uci"] as? String == "e2e4")
        #expect(plainCalls.first?.json["p_expected_ply"] as? Int == 0)
        let plainAfter = try #require(plain.match)
        #expect(plainAfter.plyCount == 1)
        #expect(plainAfter.moves.last?.san == "e4")
    }

    // MARK: - ⑥ 늦은 응답은 **실제로** 버려진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func lateStateResponseAfterResetIsDiscarded() async throws {
        // 없으면: 로그아웃·계정 전환 뒤 도착한 앞 계정의 판이 새 화면에 그대로 뜬다(세대 가드를 빼면 이 자리가 빨개진다).
        let name = "chess_state__ok_initial_my_turn"
        let body = try csText(name)
        let host = "v0343-c-late-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            guard rpc == "chess_state" else { return GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
            return GomokuStubProtocol.Reply(body: body, delay: 0.3)   // 늦게 도착한다
        }
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
            session: GomokuStubProtocol.session())
        let owner = WorkTimerStore(
            service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: GomokuTestDefaults.make("v0343-chess"), workspaceNotifications: nil)
        owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: try csCaller(name))
        CSRetention.stores.append(owner)
        let store = ChessStore(host: owner)
        store.pollStepSeconds = 3_600

        let task = Task { @MainActor in await store.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600") }
        // 요청이 실제로 나간 뒤에 리셋한다 — 안 나갔으면 이 시험은 아무것도 재지 않는다.
        await csWait { GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1 }
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1)
        store.reset()
        _ = await task.value
        // 응답이 도착할 시간을 충분히 준다(지연 0.3초).
        for _ in 0..<200 { try? await Task.sleep(for: .milliseconds(5)) }

        #expect(store.match == nil, "리셋 뒤 도착한 앞 계정의 판이 화면에 섰다")
        #expect(store.phase == .lobby)
        #expect(store.rubyBalance == nil)
        #expect(store.selection == nil)

        // ★ 기준선 갈림: 리셋이 없으면 **같은 응답이 판을 세운다**(그래야 위 nil 이 뜻을 가진다).
        let (fresh, _) = makeChessStore("late-ok", me: try csCaller(name),
                                        handler: csHandler(["chess_state": [body]]))
        await fresh.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        #expect(fresh.match != nil)
    }

    // MARK: - ⑦ 창이 안 보이면 요청이 안 나간다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func pollTickSendsNothingWhileWindowIsHiddenOrOccluded() async throws {
        // 없으면: 창을 닫아 둔 맥이 1.5초마다 서버를 때린다(무료 플랜 예산이 그 자리에서 샌다).
        let theirs = "chess_state__ok_initial_their_turn"     // 상대 차례 = 폴링이 돌아야 하는 분기
        let (store, host) = makeChessStore("poll", me: try csCaller(theirs),
                                           handler: csHandler(["chess_state": [try csText(theirs)]]))
        await store.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1)
        let baseline = GomokuStubProtocol.count(host: host, rpc: "chess_state")
        let later = store.clock().addingTimeInterval(600)

        // ① 창이 안 보인다 → 한 건도 안 나간다.
        store.isWindowVisible = false
        await store.pollTick(at: later)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == baseline)

        // ② 창은 보이지만 **가려졌다** → 역시 안 나간다.
        store.isWindowVisible = true
        store.windowOcclusionDidChange(visible: false)
        await store.pollTick(at: later)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == baseline)
        #expect(store.pollTask == nil, "가려졌는데 폴링 루프가 살아 있다")

        // ③ 보이고 안 가려졌다 → 나간다(여기서 안 나가면 ①②가 아무것도 재지 않는다).
        store.windowOcclusionDidChange(visible: true)
        await store.pollTick(at: later)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == baseline + 1)
        #expect(store.pollTask != nil)
        store.stopPolling()
    }

    // MARK: - ⑧ 시계는 서버 값으로 덮어써진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func serverClockOverwritesInterpolatedValues() async throws {
        // 없으면: 클라가 센 초를 기준선으로 쥐고 서버 값을 '보정' 해도 초록이다 — 그러면 기기가 잠들었다 깨어난 뒤
        // 화면이 남았다고 말하는 시간에 깃발이 떨어진다.
        let name = "chess_state__ok_mid_since0"
        let first = try csJSON(name)
        let firstMatch = try #require(first["match"] as? [String: Any])
        #expect(firstMatch["white_ms_left"] as? Int == 308_770)

        // 두 번째 응답: **같은 봉투**에 시계 셋만 서버가 줄여 보낸 모양(수가 한 수 더 진행됐다).
        var second = first
        var secondMatch = firstMatch
        secondMatch["white_ms_left"] = 12_345
        secondMatch["black_ms_left"] = 67_890
        secondMatch["turn_started_ms"] = (firstMatch["turn_started_ms"] as! Double) + 5_000
        second["match"] = secondMatch
        second["state"] = nil
        second.removeValue(forKey: "state")

        let (store, _) = makeChessStore(
            "clock", me: try csCaller(name),
            handler: csHandler(["chess_state": [try csText(name), csSerialize(second)]]))
        let matchID = "9a7156f6-f055-4590-ba98-f537ead0a600"
        await store.refreshMatch(id: matchID)

        let before = try #require(store.match)
        #expect(before.clock.whiteMsLeft == 308_770)
        #expect(before.clock.blackMsLeft == 308_875)
        let startedBefore = try #require(before.clock.turnStartedAt)
        #expect(abs(before.clock.remainingSeconds(.white, now: startedBefore) - 308.770) < 0.002)

        await store.refreshMatch(id: matchID)

        let after = try #require(store.match)
        // ★ 서버 값 **그대로**다(앞 값과 섞지도, 큰 쪽을 고르지도 않는다).
        #expect(after.clock.whiteMsLeft == 12_345)
        #expect(after.clock.blackMsLeft == 67_890)
        #expect(after.clock.whiteMsLeft != before.clock.whiteMsLeft)
        let startedAfter = try #require(after.clock.turnStartedAt)
        #expect(abs(startedAfter.timeIntervalSince(startedBefore) - 5) < 0.002)
        #expect(abs(after.clock.remainingSeconds(.white, now: startedAfter) - 12.345) < 0.002)
        // 보간은 그대로 돈다: 5초 뒤에는 차례쪽만 5초 줄었다.
        #expect(abs(after.clock.remainingSeconds(.white, now: startedAfter.addingTimeInterval(5)) - 7.345) < 0.002)
        #expect(abs(after.clock.remainingSeconds(.black, now: startedAfter.addingTimeInterval(5)) - 67.890) < 0.002)
        // 깃발 되묻기: 남은 시간 + 유예가 지나야 참이다(12.345초 + 2초).
        #expect(after.isFlagOverdue(now: startedAfter.addingTimeInterval(13), graceSeconds: 2) == false)
        #expect(after.isFlagOverdue(now: startedAfter.addingTimeInterval(15), graceSeconds: 2) == true)
    }

    // MARK: - ⑨ AI id 가 서버 경로를 **실제로** 막는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aiMatchNeverTouchesTheServerWhileTheSameActionsDoInPvP() async throws {
        // 없으면: AI 판의 id 로 `chess_state`·`chess_move` 가 서버에 나가 404 를 반복한다(오목 선례).
        let initial = "chess_state__ok_initial_my_turn"
        let (store, host) = makeChessStore(
            "ai", me: try csCaller(initial),
            handler: csHandler(["chess_state": [try csText(initial)],
                                "chess_move": [try csText("chess_move__ok_white_first")],
                                "chess_lobby": [try csText("chess_lobby__ok_empty")]]))
        store.aiRuntime.minimumThinkSeconds = 0
        // 결정적 가짜 엔진: 언제나 **첫 합법 수**(ChessRules 의 순서는 결정적이다).
        store.aiMoveChooser = { position, _ in ChessRules.legalMoves(in: position).first }
        store.isWindowVisible = true

        store.startAIMatch(humanColor: .white)
        let opened = try #require(store.match)
        #expect(store.isAIMatch)
        #expect(opened.id.hasPrefix(ChessAIGame.idPrefix))
        #expect(store.phase == .playing)
        #expect(opened.myColor == .white)
        #expect(opened.turn == .white)
        #expect(opened.stake == 0)
        #expect(opened.opponent.characterID == "robot")
        // ★ AI 판에서는 **로컬 규칙**이 하이라이트를 만든다(1:1 과 정반대 — ChessStore 머리말 ⑦).
        #expect(opened.legalMoves.count == 20)
        let openedPosition = try #require(opened.position)
        #expect(opened.legalMoves.map(\.uci).sorted()
                == ChessRules.legalMoves(in: openedPosition).map(\.uci).sorted())
        #expect(opened.clock.whiteMsLeft == 300_000)

        // 조회·폴링·착수 전부 서버로 안 나간다.
        await store.refreshMatch(id: opened.id)
        await store.refreshMatch()
        await store.pollTick(at: store.clock().addingTimeInterval(600))
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 0, "AI 판 id 로 상태 조회가 나갔다")

        await store.tap(try csSquare("e2"))
        await store.tap(try csSquare("e4"))
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_move") == 0, "AI 판의 수가 서버로 나갔다")
        // 로컬 판이 권위다: 사람 수 뒤 AI 가 한 수 둬 ply 2 가 되고 다시 사람 차례다.
        await csWait { store.match?.plyCount == 2 }
        let played = try #require(store.match)
        #expect(played.plyCount == 2)
        #expect(played.moves.first?.san == "e4")
        #expect(played.turn == .white)
        #expect(store.aiRuntime.chooserCalls == 1)
        // 피셔 가산이 붙었다(쓴 시간은 0 에 가깝고 +3초).
        #expect(played.clock.whiteMsLeft >= 300_000)
        #expect(played.clock.whiteMsLeft <= 303_000)

        // 무승부 합의는 AI 판에 없다(상대가 사람이 아니다) — 요청이 나가면 안 된다.
        await store.offerDraw()
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_offer_draw") == 0)

        // ★ 기준선 갈림: **같은 동작**이 1:1 판에서는 요청을 낸다.
        let (pvp, pvpHost) = makeChessStore(
            "ai-pvp", me: try csCaller(initial),
            handler: csHandler(["chess_state": [try csText(initial)],
                                "chess_move": [try csText("chess_move__ok_white_first")]]))
        await pvp.refreshMatch(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        await pvp.tap(try csSquare("e2"))
        await pvp.tap(try csSquare("e4"))
        #expect(GomokuStubProtocol.count(host: pvpHost, rpc: "chess_state") >= 1)
        #expect(GomokuStubProtocol.count(host: pvpHost, rpc: "chess_move") == 1)
    }

    // MARK: - ⑩ 로비 결과(상수 다섯 · 사람 목록 · 지금 대결 중)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func lobbyFixtureFillsConstantsPeopleAndLiveMatches() async throws {
        // 없으면: 로비 응답을 받아 두고 상수·전적·관전 목록을 하나도 안 옮겨도 초록이다.
        let name = "chess_lobby__ok_in_match"
        let initial = "chess_state__ok_initial_my_turn"
        let (store, host) = makeChessStore(
            name, me: try csCaller(name),
            handler: csHandler(["chess_lobby": [try csText(name)],
                                "chess_state": [try csText(initial)]]))
        await store.refreshLobby()

        #expect(store.hasLoadedLobby)
        #expect(!store.lobbyLoadFailed)
        // 서버 상수 다섯(판돈 셋은 ChessStake 가 든다).
        #expect(store.initialMs == 300_000)
        #expect(store.incrementMs == 3_000)
        #expect(store.graceMs == 2_000)
        #expect(ChessStake.allCases.map(\.rawValue) == [3, 5, 10])
        #expect(store.rubyBalance == 95)
        #expect(store.record == ChessRecord(wins: 0, losses: 0, draws: 0))

        // 사람 목록: 호출자(A)와 숨김 계정은 없고, capable 이 **양쪽 다** 있다.
        #expect(store.users.count == 9)
        #expect(!store.users.contains { $0.id == (try! csCaller(name)) }, "호출자 자신이 목록에 있다")
        #expect(!store.users.contains { $0.id == "785b5732-75fe-4a71-931a-2e3f06e63505" }, "숨김 계정이 샜다")
        #expect(store.users.contains { $0.isCapable })
        #expect(store.users.contains { !$0.isCapable })
        #expect(store.users.first { $0.id == "ee000000-0000-4000-8000-0000000000e5" }?.isCapable == false)
        // 근무 중은 B 한 사람이고, 정렬이 그 사람을 맨 앞에 세운다.
        #expect(store.users.filter(\.isWorking).map(\.id) == ["bb000000-0000-4000-8000-0000000000b2"])
        #expect(store.users.first?.id == "bb000000-0000-4000-8000-0000000000b2")
        #expect(store.users.first?.inMatch == true)

        // 지금 대결 중: 한 건 · 두 자리는 uuid 오름차순(색이 아니다).
        #expect(store.liveMatches.count == 1)
        let live = try #require(store.liveMatches.first)
        #expect(live.stake == .five)
        #expect(live.a.id < live.b.id)
        #expect(live.id == "9a7156f6-f055-4590-ba98-f537ead0a600")
        #expect(store.isMine(live), "내가 두고 있는 판인데 '내 판' 으로 안 읽힌다")

        // 진행 중 판이 있으면 그 판을 곧바로 불러온다(로비 한 번에 조회가 한 건 더 나간다).
        #expect(store.activeMatchID == live.id)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1)
        #expect(store.match?.id == live.id)
        #expect(store.phase == .playing)
    }

    // MARK: - ⑪ 순위 결과(독립 산식 · me.rank 양쪽 · 주 스위치)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func rankingMatchesIndependentFormulasAndTheSwitchGatesTheRequest() async throws {
        // 없으면: 서버 정렬이 바뀌어도, 순위 숫자가 틀려도, 폰이 1분마다 순위를 당겨도 초록이다.
        let ranked = "chess_ranking__ok_me_ranked"
        let unranked = "chess_ranking__ok_me_unranked"
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let (store, host) = makeChessStore(
            ranked, me: try csCaller(ranked),
            handler: csHandler(["chess_ranking": [try csText(ranked)]]))

        // 주 스위치가 꺼져 있으면 **요청이 한 건도 안 나간다**.
        #expect(!store.spectatorFeaturesEnabled)
        await store.loadRanking()
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_ranking") == 0)
        #expect(store.ranking == nil)

        // 켜면 나간다(여기서 안 나가면 위 0 이 아무것도 재지 않는다).
        store.spectatorFeaturesEnabled = true
        await store.loadRanking()
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_ranking") == 1)
        let board = try #require(store.ranking)
        #expect(store.hasLoadedRanking)
        #expect(!store.rankingLoadFailed)
        #expect(!store.rankingUnavailable)
        #expect(board.recordSince == nil, "컷이 -infinity 인데 캡션 날짜가 섰다")
        #expect(!board.entries.isEmpty)

        // 서버 순서 그대로 + 서버 규칙으로 정렬돼 있다.
        #expect(ChessRankingOrder.isSorted(board.entries))
        #expect(ChessRankingOrder.ranksMatchServerRule(board.entries))
        for entry in board.entries {
            // 승점 = 승 − 패(독립 산식).
            #expect(entry.points == entry.wins - entry.losses)
            // 순위 = 나보다 **엄격히 나은** 행 수 + 1 — 부호를 뒤집은 다른 식으로 센다.
            let key = ChessRankingOrder.Key(entry)
            let better = board.entries.filter {
                let other = ChessRankingOrder.Key($0)
                return !ChessRankingOrder.ties(other, key) && !ChessRankingOrder.precedes(key, other)
            }.count
            #expect(entry.rank == better + 1)
        }
        // 0판은 순위에 없다.
        #expect(!board.entries.contains { $0.wins + $0.losses + $0.draws == 0 })
        // ★ "C 는 순위에 없고 **로비에는 있다**" — 0판 제외가 사람을 지우는 게 아니라는 결과.
        let spectatorID = "cc000000-0000-4000-8000-0000000000c3"
        #expect(!board.entries.contains { $0.id == spectatorID })
        let lobby = try decoder.decode(ChessLobbyResponse.self, from: Data(try csText("chess_lobby__ok_in_match").utf8))
        #expect((lobby.users ?? []).contains { $0.userId == spectatorID })

        // ★ 기준선 갈림: me.rank 가 숫자인 응답과 null 인 응답이 다른 답을 낸다.
        let mine = try #require(board.me)
        #expect(mine.rank != nil)
        let other = ChessStore.rankingBoard(
            from: try decoder.decode(ChessRankingResponse.self, from: Data(try csText(unranked).utf8)))
        let otherMine = try #require(other.me)
        #expect(otherMine.rank == nil)
        #expect(mine.rank != otherMine.rank)
        #expect(otherMine.wins == 0)
    }

    // MARK: - ⑫ 관전은 phase 가 아니고 chess_state 를 안 쓴다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func watchFixtureStandsBesideTheLobbyWithoutMyColorOrState() async throws {
        // 없으면: 관전이 `chess_state` 를 재사용해 참가자 게이트에 걸리거나(관전자는 not_found 만 받는다),
        // 남의 판이 **대국 화면**으로 서 버린다.
        let watch = "chess_watch__ok_active"
        let lobbyName = "chess_lobby__ok_watch_entry"
        let (store, host) = makeChessStore(
            watch, me: try csCaller(watch),
            handler: csHandler(["chess_lobby": [try csText(lobbyName)],
                                "chess_watch": [try csText(watch)]]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        await store.refreshLobby()
        let matchID = "9a7156f6-f055-4590-ba98-f537ead0a600"
        let live = try #require(store.liveMatches.first { $0.id == matchID })
        #expect(!store.isMine(live), "관전자(C)가 그 판의 대국자로 읽혔다")

        store.startWatching(matchID: matchID)
        await csWait { store.spectating?.hasServerState == true }

        let seen = try #require(store.spectating)
        // 관전은 **phase 가 아니다** — 로비 자리에 선다.
        #expect(store.phase == .lobby)
        #expect(store.isSpectating)
        #expect(store.match == nil, "남의 판이 내 대국으로 섰다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 0, "관전이 chess_state 를 불렀다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == 1)

        // 흑·백은 서버가 말한 대로만 선다(로비 카드의 a/b 는 색이 아니다).
        let fixture = try csJSON(watch)
        let whiteRow = try #require(fixture["white_user"] as? [String: Any])
        let blackRow = try #require(fixture["black_user"] as? [String: Any])
        let seenWhite = try #require(seen.white)
        let seenBlack = try #require(seen.black)
        #expect(seenWhite.id == (whiteRow["user_id"] as? String))
        #expect(seenBlack.id == (blackRow["user_id"] as? String))
        #expect(seen.faces.map(\.id) == [live.a.id, live.b.id])
        #expect(seen.hasServerState)
        #expect(seen.stake == 5)

        // 판·기보·시계가 결과로 섰다.
        let row = try #require(fixture["match"] as? [String: Any])
        #expect(seen.fen == (row["fen"] as? String))
        let seenPosition = try #require(seen.position)
        #expect(seenPosition.fen == seen.fen)
        #expect(seen.plyCount == (row["ply_count"] as? Int))
        #expect(seen.moves.count == (fixture["moves"] as? [[String: Any]])?.count)
        #expect(seen.appliedSeq == seen.moves.last?.seq)
        let watchTurnText = try #require(row["turn"] as? String)
        #expect(seen.turn == ChessColor(rawValue: watchTurnText))
        #expect(seen.clock.whiteMsLeft == (row["white_ms_left"] as? Int))
        #expect(seen.clock.blackMsLeft == (row["black_ms_left"] as? Int))
        #expect(!seen.isFinished)
        #expect(seen.winner == nil)
        #expect(seen.endReason == nil)
        #expect(seen.isInCheck == (fixture["in_check"] as? Bool))

        // 내 판이 서면 관전은 내려가고 세대가 오른다(늦은 관전 응답이 되살리지 못한다).
        let generationBefore = store.watchRuntime.watchGeneration
        store.match = seen.position.map { position in
            ChessMatchState(
                id: "mine", stake: 5, myColor: .white, opponent: .chessAI, fen: position.fen,
                position: position, plyCount: 0, turn: .white, lastMove: nil, moves: [],
                clock: .initial, isInCheck: false, legalMoves: [], isFinished: false, outcome: nil,
                endReason: nil, rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
        }
        #expect(store.spectating == nil)
        #expect(store.watchRuntime.watchGeneration > generationBefore)
    }

    // MARK: - ⑬ 신청은 pending 상태 **한 경로**로 선다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func pendingStateBecomesAnInviteAndAcceptanceReplacesItWithTheMatch() async throws {
        // 없으면: 체스에 받은함 RPC 가 없다는 사실 때문에 신청이 화면에 영영 안 뜨거나(초인종을 못 받은 사람은
        // 대기 신청을 알 길이 없다), pending 판이 **대국 화면**으로 서 버린다.
        let base = "chess_state__ok_initial_their_turn"       // 호출자 B · 상대(challenger) A
        let accept = "chess_respond__accept_ok"
        let matchID = "9a7156f6-f055-4590-ba98-f537ead0a600"

        // pending 상태 픽스처는 없다(흐름이 수락부터 시작한다). 그래서 실제 봉투의 키를 그대로 쓰고
        // status·흑백·시계만 **서버가 pending 에 싣는 모양**으로 되돌린다(마이그레이션 §5.3: 흑백 추첨과
        // 시계 지급은 수락 순간이고 그 전에는 null 이다).
        var pending = try csJSON(base)
        var row = try #require(pending["match"] as? [String: Any])
        row["status"] = "pending"
        row["white"] = NSNull()
        row["black"] = NSNull()
        row["turn"] = NSNull()
        row["white_ms_left"] = NSNull()
        row["black_ms_left"] = NSNull()
        row["turn_started_ms"] = NSNull()
        row["deadline_ms"] = NSNull()
        row["started_ms"] = NSNull()
        row["invite_expires_ms"] = (try #require(pending["server_now_ms"] as? Double)) + 60_000
        pending["match"] = row
        pending["my_color"] = NSNull()
        pending["legal_moves"] = NSNull()
        pending["in_check"] = NSNull()
        pending.removeValue(forKey: "state")

        var arrived: [ChessInvite] = []
        let (store, _) = makeChessStore(
            "invite", me: try csCaller(base),
            handler: csHandler(["chess_state": [csSerialize(pending)],
                                "chess_respond": [try csText(accept)]]))
        store.onInviteArrived = { arrived.append($0) }
        await store.refreshMatch(id: matchID)

        // 판이 아니라 **신청**이 섰다.
        #expect(store.match == nil, "pending 판이 대국 화면으로 섰다")
        #expect(store.phase == .lobby)
        let invite = try #require(store.incoming)
        #expect(invite.id == matchID)
        #expect(invite.stake == 5)
        #expect(invite.peer.id == "aa000000-0000-4000-8000-0000000000a1")
        #expect(invite.peer.displayName == "체스예은")
        #expect(invite.expiresAt > store.clock())
        #expect(store.outgoing == nil, "받은 신청이 보낸 신청 자리에 섰다")
        #expect(arrived.map(\.id) == [matchID])
        #expect(store.visibleIncoming?.id == matchID)

        // 차단한 사람의 신청은 화면에서 걷힌다(코어 값은 그대로 둔다).
        store.hiddenPeerIDs = [invite.peer.id]
        #expect(store.visibleIncoming == nil)
        #expect(store.incoming != nil)
        store.hiddenPeerIDs = []

        // 수락하면 같은 id 가 판으로 바뀌고 신청 카드가 걷힌다.
        await store.respond(inviteID: matchID, accept: true)
        #expect(store.incoming == nil)
        let match = try #require(store.match)
        #expect(match.id == matchID)
        #expect(store.phase == .playing)
        #expect(match.myColor == .black)
        #expect(match.stake == 5)
        #expect(store.rubyBalance == 95, "수락 뒤 잔액이 응답 값(95)이 아니다")
        #expect(store.notice == nil, "수락 성공을 안내줄로 말했다(판이 열리는 것이 답이다)")

        // ★ 기준선 갈림: 같은 봉투에서 status 만 pending → active 로 바뀌면 답이 신청에서 판으로 바뀐다.
        let (other, _) = makeChessStore("invite-active", me: try csCaller(base),
                                        handler: csHandler(["chess_state": [try csText(base)]]))
        await other.refreshMatch(id: matchID)
        #expect(other.incoming == nil)
        #expect(other.match != nil)
    }

    // MARK: - ⑭ 주기: 오목보다 잦고, 하한을 지난다

    @Test
    @MainActor
    func pollIntervalsAreTighterThanGomokuButNeverBelowTheFloor() throws {
        // 없으면: 주기 상수를 0.1초로 줄여도(무료 플랜 예산을 통째로 태워도) 아무도 모른다.
        #expect(ChessStore.statePollFloorSeconds == 1.0)
        #expect(ChessStore.statePollSeconds(subscribed: true) == 1.5)
        #expect(ChessStore.statePollSeconds(subscribed: false) == 1.0)
        // 하한은 **코드가** 지킨다 — 상수를 잘못 줄여도 이 함수가 막는다.
        #expect(ChessStore.statePollSeconds(subscribed: true) >= ChessStore.statePollFloorSeconds)
        #expect(ChessStore.statePollSeconds(subscribed: false) >= ChessStore.statePollFloorSeconds)
        // ★ 기준선 갈림: 시계가 흐르므로 오목보다 촘촘하다(두 값이 같아지면 이 단언이 빨개진다).
        #expect(ChessStore.statePollSecondsWhileSubscribed < GomokuStore.statePollSecondsWhileSubscribed)
        #expect(ChessStore.statePollSecondsUnsubscribed < GomokuStore.statePollSecondsUnsubscribed)
        // 구독 중이 더 느리다(신호가 있으니 덜 묻는다).
        #expect(ChessStore.statePollSeconds(subscribed: true) > ChessStore.statePollSeconds(subscribed: false))
        // 나머지 주기는 오목과 같은 눈금이다(두 창이 서로를 설명할 수 있게).
        #expect(ChessStore.watchPollSeconds == GomokuStore.watchPollSeconds)
        #expect(ChessStore.rankingPollSeconds == GomokuStore.rankingPollSeconds)
        #expect(ChessStore.lobbyPollSeconds == GomokuStore.lobbyPollSeconds)
        #expect(ChessStore.outgoingPollSeconds == 5)
        #expect(ChessStore.flagGraceSeconds == 2)
    }

    // MARK: - ⑮ 서버가 없는 창(PGRST202)은 상태가 아니라 throw 로 온다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func missingServerFunctionsFoldIntoOneNoticeAndLockTheWatchGate() async throws {
        // 없으면: db push 전 창에서 [관전] 칩이 활성인 채로 남아 누를 때마다 404 왕복을 반복한다(오목 실측).
        let (store, host) = makeChessStore("pgrst", me: "aa000000-0000-4000-8000-0000000000a1",
                                           handler: csHandler([:]))   // 무엇을 물어도 PGRST202
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true

        await store.refreshLobby()
        #expect(store.notice == ChessNoticeText.unavailable)
        #expect(store.lobbyLoadFailed)
        #expect(!store.hasLoadedLobby, "못 받은 로비를 받은 것으로 셌다")

        await store.loadRanking()
        #expect(store.rankingUnavailable)
        #expect(!store.rankingLoadFailed)
        #expect(store.hasLoadedRanking, "순위를 영영 로딩 문구로 두면 화면이 멈춘다")

        // 관전은 세 번 실패 전에 **404 증거 한 번**으로 곧바로 잠긴다.
        store.spectating = ChessSpectateState(id: "9a7156f6-f055-4590-ba98-f537ead0a600")
        await store.refreshWatch()
        #expect(store.watchUnavailable)
        #expect(store.spectating == nil)
        #expect(store.notice == ChessNoticeText.unavailable)
        let watchCalls = GomokuStubProtocol.count(host: host, rpc: "chess_watch")
        // 잠긴 뒤에는 입구가 **문 앞에서** 막는다(요청이 더 안 나간다).
        store.startWatching(matchID: "9a7156f6-f055-4590-ba98-f537ead0a600")
        #expect(store.spectating == nil)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == watchCalls)
        // 주기가 한 번 풀어 준다(안 풀면 서버가 올라와도 로그아웃까지 잠긴 채 남는다).
        await store.pollSpectatorFeatures(at: store.clock().addingTimeInterval(600))
        #expect(!store.watchUnavailable)
    }

    // MARK: - ⑯ 관전 세대: 앞 판의 늦은 실패가 **지금 보는 판**을 내리지 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func staleWatchFailureDoesNotTearDownTheMatchBeingWatchedNow() async throws {
        // 없으면: 판을 바꿔 관전하는 순간 앞 판의 나가 있던 5xx 가 돌아와 **새 판**의 실패 장부에 얹히고,
        // 문턱(3)에 닿으면 멀쩡한 관전이 "연결을 확인해 주세요" 와 함께 통째로 내려간다.
        // 2026-10-05 뮤테이션 실측: `refreshWatch` 의 세대 대조 두 줄을 빼도 V0343 체스 27건이 전부 초록이었다 —
        // 기존 시험은 세대 **숫자가 올랐는가**(모양)만 봤고 늦은 응답이 무엇을 하는가(결과)를 안 봤다.
        let first = "9a7156f6-f055-4590-ba98-f537ead0a600"
        let second = "c0de0000-0000-4000-8000-0000000000b2"
        let (store, host) = makeChessStore(
            "watch-stale", me: try csCaller("chess_watch__ok_active"),
            handler: { rpc, _, _ in
                guard rpc == "chess_watch" else { return GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
                return GomokuStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#, delay: 0.3)
            })
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true

        store.startWatching(matchID: first)
        // 요청이 실제로 나간 뒤에 판을 바꾼다 — 안 나갔으면 이 시험은 아무것도 재지 않는다.
        await csWait { GomokuStubProtocol.count(host: host, rpc: "chess_watch") == 1 }
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == 1)

        // 창을 내려 두고 바꾼다(바꾸는 순간 새 조회가 나가면 늦은 응답이 어느 조회의 것인지 흐려진다).
        store.isWindowVisible = false
        store.startWatching(matchID: second)
        #expect(store.spectating?.id == second)
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_watch") == 1, "판을 바꾸며 새 조회가 나갔다")
        // 새 판의 장부를 문턱 한 칸 앞에 둔다 — 앞 판의 실패 하나가 얹히면 곧바로 내려간다.
        store.watchRuntime.watchFailureStreak = ChessStore.watchFailureLimit - 1
        for _ in 0..<200 { try? await Task.sleep(for: .milliseconds(5)) }

        #expect(store.spectating?.id == second, "앞 판의 늦은 실패가 지금 보는 판을 내렸다")
        #expect(store.notice != ChessNoticeText.checkConnection)
        #expect(store.watchRuntime.watchFailureStreak == ChessStore.watchFailureLimit - 1,
                "앞 판의 실패가 새 판의 장부에 얹혔다")

        // ★ 기준선 갈림: **같은 응답**이 세대가 그대로일 때는 실제로 판을 내린다(그래야 위 셋이 뜻을 가진다).
        let (live, _) = makeChessStore(
            "watch-live", me: try csCaller("chess_watch__ok_active"),
            handler: { rpc, _, _ in
                guard rpc == "chess_watch" else { return GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
                return GomokuStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
            })
        live.spectatorFeaturesEnabled = true
        live.spectating = ChessSpectateState(id: second)
        live.watchRuntime.watchFailureStreak = ChessStore.watchFailureLimit - 1
        await live.refreshWatch()
        #expect(live.spectating == nil, "세대가 그대로인 실패가 판을 안 내리면 위 단언들이 영원히 초록이다")
        #expect(live.notice == ChessNoticeText.checkConnection)
    }

    // MARK: - ⑰ AI 세대: 1:1 이 서는 순간 늦게 끝난 계산은 **내려앉지 않는다**

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func lateEngineResultNeverLandsAfterTheAIGameWasReplaced() async throws {
        // 없으면: AI 가 생각하는 중에 1:1 판이 수락돼 열리면, 늦게 끝난 AI 수가 **사람의 1:1 판**이나
        // 버려진 로컬 판에 내려앉는다(오목에서 같은 자리를 세대로 막았다).
        let initial = "chess_state__ok_initial_my_turn"
        let (store, host) = makeChessStore(
            "ai-stale", me: try csCaller(initial),
            handler: csHandler(["chess_state": [try csText(initial)]]))
        store.isWindowVisible = true
        store.aiRuntime.minimumThinkSeconds = 0
        // 느린 가짜 엔진: 생각이 끝나기 **전에** 판이 바뀐다.
        store.aiMoveChooser = { position, _ in
            try? await Task.sleep(for: .milliseconds(300))
            return ChessRules.legalMoves(in: position).first
        }

        store.startAIMatch(humanColor: .black)      // AI 가 백 — 곧바로 생각에 들어간다
        let opened = try #require(store.aiGame)
        #expect(store.isAIThinking)
        #expect(opened.plyCount == 0)
        await csWait { store.aiRuntime.chooserCalls == 1 }
        #expect(store.aiRuntime.chooserCalls == 1, "엔진이 안 불렸으면 이 시험은 아무것도 재지 않는다")

        // 생각하는 중에 1:1 판이 선다 — `match.didSet` 이 AI 판을 버린다.
        let pvpFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let pvpPosition = try #require(ChessPosition(fen: pvpFEN))
        store.match = ChessMatchState(
            id: "pvp-stands", stake: 5, myColor: .white, opponent: .chessAI, fen: pvpFEN,
            position: pvpPosition, plyCount: 0, turn: .white, lastMove: nil, moves: [],
            clock: .initial, isInCheck: false, legalMoves: [], isFinished: false, outcome: nil,
            endReason: nil, rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
        #expect(store.aiGame == nil, "1:1 판이 섰는데 AI 판이 남았다")
        #expect(!store.isAIMatch)
        for _ in 0..<200 { try? await Task.sleep(for: .milliseconds(5)) }

        // 늦게 끝난 계산이 아무것도 못 바꾼다 — 1:1 판의 수 번호·FEN 이 그대로고 AI 판은 돌아오지 않는다.
        let stillPvP = try #require(store.match)
        #expect(stillPvP.id == "pvp-stands")
        #expect(stillPvP.plyCount == 0, "늦은 AI 수가 1:1 판을 움직였다")
        #expect(stillPvP.fen == pvpFEN)
        #expect(store.aiGame == nil, "버린 AI 판이 늦은 계산으로 되살아났다")
        #expect(store.aiRuntime.chooserCalls == 1, "엔진을 한 번 더 불렀다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "chess_move") == 0)

        // ★ 기준선 갈림: **같은 엔진**이 판을 안 바꿨을 때는 실제로 수를 둔다(그래야 위 ply 0 이 뜻을 가진다).
        let (keeps, _) = makeChessStore("ai-lands", me: try csCaller(initial),
                                        handler: csHandler(["chess_state": [try csText(initial)]]))
        keeps.isWindowVisible = true
        keeps.aiRuntime.minimumThinkSeconds = 0
        keeps.aiMoveChooser = { position, _ in
            try? await Task.sleep(for: .milliseconds(300))
            return ChessRules.legalMoves(in: position).first
        }
        keeps.startAIMatch(humanColor: .black)
        await csWait { keeps.aiGame?.plyCount == 1 }
        let landed = try #require(keeps.aiGame)
        #expect(landed.plyCount == 1, "안 바뀐 판에도 수가 안 내려앉으면 위 단언들이 영원히 초록이다")
        #expect(landed.turn == .black)
        #expect(keeps.match?.plyCount == 1)
        #expect(stillPvP.plyCount != landed.plyCount)
    }
}
