// 원본: Sources/CheckCore/MessageHistoryPaging.swift:347-457(MessageOlderHistoryRules) @ main 341eb4e3
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry

/**
 * 지난 쪽과 24시간 머리를 잇는 규칙(판 9 — 맥 0.3.86 · 아이폰 1.0.19 와 같은 규칙). **다시 정렬하지 않고 잇는다** — 지난 쪽 id 는 머리의
 * 서버 순서표에 없어서 함께 세우면 같은 초의 머리 줄 뒤로 밀린다.
 */
object MessageOlderHistoryRules {
    /** 머리 시각은 초 단위로 반올림된 값이다. 그보다 "새 줄"을 가를 때 이만큼 너그럽게 본다. */
    const val headClockSlack: Double = 1.0
    /** 머리 미끄러짐에서 24시간 경계를 이만큼 너그럽게 본다(서버 now() 와 기기 시계의 차이). */
    const val headWindowSlack: Double = 600.0

    /** 화면이 그릴 한 줄: 지난 쪽(머리에 있는 id 는 뺀다 — **머리가 이긴다**) + 머리. 다시 정렬하지 않는다. */
    fun merged(older: List<MessageHistoryEntry>, head: List<MessageHistoryEntry>): List<MessageHistoryEntry> {
        if (older.isEmpty()) return head
        val headIDs = head.map { it.id }.toSet()
        val seen = HashSet<String>()
        val kept = older.filter { it.id !in headIDs && seen.add(it.id) }
        return readFollowingHead(kept, head) + head
    }

    /**
     * 지난 쪽의 내 말 읽음(1)을 머리에 맞춘다 — 머리에 **상대가 읽은 내 말이 하나라도 있으면** 지난 쪽의 내 말은 전부 읽은 것이다
     * (지난 쪽 줄은 서버 순서에서 머리의 모든 줄보다 앞이고 읽음 경계는 앞으로만 간다). 시각을 비교하지 않는다. false → true 만 바꾼다.
     */
    fun readFollowingHead(older: List<MessageHistoryEntry>, head: List<MessageHistoryEntry>): List<MessageHistoryEntry> {
        if (!head.any { it.isMine && it.readByPeer == true } || !older.any { it.isMine && it.readByPeer == false }) return older
        return older.map { if (it.isMine && it.readByPeer == false) it.copy(readByPeer = true) else it }
    }

    /**
     * 받은 쪽(오래된 것 → 최신)을 기존 지난 쪽 **앞에** 붙인다. 빼는 줄: 머리에 있는 id · 이미 받은 id · 머리의 가장 새 줄보다 **새** 줄
     * (머리를 받은 뒤 도착한 말 — 다음 머리 조회가 받는다). 결과는 전부 지난 쪽 모양([pageEntry])이다.
     */
    fun prepending(page: List<MessageHistoryEntry>, older: List<MessageHistoryEntry>, head: List<MessageHistoryEntry>): List<MessageHistoryEntry> {
        val known = HashSet<String>().apply { addAll(older.map { it.id }); addAll(head.map { it.id }) }
        val newestHead = head.maxOfOrNull { it.createdAt }
        val additions = ArrayList<MessageHistoryEntry>()
        for (entry in page) {
            if (newestHead != null && entry.createdAt > newestHead.addingTimeInterval(headClockSlack)) continue
            if (!known.add(entry.id)) continue
            additions += pageEntry(entry)
        }
        return additions + older.map(::pageEntry)
    }

    /**
     * 24시간 머리가 미끄러졌다(대화를 오래 열어 둔 채 이력을 다시 받았다). 앞 머리에 있었는데 새 머리에서 빠진 **그 상대의** 줄을 지난 쪽 끝으로
     * 옮긴다 — 안 옮기면 지난 쪽과 새 머리 맨 앞 사이의 말이 어디에도 없어 대화 가운데가 빈다. 창 경계(24시간 + 시계 차이 · 상한까지 찬 머리)
     * 보다 새 줄이 빠졌으면 서버가 다른 이유로 뺀 것이다(차단 · 숨긴 계정 · 운영자 삭제) — 옮기지 않는다. [previousHead] 는 화면이 보던 판이다.
     */
    fun carriedAcrossHeadSlide(
        peer: String,
        previousHead: List<MessageHistoryEntry>,
        nextHead: List<MessageHistoryEntry>,
        older: List<MessageHistoryEntry>,
        now: SwiftDate,
        windowHours: Int = MessageNoticeText.historyHours,
        headLimit: Int = MessageNoticeText.historyLimit,
    ): List<MessageHistoryEntry> {
        val nextIDs = nextHead.map { it.id }.toSet()
        val edge = nextHead.firstOrNull { it.peerUserID == peer }?.createdAt
        var windowEdge = now.addingTimeInterval(-windowHours.toDouble() * 3_600 + headWindowSlack)
        if (nextHead.size >= headLimit) {
            nextHead.minOfOrNull { it.createdAt }?.let { oldest ->
                val bound = oldest.addingTimeInterval(headClockSlack)
                if (bound > windowEdge) windowEdge = bound
            }
        }
        val known = older.map { it.id }.toHashSet()
        val slid = ArrayList<MessageHistoryEntry>()
        for (entry in previousHead) {
            if (entry.peerUserID != peer || entry.id in nextIDs) continue
            if (edge != null && entry.createdAt > edge) continue
            if (entry.createdAt > windowEdge) continue
            if (!known.add(entry.id)) continue
            slid += pageEntry(entry)
        }
        return if (slid.isEmpty()) older else older + slid
    }

    /** 지난 쪽에 둘 모양: 받은 쪽 안 읽음 칸을 **비운** 사본. 사진 칸은 그대로 싣는다. */
    fun pageEntry(entry: MessageHistoryEntry): MessageHistoryEntry = entry.copy(isUnread = null)
}
