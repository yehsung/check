import Foundation
import Testing
@testable import CheckCore

// v0.3.44 — 체스 RPC 응답 **계약**: 서버가 실제로 낸 jsonb ↔ 마이그레이션이 박아 둔 봉투 키 집합 ↔ Swift 엔진의 독립 산식.
//
// 픽스처 `Fixtures/chess-rpc/*.json` 은 스텁 추측이 아니다. 체인 109개 + `20261005140000_chess_rules.sql` +
// `20261005160000_chess_duel.sql` 을 올린 **전용** 로컬 Postgres(사본·전용 포트)에 `harness.login` 으로 PostgREST
// 모양 authenticated 흉내를 내고 **RPC 를 실제로 불러** 나온 jsonb 를 그대로 적은 것이다 — 합성 계정 여섯으로
// e4 e5 Nf3 Nc6 Bb5 Nf6 를 실제로 두고 무승부 제안·기권까지 갔다. 종국 넷(외통 · 시간패 · FIDE 6.9 무승부 ·
// 3회 반복)은 판을 표에 직접 심고 그 위에서 **실제 수**를 둬 끝냈다.
// 생성기는 `_gen_fixtures.py.txt`, 호출자·인자·준비 SQL·깃발 쪽·심은 판의 출발 국면은 `_manifest.json` 에 있다(2026-10-05 실측).
//
// 이 파일이 재는 것 다섯:
//  ① 매니페스트 — 디스크의 픽스처 집합과 매니페스트·기대 status 표가 같고, 파일 이름의 RPC 가 실제 호출문과 같은가
//     (없으면 누가 손으로 json 을 고쳐 넣어도 — 서버가 못 내는 모양이어도 — 아무도 모른다)
//  ② 봉투 키 집합 — 마이그레이션 §11 의 `v_*_keys` 가 박아 둔 **정확 집합**과 같은가
//     (키가 늘기만 하면 디코더는 무사하지만, 줄면 그 자리에서 화면이 빈다)
//  ③ ★ **독립 산식** — `match.fen` 을 `ChessPosition(fen:)` 으로 읽어 서버가 준 `turn`·`ply_count`·`in_check`·
//     `legal_moves` 와 맞는가. **체스에서 가장 값진 계약**이다: 서버와 클라가 같은 판을 보는지를 재는 자리이고,
//     어긋나면 "앱은 둘 수 있다는데 서버가 거절한다" 가 된다
//  ④ 수 기록 왕복 — `moves[]` 의 `from`·`to`·`promo`·`san`·`fen` 을 Swift 가 직전 국면에 그 수를 적용해 재현하는가,
//     그리고 피셔 시계(남은 − 쓴 + 가산)가 산수로 맞는가
//  ⑤ 종국 — 외통 · 시간패 · FIDE 6.9 · 3회 반복을 `ChessRules.outcome` · `ChessRules.timeoutRuling` · 수순 재생으로
//     **다시 판정해** 서버의 `outcome`·`result`·`end_reason`·`repetition` 과 맞추는가
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가" 다.
//
// ★ 기준선이 갈리는지 **실측으로** 확인했다(두 분기가 동시에 참인 입력이 없으면 그 단언은 영원히 초록이다):
//   · `in_check` — true(`chess_state__ok_in_check`) · false(초기 국면) · null(끝난 판) 셋이 다 있다
//   · `legal_moves` — 20개(초기) · 3개(체크) · null(상대 차례 · 끝난 판)
//   · `promo` — "q"(`chess_move__ok_promotion`) · null(나머지 전부)
//   · `turn` — white · black 둘 다, `ply_count` — 0 · 1 · 6 · 8 · 58 · 78 · 79 · 99 · 118
//   · `result` — white_win · draw · null, 무승부 사유 넷 + 패배 사유 셋
//   아래 §마지막 시험이 이 갈림을 **단언으로** 못 박는다 — 갈림이 사라지면 그 자리가 빨개진다.

// MARK: - 기대 키 집합 (마이그레이션 §11 의 v_*_keys 를 베껴 적은 것)

/// 상태를 싣는 응답의 **최상위 공통 키**. `chess__state` 의 열 키 + status.
private let chessStateKeys: Set<String> = ["in_check", "legal_moves", "match", "moves", "my_color",
                                           "opponent", "ruby_balance", "server_now_ms", "state", "status"]
private let chessMatchKeys: Set<String> = ["black", "black_grace_ms", "black_ms_left", "challenger",
                                           "deadline_ms", "draw_offer_by", "end_reason", "fen", "finished_ms",
                                           "id", "increment_ms", "invite_expires_ms", "opponent", "ply_count",
                                           "result", "stake", "started_ms", "status", "turn", "turn_started_ms",
                                           "white", "white_grace_ms", "white_ms_left", "winner"]
private let chessMoveKeys: Set<String> = ["color", "fen", "from", "ms_left", "ms_spent", "promo", "san",
                                          "seq", "to"]
private let chessLobbyKeys: Set<String> = ["grace_ms", "increment_ms", "initial_ms", "invite_ttl_seconds",
                                           "matches", "me", "ruby_balance", "server_now_ms", "stakes",
                                           "status", "users"]
private let chessLobbyMeKeys: Set<String> = ["active_match_id", "draws", "incoming_match_id", "losses",
                                             "outgoing_match_id", "ruby_balance", "wins"]
/// 로비의 "지금 대결 중" 한 줄. **fen·ply_count 가 없어야 한다**(§10 이 소스로, 여기가 결과로 막는다).
private let chessLobbyMatchKeys: Set<String> = ["a", "b", "match_id", "stake", "started_ms"]
private let chessLobbyUserKeys: Set<String> = ["avatar_url", "capable", "center", "character", "display_name",
                                               "in_match", "is_working", "user_id"]
private let chessWatchKeys: Set<String> = ["black_user", "in_check", "match", "moves", "server_now_ms",
                                           "status", "white_user"]
/// 관전의 match — 참가자용에서 `invite_expires_ms` 하나가 빠진다(관전은 신청을 보지 않는다).
private let chessWatchMatchKeys: Set<String> = chessMatchKeys.subtracting(["invite_expires_ms"])
private let chessRankingKeys: Set<String> = ["me", "record_since_ms", "rows", "server_now_ms", "status"]
private let chessRankingRowKeys: Set<String> = ["avatar_url", "center", "character", "display_name", "draws",
                                                 "losses", "points", "rank", "user_id", "wins"]
private let chessPeerKeys: Set<String> = ["avatar_url", "center", "character", "display_name", "user_id"]

/// 상태 봉투에 **더 붙는** 키. 갈래마다 정확히 이것만 더 붙어야 한다.
private let chessStateExtraKeys: [String: Set<String>] = [
    "chess_respond__accept_ok": ["accepted"],
    "chess_respond_draw__accept_ok": ["accepted"],
    "chess_respond_draw__decline_ok": ["accepted"],
    "chess_move__ok_white_first": ["san", "outcome", "repetition"],
    "chess_move__ok_black_reply": ["san", "outcome", "repetition"],
    "chess_move__ok_white_mid": ["san", "outcome", "repetition"],
    "chess_move__ok_promotion": ["san", "outcome", "repetition"],
    "chess_move__end_checkmate": ["san", "outcome", "repetition"],
    "chess_move__end_threefold": ["san", "outcome", "repetition"],
    "chess_move__end_insufficient": ["san", "outcome", "repetition"],
    "chess_move__illegal": ["uci"],
    "chess_move__retry_clock_skew": ["reason"]
]

