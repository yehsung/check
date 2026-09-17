#if os(iOS)
import AppIntents
import CheckCore
import CheckMobileShared
import SwiftUI
import WidgetKit

// 위젯 3종(SPEC-ios §4): 지금 근무 중(small·medium) · 내 오늘(small) · 오늘 할 일(medium·large).
// 확장 타깃(ios/Widgets)은 `AingCheckWidgetsBundle` 에서 이 세 `Widget` 만 나열한다.
// 그리는 값은 전부 `AingWidgetModel.swift`(플랫폼 무관 — 테스트 대상)에서 오고, 이 파일은 배치·색만 한다.

// MARK: - 타임라인

public struct AingWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    /// nil = 로그아웃(또는 앱이 아직 한 번도 안 씀) → "앱에서 로그인해 주세요".
    let snapshot: WidgetSnapshot?

    init(date: Date, snapshot: WidgetSnapshot?) {
        self.date = date
        self.snapshot = snapshot
    }
}

/// 세 위젯이 같은 공급자를 쓴다(읽는 파일이 하나다). 네트워크 없음 · 토큰 읽기 없음.
struct AingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AingWidgetEntry {
        let now = Date()
        return AingWidgetEntry(date: now, snapshot: AingWidgetSamples.snapshot(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (AingWidgetEntry) -> Void) {
        let now = Date()
        // 위젯 갤러리 미리보기는 지어낸 예시(실사용자 데이터가 갤러리에 뜨지 않게, 로그아웃이어도 모양을 보이게).
        let snapshot = context.isPreview ? AingWidgetSamples.snapshot(now: now) : WidgetSharedData.live().snapshot()
        completion(AingWidgetEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AingWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSharedData.live().snapshot()
        let entries = AingWidgetTimelinePlan.entryDates(now: now).map { AingWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(AingWidgetTimelinePlan.nextReload(now: now))))
    }
}

// MARK: - 위젯

public struct AingWorkingNowWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: AingWidgetKind.workingNow, provider: AingWidgetProvider()) { entry in
            AingWidgetContainer(entry: entry) { family in
                AingWorkingNowContent(entry: entry, family: family)
            }
        }
        .configurationDisplayName(AingWidgetText.workingGalleryName)
        .description(AingWidgetText.workingGalleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct AingMyTodayWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: AingWidgetKind.myToday, provider: AingWidgetProvider()) { entry in
            AingWidgetContainer(entry: entry) { _ in
                AingMyTodayContent(entry: entry)
            }
        }
        .configurationDisplayName(AingWidgetText.myTodayGalleryName)
        .description(AingWidgetText.myTodayGalleryDescription)
        .supportedFamilies([.systemSmall])
    }
}

public struct AingTodoWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: AingWidgetKind.todos, provider: AingWidgetProvider()) { entry in
            AingWidgetContainer(entry: entry) { family in
                AingTodoContent(entry: entry, family: family)
            }
        }
        .configurationDisplayName(AingWidgetText.todoGalleryName)
        .description(AingWidgetText.todoGalleryDescription)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// 공통 껍데기: 배경 · 탭하면 지금 탭 · 큰 글자 상한(위젯 칸은 고정 크기라 AX 크기에서는 줄이 잘린다 — xxLarge 까지 받는다).
struct AingWidgetContainer<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: AingWidgetEntry
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View {
        content(family)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(URL(string: "aingcheck://now"))
            .containerBackground(for: .widget) { AingWidgetColors.background }
    }
}

// MARK: - 인텐트

/// 위젯 할 일 체크(`Button(intent:)`). 위젯 확장 프로세스에서 돈다 — 본문은 `WidgetTodoToggle.run`(토큰 갱신 없음).
public struct ToggleTodoIntent: AppIntent {
    public static let title: LocalizedStringResource = "할 일 완료 표시"
    public static let isDiscoverable = false

    @Parameter(title: "할 일")
    public var todoID: String

    public init() {}

    public init(todoID: String) {
        self.todoID = todoID
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let service = SupabaseWorkService(anonKey: AingWidgetConfig.anonKey())
        _ = await WidgetTodoToggle.run(
            todoID: todoID,
            shared: WidgetSharedData.live(),
            now: { Date() },
            sync: { token, request in try await service.todoSync(accessToken: token, request: request) }
        )
        return .result()
    }
}

// MARK: - 색

