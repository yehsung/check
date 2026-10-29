// 원본: Sources/check/WorkTimerStoreAILimits.swift:1-293 @ a90d8623 (갱신 + 업로드 배선 · 설정 스위치 · 메인 기기 고르개 · 업로드 장부 지문)
// 맥의 WorkTimerStore 확장 → Windows 는 값만 받는 독립 클래스(세션·기기 id·서비스는 조립이 넘긴다, 지시서 §4 "값만 넘긴다").
// 업로드는 **깃발 없이**(W-3 #11 — ai_limits 는 서버 ④·⑥ 대상 아님). 기기 id 가 null 이면 업로드 0(새로 짓지 않는다).
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.fetchAILimitMainDeviceID
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.math.BigDecimal
import java.math.RoundingMode

/** 업로드에 쓸 로그인 한 벌(토큰은 이 값으로만 지나간다 — 저장하지 않는다). */
data class AILimitSession(val accessToken: String, val userID: String)

/**
 * 리밋 스토어의 주기를 돌리고 받은 숫자를 올린다. **순서가 계약**: 올리는 값은 방금 읽은 값이다.
 * 게이트: ① 세션(읽기는 로그인 없이도 한다) ② 기기 id — INV-WorkTimerStoreAILimits-e77f2ac7 이식: **새로 지어내지 않는다**(저장 확인 없이 만든
 * id 로 올렸다가 순위표가 2배가 된 전례) ③ 장부 지문이 바뀌었을 때만. 수집 설정(tokenUsageCollect)·tokenUpload 깃발은 게이트가 아니다.
 */
class DesktopAILimitSync(
    val store: AILimitStore,
    private val service: SupabaseWorkService,
    private val session: () -> AILimitSession?,
    /** 확인된 기기 id(Windows `win:…`) 또는 null. null 이면 서버 쓰기 0. */
    private val deviceId: () -> String?,
) {
    /** 마지막으로 **성공한** 업로드의 지문(맥 `lastUploadedAILimits` — 메모리). */
    var lastUploadedAILimits: String? = null
        private set
    private val gate = Mutex()

    /** 플라이아웃 열림·30초 틱의 진입점. `force` = 방금 열었다(스토어 5분 하한 유지). */
    suspend fun refreshAILimitsIfNeeded(now: SwiftDate, force: Boolean = false) {
        store.refreshIfDue(now, force)
        uploadAILimitsIfNeeded(now)
    }

    /**
     * 업로드 진입점 — **직렬화만** 한다.
     * INV-WorkTimerStoreAILimits-cad9d3ba 이식: 비행 중이면 새로 쏘지 않고 **트레일링 한 번**으로 합친다(같은 PK 가 두 본문에 동시에 뜨지 않게).
     * INV-WorkTimerStoreAILimits-889c764b 이식: 트레일링을 소비하는 동안에도 '비행 중'이 참이어야 그 사이 요청이 또 쏘지 않는다 — 루프 뒤에 내린다.
     * INV-WorkTimerStoreAILimits-2a934841 이식: 둘째 바퀴부터는 **그 시점의 now**(스토어 시계)로 돈다 — 첫 바퀴의 옛 now 로 백오프를 재지 않는다.
     */
    suspend fun uploadAILimitsIfNeeded(now: SwiftDate) {
        val mine = gate.withLock {
            if (store.uploadInFlight) {
                store.uploadPendingTrailing = true
                false
            } else {
                store.uploadInFlight = true
                true
            }
        }
        if (!mine) return
        var at = now
        try {
            while (true) {
                gate.withLock { store.uploadPendingTrailing = false }   // 루프 안에서 먼저 내린다(이번 업로드 중 온 신호를 지우지 않게)
                sendAILimitsUpload(at)
                at = store.clockNow
                val again = gate.withLock {
                    if (store.uploadPendingTrailing) true else { store.uploadInFlight = false; false }
                }
                if (!again) return
            }
        } catch (e: Throwable) {
            gate.withLock { store.uploadInFlight = false }
            throw e
        }
    }

    /**
     * 변경 게이트 + 업로드 한 번. 실패는 조용히(장부는 성공에만).
     * INV-WorkTimerStoreAILimits-33a2f5bf 이식: 비우기는 "묶음이 비었으면 반환"보다 **앞**(전체 끄기가 서버에 닿게).
     * INV-WorkTimerStoreAILimits-8a8e0c07 이식: 백오프는 **값 업로드에도** 걸린다(느려지되 멈추지 않는다 — 60초 → 두 배 → 1시간).
     */
    private suspend fun sendAILimitsUpload(now: SwiftDate) {
        val session = session() ?: return
        val deviceID = deviceId() ?: return
        val claim = store.claimPendingClear()
        val bundle = store.enabledBundle
        val hasValues = bundle.visibleProviders.isNotEmpty()
        val fingerprint = AILimitUploadLedger.fingerprint(bundle)
        val valuesChanged = hasValues && fingerprint != lastUploadedAILimits
        if (!valuesChanged && claim.isEmpty) return
        if (!store.uploadRetryAllowed(now)) return
        store.noteUploadStarted()
        try {
            service.upsertAILimits(session.accessToken, session.userID, deviceID, store.deviceLabel, bundle, claim.providers, now)
            if (valuesChanged) lastUploadedAILimits = fingerprint
            store.markCleared(claim)
            store.noteUploadSucceeded()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            store.noteUploadFailed(now)
        } finally {
            store.noteUploadFinished()
        }
    }

    // ------------------------------------------------------------------ 설정 스위치(설정 화면은 이 둘만 부른다)
    suspend fun setAILimitsVisible(enabled: Boolean) {
        store.setMasterEnabled(enabled)
        noteAILimitsSettingChanged()
    }

    suspend fun setAILimitProviderEnabled(provider: AILimitProvider, enabled: Boolean) {
        store.setProviderEnabled(provider, enabled)
        noteAILimitsSettingChanged()
    }

    /** 설정이 바뀌면 ① 장부를 버리고 ② 그 순간 올린다(30초 틱을 기다리면 "껐는데 폰에 아직 있다"가 생긴다). */
    private suspend fun noteAILimitsSettingChanged() {
        lastUploadedAILimits = null
        uploadAILimitsIfNeeded(store.clockNow)
    }

    // ------------------------------------------------------------------ 메인 기기 고르개(설정 창 전용 — 틱이 부르지 않는다)
    /**
     * 내 기기 목록과 고른 메인 PC 를 받아 온다.
     * INV-WorkTimerStoreAILimits-b7e01252 이식: **둘 다 성공해야 반영한다**(못 읽은 선택을 "안 고름"으로 그리지 않는다).
     * INV-WorkTimerStoreAILimits-3193f7a8 이식: 실패는 **조용하다**(목록이 비면 고르개 줄이 안 보인다 — 진단 문구 없음).
     */
    suspend fun loadAILimitDevicesIfNeeded(now: SwiftDate, force: Boolean = false) {
        val session = session() ?: return
        deviceId() ?: return
        if (!force && !store.devicesAreDue(now)) return
        store.noteDevicesLoading(true)
        try {
            val devices = service.fetchAILimitDevices(session.accessToken, session.userID)
            val chosen = service.fetchAILimitMainDeviceID(session.accessToken, session.userID)
            store.applyDevices(devices, chosen, now)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // 조용히 — 스탬프를 안 찍었으므로 다음에 다시 묻는다.
        } finally {
            store.noteDevicesLoading(false)
        }
    }

    /** 먼저 화면에 반영하고 서버에 쓰고, 실패하면 되돌린다(화면만 바뀌는 거짓말을 하지 않는다). */
    suspend fun setAILimitMainDevice(deviceID: String) {
        val session = session() ?: return
        deviceId() ?: return
        val previous = store.setMainDeviceLocally(deviceID)
        try {
            service.upsertAILimitMainDeviceID(session.accessToken, session.userID, deviceID)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            store.setMainDeviceLocally(previous)
        }
    }
}

