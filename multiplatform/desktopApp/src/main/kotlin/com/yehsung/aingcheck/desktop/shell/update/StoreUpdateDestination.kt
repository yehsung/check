// 원본: 없음(Windows 전용) — W-13 #7 · W-12(Store 판 업데이트 목적지 ms-windows-store://pdp/?ProductId=). 맥은 서버 download_url/앱스토어가 정한다.
// 최소 빌드 미달 화면(UpdateRequiredScreen)에서 갈 곳. 생성 상수 STORE_PRODUCT_ID(desktopApp/build.gradle.kts — store.properties productId)가
// 비었으면 지금처럼 AppLinks.updateDestination(WINDOWS)(= null → 단추 숨김).
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.desktop.generated.StoreIdentity

object StoreUpdateDestination {
    const val SCHEME_PREFIX = "ms-windows-store://pdp/?ProductId="
    private val PRODUCT_ID = Regex("^[0-9A-Z]{12}$")

    /** 제품 ID 하나 → Store 제품 페이지 주소. 비었거나 꼴이 틀리면 [fallback](기본 AppLinks — Windows 는 null = 단추 숨김). */
    fun of(productId: String, fallback: () -> String? = { AppLinks.updateDestination(ClientPlatform.WINDOWS) }): String? {
        val id = productId.trim()
        return if (PRODUCT_ID.matches(id)) SCHEME_PREFIX + id else fallback()
    }

    /** 이 빌드의 목적지(생성 상수). */
    val windows: String? get() = of(StoreIdentity.STORE_PRODUCT_ID)
}
