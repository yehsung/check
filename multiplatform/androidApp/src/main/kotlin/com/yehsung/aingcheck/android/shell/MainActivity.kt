// 단일 Activity(E§1.1). 매니페스트 launchMode = singleTask(E-U16):
//   딥링크 → 프로세스 죽음 → 런처 아이콘 순서에서도 같은 작업의 이 인스턴스가 onNewIntent 로 받는다(Activity 1개).
//   표준 모드에서는 작업 뿌리 Intent(VIEW)와 런처 Intent(MAIN)가 달라 시스템이 인스턴스를 하나 더 쌓았다(W0-f 실측).
// Intent 처리:
//   - onCreate: 저장 상태가 없을 때만 getIntent() 를 연다. 저장 상태가 있으면(회전·프로세스 죽음 복원) 화면은 이미 복원된 스택이다 —
//     같은 딥링크를 다시 열지 않는다.
//   - onNewIntent: 새 라우트를 연다. 런처(MAIN)·모르는 모양이면 아무것도 바꾸지 않는다(복원된 화면 그대로).
//   - 최근 앱(기록)에서 다시 띄운 작업 뿌리 Intent(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)는 extra 째 다시 온다 — 수락은 버리고
//     화면만 연다(판돈이 걸린 respond 가 두 번 실리지 않게, G §8-13). 처리한 Intent 는 setIntent 로 라우트·수락 extra 를 지운다.
package com.yehsung.aingcheck.android.shell

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow

class MainActivity : ComponentActivity() {
    /** 열 라우트. 버퍼가 있어 화면이 그려지기 전에 온 요청도 잃지 않는다. */
    private val requests = Channel<RouteRequest>(Channel.BUFFERED)
    private val container get() = (application as AingApplication).container

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        logIntent("onCreate", intent, restored = savedInstanceState != null)
        if (savedInstanceState == null) route(intent)
        val c = container
        setContent {
            val phase by c.shellPhase.collectAsStateWithLifecycle()
            // 흐름 하나를 붙잡아 둔다 — 다시 그릴 때마다 새로 만들면 수집이 끊겼다 다시 붙으며 받은 요청을 흘릴 수 있다.
            val requestFlow = remember { requests.receiveAsFlow() }
            MaterialTheme {
                Surface {
                    AingShell(
                        phase = phase,
                        requests = requestFlow,
                        onVisibleRoute = c.visibleRoute::setRoute,
                        onAccept = { c.pendingInviteAccept.value = it },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        logIntent("onNewIntent", intent, restored = false)
        route(intent)
    }

    private fun route(intent: Intent?) {
        val incoming = RouteIntents.read(intent) ?: return
        // 증표는 수락을 요청한 Intent 에서만 꺼낸다(처음 쓸 때 만들어 저장한다 — 화면만 여는 딥링크에 디스크 쓰기를 붙이지 않는다).
        // 기록에서 다시 온 Intent 의 수락을 버리는 문은 parse 한 곳이다(시험이 그 한 곳을 잰다 — 겹문으로 가리지 않는다).
        val proof = if (incoming.acceptExtra) container.routeProof.value() else null
        val request = RouteIntents.parse(incoming, expectedProof = proof)
        if (intent != null && (incoming.routeExtra != null || incoming.acceptExtra || incoming.proofExtra != null)) {
            setIntent(RouteIntents.consumed(intent))
        }
        container.logger.log(
            LogLevel.INFO, "AingShell",
            "route accept=${request?.accept} history=${incoming.launchedFromHistory} opened=${request != null}",
        )
        request?.let { requests.trySend(it) }
    }

    /** 작업·인스턴스 시험(E-U16 기기 시나리오)이 읽는 한 줄. 라우트 id 만 싣는다(본문·토큰 없음). */
    private fun logIntent(where: String, intent: Intent?, restored: Boolean) {
        container.logger.log(
            LogLevel.INFO, "AingShell",
            "$where restored=$restored task=$taskId action=${intent?.action} instance=${System.identityHashCode(this)}",
        )
    }
}
