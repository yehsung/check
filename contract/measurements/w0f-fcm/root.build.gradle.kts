// 원본: 없음 (W0-f ⑤ FCM 토큰 탐침 — 빌드에 들지 않는 측정기 원문, 저장소 밖 스크래치 사본에서 빌드한다)
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath("com.android.tools.build:gradle:9.3.1")
        // AGP 9 가 끌어오는 KGP 를 저장소와 같은 판(캐시에 있는 2.4.21)으로 맞춘다
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
    }
}
