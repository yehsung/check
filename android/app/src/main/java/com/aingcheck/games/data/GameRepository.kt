package com.aingcheck.games.data

import com.aingcheck.games.core.GameKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Serializes token rotation and mutations; a 401 may retry once, transport failures never do. */
class GameRepository(private val api: GameApi, private val vault: TokenStore) {
    private val lock = Mutex()
    @Volatile private var session: Session? = null
    val userId: String? get() = session?.userId
    suspend fun restore(): Boolean = lock.withLock {
        withContext(Dispatchers.IO) {
            val refresh = vault.read() ?: return@withContext false
            try {
                val restored = api.refresh(refresh)
                vault.save(restored.refresh); session = restored
                true
            } catch (error: ApiFailure) {
                if (error.status == 400 || error.status == 401) vault.clear()
                throw error
            }
        }
    }
    suspend fun signIn(email: String, password: String) = lock.withLock {
        withContext(Dispatchers.IO) {
            val next = api.signIn(email, password)
            vault.save(next.refresh); session = next
        }
    }
    suspend fun signOut() = lock.withLock {
        withContext(Dispatchers.IO) {
            val old = session
            vault.clear(); session = null
            if (old != null) runCatching { api.logout(old) }
            Unit
        }
    }
    suspend fun startRound(kind: GameKind): String = authenticated { session ->
        if (!api.isPublic(session)) throw ApiFailure(403, "순위 공개가 꺼져 있거나 확인되지 않았어요. 연습 게임을 이용해 주세요.")
        api.startRound(session, kind)
    }
    suspend fun submit(kind: GameKind, score: Int, token: String): Submission = authenticated {
        // Privacy can change on another client while a round is running.
        if (!api.isPublic(it)) throw ApiFailure(403, "순위 공개가 꺼져 있어 이번 기록은 제출하지 않았어요.")
        api.submit(it, kind, score, token)
    }
    suspend fun board(kind: GameKind): List<BoardEntry> = authenticated { api.board(it, kind) }
    private suspend fun <T> authenticated(action: (Session) -> T): T = lock.withLock {
        withContext(Dispatchers.IO) {
            val old = session ?: throw ApiFailure(401, "로그인이 필요해요.")
            try { action(old) } catch (error: ApiFailure) {
                if (error.status != 401) throw error
                val next = try { api.refresh(old.refresh) } catch (refreshError: ApiFailure) {
                    if (refreshError.status == 400 || refreshError.status == 401) { vault.clear(); session = null }
                    throw refreshError
                }
                vault.save(next.refresh); session = next
                action(next)
            }
        }
    }
}
