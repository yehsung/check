import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기(reversi) — 와이어 디코딩 계약(갈래 C1). 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다(SPEC §1).
//
// 두 겹이다:
//  ① `V03xxReversiFixtureContractTests`(C1) — 설계서 §3.5·§3.6 모양의 **손 픽스처**를 앱 디코더와 같은 설정으로 읽어 값까지 대조한다
//     (원문에 없는 값 — 센터 글자·패스 줄의 빠진 키·모르는 어휘 — 을 일부러 싣는다).
//  ② `V03xxReversiServerFixtureContractTests`(C2) — 서버 갈래 픽스처 **원문**(`Fixtures/reversi-rpc/`, `FLIP/server/fixtures` 복사)을
//     매니페스트 · 봉투 키 = 마이그레이션 `v_*_keys` · 독립 산식(Swift 규칙으로 서버 판·합법 수·점수를 다시 셈) ·
//     요청 본문 키 = SQL 인자 이름으로 잰다. 마이그레이션은 `REVERSI_MIGRATION_SQL`(없으면 저장소 `supabase/migrations/…`)에서
//     읽고, `REVERSI_REQUIRE_MIGRATION=1` 이면 파일이 없을 때 건너뛰지 않고 빨갛다(SPEC §6.2).
//
// 옵셔널 칸은 키 이름이 한 글자만 어긋나도 **조용히 nil** 이 되어 초록이 된다 — 그래서 "디코드된다" 가 아니라
// **값이 원문과 같다** 를 잰다(nil 이면 빨갛다).

/// 앱 디코더와 같은 설정(`SupabaseWorkService.init` — `.convertFromSnakeCase`). 서비스는 actor 라 그 칸을 직접 빌리지 않는다.
private func rfcDecode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(json.utf8))
}

/// 앱 인코더와 같은 설정(`.convertToSnakeCase`)으로 편 요청 본문.
private func rfcObject<T: Encodable>(_ body: T) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(body)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

/// 요청 본문의 키 집합.
private func rfcKeys<T: Encodable>(_ body: T) throws -> Set<String> {
    Set(try rfcObject(body).keys)
}

private let rfcMe = "a1000000-0000-4000-8000-000000000001"
private let rfcPeer = "b2000000-0000-4000-8000-000000000002"
private let rfcMatch = "c3000000-0000-4000-8000-000000000003"

/// §3.5 로비 — 받은 신청 하나 · 보낸 신청 없음 · 사람 한 줄 · 진행 판 한 줄.
private let rfcLobbyJSON = """
{"status":"ok","server_now_ms":1793659950010,"stakes":[3,5,10],"turn_seconds":30,"turn_grace_seconds":2,
 "invite_ttl_seconds":60,"auto_abandon_streak":3,
 "me":{"ruby_balance":95,"wins":4,"losses":2,"draws":1,"active_match_id":null,
       "incoming":[{"match_id":"\(rfcMatch)","from":{"id":"\(rfcPeer)","display_name":"상대01","avatar_url":"https://x/a.png","character":"aing"},
                    "stake":5,"expires_at_ms":1793660010009}],
       "outgoing":null},
 "users":[{"id":"\(rfcPeer)","display_name":"상대01","avatar_url":null,"character":"aing","center":"seoul",
           "is_working":true,"in_match":false,"capable":true,"focus_mode":false}],
 "matches":[{"id":"d4000000-0000-4000-8000-000000000004","a":{"id":"\(rfcMe)","display_name":"나","avatar_url":null,"character":null},
             "b":{"id":"\(rfcPeer)","display_name":"상대01","avatar_url":null,"character":null},
             "stake":10,"watchers":2,"started_at_ms":1793659940000}]}
"""

/// §3.6 내 차례 active — 상대(흑)가 d3(19)에 **시간 초과 자동 착수**로 c4 쪽 한 돌을 뒤집은 뒤 내(백) 차례.
/// 판·돌 수·합법 수는 참조 구현(`research/reference.py`)으로 맞춘 값이다(손 픽스처라도 수순과 판이 어긋나지 않게).
private let rfcActiveStateJSON = """
{"status":"ok","state":{
 "match":{"id":"\(rfcMatch)","status":"active","stake":5,"challenger":"\(rfcMe)","opponent":"\(rfcPeer)",
          "black":"\(rfcPeer)","white":"\(rfcMe)","move_count":1,"turn":"white",
          "turn_started_ms":1793659950000,"deadline_ms":1793659980000,"invite_expires_ms":1793660010009,
          "started_ms":1793659918000,"finished_ms":null,"result":null,"end_reason":null,"winner":null,
          "board":"...................b.......bb......bw...........................",
          "discs":{"black":4,"white":1,"empty":59},"score":null},
 "moves":[{"seq":1,"color":"black","kind":"stone","idx":19,"flipped":[27],"auto":true,"at_ms":1793659950000}],
 "black_user":{"user_id":"\(rfcPeer)","display_name":"상대01","avatar_url":null,"character":null,"center":"busan"},
 "white_user":{"user_id":"\(rfcMe)","display_name":"나","avatar_url":null,"character":"aing","center":null},
 "opponent":{"user_id":"\(rfcPeer)","display_name":"상대01","avatar_url":null,"character":null,"center":"busan"},
 "my_color":"white","legal_moves":[18,20,34],
 "black_auto_streak":1,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":1,
 "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":95,"watchers":4,"server_now_ms":1793659951000}}
"""

