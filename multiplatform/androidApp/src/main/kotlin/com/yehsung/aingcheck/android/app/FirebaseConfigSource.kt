// Firebase 설정의 원천(§8-5 와 같은 길: Gradle 속성 → 생성 소스 ProdConfig, 기본 더미, release 변형만 읽는다).
//
// 지금 판: 생성 상수(ProdConfig.FIREBASE_*)가 아직 없다 — build-logic(AingcheckBuild.kt · aingcheck.android-app)은 조정자 몫이라
// W1-g 는 패치로 낸다(완료 보고 coordinator_patches 의 w1g-02). 패치 전에는 어느 변형이든 설정이 없다 = Firebase 를 초기화하지 않는다.
// 패치는 이 함수 본문을 `FirebaseSettings.parse(ProdConfig.FIREBASE_APP_ID, …)` 한 줄로 바꾼다(debug 의 ProdConfig 값은 빈 문자열이라
// parse 가 null — 변형 판정과 겹으로 막힌다).
package com.yehsung.aingcheck.android.app

internal object FirebaseConfigSource {
    fun settings(): FirebaseSettings? = null
}
