// 앱 안 이동(알림·위젯) Intent ↔ 라우트. E§4.6: 앱 안 이동은 **명시적 Intent + 라우트 extra** 로 한다 — 커스텀 스킴 VIEW 는
// 다른 앱도 보낼 수 있고 가로챌 수도 있다. 바깥에서 온 VIEW(aingcheck://…)는 화면 이동만 하고 부작용이 없다.
//
// [수락](오목·체스 신청 알림 버튼)은 서버에 쓰는 일(판돈이 걸린 respond)이다. MainActivity 는 런처 때문에 exported 라
// 다른 앱이 같은 extra 를 실은 명시적 Intent 를 보낼 수 있다 → 수락은 **이 설치만 아는 증표**가 맞을 때만 참이다.
// 증표는 앱 전용 저장소의 무작위 값이고(RouteProof), 알림 PendingIntent(FLAG_IMMUTABLE)에만 실린다.
//
// 최근 앱(기록)에서 다시 띄우면 시스템은 작업 뿌리 Intent 를 extra 째 다시 배달한다(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY).
// 알림 [수락] 이 작업 뿌리였다면 증표까지 그대로 다시 온다 → 기록에서 온 Intent 의 수락은 버리고 화면만 연다(G §8-13).
package com.yehsung.aingcheck.android.routing

import android.content.Context
import android.content.Intent
import com.yehsung.aingcheck.android.shell.MainActivity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import java.security.MessageDigest
import java.security.SecureRandom

/** 앱 안 이동 요청 하나. [accept] 는 오목·체스 신청에서만 참일 수 있다. */
data class RouteRequest(val route: AingRoute, val accept: Boolean = false)

object RouteIntents {
    const val ACTION_OPEN_ROUTE = "com.yehsung.aingcheck.action.OPEN_ROUTE"
    const val EXTRA_ROUTE = "com.yehsung.aingcheck.extra.ROUTE"
    const val EXTRA_ACCEPT = "com.yehsung.aingcheck.extra.ACCEPT"
    const val EXTRA_PROOF = "com.yehsung.aingcheck.extra.PROOF"

    /** 들어온 Intent 의 글자들(순수 판정용 — JVM 시험이 Intent 없이 닿는다). */
    data class Incoming(
        val action: String?,
        val dataString: String?,
        val routeExtra: String?,
        val acceptExtra: Boolean,
        val proofExtra: String?,
        /** 최근 앱(기록)에서 다시 띄운 작업 뿌리 Intent 인가(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY). 그러면 수락은 언제나 거짓이다. */
        val launchedFromHistory: Boolean = false,
    )

    /**
     * 순수 판정.
     * - VIEW + aingcheck:// → 라우트(수락 없음). extra 는 보지 않는다.
     * - OPEN_ROUTE + 라우트 extra → 라우트. 수락은 신청 라우트이고 증표가 [expectedProof] 와 같고 기록에서 다시 온 것이 아닐 때만.
     * - 그 밖(런처 MAIN 등)·모르는 모양 → null(화면을 바꾸지 않는다).
     */
    fun parse(incoming: Incoming, expectedProof: String?): RouteRequest? = when (incoming.action) {
        Intent.ACTION_VIEW -> incoming.dataString?.let(AingRoute::parse)?.let { RouteRequest(it) }
        ACTION_OPEN_ROUTE -> incoming.routeExtra?.let(AingRoute::parse)?.let { route ->
            val acceptable = route is AingRoute.GomokuInvite || route is AingRoute.ChessInvite
            val proven = !expectedProof.isNullOrEmpty() && !incoming.proofExtra.isNullOrEmpty() &&
                MessageDigest.isEqual(expectedProof.toByteArray(), incoming.proofExtra.toByteArray())
            RouteRequest(route, accept = incoming.acceptExtra && acceptable && proven && !incoming.launchedFromHistory)
        }
        else -> null
    }

    fun read(intent: Intent?): Incoming? = intent?.let {
        Incoming(
            action = it.action,
            dataString = it.dataString,
            routeExtra = it.getStringExtra(EXTRA_ROUTE),
            acceptExtra = it.getBooleanExtra(EXTRA_ACCEPT, false),
            proofExtra = it.getStringExtra(EXTRA_PROOF),
            launchedFromHistory = (it.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0,
        )
    }

    /** 처리한 Intent 의 사본에서 라우트·수락 extra 를 지운다(getIntent() 를 다시 읽어도 수락이 한 번 더 실리지 않게). */
    fun consumed(intent: Intent): Intent = Intent(intent).apply {
        removeExtra(EXTRA_ROUTE)
        removeExtra(EXTRA_ACCEPT)
        removeExtra(EXTRA_PROOF)
    }

    /** 알림·위젯이 여는 명시적 Intent. [proof] 는 수락 요청일 때만 싣는다. */
    fun explicit(context: Context, request: RouteRequest, proof: String?): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_ROUTE
            putExtra(EXTRA_ROUTE, request.route.url)
            if (request.accept && !proof.isNullOrEmpty()) {
                putExtra(EXTRA_ACCEPT, true)
                putExtra(EXTRA_PROOF, proof)
            }
        }
}

/** 이 설치만 아는 수락 증표(32바이트 무작위, 앱 전용 저장소). 처음 쓸 때 만들고 그 뒤로는 같은 값이다. */
class RouteProof(private val store: KeyValueStore, private val random: SecureRandom = SecureRandom()) {
    /** 증표. 저장소에 못 쓰면 null — 그때는 수락 버튼을 싣지 않는다(빈 증표가 통과하는 길을 두지 않는다). */
    @Synchronized
    fun value(): String? {
        store.getString(KEY)?.takeIf { it.length == 64 }?.let { return it }
        val bytes = ByteArray(32).also(random::nextBytes)
        val fresh = bytes.joinToString("") { "%02x".format(it) }
        store.putString(KEY, fresh)
        // 써 놓고 다시 읽어 같을 때만 쓴다 — 못 썼으면 수락 증표를 내지 않는다(알림은 그래도 화면은 연다).
        return store.getString(KEY)?.takeIf { it == fresh }
    }

    private companion object {
        const val KEY = "aingcheck.route.acceptProof"
    }
}