/// 수 기록의 패스 줄 — `idx` null · `flipped`·`auto` 키가 빠진 줄(없으면 []·거짓으로 읽는다)을 섞는다.
private let rfcPassMovesJSON = """
[{"seq":7,"color":"white","kind":"pass","idx":null,"flipped":[],"auto":false,"at_ms":1793659960000},
 {"seq":8,"color":"black","kind":"pass","idx":null,"at_ms":1793659960000},
 {"seq":9,"color":"white","kind":"stone","idx":63,"flipped":[54,62],"auto":false,"at_ms":1793659961000}]
"""

/// §3.6 자연 종료(판 가득, 흑 승) — 쓰기 응답(move ok)의 봉투.
private let rfcFinishedStateJSON = """
{"status":"ok","state":{
 "match":{"id":"\(rfcMatch)","status":"finished","stake":5,"challenger":"\(rfcMe)","opponent":"\(rfcPeer)",
          "black":"\(rfcMe)","white":"\(rfcPeer)","move_count":60,"turn":null,
          "turn_started_ms":1793659990000,"deadline_ms":null,"invite_expires_ms":1793660010009,
          "started_ms":1793659940000,"finished_ms":1793659999000,"result":"black_win","end_reason":"board_full",
          "winner":"\(rfcMe)",
          "board":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbwwwwwwwwwwwwwwwwwwwwwww",
          "discs":{"black":41,"white":23,"empty":0},"score":{"black":41,"white":23}},
 "moves":[],"black_user":null,"white_user":null,"opponent":null,"my_color":"black","legal_moves":[],
 "black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":0,
 "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":105,"watchers":0,"server_now_ms":1793659999100}}
"""

/// §3.6 관전 모양(watch_live) — 참가자 칸이 전부 null, legal_moves 는 [].
private let rfcWatchJSON = """
{"status":"ok","state":{
 "match":{"id":"\(rfcMatch)","status":"active","stake":3,"challenger":"\(rfcMe)","opponent":"\(rfcPeer)",
          "black":"\(rfcPeer)","white":"\(rfcMe)","move_count":0,"turn":"black",
          "turn_started_ms":1793659950099,"deadline_ms":1793659980099,"invite_expires_ms":1793660010098,
          "started_ms":1793659950099,"finished_ms":null,"result":null,"end_reason":null,"winner":null,
          "board":"...........................wb......bw...........................",
          "discs":{"black":2,"white":2,"empty":60},"score":null},
 "moves":[],"black_user":{"user_id":"\(rfcPeer)","display_name":"상대01","avatar_url":null,"character":null,"center":null},
 "white_user":{"user_id":"\(rfcMe)","display_name":"나","avatar_url":null,"character":null,"center":null},
 "opponent":null,"my_color":null,"legal_moves":[],
 "black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":null,"opponent_auto_streak":null,
 "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":7,"server_now_ms":1793659950100}}
"""

@Suite struct V03xxReversiFixtureContractTests {
    // 없으면: 로비 키 이름이 어긋나도(예: `expires_at_ms` → `expiresAtMS`) 옵셔널이 nil 로 접혀 받은 신청·만료·관전자 수가
    // 화면에서 조용히 사라진 채 초록이다.
    @Test func 로비_손픽스처가_값까지_읽힌다() throws {
        let lobby = try rfcDecode(ReversiLobbyResponse.self, rfcLobbyJSON)
        #expect(lobby.status == .ok)
        #expect(lobby.serverNowMs == 1_793_659_950_010)
        #expect(lobby.stakes == [3, 5, 10])
        #expect(lobby.turnSeconds == 30)
        #expect(lobby.turnGraceSeconds == 2)
        #expect(lobby.inviteTtlSeconds == 60)
        #expect(lobby.autoAbandonStreak == 3)

        let me = try #require(lobby.me)
        #expect(me.rubyBalance == 95)
        #expect(me.wins == 4 && me.losses == 2 && me.draws == 1)
        #expect(me.activeMatchId == nil)
        #expect(me.outgoing == nil)
        let invite = try #require(me.incoming?.first)
        #expect(me.incoming?.count == 1)
        #expect(invite.matchId == rfcMatch)
        #expect(invite.from?.id == rfcPeer)
        #expect(invite.from?.displayName == "상대01")
        #expect(invite.from?.avatarUrl == "https://x/a.png")
        #expect(invite.from?.character == "aing")
        #expect(invite.to == nil)
        #expect(invite.stake == 5)
        #expect(invite.expiresAtMs == 1_793_660_010_009)

        let user = try #require(lobby.users?.first)
        #expect(user.id == rfcPeer)
        #expect(user.center == "seoul")
        #expect(user.isWorking == true)
        #expect(user.inMatch == false)
        #expect(user.capable == true)
        #expect(user.focusMode == false)

        let live = try #require(lobby.matches?.first)
        #expect(live.a?.id == rfcMe)
        #expect(live.b?.displayName == "상대01")
        #expect(live.stake == 10)
        #expect(live.watchers == 2)
        #expect(live.startedAtMs == 1_793_659_940_000)
    }