/// 각 픽스처가 **내야 하는 status**. 손으로 적은 표다 — 서버가 다른 글자를 내면 여기서 걸린다.
/// (픽스처를 더하면 이 표가 "그 상황이 무엇을 내야 하는가" 를 한 번 결정하게 만든다 — 집합 단언이 강제한다.)
private let chessExpectedStatus: [String: String] = [
    "chess_cancel__not_found": "not_found",
    "chess_cancel__not_pending": "not_pending",
    "chess_cancel__ok": "ok",
    "chess_cancel__unsupported_client": "unsupported_client",
    "chess_challenge__already_pending": "already_pending",
    "chess_challenge__busy": "busy",
    "chess_challenge__insufficient": "insufficient",
    "chess_challenge__invalid": "invalid",
    "chess_challenge__invalid_hidden": "invalid",
    "chess_challenge__ok": "ok",
    "chess_challenge__target_busy": "target_busy",
    "chess_challenge__target_focused": "target_focused",
    "chess_challenge__target_outdated": "target_outdated",
    "chess_challenge__unsupported_client": "unsupported_client",
    "chess_lobby__ok_empty": "ok",
    "chess_lobby__ok_in_match": "ok",
    "chess_lobby__ok_pending_in": "ok",
    "chess_lobby__ok_pending_out": "ok",
    "chess_lobby__ok_watch_entry": "ok",
    "chess_lobby__unauthorized": "unauthorized",
    "chess_lobby__unsupported_client": "unsupported_client",
    "chess_move__end_checkmate": "ok",
    "chess_move__end_insufficient": "ok",
    "chess_move__end_threefold": "ok",
    "chess_move__illegal": "illegal",
    "chess_move__not_active": "not_active",
    "chess_move__not_your_turn": "not_your_turn",
    "chess_move__ok_black_reply": "ok",
    "chess_move__ok_promotion": "ok",
    "chess_move__ok_white_first": "ok",
    "chess_move__ok_white_mid": "ok",
    "chess_move__retry_clock_skew": "retry",
    "chess_move__stale": "stale",
    "chess_move__unsupported_client": "unsupported_client",
    "chess_offer_draw__offer_pending": "offer_pending",
    "chess_offer_draw__ok": "ok",
    "chess_offer_draw__ok_idempotent": "ok",
    "chess_offer_draw__unsupported_client": "unsupported_client",
    "chess_ranking__ok_hidden_empty": "ok",
    "chess_ranking__ok_me_ranked": "ok",
    "chess_ranking__ok_me_unranked": "ok",
    "chess_ranking__unauthorized": "unauthorized",
    "chess_ranking__unsupported_client": "unsupported_client",
    "chess_resign__not_active": "not_active",
    "chess_resign__ok": "ok",
    "chess_resign__unsupported_client": "unsupported_client",
    "chess_respond__accept_ok": "ok",
    "chess_respond__decline_ok": "ok",
    "chess_respond__expired": "expired",
    "chess_respond__not_found": "not_found",
    "chess_respond__not_pending": "not_pending",
    "chess_respond__unsupported_client": "unsupported_client",
    "chess_respond_draw__accept_ok": "ok",
    "chess_respond_draw__decline_ok": "ok",
    "chess_respond_draw__no_offer": "no_offer",
    "chess_respond_draw__unsupported_client": "unsupported_client",
    "chess_state__end_timeout": "ok",
    "chess_state__end_timeout_insufficient": "ok",
    "chess_state__not_found": "not_found",
    "chess_state__ok_in_check": "ok",
    "chess_state__ok_initial_my_turn": "ok",
    "chess_state__ok_initial_their_turn": "ok",
    "chess_state__ok_mid_since0": "ok",
    "chess_state__ok_mid_since4": "ok",
    "chess_state__unsupported_client": "unsupported_client",
    "chess_watch__not_found": "not_found",
    "chess_watch__not_found_hidden": "not_found",
    "chess_watch__not_found_old": "not_found",
    "chess_watch__not_found_pending": "not_found",
    "chess_watch__ok_active": "ok",
    "chess_watch__ok_as_player": "ok",
    "chess_watch__ok_in_check": "ok",
    "chess_watch__ok_seeded": "ok",
    "chess_watch__ok_since4": "ok",
    "chess_watch__ok_tail": "ok",
    "chess_watch__unauthorized": "unauthorized",
    "chess_watch__unsupported_client": "unsupported_client"
]

/// 무승부가 되는 사유 여섯(마이그레이션 CHECK 의 집합). `result = 'draw'` 와 **쌍방 iff** 여야 한다.
private let chessDrawReasons: Set<String> = ["stalemate", "fifty_move", "threefold", "insufficient_material",
                                             "agreement", "timeout_insufficient"]

// MARK: - 픽스처 도구

private struct ChessFxError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private let chessFxDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private func chessFxJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: chessFxDirectory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ChessFxError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func chessFxNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: chessFxDirectory.path)
        .filter { $0.hasPrefix("chess_") && $0.hasSuffix(".json") }
        .map { String($0.dropLast(5)) }
        .sorted()
}

private func chessFxManifest() throws -> [String: Any] { try chessFxJSON("_manifest") }

private func chessFxInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, !(value is NSNull) else { return nil }
    return number.intValue
}

private func chessFxKeys(_ value: Any?) -> Set<String> {
    guard let dictionary = value as? [String: Any] else { return [] }
    return Set(dictionary.keys)
}

/// `match.fen` 을 Swift 국면으로. 서버가 낸 FEN 이 **깐깐한 파서를 통과해야** 한다 —
/// 통과하지 않으면 앱은 그 판을 그릴 수조차 없다(그 자체가 가장 먼저 잡아야 하는 결함이다).
private func chessFxPosition(_ match: [String: Any], _ label: String) throws -> ChessPosition {
    guard let fen = match["fen"] as? String else { throw ChessFxError("\(label): match.fen 이 없다") }
    guard let position = ChessPosition(fen: fen) else {
        throw ChessFxError("\(label): 서버가 준 FEN 을 Swift 파서가 거절했다 — \(fen)")
    }
    return position
}

/// 상태(또는 관전) 봉투를 들고 있는 픽스처 전부: (이름, 최상위, match, 관전인가).
private func chessFxBoards() throws -> [(name: String, top: [String: Any], match: [String: Any], watch: Bool)] {
    var result: [(String, [String: Any], [String: Any], Bool)] = []
    for name in try chessFxNames() {
        let object = try chessFxJSON(name)
        guard let match = object["match"] as? [String: Any] else { continue }
        result.append((name, object, match, object["my_color"] == nil))
    }
    return result
}

/// FEN 이 말하는 "지금까지 둔 반수". `ply_count` 와 같아야 하는 값이고, 클라의 낙관적 동시성 토큰
/// (`p_expected_ply`)이 그 등식을 믿는다 — 어긋나면 모든 착수가 stale 로 떨어진다.
private func chessPlayedHalfmoves(_ position: ChessPosition) -> Int {
    (position.fullmoveNumber - 1) * 2 + (position.sideToMove == .white ? 0 : 1)
}

private func chessColor(_ text: Any?) -> ChessColor? {
    guard let text = text as? String else { return nil }
    return ChessColor(rawValue: text)
}

@Suite("체스 RPC 픽스처 계약 — 실제 SQL 출력 ↔ Swift 엔진")
struct V0343ChessFixtureContractTests {

    // MARK: - ① 매니페스트

    @Test("픽스처는 전부 매니페스트·status 표에 있고, 파일 이름의 RPC 가 실제 호출문과 같다")
    func manifestCoversEveryFixtureAndNamesMatchTheCall() throws {
        // 없으면: 누가 손으로 json 을 고쳐 넣어도(서버가 못 내는 모양이어도) 아무도 모른다 —
        // 매니페스트의 호출자·인자가 그 응답이 **어디서 왔는지** 말하고, status 표가 그 상황이 무엇을 내야 하는지 말한다.
        let onDisk = Set(try chessFxNames())
        let manifest = try chessFxManifest()
        let entries = try #require(manifest["fixtures"] as? [String: Any])
        #expect(Set(entries.keys) == onDisk, "매니페스트와 디스크가 다르다")
        #expect(Set(chessExpectedStatus.keys) == onDisk, "status 표와 디스크가 다르다")
        #expect(onDisk.count == 77, "픽스처 \(onDisk.count)개")

        for name in onDisk.sorted() {
            let entry = try #require(entries[name] as? [String: Any], "\(name): 매니페스트 항목 없음")
            let rpc = try #require(entry["rpc"] as? String, "\(name): rpc 없음")
            let family = try #require(name.components(separatedBy: "__").first, "\(name)")
            #expect(rpc.hasPrefix("public.\(family)("), "\(name): 파일 이름과 호출문이 다르다 — \(rpc)")
            #expect(["commit", "rollback"].contains(entry["end"] as? String ?? ""), "\(name): end")

            let object = try chessFxJSON(name)
            #expect(object["status"] as? String == chessExpectedStatus[name], "\(name): status")

            // 로그인하지 않은 호출은 **unauthorized 로만** 나온다(그 반대도 참이어야 한다).
            let anonymous = entry["caller"] is NSNull || entry["caller"] == nil
            #expect(anonymous == (chessExpectedStatus[name] == "unauthorized"),
                    "\(name): caller=null 과 unauthorized 가 짝이 아니다")
            // p_protocol 0 은 **반드시** unsupported_client 다(B10 — 옛 호출이 조용히 깨지지 않는다).
            if rpc.contains("(0,") || rpc.hasSuffix("(0)") {
                #expect(object["status"] as? String == "unsupported_client", "\(name): p_protocol 0")
                #expect(chessFxKeys(object) == ["status", "server_now_ms"], "\(name): unsupported 봉투")
            }
        }

