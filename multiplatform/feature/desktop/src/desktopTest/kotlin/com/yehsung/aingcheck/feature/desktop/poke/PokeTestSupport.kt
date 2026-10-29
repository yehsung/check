// W2-g2 찌르기 시험 바탕 — 합성 픽스처만(실제 홈·계정·로그 없음). 서버는 testkit MockRouter(모르는 요청은 실패).
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.socialapi.ConsumedRowsSink
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.socialapi.RealtimeSubscription
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPokeSink
import com.yehsung.aingcheck.testkit.mock.MockRouter
import io.ktor.client.HttpClient

internal const val NOW_EPOCH: Long = 1_790_000_000
internal val T0: SwiftDate = SwiftDate(NOW_EPOCH.toDouble())

internal fun pokeService(router: MockRouter, clock: () -> SwiftDate = { T0 }): SupabaseWorkService =
    SupabaseWorkService(
        "https://golden.invalid", "k", HttpClient(router.engine) { SupabaseWorkService.clientConfig(this) }, clock, RulesWireTextRules,
    ) { "ABCDEF12-0000-4000-8000-000000000000" }

internal class FakeSessionHost(override val service: SupabaseWorkService) : SessionHost {
    var current: SupabaseSession? = SupabaseSession("token-1", "refresh-1", "me")
    var generation: Int = 1
    override val session: SupabaseSession? get() = current
    override val sessionGeneration: Int get() = generation
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T =
        operation(current ?: throw IllegalStateException("세션 없음"))
}

internal class FakeSubscription(var subscribed: Boolean = false) : RealtimeSubscription {
    var debtCleared = 0
    override val isSubscribed: Boolean get() = subscribed
    override fun clearCatchUpDebt() {
        debtCleared++
    }
}

internal class RecordingPokeSink : ReceivedPokeSink {
    val batches = mutableListOf<List<ReceivedPoke>>()
    override fun onPokesReceived(batch: List<ReceivedPoke>) {
        batches += batch
    }
}

internal class RecordingRowsSink : ConsumedRowsSink {
    val inserted = mutableListOf<List<TakenPokeRow>>()
    val messages = mutableListOf<List<TakenPokeRow>>()
    override fun insertConsumedPokes(rows: List<TakenPokeRow>): Int {
        inserted += rows
        return 0
    }
    override fun receiveConsumedMessages(rows: List<TakenPokeRow>, now: SwiftDate) {
        messages += rows
    }
}

internal fun row(id: String, age: Long, kind: String?, body: String? = null, from: String = "peer-1"): TakenPokeRow =
    TakenPokeRow(id = id, fromUser = from, fromDisplayName = "보낸이", createdEpoch = NOW_EPOCH - age, kind = kind, body = body)

/** 흡수 세션 기본값 = 셋 다 섬(남의 맥은 세션을 주장하지 않고, 이 기기는 700초 전에 입력). */
internal fun facts(
    local: Boolean = true,
    adopted: Boolean = true,
    canonical: String? = "s-1",
    ownOpen: String? = "s-1",
    claims: List<Pair<String, String?>>? = listOf("mac:other" to null, "win:me" to "s-1"),
    device: String? = "win:me",
    inputAgo: Double? = 700.0,
    now: SwiftDate = T0,
): PokeConsumeFacts = PokeConsumeFacts(local, adopted, canonical, ownOpen, claims, device, inputAgo?.let { now.addingTimeInterval(-it) })