    // 없으면: state 의 판·시계·합법 수·연속 자동 착수 칸 하나가 잘못 읽혀도(nil·0) 스토어가 "판 없음/내 차례 아님" 으로
    // 그려 초록이다. 패스 줄(idx null)이 디코드를 통째로 깨는 결함도 여기서만 보인다.
    @Test func 진행중_state_손픽스처가_값까지_읽힌다() throws {
        let response = try rfcDecode(ReversiActionResponse.self, rfcActiveStateJSON)
        #expect(response.status == .ok)
        let state = try #require(response.state)
        let match = try #require(state.match)
        #expect(match.id == rfcMatch)
        #expect(match.matchStatus == .active)
        #expect(match.stake == 5)
        #expect(match.challenger == rfcMe && match.opponent == rfcPeer)
        #expect(match.black == rfcPeer && match.white == rfcMe)
        #expect(match.moveCount == 1)
        #expect(match.turn == .white)
        #expect(match.turnStartedMs == 1_793_659_950_000)
        #expect(match.deadlineMs == 1_793_659_980_000)
        #expect(match.inviteExpiresMs == 1_793_660_010_009)
        #expect(match.startedMs == 1_793_659_918_000)
        #expect(match.finishedMs == nil && match.result == nil && match.endReason == nil && match.winner == nil)
        #expect(match.board?.string == "...................b.......bb......bw...........................")
        #expect(match.discs == ReversiCounts(black: 4, white: 1, empty: 59))
        #expect(match.score == nil)

        #expect(state.moves == [ReversiPly(seq: 1, color: .black, kind: .stone, idx: 19, flipped: [27], auto: true)])
        #expect(state.blackUser?.userId == rfcPeer)
        #expect(state.blackUser?.center == "busan")
        #expect(state.whiteUser?.userId == rfcMe)
        #expect(state.whiteUser?.character == "aing")
        #expect(state.opponent?.userId == rfcPeer)
        #expect(state.opponent?.displayName == "상대01")
        #expect(state.myColor == .white)
        #expect(state.legalMoves == [18, 20, 34])
        #expect(state.blackAutoStreak == 1 && state.whiteAutoStreak == 0)
        #expect(state.myAutoStreak == 0 && state.opponentAutoStreak == 1)
        #expect(state.autoAbandonStreak == 3)
        #expect(state.turnSeconds == 30)
        #expect(state.graceMs == 2000)
        #expect(state.rubyBalance == 95)
        #expect(state.watchers == 4)
        #expect(state.serverNowMs == 1_793_659_951_000)
    }

