#if os(iOS) && DEBUG
import CheckMobileShared
import SwiftUI
import WidgetKit

/// 위젯 화면을 **위젯 밖에서** 그려 보는 목록(DEBUG 전용 — Release 에서 컴파일되지 않는다).
/// 검증 하네스가 `ImageRenderer` 로 PNG 를 뽑아 사람이 직접 본다(SPEC-ios-build §2 D8 위젯 검증).
/// 크기는 6.3인치 아이폰(402pt 폭)의 위젯 칸, 여백 16 · 모서리 22 는 홈 화면 위젯과 같게 그린다.
public struct AingWidgetPreviewItem: Identifiable {
    public let id: String
    public let size: CGSize
    public let view: AnyView
}

public enum AingWidgetPreviewCatalog {
    public static let smallSize = CGSize(width: 170, height: 170)
    public static let mediumSize = CGSize(width: 364, height: 170)
    public static let largeSize = CGSize(width: 364, height: 382)

    @MainActor
    public static func items(now: Date) -> [AingWidgetPreviewItem] {
        let sample = AingWidgetSamples.snapshot(now: now)
        var idle = sample
        idle.me = .init(working: false, sessionStartedAt: nil, todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40, status: .off)
        var lost = sample
        lost.me = .init(working: true, sessionStartedAt: nil, todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40, status: .disconnected)
        var empty = sample
        empty.working = []
        empty.todosPreview = []
        var many = sample
        many.working += (1...6).map { .init(name: "동료\($0)", center: "seoul", teammate: false, startedAt: nil) }
        many.todosPreview += (1...5).map {
            .init(id: String(format: "9E4F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2D%02d", $0), title: "추가 할 일 \($0) — 긴 제목이 한 줄에서 말줄임되는지 확인", isCompleted: false, carryOverDays: 0)
        }
        // 긴 별명(12자) — 2열 칸에서 경과 시간이 밀려나지 않고 이름이 먼저 줄어드는지.
        var longNames = sample
        longNames.working = [
            .init(name: "가나다라마바사아자차카타", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-7_500)),
            .init(name: "민트", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-3_000)),
            .init(name: "코랄", center: "busan", teammate: false, startedAt: nil),
        ]
        var noTeam = empty
        noTeam.me = WidgetSnapshot.Me(working: false, sessionStartedAt: nil, todaySeconds: 0, weekSeconds: 0, goalHours: 0)
        // AI 리밋: 연동 없음(받았는데 빈 목록) · 아직 못 받음(칸 자체가 없다 — 옛 스냅샷) · 리셋이 지난 낡은 값.
        var noProviders = sample
        noProviders.aiLimits = WidgetSnapshot.AILimitPanel(providers: [])
        var noLimits = sample
        noLimits.aiLimits = nil
        var staleLimits = sample
        staleLimits.aiLimits = WidgetSnapshot.AILimitPanel(
            providers: [
                // 두 시간 전 관측(맥이 자고 있었다) — 숫자가 하한이 되어 "72% 이상"으로 바뀌는지.
                // 리셋은 그 관측에서 5시간 안이어야 한다(더 멀면 규칙이 '그 창의 리셋이 아니다'로 보고 `—` 를 준다).
                .init(provider: "claude", fiveHourPercent: 72, fiveHourResetsAt: now.addingTimeInterval(3_600),
                      weeklyPercent: 88, weeklyResetsAt: now.addingTimeInterval(86_400), observedAt: now.addingTimeInterval(-7_200)),
                .init(provider: "codex", fiveHourPercent: 94, fiveHourResetsAt: now.addingTimeInterval(1_500),
                      weeklyPercent: 31, weeklyResetsAt: now.addingTimeInterval(200_000), observedAt: now.addingTimeInterval(-90)),
            ],
            todayTokens: 0,
            recentTokens: 254_000
        )
        let entry = AingWidgetEntry(date: now, snapshot: sample)
        let emptyEntry = AingWidgetEntry(date: now, snapshot: empty)
        let manyEntry = AingWidgetEntry(date: now, snapshot: many)
        let signedOut = AingWidgetEntry(date: now, snapshot: nil)
        return [
            item("working-small", smallSize, AingWorkingNowContent(entry: manyEntry, family: .systemSmall)),
            item("working-medium", mediumSize, AingWorkingNowContent(entry: entry, family: .systemMedium)),
            item("working-medium-long", mediumSize, AingWorkingNowContent(entry: AingWidgetEntry(date: now, snapshot: longNames), family: .systemMedium)),
            item("working-small-empty", smallSize, AingWorkingNowContent(entry: emptyEntry, family: .systemSmall)),
            item("working-medium-empty", mediumSize, AingWorkingNowContent(entry: emptyEntry, family: .systemMedium)),
            item("today-small-working", smallSize, AingMyTodayContent(entry: entry)),
            item("today-small-lost", smallSize, AingMyTodayContent(entry: AingWidgetEntry(date: now, snapshot: lost))),
            item("today-small-idle", smallSize, AingMyTodayContent(entry: AingWidgetEntry(date: now, snapshot: idle))),
            item("today-small-noteam", smallSize, AingMyTodayContent(entry: AingWidgetEntry(date: now, snapshot: noTeam))),
            item("todos-medium", mediumSize, AingTodoContent(entry: manyEntry, family: .systemMedium)),
            item("todos-large", largeSize, AingTodoContent(entry: entry, family: .systemLarge)),
            item("todos-medium-empty", mediumSize, AingTodoContent(entry: emptyEntry, family: .systemMedium)),
            item("todos-large-empty", largeSize, AingTodoContent(entry: emptyEntry, family: .systemLarge)),
            item("limits-small", smallSize, AingAILimitsContent(entry: entry, family: .systemSmall)),
            item("limits-medium", mediumSize, AingAILimitsContent(entry: entry, family: .systemMedium)),
            item("limits-large", largeSize, AingAILimitsContent(entry: entry, family: .systemLarge)),
            item("limits-small-stale", smallSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: staleLimits), family: .systemSmall)),
            item("limits-large-stale", largeSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: staleLimits), family: .systemLarge)),
            item("limits-medium-none", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: noProviders), family: .systemMedium)),
            item("limits-medium-nodata", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: noLimits), family: .systemMedium)),
            item("limits-medium-signedout", mediumSize, AingAILimitsContent(entry: signedOut, family: .systemMedium)),
            item("signed-out-small", smallSize, AingWorkingNowContent(entry: signedOut, family: .systemSmall)),
            item("signed-out-medium", mediumSize, AingTodoContent(entry: signedOut, family: .systemMedium)),
            item("signed-out-large", largeSize, AingTodoContent(entry: signedOut, family: .systemLarge)),
        ]
    }

    @MainActor
    private static func item(_ id: String, _ size: CGSize, _ content: some View) -> AingWidgetPreviewItem {
        AingWidgetPreviewItem(
            id: id,
            size: size,
            view: AnyView(
                content
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(16)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background(AingWidgetColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            )
        )
    }
}
#endif
