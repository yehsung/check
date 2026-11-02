import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기(reversi) — 와이어 디코딩 계약(갈래 C1). 출시 버전이 정해지면 `git mv` + `@Suite` 이름을 함께 바꾼다(SPEC §1).
//
// 지금은 설계서 §3.5(로비)·§3.6(state) 모양으로 **손으로 쓴 픽스처**를 앱 디코더와 같은 설정(`SupabaseWorkService.init` —
// snake_case → camelCase)로 읽어 값까지 대조한다. 서버 갈래 픽스처(`FLIP/server/fixtures` → `Fixtures/reversi-rpc/`)가
// 들어오면 C2 가 같은 파일에서 원문 대조(매니페스트 · 봉투 키 = `v_*_keys` · 독립 산식)를 더하고 손 픽스처를 갈아 끼운다.
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
