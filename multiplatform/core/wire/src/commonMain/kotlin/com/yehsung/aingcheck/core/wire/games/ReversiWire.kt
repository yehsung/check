// 원본: Sources/CheckCore/ReversiWire.swift:1-485(RPC 이름 · status 어휘 · 요청 · 응답) · Sources/CheckCore/RealtimeLink.swift:130-136(reversiBroadcastEvent) @ 12624739
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// 아잉 뒤집기(내부 이름 reversi) 1:1 RPC 의 와이어 타입(요청·응답)과 RPC 이름 10개 — `/rest/v1/rpc/reversi_*`.
// 계약의 정본은 설계서 FLIP/SPEC.md §3.4(RPC·status) · §3.5(로비) · §3.6(state) · §4.3 이고, 서버는 20261108200000_reversi.sql 이다.
// 서비스 호출 10개는 core/net RpcReversi.kt, 판의 값 타입(판 · 색 · 수 기록 …)은 ReversiValues.kt 다.
//
// ── 테트리스·체스 와이어의 규약을 그대로 따른다(Swift 머리말 ①~⑤) ──
//  ① status 만 필수이고 나머지는 전부 Optional 이다. null 은 "모른다" 다.
//  ② 모르는 status 는 `unknown` 으로 접는다(새 status 는 프로토콜을 안 올린다, §3.4).
//  ③ 시각은 전부 epoch 밀리초이고 `Double` 로 읽는다. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 빈 `{}` 가 아니다 — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//  ⑤ 상태가 실리는 응답은 `{status, state}` 봉투 하나다(상태 키를 최상위에 펼치지 않는다). 거절 응답에도 판이 있으면 `state` 가 실린다.
//     쓰기 RPC(respond·move·resign)의 state 는 수 기록 전체다(p_since = 0).
//
// ── 리버시에서 정한 자리 ──
//  · 칸은 정수 `idx`(0~63) 하나로 주고받는다. x·y 두 칸은 없다.
//  · 판은 64자 `.bw` 문자열 하나이고 [ReversiBoard] 로 바로 디코드한다(판의 권위 — 잘못된 판이면 응답 전체가 던진다).
//  · 받은 신청은 로비 `me.incoming` 이 통째로 준다(별도 받은함 RPC 없음). 보낸 신청은 `me.outgoing` 하나.
//  · 사람 행의 id 키가 둘이다 — 로비(users · 신청의 from/to · matches 의 a/b)는 **`id`**, state 와 순위는 **`user_id`**.
//  · 비로그인은 `unauthorized` 다.

/** Swift `ReversiWire` — 아잉 뒤집기 RPC 프로토콜과 이름 묶음. */
object ReversiWire {
    /** 서버 `reversi_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다. */
    const val protocolVersion: Long = 1

    /**
     * 실시간 초인종의 브로드캐스트 이벤트 이름(Swift `RealtimeLinkConstants.reversiBroadcastEvent`). 서버 `reversi__ring` 의
     * `realtime.send({v:1, m:<판 id>, s:<move_count>}, 'reversi', poke_topic(받는 사람), true)` 와 문자 그대로 같다.
     * payload 는 믿지 않는다 — 이름만 보고 판 상태를 한 번 다시 읽는다(Swift `ReversiStore.handleSignal`). **take_pokes 가 아니다.**
     * 링(core/net RealtimeLink)에 이 이름의 가지를 다는 일은 배선 단계 몫이다(그 전엔 drain 으로 떨어진다).
     */
    const val broadcastEvent: String = "reversi"

    /** Swift `ReversiWire.RPC` — 클라가 부르는 RPC 이름 전부(서버 함수 이름 그대로). */
    enum class RPC(override val rawValue: String) : SwiftRawValued {
        lobby("reversi_lobby"),
        challenge("reversi_challenge"),
        cancel("reversi_cancel"),
        respond("reversi_respond"),
        state("reversi_state"),
        move("reversi_move"),
        resign("reversi_resign"),
        ranking("reversi_ranking"),
        watch("reversi_watch"),
        watchLive("reversi_watch_live");

