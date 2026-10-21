// 원본: Sources/CheckMobileShared/AingRoute.swift @ ios-1011(988609b) — E§4.6 딥링크
// Android 판 차이(E§6.1): 체스 신청 푸시를 처리하므로 체스 라우트(chess/lobby · chess/invite/<id> · chess/match[/<id>])를
// 오목과 같은 꼴로 더했다. iOS 는 아직 체스 신청 푸시가 없어 이 셋이 없다 — iOS 쪽 열거를 넓힐 때 같은 글자를 쓴다.
//
// 규칙(Swift 그대로)
// - 모르는 모양은 null 이다. 조용히 "지금" 탭으로 접지 않는다(푸시 페이로드가 틀렸다는 사실을 호출부가 알아야 한다).
// - `parse(route.url) == route` 가 모든 값에서 성립한다(AingRouteTest 가 못 박는다).
// - 경로에 실리는 id 는 영문·숫자·`-`·`_` 1~64자만 받는다(`..`·공백·퍼센트 인코딩된 제어 문자는 거절).
// - 미니게임 열거는 W2-e 의 미니게임 종류와 **같이** 넓힌다(한쪽만 넓히면 오배달 — Swift 머리말). 아래 `when` 에 else 를 두지 않는다.
//
// android.net.Uri 를 쓰지 않는다 — JVM 단위 시험이 그대로 닿게 순수 Kotlin 으로 푼다.
package com.yehsung.aingcheck.android.routing

/** 탭 다섯 개. 순서가 곧 탭 막대 순서다(AingTab.swift). */
enum class AingTab(val title: String) {
    NOW("지금"),
    MESSAGES("메시지"),
    RANKINGS("순위"),
    GAMES("게임"),
    ME("나"),
}

/** 폰 앱의 딥링크(`aingcheck://…`) ↔ 화면. 푸시·위젯·딥링크가 모두 이 값 하나로 화면을 연다. */
sealed interface AingRoute {
    data object Now : AingRoute
    data object Messages : AingRoute
    data class Message(val peerId: String) : AingRoute
    data class Rankings(val board: RankingsBoard) : AingRoute
    data object Games : AingRoute
    data class MiniGame(val game: AingMiniGame) : AingRoute
    data object GomokuLobby : AingRoute
    data class GomokuInvite(val matchId: String) : AingRoute
    /** null = 지금 진행 중인 판. */
    data class GomokuMatch(val matchId: String?) : AingRoute
    data object ChessLobby : AingRoute
    data class ChessInvite(val matchId: String) : AingRoute
    /** null = 지금 진행 중인 판. */
    data class ChessMatch(val matchId: String?) : AingRoute
    data object Me : AingRoute
    data object Shop : AingRoute
    /** null = 제보 목록. */
    data class Feedback(val reportId: String?) : AingRoute
    data object Settings : AingRoute

    /** 이 화면이 속한 탭. */
    val tab: AingTab
        get() = when (this) {
            Now -> AingTab.NOW
            Messages, is Message -> AingTab.MESSAGES
            is Rankings -> AingTab.RANKINGS
            Games, is MiniGame, GomokuLobby, is GomokuInvite, is GomokuMatch,
            ChessLobby, is ChessInvite, is ChessMatch -> AingTab.GAMES
            Me, Shop, is Feedback, Settings -> AingTab.ME
        }

    /** 정규 URL(`aingcheck://host/path`). */
    val url: String
        get() {
            val segments: List<String> = when (this) {
                Now -> listOf("now")
                Messages -> listOf("messages")
                is Message -> listOf("message", peerId)
                is Rankings -> listOf("rankings", board.raw)
                Games -> listOf("games")
                is MiniGame -> listOf("games", game.raw)
                GomokuLobby -> listOf("gomoku", "lobby")
                is GomokuInvite -> listOf("gomoku", "invite", matchId)
                is GomokuMatch -> listOf("gomoku", "match") + listOfNotNull(matchId)
                ChessLobby -> listOf("chess", "lobby")
                is ChessInvite -> listOf("chess", "invite", matchId)
                is ChessMatch -> listOf("chess", "match") + listOfNotNull(matchId)
                Me -> listOf("me")
                Shop -> listOf("me", "shop")
                is Feedback -> listOf("feedback") + listOfNotNull(reportId)
                Settings -> listOf("me", "settings")
            }
            val path = if (segments.size > 1) "/" + segments.drop(1).joinToString("/") else ""
            return "$SCHEME://${segments[0]}$path"
        }

