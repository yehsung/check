// 원본: Sources/CheckCore/AILimitStore.swift:1-947 @ a90d8623 (리밋 스토어 — 10분 간격 · 영속 · 표시 설정 · 비우기 세대 · 업로드 백오프 · 기기 축)
// Windows 차이: 안티그래비티는 지원 집합에서 뺀다(W-3 #11 — `agy`·`.gemini` 접근 0) → 로그인 필요 연속 횟수(0.3.57) 절은 옮기지 않는다
// (INV-AILimitStore-7e632f8d · -49b8483a 해당 없음 제안). 영속은 UserDefaults 대신 [DesktopKeyValueStore](같은 키 이름).
// 스레드: 맥 @MainActor 와 같게 **한 디스패처**(UI)에서 부른다. 업로드 직렬화는 desktopMain `DesktopAILimitSync` 가 Mutex 로 쥔다.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitMainDeviceRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

// INV-AILimitStore-feffc8be 이식: 표시 설정은 **로컬 설정**이다(서버 컬럼이 아니다 — profiles 에 칸을 더하지 않는다).
// INV-AILimitStore-fbda3c1d 이식: 끈 제공자를 거르는 자리는 **러너 앞**이다(리더 안쪽에서 걸러도 이미 파일을 읽은 뒤다).

/** 어떤 제공자의 리밋을 읽고 보여 줄지. 마스터 + **꺼진** 제공자 rawValue(모르는 값도 보존 — 열거 확장 함정). 기본은 전부 켬. */
data class AILimitVisibility(val masterEnabled: Boolean = true, val disabledRaws: Set<String> = emptySet()) {
    fun isEnabled(provider: AILimitProvider): Boolean = masterEnabled && isProviderOn(provider)
    /** 제공자 스위치 하나만(마스터가 꺼진 동안에도 설정 화면이 그리는 값). */
    fun isProviderOn(provider: AILimitProvider): Boolean = provider.rawValue !in disabledRaws
    /** 이번 바퀴에 리더를 부를 제공자(지원 집합 교차는 스토어가 한다). */
    val enabledProviders: Set<AILimitProvider>
        get() = if (!masterEnabled) emptySet() else AILimitProvider.entries.filter { isProviderOn(it) }.toSet()

    fun withProvider(provider: AILimitProvider, on: Boolean): AILimitVisibility =
        copy(disabledRaws = if (on) disabledRaws - provider.rawValue else disabledRaws + provider.rawValue)

    companion object {
        val allEnabled = AILimitVisibility()
    }
}

/** 비우기 대기열을 **한 번 집은 것** — 돌아왔을 때 "내가 보낸 것"만 비운다(세대가 같을 때만). */
data class AILimitClearClaim(val providers: List<AILimitProvider>, val generations: Map<AILimitProvider, Int>) {
    val isEmpty: Boolean get() = providers.isEmpty()
}

/** 리더를 한 번 돌린 결과. 제공자마다 성공이거나 분류된 실패. */
data class AILimitReadOutcome(val results: Map<AILimitProvider, AILimitOutcome<AILimitProviderSnapshot>> = emptyMap()) {
    val snapshots: List<AILimitProviderSnapshot>
        get() = results.values.mapNotNull { (it as? AILimitOutcome.Ok)?.value }.sortedBy { it.provider.sortOrder }
    val failures: Map<AILimitProvider, AILimitReadFailure>
        get() = results.mapNotNull { (k, v) -> (v as? AILimitOutcome.Err)?.let { k to it.error.failure } }.toMap()
    /** 이번 바퀴에서 받은 가장 긴 retry-after(초). */
    val retryAfter: Double?
        get() = results.values.mapNotNull { (it as? AILimitOutcome.Err)?.error?.retryAfter }.maxOrNull()
}

/**
 * INV-AILimitStore-2e00745e 이식: `providers` 가 **계약의 절반** — 러너는 이 집합 안의 리더만 부른다(결과를 받아 버리는 구현은 틀렸다).
 * INV-AILimitStore-a10fd6d8 이식: 꺼진 제공자의 리더를 **부르지 않는다**(파일·API 손 0).
 */
fun interface AILimitRunner {
    suspend fun run(now: SwiftDate, providers: Set<AILimitProvider>): AILimitReadOutcome
}

/** 화면이 그리는 값 한 벌(StateFlow). */
data class AILimitStoreState(
    val bundle: AILimitSnapshotBundle?,
    val failures: Map<AILimitProvider, AILimitReadFailure>,
    val visibility: AILimitVisibility,
    val devices: List<AILimitDevice>,
    val mainDeviceID: String?,
)