        /**
         * 교착(40P01) 한 번 재시도 여부(§4.3). 쓰기 전부 + `reversi_state`(서버가 따라잡기로 자동 착수를 정산한다).
         * 로비·순위·관전 둘은 읽기 전용이라 끈다 — 실패하면 다음 계기가 다시 읽는다.
         */
        val retriesDeadlockOnce: Boolean
            get() = when (this) {
                challenge, cancel, respond, state, move, resign -> true
                lobby, ranking, watch, watchLive -> false
            }

        companion object {
            val all: List<String> = entries.map { it.rawValue }
        }
    }
}

/** Swift `ReversiRPCStatus` — RPC status 어휘(§3.4, 서버와 같은 집합). **모르는 값은 [unknown]**. 상수 이름 = Swift case 이름. */
@Serializable(with = ReversiRPCStatus.Serializer::class)
enum class ReversiRPCStatus(override val rawValue: String) : SwiftRawValued {
    ok("ok"),
    unauthorized("unauthorized"),
    unsupportedClient("unsupported_client"),
    invalid("invalid"),
    blackout("blackout"),
    targetFocused("target_focused"),
    targetOutdated("target_outdated"),
    busy("busy"),
    targetBusy("target_busy"),
    alreadyPending("already_pending"),
    insufficient("insufficient"),
    notFound("not_found"),
    notPending("not_pending"),
    expired("expired"),
    notActive("not_active"),
    notYourTurn("not_your_turn"),

    /** 보낸 `p_expected_seq` 가 서버 `move_count` 와 다르다(화면이 낡았다). **문구 없이** 실려 온 state 로 맞춘다. 판정 순서가 `not_your_turn` 보다 앞이다. */
    stale("stale"),

    /** 둘 수 없는 칸(`reason` = out_of_range · occupied · no_flip). 판은 그대로이고 state 가 실려 온다. */
    illegal("illegal"),

    /** 착수 직전 서버 따라잡기가 **내 색**을 시간 초과로 대신 뒀다(`auto_placed_count`). 내 수는 쓰지 않았다. */
    autoPlaced("auto_placed"),
    unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<ReversiRPCStatus>("ReversiRPCStatus", entries, unknown)
}

// ---------- 요청 본문(키 = 서버 인자 이름 — 첫 인자는 늘 p_protocol) ----------

/** reversi_lobby / reversi_ranking 본문. { p_protocol }. */
@Serializable
data class ReversiProtocolRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
)

/** reversi_challenge 본문. { p_protocol, p_opponent, p_stake }. */
@Serializable
data class ReversiChallengeRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_opponent") val pOpponent: String,
    @SerialName("p_stake") val pStake: Long,
)

/** reversi_cancel / reversi_resign 본문. { p_protocol, p_match_id }. */
@Serializable
data class ReversiMatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
)

/** reversi_respond 본문. { p_protocol, p_match_id, p_accept }. */
@Serializable
data class ReversiRespondRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_accept") val pAccept: Boolean,
)

/** reversi_state 본문. { p_protocol, p_match_id, p_since_seq } — 수 기록은 `seq > p_since_seq` 만 온다. */
@Serializable
data class ReversiStateRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Long,
)

/** reversi_move 본문. { p_protocol, p_match_id, p_expected_seq, p_idx }. `p_expected_seq` 는 화면이 본 `move_count`(패스 포함 기록 수)다 — 다르면 `stale`. */
@Serializable
data class ReversiMoveRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_expected_seq") val pExpectedSeq: Long,
    @SerialName("p_idx") val pIdx: Long,
)

/** reversi_watch / reversi_watch_live 본문. { p_protocol, p_match_id, p_since_seq }. */
@Serializable
data class ReversiWatchRequest(
    @SerialName("p_protocol") val pProtocol: Long = ReversiWire.protocolVersion,
    @SerialName("p_match_id") val pMatchId: String,
    @SerialName("p_since_seq") val pSinceSeq: Long,
)

