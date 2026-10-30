// W2-h3 토큰 업로드 조정 — 내 행 · 월간 업로드 · 일별 · 배경 스캔 · 하트비트 · 진단 도장의 게이트.
// 원본: Sources/check/WorkTimerStoreSync.swift:587-1092(옛 표 :736-775 · :990-1015 는 옮기지 않는다 — W-3 #11)
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.rules.token.MyTokenRowOutcome
import com.yehsung.aingcheck.core.rules.token.TokenBoardEntryFacts
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplayRule
import com.yehsung.aingcheck.core.rules.token.TokenRowServerValue
import com.yehsung.aingcheck.core.net.fetchTokenBoard
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TokenUsageDayKey
import com.yehsung.aingcheck.core.wire.models.TokenUsageMonthKey
import com.yehsung.aingcheck.core.wire.models.toTokenBoardEntries
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountSource
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsage
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexDiagnosticsStamp
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** 스캐너(W2-h1 tokens/scan) 쪽에서 조정자가 읽는 것 — 조립 때 h1 스토어가 구현한다(갈래 사이는 값만). */
interface TokenScanSource {
    val currentMonthUsage: TokenUsageMonthly?
    val lastScanAt: SwiftDate?
    val lastScanFileCount: Int
    suspend fun refreshNow()
    suspend fun refreshIfStale()
}

/**
 * Windows 토큰 업로드 조정자.
 *
 * ★1 깃발 게이트가 **맨 앞**이다: [DesktopAppConfig.tokenUpload](기본 false)면 token_usage_device_{monthly,daily}·하트비트 요청 0
 *    (서버 ④ M5 + ⑥ 전 — tokens.md §6, W-3 #11). 스캔·로컬 표시·순위판 읽기(내 행)는 연다.
 * ★2 월간 게이트 순서 `session → deviceId → collect → (total>0 ‖ 계정월>0 ‖ 안티그래비티>0) → 변경 → 60초`, 시도 시각을 **먼저** 찍는다.
 * ★3 월간 성공 **뒤에만** 일별. 일별 실패는 독립(tokenDailyRetryPending — 다음 주기의 변경 게이트를 연다).
 * ★4 하트비트도 같은 깃발 · 같은 게이트 · 같은 기기 키.
 * ★5 진단은 `"<빌드>:<KST 날짜>"` 도장당 1회, 도장은 전송 성공 뒤.
 * ★6 옛 표 token_usage_monthly 는 읽지도 쓰지도 않는다((user, month) 한 줄이라 Windows 값이 화석·legacy_live 판정에 끼어든다).
 * 맥의 aiToolDataAllowed(맥 앱스토어 판 동의)는 Windows 에 없다 — 항상 참으로 본다.
 */