        // 요구된 갈래가 **빠짐없이** 있는지(이 목록이 줄면 커버리지가 조용히 깎인다).
        let required = ["chess_lobby__ok_empty", "chess_lobby__ok_pending_out", "chess_lobby__ok_in_match",
                        "chess_challenge__ok", "chess_challenge__busy", "chess_challenge__insufficient",
                        "chess_respond__accept_ok", "chess_respond__decline_ok", "chess_respond__expired",
                        "chess_state__ok_initial_my_turn", "chess_state__ok_initial_their_turn",
                        "chess_state__ok_mid_since0",
                        "chess_move__ok_white_first", "chess_move__illegal", "chess_move__stale",
                        "chess_move__not_your_turn",
                        "chess_move__end_checkmate", "chess_state__end_timeout",
                        "chess_state__end_timeout_insufficient", "chess_move__end_threefold",
                        "chess_resign__ok", "chess_offer_draw__ok", "chess_respond_draw__accept_ok",
                        "chess_ranking__ok_me_ranked", "chess_ranking__ok_me_unranked",
                        "chess_watch__ok_active", "chess_watch__ok_tail", "chess_watch__not_found"]
        for name in required { #expect(onDisk.contains(name), "요구된 갈래 \(name) 이 없다") }
        // RPC 열하나 전부 unsupported_client 를 떴는가(하나라도 빠지면 그 RPC 의 B10 이 미검증이다).
        for family in ["chess_lobby", "chess_challenge", "chess_respond", "chess_cancel", "chess_move",
                       "chess_state", "chess_resign", "chess_offer_draw", "chess_respond_draw",
                       "chess_ranking", "chess_watch"] {
            #expect(onDisk.contains("\(family)__unsupported_client"), "\(family) 의 unsupported_client 가 없다")
        }
    }

    // MARK: - ② 봉투 키 집합

    @Test("상태 봉투의 키 집합이 마이그레이션 §11 이 박아 둔 정확 집합과 같고, state 중복 봉투가 최상위와 같다")
    func stateEnvelopeKeysMatchTheMigrationContract() throws {
        // 없으면: 키가 하나 빠져도(= 그 자리에서 화면이 빈다) 아무도 모른다. 늘기만 하면 디코더는 무사하지만
        // 줄면 조용히 빈다 — 그래서 **정확 집합**으로 잰다. state 중복 봉투는 "두 해석 다 디코드 가능" 의 근거라
        // 최상위와 **같은 내용**이어야 한다(한쪽만 고치면 두 디코더가 갈린다).
        var seen = 0
        for (name, top, match, isWatch) in try chessFxBoards() where !isWatch {
            seen += 1
            let extras = chessStateExtraKeys[name] ?? []
            #expect(chessFxKeys(top) == chessStateKeys.union(extras), "\(name): 최상위 키")
            #expect(chessFxKeys(match) == chessMatchKeys, "\(name): match 키")
            if let moves = top["moves"] as? [[String: Any]], let first = moves.first {
                #expect(chessFxKeys(first) == chessMoveKeys, "\(name): moves[] 키")
            }
            if top["opponent"] is [String: Any] {
                #expect(chessFxKeys(top["opponent"]) == chessPeerKeys, "\(name): opponent 키")
            }
            // state 중복 봉투 = 최상위에서 status·갈래별 추가 키를 뺀 것과 **같다**.
            let nested = try #require(top["state"] as? [String: Any], "\(name): state 없음")
            #expect(chessFxKeys(nested) == chessStateKeys.subtracting(["status", "state"]), "\(name): state 키")
            for key in chessFxKeys(nested) {
                let lhs = (top[key] as? NSObject) ?? NSNull()
                let rhs = (nested[key] as? NSObject) ?? NSNull()
                #expect(lhs == rhs, "\(name): state.\(key) 가 최상위와 다르다")
            }
        }
        #expect(seen == 28, "상태 봉투 픽스처 \(seen)개 — 줄면 어느 갈래가 사라진 것이다")
    }

