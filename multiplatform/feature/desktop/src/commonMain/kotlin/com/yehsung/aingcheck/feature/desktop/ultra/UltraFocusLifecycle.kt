// 원본: Sources/check/WorkTimerStoreAuth.swift 75·120(로그인 지갑 sync) · Sources/check/WorkTimerStore.swift 3505-3517(랩 → missionCandidate)
//       · Sources/check/WorkTimerStorePoke.swift 394-453(폴링 박자 순서 P10) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason

/**
 * 울트라·집중이 생명주기 사건에서 할 일(조립 AppGraph 가 [DesktopSocialLifecycle] 셋 중 하나로 펼친다).
 *
 * - 로그인 → 지갑 SignIn(어제 몫 소급 — 이 호출이 없으면 그 루비는 영영 안 들어온다) + 서버 집중 값 GET.
 * - 랩 임계(근무 갈래가 랩당 1회만 부른다) → 지갑 MissionCandidate. 축하는 여기서 하지 않는다(받았는지는 서버 granted_now 가 말한다).
 * - 로그아웃 → 둘 다 비운다.
 * - 폴링 박자(W2-g2)는 [onPollBeat] 를 부른다 — 순서 P10: **서버 집중값 로드(받을 때까지) → 집중 만료 → 지갑 periodic**.
 *   로드는 로그인 GET 이 실패했을 때의 재시도 자리다(Swift localExpiryTick 이 매 tick loadTokenUsagePrivacyIfNeeded 를 await).
 *   받은 뒤·날아가는 중엔 요청 0건이다.
 */
class UltraFocusLifecycle(
    private val wallet: UltraWalletStore,
    private val focus: FocusModeController,
) : DesktopSocialLifecycle {
    override fun onSignedIn() {
        wallet.sync(UltraSyncReason.SignIn)
        focus.loadServerFocusMode()
    }

    override fun onSignedOut() {
        wallet.reset()
        focus.reset()
    }

    override fun onWorkStarted() {}

    override fun onUserStoppedWork(isTerminating: Boolean) {}

    override fun onLapCrossed(lap: Int) {
        if (lap >= 1) wallet.sync(UltraSyncReason.MissionCandidate)
    }

    override fun onTeamStatusApplied() {}

    override fun onWillSleep(at: SwiftDate) {}

    override fun onDidWake(at: SwiftDate) {}

    fun onPollBeat(now: SwiftDate) {
        focus.loadServerFocusMode()
        focus.evaluateFocusStageExpiry(now)
        wallet.sync(UltraSyncReason.Periodic)
    }
}
