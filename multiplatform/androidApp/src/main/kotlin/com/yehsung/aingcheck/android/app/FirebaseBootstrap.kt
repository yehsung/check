// Firebase 수동 초기화(E§6.6, A§6-1). google-services 플러그인·google-services.json 을 쓰지 않는다(공개 저장소).
// - 매니페스트가 FirebaseInitProvider 를 지운다(자동 초기화 0) + firebase_messaging_auto_init_enabled=false(로그인 전 토큰 생성 0).
// - 초기화는 **release 조립 지점 + 설정이 온전 + 시험 아님** 일 때만. debug·stub·시험(Robolectric·계측)은 초기화하지 않는다 —
//   시험이 실제 제공자를 부르지 않게(E§12).
// - 설정 값은 운영 구성과 같은 길로 들어온다(§8-5, W0-a): Gradle 속성 → 생성 소스. 기본은 더미(빈 값)이고 release 변형만 읽는다.
//   그 생성 상수는 build-logic(조정자 몫)이 만든다 — FirebaseConfigSource 참조.
package com.yehsung.aingcheck.android.app

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

/** Firebase 앱 설정 넷(비밀이 아니라 앱에 실려 나가는 식별자다 — 그래도 저장소에는 두지 않는다). */
data class FirebaseSettings(
    val applicationId: String,
    val projectId: String,
    val gcmSenderId: String,
    val apiKey: String,
) {
    companion object {
        private val APP_ID = Regex("^1:[0-9]{3,20}:android:[0-9a-f]{6,40}$")
        private val PROJECT_ID = Regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
        private val SENDER_ID = Regex("^[0-9]{3,20}$")
        private val API_KEY = Regex("^[A-Za-z0-9_-]{20,80}$")

        /** 넷 다 모양이 맞을 때만 값. 빈 값(더미 기본)·공백·모양 틀림은 null — 초기화하지 않는다. */
        fun parse(applicationId: String, projectId: String, gcmSenderId: String, apiKey: String): FirebaseSettings? {
            if (!APP_ID.matches(applicationId) || !PROJECT_ID.matches(projectId) ||
                !SENDER_ID.matches(gcmSenderId) || !API_KEY.matches(apiKey)
            ) return null
            // 앱 id 의 발신자 번호와 sender id 가 다르면 서로 다른 프로젝트의 값을 섞어 넣은 것이다.
            if (applicationId.split(':')[1] != gcmSenderId) return null
            return FirebaseSettings(applicationId, projectId, gcmSenderId, apiKey)
        }
    }
}

enum class FirebaseDecision {
    INITIALIZE,
    SKIP_NOT_RELEASE,
    SKIP_RUNNING_TESTS,
    SKIP_NO_CONFIG,
}

object FirebaseBootstrap {
    /** 순수 판정(시험이 표로 잰다). 순서: 변형 → 시험 → 설정. */
    fun decide(variant: AppVariantKind, settings: FirebaseSettings?, runningTests: Boolean): FirebaseDecision = when {
        variant != AppVariantKind.RELEASE -> FirebaseDecision.SKIP_NOT_RELEASE
        runningTests -> FirebaseDecision.SKIP_RUNNING_TESTS
        settings == null -> FirebaseDecision.SKIP_NO_CONFIG
        else -> FirebaseDecision.INITIALIZE
    }

    /** [decide] 가 INITIALIZE 일 때만 기본 FirebaseApp 을 만든다. 만들었으면(또는 이미 있으면) true. */
    fun apply(context: Context, decision: FirebaseDecision, settings: FirebaseSettings?): Boolean {
        if (decision != FirebaseDecision.INITIALIZE || settings == null) return false
        if (FirebaseApp.getApps(context).isNotEmpty()) return true
        val options = FirebaseOptions.Builder()
            .setApplicationId(settings.applicationId)
            .setProjectId(settings.projectId)
            .setGcmSenderId(settings.gcmSenderId)
            .setApiKey(settings.apiKey)
            .build()
        return runCatching { FirebaseApp.initializeApp(context, options) }.isSuccess
    }
}