    companion object {
        const val SCHEME = "aingcheck"

        /** `aingcheck://…` 문자열 → 값. 다른 스킴·모르는 모양이면 null. */
        fun parse(url: String): AingRoute? {
            val colon = url.indexOf(':')
            if (colon <= 0 || !url.substring(0, colon).equals(SCHEME, ignoreCase = true)) return null
            var rest = url.substring(colon + 1)
            // 질의·조각은 경로가 아니다(Swift URL.host/path 와 같게).
            rest = rest.substringBefore('#').substringBefore('?')
            val segments = mutableListOf<String>()
            if (rest.startsWith("//")) {
                val afterSlashes = rest.substring(2)
                val authority = afterSlashes.substringBefore('/')
                val host = hostOf(authority)?.let { percentDecode(it) } ?: return null
                if (host.isNotEmpty()) segments += host
                rest = afterSlashes.substring(authority.length)
            }
            val path = percentDecode(rest) ?: return null
            segments += path.split('/')
            return parseSegments(segments)
        }

        /** 데모·시험 표기(`messages/<peer>` · `games/gomoku/lobby` · `me/feedback`)도 같은 해석을 지난다. */
        fun parsePath(path: String): AingRoute? = parseSegments(path.split('/'))

        private fun parseSegments(raw: List<String>): AingRoute? {
            // Swift `.whitespaces` = 탭 + 유니코드 공백 구분자(Zs).
            val s = raw.map { seg -> seg.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() } }
                .filter { it.isNotEmpty() }.toMutableList()
            // 데모 표기 games/gomoku/… · games/chess/… 는 gomoku/… · chess/… 와 같다.
            if (s.size >= 2 && s[0].lowercase() == "games" && s[1].lowercase() in setOf("gomoku", "chess")) s.removeAt(0)
            val head = s.firstOrNull()?.lowercase() ?: return null
            val rest = s.drop(1)
            return when (head) {
                "now" -> if (rest.isEmpty()) Now else null
                "messages", "message" -> when (rest.size) {
                    0 -> if (head == "messages") Messages else null
                    1 -> safeId(rest[0])?.let { Message(it) }
                    else -> null
                }
                "rankings" -> when (rest.size) {
                    0 -> Rankings(RankingsBoard.LEAGUE)
                    1 -> RankingsBoard.fromRaw(rest[0])?.let { Rankings(it) }
                    else -> null
                }
                "games" -> when (rest.size) {
                    0 -> Games
                    1 -> AingMiniGame.fromRaw(rest[0])?.let { MiniGame(it) }
                    else -> null
                }
                "gomoku" -> boardGame(rest, lobby = GomokuLobby, invite = ::GomokuInvite, match = ::GomokuMatch)
                "chess" -> boardGame(rest, lobby = ChessLobby, invite = ::ChessInvite, match = ::ChessMatch)
                "me" -> when (rest.size) {
                    0 -> Me
                    1 -> when (rest[0].lowercase()) {
                        "shop" -> Shop
                        "settings" -> Settings
                        "feedback" -> Feedback(null)
                        else -> null
                    }
                    else -> null
                }
                "feedback" -> when (rest.size) {
                    0 -> Feedback(null)
                    1 -> safeId(rest[0])?.let { Feedback(it) }
                    else -> null
                }
                else -> null
            }
        }

        private fun boardGame(
            rest: List<String>,
            lobby: AingRoute,
            invite: (String) -> AingRoute,
            match: (String?) -> AingRoute,
        ): AingRoute? = when (rest.size) {
            0 -> lobby
            1 -> when (rest[0].lowercase()) {
                "lobby" -> lobby
                "match" -> match(null)
                else -> null
            }
            2 -> safeId(rest[1])?.let { id ->
                when (rest[0].lowercase()) {
                    "invite" -> invite(id)
                    "match" -> match(id)
                    else -> null
                }
            }
            else -> null
        }

        /** 경로의 id: 영문·숫자·`-`·`_`, 1~64자(Swift AingRoute.safeID — 다듬기·소문자화 없음). */
        fun safeId(raw: String): String? {
            if (raw.isEmpty() || raw.length > 64) return null
            return if (raw.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }) raw else null
        }

        /** userinfo·포트를 걷어 낸 호스트. 포트 자리가 숫자가 아니면 null(모양이 틀렸다). */
        private fun hostOf(authority: String): String? {
            val noUser = authority.substringAfterLast('@')
            val portAt = noUser.lastIndexOf(':')
            if (portAt < 0) return noUser
            val port = noUser.substring(portAt + 1)
            return if (port.all { it in '0'..'9' }) noUser.substring(0, portAt) else null
        }

        /** `%XX` 를 UTF-8 로 푼다(Swift `path(percentEncoded: false)`). 모양이 틀린 퍼센트면 null. */
        private fun percentDecode(text: String): String? {
            if ('%' !in text) return text
            val bytes = java.io.ByteArrayOutputStream()
            var i = 0
            while (i < text.length) {
                val c = text[i]
                if (c == '%') {
                    if (i + 2 >= text.length) return null
                    val hex = text.substring(i + 1, i + 3).toIntOrNull(16) ?: return null
                    bytes.write(hex)
                    i += 3
                } else {
                    bytes.write(c.toString().toByteArray(Charsets.UTF_8))
                    i++
                }
            }
            return bytes.toByteArray().toString(Charsets.UTF_8)
        }
    }
}

enum class RankingsBoard(val raw: String) {
    LEAGUE("league"),
    TOKENS("tokens"),
    MINIGAME("minigame");

    companion object {
        fun fromRaw(raw: String): RankingsBoard? = entries.firstOrNull { it.raw == raw.lowercase() }
    }
}

/**
 * 딥링크가 여는 미니게임(`aingcheck://games/<raw>`).
 * ⚠️ W2-e 의 미니게임 종류와 언제나 같이 넓힌다(AingRoute.swift 머리말 — 한쪽만 넓히면 모르는 값이 다른 게임으로 오배달).
 */
enum class AingMiniGame(val raw: String) {
    TIMING("timing"),
    FLAPPY("flappy"),
    TETRIS("tetris");

    companion object {
        fun fromRaw(raw: String): AingMiniGame? = entries.firstOrNull { it.raw == raw.lowercase() }
    }
}