// ---------- 응답 행 — 로비(§3.5) ----------

/** Swift `ReversiPeerRow` — 이름 정도만 실린 사람(신청의 `from`·`to` · 로비 matches 의 `a`·`b`). id 키는 **`id`** 다. */
@Serializable
data class ReversiPeerRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
)

/**
 * Swift `ReversiLobbyUserRow` — 로비 `users[]` 한 줄. `capable` 이 null 이면 **불가**로 읽는다(스토어) — 모르는 상대에게 신청해
 * `target_outdated` 를 받는 것보다 낫다. `in_match` 는 서버 `lobby__others.busy`(= `game__busy_users`)다.
 */
@Serializable
data class ReversiLobbyUserRow(
    @SerialName("id") val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("is_working") val isWorking: Boolean? = null,
    @SerialName("in_match") val inMatch: Boolean? = null,
    @SerialName("capable") val capable: Boolean? = null,
    @SerialName("focus_mode") val focusMode: Boolean? = null,
)

/** Swift `ReversiInviteRow` — 신청 한 건. 받은 것은 `from`, 보낸 것은 `to` 가 실린다. 서버는 만료 전 pending 만 싣는다. */
@Serializable
data class ReversiInviteRow(
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("from") val from: ReversiPeerRow? = null,
    @SerialName("to") val to: ReversiPeerRow? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("expires_at_ms") val expiresAtMs: Double? = null,
)

/** Swift `ReversiLobbyMe` — 로비 `me`. `incoming` 은 최근 순 20(신청 뒤 생긴 숨김·차단은 서버가 거른다). */
@Serializable
data class ReversiLobbyMe(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("active_match_id") val activeMatchId: String? = null,
    @SerialName("incoming") val incoming: List<ReversiInviteRow>? = null,
    @SerialName("outgoing") val outgoing: ReversiInviteRow? = null,
)

/** Swift `ReversiLobbyMatchRow` — 로비 "지금 대결 중" 한 줄(active 판, 최근 순 20). a/b 는 **uuid 오름차순**(색이 아니다). */
@Serializable
data class ReversiLobbyMatchRow(
    @SerialName("id") val id: String? = null,
    @SerialName("a") val a: ReversiPeerRow? = null,
    @SerialName("b") val b: ReversiPeerRow? = null,
    @SerialName("stake") val stake: Long? = null,
    /** 관전자 수(`match__watchers`). 없으면 0 으로 읽는다(스토어). */
    @SerialName("watchers") val watchers: Long? = null,
    @SerialName("started_at_ms") val startedAtMs: Double? = null,
)

/** Swift `ReversiLobbyResponse` — reversi_lobby 응답(§3.5). 숫자 상수(판돈·차례 초·유예·신청 TTL·자리 비움 연속 수)도 서버가 말한다. */
@Serializable
data class ReversiLobbyResponse(
    @SerialName("status") val status: ReversiRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("turn_seconds") val turnSeconds: Long? = null,
    @SerialName("turn_grace_seconds") val turnGraceSeconds: Long? = null,
    @SerialName("invite_ttl_seconds") val inviteTtlSeconds: Long? = null,
    @SerialName("auto_abandon_streak") val autoAbandonStreak: Long? = null,
    @SerialName("me") val me: ReversiLobbyMe? = null,
    @SerialName("users") val users: List<ReversiLobbyUserRow>? = null,
    @SerialName("matches") val matches: List<ReversiLobbyMatchRow>? = null,
)

// ---------- 응답 행 — state(§3.6, 참가자·관전 공용) ----------

/** Swift `ReversiPlayerRow` — state 의 사람 한 칸(`black_user`·`white_user`·`opponent`). id 키는 **`user_id`** 다. */
@Serializable
data class ReversiPlayerRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
)

