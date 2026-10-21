// 프로세스 시작점. 하는 일은 셋뿐이다: 그릇 만들기 · 알림 채널 다섯 · Firebase 판정(release 조립 지점에서만 초기화).
// 네트워크·디스크 큰 일을 여기서 하지 않는다(위젯·FCM 콜드 스타트의 짧은 창).
package com.yehsung.aingcheck.android.app

import android.app.Application
import androidx.lifecycle.ProcessLifecycleOwner
import com.yehsung.aingcheck.android.push.NotificationChannels
import com.yehsung.aingcheck.core.foundation.platform.LogLevel

class AingApplication : Application() {
    lateinit var container: AppContainer
        private set

    /** 이번 프로세스의 Firebase 판정(시험이 읽는다). */
    var firebaseDecision: FirebaseDecision = FirebaseDecision.SKIP_NOT_RELEASE
        private set

    override fun onCreate() {
        super.onCreate()
        val c = AppContainer(this)
        container = c
        NotificationChannels.ensure(this)
        c.lifecycle.addListener { c.visibleRoute.setForeground(it) }
        c.lifecycle.attach(ProcessLifecycleOwner.get().lifecycle)

        val settings = FirebaseConfigSource.settings()
        val decision = FirebaseBootstrap.decide(AppVariant.kind, settings, c.runningTests.isRunningTests)
        firebaseDecision = decision
        val initialized = FirebaseBootstrap.apply(this, decision, settings)
        c.logger.log(LogLevel.INFO, TAG, "variant=${AppVariant.kind} firebase=$decision initialized=$initialized")
    }

    private companion object {
        const val TAG = "AingApp"
    }
}
