// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (navigationDestination 표 — MeDestination 마다 화면 하나)
//
// 나 탭 하위 화면 → 내비 목적지. 라우트로 열 수 있는 셋(상점 · 설정 · 제보)은 셸의 라우트 계획(RoutePlans)과 **같은 목적지**여야 한다 —
// 딥링크로 연 화면과 나 탭 메뉴로 연 화면이 다른 목적지면 뒤로가기·복원이 갈린다. 「미션」은 아직 목적지가 없다(null — 조립이 더한다).
package com.yehsung.aingcheck.android.screens.me

import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.RoutePlans
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import org.junit.Assert.assertEquals
import org.junit.Test

class MeDestinationsTest {
    @Test
    fun routableDestinationsMatchTheShellRoutePlan() {
        assertEquals(RoutePlans.plan(AingRoute.Shop).top, MeDestinations.dest(MeDestination.Shop))
        assertEquals(RoutePlans.plan(AingRoute.Settings).top, MeDestinations.dest(MeDestination.Settings))
        assertEquals(RoutePlans.plan(AingRoute.Feedback(null)).top, MeDestinations.dest(MeDestination.Feedback))
    }

    @Test
    fun everyDestinationHasAPlace() {
        assertEquals(Dest.CharacterPicker, MeDestinations.dest(MeDestination.Characters))
        assertEquals(Dest.Profile, MeDestinations.dest(MeDestination.Profile))
        assertEquals(Dest.BlockedPeople, MeDestinations.dest(MeDestination.Blocked))
        assertEquals(Dest.GrassDetail("work"), MeDestinations.dest(MeDestination.Grass(MeGrassAxis.work)))
        assertEquals(Dest.GrassDetail("token"), MeDestinations.dest(MeDestination.Grass(MeGrassAxis.token)))
        // 7차 조립(K11): 미션 화면 목적지 — 나 탭 「미션」 줄이 여기로 간다(W4-c MissionsRoute).
        assertEquals(Dest.Missions, MeDestinations.dest(MeDestination.Missions))
    }

    /** 잔디 목적지 인자는 왕복한다(나 탭이 넣은 글자를 잔디 화면이 같은 축으로 푼다) · 모르는 글자는 근무로 연다. */
    @Test
    fun grassAxisArgRoundTripsAndFallsBackToWork() {
        for (axis in MeGrassAxis.entries) {
            val dest = MeDestinations.dest(MeDestination.Grass(axis)) as Dest.GrassDetail
            assertEquals(axis, GrassAxisArg.parse(dest.axis))
        }
        assertEquals(MeGrassAxis.work, GrassAxisArg.parse("calories"))
        assertEquals(MeGrassAxis.work, GrassAxisArg.parse(""))
    }
}
