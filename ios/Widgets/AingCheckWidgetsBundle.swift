import CheckWidgetsKit
import SwiftUI
import WidgetKit

/// aing-check 위젯 확장 진입점. **껍데기만 둔다** — 위젯 화면·타임라인·체크 인텐트는 패키지 모듈(CheckWidgetsKit)에 있다.
/// 위젯 4종(SPEC-ios §4): 지금 근무 중(small·medium) · 내 오늘(small) · 오늘 할 일(medium·large, 체크는 `ToggleTodoIntent`) ·
/// AI 리밋(**medium 하나뿐** — v0.3.46 에서 small·large 를 지웠다. 근거는 `AingLimitsWidget.swift` 머리말).
@main
struct AingCheckWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AingWorkingNowWidget()
        AingMyTodayWidget()
        AingTodoWidget()
        AingAILimitsWidget()
    }
}
