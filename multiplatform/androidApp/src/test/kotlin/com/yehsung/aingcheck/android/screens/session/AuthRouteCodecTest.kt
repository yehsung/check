// 원본: Sources/CheckMobileKit/Session/MobileAuthRoute.swift @ 3bd04bd (로그인 아래 화면 경로)
package com.yehsung.aingcheck.android.screens.session

import com.yehsung.aingcheck.core.session.AuthRoute
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthRouteCodecTest {
    @Test
    fun routesRoundTrip() {
        for (route in listOf(AuthRoute.SignUp(false), AuthRoute.SignUp(true), AuthRoute.SignUpConfirm("me@x.invalid"), AuthRoute.PasswordReset)) {
            assertEquals(route, AuthRouteCodec.decode(AuthRouteCodec.encode(route)))
        }
    }

    @Test
    fun resetCarriesTypedEmail() {
        val raw = AuthRouteCodec.resetWith("typed@x.invalid")
        assertEquals(AuthRoute.PasswordReset, AuthRouteCodec.decode(raw))
        assertEquals("typed@x.invalid", AuthRouteCodec.resetEmail(raw))
        assertNull(AuthRouteCodec.resetEmail("signup"))
        assertNull(AuthRouteCodec.decode("tabs"))
    }
}
