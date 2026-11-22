// 원본: Sources/CheckCore/MegaphoneFeed.swift:334-624(MegaphoneFeedNotice · MegaphoneFeedStore — 맥 · 폰 공용 스토어) @ main 341eb4e3
package com.yehsung.aingcheck.core.stores.messages

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.fetchMegaphoneFeed
import com.yehsung.aingcheck.core.net.megaphoneAdminHide
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedDecode
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedPage
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedText
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.messages.MegaphoneAdminHideResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** 페이지의 결과 한 줄(운영자 [내리기]의 결과). */
data class MegaphoneFeedNotice(val text: String, val isError: Boolean)

/**
 * 지난 확성기 스토어(판 9 — 맥 0.3.86 · 아이폰 1.0.19 와 같은 코어). 문은 세 갈래([isAvailable] — null 모름 · false 닫힘 · true 열림)이고,
 * 닫힘은 영구히 기억하지 않는다([rearm]). **자동 호출이 없다** — 페이지 열기 · 더 보기 · 다시 시도 · 페이지가 떠 있는 동안의 실시간 신호 ·
 * 운영자 내리기에서만 부른다. 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정 목록을 건드리지 않는다.
 */
class MegaphoneFeedStore(host: SessionHost?, private val scope: CoroutineScope) {
    var host: SessionHost? = host
        private set
    /** 한 쪽 크기(시험이 줄인다). */
    var pageSize: Int = MegaphoneFeedRules.pageSize

    /** 받은 줄(최신이 먼저 · 확성기 id 로 중복 없음). 차단으로 걷어낸 사람은 읽는 자리에서 뺀다. */
    var items: List<MegaphoneFeedItem> by mutableStateOf(emptyList())
        private set
    var isOpen: Boolean by mutableStateOf(false)
        private set
    var isAvailable: Boolean? by mutableStateOf(null)
        private set
    var isLoading: Boolean by mutableStateOf(false)
        private set
    var isLoadingMore: Boolean by mutableStateOf(false)
        private set
    var hasLoaded: Boolean by mutableStateOf(false)
        private set
    var loadFailed: Boolean by mutableStateOf(false)
        private set
    var loadMoreFailed: Boolean by mutableStateOf(false)
        private set
    var hasMore: Boolean by mutableStateOf(false)
        private set
    var hidingID: String? by mutableStateOf(null)
        private set
    var notice: MegaphoneFeedNotice? by mutableStateOf(null)
        private set

    /** 페이지가 열린 채 화면이 안 보이는 동안 실시간 신호가 왔다 — 다시 보일 때 한 번 읽는다. */
    var missedSignal: Boolean = false
        private set

    private var resetGeneration = 0
    private var refreshJob: Job? = null
    private var rerunRequested = false
    /** 다음에 도착하는 첫 쪽은 목록을 **갈아 끼운다**(페이지 열기가 켜고, 첫 쪽 반영이 끈다). */
    private var replacesLoadedTail = false

    fun attach(host: SessionHost) {
        this.host = host
    }

    // ---------------------------------------------------------------- 화면 사건

    /** 페이지를 연다 — 언제나 첫 쪽을 다시 읽고, 도착하면 그 쪽으로 갈아 끼운다(더 보기로 받았던 꼬리는 서버에 다시 물어 받는다). */
    fun open(): Job? {
        isOpen = true
        if (notice != null) notice = null
        missedSignal = false
        replacesLoadedTail = true
        return refresh()
    }

    /** 페이지를 닫는다. 받아 둔 줄은 남긴다. 결과 한 줄은 걷는다. */
    fun close() {
        if (isOpen) isOpen = false
        if (notice != null) notice = null
        missedSignal = false
    }

    /** 페이지가 열려 있지만 화면이 안 보일 때 실시간 신호가 왔다 — 요청 없이 표시만 남긴다. */
    fun noteMissedSignal() {
        if (isOpen) missedSignal = true
    }

    /** 화면이 다시 보이는 순간 — 놓친 신호가 있었을 때만 첫 쪽을 **한 번** 읽는다. */
    fun refreshIfMissedSignal(): Job? {
        if (!missedSignal || !isOpen) return null
        missedSignal = false
        return refresh()
    }

    /** 다음 자연스러운 진입(작성기 열기)에서 닫힘을 **모름으로** 되돌린다. 요청은 없다. */
    fun rearm() {
        if (isAvailable == false) isAvailable = null
    }

    /** 첫 쪽을 읽어 목록 머리를 갈아 끼운다. 겹친 호출은 하나로 모이되, 진행 중에 들어온 요청은 **한 번 더** 돈다. */
    fun refresh(): Job? {
        refreshJob?.let {
            rerunRequested = true
            return it
        }
        val host = host ?: return null
        if (host.session == null) return null
        val generation = resetGeneration
        val sessionGeneration = host.sessionGeneration
        isLoading = true
        if (loadFailed) loadFailed = false
        val job = scope.launch {
            do {
                rerunRequested = false
                performRefresh(host, generation, sessionGeneration)
                if (generation != resetGeneration) return@launch
            } while (rerunRequested)
            refreshJob = null
            isLoading = false
        }
        refreshJob = job
        return job
    }

