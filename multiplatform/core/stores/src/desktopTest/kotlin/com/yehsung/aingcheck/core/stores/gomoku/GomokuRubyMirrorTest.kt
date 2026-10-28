// 원본: 없음 — 조립 계약(W2-c `RubyBalanceMirror` × W2-d `SessionGomokuHost`). Swift 는 `MobileGomokuHost.rubyBalance` 한 칸을 오목·체스·나 탭이 같이 쓴다(Sources/CheckMobileKit/App/MobileContext.swift:127-147 @ 1b8260d).
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.me.MeHarness
import com.yehsung.aingcheck.core.stores.me.applyAchievementStatus
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

/**
 * 루비 칸은 **하나**다(6차 W2-d 검증 지적 — 병합 전에는 오목 호스트와 나 탭이 칸을 하나씩 들어 탭마다 잔액이 갈렸다).
 * 오목·체스 정산이 나 탭이 읽는 그 칸에 쓰고(쓰기 횟수가 오른다), 그래서 나 탭의 늦은 응답(정산 전의 서버 잔량)이 칸을 되돌리지 못한다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuRubyMirrorTest {
    @Test
    fun aDuelSettlementWritesTheCellTheMeTabReadsAndALateMeReplyCannotRewindIt() = runTest {
        val me = MeHarness(this) { null }
        me.signIn(HAND_ME)
        val host = SessionGomokuHost(me.context, ruby = me.context.ruby)
        assertSame(me.ruby, host.ruby, "조립이 나 탭과 다른 칸을 건넸다")
        val gomoku = GomokuStore(me.storeScope, host)
        gomoku.clock = { contractClock }
        val chess = ChessStore(me.storeScope, host)
        chess.clock = { contractClock }

        // 나 탭의 받기 조회가 떠났다(떠날 때의 쓰기 횟수를 찍는다) — 그 사이 오목 판이 끝나 서버가 정산했다.
        val departure = me.ruby.rubyWriteSerial
        gomoku.applyState(handPayload(JsonObject(handState(finished = true) + ("ruby_balance" to JsonPrimitive(95)))))
        assertEquals(95L, me.ruby.rubyBalance, "오목 정산이 나 탭의 칸에 닿지 않았다")
        assertEquals(departure + 1, me.ruby.rubyWriteSerial, "오목 정산이 나 탭의 쓰기 횟수를 올리지 않았다")

        // 늦게 온 나 탭 응답(정산 **전**의 서버 잔량 100)은 칸을 되돌리지 못한다.
        me.store.applyAchievementStatus(AchievementStatus.of(rubyBalance = 100), rubyWriteSerialAtDeparture = departure)
        assertEquals(95L, me.ruby.rubyBalance, "오목 정산 뒤에 도착한 나 탭의 옛 잔량이 칸을 되돌렸다")
        // 기준선: 떠난 뒤 다른 쓰기가 없으면 나 탭 응답이 칸을 쓴다(위 95 가 '아무것도 안 쓰는 나 탭'이라서가 아니다).
        me.store.applyAchievementStatus(AchievementStatus.of(rubyBalance = 100), rubyWriteSerialAtDeparture = me.ruby.rubyWriteSerial)
        assertEquals(100L, me.ruby.rubyBalance)

        // 체스 정산도 같은 칸이다(체스 호스트 = 오목 호스트).
        val chessState = fixtureJSON(CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
        val before = me.ruby.rubyWriteSerial
        chess.applyState(decodeJson(JsonObject((chessState - "state") + ("ruby_balance" to JsonPrimitive(80))), ChessStatePayload.serializer()))
        assertEquals(80L, me.ruby.rubyBalance, "체스 정산이 나 탭의 칸에 닿지 않았다")
        assertEquals(before + 1, me.ruby.rubyWriteSerial)

        // 나 탭(상점·뽑기)이 쓴 잔액을 게임 호스트가 그대로 본다 — [도전] 판돈 단추의 '걸 수 있나'가 같은 수를 읽는다.
        me.ruby.rubyBalance = 40
        assertEquals(40L, host.rubyBalance)
    }
}