    @Test("로비·관전·순위의 키 집합이 정확 집합과 같고, 관전은 참가자 전용 키를 안 싣는다")
    func lobbyWatchRankingKeysMatchTheMigrationContract() throws {
        // 없으면: 관전 응답에 legal_moves·ruby_balance 가 섞여 나가도(= 남의 지갑과 둘 수 있는 칸이 제3자에게 간다)
        // 모양만 보는 테스트는 초록이다. 로비는 **판 내용(fen·ply_count)** 을 실으면 관전 게이트가 장식이 된다.
        for name in try chessFxNames() {
            let object = try chessFxJSON(name)
            guard object["status"] as? String == "ok" else { continue }
            if name.hasPrefix("chess_lobby__") {
                #expect(chessFxKeys(object) == chessLobbyKeys, "\(name): 로비 키")
                #expect(chessFxKeys(object["me"]) == chessLobbyMeKeys, "\(name): me 키")
                for row in try #require(object["users"] as? [[String: Any]]) {
                    #expect(chessFxKeys(row) == chessLobbyUserKeys, "\(name): users[] 키")
                }
                for row in try #require(object["matches"] as? [[String: Any]]) {
                    #expect(chessFxKeys(row) == chessLobbyMatchKeys, "\(name): matches[] 키")
                    #expect(chessFxKeys(row["a"]) == chessPeerKeys, "\(name): matches[].a 키")
                    #expect(chessFxKeys(row["b"]) == chessPeerKeys, "\(name): matches[].b 키")
                }
            } else if name.hasPrefix("chess_watch__") {
                #expect(chessFxKeys(object) == chessWatchKeys, "\(name): 관전 키")
                #expect(chessFxKeys(object["match"]) == chessWatchMatchKeys, "\(name): 관전 match 키")
                for key in ["my_color", "legal_moves", "ruby_balance", "opponent", "state"] {
                    #expect(object[key] == nil, "\(name): 관전이 \(key) 를 실었다")
                }
                #expect(chessFxKeys(object["white_user"]) == chessPeerKeys, "\(name): white_user 키")
                #expect(chessFxKeys(object["black_user"]) == chessPeerKeys, "\(name): black_user 키")
            } else if name.hasPrefix("chess_ranking__") {
                #expect(chessFxKeys(object) == chessRankingKeys, "\(name): 순위 키")
                for row in try #require(object["rows"] as? [[String: Any]]) {
                    #expect(chessFxKeys(row) == chessRankingRowKeys, "\(name): rows[] 키")
                }
            }
        }
    }

    // MARK: - ③ 독립 산식 — 서버와 클라가 같은 판을 보는가

    @Test("match.fen 을 Swift 로 읽으면 서버가 준 turn·ply_count·in_check·legal_moves 와 **같다**")
    func serverBoardAgreesWithTheSwiftEngine() throws {
        // ★ 체스에서 가장 값진 계약이다. 없으면: 서버가 FEN 을 조금 다르게 적거나 차례를 칼럼으로 따로 들거나
        // 합법 수 목록을 다른 국면에서 만들어도 아무도 모르고, 사용자 화면에는 "둘 수 있다고 보여 준 수가
        // 거절되는" 모양으로 나온다. 서버 값(turn·in_check·legal_moves)을 **쓰지 않고** FEN 하나에서
        // 전부 다시 계산해 맞춘다 — 그래서 이것은 자기 확인이 아니라 두 구현의 대조다.
        var observedInCheck: Set<Bool?> = []
        var observedLegalCounts: Set<Int?> = []
        var observedTurns: Set<String> = []
        var observedPlies: Set<Int> = []
        var boards = 0

        for (name, top, match, isWatch) in try chessFxBoards() {
            boards += 1
            let position = try chessFxPosition(match, name)
            let status = try #require(match["status"] as? String, "\(name): match.status")

            // (a) 차례는 FEN 에서 파생한다(B6 — 따로 저장하면 갈린다).
            #expect(match["turn"] as? String == position.sideToMove.rawValue, "\(name): turn")
            observedTurns.insert(position.sideToMove.rawValue)

            // (b) ply_count 는 FEN 이 말하는 반수와 같다 — 클라의 stale 토큰이 이 등식을 믿는다.
            let ply = try #require(chessFxInt(match["ply_count"]), "\(name): ply_count")
            #expect(ply == chessPlayedHalfmoves(position), "\(name): ply_count \(ply) ↔ FEN \(match["fen"] ?? "")")
            observedPlies.insert(ply)

            // (c) in_check — 진행 중이면 Swift 판정과 같고, 끝난 판이면 **null** 이다.
            let serverCheck = top["in_check"] as? Bool
            if status == "active" {
                #expect(serverCheck == ChessRules.isInCheck(position), "\(name): in_check")
            } else {
                #expect(top["in_check"] is NSNull, "\(name): 끝난 판의 in_check 는 null 이어야 한다")
            }
            observedInCheck.insert(serverCheck)

            // (d) legal_moves — **내 차례일 때만** 싣고, 그 집합은 Swift 합법 수와 글자 그대로 같다.
            let mine = chessColor(top["my_color"])
            let myTurn = status == "active" && mine == position.sideToMove
            if isWatch {
                #expect(top["legal_moves"] == nil, "\(name): 관전에 legal_moves 가 있다")
                observedLegalCounts.insert(nil)
            } else if myTurn {
                let served = try #require(top["legal_moves"] as? [String], "\(name): legal_moves 가 없다")
                let computed = ChessRules.legalMoves(in: position).map(\.uci).sorted()
                #expect(served == computed, "\(name): legal_moves")
                #expect(!served.isEmpty, "\(name): 진행 중인 판에 합법 수가 없다")
                observedLegalCounts.insert(served.count)
            } else {
                #expect(top["legal_moves"] is NSNull, "\(name): 내 차례가 아닌데 legal_moves 를 실었다")
                observedLegalCounts.insert(nil)
            }

            // (e) 시계 봉투: deadline_ms 는 **표시값**(유예를 안 더한다) — 차례인 쪽의 남은 시간만 더한다.
            let left = chessFxInt(match["\(position.sideToMove.rawValue)_ms_left"])
            if status == "active" {
                let started = try #require(chessFxInt(match["turn_started_ms"]), "\(name): turn_started_ms")
                #expect(chessFxInt(match["deadline_ms"]) == started + (left ?? -1), "\(name): deadline_ms")
                #expect(chessFxInt(match["white_grace_ms"]) != nil && chessFxInt(match["black_grace_ms"]) != nil,
                        "\(name): 진행 중인 판에 유예 예산이 없다")
            } else {
                #expect(match["deadline_ms"] is NSNull, "\(name): 끝난 판의 deadline_ms 는 null 이다")
            }
            #expect(chessFxInt(match["increment_ms"]) == 3000, "\(name): 가산은 3초다(A3)")

            // (f) 결과 ⟺ 사유 쌍방 iff. 무승부 사유 여섯과 result='draw' 가 **서로를 함의**해야 한다.
            if let result = match["result"] as? String {
                let reason = try #require(match["end_reason"] as? String, "\(name): end_reason")
                #expect((result == "draw") == chessDrawReasons.contains(reason), "\(name): result ⟺ 사유")
                #expect(status == "finished", "\(name): 결과가 있는데 status 가 \(status) 다")
                if result == "draw" {
                    #expect(match["winner"] is NSNull, "\(name): 무승부에 승자가 있다")
                } else {
                    let winner = try #require(match["winner"] as? String, "\(name): winner")
                    let expected = result == "white_win" ? match["white"] as? String : match["black"] as? String
                    #expect(winner == expected, "\(name): winner 가 result 와 어긋난다")
                }
            } else {
                #expect(match["end_reason"] is NSNull && match["winner"] is NSNull, "\(name): 결과 없이 사유·승자")
            }
        }

        #expect(boards == 34, "판을 실은 픽스처 \(boards)개(상태 28 + 관전 6) — 줄면 어느 갈래가 사라진 것이다")
        // ★ 기준선: 위 단언들이 "null == null" 로 통과하지 않는다는 증거.
        #expect(observedInCheck == [true, false, nil], "in_check 의 세 갈래가 다 안 나왔다: \(observedInCheck)")
        #expect(observedLegalCounts.contains(nil) && observedLegalCounts.contains(20)
                && observedLegalCounts.contains(3),
                "legal_moves 의 갈림이 없다: \(observedLegalCounts)")
        #expect(observedTurns == ["white", "black"], "차례가 한쪽만 나왔다")
        #expect(observedPlies.count >= 6, "ply_count 가 \(observedPlies.count) 가지뿐이다")
    }

    // MARK: - ④ 수 기록 왕복 + 피셔 시계 산수

    @Test("수 기록의 from·to·promo·san·fen 은 직전 국면에 그 수를 적용한 결과와 같고, 시계는 산수로 맞는다")
    func moveRowsReplayExactlyAndTheFischerClockAddsUp() throws {
        // 없으면: 서버가 칸 번호를 다른 기준(a8=0)으로 적거나 SAN 을 자기 식으로 적거나 승격 글자를 흘려도
        // 아무도 모른다 — 기보 화면이 통째로 어긋나고, 승격 수는 "말이 바뀌지 않은 폰" 으로 그려진다.
        // 시계 산수가 없으면 "쓴 시간" 을 least(흐른, 남은) 으로 적은 사본(유예로 버틴 구간이 0 으로 사라진다)이 통과한다.
        let manifest = try chessFxManifest()
        let users = try #require(manifest["users"] as? [String: Any])
        let seeds = try #require(manifest["seeds"] as? [String: Any])
        let startFEN = try #require(users["threefold_start_fen"] as? String)
        var replayed = 0
        var promos: Set<String?> = []

        for (name, top, match, _) in try chessFxBoards() {
            guard let moves = top["moves"] as? [[String: Any]], !moves.isEmpty else { continue }
            let matchID = try #require(match["id"] as? String, "\(name): match.id")
            let firstSeq = try #require(chessFxInt(moves[0]["seq"]), "\(name): seq")

            // 출발 국면: 첫 수가 seq 1 이면 표준 시작 국면, 심은 판이면 매니페스트의 출발 FEN.
            var position: ChessPosition
            if let seed = seeds[matchID] as? [String: Any], let fen = seed["fen"] as? String,
               chessFxInt(seed["ply"]) == firstSeq - 1 {
                // ★ 심은 판을 **먼저** 본다. seq 1 이라고 표준 시작 국면이 아니다 — 외통 픽스처는 seq 1 이
                //   면서 출발 국면이 '6k1/5ppp/…' 다. 순서를 거꾸로 두면 그 수가 "합법 수 목록에 없다" 로 떨어진다.
                position = try #require(ChessPosition(fen: fen), "\(name): 심은 FEN")
            } else if firstSeq == 1 {
                position = try #require(ChessPosition(fen: startFEN), "시작 FEN")
            } else {
                continue        // since 가 0 이 아니어서 수 사슬이 끊긴 픽스처(§3 이 fen 한 칸을 따로 잰다)
            }

            // 피셔 시계: 초기 5분 · 한 수 3초 가산. 심은 판은 심은 값에서 출발한다.
            var remaining: [ChessColor: Int] = [.white: 300_000, .black: 300_000]
            if let seed = seeds[matchID] as? [String: Any] {
                remaining[.white] = chessFxInt(seed["white_ms_left"]) ?? 300_000
                remaining[.black] = chessFxInt(seed["black_ms_left"]) ?? 300_000
            }

            for row in moves {
                let seq = try #require(chessFxInt(row["seq"]), "\(name): seq")
                let color = try #require(chessColor(row["color"]), "\(name) seq\(seq): color")
                let from = try #require(ChessSquare(index: chessFxInt(row["from"]) ?? -1),
                                        "\(name) seq\(seq): from \(row["from"] ?? "")")
                let to = try #require(ChessSquare(index: chessFxInt(row["to"]) ?? -1), "\(name) seq\(seq): to")
                let promoText = row["promo"] as? String
                promos.insert(promoText)
                var promotion: ChessPieceKind?
                if let promoText {
                    #expect(promoText.count == 1, "\(name) seq\(seq): promo 는 소문자 한 글자다 — \(promoText)")
                    guard let letter = promoText.first, let kind = ChessPieceKind(fenLetter: letter) else {
                        throw ChessFxError("\(name) seq\(seq): 승격 글자가 말이 아니다 — \(promoText)")
                    }
                    // 고를 수 있는 말은 넷뿐이다(FIDE 3.7e) — 폰·킹이 오면 그 수는 체스가 아니다.
                    #expect(ChessPieceKind.promotionChoices.contains(kind), "\(name) seq\(seq): 고를 수 없는 말 \(kind)")
                    #expect(letter.isLowercase, "\(name) seq\(seq): 승격 글자는 소문자다")
                    promotion = kind
                }

                // (a) 둔 쪽은 **차례인 쪽**이다(상수로 박으면 모든 수가 백으로 찍힌다).
                #expect(color == position.sideToMove, "\(name) seq\(seq): color")
                #expect(seq == chessPlayedHalfmoves(position) + 1, "\(name) seq\(seq): seq ↔ 국면")

                // (b) 그 수는 이 국면의 합법 수 목록에 **있어야** 한다 — 없으면 서버가 불법 수를 기록한 것이다.
                let move = ChessMove(from: from, to: to, promotion: promotion)
                let legal = ChessRules.legalMoves(in: position)
                #expect(legal.contains(move), "\(name) seq\(seq): 기록된 수 \(move.uci) 가 합법 수 목록에 없다")

                // (c) SAN 과 적용 결과 FEN 을 Swift 가 혼자 만들어 맞춘다.
                let san = try #require(ChessRules.san(for: move, in: position), "\(name) seq\(seq): san")
                #expect(row["san"] as? String == san, "\(name) seq\(seq): san")
                let after = try #require(ChessRules.apply(move, to: position), "\(name) seq\(seq): apply")
                #expect(row["fen"] as? String == after.fen, "\(name) seq\(seq): fen")

                // (d) 피셔 시계: 남은 − 쓴(0 에서 끊고) + 가산. 쓴 시간은 **흐른 시간 그대로**다.
                let spent = try #require(chessFxInt(row["ms_spent"]), "\(name) seq\(seq): ms_spent")
                let left = try #require(chessFxInt(row["ms_left"]), "\(name) seq\(seq): ms_left")
                #expect(spent >= 0, "\(name) seq\(seq): 쓴 시간이 음수다")
                let expected = max((remaining[color] ?? 0) - spent, 0) + 3000
                #expect(left == expected,
                        "\(name) seq\(seq): ms_left \(left)(기대 \(expected) = \(remaining[color] ?? 0) − \(spent) + 3000)")
                remaining[color] = left

                position = after
                replayed += 1
            }

            // (e) 사슬의 끝은 match.fen 과 같아야 한다 — 판의 권위는 match.fen 하나다.
            #expect(match["fen"] as? String == position.fen, "\(name): 수 사슬의 끝이 match.fen 과 다르다")
        }

        #expect(replayed >= 20, "재생한 수가 \(replayed)개뿐이다")
        #expect(promos.contains("q") && promos.contains(nil), "승격 기준선이 갈리지 않는다: \(promos)")
    }

    // MARK: - ⑤ 종국 넷 — Swift 가 다시 판정한다

    @Test("외통·불충분 기물·3회 반복을 Swift 가 다시 판정해도 서버의 outcome·result·사유와 같다")
    func endgameOutcomesAgreeWithTheSwiftRuleset() throws {
        // 없으면: 서버의 판정 **순서**가 FIDE 9.3 과 어긋나도(100번째 반수의 메이트를 무승부로 적어도) 모른다.
        // repetition 숫자는 서버 값을 쓰지 않고 수순을 **직접 재생해** 센다 — 안 그러면 서버가 1 을 줘도 통과한다.
        let manifest = try chessFxManifest()
        let users = try #require(manifest["users"] as? [String: Any])

        // (1) 외통 — FIDE 9.3: 수가 없고 체크면 메이트다.
        let mate = try chessFxJSON("chess_move__end_checkmate")
        let mateMatch = try #require(mate["match"] as? [String: Any])
        let matePosition = try chessFxPosition(mateMatch, "end_checkmate")
        #expect(ChessRules.outcome(position: matePosition) == .checkmate(winner: .white))
        #expect(mate["outcome"] as? String == "checkmate:white")
        #expect(mate["san"] as? String == "Ra8#", "서버 SAN 이 \(mate["san"] ?? "") 다")
        #expect(mateMatch["result"] as? String == "white_win")
        #expect(mateMatch["end_reason"] as? String == "checkmate")
        #expect(ChessRules.legalMoves(in: matePosition).isEmpty && ChessRules.isInCheck(matePosition))

        // (2) 불충분 기물 — **사국**(판 전체)이다. 체크를 주면서 무승부가 되는 자리라 순서가 드러난다.
        let insufficient = try chessFxJSON("chess_move__end_insufficient")
        let insufficientMatch = try #require(insufficient["match"] as? [String: Any])
        let insufficientPosition = try chessFxPosition(insufficientMatch, "end_insufficient")
        #expect(ChessRules.hasInsufficientMaterial(insufficientPosition))
        #expect(ChessRules.outcome(position: insufficientPosition) == .insufficientMaterial)
        #expect(insufficient["outcome"] as? String == "insufficient_material")
        #expect(insufficientMatch["result"] as? String == "draw")
        #expect(insufficientMatch["end_reason"] as? String == "insufficient_material")
        // 기준선: 메이트가 **먼저**다. 이 국면은 체크지만 수가 있어 메이트가 아니다 — 그래서 무승부로 떨어진다.
        #expect(ChessRules.isInCheck(insufficientPosition))
        #expect(!ChessRules.legalMoves(in: insufficientPosition).isEmpty)

        // (3) 3회 반복 — 수순을 **재생해 직접 센다**(서버의 repetition 을 입력으로 쓰지 않는다).
        let threefold = try chessFxJSON("chess_move__end_threefold")
        let threefoldMatch = try #require(threefold["match"] as? [String: Any])
        let line = try #require(users["threefold_line"] as? [String])
        let threefoldStart = try #require(users["threefold_start_fen"] as? String)
        var position = try #require(ChessPosition(fen: threefoldStart))
        var ledger = ChessRepetitionLedger()
        ledger.record(position)                      // ★ 시작 국면도 센다 — 안 세면 3회가 한 수 늦는다
        var countsAlongTheWay: [Int] = []
        for uci in line {
            let move = try #require(ChessMove(uci: uci), "\(uci)")
            position = try #require(ChessRules.apply(move, to: position), "\(uci) 가 불법이다")
            ledger.record(position)
            countsAlongTheWay.append(ledger.count(of: position))
        }
        #expect(ledger.count(of: position) == 3, "재생해 센 반복 횟수가 \(ledger.count(of: position)) 다")
        #expect(chessFxInt(threefold["repetition"]) == ledger.count(of: position), "서버 repetition")
        #expect(ChessRules.outcome(position: position, repetitionCounts: ledger.repetitionCounts)
                == .threefoldRepetition)
        #expect(threefold["outcome"] as? String == "threefold_repetition")
        #expect(threefoldMatch["result"] as? String == "draw")
        #expect(threefoldMatch["end_reason"] as? String == "threefold")
        #expect(threefoldMatch["fen"] as? String == position.fen, "재생한 끝 국면이 서버 FEN 과 다르다")
        // 기준선: 같은 키가 2회인 중간 국면에서는 **무승부가 아니다**(2 와 3 이 갈리지 않으면 이 단언은 공짜다).
        #expect(countsAlongTheWay == [1, 1, 1, 2, 2, 2, 2, 3], "중간 반복 횟수 \(countsAlongTheWay)")
        var midLedger = ChessRepetitionLedger()
        var midPosition = try #require(ChessPosition(fen: threefoldStart))
        midLedger.record(midPosition)
        for uci in line.prefix(4) {
            let midMove = try #require(ChessMove(uci: uci))
            midPosition = try #require(ChessRules.apply(midMove, to: midPosition))
            midLedger.record(midPosition)
        }
        #expect(midLedger.count(of: midPosition) == 2)
        #expect(ChessRules.outcome(position: midPosition, repetitionCounts: midLedger.repetitionCounts) == nil,
                "2회에서 이미 무승부면 3회 반복 단언은 뜻이 없다")

        // (4) 무승부 합의 — 판정이 아니라 **합의**다. 국면 판정은 nil 이어야 한다(그게 기준선이다).
        let agreed = try chessFxJSON("chess_respond_draw__accept_ok")
        let agreedMatch = try #require(agreed["match"] as? [String: Any])
        let agreedPosition = try chessFxPosition(agreedMatch, "respond_draw__accept_ok")
        #expect(agreedMatch["result"] as? String == "draw")
        #expect(agreedMatch["end_reason"] as? String == "agreement")
        #expect(ChessRules.outcome(position: agreedPosition) == nil, "합의 무승부의 국면은 아직 안 끝난 판이다")
        #expect(agreed["accepted"] as? Bool == true)
    }

    @Test("시간패 둘을 Swift 가 다시 판정해도 같고, FIDE 6.9 는 **한쪽만 보는 술어**라야 선다")
    func timeoutRulingsAgreeAndFIDE69NeedsTheOneSidedPredicate() throws {
        // 없으면: 깃발 판정에 '사국'(판 전체)을 쓴 사본이 통과한다 — 백이 퀸을 들고 깃발이 떨어졌는데
        // 흑이 맨 왕이면 사국은 false 라 "흑 승" 이 되고, **킹만 남은 사람이 판돈 2배를 받는다.**
        // 그래서 이 시험은 두 술어가 그 국면에서 **값이 갈린다**는 것까지 잰다.
        let entries = try #require(try chessFxManifest()["fixtures"] as? [String: Any])

        // (a) 평범한 시간패: 흑의 깃발 → 백 승 · 사유 timeout.
        let loss = try chessFxJSON("chess_state__end_timeout")
        let lossMatch = try #require(loss["match"] as? [String: Any])
        let lossPosition = try chessFxPosition(lossMatch, "end_timeout")
        let lossEntry = entries["chess_state__end_timeout"] as? [String: Any]
        let lossFlagged = try #require(chessColor(lossEntry?["flagged"]))
        #expect(lossFlagged == .black)
        #expect(ChessRules.timeoutRuling(position: lossPosition, flagged: lossFlagged) == .loss(flagged: .black))
        #expect(lossMatch["result"] as? String == "white_win")
        #expect(lossMatch["end_reason"] as? String == "timeout")
        #expect(lossMatch["winner"] as? String == lossMatch["white"] as? String)
        // 깃발이 떨어진 쪽이 차례인 쪽이다(시계는 차례인 쪽만 흐른다).
        #expect(lossPosition.sideToMove == lossFlagged, "깃발이 차례가 아닌 쪽에서 떨어졌다")

        // (b) FIDE 6.9: 백의 깃발인데 흑이 **맨 왕** → 무승부 · 사유 timeout_insufficient.
        let draw = try chessFxJSON("chess_state__end_timeout_insufficient")
        let drawMatch = try #require(draw["match"] as? [String: Any])
        let drawPosition = try chessFxPosition(drawMatch, "end_timeout_insufficient")
        let drawEntry = entries["chess_state__end_timeout_insufficient"] as? [String: Any]
        let drawFlagged = try #require(chessColor(drawEntry?["flagged"]))
        #expect(drawFlagged == .white)
        #expect(ChessRules.timeoutRuling(position: drawPosition, flagged: drawFlagged)
                == .drawByInsufficientMaterial)
        #expect(drawMatch["result"] as? String == "draw")
        #expect(drawMatch["end_reason"] as? String == "timeout_insufficient")
        #expect(drawMatch["winner"] is NSNull)
        #expect(drawPosition.sideToMove == drawFlagged)

        // ★ 두 술어가 **값이 갈린다**: 사국은 거짓(백이 퀸을 들었다) · 한쪽만 보는 술어는 참(흑이 맨 왕이다).
        //   이 갈림이 없으면 "사국을 쓴 사본" 과 "제대로 쓴 사본" 이 같은 답을 내 (b) 가 공짜로 통과한다.
        #expect(ChessRules.hasInsufficientMaterial(drawPosition) == false, "사국이 참이면 (b) 가 공짜다")
        #expect(ChessRules.hasNoMatingMaterial(drawPosition, color: .black) == true)
        #expect(ChessRules.hasNoMatingMaterial(drawPosition, color: .white) == false)
        // 그리고 (a) 의 국면에서는 두 술어가 **둘 다** 거짓이다 — 그래서 (a) 는 패배로 떨어진다.
        #expect(ChessRules.hasInsufficientMaterial(lossPosition) == false)
        #expect(ChessRules.hasNoMatingMaterial(lossPosition, color: .white) == false)

        // (c) 기권은 시계·배치와 무관하다 — 국면 판정은 nil 인데 판은 닫힌다(사유가 결과를 가른다).
        let resign = try chessFxJSON("chess_resign__ok")
        let resignMatch = try #require(resign["match"] as? [String: Any])
        let resignPosition = try chessFxPosition(resignMatch, "resign__ok")
        #expect(ChessRules.outcome(position: resignPosition) == nil)
        #expect(resignMatch["end_reason"] as? String == "resign")
        #expect(resignMatch["result"] as? String == "white_win")
        #expect(resignMatch["winner"] as? String == resignMatch["white"] as? String)
    }

    // MARK: - ⑥ 로비 · 순위의 결과 단언

    @Test("로비는 서버 상수와 me 셋을 싣고, 판 내용은 안 싣는다")
    func lobbyCarriesTheServerConstantsAndNeverTheBoard() throws {
        // 없으면: 앱이 시계·판돈·TTL 을 자기 상수로 들고 서버와 갈리거나(오목에서 데인 자리), 로비가 판 내용을
        // 실어 관전 게이트가 장식이 된다. me 셋(진행 중·보낸·받은)이 갈리지 않으면 "받은 신청" 단언이 공짜다.
        let manifest = try chessFxManifest()
        let users = try #require(manifest["users"] as? [String: Any])
        let entries = try #require(manifest["fixtures"] as? [String: Any])
        let b = try #require(users["B"] as? String)
        let e = try #require(users["E"] as? String)
        let hidden = try #require(users["HIDDEN"] as? String)
        let m1 = try #require(users["m1"] as? String)
        let invAB = try #require(users["inv_ab"] as? String)

        var seenWorkingRow = false
        for name in try chessFxNames() where name.hasPrefix("chess_lobby__ok") {
            let lobby = try chessFxJSON(name)
            #expect(lobby["stakes"] as? [Int] == [3, 5, 10], "\(name): 판돈 셋(A4)")
            #expect(chessFxInt(lobby["initial_ms"]) == 300_000, "\(name): 5분(A3)")
            #expect(chessFxInt(lobby["increment_ms"]) == 3000, "\(name): 가산 3초(A3)")
            #expect(chessFxInt(lobby["grace_ms"]) == 2000, "\(name): 유예 2초")
            #expect(chessFxInt(lobby["invite_ttl_seconds"]) == 60, "\(name): TTL 60초")
            let rows = try #require(lobby["users"] as? [[String: Any]])
            // 숨김 계정은 일반 사용자 로비에 **없다**(§10 소스 계약의 결과 쪽).
            #expect(!rows.contains { $0["user_id"] as? String == hidden }, "\(name): 숨김 계정이 로비에 있다")
            // capable 은 build 로 갈린다 — A 는 참, E(build 50)는 거짓. 한쪽만이면 이 단언은 공짜다.
            let capable = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, Bool)? in
                guard let id = row["user_id"] as? String, let flag = row["capable"] as? Bool else { return nil }
                return (id, flag)
            })
            #expect(capable.values.contains(true) && capable.values.contains(false),
                    "\(name): capable 이 한쪽 값뿐이다 — 그러면 이 단언은 공짜다")
            #expect(capable[e] == false, "\(name): E(build 50)는 체스를 모르는 앱이다")
            // 호출자 자신은 users[] 에 없다 — B 가 부른 로비에 B 가 없는 것이 정상이고, 자기를 실으면
            // 화면이 "나에게 신청" 카드를 그린다(신청은 p_opponent = uid 에서 invalid 다).
            let listed = Set(rows.compactMap { $0["user_id"] as? String })
            let caller = (entries[name] as? [String: Any])?["caller"] as? String
            #expect(caller != nil, "\(name): 매니페스트에 호출자가 없다")
            #expect(!listed.contains(caller ?? ""), "\(name): 호출자가 자기 로비에 실렸다")
            if listed.contains(b) {
                #expect(capable[b] == true, "\(name): B(build 96)는 체스를 아는 앱이다")
                seenWorkingRow = true
            }
            // 근무 중은 B 한 사람이다(전원 거짓이면 is_working 이 상수여도 통과한다).
            let working = rows.filter { $0["is_working"] as? Bool == true }.compactMap { $0["user_id"] as? String }
            #expect(working == (listed.contains(b) ? [b] : []), "\(name): 근무 중 \(working)")
            for row in try #require(lobby["matches"] as? [[String: Any]]) {
                #expect(row["fen"] == nil && row["ply_count"] == nil, "\(name): 로비가 판 내용을 실었다")
            }
        }

        #expect(seenWorkingRow, "B 가 어느 로비에도 안 실렸다 — is_working/capable 단언이 공짜다")

        // me 셋이 **갈린다**: 빈 로비 · 보낸 신청 · 받은 신청 · 진행 중.
        let empty = try #require(try chessFxJSON("chess_lobby__ok_empty")["me"] as? [String: Any])
        #expect(empty["active_match_id"] is NSNull && empty["outgoing_match_id"] is NSNull
                && empty["incoming_match_id"] is NSNull, "빈 로비의 me 셋")
        #expect((try chessFxJSON("chess_lobby__ok_empty")["matches"] as? [Any])?.isEmpty == true)
        let out = try #require(try chessFxJSON("chess_lobby__ok_pending_out")["me"] as? [String: Any])
        #expect(out["outgoing_match_id"] as? String == invAB)
        #expect(out["incoming_match_id"] is NSNull && out["active_match_id"] is NSNull)
        let incoming = try #require(try chessFxJSON("chess_lobby__ok_pending_in")["me"] as? [String: Any])
        #expect(incoming["incoming_match_id"] as? String == invAB, "받은 신청을 로비가 안 싣는다")
        #expect(incoming["outgoing_match_id"] is NSNull)
        let inMatch = try chessFxJSON("chess_lobby__ok_in_match")
        let inMatchMe = try #require(inMatch["me"] as? [String: Any])
        #expect(inMatchMe["active_match_id"] as? String == m1)
        let watchRows = try #require(inMatch["matches"] as? [[String: Any]])
        #expect(watchRows.count == 1 && watchRows[0]["match_id"] as? String == m1, "대결 중 목록")
        #expect(chessFxInt(watchRows[0]["stake"]) == 5)
        // 두 사람 자리는 uuid 오름차순으로 고정한다.
        let left = try #require((watchRows[0]["a"] as? [String: Any])?["user_id"] as? String)
        let right = try #require((watchRows[0]["b"] as? [String: Any])?["user_id"] as? String)
        #expect(left < right, "대결 중 목록의 두 자리가 uuid 순이 아니다")
    }

    @Test("순위표는 승점 산식·정렬·rank 를 독립 산식으로 되물어도 자기 일관적이고, 0판은 빠진다")
    func rankingIsSelfConsistentUnderAnIndependentRecomputation() throws {
        // 없으면: 정렬 축을 하나로 줄이거나 rank 를 행 번호로 적어도(동점자 순위가 전부 틀린다) 모른다.
        // 절대값은 운영에서 흔들리므로 **행들끼리의 관계**로 잰다 — 승점 = 승 − 패, 정렬 세 축, rank =
        // 나보다 엄격히 나은 행 수 + 1. 0판 제외는 로비에는 있고 순위에는 없는 사람(C)으로 재야 뜻이 선다.
        let users = try #require(try chessFxManifest()["users"] as? [String: Any])
        let c = try #require(users["C"] as? String)

        for name in ["chess_ranking__ok_me_ranked", "chess_ranking__ok_me_unranked",
                     "chess_ranking__ok_hidden_empty"] {
            let ranking = try chessFxJSON(name)
            #expect(ranking["record_since_ms"] is NSNull, "\(name): 컷이 -infinity 면 null 이다")
            let rows = try #require(ranking["rows"] as? [[String: Any]])
            struct Row { let rank: Int; let id: String; let wins: Int; let losses: Int; let draws: Int; let points: Int }
            let parsed: [Row] = try rows.map { row in
                Row(rank: try #require(chessFxInt(row["rank"])), id: try #require(row["user_id"] as? String),
                    wins: try #require(chessFxInt(row["wins"])), losses: try #require(chessFxInt(row["losses"])),
                    draws: try #require(chessFxInt(row["draws"])), points: try #require(chessFxInt(row["points"])))
            }
            for row in parsed {
                #expect(row.points == row.wins - row.losses, "\(name): 승점 = 승 − 패")
                #expect(row.wins + row.losses + row.draws > 0, "\(name): 0판이 순위표에 있다")
                // rank 는 **나보다 엄격히 나은 행 수 + 1** 이다(부호를 뒤집은 다른 식으로 센다).
                let better = parsed.filter {
                    ($0.points, $0.wins, $0.draws) > (row.points, row.wins, row.draws)
                }.count
                #expect(row.rank == better + 1, "\(name): \(row.id) 의 rank \(row.rank) ↔ 더 나은 행 \(better)")
            }
            // 정렬은 (승점 desc, 승 desc, 무 desc, user_id asc) 다 — 거꾸로 정렬해 맞춘다.
            let sorted = parsed.sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.draws != $1.draws { return $0.draws > $1.draws }
                return $0.id < $1.id
            }
            #expect(parsed.map(\.id) == sorted.map(\.id), "\(name): 정렬 축")
            #expect(parsed.count <= 100, "\(name): 100행 상한")
        }

        // ★ 기준선: me.rank 가 **갈린다**(안 갈리면 "0판은 null" 이 공짜다).
        let ranked = try #require(try chessFxJSON("chess_ranking__ok_me_ranked")["me"] as? [String: Any])
        #expect(chessFxInt(ranked["rank"]) != nil, "순위 안인 사람의 rank 가 null 이다")
        #expect(chessFxInt(ranked["wins"])! + chessFxInt(ranked["losses"])! + chessFxInt(ranked["draws"])! > 0)
        let unranked = try chessFxJSON("chess_ranking__ok_me_unranked")
        let unrankedMe = try #require(unranked["me"] as? [String: Any])
        #expect(unrankedMe["rank"] is NSNull, "0판인데 rank 가 있다")
        #expect(chessFxInt(unrankedMe["wins"]) == 0 && chessFxInt(unrankedMe["losses"]) == 0
                && chessFxInt(unrankedMe["draws"]) == 0)
        let unrankedRows = try #require(unranked["rows"] as? [[String: Any]])
        #expect(!unrankedRows.isEmpty, "0판 호출자에게 rows 가 비면 '0판 제외' 가 '전부 제외' 와 구별되지 않는다")
        #expect(!unrankedRows.contains { $0["user_id"] as? String == c }, "0판인 C 가 순위표에 있다")
        // 그런데 C 는 **로비에는 있다** — 그래서 "0판 제외" 가 "그 사람이 없다" 와 다르다는 것이 선다.
        let lobbyRows = try #require(try chessFxJSON("chess_lobby__ok_in_match")["users"] as? [[String: Any]])
        #expect(lobbyRows.contains { $0["user_id"] as? String == c }, "C 가 로비에도 없으면 0판 단언이 공짜다")
        // 숨김 계정에게는 일반 사용자 행이 안 보인다(rows 가 비는 유일한 갈래).
        #expect((try chessFxJSON("chess_ranking__ok_hidden_empty")["rows"] as? [Any])?.isEmpty == true)
    }

    // MARK: - ⑦ 상태 없는 응답들의 봉투

    @Test("상태를 안 싣는 갈래들의 봉투가 오목 선례와 같은 정확 집합이다")
    func statelessEnvelopesMatchTheDocumentedKeys() throws {
        // 없으면: insufficient 가 need/have 를 빼먹거나 not_pending 이 match_status 를 빼먹어도(앱이 "구매 실패"
        // 식 default 갈래로 떨어진다) 아무도 모른다. not_found 는 **키가 하나뿐**이어야 한다 —
        // 하나라도 더 실으면 제3자가 "그 판이 있다" 를 알게 된다.
        let expected: [String: Set<String>] = [
            "chess_challenge__ok": ["status", "match_id", "invite_expires_ms", "ruby_balance", "server_now_ms"],
            "chess_challenge__invalid": ["status", "stakes"],
            "chess_challenge__invalid_hidden": ["status", "stakes"],
            "chess_challenge__insufficient": ["status", "need", "have", "ruby_balance"],
            "chess_challenge__already_pending": ["status", "match_id"],
            "chess_challenge__busy": ["status"],
            "chess_challenge__target_busy": ["status"],
            "chess_challenge__target_focused": ["status"],
            "chess_challenge__target_outdated": ["status"],
            "chess_respond__decline_ok": ["status", "accepted", "ruby_balance", "server_now_ms"],
            "chess_respond__expired": ["status", "ruby_balance"],
            "chess_respond__not_pending": ["status", "match_status", "ruby_balance"],
            "chess_respond__not_found": ["status"],
            "chess_cancel__ok": ["status", "ruby_balance", "server_now_ms"],
            "chess_cancel__not_pending": ["status", "match_status", "ruby_balance"],
            "chess_cancel__not_found": ["status"],
            "chess_state__not_found": ["status"],
            "chess_watch__not_found": ["status"],
            "chess_watch__not_found_old": ["status"],
            "chess_watch__not_found_hidden": ["status"],
            "chess_watch__not_found_pending": ["status"],
            "chess_lobby__unauthorized": ["status"],
            "chess_ranking__unauthorized": ["status"],
            "chess_watch__unauthorized": ["status"]
        ]
        for (name, keys) in expected {
            #expect(chessFxKeys(try chessFxJSON(name)) == keys, "\(name): 봉투 키")
        }
        // 숨김·차단·없는 상대·판돈 밖이 **같은 응답**이다(있다/없다를 구별하게 하지 않는다).
        let plain = try chessFxJSON("chess_challenge__invalid")
        let hiddenTarget = try chessFxJSON("chess_challenge__invalid_hidden")
        #expect(plain["status"] as? String == hiddenTarget["status"] as? String)
        #expect(plain["stakes"] as? [Int] == hiddenTarget["stakes"] as? [Int])
        // 신청에 루비가 움직이지 않는다(잔액만 본다) — 같은 호출자의 로비 잔액과 같아야 한다.
        let challenge = try chessFxJSON("chess_challenge__ok")
        let lobbyBalance = chessFxInt(try chessFxJSON("chess_lobby__ok_empty")["ruby_balance"])
        #expect(chessFxInt(challenge["ruby_balance"]) == 100, "신청이 루비를 움직였다")
        #expect(lobbyBalance == 100, "로비 잔액이 \(lobbyBalance ?? -1) 다")
        // 수락은 양쪽에서 stake 만큼 뺀다 — 100 → 95.
        #expect(chessFxInt(try chessFxJSON("chess_respond__accept_ok")["ruby_balance"]) == 95,
                "수락 때 판돈이 안 빠졌다")
        // 거절·만료는 루비를 움직이지 않는다. ★ 호출자(D)의 잔액은 **1** 이고 판돈은 3 이다 — 차감이 일어났다면
        //   profiles_ruby_balance_check(23514) 로 터지거나 음수가 됐을 자리라, 1 이 그대로인 것이 "안 빠졌다" 의 증거다.
        let declined = try chessFxJSON("chess_respond__decline_ok")
        #expect(chessFxInt(declined["ruby_balance"]) == 1, "거절이 루비를 움직였다")
        #expect(declined["accepted"] as? Bool == false)
        #expect(chessFxInt(try chessFxJSON("chess_respond__expired")["ruby_balance"]) == 1, "만료가 루비를 움직였다")
        // 취소는 신청자(C · 루비 100)가 한다 — 신청에서 애초에 빠지지 않았으므로 환불도 없다.
        #expect(chessFxInt(try chessFxJSON("chess_cancel__ok")["ruby_balance"]) == 100, "취소가 루비를 움직였다")
        // insufficient 는 내 잔액을 숫자로 말한다(상대 잔액은 §5.3 에서 null 이다).
        let poor = try chessFxJSON("chess_challenge__insufficient")
        #expect(chessFxInt(poor["need"]) == 3 && chessFxInt(poor["have"]) == 1)
    }

    @Test("착수의 거절 넷은 **판을 건드리지 않는다** — 같은 ply·같은 FEN·같은 시계를 되돌려 준다")
    func rejectedMovesLeaveTheBoardUntouched() throws {
        // 없으면: 불법 수·stale·not_your_turn 이 시계를 깎거나 ply 를 올려도 모른다 — 상대 시계를 흘리거나
        // 내 시계를 아끼는 길이 열린다. 기준선: **받아들여진** 수는 ply 를 올린다(안 올리면 이 단언이 공짜다).
        let accepted = try chessFxJSON("chess_move__ok_white_first")
        let acceptedMatch = try #require(accepted["match"] as? [String: Any])
        #expect(chessFxInt(acceptedMatch["ply_count"]) == 1, "받아들여진 수가 ply 를 안 올렸다")

        let rejected = ["chess_move__illegal", "chess_move__stale", "chess_move__not_your_turn"]
        var fens: Set<String> = []
        for name in rejected {
            let object = try chessFxJSON(name)
            let match = try #require(object["match"] as? [String: Any])
            #expect(chessFxInt(match["ply_count"]) == 1, "\(name): 거절된 수가 ply 를 올렸다")
            fens.insert(try #require(match["fen"] as? String))
            #expect(chessFxInt(match["white_grace_ms"]) == 2000 && chessFxInt(match["black_grace_ms"]) == 2000,
                    "\(name): 거절된 수가 유예를 깎았다")
            // 거절된 수는 **합법 수 목록이 없다**(내 차례가 아니거나 판이 옛것이다) — 단 illegal 은 내 차례다.
            if name == "chess_move__illegal" {
                let served = try #require(object["legal_moves"] as? [String])
                #expect(!served.contains("e7e4"), "불법 수가 합법 수 목록에 있다")
                #expect(object["uci"] as? String == "e7e4", "거절된 수를 그대로 돌려줘야 한다")
            }
        }
        #expect(fens.count == 1, "거절 셋이 서로 다른 판을 봤다: \(fens)")
        #expect(fens.first == acceptedMatch["fen"] as? String, "거절된 수가 판을 바꿨다")

        // clock_skew: 시간패가 **아니다** — 판은 그대로 active 다(여기서 깃발을 떨어뜨리면 한 번에 진다).
        let skew = try chessFxJSON("chess_move__retry_clock_skew")
        let skewMatch = try #require(skew["match"] as? [String: Any])
        #expect(skew["reason"] as? String == "clock_skew")
        #expect(skewMatch["status"] as? String == "active", "시계 밀림이 판을 닫았다")
        #expect(skewMatch["result"] is NSNull && skewMatch["end_reason"] is NSNull)
        #expect(chessFxInt(skewMatch["ply_count"]) == 0)
    }

    @Test("since 는 **배타**다 — 참가자·관전 둘 다 이미 본 수를 다시 보내지 않는다")
    func sinceSequenceIsExclusiveForPlayersAndSpectators() throws {
        // 없으면: `>=` 로 바꾼 사본이 통과하고(매 폴링마다 이미 본 수를 다시 보낸다) 기보가 중복으로 쌓인다.
        // 기준선: since 0 은 **전부** 온다(0 과 4 가 같은 답이면 이 단언은 뜻이 없다).
        for (zero, since) in [("chess_state__ok_mid_since0", "chess_state__ok_mid_since4"),
                              ("chess_watch__ok_active", "chess_watch__ok_since4")] {
            let all = try #require(try chessFxJSON(zero)["moves"] as? [[String: Any]])
            let tail = try #require(try chessFxJSON(since)["moves"] as? [[String: Any]])
            #expect(all.compactMap { chessFxInt($0["seq"]) } == [1, 2, 3, 4, 5, 6], "\(zero): since 0")
            #expect(tail.compactMap { chessFxInt($0["seq"]) } == [5, 6], "\(since): since 4 는 배타다")
            #expect(all.count != tail.count, "\(zero) 와 \(since) 가 같은 답이면 since 단언이 공짜다")
        }
    }
}
