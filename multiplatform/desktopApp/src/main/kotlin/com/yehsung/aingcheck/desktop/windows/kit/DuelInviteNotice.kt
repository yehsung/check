// 원본: Sources/check/CheckOverlayWindow.swift:1266-1274(오목) · :1422-1429(체스) · :1563-1569(테트리스) — 받은 신청 말풍선 글
// "<이름>님이 <게임> 대결을 신청했어요 · 루비 <판돈>". 맥은 캐릭터 말풍선 큐에 넣는다(CheckApp.swift:359·401·437 onInviteArrived);
// Windows 는 껍데기 알림 한 문(ShellNotifier — 말풍선/풍선/점 중재)으로 보낸다(int-w2 onInvite→알림).
package com.yehsung.aingcheck.desktop.windows.kit

/** 받은 대결 신청 한 건(알림에 실을 값만). 대결 깃발이 꺼진 빌드는 만들지 않는다(GameWindowWiring — W-3 #7). */
data class DuelInviteNotice(val kind: GameWindowKind, val peerName: String, val stake: Long) {
    /** 게임 이름(맥 말풍선 낱말). 미니게임 창은 신청이 없다. */
    val gameName: String
        get() = when (kind) {
            GameWindowKind.Gomoku -> "오목"
            GameWindowKind.Chess -> "체스"
            GameWindowKind.TetrisDuel -> "테트리스"
            else -> "게임"
        }

    /** 맥 full 문장 그대로(:1268 · :1424 · :1565). 이름이 비면 짧은 꼴(:1273 · :1428). */
    val body: String
        get() = if (peerName.isBlank()) "$gameName 대결 신청 · 루비 $stake" else "${peerName}님이 $gameName 대결을 신청했어요 · 루비 $stake"

    val title: String get() = "$gameName 대결 신청"
}
