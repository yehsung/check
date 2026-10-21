// release 변형 표식(AppVariant.kt). 운영 구성·Firebase 설정이 들어오는 유일한 조립 지점이다(§8-5).
package com.yehsung.aingcheck.android.app

internal object CurrentVariant {
    val kind: AppVariantKind = AppVariantKind.RELEASE
}
