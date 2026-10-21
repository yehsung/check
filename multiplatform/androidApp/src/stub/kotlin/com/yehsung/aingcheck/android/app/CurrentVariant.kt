// stub 변형 표식(AppVariant.kt, E§4.6). 빌드 유형 `stub` 은 조정자 패치가 androidApp/build.gradle.kts 에 만든다 —
// 그 전에는 이 소스셋이 컴파일되지 않는다.
package com.yehsung.aingcheck.android.app

internal object CurrentVariant {
    val kind: AppVariantKind = AppVariantKind.STUB
}