/** Swift `ReversiScoreRow` — WOF 점수(자연 종료만 — 기권·abandoned 판은 null, V-15). 빈칸은 이긴 쪽에 더해져 합이 늘 64 다. */
@Serializable
data class ReversiScoreRow(
    @SerialName("black") val black: Long? = null,
    @SerialName("white") val white: Long? = null,
)

/**
 * Swift `ReversiMatchRow` — 판 행(`state.match`). 사람 칸(challenger·opponent·black·white·winner)은 **uuid 문자열**이다 —
 * 얼굴은 state 최상위의 `black_user`·`white_user`·`opponent` 가 준다.
 */
@Serializable
data class ReversiMatchRow(
    @SerialName("id") val id: String? = null,
    /** 'pending' | 'declined' | 'cancelled' | 'expired' | 'active' | 'finished'. [matchStatus] 로 접는다. */
    @SerialName("status") val status: String? = null,
    @SerialName("stake") val stake: Long? = null,
    @SerialName("challenger") val challenger: String? = null,
    @SerialName("opponent") val opponent: String? = null,
    /** 수락 때 무작위 배정. pending 이면 null. */
    @SerialName("black") val black: String? = null,
    @SerialName("white") val white: String? = null,
    /** 패스 포함 기록 수 = 마지막 seq. `p_expected_seq` 의 눈금. */
    @SerialName("move_count") val moveCount: Long? = null,
    /** 끝났거나 pending 이면 null. */
    @SerialName("turn") val turn: ReversiColor? = null,
    @SerialName("turn_started_ms") val turnStartedMs: Double? = null,
    /** turn_started + 30초 **표시값**(서버 유예 2초 미포함). active 가 아니면 null. */
    @SerialName("deadline_ms") val deadlineMs: Double? = null,
    @SerialName("invite_expires_ms") val inviteExpiresMs: Double? = null,
    @SerialName("started_ms") val startedMs: Double? = null,
    @SerialName("finished_ms") val finishedMs: Double? = null,
    @SerialName("result") val result: ReversiResult? = null,
    @SerialName("end_reason") val endReason: ReversiEndReason? = null,
    /** 이긴 사람의 uuid(무승부·진행 중이면 null). */
    @SerialName("winner") val winner: String? = null,
    /** 64자 `.bw` — **판의 권위**. */
    @SerialName("board") val board: ReversiBoard? = null,
    /** 판 위 실제 돌 수(늘 실린다, V-12). */
    @SerialName("discs") val discs: ReversiCounts? = null,
    /** 자연 종료만. */
    @SerialName("score") val score: ReversiScoreRow? = null,
) {
    val matchStatus: ReversiMatchStatus get() = ReversiMatchStatus.wire(status)
}

/**
 * Swift `ReversiStatePayload` — state 묶음(§3.6). state · respond · move · resign · watch · watch_live 공통. 관전 모양이면 참가자 칸
 * (`opponent`·`my_color`·`my_auto_streak`·`opponent_auto_streak`·`ruby_balance`)이 null 이고 `legal_moves` 는 [] 다.
 */