    // 없으면: 패스 줄(idx null)이나 `flipped`·`auto` 키가 빠진 줄 하나가 state 디코드를 통째로 깨 판이 안 읽히고,
    // 기준선(돌 줄)과 같은 값으로 읽혀도 초록이다 — 줄마다 값으로 잰다.
    @Test func 수_기록의_패스_줄과_빠진_키를_읽는다() throws {
        let moves = try rfcDecode([ReversiPly].self, rfcPassMovesJSON)
        #expect(moves == [
            ReversiPly(seq: 7, color: .white, kind: .pass, idx: nil, flipped: [], auto: false),
            ReversiPly(seq: 8, color: .black, kind: .pass, idx: nil, flipped: [], auto: false),
            ReversiPly(seq: 9, color: .white, kind: .stone, idx: 63, flipped: [54, 62], auto: false),
        ])
    }

    // 없으면: 자연 종료의 결과·끝 사유·WOF 점수가 nil 로 읽혀 결과 카드가 "끝났는데 무승부도 승패도 아닌" 판을 그린 채 초록이다.
    @Test func 끝난_state_손픽스처는_결과와_점수를_싣는다() throws {
        let response = try rfcDecode(ReversiActionResponse.self, rfcFinishedStateJSON)
        let match = try #require(response.state?.match)
        #expect(match.matchStatus == .finished)
        #expect(match.turn == nil)
        #expect(match.deadlineMs == nil)
        #expect(match.result == .blackWin)
        #expect(match.endReason == .boardFull)
        #expect(match.winner == rfcMe)
        #expect(match.finishedMs == 1_793_659_999_000)
        #expect(match.score == ReversiScoreRow(black: 41, white: 23))
        #expect(match.discs == ReversiCounts(black: 41, white: 23, empty: 0))
        #expect(response.state?.moves == [])
        #expect(response.state?.blackUser == nil)
        #expect(response.state?.legalMoves == [])
        #expect(response.state?.rubyBalance == 105)
    }

    // 없으면: 관전 모양(참가자 칸 null)에서 디코드가 깨지거나, 참가자 전용 칸이 0·빈 값으로 지어져 관전자에게 "내 차례" 가 보인다.
    @Test func 관전_state_는_참가자_칸이_비어도_읽힌다() throws {
        let response = try rfcDecode(ReversiActionResponse.self, rfcWatchJSON)
        let state = try #require(response.state)
        #expect(state.myColor == nil)
        #expect(state.opponent == nil)
        #expect(state.myAutoStreak == nil && state.opponentAutoStreak == nil)
        #expect(state.rubyBalance == nil)
        #expect(state.legalMoves == [])
        #expect(state.watchers == 7)
        #expect(state.blackUser?.userId == rfcPeer)
        #expect(state.match?.board == .start)
    }

    // 없으면: 서버가 어휘를 넓히는 날(새 status·새 끝 사유·새 불법 이유) 디코드가 throw 해 대결 창이 통째로 죽는다.
    // 기준선: 아는 값은 제 case 로 읽힌다(`.unknown` 으로 다 접는 변이도 빨갛다).
    @Test func 모르는_어휘는_접히고_아는_어휘는_제자리로_읽힌다() throws {
        let unknown = try rfcDecode(ReversiActionResponse.self, #"{"status":"one_writer","reason":"diagonal_only"}"#)
        #expect(unknown.status == .unknown)
        #expect(unknown.reason == "diagonal_only")
        #expect(unknown.illegalReason == nil)

        let illegal = try rfcDecode(ReversiActionResponse.self, #"{"status":"illegal","reason":"no_flip"}"#)
        #expect(illegal.status == .illegal)
        #expect(illegal.illegalReason == .noFlip)

        let auto = try rfcDecode(ReversiActionResponse.self, #"{"status":"auto_placed","auto_placed_count":2}"#)
        #expect(auto.status == .autoPlaced)
        #expect(auto.autoPlacedCount == 2)

        let stale = try rfcDecode(ReversiActionResponse.self, #"{"status":"stale"}"#)
        #expect(stale.status == .stale)
        let notYourTurn = try rfcDecode(ReversiActionResponse.self, #"{"status":"not_your_turn"}"#)
        #expect(notYourTurn.status == .notYourTurn)

        // §3.4 어휘 전체가 제 이름으로 읽힌다(글자 하나 어긋난 case 가 `.unknown` 으로 새는 것을 잡는다).
        let vocabulary = [
            "ok", "unauthorized", "unsupported_client", "invalid", "blackout", "target_focused", "target_outdated",
            "busy", "target_busy", "already_pending", "insufficient", "not_found", "not_pending", "expired",
            "not_active", "not_your_turn", "stale", "illegal", "auto_placed",
        ]
        for word in vocabulary {
            let decoded = try rfcDecode(ReversiActionResponse.self, "{\"status\":\"\(word)\"}")
            #expect(decoded.status != .unknown, "\(word) 가 .unknown 으로 접혔다")
            #expect(decoded.status.rawValue == word)
        }

        let row = try rfcDecode(ReversiMatchRow.self, #"{"status":"paused","end_reason":"timeout_new"}"#)
        #expect(row.matchStatus == .unknown)
        #expect(row.endReason == .unknown)
    }

    // 없으면: 쓰기 응답의 부가 칸(신청 id·만료·잔액·부족분·수락 여부)이 nil 로 읽혀 신청 카드·잔액 칩·부족 문구가 틀린 채 초록이다.
    @Test func 쓰기_응답의_부가_칸이_읽힌다() throws {
        let challenge = try rfcDecode(ReversiActionResponse.self, """
        {"status":"ok","match_id":"\(rfcMatch)","ruby_balance":100,"server_now_ms":1793659950009,"invite_expires_ms":1793660010009}
        """)
        #expect(challenge.matchId == rfcMatch)
        #expect(challenge.inviteExpiresMs == 1_793_660_010_009)
        #expect(challenge.rubyBalance == 100)
        #expect(challenge.serverNowMs == 1_793_659_950_009)

        let short = try rfcDecode(ReversiActionResponse.self, #"{"status":"insufficient","side":"challenger","need":3,"have":null}"#)
        #expect(short.status == .insufficient)
        #expect(short.side == "challenger")
        #expect(short.need == 3 && short.have == nil)

        let declined = try rfcDecode(ReversiActionResponse.self, #"{"status":"ok","accepted":false}"#)
        #expect(declined.accepted == false)

        let invalid = try rfcDecode(ReversiActionResponse.self, #"{"status":"invalid","stakes":[3,5,10]}"#)
        #expect(invalid.stakes == [3, 5, 10])
    }

    // 없으면: 요청 본문 키가 서버 인자 이름과 한 글자만 달라도(PGRST202 — 함수를 못 찾는다) 스텁 서버 시험은 전부 초록이다.
    // 빈 `{}` 본문(`p_protocol` 빠짐)도 여기서만 잡힌다.
    @Test func 요청_본문_키는_서버_인자_이름과_같다() throws {
        #expect(try rfcKeys(ReversiProtocolRequest()) == ["p_protocol"])
        #expect(try rfcKeys(ReversiChallengeRequest(pOpponent: rfcPeer, pStake: 5))
                == ["p_protocol", "p_opponent", "p_stake"])
        #expect(try rfcKeys(ReversiMatchRequest(pMatchId: rfcMatch)) == ["p_protocol", "p_match_id"])
        #expect(try rfcKeys(ReversiRespondRequest(pMatchId: rfcMatch, pAccept: true))
                == ["p_protocol", "p_match_id", "p_accept"])
        #expect(try rfcKeys(ReversiStateRequest(pMatchId: rfcMatch, pSinceSeq: 4))
                == ["p_protocol", "p_match_id", "p_since_seq"])
        #expect(try rfcKeys(ReversiMoveRequest(pMatchId: rfcMatch, pExpectedSeq: 3, pIdx: 19))
                == ["p_protocol", "p_match_id", "p_expected_seq", "p_idx"])
        #expect(try rfcKeys(ReversiWatchRequest(pMatchId: rfcMatch, pSinceSeq: 0))
                == ["p_protocol", "p_match_id", "p_since_seq"])

        let move = try rfcObject(ReversiMoveRequest(pMatchId: rfcMatch, pExpectedSeq: 3, pIdx: 19))
        #expect(move["p_protocol"] as? Int == ReversiWire.protocolVersion)
        #expect(ReversiWire.protocolVersion == 1)
        #expect(move["p_expected_seq"] as? Int == 3)
        #expect(move["p_idx"] as? Int == 19)
        #expect(move["p_match_id"] as? String == rfcMatch)
    }

    // 없으면: RPC 이름 하나가 빠지거나 오타여도(마이그레이션 대조 시험이 읽을 목록이 틀린다) 초록이고,
    // 읽기 전용 RPC 에 교착 재시도가 켜지거나 상태 조회에서 꺼지는 것도 안 보인다.
    @Test func RPC_이름_열개와_교착_재시도_집합() {
        #expect(ReversiWire.RPC.all == [
            "reversi_lobby", "reversi_challenge", "reversi_cancel", "reversi_respond", "reversi_state",
            "reversi_move", "reversi_resign", "reversi_ranking", "reversi_watch", "reversi_watch_live",
        ])
        let retried = Set(ReversiWire.RPC.allCases.filter(\.retriesDeadlockOnce).map(\.rawValue))
        #expect(retried == [
            "reversi_challenge", "reversi_cancel", "reversi_respond", "reversi_state", "reversi_move", "reversi_resign",
        ])
    }

    // 없으면: 순위 줄의 id 키(`user_id`)를 로비처럼 `id` 로 읽어 순위표가 전부 빈 사람으로 그려진 채 초록이다.
    @Test func 순위_응답이_값까지_읽힌다() throws {
        let ranking = try rfcDecode(ReversiRankingResponse.self, """
        {"status":"ok","server_now_ms":1793659950106,"record_since_ms":null,
         "me":{"rank":1,"wins":3,"losses":1,"draws":2,"points":2},
         "rows":[{"rank":1,"user_id":"\(rfcMe)","display_name":"나","avatar_url":null,"character":"aing","center":"seoul",
                  "wins":3,"losses":1,"draws":2,"points":2}]}
        """)
        #expect(ranking.status == .ok)
        #expect(ranking.recordSinceMs == nil)
        #expect(ranking.me?.rank == 1 && ranking.me?.points == 2)
        let row = try #require(ranking.rows?.first)
        #expect(row.userId == rfcMe)
        #expect(row.displayName == "나")
        #expect(row.center == "seoul")
        #expect(row.wins == 3 && row.losses == 1 && row.draws == 2 && row.points == 2)
    }
}

