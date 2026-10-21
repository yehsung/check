// 단일 Activity(E§1.1). 매니페스트 launchMode = singleTask(E-U16):
//   딥링크 → 프로세스 죽음 → 런처 아이콘 순서에서도 같은 작업의 이 인스턴스가 onNewIntent 로 받는다(Activity 1개).
//   표준 모드에서는 작업 뿌리 Intent(VIEW)와 런처 Intent(MAIN)가 달라 시스템이 인스턴스를 하나 더 쌓았다(W0-f 실측).
// Intent 처리:
//   - onCreate: 저장 상태가 없을 때만 getIntent() 를 연다. 저장 상태가 있으면(회전·프로세스 죽음 복원) 화면은 이미 복원된 스택이다 —
//     같은 딥링크를 다시 열지 않는다.
//   - onNewIntent: 새 라우트를 연다. 런처(MAIN)·모르는 모양이면 아무것도 바꾸지 않는다(복원된 화면 그대로).
package com.yehsung.aingcheck.android.shell

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
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
            MaterialTheme {
                Surface {
                    AingShell(
                        phase = phase,
                        requests = requests.receiveAsFlow(),
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
        val request = RouteIntents.parse(incoming, expectedProof = container.routeProof.value()) ?: return
        requests.trySend(request)
    }

    /** 작업·인스턴스 시험(E-U16 기기 시나리오)이 읽는 한 줄. 라우트 id 만 싣는다(본문·토큰 없음). */
    private fun logIntent(where: String, intent: Intent?, restored: Boolean) {
        container.logger.log(
            LogLevel.INFO, "AingShell",
            "$where restored=$restored task=$taskId action=${intent?.action} instance=${System.identityHashCode(this)}",
        )
    }
}