@Serializable
data class ReversiStatePayload(
    @SerialName("match") val match: ReversiMatchRow? = null,
    /** `seq > p_since_seq` 인 수만 seq 순(쓰기 RPC 응답은 전체). */
    @SerialName("moves") val moves: List<ReversiPly>? = null,
    @SerialName("black_user") val blackUser: ReversiPlayerRow? = null,
    @SerialName("white_user") val whiteUser: ReversiPlayerRow? = null,
    /** 참가자 관점의 상대(관전이면 null). */
    @SerialName("opponent") val opponent: ReversiPlayerRow? = null,
    /** 관전·pending 이면 null. */
    @SerialName("my_color") val myColor: ReversiColor? = null,
    /** active 이고 **내 차례일 때만** 오름차순. 그 밖은 []. 클라는 이 목록만 하이라이트·입력으로 받는다. */
    @SerialName("legal_moves") val legalMoves: List<Long>? = null,
    @SerialName("black_auto_streak") val blackAutoStreak: Long? = null,
    @SerialName("white_auto_streak") val whiteAutoStreak: Long? = null,
    @SerialName("my_auto_streak") val myAutoStreak: Long? = null,
    @SerialName("opponent_auto_streak") val opponentAutoStreak: Long? = null,
    @SerialName("auto_abandon_streak") val autoAbandonStreak: Long? = null,
    @SerialName("turn_seconds") val turnSeconds: Long? = null,
    @SerialName("grace_ms") val graceMs: Long? = null,
    /** 참가자만. */
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    /** `match__watchers('reversi', id)`. 관전 RPC 는 watch_live 만 채운다(watch 는 0). */
    @SerialName("watchers") val watchers: Long? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
)

/**
 * Swift `ReversiActionResponse` — 쓰기·조회 공용 응답(challenge · cancel · respond · state · move · resign · watch · watch_live).
 * 상태는 **`state` 키**에 실려 온다(펼치지 않는다).
 */
@Serializable
data class ReversiActionResponse(
    @SerialName("status") val status: ReversiRPCStatus,
    @SerialName("state") val state: ReversiStatePayload? = null,
    /** challenge ok / already_pending. */
    @SerialName("match_id") val matchId: String? = null,
    /** challenge ok. */
    @SerialName("invite_expires_ms") val inviteExpiresMs: Double? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    /** insufficient. */
    @SerialName("need") val need: Long? = null,
    /** insufficient — 남(신청자)의 잔액이면 null. */
    @SerialName("have") val have: Long? = null,
    /** insufficient(respond) — 'me' | 'challenger'. */
    @SerialName("side") val side: String? = null,
    /** illegal — 'out_of_range' | 'occupied' | 'no_flip'. 글자로 받고 [illegalReason] 으로 접는다(모르는 값은 null). */
    @SerialName("reason") val reason: String? = null,
    /** auto_placed — 이번 따라잡기가 둔 수. */
    @SerialName("auto_placed_count") val autoPlacedCount: Long? = null,
    /** respond ok — 수락이면 true, 거절이면 false. */
    @SerialName("accepted") val accepted: Boolean? = null,
    /** invalid(challenge) — 서버가 받는 판돈 집합. */
    @SerialName("stakes") val stakes: List<Long>? = null,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
) {
    val illegalReason: ReversiIllegalReason? get() = ReversiIllegalReason.of(reason)
}

// ---------- 응답 — 순위 ----------

/** Swift `ReversiRankRow` — 순위표 한 줄. 순위는 **서버가 매긴 값**이고 배열 순서도 서버 것이다(재정렬 금지). id 키는 `user_id`. */
@Serializable
data class ReversiRankRow(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("character") val character: String? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    /** 승점 = 승 − 패. */
    @SerialName("points") val points: Long? = null,
)

/** Swift `ReversiRankingMe` — 순위표의 `me`(0판이면 rank null). */
@Serializable
data class ReversiRankingMe(
    @SerialName("rank") val rank: Long? = null,
    @SerialName("wins") val wins: Long? = null,
    @SerialName("losses") val losses: Long? = null,
    @SerialName("draws") val draws: Long? = null,
    @SerialName("points") val points: Long? = null,
)

/** Swift `ReversiRankingResponse` — reversi_ranking 응답. `record_since_ms` 는 전적 컷이 없으면 null 이다. */
@Serializable
data class ReversiRankingResponse(
    @SerialName("status") val status: ReversiRPCStatus,
    @SerialName("server_now_ms") val serverNowMs: Double? = null,
    @SerialName("record_since_ms") val recordSinceMs: Double? = null,
    @SerialName("me") val me: ReversiRankingMe? = null,
    @SerialName("rows") val rows: List<ReversiRankRow>? = null,
)
