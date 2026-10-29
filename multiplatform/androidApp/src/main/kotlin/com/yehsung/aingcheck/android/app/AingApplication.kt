// 프로세스 시작점: 그릇 만들기 · 알림 채널 다섯 · 폰 앱 모델 시작(수명 · 푸시 다리 · 세션 복원) · Firebase 판정(release 조립 지점에서만 초기화).
// 네트워크·디스크 큰 일을 여기서 하지 않는다(위젯·FCM 콜드 스타트의 짧은 창).
package com.yehsung.aingcheck.android.app

import android.app.Application
import androidx.lifecycle.ProcessLifecycleOwner
import com.yehsung.aingcheck.android.push.NotificationChannels
import com.yehsung.aingcheck.android.push.PushBridge
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
        // 폰 앱 모델(K11 — W2-f §2): 시험 프로세스는 세션을 시작하지 않는다(망 0 — 시험은 스텁 서버의 앱 모델을 따로 만든다, C§4 #17).
        if (!c.runningTests.isRunningTests) startPhone(c)
        c.lifecycle.attach(ProcessLifecycleOwner.get().lifecycle)

        val settings = FirebaseConfigSource.settings()
        val decision = FirebaseBootstrap.decide(AppVariant.kind, settings, c.runningTests.isRunningTests)
        firebaseDecision = decision
        val initialized = FirebaseBootstrap.apply(this, decision, settings)
        c.logger.log(LogLevel.INFO, TAG, "variant=${AppVariant.kind} firebase=$decision initialized=$initialized")
    }

    /** 수명(ON_START/ON_STOP 만 — E§5.1) · 푸시 다리(패치 0001) · client_release → 세션 복원(한 번). */
    private fun startPhone(c: AppContainer) {
        val phone = c.phone
        c.lifecycle.addListener { foreground -> if (foreground) phone.sceneDidBecomeActive() else phone.sceneDidEnterBackground() }
        c.pushSystem.onToken = phone.push::didReceivePushToken
        c.pushSystem.onTokenFailure = phone.push::didFailToRegister
        phone.push.attach(c.pushSystem)
        PushBridge.start(c.mainScope, c.pushInbox, deliver = { content -> phone.push.didReceive(content) }, token = phone.push::didReceivePushToken)
        phone.start()
    }

    private companion object {
        const val TAG = "AingApp"
    }
}
