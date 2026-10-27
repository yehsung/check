// 원본: Sources/CheckCore/GomokuStore.swift:50-65(GomokuEndReason · GomokuOutcome) · :321-338(GomokuTapRefusal) @ 1b8260d
package com.yehsung.aingcheck.core.rules.renju

// 판 결과·끝난 사유·탭 거절 — Swift 에서는 스토어 파일(GomokuStore.swift, W2-d)에 선언돼 있지만 **AI 판 규칙(GomokuAIGame, C§3.2 A-5)이
// 이 셋을 쓴다**. 의존 방향이 rules ← stores 한쪽뿐이라(C§3.1) 셋을 rules 에 두고, 스토어 갈래(W2-d)는 여기 것을 그대로 쓴다
// (같은 이름을 stores 에 다시 만들지 않는다 — 두 벌이면 AI 판과 서버 판이 다른 열거를 들게 된다). 조정자 보고 거리.
// 케이스 순서 · rawValue(서버·로그 어휘) · rawValue 읽기는 골든 `renju/inputs`(endReasonCases · outcomeCases · tapRefusalCases · enumRawValue)가 잰다.

/** 판이 끝난 사유. [rawValue] 는 서버 어휘. */
enum class GomokuEndReason(val rawValue: String) {
    five("five"),
    /** **옛 어휘**(0.3.27: 시간 초과 = 즉시 패배). 옛 판 기록에 남아 있고 배포 중간 창의 옛 서버가 보낸다 — 지우지 마라. */
    timeout("timeout"),
    resign("resign"),
    boardFull("board_full"),
    /** 0.3.28 — 자동 착수가 **연속 3번** 놓여 끝난 판(자리 비움 패배). */
    abandoned("abandoned");

    companion object {
        fun fromRawValue(raw: String): GomokuEndReason? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** **사람(나) 기준** 결과. */
enum class GomokuOutcome { won, lost, draw }

/**
 * 탭(착수) 거절 사유. [rawValue] 는 **로그 어휘**다 — 사람 이름·판 내용과 무관한 고정 문자열.
 * 0.3.27 까지 네 가지 거절이 전부 무음이었고, 사용자가 돌을 못 놓아 판돈을 잃었는데 사유를 하나도 말해 주지 않았다 — 그래서 갈래를 가른다.
 */
enum class GomokuTapRefusal(val rawValue: String) {
    /** 상대 차례다. */
    notYourTurn("not-your-turn"),
    /** 앞 착수·기권이 아직 왕복 중이라 잠겨 있다. */
    busy("busy"),
    /** 이미 돌이 있는 자리다. */
    occupied("occupied"),
    /** 판이 끝났다. */
    finished("finished"),
    /** 로그인이 풀렸다. */
    signedOut("signed-out"),
    /** 들고 있는 판이 없다. **말하지 않는다**(로그만 남는다). */
    noMatch("no-match"),
    /** 흑 금수다. 사유는 따로 싣는다. */
    forbidden("forbidden");

    companion object {
        fun fromRawValue(raw: String): GomokuTapRefusal? = entries.firstOrNull { it.rawValue == raw }
    }
}