    /** 꼬리 아래 [이전 확성기 더 보기]. 커서는 지금 목록의 마지막(가장 오래된) 줄의 µs. 겹쳐 누르면 하나만 나간다. */
    fun loadMore(): Job? {
        val host = host ?: return null
        val tail = items.lastOrNull() ?: return null
        if (isAvailable != true || !hasMore || isLoadingMore || host.session == null) return null
        val generation = resetGeneration
        val sessionGeneration = host.sessionGeneration
        val service = host.service
        val limit = pageSize
        val me = host.session?.userID
        val cursor = tail.createdEpochUs
        val tailID = tail.megaphoneID
        isLoadingMore = true
        if (loadMoreFailed) loadMoreFailed = false
        return scope.launch {
            try {
                val response = host.withSessionRetry { s -> service.fetchMegaphoneFeed(s.accessToken, cursor, limit) }
                val page = MegaphoneFeedDecode.page(response.rows, response.wireRowCount, limit, me)
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                isLoadingMore = false
                applyNextPage(page, tailID)
            } catch (error: Throwable) {
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                isLoadingMore = false
                if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return@launch
                if (isMissingFunction(error)) {
                    shutDoor()
                    return@launch
                }
                loadMoreFailed = true
            }
        }
    }

    /** 운영자 [내리기]. 판정은 서버가 한다. 성공(ok · 이미 없는 글)이면 그 줄을 목록에서 뺀다. 겹쳐 누르면 하나만 나간다. */
    fun adminHide(megaphoneID: String): Job? {
        val host = host ?: return null
        if (hidingID != null || items.none { it.id == megaphoneID } || host.session == null) return null
        val generation = resetGeneration
        val sessionGeneration = host.sessionGeneration
        val service = host.service
        hidingID = megaphoneID
        if (notice != null) notice = null
        return scope.launch {
            try {
                val response = host.withSessionRetry { s -> service.megaphoneAdminHide(s.accessToken, megaphoneID) }
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                hidingID = null
                notice = when (response.outcome) {
                    MegaphoneAdminHideResponse.Outcome.hidden -> {
                        items = items.filter { it.id != megaphoneID }
                        MegaphoneFeedNotice(MegaphoneFeedText.adminHidden, isError = false)
                    }
                    MegaphoneAdminHideResponse.Outcome.forbidden -> MegaphoneFeedNotice(MegaphoneFeedText.adminForbidden, isError = true)
                    MegaphoneAdminHideResponse.Outcome.failed -> MegaphoneFeedNotice(MegaphoneFeedText.adminHideFailed, isError = true)
                }
            } catch (error: Throwable) {
                if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return@launch
                hidingID = null
                if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return@launch
                notice = MegaphoneFeedNotice(MegaphoneFeedText.adminHideFailed, isError = true)
            }
        }
    }

    /** 로그아웃 · 계정 전환. 계정에 묶인 값을 전부 비우고, 나가 있던 응답은 세대로 버린다. */
    fun reset() {
        resetGeneration += 1
        refreshJob = null
        rerunRequested = false
        items = emptyList()
        isOpen = false
        isAvailable = null
        isLoading = false
        isLoadingMore = false
        hasLoaded = false
        loadFailed = false
        loadMoreFailed = false
        hasMore = false
        hidingID = null
        notice = null
        missedSignal = false
        replacesLoadedTail = false
    }

    // ---------------------------------------------------------------- 내부

    private suspend fun performRefresh(host: SessionHost, generation: Int, sessionGeneration: Int) {
        if (host.session == null || host.sessionGeneration != sessionGeneration || generation != resetGeneration) return
        val service = host.service
        val limit = pageSize
        val me = host.session?.userID
        try {
            val response = host.withSessionRetry { s -> service.fetchMegaphoneFeed(s.accessToken, null, limit) }
            val page = MegaphoneFeedDecode.page(response.rows, response.wireRowCount, limit, me)
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return
            val keepsLoadedTail = !replacesLoadedTail
            replacesLoadedTail = false
            applyFirstPage(page, keepsLoadedTail)
        } catch (error: Throwable) {
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return
            if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return
            if (isMissingFunction(error)) {
                shutDoor()
                return
            }
            loadFailed = true
        }
    }

    /**
     * 첫 쪽 반영(네트워크 없음). [keepsLoadedTail](떠 있는 동안의 새로고침)이면 새 머리의 가장 오래된 줄이 지금 목록에 있을 때 그 아래 꼬리를
     * 살린다(읽던 자리). 없으면 · 페이지를 새로 연 첫 쪽이면 새 머리로 갈아 끼운다.
     */
    fun applyFirstPage(page: MegaphoneFeedPage, keepsLoadedTail: Boolean = true) {
        if (isAvailable != true) isAvailable = true
        val fresh = page.items
        val pageHasMore = page.hasMore && fresh.isNotEmpty()
        loadFailed = false
        hasLoaded = true
        val oldest = fresh.lastOrNull()
        val index = if (keepsLoadedTail && oldest != null) items.indexOfFirst { it.id == oldest.id } else -1
        if (index >= 0) {
            val freshIDs = fresh.map { it.id }.toSet()
            val tail = items.drop(index + 1).filter { it.id !in freshIDs }
            items = fresh + tail
            if (tail.isEmpty()) hasMore = pageHasMore
        } else {
            items = fresh
            hasMore = pageHasMore
        }
    }

    /** 다음 쪽 반영. 그 사이 꼬리가 바뀌었으면 버린다. 새 줄이 하나도 없으면 더 없는 것으로 본다(같은 쪽을 끝없이 다시 묻지 않게). */
    private fun applyNextPage(page: MegaphoneFeedPage, tailID: String) {
        if (items.lastOrNull()?.megaphoneID != tailID) return
        val known = items.map { it.id }.toSet()
        val added = page.items.filter { it.id !in known }
        items = items + added
        hasMore = page.hasMore && added.isNotEmpty()
    }

    /** 문이 닫혔다(함수 없음). 받아 둔 줄은 내린다. */
    private fun shutDoor() {
        if (isAvailable != false) isAvailable = false
        items = emptyList()
        hasMore = false
        loadFailed = false
        loadMoreFailed = false
    }

    private fun isMissingFunction(error: Throwable): Boolean = BlockReportRules.isMissingFunction(serviceErrorFacts(error))
}
