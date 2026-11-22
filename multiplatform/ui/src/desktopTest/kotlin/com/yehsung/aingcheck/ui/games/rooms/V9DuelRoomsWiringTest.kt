// 원본: Tests/CheckMobileKitTests/V1019DuelRoomsTests.swift(wiring · sixLobbies) @ 9774e23b — 판 9 1:1 대기방
package com.yehsung.aingcheck.ui.games.rooms

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/** 판 9 — 앱이 방 스토어를 붙이고 · 여섯 게임 스토어가 판을 받고 · 여섯 로비가 자기 게임으로 절을 세운다. 주석을 걷고 본다. */
class V9DuelRoomsWiringTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private fun code(rel: String) = SwiftStyleComments.strip(File(mp, rel).readText()).filter { !it.isWhitespace() }

    @Test
    fun appAttachesTheStoreAndSixGamesAdoptRoomMatches() {
        val app = code("feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone/app/PhoneAppModel.kt")
        assertTrue(app.contains("DuelRoomLiveService(context)"), "방 스토어가 실제 서버에 안 붙었다")
        assertTrue(app.contains("rooms.onRoomStarted=adoptRoomMatch") && app.contains("rooms.onJoined=adoptRoomMatch"))
        for (call in listOf("gomoku.adoptRoomMatch(matchID)", "chess.adoptRoomMatch(matchID)", "tetris.adoptRoomMatch(matchID)",
            "reversi?.adoptRoomMatch(matchID)", "crossyDuel?.adoptRoomMatch(matchID)", "alkkagi?.adoptRoomMatch(matchID)")) {
            assertTrue(app.contains(call), "$call 가 없다 — 방에서 선 판을 그 게임이 받지 않는다")
        }
        assertTrue(app.contains("rooms.rubyBalanceSource={ruby.rubyBalance}"))
        assertTrue(app.contains("realtime.duelRooms={rooms.handleGameSignal()}") && app.contains("context.duelRooms?.reset()"))
        val runner = code("feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone/realtime/PhoneRealtimeRunner.kt")
        assertTrue(runner.contains("if(isDuelRoomGameSignal(effect))duelRooms?.invoke()"))
        val games = code("feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone/app/PhoneGamesContext.kt")
        assertTrue(games.contains("overridevalduelRooms:com.yehsung.aingcheck.core.stores.rooms.DuelRoomStore?get()=phone.duelRooms"))
    }

    @Test
    fun sixLobbiesDrawTheSectionForTheirOwnGameOnlyWhenTheDoorIsOpen() {
        val g = "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/games"
        val lobbies = listOf(
            "$g/gomoku/GomokuLobby.kt" to "games.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.gomoku",
            "$g/chess/ChessScreen.kt" to "games.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.chess",
            "$g/tetris/GamesTetrisDuelScreen.kt" to "store.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.tetris",
            "$g/reversi/ReversiScreen.kt" to "games.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.reversi",
            "$g/crossy/GamesCrossyDuelScreen.kt" to "store.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.crossyDuel",
            "$g/alkkagi/GamesAlkkagiScreen.kt" to "store.context.duelRooms,com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame.alkkagi",
        )
        for ((file, args) in lobbies) assertTrue(code(file).contains("GamesDuelRoomsSection($args)"), "$file 에 대기방 절이 없다")
        val section = code("$g/rooms/GamesDuelRoomsSection.kt")
        assertTrue(section.contains("if(store.doorOpen!=true)return"), "문이 닫혀도 절이 선다")
        assertTrue(section.contains("while(isActive&&store.doorOpen==true){store.sleep(DuelRoomsRules.refreshSeconds)"), "문이 닫혀도 15초마다 묻는다")
        assertTrue(section.contains("store.join(room)") && section.contains("store.open(game,store.selectedStake)") && section.contains("store.closeMyRoom()"))
    }
}
