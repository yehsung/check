// 루트 프로젝트 전용. build-logic 의 classpath(KGP·AGP·CMP)를 루트 클래스로더에 한 번만 올려
// 하위 프로젝트가 같은 플러그인 클래스를 나눠 쓰게 한다("loaded multiple times" 경고 방지).
// 게이트 집계 작업과 판 확인 작업을 둔다.

val gateFast = tasks.register("aingcheckGateFast") {
    group = "verification"
    description = "빠른 게이트(scripts/gate-fast.sh 가 봉인 아래에서 부른다)."
}
val gateDesktop = tasks.register("aingcheckGateDesktop") {
    group = "verification"
    description = "데스크톱 JVM 시험만(Windows 러너 방화벽 봉인 아래)."
}
val prefetch = tasks.register("aingcheckPrefetch") {
    group = "build setup"
    description = "모든 모듈의 의존 예열(봉인 밖에서 한 번)."
}

subprojects {
    val sub = path // configure { } 안의 path 는 작업 경로라 따로 잡는다
    plugins.withId("aingcheck.test-seal") {
        gateFast.configure { dependsOn("$sub:aingcheckGateTests") }
        gateDesktop.configure { dependsOn("$sub:aingcheckGateDesktopTests") }
        prefetch.configure { dependsOn("$sub:aingcheckPrefetch") }
    }
}

// 판 확인(완료 기준 ①): Gradle·Kotlin(KGP)·AGP·CMP·JDK 를 한 줄씩 찍는다.
// `./gradlew --version` 의 Kotlin 줄은 Gradle 이 품은 빌드 스크립트용 Kotlin 이다(KGP 판이 아니다).
tasks.register("aingcheckVersions") {
    group = "help"
    description = "빌드 도구 판을 찍는다."
    val gradleVersion = gradle.gradleVersion
    val javaVersion = System.getProperty("java.runtime.version")
    val javaVendor = System.getProperty("java.vendor")
    val kgp = org.jetbrains.kotlin.gradle.plugin.getKotlinPluginVersion(logger)
    // AGP 판: 실제로 올라온 플러그인 jar 에서 읽는다(목록 파일의 기대값이 아니라).
    val agp = runCatching {
        Class.forName("com.android.builder.model.Version").getField("ANDROID_GRADLE_PLUGIN_VERSION").get(null) as String
    }.getOrElse {
        Class.forName("com.android.build.gradle.AppPlugin").`package`?.implementationVersion ?: "unknown"
    }
    val cmp = aingcheckLibs.version("compose-multiplatform")
    doLast {
        println("gradle=$gradleVersion")
        println("kotlin-gradle-plugin=$kgp")
        println("agp=$agp")
        println("compose-multiplatform=$cmp")
        println("jdk=$javaVersion ($javaVendor)")
    }
}