class TokenUploadCoordinator(
    private val config: DesktopAppConfig,
    private val host: SessionHost,
    /** 이 기기 키(`win:…`). 새로 짓지 않는다 — 없으면 업로드·하트비트 0. */
    private val deviceId: () -> String?,
    /** 서버 수집 설정(fetchTokenUsageSettings 를 읽어 둔 값 && 불러옴). */
    private val tokenUsageCollect: () -> Boolean,
    private val store: DesktopKeyValueStore,
    /** version.properties windowsBuild(생성 상수 BuildIdentity — 조립 지점이 넘긴다). 0 이하면 진단 0. */
    private val appBuild: Long,
    /** 진단 전량 순회(조립: CodexUsageDiagnosticsScanner.compute(homes.codexHome(), month, build) 를 IO 에서). */
    private val computeDiagnostics: suspend (month: String, appBuild: Long) -> CodexUsageDiagnostics?,
    /** 스키마 부재(배포로만 풀리는 실패) 운영자 신호. */
    private val onSchemaMissing: () -> Unit = {},
) {
    var lastUploadedUsage: TokenUsageMonthly? = null; private set
    var lastUploadedAccountKey: String? = null; private set
    var lastTokenUploadAt: SwiftDate? = null; private set
    var lastUploadedDaily: Map<String, TokenUsageDailyValue> = emptyMap(); private set
    var lastUploadedDailyBaselineDay: String? = null; private set
    var tokenDailyRetryPending: Boolean = false; private set
    var didUploadTokenUsage: Boolean = false; private set
    var lastTokenScanHeartbeatAt: SwiftDate? = null; private set
    var lastBackgroundTokenScanAt: SwiftDate? = null; private set
    var lastMyTokenRowFetchAt: SwiftDate? = null; private set
    var myTokenRow: TokenRowServerValue? = restoreMyRow(); private set

    // MARK: 내 행(순위판 읽기 — 깃발과 무관)

    /** Swift loadMyTokenRowIfDue — 순위판이 이번 달을 보고 있으면 그쪽이 같은 RPC 를 이미 부른다. 300초 간격. */
    suspend fun loadMyTokenRowIfDue(now: SwiftDate, force: Boolean = false, boardVisibleForCurrentMonth: Boolean = false) {
        val userID = host.session?.userID ?: return
        // INV-WorkTimerStoreSync-ddc05326 이식: 순위판이 이번 달을 열어 두면 한 번도 쏘지 않는다(그쪽이 같은 RPC 를 이미 돈다).
        // INV-WorkTimerStoreSync-97f46c3d 이식: 순위판의 보는 달을 쓰지 않는다 — 팝오버 행은 언제나 이번 달(TokenUsageMonthKey.current).
        if (boardVisibleForCurrentMonth) return
        val last = lastMyTokenRowFetchAt
        if (!force && last != null && now.timeIntervalSince(last) < 300) return
        val month = TokenUsageMonthKey.current(now)
        val generation = host.sessionGeneration
        lastMyTokenRowFetchAt = now
        try {
            val rows = host.withSessionRetry { s -> host.service.fetchTokenBoard(s.accessToken, month) }
            if (generation != host.sessionGeneration) return
            val facts = rows.toTokenBoardEntries().map {
                TokenBoardEntryFacts(it.userID, it.total, it.claudeTotal, it.codexEffective, it.antigravityEffective,
                    it.codexAccountMonth, it.hasServerCodexEffective)
            }
            applyMyTokenRowOutcome(TokenRowDisplayRule.outcomeForMyRow(facts, userID, month, now.timeIntervalSinceReferenceDate))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // 실패는 '판단하지 않는다'(keep) — 마지막 값을 그대로 둔다.
        }
    }

    fun applyMyTokenRowOutcome(outcome: MyTokenRowOutcome) {
        when (outcome) {
            is MyTokenRowOutcome.adopt -> {
                if (myTokenRow == outcome.value) return
                myTokenRow = outcome.value
                store.putString(MY_ROW_KEY, json.encodeToString(MyRow.serializer(), MyRow.of(outcome.value)))
            }
            MyTokenRowOutcome.clear -> {
                myTokenRow = null
                store.remove(MY_ROW_KEY)
            }
            MyTokenRowOutcome.keep -> Unit
        }
    }

    // MARK: 월간

    /** Swift uploadTokenUsageIfNeeded(now:) — 계정 프로브(수집 동의일 때만) → 업로드 → 올렸으면 내 행 강제 갱신. */
    suspend fun uploadTokenUsageIfNeeded(scan: TokenScanSource, account: CodexAccountSource?, now: SwiftDate) {
        val usage = scan.currentMonthUsage
        if (host.session != null && tokenUsageCollect() && account != null) {
            val rolledOver = usage?.month != TokenUsageMonthKey.current(now)
            account.refreshIfDue(now, force = rolledOver)
        }
        uploadTokenUsageIfNeeded(usage, account?.snapshot, account?.lastStatus, now)
        if (didUploadTokenUsage) {
            didUploadTokenUsage = false
            loadMyTokenRowIfDue(now, force = true)
        }
    }

    suspend fun uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly?,
        account: CodexAccountUsage?,
        accountStatus: CodexAccountProbeStatus?,
        now: SwiftDate,
    ) {
        if (!config.tokenUpload) return                     // ★1
        if (host.session == null) return
        val device = deviceId() ?: return
        if (!tokenUsageCollect()) return
        if (usage == null) return
        val accountMonth = account?.monthTotal(usage.month) ?: 0L
        if (!(usage.total > 0 || accountMonth > 0 || usage.antigravityTotal > 0)) return
        val accountKey = accountUploadKey(account, usage.month, accountStatus)
        val dailyDue = tokenDailyRetryPending || lastUploadedDailyBaselineDay != TokenUsageDayKey.current(now)
        val changed = usage != lastUploadedUsage || accountKey != lastUploadedAccountKey || dailyDue
        val last = lastTokenUploadAt
        if (!changed || (last != null && now.timeIntervalSince(last) < 60)) return
        lastTokenUploadAt = now                              // ★2 시도 시각을 먼저
        val diagnostics = codexDiagnosticsIfUnreported(usage.month, now)
        val generation = host.sessionGeneration
        try {
            host.withSessionRetry { s ->
                host.service.upsertTokenUsage(s.accessToken, s.userID, usage, device, account, accountStatus, diagnostics)
            }
            if (diagnostics != null) store.putString(CodexDiagnosticsStamp.KEY, CodexDiagnosticsStamp.stamp(diagnostics.appBuild, now))  // ★5
            if (generation != host.sessionGeneration) return
            lastUploadedUsage = usage
            lastUploadedAccountKey = accountKey
            didUploadTokenUsage = true
            uploadTokenUsageDailyIfNeeded(usage, account, generation, now)                       // ★3
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (generation != host.sessionGeneration) return
            if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) onSchemaMissing()
        }
    }

    // MARK: 일별

    suspend fun uploadTokenUsageDailyIfNeeded(usage: TokenUsageMonthly, account: CodexAccountUsage?, generation: Int, now: SwiftDate) {
        if (!config.tokenUpload) return                     // ★1
        if (host.session == null || !tokenUsageCollect()) return
        val device = deviceId() ?: return
        val today = TokenUsageDayKey.current(now)
        if (lastUploadedDailyBaselineDay != today) {
            lastUploadedDaily = emptyMap()
            lastUploadedDailyBaselineDay = today
        }
        val current = TokenUsageDailyUpload.values(usage, account)
        val changed = TokenUsageDailyUpload.changedDays(current, lastUploadedDaily)
        if (changed.isEmpty()) {
            tokenDailyRetryPending = false
            return
        }
        try {
            host.withSessionRetry { s ->
                host.service.upsertTokenUsageDaily(s.accessToken, TokenUsageDailyUpload.rows(s.userID, device, changed, current))
            }
            if (generation != host.sessionGeneration) return
            lastUploadedDaily = current
            tokenDailyRetryPending = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (generation != host.sessionGeneration) return
            if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) onSchemaMissing() else tokenDailyRetryPending = true
        }
    }

    // MARK: 배경 스캔 · 하트비트

    /** Swift refreshTokenUsageInBackgroundIfDue — 근무 중일 때만, 월이 바뀌었으면 60초·아니면 600초. 스캔은 깃발과 무관(로컬 표시). */
    suspend fun refreshTokenUsageInBackgroundIfDue(scan: TokenScanSource, account: CodexAccountSource?,
                                                   isWorking: Boolean, now: SwiftDate) {
        if (host.session == null || !tokenUsageCollect() || !isWorking) return
        val rolledOver = scan.currentMonthUsage?.month != TokenUsageMonthKey.current(now)
        // INV-WorkTimerStoreSync-c13b53fa 이식: 롤오버여도 60초 하한은 반드시 둔다(스캔 뒤에도 롤오버 판정이 참으로 남는 경로가 있다).
        // INV-WorkTimerStoreSync-b6f6f6c2 이식: "총합 0 이면 currentMonthUsage 가 안 채워진다"는 틀린 근거 — 하한이 유일한 방어선이다.
        val interval = if (rolledOver) 60.0 else 600.0
        val last = lastBackgroundTokenScanAt
        if (last != null && now.timeIntervalSince(last) < interval) return
        lastBackgroundTokenScanAt = now
        if (rolledOver) scan.refreshNow() else scan.refreshIfStale()
        uploadTokenUsageIfNeeded(scan, account, now)
        sendTokenScanHeartbeatIfNeeded(scan.lastScanAt, scan.lastScanFileCount, now)
    }

    suspend fun sendTokenScanHeartbeatIfNeeded(scannedAt: SwiftDate?, files: Int, now: SwiftDate) {
        if (!config.tokenUpload) return                     // ★1 · ★4
        if (host.session == null || !tokenUsageCollect()) return
        val device = deviceId() ?: return
        if (scannedAt == null || scannedAt == lastTokenScanHeartbeatAt) return
        val month = TokenUsageMonthKey.current(now)
        val generation = host.sessionGeneration
        try {
            host.withSessionRetry { s -> host.service.sendTokenScanHeartbeat(s.accessToken, s.userID, month, device, files, scannedAt) }
            if (generation != host.sessionGeneration) return
            lastTokenScanHeartbeatAt = scannedAt
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // 다음 스캔이 다시 보낸다.
        }
    }

    // MARK: 진단

    suspend fun codexDiagnosticsIfUnreported(month: String, now: SwiftDate): CodexUsageDiagnostics? {
        if (appBuild <= 0) return null
        if (store.getString(CodexDiagnosticsStamp.KEY) == CodexDiagnosticsStamp.stamp(appBuild, now)) return null
        return computeDiagnostics(month, appBuild)
    }

    private fun restoreMyRow(): TokenRowServerValue? = store.getString(MY_ROW_KEY)?.let {
        try { json.decodeFromString(MyRow.serializer(), it).toValue() } catch (_: Exception) { null }
    }

    @Serializable
    private data class MyRow(val userID: String, val month: String, val total: Long, val claudeTotal: Long, val codexEffective: Long,
                             val antigravityEffective: Long, val codexAccountShare: Long? = null, val fetchedAt: Double) {
        fun toValue() = TokenRowServerValue(userID, month, total, claudeTotal, codexEffective, antigravityEffective, codexAccountShare, fetchedAt)
        companion object {
            fun of(v: TokenRowServerValue) = MyRow(v.userID, v.month, v.total, v.claudeTotal, v.codexEffective, v.antigravityEffective,
                v.codexAccountShare, v.fetchedAt)
        }
    }

    companion object {
        /** Swift WorkTimerStore.myTokenRowKey. */
        const val MY_ROW_KEY: String = "check.tokenBoard.myRow"
        private val json = Json { explicitNulls = false; ignoreUnknownKeys = true }

        /** Swift accountUploadKey — 계정도 상태도 없으면 null, 아니면 "월합|평생|상태"(모르면 "-"). */
        fun accountUploadKey(account: CodexAccountUsage?, month: String, status: CodexAccountProbeStatus?): String? {
            if (account == null && status == null) return null
            val monthTotal = account?.monthTotal(month)?.toString() ?: "-"
            val lifetime = account?.lifetimeTokens?.toString() ?: "-"
            val statusRaw = status?.raw?.toString() ?: "-"
            return "$monthTotal|$lifetime|$statusRaw"
        }
    }
}
