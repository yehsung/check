// 원본: Sources/CheckCore/DuelRooms.swift(DuelRoomStore · DuelRoomLiveService) · DuelRoomAdoption.swift @ main 341eb4e3 — 판 9 1:1 대기방
//       · Sources/CheckMobileKit/Games/GamesDuelRooms.swift(GamesDuelRoomsRules) @ 9774e23b
//
// 이 스토어가 지키는 것(맥 · 아이폰과 같다):
//  ① 방장 기기는 방이 열려 있는 동안 화면과 상관없이 숨(duel_room_ping)을 쉰다(20초 · 게임 초인종이 오면 바로 · 1초에 한 번).
//  ② 숨이 '시작됨 + 판 id' 를 돌려주면 그 방마다 **한 번** onRoomStarted — 앱이 그 판을 그 게임 스토어로 받아 원래 길로 판 화면을 연다.
//     참가자는 join 이 ok 면 onJoined.
//  ③ 응답 상태는 모르는 값이 와도 죽지 않는다. 문이 닫혀 있으면(unsupported_client) 방 칸을 감춘다.
package com.yehsung.aingcheck.core.stores.rooms

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.wire.rooms.DuelRoom
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomCall
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomStatus
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomText
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomsResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** 방 RPC 한 번(시험이 바꿔 낀다). */
fun interface DuelRoomServing {
    suspend fun call(call: DuelRoomCall): DuelRoomsResponse
}

/** 실제 서버 — 1:1 대결 RPC 공용 몸통(duelRPC)으로 부른다. 세션이 바뀌면 결과를 버린다. */
class DuelRoomLiveService(private val context: SessionContext) : DuelRoomServing {
    override suspend fun call(call: DuelRoomCall): DuelRoomsResponse {
        val userID = context.sessionStore.userID ?: throw kotlinx.coroutines.CancellationException("로그인 전")
        val generation = context.generation
        val service = context.service
        val body = service.encode(com.yehsung.aingcheck.core.wire.rooms.DuelRoomBody.serializer(), call.body)
        val response = context.withSessionRetry { session ->
            if (context.generation != generation || session.userID != userID) throw kotlinx.coroutines.CancellationException("세션이 바뀌었다")
            service.duelRPC(call.rpcName, body, session.accessToken, DuelRoomsResponse.serializer())
        }
        if (context.generation != generation || context.sessionStore.userID != userID) throw kotlinx.coroutines.CancellationException("세션이 바뀌었다")
        return response
    }
}

/** 대기방 절의 순수 판정(시험이 값으로 잰다 — 아이폰 GamesDuelRoomsRules). */
object DuelRoomsRules {
    /** 목록을 다시 읽는 주기(초) — 맥 DuelRoomsTab 과 같은 15초. */
    const val refreshSeconds = 15.0
    /** 이 방에 들어갈 루비가 있는가(잔액을 모르면 막지 않는다 — 서버가 다시 잰다). */
    fun affordable(stake: Long, balance: Long?): Boolean = (balance ?: Long.MAX_VALUE) >= stake
    /** [참가]를 누를 수 있는가: 루비 · 걸린 일 없음 · 이 게임에 내 방이 열려 있지 않음. */
    fun canJoin(room: DuelRoom, store: DuelRoomStore, game: DuelRoomGame): Boolean =
        affordable(room.stake, store.rubyBalance) && !store.isBusy && store.myOpenRoom(game) == null
}

