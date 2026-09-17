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
        idle.me = .init(working: false, sessionStartedAt: nil, todaySeconds: 4_020, weekSeconds: 146_000, goalHours: 40)
        idle.working = []
        idle.todosPreview = []
        var many = sample
        many.working += (1...6).map { .init(name: "동료\($0)", center: "seoul", teammate: false, startedAt: nil) }
        many.todosPreview += (1...5).map {
            .init(id: String(format: "9E4F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C%02d", $0), title: "추가 할 일 \($0) — 긴 제목이 한 줄에서 말줄임되는지 확인", isCompleted: false, carryOverDays: 0)
        }
        // 긴 별명(12자) 우리 팀원 — 2열 칸에서 "우리 팀" 라벨이 말줄임표만 남지 않는지.
        var longNames = sample
        longNames.working = [
            .init(name: "가나다라마바사아자차카타", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-7_500)),
            .init(name: "민트", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-3_000)),
            .init(name: "코랄", center: "busan", teammate: false, startedAt: nil),
        ]
        var noTeam = idle
        noTeam.me = WidgetSnapshot.Me(working: false, sessionStartedAt: nil, todaySeconds: 0, weekSeconds: 0, goalHours: 0)
        let entry = AingWidgetEntry(date: now, snapshot: sample)
        let idleEntry = AingWidgetEntry(date: now, snapshot: idle)
        let manyEntry = AingWidgetEntry(date: now, snapshot: many)
        let signedOut = AingWidgetEntry(date: now, snapshot: nil)
        return [
            item("working-small", smallSize, AingWorkingNowContent(entry: entry, family: .systemSmall)),
            item("working-medium", mediumSize, AingWorkingNowContent(entry: manyEntry, family: .systemMedium)),
            item("working-medium-long", mediumSize, AingWorkingNowContent(entry: AingWidgetEntry(date: now, snapshot: longNames), family: .systemMedium)),
            item("working-small-empty", smallSize, AingWorkingNowContent(entry: idleEntry, family: .systemSmall)),
            item("today-small-working", smallSize, AingMyTodayContent(entry: entry)),
            item("today-small-idle", smallSize, AingMyTodayContent(entry: idleEntry)),
            item("today-small-noteam", smallSize, AingMyTodayContent(entry: AingWidgetEntry(date: now, snapshot: noTeam))),
            item("todos-medium", mediumSize, AingTodoContent(entry: entry, family: .systemMedium)),
            item("todos-large", largeSize, AingTodoContent(entry: manyEntry, family: .systemLarge)),
            item("todos-medium-empty", mediumSize, AingTodoContent(entry: idleEntry, family: .systemMedium)),
            item("signed-out-small", smallSize, AingWorkingNowContent(entry: signedOut, family: .systemSmall)),
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
