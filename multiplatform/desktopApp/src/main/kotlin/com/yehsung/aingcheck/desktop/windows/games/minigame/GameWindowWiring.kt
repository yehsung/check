// 원본: Sources/check/CheckApp.swift:344-440(presentWindow · dismissWindow · requestAttention · onInviteArrived · onAttention · spectatorFeaturesEnabled)
//       (W4-e — ★ 맥 주석 "전부 빠져도 컴파일·시험은 초록"(옵셔널 문) → 배선은 이 한 곳, 계약은 WindowWiringContractTest 가 잰다)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig

/**
 * 판 게임 스토어 셋의 창 문 다섯을 Windows 창 호스트에 잇는다. 조립 지점(AppGraph — 조정자 C3)이 로그인 뒤 한 번 부른다.
 *
 * - presentWindow → 그 창을 (지연 생성해) 앞으로 · dismissWindow → 앱이 닫는다(reset — 로그아웃한 뒤 앞 계정의 판이 떠 있으면 안 된다)
 * - requestAttention → 앱이 뒤면 작업 표시줄 깜빡임(FlashWindowEx — 창이 없으면 아무 일도 없다)
 * - onInviteArrived → [onInvite](알림 중재는 W3-c1). **대결 깃발이 꺼진 빌드는 부르지 않는다**(W-3 #7 — 스토어도 잠긴 빌드에서 안 부르지만 여기서 한 번 더 막는다)
 * - onAttention → [onTurnWhileHidden](창이 안 보이는 동안 내 차례)
 * - spectatorFeaturesEnabled ← [DesktopAppConfig.spectator](W-3 #4 — Windows 는 켠다)
 * - 테트리스 대결 rankingEnabled = true(CheckApp.swift:409 ① 순위의 **주 스위치** — 스토어는 폰과 공용이라 기본 꺼짐, 없으면 순위 탭은 영영 로딩.
 *   맥 :430 · 폰 PhoneAppModel 도 무조건 켠다. 관전 스위치와 **따로** 둔다 — 순위 없이 관전만 여는 날이 온다)
 */
/**
 * 대결 신청 한 건의 구조 정보(id·만료) — 오버레이 말풍선(overlay.onDuelInvite)이 받는다. 맥 CheckApp.swift:380-387 onInviteArrived 가
 * 구조 신청을 오버레이로 먼저 넘기고 글 알림은 그 뒤다 — 오버레이가 같은 글을 '이미 받은 신청'으로 묶어 대체 말풍선을 하나 더 세우지 않게.
 */
typealias DuelInviteArrival = (game: DuelGame, id: String, peerName: String, stake: Int, expiresAt: SwiftDate) -> Unit

object GameWindowWiring {
    fun wire(
        gomoku: GomokuStore,
        chess: ChessStore,
        tetris: TetrisDuelStore,
        windows: GamesWindowsHost,
        config: DesktopAppConfig,
        onInvite: (GameWindowKind) -> Unit = {},
        onTurnWhileHidden: (GameWindowKind) -> Unit = {},
        onInviteNotice: (DuelInviteNotice) -> Unit = {},
        /** 구조 신청(오버레이 몫) — **onInviteNotice 보다 먼저** 부른다(짝짓기 열쇠: 셸 글이 먼저 오면 대체 말풍선이 하나 더 뜬다). */
        onInviteArrival: DuelInviteArrival = { _, _, _, _, _ -> },
    ) {
        val duels = config.toAppConfig().duelsEnabled

        gomoku.presentWindow = { windows.present(GameWindowKind.Gomoku) }
        gomoku.dismissWindow = { windows.dismiss(GameWindowKind.Gomoku) }
        gomoku.requestAttention = { windows.requestAttention(GameWindowKind.Gomoku) }
        gomoku.onInviteArrived = { invite ->
            if (duels) {
                onInvite(GameWindowKind.Gomoku)
                onInviteArrival(DuelGame.GOMOKU, invite.id, invite.peer.displayName, invite.stake.toInt(), invite.expiresAt)
                onInviteNotice(DuelInviteNotice(GameWindowKind.Gomoku, invite.peer.displayName, invite.stake))
            }
        }
        gomoku.onAttention = { onTurnWhileHidden(GameWindowKind.Gomoku) }
        gomoku.spectatorFeaturesEnabled = config.spectator

        chess.presentWindow = { windows.present(GameWindowKind.Chess) }
        chess.dismissWindow = { windows.dismiss(GameWindowKind.Chess) }
        chess.requestAttention = { windows.requestAttention(GameWindowKind.Chess) }
        chess.onInviteArrived = { invite ->
            if (duels) {
                onInvite(GameWindowKind.Chess)
                onInviteArrival(DuelGame.CHESS, invite.id, invite.peer.displayName, invite.stake.toInt(), invite.expiresAt)
                onInviteNotice(DuelInviteNotice(GameWindowKind.Chess, invite.peer.displayName, invite.stake))
            }
        }
        chess.onAttention = { onTurnWhileHidden(GameWindowKind.Chess) }
        chess.spectatorFeaturesEnabled = config.spectator

        tetris.presentWindow = { windows.present(GameWindowKind.TetrisDuel) }
        tetris.dismissWindow = { windows.dismiss(GameWindowKind.TetrisDuel) }
        tetris.requestAttention = { windows.requestAttention(GameWindowKind.TetrisDuel) }
        tetris.onInviteArrived = { invite ->
            if (duels) {
                onInvite(GameWindowKind.TetrisDuel)
                onInviteArrival(DuelGame.TETRIS, invite.id, invite.peer.displayName, invite.stake, invite.expiresAt)
                onInviteNotice(DuelInviteNotice(GameWindowKind.TetrisDuel, invite.peer.displayName, invite.stake.toLong()))
            }
        }
        tetris.onAttention = { onTurnWhileHidden(GameWindowKind.TetrisDuel) }
        tetris.spectatorFeaturesEnabled = config.spectator
        tetris.rankingEnabled = true
    }

    /** 판 게임 창을 스토어를 거쳐 여는 문(맥 openWindow(focusMatchID) — 조회를 먼저 쏘고 presentWindow). */
    fun openers(gomoku: GomokuStore, chess: ChessStore, tetris: TetrisDuelStore): GamesWindowsHost.StoreWindowOpeners =
        object : GamesWindowsHost.StoreWindowOpeners {
            override fun gomoku(focusMatchID: String?): Boolean { gomoku.openWindow(focusMatchID); return true }
            override fun chess(focusMatchID: String?): Boolean { chess.openWindow(focusMatchID); return true }
            override fun tetrisDuel(focusMatchID: String?): Boolean { tetris.openWindow(focusMatchID); return true }
        }
}