class DuelRoomStore(
    parentScope: CoroutineScope,
    private var service: DuelRoomServing? = null,
    /** 1970 기준 밀리초(벽시계). */
    private val clockMs: () -> Double,
    private val pingSeconds: Double = PING_SECONDS,
    /** 기다리기(가상 시간 위에서 도는 delay). */
    var sleep: suspend (Double) -> Unit = { seconds -> delay((seconds * 1000).toLong()) },
) {
    companion object {
        /** 방장 숨 간격(서버는 75초 안 본 방을 목록에서 뺀다). */
        const val PING_SECONDS = 20.0
    }

    private val work = SupervisorJob(parentScope.coroutineContext[Job])
    private val scope = CoroutineScope(parentScope.coroutineContext + work)

    var rooms: Map<DuelRoomGame, List<DuelRoom>> by mutableStateOf(emptyMap())
        private set
    var loadedGames: Set<DuelRoomGame> by mutableStateOf(emptySet())
        private set
    /** 내 방(열림 · 막 시작). */
    var myRoom: DuelRoom? by mutableStateOf(null)
        private set
    /** 문(서버 duel__capable). null = 아직 모름. 거짓이면 방 칸을 감춘다. */
    var doorOpen: Boolean? by mutableStateOf(null)
        private set
    var stakes: List<Long> by mutableStateOf(listOf(3L, 5L, 10L))
        private set
    var isBusy: Boolean by mutableStateOf(false)
        private set
    var notice: String? by mutableStateOf(null)
    var selectedStake: Long by mutableStateOf(5L)
    /** 화면이 그리는 시각(대기 시간 줄) — 목록을 다시 읽을 때마다 바뀐다. */
    var tickMs: Double by mutableStateOf(0.0)
        private set

    /** 루비 잔액(앱 미러). [참가] · 판돈 버튼을 미리 막는 데만 쓴다(서버가 다시 잰다). */
    var rubyBalanceSource: (() -> Long?)? = null
    val rubyBalance: Long? get() = rubyBalanceSource?.invoke()

    /** 방장 기기 — 내 방에 사람이 들어와 판이 섰다(방마다 한 번). */
    var onRoomStarted: ((DuelRoomGame, String) -> Unit)? = null
    /** 참가자 — 참가 ok(그 게임 판 id). */
    var onJoined: ((DuelRoomGame, String) -> Unit)? = null

    private var serverOffsetMs = 0.0
    private val handledStarts = HashSet<String>()
    private var pingTask: Job? = null
    private var generation = 0
    private var lastSignalPingAt = Double.NEGATIVE_INFINITY

    val isAvailable: Boolean get() = service != null && doorOpen == true
    val serverNowMs: Double get() = clockMs() + serverOffsetMs

    fun rooms(game: DuelRoomGame): List<DuelRoom> = rooms[game] ?: emptyList()
    fun myOpenRoom(game: DuelRoomGame): DuelRoom? = myRoom?.takeIf { it.isOpen && it.game == game }
    /** 다른 게임에 열어 둔 내 방(이 게임 로비에 한 줄로 알린다). */
    fun myOpenRoomOtherThan(game: DuelRoomGame): DuelRoom? = myRoom?.takeIf { it.isOpen && it.game != null && it.game != game }
    fun waitedSeconds(room: DuelRoom): Long = maxOf(0L, ((serverNowMs - room.createdMs) / 1000).toLong())

    // ---------------------------------------------------------------- 부르기

    suspend fun refresh(game: DuelRoomGame) {
        val response = perform(DuelRoomCall.list(game)) ?: return
        if (response.status != DuelRoomStatus.ok) return
        rooms = rooms + (game to (response.rooms ?: emptyList()))
        loadedGames = loadedGames + game
        response.stakes?.takeIf { it.isNotEmpty() }?.let { stakes = it }
        tickMs = serverNowMs
        applyMyRoom(response.myRoom)
    }

    suspend fun open(game: DuelRoomGame, stake: Long) {
        if (isBusy) return
        isBusy = true
        try {
            val response = perform(DuelRoomCall.open(game, stake)) ?: return
            if (response.status != DuelRoomStatus.ok) {
                notice = DuelRoomText.notice(response.status, response.need ?: stake)
                return
            }
            notice = null
            selectedStake = stake
            applyMyRoom(response.myRoom)
        } finally {
            isBusy = false
        }
    }

    suspend fun closeMyRoom() {
        val room = myRoom ?: return
        if (!room.isOpen || isBusy) return
        isBusy = true
        var refreshGame: DuelRoomGame? = null
        try {
            val response = perform(DuelRoomCall.close(room.id)) ?: return
            if (response.status == DuelRoomStatus.ok || response.status == DuelRoomStatus.notFound) {
                applyMyRoom(response.myRoom)
                refreshGame = room.game
            }
        } finally {
            isBusy = false
        }
        refreshGame?.let { refresh(it) }
    }

    suspend fun join(room: DuelRoom) {
        val game = room.game ?: return
        if (isBusy) return
        isBusy = true
        val response = try {
            perform(DuelRoomCall.join(room.id))
        } finally {
            isBusy = false
        } ?: return
        val matchID = response.matchID
        if (response.status == DuelRoomStatus.ok && !matchID.isNullOrEmpty()) {
            notice = null
            rooms = rooms + (game to rooms(game).filter { it.id != room.id })
            onJoined?.invoke(game, matchID.lowercase())
            return
        }
        notice = DuelRoomText.notice(response.status, response.need ?: room.stake)
        if (response.status == DuelRoomStatus.roomGone || response.status == DuelRoomStatus.hostBusy) {
            rooms = rooms + (game to rooms(game).filter { it.id != room.id })
        }
        refresh(game)
    }

    suspend fun ping() {
        val response = perform(DuelRoomCall.ping) ?: return
        if (response.status != DuelRoomStatus.ok) return
        applyMyRoom(response.myRoom)
    }

    /** 게임 초인종이 왔다 — 내 방이 열려 있으면 바로 숨을 쉰다(방에 사람이 들어온 신호일 수 있다). 1초에 한 번. */
    fun handleGameSignal() {
        if (myRoom?.isOpen != true) return
        val now = clockMs()
        if (now - lastSignalPingAt < 1000) return
        lastSignalPingAt = now
        scope.launch { ping() }
    }

    fun attach(service: DuelRoomServing) {
        reset()
        this.service = service
    }

    /** 로그아웃 · 계정 바뀜(서비스 배선은 그대로). */
    fun reset() {
        generation += 1
        pingTask?.cancel()
        pingTask = null
        rooms = emptyMap()
        loadedGames = emptySet()
        myRoom = null
        doorOpen = null
        notice = null
        isBusy = false
        handledStarts.clear()
    }

    // ---------------------------------------------------------------- 안쪽

    private fun applyMyRoom(room: DuelRoom?) {
        myRoom = room
        val game = room?.game
        val matchID = room?.matchID
        if (room != null && room.isStarted && game != null && matchID != null && handledStarts.add(room.id)) {
            onRoomStarted?.invoke(game, matchID.lowercase())
        }
        updatePing()
    }

    private fun updatePing() {
        if (myRoom?.isOpen != true) {
            pingTask?.cancel()
            pingTask = null
            return
        }
        if (pingTask != null) return
        val gen = generation
        pingTask = scope.launch {
            while (isActive) {
                sleep(pingSeconds)
                if (gen != generation) return@launch
                if (myRoom?.isOpen != true) {
                    pingTask = null
                    return@launch
                }
                ping()
            }
        }
    }

    private suspend fun perform(call: DuelRoomCall): DuelRoomsResponse? {
        val service = service ?: return null
        val gen = generation
        val sentMs = clockMs()
        return try {
            val response = service.call(call)
            if (gen != generation) return null
            val now = response.serverNowMs
            if (now != null && now.isFinite() && now > 0) serverOffsetMs = now - (sentMs + clockMs()) / 2
            when (response.status) {
                DuelRoomStatus.unsupportedClient -> doorOpen = false
                DuelRoomStatus.ok -> doorOpen = true
                else -> Unit
            }
            response
        } catch (e: Throwable) {
            if (gen != generation || AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return null
            notice = DuelRoomText.notice(DuelRoomStatus.unknown)
            null
        }
    }
}
