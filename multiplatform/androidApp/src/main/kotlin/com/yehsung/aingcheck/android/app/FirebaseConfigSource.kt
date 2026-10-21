// Firebase 설정의 원천(§8-5 와 같은 길: Gradle 속성 → 생성 소스 ProdConfig, 기본 더미, release 변형만 읽는다).
//
// 생성 상수 ProdConfig.FIREBASE_*(build-logic — 조정자 몫)를 읽는다. debug·stub 의 값은 빈 문자열이라 parse 가 null 이고,
// 변형 판정(FirebaseBootstrap.decide — release 만)과 겹으로 막힌다.
package com.yehsung.aingcheck.android.app

import com.yehsung.aingcheck.android.generated.ProdConfig

internal object FirebaseConfigSource {
    fun settings(): FirebaseSettings? = FirebaseSettings.parse(
        ProdConfig.FIREBASE_APP_ID,
        ProdConfig.FIREBASE_PROJECT_ID,
        ProdConfig.FIREBASE_SENDER_ID,
        ProdConfig.FIREBASE_API_KEY,
    )
}
