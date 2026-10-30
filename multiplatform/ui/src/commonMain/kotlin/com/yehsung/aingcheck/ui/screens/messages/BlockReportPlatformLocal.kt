// 원본: Sources/check/WorkTimerStoreBlocks.swift:125-126 (맥 `WorkTimerStore.blockReportPlatform = .mac` — 설정 창·팝오버의 길 안내 "설정 → 차단한 사람")
//       · Sources/check/CheckBlockReportViews.swift:220·276·404·505·553 (맥 화면이 그 갈래로 문구를 읽는 다섯 자리)
//       · Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift (폰은 `.phone` — "나 → 설정 → 차단한 사람")
//
// 차단 문구의 플랫폼 갈래(공용 패치 20). ui commonMain 의 차단 화면 셋(메시지 차단 확인 · 대국 채팅 차단 확인 · 차단한 사람)은
// 이 값을 읽는다 — 호출 자리에 판을 박지 않는다(기본값은 아래 선언 한 곳). 기본값은 폰: Android 는 아무것도 제공하지 않아 문구가 그대로다.
// Windows(desktopApp)는 `.mac` 을 **Compose 뿌리마다** 제공한다. `ComposeWindow().setContent { }`·`ComposePanel.setContent { }` 로
// 따로 세운 창은 다른 컴포지션이라 제공이 건너가지 않는다 — 플라이아웃만 감싸면 게임 창(별도 Window)의 차단 시트가 폰 문구로 남는다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.runtime.staticCompositionLocalOf
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform

/**
 * 차단·신고 길 안내 문구의 판. 제공이 없으면 폰("나 → 설정 → 차단한 사람"), Windows 는 `.mac`("설정 → 차단한 사람" + 콕·울트라 확인 항목).
 * 앱이 사는 동안 바뀌지 않는 값이라 static 이다(바꾸면 아래 전체를 다시 그린다).
 */
val LocalBlockReportPlatform = staticCompositionLocalOf { BlockReportPlatform.phone }
