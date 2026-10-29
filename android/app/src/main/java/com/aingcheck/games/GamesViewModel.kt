package com.aingcheck.games

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.aingcheck.games.core.*
import com.aingcheck.games.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.security.SecureRandom

data class GamesUi(
    val signedIn: Boolean = false,
    val authBusy: Boolean = false,
    val preparing: Boolean = false,
    val submitting: Boolean = false,
    val selected: GameKind? = null,
    val ranked: Boolean = false,
    val game: Game? = null,
    val frame: Long = 0,
    val notice: String? = null,
    val boardKind: GameKind? = null,
    val board: List<BoardEntry> = emptyList(),
    val boardBusy: Boolean = false,
    val boardError: String? = null,
    val localBest: Map<GameKind, Int> = emptyMap()
)

class GamesViewModel(app: Application) : AndroidViewModel(app) {
    val configured = BuildConfig.SUPABASE_ANON_KEY.isNotBlank()
    private val repo = GameRepository(GameApi(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY), SessionVault(app))
    private val bestPrefs = app.getSharedPreferences("practice-best", Application.MODE_PRIVATE)
    private val mutable = MutableStateFlow(GamesUi(localBest = GameKind.entries.associateWith { bestPrefs.getInt(it.wire, 0) }))
    val ui = mutable.asStateFlow()
    private val roundGate = RoundGate()
    private val random = SecureRandom()
    private var generation = 0L
    private var authGeneration = 0L
    private var boardGeneration = 0L
    private var startJob: Job? = null
    private var finishedHandled = false

