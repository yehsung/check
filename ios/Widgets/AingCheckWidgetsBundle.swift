import CheckWidgetsKit
import SwiftUI
import WidgetKit

/// aing-check 위젯 확장 진입점. **껍데기만 둔다** — 위젯 화면과 타임라인은 패키지 모듈(CheckWidgetsKit)에 있다.
/// D8 에서 위젯 3종(지금 근무 중 · 내 오늘과 목표 · 오늘 할 일)으로 채운다.
@main
struct AingCheckWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AingCheckPlaceholderWidget()
    }
}

/// 골격 확인용 위젯 하나. App Group 스냅샷을 읽는 실제 타임라인은 D8 몫이다.
struct AingCheckPlaceholderWidget: Widget {
    let kind = "AingCheckPlaceholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CheckWidgetsPlaceholderProvider()) { entry in
            CheckWidgetsRootView(date: entry.date)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("aing-check")
        .description("골격 위젯")
        .supportedFamilies([.systemSmall])
    }
}
