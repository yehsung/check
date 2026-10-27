// 원본: Sources/CheckCore/CheckCoreShared.swift:23-26(shortfallNotice) @ 1b8260d
package com.yehsung.aingcheck.core.rules.format

/** 상점 · 뽑기 · 확성기가 같이 쓰는 문구(CheckCoreShared 의 글자 몫 — 상수 몫은 foundation). */
object SharedText {
    /** 모자란 루비 한 줄. 필요·보유를 다 알고 필요가 클 때만 개수를 말한다. */
    fun shortfallNotice(need: Long?, have: Long?): String {
        if (need == null || have == null || need <= have) return "루비가 모자라요"
        return "루비 ${need - have}개 더 필요해요"
    }
}