    init {
        if (configured) viewModelScope.launch {
            val request = authGeneration
            mutable.value = mutable.value.copy(authBusy = true)
            try {
                val restored = repo.restore()
                if (request == authGeneration) mutable.value = mutable.value.copy(signedIn = restored)
            } catch (error: Exception) {
                if (request == authGeneration) mutable.value = mutable.value.copy(notice = message(error))
            } finally {
                if (request == authGeneration) mutable.value = mutable.value.copy(authBusy = false)
            }
        }
    }
    fun signIn(email: String, password: String) {
        if (!configured || mutable.value.authBusy) return
        val request = ++authGeneration
        mutable.value = mutable.value.copy(authBusy = true, notice = null)
        viewModelScope.launch {
            try {
                repo.signIn(email, password)
                if (request == authGeneration) mutable.value = mutable.value.copy(signedIn = true, notice = "계정을 연결했어요. 순위 게임에 참여할 수 있어요.")
            } catch (error: Exception) {
                if (request == authGeneration) mutable.value = mutable.value.copy(notice = message(error))
            } finally {
                if (request == authGeneration) mutable.value = mutable.value.copy(authBusy = false)
            }
        }
    }
    fun signOut() {
        if (mutable.value.authBusy || mutable.value.submitting) return
        leaveGame()
        ++authGeneration; ++boardGeneration
        mutable.value = mutable.value.copy(signedIn = false, authBusy = true, boardKind = null, board = emptyList(), notice = null)
        viewModelScope.launch {
            try { repo.signOut() } finally { mutable.value = mutable.value.copy(authBusy = false) }
        }
    }
    fun start(kind: GameKind, ranked: Boolean) {
        if (mutable.value.preparing || mutable.value.submitting || (ranked && !mutable.value.signedIn)) return
        startJob?.cancel()
        val request = ++generation
        val round = roundGate.begin(kind)
        finishedHandled = false
        mutable.value = mutable.value.copy(selected = kind, ranked = ranked, preparing = ranked, game = null, notice = null, boardKind = null)
        if (!ranked) { launchGame(kind); return }
        startJob = viewModelScope.launch {
            try {
                val token = repo.startRound(kind)
                if (request != generation || !roundGate.accept(round, token)) return@launch
                launchGame(kind)
            } catch (error: Exception) {
                if (request == generation) {
                    roundGate.cancel()
                    mutable.value = mutable.value.copy(preparing = false, selected = null, notice = message(error), signedIn = repo.userId != null)
                }
            }
        }
    }
    private fun launchGame(kind: GameKind) {
        val game: Game = when (kind) {
            GameKind.TIMING -> TimingGame(random.nextLong())
            GameKind.FLAPPY -> FlappyGame(random.nextLong())
        }
        game.tap()
        mutable.value = mutable.value.copy(preparing = false, game = game, frame = 0)
    }
    fun tap() {
        val current = mutable.value.game ?: return
        if (current.finished) return
        current.tap()
        mutable.value = mutable.value.copy(frame = mutable.value.frame + 1)
    }
    fun step(seconds: Double) {
        val current = mutable.value.game ?: return
        if (!current.playing) return
        current.step(seconds)
        mutable.value = mutable.value.copy(frame = mutable.value.frame + 1)
        if (current.finished && !finishedHandled) finish(current.score)
    }
    private fun finish(score: Int) {
        finishedHandled = true
        val state = mutable.value
        val kind = state.selected ?: return
        val best = maxOf(state.localBest[kind] ?: 0, score)
        bestPrefs.edit().putInt(kind.wire, best).apply()
        mutable.value = state.copy(localBest = state.localBest + (kind to best))
        if (!state.ranked) { mutable.value = mutable.value.copy(notice = "연습 기록이에요. 순위에는 반영되지 않아요."); return }
        val token = roundGate.consume(kind) ?: return
        val request = generation
        mutable.value = mutable.value.copy(submitting = true, notice = "기록을 보내고 있어요…")
        viewModelScope.launch {
            try {
                val result = repo.submit(kind, score, token)
                if (request == generation) {
                    val notice = when (result.status) {
                        "ok" -> if (result.improved) "오늘 최고 기록! ${result.bestScore ?: score}점" else "기록 반영 완료 · 오늘 최고 ${result.bestScore ?: score}점"
                        "token_used" -> "이미 처리된 판이에요. 오늘 순위에서 기록을 확인해 주세요."
                        "token_expired", "no_token" -> "이번 판의 유효 시간이 지나 기록을 반영하지 못했어요."
                        "too_fast" -> "서버 검증을 통과하지 못해 기록을 반영하지 못했어요."
                        else -> "기록을 반영하지 못했어요. 다음 판에서 다시 시도해 주세요."
                    }
                    mutable.value = mutable.value.copy(notice = notice)
                }
            } catch (error: Exception) {
                if (request == generation) mutable.value = mutable.value.copy(notice = "기록 반영을 확인하지 못했어요. 오늘 순위에서 확인해 주세요.", signedIn = repo.userId != null)
            } finally {
                if (request == generation) mutable.value = mutable.value.copy(submitting = false)
            }
        }
    }
    fun leaveGame(background: Boolean = false) {
        // Finished submissions retain their generation so a response is not lost on backgrounding.
        if (background && mutable.value.game?.finished == true) return
        if (mutable.value.submitting) return
        val hadRound = mutable.value.preparing || mutable.value.game?.playing == true
        ++generation
        startJob?.cancel(); roundGate.cancel()
        mutable.value = mutable.value.copy(selected = null, game = null, preparing = false, notice =
            if (background && hadRound) "앱을 벗어나 진행 중인 판을 종료했어요. 점수는 제출하지 않았어요." else null)
    }
    fun loadBoard(kind: GameKind) {
        if (!mutable.value.signedIn || mutable.value.submitting) return
        val request = ++boardGeneration
        val account = authGeneration
        mutable.value = mutable.value.copy(boardKind = kind, board = emptyList(), boardBusy = true, boardError = null)
        viewModelScope.launch {
            try {
                val board = repo.board(kind)
                if (request == boardGeneration && account == authGeneration) mutable.value = mutable.value.copy(board = board)
            } catch (error: Exception) {
                if (request == boardGeneration && account == authGeneration) mutable.value = mutable.value.copy(boardError = message(error), signedIn = repo.userId != null)
            } finally {
                if (request == boardGeneration && account == authGeneration) mutable.value = mutable.value.copy(boardBusy = false)
            }
        }
    }
    fun closeBoard() { ++boardGeneration; mutable.value = mutable.value.copy(boardKind = null, boardBusy = false) }
    private fun message(error: Exception): String {
        if (error is CancellationException) throw error
        return if (error is ApiFailure) error.message ?: "연결을 확인해 주세요." else "연결을 확인하고 다시 시도해 주세요."
    }
}