// MARK: - ② 서버 픽스처 원문 계약 (C2)

private let rfcServerDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/reversi-rpc", isDirectory: true)

private func rfcServerJSON(_ file: String) throws -> [String: Any] {
    let data = try Data(contentsOf: rfcServerDirectory.appendingPathComponent(file))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RFCError("\(file) 는 JSON 객체가 아니다")
    }
    return object
}

private struct RFCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 디스크의 픽스처 파일 이름(매니페스트 제외), 정렬.
private func rfcServerFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: rfcServerDirectory.path)
        .filter { $0.hasSuffix(".json") && $0 != "_manifest.json" }
        .sorted()
}

private func rfcKeySet(_ value: Any?) -> Set<String> {
    Set((value as? [String: Any])?.keys.map { $0 } ?? [])
}

private func rfcInt(_ value: Any?) -> Int? {
    (value as? NSNumber).map(\.intValue)
}

private func rfcDouble(_ value: Any?) -> Double? {
    (value as? NSNumber).map(\.doubleValue)
}

/// 상태가 실린 원문 픽스처 전부(파일 이름 · state 객체).
private func rfcServerStates() throws -> [(file: String, state: [String: Any])] {
    try rfcServerFiles().compactMap { file in
        guard let state = try rfcServerJSON(file)["state"] as? [String: Any] else { return nil }
        return (file, state)
    }
}

