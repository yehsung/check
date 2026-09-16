#if os(iOS)
import CheckCore
import SwiftUI
import WidgetKit

/// 위젯 루트 화면(D1 골격). D8 에서 App Group 스냅샷을 읽는 위젯 3종으로 바꾼다.
public struct CheckWidgetsRootView: View {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("aing-check")
                .font(.headline)
                .foregroundStyle(CheckTheme.working)
            Text(date, style: .time)
                .font(.caption)
                .monospacedDigit()
        }
    }
}

/// 골격 타임라인: 지금 한 칸, 15분 뒤 다시(계획서 위젯 절 — 앱이 쓴 스냅샷을 15분 타임라인으로 그린다).
public struct CheckWidgetsPlaceholderEntry: TimelineEntry {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }
}

public struct CheckWidgetsPlaceholderProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> CheckWidgetsPlaceholderEntry {
        CheckWidgetsPlaceholderEntry(date: Date())
    }

    public func getSnapshot(in context: Context, completion: @escaping (CheckWidgetsPlaceholderEntry) -> Void) {
        completion(CheckWidgetsPlaceholderEntry(date: Date()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<CheckWidgetsPlaceholderEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [CheckWidgetsPlaceholderEntry(date: now)], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
#endif
