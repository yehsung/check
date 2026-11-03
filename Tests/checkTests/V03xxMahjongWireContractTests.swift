@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 와이어 디코딩 단위 시험(갈래 C1 — SPEC §3.4~3.6 · §4.4). 서버 픽스처(S2) 원문 대조 · 봉투 키 집합 =
// 마이그레이션 `v_*_keys` · 숨은 정보 원문 검사는 C2 가 S 픽스처로 더한다. 여기서는 §3.6 모양 손 픽스처로
// '이름·모양·접기'만 잰다. 디코더·인코더는 `SupabaseWorkService` 와 같은 설정(snake_case ↔ camelCase).

@Suite("아잉 마작 와이어 — RPC 이름 · status 어휘 · 요청 본문 · 응답 디코딩 · 모르는 값 접기")
struct V03xxMahjongWireContractTests {
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func keys(of body: some Encodable) throws -> Set<String> {
        let data = try encoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set(object?.keys.map { $0 } ?? [])
    }

    private static func tile(_ id: Int) -> MahjongTile { MahjongTile(id: id)! }

    /// §3.6 모양의 루비 판 state(내 차례 · 동 퐁 한 번 · 주인 전용 뽑은 패).
    static let activeState = #"""
    {"match":{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","status":"active","stake":5,"format":"tonpuu","is_public":false,
      "host":{"id":"11111111-1111-1111-1111-111111111111","display_name":"방장","avatar_url":null,"character":"aing"},
      "seq":42,"created_ms":1762150000000,"room_expires_ms":null,"started_ms":1762150100000,"finished_ms":null,"end_reason":null,
      "phase":"turn","hand_index":3,"round":0,"hand_no":2,"honba":1,"kyotaku":1,"dealer_seat":2,"extension":false,
      "wall_remaining":51,"dora_indicators":[88],"kan_count":0,"turn_seat":1,
      "wake_at_ms":1762150206000,"wake_seat":3,"backup_at_ms":1762150229000,"next_hand_ms":null,
      "base_ms":5000,"bank_full_ms":20000,"grace_ms":1000},
     "members":[],
     "seats":[
      {"seat_no":0,"user":{"user_id":"11111111-1111-1111-1111-111111111111","display_name":"가","avatar_url":null,"character":null,"center":"서울"},
       "wind":"W","is_dealer":false,"score":24000,"hand_count":10,
       "melds":[{"type":"pon","tiles":[108,109,110],"called":110,"from_seat":3}],
       "discards":[{"tile":4,"tsumogiri":true,"riichi":false,"taken":false}],
       "riichi":false,"away":false,"deleted":false,"final_rank":null,"final_score":null,"payout":null},
      {"seat_no":3,"user":null,"wind":"S","is_dealer":false,"score":26000,"hand_count":13,"melds":[],
       "discards":[{"tile":110,"tsumogiri":false,"riichi":false,"taken":true}],
       "riichi":false,"away":true,"deleted":true,"final_rank":null,"final_score":null,"payout":null}],
     "my_seat":1,"my_hand":[0,8,12,20,24,36,40,44,60,64,72,76,100],"my_drawn":135,"my_waits":[],"my_furiten":["temporary"],
     "my_decision":{"kind":"turn","seq":42,"decision_seq":17,"started_ms":1762150201000,"deadline_ms":1762150206000,
       "not_before_ms":null,"bank_ms":20000,"discard":[0,8,135],"riichi":[],"tsumo":false,"ankan":[],"kakan":[],"kyuushu":false},
     "my_away":null,
     "events":[{"seq":41,"kind":"call","seat":0,"at_ms":1762150200000,"type":"pon","tiles":[108,109,110],"called":110,"from_seat":3},
               {"seq":42,"kind":"draw","seat":1,"at_ms":1762150201000,"rinshan":false,"tile":135,"priv":{"tile":135}}],
     "last_hand":null,"reactions":[{"seat_no":0,"key":"joy","at_ms":1762150199000}],
     "ruby_balance":120,"server_now_ms":1762150201500}
    """#

    @Test("RPC 13개 이름 · 프로토콜 1 · 교착 재시도는 쓰기 + state 만")
    func rpcNamesAndRetryPolicy() {
        // 없으면: RPC 하나를 빠뜨리거나 이름 글자를 틀려도(예: mahjong_calls) 계약 시험 전까지 초록 — 그 동작이 PGRST202 로 죽는다.
        #expect(MahjongWire.protocolVersion == 1)
        #expect(MahjongWire.RPC.all == [
            "mahjong_lobby", "mahjong_create", "mahjong_invite", "mahjong_join", "mahjong_decline", "mahjong_leave",
            "mahjong_start", "mahjong_state", "mahjong_act", "mahjong_call", "mahjong_back", "mahjong_react",
            "mahjong_ranking",
        ])
        let retrying = Set(MahjongWire.RPC.allCases.filter(\.retriesDeadlockOnce).map(\.rawValue))
        #expect(retrying == [
            "mahjong_create", "mahjong_invite", "mahjong_join", "mahjong_decline", "mahjong_leave", "mahjong_start",
            "mahjong_state", "mahjong_act", "mahjong_call", "mahjong_back",
        ])
    }

    @Test("status 어휘 = §3.4 목록(too_early 포함) · 모르는 값은 .unknown")
    func statusVocabulary() throws {
        // 없으면: 서버 어휘 하나(too_early · window_closed)를 클라가 모르면 .unknown 으로 접혀 '다시 시도' 문구가 뜬다.
        let spec = [
            "ok", "unauthorized", "unsupported_client", "invalid", "blackout", "target_focused", "target_outdated", "busy",
            "target_busy", "already_in_room", "already_invited", "room_full", "too_many_invites", "room_closed",
            "not_invited", "not_host", "not_enough_players", "seats_dropped", "insufficient", "not_found", "not_active",
            "not_your_turn", "stale", "illegal", "window_closed", "too_fast", "too_early",
        ]
        let known = MahjongRPCStatus.allCases.filter { $0 != .unknown }.map(\.rawValue)
        #expect(Set(known) == Set(spec))
        #expect(known.count == spec.count)
        for raw in spec {
            let status = try Self.decoder().decode(MahjongRPCStatus.self, from: Data("\"\(raw)\"".utf8))
            #expect(status.rawValue == raw)
        }
        #expect(try Self.decoder().decode(MahjongRPCStatus.self, from: Data(#""future_status""#.utf8)) == .unknown)
    }

    @Test("요청 본문 키 = SQL 인자 이름(p_protocol 늘 포함) · 패는 id 정수")
    func requestBodyKeys() throws {
        // 없으면: 카멜 → 스네이크 변환이 어긋난 키(p_match_i_d 등)를 PostgREST 가 다른 서명으로 읽어 PGRST202 가 난다.
        #expect(try Self.keys(of: MahjongProtocolRequest()) == ["p_protocol"])
        #expect(try Self.keys(of: MahjongCreateRequest(pStake: 5, pPublic: true, pFormat: "hanchan"))
            == ["p_protocol", "p_stake", "p_public", "p_format"])
        #expect(try Self.keys(of: MahjongMatchRequest(pMatchId: "m")) == ["p_protocol", "p_match_id"])
        #expect(try Self.keys(of: MahjongInviteRequest(pMatchId: "m", pUserId: "u"))
            == ["p_protocol", "p_match_id", "p_user_id"])
        #expect(try Self.keys(of: MahjongStateRequest(pMatchId: "m", pSinceSeq: 3))
            == ["p_protocol", "p_match_id", "p_since_seq"])
        #expect(try Self.keys(of: MahjongActRequest(pMatchId: "m", pExpectedSeq: 1, pAction: "discard"))
            == ["p_protocol", "p_match_id", "p_expected_seq", "p_action", "p_tiles"])
        #expect(try Self.keys(of: MahjongCallRequest(pMatchId: "m", pWindowId: 2, pAction: "pass"))
            == ["p_protocol", "p_match_id", "p_window_id", "p_action", "p_tiles"])
        #expect(try Self.keys(of: MahjongReactRequest(pMatchId: "m", pKey: "joy")) == ["p_protocol", "p_match_id", "p_key"])

        let act = MahjongActRequest(pMatchId: "m", pExpectedSeq: 17, pAction: "riichi", pTiles: [Self.tile(16)])
        let text = String(decoding: try Self.encoder().encode(act), as: UTF8.self)
        #expect(text == #"{"p_action":"riichi","p_expected_seq":17,"p_match_id":"m","p_protocol":1,"p_tiles":[16]}"#)
    }

    @Test("로비 응답(§3.5) — 형식·상수·내 방·전적 avg_rank(0판이면 null)")
    func lobbyDecodes() throws {
        // 없으면: v1.0.2 레코드 avg_rank 칸을 빠뜨리거나 null 을 비옵셔널로 받아 0판인 사람의 로비가 통째로 실패한다.
        let json = #"""
        {"status":"ok","server_now_ms":1762150000000,"stakes":[3,5,10],"formats":["tonpuu","hanchan"],"room_ttl_seconds":600,
         "max_invites":6,"base_ms":5000,"bank_ms":20000,
         "me":{"ruby_balance":80,"record":{"games":0,"firsts":0,"seconds":0,"thirds":0,"fourths":0,"avg_rank":null},
               "room":{"id":"22222222-2222-2222-2222-222222222222","host":{"id":"11111111-1111-1111-1111-111111111111",
                       "display_name":"방장","avatar_url":null,"character":null},"stake":5,"format":"hanchan","is_public":true,
                       "expires_at_ms":1762150600000,"max_seats":4,
                       "seats":[{"user":{"id":"11111111-1111-1111-1111-111111111111","display_name":"방장","avatar_url":null,"character":null},"state":"joined"},
                                {"user":{"id":"33333333-3333-3333-3333-333333333333","display_name":"나","avatar_url":null,"character":null},"state":"joined"},
                                {"user":{"id":"44444444-4444-4444-4444-444444444444","display_name":"다","avatar_url":null,"character":null},"state":"invited"}]},
               "active_match_id":null},
         "invites":[],"public_rooms":[],
         "users":[{"id":"55555555-5555-5555-5555-555555555555","display_name":"라","avatar_url":null,"character":null,
                   "is_working":true,"in_match":false,"capable":true,"focus_mode":false}]}
        """#
        let lobby = try Self.decoder().decode(MahjongLobbyResponse.self, from: Data(json.utf8))
        #expect(lobby.status == .ok)
        #expect(lobby.formats == ["tonpuu", "hanchan"])
        #expect(lobby.roomTtlSeconds == 600 && lobby.maxInvites == 6 && lobby.baseMs == 5_000 && lobby.bankMs == 20_000)
        #expect(lobby.me?.record?.games == 0)
        #expect(lobby.me?.record?.avgRank == nil)
        #expect(lobby.me?.room?.formatKind == .hanchan)
        #expect(lobby.me?.room?.joinedCount == 2)
        #expect(lobby.me?.activeMatchId == nil)
        #expect(lobby.users?.first?.capable == true)
    }

    @Test("순위 응답(v1.0.2) — me.rank null · avg_rank 소수 · rows 순서는 서버 것")
    func rankingDecodes() throws {
        // 없으면: 10판 전 me.rank null 을 비옵셔널로 받아 순위 화면이 통째로 비거나, avg_rank 를 정수로 받아 2.25 가 깨진다.
        let json = #"""
        {"status":"ok","server_now_ms":1762150000000,"record_since_ms":null,
         "me":{"rank":null,"games":7,"firsts":2,"seconds":2,"thirds":2,"fourths":1,"avg_rank":2.2857142857},
         "rows":[{"rank":1,"user_id":"55555555-5555-5555-5555-555555555555","display_name":"라","avatar_url":null,
                  "character":null,"center":"부산","games":12,"firsts":6,"avg_rank":1.75},
                 {"rank":2,"user_id":"66666666-6666-6666-6666-666666666666","display_name":"마","avatar_url":null,
                  "character":null,"center":null,"games":40,"firsts":12,"avg_rank":2.25}]}
        """#
        let ranking = try Self.decoder().decode(MahjongRankingResponse.self, from: Data(json.utf8))
        #expect(ranking.recordSinceMs == nil)
        #expect(ranking.me?.rank == nil)
        #expect(ranking.me?.games == 7)
        #expect(ranking.me?.gamesUntilRanked == 3)
        #expect(ranking.rows?.map(\.avgRank) == [1.75, 2.25])
        #expect(ranking.rows?.map(\.rank) == [1, 2])
    }

    @Test("state(§3.6) — 판·자리·내 결정·사건 priv·반응이 원문 그대로 읽힌다")
    func activeStateDecodes() throws {
        // 없으면: 칸 이름 하나(extension · decision_seq · priv)가 어긋나도 옵셔널이라 조용히 nil — 화면이 깨우기·낡음 판정을 잃는다.
        let state = try Self.decoder().decode(MahjongStatePayload.self, from: Data(Self.activeState.utf8))
        let match = try #require(state.match)
        #expect(match.matchStatus == .active)
        #expect(match.formatKind == .tonpuu)
        #expect(match.phase == "turn" && match.handIndex == 3 && match.turnSeat == 1)
        #expect(match.extension == false)
        #expect(match.doraIndicators == [Self.tile(88)])
        #expect(match.wakeSeat == 3 && match.backupAtMs == 1_762_150_229_000)
        #expect(state.seats?.count == 2)
        #expect(state.seats?[1].user == nil && state.seats?[1].deleted == true && state.seats?[1].away == true)
        #expect(state.seats?[0].melds?.first?.meld?.type == .pon)
        #expect(state.mySeat == 1 && state.myHand?.count == 13 && state.myDrawn == Self.tile(135))
        #expect(state.myFuriten == ["temporary"])
        guard case .turn(let turn)? = state.myDecision else {
            Issue.record("내 차례 결정이 안 읽혔다")
            return
        }
        #expect(turn.decisionSeq == 17 && turn.notBeforeMs == nil && turn.discard.count == 3)
        #expect(state.events?.map(\.kind) == ["call", "draw"])
        #expect(state.events?.last?.priv?.tile == Self.tile(135))
        #expect(state.events?.contains(where: \.isAutoDiscard) == false)
        #expect(state.reactions?.first?.sticker == .joy)
        #expect(state.rubyBalance == 120)
        let key = try #require(MahjongDecisionKey.of(state))
        #expect(key == MahjongDecisionKey(
            matchID: match.id, handIndex: 3, kind: "turn", anchor: 17, startedMs: 1_762_150_201_000))
    }

    @Test("모르는 값 접기(CC-07) — 새 역·새 사건·새 부로·새 끝 이유 하나에 state 가 통째로 실패하지 않는다")
    func unknownOpenVocabularyFolds() throws {
        // 없으면: 규칙 2판의 새 역 id 하나에 옛 맥의 판 화면이 멎는다(메모리 enum-widening-needs-capability-negotiation).
        var text = Self.activeState
        text = text.replacingOccurrences(of: #""type":"pon","tiles":[108,109,110],"called":110,"from_seat":3}],"#,
                                         with: #""type":"future_meld","tiles":[108,109,110],"called":110,"from_seat":3}],"#)
        text = text.replacingOccurrences(of: #""kind":"call","seat":0"#, with: #""kind":"future_event","seat":0"#)
        text = text.replacingOccurrences(of: #""end_reason":null"#, with: #""end_reason":"future""#)
        text = text.replacingOccurrences(
            of: #""last_hand":null"#,
            with: #""last_hand":{"hand_index":2,"kind":"win","reason":null,"wins":[{"seat":0,"from_seat":2,"hand":[1,5,9],"#
                + #""melds":[],"win_tile":13,"yaku":[["future_yaku",2],["riichi",1]],"yakuman":0,"han":3,"fu":40,"limit":"","#
                + #""dora":0,"aka":0,"ura":0,"ura_indicators":[12],"total":5200,"pao":{"seat":3,"yaku":"future_yaku"}}],"#
                + #""tenpai":[],"nagashi":[],"deltas":[5200,0,-5200,0],"scores_after":[30200,25000,19800,25000],"#
                + #""bonus_to":0,"renchan":false}"#)
        #expect(text != Self.activeState)
        let state = try Self.decoder().decode(MahjongStatePayload.self, from: Data(text.utf8))
        #expect(state.seats?[0].melds?.first?.type == "future_meld")
        #expect(state.seats?[0].melds?.first?.meld == nil)
        #expect(state.events?.first?.kind == "future_event")
        #expect(state.match?.endReason == "future")
        let win = try #require(state.lastHand?.wins?.first)
        #expect(win.yaku?.map(\.id) == ["future_yaku", "riichi"])
        #expect(win.yaku?.map(\.yakuKind) == [nil, .riichi])
        #expect(win.yaku.map { $0.map { MahjongNoticeText.yakuName($0.id) } }?.first == MahjongNoticeText.newYaku)
        #expect(win.pao?.yaku == "future_yaku" && win.pao?.pao == nil)
        // 기준선: 같은 역 칸을 엄격 열거(`MahjongYakuHan`)로 받으면 실패한다 — 원문 문자열 칸이 아니면 위가 빨강이다.
        #expect(throws: DecodingError.self) {
            try Self.decoder().decode([MahjongYakuHan].self, from: Data(#"[["future_yaku",2]]"#.utf8))
        }
    }

    @Test("모르는 결정 kind 는 my_decision 만 nil — 판 나머지는 읽힌다")
    func unknownDecisionKindFoldsToNil() throws {
        // 없으면: 새 결정 갈래 하나(예: 규칙 2판의 'pick')에 state 전체가 throw 해 판 화면이 멎는다.
        let text = Self.activeState.replacingOccurrences(of: #"{"kind":"turn","seq":42"#, with: #"{"kind":"pick","seq":42"#)
        #expect(text != Self.activeState)
        let state = try Self.decoder().decode(MahjongStatePayload.self, from: Data(text.utf8))
        #expect(state.myDecision == nil)
        #expect(state.match?.seq == 42 && state.myHand?.count == 13)
        // 기준선: 같은 결정 칸을 `MahjongDecision` 으로 바로 받으면 실패한다(감싸기가 없으면 위가 빨강).
        #expect(throws: DecodingError.self) {
            try Self.decoder().decode(MahjongDecision.self, from: Data(#"{"kind":"pick","seq":1}"#.utf8))
        }
    }

    @Test("state 왕복 — 연습판 엔진이 만든 payload 를 스네이크로 써서 다시 읽으면 같다(양방향 Codable)")
    func statePayloadRoundTrips() throws {
        // 없으면: 인코드 키가 디코드 키와 갈려(예: extension · my_decision kind) 엔진 payload 대조가 조용히 어긋난다.
        let state = try Self.decoder().decode(MahjongStatePayload.self, from: Data(Self.activeState.utf8))
        let again = try Self.decoder().decode(MahjongStatePayload.self, from: Self.encoder().encode(state))
        #expect(again == state)
    }

    @Test("거절 응답 — seats_dropped 의 uuid 열쇠 사전 · too_fast retry_ms · illegal reason")
    func actionResponseDecodes() throws {
        // 없으면: reasons 사전의 uuid 열쇠가 스네이크 변환에 망가지거나 칸이 빠져 '내가 빠졌다' 문구를 못 고른다.
        let json = #"""
        {"status":"seats_dropped","dropped":["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"],
         "reasons":{"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee":"unseen"},"retry_ms":4200,"reason":"not_option",
         "state":{"match":{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","status":"forming"},"members":[]},"server_now_ms":1}
        """#
        let response = try Self.decoder().decode(MahjongActionResponse.self, from: Data(json.utf8))
        #expect(response.status == .seatsDropped)
        #expect(response.dropped == ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"])
        #expect(response.reasons == ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee": "unseen"])
        #expect(response.retryMs == 4_200 && response.reason == "not_option")
        #expect(response.state?.match?.matchStatus == .forming)
        #expect(MahjongNoticeText.dropped(reason: response.reasons?.values.first) == MahjongNoticeText.droppedUnseen)
    }

    @Test("보이는 장수(CC-08) — 퐁 한 번: 울려 간 패는 강에서 안 센다")
    func visibleTilesCountsPonOnce() throws {
        // 없으면: 울린 패를 강(taken)과 부로에서 두 번 세어 '남은 패'가 하나 모자라게 보인다.
        let state = try Self.decoder().decode(MahjongStatePayload.self, from: Data(Self.activeState.utf8))
        let counts = MahjongVisibleTiles.counts(of: state)
        #expect(counts.count == 34)
        #expect(counts[27] == 3)
        #expect(MahjongVisibleTiles.unseen(kind: 27, in: state) == 1)
        // 기준선: 강을 다 세는 순진한 셈은 4 — 위 단언이 그 셈과 갈린다.
        var naive = 0
        for seat in state.seats ?? [] {
            let river: [MahjongTile] = (seat.discards ?? []).map(\.tile)
            let melded: [MahjongTile] = (seat.melds ?? []).flatMap(\.tiles)
            naive += (river + melded).filter { $0.kind == 27 }.count
        }
        #expect(naive == 4)
    }
}
