package com.aingcheck.games.core

/** ViewModel confines this to the main thread. Cancelling invalidates pending network callbacks. */
class RoundGate {
    private var generation = 0L
    private var kind: GameKind? = null
    private var token: String? = null
    fun begin(game: GameKind): Long {
        cancel()
        kind = game
        return generation
    }
    fun accept(request: Long, value: String): Boolean {
        if (request != generation || kind == null || value.isBlank()) return false
        token = value
        return true
    }
    fun consume(game: GameKind): String? {
        if (game != kind) return null
        return token.also { token = null }
    }
    fun cancel() { generation++; kind = null; token = null }
}