/**
 * 업로드 변경 게이트의 지문(순수). 조건 둘: ① 값(퍼센트·리셋·플랜·계정 지문)이 바뀌었다 ② 같아도 관측 시각이 **한 칸(15분)** 넘게 움직였다.
 * INV-WorkTimerStoreAILimits-388d22a6 이식: 칸은 `now` 가 아니라 **관측 시각**에서 뽑는다(못 읽는 동안 다시 올려도 같은 옛 observed_at 이다).
 */
object AILimitUploadLedger {
    const val observedBucketSeconds: Double = 900.0

    fun observedBucket(seconds1970: Double): Long = kotlin.math.floor(seconds1970 / observedBucketSeconds).toLong()

    /** Swift `String(format: "%.3f", x)`(C printf — 정확한 이진 값을 반올림, 동률은 짝수 쪽, 음의 0 은 "-0.000"). */
    fun percentText(value: Double): String {
        if (value.isNaN()) return "nan"
        if (value.isInfinite()) return if (value > 0) "inf" else "-inf"
        val text = BigDecimal(value).setScale(3, RoundingMode.HALF_EVEN).toPlainString()
        val negative = value < 0 || (value == 0.0 && 1.0 / value < 0)
        return if (negative && !text.startsWith("-")) "-$text" else text
    }

    fun fingerprint(bundle: AILimitSnapshotBundle): String = bundle.visibleProviders.joinToString(";") { snapshot ->
        val parts = mutableListOf(snapshot.provider.rawValue)
        for (window in AILimitWindow.entries.sortedBy { it.sortOrder }) {
            val row = snapshot.window(window)
            parts += row?.let { percentText(it.usedPercent) } ?: "-"
            // Swift `Int(date.timeIntervalSince1970)` — 0 쪽으로 자른다.
            parts += row?.resetsAt?.let { SwiftDate(it).timeIntervalSince1970.toLong().toString() } ?: "-"
        }
        parts += snapshot.planLabel ?: "-"
        parts += snapshot.accountFingerprint ?: "-"
        parts += snapshot.latestObservedAt?.let { observedBucket(SwiftDate(it).timeIntervalSince1970).toString() } ?: "-"
        parts.joinToString("|")
    }
}
