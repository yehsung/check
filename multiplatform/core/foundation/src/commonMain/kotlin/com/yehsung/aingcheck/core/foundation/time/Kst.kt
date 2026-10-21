// 원본: Sources/CheckCore/WeeklyWorkReward.swift:247-264(KST 주 경계) · MilestoneTracker(KST 달력) @ a63fea2
package com.yehsung.aingcheck.core.foundation.time

import kotlinx.datetime.TimeZone

/**
 * 한국 표준시. 주간 보상(월 0시 KST)·9시 경계·잔디의 날짜 계산은 이 시간대 하나로 한다.
 * 기기 시간대(`TimeZone.currentSystemDefault()`)로 계산하지 않는다 — 해외에 있는 사람도 같은 숫자를 봐야 한다.
 */
val KST: TimeZone = TimeZone.of("Asia/Seoul")
