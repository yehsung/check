// W2-g2 take_pokes 소비 게이트 — Swift Sources/check/WorkTimerStorePoke.swift 539-575(takePokesIfWorking · adoptedSessionMayConsumePokes)
// · WorkTimerStoreRealtime.swift 205-215(.drain 이 같은 판정을 부른다). 판정은 이 한 벌 — 폴링(W2-g2)·.drain/따라잡기(W2-g3)가 같은 함수를 부른다.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource

/**
 * ★ P4: take_pokes 로 가는 문은 하나 — `localSessionOpen && (!adopted || adoptedMayConsume)`. `isWorking` 이 아니다(Swift startedAt != nil).
 * Windows 기본(조정 ⑤ · W-3 #17): [DesktopAppConfig.adoptedPokeConsume] = false 면 흡수 가지는 **언제나 거짓**이다 — 깃발 꺼진 Windows 가
 * 흡수 세션에서 소비하면 맥 입력 덕에 서버가 받아 준 찌르기를 훔친다. 값([PokeConsumeFacts])은 근무 갈래가 정규화를 끝내 내고 여기서는 다시 정규화하지 않는다.
 */
class DesktopPokeConsumeGate(
    private val facts: PokeFactsSource,
    private val config: DesktopAppConfig = DesktopAppConfig(),
) : PokeConsumeGate {
    override fun mayConsume(now: SwiftDate): Boolean = decide(facts.pokeConsumeFacts(), now, config.adoptedPokeConsume)

    companion object {
        /** P4 문. 흡수 세션이 아니면 로컬 세션만 본다. */
        fun decide(facts: PokeConsumeFacts, now: SwiftDate, adoptedConsumeEnabled: Boolean): Boolean {
            if (!facts.localSessionOpen) return false
            if (!facts.adoptedRemoteSession) return true
            return adoptedConsumeEnabled && adoptedSessionMayConsume(facts, now)
        }

        /**
         * P5 Swift `adoptedSessionMayConsumePokes` — 셋이 모두 서야 한다(하나라도 모르면 받지 않는다):
         *  1. 기기 주장을 **읽었다**(null·빈 = 판정 불가) · 서버가 연 행의 세션이 지금 흡수한 그 세션이다.
         *  2. **남의 기기**가 이 세션을 주장하지 않는다(빈 deviceID 주장은 세지 않는다). 이 기기 id 가 null 이면 흡수 소비 금지.
         *  3. 이 기기 입력이 900초 안이다(서버 600초보다 넓다 — 서버가 받아 준 찌르기를 놓치지 않는다).
         */
        fun adoptedSessionMayConsume(facts: PokeConsumeFacts, now: SwiftDate): Boolean {
            if (!facts.adoptedRemoteSession || !facts.localSessionOpen) return false
            val sessionID = facts.canonicalSessionID ?: return false
            if (facts.ownOpenSessionID != sessionID) return false
            val claims = facts.ownDeviceClaims
            if (claims.isNullOrEmpty()) return false
            val me = facts.deviceID ?: return false
            val anotherDeviceClaimsIt = claims.any { (deviceID, claimedSession) ->
                deviceID.isNotEmpty() && deviceID != me && claimedSession == sessionID
            }
            if (anotherDeviceClaimsIt) return false
            val input = facts.lastMeaningfulInputAt ?: return false
            return now.timeIntervalSince(input) <= DesktopPokeRules.ADOPTED_CONSUMER_INPUT_WINDOW_SECONDS
        }
    }
}
