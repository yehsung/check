// 원본: Sources/check/WorkTimerStore.swift:4385-4420 @ a63fea2 (NetworkPathObserving.waitUntilSatisfied — 호출마다 새 NWPathMonitor,
//       첫 보고를 진실로, 상한은 호출자(스토어)가 건다, 취소되면 돌아온다) · :420-428(상한 10초는 스토어 몫 → 우리는 WakeGate)
//
// Windows 는 iphlpapi `GetNetworkConnectivityHint`(Windows 10 2004 / build 19041+)를 **짧은 간격으로 묻는다**. 고른 이유:
//  - 한 번 부르면 지금 값이 바로 온다 = 맥 '호출마다 새 모니터, 첫 보고가 진실'과 같은 꼴(잠들기 전에 받아 둔 값을 믿지 않는다).
//  - NotifyAddrChange 는 "주소표가 바뀌었다"만 알려 준다(준비됐는지는 다시 물어야 한다) + 취소하려면 OVERLAPPED·CancelIPChangeNotify.
//  - NotifyNetworkConnectivityHintChange(콜백 꼴)는 12바이트 구조체를 **값으로** 네이티브 스레드에서 넘긴다 — JNA ByValue 콜백
//    마샬링이 x64·arm64 에서 다를 수 있어 러너 2종에서 확인할 것이 늘어난다. 묻기는 out 포인터 하나라 서명이 단순하다.
//  - 묻는 비용은 μs 단위이고, 기다리는 동안만(깨어난 뒤 몇 초) 돈다.
// 판정(맥 NWPath.satisfied = 경로가 있다, 인터넷 확인 아님): LocalAccess·InternetAccess·ConstrainedInternetAccess·Hidden → 준비됨.
// Unknown·None → 아직. 함수가 없거나(옛 Windows) 오류 코드면 **바로 연다**(fail-open — 매 깨움마다 상한 10초를 기다리는 것보다 낫다).
// 맥 개발 실행·시험은 [NetworkReadiness.AlwaysReady].
package com.yehsung.aingcheck.desktop.platform.windows.network

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Structure
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext

/** WorkDeps.wakeNetworkReady 를 채운다. 상한은 부르는 쪽(WakeGate 10초)이 건다 — 여기는 취소에만 응한다. */
fun interface NetworkReadiness {
    suspend fun awaitReady()

    companion object {
        /** 맥 개발 실행·시험: 늘 준비됨. */
        val AlwaysReady: NetworkReadiness = NetworkReadiness { }

        /** 실행 중인 OS 로 고른다. */
        fun forHost(isWindows: Boolean): NetworkReadiness = if (isWindows) PolledNetworkReadiness(WindowsConnectivityHint::probe) else AlwaysReady
    }
}

/** 한 번 묻기의 결과. */
sealed interface ConnectivityProbe {
    /** NL_NETWORK_CONNECTIVITY_LEVEL_HINT 값(0..5). */
    data class Level(val level: Int) : ConnectivityProbe

    /** 함수 없음·오류 코드 — 판정할 수 없다. */
    data class Unavailable(val reason: String) : ConnectivityProbe
}

enum class Readiness { READY, NOT_YET, FAIL_OPEN }

object ConnectivityLevels {
    const val UNKNOWN = 0
    const val NONE = 1
    const val LOCAL_ACCESS = 2
    const val INTERNET_ACCESS = 3
    const val CONSTRAINED_INTERNET_ACCESS = 4
    const val HIDDEN = 5

    fun classify(probe: ConnectivityProbe): Readiness = when (probe) {
        is ConnectivityProbe.Unavailable -> Readiness.FAIL_OPEN
        is ConnectivityProbe.Level -> when (probe.level) {
            LOCAL_ACCESS, INTERNET_ACCESS, CONSTRAINED_INTERNET_ACCESS, HIDDEN -> Readiness.READY
            UNKNOWN, NONE -> Readiness.NOT_YET
            // 문서에 없는 새 값 — 막지 않는다(fail-open).
            else -> Readiness.FAIL_OPEN
        }
    }
}

/**
 * [probe] 를 처음엔 바로, 그 뒤 [pollMillis] 마다 묻는다. READY·FAIL_OPEN 이면 돌아온다. 취소되면(상한이 이겼다) delay 에서 바로 끝난다.
 * [probeContext] 는 네이티브 호출 자리(앱 = IO, 시험 = 시험 디스패처).
 */
class PolledNetworkReadiness(
    private val probe: () -> ConnectivityProbe,
    private val pollMillis: Long = DEFAULT_POLL_MILLIS,
    private val probeContext: CoroutineContext = Dispatchers.IO,
) : NetworkReadiness {
    /** 마지막 판정(진단·시험). */
    @Volatile var lastProbe: ConnectivityProbe? = null
        private set

    override suspend fun awaitReady() {
        while (true) {
            val p = withContext(probeContext) { runCatching(probe).getOrElse { ConnectivityProbe.Unavailable(it.toString()) } }
            lastProbe = p
            if (ConnectivityLevels.classify(p) != Readiness.NOT_YET) return
            delay(pollMillis)
        }
    }

    companion object {
        const val DEFAULT_POLL_MILLIS = 250L
    }
}

/** NL_NETWORK_CONNECTIVITY_HINT(netioapi.h): 열거 둘(4+4) + BOOLEAN 셋 → 12바이트(끝 채움 1). */
@Structure.FieldOrder("ConnectivityLevel", "ConnectivityCost", "ApproachingDataLimit", "OverDataLimit", "Roaming")
class NL_NETWORK_CONNECTIVITY_HINT : Structure() {
    @JvmField var ConnectivityLevel: Int = 0
    @JvmField var ConnectivityCost: Int = 0
    @JvmField var ApproachingDataLimit: Byte = 0
    @JvmField var OverDataLimit: Byte = 0
    @JvmField var Roaming: Byte = 0

    companion object {
        const val EXPECTED_SIZE = 12
    }
}

/** iphlpapi.dll — Windows 밖에서는 로드하지 않는다(lazy). */
interface IphlpapiX : Library {
    /** NO_ERROR(0) 또는 Win32 오류 코드. Windows 10 2004+ 에만 있다(없으면 부를 때 UnsatisfiedLinkError). */
    fun GetNetworkConnectivityHint(hint: NL_NETWORK_CONNECTIVITY_HINT): Int

    companion object {
        val INSTANCE: IphlpapiX by lazy { Native.load("iphlpapi", IphlpapiX::class.java) }
    }
}

object WindowsConnectivityHint {
    /** 한 번 묻는다. 예외(함수 없음 등)도 Unavailable 로 접는다. */
    fun probe(): ConnectivityProbe = try {
        val hint = NL_NETWORK_CONNECTIVITY_HINT()
        val rc = IphlpapiX.INSTANCE.GetNetworkConnectivityHint(hint)
        if (rc == 0) ConnectivityProbe.Level(hint.ConnectivityLevel) else ConnectivityProbe.Unavailable("rc=$rc")
    } catch (t: Throwable) {
        ConnectivityProbe.Unavailable(t.toString())
    }
}
