// 원본: Sources/CheckMobileKit/Games/GamesChessText.swift:140-221(ChessPhoneText.BusyGame · busyTitle · busyHint · entryBlock · entryBlockHint ·
//       entryBlockNotice) · :763-766(objectParticle) @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

/**
 * 한 사람 한 판(B8) 입구 막힘 문구 — Swift `ChessPhoneText` 의 막힘 절을 [GamesBusyGame] 위에 옮긴 것.
 *
 * 왜 여기 있나: 그 표는 체스 문구 파일(W2-d `GamesChessText`)에 있지만 **세 게임 카드**(오목·체스·테트리스)가 같이 쓰고, 테트리스 카드
 * 판정(`GamesTetrisDuelCard` — W2-e)이 그 두 줄을 조립한다. 같은 웨이브의 W2-d 가 체스 표를 옮기면 그쪽 `entryBlock` 은 이 함수로 넘겨
 * 한 벌로 둔다(c-fold 후보 — 보고). 글자는 Swift 와 한 글자도 다르지 않다(`GamesBusyTextTest`).
 *
 * ★ **세 게임이다** — "반대쪽 게임"(이진 뒤집기)은 없다. 셋에서는 반대쪽이 하나로 정해지지 않아 오목을 두는 중에 막힌 테트리스 입구가
 *   "체스를 신청할 수 있어요" 라고 **틀린 안내**를 했다(그래도 시험은 초록이었다 — 둘만 있을 때 참이던 식이라서). 문구 함수가 **두는 판(playing)과
 *   막힌 입구(blocked)를 둘 다** 받는다.
 */
object GamesBusyText {
    /** 진행 중인 판을 가리키는 말("오목 판" · "체스 판" · "테트리스 대결"). 셋 다 받침으로 끝나므로 뒤에 "이" 를 붙인다. */
    fun matchNoun(game: GamesBusyGame): String = when (game) {
        GamesBusyGame.gomoku -> "오목 판"
        GamesBusyGame.chess -> "체스 판"
        GamesBusyGame.tetris -> "테트리스 대결"
    }

    /** 다른 판을 두는 중이라 입구가 막혔다 — "오목을 두는 중이에요" · "체스를 두는 중이에요" · "1:1 테트리스 대결 중이에요". */
    fun busyTitle(playing: GamesBusyGame): String = when (playing) {
        GamesBusyGame.gomoku, GamesBusyGame.chess -> "${playing.gameName}${objectParticle(playing.gameName)} 두는 중이에요"
        GamesBusyGame.tetris -> "${playing.gameName} 대결 중이에요"
    }

    /** 그 아래 한 줄 — 언제 풀리는지 말한다(막힌 이유만 말하면 사용자가 기다릴 끝을 모른다). [blocked] 가 **막힌 입구**다. */
    fun busyHint(playing: GamesBusyGame, blocked: GamesBusyGame): String {
        val name = blocked.gameName
        return "${matchNoun(playing)}이 끝나면 $name${objectParticle(name)} 신청할 수 있어요"
    }

    /** 1:1 입구(도전·수락)를 막는 사유 한 줄. 두는 판이 없으면 null 이다. */
    fun entryBlock(playing: GamesBusyGame?): String? = playing?.let(::busyTitle)

    /** 막힌 입구의 **둘째 줄**(언제 풀리는지). [entryBlock] 과 **짝으로** 쓴다. */
    fun entryBlockHint(playing: GamesBusyGame?, blocked: GamesBusyGame): String? = playing?.let { busyHint(it, blocked) }

    /** 막힌 입구에 세우는 안내 **한 칸 두 줄**(제목 + 언제 풀리는지). 줄바꿈까지 표가 쥔다(화면이 이으면 한 화면만 둘째 줄을 빠뜨린다). */
    fun entryBlockNotice(playing: GamesBusyGame?, blocked: GamesBusyGame): String? {
        if (playing == null) return null
        return busyTitle(playing) + "\n" + busyHint(playing, blocked)
    }

    /** 받침이 있으면 "을", 없으면(한글이 아니어도) "를". 마지막 UTF-16 단위로 본다 — 보조 평면 끝은 한글 밖이라 Swift 와 같은 "를". */
    fun objectParticle(word: String): String {
        if (word.isEmpty()) return "를"
        val scalar = word.last().code
        if (scalar !in 0xAC00..0xD7A3) return "를"
        return if ((scalar - 0xAC00) % 28 == 0) "를" else "을"
    }
}