/// 리버시 마이그레이션 한 장의 위치(SPEC §6.2 — 공용 `CHECK_MIGRATIONS_DIR` 가 아니다).
private func rfcMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<6 {
        let candidate = directory.appendingPathComponent("supabase/migrations/20261108200000_reversi.sql")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private let rfcMigrationRequired = ProcessInfo.processInfo.environment["REVERSI_REQUIRE_MIGRATION"] == "1"
/// 마이그레이션을 읽는 시험이 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let rfcMigrationGate = rfcMigrationURL() != nil || rfcMigrationRequired

/// 마이그레이션 원문(`--` 주석을 걷는다 — 키 배열 줄에는 문자열 안 `--` 가 없다).
private func rfcMigrationText() throws -> String {
    guard let url = rfcMigrationURL() else {
        throw RFCError("""
            리버시 마이그레이션이 없다(REVERSI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"] ?? "(없음)")) — \
            REVERSI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    let raw = try String(contentsOf: url, encoding: .utf8)
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 마이그레이션 사후 단언의 키 배열 상수(`v_<이름>_keys constant text[] := array[...]`). 이름 → 키 집합.
private func rfcMigrationKeyArrays(_ sql: String) throws -> [String: Set<String>] {
    let pattern = #"v_([a-z_]+)_keys\s+constant\s+text\[\]\s*:=\s*array\[([^\]]*)\]"#
    let regex = try NSRegularExpression(pattern: pattern)
    var out: [String: Set<String>] = [:]
    let range = NSRange(sql.startIndex..., in: sql)
    for match in regex.matches(in: sql, range: range) {
        guard let nameRange = Range(match.range(at: 1), in: sql),
              let bodyRange = Range(match.range(at: 2), in: sql) else { continue }
        let keys = sql[bodyRange].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        }
        out[String(sql[nameRange])] = Set(keys)
    }
    return out
}

/// 마이그레이션의 `create or replace function public.<이름>(<인자>)` — **마지막 정의**의 인자 이름(순서대로).
private func rfcMigrationArguments(_ sql: String, function: String) throws -> [String]? {
    let pattern = #"create\s+or\s+replace\s+function\s+public\."# + function + #"\s*\(([^)]*)\)"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    let matches = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql))
    guard let last = matches.last, let argsRange = Range(last.range(at: 1), in: sql) else { return nil }
    return sql[argsRange].split(separator: ",").compactMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
    }
}

@Suite("아잉 뒤집기 서버 픽스처 원문 — 매니페스트 · 봉투 키 · 독립 산식 · 요청 인자")
struct V03xxReversiServerFixtureContractTests {

    // 없으면: 서버 갈래가 픽스처를 다시 뽑다 한 갈래를 빠뜨리거나 이름·status 가 어긋나도(스토어 시험이 엉뚱한 원문을 먹는다)
    // 초록이고, 앱 디코더가 원문 status 를 `.unknown` 으로 접어도(어휘 한 글자 차이) 안 보인다.
    @Test func 매니페스트가_디스크와_같고_원문_status_를_앱이_읽는다() throws {
        let manifest = try rfcServerJSON("_manifest.json")
        let entries = try #require(manifest["files"] as? [[String: Any]])
        let listed = entries.compactMap { $0["file"] as? String }.sorted()
        let onDisk = try rfcServerFiles()
        #expect(listed == onDisk)
        #expect(onDisk.count == 51, "픽스처 \(onDisk.count)장 — 줄면 어느 갈래가 사라진 것이다")
        for entry in entries {
            let file = try #require(entry["file"] as? String)
            let rpc = try #require(entry["rpc"] as? String)
            let kase = try #require(entry["case"] as? String)
            #expect(file == "\(rpc)__\(kase).json", "\(file): 이름이 rpc__case 가 아니다")
            #expect(ReversiWire.RPC.all.contains(rpc), "\(file): 모르는 rpc \(rpc)")
            let top = try rfcServerJSON(file)
            let status = try #require(top["status"] as? String, "\(file): status 없음")
            #expect(status == entry["status"] as? String, "\(file): 매니페스트 status 와 다르다")
            #expect((top["state"] != nil) == (entry["has_state"] as? Bool), "\(file): has_state 가 다르다")
            let text = try String(contentsOf: rfcServerDirectory.appendingPathComponent(file), encoding: .utf8)
            let decoded: ReversiRPCStatus
            switch rpc {
            case ReversiWire.RPC.lobby.rawValue: decoded = try rfcDecode(ReversiLobbyResponse.self, text).status
            case ReversiWire.RPC.ranking.rawValue: decoded = try rfcDecode(ReversiRankingResponse.self, text).status
            default:
                let action = try rfcDecode(ReversiActionResponse.self, text)
                decoded = action.status
                #expect((action.state != nil) == (top["state"] != nil), "\(file): state 디코드가 빠졌다")
                if top["state"] != nil {
                    #expect(action.state?.match?.board != nil, "\(file): 판 문자열을 못 읽었다")
                    #expect(action.state?.match?.matchStatus != .unknown, "\(file): 판 status 를 모른다")
                }
            }
            #expect(decoded.rawValue == status, "\(file): 앱이 status 를 \(decoded) 로 읽었다")
        }
        // 매니페스트가 말하는 시청자 A·B 가 스토어 시험의 상수와 같다(손으로 적은 uuid 가 조용히 어긋나지 않게).
        let viewers = try #require(manifest["viewers"] as? [String: String])
        #expect(viewers["A"] == "b0000000-0000-4000-8000-000000000001")
        #expect(viewers["B"] == "b0000000-0000-4000-8000-000000000002")
    }

    // 없으면: 서버가 키를 하나 빼거나 이름을 바꿔도(= 그 자리 화면이 조용히 빈다 — 옵셔널 디코드) 아무도 모른다.
    // 늘기만 하면 디코더는 무사하지만 줄면 빈다 — 그래서 **정확 집합**을 마이그레이션 사후 단언 상수와 잰다.
    @Test(.enabled(if: rfcMigrationGate))
    func 봉투_키가_마이그레이션_v_keys_와_같다() throws {
        let keys = try rfcMigrationKeyArrays(try rfcMigrationText())
        for name in ["state", "match", "move", "user", "lobby", "lobby_me", "lobby_user", "lobby_match", "peer"] {
            #expect(keys[name] != nil, "마이그레이션에 v_\(name)_keys 가 없다")
        }
        // 매니페스트가 적은 키 집합도 같은 상수다(서버 갈래가 뽑은 시점과 지금 마이그레이션이 같은가).
        let manifestKeys = try #require(try rfcServerJSON("_manifest.json")["keys"] as? [String: [String]])
        for (name, list) in manifestKeys {
            #expect(Set(list) == keys[name], "매니페스트 keys.\(name) 가 마이그레이션과 다르다")
        }
        var states = 0
        for (file, state) in try rfcServerStates() {
            states += 1
            #expect(rfcKeySet(state) == keys["state"], "\(file): state 키")
            #expect(rfcKeySet(state["match"]) == keys["match"], "\(file): match 키")
            for move in (state["moves"] as? [[String: Any]]) ?? [] {
                #expect(Set(move.keys) == keys["move"], "\(file): moves[] 키")
            }
            for key in ["black_user", "white_user", "opponent"] where state[key] is [String: Any] {
                #expect(rfcKeySet(state[key]) == keys["user"], "\(file): \(key) 키")
            }
        }
        #expect(states == 30, "상태가 실린 픽스처 \(states)장")
        var lobbies = 0
        for file in try rfcServerFiles() where file.hasPrefix("reversi_lobby__") {
            let top = try rfcServerJSON(file)
            guard top["status"] as? String == "ok" else { continue }
            lobbies += 1
            #expect(rfcKeySet(top) == keys["lobby"], "\(file): lobby 키")
            let me = try #require(top["me"] as? [String: Any])
            #expect(Set(me.keys) == keys["lobby_me"], "\(file): me 키")
            for user in (top["users"] as? [[String: Any]]) ?? [] {
                #expect(Set(user.keys) == keys["lobby_user"], "\(file): users[] 키")
            }
            for row in (me["incoming"] as? [[String: Any]]) ?? [] {
                #expect(rfcKeySet(row["from"]) == keys["peer"], "\(file): incoming[].from 키")
            }
            if let outgoing = me["outgoing"] as? [String: Any] {
                #expect(rfcKeySet(outgoing["to"]) == keys["peer"], "\(file): outgoing.to 키")
            }
        }
        #expect(lobbies == 3)
    }

    // 없으면: 서버 판정(SQL)과 Swift 규칙이 갈려도(합법 수·뒤집힌 칸·끝 분류·WOF 점수) 스텁 시험은 서버 원문을 그대로 믿어 초록이다.
    // 원문 값을 **Swift 규칙으로 다시 셈한** 값과 잰다(체스 독립 산식과 같은 방식). 씨앗 판(수 기록이 1 부터가 아닌 판)도 있어
    // 시작 판 재생 대신 "마지막 돌 한 수를 되돌려 다시 둔다" 로 잰다.
    @Test func 독립_산식_서버_판과_Swift_규칙이_같다() throws {
        var legalChecked = 0
        var undoChecked = 0
        var scored = 0
        for (file, state) in try rfcServerStates() {
            let match = try #require(state["match"] as? [String: Any])
            let boardText = try #require(match["board"] as? String, "\(file): 판 글자")
            let board = try #require(ReversiBoard(string: boardText), "\(file): 판")
            let discs = try #require(match["discs"] as? [String: Any])
            #expect(ReversiCounts(black: rfcInt(discs["black"]) ?? -1, white: rfcInt(discs["white"]) ?? -1,
                                  empty: rfcInt(discs["empty"]) ?? -1) == board.counts, "\(file): discs")
            let status = match["status"] as? String
            let legal = (state["legal_moves"] as? [NSNumber])?.map(\.intValue) ?? []
            let myColor = (state["my_color"] as? String).flatMap(ReversiColor.init(rawValue:))
            let turn = (match["turn"] as? String).flatMap(ReversiColor.init(rawValue:))
            if status == "active" {
                let mover = try #require(turn, "\(file): active 인데 차례가 없다")
                #expect(ReversiRules.hasLegalMove(board, color: mover), "\(file): 차례 주인이 둘 곳이 없다(V-09 불변식)")
                if let myColor, myColor == mover {
                    #expect(legal == ReversiRules.legalMoves(board, color: mover), "\(file): legal_moves")
                    legalChecked += 1
                } else {
                    #expect(legal.isEmpty, "\(file): 내 차례가 아닌데 legal_moves 가 있다")
                }
                let started = try #require(rfcDouble(match["turn_started_ms"]))
                let deadline = try #require(rfcDouble(match["deadline_ms"]))
                #expect(deadline - started == Double((rfcInt(state["turn_seconds"]) ?? 0) * 1000), "\(file): 마감 = 시작 + 30초")
            } else {
                #expect(legal.isEmpty, "\(file): 진행 중이 아닌데 legal_moves 가 있다")
                #expect(match["deadline_ms"] is NSNull, "\(file): 진행 중이 아닌데 마감이 있다")
            }
            if status == "finished" {
                let reason = match["end_reason"] as? String
                if let score = match["score"] as? [String: Any] {
                    // 자연 종료 — WOF 점수 · 끝 분류가 Swift 와 같다(V-10·V-11).
                    let swift = try #require(ReversiRules.score(board), "\(file): 끝난 판인데 Swift 는 안 끝났다고 한다")
                    #expect(rfcInt(score["black"]) == swift.black && rfcInt(score["white"]) == swift.white, "\(file): 점수")
                    #expect(match["result"] as? String == swift.result.rawValue, "\(file): 결과")
                    #expect(reason == ReversiRules.endKind(board)?.rawValue, "\(file): 끝 분류")
                    scored += 1
                } else {
                    #expect(reason == "resign" || reason == "abandoned", "\(file): 점수 없는 자연 종료")
                }
            }
            // 마지막 돌 한 수를 되돌려 다시 두면 서버 판이 나와야 한다(뒤에 패스만 있을 때).
            let moves = (state["moves"] as? [[String: Any]]) ?? []
            if let lastIndex = moves.lastIndex(where: { $0["kind"] as? String == "stone" }),
               moves[(lastIndex + 1)...].allSatisfy({ $0["kind"] as? String == "pass" }) {
                let row = moves[lastIndex]
                let color = try #require((row["color"] as? String).flatMap(ReversiColor.init(rawValue:)))
                let idx = try #require(rfcInt(row["idx"]))
                let flipped = (row["flipped"] as? [NSNumber])?.map(\.intValue) ?? []
                var cells = Array(board.string)
                cells[idx] = "."
                for cell in flipped { cells[cell] = color.opponent.cell }
                let prior = try #require(ReversiBoard(string: String(cells)))
                guard case .success(let outcome) = ReversiRules.play(prior, color: color, idx: idx) else {
                    Issue.record("\(file): 되돌린 판에서 그 수가 불법이다")
                    continue
                }
                #expect(outcome.board == board, "\(file): 다시 둔 판이 서버 판과 다르다")
                #expect(outcome.flipped == flipped, "\(file): 뒤집힌 칸")
                let passes = moves.count - 1 - lastIndex
                #expect(outcome.passed == (passes == 1), "\(file): 뒤따른 패스 줄")
                if status == "active" { #expect(outcome.next == turn, "\(file): 다음 차례") }
                undoChecked += 1
            }
        }
        #expect(legalChecked == 6, "내 차례 원문 \(legalChecked)장")
        #expect(undoChecked == 10, "되돌려 다시 둔 원문 \(undoChecked)장")
        #expect(scored == 7)
        // 시작 판 재생 — 수 기록이 1 부터 빠짐없는 원문 하나(첫 수 d3).
        let firstMove = try #require(try rfcServerJSON("reversi_move__ok.json")["state"] as? [String: Any])
        let firstMatch = try #require(firstMove["match"] as? [String: Any])
        guard case .success(let replay) = ReversiRules.play(.start, color: .black, idx: 19) else {
            Issue.record("시작 판 d3 가 불법이다")
            return
        }
        #expect(replay.board.string == firstMatch["board"] as? String)
    }

    // 없으면: 앱 요청 본문 키가 서버 인자 이름과 한 글자만 달라도(PostgREST 는 본문 키 집합으로 함수를 고른다 → PGRST202)
    // 스텁 시험은 전부 초록이다. 손으로 적은 이름(C1 시험)이 아니라 **마이그레이션 원문**과 잰다.
    @Test(.enabled(if: rfcMigrationGate))
    func 요청_본문_키가_마이그레이션_인자_이름과_같다() throws {
        let sql = try rfcMigrationText()
        let bodies: [(ReversiWire.RPC, Set<String>)] = [
            (.lobby, try rfcKeys(ReversiProtocolRequest())),
            (.ranking, try rfcKeys(ReversiProtocolRequest())),
            (.challenge, try rfcKeys(ReversiChallengeRequest(pOpponent: rfcPeer, pStake: 3))),
            (.cancel, try rfcKeys(ReversiMatchRequest(pMatchId: rfcMatch))),
            (.resign, try rfcKeys(ReversiMatchRequest(pMatchId: rfcMatch))),
            (.respond, try rfcKeys(ReversiRespondRequest(pMatchId: rfcMatch, pAccept: true))),
            (.state, try rfcKeys(ReversiStateRequest(pMatchId: rfcMatch, pSinceSeq: 0))),
            (.move, try rfcKeys(ReversiMoveRequest(pMatchId: rfcMatch, pExpectedSeq: 0, pIdx: 19))),
            (.watch, try rfcKeys(ReversiWatchRequest(pMatchId: rfcMatch, pSinceSeq: 0))),
            (.watchLive, try rfcKeys(ReversiWatchRequest(pMatchId: rfcMatch, pSinceSeq: 0))),
        ]
        #expect(Set(bodies.map(\.0)) == Set(ReversiWire.RPC.allCases))
        for (rpc, keys) in bodies {
            let arguments = try #require(try rfcMigrationArguments(sql, function: rpc.rawValue),
                                         "마이그레이션에 \(rpc.rawValue) 정의가 없다")
            #expect(Set(arguments) == keys, "\(rpc.rawValue): 서버 인자 \(arguments) · 앱 본문 \(keys.sorted())")
            #expect(arguments.first == "p_protocol", "\(rpc.rawValue): p_protocol 이 첫 인자가 아니다")
        }
    }

    // 없으면: 관전 응답에 참가자 전용 칸(내 색·남의 지갑·둘 수 있는 칸)이 섞여 나가도(= 제3자에게 남의 루비가 간다) 초록이고,
    // 스토어가 관전 응답을 대국으로 착각할 길이 열려도 안 보인다.
    @Test func 관전_원문은_참가자_칸이_비어_있다() throws {
        var seen = 0
        for file in ["reversi_watch__ok.json", "reversi_watch_live__ok.json"] {
            let state = try #require(try rfcServerJSON(file)["state"] as? [String: Any])
            seen += 1
            for key in ["my_color", "opponent", "my_auto_streak", "opponent_auto_streak", "ruby_balance"] {
                #expect(state[key] is NSNull, "\(file): \(key) 가 실렸다")
            }
            #expect((state["legal_moves"] as? [Any])?.isEmpty == true, "\(file): legal_moves 가 실렸다")
        }
        #expect(seen == 2)
        // watch 는 관전자 수를 안 센다(0) — watch_live 만 센다(1, 관전자 D 한 명).
        #expect(rfcInt((try rfcServerJSON("reversi_watch__ok.json")["state"] as? [String: Any])?["watchers"]) == 0)
        #expect(rfcInt((try rfcServerJSON("reversi_watch_live__ok.json")["state"] as? [String: Any])?["watchers"]) == 1)
    }
}