class AILimitStore(
    private val defaults: DesktopKeyValueStore,
    private val clock: () -> SwiftDate,
    /**
     * 이 PC 의 이름을 **그때그때** 읽는 통로(조립이 `COMPUTERNAME` 을 넣는다 — 이 패키지는 환경을 직접 읽지 않는다, 홈 격리 규약).
     * INV-AILimitStore-a14be9e0 이식: **프로세스를 띄우지 않는다**(맥 scutil 금지와 같은 규약 — Windows 는 환경 값 하나).
     * INV-AILimitStore-df4d5c90 이식: 이름은 **식별자가 아니다** — 겹치면 읽는 쪽(`AILimitDeviceRoster.displayNames`)이 가른다.
     */
    private val deviceLabelProvider: () -> String?,
    private val runner: AILimitRunner,
    /** 이 판이 읽을 수 있는 제공자. Windows = Claude·Codex(안티그래비티 0 — W-3 #11). */
    val supportedProviders: Set<AILimitProvider> = windowsProviders,
) {
    companion object {
        val windowsProviders: Set<AILimitProvider> = setOf(AILimitProvider.claude, AILimitProvider.codex)

        const val snapshotKey = "check.aiLimits.snapshot"
        const val failuresKey = "check.aiLimits.failures"
        /** INV-AILimitStore-b7c16385 이식: 마지막 **시도** 시각 — 간격은 프로세스 수명보다 오래 산다(재시작이 5분 5회를 뚫지 않게). */
        const val lastAttemptKey = "check.aiLimits.lastAttemptAt"
        const val silentUntilKey = "check.aiLimits.silentUntil"
        const val refreshInterval: Double = 600.0
        const val forcedRefreshFloor: Double = 300.0
        const val defaultBackoff: Double = 300.0
        /** INV-AILimitStore-78096446 이식: 이름을 바꾸면 이미 끈 사람의 설정이 아무 말 없이 켜짐으로 돌아간다. */
        const val visibilityKey = "check.aiLimits.show"
        const val disabledProvidersKey = "check.aiLimits.disabledProviders"
        /** INV-AILimitStore-4353f922 이식: 비우기 대기열은 **영속**한다(끄고 바로 죽어도 그 행이 서버에 남지 않게). */
        const val pendingClearKey = "check.aiLimits.pendingClear"
        const val uploadRetryBaseBackoff: Double = 60.0
        const val uploadRetryMaxBackoff: Double = 3_600.0
        const val devicesReloadInterval: Double = 300.0

        private val json = Json { isLenient = false }

        internal fun encodeBundle(bundle: AILimitSnapshotBundle): String = buildJsonObject {
            put("schemaVersion", bundle.schemaVersion)
            put("providers", buildJsonArray {
                for (p in bundle.providers) add(buildJsonObject {
                    put("provider", p.provider.rawValue)
                    put("planLabel", p.planLabel)
                    put("accountFingerprint", p.accountFingerprint)
                    put("windows", buildJsonArray {
                        for (w in p.windows) add(buildJsonObject {
                            put("window", w.window.rawValue)
                            put("usedPercent", w.usedPercent)
                            put("resetsAt", w.resetsAt)
                            put("observedAt", w.observedAt)
                            put("source", w.source.rawValue)
                        })
                    })
                })
            })
        }.toString()

        /** 모르는 제공자·창·출처 행은 버린다(접어서 남의 값을 내 카드에 붙이지 않는다). 판이 더 새것이면 통째로 null. */
        internal fun decodeBundle(text: String): AILimitSnapshotBundle? = runCatching {
            val root = json.parseToJsonElement(text) as JsonObject
            val schema = root["schemaVersion"]!!.jsonPrimitive.content.toInt()
            if (schema > AILimitSnapshotBundle.currentSchemaVersion) return null
            val providers = root["providers"]!!.jsonArray.mapNotNull { e ->
                val o = e as JsonObject
                val provider = AILimitProvider.of(o["provider"]!!.jsonPrimitive.content) ?: return@mapNotNull null
                val windows = o["windows"]!!.jsonArray.mapNotNull { we ->
                    val w = we as JsonObject
                    val window = AILimitWindow.of(w["window"]!!.jsonPrimitive.content) ?: return@mapNotNull null
                    val source = AILimitSource.entries.firstOrNull { it.rawValue == w["source"]!!.jsonPrimitive.content } ?: return@mapNotNull null
                    AILimitWindowSnapshot(window, w["usedPercent"]!!.jsonPrimitive.content.toDouble(),
                        (w["resetsAt"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content?.toDouble(),
                        w["observedAt"]!!.jsonPrimitive.content.toDouble(), source)
                }
                AILimitProviderSnapshot(provider, windows, AILimitJson.string(o["planLabel"]), AILimitJson.string(o["accountFingerprint"]))
            }
            AILimitSnapshotBundle(schema, providers)
        }.getOrNull()
    }

    // ------------------------------------------------------------------ 상태
    var bundle: AILimitSnapshotBundle? = null
        private set
    var failures: Map<AILimitProvider, AILimitReadFailure> = emptyMap()
        private set
    var lastAttemptAt: SwiftDate? = null
        private set
    var silentUntil: SwiftDate? = null
        private set
    var visibility: AILimitVisibility = AILimitVisibility.allEnabled
        private set
    /** 끈 제공자 → 그 끄기의 세대(업로드 성공에만 빠진다). 같은 제공자가 다시 꺼지면 더 큰 세대 = 아직 아무도 안 보낸 새 사건. */
    private var pendingClearGenerations: Map<AILimitProvider, Int> = emptyMap()
    private var clearSequence = 0
    /** 러너가 불린 횟수(시험 계측). */
    var runnerCallCount = 0
        private set
    private var inFlight = false
    val pendingClear: Set<AILimitProvider> get() = pendingClearGenerations.keys

    /** 업로드 비행 중(직렬화는 DesktopAILimitSync). INV-AILimitStore-7c7d0b10 이식: 동시 왕복이 1 이 아니면 도착 순서를 아무도 보장하지 않는다. */
    var uploadInFlight = false
    var uploadPendingTrailing = false
    var uploadPeakConcurrency = 0
        private set
    var uploadRoundTripCount = 0
        private set
    private var uploadsInFlightNow = 0
    // INV-AILimitStore-bb9f581f 이식: 백오프는 값 업로드에도 걸린다(스키마 없는 서버에서 valuesChanged 는 영원히 참이다). 영속하지 않는다.
    private var uploadFailureCount = 0
    private var uploadRetryNotBefore: SwiftDate? = null

    // INV-AILimitStore-6965cb6e 이식: 기기 목록은 **영속하지 않는다**(주인은 서버 — 팔아 버린 PC 가 고르개에 남지 않게).
    var devices: List<AILimitDevice> = emptyList()
        private set
    var mainDeviceID: String? = null
        private set
    var devicesLoadedAt: SwiftDate? = null
        private set
    private var devicesLoading = false

    private val _state = MutableStateFlow(AILimitStoreState(null, emptyMap(), AILimitVisibility.allEnabled, emptyList(), null))
    val state: StateFlow<AILimitStoreState> = _state.asStateFlow()

    init {
        defaults.getString(snapshotKey)?.let(::decodeBundle)?.let { restored ->
            bundle = AILimitSnapshotBundle(restored.schemaVersion, restored.providers.filter { it.provider in supportedProviders })
        }
        defaults.getString(failuresKey)?.let { text ->
            runCatching {
                (json.parseToJsonElement(text) as JsonObject).mapNotNull { (k, v) ->
                    val provider = AILimitProvider.of(k)?.takeIf { it in supportedProviders } ?: return@mapNotNull null
                    val failure = AILimitJson.string(v)?.let(AILimitReadFailure::of) ?: return@mapNotNull null
                    provider to failure
                }.toMap()
            }.getOrNull()?.let { failures = it }
        }
        // 간격·금지창 복원: 미래 스탬프는 지금으로 접고(영구고착 방지), 금지창은 기본 백오프보다 길게 믿지 않는다.
        val now = clock()
        restoredDate(lastAttemptKey)?.let { lastAttemptAt = minOf(it, now) }
        restoredDate(silentUntilKey)?.let { silentUntil = minOf(it, now.addingTimeInterval(defaultBackoff)) }
        visibility = AILimitVisibility(
            masterEnabled = defaults.getBoolean(visibilityKey) ?: true,
            disabledRaws = readStringList(disabledProvidersKey).toSet(),
        )
        // 비우기 대기열은 아는 제공자만(서버 CHECK 로 올릴 수 없는 항목은 영구 고착). 세대는 복원 순서대로 다시 매긴다.
        for (provider in readStringList(pendingClearKey).mapNotNull(AILimitProvider::of)) enqueueClear(provider)
        publish()
    }

    private fun restoredDate(key: String): SwiftDate? {
        val raw = defaults.getString(key)?.toDoubleOrNull() ?: return null
        return if (raw.isFinite()) SwiftDate(raw) else null
    }

    private fun readStringList(key: String): List<String> = defaults.getString(key)?.let { text ->
        runCatching { (json.parseToJsonElement(text) as JsonArray).mapNotNull { AILimitJson.string(it) } }.getOrNull()
    } ?: emptyList()

    private fun writeStringList(key: String, values: List<String>) {
        defaults.putString(key, JsonArray(values.map(::JsonPrimitive)).toString())
    }

    private fun publish() {
        _state.value = AILimitStoreState(bundle, failures, visibility, devices, mainDeviceID)
    }

    // ------------------------------------------------------------------ 기기 축
    val clockNow: SwiftDate get() = clock()
    /** 올려도 되는 이 PC 의 이름(규칙은 AILimitDeviceLabelContract 한 곳). */
    val deviceLabel: String? get() = AILimitDeviceLabelContract.normalized(deviceLabelProvider())

    fun devicesAreDue(now: SwiftDate): Boolean {
        if (devicesLoading) return false
        val loaded = devicesLoadedAt ?: return true
        return now.timeIntervalSince(loaded) >= devicesReloadInterval
    }

    fun noteDevicesLoading(loading: Boolean) { devicesLoading = loading }

    /** 목록과 고른 PC 를 **한 번에** 넣는다(사이에 그려진 고르개가 "새 목록 + 옛 선택"을 보지 않게). */
    fun applyDevices(devices: List<AILimitDevice>, mainDeviceID: String?, now: SwiftDate) {
        this.devices = devices
        this.mainDeviceID = mainDeviceID
        devicesLoadedAt = now
        publish()
    }

    /** 먼저 화면에 반영하고 직전 선택을 돌려준다(왕복 실패면 호출부가 되돌린다). */
    fun setMainDeviceLocally(deviceID: String?): String? {
        val previous = mainDeviceID
        mainDeviceID = deviceID
        publish()
        return previous
    }

    val effectiveMainDevice: AILimitDevice? get() = AILimitMainDeviceRule.resolve(devices, mainDeviceID)
    val showsMainDevicePicker: Boolean get() = devices.size >= 2

    // ------------------------------------------------------------------ 표시 재료
    private fun enabledProviders(v: AILimitVisibility): Set<AILimitProvider> = v.enabledProviders intersect supportedProviders

    val visibleProviders: List<AILimitProviderSnapshot>
        get() = if (!visibility.masterEnabled) emptyList()
        else (bundle?.visibleProviders ?: emptyList()).filter { visibility.isProviderOn(it.provider) && it.provider in supportedProviders }

    val isAvailable: Boolean
        get() {
            if (!visibility.masterEnabled) return false
            if (visibleProviders.isNotEmpty()) return true
            return failures.any { (p, f) -> visibility.isProviderOn(p) && p in supportedProviders && !f.hidesProvider }
        }

    /**
     * 설정 화면이 줄을 세울 제공자(읽은 것 + 숨기지 않는 실패). **표시 설정을 보지 않는다.** Windows 는 지원 집합 안에서만(안티그래비티 줄 0).
     * INV-AILimitStore-f4fbb581 이식: 설정을 보면 꺼서 안 보이는 제공자를 되켤 줄이 사라진다(들어가면 못 나오는 방).
     * INV-AILimitStore-93bd2b89 이식: 근거는 **영속된 묶음과 실패 표**(끈 동안에도 디스크에 남는다).
     */
    val configurableProviders: List<AILimitProvider>
        get() {
            val out = LinkedHashSet<AILimitProvider>()
            for (s in bundle?.visibleProviders ?: emptyList()) out += s.provider
            for ((p, f) in failures) if (!f.hidesProvider) out += p
            return out.filter { it in supportedProviders }.sortedBy { it.sortOrder }
        }

    val listedProviders: List<AILimitProvider>
        get() = if (!visibility.masterEnabled) emptyList() else configurableProviders.filter { visibility.isProviderOn(it) }

    /** 서버에 **값으로** 올라갈 묶음(켠 제공자만). */
    val enabledBundle: AILimitSnapshotBundle get() = AILimitSnapshotBundle(providers = visibleProviders)

    fun summary(now: SwiftDate): AILimitDisplay =
        AILimitFreshnessRule.combine(visibleProviders.flatMap { AILimitFreshnessRule.displays(it, now.timeIntervalSince1970) })

    fun display(provider: AILimitProvider, window: AILimitWindow, now: SwiftDate): AILimitDisplay =
        AILimitFreshnessRule.display(bundle?.provider(provider), window, now.timeIntervalSince1970)

    fun noticeText(provider: AILimitProvider): String? = failures[provider]?.noticeText(provider)

    // ------------------------------------------------------------------ 갱신
    /**
     * 간격이 찼는가. 진행 중 · 백오프 중이면 거짓.
     * INV-AILimitStore-f6f97299 이식: **꺼진 축은 타이머가 돌지 않는다**(거짓이면 스탬프도 디스크도 안 건드린다).
     * INV-AILimitStore-4b12ceb8 이식: 게이트는 **사용자가 끌 수 있는 집합**(configurableProviders)으로 잰다.
     * INV-AILimitStore-5f747947 이식: 줄이 하나도 없는 동안은 거꾸로 **돈다**(나중에 로그인한 사람에게 축이 켜지게).
     * INV-AILimitStore-e4ddb4a6 이식: 다른 제공자 때문에 도는 바퀴에는 줄 없는 제공자도 같이 묻는다(연동 발견의 유일한 길).
     */
    fun isDue(now: SwiftDate, force: Boolean = false): Boolean {
        val enabled = enabledProviders(visibility)
        if (enabled.isEmpty()) return false
        val stoppable = configurableProviders.toSet()
        if (stoppable.isNotEmpty() && (enabled intersect stoppable).isEmpty()) return false
        if (inFlight) return false
        silentUntil?.let { if (now < it) return false }
        val last = lastAttemptAt ?: return true
        val elapsed = now.timeIntervalSince(last)
        return if (force) elapsed >= forcedRefreshFloor else elapsed >= refreshInterval
    }

    /** 간격이 찼을 때만 리더를 돈다. `force` = 사용자가 방금 플라이아웃을 열었다(5분 하한 유지). */
    suspend fun refreshIfDue(now: SwiftDate, force: Boolean = false) {
        if (!isDue(now, force)) return
        // 요청 집합을 **여기서** 굳힌다(바퀴 도중 스위치를 만져도 이번 바퀴는 변하지 않는다).
        val providers = enabledProviders(visibility)
        // INV-AILimitStore-ede5ecb2 이식: 빼고 나서 아무도 안 남으면 러너도 스탬프도 없다(이건 시도가 아니다).
        if (providers.isEmpty()) return
        // 스탬프를 러너 **전에** 찍고 디스크에도 지금 내린다(바퀴 도중 죽어도 이 시도가 장부에 남는다).
        lastAttemptAt = now
        persistSchedule()
        inFlight = true
        try {
            runnerCallCount += 1
            val outcome = runner.run(now, providers)
            apply(outcome, now)
        } finally {
            inFlight = false
        }
    }

    // ------------------------------------------------------------------ 표시 설정
    fun setMasterEnabled(enabled: Boolean) {
        if (visibility.masterEnabled == enabled) return
        applyVisibility(visibility.copy(masterEnabled = enabled))
    }

    fun setProviderEnabled(provider: AILimitProvider, enabled: Boolean) {
        if (visibility.isProviderOn(provider) == enabled) return
        applyVisibility(visibility.withProvider(provider, enabled))
    }

    /** 대기열에 넣는 것은 "바뀌기 전에 올라가던 − 바뀐 뒤에 올라갈" 뿐. 다시 켠 제공자는 뺀다(같은 PK 값·비우기가 한 본문에 섞이면 21000). */
    private fun applyVisibility(next: AILimitVisibility) {
        val before = uploadableProviders(visibility)
        visibility = next
        val after = uploadableProviders(next)
        for (provider in (before - after).sortedBy { it.sortOrder }) enqueueClear(provider)
        pendingClearGenerations = pendingClearGenerations - after
        persistVisibility()
        publish()
    }

    private fun enqueueClear(provider: AILimitProvider) {
        clearSequence += 1
        pendingClearGenerations = pendingClearGenerations + (provider to clearSequence)
    }

    /** 지금 서버에 값이 올라가는 제공자(= 끄면 비울 대상). 연동 사실은 **묶음**에서 본다. */
    private fun uploadableProviders(v: AILimitVisibility): Set<AILimitProvider> {
        if (!v.masterEnabled) return emptySet()
        return (bundle?.visibleProviders ?: emptyList()).map { it.provider }.filter { v.isProviderOn(it) }.toSet()
    }

    fun claimPendingClear(): AILimitClearClaim =
        AILimitClearClaim(pendingClearGenerations.keys.sortedBy { it.sortOrder }, pendingClearGenerations)

    /** INV-AILimitStore-5dbdb009 이식: 인자는 '지금 대기열'이 아니라 **집음** — 보낸 뒤 다시 끈 제공자(세대가 큼)는 살아남는다. */
    fun markCleared(claim: AILimitClearClaim) {
        val next = pendingClearGenerations.filterNot { (p, gen) -> claim.generations[p] == gen }
        if (next == pendingClearGenerations) return
        pendingClearGenerations = next
        persistVisibility()
    }

    fun noteUploadStarted() {
        uploadsInFlightNow += 1
        uploadRoundTripCount += 1
        uploadPeakConcurrency = maxOf(uploadPeakConcurrency, uploadsInFlightNow)
    }

    fun noteUploadFinished() { uploadsInFlightNow = maxOf(0, uploadsInFlightNow - 1) }

    /** 값이든 비우기든 같은 문(같은 실패를 30초마다 영원히 막는다 — 성공 한 번이면 즉시 열린다). */
    fun uploadRetryAllowed(now: SwiftDate): Boolean {
        val notBefore = uploadRetryNotBefore ?: return true
        return now >= notBefore
    }

    /** 실패 → 60초에서 두 배씩, 상한 1시간. **대기열은 그대로.** */
    fun noteUploadFailed(now: SwiftDate) {
        uploadFailureCount += 1
        var doubled = uploadRetryBaseBackoff
        repeat(uploadFailureCount - 1) { doubled *= 2 }   // Swift `60 * pow(2, n-1)` — 2 의 거듭제곱은 곱셈과 비트까지 같다
        uploadRetryNotBefore = now.addingTimeInterval(minOf(uploadRetryMaxBackoff, doubled))
    }

    fun noteUploadSucceeded() {
        uploadFailureCount = 0
        uploadRetryNotBefore = null
    }

    val uploadFailureStreak: Int get() = uploadFailureCount
    val uploadRetryNotBeforeForTest: SwiftDate? get() = uploadRetryNotBefore

    private fun persistVisibility() {
        defaults.putBoolean(visibilityKey, visibility.masterEnabled)
        writeStringList(disabledProvidersKey, visibility.disabledRaws.sorted())
        writeStringList(pendingClearKey, pendingClear.map { it.rawValue }.sorted())
    }

    /**
     * 결과 반영. 새로 읽은 제공자는 **통째로 교체**(옛 값과 max 를 취하지 않는다), 못 읽은 제공자는 그대로(하한), 숨기는 실패는 값까지 지운다.
     * INV-AILimitStore-e865b750 이식: 이번 바퀴에 **결과가 있는** 제공자만 실패를 갈아 끼운다("이번에 안 읽었다"는 "사라졌다"가 아니다).
     */
    fun apply(outcome: AILimitReadOutcome, now: SwiftDate) {
        val merged = LinkedHashMap<AILimitProvider, AILimitProviderSnapshot>()
        for (s in bundle?.providers ?: emptyList()) merged[s.provider] = s
        for (s in outcome.snapshots) merged[s.provider] = s
        for ((p, f) in outcome.failures) if (f.hidesProvider) merged.remove(p)
        bundle = AILimitSnapshotBundle(providers = merged.values.sortedBy { it.provider.sortOrder })
        val nextFailures = LinkedHashMap(failures)
        for (p in outcome.results.keys) nextFailures.remove(p)
        nextFailures.putAll(outcome.failures)
        failures = nextFailures
        silentUntil = if (AILimitReadFailure.rateLimited in outcome.failures.values) now.addingTimeInterval(outcome.retryAfter ?: defaultBackoff) else null
        persist()
        publish()
    }

    private fun persist() {
        val b = bundle
        if (b != null) defaults.putString(snapshotKey, encodeBundle(b)) else defaults.remove(snapshotKey)
        defaults.putString(failuresKey, JsonObject(failures.entries.associate { (p, f) -> p.rawValue to JsonPrimitive(f.rawValue) }).toString())
        persistSchedule()
    }

    private fun persistSchedule() {
        lastAttemptAt?.let { defaults.putString(lastAttemptKey, it.timeIntervalSince1970.toString()) } ?: defaults.remove(lastAttemptKey)
        silentUntil?.let { defaults.putString(silentUntilKey, it.timeIntervalSince1970.toString()) } ?: defaults.remove(silentUntilKey)
    }
}