enum AingWidgetColors {
    static let background = color(AingWidgetPalette.background)
    static let elevated = color(AingWidgetPalette.cardElevated)
    static let primary = color(AingWidgetPalette.primaryText)
    static let secondary = color(AingWidgetPalette.secondaryText)
    static let working = color(AingWidgetPalette.working)
    static let offWork = color(AingWidgetPalette.offWork)
    static let pending = color(AingWidgetPalette.pending)
    static let accent = color(AingWidgetPalette.accent)
    static let track = color(AingWidgetPalette.track)

    private static func color(_ pair: AingWidgetPalette.Pair) -> Color {
        let light = ui(pair.light), dark = ui(pair.dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        let c = AingWidgetPalette.components(hex)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

// MARK: - 공통 조각

struct AingWidgetSignedOut: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(AingWidgetColors.accent)
                .accessibilityHidden(true)
            Text(AingWidgetText.signedOut)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AingWidgetColors.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AingWidgetFooter: View {
    let leading: String?
    let generatedAt: Date
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let leading {
                Text(leading)
                    .foregroundStyle(AingWidgetColors.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(AingWidgetFormat.ago(from: generatedAt, now: now))
                .foregroundStyle(AingWidgetColors.secondary)
                .lineLimit(1)
        }
        .font(.caption2)
    }
}

struct AingWidgetHeader: View {
    let title: String
    let dot: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AingWidgetColors.secondary)
                .lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 지금 근무 중

struct AingWorkingNowContent: View {
    let entry: AingWidgetEntry
    let family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot {
            let limit = family == .systemSmall ? 3 : 6
            let working = AingWidgetWorking(snapshot.working, limit: limit)
            if family == .systemSmall {
                small(working, snapshot: snapshot)
            } else {
                medium(working, snapshot: snapshot)
            }
        } else {
            AingWidgetSignedOut()
        }
    }

    private func small(_ working: AingWidgetWorking, snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AingWidgetHeader(title: AingWidgetText.workingTitle, dot: AingWidgetColors.working)
            countText(working.total)
            if working.total == 0 {
                emptyText
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(working.shown.enumerated()), id: \.offset) { _, person in
                        nameRow(person)
                    }
                }
            }
            Spacer(minLength: 0)
            AingWidgetFooter(leading: moreText(working), generatedAt: snapshot.generatedAt, now: entry.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ working: AingWidgetWorking, snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    AingWidgetHeader(title: AingWidgetText.workingTitle, dot: AingWidgetColors.working)
                    countText(working.total)
                }
                .frame(width: 100, alignment: .leading)
                if working.total == 0 {
                    emptyText
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    // 이름 두 줄 칸(3행 × 2열) — 한 줄로 세우면 오른쪽 절반이 빈다(ImageRenderer 미리보기 실측).
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8, alignment: .leading), GridItem(.flexible(), spacing: 8, alignment: .leading)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(Array(working.shown.enumerated()), id: \.offset) { _, person in
                            nameRow(person)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            AingWidgetFooter(leading: moreText(working), generatedAt: snapshot.generatedAt, now: entry.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func countText(_ total: Int) -> some View {
        Text(AingWidgetText.people(total))
            .font(.system(.title, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(AingWidgetColors.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var emptyText: some View {
        Text(AingWidgetText.workingEmpty)
            .font(.caption)
            .foregroundStyle(AingWidgetColors.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func nameRow(_ person: WidgetSnapshot.WorkingPerson) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(person.teammate ? AingWidgetColors.working : AingWidgetColors.offWork)
                .frame(width: 6, height: 6)
            Text(person.name)
                .font(.footnote.weight(person.teammate ? .semibold : .regular))
                .foregroundStyle(AingWidgetColors.primary)
                .lineLimit(1)
            if person.teammate {
                Text(AingWidgetText.teammate)
                    .font(.caption2)
                    .foregroundStyle(AingWidgetColors.working)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(person.teammate ? "\(person.name), \(AingWidgetText.teammate)" : person.name))
    }

    private func moreText(_ working: AingWidgetWorking) -> String? {
        working.hiddenCount > 0 ? AingWidgetText.morePeople(working.hiddenCount) : nil
    }
}

// MARK: - 내 오늘

struct AingMyTodayContent: View {
    let entry: AingWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            if let me = snapshot.me {
                content(AingWidgetMe(me: me, generatedAt: snapshot.generatedAt, at: entry.date), snapshot: snapshot)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    AingWidgetHeader(title: AingWidgetText.today, dot: nil)
                    Text(AingWidgetText.noData)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AingWidgetColors.primary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            AingWidgetSignedOut()
        }
    }

    private func content(_ me: AingWidgetMe, snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            AingWidgetHeader(
                title: me.isWorking ? AingWidgetText.workingOnMac : AingWidgetText.notWorking,
                dot: me.isWorking ? AingWidgetColors.working : AingWidgetColors.offWork
            )
            Text(AingWidgetText.today)
                .font(.caption2)
                .foregroundStyle(AingWidgetColors.secondary)
                .padding(.top, 2)
            todayValue(me)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 8) {
                ring(me)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AingWidgetText.thisWeek)
                        .font(.caption2)
                        .foregroundStyle(AingWidgetColors.secondary)
                    Text(me.weekCaption)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AingWidgetColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date))
                        .font(.caption2)
                        .foregroundStyle(AingWidgetColors.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func todayValue(_ me: AingWidgetMe) -> some View {
        if let start = me.timerStart(at: entry.date) {
            Text(timerInterval: start...start.addingTimeInterval(7 * 86_400), countsDown: false)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AingWidgetColors.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text(AingWidgetFormat.hoursMinutes(me.todaySeconds))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AingWidgetColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func ring(_ me: AingWidgetMe) -> some View {
        ZStack {
            Circle().stroke(AingWidgetColors.track, lineWidth: 5)
            Circle()
                .trim(from: 0, to: me.progress)
                .stroke(me.isGoalComplete ? AingWidgetColors.working : AingWidgetColors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(me.percent)%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AingWidgetColors.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(4)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AingWidgetText.weekGoalSpoken(me.percent)))
    }
}

// MARK: - 오늘 할 일

struct AingTodoContent: View {
    let entry: AingWidgetEntry
    let family: WidgetFamily

    var body: some View {
        if let snapshot = entry.snapshot {
            let todos = AingWidgetTodos(snapshot.todosPreview, limit: family == .systemLarge ? 6 : 3)
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AingWidgetText.todoTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AingWidgetColors.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    if !todos.rows.isEmpty {
                        Text(AingWidgetText.todoRemaining(todos.remaining))
                            .font(.caption)
                            .foregroundStyle(AingWidgetColors.secondary)
                            .monospacedDigit()
                    }
                }
                if todos.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AingWidgetText.todoEmpty)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AingWidgetColors.primary)
                        Text(AingWidgetText.todoEmptyHint)
                            .font(.caption)
                            .foregroundStyle(AingWidgetColors.secondary)
                    }
                } else {
                    ForEach(todos.rows) { row in
                        todoRow(row)
                    }
                }
                Spacer(minLength: 0)
                AingWidgetFooter(
                    leading: todos.hiddenCount > 0 ? AingWidgetText.more(todos.hiddenCount) : nil,
                    generatedAt: snapshot.generatedAt,
                    now: entry.date
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            AingWidgetSignedOut()
        }
    }

    private func todoRow(_ row: WidgetSnapshot.TodoPreview) -> some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTodoIntent(todoID: row.id)) {
                Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(row.isCompleted ? AingWidgetColors.working : AingWidgetColors.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(row.isCompleted ? AingWidgetText.todoMarkUndone : AingWidgetText.todoMarkDone))
            .accessibilityValue(Text(row.title))
            Text(row.title)
                .font(.footnote)
                .strikethrough(row.isCompleted)
                .foregroundStyle(row.isCompleted ? AingWidgetColors.secondary : AingWidgetColors.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let badge = AingWidgetTodos.carryBadge(row) {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AingWidgetColors.pending)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - 예시 데이터(갤러리 미리보기 · 자리 표시)

/// 지어낸 예시(실사용자 이름 아님).
package enum AingWidgetSamples {
    package static func snapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-120),
            me: .init(working: true, sessionStartedAt: now.addingTimeInterval(-9_900), todaySeconds: 12_300, weekSeconds: 89_280, goalHours: 40),
            working: [
                .init(name: "민트", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-7_500)),
                .init(name: "라임", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-3_000)),
                .init(name: "코랄", center: "busan", teammate: false, startedAt: nil),
                .init(name: "하늘", center: nil, teammate: false, startedAt: nil),
                .init(name: "모래", center: "seoul", teammate: false, startedAt: nil),
            ],
            todosPreview: [
                .init(id: "5A0F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C11", title: "주간 회고 초안 쓰기", isCompleted: false, carryOverDays: 1),
                .init(id: "6B1F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C12", title: "디자인 리뷰 피드백 반영", isCompleted: false, carryOverDays: 0),
                .init(id: "7C2F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C13", title: "점심 전에 PR 올리기", isCompleted: true, carryOverDays: 0),
                .init(id: "8D3F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C14", title: "팀 회의 안건 정리", isCompleted: false, carryOverDays: 3),
            ]
        )
    }
}
#endif
