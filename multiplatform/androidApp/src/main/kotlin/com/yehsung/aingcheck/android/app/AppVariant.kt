// 이 APK 가 어느 변형인가. 값은 변형 소스셋(src/debug · src/release · src/stub)의 CurrentVariant 한 곳에서 온다 —
// 변형을 하나 더 만들고 그 소스셋에 CurrentVariant 를 두지 않으면 컴파일이 막힌다(조용히 기본값으로 접지 않는다).
// stub 은 데모 픽스처로 도는 시험·스크린샷 변형(E§4.6) — 빌드 유형은 조정자 패치 w1g-02(build-logic aingcheck.android-app)가 만든다.
package com.yehsung.aingcheck.android.app

enum class AppVariantKind {
    /** 개발·계측. 운영 구성 없음(§8-5 — ProdConfig 는 .invalid). */
    DEBUG,
    /** 데모 픽스처(E§4.6). 운영 주소가 아예 없고 Firebase 를 초기화하지 않는다. */
    STUB,
    /** 출시 조립 지점. 운영 구성·Firebase 설정이 Gradle 속성으로 들어오는 유일한 변형. */
    RELEASE,
}

object AppVariant {
    val kind: AppVariantKind get() = CurrentVariant.kind
}
