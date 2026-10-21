// §8-5 와 같은 길(E§6.6): Firebase 설정은 release 조립 지점에서만 들어온다. 시험이 도는 변형(debug·stub)의 생성 상수는 빈 값이다.
package com.yehsung.aingcheck.android.app

import com.yehsung.aingcheck.android.generated.ProdConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FirebaseConfigSourceTest {
    @Test
    fun testVariantsCarryNoFirebaseConfig() {
        assertEquals(
            listOf("", "", "", ""),
            listOf(ProdConfig.FIREBASE_APP_ID, ProdConfig.FIREBASE_PROJECT_ID, ProdConfig.FIREBASE_SENDER_ID, ProdConfig.FIREBASE_API_KEY),
        )
        assertNull(FirebaseConfigSource.settings())
    }
}
