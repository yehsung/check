#if os(iOS)
import AppIntents
import CheckCore
import CheckMobileShared
import SwiftUI
import WidgetKit

// 위젯 3종(SPEC-ios §4): 지금 근무 중(small·medium) · 내 오늘(small) · 오늘 할 일(medium·large).
// 확장 타깃(ios/Widgets)은 `AingCheckWidgetsBundle` 에서 이 세 `Widget` 만 나열한다.
// 그리는 값은 전부 `AingWidgetModel.swift`(플랫폼 무관 — 테스트 대상)에서 오고, 이 파일은 배치만 한다(부품·색은 `AingWidgetParts.swift`).
//
// w15 재디자인(시안 B 위젯 보드): 내 오늘 = 착용 캐릭터 초상(표정 = 상태) + 큰 타이머 + 이번 주 **막대**(틴트에서 꽉 찬 원으로 보이던 링 대신) ·
// 지금 근무 중 = 숫자 + 얼굴 더미(S) / 숫자 기둥 + 2×3 사람 칸(M) · 할 일 = 줄 전체 체크 버튼(M 34pt · L 46pt) + '앱에서 추가' ·
// 로그아웃 · 0명 · 할 일 없음 = 캐릭터 + 다음 행동. 루비는 넣지 않는다.

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

/// 공통 껍데기: 배경(흰색 / 남색 #232633 — 틴트·투명에서는 시스템이 걷어낸다) · 탭하면 지금 탭 · 큰 글자 상한
/// (위젯 칸은 고정 크기라 AX 크기에서는 줄이 잘린다 — xxLarge 까지 받는다).
struct AingWidgetContainer<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: AingWidgetEntry
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View {
        content(family)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .widgetURL(AingWidgetLinks.now)
            .containerBackground(for: .widget) { AingWidgetColors.background }
    }
}

