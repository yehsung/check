// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift:1-36(GamesWatcherCount) @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

/**
 * 관전자 수 한 칸의 **순수 판정·문구**(0.3.65 / 폰 1.0.13). 오목·체스·테트리스가 로비 줄·관전 화면·대국자 본인 화면에서 같은 것을 쓴다.
 *
 * ── 왜 화면 밖인가 ──
 * 판정을 화면(Compose) 안 삼항으로 묻어 두면 "0 인데 그렸다"·"라벨이 숫자만 읽힌다"를 **값으로 잴 자리가 없다**.
 * 그래서 그리는가([shows])·숫자([text])·접근성 라벨([accessibilityLabel])을 여기 세 함수로 떼어 두고, 화면은 이 셋을 배치만 한다.
 *
 * ── 규약(명세 §3 · 맥과 같다) ──
 *  · 눈 아이콘(`eye.fill` — Material Symbols 대응은 ui 의 SfSymbols 표) + 수. **0 이면 아무것도 그리지 않는다**.
 *  · 보이스오버(TalkBack)는 **"관전자 N명"**. 숫자만 읽으면 뜻이 없다.
 *  · 애니메이션 금지 — 2초 폴링마다 숫자가 튀면 눈에 거슬린다(값만 갈린다).
 *  · 서버가 아직 관전자 수를 모르는 창(`*_watch_live` 가 없어 접힌 길)에서는 코어가 0 을 주므로 **저절로** 안 그린다.
 */
object GamesWatcherCount {
    /** SF Symbol — 눈. 세 화면이 같은 기호를 쓴다. */
    const val symbol: String = "eye.fill"

    /** 이 수를 그리는가. INV-GamesComponents-f51fde29 이식: **0 이면 거짓**이고 음수(있을 수 없지만 서버가 흔들리면 온다)도 거짓이다. */
    fun shows(count: Int): Boolean = count > 0

    /** 눈 아이콘 옆 숫자(그리는 자리에서만 부른다). */
    fun text(count: Int): String = maxOf(0, count).toString()

    /** 접근성 라벨 — "관전자 N명". */
    fun accessibilityLabel(count: Int): String = "관전자 ${maxOf(0, count)}명"

    /** 글자 문구가 필요한 자리("N명이 보고 있어요"). 지금 폰에서 쓰는 자리는 없고 맥과 **같은 말**을 남겨 둔다. */
    fun watchingPhrase(count: Int): String = "${maxOf(0, count)}명이 보고 있어요"
}
