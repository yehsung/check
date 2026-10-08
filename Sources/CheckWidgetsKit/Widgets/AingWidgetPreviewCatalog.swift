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
        // AI 리밋: 연동 없음(받았는데 빈 목록) · 아직 못 받음(칸 자체가 없다 — 옛 스냅샷) · 리셋이 지난 낡은 값 ·
        // ★ 제공자 **하나뿐**(아래가 비지 않는지 — 라지를 지운 이유가 그것이었다).
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
        // 제공자 하나(5시간 창이 **없는** 계정 — `없음` 칸과 빈 자리를 같이 본다).
        var oneProvider = sample
        oneProvider.aiLimits = WidgetSnapshot.AILimitPanel(
            providers: [
                .init(provider: "antigravity", fiveHourPercent: nil, fiveHourResetsAt: nil,
                      weeklyPercent: 8, weeklyResetsAt: now.addingTimeInterval(500_000), observedAt: now.addingTimeInterval(-120)),
            ],
            todayTokens: 25_950_000,
            recentTokens: 2_410_000_000
        )
        // ★ 맥 **두 대 이상**인 사람의 위젯(v0.3.47): 메인 맥 하나만 그리고 머리에 그 맥 이름이 붙는다.
        //   이름이 겹쳐 꼬리까지 달린 **가장 넓은 현실 문구**를 넣어, 머리 줄에서 나이 글자를 밀어내지 않는지 본다.
        var mainMac = sample
        mainMac.aiLimits?.deviceName = "예성의 MacBook Pro (A1B2)"
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
            // AI 리밋은 **미디움 하나뿐**이다(v0.3.46 — 스몰·라지를 지웠다). 좁은 기기 칸(329×155)도 같이 굽는다:
            // 줄 높이가 마크를 깎는 갈래가 그 폭에서만 드러난다.
            item("limits-medium", mediumSize, AingAILimitsContent(entry: entry)),
            item("limits-medium-narrow", CGSize(width: 329, height: 155), AingAILimitsContent(entry: entry)),
            // 맥 두 대 이상(머리에 맥 이름) — 기준 칸과 **가장 좁은 칸** 둘 다 굽는다: 이름이 들어갈 자리가
            // 모자라면 좁은 칸에서만 드러난다(실측 194.4pt).
            item("limits-medium-device", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: mainMac))),
            item("limits-medium-device-narrow", CGSize(width: 329, height: 155),
                 AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: mainMac))),
            item("limits-medium-stale", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: staleLimits))),
            item("limits-medium-one", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: oneProvider))),
            item("limits-medium-none", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: noProviders))),
            item("limits-medium-nodata", mediumSize, AingAILimitsContent(entry: AingWidgetEntry(date: now, snapshot: noLimits))),
            item("limits-medium-signedout", mediumSize, AingAILimitsContent(entry: signedOut)),
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