enum AingWidgetLinks {
    static let now = URL(string: "aingcheck://now")!
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

// MARK: - 공통 조각

/// 머리 "● 지금 근무 중"(13 semibold · 2단 글자). 점 색이 뜻이다 — 아무도 없으면 청회색.
struct AingWidgetHead: View {
    let title: String
    let status: WidgetSnapshot.WorkState
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 5) {
            AingWidgetDot(status: status)
            Text(title)
                .aingFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(AingWidgetInk(renderingMode).secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 큰 숫자(34 bold · 고정폭 숫자) — "6명".
struct AingWidgetBigNumber: View {
    let text: String
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(text)
            .kerning(-0.8)
            .monospacedDigit()
            .aingFont(34, .bold, relativeTo: .largeTitle)
            .foregroundStyle(AingWidgetInk(renderingMode).primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// 11pt 2단 글자 한 줄(아래 줄 · 신선도).
struct AingWidgetCaption: View {
    let text: String
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(text)
            .monospacedDigit()
            .aingFont(11, relativeTo: .caption2)
            .foregroundStyle(AingWidgetInk(renderingMode).secondary)
            .lineLimit(1)
    }
}

/// 로그아웃: 캐릭터(시무룩 아잉) + 로그인 안내. S 는 세로로, M 은 가로로, L 은 크게 가운데. 경고 기호는 쓰지 않는다(오류처럼 읽혔다).
struct AingWidgetSignedOut: View {
    let family: WidgetFamily
    let hint: String?

    var body: some View {
        switch family {
        case .systemSmall:
            AingWidgetEmptyState(characterID: AingCharacterArt.defaultID, mood: .plain, expression: .negative, title: AingWidgetText.signedOut, hint: nil, layout: .stacked, portraitSize: 58)
        case .systemLarge:
            AingWidgetEmptyState(characterID: AingCharacterArt.defaultID, mood: .plain, expression: .negative, title: AingWidgetText.signedOut, hint: hint, layout: .stacked, portraitSize: 96)
        default:
            AingWidgetEmptyState(characterID: AingCharacterArt.defaultID, mood: .plain, expression: .negative, title: AingWidgetText.signedOut, hint: hint, layout: .row, portraitSize: 72)
        }
    }
}

// MARK: - 지금 근무 중

struct AingWorkingNowContent: View {
    let entry: AingWidgetEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let snapshot = entry.snapshot {
            if family == .systemSmall {
                small(AingWidgetWorking(snapshot.working, limit: AingWidgetLayout.workingSmallFaces), snapshot: snapshot)
            } else {
                medium(AingWidgetWorking(snapshot.working, limit: AingWidgetLayout.workingMediumCells), snapshot: snapshot)
            }
        } else {
            AingWidgetSignedOut(family: family, hint: AingWidgetText.signedOutWorkingHint)
        }
    }

    /// S: 머리 → 6명 → 얼굴 더미 → 이름 줄 → "우리 팀 3 · 외 3명 … 2분 전". 0명은 청회색 점 + 아잉 + 안내.
    private func small(_ working: AingWidgetWorking, snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return VStack(alignment: .leading, spacing: 0) {
            AingWidgetHead(title: AingWidgetText.workingTitle, status: working.total > 0 ? .working : .off)
            HStack(alignment: .center, spacing: 4) {
                AingWidgetBigNumber(text: AingWidgetText.people(working.total))
                Spacer(minLength: 0)
                if working.total == 0 {
                    AingWidgetPortrait(id: AingCharacterArt.defaultID, mood: .plain, size: 40)
                }
            }
            .padding(.top, 6)
            if working.total == 0 {
                Text(AingWidgetText.workingEmpty)
                    .aingFont(12, relativeTo: .caption)
                    .foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                // 158~170pt 칸은 기본 글자에서 딱 찬다 — 큰 글자(XL 이상)에서는 얼굴 더미를 접고 이름 줄을 남긴다(같은 정보, 글자가 잘리지 않게).
                if dynamicTypeSize < .xLarge {
                    AingWidgetFacepile(names: working.shown.map(\.name), size: 26)
                        .padding(.top, 8)
                }
                Text(working.namesLine)
                    .aingFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
            // 아래 줄: "우리 팀 3 · 외 3명 … 2분 전" — 둘이 한 줄에 안 들어가면(큰 글자) 사람 수를 남기고 신선도를 뺀다.
            ViewThatFits(in: .horizontal) {
                smallFooter(working, ago: AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date))
                smallFooter(working, ago: working.smallFooter == nil ? AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date) : nil)
            }
            .padding(.bottom, -4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallFooter(_ working: AingWidgetWorking, ago: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let footer = working.smallFooter {
                AingWidgetCaption(text: footer)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if let ago {
                AingWidgetCaption(text: ago)
                    .fixedSize()
            }
        }
    }

    /// M: 왼쪽 숫자 기둥(84pt) + 오른쪽 2×3 사람 칸(열 먼저 — 왼쪽 열이 우리 팀). 우리 팀은 경과 시간, 다른 팀은 센터.
    private func medium(_ working: AingWidgetWorking, snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                AingWidgetHead(title: AingWidgetText.workingShortTitle, status: working.total > 0 ? .working : .off)
                AingWidgetBigNumber(text: AingWidgetText.people(working.total))
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    if working.teammateCount > 0 {
                        Text(AingWidgetText.teammates(working.teammateCount))
                    }
                    if working.otherCount > 0 {
                        Text(AingWidgetText.otherTeams(working.otherCount))
                    }
                }
                .monospacedDigit()
                .aingFont(12, relativeTo: .caption)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .padding(.top, 4)
                Spacer(minLength: 0)
                AingWidgetCaption(text: AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date))
                    .padding(.bottom, -3)
            }
            .frame(width: AingWidgetLayout.workingMediumColumnWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Group {
                if working.total == 0 {
                    AingWidgetEmptyState(
                        characterID: AingCharacterArt.defaultID, mood: .plain, expression: nil,
                        title: AingWidgetText.workingEmptyTitle, hint: AingWidgetText.workingEmptyHint, layout: .row, portraitSize: 52
                    )
                } else {
                    grid(working)
                }
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle().fill(ink.separator).frame(width: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func grid(_ working: AingWidgetWorking) -> some View {
        let columns = working.columns(rows: AingWidgetLayout.workingMediumRows)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(0..<AingWidgetLayout.workingMediumColumns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<AingWidgetLayout.workingMediumRows, id: \.self) { row in
                        Group {
                            if column < columns.count, row < columns[column].count {
                                cell(columns[column][row])
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, -2)
    }

    private func cell(_ person: WidgetSnapshot.WorkingPerson) -> some View {
        let detail = AingWidgetWorking.detail(person, now: entry.date)
        // 이름이 먼저다: 이름 + 경과 시간(센터)이 칸에 다 들어가면 둘 다, 아니면 경과 시간을 빼고 이름만(긴 별명은 이름이 줄어든다).
        // 사이 틈 7 은 셋 사이에만 — Spacer 를 끼우면 틈이 두 번 더 붙어 90pt 칸에서 두 글자 이름이 "…"로 접혔다(실측).
        return ViewThatFits(in: .horizontal) {
            cellLine(person, detail: detail, keepsName: true)
            cellLine(person, detail: nil, keepsName: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AingWidgetText.joined([person.name, person.teammate ? AingWidgetText.teammate : nil, detail])))
    }

    /// `keepsName`: 경과 시간과 함께 설 때는 이름을 줄이지 않는다(재어 본 폭과 실제 배치가 1~2pt 어긋나 "…" 가 되던 것 — 큰 글자 실측).
    private func cellLine(_ person: WidgetSnapshot.WorkingPerson, detail: String?, keepsName: Bool) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(spacing: 7) {
            AingWidgetInitialAvatar(name: person.name, size: 24)
            Text(person.name)
                .kerning(-0.2)
                .aingFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .fixedSize(horizontal: keepsName, vertical: false)
            if let detail {
                Text(detail)
                    .monospacedDigit()
                    .aingFont(12, relativeTo: .caption)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 내 오늘

struct AingMyTodayContent: View {
    let entry: AingWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let snapshot = entry.snapshot {
            switch AingWidgetMyTodayState(snapshot: snapshot, at: entry.date) {
            case .me(let me):
                content(me, snapshot: snapshot)
            case .noTeam:
                message(AingWidgetText.noTeam, characterID: snapshot.resolvedCharacterID)
            case .noData:
                message(AingWidgetText.noData, characterID: snapshot.resolvedCharacterID)
            }
        } else {
            AingWidgetSignedOut(family: .systemSmall, hint: nil)
        }
    }

    private func message(_ text: String, characterID: String) -> some View {
        AingWidgetEmptyState(characterID: characterID, mood: .plain, expression: nil, title: text, hint: nil, layout: .stacked, portraitSize: 52)
    }

    /// 초상(표정 = 상태) + "근무 중 / 오늘 누적" → 가장 큰 타이머 → 이번 주 한 줄 + 막대.
    private func content(_ me: AingWidgetMe, snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AingWidgetPortrait(id: snapshot.resolvedCharacterID, mood: me.mood, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(me.stateTitle)
                        .aingFont(13, .bold, relativeTo: .footnote)
                        .foregroundStyle(ink.state(me.status))
                        .widgetAccentable()
                        .lineLimit(1)
                    Text(me.stateSubtitle(generatedAt: snapshot.generatedAt, now: entry.date))
                        .aingFont(11, relativeTo: .caption2)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                }
            }
            todayValue(me)
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                // "이번 주 24.8/40시간 … 62%" — 큰 글자에서 한 줄에 안 들어가면 "이번 주"를 떼고 숫자를 지킨다(말줄임 없음).
                ViewThatFits(in: .horizontal) {
                    weekRow(AingWidgetText.weekLine(me.weekCaption), percent: me.percent)
                    weekRow(me.weekCaption, percent: me.percent)
                }
                AingWidgetBar(progress: me.progress, isComplete: me.isGoalComplete, height: 5)
            }
            .padding(.bottom, 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AingWidgetText.weekGoalSpoken(me.percent)))
            .accessibilityValue(Text(AingWidgetText.weekLine(me.weekCaption)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func weekRow(_ caption: String, percent: Int) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(caption)
                .monospacedDigit()
                .aingFont(11, relativeTo: .caption2)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Text("\(percent)%")
                .monospacedDigit()
                .aingFont(11, .bold, relativeTo: .caption2)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// 세는 중이면 "5:10:00"(31), 멈춘 값이면 "5시간 10분"(24).
    @ViewBuilder
    private func todayValue(_ me: AingWidgetMe) -> some View {
        let ink = AingWidgetInk(renderingMode)
        if let start = me.timerStart(at: entry.date) {
            Text(timerInterval: start...start.addingTimeInterval(7 * 86_400), countsDown: false)
                .kerning(-1)
                .monospacedDigit()
                .aingFont(31, .bold, relativeTo: .title)
                .foregroundStyle(ink.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        } else {
            Text(AingWidgetFormat.hoursMinutes(me.todaySeconds))
                .kerning(-0.6)
                .monospacedDigit()
                .aingFont(24, .bold, relativeTo: .title2)
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 14)
        }
    }
}

// MARK: - 오늘 할 일

struct AingTodoContent: View {
    let entry: AingWidgetEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        if let snapshot = entry.snapshot {
            let todos = AingWidgetTodos(snapshot.todosPreview, limit: isLarge ? AingWidgetLayout.todoRowsLarge : AingWidgetLayout.todoRowsMedium)
            if isLarge {
                large(todos, snapshot: snapshot)
            } else if todos.rows.isEmpty {
                AingWidgetEmptyState(
                    characterID: AingCharacterArt.defaultID, mood: .plain, expression: nil,
                    title: AingWidgetText.todoEmpty, hint: AingWidgetText.todoEmptyHint, layout: .row, portraitSize: 72
                )
            } else {
                medium(todos)
            }
        } else {
            AingWidgetSignedOut(family: family, hint: AingWidgetText.signedOutTodoHint)
        }
    }

    /// M: "오늘 할 일 … 남은 4개 · 외 2개" + 34pt 줄 셋.
    private func medium(_ todos: AingWidgetTodos) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AingWidgetText.todoTitle)
                    .aingFont(15, .bold, relativeTo: .subheadline)
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text(todos.mediumTrailing)
                    .monospacedDigit()
                    .aingFont(12, relativeTo: .caption)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.bottom, 2)
            rows(todos)
            Spacer(minLength: 0)
        }
        .padding(.top, -2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// L: 제목 + "9월 17일 목 · 5개 중 1개 완료" + 남은 칩 → 46pt 줄 다섯 → "2분 전 … + 앱에서 추가".
    private func large(_ todos: AingWidgetTodos, snapshot: WidgetSnapshot) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AingWidgetText.todoTitle)
                        .aingFont(17, .bold, relativeTo: .headline)
                        .foregroundStyle(ink.primary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(todos.rows.isEmpty ? AingWidgetFormat.dayLabel(entry.date) : todos.largeSubtitle(at: entry.date))
                        .monospacedDigit()
                        .aingFont(12, relativeTo: .caption)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !todos.rows.isEmpty {
                    AingWidgetChip(text: AingWidgetText.todoRemaining(todos.remaining), height: 24, fontSize: 12)
                }
            }
            .padding(.bottom, 6)
            if todos.rows.isEmpty {
                AingWidgetEmptyState(
                    characterID: AingCharacterArt.defaultID, mood: .plain, expression: nil,
                    title: AingWidgetText.todoEmptyLarge, hint: nil, layout: .stacked, portraitSize: 96
                )
            } else {
                rows(todos)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AingWidgetCaption(text: todos.largeFooter(ago: AingWidgetFormat.ago(from: snapshot.generatedAt, now: entry.date)))
                Spacer(minLength: 4)
                Link(destination: AingWidgetLinks.now) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .aingFont(10, .bold, relativeTo: .caption2)
                        Text(AingWidgetText.todoAddInApp)
                            .aingFont(11, .semibold, relativeTo: .caption2)
                    }
                    .foregroundStyle(ink.accented ? Color.white : AingWidgetColors.accent)
                    .widgetAccentable()
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .padding(.bottom, -3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rows(_ todos: AingWidgetTodos) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(todos.rows.enumerated()), id: \.element.id) { index, row in
                todoRow(row)
                    .overlay(alignment: .topLeading) {
                        if index > 0 {
                            Rectangle()
                                .fill(AingWidgetInk(renderingMode).separator)
                                .frame(height: 0.5)
                                .padding(.leading, AingWidgetLayout.todoSeparatorInset)
                        }
                    }
            }
        }
    }

    /// 줄 전체가 체크 버튼이다 — 위젯에는 "눌러서 수정"이 없어 줄을 누를 다른 뜻이 없다(칸 밖은 `widgetURL` 로 앱을 연다).
    /// 이월 배지는 회색 칩(앰버 금지 — 이월은 경고가 아니다), 끝난 줄은 3단 글자 + 취소선.
    private func todoRow(_ row: WidgetSnapshot.TodoPreview) -> some View {
        let ink = AingWidgetInk(renderingMode)
        return Button(intent: ToggleTodoIntent(todoID: row.id)) {
            HStack(spacing: 10) {
                AingWidgetCheck(isDone: row.isCompleted)
                Text(row.title)
                    .strikethrough(row.isCompleted)
                    .aingFont(isLarge ? 15 : 14, relativeTo: .subheadline)
                    .foregroundStyle(row.isCompleted ? ink.tertiaryText : ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge = AingWidgetTodos.carryBadge(row) {
                    AingWidgetChip(text: badge)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isLarge ? AingWidgetLayout.todoRowHeightLarge : AingWidgetLayout.todoRowHeightMedium, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.isCompleted ? AingWidgetText.todoMarkUndone : AingWidgetText.todoMarkDone))
        .accessibilityValue(Text(row.title))
        .accessibilityAddTraits(.isButton)
    }
}

#endif
