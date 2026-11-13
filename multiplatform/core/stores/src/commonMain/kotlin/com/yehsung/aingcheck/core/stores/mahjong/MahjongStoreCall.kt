// 원본: Sources/CheckCore/MahjongStoreCall.swift @ e4995a3a(울기 답) — Android 판 8
//
// 울기 답은 seq · 사건 · 초인종을 만들지 않으므로 한 창 안에서 단조여야 한다(가드 (h) — answeredWindowIDs).
// window_closed 는 문구 없이 프롬프트를 내린다. 비행 잠금은 isAnsweringCall 하나 — isWorking 과 따로라 패스가 막히지 않는다.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimAnswer
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.stores.tetris.DuelCall

/** 울기(론 · 퐁 · 대명깡 · 치). tiles 는 손에서 낼 패(론은 []). 비었고 조합이 둘 이상이면 고르기 줄을 펼친다. */
suspend fun MahjongStore.call(kind: MahjongClaimKind, tiles: List<MahjongTile>) {
    if (showsPractice) {
        practiceCall(kind, tiles)
        return
    }
    val (current, call) = openServerCall ?: return
    val chosen = chooseCallTiles(kind, tiles, call) ?: return
    sendCall(kind.rawValue, chosen, call, current.id)
}

/** 울기 조합 고르기(서버 · 연습 같은 규칙) — 고를 것이 둘 이상이면 고르기 줄을 펼치고 null. */
internal fun MahjongStore.chooseCallTiles(kind: MahjongClaimKind, tiles: List<MahjongTile>, call: MahjongDecision.Call): List<MahjongTile>? {
    var chosen = tiles.sorted()
    when (kind) {
        MahjongClaimKind.ron -> {
            if (!call.ron) return null
            chosen = emptyList()
        }
        MahjongClaimKind.pon, MahjongClaimKind.minkan, MahjongClaimKind.chi -> {
            val options = MahjongStore.options(kind, call).map { it.sorted() }
            if (chosen.isEmpty()) {
                if (options.size > 1) {
                    if (riichiArmed) riichiArmed = false
                    if (!chiChoicesOpen) chiChoicesOpen = true
                    return null
                }
                chosen = options.firstOrNull() ?: return null
            }
            if (chosen !in options) return null
        }
    }
    return chosen
}

/** 넘기기. */
suspend fun MahjongStore.passCall() {
    if (showsPractice) {
        val call = practice?.payload?.myDecision as? MahjongDecision.Call ?: return
        if (call.answered != null) return
        if (chiChoicesOpen) chiChoicesOpen = false
        practiceAnswer(MahjongCallAnswer.Pass)
        return
    }
    val (current, call) = openServerCall ?: return
    sendCall(MahjongClaimAnswer.pass.rawValue, emptyList(), call, current.id)
}

/** 고르기 줄을 접는다(치 조합 · 깡 후보). */
fun MahjongStore.closeChoices() {
    if (chiChoicesOpen) chiChoicesOpen = false
    if (kanChoicesOpen) kanChoicesOpen = false
}

/** 지금 답할 수 있는 서버 울기 창(아직 안 답했고, 이 기기에서 답을 보내지 않은 창). */
internal val MahjongStore.openServerCall: Pair<MahjongStateMatch, MahjongDecision.Call>?
    get() {
        if (isAnsweringCall) return null
        val payload = match ?: return null
        val current = payload.match ?: return null
        if (current.matchStatus != MahjongMatchStatus.active) return null
        val call = payload.myDecision as? MahjongDecision.Call ?: return null
        if (call.answered != null || MahjongStore.windowKey(current.id, call.windowId) in answeredWindowIDs) return null
        return current to call
    }

/** call 한 번 — 장부 · 답 적기(요청 직전) · isAnsweringCall · 요청 마감 · 응답 처리. */
internal suspend fun MahjongStore.sendCall(answer: String, tiles: List<MahjongTile>, call: MahjongDecision.Call, matchID: String) {
    if (host?.session == null) return
    noteOwnsMatch(matchID)
    noteCallAnswered(matchID, call.windowId, answer)
    if (chiChoicesOpen) chiChoicesOpen = false
    callToken += 1
    val token = callToken
    isAnsweringCall = true
    val generation = resetGeneration
    try {
        val ticket = issueTicket()
        val windowID = call.windowId
        val result = performWithin(requestDeadlineSeconds(call.deadlineMs)) { s, t -> s.mahjongCallAnswer(t, matchID, windowID, answer, tiles) }
        // 답이 서버에 못 닿았다 — 보내기 전에 적은 '답함'을 걷는다(다음 조회의 answered 가 진실이다).
        if (result is DuelCall.Failure && generation == resetGeneration) forgetCallAnswered(matchID, windowID)
        handleDecisionResponse(result, MahjongNoticeText.Action.call, ticket, matchID)
    } finally {
        if (generation == resetGeneration && token == callToken && isAnsweringCall) isAnsweringCall = false
    }
}

internal fun MahjongStore.forgetCallAnswered(matchID: String, windowID: Int) {
    val key = MahjongStore.windowKey(matchID, windowID)
    answeredWindowIDs.remove(key)
    answeredWindowAnswers.remove(key)
}

internal fun MahjongStore.noteCallAnswered(matchID: String, windowID: Int, answer: String) {
    val key = MahjongStore.windowKey(matchID, windowID)
    answeredWindowIDs.add(key)
    answeredWindowAnswers[key] = answer
}
